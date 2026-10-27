class_name TwinClinicProgress
extends RefCounted
## Shared host evidence/history only. No SceneTree, storage, rewards, clock IO,
## actor identity or automatic Story submission. Host validates Waterworks first.
const SOURCE := "I2:clean_cistern"
const CLINIC := "I2:clinic_tank"
const RAIN := "I2:rain_tank"
const WASTE := "I2:waste_sump"
const GRAVITY := "I2:clean_to_clinic"
const PUMP := "I2:clean_pump_to_clinic"
const DIAGNOSE := "I2:clinic_supply:diagnose"
const CONNECT := "I2:clinic_supply:connect"
const STABILIZE := "I2:clinic_supply:stabilize"
const CONFIRM := "I2:clinic_supply:confirm"
const READY_FLAG := "I2:clinic_ready"
const TARGET_ML := 2000000
const STABLE_USEC := 2000000
const MAX_SERIAL := 9007199254740000
const MAX_DELTA := 0.25
const HISTORY_KEYS := ["version","route_method","first_transfer_ml","first_transfer","observed_serial","stable_usec","stable_fractional_usec","stabilized_once","commissioned"]
const TRANSFER_KEYS := ["source_id","destination_id","source_before","destination_before","clean_ml","dirty_ml","serial"]
const CAPACITY := {SOURCE:4800000,CLINIC:4000000,RAIN:800000,WASTE:1200000}
var _history: Dictionary = _default_history()
var _restore_permit := ""

static func _default_history() -> Dictionary:
	return {"version":1,"route_method":"","first_transfer_ml":0,"first_transfer":{},
		"observed_serial":0,"stable_usec":0,"stable_fractional_usec":0.0,
		"stabilized_once":false,"commissioned":false}

func snapshot() -> Dictionary:
	return _history.duplicate(true)

func observe(delta: float, before: Variant, after: Variant, status: Variant, step_result: Variant, physical_access: Variant, is_authority: bool = true, paused: bool = false) -> Dictionary:
	if not is_authority: return _result(false,"authority_required")
	if not _number(delta,0.0,MAX_DELTA) or not physical_access is bool: return _result(false,"observation_input")
	if not step_result is Dictionary or step_result.get("ok") != true or not step_result.get("ok") is bool: return _result(false,"step_not_accepted")
	var old := _sample(before)
	var now := _sample(after)
	if not old.ok: return old
	if not now.ok: return now
	var checked := _status_check(status,now)
	if not checked.ok: return checked
	checked = validate_history(_history,before)
	if not checked.ok: return checked
	if paused or delta==0.0:
		# Host pause is allowed to cancel axis velocity, but cannot move a valve,
		# change hydraulic state/clock, or count as an observed positive step.
		if old!=now or before.runtime!=after.runtime or float(before.gravity_fraction)!=float(after.gravity_fraction) or float(before.pump_fraction)!=float(after.pump_fraction) or not _integer(step_result.get("moved_ml",0),0,0): return _result(false,"paused_mechanism_changed")
		return _result(true,"paused")
	if int(now.serial)!=int(old.serial)+1: return _result(false,"observation_serial")
	# Subtract integer ticks first: no precision loss from a huge wall-clock value.
	var clock_change := float(int(now.tick)-int(old.tick))*100000.0 + float(int(now.pending)-int(old.pending)) + float(now.fraction)-float(old.fraction)
	if absf(clock_change-delta*1000000.0)>0.00001: return _result(false,"observation_clock")
	var clean := int(now.nodes[CLINIC].clean_ml)-int(old.nodes[CLINIC].clean_ml)
	var dirty := int(now.nodes[CLINIC].dirty_ml)-int(old.nodes[CLINIC].dirty_ml)
	if clean<0 or dirty<0 or clean+dirty>15000: return _result(false,"transfer_bounds")
	if int(old.nodes[SOURCE].clean_ml)-int(now.nodes[SOURCE].clean_ml)!=clean or int(old.nodes[SOURCE].dirty_ml)-int(now.nodes[SOURCE].dirty_ml)!=dirty: return _result(false,"transfer_components")
	for id in [RAIN,WASTE]:
		if old.nodes[id]!=now.nodes[id]: return _result(false,"isolated_node_changed")
	if not _integer(step_result.get("moved_ml"),0,15000) or int(step_result.moved_ml)!=clean+dirty: return _result(false,"transfer_result_mismatch")
	if clean+dirty>0 and (str(now.route).is_empty() or bool(now.blocked)): return _result(false,"transfer_without_valid_route")
	var next: Dictionary = _history.duplicate(true)
	if next.route_method=="" and clean+dirty>0:
		if clean==0 or int(old.volume)!=0: return _result(false,"missing_first_clean_transfer")
		next.route_method = str(now.route)
		next.first_transfer_ml = clean+dirty
		next.first_transfer = {"source_id":SOURCE,"destination_id":CLINIC,
			"source_before":old.nodes[SOURCE].duplicate(true),"destination_before":old.nodes[CLINIC].duplicate(true),
			"clean_ml":clean,"dirty_ml":dirty,"serial":int(now.serial)}
	# The last filling step was not stable for its whole duration. Count only
	# intervals whose source AND destination samples were already at cutoff.
	var stable: bool = int(old.volume)==TARGET_ML and bool(old.inlet_closed) and clean+dirty==0 and _stable(now,status,physical_access)
	if stable:
		var precise := delta*1000000.0+float(next.stable_fractional_usec)
		var elapsed := int(floor(precise+0.5))
		next.stable_usec = mini(STABLE_USEC,int(next.stable_usec)+elapsed)
		next.stable_fractional_usec = 0.0 if int(next.stable_usec)==STABLE_USEC else precise-float(elapsed)
		if int(next.stable_usec)==STABLE_USEC: next.stabilized_once=true
	else:
		next.stable_usec=0
		next.stable_fractional_usec=0.0
	next.observed_serial=int(now.serial)
	checked=validate_history(next,after)
	if not checked.ok: return checked
	_history=next
	return _result(true,"observed",true)

func fact_for(objective_id: String) -> Dictionary:
	if objective_id==CONNECT and not str(_history.route_method).is_empty():
		return {"kind":"fact","target":"I2:clinic_feed","option":str(_history.route_method)}
	if objective_id==STABILIZE and int(_history.stable_usec)==STABLE_USEC:
		return {"kind":"fact","target":"I2:clinic_water_ready","option":"verified"}
	return {}

func prepare_confirm(mechanism: Variant, status: Variant, physical_access: Variant) -> Dictionary:
	var checked := validate_history(_history,mechanism)
	if not checked.ok: return checked
	var current := _sample(mechanism)
	checked=_status_check(status,current)
	if not checked.ok: return checked
	if not physical_access is bool: return _result(false,"physical_access_type")
	if bool(_history.commissioned): return _result(false,"already_commissioned")
	if int(_history.stable_usec)!=STABLE_USEC or not _stable(current,status,physical_access): return _result(false,"not_stable")
	var next := snapshot()
	next.commissioned=true
	return {"ok":true,"code":"confirm_candidate","base_history_sha256":_hash(_history),"history":next,
		"fact":{"kind":"fact","target":"I2:clinic_water_check","option":"commissioned"}}

func adopt_confirm(candidate: Variant) -> bool:
	if not candidate is Dictionary or not _exact(candidate,["ok","code","base_history_sha256","history","fact"]): return false
	if candidate.ok!=true or not candidate.ok is bool or candidate.code!="confirm_candidate" or candidate.base_history_sha256!=_hash(_history): return false
	if bool(_history.commissioned) or int(_history.stable_usec)!=STABLE_USEC: return false
	var expected := snapshot()
	expected.commissioned=true
	if _hash(candidate.history)!=_hash(expected) or candidate.fact!={"kind":"fact","target":"I2:clinic_water_check","option":"commissioned"}: return false
	if not _history_shape(candidate.history).ok: return false
	_history=expected
	return true

# Internal consistency only: safe for already authority-bound reliable state
# arriving before/after Story. Never substitutes for prepare_restore on disk.
func validate_history(history: Variant, mechanism: Variant) -> Dictionary:
	var checked := _history_shape(history)
	if not checked.ok: return checked
	var water := _sample(mechanism)
	if not water.ok: return water
	if int(history.observed_serial)!=int(water.serial): return _result(false,"history_serial_mismatch")
	if history.route_method=="":
		if int(water.volume)!=0: return _result(false,"water_without_history")
	else:
		var first: Dictionary = history.first_transfer
		var source: Dictionary = water.nodes[SOURCE]
		var destination: Dictionary = water.nodes[CLINIC]
		for component in ["clean_ml","dirty_ml"]:
			var earlier_total := int(first.source_before[component])+int(first.destination_before[component])
			if earlier_total!=int(source[component])+int(destination[component]): return _result(false,"history_component_conservation")
			if int(source[component])>int(first.source_before[component])-int(first[component]) or int(destination[component])<int(first.destination_before[component])+int(first[component]): return _result(false,"history_transfer_reversed")
	if int(history.stable_usec)>0 or bool(history.stabilized_once) or bool(history.commissioned):
		if int(water.volume)!=TARGET_ML or int(water.nodes[CLINIC].clean_ml)*100<TARGET_ML*95 or not water.inlet_closed: return _result(false,"history_ready_water_mismatch")
	return _result(true,"valid")

func prepare_restore(envelope: Variant, completed: Array, world_flags: Dictionary) -> Dictionary:
	# A new preparation invalidates the old adoption permit, including failures.
	# This never changes the current gameplay/history snapshot.
	_restore_permit=""
	var progress := _story_state(completed,world_flags)
	if not progress.ok: return _restore_result(false,progress.code,false,{})
	if envelope==null:
		if progress.has_results: return _restore_result(false,"missing_i2_state_with_results",false,{})
		return _permit_restore("needs_initialization",true,_default_history())
	if not envelope is Dictionary or not _exact(envelope,["version","mechanism","history"]) or not _integer(envelope.get("version"),1,1): return _restore_result(false,"i2_envelope",false,{})
	var checked := validate_history(envelope.history,envelope.mechanism)
	if not checked.ok: return _restore_result(false,checked.code,false,{})
	var history: Dictionary = envelope.history
	if progress.connect and history.route_method=="": return _restore_result(false,"completed_connect_without_transfer",false,{})
	if progress.stabilize and not history.stabilized_once: return _restore_result(false,"completed_stabilize_without_history",false,{})
	if bool(history.commissioned)!=bool(progress.confirm) or bool(history.commissioned)!=bool(progress.ready): return _restore_result(false,"commissioned_story_mismatch",false,{})
	return _permit_restore("restore_prepared",false,_normalize(history))

func adopt_reliable_history(history: Variant, mechanism: Variant) -> bool:
	# Internal transport adapter only: the Session has already bound the sender,
	# epoch and serial. Story may arrive independently. Disk loading still must
	# use prepare_restore and its stricter world/objective consistency checks.
	if not validate_history(history, mechanism).ok: return false
	_history = _normalize(history)
	_restore_permit = ""
	return true

func adopt_restore(prepared: Variant) -> bool:
	if not prepared is Dictionary or not _exact(prepared,["ok","code","needs_init","history"]): return false
	if _restore_permit.is_empty() or _hash(prepared)!=_restore_permit or not _history_shape(prepared.history).ok: return false
	_history=_normalize(prepared.history)
	_restore_permit=""
	return true

func _permit_restore(code: String, needs_init: bool, history: Dictionary) -> Dictionary:
	var prepared := _restore_result(true,code,needs_init,history)
	_restore_permit=_hash(prepared)
	return prepared

static func _restore_result(ok: bool, code: String, needs_init: bool, history: Dictionary) -> Dictionary:
	return {"ok":ok,"code":code,"needs_init":needs_init,"history":history.duplicate(true)}

static func _story_state(completed: Array, flags: Dictionary) -> Dictionary:
	if completed.size()>256 or flags.size()>512: return _result(false,"story_bounds")
	var seen: Dictionary = {}
	for id in completed:
		if not id is String or id.length()>128 or seen.has(id): return _result(false,"completed_ids")
		seen[id]=true
		if id.begins_with("I2:") and id not in [DIAGNOSE,CONNECT,STABILIZE,CONFIRM]: return _result(false,"unknown_i2_result")
	for key in flags:
		# In-memory dot assignments use StringName; JSON restores use String.
		# Both represent the same stable key at this world-state boundary.
		if not (key is String or key is StringName): return _result(false,"flag_key")
		if key.begins_with("I2:") and key!=READY_FLAG: return _result(false,"unknown_i2_flag")
	if flags.has(READY_FLAG) and not flags[READY_FLAG] is bool: return _result(false,"ready_flag_type")
	var diagnose: bool = seen.has(DIAGNOSE)
	var connect: bool = seen.has(CONNECT)
	var stabilize: bool = seen.has(STABILIZE)
	var confirm: bool = seen.has(CONFIRM)
	var ready: bool = flags.get(READY_FLAG,false)
	if (connect and not diagnose) or (stabilize and not connect) or (confirm and not stabilize): return _result(false,"completed_prerequisites")
	return {"ok":true,"code":"valid","connect":connect,"stabilize":stabilize,"confirm":confirm,"ready":ready,"has_results":diagnose or connect or stabilize or confirm or ready}

static func _history_shape(raw: Variant) -> Dictionary:
	if not raw is Dictionary or not _exact(raw,HISTORY_KEYS): return _result(false,"history_keys")
	if not _integer(raw.version,1,1) or not raw.route_method is String or raw.route_method not in ["","gravity","pump"]: return _result(false,"history_version_route")
	if not _integer(raw.observed_serial,0,MAX_SERIAL) or not _integer(raw.stable_usec,0,STABLE_USEC) or not _number(raw.stable_fractional_usec,-0.5,0.499999999999): return _result(false,"history_clock")
	if not raw.stabilized_once is bool or not raw.commissioned is bool or not _integer(raw.first_transfer_ml,0,15000): return _result(false,"history_types")
	if (int(raw.stable_usec)==0 and float(raw.stable_fractional_usec)<0.0) or (int(raw.stable_usec)==STABLE_USEC and float(raw.stable_fractional_usec)!=0.0): return _result(false,"history_clock_remainder")
	if int(raw.stable_usec)==STABLE_USEC and not raw.stabilized_once: return _result(false,"history_stability_evidence")
	if raw.commissioned and not raw.stabilized_once: return _result(false,"history_confirmation_evidence")
	if raw.route_method=="":
		if not raw.first_transfer is Dictionary or not raw.first_transfer.is_empty() or int(raw.first_transfer_ml)!=0 or int(raw.stable_usec)!=0 or raw.stabilized_once or raw.commissioned: return _result(false,"history_empty_route")
		return _result(true,"valid")
	var first: Variant = raw.first_transfer
	if not first is Dictionary or not _exact(first,TRANSFER_KEYS) or first.source_id!=SOURCE or first.destination_id!=CLINIC: return _result(false,"first_transfer_keys")
	if not _components(first.source_before,CAPACITY[SOURCE]) or not _components(first.destination_before,CAPACITY[CLINIC]): return _result(false,"first_transfer_nodes")
	if int(first.destination_before.clean_ml)+int(first.destination_before.dirty_ml)!=0: return _result(false,"first_transfer_not_first")
	if not _integer(first.clean_ml,1,15000) or not _integer(first.dirty_ml,0,15000) or int(first.clean_ml)+int(first.dirty_ml)!=int(raw.first_transfer_ml): return _result(false,"first_transfer_amount")
	if int(first.clean_ml)>int(first.source_before.clean_ml) or int(first.dirty_ml)>int(first.source_before.dirty_ml) or not _integer(first.serial,1,int(raw.observed_serial)): return _result(false,"first_transfer_source")
	return _result(true,"valid")

static func _sample(raw: Variant) -> Dictionary:
	if not raw is Dictionary or not _integer(raw.get("schema_version"),2,2) or not _integer(raw.get("serial"),0,MAX_SERIAL): return _result(false,"mechanism_header")
	var runtime: Variant = raw.get("runtime")
	if not runtime is Dictionary or not runtime.get("simulation") is Dictionary or not runtime.get("facts") is Dictionary: return _result(false,"mechanism_water")
	var simulation: Dictionary = runtime.simulation
	if not simulation.get("nodes") is Dictionary or not _exact(simulation.nodes,[SOURCE,CLINIC,RAIN,WASTE]) or not simulation.get("edges") is Dictionary or not _exact(simulation.edges,[GRAVITY,PUMP]): return _result(false,"mechanism_topology")
	var clean := 0
	var dirty := 0
	for id in CAPACITY:
		if not _components(simulation.nodes[id],int(CAPACITY[id])): return _result(false,"mechanism_components")
		clean+=int(simulation.nodes[id].clean_ml)
		dirty+=int(simulation.nodes[id].dirty_ml)
	if clean!=3270000 or dirty!=430000: return _result(false,"mechanism_conservation")
	var volume := int(simulation.nodes[CLINIC].clean_ml)+int(simulation.nodes[CLINIC].dirty_ml)
	if volume>TARGET_ML: return _result(false,"mechanism_above_cutoff")
	var facts: Dictionary = runtime.facts
	if not _exact(facts,["gravity_open_permille","pump_open_permille","pump_powered","platform_blocked"]): return _result(false,"mechanism_facts")
	if not _integer(facts.gravity_open_permille,0,1000) or not _integer(facts.pump_open_permille,0,1000) or not facts.pump_powered is bool or not facts.platform_blocked is bool: return _result(false,"mechanism_fact_type")
	if int(facts.gravity_open_permille)>0 and int(facts.pump_open_permille)>0: return _result(false,"mechanism_interlock")
	if not _number(raw.get("gravity_fraction"),0,1) or not _number(raw.get("pump_fraction"),0,1) or not raw.get("pump_latched") is bool or not raw.get("powered") is bool or not raw.get("platform_blocked") is bool: return _result(false,"mechanism_pose")
	if int(facts.gravity_open_permille)!=(1000 if float(raw.gravity_fraction)>=0.995 else 0) or int(facts.pump_open_permille)!=(1000 if raw.pump_latched else 0) or raw.pump_latched!=(float(raw.pump_fraction)==1.0) or raw.powered!=facts.pump_powered or raw.platform_blocked!=facts.platform_blocked: return _result(false,"mechanism_pose_water_mismatch")
	var inlet_closed := true
	for id in [GRAVITY,PUMP]:
		var edge: Variant = simulation.edges[id]
		if not edge is Dictionary or not _integer(edge.get("open_permille"),0,1000) or not edge.get("powered") is bool: return _result(false,"mechanism_edge")
		var expected := 0 if volume==TARGET_ML or facts.platform_blocked else int(facts.gravity_open_permille if id==GRAVITY else facts.pump_open_permille)
		if int(edge.open_permille)!=expected or edge.powered!=(false if id==GRAVITY else facts.pump_powered): return _result(false,"mechanism_effective_controls")
		if expected>0: inlet_closed=false
	if not _integer(simulation.get("tick"),0,2147483647) or not _integer(runtime.get("pending_usec"),0,99999) or not _number(runtime.get("fractional_usec"),-0.5,0.499999999999): return _result(false,"mechanism_clock")
	var route := "gravity" if int(facts.gravity_open_permille)>0 else "pump" if int(facts.pump_open_permille)>0 and facts.pump_powered else ""
	return {"ok":true,"code":"valid","serial":int(raw.serial),"nodes":simulation.nodes.duplicate(true),"volume":volume,"inlet_closed":inlet_closed,"route":route,"blocked":bool(facts.platform_blocked),"tick":int(simulation.tick),"pending":int(runtime.pending_usec),"fraction":float(runtime.fractional_usec)}

static func _status_check(status: Variant, sample: Dictionary) -> Dictionary:
	if not status is Dictionary or not _integer(status.get("clinic_volume_ml"),0,TARGET_ML) or int(status.clinic_volume_ml)!=int(sample.volume): return _result(false,"status_volume")
	if not _number(status.get("clean_fraction"),0,1) or not _number(status.get("deck_top_y"),-3,18) or not status.get("automatic_cutoff") is bool or not status.get("inlet_closed") is bool: return _result(false,"status_shape")
	var expected_clean := float(sample.nodes[CLINIC].clean_ml)/float(sample.volume) if int(sample.volume)>0 else 0.0
	if absf(float(status.clean_fraction)-expected_clean)>0.000000001 or status.automatic_cutoff!=(int(sample.volume)==TARGET_ML) or status.inlet_closed!=sample.inlet_closed: return _result(false,"status_water_mismatch")
	return _result(true,"valid")

static func _stable(sample: Dictionary, status: Dictionary, access: bool) -> bool:
	return int(sample.volume)==TARGET_ML and int(sample.nodes[CLINIC].clean_ml)*100>=TARGET_ML*95 and bool(sample.inlet_closed) and bool(status.automatic_cutoff) and not sample.blocked and absf(float(status.deck_top_y)-5.0)<=0.002 and access

static func _components(value: Variant, capacity: int) -> bool:
	return value is Dictionary and _exact(value,["clean_ml","dirty_ml"]) and _integer(value.clean_ml,0,capacity) and _integer(value.dirty_ml,0,capacity) and int(value.clean_ml)+int(value.dirty_ml)<=capacity

static func _normalize(value: Dictionary) -> Dictionary:
	var out: Dictionary = value.duplicate(true)
	for key in ["version","first_transfer_ml","observed_serial","stable_usec"]: out[key]=int(out[key])
	out.stable_fractional_usec=float(out.stable_fractional_usec)
	if not out.first_transfer.is_empty():
		for key in ["clean_ml","dirty_ml","serial"]: out.first_transfer[key]=int(out.first_transfer[key])
		for key in ["source_before","destination_before"]:
			for component in ["clean_ml","dirty_ml"]: out.first_transfer[key][component]=int(out.first_transfer[key][component])
	return out

static func _hash(value: Variant) -> String:
	return JSON.stringify(value,"",true,true).sha256_text()

static func _exact(value: Dictionary, keys: Array) -> bool:
	if value.size()!=keys.size(): return false
	for key in value:
		if not key is String or key not in keys: return false
	return true

static func _number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=low and float(value)<=high

static func _integer(value: Variant, low: int, high: int) -> bool:
	return _number(value,float(low),float(high)) and floor(float(value))==float(value)

static func _result(ok: bool, code: String, changed: bool = false) -> Dictionary:
	return {"ok":ok,"code":code,"changed":changed}
