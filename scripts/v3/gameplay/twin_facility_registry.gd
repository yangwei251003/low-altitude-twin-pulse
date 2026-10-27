class_name TwinFacilityRegistry
extends RefCounted
## Adapters retain all domain validation, IO,
## authority checks, retry transactions, off-region policy and receive semantics.
## The caller owns candidate World nodes and commits BEFORE calling adopt().
const Clinic = preload("res://scripts/v3/gameplay/twin_clinic_session.gd")
const Distribution = preload("res://scripts/v3/gameplay/twin_distribution_session.gd")
const Trial = preload("res://scripts/v3/gameplay/twin_trial_session.gd")
const SharedAccess = preload("res://scripts/v3/gameplay/twin_shared_access_session.gd")
const Contract = preload("res://scripts/v3/network/twin_facility_contract.gd")
const I2Results = preload("res://scripts/v3/gameplay/twin_i2_result_ledger.gd")
const IDS := ["clinic", "distribution", "trial", "shared_access"]
var error := ""
var _session
var _adapters: Dictionary = {}
var _definitions: Array = []
var _targets: Dictionary = {}
var _impulses: Dictionary = {}
var _events: Dictionary = {}
var _barrier_ready := false

static func definitions() -> Array:
	return [
		{"id":"clinic", "region":"I2", "slot":1, "path":"world.environment.I2_water",
			"event":"clinic_state", "serial_key":"clinic_serial", "epoch_key":"clinic_epoch",
			"targets":[Clinic.Works.GRAVITY_ID, Clinic.Works.PUMP_ID, Clinic.Works.RELAY_ID],
			"impulses":[Clinic.Works.GRAVITY_ID]},
		{"id":"distribution", "region":"I2", "slot":2, "path":Distribution.STATE_PATH,
			"event":"distribution_state", "serial_key":"distribution_serial", "epoch_key":"distribution_epoch",
			"targets":[Distribution.Cabinet.COVER_ID, Distribution.Cabinet.RELAY_ID, Distribution.Cabinet.LOCK_ID],
			"impulses":[Distribution.Cabinet.COVER_ID]},
		{"id":"trial", "region":"I2", "slot":3, "path":Trial.STATE_PATH,
			"event":"trial_state", "serial_key":"trial_serial", "epoch_key":"trial_epoch",
			"targets":[Trial.Assembly.Link.HANDLE, Trial.Assembly.Station.SELECTOR, Trial.Assembly.Station.RELAY, Trial.Assembly.Station.CONTROLLER],
			"impulses":[Trial.Assembly.Link.HANDLE, Trial.Assembly.Station.SELECTOR]},
		{"id":"shared_access", "region":"I2", "slot":4, "path":SharedAccess.STATE_PATH,
			"event":"shared_access_state", "serial_key":"shared_access_serial", "epoch_key":"shared_access_epoch",
			"targets":[SharedAccess.Bridge.HANDLE, SharedAccess.Bridge.PIN, SharedAccess.Bridge.RELAY, SharedAccess.Bridge.PUBLIC_CONTROL, SharedAccess.Bridge.SERVICE_CONTROL],
			"impulses":[SharedAccess.Bridge.HANDLE, SharedAccess.Bridge.PIN]}
	]

## Pure registration check. Production setup always uses the fixed table above;
## this is not a loader for descriptors/scripts supplied by a save or a peer.
static func validate_definitions(raw: Variant) -> Dictionary:
	if not raw is Array or raw.is_empty(): return _failure("definition_array")
	var seen: Dictionary = {"id":{}, "path":{}, "slot":{}, "event":{}, "wire":{}, "target":{}}
	for item in raw:
		if not item is Dictionary: return _failure("definition_shape")
		for key in ["id", "region", "path", "event", "serial_key", "epoch_key"]:
			if not item.get(key) is String or item[key].is_empty(): return _failure("definition_" + key)
		if not item.path.begins_with("world.environment.") or item.path.trim_prefix("world.environment.").contains(".") or item.path.ends_with("."):
			return _failure("definition_path")
		if not item.get("slot") is int or item.slot < 1: return _failure("definition_slot")
		for key in ["id", "path", "slot", "event"]:
			if seen[key].has(item[key]): return _failure("duplicate_" + key)
			seen[key][item[key]] = true
		for key in ["serial_key", "epoch_key"]:
			if seen.wire.has(item[key]): return _failure("duplicate_wire")
			seen.wire[item[key]] = true
		if not item.get("targets") is Array or not item.get("impulses") is Array: return _failure("definition_targets")
		for target in item.targets:
			if not target is String or target.is_empty(): return _failure("definition_target")
			if seen.target.has(target): return _failure("duplicate_target")
			seen.target[target] = true
		var impulses: Dictionary = {}
		for target in item.impulses:
			if not target is String or target not in item.targets or impulses.has(target): return _failure("definition_impulse")
			impulses[target] = true
	return {"ok":true, "error":""}

func setup(owner_session, instances: Dictionary) -> Dictionary:
	if not _adapters.is_empty(): return _failure("already_setup")
	if not is_instance_valid(owner_session) or instances.size() != IDS.size(): return _failure("setup_instances")
	if not instances.get("clinic") is Clinic or not instances.get("distribution") is Distribution or not instances.get("trial") is Trial or not instances.get("shared_access") is SharedAccess:
		return _failure("setup_adapter_types")
	var next: Array = definitions()
	var checked: Dictionary = validate_definitions(next)
	if not checked.ok: return checked
	for entry in next:
		var declared: Dictionary = Contract.DEFINITIONS[int(entry.slot)-1]
		if declared.id != entry.id or declared.region != entry.region: return _failure("wire_registration_mismatch")
	_session = owner_session
	_definitions = next
	_adapters = instances.duplicate()
	for entry in _definitions:
		_adapters[entry.id].setup(owner_session)
		_events[entry.event] = entry.id
		for target in entry.targets: _targets[target] = entry.id
		for target in entry.impulses: _impulses[target] = entry.id
	return {"ok":true, "error":""}

func prepare(world_data: Dictionary, destination: String, authority: bool, discoveries: Array = []) -> Dictionary:
	if _adapters.is_empty(): return _failure("not_setup")
	var ledger: Dictionary = I2Results.validate_world(world_data, discoveries)
	if not ledger.ok: return _failure("i2_results:" + str(ledger.error))
	var result: Dictionary = {"ok":true, "error":"", "region":destination, "entries":{}, "modules":{}, "initialization":{}, "states":{}}
	for entry in _definitions:
		var adapter = _adapters[entry.id]
		var candidate: Dictionary
		if entry.id == "clinic": candidate = adapter.prepare(world_data, destination, authority)
		else: candidate = adapter.prepare(world_data, destination, authority, discoveries)
		if not candidate.get("ok", false):
			discard(result)
			return _failure(str(entry.id) + ":" + str(candidate.get("error", "prepare_failed")))
		result.entries[entry.id] = candidate
		result.modules[entry.id] = candidate.get("module")
		var module: Variant = candidate.get("module")
		if is_instance_valid(module):
			var actual: Array = []
			for target in module.target_definitions(): actual.append(target.id)
			var expected: Array = entry.targets.duplicate()
			actual.sort()
			expected.sort()
			if actual != expected:
				discard(result)
				return _failure(str(entry.id) + ":registered_targets_changed")
		var state: Dictionary = candidate.get("state", {})
		if state.is_empty(): continue
		result.states[entry.path] = state.duplicate(true)
		var initialize: bool = bool(candidate.get("needs_init", false)) or bool(candidate.get("migrated", false))
		if entry.id == "clinic":
			initialize = not world_data.get("environment", {}).has("I2_water") or bool(candidate.get("migrated", false))
		if initialize: result.initialization[entry.path] = state.duplicate(true)
	return result

func discard(prepared: Dictionary) -> void:
	# Never free a child owned by a candidate World, even after its parent has
	# been removed from the tree. The caller disposes that World exactly once.
	for entry in _definitions:
		var candidate: Dictionary = prepared.get("entries", {}).get(entry.id, {})
		var module: Variant = candidate.get("module")
		if is_instance_valid(module) and module.get_parent() == null:
			_adapters[entry.id].discard(candidate)

func adopt(prepared: Dictionary, world_data: Dictionary) -> Dictionary:
	if _adapters.is_empty() or not prepared.get("ok", false) or prepared.get("region") != _session.region_id:
		return _failure("adopt_prepared_region")
	# Structural preflight before any adapter changes its current references.
	# World.build/bind and the caller's Store transaction remain prerequisites.
	for entry in _definitions:
		var candidate: Variant = prepared.get("entries", {}).get(entry.id)
		if not candidate is Dictionary or not candidate.get("ok", false): return _failure("adopt_missing:" + str(entry.id))
		var module: Variant = candidate.get("module")
		if prepared.region == entry.region and (not is_instance_valid(module) or not module.is_inside_tree()):
			return _failure("adopt_world_must_own:" + str(entry.id))
	_barrier_ready = false
	var errors: Array[String] = []
	for entry in _definitions:
		var adapter = _adapters[entry.id]
		adapter.adopt(prepared.entries[entry.id], world_data)
		if not adapter.error.is_empty(): errors.append(str(entry.id) + ":" + str(adapter.error))
	error = ";".join(errors)
	return {"ok":errors.is_empty(), "error":error}

## Flat Store patch, not a new envelope. Caller-supplied fields take precedence
## when merging (e.g. a pending observation's newly committed history).
func persistent_states() -> Dictionary:
	var patch: Dictionary = {}
	for entry in _definitions:
		var state: Dictionary = _adapters[entry.id].persistent_state()
		if not state.is_empty(): patch[entry.path] = state
	return patch

func pending_retry() -> bool:
	# Preserve the existing transaction order: a failed earlier observation must
	# block travel/branch. Clinic has no independent pending-observation writer.
	if _adapters.is_empty(): return false
	for id in ["distribution", "trial"]:
		if _adapters.has(id) and not _adapters[id].retry_pending(): return false
	return true

func has_pending_observation() -> bool:
	for id in ["distribution", "trial"]:
		if _adapters.has(id) and _adapters[id].has_pending_observation(): return true
	return false

func clear() -> void:
	for entry in _definitions: _adapters[entry.id].clear()
	_barrier_ready = false
	error = ""

func reset_connection() -> void:
	for entry in _definitions: _adapters[entry.id].reset_connection()
	_barrier_ready = false
	error = ""

func set_paused(value: bool) -> void:
	for entry in _definitions: _adapters[entry.id].set_paused(value)

func sync_roster(reset_peer: int = 0) -> void:
	for entry in _definitions: _adapters[entry.id].sync_roster(reset_peer)

func advance(delta: float) -> void:
	# Do not filter by current region: Clinic intentionally advances its visited
	# history in a background World; the other adapters retain frozen state.
	for entry in _definitions:
		var qa_clock: int = _session._qa_cpu_begin() if _session.has_method("_qa_cpu_begin") else 0
		_adapters[entry.id].advance(delta)
		if qa_clock != 0: _session._qa_cpu_end("facility."+str(entry.id),qa_clock)

func publish(peer_id: int = 0) -> void:
	for entry in _definitions: _adapters[entry.id].publish(peer_id)

func all_ready(region: String) -> bool:
	if _adapters.is_empty(): return false
	for entry in _definitions:
		if entry.region != region: continue
		if not _adapters[entry.id].ready: return false
		if _session.network.mode == "guest" and not _barrier_ready: return false
	return true

func legacy_refs() -> Dictionary:
	var refs: Dictionary = {}
	for entry in _definitions:
		refs[entry.serial_key] = _adapters[entry.id].serial
		refs[entry.epoch_key] = _adapters[entry.id].epoch
	return refs

func wire_refs() -> Array:
	var refs: Array = []
	for entry in _definitions:
		refs.append([entry.slot, _adapters[entry.id].epoch, _adapters[entry.id].serial])
	return refs

func consume_all(packet: Dictionary, region: String) -> bool:
	if _adapters.is_empty(): return false
	var refs: Variant = packet.get("facility_refs")
	if not Contract.valid_refs(refs):
		_barrier_ready = false
		return false
	var complete := true
	for entry in _definitions:
		# Only protect the typed call boundary; each unchanged adapter retains its
		# own counter bounds, session/epoch validation and exact-vs-latest policy.
		var reference: Dictionary = Contract.ref_for_slot(refs, entry.slot)
		var serial: int = reference.serial
		var epoch: int = reference.epoch
		var accepted: bool = _adapters[entry.id].consume(serial, epoch, region)
		if not accepted: complete = false # Never short-circuit later consumers.
	_barrier_ready = complete
	return complete

func receive(event: Dictionary) -> bool:
	var kind: Variant = event.get("kind")
	if not kind is String or not _events.has(kind): return false
	_adapters[_events[kind]].receive(event)
	return true # Routed only; adapter validation may have rejected the event.

func owner_for_target(target: String) -> String:
	return str(_targets.get(target, ""))

func impulse_owner(target: String) -> String:
	return str(_impulses.get(target, ""))

func can_accept_impulse(target: String, impulse: Vector3, peer: int, action_serial: int) -> Dictionary:
	var id: String = impulse_owner(target)
	var checked: Dictionary = _impulse_context(id)
	if not checked.ok: return checked
	var adapter = _adapters[id]
	adapter.sync_roster()
	return adapter.module.can_accept_impulse(target, impulse, peer, action_serial)

func apply_authorized_impulse(target: String, impulse: Vector3, peer: int, action_serial: int) -> Dictionary:
	var checked: Dictionary = _impulse_context(impulse_owner(target))
	if not checked.ok: return checked
	# Only after the caller's Rules.commit; no extra actor revision/energy write.
	return _adapters[impulse_owner(target)].module.apply_authorized_impulse(target, impulse, peer, action_serial)

func _impulse_context(id: String) -> Dictionary:
	if id.is_empty(): return {"ok":false, "code":"unregistered_impulse"}
	if not is_instance_valid(_session) or _session.region_id != "I2" or not _session.network.is_authority():
		return {"ok":false, "code":"facility_unavailable"}
	var adapter = _adapters[id]
	if not adapter.ready or not is_instance_valid(adapter.module) or not adapter.module.is_inside_tree():
		return {"ok":false, "code":"facility_unavailable"}
	return {"ok":true, "code":"owned_impulse"}

static func _reference(value: Variant) -> int:
	if value is int: return value
	if value is float and is_finite(value) and value >= 1.0 and value <= 9007199254740000.0 and floor(value) == value: return int(value)
	return -1

static func _failure(code: String) -> Dictionary:
	return {"ok":false, "error":code}
