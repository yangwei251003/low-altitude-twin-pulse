extends SceneTree

var failures: Array[String] = []
var checks: Array[String] = []
var project_root := ""

func _initialize() -> void:
	project_root = get_script().resource_path.get_base_dir().get_base_dir()
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks.append(label)
	if condition:
		print("PASS " + label)
	else:
		failures.append(label)
		push_error("FAIL " + label)

func _run() -> void:
	var audio_script := load(project_root.path_join("scripts/v2/game_audio.gd")) as GDScript
	if audio_script == null or not audio_script.can_instantiate():
		push_error("Audio script could not load")
		quit(1)
		return
	var audio: Node = audio_script.new()
	audio.audio_root = ProjectSettings.globalize_path(project_root.path_join("assets/v2/audio"))
	root.add_child(audio)
	await process_frame
	check(audio.process_mode == Node.PROCESS_MODE_ALWAYS, "Audio continues fades and UI processing during pause")
	for bus: String in ["Master", "Music", "Rotor", "SFX", "UI", "Ambient", "Birds", "Voice"]:
		check(AudioServer.get_bus_index(bus) >= 0, "Dedicated " + bus + " bus exists")
	for bus: String in ["Music", "Rotor", "SFX", "UI", "Ambient", "Birds", "Voice"]:
		check(AudioServer.get_bus_send(AudioServer.get_bus_index(bus)) == "Master", bus + " has independent routing to Master")
	var before_count := AudioServer.bus_count
	var before_effects := AudioServer.get_bus_effect_count(0)
	var duplicate: Node = audio_script.new()
	duplicate.audio_root = audio.audio_root
	root.add_child(duplicate)
	await process_frame
	check(AudioServer.bus_count == before_count, "A second instance does not duplicate buses")
	check(AudioServer.get_bus_effect_count(0) == before_effects, "Master limiter is not duplicated")
	duplicate.queue_free()
	await process_frame
	check(audio.get_debug_state().missing_assets.is_empty(), "All initial loop and event assets load without import dependency")
	check(audio.get_debug_state().loaded_streams == 32, "Nine fixed loops, one environment and twenty-two events prewarm")
	check(audio.get_debug_state().music_resident_count <= 2, "Long music retains only current plus next")
	var loop: AudioStreamWAV = audio._streams["rotor_low"]
	check(loop.loop_mode == AudioStreamWAV.LOOP_FORWARD and loop.loop_end == 192000, "Rotor loops at exact four-second PCM boundary")
	check(loop.format == AudioStreamWAV.FORMAT_16_BITS and loop.mix_rate == 48000, "Runtime retains 48 kHz 16-bit PCM")
	check(audio._streams["shot_1"].loop_mode == AudioStreamWAV.LOOP_DISABLED, "Event streams never loop")
	audio.set_mix({"master": 0.8, "music": 0.25, "sfx": 0.6, "ui": 0.9, "ambient": 0.4, "mute": true})
	check(AudioServer.is_bus_mute(0), "Master mute suppresses every bus")
	check(is_equal_approx(AudioServer.get_bus_volume_linear(AudioServer.get_bus_index("Music")), 0.25), "Music has independent volume")
	check(is_equal_approx(AudioServer.get_bus_volume_linear(AudioServer.get_bus_index("SFX")), 0.6), "SFX has independent volume")
	check(is_equal_approx(AudioServer.get_bus_volume_linear(AudioServer.get_bus_index("UI")), 0.9), "UI has independent volume")
	audio.set_mix({"mute": false, "music": 0.0, "master": NAN, "sfx": INF, "ui": -0.5, "ambient": "invalid"})
	check(not AudioServer.is_bus_mute(0), "Unmute restores master")
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "Zero music volume also mutes the bus")
	check(audio.get_debug_state().mix.master == 0.8 and audio.get_debug_state().mix.sfx == 0.6, "Non-finite mix inputs keep safe previous levels")
	check(audio.get_debug_state().mix.ui == 0.0 and audio.get_debug_state().mix.ambient == 0.4, "Mix clamps numeric bounds and rejects nonnumbers")
	audio.set_mix({"music_volume": 0.36, "ui_volume": 0.65})
	check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "Volume aliases restore an independently muted bus")
	audio.set_mix({"volume": 0.7})
	check(is_equal_approx(AudioServer.get_bus_volume_linear(0), 0.7), "Session volume key controls Master")
	audio.update_flight({"thrust_fraction": 0.2, "speed_mps": 2.0, "flight_state": "flying"}, true, "R1", false)
	for _index: int in range(20):
		audio._process(0.1)
	var low_pitch := float(audio._loop_players["rotor_low"].pitch_scale)
	check(audio.get_debug_state().loop_gains.rotor_low > audio.get_debug_state().loop_gains.rotor_high, "Low actual thrust selects low rotor layer")
	audio.update_flight({"thrust_fraction": 0.95, "speed_mps": 15.0, "flight_state": "flying"}, true, "R3", true)
	for _index: int in range(30):
		audio._process(0.1)
	check(audio._loop_players["rotor_low"].pitch_scale > low_pitch, "Actual thrust modulates pitch smoothly")
	check(audio.get_debug_state().loop_gains.rotor_high > audio.get_debug_state().loop_gains.rotor_low, "High actual thrust selects high rotor layer")
	check(audio.get_debug_state().loop_gains.wind > 0.3, "Airspeed raises wind rather than keyboard input")
	check(audio.get_debug_state().region_asset == "v22/environment/bed_R3", "Region selects its bird-free environmental bed")
	check(audio._night and audio.get_debug_state().loop_gains.environment_a < 0.45, "Night reduces the bed and suppresses scheduled birds")
	check(audio.get_debug_state().loop_gains.environment_a > 0.3 and audio.get_debug_state().loop_gains.environment_b < 0.003, "Regional transition fades old layer without overlap accumulation")
	audio.update_flight({"thrust_fraction": 0.5, "flight_state": "recovering"}, true, "R3", true)
	for _index: int in range(12):
		audio._process(0.1)
	check(audio.get_debug_state().loop_gains.rotor_unstable > 0.3, "Recovery uses the subdued instability layer")
	var events_before := int(audio.get_debug_state().events_played)
	audio.play_event("enemy_warning")
	audio.play_event("warning")
	audio.play_event("not_a_real_cue")
	check(audio.get_debug_state().events_played == events_before + 1, "Aliases resolve, warnings debounce, and unknown cues are ignored")
	check(audio.get_debug_state().tension_left == 6.0, "Combat cues trigger bounded action music context")
	audio.play_event("mission_completed")
	check(audio.get_debug_state().tension_left == 0.0, "Completion returns music to calm")
	var before_discover := int(audio.get_debug_state().events_played)
	audio.play_event("discover")
	check(audio.get_debug_state().events_played == before_discover + 1, "Discovery event resolves to the gentle reward cue")
	for _index: int in range(25):
		audio._last_event.clear()
		audio.play_event("shot")
	check(audio._voices.size() == 10, "Repeated events have a fixed ten-voice cap")
	paused = true
	for _index: int in range(25):
		audio._process(0.1)
	check(audio.get_debug_state().loop_gains.rotor_high < 0.0001 and audio.get_debug_state().loop_gains.wind < 0.0001, "Pause fades flight audio while mixer remains live")
	check(audio._music_players[audio._music_slot].playing, "Full-length music remains under pause")
	paused = false
	audio.update_flight({"thrust_fraction": INF, "speed_mps": NAN}, false, "bad-region", false)
	for _index: int in range(30):
		audio._process(0.1)
	check(is_finite(float(audio.get_debug_state().thrust)) and audio.get_debug_state().thrust < 0.001, "Invalid telemetry cannot poison the mixer")
	check(audio.get_debug_state().region_asset == "v22/environment/bed_R1", "Unknown region uses the explicit R1 fallback")
	check(audio.get_debug_state().missing_assets.is_empty(), "All dynamically selected assets remain available")
	var transitions_before := int(audio.get_debug_state().events_played)
	audio.update_flight({"flight_state": "landed", "speed_mps": 0.0}, true, "R1", false)
	audio.update_flight({"flight_state": "flying", "speed_mps": 8.0, "brake_active": false}, true, "R1", false)
	audio.update_flight({"flight_state": "flying", "speed_mps": 8.0, "brake_active": true}, true, "R1", false)
	check(audio.get_debug_state().events_played == transitions_before + 2, "Takeoff and braking telemetry trigger distinct physical feedback")
	var stereo_music := true
	var music_seconds := 0.0
	for track: Dictionary in audio._music_catalog:
		stereo_music = stereo_music and int(track.get("channels", 0)) == 2
		music_seconds += float(track.get("seconds", 0))
	check(stereo_music and audio._music_catalog.size() >= 6, "All full music arrangements retain stereo")
	check(music_seconds >= 900.0 and not audio._loop_players.has("music_tension"), "Complete playlist exceeds fifteen minutes with no conflicting legacy drum loop")
	audio.set_mix({"rotor_volume": 0.7, "birds_volume": 0.3, "voice_volume": 0.9, "sfx": 0.0})
	check(is_equal_approx(AudioServer.get_bus_volume_linear(AudioServer.get_bus_index("Rotor")), 0.7), "Rotor gain is independent of SFX mute")
	check(is_equal_approx(AudioServer.get_bus_volume_linear(AudioServer.get_bus_index("Birds")), 0.3), "Bird gain is independently adjustable")
	check(not audio.voice_text("m01_yaw90").is_empty(), "Tutorial alias resolves Mandarin text")
	check(audio.play_voice("m01_lift", true), "Tutorial narration resolves an exported asset")
	audio.stop_voice()
	check(audio.get_debug_state().buses.has("Master"), "Output diagnostics expose live driver and bus state")
	var result := {
		"engine": Engine.get_version_info().string,
		"audio_driver": AudioServer.get_driver_name(),
		"checks": checks.size(), "failures": failures,
		"status": "PASS" if failures.is_empty() else "FAIL",
		"not_tested": ["human_listening", "speaker_headphone_mix", "game_output_capture"]
	}
	var evidence := FileAccess.open(project_root.path_join("assets/v2/audio/test_result.json"), FileAccess.WRITE)
	if evidence != null:
		evidence.store_string(JSON.stringify(result, "\t") + "\n")
	print(JSON.stringify(result))
	audio.queue_free()
	await process_frame
	audio = null
	# The audio thread releases stopped playback references on its next mix cycle.
	await create_timer(0.15).timeout
	quit(0 if failures.is_empty() else 1)
