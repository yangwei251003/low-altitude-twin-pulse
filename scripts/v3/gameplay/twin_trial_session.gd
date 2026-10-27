class_name TwinTrialSession
extends RefCounted
## Independent trial lifecycle. No objectives, discoveries, rewards or background
## simulation. The caller commits a prepared world BEFORE adopting its Assembly.
signal gauge_read(peer_id: int, observation: Dictionary)
const Assembly = preload("res://scripts/v3/world/twin_trial_assembly.gd")
const Runtime = preload("res://scripts/v3/environment/twin_trial_flow_runtime.gd")
const STATE_PATH := "world.environment.I2_trial_flow"
const GAUGE_A := "I2:trial_gauge_a"
const GAUGE_B := "I2:trial_gauge_b"
const RETURN_SWITCH := "I2:trial_return_switch"
const TRACE_OBJECTIVE := "I2:distribution_audit:trace"
const TRACE_TARGET := "I2:distribution_route_verified"
const TRACE_FLAG := "I2:distribution_trace_verified"
const MAX_COUNTER := 9007199254740000
const MAX_PENDING_PACKETS := 8
const PUBLISH_SECONDS := 0.1
const RETRY_SECONDS := 0.5
const ENVELOPE_KEYS := ["version","link","station","observed_gauges"]
const EVENT_KEYS := ["kind","session_id","region","epoch","serial","state"]
const RECORD_KEYS := ["receiver_id","mechanism_serial","volume_ml","level_um","sample","link_geometry_sha256","station_layout_sha256"]
var session
var module
var ready := false
var error := ""
var serial := 0
var epoch := 0
var expected_serial := -1
var expected_epoch := -1
var expected_region := ""
var applied_serial := -1
var pending_observation: Dictionary = {}
var pending_network: Array[Dictionary] = []
var publish_clock := 0.0
var retry_clock := 0.0
var _observed := {"A":{},"B":{}}
var _retained_state: Dictionary = {}
var _bound_session := ""
var _last_packet: Dictionary = {}
var _needs_rebuild := true
var _handling_failure := false

func setup(owner_session) -> void:
	session=owner_session

func reset_connection() -> void:
	clear()
	serial=0
	epoch=0
	expected_serial=-1
	expected_epoch=-1
	expected_region=""
	applied_serial=-1
	pending_network.clear()
	_last_packet.clear()
	_bound_session=""

func clear() -> void:
	# Caller must guard/retry pending reads before travel, branch, quit or reset.
	# Visible Assemblies belong to World and are freed with that World.
	module=null
	ready=false
	error=""
	_observed={"A":{},"B":{}}
	_retained_state.clear()
	pending_observation.clear()
	publish_clock=0.0
	retry_clock=0.0
	_needs_rebuild=true

func prepare(world_data: Dictionary, destination: String, authority: bool, discoveries: Array = []) -> Dictionary:
	if destination not in ["I1","I2","I3","I4","F1","F2","F3","F4"]: return _failure("trial_destination")
	if not world_data.get("environment",{}) is Dictionary: return _failure("trial_environment")
	if not world_data.get("actions", {}) is Dictionary or not world_data.get("flags", {}) is Dictionary or not world_data.get("completed_objectives", []) is Array: return _failure("trial_world_results")
	var opening: Variant = world_data.get("actions", {}).get("opening", {})
	if not opening is Dictionary or not opening.get("completed", []) is Array or not opening.get("choices", {}) is Dictionary: return _failure("trial_story_results")
	var environment: Dictionary=world_data.get("environment",{})
	var missing: bool=not environment.has("I2_trial_flow")
	if missing and _has_results(world_data,discoveries): return _failure("trial_missing_history")
	var envelope: Variant=environment.get("I2_trial_flow")
	if not missing and (not envelope is Dictionary or not _exact(envelope,ENVELOPE_KEYS)):
		return _failure("trial_envelope")
	var candidate = Assembly.new()
	# Configure without authority normalization first, so validation observes the
	# original exact saved pair. v1 independent Station cannot enter this envelope.
	var pair: Dictionary={} if missing else {"link":envelope.link,"station":envelope.station}
	var configured: Dictionary=candidate.configure(pair,false)
	if not configured.ok:
		candidate.free()
		return _failure("trial_mechanism:"+str(configured.code))
	if not missing:
		var valid:=_validate_envelope(envelope,candidate)
		if not valid.ok:
			candidate.free()
			return valid
		if _has_trace_result(world_data):
			var fact: Dictionary = trace_fact_from(envelope, candidate)
			var option: Variant = world_data.get("actions", {}).get("opening", {}).get("choices", {}).get(TRACE_OBJECTIVE)
			if fact.is_empty() or option != fact.option:
				candidate.free()
				return _failure("trial_trace_result_mismatch")
	var history: Dictionary={"A":{},"B":{}} if missing else envelope.observed_gauges.duplicate(true)
	if authority:
		# Recreate a detached authority candidate. The existing live world is never
		# touched by stopping axes/rosters or clearing a saved return request.
		candidate.free()
		candidate=Assembly.new()
		configured=candidate.configure(pair,true)
		if not configured.ok:
			candidate.free()
			return _failure("trial_host_restore:"+str(configured.code))
	var next:=_envelope(candidate.snapshot(),history)
	var stopped: bool=not missing and not _same(pair,candidate.snapshot())
	var result: Dictionary={"ok":true,"error":"","module":null,"destination":destination,
		"needs_init":missing and destination=="I2","stopped":stopped,"migrated":false,
		"state":{} if missing and destination!="I2" else next}
	if destination=="I2": result.module=candidate
	else: candidate.free() # No hidden World3D, timers, water loss or catch-up.
	return result

func discard(prepared: Dictionary) -> void:
	var candidate: Variant=prepared.get("module")
	if is_instance_valid(candidate) and candidate is Node and candidate.get_parent()==null: candidate.free()

func adopt(prepared: Dictionary, _world_data: Dictionary) -> void:
	clear()
	if not prepared.get("ok",false) or str(prepared.get("destination",""))!=str(session.region_id):
		error="trial_adopt_unprepared"
		return
	module=prepared.get("module")
	_retained_state=prepared.get("state",{}).duplicate(true)
	if not _retained_state.is_empty(): _observed=_retained_state.observed_gauges.duplicate(true)
	if session.region_id=="I2":
		if not is_instance_valid(module) or not module.is_inside_tree():
			error="trial_world_must_own_assembly"
			return
		var linked: Dictionary=module.bind()
		if not linked.ok:
			error="trial_binding:"+str(linked.code)
			return
	if session.network.is_authority():
		ready=true
		if is_instance_valid(module):
			var synced: Dictionary=module.synchronize_impulse_roster({})
			if not synced.ok:
				_fail_live("trial_roster:"+str(synced.code))
				return
			_update_positions()
		if epoch>=MAX_COUNTER:
			_fail_live("trial_epoch_limit")
			return
		epoch+=1
		publish()
	else:
		ready=false
		applied_serial=-1
		_needs_rebuild=true

func persistent_state() -> Dictionary:
	if not ready: return {}
	return _envelope(module.snapshot(),_observed) if is_instance_valid(module) else _retained_state.duplicate(true)

func observed_gauges() -> Dictionary:
	return _observed.duplicate(true)

## Only durable observations can advance the investigation. Today's full/empty
## tanks and an unsaved gauge request are not proof of a completed reading.
func committed_flow_fact() -> Dictionary:
	if not _host_local(): return {}
	var saved: Variant = session.world_cache.get("world", {}).get("environment", {}).get("I2_trial_flow")
	return trace_fact_from(saved, module)

static func trace_fact_from(raw: Variant, checker) -> Dictionary:
	if not _validate_envelope(raw, checker).ok: return {}
	if raw.observed_gauges.A.is_empty() or raw.observed_gauges.B.is_empty(): return {}
	var manual := 0
	var pulse := 0
	for selection in ["A", "B"]:
		var sample: Dictionary = raw.station.runtime.samples[selection]
		manual += int(sample.manual_ml)
		pulse += int(sample.pulse_ml)
	if manual + pulse != Runtime.SAMPLE_ML * 2: return {}
	var option := "mixed_trial"
	if pulse == 0: option = "manual_trial"
	elif manual == 0: option = "pulse_trial"
	return {"type":"fact", "target_id":TRACE_TARGET, "option":option}

func has_pending_observation() -> bool:
	return not pending_observation.is_empty()

func sync_roster(reset_peer: int = 0) -> void:
	if not _host_local(): return
	var checked: Dictionary=module.synchronize_impulse_roster(session.players)
	if not checked.ok:
		_fail_live("trial_roster:"+str(checked.code))
		return
	if reset_peer>0 and session.players.has(reset_peer) and session.players[reset_peer].enabled and float(session.players[reset_peer].health)>0:
		checked=module.reset_impulse_peer(reset_peer)
		if not checked.ok: _fail_live("trial_reset_peer:"+str(checked.code))

func set_paused(value: bool) -> void:
	if not is_instance_valid(module): return
	var checked: Dictionary=module.set_simulation_paused(value)
	if not checked.ok:
		_fail_live("trial_pause:"+str(checked.code))
		return
	if session.network.is_authority(): publish()

func advance(delta: float) -> void:
	if not _host_local() or session.simulation_paused: return
	if not is_finite(delta) or delta<0.0 or delta>1.0:
		_fail_live("trial_delta_range")
		return
	var remaining:=delta
	while remaining>0.0000001:
		var part:=minf(remaining,Assembly.MAX_DELTA)
		var moved: Dictionary=module.fixed_update(part,session.entities,session.players,true)
		if not moved.ok:
			_fail_live("trial_update:"+str(moved.code))
			return
		remaining-=part
	_update_positions()
	publish_clock+=delta
	retry_clock+=delta
	if has_pending_observation() and retry_clock>=RETRY_SECONDS and session.consensus.current_proposal().is_empty():
		retry_clock=0.0
		retry_pending()
	if publish_clock>=PUBLISH_SECONDS:
		publish_clock=0.0
		publish()

func observe_gauge(peer_id: int, receiver_id: String) -> Dictionary:
	if not _host_local() or session.simulation_paused or not session.players.has(peer_id): return _observation(false,"trial_unavailable")
	var observed: Dictionary=module.observe_gauge(peer_id,session.players[peer_id],receiver_id)
	if not observed.ok:
		session._note(peer_id,"靠近接收箱正面的刻度窗，避开遮挡后再读取。")
		return observed
	# Actual successful observations always feed the read-only view, including an
	# empty/partial tank. They never enter from a client-supplied evidence record.
	gauge_read.emit(peer_id,observed.duplicate(true))
	if not observed.sample.complete:
		session._note(peer_id,"已读取实际水位；这一侧的首份 20 L 试样尚未完整。")
		return _observation(true,"reading_only")
	var label: String="A" if receiver_id==Runtime.RECEIVER_A else "B"
	if not _observed[label].is_empty(): return _observation(true,"already_observed")
	# First accepted local reading wins even if a later read happens while disk
	# is unavailable; retry saves that evidence with CURRENT mechanisms.
	if not pending_observation.has(label):
		pending_observation[label]={"receiver_id":receiver_id,"mechanism_serial":int(observed.mechanism_serial),
			"volume_ml":int(observed.volume_ml),"level_um":250000+int(observed.volume_ml)*5,
			"sample":observed.sample.duplicate(true),"link_geometry_sha256":observed.link_geometry_sha256,
			"station_layout_sha256":observed.station_layout_sha256}
	retry_clock=0.0
	var saved:=retry_pending()
	if saved: session._note(peer_id,"这侧刻度窗的首份完整试样读数已保存。")
	else: session._note(peer_id,"读数已看清，仍待保存；不会提前记作成果。")
	return _observation(saved,"gauge_observed" if saved else "observation_save_pending")

func request_return(peer_id: int) -> Dictionary:
	if not _host_local() or session.simulation_paused or not session.players.has(peer_id): return _observation(false,"trial_unavailable")
	var requested: Dictionary=module.request_return(peer_id,session.players[peer_id])
	if requested.ok: publish()
	else: session._note(peer_id,"靠近回流开关，并让开关直接进入视线后再操作。")
	return requested

func retry_pending() -> bool:
	if not has_pending_observation(): return true
	if not _host_local(): return false
	if not session.consensus.current_proposal().is_empty() and not session._resolving_decision:
		error="trial_save_deferred_for_consensus"
		return false
	var history:=_observed.duplicate(true)
	for label in pending_observation:
		if history[label].is_empty(): history[label]=pending_observation[label].duplicate(true)
	var envelope:=_envelope(module.snapshot(),history)
	var checked:=_validate_envelope(envelope,module)
	if not checked.ok:
		error="trial_retry:"+str(checked.error)
		return false
	if not session._commit("trial-gauge-observation",{STATE_PATH:envelope,"world.entities.I2":session._persistent_environment()}):
		error="trial_observation_save_failed"
		return false
	_observed=history
	pending_observation.clear()
	error=""
	retry_clock=0.0
	publish()
	return true

func publish(peer_id: int = 0) -> void:
	if session==null or not session.owns_world or not session.network.is_authority() or not ready or epoch<1: return
	if peer_id==0 or serial==0:
		if serial>=MAX_COUNTER:
			_fail_live("trial_serial_limit")
			return
		serial+=1
	# Keep simulation and serials advancing; an empty broadcast has no recipient
	# and needs no materialized save/event payload. Targeted joins remain live.
	if peer_id<=1 and session.network.guests.is_empty(): return
	var event: Dictionary={"kind":"trial_state","session_id":session.network.session_id,"region":session.region_id,
		"epoch":epoch,"serial":serial,"state":persistent_state() if session.region_id=="I2" else {}}
	if peer_id>1: session.network.send_event(peer_id,event)
	else:
		for peer in session.network.guests: session.network.send_event(int(peer),event)

func receive(event: Dictionary) -> void:
	if session==null or session.network.mode!="guest" or not session.active: return
	if not _exact(event,EVENT_KEYS) or event.get("kind")!="trial_state": return
	if not event.session_id is String or event.session_id.is_empty() or event.session_id.length()>128: return
	if event.region not in ["I1","I2","I3","I4","F1","F2","F3","F4"] or not event.state is Dictionary: return
	if not _integer(event.serial,1,MAX_COUNTER) or not _integer(event.epoch,1,MAX_COUNTER) or var_to_bytes(event).size()>32768: return
	if not session.received_session.is_empty() and event.session_id!=session.received_session: return
	if not _bound_session.is_empty() and event.session_id!=_bound_session: return
	if int(event.epoch)<expected_epoch: return
	for cached in pending_network:
		if cached.session_id==event.session_id and cached.epoch==event.epoch and cached.region==event.region and cached.serial==event.serial: return
	pending_network.append(event.duplicate(true))
	while pending_network.size()>MAX_PENDING_PACKETS: pending_network.pop_front()
	consume(expected_serial,expected_epoch,expected_region)

func consume(snapshot_serial: int, snapshot_epoch: int, region: String) -> bool:
	if session==null or session.network.mode!="guest": return true
	if not _integer(snapshot_serial,1,MAX_COUNTER) or not _integer(snapshot_epoch,1,MAX_COUNTER) or region not in ["I1","I2","I3","I4","F1","F2","F3","F4"]: return false
	if session.received_session.is_empty(): return false
	if _bound_session.is_empty(): _bound_session=session.received_session
	elif _bound_session!=session.received_session: return false
	if snapshot_epoch<expected_epoch or (snapshot_epoch==expected_epoch and not expected_region.is_empty() and region!=expected_region): return false
	if snapshot_epoch==expected_epoch and snapshot_serial<expected_serial: return false
	var new_context: bool=snapshot_epoch!=expected_epoch or region!=expected_region
	if new_context:
		applied_serial=-1
		_last_packet.clear()
		_needs_rebuild=true
	if new_context or snapshot_serial!=expected_serial: ready=false
	expected_serial=snapshot_serial
	expected_epoch=snapshot_epoch
	expected_region=region
	_filter_network()
	if region!="I2":
		ready=true
		return true
	if not is_instance_valid(module) or not module.is_inside_tree(): return false
	if ready and not _needs_rebuild and applied_serial==snapshot_serial: return true
	var packet: Dictionary={}
	for candidate in pending_network:
		if candidate.epoch==snapshot_epoch and candidate.region==region and candidate.serial==snapshot_serial:
			packet=candidate
			break
	if packet.is_empty() and _needs_rebuild and not _last_packet.is_empty() and int(_last_packet.serial)==snapshot_serial: packet=_last_packet
	# Exact referenced serial barrier: an old reliable frame cannot release a
	# pilot whose motion packet already names a newer mechanism/history frame.
	if packet.is_empty(): return false
	if not _apply_packet(packet):
		pending_network.erase(packet)
		return false
	_last_packet=packet.duplicate(true)
	applied_serial=snapshot_serial
	_needs_rebuild=false
	ready=true
	error=""
	_filter_network()
	return true

func _apply_packet(packet: Dictionary) -> bool:
	var checked:=_validate_envelope(packet.state,module)
	if not checked.ok:
		error="trial_network:"+str(checked.error)
		return false
	if not _last_packet.is_empty():
		for part in ["link","station"]:
			var previous: Dictionary=_last_packet.state[part]
			var incoming: Dictionary=packet.state[part]
			if int(incoming.serial)<int(previous.serial): return false
			if incoming.serial==previous.serial and not _same(incoming,previous): return false
		for label in ["A","B"]:
			var old: Dictionary=_last_packet.state.observed_gauges[label]
			if not old.is_empty() and not _same(old,packet.state.observed_gauges[label]): return false
	var applied: Dictionary=module.apply_snapshot({"link":packet.state.link,"station":packet.state.station})
	if not applied.ok: return false
	_observed=packet.state.observed_gauges.duplicate(true)
	_update_positions()
	return true

func _filter_network() -> void:
	var kept: Array[Dictionary]=[]
	for packet in pending_network:
		if packet.session_id!=_bound_session or int(packet.epoch)<expected_epoch: continue
		if int(packet.epoch)==expected_epoch:
			if packet.region!=expected_region or int(packet.serial)<expected_serial: continue
		kept.append(packet)
	pending_network=kept

func _update_positions() -> void:
	if not is_instance_valid(module) or session.region_id!="I2": return
	for id in module.target_bodies:
		if session.entities.has(id): session.entities[id].position=module.entity_position(id)

func _host_local() -> bool:
	return session!=null and session.active and session.owns_world and session.network.is_authority() and session.region_id=="I2" and ready and is_instance_valid(module) and module.is_inside_tree()

func _fail_live(code: String) -> void:
	error=code
	ready=false
	if _handling_failure: return
	_handling_failure=true
	if session!=null and session.owns_world and session.network.is_authority():
		session.simulation_paused=true
		session._apply_pause_state()
		session._note_all("试流状态校验未通过，世界已暂停；已保存记录保留。")
	push_error(code)
	_handling_failure=false

func _observation(ok: bool, code: String) -> Dictionary:
	return {"ok":ok,"code":code,"pending":has_pending_observation()}

static func _envelope(pair: Dictionary, history: Dictionary) -> Dictionary:
	return {"version":1,"link":pair.link.duplicate(true),"station":pair.station.duplicate(true),"observed_gauges":history.duplicate(true)}

static func _validate_envelope(raw: Variant, checker) -> Dictionary:
	if not raw is Dictionary or not _exact(raw,ENVELOPE_KEYS) or not _integer(raw.version,1,1): return _failure("trial_envelope")
	var checked: Dictionary=checker.validate_snapshot({"link":raw.link,"station":raw.station})
	if not checked.ok: return _failure("trial_pair:"+str(checked.code))
	if not raw.observed_gauges is Dictionary or not _exact(raw.observed_gauges,["A","B"]): return _failure("trial_history_keys")
	for label in ["A","B"]:
		var record: Variant=raw.observed_gauges[label]
		if not record is Dictionary: return _failure("trial_history_record")
		if record.is_empty(): continue
		if not _exact(record,RECORD_KEYS): return _failure("trial_history_schema")
		var receiver: String=Runtime.RECEIVER_A if label=="A" else Runtime.RECEIVER_B
		if record.receiver_id!=receiver or not _integer(record.mechanism_serial,0,int(raw.station.serial)): return _failure("trial_history_identity")
		if record.link_geometry_sha256!=raw.link.geometry_sha256 or record.station_layout_sha256!=raw.station.layout_sha256: return _failure("trial_history_layout")
		if not _integer(record.volume_ml,0,200000) or not _integer(record.level_um,250000,1250000) or int(record.level_um)!=250000+int(record.volume_ml)*5: return _failure("trial_history_level")
		# A receiver is deliberately fed by the OTHER labelled selection. Validate
		# against the immutable first-20L ledger, not today's water after a return.
		var selection: String="B" if label=="A" else "A"
		var expected: Dictionary=raw.station.runtime.samples[selection].duplicate(true)
		var amount: int=int(expected.clean_ml)+int(expected.dirty_ml)
		if amount!=Runtime.SAMPLE_ML: return _failure("trial_incomplete_sample")
		expected.merge({"moved_ml":amount,"complete":true,"source":Runtime.SOURCE,"destination":receiver})
		if not record.sample is Dictionary or not _same(record.sample,expected): return _failure("trial_history_sample")
	return {"ok":true,"error":""}

static func _has_results(world_data: Dictionary, discoveries: Array) -> bool:
	if _has_trace_result(world_data): return true
	# Personal discoveries from another branch do not prove this branch has run
	# the experiment. Reserved unknown trial prefixes still reject silent resets.
	var actions: Variant=world_data.get("actions",{})
	var opening: Variant=actions.get("opening",{}) if actions is Dictionary else {}
	var completed: Variant=opening.get("completed",[]) if opening is Dictionary else []
	for list in [completed,world_data.get("completed_objectives",[]),discoveries]:
		if not list is Array: return true
		for id in list:
			if id is String and id.begins_with("I2:trial"): return true
	var flags: Variant=world_data.get("flags",{})
	if not flags is Dictionary: return true
	for key in flags:
		if (key is String or key is StringName) and str(key).begins_with("I2:trial") and flags[key]!=false: return true
	return false

static func _has_trace_result(world_data: Dictionary) -> bool:
	var actions: Variant = world_data.get("actions", {})
	if not actions is Dictionary or not actions.get("opening", {}) is Dictionary: return false
	var opening: Dictionary = actions.get("opening", {})
	if not opening.get("completed", []) is Array or not opening.get("choices", {}) is Dictionary or not world_data.get("completed_objectives", []) is Array or not world_data.get("flags", {}) is Dictionary: return false
	return TRACE_OBJECTIVE in opening.get("completed", []) or TRACE_OBJECTIVE in world_data.get("completed_objectives", []) or opening.get("choices", {}).has(TRACE_OBJECTIVE) or world_data.get("flags", {}).get(TRACE_FLAG, false) != false

static func _same(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float): return is_finite(float(a)) and is_finite(float(b)) and float(a)==float(b)
	if typeof(a)!=typeof(b): return false
	if a is Dictionary:
		if a.size()!=b.size(): return false
		for key in a:
			if not b.has(key) or not _same(a[key],b[key]): return false
		return true
	if a is Array:
		if a.size()!=b.size(): return false
		for i in range(a.size()):
			if not _same(a[i],b[i]): return false
		return true
	return a==b

static func _integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=low and float(value)<=high and floor(float(value))==float(value)

static func _exact(value: Dictionary, keys: Array) -> bool:
	if value.size()!=keys.size(): return false
	for key in value:
		if not key is String or key not in keys: return false
	return true

static func _failure(code: String) -> Dictionary:
	return {"ok":false,"error":code}
