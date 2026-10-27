extends SceneTree

const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const Consensus = preload("res://scripts/v3/core/twin_consensus.gd")
var checks = 0
var failures: Array[String] = []
var base = ""

func _initialize() -> void:
	base = "user://qa_v3_core/" + str(Time.get_unix_time_from_system()).replace(".", "_") + "_" + str(Time.get_ticks_usec())
	_test_transactions()
	_test_failures()
	_test_backups_and_future()
	_test_branches_and_guests()
	_test_consensus()
	print("V3_CORE_TESTS checks=%d failures=%d qa_path=%s" % [checks, failures.size(), ProjectSettings.globalize_path(base)])
	for failure in failures: print("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)

func _new(name: String):
	var store = Store.new(base.path_join(name))
	_check(store.load_profile().ok, name + " load")
	return store

func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file = FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "fixture write " + path)
	if file != null:
		file.store_string(text)
		file.close()

func _latest(store) -> String:
	return store.root_path.path_join("profile_g%012d.json" % int(store.data.generation))

func _test_transactions() -> void:
	var store = _new("transactions")
	_check(store.data.world.region_id == "I1" and store.data.world.branch_id == "main", "initial world")
	_check(not str(store.data.lineage_id).is_empty(), "stable lineage created")
	var id: String = store.data.lineage_id
	var tx = {"id":"main:repair:bridge", "set":{"world.entities.bridge":{"repaired":true}}, "append":{"world.completed_objectives":["I1-bridge"], "personal.discoveries":["bridge", "bridge"]}}
	_check(store.commit(tx).ok, "atomic world and personal commit")
	_check(store.data.world.entities.bridge.repaired and store.data.personal.discoveries == ["bridge"], "applied and append deduplicated")
	_check(store.data.world_revision == 1, "world revision advanced")
	var generation: int = store.data.generation
	_check(store.commit(tx).duplicate and store.data.generation == generation, "duplicate transaction no new generation")
	_check(not store.commit({"id":"main:repair:bridge", "set":{"world.entities.bridge":false}}).ok, "same receipt changed payload rejected")
	var copy: Dictionary = store.data
	copy.world.region_id = "HACK"
	_check(store.data.world.region_id == "I1", "data getter does not expose mutable authority")
	for path in ["schema_version", "ledger.commits", "world", "world.branch_id", "world..region_id", ".world.region_id"]:
		_check(not store.commit({"id":"invalid:" + path, "set":{path:0}}).ok, "protected path " + path)
	_check(not store.commit({"id":"bad-number", "set":{"world.flags.nan":NAN}}).ok, "nonfinite rejected")
	_check(not store.commit({"id":"bad-append", "append":{"world.flags":[]}}).ok, "append to dictionary rejected")
	_check(store.commit({"id":"personal:only", "append":{"personal.collections":["relic"]}}).ok, "personal commit")
	_check(store.data.world_revision == 1, "personal commit does not invalidate world proposal")
	var reloaded = Store.new(store.root_path)
	_check(reloaded.load_profile().ok and reloaded.data.lineage_id == id, "lineage stable after reload")
	_check(reloaded.snapshot() == store.snapshot(), "exact saved aggregate reload")
	_check(store.commit({"id":"writer:one", "set":{"world.flags.one":true}}).ok, "first writer commit")
	var stale: Dictionary = reloaded.snapshot()
	_check(reloaded.commit({"id":"writer:two", "set":{"world.flags.two":true}}).error == "SAVE_CONCURRENT_WRITE", "stale second writer rejected")
	_check(reloaded.snapshot() == stale, "stale writer memory unchanged")
	var forbidden = Store.new("user://profiles/default")
	_check(forbidden.load_profile().error == "SAVE_PATH_OUTSIDE_V3", "old storage root forbidden")

func _test_failures() -> void:
	var store = _new("failures")
	_check(store.commit({"id":"initial", "set":{"world.flags.saved":true}}).ok, "failure baseline")
	for point in ["before_write", "after_write", "before_publish"]:
		var before: Dictionary = store.snapshot()
		store.failure_point = point
		var tx = {"id":"failure:" + point, "set":{"world.flags.failed":point}, "append":{"personal.collections":[point]}}
		_check(not store.commit(tx).ok, "injected " + point)
		_check(store.snapshot() == before, "memory unchanged " + point)
		var disk = Store.new(store.root_path)
		_check(disk.load_profile().ok and disk.snapshot() == before, "disk unchanged / temp ignored " + point)
		store.failure_point = ""
		_check(store.commit(tx).ok, "retry succeeds " + point)
		_check(store.commit(tx).duplicate, "retry receipt persisted " + point)
	var before: Dictionary = store.snapshot()
	store.failure_point = "before_publish"
	_check(not store.fork_branch("failed-fork").ok and store.snapshot() == before, "failed branch not exposed")
	store.failure_point = ""
	var blocked_path = base.path_join("blocked-directory")
	_write(blocked_path, "This file is deliberately not a directory.")
	var blocked = Store.new(blocked_path)
	_check(blocked.load_profile().ok, "file directory initial load")
	var blocked_before: Dictionary = blocked.snapshot()
	_check(not blocked.commit({"id":"io-failure", "set":{"world.flags.bad":true}}).ok, "actual filesystem directory failure")
	_check(blocked.snapshot() == blocked_before, "actual I/O failure memory unchanged")

func _test_backups_and_future() -> void:
	var store = _new("backup")
	_check(store.commit({"id":"first", "set":{"world.flags.step":1}}).ok, "backup first")
	_check(store.commit({"id":"second", "set":{"world.flags.step":2}}).ok, "backup second")
	var previous: Dictionary = store.snapshot()
	_check(store.commit({"id":"third", "set":{"world.flags.step":3}}).ok, "backup third")
	_write(_latest(store), "{broken")
	var recovery = Store.new(store.root_path)
	var result: Dictionary = recovery.load_profile()
	_check(result.ok and result.recovered, "corruption recovers backup")
	_check(recovery.snapshot() == previous, "backup exact previous state")
	_check(recovery.commit({"id":"after-recovery", "set":{"world.flags.recovered":true}}).ok, "commit after corrupt generation skips its number")
	_check(recovery.data.generation == 4, "corrupt generation never overwritten")
	var future = _new("future")
	_check(future.commit({"id":"initial", "set":{"world.flags.preserved":true}}).ok, "future baseline")
	var before: Dictionary = future.snapshot()
	var future_path = future.root_path.path_join("profile_g000000000002.json")
	_write(future_path, JSON.stringify({"schema_version":4, "format":99}))
	var original_hash = FileAccess.get_sha256(future_path)
	_check(not future.commit({"id":"future-overwrite", "set":{"world.flags.bad":true}}).ok and future.read_only, "future introduced after load blocks write")
	_check(future.snapshot() == before and FileAccess.get_sha256(future_path) == original_hash, "future untouched")
	var future_reload = Store.new(future.root_path)
	_check(future_reload.load_profile().error == "SAVE_SCHEMA_NEWER" and future_reload.read_only, "future prevents fallback to old generation")
	var corrupt = _new("all-corrupt")
	_check(corrupt.commit({"id":"baseline"}).ok, "all-corrupt baseline")
	_write(_latest(corrupt), "broken")
	var corrupt_reload = Store.new(corrupt.root_path)
	_check(corrupt_reload.load_profile().error == "SAVE_NO_VALID_BACKUP", "no valid backup fails closed")
	_check(not corrupt_reload.commit({"id":"cannot-reset"}).ok, "cannot overwrite damaged save with defaults")

func _test_branches_and_guests() -> void:
	var host = _new("host")
	var guest = _new("guest")
	_check(guest.commit({"id":"guest:init"}).ok, "guest identity persisted")
	var guest_id: String = guest.data.profile_id
	var lineage: String = host.data.lineage_id
	_check(host.commit({"id":"main:before", "set":{"world.flags.friend_alive":true, "encounter":{"boss_hp":20}}, "append":{"personal.collections":["old-relic"]}}).ok, "pre-choice world")
	_check(host.fork_branch("before-choice", "Before informed choice").ok, "independent pre-choice branch")
	_check(host.data.world.branch_id == "main" and host.list_branches().size() == 2, "fork does not switch by default")
	_check(host.commit({"id":"main:choice", "set":{"world.flags.friend_alive":false, "world.choices.gate":"close"}, "append":{"personal.collections":["new-relic"]}}).ok, "choice committed")
	_check(host.switch_branch("before-choice").ok, "switch before decision")
	_check(host.data.world.flags.friend_alive and not host.data.world.choices.has("gate"), "branch world restored")
	_check(host.data.personal.collections == ["old-relic", "new-relic"] and host.data.encounter.is_empty(), "personal does not rewind / encounter cleared")
	_check(host.data.lineage_id == lineage, "lineage unchanged by branch")
	_check(host.switch_branch("main").ok and not host.data.world.flags.friend_alive, "main consequence retained")
	var before: Dictionary = host.snapshot()
	host.failure_point = "before_publish"
	_check(not host.switch_branch("before-choice").ok and host.snapshot() == before, "failed switch atomic")
	host.failure_point = ""
	var payload = {"discoveries":["I1-secret"], "collections":["sun-token"], "builds":[{"build_id":"gift-glider", "airframe_id":"tr01"}]}
	var queued: Dictionary = host.queue_guest_receipt(guest_id, "discovery:I1-secret", payload)
	_check(queued.ok and host.pending_guest_receipts(guest_id).size() == 1, "guest durable outbox")
	var receipt: Dictionary = queued.receipt
	guest.failure_point = "before_publish"
	var guest_before: Dictionary = guest.snapshot()
	_check(not guest.apply_guest_receipt(receipt).ok and guest.snapshot() == guest_before, "guest failed grant unchanged")
	guest.failure_point = ""
	_check(guest.apply_guest_receipt(receipt).ok, "guest receipt applies")
	_check(guest.apply_guest_receipt(receipt).duplicate, "lost ACK resend deduplicated")
	_check(guest.data.personal.collections == ["sun-token"] and guest.data.personal.discoveries == ["I1-secret"], "guest received once")
	var loaded_guest = Store.new(guest.root_path)
	_check(loaded_guest.load_profile().ok and loaded_guest.apply_guest_receipt(receipt).duplicate, "guest dedup survives process reload")
	_check(host.apply_guest_receipt(receipt).error == "GUEST_WRONG_RECIPIENT", "wrong player cannot claim receipt")
	var tampered = receipt.duplicate(true)
	tampered.payload.collections.append("extra")
	_check(guest.apply_guest_receipt(tampered).error == "GUEST_RECEIPT_CONFLICT", "same receipt different grant rejected")
	_check(host.ack_guest_receipt(guest_id, receipt.receipt_id).ok and host.pending_guest_receipts(guest_id).is_empty(), "ACK retires pending item")
	_check(host.ack_guest_receipt(guest_id, receipt.receipt_id).duplicate, "ACK idempotent")
	_check(host.switch_branch("before-choice").ok, "branch for duplicate award test")
	_check(host.queue_guest_receipt(guest_id, "discovery:I1-secret", payload).duplicate, "branch cannot create new award identity")
	_check(host.queue_guest_receipt(guest_id, "discovery:I1-secret", {"collections":["extra"]}).error == "GUEST_RECEIPT_CONFLICT", "host cannot rewrite existing grant")
	var reloaded_host = Store.new(host.root_path)
	_check(reloaded_host.load_profile().ok and reloaded_host.list_branches().size() == 2, "branches reload")
	_check(reloaded_host.pending_guest_receipts(guest_id).is_empty(), "ACK persists across reload")
	var atomic_tx = {"id":"before-choice:objective:atomic", "set":{"world.flags.atomic_objective":true}, "guest_rewards":[{"guest_id":guest_id, "reward_id":"objective:atomic", "payload":{"collections":["atomic-medal"]}}]}
	var atomic_before: Dictionary = reloaded_host.snapshot()
	reloaded_host.failure_point = "before_publish"
	_check(not reloaded_host.commit(atomic_tx).ok, "atomic guest/world failure injected")
	_check(reloaded_host.snapshot() == atomic_before and reloaded_host.pending_guest_receipts(guest_id).is_empty(), "world and outbox both unchanged on failed publish")
	reloaded_host.failure_point = ""
	_check(reloaded_host.commit(atomic_tx).ok and reloaded_host.data.world.flags.atomic_objective, "world plus guest award committed")
	_check(reloaded_host.pending_guest_receipts(guest_id).size() == 1, "atomic award pending")
	_check(reloaded_host.commit(atomic_tx).duplicate and reloaded_host.pending_guest_receipts(guest_id).size() == 1, "atomic award dedup")
	var extra_before: Dictionary = reloaded_host.snapshot()
	_check(not reloaded_host.commit({"id":"invalid-guest-atomic", "set":{"world.flags.must_not_apply":true}, "guest_rewards":[{"guest_id":guest_id, "reward_id":"bad", "payload":{"collections":[{"not":"an id"}]}}]}).ok, "invalid reward rejects whole transaction")
	_check(reloaded_host.snapshot() == extra_before, "invalid atomic reward changes nothing")
	var build_conflict: Dictionary = reloaded_host.queue_guest_receipt(guest_id, "new-build-conflict", {"builds":[{"build_id":"gift-glider", "airframe_id":"other"}]})
	_check(build_conflict.ok and guest.apply_guest_receipt(build_conflict.receipt).error == "GUEST_BUILD_CONFLICT", "guest existing build cannot be silently overwritten")

func _test_consensus() -> void:
	var consensus = Consensus.new()
	_check(consensus.configure([1, 2], 10).ok, "two participants configured")
	var proposed: Dictionary = consensus.propose("major_choice", {"choice_id":"gate", "value":"close"}, 1)
	_check(proposed.ok and not proposed.ready, "host alone cannot make major choice")
	var id: String = proposed.proposal_id
	proposed.proposal.payload.value = "tamper"
	_check(consensus.current_proposal().payload.value == "close", "proposal return isolated")
	_check(not consensus.confirm(id, 99, 10).ok, "outsider cannot confirm")
	_check(not consensus.confirm(id, 99, 99).ok and not consensus.current_proposal().is_empty(), "outsider cannot cancel proposal with fake revision")
	_check(consensus.confirm(id, 2, 10).ready, "all required participants ready")
	_check(consensus.confirm(id, 2, 10).duplicate, "duplicate confirmation safe")
	_check(not consensus.propose("pause", {}, 1).ok, "ready proposal held until resolved")
	_check(consensus.resolve(id, true).ok and consensus.current_proposal().is_empty(), "durable action resolves proposal")
	var pending: Dictionary = consensus.propose("region_change", {"region_id":"F1"}, 1)
	_check(not consensus.confirm(pending.proposal_id, 2, 11).ok and consensus.current_proposal().is_empty(), "stale revision cancels")
	pending = consensus.propose("pause", {}, 1)
	consensus.set_world_revision(12)
	_check(consensus.current_proposal().is_empty(), "world mutation invalidates proposal")
	pending = consensus.propose("major_choice", {}, 1)
	_check(consensus.participant_disconnected(2).cancelled and consensus.current_proposal().is_empty(), "disconnect cancels pending without autoaccept")
	_check(consensus.propose("pause", {}, 1).ready, "remaining solo participant can propose new action")
	_check(consensus.configure(["solo"], 20).ok, "solo configured")
	_check(consensus.propose("region_change", {"region_id":"I2"}, "solo").ready, "solo ready immediately")
	_check(not consensus.configure([1, 2, 3], 20).ok and not consensus.configure([1, 1], 20).ok, "invalid roster rejected")
	consensus.configure([1, 2], 30)
	pending = consensus.propose("pause", {}, 1)
	_check(not consensus.resolve(pending.proposal_id, true).ok, "cannot commit unapproved action")
	_check(consensus.resolve(pending.proposal_id, false).ok, "explicit cancellation")
	_check(not consensus.propose("unsupported", {}, 1).ok, "unknown action rejected")
