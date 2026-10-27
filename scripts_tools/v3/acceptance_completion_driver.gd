extends "res://scripts_tools/v3/acceptance_flight_driver.gd"
## Aggregate only the saved results of this task's real optional-input runs.
const Jobs = preload("res://scripts/v3/content/dev88_story/twin_side_story_catalog.gd")
const Field = preload("res://scripts/v3/content/npc_story_next/twin_npc_story_catalog.gd")
const Notes = preload("res://scripts/v3/content/dev88_progression/twin_dev88_rewards.gd")
const Sites = preload("res://scripts/v3/content/dev88_combat/twin_combat_sites_catalog.gd")
var outcomes: Array = []

func play_region(_region: String, _mode: String) -> bool:
	var saved: Dictionary = session.store.snapshot()
	var discoveries: Array = saved.personal.discoveries
	var jobs: Array = []
	for spec: Dictionary in Jobs.definitions():
		var row: Dictionary = saved.world.get("side_stories_dev88_v1",{}).get("jobs",{}).get(spec.id,{})
		if not _check(row.get("complete",false) and int(row.get("stage",0))==spec.stages.size() and discoveries.count(str(spec.reward_id))==1,"real saved short story and unique reward are complete",spec.id): return false
		jobs.append(spec.id)
	for region: String in Field.regions():
		var spec: Dictionary = Field.definition(region)
		var row: Dictionary = saved.world.get("field_requests_next_v1",{}).get("jobs",{}).get(region,{})
		if not _check(row.get("complete",false) and int(row.get("survey_bits",0))==3 and int(row.get("native_serial",0))>int(row.get("accepted_serial",0)) and discoveries.count(str(spec.reward_id))==1,"real saved field surveys and post-acceptance native ecology event are complete",region): return false
		jobs.append("field:"+region)
	for region: String in ["I1","I2","F2","I3"]:
		var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/v3/campaign/npc_sidejob_"+region.to_lower()+".json"))
		var row: Dictionary = saved.world.get("npc_sidejobs_v1",{}).get("jobs",{}).get(spec.id,{})
		if not _check(row.get("status","")=="complete" and discoveries.count(str(spec.reward_id))==1,"real saved legacy commission and unique reward are complete",spec.id): return false
		jobs.append(spec.id)
	var secrets: Array = []
	for note: Dictionary in Notes.notes():
		if not _check(saved.world.flags.get("note:"+str(note.id),false) and discoveries.count(str(note.discovery_id))==1,"saved physical investigation and unique discovery exist",note.id): return false
		secrets.append(note.id)
	var sites: Array = []
	for region: String in ["I1","F1","I2","F2","I3","F3","I4","F4"]:
		for site: Dictionary in Sites.sites(region):
			if not _check(session.combat_sites.completed(str(site.id)) and session.combat_sites.completion_serial(str(site.id))>0 and discoveries.count(str(site.reward_id))==1,"saved real encounter has one reward and original completion serial",site.id): return false
			sites.append(site.id)
	var modules: Array = []
	for row: Dictionary in Notes.unlocks(discoveries):
		if not _check(row.owned and row.found==4 and row.total==4,"four actual region discoveries unlock the existing module",row.region): return false
		modules.append(row.module_id)
	outcomes.append({"kind":"aggregate_of_actual_saved_input_runs","jobs":jobs,"secrets":secrets,"combat_sites":sites,"modules":modules})
	return _check(jobs.size()==24 and secrets.size()==32 and sites.size()==10 and modules.size()==8,"all authored optional content has actual saved completion evidence")
