class_name TwinCampaignStateUpgrade
extends RefCounted
## Replays old validated receipts through the new reducer. Emits no rewards.

static func prepare(old_director, new_director, saved: Dictionary) -> Dictionary:
	var current_check: Dictionary = new_director.validate_state(saved)
	if current_check.get("ok", false):
		return {"ok":true,"code":"already_current","state":saved.duplicate(true),"migrated":false}
	var old_check: Dictionary = old_director.validate_state(saved)
	if not old_check.get("ok", false):
		return {"ok":false,"code":"old_action_state_invalid:"+str(old_check.get("code","")),"migrated":false}
	var objective_regions: Dictionary = {}
	for action in new_director.definitions().get("actions", []):
		for objective in action.get("objectives", []): objective_regions[str(objective.id)] = str(action.region_id)
	var receipt_by_objective: Dictionary = {}
	for event_id in saved.get("receipts", {}):
		var receipt: Dictionary = saved.receipts[event_id]
		receipt_by_objective[str(receipt.objective_id)] = {"id":str(event_id),"type":receipt.type,"target_id":receipt.target_id,"option":receipt.option}
	var replay: Dictionary = new_director.default_state()
	if replay.is_empty(): return {"ok":false,"code":"new_definitions_not_loaded","migrated":false}
	for objective_id in saved.completed:
		if not objective_regions.has(str(objective_id)) or not receipt_by_objective.has(str(objective_id)):
			return {"ok":false,"code":"old_objective_removed","migrated":false}
		var result: Dictionary = new_director.apply_event(replay,receipt_by_objective[str(objective_id)],
			{"is_authority":true,"validated":true,"region_id":objective_regions[str(objective_id)]})
		if not result.get("ok",false) or not result.get("changed",false):
			return {"ok":false,"code":"receipt_replay_failed:"+str(result.get("code","")),"migrated":false}
		replay = result.state
	# Fail closed if the new content reinterpreted old event identity or order.
	for key in ["completed","completed_actions","choices","flags","discoveries","receipts"]:
		if JSON.stringify(replay[key],"",true,true) != JSON.stringify(saved[key],"",true,true):
			return {"ok":false,"code":"old_progress_changed:"+str(key),"migrated":false}
	for id in saved.characters:
		if not replay.characters.has(id) or JSON.stringify(replay.characters[id],"",true,true) != JSON.stringify(saved.characters[id],"",true,true):
			return {"ok":false,"code":"old_character_changed:"+str(id),"migrated":false}
	var checked: Dictionary = new_director.validate_state(replay)
	if not checked.get("ok",false): return {"ok":false,"code":"new_action_state_invalid:"+str(checked.get("code","")),"migrated":false}
	return {"ok":true,"code":"old_receipts_replayed","state":replay,"migrated":true}
