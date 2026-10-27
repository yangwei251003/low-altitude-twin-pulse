extends SceneTree
## F2 choice boundary over actual MAIN/Store/Consensus/UI. Prior progression is
## an explicitly validated Director-receipt fixture, not played campaign evidence.
const MAIN = preload("res://scenes/v3/main.tscn")
const Regions = preload("res://scripts/v3/world/twin_region_catalog.gd")
const Layout = preload("res://scripts/v3/campaign/twin_campaign_layout.gd")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const TARGET := "F2:chapter_choice"
const ANCHOR := "F2:choice_terminal"
const OBJECTIVE := "F2:mirror_evidence:decision"
const OPTIONS := ["publish_raw","publish_context"]
class ErrorLogger extends Logger:
	var guard := Mutex.new()
	var errors: Array = []
	func _log_error(function: String,file: String,line: int,code: String,rationale: String,_notify: bool,kind: int,_trace: Array[ScriptBacktrace]) -> void:
		if kind==Logger.ERROR_TYPE_WARNING: return
		guard.lock()
		errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale})
		guard.unlock()
var logger := ErrorLogger.new()
var session: Node
var profile := ""
var output := ""
var checks: Array = []
var fixture_receipts := 0
var finished := false
var pending_before_failure: Dictionary = {}
var committed: Dictionary = {}

func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile = arg.trim_prefix("--qa-profile=")
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	if not profile.begins_with("qa_campaign_choices_") or profile!=profile.validate_filename() or not output.begins_with("res://artifacts/v3/campaign-choices-") or ".." in output or DirAccess.dir_exists_absolute(output) or DirAccess.dir_exists_absolute("user://profiles_v3/"+profile):
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	create_timer(60).timeout.connect(func():
		if not finished:
			_check(false,"bounded campaign choice boundary check")
			_finish())
	Regions._entries = Regions.entries()
	var layout: Dictionary = Layout.definition("F2")
	for item: Dictionary in Regions._entries:
		if item.id=="F2":
			item.playable = true
			item.spawn = layout.spawn.duplicate()
			item.bounds = layout.bounds.duplicate()
	session = MAIN.instantiate()
	root.add_child(session)
	if not _check(session.profile_ready and session.start_flight("solo"),"actual MAIN opens new QA solo for choice boundary"):
		_finish()
		return
	session.set_physics_process(false)
	# Prepare F2 from the original empty QA world first. The rule-only prefix
	# deliberately has no I2 physical Result envelopes and must never be used
	# as if it were a fully played prior campaign during facilities.prepare.
	var loaded_f2: bool = session._load_region("F2")
	if not _check(loaded_f2 and session.region_id=="F2","actual F2 MAIN prepares from original blank QA world",{"message":session.interface.message.text,"active":session.active,"build_errors":session.world.build_errors if is_instance_valid(session.world) else null}):
		_finish()
		return
	if not _seed_rule_fixture():
		_finish()
		return
	session.story.load_world()
	if not _check(session.story.ready and session.story.director.validate_state(session.story.state).ok and session.chapter_choices.target_for_anchor(ANCHOR)==TARGET,"already-loaded F2 Story adopts Director-validated choice-boundary fixture",{"message":session.interface.message.text,"region":session.region_id,"current_targets":session.story.current_targets()}):
		_finish()
		return
	var anchor: Vector3 = session.story._point(session.story.markers[ANCHOR])
	await _place(1,anchor+Vector3(0,1,0))
	if not _check(_near(1) and session.story.nearest(session.players[1].global_position)==ANCHOR,"real host is near terminal with clear LOS and normal G target"):
		_finish()
		return
	session.interface.clear_dialogue()
	var before_open: Dictionary = session.store.snapshot()
	var event := InputEventKey.new()
	event.keycode = KEY_G
	event.physical_keycode = KEY_G
	event.pressed = true
	session._unhandled_input(event)
	var panel: PanelContainer = session.interface.chapter_choice
	_check(panel.visible and panel._target==TARGET and panel._read.is_empty() and panel._buttons.all(func(button: Button): return button.disabled),"normal G opens actual offer panel with both options unread and disabled")
	_check(session.chapter_choices.readings.is_empty() and session.store.snapshot()==before_open and _decision_count(session.story.state)==0,"G does not read, choose, create a branch or write Store")
	var branches_before: int = session.store.snapshot().branches.size()
	var generation_before: int = session.store.snapshot().generation
	_propose()
	_check(session.consensus.current_proposal().is_empty() and session.store.snapshot().generation==generation_before and session.store.snapshot().branches.size()==branches_before,"unread proposal is refused without Store or branch mutation")
	for option: String in OPTIONS:
		_check(session.chapter_choices.read_option(1,TARGET,option),"host explicitly reads authored option: "+option)
	_check(session.chapter_choices.has_read_all(1,TARGET),"host has read both benefits and burdens")
	var read_generation: int = session.store.snapshot().generation
	_check(session.chapter_choices.read_option(1,TARGET,OPTIONS[0]) and session.store.snapshot().generation==read_generation,"duplicate explicit read does not repeat Store commit")
	# A second actual FlightBody and identity exercise the original two-party
	# consensus in-process. This is not a transport or two-computer LAN test.
	session._spawn_player(2,"qa_campaign_choice_second_reader",anchor+Vector3(1.8,1,0))
	await _place(2,anchor+Vector3(1.8,1,0))
	if not _check(_near(2) and session.consensus.configure([1,2],int(session.world_cache.world_revision)).get("ok",false),"second real nearby participant joins original consensus fixture"):
		_finish()
		return
	_propose()
	var proposal: Dictionary = session.consensus.current_proposal()
	if not _check(proposal.get("kind")=="campaign_choice" and proposal.get("state")=="pending" and proposal.get("confirmed",[])==["1"],"host read offer creates pending original two-party proposal"):
		_finish()
		return
	var branch_id := str(proposal.payload.get("branch_id",""))
	var store_before: Dictionary = session.store.snapshot()
	_check(store_before.branches.size()==branches_before+1 and store_before.branches.has(branch_id) and _decision_count(store_before.branches[branch_id].world.actions.opening)==0,"choice-before branch is durable before the decision")
	_confirm(2,proposal)
	_check(session.consensus.current_proposal().get("state")=="pending" and session.consensus.current_proposal().get("confirmed",[])==["1"] and session.store.snapshot().generation==store_before.generation,"unread second participant cannot confirm or commit")
	for option: String in OPTIONS:
		_check(session.chapter_choices.read_option(2,TARGET,option),"second participant explicitly reads pending option: "+option)
	_check(session.chapter_choices.has_read_all(2,TARGET) and session.store.snapshot().generation==store_before.generation,"pending read acknowledgements wait for the one final Story transaction")
	var state_before: Dictionary = session.story.state.duplicate(true)
	var discoveries_before: Array = session.store.snapshot().personal.discoveries.duplicate()
	session.store.read_only = true
	_confirm(2,proposal)
	pending_before_failure = session.consensus.current_proposal()
	_check(pending_before_failure.get("state")=="ready" and session.story.state==state_before and session.store.snapshot().generation==store_before.generation and _decision_count(session.story.state)==0,"forced original Store rejection leaves ready proposal and unapplied choice retryable",{"proposal":pending_before_failure,"notice":session.store.notice})
	session.store.read_only = false
	_confirm(2,pending_before_failure)
	committed = session.store.snapshot()
	_check(session.consensus.current_proposal().is_empty() and int(committed.generation)==int(store_before.generation)+1,"explicit retry commits exactly one original Story generation and resolves consensus")
	_check(_decision_count(session.story.state)==1 and session.story.state.choices.get(OBJECTIVE)==OPTIONS[0] and bool(committed.world.flags.get("F2:chapter_decision_saved",false)),"exactly one authored F2 choice receipt and saved consequence flag")
	_check(session.story.state.characters["npc:shuyao"].memories.count("F2:publication_consent")==1 and committed.personal.discoveries==discoveries_before,"authored memory appears once and no nonexistent discovery reward is invented")
	var final_generation: int = committed.generation
	var final_branches: int = committed.branches.size()
	_confirm(2,proposal)
	_propose()
	session.chapter_choices.read_option(1,TARGET,OPTIONS[0])
	_check(session.store.snapshot().generation==final_generation and session.store.snapshot().branches.size()==final_branches and _decision_count(session.story.state)==1 and session.story.state.characters["npc:shuyao"].memories.count("F2:publication_consent")==1,"duplicate confirm/proposal/read adds no receipt, consequence, reward or branch")
	var reader = Store.new(session.store.root_path)
	var loaded: Dictionary = reader.load_profile()
	var disk: Dictionary = reader.snapshot()
	_check(loaded.get("ok",false) and _decision_count(disk.world.actions.opening)==1 and disk.world.actions.opening.choices.get(OBJECTIVE)==OPTIONS[0] and session.story.director.validate_state(disk.world.actions.opening).ok,"new original Store reader verifies published choice receipt on disk")
	_finish()

func _seed_rule_fixture() -> bool:
	var director = session.story.director
	var state: Dictionary = director.default_state()
	var found := false
	for action: Dictionary in director.definitions().actions:
		for objective: Dictionary in action.objectives:
			var matcher: Dictionary = objective.events[0]
			if matcher.target_id==TARGET:
				found = true
				break
			var event := {"id":"qa-choice-rule:"+str(objective.id),"type":matcher.type,"target_id":matcher.target_id,"option":matcher.options[0]}
			var applied: Dictionary = director.apply_event(state,event,{"is_authority":true,"validated":true,"region_id":action.region_id})
			if not applied.get("ok",false) or not applied.get("changed",false): return _check(false,"ordered Director rule fixture advances valid receipt",{"objective":objective.id,"result":applied.get("code")})
			state = applied.state
			fixture_receipts += 1
		if found: break
	if not _check(found and director.validate_state(state).ok and OBJECTIVE not in state.completed,"prior progression is an ordered Director-validated receipt fixture, stopping before F2 choice",{"fixture_receipts":fixture_receipts}): return false
	var stored: Dictionary = session.store.commit({"id":"qa-campaign-choice-rules-fixture","set":{"world.actions.opening":state}})
	if not _check(stored.get("ok",false),"fixture is isolated in the real QA Store"): return false
	session.world_cache = session.store.snapshot()
	session.consensus.set_world_revision(int(session.world_cache.world_revision))
	return true

func _place(peer: int,at: Vector3) -> void:
	var actor: FlightBodyV2 = session.players[peer]
	actor.freeze = true
	actor.global_transform = Transform3D(Basis.IDENTITY,at)
	actor.force_update_transform()
	PhysicsServer3D.body_set_state(actor.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,actor.global_transform)
	actor.linear_velocity = Vector3.ZERO
	actor.angular_velocity = Vector3.ZERO
	await physics_frame
	await physics_frame

func _near(peer: int) -> bool:
	var actor: FlightBodyV2 = session.players[peer]
	var marker: Dictionary = session.story.markers[ANCHOR]
	var at: Vector3 = session.story._point(marker)
	return actor.enabled and actor.global_position.distance_to(at)<=float(marker.radius) and session._line_clear(actor.global_position,at,actor.get_rid(),ANCHOR)

func _propose() -> void:
	session._action_received(1,"propose",{"kind":"campaign_choice","payload":{"target":TARGET,"option":OPTIONS[0]}})

func _confirm(peer: int,proposal: Dictionary) -> void:
	session._action_received(peer,"confirm",{"proposal_id":str(proposal.get("proposal_id","")),"world_revision":int(proposal.get("world_revision",-1))})

static func _decision_count(state: Dictionary) -> int:
	var total := 0
	for receipt: Dictionary in state.get("receipts",{}).values():
		if receipt.get("objective_id")==OBJECTIVE: total += 1
	return total

func _check(ok: bool,label: String,actual: Variant=null) -> bool:
	checks.append({"passed":ok,"label":label,"actual":actual})
	return ok

func _finish() -> void:
	if finished: return
	finished = true
	var failures: Array = checks.filter(func(row: Dictionary): return not row.passed)
	FileAccess.open(output+"/result.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"engine_errors":logger.errors,"fixture_receipts":fixture_receipts,"pending_on_store_failure":pending_before_failure,"committed":committed,"scope":"Actual MAIN F2 prepares from a blank QA world before the ordered Director receipt fixture is committed and Story is reloaded in the same already-loaded area. The fixture is choice-boundary rules evidence only; it has no I2 physical Result envelopes and is not used for cross-region/reentry preparation. Original chapter Choices/Consensus/branch/Story Store, nearby frozen QA actor placements, same-process second participant, unread confirm rejection, real Store.read_only failure/retry and duplicate/disk checks. F2 authors one flag and character memory, no discovery reward. No played prior campaign, flown route, normal unlock, LAN, graphics, performance or full campaign acceptance."},"\t"))
	print("CAMPAIGN_CHOICES_RESULT "+JSON.stringify({"checks":checks.size(),"failures":failures,"engine_errors":logger.errors,"fixture_receipts":fixture_receipts}))
	if is_instance_valid(session):
		session.store.read_only = false
		session.network.close()
		session.free()
		session = null
	await process_frame
	await physics_frame
	await process_frame
	quit(0 if failures.is_empty() and logger.errors.is_empty() else 1)
