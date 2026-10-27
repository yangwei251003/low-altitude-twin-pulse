extends SceneTree
## Source-only original Audio; explicit context fixtures, natural SceneTree time.
const Audio = preload("res://scripts/v3/audio/twin_audio.gd")
const MUSIC := ["music_industrial","music_fantasy","music_tension"]
class ErrorLog extends Logger:
	var errors: Array = []
	var guard := Mutex.new()
	func _log_error(function: String,file: String,line: int,code: String,rationale: String,_notify: bool,kind: int,_trace: Array[ScriptBacktrace]) -> void:
		if kind==Logger.ERROR_TYPE_WARNING: return
		guard.lock()
		if errors.size()<16: errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale})
		guard.unlock()
var logger := ErrorLog.new()
var audio: Node
var output := ""
var finished := false
var began := 0
var checks: Array = []
var stages: Array = []
var identity: Dictionary = {}
var original_mix: Dictionary = {}
var original_buses: Dictionary = {}
var settings_before: Dictionary = {}
func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()
func _check(ok: bool,label: String,actual: Variant = null) -> bool:
	checks.append({"passed":ok,"label":label,"actual":actual}); return ok
func _settings() -> Dictionary:
	var exists := FileAccess.file_exists(Audio.SETTINGS_PATH)
	return {"exists":exists,"sha256":FileAccess.get_sha256(Audio.SETTINGS_PATH) if exists else "","mtime":FileAccess.get_modified_time(Audio.SETTINGS_PATH) if exists else 0}
func _identities() -> Dictionary:
	var result: Dictionary={"loops":{},"cache":{}}
	for id: String in audio._loops: result.loops[id]=[audio._loops[id].get_instance_id(),audio._loops[id].stream.get_instance_id()]
	for key: String in audio._streams: result.cache[key]=audio._streams[key].get_instance_id()
	return result
func _buses() -> Dictionary:
	var result: Dictionary={}
	for key: String in Audio.BUS_NAMES:
		var index := AudioServer.get_bus_index(Audio.BUS_NAMES[key])
		result[key]=[AudioServer.get_bus_volume_db(index),AudioServer.is_bus_mute(index)]
	return result
func _ratios() -> Dictionary:
	var result: Dictionary={}
	for id: String in MUSIC:
		result[id]=db_to_linear(audio._loops[id].volume_db)/db_to_linear(float(audio._catalog.loops[id].gain_db))
	return result
func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--mix-output="): output=arg.trim_prefix("--mix-output=").replace("\\","/")
	var managed := OS.get_environment("LOW_ALTITUDE_DEV_HOME").replace("\\","/").trim_suffix("/")
	if managed.is_empty() or not output.begins_with(managed+"/evidence/regional-boss-mix-") or not output.is_absolute_path() or ".." in output or output.get_extension()!="json" or FileAccess.file_exists(output) or not DirAccess.dir_exists_absolute(output.get_base_dir()): quit(2); return
	began=Time.get_ticks_msec(); settings_before=_settings()
	create_timer(18.0).timeout.connect(func():
		if not finished: _check(false,"18 second native mix probe bound"); _finish())
	audio=Audio.new(); root.add_child(audio)
	await process_frame
	if not _check(audio.diagnostics().ready and audio.diagnostics().missing.is_empty(),"original catalog/loop streams ready"): _finish(); return
	identity=_identities(); original_mix=audio.get_mix(); original_buses=_buses()
	for region: String in ["I1","F1"]:
		for spec: Array in [[false,false],[true,false],[true,true],[true,false],[false,false]]:
			if not await _step(region,bool(spec[0]),bool(spec[1])): _finish(); return
	_check(_settings()==settings_before,"user settings file unchanged",_settings())
	_finish()
func _step(region: String,boss: bool,paused: bool) -> bool:
	var factor := 0.5 if paused else 1.0
	var bed := 0.25 if boss else 1.0
	var expected := {"music_industrial":factor*bed if region=="I1" else 0.0,"music_fantasy":factor*bed if region=="F1" else 0.0,"music_tension":factor if boss else 0.0}
	var before := _ratios()
	audio.set_context(region,true,boss,paused) # Explicit scene context, not real combat.
	var deadline := Time.get_ticks_msec()+2000
	var samples := 0; var middle: Dictionary={}; var actual: Dictionary={}; var native := false
	while not finished and Time.get_ticks_msec()<deadline:
		await physics_frame; await process_frame
		if finished: return false
		samples+=1; actual=_ratios()
		var settled := true
		for id: String in MUSIC:
			settled=settled and absf(float(actual[id])-float(expected[id]))<0.015
			if middle.is_empty() and absf(float(actual[id])-float(before[id]))>0.02 and absf(float(actual[id])-float(expected[id]))>0.02: middle=actual.duplicate()
		native=true
		for id: String in MUSIC: native=native and audio._loops[id].playing and audio._loops[id].has_stream_playback()
		if settled and samples>=2: break
	var changed := MUSIC.any(func(id: String): return absf(float(before[id])-float(expected[id]))>0.05)
	var row := {"region":region,"boss":boss,"paused":paused,"before":before,"expected":expected,"actual":actual,"middle":middle,"frames":samples,"native_playing":native,"display":DisplayServer.get_name(),"audio_driver":AudioServer.get_driver_name()}
	stages.append(row)
	var settled := MUSIC.all(func(id: String): return absf(float(actual.get(id,-99))-float(expected[id]))<0.015)
	return _check(settled and native and (not changed or not middle.is_empty()) and _identities()==identity and audio.get_mix()==original_mix and _buses()==original_buses,"original loops naturally crossfade with expected regional/Boss/pause weights and unchanged nodes/cache/user mix",row)
func _finish() -> void:
	if finished: return
	finished=true
	var drain: Dictionary={}
	if is_instance_valid(audio):
		audio.shutdown()
		var deadline := Time.get_ticks_msec()+1000
		while Time.get_ticks_msec()<deadline:
			drain=audio.shutdown_status()
			if drain.get("ready",false): break
			await process_frame
		_check(drain.get("ready",false),"original native audio references drain",drain)
		audio.queue_free(); await process_frame
	_check(_settings()==settings_before,"no settings write during shutdown",_settings())
	var failures: Array=checks.filter(func(row: Dictionary): return not row.passed)
	var report := {"passed":failures.is_empty() and logger.errors.is_empty(),"checks":checks,"failures":failures,"stages":stages,"engine_errors":logger.errors,"original_mix":original_mix,"original_bus_mix":original_buses,"settings_before":settings_before,"audio_drain":drain,"seconds":float(Time.get_ticks_msec()-began)/1000.0,"scope":"Original TwinAudio/streams, explicit set_context fixtures, natural SceneTree clock. Headless Dummy native/logical mix evidence only; no real Boss, victory, user-play, hardware/listening, graphics, LAN or saved preference change."}
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report,"\t")); file.close()
	print("REGIONAL_BOSS_MIX "+JSON.stringify({"passed":report.passed,"seconds":report.seconds,"output":output}))
	quit(0 if report.passed and file!=null else 1)
