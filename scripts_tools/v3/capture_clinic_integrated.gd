extends SceneTree
## Production MAIN capture, NOT a human playthrough or performance measurement.
## Run after import, --rendering-method gl_compatibility --windowed --resolution 1280x720
## --script res://scripts_tools/v3/capture_clinic_integrated.gd --
## --qa-profile=qa_visual_clinic_<unique>
## --capture-output=res://artifacts/v3/art/clinic-integrated-<unique>
## Previous 27 goals are an explicit historical fixture. New I2 facts are not seeded.
## Pilot poses are frozen QA placements; AGL remains a cached, unverified reading.
## Normal production physics is explicitly advanced once per awaited physics frame
## at 1/60s. Screenshots hold simulation and run only production presentation updates.

const MAIN = preload("res://scenes/v3/main.tscn")
const HudCapture = preload("res://scripts_tools/v3/capture_hud_visibility.gd")
const Director = preload("res://scripts/v3/gameplay/actions/twin_action_director.gd")
const HistoricalData = preload("res://tests_v3/test_clinic_action.gd")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const Works = preload("res://scripts/v3/world/twin_clinic_waterworks.gd")
const Regions = preload("res://scripts/v3/world/twin_region_catalog.gd")
const SIZE := Vector2i(1280, 720)
const DT := 1.0 / 60.0
const PREFIX := "I2:clinic_supply:"
const TARGET_ML := 2000000
const INPUTS := [
	"res://scripts_tools/v3/capture_clinic_integrated.gd",
	"res://scripts_tools/v3/capture_hud_visibility.gd",
	"res://tests_v3/test_clinic_action.gd", "res://tests_v3/test_clinic_session.gd",
	"res://project.godot", "res://scripts/v2/flight_body.gd",
	"res://scripts/v2/pilot_input.gd", "res://scripts/v2/flight_camera.gd",
	"res://assets/fonts/NotoSansSC-Medium.ttf"
]

var session
var body
var output := ""
var profile := ""
var finishing := false
var checks: Array = []
var shots: Array = []
var actions: Array = []
var placements: Array = []
var live_windows: Array = []
var input_paths: Array = []
var hashes_before: Dictionary = {}
var inventories: Dictionary = {}
var fixture: Dictionary = {}
var physical_probes: Dictionary = {}
var simulated_ticks := 0
var started_usec := 0
var capture_logger = HudCapture.CaptureLogger.new()

func _initialize() -> void:
	OS.add_logger(capture_logger)
	_run.call_deferred()

func _run() -> void:
	started_usec = Time.get_ticks_usec()
	if not _arguments_valid():
		push_error("CLINIC_CAPTURE requires a fresh qa_visual_clinic_ profile/output, debug Compatibility renderer and 60Hz physics")
		OS.remove_logger(capture_logger)
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("CLINIC_CAPTURE cannot create output directory")
		OS.remove_logger(capture_logger)
		quit(2)
		return
	create_timer(180.0, true, false, true).timeout.connect(_timeout)
	root.size = SIZE
	session = MAIN.instantiate()
	root.add_child(session)
	if not _check(session.profile_ready and session.store.root_path == "user://profiles_v3/" + profile,
		"production MAIN owns the new isolated profile"):
		await _finish()
		return
	if not _check(session.start_flight("solo") and session.region_id == "I1" and session.players.has(1), "production solo I1 starts"):
		await _finish()
		return
	_hold()
	if not _seed_history():
		await _finish()
		return
	_hold()
	body = session.players[1]
	inventories.I1 = _scene_inventory(session.world)
	input_paths.assign(INPUTS)
	for directory in ["res://scripts/v3", "res://data/v3", "res://scenes/v3"]:
		_collect_inputs(directory)
	for path in inventories.I1.imported_sources:
		if path not in input_paths: input_paths.append(path)
	for path in inventories.I1.material_sources:
		if path not in input_paths: input_paths.append(path)
	_add_import_hashes()
	hashes_before = _input_hashes()
	var complete := not hashes_before.is_empty()
	for value in hashes_before.values(): complete = complete and str(value).length() == 64
	if not _check(complete and session.world.build_errors.is_empty() and not inventories.I1.imported_sources.is_empty(), "all capture/source inputs exist and I1 uses actual imported scene geometry"):
		await _finish()
		return
	_view()
	_key(KEY_M)
	var route_button: Button = null
	var destination_name: String = str(Regions.definition("I2").name)
	for child in session.interface.travel_choices.get_children():
		if child is Button and child.text == destination_name: route_button = child
	if not _check(session.interface.travel.visible and is_instance_valid(route_button) and not route_button.disabled,
		"actual I1 M menu exposes enabled I2 destination after legal old27 history"):
		await _finish()
		return
	await _capture("01-I1-watercity-route-menu", "Actual I1 multi-destination menu; I2 itself has only the direct return route.")
	if finishing: return
	route_button.pressed.emit()
	_hold()
	await physics_frame
	await physics_frame
	if not _check(session.region_id == "I2" and session.consensus.current_proposal().is_empty()
		and session.clinic.ready and session.world.clinic == session.clinic.module
		and session.clinic.background == null and session.world.build_errors.is_empty(), "real route-button transition adopts the production visible clinic module"):
		await _finish()
		return
	body = session.players[1]
	inventories.I2 = _scene_inventory(session.world)
	# I2 is constructed only after the real travel command. Include its imported
	# GLB, material inputs and exact import cache before its first captured view.
	for path in inventories.I2.imported_sources + inventories.I2.material_sources:
		if path not in input_paths: input_paths.append(path)
	_add_import_hashes()
	for path in input_paths:
		if not hashes_before.has(path): hashes_before[path] = FileAccess.get_sha256(path)
	_check(session.clinic.module.gravity_art.get("ok", false)
		and "res://assets/v3/clinic_gravity/clinic_gravity.glb" in inventories.I2.imported_sources,
		"I2 uses the actual authored gravity GLB and records its imported resource bytes")
	_check(session.clinic.module.reception_art.get("ok", false)
		and "res://assets/v3/clinic_reception/clinic_reception.glb" in inventories.I2.imported_sources
		and "res://assets/v3/clinic_reception/clinic_reception_support.glb" in inventories.I2.imported_sources,
		"I2 uses and records the actual reception and four-post support GLBs")
	_check(session.clinic.module.ground_art.get("ok", false)
		and "res://assets/v3/clinic_ground/clinic_ground.glb" in inventories.I2.imported_sources
		and "res://assets/v3/clinic_ground/clinic_ground_plain_v2.glb" in inventories.I2.imported_sources,
		"I2 records both actual authored court GLBs")
	_check(session.story.state.completed.size() == 27 and session.clinic.progress.snapshot().route_method == ""
		and int(session.clinic.module.status().clinic_volume_ml) == 0, "I2 arrival has no seeded goals, transfer or full tank")
	await _capture("02-I2-first-arrival", "Unmodified production arrival position; same default 26m fixed oblique camera.")
	if finishing: return
	await _place(Vector3(-7, 1.8, 14.5), "outside south pump-room doorway")
	if finishing: return
	await _capture("03-I2-low-pump-entrance", "Frozen QA view outside actual 3.4m pump-room entrance; no traversal claim.")
	if finishing: return
	await _place(Vector3(-7, 1.8, 9.5), "inside low pump room")
	if finishing: return
	if not _select(KEY_0, Works.PUMP_ID):
		await _finish()
		return
	await _capture("04-I2-pump-interior-roof-fade", "Production roof occlusion assistance, actual target and UI; pump route is shown but not activated.")
	if finishing: return
	_check(_roof_probe(), "actual roof stays collidable while production terrain visibility fades the obstructing roof")
	await _place(Vector3(7, 5.8, -1), "near actual clinic diagnosis marker")
	if finishing: return
	_g("diagnose")
	if not _check(_completed("diagnose") and not _completed("connect"), "real nearby G diagnoses without manufacturing water or connect fact"):
		await _finish()
		return
	session.interface.clear_dialogue()
	await _place(Vector3(-10, 7, -2.5), "gravity valve approach used by the independent Session regression")
	if finishing: return
	if not _select(KEY_2, Works.GRAVITY_ID):
		await _finish()
		return
	var before: Dictionary = _state()
	var accepted_before: int = int(session.stats.abilities)
	var rejected_before: int = int(session.stats.rejected_abilities)
	_key(KEY_F)
	actions.append({"input":"2 / Tab / F", "before":before, "after":_state()})
	if not _check(int(session.stats.abilities) == accepted_before + 1 and int(session.stats.rejected_abilities) == rejected_before,
		"genuine selected F is accepted by Rules and Session guided-axis adapter"):
		await _finish()
		return
	if not await _advance_until("first gravity transfer and committed connect", 6.0, "transfer_committed"):
		await _finish()
		return
	_check(float(session.clinic.module.status().gravity_fraction) >= 0.995
		and session.clinic.progress.snapshot().route_method == "gravity" and _completed("connect"),
		"physical high valve reaches opening threshold and actual first transfer commits gravity method")
	await _capture("05-I2-high-gravity-valve", "Actual opened high valve and initial transfer; valve and water were not edited by the driver.")
	if finishing: return
	await _place(Vector3(7, 5.8, -1), "off the 3m access corridor, near manual confirmation marker")
	if finishing: return
	if not await _advance_until("full tank and two-second clear access", 85.0, "stable"):
		await _finish()
		return
	_check(_full_platform_checks(), "actual full-water deck, water surface and clear route satisfy physical/Story boundary")
	_check(not _completed("confirm") and not bool(session.store.snapshot().world.flags.get("I2:clinic_ready", false))
		and not bool(session.clinic.progress.snapshot().commissioned)
		and not bool(session.clinic.module.reception_art.service_available), "full platform does not auto-confirm, switch service lamp or award the discovery")
	session.interface.clear_dialogue()
	await _capture("06-I2-full-platform-awaiting-G", "Actual raised deck and 2000L state before the manual nearby confirmation.")
	if finishing: return
	_g("confirm")
	var saved: Dictionary = session.store.snapshot()
	var reread = Store.new(session.store.root_path)
	var loaded: Dictionary = reread.load_profile()
	_check(_completed("confirm") and bool(saved.world.flags.get("I2:clinic_ready", false))
		and bool(saved.world.environment.I2_water.history.commissioned)
		and bool(session.clinic.module.reception_art.service_available)
		and saved.personal.discoveries.count("I2:clinic_priority_misroute") == 1
		and loaded.ok and _same(reread.snapshot(), saved), "actual G commits result/history/discovery together and a separate Store reads identical saved bytes")
	await _capture("07-I2-confirmed-on-site", "Real saved completion and production character response, with no return-to-port reward step.")
	if finishing: return
	var committed_before_review: Dictionary = session.store.snapshot()
	var continued := 0
	while session.interface.radio.visible and continued < 32:
		_key(KEY_G)
		continued += 1
	_check(not session.interface.radio.visible and _same(session.store.snapshot(), committed_before_review),
		"actual G consumes remaining radio without repeating a nearby completion or reward")
	# Inspect the asset after the player can dismiss dialogue and select another
	# existing target. Keep normal HUD; do not hide production layers for beauty.
	if not _select(KEY_1, Works.PUMP_ID):
		await _finish()
		return
	await _place(Vector3(-8.5, 2.0, -8.0), "inside the actual four-post undercroft")
	if finishing: return
	await _capture("08-I2-gravity-undercroft-cutaway", "Actual imported deck and supports with collider-triggered production cutaway; frozen pose, not a flown route.")
	if finishing: return
	await _place(Vector3(-9.5, 8.0, -3.5), "inspect remaining source water after real delivery")
	if finishing: return
	await _capture("09-I2-source-water-zoom", "Five legal production camera zoom steps; imported material and remaining source volume after actual gravity delivery.", 5)
	if finishing: return
	await _place(Vector3(7, 6, -4), "inside open reception front passage below the central skylight")
	if finishing: return
	await _capture("10-I2-reception-passage", "Authored front floor, open passage and production service light after the actual committed G confirmation.")
	if finishing: return
	await _place(Vector3(7, 6.9, -7.5), "inside the actual rear room above desk height, clear of door pockets and furniture")
	if finishing: return
	await _capture("11-I2-reception-interior", "Actual room triangles and floor at default fixed camera; production cutaway and local indoor lights.")
	if finishing: return
	await _capture("12-I2-reception-interior-zoom", "Four legal camera zoom steps expose actual imported room materials, medical furniture and open door geometry.", 4)
	if finishing: return
	await _place(Vector3(7, 2, -6), "under the occupied clinic floor, between its four structural supports")
	if finishing: return
	await _capture("13-I2-reception-undercroft", "Real four-post support, full floor collision and production cutaway from an explicitly parked QA pose.")
	if finishing: return
	await _place(Vector3(7, 9.2, -4), "above the truly open central reception skylight")
	if finishing: return
	await _capture("14-I2-reception-skylight", "Upper default view shows the open central skylight and stepped physical enclosure; not a completed flight-path claim.")
	if finishing: return
	await _place(Vector3(-19, 2.4, 15), "above the first authored six-metre service paving near arrival")
	if finishing: return
	await _capture("15-I2-first-paving-default", "Drain edge within the new six-tile service court; surrounding untextured terrain remains unfinished.")
	if finishing: return
	await _capture("16-I2-first-paving-zoom", "Three legal zoom steps show four slabs, sealed joints, repair and flush grate; shallow drain has conservative Y0 collision, no hydraulic interaction.", 3)
	if finishing: return
	await _place(Vector3(-13,2.4,18), "middle of the authored arrival/service court")
	if finishing: return
	await _capture("17-I2-service-court", "Default 26m camera shows the full 18x12m court and its relationship to the pump-room entrance; no whole-region art acceptance.")
	if finishing: return
	await _place(Vector3(-16,2.4,15), "over the shared drain/plain joint")
	if finishing: return
	await _capture("18-I2-court-joint", "Three normal zoom steps inspect the imported full-seal edge beside the original P2 drain, not a detached Blender preview.",3)
	if finishing: return
	await _place(Vector3(5,2.4,15), "east end of the real two-module receiving approach")
	if finishing: return
	await _capture("19-I2-receiving-approach", "Default 26m view of the unscaled 12x6m extension, the open lower receiving route and the real five-metre reception level.")
	if finishing: return
	await _place(Vector3(-4,2.4,15), "old court and new approach shared half-seal edge")
	if finishing: return
	await _capture("20-I2-approach-joint", "Three legal zoom steps inspect the 20mm assembled joint between original court and new approach modules.",3)
	if finishing: return
	await _place(Vector3(23,2.4,-2), "within the three-metre east-side maintenance approach, outside the original pipe and bridge solids")
	if finishing: return
	await _capture("21-I2-maintenance-bay-default", "Actual eight-variant 160m2 work bay, shared 2K material, physical cabinet and trial station at the default game camera; surrounding terrain remains unfinished.")
	if finishing: return
	await _capture("22-I2-maintenance-bay-zoom", "Three normal zoom steps inspect imported concrete, flush inspection band and new-to-old paving edge; no changed Y0 collision or hydraulic claim.",3)
	if finishing: return
	physical_probes.court = _court_probe()
	var paving_hits: Array = []
	for point in [Vector3(-19,1,15),Vector3(-16.44,1,15),Vector3(-22.05,1,15),Vector3(-3.95,1,15),
		Vector3(-16,1,15),Vector3(-10,1,15),Vector3(-16,1,21),Vector3(-10,1,21),
		Vector3(-19,1,18),Vector3(-13,1,18),Vector3(-7,1,18),
		Vector3(-4,1,15),Vector3(2,1,15),Vector3(7.95,1,15),Vector3(8.05,1,15),Vector3(6,1,20),
		Vector3(23,1,-12),Vector3(23,1,-8),Vector3(23,1,-4),Vector3(23,1,0),Vector3(24.55,1,-2)]:
		var hit: Dictionary = session.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point, point-Vector3.UP*2, 1))
		paving_hits.append(_ray_record(hit))
		_check(hit.get("collider") == session.clinic.module.fixed_bodies.Ground and absf(float(hit.position.y)) < 0.002,
			"paving, shallow grate and outer edges retain continuous original Y0 collision: " + str(point))
	physical_probes.paving = paving_hits
	physical_probes.receiving_route = _receiving_route_probe()
	_check(int(session.stats.abilities) == 1 and int(session.stats.rejected_abilities) == 0
		and session.network.mode == "solo" and session.qa_mode.is_empty() and not session.boss_active,
		"one real gravity cast, no rejected cast, fake network, Boss or autonomous QA controller")
	await _finish()

func _receiving_route_probe() -> Array:
	var envelope := body.get_node("Envelope") as CollisionShape3D
	var result: Array = []
	for leg: Array in [[Vector3(-7,1.8,15),Vector3(6,1.8,15)],[Vector3(6,1.8,15),Vector3(6,1.8,2)],
		[Vector3(23,1.8,2),Vector3(23,1.8,-12)]]:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = envelope.shape
		query.transform = Transform3D(Basis.IDENTITY,leg[0]) * envelope.transform
		query.collision_mask = 1 | 8 | 32
		query.exclude = [body.get_rid()]
		var clear_start: bool = session.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()
		query.motion = leg[1] - leg[0]
		var travel: PackedFloat32Array = session.get_world_3d().direct_space_state.cast_motion(query)
		_check(clear_start and travel.size()==2 and travel[0]>=.99999,"real current pilot envelope clears receiving approach leg: "+str(leg))
		result.append({"from":_vec(leg[0]),"to":_vec(leg[1]),"clear_start":clear_start,"fractions":Array(travel),
			"scope":"actual current pilot shape sweep; no input-driven flight or other hull claim"})
	return result

func _court_probe() -> Dictionary:
	var art: Dictionary = session.clinic.module.ground_art
	var records: Array = []
	var boxes: Array[AABB] = []
	var material_ids: Dictionary = {}
	var faces := 0
	var surfaces := 0
	var area := 0.0
	for tile: Dictionary in art.tiles:
		var bounds := AABB()
		var first := true
		var count := 0
		for mesh: MeshInstance3D in tile.model.find_children("*","MeshInstance3D",true,false):
			var box: AABB = mesh.global_transform * mesh.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
			count += int(mesh.mesh.get_faces().size()/3)
			for surface in mesh.mesh.get_surface_count():
				surfaces += 1
				var mat := mesh.get_active_material(surface) as BaseMaterial3D
				_check(mat != null and mat.albedo_texture is CompressedTexture2D and mat.normal_texture is CompressedTexture2D
					and mat.roughness_texture is CompressedTexture2D and mat.metallic_texture is CompressedTexture2D,
					"court tile actually binds imported PBR: "+str(tile.id)+"/"+str(mesh.name))
				if not str(tile.variant).is_empty() and mat != null: material_ids[mat.get_instance_id()] = true
		_check(bounds.position.is_equal_approx(tile.bounds.position) and bounds.size.is_equal_approx(tile.bounds.size),
			"actual imported/rotated bounds match court tile: "+str(tile.id))
		boxes.append(bounds)
		faces += count
		area += bounds.size.x*bounds.size.z
		records.append({"id":tile.id,"variant":tile.variant,"min":_vec(bounds.position),"max":_vec(bounds.end),"triangles":count})
	_check(records.size()==8 and surfaces==16 and faces==8216 and absf(area-288.0)<0.01,
		"eight actual court and approach instances cover 288 square metres with sixteen surfaces and 8216 triangles")
	_check(material_ids.size()==1,"all seven ordinary tile instances share one imported PBR material")
	var bay: Dictionary = art.maintenance
	var bay_records: Array = []
	var bay_materials := {}
	var bay_area := 0.0
	var bay_faces := 0
	var bay_surfaces := 0
	for tile: Dictionary in bay.tiles:
		var bounds := AABB()
		var first := true
		for mesh: MeshInstance3D in tile.meshes:
			var actual: AABB = mesh.global_transform*mesh.get_aabb()
			bounds = actual if first else bounds.merge(actual)
			first = false
			bay_faces += int(mesh.mesh.get_faces().size()/3)
			bay_surfaces += mesh.mesh.get_surface_count()
			var material := mesh.get_active_material(0) as BaseMaterial3D
			_check(material != null and material.albedo_texture is CompressedTexture2D and material.normal_texture is CompressedTexture2D and material.roughness_texture is CompressedTexture2D and material.metallic_texture is CompressedTexture2D,"maintenance tile binds imported PBR: "+str(tile.id)+"/"+str(mesh.name))
			if material != null: bay_materials[material.get_instance_id()] = true
		_check(bounds.position.is_equal_approx(tile.bounds.position) and bounds.size.is_equal_approx(tile.bounds.size),"maintenance actual mesh bounds match planned footprint: "+str(tile.id))
		bay_area += bounds.size.x*bounds.size.z
		boxes.append(bounds)
		bay_records.append({"id":tile.id,"min":_vec(bounds.position),"max":_vec(bounds.end)})
	_check(bay_records.size()==8 and bay_faces==14280 and bay_surfaces==12 and bay_materials.size()==1 and absf(bay_area-160.0)<.01,"eight maintenance variants share one actual material and cover 160m2 with 14280 triangles")
	var overlap := false
	for a in boxes.size():
		for b in range(a+1,boxes.size()):
			var intersection := boxes[a].intersection(boxes[b])
			if intersection.size.x>0.001 and intersection.size.z>0.001: overlap=true
	_check(not overlap,"authored tiles have no positive-area coplanar overlap")
	var remainder_area := 0.0
	var remaining_boxes: Array[AABB] = []
	for rest: MeshInstance3D in art.surface_patches:
		if session.world.waterfront != null:
			_check(not rest.visible,"old rectangular surface hidden after real terrain cut: "+str(rest.name))
			continue
		var bounds: AABB = rest.global_transform * rest.get_aabb()
		remainder_area += bounds.size.x*bounds.size.z
		for previous: AABB in remaining_boxes:
			var common := bounds.intersection(previous)
			_check(common.size.x<=0.001 or common.size.z<=0.001,"remaining terrain patches do not overlap")
		remaining_boxes.append(bounds)
		for box in boxes:
			var intersection := bounds.intersection(box)
			_check(intersection.size.x<=0.001 or intersection.size.z<=0.001,"outer terrain excludes authored court: "+str(rest.name))
	var cut_area := 0.0
	if session.world.waterfront != null:
		var dry: MeshInstance3D = session.world.waterfront_install.meshes.dry_surface
		var actual_faces: PackedVector3Array = _raw_surface_faces(dry.mesh)
		var clear := true
		for i in range(0,actual_faces.size(),3):
			var a: Vector3 = dry.global_transform*actual_faces[i]
			var b: Vector3 = dry.global_transform*actual_faces[i+1]
			var c: Vector3 = dry.global_transform*actual_faces[i+2]
			remainder_area += (b-a).cross(c-a).length()*.5
			clear = clear and absf(a.y)<.001 and absf(b.y)<.001 and absf(c.y)<.001
			var triangle := PackedVector2Array([Vector2(a.x,a.z),Vector2(b.x,b.z),Vector2(c.x,c.z)])
			for region: Rect2 in art.surface_regions:
				var rectangle := PackedVector2Array([region.position,Vector2(region.end.x,region.position.y),region.end,Vector2(region.position.x,region.end.y)])
				for overlap_polygon: PackedVector2Array in Geometry2D.intersect_polygons(triangle,rectangle):
					var twice_area := 0.0
					for p in overlap_polygon.size(): twice_area += overlap_polygon[p].cross(overlap_polygon[(p+1)%overlap_polygon.size()])
					clear = clear and absf(twice_area)<.002
		_check(clear,"actual new dry triangles remain at Y0 and exclude all three authored paving regions")
		var wet: MeshInstance3D = session.world.waterfront_install.meshes.water
		var water_faces: PackedVector3Array = _raw_surface_faces(wet.mesh)
		for i in range(0,water_faces.size(),3):
			cut_area += (water_faces[i+1]-water_faces[i]).cross(water_faces[i+2]-water_faces[i]).length()*.5
		_check(absf(cut_area-212.6)<.002,"actual non-colliding river surface replaces 212.6m2 of old flat ground")
	var bank_top_footprint := 0.0
	var revetment: Variant = session.world.get("revetment_art")
	if revetment is Dictionary and revetment.get("ok",false):
		bank_top_footprint = float(revetment.summary.parts.dry_surface.removed_area_m2)
	var east_revetment: Variant = session.world.get("east_revetment_art")
	if east_revetment is Dictionary and east_revetment.get("ok",false):
		bank_top_footprint += float(east_revetment.report.parts.dry_surface.removed_area_m2)
	var east_extension_area := 0.0
	var extension: Variant = session.world.get("east_maintenance_art")
	if extension is Dictionary and extension.get("ok",false):
		east_extension_area = float(extension.removed_area_m2)
	_check(absf(remainder_area+area+bay_area+east_extension_area+cut_area+bank_top_footprint-3136.0)<0.01 and not session.clinic.module.fixed_bodies.Ground.get_node("Visual").visible,
		"rendered dry partition, authored paving, bank-top footprint and water cover original ground without coplanar mesh")
	return {"tiles":records,"triangles":faces,"surfaces":surfaces,"ordinary_material_instances":material_ids.size(),
		"authored_area_m2":area,"maintenance_tiles":bay_records,"maintenance_area_m2":bay_area,"maintenance_triangles":bay_faces,
		"remaining_area_m2":remainder_area,"east_extension_area_m2":east_extension_area,"cut_area_m2":cut_area,"bank_top_footprint_m2":bank_top_footprint,"collision":"same Ground identity; Y0 paving support with real river cut, banks and bed"}

## Mesh.get_faces() uses a snapped TriangleMesh cache. Measure the submitted
## render vertices directly so tiny valid edges keep their original positions.
static func _raw_surface_faces(mesh: Mesh) -> PackedVector3Array:
	var result := PackedVector3Array()
	for surface in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.is_empty(): result.append_array(vertices)
		else:
			for index: int in indices: result.append(vertices[index])
	return result

func _arguments_valid() -> bool:
	var profile_count := 0
	var output_count := 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="):
			profile_count += 1
			profile = arg.trim_prefix("--qa-profile=")
		elif arg.begins_with("--capture-output="):
			output_count += 1
			output = arg.trim_prefix("--capture-output=")
		else: return false
	var regex := RegEx.new()
	if regex.compile("^qa_visual_clinic_[A-Za-z0-9_-]+$") != OK: return false
	if profile_count != 1 or output_count != 1 or regex.search(profile) == null: return false
	output = ProjectSettings.globalize_path(output).replace("\\", "/").simplify_path()
	var allowed := ProjectSettings.globalize_path("res://artifacts/v3/art").replace("\\", "/").simplify_path()
	if not output.is_absolute_path() or output.get_base_dir().to_lower() != allowed.to_lower(): return false
	if not output.get_file().begins_with("clinic-integrated-") or output.get_file() == "clinic-integrated-": return false
	if DirAccess.dir_exists_absolute(output) or FileAccess.file_exists(output): return false
	if DirAccess.dir_exists_absolute("user://profiles_v3/" + profile) or FileAccess.file_exists("user://profiles_v3/" + profile): return false
	return OS.is_debug_build() and DisplayServer.get_name() != "headless" and RenderingServer.get_current_rendering_method() == "gl_compatibility" and RenderingServer.is_render_loop_enabled() and Engine.physics_ticks_per_second == 60

func _seed_history() -> bool:
	var legacy = Director.new()
	if not _check(legacy.load_definitions(Director.DEFAULT_PATH, HistoricalData.OLD_EXTENSIONS).ok, "production old-seven-action definitions load for explicit history fixture"): return false
	var state: Dictionary = legacy.default_state()
	for row in HistoricalData.OLD_EVENTS:
		var event := {"id":"qa-clinic-capture-history:" + str(row[0]), "type":row[1], "target_id":row[2], "option":row[3]}
		var result: Dictionary = legacy.apply_event(state, event, {"is_authority":true, "validated":true, "region_id":str(row[0]).get_slice(":", 0)})
		if not _check(result.get("changed", false), "trusted historical fixture accepted: " + str(row[0])): return false
		state = result.state
	if not _check(state.completed.size() == 27 and state.completed_actions.size() == 7 and session.story.director.validate_state(state).ok,
		"exact legal old27 fixture validates against production extended Director"): return false
	var result: Dictionary = session.store.commit({"id":"qa-clinic-capture-old27", "set":{
		"world.actions.opening":state, "world.flags":state.flags, "world.completed_objectives":state.completed},
		"append":{"personal.discoveries":state.discoveries}})
	if not _check(result.ok, "historical fixture uses an actual isolated Store transaction"): return false
	session.world_cache = session.store.snapshot()
	if not _check(session._load_region("I1"), "production I1 reload restores historical fixture"): return false
	session.consensus.configure([1], int(session.world_cache.world_revision))
	fixture = {"kind":"fixed_old27_legal_Director_events", "source":"res://tests_v3/test_clinic_action.gd:OLD_EVENTS",
		"completed":state.completed.duplicate(), "completed_actions":state.completed_actions.duplicate(),
		"limit":"Historical seven-action fixture only, not a seven-action playthrough. No I2 event, water, energy or health was seeded."}
	return true

func _hold() -> void:
	session.set_process(false)
	session.set_physics_process(false)
	session.inputs.set_process(false)
	session.inputs.set_physics_process(false)
	session.inputs.test_enabled = true
	session.inputs.test_frame = {"axes":{}, "held":[], "edges":[]}
	for pilot in session.players.values():
		pilot.freeze = true
		pilot.set_process(false)
		pilot.set_physics_process(false)
		pilot.linear_velocity = Vector3.ZERO
		pilot.angular_velocity = Vector3.ZERO
	session.world.set_effects_paused(true)
	paused = true

func _place(at: Vector3, reason: String) -> void:
	_hold()
	body = session.players[1]
	body.global_transform = Transform3D(Basis.IDENTITY, at)
	PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, body.global_transform)
	session.entities["player:1"].position = at
	placements.append({"position":_vec(at), "reason":reason, "kind":"frozen_QA_pose_not_flight", "cached_AGL":body.ground_distance})
	await physics_frame
	await physics_frame
	if finishing: return
	_view()
	var envelope := body.get_node("Envelope") as CollisionShape3D
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = envelope.shape
	query.transform = envelope.global_transform
	query.collision_mask = 1 | 8 | 32
	query.exclude = [body.get_rid()]
	_check(session.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(), "QA pose has actual full-envelope clearance: " + reason)

func _view() -> void:
	session.flight_camera.target_size = 26.0
	session.flight_camera.snap(session.players[1].global_position)
	session.story.refresh(session.players[1].global_position, 0.0)
	session._refresh_interface()

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	session._unhandled_input(event)

func _select(key: Key, target: String) -> bool:
	session.interface.clear_dialogue()
	_key(key)
	var count := 0
	while str(session.locks.get(1, "")) != target and count < 64:
		_key(KEY_TAB)
		count += 1
	return _check(str(session.locks.get(1, "")) == target, "real number/Tab input selects " + target)

func _g(label: String) -> void:
	session.interface.clear_dialogue()
	session.interface.menu.hide()
	_view()
	var before: Dictionary = _state()
	_key(KEY_G)
	_view()
	actions.append({"input":"G", "purpose":label, "before":before, "after":_state()})

func _advance_until(label: String, seconds: float, condition: String) -> bool:
	var begin := Time.get_ticks_usec()
	var first_tick := simulated_ticks
	var before: Dictionary = _state()
	var reached := false
	paused = false
	session.world.set_effects_paused(false)
	for unused in range(int(ceil(seconds / DT))):
		await physics_frame
		if finishing: return false
		session._physics_process(DT)
		simulated_ticks += 1
		if not session.clinic.error.is_empty() or session.simulation_paused:
			_check(false, "production update stopped: " + session.clinic.error)
			break
		var state: Dictionary = session.clinic.module.status()
		if condition == "transfer_committed":
			# Hydraulic transfer is observed every physics step; Story facts are
			# sampled at its own 0.25s cadence. Keep real ticks running until the
			# corresponding successful transaction, not merely the first wet tick.
			var history: Dictionary = session.clinic.progress.snapshot()
			var committed: Array = session.store.snapshot().world.get("completed_objectives", [])
			reached = int(state.clinic_volume_ml) > 0 and float(state.gravity_fraction) >= 0.995 \
				and history.route_method == "gravity" and int(history.first_transfer_ml) > 0 \
				and _completed("connect") and PREFIX + "connect" in committed
		elif condition == "stable":
			reached = _completed("stabilize")
		else:
			_check(false, "unknown bounded wait condition: " + condition)
			break
		if reached: break
	_hold()
	live_windows.append({"name":label, "wall_seconds":float(Time.get_ticks_usec() - begin) / 1000000.0,
		"fixed_steps":simulated_ticks - first_tick, "simulated_seconds":float(simulated_ticks - first_tick) * DT,
		"before":before, "after":_state(), "reached":reached})
	return _check(reached, "bounded real Session fixed updates reach " + label)

func _roof_probe() -> bool:
	var module = session.clinic.module
	var hit: Dictionary = session.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-7, 4, 9.5), Vector3(-7, 2.8, 9.5), 1 | 8))
	var faded := false
	for entry in session.terrain_visibility._entries.values():
		if entry.root == module.fixed_bodies.PumpRoof: faded = bool(entry.installed) and float(entry.alpha) < 0.999
	physical_probes.roof = {"from":[-7,4,9.5], "to":[-7,2.8,9.5], "hit":_ray_record(hit), "actual_roof_faded":faded}
	return not hit.is_empty() and hit.collider == module.fixed_bodies.PumpRoof and faded

func _full_platform_checks() -> bool:
	var module = session.clinic.module
	var state: Dictionary = module.status()
	var poses_ok := true
	var poses: Array = []
	for node in module.moving_bodies.values():
		var actual: Transform3D = PhysicsServer3D.body_get_state(node.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
		poses_ok = poses_ok and actual.is_equal_approx(node.global_transform)
		poses.append({"node":str(node.name), "scene_position":_vec(node.global_position), "physics_position":_vec(actual.origin), "basis_matches":actual.basis.is_equal_approx(node.global_basis)})
	var ray: Dictionary = session.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 5.5, -4), Vector3(0, 4.5, -4), 1 | 8))
	var water_ray: Dictionary = session.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0.9, 4.7, -8), Vector3(0.9, 4.3, -8), 1 | 8))
	var surface: MeshInstance3D = module.water_surfaces["I2:clinic_tank"]
	physical_probes.full = {"moving_poses":poses, "deck_ray":_ray_record(ray), "water_ray":_ray_record(water_ray),
		"water_mesh_y":surface.global_position.y, "rule_water_y":module.water_level("I2:clinic_tank"), "clear_3m_access":session.clinic.access_clear()}
	return int(state.clinic_volume_ml) == TARGET_ML and absf(float(state.deck_top_y) - 5.0) <= 0.002 and poses_ok \
		and not ray.is_empty() and ray.collider == module.deck and absf(float(ray.position.y) - 5.0) <= 0.002 \
		and water_ray.is_empty() and absf(surface.global_position.y - float(module.water_level("I2:clinic_tank"))) <= 0.002 \
		and session.clinic.access_clear() and _completed("stabilize")

func _capture(id: String, note: String, zoom_steps: int = 0) -> void:
	_hold()
	_view()
	if zoom_steps != 0:
		session.flight_camera.zoom(zoom_steps)
		session.flight_camera.snap(session.players[1].global_position)
	var view_size: float = session.flight_camera.target_size
	# Production presentation only: settle the real roof-fade/marker/layout, not water.
	var before: Dictionary = _state()
	for unused in range(18):
		session._process(1.0 / 30.0)
		await RenderingServer.frame_post_draw
		if finishing: return
	session._refresh_interface()
	await RenderingServer.frame_post_draw
	if finishing: return
	var after: Dictionary = _state()
	var picture: Image = root.get_texture().get_image()
	var path := output.path_join(id + ".png")
	if not _check(picture != null and not picture.is_empty() and picture.get_size() == SIZE and root.size == SIZE
		and session.camera.projection == Camera3D.PROJECTION_ORTHOGONAL and is_equal_approx(session.camera.size, view_size)
		and _same(before, after), "stable production camera 720p state: " + id): return
	if not _check(not FileAccess.file_exists(path) and picture.save_png(path) == OK, "write fresh viewport PNG: " + id): return
	shots.append({"id":id, "file":path, "png_sha256":FileAccess.get_sha256(path), "note":note,
		"state":after, "camera":{"size":session.camera.size, "zoom_steps_from_default":zoom_steps, "position":_vec(session.camera.global_position),
			"basis_x":_vec(session.camera.global_basis.x), "basis_y":_vec(session.camera.global_basis.y), "basis_z":_vec(session.camera.global_basis.z)},
		"ui":_ui_record(), "terrain_visibility":_fade_record(), "cached_AGL_limitation":true})

func _ui_record() -> Dictionary:
	var ui = session.interface
	var rects: Dictionary = {}
	for name in ["top_panel", "bottom_panel", "task_panel", "travel", "radio"]:
		var control: Control = ui.get(name)
		var rectangle := control.get_global_rect()
		rects[name] = {"visible":control.is_visible_in_tree(), "rect":[rectangle.position.x,rectangle.position.y,rectangle.size.x,rectangle.size.y]}
		if control.is_visible_in_tree(): _check(Rect2(Vector2.ZERO, Vector2(SIZE)).encloses(rectangle), "visible production panel stays in 720p: " + name)
	return {"rects":rects, "title":ui.title.text, "vitals":ui.vitals.text, "objective":ui.objective.text,
		"target":ui.target_info.text, "ability":ui.ability_title.text, "ability_action":ui.ability_description.text,
		"G":ui.explore_button.text, "message":ui.message.text, "speaker":ui.radio_speaker.text, "dialogue":ui.radio_text.text}

func _fade_record() -> Array:
	var result: Array = []
	for entry in session.terrain_visibility._entries.values():
		result.append({"node":str(entry.root.name), "blocked":entry.blocked, "alpha":entry.alpha, "installed":entry.installed})
	return result

func _completed(suffix: String) -> bool:
	return PREFIX + suffix in session.story.state.get("completed", [])

func _state() -> Dictionary:
	var result := {"region":session.region_id, "body":_vec(session.players[1].global_position), "health":session.players[1].health,
		"cached_AGL":session.players[1].ground_distance, "energy":session.entities["player:1"].energy,
		"cooldown":session.cooldowns.get(1, 0), "selected":session.selected_ability, "lock":session.locks.get(1, ""),
		"completed":session.story.state.get("completed", []).duplicate(), "flags":session.story.state.get("flags", {}).duplicate(true),
		"world_revision":session.store.snapshot().world_revision}
	if session.clinic.ready:
		result.clinic = session.clinic.persistent_state()
		result.clinic_status = session.clinic.module.status()
		result.physical_access = session.clinic.access_clear()
	return result

func _scene_inventory(node: Node) -> Dictionary:
	var result := {"mesh_count":0, "triangle_count":0, "collision_count":0, "imported_sources":[], "material_sources":[], "stage":"production scene"}
	_inventory_walk(node, result)
	return result

func _inventory_walk(node: Node, result: Dictionary) -> void:
	if node is CollisionObject3D: result.collision_count += 1
	if node is MeshInstance3D and node.mesh != null:
		result.mesh_count += 1
		result.triangle_count += int(node.mesh.get_faces().size() / 3.0)
		var source: String = str(node.mesh.resource_path).get_slice("::", 0)
		if source.begins_with("res://") and FileAccess.file_exists(source) and source not in result.imported_sources: result.imported_sources.append(source)
		for surface in node.mesh.get_surface_count():
			var material = node.get_active_material(surface)
			if material is BaseMaterial3D:
				for slot in ["albedo_texture", "normal_texture", "roughness_texture", "metallic_texture", "ao_texture", "emission_texture"]:
					var texture = material.get(slot)
					if texture is Texture2D: _record_material_source(str(texture.resource_path), result)
			elif material is ShaderMaterial and material.shader != null:
				_record_material_source(str(material.shader.resource_path), result)
				for parameter in material.shader.get_shader_uniform_list():
					var value = material.get_shader_parameter(parameter.name)
					if value is Texture2D: _record_material_source(str(value.resource_path), result)
	for child in node.get_children(): _inventory_walk(child, result)

func _record_material_source(path: String, result: Dictionary) -> void:
	var source := path.get_slice("::", 0)
	if source.begins_with("res://") and FileAccess.file_exists(source) and source not in result.material_sources: result.material_sources.append(source)

func _ray_record(hit: Dictionary) -> Dictionary:
	if hit.is_empty(): return {"hit":false}
	return {"hit":true, "collider":str(hit.collider.get_path()), "position":_vec(hit.position), "normal":_vec(hit.normal)}

func _collect_inputs(directory: String) -> void:
	for filename in DirAccess.get_files_at(directory):
		if filename.get_extension() in ["gd", "json", "tscn"]:
			var path := directory.path_join(filename)
			if path not in input_paths: input_paths.append(path)
	for child in DirAccess.get_directories_at(directory): _collect_inputs(directory.path_join(child))

func _add_import_hashes() -> void:
	for path in input_paths.duplicate():
		var descriptor := str(path) + ".import"
		if not FileAccess.file_exists(descriptor): continue
		if descriptor not in input_paths: input_paths.append(descriptor)
		var config := ConfigFile.new()
		if config.load(descriptor) != OK or not config.has_section("remap"): continue
		for key in config.get_section_keys("remap"):
			if key == "path" or key.begins_with("path."):
				var cache := str(config.get_value("remap", key, ""))
				if not cache.is_empty() and cache not in input_paths: input_paths.append(cache)

func _input_hashes() -> Dictionary:
	var result: Dictionary = {}
	for path in input_paths: result[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "MISSING"
	return result

func _same(a: Variant, b: Variant) -> bool:
	return JSON.stringify(a, "", true, true) == JSON.stringify(b, "", true, true)

func _vec(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func _check(ok: bool, name: String) -> bool:
	checks.append({"name":name, "passed":ok})
	return ok

func _timeout() -> void:
	if finishing:
		quit(3)
		return
	_check(false, "180 second wall-clock watchdog expired")
	_finish.call_deferred()

func _finish() -> void:
	if finishing: return
	finishing = true
	var final_state: Dictionary = _state() if is_instance_valid(session) and session.players.has(1) else {}
	if is_instance_valid(session):
		session.active = false
		if is_instance_valid(session.network): session.network.close()
		session.free()
	await process_frame
	await process_frame
	var hashes_after := _input_hashes()
	_check(not hashes_before.is_empty() and hashes_before == hashes_after, "source, scene, layout, action data and discovered imported-resource bytes stayed unchanged")
	_check(shots.size() == 22, "all twenty-two requested production views saved")
	var logged: Dictionary = capture_logger.snapshot()
	_check(int(logged.error_count) == 0, "no engine/script/shader error including cleanup")
	var passed := true
	for item in checks: passed = passed and bool(item.passed)
	var report := {"passed":passed, "status":"rendered_evidence_for_review_not_art_acceptance", "profile":profile, "output":output,
		"checks":checks, "shots":shots, "actions":actions, "fixture":fixture, "QA_placements":placements,
		"live_windows":live_windows, "nominal_fixed_step_seconds":DT, "simulated_ticks":simulated_ticks,
		"final_state":final_state, "physical_probes":physical_probes, "production_scene_inventory":inventories,
		"input_sha256_before":hashes_before, "input_sha256_after":hashes_after, "engine_log":logged,
		"engine":Engine.get_version_info(), "renderer":RenderingServer.get_current_rendering_method(),
		"GPU":RenderingServer.get_video_adapter_name(), "display":DisplayServer.get_name(), "viewport":[root.size.x,root.size.y],
		"wall_seconds":float(Time.get_ticks_usec()-started_usec)/1000000.0,
		"limits":["Historical27 is an explicit trusted QA fixture, not completion by play. New I2 facts must come from production Session/Story.",
			"Frozen pilot placements are composition fixtures, not flown routes. Cached AGL is recorded but not verified or overwritten.",
			"Production orthographic camera/lighting/materials; each shot records normal26m view or explicit legal wheel zoom. No alternative I2 scene or temporary material is built.",
			"One gravity solution is physically activated. Pump interior is inspected only; this capture is not pump-route completion coverage.",
			"One1/60s production fixed callback per awaited physics frame; no wall-clock/offline catch-up. Not a duration or performance benchmark.",
			"I2 includes the authored gravity assembly and remaining graybox. PNG generation/checks are not aesthetic acceptance or a human usability test.",
			"I1 provides the actual multiple-route menu; I2 M has only a direct return and no menu is invented.",
			"Logger cannot catch a parser error before initialization; runner must enforce process exit and require this report."]}
	var path := output.path_join("state_checks.json")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE) if not FileAccess.file_exists(path) else null
	var write_ok := file != null
	if file != null:
		file.store_string(JSON.stringify(report, "\t", true, true))
		file.flush()
		write_ok = file.get_error() == OK
		file.close()
	if not write_ok: push_error("CLINIC_CAPTURE state_checks.json write failed")
	var final_log: Dictionary = capture_logger.snapshot()
	var success: bool = passed and write_ok and int(final_log.error_count) == 0
	print("CLINIC_INTEGRATED_CAPTURE ", JSON.stringify({"passed":success,"checks":checks.size(),"shots":shots.size(),"errors":final_log.error_count,"output":output}))
	OS.remove_logger(capture_logger)
	quit(0 if success else 1)
