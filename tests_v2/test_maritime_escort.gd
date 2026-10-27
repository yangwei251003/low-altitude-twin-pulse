extends SceneTree
const Runner=preload("res://scripts/v2/task_runner.gd")
var failures: Array=[]
var checks=0
var world: RegionWorldV2
var runner: TaskRunnerV2
var pilot: FlightBodyV2
var combat: CombatV2
var traces: Array=[]
var scene: Node3D

func _initialize() -> void:call_deferred("run")
func expect(value: bool,label: String) -> void:
	checks+=1
	if not value:failures.append(label);printerr("MARITIME_FAIL "+label)

func run() -> void:
	scene=Node3D.new();root.add_child(scene)
	var content=CatalogV2.content()
	var region: Dictionary
	for candidate in content.regions:
		if candidate.id=="R3":region=candidate
	world=RegionWorldV2.new();world.configure(region,false,{});scene.add_child(world);world.set_physics_process(false)
	for x in 6:
		for z in 5:world._load_chunk(Vector2i(x,z))
	pilot=FlightBodyV2.new();pilot.configure(CatalogV2.resolve_build(CatalogV2.default_build()));pilot.freeze=true;pilot.enabled=true;scene.add_child(pilot);pilot.position=Vector3(20,45,20);pilot.set_physics_process(false)
	combat=CombatV2.new();combat.pilot=pilot;combat.navigation_world=world;scene.add_child(combat);combat.set_physics_process(false)
	runner=Runner.new();runner.pilot=pilot;runner.world=world;runner.combat=combat;scene.add_child(runner);runner.set_physics_process(false)
	await physics_frame;await physics_frame
	for id in ["R3-P02","R3-P11"]:
		var p=world.poi_position(id)
		expect(not world.surface_at(p+Vector3.UP).water,"relocated service/work POI has physical dry support "+id)
		var ray=PhysicsRayQueryParameters3D.create(p+Vector3.UP*2,p-Vector3.UP*.2,1)
		var hit=world.get_world_3d().direct_space_state.intersect_ray(ray)
		expect(not hit.is_empty() and absf(hit.position.y-p.y)<.08,"physical deck agrees with POI support "+id)
	var stages: Array=[]
	for mission in content.missions:
		if mission.id in ["M09","M12"]:
			for stage in mission.stages:
				for action in stage.actions:
					if action.type=="escort":stages.append({"id":stage.id,"action":action})
	expect(stages.size()==2,"both authored R3 vessel escorts are exercised")
	for fixture in stages:await check_route(fixture)
	# First M09 defend is the same floating maintenance craft, not a land cube.
	runner.stage={"id":"M09-S3"}
	var defend={"type":"defend","poi_id":"R3-P11"}
	var route=runner._water_route_for_action(defend)
	expect(not route.is_empty() and route.vessel=="maintenance_boat","M09 first defense resolves the departure boat berth")
	expect(runner._water_route_for_action({"type":"escort","escort_path":["R2-P22","R2-P15","R2-P21"]}).is_empty(),"R2 land escort keeps its separate existing navigation")
	print("MARITIME_SUMMARY "+JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures,"traces":traces,"scope":"Real RegionWorld geometry and TaskRunner water-route motion at 0.25s fixture steps; no mission completion, player flight, combat success or GPU appearance claim"}))
	runner.queue_free();combat.queue_free();pilot.queue_free();world.queue_free();await process_frame
	quit(0 if failures.is_empty() else 1)

func check_route(fixture: Dictionary) -> void:
	# Only the authored escort action is isolated; its content and stops are unchanged.
	runner.start_stage({"id":fixture.id,"actions":[fixture.action],"poi_ids":fixture.action.escort_path})
	await physics_frame;await physics_frame
	expect(not runner.pending and not runner.escort_water_route.is_empty(),fixture.id+" resolves an authored water route")
	if runner.pending or runner.escort_water_route.is_empty():return
	var vessel=runner.facility
	expect(vessel.has_node("PointedBoatHull") and not vessel.vessel_kind.is_empty(),fixture.id+" uses the distinct editable pointed vessel hull")
	var initial=vessel.global_position
	runner._advance_water_escort(.25,false)
	expect(vessel.global_position==initial and runner.escort_index==0,fixture.id+" departure berth waits for player interaction")
	runner._physics_process(.25)
	expect(vessel.global_position==initial,fixture.id+" absent escort pilot cannot move the boat")
	runner._advance_water_escort(.25,true)
	# A real obstacle introduced on the route must hold the boat, not teleport it.
	var blocker=GameVisuals.collider(world,initial+Vector3(-1.5,.7,0),Vector3(1,4,8))
	await physics_frame;await physics_frame
	runner._advance_water_escort(.25,true)
	expect(vessel.global_position==initial,fixture.id+" physical obstruction safely stops the boat")
	blocker.queue_free();await process_frame;await physics_frame
	var tick=0;var max_step=0.0;var min_shore=1000.0;var waited: Dictionary={};var finished=false
	while tick<2400 and not finished:
		var before=vessel.global_position
		finished=runner._advance_water_escort(.25,false)
		var after=vessel.global_position
		max_step=maxf(max_step,before.distance_to(after))
		expect(absf(after.y-(float(world.layout.water_level)+.25))<.0001,fixture.id+" vessel stays on waterline tick "+str(tick))
		var position2=Vector2(after.x,after.z)
		var dry=false
		for land in world.layout.land:
			var polygon=RegionLayoutWorldUI.polygon(land.points)
			dry=dry or Geometry2D.is_point_in_polygon(position2,polygon)
			for i in polygon.size():min_shore=minf(min_shore,position2.distance_to(Geometry2D.get_closest_point_to_segment(position2,polygon[i],polygon[(i+1)%polygon.size()])))
		expect(not dry,fixture.id+" boat center never crosses authored land tick "+str(tick))
		if runner.escort_index in runner.safe_stop_targets and runner.escort_index not in runner.escort_released_stops and after.distance_to(runner.escort_path[runner.escort_index])<.001:
			waited[runner.escort_index]=true
			runner._advance_water_escort(.25,false)
			expect(vessel.global_position==after,fixture.id+" safe berth waits only after actually arriving")
			runner._advance_water_escort(.25,true)
		await physics_frame
		tick+=1
	expect(finished,fixture.id+" reaches the actual destination water berth without relocation")
	expect(max_step<=.8001,fixture.id+" every motion step obeys the 3.2m/s speed bound")
	expect(min_shore>=3.4,fixture.id+" complete vessel corridor keeps clearance from shoreline")
	expect(vessel.global_position.distance_to(runner.escort_path[-1])<.001,fixture.id+" finishes at authored water berth, not service POI")
	if runner.safe_stop_targets.size()>1:expect(waited.has(runner.safe_stop_targets[1]),fixture.id+" middle safety stop is actually reached and released")
	var target=runner.target_position()
	expect(Vector2(target.x,target.z).distance_to(Vector2(vessel.global_position.x,vessel.global_position.z))<.001,fixture.id+" live mission target follows the vessel")
	traces.append({"stage_id":fixture.id,"ticks":tick,"max_step_m":max_step,"minimum_shore_clearance_m":min_shore,"end":[vessel.position.x,vessel.position.y,vessel.position.z],"waited_stops":waited.keys()})
	runner._cleanup_action();await process_frame;await physics_frame
