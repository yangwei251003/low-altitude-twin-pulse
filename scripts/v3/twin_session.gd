class_name TwinSession
extends Node3D

const BuildContract = preload("res://scripts/v3/network/twin_build_contract.gd")
const Hangar = preload("res://scripts/v3/gameplay/twin_hangar.gd")
const WeaponSession = preload("res://scripts/v3/gameplay/twin_weapon_session.gd")
var weapons = WeaponSession.new()
var _departure_build: Dictionary = {}
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const CanalSaveGate = preload("res://scripts/v3/core/twin_canal_save_gate.gd")
const Audio = preload("res://scripts/v3/audio/twin_audio.gd")
const AudioSettings = preload("res://scripts/v3/audio/twin_audio_settings.gd")
const CampaignSession = preload("res://scripts/v3/gameplay/twin_campaign_session.gd")
const CampaignChoices = preload("res://scripts/v3/gameplay/twin_campaign_choices.gd")
const CanalAdapter = preload("res://scripts/v3/gameplay/twin_canal_session.gd")
const CanalReplica = preload("res://scripts/v3/gameplay/twin_canal_replica.gd")
const ThermalParticipant = preload("res://scripts/v3/gameplay/twin_thermal_cargo_participant.gd")
const F2Patrol = preload("res://scripts/v3/gameplay/twin_f2_patrol_host.gd")
const Consensus = preload("res://scripts/v3/core/twin_consensus.gd")
const Rules = preload("res://scripts/v3/gameplay/twin_ability_rules.gd")
const LightRotationClearance = preload("res://scripts/v3/gameplay/twin_light_rotation_clearance.gd")
const Encounter = preload("res://scripts/v3/gameplay/twin_encounter_state.gd")
const World = preload("res://scripts/v3/twin_test_world.gd")
const I4Storm = preload("res://scripts/v3/environment/twin_i4_storm_environment.gd")
const RegionSpace = preload("res://scripts/v3/world/twin_region_space.gd")
const Transport = preload("res://scripts/v3/twin_network.gd")
const Interface = preload("res://scripts/v3/twin_interface.gd")
const Regions = preload("res://scripts/v3/world/twin_region_catalog.gd")
const OpeningStory = preload("res://scripts/v3/gameplay/twin_opening_story.gd")
const ReceiptChannel = preload("res://scripts/v3/network/twin_receipt_channel.gd")
const BossAttacks = preload("res://scripts/v3/gameplay/twin_boss_attacks.gd")
const LivingWorld = preload("res://scripts/v3/ecology/twin_living_world.gd")
const NpcSidejobs = preload("res://scripts/v3/ecology/twin_npc_sidejob_host.gd")
const WorldContentBuilder = preload("res://scripts/v3/content/world_content_next/twin_world_content_builder.gd")
const FieldRequests = preload("res://scripts/v3/content/npc_story_next/twin_field_requests_host.gd")
const ContentChapters = preload("res://scripts/v3/content/twin_content_chapters.gd")
const ContentJournal = preload("res://scripts/v3/content/dev88_progression/twin_content_journal.gd")
const Secrets88 = preload("res://scripts/v3/content/dev88_progression/twin_dev88_secrets.gd")
const Presentation88 = preload("res://scripts/v3/content/dev88_presentation/twin_dev88_presentation.gd")
const Voices88 = preload("res://scripts/v3/content/dev88_presentation/twin_dev88_sound_routes.gd")
const StoryJobs88 = preload("res://scripts/v3/content/dev88_story/twin_side_story_host.gd")
const StoryBuilder88 = preload("res://scripts/v3/content/dev88_story/twin_side_story_builder.gd")
const CombatSites88 = preload("res://scripts/v3/content/dev88_combat/twin_combat_sites_runtime.gd")
const FinalFlow = preload("res://scripts/v3/content/final_flow/twin_final_flow.gd")
const FinalVoices = preload("res://scripts/v3/content/final_flow/twin_final_voice_routes.gd")
const FinalStory = preload("res://scripts/v3/content/final_story/twin_final_story_catalog.gd")
const FinalStoryHelper = preload("res://scripts/v3/content/final_story/twin_final_story_helper.gd")
const FinalBossVisuals = preload("res://scripts/v3/content/final_presentation/twin_final_boss_visuals.gd")
const FinalWorld = preload("res://scripts/v3/content/final_world/twin_final_world.gd")
const CrownSession = preload("res://scripts/v3/gameplay/twin_crown_session.gd")
const TerrainVisibility = preload("res://scripts/v3/art/twin_terrain_visibility.gd")
const DroneStaticBatch = preload("res://scripts/v3/art/twin_drone_static_batch.gd")
const Guidance = preload("res://scripts/v3/ui/twin_opening_guidance.gd")
const ClinicSession = preload("res://scripts/v3/gameplay/twin_clinic_session.gd")
const DistributionSession = preload("res://scripts/v3/gameplay/twin_distribution_session.gd")
const TrialSession = preload("res://scripts/v3/gameplay/twin_trial_session.gd")
const FacilityRegistry = preload("res://scripts/v3/gameplay/twin_facility_registry.gd")
const SharedAccessSession = preload("res://scripts/v3/gameplay/twin_shared_access_session.gd")
const TrialGaugeReadout = preload("res://scripts/v3/ui/twin_trial_gauge_readout.gd")
const FRAMES = ["tr01", "hx02", "ag03", "nx04", "sh05", "at06"]
const ERROR_TEXT = {"out_of_range":"距离太远，请靠近目标", "line_of_sight_required":"目标被遮挡", "unsupported_target":"这个物件不支持该能力", "growth_needs_light":"根簇需要先获得光照", "growth_temperature":"温度不适合生长", "insufficient_energy":"能力能量不足，稍候会恢复", "target_busy":"队友正在使用这个物件", "not_owner":"无法接管当前归属的物件", "node_armored":"供能舱装甲关闭，等待攻击后的恢复窗口", "core_shielded":"先让左右供能舱同时停止供能", "actor_downed":"当前无人机已停机，需要救援", "physics_blocked":"路径或目的地被实体挡住，能力未消耗", "target_missing":"请先用 Tab 选择目标"}

var store
var consensus = Consensus.new()
var rules = Rules.new()
var encounter = Encounter.new()
var network: TwinNetwork
var interface: TwinInterface
var inputs: PilotInputV2
var camera: Camera3D
var flight_camera = FlightCameraV22.new()
var flight_assist
var world: TwinTestWorld
var _region_space: RegionSpace
var _presentation_viewport: Viewport
var _fallback_world: World3D
var world_cache: Dictionary = {}
var entities: Dictionary = {}
var players: Dictionary = {}
var identities: Dictionary = {}
var locks: Dictionary = {}
var cooldowns: Dictionary = {} # Ability pacing; weapon fire must never consume this.
var weapon_cooldowns: Dictionary = {}
var shot_notices: Dictionary = {}
var revive_time: Dictionary = {}
var active = false
var boss_active = false
var boss_campaign = false
var simulation_paused = false
var frame_id = "tr01"
var selected_ability = "blink"
var last_light_rotation_clearance: Dictionary = {} # Read-only physics preflight diagnostics; never saved.
var region_id = "I1"
var snapshot_clock = 0.0
var paused_campaign_clock := 0.0
var _quit_draining := false
var last_audio_shutdown_result: Dictionary = {}
var hud_clock = 0.0
var save_clock = 0.0
var packet_sequence = 0
var received_sequence = -1
var pending_packet: Dictionary = {}
var remote_targets: Dictionary = {}
var choice_proposal: Dictionary = {}
var stats = {"inputs":0, "actions":0, "abilities":0, "rejected_abilities":0, "snapshots":0, "guest_joins":0, "guest_leaves":0, "shots":0}
var qa_mode = ""
var qa_seconds = 0.0
var qa_limit = 0.0
var qa_report = ""
var _qa_action_sent = false
var _qa_constructed_usec: int = Time.get_ticks_usec()
var _qa_started_usec: int = -1
var _qa_ready_wait_seconds := 0.0
var _qa_max_raw_delta := 0.0
var _qa_action_seconds := -1.0
var _qa_first_sequence := -1
var _qa_stop_reason := ""
var _boss_target_positions: Dictionary = {}
var _last_input_active = false
var profile_ready = false
var owns_world = false
var received_session = ""
var pending_completion = false
var arena_checkpoint: Dictionary = {}
var _resolving_decision = false
var story = OpeningStory.new()
var receipt_catchup: Dictionary = {}
var receipts = ReceiptChannel.new()
var receipt_retry_clock = 0.0
var ecology = LivingWorld.new()
var sidejobs = NpcSidejobs.new()
var field_requests = FieldRequests.new()
var content_chapters = ContentChapters.new()
var content_journal = ContentJournal.new()
var final_flow = FinalFlow.new()
var final_story = FinalStoryHelper.new()
var story_jobs = StoryJobs88.new()
var combat_sites = CombatSites88.new()
var crown = CrownSession.new()
var terrain_visibility = TerrainVisibility.new()
var _terrain_view_key := ""
var clinic = ClinicSession.new()
var distribution = DistributionSession.new()
var trial = TrialSession.new()
var facilities = FacilityRegistry.new()
## A bound adapter participates in the SAME Store transaction, never its own.
var canal: RefCounted
var environment_save_gate = CanalSaveGate.new()
var canal_runtime_enabled := true
var _canal_action_in_capture := false
var _lifecycle_action: Callable
var _lifecycle_waiting_for_save := false
var canal_replica = CanalReplica.new()
var _canal_epoch := 0
var _canal_serial := 0
var _expected_canal_epoch := 0
var _canal_publish_clock := 0.0
var last_pause_result: Dictionary = {}
var last_commit_result: Dictionary = {}
var _canal_pause_proposal := ""
var _thermal_pause_proposal := ""
var thermal_cargo = ThermalParticipant.new()
var ambient_patrol = F2Patrol.new() # Ordinary F2 patrol; Host simulation, Guest presentation.
var audio = Audio.new()
var _audio_serial := 0
## Opt-in performance diagnostic only; ordinary sessions do not collect samples.
var qa_cpu_enabled := false
var qa_cpu_totals: Dictionary = {}
var qa_store_commit_wall: Array[Dictionary] = [] # Last8 original calls in this CPU ROI only.

func _qa_cpu_begin() -> int:
	return Time.get_ticks_usec() if qa_cpu_enabled else 0

func _qa_cpu_end(label: String, began_usec: int) -> void:
	if not qa_cpu_enabled or began_usec == 0: return
	var elapsed: int = Time.get_ticks_usec()-began_usec
	var row: Dictionary = qa_cpu_totals.get(label,{"count":0,"total_usec":0,"max_usec":0})
	row.count += 1
	row.total_usec += elapsed
	row.max_usec = maxi(row.max_usec,elapsed)
	qa_cpu_totals[label] = row
var campaign = CampaignSession.new()
var chapter_choices = CampaignChoices.new()
var shared_access = SharedAccessSession.new()
var trial_gauge: PanelContainer

func _ready() -> void:
	name = "TwinPulseSession"
	environment_save_gate.setup(self)
	campaign.setup(self)
	chapter_choices.setup(self)
	canal_replica.setup(self)
	thermal_cargo.setup(self)
	add_child(ambient_patrol)
	ambient_patrol.setup(self)
	add_child(combat_sites)
	combat_sites.setup(self)
	_presentation_viewport = get_viewport()
	_fallback_world = _presentation_viewport.find_world_3d()
	crown.setup(self)
	var registered: Dictionary = facilities.setup(self, {"clinic":clinic, "distribution":distribution, "trial":trial, "shared_access":shared_access})
	if not registered.ok:
		push_error("Invalid facility registration: " + str(registered.error))
		return
	trial.gauge_read.connect(_trial_gauge_read)
	var profile = "default"
	var capture_output = ""
	var campaign_output = ""
	var performance_output = ""
	var performance_seconds := 30.0
	var performance_cpu := false
	var performance_disable_3d := false
	var performance_mobile := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile = arg.trim_prefix("--qa-profile=").validate_filename()
		if arg.begins_with("--qa-network="): qa_mode = arg.trim_prefix("--qa-network=")
		if arg.begins_with("--qa-duration="): qa_limit = float(arg.trim_prefix("--qa-duration="))
		if arg.begins_with("--qa-report="): qa_report = arg.trim_prefix("--qa-report=")
		if arg.begins_with("--qa-capture-output="): capture_output = arg.trim_prefix("--qa-capture-output=")
		if arg.begins_with("--qa-campaign-output="): campaign_output = arg.trim_prefix("--qa-campaign-output=")
		if arg.begins_with("--qa-performance-output="): performance_output = arg.trim_prefix("--qa-performance-output=")
		if arg.begins_with("--qa-performance-seconds="): performance_seconds = float(arg.trim_prefix("--qa-performance-seconds="))
		if arg=="--qa-performance-cpu": performance_cpu=true
		if arg=="--disable-3d-diagnostic": performance_disable_3d=true
		if arg=="--qa-renderer-mobile-diagnostic": performance_mobile=true
	if performance_mobile and (performance_disable_3d or OS.get_cmdline_user_args().count("--qa-renderer-mobile-diagnostic")!=1 or not performance_output.is_absolute_path() or not performance_output.get_file().begins_with("campaign-performance-") or ".." in performance_output or not profile.begins_with("qa_campaign_performance_") or Array(OS.get_cmdline_user_args()).filter(func(value: String): return value.begins_with("--qa-profile=")).size()!=1 or Array(OS.get_cmdline_user_args()).filter(func(value: String): return value.begins_with("--qa-performance-output=")).size()!=1 or OS.get_cmdline_user_args().count("--qa-profile="+profile)!=1 or OS.get_cmdline_user_args().count("--qa-performance-output="+performance_output)!=1 or not qa_mode.is_empty() or not capture_output.is_empty() or not campaign_output.is_empty()):
		push_error("Mobile renderer diagnostic requires one explicit isolated performance observer")
		get_tree().quit(2); return
	if performance_disable_3d and (performance_output.is_empty() or not profile.begins_with("qa_campaign_performance_") or not qa_mode.is_empty() or not capture_output.is_empty() or not campaign_output.is_empty() or OS.get_cmdline_user_args().count("--disable-3d-diagnostic")!=1):
		push_error("Render diagnostic requires an explicit isolated performance observer")
		get_tree().quit(2)
		return
	if (not qa_mode.is_empty() or not capture_output.is_empty() or not campaign_output.is_empty() or not performance_output.is_empty() or performance_cpu) and not profile.begins_with("qa_"):
		push_error("Automated QA requires an isolated qa_ profile")
		get_tree().quit(2)
		return
	if "--qa-performance-long-i2" in OS.get_cmdline_user_args():
		var long_checked: Dictionary = load("res://scripts/v3/qa/twin_campaign_performance.gd").long_i2_preflight(OS.get_cmdline_user_args())
		if not long_checked.ok:
			push_error(str(long_checked.code)); get_tree().quit(2); return
	store = Store.new("user://profiles_v3/" + profile)
	var loaded: Dictionary = store.load_profile()
	world_cache = store.snapshot()
	network = Transport.new()
	network.name = "Network"
	add_child(network)
	weapons.session = self
	network.input_received.connect(_command_received)
	network.action_received.connect(_action_received)
	network.guest_joined.connect(_guest_joined)
	network.guest_left.connect(_guest_left)
	network.snapshot_received.connect(_queue_snapshot)
	network.event_received.connect(_network_event)
	network.status_changed.connect(func(message): if interface: interface.notify(message))
	inputs = PilotInputV2.new()
	add_child(inputs)
	inputs.pause_requested.connect(func(_reason): _request_pause())
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 36
	camera.far = 300
	add_child(camera)
	camera.make_current()
	flight_camera.configure(camera)
	flight_camera.target_size = 26
	interface = Interface.new()
	interface.action_requested.connect(_ui_action)
	add_child(interface)
	add_child(audio)
	audio.bind_session(self)
	var sound_settings = AudioSettings.new()
	interface.menu_content.add_child(sound_settings)
	sound_settings.setup(audio)
	trial_gauge=TrialGaugeReadout.new()
	interface.hud.add_child(trial_gauge)
	trial_gauge.setup_layout(interface.bottom_panel,[interface.top_panel,interface.task_panel,interface.radio],interface.pilot_marker)
	if not ecology.setup(self):
		interface.notify("环境航线资料无法读取，请检查内容包。")
		return
	receipts.setup(self)
	sidejobs.setup(self,func() -> Dictionary: return {"contact":OS.get_keycode_string(KEY_G),"ability":OS.get_keycode_string(KEY_F),"brake":inputs.legacy.binding_label("brake")})
	field_requests.setup(self,func() -> Dictionary: return {"contact":OS.get_keycode_string(KEY_G),"ability":OS.get_keycode_string(KEY_F),"brake":inputs.legacy.binding_label("brake")})
	content_chapters.setup(self)
	content_journal.setup(self)
	final_flow.setup(self)
	final_story.setup(self)
	if not story_jobs.setup(self,func() -> Dictionary: return {"contact":OS.get_keycode_string(KEY_G),"ability":OS.get_keycode_string(KEY_F),"brake":inputs.legacy.binding_label("brake")}):
		interface.notify("短支线内容资料无法读取，请保留存档并检查完整内容包。")
		return
	story_jobs.set_combat_source(combat_sites.completed, combat_sites.completion_serial)
	if not story.setup(self):
		interface.notify("开场行动资料无法读取，请检查内容包。")
		return
	get_tree().auto_accept_quit = false
	if not loaded.get("ok", false):
		interface.notify("存档未打开：" + str(loaded.get("error", "unknown")))
		return
	var bootstrap: Dictionary = store.commit({"id":"profile-bootstrap-v3"})
	if not bootstrap.get("ok", false):
		interface.notify("无法保存玩家身份：" + str(bootstrap.get("error", "unknown")))
		return
	profile_ready = true
	world_cache = store.snapshot()
	var selected_loadout: Dictionary = Hangar.launch_build(world_cache)
	if selected_loadout.get("ok",false):
		frame_id = str(selected_loadout.build.airframe_id)
		interface.frames.select(FRAMES.find(frame_id))
	interface.set_branches(store.list_branches())
	print("V3_READY user_dir=", OS.get_user_data_dir(), " profile=", profile)
	interface.install_front(self)
	_ensure_flight_assist()
	if not performance_output.is_empty():
		var driver = load("res://scripts/v3/qa/twin_campaign_performance.gd").new()
		add_child(driver)
		driver.run.call_deferred(self,performance_output,performance_seconds,performance_cpu,performance_disable_3d)
		return
	if not campaign_output.is_empty():
		var driver = load("res://scripts/v3/qa/twin_campaign_packaged_check.gd").new()
		add_child(driver)
		driver.run.call_deferred(self,campaign_output)
		return
	if not capture_output.is_empty():
		var driver = load("res://scripts/v3/qa/twin_packaged_capture.gd").new()
		add_child(driver)
		driver.run.call_deferred(self, capture_output)
		return
	if qa_mode == "host": start_flight("host")
	elif qa_mode == "guest": start_flight("guest", "127.0.0.1")
	elif qa_mode == "solo": start_flight("solo")

func start_flight(mode: String, address = "127.0.0.1") -> bool:
	if not profile_ready:
		interface.notify("存档尚未成功打开，不能开始会话")
		return false
	if active and consensus.current_proposal().get("state") == "ready":
		interface.notify("共同决定正在等待保存；请先重试确认或明确取消")
		return false
	if _capture_before_lifecycle(func(): start_flight(mode,address)): return false
	if pending_completion:
		_finish_boss()
		if pending_completion: return false
	if owns_world and active and not _canal_action_in_capture and not _save_environment(): return false
	world_cache = store.snapshot()
	var launch: Dictionary = Hangar.launch_build(world_cache,frame_id)
	if not launch.get("ok",false):
		interface.notify(Hangar.error_text(launch))
		return false
	_departure_build = launch.build.duplicate(true)
	if mode != "guest" and not ecology.restore_world(world_cache.world):
		interface.notify("环境记录不兼容或损坏，原存档已保留；不能重置后覆盖。")
		return false
	Engine.time_scale = 1.0
	story.reset_connection()
	sidejobs.reset_connection()
	field_requests.reset_connection()
	content_chapters.reset_connection()
	content_journal.reset_connection()
	final_flow.reset_connection()
	story_jobs.reset_connection()
	ecology.reset_connection()
	facilities.reset_connection()
	if is_instance_valid(trial_gauge): trial_gauge.clear_readings()
	receipts.reset()
	receipt_catchup.clear()
	receipt_retry_clock = 0.0
	simulation_paused = false
	active = false
	owns_world = false
	received_sequence = -1
	packet_sequence = 0
	received_session = ""
	pending_packet.clear()
	choice_proposal.clear()
	cooldowns.clear()
	weapon_cooldowns.clear()
	shot_notices.clear()
	revive_time.clear()
	_clear_players()
	_dispose_current_region()
	var error = OK
	if mode == "host": error = network.host()
	elif mode == "guest": error = network.join(address, str(world_cache.profile_id), Transport.DEFAULT_PORT, frame_id, _departure_build)
	else: network.start_solo()
	if error != OK:
		interface.notify(error_string(error))
		return false
	active = true
	owns_world = mode != "guest"
	interface.show_game()
	if mode != "guest":
		if not _load_region(str(world_cache.world.get("region_id", "I1"))): return false
		_spawn_player(1, str(world_cache.profile_id), world.spawn_position)
		if not players.has(1): return false
		consensus.configure([1], int(world_cache.world_revision))
		flight_camera.snap(players[1].global_position,players[1].heading)
	return true

func _load_region(id: String) -> bool:
	network._lan_trace("region_load_begin:"+id)
	var prepared := _prepare_region(id)
	network._lan_trace("region_prepared:"+id, {"ok":bool(prepared.ok)})
	if not prepared.ok:
		_stop_failed_region_load("地区地形资料与模型不匹配，会话已停止，存档保留：" + str(prepared.error))
		return false
	var initialization: Dictionary = prepared.facilities.initialization
	if owns_world and not initialization.is_empty():
		if not _commit("facilities-initialize", initialization):
			_discard_prepared_region(prepared)
			_stop_failed_region_load("保存失败，房间已关闭，原存档保留。请重试进入世界。")
			return false
	var loaded: bool = _adopt_prepared_region(prepared)
	network._lan_trace("region_adopted:"+id, {"ok":loaded})
	return loaded

func _stop_failed_region_load(message: String) -> void:
	if is_instance_valid(flight_assist): flight_assist.stop("区域加载停止，辅助已交还控制。")
	network._lan_trace("close_origin_region_load_failed", {"region":region_id,"reason":message.left(240)})
	active = false
	owns_world = false
	inputs.clear()
	for peer_id in players: players[peer_id].freeze = true
	network.close()
	interface.menu.visible = true
	interface.notify(message)

## Build before any persistent travel/branch commit. There is no await between
## construction and adoption/discard, so the candidate never advances a frame.
func _prepare_region(id: String, destination_world: Dictionary = {}) -> Dictionary:
	var destination = id if Regions.playable(id) else "I1"
	var saved_world: Dictionary = (world_cache.get("world", {}) if destination_world.is_empty() else destination_world).duplicate(true)
	if not network.is_authority(): saved_world = {}
	elif destination_world.is_empty():
		if not saved_world.has("environment"): saved_world.environment = {}
		var latest: Dictionary = facilities.persistent_states()
		for path in latest: saved_world.environment[str(path).trim_prefix("world.environment.")] = latest[path]
		if region_id == "I2" and is_instance_valid(world): saved_world.entities.I2 = _persistent_environment()
	var discoveries: Array = store.snapshot().get("personal", {}).get("discoveries", []) if network.is_authority() else []
	var prepared_facilities: Dictionary = facilities.prepare(saved_world, destination, network.is_authority(), discoveries)
	if not prepared_facilities.ok: return prepared_facilities
	if not is_instance_valid(_presentation_viewport) or _presentation_viewport.own_world_3d:
		facilities.discard(prepared_facilities)
		return {"ok":false,"error":"shared_main_viewport_required"}
	var next_space = RegionSpace.new()
	add_child(next_space)
	var next_world = World.new()
	var mounted: Dictionary = next_space.mount(next_world)
	if not mounted.ok:
		next_space.queue_free()
		if next_world.get_parent() == null: next_world.free()
		facilities.discard(prepared_facilities)
		return {"ok":false,"error":"region_space:"+str(mounted.code)}
	var next_entities: Dictionary = next_world.build(destination, saved_world.get("flags", {}), network.is_authority(), prepared_facilities.modules)
	if is_instance_valid(next_world.campaign_arena):
		var visual_components: Dictionary = FinalBossVisuals.decorate(next_world.campaign_arena)
		if not visual_components.get("ok", false): next_world.build_errors.append("boss_visuals:" + str(visual_components.get("code", "unavailable")))
		for original: MeshInstance3D in visual_components.get("original_meshes", []): original.hide()
	var final_weather := FinalWorld.build(next_world)
	if final_weather != null: next_world.add_child(final_weather)
	else: next_world.build_errors.append("final_weather_unavailable:" + destination)
	var content: Dictionary = WorldContentBuilder.install(next_world)
	var side_content: Dictionary = StoryBuilder88.install(next_world)
	if not side_content.get("ok", false): next_world.build_errors.append("side_story:" + str(side_content.get("code", "unavailable")))
	Secrets88.install(next_world)
	Presentation88.decorate_devices(next_world)
	if not content.get("ok", false): next_world.build_errors.append("world_content:" + str(content.get("code", "unavailable")))
	# The original build returned a copy before the new authored entities existed.
	next_entities = next_world.definitions.duplicate(true)
	if not next_world.build_errors.is_empty():
		var error_message = str(next_world.build_errors)
		facilities.discard(prepared_facilities)
		remove_child(next_space)
		next_space.queue_free()
		return {"ok":false, "error":error_message}
	var prepared: Dictionary = {"ok":true, "region":destination, "world":next_world,"space_owner":next_space, "entities":next_entities, "facilities":prepared_facilities, "saved_world":saved_world}
	if canal_runtime_enabled and destination == "I2" and network.is_authority():
		var adapter = CanalAdapter.new()
		adapter.setup(self)
		var site: Dictionary = adapter.prepare(saved_world,destination,true,discoveries)
		if not site.get("ok",false):
			_discard_prepared_region(prepared)
			return {"ok":false,"error":"canal_prepare:"+str(site.get("code","failed"))}
		prepared["canal"] = {"adapter":adapter,"site":site}
	return prepared

func _discard_prepared_region(prepared: Dictionary) -> void:
	if prepared.has("canal"): prepared.canal.adapter.discard(prepared.canal.site)
	if prepared.has("facilities"): facilities.discard(prepared.facilities)
	var candidate = prepared.get("space_owner")
	if is_instance_valid(candidate):
		candidate.get_parent().remove_child(candidate)
		candidate.queue_free()

func _dispose_current_region() -> void:
	sidejobs.clear_transient()
	field_requests.clear_transient()
	story_jobs.clear_transient()
	content_chapters.clear_transient()
	ambient_patrol.clear()
	combat_sites.clear()
	# This first migration changes ownership only. Travel still disposes the old
	# region; retaining I2 also requires the facility/save lifecycle adaptation.
	if is_instance_valid(_region_space):
		_restore_presentation_world()
		_region_space.get_parent().remove_child(_region_space)
		_region_space.queue_free()
	elif is_instance_valid(world):
		world.get_parent().remove_child(world)
		world.queue_free()
	_region_space = null
	world = null

func _restore_presentation_world() -> void:
	if is_instance_valid(_presentation_viewport) and is_instance_valid(_region_space) and _presentation_viewport.find_world_3d() == _region_space.world:
		_presentation_viewport.world_3d = _fallback_world

func _adopt_prepared_region(prepared: Dictionary) -> bool:
	_clear_terrain_visibility()
	region_id = str(prepared.region)
	remote_targets.clear()
	locks.clear()
	cooldowns.clear()
	weapon_cooldowns.clear()
	_boss_target_positions.clear()
	boss_active = false
	boss_campaign = false
	crown.clear()
	campaign.clear()
	_canal_pause_proposal = ""
	_thermal_pause_proposal = ""
	thermal_cargo.clear()
	if not _canal_action_in_capture: environment_save_gate.cancel("region_changed")
	if canal != null: canal.clear()
	canal = null
	canal_replica.clear()
	_expected_canal_epoch = 0
	facilities.clear()
	if is_instance_valid(trial_gauge): trial_gauge.clear_readings()
	_dispose_current_region()
	world = prepared.world
	_region_space = prepared.space_owner
	var presented: Dictionary = _region_space.present_on(_presentation_viewport)
	if not presented.ok:
		_stop_failed_region_load("地区画面无法接入，会话已停止，存档保留。")
		return false
	if is_instance_valid(world.trial):
		for node: Node in world.trial.station.get_children():
			if node is TwinTrialFlowPresentation: node.camera = camera
	entities = prepared.entities
	world.spawn_position = Regions.spawn(region_id)
	var saved: Dictionary = world_cache.get("world", {}).get("entities", {}).get(region_id, {})
	for id_key in saved:
		if not entities.has(id_key): continue
		var restored: Variant = _decode(saved[id_key])
		if not restored is Dictionary or restored.has("position") and not restored.position is Vector3:
			_stop_failed_region_load("地区设备坐标无效，原档保留。")
			return false
		entities[id_key].merge(restored, true)
	world.restored_gate = bool(world_cache.get("world", {}).get("flags", {}).get(region_id + "_gate", false))
	world.local_authority = network.is_authority()
	world.initialize_mechanisms(entities)
	var adopted: Dictionary = facilities.adopt(prepared.facilities, prepared.saved_world)
	if not adopted.ok:
		_stop_failed_region_load("设施恢复失败，会话已停止，存档保留：" + str(adopted.error))
		return false
	world.set_boss_state({}, bool(world_cache.get("world", {}).get("flags", {}).get("campaign_crown_v1" if region_id == "F1" else "campaign_whale_v1", false)))
	if prepared.has("canal"):
		canal = prepared.canal.adapter
		_canal_epoch += 1
		_canal_serial = 0
		_canal_publish_clock = 0.0
		var installed: Dictionary = canal.adopt(prepared.canal.site,prepared.saved_world)
		if not installed.get("ok",false):
			_stop_failed_region_load("南湾现场无法恢复，原档保留："+str(installed.get("code","failed")))
			return false
	story.load_world()
	if not chapter_choices.bind_world():
		_stop_failed_region_load("章节阅读记录无法恢复，原档保留："+chapter_choices.error)
		return false
	if not campaign.bind_world():
		_stop_failed_region_load("地区机关记录无法恢复，原档保留："+campaign.error)
		return false
	ecology.bind_world()
	field_requests.bind_world()
	_apply_pause_state()
	for peer_id in players:
		var body: FlightBodyV2 = players[peer_id]
		body.global_position = world.spawn_position + Vector3((int(peer_id) % 2) * 3, 0, 0)
		body.linear_velocity = Vector3.ZERO
		body.hold_height = body.position.y
		body.environment_query = world.sample_environment
		body.environment_hazards_authoritative = network.is_authority()
		body.environment_sample = world.sample_environment(body.global_position)
		# A rescue checkpoint from the previous region may lie outside this map.
		body.safe_position = body.global_position
		body.water_seconds = 0.0
		body.water_contact = false
		_register_player_entity(int(peer_id))
	if not thermal_cargo.bind_world():
		_stop_failed_region_load("吊载记录无法恢复，原档保留："+thermal_cargo.error)
		return false
	var patrol_bound: Dictionary=ambient_patrol.bind_world()
	if not patrol_bound.ok:
		_stop_failed_region_load("巡逻场地未通过原生构建检查："+str(patrol_bound.code))
		return false
	var combat_bound: Dictionary = combat_sites.bind_world()
	if not combat_bound.get("ok", false):
		_stop_failed_region_load("可选遭遇现场无法读取，原档保留：" + str(combat_bound.get("code", "unavailable")))
		return false
	story_jobs.bind_world()
	content_chapters.bind_world()
	final_story.bind_world()
	return true

func _spawn_player(peer_id: int, identity: String, at: Vector3, airframe = "", hardware: Dictionary = {}) -> void:
	if players.has(peer_id): return
	var body = FlightBodyV2.new()
	body.name = "Pilot_" + str(peer_id)
	var chosen = airframe if airframe in FRAMES else frame_id
	var saved_cargo_build: Dictionary = thermal_cargo.saved_build(identity)
	var chosen_build: Dictionary = CatalogV2.default_build(chosen)
	if not hardware.is_empty(): chosen_build = hardware
	elif peer_id == network.local_id() and not _departure_build.is_empty(): chosen_build = _departure_build
	elif network.guest_builds.has(peer_id): chosen_build = network.guest_builds[peer_id]
	# Saved I3 custody belongs to the original departure build, including metadata.
	if not saved_cargo_build.is_empty(): chosen_build = saved_cargo_build
	var resolved: Dictionary = CatalogV2.resolve_build(chosen_build)
	if not resolved.valid:
		body.free()
		_stop_failed_region_load("出击配装无法读取，原存档保留。")
		return
	body.configure(resolved)
	body.environment_hazards_authoritative = network.is_authority()
	body.sandbox_rules = {"unlimited_power":true}
	body.max_altitude = 27
	add_child(body)
	# _ready has collected the original Rotor nodes and attachments. Batch only
	# known TR01 visual geometry; never alter the native body or shared factory.
	if body.build.get("airframe_id", "") == "tr01":
		var visual_batch: Dictionary = DroneStaticBatch.install(body.model, true)
		if visual_batch.get("ok", false):
			body.model.set_meta("v3_drone_static_batch_report", visual_batch.report)
			if int(visual_batch.report.merged_source_meshes) > 0: body.rebuild_visibility_silhouette()
		else:
			push_warning("TR01 visual batch kept original geometry: " + str(visual_batch.get("code", "unavailable")))
	body.global_position = at
	body.hold_height = at.y
	body.safe_position = at
	body.environment_query = world.sample_environment
	body.environment_sample = world.sample_environment(at)
	body.disabled.connect(func(): _pilot_disabled(peer_id))
	body.crash_started.connect(func(): _audio_owner_vital(peer_id,"disabled"))
	players[peer_id] = body
	identities[peer_id] = identity
	locks[peer_id] = ""
	_register_player_entity(peer_id)
	body.freeze = simulation_paused or (not network.is_authority() and peer_id != network.local_id())
	body.set_process(not simulation_paused)
	if not thermal_cargo.bind_world(): _stop_failed_region_load("载货身份无法恢复，原档保留："+thermal_cargo.error)

func _apply_pause_state() -> bool:
	last_pause_result = {"ok":true,"code":"applied","paused":simulation_paused}
	if canal != null:
		var paused_site: Dictionary = canal.set_paused(simulation_paused)
		last_pause_result = paused_site.duplicate(true)
		if not paused_site.get("ok",false):
			simulation_paused = bool(canal.status().physics_paused)
			_note_all("南湾暂停状态未改变："+str(paused_site.get("code","failed")))
			return false
	if thermal_cargo.supported():
		var cargo_pause: Dictionary = thermal_cargo.set_paused(simulation_paused)
		if not cargo_pause.get("ok",false) or simulation_paused and not cargo_pause.get("ready",true):
			last_pause_result = cargo_pause.duplicate(true)
			simulation_paused = thermal_cargo.pause_status().get("paused",false)
			return false
	for peer_id in players:
		# RigidBody freeze does not stop the downed recovery clock in _process.
		players[peer_id].set_process(not simulation_paused)
		if thermal_cargo.owns_paused_body(players[peer_id]): continue
		players[peer_id].freeze = simulation_paused or thermal_cargo.remote_loaded_actor(players[peer_id]) or (not network.is_authority() and (peer_id != network.local_id() or not _facilities_ready()))
	if not is_instance_valid(world): return true
	for id in world.objects:
		var body = world.objects[id]
		if body is RigidBody3D:
			if canal != null and canal.owns_body(body): continue
			if thermal_cargo.owns_paused_body(body): continue
			body.freeze = simulation_paused or not network.is_authority() or bool(entities.get(id, {}).get("pinned", false))
	world.set_effects_paused(simulation_paused)
	facilities.set_paused(simulation_paused)
	if simulation_paused: weapons.cancel_all("paused")
	return true

func _facilities_ready() -> bool:
	var site_ready: bool = network.is_authority() or region_id != "I2" or _expected_canal_epoch == 0 or canal_replica.installed and int(canal_replica.status().epoch) == _expected_canal_epoch
	return facilities.all_ready(region_id) and campaign.presentation_ready() and site_ready

func _register_player_entity(peer_id: int) -> void:
	var body: FlightBodyV2 = players[peer_id]
	entities[_actor_id(peer_id)] = {"id":_actor_id(peer_id), "name":"小队无人机", "position":body.global_position, "tags":["player"], "revision":0, "owner":str(peer_id), "energy":100.0, "max_energy":100.0, "health":body.health, "downed":not body.enabled}
	facilities.sync_roster(peer_id)

func _clear_players() -> void:
	ambient_patrol.reset_connection()
	combat_sites.reset_connection()
	weapons.clear()
	_clear_terrain_visibility()
	for body in players.values():
		if is_instance_valid(body): body.queue_free()
	players.clear()
	identities.clear()
	entities.clear()
	remote_targets.clear()
	locks.clear()
	cooldowns.clear()
	weapon_cooldowns.clear()
	shot_notices.clear()

func _physics_process(delta: float) -> void:
	if not active or not is_instance_valid(world): return
	sidejobs.consume_projection()
	if not network.is_authority():
		content_chapters.advance(delta)
		story_jobs.advance(delta)
	var qa_clock: int = _qa_cpu_begin()
	if canal_runtime_enabled and canal != null:
		_reconcile_canal_pause_request()
		var canal_tick: Dictionary = canal.advance(delta)
		if not canal_tick.ok: _note_all("南湾现场已停止：" + str(canal_tick.code))
		_finish_canal_pause_request()
		_canal_publish_clock += delta
		if _canal_publish_clock >= .1:
			_canal_publish_clock = 0.0
			_publish_canal()
	_qa_cpu_end("canal.total",qa_clock)
	qa_clock = _qa_cpu_begin()
	receipts.tick(delta)
	if owns_world:
		receipt_retry_clock += delta
		if receipt_retry_clock >= 8:
			receipt_retry_clock = 0.0
			_retry_receipt_catchup()
	var local = network.local_id()
	world.local_authority = network.is_authority()
	# FlightBody's hull reads environment_sample; environment_query alone is
	# used by suspended cargo. Sample both authority and local prediction here.
	if not simulation_paused or region_id == "I4":
		for pilot: FlightBodyV2 in players.values():
			pilot.environment_sample = world.sample_environment(pilot.global_position)
	inputs.active = not interface.journal.visible and not interface.hangar.visible and not interface.menu.visible and not interface.wheel.visible and not interface.chapter_choice.visible and not simulation_paused and not interface.vote.visible and not interface.travel.visible and (network.is_authority() or _facilities_ready())
	if inputs.active != _last_input_active:
		inputs.clear()
		_last_input_active = inputs.active
	inputs.legacy.pointer_fire_blocked = interface.blocks_pointer_fire()
	var command = inputs.command(camera.global_basis)
	# The input adapter chooses head-relative or the preserved map scheme.
	# Do not overwrite it here: FlightBody already resolves pitch/roll by heading.
	if is_instance_valid(flight_assist) and qa_mode.is_empty():
		command=flight_assist.compose_command(command,delta)
	if not qa_mode.is_empty():
		command = {"active":true, "body_relative":false, "mode":"assisted", "planar":Vector3(0.25, 0, -0.3) if qa_seconds < 3.5 else Vector3.ZERO, "vertical":0.0, "brake":qa_seconds > 3.5, "fire":false}
	network.send_input(command)
	_qa_cpu_end("input_environment",qa_clock)
	if not network.is_authority():
		if not _facilities_ready(): return
		if players.has(local) and not simulation_paused: players[local].command = command
		for peer_id in players:
			if remote_targets.has(peer_id):
				var target: Dictionary = remote_targets[peer_id]
				var body: FlightBodyV2 = players[peer_id]
				var error = body.global_position.distance_to(target.position)
				body.global_position = body.global_position.lerp(target.position, 1.0 if error > 4 else minf(delta * (8 if peer_id == local else 14), 1))
				if error > 4 and peer_id == local:
					# A host rescue/teleport must also reset the local flight controller;
					# otherwise its old submerged hold target pulls the pilot down again.
					body.linear_velocity = target.get("velocity", Vector3.ZERO)
					body.angular_velocity = Vector3.ZERO
					body.hold_height = body.global_position.y
					body.water_seconds = 0.0
					body.water_contact = false
				if peer_id != local: body.rotation.y = lerp_angle(body.rotation.y, float(target.get("heading", 0)), delta * 12)
		if not simulation_paused: world.synchronize(entities, delta)
		return
	for id in network.stale_peers():
		if players.has(id): players[id].command = {"active":false, "brake":true}
	qa_clock = _qa_cpu_begin()
	_reconcile_thermal_pause_request()
	thermal_cargo.advance(delta) # After ordinary player commands; one native tick.
	_finish_thermal_pause_request()
	if canal == null or canal_runtime_enabled: _advance_environment_save()
	_qa_cpu_end("thermal_and_save_gate",qa_clock)
	# A successful lifecycle continuation can release this world at this boundary.
	if not active or not is_instance_valid(world) or simulation_paused: return
	qa_clock = _qa_cpu_begin()
	for peer_id in players:
		var body: FlightBodyV2 = players[peer_id]
		var entity: Dictionary = entities[_actor_id(peer_id)]
		entity.position = body.global_position
		entity.health = body.health
		entity.downed = not body.enabled
		entity.energy = minf(100, float(entity.energy) + delta * 9)
		cooldowns[peer_id] = maxf(0, float(cooldowns.get(peer_id, 0)) - delta)
		weapons.advance_peer(int(peer_id), delta)
		if boss_active and region_id == "I1": encounter.set_player_position(str(peer_id), body.global_position)
	_qa_cpu_end("actor_state",qa_clock)
	qa_clock = _qa_cpu_begin()
	for id in world.objects:
		entities[id].position = world.objects[id].global_position
	var timed_entities: Dictionary = entities.duplicate()
	for id in timed_entities.keys():
		if str(id).begins_with(CrownSession.HOST_PREFIX): timed_entities.erase(id)
	var timed: Dictionary = rules.advance_states(timed_entities, delta)
	if timed.get("ok", false): rules.commit(timed, entities)
	_qa_cpu_end("generic_rules",qa_clock)
	qa_clock = _qa_cpu_begin()
	world.synchronize(entities, delta, players)
	_qa_cpu_end("world.synchronize",qa_clock)
	qa_clock = _qa_cpu_begin()
	facilities.advance(delta)
	_qa_cpu_end("facilities.advance",qa_clock)
	qa_clock = _qa_cpu_begin()
	ecology.advance(delta)
	_qa_cpu_end("ecology.advance",qa_clock)
	qa_clock = _qa_cpu_begin()
	campaign.advance(delta)
	_qa_cpu_end("campaign.advance",qa_clock)
	sidejobs.advance()
	field_requests.advance(delta)
	story_jobs.advance(delta)
	var site_tick: Dictionary = combat_sites.advance(delta)
	if not site_tick.get("ok", false): _note_all("可选遭遇已停止，已保存成果保留：" + str(site_tick.get("code", "unavailable")))
	var patrol_tick: Dictionary=ambient_patrol.advance(delta) if network.is_authority() else {"ok":true}
	if not patrol_tick.ok: _note_all("巡逻现场停止："+str(patrol_tick.code))
	qa_clock = _qa_cpu_begin()
	if boss_active:
		if campaign.active(): pass
		elif crown.active(): crown.advance(delta)
		else:
			_handle_boss_events(encounter.advance(delta))
			_sync_boss_entities()
			_update_boss_warning()
	_update_revives(delta)
	_qa_cpu_end("combat_and_revives",qa_clock)
	qa_clock = _qa_cpu_begin()
	story.observe(delta)
	content_chapters.advance(delta)
	_qa_cpu_end("story.observe",qa_clock)
	save_clock += delta
	if save_clock >= 8:
		save_clock = 0
		if pending_completion: _finish_boss()
		request_environment_save()

func _process(delta: float) -> void:
	var qa_clock: int = _qa_cpu_begin()
	if not pending_packet.is_empty():
		var packet = pending_packet
		pending_packet = {}
		_apply_snapshot(packet)
	if not active or not is_instance_valid(world): return
	weapons.publish(delta)
	# Presentation transport keeps working during a common pause. A reconnect
	# can bind its epoch after the first reliable event arrived; resend the same
	# current state without advancing any encounter, mechanism or physics.
	if simulation_paused and network.is_authority() and not network.guests.is_empty() and campaign.supported():
		paused_campaign_clock+=delta
		if paused_campaign_clock>=0.25:
			paused_campaign_clock=0.0
			campaign.publish()
	else:
		paused_campaign_clock=0.0
	var local = network.local_id()
	if players.has(local):
		var body: FlightBodyV2 = players[local]
		var qa_part: int = _qa_cpu_begin()
		var reduced: bool=interface.front!=null and bool(interface.front.prefs.values.reduced_motion)
		flight_camera.update(delta, body.global_position, body.linear_velocity,reduced,body.heading)
		_qa_cpu_end("process.camera",qa_part)
		qa_part = _qa_cpu_begin()
		_update_terrain_visibility(body, delta)
		_qa_cpu_end("process.terrain_visibility",qa_part)
		qa_part = _qa_cpu_begin()
		world.set_focus(body.global_position, str(locks.get(local, "")))
		_qa_cpu_end("process.world_focus",qa_part)
		qa_part = _qa_cpu_begin()
		story.refresh(body.global_position, 0.0 if simulation_paused else delta)
		_qa_cpu_end("process.story_refresh",qa_part)
		qa_part = _qa_cpu_begin()
		_update_pilot_marker(body)
		ecology.update_view(delta, body.global_position)
		FinalWorld.apply_state(world.get_node_or_null(FinalWorld.ROOT_NAME),
			{"weather":world.ecology_weather,"clock":world.clock_seconds,"wind_velocity":body.environment_sample.get("wind_velocity", Vector3.ZERO)},
			FinalWorld.ecology_view(ecology, network.is_authority()), simulation_paused, body.global_position)
		_qa_cpu_end("process.ecology_view",qa_part)
		qa_part = _qa_cpu_begin()
		var direction: Vector3 = camera.global_basis.z.normalized()
		var ray_start: Vector3 = body.global_position + direction * maxf(0.0, (camera.global_position - body.global_position).dot(direction) - camera.near)
		var ray = PhysicsRayQueryParameters3D.create(ray_start, body.global_position, 1 | 8)
		body.set_occlusion_hint(not get_world_3d().direct_space_state.intersect_ray(ray).is_empty(), delta)
		_qa_cpu_end("process.pilot_occlusion",qa_part)
	var qa_part: int = _qa_cpu_begin()
	snapshot_clock += delta
	if snapshot_clock >= 0.05 and network.is_authority():
		snapshot_clock = 0
		if network.mode == "host" and not network.guests.is_empty():
			network.publish(_snapshot())
		else:
			# _snapshot advances this once, even when publish has no recipient.
			# Keep that clock without materializing an unused full-world packet.
			packet_sequence += 1
	_qa_cpu_end("process.snapshot",qa_part)
	qa_part = _qa_cpu_begin()
	hud_clock += delta
	if hud_clock >= 0.12:
		hud_clock = 0
		_refresh_interface()
	_qa_cpu_end("process.HUD",qa_part)
	if not qa_mode.is_empty():
		_observe_qa_network(delta, local)
	ambient_patrol.present(delta)
	combat_sites.present(delta)
	_qa_cpu_end("process.total",qa_clock)

func _observe_qa_network(raw_delta: float, local: int) -> void:
	# Opt-in QA only. Scene construction and the first render delta must not
	# consume the client's observation window or send a request before welcome.
	_qa_max_raw_delta = maxf(_qa_max_raw_delta, raw_delta)
	var ready := active and is_instance_valid(world) and players.has(local)
	if qa_mode == "guest":
		ready = ready and not received_session.is_empty() and received_sequence >= 0 and stats.snapshots > 0 and story.ready and _facilities_ready()
	if not ready: return
	var now := Time.get_ticks_usec()
	if _qa_started_usec < 0:
		_qa_started_usec = now
		_qa_ready_wait_seconds = float(now - _qa_constructed_usec) / 1000000.0
		_qa_first_sequence = received_sequence
		print("V3_QA_NETWORK_READY ", JSON.stringify({"mode":qa_mode,"region":region_id,"ready_wait_seconds":_qa_ready_wait_seconds,"first_sequence":_qa_first_sequence}))
	qa_seconds = float(now - _qa_started_usec) / 1000000.0
	if qa_seconds > 5.0 and not _qa_action_sent:
		_qa_action_sent = true
		_qa_action_seconds = qa_seconds
		network.send_action("ability", {"ability":"blink", "point":players[local].global_position + Vector3(2, 0, 0)})
	if qa_limit <= 0 or qa_seconds < qa_limit: return
	if qa_limit > 5.0 and (not _qa_action_sent or qa_seconds - _qa_action_seconds < 2.0): return
	# The loopback host must outlive both clients' complete observation windows.
	# A missing client still ends at a bounded time and fails the peer assertions.
	if qa_mode == "host" and int(stats.guest_leaves) < 2 and qa_seconds < 60.0: return
	_qa_stop_reason = "observation_complete" if qa_mode != "host" or int(stats.guest_leaves) >= 2 else "peer_deadline"
	_write_qa_report()
	_quit()

func _update_terrain_visibility(body: FlightBodyV2, delta: float) -> bool:
	if not is_instance_valid(world) or not is_instance_valid(body):
		_clear_terrain_visibility()
		return false
	var key := "%d:%d" % [world.get_instance_id(), body.get_instance_id()]
	if key != _terrain_view_key:
		var candidates: Array = []
		if is_instance_valid(world.crown_arena):
			candidates.append_array(world.crown_arena.hosts.values())
			candidates.append_array(world.crown_arena.ground_modules)
		if is_instance_valid(world.underdeck):
			candidates.append(world.underdeck.shell)
		if is_instance_valid(world.clinic):
			for id in ["PumpRoof", "PumpWestWall", "PumpEastWall", "PumpNorthWall"]:
				candidates.append(world.clinic.fixed_bodies[id])
			candidates.append_array(world.clinic.gravity_art.get("occluders", []))
			candidates.append_array(world.clinic.reception_art.get("occluders", []))
			candidates.append_array(world.clinic.west_service_room_art.get("occluders", []))
			candidates.append_array(world.clinic.west_offset_room_art.get("occluders", []))
			candidates.append_array(world.clinic.west_landing_platform_art.get("occluders", []))
			candidates.append_array(world.clinic.lift_deck_art.get("occluders", []))
		if is_instance_valid(world.distribution):
			# Fade only structure between this local camera and pilot. Pipes,
			# physical backplates and ability targets keep their readable surfaces.
			for id in ["LeftWall", "RightWall", "BackWall", "RoofLeft", "RoofRight", "RoofBack", "RoofFront",
				"UpperDeckLeft", "UpperDeckRight", "UpperDeckBack", "UpperDeckFront", "UpperFrontApron"]:
				candidates.append(world.distribution.fixed_bodies[id])
			candidates.append(world.distribution.door)
		if is_instance_valid(world.shared_access):
			# Actual floor/rail/support meshes may hide a pilot below the crossing.
			# Fade their local material copies only; controls, handle and pin stay
			# readable, and every physical collision body remains in the world.
			var controls: Array = world.shared_access.target_bodies.values()
			for structure in world.shared_access.fixed_bodies.values() + world.shared_access.moving_bodies.values():
				if structure not in controls: candidates.append(structure)
		terrain_visibility.setup(camera, body, candidates)
		_terrain_view_key = key
	return terrain_visibility.update(delta)

func _clear_terrain_visibility() -> void:
	terrain_visibility.clear()
	_terrain_view_key = ""

func _exit_tree() -> void:
	_clear_terrain_visibility()
	_restore_presentation_world()

func _command_received(peer_id: int, command: Dictionary) -> void:
	if not network.is_authority() or not players.has(peer_id): return
	stats.inputs += 1
	players[peer_id].command = command if not simulation_paused else {"active":false, "brake":true}

func _action_received(peer_id: int, verb: String, payload: Dictionary) -> void:
	if not owns_world or not network.is_authority() or not players.has(peer_id): return
	if verb == "content_journal":
		content_journal.request(peer_id)
		return
	var pause_decision: bool = verb == "propose" and payload.get("kind") == "pause" or verb == "confirm" and consensus.current_proposal().get("kind") == "pause"
	var boundary_action: bool = verb in ["propose","confirm"] or thermal_cargo.supported() and verb in ["interact","campaign_operate","explore","revive"]
	if (canal != null or thermal_cargo.supported()) and not _canal_action_in_capture and boundary_action and not pause_decision:
		if environment_save_gate.pending():
			_note(peer_id,"正在保存现场，请稍候再确认。")
			return
		var captured_payload := payload.duplicate(true)
		environment_save_gate.request(func() -> bool:
			_canal_action_in_capture = true
			# A confirmation keeps the proposal's revision until its own atomic
			# decision commit. That commit captures this prepared physical frame;
			# a separate environment commit here would invalidate the proposal.
			var confirming: bool = verb == "confirm" and not consensus.current_proposal().is_empty()
			var saved := confirming or _save_environment()
			if saved: _action_received(peer_id,verb,captured_payload)
			_canal_action_in_capture = false
			return saved,
			func(result: Dictionary):
				if not result.ok: _note(peer_id,"现场保存未完成，决定尚未生效；可以重试："+str(result.code)))
		return
	stats.actions += 1
	if consensus.current_proposal().get("state") == "ready" and verb not in ["confirm", "cancel", "receipt_ack", "receipt_ack_batch"]: return
	if simulation_paused and verb not in ["propose", "confirm", "cancel", "receipt_ack", "receipt_ack_batch"]: return
	match verb:
		"thermal_cargo_operate": thermal_cargo.operate(peer_id,str(payload.get("target_id","")))
		"campaign_choice_open": chapter_choices.open(peer_id,str(payload.get("anchor","")))
		"campaign_choice_read": chapter_choices.read_option(peer_id,str(payload.get("target","")),str(payload.get("option","")))
		"campaign_operate": campaign.operate(peer_id,str(payload.get("target_id","")))
		"lock":
			var target = str(payload.get("target_id", ""))
			if entities.has(target) and target != _actor_id(peer_id) and players[peer_id].global_position.distance_to(entities[target].position) <= 55: locks[peer_id] = target
		"ability": _use_ability(peer_id, payload)
		"interact": _complete_gate(peer_id)
		"explore": story.interact(peer_id, payload)
		"boss_start": _note(peer_id, "修复两界支脉后，在北港检修联络台了解截停方案。")
		"retry":
			if pending_completion:
				_finish_boss()
				return
			if boss_active:
				if players.size() == 1:
					if campaign.active(): campaign.retry()
					elif crown.active(): crown.retry()
					else:
						encounter.reset_attempt("manual")
						_reset_players()
				else: _note(peer_id, "合作战斗请救援队友；全员停机会自动重试")
			else: _restore_player(peer_id, world.spawn_position)
		"revive": revive_time[peer_id] = {"target":int(payload.get("target", 0)), "held":0.0}
		"propose":
			var kind = str(payload.get("kind", ""))
			if kind == "region_change" and simulation_paused:
				_note(peer_id,"先共同恢复飞行，再确认跨区航路。")
				return
			if kind == "region_change" and pending_completion:
				_finish_boss()
				if pending_completion: return
			if not payload.get("payload", {}) is Dictionary: return
			var body: Dictionary = payload.get("payload", {})
			if kind == "campaign_choice":
				var prepared_choice: Dictionary = chapter_choices.prepare_proposal(peer_id,str(body.get("target","")),str(body.get("option","")))
				if not prepared_choice.get("ok",false):
					_note(peer_id,"先逐项阅读方案，并靠近确认台："+str(prepared_choice.get("code","not_ready")))
					return
				body = prepared_choice.payload
			if kind == "region_change" and not _can_travel_to(str(body.get("region_id", ""))):
				_note(peer_id, "先完成本区调查与战后决定，再确认下一航路。水城入口需先贯通检修廊。" if not Regions.required_action(region_id,str(body.get("region_id",""))).is_empty() else "航路尚未开放：跨界需恢复通航，水城入口需先贯通检修廊。")
				return
			if kind == "major_choice" and (body.get("value", "") not in ["city", "shared"] or not world.restored_gate):
				_note(peer_id, "先完成闸门修复，再决定供能方案。")
				return
			if kind == "facility_choice":
				if not consensus.current_proposal().is_empty(): return
				if not story.shared_choice_available():
					_note(peer_id, "先完成双窗试流调查，再确认本次通路安排。")
					return
				var confirmation: Dictionary = shared_access.choice_confirmation(peer_id, str(body.get("mode", "")))
				if not confirmation.ok:
					_note(peer_id, SharedAccessSession.confirmation_message(str(confirmation.code)))
					return
				if not _save_environment(): return
				body = {"mode":str(body.mode), "observer":peer_id}
			if kind == "region_change" and not _save_environment(): return
			if kind == "major_choice":
				if not consensus.current_proposal().is_empty(): return
				if not _save_environment(): return
				var branch = "before-choice-%d-%d" % [int(world_cache.generation), Time.get_ticks_usec()]
				var fork: Dictionary = store.fork_branch(branch, "供能选择之前", false)
				if not fork.get("ok", false):
					_note(peer_id, "选择前分支保存失败，尚未发起决定")
					return
				world_cache = store.snapshot()
				consensus.set_world_revision(int(world_cache.world_revision))
			var proposal = consensus.propose(kind, body, peer_id)
			if proposal.get("ok", false): _resolve_ready()
			else: _note(peer_id, str(proposal.get("error")))
		"confirm":
			var current: Dictionary = consensus.current_proposal()
			if current.get("kind") == "campaign_choice" and not chapter_choices.confirmation_valid(peer_id,current.payload):
				_note(peer_id,"请先靠近确认台，逐项阅读这次方案的收益与负担。")
				return
			var result = consensus.confirm(str(payload.get("proposal_id", "")), peer_id, int(payload.get("world_revision", -1)))
			if result.get("ok", false): _resolve_ready()
			else: _note(peer_id, "世界已变化或提案已取消，请重新发起")
		"cancel":
			consensus.resolve(str(payload.get("proposal_id", "")), false)
			_reconcile_canal_pause_request()
			_reconcile_thermal_pause_request()
		"receipt_ack": store.ack_guest_receipt(str(identities.get(peer_id, "")), str(payload.get("receipt_id", "")))
		"receipt_ack_batch":
			receipts.acknowledge(peer_id, payload)
			world_cache = store.snapshot()

func _use_ability(peer_id: int, payload: Dictionary) -> void:
	if float(cooldowns.get(peer_id, 0)) > 0:
		stats.rejected_abilities += 1
		_note(peer_id, "能力正在恢复，请稍候再试")
		return
	var ability = str(payload.get("ability", ""))
	var target = str(payload.get("target_id", locks.get(peer_id, "")))
	if canal != null and canal.owns_target(target):
		var used: Dictionary = canal.use_ability(peer_id,payload)
		if used.get("ok",false): _audio_event("ability",players[peer_id].global_position,str(peer_id))
		else: _note(peer_id,"南湾设备尚未接受操作："+str(used.get("code","not_ready")))
		return
	var actor = _actor_id(peer_id)
	var body: FlightBodyV2 = players[peer_id]
	entities[actor].position = body.global_position
	var intent = {"actor_id":actor, "ability":ability, "target_id":target, "mode":str(payload.get("mode", "")), "point":payload.get("point", body.global_position + Vector3(0, 0, -5))}
	if target.begins_with(CrownSession.HOST_PREFIX):
		crown.use_ability(peer_id, intent)
		return
	var los = _line_clear(body.global_position, entities.get(target, {}).get("position", body.global_position), body.get_rid(), target)
	var result: Dictionary = rules.resolve(intent, entities, {"sender_id":str(peer_id), "line_of_sight":los})
	if result.get("ok", false) and target.begins_with("boss:") and ability in ["charge", "takeover"]:
		var state = encounter.get_state()
		if target == "boss:core": result = {"ok":false, "code":"unsupported_target"}
		elif not boss_active or not state.get("nodes_open", false): result = {"ok":false, "code":"node_armored"}
	# Check the exact resolved angle patch before Rules atomically spends energy.
	# This batch only opts in F2 physical mirrors; F1's Z-rotor/G/F4 stay unchanged.
	if result.get("ok", false) and ability == "light" and target in ["F2:clock_mirror","F2:clock_mirror_bypass"]:
		for patch: Dictionary in result.get("patches", []):
			if str(patch.get("entity_id",""))!=target or not patch.get("changes",{}).has("angle"): continue
			last_light_rotation_clearance=LightRotationClearance.inspect(world,world.objects.get(target) as StaticBody3D,float(entities[target].get("angle",0.0)),float(patch.changes.angle))
			if not last_light_rotation_clearance.get("ok",false): result={"ok":false,"code":"physics_blocked"}
			break
	if result.get("ok", false):
		for request in result.get("physics_requests", []):
			if not _approve_physics(request, peer_id):
				result = {"ok":false, "code":"physics_blocked"}
				break
	if not result.get("ok", false):
		stats.rejected_abilities += 1
		_note(peer_id, ERROR_TEXT.get(str(result.get("code")), str(result.get("code"))))
		return
	var committed: Dictionary = rules.commit(result, entities, true)
	if not committed.get("ok", false):
		_note(peer_id, "物件已变化，请重试")
		return
	for request in committed.get("physics_requests", []): _execute_physics(request, peer_id)
	story_jobs.ability_applied(peer_id, intent)
	if target.begins_with("boss:") and ability in ["charge", "takeover"]:
		var powered = bool(entities[target].get("powered", false)) and not bool(entities[target].get("controlled", false))
		_handle_boss_events(encounter.set_node_power(target.trim_prefix("boss:"), powered, str(peer_id)).get("events", []))
	stats.abilities += 1
	if campaign.mechanisms != null: campaign.mechanisms.observe_ability(peer_id,target,ability)
	_audio_event("ability", body.global_position, str(peer_id))
	cooldowns[peer_id] = 0.35
	if entities.has(target): _beam(body.global_position, entities[target].position, Color("81d9c5"), 0.25)
	var ability_index = Interface.ABILITIES.find(ability)
	_note(peer_id, "已使用" + str(Interface.NAMES[ability_index] if ability_index >= 0 else ability))

func _approve_physics(request: Dictionary, peer_id: int) -> bool:
	var kind = str(request.get("type", ""))
	if kind == "impulse" and not facilities.impulse_owner(str(request.get("entity_id", ""))).is_empty():
		return bool(facilities.can_accept_impulse(request.entity_id, request.impulse, peer_id, int(entities[_actor_id(peer_id)].revision) + 1).ok)
	if kind == "impulse": return world.objects.get(request.entity_id) is RigidBody3D
	if kind not in ["blink", "spawn_decoy"]: return false
	var destination: Vector3 = request.to
	if not Regions.contains(region_id, destination): return false
	var body: FlightBodyV2 = players[peer_id]
	var query = PhysicsShapeQueryParameters3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(float(body.stats.width_m), float(body.stats.height_m), float(body.stats.length_m))
	query.shape = shape
	query.collision_mask = 1 | 2 | 8 | 32
	query.exclude = [body.get_rid()]
	query.transform = Transform3D(Basis.IDENTITY, destination)
	if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(): return false
	if kind == "spawn_decoy" and not _line_clear(body.global_position, destination, body.get_rid()): return false
	if kind == "blink":
		query.transform.origin = body.global_position
		query.motion = destination - body.global_position
		var fractions = get_world_3d().direct_space_state.cast_motion(query)
		if fractions.size() < 2 or fractions[0] < 0.999: return false
	return true

func _execute_physics(request: Dictionary, peer_id: int) -> void:
	match str(request.type):
		"blink":
			var from: Vector3 = players[peer_id].global_position
			story.last_blink[peer_id] = {"time":Time.get_ticks_msec(), "position":request.to}
			players[peer_id].global_position = request.to
			players[peer_id].linear_velocity = Vector3.ZERO
			players[peer_id].hold_height = request.to.y
			entities[_actor_id(peer_id)].position = request.to
			story.note_underdeck_blink(peer_id, from, request.to)
		"impulse":
			if not facilities.impulse_owner(str(request.entity_id)).is_empty():
				var result: Dictionary = facilities.apply_authorized_impulse(request.entity_id, request.impulse, peer_id, int(entities[_actor_id(peer_id)].revision))
				if not result.ok: push_error("Approved facility impulse was not committed: " + str(result.code))
			else: world.objects[request.entity_id].apply_central_impulse(request.impulse)
		"spawn_decoy":
			_ring(request.to, 0.8, 6.0)
			_beam(request.to, request.to + Vector3.UP * 1.5, Color("81d9e2"), 6.0)

func _line_clear(from: Vector3, to: Vector3, exclude: RID, target_id = "", boss_origin = false) -> bool:
	var query = PhysicsRayQueryParameters3D.create(from, to, 1 | 4 | 8)
	query.exclude = [exclude]
	if boss_origin:
		var excluded: Array[RID] = [exclude]
		for part in world.boss_collision_bodies(): excluded.append(part.get_rid())
		query.exclude = excluded
	var hit = get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or (not target_id.is_empty() and str(hit.collider.get_meta("entity_id", "")) == target_id)

func _fire(peer_id: int, damage: float = 9.0) -> bool:
	if not network.is_authority(): return false
	if not weapons.is_burst(peer_id):
		if float(weapon_cooldowns.get(peer_id, 0)) > 0: return false
		weapon_cooldowns[peer_id] = 0.23
	if ambient_patrol.owns_target(str(locks.get(peer_id,""))):
		return ambient_patrol.fire_player(peer_id,damage)
	if combat_sites.owns_target(str(locks.get(peer_id,""))):
		return combat_sites.fire_player(peer_id,damage)
	if campaign.active():
		# Only internal Host real damage is converted; Encounter keeps its milli gate.
		if not is_finite(damage) or damage < 0.001 or damage > 50.0: return false
		return campaign.fire(peer_id, int(round(damage * 1000.0)))
	if crown.active():
		return crown.fire(peer_id, damage)
	var target = str(locks.get(peer_id, ""))
	if not boss_active or not target.begins_with("boss:") or not entities.has(target):
		_shot_rejected(peer_id, "target_missing", "Tab 锁定敌方部件，再按 J / 左键射击。")
		return false
	var body: FlightBodyV2 = players[peer_id]
	var point: Vector3 = entities[target].position
	if body.global_position.distance_to(point) > 36:
		_shot_rejected(peer_id, "out_of_range", "射程 36m，请靠近锁定部件。")
		return false
	if not _line_clear(body.global_position, point, body.get_rid(), target):
		_shot_rejected(peer_id, "occluded", "射线被挡住，换高度或绕到部件一侧。")
		return false
	stats.shots += 1
	_audio_event("shot", body.global_position, str(peer_id))
	_beam(body.global_position, point, Color("f4d497"))
	var hit = encounter.hit_part(target.trim_prefix("boss:"), damage, str(peer_id))
	if hit.get("ok", false):
		_audio_event("hit", point, target)
		_handle_boss_events(hit.events)
	else: _shot_rejected(peer_id, str(hit.get("code")), ERROR_TEXT.get(str(hit.get("code")), "装甲挡住了攻击，等待接口开启。"))
	return bool(hit.get("ok", false))

func _shot_rejected(peer_id: int, code: String, text: String) -> bool:
	# Host-local feedback throttling only; no damage or ability decision depends on it.
	var now = Time.get_ticks_msec()
	var previous: Dictionary = shot_notices.get(peer_id, {})
	if not previous.is_empty() and now - int(previous.time) < (2200 if str(previous.code) == code else 900): return false
	shot_notices[peer_id] = {"code":code, "time":now}
	_note(peer_id, text)
	return true

func _start_boss(campaign = false) -> void:
	if boss_active or pending_completion: return
	if region_id not in ["I1", "F1"]: return
	if region_id == "F1":
		crown.start(campaign)
		return
	boss_campaign = campaign and region_id == "I1" and "I1:whale:brief" in story.state.get("completed", [])
	arena_checkpoint = {}
	for id in world.objects: arena_checkpoint[id] = entities[id].duplicate(true)
	var roster: Dictionary = {}
	for peer_id in players:
		roster[str(peer_id)] = {"position":players[peer_id].global_position, "max_health":players[peer_id].maximum_health, "health":players[peer_id].health}
	encounter.start({"players":roster})
	boss_active = true
	_sync_boss_entities()
	_telegraph("low_sweep", 2.0)
	_note_all("首领已启动：攻击后供能舱会开启；拆除或接管两侧后攻击核心。")

func _sync_boss_entities() -> void:
	if not boss_active: return
	if crown.active():
		crown.sync_view()
		return
	var state = encounter.get_state()
	world.set_boss_state(state)
	for part in world.boss_parts:
		var id = "boss:" + str(part)
		if not entities.has(id):
			entities[id] = {"id":id, "name":"抽能机 · " + str(part), "tags":["enemy", "mechanical", "hackable", "conductive", "electrical"], "revision":0, "owner":"enemy", "charge":100.0, "powered":true}
		entities[id].position = world.boss_parts[part].global_position
		if part != "core":
			var powered = bool(state.nodes[part].powered)
			if powered and not bool(entities[id].get("powered", false)):
				entities[id].charge = 100.0
				entities[id].owner = "enemy"
				entities[id].controlled = false
				entities[id].takeover_remaining = 0.0
				entities[id].revision += 1
			entities[id].powered = powered

func _handle_boss_events(events: Array) -> void:
	for event in events:
		match str(event.get("type", "")):
			"telegraph_started": _telegraph(str(event.attack), float(event.duration))
			"attack": _boss_attack(str(event.attack))
			"attempt_reset":
				_reset_players()
				_note_all("小队全员停机：首领整场已重置，已有成果保留。")
			"phase_changed": _audio_event("boss_phase", world.boss_position, "whale")
			"core_exposed": _note_all("核心暴露！切换锁定到核心。")
			"boss_defeated":
				pending_completion = true
				_finish_boss()

func _finish_boss() -> void:
	if not pending_completion: return
	if campaign.supported():
		campaign.commit_victory()
		return
	if region_id == "F1":
		var crown_changes = {"world.flags.F1_boss":true}
		if boss_campaign: crown_changes["world.flags.campaign_crown_v1"] = true
		if _commit("boss:F1:parasitic_crown" + (":opening_v1" if boss_campaign else ""), crown_changes, "boss:F1:parasitic_crown"):
			_audio_event("boss_defeated", world.boss_position, "crown")
			pending_completion = false
			boss_active = false
			world.set_boss_state({}, story.crown_victory_committed())
			crown.apply_entities({})
			revive_time.clear()
			var roster: Array = players.keys()
			roster.sort()
			for slot in range(roster.size()):
				var peer = int(roster[slot])
				if not players[peer].enabled:
					_restore_player(peer, world.crown_arena.retry_position(slot))
					players[peer].health = players[peer].maximum_health * 0.4
					players[peer].damage_state.health = players[peer].health
					entities[_actor_id(peer)].health = players[peer].health
			for peer in locks:
				if str(locks[peer]).begins_with(CrownSession.HOST_PREFIX) or locks[peer] == CrownSession.CORE: locks[peer] = ""
			_note_all("冠兽已脱离支脉，胜利已保存。靠近西侧宿主的琥珀结，按 G 核对恢复后的读数。" if boss_campaign else "冠兽开发机制检查已保存；不计入主线。")
		return
	var changes = {"world.flags." + region_id + "_boss":true}
	var receipt = "boss:" + region_id + ":harbor_whale"
	if boss_campaign:
		changes["world.flags.campaign_whale_v1"] = true
		receipt += ":opening_v1"
	if _commit(receipt, changes, "boss:" + region_id + ":harbor_whale"):
		_audio_event("boss_defeated", world.boss_position, "whale")
		pending_completion = false
		boss_active = false
		_boss_target_positions.clear()
		world.show_boss_warning("", {}, 0.0)
		world.set_boss_state({}, story.whale_victory_committed())
		for part in ["core", "port", "starboard"]: entities.erase("boss:" + part)
		for peer in locks:
			if str(locks[peer]).begins_with("boss:"): locks[peer] = ""
		_note_all("鲸机已停机，胜利已保存。靠近核心侧的记录匣，提取原始指令。" if boss_campaign else "开发机制检查已保存；不计入主线鲸机战。")

func _telegraph(attack: String, seconds: float) -> void:
	_audio_event("boss_warning", world.boss_position, attack)
	_boss_target_positions.clear()
	var definition: Dictionary = BossAttacks.definition(attack)
	if definition.is_empty(): return
	for peer_id in players:
		if not players[peer_id].enabled or players[peer_id].global_position.distance_to(world.boss_position) > float(definition.range): continue
		var entity: Dictionary = entities[_actor_id(peer_id)]
		var target: Vector3 = entity.get("decoy_position", entity.position) if float(entity.get("decoy_remaining", 0)) > 0 else entity.position
		_boss_target_positions[peer_id] = target
	world.show_boss_warning(attack, _boss_target_positions, seconds)
	_note_all(str(definition.message))

func _update_boss_warning() -> void:
	var state: Dictionary = encounter.get_state()
	if not boss_active or state.get("attack_state", "") != "windup" or state.get("completed", false):
		world.show_boss_warning("", {}, 0.0)
		return
	world.show_boss_warning(str(state.telegraph), _boss_target_positions, float(state.attack_remaining))

func _boss_attack(attack: String) -> void:
	var definition: Dictionary = BossAttacks.definition(attack)
	if definition.is_empty(): return
	_audio_event("boss_attack", world.boss_attack_origin(), attack)
	for peer_id in players:
		var body: FlightBodyV2 = players[peer_id]
		# A pilot who joins during a windup has not seen a locked mark yet.
		if not body.enabled or not _boss_target_positions.has(peer_id) or body.global_position.distance_to(world.boss_position) > float(definition.range): continue
		var origin = world.boss_attack_origin()
		if not _line_clear(origin, body.global_position, body.get_rid(), "", true): continue
		var target: Vector3 = _boss_target_positions[peer_id]
		var hit = BossAttacks.contains(attack, body.global_position, target)
		if bool(definition.brake_immune) and body.command.get("brake", false): hit = false
		if attack == "tractor" and hit: body.apply_central_impulse((world.boss_position - body.global_position).normalized() * 12)
		_beam(origin, target, Color("ed8569"), 0.3)
		if hit: body.apply_combat_hit(BossAttacks.damage_for(attack), (body.global_position - origin).normalized(), body.global_position, "pulse", {"source":"whale"})

func _pilot_disabled(peer_id: int) -> void:
	if not network.is_authority(): return
	weapons.cancel(peer_id,"disabled")
	if campaign.active(): campaign.player_disabled()
	elif crown.active():
		crown.down(peer_id)
	elif boss_active:
		_handle_boss_events(encounter.down_player(str(peer_id)).get("events", []))
	else:
		call_deferred("_restore_player", peer_id, world.spawn_position)

func _reset_players() -> void:
	world.reset_physics()
	for id in arena_checkpoint: entities[id] = arena_checkpoint[id].duplicate(true)
	revive_time.clear()
	cooldowns.clear()
	weapon_cooldowns.clear()
	var roster: Array = players.keys()
	roster.sort()
	for slot in range(roster.size()): _restore_player(int(roster[slot]), world.boss_retry_position(slot))
	for part in ["port", "starboard", "core"]: entities.erase("boss:" + part)
	_sync_boss_entities()
	_telegraph("low_sweep", 2.0)

func _restore_player(peer_id: int, at: Vector3) -> void:
	if not players.has(peer_id): return
	# The original same-body configure retains heat. Retain the overheat recovery
	# latch and single burst clock too; only transient charge is cancelled.
	weapons.cancel(peer_id,"restored")
	story.reset_underdeck_tracking(peer_id)
	cooldowns.erase(peer_id)
	weapon_cooldowns.erase(peer_id)
	shot_notices.erase(peer_id)
	var body: FlightBodyV2 = players[peer_id]
	var was_disabled: bool = not body.enabled or body.health<=0.0
	body.configure(CatalogV2.resolve_build(body.build))
	body.enabled = true
	body.freeze = simulation_paused or thermal_cargo.remote_loaded_actor(body) or (not network.is_authority() and (peer_id != network.local_id() or not _facilities_ready()))
	body.set_process(not simulation_paused)
	body.global_position = at
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.hold_height = at.y
	body.crash_seconds = 0
	body.crash_reported = false
	_register_player_entity(peer_id)
	if was_disabled: _audio_owner_vital(peer_id,"revived")

func _update_revives(delta: float) -> void:
	for peer_id in revive_time.keys():
		var progress: Dictionary = revive_time[peer_id]
		var target = int(progress.target)
		if not players.has(peer_id) or not players.has(target) or not players[peer_id].enabled or players[target].enabled or players[peer_id].position.distance_to(players[target].position) > 3:
			revive_time.erase(peer_id)
			continue
		progress.held += delta
		if float(progress.held) >= 2.5:
			if campaign.active():
				_restore_player(target,players[target].global_position)
				players[target].health = players[target].maximum_health*.4
				players[target].damage_state.health = players[target].health
				revive_time.erase(peer_id)
				continue
			if crown.active():
				crown.revive(int(peer_id), target, float(progress.held))
				revive_time.erase(peer_id)
				continue
			var result = encounter.revive_player(str(peer_id), str(target), float(progress.held))
			if result.get("ok", false):
				_restore_player(target, players[target].global_position)
				players[target].health = players[target].maximum_health * 0.4
				players[target].damage_state.health = players[target].health
			revive_time.erase(peer_id)

func _complete_gate(peer_id: int) -> void:
	if not world.objects.has(region_id + ":beacon"): return
	if not world.gate_open:
		_note(peer_id, "先让继电器供能、开启热旁路，或接管信标。")
		return
	if players[peer_id].position.distance_to(world.objects[region_id + ":beacon"].position) > 7:
		_note(peer_id, "闸门已打开，请靠近跨界信标提交修复。")
		return
	if _commit("gate:" + region_id, {"world.flags." + region_id + "_gate":true}, "gate:" + region_id):
		world.restored_gate = true
		_note_all("通航恢复已保存。可以提出跨界，也可以继续探索。")

func _can_travel_to(destination: String) -> bool:
	if not Regions.can_travel(region_id, destination): return false
	var required: String = Regions.required_action(region_id,destination)
	if not required.is_empty(): return required in story.state.get("completed_actions", [])
	if region_id == "I2": return destination == "I1"
	if destination == "I2": return "I1:underdeck" in story.state.get("completed_actions", [])
	return world.restored_gate

func _commit(receipt: String, changes: Dictionary, discovery = "") -> bool:
	if not profile_ready or not owns_world: return false
	var canal_saved: Dictionary = _canal_persistence()
	if not canal_saved.ok: return false
	var cargo_saved: Dictionary = thermal_cargo.capture()
	if not cargo_saved.get("ok",false): return false
	# World replays are branch/revision scoped; personal receipts remain stable.
	var tx = {"id":"%s:%s:%d" % [receipt, str(world_cache.world.branch_id), int(world_cache.generation)], "set":changes}
	if ecology.ready: tx.set["world.ecology"] = ecology.persistent_state()
	tx.set.merge(facilities.persistent_states(), false)
	tx.set.merge(campaign.persistent_states(), false)
	tx.set.merge(chapter_choices.persistent_states(), false)
	if canal_saved.has("envelope"):
		# Only the current authority-validated physical envelope may be saved.
		# A caller cannot replace it through an unrelated changes dictionary.
		tx.set["world.environment.I2_canal"] = canal_saved.envelope
	if cargo_saved.has("state"): tx.set[ThermalParticipant.PATH] = cargo_saved.state
	if is_instance_valid(world) and not tx.set.has("world.entities." + region_id): tx.set["world.entities." + region_id] = _persistent_environment()
	if not discovery.is_empty():
		tx["append"] = {"personal.discoveries":[discovery]}
		tx["guest_rewards"] = []
		for id in network.guests:
			tx.guest_rewards.append({"guest_id":identities[id], "reward_id":discovery, "payload":{"discoveries":[discovery]}})
	var qa_store_begin_usec := 0
	var qa_store_frame := 0
	var qa_store_generation := 0
	if qa_cpu_enabled:
		qa_store_frame = Engine.get_physics_frames()
		qa_store_generation = int(store._data.generation) # Scalar read; no snapshot/payload copy.
		store.qa_phase_enabled = true
		qa_store_begin_usec = Time.get_ticks_usec()
	var result: Dictionary = store.commit(tx)
	if qa_store_begin_usec != 0:
		var qa_store_end_usec := Time.get_ticks_usec()
		store.qa_phase_enabled = false
		if qa_store_commit_wall.size()>=8: qa_store_commit_wall.pop_front()
		qa_store_commit_wall.append({"begin_usec":qa_store_begin_usec,"end_usec":qa_store_end_usec,
			"wall_usec":qa_store_end_usec-qa_store_begin_usec,"physics_frame":qa_store_frame,"receipt":receipt,
			"generation_before":qa_store_generation,"generation_after":int(result.get("generation",-1)),
			"ok":bool(result.get("ok",false)),"error":str(result.get("error","")),
			"store_phases":store.qa_last_phases.duplicate(true)}) # One scalar-result copy AFTER outer end.
	last_commit_result = {"ok":result.get("ok",false),"error":str(result.get("error","")),"receipt":receipt}
	if not result.get("ok", false):
		if result.get("error") == "SAVE_INVALID_TRANSACTION": last_commit_result["invalid_paths"] = _invalid_persistent_paths(tx)
		_note_all("保存失败，尚未提交成果：" + str(result.get("error")))
		return false
	world_cache = store.snapshot()
	if not _resolving_decision: consensus.set_world_revision(int(world_cache.world_revision))
	return true

## Diagnostic only. Keep an exact offending field/type when the original Store
## rejects a transaction; do not coerce or discard it to make a save succeed.
func _invalid_persistent_paths(value: Variant, path: String = "transaction", depth: int = 0) -> Array:
	if store._tree_valid(value,depth): return []
	if depth > 28: return [{"path":path,"reason":"depth"}]
	var result: Array = []
	if value is Dictionary:
		for key in value:
			if not key is String or key.is_empty() or key.length()>256: result.append({"path":path,"reason":"dictionary_key","key":str(key),"type":type_string(typeof(key))})
			else: result.append_array(_invalid_persistent_paths(value[key],path+"."+str(key),depth+1))
	elif value is Array:
		for index in value.size(): result.append_array(_invalid_persistent_paths(value[index],path+"[%d]"%index,depth+1))
	else: result.append({"path":path,"reason":"value","type":type_string(typeof(value)),"value":str(value)})
	return result

func _save_environment() -> bool:
	if not profile_ready or not owns_world or not active or not network.is_authority() or not is_instance_valid(world): return true
	if pending_completion: return false
	if not facilities.pending_retry(): return false
	if not consensus.current_proposal().is_empty(): return false
	var canal_saved: Dictionary = _canal_persistence()
	if not canal_saved.ok: return false
	var cargo_saved: Dictionary = thermal_cargo.capture()
	if not cargo_saved.get("ok",false): return false
	var persistent = _persistent_environment()
	var current: Dictionary = world_cache.world.get("entities", {}).get(region_id, {})
	var changed: bool = not store.matches_persisted_value(persistent, current) or not store.matches_persisted_value(ecology.persistent_state(), world_cache.world.get("ecology", {}))
	var facility_states: Dictionary = facilities.persistent_states()
	facility_states.merge(campaign.persistent_states(), false)
	facility_states.merge(chapter_choices.persistent_states(), false)
	if canal_saved.has("envelope"):
		facility_states["world.environment.I2_canal"] = canal_saved.envelope
	if cargo_saved.has("state"): facility_states[ThermalParticipant.PATH] = cargo_saved.state
	for path in facility_states:
		if not store.matches_persisted_value(facility_states[path], world_cache.world.get("environment", {}).get(str(path).trim_prefix("world.environment."), {})): changed = true
	if changed:
		return _commit("environment", {"world.entities." + region_id:persistent})
	return true

## Acceptance is asynchronous. Completion reports the actual Store result;
## callers must not leave the world on acceptance alone. The gate is advanced
## after ordinary Canal physics, never by capture or a second simulation tick.
func request_environment_save(completion: Callable = Callable()) -> Dictionary:
	return environment_save_gate.request(_save_environment, completion)

## Window/menu callbacks only request a save. Run lifecycle changes at the
## same physical boundary as their successful original Store transaction.
func _capture_before_lifecycle(action: Callable) -> bool:
	if not owns_world or not active or _canal_action_in_capture: return false
	if not consensus.current_proposal().is_empty():
		_note_all("请先确认或暂缓当前共同决定，再保存退出或切换会话。")
		return true
	if _lifecycle_action.is_valid():
		_note_all("正在保存现场，完成后继续刚才的操作。")
		return true
	_lifecycle_action = action
	if environment_save_gate.pending():
		_lifecycle_waiting_for_save = true
		_note_all("正在保存现场，完成后继续刚才的操作。")
		return true
	environment_save_gate.request(_save_environment,
		func(result: Dictionary):
			var continuation := _lifecycle_action
			_lifecycle_action = Callable()
			_lifecycle_waiting_for_save = false
			if not result.ok:
				_note_all("现场保存未完成，原会话保持；可以重试："+str(result.code))
				return
			# The gate releases the original capture BEFORE this continuation.
			# No freed world/adapter may be used by a trailing release operation.
			_canal_action_in_capture = true
			if continuation.is_valid(): continuation.call()
			_canal_action_in_capture = false)
	return true

func _advance_environment_save() -> Dictionary:
	var was_pending := environment_save_gate.pending()
	var result: Dictionary = environment_save_gate.advance()
	if was_pending and not environment_save_gate.pending() and _lifecycle_waiting_for_save:
		var continuation := _lifecycle_action
		_lifecycle_action = Callable()
		_lifecycle_waiting_for_save = false
		if result.get("ok",false) and continuation.is_valid():
			_capture_before_lifecycle(continuation)
		else: _note_all("现场保存未完成，原会话保持；可以重试："+str(result.get("code","save_failed")))
	return result

## A cold-cassette proof may become ready during an active scan. Capture and
## recheck it at the ordinary save boundary, then publish through Story's same
## transaction; neither the query nor this queue advances physical time.
func request_canal_exchange_fact(option: String) -> void:
	if canal == null or environment_save_gate.pending(): return
	var adapter: RefCounted = canal
	environment_save_gate.request(func() -> bool:
		if canal != adapter or not story._can_advance() or story._fact("I2:canal_exchange_verified") != option: return false
		return story._submit("fact","I2:canal_exchange_verified",option))

func _canal_persistence() -> Dictionary:
	if canal == null: return {"ok":true}
	if not active or not network.is_authority(): return {"ok":false,"code":"canal_authority_required"}
	var captured: Dictionary = canal.capture_persistent_state()
	if not captured.get("ok",false) or captured.get("path","") != "world.environment.I2_canal" or not captured.get("envelope") is Dictionary or captured.envelope.is_empty():
		_note_all("运河现场尚未形成可恢复的保存状态，原档保留："+str(captured.get("code","invalid_canal_envelope")))
		return {"ok":false,"code":str(captured.get("code","invalid_canal_envelope"))}
	return captured

func _persistent_environment() -> Dictionary:
	var persistent: Dictionary = {}
	for id in world.objects:
		# Charge/temperature alone cannot restore cargo custody or a work order.
		# The optional Canal participant owns these fields in its full envelope.
		if canal != null and canal.owns_target(str(id)): continue
		if thermal_cargo.owns_target(str(id)) and id == ThermalParticipant.Cargo.CARGO: continue
		persistent[id] = {}
		for key in ["charge", "temperature", "growth", "powered", "angle"]:
			if entities[id].has(key): persistent[id][key] = entities[id][key]
		if "sustained_light_source" in entities[id].get("tags", []): persistent[id]["light_level"] = float(entities[id].get("light_level", 0.0))
		if campaign.supported() and not str(id).begins_with("campaign:") and (region_id != "I2" or str(id).begins_with("I2:guardian_")):
			var p: Vector3 = world.objects[id].global_position
			persistent[id]["position"] = [p.x,p.y,p.z]
	# Transient ownership, force fields and player positions are not permanent saves.
	return persistent

func _resolve_ready() -> void:
	var proposal = consensus.current_proposal()
	if proposal.is_empty() or proposal.get("state") != "ready": return
	var kind = str(proposal.kind)
	var payload: Dictionary = proposal.payload
	var success = false
	_resolving_decision = true
	if kind != "pause" and not facilities.pending_retry():
		_resolving_decision = false
		return
	if kind == "major_choice":
		success = _commit("choice:" + str(proposal.proposal_id), {"world.choices.supply":str(payload.value)})
	elif kind == "campaign_choice":
		success = chapter_choices.commit_ready(proposal)
	elif kind == "facility_choice":
		var confirmation: Dictionary = shared_access.choice_confirmation(int(payload.get("observer", 0)), str(payload.get("mode", "")))
		if not confirmation.ok:
			_resolving_decision = false
			_note_all(SharedAccessSession.confirmation_message(str(confirmation.code)) + " 如需操作机关，可先选择“暂缓，继续探索”。")
			return
		success = story.commit_shared_choice(str(proposal.proposal_id), str(payload.get("mode", "")))
	elif kind == "region_change":
		var prepared := _prepare_region(str(payload.region_id))
		if not prepared.ok:
			_resolving_decision = false
			_note_all("目的地区资料无法读取，当前地区与存档保持不变；修复后可重试或取消：" + str(prepared.error))
			return
		if pending_completion:
			_finish_boss()
			if pending_completion:
				_discard_prepared_region(prepared)
				_resolving_decision = false
				return
		var changes := {"world.region_id":str(payload.region_id)}
		changes.merge(prepared.facilities.states)
		success = _commit("travel:" + str(proposal.proposal_id), changes)
		if success:
			if not _adopt_prepared_region(prepared):
				_resolving_decision = false
				return
			flight_camera.snap(players[1].position,players[1].heading)
		else: _discard_prepared_region(prepared)
	elif kind == "pause":
		if thermal_cargo.supported() and not simulation_paused:
			_thermal_pause_proposal = str(proposal.proposal_id)
			var cargo_requested: Dictionary = thermal_cargo.request_pause()
			last_pause_result = cargo_requested.duplicate(true)
			if not cargo_requested.get("ok",false) or not cargo_requested.get("ready",false):
				_resolving_decision = false
				return
		if canal != null and not simulation_paused:
			_canal_pause_proposal = str(proposal.proposal_id)
			var requested: Dictionary = canal.request_pause()
			last_pause_result = requested.duplicate(true)
			if not requested.get("ok",false):
				_resolving_decision = false
				_note_all("暂停尚未生效，可重试或暂缓："+str(requested.get("code","failed")))
				return
			if not requested.get("ready",false):
				_resolving_decision = false
				return # Original proposal remains ready until the actual boundary.
		simulation_paused = not simulation_paused
		success = _apply_pause_state()
		if success:
			_canal_pause_proposal = ""
			_thermal_pause_proposal = ""
	_resolving_decision = false
	if success:
		consensus.resolve(str(proposal.proposal_id), true)
		world_cache = store.snapshot()
		consensus.set_world_revision(int(world_cache.world_revision))
		interface.set_branches(store.list_branches())
	else: _note_all("保存未成功，决定尚未生效；修复后点击确认重试，或暂缓取消。")

func _reconcile_canal_pause_request() -> void:
	if _canal_pause_proposal.is_empty(): return
	var proposal: Dictionary = consensus.current_proposal()
	if proposal.get("proposal_id") == _canal_pause_proposal and proposal.get("kind") == "pause" and proposal.get("state") == "ready": return
	if canal != null:
		if not simulation_paused and canal.status().physics_paused: canal.set_paused(false)
		else: canal.cancel_pause_request()
	_canal_pause_proposal = ""

func _finish_canal_pause_request() -> void:
	if _canal_pause_proposal.is_empty() or canal == null: return
	_reconcile_canal_pause_request()
	if _canal_pause_proposal.is_empty(): return
	var result: Dictionary = canal.pause_request_status()
	last_pause_result = result.duplicate(true)
	if result.get("ok",false) and result.get("ready",false): _resolve_ready()
	elif not result.get("ok",false):
		_note_all("暂停尚未生效，可重试或暂缓："+str(result.get("code","failed")))
		_canal_pause_proposal = ""

func _reconcile_thermal_pause_request() -> void:
	if _thermal_pause_proposal.is_empty(): return
	var proposal: Dictionary = consensus.current_proposal()
	if proposal.get("proposal_id") == _thermal_pause_proposal and proposal.get("kind") == "pause" and proposal.get("state") == "ready": return
	thermal_cargo.set_paused(false)
	_thermal_pause_proposal = ""

func _finish_thermal_pause_request() -> void:
	if _thermal_pause_proposal.is_empty() or not thermal_cargo.supported(): return
	_reconcile_thermal_pause_request()
	if _thermal_pause_proposal.is_empty(): return
	var status: Dictionary = thermal_cargo.pause_status()
	last_pause_result = status.duplicate(true)
	if status.get("ok",false) and status.get("ready",false): _resolve_ready()
	elif not status.get("ok",false):
		_note_all("吊载暂停尚未生效，请保持制动后重试或暂缓。")
		_thermal_pause_proposal = ""

func _guest_joined(peer_id: int, identity: String, airframe = "tr01") -> void:
	network._lan_trace("guest_join_callback_begin")
	if thermal_cargo.defer_rejoin(peer_id,identity,str(airframe)): return
	stats.guest_joins += 1
	var arrival: Vector3 = world.boss_retry_position(1) if boss_active else world.spawn_position + Vector3(3, 0, 0)
	_spawn_player(peer_id, identity, arrival, airframe)
	consensus.configure(players.keys(), int(world_cache.world_revision))
	if boss_active and region_id == "I1":
		_handle_boss_events(encounter.add_player(str(peer_id), {"position":arrival, "max_health":players[peer_id].maximum_health}).get("events", []))
	for flag in world_cache.world.flags:
		var reward = ""
		if flag.ends_with("_gate") and world_cache.world.flags[flag]: reward = "gate:" + str(flag).trim_suffix("_gate")
		if flag == "I1_boss" and world_cache.world.flags[flag]: reward = "boss:I1:harbor_whale"
		if flag == "F1_boss" and world_cache.world.flags[flag] and world_cache.world.flags.get("campaign_crown_v1", false): reward = "boss:F1:parasitic_crown"
		if not reward.is_empty(): _queue_receipt_catchup(identity, reward)
	for discovery in story.state.get("discoveries", []):
		_queue_receipt_catchup(identity, str(discovery))
	for id in story.found_notes:
		_queue_receipt_catchup(identity, str(story.markers[id].discovery_id))
	for reward in sidejobs.completed_rewards(): _queue_receipt_catchup(identity,str(reward))
	for reward in field_requests.completed_rewards(): _queue_receipt_catchup(identity,str(reward))
	for reward in story_jobs.completed_rewards(): _queue_receipt_catchup(identity,str(reward))
	for reward in combat_sites.completed_rewards(): _queue_receipt_catchup(identity,str(reward))
	_retry_receipt_catchup()
	receipts.send_pending(peer_id)
	story.publish(peer_id)
	sidejobs.forget_peer(peer_id)
	field_requests.forget_peer(peer_id)
	story_jobs.forget_peer(peer_id)
	sidejobs.publish(peer_id)
	combat_sites.publish(peer_id)
	ecology.publish(peer_id)
	facilities.publish(peer_id)
	campaign.publish(peer_id)
	_publish_canal(peer_id)
	_note_all("队友已加入：同一区域可自由分头，跨界和剧情选择共同确认。")
	network._lan_trace("guest_join_callback_complete")

func _queue_receipt_catchup(identity: String, reward: String) -> void:
	if not receipt_catchup.has(identity): receipt_catchup[identity] = []
	if reward not in receipt_catchup[identity]: receipt_catchup[identity].append(reward)

func _retry_receipt_catchup() -> void:
	if not owns_world or not network.is_authority(): return
	for identity in receipt_catchup.keys():
		for reward in receipt_catchup[identity].duplicate():
			var result: Dictionary = store.queue_guest_receipt(str(identity), str(reward), {"discoveries":[str(reward)]})
			if not result.get("ok", false): return
			receipt_catchup[identity].erase(reward)
			world_cache = store.snapshot()
		if receipt_catchup[identity].is_empty(): receipt_catchup.erase(identity)

func _guest_left(peer_id: int) -> void:
	weapons.forget(peer_id)
	field_requests.forget_peer(peer_id)
	story_jobs.forget_peer(peer_id)
	stats.guest_leaves += 1
	consensus.participant_disconnected(peer_id)
	if thermal_cargo.begin_disconnect(peer_id): return
	_finish_guest_departure(peer_id)

func _finish_guest_departure(peer_id: int, retained_for_cargo: bool = false) -> void:
	if players.has(peer_id) and not retained_for_cargo: players[peer_id].queue_free()
	players.erase(peer_id)
	cooldowns.erase(peer_id)
	weapon_cooldowns.erase(peer_id)
	_boss_target_positions.erase(peer_id)
	entities.erase(_actor_id(peer_id))
	locks.erase(peer_id)
	identities.erase(peer_id)
	facilities.sync_roster()
	thermal_cargo.sync_roster()
	for id in entities:
		if str(entities[id].get("owner", "")) == str(peer_id) and not id.begins_with("player:"):
			entities[id].owner = entities[id].get("return_owner", "neutral")
			entities[id].controlled = false
			entities[id].takeover_remaining = 0.0
	if crown.active():
		crown.leave(peer_id)
	elif boss_active and not campaign.supported():
		_handle_boss_events(encounter.remove_player(str(peer_id)).get("events", []))
		_update_boss_warning()
	_note_all("队友断线，未确认的共同选择已取消。")

func _snapshot() -> Dictionary:
	packet_sequence += 1
	var roster: Dictionary = {}
	for id in players:
		var body: FlightBodyV2 = players[id]
		roster[id] = {"position":body.global_position, "velocity":body.linear_velocity, "heading":body.heading, "health":body.health, "enabled":body.enabled, "identity":identities[id], "airframe":body.build.airframe_id,"build":BuildContract.view(body.build)}
	var entity_states: Dictionary = {}
	for id in entities:
		if str(id).begins_with(CrownSession.HOST_PREFIX) or id == CrownSession.CORE: continue
		if combat_sites.owns_projection(str(id)): continue
		var state: Dictionary = entities[id].duplicate(true)
		# Definitions already exist locally; only changing authority state is sent.
		for key in ["id", "name", "tags", "abilities", "payload_hashes", "received_hashes", "rated_w", "current_limit_w", "actual_draw_w", "cargo_phase"]: state.erase(key)
		if str(id).begins_with("player:"):
			for key in ["position", "health", "downed", "owner", "max_energy", "revision"]: state.erase(key)
		entity_states[id] = state
	var boss_view: Dictionary = {} if campaign.supported() else (crown.presentation() if crown.active() else (encounter.get_state() if boss_active else {}))
	# Player pose/health already travel in roster; encounter bookkeeping remains
	# host-only. The guest needs only the render, telegraph and HUD state.
	for key in ["players", "boss_id", "reset_reason", "attack_index"]: boss_view.erase(key)
	var packet: Dictionary = {"session_id":network.session_id, "sequence":packet_sequence, "region":region_id, "players":roster, "entities":entity_states, "mechanisms":world.mechanism_snapshot(), "ecology_serial":ecology.serial, "ecology_epoch":ecology.epoch, "locks":locks.duplicate(), "vote":consensus.current_proposal(), "boss":boss_view, "boss_marks":_boss_target_positions.duplicate() if boss_active and region_id == "I1" else {}, "boss_defeated":world.crown_defeated if region_id == "F1" else world.whale_defeated, "paused":simulation_paused, "gate_saved":world.restored_gate, "story_serial":story.serial}
	packet["facility_refs"] = facilities.wire_refs()
	packet["campaign_epoch"] = campaign.epoch if campaign.supported() else 0
	packet["canal_epoch"] = _canal_epoch if canal != null else 0
	packet["thermal_cargo"] = thermal_cargo.presentation()
	packet["ambient"] = ambient_patrol.presentation()
	return packet

func _queue_snapshot(packet: Dictionary) -> void:
	network._lan_trace("snapshot_queue_begin", {"active":active})
	if network.mode != "guest" or not active: network._lan_trace("queue_reject_inactive"); return
	var source_session = str(packet.get("session_id", ""))
	var sequence = int(packet.get("sequence", -1))
	if source_session.is_empty() or sequence <= received_sequence: network._lan_trace("queue_reject_header_or_old_sequence"); return
	if not received_session.is_empty() and source_session != received_session: network._lan_trace("queue_reject_session"); return
	if not pending_packet.is_empty():
		if source_session != str(pending_packet.get("session_id", "")): network._lan_trace("queue_reject_pending_session"); return
		if sequence <= int(pending_packet.get("sequence", -1)): network._lan_trace("queue_reject_pending_sequence"); return
	# Reliable fallback and unreliable motion may arrive in either order
	# during one frame. Keep the newest admissible packet until presentation.
	pending_packet = packet
	network._lan_trace("snapshot_queued")

func _apply_snapshot(packet: Dictionary) -> void:
	network._lan_trace("snapshot_apply_begin", {"world_present":is_instance_valid(world),"active":active})
	if network.mode != "guest" or not active: network._lan_trace("apply_reject_inactive"); return
	var session = str(packet.get("session_id", ""))
	if session.is_empty(): network._lan_trace("apply_reject_empty_session"); return
	if not received_session.is_empty() and session != received_session: network._lan_trace("apply_reject_session"); return
	if int(packet.get("sequence", -1)) <= received_sequence: network._lan_trace("apply_reject_old_sequence"); return
	if not ambient_patrol.can_receive(packet.get("ambient"),session,str(packet.get("region",""))): network._lan_trace("apply_reject_ambient"); return
	# Validate every body before changing any region or presentation. Configure
	# only new departures: configuring an active body would reset damage/health.
	for raw: Variant in packet.get("players",{}):
		var state: Dictionary = packet.players[raw]
		if not BuildContract.valid(state.get("build")) or state.get("airframe") != state.build.airframe_id: network._lan_trace("apply_reject_build_contract"); return
		if players.has(int(raw)) and not BuildContract.matches(players[int(raw)].build,state.build): network._lan_trace("apply_reject_build_changed"); return
	if not is_instance_valid(world) or region_id != str(packet.region):
		if not _load_region(str(packet.region)): network._lan_trace("apply_reject_region_load"); return
	world.local_authority = false
	if not world.apply_mechanism_snapshot(packet.get("mechanisms", {})): network._lan_trace("apply_reject_mechanisms"); return
	if received_session.is_empty(): received_session = session
	if not thermal_cargo.receive_presentation(packet.get("thermal_cargo",{})): network._lan_trace("apply_reject_thermal"); return
	var canal_reference: Variant = packet.get("canal_epoch",0)
	if not canal_reference is int or canal_reference < 0: network._lan_trace("apply_reject_canal_reference"); return
	_expected_canal_epoch = canal_reference if region_id == "I2" else 0
	# Consume every reliable reference even when another facility is late.
	# No accepted motion sequence or pilot input advances with half-built collision.
	if not facilities.consume_all(packet, str(packet.region)):
		network._lan_trace("apply_wait_facility")
		pending_packet = packet
		_apply_pause_state()
		return
	if not campaign.consume_epoch(packet.get("campaign_epoch",0)):
		network._lan_trace("apply_wait_campaign")
		pending_packet = packet
		_apply_pause_state()
		return
	if not _facilities_ready():
		network._lan_trace("apply_wait_readiness")
		pending_packet = packet
		_apply_pause_state()
		return
	received_sequence = int(packet.sequence)
	stats.snapshots += 1
	ecology.consume(int(packet.get("ecology_serial", -1)), int(packet.get("ecology_epoch", -1)))
	for raw in packet.players:
		var id = int(raw)
		var state: Dictionary = packet.players[raw]
		if not players.has(id):
			_spawn_player(id, str(state.identity), state.position, str(state.airframe), BuildContract.validate(state.build).build)
			if not players.has(id): network._lan_trace("apply_reject_player_spawn"); return
			if id == network.local_id(): flight_camera.snap(state.position,float(state.get("heading",0)))
		var body: FlightBodyV2 = players[id]
		body.health = float(state.health)
		body.enabled = bool(state.enabled)
		if region_id == "I3":
			var cargo_actor: bool = thermal_cargo.remote_loaded_actor(body)
			if body.freeze and not cargo_actor and id == network.local_id() and not packet.paused:
				body.linear_velocity = state.velocity
				body.hold_height = state.position.y
			body.cargo_kg = 2.0 if cargo_actor else 0.0
		body.freeze = id != network.local_id() or bool(packet.paused)
		remote_targets[id] = state
	var merged: Dictionary = {}
	for id in packet.entities:
		merged[id] = entities.get(id, {"id":id, "name":"抽能机 · " + str(id).trim_prefix("boss:")}).duplicate(true)
		merged[id].merge(packet.entities[id], true)
	entities = merged
	if not ambient_patrol.receive(packet.ambient): network._lan_trace("apply_reject_ambient_commit"); return
	for raw in packet.players:
		var id = _actor_id(int(raw))
		if entities.has(id):
			entities[id].position = packet.players[raw].position
			entities[id].health = packet.players[raw].health
			entities[id].downed = not packet.players[raw].enabled
	locks = packet.locks.duplicate()
	choice_proposal = packet.vote
	simulation_paused = bool(packet.paused)
	world.restored_gate = bool(packet.gate_saved)
	# Rebuild all state-derived geometry before input, including paused reconnects.
	# Guest synchronization applies state without integrating authoritative motion.
	world.synchronize(entities, 0.0)
	_apply_pause_state()
	for id in world.objects:
		if world.objects[id] is RigidBody3D and entities.has(id) and not world.objects[id].get_meta("thermal_remote_presentation",false): world.objects[id].global_position = entities[id].position
	world_cache["remote_boss"] = packet.boss
	var boss: Dictionary = packet.boss
	world.set_boss_state(boss, bool(packet.get("boss_defeated", false)))
	if region_id == "F1": crown.apply_entities(boss)
	world.show_boss_warning(str(boss.get("telegraph", "")) if boss.get("attack_state", "") == "windup" else "", packet.get("boss_marks", {}), float(boss.get("attack_remaining", 0.0)))
	story.consume(int(packet.get("story_serial", -1)))
	network._lan_trace("snapshot_applied", {"region":region_id,"players":players.size()})

func _trial_gauge_read(peer_id: int, observation: Dictionary) -> void:
	if not network.is_authority() or not active or region_id!="I2": return
	if peer_id==network.local_id(): trial_gauge.apply_observation(observation)
	elif network.guests.has(peer_id):
		network.send_event(peer_id,{"kind":"trial_gauge_read","session_id":network.session_id,"epoch":trial.epoch,"observation":observation})

func _network_event(event: Dictionary) -> void:
	content_journal.receive(event)
	combat_sites.receive_event(event)
	if event.get("kind") == "chapter_voice_read88" and active and event.get("region") == region_id:
		var voice_session: String = received_session if network.mode == "guest" else network.session_id
		if event.get("session_id") == voice_session:
			var voice_target: String = str(event.get("target", ""))
			if voice_target == "F4:plans_reviewed": voice_target = "F4:chapter_choice"
			var read_voice: String = Voices88.cue_for("choice:" + voice_target + ":" + str(event.get("option", "")) + ":full")
			if not read_voice.is_empty(): audio.play_radio(read_voice)
	ambient_patrol.receive_event(event)
	weapons.receive(event)
	campaign.receive(event)
	chapter_choices.receive(event)
	if event.get("kind") == CanalReplica.KIND and network.mode == "guest" and _expected_canal_epoch > 0 and event.get("epoch") == _expected_canal_epoch:
		canal_replica.receive(event)
	if event.get("kind") == "audio" and network.mode == "guest" and active and event.get("session_id") == received_session and event.get("region") == region_id:
		audio.receive_event(event)
	facilities.receive(event)
	if event.get("kind") == "trial_gauge_read" and network.mode=="guest" and active and region_id=="I2" and _facilities_ready():
		if event.get("session_id")==received_session and event.get("epoch")==trial.expected_epoch and event.get("observation") is Dictionary:
			trial_gauge.apply_observation(event.observation)
	if event.get("kind") == "ecology_state": ecology.receive(event)
	if event.get("kind") == "receipt_batch": receipts.receive(event)
	if event.get("kind") == "story_state": story.receive(event)
	if event.get("kind") == NpcSidejobs.KIND: sidejobs.receive(event)
	if event.get("kind") == "dialogue":
		var lines: Array=event.get("lines",[])
		if event.get("sidejob_templates",false): lines=sidejobs.render_lines(lines)
		interface.show_dialogue(str(event.get("character_id", "")),lines,str(event.get("speaker_name", "")))
	if event.get("kind") == "notice": interface.notify(str(event.text))
	if event.get("kind") == "effect" and network.mode == "guest" and is_instance_valid(world):
		if event.get("effect") == "beam": world.beam(event.from, event.to, event.tint, float(event.duration))
		elif event.get("effect") == "ring": world.telegraph(event.position, float(event.radius), float(event.duration))
	if event.get("kind") == "host_left":
		if is_instance_valid(flight_assist): flight_assist.stop("房主已离开，辅助已停止。")
		canal_replica.clear()
		facilities.reset_connection()
		field_requests.reset_connection()
		content_chapters.reset_connection()
		trial_gauge.clear_readings()
		receipts.reset()
		active = false
		owns_world = false
		pending_packet.clear()
		received_sequence = -1
		received_session = ""
		choice_proposal.clear()
		_clear_players()
		_dispose_current_region()
		world_cache = store.snapshot()
		interface.menu.show()
		interface.hud.hide()
		interface.vote.hide()
		inputs.active = false

func _publish_canal(peer_id := 0) -> void:
	if canal == null or region_id != "I2" or network.mode != "host" or network.guests.is_empty(): return
	_canal_serial += 1
	var event: Dictionary = canal_replica.make_event(canal,_canal_epoch,_canal_serial)
	if event.is_empty(): return
	if peer_id > 1: network.send_event(peer_id,event)
	else:
		for id in network.guests: network.send_event(int(id),event)

func _ui_action(action: String, payload: Dictionary) -> void:
	if _quit_draining: return
	if active and network.mode == "guest" and not _facilities_ready() and action in ["explore", "travel", "travel_to", "boss_start", "interact", "choice"]:
		interface.notify("正在恢复机关状态，请稍候。")
		return
	if action == "branch" and network.mode == "solo" and consensus.current_proposal().is_empty():
		var branch_payload: Dictionary = payload.duplicate(true)
		if _capture_before_lifecycle(func(): _ui_action(action,branch_payload)): return
	match action:
		"assist_menu":
			if is_instance_valid(flight_assist) and bool(flight_assist.status().get("enabled",false)):
				flight_assist.stop("已交还手动驾驶")
			else: interface.front.navigate("assist")
		"handbook": final_flow.open_handbook()
		"ending_book": final_flow.open_ending()
		"campaign_book_close": final_flow.close_book()
		"campaign_book_voice":
			audio.stop_radio()
			var final_cue: String = str(payload.get("cue", ""))
			if FinalVoices.owns(final_cue): audio.play_radio(final_cue)
		"radio_line":
			var voice: String = FinalVoices.cue_for_line(str(payload.get("character_id", "")), str(payload.get("text", "")))
			if voice.is_empty(): voice = Voices88.cue_for_line(str(payload.get("character_id", "")), str(payload.get("text", "")), str(payload.get("speaker", "")))
			if voice.is_empty(): audio.stop_radio()
			else: audio.play_radio(voice)
		"radio_stop": audio.stop_radio()
		"journal":
			if interface.journal.visible: interface.journal.hide()
			elif active: network.send_action("content_journal", {})
			else: interface.notify("先进入飞行，再查看这一世界的小队纪事。")
		"journal_track": content_journal.track(payload)
		"campaign_choice_reopen":
			var offer: Dictionary = chapter_choices.specification(str(payload.get("target","")))
			network.send_action("campaign_choice_open",{"anchor":str(offer.get("anchor_id",""))})
		"campaign_choice_read": network.send_action(action,payload)
		"campaign_choice_propose": network.send_action("propose",{"kind":"campaign_choice","payload":payload})
		"select": selected_ability = str(payload.ability)
		"hangar": _open_hangar()
		"hangar_save": _save_hangar(payload)
		"hangar_return": _return_to_hangar()
		"hangar_close":
			interface.hangar.hide()
			interface.menu.show()
		"solo", "host", "join":
			if active:
				interface.menu.hide()
				interface.notify("已返回当前飞行；更换配装或房间请先保存战况并返回机库。")
				return
			frame_id = FRAMES[clampi(int(payload.get("frame", 0)), 0, FRAMES.size() - 1)]
			start_flight("guest" if action == "join" else action, str(payload.get("address", "127.0.0.1")))
		"menu":
			interface.menu.show()
			interface.set_branches(store.list_branches() if network.is_authority() else [])
		"resume":
			if active: interface.menu.hide()
		"wheel":
			interface.wheel.visible = not interface.wheel.visible
			Engine.time_scale = 0.25 if interface.wheel.visible and network.mode == "solo" else 1.0
		"travel":
			var destinations: Array = Regions.destinations(region_id)
			if destinations.size() == 1:
				network.send_action("propose", {"kind":"region_change", "payload":{"region_id":destinations[0]}})
			else:
				var choices: Array = []
				for destination in destinations:
					choices.append({"id":destination, "name":Regions.definition(destination).name, "available":_can_travel_to(destination)})
				interface.show_travel(choices)
		"travel_to":
			interface.travel.hide()
			network.send_action("propose", {"kind":"region_change", "payload":{"region_id":str(payload.get("region_id", ""))}})
		"explore": story.request_nearby()
		"choice":
			interface.menu.hide()
			network.send_action("propose", {"kind":"major_choice", "payload":{"value":str(payload.value)}})
		"confirm", "cancel", "boss_start", "interact": network.send_action(action, payload)
		"branch":
			if str(payload.get("id", "")) == str(world_cache.get("world", {}).get("branch_id", "")): return
			if not profile_ready or not owns_world or not active: interface.notify("先进入自己的单人世界再切换分支")
			elif network.mode != "solo": interface.notify("剧情分支切换请在单人会话进行")
			elif not consensus.current_proposal().is_empty(): interface.notify("请先完成或取消当前共同决定，再切换分支")
			else:
				if not facilities.pending_retry(): return
				var target_branch: Dictionary = store.snapshot().branches.get(str(payload.id), {})
				var target_hash: String = store.branch_world_hash(str(payload.id))
				if not target_branch.has("world") or not ecology.restore_world(target_branch.world, false):
					interface.notify("目标分支的环境记录无法读取，当前分支与原档保持不变。")
					return
				var prepared := _prepare_region(str(target_branch.world.get("region_id", "I1")), target_branch.world)
				if not prepared.ok:
					interface.notify("目标分支地区无法读取，当前分支与原档保持不变：" + str(prepared.error))
					return
				if pending_completion:
					_finish_boss()
					if pending_completion:
						_discard_prepared_region(prepared)
						return
				if not _canal_action_in_capture and not _save_environment():
					_discard_prepared_region(prepared)
					return
				var branch_changes: Dictionary = prepared.facilities.initialization
				var switched: Dictionary = store.switch_branch(str(payload.id), branch_changes, target_hash)
				if switched.get("ok", false):
					world_cache = store.snapshot()
					if not ecology.restore_world(world_cache.world):
						_discard_prepared_region(prepared)
						active = false
						interface.notify("分支环境记录未通过检查，已停止会话以保留原档。")
						return
					consensus.configure([1], int(world_cache.world_revision))
					if not _adopt_prepared_region(prepared): return
					interface.show_game()
				else:
					_discard_prepared_region(prepared)
					interface.notify("分支未切换：" + str(switched.get("error", "保存失败")))
		"quit": _quit()

func _open_hangar() -> void:
	if not profile_ready: return
	interface.menu.show()
	interface.wheel.hide()
	Engine.time_scale = 1.0
	inputs.clear()
	interface.hangar.open(store.snapshot(),active,frame_id)

func _save_hangar(payload: Dictionary) -> void:
	if not profile_ready or not payload.get("build") is Dictionary: return
	var prepared: Dictionary = Hangar.prepare_save(store.snapshot(),payload.build,active,int(payload.get("generation",-1)))
	if not prepared.get("ok",false):
		interface.hangar.apply_commit_result({"ok":false,"error":Hangar.error_text(prepared)})
		return
	var committed: Dictionary = {"ok":true} if prepared.no_op else store.commit(prepared.transaction)
	if committed.get("ok",false):
		frame_id = str(prepared.build.airframe_id)
		interface.frames.select(FRAMES.find(frame_id))
		if not active: world_cache = store.snapshot()
	interface.hangar.apply_commit_result(committed,store.snapshot() if committed.get("ok",false) else {})

func _return_to_hangar() -> void:
	if is_instance_valid(flight_assist): flight_assist.stop("已停止辅助，准备保存返航")
	if pending_completion:
		_finish_boss()
		if pending_completion: return
	if _capture_before_lifecycle(_return_to_hangar): return
	if owns_world and active and not _canal_action_in_capture and not _save_environment(): return
	# Save/capture has released before destroying any custody or region nodes.
	active = false
	owns_world = false
	inputs.active = false
	inputs.clear()
	Engine.time_scale = 1.0
	audio.set_context(region_id,false)
	network._lan_trace("close_origin_return_to_hangar")
	network.close()
	thermal_cargo.clear()
	crown.clear()
	campaign.clear()
	if canal != null: canal.clear()
	canal = null
	canal_replica.clear()
	_expected_canal_epoch = 0
	_canal_pause_proposal = ""
	_thermal_pause_proposal = ""
	boss_active = false
	boss_campaign = false
	simulation_paused = false
	_clear_players()
	_dispose_current_region()
	story.reset_connection()
	sidejobs.reset_connection()
	field_requests.reset_connection()
	content_chapters.reset_connection()
	content_journal.reset_connection()
	story_jobs.reset_connection()
	final_flow.reset_connection()
	ecology.reset_connection()
	facilities.reset_connection()
	receipts.reset()
	receipt_catchup.clear()
	choice_proposal.clear()
	pending_packet.clear()
	received_sequence = -1
	received_session = ""
	interface.hud.hide()
	interface.vote.hide()
	interface.travel.hide()
	interface.chapter_choice.hide()
	interface.radio.hide()
	interface.radio_queue.clear()
	_open_hangar()
	if is_instance_valid(interface.front): interface.front.on_returned()

func _unhandled_input(event: InputEvent) -> void:
	if interface.campaign_book.visible:
		if event.is_action_pressed("ui_cancel") or event is InputEventKey and event.pressed and event.physical_keycode == KEY_H or event is InputEventJoypadButton and event.pressed and event.button_index in [JOY_BUTTON_BACK, JOY_BUTTON_B]:
			final_flow.close_book()
			get_viewport().set_input_as_handled()
		return
	if interface.hangar.visible:
		if event.is_action_pressed("ui_cancel"):
			_ui_action("hangar_close",{})
			get_viewport().set_input_as_handled()
		return
	if interface.menu.visible and is_instance_valid(interface.front):
		if event.is_action_pressed("ui_cancel"):
			if interface.front.handle_cancel(): get_viewport().set_input_as_handled()
		return
	if not active: return
	if is_instance_valid(flight_assist): flight_assist.manual_event(event)
	if interface.journal.visible:
		if event is InputEventKey and event.pressed and event.physical_keycode in [KEY_ESCAPE, KEY_L]: interface.journal.hide()
		if event is InputEventJoypadButton and event.pressed and event.button_index in [JOY_BUTTON_BACK, JOY_BUTTON_B]: interface.journal.hide()
		return
	if event is InputEventJoypadButton:
		if _controller_button(event): get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: flight_camera.zoom(1)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: flight_camera.zoom(-1)
	if not event is InputEventKey or not event.pressed or event.echo: return
	var key = event.physical_keycode
	# Match the existing flight-input fallback for virtual keyboards with special scan codes.
	if (key == 0 or key >= KEY_SPECIAL) and event.keycode > 0: key = event.keycode
	if key == KEY_ESCAPE and interface.travel.visible:
		interface.travel.hide()
		return
	if interface.chapter_choice.visible:
		if key == KEY_ESCAPE: interface.chapter_choice.hide()
		return
	if key == KEY_ESCAPE: interface.menu.visible = not interface.menu.visible
	if interface.menu.visible: return
	if network.mode == "guest" and not _facilities_ready(): return
	if key >= KEY_1 and key <= KEY_9: interface.select_ability(key - KEY_1)
	if key == KEY_0: interface.select_ability(9)
	if key == KEY_TAB: _cycle_target()
	if key == KEY_F or key == KEY_X: _send_ability(key == KEY_X)
	if key == KEY_G:
		if not interface.advance_dialogue(): story.request_nearby()
	if key == KEY_R: network.send_action("retry")
	if key == KEY_B: _ui_action("wheel", {})
	if key == KEY_M: _ui_action("travel", {})
	if key == KEY_L: _ui_action("journal", {})
	if key == KEY_H: _ui_action("handbook", {})
	if key == KEY_P: _request_pause()
	if key == KEY_T:
		for id in players:
			if id != network.local_id() and not players[id].enabled: network.send_action("revive", {"target":id})

## Local buttons use the same reliable, authority-validated actions as keys.
## Do not trust button edges carried in an unreliable flight input packet.
func _controller_button(event: InputEventJoypadButton) -> bool:
	if not active or not event.pressed or inputs.legacy.device >= 0 and event.device != inputs.legacy.device: return false
	interface.controller_navigation = true
	interface._update_controller_focus()
	if interface.journal.visible:
		if event.button_index in [JOY_BUTTON_BACK, JOY_BUTTON_B]:
			interface.journal.hide()
			return true
		return false
	if event.button_index == JOY_BUTTON_BACK:
		if interface.hangar.visible: _ui_action("hangar_close",{})
		elif interface.travel.visible: interface.travel.hide()
		elif interface.chapter_choice.visible: interface.chapter_choice.hide()
		elif interface.wheel.visible: _ui_action("wheel",{})
		else: interface.menu.visible = not interface.menu.visible
		return true
	if interface.hangar.visible or interface.menu.visible or interface.wheel.visible or interface.chapter_choice.visible or interface.vote.visible or interface.travel.visible: return false
	if network.mode == "guest" and not _facilities_ready(): return false
	match event.button_index:
		JOY_BUTTON_RIGHT_SHOULDER: _cycle_target()
		JOY_BUTTON_Y: _send_ability(false)
		JOY_BUTTON_RIGHT_STICK: _send_ability(true)
		JOY_BUTTON_B:
			if not interface.advance_dialogue(): story.request_nearby()
		JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_DPAD_LEFT: interface.select_ability(posmod(interface.selected-1,Interface.ABILITIES.size()))
		JOY_BUTTON_DPAD_RIGHT: interface.select_ability(posmod(interface.selected+1,Interface.ABILITIES.size()))
		JOY_BUTTON_LEFT_STICK: _ui_action("travel",{})
		JOY_BUTTON_START: _request_pause()
		_: return false
	return true

func _cycle_target() -> void:
	if network.mode == "guest" and not _facilities_ready(): return
	var id = network.local_id()
	if not players.has(id): return
	var candidates: Array = []
	var ranks: Dictionary = {}
	var crown_space = is_instance_valid(world.crown_arena) and world.crown_arena.in_combat_space(players[id].global_position)
	for key in entities:
		if key.begins_with("player:"): continue
		if players[id].global_position.distance_to(entities[key].position) <= 45:
			candidates.append(key)
			var on_screen = not camera.is_position_behind(entities[key].position) and get_viewport().get_visible_rect().has_point(camera.unproject_position(entities[key].position))
			var familiar = selected_ability in Guidance.recommended_abilities(str(key), entities[key])
			var crown_target = str(key).begins_with(CrownSession.HOST_PREFIX) or key == CrownSession.CORE
			ranks[key] = (4 if crown_space and not crown_target else 0) + (0 if on_screen else 2) + (0 if familiar else 1)
	# Reorder only on an explicit Tab press. Every nearby target stays reachable;
	# a recommendation is not support/LOS validation and never changes a lock itself.
	candidates.sort_custom(func(a, b):
		if ranks[a] != ranks[b]: return ranks[a] < ranks[b]
		var da = players[id].position.distance_squared_to(entities[a].position)
		var db = players[id].position.distance_squared_to(entities[b].position)
		return str(a) < str(b) if da == db else da < db
	)
	if candidates.is_empty(): return
	var index = candidates.find(str(locks.get(id, "")))
	var selected: String = candidates[(index + 1) % candidates.size()]
	locks[id] = selected
	network.send_action("lock", {"target_id":selected})

func _send_ability(reverse: bool) -> void:
	if network.mode == "guest" and not _facilities_ready(): return
	var id = network.local_id()
	if not players.has(id): return
	var body: FlightBodyV2 = players[id]
	var modes = {"push_pull":"pull", "force_field":"release", "light":"off", "heat":"cool", "charge":"drain"}
	network.send_action("ability", {"ability":selected_ability, "target_id":str(locks.get(id, "")), "mode":str(modes.get(selected_ability, "")) if reverse else "", "point":_ability_aim_point(body)})

func _ability_aim_point(body: FlightBodyV2) -> Vector3:
	var direction = Vector3(body.command.get("planar", Vector3.ZERO))
	if direction.length() < 0.1: direction = Vector3(-camera.global_basis.z.x, 0, -camera.global_basis.z.z).normalized()
	return body.global_position + direction.normalized() * 6

func _request_pause() -> void:
	if active: network.send_action("propose", {"kind":"pause", "payload":{}})

func _update_pilot_marker(body: FlightBodyV2) -> void:
	interface.pilot_marker.visible = body.enabled and not camera.is_position_behind(body.global_position)
	interface.pilot_marker.position = camera.unproject_position(body.global_position)
	var edge = camera.unproject_position(body.global_position + camera.global_basis.x * float(body.stats.width_m) * 0.6)
	interface.pilot_marker.radius = clampf(edge.distance_to(interface.pilot_marker.position) + 5, 12, 32)
	interface.pilot_marker.queue_redraw()

func _refresh_interface() -> void:
	final_flow.advance()
	var local = network.local_id()
	var content_art = world.get_node_or_null("Dev88Presentation") if is_instance_valid(world) else null
	if content_art != null: Presentation88.apply_state(content_art, story.state)
	interface.weapon_status.text = weapons.hud(local) if players.has(local) else ""
	interface.title.text = str(Regions.definition(region_id).get("name", region_id))
	if players.has(local):
		var body: FlightBodyV2 = players[local]
		var entity: Dictionary = entities.get(_actor_id(local), {})
		_update_pilot_marker(body)
		var session_label = {"solo":"单人", "host":"房主 · %d人" % players.size(), "guest":"访客"}.get(network.mode, "")
		if simulation_paused: session_label += " · 共同暂停"
		var weather_label = str({"clear":"平稳", "rain":"阵风", "storm":"强风"}.get(world.ecology_weather, "平稳"))
		if region_id == "I4":
			var local_storm: String = I4Storm.short_status(body.environment_sample)
			if not local_storm.is_empty(): weather_label = local_storm
		interface.vitals.text = "生命 %d  能量 %d  高度 %.1fm / 离地 %.1fm  速度 %.1fm/s  %s · %s" % [body.health, entity.get("energy", 100), body.global_position.y, body.ground_distance, body.linear_velocity.length(), session_label, weather_label]
		interface.flight_details.text = "两界共脉 · %s\n绝对高度 %.1fm · 离地 %.1fm · %d FPS\n风况：%s" % [session_label, body.global_position.y, body.ground_distance, Engine.get_frames_per_second(), weather_label]
		if simulation_paused: interface.flight_details.text += "\n返回飞行后按 P / 手柄 Start，提议共同恢复。"
		var instrument_line := ""
		if region_id == "I4":
			instrument_line = I4Storm.instrument_text(body.environment_sample,float(body.telemetry.get("heading_deg",rad_to_deg(body.heading))))
			if not instrument_line.is_empty(): interface.flight_details.text += "\n"+instrument_line
		var optional_hint: String=sidejobs.hint_text(region_id)
		var field_hint: String=field_requests.hint_text(region_id)
		var story_hint: String=story_jobs.hint_text(region_id)
		if not story_hint.is_empty(): field_hint += ("\n" if not field_hint.is_empty() else "") + story_hint
		if not field_hint.is_empty(): optional_hint += ("\n" if not optional_hint.is_empty() else "") + field_hint
		var combat_hint: String = combat_sites.hint_text(region_id)
		if not combat_hint.is_empty(): optional_hint = combat_hint
		var status_line: String=instrument_line
		if not optional_hint.is_empty():
			interface.flight_details.text += "\n"+optional_hint
			status_line += ("\n" if not status_line.is_empty() else "") + optional_hint.get_slice("\n", 0) + " · L 纪事"
		interface.environment_status.text = status_line
		interface.environment_status.visible = not status_line.is_empty()
	var target = str(locks.get(local, ""))
	var resolved_underdeck := target in ["I1:underdeck_latch", "I1:underdeck_grille"] and is_instance_valid(world.underdeck) and bool(world.underdeck.snapshot().latched)
	var ability_hint = Guidance.ability_hint(selected_ability)
	if players.has(local): ability_hint = Guidance.ability_hint(selected_ability, players[local].global_position, entities.get(target, {}), _ability_aim_point(players[local]))
	var ability_line = str(ability_hint.get("action_text", ""))
	if not str(ability_hint.get("note", "")).is_empty(): ability_line += " · " + str(ability_hint.note)
	if ability_hint.get("target_required", false) and ability_hint.get("distance_known", false): ability_line += " · " + str(ability_hint.distance_text)
	if resolved_underdeck: ability_line = "检修通道已开放 · 不必重复操作"
	var recommendations: Array[String] = []
	if not resolved_underdeck: recommendations = Guidance.recommended_abilities(target, entities.get(target, {}))
	interface.show_ability_context("当前：%s · %s" % [ability_hint.get("name", ""), ability_hint.get("range_text", "")], ability_line, recommendations)
	interface.target_marker.clear_target()
	interface.objective_marker.clear()
	if players.has(local) and not boss_active:
		var destination = story.display_anchor()
		var tracked_destination: Dictionary = content_journal.target()
		if not tracked_destination.is_empty(): destination = tracked_destination
		if not destination.is_empty() and str(destination.anchor_id) != target: interface.objective_marker.show_destination(camera, destination, players[local].global_position)
	if entities.has(target):
		var state: Dictionary = entities[target]
		if players.has(local) and state.get("position") is Vector3:
			var pilot: FlightBodyV2 = players[local]
			var at: Vector3 = state.position
			var occluded = not _line_clear(pilot.global_position, at, pilot.get_rid(), target)
			var closed = target == CrownSession.CORE and not bool(state.get("open", false))
			var condition = "装甲关闭" if closed else ("遮挡" if occluded else "已瞄准")
			if resolved_underdeck: condition = "已解除" if target == "I1:underdeck_latch" else "通道常开"
			if not resolved_underdeck and not closed and not occluded and ability_hint.get("target_required", false) and ability_hint.get("distance_known", false) and not ability_hint.in_range:
				condition = "能力需再靠近 %.1fm" % (ceilf(float(ability_hint.approach_m) * 10) / 10)
			if target == CrownSession.CORE and not closed and not occluded: condition = "开放"
			interface.target_marker.show_target(camera, at, str(state.get("name", target)), pilot.global_position.distance_to(at), at.y - pilot.global_position.y, condition, closed or occluded, 4.0 if target == "boss:crown_core" else 1.2)
		interface.target_info.text = "目标：%s%s" % [state.get("name", target), " · 已解除" if resolved_underdeck else ""]
		if interface.details_open: interface.target_info.text += "\n温度 %.0f°  电荷 %.0f  生长 %.0f%%" % [state.get("temperature", 20), state.get("charge", 0), float(state.get("growth", 0)) * 100]
		if "rotatable" in state.get("tags", []):
			interface.target_info.text = "锁定：%s · 光源%s" % [state.get("name", target), "已亮" if float(state.get("light_level", 0)) > 0.25 else "未亮"]
			if interface.details_open: interface.target_info.text += "\n朝向 %.0f° · 光束可调整方向。" % rad_to_deg(float(state.get("angle", 0)))
		elif "growable" in state.get("tags", []):
			var illuminated = maxf(float(state.get("light_level", 0)), float(state.get("environment_light", 0))) >= 0.25
			interface.target_info.text = "锁定：%s\n%s · 生长 %.0f%%" % [state.get("name", target), "已获得光照" if illuminated else "缺少光照", float(state.get("growth", 0)) * 100]
			if interface.details_open: interface.target_info.text += "\n温度 %.0f° · 光足且温度适宜时可催生。" % state.get("temperature", 20)
		if not interface.details_open:
			var temperature = float(state.get("temperature", 20.0))
			if "growable" in state.get("tags", []) and temperature > 60.0:
				interface.target_info.text += ("\n过热 %.0f° · 5 热量，X 降温" if "thermal" in state.get("tags", []) else "\n过热 %.0f° · 不能直接调温") % temperature
			elif "growable" in state.get("tags", []) and temperature < 0.0:
				interface.target_info.text += ("\n过冷 %.0f° · 5 热量，F 加热" if "thermal" in state.get("tags", []) else "\n过冷 %.0f° · 不能直接调温") % temperature
			elif selected_ability == "heat" and "thermal" in state.get("tags", []):
				interface.target_info.text += "\n温度 %.0f°" % temperature
			elif selected_ability == "charge" and "conductive" in state.get("tags", []):
				interface.target_info.text += "\n电荷 %.0f" % state.get("charge", 0)
	else: interface.target_info.text = "Tab 选择附近目标 · B 查看能力"
	interface.target_info.visible = entities.has(target) or interface.details_open
	if players.has(local): interface.objective.text = story.objective_text(players[local].global_position, interface.details_open)
	interface.show_vote(consensus.current_proposal() if network.is_authority() else choice_proposal, simulation_paused)
	var boss = (crown.presentation() if crown.active() else encounter.get_state()) if network.is_authority() and boss_active else world_cache.get("remote_boss", {})
	if campaign.supported(): boss = campaign.presentation() if boss_active and (not network.is_authority() or campaign.active()) else {}
	interface.boss_info.text = ""
	if boss.is_empty() and combat_sites.active():
		interface.objective.text = "可选战斗 · " + combat_sites.hint_text(region_id) + "\n退出标线可撤回；条件成立后回站牌 G 交接。"
	var nearby_contact = story.nearest(players[local].global_position) if players.has(local) else ""
	interface.explore_button.visible = boss.is_empty() and players.has(local) and (not nearby_contact.is_empty() or interface.radio.visible)
	interface.explore_button.text = "继续对话  G" if interface.radio.visible else ("G " + story.interaction_label(nearby_contact) if not nearby_contact.is_empty() else "G 联络 / 调查")
	interface.gate_button.visible = boss.is_empty() and world.objects.has(region_id + ":beacon") and players.has(local) and players[local].global_position.distance_to(world.objects[region_id + ":beacon"].global_position) <= 7.0
	interface.gate_button.text = "修复已记录" if world.restored_gate else "提交闸门修复"
	interface.gate_button.disabled = world.restored_gate
	if not boss.is_empty():
		if campaign.supported():
			interface.objective.text = str(campaign.definition.name)+"\n处理场地机关，避开预警，在恢复窗口攻击亮起的部件。"
			interface.boss_info.text = "%s · 核心 %.0f / %.0f · 阶段%d · 第%d次\n%s" % [campaign.definition.name,float(boss.core_hp_milli)/1000.0,float(campaign.definition.core_hp_milli)/1000.0,int(boss.phase),int(boss.attempt),"攻击预警：移动、换高度或借掩体" if boss.attack_stage=="warning" else ("恢复窗口：观察亮起的部件" if boss.attack_stage=="recovery" else "保持航迹，注意锁定的攻击范围")]
			return
		if boss.get("type", "") == "parasitic_crown":
			interface.objective.text = "解除冠兽寄生\n" + ("种核已暴露，锁定后射击。" if boss.core_open else "操作宿主，使冠甲张开。")
			if interface.details_open: interface.objective.text += "\n照亮宿主再催生，或连续加热逼落。\n迁移时可先操作下一处宿主；低根浪向上躲，孢柱横移或换层。"
			if target == CrownSession.CORE: interface.target_info.text = "锁定：冠兽种核\n%s\nJ / 左键射击 · Tab 切换宿主" % ("冠甲已张开" if boss.core_open else "冠甲关闭，先操作宿主")
			elif target.begins_with(CrownSession.HOST_PREFIX) and entities.has(target):
				var host: Dictionary = entities[target]
				interface.target_info.text = "锁定：%s · %.0f°\n4 光 → 7 生长，或 5 热量\n%s" % [host.name, host.temperature, "根系恢复中，可转向其他宿主" if host.recovering else ("已受光，可催生束缚" if host.light_level > 0 else "可照亮催生或加热逼退")]
			interface.boss_info.text = "寄生冠兽 %d / 160 · 阶段%d · 第%d次\n%s" % [boss.core_health, boss.phase, boss.attempt, "种核暴露，抓住窗口" if boss.core_open else "观察宿主与高度预警"]
			return
		interface.objective.text = "截停抽能鲸机\n" + ("核心已暴露，锁定后射击。" if boss.phase == "exposed" else "让左右供能舱停止供能。")
		if interface.details_open: interface.objective.text += "\n攻击后供能舱会开启；射击、抽能、接管可以混用。\n绕到侧面准备下一次开舱。"
		if target.begins_with("boss:"):
			var part = target.trim_prefix("boss:")
			if part == "core":
				interface.target_info.text = "锁定：核心\n%s\nTab 切换部件 · J / 左键射击" % ("核心已暴露" if boss.phase == "exposed" else "两侧供能未切断")
			elif boss.nodes.has(part):
				var node: Dictionary = boss.nodes[part]
				interface.target_info.text = "锁定：%s供能舱\n%s · 结构 %d\n6 电荷 → X 抽能\n0 接管 → F 使用" % ["左" if part == "port" else "右", "已停机" if not node.powered else ("接口已露出" if boss.nodes_open else "装甲关闭"), node.health]
		interface.boss_info.text = "抽能机核心 %d / %d · 第%d次尝试\n%s" % [boss.core_health, boss.core_max_health, boss.attempt, "核心暴露，锁定核心" if boss.phase == "exposed" else ("供能舱开启，可攻击或接管" if boss.nodes_open else "观察预警，等待攻击后窗口")]

func _note(peer_id: int, text: String) -> void:
	network.send_event(peer_id, {"kind":"notice", "text":text})

func _note_all(text: String) -> void:
	for id in players: _note(int(id), text)

func _beam(from: Vector3, to: Vector3, tint: Color, duration = 0.16) -> void:
	world.beam(from, to, tint, duration)
	_broadcast_effect({"effect":"beam", "from":from, "to":to, "tint":tint, "duration":duration})

func _ring(at: Vector3, radius: float, duration: float) -> void:
	world.telegraph(at, radius, duration)
	_broadcast_effect({"effect":"ring", "position":at, "radius":radius, "duration":duration})

func _broadcast_effect(event: Dictionary) -> void:
	if network.mode != "host": return
	event["kind"] = "effect"
	for id in network.guests: network.send_event(int(id), event)

## Only accepted local-pilot lifecycle cues; never broadcast another pilot's UI.
func _audio_owner_vital(peer_id: int, cue: String) -> void:
	if not network.is_authority() or not active or simulation_paused or cue not in ["disabled","revived"] or not players.has(peer_id): return
	var body: FlightBodyV2 = players[peer_id]
	if cue=="disabled" and (body.enabled or body.health>0.0): return
	if cue=="revived" and (not body.enabled or body.health<=0.0): return
	if peer_id!=network.local_id() and (network.mode!="host" or not network.guests.has(peer_id)): return
	_audio_serial += 1
	var event := {"kind":"audio","cue":cue,"position":body.global_position,"emitter":"local_damage","owner_id":peer_id,
		"event_id":"%s:%d" % [network.session_id,_audio_serial],"session_id":network.session_id,"region":region_id}
	if peer_id==network.local_id(): audio.receive_event(event)
	else: network.send_event(peer_id,event)

## Sound follows an accepted gameplay event. Guests never rebroadcast cues.
func _audio_event(cue: String, at: Vector3, emitter := "world") -> void:
	if not at.is_finite(): return
	_audio_serial += 1
	var event := {"kind":"audio","cue":cue,"position":at,"emitter":emitter,
		"event_id":"%s:%d" % [network.session_id, _audio_serial],"session_id":network.session_id,"region":region_id}
	audio.receive_event(event)
	if network.mode == "host":
		for id in network.guests: network.send_event(int(id), event)

func _actor_id(peer_id: int) -> String:
	return "player:" + str(peer_id)

func _decode(value: Variant) -> Variant:
	if value is Dictionary:
		var copy: Dictionary = {}
		for key in value:
			var item: Variant = value[key]
			if key == "position" and item is Array and item.size() == 3:
				var valid := true
				for component in item:
					if not (component is int or component is float) or not is_finite(float(component)): valid = false
				copy[key] = Vector3(float(item[0]),float(item[1]),float(item[2])) if valid else item
			else: copy[key] = _decode(item)
		return copy
	return value

func _write_qa_report() -> void:
	var report = {"qa_scripted":true, "mode":qa_mode, "seconds":qa_seconds, "region":region_id, "players":players.size(), "stats":stats, "network":network.telemetry, "positions":{}, "user_dir":OS.get_user_data_dir()}
	report.observation = {"started_after_ready":_qa_started_usec >= 0,"ready_wait_seconds":_qa_ready_wait_seconds,"first_sequence":_qa_first_sequence,"max_raw_delta_seconds":_qa_max_raw_delta,"action_seconds":_qa_action_seconds,"stop_reason":_qa_stop_reason}
	report.ecology = {"simulated_seconds":ecology.simulation.elapsed_seconds(), "applied_serial":ecology.applied_serial, "host_serial":ecology.serial, "visible_actors":ecology.view.targets.size() if is_instance_valid(ecology.view) else 0}
	for id in players: report.positions[str(id)] = [players[id].position.x, players[id].position.y, players[id].position.z]
	if not qa_report.is_empty():
		DirAccess.make_dir_recursive_absolute(qa_report.get_base_dir())
		var file = FileAccess.open(qa_report, FileAccess.WRITE)
		if file: file.store_string(JSON.stringify(report, "\t"))
	print("V3_QA_REPORT ", JSON.stringify(report))

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST: _quit()

func _quit() -> void:
	if is_instance_valid(flight_assist): flight_assist.stop("正在保存并退出")
	if pending_completion:
		_finish_boss()
		if pending_completion: return
	if _capture_before_lifecycle(_quit): return
	if owns_world and active and not _canal_action_in_capture and not _save_environment(): return
	_complete_quit()

func _ensure_flight_assist() -> bool:
	if is_instance_valid(flight_assist): return true
	var path:="res://scripts/v3/assist/twin_flight_assist.gd"
	if not ResourceLoader.exists(path): return false
	var script=load(path)
	if script==null or not script.can_instantiate(): return false
	flight_assist=script.new()
	add_child(flight_assist)
	flight_assist.setup(self)
	flight_assist.changed.connect(interface.set_assist_status)
	return true

func start_flight_assist(scope: String = "objective") -> Dictionary:
	if not _ensure_flight_assist(): return {"ok":false,"message":"辅助驾驶模块未能加载，请返回大厅重试。"}
	return flight_assist.start(scope)

func _complete_quit() -> void:
	if _quit_draining: return
	_quit_draining = true
	Engine.time_scale = 1.0
	# This terminal path is reached only after the original save/capture gate.
	# Do not turn a closed guest connection into a new solo simulation while
	# AudioServer releases its stopped native playbacks on ordinary main frames.
	active = false
	audio.shutdown()
	if network:
		network._lan_trace("close_origin_complete_quit")
		network.close()
	var deadline: int = Time.get_ticks_usec() + 1000000
	last_audio_shutdown_result = audio.shutdown_status()
	while not last_audio_shutdown_result.ready and Time.get_ticks_usec() < deadline:
		await get_tree().process_frame
		last_audio_shutdown_result = audio.shutdown_status()
	print("V3_AUDIO_SHUTDOWN_EXIT " + JSON.stringify(last_audio_shutdown_result))
	if not last_audio_shutdown_result.ready:
		push_error("Native audio references did not release within final-exit bound: " + JSON.stringify(last_audio_shutdown_result))
	get_tree().quit(0 if last_audio_shutdown_result.ready else 1)
