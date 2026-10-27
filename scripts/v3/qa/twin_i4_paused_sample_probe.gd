extends RefCounted
## Read-only native assertion draft for the existing environment-LAN observer.
## No launcher, fake state, clock/pose/UI writes, Store or solver progression.
const Storm = preload("res://scripts/v3/environment/twin_i4_storm_environment.gd")

static func capture(session: Node) -> Dictionary:
	if not is_instance_valid(session) or not session.active or session.region_id!="I4" or not is_instance_valid(session.world):
		return {"ok":false,"code":"live_I4_required"}
	var local: int = session.network.local_id()
	if not session.players.has(local): return {"ok":false,"code":"actual_local_actor_required"}
	var body: FlightBodyV2 = session.players[local]
	var clock_before: float = session.world.clock_seconds
	var at: Vector3 = body.global_position
	var expected: Dictionary = session.world.sample_environment(at)
	var cached: Dictionary = body.environment_sample.duplicate(true)
	var field: Dictionary = expected.get("i4_storm",{})
	var cached_field: Dictionary = cached.get("i4_storm",{})
	var differences: Array[String] = []
	for key: String in ["available","code","phase","phase_seconds","seconds_to_change","clock_input","field_weight","gust","open_wind_mps","wind_window","shelter_hits","shelter_rays","shelter_factor","shelter_blockers","interference_strength","signal_blocker","navigation_source_present","compass_error_limit_deg","compass_error_deg"]:
		if not field.has(key) or not cached_field.has(key) or field[key]!=cached_field[key]: differences.append("i4_storm."+key)
	for key: String in ["wind_velocity","water","water_height","nav_quality","compass_quality"]:
		if not expected.has(key) or not cached.has(key) or expected[key]!=cached[key]: differences.append(key)
	var heading: float = float(body.telemetry.get("heading_deg",rad_to_deg(body.heading)))
	var expected_hud: String = Storm.instrument_text(expected,heading)
	var actual_hud: String = session.interface.environment_status.text
	var visible: bool = session.interface.environment_status.is_visible_in_tree()
	var stable_read: bool = clock_before==session.world.clock_seconds and at==body.global_position
	var actual_paused: bool = session.simulation_paused and body.freeze
	var available: bool = field.get("available",false) and field.get("code")=="actual_current_world_sample"
	var hud_ok: bool = visible and not expected_hud.is_empty() and actual_hud==expected_hud and "罗盘约" in actual_hud and "±" in actual_hud
	return {"ok":actual_paused and available and stable_read and differences.is_empty() and hud_ok,
		"code":"paused_native_cache_HUD_match" if actual_paused and available and stable_read and differences.is_empty() and hud_ok else "not_yet_paused_native_cache_HUD_match",
		"role":session.network.mode,"session_id":session.received_session if session.network.mode=="guest" else session.network.session_id,
		"sequence":session.received_sequence,"physics_frame":Engine.get_physics_frames(),"process_frame":Engine.get_process_frames(),
		"region":session.region_id,"world_clock":clock_before,"world_space":session.world.get_world_3d().space.get_id(),
		"body_id":body.get_instance_id(),"body_rid":body.get_rid().get_id(),"position":at,"body_frozen":body.freeze,
		"native_pose":PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM),
		"paused":session.simulation_paused,"fresh_query_did_not_mutate_clock_or_pose":stable_read,
		"expected":expected,"cached":cached,"differences":differences,"hud_visible":visible,"hud_text":actual_hud,"expected_hud":expected_hud,
		"scope":"Exact current local native World/pose query versus original body cache and visible original Label. Requires ordinary paused pose correction to settle; not a Host-contact proxy, ENet launcher or clock fixture."}
