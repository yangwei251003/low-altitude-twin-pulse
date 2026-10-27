class_name TwinTestWorld
extends Node3D
## Partial art integration. Imported I-B/F-B assets coexist with clearly marked graybox areas.

const ServiceBridge = preload("res://scenes/v3/assets/service_bridge.tscn")
const TempleGate = preload("res://scenes/v3/assets/temple_gate.tscn")
const GroundSurface = preload("res://scripts/v3/art/twin_ground_surface.gd")
const CoastalTerrace = preload("res://scenes/v3/assets/coastal_work_terrace.tscn")
const RootstoneTerrace = preload("res://scenes/v3/assets/rootstone_terrace.tscn")
const RelayCabinet = preload("res://scenes/v3/assets/power_relay_cabinet.tscn")
const ThermalBypass = preload("res://scenes/v3/assets/thermal_bypass.tscn")
const PhotosensitiveRoots = preload("res://scenes/v3/assets/photosensitive_roots.tscn")
const BossWarning = preload("res://scripts/v3/art/twin_boss_warning.gd")
const SiphonWhale = preload("res://scenes/v3/assets/siphon_whale.tscn")
const MaintenanceOverpass = preload("res://scenes/v3/assets/maintenance_overpass.tscn")
const RootArch = preload("res://scenes/v3/assets/f1_root_arch.tscn")
const CrownArena = preload("res://scripts/v3/world/twin_crown_arena.gd")
const ShoreLayout = preload("res://scripts/v3/world/twin_shore_layout.gd")
const GrowthCrossing = preload("res://scripts/v3/world/twin_growth_crossing.gd")
const RisingSeal = preload("res://scenes/v3/assets/rising_seal.tscn")
const Underdeck = preload("res://scripts/v3/world/twin_underdeck_passage.gd")
const ClinicWaterworks = preload("res://scripts/v3/world/twin_clinic_waterworks.gd")
const DistributionCabinet = preload("res://scripts/v3/world/twin_distribution_cabinet.gd")
const TrialAssembly = preload("res://scripts/v3/world/twin_trial_assembly.gd")
const TrialPresentation = preload("res://scripts/v3/world/twin_trial_flow_presentation.gd")
const CanalBufferLayout = preload("res://scripts/v3/world/twin_canal_buffer_layout.gd")
const SharedAccessBridge = preload("res://scripts/v3/world/twin_shared_access_bridge.gd")
const SharedBridgeArt = preload("res://scripts/v3/art/twin_shared_bridge_art.gd")
const SharedLandingArt = preload("res://scripts/v3/art/twin_shared_landing_art.gd")
const WaterfrontTerrain = preload("res://scripts/v3/world/twin_i2_waterfront_terrain.gd")
const RevetmentArt = preload("res://scripts/v3/art/twin_i2_revetment_art.gd")
const EastRevetmentArt = preload("res://scripts/v3/art/twin_i2_east_revetment_art.gd")
const EastMaintenanceArt = preload("res://scripts/v3/art/twin_i2_east_maintenance_art.gd")
const RevetmentClosureArt = preload("res://scripts/v3/art/twin_i2_revetment_closure_art.gd")
const InspectionPit = preload("res://scripts/v3/world/twin_i2_inspection_pit.gd")
const InspectionPitArt = preload("res://scripts/v3/art/twin_i2_inspection_pit_art.gd")
const YardConnectorArt = preload("res://scripts/v3/art/twin_i2_yard_connector_art.gd")
const ThermalStoneArt = preload("res://scripts/v3/art/twin_f1_thermal_stone_art.gd")
const CentralApronArt = preload("res://scripts/v3/art/twin_central_service_apron_art.gd")
const I4Storm = preload("res://scripts/v3/environment/twin_i4_storm_environment.gd")
const CampaignLayout = preload("res://scripts/v3/campaign/twin_campaign_layout.gd")
const CampaignDressing = preload("res://scripts/v3/campaign/twin_campaign_set_dressing.gd")
const PumpMechanisms = preload("res://scripts/v3/gameplay/twin_pump_guardian_mechanisms.gd")
const ThermalCargo = preload("res://scripts/v3/gameplay/twin_thermal_cargo_session.gd")
const CampaignCatalog = preload("res://scripts/v3/campaign/twin_campaign_catalog.gd")
const CampaignArena = preload("res://scripts/v3/world/twin_campaign_arena.gd")
const CampaignMechanismView = preload("res://scripts/v3/world/twin_campaign_mechanism_view.gd")
var central_service_apron_art: Dictionary = {}
var campaign_arena: Node3D
var campaign_mechanism_view: Node3D
var campaign_layout: Dictionary = {}
var campaign_body_aliases: Dictionary = {}

var region_id = "I1"
var objects: Dictionary = {}
var definitions: Dictionary = {}
var initial_transforms: Dictionary = {}
var gate: AnimatableBody3D
var platform: AnimatableBody3D
var growth_bridge: StaticBody3D
var boss_root: Node3D
var boss_parts: Dictionary = {}
var indicators: Dictionary = {}
var gate_open = false
var restored_gate = false
var local_authority = true
var clock_seconds = 0.0
var spawn_position = Vector3(-18, 2.5, 32)
var boss_position = Vector3(14, 6, -32)
var _materials: Dictionary = {}
var _effect_tweens: Array[Tween] = []
var _effects_paused = false
var art_bridge: Node3D
var art_temple: Node3D
var gate_fraction = 0.0
var platform_height = 2.0
var rotor_angle = -PI / 3.0
var light_hit = Vector3.ZERO
var light_enabled = false
var gate_obstructed = false
var _base_object_materials: Dictionary = {}
var campaign_growth_blockers: Dictionary = {}
var _labels: Array[Label3D] = []
var terrain_modules: Array[Node3D] = []
var art_relay: Node3D
var art_thermal: Node3D
var art_roots: Node3D
var boss_warnings: Dictionary = {}
var art_whale: Node3D
var whale_defeated = false
var ecology_weather = "clear"
var art_traversal: Node3D
var crown_arena: Node3D
var crown_defeated = false
var shore_layout: RefCounted
var growth_crossing: RefCounted
var shore_verification: Dictionary = {}
var build_errors: Array[String] = []
var underdeck: Node3D
var underdeck_columns: Array[Node3D] = []
var _committed_flags: Dictionary = {}
var clinic: Node3D
var _water_tanks_owner: Node3D
var _water_tanks: Dictionary = {}
var distribution: Node3D
var trial: Node3D
var shared_access: Node3D
var waterfront: RefCounted
var waterfront_install: Dictionary = {}
var revetment_art: Dictionary = {}
var east_revetment_art: Dictionary = {}
var east_maintenance_art: Dictionary = {}
var revetment_closure_art: Dictionary = {}
var inspection_pit: Dictionary = {}
var inspection_pit_art: Dictionary = {}
var yard_connector_art: Dictionary = {}
# Asset comparison fixtures may isolate an earlier build stage explicitly.
# Normal solo and network worlds always include both production additions.
var include_revetment_closure := true
var include_inspection_pit := true
var include_yard_connector := true

func build(id: String, committed_flags: Dictionary = {}, authority: bool = true, facilities: Dictionary = {}) -> Dictionary:
	region_id = id
	_committed_flags = committed_flags.duplicate(true)
	local_authority = authority
	name = "Mechanics_" + id
	if id in ["F2", "I3", "F3", "I4", "F4"]:
		return _build_campaign_region()
	if id == "I2":
		clinic = facilities.get("clinic")
		if not is_instance_valid(clinic):
			clinic = ClinicWaterworks.new()
			var loaded: Dictionary = clinic.load_layout({}, authority)
			if not loaded.ok:
				build_errors.append("clinic_layout:" + str(loaded.code))
				clinic.free()
				clinic = null
				return {}
		# Static geography belongs to the region, not the waterworks save envelope.
		# Keep the same Ground body and all four facility identities on restoration.
		waterfront = WaterfrontTerrain.new()
		var terrain_ready: Dictionary = waterfront.configure(clinic.ground_art.surface_regions)
		if not terrain_ready.ok:
			build_errors.append("i2_terrain:" + str(terrain_ready.code))
			return {}
		var shore_points := PackedVector4Array()
		for point: Vector3 in WaterfrontTerrain.PROFILE:
			shore_points.append(Vector4(point.x,point.y,point.z,0))
		if not GroundSurface.configure_shore("I2", {"count":shore_points.size(),"water_points":shore_points}):
			build_errors.append("i2_water_material_profile")
			return {}
		waterfront_install = waterfront.install(clinic.fixed_bodies.Ground, clinic.ground_art.surface_patches, GroundSurface.water_material("I2"))
		if not waterfront_install.ok:
			build_errors.append("i2_terrain:" + str(waterfront_install.code))
			return {}
		revetment_art = RevetmentArt.install(waterfront,waterfront_install)
		if not revetment_art.ok:
			build_errors.append("i2_revetment:"+str(revetment_art.code))
			return {}
		east_revetment_art = EastRevetmentArt.install(waterfront,waterfront_install)
		if not east_revetment_art.ok:
			build_errors.append("i2_east_revetment:"+str(east_revetment_art.code))
			return {}
		east_maintenance_art = EastMaintenanceArt.install(waterfront_install)
		if not east_maintenance_art.ok:
			build_errors.append("i2_east_maintenance:"+str(east_maintenance_art.code))
			return {}
		if include_revetment_closure:
			revetment_closure_art = RevetmentClosureArt.install(waterfront,waterfront_install)
			if not revetment_closure_art.ok:
				build_errors.append("i2_revetment_closure:"+str(revetment_closure_art.code))
				return {}
		if include_inspection_pit:
			inspection_pit = InspectionPit.new().install(waterfront_install)
			if not inspection_pit.ok:
				build_errors.append("i2_inspection_pit:"+str(inspection_pit.code))
				return {}
			inspection_pit_art = InspectionPitArt.install(inspection_pit)
			if not inspection_pit_art.ok:
				build_errors.append("i2_inspection_pit_art:"+str(inspection_pit_art.code))
				return {}
		_build_environment()
		# A supported high side bay keeps the empty buffer out of both 3m routes.
		# Its thin deck is above the original low carrier/beneficiary passage.
		var buffer_bay: Node3D = _box(self,CanalBufferLayout.SUPPORT_CENTER,CanalBufferLayout.SUPPORT_SIZE,Color("748888"),true)
		buffer_bay.name = "CanalBufferSideBay"
		buffer_bay.force_update_transform()
		clinic.name = "ClinicWaterworks"
		add_child(clinic)
		distribution = facilities.get("distribution")
		if not is_instance_valid(distribution):
			distribution = DistributionCabinet.new()
			var loaded: Dictionary = distribution.load_layout({}, authority)
			if not loaded.ok:
				build_errors.append("distribution_layout:" + str(loaded.code))
				distribution.free()
				distribution = null
				return {}
		distribution.name = "DistributionCabinet"
		distribution.set_meta("stage", "integrated_replaceable_graybox")
		add_child(distribution)
		trial=facilities.get("trial")
		if not is_instance_valid(trial):
			trial=TrialAssembly.new()
			var loaded: Dictionary=trial.configure({},authority)
			if not loaded.ok:
				build_errors.append("trial_layout:"+str(loaded.code))
				trial.free()
				trial=null
				return {}
		trial.name="TrialFlowAssembly"
		add_child(trial)
		var bound: Dictionary=trial.bind()
		if not bound.ok:
			build_errors.append("trial_connection:"+str(bound.code))
			return {}
		var signs=TrialPresentation.new()
		trial.station.add_child(signs)
		var presented: Dictionary=signs.setup(trial.station)
		if not presented.ok:
			build_errors.append("trial_presentation:"+str(presented.code))
			return {}
		shared_access = facilities.get("shared_access")
		if not is_instance_valid(shared_access):
			shared_access = SharedAccessBridge.new()
			var loaded: Dictionary = shared_access.load_layout({}, authority)
			if not loaded.ok:
				build_errors.append("shared_access_layout:" + str(loaded.code))
				shared_access.free()
				shared_access = null
				return {}
		shared_access.name = "SharedAccessBridge"
		shared_access.deck_art = SharedBridgeArt.install(shared_access)
		if not shared_access.deck_art.ok:
			build_errors.append("shared_bridge_art:" + str(shared_access.deck_art.code))
			return {}
		shared_access.landing_art = SharedLandingArt.install(shared_access)
		if not shared_access.landing_art.ok:
			build_errors.append("shared_landing_art:" + str(shared_access.landing_art.code))
			return {}
		shared_access.set_meta("stage", "imported_moving_deck_and_fixed_landings")
		add_child(shared_access)
		# The final visual cut uses actual live pump/bridge footprints. Install
		# after these structures enter the tree; keep all physical shapes intact.
		if include_yard_connector and include_inspection_pit and include_revetment_closure:
			yard_connector_art = YardConnectorArt.install(self)
			if not yard_connector_art.ok:
				build_errors.append("i2_yard_connector:"+str(yard_connector_art.code))
				return {}
			central_service_apron_art = CentralApronArt.install(self)
			if not central_service_apron_art.ok:
				build_errors.append("i2_central_apron:"+str(central_service_apron_art.code))
				return {}
		for facility in [clinic, distribution, trial, shared_access]:
			for item in facility.target_definitions():
				definitions[item.id] = item.duplicate(true)
				objects[item.id] = facility.target_bodies[item.id]
				initial_transforms[item.id] = objects[item.id].transform
				if facility not in [trial, shared_access]: _label(objects[item.id], str(item.name), Vector3.UP * 0.7, Color("c6e7de"), 22)
		var pump_rig: Dictionary = PumpMechanisms.install(self)
		if not pump_rig.get("ok",false):
			build_errors.append("pump_guardian:"+str(pump_rig.get("code","install")))
			return {}
		if not _install_campaign_arena(Vector3(0,8,-25)): return {}
		return definitions.duplicate(true)
	if id == "F1":
		shore_layout = ShoreLayout.new()
		var loaded: Dictionary = shore_layout.load_layout()
		shore_verification = loaded.duplicate(true)
		if not loaded.get("ok", false):
			build_errors.append("shore_layout:" + str(loaded.get("code", "unknown")))
			return {}
		if not GroundSurface.configure_shore(id, shore_layout.shader_data()):
			build_errors.append("shore_material_profile")
			return {}
		growth_crossing = GrowthCrossing.new()
		var crossing_loaded: Dictionary = growth_crossing.load_layout()
		if not crossing_loaded.ok:
			build_errors.append(str(crossing_loaded.code))
			return {}
	_build_environment()
	if id == "F1":
		_build_fantasy_volumes()
	else:
		_build_industrial_volumes()
	_build_interactions()
	_build_boss()
	_validate_required_boss()
	return definitions.duplicate(true)

func _validate_required_boss() -> void:
	if region_id == "I1":
		if not whale_ready():
			build_errors.append("whale_import:" + str(art_whale.import_errors if is_instance_valid(art_whale) else ["missing_wrapper"]))
	elif region_id == "F1":
		if not is_instance_valid(gate) or not gate.get("imported"):
			build_errors.append("rising_seal_import:" + str(gate.get("import_errors") if is_instance_valid(gate) else ["missing_wrapper"]))
		if not is_instance_valid(crown_arena):
			build_errors.append("crown_import:missing_arena")
		elif not crown_arena.imported:
			var details: Array = crown_arena.missing.duplicate()
			if is_instance_valid(crown_arena.model): details.append_array(crown_arena.model.import_errors)
			else: details.append("missing_wrapper")
			build_errors.append("crown_import:" + str(details))

func _build_campaign_region() -> Dictionary:
	_build_environment()
	campaign_layout = CampaignLayout.build_geometry(self, region_id)
	if not campaign_layout.ok:
		build_errors.append(str(campaign_layout.code))
		return {}
	for spec: Dictionary in CampaignCatalog.physical_entities(region_id):
		var p: Array = spec.position
		var dimensions: Array = spec.get("size",[1.5,1.5,1.5])
		if str(spec.id) in ["F3:nutrient_bridge","F4:living_support"]: dimensions = [3,.4,3]
		var properties := {"temperature":float(spec.get("temperature",20.0)),"charge":float(spec.get("charge",0.0)),"charge_capacity":100.0,
			"growth":float(spec.get("growth",0.0)),"light_level":float(spec.get("light_level",0.0)),"angle":deg_to_rad(float(spec.get("angle_degrees",spec.get("initial_yaw_degrees",0.0)))),"powered":false}
		for key in ["powered","charge_capacity","rated_w","current_limit_w"]:
			if spec.has(key): properties[key] = spec[key]
		_entity(str(spec.id).trim_prefix(region_id+":"),_campaign_target_name(str(spec.id)),Vector3(p[0],p[1],p[2]),
			Vector3(dimensions[0],dimensions[1],dimensions[2]),spec.tags,properties,
			Color("79a48a") if region_id.begins_with("F") else Color("82a5b0"))
		objects[spec.id].rotation.y = float(properties.angle)
	var p: Array = campaign_layout.definition.boss_arena.centre
	if not _install_campaign_arena(Vector3(p[0],p[1],p[2])): return {}
	# The reveal beam must hit the actual collidable core before the receiver.
	if region_id == "F2" and is_instance_valid(campaign_arena):
		_entity("reveal_source","辨真光源",boss_position+Vector3(-8,1,0),Vector3(.5,.5,.5),["photosensitive","sustained_light_source"],{"light_level":0.0},Color("b7b376"))
		_entity("shadow_receiver","背光传感面",boss_position+Vector3(8,1,0),Vector3(.5,2,2),["photosensitive"],{},Color("7e9d9a"))
		campaign_body_aliases["F2:true_body"] = campaign_arena.targets[campaign_arena.target_id("core")]
	elif region_id == "I3":
		_entity("boss_radiator","履带散热器",boss_position+Vector3(-5,0,3),Vector3(1.2,2.5,1.8),["thermal"],{"temperature":80.0},Color("a36c48"))
		var chassis := RigidBody3D.new()
		chassis.name = "PhysicalCrawlerChassis"
		chassis.freeze = true
		chassis.collision_layer = 8
		chassis.collision_mask = 1 | 2 | 8
		add_child(chassis)
		chassis.position = boss_position-Vector3(0,2.5,0)
		_geometry(chassis,Vector3(8,1.5,4),Color("46515a"),true)
		objects["I3:boss_chassis"] = chassis
		definitions["I3:boss_chassis"] = {"id":"I3:boss_chassis","name":"履带车架","position":chassis.position,"tags":[],"revision":0,"owner":"world","pinned":true}
		initial_transforms["I3:boss_chassis"] = chassis.transform
		var installed_cargo: Dictionary = ThermalCargo.install(self)
		if not installed_cargo.get("ok",false): build_errors.append("thermal_cargo:"+str(installed_cargo.get("code","failed")))
	if region_id == "I4":
		var installed_storm: Dictionary = I4Storm.install(self)
		if not installed_storm.get("ok",false): build_errors.append("i4_storm:"+str(installed_storm.get("code","failed")))
	var dressing: Dictionary = CampaignDressing.install(self)
	if not dressing.get("ok",false): build_errors.append("campaign_dressing:"+str(dressing.get("code","failed")))
	campaign_mechanism_view = CampaignMechanismView.new()
	if not campaign_mechanism_view.setup(self): build_errors.append("mechanism_view_setup")
	for target in ["F2:clock_mirror","F2:clock_mirror_bypass","I3:cooling_valve","F3:signal_hold","F4:test_hold","F4:living_emitter"]:
		if objects.has(target): CampaignMechanismView.attach_direction(objects[target])
	return definitions.duplicate(true)

func _install_campaign_arena(at: Vector3) -> bool:
	var document: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/v3/campaign/bosses.json"))
	for spec: Dictionary in document.get("bosses",[]):
		if spec.region_id != region_id: continue
		boss_position = at
		campaign_arena = CampaignArena.new()
		add_child(campaign_arena)
		var made: Dictionary = campaign_arena.configure(spec,at)
		if not made.ok:
			build_errors.append(str(made.code))
			return false
		for id in campaign_arena.targets:
			objects[id] = campaign_arena.targets[id]
			definitions[id] = campaign_arena.definitions[id]
			initial_transforms[id] = objects[id].transform
			boss_parts[id] = objects[id]
		return true
	build_errors.append("campaign_boss_definition_missing:"+region_id)
	return false

static func _campaign_target_name(id: String) -> String:
	return {"F2:clock_source":"校时光源","F2:clock_mirror":"转向镜面","F2:clock_mirror_bypass":"旁路转向镜","F2:clock_receiver":"接收石",
		"I3:hot_cassette":"热匣","I3:cooling_sink":"冷却热汇","I3:cooling_valve":"热交换阀 · G转动","I3:loaded_cassette":"吊载匣","I3:high_dock":"高台货架",
		"F3:signal_hold":"信号保持端","F3:signal_breaker":"重复信号开关","F3:nutrient_bridge":"养分枝桥","F3:nutrient_receiver":"养分接收端",
		"I4:witness_source":"原件发射端","I4:witness_receiver":"原件接收端","I4:defence_platform":"检修平台","I4:defence_breaker":"防御馈线开关",
		"F4:limited_bus":"限流总线","F4:living_emitter":"活脉光源","F4:living_support":"活脉支撑","F4:test_hold":"双负载锁定端","F4:industrial_gauge":"工业负载表","F4:living_gauge":"活脉负载表"}.get(id,id)

func _build_environment() -> void:
	var environment = WorldEnvironment.new()
	var settings = Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("182820") if region_id == "F1" else Color("182632")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("c7dbdf")
	settings.ambient_light_energy = 0.34
	if region_id == "I2":
		# A color ambient source supplies diffuse light only. The imported steel
		# needs an actual reflection source even with this oblique camera's
		# solid-color backdrop. Static low-resolution overcast radiance; no GI
		# or real-time reflection probe is needed for this bounded clinic site.
		var sky_material := ProceduralSkyMaterial.new()
		sky_material.sky_top_color = Color(.6,.6,.6)
		sky_material.sky_horizon_color = Color(.6,.6,.6)
		sky_material.ground_bottom_color = Color(.6,.6,.6)
		sky_material.ground_horizon_color = Color(.6,.6,.6)
		sky_material.sun_angle_max = 0.0
		var sky := Sky.new()
		sky.radiance_size = Sky.RADIANCE_SIZE_128
		sky.process_mode = Sky.PROCESS_MODE_QUALITY
		sky.sky_material = sky_material
		settings.sky = sky
		settings.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	settings.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.environment = settings
	add_child(environment)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -25, 0)
	sun.light_color = Color("ffe8c7")
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90
	add_child(sun)
	if region_id not in ["I1", "F1"]:
		# This bounded clinic site has its own terrain. Do not inherit port banks,
		# beacon, boss or ocean collision from another region.
		return
	if region_id == "F1":
		_build_shore_geometry()
	else:
		var water = _box(self, Vector3(0, -2.7, 0), Vector3(125, 1, 125), Color("315c6b"), true)
		water.get_node("Shape").material_override = GroundSurface.water_material(region_id)
		var left_shore = _box(self, Vector3(-30, -0.6, 0), Vector3(44, 1.2, 100), Color("657478"), true)
		left_shore.get_node("Shape").material_override = GroundSurface.material_for(region_id, -1)
		var right_shore = _box(self, Vector3(30, 0.9, 0), Vector3(44, 3, 100), Color("788887"), true)
		right_shore.get_node("Shape").material_override = GroundSurface.material_for(region_id, 1)
	for x in [-54.0, 54.0]:
		_box(self, Vector3(x, 2, 0), Vector3(2, 8, 104), Color("394d59"), true)
	for z in [-51.0, 51.0]:
		_box(self, Vector3(0, 1, z), Vector3(108, 5, 2), Color("394d59"), true)
	_label(self, "潮湾 · 供能栈桥" if region_id == "I1" else "巨木 · 共脉环门", Vector3(-18, 6, 38), Color("d9e6e2"), 32)

func _build_shore_geometry() -> void:
	# These replace the old F1 shore boxes; no hidden solid rectangle remains.
	# Authored Blender shoulders will replace these explicitly marked base pieces.
	for part in shore_layout.part_ids():
		var holder = Node3D.new()
		holder.name = "Shore_" + str(part).replace(":", "_")
		holder.set_meta("terrain_stage", "replaceable_graybox")
		add_child(holder)
		var mesh = MeshInstance3D.new()
		mesh.name = "Surface"
		mesh.mesh = shore_layout.make_mesh(part)
		if part == "water": mesh.material_override = GroundSurface.water_material(region_id)
		elif part == "west": mesh.material_override = GroundSurface.material_for(region_id, -1)
		elif part == "east": mesh.material_override = GroundSurface.material_for(region_id, 1)
		else: mesh.material_override = _material(Color("48534d"))
		holder.add_child(mesh)
		var shape: Shape3D = shore_layout.make_shape(part)
		if shape == null: continue
		var body = StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.set_meta("entity_id", "terrain:" + str(part))
		holder.add_child(body)
		var collision = CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)

func _build_industrial_volumes() -> void:
	# Two tiers have foundations under every upper module; no floating box decks.
	for at in [Vector3(-40, 0, 3), Vector3(-40, 0, -5), Vector3(-40, 4, -5), Vector3(-28, 0, -5), Vector3(-28, 4, -5), Vector3(-14, 0, -18)]:
		var terrace = CoastalTerrace.instantiate()
		terrace.position = at
		add_child(terrace)
		terrain_modules.append(terrace)
	# A physical maintenance shelter between the retry deck and the whale's head.
	var shelter = RelayCabinet.instantiate()
	shelter.name = "NorthMaintenanceShelter"
	shelter.create_collision = true
	shelter.scale = Vector3.ONE * 1.5
	shelter.position = Vector3(-9.2, 4, -19.4)
	add_child(shelter)
	art_traversal = MaintenanceOverpass.instantiate()
	art_traversal.position = Vector3(0, 7.5, -8)
	add_child(art_traversal)
	# The old lower gate and its solid placeholder are replaced by the I-B module.
	_box(self, Vector3(31, 6, -10), Vector3(18, 7.2, 15), Color("adbbb9"), true)
	underdeck = Underdeck.new()
	underdeck.name = "InspectionPassage"
	var passage_loaded: Dictionary = underdeck.load_layout(local_authority, _committed_flags)
	if not passage_loaded.ok:
		build_errors.append("underdeck:" + str(passage_loaded.code))
		underdeck.free()
		underdeck = null
	else:
		add_child(underdeck)
		for definition in underdeck.target_definitions():
			var target_id: String = definition.id
			var target = underdeck.gates.front if target_id == Underdeck.FRONT_ID else underdeck.get_node("InnerLatch")
			objects[target_id] = target
			initial_transforms[target_id] = target.transform
			definitions[target_id] = definition
	for x in [-42, -35, -28]:
		var column := _box(self, Vector3(x, 8.8, -26), Vector3(3, 5.6, 3), Color("6c7f89"), true)
		# Roof and its supports form one visual cutaway. Reparenting preserves
		# world-space solids; the protected corridor floor remains fully opaque.
		if is_instance_valid(underdeck): column.reparent(underdeck.shell, true)
		if is_instance_valid(underdeck) and underdeck.shell_art.get("ok", false):
			# Imported roof supports share the shell cutaway; the original solid
			# columns remain the collision source, with no second gray visual.
			column.get_node("Shape").visible = false
			column.get_node("Shape").set_meta("terrain_visibility_keep", true)
		underdeck_columns.append(column)
	for z in [5, 12]:
		_box(self, Vector3(31, 3.9, z), Vector3(9, 3, 5), Color("ac8b65"), true)
	_label(self, "桥上 / 桥下均可飞行", Vector3(-3, 10.5, -8), Color("d4e5e6"), 26)

func _build_fantasy_volumes() -> void:
	for at in [Vector3(-35, 0, -12), Vector3(35, 2.4, -13), Vector3(-15.5, 0, 26.35)]:
		var terrace = RootstoneTerrace.instantiate()
		terrace.position = at
		if terrain_modules.size() == 2: terrace.scale = Vector3.ONE * 0.75
		add_child(terrace)
		terrain_modules.append(terrace)
	_cylinder(self, Vector3(30, 7, 22), 4.5, 14, Color("6e7868"), true)
	art_traversal = RootArch.instantiate()
	art_traversal.position = Vector3(0, 0, -6)
	add_child(art_traversal)
	# The permanent cross-river board is gone. Only the independent growth
	# state machine can add the central bearing surface; flying can still bypass it.
	for id in growth_crossing.part_ids():
		var body = StaticBody3D.new()
		body.name = "GrowthApproach_" + id
		body.set_meta("terrain_stage", "replaceable_graybox")
		body.set_meta("entity_id", "terrain:growth_approach:" + id)
		body.collision_layer = 1
		body.collision_mask = 0
		add_child(body)
		var mesh = MeshInstance3D.new()
		mesh.name = "Surface"
		mesh.mesh = growth_crossing.make_mesh(id)
		mesh.material_override = _material(Color("768479"))
		body.add_child(mesh)
		var collision = CollisionShape3D.new()
		collision.shape = growth_crossing.make_shape(id)
		body.add_child(collision)
	for i in range(5):
		_box(self, Vector3(21 + i * 3, 3 + i, 8), Vector3(4, 1, 9), Color("a0a58e"), true)
	_label(self, "根桥上 / 洞室下两条路线", Vector3(0, 12, -6), Color("dbe6c6"), 26)

func _build_interactions() -> void:
	_entity("relay", "供能继电器", Vector3(-14, 1, 17), Vector3(2, 2, 2), ["conductive", "electrical", "mechanical", "hackable"], {"charge":0.0, "powered":false, "temperature":20.0}, Color("76c5dd"))
	_entity("thermal", "热交换旁路", Vector3(-29, 1, 8), Vector3(3, 2, 2), ["thermal", "thermal_engine", "mechanical"], {"temperature":20.0, "powered":false}, Color("dba574"))
	if region_id == "I1":
		_entity("mirror", "光路反射器", Vector3(-12, 2, -2), Vector3(2, 3, 0.6), ["photosensitive", "solar"], {"light_level":0.0, "angle":0.0}, Color("c6d7e5"))
	else:
		art_temple = TempleGate.instantiate()
		art_temple.position = Vector3(-24, 0, 25)
		add_child(art_temple)
		var anchor = Marker3D.new()
		anchor.name = "RingTarget"
		add_child(anchor)
		anchor.position = Vector3(-24, 5.2, 25)
		objects["F1:mirror"] = anchor
		initial_transforms["F1:mirror"] = anchor.transform
		definitions["F1:mirror"] = {"id":"F1:mirror", "name":"共脉折光环", "position":anchor.position, "tags":["photosensitive", "rotatable", "solar", "sustained_light_source"], "angle":-PI/3.0, "light_level":0.0, "revision":0, "owner":"neutral"}
		_label(self, "折光环：每次导光转动一格\n让光照到活性根簇，再催化生长", Vector3(-24, 11, 25), Color("d5d3a5"), 23)
	var growth_at = Vector3(11, 3.3, 14) if region_id == "I1" else Vector3(-16, 5.2, 26.35)
	_entity("growth", "活性根簇", growth_at, Vector3(2.5, 2, 2.5), ["photosensitive", "plant", "growable", "organic"], {"growth":0.0, "temperature":20.0, "environment_light":0.0}, Color("8ebf82"))
	_entity("crate", "可移动导体", Vector3(-17, 1.2, 5), Vector3(2, 2, 2), ["movable", "conductive", "fieldable"], {"charge":0.0, "mass":3.0, "pinned":false}, Color("c0ab85"), true)
	_entity("switch", "持续操作台", Vector3(15, 3.4, 23), Vector3(2, 2, 2), ["echo_operable", "mechanical", "hackable"], {"operated":false, "powered":false}, Color("b4a1d5"))
	_entity("beacon", "跨界通航信标", Vector3(29, 3.4, 32), Vector3(2, 2, 2), ["mechanical", "hackable", "conductive"], {"powered":false, "charge":0.0}, Color("dccb8d"))
	if region_id == "I1":
		art_bridge = ServiceBridge.instantiate()
		art_bridge.position = Vector3(-24, 0, 25)
		add_child(art_bridge)
		gate = art_bridge.shutter_body
		_label(self, "供能栈桥：桥下可通行\n充能 / 热旁路 / 接管 → 卷帘打开", Vector3(-24, 10.3, 25), Color("dce8e0"), 23)
	else:
		gate = RisingSeal.instantiate()
		gate.position = Vector3(6, 5.4, 26)
		add_child(gate)
	platform = AnimatableBody3D.new()
	platform.name = "MovingPlatform"
	platform.sync_to_physics = false
	platform.collision_layer = 1
	add_child(platform)
	platform.position = Vector3(0, 2.0, 12)
	_geometry(platform, Vector3(6, 0.6, 6), Color("c0bb95"), true)
	growth_bridge = StaticBody3D.new()
	growth_bridge.collision_layer = 1
	add_child(growth_bridge)
	growth_bridge.position = Vector3(0, 5, 5) if region_id == "I1" else Vector3(0, 5, 25)
	_geometry(growth_bridge, Vector3(22, 0.5, 3), Color("8fa782"), true)
	growth_bridge.visible = false
	growth_bridge.collision_layer = 0
	if region_id == "F1":
		_label(self, "通航闸门：供电 / 热旁路 / 接管", Vector3(4, 10.5, 28), Color("dce8e0"), 24)
	_mount_authored_props()

func _mount_authored_props() -> void:
	if region_id == "I1":
		var body = objects["I1:relay"]
		body.get_node("Shape").hide()
		for child in body.get_children():
			if child is CollisionShape3D:
				var box = BoxShape3D.new()
				box.size = Vector3(1.76, 2.5, 1.2)
				child.shape = box
				child.position = Vector3(0, 0.43, -0.04)
		var base = CollisionShape3D.new()
		var base_shape = BoxShape3D.new()
		base_shape.size = Vector3(2, 0.18, 1.6)
		base.shape = base_shape
		base.position.y = -0.91
		body.add_child(base)
		art_relay = RelayCabinet.instantiate()
		art_relay.position.y = -1
		body.add_child(art_relay)
		var thermal_body = objects["I1:thermal"]
		art_thermal = ThermalBypass.instantiate()
		art_thermal.position.y = -1
		thermal_body.add_child(art_thermal)
		if art_thermal.imported:
			thermal_body.get_node("Shape").hide()
		else:
			build_errors.append("thermal_bypass_import:" + str(art_thermal.import_errors))
	else:
		var thermal_body = objects["F1:thermal"]
		art_thermal = ThermalStoneArt.new()
		art_thermal.position.y = -1
		thermal_body.add_child(art_thermal)
		if art_thermal.imported:
			thermal_body.get_node("Shape").hide()
		else:
			build_errors.append("thermal_stone_import:" + str(art_thermal.import_errors))
		var body = objects["F1:growth"]
		body.get_node("Shape").hide()
		art_roots = PhotosensitiveRoots.instantiate()
		art_roots.position.y = -1
		body.add_child(art_roots)

func _entity(key: String, title: String, at: Vector3, size: Vector3, tags: Array, properties: Dictionary, tint: Color, dynamic = false) -> void:
	var id = region_id + ":" + key
	var body: PhysicsBody3D
	if dynamic:
		var rigid = RigidBody3D.new()
		rigid.mass = 3.0
		rigid.continuous_cd = true
		rigid.linear_damp = 1.2
		body = rigid
	else:
		body = StaticBody3D.new()
	body.name = key
	body.collision_layer = 8
	body.collision_mask = 1 | 2 | 8
	body.set_meta("entity_id", id)
	add_child(body)
	body.position = at
	_geometry(body, size, tint, true)
	_base_object_materials[id] = body.get_node("Shape").material_override
	_label(body, title, Vector3(0, size.y * 0.5 + 0.7, 0), tint.lightened(0.3), 23)
	objects[id] = body
	initial_transforms[id] = body.transform
	var state = {"id":id, "name":title, "position":at, "tags":tags, "revision":0, "owner":"neutral"}
	state.merge(properties, true)
	definitions[id] = state

func _build_boss() -> void:
	if region_id == "I1":
		art_whale = SiphonWhale.instantiate()
		art_whale.position = boss_position
		add_child(art_whale)
		boss_root = art_whale
		if not whale_ready(): return
		for part in ["core", "port", "starboard"]:
			var body = StaticBody3D.new()
			body.name = str(part) + "Weakpoint"
			body.collision_layer = 8
			body.set_meta("entity_id", "boss:" + part)
			boss_root.add_child(body)
			body.global_position = art_whale.weakpoint_position(part)
			var collision = CollisionShape3D.new()
			var sphere = SphereShape3D.new()
			# Final GLB measured inner-cover clearance: core .205m, sides .499m.
			# Keep targets inside the armor instead of letting a hurtbox protrude.
			sphere.radius = 0.15 if part == "core" else 0.38
			collision.shape = sphere
			body.add_child(collision)
			boss_parts[part] = body
		return
	crown_arena = CrownArena.new()
	crown_arena.name = "CrownArena"
	add_child(crown_arena)
	crown_arena.build()
	boss_root = crown_arena

func whale_ready() -> bool:
	return is_instance_valid(art_whale) and art_whale.imported

func whale_record_position() -> Vector3:
	return art_whale.raw_record_position() if whale_ready() else Vector3.INF

func boss_attack_origin() -> Vector3:
	return art_whale.attack_origin() if whale_ready() else boss_position + Vector3(0, 2, 0)

func boss_retry_position(slot: int) -> Vector3:
	if is_instance_valid(crown_arena): return crown_arena.retry_position(slot)
	var origin: Vector3 = art_whale.retry_entry() if whale_ready() else Vector3(-14, 5.2, -18)
	return origin + Vector3(-2.4 if slot == 0 else 2.4, 0, 0)

func boss_collision_bodies() -> Array:
	var result: Array = boss_parts.values()
	if whale_ready(): result.append_array(art_whale.collision_bodies())
	if is_instance_valid(crown_arena) and crown_arena.imported: result.append_array(crown_arena.model.collision_bodies())
	return result

func set_boss_state(state: Dictionary, defeated = false) -> void:
	if region_id == "F1":
		crown_defeated = defeated
		if is_instance_valid(crown_arena): crown_arena.apply_view(state, defeated)
		return
	whale_defeated = defeated
	if whale_ready(): art_whale.set_state(state, defeated)

func synchronize(entities: Dictionary, delta: float, players: Dictionary = {}) -> void:
	# Called in the physics tick. Guests reconstruct received poses; no local integration.
	if local_authority: clock_seconds += delta
	var content_view = get_node_or_null("WorldContentNext")
	if content_view != null: content_view.apply_view(entities)
	# Additive salvage bodies use the same physical pin on every region; the
	# established I2/campaign branches below retain their existing early return.
	for id in objects:
		var content_body: Variant = objects[id]
		if content_body is RigidBody3D and content_body.get_meta("side_story88", false) and entities.has(id):
			content_body.freeze = not local_authority or bool(entities[id].get("pinned", false))
			if not local_authority and entities[id].get("position") is Vector3: content_body.position = entities[id].position
	GroundSurface.set_wind_phase(clock_seconds, 2.0 if ecology_weather == "storm" else (1.4 if ecology_weather == "rain" else 1.0), region_id)
	if region_id == "I4": I4Storm.present(self,clock_seconds)
	if region_id in ["F2", "I3", "F3", "I4", "F4"]:
		for id in objects:
			if not entities.has(id) or str(id).begins_with("campaign:") or id in ["F2:true_body","I3:boss_chassis"]: continue
			var state: Dictionary = entities[id]
			if not local_authority and objects[id].get_meta("thermal_remote_presentation",false): continue
			if not local_authority or delta == 0.0: objects[id].position = state.position
			if state.has("angle") and not (local_authority and objects[id] is RigidBody3D): objects[id].rotation.y = float(state.angle)
			if "growable" in state.get("tags",[]): _campaign_growth_pose(str(id),state)
		return
	if region_id == "I2":
		# ClinicSession owns the single authoritative update in both visible and
		# background worlds. Guests only display its reliable composite state.
		for id in objects:
			if str(id).begins_with("I2:guardian_") and entities.has(id):
				if not local_authority or delta == 0.0: objects[id].position = entities[id].position
				if entities[id].has("angle"): objects[id].rotation.y = float(entities[id].angle)
		for facility in [clinic, distribution, trial, shared_access]:
			if not is_instance_valid(facility): continue
			for id in facility.target_bodies:
				if entities.has(id): entities[id].position = facility.entity_position(id)
		return
	for id in objects:
		if not entities.has(id): continue
		var body = objects[id]
		var state: Dictionary = entities[id]
		if body is RigidBody3D:
			body.freeze = not local_authority or bool(state.get("pinned", false))
		var mesh = body.get_node_or_null("Shape")
		if mesh:
			mesh.material_override = _material(Color("8ce0b2")) if (bool(state.get("powered", false)) or float(state.get("charge", 0)) >= 30 or float(state.get("environment_light", 0)) > 0.25) else _base_object_materials[id]
	var relay: Dictionary = entities.get(region_id + ":relay", {})
	var thermal: Dictionary = entities.get(region_id + ":thermal", {})
	var beacon: Dictionary = entities.get(region_id + ":beacon", {})
	if local_authority:
		gate_open = restored_gate or bool(relay.get("powered", false)) or float(relay.get("charge", 0)) >= 40 or float(thermal.get("temperature", 20)) >= 55 or bool(beacon.get("controlled", false)) or bool(beacon.get("powered", false))
		var next_gate = move_toward(gate_fraction, 1.0 if gate_open else 0.0, delta * 0.7)
		gate_obstructed = next_gate < gate_fraction and not _gate_clear_to_close(next_gate)
		if not gate_obstructed: gate_fraction = next_gate
	var switch_state: Dictionary = entities.get(region_id + ":switch", {})
	var active = bool(switch_state.get("operated", false)) or bool(switch_state.get("powered", false)) or bool(switch_state.get("controlled", false))
	if local_authority: platform_height = move_toward(platform_height, 7.5 if active else 2.0, delta * 2)
	if is_instance_valid(art_temple):
		if local_authority:
			rotor_angle = rotate_toward(rotor_angle, float(entities.get("F1:mirror", {}).get("angle", -PI/3.0)), delta * 1.4)
		art_temple.set_angle(rotor_angle)
		if local_authority: _resolve_light_path(entities)
		art_temple.show_light(light_enabled, light_hit)
	_apply_mechanism_pose()
	var grown = float(entities.get(region_id + ":growth", {}).get("growth", 0)) >= 0.5
	growth_bridge.visible = grown
	growth_bridge.collision_layer = 1 if grown else 0
	if is_instance_valid(art_relay): art_relay.set_state(relay)
	if is_instance_valid(art_thermal): art_thermal.set_state(thermal)
	if is_instance_valid(art_roots): art_roots.set_state(entities.get(region_id + ":growth", {}))
	if is_instance_valid(underdeck):
		if local_authority and delta > 0.0:
			# The module bounds individual steps; preserve all elapsed simulation time.
			var remaining: float = delta
			while remaining > 0.0000001:
				var step: float = minf(remaining, Underdeck.MAX_DELTA)
				var result: Dictionary = underdeck.fixed_update(step, entities, players, true)
				if not result.ok:
					push_error("Underdeck update: " + str(result.code))
					break
				remaining -= step
		update_underdeck_targets(entities)

func _campaign_growth_pose(id: String, state: Dictionary) -> void:
	var body: PhysicsBody3D = objects[id]
	var collision: CollisionShape3D
	for child in body.get_children():
		if child is CollisionShape3D: collision = child; break
	if collision == null or not collision.shape is BoxShape3D: return
	var next := Vector3(maxf(.15,float(state.get("growth",0.0))*3.0),.4,3.0)
	if collision.shape.size.is_equal_approx(next): return
	if local_authority and next.x > collision.shape.size.x:
		var shape := BoxShape3D.new()
		shape.size = next
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform = body.global_transform*collision.transform
		query.collision_mask = 1 | 2 | 8
		query.exclude = [body.get_rid()]
		query.margin = 0.0
		var overlaps: Array[Dictionary] = get_world_3d().direct_space_state.intersect_shape(query,8)
		if not overlaps.is_empty():
			campaign_growth_blockers[id] = overlaps.map(func(hit: Dictionary): return {"path":str(hit.collider.get_path()),"entity_id":str(hit.collider.get_meta("entity_id","")),"requested_size":next,"current_size":collision.shape.size})
			return
	campaign_growth_blockers.erase(id)
	collision.shape.size = next
	var mesh: MeshInstance3D = body.get_node_or_null("Shape")
	if mesh != null and mesh.mesh is BoxMesh: mesh.mesh.size = next

func update_underdeck_targets(entities: Dictionary) -> void:
	if not is_instance_valid(underdeck): return
	for id in [Underdeck.FRONT_ID, Underdeck.LATCH_ID]:
		if entities.has(id): entities[id].position = underdeck.entity_position(id)

func apply_committed_flags(flags: Dictionary) -> void:
	if not is_instance_valid(underdeck) or not local_authority: return
	var result: Dictionary = underdeck.apply_committed(flags)
	if not result.ok: push_error("Underdeck committed flags: " + str(result.code))

func _gate_clear_to_close(fraction: float) -> bool:
	# Test the newly occupied volume before moving a solid shutter into a drone/crate.
	var query = PhysicsShapeQueryParameters3D.new()
	var shape = BoxShape3D.new()
	if is_instance_valid(art_bridge):
		var remaining = 2.8 * (1.0 - fraction)
		shape.size = Vector3(4.5, maxf(0.02, remaining) + 0.12, 0.35)
		query.transform = art_bridge.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 7.6 - remaining * 0.5, -1.75))
	else:
		shape.size = Vector3(1.15, 5.15, 7.15)
		query.transform = Transform3D(Basis.IDENTITY, to_global(Vector3(6, 5.4 + fraction * 6.0, 26)))
	query.shape = shape
	query.collision_mask = 2 | 8
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _resolve_light_path(entities: Dictionary) -> void:
	var growth_state: Dictionary = entities.get("F1:growth", {})
	light_enabled = float(entities.get("F1:mirror", {}).get("light_level", 0)) > 0.25
	var illumination = 0.0
	light_hit = art_temple.light_endpoint()
	if light_enabled:
		var query = PhysicsRayQueryParameters3D.create(art_temple.light_origin(), light_hit, 1 | 8)
		var hit = get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			light_hit = hit.position
			if str(hit.collider.get_meta("entity_id", "")) == "F1:growth": illumination = 1.0
	if float(growth_state.get("environment_light", 0)) != illumination:
		growth_state.environment_light = illumination
		growth_state.revision = int(growth_state.get("revision", 0)) + 1

func _apply_mechanism_pose() -> void:
	if region_id not in ["I1", "F1"]: return
	if is_instance_valid(art_bridge): art_bridge.set_lift(gate_fraction * 2.8)
	else:
		gate.position.y = lerpf(5.4, 11.4, gate_fraction)
		gate.set_gate_state(gate_fraction, gate_open)
	platform.position.y = platform_height

func mechanism_snapshot() -> Dictionary:
	var state := {"gate":gate_fraction, "open":gate_open, "platform":platform_height, "rotor":rotor_angle, "light":light_enabled, "hit":light_hit, "clock":clock_seconds}
	if is_instance_valid(underdeck): state.underdeck = underdeck.snapshot()
	return state

func apply_mechanism_snapshot(state: Dictionary) -> bool:
	if state.is_empty(): return false
	if is_instance_valid(underdeck):
		var applied: Dictionary = underdeck.apply_snapshot(state.get("underdeck"))
		if not applied.ok: return false
	gate_fraction = clampf(float(state.get("gate", 0.0)), 0, 1)
	gate_open = bool(state.get("open", false))
	platform_height = clampf(float(state.get("platform", 2.0)), 2.0, 7.5)
	rotor_angle = float(state.get("rotor", -PI/3.0))
	light_enabled = bool(state.get("light", false))
	light_hit = state.get("hit", Vector3.ZERO)
	clock_seconds = float(state.get("clock", 0.0))
	_apply_mechanism_pose()
	if is_instance_valid(art_temple):
		art_temple.set_angle(rotor_angle)
		art_temple.show_light(light_enabled, light_hit)
	return true

func initialize_mechanisms(entities: Dictionary) -> void:
	# Initialize before enabling pilot input after a save/region restore.
	if not local_authority: return
	rotor_angle = float(entities.get("F1:mirror", {}).get("angle", -PI/3.0))
	_flush_physics_transforms(self)
	synchronize(entities, 0.0)
	gate_fraction = 1.0 if gate_open else 0.0
	_apply_mechanism_pose()

func _flush_physics_transforms(node: Node) -> void:
	# Newly instanced collision transforms otherwise wait for the next physics tick.
	if node is Node3D: node.force_update_transform()
	for child in node.get_children(): _flush_physics_transforms(child)

func gate_passage() -> Array[Vector3]:
	if is_instance_valid(art_bridge): return [art_bridge.marker_position("PassStart"), art_bridge.marker_position("PassEnd")]
	return [Vector3(3, 5.4, 26), Vector3(9, 5.4, 26)]

func reset_physics() -> void:
	if region_id == "I2": return # Retry a pilot, never empty a restored clinic.
	for id in objects:
		# A Boss retry must not reset an unrelated persistent route or its live cycle.
		if id in [Underdeck.FRONT_ID, Underdeck.LATCH_ID]: continue
		objects[id].transform = initial_transforms[id]
		if objects[id] is RigidBody3D:
			objects[id].linear_velocity = Vector3.ZERO
			objects[id].angular_velocity = Vector3.ZERO
	gate_fraction = 0.0
	platform_height = 2.0
	_apply_mechanism_pose()

func sample_environment(at: Vector3) -> Dictionary:
	var strength = 3.6 if ecology_weather == "storm" else (2.0 if ecology_weather == "rain" else 1.4)
	var wind = Vector3(sin(clock_seconds * 0.13 + at.z * 0.02), 0, cos(clock_seconds * 0.09 + at.x * 0.02)) * strength
	if region_id == "I4":
		return I4Storm.sample(self,at,clock_seconds,{"wind_velocity":wind,"water":true,"water_height":-2.2,"nav_quality":1.0,"compass_quality":1.0})
	if region_id in ["F2", "I3", "F3", "I4", "F4"]:
		return {"wind_velocity":wind,"water":true,"water_height":-2.2,"nav_quality":1.0,"compass_quality":1.0}
	if is_instance_valid(clinic):
		# Layout is immutable after configure. Keep this private copy per actual
		# clinic instance; sample live water levels on every call below.
		if not is_instance_valid(_water_tanks_owner) or _water_tanks_owner!=clinic:
			_water_tanks=clinic.layout().tanks
			_water_tanks_owner=clinic
		var height := -1000.0
		if waterfront != null:
			var channel: Dictionary = waterfront.water_at(at)
			if channel.water: height = float(channel.water_height)
		for id in _water_tanks:
			var tank: Dictionary = _water_tanks[id]
			var surface: float = clinic.water_level(id)
			if surface <= float(tank.base_y): continue
			if absf(at.x - float(tank.center_xz[0])) < float(tank.inner_size[0]) * 0.5 and absf(at.z - float(tank.center_xz[1])) < float(tank.inner_size[2]) * 0.5 and at.y >= float(tank.base_y): height = maxf(height, surface)
		return {"wind_velocity":wind, "water":height > -999.0, "water_height":height, "nav_quality":1.0, "compass_quality":1.0}
	var above_water: bool = shore_layout.is_water_xz(at.x, at.z) if shore_layout != null else absf(at.x) < 8
	return {"wind_velocity":wind, "water":above_water, "water_height":-2.2, "nav_quality":1.0, "compass_quality":1.0}

func telegraph(position_m: Vector3, radius: float, duration: float) -> void:
	var ring = MeshInstance3D.new()
	var mesh = TorusMesh.new()
	mesh.inner_radius = maxf(0.1, radius - 0.18)
	mesh.outer_radius = radius
	mesh.rings = 28
	mesh.ring_segments = 6
	ring.mesh = mesh
	ring.material_override = _material(Color("ed815f"))
	add_child(ring)
	ring.position = position_m
	_expire(ring, duration)

func show_boss_warning(attack: String, marks: Dictionary, seconds: float) -> void:
	# Authoritative remaining time also restores a paused or late-joining guest.
	for id in boss_warnings.keys():
		if attack.is_empty() or seconds <= 0 or not marks.has(id) or boss_warnings[id].attack != attack or boss_warnings[id].target != marks[id]:
			remove_child(boss_warnings[id])
			boss_warnings[id].queue_free()
			boss_warnings.erase(id)
	if attack.is_empty() or seconds <= 0: return
	for id in marks:
		if not marks[id] is Vector3 or not marks[id].is_finite(): continue
		if not boss_warnings.has(id):
			var warning = BossWarning.new()
			warning.name = "BossWarning_" + str(id)
			add_child(warning)
			warning.configure(attack, marks[id])
			boss_warnings[id] = warning
		boss_warnings[id].set_remaining(seconds)

func beam(from: Vector3, to: Vector3, tint: Color, seconds = 0.16) -> void:
	var length = from.distance_to(to)
	if length < 0.01: return
	var visual = MeshInstance3D.new()
	var shape = CylinderMesh.new()
	shape.top_radius = 0.055
	shape.bottom_radius = 0.055
	shape.height = length
	shape.radial_segments = 6
	visual.mesh = shape
	visual.material_override = _material(tint)
	add_child(visual)
	visual.position = (from + to) * 0.5
	visual.quaternion = Quaternion(Vector3.UP, (to - from).normalized())
	_expire(visual, seconds)

func _expire(node: Node, seconds: float) -> void:
	var tween = node.create_tween()
	tween.tween_callback(node.queue_free).set_delay(seconds)
	_effect_tweens.append(tween)
	tween.finished.connect(_effect_finished.bind(tween), CONNECT_ONE_SHOT)
	if _effects_paused: tween.pause()
	_effect_tweens = _effect_tweens.filter(func(item): return item.is_valid())

func _effect_finished(tween: Tween) -> void:
	# A finished Tween can remain valid until the end of this frame.
	# Remove it synchronously so an arriving resume snapshot cannot replay it.
	_effect_tweens.erase(tween)

func set_effects_paused(paused: bool) -> void:
	_effects_paused = paused
	if is_instance_valid(art_thermal): art_thermal.set_animation_paused(paused)
	_effect_tweens = _effect_tweens.filter(func(item): return item.is_valid())
	for tween in _effect_tweens:
		if tween.is_valid():
			if paused: tween.pause()
			else: tween.play()

func _material(tint: Color) -> StandardMaterial3D:
	var key = tint.to_html()
	if not _materials.has(key):
		var material = StandardMaterial3D.new()
		material.albedo_color = tint
		material.roughness = 0.78
		_materials[key] = material
	return _materials[key]

func _geometry(parent: Node3D, size: Vector3, tint: Color, collision = false) -> MeshInstance3D:
	var mesh = MeshInstance3D.new()
	mesh.name = "Shape"
	var box = BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _material(tint)
	parent.add_child(mesh)
	if collision:
		var shape = CollisionShape3D.new()
		var bounds = BoxShape3D.new()
		bounds.size = size
		shape.shape = bounds
		parent.add_child(shape)
	return mesh

func _box(parent: Node3D, at: Vector3, size: Vector3, tint: Color, collision = false) -> Node3D:
	var root: Node3D = StaticBody3D.new() if collision else Node3D.new()
	parent.add_child(root)
	root.position = at
	_geometry(root, size, tint, collision)
	return root

func _cylinder(parent: Node3D, at: Vector3, radius: float, height: float, tint: Color, collision: bool) -> void:
	var root: Node3D = StaticBody3D.new() if collision else Node3D.new()
	parent.add_child(root)
	root.position = at
	var visual = MeshInstance3D.new()
	var mesh = CylinderMesh.new()
	mesh.top_radius = radius * 0.75
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	visual.mesh = mesh
	visual.material_override = _material(tint)
	root.add_child(visual)
	if collision:
		var shape = CollisionShape3D.new()
		var cylinder = CylinderShape3D.new()
		cylinder.radius = radius
		cylinder.height = height
		shape.shape = cylinder
		root.add_child(shape)

func _label(parent: Node3D, text: String, at: Vector3, tint: Color, size = 24) -> void:
	var label = Label3D.new()
	label.font = load("res://assets/fonts/NotoSansSC-Medium.ttf")
	label.text = text
	label.font_size = size
	label.pixel_size = 0.018
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = tint
	label.outline_size = 4
	parent.add_child(label)
	label.position = at
	label.visible = false
	_labels.append(label)

func set_focus(at: Vector3, target_id: String) -> void:
	# Directions belong in the HUD. Only the selected object gets an in-world label;
	# large permanent banners must not cover the approved asset silhouette.
	for label in _labels:
		var parent = label.get_parent()
		label.visible = not target_id.is_empty() and str(parent.get_meta("entity_id", "")) == target_id and label.global_position.distance_to(at) < 35.0
