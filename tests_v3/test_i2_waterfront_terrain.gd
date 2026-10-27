extends SceneTree
## Detached real Works + candidate terrain in an isolated physics world.
## Pilot placement/frozen bodies and explicit environment samples are QA fixtures.
## No production World/Session, Story, network, graphics or playtime claim.
const Terrain = preload("res://scripts/v3/world/twin_i2_waterfront_terrain.gd")
const Works = preload("res://scripts/v3/world/twin_clinic_waterworks.gd")
const FlightBody = preload("res://scripts/v2/flight_body.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
var terrain: Terrain = Terrain.new()
var works: Node3D
var viewport: SubViewport
var ground: StaticBody3D
var installed: Dictionary = {}
var checks := 0
var failures: Array = []
var measurements: Dictionary = {}
var finished := false
var original_sha := ""
var players: Dictionary = {}
var ground_only_exclusions: Array[RID] = []
class TestLogger extends Logger:
	var errors: Array = []
	func _log_error(function: String,file: String,line: int,code: String,rationale: String,_notify: bool,error_type: int,_backtraces: Array[ScriptBacktrace]) -> void:
		errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale,"type":error_type})
var logger := TestLogger.new()

func _init() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	create_timer(85).timeout.connect(func():
		if not finished:
			print("I2_WATERFRONT_TIMEOUT "+JSON.stringify({"checks":checks,"failures":failures,"engine_errors":logger.errors}))
			quit(2))
	original_sha=FileAccess.get_sha256(Works.PATH)
	var configured: Dictionary=terrain.configure()
	_check(configured.ok,"canonical terrain configures",configured)
	if not configured.ok:
		await _finish()
		return
	_geometry_contract()
	works=Works.new()
	var loaded: Dictionary=works.load_layout()
	_check(loaded.ok,"actual detached Clinic loads existing authored paving before terrain replacement",loaded)
	if not loaded.ok:
		works.free()
		await _finish()
		return
	ground=works.fixed_bodies.Ground
	var mechanism: Dictionary=works.snapshot()
	var old_rid:=ground.get_rid()
	var old_transform:=ground.transform
	var old_metadata: Dictionary={}
	for key in ground.get_meta_list(): old_metadata[key]=ground.get_meta(key)
	var old_shape: Shape3D=ground.get_node("ExactBoxCollision").shape
	var old_visibility: Array=[]
	for patch: MeshInstance3D in works.ground_art.surface_patches: old_visibility.append(patch.visible)
	# Reject bad candidate inputs before altering any shape or already loaded art.
	var rejected: Dictionary=terrain.install(ground,[42])
	_check(not rejected.ok and ground.get_node("ExactBoxCollision").shape==old_shape,"malformed visual patch rejection leaves original collider untouched",rejected)
	ground.position.x=.1
	rejected=terrain.install(ground,works.ground_art.surface_patches)
	_check(not rejected.ok and ground.get_node("ExactBoxCollision").shape==old_shape,"noncanonical Ground pose rejected atomically",rejected)
	ground.transform=old_transform
	var after_visibility: Array=[]
	for patch: MeshInstance3D in works.ground_art.surface_patches: after_visibility.append(patch.visible)
	_check(old_visibility==after_visibility and works.get_node_or_null("I2WaterfrontTerrainA")==null,"failed installs do not hide old surfaces or leak terrain nodes")
	installed=terrain.install(ground,works.ground_art.surface_patches)
	_check(installed.ok,"real Ground is replaced detached",installed.get("summary",{}))
	if not installed.ok:
		works.free()
		await _finish()
		return
	_check(ground.get_rid()==old_rid and ground.transform==old_transform and ground.name=="Ground" and works.fixed_bodies.Ground==ground,"Ground identity/RID/pose/dictionary entry survive")
	var new_metadata: Dictionary={}
	for key in ground.get_meta_list(): new_metadata[key]=ground.get_meta(key)
	_check(new_metadata==old_metadata and ground.collision_layer==1 and ground.collision_mask==0,"existing metadata and collision layer remain unchanged")
	_check(works.snapshot()==mechanism,"terrain installation does not rewrite water/axis/history/layout fingerprint")
	var actual_shape:=ground.get_node("ExactBoxCollision").shape as ConcavePolygonShape3D
	_check(actual_shape!=null and actual_shape.backface_collision and actual_shape.get_faces()==terrain.collision_faces(ground.position),"actual same Ground shape uses precisely all nonwater faces with correct parent offset")
	var box_left:=false
	for child: Node in ground.get_children():
		if child is CollisionShape3D and child.shape is BoxShape3D: box_left=true
	_check(not box_left,"no hidden full 56m box collider remains")
	var hidden: bool=not ground.get_node("Visual").visible
	for patch: MeshInstance3D in works.ground_art.surface_patches: hidden=hidden and not patch.visible
	_check(hidden,"legacy uncut visual surfaces are hidden")
	var paving_visible:=true
	for record: Dictionary in works.ground_art.tiles: paving_visible=paving_visible and record.model.visible
	for record: Dictionary in works.ground_art.maintenance.tiles: paving_visible=paving_visible and record.model.visible
	_check(paving_visible and works.ground_art.all_authored_area_m2==448.0,"all 448m2 authored paving stays visible and in place")
	var stable_shape: Shape3D=actual_shape
	rejected=terrain.install(ground,works.ground_art.surface_patches)
	_check(not rejected.ok and ground.get_node("ExactBoxCollision").shape==stable_shape,"repeat install refuses without changing committed geometry")
	viewport=SubViewport.new()
	viewport.own_world_3d=true
	viewport.world_3d=World3D.new()
	root.add_child(viewport)
	viewport.add_child(works)
	for id: String in ["tr01","hx02"]:
		var body:=FlightBody.new()
		body.configure(Catalog.resolve_build(Catalog.default_build(id)))
		body.freeze=true
		body.position=Vector3(-25,12 if id=="tr01" else 15,25)
		works.add_child(body)
		body.set_process(false)
		body.set_physics_process(false)
		players[id]=body
	for object: Node in works.find_children("*","CollisionObject3D",true,false):
		if object!=ground: ground_only_exclusions.append(object.get_rid())
	await _settle()
	_ground_rays()
	_preserved_supports()
	await _body_routes()
	measurements=terrain.summary()
	await _finish()

func _geometry_contract() -> void:
	var report: Dictionary=terrain.summary()
	_check(absf(report.cut_area_m2-212.6)<.0001 and absf(report.dry_area_m2-2923.4)<.0001 and report.authored_area_m2==448 and absf(report.visible_dry_area_m2-2475.4)<.0001,"exact 3136 = 212.6 water cut + 448 paving + 2475.4 remaining dry area")
	var source_before: Dictionary=terrain.definition()
	var vertices_before:=terrain.collision_faces()
	for wrong: Array in [[Rect2(14,5,1,1)],[Rect2(-40,0,2,2)],[Rect2(-25,10,2,2),Rect2(-24,10,2,2)],[17]]:
		var outcome: Dictionary=terrain.configure(wrong)
		_check(not outcome.ok and terrain.definition()==source_before and terrain.collision_faces()==vertices_before,"invalid authored exclusion rejects without replacing configured geometry",{"code":outcome.get("code")})
	var copy: Dictionary=terrain.geometry("bed")
	copy.faces.clear()
	_check(not terrain.geometry("bed").faces.is_empty(),"geometry access returns an independent copy")
	var collision_water:=false
	var faces:=terrain.collision_faces()
	for i in range(0,faces.size(),3):
		if absf(faces[i].y-Terrain.WATER_Y)<1e-5 and absf(faces[i+1].y-Terrain.WATER_Y)<1e-5 and absf(faces[i+2].y-Terrain.WATER_Y)<1e-5: collision_water=true
	_check(not collision_water,"water plane is absent from physical triangles")
	var normal_ok:=true
	var matched:=true
	var part_diagnostics: Array=[]
	for part: String in terrain.part_ids():
		var data: Dictionary=terrain.geometry(part)
		var mesh: ArrayMesh=terrain.make_mesh(part)
		# get_faces() passes through TriangleMesh's snapped BVH cache. The actual
		# rendering source is ARRAY_VERTEX; keep its byte-value equality strict.
		var surface_arrays: Array=mesh.surface_get_arrays(0) if mesh!=null else []
		var raw_vertices: PackedVector3Array=surface_arrays[Mesh.ARRAY_VERTEX] if not surface_arrays.is_empty() else PackedVector3Array()
		var actual_faces: PackedVector3Array=mesh.get_faces() if mesh!=null else PackedVector3Array()
		var same_raw_vertices: bool=mesh!=null and raw_vertices==data.faces
		var same_bvh_faces: bool=mesh!=null and actual_faces==data.faces
		matched=matched and same_raw_vertices
		var max_raw_difference:=0.0
		for i in mini(raw_vertices.size(),data.faces.size()):
			max_raw_difference=maxf(max_raw_difference,raw_vertices[i].distance_to(data.faces[i]))
		var max_vertex_difference:=0.0
		var max_difference_index: int=-1
		for i in mini(actual_faces.size(),data.faces.size()):
			var difference: float=actual_faces[i].distance_to(data.faces[i])
			if difference>max_vertex_difference:
				max_vertex_difference=difference
				max_difference_index=i
		var wrong_winding: Array=[]
		for i in range(0,data.faces.size(),3):
			var cross: Vector3=(data.faces[i+1]-data.faces[i]).cross(data.faces[i+2]-data.faces[i])
			var dot: float=cross.dot(data.normals[i])
			if dot>=0: wrong_winding.append({"triangle":i/3,"dot":dot,"cross":str(cross),"normal":str(data.normals[i])})
			normal_ok=normal_ok and dot<0
		part_diagnostics.append({"part":part,"raw_vertices_equal":same_raw_vertices,"raw_vertices":raw_vertices.size(),"max_raw_difference_m":max_raw_difference,
			"bvh_faces_equal":same_bvh_faces,"source_vertices":data.faces.size(),"bvh_vertices":actual_faces.size(),"source_triangles":data.faces.size()/3,"bvh_triangles":actual_faces.size()/3,
			"max_bvh_vertex_difference_m":max_vertex_difference,"difference_index":max_difference_index,
			"source_at_difference":str(data.faces[max_difference_index]) if max_difference_index>=0 else "",
			"mesh_at_difference":str(actual_faces[max_difference_index]) if max_difference_index>=0 else "",
			"surface_count":mesh.get_surface_count() if mesh!=null else 0,"mesh_format_flags":mesh.surface_get_format(0) if mesh!=null else -1,
			"primitive":mesh.surface_get_primitive_type(0) if mesh!=null else -1,"wrong_winding":wrong_winding})
	print("I2_WATERFRONT_MESH_DIAGNOSTICS "+JSON.stringify(part_diagnostics))
	_check(matched and normal_ok,"all raw ArrayMesh vertex arrays exactly match source geometry and Godot clockwise front convention",{"matched":matched,"normal_ok":normal_ok,"parts":part_diagnostics})
	_check(terrain.water_at(Vector3(14.75,-.5,6)).water and terrain.water_at(Vector3(14.75,-2.7,6)).water,"negative-Y air and water column above bed classified using same footprint")
	_check(not terrain.water_at(Vector3(14.75,-2.8,6)).water and not terrain.water_at(Vector3(14.75,-3.1,6)).water,"solid bed and below-bed positions are not fluid")
	_check(not terrain.water_at(Vector3(12,-.5,6)).water and not terrain.water_at(Vector3(15,0,1)).water and not terrain.water_at(Vector3(15,0,29)).water and not terrain.water_at(Vector3(NAN,0,6)).water,"shore, north cap, outside region and nonfinite coordinates reject water")
	_check(not terrain.is_water_xz(12.6,6) and terrain.is_water_xz(12.61,6),"bank face itself stays dry; no expanded water footprint")
	_check(terrain.water_at(Vector3(14.75,5,6)).water_height==-1.2 and is_nan(terrain.surface_height(30,0)),"water height and out-of-region height are explicit")

func _ground_rays() -> void:
	var mismatch: Array=[]
	for x in range(-27,28,2):
		for z in range(-27,28,2):
			var hit:=_ray(Vector3(x,2,z),Vector3(x,-3.1,z),true)
			var expected: float=terrain.surface_height(x,z)
			if hit.is_empty() or hit.collider!=ground or absf(hit.position.y-expected)>.001: mismatch.append({"x":x,"z":z,"expected":expected,"hit":str(hit.get("position"))})
	_check(mismatch.is_empty(),"784 actual ground rays agree with dry/water footprint and bed height",{"mismatches":mismatch})
	for row: Array in [[Vector3(14.75,2,6),Vector3(14.75,-3,6),"bed",Vector3(14.75,-2.8,6)], [Vector3(14.75,-.5,6),Vector3(12,-.5,6),"bank",Vector3(12.6,-.5,6)], [Vector3(14.75,-.5,4),Vector3(14.75,-.5,1),"north cap",Vector3(14.75,-.5,2.3)], [Vector3(14.75,-3.3,6),Vector3(14.75,-2.9,6),"underside",Vector3(14.75,-3,6)]]:
		var hit:=_ray(row[0],row[1],true)
		_check(not hit.is_empty() and hit.collider==ground and hit.position.distance_to(row[3])<.002,"actual "+row[2]+" collision, including negative-Y side approach",{"hit":str(hit.get("position"))})
	_check(_ray(Vector3(15,-1.8,26),Vector3(15,-1.8,29),true).is_empty(),"south river mouth has no wall above bed")
	_check(_ray(Vector3(14.75,-1,6),Vector3(14.75,-1.4,6),true).is_empty(),"ray crosses visual water with no glass collision")

func _preserved_supports() -> void:
	var failures_at: Array=[]
	var count:=0
	# Real current JSON support footprints, rather than invented centres only.
	for path: String in [Works.PATH,"res://data/v3/terrain/i2_shared_access_layout.json","res://data/v3/terrain/i2_distribution_layout.json","res://data/v3/terrain/i2_trial_flow_layout.json"]:
		var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
		var origin:=Vector3.ZERO
		if data.has("origin"): origin=_v(data.origin)
		var rows: Array=data.get("fixed_solids",data.get("fixed",data.get("solids",[])))
		for item: Dictionary in rows:
			if item.id=="Ground": continue
			var lo: Vector3=_v(item.min) if item.has("min") else _v(item.center)-_v(item.size)*.5
			var hi: Vector3=_v(item.max) if item.has("max") else _v(item.center)+_v(item.size)*.5
			lo+=origin
			hi+=origin
			if lo.y>=.4 or hi.y<=0: continue
			for point: Vector3 in [Vector3(lo.x+.001,0,lo.z+.001),Vector3(hi.x-.001,0,lo.z+.001),Vector3(lo.x+.001,0,hi.z-.001),Vector3(hi.x-.001,0,hi.z-.001),(lo+hi)*.5]:
				count+=1
				var hit:=_ray(Vector3(point.x,.3,point.z),Vector3(point.x,-.3,point.z),true)
				if hit.is_empty() or absf(hit.position.y)>.001: failures_at.append({"file":path,"id":item.id,"point":str(point)})
	_check(count>100 and failures_at.is_empty(),"current four facilities keep corner-and-centre ground support including .29m west-track margin",{"samples":count,"missing":failures_at})
	for x: float in [12.30,12.31,17.26,17.69,8.9,20.9]:
		var hit:=_ray(Vector3(x,.1,6),Vector3(x,-.3,6),true)
		_check(not hit.is_empty() and absf(hit.position.y)<.001,"retained narrow pier/socket bearing ground x="+str(x))

func _body_routes() -> void:
	for id: String in players:
		var body: FlightBody=players[id]
		for yaw: float in [0.0,90.0]:
			for segment: Array in [[Vector3(16,.4,25),Vector3(14.75,.4,17)], [Vector3(14.75,.4,17),Vector3(14.75,.4,6)], [Vector3(14.75,-.5,6),Vector3(14.75,-.5,4)], [Vector3(14.75,.4,6),Vector3(14.75,1.2,3)], [Vector3(23,1.2,2),Vector3(23,1.2,-7.5)], [Vector3(6,1.2,15),Vector3(6,1.2,2)]]:
				for reverse: bool in [false,true]:
					var start: Vector3=segment[1] if reverse else segment[0]
					var finish: Vector3=segment[0] if reverse else segment[1]
					var result:=_sweep(body,start,finish,yaw)
					_check(result.ok,id+" full real envelope route yaw="+str(yaw)+" reverse="+str(reverse),{"start":str(start),"end":str(finish),"result":result})
		await _place(body,Vector3(14.75,-.5,6))
		var impact: KinematicCollision3D=body.move_and_collide(Vector3.DOWN*3)
		_check(impact!=null and impact.get_collider()==ground and body.position.y< Terrain.WATER_Y and absf(body.position.y-float(body.stats.height_m)*.5-Terrain.BED_Y)<.035,id+" real body crosses water and contacts actual bed rather than old Y0 box",{"end":str(body.position)})
		await _place(body,Vector3(14.75,-.5,6))
		impact=body.move_and_collide(Vector3.LEFT*4)
		_check(impact!=null and impact.get_collider()==ground and body.position.x>12.6,id+" negative-Y full body stops on real bank",{"end":str(body.position)})
		await _place(body,Vector3(-25,12 if id=="tr01" else 15,25))
	# Explicit environmental fixture, not proof of V3 Session supplying samples.
	var probe: FlightBody=players.tr01
	probe.environment_sample=terrain.water_at(Vector3(14.75,-1.3,6))
	_check(probe.environment_sample.water and probe.environment_sample.water_height==-1.2,"body accepts explicit water environment sample; production assignment remains root integration")

func _sweep(body: FlightBody,start: Vector3,finish: Vector3,yaw: float) -> Dictionary:
	var query:=PhysicsShapeQueryParameters3D.new()
	query.shape=body.get_node("Envelope").shape
	query.transform=Transform3D(Basis(Vector3.UP,deg_to_rad(yaw)),start)
	query.collision_mask=0xFFFFFFFF
	query.exclude=[body.get_rid()]
	query.margin=0.0
	var space:=works.get_world_3d().direct_space_state
	var overlap:=space.intersect_shape(query,4)
	if not overlap.is_empty(): return {"ok":false,"stage":"start","hits":_names(overlap)}
	query.motion=finish-start
	var fractions:=space.cast_motion(query)
	if fractions.size()!=2 or fractions[0]<.99999:
		return {"ok":false,"stage":"sweep","fractions":str(fractions)}
	query.transform.origin=finish
	query.motion=Vector3.ZERO
	overlap=space.intersect_shape(query,4)
	return {"ok":overlap.is_empty(),"stage":"end","hits":_names(overlap)}

func _ray(start: Vector3,finish: Vector3,only_ground: bool=false) -> Dictionary:
	var query:=PhysicsRayQueryParameters3D.create(start,finish,0xFFFFFFFF)
	if only_ground: query.exclude=ground_only_exclusions
	query.hit_back_faces=true
	return works.get_world_3d().direct_space_state.intersect_ray(query)

func _place(body: FlightBody,at: Vector3) -> void:
	body.transform=Transform3D(Basis.IDENTITY,at)
	body.linear_velocity=Vector3.ZERO
	body.angular_velocity=Vector3.ZERO
	PhysicsServer3D.body_set_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,body.global_transform)
	await _settle()

func _settle() -> void:
	await physics_frame
	await physics_frame
	await process_frame

func _check(ok: bool,label: String,details: Dictionary={}) -> void:
	checks+=1
	if not ok:
		failures.append({"check":label,"details":details})
		print("I2_WATERFRONT_FAIL "+label+" "+JSON.stringify(details))

static func _v(value: Array) -> Vector3:
	return Vector3(float(value[0]),float(value[1]),float(value[2]))

static func _names(hits: Array) -> Array:
	var result: Array=[]
	for hit: Dictionary in hits: result.append(str(hit.collider.get_path()))
	return result

func _finish() -> void:
	finished=true
	_check(FileAccess.get_sha256(Works.PATH)==original_sha,"production clinic layout bytes unchanged")
	if is_instance_valid(viewport): viewport.queue_free()
	await process_frame
	await process_frame
	print("V3_I2_WATERFRONT_TESTS "+JSON.stringify({"checks":checks,"failures":failures,"engine_errors":logger.errors,"geometry":measurements,"scope":"isolated actual Works, geometry/rays/envelope sweeps; placement and environment fixtures, no MAIN/Story/LAN/graphics/human verification"}))
	OS.remove_logger(logger)
	quit(0 if failures.is_empty() and logger.errors.is_empty() else 1)
