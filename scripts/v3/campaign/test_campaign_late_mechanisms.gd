extends SceneTree
const Mechanisms = preload("res://scripts/v3/campaign/twin_campaign_late_mechanisms.gd")
var checks := 0
var failures := 0

class FixtureWorld:
	extends Node3D
	var region_id := "F3"
	var objects: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("LATE MECHANISMS: " + label)

func _box(parent: FixtureWorld,id: String,at: Vector3,size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.set_meta("entity_id",id)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	parent.objects[id] = body
	return body

func _settle() -> void:
	await physics_frame
	await physics_frame

func _run() -> void:
	await _signal()
	await _array()
	await _final_links()
	print("Late campaign mechanisms: %d checks, %d failures; physics fixtures, no full campaign claim." % [checks,failures])
	quit(0 if failures == 0 else 1)

func _signal() -> void:
	var scene := FixtureWorld.new()
	root.add_child(scene)
	var hold := _box(scene,"F3:signal_hold",Vector3(5,7,6),Vector3(.5,.5,.5))
	hold.rotation.y = PI/2.0
	_box(scene,"F3:signal_breaker",Vector3(12,7,9),Vector3(.5,.5,.5))
	var bridge := _box(scene,"F3:nutrient_bridge",Vector3(16,8,2),Vector3(.4,.4,3))
	_box(scene,"support:west",Vector3(13,7.5,2),Vector3(3,1,3))
	_box(scene,"support:east",Vector3(19,7.5,2),Vector3(3,1,3))
	await _settle()
	var rules = Mechanisms.new()
	rules.configure(scene)
	var entities := {"F3:signal_hold":{},"F3:nutrient_bridge":{"growth":1.0}}
	for _step in range(4): rules.advance(.1,entities,{})
	_check(rules.fact("F3:signal_isolation_verified").is_empty(),"growth number without actual spanning collision insufficient")
	bridge.get_child(0).shape.size = Vector3(3,.4,3)
	await _settle()
	for _step in range(4): rules.advance(.1,entities,{})
	_check(rules.fact("F3:signal_isolation_verified") == "latched_bypass","actual held opening and supported bridge gives signal fact")
	_check(rules.verified_nutrient_route() == "grown_path","actual nutrient support route")
	_check(rules.boss_environment("F3").signal_isolated and rules.boss_environment("F3").nutrient_connected,"F3 Boss gate uses current mechanism")
	hold.rotation.y = 0.0
	await _settle()
	rules.advance(.1,entities,{})
	_check(not rules.boss_environment("F3").signal_isolated,"release actual hold closes Boss gate")
	_check(rules.validate_state(JSON.parse_string(JSON.stringify(rules.persistent_state()))).ok,"signal history survives later release")
	scene.queue_free()
	await _settle()

func _array() -> void:
	var scene := FixtureWorld.new()
	scene.region_id = "I4"
	root.add_child(scene)
	_box(scene,"I4:witness_source",Vector3(-10,12,4),Vector3(.5,.5,.5))
	_box(scene,"I4:witness_receiver",Vector3(20,12,4),Vector3(.5,.5,.5))
	_box(scene,"I4:defence_platform",Vector3(14,4.2,-3),Vector3(4,.4,4))
	_box(scene,"I4:defence_breaker",Vector3(14,5,-.5),Vector3(.5,.5,.5))
	_box(scene,"I4:civilian_feed",Vector3(-6,6,-3),Vector3(.5,.5,.5))
	_box(scene,"support:platform",Vector3(14,3.5,-3),Vector3(5,1,5))
	await _settle()
	var rules = Mechanisms.new()
	rules.configure(scene)
	var payload := {"opening:whale_raw_command_record":"a".repeat(64),"F2:aligned_timeline":"b".repeat(64),"F3:living_isolation":"c".repeat(64)}
	var entities := {"I4:witness_source":{"light_level":1.0,"payload_hashes":payload},"I4:witness_receiver":{},"I4:civilian_feed":{"charge":35.0,"powered":true},"I4:defence_platform":{}}
	var players := {1:{"active":true,"position":Vector3(20,12,4)}}
	for _step in range(4): rules.advance(.1,entities,players)
	_check(rules.fact("I4:evidence_delivery_verified") == "optical","three hashes transmitted through real channel")
	_check(entities["I4:witness_receiver"].received_hashes == payload,"original receiver stores matching original hashes")
	_check(rules.fact("I4:defence_isolated") == "mechanical_lock","actual stopped supported platform/open breaker/civilian feed")
	for step in range(1,21):
		players[1].position = Vector3(20,12,4).lerp(Vector3(20,5,4),float(step)/20.0)
		rules.advance(.1,entities,players)
	for step in range(1,21):
		players[1].position = Vector3(20,5,4).lerp(Vector3(14,5,-3),float(step)/20.0)
		rules.advance(.1,entities,players)
	_check(rules.fact("I4:storm_route_verified") == "covered_low","continuous sampled low route and supported arrival")
	entities["I4:civilian_feed"].powered = false
	rules.advance(.1,entities,players)
	_check(not rules.boss_environment("I4").defence_isolated,"civilian power loss closes present defence gate")
	_check(rules.validate_state(JSON.parse_string(JSON.stringify(rules.persistent_state()))).ok,"I4 immutable evidence survives present changes")
	scene.queue_free()
	await _settle()

func _final_links() -> void:
	var scene := FixtureWorld.new()
	scene.region_id = "F4"
	root.add_child(scene)
	_box(scene,"F4:limited_bus",Vector3(-12,9,6),Vector3(.5,.5,.5))
	_box(scene,"F4:industrial_load",Vector3(-6,9,6),Vector3(.5,.5,.5))
	_box(scene,"F4:lifeline_bus",Vector3(-12,9,12),Vector3(.5,.5,.5))
	_box(scene,"F4:living_emitter",Vector3(5,12,6),Vector3(.5,.5,.5))
	_box(scene,"F4:living_support",Vector3(14,12,6),Vector3(3,.4,3))
	_box(scene,"support:west",Vector3(11,11.5,6),Vector3(3,1,3))
	_box(scene,"support:east",Vector3(17,11.5,6),Vector3(3,1,3))
	var hold := _box(scene,"F4:test_hold",Vector3(10,16,-5),Vector3(.5,.5,.5))
	hold.rotation.y = PI/2.0
	_box(scene,"F4:industrial_gauge",Vector3(15,16,-5),Vector3(.4,.4,.4))
	_box(scene,"F4:living_gauge",Vector3(21,16,-5),Vector3(.4,.4,.4))
	await _settle()
	var rules = Mechanisms.new()
	rules.configure(scene)
	var entities := {"F4:limited_bus":{"powered":true,"charge":35.0},"F4:industrial_load":{"rated_w":120},"F4:lifeline_bus":{"powered":true,"charge":35.0},"F4:living_emitter":{"light_level":1.0},"F4:living_support":{"growth":1.0},"F4:test_hold":{}}
	var players := {1:{"active":true,"position":Vector3(15,16,-5)}}
	rules.advance(.1,entities,players)
	_check(rules.fact("F4:industrial_link_verified") == "limited_bus","actual inserted bus and real load")
	_check(rules.fact("F4:living_link_verified") == "growth_support","real light and supported living span")
	_check(rules.observe_interaction(1,"F4:industrial_gauge").ok,"first actual load gauge read")
	_check(rules.fact("F4:dual_load_verified").is_empty(),"one side cannot complete dual load")
	hold.rotation.y = 0.0
	await _settle()
	rules.advance(.1,entities,players)
	hold.rotation.y = PI/2.0
	await _settle()
	players[1].position = Vector3(21,16,-5)
	rules.advance(.1,entities,players)
	_check(rules.observe_interaction(1,"F4:living_gauge").ok,"second test living read")
	_check(rules.fact("F4:dual_load_verified").is_empty(),"records across tests cannot mix")
	players[1].position = Vector3(15,16,-5)
	rules.advance(.1,entities,players)
	_check(rules.observe_interaction(1,"F4:industrial_gauge").ok,"same test industrial read")
	_check(rules.fact("F4:dual_load_verified") == "latched_test","matching same test load records")
	players[1].position = Vector3(0,12,-25)
	rules.advance(.1,entities,players)
	for plan in ["shared_stewardship","industrial_lifeline","living_vein"]: rules.observe_interaction(1,"F4:choice_terminal",plan)
	_check(rules.fact("F4:plans_reviewed") == "all_read","three explicit plan views before choice")
	hold.rotation.y = 0.0
	await _settle()
	rules.advance(.1,entities,players)
	hold.rotation.y = PI/2.0
	await _settle()
	rules.advance(.1,entities,players)
	_check(rules.validate_state(JSON.parse_string(JSON.stringify(rules.persistent_state()))).ok,"completed first dual sample survives later new test")
	_check(rules.boss_environment("F4").is_empty(),"missing actual final Boss controls remain closed")
	scene.queue_free()
	await _settle()
