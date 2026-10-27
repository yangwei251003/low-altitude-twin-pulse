extends SceneTree
## Pure prepare APIs over native reducer/ecology receipts plus one actual bridge
## fixture. Root owns engine scheduling. No Store files or game profiles written.
const Proofs = preload("res://scripts/v3/campaign/twin_campaign_runtime_proofs.gd")
const Director = preload("res://scripts/v3/gameplay/actions/twin_action_director.gd")
const Catalog = preload("res://scripts/v3/campaign/twin_campaign_catalog.gd")
const Ecology = preload("res://scripts/v3/ecology/twin_ecology_state.gd")
const Npc = preload("res://scripts/v3/campaign/twin_campaign_npc_routes.gd")
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
		push_error("CAMPAIGN PROOFS: "+label)

func _director():
	var director = Director.new()
	_check(director.load_definitions(Director.DEFAULT_PATH,Catalog.extension_paths()).ok,"full original reducer definitions")
	return director

func _before_objective(director, stop_id: String) -> Dictionary:
	# Scripted logical fixture only, through the real reducer and original
	# definitions. This is not claimed as played Story or physical completion.
	var state: Dictionary = director.default_state()
	for action in director.definitions().actions:
		for objective in action.objectives:
			if objective.id == stop_id: return state
			var matcher: Dictionary = objective.events[0]
			var result: Dictionary = director.apply_event(state,{"id":"proof-fixture:"+str(objective.id),"type":matcher.type,"target_id":matcher.target_id,"option":matcher.options[0]},
				{"is_authority":true,"validated":true,"region_id":action.region_id})
			if not result.get("ok",false):
				_check(false,"fixture receipt replay "+str(objective.id))
				return {}
			state = result.state
	return {}

func _world(state: Dictionary, region: String) -> Dictionary:
	return {"region_id":region,"branch_id":"main","actions":{"opening":state.duplicate(true)},"completed_objectives":state.completed.duplicate()}

func _box(parent: FixtureWorld,id: String,at: Vector3,size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = 8
	body.set_meta("entity_id",id)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	parent.objects[id] = body
	return body

func _run() -> void:
	_test_payload()
	await _test_nutrient()
	print("Campaign runtime proofs: %d checks, %d failures; no profile writes or played-story claim." % [checks,failures])
	quit(0 if failures == 0 else 1)

func _test_payload() -> void:
	var director = _director()
	var state: Dictionary = _before_objective(director,"I4:array_witness:witness")
	_check(not state.is_empty(),"I4 current target fixture")
	if state.is_empty(): return
	var world: Dictionary = _world(state,"I4")
	var before: String = JSON.stringify(world,"",true,true)
	var prepared: Dictionary = Proofs.prepare_payload(director,world)
	_check(prepared.ok and prepared.payload_hashes.size() == 3,"three original receipt hashes prepared")
	_check(JSON.stringify(world,"",true,true) == before,"payload prepare leaves world untouched")
	if not prepared.ok: return
	for key in Proofs.SOURCES:
		var source: Dictionary = prepared.sources[key]
		_check(source.receipt == state.receipts[source.event_id],"exact full source receipt retained "+str(key))
		_check(JSON.stringify(source,"",true,true).sha256_text() == prepared.payload_hashes[key],"hash covers exact scoped receipt "+str(key))
	var repeated: Dictionary = Proofs.prepare_payload(director,JSON.parse_string(JSON.stringify(world)))
	_check(repeated.ok and repeated.payload_hashes == prepared.payload_hashes,"same source JSON roundtrip deterministic")
	var other: Dictionary = world.duplicate(true)
	other.branch_id = "other-branch"
	var branched: Dictionary = Proofs.prepare_payload(director,other)
	_check(branched.ok and branched.payload_hashes != prepared.payload_hashes,"payload identity bound to current branch")
	var bad: Dictionary = world.duplicate(true)
	bad.actions.opening.receipts[prepared.sources["F2:aligned_timeline"].event_id].option = "invented_method"
	_check(not Proofs.prepare_payload(director,bad).ok,"tampered exact receipt refused")
	bad = world.duplicate(true)
	bad.completed_objectives.erase("F3:separate_network:feed")
	_check(not Proofs.prepare_payload(director,bad).ok,"uncommitted source objective refused")
	bad = world.duplicate(true)
	bad.completed_objectives = "F3:separate_network:feed"
	_check(not Proofs.prepare_payload(director,bad).ok,"malformed original completion list refused")
	bad = _world(_before_objective(director,"I4:array_witness:brief"),"I4")
	_check(not Proofs.prepare_payload(director,bad).ok,"payload cannot skip current I4 goals")
	bad = _world(director.default_state(),"I4")
	bad["personal"] = {"discoveries":Proofs.SOURCES.keys()}
	_check(not Proofs.prepare_payload(director,bad).ok,"personal discoveries do not replace branch receipts")

func _test_nutrient() -> void:
	var director = _director()
	var state: Dictionary = _before_objective(director,"F3:separate_network:feed")
	var world: Dictionary = _world(state,"F3")
	var base = Ecology.new()
	base.load_routes()
	var expanded: Dictionary = Npc.combined_definition(base.definitions())
	var simulation = Ecology.new()
	_check(simulation.configure(expanded.definition).ok,"native expanded Ecology")
	var arrival: Dictionary = {}
	for _step in range(180):
		var update: Dictionary = simulation.advance(1.0,"F3",{"F3":Npc.region_context("F3",{"F3:signal_isolated":true})})
		for event in update.events:
			if event.actor_id == "F3:nutrient_01" and event.kind == "transport_arrival": arrival = event.duplicate(true)
		if not arrival.is_empty(): break
	_check(not arrival.is_empty(),"native pickup then actual simulation delivery event")
	if arrival.is_empty(): return
	world["ecology"] = {"simulation":simulation.snapshot(),"facilities":{"coolant":0,"maintenance":{},"deliveries":0},"last_event_serial":int(simulation.snapshot().event_serial)}
	var scene := FixtureWorld.new()
	root.add_child(scene)
	var hold := _box(scene,"F3:signal_hold",Vector3(5,7,6),Vector3(.5,.5,.5))
	hold.rotation.y = PI/2.0
	_box(scene,"F3:signal_breaker",Vector3(12,7,9),Vector3(.5,.5,.5))
	_box(scene,"F3:nutrient_bridge",Vector3(16,8,2),Vector3(3,.4,3))
	_box(scene,"support:west",Vector3(13,7.5,2),Vector3(3,1,3))
	_box(scene,"support:east",Vector3(19,7.5,2),Vector3(3,1,3))
	await physics_frame
	await physics_frame
	var mechanisms = Mechanisms.new()
	mechanisms.configure(scene)
	var entities := {"F3:nutrient_bridge":{"growth":1.0},"F3:signal_hold":{}}
	for _step in range(3): mechanisms.advance(.1,entities,{})
	_check(mechanisms.verified_nutrient_route() == "grown_path","proof uses actual supported physics bridge")
	var scoped := {"branch_id":"main","event":arrival.duplicate(true)}
	var before: String = JSON.stringify(mechanisms.persistent_state(),"",true,true)
	var source_before: String = JSON.stringify(simulation.snapshot(),"",true,true)
	var prepared: Dictionary = Proofs.prepare_nutrient(director,world,mechanisms,simulation,scoped)
	_check(prepared.ok and prepared.changed,"native current arrival prepared")
	_check(JSON.stringify(mechanisms.persistent_state(),"",true,true) == before,"prepare does not mutate real mechanisms")
	_check(JSON.stringify(simulation.snapshot(),"",true,true) == source_before,"prepare does not advance native ecology")
	if prepared.ok:
		_check(prepared.proof.event == arrival,"exact native event retained")
		_check(mechanisms.validate_state(JSON.parse_string(JSON.stringify(prepared.mechanism_state))).ok,"candidate original Store JSON state valid")
		_check(mechanisms.restore(prepared.mechanism_state).ok,"Root can adopt only after original Store commit")
		var duplicate: Dictionary = Proofs.prepare_nutrient(director,world,mechanisms,simulation,scoped)
		_check(duplicate.ok and duplicate.get("duplicate",false) and not duplicate.changed,"same native event deduplicated")
	var wrong: Dictionary = scoped.duplicate(true)
	wrong.branch_id = "other-branch"
	_check(not Proofs.prepare_nutrient(director,world,mechanisms,simulation,wrong).ok,"event from another branch refused")
	wrong = scoped.duplicate(true)
	wrong.event.serial = int(wrong.event.serial)-1
	wrong.event.id = "ecology:%s:%d:%d" % [simulation.snapshot().content_id,int(simulation.snapshot().seed),int(wrong.event.serial)]
	wrong.event.event_id = wrong.event.id
	_check(not Proofs.prepare_nutrient(director,world,mechanisms,simulation,wrong).ok,"wrong native actor serial refused")
	wrong = scoped.duplicate(true)
	wrong.event.position[0] += .1
	_check(not Proofs.prepare_nutrient(director,world,mechanisms,simulation,wrong).ok,"wrong actual arrival position refused")
	var bad_world: Dictionary = world.duplicate(true)
	bad_world.ecology.last_event_serial = int(bad_world.ecology.last_event_serial)-1
	_check(not Proofs.prepare_nutrient(director,bad_world,mechanisms,simulation,scoped).ok,"partial native event batch refused")
	bad_world = world.duplicate(true)
	bad_world.branch_id = "other-branch"
	wrong = scoped.duplicate(true)
	wrong.branch_id = "other-branch"
	_check(not Proofs.prepare_nutrient(director,bad_world,mechanisms,simulation,wrong).ok,"stored first proof cannot cross branches")
	bad_world = _world(_before_objective(director,"F3:separate_network:listen"),"F3")
	bad_world["ecology"] = world.ecology.duplicate(true)
	_check(not Proofs.prepare_nutrient(director,bad_world,mechanisms,simulation,scoped).ok,"proof cannot skip current F3 goals")
	scene.objects["F3:nutrient_bridge"].get_child(0).disabled = true
	await physics_frame
	await physics_frame
	mechanisms.advance(.1,entities,{})
	_check(not Proofs.prepare_nutrient(director,world,mechanisms,simulation,scoped).ok,"current unsupported route refused despite historical goal")
	scene.queue_free()
	await physics_frame
