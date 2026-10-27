extends RefCounted
## Integrates authored later encounters with actual bodies, original damage,
## original Story and original Store. No client may supply a physical fact.
const Encounter = preload("res://scripts/v3/campaign/twin_campaign_encounter.gd")
const Layout = preload("res://scripts/v3/campaign/twin_campaign_layout.gd")
const Catalog = preload("res://scripts/v3/campaign/twin_campaign_catalog.gd")
const Proofs = preload("res://scripts/v3/campaign/twin_campaign_runtime_proofs.gd")
const PumpMechanisms = preload("res://scripts/v3/gameplay/twin_pump_guardian_mechanisms.gd")
const MechanismView = preload("res://scripts/v3/world/twin_campaign_mechanism_view.gd")
const OPERATIONS := {
	"I2:guardian_direction_valve":{"angle":true},
	"I2:guardian_isolation_plug":{"closed":Vector3(-10,4.72,-25),"open":Vector3(-8.4,4.72,-25)},
	"I3:cooling_valve":{"angle":true},"F3:signal_hold":{"angle":true},"F4:test_hold":{"angle":true},
	"F3:signal_breaker":{"closed":Vector3(12,7,6),"open":Vector3(12,7,9)},
	"I4:defence_breaker":{"closed":Vector3(14,5.2,-3),"open":Vector3(14,5.2,-.5)},
	"F4:limited_bus":{"closed":Vector3(-12,9,8),"open":Vector3(-12,9,6)},
	"F4:core_charge_breaker":{"closed":Vector3(-5,14,-27),"open":Vector3(-5,14,-24.5)}}
var session
var encounter: RefCounted
var definition: Dictionary = {}
var mechanisms: RefCounted
var observed := false
var _saw_warning := false
var _saw_active := false
var _sequences: Dictionary = {}
var _remote_state: Dictionary = {}
var _serial := 0
var _applied_serial := -1
var _publish_clock := 0.0
var error := ""
var last_operation_blockers: Array = []
var _ecology_events: Array = []
var epoch := 0
var _expected_epoch := -1
var _applied_epoch := -1
var _entry_z := INF
var _navigation_facts: Dictionary = {}
var _paired_record_reads: Array = [] # Guest navigation only; never physical proof.

func setup(owner_session) -> void:
	session = owner_session

func clear() -> void:
	encounter = null
	mechanisms = null
	definition.clear()
	_remote_state.clear()
	observed = false
	_saw_warning = false
	_saw_active = false
	_sequences.clear()
	_applied_serial = -1
	_expected_epoch = -1
	_applied_epoch = -1
	error = ""
	_ecology_events.clear()
	_entry_z = INF
	_navigation_facts.clear()
	_paired_record_reads.clear()

func bind_world() -> bool:
	clear()
	if not is_instance_valid(session.world.campaign_arena): return true
	definition = session.world.campaign_arena.definition.duplicate(true)
	_navigation_facts = Catalog.facts()
	_entry_z = float(Layout.definition(session.region_id).get("boss_arena",{}).get("entry_z",INF))
	# I2 reuses its original waterfront rather than a later-region layout. Its
	# briefing at z=-19 must stay safe; cross the actual approach before combat.
	if session.region_id=="I2": _entry_z=-21.0
	encounter = Encounter.new()
	if not encounter.configure(str(definition.id)).ok: return _fail("boss_definition")
	var script = PumpMechanisms if session.region_id == "I2" else load("res://scripts/v3/campaign/twin_campaign_late_mechanisms.gd")
	if script == null: return _fail("mechanisms_not_available")
	mechanisms = script.new()
	var bodies: Dictionary = session.world.objects.duplicate()
	bodies.merge(session.world.campaign_body_aliases)
	var configured: Dictionary = mechanisms.configure(session.world, bodies, session.network.is_authority())
	if not configured.get("ok", false): return _fail("mechanisms:" + str(configured.get("code", "configure")))
	if not session.network.is_authority(): return true
	epoch += 1
	var saved: Dictionary = session.world_cache.world.get("environment", {}).get(_save_key(), {})
	if saved.is_empty(): return true
	if saved.get("version") != 1 or not saved.get("observed") is bool or not saved.get("encounter") is Dictionary or not saved.get("mechanisms") is Dictionary: return _fail("campaign_save_shape")
	if not mechanisms.restore(saved.mechanisms).get("ok", false): return _fail("campaign_mechanisms_restore")
	if not saved.encounter.is_empty() and not encounter.restore(saved.encounter).get("ok", false): return _fail("campaign_encounter_restore")
	for id in encounter.get_state().get("last_sequences",{}): _sequences[int(str(id))] = int(encounter.get_state().last_sequences[id])
	observed = saved.observed
	if not encounter.get_state().is_empty():
		session.boss_active = not victory_committed()
		session.boss_campaign = session.boss_active
		if encounter.get_state().get("completed", false) and not victory_committed(): session.pending_completion = true
	_sync_view()
	return true

func active() -> bool:
	return encounter != null and not encounter.get_state().is_empty() and not victory_committed()

func supported() -> bool:
	return encounter != null and is_instance_valid(session.world.campaign_arena)

func consume_epoch(value: Variant) -> bool:
	if not supported(): return value == 0
	if not value is int or value < 1: return false
	if session.network.is_authority(): return value == epoch
	if _expected_epoch != value:
		_expected_epoch = value
		_paired_record_reads.clear()
		_applied_serial = -1
	return _applied_epoch == _expected_epoch

func presentation_ready() -> bool:
	return not supported() or session.network.is_authority() or _expected_epoch > 0 and _applied_epoch == _expected_epoch

func owns_target(id: String) -> bool:
	return supported() and session.world.campaign_arena.targets.has(id)

func victory_committed() -> bool:
	return not definition.is_empty() and bool(session.world_cache.world.get("flags", {}).get("campaign_boss:" + str(definition.region_id), false))

func fact(target: String) -> String:
	if not supported(): return ""
	if target == session.region_id + ":boss_observed": return "observed" if observed else ""
	if target == session.region_id + ":boss_defeated": return "committed" if victory_committed() else ""
	return mechanisms.fact(target) if mechanisms != null else ""

func observe_interaction(peer_id: int, id: String, method := "") -> Dictionary:
	if not supported() or not session.network.is_authority() or mechanisms == null: return {"ok":false,"code":"campaign_not_ready"}
	return mechanisms.observe_interaction(peer_id,id,method)

func navigation_target(target: String) -> String:
	var spec: Dictionary = _navigation_catalog().get(target,{})
	for id in spec.get("physical",{}).get("manual_markers",[]):
		if session.region_id == "F2" and not session.network.is_authority():
			if id not in _paired_record_reads: return str(id)
		elif mechanisms == null or not mechanisms.persistent_state().get("readings",{}).has(id): return str(id)
	return str(spec.get("binding",{}).get("navigation_marker_id",""))

func manual_targets() -> Array:
	var result: Array = []
	if not supported(): return result
	for target in session.story.current_targets():
		if target.type != "fact": continue
		var spec: Dictionary = _navigation_catalog().get(str(target.target_id),{})
		for id in spec.get("physical",{}).get("manual_markers",[]):
			if id not in result: result.append(id)
		var navigation := str(spec.get("binding",{}).get("navigation_marker_id",""))
		if navigation.ends_with("choice_terminal") and navigation not in result: result.append(navigation)
	return result

## Authored data is private to this bound World; live readings, support and
## observations remain uncached. A missing catalog is retried, never latched.
func _navigation_catalog() -> Dictionary:
	if _navigation_facts.is_empty(): _navigation_facts = Catalog.facts()
	return _navigation_facts

func read_manual(peer_id: int, id: String, method := "") -> bool:
	if not supported() or id not in manual_targets() and id not in ["F4:industrial_gauge","F4:living_gauge"]: return false
	if id.ends_with("choice_terminal"): return false # Explicit panel handled separately.
	var before: Dictionary = mechanisms.persistent_state()
	var result: Dictionary = observe_interaction(peer_id,id,method)
	if not result.get("ok",false):
		session._note(peer_id,"读数尚未取得："+str(result.get("code","not_ready")))
		return true
	if result.code == "already_read" and before == mechanisms.persistent_state():
		session._note(peer_id,"原始读数已保存。")
		return true
	if not session._commit("campaign-reading:"+id,{}):
		mechanisms.restore(before)
		return true
	session._audio_event("interaction",session.players[peer_id].global_position,str(peer_id))
	session._note(peer_id,"原始读数已记录。")
	return true

func operable_near(peer_id: int, id: String) -> bool:
	return supported() and OPERATIONS.has(id) and session.players.has(peer_id) and session.world.objects.has(id) and session.players[peer_id].enabled and session.players[peer_id].global_position.distance_to(session.world.objects[id].global_position) <= 4.5

func operate(peer_id: int, id: String) -> bool:
	last_operation_blockers.clear()
	if not operable_near(peer_id,id) or session.simulation_paused: return false
	var actor: FlightBodyV2 = session.players[peer_id]
	var body: PhysicsBody3D = session.world.objects[id]
	if not session._line_clear(actor.global_position,body.global_position,actor.get_rid(),id): return false
	var shape := body.find_child("*",true,false) as CollisionShape3D
	# Geometry children may precede the shape; select by type rather than name.
	for node in body.get_children():
		if node is CollisionShape3D: shape = node; break
	if shape == null or shape.disabled: return false
	var old_pose: Transform3D = body.global_transform
	var old_entity: Dictionary = session.entities[id].duplicate(true)
	var next := old_pose
	var spec: Dictionary = OPERATIONS[id]
	if spec.get("angle",false):
		var angle := 0.0 if absf(wrapf(body.rotation.y,-PI,PI)) > .4 else PI*.5
		next.basis = Basis(Vector3.UP,angle)
	else:
		next.origin = spec.open if old_pose.origin.distance_to(spec.closed) <= .4 else spec.closed
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape.shape
	query.collision_mask = 1 | 2 | 8
	query.exclude = [body.get_rid()]
	query.margin = .001
	for step in range(1,9):
		query.transform = old_pose.interpolate_with(next,float(step)/8.0)*shape.transform
		var hits: Array[Dictionary] = body.get_world_3d().direct_space_state.intersect_shape(query,4)
		if not hits.is_empty():
			for hit in hits:
				last_operation_blockers.append({"step":step,"collider":str(hit.collider.get_path()),"entity_id":str(hit.collider.get_meta("entity_id",""))})
			session._note(peer_id,"操作范围被挡住了，请让开设备和它的行程。")
			return true
	body.global_transform = next
	session.entities[id].position = next.origin
	session.entities[id].angle = next.basis.get_euler().y
	var old_mechanisms: Dictionary = mechanisms.persistent_state()
	mechanisms.observe_ability(peer_id,id,"manual")
	if not session._commit("campaign-operation:"+id,{}):
		body.global_transform = old_pose
		session.entities[id] = old_entity
		mechanisms.restore(old_mechanisms)
		return true
	session._audio_event("mechanism",next.origin,id)
	session._note(peer_id,"设备已操作；检查实际光路、支撑或仪表反馈。")
	return true

func advance(delta: float) -> void:
	if not supported() or not session.owns_world or not session.network.is_authority(): return
	if mechanisms != null:
		_prepare_evidence_payload()
		var result: Dictionary = mechanisms.advance(delta, session.entities, session.players, session.simulation_paused)
		if not result.get("ok", false):
			error = str(result.get("code", "mechanism_step"))
			return
		_commit_ecology_proofs()
		if is_instance_valid(session.world.campaign_mechanism_view): session.world.campaign_mechanism_view.apply_view(MechanismView.wire(mechanisms.view_state()))
	if session.simulation_paused: return
	_bind_actors()
	if not active() and not victory_committed() and _engagement_allowed():
		for body: FlightBodyV2 in session.players.values():
			if body.enabled and body.global_position.z <= _entry_z and body.global_position.distance_to(session.world.campaign_arena.centre()) <= 16.0:
				var started: Dictionary = encounter.start(session.world.campaign_arena.centre())
				if started.ok:
					session.boss_active = true
					session.boss_campaign = true
					_events(started.events)
				break
	if active():
		var environment: Dictionary = mechanisms.boss_environment(session.region_id) if mechanisms != null else {}
		# Missing physics keeps the relevant weakpoint closed.
		if not environment.is_empty(): encounter.observe_environment(environment,{"is_authority":true,"physical_sample":true})
		var advanced: Dictionary = encounter.advance(delta)
		if advanced.ok: _events(advanced.events)
		_damage_active_attack()
	_sync_view()
	_publish_clock += delta
	if _publish_clock >= .1:
		_publish_clock = 0.0
		publish()

func queue_ecology_event(event: Dictionary, branch_id: String) -> void:
	if not supported() or session.region_id != "F3" or event.get("kind") != "transport_arrival" or event.get("region_id") != "F3": return
	if _ecology_events.size() < 8: _ecology_events.append({"branch_id":branch_id,"event":event.duplicate(true)})

func _commit_ecology_proofs() -> void:
	if session.region_id != "F3" or not session.consensus.current_proposal().is_empty():
		_ecology_events.clear()
		return
	for scoped: Dictionary in _ecology_events:
		var saved_world: Dictionary = session.world_cache.world.duplicate(true)
		saved_world.ecology = session.ecology.persistent_state()
		var prepared: Dictionary = Proofs.prepare_nutrient(session.story.director,saved_world,mechanisms,session.ecology.simulation,scoped)
		if not prepared.get("ok",false) or not prepared.get("changed",false): continue
		var path := "world.environment."+_save_key()
		var envelope: Dictionary = persistent_states()[path].duplicate(true)
		envelope.mechanisms = prepared.mechanism_state
		if session._commit("campaign-nutrient:"+str(scoped.event.event_id),{path:envelope}):
			var adopted: Dictionary = mechanisms.restore(prepared.mechanism_state)
			if not adopted.get("ok",false): error = "committed_nutrient_proof_adoption"
	_ecology_events.clear()

func _prepare_evidence_payload() -> void:
	if session.region_id != "I4" or not session.entities.has("I4:witness_source"): return
	var prepared: Dictionary = Proofs.prepare_payload(session.story.director,session.world_cache.world)
	if prepared.get("ok",false): session.entities["I4:witness_source"]["payload_hashes"] = prepared.payload_hashes.duplicate(true)

func fire(peer_id: int, damage_milli: int = 9000) -> bool:
	if not session.network.is_authority(): return false
	if not active() or not session.players.has(peer_id): return false
	var id: String = str(session.locks.get(peer_id, ""))
	if not owns_target(id):
		session._shot_rejected(peer_id,"target_missing","Tab 锁定当前露出的部件，再按 J / 左键射击。")
		return false
	var body: FlightBodyV2 = session.players[peer_id]
	var at: Vector3 = session.world.campaign_arena.targets[id].global_position
	if not body.enabled or body.global_position.distance_to(at) > 36.0 or not session._line_clear(body.global_position,at,body.get_rid(),id):
		session._shot_rejected(peer_id,"occluded","部件被挡住或超出36米射程，换位置与高度。")
		return false
	_sequences[peer_id] = int(_sequences.get(peer_id,0))+1
	session.stats.shots += 1
	session._beam(body.global_position,at,Color("f4d497"))
	session._audio_event("shot",body.global_position,str(peer_id))
	var hit: Dictionary = encounter.hit_part(session.world.campaign_arena.part_id(id),damage_milli,str(peer_id),int(_sequences[peer_id]),
		{"is_authority":true,"hit_confirmed":true,"line_of_sight":true})
	if hit.ok:
		session._audio_event("hit",at,id)
		_events(hit.events)
	else: session._shot_rejected(peer_id,str(hit.code),"装甲仍关闭：处理场地机关，避开攻击，再打亮起的部件。")
	_sync_view()
	return bool(hit.get("ok", false))

func retry() -> void:
	if not active(): return
	var point: Vector3 = _retry_position()
	var slot := 0
	for peer_id in session.players:
		session._restore_player(int(peer_id),point+Vector3(slot*3,0,0))
		slot += 1
	_bind_actors()
	var reset: Dictionary = encounter.reset_attempt()
	if reset.ok:
		_sequences.clear()
		_events(reset.events)
		session._note_all("首领整场已重试，已保存的调查、机关和居民服务保留。")
	_sync_view()

func player_disabled() -> void:
	if not active(): return
	var anyone := false
	for body: FlightBodyV2 in session.players.values(): anyone = anyone or body.enabled
	if not anyone: retry()

func commit_victory() -> bool:
	if not supported() or not encounter.get_state().get("completed",false): return false
	var id: String = str(definition.id)
	if not session._commit("campaign-boss:"+id,{"world.flags.campaign_boss:"+session.region_id:true},"boss:"+session.region_id+":"+id): return false
	session.pending_completion = false
	session.boss_active = false
	session._audio_event("boss_defeated",session.world.campaign_arena.centre(),id)
	for peer_id in session.locks:
		if owns_target(str(session.locks[peer_id])): session.locks[peer_id] = ""
	session._note_all("首领已停止，胜利与共同发现已保存。靠近战后记录点，继续调查。")
	_sync_view()
	publish()
	return true

func persistent_states() -> Dictionary:
	if not supported() or not session.network.is_authority() or mechanisms == null: return {}
	return {"world.environment."+_save_key():{"version":1,"observed":observed,
		"encounter":encounter.snapshot() if not encounter.get_state().is_empty() else {},"mechanisms":mechanisms.persistent_state()}}

func presentation() -> Dictionary:
	return _remote_state.duplicate(true) if not session.network.is_authority() else (encounter.get_state() if supported() else {})

func publish(peer_id := 0) -> void:
	if not supported() or not session.network.is_authority(): return
	_serial += 1
	if peer_id<=1 and session.network.guests.is_empty(): return
	var event := {"kind":"campaign_state","session_id":session.network.session_id,"region":session.region_id,"epoch":epoch,"serial":_serial,
		"encounter":encounter.snapshot() if not encounter.get_state().is_empty() else {},"observed":observed,"defeated":victory_committed()}
	if session.region_id == "I2": event["pump_state"] = mechanisms.persistent_state()
	event["mechanism_view"] = MechanismView.wire(mechanisms.view_state())
	if session.region_id == "F2":
		var readings: Dictionary = mechanisms.persistent_state().get("readings",{})
		event["paired_record_reads"] = []
		for id in ["F2:record_low","F2:record_high"]:
			if readings.has(id): event["paired_record_reads"].append(id)
	if peer_id > 1: session.network.send_event(peer_id,event)
	else:
		for id in session.network.guests: session.network.send_event(int(id),event)

func receive(event: Dictionary) -> void:
	if not supported() or session.network.mode != "guest" or event.get("kind") != "campaign_state" or event.get("session_id") != session.received_session or event.get("region") != session.region_id: return
	if event.get("epoch") != _expected_epoch or _expected_epoch < 1: return
	if not event.get("serial") is int or int(event.serial) <= _applied_serial or not event.get("encounter") is Dictionary or not event.get("defeated") is bool or not event.get("observed") is bool: return
	if JSON.stringify(event).length() > 16384: return
	if not MechanismView.valid_wire(event.get("mechanism_view")): return
	var reads: Variant = event.get("paired_record_reads",[])
	if session.region_id == "F2":
		if not reads is Array or reads.size() > 2: return
		for id in reads:
			if not id is String or id not in ["F2:record_low","F2:record_high"] or reads.count(id) != 1: return
	if session.region_id == "I2":
		if not event.get("pump_state") is Dictionary or not mechanisms.validate_state(event.pump_state).get("ok",false): return
	if not event.encounter.is_empty() and not encounter.restore(event.encounter).ok: return
	_applied_serial = int(event.serial)
	_applied_epoch = _expected_epoch
	if session.region_id == "F2": _paired_record_reads = reads.duplicate()
	observed = event.observed
	_remote_state = encounter.get_state()
	if session.region_id == "I2": mechanisms.restore(event.pump_state)
	session.boss_active = not _remote_state.is_empty() and not event.defeated
	_sync_view(event.defeated)
	if is_instance_valid(session.world.campaign_mechanism_view): session.world.campaign_mechanism_view.apply_view(event.mechanism_view)

func _bind_actors() -> void:
	var actors: Dictionary = {}
	for id in session.players:
		var body: FlightBodyV2 = session.players[id]
		actors[str(id)] = {"position":body.global_position,"active":body.enabled}
	encounter.bind_actors(actors)

func _engagement_allowed() -> bool:
	var objective: String = session.region_id+":"+str(definition.id)+":plan"
	return objective in session.story.state.get("completed",[])

func _damage_active_attack() -> void:
	var state: Dictionary = encounter.get_state()
	if state.get("attack_stage") != "active": return
	var attack: Dictionary = state.get("attack",{})
	for id in session.players:
		var body: FlightBodyV2 = session.players[id]
		if not body.enabled: continue
		var origin: Vector3 = session.world.campaign_arena.centre()
		if not session._line_clear(origin,body.global_position,body.get_rid(),"",true): continue
		var hit: Dictionary = encounter.claim_attack_hit(str(attack.token),str(id),{"is_authority":true,"line_of_sight":true,"physical_hit":true})
		if hit.ok:
			for event: Dictionary in hit.events:
				body.apply_combat_hit(float(event.damage_milli)/1000.0,(body.global_position-origin).normalized(),body.global_position,"pulse",{"source":str(definition.id)})

func _events(events: Array) -> void:
	for event: Dictionary in events:
		match str(event.kind):
			"telegraph_started":
				_saw_warning = true
				_saw_active = false
				session._audio_event("boss_warning",session.world.campaign_arena.centre(),str(definition.id))
				session._note_all(str(event.counter))
			"attack_active":
				_saw_active = _saw_warning
				session._audio_event("boss_attack",session.world.campaign_arena.centre(),str(definition.id))
			"recovery_started":
				if _saw_warning and _saw_active: observed = true
			"phase_changed", "core_exposed": session._audio_event("boss_phase",session.world.campaign_arena.centre(),str(definition.id))
			"boss_defeated":
				session.pending_completion = true
				commit_victory()

func _sync_view(defeated_override := false) -> void:
	if not supported(): return
	var open: Array = []
	for part in definition.parts + ["core"]:
		if encounter.part_open(str(part)): open.append(str(part))
	session.world.campaign_arena.apply_view(encounter.get_state(),open,defeated_override or victory_committed())

func _retry_position() -> Vector3:
	if session.region_id == "I2": return Vector3(0,6,-16)
	var layout: Dictionary = Layout.definition(session.region_id)
	var p: Array = layout.get("boss_arena",{}).get("retry_position",[-8,4,-26])
	return Vector3(float(p[0]),float(p[1]),float(p[2]))

func _save_key() -> String:
	return "campaign_"+str(definition.get("region_id",""))

func _fail(code: String) -> bool:
	error = code
	return false
