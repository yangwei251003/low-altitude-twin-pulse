extends SceneTree
## Root schedules this lightweight rule smoke test with other engine jobs.
const Encounter = preload("res://scripts/v3/campaign/twin_campaign_encounter.gd")
const Catalog = preload("res://scripts/v3/campaign/twin_campaign_catalog.gd")
const Npc = preload("res://scripts/v3/campaign/twin_campaign_npc_routes.gd")
const Ecology = preload("res://scripts/v3/ecology/twin_ecology_state.gd")
const Director = preload("res://scripts/v3/gameplay/actions/twin_action_director.gd")
const Upgrade = preload("res://scripts/v3/campaign/twin_campaign_state_upgrade.gd")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("CAMPAIGN: " + label)

func _run() -> void:
	_test_catalog()
	_test_state_upgrade()
	_test_npc()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/v3/campaign/bosses.json"))
	for definition in data.bosses: _test_boss(definition)
	print("Campaign rule smoke: %d checks, %d failures. No scene/graphics/playability claim." % [checks, failures])
	quit(0 if failures == 0 else 1)

func _test_catalog() -> void:
	_check(Catalog.extension_paths().size() == 11, "base and expansion order")
	var facts: Dictionary = Catalog.facts()
	_check(facts.has("I2:canal_service_verified"), "real canal fact declared")
	_check(facts.has("F4:chapter_choice"), "ending choice declared")
	_check(Catalog.physical_entities("F2").size() == 3, "F2 source/mirror/receiver entities")
	_check(Catalog.ending({}).is_empty(), "no ending before final choice")
	for option in ["shared_stewardship", "industrial_lifeline", "living_vein"]:
		var result: Dictionary = Catalog.ending({"F4:twin_vein_core:decision":option,"I2:twin_pump_guardian:decision":"clinic_reserve","F2:mirror_evidence:decision":"publish_context","I4:prism_array:decision":"public_caps"})
		_check(result.get("ending_id") == option and result.get("lines", []).size() >= 5, "ending consequences " + option)

func _test_npc() -> void:
	var previous = Ecology.new()
	_check(previous.load_routes().ok, "old ecology config")
	previous.advance(4.0, "I1")
	var merged: Dictionary = Npc.combined_definition(previous.definitions())
	_check(merged.ok, "NPC merge")
	if not merged.ok: return
	var expanded = Ecology.new()
	_check(expanded.configure(merged.definition).ok, "expanded ecology config")
	var migrated: Dictionary = Npc.migrate_snapshot(previous, expanded)
	_check(migrated.ok, "NPC migration validation")
	if not migrated.ok: return
	_check(expanded.restore(migrated.snapshot).ok, "NPC migrated restore")
	_check(expanded.get_actors().size() == 12, "existing actor budget")
	for actor in previous.get_actors():
		_check(expanded.snapshot().actors[actor.id] == previous.snapshot().actors[actor.id], "old actor preserved " + actor.id)
	var got_fact := false
	for _step in range(12):
		var update: Dictionary = expanded.advance(10.0,"F3",{"F3":Npc.region_context("F3",{"F3:signal_isolated":true})})
		for event in update.events:
			var fact: Dictionary = Npc.objective_fact(event,"grown_path")
			if not fact.is_empty():
				got_fact = true
				_check(int(fact.source_serial) > 0, "NPC proof uses real event serial")
	_check(got_fact, "actual pickup then delivery produces F3 fact")
	_check(Npc.objective_fact({"actor_id":"F3:nutrient_01","kind":"transport_arrival","target_id":"F3:nutrient_receiver"}).is_empty(), "missing supported route gives no NPC fact")

func _test_state_upgrade() -> void:
	var old = Director.new()
	var index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Catalog.INDEX_PATH))
	_check(old.load_definitions(Director.DEFAULT_PATH,index.base_extension_paths).ok,"old actions load")
	var current = Director.new()
	var loaded: Dictionary = current.load_definitions(Director.DEFAULT_PATH,Catalog.extension_paths())
	_check(loaded.ok,"new actions load with Root eight-region validation")
	if not loaded.ok: return
	var saved: Dictionary = old.default_state()
	for index_value in range(2):
		var objective: Dictionary = old.definitions().actions[0].objectives[index_value]
		var event: Dictionary = objective.events[0]
		var result: Dictionary = old.apply_event(saved,{"id":"upgrade-fixture:"+str(index_value),"type":event.type,"target_id":event.target_id,"option":event.options[0]}, {"is_authority":true,"validated":true,"region_id":"I1"})
		_check(result.ok,"old receipt fixture")
		saved = result.state
	var before: String = JSON.stringify(saved,"",true,true)
	var upgraded: Dictionary = Upgrade.prepare(old,current,saved)
	_check(upgraded.ok and upgraded.migrated,"old action receipt upgrade")
	_check(JSON.stringify(saved,"",true,true) == before,"upgrade does not mutate old save")
	if upgraded.ok:
		_check(current.validate_state(upgraded.state).ok,"upgraded new state integrity")
		_check(upgraded.state.completed == saved.completed and upgraded.state.receipts == saved.receipts,"old exact receipts retained")
		_check(not Upgrade.prepare(old,current,upgraded.state).migrated,"upgrade idempotent")
	var bad: Dictionary = saved.duplicate(true)
	bad.revision = int(bad.revision)+1
	_check(not Upgrade.prepare(old,current,bad).ok,"bad old save refused")

func _test_boss(spec: Dictionary) -> void:
	_test_store_shapes(spec)
	var rules = Encounter.new()
	var id: String = str(spec.id)
	_check(rules.configure(id).ok, id + " configure")
	_check(rules.bind_actors({"player:1":{"position":Vector3(0,10,0),"active":true}}).ok, id + " bind host actor")
	_check(rules.start(Vector3(0,10,0)).ok, id + " start")
	_check(rules.validate_snapshot(rules.snapshot()).ok, id + " initial valid")
	var before: Dictionary = rules.snapshot()
	rules.advance(1.0,true)
	_check(rules.snapshot() == before, id + " pause no change")
	_check(not rules.advance(.1,false,false).ok and rules.snapshot() == before, id + " client advance rejected")
	_check(not rules.observe_environment(spec.environment_defaults,{"is_authority":true}).ok, id + " no unverified environment")
	_check(not rules.hit_part("core",1000,"player:1",1,{"is_authority":true,"hit_confirmed":true,"line_of_sight":true}).ok, id + " shielded core")
	# Let the full first warning play, then test a real fixed locked shape.
	for _step in range(40):
		if rules.get_state().attack_stage == "active": break
		rules.advance(.1)
	var state: Dictionary = rules.get_state()
	var shape: Dictionary = state.attack.shapes[0]
	var point: Array = shape.centre_mm.duplicate()
	point[1] = (int(shape.y_min_mm)+int(shape.y_max_mm)) >> 1
	if shape.kind == "ring": point[0] += (int(shape.inner_mm)+int(shape.outer_mm)) >> 1
	rules.bind_actors({"player:1":{"position":Vector3(float(point[0])/1000.0,float(point[1])/1000.0,float(point[2])/1000.0),"active":true}})
	var hit_context := {"is_authority":true,"physical_hit":true,"line_of_sight":true}
	_check(rules.claim_attack_hit(str(state.attack.token),"player:1",hit_context).ok, id + " host shape damage claim")
	_check(not rules.claim_attack_hit(str(state.attack.token),"player:1",hit_context).ok, id + " one hit per attack actor")
	var damage_context := {"is_authority":true,"hit_confirmed":true,"line_of_sight":true}
	var sequence := 10
	var saw_second_phase := false
	for _step in range(900):
		state = rules.get_state()
		if state.completed: break
		var part: String = rules.current_part()
		var sample: Dictionary = spec.environment_defaults.duplicate(true)
		for key in sample:
			if sample[key] is bool: sample[key] = true
		if sample.has("water_level_mm"): sample.water_level_mm = 1000 if part == "low_pump" else 4000
		if sample.has("radiator_temperature_milli_c"): sample.radiator_temperature_milli_c = 20000
		_check(rules.observe_environment(sample,{"is_authority":true,"physical_sample":true}).ok, id + " physical sample")
		if rules.part_open(part):
			var result: Dictionary = rules.hit_part(part,50000,"player:1",sequence,damage_context)
			sequence += 1
			if result.ok:
				_check(not rules.hit_part(part,50000,"player:1",sequence-1,damage_context).ok, id + " replay rejected")
		if int(rules.get_state().phase) == 2: saw_second_phase = true
		var saved: Dictionary = JSON.parse_string(JSON.stringify(rules.snapshot()))
		_check(rules.validate_snapshot(saved).ok, id + " JSON-safe mid-attempt")
		if failures > 20: return
		rules.advance(.1)
	state = rules.get_state()
	_check(saw_second_phase, id + " compulsory half phase")
	_check(state.completed and int(state.core_hp_milli) == 0, id + " complete through parts and core")
	_check(rules.validate_snapshot(rules.snapshot()).ok, id + " defeated valid")
	var clone = Encounter.new()
	clone.configure(id)
	_check(clone.restore(JSON.parse_string(JSON.stringify(rules.snapshot()))).ok, id + " JSON restore")
	_check(not rules.reset_attempt().ok, id + " no completed retry reward loop")

func _test_store_shapes(spec: Dictionary) -> void:
	var rules = Encounter.new()
	var configured: Dictionary = rules.configure(str(spec.id))
	_check(configured.ok,str(spec.id)+" Store fixture configure")
	if not configured.ok: return
	var bound: Dictionary = rules.bind_actors({"player:1":{"position":Vector3(0,10,0),"active":true}})
	_check(bound.ok,str(spec.id)+" Store fixture host actor")
	if not bound.ok: return
	var started: Dictionary = rules.start(Vector3(0,10,0))
	_check(started.ok,str(spec.id)+" Store fixture starts ordinary encounter")
	if not started.ok: return
	var store = Store.new()
	var seen: Dictionary = {}
	# Advance ordinary warnings/attacks/recovery through every authored pattern.
	# Feed the actual untouched attack snapshot directly to the original Store;
	# a JSON roundtrip would hide StringName keys and is deliberately absent.
	for _step in range(400):
		var state: Dictionary = rules.snapshot()
		var index_value: int = int(state.state.pattern_index)
		if not seen.has(index_value):
			seen[index_value] = true
			_check(store._tree_valid(state),str(spec.id)+" original Store accepts actual "+str(spec.patterns[index_value].shape)+" attack")
		if seen.size() == spec.patterns.size(): break
		rules.advance(.1)
	_check(seen.size() == spec.patterns.size(),str(spec.id)+" native pattern cycle covered for Store boundary")
