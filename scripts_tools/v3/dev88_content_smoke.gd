extends SceneTree
## One bounded final content smoke, not a campaign replay or a playtime proof.
## Opens a NEW named profile only. The F2 start and single initial pilot pose
## are explicit component fixtures; no objectives, rewards, Boss HP or old saves
## are authored. No LAN, performance, screenshots, desktop input or focus calls.
const Main = preload("res://scenes/v3/main.tscn")
const StoryCatalog = preload("res://scripts/v3/content/dev88_story/twin_side_story_catalog.gd")
const CombatCatalog = preload("res://scripts/v3/content/dev88_combat/twin_combat_sites_catalog.gd")
const CombatView = preload("res://scripts/v3/content/dev88_combat/twin_combat_site_view.gd")
const Rewards = preload("res://scripts/v3/content/dev88_progression/twin_dev88_rewards.gd")
const Presentation = preload("res://scripts/v3/content/dev88_presentation/twin_dev88_presentation.gd")
const Voices = preload("res://scripts/v3/content/dev88_presentation/twin_dev88_sound_routes.gd")
class ErrorLogger extends Logger:
	var errors: Array = []
	var guard := Mutex.new()
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _notify: bool, kind: int, _trace: Array[ScriptBacktrace]) -> void:
		if kind == Logger.ERROR_TYPE_WARNING: return
		guard.lock()
		if errors.size() < 30: errors.append({"function":function,"file":file,"line":line,"code":code,"reason":rationale})
		guard.unlock()
var logger := ErrorLogger.new()
var session: Node
var profile := ""
var output := ""
var checks: Array = []
var ended := false
var began := 0
var only_journal := false

func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile = arg.trim_prefix("--qa-profile=")
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		if arg == "--only-journal": only_journal = true
	if not profile.begins_with("qa_dev88_final_") or profile != profile.validate_filename() or DirAccess.dir_exists_absolute("user://profiles_v3/" + profile) or not output.is_absolute_path() or ".." in output:
		print("DEV88_FINAL_ARGUMENTS_REJECTED"); quit(2); return
	began = Time.get_ticks_usec()
	create_timer(110).timeout.connect(func():
		if not ended:
			_check(false,"bounded final smoke completed within 110 seconds",{})
			_finish())
	session = Main.instantiate()
	root.add_child(session)
	await process_frame
	if not _check(session.profile_ready and session.store.root_path == "user://profiles_v3/" + profile, "new isolated source MAIN profile", {}): _finish(); return
	# An empty starting-region fixture only; never pre-author campaign progress.
	var located: Dictionary = session.store.commit({"id":"dev88-final-new-start-location-only","set":{"world.region_id":"F2"}})
	if not _check(located.get("ok",false) and session.start_flight("solo"),"source MAIN starts the authored F2 component fixture",located): _finish(); return
	session.set_physics_process(false)
	# Interface, real rigid bodies and normal physics remain enabled.
	await physics_frame
	var original: Array = session.story.state.get("completed",[]).duplicate()
	if only_journal:
		var notebook: Dictionary = session.content_journal.document()
		session.content_journal.receive({"kind":"content_journal88","session_id":session.network.session_id,"document":notebook})
		_check(session.interface.journal.visible and notebook.regions.size() == 8,"corrected notebook opens with all Host sections",{})
		var mobile := ""
		for id: String in session.ecology.view.actors:
			mobile = id
			break
		var anchor: Dictionary = session.content_journal._marker_anchor(mobile,"F2","活动同伴")
		session.content_journal.track(anchor)
		var target: Dictionary = session.content_journal.target()
		_check(not anchor.is_empty() and target.get("position") is Vector3,"corrected tracking reads the real moving actor node",{})
		session.content_journal.track({})
		_check(session.content_journal.target().is_empty(),"notebook can restore main-story tracking",{})
		await process_frame
		_finish()
		return
	for region: String in ["I1","F1","I2","F2","I3","F3","I4","F4"]:
		var prepared: Dictionary = session._prepare_region(region)
		if not _check(prepared.get("ok",false),"native region and additive content construct: " + region,{"error":prepared.get("error","")}): _finish(); return
		var site_world: Node3D = prepared.world
		var rows: Array = []
		for marker: Dictionary in session.story.markers.values():
			if marker.get("region") == region: rows.append(marker)
		var art: Node3D = Presentation.build(region,rows)
		site_world.add_child(art)
		Presentation.apply_state(art,session.story.state)
		await physics_frame
		var rigid_id := ""
		for id: String in site_world.objects:
			if site_world.objects[id] is RigidBody3D and site_world.objects[id].get_meta("side_story88",false): rigid_id = id; break
		if not rigid_id.is_empty():
			prepared.entities[rigid_id]["pinned"] = true
			site_world.synchronize(prepared.entities,0.0)
			_check(site_world.objects[rigid_id].freeze,"new salvage force-field binds a native body: " + region,{"entity":rigid_id})
			prepared.entities[rigid_id]["pinned"] = false
			site_world.synchronize(prepared.entities,0.0)
			_check(not site_world.objects[rigid_id].freeze,"new salvage force-field releases a native body: " + region,{})
		session._discard_prepared_region(prepared)
		await process_frame
	var secret_counts: Dictionary = {}
	for region: String in ["I1","F1","I2","F2","I3","F3","I4","F4"]: secret_counts[region] = Rewards.notes(region).size()
	_check(Rewards.notes().size() == 32 and secret_counts.values().all(func(n): return n == 4),"eight regions expose four real unique field records each",secret_counts)
	_check(StoryCatalog.definitions().size() == 15 and CombatCatalog.sites().size() == 10,"new story and encounter catalogs present",{})
	var notebook: Dictionary = session.content_journal.document()
	session.content_journal.receive({"kind":"content_journal88","session_id":session.network.session_id,"document":notebook})
	_check(session.interface.journal.visible and notebook.regions.size() == 8,"real notebook builds from Host state",{})
	session.interface.journal.hide()
	var pilot: FlightBodyV2 = session.players[1]
	# One explicit initial fixture pose, not a persisted player position.
	pilot.global_position = Vector3(2,5,33)
	pilot.linear_velocity = Vector3.ZERO
	pilot.hold_height = 5.0
	pilot.safe_position = pilot.global_position
	session.entities[session._actor_id(1)].position = pilot.global_position
	session.combat_sites.interact(1,"F2:combat88:scout_lane")
	while session.interface.advance_dialogue(): pass
	if not _check(session.combat_sites.active() and session.combat_sites.error.is_empty(),"optional site starts with native enemy bodies",{"error":session.combat_sites.error}): _finish(); return
	var entered := false
	for tick in range(180):
		pilot.command = {"active":true,"body_relative":false,"mode":"assisted","planar":Vector3(0,0,-.25) if pilot.global_position.z > 28.0 else Vector3.ZERO,"vertical":0.0,"brake":pilot.global_position.z <= 28.0,"fire":false}
		await physics_frame
		var step: Dictionary = session.combat_sites.advance(1.0 / 60.0)
		if not step.get("ok",false): _check(false,"ordinary combat tick",step); break
		if str(session.combat_sites.get("_phase")) == "running": entered = true
		if entered and pilot.global_position.z <= 28.0: break
	_check(entered,"real flight enters the optional combat envelope",{"position":pilot.global_position})
	pilot.command = {"active":true,"body_relative":false,"mode":"assisted","planar":Vector3.ZERO,"vertical":0.0,"brake":true,"fire":false}
	var target := ""
	for id: String in session.entities:
		if session.combat_sites.owns_target(id) and session._line_clear(pilot.global_position, session.entities[id].position,pilot.get_rid(),id): target = id; break
	if _check(not target.is_empty(),"normal LOS can select a real enemy",{}):
		session._action_received(1,"lock",{"target_id":target})
		var before := float(session.entities[target].get("health",-1))
		var fired: bool = session._fire(1)
		for tick in range(3):
			await physics_frame
			session.combat_sites.advance(1.0 / 60.0)
		var after := float(session.entities[target].get("health",-1))
		_check(fired and after < before,"original player weapon settles actual enemy damage",{"before":before,"after":after})
		var view: Dictionary = session.combat_sites.presentation()
		_check(CombatView.valid(view),"current native encounter has a valid reliable projection",{})
	session.interface.journal.show()
	await physics_frame
	var held: Dictionary = session.combat_sites.advance(1.0 / 60.0)
	_check(held.get("ok",false),"notebook suspends optional combat without a second clock",held)
	session.interface.journal.hide()
	var voice: String = Voices.cue_for("choice:F4:chapter_choice:shared_stewardship:full")
	_check(not voice.is_empty() and session.audio.play_radio(voice),"explicit option explanation uses the existing UI voice pool",{})
	session.audio.stop_radio()
	_check(session.story.state.get("completed",[]) == original and session.combat_sites.completed_sites().is_empty(),"smoke never authored campaign completion or encounter rewards",{})
	_finish()

func _check(ok: bool, label: String, details: Dictionary) -> bool:
	checks.append({"ok":ok,"label":label,"details":details})
	if not ok: print("DEV88_SMOKE_FAIL ",label," ",details)
	return ok

func _finish() -> void:
	if ended: return
	ended = true
	var passed: bool = checks.all(func(row): return row.ok) and logger.errors.is_empty()
	var report := {"version":"3.0.0-dev.88","scope":"targeted journal correction recheck" if only_journal else "one bounded source content smoke; explicit new F2 start/pilot fixtures; not natural campaign, graphics, timing, performance, LAN or human play proof", "profile":profile,"checks":checks,"errors":logger.errors,"passed":passed,"elapsed_s":float(Time.get_ticks_usec()-began)/1000000.0}
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report,"\t")); file.close()
	print("DEV88_FINAL_CONTENT_SMOKE ",JSON.stringify({"passed":passed,"checks":checks.size(),"errors":logger.errors.size(),"report":output}))
	if is_instance_valid(session):
		session.audio.shutdown()
		session.queue_free()
	await process_frame
	await process_frame
	quit(0 if passed else 1)
