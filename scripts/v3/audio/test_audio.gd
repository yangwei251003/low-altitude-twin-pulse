extends SceneTree
## Bounded integration contract check. Headless playback is not a listening test.
const Audio = preload("res://scripts/v3/audio/twin_audio.gd")
var checks: Dictionary = {}
var audio
var report := "res://data/v3/audio/runtime_validation.json"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audio-report="): report = arg.trim_prefix("--audio-report=")
	_run.call_deferred()

func _run() -> void:
	audio = Audio.new()
	root.add_child(audio)
	await process_frame
	var initial: Dictionary = audio.diagnostics()
	check("catalog_and_all_streams_loaded", initial.ready and initial.missing.is_empty())
	audio.set_mix({"master":0.8,"music":0.65,"sfx":0.8,"ambient":0.65,"rotor":0.8,"ui":0.75,"mute":false}, false)
	audio.set_context("I1", true)
	audio.set_listener(Vector3.ZERO)
	check("in_range_event_accepted", audio.play_event("shot", Vector3(0,0,2), {"emitter":"test"}))
	check("same_emitter_cooldown", not audio.play_event("shot", Vector3(0,0,2), {"emitter":"test"}))
	check("out_of_range_dropped", not audio.play_event("hit", Vector3(1000,0,0), {"emitter":"far"}))
	check("unknown_cue_rejected", not audio.play_event("unknown"))
	check("nonfinite_rejected", not audio.play_event("hit", Vector3.INF))
	check("invalid_network_position_rejected", not audio.receive_event({"kind":"audio","cue":"hit","position":["bad",0,0]}))
	audio.set_paused(true)
	check("shared_pause_blocks_gameplay_cues", not audio.play_event("hit", Vector3.ZERO))
	check("shared_pause_keeps_ui", audio.play_event("ui_confirm"))
	audio.set_paused(false)
	audio.release_region()
	check("release_requires_new_listener", not audio.play_event("hit", Vector3.ZERO))
	audio.set_listener(Vector3.ZERO)
	var burst_ok := true
	for i in range(Audio.SPATIAL_LIMIT):
		burst_ok = audio.play_event("boss_warning", Vector3.ZERO, {"emitter":"warning%d" % i}) and burst_ok
	check("same_frame_pool_slots_reserved", burst_ok)
	check("low_priority_cannot_steal_warnings", not audio.play_event("shot", Vector3.ZERO, {"emitter":"low"}))
	await physics_frame
	check("spatial_voice_limit", int(audio.diagnostics().active_spatial) <= Audio.SPATIAL_LIMIT)
	audio.release_region()
	await physics_frame
	check("release_stops_spatial_voices", int(audio.diagnostics().active_spatial) == 0)
	audio.set_mix({"master":0.6,"sfx":0.0,"mute":true}, false)
	check("settings_mute_and_sfx_zero", AudioServer.is_bus_mute(AudioServer.get_bus_index("V3Master")) and AudioServer.is_bus_mute(AudioServer.get_bus_index("V3SFX")))
	audio.set_mix({"mute":false}, false)
	check("unmute_preserves_channel_zero", not AudioServer.is_bus_mute(AudioServer.get_bus_index("V3Master")) and AudioServer.is_bus_mute(AudioServer.get_bus_index("V3SFX")))
	audio.set_context("F1", true)
	check("fantasy_context_accepted", audio.diagnostics().region == "F1")
	audio.shutdown()
	check("shutdown_rejects_events", not audio.play_event("ui_confirm"))
	var failed: Array = []
	for id in checks:
		if not checks[id]: failed.append(id)
	var result := {"schema":1,"passed":failed.is_empty(),"checks":checks,"failed":failed,"engine":Engine.get_version_info(),"human_listening":"not_performed","headless_is_not_physical_output_evidence":true}
	var output := FileAccess.open(report, FileAccess.WRITE)
	if output != null: output.store_string(JSON.stringify(result, "\t") + "\n")
	else: push_error("Audio test report could not be written: " + report)
	print("V3_AUDIO_CONTRACT ", JSON.stringify(result))
	audio.queue_free()
	quit(0 if failed.is_empty() and output != null else 1)

func check(id: String, ok: bool) -> void:
	checks[id] = ok
	if not ok: push_error("V3 audio check failed: " + id)
