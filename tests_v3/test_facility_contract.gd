extends SceneTree
const Contract = preload("res://scripts/v3/network/twin_facility_contract.gd")
var checks := 0
var failures: Array = []

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func _run() -> void:
	var refs: Array = [[1,1,3],[2,4,5],[3,8,13],[4,21,34]]
	check(Contract.valid_refs(refs), "four stable slots accepted")
	check(Contract.ref_for_slot(refs, 3) == {"epoch":8,"serial":13}, "lookup uses identity not array index")
	refs.reverse()
	check(Contract.valid_refs(refs) and Contract.ref_for_slot(refs, 1).serial == 3, "wire order cannot change ownership")
	check(Contract.valid_refs(JSON.parse_string(JSON.stringify(refs))), "lossless JSON numbers remain valid")
	var missing: Array = refs.duplicate(true)
	missing.pop_back()
	check(not Contract.valid_refs(missing), "missing facility cannot reduce readiness requirements")
	var duplicate: Array = refs.duplicate(true)
	duplicate[0][0] = duplicate[1][0]
	check(not Contract.valid_refs(duplicate), "duplicate slot rejected")
	for malformed in [null, {}, [], [[1,1,1]], [1,2,3,4], refs + [[5,1,1]]]:
		check(not Contract.valid_refs(malformed), "bounded complete array required")
	for index in range(3):
		for bad in [null, true, "1", -1, 0, NAN, INF, 1.5, Contract.MAX_COUNTER+1]:
			var malformed: Array = refs.duplicate(true)
			malformed[0][index] = bad
			check(not Contract.valid_refs(malformed), "invalid slot/epoch/serial rejected")
	check(Contract.ref_for_slot(duplicate, 3).is_empty(), "lookup cannot partly accept an invalid table")
	check(Contract.compatible(Contract.VERSION, Contract.fingerprint()), "same manifest handshake accepted")
	check(not Contract.compatible(0, Contract.fingerprint()), "contract version mismatch rejected")
	check(not Contract.compatible(Contract.VERSION, "different-required-facilities"), "same-version different manifest rejected")
	check(not Contract.compatible(Contract.VERSION, null), "absent manifest rejected")
	print("FACILITY_CONTRACT_RESULT " + JSON.stringify({"checks":checks,"failures":failures,"passed":failures.is_empty(),"scope":"pure stable wire contract; no network or gameplay"}))
	quit(0 if failures.is_empty() else 1)
