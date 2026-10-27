class_name TwinReceiptChannel
extends RefCounted
## Durable personal rewards travel separately from high-frequency motion snapshots.
## The transport must deliver receipt_batch reliably and authenticate RPC senders.

const MAX_BATCH := 8
const RETRY_SECONDS := 2.0
var session
var _clock := 0.0
var _last_sent: Dictionary = {}
var _sent_for: Dictionary = {}
var _in_flight: Dictionary = {}

func setup(owner_session) -> void:
	session = owner_session
	reset()

func reset() -> void:
	_clock = 0.0
	_last_sent.clear()
	_sent_for.clear()
	_in_flight.clear()

func tick(delta: float) -> void:
	if not is_finite(delta) or delta < 0.0: return
	_clock += delta
	if not _host_ready(): return
	for peer_id in _sent_for.keys():
		if not session.network.guests.has(peer_id): _forget_peer(peer_id)
	for peer_id in session.network.guests.keys(): send_pending(int(peer_id))

func send_pending(peer_id: int) -> Dictionary:
	if not _host_ready(): return _result(false, "host_required")
	var identity := _identity(peer_id)
	if identity.is_empty(): return _result(false, "unknown_peer")
	var recipient_key: String = str(session.network.session_id) + ":" + identity
	if _sent_for.get(peer_id, "") != recipient_key:
		_forget_peer(peer_id)
		_sent_for[peer_id] = recipient_key
	if _last_sent.has(peer_id) and _clock - float(_last_sent[peer_id]) < RETRY_SECONDS:
		return _result(true, "throttled")
	var pending: Array = session.store.pending_guest_receipts(identity)
	var batch: Array = []
	var ids: Dictionary = {}
	for receipt in pending:
		if not receipt is Dictionary or not _id(receipt.get("receipt_id")) or receipt.get("guest_id") != identity:
			return _result(false, "invalid_outbox_receipt")
		if ids.has(receipt.receipt_id): continue
		ids[receipt.receipt_id] = true
		batch.append(receipt.duplicate(true))
		if batch.size() == MAX_BATCH: break
	if batch.is_empty():
		_in_flight.erase(peer_id)
		return _result(true, "empty")
	# Set throttle/in-flight first: a local test adapter may deliver synchronously.
	_last_sent[peer_id] = _clock
	_in_flight[peer_id] = ids
	session.network.send_event(peer_id, {"kind":"receipt_batch", "session_id":str(session.network.session_id), "receipts":batch})
	return _result(true, "sent", batch.size())

func receive(event: Dictionary) -> Dictionary:
	if not is_instance_valid(session) or not session.active or session.network.mode != "guest": return _result(false, "guest_required")
	var accepted_session: String = str(session.received_session)
	if event.get("kind") != "receipt_batch" or accepted_session.is_empty() or event.get("session_id") != accepted_session:
		return _result(false, "wrong_session")
	var receipts: Variant = event.get("receipts")
	if not receipts is Array or receipts.is_empty() or receipts.size() > MAX_BATCH: return _result(false, "invalid_batch")
	# Validate the envelope before applying any item. The store validates signatures,
	# target identity, payload and persistence; partial disk failures remain pending.
	var seen: Dictionary = {}
	for receipt in receipts:
		if not receipt is Dictionary or not _id(receipt.get("receipt_id")) or seen.has(receipt.receipt_id): return _result(false, "invalid_batch")
		seen[receipt.receipt_id] = true
	var acknowledged: Array = []
	var failed: Array = []
	for receipt in receipts:
		var applied: Dictionary = session.store.apply_guest_receipt(receipt)
		if applied.get("ok", false): acknowledged.append(str(receipt.receipt_id))
		else: failed.append(str(receipt.receipt_id))
	if not acknowledged.is_empty():
		session.network.send_action("receipt_ack_batch", {"session_id":accepted_session, "receipt_ids":acknowledged})
	return {"ok":failed.is_empty(), "code":"applied" if failed.is_empty() else "partial_failure", "count":acknowledged.size(), "failed":failed}

func acknowledge(peer_id: int, payload: Dictionary) -> Dictionary:
	if not _host_ready(): return _result(false, "host_required")
	var identity := _identity(peer_id)
	if identity.is_empty(): return _result(false, "unknown_peer")
	if payload.get("session_id") != session.network.session_id: return _result(false, "wrong_session")
	if _sent_for.get(peer_id, "") != str(session.network.session_id) + ":" + identity: return _result(false, "batch_not_sent")
	var ids: Variant = payload.get("receipt_ids")
	if not ids is Array or ids.is_empty() or ids.size() > MAX_BATCH: return _result(false, "invalid_ack")
	var seen: Dictionary = {}
	for receipt_id in ids:
		if not _id(receipt_id) or seen.has(receipt_id): return _result(false, "invalid_ack")
		seen[receipt_id] = true
	var acknowledged := 0
	var failed: Array = []
	var ignored := 0
	var in_flight: Dictionary = _in_flight.get(peer_id, {})
	for receipt_id in ids:
		# Duplicate/late ACKs and IDs from another guest never reach the store.
		if not in_flight.has(receipt_id):
			ignored += 1
			continue
		var saved: Dictionary = session.store.ack_guest_receipt(identity, receipt_id)
		if saved.get("ok", false):
			in_flight.erase(receipt_id)
			acknowledged += 1
		else: failed.append(receipt_id)
	if acknowledged > 0:
		# ACK writes advance generation, though world_revision does not change.
		session.world_cache = session.store.snapshot()
	return {"ok":failed.is_empty(), "code":"acknowledged" if failed.is_empty() else "partial_failure", "count":acknowledged, "ignored":ignored, "failed":failed}

func _host_ready() -> bool:
	return is_instance_valid(session) and session.active and session.owns_world and session.network.mode == "host" and session.network.is_authority() and not str(session.network.session_id).is_empty()

func _identity(peer_id: int) -> String:
	if peer_id <= 1 or not session.network.guests.has(peer_id) or not session.identities.has(peer_id): return ""
	var registered: String = str(session.network.guests[peer_id])
	return registered if registered == str(session.identities[peer_id]) else ""

func _forget_peer(peer_id: int) -> void:
	_last_sent.erase(peer_id)
	_sent_for.erase(peer_id)
	_in_flight.erase(peer_id)

func _id(value: Variant) -> bool:
	return value is String and not value.is_empty() and value.length() <= 200

func _result(ok: bool, code: String, count: int = 0) -> Dictionary:
	return {"ok":ok, "code":code, "count":count}
