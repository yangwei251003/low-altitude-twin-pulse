extends RefCounted
## Authored field conversations. Pure reads of committed Story state only.
## Developed for the next content candidate; this batch has not been play-tested.
const SOURCE := "res://data/v3/content/npc_story_next/field_stories.json"
const ENDING_SOURCE := "res://data/v3/content/npc_story_next/ending_stories.json"
const REGIONS := ["F2", "I3", "F3", "I4", "F4"]
static var _book: Dictionary = {}
static var _endings: Dictionary = {}

static func definition(region: String) -> Dictionary:
	return _data().get("regions", {}).get(region, {}).duplicate(true)

static func regions() -> Array:
	return REGIONS.duplicate()

static func markers() -> Array:
	var result: Array = []
	for region: String in REGIONS:
		var row: Dictionary = definition(region)
		if row.is_empty(): continue
		result.append({"id":contact_id(region), "region":region, "kind":"npc", "position":[-29,5.8,18],
			"radius":4.2, "label":str(row.speaker_name)+" · 可选巡访", "optional":false, "field_request_next":true})
		for index: int in 2:
			var survey: Dictionary = row.surveys[index]
			result.append({"id":survey_id(region,index), "region":region, "kind":"inspect", "position":survey.position.duplicate(),
				"radius":3.5, "label":str(survey.label), "title":str(survey.label), "character_id":contact_id(region),
				"lines":survey.lines.duplicate(), "discovery_id":"", "optional":true, "field_request_next":true})
	return result

static func contact_id(region: String) -> String:
	return region+":field_contact_next"

static func survey_id(region: String, index: int) -> String:
	return region+":field_survey_next:"+str(index)

static func target(target_id: String) -> Dictionary:
	for region: String in REGIONS:
		if target_id == contact_id(region): return {"region":region,"kind":"contact","index":-1}
		for index: int in 2:
			if target_id == survey_id(region,index): return {"region":region,"kind":"survey","index":index}
	return {}

static func marker(target_id: String) -> Dictionary:
	for row: Dictionary in markers():
		if row.id == target_id: return row
	return {}

static func entry(committed: Dictionary, region: String) -> Dictionary:
	var row: Dictionary = definition(region)
	if row.is_empty() or committed.get("content_id", "") != "opening_v1": return {}
	var lines: Array = row.entry.duplicate()
	lines.append_array(_choice_lines(committed.get("choices",{}), row.get("entry_choice", "")))
	return _reply(row,region+":entry_next","arrival",str(row.chapter_title),lines)

static func reaction(committed: Dictionary, region: String, requested: String) -> Dictionary:
	var row: Dictionary = definition(region)
	if row.is_empty() or committed.get("content_id", "") != "opening_v1": return {}
	var stage: String = requested
	if requested == region+":boss_briefing": stage = "boss_before"
	elif requested == region+":boss_record" or requested == row.main_character:
		stage = "chapter_after" if str(row.boss_action) in committed.get("completed_actions",[]) else "boss_after"
	var flags: Dictionary = committed.get("flags",{})
	var choices: Dictionary = committed.get("choices",{})
	var completed: Array = committed.get("completed",[])
	var lines: Array = []
	if stage == "boss_before":
		if flags.get(region+":boss_stopped",false) or str(row.boss_action)+":plan" not in completed: return {}
		lines = row.boss_before.duplicate()
	elif stage == "boss_after":
		if not flags.get(region+":boss_stopped",false): return {}
		lines = row.boss_after.duplicate()
	elif stage == "choice_after":
		var key: String = str(row.get("choice_objective",""))
		if key.is_empty() or not choices.has(key): return {}
		lines = _choice_lines(choices,key)
	elif stage == "chapter_after":
		if str(row.boss_action) not in committed.get("completed_actions",[]): return {}
		lines = row.transition.duplicate()
		lines.append_array(_choice_lines(choices,str(row.get("choice_objective",""))))
	else: return {}
	if lines.is_empty(): return {}
	var suffix: String = str(choices.get(str(row.get("choice_objective","")),""))
	return _reply(row,region+":"+stage+":"+suffix,stage,str(row.chapter_title),lines)

static func extra_contact_lines(committed: Dictionary, region: String) -> Array:
	var row: Dictionary = definition(region)
	if row.is_empty(): return []
	var reply: Dictionary = reaction(committed,region,"chapter_after")
	if reply.is_empty(): reply = reaction(committed,region,"boss_after")
	return reply.get("lines",[]).duplicate()

static func ending(choices: Dictionary) -> Dictionary:
	var final: String = str(choices.get("F4:twin_vein_core:decision",""))
	var definitions: Dictionary = _ending_data()
	if not definitions.get("endings",{}).has(final): return {}
	var result: Dictionary = definitions.endings[final].duplicate(true)
	result["ending_id"] = final
	var lines: Array = result.lines.duplicate()
	var stills: Array = result.get("stills",[]).duplicate(true)
	for key: String in ["I2:twin_pump_guardian:decision","F2:mirror_evidence:decision","I4:prism_array:decision"]:
		var consequences: Array = _choice_lines(choices,key)
		lines.append_array(consequences)
		if not consequences.is_empty(): stills.append({"title":str(definitions.choice_titles.get(key,"各地的回答")),"lines":consequences})
	lines.append_array(definitions.get("shared_coda",[]))
	stills.append({"title":"下一次呼叫","lines":definitions.get("shared_coda",[]).duplicate()})
	result["lines"] = lines
	result["stills"] = stills
	result["postgame"] = "按 M 返回已开放地区，继续探索、交接巡访和回访同伴。主线、选择与已领取发现继续保留。"
	return result

static func _choice_lines(choices: Dictionary, objective: String) -> Array:
	if objective.is_empty(): return []
	var option: String = str(choices.get(objective,""))
	if option.is_empty(): return []
	return _ending_data().get("choice_consequences",{}).get(objective,{}).get(option,[]).duplicate()

static func _reply(row: Dictionary, key: String, stage: String, title: String, lines: Array) -> Dictionary:
	return {"key":key,"stage":stage,"title":title,"character_id":str(row.main_character),
		"speaker_name":str(row.chapter_speaker),"lines":lines.duplicate()}

static func _data() -> Dictionary:
	if _book.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
		if parsed is Dictionary: _book = parsed
	return _book

static func _ending_data() -> Dictionary:
	if _endings.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ENDING_SOURCE))
		if parsed is Dictionary: _endings = parsed
	return _endings
