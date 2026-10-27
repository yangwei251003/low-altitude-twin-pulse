extends SceneTree
## Two explicitly isolated QA rule-prefix slices over real MAIN. Actual G,
## native Flight commands and ordinary Session ticks test the engagement gate.
const MAIN = preload("res://scenes/v3/main.tscn")
const Catalog = preload("res://scripts/v3/campaign/twin_campaign_catalog.gd")
const Layout = preload("res://scripts/v3/campaign/twin_campaign_layout.gd")
const Pilot = preload("res://scripts/v3/gameplay/canal/canal_transport_physics/transport_pilot.gd")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")

class ErrorLogger extends Logger:
	var guard := Mutex.new()
	var errors: Array = []
	func _log_error(function: String,file: String,line: int,code: String,rationale: String,_notify: bool,kind: int,_trace: Array[ScriptBacktrace]) -> void:
		if kind == Logger.ERROR_TYPE_WARNING: return
		guard.lock()
		errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale})
		guard.unlock()

class FlightCommands extends Node:
	var owner_session: Node
	var pilot: RefCounted
	func _physics_process(delta: float) -> void:
		if not is_instance_valid(owner_session) or not owner_session.active or owner_session.simulation_paused or pilot == null: return
		pilot.tick(delta,true,false) # Real command only; Session alone ticks mechanics.

var logger := ErrorLogger.new()
var session: Node
var driver: FlightCommands
var profile := ""
var output := ""
var finished := false
var complete := false
var checks: Array = []
var phases: Array = []
var fixture_receipts: Dictionary = {}
var f4_precombat: Dictionary = {}
var ending_view: Dictionary = {}
var start_frame := 0

func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile = arg.trim_prefix("--qa-profile=")
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	if not profile.begins_with("qa_campaign_story_ui_") or profile != profile.validate_filename() or not output.begins_with("res://artifacts/v3/campaign-story-ui-") or ".." in output or DirAccess.dir_exists_absolute(output) or DirAccess.dir_exists_absolute("user://profiles_v3/"+profile):
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	start_frame = Engine.get_physics_frames()
	create_timer(30.0).timeout.connect(func():
		if not finished: _check(false,"30 second actual campaign Story/UI slice bound",_diagnostics()); _finish())
	session = MAIN.instantiate()
	root.add_child(session)
	if not _check(session.profile_ready and session.start_flight("solo"),"actual blank unique QA MAIN starts before any rules fixture",_diagnostics()): _finish(); return
	session.inputs.test_enabled = true
	session.inputs.test_frame = {"axes":{},"held":["brake"],"edges":[]}
	driver = FlightCommands.new()
	driver.owner_session = session
	driver.process_physics_priority = 10
	root.add_child(driver)
	if not await _entry_slice("F2","mirrorwing_warden"): _finish(); return
	if not await _wait_gate() or not _reset_rules_fixture("before_F4"): _finish(); return
	if not await _entry_slice("F4","twin_vein_core"): _finish(); return
	if not await _wait_gate() or not _ending_fixture(): _finish(); return
	complete = true
	_finish()

func _entry_slice(region: String,boss: String) -> bool:
	driver.pilot = null
	if not _check(session._load_region(region) and session.region_id == region and session.campaign.supported(),"actual MAIN loads physical region before its prior rules fixture: "+region,_diagnostics()): return false
	if region == "F4": f4_precombat = session.campaign.persistent_states()["world.environment.campaign_F4"].duplicate(true)
	var objective: String = region+":"+boss+":plan"
	var prepared: Dictionary = _director_fixture(objective)
	if not prepared.get("ok",false): return false
	fixture_receipts[region] = prepared.state.completed.size()
	var committed: Dictionary = session.store.commit({"id":"qa-story-ui-prefix:"+region,"set":{"world.region_id":region,"world.actions.opening":prepared.state}})
	if not _check(committed.get("ok",false),"explicit legal prior-rule prefix is stored only after real region load: "+region,committed): return false
	session.world_cache = session.store.snapshot()
	session.consensus.set_world_revision(int(session.world_cache.world_revision))
	session.story.load_world()
	var marker_id: String = region+":boss_briefing"
	var marker: Dictionary = session.story.markers[marker_id]
	var point: Vector3 = session.story._point(marker)
	var at: Vector3 = point+Vector3(2,1.4,1.2)
	var actor: FlightBodyV2 = session.players[1]
	var entry_z: float = float(Layout.definition(region).boss_arena.entry_z)
	var clear: Array = _hull_hits(actor,Transform3D(Basis.IDENTITY,at))
	if not _check(clear.is_empty() and at.z > entry_z and at.distance_to(session.world.campaign_arena.centre()) < 16.0,"single initial QA briefing pose is clear, inside old radius but outside real entry line: "+region,{"position":_xyz(at),"entry_z":entry_z,"hits":clear}): return false
	# This is this region's sole spatial fixture. No later route pose/velocity,
	# device, damage or encounter state is written by this entry test.
	actor.global_transform = Transform3D(Basis.IDENTITY,at)
	actor.force_update_transform()
	PhysicsServer3D.body_set_state(actor.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,actor.global_transform)
	actor.linear_velocity = Vector3.ZERO
	actor.angular_velocity = Vector3.ZERO
	actor.hold_height = at.y
	actor.safe_position = at
	session.interface.clear_dialogue()
	if not _check(session.story.nearest(at) == marker_id and session._line_clear(at,point,actor.get_rid(),marker_id),"ordinary nearest-G resolves the real visible briefing: "+region): return false
	var key := InputEventKey.new()
	key.physical_keycode = KEY_G
	key.keycode = KEY_G
	key.pressed = true
	session._unhandled_input(key)
	for _step: int in range(8):
		if not await _frame(): return false
		if session.boss_active or session.campaign.active(): return _check(false,"briefing remains safe without crossing entry: "+region,_diagnostics())
	var receipt: Dictionary = _receipt(objective)
	session._refresh_interface()
	if not _check(receipt.get("type") == "inspect" and receipt.get("target_id") == marker_id and receipt.get("option") == "plan" and not session.boss_active and not session.campaign.active() and actor.global_position.distance_to(at) < .3 and actor.global_position.z > entry_z and session.interface.boss_info.text.is_empty() and session.interface.objective.text == session.story.objective_text(actor.global_position,session.interface.details_open),"actual G commits plan, then eight ordinary frames retain safe Story UI: "+region,{"receipt":receipt,"diagnostics":_diagnostics()}): return false
	_phase(region+"_real_G_safe_for_8_frames")
	driver.pilot = Pilot.new()
	if not _check(driver.pilot.bind(actor) and driver.pilot.go_to(Vector3(3.2,at.y,entry_z-1.0),1),"canonical Pilot commands real flight through actual entry: "+region): return false
	var origin: Vector3 = actor.global_position
	var last: Vector3 = origin
	var max_step := 0.0
	var crossed := false
	for _step: int in range(900):
		if not await _frame(): return false
		max_step = maxf(max_step,actor.global_position.distance_to(last))
		last = actor.global_position
		if session.boss_active and session.campaign.active(): crossed = true; break
	if not _check(crossed and actor.global_position.z <= entry_z and actor.global_position.distance_to(origin) >= 2.0 and max_step < .5 and _hull_hits(actor,actor.global_transform).is_empty(),"continuous original Flight actually crosses the authored entry before combat: "+region,{"entry_z":entry_z,"max_frame_step_m":max_step,"diagnostics":_diagnostics()}): return false
	session._refresh_interface()
	var encounter: Dictionary = session.campaign.encounter.get_state()
	if not _check(not session.interface.boss_info.text.is_empty() and session.interface.objective.text.contains(str(session.campaign.definition.name)) and not encounter.get("completed",true) and int(encounter.get("core_hp_milli",-1)) == int(session.campaign.definition.core_hp_milli) and int(session.stats.shots) == 0,"only actual active encounter switches HUD; this slice has no shot or Boss victory: "+region,_diagnostics()): return false
	_phase(region+"_native_entry_starts_real_encounter")
	driver.pilot = null
	return true

func _director_fixture(stop_before: String = "") -> Dictionary:
	var director: RefCounted = session.story.director
	var state: Dictionary = director.default_state()
	for action: Dictionary in director.definitions().actions:
		for objective: Dictionary in action.objectives:
			if objective.id == stop_before:
				return {"ok":bool(director.validate_state(state).get("ok",false)),"state":state}
			var matcher: Dictionary = objective.events[0]
			var applied: Dictionary = director.apply_event(state,{"id":"qa-story-ui-rules:"+str(objective.id),"type":matcher.type,"target_id":matcher.target_id,"option":matcher.options[0]}, {"is_authority":true,"validated":true,"region_id":action.region_id})
			if not applied.get("ok",false) or not applied.get("changed",false):
				_check(false,"legal original Director fixture replay",{"objective":objective.id,"result":applied})
				return {"ok":false}
			state = applied.state
	if not stop_before.is_empty(): return {"ok":false,"code":"fixture_stop_missing"}
	return {"ok":bool(director.validate_state(state).get("ok",false)),"state":state}

func _reset_rules_fixture(label: String,reset_f4: bool = false) -> bool:
	# These are independent UI slices, never natural travel from fake facilities.
	# Restore the QA's default logical index BEFORE a later real region prepare.
	var changes: Dictionary = {"world.actions.opening":session.story.director.default_state(),"world.completed_objectives":[]}
	if reset_f4: changes["world.environment.campaign_F4"] = f4_precombat.duplicate(true)
	var result: Dictionary = session.store.commit({"id":"qa-story-ui-reset:"+label,"set":changes})
	if not _check(result.get("ok",false),"reset only explicitly simulated QA rules between physical slices: "+label,result): return false
	session.world_cache = session.store.snapshot()
	session.consensus.set_world_revision(int(session.world_cache.world_revision))
	return true

func _ending_fixture() -> bool:
	driver.pilot = null
	if not _reset_rules_fixture("ending_UI_only",true): return false
	if not _check(session._load_region("F4") and not session.boss_active and not session.campaign.active(),"actual F4 is reloaded from its recorded precombat QA baseline before ending fixture",_diagnostics()): return false
	var prepared: Dictionary = _director_fixture()
	if not _check(prepared.get("ok",false),"all original Director events form a valid ending UI rules fixture"): return false
	var result: Dictionary = session.store.commit({"id":"qa-story-ui-terminal-Director-only","set":{"world.actions.opening":prepared.state,"world.completed_objectives":prepared.state.completed.duplicate()}})
	if not _check(result.get("ok",false),"original Store accepts explicit terminal Director UI fixture, without physical victory claim",result): return false
	session.world_cache = session.store.snapshot()
	session.story.load_world()
	session._refresh_interface()
	var ending: Dictionary = Catalog.ending(session.story.state.choices)
	var reader: RefCounted = Store.new(session.store.root_path)
	var opened: Dictionary = reader.load_profile()
	var stored: Dictionary = reader.snapshot().world.actions.opening
	ending_view = {"title":ending.get("title",""),"hud":session.interface.objective.text,"boss_info":session.interface.boss_info.text,"ending_id":ending.get("ending_id",""),"fixture_actions":prepared.state.completed_actions.size(),"fixture_objectives":prepared.state.completed.size()}
	if not _check(not ending.is_empty() and opened.get("ok",false) and session.story.director.validate_state(stored).get("ok",false) and stored == session.story.state and session.story.info().get("complete",false) and not session.boss_active and session.interface.boss_info.text.is_empty() and session.interface.objective.text.contains(str(ending.title)) and session.interface.objective.text == session.story.objective_text(session.players[1].global_position,session.interface.details_open),"real MAIN HUD displays original ending fixture and exact original Store readback; no stale combat text",ending_view): return false
	_phase("F4_original_ending_UI_fixture_visible_not_a_physical_win")
	return true

func _wait_gate() -> bool:
	for _step: int in range(120):
		if not session.environment_save_gate.pending(): return true
		if not await _frame(): return false
	return _check(false,"background original SaveGate completes before switching independent QA fixtures",_diagnostics())

func _hull_hits(actor: FlightBodyV2,pose: Transform3D) -> Array:
	var envelope: CollisionShape3D = actor.get_node("Envelope")
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = envelope.shape
	query.transform = pose*envelope.transform
	query.collision_mask = 1|2|4|8|32
	query.exclude = [actor.get_rid()]
	query.margin = .001
	var hits: Array[Dictionary] = session.world.get_world_3d().direct_space_state.intersect_shape(query,8)
	return hits.map(func(hit: Dictionary): return str(hit.collider.get_path()))

func _receipt(objective: String) -> Dictionary:
	for value: Dictionary in session.story.state.get("receipts",{}).values():
		if value.get("objective_id") == objective: return value.duplicate(true)
	return {}

func _frame() -> bool:
	await physics_frame
	await process_frame
	return not finished

func _phase(label: String) -> void:
	var row: Dictionary = {"phase":label,"frame":Engine.get_physics_frames(),"diagnostics":_diagnostics()}
	phases.append(row)
	print("CAMPAIGN_STORY_UI_STAGE "+JSON.stringify(row))

func _diagnostics() -> Dictionary:
	if not is_instance_valid(session): return {"session":"not_installed"}
	var result: Dictionary = {"region":session.region_id,"active":session.active,"boss_active":session.boss_active,"campaign_active":session.campaign.active(),"campaign_error":session.campaign.error,"generation":session.store.snapshot().generation,"last_commit_result":session.last_commit_result,"current_targets":session.story.current_targets(),"objective":session.interface.objective.text,"boss_info":session.interface.boss_info.text,"message":session.interface.message.text}
	if session.players.has(1): result["position"] = _xyz(session.players[1].global_position)
	if is_instance_valid(driver) and driver.pilot != null: result["pilot"] = driver.pilot.report()
	return result

static func _xyz(at: Vector3) -> Array:
	return [at.x,at.y,at.z]

func _check(ok: bool,label: String,actual: Variant = null) -> bool:
	checks.append({"passed":ok,"label":label,"actual":actual})
	return ok

func _finish() -> void:
	if finished: return
	finished = true
	var diagnostics: Dictionary = _diagnostics()
	if is_instance_valid(driver): driver.owner_session = null; driver.free()
	driver = null
	if is_instance_valid(session):
		session.environment_save_gate.cancel("qa_campaign_story_ui_teardown")
		if session.canal != null: session.canal.clear()
		session.thermal_cargo.clear()
		session.network.close()
		session.free()
	session = null
	await process_frame
	await physics_frame
	await process_frame
	var failures: Array = checks.filter(func(row: Dictionary): return not row.passed)
	var report: Dictionary = {"complete":complete,"checks":checks,"failures":failures,"engine_errors":logger.errors,"phases":phases,"fixture_receipts":fixture_receipts,"ending_view":ending_view,"diagnostics":diagnostics,"physics_frames":Engine.get_physics_frames()-start_frame,
		"scope":"Actual normal MAIN in one unique initially blank QA profile. Two independent physical F2/F4 slices: actual region loads before an explicit legal prior-Director rules fixture stopping before plan; one full-hull-clear initial aircraft observation pose per slice; actual ordinary nearest G reads briefing; eight unmoved ordinary physics frames stay safe inside old16m radius; canonical Pilot commands real Flight across authored entry_z before original combat starts. No manual module advance, HP writes, shots, combat victory or natural prior campaign claim. Logical QA prefixes are reset to original defaults before later physical prepare, so fake completed I2 facilities never authorize travel. A recorded actual F4 precombat baseline is reloaded before a separate terminal Director/Store UI fixture; original event replay/readback validates that UI fixture and ending text only. That terminal fixture is not a physically completed facility save or a gameplay-reload acceptance. Real completed-encounter HUD remains covered by Root's existing actual F4 combat test, not duplicated here. No LAN/performance/graphics/human-comfort or full-campaign claim."}
	FileAccess.open(output+"/result.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("CAMPAIGN_STORY_UI_RESULT "+JSON.stringify({"complete":complete,"checks":checks.size(),"failures":failures,"engine_errors":logger.errors,"ending_view":ending_view,"physics_frames":report.physics_frames}))
	quit(0 if complete and failures.is_empty() and logger.errors.is_empty() else 1)
