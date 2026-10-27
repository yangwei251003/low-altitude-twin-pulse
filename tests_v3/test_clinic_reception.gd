extends SceneTree
## Actual imported reception, Works, PhysicsServer, FlightBody and camera fader.
## Parked poses and Runtime/Progress history are explicit QA fixtures. Reliable
## packets below enter the real consumer, but use an in-memory transport seam.
## No Store writes, player journey, ENet, GPU, performance or duration claim.
const Works = preload("res://scripts/v3/world/twin_clinic_waterworks.gd")
const Runtime = preload("res://scripts/v3/environment/twin_clinic_water_runtime.gd")
const Progress = preload("res://scripts/v3/gameplay/actions/twin_clinic_progress.gd")
const Clinic = preload("res://scripts/v3/gameplay/twin_clinic_session.gd")
const Visibility = preload("res://scripts/v3/art/twin_terrain_visibility.gd")
const FlightBody = preload("res://scripts/v2/flight_body.gd")
const FlightCamera = preload("res://scripts/v2/flight_camera.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
const MODEL := "res://assets/v3/clinic_reception/clinic_reception.glb"
const MODEL_SHA := "3e812dfa70c48585425ea1c9b572d4fb91340e588d96fa57a1ad048e7fd1db07"
const SUPPORT := "res://assets/v3/clinic_reception/clinic_reception_support.glb"
const SUPPORT_SHA := "5d713b0bd4db083f674bdbcdffd280f60488eec35ea4ca275d4b547c427fa54b"
const ORIGIN := Vector3(7,5,-6)
const OLD_RENDER := ["EastLanding","ClinicRearFloor","ClinicCanopyLeft","ClinicCanopyRight","ClinicRearRoofLeft","ClinicRearRoofRight"]
var stage: Node3D
var works
var camera: Camera3D
var camera_control = FlightCamera.new()
var helper = Visibility.new()
var imported: Dictionary = {}
var original_boxes: Dictionary = {}
var baseline: Dictionary = {}
var checks: Array = []
var failures: Array = []
var done := false

class TestLogger extends Logger:
	var errors: Array = []
	var guard := Mutex.new()
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _notify: bool, type: int, _backtraces: Array[ScriptBacktrace]) -> void:
		guard.lock()
		errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale,"type":type})
		guard.unlock()
var logger := TestLogger.new()

class TransportFixture extends RefCounted:
	var mode := "host"
	var session_id := "qa-reception-authority"
	var guests := {2:{}}
	var sent: Array = []
	func is_authority() -> bool: return mode=="host"
	func send_event(peer: int, event: Dictionary) -> void: sent.append({"peer":peer,"event":event.duplicate(true)})

class SessionFixture extends RefCounted:
	var network = TransportFixture.new()
	var active := true
	var owns_world := true
	var region_id := "I2"
	var received_session := "qa-reception-authority"

func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func check(ok: bool, label: String, detail: Variant = null) -> void:
	checks.append({"label":label,"passed":ok,"detail":detail})
	if not ok: failures.append(label)

func _run() -> void:
	create_timer(90).timeout.connect(func():
		if not done:
			check(false,"bounded reception integration test timed out")
			_finish(2))
	_read_asset()
	if not failures.is_empty():
		await _finish(1)
		return
	var bare = Works.new()
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Works.PATH))
	var configured: Dictionary = bare.configure(layout,{},false)
	check(configured.ok,"bare current layout configures before presentation")
	if not configured.ok:
		bare.free()
		await _finish(1)
		return
	baseline=bare.snapshot()
	for body in bare.find_children("*","StaticBody3D",true,false):
		var shape: CollisionShape3D = body.get_node_or_null("ExactBoxCollision")
		if shape!=null: original_boxes[str(body.name)]={"transform":body.transform,"size":shape.shape.size,"layer":body.collision_layer,"mask":body.collision_mask}
	bare.free()
	works=Works.new()
	var loaded: Dictionary = works.load_layout({},false)
	check(loaded.ok and works.reception_art.get("ok",false),"production load installs actual reception and support",loaded)
	if not loaded.ok:
		works.free()
		await _finish(1)
		return
	stage=Node3D.new()
	root.add_child(stage)
	stage.add_child(works)
	await _settle()
	_test_assembly()
	if failures.is_empty():
		_test_solid_rays()
		await _test_routes_and_cutaway()
		_test_service_history()
	await _finish(0 if failures.is_empty() else 1)

func _relative(node: Node3D, ancestor: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current!=ancestor:
		if current is Node3D: result=current.transform*result
		current=current.get_parent()
	return result

func _read_asset() -> void:
	check(FileAccess.get_sha256(MODEL)==MODEL_SHA,"actual reception GLB equals frozen delivery")
	check(FileAccess.get_sha256(SUPPORT)==SUPPORT_SHA,"actual support GLB equals frozen delivery")
	var packed := load(MODEL) as PackedScene
	if packed==null:
		check(false,"actual reception import is available")
		return
	var raw := packed.instantiate() as Node3D
	if raw==null:
		check(false,"actual reception root is Node3D")
		return
	var material_ids: Dictionary = {}
	var triangles := 0
	var valid := true
	var bounds := AABB()
	var first := true
	for mesh: MeshInstance3D in raw.find_children("*","MeshInstance3D",true,false):
		if not mesh.mesh is ArrayMesh or mesh.mesh.get_surface_count()!=1 or imported.has(str(mesh.name)):
			valid=false
			continue
		var material := mesh.get_active_material(0) as BaseMaterial3D
		if material==null:
			valid=false
			continue
		var pose := _relative(mesh,raw)
		var box: AABB = pose*mesh.get_aabb()
		bounds=box if first else bounds.merge(box)
		first=false
		triangles+=int(mesh.mesh.get_faces().size()/3)
		material_ids[material.get_instance_id()]=material
		imported[str(mesh.name)]={"transform":pose,"material":material,"mesh":mesh.mesh,"color":material.albedo_color}
	var textured := 0
	var glass := 0
	var emissive := 0
	for material: BaseMaterial3D in material_ids.values():
		if material.albedo_texture!=null:
			textured+=1
			valid=valid and material.roughness_texture!=null and material.metallic_texture!=null
		elif material.transparency in [BaseMaterial3D.TRANSPARENCY_ALPHA,BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS]:
			glass+=1
			valid=valid and material.albedo_color.a>0 and material.albedo_color.a<1
		elif material.emission_enabled: emissive+=1
	check(valid and imported.size()==186 and triangles==15951 and material_ids.size()==19,"actual mesh, triangle and independent material counts",{"meshes":imported.size(),"triangles":triangles,"materials":material_ids.size()})
	check(textured==11 and glass==5 and emissive==2,"actual atlas/ORM, separate glass and interior diffusers match export",{"textured":textured,"glass":glass,"emissive":emissive})
	check(bounds.position.is_equal_approx(Vector3(-5,-0.4,-4)) and bounds.end.is_equal_approx(Vector3(5,3.3,4)),"actual local bounds preserve ten-metre room scale",str(bounds))
	raw.free()

func _test_assembly() -> void:
	check(works.fixed_bodies.size()==65,"all65 layout fixed boxes are retained")
	var same := true
	for name in original_boxes:
		var found: Array = works.find_children(name,"StaticBody3D",true,false)
		if found.size()!=1:
			same=false
			continue
		var body: StaticBody3D = found[0]
		var shape: CollisionShape3D = body.get_node_or_null("ExactBoxCollision")
		var original: Dictionary = original_boxes[name]
		same=same and shape!=null and shape.shape is BoxShape3D
		if shape==null or not shape.shape is BoxShape3D: continue
		same=same and body.transform==original.transform and body.global_transform==original.transform and shape.shape.size==original.size and body.collision_layer==original.layer and body.collision_mask==original.mask
	check(same,"every original box preserves name, local/world pose, dimensions and layers",original_boxes.size())
	var hidden := 0
	for name in works.fixed_bodies:
		if name in OLD_RENDER or str(name).begins_with("ClinicSupportLeg_") or str(name).begins_with("ClinicFootPlate_") or str(name).begins_with("ClinicBearingNode_") or str(name).begins_with("ClinicCrossbeam_"):
			var body: StaticBody3D = works.fixed_bodies[name]
			same=same and not body.get_node("Visual").visible and body.visible
			hidden+=1
	check(same and hidden==20,"six replaced room boxes and fourteen support boxes hide only old rendering",hidden)
	var art: Dictionary = works.reception_art
	check(art.model_meshes.size()==186 and art.occluders.size()==13 and art.detail_bodies.size()==11,"reception and support retain separate assembly accounting")
	var placed := true
	for mesh: MeshInstance3D in art.model_meshes:
		var source: Dictionary = imported.get(str(mesh.name),{})
		if source.is_empty():
			placed=false
			continue
		placed=placed and mesh.global_transform.is_equal_approx(Transform3D(Basis.IDENTITY,ORIGIN)*source.transform) and mesh.mesh==source.mesh
		if mesh!=art.status_mesh: placed=placed and mesh.get_active_material(0)==source.material
	check(placed,"all186 real meshes preserve source hierarchy/pivots and world placement without material rewrites")
	var identities := true
	for cover: Node3D in art.occluders:
		identities=identities and cover.get_parent()==works and cover.transform==Transform3D.IDENTITY
	check(identities,"all thirteen visual/collider covers stay identity in Works space")
	var support: Dictionary = art.support
	var support_materials: Dictionary = {}
	var support_triangles := 0
	var support_ok: bool = support.ok and support.model_meshes.size()==2
	for mesh: MeshInstance3D in support.model_meshes:
		var material := mesh.get_active_material(0) as BaseMaterial3D
		support_ok=support_ok and mesh.global_transform.is_equal_approx(Transform3D(Basis.IDENTITY,Vector3(7,0,-6))) and material!=null
		if material!=null:
			support_materials[material.get_instance_id()]=true
			support_ok=support_ok and material.albedo_texture!=null and material.normal_texture!=null and material.roughness_texture!=null and material.metallic_texture!=null
		support_triangles+=int(mesh.mesh.get_faces().size()/3)
	check(support_ok and support_materials.size()==1 and support_triangles==4520,"actual two-mesh support uses source PBR, proper origin and unchanged geometry")
	var exact := true
	for name in art.detail_bodies:
		var body: StaticBody3D = art.detail_bodies[name]
		var cover: Node3D = body.get_parent()
		var collision: CollisionShape3D = body.get_child(0)
		var expected := PackedVector3Array()
		for mesh: MeshInstance3D in cover.get_node("AuthoredVisual").find_children("*","MeshInstance3D",true,false):
			for point in mesh.mesh.get_faces(): expected.append(mesh.global_transform*point)
		exact=exact and collision.shape is ConcavePolygonShape3D and collision.shape.backface_collision and body.global_transform==Transform3D.IDENTITY and body.collision_layer==1 and body.collision_mask==0
		if collision.shape is ConcavePolygonShape3D:
			var actual: PackedVector3Array = collision.shape.get_faces()
			exact=exact and actual.size()==expected.size()
			if actual.size()==expected.size():
				for index in range(actual.size()):
					if not actual[index].is_equal_approx(expected[index]): exact=false
	check(exact,"all supplemental triangles coincide with actual authored world-space surfaces")
	check(art.lights.size()==2 and art.status_mesh.get_parent()!=null,"two real interior lights and a separate status mesh exist")
	var targets: Dictionary = works.target_bodies
	check(targets[Works.GRAVITY_ID].get_parent()==works and targets[Works.PUMP_ID].get_parent()==works and targets[Works.RELAY_ID].get_parent()==works,"authority-owned ability targets stay outside all reception covers")

func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from,to,1|8|32)
	query.hit_back_faces=true
	return stage.get_world_3d().direct_space_state.intersect_ray(query)

func _test_solid_rays() -> void:
	for point in [Vector3(4,7,-8),Vector3(7,7,-7.2),Vector3(9,7,-7.2)]:
		var hit := _ray(point,point-Vector3.UP*2.3)
		check(hit.get("collider")==works.fixed_bodies.ClinicRearFloor and absf(hit.get("position",Vector3.ZERO).y-5.0)<0.0001,"rear-room actual floor supports landing at "+str(point),str(hit.get("collider")))
	for row in [["ReceptionRoom",Vector3(4,6.3,-8),Vector3(1,6.3,-8)],
		["ReceptionDesk",Vector3(7,5.7,-7.8),Vector3(7,5.7,-9.6)],
		["ReceptionStretcher",Vector3(10.2,6.5,-8),Vector3(10.2,5.2,-8)],
		["ReceptionBed",Vector3(11.3,6.5,-8),Vector3(11.3,5.2,-8)],
		["ReceptionRoom",Vector3(11,6.5,-8),Vector3(12.3,6.5,-8)]]:
		var hit := _ray(row[1],row[2])
		check(hit.get("collider")==works.reception_art.detail_bodies[row[0]],"real wall/furniture/glass triangle blocks ray: "+str(row[0]),str(hit.get("collider")))

func _physical_state() -> Dictionary:
	var result: Dictionary = {}
	for body in works.find_children("*","PhysicsBody3D",true,false):
		var shapes: Array = []
		for owner in body.get_shape_owners():
			for index in range(body.shape_owner_get_shape_count(owner)):
				shapes.append([body.shape_owner_get_shape(owner,index).get_instance_id(),body.shape_owner_get_transform(owner),body.is_shape_owner_disabled(owner)])
		result[body.get_instance_id()]={"pose":body.global_transform,"server":PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM),"layer":body.collision_layer,"mask":body.collision_mask,"shapes":shapes}
	return result

func _body_sweep(body: PhysicsBody3D, from: Vector3, to: Vector3) -> Dictionary:
	for owner in body.get_shape_owners():
		if body.is_shape_owner_disabled(owner): continue
		for index in range(body.shape_owner_get_shape_count(owner)):
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape=body.shape_owner_get_shape(owner,index)
			query.transform=Transform3D(Basis.IDENTITY,from)*body.shape_owner_get_transform(owner)
			query.collision_mask=1|8|32
			query.exclude=[body.get_rid()]
			query.margin=0.0
			var hits := stage.get_world_3d().direct_space_state.intersect_shape(query,1)
			if not hits.is_empty(): return {"ok":false,"phase":"start","collider":str(hits[0].collider)}
			query.motion=to-from
			var fractions := stage.get_world_3d().direct_space_state.cast_motion(query)
			if fractions.size()!=2 or fractions[0]<0.999: return {"ok":false,"phase":"sweep","fractions":str(fractions)}
			query.transform.origin+=to-from
			query.motion=Vector3.ZERO
			hits=stage.get_world_3d().direct_space_state.intersect_shape(query,1)
			if not hits.is_empty(): return {"ok":false,"phase":"end","collider":str(hits[0].collider)}
	return {"ok":true}

func _place(body: PhysicsBody3D, position: Vector3) -> void:
	body.global_transform=Transform3D(Basis.IDENTITY,position)
	PhysicsServer3D.body_set_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,body.global_transform)
	await _settle()

func _materials(mesh: MeshInstance3D) -> Array:
	var result: Array = []
	for surface in range(mesh.mesh.get_surface_count()): result.append(mesh.get_active_material(surface))
	return result

func _test_routes_and_cutaway() -> void:
	camera=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	stage.add_child(camera)
	camera_control.configure(camera)
	camera_control.target_size=26.0
	for frame in ["tr01","hx02"]:
		var body=FlightBody.new()
		body.configure(Catalog.resolve_build(Catalog.default_build(frame)))
		body.freeze=true
		stage.add_child(body)
		body.set_process(false)
		body.set_physics_process(false)
		for row in [["front corridor",Vector3(3.5,6.4,-3.9),Vector3(10.5,6.4,-3.9)],
			["open doorway",Vector3(7,6.4,-3.8),Vector3(7,6.4,-7.5)],
			["central skylight",Vector3(7,6.4,-3.8),Vector3(7,10,-3.8)]]:
			await _place(body,row[1])
			var sweep := _body_sweep(body,row[1],row[2])
			check(sweep.ok,frame+" actual full hull sweep and both endpoint overlaps: "+str(row[0]),sweep)
			if sweep.ok:
				var collision: KinematicCollision3D = body.move_and_collide(row[2]-row[1])
				check(collision==null and body.global_position.distance_to(row[2])<0.002,frame+" actual body movement traverses "+str(row[0]),str(collision.get_collider()) if collision!=null else null)
		# HX02 is 1.9m long: Z=-7.5 intersects the open door pocket back
		# by 5cm. Z=-7.8 leaves 25cm behind that real surface before sweeping west.
		for row in [["wall",Vector3(4.2,6.4,-7.8),Vector3(1,6.4,-7.8)],
			["desk",Vector3(7,5.8,-7.2),Vector3(7,5.8,-9.5)]]:
			await _place(body,row[1])
			var sweep := _body_sweep(body,row[1],row[2])
			check(not sweep.ok and sweep.get("phase")=="sweep",frame+" real hull is stopped by "+str(row[0])+" after a clear start",sweep)
			var collision: KinematicCollision3D = body.move_and_collide(row[2]-row[1])
			check(collision!=null,frame+" actual body cannot traverse "+str(row[0]))
		for row in [["inside rear room",Vector3(4.3,6.4,-8),"ReceptionRearRoofLeft"],
			["under front canopy",Vector3(3.5,6.4,-3.8),"ReceptionCanopyLeft"]]:
			await _cutaway_case(body,frame,row)
		helper.clear()
		body.queue_free()
		await _settle()

func _cutaway_case(body: PhysicsBody3D, frame: String, row: Array) -> void:
	helper.clear()
	await _place(body,row[1])
	camera_control.snap(body.global_position)
	await _settle()
	var cover: Node3D = works.get_node(NodePath(row[2]))
	var original: Array = []
	for mesh: MeshInstance3D in cover.get_node("AuthoredVisual").find_children("*","MeshInstance3D",true,false): original.append({"mesh":mesh,"materials":_materials(mesh)})
	var physical := _physical_state()
	var state: Dictionary = works.snapshot()
	var status_material: BaseMaterial3D = works.reception_art.status_mesh.get_active_material(0)
	var status_color: Color = status_material.albedo_color
	var lights: Array = []
	for light in works.reception_art.lights: lights.append([light.global_transform,light.light_energy,light.light_color,light.visible])
	helper.setup(camera,body,works.reception_art.occluders)
	for unused in range(6): helper.update(0.1)
	var entry: Dictionary = helper._entries.get(cover.get_instance_id(),{})
	check(helper.occluded and entry.get("blocked",false),frame+" real fixed-camera rays select "+str(row[0]))
	var faded := true
	var visible_shell := false
	for saved in original:
		for index in range(saved.materials.size()):
			var material: BaseMaterial3D = saved.mesh.get_active_material(index)
			if str(saved.mesh.name).ends_with("_Subdeck"):
				visible_shell=true
				faded=faded and material!=saved.materials[index] and is_equal_approx(material.albedo_color.a,0.2*saved.materials[index].albedo_color.a)
			else: faded=faded and material!=saved.materials[index] and is_zero_approx(material.albedo_color.a)
	check(faded and visible_shell,frame+" roof silhouette fades while dense seams withdraw: "+str(row[0]))
	var unchanged: bool = works.reception_art.status_mesh.get_active_material(0)==status_material and status_material.albedo_color==status_color
	for index in range(lights.size()):
		var light: OmniLight3D = works.reception_art.lights[index]
		unchanged=unchanged and lights[index]==[light.global_transform,light.light_energy,light.light_color,light.visible]
	check(unchanged and works.snapshot()==state and _physical_state()==physical,frame+" cutaway preserves service/lighting, exact collision and authority state: "+str(row[0]))
	await _place(body,Vector3(20,11,20))
	camera_control.snap(body.global_position)
	await _settle()
	for unused in range(20): helper.update(0.1)
	var restored: bool = not helper.occluded
	for saved in original: restored=restored and _materials(saved.mesh)==saved.materials
	check(restored and _physical_state()==physical,frame+" normal clear-view release restores original bindings: "+str(row[0]))

func _mechanism(water, serial: int) -> Dictionary:
	var value: Dictionary = baseline.duplicate(true)
	value.runtime=water.snapshot()
	value.serial=serial
	value.gravity_fraction=1.0 if int(value.runtime.facts.gravity_open_permille)>0 else 0.0
	value.axis.position_m=float(value.gravity_fraction)*1.2
	return value

func _history_fixtures() -> Dictionary:
	# Real 0.1s hydraulic ticks and observation. Valve-open/access/deck-height
	# are declared physical evidence fixtures, not real pilot operation.
	var water=Runtime.new()
	if not water.load_definition().ok:
		check(false,"history fixture water definition")
		return {}
	var progress=Progress.new()
	var serial := 0
	for unused in range(1220):
		var before := _mechanism(water,serial)
		var step: Dictionary = water.step(0.1,{"gravity_open_permille":1000,"pump_open_permille":0,"pump_powered":false,"platform_blocked":false})
		serial+=1
		var state := _mechanism(water,serial)
		var status: Dictionary = water.status()
		status.deck_top_y=status.desired_deck_top_m
		var observed: Dictionary = progress.observe(0.1,before,state,status,step,true)
		if not step.ok or not observed.ok:
			check(false,"real hydraulic/history fixture step accepted",{"step":step,"history":observed})
			return {}
		if progress.snapshot().stabilized_once: break
	check(progress.snapshot().stabilized_once and not progress.snapshot().commissioned,"real water/history reaches stable cutoff without confirmation")
	var mechanism := _mechanism(water,serial)
	var full := {"version":1,"mechanism":mechanism,"history":progress.snapshot()}
	var status: Dictionary = water.status()
	status.deck_top_y=status.desired_deck_top_m
	var candidate: Dictionary = progress.prepare_confirm(mechanism,status,true)
	check(candidate.ok,"production Progress prepares confirmation separately from adopting it",candidate.get("code"))
	if not candidate.ok: return {}
	check(progress.adopt_confirm(candidate),"production Progress adopts the explicit confirmed-history fixture")
	return {"full":full,"confirmed":{"version":1,"mechanism":mechanism.duplicate(true),"history":progress.snapshot()}}

func _saved_world(envelope: Dictionary, confirmed: bool) -> Dictionary:
	# Minimal valid I2 disk history, not an assertion of earlier-action playthrough.
	var completed: Array = [Progress.DIAGNOSE,Progress.CONNECT,Progress.STABILIZE]
	var flags: Dictionary = {}
	if confirmed:
		completed.append(Progress.CONFIRM)
		flags[Progress.READY_FLAG]=true
	return {"actions":{"opening":{"completed":completed.duplicate()}},"completed_objectives":completed,"flags":flags,"environment":{"I2_water":envelope.duplicate(true)}}

func _color(module: Node3D) -> Color:
	return module.reception_art.status_mesh.get_active_material(0).albedo_color

func _event(envelope: Dictionary, serial: int) -> Dictionary:
	return {"kind":"clinic_state","session_id":"qa-reception-authority","region":"I2","epoch":1,"serial":serial,"state":envelope.duplicate(true)}

func _test_service_history() -> void:
	var fixtures := _history_fixtures()
	if fixtures.is_empty(): return
	var owner=SessionFixture.new()
	var adapter=Clinic.new()
	adapter.setup(owner)
	var full: Dictionary = adapter.prepare(_saved_world(fixtures.full,false),"I2",true)
	var confirmed: Dictionary = adapter.prepare(_saved_world(fixtures.confirmed,true),"I2",true)
	check(full.ok and confirmed.ok,"host prepare restores both validated pending and confirmed service histories")
	if not full.ok or not confirmed.ok:
		if full.ok: adapter.discard(full)
		if confirmed.ok: adapter.discard(confirmed)
		return
	var pending_module: Node3D = full.module
	var confirmed_module: Node3D = confirmed.module
	var pending_color := _color(pending_module)
	var lit_color := _color(confirmed_module)
	check(not pending_module.reception_art.service_available and confirmed_module.reception_art.service_available and pending_color!=lit_color,"full water alone does not present commissioned service; confirmed disk history does")
	var original_source: Dictionary = imported[str(pending_module.reception_art.status_mesh.name)]
	var material_a: Material = pending_module.reception_art.status_mesh.get_active_material(0)
	var material_b: Material = confirmed_module.reception_art.status_mesh.get_active_material(0)
	check(material_a!=material_b and material_a!=original_source.material and material_b!=original_source.material,"each service lens owns an instance material independent of imported source")
	var before: Dictionary = pending_module.snapshot()
	pending_module.set_service_available(true)
	pending_module.set_service_available(false)
	check(pending_module.snapshot()==before and _color(pending_module)==pending_color and _color(confirmed_module)==lit_color and original_source.material.albedo_color==original_source.color,"presentation toggles preserve hydraulic state, second instance and source material")
	var bad_world := _saved_world(fixtures.confirmed,false)
	var rejected: Dictionary = adapter.prepare(bad_world,"I2",true)
	check(not rejected.ok,"host rejects commissioned history without matching committed objective/flag")
	if rejected.ok: adapter.discard(rejected)
	adapter.module=pending_module
	adapter.progress=full.progress
	adapter.ready=true
	var candidate: Dictionary = adapter.progress.prepare_confirm(pending_module.snapshot(),pending_module.status(),true)
	check(candidate.ok,"pending host can prepare a confirmation at actual restored deck height")
	adapter.publish()
	check(not pending_module.reception_art.service_available and owner.network.sent.size()==1 and not owner.network.sent[-1].event.state.history.commissioned,"publish before confirmation adoption does not light service or send confirmed history")
	if candidate.ok:
		check(adapter.progress.adopt_confirm(candidate),"explicit post-commit adoption fixture is accepted")
		adapter.publish()
		check(pending_module.reception_art.service_available and owner.network.sent[-1].event.state.history.commissioned,"publish follows adopted confirmation rather than full water")
	# Guest receive/consume ordering is exercised without sockets or direct lamp
	# injection. The fake owner only supplies transport identity and mode.
	owner.network.mode="guest"
	owner.owns_world=false
	adapter.module=works
	adapter.ready=false
	adapter.progress=Progress.new()
	adapter.receive(_event(fixtures.full,1))
	check(not works.reception_art.service_available and adapter.applied_serial==-1,"reliable state arriving before its motion epoch cannot change service")
	check(adapter.consume(1,1,"I2") and adapter.applied_serial==1 and not works.reception_art.service_available,"matching first guest packet applies real water yet leaves pending service unlit")
	var accepted: Dictionary = works.snapshot()
	var malformed: Dictionary = fixtures.confirmed.duplicate(true)
	malformed.history.stabilized_once=false
	adapter.receive(_event(malformed,2))
	adapter.consume(2,1,"I2")
	check(adapter.applied_serial==1 and works.snapshot()==accepted and not works.reception_art.service_available,"invalid confirmed history cannot change first-frame collision or lamp")
	malformed=fixtures.confirmed.duplicate(true)
	malformed.mechanism.layout_sha256="unrecognized-layout"
	adapter.receive(_event(malformed,3))
	adapter.consume(3,1,"I2")
	check(adapter.applied_serial==1 and works.snapshot()==accepted and not works.reception_art.service_available,"valid history with rejected mechanism cannot light service")
	adapter.receive(_event(fixtures.confirmed,4))
	check(not works.reception_art.service_available,"future reliable confirmation waits for accepted snapshot sequence")
	check(adapter.consume(4,1,"I2") and adapter.applied_serial==4 and works.reception_art.service_available and _color(works)==lit_color,"accepted history and mechanism update guest service together")
	adapter.receive(_event(fixtures.full,1))
	adapter.consume(4,1,"I2")
	check(adapter.applied_serial==4 and works.reception_art.service_available,"stale unconfirmed packet cannot extinguish accepted service")
	adapter.module=null
	pending_module.free()
	confirmed_module.free()

func _settle() -> void:
	await physics_frame
	await physics_frame
	await process_frame

func _finish(code: int) -> void:
	if done: return
	done=true
	helper.clear()
	if is_instance_valid(stage): stage.queue_free()
	await process_frame
	if not logger.errors.is_empty(): code=1
	print("CLINIC_RECEPTION_RESULT "+JSON.stringify({"passed":code==0,"checks":checks,"failures":failures,"engine_errors":logger.errors,"scope":"actual imported meshes/PhysicsServer/TR01+HX02/fixed-camera cutaway and real ClinicSession preparation/packet consumption; parked poses, valve/access and history fixtures; no Store durability, actual LAN, GPU, performance or player-duration acceptance"}))
	OS.remove_logger(logger)
	quit(code)
