class_name TwinConsensus
extends RefCounted
## Transport-free host authority. Ready proposals still require a successful store commit.

const KINDS = ["major_choice", "region_change", "pause", "facility_choice", "campaign_choice"]
var _participants: Array[String] = []
var _world_revision = 0
var _proposal: Dictionary = {}
var _sequence = 0

func configure(participant_ids: Array, world_revision: int) -> Dictionary:
	if world_revision < 0 or participant_ids.size() < 1 or participant_ids.size() > 2: return _error("CONSENSUS_INVALID_PARTICIPANTS")
	var ids: Array[String] = []
	for value in participant_ids:
		if not (value is int or value is String): return _error("CONSENSUS_INVALID_PARTICIPANTS")
		var id = str(value)
		if id.is_empty() or ids.has(id): return _error("CONSENSUS_INVALID_PARTICIPANTS")
		ids.append(id)
	_participants = ids
	_world_revision = world_revision
	_proposal = {}
	return {"ok":true}

func propose(kind: String, payload: Dictionary, proposer_id: Variant) -> Dictionary:
	var id = str(proposer_id)
	if kind not in KINDS: return _error("CONSENSUS_INVALID_KIND")
	if id not in _participants: return _error("CONSENSUS_NOT_PARTICIPANT")
	if not _proposal.is_empty(): return _error("CONSENSUS_PENDING")
	if not _json_safe(payload): return _error("CONSENSUS_INVALID_PAYLOAD")
	_sequence += 1
	_proposal = {"proposal_id":"proposal:%d:%d" % [Time.get_ticks_usec(), _sequence], "kind":kind,
		"payload":payload.duplicate(true), "world_revision":_world_revision, "participants":_participants.duplicate(),
		"confirmed":[id], "state":"pending"}
	_update_ready()
	return _result()

func confirm(proposal_id: String, participant_id: Variant, world_revision: int) -> Dictionary:
	if _proposal.is_empty() or _proposal.proposal_id != proposal_id: return _error("CONSENSUS_NOT_FOUND")
	var id = str(participant_id)
	if id not in _participants or id not in _proposal.participants: return _error("CONSENSUS_NOT_PARTICIPANT")
	if world_revision != _world_revision or int(_proposal.world_revision) != _world_revision:
		_proposal = {}
		return _error("CONSENSUS_STALE_WORLD")
	var duplicate: bool = _proposal.confirmed.has(id)
	if not duplicate: _proposal.confirmed.append(id)
	_update_ready()
	var result = _result()
	result["duplicate"] = duplicate
	return result

func _update_ready() -> void:
	if _proposal.confirmed.size() == _proposal.participants.size(): _proposal.state = "ready"

func current_proposal() -> Dictionary:
	return _proposal.duplicate(true)

func set_world_revision(revision: int) -> void:
	if revision < _world_revision: return
	if revision != _world_revision: _proposal = {}
	_world_revision = revision

func participant_disconnected(participant_id: Variant) -> Dictionary:
	var id = str(participant_id)
	if id not in _participants: return _error("CONSENSUS_NOT_PARTICIPANT")
	var cancelled = not _proposal.is_empty()
	_proposal = {}
	_participants.erase(id)
	return {"ok":true, "cancelled":cancelled}

## Call after durable commit (true), or explicit user cancellation (false).
## A failed save should leave the ready proposal intact for an explicit retry.
func resolve(proposal_id: String, committed: bool) -> Dictionary:
	if _proposal.is_empty() or _proposal.proposal_id != proposal_id: return _error("CONSENSUS_NOT_FOUND")
	if committed and _proposal.state != "ready": return _error("CONSENSUS_NOT_READY")
	_proposal = {}
	return {"ok":true, "committed":committed}

func _result() -> Dictionary:
	return {"ok":true, "proposal_id":str(_proposal.proposal_id), "ready":_proposal.state == "ready", "proposal":current_proposal()}

func _error(error: String) -> Dictionary:
	return {"ok":false, "error":error, "ready":false}

func _json_safe(value: Variant, depth: int = 0) -> bool:
	if depth > 12: return false
	if value == null or value is bool: return true
	if value is String: return value.length() <= 4096
	if value is int or value is float: return is_finite(float(value)) and absf(float(value)) <= 9007199254740991
	if value is Array:
		if value.size() > 256: return false
		for item in value:
			if not _json_safe(item, depth + 1): return false
		return true
	if value is Dictionary:
		if value.size() > 256: return false
		for key in value:
			if not key is String or not _json_safe(value[key], depth + 1): return false
		return true
	return false
