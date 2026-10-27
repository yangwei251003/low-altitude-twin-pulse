extends SceneTree
## Pure rules. Explicit receipt fixtures are NOT flight, joints, collisions,
## actual work, Store transactions, network or human play evidence.
const Runtime = preload("res://scripts/v3/candidates/canal_service_loop/canal_service_runtime.gd")
var checks: int = 0
var failures: Array[String] = []
var evidence: Dictionary = {"scope":"pure rules; completed physical actions are trusted-executor fixtures"}

func _init() -> void:
	_test_initial_and_time()
	_test_commands_and_thermal_limits()
	_test_in_place_cooling()
	_test_receipts_and_orders()
	_test_occupied_buffer_policy_switch()
	_test_external_custody()
	_test_closed_cooling_and_partition()
	_test_service_transaction()
	_test_restore_rejection()
	print("V3_CANAL_SERVICE_RUNTIME_TESTS " + JSON.stringify({"checks":checks,"failures":failures,"evidence":evidence}))
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, label: String, details: Dictionary = {}) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL " + label + " " + JSON.stringify(details))

func _new():
	var state = Runtime.new()
	_check(state.configure().ok, "independent bounded definition configures")
	return state

func _facts(state, enabled: bool = true) -> Dictionary:
	var occupancy: Dictionary = state.status().occupancy
	return {"powered":enabled,"valve_open":enabled,"sweep_clear":enabled,
		"contacts":{Runtime.SOUTH_0:occupancy[Runtime.SOUTH_0],Runtime.SOUTH_1:occupancy[Runtime.SOUTH_1]}}

func _command(state, fields: Dictionary) -> Dictionary:
	var saved: Dictionary = state.snapshot()
	var command: Dictionary = fields.duplicate(true)
	command.serial = int(saved.command_serial) + 1
	command.expected_revision = int(saved.revision)
	return command

func _receipt(action: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in ["serial","kind","actor","cassette_id","source","destination","route","job"]:
		result[key] = action[key]
	result.merge({"path_clear":true,"endpoint_valid":true,"custody_verified":true,"completed":true})
	return result

func _fixture_finish_next(state) -> Dictionary:
	var request: Dictionary = state.request_action(int(state.snapshot().revision))
	if not request.ok or not request.has("action"): return request
	var result: Dictionary = state.confirm_action(_receipt(request.action))
	result.action = request.action
	return result

func _fixture_first_work(state) -> Array:
	var trace: Array = []
	for index in range(24):
		var result: Dictionary = _fixture_finish_next(state)
		if not result.ok or not result.has("action"):
			trace.append({"failure":result})
			break
		trace.append(result.action.duplicate(true))
		if result.action.kind == "work": break
	return trace

func _fixture_handoff(state, actor: String, id: String, source: String, destination: String) -> Dictionary:
	var request: Dictionary = state.request_handoff({"expected_revision":state.snapshot().revision,
		"actor":actor,"cassette_id":id,"source":source,"destination":destination})
	if not request.ok: return request
	return state.confirm_action(_receipt(request.action))

func _physics_independent_equal(a: Dictionary, b: Dictionary) -> bool:
	# Host-call count is revisioned. All simulated clocks/quantities/credit and
	# remaining fields must still match across different call partitions.
	var left: Dictionary = a.duplicate(true)
	var right: Dictionary = b.duplicate(true)
	left.erase("revision")
	right.erase("revision")
	return Runtime._same(left,right)

func _invariants(state, label: String) -> void:
	var saved: Dictionary = state.snapshot()
	var clean: int = 0
	var dirty: int = 0
	var capacity_ok: bool = true
	for definition in Runtime.water_definition().nodes:
		var node: Dictionary = saved.water.nodes[definition.id]
		clean += int(node.clean_ml)
		dirty += int(node.dirty_ml)
		capacity_ok = capacity_ok and int(node.clean_ml) >= 0 and int(node.dirty_ml) >= 0 and int(node.clean_ml) + int(node.dirty_ml) <= int(definition.capacity_ml)
	_check(clean == 7600 and dirty == 400 and capacity_ok, label + ": closed 8 L and both components conserved")
	var ledger: Dictionary = saved.thermal_ledger
	var total: int = int(saved.water_energy_mj)
	var holders: Array = []
	for pod in saved.cassettes.values():
		total += int(pod.energy_mj)
		holders.append(pod.holder)
	_check(holders.size() == 2 and holders[0] != holders[1], label + ": exactly two unique occupied holders")
	_check(total == Runtime.INITIAL_HEAT_MJ + int(ledger.work_added) + int(ledger.ability_added) - int(ledger.ability_removed) + int(ledger.ambient_added) - int(ledger.ambient_removed), label + ": thermal energy ledger closes exactly")
	_check(state.validate_snapshot(saved).ok, label + ": own snapshot validates")

func _test_initial_and_time() -> void:
	var state = _new()
	var initial: Dictionary = state.snapshot()
	_check(initial.cassettes.size() == 2 and state.status().occupancy[Runtime.CARRIER] == Runtime.CASSETTES[0] and state.status().occupancy[Runtime.WORK] == Runtime.CASSETTES[1], "initial cold carrier and hot work cartridge have unique custody")
	_check(state.status().proposal.kind == "move" and state.status().proposal.destination == Runtime.SOUTH_0, "staggered order first frees its single grip at a real empty south berth")
	var exposed: Dictionary = state.status()
	exposed.occupancy.clear()
	exposed.proposal.destination = Runtime.WORK
	var copy: Dictionary = state.snapshot()
	copy.cassettes.clear()
	_check(state.snapshot() == initial, "nested status/snapshot/proposal cannot mutate custody")
	_check(state.step(0,_facts(state)).ok and state.step(5000000,_facts(state),true,true).ok and state.snapshot() == initial, "pause and zero delta preserve all counters, clocks and credit")
	for delta in [-1,5000001,0.5,NAN,INF,"100000",true]:
		_check(not state.step(delta,_facts(state)).ok and state.snapshot() == initial, "invalid delta rejects atomically: " + str(delta))
	_check(not state.step(100000,_facts(state),false).ok and state.snapshot() == initial, "client cannot advance simulation")
	_check(state.step(5000000,_facts(state,false)).ok and state.snapshot().cassettes == initial.cassettes and state.snapshot().pending_action.is_empty() and state.snapshot().carrier_anchor == initial.carrier_anchor, "five seconds never creates pick, move, delivery or work")
	_check(state.snapshot().water.nodes == initial.water.nodes and int(state.snapshot().pump_total_ml) == 0, "closed unpowered loop advances clock without moving fluid")
	var before: Dictionary = state.snapshot()
	var wrong: Dictionary = _facts(state)
	wrong.contacts[Runtime.SOUTH_0] = Runtime.CASSETTES[0]
	_check(not state.step(100000,wrong).ok and state.snapshot() == before, "thermal contact in a different holder is rejected atomically")
	_invariants(state,"initial and paused")

func _test_receipts_and_orders() -> void:
	var state = _new()
	var initial: Dictionary = state.snapshot()
	var request: Dictionary = state.request_action(int(initial.revision))
	_check(request.ok and state.snapshot().cassettes == initial.cassettes and state.snapshot().carrier_anchor == initial.carrier_anchor, "reserving travel is not teleporting or changing custody")
	var pending: Dictionary = state.snapshot()
	_check(state.request_action(int(pending.revision)).ok and state.snapshot() == pending, "repeat request returns the same serial without duplication")
	var receipt: Dictionary = _receipt(request.action)
	for key in ["serial","source","cassette_id","custody_verified","completed"]:
		var bad: Dictionary = receipt.duplicate(true)
		if key == "serial": bad[key] = float(bad[key]) + 0.25
		elif key in ["custody_verified","completed"]: bad[key] = false
		else: bad[key] = "wrong"
		_check(not state.confirm_action(bad).ok and state.snapshot() == pending, "incorrect executor receipt remains atomic: " + key)
	_check(not state.confirm_action(receipt,false).ok and not state.confirm_action(receipt,true,true).ok and not state.report_blocked(int(request.action.serial),true,true).ok and state.snapshot() == pending, "client/paused confirmation and blocked report cannot mutate reservation")
	_check(state.report_blocked(int(request.action.serial)).ok, "blocked motion retains serial and custody")
	var blocked: Dictionary = state.snapshot()
	_check(state.step(5000000,_facts(state,false)).ok and state.snapshot().pending_action == blocked.pending_action and state.snapshot().cassettes == blocked.cassettes, "blockage never becomes timeout delivery")
	_check(not state.abort_action(int(request.action.serial),false).ok, "abort requires proof of original physical configuration")
	var restored = _new()
	var json_state: Variant = JSON.parse_string(JSON.stringify(state.snapshot()))
	_check(json_state is Dictionary and restored.restore(json_state).ok and Runtime._same(restored.snapshot(),state.snapshot()), "JSON restore retains in-flight serial, load, reservation and clock")
	_check(restored.confirm_action(receipt).ok and restored.snapshot().carrier_anchor == Runtime.SOUTH_0, "matching executor receipt may resume after crash restoration")
	var once: Dictionary = restored.snapshot()
	_check(not restored.confirm_action(receipt).ok and restored.snapshot() == once, "duplicate receipt cannot repeat movement")
	for policy in ["staggered","buffered"]:
		var model = _new()
		_check(model.apply_command(_command(model,{"kind":"policy","policy":policy})).ok, policy + ": request uses current revision")
		var trace: Array = _fixture_first_work(model)
		evidence[policy + "_trusted_receipt_trace"] = trace
		_check(int(model.snapshot().jobs_completed) == 1 and int(model.snapshot().service_credit) == 1 and not model.snapshot().job_requested, policy + ": work order requires individual executor fixtures", {"trace":trace})
		var contains_tray: bool = false
		for action in trace:
			if action.get("kind") == "tray": contains_tray = true
		_check(contains_tray == (policy == "buffered"), policy + ": buffer tray is a distinct confirmed transfer")
		_check(int(model.snapshot().thermal_ledger.work_added) == Runtime.WORK_HEAT_MJ, policy + ": confirmed work consumes cooling capacity once")
		_invariants(model,policy + " first work")

func _test_commands_and_thermal_limits() -> void:
	var state = _new()
	var command: Dictionary = _command(state,{"kind":"thermal","cassette_id":Runtime.CASSETTES[0],"delta_mc":25000})
	_check(state.apply_command(command).ok,"host-authorized bounded heat command accepted")
	var before: Dictionary = state.snapshot()
	_check(not state.apply_command(command).ok and state.snapshot() == before,"same committed command serial cannot heat twice")
	command = _command(state,{"kind":"policy","policy":"buffered"})
	command.expected_revision -= 1
	_check(not state.apply_command(command).ok and state.snapshot() == before,"new serial with stale revision cannot overwrite a newer state")
	command = _command(state,{"kind":"thermal","cassette_id":Runtime.CASSETTES[0],"delta_mc":25001})
	_check(not state.apply_command(command).ok and state.snapshot() == before,"over-spec ability amount rejected, not silently accepted")
	command = _command(state,{"kind":"policy","policy":"buffered"})
	command.unknown = true
	_check(not state.apply_command(command).ok and state.snapshot() == before,"extra command fields atomically rejected")
	_check(not state.apply_command(_command(state,{"kind":"policy","policy":"buffered"}),false).ok and not state.apply_command(_command(state,{"kind":"policy","policy":"buffered"}),true,true).ok and state.snapshot() == before,"client and paused authority cannot change policy")
	var all_ok: bool = true
	for index in range(7):
		all_ok = state.apply_command(_command(state,{"kind":"thermal","cassette_id":Runtime.CASSETTES[0],"delta_mc":25000})).ok and all_ok
	_check(all_ok and float(state.status().temperatures_c[Runtime.CASSETTES[0]]) == 200.0 and int(state.snapshot().thermal_ledger.ability_added) == 180000000,"upper temperature clamp records actual energy, not requested excess")
	for index in range(10):
		all_ok = state.apply_command(_command(state,{"kind":"thermal","cassette_id":Runtime.CASSETTES[0],"delta_mc":-25000})).ok and all_ok
	_check(all_ok and float(state.status().temperatures_c[Runtime.CASSETTES[0]]) == -40.0 and int(state.snapshot().thermal_ledger.ability_removed) == 240000000,"lower clamp preserves exact removed-energy ledger")
	_invariants(state,"thermal ability limits")

func _test_in_place_cooling() -> void:
	for policy in ["staggered","buffered"]:
		var state = _new()
		_check(state.apply_command(_command(state,{"kind":"policy","policy":policy})).ok,policy+": policy selected before local cooling")
		_check(state.apply_command(_command(state,{"kind":"thermal","cassette_id":Runtime.CASSETTES[1],"delta_mc":-24999})).ok,policy+": near-threshold cooling is legal")
		_check(state.status().temperatures_c[Runtime.CASSETTES[1]]>45.0 and state.status().proposal.kind!="work",policy+": 45.001 Celsius still cannot work")
		_check(state.apply_command(_command(state,{"kind":"thermal","cassette_id":Runtime.CASSETTES[1],"delta_mc":-1})).ok,policy+": exact 45 Celsius reaches work threshold")
		var before: Dictionary=state.snapshot()
		var proposal: Dictionary=state.status().proposal
		_check(proposal.kind=="work" and proposal.cassette_id==Runtime.CASSETTES[1] and proposal.route=="stationary" and proposal.job==1,policy+": safe WAIT proposes original work cartridge before carrying or opening buffer")
		_check(state.snapshot()==before and before.carrier_anchor==Runtime.WAIT and before.service_credit==0 and before.cassettes[Runtime.CASSETTES[0]].holder==Runtime.CARRIER,policy+": proposal creates no movement, work heat or service")
		var restored = _new()
		_check(restored.restore(JSON.parse_string(JSON.stringify(before))).ok and restored.status().proposal==proposal,policy+": exact JSON restore retains shortcut proposal")
		var request: Dictionary=state.request_action(int(before.revision))
		var pending: Dictionary=state.snapshot()
		_check(request.ok and request.action.kind=="work" and pending.cassettes==before.cassettes and pending.jobs_completed==0,policy+": reservation is not completed work")
		_check(state.step(5000000,_facts(state,false)).ok and state.snapshot().pending_action==pending.pending_action and state.snapshot().service_credit==0,policy+": elapsed time cannot award pending work")
		var receipt: Dictionary=_receipt(request.action)
		_check(state.confirm_action(receipt).ok and state.snapshot().service_credit==1 and state.snapshot().jobs_completed==1 and state.status().temperatures_c[Runtime.CASSETTES[1]]==70.0,policy+": trusted work fixture adds exactly 25 C and one service")
		var once: Dictionary=state.snapshot()
		_check(not state.confirm_action(receipt).ok and state.snapshot()==once,policy+": duplicated work receipt cannot create another service")
		_check(state.status().proposal.kind!="work" and not once.job_requested and once.cassettes[Runtime.CASSETTES[0]].holder==Runtime.CARRIER and once.cassettes[Runtime.CASSETTES[1]].holder==Runtime.WORK,policy+": full service prevents another job and preserves original two holders")
		_invariants(state,policy+" local cooling shortcut")
		evidence[policy+"_in_place_fixture"]={"proposal":proposal,"after_work":state.status()}
		var cleanup: Array=[]
		for index in 12:
			if state.status().proposal.is_empty(): break
			var result: Dictionary=_fixture_finish_next(state)
			_check(result.ok,policy+": post-work cleanup fixture succeeds")
			if not result.ok: break
			cleanup.append(result.action.kind)
		_check(state.status().proposal.is_empty() and "work" not in cleanup and "buffer_enable" not in cleanup and state.snapshot().jobs_completed==1 and state.snapshot().service_credit==1,policy+": completed demand only returns cassettes; no unused buffer cycle or duplicate job")
		_check(state.status().occupancy[Runtime.CARRIER]=="" and state.status().occupancy[Runtime.WORK]=="" and not state.status().occupancy[Runtime.SOUTH_0].is_empty() and not state.status().occupancy[Runtime.SOUTH_1].is_empty(),policy+": cleanup ends with both original cassettes at real south-holder fixtures")
		_invariants(state,policy+" idle after fulfilled demand")
	# Cooling during an active move must not replace that move or reassign cargo.
	var moving = _new()
	var travel: Dictionary=moving.request_action(int(moving.snapshot().revision))
	_check(moving.apply_command(_command(moving,{"kind":"thermal","cassette_id":Runtime.CASSETTES[1],"delta_mc":-25000})).ok,"cooling is independent of the carrier's reserved journey")
	var in_flight: Dictionary=moving.snapshot()
	_check(in_flight.pending_action==travel.action and moving.status().proposal.is_empty() and in_flight.carrier_anchor==Runtime.WAIT,"cold WORK does not interrupt an existing reservation even with last-confirmed WAIT")
	_check(moving.confirm_action(_receipt(travel.action)).ok and moving.snapshot().carrier_anchor==Runtime.SOUTH_0 and moving.status().proposal.kind=="place","away from WAIT keeps the existing safe unload before work priority")
	# Thermal changes after reservation are checked again at completion.
	var reheated = _new()
	_check(reheated.apply_command(_command(reheated,{"kind":"thermal","cassette_id":Runtime.CASSETTES[1],"delta_mc":-25000})).ok,"reheat case first cools original hot cartridge")
	var work_request: Dictionary=reheated.request_action(int(reheated.snapshot().revision))
	_check(reheated.apply_command(_command(reheated,{"kind":"thermal","cassette_id":Runtime.CASSETTES[1],"delta_mc":1})).ok,"pending work may observe an actual thermal change")
	var hot_pending: Dictionary=reheated.snapshot()
	_check(not reheated.confirm_action(_receipt(work_request.action)).ok and reheated.snapshot()==hot_pending,"work heated above threshold refuses completion without losing reservation")
	_check(reheated.apply_command(_command(reheated,{"kind":"thermal","cassette_id":Runtime.CASSETTES[1],"delta_mc":-1})).ok and reheated.confirm_action(_receipt(work_request.action)).ok,"restoring thermal condition permits original matching receipt")
	_invariants(reheated,"reheated reserved work")
	var v2: Dictionary=reheated.snapshot()
	var old: Dictionary=v2.duplicate(true)
	old.algorithm="canal-service-receipts-thermal-v1"
	_check(not reheated.restore(old).ok and reheated.snapshot()==v2,"different scheduler algorithm cannot silently restore as v2")

func _test_occupied_buffer_policy_switch() -> void:
	var state = _new()
	_check(state.apply_command(_command(state,{"kind":"policy","policy":"buffered"})).ok,"mixed order starts buffered")
	var prepared_ok: bool = true
	for index in range(3):
		prepared_ok = _fixture_finish_next(state).ok and prepared_ok
	_check(prepared_ok and state.status().occupancy[Runtime.BUFFER] == Runtime.CASSETTES[0] and state.snapshot().pending_action.is_empty(),"three executor fixtures leave cold cartridge in open north buffer")
	_check(state.apply_command(_command(state,{"kind":"policy","policy":"staggered"})).ok,"no action in flight permits switching carrier strategy with occupied buffer")
	var trace: Array = _fixture_first_work(state)
	var actual_high_tray: bool = false
	var low_carrier_routes: bool = true
	for action in trace:
		if action.get("kind") == "tray":
			actual_high_tray = action.route == "high" and action.source == Runtime.BUFFER and action.destination == Runtime.WORK
		if action.get("actor") == Runtime.CARRIER:
			low_carrier_routes = low_carrier_routes and action.route == "low"
	_check(actual_high_tray and low_carrier_routes and int(state.snapshot().jobs_completed) == 1,"switch drains hot cartridge by low carrier route and completes real high tray transfer",{"trace":trace})
	_check(state.status().occupancy[Runtime.BUFFER] == "" and not state.snapshot().buffer_enabled,"only empty buffer closes after real high tray completion")
	evidence.occupied_buffer_switch_fixture = trace
	_invariants(state,"occupied buffer policy switch")

func _test_external_custody() -> void:
	var state = _new()
	_check(state.apply_command(_command(state,{"kind":"pilot","slot":"pilot_a","peer_id":11,"enabled":true})).ok and state.apply_command(_command(state,{"kind":"pilot","slot":"pilot_b","peer_id":22,"enabled":true})).ok, "two external slots bind distinct peers")
	_check(_fixture_handoff(state,"pilot_a",Runtime.CASSETTES[0],Runtime.CARRIER,"pilot_a").ok and _fixture_handoff(state,"pilot_b",Runtime.CASSETTES[1],Runtime.WORK,"pilot_b").ok, "two 2 kg cartridges may be held by two players")
	var held: Dictionary = state.snapshot()
	_check(not state.apply_command(_command(state,{"kind":"pilot","slot":"pilot_a","peer_id":0,"enabled":false})).ok and state.snapshot() == held, "disconnect cleanup cannot erase a held cartridge owner")
	_check(not state.apply_command(_command(state,{"kind":"pilot","slot":"pilot_b","peer_id":11,"enabled":true})).ok and state.snapshot() == held, "same peer cannot acquire both identity roles")
	_check(not _fixture_handoff(state,"pilot_a",Runtime.CASSETTES[0],"pilot_a","pilot_b").ok and state.snapshot() == held, "occupied destination rejects handoff without stealing")
	var request: Dictionary = state.request_handoff({"expected_revision":held.revision,"actor":"pilot_a","cassette_id":Runtime.CASSETTES[0],"source":"pilot_a","destination":Runtime.SOUTH_0})
	_check(request.ok and state.apply_command(_command(state,{"kind":"pilot","slot":"pilot_a","peer_id":11,"enabled":false})).ok, "disconnect disables peer while preserving in-flight custody")
	var interrupted: Dictionary = state.snapshot()
	_check(not state.confirm_action(_receipt(request.action)).ok and state.snapshot() == interrupted, "offline actor cannot finish its old transfer")
	var restore = _new()
	_check(restore.restore(JSON.parse_string(JSON.stringify(interrupted))).ok and restore.snapshot().pending_action == interrupted.pending_action, "disconnect plus pending transfer remains resumable")
	_check(restore.abort_action(int(request.action.serial),true).ok and _fixture_handoff(restore,"recovery",Runtime.CASSETTES[0],"pilot_a",Runtime.SOUTH_0).ok, "source restoration then verified recovery clears disabled grip")
	_check(restore.apply_command(_command(restore,{"kind":"pilot","slot":"pilot_a","peer_id":0,"enabled":false})).ok and restore.status().occupancy.pilot_b == Runtime.CASSETTES[1], "one peer recovery does not reset other load")
	_invariants(restore,"external recovery")

func _cooled_fixture():
	var state = _new()
	# Six trusted action receipts place cold/hot pods at the south sockets.
	# Their physical truth is explicitly outside this rule test.
	var all_ok: bool = true
	for index in range(6):
		all_ok = _fixture_finish_next(state).ok and all_ok
	_check(all_ok and state.status().occupancy[Runtime.SOUTH_0] == Runtime.CASSETTES[0] and state.status().occupancy[Runtime.SOUTH_1] == Runtime.CASSETTES[1], "cooling fixture preserves rule custody at both sockets")
	return state

func _test_closed_cooling_and_partition() -> void:
	var large = _cooled_fixture()
	var small = _new()
	_check(small.restore(large.snapshot()).ok,"identical start for partition comparison")
	var before: Dictionary = large.snapshot()
	var big_ok: bool = true
	var small_ok: bool = true
	for index in range(2): big_ok = large.step(5000000,_facts(large)).ok and big_ok
	for index in range(100): small_ok = small.step(100000,_facts(small)).ok and small_ok
	_check(big_ok and small_ok and _physics_independent_equal(large.snapshot(),small.snapshot()), "10 s: identical water, energy, credit and clock under 5 s / 100 ms calls")
	_check(int(large.snapshot().pump_total_ml) > 0 and int(large.snapshot().cassettes[Runtime.CASSETTES[1]].energy_mj) < int(before.cassettes[Runtime.CASSETTES[1]].energy_mj), "actual circulating ml cool the hot coupled cartridge")
	_check(int(large.snapshot().thermal_ledger.ambient_removed) <= int(large.snapshot().pump_total_ml) * Runtime.RADIATOR_MJ_PER_ML and float(large.status().water_temperature_c) >= 20.0, "radiator cannot exceed actual flow energy budget or overshoot ambient")
	_invariants(large,"10 s cooling")
	var partial = _cooled_fixture()
	_check(partial.step(37000,_facts(partial)).ok,"partial contact records sub-tick authorization")
	var middle: Dictionary = partial.snapshot()
	var resumed = _new()
	_check(resumed.restore(JSON.parse_string(JSON.stringify(middle))).ok,"restore keeps partial cooling authorization")
	_check(partial.step(63000,_facts(partial,false)).ok and resumed.step(13000,_facts(resumed,false)).ok and resumed.step(50000,_facts(resumed,false)).ok and _physics_independent_equal(partial.snapshot(),resumed.snapshot()), "cut power: only earlier 37 ms credit settles, independent of later subdivision")
	var cutoff: Dictionary = partial.snapshot()
	_check(partial.step(1000000,_facts(partial,false)).ok and partial.snapshot().water.nodes == cutoff.water.nodes and partial.snapshot().cassettes == cutoff.cassettes and partial.snapshot().water_energy_mj == cutoff.water_energy_mj, "settled disconnected loop creates no new flow or cooling")
	var cold = _cooled_fixture()
	_check(cold.apply_command(_command(cold,{"kind":"thermal","cassette_id":Runtime.CASSETTES[0],"delta_mc":-25000})).ok,"authorized reverse heat records exact energy")
	var chilled: int = int(cold.snapshot().cassettes[Runtime.CASSETTES[0]].energy_mj)
	_check(cold.step(100000,_facts(cold)).ok and int(cold.snapshot().cassettes[Runtime.CASSETTES[0]].energy_mj) > chilled, "warmer water transfers heat toward over-cooled cartridge")
	_invariants(cold,"reversed thermal gradient")
	evidence.cooling_10s = {"pump_ml":large.snapshot().pump_total_ml,"temperatures":large.status().temperatures_c,"bath_c":large.status().water_temperature_c}

func _test_service_transaction() -> void:
	var state = _new()
	_fixture_first_work(state)
	var before: Dictionary = state.snapshot()
	var prepared: Dictionary = state.prepare_service(int(before.revision),1)
	_check(prepared.ok and state.snapshot() == before, "prepare is read-only: failed save cannot consume credit")
	var altered: Dictionary = prepared.duplicate(true)
	altered.candidate.service_credit = 1
	_check(not state.adopt_service(altered).ok and state.snapshot() == before, "caller cannot rewrite prepared consumption")
	_check(state.step(1,_facts(state,false)).ok and not state.adopt_service(prepared).ok and int(state.snapshot().service_credit) == 1, "intervening revision rejects stale service without overwriting time")
	prepared = state.prepare_service(int(state.snapshot().revision),1)
	_check(prepared.ok and state.adopt_service(prepared).ok and int(state.snapshot().service_credit) == 0 and int(state.snapshot().services_consumed) == 1 and state.snapshot().job_requested, "matching committed candidate consumes once and requests one work order")
	var once: Dictionary = state.snapshot()
	_check(not state.adopt_service(prepared).ok and not state.prepare_service(int(once.revision),1).ok and state.snapshot() == once, "replayed consumption cannot grant second service")
	var reset_serial: Dictionary = once.duplicate(true)
	reset_serial.service_serial = 0
	_check(not state.restore(reset_serial).ok and state.snapshot() == once,"consumed service cannot restore with its monotonic request serial reset")
	var restored = _new()
	_check(restored.restore(JSON.parse_string(JSON.stringify(once))).ok,"first consumed service restores with its receipt serial")
	var second_work: Array = _fixture_first_work(restored)
	_check(int(restored.snapshot().jobs_completed) == 2 and int(restored.snapshot().service_credit) == 1,"second actual work receipt fixture creates new credit",{"trace":second_work})
	var second_ready: Dictionary = restored.snapshot()
	_check(not restored.prepare_service(int(second_ready.revision),1).ok and restored.snapshot() == second_ready,"new service credit does not make old request serial valid again")
	var second: Dictionary = restored.prepare_service(int(second_ready.revision),2)
	_check(second.ok and restored.adopt_service(second).ok and int(restored.snapshot().services_consumed) == 2,"fresh request serial consumes second credit exactly once")
	var impossible: Dictionary = restored.snapshot()
	impossible.service_serial = 1
	_check(not restored.restore(impossible).ok and int(restored.snapshot().service_serial) == 2,"two consumed services cannot restore with only one serial advancement")
	var fresh = _new()
	var initial: Dictionary = fresh.snapshot()
	var premature: Dictionary = initial.duplicate(true)
	premature.service_serial = 1
	_check(not fresh.restore(premature).ok and fresh.snapshot() == initial,"zero consumed services require untouched service serial")
	_invariants(state,"service consumption")
	_invariants(restored,"second service consumption")

func _test_restore_rejection() -> void:
	var state = _cooled_fixture()
	_check(state.step(47000,_facts(state)).ok,"corruption fixture includes partial credit")
	var saved: Dictionary = state.snapshot()
	var malformed: Array = []
	var changed: Dictionary = saved.duplicate(true)
	changed.extra = true
	malformed.append(changed)
	changed = saved.duplicate(true)
	changed.version = 2
	malformed.append(changed)
	changed = saved.duplicate(true)
	changed.cassettes[Runtime.CASSETTES[1]].holder = changed.cassettes[Runtime.CASSETTES[0]].holder
	malformed.append(changed)
	changed = saved.duplicate(true)
	changed.cassettes[Runtime.CASSETTES[0]].mass_g = 1999
	malformed.append(changed)
	changed = saved.duplicate(true)
	changed.cassettes[Runtime.CASSETTES[0]].energy_mj += 1
	malformed.append(changed)
	changed = saved.duplicate(true)
	changed.water.nodes[Runtime.RESERVOIR].clean_ml += 1
	malformed.append(changed)
	changed = saved.duplicate(true)
	changed.water.definition_digest = "old-layout"
	malformed.append(changed)
	changed = saved.duplicate(true)
	changed.pending_usec = 100000
	malformed.append(changed)
	changed = saved.duplicate(true)
	changed.heat_credit[Runtime.CASSETTES[0]] = {"loss":94000,"gain":94000}
	malformed.append(changed)
	changed = saved.duplicate(true)
	changed.service_credit = 1
	malformed.append(changed)
	changed = saved.duplicate(true)
	changed.revision = NAN
	malformed.append(changed)
	for index in malformed.size():
		_check(not state.restore(malformed[index]).ok and state.snapshot() == saved, "malformed restore remains atomic: " + str(index))
	var restored = _new()
	_check(restored.restore(JSON.parse_string(JSON.stringify(saved))).ok and Runtime._same(restored.snapshot(),saved), "full JSON restore exact; no offline time")
	evidence.snapshot_bytes = JSON.stringify(saved).to_utf8_buffer().size()
