extends SceneTree
## Owner-run physics tests. No art import, external tools, files or GPU required.
const Brain=preload("res://scripts/v2/enemy_brain.gd")
const Director=preload("res://scripts/v2/encounter_director.gd")
var checks=0
var failures: Array[String]=[]
var arena: Node3D
var world: TestWorld
var combat: TestCombat
var player: TestPilot

class TestPilot extends CharacterBody3D:
	var enabled=true
	var health=100.0
	var maximum_health=100.0

class TestActor extends CharacterBody3D:
	var combat: Node3D
	var home=Vector3.ZERO
	var hp=48.0
	var max_hp=48.0
	var role="harasser"
	var brain: RefCounted

class TestWorld extends Node3D:
	var chunks: Dictionary={}
	var obstacles: Array=[]
	var region={"id":"R2","spawn_poi":"safe","pois":[{"id":"safe","position_xz_m":[150,50],"service_function":"repair"}]}

class TestCombat extends Node3D:
	var pilot: CharacterBody3D
	var facility: CollisionObject3D
	var enemies: Array=[]
	var spawn_calls=0
	func line_clear(from: Vector3,to: Vector3,source: RID,target: RID) -> bool:
		var ray=PhysicsRayQueryParameters3D.create(from,to,1|2|4|8|32,[source])
		var hit=get_world_3d().direct_space_state.intersect_ray(ray)
		return hit.is_empty() or hit.rid==target
	func spawn_patrol(roles: Array,entry: Vector3,_target: Vector3) -> Array:
		spawn_calls+=1
		var result: Array=[]
		for i in roles.size():
			var actor=TestActor.new();actor.combat=self;actor.role=str(roles[i]);actor.position=entry+Vector3(0,float(i)*2.5,0);actor.home=actor.position
			actor.collision_layer=4;actor.collision_mask=1|2|4|8|32
			var shape=CollisionShape3D.new();var sphere=SphereShape3D.new();sphere.radius=.85;shape.shape=sphere;actor.add_child(shape)
			add_child(actor);enemies.append(actor);result.append(actor)
			actor.brain=Brain.new();actor.brain.configure(actor,actor.role,35+i,true)
		return result

func _initialize() -> void: call_deferred("run")
func check(value: bool,label: String) -> void:
	checks+=1
	if not value: failures.append(label)
	print("V22_ENEMY_","PASS " if value else "FAIL ",label)
func frames(count=2) -> void:
	for i in count: await physics_frame
func box(point: Vector3,size: Vector3) -> StaticBody3D:
	var node=StaticBody3D.new();node.collision_layer=1
	var collision=CollisionShape3D.new();var shape=BoxShape3D.new();shape.size=size;collision.shape=shape
	node.add_child(collision);arena.add_child(node);node.position=point;return node
func setup() -> void:
	if is_instance_valid(arena): arena.queue_free();await process_frame
	arena=Node3D.new();root.add_child(arena)
	world=TestWorld.new();arena.add_child(world)
	box(Vector3(300,-.5,250),Vector3(600,1,500))
	for x in 6:
		for z in 5:
			var chunk=Node3D.new();world.add_child(chunk);world.chunks[Vector2i(x,z)]=chunk
	player=TestPilot.new();player.position=Vector3(200,6,184);player.collision_layer=2
	var shape=CollisionShape3D.new();var sphere=SphereShape3D.new();sphere.radius=.7;shape.shape=sphere;player.add_child(shape);arena.add_child(player)
	combat=TestCombat.new();arena.add_child(combat);combat.pilot=player
	await frames()
func actor(role="harasser",point=Vector3(200,6,200)) -> TestActor:
	return combat.spawn_patrol([role],point,point)[0]
func observe(brain: RefCounted,seconds: float) -> Dictionary:
	var result: Dictionary={}
	for i in ceili(seconds/.05): result=brain.step(.05)
	return result
func make_director(region="R2",seed_value=41) -> Node:
	var director=Director.new();arena.add_child(director);director.configure(combat,world,player,region,seed_value)
	director.set_physics_process(false);director.camera_guard=func(_point): return true
	director.advance(1.0)
	return director

func test_perception() -> void:
	await setup()
	var foe=actor();await frames()
	var brain=foe.brain
	var first=brain.step(.10)
	check(not first.can_attack,"First sight does not skip reaction time")
	var ready=observe(brain,1.2)
	check(ready.seen and ready.can_attack and ready.target==player,"Continuous FOV plus physical LOS eventually permits attack")
	check(ready.aim_position.distance_to(player.global_position)>.05,"Aim contains seeded finite error")
	var remembered: Vector3=brain.last_seen_position
	var wall=box(Vector3(200,6,192),Vector3(18,12,1));await frames()
	player.position=Vector3(205,6,184)
	var hidden=observe(brain,.4)
	check(not hidden.seen and not hidden.can_attack and hidden.target==null,"A real wall cancels target and attack permission")
	check(brain.last_seen_position.is_equal_approx(remembered),"Wall-hidden player movement does not update last observation")
	check(hidden.state=="search","Enemy searches old memory after losing sight")
	brain.hear_noise(Vector3(204,6,182),1.0)
	check(brain.last_seen_position.is_equal_approx(remembered) and brain.target==player,"Hearing keeps visual memory unchanged")
	observe(brain,11)
	check(brain.state in ["lost","patrol"] and not brain.seen,"Expired memory permits disengagement")
	wall.queue_free();await frames()
	player.position=Vector3(200,6,218)
	brain=Brain.new();brain.configure(foe,"harasser",42,true)
	check(not observe(brain,.4).seen,"A distant target behind the nose is outside the FOV")
	player.position=Vector3(200,6,184);brain.perception_visibility=func(_a,_b):return false
	check(not observe(brain,.4).seen,"Night illumination permission gates perception")
	brain.perception_visibility=func(_a,_b):return true
	check(observe(brain,1.5).seen,"Lighting plus LOS restores perception")
	foe.hp=8
	check(brain.step(.05).state=="retreat","Actual low durability triggers retreat")

func test_facility_and_report() -> void:
	await setup();player.position=Vector3(500,6,400)
	var facility=box(Vector3(200,6,184),Vector3(2,2,2));combat.facility=facility
	var foe=actor();await frames()
	var mission=Brain.new();mission.configure(foe,"harasser",11,false)
	check(observe(mission,1.3).target==facility,"Assigned mission facility can be perceived and attacked")
	var ambient=Brain.new();ambient.configure(foe,"harasser",11,true)
	check(observe(ambient,1.3).target==null,"Ambient patrol never inherits facility authorization")
	facility.queue_free();combat.facility=null;player.position=Vector3(200,6,184);await frames()
	var scout=Brain.new();scout.configure(foe,"scout",123,true)
	var reports=0
	for i in 120:
		var intent=scout.step(.05)
		if intent.report_ready: reports+=1
	check(reports==1 and scout.reported,"Scout has one report pulse only after sustained confirmation")
	var interrupted=Brain.new();interrupted.configure(foe,"scout",124,true)
	observe(interrupted,2.9)
	var barrier=box(Vector3(200,6,192),Vector3(18,12,1));await frames()
	var interrupted_reports=0
	for i in 20:
		if interrupted.step(.05).report_ready: interrupted_reports+=1
	check(interrupted_reports==0 and not interrupted.reported,"Breaking LOS during the call prevents scout transmission")
	barrier.queue_free();await frames()
	var saved=scout.snapshot();var restored=Brain.new();restored.configure(foe,"scout",99,true);restored.restore(saved)
	check(restored.snapshot().rng_state==saved.rng_state,"Brain restores exact RNG state without JSON integer rounding")
	check(not restored.seen and restored.reaction_time==0,"Restored memory must reacquire before another attack")
	var start=foe.velocity;var intent=restored.step(.05)
	check(intent.velocity.distance_to(start)<=float(restored.profile.accel)*.05+.0001,"Movement acceleration is bounded")
	check(absf(wrapf(intent.heading-float(saved.heading),-PI,PI))<=float(restored.profile.yaw)*.05+.0001,"Yaw does not snap instantly")

func test_collision_route() -> void:
	await setup();player.position=Vector3(500,6,400)
	box(Vector3(200,6,190),Vector3(10,12,2))
	world.obstacles=[{"x":200.0,"z":190.0,"w":10.0,"l":2.0,"h":12.0}]
	var foe=actor("harasser",Vector3(200,6,200));foe.brain.navigation_world=world;foe.brain.set_patrol_target(Vector3(200,6,170))
	await frames()
	var crossed_wall=false;var largest_speed=0.0;var turned=false
	for i in 300:
		var result=foe.brain.step(1.0/60)
		foe.velocity=result.velocity;foe.rotation.y=result.heading;foe.move_and_slide()
		largest_speed=maxf(largest_speed,foe.velocity.length());turned=turned or absf(foe.position.x-200)>1.5
		if absf(foe.position.x-200)<4.0 and absf(foe.position.z-190)<1.8 and foe.position.y<12.8: crossed_wall=true
		await physics_frame
	check(not crossed_wall,"Physical movement never crosses the wall volume")
	check(turned,"Blocked corridor produces a lateral avoidance route")
	check(largest_speed<=float(foe.brain.profile.speed)+.05,"Avoidance preserves speed limit")

func test_director() -> void:
	await setup();player.position=Vector3(210,5,80)
	var director=make_director()
	var entries=director.legal_entries()
	check(not entries.is_empty(),"Loaded industrial roads offer genuine collision-tested entries")
	var legal=true
	for entry in entries:
		legal=legal and Vector2(entry.position.x-player.position.x,entry.position.z-player.position.z).length()>=45
		legal=legal and Vector2(entry.position.x-150,entry.position.z-50).length()>=22
	check(legal,"Every candidate respects player distance and service exclusion")
	director.camera_guard=func(_point):return false
	check(director.legal_entries().is_empty(),"Visible camera coverage cannot be overridden by darkness")
	director._plan(false,Vector3.INF,"")
	check(director.pending.is_empty() and combat.spawn_calls==0,"No legal entry postpones instead of near-pop fallback")
	director.camera_guard=func(_point):return true
	var saved_chunks=world.chunks.duplicate();world.chunks.clear()
	check(director.legal_entries().is_empty(),"Unloaded collision chunks cannot host entry")
	world.chunks=saved_chunks
	director._plan(false,Vector3.INF,"")
	check(not director.pending.is_empty() and director.pending.roles[0]=="scout","Industrial plan starts with its scouting role")
	var planned=director.snapshot();var sequence_before=director.sequence
	director.advance(12)
	check(combat.spawn_calls==1 and director.registry.size() in [1,2],"Virtual corridor plan materializes through spawn_patrol")
	var id_ok=true
	for enemy in combat.enemies:
		id_ok=id_ok and str(enemy.get_meta("unit_id","")).begins_with("R2-E") and not bool(enemy.get_meta("allow_facility_target",true))
	check(id_ok,"Environment units have stable ownership and no facility permission")
	check(director.sequence==sequence_before,"Entry retries do not reroll encounter identity")
	director.set_context({"mission_reserved":8})
	check(director._budget_available()==0,"Mission reservation takes precedence over ambient budget")
	director.set_context({"mission_reserved":0});player.health=20
	director.advance(.5)
	check(director.rest_left>=45 and director.pending.is_empty(),"Low health preserves a recovery interval")
	player.health=100
	var hit={"event_id":"damage_once","kind":"damage_receipt","target_is_player":true,"actual_damage":10}
	director.note_event(hit);var pressure=director.load_pressure;director.note_event(hit)
	check(is_equal_approx(pressure,director.load_pressure),"Repeated receipt is counted once")
	director.set_suppressed(true);var previous_calls=combat.spawn_calls;director.advance(120)
	check(combat.spawn_calls==previous_calls,"Suppressed tutorial/required combat produces no new patrol")
	var restored=make_director();restored.restore(planned)
	check(restored.snapshot().rng_state==planned.rng_state and restored.sequence==planned.sequence,"Director restores exact RNG and stable encounter serial")
	check(restored.pending.entry==Director._point(planned.pending.entry,Vector3.ZERO) and is_equal_approx(restored.pending.eta,planned.pending.eta),"Pending entrance and ETA survive snapshot without reroll")
	for region in ["R1","R2","R3","R4"]:
		var a=make_director(region,20261015);var b=make_director(region,9);b.restore(a.snapshot())
		var same=true
		for i in 12: same=same and is_equal_approx(a._new_gap(),b._new_gap())
		check(same,region+" seeded future rest intervals reproduce after save")
		check(a._profile.roles.size()>=2 and a._profile.gap_min>=45,region+" has distinct role mix and meaningful quiet interval")
		var before=a.time_s;paused=true;a.advance(2);paused=false
		check(is_equal_approx(a.time_s,before),region+" pause never advances the director clock")
	var slow=make_director("R2",71);var fast=make_director("R2",71)
	slow.set_suppressed(true);fast.set_suppressed(true)
	for i in 300: slow.advance(1.0/30)
	for i in 1200: fast.advance(1.0/120)
	check(is_equal_approx(slow.time_s,fast.time_s) and is_equal_approx(slow.rest_left,fast.rest_left),"30/120 Hz inputs share fixed director scheduling time")

func test_director_report() -> void:
	await setup();player.position=Vector3(210,5,80)
	var director=make_director();director._plan(false,Vector3.INF,"");director.advance(12)
	check(not combat.enemies.is_empty(),"Scout-report fixture materializes a real patrol")
	if combat.enemies.is_empty(): return
	var scout: TestActor=combat.enemies[0]
	player.global_position=scout.global_position+Vector3(0,0,-14);await frames()
	observe(scout.brain,3.8)
	var report={"event_id":"report_good","kind":"enemy_report","source_id":str(scout.get_meta("unit_id")),"reported_position":Director._vec(scout.brain.last_seen_position)}
	director.note_event(report)
	check(not director.pending.is_empty() and director.pending.source_kind=="reinforcement","A completed visual scout report can authorize one distant reinforcement")
	var serial=director.sequence
	report.event_id="report_repeat";director.note_event(report)
	check(director.sequence==serial,"One encounter cannot request endless reinforcements")
	director.pending.clear();director._reported_encounters.clear();scout.hp=0
	report.event_id="report_dead";director.note_event(report)
	check(director.pending.is_empty(),"Destroyed scout cannot report even before its node is freed")
	scout.hp=48
	box((scout.global_position+player.global_position)*.5,Vector3(18,14,1));await frames()
	observe(scout.brain,.3);report.event_id="report_hidden";director.note_event(report)
	check(director.pending.is_empty(),"A stale wall-hidden observation cannot authorize reinforcement")

func run() -> void:
	await test_perception();await test_facility_and_report();await test_collision_route();await test_director();await test_director_report()
	finish("enemy_brain_and_director")
func finish(suite: String) -> void:
	print("V22_ENEMY_REPORT ",JSON.stringify({"suite":suite,"checks":checks,"failures":failures,"ok":failures.is_empty(),"evidence_scope":"Real physics queries plus deterministic scheduling tests; not rendered gameplay or physical device evidence."}))
	if is_instance_valid(arena): arena.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
