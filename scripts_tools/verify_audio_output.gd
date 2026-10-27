extends SceneTree
## Captures actual Godot bus output; never opens a microphone or changes OS volume.

var audio: Node
var captures: Dictionary = {}
var measures: Dictionary = {}
var samples := PackedVector2Array()
var output_id := "current"
var audio_script_path := "res://scripts/v2/game_audio.gd"
var export_audio_path := ""
var evidence_directory := ""
var boundary_previous_id := ""

func _initialize() -> void:
	evidence_directory = ProjectSettings.globalize_path("res://assets/v2/audio/evidence")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--audio-evidence="):
			output_id = argument.trim_prefix("--audio-evidence=").validate_filename()
		if argument.begins_with("--audio-pack="):
			export_audio_path = argument.trim_prefix("--audio-pack=")
	call_deferred("_run")

func _run() -> void:
	if not export_audio_path.is_empty():
		if not ProjectSettings.load_resource_pack(export_audio_path, true):
			push_error("Could not mount exported audio pack")
			quit(1)
			return
	audio = load(audio_script_path).new()
	if export_audio_path.is_empty():
		audio.audio_root = ProjectSettings.globalize_path("res://assets/v2/audio")
	root.add_child(audio)
	await process_frame
	# Match a fresh player profile, including its 55% master setting.
	audio.set_mix({"volume": 0.55})
	# Godot applies effects before a bus fader. Move only the Master fader to
	# a temporary input bus so Master capture observes the final audible mix.
	AudioServer.add_bus(1)
	AudioServer.set_bus_name(1, "OutputProbeFader")
	for bus: String in ["Music", "Rotor", "SFX", "UI", "Ambient", "Birds", "Voice"]:
		AudioServer.set_bus_send(AudioServer.get_bus_index(bus), "OutputProbeFader")
	_sync_probe_fader()
	for bus: String in ["Master", "Music", "Rotor", "SFX", "UI", "Ambient", "Birds", "Voice"]:
		var capture := AudioEffectCapture.new()
		capture.buffer_length = 1.0
		AudioServer.add_bus_effect(AudioServer.get_bus_index(bus), capture)
		captures[bus] = capture
		measures[bus] = {"sum_sq": 0.0, "peak": 0.0, "samples": 0, "nonzero": 0, "clipped": 0}
	var stages: Array = []
	for phase: String in ["menu", "hover", "full_thrust", "narration", "rain_traffic", "region_night", "paused", "loop_boundary", "mute"]:
		if phase == "menu": audio.update_flight({}, false, "R1", false)
		if phase == "hover": audio.update_flight({"thrust_fraction": 0.45, "speed_mps": 3.0, "flight_state": "flying"}, true, "R1", false)
		if phase == "full_thrust":
			audio.update_flight({"thrust_fraction": 0.95, "speed_mps": 18.0, "flight_state": "flying"}, true, "R2", false)
		if phase == "region_night": audio.update_flight({"thrust_fraction": 0.6, "speed_mps": 6.0, "flight_state": "flying"}, true, "R3", true)
		if phase == "rain_traffic": audio.update_environment({"wind": 0.3, "rain": 0.6, "traffic": 0.35, "machinery": 0.2, "listener_position": Vector3.ZERO})
		if phase == "paused": paused = true
		if phase == "loop_boundary":
			paused = false
			audio.update_flight({}, false, "R1", false)
		if phase == "mute":
			paused = false
			audio.set_mix({"mute": true})
			_sync_probe_fader()
		# Let smooth gains settle before measuring each scenario.
		await _collect(2.0, false)
		_reset_measures()
		if phase == "loop_boundary":
			boundary_previous_id = str(audio.get_debug_state().music_current)
			var current: AudioStreamPlayer = audio._music_players[audio._music_slot]
			current.seek(current.stream.get_length() - 3.8)
		if phase == "narration": audio.play_voice("lobby_welcome", true)
		if phase == "full_thrust":
			audio.play_event("warning")
			audio.play_event("collision")
			audio.play_event("shot")
			audio.play_environment_event("bird", Vector3(12, 0, 0))
		if phase == "rain_traffic": audio.play_environment_event("vehicle_start", Vector3(8, 0, 0))
		if phase == "region_night": audio.play_event("reward")
		await _collect(4.8 if phase == "loop_boundary" else 2.0, true)
		var music_player: AudioStreamPlayer = audio._music_players[audio._music_slot]
		var stage := {"phase": phase, "buses": _summarize(), "state": audio.get_debug_state(), "music_playing": music_player.playing, "music_position": music_player.get_playback_position()}
		stages.append(stage)
	var failures: Array[String] = []
	for stage: Dictionary in stages:
		var master: Dictionary = stage.buses.Master
		if stage.phase == "mute":
			if float(master.peak) > 0.0001: failures.append("Master mute leaks output")
		else:
			if master.nonzero_samples == 0: failures.append(stage.phase + ": silent Master output")
			if float(master.rms_dbfs) < -36.0: failures.append(stage.phase + ": extremely quiet output")
			if int(master.clipped_samples) > 0: failures.append(stage.phase + ": clipped samples")
		if stage.phase == "loop_boundary" and (not stage.music_playing or str(stage.state.music_current) == boundary_previous_id):
			failures.append("Full music playlist did not advance across its transition")
		if stage.phase == "narration" and (int(stage.buses.Voice.nonzero_samples) == 0 or float(stage.state.narration_duck) > 0.4):
			failures.append("Narration is silent or does not duck music")
		if stage.phase == "full_thrust" and int(stage.buses.Rotor.nonzero_samples) == 0:
			failures.append("Thrust-dependent Rotor bus is silent")
		if int(stage.state.music_resident_count) > 2: failures.append("More than current and next music retained")
	var directory := evidence_directory
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		push_error("Could not create host audio evidence directory")
		quit(1)
		return
	var wave := AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.mix_rate = int(AudioServer.get_mix_rate())
	wave.stereo = true
	var pcm := PackedByteArray()
	pcm.resize(samples.size() * 4)
	for index: int in range(samples.size()):
		pcm.encode_s16(index * 4, int(clampf(samples[index].x, -1.0, 1.0) * 32767.0))
		pcm.encode_s16(index * 4 + 2, int(clampf(samples[index].y, -1.0, 1.0) * 32767.0))
	wave.data = pcm
	if wave.save_to_wav(directory.path_join(output_id + "_mix.wav")) != OK: failures.append("Could not save captured audio")
	var result := {"engine": Engine.get_version_info().string, "driver": AudioServer.get_driver_name(), "mix_rate": AudioServer.get_mix_rate(), "stages": stages, "failures": failures, "status": "PASS" if failures.is_empty() else "FAIL", "not_tested": ["human_listening", "physical_speaker_or_headphone_output"], "scope": "Real-time AudioEffectCapture of final Godot mix: temporary upstream bus applies the Master fader/mute before the Master capture and limiter. Other bus captures are pre-fader."}
	var file := FileAccess.open(directory.path_join(output_id + "_result.json"), FileAccess.WRITE)
	if file == null:
		push_error("Could not save audio evidence JSON")
		quit(1)
		return
	file.store_string(JSON.stringify(result, "\t") + "\n")
	print(JSON.stringify({"audio_output": result.status, "driver": result.driver, "failures": failures, "evidence": directory.path_join(output_id + "_result.json")}))
	paused = false
	audio.queue_free()
	await process_frame
	audio = null
	for bus: String in captures:
		var bus_index := AudioServer.get_bus_index(bus)
		for effect_index: int in range(AudioServer.get_bus_effect_count(bus_index) - 1, -1, -1):
			if AudioServer.get_bus_effect(bus_index, effect_index) == captures[bus]:
				AudioServer.remove_bus_effect(bus_index, effect_index)
	captures.clear()
	await create_timer(0.5).timeout
	quit(0 if failures.is_empty() else 1)

func _sync_probe_fader() -> void:
	var mix: Dictionary = audio.get_debug_state().mix
	AudioServer.set_bus_volume_db(1, linear_to_db(maxf(float(mix.master), 0.0001)))
	AudioServer.set_bus_mute(1, bool(mix.mute) or float(mix.master) <= 0.0)
	AudioServer.set_bus_volume_db(0, 0.0)
	AudioServer.set_bus_mute(0, false)

func _collect(seconds: float, record: bool) -> void:
	var end_time := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end_time:
		await process_frame
		for bus: String in captures:
			var effect: AudioEffectCapture = captures[bus]
			var block := effect.get_buffer(effect.get_frames_available())
			if record:
				var values: Dictionary = measures[bus]
				for frame: Vector2 in block:
					values.sum_sq += frame.length_squared()
					values.peak = maxf(values.peak, maxf(absf(frame.x), absf(frame.y)))
					values.samples += 2
					if absf(frame.x) > 0.000001: values.nonzero += 1
					if absf(frame.y) > 0.000001: values.nonzero += 1
					if absf(frame.x) >= 0.9999: values.clipped += 1
					if absf(frame.y) >= 0.9999: values.clipped += 1
				if bus == "Master": samples.append_array(block)

func _reset_measures() -> void:
	for bus: String in measures:
		measures[bus] = {"sum_sq": 0.0, "peak": 0.0, "samples": 0, "nonzero": 0, "clipped": 0}

func _summarize() -> Dictionary:
	var result: Dictionary = {}
	for bus: String in measures:
		var item: Dictionary = measures[bus]
		result[bus] = {"peak": item.peak, "peak_dbfs": linear_to_db(maxf(item.peak, 0.000000001)), "rms_dbfs": linear_to_db(maxf(sqrt(item.sum_sq / maxf(item.samples, 1)), 0.000000001)), "samples": item.samples, "nonzero_samples": item.nonzero, "clipped_samples": item.clipped, "discarded_frames": captures[bus].get_discarded_frames()}
	return result
