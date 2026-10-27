extends RefCounted
## Optional authored visits use the original Host/Gate/Store/discovery path.
## No scene simulation, client facts, secondary reward bank or offline timers.
const Catalog = preload("res://scripts/v3/content/npc_story_next/twin_npc_story_catalog.gd")
const OldJobs = preload("res://scripts/v3/ecology/twin_npc_sidejob_state.gd")
const PATH := "world.field_requests_next_v1"
const MAX_ACTIVE := 4
const MAX_COUNTER := 9007199254740000
var session
var labels: Callable
var error := ""
var _offers: Dictionary = {}
var _events: Array = []
var _context := ""

func setup(owner_session, key_labels: Callable = Callable()) -> bool:
	session = owner_session
	labels = key_labels
	for region: String in Catalog.regions():
		var row: Dictionary = Catalog.definition(region)
		if row.is_empty() or not row.get("surveys") is Array or row.surveys.size() != 2 or not row.get("native") is Dictionary:
			error = "field_content_unavailable"
			return false
	return true

func reset_connection() -> void:
	clear_transient()

func clear_transient() -> void:
	_offers.clear()
	_events.clear()
	_context = ""

func forget_peer(peer: int) -> void:
	_offers.erase(peer)

func bind_world() -> void:
	clear_transient()

func markers() -> Array:
	return Catalog.markers()

func block_legacy_contact(peer: int, actor_id: String) -> bool:
	# The old four job definitions/validator remain untouched. This dispatcher
	# guard counts the same shared activity limit in the opposite direction.
	if not _host(): return false
	var legacy_id := ""
	for id: String in OldJobs.SPECS:
		if OldJobs.SPECS[id].npc == actor_id:
			legacy_id = id
			break
	if legacy_id.is_empty(): return false
	var old: Dictionary = OldJobs.restore(session.world_cache.world.get("npc_sidejobs_v1",{}))
	if not old.ok: return false # Original handler retains its own failure message.
	if old.state.jobs.has(legacy_id): return false # Existing work is never blocked.
	var loaded: Dictionary = _load()
	if not loaded.ok:
		session._note(peer,"巡访记录暂不可确认，新委托尚未接单；已有委托可继续。")
		return true
	var active := 0
	for row: Dictionary in old.state.jobs.values():
		if row.status != "complete": active += 1
	for row: Dictionary in loaded.state.jobs.values():
		if not row.complete: active += 1
	if active < MAX_ACTIVE: return false
	session._note(peer,"共同进行中的可选委托已达4条；先交接一条，再来接新委托。")
	return true

func interact(peer: int, target_id: String) -> bool:
	var target: Dictionary = Catalog.target(target_id)
	if target.is_empty(): return false
	if not _host() or not error.is_empty(): return true
	_refresh_context()
	if not _near(peer,target_id): return true
	var loaded: Dictionary = _load()
	if not loaded.ok:
		session._note(peer,"巡访记录暂不可读取；原记录已保留。")
		return true
	var region: String = target.region
	var spec: Dictionary = Catalog.definition(region)
	if target.kind == "survey":
		_survey(peer,target_id,region,int(target.index),spec)
		return true
	if not loaded.state.jobs.has(region):
		if _offers.get(peer,"") != target_id:
			_offers[peer] = target_id
			var lines: Array = spec.offer.duplicate()
			lines.append("这是可选巡访，不阻挡主线。逐句结束后，再按{contact}接下；离开不会接单。")
			_say(peer,target_id,spec.speaker_name,lines)
			return true
		_offers.erase(peer)
		_accept(peer,target_id,region,spec)
		return true
	var row: Dictionary = loaded.state.jobs[region]
	if row.complete:
		var lines: Array = spec.complete.duplicate()
		lines.append_array(Catalog.extra_contact_lines(session.story.state,region))
		_say(peer,target_id,spec.speaker_name,lines)
	elif _ready(row): _claim(peer,target_id,region,spec)
	else:
		var lines: Array = [str(spec.work_hint),_progress(spec,row)]
		lines.append_array(Catalog.extra_contact_lines(session.story.state,region))
		_say(peer,target_id,spec.speaker_name,lines)
	return true

func ecology_batch(batch: Array, emission_branch: String) -> void:
	if not _host() or not error.is_empty() or emission_branch != str(session.world_cache.world.branch_id): return
	_refresh_context()
	var loaded: Dictionary = _load()
	var region: String = str(session.region_id)
	if not loaded.ok or not loaded.state.jobs.has(region): return
	var row: Dictionary = loaded.state.jobs[region]
	if row.complete or not str(row.native_event_id).is_empty(): return
	var spec: Dictionary = Catalog.definition(region)
	for event: Dictionary in batch:
		if not _native_matches(event,region,spec,row): continue
		# Keep one native event for this visit; no historical replay or client proof.
		if _events.is_empty(): _events.append({"region":region,"event":event.duplicate(true)})
		return

func advance(_delta: float = 0.0) -> void:
	if not _host() or not error.is_empty() or session.environment_save_gate.pending(): return
	_refresh_context()
	if _events.is_empty(): return
	var current_context: String = _context
	var pending: Dictionary = _events[0].duplicate(true)
	var operation := func() -> bool:
		if not _host() or current_context != _context_key(): return false
		var loaded: Dictionary = _load()
		if not loaded.ok or not loaded.state.jobs.has(pending.region): return false
		var candidate: Dictionary = loaded.state.duplicate(true)
		var row: Dictionary = candidate.jobs[pending.region]
		var spec: Dictionary = Catalog.definition(pending.region)
		if not row.complete and str(row.native_event_id).is_empty() and _native_matches(pending.event,pending.region,spec,row):
			row.native_event_id = str(pending.event.event_id)
			row.native_serial = int(pending.event.serial)
			if not session._commit("field-visit-native:"+pending.region,{PATH:candidate}): return false
		if not _events.is_empty(): _events.pop_front()
		return true
	_gate(operation)

func completed_rewards() -> Array:
	var result: Array = []
	if not _authority(): return result
	var loaded: Dictionary = _load()
	if not loaded.ok: return result
	for region: String in Catalog.regions():
		if loaded.state.jobs.get(region,{}).get("complete",false): result.append(str(Catalog.definition(region).reward_id))
	return result

func display_rows() -> Array:
	var result: Array = []
	if not _authority(): return result
	var loaded: Dictionary = _load()
	if not loaded.ok: return result
	for region: String in Catalog.regions():
		if not loaded.state.jobs.has(region): continue
		var row: Dictionary = loaded.state.jobs[region]
		result.append({"title":str(Catalog.definition(region).title),"region":region,"npc_id":Catalog.contact_id(region),
			"status":"complete" if row.complete else ("ready" if _ready(row) else "active")})
	return result

func hint_text(region: String) -> String:
	if not _authority(): return "可选巡访：西侧联络台可接单、查看共同巡访进度。" if region in Catalog.REGIONS else ""
	var loaded: Dictionary = _load()
	if not loaded.ok or not loaded.state.jobs.has(region): return ""
	var row: Dictionary = loaded.state.jobs[region]
	if row.complete: return ""
	var spec: Dictionary = Catalog.definition(region)
	return _render("巡访 · "+str(spec.title)+" · "+("回西侧联络台按{contact}交接" if _ready(row) else _progress(spec,row)))

func _accept(peer: int, target_id: String, region: String, spec: Dictionary) -> void:
	var current_context: String = _context
	var operation := func() -> bool:
		if not _host() or current_context != _context_key() or not _near(peer,target_id): return false
		var loaded: Dictionary = _load()
		if not loaded.ok: return false
		if loaded.state.jobs.has(region): return true
		var old: Dictionary = OldJobs.restore(session.world_cache.world.get("npc_sidejobs_v1",{}))
		if not old.ok:
			session._note(peer,"原委托记录暂不可确认，新巡访尚未接单。")
			return true
		var active := 0
		for item: Dictionary in old.state.jobs.values():
			if item.status != "complete": active += 1
		for item: Dictionary in loaded.state.jobs.values():
			if not item.complete: active += 1
		if active >= MAX_ACTIVE:
			session._note(peer,"共同进行中的可选委托已达4条；先交接一条，再来接巡访。")
			return true
		var baseline: Dictionary = session.ecology.simulation.snapshot()
		var candidate: Dictionary = loaded.state.duplicate(true)
		candidate.jobs[region] = {"accepted_by":str(session.identities.get(peer,session.world_cache.profile_id)),
			"accepted_serial":int(baseline.event_serial),"accepted_seed":int(baseline.seed),
			"survey_bits":0,"native_event_id":"","native_serial":0,"complete":false}
		if not session._commit("field-visit-accept:"+region,{PATH:candidate}): return false
		_say(peer,target_id,spec.speaker_name,["已接下巡访："+str(spec.title),str(spec.work_hint),str(spec.native_hint)],"task_step")
		return true
	_gate(operation,peer)

func _survey(peer: int, target_id: String, region: String, index: int, spec: Dictionary) -> void:
	var survey: Dictionary = spec.surveys[index]
	var loaded: Dictionary = _load()
	if not loaded.ok: return
	if not loaded.state.jobs.has(region):
		var preview: Array = survey.lines.duplicate()
		preview.append("这处线索属于"+str(spec.speaker_name)+"的巡访。可先自由查看；到西侧联络台接单后再核对本轮记录。")
		_say(peer,target_id,spec.speaker_name,preview)
		return
	if loaded.state.jobs[region].complete or (int(loaded.state.jobs[region].survey_bits) & (1 << index)) != 0:
		_say(peer,target_id,spec.speaker_name,survey.lines)
		return
	if session.players[peer].linear_velocity.length() > 4.0:
		session._note(peer,_render("先按{brake}把速度降下来，再按{contact}读取；不必落地。"))
		return
	var current_context: String = _context
	var operation := func() -> bool:
		if not _host() or current_context != _context_key() or not _near(peer,target_id) or session.players[peer].linear_velocity.length() > 4.0: return false
		var fresh: Dictionary = _load()
		if not fresh.ok or not fresh.state.jobs.has(region): return false
		var candidate: Dictionary = fresh.state.duplicate(true)
		var row: Dictionary = candidate.jobs[region]
		if row.complete or (int(row.survey_bits) & (1 << index)) != 0: return true
		row.survey_bits = int(row.survey_bits) | (1 << index)
		if not session._commit("field-visit-survey:"+target_id,{PATH:candidate}): return false
		var lines: Array = survey.lines.duplicate()
		lines.append(_progress(spec,row))
		_say(peer,target_id,spec.speaker_name,lines,"task_step")
		return true
	_gate(operation,peer)

func _claim(peer: int, target_id: String, region: String, spec: Dictionary) -> void:
	var current_context: String = _context
	var operation := func() -> bool:
		if not _host() or current_context != _context_key() or not _near(peer,target_id): return false
		var loaded: Dictionary = _load()
		if not loaded.ok or not loaded.state.jobs.has(region): return false
		var candidate: Dictionary = loaded.state.duplicate(true)
		var row: Dictionary = candidate.jobs[region]
		if row.complete: return true
		if not _ready(row): return false
		row.complete = true
		if not session._commit("field-visit-claim:"+region,{PATH:candidate,"world.flags.field_visit_next:"+region:true},str(spec.reward_id)): return false
		_say(peer,target_id,spec.speaker_name,spec.complete,"task_complete")
		return true
	_gate(operation,peer)

func _native_matches(event: Dictionary, region: String, spec: Dictionary, row: Dictionary) -> bool:
	if row.complete or region != session.region_id: return false
	var expected: Dictionary = spec.get("native",{})
	var required_flag: String = str(expected.get("requires_flag",""))
	if not required_flag.is_empty() and not session.world_cache.world.get("flags",{}).get(required_flag,false): return false
	if event.get("region_id") != region or event.get("actor_id") != expected.get("actor") or event.get("kind") != expected.get("kind") or event.get("target_id") != expected.get("target"): return false
	if not _counter(event.get("serial")) or int(event.serial) <= int(row.accepted_serial): return false
	var current: Dictionary = session.ecology.simulation.snapshot()
	if int(current.seed) != int(row.accepted_seed) or int(event.serial) > int(current.event_serial): return false
	return event.get("event_id") == "ecology:%s:%d:%d" % [str(current.content_id),int(current.seed),int(event.serial)]

func _load() -> Dictionary:
	var raw: Variant = session.world_cache.world.get("field_requests_next_v1",{})
	if raw is Dictionary and raw.is_empty(): return {"ok":true,"state":{"schema_version":1,"jobs":{}}}
	if not raw is Dictionary or raw.size() != 2 or raw.get("schema_version") != 1 or not raw.get("jobs") is Dictionary or raw.jobs.size() > 5: return {"ok":false}
	for region: Variant in raw.jobs:
		if not region is String or region not in Catalog.REGIONS: return {"ok":false}
		var row: Variant = raw.jobs[region]
		if not row is Dictionary or row.size() != 7 or not row.has_all(["accepted_by","accepted_serial","accepted_seed","survey_bits","native_event_id","native_serial","complete"]): return {"ok":false}
		if not row.accepted_by is String or row.accepted_by.is_empty() or row.accepted_by.length() > 200 or not row.complete is bool: return {"ok":false}
		for key: String in ["accepted_serial","accepted_seed","survey_bits","native_serial"]:
			if not _counter(row[key]): return {"ok":false}
		if int(row.accepted_seed) < 1 or int(row.accepted_seed) >= 2147483647 or int(row.survey_bits) > 3: return {"ok":false}
		if not row.native_event_id is String or row.native_event_id.length() > 200: return {"ok":false}
		if row.native_event_id.is_empty():
			if int(row.native_serial) != 0: return {"ok":false}
		elif int(row.native_serial) <= int(row.accepted_serial) or not row.native_event_id.begins_with("ecology:"): return {"ok":false}
		if row.complete and not _ready(row): return {"ok":false}
	return {"ok":true,"state":raw.duplicate(true)}

func _ready(row: Dictionary) -> bool:
	return int(row.survey_bits) == 3 and not str(row.native_event_id).is_empty() and int(row.native_serial) > int(row.accepted_serial)

func _progress(spec: Dictionary, row: Dictionary) -> String:
	if _ready(row): return "两处巡访与本轮作业都已记录，回西侧联络台交接。"
	var readings := 0
	if (int(row.survey_bits) & 1) != 0: readings += 1
	if (int(row.survey_bits) & 2) != 0: readings += 1
	return "现场读数 %d/2 · %s" % [readings,"本轮同伴作业已记录" if not str(row.native_event_id).is_empty() else str(spec.native_hint)]

func _gate(operation: Callable, peer: int = 0) -> void:
	if session._canal_action_in_capture:
		if not operation.call() and peer > 0: session._note(peer,"巡访保存未完成，尚未确认或发奖。")
		return
	if session.environment_save_gate.pending():
		if peer > 0: session._note(peer,"现场正在保存，请稍后再联络；这次尚未确认。")
		return
	session.environment_save_gate.request(operation,func(result: Dictionary):
		if not result.get("ok",false) and peer > 0: session._note(peer,"巡访保存未完成，尚未确认或发奖。"))

func _near(peer: int, target_id: String) -> bool:
	var marker: Dictionary = Catalog.marker(target_id)
	if marker.is_empty() or marker.region != session.region_id or not session.players.has(peer): return false
	var body: Variant = session.players[peer]
	if not is_instance_valid(body) or not body.enabled: return false
	var p: Array = marker.position
	var at := Vector3(float(p[0]),float(p[1]),float(p[2]))
	if not body.global_position.is_finite() or body.global_position.distance_to(at) > float(marker.radius): return false
	return session._line_clear(body.global_position,at,body.get_rid(),target_id)

func _say(peer: int, target_id: String, speaker: String, lines: Array, cue: String = "interaction") -> void:
	var rendered: Array = []
	for line: String in lines: rendered.append(_render(line))
	session.network.send_event(peer,{"kind":"dialogue","character_id":target_id,"speaker_name":speaker,"lines":rendered})
	var p: Array = Catalog.marker(target_id).get("position",[0,0,0])
	session._audio_event(cue,Vector3(float(p[0]),float(p[1]),float(p[2])),target_id)

func _render(line: String) -> String:
	var keys: Dictionary = labels.call() if labels.is_valid() else {}
	for key: String in ["contact","brake","ability"]:
		line = line.replace("{"+key+"}",str(keys.get(key,"G" if key == "contact" else ("空格" if key == "brake" else "F"))))
	return line

func _authority() -> bool:
	return is_instance_valid(session) and session.active and session.owns_world and session.network.is_authority()

func _host() -> bool:
	return _authority() and session.ecology.ready and not session.simulation_paused and not session.boss_active and not session.pending_completion and session.consensus.current_proposal().is_empty()

func _context_key() -> String:
	return str(session.network.session_id)+":"+str(session.world_cache.world.branch_id)+":"+str(session.region_id)

func _refresh_context() -> void:
	var value: String = _context_key()
	if value != _context:
		_offers.clear()
		_events.clear()
		_context = value

func _counter(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0 and float(value) <= MAX_COUNTER and floor(float(value)) == float(value)
