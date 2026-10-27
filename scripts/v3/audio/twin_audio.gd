class_name TwinAudioV3
extends Node3D
## Local presentation only: no gameplay decisions, networking, or Store writes.
## One instance per session. bind_session() supplies the normal V3 state adapter;
## play_event() is the explicit hook for committed gameplay/network events.

const CATALOG_PATH := "res://data/v3/audio/cues.json"
const ContentSounds = preload("res://scripts/v3/content/presentation_next/twin_content_sound_routes.gd")
const ContentSounds88 = preload("res://scripts/v3/content/dev88_presentation/twin_dev88_sound_routes.gd")
const FinalSounds = preload("res://scripts/v3/content/final_flow/twin_final_voice_routes.gd")
const SETTINGS_PATH := "user://settings_v3/audio.cfg"
const SPATIAL_LIMIT := 14
const UI_LIMIT := 4
const BUS_NAMES := {"master":"V3Master", "music":"V3Music", "sfx":"V3SFX", "ambient":"V3Ambient", "rotor":"V3Rotor", "ui":"V3UI"}
const DEFAULT_MIX := {"master":0.8, "music":0.65, "sfx":0.85, "ambient":0.65, "rotor":0.8, "ui":0.75, "mute":false}

var _session: WeakRef
var _catalog: Dictionary = {}
var _streams: Dictionary = {}
var _loops: Dictionary = {}
var _loop_levels: Dictionary = {}
var _spatial: Array[AudioStreamPlayer3D] = []
var _ui: Array[AudioStreamPlayer] = []
var _slots: Array[Dictionary] = []
var _ui_slots: Array[Dictionary] = []
var _listener: AudioListener3D
var _listener_ready := false
var _mix: Dictionary = DEFAULT_MIX.duplicate()
var _cooldowns: Dictionary = {}
var _variants: Dictionary = {}
var _recent_ids: Array[String] = []
var _clock := 0.0
var _region := "I1"
var _active := false
var _paused := false
var _boss := false
var _thrust := 0.0
var _speed := 0.0
var _flight_enabled := false
var _previous_telemetry: Dictionary = {}
var _observed_key := ""
var _objective_count := -1
var _action_count := -1
var _missing: Array[String] = []
var _events_played := 0
var _events_dropped := 0
var _ready_complete := false
var _radio_slot := -1
var _radio_token := 0
var _shutdown_started := false
var _shutdown_usec := 0
var _shutdown_refs: Array[Dictionary] = []
var _shutdown_seen: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	_load_settings()
	_apply_mix()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if not parsed is Dictionary or int(parsed.get("schema", 0)) != 1:
		push_warning("V3 audio cue catalog is missing or incompatible")
		return
	_catalog = parsed
	_catalog.events.merge(ContentSounds.event_definitions(), false)
	_catalog.events.merge(ContentSounds88.event_definitions(), false)
	_catalog.events.merge(FinalSounds.event_definitions(), false)
	_remove_unreleased_voice_cues()
	_listener = AudioListener3D.new()
	_listener.name = "PilotAudioListener"
	add_child(_listener)
	for index in range(SPATIAL_LIMIT):
		var voice := AudioStreamPlayer3D.new()
		voice.name = "SpatialCue%d" % index
		voice.bus = BUS_NAMES.sfx
		voice.max_polyphony = 1
		voice.unit_size = 10.0
		voice.max_db = -2.0
		voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		voice.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		add_child(voice)
		_spatial.append(voice)
		_slots.append({"priority":0,"started":0.0,"deadline":0.0})
	for index in range(UI_LIMIT):
		var voice := AudioStreamPlayer.new()
		voice.name = "UICue%d" % index
		voice.bus = BUS_NAMES.ui
		voice.max_polyphony = 1
		add_child(voice)
		_ui.append(voice)
		_ui_slots.append({"priority":0,"started":0.0,"deadline":0.0})
	# Prewarm while the menu is open. PCKs use ResourceLoader's resource remaps.
	for cue: Dictionary in _catalog.get("events", {}).values():
		for path in cue.files: _stream(str(path), false)
	for id in _catalog.get("loops", {}):
		var definition: Dictionary = _catalog.loops[id]
		var player := AudioStreamPlayer.new()
		player.name = str(id)
		player.bus = str(BUS_NAMES[definition.bus])
		player.volume_db = -80.0
		player.stream = _stream(str(definition.file), true)
		add_child(player)
		_loops[id] = player
		_loop_levels[id] = 0.0
		if player.stream != null: player.play()
	_ready_complete = true

func _remove_unreleased_voice_cues() -> void:
	# Public archive policy: authored captions remain available. Speech WAVs made
	# with Windows voices are withheld until their redistribution rights are clear.
	# Other missing sounds still follow the normal warning/diagnostic behavior.
	var prefixes := ["res://assets/v3/content/presentation_next/", "res://assets/v3/content/dev88_presentation/", "res://assets/v3/content/final_flow/", "res://assets/v3/content/final_presentation/"]
	for cue_id in _catalog.events.keys():
		var cue: Dictionary = _catalog.events[cue_id]
		var files: Array = cue.get("files", [])
		if files.is_empty(): continue
		var withheld := true
		for item in files:
			var file := str(item)
			var voice_path := false
			for prefix in prefixes:
				if file.begins_with(str(prefix)): voice_path = true; break
			if not voice_path or FileAccess.file_exists(file) or ResourceLoader.exists(file):
				withheld = false
				break
		if withheld: _catalog.events.erase(cue_id)

func bind_session(owner_session: Node) -> void:
	_session = weakref(owner_session)
	_observed_key = ""

func set_listener(at: Vector3, orientation: Basis = Basis.IDENTITY) -> void:
	if not _ready_complete or not at.is_finite() or not orientation.is_finite(): return
	_listener.global_transform = Transform3D(orientation.orthonormalized(), at)
	_listener.make_current()
	_listener_ready = true

func set_context(region: String, active: bool, boss: bool = false, paused: bool = false) -> void:
	if _shutdown_started: return
	if region != _region or (_active and not active): release_region()
	_region = region
	_active = active
	_boss = active and boss
	set_paused(paused)

func set_paused(paused: bool) -> void:
	if paused == _paused: return
	_paused = paused
	for voice in _spatial: voice.stream_paused = paused
	for id in _loops:
		# Music continues quietly through the shared pause. World and rotor time
		# stop together; menu confirmations remain usable.
		if str(_catalog.loops[id].bus) != "music": _loops[id].stream_paused = paused

func update_flight(telemetry: Dictionary, enabled: bool = true) -> void:
	_flight_enabled = enabled
	if not _active or _paused:
		_thrust = 0.0
		_speed = 0.0
		return
	_thrust = _number(telemetry.get("thrust_fraction", 0.0), 0.0, 1.0) if enabled else 0.0
	_speed = _number(telemetry.get("speed_mps", 0.0), 0.0, 60.0) if enabled else 0.0
	if not _previous_telemetry.is_empty():
		var at: Vector3 = _listener.global_position
		if bool(telemetry.get("brake_active", false)) and not bool(_previous_telemetry.get("brake_active", false)) and _speed > 2.0:
			play_event("brake", at, {"emitter":"local_flight"})
		var grounded := bool(telemetry.get("grounded", false))
		var was_grounded := bool(_previous_telemetry.get("grounded", false))
		if grounded != was_grounded: play_event("land" if grounded else "takeoff", at, {"emitter":"local_flight"})
		var health := _number(telemetry.get("health", 100.0), 0.0, 100000.0)
		var old_health := _number(_previous_telemetry.get("health", health), 0.0, 100000.0)
		if health + 0.01 < old_health:
			play_event("damage", at, {"emitter":"local_damage"})
		# Disabled/restored are accepted owner lifecycle events, not sampled edges.
	_previous_telemetry = telemetry.duplicate()

## One-shot event interface. Spatial cues need a valid local listener and active
## world; UI cues are nonspatial and also work in the hangar/shared pause.
func play_event(cue_id: String, at: Vector3 = Vector3.ZERO, options: Dictionary = {}) -> bool:
	if not _ready_complete or not at.is_finite() or not _catalog.events.has(cue_id): return false
	var definition: Dictionary = _catalog.events[cue_id]
	var is_ui := str(definition.bus) == "ui"
	if not is_ui and (not _active or _paused or not _listener_ready): return false
	if not is_ui and _listener.global_position.distance_to(at) > float(definition.range_m):
		_events_dropped += 1
		return false
	var event_id := str(options.get("id", ""))
	if not event_id.is_empty() and event_id in _recent_ids: return false
	var emitter := str(options.get("emitter", "world"))
	var cooldown_key := cue_id + ":" + emitter
	if _clock < float(_cooldowns.get(cooldown_key, -1.0)): return false
	var index := _choose_voice(is_ui, int(definition.priority))
	if index < 0:
		_events_dropped += 1
		return false
	var files: Array = definition.files
	var variant := int(_variants.get(cue_id, 0)) % files.size()
	var sound := _stream(str(files[variant]), false)
	if sound == null: return false
	_variants[cue_id] = variant + 1
	var voice = _ui[index] if is_ui else _spatial[index]
	voice.stop()
	voice.stream = sound
	voice.stream_paused = false
	voice.pitch_scale = _number(options.get("pitch", 1.0), 0.8, 1.2)
	voice.volume_db = float(definition.gain_db)
	if not is_ui:
		voice.global_position = at
		voice.max_distance = float(definition.range_m)
	voice.play()
	var slots: Array[Dictionary] = _ui_slots if is_ui else _slots
	slots[index] = {"priority":int(definition.priority),"started":_clock,"deadline":_clock + sound.get_length() / voice.pitch_scale + 0.25}
	if is_ui and bool(options.get("radio", false)):
		_radio_token += 1
		_radio_slot = index
		slots[index]["radio_token"] = _radio_token
	_cooldowns[cooldown_key] = _clock + float(definition.cooldown_ms) / 1000.0
	if not event_id.is_empty():
		_recent_ids.append(event_id)
		if _recent_ids.size() > 128: _recent_ids.pop_front()
	_events_played += 1
	return true

func play_radio(cue: String) -> bool:
	stop_radio()
	return play_event(cue, Vector3.ZERO, {"emitter":"dialogue", "radio":true})

func stop_radio() -> void:
	if _radio_slot >= 0 and _radio_slot < _ui.size() and int(_ui_slots[_radio_slot].get("radio_token", -1)) == _radio_token:
		_ui[_radio_slot].stop()
		_ui[_radio_slot].stream = null
		_ui_slots[_radio_slot] = {"priority":0,"started":0.0,"deadline":0.0}
	_radio_slot = -1

## Transport owns sender/session/sequence validation before calling this method.
## This method validates the cue and finite position, and never rebroadcasts it.
func receive_event(event: Dictionary) -> bool:
	if str(event.get("kind", "")) != "audio": return false
	var at: Variant = event.get("position", Vector3.ZERO)
	if at is Array and at.size() == 3:
		for value in at:
			if not (value is int or value is float): return false
		at = Vector3(float(at[0]), float(at[1]), float(at[2]))
	if not at is Vector3 or not at.is_finite(): return false
	var cue := str(event.get("cue", ""))
	if cue in ["disabled", "revived"]:
		var owner_session: Variant = _session.get_ref() if _session!=null else null
		if not is_instance_valid(owner_session) or not is_instance_valid(owner_session.network) or not event.get("owner_id") is int or event.owner_id!=owner_session.network.local_id(): return false
		if not owner_session.active or owner_session.simulation_paused or not _listener_ready: return false
		# A self cue follows the listener, even before a retry pose snapshot arrives.
		at = _listener.global_position
	return play_event(cue, at, {"emitter":str(event.get("emitter", "remote")),"id":str(event.get("event_id", ""))})

func set_mix(settings: Dictionary, persist: bool = true) -> void:
	for key in BUS_NAMES:
		if settings.has(key): _mix[key] = _number(settings[key], 0.0, 1.0)
	if settings.has("mute"): _mix.mute = bool(settings.mute)
	if _ready_complete: _apply_mix()
	if persist:
		var config := ConfigFile.new()
		for key in _mix: config.set_value("audio", str(key), _mix[key])
		var error := DirAccess.make_dir_recursive_absolute("user://settings_v3")
		if error == OK or error == ERR_ALREADY_EXISTS:
			error = config.save(SETTINGS_PATH)
		if error != OK: push_warning("Audio preferences could not be saved: " + error_string(error))

func get_mix() -> Dictionary:
	return _mix.duplicate()

func preview_mix() -> bool:
	return play_event("ui_confirm")

func release_region() -> void:
	stop_radio()
	for voice in _spatial: voice.stop()
	for slot in _slots:
		slot.priority = 0
		slot.started = 0.0
		slot.deadline = 0.0
	_previous_telemetry.clear()
	_cooldowns.clear()
	_recent_ids.clear()
	_thrust = 0.0
	_speed = 0.0
	_flight_enabled = false
	_objective_count = -1
	_action_count = -1
	_listener_ready = false

## Terminal, idempotent release. Session calls this after its final successful
## save, BEFORE tree.quit(), then polls shutdown_status on ordinary main frames.
## Godot4.7.2 stop queues native fade/deletion; a stopped player alone is not
## proof that AudioServer has released its playback and associated WAV yet.
func shutdown() -> void:
	if _shutdown_started: return
	_shutdown_started = true
	_shutdown_usec = Time.get_ticks_usec()
	_ready_complete = false
	set_process(false)
	_session = null
	_active = false
	for sound: AudioStream in _streams.values(): _watch_shutdown_ref(sound, "stream")
	for voice in _spatial: _detach_shutdown_voice(voice)
	for voice in _ui: _detach_shutdown_voice(voice)
	for player in _loops.values(): _detach_shutdown_voice(player)
	_spatial.clear()
	_ui.clear()
	_loops.clear()
	_streams.clear() # Only our duplicated streams; never alter imported resources.
	release_region()
	if is_instance_valid(_listener): _listener.clear_current()

func _watch_shutdown_ref(value: Object, kind: String) -> void:
	if not is_instance_valid(value): return
	var id := str(value.get_instance_id())
	if _shutdown_seen.has(id): return
	_shutdown_seen[id] = true
	_shutdown_refs.append({"kind":kind,"class":value.get_class(),"id":id,"ref":weakref(value)})

func _detach_shutdown_voice(voice: Node) -> void:
	if not is_instance_valid(voice): return
	_watch_shutdown_ref(voice.stream, "stream")
	if voice.has_stream_playback():
		_watch_shutdown_ref(voice.get_stream_playback(), "playback")
	voice.stop()
	voice.stream = null # set_stream disconnects stream callbacks and clears its Ref.
	# Terminal only: 3D can retain its queued setplayback after stop() cancels
	# the first physics handoff. Releasing our native node drops that owner.
	voice.queue_free()

## Observation only: weak references neither prolong playback nor force the
## server's private mix/cleanup. Caller owns a bounded final-exit wait and must
## retain pending diagnostics if the original native references do not drain.
func shutdown_status() -> Dictionary:
	var pending: Array = []
	for record: Dictionary in _shutdown_refs:
		if is_instance_valid(record.ref.get_ref()):
			pending.append({"kind":record.kind,"class":record["class"],"id":record.id})
	return {"started":_shutdown_started,"ready":_shutdown_started and pending.is_empty(),
		"elapsed_usec":Time.get_ticks_usec()-_shutdown_usec if _shutdown_started else 0,
		"tracked_references":_shutdown_refs.size(),"pending_references":pending.size(),
		"pending":pending,"own_stream_cache_entries":_streams.size()}

func diagnostics() -> Dictionary:
	var active_voices := 0
	for voice in _spatial:
		if voice.playing: active_voices += 1
	return {"ready":_ready_complete,"region":_region,"active":_active,"paused":_paused,"spatial_limit":SPATIAL_LIMIT,"ui_limit":UI_LIMIT,"active_spatial":active_voices,"played":_events_played,"dropped":_events_dropped,"missing":_missing.duplicate(),"mix":get_mix()}

func _process(delta: float) -> void:
	if not _ready_complete: return
	if _session != null:
		var owner_session: Variant = _session.get_ref()
		if is_instance_valid(owner_session): _observe_session(owner_session)
	# The local clock keeps UI cooldowns usable while gameplay is paused. Move
	# paused voice deadlines with it so an unpause resumes, rather than kills,
	# a sound which was partway through playing.
	_clock += maxf(0.0, delta)
	for index in range(_spatial.size()):
		if _paused: _slots[index].deadline = float(_slots[index].deadline) + maxf(0.0, delta)
		if not _paused and _spatial[index].playing and _clock > float(_slots[index].deadline): _spatial[index].stop()
	for id in _loops:
		var target := _loop_target(str(id))
		var level := move_toward(float(_loop_levels[id]), target, maxf(0.0, delta) * (1.0 if str(id).begins_with("music") else 3.0))
		_loop_levels[id] = level
		_loops[id].volume_db = linear_to_db(level) if level > 0.0001 else -80.0
		if str(id).begins_with("rotor"):
			_loops[id].pitch_scale = 0.92 + _thrust * 0.2 + minf(_speed / 100.0, 0.12)
	# Bound emitter memory for long sessions, including discarded NPC identities.
	if _cooldowns.size() > 256:
		for key in _cooldowns.keys():
			if _clock > float(_cooldowns[key]) + 10.0: _cooldowns.erase(key)

func _observe_session(owner_session) -> void:
	var is_active: bool = bool(owner_session.active) and is_instance_valid(owner_session.world)
	var session_key := str(owner_session.network.session_id) + ":" + str(owner_session.region_id) if is_instance_valid(owner_session.network) else ""
	if session_key != _observed_key:
		release_region()
		_observed_key = session_key
	var boss_view: Dictionary = owner_session.world_cache.get("remote_boss", {}) if is_instance_valid(owner_session.network) and not owner_session.network.is_authority() else {}
	var is_boss: bool = bool(owner_session.boss_active) or (not boss_view.is_empty() and not bool(boss_view.get("completed", false)))
	set_context(str(owner_session.region_id), is_active, is_boss, bool(owner_session.simulation_paused))
	if not is_active or not is_instance_valid(owner_session.network): return
	var local: int = owner_session.network.local_id()
	if owner_session.players.has(local):
		var body = owner_session.players[local]
		var orientation: Basis = owner_session.camera.global_basis if is_instance_valid(owner_session.camera) else Basis.IDENTITY
		set_listener(body.global_position, orientation)
		var telemetry: Dictionary = body.telemetry.duplicate()
		# A remote authority may apply health between local physics telemetry ticks.
		telemetry["health"] = body.health
		update_flight(telemetry, bool(body.enabled))
	if not _paused and owner_session.story.ready:
		var objectives: int = owner_session.story.state.get("completed", []).size()
		var actions: int = owner_session.story.state.get("completed_actions", []).size()
		# First load/reconnect is a baseline, not a replay of old rewards.
		if _action_count >= 0 and actions > _action_count: play_event("task_complete")
		elif _objective_count >= 0 and objectives > _objective_count: play_event("task_step")
		_objective_count = objectives
		_action_count = actions

func _loop_target(id: String) -> float:
	var industrial := not _region.begins_with("F")
	var regional_weight := 0.25 if _boss else 1.0
	var weight := 0.0
	match id:
		"music_industrial": weight = regional_weight if industrial else 0.0
		"music_fantasy": weight = 0.0 if industrial else regional_weight
		"music_tension": weight = 1.0 if _boss else 0.0
		"ambient_industrial": weight = 1.0 if _active and industrial else 0.0
		"ambient_fantasy": weight = 1.0 if _active and not industrial else 0.0
		"rotor_low": weight = (0.25 + _thrust * 0.6) * (1.0 - _thrust * 0.55) if _active and not _paused and _listener_ready and _flight_enabled else 0.0
		"rotor_high": weight = _thrust * _thrust * 0.8 if _active and not _paused and _listener_ready and _flight_enabled else 0.0
		"wind": weight = minf(1.0, _speed / 18.0) * 0.65 if _active and not _paused and _listener_ready and _flight_enabled else 0.0
	if id.begins_with("music"):
		if _paused: weight *= 0.5
		if not _active: weight *= 0.6
	return weight * db_to_linear(float(_catalog.loops[id].gain_db))

func _choose_voice(is_ui: bool, priority: int) -> int:
	var players: Array = _ui if is_ui else _spatial
	var slots: Array[Dictionary] = _ui_slots if is_ui else _slots
	var candidate := -1
	for index in range(players.size()):
		# Spatial playback can be queued until the next audio/physics update.
		# Reserve a newly assigned slot immediately, including same-frame bursts.
		if float(slots[index].deadline) <= _clock or (not players[index].playing and _clock - float(slots[index].started) > 0.05): return index
		if int(slots[index].priority) > priority: continue
		if candidate < 0 or int(slots[index].priority) < int(slots[candidate].priority) or (int(slots[index].priority) == int(slots[candidate].priority) and float(slots[index].started) < float(slots[candidate].started)):
			candidate = index
	return candidate

func _stream(path: String, looped: bool) -> AudioStream:
	var key := path + (":loop" if looped else ":once")
	if _streams.has(key): return _streams[key]
	var sound: AudioStreamWAV
	if ResourceLoader.exists(path, "AudioStreamWAV"):
		sound = ResourceLoader.load(path, "AudioStreamWAV") as AudioStreamWAV
	elif FileAccess.file_exists(path): sound = AudioStreamWAV.load_from_file(path)
	if sound == null:
		if path not in _missing:
			_missing.append(path)
			push_warning("V3 audio resource unavailable: " + path)
		return null
	# Never mutate a shared imported resource used by another scene/version.
	sound = sound.duplicate() as AudioStreamWAV
	sound.loop_mode = AudioStreamWAV.LOOP_FORWARD if looped else AudioStreamWAV.LOOP_DISABLED
	sound.loop_begin = 0
	sound.loop_end = roundi(sound.get_length() * sound.mix_rate)
	_streams[key] = sound
	return sound

func _ensure_buses() -> void:
	for key in BUS_NAMES:
		var bus: String = BUS_NAMES[key]
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
		AudioServer.set_bus_send(AudioServer.get_bus_index(bus), "Master" if key == "master" else BUS_NAMES.master)
	var master := AudioServer.get_bus_index(BUS_NAMES.master)
	for index in range(AudioServer.get_bus_effect_count(master)):
		if AudioServer.get_bus_effect(master, index) is AudioEffectHardLimiter: return
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = -1.0
	limiter.pre_gain_db = 0.0
	limiter.release = 0.1
	AudioServer.add_bus_effect(master, limiter)

func _apply_mix() -> void:
	for key in BUS_NAMES:
		var index := AudioServer.get_bus_index(str(BUS_NAMES[key]))
		if index < 0: continue
		var gain := float(_mix[key])
		AudioServer.set_bus_volume_db(index, linear_to_db(gain) if gain > 0.0001 else -80.0)
		AudioServer.set_bus_mute(index, (key == "master" and bool(_mix.mute)) or gain <= 0.0001)

func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK: return
	for key in BUS_NAMES:
		_mix[key] = _number(config.get_value("audio", str(key), _mix[key]), 0.0, 1.0)
	_mix.mute = bool(config.get_value("audio", "mute", false))

func _number(value: Variant, minimum: float, maximum: float) -> float:
	if not (value is int or value is float): return minimum
	var number := float(value)
	return clampf(number, minimum, maximum) if is_finite(number) else minimum

func _exit_tree() -> void:
	shutdown()
