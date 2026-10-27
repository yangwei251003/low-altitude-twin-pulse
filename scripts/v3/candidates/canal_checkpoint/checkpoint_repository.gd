extends RefCounted
## Candidate profile only. Reuses the production Store's generation/hash/rename
## transaction and receipt ledger; never touches MAIN/default/V2 profiles.
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const PlayerCheckpoint = preload("res://scripts/v3/candidates/canal_checkpoint/player_checkpoint.gd")
const DEFAULT_PATH := "user://profiles_v3/canal_candidate"
const STATE_PATH := "world.environment.canal_candidate_checkpoint"
var _path: String
var _store: RefCounted

func _init(path: String = DEFAULT_PATH) -> void:
    _path = path.trim_suffix("/")
    if _path_allowed(_path): _store = Store.new(_path)

func read() -> Dictionary:
    if _store == null: return _bad("candidate_profile_path_required")
    var loaded: Dictionary = _store.load_profile()
    if not loaded.ok: return _bad("store:"+str(loaded.error))
    var state: Dictionary = _store.snapshot()
    var environment: Variant = state.world.get("environment",{})
    if not environment is Dictionary: return _bad("environment_type")
    if not environment.has("canal_candidate_checkpoint"):
        return {"ok":true,"code":"empty_candidate_profile","empty":true,"envelope":{},"generation":int(state.generation),"recovered":loaded.recovered}
    var raw: Variant = environment.canal_candidate_checkpoint
    var valid: Dictionary = PlayerCheckpoint.validate(raw)
    if not valid.ok: return _bad("checkpoint:"+str(valid.code))
    return {"ok":true,"code":"read_valid_checkpoint","empty":false,"envelope":raw.duplicate(true),"generation":int(state.generation),"recovered":loaded.recovered}

func save(envelope: Dictionary, transaction_id: String, expected_generation: int) -> Dictionary:
    var valid: Dictionary = PlayerCheckpoint.validate(envelope)
    if not valid.ok: return _bad("checkpoint:"+str(valid.code))
    if transaction_id.is_empty() or transaction_id.length()>160 or expected_generation<0 or expected_generation>Store.MAX_INTEGER: return _bad("transaction_contract")
    # Read back the current generation before attempting any mutation. Invalid
    # application schema fails closed rather than silently replacing that save.
    var current: Dictionary = read()
    if not current.ok: return current
    var id: String = "canal-checkpoint:"+transaction_id
    var state: Dictionary = _store.snapshot()
    var committed_before: bool = state.ledger.commits.has(id)
    if int(current.generation)!=expected_generation and not committed_before: return _bad("generation_changed")
    # An identical retry is delegated to Store.commit; conflicting reuse of the
    # same ID is rejected by its existing canonical transaction fingerprint.
    var committed: Dictionary = _store.commit({"id":id,"set":{STATE_PATH:envelope.duplicate(true),"world.region_id":"I2"}})
    if not committed.ok: return _bad("store:"+str(committed.error))
    var result: Dictionary = read()
    if not result.ok or result.empty: return _bad("committed_readback_invalid")
    # Duplicate receipts do not roll back a later valid generation. A new commit
    # must read back the exact value produced by the Store's JSON boundary.
    if not committed.duplicate and not _store.matches_persisted_value(envelope,result.envelope): return _bad("committed_readback_mismatch")
    result.code = "saved_checkpoint" if not committed.duplicate else "duplicate_transaction"
    result.duplicate = committed.duplicate
    return result

static func _path_allowed(path: String) -> bool:
    if path == DEFAULT_PATH: return true
    if not path.begins_with("user://qa_v3/") or path.contains("..") or path.contains("\\"): return false
    var relative: String = path.trim_prefix("user://qa_v3/")
    if relative.is_empty() or relative.length()>180: return false
    for part: String in relative.split("/",true):
        if part.is_empty(): return false
        for code: int in part.to_ascii_buffer():
            if not (code>=48 and code<=57) and not (code>=65 and code<=90) and not (code>=97 and code<=122) and code not in [45,95]: return false
    return true

static func _bad(code: String) -> Dictionary:
    return {"ok":false,"code":code}
