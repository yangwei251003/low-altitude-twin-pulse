extends "res://scripts_tools/v3/capture_assets.gd"
## Opt-in, local review of changed geometry. No runtime asset is overwritten.
const Crown = preload("res://scripts/v3/gameplay/twin_crown_encounter.gd")
const CANDIDATE = "res://assets/v3/candidates/root_buttress_h10_p12/root_buttress_h10_p12.glb"
const EXPECTED = "d8d8877b31a68472610719974df8eeeadb06cb90facaed8a31b86a4b61923850"
const BASELINE = "res://assets/v3/root_buttress/root_buttress_h10.glb"
const BASELINE_SHA = "ceaae98c56aa8fa3517d43a11708c352e8741fa801d78a24eba87871a8d29d53"
const WEST = "F1:crown_host_west"
var checks: Array = []
var failures: Array = []
var input_hashes: Dictionary = {}
var original: Node3D

func _run() -> void:
	var safe = false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile=qa_visual_"): safe = true
		if arg.begins_with("--capture-output="): output=arg.trim_prefix("--capture-output=")
	if not safe or DisplayServer.get_name()=="headless" or output.is_empty(): quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	input_hashes=_hashes()
	_check(FileAccess.get_sha256(BASELINE)==BASELINE_SHA,"historical P2 baseline SHA; refuse a mislabeled comparison after runtime integration")
	_check(FileAccess.get_sha256(CANDIDATE)==EXPECTED,"frozen candidate SHA")
	if not failures.is_empty(): _finish(); return
	session=load("res://scenes/v3/main.tscn").instantiate()
	root.add_child(session)
	if not session.start_flight("solo") or not session._load_region("F1"): quit(1); return
	session.set_process(false)
	session.set_physics_process(false)
	session.inputs.set_process(false)
	session.inputs.set_physics_process(false)
	await physics_frame
	var arena=session.world.crown_arena
	original=arena.hosts[WEST]
	await _views("p2-baseline")
	var candidate=(load(CANDIDATE) as PackedScene).instantiate() as Node3D
	arena.add_child(candidate)
	candidate.transform=original.transform
	for name in ["GroundOrigin","BodyPerch","HostTarget","LowerShelf"]:
		var a=candidate.find_child(name,true,false)
		var b=original.find_child(name,true,false)
		_check(a is Node3D and b is Node3D and a.global_position.distance_to(b.global_position)<0.001,"same anchor "+name)
	var meshes=candidate.find_children("*","MeshInstance3D",true,false)
	_check(meshes.size()==3,"three imported candidate meshes")
	var tris=0
	for mesh: MeshInstance3D in meshes:
		tris+=mesh.mesh.get_faces().size()/3
		var body=StaticBody3D.new()
		body.collision_layer=1
		body.collision_mask=0
		body.set_meta("entity_id",WEST if str(mesh.name).contains("SapKnot") else "crown:terrain")
		mesh.add_child(body)
		var collider=CollisionShape3D.new()
		collider.shape=mesh.mesh.create_trimesh_shape()
		collider.shape.backface_collision=true
		body.add_child(collider)
		var material=mesh.get_active_material(0)
		_check(material is BaseMaterial3D and material.albedo_texture!=null and material.normal_enabled and material.normal_texture!=null and material.roughness_texture!=null,"actual imported PBR textures "+str(mesh.name))
		if str(mesh.name).contains("SapKnot"):
			var glow=material.duplicate()
			mesh.set_surface_override_material(0,glow)
			arena._glows[WEST]=glow
	_check(tris==63996,"all candidate triangles loaded")
	arena.remove_child(original)
	arena.hosts[WEST]=candidate
	arena.host_targets[WEST]=candidate.find_child("HostTarget",true,false)
	arena._force_transforms(candidate)
	await physics_frame
	await physics_frame
	await _place(arena.retry_position(0))
	_geometry(candidate)
	await _views("p12-candidate")
	await _place(arena.host_position(WEST)+Vector3(0,0,2.5))
	_check(session.crown.start(false),"production Crown starts against candidate terrain")
	for ability in ["light","growth"]:
		session.cooldowns[1]=0.0
		session._action_received(1,"ability",{"ability":ability,"target_id":WEST})
	_check(session.crown.encounter.get_state().core_open,"candidate actual Sap first hit accepts light-growth core opening")
	await _pose(Vector3(1,13,-22),18)
	session.locks[1]="boss:crown_core"
	session._refresh_interface()
	await _capture("04-p12-core-open")
	_check(_hashes()==input_hashes,"baseline, candidate and review inputs unchanged")
	_finish()

func _views(label: String) -> void:
	await _pose(Vector3(8,13,-23),34)
	await _capture("01-"+label+"-default")
	await _pose(Vector3(1,12,-21),18)
	await _capture("02-"+label+"-near")
	await _pose(Vector3(-3,5,-20),20)
	await _capture("03-"+label+"-lower-root")

func _geometry(candidate: Node3D) -> void:
	var arena=session.world.crown_arena
	var excluded: Array[RID]=[]
	for body in arena.model.collision_bodies(): excluded.append(body.get_rid())
	for foot in [Vector2(-2.54,2.17),Vector2(2.51,2.22),Vector2(-2.28,-2.50),Vector2(2.31,-2.48)]:
		for i in range(9):
			var offset=Vector2.ZERO if i==0 else Vector2.from_angle(TAU*(i-1)/8.0)*0.75
			var at=candidate.to_global(Vector3(foot.x+offset.x,10,foot.y+offset.y))
			var query=PhysicsRayQueryParameters3D.create(at+Vector3.UP*0.15,at-Vector3.UP*0.15,1,excluded)
			var hit=session.get_world_3d().direct_space_state.intersect_ray(query)
			_check(not hit.is_empty() and candidate.is_ancestor_of(hit.collider) and absf(hit.position.y-10)<0.003,"actual candidate claw support "+str(foot)+":"+str(i))
	for spec in arena.definition.anchors:
		for destination in arena.definition.anchors:
			if spec.id==destination.id: continue
			var from: Vector3=arena.vector(spec.body_position)
			var to: Vector3=arena.vector(destination.body_position)
			var points=Crown.build_route(_mm(from),_mm(to),roundi(maxf(from.y,to.y)*1000)+3000)
			var result: Dictionary=arena.motion_result(points)
			_check(result.clear,"full-body migration "+str(spec.id)+" to "+str(destination.id),result)
		var from: Vector3=arena.vector(spec.body_position)
		var to: Vector3=arena.vector(spec.fall_position)
		var points=Crown.build_route(_mm(from),_mm(to),roundi(maxf(from.y+2,spec.fall_via_position[1])*1000))
		var result: Dictionary=arena.motion_result(points)
		_check(result.clear,"full-body fall "+str(spec.id),result)

func _mm(p: Vector3) -> Array:
	return [roundi(p.x*1000),roundi(p.y*1000),roundi(p.z*1000)]

func _check(ok: bool,label: String,detail: Dictionary={}) -> void:
	checks.append({"name":label,"passed":ok,"detail":detail})
	if not ok: failures.append(label)

func _hashes() -> Dictionary:
	var result={}
	for path in [CANDIDATE,BASELINE,"res://assets/v3/crown/parasitic_crown.glb","res://data/v3/terrain/f1_shore_layout.json","res://scripts/v3/world/twin_crown_arena.gd","res://scripts_tools/v3/capture_h10_p12.gd"]:
		result[path]=FileAccess.get_sha256(path)
	return result

func _finish() -> void:
	var file=FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"purpose":"Actual Compatibility world camera. Only this QA process replaces west H10 with the candidate and its actual trimesh collision; other runtime assets and shore foundations remain baseline. Scripted static poses, not full integration, human play or performance evidence.","checks":checks,"failures":failures,"input_sha256":input_hashes,"shots":shots},"\t"))
	file.close()
	print("H10_P12_REVIEW ",JSON.stringify({"checks":checks.size(),"failures":failures,"shots":shots.size(),"output":output}))
	if is_instance_valid(original) and not original.is_inside_tree(): original.free()
	if is_instance_valid(session):
		session.network.close()
		session.queue_free()
	quit(0 if failures.is_empty() else 1)
