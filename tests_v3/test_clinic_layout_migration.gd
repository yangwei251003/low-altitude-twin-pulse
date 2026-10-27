extends SceneTree
## Explicit migration fixtures, not a completed journey or a duration benchmark.
## Hydraulic quantities/history use real Runtime ticks and Progress observation.
## Valve pose, deck-height/access and predecessor actions are declared QA inputs.
## MAIN/Store checks use isolated fresh profiles; there is no UDP or GPU capture.
const MAIN = preload("res://scenes/v3/main.tscn")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const Works = preload("res://scripts/v3/world/twin_clinic_waterworks.gd")
const Runtime = preload("res://scripts/v3/environment/twin_clinic_water_runtime.gd")
const Progress = preload("res://scripts/v3/gameplay/actions/twin_clinic_progress.gd")
const Clinic = preload("res://scripts/v3/gameplay/twin_clinic_session.gd")
const Migration = preload("res://scripts/v3/world/twin_clinic_layout_migration.gd")
const Director = preload("res://scripts/v3/gameplay/actions/twin_action_director.gd")
const ActionData = preload("res://tests_v3/test_clinic_action.gd") # Constants only.
const LEGACY_FILE_SHA := "4369c0a9c07a0517cb220c713ae0f5f31a3cbdecf063b15e49bb646c313ef6cd"
const LEGACY_STATE_SHA := "6ffe938bf721f5f9b146bde159b41226c368bfc7544b3a4f591a655255598d4c"
const REWARD := "I2:clinic_priority_misroute"
var profile := ""
var base := ""
var phase := "setup"
var checks: Array = []
var failures: Array = []
var fixtures: Dictionary = {}
var legacy_layout: Dictionary = {}
var current_digest := ""
var baseline: Dictionary = {}
var old_actions: Dictionary = {}
var director = Director.new()
var session
var done := false

class TestLogger extends Logger:
	var errors: Array = []
	var guard := Mutex.new()
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		guard.lock()
		errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale,"type":error_type})
		guard.unlock()
var error_logger := TestLogger.new()

func _initialize() -> void:
	OS.add_logger(error_logger)
	_run.call_deferred()

func check(ok: bool, label: String, detail: Variant = null) -> void:
	checks.append({"phase":phase,"label":label,"passed":ok,"detail":detail})
	if not ok: failures.append(label)

func _run() -> void:
	var count := 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="):
			profile = arg.trim_prefix("--qa-profile=")
			count += 1
		elif arg.begins_with("--qa-"):
			print("CLINIC_MIGRATION refuses unrelated QA drivers")
			_finish(2)
			return
	if count != 1 or not profile.begins_with("qa_clinic_migration_") or profile != profile.validate_filename():
		print("One fresh --qa-profile=qa_clinic_migration_<unique> is required")
		_finish(2)
		return
	base = "user://qa_v3_clinic_migration/" + profile
	if DirAccess.dir_exists_absolute(base) or DirAccess.dir_exists_absolute("user://profiles_v3/" + profile):
		print("CLINIC_MIGRATION refuses an existing QA directory")
		_finish(2)
		return
	create_timer(120.0).timeout.connect(func():
		if not done:
			check(false,"bounded migration test timed out")
			_finish(2))
	if not _build_fixtures():
		_finish(1)
		return
	_test_prepare_matrix()
	_test_rejections()
	_test_branch_transaction()
	if failures.is_empty() and _engine_healthy("before MAIN integration"): await _test_main_wiring()
	_finish(0 if failures.is_empty() and error_logger.errors.is_empty() else 1)

func _same(a: Variant, b: Variant) -> bool:
	# Exact values, allowing only JSON's integer/float representation boundary.
	# No tolerance, truncation or rounding is used for fractional values.
	if (a is int or a is float) and (b is int or b is float): return a == b
	if typeof(a) != typeof(b): return false
	if a is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not _same(a[key],b[key]): return false
		return true
	if a is Array:
		if a.size() != b.size(): return false
		for index in range(a.size()):
			if not _same(a[index],b[index]): return false
		return true
	return a == b

func _disk_form(value: Variant) -> Variant:
	# Exactly the Store's full-precision JSON serialization boundary.
	return JSON.parse_string(JSON.stringify(value,"",true,true))

func _build_fixtures() -> bool:
	check(FileAccess.get_sha256(Migration.LEGACY_PATH)==LEGACY_FILE_SHA,"legacy layout is the frozen dev16 byte sequence")
	legacy_layout = JSON.parse_string(FileAccess.get_file_as_string(Migration.LEGACY_PATH))
	current_digest = JSON.stringify(JSON.parse_string(FileAccess.get_file_as_string(Works.PATH)),"",true,true).sha256_text()
	var old = Works.new()
	var loaded: Dictionary = old.configure(legacy_layout,{},false)
	check(loaded.ok,"actual Works configures the frozen old layout",loaded)
	if not loaded.ok:
		old.free()
		return false
	baseline = old.snapshot()
	old.free()
	check(baseline.layout_sha256==LEGACY_STATE_SHA and current_digest!=LEGACY_STATE_SHA,"old state digest is distinct from current reviewed layout")
	var extensions: Array = ActionData.OLD_EXTENSIONS.duplicate()
	extensions.append(ActionData.CLINIC_PATH)
	var definitions: Dictionary = director.load_definitions(Director.DEFAULT_PATH,extensions)
	check(definitions.ok,"production eight-action Director loads historical fixtures")
	if not definitions.ok: return false
	old_actions = director.default_state()
	for row in ActionData.OLD_EVENTS:
		var event := {"id":"migration-history:"+str(row[0]),"type":row[1],"target_id":row[2],"option":row[3]}
		var result: Dictionary = director.apply_event(old_actions,event,{"is_authority":true,"validated":true,"region_id":str(row[0]).get_slice(":",0)})
		if not result.get("changed",false):
			check(false,"explicit predecessor fixture accepted",{"row":row,"result":result})
			return false
		old_actions = result.state
	check(old_actions.completed.size()==27,"historical fixture contains exactly the existing27 goals")
	var initial := _rig("gravity")
	_record_fixture("initial",initial,0)
	var half: Dictionary = fixtures.initial.duplicate(true)
	half.envelope.mechanism.gravity_fraction = 0.5
	half.envelope.mechanism.gravity_speed = 1.25
	half.envelope.mechanism.axis.position_m = 0.6
	half.envelope.mechanism.axis.velocity_mps = 1.25
	fixtures["valve_mid_velocity"] = half
	var gravity := _rig("gravity")
	for unused in range(20):
		if not _advance_fixture(gravity): return false
	_record_fixture("gravity_in_progress",gravity,0) # Operation before diagnosis is legal.
	var pump := _rig("pump")
	for unused in range(20):
		if not _advance_fixture(pump): return false
	_record_fixture("pump_in_progress",pump,2)
	var steps := 0
	while int(gravity.water.status().clinic_volume_ml)<Runtime.TARGET_ML and steps<1200:
		if not _advance_fixture(gravity): return false
		steps += 1
	check(int(gravity.water.status().clinic_volume_ml)==Runtime.TARGET_ML,"actual hydraulic ticks reach target; no volume injection")
	if int(gravity.water.status().clinic_volume_ml)!=Runtime.TARGET_ML: return false
	for unused in range(20):
		if not _advance_fixture(gravity): return false
	check(gravity.progress.snapshot().stabilized_once,"production history observes two stable simulated seconds with explicit physical-access fixture")
	_record_fixture("full_pending_confirm",gravity,3)
	var confirm: Dictionary = gravity.progress.prepare_confirm(_mechanism(gravity),_status(gravity),true)
	check(confirm.ok and gravity.progress.adopt_confirm(confirm),"production confirmation makes the explicit already-commissioned history fixture")
	_record_fixture("commissioned",gravity,4)
	for name in fixtures:
		var validator = Works.new()
		var valid: Dictionary = validator.configure(legacy_layout,fixtures[name].envelope.mechanism,false)
		check(valid.ok,"old full strict validator accepts fixture "+name,valid)
		validator.free()
	return failures.is_empty()

func _rig(route: String) -> Dictionary:
	var water = Runtime.new()
	check(water.load_definition().ok,"production Runtime initializes "+route+" fixture")
	return {"water":water,"progress":Progress.new(),"serial":0,"route":route}

func _mechanism(rig: Dictionary) -> Dictionary:
	var result: Dictionary = baseline.duplicate(true)
	result.runtime = rig.water.snapshot()
	result.serial = int(rig.serial)
	result.gravity_fraction = 1.0 if int(result.runtime.facts.gravity_open_permille)>0 else 0.0
	result.pump_fraction = 1.0 if int(result.runtime.facts.pump_open_permille)>0 else 0.0
	result.pump_latched = result.pump_fraction==1.0
	result.powered = bool(result.runtime.facts.pump_powered)
	result.axis.position_m = float(result.gravity_fraction)*1.2
	result.axis.last_serial = {"1":7} # Saved authority input ledger must survive prepare.
	return result

func _status(rig: Dictionary) -> Dictionary:
	var result: Dictionary = rig.water.status()
	result.deck_top_y = result.desired_deck_top_m # Explicit access/pose fixture, not a physical clearance proof.
	return result

func _advance_fixture(rig: Dictionary) -> bool:
	var before := _mechanism(rig)
	var facts := {"gravity_open_permille":1000 if rig.route=="gravity" else 0,"pump_open_permille":1000 if rig.route=="pump" else 0,"pump_powered":rig.route=="pump","platform_blocked":false}
	var step: Dictionary = rig.water.step(0.1,facts)
	if not step.ok:
		check(false,"fixture hydraulic step rejected",step)
		return false
	rig.serial = int(rig.serial)+1
	var observed: Dictionary = rig.progress.observe(0.1,before,_mechanism(rig),_status(rig),step,true)
	if not observed.ok: check(false,"fixture history observation rejected",observed)
	return observed.ok

func _record_fixture(name: String, rig: Dictionary, completed_count: int) -> void:
	fixtures[name] = {"envelope":{"version":1,"mechanism":_mechanism(rig),"history":rig.progress.snapshot()},"goals":completed_count,"route":rig.route}

func _action_state(count: int, route: String) -> Dictionary:
	var state: Dictionary = old_actions.duplicate(true)
	for index in range(count):
		var row: Array = ActionData.EVENTS[index].duplicate()
		if index==1: row[3]=route
		var result: Dictionary = director.apply_event(state,{"id":"migration-clinic:"+str(row[0]),"type":row[1],"target_id":row[2],"option":row[3]},{"is_authority":true,"validated":true,"region_id":"I2"})
		if not result.get("changed",false):
			check(false,"clinic historical objective fixture accepted",result)
			return {}
		state = result.state
	return state

func _world(fixture: Dictionary, region: String = "I1") -> Dictionary:
	var actions := _action_state(int(fixture.goals),str(fixture.route))
	return {"region_id":region,"branch_id":"main","flags":actions.flags.duplicate(true),"choices":{},"entities":{},"completed_objectives":actions.completed.duplicate(),"actions":{"opening":actions},"environment":{"I2_water":fixture.envelope.duplicate(true)}}

func _expected(envelope: Dictionary) -> Dictionary:
	var value: Dictionary = envelope.duplicate(true)
	value.mechanism.layout_sha256 = current_digest
	# Existing host disk-restore rule, not a new migration loss.
	value.mechanism.axis.velocity_mps = 0.0
	value.mechanism.gravity_speed = 0.0
	return value

func _test_prepare_matrix() -> void:
	phase = "host preparation matrix"
	var clinic = Clinic.new()
	for name in fixtures:
		var fixture: Dictionary = fixtures[name]
		var original: Dictionary = fixture.envelope.duplicate(true)
		var helper: Dictionary = Migration.prepare(original.mechanism)
		var digest_only: Dictionary = original.mechanism.duplicate(true)
		digest_only.layout_sha256 = current_digest
		check(helper.ok and helper.migrated and _same(helper.state,digest_only),name+": pure helper changes only layout digest")
		for region in ["I1","F1","I2"]:
			var world := _world(fixture,region)
			var before: Dictionary = world.duplicate(true)
			var prepared: Dictionary = clinic.prepare(world,region,true)
			check(prepared.ok and prepared.get("migrated",false),name+": host restores legacy state while visiting "+region,prepared.get("error",""))
			if prepared.ok:
				check(_same(prepared.state,_expected(original)),name+": "+region+" preserves every field except digest and existing authority stop")
				var second_world: Dictionary = world.duplicate(true)
				second_world.environment.I2_water = prepared.state.duplicate(true)
				var again: Dictionary = clinic.prepare(second_world,region,true)
				check(again.ok and not again.get("migrated",true) and _same(again.get("state"),prepared.state),name+": current-state preparation is idempotent in "+region)
				clinic.discard(again)
			clinic.discard(prepared)
			check(_same(world,before) and _same(fixture.envelope,original),name+": preparation never mutates source world/history/rewards")
	var missing: Dictionary = _world(fixtures.initial)
	missing.environment.erase("I2_water")
	var optional: Dictionary = clinic.prepare(missing,"I1",true)
	check(optional.ok and optional.get("module")==null,"never-visited legacy world outside I2 does not invent a water module")
	clinic.discard(optional)

func _test_rejections() -> void:
	phase = "strict rejection"
	var clinic = Clinic.new()
	for kind in ["unknown_digest","water_definition","water_conservation","axis_config","axis_pose","history_serial","commissioned_flag","missing_with_results"]:
		var world := _world(fixtures.commissioned)
		match kind:
			"unknown_digest": world.environment.I2_water.mechanism.layout_sha256="f".repeat(64)
			"water_definition": world.environment.I2_water.mechanism.runtime.simulation.definition_digest="e".repeat(64)
			"water_conservation": world.environment.I2_water.mechanism.runtime.simulation.nodes[Runtime.SOURCE].clean_ml+=1
			"axis_config": world.environment.I2_water.mechanism.axis.config_sha256="d".repeat(64)
			"axis_pose": world.environment.I2_water.mechanism.axis.position_m=0.4
			"history_serial": world.environment.I2_water.history.observed_serial+=1
			"commissioned_flag": world.flags.erase(Progress.READY_FLAG)
			"missing_with_results": world.environment.erase("I2_water")
		var before: Dictionary = world.duplicate(true)
		var rejected: Dictionary = clinic.prepare(world,"I2",true)
		check(not rejected.ok and _same(world,before),kind+": invalid old state is rejected without mutation/default initialization",rejected.get("error",""))
		clinic.discard(rejected)
	var remote: Dictionary = clinic.prepare(_world(fixtures.initial),"I2",false)
	check(not remote.ok,"client prepare does not migrate an old host layout")
	clinic.discard(remote)
	var view = Works.new()
	check(view.load_layout({},false).ok,"current client module initializes for strict snapshot test")
	var original: Dictionary = view.snapshot()
	var applied: Dictionary = view.apply_snapshot(fixtures.pump_in_progress.envelope.mechanism)
	check(not applied.ok and _same(view.snapshot(),original),"client apply_snapshot rejects old digest without changing water or geometry")
	view.free()

func _new_store(name: String):
	var result = Store.new(base.path_join(name))
	check(result.load_profile().ok,"fresh isolated Store opens "+name)
	return result

func _seed_store(store, fixture: Dictionary, id: String, region: String = "I1") -> bool:
	var world := _world(fixture,region)
	var changes: Dictionary = {}
	for key in world:
		if key!="branch_id": changes["world."+str(key)] = world[key]
	var saved: Dictionary = store.commit({"id":id,"set":changes,"append":{"personal.collections":["migration-keeps-collection"],"personal.discoveries":world.actions.opening.discoveries}})
	check(saved.ok,"explicit old world fixture committed: "+id,saved)
	return saved.ok

func _test_branch_transaction() -> void:
	phase = "atomic Store branch migration"
	var store = _new_store("branch")
	var guest = _new_store("guest-receipt")
	var guest_id: String = str(guest.snapshot().profile_id)
	if not _seed_store(store,fixtures.commissioned,"legacy-main"): return
	check(store.queue_guest_receipt(guest_id,REWARD,{"discoveries":[REWARD]}).ok,"existing unacknowledged personal receipt is persisted")
	check(store.fork_branch("legacy-target","Legacy target",false).ok,"independent legacy target is frozen before switching")
	check(store.commit({"id":"active-marker","set":{"world.choices.migration_sentinel":"main"}}).ok,"active world differs from target")
	var clinic = Clinic.new()
	var target: Dictionary = store.snapshot().branches["legacy-target"].world
	var prepared: Dictionary = clinic.prepare(target,"I2",true)
	check(prepared.ok and prepared.migrated,"actual target branch preparation yields valid upgrade")
	if not prepared.ok: return
	var patch := {"world.environment.I2_water":prepared.state.duplicate(true)}
	clinic.discard(prepared)
	var target_hash: String = store.branch_world_hash("legacy-target")
	var reread = Store.new(store.root_path)
	check(reread.load_profile().ok and reread.branch_world_hash("legacy-target")==target_hash,"branch fingerprint survives actual JSON disk reread")
	# A real intervening target write, not merely an incorrectly formatted hash.
	check(store.switch_branch("legacy-target").ok and store.commit({"id":"target-changed-after-prepare","set":{"world.choices.preparation_race":true}}).ok and store.switch_branch("main").ok,"intervening target-branch edit is a declared CAS race fixture")
	var before: Dictionary = store.snapshot()
	check(store.branch_world_hash("legacy-target")!=target_hash and not store.switch_branch("legacy-target",patch,target_hash).ok and _same(store.snapshot(),before),"stale prepared fingerprint cannot switch or patch an edited target")
	target_hash = store.branch_world_hash("legacy-target")
	for path in ["personal.discoveries","encounter.anything","world.branch_id","world..flags"]:
		check(not store.switch_branch("legacy-target",{path:[]},target_hash).ok and _same(store.snapshot(),before),"prepared branch rejects illegal patch path "+path)
	check(not store.switch_branch("main",patch,store.branch_world_hash("main")).ok and _same(store.snapshot(),before),"active branch plus nonempty patch is rejected, not silently ignored")
	for point in ["before_write","after_write","before_publish"]:
		store.failure_point = point
		var failed: Dictionary = store.switch_branch("legacy-target",patch,target_hash)
		check(not failed.ok and _same(store.snapshot(),before),point+": branch/migration/generation/ledger remain unchanged in memory")
		var disk = Store.new(store.root_path)
		check(disk.load_profile().ok and _same(disk.snapshot(),before),point+": independent reread ignores unpublished generation and preserves original branch")
		store.failure_point = ""
	var switched: Dictionary = store.switch_branch("legacy-target",patch,target_hash)
	var after: Dictionary = store.snapshot()
	check(switched.ok and after.world.branch_id=="legacy-target" and int(after.generation)==int(before.generation)+1 and int(after.world_revision)==int(before.world_revision)+1,"successful switch and migration publish exactly one generation/revision")
	check(_same(after.world,after.branches["legacy-target"].world) and _same(after.world.environment.I2_water,_disk_form(patch["world.environment.I2_water"])),"active and archived target worlds contain the same complete migrated envelope")
	check(_same(after.branches.main,before.branches.main) and _same(after.personal,before.personal) and _same(after.ledger,before.ledger) and after.lineage_id==before.lineage_id,"other branch, personal assets, all receipt ledgers and lineage are unchanged")
	var disk = Store.new(store.root_path)
	check(disk.load_profile().ok and _same(disk.snapshot(),after),"successful atomic branch migration survives an independent Store load")
	check(store.switch_branch("legacy-target").ok and _same(store.snapshot(),after),"legacy no-patch same-branch call remains an idempotent no-op")
	var pending: Array = store.pending_guest_receipts(guest_id)
	check(pending.size()==1,"migration does not create another guest reward receipt")
	if pending.size()==1:
		check(guest.apply_guest_receipt(pending[0]).ok,"existing guest discovery remains claimable after migration")
		var received: Dictionary = guest.snapshot()
		var repeated: Dictionary = guest.apply_guest_receipt(pending[0])
		check(repeated.ok and repeated.duplicate and _same(guest.snapshot(),received) and received.personal.discoveries.count(REWARD)==1,"repeat delivery cannot duplicate the old clinic discovery")

func _engine_healthy(label: String) -> bool:
	if error_logger.errors.is_empty(): return true
	check(false,"engine errors prevent further test execution: "+label,error_logger.errors.duplicate(true))
	return false

func _session_has_property(property_name: String) -> bool:
	if not is_instance_valid(session): return false
	for entry in session.get_property_list():
		if str(entry.name)==property_name: return true
	return false

func _main_script_available() -> bool:
	# A failed Session script can leave PackedScene.instantiate() returning a
	# perfectly valid bare Node3D. Never infer script availability from the node.
	if not is_instance_valid(session) or session.get_script()==null or not session.has_method("start_flight"): return false
	for property_name in ["active","network","inputs","players","profile_ready","store","clinic","world"]:
		if not _session_has_property(property_name): return false
	return true

func _disable_callbacks() -> bool:
	if not _main_script_available() or not _engine_healthy("before disabling Session callbacks"):
		check(false,"MAIN must have a usable Session script before accessing its callbacks")
		return false
	session.set_process(false)
	session.set_physics_process(false)
	if not is_instance_valid(session.inputs) or not session.players is Dictionary:
		check(false,"MAIN initialization must create inputs and player registry")
		return false
	session.inputs.set_process(false)
	session.inputs.set_physics_process(false)
	for body in session.players.values():
		body.freeze = true
		body.set_process(false)
		body.set_physics_process(false)
	return true

func _test_main_wiring() -> void:
	phase = "real MAIN startup and target branch"
	if not _engine_healthy("before MAIN instantiate"): return
	session = MAIN.instantiate()
	if not _main_script_available():
		check(false,"MAIN instantiated without its required Session script; abort immediately",{"node_class":session.get_class() if is_instance_valid(session) else "null","engine_errors":error_logger.errors.duplicate(true)})
		return
	root.add_child(session)
	if not _engine_healthy("MAIN initialization") or not _disable_callbacks(): return
	check(session.profile_ready,"real MAIN bootstrap uses only the fresh explicit QA profile")
	if not session.profile_ready: return
	if not _seed_store(session.store,fixtures.gravity_in_progress,"main-old-background"): return
	check(session.store.queue_guest_receipt("migration_guest",REWARD,{"discoveries":[REWARD]}).ok,"MAIN old profile contains a pending guest receipt sentinel")
	var before: Dictionary = session.store.snapshot()
	session.store.failure_point = "before_publish"
	var started: bool = session.start_flight("solo")
	check(not started and not session.active and not session.clinic.ready and not is_instance_valid(session.world),"failed startup migration cannot adopt candidate world or run hydraulics")
	check(_same(session.store.snapshot(),before),"failed startup leaves original active world/history/generation intact")
	var disk = Store.new(session.store.root_path)
	check(disk.load_profile().ok and _same(disk.snapshot(),before),"failed startup retains the exact disk generation")
	session.store.failure_point = ""
	check(session.start_flight("solo"),"startup retry commits reviewed upgrade before adopting real I1 with background clinic")
	if not _disable_callbacks(): return
	if not session.active: return
	var after: Dictionary = session.store.snapshot()
	check(session.region_id=="I1" and session.clinic.ready and is_instance_valid(session.clinic.background),"legacy I2 progress migrates even when its host starts in I1")
	check(int(after.generation)==int(before.generation)+1 and _same(after.world.environment.I2_water,_disk_form(_expected(before.world.environment.I2_water))),"startup stores exact hydraulic/history upgrade once")
	check(_same(after.personal,before.personal) and _same(after.ledger.guest_outbox,before.ledger.guest_outbox) and _same(after.ledger.guest_received,before.ledger.guest_received),"startup migration neither awards nor discards personal/guest records")
	await physics_frame
	# Explicit disk fixture: author an inactive old I2 branch, then return Store
	# to the currently running main branch. No traversal/completion is claimed.
	check(session.store.fork_branch("legacy-i2","Legacy I2",false).ok and session.store.switch_branch("legacy-i2").ok,"create explicit inactive legacy branch fixture")
	if not _seed_store(session.store,fixtures.pump_in_progress,"branch-old-pump","I2"): return
	check(session.store.switch_branch("main").ok,"restore active Store branch before exercising actual UI branch action")
	session.world_cache = session.store.snapshot()
	session.consensus.configure([1],int(session.world_cache.world_revision))
	var old_target: Dictionary = session.world_cache.branches["legacy-i2"].world.duplicate(true)
	var personal: Dictionary = session.world_cache.personal.duplicate(true)
	var outbox: Dictionary = session.world_cache.ledger.guest_outbox.duplicate(true)
	session._ui_action("branch",{"id":"legacy-i2"})
	if not _disable_callbacks(): return
	var branch: Dictionary = session.store.snapshot()
	check(session.active and session.region_id=="I2" and branch.world.branch_id=="legacy-i2" and session.clinic.module==session.world.clinic,"real branch action adopts the prepared visible I2 module")
	check(_same(branch.world.environment.I2_water,_disk_form(_expected(old_target.environment.I2_water))) and _same(branch.world,branch.branches["legacy-i2"].world),"real branch wiring persists migration into target and active world together")
	check(_same(branch.personal,personal) and _same(branch.ledger.guest_outbox,outbox) and _same(branch.world.actions,old_target.actions),"real branch change preserves goals/personal collection and pending reward count")
	var reread = Store.new(session.store.root_path)
	check(reread.load_profile().ok and _same(reread.snapshot(),branch),"real branch wiring reads back exactly after migration")
	await physics_frame

func _finish(code: int) -> void:
	if done: return
	done = true
	if is_instance_valid(session):
		# Cleanup is also valid for a bare Node3D after a script parse failure.
		if _session_has_property("active"): session.set("active",false)
		var transport: Node = session.get_node_or_null("Network")
		if is_instance_valid(transport) and transport.has_method("close"): transport.call("close")
		session.free()
	if code==0 and not error_logger.errors.is_empty(): code=1
	print("CLINIC_LAYOUT_MIGRATION checks=%d failures=%d profile=%s" % [checks.size(),failures.size(),profile])
	print("CLINIC_LAYOUT_MIGRATION_RESULT "+JSON.stringify({"passed":code==0,"checks":checks,"failures":failures,"engine_errors":error_logger.errors,"profile":profile,"limits":["Historical actions and legal moving valve pose are explicit QA fixtures, not player completion.","Runtime transfer/history are real; physical access and deck alignment in pure fixtures are supplied host evidence.","MAIN startup and branch adoption plus actual Store disk failure/reload are exercised; no fresh static-geometry sweep, ENet, mixed executable handshake, GPU, human playtime or performance acceptance."]}))
	OS.remove_logger(error_logger)
	quit(code)
