extends SceneTree
## Owner runs serially with a real driver after import. No microphone or OS-volume
## access. Captures the final Godot mix, not physical speakers or human listening.

const VOICES: Array[String] = ["lobby_welcome", "lobby_device", "lobby_settings", "lobby_tutorial", "cargo_swing"]
const LISTENER_POSITION := Vector3(20, 4, 30)
const BIRD_POSITION := LISTENER_POSITION + Vector3(12, 2, 0)
var audio: Node
var scene: Node3D
var camera: Camera3D
var captures: Dictionary = {}
var stereo := PackedVector2Array()
var stages: Array = []
var measurements: Dictionary = {}
var failures: Array[String] = []
var manifest: Dictionary = {}
var spatial_setup: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _run() -> void:
	# Godot 4.7.2 _update_panning enumerates cameras before resolving their
	# viewport's AudioListener3D. A listener alone cannot validate spatial sound.
	root.audio_listener_enable_3d = true
	scene = Node3D.new()
	root.add_child(scene)
	camera = Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(0, 3, 12)
	camera.make_current()
	audio = load("res://scripts/v2/game_audio.gd").new()
	scene.add_child(audio)
	audio.update_environment({"listener_position": LISTENER_POSITION})
	await create_timer(0.5).timeout
	spatial_setup = {"camera_current": camera.is_current(), "listener_current": audio._listener.is_current(),
		"same_world": camera.get_world_3d() == audio._listener.get_world_3d() and camera.get_world_3d() == audio._spatial_voices[0].get_world_3d(),
		"listener_position": [LISTENER_POSITION.x, LISTENER_POSITION.y, LISTENER_POSITION.z],
		"bird_position": [BIRD_POSITION.x, BIRD_POSITION.y, BIRD_POSITION.z], "bird_distance_m": LISTENER_POSITION.distance_to(BIRD_POSITION)}
	_check(spatial_setup.camera_current and spatial_setup.listener_current and spatial_setup.same_world, "Spatial scene has current camera/listener in the emitter world")
	_check(AudioServer.get_driver_name() != "Dummy", "Actual output requires a non-Dummy driver")
	manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/v22/manifest.json"))
	AudioServer.add_bus(1)
	AudioServer.set_bus_name(1, "V22ProbeFader")
	AudioServer.set_bus_send(1, "Master")
	for bus: String in audio.BUS_NAMES:
		AudioServer.set_bus_send(AudioServer.get_bus_index(bus), "V22ProbeFader")
	# Capture effects see pre-fader samples. Apply user's master gain/mute on an
	# upstream bus so Master capture includes their actual final output gain.
	for bus: String in ["Master", "Music", "Rotor", "SFX", "Ambient", "Birds", "Voice", "UI"]:
		var capture := AudioEffectCapture.new()
		capture.buffer_length = 1.0
		AudioServer.add_bus_effect(AudioServer.get_bus_index(bus), capture)
		captures[bus] = capture
	await _phase("music", 4.0)
	for id: String in VOICES:
		var seconds := 6.0
		for item: Dictionary in manifest.voice:
			if str(item.id) == id: seconds = float(item.seconds) + 1.2
		await _phase("voice_" + id, seconds, id)
	await _phase("bird_spatial", 4.0)
	await _phase("flight", 4.0)
	await _phase("warning_burst", 4.0)
	await _phase("warning_release", 1.6)
	await _phase("rain_traffic", 5.0)
	audio.set_mix({"mute": true})
	AudioServer.set_bus_mute(AudioServer.get_bus_index("V22ProbeFader"), true)
	await create_timer(0.25).timeout
	await _phase("muted", 2.5)
	_write_result()
	scene.queue_free()
	await process_frame
	audio = null
	camera = null
	scene = null
	for bus: String in captures:
		var bus_index := AudioServer.get_bus_index(bus)
		for effect_index: int in range(AudioServer.get_bus_effect_count(bus_index) - 1, -1, -1):
			if AudioServer.get_bus_effect(bus_index, effect_index) == captures[bus]: AudioServer.remove_bus_effect(bus_index, effect_index)
	captures.clear()
	for bus: String in ["Music", "Rotor", "SFX", "Ambient", "Birds", "Voice", "UI"]:
		AudioServer.set_bus_send(AudioServer.get_bus_index(bus), "Master")
	AudioServer.remove_bus(AudioServer.get_bus_index("V22ProbeFader"))
	await create_timer(0.2).timeout
	quit(0 if failures.is_empty() else 1)

func _phase(phase: String, seconds: float, voice_id: String = "") -> void:
	measurements.clear()
	for bus: String in captures:
		captures[bus].clear_buffer()
		measurements[bus] = {"samples": 0, "sum_sq": 0.0, "peak": 0.0, "nonzero": 0, "clipped": 0, "discarded_start": captures[bus].get_discarded_frames()}
	var event_started := true
	if not voice_id.is_empty(): event_started = audio.play_voice(voice_id, true)
	var clip: Dictionary = {}
	if not voice_id.is_empty() and event_started:
		var path := "res://assets/audio/v22/voice/" + voice_id + ".wav"
		clip = {"id": voice_id, "text": audio.voice_text(voice_id), "source_sha256": FileAccess.get_sha256(path), "loaded_seconds": audio._narrator.stream.get_length()}
		for item: Dictionary in manifest.voice:
			if str(item.id) != voice_id: continue
			_check(str(clip.source_sha256) == str(item.sha256), voice_id + ": source matches manifest hash")
			_check(absf(float(clip.loaded_seconds) - float(item.seconds)) < 0.03, voice_id + ": loaded resource duration matches final source")
	if phase == "bird_spatial": event_started = audio.play_environment_event("bird_00", BIRD_POSITION)
	if phase == "flight":
		audio.update_flight({"flight_state": "flying", "thrust_fraction": 0.7, "speed_mps": 8.0}, true, "R1", false)
		audio.update_environment({"wind": 0.3, "traffic": 0.15})
	if phase == "rain_traffic":
		audio.update_environment({"rain": 0.6, "traffic": 0.4, "machinery": 0.2})
		event_started = audio.play_environment_event("vehicle_start", LISTENER_POSITION + Vector3(7, 0, 3))
		audio.play_event("collision")
	_check(event_started, phase + ": requested audio started")
	var begin := Time.get_ticks_msec()
	var first_frame := stereo.size()
	var next_warning := 0.0
	var minimum_duck := 1.0
	var burst_recovery := 0.0
	while Time.get_ticks_msec() - begin < seconds * 1000.0:
		var elapsed := (Time.get_ticks_msec() - begin) / 1000.0
		if phase == "warning_burst" and elapsed >= next_warning:
			audio.play_event("warning")
			next_warning += 0.7
		var state: Dictionary = audio.get_debug_state()
		minimum_duck = minf(minimum_duck, float(state.warning_duck))
		if elapsed >= 2.5: burst_recovery = maxf(burst_recovery, float(state.warning_duck))
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("V22ProbeFader"), linear_to_db(maxf(float(state.mix.master), 0.0001)))
		AudioServer.set_bus_mute(AudioServer.get_bus_index("V22ProbeFader"), bool(state.mix.mute))
		AudioServer.set_bus_volume_db(0, 0.0)
		AudioServer.set_bus_mute(0, false)
		await process_frame
		for bus: String in captures:
			var buffer: PackedVector2Array = captures[bus].get_buffer(captures[bus].get_frames_available())
			if bus == "Master": stereo.append_array(buffer)
			var measure: Dictionary = measurements[bus]
			for sample: Vector2 in buffer:
				measure.samples += 2
				measure.sum_sq += sample.x * sample.x + sample.y * sample.y
				measure.peak = maxf(float(measure.peak), maxf(absf(sample.x), absf(sample.y)))
				if absf(sample.x) + absf(sample.y) > 0.00001: measure.nonzero += 1
				if maxf(absf(sample.x), absf(sample.y)) >= 0.99997: measure.clipped += 1
	var buses: Dictionary = {}
	for bus: String in measurements:
		var measure: Dictionary = measurements[bus]
		var discarded: int = captures[bus].get_discarded_frames() - measure.discarded_start
		buses[bus] = {"rms_dbfs": linear_to_db(maxf(sqrt(float(measure.sum_sq) / maxf(float(measure.samples), 1)), 0.0000001)), "peak": measure.peak, "nonzero_frames": measure.nonzero, "clipped_frames": measure.clipped, "discarded_frames": discarded}
		_check(discarded == 0, phase + ": no capture overflow on " + bus)
	_check(int(buses.Master.clipped_frames) == 0, phase + ": final mix has no clipped frames")
	_check((int(buses.Master.nonzero_frames) == 0) if phase == "muted" else (int(buses.Master.nonzero_frames) > 0), phase + ": expected final output silence/non-silence")
	if not voice_id.is_empty(): _check(int(buses.Voice.nonzero_frames) > 0, phase + ": actual narration samples captured")
	if phase == "bird_spatial": _check(int(buses.Birds.nonzero_frames) > 0, "Actual spatial bird samples captured")
	if phase == "flight": _check(int(buses.Rotor.nonzero_frames) > 0, "Actual rotor samples captured")
	if phase == "rain_traffic": _check(int(buses.Ambient.nonzero_frames) > 0, "Actual rain/traffic ambience samples captured")
	if phase == "warning_burst":
		_check(minimum_duck < 0.7, "Warning causes modest background duck")
		_check(burst_recovery > 0.99, "Repeated warnings have bounded duck with recovery")
	if phase == "warning_release": _check(float(audio.get_debug_state().warning_duck) > 0.99, "Warning release restores background gain")
	stages.append({"phase": phase, "buses": buses, "state": audio.get_debug_state(), "voice_clip": clip,
		"start_frame": first_frame, "end_frame": stereo.size(), "warning_minimum_gain": minimum_duck, "warning_burst_recovery_gain": burst_recovery})
	print("V22_AUDIO_CAPTURE_PHASE ", phase)

func _write_result() -> void:
	var directory := "res://assets/source_audio/v22/evidence"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var bytes := PackedByteArray()
	bytes.resize(stereo.size() * 4)
	for index: int in range(stereo.size()):
		bytes.encode_s16(index * 4, int(clampf(stereo[index].x, -1, 1) * 32767))
		bytes.encode_s16(index * 4 + 2, int(clampf(stereo[index].y, -1, 1) * 32767))
	var output := AudioStreamWAV.new()
	output.format = AudioStreamWAV.FORMAT_16_BITS
	output.stereo = true
	output.mix_rate = int(AudioServer.get_mix_rate())
	output.data = bytes
	_check(output.save_to_wav(ProjectSettings.globalize_path(directory.path_join("engine_mix.wav"))) == OK, "Mix WAV written")
	_check(audio.get_debug_state().missing_assets.is_empty(), "No referenced audio missing")
	var report := {"schema": 2, "captured_at_utc": Time.get_datetime_string_from_system(true), "driver": AudioServer.get_driver_name(),
		"physical_listening_verified": false, "status": "PASS" if failures.is_empty() else "FAIL", "failures": failures,
		"mix_rate": output.mix_rate, "frames": stereo.size(), "seconds": float(stereo.size()) / output.mix_rate,
		"audio_script_sha256": FileAccess.get_sha256("res://scripts/v2/game_audio.gd"), "manifest_sha256": FileAccess.get_sha256("res://assets/audio/v22/manifest.json"),
		"capture_script_sha256": FileAccess.get_sha256("res://scripts_tools/v22_audio_capture.gd"), "spatial_setup": spatial_setup, "stages": stages,
		"scope": "Actual Godot output mix and pre-fader source buses; no microphone, no OS-volume change, no physical speaker/headphone or human listening verification."}
	var file := FileAccess.open(directory.path_join("engine_mix.json"), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	else: failures.append("Could not write capture JSON")
	print(JSON.stringify({"driver": report.driver, "frames": stereo.size(), "output": directory, "failures": failures}))

