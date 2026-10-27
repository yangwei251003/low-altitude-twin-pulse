extends SceneTree
## Pure transport/state adapters only: no ENet, main scene or real save writes.
const Channel = preload("res://scripts/v3/network/twin_receipt_channel.gd")
var checks := 0
var failures: Array[String] = []

class FakeTransport extends RefCounted:
	var mode := "host"
	var session_id := "qa-connection-A"
	var guests: Dictionary = {2:"guest-A"}
	var sent_events: Array = []
	var sent_actions: Array = []
	func is_authority() -> bool: return mode in ["host", "solo"]
	func send_event(peer_id: int, event: Dictionary) -> void: sent_events.append({"peer_id":peer_id,"event":event.duplicate(true)})
	func send_action(verb: String, payload: Dictionary) -> void: sent_actions.append({"verb":verb,"payload":payload.duplicate(true)})

class FakeStore extends RefCounted:
	var identity := "guest-A"
	var outbox: Dictionary = {}
	var received: Dictionary = {}
	var discoveries: Array = []
	var fail_apply := false
	var fail_ack := false
	var fail_apply_ids: Dictionary = {}
	var generation := 0
	var apply_calls := 0
	var apply_writes := 0
	var ack_calls := 0
	func add_rewards(count: int, target := "guest-A", prefix := "reward") -> void:
		for index in count:
			var reward_id := prefix + ":" + str(index)
			var id := JSON.stringify(["lineage",target,reward_id]).sha256_text()
			outbox[id] = {"receipt":{"receipt_id":id,"lineage_id":"lineage","guest_id":target,"reward_id":reward_id,"payload":{"discoveries":[reward_id]}},"acknowledged":false}
	func pending_guest_receipts(target: String) -> Array:
		var pending: Array = []
		for item in outbox.values():
			if not item.acknowledged and item.receipt.guest_id == target: pending.append(item.receipt.duplicate(true))
		return pending
	func apply_guest_receipt(receipt: Dictionary) -> Dictionary:
		apply_calls += 1
		if receipt.get("guest_id") != identity: return {"ok":false}
		if received.has(receipt.receipt_id): return {"ok":received[receipt.receipt_id] == receipt,"duplicate":true}
		if fail_apply or fail_apply_ids.has(receipt.receipt_id): return {"ok":false}
		received[receipt.receipt_id] = receipt.duplicate(true)
		for discovery in receipt.payload.discoveries:
			if not discovery in discoveries: discoveries.append(discovery)
		apply_writes += 1
		generation += 1
		return {"ok":true}
	func ack_guest_receipt(target: String, id: String) -> Dictionary:
		ack_calls += 1
		if fail_ack or not outbox.has(id) or outbox[id].receipt.guest_id != target: return {"ok":false}
		if not outbox[id].acknowledged:
			outbox[id].acknowledged = true
			generation += 1
		return {"ok":true}
	func snapshot() -> Dictionary:
		return {"generation":generation,"world_revision":0,"world":{"region_id":"I1","branch_id":"main"}}

class FakeSession extends RefCounted:
	var active := true
	var owns_world := true
	var simulation_paused := false
	var received_session := "qa-connection-A"
	var identities: Dictionary = {2:"guest-A"}
	var world_cache: Dictionary = {}
	var network = FakeTransport.new()
	var store = FakeStore.new()

func _initialize() -> void:
	_test_batch_limits_and_late_ack()
	_test_guest_disk_failure_and_partial_success()
	_test_host_disk_failure_and_duplicate_ack()
	_test_session_and_identity_guards()
	_test_reset_pause_and_peer_reuse()
	print("V3_RECEIPT_CHANNEL_TESTS " + JSON.stringify({"checks":checks,"failures":failures,"scope":"pure fake session/store/transport; no ENet and no real profile writes"}))
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)

func _pair(rewards: int) -> Dictionary:
	var host = FakeSession.new()
	host.store.add_rewards(rewards)
	var guest = FakeSession.new()
	guest.owns_world = false
	guest.network.mode = "guest"
	guest.network.guests = {}
	var sender = Channel.new()
	sender.setup(host)
	var receiver = Channel.new()
	receiver.setup(guest)
	return {"host":host,"guest":guest,"sender":sender,"receiver":receiver}

func _last_event(pair: Dictionary) -> Dictionary:
	return pair.host.network.sent_events.back().event.duplicate(true)

func _last_ack(pair: Dictionary) -> Dictionary:
	return pair.guest.network.sent_actions.back().payload.duplicate(true)

func _test_batch_limits_and_late_ack() -> void:
	var pair = _pair(19)
	var initial = pair.sender.send_pending(2)
	_check(initial.ok and initial.count == 8, "first connection batch immediately sends at most eight")
	var first = _last_event(pair)
	_check(first.kind == "receipt_batch" and first.session_id == "qa-connection-A" and first.receipts.size() == 8, "reliable event envelope is independent of motion data")
	_check(not first.has("players") and not first.has("entities"), "receipt event contains no motion snapshot")
	for index in 39: pair.sender.tick(0.05)
	_check(pair.host.network.sent_events.size() == 1, "39 motion-frame intervals cannot resend within two seconds")
	_check(pair.sender.send_pending(2).code == "throttled", "explicit send_pending cannot bypass throttle")
	pair.sender.tick(0.051)
	_check(pair.host.network.sent_events.size() == 2 and _last_event(pair).receipts == first.receipts, "delayed ACK causes only one resend after two seconds")
	_check(pair.host.store.pending_guest_receipts("guest-A").size() == 19, "sending never marks an unacknowledged receipt delivered")
	var accepted = pair.receiver.receive(first)
	_check(accepted.ok and accepted.count == 8 and pair.guest.store.discoveries.size() == 8, "guest durably applies first eight")
	_check(pair.guest.network.sent_actions.size() == 1 and pair.guest.network.sent_actions[0].verb == "receipt_ack_batch", "one ACK command per successful batch")
	_check(_last_ack(pair).session_id == "qa-connection-A" and _last_ack(pair).receipt_ids.size() == 8, "ACK carries connection and successful IDs")
	_check(pair.sender.acknowledge(2, _last_ack(pair)).count == 8, "host acknowledges its registered recipient batch")
	_check(pair.host.world_cache.generation == pair.host.store.generation, "ACK generation refreshes host cache")
	_check(pair.host.world_cache.world_revision == 0, "ACK never advances world-story revision")
	pair.sender.tick(1.0)
	_check(pair.host.network.sent_events.size() == 2, "new rewards do not burst immediately after ACK")
	pair.sender.tick(1.01)
	_check(_last_event(pair).receipts.size() == 8, "second distinct batch is also bounded")
	_check(pair.receiver.receive(_last_event(pair)).count == 8, "second batch applied")
	_check(pair.sender.acknowledge(2, _last_ack(pair)).count == 8, "second batch acknowledged")
	pair.sender.tick(2.0)
	_check(_last_event(pair).receipts.size() == 3, "final partial batch contains exactly remaining rewards")
	_check(pair.receiver.receive(_last_event(pair)).count == 3, "partial final batch applied")
	_check(pair.sender.acknowledge(2, _last_ack(pair)).count == 3, "partial final batch acknowledged")
	_check(pair.guest.store.discoveries.size() == 19 and pair.guest.store.apply_writes == 19, "all nineteen rewards received exactly once")
	_check(pair.host.store.pending_guest_receipts("guest-A").is_empty(), "no pending rewards remain after ACK")
	var sent = pair.host.network.sent_events.size()
	pair.sender.tick(20.0)
	_check(pair.host.network.sent_events.size() == sent, "empty outbox produces no reliable heartbeat")

func _test_guest_disk_failure_and_partial_success() -> void:
	var pair = _pair(10)
	pair.sender.send_pending(2)
	var batch = _last_event(pair)
	pair.guest.store.fail_apply = true
	var failed = pair.receiver.receive(batch)
	_check(not failed.ok and failed.count == 0 and failed.failed.size() == 8, "guest disk failure reports failed items")
	_check(pair.guest.store.discoveries.is_empty() and pair.guest.network.sent_actions.is_empty(), "guest cannot ACK failed durable writes")
	pair.guest.store.fail_apply = false
	var failed_id: String = batch.receipts[3].receipt_id
	pair.guest.store.fail_apply_ids[failed_id] = true
	pair.sender.tick(2.0)
	var partial = pair.receiver.receive(_last_event(pair))
	_check(not partial.ok and partial.count == 7, "partial disk failure allows seven independent successes")
	_check(not failed_id in _last_ack(pair).receipt_ids and _last_ack(pair).receipt_ids.size() == 7, "only persisted IDs appear in batch ACK")
	_check(pair.sender.acknowledge(2, _last_ack(pair)).count == 7, "host removes only persisted rewards")
	_check(pair.host.store.pending_guest_receipts("guest-A").size() == 3, "failed item and unseen tail remain pending")
	var prior_writes = pair.guest.store.apply_writes
	var replay = pair.receiver.receive(batch)
	_check(replay.count == 7 and pair.guest.store.apply_writes == prior_writes, "duplicate batch cannot duplicate successful discoveries")
	_check(pair.sender.acknowledge(2, _last_ack(pair)).count == 0, "duplicate ACK cannot create additional host writes")
	pair.guest.store.fail_apply_ids.clear()
	pair.sender.tick(2.0)
	_check(_last_event(pair).receipts.size() == 3, "recovery retries failed item with remaining tail")
	_check(pair.receiver.receive(_last_event(pair)).count == 3, "guest recovers without reconnect")
	_check(pair.sender.acknowledge(2, _last_ack(pair)).count == 3, "recovered batch acknowledged")
	_check(pair.guest.store.discoveries.size() == 10 and pair.guest.store.apply_writes == 10 and pair.host.store.pending_guest_receipts("guest-A").is_empty(), "all rewards delivered once despite partial disk failure")

func _test_host_disk_failure_and_duplicate_ack() -> void:
	var pair = _pair(8)
	pair.sender.send_pending(2)
	pair.receiver.receive(_last_event(pair))
	pair.host.store.fail_ack = true
	var before = pair.host.world_cache.duplicate(true)
	var ack = _last_ack(pair)
	var failed = pair.sender.acknowledge(2, ack)
	_check(not failed.ok and failed.count == 0 and failed.failed.size() == 8, "host failed ACK persistence leaves batch in flight")
	_check(pair.host.store.pending_guest_receipts("guest-A").size() == 8 and pair.host.world_cache == before, "host ACK failure leaves outbox and cache unchanged")
	pair.sender.tick(2.0)
	_check(pair.receiver.receive(_last_event(pair)).count == 8 and pair.guest.store.apply_writes == 8, "host retry is duplicate-safe on guest")
	pair.host.store.fail_ack = false
	_check(pair.sender.acknowledge(2, _last_ack(pair)).count == 8, "host ACK persistence can recover without reconnect")
	var calls = pair.host.store.ack_calls
	_check(pair.sender.acknowledge(2, ack).count == 0 and pair.host.store.ack_calls == calls, "late duplicate ACK does not hit disk")

func _test_session_and_identity_guards() -> void:
	var pair = _pair(8)
	pair.sender.send_pending(2)
	var batch = _last_event(pair)
	var wrong = batch.duplicate(true)
	wrong.session_id = "previous-connection"
	_check(not pair.receiver.receive(wrong).ok and pair.guest.store.apply_calls == 0, "foreign session rejected before persistence")
	pair.guest.received_session = ""
	_check(not pair.receiver.receive(batch).ok and pair.guest.store.apply_calls == 0, "batch before accepted first snapshot is rejected")
	pair.guest.received_session = "qa-connection-A"
	var malformed = batch.duplicate(true)
	malformed.receipts.append(batch.receipts[0])
	_check(not pair.receiver.receive(malformed).ok and pair.guest.store.apply_calls == 0, "oversized batch rejected atomically")
	malformed = batch.duplicate(true)
	malformed.receipts[2] = batch.receipts[0]
	_check(not pair.receiver.receive(malformed).ok and pair.guest.store.apply_calls == 0, "duplicate IDs in one envelope rejected before applying any")
	malformed = batch.duplicate(true)
	malformed.receipts[7] = null
	_check(not pair.receiver.receive(malformed).ok and pair.guest.store.apply_calls == 0, "malformed final item cannot cause partial envelope application")
	_check(pair.receiver.receive(batch).count == 8, "same valid batch works after guards")
	var ack = _last_ack(pair)
	var bad_ack = ack.duplicate(true)
	bad_ack.session_id = "previous-connection"
	_check(not pair.sender.acknowledge(2, bad_ack).ok and pair.host.store.ack_calls == 0, "foreign-session ACK rejected")
	_check(not pair.sender.acknowledge(9, ack).ok and pair.host.store.ack_calls == 0, "unregistered peer cannot ACK another guest")
	pair.host.network.guests[3] = "guest-B"
	pair.host.identities[3] = "guest-B"
	pair.host.store.add_rewards(1, "guest-B")
	pair.sender.send_pending(3)
	_check(pair.sender.acknowledge(3, ack).count == 0 and pair.host.store.ack_calls == 0, "registered second identity cannot acknowledge first identity receipts")
	bad_ack = ack.duplicate(true)
	bad_ack.receipt_ids.append("extra")
	_check(not pair.sender.acknowledge(2, bad_ack).ok, "oversized ACK rejected")
	bad_ack = ack.duplicate(true)
	bad_ack.receipt_ids[1] = bad_ack.receipt_ids[0]
	_check(not pair.sender.acknowledge(2, bad_ack).ok, "duplicate ACK entries rejected before writes")
	pair.host.identities[2] = "spoofed-identity"
	_check(not pair.sender.send_pending(2).ok and not pair.sender.acknowledge(2, ack).ok, "registration/session identity mismatch rejected")
	pair.host.identities[2] = "guest-A"
	_check(pair.sender.acknowledge(2, ack).count == 8, "legitimate identity retains valid in-flight receipt batch")
	_check(pair.host.store.pending_guest_receipts("guest-B").size() == 1, "other identity outbox remains intact")

func _test_reset_pause_and_peer_reuse() -> void:
	var pair = _pair(3)
	pair.host.simulation_paused = true
	pair.sender.tick(0.01)
	_check(pair.host.network.sent_events.size() == 1, "paused game can still deliver rewards when independent tick runs")
	pair.sender.tick(NAN)
	pair.sender.tick(-10.0)
	pair.sender.tick(INF)
	_check(pair.host.network.sent_events.size() == 1, "invalid delta cannot force resend")
	var old = _last_event(pair)
	pair.sender.reset()
	pair.host.network.session_id = "qa-connection-B"
	pair.guest.received_session = "qa-connection-B"
	_check(pair.sender.send_pending(2).count == 3, "new connection reset immediately resends unacknowledged rewards")
	_check(not pair.receiver.receive(old).ok, "old-connection reliable payload cannot enter new session")
	pair.receiver.reset()
	_check(pair.receiver.receive(_last_event(pair)).count == 3, "new connection rewards accepted after reset")
	_check(pair.sender.acknowledge(2, _last_ack(pair)).count == 3, "new connection ACK binds current session")
	pair.host.active = false
	pair.host.store.add_rewards(1, "guest-A", "later")
	pair.sender.tick(10.0)
	_check(not pair.sender.send_pending(2).ok, "inactive host cannot deliver")
	pair.host.active = true
	pair.host.network.guests.erase(2)
	pair.sender.tick(0.1)
	pair.host.network.guests[2] = "guest-C"
	pair.host.identities[2] = "guest-C"
	pair.host.store.add_rewards(2, "guest-C")
	_check(pair.sender.send_pending(2).count == 2, "reused peer ID receives only new registered identity rewards")
	for receipt in _last_event(pair).receipts: _check(receipt.guest_id == "guest-C", "peer reuse does not leak prior identity payload")
	pair.host.network.mode = "solo"
	_check(not pair.sender.send_pending(2).ok, "solo mode cannot send network receipts")
	pair.guest.active = false
	_check(not pair.receiver.receive(_last_event(pair)).ok, "inactive guest cannot apply receipt payload")
