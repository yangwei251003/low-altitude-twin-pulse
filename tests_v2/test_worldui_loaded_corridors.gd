extends SceneTree
## Actual 60 Hz rigid bodies, production cargo/joint and authored world.
## No GameSession, player save, combat, normal task completion or visual evidence.

const World = preload("res://scripts/v2/region_world.gd")
const Flight = preload("res://scripts/v2/flight_body.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
const FRAMES = ["tr01","hx02","ag03","nx04","sh05","at06"]
const MARGIN = 0.10
const SEPARATION = 2.75
const SIDE_OFFSET = 0.85
const SPEED = 4.0
const LOADED_CLEARANCE = 6.0 # Same support-relative cruise clearance as the window probe.
const ROUTES = [
	{"id":"R1_dock_supply_approach","name":"研发楼南侧—入港补给台服务进出段","region":"R1","road":0,"segment":1,"kind":"service","pois":["R1-P01","R1-P02"]},
	{"id":"R1_low_bridge_deck_midspan","name":"入港补给桥桥上中段","region":"R1","road":2,"segment":0,"kind":"bridge","pois":["R1-P02"]},
	{"id":"R1_high_bridge_deck_midspan","name":"花园—东岸桥桥上中段","region":"R1","road":3,"segment":0,"kind":"bridge","pois":["R1-P10"]},
	{"id":"R2_valley_service_approach","name":"谷口起降场服务进出段","region":"R2","road":0,"segment":0,"kind":"service","pois":["R2-P01"]},
	{"id":"R3_south_harbor_service_approach","name":"南湾补给港服务进出段","region":"R3","road":0,"segment":0,"kind":"service","pois":["R3-P01"]},
	{"id":"R4_west_gate_service_approach","name":"西门前哨服务进出段","region":"R4","road":0,"segment":0,"kind":"service","pois":["R4-P01"]}
]

class CargoFactory extends "res://scripts/v2/task_runner.gd":
	# Reuse _spawn_cargo unchanged; this fixture does not run mission or combat code.
	func _ready() -> void:
		set_physics_process(false)

var output_root = ""
var regions = ["R1","R2","R3","R4"]
var checks = 0
var failures: Array = []
var cases: Array = []
var under_bridge_diagnostics: Array = []
var source_before: Dictionary = {}
var started_ms = 0
var timed_out = false
var arena: Node3D
var world: RegionWorldV2
var fixture: Node3D
var body: FlightBodyV2
var cargo: RigidBody3D
var cargo_shape: CollisionShape3D
var state: Dictionary = {}

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--loaded-output="): output_root=argument.trim_prefix("--loaded-output=").replace("\\","/")
		if argument.begins_with("--loaded-region="): regions=[argument.trim_prefix("--loaded-region=")]
	var allowed=OS.get_environment("TEMP").replace("\\","/").trim_suffix("/")+"/"
	if DisplayServer.get_name()!="headless" or not output_root.is_absolute_path() or not output_root.to_lower().begins_with(allowed.to_lower()) or DirAccess.dir_exists_absolute(output_root):
		printerr("Requires headless and a fresh absolute --loaded-output directory inside TEMP.");quit(2);return
	for region in regions:
		if region not in ["R1","R2","R3","R4"]: printerr("Unknown loaded region");quit(2);return
	if DirAccess.make_dir_recursive_absolute(output_root)!=OK: printerr("Cannot create evidence directory");quit(2);return
	Engine.physics_ticks_per_second=60
	started_ms=Time.get_ticks_msec();source_before=_hashes()
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks+=1
	if not value: failures.append(label);printerr("LOADED_FAIL "+label)

func _hashes() -> Dictionary:
	var result: Dictionary={}
	for path in ["res://scripts/v2/flight_body.gd","res://scripts/v2/task_runner.gd","res://scripts/v2/catalog.gd","res://scripts/v2/region_world.gd","res://scripts/v2/region_layout.gd","res://scripts/v2/worldui_builder.gd","res://data/v2/world_content.json","res://data/worldui/R1.json","res://data/worldui/R2.json","res://data/worldui/R3.json","res://data/worldui/R4.json"]: result[path]=FileAccess.get_sha256(path)
	result["driver"]=FileAccess.get_sha256(get_script().resource_path)
	return result

func run() -> void:
	var content: Dictionary=Catalog.content()
	for region_id in regions:
		var region: Dictionary={}
		for item in content.regions:
			if str(item.id)==region_id: region=item;break
		check(not region.is_empty(),"Region exists: "+str(region_id))
		if region.is_empty(): continue
		var assets_ok=true
		var seen_assets: Dictionary={}
		for structure in RegionLayoutWorldUI.get_layout(str(region_id)).structures:
			var asset=str(structure.asset)
			if seen_assets.has(asset): continue
			seen_assets[asset]=true
			var path="res://assets/models/worldui/"+asset+".glb"
			var imported=load(path) if ResourceLoader.exists(path) else null
			check(imported is PackedScene,"Required imported world model "+asset)
			assets_ok=assets_ok and imported is PackedScene
		if not assets_ok: continue
		arena=Node3D.new();root.add_child(arena)
		world=World.new();world.configure(region,false,{"layout_revision":1});arena.add_child(world)
		# Same full geometry coverage as test_worldui_physics; no unloaded obstacles.
		for x in range(6):
			for z in range(5): world._load_chunk(Vector2i(x,z))
		await physics_frame;await physics_frame
		for spec in ROUTES:
			if str(spec.region)!=region_id: continue
			var route=_route(spec)
			for frame_id in FRAMES:
				if timed_out: break
				await _case(str(frame_id),route)
			if timed_out: break
		arena.queue_free();await process_frame;await physics_frame
		if timed_out: break
	var expected=0
	for spec in ROUTES:
		if str(spec.region) in regions: expected+=FRAMES.size()
	check(cases.size()==expected,"Every selected frame/corridor combination has a result")
	check(not timed_out,"Wall budget 360 seconds was not exceeded")
	var source_after=_hashes()
	check(source_before==source_after,"Source fingerprints unchanged during run")
	var report={"suite":"worldui_loaded_corridors","checks":checks,"failed":failures.size(),"failures":failures,"cases":cases,"expected_cases":expected,"under_bridge_diagnostics":under_bridge_diagnostics,"engine":Engine.get_version_info().string,"physics_hz":Engine.physics_ticks_per_second,"physics_engine":ProjectSettings.get_setting("physics/3d/physics_engine"),"wall_seconds":float(Time.get_ticks_msec()-started_ms)/1000.0,"source_before":source_before,"source_after":source_after,"scope":"Actual 60 Hz FlightBody forces, production TaskRunner cargo shape and physical PinJoint3D. Synthetic assisted commands at 4 m/s and authored regional service approach / bridge-midspan samples, maximum nominal frame payload in a checked legal hook_base build. Long allowed pickup geometry is a preattached fixture, not proof of pickup input predicates. Exact transformed shape margin/contact/water checks at every physics sample. No save writes, task completion, full route certification, all module combinations, weather/traffic/combat, human comfort, controller or GPU evidence. Bridge underside records are geometry diagnostics only, never a loaded-pass claim."}
	var file=FileAccess.open(output_root.path_join("report.json"),FileAccess.WRITE)
	if file==null: printerr("Cannot write loaded report");quit(2);return
	file.store_string(JSON.stringify(report,"\t",true,true));file.flush()
	var error=file.get_error();file.close()
	print("LOADED_SUMMARY "+JSON.stringify({"checks":checks,"failed":failures.size(),"cases":cases.size(),"report":output_root.path_join("report.json"),"write_error":error}))
	quit(0 if failures.is_empty() and error==OK else 1)

func _route(spec: Dictionary) -> Dictionary:
	var road: Dictionary=world.layout.roads[int(spec.road)]
	var aa: Array=road.points[int(spec.segment)];var bb: Array=road.points[int(spec.segment)+1]
	var a=Vector3(float(aa[0]),0,float(aa[1]));var b=Vector3(float(bb[0]),0,float(bb[1]))
	var along=(b-a).normalized();var span=minf(24.0,a.distance_to(b)-8.0)
	var center=(a+b)*.5 if str(spec.kind)=="bridge" else a+along*(4.0+span*.5)
	var start=center-along*span*.5;var end=center+along*span*.5
	var top=-INF
	for j in range(25):
		# Include the braking overrun when choosing this fixed flight altitude.
		var point=start.lerp(end+along*8.0,float(j)/24.0)
		top=maxf(top,world.surface_height(point))
	start.y=top+LOADED_CLEARANCE;end.y=start.y
	var result=spec.duplicate(true)
	result.merge({"start":start,"end":end,"along":along,"width":float(road.width),"length":span,"altitude":start.y,"authored_road_points":[aa,bb]})
	if str(spec.kind)=="bridge":
		var deck=(float(aa[2])+float(bb[2]))*.5
		var support=maxf(world.terrain_height(center),float(world.layout.water_level))
		for frame_id in FRAMES:
			var frame: Dictionary=Catalog.airframes()[frame_id]
			var minimum_vertical_group=SEPARATION+.25+float(frame.height_m)*.5+2.0*MARGIN
			under_bridge_diagnostics.append({"route":spec.id,"frame":frame_id,"center":_vec(center),"available_height_m":deck-.4-support,"upright_long_hang_group_plus_margin_m":minimum_vertical_group,"upright_geometry_fits":deck-.4-support>=minimum_vertical_group,"not_a_dynamic_clearance_pass":true})
	return result

func _command(planar=Vector3.ZERO,brake=false) -> Dictionary:
	return {"active":true,"mode":"assisted","planar":planar,"vertical":0.0,"yaw":0.0,"pitch":0.0,"roll":0.0,"brake":brake}

func _case(frame_id: String, route: Dictionary) -> void:
	fixture=Node3D.new();arena.add_child(fixture)
	var build=Catalog.default_build(frame_id);build.slots.tool="hook_base"
	var weight=float(Catalog.airframes()[frame_id].cargo_rating_kg)
	var resolved=Catalog.resolve_build(build,weight)
	var label=frame_id+" / "+str(route.id)
	check(bool(resolved.valid),label+" rated payload is a legal actual Catalog build")
	if not bool(resolved.valid):
		cases.append({"label":label,"blocked":"illegal_rated_build","errors":resolved.errors});fixture.queue_free();await process_frame;return
	body=Flight.new();body.configure(resolved);body.position=route.start;body.hold_height=float(route.altitude)
	body.heading=atan2(-float(route.along.x),-float(route.along.z));body.rotation.y=body.heading;body.command=_command()
	fixture.add_child(body)
	var factory=CargoFactory.new();fixture.add_child(factory)
	var side=Vector3(-float(route.along.z),0,float(route.along.x))
	var cargo_start: Vector3=body.global_position+Vector3.DOWN*SEPARATION+side*SIDE_OFFSET
	factory._spawn_cargo("rated",{"mass_kg":weight,"home":_vec(cargo_start),"state":"available"})
	cargo=factory.cargo["rated"];cargo_shape=cargo.get_child(0)
	var attached=body.attach_cargo(cargo,"rated",weight)
	check(attached,label+" production physical cargo joint attaches")
	if not attached: cases.append({"label":label,"blocked":"attach_rejected"});fixture.queue_free();await process_frame;return
	state={"label":label,"frame":frame_id,"payload_kg":weight,"legal_build":build,"route_id":route.id,"route_name":route.name,"route_start":_vec(route.start),"route_end":_vec(route.end),"route_width_m":route.width,"initial_vertical_separation_m":SEPARATION,"initial_lateral_offset_m":SIDE_OFFSET,"margin_m":MARGIN,"samples":0,"peak_swing_deg":0.0,"max_joint_center_distance_m":0.0,"minimum_cargo_support_gap_m":INF,"max_lateral_extent_m":0.0,"faults":[],"trace":[]}
	await _phase(180,_command(),route,"settle")
	var flight_start: Vector3=body.global_position
	var cruise=Vector3(route.along)*SPEED/float(body.stats.speed_mps)
	var moving_ticks=0
	while moving_ticks<1200 and not timed_out and state.faults.is_empty():
		body.command=_command(cruise)
		await physics_frame;_observe(route,"flight");moving_ticks+=1
		if (body.global_position-flight_start).dot(Vector3(route.along))>=float(route.length): break
	state["flight_displacement_m"]=(body.global_position-flight_start).dot(Vector3(route.along))
	state["speed_before_brake_mps"]=_speed()
	var brake_start: Vector3=body.global_position
	await _phase(240,_command(Vector3.ZERO,true),route,"brake")
	state["speed_after_4s_brake_mps"]=_speed()
	state["braking_distance_m"]=Vector2(body.global_position.x-brake_start.x,body.global_position.z-brake_start.z).length()
	await _phase(120,_command(),route,"settle_after_brake")
	state["final_swing_deg"]=body.cargo_swing();state["damage_taken"]=body.damage_taken
	check(state.faults.is_empty(),label+" no physical overlap/contact/water or nonfinite state")
	check(float(state.flight_displacement_m)>=float(route.length)-.1,label+" actually traversed the declared approach segment")
	check(float(state.speed_before_brake_mps)>1.0,label+" braking began from meaningful loaded movement")
	check(float(state.speed_after_4s_brake_mps)<.5,label+" loaded brake settles below 0.5 m/s within four seconds")
	check(float(state.peak_swing_deg)>.1 and is_finite(float(state.final_swing_deg)),label+" physical swing exercised and remains finite")
	check(float(state.final_swing_deg)<=25.0,label+" residual swing reaches default delivery tolerance after six seconds")
	check(float(state.max_lateral_extent_m)<=float(route.width)*.5-MARGIN,label+" actual tilted body and swinging box stay within named corridor width")
	check(is_instance_valid(body.cargo_joint) and is_equal_approx(body.cargo_kg,weight),label+" rated load remains physically attached")
	check(float(state.max_joint_center_distance_m)<3.10,label+" physical joint does not stretch beyond the initial legal geometry")
	check(is_equal_approx(float(body.telemetry.get("mass_kg",0)),body.mass+weight),label+" load mass is counted once")
	cases.append(state.duplicate(true));print("LOADED_CASE "+JSON.stringify({"label":label,"samples":state.samples,"faults":state.faults,"swing_peak":state.peak_swing_deg,"brake_speed":state.speed_after_4s_brake_mps}))
	fixture.queue_free();await process_frame;await physics_frame

func _phase(ticks: int, command_value: Dictionary, route: Dictionary, phase: String) -> void:
	body.command=command_value
	for tick in range(ticks):
		if timed_out or not state.faults.is_empty(): return
		await physics_frame;_observe(route,phase)

func _fault(message: String) -> void:
	if message not in state.faults: state.faults.append(message)

func _observe(route: Dictionary, phase: String) -> void:
	if Time.get_ticks_msec()-started_ms>360000: timed_out=true;_fault("wall_budget");return
	state.samples=int(state.samples)+1
	if not body.global_position.is_finite() or not cargo.global_position.is_finite() or not body.linear_velocity.is_finite() or not cargo.linear_velocity.is_finite(): _fault("nonfinite_physics");return
	state.peak_swing_deg=maxf(float(state.peak_swing_deg),body.cargo_swing())
	state.max_joint_center_distance_m=maxf(float(state.max_joint_center_distance_m),body.global_position.distance_to(cargo.global_position))
	var envelope: CollisionShape3D=body.get_node("Envelope")
	for shape_node in [envelope,cargo_shape]:
		var query=PhysicsShapeQueryParameters3D.new();query.shape=shape_node.shape;query.transform=shape_node.global_transform;query.margin=MARGIN;query.collision_mask=1|32
		var hits=body.get_world_3d().direct_space_state.intersect_shape(query,1)
		if not hits.is_empty(): _fault(("cargo" if shape_node==cargo_shape else "body")+"_clearance:"+str(hits[0].collider.name))
		var half: Vector3=shape_node.shape.size*.5
		for x in [-1.0,1.0]:
			for y in [-1.0,1.0]:
				for z in [-1.0,1.0]:
					var vertex: Vector3=shape_node.global_transform*Vector3(half.x*x,half.y*y,half.z*z)
					var side=Vector3(-float(route.along.z),0,float(route.along.x))
					state.max_lateral_extent_m=maxf(float(state.max_lateral_extent_m),absf((vertex-Vector3(route.start)).dot(side)))
					if shape_node==cargo_shape:
						var support: Dictionary=world.surface_at(vertex)
						var height=maxf(float(support.height),float(world.layout.water_level)) if bool(support.water) else float(support.height)
						state.minimum_cargo_support_gap_m=minf(float(state.minimum_cargo_support_gap_m),vertex.y-height)
						if bool(support.water) and vertex.y-height<MARGIN: _fault("cargo_water_clearance")
	for actor in [body,cargo]:
		for other in actor.get_colliding_bodies():
			if other is CollisionObject3D and (other.collision_layer & (1|32))!=0: _fault("world_contact:"+str(other.name))
	if int(state.samples)%6==0 or not state.faults.is_empty(): state.trace.append({"tick":Engine.get_physics_frames(),"phase":phase,"body":_vec(body.global_position),"cargo":_vec(cargo.global_position),"speed_mps":_speed(),"swing_deg":body.cargo_swing()})

func _speed() -> float:
	return Vector2(body.linear_velocity.x,body.linear_velocity.z).length()

func _vec(point: Vector3) -> Array:
	return [point.x,point.y,point.z]
