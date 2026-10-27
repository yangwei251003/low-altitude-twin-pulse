class_name CombatV2
extends Node3D

signal warning_seen
signal enemy_down(role: String)
signal shot_fired(friendly: bool)
signal combat_event(event: Dictionary)

const MAX_BOLTS = 128
const DamageModel = preload("res://scripts/v2/damage_model.gd")
const EnemyBrain = preload("res://scripts/v2/enemy_brain.gd")
var pilot: FlightBodyV2
var target_visibility: Callable
var perception_visibility: Callable
var environment_query: Callable
var navigation_world: Node3D
var unit_sequence = 0
var combat_seed = 10415
var enemies: Array[CharacterBody3D] = []
var facility: Node3D
var shoot_clock = 0.0
var kills = 0
var auto_fire = true
var overheat = false
var difficulty = 0
var charge = 0.0
var aim_status = "idle"
var aim_direction = Vector3.FORWARD
var target_nodes: Array[StaticBody3D] = []
var boss_phase = 0
var exposure_window_s = 4.0
var objective_clock = 0.0
var safe_window_s = 4.0
var objective_center = Vector3.ZERO
var boss_spawned = false
var objective_bosses: Array[CharacterBody3D] = []
var bolts: Array[Node3D] = []
var _charge_target: CollisionObject3D
var _safe_ring: MeshInstance3D
var _sweep_beam: MeshInstance3D
var _last_sweep_state = 0
var _sweep_hit = false
var _bolt_meshes: Dictionary = {}
var events: Array[Dictionary] = []
var _event_serial = 0
var _warning_serial = 0
var _warning_gap = 0.0
var _weapon_mount: Node3D
var _weapon_rest=Vector3.ZERO
var _weapon_recoil=0.0

func _physics_process(delta: float) -> void:
	_weapon_recoil=move_toward(_weapon_recoil,0,delta*.65)
	if is_instance_valid(_weapon_mount):_weapon_mount.position=_weapon_rest+_weapon_mount.basis.z*_weapon_recoil
	if not is_instance_valid(pilot) or not pilot.enabled:
		_cancel_charge()
		return
	_update_objective(delta)
	_warning_gap = maxf(0.0, _warning_gap - delta)
	var mods: Dictionary = pilot.stats.get("modifiers", {})
	if bool(pilot.sandbox_rules.get("no_overheat",false)):
		pilot.heat = 0.0
		overheat = false
	pilot.heat = maxf(0.0, pilot.heat - delta * float(mods.get("cooling_multiplier", 1.0)) * float(mods.get("heat_dissipation_ps", 16.0)))
	if pilot.heat < pilot.max_heat * 0.4 and overheat:
		overheat = false
		_record("recovered", pilot, pilot, pilot.global_position)
	shoot_clock = maxf(0.0, shoot_clock - delta)
	if not bool(pilot.command.get("active", true)) or (not auto_fire and not bool(pilot.command.get("fire", false))):
		_cancel_charge()
		aim_status = "idle"
		return
	if overheat or shoot_clock > 0.0:
		_cancel_charge()
		aim_status = "overheat" if overheat else "cooldown"
		return
	var target = nearest_target(36.0)
	if target == null:
		_cancel_charge()
		aim_status = "no_visible_target"
		return
	var aim = target.global_position
	if target is CharacterBody3D: aim += target.velocity * 0.12
	if not line_clear(pilot.global_position, aim, pilot.get_rid(), target.get_rid()):
		_cancel_charge()
		aim_status = "blocked"
		return
	if _charge_target != target: charge = 0.0
	_charge_target = target
	aim_direction = (aim - pilot.global_position).normalized()
	if not is_instance_valid(_weapon_mount) and is_instance_valid(pilot.model):
		_weapon_mount = pilot.model.get_node_or_null("Attachment_weapon")
		if is_instance_valid(_weapon_mount):_weapon_rest=_weapon_mount.position
	if is_instance_valid(_weapon_mount) and absf(aim_direction.dot(Vector3.UP)) < 0.99: _weapon_mount.look_at(_weapon_mount.global_position + aim_direction, Vector3.UP)
	charge += delta
	aim_status = "charging"
	if charge + 0.00001 < maxf(0.0, float(mods.get("weapon_charge_s", 0.0))): return
	var boost = float(mods.get("burst_window_damage_multiplier", 1.3)) if pilot.build.get("airframe_id") == "at06" and pilot.ability_left > 0.0 else 1.0
	if not fire_bolt(pilot.global_position, aim, float(mods.get("weapon_damage", 10.0)) * boost, true, pilot): return
	pilot.heat = 0.0 if bool(pilot.sandbox_rules.get("no_overheat",false)) else minf(pilot.max_heat, pilot.heat + maxf(0.0, float(mods.get("weapon_heat", 8.0))))
	shoot_clock = maxf(0.02, float(mods.get("weapon_interval_s", 0.28)))
	_cancel_charge()
	aim_status = "firing"
	if pilot.heat >= pilot.max_heat:
		overheat = true
		_record("overheated", pilot, pilot, pilot.global_position)

func _record(kind: String, source: Node, target: Node, point: Vector3, damage: float = 0.0, heat_delta: float = 0.0, warning_id: int = 0, hit_result: String = "", extra: Dictionary={}) -> Dictionary:
	_event_serial += 1
	var weapon_id = str(pilot.build.get("slots", {}).get("weapon", "")) if source == pilot else str(source.role) if source is Foe else "environment"
	var event = {"event_id":_event_serial,"tick":Engine.get_physics_frames(),"source_id":str(source.get_instance_id()) if is_instance_valid(source) else "","target_id":str(target.get_instance_id()) if is_instance_valid(target) else "","kind":kind,"position":[point.x,point.y,point.z],"damage":damage,"heat_delta":heat_delta,"warning_id":warning_id,"hit_result":hit_result,"weapon_id":weapon_id}
	if is_instance_valid(source):event.source_id=str(source.get_meta("unit_id",event.source_id))
	if is_instance_valid(target):event.target_id=str(target.get_meta("unit_id",event.target_id))
	event["friendly"]=source==pilot
	event["pilot_target"]=target==pilot
	if source is Node3D:event["source_position"]=[source.global_position.x,source.global_position.y,source.global_position.z]
	if target is Node3D:event["target_position"]=[target.global_position.x,target.global_position.y,target.global_position.z]
	if target is Foe:event["role"]=target.role
	elif source is Foe:event["role"]=source.role
	event.merge(extra,true)
	events.append(event)
	if events.size() > 256: events.pop_front()
	combat_event.emit(event.duplicate(true))
	return event

func settle_hit(source: Node, target: Node, point: Vector3, direction: Vector3, amount: float, weapon_type="pulse", warning_id=0) -> Dictionary:
	if not is_instance_valid(target) or not is_finite(amount) or amount<=0:return {}
	var receipt:Dictionary={}
	if target.has_method("apply_combat_hit"):
		receipt=target.apply_combat_hit(amount,direction,point,weapon_type,{"combat":true})
	elif target.has_method("take_damage"):
		var before=float(target.get("hp"))
		target.take_damage(amount,direction)
		var after=maxf(0,float(target.get("hp")))
		receipt={"damage":maxf(0,before-after),"health_before":before,"health":after,"max_health":before,"armor_absorbed":0.0,"shield_absorbed":0.0,"component":"hull","component_damage":0.0,"killed":before>0 and after<=0,"hit_result":"hit"}
	if receipt.is_empty():
		_record("impact",source,target,point,0,0,warning_id,"blocked",{"direction":[direction.x,direction.y,direction.z],"surface":surface_at(target,point)})
		return {}
	receipt["direction"]=[direction.x,direction.y,direction.z]
	receipt["surface"]="metal"
	receipt["receipt_id"]="%s:%d:%d"%[str(target.get_meta("unit_id",target.get_instance_id())),Engine.get_physics_frames(),_event_serial+1]
	var kind="shield_absorbed" if float(receipt.get("damage",0))<=0 and float(receipt.get("shield_absorbed",0))>0 else "hit"
	_record(kind,source,target,point,float(receipt.damage),0,warning_id,str(receipt.get("hit_result","hit")),receipt)
	if target is Foe:
		if is_instance_valid(source) and source is Node3D:target.brain.note_damage(source.global_position)
		if bool(receipt.get("killed",false)):target.finish_destroyed(source,receipt)
	elif target is PowerNode and bool(receipt.get("killed",false)):target.finish_destroyed(source,receipt)
	return receipt

func surface_at(target: Node, point: Vector3) -> String:
	if is_instance_valid(target) and target.has_meta("surface"):return str(target.get_meta("surface"))
	if environment_query.is_valid():
		var sample:Dictionary=environment_query.call(point)
		if bool(sample.get("water",false)) and point.y<=float(sample.get("water_height",-.6))+.25:return "water"
	if target is Foe or target==pilot or target is PowerNode:return "metal"
	return "ground"

func nearby_threats(radius: float=32.0) -> int:
	if not is_instance_valid(pilot):return 0
	var count=0
	for foe in enemies:
		if not is_instance_valid(foe) or foe.hp<=0:continue
		if foe.global_position.distance_to(pilot.global_position)>radius:continue
		if foe.telegraph>0 or foe.charge_left>0 or (foe.brain.seen and foe.brain.state in ["notice","pursue","flank"]):count+=1
	return count

func request_warning(attacker: Foe, target: CollisionObject3D) -> int:
	# Dark encounters approach the observable area before starting an attack.
	if target == pilot and target_visibility.is_valid() and not target_visibility.call(attacker.global_position):return 0
	if _warning_gap > 0.0: return 0
	var threats = 0
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy != attacker and (enemy.telegraph > 0.0 or enemy.charge_left > 0.0): threats += 1
	var limit = 1 if difficulty == 0 or attacker.role == "boss" else 2
	if threats >= limit: return 0
	_warning_gap = 0.65 if difficulty == 0 else 0.4
	_warning_serial += 1
	_record("warning_started", attacker, target, attacker.global_position, 0.0, 0.0, _warning_serial)
	warning_seen.emit()
	return _warning_serial

func _cancel_charge() -> void:
	charge = 0.0
	_charge_target = null

func nearest_target(radius: float) -> CollisionObject3D:
	if not is_instance_valid(pilot): return null
	var nearest: CollisionObject3D
	var distance_m = radius
	var candidates: Array = enemies + target_nodes
	for candidate in candidates:
		if not is_instance_valid(candidate) or candidate.is_queued_for_deletion() or candidate.hp <= 0.0: continue
		if target_visibility.is_valid() and not target_visibility.call(candidate.global_position):continue
		if candidate is Foe and not candidate.can_take_damage(): continue
		var d: float = candidate.global_position.distance_to(pilot.global_position)
		if d < distance_m and line_clear(pilot.global_position, candidate.global_position, pilot.get_rid(), candidate.get_rid()):
			nearest = candidate
			distance_m = d
	return nearest

func line_clear(from: Vector3, to: Vector3, source: RID, target: RID) -> bool:
	if not from.is_finite() or not to.is_finite(): return false
	var ray = PhysicsRayQueryParameters3D.create(from, to, 1 | 2 | 4 | 8 | 32)
	if source.is_valid(): ray.exclude = [source]
	var hit = get_world_3d().direct_space_state.intersect_ray(ray)
	return hit.is_empty() or hit.rid == target

func spawn_wave(roles: Array, center: Vector3) -> void:
	for i in range(roles.size()):
		var enemy = Foe.new()
		enemy.role = str(roles[i]) if str(roles[i]) in ["shooter", "charger", "support", "boss", "scout", "harasser", "suppressor"] else "shooter"
		enemy.combat = self
		unit_sequence+=1
		enemy.set_meta("unit_id","mission:%d:%d"%[combat_seed,unit_sequence])
		enemy.set_meta("source_kind","mission")
		enemy.set_meta("allow_facility_target",true)
		var angle = i * TAU / maxi(1, roles.size()) + 0.5
		enemy.position = to_local(_free_spawn(center + Vector3(cos(angle) * 15.0, 4.0 + i * 0.65, sin(angle) * 15.0)))
		add_child(enemy)
		enemy.home = enemy.global_position
		enemies.append(enemy)
		if enemy.role == "boss":
			boss_spawned = true
			objective_bosses.append(enemy)

func spawn_patrol(roles: Array, entry: Vector3, patrol_target: Vector3) -> Array:
	var spawned:Array=[]
	if not entry.is_finite() or not patrol_target.is_finite():return spawned
	for i in mini(roles.size(),4):
		var point=entry+Vector3(i*2.3,0,0)
		var sphere=SphereShape3D.new();sphere.radius=1.2
		var query=PhysicsShapeQueryParameters3D.new();query.shape=sphere
		query.transform=Transform3D(Basis.IDENTITY,point);query.collision_mask=1|2|4|8|32
		if not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():continue
		var actor=Foe.new();actor.role=str(roles[i]);actor.combat=self
		unit_sequence+=1
		actor.set_meta("unit_id","patrol:%d:%d"%[combat_seed,unit_sequence])
		actor.set_meta("source_kind","ambient");actor.set_meta("ambient_patrol",true)
		actor.set_meta("allow_facility_target",false)
		actor.position=to_local(point)
		var direction=patrol_target-point
		actor.rotation.y=atan2(-direction.x,-direction.z)
		add_child(actor);actor.home=point;actor.brain.set_patrol_target(patrol_target)
		enemies.append(actor);spawned.append(actor)
	return spawned

func _free_spawn(requested: Vector3) -> Vector3:
	var query = PhysicsShapeQueryParameters3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = 1.15
	query.shape = sphere
	query.collision_mask = 1 | 2 | 4 | 8 | 32
	for step in range(16):
		var candidate = requested + Vector3(0.0, float(step) * 1.2, 0.0)
		query.transform = Transform3D(Basis.IDENTITY, candidate)
		if get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(): return candidate
	return requested + Vector3.UP * 20.0

func alive_count() -> int:
	var count = 0
	for foe in enemies:
		if is_instance_valid(foe) and foe.hp > 0: count += 1
	return count

func clear_enemies(include_ambient: bool=false) -> void:
	for enemy in enemies:
		if is_instance_valid(enemy) and (include_ambient or str(enemy.get_meta("source_kind","mission")) not in ["ambient","reinforcement"]): enemy.queue_free()
	enemies=enemies.filter(func(enemy):return is_instance_valid(enemy) and not enemy.is_queued_for_deletion())
	for bolt in bolts:
		if is_instance_valid(bolt): bolt.deactivate()
	configure_objective({}, Vector3.ZERO)
	facility = null
	shoot_clock = 0.0
	_warning_gap = 0.0
	_cancel_charge()

func configure_objective(action: Dictionary, center: Vector3) -> void:
	for node in target_nodes:
		if is_instance_valid(node): node.queue_free()
	target_nodes.clear()
	if is_instance_valid(_safe_ring): _safe_ring.queue_free()
	if is_instance_valid(_sweep_beam): _sweep_beam.queue_free()
	_safe_ring = null
	_sweep_beam = null
	objective_bosses.clear()
	boss_spawned = false
	boss_phase = int(action.get("boss_phase", 0))
	exposure_window_s = maxf(4.0, float(action.get("exposure_window_s", 4.0)))
	safe_window_s = maxf(4.0, float(action.get("safe_window_s", 4.0)))
	objective_clock = 0.0
	objective_center = center
	_last_sweep_state = 0
	_sweep_hit = false
	if boss_phase != 2: spawn_objective_nodes(clampi(int(action.get("target_nodes", 0)), 0, 12), center)
	if boss_phase == 2:
		_safe_ring = GameVisuals.ring(self, to_local(center + Vector3.UP * 0.2), 11.0, Color("42c7b2"), 0.1)
		_sweep_beam = GameVisuals.box(self, to_local(center), Vector3(24.0, 0.10, 0.16), Color("ffb05b"))
		_sweep_beam.visible = false
	_cancel_charge()

func spawn_objective_nodes(count: int, center: Vector3) -> void:
	for i in range(clampi(count, 0, 12)):
		var node = PowerNode.new()
		node.combat = self
		var angle = TAU * i / maxi(1, count)
		node.position = to_local(_free_spawn(center + Vector3(cos(angle) * 8.0, 1.4, sin(angle) * 8.0)))
		add_child(node)
		target_nodes.append(node)

func objective_complete() -> bool:
	for node in target_nodes:
		if is_instance_valid(node) and node.hp > 0.0: return false
	if boss_phase == 3:
		if not boss_spawned: return false
		for boss in objective_bosses:
			if is_instance_valid(boss) and boss.hp > 0.0: return false
	return true

func is_safe_window() -> bool:
	return boss_phase != 2 or fmod(objective_clock, safe_window_s + 1.8) < safe_window_s

func _update_objective(delta: float) -> void:
	if boss_phase != 2: return
	objective_clock += delta
	var cycle = fmod(objective_clock, safe_window_s + 1.8)
	var state = 0 if cycle < safe_window_s else (1 if cycle < safe_window_s + 1.2 else 2)
	if is_instance_valid(_safe_ring): _safe_ring.visible = state == 0
	if is_instance_valid(_sweep_beam):
		_sweep_beam.visible = state != 0
		_sweep_beam.rotation.y = 0.0 if state == 1 else (cycle - safe_window_s - 1.2) / 0.6 * PI
	if state == 1 and _last_sweep_state != 1:
		_warning_serial += 1
		_record("warning_started", self, pilot, objective_center, 0.0, 0.0, _warning_serial)
		warning_seen.emit()
	if state == 0: _sweep_hit = false
	if state == 2 and not _sweep_hit:
		var difference = pilot.global_position - objective_center
		var axis = _sweep_beam.global_basis.x * 12.0
		var nearest = Geometry3D.get_closest_point_to_segment(pilot.global_position, objective_center - axis, objective_center + axis)
		var envelope = maxf(0.7, float(pilot.stats.get("width_m",1.4)) * 0.5)
		if absf(difference.y) < 0.7 and pilot.global_position.distance_to(nearest) < envelope and line_clear(nearest, pilot.global_position, RID(), pilot.get_rid()):
			settle_hit(self,pilot,nearest,difference.normalized(),6.0,"collision",_warning_serial)
			_sweep_hit = true
	_last_sweep_state = state

func fire_bolt(from: Vector3, to: Vector3, amount: float, friendly: bool, source: CollisionObject3D) -> bool:
	if not from.is_finite() or not to.is_finite() or not is_finite(amount) or amount <= 0.0 or from.distance_squared_to(to) < 0.0001: return false
	var bolt: Bolt
	for existing in bolts:
		if not existing.active:
			bolt = existing
			break
	if bolt == null:
		if bolts.size() >= MAX_BOLTS: return false
		bolt = Bolt.new()
		bolt.combat = self
		add_child(bolt)
		bolts.append(bolt)
	if not _bolt_meshes.has(friendly):
		var mesh = SphereMesh.new()
		mesh.radius = 0.14 if friendly else 0.23
		mesh.height = mesh.radius * 2.0
		mesh.radial_segments = 8
		mesh.rings = 4
		_bolt_meshes[friendly] = mesh
	bolt.visual.mesh = _bolt_meshes[friendly]
	bolt.visual.material_override = GameVisuals.material(Color("74f6c8") if friendly else Color("ffb05b"), 0.2)
	bolt.direction = (to - from).normalized()
	bolt.weapon_type="lance" if friendly and str(pilot.build.get("slots",{}).get("weapon",""))=="burst_capacitor" else ("pulse" if friendly else "kinetic")
	bolt.near_pass_played=false
	bolt.amount = amount
	bolt.friendly = friendly
	bolt.source = source.get_rid() if is_instance_valid(source) else RID()
	bolt.source_node = source
	bolt.warning_id = source.warning_id if source is Foe else 0
	# Excluding the source collider lets swept rays begin at the muzzle, not beyond nearby walls.
	bolt.global_position = from
	if absf(bolt.direction.dot(Vector3.UP))<.99:bolt.look_at(from+bolt.direction,Vector3.UP)
	bolt.visual.scale=Vector3(.45,.45,2.6)
	bolt.remaining = 3.0
	bolt.active = true
	bolt.visible = friendly or not target_visibility.is_valid() or bool(target_visibility.call(from))
	bolt.set_physics_process(true)
	shot_fired.emit(friendly)
	var muzzle_point=from
	if is_instance_valid(source):
		var muzzle=source.find_child("Muzzle",true,false)
		if muzzle is Node3D:muzzle_point=muzzle.global_position
	if friendly:_weapon_recoil=.045
	_record("shot", source, null, from, amount, float(pilot.stats.get("modifiers",{}).get("weapon_heat",8.0)) if friendly else 0.0, bolt.warning_id,"",{"direction":[bolt.direction.x,bolt.direction.y,bolt.direction.z],"weapon_type":bolt.weapon_type,"friendly":friendly,"muzzle_position":[muzzle_point.x,muzzle_point.y,muzzle_point.z]})
	if friendly:
		for enemy in enemies:
			if is_instance_valid(enemy) and enemy.hp>0:enemy.brain.hear_noise(from,1.0)
	return true

class Bolt extends Node3D:
	var combat: CombatV2
	var direction = Vector3.FORWARD
	var amount = 10.0
	var friendly = false
	var weapon_type="pulse"
	var near_pass_played=false
	var source: RID
	var source_node: CollisionObject3D
	var warning_id = 0
	var remaining = 0.0
	var active = false
	var visual: MeshInstance3D
	func _ready() -> void:
		visual = MeshInstance3D.new()
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(visual)
		deactivate()
	func deactivate() -> void:
		active = false
		visible = false
		set_physics_process(false)
	func _physics_process(delta: float) -> void:
		remaining -= delta
		if remaining <= 0.0 or not is_instance_valid(combat.pilot) or not combat.pilot.enabled:
			deactivate()
			return
		var next = global_position + direction * (70.0 if friendly else 18.0) * delta
		var query = PhysicsRayQueryParameters3D.create(global_position, next, 1 | 4 | 8 | 32 if friendly else 1 | 2 | 8 | 32)
		if source.is_valid(): query.exclude = [source]
		var hit = get_world_3d().direct_space_state.intersect_ray(query)
		var stop:Vector3=hit.position if not hit.is_empty() else next
		if combat.environment_query.is_valid() and direction.y<-.001:
			var sample:Dictionary=combat.environment_query.call(stop)
			var water_y=float(sample.get("water_height",-.6))
			if bool(sample.get("water",false)) and global_position.y>water_y and stop.y<=water_y:
				var t=(water_y-global_position.y)/(stop.y-global_position.y)
				var water_point=global_position.lerp(stop,t)
				combat._record("impact",source_node if is_instance_valid(source_node) else null,null,water_point,0,0,warning_id,"water",{"surface":"water","direction":[direction.x,direction.y,direction.z],"friendly":friendly})
				deactivate();return
		if not friendly and not near_pass_played and (hit.is_empty() or hit.collider!=combat.pilot):
			var closest=Geometry3D.get_closest_point_to_segment(combat.pilot.global_position,global_position,stop)
			if closest.distance_to(combat.pilot.global_position)<2.8:
				near_pass_played=true
				combat._record("near_pass",source_node if is_instance_valid(source_node) else null,combat.pilot,closest,0,0,warning_id,"",{"direction":[direction.x,direction.y,direction.z],"friendly":false,"pilot_target":true})
		if not hit.is_empty():
			var valid_target = hit.collider.has_method("take_damage") and (not friendly or hit.collider is Foe or hit.collider is PowerNode)
			if valid_target:combat.settle_hit(source_node if is_instance_valid(source_node) else null,hit.collider,hit.position,direction,amount,weapon_type,warning_id)
			else:combat._record("impact",source_node if is_instance_valid(source_node) else null,hit.collider,hit.position,0,0,warning_id,"blocked",{"direction":[direction.x,direction.y,direction.z],"surface":combat.surface_at(hit.collider,hit.position),"friendly":friendly})
			deactivate()
		else:
			global_position = next
			visible=friendly or not combat.target_visibility.is_valid() or bool(combat.target_visibility.call(global_position))

class PowerNode extends StaticBody3D:
	var combat: CombatV2
	var hp = 30.0
	var max_hp = 30.0
	var destroyed = false
	func _ready() -> void:
		collision_layer = 4
		collision_mask = 0
		var shape = CollisionShape3D.new()
		var box_shape = BoxShape3D.new()
		box_shape.size = Vector3(1.6, 2.2, 1.6)
		shape.shape = box_shape
		add_child(shape)
		GameVisuals.box(self, Vector3.ZERO, box_shape.size, Color("567d88"))
		GameVisuals.box(self, Vector3(0, 0.7, 0), Vector3(1.7, 0.22, 1.7), Color("ffb05b"))
	func take_damage(amount: float, _direction: Vector3 = Vector3.ZERO) -> void:
		combat.settle_hit(combat.pilot,self,global_position,_direction,amount,"pulse")
	func apply_combat_hit(amount:float,_direction:Vector3,_point:Vector3,_type:String,_context:Dictionary) -> Dictionary:
		if hp<=0 or destroyed or not is_finite(amount) or amount<=0:return {}
		var before=hp;hp=maxf(0,hp-amount)
		return {"raw_damage":amount,"damage":before-hp,"health_before":before,"health":hp,"max_health":max_hp,"armor_absorbed":0,"shield_absorbed":0,"component":"hull","component_damage":0,"killed":hp<=0,"hit_result":"destroyed" if hp<=0 else "hit","role":"power_node","entity_kind":"power_node"}
	func finish_destroyed(source:Node,receipt:Dictionary) -> void:
		if destroyed:return
		destroyed=true
		combat._record("destroyed",source,self,global_position,float(receipt.get("damage",0)),0,0,"destroyed",receipt)
		combat.enemy_down.emit("power_node")
		queue_free()

class Foe extends "res://scripts/v2/enemy_actor.gd":
	pass
