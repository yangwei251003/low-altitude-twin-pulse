extends SceneTree

const Body = preload("res://scripts/v2/flight_body.gd")
const Pilot = preload("res://scripts/v2/pilot_input.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
var failures: Array = []
var checks = 0
var measurements: Dictionary = {}
var arena: Node3D
var body: RigidBody3D
var events: Array = []
var run_started: int
var render_fps = 60
var report_suffix = "summary"
var write_report = true

func _initialize() -> void:
	run_started = Time.get_ticks_msec()
	for arg in OS.get_cmdline_user_args():
		if arg == "--no-report": write_report = false
		if arg in ["--render-fps=30", "--render-fps=60", "--render-fps=120"]:
			render_fps = int(arg.get_slice("=",1))
			report_suffix = str(render_fps)
	Engine.physics_ticks_per_second = 60
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	checks += 1
	print("FLIGHT_V2_", "PASS " if condition else "FAIL ", description)
	if not condition:failures.append(description)

func command(planar: Vector3 = Vector3.ZERO, vertical: float = 0.0, brake: bool = false) -> Dictionary:
	return {"active":true, "mode":"assisted", "planar":planar, "vertical":vertical, "yaw":0.0, "pitch":0.0, "roll":0.0, "brake":brake}

func step(count: int) -> void:
	for index in range(count):await physics_frame

func make_box(parent: Node3D, position: Vector3, size: Vector3, dynamic: bool = false):
	var node = RigidBody3D.new() if dynamic else StaticBody3D.new()
	node.position = position
	node.collision_layer = 1
	var shape_node = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = size
	shape_node.shape = shape
	node.add_child(shape_node)
	parent.add_child(node)
	return node

func setup(frame_id: String, height: float = 3.0, tool: String = "scan_base") -> void:
	if is_instance_valid(arena):
		arena.queue_free()
		await process_frame
		await physics_frame
	arena = Node3D.new()
	root.add_child(arena)
	make_box(arena, Vector3(0,-0.2,0), Vector3(500,0.4,500))
	var build = Catalog.default_build(frame_id)
	build.slots.tool = tool
	var resolved = Catalog.resolve_build(build)
	check(resolved.valid, frame_id + " test assembly is legal")
	body = Body.new()
	body.position = Vector3(0,height,0)
	body.configure(resolved)
	body.hold_height = height
	body.command = command()
	arena.add_child(body)
	events = []
	body.collision_event.connect(func(event):events.append(event.duplicate(true)))
	await step(120)

func run() -> void:
	var body_script: Script = Body
	if not body_script.can_instantiate():
		printerr("FLIGHT_V2_DEPENDENCY_ERROR: import the project class registry before running this suite")
		quit(2)
		return
	await test_input()
	await test_motion("tr01")
	await test_motion("hx02")
	check(measurements.hx02.mass_kg > measurements.tr01.mass_kg, "HX is physically heavier than TR")
	check(measurements.tr01.speed_after_2s > measurements.hx02.speed_after_2s, "TR and HX have distinct acceleration responses")
	await test_advanced_tilt()
	await test_cargo("tr01")
	await test_cargo("hx02")
	await test_multiple_cargo()
	await test_cargo_damping()
	await test_collisions()
	await test_contact_world_coordinates()
	await test_landing("tr01")
	await test_landing("hx02")
	await test_ag03_ability()
	await test_searchlight_swap()
	await test_environment_force()
	if is_instance_valid(arena):arena.queue_free()
	await process_frame
	var summary = {"suite":"flight_v2", "engine":Engine.get_version_info().string, "physics_hz":Engine.physics_ticks_per_second, "headless_fixed_render_step_fps":render_fps, "physics_engine":ProjectSettings.get_setting("physics/3d/physics_engine"), "elapsed_wall_ms":Time.get_ticks_msec()-run_started, "checks":checks, "failures":failures, "ok":failures.is_empty(), "measurements":measurements, "evidence_scope":"Headless actual rigid-body physics and synthetic input only. Not GUI, GPU performance, controller hardware, phone touch, or human comfort evidence."}
	var report_path = "res://artifacts/v2/flight_physics_" + report_suffix + ".json"
	if write_report:
		DirAccess.make_dir_recursive_absolute("res://artifacts/v2")
		var file = FileAccess.open(report_path, FileAccess.WRITE)
		if file == null:
			printerr("Cannot write flight report")
			quit(2)
			return
		file.store_string(JSON.stringify(summary,"\t",true,true))
		file.close()
	print("FLIGHT_V2_SUMMARY ", JSON.stringify(summary))
	quit(0 if failures.is_empty() else 1)

func test_input() -> void:
	var pilot = Pilot.new()
	root.add_child(pilot)
	pilot.active = true
	pilot.test_enabled = true
	pilot.test_frame = {"axes":{"left_x":NAN,"left_y":INF,"right_x":5,"right_y":-3},"held":[],"edges":[]}
	var frame = pilot.sample()
	check(frame.axes.left_x == 0.0 and frame.axes.left_y == 0.0 and frame.axes.right_x == 1.0 and frame.axes.right_y == -1.0, "input axes reject nonfinite values and clamp")
	var cmd = pilot.command(Basis.IDENTITY)
	check(cmd.planar.is_finite() and is_equal_approx(cmd.planar.length(),1.0), "diagonal movement is normalized")
	pilot.test_frame = {"edges":[{"id":4,"action":"utility","kind":"pressed"},{"id":4,"action":"utility","kind":"pressed"}],"held":[]}
	check(pilot.sample().edges.size() == 1, "duplicate edge in one snapshot executes once")
	pilot.test_frame = {"edges":[{"id":4,"action":"utility","kind":"pressed"}],"held":[]}
	check(pilot.sample().edges.is_empty(), "duplicate edge across snapshots executes once")
	pilot.test_frame = {"edges":[{"id":5,"action":"utility","kind":"pressed"}],"held":[]}
	check(pilot.sample().edges.size() == 1, "new edge executes")
	pilot.active = false
	pilot.test_frame = {"axes":{"right_x":1.0},"held":["fire"]}
	cmd = pilot.command(Basis.IDENTITY)
	check(not cmd.active and not cmd.fire and cmd.planar == Vector3.ZERO, "inactive input is fully neutral")
	pilot.test_enabled = false
	pilot.active = true
	pilot.take_control("phone")
	var epoch = pilot.epoch
	pilot.receive_phone({"axes":{"right_x":0.5},"held":["fire"],"edges":[],"neutral":false})
	check(pilot.command(Basis.IDENTITY).fire, "phone owner can provide held actions")
	pilot.receive_phone({"axes":{"right_x":1},"held":["fire"],"edges":[],"neutral":true})
	cmd = pilot.command(Basis.IDENTITY)
	check(not cmd.fire and cmd.planar == Vector3.ZERO, "phone neutral snapshot clears axes and held actions")
	pilot.take_control("keyboard")
	pilot.receive_phone({"axes":{"right_x":1},"held":["fire"]})
	check(pilot.epoch == epoch + 1 and pilot.phone_frame.is_empty(), "takeover changes epoch and ignores non-owner phone frames")
	pilot.test_enabled = true
	pilot.test_frame = {"edges":[{"id":20,"action":"not_a_game_action","kind":"pressed"},{"id":21}],"held":[]}
	check(pilot.sample().edges.is_empty(), "unknown or incomplete edges rejected by input boundary")
	pilot.test_frame = {"edges":[{"id":22,"action":"utility","kind":"released"},{"id":23,"action":"map","kind":"released"}],"held":[]}
	check(pilot.command(Basis.IDENTITY).edges.is_empty(), "released edges never activate utility or map commands")
	pilot.queue_free()
	await process_frame

func test_motion(frame_id: String) -> void:
	await setup(frame_id)
	var min_height = body.position.y
	var max_height = min_height
	var max_hover_error = 0.0
	for index in range(1800):
		await physics_frame
		min_height = minf(min_height,body.position.y)
		max_height = maxf(max_height,body.position.y)
		max_hover_error = maxf(max_hover_error,absf(body.position.y-body.hold_height))
	check(max_hover_error <= 0.15, frame_id + " 30s hover stays within 0.15m of target")
	check(absf(float(body.telemetry.get("altitude_agl_m",0))-body.position.y) < 0.05, frame_id + " AGL follows physical ground ray")
	body.command = command(Vector3.RIGHT)
	await step(120)
	var speed_after_2s = Vector2(body.linear_velocity.x,body.linear_velocity.z).length()
	var motion_start = body.position
	body.command = command()
	await step(180)
	var neutral_speed = Vector2(body.linear_velocity.x,body.linear_velocity.z).length()
	var neutral_distance = motion_start.distance_to(body.position)
	check(neutral_speed < 0.2, frame_id + " neutral stops to below 0.2m/s within 3s")
	body.command = command(Vector3.RIGHT)
	await step(180)
	var brake_start = body.position
	var brake_speed_before = body.linear_velocity.length()
	body.command = command(Vector3.ZERO,0,true)
	await step(180)
	var brake_speed = Vector2(body.linear_velocity.x,body.linear_velocity.z).length()
	var brake_distance = brake_start.distance_to(body.position)
	var settled_brake_speed = brake_speed
	if frame_id == "hx02":
		await step(60)
		settled_brake_speed = Vector2(body.linear_velocity.x,body.linear_velocity.z).length()
	check(settled_brake_speed < 0.2, frame_id + " brake settles within " + ("4s" if frame_id == "hx02" else "3s"))
	body.command = command(Vector3.ZERO,1)
	var rise_start = body.position.y
	await step(120)
	var rise_distance = body.position.y-rise_start
	body.command = command()
	await step(180)
	check(rise_distance > 1.0 and absf(body.position.y-body.hold_height)<0.15, frame_id + " continuous climb transitions to height hold")
	measurements[frame_id] = {"mass_kg":body.mass,"hover_range_m":max_height-min_height,"hover_max_error_m":max_hover_error,"speed_after_2s":speed_after_2s,"neutral_speed_after_3s":neutral_speed,"neutral_distance_3s_m":neutral_distance,"brake_speed_before":brake_speed_before,"brake_speed_after_3s":brake_speed,"settled_brake_speed":settled_brake_speed,"brake_distance_3s_m":brake_distance,"rise_2s_m":rise_distance,"height_hold_error_m":absf(body.position.y-body.hold_height)}

func test_advanced_tilt() -> void:
	await setup("tr01")
	body.command = {"active":true,"mode":"advanced","roll":1.0,"pitch":1.0,"vertical":0.0,"yaw":0.0,"brake":false}
	var maximum_tilt = 0.0
	for index in range(240):
		await physics_frame
		maximum_tilt = maxf(maximum_tilt,rad_to_deg(body.global_basis.y.angle_to(Vector3.UP)))
	measurements.advanced = {"max_observed_tilt_deg":maximum_tilt,"specified_tilt_deg":body.stats.tilt_deg,"altitude_m":body.position.y}
	check(maximum_tilt <= float(body.stats.tilt_deg)+2.0, "advanced diagonal attitude respects maximum tilt plus 2 degree settling tolerance")
	body.command = command(Vector3.ZERO,0,true)
	await step(180)
	check(body.position.is_finite() and body.linear_velocity.is_finite() and body.position.y > 0.42, "braking from advanced diagonal remains finite and airborne")

func test_cargo(frame_id: String) -> void:
	await setup(frame_id,5.0,"hook_base")
	var empty_mass = body.mass
	var weight = minf(2.0,float(Catalog.airframes()[frame_id].cargo_rating_kg))
	body.configure(Catalog.resolve_build(body.build,weight))
	check(is_equal_approx(body.mass,empty_mass), frame_id + " loaded resolved build keeps carried mass out of chassis")
	var cargo = make_box(arena,body.position+Vector3.DOWN*1.1,Vector3(0.4,0.4,0.4),true)
	check(body.attach_cargo(cargo,"qa_cargo",weight), frame_id + " legal cargo attaches through a physical joint")
	await step(180)
	var hover_error = absf(body.position.y-body.hold_height)
	check(is_instance_valid(body.cargo_joint) and hover_error<0.40, frame_id + " loaded hover remains controlled")
	check(is_equal_approx(float(body.telemetry.mass_kg),empty_mass+weight), frame_id + " telemetry counts cargo mass once")
	body.command = command(Vector3.RIGHT)
	await step(120)
	var speed = Vector2(body.linear_velocity.x,body.linear_velocity.z).length()
	check(speed < float(measurements[frame_id].speed_after_2s), frame_id + " cargo reduces achieved acceleration")
	var swing = body.cargo_swing()
	body.command = command(Vector3.ZERO,0,true)
	await step(240)
	check(body.position.is_finite() and body.linear_velocity.is_finite() and is_finite(body.cargo_swing()), frame_id + " loaded braking stays finite")
	measurements[frame_id+"_cargo"] = {"cargo_kg":weight,"body_mass_kg":body.mass,"telemetry_mass_kg":body.telemetry.mass_kg,"hover_error_m":hover_error,"speed_after_2s":speed,"swing_after_acceleration_deg":swing,"brake_speed_after_4s":body.linear_velocity.length()}
	check(body.release_cargo() == cargo and body.cargo_kg == 0, frame_id + " release clears carried mass and retains cargo body")
	await step(2)
	var overloaded = make_box(arena,body.position+Vector3.DOWN*1.1,Vector3(0.4,0.4,0.4),true)
	check(not body.attach_cargo(overloaded,"overload",100.0), frame_id + " overload cannot attach")

func test_multiple_cargo() -> void:
	await setup("hx02",5.0,"hook_base")
	var empty_mass = body.mass
	var first = make_box(arena,body.position+Vector3(-0.3,-1.1,0),Vector3(0.4,0.4,0.4),true)
	var second = make_box(arena,body.position+Vector3(0.3,-1.1,0),Vector3(0.4,0.4,0.4),true)
	check(body.attach_cargo(first,"first",1.0) and body.attach_cargo(second,"second",1.5), "two distinct cargo bodies attach in one sortie")
	check(body.cargo_items.size()==2 and is_equal_approx(body.cargo_kg,2.5) and is_equal_approx(body.mass,empty_mass), "multiple cargo mass is accumulated once outside chassis")
	check(not body.attach_cargo(first,"first",1.0), "duplicate cargo ID cannot create an extra pin or mass")
	check(not body.attach_cargo(first,"same_body",1.0), "same cargo body under another ID cannot double its mass or pins")
	check(not body.attach_cargo(null,"null",1.0), "null cargo body is rejected before mutation")
	var detached = RigidBody3D.new()
	check(not body.attach_cargo(detached,"detached",1.0), "detached cargo cannot make invalid joint paths")
	detached.free()
	var candidate = make_box(arena,body.position+Vector3(3,-1.1,0),Vector3(0.4,0.4,0.4),true)
	check(not body.attach_cargo(candidate,"",1.0), "empty cargo ID is rejected")
	check(not body.attach_cargo(candidate,"negative",-0.5), "negative per-item mass is rejected even if combined mass stays positive")
	check(not body.attach_cargo(candidate,"zero",0.0) and not body.attach_cargo(candidate,"nan",NAN) and not body.attach_cargo(candidate,"infinity",INF), "zero and nonfinite cargo mass are rejected")
	check(body.cargo_items.size()==2 and is_equal_approx(body.cargo_kg,2.5), "failed attachments preserve both existing cargo records and total mass")
	candidate.queue_free()
	await step(240)
	check(body.position.is_finite() and body.linear_velocity.is_finite() and absf(body.position.y-body.hold_height)<0.4, "two physical cargo pins retain controlled finite hover")
	check(is_equal_approx(float(body.telemetry.mass_kg),empty_mass+2.5), "multiple cargo telemetry includes both payload masses exactly once")
	check(body.release_cargo("missing")==null and body.cargo_items.size()==2, "unknown release leaves both cargo items intact")
	check(body.release_cargo("first")==first and body.cargo_items.size()==1 and is_equal_approx(body.cargo_kg,1.5), "releasing noncurrent cargo preserves the other cargo and mass")
	check(body.cargo_body==second and body.cargo_id=="second" and is_instance_valid(body.cargo_joint), "remaining cargo legacy aliases point to the surviving item")
	await step(120)
	check(body.release_cargo()==second and body.cargo_items.is_empty() and body.cargo_kg==0, "default release clears the final cargo and aliases")
	measurements.multiple_cargo = {"count":2,"combined_payload_kg":2.5,"empty_mass_kg":empty_mass,"final_payload_kg":body.cargo_kg,"final_count":body.cargo_items.size()}

func test_collisions() -> void:
	var results = []
	for speed in [2.0,6.0,12.0]:
		await setup("tr01",4.0)
		var width = float(body.stats.width_m)
		make_box(arena,Vector3(width*0.5+0.70,5,0),Vector3(0.15,10,30))
		body.linear_velocity = Vector3(speed,0,0)
		body.command = command(Vector3.RIGHT * speed / float(body.stats.speed_mps))
		await step(35)
		var damage = body.damage_taken
		var count = events.size()
		var wall_crossed = body.position.x > width*0.5+0.70+width*0.5
		check(count>0 and not wall_crossed, "frontal " + str(speed) + "m/s yields contact without thin-wall tunneling")
		body.command = command(Vector3.LEFT)
		await step(90)
		check(body.recovery_left <= 0 and body.linear_velocity.is_finite(), "frontal " + str(speed) + "m/s exits temporary recovery within 1.5s")
		results.append({"speed_mps":speed,"normal_speed_mps":float(events[0].normal_speed_mps) if not events.is_empty() else -1.0,"contact_events":count,"damage":damage,"wall_crossed":wall_crossed,"recovery_after_1_5s":body.recovery_left})
	check(results[0].damage < results[1].damage and results[1].damage <= results[2].damage, "frontal damage grows with normal impact speed")
	await setup("tr01",4.0)
	var width = float(body.stats.width_m)
	make_box(arena,Vector3(width*0.5+0.13,5,0),Vector3(0.15,10,100))
	body.linear_velocity = Vector3(6*sin(deg_to_rad(15)),0,6*cos(deg_to_rad(15)))
	body.command = command(Vector3.FORWARD)
	await step(35)
	check(body.damage_taken < float(results[1].damage), "15 degree scrape damages less than equal-speed frontal impact")
	measurements.scrape = {"speed_mps":6,"damage":body.damage_taken,"contact_events":events.size()}
	measurements.collisions = results
	await setup("tr01",0.45)
	body.linear_velocity = Vector3(0,-6,0)
	body.command = command(Vector3.ZERO,-1)
	await step(25)
	var landing_seen = false
	for event in events:
		if event.kind == "landing":landing_seen = true
	check(landing_seen and body.position.y>0.0, "hard landing reports a landing event without ground penetration")
	measurements.hard_landing = {"events":events.size(),"damage":body.damage_taken,"height_m":body.position.y}
	await setup("tr01",4.0)
	width = float(body.stats.width_m)
	make_box(arena,Vector3(width*0.5+0.13,5,0),Vector3(0.15,10,30))
	body.practice = true
	body.linear_velocity = Vector3(6,0,0)
	body.command = command(Vector3.RIGHT)
	await step(35)
	var first_count = events.size()
	body.command = command(Vector3.LEFT)
	await step(120)
	body.position = Vector3(0,4,0)
	body.rotation = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.linear_velocity = Vector3(6,0,0)
	body.command = command(Vector3.RIGHT)
	await step(35)
	check(events.size()>first_count, "same wall collision re-arms after two simulated seconds")
	measurements.repeated_collision = {"first_events":first_count,"total_events":events.size(),"elapsed_simulation_s":body.flight_seconds}

func record_contact_sample(source: RigidBody3D, payload: Dictionary, samples: Array) -> void:
	# Signals are emitted from the real integration callback. Sample the same
	# physical pose; a scene-node transform may be one rendered frame behind it.
	var snapshot := payload.duplicate(true)
	var state := PhysicsServer3D.body_get_direct_state(source.get_rid())
	snapshot["body_transform"] = state.transform if state != null else source.global_transform
	snapshot["physics_tick"] = Engine.get_physics_frames()
	samples.append(snapshot)

func verify_world_contact(label: String, contacts: Array, receipts: Array, expected_normal: Vector3, surface_point: Vector3) -> Dictionary:
	check(not contacts.is_empty() and not receipts.is_empty(), label+" emits a real contact and damage receipt")
	if contacts.is_empty() or receipts.is_empty(): return {"contact_count":contacts.size(),"receipt_count":receipts.size()}
	var contact: Dictionary = contacts[0]
	var receipt: Dictionary = receipts[0]
	var point_array: Array = receipt.get("position",[])
	var direction_array: Array = receipt.get("direction",[])
	check(point_array.size()==3 and direction_array.size()==3, label+" receipt contains world position and direction")
	if point_array.size()!=3 or direction_array.size()!=3: return {}
	var point := Vector3(float(point_array[0]),float(point_array[1]),float(point_array[2]))
	var normal := Vector3(float(direction_array[0]),float(direction_array[1]),float(direction_array[2]))
	var contact_point: Vector3 = contact.point
	var contact_normal: Vector3 = contact.normal
	var pose: Transform3D = receipt.body_transform
	var half_size: Vector3 = body.get_node("Envelope").shape.size*0.5
	var local_point := pose.affine_inverse()*point
	var plane_error := absf((point-surface_point).dot(expected_normal))
	var normal_dot := normal.dot(expected_normal)
	# 0.18 m allows one 60-Hz tick at the 6 m/s approach speed plus the
	# contact margin. It is tiny compared with the deliberately translated arena.
	check(point.is_finite() and AABB(-half_size,half_size*2.0).grow(0.18).has_point(local_point), label+" receipt point stays on the current oriented aircraft envelope")
	check(plane_error<0.18, label+" receipt point lies on the actual wall or floor plane")
	check(contact_normal.dot(expected_normal)>0.99 and normal_dot>0.99 and absf(normal.length()-1.0)<0.01, label+" contact and receipt normals remain in world space")
	check(point.distance_to(contact_point)<0.0001 and normal.distance_to(contact_normal)<0.0001, label+" receipt preserves the physical contact point and normal exactly once")
	check(receipt.get("weapon_type","")=="collision" and not bool(receipt.get("combat",true)), label+" receipt comes from the physical collision path")
	var repeated_rotation_angle := rad_to_deg(expected_normal.angle_to((pose.basis*expected_normal).normalized()))
	return {"contact_count":contacts.size(),"receipt_count":receipts.size(),"kind":contact.kind,"physics_tick":receipt.physics_tick,"point_world":[point.x,point.y,point.z],"center_world":[pose.origin.x,pose.origin.y,pose.origin.z],"point_in_envelope":[local_point.x,local_point.y,local_point.z],"normal_world":[normal.x,normal.y,normal.z],"normal_dot_expected":normal_dot,"surface_plane_error_m":plane_error,"wrong_second_basis_rotation_deg":repeated_rotation_angle,"normal_speed_mps":contact.normal_speed_mps}

func test_contact_world_coordinates() -> void:
	check("jolt" in str(ProjectSettings.get_setting("physics/3d/physics_engine")).to_lower(), "contact coordinate regression runs against actual Jolt physics")
	var offset := Vector3(37,0,-29)
	var wall_results: Array = []
	for yaw_degrees in [0.0,90.0,-135.0]:
		await setup("tr01",4.0)
		var yaw := deg_to_rad(float(yaw_degrees))
		var orientation := Basis(Vector3.UP,yaw)
		var start := offset+Vector3.UP*4.0
		body.global_transform = Transform3D(orientation,start)
		body.heading = yaw
		body.hold_height = start.y
		body.angular_velocity = Vector3.ZERO
		body.linear_velocity = Vector3.ZERO
		var half_size: Vector3 = body.get_node("Envelope").shape.size*0.5
		var extent_x := absf(orientation.x.x)*half_size.x+absf(orientation.y.x)*half_size.y+absf(orientation.z.x)*half_size.z
		var wall_face_x := start.x+extent_x+0.70
		make_box(arena,Vector3(wall_face_x+0.15,5,offset.z),Vector3(0.3,10,30))
		var contacts: Array = []
		var receipts: Array = []
		body.collision_event.connect(func(event):record_contact_sample(body,event,contacts))
		body.damage_resolved.connect(func(receipt):record_contact_sample(body,receipt,receipts))
		await step(2)
		body.linear_velocity = Vector3.RIGHT*6.0
		body.command = command(Vector3.RIGHT*6.0/float(body.stats.speed_mps))
		for tick in range(45):
			await physics_frame
			if not receipts.is_empty(): break
		var label := "translated yaw "+str(yaw_degrees)+" degree wall impact"
		var result := verify_world_contact(label,contacts,receipts,Vector3.LEFT,Vector3(wall_face_x,0,0))
		if result.has("kind"):
			check(result.kind=="frontal", label+" remains a frontal collision")
			if absf(float(yaw_degrees))>1.0:
				check(float(result.wrong_second_basis_rotation_deg)>45.0, label+" occurs while yaw would expose a second normal rotation")
		result["yaw_degrees"] = yaw_degrees
		wall_results.append(result)
	var landing_results: Array = []
	for yaw_degrees in [90.0,-135.0]:
		await setup("tr01",3.0)
		var yaw := deg_to_rad(float(yaw_degrees))
		var orientation := Basis(Vector3.UP,yaw)*Basis(Vector3.FORWARD,deg_to_rad(28.0))
		var half_size: Vector3 = body.get_node("Envelope").shape.size*0.5
		var extent_y := absf(orientation.x.y)*half_size.x+absf(orientation.y.y)*half_size.y+absf(orientation.z.y)*half_size.z
		var start := offset+Vector3.UP*(extent_y+0.22)
		body.global_transform = Transform3D(orientation,start)
		body.heading = yaw
		body.hold_height = start.y
		body.angular_velocity = Vector3.ZERO
		body.linear_velocity = Vector3.ZERO
		body.command = {"active":true,"mode":"manual_throttle","throttle":0.0,"yaw":0.0,"roll":0.0,"pitch":0.0,"brake":false}
		var contacts: Array = []
		var receipts: Array = []
		body.collision_event.connect(func(event):record_contact_sample(body,event,contacts))
		body.damage_resolved.connect(func(receipt):record_contact_sample(body,receipt,receipts))
		await step(2)
		body.linear_velocity = Vector3.DOWN*4.5
		for tick in range(45):
			await physics_frame
			if not receipts.is_empty(): break
		var label := "translated yaw "+str(yaw_degrees)+" degree tilted landing"
		var result := verify_world_contact(label,contacts,receipts,Vector3.UP,Vector3.ZERO)
		if result.has("kind"):
			check(result.kind=="landing", label+" is classified from the world-up ground normal")
			check(float(result.wrong_second_basis_rotation_deg)>15.0, label+" touches down before attitude recovery can hide the normal regression")
		body.command = command(Vector3.ZERO,-0.25)
		await step(180)
		var grounded_ticks := 0
		for tick in range(60):
			await physics_frame
			if body.is_landed() and body.grounded: grounded_ticks += 1
		check(grounded_ticks>=55 and body.is_landed() and body.telemetry.flight_state=="landed", label+" settles into physical ground support")
		check(absf(body.global_position.y-half_size.y)<0.06 and body.linear_velocity.length()<0.25, label+" rests at collider height without ground penetration")
		result.merge({"yaw_degrees":yaw_degrees,"stable_grounded_ticks":grounded_ticks,"observed_ground_ticks":60,"settled_height_m":body.global_position.y})
		landing_results.append(result)
	measurements.contact_world_coordinates = {"offset_world":[offset.x,offset.y,offset.z],"walls":wall_results,"landings":landing_results,"scope":"Actual Jolt contacts and production collision damage signals; fixture sets only starting pose/velocity and ordinary commands."}

func test_cargo_damping() -> void:
	var results = {}
	for tool in ["hook_base","cargo_winch"]:
		await setup("tr01",5.0,tool)
		var weight = 1.5
		var cargo = make_box(arena,body.position+Vector3.DOWN*1.1,Vector3(0.4,0.4,0.4),true)
		check(body.attach_cargo(cargo,"damping_probe",weight), tool + " damping fixture attaches")
		await step(120)
		cargo.apply_central_impulse(Vector3.RIGHT*weight*1.5)
		var peak = 0.0
		var sum_squared = 0.0
		var sample_count = 0
		for index in range(360):
			await physics_frame
			var angle = body.cargo_swing()
			peak = maxf(peak,angle)
			if index >= 120:
				sum_squared += angle*angle
				sample_count += 1
		results[tool] = {"peak_deg":peak,"tail_rms_deg":sqrt(sum_squared/sample_count),"body_drift_m":Vector2(body.position.x,body.position.z).length(),"configured_damping_multiplier":body.stats.modifiers.cargo_damping_multiplier}
	measurements.cargo_damping = results
	check(results.cargo_winch.tail_rms_deg < results.hook_base.tail_rms_deg * 0.98, "cargo winch reduces measured residual swing by at least 2 percent")

func test_landing(frame_id: String) -> void:
	await setup(frame_id,0.5)
	check(not body.is_landed() and not body.grounded and body.telemetry.flight_state=="flying", frame_id+" half-meter hover is never a landed state")
	body.command = command(Vector3.ZERO,-0.25)
	await step(180)
	check(body.is_landed() and absf(body.position.y-float(body.stats.height_m)*0.5)<0.035 and body.linear_velocity.length()<0.25, frame_id+" held descent settles at its catalog collider height")
	var touchdown = body.position.y
	body.command = command()
	var high = touchdown
	var landed_ticks = 0
	for index in range(180):
		await physics_frame
		high = maxf(high,body.position.y)
		if body.is_landed(): landed_ticks += 1
	check(landed_ticks>=175 and high-touchdown<0.03 and body.telemetry.flight_state=="landed", frame_id+" releasing descent holds the physical landing without an automatic bounce")
	body.command = command(Vector3.ZERO,0.5)
	await step(60)
	check(not body.is_landed() and body.position.y>touchdown+0.7, frame_id+" explicit climb releases ground state and takes off again")
	measurements[frame_id+"_landing"] = {"touchdown_center_height_m":touchdown,"neutral_max_rise_m":high-touchdown,"stable_grounded_ticks":landed_ticks,"neutral_observed_ticks":180,"takeoff_height_m":body.position.y}

func test_ag03_ability() -> void:
	await setup("ag03",5.0)
	body.command = command(Vector3.RIGHT)
	await step(180)
	var before = Vector2(body.linear_velocity.x,body.linear_velocity.z).length()
	check(body.activate_ability(), "AG03 brake pulse activates while available")
	check(not body.activate_ability(), "AG03 ability cannot reactivate during cooldown")
	var active_ticks = 0
	for index in range(48):
		body.command = command(Vector3.RIGHT)
		await physics_frame
		if bool(body.telemetry.get("brake_active",false)): active_ticks += 1
	var during = Vector2(body.linear_velocity.x,body.linear_velocity.z).length()
	check(active_ticks>=47 and body.ability_left>0.1, "AG03 brake survives replacement input snapshots for its full active window")
	check(during<before-0.5 and not bool(body.command.brake), "AG03 active brake physically slows despite a held movement command")
	await step(20)
	check(body.ability_left==0 and not bool(body.telemetry.brake_active) and body.ability_cooldown>6.0, "AG03 pulse ends independently of remaining cooldown")
	check(not body.activate_ability(), "AG03 cannot bypass cooldown after effect expires")
	body.command = command()
	await step(430)
	check(body.ability_cooldown==0 and body.activate_ability(), "AG03 cooldown eventually allows a fresh activation")
	measurements.ag03_ability = {"speed_before_mps":before,"speed_during_mps":during,"braking_ticks":active_ticks,"sampled_ticks":48}

func test_searchlight_swap() -> void:
	await setup("tr01",3.0)
	check(not is_instance_valid(body.searchlight), "non-light utility does not allocate a searchlight")
	var build = body.build.duplicate(true)
	build.slots.utility = "searchlight_base"
	var resolved = Catalog.resolve_build(build)
	check(resolved.valid, "searchlight utility replacement is a legal test assembly")
	body.configure(resolved)
	check(is_instance_valid(body.searchlight) and body.searchlight.visible, "configure immediately enables newly installed searchlight")
	var light_id = body.searchlight.get_instance_id()
	body.configure(resolved)
	check(body.searchlight.get_instance_id()==light_id, "configuring light twice reuses its existing node")
	build.slots.utility = "guard_base"
	body.configure(Catalog.resolve_build(build))
	check(not body.searchlight.visible, "removing light utility immediately disables its illumination")
	build.slots.utility = "searchlight_base"
	body.configure(Catalog.resolve_build(build))
	var count = 0
	for node in body.get_children():
		if node is SpotLight3D: count += 1
	check(body.searchlight.visible and body.searchlight.get_instance_id()==light_id and count==1, "reinstalling light reuses one node without duplicate lights")

func test_environment_force() -> void:
	await setup("tr01",4.0)
	var start = body.position
	await step(120)
	check(body.environment_acceleration==Vector3.ZERO and body.position.distance_to(start)<0.01, "default zero environment force preserves calm hover")
	body.environment_acceleration = Vector3(2.0,0.0,0.0)
	var before = body.position
	var peak_tilt = 0.0
	for index in range(180):
		await physics_frame
		peak_tilt = maxf(peak_tilt,rad_to_deg(body.global_basis.y.angle_to(Vector3.UP)))
	var drift = body.position.x-before.x
	check(drift>0.5 and peak_tilt>3.0, "constant side force produces real drift and opposing attitude response")
	check(body.global_basis.y.x<0 and absf(body.position.y-body.hold_height)<0.15, "flight controller opposes wind while retaining altitude")
	check(body.telemetry.environment_acceleration==Vector3(2,0,0), "telemetry reports applied acceleration in meters per second squared")
	body.environment_acceleration = Vector3(1000,1000,1000)
	check(body.environment_acceleration.is_finite() and body.environment_acceleration.length()<=Body.MAX_ENVIRONMENT_ACCELERATION+0.00001, "environment acceleration is magnitude limited at input boundary")
	body.environment_acceleration = Vector3(NAN,0,0)
	check(body.environment_acceleration==Vector3.ZERO, "nonfinite wind input fails neutral instead of poisoning physics")
	await step(180)
	check(body.position.is_finite() and body.linear_velocity.is_finite() and body.linear_velocity.length()<0.2, "aircraft settles safely after rejected environment input")
	measurements.environment_force = {"side_acceleration_mps2":2.0,"drift_after_3s_m":drift,"peak_tilt_deg":peak_tilt,"acceleration_limit_mps2":Body.MAX_ENVIRONMENT_ACCELERATION}
