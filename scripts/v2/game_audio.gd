class_name GameAudioV2
extends Node

signal voice_started(id: String, text: String)
signal voice_finished(id: String)

const BUS_NAMES: Array[String] = ["Music", "Rotor", "SFX", "Ambient", "Birds", "UI", "Voice"]
const V22_ROOT := "res://assets/audio/v22"
const MUSIC_FADE_SECONDS := 4.0
const ENVIRONMENT_VOICE_LIMIT := 6
const COMBAT_ROOT := "res://assets/audio/v22_combat"
const COMBAT_VOICE_LIMIT := 12
# priority, per-emitter cooldown milliseconds, gain dB, hearing range metres
const COMBAT_RULES := {
	"shot_light": [1, 80, -7.0, 85.0], "shot_heavy": [2, 140, -6.0, 100.0],
	"near_pass": [4, 160, -6.0, 12.0], "impact_metal": [2, 100, -6.0, 65.0],
	"impact_ground": [2, 100, -7.0, 60.0], "impact_water": [2, 150, -6.0, 65.0],
	"shield": [4, 220, -5.0, 70.0], "component": [4, 300, -6.0, 70.0],
	"destroyed": [5, 500, -5.0, 110.0], "wreck": [3, 350, -7.0, 75.0],
	"approach": [1, 1200, -9.0, 65.0], "warning": [6, 1400, -10.0, 65.0],
	"critical": [7, 2800, -8.0, 65.0]
}
const VOICE_ALIASES := {
	"m01_lift": "flight_lift", "m01_hover": "flight_hover", "m01_yaw90": "flight_yaw",
	"m01_forward": "flight_forward", "m01_strafe": "flight_strafe", "m01_brake": "flight_brake",
	"m01_land": "flight_land", "m01_zoom": "flight_zoom", "m02_cargo_pickup": "cargo_pickup",
	"m02_swing": "cargo_swing", "m02_delivery": "cargo_delivery", "m02_wind": "cargo_wind",
	"m03_scan": "scan", "m03_route": "route", "m03_interference": "interference", "m03_cover": "cover",
	"tutorial_complete": "training_complete", "profile": "lobby_profile", "fleet": "lobby_fleet",
	"loadout": "lobby_loadout", "mission": "lobby_mission", "prepare": "lobby_prepare", "complete": "lobby_complete"
}
const VOICE_LIMIT := 10
const EVENT_FILES := {
	"shot": ["shot_1", "shot_2"], "warning": ["warning_1", "warning_2"],
	"collision": ["collision_1", "collision_2"], "scrape": ["scrape_1", "scrape_2"],
	"land": ["land_1", "land_2"], "tool": ["tool_1", "tool_2"],
	"shield": ["shield_1", "shield_2"], "ui": ["ui_1", "ui_2"],
	"reward": ["reward"], "complete": ["complete"],
	"failure": ["failure"], "disconnect": ["disconnect"],
	"takeoff": ["takeoff"], "brake": ["brake"]
}
const ALIASES := {
	"fire": "shot", "shoot": "shot", "player_shot": "shot",
	"enemy_warning": "warning", "warning_started": "warning", "incoming": "warning",
	"frontal": "collision", "collision_frontal": "collision", "damage": "collision",
	"collision_scrape": "scrape", "landing": "land", "landed": "land",
	"tool_started": "tool", "interact": "tool", "scanned": "tool", "scan": "tool",
	"shield_started": "shield", "stage_completed": "reward", "task_stage": "reward",
	"mission_completed": "complete", "task_complete": "complete", "task_completed": "complete",
	"mission_failed": "failure", "phone_disconnected": "disconnect", "discover": "reward",
	"ui_confirm": "ui", "ui_focus": "ui", "confirm": "ui"
}
const COOLDOWN_MS := {
	"shot": 75, "warning": 650, "collision": 150, "scrape": 220, "land": 180,
	"tool": 180, "shield": 250, "ui": 50, "reward": 500, "complete": 1000,
	"failure": 1000, "disconnect": 1000, "takeoff": 1200, "brake": 550
}
const EVENT_PRIORITY := {
	"shot": 1, "scrape": 1, "ui": 2, "tool": 2, "land": 2, "shield": 2,
	"reward": 3, "collision": 3, "warning": 4, "complete": 4, "failure": 4, "disconnect": 5,
	"takeoff": 2, "brake": 1
}

var audio_root := "res://assets/v2/audio"
const DEFAULT_MIX := {"master": 0.8, "music": 0.65, "rotor": 0.85, "sfx": 0.85, "ui": 0.75, "ambient": 0.62, "birds": 0.5, "voice": 1.0, "mute": false}
var _mix: Dictionary = DEFAULT_MIX.duplicate()
var _streams: Dictionary = {}
var _loop_players: Dictionary = {}
var _loop_gains: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _voice_priority: Array[int] = []
var _voice_started: Array[int] = []
var _last_event: Dictionary = {}
var _variation: Dictionary = {}
var _events_played := 0
var _active := false
var _thrust_target := 0.0
var _thrust_smoothed := 0.0
var _speed_target := 0.0
var _flight_state := "landed"
var _region := "R1"
var _night := false
var _environment_key := ""
var _environment_slot := 0
var _environment_settle := 0.0
var _tension_left := 0.0
var _ready_complete := false
var _missing_assets: Array[String] = []
var _braking := false
var _manifest: Dictionary = {}
var _music_catalog: Array = []
var _voice_catalog: Dictionary = {}
var _music_players: Array[AudioStreamPlayer] = []
var _music_slot := 0
var _music_current_id := ""
var _music_next_id := ""
var _music_pending_path := ""
var _music_pending_id := ""
var _music_recent: Array[String] = []
var _music_bag: Array[String] = []
var _music_crossfade := -1.0
var _music_context := "hangar"
var _music_requested_context := ""
var _narrator: AudioStreamPlayer
var _narration_id := ""
var _narration_queue: Array[String] = []
var _narration_duck := 1.0
var _applied_duck := 1.0
var _warning_duck := 1.0
var _applied_warning_duck := 1.0
var _warning_duck_left := 0.0
var _warning_burst_left := 0.0
var _warning_rearm_left := 0.0
var _spatial_voices: Array[AudioStreamPlayer3D] = []
var _listener: AudioListener3D
var _listener_position := Vector3.ZERO
var _environment := {"wind": 0.0, "rain": 0.0, "traffic": 0.0, "machinery": 0.0}
var _bird_timer := 12.0
var _traffic_timer := 15.0
var _rng := RandomNumberGenerator.new()
var _last_bird := -1
var _combat_manifest: Dictionary = {}
var _combat_catalog: Dictionary = {}
var _combat_streams: Dictionary = {}
var _combat_players: Array[AudioStreamPlayer3D] = []
var _combat_slots: Array[Dictionary] = []
var _combat_recent: Dictionary = {}
var _combat_cooldowns: Dictionary = {}
var _combat_variants: Dictionary = {}
var _combat_epoch := ""
var _combat_clock := 0.0
var _combat_occlusion_clock := 0.0
var _combat_cursor := 0
var _combat_played := 0
var _combat_dropped := 0
var _rotor_damage_target := 0.0
var _rotor_damage := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	_apply_mix()
	_rng.randomize()
	_load_catalog()
	for key: String in ["rotor_low", "rotor_mid", "rotor_high", "rotor_unstable"]:
		_add_loop(key, key, "Rotor")
	_add_loop("wind", "wind", "Ambient")
	_add_loop("environment_a", "", "Ambient")
	_add_loop("environment_b", "", "Ambient")
	for key: String in ["rain_00", "traffic", "machinery", "wind"]:
		_add_loop("world_" + key, "v22/environment/" + key, "Ambient")
	for index: int in range(VOICE_LIMIT):
		var voice := AudioStreamPlayer.new()
		voice.name = "Cue%d" % index
		voice.max_polyphony = 1
		voice.bus = "SFX"
		add_child(voice)
		_voices.append(voice)
		_voice_priority.append(0)
		_voice_started.append(0)
	# Prewarm event resources while the menu is open, not on the first combat frame.
	for file_ids: Array in EVENT_FILES.values():
		for file_id: String in file_ids:
			_load_stream(file_id, false)
	_narrator = AudioStreamPlayer.new()
	_narrator.name = "MandarinNarration"
	_narrator.bus = "Voice"
	_narrator.finished.connect(_on_voice_finished)
	add_child(_narrator)
	_listener = AudioListener3D.new()
	_listener.name = "DroneAudioListener"
	add_child(_listener)
	_listener.make_current()
	_setup_combat_audio()
	for index: int in range(ENVIRONMENT_VOICE_LIMIT):
		var spatial := AudioStreamPlayer3D.new()
		spatial.name = "EnvironmentCue%d" % index
		spatial.bus = "Ambient"
		spatial.unit_size = 12.0
		spatial.max_distance = 75.0
		spatial.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		spatial.max_db = -2.0
		add_child(spatial)
		_spatial_voices.append(spatial)
	for index: int in range(2):
		var player := AudioStreamPlayer.new()
		player.name = "Music%d" % index
		player.bus = "Music"
		player.volume_db = -80.0
		add_child(player)
		_music_players.append(player)
	_ready_complete = true
	_change_environment()
	_start_music()

func _ensure_buses() -> void:
	for bus_name: String in BUS_NAMES:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			var bus_index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(bus_index, bus_name)
		# Repair old Ambient -> SFX routing as well as creating independent buses.
		AudioServer.set_bus_send(AudioServer.get_bus_index(bus_name), "Master")
	var master_index := AudioServer.get_bus_index("Master")
	for effect_index: int in range(AudioServer.get_bus_effect_count(master_index)):
		if AudioServer.get_bus_effect(master_index, effect_index) is AudioEffectHardLimiter:
			return
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = -1.0
	limiter.pre_gain_db = 0.0
	limiter.release = 0.1
	AudioServer.add_bus_effect(master_index, limiter)

func set_mix(settings: Dictionary) -> void:
	for key: String in ["master", "music", "rotor", "sfx", "ui", "ambient", "birds", "voice"]:
		var value: Variant = settings.get(key, settings.get(key + "_volume", _mix[key]))
		if key == "master" and not settings.has("master") and not settings.has("master_volume"):
			value = settings.get("volume", value)
		_mix[key] = _safe_number(value, float(_mix[key]), 0.0, 1.0)
	if settings.has("mute") or settings.has("muted"):
		_mix["mute"] = bool(settings.get("mute", settings.get("muted", false)))
	if _ready_complete:
		_apply_mix()

func _apply_mix() -> void:
	for entry: Array in [["master", "Master"], ["music", "Music"], ["rotor", "Rotor"], ["sfx", "SFX"], ["ui", "UI"], ["ambient", "Ambient"], ["birds", "Birds"], ["voice", "Voice"]]:
		var index := AudioServer.get_bus_index(str(entry[1]))
		if index < 0:
			continue
		var gain := _bus_gain(str(entry[0]))
		AudioServer.set_bus_volume_db(index, linear_to_db(gain) if gain > 0.0 else -80.0)
		AudioServer.set_bus_mute(index, gain <= 0.0 or (entry[0] == "master" and bool(_mix["mute"])))

func _bus_gain(key: String) -> float:
	var gain := float(_mix[key])
	# Overlapping narration and warning take the stronger reduction, not their
	# product. Critical cues and the narrator retain their independent levels.
	if key == "music": gain *= minf(_narration_duck, _warning_duck)
	elif key in ["ambient", "birds"]: gain *= minf(lerpf(0.45, 1.0, (_narration_duck - 0.28) / 0.72), lerpf(0.75, 1.0, (_warning_duck - 0.62) / 0.38))
	elif key == "rotor": gain *= minf(lerpf(0.65, 1.0, (_narration_duck - 0.28) / 0.72), lerpf(0.85, 1.0, (_warning_duck - 0.62) / 0.38))
	return gain

func _apply_ducked_buses() -> void:
	for entry: Array in [["music", "Music"], ["rotor", "Rotor"], ["ambient", "Ambient"], ["birds", "Birds"]]:
		var index := AudioServer.get_bus_index(str(entry[1]))
		var gain := _bus_gain(str(entry[0]))
		if index >= 0: AudioServer.set_bus_volume_db(index, linear_to_db(gain) if gain > 0.0 else -80.0)

func update_flight(telemetry: Dictionary, active: bool, region_id: String, night: bool) -> void:
	var previous_state := _flight_state
	var previously_active := _active
	_active = active
	if previously_active and not active: reset_combat_audio()
	# Only actual component telemetry may change the mechanical timbre.
	_rotor_damage_target = maxf(_safe_number(telemetry.get("rotor_damage", 0.0), 0.0, 0.0, 1.0), _safe_number(telemetry.get("motor_damage", 0.0), 0.0, 0.0, 1.0))
	if telemetry.get("position_m") is Vector3 and telemetry.position_m.is_finite():
		_listener_position = telemetry.position_m
		if is_instance_valid(_listener): _listener.global_position = _listener_position
	_thrust_target = _safe_number(telemetry.get("thrust_fraction", 0.0), 0.0, 0.0, 1.0)
	_speed_target = _safe_number(telemetry.get("speed_mps", 0.0), 0.0, 0.0, 60.0)
	_flight_state = str(telemetry.get("flight_state", "landed"))
	var braking := active and bool(telemetry.get("brake_active", false))
	if _ready_complete and active and previously_active:
		if previous_state == "landed" and _flight_state == "flying": play_event("takeoff")
		if previous_state != "landed" and _flight_state == "landed": play_event("land")
		if braking and not _braking and _speed_target > 2.0: play_event("brake")
	_braking = braking
	_region = region_id if region_id in ["R1", "R2", "R3", "R4"] else "R1"
	_night = night
	if _ready_complete:
		_change_environment()

func _change_environment() -> void:
	# No bird recording is baked into the continuous regional bed.
	var key := "v22/environment/bed_" + _region
	if key == _environment_key or _environment_settle > 0.0:
		return
	_environment_key = key
	_environment_slot = 1 - _environment_slot
	_environment_settle = 1.8
	var slot_key := "environment_a" if _environment_slot == 0 else "environment_b"
	var player: AudioStreamPlayer = _loop_players[slot_key]
	player.stop()
	player.volume_db = -80.0
	_loop_gains[slot_key] = 0.0
	player.stream = _load_stream(key, true)
	if player.stream != null:
		player.play()

func _process(delta: float) -> void:
	if not _ready_complete:
		return
	delta = clampf(delta, 0.0, 0.1)
	var paused := get_tree().paused
	var flying := _active and not paused
	for player: AudioStreamPlayer3D in _combat_players: player.stream_paused = paused
	_refresh_combat_headroom()
	# Keep perceived left/right aligned with the fixed oblique view while the
	# listening position remains at the drone, independent of camera zoom.
	var camera := get_viewport().get_camera_3d()
	if is_instance_valid(camera) and is_instance_valid(_listener):
		_listener.global_basis = camera.global_basis.orthonormalized()
	if not paused: _combat_clock += delta
	_rotor_damage = move_toward(_rotor_damage, _rotor_damage_target, delta * 1.5)
	var flight_gain := 1.0 if flying else 0.0
	_thrust_smoothed = lerpf(_thrust_smoothed, _thrust_target if flying else 0.0, 1.0 - exp(-delta / 0.18))
	var power := _thrust_smoothed
	var low := clampf(1.0 - power * 2.0, 0.0, 1.0)
	var high := clampf((power - 0.5) * 2.0, 0.0, 1.0)
	var mid := 1.0 - low - high
	var spinning := flight_gain * (0.22 + 0.72 * power)
	if _flight_state == "landed" and power < 0.05:
		spinning = 0.0
	_set_loop("rotor_low", sqrt(low) * spinning, delta, 0.9 + power * 0.25)
	_set_loop("rotor_mid", sqrt(mid) * spinning, delta, 0.88 + power * 0.24)
	_set_loop("rotor_high", sqrt(high) * spinning, delta, 0.86 + power * 0.24)
	_set_loop("rotor_unstable", maxf(0.32 if _flight_state == "recovering" else 0.0, _rotor_damage * 0.25) * flight_gain, delta, 0.95 - _rotor_damage * 0.07)
	_set_loop("wind", flight_gain * clampf(_speed_target / 20.0, 0.0, 1.0) * 0.55, delta)
	_tension_left = maxf(0.0, _tension_left - delta)
	var tension := 1.0 if _tension_left > 0.0 and flying else 0.0
	var desired_context := _music_requested_context
	if desired_context.is_empty(): desired_context = "action" if tension > 0.0 else ("explore" if _active else "hangar")
	if desired_context != _music_context:
		_music_context = desired_context
		_music_bag.clear()
	_update_music(delta, 0.75 if flying else 0.82)
	var duck_target := 0.28 if _narrator.playing else 1.0
	_narration_duck = move_toward(_narration_duck, duck_target, delta / (0.12 if _narrator.playing else 0.65))
	_warning_rearm_left = maxf(0.0, _warning_rearm_left - delta)
	if _warning_burst_left > 0.0:
		_warning_burst_left = maxf(0.0, _warning_burst_left - delta)
		if _warning_burst_left <= 0.0:
			_warning_duck_left = 0.0
			_warning_rearm_left = 1.0
	_warning_duck_left = maxf(0.0, _warning_duck_left - delta)
	_warning_duck = move_toward(_warning_duck, 0.62 if _warning_duck_left > 0.0 else 1.0, delta * 0.38 / (0.10 if _warning_duck_left > 0.0 else 0.45))
	if absf(_narration_duck - _applied_duck) > 0.002 or absf(_warning_duck - _applied_warning_duck) > 0.002:
		_applied_duck = _narration_duck
		_applied_warning_duck = _warning_duck
		_apply_ducked_buses()
	var environment_gain := (0.52 if flying else 0.10) * (0.75 if _night else 1.0)
	_set_loop("environment_a", environment_gain if _environment_slot == 0 else 0.0, delta, 1.0, 0.45)
	_set_loop("environment_b", environment_gain if _environment_slot == 1 else 0.0, delta, 1.0, 0.45)
	for channel: String in ["wind", "rain", "traffic", "machinery"]:
		var loop_key := "world_rain_00" if channel == "rain" else "world_" + channel
		_set_loop(loop_key, float(_environment[channel]) * flight_gain * 0.55, delta, 1.0, 0.8)
	_update_environment_events(delta, flying)
	_environment_settle = maxf(0.0, _environment_settle - delta)
	if _environment_settle <= 0.0:
		_change_environment()

func _set_loop(key: String, target_gain: float, delta: float, pitch: float = 1.0, smoothing: float = 0.16) -> void:
	var player: AudioStreamPlayer = _loop_players[key]
	var gain := lerpf(float(_loop_gains[key]), target_gain, 1.0 - exp(-delta / smoothing))
	_loop_gains[key] = gain
	player.volume_db = linear_to_db(gain) if gain > 0.0001 else -80.0
	player.pitch_scale = pitch
	if player.stream != null and not player.playing:
		player.play()

func _add_loop(key: String, asset_id: String, bus_name: String) -> void:
	var player := AudioStreamPlayer.new()
	player.name = key
	player.bus = bus_name
	player.volume_db = -80.0
	add_child(player)
	_loop_players[key] = player
	_loop_gains[key] = 0.0
	if not asset_id.is_empty():
		player.stream = _load_stream(asset_id, true)
		if player.stream != null:
			player.play()

func _load_stream(asset_id: String, loop: bool) -> AudioStreamWAV:
	if _streams.has(asset_id):
		return _streams[asset_id] as AudioStreamWAV
	var path := audio_root.path_join(asset_id + ".wav")
	if asset_id.begins_with("v22/"):
		path = V22_ROOT.path_join(asset_id.trim_prefix("v22/") + ".wav")
	var stream: AudioStreamWAV
	# Exported PCKs may contain imported resources without the source-side
	# .import marker. ResourceLoader understands remaps; FileAccess does not.
	if path.begins_with("res://") and ResourceLoader.exists(path, "AudioStreamWAV"):
		stream = ResourceLoader.load(path, "AudioStreamWAV") as AudioStreamWAV
	elif FileAccess.file_exists(path):
		stream = AudioStreamWAV.load_from_file(path)
	if stream == null:
		if asset_id not in _missing_assets:
			_missing_assets.append(asset_id)
			push_warning("V2 audio resource unavailable: " + asset_id)
		return null
	stream = stream.duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
	stream.loop_begin = 0
	stream.loop_end = int(round(stream.get_length() * stream.mix_rate))
	_streams[asset_id] = stream
	return stream

func play_event(event_name: String) -> void:
	if not _ready_complete:
		return
	var key := str(ALIASES.get(event_name, event_name))
	if not EVENT_FILES.has(key):
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_event.get(key, -10000)) < int(COOLDOWN_MS[key]):
		return
	var priority := int(EVENT_PRIORITY[key])
	var voice_index := -1
	for index: int in range(_voices.size()):
		if not _voices[index].playing:
			voice_index = index
			break
	# Never displace a more important cue with a shot or UI tap.
	if voice_index < 0:
		var oldest := now + 1
		for index: int in range(_voices.size()):
			if _voice_priority[index] <= priority and _voice_started[index] < oldest:
				oldest = _voice_started[index]
				voice_index = index
	if voice_index < 0:
		return
	var files: Array = EVENT_FILES[key]
	var variant_index := int(_variation.get(key, 0))
	var stream := _load_stream(str(files[variant_index % files.size()]), false)
	if stream == null:
		return
	_variation[key] = variant_index + 1
	_last_event[key] = now
	_voice_priority[voice_index] = priority
	_voice_started[voice_index] = now
	var voice: AudioStreamPlayer = _voices[voice_index]
	voice.stop()
	voice.bus = "UI" if key in ["ui", "reward", "complete", "failure", "disconnect"] else "SFX"
	voice.stream = stream
	voice.volume_db = -1.0 if key in ["warning", "collision", "disconnect"] else -4.0
	voice.pitch_scale = 1.0
	voice.play()
	_events_played += 1
	if key in ["warning", "disconnect", "failure"] and _warning_rearm_left <= 0.0:
		# Extend a short hold, never accumulate seconds per cue. A warning burst
		# has a hard 2.4 s budget then a 1 s recovery even under repeated alarms.
		if _warning_burst_left <= 0.0: _warning_burst_left = 2.4
		_warning_duck_left = minf(maxf(_warning_duck_left, 0.85), _warning_burst_left)
	if key in ["shot", "warning", "collision", "shield"]:
		_tension_left = 6.0
	elif key in ["complete", "failure", "disconnect"]:
		_tension_left = 0.0

func get_debug_state() -> Dictionary:
	var buses: Dictionary = {}
	for bus_name: String in ["Master", "Music", "Rotor", "SFX", "UI", "Ambient", "Birds", "Voice"]:
		var index := AudioServer.get_bus_index(bus_name)
		buses[bus_name] = {"volume_db": AudioServer.get_bus_volume_db(index), "mute": AudioServer.is_bus_mute(index), "peak_db": maxf(AudioServer.get_bus_peak_volume_left_db(index, 0), AudioServer.get_bus_peak_volume_right_db(index, 0))}
	return {
		"mix": _mix.duplicate(), "thrust": _thrust_smoothed,
		"loop_gains": _loop_gains.duplicate(), "region_asset": _environment_key,
		"tension_left": _tension_left, "events_played": _events_played,
		"voice_limit": _voices.size(), "loaded_streams": _streams.size(),
		"missing_assets": _missing_assets.duplicate(), "audio_driver": AudioServer.get_driver_name(),
		"buses": buses, "output_device": AudioServer.output_device,
		"music_current": _music_current_id, "music_next": _music_next_id,
		"music_position": _music_players[_music_slot].get_playback_position() if not _music_players.is_empty() else 0.0,
		"music_recent": _music_recent.duplicate(), "music_context": _music_context,
		"music_resident_count": _music_resident_count(), "music_pending": _music_pending_id,
		"narration": _narration_id, "narration_duck": _narration_duck,
		"warning_duck": _warning_duck, "warning_duck_left": _warning_duck_left,
		"warning_burst_left": _warning_burst_left, "warning_rearm_left": _warning_rearm_left,
		"combat": get_combat_audio_debug(), "rotor_damage_timbre": _rotor_damage,
		"environment": _environment.duplicate(), "next_bird_seconds": _bird_timer
	}

func preview_mix() -> void:
	# Real narration demonstrates ducking against the currently playing music.
	play_voice("lobby_welcome", true)

func _exit_tree() -> void:
	_ready_complete = false
	# An outstanding threaded load owns a ResourceLoader task until it is taken.
	# Drain it on teardown; do not leave its Ogg page resources alive at quit.
	if not _music_pending_path.is_empty():
		var status := ResourceLoader.load_threaded_get_status(_music_pending_path)
		if status in [ResourceLoader.THREAD_LOAD_IN_PROGRESS, ResourceLoader.THREAD_LOAD_LOADED]:
			ResourceLoader.load_threaded_get(_music_pending_path)
		_music_pending_path = ""
		_music_pending_id = ""
	for player: AudioStreamPlayer in _loop_players.values():
		player.stop()
		player.stream = null
	for voice: AudioStreamPlayer in _voices:
		voice.stop()
		voice.stream = null
	for player: AudioStreamPlayer in _music_players:
		player.stop()
		player.stream = null
	if is_instance_valid(_narrator):
		_narrator.stop()
		_narrator.stream = null
	for player: AudioStreamPlayer3D in _spatial_voices:
		player.stop()
		player.stream = null
	for player: AudioStreamPlayer3D in _combat_players:
		player.stop()
		player.stream = null
	_combat_streams.clear()
	_streams.clear()

func _load_catalog() -> void:
	var path := V22_ROOT.path_join("manifest.json")
	if not FileAccess.file_exists(path):
		_missing_assets.append(path)
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is not Dictionary: return
	_manifest = data
	_music_catalog = _manifest.get("music", [])
	for item: Dictionary in _manifest.get("voice", []):
		_voice_catalog[str(item.get("id", ""))] = item

func set_context(context: String) -> void:
	# Context changes choose future tracks; opening UI never rewinds a track.
	_music_requested_context = context if context in ["hangar", "explore", "action"] else ""

func update_environment(sample: Dictionary) -> void:
	for key: String in ["wind", "rain", "traffic", "machinery"]:
		if sample.has(key): _environment[key] = _safe_number(sample[key], float(_environment[key]), 0.0, 1.0)
	if sample.get("listener_position") is Vector3:
		_listener_position = sample["listener_position"]
		if is_instance_valid(_listener): _listener.global_position = _listener_position
	var region_id := str(sample.get("region_id", _region))
	if region_id in ["R1", "R2", "R3", "R4"]: _region = region_id
	if sample.has("night"): _night = bool(sample["night"])
	if _ready_complete: _change_environment()

func _music_item(id: String) -> Dictionary:
	for item: Dictionary in _music_catalog:
		if str(item.get("id", "")) == id: return item
	return {}

func _choose_music() -> String:
	if _music_catalog.is_empty(): return ""
	if _music_bag.is_empty():
		for item: Dictionary in _music_catalog:
			var id := str(item["id"])
			if _music_context in item.get("contexts", []) and id not in _music_recent:
				_music_bag.append(id)
		# A small action/hangar pool must not force the current track to repeat.
		if _music_bag.is_empty():
			for item: Dictionary in _music_catalog:
				var id := str(item["id"])
				if id not in _music_recent: _music_bag.append(id)
		if _music_bag.is_empty(): return ""
	var index := _rng.randi_range(0, _music_bag.size() - 1)
	var chosen := _music_bag[index]
	_music_bag.remove_at(index)
	return chosen

func _remember_music(id: String) -> void:
	_music_recent.append(id)
	while _music_recent.size() > 2: _music_recent.pop_front()
	_music_bag.erase(id)

func _load_audio_path(path: String, loop: bool = false) -> AudioStream:
	var stream: AudioStream
	if ResourceLoader.exists(path):
		stream = ResourceLoader.load(path, "AudioStream", ResourceLoader.CACHE_MODE_IGNORE) as AudioStream
	elif FileAccess.file_exists(path):
		if path.ends_with(".ogg"): stream = AudioStreamOggVorbis.load_from_file(path)
		elif path.ends_with(".wav"): stream = AudioStreamWAV.load_from_file(path)
	if stream is AudioStreamOggVorbis: (stream as AudioStreamOggVorbis).loop = loop
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
	if stream == null and path not in _missing_assets: _missing_assets.append(path)
	return stream

func _start_music() -> void:
	_music_current_id = _choose_music()
	if _music_current_id.is_empty(): return
	var item := _music_item(_music_current_id)
	var player := _music_players[_music_slot]
	player.stream = _load_audio_path(V22_ROOT.path_join(str(item["file"])))
	if player.stream == null: return
	player.play()
	_remember_music(_music_current_id)
	_request_next_music()

func _request_next_music() -> void:
	if not _music_pending_path.is_empty() or not _music_next_id.is_empty(): return
	_music_pending_id = _choose_music()
	if _music_pending_id.is_empty(): return
	var item := _music_item(_music_pending_id)
	_music_pending_path = V22_ROOT.path_join(str(item["file"]))
	# At most the current player and a single pending/next stream are retained.
	if ResourceLoader.exists(_music_pending_path):
		var error := ResourceLoader.load_threaded_request(_music_pending_path, "AudioStream", false, ResourceLoader.CACHE_MODE_IGNORE)
		if error != OK:
			_missing_assets.append(_music_pending_path)
			_music_pending_path = ""
			_music_pending_id = ""
	else:
		_music_players[1 - _music_slot].stream = _load_audio_path(_music_pending_path)
		_music_next_id = _music_pending_id
		_music_pending_path = ""
		_music_pending_id = ""

func _poll_next_music() -> void:
	if _music_pending_path.is_empty(): return
	var status := ResourceLoader.load_threaded_get_status(_music_pending_path)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		var stream := ResourceLoader.load_threaded_get(_music_pending_path) as AudioStream
		if stream is AudioStreamOggVorbis: (stream as AudioStreamOggVorbis).loop = false
		_music_players[1 - _music_slot].stream = stream
		_music_next_id = _music_pending_id
		_music_pending_path = ""
		_music_pending_id = ""
	elif status in [ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE]:
		_missing_assets.append(_music_pending_path)
		_music_pending_path = ""
		_music_pending_id = ""

func _update_music(delta: float, gain: float) -> void:
	if _music_players.is_empty(): return
	_poll_next_music()
	var current := _music_players[_music_slot]
	var next := _music_players[1 - _music_slot]
	if current.stream == null: return
	var remaining := current.stream.get_length() - current.get_playback_position()
	# Re-select the one preloaded successor after a context change. The old
	# successor is released before loading another, preserving the two-track cap.
	if _music_crossfade < 0.0 and remaining > MUSIC_FADE_SECONDS + 1.0 and not _music_next_id.is_empty():
		var preferred_available := false
		for item: Dictionary in _music_catalog:
			if _music_context in item.get("contexts", []) and str(item["id"]) not in _music_recent:
				preferred_available = true
		if preferred_available and _music_context not in _music_item(_music_next_id).get("contexts", []):
			next.stream = null
			_music_next_id = ""
			_request_next_music()
	if _music_crossfade < 0.0 and next.stream != null and (remaining <= MUSIC_FADE_SECONDS or not current.playing):
		_music_crossfade = 0.0
		next.play()
	if _music_crossfade >= 0.0:
		_music_crossfade += delta
		var blend := clampf(_music_crossfade / MUSIC_FADE_SECONDS, 0.0, 1.0)
		current.volume_db = linear_to_db(maxf(gain * cos(blend * PI * 0.5), 0.0001))
		next.volume_db = linear_to_db(maxf(gain * sin(blend * PI * 0.5), 0.0001))
		if blend >= 1.0:
			current.stop()
			current.stream = null
			_music_slot = 1 - _music_slot
			_music_current_id = _music_next_id
			_music_next_id = ""
			_music_crossfade = -1.0
			_remember_music(_music_current_id)
			_request_next_music()
	else:
		current.volume_db = linear_to_db(maxf(gain, 0.0001))
		next.volume_db = -80.0
		if _music_next_id.is_empty() and _music_pending_id.is_empty(): _request_next_music()

func _music_resident_count() -> int:
	var count := 0
	for player: AudioStreamPlayer in _music_players:
		if player.stream != null: count += 1
	return count + (1 if not _music_pending_path.is_empty() else 0)

func voice_text(id: String) -> String:
	var key := str(VOICE_ALIASES.get(id, id))
	return str(_voice_catalog.get(key, {}).get("text", ""))

func play_voice(id: String, interrupt: bool = false) -> bool:
	if id.is_empty() and interrupt:
		stop_voice()
		return true
	if not _ready_complete or not _voice_catalog.has(str(VOICE_ALIASES.get(id, id))): return false
	if interrupt: stop_voice()
	if _narrator.playing:
		if id == _narration_id or id in _narration_queue: return false
		if _narration_queue.size() >= 4: return false
		_narration_queue.append(id)
		return true
	var key := str(VOICE_ALIASES.get(id, id))
	var item: Dictionary = _voice_catalog[key]
	_narrator.stream = _load_audio_path(V22_ROOT.path_join(str(item["file"])))
	if _narrator.stream == null: return false
	_narration_id = id
	_narrator.volume_db = 0.0
	_narrator.play()
	voice_started.emit(id, str(item["text"]))
	return true

func stop_voice() -> void:
	_narration_queue.clear()
	if not is_instance_valid(_narrator): return
	_narrator.stop()
	_narrator.stream = null
	var stopped := _narration_id
	_narration_id = ""
	if not stopped.is_empty(): voice_finished.emit(stopped)

func _on_voice_finished() -> void:
	var finished := _narration_id
	_narration_id = ""
	_narrator.stream = null
	if not finished.is_empty(): voice_finished.emit(finished)
	if not _narration_queue.is_empty(): play_voice(_narration_queue.pop_front())

func play_environment_event(id: String, position: Vector3 = Vector3.ZERO) -> bool:
	if not _ready_complete: return false
	var key := id
	var bird := id.begins_with("bird")
	if id in ["bird", "birds"]:
		var choice := _rng.randi_range(0, 6)
		if choice >= _last_bird: choice += 1
		_last_bird = choice
		key = "bird_%02d" % choice
	elif id in ["vehicle", "vehicle_pass", "car_pass"]: key = "vehicle_pass_%d" % _rng.randi_range(0, 2)
	elif id in ["mechanical", "machinery"]: key = "mechanical_%d" % _rng.randi_range(0, 2)
	elif id == "collision": key = "mechanical_0"
	elif id in ["weather_selected","fan_disabled","fan_enabled","platform_locked","platform_unlocked","dock_locked","dock_unlocked","crane_warning","platform_arrival"]: key = "mechanical_1"
	elif id in ["interference_enter","interference_exit","environment_warning","event_warning"]:
		play_event("warning")
		return true
	elif id not in ["vehicle_start"] and not id.begins_with("bird_") and not id.begins_with("mechanical_") and not id.begins_with("vehicle_pass_"): return false
	var now := Time.get_ticks_msec()
	var cooldown_key := "environment:" + id
	if now - int(_last_event.get(cooldown_key, -10000)) < (2000 if bird else 750): return false
	var selected: AudioStreamPlayer3D
	var birds_playing := 0
	for spatial: AudioStreamPlayer3D in _spatial_voices:
		if spatial.playing and spatial.bus == "Birds": birds_playing += 1
		if not spatial.playing and selected == null: selected = spatial
	if selected == null or (bird and birds_playing >= 2): return false
	var stream := _load_stream("v22/environment/" + key, false)
	if stream == null: return false
	_last_event[cooldown_key] = now
	selected.stream = stream
	selected.bus = "Birds" if bird else "Ambient"
	selected.global_position = position
	selected.volume_db = (-2.0 if bird else -3.0) + _rng.randf_range(-1.5, 1.0)
	selected.pitch_scale = _rng.randf_range(0.97, 1.03)
	selected.play()
	return true

func _update_environment_events(delta: float, flying: bool) -> void:
	if not flying: return
	_bird_timer -= delta
	_traffic_timer -= delta
	if _bird_timer <= 0.0:
		_bird_timer = _rng.randf_range(12.0, 30.0)
		if not _night and _region in ["R1", "R2", "R3"] and float(_environment["rain"]) < 0.5:
			var angle := _rng.randf_range(0.0, TAU)
			var distance := _rng.randf_range(14.0, 32.0)
			play_environment_event("bird", _listener_position + Vector3(cos(angle) * distance, 3.0, sin(angle) * distance))
	if _traffic_timer <= 0.0:
		_traffic_timer = _rng.randf_range(16.0, 32.0)
		if float(_environment["traffic"]) > 0.1:
			play_environment_event("vehicle_pass", _listener_position + Vector3(_rng.randf_range(-25.0, 25.0), -2.0, 18.0))

func get_audio_credits() -> String:
	return str(_manifest.get("credits_text", "")) + "\n\n" + get_combat_audio_credits()

func _setup_combat_audio() -> void:
	var path := COMBAT_ROOT.path_join("manifest.json")
	if not FileAccess.file_exists(path):
		_missing_assets.append(path)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary: return
	_combat_manifest = parsed
	for item: Dictionary in parsed.get("files", []):
		var family := str(item.get("family", ""))
		if not COMBAT_RULES.has(family): continue
		var stream := _load_audio_path(COMBAT_ROOT.path_join(str(item.file)))
		if stream == null: continue
		_combat_streams[str(item.id)] = stream
		if not _combat_catalog.has(family): _combat_catalog[family] = []
		_combat_catalog[family].append(str(item.id))
	for index: int in COMBAT_VOICE_LIMIT:
		var player := AudioStreamPlayer3D.new()
		player.name = "CombatCue%d" % index
		player.bus = "SFX"
		player.max_polyphony = 1
		player.unit_size = 12.0
		player.max_db = -3.0
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(player)
		_combat_players.append(player)
		_combat_slots.append({"family":"", "priority":0, "time":0.0, "gain":-10.0, "occluded":false})

func _combat_position(value: Variant) -> Vector3:
	if value is Vector3: return value if value.is_finite() else Vector3.INF
	if value is Array and value.size() == 3:
		for number: Variant in value:
			if not (number is float or number is int) or not is_finite(float(number)): return Vector3.INF
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.INF

func _combat_family(event: Dictionary) -> String:
	var kind := str(event.get("kind", ""))
	match kind:
		"shot", "weapon_shot":
			var weapon := str(event.get("weapon_id", ""))
			return "shot_heavy" if weapon.contains("heavy") or weapon.contains("charge") or weapon.contains("cannon") or weapon in ["burst_capacitor","suppressor","boss"] else "shot_light"
		"near_pass", "nearpass": return "near_pass"
		"shield_absorbed", "shield", "shield_hit": return "shield"
		"component", "component_damaged", "component_destroyed":
			return "component" if _safe_number(event.get("component_damage", 0.0), 0.0, 0.0, 10000.0) > 0.0 else ""
		"destroyed", "falling": return "destroyed"
		"wreck_impact", "wreck", "wreck_landed": return "impact_water" if str(event.get("surface", "")) == "water" else "wreck"
		"approach", "flyby", "reinforcement_call": return "approach"
		"warning_started", "warning": return "warning" if bool(event.get("pilot_target", false)) else ""
		"critical_warning", "critical": return "critical" if bool(event.get("pilot_target", false)) else ""
		"hit", "impact":
			var surface := str(event.get("surface", ""))
			if surface in ["water", "river", "sea"]: return "impact_water"
			if surface in ["ground", "concrete", "asphalt", "soil", "stone", "wall"]: return "impact_ground"
			return "impact_metal" if surface == "metal" or not str(event.get("target_id", "")).is_empty() else "impact_ground"
	return ""

func play_combat_event(event: Dictionary) -> bool:
	# Receives committed world events only. This method does not create hits,
	# enemy detection, UI markers, identity announcements or gameplay receipts.
	if not _ready_complete or get_tree().paused or event.get("audible", true) == false: return false
	var family := _combat_family(event)
	if not _combat_catalog.has(family): return false
	var position := _combat_position(event.get("position"))
	if family in ["shot_light", "shot_heavy", "approach"]:
		var origin := _combat_position(event.get("source_position"))
		if origin.is_finite(): position = origin
	if not position.is_finite(): return false
	var distance := position.distance_to(_listener_position)
	var rule: Array = COMBAT_RULES[family]
	if distance > float(rule[3]) or (family == "near_pass" and distance > 6.0): return false
	var unique := str(event.get("receipt_id", event.get("event_id", "")))
	var event_key := _combat_epoch + ":" + str(event.get("kind", "")) + ":" + unique
	if not unique.is_empty() and _combat_recent.has(event_key): return false
	var emitter := str(event.get("target_id", "")) if family.begins_with("impact") else str(event.get("source_id", ""))
	var cooldown_key := family if family in ["warning", "critical"] else family + ":" + emitter
	if (_combat_clock - float(_combat_cooldowns.get(cooldown_key, -100.0))) * 1000.0 < float(rule[1]): return false
	var selected := -1
	var same_family := 0
	var oldest := INF
	for index: int in _combat_players.size():
		if not _combat_players[index].playing:
			if selected < 0: selected = index
		elif _combat_slots[index].family == family: same_family += 1
	if (family == "near_pass" and same_family >= 2) or (family.begins_with("shot_") and same_family >= 5):
		_combat_dropped += 1
		return false
	if selected < 0:
		for index: int in _combat_players.size():
			if int(_combat_slots[index].priority) <= int(rule[0]) and float(_combat_slots[index].time) < oldest:
				oldest = float(_combat_slots[index].time)
				selected = index
	if selected < 0:
		_combat_dropped += 1
		return false
	if not unique.is_empty():
		_combat_recent[event_key] = _combat_clock
		while _combat_recent.size() > 256: _combat_recent.erase(_combat_recent.keys()[0])
	_combat_cooldowns[cooldown_key] = _combat_clock
	while _combat_cooldowns.size() > 128: _combat_cooldowns.erase(_combat_cooldowns.keys()[0])
	var variants: Array = _combat_catalog[family]
	var previous := int(_combat_variants.get(family, -1))
	var choice := _rng.randi_range(0, variants.size() - 2) if variants.size() > 1 and previous >= 0 else _rng.randi_range(0, variants.size() - 1)
	if variants.size() > 1 and choice >= previous and previous >= 0: choice += 1
	_combat_variants[family] = choice
	var player := _combat_players[selected]
	player.stop()
	player.stream = _combat_streams[str(variants[choice])]
	player.global_position = position
	player.max_distance = float(rule[3])
	player.pitch_scale = 1.0 if family in ["warning", "critical"] else _rng.randf_range(0.97, 1.03)
	player.volume_db = float(rule[2])
	_combat_slots[selected] = {"family":family, "priority":int(rule[0]), "time":_combat_clock, "gain":float(rule[2]), "occluded":false, "asset":str(variants[choice])}
	player.play()
	_refresh_combat_headroom()
	_combat_played += 1
	if family in ["warning", "critical"] and _warning_rearm_left <= 0.0:
		if _warning_burst_left <= 0.0: _warning_burst_left = 2.4
		_warning_duck_left = minf(maxf(_warning_duck_left, 0.85), _warning_burst_left)
	return true

func _refresh_combat_headroom() -> void:
	var active := 0
	for player: AudioStreamPlayer3D in _combat_players:
		if player.playing: active += 1
	# Each source peaks below -7 dBFS. A summed maximum gain of 2 leaves
	# approximately 1 dB headroom even for coherent, simultaneous waveforms.
	var ceiling := minf(-3.0, linear_to_db(2.0 / maxf(1.0, float(active))))
	for player: AudioStreamPlayer3D in _combat_players: player.max_db = ceiling

func _physics_process(delta: float) -> void:
	if not _ready_complete or get_tree().paused or _combat_players.is_empty(): return
	_combat_occlusion_clock += delta
	if _combat_occlusion_clock < 0.1: return
	_combat_occlusion_clock = 0.0
	# Two static-world rays per 100 ms, round robin. Never inspect enemy metadata.
	var space := _listener.get_world_3d().direct_space_state
	var checked := 0
	for offset: int in _combat_players.size():
		var index := (_combat_cursor + offset) % _combat_players.size()
		var player := _combat_players[index]
		if not player.playing: continue
		var query := PhysicsRayQueryParameters3D.create(_listener_position, player.global_position, 1)
		var hit := space.intersect_ray(query)
		var blocked := not hit.is_empty() and _listener_position.distance_to(hit.position) < _listener_position.distance_to(player.global_position) - 0.5
		_combat_slots[index].occluded = blocked
		player.volume_db = float(_combat_slots[index].gain) - (10.0 if blocked else 0.0)
		checked += 1
		if checked >= 2:
			_combat_cursor = (index + 1) % _combat_players.size()
			break

func reset_combat_audio(epoch: String = "") -> void:
	_combat_epoch = epoch
	_combat_recent.clear()
	_combat_cooldowns.clear()
	for player: AudioStreamPlayer3D in _combat_players:
		player.stop()
		player.stream = null

func get_combat_audio_debug() -> Dictionary:
	var active := 0
	var near_pass := 0
	for index: int in _combat_players.size():
		if _combat_players[index].playing:
			active += 1
			if _combat_slots[index].family == "near_pass": near_pass += 1
	return {"voice_limit":COMBAT_VOICE_LIMIT, "active_voices":active, "near_pass_voices":near_pass, "loaded_streams":_combat_streams.size(), "played":_combat_played, "dropped":_combat_dropped, "dedup_entries":_combat_recent.size(), "cooldown_entries":_combat_cooldowns.size(), "last_slots":_combat_slots.duplicate(true)}

func get_combat_audio_credits() -> String:
	return str(_combat_manifest.get("credits_text", ""))

func _safe_number(value: Variant, fallback: float, low: float, high: float) -> float:
	if value is not float and value is not int:
		return fallback
	var number := float(value)
	return clampf(number, low, high) if is_finite(number) else fallback
