extends RefCounted
## Authored choices use original consensus, branches and Story transactions.
## A nearby G opens the offer; only explicit read acknowledgements are saved.
const PATH := "world.environment.campaign_choices"
const SOURCE := "res://data/v3/campaign/choices.json"
var session
var readings: Dictionary = {}
var error := ""

func setup(owner_session) -> void:
	session = owner_session

func bind_world() -> bool:
	readings.clear()
	error = ""
	if not session.network.is_authority(): return true
	var saved: Dictionary = session.world_cache.world.get("environment",{}).get("campaign_choices",{})
	if saved.is_empty(): return true
	if saved.get("version") != 1 or not saved.get("readings") is Dictionary: return _fail("choice_save_shape")
	for target in saved.readings:
		var offer := specification(str(target))
		if offer.is_empty() or not saved.readings[target] is Dictionary: return _fail("choice_save_target")
		for identity in saved.readings[target]:
			var options: Variant = saved.readings[target][identity]
			if not identity is String or identity.is_empty() or not options is Array: return _fail("choice_save_identity")
			var seen: Array = []
			for option in options:
				if option not in _option_ids(offer) or option in seen: return _fail("choice_save_option")
				seen.append(option)
	readings = saved.readings.duplicate(true)
	return true

func persistent_states() -> Dictionary:
	return {PATH:{"version":1,"readings":readings.duplicate(true)}}

func specification(target: String) -> Dictionary:
	var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
	if not document is Dictionary: return {}
	var offer: Dictionary = document.get("choices",{}).get(target,{}).duplicate(true)
	if offer.is_empty(): return {}
	if offer.has("options_from"): offer["options"] = document.choices.get(offer.options_from,{}).get("options",[]).duplicate(true)
	offer["target_id"] = target
	return offer

func target_for_anchor(id: String) -> String:
	for target in session.story.current_targets():
		if target.type != "fact": continue
		var offer := specification(str(target.target_id))
		if offer.get("anchor_id","") == id: return str(target.target_id)
	return ""

func open(peer: int, anchor: String) -> bool:
	var target := target_for_anchor(anchor)
	if target.is_empty(): return false
	if not _near(peer,target): return true
	var event := {"kind":"campaign_choice_offer","session_id":session.network.session_id,"region":session.region_id,"target":target,"read_options":_read_options(peer,target)}
	if peer == session.network.local_id(): _show(event)
	else: session.network.send_event(peer,event)
	return true

func receive(event: Dictionary) -> void:
	if session.network.mode != "guest" or event.get("kind") != "campaign_choice_offer": return
	if event.get("session_id") != session.received_session or event.get("region") != session.region_id: return
	if not event.get("target") is String or not event.get("read_options") is Array: return
	_show(event)

func read_option(peer: int, target: String, option: String) -> bool:
	if not session.network.is_authority() or not _eligible(target) or not _near(peer,target): return false
	var offer := specification(target)
	if option not in _option_ids(offer): return false
	var identity: String = str(session.identities.get(peer,""))
	if identity.is_empty(): return false
	var before := readings.duplicate(true)
	if not readings.has(target): readings[target] = {}
	if not readings[target].has(identity): readings[target][identity] = []
	if option in readings[target][identity]:
		_voice_read(peer, target, option)
		return true
	readings[target][identity].append(option)
	# Reading a pending offer changes no scene or choice. Keep this acknowledgement
	# with the pending proposal and persist it in the eventual original Story tx;
	# an unrelated Store revision must still invalidate that proposal normally.
	var pending: Dictionary = session.consensus.current_proposal()
	if pending.get("kind") == "campaign_choice" and pending.get("payload",{}).get("target") == target:
		_voice_read(peer, target, option)
		return true
	var mechanism_before: Dictionary = {}
	if offer.get("review_only",false) and session.campaign.mechanisms != null:
		mechanism_before = session.campaign.mechanisms.persistent_state()
		var observed: Dictionary = session.campaign.observe_interaction(peer,str(offer.anchor_id),option)
		if not observed.get("ok",false):
			readings = before
			return false
	if not session._commit("campaign-choice-read:"+target+":"+option,{}):
		readings = before
		if not mechanism_before.is_empty(): session.campaign.mechanisms.restore(mechanism_before)
		return false
	_voice_read(peer, target, option)
	return true

func _voice_read(peer: int, target: String, option: String) -> void:
	# Only a successful explicit read acknowledgement requests its explanation.
	# This event has no choice, checkbox, reward or Store authority of its own.
	session.network.send_event(peer, {"kind":"chapter_voice_read88", "session_id":session.network.session_id,
		"region":session.region_id, "target":target, "option":option})

func prepare_proposal(peer: int, target: String, option: String) -> Dictionary:
	if not session.consensus.current_proposal().is_empty() or not _eligible(target) or not _near(peer,target): return {"ok":false,"code":"choice_not_available"}
	var offer := specification(target)
	if offer.get("review_only",false) or option not in _option_ids(offer) or not has_read_all(peer,target): return {"ok":false,"code":"read_each_option_first"}
	var live: Dictionary = _final_lifelines_status(target)
	if not live.ok: return {"ok":false,"code":str(live.code),"details":live}
	if not session._save_environment(): return {"ok":false,"code":"environment_save_failed"}
	var branch := "before-chapter-%d-%d" % [int(session.world_cache.generation),Time.get_ticks_usec()]
	var fork: Dictionary = session.store.fork_branch(branch,str(offer.title)+" · 决定之前",false)
	if not fork.get("ok",false): return {"ok":false,"code":"choice_branch_save_failed"}
	session.world_cache = session.store.snapshot()
	session.consensus.set_world_revision(int(session.world_cache.world_revision))
	var label := ""
	for item in offer.options:
		if item.id == option: label = str(item.label)+"\n收益："+str(item.benefit)+"\n负担："+str(item.cost)+"\n保底："+str(item.baseline)
	return {"ok":true,"payload":{"target":target,"option":option,"observer":peer,"branch_id":branch,"description":label}}

func confirmation_valid(peer: int, payload: Dictionary) -> bool:
	var target := str(payload.get("target",""))
	return _eligible(target) and _near(peer,target) and has_read_all(peer,target) and str(payload.get("option","")) in _option_ids(specification(target))

func commit_ready(proposal: Dictionary) -> bool:
	var payload: Dictionary = proposal.get("payload",{})
	if proposal.get("kind") != "campaign_choice" or proposal.get("state") != "ready" or not session._resolving_decision: return false
	if not session.store.snapshot().branches.has(str(payload.get("branch_id",""))): return false
	for id in proposal.get("participants",[]):
		if not confirmation_valid(int(id),payload): return false
	# Re-sample after ALL original proposal/UUID/read/branch gates, immediately
	# before the original no-await Story Store transaction. No earlier view credit.
	if not _final_lifelines_status(str(payload.target)).ok: return false
	return session.story.commit_campaign_choice(str(proposal.proposal_id),str(payload.target),str(payload.option))

func _final_lifelines_status(target: String) -> Dictionary:
	if target != "F4:chapter_choice": return {"ok":true}
	if not session.owns_world or not session.network.is_authority() or not session.campaign.supported() or session.campaign.mechanisms == null: return {"ok":false,"code":"final_lifelines_live_host_required"}
	var current: Dictionary = session.campaign.mechanisms.final_lifelines_status(session.entities)
	if not current.ok:
		var cancel_hint := "先取消当前提案，" if not session.consensus.current_proposal().is_empty() else ""
		session._note_all("终局尚未签署："+cancel_hint+"恢复工业供电与活脉光路、完整支撑后再确认；已保存成果保留。")
	return current

func has_read_all(peer: int, target: String) -> bool:
	var required := _option_ids(specification(target))
	var read := _read_options(peer,target)
	if required.is_empty() or read.size() != required.size(): return false
	for option in required:
		if option not in read: return false
	return true

func _read_options(peer: int, target: String) -> Array:
	return readings.get(target,{}).get(str(session.identities.get(peer,"")),[]).duplicate()

func _eligible(target: String) -> bool:
	if not session.active or not session.story.ready or session.simulation_paused or session.pending_completion: return false
	var offer := specification(target)
	if offer.is_empty() or not str(target).begins_with(session.region_id+":"): return false
	if offer.has("requires_action_objective") and offer.requires_action_objective not in session.story.state.get("completed",[]): return false
	for current in session.story.current_targets():
		if current.type == "fact" and current.target_id == target: return true
	return false

func _near(peer: int, target: String) -> bool:
	if not session.players.has(peer) or not session.players[peer].enabled: return false
	var anchor: String = str(specification(target).get("anchor_id",""))
	if not session.story.markers.has(anchor): return false
	var marker: Dictionary = session.story.markers[anchor]
	var at: Vector3 = session.story._point(marker)
	var body: FlightBodyV2 = session.players[peer]
	return marker.region == session.region_id and body.global_position.distance_to(at) <= float(marker.radius) and session._line_clear(body.global_position,at,body.get_rid(),anchor)

func _show(event: Dictionary) -> void:
	var offer := specification(str(event.target))
	if offer.is_empty(): return
	for option in event.read_options:
		if option not in _option_ids(offer): return
	session.interface.chapter_choice.show_offer(offer,event.read_options,bool(offer.get("review_only",false)))

func _option_ids(offer: Dictionary) -> Array:
	var ids: Array = []
	for option in offer.get("options",[]): ids.append(str(option.id))
	return ids

func _fail(code: String) -> bool:
	error = code
	return false
