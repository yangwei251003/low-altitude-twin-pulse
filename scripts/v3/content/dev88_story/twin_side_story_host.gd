extends RefCounted
## Original authority alone receives successful native ability callbacks.
## Each stage and reward uses the original environment Gate/_commit.
const Catalog = preload("res://scripts/v3/content/dev88_story/twin_side_story_catalog.gd")
const Legacy = preload("res://scripts/v3/ecology/twin_npc_sidejob_state.gd")
const PATH := "world.side_stories_dev88_v1"
const MAX_ACTIVE := 4
const MAX_COUNTER := 9007199254740000
var session
var labels: Callable
var error := ""
var _completed: Callable
var _completion_serial: Callable
var _offers: Dictionary = {}
var _events: Array = []
var _context := ""
var _positions: Dictionary = {}
var _clock := 0.0
var _view: Node

func setup(owner_session, key_labels: Callable = Callable()) -> bool:
	session = owner_session
	labels = key_labels
	if Catalog.definitions().size() != 15:
		error = "side_story_data_unavailable"
		return false
	return true

func set_combat_source(completed: Callable, completion_serial: Callable) -> void:
	_completed = completed
	_completion_serial = completion_serial

func reset_connection() -> void:
	clear_transient()

func clear_transient() -> void:
	_offers.clear()
	_events.clear()
	_positions.clear()
	_context = ""
	_clock = 0.0
	_view = null

func forget_peer(peer: int) -> void:
	_offers.erase(peer)
	_positions.erase(peer)

func bind_world() -> void:
	clear_transient()
	if not is_instance_valid(session.world): return
	_view = session.world.get_node_or_null("SideStoryContent88")
	if not _authority(): return
	# Restore only previously committed native dock observations. This is a
	# saved physical success pose, never a shortcut toward a pending objective.
	var loaded: Dictionary = _load()
	if not loaded.ok: return
	for id: String in loaded.state.jobs:
		if Catalog.definition(id).get("region","") != session.region_id: continue
		for body_id: String in loaded.state.jobs[id].docks:
			var body: Variant = session.world.objects.get(body_id)
			if not body is RigidBody3D: continue
			var at: Vector3 = Catalog.vector(loaded.state.jobs[id].docks[body_id])
			body.global_position = at
			body.linear_velocity = Vector3.ZERO
			body.angular_velocity = Vector3.ZERO
			if session.entities.has(body_id): session.entities[body_id].position = at

func active_count() -> int:
	if not _authority(): return 0
	var loaded: Dictionary = _load()
	if not loaded.ok: return -1
	var count := 0
	for row: Dictionary in loaded.state.jobs.values():
		if not row.complete: count += 1
	return count

func total_active_count() -> int:
	if not _authority(): return 0
	var foreign: Dictionary = _foreign_count()
	var own: int = active_count()
	return own + int(foreign.active) if foreign.ok and own >= 0 else -1

func block_existing_contact(peer: int, target_id: String) -> bool:
	# Call before the two pre-existing contact handlers. Work already accepted
	# in either system remains playable even when all four shared slots are full.
	if not _host(): return false
	var is_new := false
	for id: String in Legacy.SPECS:
		if Legacy.SPECS[id].npc != target_id: continue
		var old: Dictionary = Legacy.restore(session.world_cache.world.get("npc_sidejobs_v1",{}))
		if not old.ok or old.state.jobs.has(id): return false
		is_new = true
	for region: String in ["F2","I3","F3","I4","F4"]:
		if target_id != region+":field_contact_next": continue
		var previous: Variant = session.world_cache.world.get("field_requests_next_v1",{})
		if previous is Dictionary and previous.get("jobs",{}).has(region): return false
		is_new = true
	if not is_new: return false
	var count: int = total_active_count()
	if count >= 0 and count < MAX_ACTIVE: return false
	session._note(peer,"可选委托共同上限为4条。先交接已有任务，再接新单；已有任务仍可继续。" if count >= 0 else "可选任务记录暂不可确认，新单尚未接下；原进度保留。")
	return true

func interact(peer: int, target_id: String) -> bool:
	var spec: Dictionary = Catalog.contact(target_id)
	if spec.is_empty(): return false
	if not _host() or not error.is_empty() or not _near(peer,spec): return true
	_refresh_context()
	var loaded: Dictionary = _load()
	if not loaded.ok:
		session._note(peer,"短支线记录暂不可读取，原记录已保留。")
		return true
	var id: String = spec.id
	if not loaded.state.jobs.has(id):
		var prerequisite: String = Catalog.prerequisite_text(spec,session.story.state)
		if not prerequisite.is_empty():
			_say(peer,spec,[prerequisite])
			return true
		if _offers.get(peer,"") != id:
			_offers[peer] = id
			var offer: Array = spec.offer.duplicate()
			offer.append("这是可选短支线。逐句结束后，再按{contact}才接单；不接也能继续原主线。")
			_say(peer,spec,offer)
			return true
		_offers.erase(peer)
		_accept(peer,spec)
		return true
	var row: Dictionary = loaded.state.jobs[id]
	if row.complete:
		var lines: Array = Catalog.completion_lines(spec,session.story.state)
		lines.append_array(spec.get("replay",[]))
		_say(peer,spec,lines)
	elif int(row.stage) >= spec.stages.size(): _claim(peer,spec)
	else:
		var stage: Dictionary = spec.stages[int(row.stage)]
		_say(peer,spec,[str(stage.label),_stage_hint(spec,row)])
	return true

func ability_applied(peer: int, intent: Dictionary) -> void:
	# Root calls AFTER the original Rules commit and approved physics execution.
	if not _host() or not error.is_empty() or not session.players.has(peer): return
	_refresh_context()
	var loaded: Dictionary = _load()
	if not loaded.ok: return
	var target: String = str(intent.get("target_id",""))
	var ability: String = str(intent.get("ability",""))
	if target.is_empty() or not session.entities.has(target): return
	for id: String in loaded.state.jobs:
		var spec: Dictionary = Catalog.definition(id)
		var row: Dictionary = loaded.state.jobs[id]
		if spec.region != session.region_id or row.complete or int(row.stage) >= spec.stages.size(): continue
		var stage: Dictionary = spec.stages[int(row.stage)]
		if stage.type != "ability" or target not in stage.get("targets",[]) or ability not in stage.get("abilities",[]): continue
		if stage.has("mode") and str(intent.get("mode","")) != stage.mode: continue
		if _events.size() >= 32: return
		_events.append({"job":id,"stage":int(row.stage),"kind":"ability","peer":peer,"target":target,"ability":ability,
			"mode":str(intent.get("mode","")),"revision":int(session.entities[target].get("revision",0)),"context":_context})

func advance(delta: float) -> void:
	if not is_instance_valid(session.world) or not session.active: return
	if is_instance_valid(_view):
		if _view.has_method("apply_view"): _view.apply_view(session.entities)
		var local_peer: int = session.network.local_id()
		if _view.has_method("set_focus") and session.players.has(local_peer): _view.set_focus(session.players[local_peer].global_position)
	if not _host() or not error.is_empty(): return
	_refresh_context()
	_clock += delta
	if _clock < .10 or session.environment_save_gate.pending(): return
	var sample_delta: float = _clock
	_clock = 0.0
	var previous: Dictionary = _positions.duplicate()
	for peer: Variant in session.players:
		var body: Variant = session.players[peer]
		if is_instance_valid(body): _positions[peer] = body.global_position
	if not _events.is_empty():
		_flush_event()
		return
	var loaded: Dictionary = _load()
	if not loaded.ok: return
	for id: String in loaded.state.jobs:
		var spec: Dictionary = Catalog.definition(id)
		var row: Dictionary = loaded.state.jobs[id]
		if spec.region != session.region_id or row.complete or int(row.stage) >= spec.stages.size(): continue
		var stage: Dictionary = spec.stages[int(row.stage)]
		var proof: Dictionary = {}
		if stage.type == "combat": proof = _combat_proof(stage)
		elif stage.type == "dock": proof = _dock_proof(stage)
		elif stage.type == "route": proof = _route_proof(stage,row,previous,sample_delta)
		if proof.is_empty(): continue
		_events.append({"job":id,"stage":int(row.stage),"kind":str(stage.type),"proof":proof,"context":_context})
		_flush_event()
		return

func completed_rewards() -> Array:
	var result: Array = []
	if not _authority(): return result
	var loaded: Dictionary = _load()
	if not loaded.ok: return result
	for id: String in loaded.state.jobs:
		if loaded.state.jobs[id].complete: result.append(str(Catalog.definition(id).reward_id))
	return result

func display_rows() -> Array:
	var result: Array = []
	if not _authority(): return result
	var loaded: Dictionary = _load()
	if not loaded.ok: return result
	for spec: Dictionary in Catalog.definitions():
		var id: String = spec.id
		var row: Dictionary = loaded.state.jobs.get(id,{})
		var status := "available"
		var hint := "到委托台先听邀约，再次联络才接单。"
		var target_id: String = spec.contact.id
		var position: Array = spec.contact.position.duplicate()
		var prerequisite: String = Catalog.prerequisite_text(spec,session.story.state)
		if not prerequisite.is_empty():
			status = "locked"
			hint = prerequisite
		if not row.is_empty():
			if row.complete:
				status = "complete"
				hint = "已交接，可回访；唯一发现保留。"
			elif int(row.stage) >= spec.stages.size():
				status = "ready"
				hint = "现场步骤已保存，回委托台联络交接。"
			else:
				status = "active"
				hint = _stage_hint(spec,row)
				var current: Dictionary = _stage_target(spec.stages[int(row.stage)],row)
				target_id = str(current.get("target_id",target_id))
				position = current.get("position",position)
		result.append({"id":id,"region":str(spec.region),"title":str(spec.title),"status":status,"hint":_render(hint),
			"position":position.duplicate(),"target_id":target_id,"character_id":str(spec.character_id),"speaker_name":str(spec.speaker_name)})
	return result

func hint_text(region: String) -> String:
	for row: Dictionary in display_rows():
		if row.region == region and row.status in ["active","ready"]: return "短支线 · "+str(row.title)+" · "+str(row.hint)
	return ""

func _accept(peer: int, spec: Dictionary) -> void:
	var context: String = _context
	var operation := func() -> bool:
		if not _host() or context != _context_key() or not _near(peer,spec): return false
		if not Catalog.prerequisite_text(spec,session.story.state).is_empty(): return false
		var loaded: Dictionary = _load()
		if not loaded.ok: return false
		if loaded.state.jobs.has(spec.id): return true
		var count: int = total_active_count()
		if count < 0 or count >= MAX_ACTIVE:
			session._note(peer,"旧委托、巡访和短支线共同最多4条。先交接一条，再来接新单。")
			return true
		var next: Dictionary = loaded.state.duplicate(true)
		next.jobs[spec.id] = {"accepted_by":str(session.identities.get(peer,session.world_cache.profile_id)),"accepted_generation":int(session.world_cache.generation),
			"stage":0,"route_index":0,"complete":false,"proofs":[],"docks":{}}
		if not session._commit("side-story88-accept:"+str(spec.id),{PATH:next}): return false
		var lines: Array = spec.accepted.duplicate()
		lines.append(_stage_hint(spec,next.jobs[spec.id]))
		_say(peer,spec,lines,"task_step")
		return true
	_gate(operation,peer)

func _claim(peer: int, spec: Dictionary) -> void:
	var context: String = _context
	var operation := func() -> bool:
		if not _host() or context != _context_key() or not _near(peer,spec): return false
		var loaded: Dictionary = _load()
		if not loaded.ok or not loaded.state.jobs.has(spec.id): return false
		var next: Dictionary = loaded.state.duplicate(true)
		var row: Dictionary = next.jobs[spec.id]
		if row.complete: return true
		if int(row.stage) != spec.stages.size(): return false
		row.complete = true
		if not session._commit("side-story88-claim:"+str(spec.id),{PATH:next,"world.flags.side_story88:"+str(spec.id):true},str(spec.reward_id)): return false
		_say(peer,spec,Catalog.completion_lines(spec,session.story.state),"task_complete")
		return true
	_gate(operation,peer)

func _flush_event() -> void:
	if _events.is_empty(): return
	var pending: Dictionary = _events[0].duplicate(true)
	var operation := func() -> bool:
		if not _host() or str(pending.context) != _context_key(): return false
		var loaded: Dictionary = _load()
		if not loaded.ok: return false
		if not loaded.state.jobs.has(pending.job): return _discard_event()
		var next: Dictionary = loaded.state.duplicate(true)
		var row: Dictionary = next.jobs[pending.job]
		var spec: Dictionary = Catalog.definition(pending.job)
		if row.complete or int(row.stage) != int(pending.stage) or int(row.stage) >= spec.stages.size(): return _discard_event()
		var stage: Dictionary = spec.stages[int(row.stage)]
		var proof: Dictionary = {}
		if pending.kind == "ability":
			if not _ability_matches(stage,pending): return _discard_event()
			proof = {"key":"ability:%s:%s:r%d" % [str(pending.target),str(pending.ability),int(pending.revision)]}
		elif pending.kind == "combat": proof = _combat_proof(stage)
		elif pending.kind == "dock": proof = _dock_proof(stage)
		elif pending.kind == "route":
			proof = _route_claim(stage,row,pending.proof)
		if proof.is_empty(): return _discard_event()
		if stage.type == "route" and int(row.route_index)+1 < stage.points.size(): row.route_index = int(row.route_index)+1
		else:
			if stage.type == "dock": row.docks[str(stage.body)] = proof.position.duplicate()
			row.proofs.append(str(proof.key))
			row.stage = int(row.stage)+1
			row.route_index = 0
		if not session._commit("side-story88-step:"+str(spec.id)+":"+str(pending.stage),{PATH:next}): return false
		_discard_event()
		var message: String = "现场步骤已保存 · "+str(spec.title)+" · "+_stage_hint(spec,row)
		session._note_all(_render(message))
		if int(row.stage) >= spec.stages.size():
			for peer: Variant in session.players: _say(int(peer),spec,spec.ready,"task_step")
		return true
	_gate(operation)

func _ability_matches(stage: Dictionary, event: Dictionary) -> bool:
	if stage.type != "ability" or event.target not in stage.get("targets",[]) or event.ability not in stage.get("abilities",[]): return false
	if stage.has("mode") and str(event.get("mode","")) != stage.mode: return false
	if not session.entities.has(event.target) or int(session.entities[event.target].get("revision",0)) < int(event.revision): return false
	return _clauses(stage.get("requires",[]))

func _clauses(clauses: Array) -> bool:
	for clause: Dictionary in clauses:
		var target: String = str(clause.target)
		if not session.entities.has(target): return false
		var actual: Variant = session.entities[target].get(str(clause.field))
		if actual == null: return false
		match str(clause.op):
			"eq":
				if actual != clause.value: return false
			"gte":
				if not (actual is int or actual is float) or float(actual) < float(clause.value): return false
			"lte":
				if not (actual is int or actual is float) or float(actual) > float(clause.value): return false
			_: return false
	return true

func _combat_proof(stage: Dictionary) -> Dictionary:
	if stage.get("type") != "combat" or not _completed.is_valid() or not _completion_serial.is_valid(): return {}
	var id: String = str(stage.site_id)
	if _completed.call(id) != true: return {}
	var serial: Variant = _completion_serial.call(id)
	if not _counter(serial) or int(serial) < 1: return {}
	return {"key":"combat:"+id+":"+str(int(serial))}

func _dock_proof(stage: Dictionary) -> Dictionary:
	if stage.get("type") != "dock": return {}
	var body: Variant = session.world.objects.get(str(stage.body))
	if not body is RigidBody3D or not body.is_inside_tree(): return {}
	var at: Vector3 = Catalog.vector(stage.position)
	if body.global_position.distance_to(at) > float(stage.radius) or body.linear_velocity.length() > float(stage.max_speed): return {}
	var native: Variant = PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
	if not native is Transform3D or not native.is_equal_approx(body.global_transform): return {}
	var p: Vector3 = body.global_position
	return {"key":"dock:"+str(stage.body),"position":[p.x,p.y,p.z]}

func _route_proof(stage: Dictionary, row: Dictionary, previous: Dictionary, delta: float) -> Dictionary:
	var index: int = int(row.route_index)
	if index >= stage.points.size(): return {}
	var at: Vector3 = Catalog.vector(stage.points[index])
	for peer: Variant in session.players:
		var body: Variant = session.players[peer]
		if not is_instance_valid(body) or not body.enabled or not previous.has(peer): continue
		var before: Vector3 = previous[peer]
		var now: Vector3 = body.global_position
		if not now.is_finite() or now.distance_to(before) > maxf(.8,delta*18.0): continue
		# Enter a real waypoint under original physics. Starting inside a ring
		# or jumping directly into it does not supply a flight observation.
		if before.distance_to(at) <= float(stage.radius) or now.distance_to(at) > float(stage.radius): continue
		if body.linear_velocity.length() > float(stage.max_speed): continue
		return {"key":"route:"+str(index),"peer":int(peer),"index":index,"position":[now.x,now.y,now.z]}
	return {}

func _route_claim(stage: Dictionary, row: Dictionary, proof: Dictionary) -> Dictionary:
	if int(proof.get("index",-1)) != int(row.route_index): return {}
	var peer: int = int(proof.get("peer",0))
	if not session.players.has(peer) or not session.players[peer].enabled: return {}
	var at: Vector3 = Catalog.vector(stage.points[int(row.route_index)])
	# The proof was made in our Host physics callback, not a network payload.
	# Preserve that real entry while the original save barrier captures the
	# environment; the pilot need not hover motionless waiting for disk I/O.
	if not _point_valid(proof.get("position")) or Catalog.vector(proof.position).distance_to(at) > float(stage.radius): return {}
	return proof

func _stage_target(stage: Dictionary, row: Dictionary) -> Dictionary:
	if stage.type == "route": return {"target_id":"","position":stage.points[int(row.route_index)].duplicate()}
	if stage.type == "dock": return {"target_id":str(stage.body),"position":stage.position.duplicate()}
	if stage.type == "combat": return {"target_id":str(stage.site_id),"position":[24,18,18] if str(stage.site_id).ends_with("service_guard") else [2,4,32]}
	var id: String = str(stage.get("targets",[""])[0])
	var target: Dictionary = session.entities.get(id,{})
	if target.get("position") is Vector3:
		var p: Vector3 = target.position
		return {"target_id":id,"position":[p.x,p.y,p.z]}
	for spec: Dictionary in Catalog.definitions():
		for entity: Dictionary in spec.entities:
			if entity.id == id: return {"target_id":id,"position":entity.position.duplicate()}
	return {"target_id":id}

func _stage_hint(spec: Dictionary, row: Dictionary) -> String:
	if int(row.stage) >= spec.stages.size(): return "回委托台按{contact}交接，确认成功才领取唯一发现。"
	var stage: Dictionary = spec.stages[int(row.stage)]
	var line: String = "%d/%d · %s" % [int(row.stage)+1,spec.stages.size(),str(stage.hint)]
	if stage.type == "route": line += " 当前灯环 %d/%d。" % [int(row.route_index)+1,stage.points.size()]
	return line

func _load() -> Dictionary:
	var raw: Variant = session.world_cache.world.get("side_stories_dev88_v1",{})
	if raw is Dictionary and raw.is_empty(): return {"ok":true,"state":{"schema_version":1,"jobs":{}}}
	if not raw is Dictionary or raw.size() != 2 or raw.get("schema_version") != 1 or not raw.get("jobs") is Dictionary or raw.jobs.size() > 15: return {"ok":false}
	for id: Variant in raw.jobs:
		if not id is String: return {"ok":false}
		var spec: Dictionary = Catalog.definition(id)
		var row: Variant = raw.jobs[id]
		if spec.is_empty() or not row is Dictionary or row.size() != 7 or not row.has_all(["accepted_by","accepted_generation","stage","route_index","complete","proofs","docks"]): return {"ok":false}
		if not row.accepted_by is String or row.accepted_by.is_empty() or row.accepted_by.length() > 200 or not row.complete is bool: return {"ok":false}
		for key: String in ["accepted_generation","stage","route_index"]:
			if not _counter(row[key]): return {"ok":false}
		if int(row.stage) > spec.stages.size() or not row.proofs is Array or row.proofs.size() != int(row.stage) or not row.docks is Dictionary or row.docks.size() > 2: return {"ok":false}
		if row.complete and int(row.stage) != spec.stages.size(): return {"ok":false}
		for proof: Variant in row.proofs:
			if not proof is String or proof.is_empty() or proof.length() > 240: return {"ok":false}
		if int(row.stage) < spec.stages.size() and spec.stages[int(row.stage)].type == "route":
			if int(row.route_index) >= spec.stages[int(row.stage)].points.size(): return {"ok":false}
		elif int(row.route_index) != 0: return {"ok":false}
		for body_id: Variant in row.docks:
			if not body_id is String or not _valid_dock_id(spec,body_id) or not _point_valid(row.docks[body_id]): return {"ok":false}
	return {"ok":true,"state":raw.duplicate(true)}

func _valid_dock_id(spec: Dictionary, id: String) -> bool:
	for stage: Dictionary in spec.stages:
		if stage.type == "dock" and str(stage.body) == id: return true
	return false

func _foreign_count() -> Dictionary:
	var old: Dictionary = Legacy.restore(session.world_cache.world.get("npc_sidejobs_v1",{}))
	if not old.ok: return {"ok":false}
	var count := 0
	for row: Dictionary in old.state.jobs.values():
		if row.status != "complete": count += 1
	var previous: Variant = session.world_cache.world.get("field_requests_next_v1",{})
	if not previous is Dictionary: return {"ok":false}
	if not previous.is_empty():
		if previous.get("schema_version") != 1 or not previous.get("jobs") is Dictionary or previous.jobs.size() > 5: return {"ok":false}
		for row: Variant in previous.jobs.values():
			if not row is Dictionary or not row.get("complete") is bool: return {"ok":false}
			if not row.complete: count += 1
	return {"ok":true,"active":count}

func _gate(operation: Callable, peer: int = 0) -> void:
	if session._canal_action_in_capture:
		if not operation.call() and peer > 0: session._note(peer,"短支线保存未完成，本次尚未确认或发奖。")
		return
	if session.environment_save_gate.pending():
		if peer > 0: session._note(peer,"现场正在保存，稍后再联络；本次尚未接单或交接。")
		return
	session.environment_save_gate.request(operation,func(result: Dictionary):
		if not result.get("ok",false) and peer > 0: session._note(peer,"短支线保存未完成，本次尚未确认或发奖。"))

func _near(peer: int, spec: Dictionary) -> bool:
	if spec.region != session.region_id or not session.players.has(peer): return false
	var body: Variant = session.players[peer]
	if not is_instance_valid(body) or not body.enabled: return false
	var at: Vector3 = Catalog.vector(spec.contact.position)
	return body.global_position.distance_to(at) <= 4.0 and session._line_clear(body.global_position,at,body.get_rid(),str(spec.contact.id))

func _say(peer: int, spec: Dictionary, lines: Array, cue := "interaction") -> void:
	var text: Array = []
	for line: String in lines: text.append(_render(line))
	# Native dialogue owns per-line speech playback. Do not play an extra voice
	# here: the content audio router matches exact displayed text and speaker.
	session.network.send_event(peer,{"kind":"dialogue","character_id":str(spec.character_id),"speaker_name":str(spec.speaker_name),"lines":text})
	session._audio_event(cue,Catalog.vector(spec.contact.position),str(spec.id))

func _render(line: String) -> String:
	var keys: Dictionary = labels.call() if labels.is_valid() else {}
	for token: String in ["contact","ability","brake"]:
		line = line.replace("{"+token+"}",str(keys.get(token,"G" if token == "contact" else ("F" if token == "ability" else "空格"))))
	return line

func _discard_event() -> bool:
	if not _events.is_empty(): _events.pop_front()
	return true

func _authority() -> bool:
	return is_instance_valid(session) and session.active and session.owns_world and session.network.is_authority()

func _host() -> bool:
	return _authority() and not session.simulation_paused and not session.boss_active and not session.pending_completion and session.consensus.current_proposal().is_empty()

func _context_key() -> String:
	return str(session.network.session_id)+":"+str(session.world_cache.world.branch_id)+":"+str(session.region_id)

func _refresh_context() -> void:
	var key: String = _context_key()
	if key != _context:
		_offers.clear()
		_events.clear()
		_positions.clear()
		_context = key

func _counter(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0 and float(value) <= MAX_COUNTER and floor(float(value)) == float(value)

func _point_valid(value: Variant) -> bool:
	if not value is Array or value.size() != 3: return false
	for axis: Variant in value:
		if not (axis is float or axis is int) or not is_finite(float(axis)) or absf(float(axis)) > 1000: return false
	return true
