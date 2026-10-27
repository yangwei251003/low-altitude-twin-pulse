extends SceneTree
## Structural projections plus pinned REAL Canal physics envelopes. No scenes,
## old facilities, played story, rewards or whole-profile validity are claimed.
const Ledger = preload("res://scripts/v3/gameplay/twin_i2_result_ledger.gd")
const SOURCE := "res://tests_v3/candidates/canal_session/evidence/service_20261020_230122_2e6a2e/result.json"
const SHA := "95c7e7e1482bbbd6adc977c10152675c118a4f10bf93211be01ffbba41e848a1"
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _run() -> void:
	_check(FileAccess.get_sha256(SOURCE)==SHA,"pinned successful physical service source")
	var evidence: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
	var idle: Dictionary = evidence.snapshots.phases.transport_idle.source
	var claimed: Dictionary = evidence.snapshots.phases.claimed.source
	var world := {"actions":{"opening":{"completed":[],"choices":{},"flags":{},"discoveries":[]}},"environment":{},"flags":{},"completed_objectives":[]}
	var rules: Dictionary = Ledger.contract()
	for id in rules: _complete(world,str(id),str(rules[id].options[0]),rules[id])
	_check(Ledger.validate_world(world).ok,"legacy seven-result contract remains accepted")
	var extension: Dictionary = Ledger.campaign_contract()
	_complete(world,"I2:canal_service:brief","brief",extension["I2:canal_service:brief"])
	_check(not Ledger.validate_world(world).ok,"new briefing cannot restore without its original physical envelope")
	world.environment["I2_canal"] = idle.duplicate(true)
	_check(Ledger.validate_world(world).ok,"known briefing with actual valid service-site snapshot")
	_complete(world,"I2:canal_service:exchange","low_route",extension["I2:canal_service:exchange"])
	_check(Ledger.validate_world(world).ok,"original ten-receipt transport history binds exchange")
	var bad: Dictionary = world.duplicate(true)
	bad.actions.opening.choices["I2:canal_service:exchange"] = "local_cooling"
	_check(not Ledger.validate_world(bad).ok,"transport-only source cannot pretend to be thermal preparation")
	bad = world.duplicate(true)
	bad.environment.I2_canal.executor.fields._receipt_count = 0
	_check(not Ledger.validate_world(bad).ok,"missing original receipts cannot bind transport exchange")
	_complete(world,"I2:canal_service:service","repaired",extension["I2:canal_service:service"])
	_check(not Ledger.validate_world(world).ok,"unconsumed physical service cannot restore a claimed Story result")
	world.environment.I2_canal = claimed.duplicate(true)
	_check(Ledger.validate_world(world).ok,"same original consumed service validates its exact Story result")
	_complete(world,"I2:canal_service:order","record",extension["I2:canal_service:order"])
	_check(Ledger.validate_world(world).ok,"recorded work order keeps original consumed physics required")
	bad = world.duplicate(true)
	bad.actions.opening.completed.append("I2:unknown_campaign_goal")
	bad.completed_objectives.append("I2:unknown_campaign_goal")
	_check(not Ledger.validate_world(bad).ok,"unknown I2 objectives still fail closed")
	bad = world.duplicate(true)
	bad.flags["I2:unknown_campaign_flag"] = true
	_check(not Ledger.validate_world(bad).ok,"unknown I2 flags still fail closed")
	bad = world.duplicate(true)
	bad.actions.opening.discoveries.append("I2:unknown_campaign_finding")
	_check(not Ledger.validate_world(bad).ok,"unknown I2 discoveries still fail closed")
	bad = world.duplicate(true)
	bad.flags["I2:region_route_open"] = true
	_check(not Ledger.validate_world(bad).ok,"route cannot precede actual chapter decision")
	_complete(world,"I2:twin_pump_guardian:plan","plan",extension["I2:twin_pump_guardian:plan"])
	_check(not Ledger.validate_world(world).ok,"guardian plan cannot restore without its original combat-water envelope")
	var pump = Ledger.Pump.new()
	pump.network.configure(Ledger.Pump.definition())
	world.environment["campaign_I2"] = {"version":1,"observed":false,"encounter":{},"mechanisms":{"schema_version":1,"region_id":"I2","serial":0,"simulation":pump.network.snapshot(),"readings":{},"methods":{}}}
	_check(Ledger.validate_world(world).ok,"conservative initial water schema binds only the plan fixture")
	bad = world.duplicate(true)
	bad.environment.campaign_I2.mechanisms.simulation.nodes[Ledger.Pump.CIVILIAN].clean_ml -= 1
	_check(not Ledger.validate_world(bad).ok,"civilian reserve corruption cannot restore guardian result")
	_complete(world,"I2:twin_pump_guardian:engage","observed",extension["I2:twin_pump_guardian:engage"])
	_check(not Ledger.validate_world(world).ok,"empty encounter cannot claim an observed attack cycle")
	print("Campaign I2 result binding: %d checks, %d failures; pure projections and pinned original physics only."%[checks,failures])
	quit(0 if failures==0 else 1)

func _complete(world: Dictionary, id: String, option: String, rule: Dictionary) -> void:
	world.actions.opening.completed.append(id)
	world.completed_objectives.append(id)
	world.actions.opening.choices[id] = option
	if not str(rule.flag).is_empty():
		world.flags[str(rule.flag)] = true
		world.actions.opening.flags[str(rule.flag)] = true
	if not str(rule.discovery).is_empty(): world.actions.opening.discoveries.append(str(rule.discovery))
