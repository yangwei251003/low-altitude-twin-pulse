extends SceneTree
## Main integrator runs this after the unified import. Does not use desktop input.

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var script := load("res://scripts/v2/game_audio.gd") as GDScript
	if script == null or not script.can_instantiate():
		quit(1)
		return
	var audio: Node = script.new()
	root.add_child(audio)
	await create_timer(2.0).timeout
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/v22/manifest.json"))
	var duration := 0.0
	for track: Dictionary in manifest.music:
		var stream := load("res://assets/audio/v22/" + str(track.file)) as AudioStream
		check(stream != null, "Music loads: " + str(track.id))
		if stream != null: duration += stream.get_length()
	check(manifest.music.size() >= 6 and duration >= 900.0, "Six complete tracks total at least fifteen minutes")
	for bus: String in ["Music", "Rotor", "SFX", "Ambient", "Birds", "UI", "Voice"]:
		check(AudioServer.get_bus_index(bus) >= 0, "Bus exists: " + bus)
		check(AudioServer.get_bus_send(AudioServer.get_bus_index(bus)) == "Master", "Independent routing: " + bus)
	check(audio.get_debug_state().music_resident_count <= 2, "Only current plus next music retained")
	var current_id: String = audio.get_debug_state().music_current
	var before: float = audio.get_debug_state().music_position
	audio.set_context("hangar")
	paused = true
	await create_timer(0.3, true).timeout
	paused = false
	check(audio.get_debug_state().music_current == current_id, "Menu/pause keeps same music")
	check(float(audio.get_debug_state().music_position) >= before, "Menu/pause does not rewind")
	audio.set_mix({"sfx": 0.0, "ambient": 0.6, "rotor": 0.7, "birds": 0.4, "voice": 0.9})
	check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Ambient")), "SFX mute does not mute environment")
	for id: String in ["lobby_welcome", "m01_lift", "m01_yaw90", "m02_cargo_pickup", "m02_swing", "m03_cover", "tutorial_complete"]:
		check(not audio.voice_text(id).is_empty(), "Voice alias/text: " + id)
	check(audio.play_voice("m01_lift", true), "Narration starts")
	await create_timer(0.25).timeout
	check(float(audio.get_debug_state().narration_duck) < 0.4, "Voice ducks music")
	audio.stop_voice()
	await create_timer(0.8).timeout
	check(float(audio.get_debug_state().narration_duck) > 0.99, "Voice release restores gain")
	check(audio.play_environment_event("bird", Vector3(8, 3, 0)), "Spatial bird event starts")
	audio.update_environment({"listener_position": Vector3(2, 3, 4), "wind": 0.5, "rain": 0.6, "traffic": 0.2, "region_id": "R3"})
	check(audio.get_debug_state().environment.rain == 0.6, "Environment sample accepted")
	# Seek near the end to exercise a real transition without waiting nineteen minutes.
	var current: AudioStreamPlayer = audio._music_players[audio._music_slot]
	current.seek(current.stream.get_length() - 0.3)
	await create_timer(4.6).timeout
	check(audio.get_debug_state().music_current != current_id, "Transition advances without immediate repeat")
	check(audio.get_debug_state().music_resident_count <= 2, "Transition releases previous music")
	check(audio.get_debug_state().missing_assets.is_empty(), "No missing referenced audio")
	print(JSON.stringify({"checks": checks, "failures": failures, "music_seconds": duration, "state": audio.get_debug_state()}))
	audio.queue_free()
	await process_frame
	audio = null
	# Release stopped playback references on the audio mix thread.
	await create_timer(0.2).timeout
	quit(0 if failures.is_empty() else 1)
