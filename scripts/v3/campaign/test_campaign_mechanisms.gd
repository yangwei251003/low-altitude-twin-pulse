extends SceneTree
## Root schedules this actual PhysicsServer ray/thermal fixture. Not a game playtest.
const Mechanisms = preload("res://scripts/v3/campaign/twin_campaign_mechanisms.gd")
var checks := 0
var failures := 0

class FixtureWorld:
	extends Node3D
	var region_id := "F2"
	var objects: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("MECHANISMS: " + label)

func _box(parent: FixtureWorld, id: String, at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = 1
	body.set_meta("entity_id",id)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
	parent.objects[id] = body
	return body

func _settle() -> void:
	await physics_frame
	await physics_frame

func _run() -> void:
	await _test_mirror()
	await _test_heat()
	print("Campaign mechanisms: %d checks, %d failures. Actual ray fixture; no campaign playability claim." % [checks,failures])
	quit(0 if failures == 0 else 1)

func _test_mirror() -> void:
	var test_world := FixtureWorld.new()
	root.add_child(test_world)
	var source := _box(test_world,"F2:clock_source",Vector3(-10,8,0),Vector3(.4,.4,.4))
	var mirror := _box(test_world,"F2:clock_mirror",Vector3(21,8,0),Vector3(.15,4,4))
	var receiver := _box(test_world,"F2:clock_receiver",Vector3(21,8,15),Vector3(4,4,.5))
	# Match native MAIN: devices on layer 8, terrain obstruction on layer 1.
	source.collision_layer = 8
	mirror.collision_layer = 8
	receiver.collision_layer = 8
	var rules = Mechanisms.new()
	_check(rules.configure(test_world).ok,"configure F2")
	var entities := {"F2:clock_source":{"light_level":1.0}}
	var players := {1:{"position":Vector3(-12,3,10),"active":true}}
	await _settle()
	rules.advance(.1,entities,players)
	_check(rules.fact("F2:clock_light_path").is_empty(),"unaligned actual mirror gives no fact")
	_check(rules.observe_interaction(1,"F2:record_low").ok,"real near first original reading")
	_check(rules.fact("F2:paired_records").is_empty(),"one original is insufficient")
	_check(not rules.observe_interaction(1,"F2:record_high").ok,"remote second original rejected")
	players[1].position = Vector3(16,13,-4)
	rules.advance(.1,entities,players)
	_check(rules.observe_interaction(1,"F2:record_high").ok,"real near second original reading")
	_check(rules.fact("F2:paired_records") == "both_read","two actual originals become fact")
	mirror.rotation.y = PI/4.0
	await _settle()
	rules.advance(.1,entities,players)
	_check(rules.view_state().beam_valid,"actual layer-8 +X mirror reflects to layer-8 +Z receiver")
	_check(rules.fact("F2:clock_light_path") == "manual_mirror","two real rays give mirror fact")
	var blocker := _box(test_world,"fixture:blocker",Vector3(21,8,8),Vector3(3,4,1))
	await _settle()
	rules.advance(.1,entities,players)
	_check(not rules.view_state().beam_valid,"actual second segment blocker stops light")
	_check(rules.fact("F2:clock_light_path") == "manual_mirror","historical accepted evidence retained")
	blocker.queue_free()
	await _settle()
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(rules.persistent_state()))
	_check(rules.validate_state(snapshot).ok,"F2 history JSON roundtrip")
	var copy = Mechanisms.new()
	copy.configure(test_world)
	_check(copy.restore(snapshot).ok and copy.fact("F2:paired_records") == "both_read","F2 actual reading history restores")
	_check(copy.boss_environment("F2").is_empty(),"missing actual true body and shadow receiver keep Boss gate closed")
	var reveal := _box(test_world,"F2:reveal_source",Vector3(-8,10,-28),Vector3(.5,.5,.5))
	var core := _box(test_world,"F2:true_body",Vector3(0,10,-28),Vector3(2,2,2))
	var shadow := _box(test_world,"F2:shadow_receiver",Vector3(8,10,-28),Vector3(.5,2,2))
	for device in [reveal,core,shadow]: device.collision_layer = 8
	entities["F2:reveal_source"] = {"light_level":1.0}
	await _settle()
	rules.advance(.1,entities,players)
	_check(rules.boss_environment("F2").true_body_revealed,"layer-8 actual Boss body intercepts reveal ray")
	var cover := _box(test_world,"fixture:reveal_cover",Vector3(-4,10,-28),Vector3(1,3,2))
	await _settle()
	_check(not rules.boss_environment("F2").true_body_revealed,"layer-1 terrain blocks layer-8 Boss reveal")
	cover.queue_free()
	await _settle()
	entities["F2:reveal_source"].light_level = 0.0
	_check(not rules.boss_environment("F2").true_body_revealed,"present but unlit reveal source is insufficient")
	test_world.queue_free()
	await _settle()

func _test_heat() -> void:
	var test_world := FixtureWorld.new()
	test_world.region_id = "I3"
	root.add_child(test_world)
	_box(test_world,"I3:hot_cassette",Vector3(8,8,8),Vector3(.5,.5,.5))
	_box(test_world,"I3:cooling_sink",Vector3(16,8,8),Vector3(.5,.5,.5))
	var valve := _box(test_world,"I3:cooling_valve",Vector3(12,8,8),Vector3(.5,.5,.5))
	valve.rotation.y = PI/2.0
	await _settle()
	var rules = Mechanisms.new()
	_check(rules.configure(test_world).ok,"configure I3")
	var entities := {"I3:hot_cassette":{"temperature":80.0,"heat_capacity_j_per_c":1000.0},"I3:cooling_sink":{"temperature":20.0,"heat_capacity_j_per_c":4000.0},"I3:cooling_valve":{"controlled":true}}
	rules.advance(.5,entities,{})
	_check(entities["I3:hot_cassette"].temperature == 80.0,"controlled flag without real connection transfers no heat")
	_check(rules.fact("I3:thermal_transfer_verified").is_empty(),"UI flag cannot complete thermal task")
	valve.rotation.y = 0.0
	await _settle()
	var total_before: float = 80.0*1000.0+20.0*4000.0
	for _step in range(40): rules.advance(.1,entities,{})
	var hot: float = entities["I3:hot_cassette"].temperature
	var cold: float = entities["I3:cooling_sink"].temperature
	_check(absf(hot*1000.0+cold*4000.0-total_before) < .00001,"actual two entity energy conserved")
	_check(hot <= 35.0 and cold > 20.0,"hot source actually cools and sink actually heats")
	_check(rules.fact("I3:thermal_transfer_verified") == "manual_sink","real conserved transfer gives thermal fact")
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(rules.persistent_state()))
	_check(rules.validate_state(snapshot).ok,"thermal history JSON roundtrip")
	var bad: Dictionary = snapshot.duplicate(true)
	bad.thermal.sink_gain_j += 1
	_check(not rules.validate_state(bad).ok,"nonconserving thermal save refused")
	_check(rules.boss_environment("I3").is_empty(),"puzzle cooling cannot pretend to be Boss radiator and speed")
	var client = Mechanisms.new()
	client.configure(test_world,{},false)
	_check(not client.advance(.1,entities,{}).ok,"client cannot advance mechanisms")
	test_world.queue_free()
	await _settle()
