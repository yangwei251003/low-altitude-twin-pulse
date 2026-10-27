class_name TwinCampaignRuntimeProofs
extends RefCounted
## Pure bridge from original reducer/simulation evidence to one original Store
## transaction. Never advances a module, writes a save, completes Story or pays.
const NUTRIENT_TARGET := "F3:nutrient_delivery_verified"
const NUTRIENT_ACTOR := "F3:nutrient_01"
const NUTRIENT_RECEIVER := "F3:nutrient_receiver"
const NUTRIENT_PROOF := "F3:nutrient_route_proof"
const EVENT_KEYS := ["id","type","actor_id","region_id","target_id","amount","tick","cycle","position","serial","event_id","kind","region"]
const PAYLOAD_TARGET := "I4:evidence_delivery_verified"
const SOURCES := {
	"opening:whale_raw_command_record":{"objective":"I1:whale:record","type":"fact","target":"I1:whale_raw_record","options":["retrieved"]},
	"F2:aligned_timeline":{"objective":"F2:mirror_evidence:light","type":"fact","target":"F2:clock_light_path","options":["manual_mirror","takeover_mirror"]},
	"F3:living_isolation":{"objective":"F3:separate_network:feed","type":"fact","target":"F3:nutrient_delivery_verified","options":["grown_path","existing_bypass"]}}

## world is a COPY of the current original Store.world with its ecology field
## replaced by LivingWorld.persistent_state AFTER that native event batch ends.
## scoped_event = {branch_id: branch captured at native emission, event: exact
## simulation.advance event}. It is an internal host envelope, never peer data.
static func prepare_nutrient(director, world: Dictionary, mechanisms, simulation, scoped_event: Dictionary) -> Dictionary:
	var context: Dictionary = _story_context(director,world,"F3",NUTRIENT_TARGET)
	if not context.ok: return context
	if not _keys(scoped_event,["branch_id","event"]) or scoped_event.branch_id != world.branch_id or not scoped_event.event is Dictionary:
		return _no("event_branch_scope_mismatch")
	var event: Dictionary = scoped_event.event
	if not _keys(event,EVENT_KEYS): return _no("native_event_shape")
	if event.actor_id != NUTRIENT_ACTOR or event.target_id != NUTRIENT_RECEIVER or event.type != "transport_arrival" or event.kind != event.type or event.region != "F3" or event.region_id != event.region or event.id != event.event_id:
		return _no("not_native_nutrient_arrival")
	for key in ["serial","tick"]:
		if not _integer(event[key],1,9007199254740000): return _no("native_event_counter")
	if not _integer(event.cycle,0,9007199254740000) or not _integer(event.amount,1,1) or not _position(event.position): return _no("native_event_value")
	var current: Dictionary = simulation.snapshot()
	var valid: Dictionary = simulation.validate_snapshot(current)
	if not valid.get("ok",false): return _no("source_simulation_invalid:"+str(valid.get("code","")))
	var ecology: Variant = world.get("ecology")
	if not ecology is Dictionary or not ecology.get("simulation") is Dictionary or not ecology.get("facilities") is Dictionary or not _integer(ecology.get("last_event_serial"),0,9007199254740000): return _no("original_ecology_envelope_missing")
	if int(ecology.last_event_serial) != int(current.event_serial) or not _same_value(ecology.simulation,current): return _no("ecology_batch_not_sealed")
	if int(event.serial) > int(current.event_serial) or int(event.tick) != int(current.tick): return _no("stale_or_future_nutrient_event")
	var expected_id := "ecology:%s:%d:%d" % [str(current.content_id),int(current.seed),int(event.serial)]
	if event.id != expected_id: return _no("native_event_identity_mismatch")
	# Ecology emits in sorted actor order. Its current waiting/job_completed
	# actors are exactly this tick's finishers, so derive the exact source serial
	# rather than accepting an arbitrary older counter with a plausible actor.
	var finishers: Array = []
	for id in current.actors:
		var item: Dictionary = current.actors[id]
		if item.phase == "waiting" and item.reason == "job_completed": finishers.append(str(id))
	finishers.sort()
	var order: int = finishers.find(NUTRIENT_ACTOR)
	if order < 0 or int(event.serial) != int(current.event_serial)-finishers.size()+1+order: return _no("native_event_serial_not_this_actor")
	var actor: Variant = current.get("actors",{}).get(NUTRIENT_ACTOR)
	if not actor is Dictionary or actor.region != "F3" or actor.node != "service" or actor.next_node != "" or actor.cargo != false or int(actor.job_index) != 0 or int(actor.cycles) != int(event.cycle)+1 or actor.phase != "waiting" or actor.reason != "job_completed": return _no("arrival_not_current_native_actor_state")
	if not _same_value(actor.position,event.position): return _no("arrival_position_mismatch")
	var definition: Dictionary = simulation.definitions()
	var source_actor: Dictionary = {}
	for item in definition.get("actors",[]):
		if item.get("id") == NUTRIENT_ACTOR: source_actor = item
	if source_actor.is_empty() or source_actor.get("jobs",[]).size() != 2: return _no("nutrient_job_definition_changed")
	if source_actor.jobs[0].get("kind") != "pickup" or source_actor.jobs[1].get("kind") != "deliver" or source_actor.jobs[1].get("target_id") != NUTRIENT_RECEIVER or source_actor.jobs[1].get("node") != actor.node: return _no("nutrient_job_definition_changed")
	var route: String = str(mechanisms.verified_nutrient_route())
	if route not in ["grown_path","existing_bypass"]: return _no("actual_supported_nutrient_route_missing")
	var before: Dictionary = mechanisms.persistent_state()
	valid = mechanisms.validate_state(before)
	if not valid.get("ok",false) or before.get("region_id") != "F3": return _no("mechanism_source_state_invalid")
	var proof := {"version":1,"branch_id":str(world.branch_id),"route":route,"event":event.duplicate(true),
		"ecology_content_id":str(current.content_id),"ecology_routes_digest":str(current.routes_digest),"ecology_seed":int(current.seed),
		"actor_steps_completed":int(actor.steps_completed),"source_event_serial":int(event.serial)}
	var old_proof: Variant = before.get("histories",{}).get(NUTRIENT_PROOF)
	if old_proof != null:
		if not old_proof is Dictionary or old_proof.get("branch_id") != world.branch_id: return _no("stored_nutrient_proof_cross_branch")
		if not _same_value(old_proof,proof): return _no("first_nutrient_proof_already_recorded")
		if before.get("facts",{}).get(NUTRIENT_TARGET) != route: return _no("stored_nutrient_fact_conflict")
		return {"ok":true,"code":"duplicate_native_arrival","changed":false,"duplicate":true,"branch_id":str(world.branch_id),
			"mechanism_state":before,"ecology_state":ecology.duplicate(true),"proof":proof,"fact":{"type":"fact","target_id":NUTRIENT_TARGET,"option":route}}
	if before.get("facts",{}).has(NUTRIENT_TARGET): return _no("nutrient_fact_without_native_proof")
	var candidate: Dictionary = before.duplicate(true)
	candidate.histories[NUTRIENT_PROOF] = proof.duplicate(true)
	candidate.facts[NUTRIENT_TARGET] = route
	candidate.serial = int(candidate.serial)+1
	valid = mechanisms.validate_state(candidate)
	if not valid.get("ok",false): return _no("candidate_mechanism_invalid:"+str(valid.get("code","")))
	return {"ok":true,"code":"native_arrival_prepared","changed":true,"duplicate":false,"branch_id":str(world.branch_id),
		"mechanism_state":candidate,"ecology_state":ecology.duplicate(true),"proof":proof,"fact":{"type":"fact","target_id":NUTRIENT_TARGET,"option":route}}

## Derive actual source payload from the current branch's fully validated
## original action receipts. Personal discoveries are intentionally irrelevant.
static func prepare_payload(director, world: Dictionary) -> Dictionary:
	var context: Dictionary = _story_context(director,world,"I4",PAYLOAD_TARGET)
	if not context.ok: return context
	if not world.get("completed_objectives") is Array: return _no("original_completed_objectives_missing")
	var state: Dictionary = context.state
	var hashes: Dictionary = {}
	var sources: Dictionary = {}
	for key in SOURCES:
		var spec: Dictionary = SOURCES[key]
		if spec.objective not in state.completed or spec.objective not in world.get("completed_objectives",[]): return _no("source_objective_not_committed:"+str(spec.objective))
		var event_id := ""
		var receipt: Dictionary = {}
		for id in state.receipts:
			if state.receipts[id].objective_id != spec.objective: continue
			if not event_id.is_empty(): return _no("duplicate_source_receipt")
			event_id = str(id)
			receipt = state.receipts[id].duplicate(true)
		if event_id.is_empty() or receipt.get("type") != spec.type or receipt.get("target_id") != spec.target or receipt.get("option") not in spec.options: return _no("source_receipt_mismatch:"+str(key))
		# Exact event ID and full validated receipt are retained; no text-only
		# discovery title, invented sample or new authority receipt is substituted.
		var source := {"version":1,"branch_id":str(world.branch_id),"content_id":str(state.content_id),
			"objective_id":str(spec.objective),"event_id":event_id,"receipt":receipt}
		hashes[key] = JSON.stringify(source,"",true,true).sha256_text()
		sources[key] = source
	return {"ok":true,"code":"original_branch_payload_prepared","branch_id":str(world.branch_id),"payload_hashes":hashes,"sources":sources}

static func _story_context(director, world: Dictionary, expected_region: String, target: String) -> Dictionary:
	if not world.get("branch_id") is String or world.branch_id.is_empty() or world.branch_id.length() > 160 or world.branch_id != world.branch_id.strip_edges() or world.branch_id.contains("\n") or world.branch_id.contains("\r") or world.get("region_id") != expected_region: return _no("world_region_or_branch_mismatch")
	var actions: Variant = world.get("actions")
	if not actions is Dictionary: return _no("original_action_state_missing")
	var state: Variant = actions.get("opening")
	if not state is Dictionary: return _no("original_action_state_missing")
	var valid: Dictionary = director.validate_state(state)
	if not valid.get("ok",false): return _no("original_action_state_invalid:"+str(valid.get("code","")))
	var display: Dictionary = director.hud(state,expected_region)
	if display.get("next_region","") not in ["",expected_region]: return _no("goal_in_other_region")
	var eligible := false
	for objective in display.get("objectives",[]):
		for event in objective.get("targets",[]):
			if event.get("type") == "fact" and event.get("target_id") == target: eligible = true
	if not eligible: return _no("proof_target_not_current")
	return {"ok":true,"code":"original_story_context_valid","state":state}

static func _same_value(a, b, depth: int = 0) -> bool:
	if depth > 24: return false
	if (a is int or a is float) and (b is int or b is float): return is_finite(float(a)) and is_finite(float(b)) and float(a) == float(b)
	if typeof(a) != typeof(b): return false
	if a is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not _same_value(a[key],b[key],depth+1): return false
		return true
	if a is Array:
		if a.size() != b.size(): return false
		for index in range(a.size()):
			if not _same_value(a[index],b[index],depth+1): return false
		return true
	return a == b

static func _keys(value, expected: Array) -> bool:
	if not value is Dictionary or value.size() != expected.size(): return false
	for key in expected:
		if not value.has(key): return false
	return true

static func _integer(value, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and float(value) >= float(low) and float(value) <= float(high)

static func _position(value) -> bool:
	if not value is Array or value.size() != 3: return false
	for coordinate in value:
		if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)): return false
	return true

static func _no(code: String) -> Dictionary:
	return {"ok":false,"code":code,"changed":false,"duplicate":false}
