extends SceneTree

const Body=preload("res://scripts/v2/flight_body.gd")
const Pilot=preload("res://scripts/v2/pilot_input.gd")
const Profiles=preload("res://scripts/v2/profile_catalog.gd")
const Field=preload("res://scripts/v2/environment_field.gd")
const CameraRig=preload("res://scripts/v2/flight_camera.gd")
const Phone=preload("res://scripts/v2/phone_server.gd")
var failures: Array=[]
var checks=0
var arena: Node3D
var body: FlightBodyV2
var queried_cargo: RigidBody3D
var query_calls = 0
var query_separate_calls = 0
var query_windy_calls = 0
var query_max_position_error = 0.0
var query_max_separation = 0.0
var cargo_wind_ceiling = 0.0

func _initialize() -> void:call_deferred("run")
func check(value: bool, label: String) -> void:
	checks+=1
	if not value: failures.append(label)
	print("V22_CORE_", "PASS " if value else "FAIL ",label)
func steps(count: int) -> void:
	for i in range(count):await physics_frame
func reset_body(tool = "scan_base") -> void:
	if is_instance_valid(arena):arena.queue_free();await process_frame
	arena=Node3D.new();root.add_child(arena)
	GameVisuals.collider(arena,Vector3(0,-0.5,0),Vector3(300,1,300))
	var build = CatalogV2.default_build()
	build.slots.tool = tool
	body=Body.new();body.configure(CatalogV2.resolve_build(build))
	body.position=Vector3(0,8,0);body.hold_height=8
	body.command={"active":true,"body_relative":true,"mode":"assisted","pitch":0.0,"roll":0.0,"vertical":0.0,"yaw":0.0}
	arena.add_child(body);await steps(90)

func make_hook_cargo() -> RigidBody3D:
	var weight = 1.5
	var valid = bool(CatalogV2.resolve_build(body.build,weight).valid)
	check(valid,"TR01 hook plus 1.5kg box is a legal physical fixture")
	if not valid: return null
	var cargo = RigidBody3D.new()
	cargo.name = "ManualCollectiveCargo"
	cargo.mass = weight
	cargo.can_sleep = false
	cargo.position = body.position+Vector3.DOWN*1.1
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(0.4,0.4,0.4)
	collision.shape = shape
	cargo.add_child(collision)
	arena.add_child(cargo)
	check(body.attach_cargo(cargo,"core_manual_box",weight),"Cargo is attached through the real hook joint")
	return cargo

func manual_collective(value: float) -> Dictionary:
	return {"active":true,"body_relative":true,"mode":"manual_throttle","throttle":value,"pitch":0.0,"roll":0.0,"yaw":0.0,"vertical":0.0}

func cargo_local_field(point: Vector3) -> Dictionary:
	# A horizontal shear layer reaches the suspended box but not the aircraft.
	# Production physics, not this test driver, invokes the query at cargo position.
	query_calls += 1
	var separation = point.distance_to(body.global_position)
	query_max_separation = maxf(query_max_separation,separation)
	if separation > 0.5: query_separate_calls += 1
	if is_instance_valid(queried_cargo): query_max_position_error = maxf(query_max_position_error,point.distance_to(queried_cargo.global_position))
	var local_wind = Vector3(8,0,0) if point.y < cargo_wind_ceiling else Vector3.ZERO
	if local_wind.x > 0: query_windy_calls += 1
	return {"wind_velocity":local_wind,"density":1.225}

func test_manual_cargo() -> void:
	await reset_body("hook_base")
	var cargo = make_hook_cargo()
	if not is_instance_valid(cargo): return
	await steps(180)
	var empty_collective = body.mass*9.8/float(body.stats.thrust_n)
	var loaded_collective = (body.mass+cargo.mass)*9.8/float(body.stats.thrust_n)
	check(loaded_collective > empty_collective+0.02 and loaded_collective < 1.0,"Legal suspended cargo needs more collective with thrust headroom")
	var low_start = body.position.y
	body.command = manual_collective(empty_collective)
	await steps(90)
	var low_end = body.position.y
	var low_velocity = body.linear_velocity.y
	check(low_start-low_end > 0.7 and low_velocity < -0.5,"Loaded aircraft descends at the previously valid empty-aircraft hover throttle")
	check(low_end > 2.0 and body.position.is_finite() and cargo.position.is_finite(),"Lower-collective comparison remains airborne and bounded")
	# Recreate identical settled initial conditions, rather than erasing descent
	# velocity or allowing a hidden altitude controller to rescue the first run.
	await reset_body("hook_base")
	cargo = make_hook_cargo()
	if not is_instance_valid(cargo): return
	await steps(180)
	loaded_collective = (body.mass+cargo.mass)*9.8/float(body.stats.thrust_n)
	var balanced_start = body.position.y
	body.command = manual_collective(loaded_collective)
	var maximum_error = 0.0
	for tick in 180:
		await physics_frame
		maximum_error = maxf(maximum_error,absf(body.position.y-balanced_start))
	var balanced_end = body.position.y
	check(maximum_error < 0.5 and absf(body.linear_velocity.y) < 0.3,"Actual loaded force-balance collective holds within 0.5m for three seconds")
	check(balanced_end > low_end+0.7,"Higher loaded hover collective retains altitude lost by empty hover collective")
	check(is_equal_approx(float(body.telemetry.mass_kg),body.mass+cargo.mass),"Loaded manual telemetry counts the real suspended mass exactly once")
	var climb_start = body.position.y
	body.command.throttle = loaded_collective*1.15
	await steps(90)
	check(body.position.y > climb_start+0.3 and body.position.y < climb_start+4.0 and body.linear_velocity.y > 0.2,"A bounded collective increase lifts the real loaded aircraft")
	print("V22_CORE_CARGO_COLLECTIVE ",JSON.stringify({"cargo_kg":cargo.mass,"empty_collective":empty_collective,"loaded_collective":loaded_collective,"empty_throttle_start_y":low_start,"empty_throttle_end_y":low_end,"empty_throttle_velocity_y":low_velocity,"loaded_hover_start_y":balanced_start,"loaded_hover_end_y":balanced_end,"loaded_hover_max_error":maximum_error,"loaded_climb_y":body.position.y-climb_start}))
	await reset_body("hook_base")
	queried_cargo = make_hook_cargo()
	if not is_instance_valid(queried_cargo): return
	await steps(180)
	body.command = manual_collective((body.mass+queried_cargo.mass)*9.8/float(body.stats.thrust_n))
	body.environment_sample = {"wind_velocity":Vector3.ZERO,"density":1.225}
	cargo_wind_ceiling = body.global_position.y-0.55
	query_calls = 0; query_separate_calls = 0; query_windy_calls = 0
	query_max_position_error = 0.0; query_max_separation = 0.0
	var cargo_start = queried_cargo.global_position
	body.environment_query = cargo_local_field
	await steps(120)
	check(query_calls >= 100 and query_separate_calls == query_calls and query_max_separation > 0.5,"Cargo physics queries the local field every step at a point distinct from pilot position")
	check(query_max_position_error < 0.001 and query_windy_calls >= 90,"Field query receives the actual suspended box position in its own wind layer")
	check(Vector3(body.environment_sample.wind_velocity).is_zero_approx() and Vector3(body.telemetry.wind_velocity).is_zero_approx(),"Pilot remains in still air while cargo samples the separate windy layer")
	var cargo_drift = queried_cargo.global_position.x-cargo_start.x
	check(cargo_drift > 0.15 and cargo_drift < 5.0,"Cargo-only local wind produces bounded real box displacement")
	check(body.position.is_finite() and queried_cargo.position.is_finite() and body.position.y > 4 and queried_cargo.position.y > 2,"Independent cargo airflow keeps both connected bodies stable and airborne")
	print("V22_CORE_CARGO_FIELD ",JSON.stringify({"query_calls":query_calls,"separate_position_calls":query_separate_calls,"wind_layer_calls":query_windy_calls,"max_position_error_m":query_max_position_error,"max_pilot_separation_m":query_max_separation,"cargo_drift_m":cargo_drift}))

func run() -> void:
	var input=Pilot.new();root.add_child(input)
	check(input.legacy.config.axis_x==2 and input.legacy.config.axis_y==3 and input.legacy.config.axis_yaw==0 and input.legacy.config.axis_vertical==1,"USB defaults are Mode 2, matching phone")
	input.configure_input({"center":{"0":0.12},"device_bindings":{"key":{"yaw_left":KEY_V}},"axis_x":0,"axis_y":1})
	check(is_equal_approx(float(input.legacy.config.center["0"]),0.12) and input.legacy.config.device_bindings.key.yaw_left==KEY_V,"Mode 2 migration preserves calibration and custom buttons")
	input.active=true;input.take_control("phone");input.mode="manual_throttle"
	input.receive_phone({"axes":{"left_y":-0.3},"neutral":false})
	check(is_equal_approx(float(input.command(Basis.IDENTITY).throttle),0.35),"phone left vertical maps to collective")
	input.receive_phone({"neutral":true})
	check(is_equal_approx(float(input.command(Basis.IDENTITY).throttle),0.35),"neutral pause frame cannot jump manual throttle")
	input.queue_free()
	await reset_body()
	body.command.pitch=1.0;await steps(120)
	check(body.position.z < -3.0 and absf(body.position.x)<0.3,"forward follows initial nose")
	await reset_body()
	body.heading=PI/2;body.rotation.y=PI/2;body.command.pitch=1.0;await steps(120)
	check(body.position.x < -3.0 and absf(body.position.z)<0.5,"90-degree yaw redirects forward to new nose")
	await reset_body()
	body.command.yaw=1.0;await steps(90)
	check(absf(body.heading)>1.0,"left horizontal actually rotates heading")
	await reset_body()
	var hover=body.mass*9.8/float(body.stats.thrust_n)
	body.command={"active":true,"body_relative":true,"mode":"manual_throttle","throttle":hover,"pitch":0.0,"roll":0.0,"yaw":0.0,"vertical":0.0}
	await steps(120)
	check(absf(body.position.y-8.0)<0.35,"manual empty-frame hover uses actual force balance")
	body.command.throttle=0.0;await steps(60)
	check(body.position.y<5.0,"zero manual throttle falls; no hidden altitude controller")
	await test_manual_cargo()
	await reset_body()
	body.command={"active":true,"body_relative":true,"mode":"manual_throttle","throttle":body.mass*9.8/float(body.stats.thrust_n),"pitch":0.0,"roll":0.0,"yaw":0.0,"vertical":0.0}
	body.environment_sample={"wind_velocity":Vector3(8,0,0),"density":1.225};await steps(150)
	check(body.position.x>0.4 and float(body.telemetry.airspeed_mps)>1.0,"relative airflow produces physical drift and airspeed telemetry")
	body.sandbox_rules={"invincible":true};var hp=body.health;body.take_damage(30)
	check(body.health==hp,"sandbox invincibility affects damage only when enabled")
	body.sandbox_rules={};body.take_damage(10);check(body.health<hp,"turning invincibility off restores damage")
	var field=Field.new();field.configure("R2",42,{"environment_preset":"standard"})
	field.update_focus(Vector3(212,2,85))
	var waited=0.0
	while field.event_phase!="active" and waited<12:
		field.advance(0.1);waited+=0.1
	field.advance(1.0)
	var sample=field.sample(Vector3(212,2,85));check(Vector3(sample.wind_velocity).length()>1.0,"industrial fan has measurable airflow")
	field.fan_enabled=false;check(Vector3(field.sample(Vector3(212,2,85)).wind_velocity).length()<Vector3(sample.wind_velocity).length(),"fan switch reduces actual airflow")
	field.set_weather("rain");field.advance(10);check(field.sample(Vector3.ZERO).rain>0.3,"weather transitions produce rain field")
	var snapshot=field.snapshot();var clone=Field.new();clone.configure("R2",42,{});clone.restore(snapshot)
	check(field.sample(Vector3(220,4,80))==clone.sample(Vector3(220,4,80)),"restored weather and fan state replay deterministically")
	field.set_settings({"environment_wind":0.0,"environment_interference":0.0})
	check(Vector3(field.sample(Vector3(212,3,80)).wind_velocity).is_zero_approx() and float(field.sample(Vector3(212,3,80)).nav_quality)==1.0,"custom environment controls alter physics and sensing")
	await test_authored_water_and_bridges()
	var camera=Camera3D.new();arena.add_child(camera);var rig=CameraRig.new();rig.configure(camera);rig.snap(body.position)
	rig.zoom(100);check(rig.target_size==12.0,"close zoom is bounded")
	rig.zoom(-100);check(rig.target_size==70.0,"wide live zoom is bounded")
	rig.enter_overview(Vector2(1440,810));check(rig.overview and camera.size>500.0 and camera.far>1500,"whole-map camera fits full bounds beyond stream radius")
	rig.exit_overview(body.position);check(not rig.overview and camera.size==70.0,"leaving map restores previous live zoom")
	var prefix="user://qa_v22/core_"+str(Time.get_ticks_usec())
	var old=SaveRepositoryV2.new(prefix+"/old");old.load_profile();old.commit({"id":"fixture","parts_delta":321,"append":{"campaign.completed_missions":["M01"]}})
	var source_file=old.root_path.path_join(old._generation_files()[0]);var source_hash=FileAccess.get_sha256(source_file)
	var catalog=Profiles.new(prefix+"/new",ProjectSettings.globalize_path(old.root_path));catalog.initialize()
	var normal=catalog.open_profile("default");var free1=catalog.open_profile("free_01");var free2=catalog.open_profile("free_02")
	check(normal.data.wallet.parts==321 and "M01" in normal.data.campaign.completed_missions,"V2.1 profile migrates valid progression")
	check(FileAccess.get_sha256(source_file)==source_hash,"migration never modifies source save")
	check(free1.data.owned_airframes.size()==CatalogV2.airframes().size() and free1.data.owned_modules.size()==CatalogV2.modules().size(),"sandbox owns every aircraft and module")
	check(free1.data.campaign.completed_missions.is_empty(),"unlock rights do not fabricate mission completion")
	free1.commit({"id":"rename","set":{"settings.profile_name":"独立体验","settings.sandbox_rules.invincible":true}})
	check(not bool(free2.data.settings.sandbox_rules.invincible) and not bool(normal.data.settings.sandbox_rules.invincible),"sandbox rules are isolated across all profiles")
	catalog.select("free_01");catalog.initialize();check(catalog.selected=="free_01" and catalog.open_profile("free_01").data.settings.profile_name=="独立体验","restarting preserves chosen pilot and preferences")
	var phone=Phone.new();phone._controller={"peer":null,"violations":0};phone._state="TakingControl";phone.set_telemetry({"mode":"manual_throttle","resume_throttle":0.35})
	var now=Time.get_ticks_msec();phone._leases["test"]=now
	var frame={"schema":2,"control_epoch":0,"seq":1,"sample_ms":now,"axes":{"left_x":0.0,"left_y":0.0,"right_x":0.0,"right_y":0.0},"held":[],"edges":[],"context":"flight","neutral":false}
	phone._receive_input(phone._controller,{"frame":frame,"lease_nonce":"test"},now)
	check(not phone._neutral,"manual resume rejects unmatched physical throttle")
	frame.seq=2;frame.axes.left_y=-0.3;phone._receive_input(phone._controller,{"frame":frame,"lease_nonce":"test"},now)
	check(phone._neutral,"manual resume accepts matched throttle with other axes centered")
	phone.free();arena.queue_free();await process_frame
	print("V22_CORE_SUMMARY ",JSON.stringify({"checks":checks,"failures":failures,"ok":failures.is_empty(),"scope":"headless physics/input/save/environment only"}))
	quit(0 if failures.is_empty() else 1)

func test_authored_water_and_bridges() -> void:
	var water_world=RegionWorldV2.new();water_world.configure(CatalogV2.content().regions[0],false,{})
	# Separate physical space prevents the flight fixture's 300m floor masking water.
	var viewport=SubViewport.new();viewport.own_world_3d=true;root.add_child(viewport);viewport.add_child(water_world)
	for x in range(6):
		for z in range(5):water_world._load_chunk(Vector2i(x,z))
	await physics_frame;await physics_frame
	var space=water_world.get_world_3d().direct_space_state
	var water_level=float(water_world.layout.water_level)
	var bridges=0
	for road in water_world.layout.get("roads",[]):
		if not bool(road.get("bridge",false)):continue
		for i in range(road.points.size()-1):
			bridges+=1
			var a=road.points[i];var b=road.points[i+1]
			var point=Vector3((a[0]+b[0])*.5,(a[2]+b[2])*.5,(a[1]+b[1])*.5)
			var above=water_world.surface_at(point+Vector3.UP)
			var below=water_world.surface_at(point-Vector3.UP*.7)
			check(str(above.material)=="bridge" and not above.water and absf(float(above.height)-point.y)<.01,"authored bridge "+str(bridges)+" has the correct solid top surface")
			check(below.water and float(below.height)<water_level-1.0,"authored bridge "+str(bridges)+" exposes a real submerged bed beneath its deck")
			var top=space.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*2,point-Vector3.UP*.8,1))
			var bottom=space.intersect_ray(PhysicsRayQueryParameters3D.create(point-Vector3.UP*.7,Vector3(point.x,-4,point.z),1))
			check(not top.is_empty() and absf(top.position.y-point.y)<.08,"authored bridge "+str(bridges)+" physical collider matches the logical deck")
			check(not bottom.is_empty() and absf(bottom.position.y-float(below.height))<.08,"authored bridge "+str(bridges)+" downward query below deck reaches the physical bed")
			var across=Vector3(-(b[1]-a[1]),0,b[0]-a[0]).normalized()*(float(road.width)*.5+2.0)
			for frame_id in CatalogV2.airframes():
				var build=CatalogV2.default_build(str(frame_id));build.slots.utility="reinforced_guard"
				var resolved=CatalogV2.resolve_build(build)
				if not resolved.valid:continue
				var shape=BoxShape3D.new();shape.size=Vector3(resolved.derived.width_m,resolved.derived.height_m,resolved.derived.length_m)
				var center=Vector3(point.x,(water_level+point.y-.4)*.5,point.z)
				var query=PhysicsShapeQueryParameters3D.new();query.shape=shape;query.collision_mask=1|32
				query.transform=Transform3D(Basis.IDENTITY,center-across)
				var clear=space.intersect_shape(query,1).is_empty()
				query.transform.origin=center+across;clear=clear and space.intersect_shape(query,1).is_empty()
				query.transform.origin=center-across;query.motion=across*2
				var fractions=space.cast_motion(query)
				check(clear and center.y-shape.size.y*.5>water_level and fractions.size()==2 and fractions[0]>=.99999,"authored bridge "+str(bridges)+" permits a dry swept underpass for "+str(frame_id))
	check(bridges>=2,"R1 retains multiple physical canal crossings")
	viewport.queue_free();await process_frame;await physics_frame
