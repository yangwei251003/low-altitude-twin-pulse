extends SceneTree

const Combat = preload("res://scripts/v2/combat.gd")
const Body = preload("res://scripts/v2/flight_body.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
const Damage = preload("res://scripts/v2/damage_model.gd")
var arena: Node3D
var combat: CombatV2
var pilot: FlightBodyV2
var failures: Array = []
var checks = 0
var friendly_shots = 0
var hostile_shots = 0
var warnings = 0
var deaths: Array = []
var metrics: Dictionary = {}

func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	checks += 1
	print("COMBAT_V2_", "PASS " if condition else "FAIL ", description)
	if not condition: failures.append(description)

func step(count: int) -> void:
	for i in range(count): await physics_frame

func setup() -> void:
	if is_instance_valid(arena):
		arena.queue_free()
		await process_frame
		await physics_frame
	arena = Node3D.new()
	# Production navigation is bounded to the authored world. Keep this fixture
	# inside it so perception tests do not also exercise an out-of-world return.
	arena.position = Vector3(200,0,200)
	root.add_child(arena)
	pilot = Body.new()
	pilot.configure(Catalog.resolve_build(Catalog.default_build()))
	pilot.position = Vector3(0, 5, 0)
	pilot.freeze = true
	pilot.command = {"active":true,"fire":false}
	arena.add_child(pilot)
	combat = Combat.new()
	combat.pilot = pilot
	combat.auto_fire = false
	arena.add_child(combat)
	combat.shot_fired.connect(func(friendly):
		if friendly: friendly_shots += 1
		else: hostile_shots += 1)
	combat.warning_seen.connect(func():warnings += 1)
	combat.enemy_down.connect(func(role):deaths.append(role))
	friendly_shots = 0
	hostile_shots = 0
	warnings = 0
	deaths = []
	await step(3)

func foe(role: String, position: Vector3, moving: bool = false):
	var enemy = Combat.Foe.new()
	enemy.role = role
	enemy.combat = combat
	enemy.position = position
	combat.add_child(enemy)
	enemy.home = position
	enemy.set_physics_process(moving)
	combat.enemies.append(enemy)
	return enemy

func exact_projectile_fixture(enemy) -> void:
	# Only trajectory/receipt tests remove aim error. Production profiles retain
	# their nonzero error and get a separate assertion before this fixture applies.
	enemy.brain.profile.error = 0.0
	enemy.brain._aim_error = Vector3.ZERO
	enemy.brain._aim_left = 0.0

func wait_warning(enemy, limit: int = 180) -> bool:
	for i in limit:
		if enemy.telegraph > 0.0: return true
		await step(1)
	return enemy.telegraph > 0.0

func target_hits(id: String) -> Array:
	return combat.events.filter(func(event): return str(event.kind)=="hit" and str(event.target_id)==id)

func conserved(receipt: Dictionary, raw: float) -> bool:
	return not receipt.is_empty() and is_equal_approx(float(receipt.damage)+float(receipt.get("armor_absorbed",0))+float(receipt.get("shield_absorbed",0)),raw)

func wall(position: Vector3, size: Vector3) -> StaticBody3D:
	var body = StaticBody3D.new()
	body.position = position
	body.collision_layer = 1
	var shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	arena.add_child(body)
	return body

func run() -> void:
	await test_player_weapon()
	await test_charge_and_heat()
	await test_occlusion()
	await test_enemy_roles()
	await test_objectives()
	await test_projectile_pool()
	if is_instance_valid(arena): arena.queue_free()
	await process_frame
	var report = {"suite":"combat_v2","engine":Engine.get_version_info().string,"checks":checks,"failures":failures,"ok":failures.is_empty(),"metrics":metrics,"evidence_scope":"Headless actual physics frames, ray collisions and synthetic commands. Not graphics, GPU performance, touch/controller hardware or human comfort evidence."}
	var file = FileAccess.open("res://artifacts/v2/combat_summary.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report,"\t",true,true))
		file.close()
	else:
		printerr("Cannot write combat summary")
		quit(2)
		return
	print("COMBAT_V2_SUMMARY ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func test_player_weapon() -> void:
	await setup()
	var target = foe("shooter", Vector3(9,5,0))
	var target_id = str(target.get_instance_id())
	await step(3)
	check(combat.nearest_target(36) == target, "nearest target uses live collider")
	var heading = pilot.heading
	var orientation = pilot.basis
	pilot.command.fire = true
	await step(17)
	var hits = target_hits(target_id)
	var first: Dictionary = hits[0] if not hits.is_empty() else {}
	check(hits.size()==1 and conserved(first,float(pilot.stats.modifiers.get("weapon_damage",10))) and is_equal_approx(target.max_hp-target.hp,float(first.get("damage",0))), "pulse receipt conserves catalog damage across hull and armor")
	check(friendly_shots == 1, "pulse interval prevents premature second shot")
	check(is_equal_approx(pilot.heading, heading) and pilot.basis.is_equal_approx(orientation), "weapon aiming does not rotate aircraft heading or body")
	check(combat.aim_direction.dot(Vector3.RIGHT) > 0.99, "independent aim follows lateral target")
	var mount = pilot.model.get_node_or_null("Attachment_weapon")
	check(is_instance_valid(mount) and (-mount.global_basis.z).dot(Vector3.RIGHT) > 0.99, "actual weapon attachment turns independently toward target")
	for i in 600:
		if combat.alive_count()==0: break
		await step(1)
	check(combat.alive_count() == 0 and combat.kills == 1 and deaths == ["shooter"], "real swept bullets defeat enemy exactly once")
	var shots_at_defeat = friendly_shots
	await step(80)
	check(friendly_shots == shots_at_defeat and combat.kills==1 and deaths.size()==1, "firing stops after actual defeat without assuming a fixed armor-dependent shot count")
	metrics.pulse_shots_to_defeat = shots_at_defeat

func test_charge_and_heat() -> void:
	await setup()
	var target = foe("shooter", Vector3(8,5,0))
	target.hp = 500
	target.max_hp = 500
	target.damage_state = Damage.create_state(500,float(target.damage_state.armor),target.dimensions)
	var target_id = str(target.get_instance_id())
	pilot.stats.modifiers.merge({"weapon_charge_s":0.7,"weapon_damage":28.0,"weapon_interval_s":1.0,"weapon_heat":32.0,"heat_dissipation_ps":0.0}, true)
	pilot.command.fire = true
	await step(39)
	check(friendly_shots == 0 and combat.charge > 0.5, "0.7 second charge never fires at 0.65 seconds")
	pilot.command.fire = false
	await step(5)
	check(combat.charge == 0 and friendly_shots == 0 and pilot.heat == 0, "early release cancels charge without damage or heat")
	pilot.command.fire = true
	await step(45)
	pilot.command.fire = false
	await step(12)
	var hits = target_hits(target_id)
	var receipt: Dictionary = hits[0] if not hits.is_empty() else {}
	check(friendly_shots == 1 and hits.size()==1 and conserved(receipt,28) and is_equal_approx(500-target.hp,float(receipt.get("damage",0))), "fresh full charge emits one receipt whose hull and armor loss equal catalog strength")
	check(is_equal_approx(pilot.heat,32), "charged shot uses catalog heat")
	pilot.heat = 95
	pilot.stats.modifiers.weapon_charge_s = 0
	combat.shoot_clock = 0
	pilot.command.fire = true
	await step(3)
	check(combat.overheat and pilot.heat == pilot.max_heat, "overheat clamps to capacity and locks firing")
	var count = friendly_shots
	await step(120)
	check(friendly_shots == count, "overheat prevents further shots")
	pilot.command.fire = false
	pilot.stats.modifiers.cooling_multiplier = 2.0
	pilot.stats.modifiers.heat_dissipation_ps = 16.0
	await step(90)
	check(combat.overheat and pilot.heat > 40 and pilot.heat < 54, "catalog cooling multiplier applied while still above unlock threshold")
	await step(30)
	check(not combat.overheat and pilot.heat < 40, "weapon unlocks below 40 percent heat")
	pilot.command = {"active":false,"fire":true}
	await step(60)
	check(friendly_shots == count, "inactive input cannot continue charged or automatic firing")

func test_occlusion() -> void:
	await setup()
	var blocked = foe("shooter", Vector3(6,5,0))
	var visible = foe("shooter", Vector3(0,5,-10))
	var blocker = wall(Vector3(3,5,0), Vector3(0.2,8,5))
	await step(4)
	check(combat.nearest_target(36) == visible, "occluded nearest enemy does not mask a visible alternative")
	combat.fire_bolt(pilot.global_position, blocked.global_position, 20, true, pilot)
	await step(20)
	check(blocked.hp == blocked.max_hp, "swept player shot is stopped by wall")
	blocker.queue_free()
	await step(3)
	wall(Vector3(0.85,5,0),Vector3(0.1,4,4))
	await step(3)
	combat.fire_bolt(pilot.global_position, blocked.global_position,20,true,pilot)
	await step(20)
	check(blocked.hp == blocked.max_hp, "muzzle does not skip thin wall within old one-meter offset")
	check(not combat.line_clear(Vector3(NAN,0,0),Vector3.ZERO,RID(),RID()), "nonfinite ray endpoints rejected")
	check(not combat.fire_bolt(Vector3.ZERO,Vector3.ZERO,10,true,pilot), "zero-direction bolt rejected")
	check(not combat.fire_bolt(Vector3.ZERO,Vector3.ONE,NAN,true,pilot), "nonfinite damage rejected")

func test_enemy_roles() -> void:
	await setup()
	var shooter = foe("shooter",Vector3(0,5,-12),true)
	shooter.cooldown = 0
	var began = Engine.get_physics_frames()
	await step(34)
	check(warnings==0 and hostile_shots==0, "shooter does not skip the 0.65 second perception reaction")
	check(float(shooter.brain.profile.error)>0 and shooter.brain._aim_error.length()>.01, "normal enemy profile produces nonzero seeded aim error")
	exact_projectile_fixture(shooter)
	var warned = await wait_warning(shooter)
	check(warned and warnings==1 and hostile_shots==0 and shooter.beam.visible and shooter.brain.reaction_time>=.65, "continuous perception finishes reaction before starting the full warning")
	var warning_id: int = shooter.warning_id
	var warning_events: Array = combat.events.filter(func(event):return event.kind=="warning_started" and event.warning_id==warning_id)
	var warning_tick: int = int(warning_events[0].tick) if not warning_events.is_empty() else -1
	check(warning_tick>=began+38, "warning timestamp includes reaction time within one physics-tick boundary")
	var locked: Vector3 = shooter.attack_direction
	await step(50)
	check(hostile_shots==0 and (-shooter.beam.global_basis.z).normalized().dot(locked)>.999, "warning stays on the locked world vector before its one-second duration ends")
	for i in 40:
		if hostile_shots>0: break
		await step(1)
	var shot_events: Array = combat.events.filter(func(event):return event.kind=="shot" and event.warning_id==warning_id)
	check(not shot_events.is_empty() and int(shot_events[0].tick)-warning_tick>=59, "actual shot waits a full one-second warning within one tick")
	await step(60)
	check(hostile_shots == 1 and pilot.health < pilot.maximum_health, "warned enemy projectile can damage pilot")
	var traced: Array = []
	for event in combat.events:
		if event.warning_id == warning_id: traced.append(event.kind)
	check(traced.has("warning_started") and traced.has("shot") and traced.has("hit"), "warning shot and hit share a traceable warning ID")
	var event = combat.events.back()
	check(event.has_all(["event_id","tick","source_id","target_id","kind","position","damage","heat_delta","warning_id","hit_result","weapon_id"]), "combat events contain required replay fields")
	await setup()
	foe("shooter",Vector3(-6,5,-10),true).cooldown = 0
	foe("shooter",Vector3(6,5,-10),true).cooldown = 0
	await step(34)
	check(warnings==0, "both enemies must first complete their reaction period")
	for i in 100:
		if warnings>0: break
		await step(1)
	check(warnings == 1, "beginner attack budget staggers simultaneous shooter warnings")
	await step(110)
	check(warnings >= 2, "waiting enemies receive a later attack window")
	await setup()
	pilot.position = Vector3(40,5,0)
	var facility = Facility.new()
	facility.position = Vector3(0,5,0)
	arena.add_child(facility)
	combat.facility = facility
	shooter = foe("shooter",Vector3(0,5,-12),true)
	# Face the assigned facility; perception still needs real FOV, LOS and time.
	shooter.rotation.y=PI;shooter.brain.heading=PI
	exact_projectile_fixture(shooter)
	shooter.cooldown = 0
	for i in 240:
		if facility.hp<100: break
		await step(1)
	check(facility.hp < 100 and pilot.health == pilot.maximum_health, "unguarded facility takes real hostile projectile damage")
	metrics.facility_hp_after_attack = facility.hp
	await setup()
	var charger = foe("charger",Vector3(0,5,-8),true)
	charger.attack_direction = Vector3.BACK
	charger.charge_left = 1.2
	wall(Vector3(0,5,-4),Vector3(12,8,0.15))
	await step(50)
	var relative_z: float = arena.to_local(charger.global_position).z
	var half_depth: float = (absf(charger.basis.x.z)*charger.dimensions.x+absf(charger.basis.y.z)*charger.dimensions.y+absf(charger.basis.z.z)*charger.dimensions.z)*.5
	var wall_near_face = -4.0-.15*.5
	metrics.charger_wall={"relative_z":relative_z,"charge_left":charger.charge_left,"forward_envelope_z":relative_z+half_depth,"wall_near_face_z":wall_near_face,"contact_tolerance_m":.03}
	check(relative_z+half_depth <= wall_near_face+.03 and charger.charge_left == 0, "charger swept body envelope stops at the near face of the thin wall")
	check(pilot.health == pilot.maximum_health, "charger cannot hurt pilot through intervening wall")
	await setup()
	var support = foe("support",Vector3(0,5,-5))
	var ally = foe("charger",Vector3(4,5,-5))
	ally.hp = 36
	await step(3)
	support.cooldown = 0
	support._physics_process(1.0 / 60.0)
	check(ally.hp == 38, "support healing clamps to recipient max HP")
	check(is_equal_approx(ally.hp,float(ally.damage_state.health)), "support repair synchronizes the authoritative damage snapshot")
	ally.hp = 20
	wall(Vector3(2,5,-5),Vector3(0.15,6,6))
	await step(3)
	support.cooldown = 0
	support._physics_process(1.0 / 60.0)
	check(ally.hp == 20, "support cannot heal through walls")
	ally.take_damage(-20)
	ally.take_damage(NAN)
	check(ally.hp == 20, "invalid damage cannot heal or poison foe health")

func test_objectives() -> void:
	await setup()
	combat.configure_objective({"boss_phase":1,"target_nodes":3},arena.to_global(Vector3(0,3.6,0)))
	await step(3)
	check(combat.target_nodes.size() == 3 and not combat.objective_complete(), "phase one creates three required destructible power nodes")
	var node = combat.target_nodes[0]
	combat.fire_bolt(pilot.global_position,node.global_position,30,true,pilot)
	await step(20)
	check(deaths.has("power_node") and combat.kills == 0 and combat.alive_count() == 0, "power node accepts physical shots without consuming wave kills")
	for power in combat.target_nodes:
		if is_instance_valid(power):power.take_damage(100)
	check(combat.objective_complete(), "power-node objective requires all nodes destroyed")
	combat.configure_objective({"boss_phase":2,"safe_window_s":4},arena.to_global(Vector3(0,5,0)))
	check(combat.target_nodes.is_empty() and combat.objective_complete() and combat.is_safe_window(), "delivery phase does not require simultaneous combat")
	await step(238)
	check(combat.is_safe_window() and warnings == 0, "delivery safe window lasts at least four full seconds")
	await step(5)
	check(not combat.is_safe_window() and warnings == 1, "low sweep has distinct pre-warning after safe window")
	var hp = pilot.health
	await step(60)
	check(pilot.health == hp, "low sweep causes no damage during its warning")
	await step(20)
	check(pilot.health < hp, "low sweep damage occurs only after warning")
	pilot.position.y = 7.0
	combat.objective_clock = 5.3
	combat._sweep_hit = false
	hp = pilot.health
	await step(10)
	check(pilot.health == hp, "climbing above sweep avoids its actual beam collision")
	combat.configure_objective({"boss_phase":3,"exposure_window_s":4},arena.global_position)
	check(not combat.objective_complete(), "empty boss list cannot falsely complete final phase")
	combat.spawn_wave(["boss"],arena.to_global(Vector3(0,1,0)))
	var boss = combat.enemies.back()
	boss.take_damage(1000)
	check(boss.hp == boss.max_hp, "boss rejects damage while protected")
	for i in 300:
		if boss.exposure_left>0: break
		await step(1)
	check(boss.exposure_left > 3.0 and boss.exposure_left <= 4.0, "boss opens at least four-second exposure after telegraphed attack")
	var boss_hp: float = boss.hp
	boss.take_damage(10)
	check(boss.hp == boss_hp - 10, "boss accepts damage in exposed window")
	boss.take_damage(1000)
	check(combat.objective_complete() and deaths.has("boss"), "final boss objective completes only after actual defeat")
	combat.configure_objective({},Vector3.ZERO)
	check(combat.boss_phase == 0 and combat.target_nodes.is_empty() and combat.objective_complete(), "ordinary action clears old objective state")

func test_projectile_pool() -> void:
	await setup()
	var shooter = foe("shooter",Vector3(0,5,-12),true)
	shooter.cooldown=0
	exact_projectile_fixture(shooter)
	check(await wait_warning(shooter), "pool retry fixture first acquires a real target through perception and reaction")
	check(shooter.attack_target!=null and shooter.attack_target.get_ref()==pilot and shooter.brain.seen, "pool retry retains the warning's actual sensed target")
	shooter.set_physics_process(false)
	for i in range(Combat.MAX_BOLTS):combat.fire_bolt(Vector3(0,50,0),Vector3(0,50,-50),1,true,pilot)
	check(combat.bolts.size() == Combat.MAX_BOLTS, "projectile pool has a fixed upper bound")
	check(not combat.fire_bolt(Vector3(0,50,0),Vector3(0,50,-50),1,true,pilot), "full pool rejects shot without unbounded allocation")
	var first = combat.bolts[0]
	first.deactivate()
	check(combat.fire_bolt(Vector3(0,50,0),Vector3(0,50,-50),1,false,pilot) and combat.bolts.size() == Combat.MAX_BOLTS, "inactive pooled projectile is reused across teams")
	check(combat._bolt_meshes.size() == 2, "all pooled projectiles share two cached meshes")
	var old_shots = hostile_shots
	shooter._physics_process(shooter.telegraph+1.0/60.0)
	check(shooter.telegraph > 0 and shooter.beam.visible and hostile_shots == old_shots, "full pool keeps enemy warning alive instead of discarding attack")
	first.deactivate()
	shooter._physics_process(0.2)
	check(hostile_shots == old_shots + 1 and not shooter.beam.visible, "delayed enemy shot is emitted when pool slot is released")
	for i in range(300): combat._record("shot",pilot,null,pilot.global_position)
	check(combat.events.size() == 256, "combat replay event history remains bounded")
	combat.clear_enemies()
	var active = 0
	for bolt in combat.bolts:
		if bolt.active: active += 1
	check(active == 0 and combat.charge == 0, "stage reset clears every active projectile and partial charge")
	metrics.max_allocated_projectiles = combat.bolts.size()

class Facility extends StaticBody3D:
	var hp = 100.0
	func _ready() -> void:
		collision_layer = 32
		var shape = CollisionShape3D.new()
		var box = BoxShape3D.new()
		box.size = Vector3(3,3,3)
		shape.shape = box
		add_child(shape)
	func take_damage(amount:float,_direction:Vector3=Vector3.ZERO)->void:
		hp = maxf(0,hp-amount)
