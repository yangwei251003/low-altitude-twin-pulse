extends SceneTree
## Native active/paused eight-loop release, without Session or QA networking.
## Root runs serially with --verbose; this is not listening/output-device evidence.
const Audio = preload("res://scripts/v3/audio/twin_audio.gd")
var checks: Array = []
var observations: Array = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await _case(false)
	await _case(true)
	var failures: Array = []
	for row: Dictionary in checks:
		if not row.passed: failures.append(row.name)
	print("V3_AUDIO_SHUTDOWN ", JSON.stringify({"checks":checks,"failures":failures,
		"observations":observations,"human_listening":"not_performed"}))
	quit(0 if failures.is_empty() else 1)

func _case(paused: bool) -> void:
	var audio := Audio.new()
	root.add_child(audio)
	# Use real driver/main time, not a synthesized audio update or private API.
	await create_timer(.05,true,false,true).timeout
	var native_playbacks := 0
	for player in audio._loops.values():
		if player.has_stream_playback(): native_playbacks += 1
	audio.set_paused(paused)
	var prefix := "paused" if paused else "active"
	_check(prefix+"_original_eight_loop_playbacks", native_playbacks==8)
	audio.shutdown()
	var initial: Dictionary = audio.shutdown_status()
	_check(prefix+"_terminal_detaches_own_streams", initial.started and initial.own_stream_cache_entries==0 and not audio.play_event("ui_confirm"))
	audio.shutdown()
	_check(prefix+"_repeat_shutdown_keeps_observed_references", audio.shutdown_status().tracked_references==initial.tracked_references)
	var started: int = Time.get_ticks_usec()
	var final: Dictionary = audio.shutdown_status()
	while not final.ready and Time.get_ticks_usec()-started<1000000:
		await process_frame
		final = audio.shutdown_status()
	_check(prefix+"_actual_native_references_drain_within_one_second", final.ready and final.pending_references==0)
	observations.append({"paused":paused,"initial":initial,"final":final})
	audio.queue_free()
	await process_frame

func _check(label: String, passed: bool) -> void:
	checks.append({"name":label,"passed":passed})
	if not passed: push_error("Audio native shutdown check failed: "+label)
