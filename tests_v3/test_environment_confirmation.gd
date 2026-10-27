extends SceneTree
## Ordinary MAIN/I3 with native default cargo. Only initial region, authenticated
## guest lifecycle delivery and the otherwise gated major-choice proposal are QA.
const Cargo = preload("res://scripts/v3/gameplay/twin_thermal_cargo_session.gd")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")

class ObservedSession extends "res://scripts/v3/twin_session.gd":
    var qa_owner
    func _commit(receipt: String,changes: Dictionary,discovery = "") -> bool:
        var watched: bool = receipt.begins_with("choice:") and is_instance_valid(qa_owner)
        var before: Dictionary = qa_owner.observe_boundary(self) if watched else {}
        var accepted: bool = super._commit(receipt,changes,discovery)
        if watched:
            qa_owner.boundaries.append({"receipt":receipt,"accepted":accepted,"before":before,"after":qa_owner.observe_boundary(self)})
        return accepted

class GuestBrake extends Node:
    var owner_session: Node
    func _physics_process(_delta: float) -> void:
        if is_instance_valid(owner_session) and owner_session.active and not owner_session.simulation_paused and owner_session.players.has(2):
            owner_session.players[2].command = {"active":true,"mode":"assisted","body_relative":false,"planar":Vector3.ZERO,"vertical":0.0,"yaw":0.0,"brake":true,"fire":false}

class ErrorLogger extends Logger:
    var guard := Mutex.new()
    var errors: Array = []
    func _log_error(function: String,file: String,line: int,code: String,rationale: String,_notify: bool,kind: int,_trace: Array[ScriptBacktrace]) -> void:
        if kind == Logger.ERROR_TYPE_WARNING: return
        guard.lock()
        errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale})
        guard.unlock()

var logger := ErrorLogger.new()
var session: Node
var driver: GuestBrake
var profile := ""
var output := ""
var checks: Array = []
var boundaries: Array = []
var deliveries: Array = []
var snapshots: Dictionary = {}
var original_proposal: Dictionary = {}
var original_payload: Dictionary = {}
var finished := false
var began := 0

func _initialize() -> void:
    OS.add_logger(logger)
    _run.call_deferred()

func _run() -> void:
    for arg: String in OS.get_cmdline_user_args():
        if arg.begins_with("--qa-profile="): profile = arg.trim_prefix("--qa-profile=")
        if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
    if not profile.begins_with("qa_environment_confirmation_") or profile != profile.validate_filename() or DirAccess.dir_exists_absolute("user://profiles_v3/"+profile) or not output.begins_with("res://artifacts/v3/environment-confirmation-") or ".." in output or DirAccess.dir_exists_absolute(output):
        quit(2)
        return
    began = Time.get_ticks_msec()
    DirAccess.make_dir_recursive_absolute(output)
    create_timer(30.0).timeout.connect(func():
        if not finished:
            _check(false,"30 second ordinary MAIN bound; runner owned limit40s",_diagnostics())
            _finish())
    # MAIN is precisely one Node3D named TwinPulseSession with this base script.
    # Construct the subclass once: replacing an initialized base script would
    # discard its unparented default Node fields before _ready can own them.
    session = ObservedSession.new()
    session.name = "TwinPulseSession"
    session.qa_owner = self
    root.add_child(session)
    if not _check(session.profile_ready and session.store.commit({"id":"qa-confirmation-start-region-only","set":{"world.region_id":"I3"}}).get("ok",false),"new original QA Store receives only initial I3 location, no Story or choice fixture"): _finish(); return
    session.world_cache = session.store.snapshot()
    if not _check(session.start_flight("solo") and session.region_id=="I3" and session.thermal_cargo.supported() and session.world.build_errors.is_empty(),"ordinary MAIN factory constructs actual default I3 and binds original thermal participant",_diagnostics()): _finish(); return
    session.inputs.test_enabled = true
    session.inputs.test_frame = {"axes":{},"held":["brake"],"edges":[]}
    var guest_identity: String = Crypto.new().generate_random_bytes(16).hex_encode()
    session.network.guests[2] = guest_identity
    session._guest_joined(2,guest_identity,"tr01") # Explicit simulated authenticated transport lifecycle.
    driver = GuestBrake.new()
    driver.owner_session = session
    driver.process_physics_priority = 10
    root.add_child(driver)
    if not _check(session.players.size()==2 and session.players.has(1) and session.players.has(2) and session.identities.get(2)==guest_identity and session.players[1] is FlightBodyV2 and session.players[2] is FlightBodyV2,"original guest_joined creates a second real Flight and actual two-participant roster",_diagnostics()): _finish(); return
    var ready := false
    for unused in 240:
        if not await _frame(): return
        var capture: Dictionary = session.thermal_cargo.capture()
        if _module().ready and _module()._row().phase=="docked" and capture.get("ok",false): ready = true; break
    if not _check(ready and session.world.objects[Cargo.CARGO] is RigidBody3D and session.world.objects[Cargo.CARGO].mass==2.0,"ordinary physics freshly observes real default cargo on LOW; no native pose, holder or support evidence is injected",_diagnostics()): _finish(); return
    snapshots["before"] = session.store.snapshot()
    var baseline: Dictionary = snapshots.before
    var proposed: Dictionary = session.consensus.propose("major_choice",{"value":"shared"},1)
    original_proposal = session.consensus.current_proposal()
    original_payload = {"proposal_id":original_proposal.get("proposal_id",""),"world_revision":original_proposal.get("world_revision",-1)}
    if not _check(proposed.get("ok",false) and original_proposal.get("state")=="pending" and original_proposal.get("participants")==["1","2"] and original_proposal.get("confirmed")==["1"] and original_payload.world_revision==baseline.world_revision,"explicit gated-choice fixture uses original Consensus proposal and original two-participant revision; no natural prior-story claim",original_proposal): _finish(); return
    session.store.failure_point = "before_write"
    _deliver_confirmation("first original guest confirmation with real Store before_write fault")
    if not _wait_requested(): _finish(); return
    if not await _settle_confirmation(): return
    if not _check(boundaries.size()==1 and not boundaries[0].accepted,"confirmation crosses actual SaveGate boundary and reaches exactly one original decision Store attempt",_diagnostics()): _finish(); return
    var failed: Dictionary = boundaries[0]
    snapshots["failed"] = session.store.snapshot()
    var proposal: Dictionary = session.consensus.current_proposal()
    var kept: bool = snapshots.failed==baseline and session.world_cache==baseline and failed.before.store==baseline and failed.after.store==baseline
    kept = kept and failed.before.frame==failed.after.frame and failed.before.physical==failed.after.physical and failed.before.capture==failed.after.capture
    kept = kept and not session.last_commit_result.get("ok",true) and session.last_commit_result.get("error")=="SAVE_WRITE_FAILED" and session.last_commit_result.get("receipt")=="choice:"+str(original_payload.proposal_id)
    if not _check(kept,"failed original Store keeps exact world/cache/generation and same-frame native cargo, body/RID/custody/velocity/capture unchanged",failed): _finish(); return
    if not _check(proposal.get("state")=="ready" and proposal.get("proposal_id")==original_payload.proposal_id and proposal.get("world_revision")==original_payload.world_revision and proposal.get("confirmed")==["1","2"] and not baseline.world.choices.has("supply") and not snapshots.failed.world.choices.has("supply"),"failed choice leaves original ready proposal retryable at its original revision and does not publish a choice",proposal): _finish(); return
    var reader := Store.new(session.store.root_path)
    var loaded: Dictionary = reader.load_profile()
    if not _check(loaded.get("ok",false) and reader.snapshot()==baseline,"new independent original Store reader still sees pre-confirmation generation after failed write",loaded): _finish(); return
    session.store.failure_point = ""
    _deliver_confirmation("same original guest confirmation retried after clearing only Store fault")
    if not _wait_requested(): _finish(); return
    if not await _settle_confirmation(): return
    if not _check(boundaries.size()==2 and boundaries[1].accepted and session.consensus.current_proposal().is_empty(),"original repeated confirm successfully resolves the same ready proposal through one boundary/decision Store call",_diagnostics()): _finish(); return
    var success: Dictionary = boundaries[1]
    var saved: Dictionary = session.store.snapshot()
    var actual_cargo: Dictionary = saved.world.get("environment",{}).get("I3_thermal_cargo",{})
    var candidate: Dictionary = success.before.capture.get("state",{})
    var count := 0
    for id: String in saved.ledger.commits:
        if id.begins_with("choice:"+str(original_payload.proposal_id)+":"): count += 1
    var committed: bool = saved.generation==baseline.generation+1 and saved.world_revision==baseline.world_revision+1 and saved.world.choices.get("supply")=="shared" and count==1
    committed = committed and success.before.store==baseline and success.before.frame==success.after.frame and success.before.physical==success.after.physical and success.before.capture.get("ok",false) and not candidate.is_empty()
    committed = committed and session.store.matches_persisted_value(candidate,actual_cargo) and _module()._validate_save(actual_cargo).get("ok",false)
    if not _check(committed,"exactly one new original generation atomically contains chosen supply and the complete original thermal checkpoint captured in that same physical frame",{"boundary":success,"saved_generation":saved.generation,"choice_commits":count,"cargo":actual_cargo}): _finish(); return
    snapshots["success"] = saved
    reader = Store.new(session.store.root_path)
    loaded = reader.load_profile()
    snapshots["independent_reader"] = reader.snapshot() if loaded.get("ok",false) else loaded
    _check(loaded.get("ok",false) and reader.snapshot()==saved and reader.snapshot().world.choices.get("supply")=="shared" and _module()._validate_save(reader.snapshot().world.environment.I3_thermal_cargo).get("ok",false),"new original reader verifies combined choice plus real cargo checkpoint without extra environment generation",loaded)
    _check(session.story.state.get("completed",[]).is_empty() and saved.personal.discoveries==baseline.personal.discoveries and _module()._row().phase=="docked" and session.players[1].cargo_kg==0.0 and session.players[2].cargo_kg==0.0,"confirmation creates no prior Story completion, reward, pickup or fabricated delivery",_diagnostics())
    _finish()

func _deliver_confirmation(label: String) -> void:
    deliveries.append({"label":label,"peer":2,"verb":"confirm","payload":original_payload.duplicate(true),"proposal":session.consensus.current_proposal(),"frame":Engine.get_physics_frames()})
    session._action_received(2,"confirm",original_payload.duplicate(true)) # Authenticated sender delivery is explicitly simulated.

func _wait_requested() -> bool:
    return _check(session.environment_save_gate.pending(),"process-side confirmation queues capture rather than saving or mutating proposal immediately",{"gate":session.environment_save_gate.last_result,"proposal":session.consensus.current_proposal(),"generation":session.store.snapshot().generation})

func _settle_confirmation() -> bool:
    for unused in 180:
        if not await _frame(): return false
        if not session.environment_save_gate.pending(): return true
    _check(false,"ordinary MAIN completes native confirmation capture within three seconds",_diagnostics())
    _finish()
    return false

func observe_boundary(owner_session: Node) -> Dictionary:
    var body: RigidBody3D = owner_session.world.objects[Cargo.CARGO]
    return {"frame":Engine.get_physics_frames(),"store":owner_session.store.snapshot(),"capture":owner_session.thermal_cargo.capture(),"proposal":owner_session.consensus.current_proposal(),"physical":{"body_id":body.get_instance_id(),"rid":str(body.get_rid()),"frozen":body.freeze,"body":Cargo._body_snapshot(body),"custody":owner_session.thermal_cargo.module._custody.report()}}

func _module():
    return session.thermal_cargo.module

func _frame() -> bool:
    await physics_frame
    await process_frame
    return not finished

func _diagnostics() -> Dictionary:
    if not is_instance_valid(session): return {"session":"not_installed"}
    return {"active":session.active,"region":session.region_id,"players":session.players.keys(),"proposal":session.consensus.current_proposal(),"last_commit":session.last_commit_result.duplicate(true),"gate_pending":session.environment_save_gate.pending(),"gate_result":session.environment_save_gate.last_result.duplicate(true),"message":session.interface.message.text,"generation":session.store.snapshot().generation,"module":_module().status() if _module()!=null else {},"decision_attempts":boundaries.size()}

func _check(ok: bool,label: String,actual: Variant=null) -> bool:
    checks.append({"passed":ok,"label":label,"actual":actual})
    return ok

func _finish() -> void:
    if finished: return
    finished = true
    var diagnostics: Dictionary = _diagnostics()
    if is_instance_valid(driver): driver.owner_session=null; driver.free()
    driver = null
    if is_instance_valid(session):
        session.store.failure_point = ""
        session.environment_save_gate.cancel("qa_confirmation_teardown")
        session.thermal_cargo.clear()
        session.network.close()
        session.free()
    session = null
    await process_frame
    await physics_frame
    await process_frame
    var failures: Array = checks.filter(func(row: Dictionary): return not row.passed)
    var report := {"checks":checks,"failures":failures,"engine_errors":logger.errors,"boundaries":boundaries,"simulated_deliveries":deliveries,"original_proposal":original_proposal,"snapshots":snapshots,"diagnostics":diagnostics,"wall_seconds":float(Time.get_ticks_msec()-began)/1000.0,"scope":"Actual ordinary MAIN native root, instrumented Session subclass only observes calls around original super._commit. New private profile with explicit I3 starting location, host and original joined second actual Flight, default real 2kg LOW cargo freshly observed by ordinary physics. Authenticated guest join/confirm delivery is simulated; direct original Consensus major_choice proposal deliberately bypasses initial chapter eligibility and is not naturally played history. Actual SaveGate and original decision Store before_write failure followed by original confirm retry. Native body/RID/custody/capture compared inside each unchanged physical frame, not across freely advancing frames. Complete actual docked version1 cargo and choice share one successful generation. No cargo pose/holder/clock/credit/success endpoint, prior Story, pickup/carried state, second repository, real ENet/authentication, two-PC LAN or full Registry reopen is claimed."}
    FileAccess.open(output+"/result.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
    print("ENVIRONMENT_CONFIRMATION_RESULT ",JSON.stringify({"checks":checks.size(),"failures":failures,"engine_errors":logger.errors,"wall_seconds":report.wall_seconds}))
    quit(0 if failures.is_empty() and logger.errors.is_empty() else 1)
