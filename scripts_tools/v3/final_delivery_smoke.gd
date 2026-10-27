extends SceneTree
## One final bounded integration check after ALL production content was frozen.
## A NEW isolated profile only. Presentation fixtures never enter Main/Store.
## No campaign replay, screenshots, desktop input, performance or LAN claim.
const Main = preload("res://scenes/v3/main.tscn")
const FinalStory = preload("res://scripts/v3/content/final_story/twin_final_story_catalog.gd")
const FinalWorld = preload("res://scripts/v3/content/final_world/twin_final_world.gd")
const FinalBoss = preload("res://scripts/v3/content/final_presentation/twin_final_boss_visuals.gd")
const FinalVoices = preload("res://scripts/v3/content/final_flow/twin_final_voice_routes.gd")
class ErrorLog extends Logger:
	var errors: Array = []
	var warnings: Array = []
	var guard := Mutex.new()
	func _log_error(function: String, file: String, line: int, code: String, reason: String, _notify: bool, kind: int, _trace: Array[ScriptBacktrace]) -> void:
		guard.lock()
		var row := {"function":function,"file":file,"line":line,"code":code,"reason":reason}
		if kind == Logger.ERROR_TYPE_WARNING:
			if warnings.size() < 30: warnings.append(row)
		elif errors.size() < 30: errors.append(row)
		guard.unlock()
var logger := ErrorLog.new()
var session: Node
var checks: Array = []
var output := ""
var profile := ""
var began := 0
var ended := false
var only_fixes := false

func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile = arg.trim_prefix("--qa-profile=")
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		if arg == "--only-fixes": only_fixes = true
	if not profile.begins_with("qa_final_delivery_") or profile != profile.validate_filename() or DirAccess.dir_exists_absolute("user://profiles_v3/"+profile) or not output.is_absolute_path() or ".." in output:
		print("FINAL_DELIVERY_ARGUMENTS_REJECTED"); quit(2); return
	began = Time.get_ticks_usec()
	create_timer(100).timeout.connect(func():
		if not ended:
			_check(false,"bounded integration check finished within 100 seconds")
			_finish())
	session = Main.instantiate()
	root.add_child(session)
	await process_frame
	if not _check(session.profile_ready and session.store.root_path == "user://profiles_v3/"+profile,"new isolated Main profile"): _finish(); return
	if not _check(session.start_flight("solo"),"ordinary Main starts at its genuine current opening"): _finish(); return
	session.set_physics_process(false)
	await physics_frame
	var saved: Dictionary = session.store.snapshot()
	var original_story: Dictionary = session.story.state.duplicate(true)
	_check(not FinalStory.ending_ready(original_story) and FinalStory.ending_cards(original_story).is_empty(),"unfinished opening cannot reveal an ending")
	_check(FinalStory.markers(original_story).is_empty(),"postwar records do not appear before real progress")
	session.final_flow.open_handbook()
	await process_frame
	session.interface._update_controller_focus()
	var pages: Array = session.interface.campaign_book.pages
	var ids: Array = pages.map(func(page): return page.id)
	_check(session.interface.campaign_book.visible and session.interface.menu.visible and ["I1","F1","I2","F2","I3","F3","I4","F4","tools","flight","cooperation"].all(func(id): return id in ids),"real handbook contains flight/tools/cooperation and all regions")
	_check(session.interface.campaign_book.is_ancestor_of(root.get_viewport().gui_get_focus_owner()),"book owns internal UI focus")
	session.final_flow.close_book()
	_check(not session.interface.campaign_book.visible and not session.interface.menu.visible,"closing handbook restores flight menu state")
	if only_fixes:
		var built: Dictionary = session._prepare_region("I2")
		if _check(built.get("ok", false),"corrected first-time Boss visual decoration builds",{"error":built.get("error", "")}):
			var arena: Node3D = built.world.campaign_arena
			arena.apply_view({}, [], false)
			_check(is_instance_valid(arena.get_meta(FinalBoss.META_KEY)),"corrected Boss visual state can be applied")
			session._discard_prepared_region(built)
		await process_frame
		_check(logger.warnings.is_empty(),"corrected handbook focus has no warning")
		_check(session.story.state == original_story and session.store.snapshot() == saved,"correction recheck does not author progress")
		_finish()
		return
	for region: String in ["I1","F1","I2","F2","I3","F3","I4","F4"]:
		var prepared: Dictionary = session._prepare_region(region)
		if not _check(prepared.get("ok",false),"native integrated region builds: "+region,{"error":prepared.get("error","")}): _finish(); return
		var world: Node3D = prepared.world
		var weather: Node3D = world.get_node_or_null(FinalWorld.ROOT_NAME)
		_check(is_instance_valid(weather),"weather/life module mounted: "+region)
		FinalWorld.apply_state(weather,{"weather":"rain","clock":12.0,"wind_velocity":Vector3(2,0,1)},{},false,world.spawn_position)
		var held_clock: float = weather.get("_clock")
		var held_wind: Vector3 = weather.get("_wind")
		FinalWorld.apply_state(weather,{"weather":"storm","clock":24.0,"wind_velocity":Vector3(5,0,0)},{},true,world.spawn_position)
		_check(float(weather.get("_clock")) == held_clock and weather.get("_wind") == held_wind,"pause holds the supplied weather pose: "+region)
		if region not in ["I1","F1"]:
			var arena: Node3D = world.campaign_arena
			var parts: Array = arena.definition.parts.duplicate(); parts.append("core")
			var expected: Array = parts.map(func(part): return arena.target_id(part))
			_check(is_instance_valid(arena.get_meta(FinalBoss.META_KEY,null)) and arena.targets.size() == expected.size() and expected.all(func(id): return arena.targets.has(id)),"distinct Boss skin retains original part targets: "+region)
			var positions: Dictionary = {}
			for id: String in arena.targets: positions[id] = arena.targets[id].transform
			var hp: Dictionary = {}
			for part: String in arena.definition.parts: hp[part] = 1000
			arena.apply_view({"core_hp_milli":1000,"parts":hp},[str(arena.definition.parts[0])],false)
			_check(positions.keys().all(func(id): return arena.targets[id].transform == positions[id]),"visual opening leaves original hit transforms intact: "+region)
			arena.apply_view({"core_hp_milli":0,"parts":{}},[],true)
			var remains: Node3D = arena.get_meta(FinalBoss.META_KEY).get_node("DormantRemains")
			_check(remains.visible and arena.targets.values().all(func(body): return not body.visible),"committed-defeat presentation has independent dormant remains: "+region)
		session._discard_prepared_region(prepared)
		await process_frame
	var fixture := {"content_id":"opening_v1","completed":["F4:twin_vein_core:stop",FinalStory.FINAL_OBJECTIVE],"completed_actions":[FinalStory.FINAL_ACTION],
		"flags":{"F4:boss_stopped":true,"F4:chapter_decision_saved":true,"F4:region_route_open":true},
		"choices":{"I2:twin_pump_guardian:decision":"balanced_service","F2:mirror_evidence:decision":"publish_context","I4:prism_array:decision":"regional_cosign",FinalStory.FINAL_OBJECTIVE:"shared_stewardship"}}
	var first_voice := ""
	for option: String in FinalStory.CHOICES[FinalStory.FINAL_OBJECTIVE]:
		fixture.choices[FinalStory.FINAL_OBJECTIVE] = option
		var cards: Array = FinalStory.ending_cards(fixture)
		_check(cards.size() == 18 and FinalStory.character_outcomes(fixture).size() == 13,"presentation-only fixture has complete ending and character cards: "+option)
		_check(cards.all(func(card): return FinalVoices.owns(str(card.voice_id))),"all key ending cards have registered actual voice events: "+option)
		if not cards.is_empty(): first_voice = str(cards[0].voice_id)
		var uncommitted: Dictionary = fixture.duplicate(true)
		uncommitted.flags["F4:chapter_decision_saved"] = false
		_check(FinalStory.ending_cards(uncommitted).is_empty(),"an uncommitted choice cannot expose the ending: "+option)
	_check(not first_voice.is_empty() and session.audio.play_radio(first_voice),"final key voice plays through the existing UI pool")
	session.audio.stop_radio()
	var document: Dictionary = session.content_journal.document()
	session.content_journal.receive({"kind":"content_journal88","session_id":session.network.session_id,"document":document})
	_check(session.interface.journal.visible and document.regions.size() == 8,"real Host notebook remains readable")
	session.interface.journal.hide()
	_check(session.story.state == original_story and session.store.snapshot() == saved,"presentation fixtures never mutate real Story or Store")
	_finish()

func _check(ok: bool, label: String, details: Dictionary = {}) -> bool:
	checks.append({"ok":ok,"label":label,"details":details})
	if not ok: print("FINAL_DELIVERY_FAIL ",label," ",details)
	return ok

func _finish() -> void:
	if ended: return
	ended = true
	var passed: bool = checks.all(func(row): return row.ok) and logger.errors.is_empty()
	var report := {"version":"3.0.0-dev.89","profile":profile,"passed":passed,"checks":checks,"errors":logger.errors,"warnings":logger.warnings,"elapsed_s":float(Time.get_ticks_usec()-began)/1000000.0,
		"scope":"targeted first-time Boss metadata and handbook focus correction recheck" if only_fixes else "one unified bounded source integration check after all content production; ending states are local presentation fixtures never applied to Story/Store; not a natural full campaign, rendering, human, performance or LAN proof"}
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report,"\t")); file.close()
	print("FINAL_DELIVERY_RESULT ",JSON.stringify({"passed":passed,"checks":checks.size(),"errors":logger.errors.size(),"report":output}))
	if is_instance_valid(session):
		session.audio.shutdown()
		session.queue_free()
	await process_frame
	await process_frame
	quit(0 if passed else 1)
