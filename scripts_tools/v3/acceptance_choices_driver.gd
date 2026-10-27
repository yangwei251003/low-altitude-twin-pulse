extends "res://scripts_tools/v3/acceptance_flight_driver.gd"
const CampaignCatalog = preload("res://scripts/v3/campaign/twin_campaign_catalog.gd")
## Forks only this task's naturally created private pre-choice branches.
## The original Store branch API isolates alternate play, never authors progress.
var outcomes: Array = []
var home_branch := ""

func play_region(_region: String, _mode: String) -> bool:
	var original := str(session.world_cache.world.branch_id)
	home_branch = original
	var original_story: Dictionary = session.story.state.duplicate(true)
	var pristine: Dictionary = {}
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/v3/campaign/choices.json"))
	for target: String in ["I2:chapter_choice","F2:chapter_choice","I4:chapter_choice","F4:chapter_choice"]:
		var spec: Dictionary = document.choices[target]
		var found := ""
		for id: String in session.store.snapshot().branches:
			var world: Dictionary = session.store.snapshot().branches[id].world
			var story: Dictionary = world.get("actions",{}).get("opening",{})
			if world.region_id == target.substr(0,2) and id.begins_with("before-chapter-") and str(spec.requires_action_objective) in story.get("completed",[]) and str(spec.objective_id) not in story.get("completed",[]):
				found = id; break
		if not _check(not found.is_empty(),"natural main run created a genuine before-choice branch",target): return false
		pristine[target] = found
	for target: String in pristine:
		var spec: Dictionary = session.chapter_choices.specification(target)
		for option: Dictionary in spec.options:
			if not await _switch(str(pristine[target])): return false
			# A normal Store fork preserves the real backup and entire main branch.
			var fork_id := "accept-choice-"+str(Time.get_ticks_usec())
			var fork: Dictionary = session.store.fork_branch(fork_id,"验收替代选择 · "+str(option.label),false)
			if not _check(fork.get("ok",false),"original Store creates a separate alternate branch",fork): return false
			session.world_cache = session.store.snapshot()
			session.consensus.set_world_revision(int(session.world_cache.world_revision))
			if not await _switch(fork_id) or not await _choose(target,option): return false
	if not await _switch(original): return false
	return _check(session.story.state == original_story,"return to main preserves all 84 main receipts and original choices")

func recover_main() -> bool:
	if home_branch.is_empty() or str(session.world_cache.world.branch_id)==home_branch: return true
	pilot = null
	_key(KEY_ESCAPE)
	if not session.consensus.current_proposal().is_empty(): session._ui_action("cancel",{})
	if session.simulation_paused: _key(KEY_P)
	for _frame in range(12): await _next()
	session._ui_action("branch",{"id":home_branch})
	var deadline := Time.get_ticks_msec()+20000
	while session.active and str(session.world_cache.world.branch_id)!=home_branch and Time.get_ticks_msec()<deadline: await _next()
	return _check(str(session.world_cache.world.branch_id)==home_branch,"failure cleanup returns to untouched main through ordinary branch UI",home_branch)

func _switch(id: String) -> bool:
	if not await _dismiss(): return false
	if session.interface.chapter_choice.visible: _key(KEY_ESCAPE)
	if session.simulation_paused: _key(KEY_P); await _next()
	pilot = null
	session._ui_action("branch",{"id":id})
	var deadline := Time.get_ticks_msec()+20000
	while running and str(session.world_cache.world.branch_id) != id and Time.get_ticks_msec()<deadline: await _next()
	if not _check(str(session.world_cache.world.branch_id)==id and session.active,"normal branch UI loads original authored world",id): return false
	if not _rebind(): return false
	_event("normal_branch_switch",{"id":id,"region":session.region_id,"completed":session.story.state.completed.size()})
	return await _dismiss()

func _choose(target: String, option: Dictionary) -> bool:
	var spec: Dictionary = session.chapter_choices.specification(target)
	var anchor := str(spec.anchor_id)
	if not await approach(session.story._point(session.story.markers[anchor]),anchor,4.1): return false
	if not await contact(anchor): return false
	var panel: Control = session.interface.chapter_choice
	if not _check(panel.visible and panel._target==target,"ordinary nearby G opens real choice panel",target): return false
	var boxes: Array[CheckBox] = []
	var text: Array = []
	for child: Node in panel._content.get_children():
		if child is CheckBox: boxes.append(child)
		elif child is Label: text.append(child.text)
	if not _check(boxes.size()==spec.options.size(),"each choice has its own real acknowledgement control",target): return false
	var selected := -1
	for index: int in range(spec.options.size()):
		var item: Dictionary = spec.options[index]
		if not _check("收益："+str(item.benefit)+"\n负担："+str(item.cost) in text,"actual displayed benefit and cost precede decision",item.id): return false
		if not boxes[index].button_pressed and not await ui_accept(boxes[index]): return false
		if item.id==option.id: selected=index
	if not _check(session.chapter_choices.has_read_all(1,target) and selected>=0,"all real host read acknowledgements exist",target): return false
	if not await ui_accept(panel._buttons[selected]): return false
	var deadline := Time.get_ticks_msec()+12000
	while _healthy() and str(spec.objective_id) not in session.story.state.completed and Time.get_ticks_msec()<deadline: await _next()
	var saved: Dictionary = session.store.snapshot()
	var actual: String = str(saved.world.actions.opening.choices.get(spec.objective_id,""))
	if not _check(actual==option.id and session.consensus.current_proposal().is_empty(),"real GUI, Consensus and Story commit requested option",{"target":target,"expected":option.id,"actual":actual}): return false
	if target=="F4:chapter_choice":
		if not _check(saved.world.actions.opening.completed.size()==84 and CampaignCatalog.ending(session.story.state.choices).get("ending_id","")==option.id,"each final option produces its actual ending after native lifeline gates",option.id): return false
	outcomes.append({"kind":"chapter_choice","target":target,"option":option.id,"branch":saved.world.branch_id,"generation":saved.generation})
	_event("actual_alternate_choice",outcomes[-1])
	return true
