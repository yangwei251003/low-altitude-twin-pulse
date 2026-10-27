extends SceneTree
## Original host Assembly + real production I2; isolated guest World3D contains
## static copies only. No profiles, Store, RPC, second controller or LAN claim.
const Replica = preload("res://scripts/v3/gameplay/twin_canal_replica.gd")
const Adapter = preload("res://scripts/v3/gameplay/twin_canal_session.gd")
const World = preload("res://scripts/v3/twin_test_world.gd")
const WAIT := "res://tests_v3/candidates/canal_session/scan_fixture/actual_wait_78.json"
const WAIT_SHA := "85da0cd7541076c33b7a00ce5ed3aa5ad83904b06feb0dd263602788aebbc9ea"
const DT := 1.0/60.0
var checks := 0
var failures := 0
var done := false
var host_session: FixtureSession
var guest_session: FixtureSession
var host_viewport: SubViewport
var guest_viewport: SubViewport
var adapter = Adapter.new()
var sender = Replica.new()
var receiver = Replica.new()

class FixtureNetwork:
	extends RefCounted
	var mode := "host"
	var session_id := "qa-canal-replica-host"
	func is_authority() -> bool:
		return mode in ["host","solo"]

class FixtureSession:
	extends Node
	var world
	var region_id := "I2"
	var active := true
	var simulation_paused := false
	var entities: Dictionary = {}
	var network = FixtureNetwork.new()
	var received_session := "qa-canal-replica-host"

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		push_error("CANAL REPLICA: "+label)
	return value

func _new_viewport(label: String) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = label
	viewport.own_world_3d = true
	viewport.size = Vector2i(64,64)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	return viewport

func _run() -> void:
	create_timer(25.0).timeout.connect(func():
		if not done:
			_check(false,"25 second bound")
			_finish())
	host_session = FixtureSession.new()
	guest_session = FixtureSession.new()
	guest_session.network.mode = "guest"
	root.add_child(host_session)
	root.add_child(guest_session)
	host_viewport = _new_viewport("ReplicaHostSpace")
	guest_viewport = _new_viewport("ReplicaGuestSpace")
	host_session.world = World.new()
	guest_session.world = World.new()
	host_viewport.add_child(host_session.world)
	guest_viewport.add_child(guest_session.world)
	host_session.world.build("I2",{},true)
	guest_session.world.build("I2",{},false)
	if not _check(host_session.world.build_errors.is_empty() and guest_session.world.build_errors.is_empty(),"original production I2 worlds built"): _finish(); return
	await physics_frame
	await physics_frame
	_check(host_session.world.get_world_3d().space != guest_session.world.get_world_3d().space,"host and guest are independent actual PhysicsServer spaces")
	var original_guest: Dictionary = guest_session.world.objects.duplicate()
	adapter.setup(host_session)
	sender.setup(host_session)
	receiver.setup(guest_session)
	var prepared: Dictionary = adapter.prepare({},"I2",true)
	if not _check(prepared.ok and adapter.adopt(prepared).ok,"original fresh Assembly mounts without replica controllers"): _finish(); return
	var initial: Dictionary = sender.make_event(adapter,1,1)
	if not _check(not initial.is_empty(),"host exports initial real body geometry: "+sender.error): _finish(); return
	_check(initial.targets.is_empty(),"partial Bootstrap interaction set withheld")
	_check(receiver.receive(initial).ok and receiver.installed and not receiver.ready,"Bootstrap collisions installed before six targets")
	_check(not sender.receive(initial).ok,"authority cannot receive a guest replica")
	_check(not receiver.receive(initial).ok,"duplicate event rejected")
	# A validated historical WAIT avoids running unrelated transport work here;
	# its original restorer still re-observes actual support and real joints.
	adapter.clear()
	if not _check(FileAccess.get_sha256(WAIT) == WAIT_SHA,"unchanged original actual WAIT fixture"): _finish(); return
	var fixture: Variant = JSON.parse_string(FileAccess.get_file_as_string(WAIT))
	if not _check(fixture is Dictionary and Adapter.WaitCheckpoint.validate(fixture).ok,"original WAIT validated"): _finish(); return
	prepared = adapter.prepare({"environment":{"I2_canal":fixture}},"I2",true)
	if not _check(prepared.ok and adapter.adopt(prepared).ok,"original physical WAIT restore staged"): _finish(); return
	for _frame in range(240):
		await physics_frame
		var step: Dictionary = adapter.advance(DT)
		if not _check(step.ok,"original host restore frame "+str(step.get("code",""))): _finish(); return
		if adapter.ready: break
	if not _check(adapter.ready,"original host settles actual WAIT contacts"): _finish(); return
	var event: Dictionary = sender.make_event(adapter,2,1)
	if not _check(not event.is_empty(),"full original Assembly exports supported geometry: "+sender.error): _finish(); return
	_check(event.targets.size() == 6,"exact six host target definitions exported")
	# Capture the source comparison in this same synchronous call. The host's
	# carried rigid bodies continue moving in the later awaited physics frames.
	for row in event.bodies:
		var actual: PhysicsBody3D = root.get_node(NodePath(row.path))
		_check(actual.global_transform.is_equal_approx(Replica._transform(row.pose)),"source pose observed in exact export frame: "+str(row.path))
	_check(receiver.receive(event).ok and receiver.ready,"new epoch atomically replaces Bootstrap geometry")
	await physics_frame
	await physics_frame
	_compare_event(event)
	for id in Adapter.IDS:
		_check(receiver.owns_target(id) and guest_session.world.objects[id] is StaticBody3D and guest_session.world.objects[id].get_script() == null,"guest target is static without authority script: "+id)
		_check(guest_session.world.objects[id].get_meta("entity_id","") == id and guest_session.world.definitions[id].id == id and guest_session.entities[id].id == id,"body/definition/entity target registration: "+id)
		var expected := Vector3.INF
		for target in event.targets:
			if target.id == id: expected = Replica._v3(target.state.position)
		_check(guest_session.entities[id].position.is_equal_approx(expected),"target physical position matches captured host event: "+id+" expected="+str(expected)+" actual="+str(guest_session.entities[id].position))
	var cargo: PhysicsBody3D = guest_session.world.objects[Adapter.IDS[1]]
	var query := PhysicsShapeQueryParameters3D.new()
	var tiny := BoxShape3D.new()
	tiny.size = Vector3(.02,.02,.02)
	query.shape = tiny
	query.transform = Transform3D(Basis.IDENTITY,cargo.global_position)
	query.collision_mask = 8
	var actual_hit := false
	for hit in guest_session.world.get_world_3d().direct_space_state.intersect_shape(query,32):
		if hit.collider == cargo: actual_hit = true
	_check(actual_hit,"copied collider exists in guest real physics space")
	_bad_packets(event)
	await _shape_and_pose_fixtures(event)
	# A newer registry owner sharing one ID must survive participant cleanup.
	var relay: String = Adapter.IDS[3]
	var newer := StaticBody3D.new()
	guest_session.world.add_child(newer)
	var newer_entity := {"id":relay,"revision":777,"owner":"new_owner"}
	var newer_definition := {"id":relay,"name":"new registry owner"}
	guest_session.world.objects[relay] = newer
	guest_session.world.definitions[relay] = newer_definition
	guest_session.world.initial_transforms[relay] = Transform3D.IDENTITY
	guest_session.entities[relay] = newer_entity
	receiver.clear()
	_check(not receiver.installed and receiver.status().body_count == 0,"clear resets participant state")
	_check(guest_session.world.objects.get(relay) == newer and is_same(guest_session.entities.get(relay),newer_entity) and is_same(guest_session.world.definitions.get(relay),newer_definition),"clear preserves newer same-ID registry owner")
	for id in original_guest:
		_check(guest_session.world.objects.get(id) == original_guest[id] and is_instance_valid(original_guest[id]),"clear preserves original World facility: "+str(id))
	for id in Adapter.IDS:
		if id != relay: _check(not guest_session.world.objects.has(id) and not guest_session.entities.has(id),"clear removes only owned target: "+id)
	newer.free()
	_finish()

func _compare_event(event: Dictionary) -> void:
	_check(receiver.status().body_count == event.bodies.size(),"all and only host Assembly bodies copied")
	for row in event.bodies:
		var host: PhysicsBody3D = root.get_node(NodePath(row.path))
		var copy: StaticBody3D = receiver._bodies[row.path]
		var expected: Transform3D = Replica._transform(row.pose)
		_check(copy.global_transform.is_equal_approx(expected),"full captured body transform: "+row.path+" expected="+str(row.pose)+" actual="+str(Replica._pose(copy.global_transform)))
		var physical: Transform3D = PhysicsServer3D.body_get_state(copy.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
		_check(physical.is_equal_approx(expected),"guest actual physics pose equals captured packet: "+row.path+" expected="+str(row.pose)+" actual="+str(Replica._pose(physical)))
		_check(copy.collision_layer == host.collision_layer and copy.collision_mask == host.collision_mask,"original physics layer/mask: "+row.path)
		var own_shapes: Array = []
		for child in host.get_children():
			if child is CollisionShape3D: own_shapes.append(child)
		var copied_shapes: Array = []
		for child in copy.get_children():
			if child is CollisionShape3D: copied_shapes.append(child)
		_check(own_shapes.size() == row.shapes.size() and copied_shapes.size() == own_shapes.size(),"only own original collision shapes: "+row.path)
		for index in range(own_shapes.size()):
			_check(copied_shapes[index].transform.is_equal_approx(own_shapes[index].transform) and copied_shapes[index].disabled == own_shapes[index].disabled and copied_shapes[index].shape.get_class() == own_shapes[index].shape.get_class(),"shape type/local pose/disabled state: "+row.path)

func _bad_packets(event: Dictionary) -> void:
	var before: Dictionary = receiver.status()
	var identity: int = receiver._container.get_instance_id()
	for kind in ["session","region","old_epoch","old_serial","shape","finite","duplicate_path","target","digest"]:
		var bad: Dictionary = event.duplicate(true)
		bad.serial = 2
		match kind:
			"session": bad.session_id = "another-host"
			"region": bad.region = "I1"
			"old_epoch": bad.epoch = 1
			"old_serial": bad.serial = 1
			"shape": bad.bodies[0].shapes[0].kind = "plane"
			"finite": bad.bodies[0].pose[9] = INF
			"duplicate_path": bad.bodies.append(bad.bodies[0].duplicate(true))
			"target": bad.targets[0].id = "I2:not_a_canal_target"
			"digest": bad.geometry_digest = "bad"
		_check(not receiver.receive(bad).ok,"bad packet rejected: "+kind)
		_check(receiver._container.get_instance_id() == identity and receiver.status().serial == before.serial and receiver.status().body_count == before.body_count,"bad packet atomic: "+kind)
	guest_session.region_id = "I1"
	_check(not receiver.receive(event).ok,"guest other region rejects I2 packet")
	guest_session.region_id = "I2"

func _fixture_body(parent: Node3D, label: String, shape: Shape3D, position: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.collision_layer = 8
	body.collision_mask = 1|2|8
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	body.position = position
	return body

func _shape_and_pose_fixtures(_original: Dictionary) -> void:
	# These declared geometry probes are added AFTER the unchanged real Assembly
	# checks. They exercise codec types, not game movement or transport success.
	var box := BoxShape3D.new()
	box.size = Vector3(.6,.4,.8)
	var probe: StaticBody3D = _fixture_body(adapter.module,"ReplicaGeometryProbe",box,Vector3(-30,12,30))
	var sphere := SphereShape3D.new()
	sphere.radius = .2
	_fixture_body(probe,"NestedBodyProbe",sphere,Vector3(0,2,0))
	var capsule := CapsuleShape3D.new()
	capsule.height = .8
	capsule.radius = .2
	_fixture_body(adapter.module,"ReplicaCapsuleProbe",capsule,Vector3(-28,12,30))
	var cylinder := CylinderShape3D.new()
	cylinder.height = .5
	cylinder.radius = .2
	_fixture_body(adapter.module,"ReplicaCylinderProbe",cylinder,Vector3(-26,12,30))
	var convex := ConvexPolygonShape3D.new()
	convex.points = PackedVector3Array([Vector3(0,0,0),Vector3(.5,0,0),Vector3(0,.5,0),Vector3(0,0,.5)])
	_fixture_body(adapter.module,"ReplicaConvexProbe",convex,Vector3(-24,12,30))
	await physics_frame
	var event: Dictionary = sender.make_event(adapter,2,2)
	if not _check(not event.is_empty() and receiver.receive(event).ok,"whitelisted five shape types install"): return
	var path: String = str(probe.get_path())
	for row in event.bodies:
		if row.path == path: _check(row.shapes.size() == 1,"nested body sphere not duplicated into parent box")
	var copy: StaticBody3D = receiver._bodies[path]
	var identity: int = copy.get_instance_id()
	var relay: String = Adapter.IDS[3]
	guest_session.entities[relay].owner = "observed_host_lease"
	guest_session.entities[relay].revision = 123
	probe.position += Vector3(.3,.2,-.1)
	probe.rotation.y = .4
	await physics_frame
	event = sender.make_event(adapter,2,3)
	_check(not event.is_empty() and receiver.receive(event).ok and receiver._bodies[path].get_instance_id() == identity,"unchanged geometry uses same static body for new pose")
	_check(copy.global_transform.is_equal_approx(probe.global_transform),"complete observed probe pose updated")
	_check(guest_session.entities[relay].owner == "observed_host_lease" and guest_session.entities[relay].revision == 123,"physical events preserve original generic ownership/revision")
	# Full-precision serialization preserves collision geometry. The default
	# display-oriented JSON float rounding is not a lossless wire contract.
	var roundtrip: Variant = JSON.parse_string(JSON.stringify(event,"",true,true))
	roundtrip.serial = 4
	for index in range(event.bodies.size()):
		var original_row: Dictionary = event.bodies[index]
		var decoded_row: Dictionary = roundtrip.bodies[index]
		_check(int(original_row.layer) == int(decoded_row.layer) and int(original_row.mask) == int(decoded_row.mask),"JSON filters preserve exact integers")
		var original_color := Color(float(original_row.color[0]),float(original_row.color[1]),float(original_row.color[2]))
		var decoded_color := Color(float(decoded_row.color[0]),float(decoded_row.color[1]),float(decoded_row.color[2]))
		_check(Replica._f32_hex([original_color.r,original_color.g,original_color.b]) == Replica._f32_hex([decoded_color.r,decoded_color.g,decoded_color.b]),"JSON constructs bit-identical actual Color")
		for shape_index in range(original_row.shapes.size()):
			_check(_native_shape_bits(original_row.shapes[shape_index]) == _native_shape_bits(decoded_row.shapes[shape_index]),"JSON constructs bit-identical actual Shape+Transform: "+str(original_row.shapes[shape_index].path))
	var decoded: Dictionary = receiver.receive(roundtrip)
	if not decoded.ok:
		var differences: Array = []
		_numeric_differences(event,roundtrip,"event",differences)
		print("CANAL_CANONICAL_FAILURE "+JSON.stringify({"code":decoded.code,
			"original_canonical":Replica._geometry_text(event.bodies,event.targets),
			"decoded_canonical":Replica._geometry_text(roundtrip.bodies,roundtrip.targets),
			"numeric_differences":differences},"",true,true))
	_check(decoded.ok,"full-precision JSON packet roundtrip accepted with numeric counters: "+str(decoded.get("code","missing")))
	var unsupported := WorldBoundaryShape3D.new()
	var rejected: StaticBody3D = _fixture_body(adapter.module,"ReplicaUnsupportedProbe",unsupported,Vector3(-22,12,30))
	_check(sender.make_event(adapter,2,5).is_empty() and sender.error.begins_with("unsupported_host_shape:"),"unsupported actual host collider rejects export instead of disappearing")
	rejected.free()
	var over: Dictionary = event.duplicate(true)
	over.serial = 5
	for row in over.bodies:
		if row.path == path: row.shapes[0].data = [0.0,.4,.8]
	_check(not receiver.receive(over).ok,"zero size cannot install fake collision")

func _native_shape_bits(spec: Dictionary) -> Dictionary:
	var shape: Shape3D = Replica._shape(spec)
	shape.margin = float(spec.margin)
	var data: Array = []
	if shape is BoxShape3D: data = Replica._xyz(shape.size)
	elif shape is SphereShape3D: data = [shape.radius]
	elif shape is CapsuleShape3D or shape is CylinderShape3D: data = [shape.radius,shape.height]
	elif shape is ConvexPolygonShape3D:
		for point in shape.points: data.append_array(Replica._xyz(point))
	var actual_transform: Transform3D = Replica._transform(spec.pose)
	return {"kind":shape.get_class(),"shape_f32":Replica._f32_hex(data),"margin_f32":Replica._f32_hex([shape.margin]),"pose_f32":Replica._f32_hex(Replica._pose(actual_transform))}

func _numeric_differences(a,b,path: String,out: Array) -> void:
	if out.size() >= 64: return
	if (a is int or a is float) and (b is int or b is float):
		var left := JSON.stringify(float(a),"",true,true)
		var right := JSON.stringify(float(b),"",true,true)
		if left != right: out.append({"path":path,"before":left,"after":right,"exact_numeric_equal":float(a)==float(b),"both_zero":float(a)==0.0 and float(b)==0.0})
	elif a is Dictionary and b is Dictionary:
		for key in a: _numeric_differences(a[key],b[key],path+"."+str(key),out)
	elif a is Array and b is Array:
		for index in range(a.size()): _numeric_differences(a[index],b[index],path+"["+str(index)+"]",out)

func _finish() -> void:
	if done: return
	done = true
	receiver.clear()
	sender.clear()
	adapter.clear()
	if is_instance_valid(host_viewport): host_viewport.free()
	if is_instance_valid(guest_viewport): guest_viewport.free()
	if is_instance_valid(host_session): host_session.free()
	if is_instance_valid(guest_session): guest_session.free()
	print("Canal replica: %d checks, %d failures; original host physics, guest static copy; no Store writes or two-PC LAN claim." % [checks,failures])
	quit(0 if failures == 0 else 1)
