extends SceneTree
## Real imported triangles and both narrow/wide production flight bodies.
## Scripted sweeps validate clearance, not propulsion, comfort or appearance.
const Main = preload("res://scenes/v3/main.tscn")
var session
var checks: Array = []
var failures: Array = []

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks.append({"label":label, "passed":ok})
	if not ok: failures.append(label)

func place(at: Vector3) -> void:
	var body = session.players[1]
	body.freeze = true
	body.set_process(false)
	body.set_physics_process(false)
	body.global_position = at
	body.linear_velocity = Vector3.ZERO
	await physics_frame
	await physics_frame

func passage(from: Vector3, to: Vector3, label: String) -> void:
	await place(from)
	var collision = session.players[1].move_and_collide(to - from)
	if collision != null: print("TRAVERSAL_HIT ", label, " at=", collision.get_position(), " body=", collision.get_collider().get_path())
	check(collision == null and session.players[1].global_position.distance_to(to) < 0.05, label)

func landing(at: Vector3, asset: Node3D, label: String) -> void:
	await place(at)
	var collision = session.players[1].move_and_collide(Vector3.DOWN * 6)
	check(collision != null and collision.get_collider() == asset.collision_body and collision.get_normal().y > 0.6, label)

func _run() -> void:
	var profile = ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile = arg.trim_prefix("--qa-profile=")
	if not profile.begins_with("qa_traversal_") or profile != profile.validate_filename() or DirAccess.dir_exists_absolute("user://profiles_v3/" + profile):
		quit(2)
		return
	session = Main.instantiate()
	root.add_child(session)
	check(session.start_flight("solo"), "isolated production session starts")
	session.set_process(false)
	session.set_physics_process(false)
	session.inputs.set_process(false)
	session.inputs.set_physics_process(false)
	for region in ["I1", "F1"]:
		session._load_region(region)
		var asset = session.world.art_traversal
		check(is_instance_valid(asset) and asset.imported, region + " imports authored GLB and required nodes")
		if not is_instance_valid(asset) or not asset.imported: continue
		check(asset.collision_mesh_count == (3 if region == "I1" else 2), region + " collidable mesh count")
		var triangles_only = true
		for shape in asset.collision_body.get_children(): triangles_only = triangles_only and shape.shape is ConcavePolygonShape3D
		check(triangles_only, region + " uses actual triangles preserving holes, never whole-volume boxes")
		if region == "I1":
			check(asset.marker_position("DeckLanding").distance_to(Vector3(0, 8.9, -8)) < 0.01, "industrial deck anchor retains authored transform")
		else:
			check(asset.marker_position("Crown").distance_to(Vector3(0, 9.5, -6)) < 0.01, "root crown anchor retains authored transform")
		for frame in ["tr01", "hx02"]:
			session.players[1].configure(CatalogV2.resolve_build(CatalogV2.default_build(frame)))
			if region == "I1":
				await passage(Vector3(0, 4, -14), Vector3(0, 4, -2), frame + " flies under industrial deck")
				await passage(Vector3(0, 4, -2), Vector3(0, 4, -14), frame + " returns through industrial underpass")
				await passage(Vector3(-16, 9.5, -8), Vector3(16, 9.5, -8), frame + " crosses industrial deck above panels")
				await landing(Vector3(0, 12, -8), asset, frame + " lands on imported industrial panels")
				await place(Vector3(0, 8.5, -8))
				var rail = session.players[1].move_and_collide(Vector3(0, 0, 6))
				check(rail != null and rail.get_collider() == asset.collision_body, frame + " low crossing respects visible industrial railing")
			else:
				await passage(Vector3(0, 3.25, -16), Vector3(0, 3.25, 4), frame + " flies through root arch opening")
				await passage(Vector3(0, 3.25, 4), Vector3(0, 3.25, -16), frame + " returns through root opening")
				await landing(Vector3(0, 14, -6), asset, frame + " lands on imported root crown")
				await place(Vector3(-19, _root_top(-19) + 1.8, -6))
				var blocked = false
				for step in range(1, 96):
					var x = lerpf(-19, 19, float(step) / 95)
					var to = Vector3(x, _root_top(x) + 1.8, -6)
					if session.players[1].move_and_collide(to - session.players[1].global_position) != null:
						blocked = true
						break
				check(not blocked and session.players[1].position.x > 18.9, frame + " follows continuous arched upper route without hidden blockers")
	var output = "res://artifacts/v3/traversal-" + profile + ".json"
	var file = FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks, "failures":failures, "scope":"scripted actual flight-body sweeps against imported triangles; not human handling, visual approval or performance"}, "\t"))
	file.close()
	print("V3_TRAVERSAL_RESULT ", JSON.stringify({"checks":checks.size(), "failures":failures, "report":output}))
	session.network.close()
	session.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _root_top(x: float) -> float:
	return 4.5 + 5.0 * (1.0 - pow(x / 20.0, 2))
