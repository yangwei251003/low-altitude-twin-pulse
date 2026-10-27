extends SceneTree
## Real GLB / PhysicsServer / fixed-camera fader integration. Conserved water
## levels and parked pilot poses are explicit fixtures, not a player journey.
## No Store, networking, graphics capture or performance acceptance.
const Works = preload("res://scripts/v3/world/twin_clinic_waterworks.gd")
const Runtime = preload("res://scripts/v3/environment/twin_clinic_water_runtime.gd")
const Visibility = preload("res://scripts/v3/art/twin_terrain_visibility.gd")
const FlightBody = preload("res://scripts/v2/flight_body.gd")
const FlightCamera = preload("res://scripts/v2/flight_camera.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
const MODEL := "res://assets/v3/clinic_gravity/clinic_gravity.glb"
const MODEL_SHA := "87b596b5bb5f4cb66e40d7a019ce9167b1eb3c1d406a5d66d086d3728fa0710e"
const PARTS := ["DeckStructure","CisternStructure","DeckDetails","CisternDetails","CisternWindow"]
const ORIGIN := Vector3(-9,6,-7)
var stage: Node3D
var works
var camera: Camera3D
var camera_control = FlightCamera.new()
var helper = Visibility.new()
var meshes: Dictionary = {}
var groups: Dictionary = {}
var reference_bodies: Dictionary = {}
var imported_materials: Dictionary = {}
var checks: Array = []
var failures: Array = []
var finished := false

class TestLogger extends Logger:
	var errors: Array = []
	var guard := Mutex.new()
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		guard.lock()
		errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale,"type":error_type})
		guard.unlock()
var error_logger := TestLogger.new()

func _initialize() -> void:
	OS.add_logger(error_logger)
	_run.call_deferred()

func check(ok: bool, label: String, detail: Variant = null) -> void:
	checks.append({"label":label,"passed":ok,"detail":detail})
	if not ok: failures.append(label)

func _run() -> void:
	create_timer(75).timeout.connect(func():
		if not finished:
			check(false,"bounded art integration test timed out")
			_finish(2))
	check(FileAccess.get_sha256(MODEL)==MODEL_SHA,"actual source GLB matches frozen five-part delivery")
	var raw = load(MODEL) as PackedScene
	if raw==null:
		check(false,"actual imported GLB must exist")
		await _finish(1)
		return
	var raw_model: Node3D = raw.instantiate()
	var imported: Array = raw_model.find_children("*","MeshInstance3D",true,false)
	check(imported.size()==5,"actual GLB contains exactly five mesh instances")
	var bounds := AABB()
	var first := true
	var triangles := 0
	var materials: Dictionary = {}
	for mesh: MeshInstance3D in imported:
		var valid_mesh: bool = str(mesh.name) in PARTS and mesh.mesh is ArrayMesh and mesh.mesh.get_surface_count()==1
		check(valid_mesh,"imported mesh has stable name and one real surface: "+str(mesh.name))
		if not valid_mesh: continue
		triangles += int(mesh.mesh.get_faces().size()/3)
		bounds = mesh.get_aabb() if first else bounds.merge(mesh.get_aabb())
		first = false
		var material := mesh.get_active_material(0) as BaseMaterial3D
		check(material!=null,"actual imported surface has a supported material: "+str(mesh.name))
		if material!=null:
			materials[material.get_instance_id()] = true
			imported_materials[str(mesh.name)]={"resource":material,"alpha":material.albedo_color.a,"transparency":material.transparency}
	check(triangles==14296 and materials.size()==2,"actual imported geometry/material totals agree with frozen delivery",{"triangles":triangles,"materials":materials.size()})
	check(bounds.position.is_equal_approx(Vector3(-3.018,-6,-3.018)) and bounds.end.is_equal_approx(Vector3(4.018,3.24,2.618)),"actual GLB local bounds preserve intended scale and bottom origin",str(bounds))
	raw_model.free()
	if not failures.is_empty():
		await _finish(1)
		return
	# A bare configure is the unchanged box-physics reference. It deliberately
	# does not invoke the presentation installer under test.
	var bare = Works.new()
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Works.PATH))
	var baseline: Dictionary = bare.configure(layout,{},false)
	check(baseline.ok,"unadorned production physics reference configures")
	if not baseline.ok:
		bare.free()
		await _finish(1)
		return
	for body in bare.find_children("*","StaticBody3D",true,false):
		var shape: CollisionShape3D = body.get_node_or_null("ExactBoxCollision")
		if shape!=null: reference_bodies[str(body.name)]={"transform":body.transform,"size":shape.shape.size,"layer":body.collision_layer,"mask":body.collision_mask}
	bare.free()
	stage = Node3D.new()
	root.add_child(stage)
	works = Works.new()
	var loaded: Dictionary = works.load_layout({},false)
	check(loaded.ok and works.gravity_art.get("ok",false),"real Works load installs actual gravity asset",loaded)
	if not loaded.ok:
		works.free()
		await _finish(1)
		return
	stage.add_child(works)
	await _settle()
	_test_installation()
	if failures.is_empty():
		_test_detail_rays()
		_test_water_levels()
		await _test_camera_cutaway()
	await _finish(0 if failures.is_empty() else 1)

func _test_installation() -> void:
	check(works.fixed_bodies.size()==65,"all65 authored fixed boxes remain registered")
	for name in ["GravityDeckCover","GravityCisternCover"]:
		var group: Node3D = works.get_node_or_null(NodePath(name))
		check(group!=null and group.transform==Transform3D.IDENTITY and group.get_parent()==works,"occlusion group stays identity in Works space: "+name)
		if group!=null:
			groups[name]=group
			var visual: Node3D = group.get_node_or_null("AuthoredVisual")
			check(visual!=null and visual.transform==Transform3D.IDENTITY,"authored visual identity child avoids collision-body name conflicts: "+name)
	for name in PARTS:
		var found: Array = works.find_children(name,"MeshInstance3D",true,false)
		check(found.size()==1,"authored mesh name remains unique after assembly: "+name)
		if found.size()!=1: continue
		var mesh: MeshInstance3D = found[0]
		meshes[name]=mesh
		check(mesh.global_transform.basis.is_equal_approx(Basis.IDENTITY) and mesh.global_position.is_equal_approx(ORIGIN),"authored mesh retains correct world placement: "+name)
		var material := mesh.get_active_material(0) as BaseMaterial3D
		check(material==imported_materials[name].resource and material.albedo_color.a==imported_materials[name].alpha and material.transparency==imported_materials[name].transparency,"assembly retains the actual imported material and opacity mode: "+name)
		if name=="CisternWindow":
			check(material!=null and material.transparency in [BaseMaterial3D.TRANSPARENCY_ALPHA,BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS] and material.albedo_color.a>0 and material.albedo_color.a<1,"authored window retains its separate transparent material")
		else:
			check(material!=null and material.albedo_texture!=null and material.normal_texture!=null and material.roughness_texture!=null and material.metallic_texture!=null,"actual imported PBR maps remain bound: "+name)
	var unchanged := true
	var count := 0
	for name in reference_bodies:
		var found: Array = works.find_children(name,"StaticBody3D",true,false)
		if found.size()!=1:
			unchanged=false
			continue
		var body: StaticBody3D = found[0]
		var ref: Dictionary = reference_bodies[name]
		var shape: CollisionShape3D = body.get_node_or_null("ExactBoxCollision")
		unchanged = unchanged and shape!=null and shape.shape is BoxShape3D
		if shape==null or not shape.shape is BoxShape3D: continue
		unchanged = unchanged and body.transform==ref.transform and body.global_transform==ref.transform and shape.shape.size==ref.size and body.collision_layer==ref.layer and body.collision_mask==ref.mask
		count+=1
	check(unchanged and count==reference_bodies.size(),"identity regrouping preserves every original box name/local/global transform/shape/layer",{"found":count,"expected":reference_bodies.size()})
	var hidden := 0
	for body in works.find_children("*","StaticBody3D",true,false):
		var old_visual: MeshInstance3D = body.get_node_or_null("Visual")
		if old_visual==null: continue
		if body.get_parent() in groups.values():
			hidden+=1
			check(not old_visual.visible and body.visible and body.has_node("ExactBoxCollision"),"only replaced render mesh is hidden, original body stays usable: "+str(body.name))
	check(hidden==24,"sixteen deck and eight tank solids hide their old render meshes")
	check(works.gravity_valve.get_parent()==works and works.pump_selector.get_parent()==works and works.interlock_bolt.get_parent()==works,"moving controls remain outside the static identity groups")
	check(works.get_node("GrayboxNavigation").get_parent()==works and works.get_node("GrayboxNavigation").get_meta("terrain_visibility_keep",false),"navigation and state lamps retain their protected independent subtree")

func _test_detail_rays() -> void:
	check(works.gravity_art.detail_bodies.size()==2,"only the two authored detail meshes add supplemental collision")
	for name in ["DeckDetails","CisternDetails"]:
		var body: StaticBody3D = works.gravity_art.detail_bodies[name]
		var collider: CollisionShape3D = body.get_child(0)
		var mesh: MeshInstance3D = meshes[name]
		check(collider.shape is ConcavePolygonShape3D and collider.shape.get_faces()==mesh.mesh.get_faces() and collider.shape.backface_collision,"supplement is exact imported two-sided triangle geometry: "+name)
		check(body.global_transform==mesh.global_transform and body.collision_layer==1 and body.collision_mask==0,"supplement collision shares the authored mesh world transform: "+name)
		var excluded: Array[RID] = []
		for other in works.find_children("*","CollisionObject3D",true,false):
			if other!=body: excluded.append(other.get_rid())
		var vertices: PackedVector3Array = mesh.mesh.get_faces()
		var found := false
		for index in range(0,mini(vertices.size(),600),3):
			var a: Vector3 = mesh.global_transform*vertices[index]
			var b: Vector3 = mesh.global_transform*vertices[index+1]
			var c: Vector3 = mesh.global_transform*vertices[index+2]
			var normal := (b-a).cross(c-a)
			if normal.length_squared()<0.000000001: continue
			normal=normal.normalized()
			var centre := (a+b+c)/3.0
			var hit := _ray(centre+normal*0.04,centre-normal*0.04,excluded)
			if hit.get("collider")==body:
				found=true
				break
		check(found,"real PhysicsServer ray hits imported detail (other bodies excluded only for attribution): "+name)

func _level_fixture(volume_ml: int) -> void:
	var water = Runtime.new()
	check(water.load_definition().ok,"water-level fixture uses the actual runtime definition")
	var hydraulic: Dictionary = water.snapshot()
	hydraulic.simulation.nodes[Runtime.SOURCE].clean_ml-=volume_ml
	hydraulic.simulation.nodes[Runtime.CLINIC].clean_ml+=volume_ml
	check(water.restore(hydraulic).ok,"explicit water-level fixture preserves source/destination conservation")
	var saved: Dictionary = works.snapshot()
	saved.runtime=water.snapshot()
	check(works.apply_snapshot(saved).ok,"actual Works restores the conserved level fixture")

func _test_water_levels() -> void:
	for amount in [0,1000000,2000000]:
		_level_fixture(amount)
		for id in [Runtime.SOURCE,Runtime.CLINIC]:
			var surface: MeshInstance3D = works.water_surfaces[id]
			var volume: MeshInstance3D = works.water_volumes[id]
			var level: float = works.water_level(id)
			check(absf(surface.global_position.y-level)<0.00001,"dynamic surface stays at real water level after reparent: "+id+" / "+str(amount))
			if volume.visible:
				var top: float = volume.global_position.y+volume.mesh.size.y*volume.global_basis.y.length()*0.5
				check(absf(top-(level-0.002))<0.00001,"dynamic volume top retains the2mm surface gap: "+id+" / "+str(amount))
			var point: Vector3 = surface.global_position
			if surface.visible:
				check(_ray(point+Vector3.UP*0.015,point-Vector3.UP*0.015).is_empty(),"surface and filled volume remain non-colliding: "+id+" / "+str(amount))
			else:
				# Empty clinic water coincides with the real tank floor. That floor
				# must remain collidable; a ray there cannot prove water collision.
				check(not volume.visible and surface.find_children("*","CollisionObject3D",true,false).is_empty() and volume.find_children("*","CollisionObject3D",true,false).is_empty(),"empty fluid has no visible volume or child collision: "+id)
		check(works.water_surfaces[Runtime.SOURCE].get_parent()==groups.GravityCisternCover and works.water_volumes[Runtime.SOURCE].get_parent()==groups.GravityCisternCover,"both source fluid meshes join the tank cutaway without a model-origin offset")

func _body_state() -> Dictionary:
	var result: Dictionary = {}
	for body in works.find_children("*","PhysicsBody3D",true,false):
		var shapes: Array = []
		for owner in body.get_shape_owners():
			for index in body.shape_owner_get_shape_count(owner):
				shapes.append([body.shape_owner_get_shape(owner,index).get_instance_id(),body.shape_owner_get_transform(owner),body.is_shape_owner_disabled(owner)])
		result[body.get_instance_id()]={"rid":body.get_rid(),"transform":body.global_transform,"server":PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM),"layer":body.collision_layer,"mask":body.collision_mask,"shapes":shapes}
	return result

func _materials(mesh: MeshInstance3D) -> Array:
	var result: Array = []
	for index in mesh.mesh.get_surface_count(): result.append(mesh.get_active_material(index))
	return result

func _ray(from: Vector3, to: Vector3, excluded: Array[RID] = []) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from,to,1|8)
	query.hit_back_faces=true
	query.exclude=excluded
	return stage.get_world_3d().direct_space_state.intersect_ray(query)

func _camera_hits(pilot: Node3D, target: PhysicsBody3D) -> bool:
	var direction: Vector3 = camera.global_basis.z.normalized()
	var point: Vector3 = pilot.get_node("Envelope").global_position
	var depth: float = (camera.global_position-point).dot(direction)-camera.near
	var excluded: Array[RID] = [pilot.get_rid()]
	for unused in range(16):
		var hit := _ray(point+direction*depth,point,excluded)
		if hit.is_empty(): return false
		if hit.collider==target: return true
		excluded.append(hit.rid)
	return false

func _test_camera_cutaway() -> void:
	camera=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	stage.add_child(camera)
	camera_control.configure(camera)
	camera_control.target_size=26.0
	var protected: Array = []
	for node in [works.gravity_valve,works.pump_selector,works.interlock_bolt,works.target_bodies[Works.RELAY_ID],works.get_node("GrayboxNavigation")]:
		for mesh in node.find_children("*","MeshInstance3D",true,false): protected.append({"mesh":mesh,"materials":_materials(mesh)})
	for frame in ["tr01","hx02"]:
		var pilot=FlightBody.new()
		pilot.configure(Catalog.resolve_build(Catalog.default_build(frame)))
		pilot.freeze=true
		stage.add_child(pilot)
		pilot.set_process(false)
		pilot.set_physics_process(false)
		for row in [["deck",Vector3(-10,4.3,-9),"GravityDeckCover","UpperWorkDeck"],["cistern",Vector3(-10.8,7.3,-8.8),"GravityCisternCover","CisternLid"]]:
			helper.clear()
			pilot.global_transform=Transform3D(Basis.IDENTITY,row[1])
			PhysicsServer3D.body_set_state(pilot.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,pilot.global_transform)
			camera_control.snap(pilot.global_position)
			await _settle()
			check(_camera_hits(pilot,works.fixed_bodies[row[3]]),frame+": actual default-camera ray reaches original box: "+str(row[0]))
			var physical := _body_state()
			var hydraulic: Dictionary = works.snapshot()
			var originals: Array = []
			for mesh in groups[row[2]].find_children("*","MeshInstance3D",true,false):
				if mesh.visible: originals.append({"mesh":mesh,"materials":_materials(mesh)})
			helper.setup(camera,pilot,works.gravity_art.occluders)
			for unused in range(6): helper.update(0.1)
			var entry: Dictionary = helper._entries.get(groups[row[2]].get_instance_id(),{})
			check(helper.occluded and entry.get("blocked",false),frame+": real old collider selects its corresponding authored cutaway: "+str(row[0]))
			var faded := true
			for saved in originals:
				for index in saved.materials.size():
					var material: BaseMaterial3D = saved.mesh.get_active_material(index)
					var expected: float = 0.0 if saved.mesh.get_meta("terrain_visibility_cutaway_detail",false) else float(saved.materials[index].albedo_color.a)*Visibility.FADED_ALPHA
					faded=faded and material!=saved.materials[index] and absf(material.albedo_color.a-expected)<0.00001
			check(faded,frame+": authored shell/window/fluid materials fade with the selected real obstruction: "+str(row[0]))
			var unchanged := true
			for saved in protected: unchanged=unchanged and _materials(saved.mesh)==saved.materials
			check(unchanged and works.snapshot()==hydraulic and _body_state()==physical,frame+": fading leaves targets/lamps/collision/water authority unchanged: "+str(row[0]))
			pilot.global_position=Vector3(18,12,18)
			PhysicsServer3D.body_set_state(pilot.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,pilot.global_transform)
			camera_control.snap(pilot.global_position)
			await _settle()
			for unused in range(20): helper.update(0.1)
			var restored: bool = not helper.occluded
			for saved in originals: restored=restored and _materials(saved.mesh)==saved.materials
			check(restored and _body_state()==physical,frame+": clear sight restores exact original material bindings, with all physics retained: "+str(row[0]))
			helper.clear()
		pilot.queue_free()
		await _settle()

func _settle() -> void:
	await physics_frame
	await physics_frame
	await process_frame

func _finish(code: int) -> void:
	if finished: return
	finished=true
	helper.clear()
	if is_instance_valid(stage): stage.queue_free()
	await process_frame
	if not error_logger.errors.is_empty(): code=1
	print("CLINIC_GRAVITY_ART_RESULT "+JSON.stringify({"passed":code==0,"checks":checks,"failures":failures,"engine_errors":error_logger.errors,"scope":"actual GLB/Works/PhysicsServer/FlightBody/fixed-camera fader with declared parked poses and conserved saved-level fixtures; no Session playthrough, Store, ENet, GPU readability, human-duration or performance acceptance"}))
	OS.remove_logger(error_logger)
	quit(code)
