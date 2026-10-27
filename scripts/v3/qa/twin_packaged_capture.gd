extends Node
## Opt-in QA driver included in the package. Never loaded during normal play.
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const FacilityContract = preload("res://scripts/v3/network/twin_facility_contract.gd")
const SnapshotCodec = preload("res://scripts/v3/network/twin_snapshot_codec.gd")
const CLINIC_DT := 1.0 / 60.0
const CLINIC_TARGET_ML := 2000000
var clinic_steps := 0
var clinic_checks: Array = []
var clinic_windows: Array = []
var facility_checks: Array = []
var waterfront_checks: Array = []

func run(session, output: String) -> void:
	if not output.is_absolute_path() or DisplayServer.get_name() == "headless":
		push_error("Packaged capture needs an absolute output folder and a rendered viewport")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	if not session.start_flight("solo"):
		get_tree().quit(1)
		return
	session.set_process(false)
	session.set_physics_process(false)
	session.inputs.set_process(false)
	session.inputs.set_physics_process(false)
	var shots: Array = []
	for view in ["I1", "F1", "I1-whale", "I1-overpass", "F1-root-arch", "I1-ecology", "F1-crown", "F1-shore", "F1-growth-gap", "F1-growth-open", "I1-thermal", "I1-underdeck-south", "I1-underdeck-inside"]:
		var region = "F1" if view.begins_with("F1") else "I1"
		if not session._load_region(region):
			get_tree().quit(1)
			return
		var body = session.players[1]
		body.freeze = true
		body.set_process(false)
		body.set_physics_process(false)
		body.position = Vector3(-36, 5.2, 3) if region == "I1" else Vector3(-21, 5.5, 27)
		if view == "I1-whale":
			body.position = Vector3(14, 10, -25)
			session.world.set_boss_state({"phase":"exposed", "nodes_open":true, "nodes":{"port":{"powered":false}, "starboard":{"powered":false}}})
		elif view == "I1-overpass": body.position = Vector3(0, 6, -8)
		elif view == "F1-root-arch": body.position = Vector3(0, 7, -6)
		elif view == "F1-crown": body.position = Vector3(8, 13, -23)
		elif view == "F1-shore": body.position = Vector3(0, 6, 18)
		elif view == "I1-thermal": body.position = Vector3(-29, 4, 12)
		elif view == "I1-underdeck-south": body.position = Vector3(-35, 2.05, -16.8)
		elif view == "I1-underdeck-inside": body.position = Vector3(-35, 2.05, -23.5)
		elif view.begins_with("F1-growth"):
			if view == "F1-growth-open":
				await _place(session, Vector3(-24,5.2,29))
				for i in range(2): _ability(session,"light","F1:mirror")
				await _advance(session,100)
				await _place(session, Vector3(-18,6.4,29))
				for i in range(2): _ability(session,"growth","F1:growth")
				session.world.synchronize(session.entities,0.0)
				await _place(session,Vector3(-14,2.5,20))
				_ability(session,"charge","F1:relay")
				await _advance(session,100)
			body.position = Vector3(0,5,25)
		elif view == "I1-ecology":
			body.position = Vector3(-14, 2, 20)
			for attempt in range(2):
				session.cooldowns[1] = 0.0
				session._action_received(1, "ability", {"ability":"charge", "target_id":"I1:relay"})
			for tick in range(140): session.ecology.advance(1.0)
			session.world.synchronize(session.entities, 0.0)
			body.position = Vector3(-28, 4, 14)
		body.linear_velocity = Vector3.ZERO
		session.flight_camera.target_size = 26
		if view == "I1-overpass": session.flight_camera.target_size = 36
		elif view == "F1-root-arch": session.flight_camera.target_size = 38
		elif view == "F1-crown": session.flight_camera.target_size = 32
		elif view == "F1-shore": session.flight_camera.target_size = 42
		elif view.begins_with("F1-growth"): session.flight_camera.target_size = 35
		elif view == "I1-ecology": session.flight_camera.target_size = 23
		elif view == "I1-thermal": session.flight_camera.target_size = 12
		session.flight_camera.snap(body.position)
		if view == "I1-thermal": session.flight_camera.snap(Vector3(-29, 1, 8))
		session.ecology.update_view(1.0, body.position)
		session._refresh_interface()
		session.interface.vitals.text = "包内实际游戏视口 · 脚本摆位 · 非真人试玩" if not OS.has_feature("editor") else "源码实际游戏视口 · 脚本摆位 · 非真人试玩"
		if view.begins_with("I1-underdeck"):
			await get_tree().physics_frame
			await get_tree().physics_frame
			for i in range(20):
				session._update_terrain_visibility(body, 1.0 / 60.0)
				await get_tree().process_frame
		await get_tree().create_timer(0.35).timeout
		await RenderingServer.frame_post_draw
		var path = output.path_join(view + "-packaged.png")
		var result = get_viewport().get_texture().get_image().save_png(path)
		if result != OK:
			push_error("Packaged capture failed: " + str(result))
			get_tree().quit(2)
			return
		shots.append({"view":view,"region":region,"path":path,"task_panel_height":session.interface.task_panel.size.y,"task_panel_min_height":session.interface.task_panel.get_combined_minimum_size().y,"terrain_modules":session.world.terrain_modules.size(),"landmark_imported":session.world.art_bridge.imported if region == "I1" else session.world.art_temple.imported,"prop_imported":session.world.art_relay.imported if region == "I1" else session.world.art_roots.imported,"whale_imported":session.world.whale_ready() if region == "I1" else false,"traversal_imported":session.world.art_traversal.imported,"ecology_actors":session.ecology.view.targets.size(),"coolant":session.ecology.facilities.coolant,"deliveries":session.ecology.facilities.deliveries})
		shots[-1]["crown_imported"] = region == "F1" and session.world.crown_arena.imported
		shots[-1]["seal_imported"] = region == "F1" and session.world.gate.get("imported") == true
		shots[-1]["seal_triangles"] = session.world.gate.get("triangles") if region == "F1" else 0
		shots[-1]["shore_verification"] = session.world.shore_verification.duplicate(true)
		shots[-1]["raw_glb_present"] = FileAccess.file_exists("res://assets/v3/root_buttress/root_buttress_h10.glb")
		shots[-1]["ground_materials"] = _ground_materials(session.world)
		if view.begins_with("I1-underdeck"):
			var passage = session.world.underdeck
			var floor_mesh = passage.shell.get_node("PermanentNavigation/Surface")
			var floor_opaque := true
			for surface in range(floor_mesh.mesh.get_surface_count()):
				floor_opaque = floor_opaque and is_equal_approx(floor_mesh.get_active_material(surface).albedo_color.a, 1.0)
			shots[-1]["underdeck"] = {"configured":passage.configured,"state":passage.snapshot(),
				"authored_gates":_underdeck_art(passage),
				"authored_shell":_underdeck_shell(passage),
				"floor_opaque":floor_opaque,"cover_faded":session.terrain_visibility.occluded,
				"collision_triangles":int(passage.geometry_faces().size() / 3),
				"front_target_matches_body":session.entities["I1:underdeck_grille"].position.distance_to(passage.gates.front.global_position) < 0.001,
				"fixture":"scripted frozen body pose; no new action completion"}
		if view == "I1-thermal":
			var thermal = session.world.art_thermal
			var surfaces := 0
			var triangles := 0
			var meshes = thermal.visual.find_children("*", "MeshInstance3D", true, false)
			for mesh in meshes:
				surfaces += mesh.mesh.get_surface_count()
				for surface in range(mesh.mesh.get_surface_count()):
					triangles += int(mesh.mesh.surface_get_array_index_len(surface) / 3.0)
			var collider = session.world.objects["I1:thermal"].find_children("*", "CollisionShape3D", true, false)[0]
			shots[-1]["thermal"] = {"imported":thermal.imported,"import_errors":thermal.import_errors,
				"meshes":meshes.size(),"surfaces":surfaces,"triangles":triangles,
				"old_placeholder_hidden":not session.world.objects["I1:thermal"].get_node("Shape").visible,
				"collision_box":str(collider.shape.size),"temperature":session.entities["I1:thermal"].temperature,
				"powered":session.entities["I1:thermal"].powered}
		if view.begins_with("F1-growth"):
			shots[-1]["growth_crossing"] = {"bridge_visible":session.world.growth_bridge.visible,"bridge_collision":session.world.growth_bridge.collision_layer,"gate_fraction":session.world.gate_fraction,"approaches_loaded":session.world.has_node("GrowthApproach_west") and session.world.has_node("GrowthApproach_east"),"abilities_total":session.stats.abilities,"rejected_total":session.stats.rejected_abilities}
	if not await _capture_clinic(session, output, shots):
		get_tree().quit(1)
		return
	if not await _capture_facilities(session, output, shots):
		get_tree().quit(1)
		return
	if not await _capture_waterfront(session, output, shots):
		get_tree().quit(1)
		return
	if not await _capture_extensions(session, output, shots):
		get_tree().quit(1)
		return
	var file = FileAccess.open(output.path_join("capture.json"), FileAccess.WRITE)
	if file == null:
		push_error("Packaged capture report could not be opened")
		get_tree().quit(2)
		return
	file.store_string(JSON.stringify({"purpose":"packaged runtime resource and graphics verification; scripted camera, not human play or performance", "executable":OS.get_executable_path(), "editor_binary":OS.has_feature("editor"),"version":ProjectSettings.get_setting("application/config/version"),"protocol":session.network.PROTOCOL,"content":_content_manifest(session),"facility_contract":{"version":FacilityContract.VERSION,"fingerprint":FacilityContract.fingerprint(),"definitions":FacilityContract.DEFINITIONS},"driver":RenderingServer.get_video_adapter_name(),"viewport":str(get_viewport().size),"shots":shots,"clinic_checks":clinic_checks,"clinic_live_windows":clinic_windows,"facility_checks":facility_checks,"waterfront_checks":waterfront_checks,"waterfront_scope":"Canal overview plus pit/default and north-closure QA poses. Final original Ground body with intentional pit shape replacement, raw remaining surface arrays, imported east paving/closure/pit PBR, first-hit rays and unchanged water samples. Normal camera cutaway; image review covers visible seam portions only. No source GLB byte check, traversal, progress, performance or final-art claim.","clinic_scope":"Direct _load_region(I2) initializes actual packaged resources. No historical goals, clinic goals or G completion are injected. Frozen pilot poses; one actual push ability and bounded production fixed updates. I2 has authored gravity/reception/paving within unfinished graybox surroundings; no mainline completion, human play or performance claim.","facility_scope":"Three additional production-world views check four live modules, exact serialized Store envelopes, real PhysicsServer transforms and protocol21 lossless local codec. No historical27 fixture, observation, trial sample or bridge choice is injected; no ENet/reconnect or complete action claim."}, "\t"))
	file.close()
	print("V3_PACKAGED_CAPTURE ", output, " shots=", shots.size())
	session._quit()

func _content_manifest(session) -> Dictionary:
	var definitions: Dictionary = session.story.director.definitions()
	var ids: Array = []
	var objectives := 0
	for action in definitions.get("actions", []):
		ids.append(str(action.id))
		objectives += action.objectives.size()
	return {"actions":ids.size(), "objectives":objectives, "action_ids":ids,
		"completed":session.story.state.get("completed", []).duplicate(), "historical_fixture_used":false}

func _capture_facilities(session, output: String, shots: Array) -> bool:
	# Reuse the actual I2 World left by the hydraulic capture. No second module,
	# saved success state or trusted historical-goal fixture is installed.
	var content := _content_manifest(session)
	if not _facility_check(content.actions == 9 and content.objectives == 34 and session.network.PROTOCOL == 21,
		"packaged production definitions contain nine actions /34 objectives and protocol21"): return false
	var baseline_story: Dictionary = session.story.state.duplicate(true)
	var baseline_personal: Dictionary = session.store.snapshot().personal.duplicate(true)
	for row in [["I2-distribution", Vector3(17.8,2.7,-7.85)],
		["I2-trial-connected", Vector3(18,2.5,-.5)],
		["I2-shared-access", Vector3(19.7,8.6,3.25)]]:
		var view: String = row[0]
		await _place_clinic(session, row[1])
		if not _facility_check(_clinic_body_clear(session), "full pilot envelope clear: " + view): return false
		if not _facility_check(session._save_environment(), "save four actual facility envelopes: " + view): return false
		var before: Dictionary = session.facilities.persistent_states()
		var reread = Store.new(session.store.root_path)
		var loaded: Dictionary = reread.load_profile()
		var disk: Dictionary = reread.snapshot()
		if not _facility_check(loaded.ok and _same(session.store.snapshot(), disk), "independent Store rereads current complete profile: " + view): return false
		session.flight_camera.target_size = 26.0
		session.flight_camera.snap(session.players[1].global_position)
		for unused in range(18):
			session._process(1.0 / 30.0)
			await RenderingServer.frame_post_draw
		session._refresh_interface()
		await RenderingServer.frame_post_draw
		var proof := _facility_probe(session, disk)
		proof.capture_state_stable = _same(before, session.facilities.persistent_states())
		proof.story_and_personal_unchanged = _same(baseline_story, session.story.state) and _same(baseline_personal, session.store.snapshot().personal)
		if not _facility_check(proof.ok and proof.capture_state_stable and proof.story_and_personal_unchanged,
			"four live facilities / serialized states / physics / codec and no results injected: " + view):
			print("PACKAGED_FACILITY_FAILURE ", JSON.stringify({"view":view,"proof":proof}))
			return false
		var path: String = output.path_join(view + "-packaged.png")
		var frame: Image = get_viewport().get_texture().get_image()
		if not _facility_check(frame != null and not frame.is_empty() and frame.save_png(path) == OK, "save rendered facility frame: " + view): return false
		shots.append({"view":view,"region":"I2","path":path,"camera_size":session.camera.size,
			"viewport":_vec2(get_viewport().size),"body_position":_vec(session.players[1].global_position),
			"task_panel_height":session.interface.task_panel.size.y,"task_panel_min_height":session.interface.task_panel.get_combined_minimum_size().y,
			"facilities":proof,"fixture":"direct QA I2 initialization, frozen collision-checked pose; no historical27, observation, sample or choice fixture"})
	return true

func _facility_probe(session, saved: Dictionary) -> Dictionary:
	var rows: Array = []
	var valid: bool = session.region_id == "I2" and session._facilities_ready() and session.world.build_errors.is_empty()
	var modules := {"clinic":session.clinic,"distribution":session.distribution,"trial":session.trial,"shared_access":session.shared_access}
	for id: String in modules:
		var adapter = modules[id]
		var module = adapter.module
		if not is_instance_valid(module): return {"ok":false,"error":"missing_" + id}
		var snapshot: Dictionary = module.snapshot()
		# Clinic exposes its pure history/water validator, not validate_snapshot;
		# the actual mechanism was already validated by World construction.
		var checked: Dictionary = adapter.progress.validate_history(adapter.progress.snapshot(), snapshot) if id == "clinic" else module.validate_snapshot(snapshot)
		var physics: Array = []
		var aligned := true
		for body: PhysicsBody3D in module.find_children("*", "PhysicsBody3D", true, false):
			var actual: Transform3D = PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
			var matches: bool = actual.is_equal_approx(body.global_transform)
			aligned = aligned and matches
			physics.append({"node":str(module.get_path_to(body)),"scene":_vec(body.global_position),"physics":_vec(actual.origin),"matches":matches})
		var targets: Array = []
		var targets_match := true
		# The trial return switch is a G interaction, not an ability entity. All
		# colliders were checked above; only actual target_definitions map to Rules.
		for definition: Dictionary in module.target_definitions():
			var target_id: String = definition.id
			var body: PhysicsBody3D = module.target_bodies[target_id]
			var actual: Transform3D = PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
			var matches: bool = session.entities.has(target_id) and session.entities[target_id].position.distance_to(body.global_position) < .001 and actual.is_equal_approx(body.global_transform)
			targets_match = targets_match and matches
			targets.append({"id":target_id,"position":_vec(body.global_position),"matches":matches})
		var key: String = "I2_water" if id == "clinic" else ("I2_trial_flow" if id == "trial" else "I2_" + id)
		var envelope: Dictionary = adapter.persistent_state()
		var persisted: bool = not envelope.is_empty() and _same(_json_roundtrip(envelope), saved.world.environment.get(key, {}))
		var owned: bool = session.world.get(id) == module and module.is_inside_tree() and module.get_world_3d() == session.world.get_world_3d()
		var passed: bool = bool(adapter.ready) and str(adapter.error).is_empty() and module.authority and owned and checked.ok and persisted and not physics.is_empty() and not targets.is_empty() and aligned and targets_match
		valid = valid and passed
		rows.append({"id":id,"ok":passed,"ready":adapter.ready,"world_owned":owned,"authority":module.authority,
			"snapshot_validation":checked,"persisted":persisted,"state":envelope,"physics_matches":aligned,"physics":physics,"targets_match":targets_match,"targets":targets})
	var packet: Dictionary = session._snapshot()
	var wire: Dictionary = SnapshotCodec.encode(packet)
	var decoded: Dictionary = SnapshotCodec.decode(wire) if not wire.is_empty() else {}
	var codec_matches: bool = not wire.is_empty() and _same(packet, decoded)
	var refs: Array = packet.get("facility_refs", [])
	var valid_refs: bool = FacilityContract.valid_refs(refs) and refs.size() == 4
	var connection: Dictionary = session.trial.module.connection_status()
	var bridge: Dictionary = session.shared_access.module.status()
	var access: Dictionary = session.shared_access.module.access_report()
	var bridge_art := _bridge_art_probe(session.shared_access.module)
	var hashes: Dictionary = {}
	for name in ["i2_clinic_layout", "i2_distribution_layout", "i2_trial_flow_layout", "i2_shared_access_layout"]:
		hashes[name] = FileAccess.get_sha256("res://data/v3/terrain/" + name + ".json")
	return {"ok":valid and codec_matches and valid_refs and connection.ok and bridge.pose_valid and bridge.locked and access.choice_ready and bridge_art.ok,
		"modules":rows,"refs":refs,"refs_valid":valid_refs,"codec_roundtrip":codec_matches,"protocol":session.network.PROTOCOL,
		"contract_fingerprint":FacilityContract.fingerprint(),"connection":connection,"bridge":bridge,"access":access,"bridge_art":bridge_art,"layout_hashes":hashes,
		"network_scope":"local lossless encode/decode only; no ENet, guest restore or late-packet proof"}

func _facility_check(ok: bool, label: String) -> bool:
	facility_checks.append({"name":label,"passed":ok})
	if not ok: push_error("PACKAGED_FACILITY " + label)
	return ok

func _pbr_proof(meshes: Array) -> Dictionary:
	# Count imported mesh resources, not the per-instance materials created by
	# local cutaway. The currently displayed overrides must still carry PBR maps.
	var materials: Dictionary = {}
	var valid := not meshes.is_empty()
	for mesh: MeshInstance3D in meshes:
		if not mesh.mesh is ArrayMesh: return {"ok":false,"source_materials":0}
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.mesh.surface_get_material(surface) as BaseMaterial3D
			var active := mesh.get_active_material(surface) as BaseMaterial3D
			if source == null or active == null: return {"ok":false,"source_materials":0}
			materials[source.get_instance_id()] = true
			for material: BaseMaterial3D in [source, active]:
				valid = valid and material.albedo_texture is CompressedTexture2D and material.normal_texture is CompressedTexture2D and material.roughness_texture is CompressedTexture2D and material.metallic_texture is CompressedTexture2D
	return {"ok":valid,"source_materials":materials.size()}

func _maintenance_probe(module) -> Dictionary:
	var installed: Dictionary = module.ground_art.get("maintenance", {})
	if not installed.get("ok", false): return {"ok":false,"error":"maintenance_missing"}
	if installed.has("paving_batch"):
		var batch: Dictionary = installed.paving_batch
		var proof: Dictionary = preload("res://scripts/v3/art/twin_i2_paving_batch.gd").proof(batch,"maintenance")
		var actual: Array = installed.runtime_meshes
		var stats: Dictionary = _clinic_meshes(actual)
		var pbr: Dictionary = _pbr_proof(actual)
		var roots_ok: bool = installed.tiles.size()==8
		for tile: Dictionary in installed.tiles:
			roots_ok=roots_ok and is_instance_valid(tile.model) and tile.model.visible and tile.model.find_children("*","CollisionObject3D",true,false).is_empty() and tile.meshes==tile.model.find_children("*","MeshInstance3D",true,false)
		return {"ok":roots_ok and proof.ok and proof.source_meshes==12 and proof.source_triangles==14280 and proof.material_count==1 and stats.triangles==14280 and stats.meshes==installed.runtime_mesh_count and stats.surfaces==stats.meshes and pbr.ok and pbr.source_materials==1,"path":installed.path,"stats":stats,"pbr":pbr,"source_proof":proof,"batch_report":batch.report,"area_m2":installed.area_m2,"collision_scope":"visual-only; original Ground native RID/shape and full-envelope rays are checked independently"}
	var meshes: Array = []
	var rows: Array = []
	var valid := true
	for tile: Dictionary in installed.tiles:
		var actual: Array = tile.model.find_children("*", "MeshInstance3D", true, false)
		var bounds := AABB()
		var first := true
		for mesh: MeshInstance3D in actual:
			var world_bounds: AABB = mesh.global_transform * mesh.get_aabb()
			bounds = world_bounds if first else bounds.merge(world_bounds)
			first = false
		var expected: AABB = module.global_transform * tile.bounds
		var matched: bool = not first and bounds.position.is_equal_approx(expected.position) and bounds.end.is_equal_approx(expected.end) and actual == tile.meshes and tile.model.find_children("*", "CollisionObject3D", true, false).is_empty()
		valid = valid and matched
		meshes.append_array(actual)
		rows.append({"id":tile.id,"stats":_clinic_meshes(actual),"bounds_match":matched,
			"min":_vec(bounds.position),"max":_vec(bounds.end)})
	var stats := _clinic_meshes(meshes)
	var pbr := _pbr_proof(meshes)
	return {"ok":valid and rows.size() == 8 and stats.meshes == 12 and stats.surfaces == 12 and stats.triangles == 14280 and pbr.ok and pbr.source_materials == 1,
		"path":installed.path,"stats":stats,"pbr":pbr,"tiles":rows,"area_m2":installed.area_m2,
		"collision_scope":"visual paving has no body; actual Ground shape is checked separately after the waterfront replacement"}

func _bridge_art_probe(bridge) -> Dictionary:
	var layout: Dictionary = bridge.layout()
	var pose: Dictionary = bridge.status()
	var specs: Dictionary = {}
	for spec: Dictionary in layout.fixed + layout.moving + layout.pin_parts: specs[str(spec.id)] = spec
	var groups: Dictionary = {}
	var valid := true
	var total := 0
	for kind: String in ["moving", "fixed"]:
		var art: Dictionary = bridge.deck_art if kind == "moving" else bridge.landing_art
		if not art.get("ok", false): return {"ok":false,"error":"missing_bridge_" + kind}
		var rows: Array = []
		var meshes: Array = []
		for row: Dictionary in art.parts:
			var mesh: MeshInstance3D = row.mesh
			var body: StaticBody3D = row.body
			var id: String = row.id
			if not specs.has(id): return {"ok":false,"error":"unknown_bridge_part:" + id}
			var spec: Dictionary = specs[id]
			var offset := Vector3.ZERO
			if kind == "moving": offset = Vector3(0, -float(pose.pin_extension_m) if id in ["LockRod", "LockGrip"] else 0.0, float(pose.position_m))
			var expected: Transform3D = bridge.global_transform * Transform3D(Basis.IDENTITY, Vector3(15,5,0) + offset) * row.authored
			var physics: Transform3D = PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
			var old := body.get_node_or_null("Visual") as MeshInstance3D
			var shapes: Array = body.find_children("*", "CollisionShape3D", false, false)
			var collider := shapes[0] as CollisionShape3D if shapes.size() == 1 else null
			var size := Vector3(spec.size[0], spec.size[1], spec.size[2])
			var collision_ok: bool = collider != null and not collider.disabled and collider.shape is BoxShape3D and collider.shape.size.is_equal_approx(size) and collider.transform.is_equal_approx(Transform3D.IDENTITY) and body.collision_layer == (8 if kind == "moving" else 1) and body.collision_mask == 0 and physics.is_equal_approx(body.global_transform)
			var matched: bool = mesh.get_parent() == body and mesh.global_transform.is_equal_approx(expected) and mesh.transform.is_equal_approx(row.local) and mesh.is_visible_in_tree() and old != null and not old.visible and old.mesh is BoxMesh and old.mesh.size.is_equal_approx(size)
			valid = valid and collision_ok and matched
			meshes.append(mesh)
			rows.append({"id":id,"pose_matches":matched,"original_box_matches":collision_ok,"position":_vec(mesh.global_position),"expected":_vec(expected.origin)})
		var stats := _clinic_meshes(meshes)
		var pbr := _pbr_proof(meshes)
		var expected_count := 12 if kind == "moving" else 6
		valid = valid and meshes == art.model_meshes and meshes.size() == expected_count and pbr.ok and pbr.source_materials == (1 if kind == "moving" else 2)
		total += meshes.size()
		groups[kind] = {"path":art.path,"stats":stats,"pbr":pbr,"parts":rows}
	return {"ok":valid and total == 18,"mesh_count":total,"groups":groups,
		"scope":"loaded ArrayMesh/PBR and actual body binding at current public pose; moving/restore behavior belongs to separate facility regressions"}

func _capture_waterfront(session, output: String, shots: Array) -> bool:
	var before: Dictionary = session.facilities.persistent_states()
	var story: Dictionary = session.story.state.duplicate(true)
	var personal: Dictionary = session.store.snapshot().personal.duplicate(true)
	await _place_clinic(session, Vector3(15,3,23))
	if not _waterfront_check(_clinic_body_clear(session), "channel overview full pilot envelope clear"): return false
	session.flight_camera.target_size = 26.0
	session.flight_camera.snap(session.players[1].global_position)
	for unused in range(18):
		session._process(1.0 / 30.0)
		await RenderingServer.frame_post_draw
	session._refresh_interface()
	session.interface.vitals.text = "航槽实际碰撞与水域 · 脚本摆位 · 可替换灰盒，非真人飞行"
	await RenderingServer.frame_post_draw
	var proof := _waterfront_probe(session)
	proof.state_unchanged = _same(before, session.facilities.persistent_states()) and _same(story, session.story.state) and _same(personal, session.store.snapshot().personal)
	if not _waterfront_check(proof.get("ok", false) and proof.state_unchanged, "actual canal geometry / physics / water and unchanged facility results"):
		print("PACKAGED_WATERFRONT_FAILURE ", JSON.stringify(proof))
		return false
	var path: String = output.path_join("I2-waterfront-channel-packaged.png")
	var frame: Image = get_viewport().get_texture().get_image()
	if not _waterfront_check(frame != null and not frame.is_empty() and frame.save_png(path) == OK, "save actual channel overview"): return false
	shots.append({"view":"I2-waterfront-channel","region":"I2","path":path,"camera_size":session.camera.size,
		"viewport":_vec2(get_viewport().size),"body_position":_vec(session.players[1].global_position),
		"task_panel_height":session.interface.task_panel.size.y,"task_panel_min_height":session.interface.task_panel.get_combined_minimum_size().y,
		"waterfront":proof,"fixture":"production World, frozen QA pose and current pilot hull queries; no physical flight, water rescue or completion claim"})
	return true

func _waterfront_probe(session) -> Dictionary:
	var world = session.world
	var terrain = world.waterfront
	var installed: Dictionary = world.waterfront_install
	if terrain == null or not installed.get("ok", false): return {"ok":false,"error":"waterfront_missing"}
	var ground: StaticBody3D = world.clinic.fixed_bodies.Ground
	var shape_node: CollisionShape3D = installed.shape_node
	var summary: Dictionary = terrain.summary()
	var definition: Dictionary = terrain.definition()
	var actual: Transform3D = PhysicsServer3D.body_get_state(ground.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
	var pit: Dictionary = world.inspection_pit
	if not pit.get("ok",false) or not pit.has_all(["remaining_visual","remaining_collision","collision_faces"]): return {"ok":false,"error":"final_pit_geometry_missing"}
	var expected_collision: PackedVector3Array = pit.remaining_collision.faces.duplicate()
	for part: String in ["floor","walls","coping","ramp"]: expected_collision.append_array(pit.geometry[part].faces)
	# Both retained and new part geometry are World-local; Ground owns a local
	# shape at Y=-.2. Apply this offset exactly once, like the physical installer.
	for i in expected_collision.size(): expected_collision[i] -= ground.position
	var shape_matches: bool = installed.ground == ground and pit.ground == ground and shape_node.get_parent() == ground and not shape_node.disabled and shape_node.shape is ConcavePolygonShape3D and shape_node.shape == pit.shape and shape_node.shape.backface_collision and shape_node.shape.get_faces() == pit.collision_faces and pit.collision_faces == expected_collision
	var identity: bool = ground.transform.is_equal_approx(Transform3D(Basis.IDENTITY,Vector3(0,-.2,0))) and shape_node.transform.is_equal_approx(Transform3D.IDENTITY) and actual.is_equal_approx(ground.global_transform) and ground.collision_layer == 1 and ground.collision_mask == 0
	var legacy_hidden: bool = not ground.get_node("Visual").visible
	for patch: MeshInstance3D in world.clinic.ground_art.surface_patches: legacy_hidden = legacy_hidden and not patch.visible
	var meshes: Array = []
	var mesh_matches := true
	var revetment: Dictionary = world.revetment_art
	var east_revetment: Dictionary = world.east_revetment_art
	for id: String in installed.meshes:
		var mesh: MeshInstance3D = installed.meshes[id]
		var geometry: Dictionary = terrain.geometry(id)
		if revetment.get("ok",false) and id in ["bank","dry_surface"]:
			geometry = revetment.partition.geometry(id)
		if east_revetment.get("ok",false) and id in ["bank","dry_surface"]:
			geometry = east_revetment.geometry[id]
		if id == "dry_surface": geometry = world.yard_connector_art.remaining_visual
		# Mesh.get_faces() passes through TriangleMesh/BVH and may quantize; the
		# actual ArrayMesh vertex buffer is the geometry contract, without tolerance.
		var raw: Dictionary = _raw_surface_geometry(mesh.mesh)
		var vertices: PackedVector3Array = raw.faces
		var matches: bool = raw.ok and not vertices.is_empty() and vertices == geometry.faces and raw.uv == geometry.uv and mesh.global_transform.is_equal_approx(world.clinic.global_transform) and mesh.visible == (id != "bank")
		mesh_matches = mesh_matches and matches
		meshes.append({"id":id,"triangles":int(vertices.size()/3),"source_matches":matches,"visible":mesh.visible})
	var water: MeshInstance3D = installed.meshes.water
	var water_height_matches := true
	for vertex: Vector3 in water.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		water_height_matches = water_height_matches and absf((water.global_transform * vertex).y + 1.2) < .00001
	var material := water.get_active_material(0) as ShaderMaterial
	var shader_profile: Variant = material.get_shader_parameter("shore_profile") if material != null else null
	var profile_matches: bool = material != null and int(material.get_shader_parameter("shore_profile_count")) == definition.profile.size() and shader_profile is PackedVector4Array and shader_profile.size() >= definition.profile.size()
	if profile_matches:
		for i in definition.profile.size():
			var point: Vector3 = definition.profile[i]
			profile_matches = profile_matches and shader_profile[i].is_equal_approx(Vector4(point.x,point.y,point.z,0))
	var no_water_body: bool = installed.wrapper.find_children("*", "CollisionObject3D", true, false).is_empty()
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var rays: Array = []
	var rays_match := true
	for spec in [["bed",Vector3(14.75,1,6),Vector3(14.75,-3,6),Vector3(14.75,-2.8,6)],
		["paving",Vector3(23,1,0),Vector3(23,-1,0),Vector3(23,0,0)],
		["bank",Vector3(14.75,-.5,6),Vector3(12,-.5,6),Vector3(12.6,-.5,6)],
		["water_surface",Vector3(14.75,-1,6),Vector3(14.75,-1.4,6),null],
		["south_mouth",Vector3(15,-1.8,26),Vector3(15,-1.8,29),null]]:
		var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(spec[1],spec[2],1|8|32))
		var matches: bool = hit.is_empty() if spec[3] == null else (not hit.is_empty() and hit.collider == ground and hit.position.distance_to(spec[3]) < .002)
		rays_match = rays_match and matches
		rays.append({"id":spec[0],"matches":matches,"collider":str(hit.collider.get_path()) if not hit.is_empty() else "","position":_vec(hit.position) if not hit.is_empty() else []})
	var samples: Array = []
	var samples_match := true
	for spec in [[Vector3(14.75,-.5,6),true],[Vector3(14.75,-2.7,6),true],[Vector3(14.75,-2.8,6),false],[Vector3(12,-.5,6),false],[Vector3(15,0,1),false],[Vector3(15,0,29),false]]:
		var environment: Dictionary = world.sample_environment(spec[0])
		var matches: bool = environment.water == spec[1] and (not spec[1] or is_equal_approx(float(environment.water_height),-1.2))
		samples_match = samples_match and matches
		samples.append({"position":_vec(spec[0]),"water":environment.water,"water_height":environment.water_height,"matches":matches})
	var hull := _channel_hull_probe(session,space)
	var partition: bool = is_equal_approx(float(summary.cut_area_m2),212.6) and is_equal_approx(float(summary.authored_area_m2),448) and is_equal_approx(float(summary.visible_dry_area_m2),2475.4) and is_equal_approx(float(summary.cut_area_m2)+float(summary.authored_area_m2)+float(summary.visible_dry_area_m2),3136)
	var authored: Array = []
	# Bank art kept the original shape; the later pit intentionally replaced it.
	# Verify the original bank-time shape still matches the full canal contract,
	# then independently verify the final pit shape above (same Ground identity).
	var original_shape: ConcavePolygonShape3D = revetment.get("shape")
	var original_shape_matches: bool = original_shape != null and original_shape != shape_node.shape and original_shape.get_faces() == terrain.collision_faces(ground.position)
	var revetment_matches: bool = original_shape_matches and revetment.get("ok",false) and revetment.parts.size() == 4 and revetment.ground == ground
	if revetment_matches:
		for i in revetment.parts.size():
			var part: Dictionary = revetment.parts[i]
			var width := 4.0 if i < 3 else 1.3
			var z: float = [4.3,8.3,12.3,14.95][i]
			var expected := Transform3D(Basis(Vector3.UP,PI*.5),Vector3(12.6,0,z))
			var matches: bool = part.model.transform.is_equal_approx(expected) and part.mesh.visible and part.mesh.mesh.get_faces().size()/3 == part.triangles and is_equal_approx(float(part.width),width)
			revetment_matches = revetment_matches and matches
			authored.append({"id":part.id,"path":part.path,"width_m":part.width,"triangles":part.triangles,"matches":matches})
	var east_authored: Array = []
	var east_matches: bool = east_revetment.get("ok",false) and east_revetment.parts.size() == 4 and east_revetment.ground == ground and east_revetment.shape == original_shape
	if east_matches:
		for i in east_revetment.parts.size():
			var part: Dictionary = east_revetment.parts[i]
			var width := 4.0 if i < 3 else 1.3
			var z: float = [4.3,8.3,12.3,14.95][i]
			var expected := Transform3D(Basis(Vector3.UP,-PI*.5),Vector3(16.9,0,z))
			var matches: bool = part.model.transform.is_equal_approx(expected) and part.mesh.visible and part.mesh.mesh.get_faces().size()/3 == part.triangles and is_equal_approx(float(part.width),width)
			east_matches = east_matches and matches
			east_authored.append({"id":part.id,"path":part.path,"width_m":part.width,"triangles":part.triangles,"matches":matches})
	var extensions: Dictionary = _extensions_probe(session, original_shape)
	return {"ok":summary.ok and shape_matches and identity and legacy_hidden and mesh_matches and meshes.size() == 6 and water_height_matches and profile_matches and no_water_body and rays_match and samples_match and hull.ok and partition and revetment_matches and east_matches and extensions.ok,
		"summary":summary,"meshes":meshes,"shape_matches":shape_matches,"ground_identity_matches":identity,"legacy_visuals_hidden":legacy_hidden,
		"original_bank_shape_matches":original_shape_matches,"extensions":extensions,
		"collision_triangles":int(shape_node.shape.get_faces().size()/3) if shape_node.shape is ConcavePolygonShape3D else 0,
		"water_shader_profile_matches":profile_matches,"water_surface_y_matches":water_height_matches,"water_has_no_body":no_water_body,"rays":rays,"samples":samples,"hull":hull,"partition_matches":partition,
		"revetment":{"ok":revetment_matches,"parts":authored,"summary":revetment.get("summary",{})},
		"east_revetment":{"ok":east_matches,"parts":east_authored,"summary":east_revetment.get("report",{})},
		"stage":"dev28 continuous forecourt / east paving / canal banks / inspection pit; same Ground body and pit collision; surrounding area unfinished"}

func _capture_extensions(session, output: String, shots: Array) -> bool:
	var before: Dictionary = session.facilities.persistent_states()
	var story: Dictionary = session.story.state.duplicate(true)
	var personal: Dictionary = session.store.snapshot().personal.duplicate(true)
	var shape: ConcavePolygonShape3D = session.world.waterfront_install.shape_node.shape
	var shape_bytes: PackedByteArray = shape.get_faces().to_byte_array()
	for spec: Dictionary in [{"id":"I2-inspection-pit-default","at":Vector3(-19,-1.2,2.7),"zoom":0},
		{"id":"I2-closure-north","at":Vector3(14.75,1.2,3),"zoom":3}]:
		await _place_clinic(session,spec.at)
		var body: PhysicsBody3D = session.players[1]
		var server_pose: Transform3D = PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
		var pose_ok: bool = body.global_position.distance_to(spec.at)<.001 and server_pose.is_equal_approx(body.global_transform) and _clinic_body_clear(session)
		if not _waterfront_check(pose_ok,"actual Node/PhysicsServer and clear QA pose: "+spec.id): return false
		session.flight_camera.target_size = 26.0
		session.flight_camera.zoom(spec.zoom)
		session.flight_camera.snap(body.global_position)
		for unused in range(18):
			# Normal production presentation performs real-collider camera cutaway.
			# No manual alpha/visibility changes, physics ticks or objective injection.
			session._process(1.0/30.0)
			await RenderingServer.frame_post_draw
		session._refresh_interface()
		session.interface.vitals.text = "检修井 / 岸墙接缝 · 脚本摆位 · 非通关或最终美术验收"
		await RenderingServer.frame_post_draw
		var proof: Dictionary = _extensions_probe(session,session.world.revetment_art.shape)
		proof.state_unchanged = _same(before,session.facilities.persistent_states()) and _same(story,session.story.state) and _same(personal,session.store.snapshot().personal)
		proof.collision_unchanged_during_capture = session.world.waterfront_install.shape_node.shape == shape and shape.get_faces().to_byte_array() == shape_bytes
		if not _waterfront_check(proof.ok and proof.state_unchanged and proof.collision_unchanged_during_capture,"final geometry / imported PBR / unchanged results: "+spec.id):
			print("PACKAGED_EXTENSIONS_FAILURE ",JSON.stringify(proof))
			return false
		var path: String = output.path_join(spec.id+"-packaged.png")
		var frame: Image = get_viewport().get_texture().get_image()
		if not _waterfront_check(frame != null and not frame.is_empty() and frame.save_png(path)==OK,"save actual "+spec.id): return false
		shots.append({"view":spec.id,"region":"I2","path":path,"camera_size":session.camera.size,"zoom_steps":spec.zoom,
			"viewport":_vec2(get_viewport().size),"body_position":_vec(body.global_position),"physics_pose_matches":pose_ok,
			"task_panel_height":session.interface.task_panel.size.y,"task_panel_min_height":session.interface.task_panel.get_combined_minimum_size().y,
			"extensions":proof,"terrain_cutaway_active":session.terrain_visibility.occluded,
			"fixture":"Frozen QA pose, normal camera and production collider-driven cutaway. In-frame/visible seam portions require image review; not flight, completion, full-seam or final-area art acceptance."})
	return true

func _raw_surface_geometry(mesh: Mesh) -> Dictionary:
	# ArrayMesh buffers retain the original positions, normals and UV indices.
	# Mesh.get_faces() routes through TriangleMesh and is not a precision baseline.
	var result: Dictionary = {"ok":false,"faces":PackedVector3Array(),"normals":PackedVector3Array(),"uv":PackedVector2Array()}
	if not mesh is ArrayMesh or mesh.get_surface_count()!=1: return result
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	# Unindexed ArrayMesh surfaces legally leave the index slot null.
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
	var count: int = indices.size() if not indices.is_empty() else vertices.size()
	if count==0 or count%3!=0 or normals.size()!=vertices.size() or uv.size()!=vertices.size(): return result
	for corner in count:
		var index: int = indices[corner] if not indices.is_empty() else corner
		if index<0 or index>=vertices.size() or not vertices[index].is_finite() or not normals[index].is_finite() or not uv[index].is_finite(): return result
		result.faces.append(vertices[index]); result.normals.append(normals[index]); result.uv.append(uv[index])
	result.ok = true
	return result

func _face_area(faces: PackedVector3Array) -> float:
	var total := 0.0
	for first in range(0,faces.size(),3): total += (faces[first+1]-faces[first]).cross(faces[first+2]-faces[first]).length()*.5
	return total

func _imported_extension(art: Dictionary, path: String, mesh_count: int, triangles: int, surfaces: int, material_count: int, parent: Node3D, pose: Transform3D) -> Dictionary:
	if not art.get("ok",false) or not is_instance_valid(art.get("model")): return {"ok":false,"error":"missing_import","path":path}
	var model: Node3D = art.model
	var meshes: Array = model.find_children("*","MeshInstance3D",true,false)
	var stats: Dictionary = {"meshes":meshes.size(),"triangles":0,"surfaces":0}
	var bounds := AABB()
	var first := true
	for mesh: MeshInstance3D in meshes:
		if not mesh.mesh is ArrayMesh: return {"ok":false,"error":"not_array_mesh","path":path}
		var actual_bounds: AABB = mesh.global_transform * mesh.get_aabb()
		bounds = actual_bounds if first else bounds.merge(actual_bounds)
		first = false
		for surface in mesh.mesh.get_surface_count():
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			stats.triangles += int((indices.size() if not indices.is_empty() else vertices.size())/3)
			stats.surfaces += 1
	var pbr: Dictionary = _pbr_proof(meshes)
	var binding: bool = model.get_parent()==parent and model.transform.is_equal_approx(pose) and model.is_visible_in_tree() and meshes==art.meshes
	var path_matches: bool = ResourceLoader.exists(path,"PackedScene") and model.scene_file_path==path
	var no_body: bool = model.find_children("*","CollisionObject3D",true,false).is_empty()
	return {"ok":binding and path_matches and no_body and stats.meshes==mesh_count and stats.triangles==triangles and stats.surfaces==surfaces and pbr.ok and pbr.source_materials==material_count,
		"path":path,"scene_file_path":model.scene_file_path,"path_matches":path_matches,"binding_matches":binding,"visual_only":no_body,"stats":stats,"pbr":pbr,
		"bounds_min":_vec(bounds.position),"bounds_max":_vec(bounds.end),"source_glb_bytes_checked":false,"verification":"actual remapped PackedScene / ArrayMesh / imported textures; no original GLB byte claim"}

func _extensions_probe(session, original_shape: ConcavePolygonShape3D) -> Dictionary:
	var world = session.world
	var installed: Dictionary = world.waterfront_install
	var pit: Dictionary = world.inspection_pit
	var closure: Dictionary = world.revetment_closure_art
	var east: Dictionary = world.east_maintenance_art
	var yard: Dictionary = world.yard_connector_art
	if original_shape == null or not pit.get("ok",false) or not closure.get("ok",false) or not east.get("ok",false) or not yard.get("ok",false): return {"ok":false,"error":"production_extensions_missing"}
	var ground: StaticBody3D = installed.ground
	var extension: Dictionary = _imported_extension(east,"res://assets/v3/i2_east_maintenance_extension/east_maintenance_extension.glb",2,16724,2,2,installed.wrapper,Transform3D(Basis.IDENTITY,Vector3(20.7,0,8.8)))
	extension.removed_area_m2 = east.removed_area_m2
	var shore: Dictionary = _imported_extension(closure,"res://assets/v3/environment/i2_revetment_closure/revetment_closure.glb",12,32122,14,2,closure.wrapper,Transform3D.IDENTITY)
	shore.report = closure.report
	shore.json_hashes = {"i2_revetment_closure_layout":FileAccess.get_sha256(closure.plan_path),"i2_revetment_closure_delivery":FileAccess.get_sha256(closure.delivery_path)}
	shore.old_bank_hidden = not installed.meshes.bank.visible
	shore.original_collision_preserved_at_install = closure.ground==ground and closure.shape==original_shape and closure.collision_unchanged
	var pit_art: Dictionary = _imported_extension(world.inspection_pit_art,"res://assets/v3/environment/inspection_pit/inspection_pit.glb",3,19640,3,3,pit.wrapper,Transform3D(Basis.IDENTITY,Vector3(-17.625,0,5.75)))
	var yard_art: Dictionary = _imported_extension(yard,"res://assets/v3/environment/yard_connector/yard_connector_field.glb",3,1202,3,3,installed.wrapper,Transform3D(Basis.IDENTITY,Vector3(-5.7,0,19.25)))
	var old_parts: Array = []
	var parts_match := true
	for id: String in ["floor","walls","coping","ramp"]:
		var view: MeshInstance3D = pit.visuals[id]
		var raw: Dictionary = _raw_surface_geometry(view.mesh)
		var geometry: Dictionary = pit.geometry[id]
		var matches: bool = raw.ok and raw.faces==geometry.faces and raw.uv==geometry.uv and not view.visible and view.transform.is_equal_approx(Transform3D.IDENTITY)
		parts_match = parts_match and matches
		old_parts.append({"id":id,"hidden_geometry_matches":matches,"triangles":int(raw.faces.size()/3)})
	var rays: Array = []
	var rays_match := true
	for spec in [["pit_floor",Vector3(-19,-2.4,2.7)],["pit_ramp",Vector3(-19,-1.2,7.25)],["pit_yard",Vector3(-19,0,11.5)]]:
		var at: Vector3 = spec[1]
		# No exclusions: prove the actual first collider, not an isolated ground-only ray.
		var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(at.x,1,at.z),Vector3(at.x,-3,at.z),1|8|32))
		var matches: bool = not hit.is_empty() and hit.collider==ground and hit.position.distance_to(at)<.002
		rays_match = rays_match and matches
		rays.append({"id":spec[0],"matches":matches,"expected":_vec(at),"position":_vec(hit.position) if not hit.is_empty() else [],"collider":str(hit.collider.get_path()) if not hit.is_empty() else ""})
	var original_area: float = _face_area(original_shape.get_faces())
	var retained_area: float = _face_area(pit.remaining_collision.faces)
	var pit_dry_area: float = _face_area(pit.remaining_visual.faces)
	var dry_area: float = _face_area(yard.remaining_visual.faces)
	var closure_top: float = closure.report.dry_surface.removed_area_m2
	var expected_pit_dry: float = 2475.4-4.655*2-97.545-closure_top-83.125
	var expected_dry: float = expected_pit_dry-296.5806327
	var area_matches: bool = absf(float(east.removed_area_m2)-97.545)<.0002 and absf(float(pit.cut_m2)-83.125)<.0002 and absf(float(pit.visible_cut_m2)-83.125)<.0002 and absf(original_area-retained_area-83.125)<.001 and absf(pit_dry_area-expected_pit_dry)<.001 and absf(dry_area-expected_dry)<.001 and absf(float(yard.removed_area_m2)-296.5806327)<.0005 and absf(float(closure.report.bank.removed_area_m2)-94.281507675845)<.0005 and absf(closure_top-11.631794036146)<.0005
	var dry_sample: Dictionary = world.sample_environment(Vector3(-19,-1.4,2.7))
	return {"ok":extension.ok and shore.ok and pit_art.ok and yard_art.ok and shore.old_bank_hidden and shore.original_collision_preserved_at_install and parts_match and rays_match and area_matches and not dry_sample.water,
		"east_maintenance":extension,"closure":shore,"pit":pit_art,"yard":yard_art,"old_pit_parts":old_parts,"pit_rays":rays,"pit_is_dry":not dry_sample.water,
		"areas":{"ok":area_matches,"pit_cut_m2":pit.cut_m2,"pit_visible_cut_m2":pit.visible_cut_m2,"original_collision_area_m2":original_area,"retained_collision_area_m2":retained_area,"final_dry_m2":dry_area,"expected_final_dry_m2":expected_dry},
		"scope":"Actual remapped production resources and same Ground body with a new validated pit shape. Surrounding district, full seam visibility, flight and performance are not certified."}

func _channel_hull_probe(session, space: PhysicsDirectSpaceState3D) -> Dictionary:
	var body: PhysicsBody3D = session.players[1]
	var envelope := body.get_node("Envelope") as CollisionShape3D
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = envelope.shape
	query.collision_mask = 1|8|32
	query.exclude = [body.get_rid()]
	query.margin = .001
	var start := Vector3(14.75,-.35,6)
	var finish := Vector3(14.75,-.35,4)
	query.transform = Transform3D(body.global_basis,start) * envelope.transform
	var start_clear := space.intersect_shape(query,1).is_empty()
	query.transform = Transform3D(body.global_basis,finish) * envelope.transform
	var end_clear := space.intersect_shape(query,1).is_empty()
	query.transform = Transform3D(body.global_basis,start) * envelope.transform
	query.motion = finish-start
	var fraction: PackedFloat32Array = space.cast_motion(query)
	var clear: bool = fraction.size() == 2 and fraction[0] >= .99999 and fraction[1] >= .99999
	return {"ok":start_clear and end_clear and clear,"start_clear":start_clear,"end_clear":end_clear,"fractions":Array(fraction),
		"from":_vec(start),"to":_vec(finish),"scope":"current real pilot Envelope query only; no move_and_collide or flight-input simulation"}

func _waterfront_check(ok: bool, label: String) -> bool:
	waterfront_checks.append({"name":label,"passed":ok})
	if not ok: push_error("PACKAGED_WATERFRONT " + label)
	return ok

func _underdeck_shell(passage) -> Dictionary:
	# The shell also owns three old solid-column collision bodies. Their hidden
	# BoxMesh children are deliberately retained, not part of the imported art.
	var meshes: Array = []
	for path in ["PermanentNavigation/Surface", "OccludingCover/Surface", "OccludingCover/CoverDetails", "OccludingCover/RoofSupports"]:
		var part = passage.shell.get_node_or_null(path)
		if not part is MeshInstance3D or not part.mesh is ArrayMesh:
			return {"installed":false,"covers":[],"error":"missing imported ArrayMesh: " + path}
		meshes.append(part)
	var hidden_collision_visuals := 0
	var legacy_visuals_hidden := true
	for other in passage.shell.find_children("*", "MeshInstance3D", true, false):
		if other in meshes: continue
		hidden_collision_visuals += 1
		legacy_visuals_hidden = legacy_visuals_hidden and other.name == "Shape" and other.mesh is BoxMesh and not other.visible and other.get_meta("terrain_visibility_keep", false)
	var triangles := 0
	var surfaces := 0
	var textured := true
	var covers: Array = []
	for mesh in meshes:
		var alphas: Array = []
		for surface in range(mesh.mesh.get_surface_count()):
			surfaces += 1
			triangles += int(mesh.mesh.surface_get_array_index_len(surface) / 3.0)
			var material = mesh.get_active_material(surface)
			textured = textured and material is StandardMaterial3D and material.albedo_texture is CompressedTexture2D and material.normal_texture is CompressedTexture2D and material.roughness_texture is CompressedTexture2D
			alphas.append(float(material.albedo_color.a) if material is BaseMaterial3D else -1.0)
		if passage.shell.get_node("OccludingCover").is_ancestor_of(mesh):
			covers.append({"name":str(mesh.name),"detail":mesh.get_meta("terrain_visibility_cutaway_detail", false),"alphas":alphas})
	return {"installed":passage.shell.get_meta("authored_shell", false),"path":passage.shell_art.get("path", ""),"meshes":meshes.size(),"surfaces":surfaces,"triangles":triangles,"pbr_textures_imported":textured,"covers":covers,"hidden_collision_visuals":hidden_collision_visuals,"legacy_visuals_hidden":legacy_visuals_hidden}

func _capture_clinic(session, output: String, shots: Array) -> bool:
	var previous_goals: Array = session.story.state.get("completed", []).duplicate()
	var previous_discoveries: Array = session.store.snapshot().personal.discoveries.duplicate()
	var accepted_before: int = int(session.stats.abilities)
	var rejected_before: int = int(session.stats.rejected_abilities)
	if not _clinic_check(session._load_region("I2"), "direct QA region initialization succeeds"): return false
	_hold_clinic(session)
	if not _clinic_check(session.clinic.ready and session.world.clinic == session.clinic.module and session.clinic.background == null and session.world.build_errors.is_empty(), "visible production clinic is the authority module"): return false
	if not _clinic_check(int(session.clinic.module.status().clinic_volume_ml) == 0, "resource arrival starts with empty clinic water"): return false
	if not await _clinic_shot(session, output, "I2-arrival", shots, previous_goals, previous_discoveries): return false
	await _place_clinic(session, Vector3(-10, 7, -2.5))
	if not _clinic_check(_clinic_body_clear(session), "actual high-valve QA pose has full-envelope clearance"): return false
	session.selected_ability = "push_pull"
	session.locks[1] = "I2:clinic_gravity_valve"
	# No timer, energy or valve fraction is edited. A real host ability supplies
	# the guided-axis impulse; all subsequent water/geometry is production state.
	session._action_received(1, "ability", {"ability":"push_pull","target_id":"I2:clinic_gravity_valve"})
	if not _clinic_check(int(session.stats.abilities) == accepted_before + 1 and int(session.stats.rejected_abilities) == rejected_before, "one actual host push is accepted without bypassing cooldown or energy"): return false
	if not await _advance_clinic(session, 6.0, false): return false
	if not await _clinic_shot(session, output, "I2-high-valve", shots, previous_goals, previous_discoveries): return false
	await _place_clinic(session, Vector3(7, 5.8, -1))
	if not _clinic_check(_clinic_body_clear(session), "actual full-water viewing pose stays clear of the access corridor"): return false
	if not await _advance_clinic(session, 85.0, true): return false
	if not await _clinic_shot(session, output, "I2-full-water", shots, previous_goals, previous_discoveries): return false
	for row in [["I2-reception-interior",Vector3(7,6.9,-7.5)],
		["I2-reception-skylight",Vector3(7,9.2,-4)],
		["I2-gravity-undercroft",Vector3(-8.5,2,-8)],
		["I2-paving",Vector3(-19,2.4,15)]]:
		await _place_clinic(session,row[1])
		if not _clinic_check(_clinic_body_clear(session),"actual authored-space QA pose stays clear: "+str(row[0])): return false
		if not await _clinic_shot(session,output,str(row[0]),shots,previous_goals,previous_discoveries): return false
	return _clinic_check(int(session.stats.abilities) == accepted_before + 1 and int(session.stats.rejected_abilities) == rejected_before and not session.clinic.progress.snapshot().commissioned and not session.store.snapshot().world.flags.get("I2:clinic_ready", false), "hydraulic verification does not manufacture an action completion or reward")

func _hold_clinic(session) -> void:
	session.set_process(false)
	session.set_physics_process(false)
	session.inputs.set_process(false)
	session.inputs.set_physics_process(false)
	session.inputs.test_enabled = true
	session.inputs.test_frame = {"axes":{}, "held":[], "edges":[]}
	for body in session.players.values():
		body.freeze = true
		body.set_process(false)
		body.set_physics_process(false)
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO

func _place_clinic(session, at: Vector3) -> void:
	_hold_clinic(session)
	var body = session.players[1]
	body.global_transform = Transform3D(Basis.IDENTITY, at)
	body.force_update_transform()
	PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, body.global_transform)
	session.entities["player:1"].position = at
	await get_tree().physics_frame
	await get_tree().physics_frame

func _clinic_body_clear(session) -> bool:
	var body = session.players[1]
	var envelope: CollisionShape3D = body.get_node("Envelope")
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = envelope.shape
	query.transform = envelope.global_transform
	query.collision_mask = 1 | 8 | 32
	query.exclude = [body.get_rid()]
	return session.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _advance_clinic(session, limit_seconds: float, full: bool) -> bool:
	var started := Time.get_ticks_usec()
	var first_step := clinic_steps
	var reached := false
	for unused in range(int(ceil(limit_seconds / CLINIC_DT))):
		await get_tree().physics_frame
		session._physics_process(CLINIC_DT)
		clinic_steps += 1
		if not session.clinic.error.is_empty() or session.simulation_paused:
			return _clinic_check(false, "production clinic update stopped: " + session.clinic.error)
		var status: Dictionary = session.clinic.module.status()
		if full:
			reached = int(status.clinic_volume_ml) == CLINIC_TARGET_ML and absf(float(status.deck_top_y) - 5.0) < 0.001 and bool(status.inlet_closed) and session.clinic.access_clear() and int(session.clinic.progress.snapshot().stable_usec) >= 2000000
		else:
			reached = int(status.clinic_volume_ml) > 0 and float(status.gravity_fraction) >= 0.995 and session.clinic.progress.snapshot().route_method == "gravity"
		if reached: break
	_hold_clinic(session)
	clinic_windows.append({"kind":"full_water" if full else "first_gravity_transfer","fixed_steps":clinic_steps-first_step,"simulated_seconds":(clinic_steps-first_step)*CLINIC_DT,"wall_seconds":float(Time.get_ticks_usec()-started)/1000000.0,"reached":reached,"limit_seconds":limit_seconds})
	return _clinic_check(reached, "bounded production physics reaches " + ("2000L and clear raised deck" if full else "first gravity transfer"))

func _clinic_shot(session, output: String, view: String, shots: Array, previous_goals: Array, previous_discoveries: Array) -> bool:
	_hold_clinic(session)
	if not _clinic_check(session._save_environment(), "persist actual hydraulic state: " + view): return false
	var before: Dictionary = session.clinic.persistent_state()
	# Compare disk state with the exact serialization boundary used by Store.
	# Godot's JSON decoder can shift the final bit of sub-microsecond floats;
	# live-to-live capture stability below still uses exact numeric equality.
	var serialized_before: Dictionary = _json_roundtrip(before)
	var saved: Dictionary = session.store.snapshot()
	var reread = Store.new(session.store.root_path)
	var loaded: Dictionary = reread.load_profile()
	if not _clinic_check(loaded.ok and _same(saved, reread.snapshot()) and _same(saved.world.environment.I2_water, serialized_before), "separate Store rereads exact serialized water/history: " + view): return false
	session.flight_camera.target_size = 26.0
	session.flight_camera.snap(session.players[1].global_position)
	for unused in range(18):
		session._process(1.0 / 30.0)
		await RenderingServer.frame_post_draw
	session._refresh_interface()
	session.interface.vitals.text = "I2 替换式灰盒 · 包内供水专项 · 脚本摆位，非主线通关" if not OS.has_feature("editor") else "I2 替换式灰盒 · 源码供水专项 · 脚本摆位，非主线通关"
	await RenderingServer.frame_post_draw
	var probe: Dictionary = _clinic_probe(session)
	probe.persistence_matches = _same(saved.world.environment.I2_water, _json_roundtrip(session.clinic.persistent_state()))
	probe.persistence_comparison = "exact JSON roundtrip, same full-precision encoding as Store; no numeric tolerance"
	probe.store_reread_matches = loaded.ok and _same(saved, reread.snapshot())
	probe.no_new_objectives_or_discoveries = session.story.state.get("completed", []) == previous_goals and session.store.snapshot().personal.discoveries == previous_discoveries
	probe.capture_state_stable = _same(before, session.clinic.persistent_state())
	probe.fixed_steps = clinic_steps
	probe.fixture = "direct resource initialization and frozen body; no old goals, current goals or G confirmation injected"
	if not _clinic_check(probe.physics_matches and probe.targets_match and probe.deck_ray_correct and probe.water_surface_matches and probe.persistence_matches and probe.store_reread_matches and probe.no_new_objectives_or_discoveries and probe.capture_state_stable, "actual clinic collision, water, persistence and capture state: " + view): return false
	var path: String = output.path_join(view + "-packaged.png")
	var frame: Image = get_viewport().get_texture().get_image()
	if not _clinic_check(frame != null and not frame.is_empty() and frame.save_png(path) == OK, "save actual rendered clinic frame: " + view): return false
	shots.append({"view":view,"region":"I2","path":path,"task_panel_height":session.interface.task_panel.size.y,"task_panel_min_height":session.interface.task_panel.get_combined_minimum_size().y,"clinic":probe,"camera_size":session.camera.size,"body_position":_vec(session.players[1].global_position),"viewport":_vec2(get_viewport().size),"stage":"authored_clinic_partial"})
	return true

func _clinic_probe(session) -> Dictionary:
	var module = session.clinic.module
	var status: Dictionary = module.status()
	var layout: Dictionary = module.layout()
	var maximum_error := 0.0
	var poses: Array = []
	for spec in layout.moving_parts:
		var body: PhysicsBody3D = module.moving_bodies[spec.id]
		var expected := Vector3(spec.offset[0], spec.offset[1], spec.offset[2]) + Vector3.UP * float(status.deck_top_y)
		var actual: Transform3D = PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
		maximum_error = maxf(maximum_error, maxf(body.global_position.distance_to(expected), actual.origin.distance_to(expected)))
		poses.append({"id":spec.id,"scene":_vec(body.global_position),"physics":_vec(actual.origin),"expected":_vec(expected),"basis_matches":actual.basis.is_equal_approx(body.global_basis)})
	var targets_match := true
	for id in module.target_bodies:
		var target: PhysicsBody3D = module.target_bodies[id]
		var actual: Transform3D = PhysicsServer3D.body_get_state(target.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
		targets_match = targets_match and session.entities[id].position.distance_to(module.entity_position(id)) < 0.001 and actual.is_equal_approx(target.global_transform)
	var top: float = float(status.deck_top_y)
	var ray: Dictionary = module.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, top+0.5, -4), Vector3(0, top-0.5, -4), 1 | 8))
	var surface: MeshInstance3D = module.water_surfaces["I2:clinic_tank"]
	var water_level: float = float(module.water_level("I2:clinic_tank"))
	var water_ray: Dictionary = module.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0.9,water_level+0.1,-8),Vector3(0.9,water_level-0.1,-8),1|8))
	var basis_match := true
	for pose in poses: basis_match = basis_match and bool(pose.basis_matches)
	return {"module_ready":session.clinic.ready,"world_owns_module":session.world.clinic==module,"background_absent":session.clinic.background==null,"authority":module.authority,"build_errors":session.world.build_errors,"layout_sha256":FileAccess.get_sha256("res://data/v3/terrain/i2_clinic_layout.json"),"state":module.snapshot(),"status":status,"history":session.clinic.progress.snapshot(),"moving_parts":poses,"maximum_pose_error":maximum_error,"physics_matches":poses.size()==9 and maximum_error<0.001 and basis_match,"targets_match":targets_match,"deck_ray_correct":not ray.is_empty() and ray.collider==module.deck and absf(float(ray.position.y)-top)<0.002,"deck_ray_collider":str(ray.collider.get_path()) if not ray.is_empty() else "","water_mesh_y":surface.global_position.y,"water_rule_y":water_level,"water_surface_matches":absf(surface.global_position.y-water_level)<0.002,"water_is_noncolliding":water_ray.is_empty(),"physical_access":session.clinic.access_clear(),"commissioned":session.clinic.progress.snapshot().commissioned,"ready_flag":session.store.snapshot().world.flags.get("I2:clinic_ready", false),"art":_clinic_art(module)}

func _json_roundtrip(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value, "", true, true))

func _clinic_art(module) -> Dictionary:
	var gravity: Array = []
	for name in ["DeckStructure","DeckDetails","CisternStructure","CisternDetails","CisternWindow"]:
		gravity.append_array(module.find_children(name,"MeshInstance3D",true,false))
	var lens: BaseMaterial3D = module.reception_art.status_mesh.get_active_material(0)
	var court_meshes: Array = []
	var tiles: Array = []
	for tile in module.ground_art.tiles:
		court_meshes.append_array(tile.model.find_children("*","MeshInstance3D",true,false))
		tiles.append({"id":tile.id,"variant":tile.variant,"triangles":tile.triangles})
	if module.ground_art.has("paving_batch"): court_meshes=module.ground_art.runtime_meshes
	var court_proof: Dictionary = preload("res://scripts/v3/art/twin_i2_paving_batch.gd").proof(module.ground_art.paving_batch,"court") if module.ground_art.has("paving_batch") else {}
	return {"gravity":_clinic_meshes(gravity),"reception":_clinic_meshes(module.reception_art.model_meshes),
		"support":_clinic_meshes(module.reception_art.support.model_meshes),
		"paving":_clinic_meshes(court_meshes),"paving_source_proof":court_proof,
		"courtyard":_clinic_meshes(court_meshes),"courtyard_tiles":tiles,
		"maintenance":_maintenance_probe(module),
		"west_rooms":_west_rooms_probe(module),
		"service_available":bool(module.reception_art.service_available),"service_color":lens.albedo_color.to_html(false)}

func _west_rooms_probe(module) -> Array:
	var rows: Array = []
	for spec: Array in [["WestLowRoof",module.west_service_room_art,"west_service_room",3608,Vector3(4,2.5,4),Vector3(-14,1.25,-8)],
		["WestOffsetRoof",module.west_offset_room_art,"west_offset_room",5696,Vector3(3,4.1,5),Vector3(-12.5,2.05,-2.5)]]:
		var body: StaticBody3D = module.fixed_bodies[spec[0]]
		var art: Dictionary = spec[1]
		var proof_input: Dictionary = art.duplicate()
		proof_input["meshes"] = art.get("model_meshes",[])
		var origin := Vector3(0,-float(spec[4].y)*.5,0)
		var imported: Dictionary = _imported_extension(proof_input,"res://assets/v3/environment/"+spec[2]+"/"+spec[2]+".glb",3,spec[3],3,3,body,Transform3D(Basis.IDENTITY,origin))
		var shape := body.get_node("ExactBoxCollision") as CollisionShape3D
		var collision: bool = shape.shape is BoxShape3D and shape.shape.size.is_equal_approx(spec[4]) and shape.transform.is_equal_approx(Transform3D.IDENTITY) and body.transform.is_equal_approx(Transform3D(Basis.IDENTITY,spec[5])) and body.collision_layer==1 and body.collision_mask==0 and not body.get_node("Visual").visible
		rows.append({"id":spec[0],"imported":imported,"original_box_and_hidden_placeholder":collision})
	return rows

func _clinic_meshes(meshes: Array) -> Dictionary:
	var triangles := 0
	var surfaces := 0
	var textured := 0
	var normal_mapped := 0
	for mesh: MeshInstance3D in meshes:
		triangles += int(mesh.mesh.get_faces().size()/3)
		for surface in mesh.mesh.get_surface_count():
			surfaces += 1
			var material := mesh.get_active_material(surface) as BaseMaterial3D
			if material == null: continue
			if material.albedo_texture is CompressedTexture2D and material.roughness_texture is CompressedTexture2D and material.metallic_texture is CompressedTexture2D:
				textured += 1
			if material.normal_texture is CompressedTexture2D: normal_mapped += 1
	return {"meshes":meshes.size(),"triangles":triangles,"surfaces":surfaces,"textured_surfaces":textured,"normal_surfaces":normal_mapped}

func _same(a: Variant, b: Variant) -> bool:
	# JSON numbers restore as floats. Compare exact numeric values, with no
	# rounding/tolerance and no boolean or string coercion.
	if (a is int or a is float) and (b is int or b is float): return a == b
	if typeof(a) != typeof(b): return false
	if a is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not _same(a[key], b[key]): return false
		return true
	if a is Array:
		if a.size() != b.size(): return false
		for i in a.size():
			if not _same(a[i], b[i]): return false
		return true
	return a == b

func _vec(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func _vec2(value: Vector2i) -> Array:
	return [value.x, value.y]

func _clinic_check(ok: bool, label: String) -> bool:
	clinic_checks.append({"name":label,"passed":ok})
	if not ok: push_error("PACKAGED_CLINIC " + label)
	return ok

func _underdeck_art(passage) -> Array:
	var result: Array = []
	for side in ["front", "rear"]:
		var panel = passage.gates[side].get_node("AuthoredMovingPanel")
		var rail = passage.get_node("GrayboxMaintenanceMarkings/" + ("FrontFixedRail" if side == "front" else "RearFixedRail"))
		var meshes: Array = panel.find_children("*", "MeshInstance3D", true, false)
		meshes.append_array(rail.find_children("*", "MeshInstance3D", true, false))
		var surfaces := 0
		var triangles := 0
		var textured := true
		for mesh in meshes:
			for surface in range(mesh.mesh.get_surface_count()):
				surfaces += 1
				triangles += int(mesh.mesh.surface_get_array_index_len(surface) / 3.0)
				var material = mesh.get_active_material(surface)
				textured = textured and material is StandardMaterial3D and material.albedo_texture is CompressedTexture2D and material.normal_texture is CompressedTexture2D
		result.append({"side":side, "meshes":meshes.size(), "surfaces":surfaces,
			"triangles":triangles, "pbr_textures_imported":textured,
			"lamp_is_authored_lens":passage._lamps[side].name == "StatusLens"})
	return result

func _ground_materials(world) -> Array:
	var result: Array = []
	for surface in world.find_children("*", "MeshInstance3D", true, false):
		var material = surface.material_override
		if not material is ShaderMaterial or material.shader == null or material.shader.resource_path != "res://assets/v3/materials/twin_ground_study.gdshader": continue
		var texture = material.get_shader_parameter("forest_basecolor")
		var imported: bool = texture is CompressedTexture2D
		var image: Image = texture.get_image() if imported else null
		result.append({"side":material.get_shader_parameter("shore_side"), "fantasy":material.get_shader_parameter("fantasy_world"),
			"imported_texture":imported, "texture_path":texture.resource_path if imported else "",
			"width":texture.get_width() if imported else 0, "height":texture.get_height() if imported else 0,
			"mipmaps":image != null and image.has_mipmaps()})
	return result

func _place(session, at: Vector3) -> void:
	session.players[1].position=at
	session.players[1].linear_velocity=Vector3.ZERO
	session.entities["player:1"].position=at
	await get_tree().physics_frame
	await get_tree().physics_frame

func _ability(session, id: String, target: String) -> void:
	session.cooldowns[1]=0.0
	session._action_received(1,"ability",{"ability":id,"target_id":target})

func _advance(session, ticks: int) -> void:
	for i in range(ticks):
		session.world.synchronize(session.entities,1.0/60.0)
		await get_tree().physics_frame
