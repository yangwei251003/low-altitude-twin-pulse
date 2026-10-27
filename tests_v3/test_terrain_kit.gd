extends SceneTree
## Real flight-body sweeps on imported surfaces; no propulsion or aesthetic claim.
const Main = preload("res://scenes/v3/main.tscn")
var session
var checks: Array = []
var failures: Array = []
var profile = ""

func _initialize() -> void: call_deferred("_run")
func check(ok: bool, label: String) -> void:
	checks.append({"label":label,"passed":ok})
	if not ok: failures.append(label)

func place(at: Vector3) -> void:
	var body = session.players[1]
	body.freeze = true
	body.set_physics_process(false)
	body.global_position = at
	body.linear_velocity = Vector3.ZERO
	await physics_frame
	await physics_frame

func clear_path(from: Vector3, to: Vector3, label: String) -> void:
	await place(from)
	var hit = session.players[1].move_and_collide(to - from)
	if hit != null: print("TERRAIN_HIT ", label, " body=", hit.get_collider().get_path(), " position=", hit.get_position(), " normal=", hit.get_normal(), " travel=", hit.get_travel())
	check(hit == null and session.players[1].global_position.distance_to(to) < 0.05, label)

func landing(from: Vector3, distance: float, expected: Object, label: String) -> void:
	await place(from)
	var hit = session.players[1].move_and_collide(Vector3.DOWN * distance)
	check(hit != null and hit.get_collider() == expected, label)

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile = arg.trim_prefix("--qa-profile=")
	if not profile.begins_with("qa_terrain_") or DirAccess.dir_exists_absolute("user://profiles_v3/" + profile):
		quit(2)
		return
	session = Main.instantiate()
	root.add_child(session)
	session.start_flight("solo")
	session.set_process(false)
	session.set_physics_process(false)
	check(session.world.terrain_modules.size() == 6, "industrial stacked terraces and north maintenance deck are imported")
	var relay = session.world.art_relay
	check(relay.imported and relay.pivots.has("SwitchPivot") and relay.lamps.size() == 4, "authored cabinet exposes independent switch and four indicators")
	await place(Vector3(-14, 2, 20))
	session.cooldowns[1] = 0.0
	session._action_received(1, "ability", {"ability":"charge", "target_id":"I1:relay"})
	session.world.synchronize(session.entities, 0.0)
	check(is_equal_approx(relay.pivots.SwitchPivot.rotation.x, deg_to_rad(28)), "real charge opens handle away from cabinet")
	for terminal in ["Terminal_A", "Terminal_B", "Terminal_C"]:
		var ceramic_found = false
		for mesh in relay.lamps[terminal]:
			for i in range(mesh.mesh.get_surface_count()):
				if str(mesh.mesh.surface_get_material(i).resource_name).contains("IvoryWeather"):
					ceramic_found = true
					check(mesh.get_surface_override_material(i) == null, terminal + " ceramic surface retains authored material")
		check(ceramic_found, terminal + " includes its separate ceramic surface")
	session.cooldowns[1] = 0.0
	session._action_received(1, "ability", {"ability":"charge", "mode":"drain", "target_id":"I1:relay"})
	session.world.synchronize(session.entities, 0.0)
	check(relay.pivots.SwitchPivot.transform.is_equal_approx(relay.rest.SwitchPivot), "real discharge returns handle to rest")
	for frame in ["tr01", "hx02"]:
		session.players[1].configure(CatalogV2.resolve_build(CatalogV2.default_build(frame)))
		await landing(Vector3(-38.8, 7, 3), 5, session.world.terrain_modules[0].collision_body, frame + " lands on imported lower work surface")
		await landing(Vector3(-26.8, 11, -5), 5, session.world.terrain_modules[4].collision_body, frame + " lands on imported upper work surface")
		await clear_path(Vector3(-44.4, 1.6, 7.6), Vector3(-44.4, 6.0, 2.0), frame + " flies above actual inset stair slope with rotor clearance")
		await clear_path(Vector3(-40, 9.0, -5), Vector3(-28, 9.0, -5), frame + " crosses adjacent upper terrace seam")
		await place(Vector3(-40, 5.2, 3))
		session._action_received(1, "explore", {"target_id":"I1:secret:tide_priority"})
		check("secret:port:tide_priority" in session.store.snapshot().personal.discoveries, frame + " can inspect low terrace note")
		await place(Vector3(-28, 9.2, -5))
		session._action_received(1, "explore", {"target_id":"I1:secret:shared_repairs"})
		check("secret:port:shared_repairs" in session.store.snapshot().personal.discoveries, frame + " can inspect high terrace note")
	if "--with-fantasy" in OS.get_cmdline_user_args():
		session._load_region("F1")
		check(session.world.terrain_modules.size() == 3, "fantasy has two exploration outcrops and receiver footing")
		var roots = session.world.art_roots
		check(roots.imported and roots.pivots.size() == 4 and roots.lamps.has("Static_Core"), "root receiver imports four leaf pivots and independent core")
		roots.set_state({"growth":1.0,"environment_light":1.0})
		for key in roots.pivots:
			var expected: Basis = roots.rest[key].basis * Basis(Vector3.RIGHT, deg_to_rad(-58))
			check(roots.pivots[key].basis.is_equal_approx(expected), key + " opens around its own axis without losing compass orientation")
		roots.set_state({"growth":1.0,"environment_light":1.0})
		roots.set_state({"growth":0.0,"environment_light":0.0})
		for key in roots.pivots: check(roots.pivots[key].transform.is_equal_approx(roots.rest[key]), key + " repeated snapshot and close do not accumulate drift")
		for frame in ["tr01", "hx02"]:
			session.players[1].configure(CatalogV2.resolve_build(CatalogV2.default_build(frame)))
			for i in range(2):
				var terrace = session.world.terrain_modules[i]
				await clear_path(terrace.position + Vector3(0, 1.8, 5), terrace.position + Vector3(0, 1.8, -5), frame + " passes imported cave " + str(i))
				await clear_path(terrace.position + Vector3(0, 1.8, -5), terrace.position + Vector3(0, 1.8, 5), frame + " returns through imported cave " + str(i))
				await landing(terrace.position + Vector3(0, 8, 0), 6, terrace.collision_body, frame + " lands above cave " + str(i))
			await place(Vector3(-35, 1.7, -12))
			session._action_received(1, "explore", {"target_id":"F1:secret:seasonal_rest"})
			check("secret:grove:seasonal_rest" in session.store.snapshot().personal.discoveries, frame + " inspects cave note")
			await place(Vector3(35, 8.7, -13))
			session._action_received(1, "explore", {"target_id":"F1:secret:upstream_scars"})
			check("secret:grove:upstream_scars" in session.store.snapshot().personal.discoveries, frame + " inspects upper root note")
	var path = "res://artifacts/v3/terrain-kit-" + profile + ".json"
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"scope":"imported terrain and actual flight-body shape sweeps; scripted placements, no human handling claim"}, "\t"))
	file.close()
	print("TERRAIN_KIT_RESULT ", JSON.stringify({"checks":checks.size(),"failures":failures,"report":path}))
	session.network.close()
	session.free()
	quit(0 if failures.is_empty() else 1)
