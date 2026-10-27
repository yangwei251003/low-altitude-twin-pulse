extends RefCounted
## Immutable-by-value seal of one ORIGINAL versioned Canal checkpoint.
## Root owns actual preparation eligibility, seal-once policy, lineage and the
## SAME Story Store transaction. A SHA is integrity, not authority or credit.
## No Store instance, scene, Rules command, clock, contact or reward is created.
const Wait=preload("res://scripts/v3/gameplay/canal/canal_checkpoint/canal_wait_checkpoint.gd")
const Startup=preload("res://scripts/v3/gameplay/canal/canal_checkpoint/canal_startup_checkpoint.gd")
const Scan=preload("res://scripts/v3/gameplay/canal/canal_checkpoint/canal_scan_checkpoint.gd")
const Progress=preload("res://scripts/v3/gameplay/canal/canal_checkpoint/canal_progress_checkpoint.gd")
const VERSION=1
const KEYS=["version","envelope","sha256"]
const CHUNK_CHARS=4096
const MAX_CHUNKS=64
const MAX_JSON_CHARS=CHUNK_CHARS*MAX_CHUNKS

static func capture(envelope: Variant) -> Dictionary:
    var checked: Dictionary=_checkpoint(envelope)
    if not checked.ok: return checked
    # Seal the WHOLE original checkpoint as sorted, full-precision JSON text.
    # Godot's JSON decode can move some fractional numbers by one ULP; Store
    # must retain this exact text rather than re-decode/re-encode its numbers.
    # Fixed ordered chunks respect the ORIGINAL Store's <=8192 String limit.
    # No field, physical value, thermal rule or contact credit is rewritten.
    var original: String=JSON.stringify(envelope,"",true,true)
    if original.length()>MAX_JSON_CHARS: return _bad("preparation_checkpoint_text_limit")
    var proof: Dictionary={"version":VERSION,"envelope":_chunks(original),"sha256":original.sha256_text()}
    checked=validate(proof)
    if not checked.ok: return checked
    return {"ok":true,"code":"sealed_original_checkpoint_no_new_fact","proof":proof}

static func validate(proof: Variant) -> Dictionary:
    if not Wait.State.exact(proof,KEYS) or not (proof.version is int or proof.version is float) or proof.version!=VERSION or not _digest(proof.sha256): return _bad("preparation_proof_schema")
    var text: String=join(proof.envelope)
    if text.is_empty(): return _bad("preparation_proof_chunks")
    if text.sha256_text()!=proof.sha256: return _bad("preparation_proof_sha256_mismatch")
    var original: Variant=JSON.parse_string(text)
    var checked: Dictionary=_checkpoint(original)
    if not checked.ok: return checked
    return {"ok":true,"code":"valid_original_checkpoint_seal_not_current_physics","envelope":original}

static func join(chunks: Variant) -> String:
    # Empty means invalid framing; an original checkpoint is never empty.
    # Non-tail chunks must be full so equivalent text has one chunk framing.
    if not chunks is Array or chunks.is_empty() or chunks.size()>MAX_CHUNKS: return ""
    var parts:=PackedStringArray()
    for i: int in chunks.size():
        var piece: Variant=chunks[i]
        if not piece is String or piece.is_empty() or piece.length()>CHUNK_CHARS or (i<chunks.size()-1 and piece.length()!=CHUNK_CHARS): return ""
        parts.append(piece)
    var text: String="".join(parts)
    return text if text.length()<=MAX_JSON_CHARS else ""

static func _chunks(text: String) -> Array:
    var chunks: Array=[]
    for start: int in range(0,text.length(),CHUNK_CHARS): chunks.append(text.substr(start,CHUNK_CHARS))
    return chunks

static func _checkpoint(envelope: Variant) -> Dictionary:
    if not envelope is Dictionary or not envelope.get("kind") is String: return _bad("preparation_original_checkpoint_required")
    var checked: Dictionary
    match str(envelope.kind):
        Wait.KIND: checked=Wait.validate(envelope)
        Startup.KIND: checked=Startup.validate(envelope)
        Scan.KIND: checked=Scan.validate(envelope)
        Progress.KIND: checked=Progress.validate(envelope)
        _: return _bad("preparation_unknown_checkpoint_kind")
    return {"ok":true} if checked.get("ok",false) else _bad("preparation_original_schema:"+str(checked.get("code","invalid")))

static func _digest(value: Variant) -> bool:
    if not value is String or value.length()!=64: return false
    for character: String in value:
        if character not in "0123456789abcdef": return false
    return true

static func _bad(code: String) -> Dictionary:
    return {"ok":false,"code":code}
