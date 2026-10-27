extends SceneTree
## Pure seal/Store verification over an actual successfully saved cold A.
## No MAIN/physics scene, synthesized successful endpoint or new preparation.
const Proof=preload("res://scripts/v3/gameplay/twin_canal_preparation_proof.gd")
const Ledger=preload("res://scripts/v3/gameplay/twin_i2_result_ledger.gd")
const Store=preload("res://scripts/v3/core/twin_world_store.gd")
const SOURCE="res://tests_v3/candidates/canal_session/evidence/local_cooling_20261020_224906_9bca43/result.json"
const SHA="8731ae899aadc871659624fcca56c02c92dacb150011df6d472a111476499a38"
const SELECTOR="snapshots.session_gate.saved"
class ErrorLogger extends Logger:
    var guard:=Mutex.new()
    var errors: Array=[]
    func _log_error(function: String,file: String,line: int,code: String,rationale: String,_notify: bool,kind: int,_trace: Array[ScriptBacktrace]) -> void:
        if kind==Logger.ERROR_TYPE_WARNING: return
        guard.lock()
        errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale})
        guard.unlock()
var logger:=ErrorLogger.new()
var checks: Array=[]
var output: String=""
var profile: String=""
var proof: Dictionary={}
var store_path: String=""
var finished:=false

func _initialize() -> void:
    OS.add_logger(logger)
    _run.call_deferred()

func _run() -> void:
    for arg: String in OS.get_cmdline_user_args():
        if arg.begins_with("--qa-profile="): profile=arg.trim_prefix("--qa-profile=")
        if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
    if profile.is_empty(): profile="qa_canal_preparation_"+str(OS.get_process_id())+"_"+str(Time.get_ticks_usec())
    if not profile.begins_with("qa_canal_preparation_") or profile!=profile.validate_filename() or DirAccess.dir_exists_absolute("user://profiles_v3/"+profile) or (not output.is_empty() and (not output.begins_with("res://artifacts/v3/canal-preparation-proof-") or ".." in output or DirAccess.dir_exists_absolute(output))): quit(2); return
    if not output.is_empty(): DirAccess.make_dir_recursive_absolute(output)
    if not _check(FileAccess.get_sha256(SOURCE)==SHA,"exact pinned original local-cooling evidence file"): _finish(); return
    var evidence: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
    var required: Array=["fresh actual350ms Custody support proves current WORK cold preparation before Brief","SCAN handshake yields frozen physical state and valid paused save cache","asynchronous Session publishes current physical scan once then releases"]
    var passed: Array=[]
    for row: Dictionary in evidence.details:
        if row.label in required and row.get("ok",false): passed.append(row.label)
    if not _check(evidence.engine_errors.is_empty() and passed.size()==required.size() and evidence.snapshots.session_gate.succeeded.ok,"selected A actually passed original current support, capture and Store publication; final unrelated fixture assertion is not called a green run",{"passed_source_checks":passed,"source_total_failures":evidence.failures.size()}): _finish(); return
    var original: Dictionary=evidence.snapshots.session_gate.saved.duplicate(true)
    if not _check(Proof.Scan.validate(original).ok and Ledger._local_cooling_history(original,original.rules),"unmodified real original SCAN is accepted by its schema and the one original local-cooling history predicate"): _finish(); return
    var before: Dictionary=original.duplicate(true)
    var captured: Dictionary=Proof.capture(original)
    if not _check(captured.get("ok",false),"seal the actual original cold preparation checkpoint",captured): _finish(); return
    proof=captured.proof
    _check(proof.envelope is Array and proof.envelope.size()>1 and Proof.join(proof.envelope)==JSON.stringify(original,"",true,true) and proof.sha256==Proof.join(proof.envelope).sha256_text(),"seal retains the complete sorted/fullprecision original JSON in ordered4096-character chunks and exact joined bytes SHA, without normalizing physical values")
    var checked: Dictionary=Proof.validate(proof)
    if not _check(checked.get("ok",false) and Ledger._local_cooling_history(checked.envelope,checked.envelope.rules),"validate seal returns the original schema/actual cold historical envelope",checked.get("code")): _finish(); return
    _check(original==before,"capture/validate do not change actual input rules, poses, clocks, thermal balances or credit")
    _check(Proof.capture(original).proof==proof,"repeating pure capture of identical original evidence is deterministic")
    var reversed: Dictionary={}
    var keys: Array=original.keys()
    keys.reverse()
    for key: String in keys: reversed[key]=original[key]
    var reordered: Dictionary=Proof.capture(reversed)
    _check(reordered.get("ok",false) and reordered.proof.sha256==proof.sha256,"canonical key order preserves exact seal without tolerance")
    checked.envelope.rules.revision+=1
    _check(Proof.validate(proof).ok and original==before,"returned validation envelope is an independent copy, not a mutable alias to the sealed proof")
    var changed_input: Dictionary=original.duplicate(true)
    var isolated: Dictionary=Proof.capture(changed_input)
    changed_input.rules.command_serial+=1
    _check(isolated.ok and Proof.validate(isolated.proof).ok and isolated.proof==proof,"later caller input mutation cannot alter an already captured proof")
    for mutation: String in ["missing","extra","version","sha","payload_byte","chunks_type","empty_chunks","empty_chunk","short_interior","oversized_chunk","too_many_chunks","reordered_chunks","unknown_kind","bad_original_schema","substituted_valid_history"]:
        var corrupt: Dictionary=proof.duplicate(true)
        match mutation:
            "missing": corrupt.erase("envelope")
            "extra": corrupt["credit"]=1
            "version": corrupt.version=2
            "sha": corrupt.sha256="0".repeat(64)
            "payload_byte": corrupt.envelope[0]=" "+str(corrupt.envelope[0]).substr(1)
            "chunks_type": corrupt.envelope=Proof.join(proof.envelope)
            "empty_chunks": corrupt.envelope=[]
            "empty_chunk": corrupt.envelope[-1]=""
            "short_interior": corrupt.envelope[0]=str(corrupt.envelope[0]).left(Proof.CHUNK_CHARS-1)
            "oversized_chunk": corrupt.envelope[0]+="0"
            "too_many_chunks":
                corrupt.envelope=[]
                for unused in Proof.MAX_CHUNKS+1: corrupt.envelope.append("0".repeat(Proof.CHUNK_CHARS))
            "reordered_chunks":
                var first: String=corrupt.envelope[0]
                corrupt.envelope[0]=corrupt.envelope[1]
                corrupt.envelope[1]=first
            "unknown_kind":
                var invalid: Dictionary=original.duplicate(true)
                invalid.kind="not_a_canal_checkpoint"
                _check(not Proof.capture(invalid).ok,"capture refuses an unknown physical checkpoint kind")
                corrupt.envelope=Proof._chunks(JSON.stringify(invalid,"",true,true))
                corrupt.sha256=Proof.join(corrupt.envelope).sha256_text() # A valid SHA cannot bypass the original schema.
            "bad_original_schema":
                var invalid: Dictionary=original.duplicate(true)
                invalid.rules.job_requested=1 # bool is never a numeric alias.
                _check(not Proof.capture(invalid).ok,"capture retains original strict thermal/rule schema")
                corrupt.envelope=Proof._chunks(JSON.stringify(invalid,"",true,true))
                corrupt.sha256=Proof.join(corrupt.envelope).sha256_text()
            "substituted_valid_history": corrupt.envelope=Proof._chunks(JSON.stringify(evidence.snapshots.latest_roundtrip.saved,"",true,true))
        _check(not Proof.validate(corrupt).ok,"corrupt or substituted proof is rejected: "+mutation)
    # An original Rules-only reheat example demonstrates the old A predicate
    # becoming false. It is NOT a new physical checkpoint and is never sealed
    # or saved as current physical evidence by this test.
    var rules=Proof.Wait.Rules.new()
    if not _check(rules.configure().ok and rules.restore(original.rules).ok,"original thermal kernel restores actual source for a clearly rule-only reheat example"): _finish(); return
    var state: Dictionary=rules.snapshot()
    var heated: Dictionary=rules.apply_command({"serial":int(state.command_serial)+1,"expected_revision":state.revision,"kind":"thermal","cassette_id":Proof.Wait.Rules.CASSETTES[1],"delta_mc":25000},true,false)
    state=rules.snapshot()
    _check(heated.ok and not Ledger._local_cooling_history(original,state) and Proof.validate(proof).ok and Ledger._local_cooling_history(Proof.validate(proof).envelope,Proof.validate(proof).envelope.rules),"original legal reheat invalidates CURRENT A while the sealed actual earlier A remains intact; no hot physical endpoint invented")
    store_path="user://profiles_v3/"+profile
    var store=Store.new(store_path)
    if not _check(store.load_profile().ok,"fresh isolated original Store opens; no alternate repository"): _finish(); return
    var transaction: Dictionary={"id":"qa-preparation-seal-once","set":{"world.environment.I2_canal":original,"world.environment.I2_canal_preparation":proof}}
    var published: Dictionary=store.commit(transaction)
    if not _check(published.ok,"original Store accepts the complete proof plus original current physical checkpoint tree",{"commit":published,"proof_tree_valid":store._tree_valid(proof),"transaction_set_tree_valid":store._tree_valid(transaction.set),"joined_json_chars":Proof.join(proof.envelope).length(),"chunk_count":proof.envelope.size()}): _finish(); return
    var committed: Dictionary=store.snapshot()
    var reader=Store.new(store_path)
    if not _check(reader.load_profile().ok,"independent original Store reader opens the exact committed generation"): _finish(); return
    var disk: Dictionary=reader.snapshot()
    var persisted: Dictionary=disk.world.environment.I2_canal_preparation
    var restored: Dictionary=Proof.validate(persisted)
    if not _check(restored.get("ok",false) and persisted.sha256==proof.sha256 and store.matches_persisted_value(original,restored.get("envelope")) and Ledger._local_cooling_history(restored.envelope,restored.envelope.rules),"actual Store JSON publication/readback retains valid exact original proof and original-history eligibility",{"validation":restored.get("code"),"sha256":persisted.sha256}): _finish(); return
    _check(persisted.envelope==proof.envelope and Proof.join(persisted.envelope).sha256_text()==proof.sha256,"Store escapes and reads ordered original STRING chunks without reparsing checkpoint numbers")
    var roundtrip: Dictionary=persisted.duplicate(true)
    for unused in 5: roundtrip=JSON.parse_string(JSON.stringify(roundtrip,"",true,true))
    _check(roundtrip.envelope==proof.envelope and roundtrip.sha256==proof.sha256 and Proof.validate(roundtrip).ok,"five additional ordinary JSON read/write boundaries retain identical sealed bytes and original schema")
    _check(disk.personal.discoveries.is_empty() and disk.world.completed_objectives.is_empty() and disk.world.environment.I2_canal.rules.service_credit==0 and disk.world.environment.I2_canal.rules.services_consumed==0,"sealing and persistence alone create no Story objective, discovery, service credit or claim")
    var replay: Dictionary=reader.commit(transaction)
    _check(replay.ok and replay.duplicate and reader.snapshot()==disk,"replaying the identical original Store transaction preserves generation and all state")
    var conflicting: Dictionary=transaction.duplicate(true)
    conflicting.set["world.environment.I2_canal_preparation"].sha256="f".repeat(64)
    var rejected: Dictionary=reader.commit(conflicting)
    _check(not rejected.ok and reader.snapshot()==disk,"changed payload with the same original transaction ID cannot replace the first sealed proof")
    var recaptured: Dictionary=Proof.capture(restored.envelope)
    _check(recaptured.get("ok",false) and Proof.validate(persisted).ok and reader.snapshot()==disk,"pure revalidation/recapture cannot reapply a thermal command, claim, reward or Store write")
    _finish()

func _check(ok: bool,label: String,detail: Variant=null) -> bool:
    checks.append({"passed":ok,"label":label,"detail":detail})
    return ok

func _finish() -> void:
    if finished: return
    finished=true
    var failures: Array=checks.filter(func(row: Dictionary): return not row.passed)
    var report: Dictionary={"checks":checks,"failures":failures,"engine_errors":logger.errors,"source":SOURCE,"source_sha256":SHA,"selector":SELECTOR,"proof_sha256":proof.get("sha256",""),"proof_envelope_type":typeof(proof.get("envelope")),"store_path":store_path,"scope":"Pure original checkpoint seal/integrity plus actual original Store tree/publication/readback/replay. Cold A source is the exact successful Session Store snapshot from a pinned physical run whose current350ms support/capture/Store checks passed; its final unrelated legacy fixture-discovery assertion failed and is not claimed green. Original Ledger._local_cooling_history is reused, never reimplemented. A subsequent original Rules thermal command is an explicitly RULE-ONLY negative example, not a fabricated hot physical checkpoint. Helper does not judge live preparation, grant current-space contact credit, import history into physics, claim services, complete Story, heal, or own another Store. Root must gate and atomically write the seal once with the original Story transaction and separately validate current physical state. No MAIN/physics/graphics/LAN/full-profile progression evidence."}
    if not output.is_empty(): FileAccess.open(output+"/result.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
    print("CANAL_PREPARATION_PROOF_RESULT ",JSON.stringify({"checks":checks.size(),"failures":failures,"engine_errors":logger.errors,"source":SOURCE,"source_sha256":SHA,"selector":SELECTOR,"proof_sha256":proof.get("sha256",""),"store_path":store_path}))
    quit(0 if failures.is_empty() and logger.errors.is_empty() else 1)
