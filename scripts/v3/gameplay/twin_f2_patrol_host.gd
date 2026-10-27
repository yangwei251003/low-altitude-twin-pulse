extends Node3D
## AUTHORING ONLY. One optional F2 scout, no Story/Store/reward ownership.
## Session owns bind/teardown, one ordinary60Hz advance and normal weapon clocks.
const Actor=preload("res://scripts/v3/gameplay/twin_f2_patrol_actor.gd")
const View=preload("res://scripts/v3/gameplay/twin_f2_patrol_view.gd")
const Layout=preload("res://scripts/v3/campaign/twin_campaign_layout.gd")
const WeaponCycle=preload("res://scripts/v3/gameplay/twin_weapon_cycle.gd")
const ID := "F2:patrol_01"
const MASK := 1|2|4|8|32
const MAX_BOLTS := View.MAX_BULLETS # Original V2 cap; unchanged firing/physics.
const PUBLISH_SECONDS := .1
var session
var enabled := true # Native MAIN and actual protocol-25 ENet validated; Host owns simulation.
var error := ""
var scout # Actual Actor/CharacterBody3D; retain its script property type at call sites.
var pilot: FlightBodyV2 # Legacy Actor interface; Brain senses the real two-player roster.
var navigation_world: Node3D
var environment_query: Callable
var perception_visibility: Callable
var target_visibility: Callable
var combat_seed := 10415
var unit_sequence := 1
var difficulty := 0
var exposure_window_s := 4.0 # Unused scout; satisfies original Actor interface.
var enemies: Array = []
var events: Array = []
var epoch := 0
var serial := 0
var _world: Node3D
var _bounds := AABB()
var _protected: Array[AABB] = []
var _bolts: Array = []
var _bullet_serial := 0 # Monotonic identity only, no clock or damage authority.
var _remote_bullets: Dictionary = {}
var _remote_bullet_mesh: SphereMesh
var _remote_bullet_material: Material
var _warning_serial := 0
var _warning_gap := 0.0
var _publish_clock := 0.0
var _last_frame := -1
var _last_edge := ""
var _last_disabled_serial := -1
var _remote_session := ""
var _remote_epoch := -1
var _remote_serial := -1
var _required_epoch := 1
var _remote_view: Dictionary = {}
var _sealed_host_view: Dictionary = {} # One immutable presentation per epoch/serial.
var _event_serial := 0
var _settlement_source: Node
var _settlement_target: Node

func _ready() -> void:
	set_physics_process(false)
	set_process(false)

func setup(owner_session) -> void:
	session=owner_session

func bind_world() -> Dictionary:
	clear()
	if not enabled or session.region_id!="F2": return _r(true,"inactive")
	if not is_instance_valid(session.world) or not session.world.is_inside_tree(): return _r(false,"actual_F2_world_required")
	if not ResourceLoader.exists("res://assets/models/v22_combat/enemy_scout.glb"): return _r(false,"original_scout_GLB_import_required")
	var layout: Dictionary=Layout.definition("F2")
	var rows: Array=layout.get("enemy_spawns",[])
	if rows.is_empty() or rows[0].get("id")!=ID or rows[0].get("route",[]).size()!=2: return _r(false,"single_authored_scout_route_required")
	_world=session.world
	navigation_world=_world
	environment_query=_world.sample_environment
	var b: Array=layout.bounds
	_bounds=AABB(Vector3(b[0],b[1],b[2]),Vector3(b[3]-b[0],b[4]-b[1],b[5]-b[2]))
	_build_protected(layout)
	scout=Actor.new()
	scout.combat=self
	scout.authoritative=session.network.is_authority()
	scout.name="F2PatrolScout"
	scout.set_meta("entity_id",ID)
	scout.set_meta("unit_id",ID)
	scout.set_meta("source_kind","ambient")
	scout.position=_v(rows[0].position)
	var to: Vector3=_v(rows[0].route[1])
	var facing: Vector3=to-scout.position
	scout.rotation.y=atan2(-facing.x,-facing.z)
	_world.add_child(scout) # Actual factory spawn once; never a gameplay teleport.
	enemies=[scout]
	if not is_instance_valid(scout.model) or not _spawn_clear():
		clear()
		return _r(false,"scout_import_or_actual_spawn_occupied")
	scout.brain.set_patrol_target(to)
	if scout.authoritative:
		if epoch>=View.MAX_COUNTER: clear(); return _r(false,"epoch_limit")
		epoch+=1
		serial=0
		_sync_entity()
	else:
		_required_epoch=maxi(1,_remote_epoch+1)
		scout.visible=false
		scout.collision_layer=0; scout.collision_mask=0 # Pending first authority view.
	return _r(true,"one_scout_bound_waiting_ordinary_ticks")

func clear() -> void:
	_clear_remote_bullets()
	if session!=null: session.entities.erase(ID)
	for row: Dictionary in _bolts:
		if is_instance_valid(row.visual): row.visual.free()
	_bolts.clear()
	if is_instance_valid(scout): scout.free()
	scout=null
	enemies.clear()
	pilot=null
	_world=null
	navigation_world=null
	_protected.clear()
	_last_frame=-1
	_publish_clock=0.0
	_last_edge=""
	_last_disabled_serial=-1
	_settlement_source=null; _settlement_target=null
	_sealed_host_view.clear()
	error=""
	# Host epoch and remote high-watermarks survive ordinary region teardown.

func reset_connection() -> void:
	clear()
	epoch=0; serial=0
	_bullet_serial=0
	_warning_serial=0; _warning_gap=0.0
	_remote_session=""; _remote_epoch=-1; _remote_serial=-1
	_required_epoch=1
	_remote_view.clear()
	events.clear(); _event_serial=0

func advance(delta: float) -> Dictionary:
	if not enabled or not is_instance_valid(scout) or session.region_id!="F2": return _r(true,"inactive")
	if not error.is_empty(): return _r(true,"fault_latched_no_AI_or_damage")
	if not is_instance_valid(_world) or _world!=session.world or not scout.is_inside_tree() or scout.get_world_3d().space!=_world.get_world_3d().space: return _fault("actual_owned_World3D_required")
	if not session.network.is_authority(): return _fault("guest_has_no_AI_or_damage_tick")
	if not is_finite(delta) or delta<=0.0 or delta>minf(.1,1.0/float(Engine.physics_ticks_per_second)+.000001): return _fault("ordinary_physics_delta_required")
	if _last_frame==Engine.get_physics_frames(): return _fault("duplicate_physics_tick")
	_last_frame=Engine.get_physics_frames()
	if session.simulation_paused: return _r(true,"paused_no_clock_or_native_motion")
	var live: Array=_live_players()
	pilot=live[0] if not live.is_empty() else null
	_warning_gap=maxf(0.0,_warning_gap-delta)
	var reason: String=_ceasefire_reason()
	if reason!="none":
		for row: Dictionary in _bolts: row.remaining=0.0
	scout.host_tick(delta,"disabled" if scout.dying else reason)
	_advance_bolts(delta)
	if serial>=View.MAX_COUNTER: return _fault("serial_limit")
	serial+=1
	_sync_entity()
	var view: Dictionary=presentation()
	if not View.valid(view): return _fault("actual_presentation_contract_rejected")
	var bullet_ids: Array=[]
	for row: Dictionary in view.bullets: bullet_ids.append(row.id)
	var edge: String=JSON.stringify([view.actor.alive,view.actor.phase,view.actor.warning.token,view.actor.warning.active,bullet_ids])
	_publish_clock+=delta
	if edge!=_last_edge or _publish_clock>=PUBLISH_SECONDS:
		_last_edge=edge
		_publish_clock=0.0
		publish()
	return _r(true,"ordinary_single_scout_tick")

func candidate_players() -> Array:
	var result: Array=[]
	for body: FlightBodyV2 in _live_players():
		if may_target(body): result.append(body)
	return result

func _live_players() -> Array:
	var result: Array=[]
	if session==null: return result
	var peers: Array=session.players.keys()
	peers.sort()
	for peer: Variant in peers:
		var body: Variant=session.players[peer]
		if body is FlightBodyV2 and is_instance_valid(body) and body.is_inside_tree() and body.enabled and body.health>0 and is_instance_valid(_world) and body.get_world_3d().space==_world.get_world_3d().space: result.append(body)
	return result

func _ceasefire_reason() -> String:
	if not error.is_empty(): return "fault"
	if not session.active: return "no_active_pilots"
	if session.boss_active or session.campaign.active(): return "boss"
	if session.combat_sites.active(): return "boss"
	if _live_players().is_empty(): return "no_active_pilots"
	if session.interface.radio.visible: return "radio"
	if session.interface.menu.visible or session.interface.hangar.visible: return "menu"
	if session.interface.journal.visible: return "menu"
	if session.interface.wheel.visible: return "wheel"
	if session.interface.travel.visible: return "travel"
	if session.interface.chapter_choice.visible: return "choice"
	if session.interface.vote.visible or not session.consensus.current_proposal().is_empty(): return "vote"
	return "none"

func may_target(body: Variant) -> bool:
	return body is FlightBodyV2 and is_instance_valid(body) and body in _live_players() and bool(body.command.get("active",true)) and _ceasefire_reason()=="none" and not _protected_point(body.global_position,Vector3.ONE*Vector3(float(body.stats.width_m),float(body.stats.height_m),float(body.stats.length_m)).length()*.5)

func flight_bounds() -> AABB:
	return _bounds

func allowed_goal(point: Vector3, from: Vector3) -> Vector3:
	return from if _protected_point(point,scout.dimensions*.5) else point

func _build_protected(layout: Dictionary) -> void:
	# Full-height columns protect ordinary spawn, manual readings/choice/NPC
	# and the Boss arena. Safety is symmetric: players cannot shoot from them.
	for solid: Dictionary in layout.solids:
		if solid.id=="SouthLanding":
			var c: Vector3=_v(solid.position)
			var size: Vector3=_v(solid.size)
			_protected.append(AABB(Vector3(c.x-size.x*.5,_bounds.position.y,c.z-size.z*.5),Vector3(size.x,_bounds.size.y,size.z)))
	for id: String in ["npc:shuyao","F2:record_low","F2:record_high","F2:clock_stone","F2:choice_terminal","F2:boss_briefing","F2:boss_record"]:
		var marker: Dictionary=session.story.markers.get(id,{})
		if marker.is_empty(): continue
		var at: Vector3=session.story._point(marker)
		var radius: float=float(marker.radius)
		_protected.append(AABB(Vector3(at.x-radius,_bounds.position.y,at.z-radius),Vector3(radius*2,_bounds.size.y,radius*2)))
	var arena: Dictionary=layout.boss_arena
	var centre: Vector3=_v(arena.centre)
	var half: Vector3=_v(arena.half_extents)
	_protected.append(AABB(Vector3(centre.x-half.x,_bounds.position.y,centre.z-half.z),Vector3(half.x*2,_bounds.size.y,half.z*2)))

func _protected_point(point: Vector3, half: Vector3) -> bool:
	for box: AABB in _protected:
		if AABB(box.position-half,box.size+half*2).has_point(point): return true
	return false

func motion_fraction(body: CharacterBody3D, from: Vector3, motion: Vector3) -> float:
	if not is_instance_valid(body) or not body.is_inside_tree() or not from.is_finite() or not motion.is_finite(): return 0.0
	var fraction := 1.0
	var found := false
	for child: Node in body.get_children():
		if not child is CollisionShape3D or child.disabled: continue
		if not child.shape is BoxShape3D: return 0.0
		found=true
		var query:=PhysicsShapeQueryParameters3D.new()
		query.shape=child.shape
		query.transform=child.global_transform
		query.transform.origin+=from-body.global_position
		var size: Vector3=child.shape.size
		var start: AABB=query.transform*AABB(-size*.5,size)
		var finish: AABB=start
		finish.position+=motion
		var swept: AABB=start.merge(finish)
		if not _bounds.encloses(swept): return 0.0
		for protected: AABB in _protected:
			if protected.intersects(swept): return 0.0
		query.collision_mask=MASK
		query.exclude=[body.get_rid()]
		var space: PhysicsDirectSpaceState3D=body.get_world_3d().direct_space_state
		if not space.intersect_shape(query,1).is_empty(): return 0.0
		if motion.length()<.000001: continue
		query.motion=motion
		var cast: PackedFloat32Array=space.cast_motion(query)
		if cast.size()!=2: return 0.0
		fraction=minf(fraction,float(cast[0]))
	return fraction if found else 0.0

func _spawn_clear() -> bool:
	return scout.dimensions.is_finite() and scout.dimensions.x>0 and scout.dimensions.y>0 and scout.dimensions.z>0 and motion_fraction(scout,scout.global_position,Vector3.ZERO)>=.999

func line_clear(from: Vector3,to: Vector3,source: RID,target: RID) -> bool:
	if not is_instance_valid(_world) or not from.is_finite() or not to.is_finite(): return false
	var hit: Dictionary=_ray(from,to,source)
	return not hit.is_empty() and hit.get("rid")==target # Empty is never a hit.

func projectile_path_clear(from: Vector3,to: Vector3,source: RID,target: RID) -> bool:
	# Original V2 aim error may deliberately miss. Empty permits launching a
	# projectile into clear air; only a later actual native ray can settle damage.
	var hit: Dictionary=_ray(from,to,source)
	return hit.is_empty() or hit.get("rid")==target

func _ray(from: Vector3,to: Vector3,source: RID) -> Dictionary:
	return _world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,to,MASK,[source]))

func owns_target(id: String) -> bool:
	return enabled and id==ID and is_instance_valid(scout) and session.region_id=="F2"

func weapon_context(peer: int) -> Dictionary:
	if not session.players.has(peer): return {"is_authority":session.network.is_authority(),"held_fire":false,"enabled":false,"paused":bool(session.simulation_paused),"target_id":ID,"target_valid":false,"line_of_sight":false,"part_open":false}
	var live: bool=owns_target(str(session.locks.get(peer,""))) and session.players.has(peer) and not scout.dying and scout.hp>0
	var los := false
	if live:
		var body: FlightBodyV2=session.players[peer]
		live=may_target(body) and body.global_position.distance_to(scout.global_position)<=36.0 and not _protected_point(scout.global_position,scout.dimensions*.5)
		los=live and line_clear(body.global_position,scout.global_position,body.get_rid(),scout.get_rid())
	return {"is_authority":session.network.is_authority(),"held_fire":bool(session.players[peer].command.get("fire",false)),"enabled":bool(session.players[peer].enabled),"paused":bool(session.simulation_paused),"target_id":ID,"target_valid":live,"line_of_sight":los,"part_open":live}

func fire_player(peer: int,amount: float) -> bool:
	if not session.network.is_authority() or not owns_target(str(session.locks.get(peer,""))) or not session.players.has(peer): return false
	var context: Dictionary=weapon_context(peer)
	if session.simulation_paused or not context.target_valid or not context.line_of_sight: return false
	var profile: Dictionary=WeaponCycle.weapon_profile(session.players[peer].build)
	if not profile.get("ok",false) or not is_finite(amount) or amount!=float(profile.profile.damage): return false
	var body: FlightBodyV2=session.players[peer]
	var hit: Dictionary=_ray(body.global_position,scout.global_position,body.get_rid())
	if hit.get("rid")!=scout.get_rid(): return false
	session.stats.shots+=1
	session._audio_event("shot",body.global_position,str(peer))
	session._beam(body.global_position,hit.position,Color("f4d497"))
	var receipt: Dictionary=_settle_native(body,scout,hit.position,(scout.global_position-body.global_position).normalized(),amount,"pulse",0)
	return not receipt.is_empty()

func request_warning(attacker: CharacterBody3D,target: CollisionObject3D) -> int:
	if attacker!=scout or _warning_gap>0 or _warning_serial>=View.MAX_COUNTER or not may_target(target): return 0
	if not line_clear(attacker.global_position,target.global_position,attacker.get_rid(),target.get_rid()): return 0
	_warning_gap=.65 # Original beginner warning cadence; one enemy only.
	_warning_serial+=1
	session._audio_event("boss_warning",scout.global_position,ID)
	_record("warning_started",{"token":_warning_serial,"target_peer":_peer(target)})
	return _warning_serial

func fire_bolt(from: Vector3,to: Vector3,amount: float,friendly: bool,source: CollisionObject3D) -> bool:
	if not session.network.is_authority() or friendly or source!=scout or _ceasefire_reason()!="none" or amount!=7.0 or _bolts.size()>=MAX_BOLTS or _bullet_serial>=View.MAX_COUNTER or not from.is_finite() or not to.is_finite() or from.distance_squared_to(to)<.0001: return false
	var visual:=MeshInstance3D.new()
	var mesh:=SphereMesh.new()
	mesh.radius=.23; mesh.height=.46; mesh.radial_segments=8; mesh.rings=4
	visual.mesh=mesh
	visual.material_override=GameVisuals.material(Color("ffb05b"),.2)
	visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.add_child(visual)
	visual.global_position=from
	visual.scale=Vector3(.45,.45,2.6)
	var direction: Vector3=(to-from).normalized()
	if absf(direction.dot(Vector3.UP))<.99: visual.look_at(from+direction,Vector3.UP)
	_bullet_serial+=1
	_bolts.append({"id":_bullet_serial,"position":from,"direction":direction,"remaining":3.0,"source":scout.get_rid(),"warning_id":int(scout.warning_id),"amount":amount,"visual":visual})
	session._audio_event("shot",from,ID)
	_record("enemy_shot",{"token":scout.warning_id,"position":from,"direction":direction})
	return true

func _advance_bolts(delta: float) -> void:
	for index: int in range(_bolts.size()-1,-1,-1):
		var row: Dictionary=_bolts[index]
		row.remaining-=delta
		if row.remaining<=0.0:
			row.visual.free(); _bolts.remove_at(index); continue
		var from: Vector3=row.position
		var to: Vector3=from+Vector3(row.direction)*18.0*delta # Original enemy projectile.
		var hit: Dictionary=_ray(from,to,row.source)
		var stop: Vector3=hit.position if not hit.is_empty() else to
		if environment_query.is_valid() and float(row.direction.y)<-.001:
			var sample: Dictionary=environment_query.call(stop)
			var water_y: float=float(sample.get("water_height",-.6))
			if sample.get("water",false) and from.y>water_y and stop.y<=water_y:
				_record("water_impact",{"warning_id":row.warning_id})
				row.visual.free(); _bolts.remove_at(index); continue
		if not hit.is_empty():
			var target: Variant=hit.get("collider")
			if may_target(target): _settle_native(scout,target,hit.position,row.direction,float(row.amount),"kinetic",int(row.warning_id))
			row.visual.free(); _bolts.remove_at(index)
		else:
			row.position=to
			row.visual.global_position=to

func settle_hit(source: Node,target: Node,point: Vector3,direction: Vector3,amount: float,weapon_type="pulse",warning_id=0) -> Dictionary:
	if source!=_settlement_source or target!=_settlement_target or not session.network.is_authority() or not is_instance_valid(target) or _ceasefire_reason()!="none": return {}
	if target==scout:
		if not source in _live_players() or not may_target(source) or scout.dying: return {}
	elif source!=scout or not may_target(target): return {}
	var receipt: Dictionary=target.apply_combat_hit(amount,direction,point,weapon_type,{"source":"F2_patrol","warning_id":warning_id})
	if receipt.is_empty(): return {}
	_record("hit",{"target":ID if target==scout else "player:"+str(_peer(target)),"receipt":receipt,"point":point})
	if target==scout:
		scout.brain.note_damage(source.global_position)
		if float(receipt.damage)>0.0: session._audio_event("hit",point,ID)
		if receipt.get("killed",false): scout.finish_destroyed(source,receipt)
	# FlightBody already owns damage telemetry/audio/disabled signal and rescue.
	return receipt

func _settle_native(source: Node,target: Node,point: Vector3,direction: Vector3,amount: float,weapon_type: String,warning_id: int) -> Dictionary:
	# Only synchronous internal native-ray call sites issue this capability.
	# Legacy take_damage/G/client payloads cannot manufacture a settlement.
	if _settlement_target!=null: return {}
	_settlement_source=source; _settlement_target=target
	var receipt: Dictionary=settle_hit(source,target,point,direction,amount,weapon_type,warning_id)
	_settlement_source=null; _settlement_target=null
	return receipt

func settlement_active_for(target: Node) -> bool:
	return target==_settlement_target and is_instance_valid(_settlement_source)

func scout_disabled(_source: Node,receipt: Dictionary) -> void:
	var damage_serial: int=int(receipt.get("serial",-1))
	if damage_serial==_last_disabled_serial: return
	_last_disabled_serial=damage_serial
	session.entities.erase(ID)
	session._audio_event("boss_defeated",scout.global_position,ID)
	_record("disabled",{"damage_serial":damage_serial,"reward":"none","save":"transient_visit_only"})

func record_transition(before: String,after: String) -> void:
	_record("AI_transition",{"before":before,"after":after})

func record_observation(intent: Dictionary) -> void:
	_record("legacy_scout_report",{"confidence":intent.confidence,"last_observed_position":intent.report_position})

func _record(kind: String,detail: Dictionary) -> void:
	_event_serial+=1
	events.append({"serial":_event_serial,"physics_frame":Engine.get_physics_frames(),"kind":kind,"detail":detail.duplicate(true)})
	if events.size()>256: events.pop_front()

func _sync_entity() -> void:
	if scout.dying: session.entities.erase(ID); return
	session.entities[ID]={"id":ID,"name":"巡逻侦察机","tags":[],"position":scout.global_position,"angle":scout.rotation.y,"revision":serial,"owner":"neutral"}
	# Deliberately absent from world.objects/definitions: no generic mechanism
	# synchronization or persistent_environment save owns this ephemeral actor.

func presentation() -> Dictionary:
	if not enabled or not is_instance_valid(scout) or session.region_id!="F2": return {}
	if not session.network.is_authority(): return _remote_view.duplicate(true)
	# UI/roster policy can change between ordinary ticks, including during pause.
	# A rank names one complete view; no live command read may rewrite that rank.
	# This seals presentation only. Targeting/LOS/DamageModel still read live truth.
	if not _sealed_host_view.is_empty() and int(_sealed_host_view.epoch)==epoch and int(_sealed_host_view.serial)==serial:
		return _sealed_host_view.duplicate(true)
	_sealed_host_view=_read_host_view()
	return _sealed_host_view.duplicate(true)

func _read_host_view() -> Dictionary:
	var alive: bool=not scout.dying and scout.hp>0.0
	var target: Variant=scout.attack_target.get_ref() if scout.attack_target!=null else null
	var warning: bool=alive and scout.telegraph>0.0 and is_instance_valid(target) and may_target(target)
	var end: Vector3=scout.global_position+scout.attack_direction*scout.attack_length if warning else scout.global_position
	var bullets: Array=[]
	for row: Dictionary in _bolts:
		bullets.append({"id":int(row.id),"position":row.visual.global_position,"basis":row.visual.global_basis})
	return {"version":1,"session_id":session.network.session_id,"region":"F2","epoch":epoch,"serial":serial,"bullets":bullets,"actor":{"id":ID,"position":scout.global_position,"velocity":scout.velocity,"heading":float(scout.rotation.y),"health":float(scout.hp),"max_health":float(scout.max_hp),"armor":float(scout.damage_state.armor),"damage_serial":int(scout.damage_state.serial),"alive":alive,"phase":"disabled" if not alive else "ceasefire" if scout.ceasefire_reason!="none" else str(scout.brain.state),"ceasefire":"disabled" if not alive else scout.ceasefire_reason,"recoil":float(scout.recoil),"warning":{"token":int(scout.warning_id),"active":warning,"remaining_ms":clampi(ceili(scout.telegraph*1000.0),1,1000) if warning else 0,"origin":scout.global_position,"end":end,"target_peer":_peer(target) if warning else 0}}}

func publish() -> void:
	if session.network.mode!="host" or session.network.guests.is_empty(): return
	var view: Dictionary=presentation()
	if view.is_empty() or not View.valid(view): return
	for peer: Variant in session.network.guests:
		session.network.send_event(int(peer),{"kind":View.KIND,"session_id":session.network.session_id,"region":"F2","state":view})

func can_receive(view: Variant,source_session: String,incoming_region: String) -> bool:
	if session.network.mode!="guest" or not View.valid(view): return false
	if view.is_empty(): return true
	# Match the exact factory branch before Session changes world/players.
	# bind_world will require the next visit epoch if this packet rebuilds F2.
	var required_epoch: int=_required_epoch
	if not is_instance_valid(session.world) or session.region_id!=incoming_region:
		required_epoch=maxi(required_epoch,_remote_epoch+1)
	if not enabled or incoming_region!="F2" or view.region!=incoming_region or view.session_id!=source_session or int(view.epoch)<required_epoch: return false
	# Reject contradictory equal-ranked actor state before Session mutates any
	# player/region presentation; older consistent packets may still carry players.
	if _remote_session==source_session and int(view.epoch)==_remote_epoch and int(view.serial)==_remote_serial and view!=_remote_view: return false
	return true

func receive(view: Dictionary) -> bool:
	if not can_receive(view,session.received_session,session.region_id): return false
	if view.is_empty():
		_clear_remote_bullets()
		if is_instance_valid(scout): scout.visible=false; scout.collision_layer=0; scout.collision_mask=0
		session.entities.erase(ID)
		return true
	if not is_instance_valid(scout): return false
	if _remote_session!=view.session_id:
		_remote_session=view.session_id; _remote_epoch=-1; _remote_serial=-1
	if int(view.epoch)<_remote_epoch or int(view.epoch)==_remote_epoch and int(view.serial)<_remote_serial:
		_sync_remote_entity(_remote_view.actor)
		return true # Ignore old actor state; keep newer player packet.
	if int(view.epoch)==_remote_epoch and int(view.serial)==_remote_serial:
		_sync_remote_entity(_remote_view.actor)
		return view==_remote_view
	_remote_epoch=int(view.epoch); _remote_serial=int(view.serial)
	_remote_view=view.duplicate(true)
	var a: Dictionary=view.actor
	scout.global_transform=Transform3D(Basis(Vector3.UP,float(a.heading)),a.position)
	scout.force_update_transform()
	scout.velocity=a.velocity
	scout.hp=float(a.health); scout.dying=not a.alive; scout.recoil=float(a.recoil)
	scout.visible=a.alive
	scout.collision_layer=4 if a.alive else 0
	scout.collision_mask=MASK if a.alive else 0
	scout.warning.visible=a.warning.active
	scout.beam.visible=a.warning.active
	if a.warning.active:
		var difference: Vector3=a.warning.end-a.warning.origin
		scout.beam.global_position=a.warning.origin+difference*.5
		if difference.length()>.001 and absf(difference.normalized().dot(Vector3.UP))<.99: scout.beam.look_at(a.warning.end,Vector3.UP)
		scout.beam.scale.z=difference.length()
	_sync_remote_bullets(view.bullets) # Whole view already validated before any pose change.
	_sync_remote_entity(a)
	return true

func receive_event(event: Dictionary) -> void:
	if event.size()!=4 or event.get("kind")!=View.KIND or event.get("session_id")!=session.received_session or event.get("region")!=session.region_id or not event.get("state") is Dictionary: return
	receive(event.state) # Same serial/epoch and no local damage, audio or AI tick.

func _clear_remote_bullets() -> void:
	for visual: Variant in _remote_bullets.values():
		if is_instance_valid(visual): visual.free()
	_remote_bullets.clear()
	_remote_bullet_mesh=null
	_remote_bullet_material=null

func _sync_remote_bullets(rows: Array) -> void:
	# Exact latest authoritative samples; no prediction, local TTL or hit effect.
	# Each object is only a MeshInstance3D, never a body/shape/timer/controller.
	var ids: Dictionary={}
	for row: Dictionary in rows: ids[row.id]=true
	for id: Variant in _remote_bullets.keys():
		if ids.has(id): continue
		var previous: Variant=_remote_bullets[id]
		if is_instance_valid(previous): previous.free()
		_remote_bullets.erase(id)
	for row: Dictionary in rows:
		var visual: MeshInstance3D=_remote_bullets.get(row.id)
		if not is_instance_valid(visual):
			if _remote_bullet_mesh==null:
				_remote_bullet_mesh=SphereMesh.new()
				_remote_bullet_mesh.radius=.23; _remote_bullet_mesh.height=.46
				_remote_bullet_mesh.radial_segments=8; _remote_bullet_mesh.rings=4
				_remote_bullet_material=GameVisuals.material(Color("ffb05b"),.2)
			visual=MeshInstance3D.new()
			visual.mesh=_remote_bullet_mesh
			visual.material_override=_remote_bullet_material
			visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			visual.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
			_world.add_child(visual)
			_remote_bullets[row.id]=visual
		visual.global_transform=Transform3D(row.basis,row.position)

func _sync_remote_entity(a: Dictionary) -> void:
	if not a.alive: session.entities.erase(ID); return
	session.entities[ID]={"id":ID,"name":"巡逻侦察机","tags":[],"position":a.position,"angle":a.heading,"revision":_remote_serial,"owner":"neutral"}

func present(delta: float) -> void:
	if session.network.mode=="guest" and is_instance_valid(scout) and not session.simulation_paused: scout.present_tick(delta)

func _peer(body: Variant) -> int:
	for peer: Variant in session.players:
		if session.players[peer]==body: return int(peer)
	return 0

static func _v(value: Array) -> Vector3:
	return Vector3(value[0],value[1],value[2])

func _fault(code: String) -> Dictionary:
	if error.is_empty():
		error=code
		if is_instance_valid(scout):
			scout.cancel_warning()
			scout.velocity=Vector3.ZERO
			scout.ceasefire_reason="fault"
		for row: Dictionary in _bolts:
			if is_instance_valid(row.visual): row.visual.free()
		_bolts.clear()
		# A terminal fault is one real state transition, with no physics/time credit.
		# At the existing hard counter bound, retain the last sealed presentation.
		if serial<View.MAX_COUNTER:
			serial+=1
			_sealed_host_view.clear()
		_record("fault_latched",{"code":code})
	return _r(false,code) # Only first rejection reaches Session note; no repeated ticks.

static func _r(ok: bool,code: String) -> Dictionary:
	return {"ok":ok,"code":code}
