extends RefCounted
## Candidate rules only. No Node, coordinates, timers, RPC, Story or Store.
## Executor receipts are trusted HOST INTERNAL calls, never client testimony.
const Water = preload("res://scripts/v3/gameplay/environment/twin_water_network.gd")
const VERSION := 1
const ALGORITHM := "canal-service-work-priority-thermal-v2"
const MAX_COUNTER := 2147483647
const STEP_USEC := 100000
const MAX_DELTA_USEC := 5000000
const SOUTH_0 := "south_0"
const SOUTH_1 := "south_1"
const WORK := "north_work"
const BUFFER := "north_buffer"
const CARRIER := "carrier"
const WAIT := "wide_bay_wait"
const PILOTS := ["pilot_a", "pilot_b"]
const BERTHS := [SOUTH_0, SOUTH_1, WORK, BUFFER]
const HOLDERS := [SOUTH_0, SOUTH_1, WORK, BUFFER, CARRIER, "pilot_a", "pilot_b"]
const CASSETTES := ["I2:canal_cassette_0", "I2:canal_cassette_1"]
const RESERVOIR := "I2:canal_cooling_reservoir"
const JACKET := "I2:canal_cooling_jacket"
const RETURN := "I2:canal_cooling_return"
const PUMP := "I2:canal_cooling_pump"
const DRAIN := "I2:canal_cooling_drain"
const RECIRCULATE := "I2:canal_cooling_recirculate"
const AMBIENT_MC := 20000
const COLD_MC := 45000
const MIN_MC := -40000
const MAX_MC := 200000
## mJ per milli-Celsius, numerically equal to J / Celsius. Model calibration,
## not a measured device: two 2 kg cartridges and one well-mixed 8 L bath.
const POD_CAPACITY := 1000
const WATER_CAPACITY := 33440
const WORK_HEAT_MJ := 25000000
const INITIAL_HEAT_MJ := 50000000
const MAX_HEAT_LEDGER := 1000000000000
const MAX_EXCHANGE_MJ_PER_ML := 2000
const RADIATOR_MJ_PER_ML := 1000
const ACTION_KEYS := ["serial", "kind", "actor", "cassette_id", "source", "destination", "route", "job", "blocked"]
const RECEIPT_KEYS := ["serial", "kind", "actor", "cassette_id", "source", "destination", "route", "job", "path_clear", "endpoint_valid", "custody_verified", "completed"]
const SAVE_KEYS := ["version", "algorithm", "revision", "command_serial", "action_serial", "policy", "buffer_enabled", "carrier_anchor", "pilots", "cassettes", "pending_action", "job_requested", "jobs_completed", "service_credit", "services_consumed", "service_serial", "pending_usec", "flow_credit_usec", "heat_credit", "water_energy_mj", "thermal_ledger", "pump_total_ml", "water"]
var _state: Dictionary = {}
var _network = Water.new()
var _prepared_service: Dictionary = {}

static func water_definition() -> Dictionary:
	return {"schema_version":1,"id":"I2:canal_cooling_closed_v1","version":1,
		"nodes":[
			{"id":RESERVOIR,"capacity_ml":7000,"clean_ml":5700,"dirty_ml":300,"base_mm":0,"area_cm2":100},
			{"id":JACKET,"capacity_ml":1500,"clean_ml":950,"dirty_ml":50,"base_mm":1500,"area_cm2":100},
			{"id":RETURN,"capacity_ml":1500,"clean_ml":950,"dirty_ml":50,"base_mm":750,"area_cm2":100}],
		"edges":[_edge(PUMP,RESERVOIR,JACKET,"pump"),_edge(DRAIN,JACKET,RETURN,"gravity"),_edge(RECIRCULATE,RETURN,RESERVOIR,"gravity")]}

static func _edge(id: String, source: String, target: String, kind: String) -> Dictionary:
	return {"id":id,"from":source,"to":target,"kind":kind,"max_rate_ml_s":1000,
		"conductance_ml_s_per_mm":10 if kind=="gravity" else 0,"pump_head_mm":3000 if kind=="pump" else 0,
		"initial_open_permille":0,"initial_powered":false,"bidirectional":false}

func configure() -> Dictionary:
	var candidate = Water.new()
	var checked: Dictionary = candidate.configure(water_definition())
	if not checked.ok: return _result(false,"water_configuration")
	_network=candidate
	_state={"version":VERSION,"algorithm":ALGORITHM,"revision":0,"command_serial":0,"action_serial":0,
		"policy":"staggered","buffer_enabled":false,"carrier_anchor":WAIT,
		"pilots":{"pilot_a":{"peer_id":0,"enabled":false},"pilot_b":{"peer_id":0,"enabled":false}},
		"cassettes":{CASSETTES[0]:{"holder":CARRIER,"mass_g":2000,"energy_mj":0},CASSETTES[1]:{"holder":WORK,"mass_g":2000,"energy_mj":INITIAL_HEAT_MJ}},
		"pending_action":{},"job_requested":true,"jobs_completed":0,"service_credit":0,"services_consumed":0,"service_serial":0,
		"pending_usec":0,"flow_credit_usec":0,"heat_credit":_empty_heat_credit(),"water_energy_mj":0,
		"thermal_ledger":{"work_added":0,"ability_added":0,"ability_removed":0,"ambient_added":0,"ambient_removed":0},
		"pump_total_ml":0,"water":candidate.snapshot()}
	_prepared_service.clear()
	return _result(true,"configured")

func snapshot() -> Dictionary:
	return _state.duplicate(true)

func status() -> Dictionary:
	if _state.is_empty(): return {}
	var temperatures: Dictionary={}
	for id in CASSETTES: temperatures[id]=float(_state.cassettes[id].energy_mj)/POD_CAPACITY/1000.0+20.0
	return {"policy":_state.policy,"buffer_enabled":_state.buffer_enabled,"temperatures_c":temperatures,
		"water_temperature_c":float(_state.water_energy_mj)/WATER_CAPACITY/1000.0+20.0,
		"occupancy":_occupancy(_state),"last_confirmed_carrier_anchor":_state.carrier_anchor,
		"pending_action":_state.pending_action.duplicate(true),"service_credit":_state.service_credit,
		"jobs_completed":_state.jobs_completed,"job_requested":_state.job_requested,
		"elapsed_usec":int(_state.water.tick)*STEP_USEC+int(_state.pending_usec),"proposal":_plan(_state)}

## Commands contain an expected revision and a monotonic HOST facility serial.
## The adapter validates Rules ownership/energy/LOS before this internal call.
func apply_command(command: Dictionary, authority: bool=true, paused: bool=false) -> Dictionary:
	var gate: Dictionary=_gate(authority,paused)
	if not gate.ok: return gate
	if not _integer(command.get("serial"),1,MAX_COUNTER) or int(command.serial)<=int(_state.command_serial): return _result(false,"command_replay")
	if not _integer(command.get("expected_revision"),int(_state.revision),int(_state.revision)): return _result(false,"stale_revision")
	var next: Dictionary=_state.duplicate(true)
	match command.get("kind"):
		"policy":
			if not _exact(command,["serial","expected_revision","kind","policy"]) or command.policy not in ["staggered","buffered"]: return _result(false,"policy_command")
			if not next.pending_action.is_empty(): return _result(false,"action_in_flight")
			next.policy=command.policy
		"pilot":
			if not _exact(command,["serial","expected_revision","kind","slot","peer_id","enabled"]) or command.slot not in PILOTS or not _integer(command.peer_id,0,MAX_COUNTER) or not command.enabled is bool: return _result(false,"pilot_command")
			if command.enabled and int(command.peer_id)==0: return _result(false,"pilot_identity")
			for slot in PILOTS:
				if slot!=command.slot and int(command.peer_id)!=0 and int(next.pilots[slot].peer_id)==int(command.peer_id): return _result(false,"duplicate_peer")
			if int(command.peer_id)!=int(next.pilots[command.slot].peer_id):
				if not _at(next,str(command.slot)).is_empty() or _action_touches(next.pending_action,str(command.slot)): return _result(false,"cargo_recovery_required")
			next.pilots[command.slot]={"peer_id":int(command.peer_id),"enabled":command.enabled}
		"thermal":
			if not _exact(command,["serial","expected_revision","kind","cassette_id","delta_mc"]) or command.cassette_id not in CASSETTES or not _integer(command.delta_mc,-25000,25000) or int(command.delta_mc)==0: return _result(false,"thermal_command")
			var pod: Dictionary=next.cassettes[command.cassette_id]
			var old_energy: int=int(pod.energy_mj)
			pod.energy_mj=clampi(old_energy+int(command.delta_mc)*POD_CAPACITY,(MIN_MC-AMBIENT_MC)*POD_CAPACITY,(MAX_MC-AMBIENT_MC)*POD_CAPACITY)
			var difference: int=int(pod.energy_mj)-old_energy
			next.thermal_ledger["ability_added" if difference>=0 else "ability_removed"]+=absi(difference)
		_:
			return _result(false,"unknown_command")
	next.command_serial=int(command.serial)
	return _commit(next,"command_applied")

## A proposal is not movement. There is one bounded physical action in flight.
func request_action(expected_revision: int, authority: bool=true, paused: bool=false) -> Dictionary:
	var gate: Dictionary=_gate(authority,paused)
	if not gate.ok: return gate
	if expected_revision!=int(_state.revision): return _result(false,"stale_revision")
	if not _state.pending_action.is_empty(): return {"ok":true,"code":"already_pending","action":_state.pending_action.duplicate(true)}
	var proposal: Dictionary=_plan(_state)
	if proposal.is_empty(): return _result(true,"waiting")
	return _reserve(proposal)

## External player grips are bounded roles. Role -> actual peer is the adapter's
## responsibility. A disconnected holder must be physically recovered, not erased.
func request_handoff(request: Dictionary, authority: bool=true, paused: bool=false) -> Dictionary:
	var gate: Dictionary=_gate(authority,paused)
	if not gate.ok: return gate
	if not _exact(request,["expected_revision","actor","cassette_id","source","destination"]): return _result(false,"handoff_keys")
	for key in ["actor","cassette_id","source","destination"]:
		if not request[key] is String: return _result(false,"handoff_types")
	if not _integer(request.expected_revision,int(_state.revision),int(_state.revision)): return _result(false,"stale_revision")
	if not _state.pending_action.is_empty(): return _result(false,"action_in_flight")
	var action: Dictionary=_action("handoff",str(request.actor),str(request.cassette_id),str(request.source),str(request.destination),"manual")
	var checked: Dictionary=_validate_action(action,_state,false)
	if not checked.ok: return checked
	return _reserve(action)

func _reserve(action: Dictionary) -> Dictionary:
	if int(_state.action_serial)>=MAX_COUNTER: return _result(false,"counter_limit")
	var next: Dictionary=_state.duplicate(true)
	next.action_serial+=1
	action.serial=int(next.action_serial)
	next.pending_action=action.duplicate(true)
	var result: Dictionary=_commit(next,"action_requested")
	if result.ok: result.action=_state.pending_action.duplicate(true)
	return result

## No RPC may call this with client-provided booleans. A future physical executor
## checks the whole path, endpoints, old holder and new attachment before receipt.
func confirm_action(receipt: Dictionary, authority: bool=true, paused: bool=false) -> Dictionary:
	var gate: Dictionary=_gate(authority,paused)
	if not gate.ok: return gate
	if not _exact(receipt,RECEIPT_KEYS) or _state.pending_action.is_empty(): return _result(false,"receipt_without_action")
	var action: Dictionary=_state.pending_action
	for key in ["serial","kind","actor","cassette_id","source","destination","route","job"]:
		if not _same(receipt[key],action[key]): return _result(false,"receipt_mismatch:"+key)
	for key in ["path_clear","endpoint_valid","custody_verified","completed"]:
		if not receipt[key] is bool or not receipt[key]: return _result(false,"physical_confirmation_required:"+key)
	var checked: Dictionary=_validate_action(action,_state,true)
	if not checked.ok: return checked
	if action.kind=="handoff" and action.actor!="recovery":
		for holder in [action.source,action.destination]:
			if holder in PILOTS and not _state.pilots[holder].enabled: return _result(false,"pilot_unavailable")
	var next: Dictionary=_state.duplicate(true)
	match action.kind:
		"move": next.carrier_anchor=action.destination
		"pick","place","tray","handoff": next.cassettes[action.cassette_id].holder=action.destination
		"buffer_enable": next.buffer_enabled=true
		"buffer_disable": next.buffer_enabled=false
		"work":
			if not _cold(next,str(action.cassette_id)): return _result(false,"work_overheated")
			next.cassettes[action.cassette_id].energy_mj+=WORK_HEAT_MJ
			next.thermal_ledger.work_added+=WORK_HEAT_MJ
			next.jobs_completed+=1
			next.service_credit=1
			next.job_requested=false
	next.pending_action={}
	return _commit(next,"action_confirmed")

func report_blocked(action_serial: int, authority: bool=true, paused: bool=false) -> Dictionary:
	var gate: Dictionary=_gate(authority,paused)
	if not gate.ok: return gate
	if _state.pending_action.is_empty() or int(_state.pending_action.serial)!=action_serial: return _result(false,"unknown_action")
	if _state.pending_action.blocked: return _result(true,"already_blocked")
	var next: Dictionary=_state.duplicate(true)
	next.pending_action.blocked=true
	return _commit(next,"action_blocked")

## Aborting also needs an executor receipt: the original physical configuration
## must be restored, including a grip interrupted mid-transfer. No timeout abort.
func abort_action(action_serial: int, source_restored: bool, authority: bool=true, paused: bool=false) -> Dictionary:
	var gate: Dictionary=_gate(authority,paused)
	if not gate.ok: return gate
	if _state.pending_action.is_empty() or int(_state.pending_action.serial)!=action_serial: return _result(false,"unknown_action")
	if not source_restored: return _result(false,"source_recovery_required")
	var next: Dictionary=_state.duplicate(true)
	next.pending_action={}
	return _commit(next,"action_aborted_at_source")

## Integer microseconds are deliberate: no wall clock or lost sub-frame remainder.
## Caller converts its explicit simulation delta with its persistent time accumulator.
## Contacts name the actually coupled cartridge in each south socket, or "".
func step(delta_usec: Variant, facts: Dictionary, authority: bool=true, paused: bool=false) -> Dictionary:
	if _state.is_empty(): return _result(false,"not_configured")
	if not authority: return _result(false,"authority_required")
	if not _integer(delta_usec,0,MAX_DELTA_USEC): return _result(false,"invalid_delta_usec")
	var checked: Dictionary=_validate_facts(facts,_state)
	if not checked.ok: return checked
	if paused or int(delta_usec)==0: return _result(true,"paused")
	var next: Dictionary=_state.duplicate(true)
	var candidate = Water.new()
	if not candidate.configure(water_definition()).ok or not candidate.restore(next.water).ok: return _result(false,"water_candidate")
	var remaining: int=int(delta_usec)
	var moved: int=0
	while remaining>0:
		var portion: int=mini(remaining,STEP_USEC-int(next.pending_usec))
		if facts.powered and facts.valve_open and facts.sweep_clear:
			next.flow_credit_usec+=portion
			for berth in [SOUTH_0,SOUTH_1]:
				var id: String=str(facts.contacts[berth])
				if id.is_empty(): continue
				var difference: int=_equilibrium_exchange(next,id)
				# 2 kW = 2 mJ / microsecond, exact under call subdivision.
				var limit: int=mini(absi(difference),portion*2)
				if difference>0: next.heat_credit[id].loss+=limit
				elif difference<0: next.heat_credit[id].gain+=limit
		next.pending_usec+=portion
		remaining-=portion
		if int(next.pending_usec)==STEP_USEC:
			checked=_water_tick(next,candidate)
			if not checked.ok: return checked
			moved+=int(checked.moved_ml)
			next.pending_usec=0
			next.flow_credit_usec=0
			next.heat_credit=_empty_heat_credit()
	next.water=candidate.snapshot()
	var result: Dictionary=_commit(next,"advanced")
	if result.ok: result.moved_ml=moved
	return result

@warning_ignore("integer_division")
func _water_tick(next: Dictionary, water) -> Dictionary:
	var opening: int=int(next.flow_credit_usec)*1000/STEP_USEC
	var controls: Dictionary={PUMP:{"open_permille":opening,"powered":opening>0},DRAIN:{"open_permille":opening},RECIRCULATE:{"open_permille":opening}}
	var result: Dictionary=water.step(0.1,controls)
	if not result.ok: return _result(false,"water_step:"+str(result.code))
	var moved: int=int(water.get_edge(PUMP).last_transfer_ml)
	next.pump_total_ml+=moved
	var budget: int=moved*MAX_EXCHANGE_MJ_PER_ML
	for id in CASSETTES:
		var equalization: int=_equilibrium_exchange(next,id)
		var credit: int=int(next.heat_credit[id].loss if equalization>0 else next.heat_credit[id].gain)
		var exchange: int=mini(budget,mini(absi(equalization),credit))
		if equalization<0: exchange=-exchange
		next.cassettes[id].energy_mj-=exchange
		next.water_energy_mj+=exchange
		budget-=absi(exchange)
	var dissipated: int=mini(absi(int(next.water_energy_mj)),moved*RADIATOR_MJ_PER_ML)
	if int(next.water_energy_mj)>0:
		next.water_energy_mj-=dissipated
		next.thermal_ledger.ambient_removed+=dissipated
	else:
		next.water_energy_mj+=dissipated
		next.thermal_ledger.ambient_added+=dissipated
	# Close published internal commands without advancing hydraulic time.
	# Water.step(0) intentionally ignores commands. Restore only the control
	# fields of its exact snapshot; volumes, transfer evidence and tick stay intact.
	var closed: Dictionary=water.snapshot()
	for edge in closed.edges.values():
		edge.open_permille=0
		edge.powered=false
	if not water.restore(closed).ok: return _result(false,"water_control_checkpoint")
	return {"ok":true,"code":"water_tick","moved_ml":moved}

@warning_ignore("integer_division")
func _equilibrium_exchange(state: Dictionary, id: String) -> int:
	return (int(state.cassettes[id].energy_mj)*WATER_CAPACITY-int(state.water_energy_mj)*POD_CAPACITY)/(POD_CAPACITY+WATER_CAPACITY)

func prepare_service(expected_revision: int, request_serial: int, authority: bool=true, paused: bool=false) -> Dictionary:
	var gate: Dictionary=_gate(authority,paused)
	if not gate.ok: return gate
	if expected_revision!=int(_state.revision): return _result(false,"stale_revision")
	if request_serial<=int(_state.service_serial) or request_serial>MAX_COUNTER: return _result(false,"service_replay")
	if int(_state.service_credit)!=1: return _result(false,"service_unavailable")
	var next: Dictionary=_state.duplicate(true)
	next.service_credit=0
	next.services_consumed+=1
	next.service_serial=request_serial
	next.job_requested=true
	next.revision+=1
	var checked: Dictionary=validate_snapshot(next)
	if not checked.ok: return checked
	_prepared_service={"ok":true,"code":"prepared","expected_revision":expected_revision,"request_serial":request_serial,"candidate":next}
	return _prepared_service.duplicate(true)

## Call only AFTER the external Store commits this exact envelope + consumption.
func adopt_service(prepared: Dictionary, authority: bool=true, paused: bool=false) -> Dictionary:
	var gate: Dictionary=_gate(authority,paused)
	if not gate.ok: return gate
	if _prepared_service.is_empty() or not _same(prepared,_prepared_service): return _result(false,"unprepared_service")
	if int(prepared.expected_revision)!=int(_state.revision): return _result(false,"stale_revision")
	var checked: Dictionary=validate_snapshot(prepared.candidate)
	if not checked.ok: return checked
	_state=prepared.candidate.duplicate(true)
	_prepared_service.clear()
	return _result(true,"service_adopted")

func _plan(state: Dictionary) -> Dictionary:
	if state.is_empty() or not state.pending_action.is_empty(): return {}
	var work: String=_at(state,WORK)
	var buffered: String=_at(state,BUFFER)
	var carried: String=_at(state,CARRIER)
	# A locally cooled work cartridge can satisfy the existing demand while the
	# carrier waits safely. Never preempt a reserved action or claim that the
	# last confirmed anchor alone proves a physical workbench is ready: the host
	# executor still has to verify its actual pose, grip, tool and work result.
	if state.carrier_anchor==WAIT and state.job_requested and not work.is_empty() and _cold(state,work):
		return _work_action(state,work)
	if state.policy=="buffered" and not state.buffer_enabled and state.job_requested: return _action("buffer_enable","buffer_actuator","","closed","open","high")
	if state.policy=="staggered" and state.buffer_enabled and buffered.is_empty():
		if state.carrier_anchor==BUFFER: return _action("move",CARRIER,carried,BUFFER,WAIT,"low")
		return _action("buffer_disable","buffer_actuator","","open","closed","low")
	if not carried.is_empty():
		if _cold(state,carried) and state.job_requested:
			if work.is_empty(): return _delivery(state,carried,WORK)
			if state.policy=="buffered" and buffered.is_empty(): return _delivery(state,carried,BUFFER)
		var free: String=_free_south(state)
		return {} if free.is_empty() else _delivery(state,carried,free)
	if not work.is_empty() and not _cold(state,work):
		if state.policy=="buffered" and buffered.is_empty() and state.job_requested:
			var cold: String=_cold_south(state)
			if not cold.is_empty(): return _pickup(state,cold)
		return {} if _free_south(state).is_empty() else _pickup(state,work)
	if work.is_empty() and not buffered.is_empty():
		if state.job_requested and _cold(state,buffered): return _action("tray","tray",buffered,BUFFER,WORK,"high")
		return {} if _free_south(state).is_empty() else _pickup(state,buffered)
	if not work.is_empty() and state.job_requested and _cold(state,work):
		return _work_action(state,work)
	if state.job_requested and work.is_empty():
		var cold: String=_cold_south(state)
		if not cold.is_empty(): return _pickup(state,cold)
	return {}

func _work_action(state: Dictionary, id: String) -> Dictionary:
	var action: Dictionary=_action("work","workbench",id,WORK,WORK,"stationary")
	action.job=int(state.jobs_completed)+1
	return action

func _pickup(state: Dictionary, id: String) -> Dictionary:
	var berth: String=str(state.cassettes[id].holder)
	var route: String="high" if state.policy=="buffered" else "low"
	if str(state.carrier_anchor)!=berth: return _action("move",CARRIER,"",str(state.carrier_anchor),berth,route)
	return _action("pick",CARRIER,id,berth,CARRIER,route)

func _delivery(state: Dictionary, id: String, berth: String) -> Dictionary:
	var route: String="high" if state.policy=="buffered" else "low"
	if str(state.carrier_anchor)!=berth: return _action("move",CARRIER,id,str(state.carrier_anchor),berth,route)
	return _action("place",CARRIER,id,CARRIER,berth,route)

static func _action(kind: String, actor: String, id: String, source: String, destination: String, route: String) -> Dictionary:
	return {"serial":0,"kind":kind,"actor":actor,"cassette_id":id,"source":source,"destination":destination,"route":route,"job":0,"blocked":false}

func _validate_action(a: Dictionary, s: Dictionary, reserved: bool) -> Dictionary:
	if not _exact(a,ACTION_KEYS): return _result(false,"action_keys")
	if not _integer(a.serial,1 if reserved else 0,MAX_COUNTER) or not _integer(a.job,0,MAX_COUNTER) or not a.blocked is bool: return _result(false,"action_types")
	for key in ["kind","actor","cassette_id","source","destination","route"]:
		if not a[key] is String: return _result(false,"action_types")
	if a.route not in ["low","high","manual","stationary"]: return _result(false,"action_route")
	# The installed north buffer tray always traverses its real high route.
	# Changing the carrier policy must not relabel or strand an occupied tray.
	var required_route: String="manual" if a.kind=="handoff" else "stationary" if a.kind=="work" else "high" if a.kind=="tray" or s.policy=="buffered" else "low"
	if a.route!=required_route: return _result(false,"action_route_policy")
	if a.kind!="work" and int(a.job)!=0: return _result(false,"action_job")
	match a.kind:
		"move":
			if a.actor!=CARRIER or a.source!=s.carrier_anchor or a.destination not in BERTHS+[WAIT] or a.source==a.destination or a.cassette_id!=_at(s,CARRIER): return _result(false,"move_precondition")
			if not _at(s,str(a.destination)).is_empty() and not a.cassette_id.is_empty(): return _result(false,"destination_occupied")
			if a.destination==BUFFER and not s.buffer_enabled: return _result(false,"buffer_closed")
		"pick","place","tray","handoff":
			if a.cassette_id not in CASSETTES or a.source not in HOLDERS or a.destination not in HOLDERS or a.source==a.destination: return _result(false,"transfer_identity")
			if s.cassettes[a.cassette_id].holder!=a.source or not _at(s,str(a.destination)).is_empty(): return _result(false,"transfer_occupancy")
			if a.kind=="pick" and (a.actor!=CARRIER or a.source not in BERTHS or a.destination!=CARRIER or s.carrier_anchor!=a.source): return _result(false,"pick_precondition")
			if a.kind=="place" and (a.actor!=CARRIER or a.source!=CARRIER or a.destination not in BERTHS or s.carrier_anchor!=a.destination): return _result(false,"place_precondition")
			if a.kind=="tray" and (a.actor!="tray" or a.source!=BUFFER or a.destination!=WORK or not s.buffer_enabled): return _result(false,"tray_precondition")
			if (a.source==BUFFER or a.destination==BUFFER) and not s.buffer_enabled: return _result(false,"buffer_closed")
			if a.kind=="handoff":
				if a.source not in PILOTS and a.destination not in PILOTS: return _result(false,"handoff_requires_external_grip")
				if a.actor=="recovery":
					if a.source not in PILOTS or s.pilots[a.source].enabled or a.destination not in BERTHS: return _result(false,"recovery_precondition")
				elif a.actor not in PILOTS or (a.actor!=a.source and a.actor!=a.destination): return _result(false,"handoff_actor")
				for holder in [a.source,a.destination]:
					if holder in PILOTS and (int(s.pilots[holder].peer_id)==0 or (not reserved and not s.pilots[holder].enabled and a.actor!="recovery")): return _result(false,"pilot_unavailable")
		"buffer_enable","buffer_disable":
			var enabling: bool=a.kind=="buffer_enable"
			if a.actor!="buffer_actuator" or a.cassette_id!="" or a.source!=("closed" if enabling else "open") or a.destination!=("open" if enabling else "closed") or bool(s.buffer_enabled)==enabling: return _result(false,"buffer_precondition")
			if not enabling and (not _at(s,BUFFER).is_empty() or s.carrier_anchor==BUFFER): return _result(false,"buffer_occupied")
		"work":
			if a.actor!="workbench" or a.cassette_id not in CASSETTES or a.source!=WORK or a.destination!=WORK or s.cassettes[a.cassette_id].holder!=WORK or not s.job_requested or int(s.service_credit)!=0 or int(a.job)!=int(s.jobs_completed)+1: return _result(false,"work_precondition")
		_:
			return _result(false,"unknown_action")
	return _result(true,"action_valid")

func validate_snapshot(saved: Dictionary) -> Dictionary:
	if _state.is_empty(): return _result(false,"not_configured")
	if not _exact(saved,SAVE_KEYS) or not _integer(saved.version,VERSION,VERSION) or saved.algorithm!=ALGORITHM: return _result(false,"snapshot_version_keys")
	for key in ["revision","command_serial","action_serial","jobs_completed","services_consumed","service_serial"]:
		if not _integer(saved[key],0,MAX_COUNTER): return _result(false,"snapshot_counter")
	if int(saved.revision)<maxi(int(saved.action_serial),maxi(int(saved.jobs_completed),int(saved.services_consumed))): return _result(false,"snapshot_revision")
	if saved.policy not in ["staggered","buffered"] or not saved.buffer_enabled is bool or not saved.job_requested is bool: return _result(false,"snapshot_mode")
	if saved.carrier_anchor not in BERTHS+[WAIT]: return _result(false,"snapshot_anchor")
	if saved.carrier_anchor==BUFFER and not saved.buffer_enabled: return _result(false,"snapshot_closed_anchor")
	if not saved.pilots is Dictionary or not _exact(saved.pilots,PILOTS) or not saved.cassettes is Dictionary or not _exact(saved.cassettes,CASSETTES): return _result(false,"snapshot_ids")
	var peers: Array=[]
	for slot in PILOTS:
		var pilot: Variant=saved.pilots[slot]
		if not pilot is Dictionary or not _exact(pilot,["peer_id","enabled"]) or not _integer(pilot.peer_id,0,MAX_COUNTER) or not pilot.enabled is bool: return _result(false,"snapshot_pilot")
		if int(pilot.peer_id)==0 and pilot.enabled: return _result(false,"snapshot_pilot_identity")
		if int(pilot.peer_id)!=0:
			if int(pilot.peer_id) in peers: return _result(false,"snapshot_duplicate_peer")
			peers.append(int(pilot.peer_id))
	var holders: Array=[]
	var total_heat: int=0
	for id in CASSETTES:
		var pod: Variant=saved.cassettes[id]
		if not pod is Dictionary or not _exact(pod,["holder","mass_g","energy_mj"]): return _result(false,"snapshot_cassette")
		if not pod.holder is String or pod.holder not in HOLDERS or pod.holder in holders or not _integer(pod.mass_g,2000,2000): return _result(false,"snapshot_occupancy")
		if not _integer(pod.energy_mj,(MIN_MC-AMBIENT_MC)*POD_CAPACITY,(MAX_MC-AMBIENT_MC)*POD_CAPACITY): return _result(false,"snapshot_temperature")
		if pod.holder==BUFFER and not saved.buffer_enabled: return _result(false,"snapshot_closed_buffer")
		if pod.holder in PILOTS and int(saved.pilots[pod.holder].peer_id)==0: return _result(false,"snapshot_orphan_cargo")
		holders.append(pod.holder)
		total_heat+=int(pod.energy_mj)
	if not _integer(saved.service_credit,0,1) or int(saved.jobs_completed)-int(saved.services_consumed)!=int(saved.service_credit): return _result(false,"snapshot_service_balance")
	# Request serials may skip, but every consumption advances them at least one.
	# This rejects unreachable reset counters, not arbitrary edited high serials.
	if (int(saved.services_consumed)==0 and int(saved.service_serial)!=0) or int(saved.service_serial)<int(saved.services_consumed): return _result(false,"snapshot_service_sequence")
	if bool(saved.job_requested)!=(int(saved.service_credit)==0): return _result(false,"snapshot_job_demand")
	if not saved.pending_action is Dictionary: return _result(false,"snapshot_action")
	if not saved.pending_action.is_empty():
		if not _integer(saved.pending_action.get("serial"),int(saved.action_serial),int(saved.action_serial)): return _result(false,"snapshot_action_serial")
		var valid: Dictionary=_validate_action(saved.pending_action,saved,true)
		if not valid.ok: return valid
	if not saved.water is Dictionary: return _result(false,"snapshot_water")
	var checked: Dictionary=_network.validate_snapshot(saved.water)
	if not checked.ok: return _result(false,"snapshot_water:"+str(checked.code))
	if int(saved.water.pending_usec)!=0 or not _integer(saved.pending_usec,0,STEP_USEC-1) or not _integer(saved.flow_credit_usec,0,int(saved.pending_usec)): return _result(false,"snapshot_clock")
	if not _integer(saved.pump_total_ml,0,int(saved.water.tick)*100): return _result(false,"snapshot_pump_budget")
	for edge in saved.water.edges.values():
		if int(edge.open_permille)!=0 or edge.powered: return _result(false,"snapshot_active_controls")
	if not saved.heat_credit is Dictionary or not _exact(saved.heat_credit,CASSETTES): return _result(false,"snapshot_heat_credit")
	for credit in saved.heat_credit.values():
		if not credit is Dictionary or not _exact(credit,["loss","gain"]): return _result(false,"snapshot_heat_credit")
		for key in ["loss","gain"]:
			if not _integer(credit[key],0,int(saved.flow_credit_usec)*2): return _result(false,"snapshot_heat_credit_budget")
		if int(credit.loss)+int(credit.gain)>int(saved.flow_credit_usec)*2: return _result(false,"snapshot_heat_credit_budget")
	if not _integer(saved.water_energy_mj,(MIN_MC-AMBIENT_MC)*WATER_CAPACITY,(MAX_MC-AMBIENT_MC)*WATER_CAPACITY): return _result(false,"snapshot_water_temperature")
	if not saved.thermal_ledger is Dictionary or not _exact(saved.thermal_ledger,["work_added","ability_added","ability_removed","ambient_added","ambient_removed"]): return _result(false,"snapshot_thermal_ledger")
	for value in saved.thermal_ledger.values():
		if not _integer(value,0,MAX_HEAT_LEDGER): return _result(false,"snapshot_heat_counter")
	var ledger: Dictionary=saved.thermal_ledger
	if int(ledger.work_added)!=int(saved.jobs_completed)*WORK_HEAT_MJ: return _result(false,"snapshot_work_heat")
	if int(ledger.ambient_added)+int(ledger.ambient_removed)>int(saved.pump_total_ml)*RADIATOR_MJ_PER_ML: return _result(false,"snapshot_radiator_budget")
	total_heat+=int(saved.water_energy_mj)
	if total_heat!=INITIAL_HEAT_MJ+int(ledger.work_added)+int(ledger.ability_added)-int(ledger.ability_removed)+int(ledger.ambient_added)-int(ledger.ambient_removed): return _result(false,"snapshot_energy_balance")
	return _result(true,"valid")

func restore(saved: Dictionary) -> Dictionary:
	var checked: Dictionary=validate_snapshot(saved)
	if not checked.ok: return checked
	var candidate = Water.new()
	if not candidate.configure(water_definition()).ok or not candidate.restore(saved.water).ok: return _result(false,"restore_water")
	# Every numerical field is integral: normalize the actual JSON boundary.
	_state=_normalize(saved)
	_network=candidate
	_state.water=candidate.snapshot()
	_prepared_service.clear()
	return _result(true,"restored_no_elapsed_time")

func _validate_facts(facts: Dictionary, state: Dictionary) -> Dictionary:
	if not _exact(facts,["powered","valve_open","sweep_clear","contacts"]): return _result(false,"facts_keys")
	for key in ["powered","valve_open","sweep_clear"]:
		if not facts[key] is bool: return _result(false,"facts_type")
	if not facts.contacts is Dictionary or not _exact(facts.contacts,[SOUTH_0,SOUTH_1]): return _result(false,"contacts_keys")
	for berth in [SOUTH_0,SOUTH_1]:
		var id: Variant=facts.contacts[berth]
		if not id is String or (id!="" and (id not in CASSETTES or state.cassettes[id].holder!=berth)): return _result(false,"contact_custody_mismatch")
	return _result(true,"facts_valid")

func _commit(next: Dictionary, code: String) -> Dictionary:
	if int(_state.revision)>=MAX_COUNTER: return _result(false,"counter_limit")
	next.revision=int(_state.revision)+1
	var checked: Dictionary=validate_snapshot(next)
	if not checked.ok: return checked
	_state=next
	return _result(true,code)

func _gate(authority: bool, paused: bool) -> Dictionary:
	if _state.is_empty(): return _result(false,"not_configured")
	if not authority: return _result(false,"authority_required")
	if paused: return _result(false,"paused")
	return _result(true,"allowed")

static func _at(state: Dictionary, holder: String) -> String:
	for id in CASSETTES:
		if state.cassettes[id].holder==holder: return id
	return ""

static func _occupancy(state: Dictionary) -> Dictionary:
	var result: Dictionary={}
	for holder in HOLDERS: result[holder]=_at(state,holder)
	return result

static func _cold(state: Dictionary, id: String) -> bool:
	return int(state.cassettes[id].energy_mj)<=(COLD_MC-AMBIENT_MC)*POD_CAPACITY

static func _free_south(state: Dictionary) -> String:
	for berth in [SOUTH_0,SOUTH_1]:
		if _at(state,berth).is_empty(): return berth
	return ""

static func _cold_south(state: Dictionary) -> String:
	for berth in [SOUTH_0,SOUTH_1]:
		var id: String=_at(state,berth)
		if not id.is_empty() and _cold(state,id): return id
	return ""

static func _empty_heat_credit() -> Dictionary:
	return {CASSETTES[0]:{"loss":0,"gain":0},CASSETTES[1]:{"loss":0,"gain":0}}

static func _action_touches(action: Dictionary, holder: String) -> bool:
	return not action.is_empty() and (action.source==holder or action.destination==holder or action.actor==holder)

static func _exact(value: Dictionary, keys: Array) -> bool:
	if value.size()!=keys.size(): return false
	for key in keys:
		if not value.has(key): return false
	return true

static func _integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=low and float(value)<=high and floor(float(value))==float(value)

static func _normalize(value: Variant) -> Variant:
	if value is Dictionary:
		var out: Dictionary={}
		for key in value: out[key]=_normalize(value[key])
		return out
	if value is Array:
		var out: Array=[]
		for item in value: out.append(_normalize(item))
		return out
	if value is float: return int(value)
	return value

static func _same(a: Variant, b: Variant) -> bool:
	if a is int or a is float or b is int or b is float:
		return _integer(a,-9007199254740991,9007199254740991) and _integer(b,-9007199254740991,9007199254740991) and float(a)==float(b)
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size(): return false
		for key in a:
			if not b.has(key) or not _same(a[key],b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size(): return false
		for i in a.size():
			if not _same(a[i],b[i]): return false
		return true
	return typeof(a)==typeof(b) and a==b

static func _result(ok: bool, code: String) -> Dictionary:
	return {"ok":ok,"code":code}
