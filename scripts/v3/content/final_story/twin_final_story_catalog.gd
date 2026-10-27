extends RefCounted
## Read-only aftermath and epilogue. The original Director owns every fact.
const SOURCE := "res://data/v3/content/final_story/aftermath.json"
const FINAL_ACTION := "F4:twin_vein_core"
const FINAL_OBJECTIVE := "F4:twin_vein_core:decision"
const NARRATOR := "narrator:final_archive"
const CHOICES := {
	"I2:twin_pump_guardian:decision":["clinic_reserve","balanced_service"],
	"F2:mirror_evidence:decision":["publish_raw","publish_context"],
	"I4:prism_array:decision":["public_caps","regional_cosign"],
	"F4:twin_vein_core:decision":["shared_stewardship","industrial_lifeline","living_vein"]}
static var _document: Dictionary = {}

static func ending_ready(committed: Dictionary) -> bool:
	if not _shape(committed): return false
	if FINAL_ACTION not in committed.completed_actions: return false
	if "F4:twin_vein_core:stop" not in committed.completed or FINAL_OBJECTIVE not in committed.completed: return false
	for flag: String in ["F4:boss_stopped","F4:chapter_decision_saved","F4:region_route_open"]:
		if committed.flags.get(flag) != true: return false
	for key: String in CHOICES:
		if str(committed.choices.get(key,"")) not in CHOICES[key]: return false
	return true

static func all_markers() -> Array:
	var result: Array = []
	for row: Dictionary in _data().get("regions",[]):
		# These are archive markers, not another instance of a living character.
		# Root registers them once, then gates visibility with marker_available.
		result.append({"id":str(row.marker_id),"region":str(row.id),"position":row.position.duplicate(),
			"kind":"inspect","radius":4.2,"optional":true,"label":str(row.title),"title":str(row.title),
			"final_story_archive":true,"discovery_id":"","lines":[]})
	return result

static func markers(committed: Dictionary) -> Array:
	var result: Array = []
	for marker: Dictionary in all_markers():
		if marker_available(committed,str(marker.id)): result.append(marker)
	return result

static func marker_available(committed: Dictionary, marker_id: String) -> bool:
	var region: Dictionary = _region_by_marker(marker_id)
	if region.is_empty(): return true # Never gate another subsystem's marker.
	if not _shape(committed): return false
	if region.id == "F4": return ending_ready(committed)
	for action: String in region.get("requires_actions",[]):
		if action not in committed.completed_actions: return false
	for objective: String in region.get("requires_objectives",[]):
		if objective not in committed.completed: return false
	for flag: String in region.get("requires_flags",[]):
		if committed.flags.get(flag) != true: return false
	var key: String = str(region.get("requires_choice",""))
	if not key.is_empty() and str(committed.choices.get(key,"")) not in CHOICES.get(key,[]): return false
	return true

static func ending_cards(committed: Dictionary, world: Dictionary = {}, presence: Dictionary = {}) -> Array:
	var result: Array = []
	if not ending_ready(committed): return result
	var selected: String = str(committed.choices[FINAL_OBJECTIVE])
	var ending: Dictionary = _data().get("endings",{}).get(selected,{})
	if ending.is_empty(): return result
	result.append(_card(ending))
	for key: String in ["I2:twin_pump_guardian:decision","F2:mirror_evidence:decision","I4:prism_array:decision"]:
		var option: String = str(committed.choices[key])
		var choice: Dictionary = _data().get("choices",{}).get(key,{}).get(option,{})
		if not choice.is_empty(): result.append(_card(choice))
	result.append_array(character_outcomes(committed,presence))
	var unfinished: Array = []
	for row: Dictionary in _data().get("task_revisits",[]):
		if _task_status(world,row) in ["active","ready"]: unfinished.append(str(row.title))
	var return_card: Dictionary = _card(_data().get("return_card",{}))
	if not unfinished.is_empty(): return_card.lines.append("还没有交接的记录继续留着："+"、".join(unfinished)+"。可按自己的次序回访，不必为结局重做。")
	result.append(return_card)
	return result

static func character_outcomes(committed: Dictionary, presence: Dictionary = {}) -> Array:
	var result: Array = []
	if not ending_ready(committed): return result
	var selected: String = str(committed.choices[FINAL_OBJECTIVE])
	for character: Dictionary in _data().get("characters",[]):
		var availability: String = _presence(presence.get(str(character.id),"recorded"))
		var source: Dictionary = character.get("legacy",{}) if availability in ["lost","absent"] else character.get("endings",{}).get(selected,{})
		if source.is_empty(): continue
		var card: Dictionary = _card(source)
		if availability not in ["lost","absent"]:
			var key: String = str(character.get("choice_key",""))
			var option: String = str(committed.choices.get(key,""))
			card.lines.append_array(character.get("choice_lines",{}).get(option,[]))
		card["subject_id"] = str(character.id)
		card["region"] = str(character.region)
		card["assignment"] = str(character.assignment)
		card["presence"] = availability
		# A location here records a responsibility, not physical NPC presence.
		card["mode"] = "archive"
		result.append(card)
	return result

static func revisit(committed: Dictionary, world: Dictionary, marker_id: String, presence: Dictionary = {}) -> Dictionary:
	var row: Dictionary = _region_by_marker(marker_id)
	if row.is_empty() or not marker_available(committed,marker_id): return {}
	var lines: Array = row.get("chapter_lines",[]).duplicate()
	for key: String in row.get("choice_keys",[]):
		var option: String = str(committed.choices.get(key,""))
		var choice: Dictionary = _data().get("choices",{}).get(key,{}).get(option,{})
		lines.append_array(choice.get("revisit_lines",[]))
	if ending_ready(committed):
		var selected: String = str(committed.choices[FINAL_OBJECTIVE])
		lines.append_array(row.get("postgame",{}).get(selected,[]))
	for task: Dictionary in _data().get("task_revisits",[]):
		if task.region != row.id: continue
		var status: String = _task_status(world,task)
		if status == "complete": lines.append_array(task.get("lines",[]))
		elif status == "ready": lines.append(str(task.get("ready_line","已有作业尚待交接，原记录保留。")))
	for character: Dictionary in _data().get("characters",[]):
		if character.region != row.id: continue
		if _presence(presence.get(str(character.id),"recorded")) in ["lost","absent"]:
			lines.append(str(character.name)+"的本人回应不在这次联络中；这里只保留此前留下的职责，由接续者继续。")
	return {"id":str(row.marker_id),"key":str(row.marker_id)+":"+str(committed.choices.get(FINAL_OBJECTIVE,"chapter")),
		"region":str(row.id),"title":str(row.title),"character_id":NARRATOR,"speaker_name":"两界留档",
		"mode":"archive","lines":lines,"voice_id":str(row.voice_id),"position":row.position.duplicate()}

static func journal_rows(committed: Dictionary, world: Dictionary = {}, region: String = "", presence: Dictionary = {}) -> Array:
	var result: Array = []
	for marker: Dictionary in markers(committed):
		if not region.is_empty() and str(marker.region) != region: continue
		var reply: Dictionary = revisit(committed,world,str(marker.id),presence)
		result.append({"id":str(marker.id),"target_id":str(marker.id),"region":str(marker.region),"title":str(reply.title),
			"status":"epilogue" if ending_ready(committed) else "aftermath","hint":"只读回访留档，可反复阅读。",
			"position":marker.position.duplicate(),"lines":reply.lines.duplicate(),"voice_id":str(reply.voice_id),"mode":"archive"})
	return result

static func _task_status(world: Dictionary, spec: Dictionary) -> String:
	var bank: Variant = world.get(str(spec.bank),{})
	if not bank is Dictionary or not bank.get("jobs",{}) is Dictionary: return "unstarted"
	if bank.get("schema_version") != 1: return "unstarted"
	var jobs: Dictionary = bank.get("jobs",{})
	var row: Variant = jobs.get(str(spec.job),{})
	if not row is Dictionary or row.is_empty(): return "unstarted"
	if str(spec.bank) == "npc_sidejobs_v1":
		return str(row.get("status","active")) if row.get("status") in ["active","ready","complete"] else "unstarted"
	if row.get("complete") == true: return "complete"
	if str(spec.bank) == "field_requests_next_v1":
		if int(row.get("survey_bits",0)) == 3 and not str(row.get("native_event_id","")).is_empty(): return "ready"
	elif int(row.get("stage",0)) >= int(spec.get("stage_count",999)): return "ready"
	return "active"

static func _card(source: Dictionary) -> Dictionary:
	return {"id":str(source.get("id","")),"title":str(source.get("title","")),"lines":source.get("lines",[]).duplicate(),
		"voice_id":str(source.get("voice_id","")),"voice_text":str(source.get("voice_text","")),
		"character_id":NARRATOR,"speaker_name":"两界留档","mode":"archive"}

static func _region_by_marker(id: String) -> Dictionary:
	for region: Dictionary in _data().get("regions",[]):
		if region.marker_id == id: return region
	return {}

static func _presence(raw: Variant) -> String:
	# The current Director stores met/memories only. Never invent mortality
	# from those fields or from a guessed flag. Root may pass explicit facts.
	if raw is String:
		if raw in ["lost","dead","deceased"]: return "lost"
		if raw in ["absent","missing","unavailable"]: return "absent"
		if raw in ["present","remote","recorded"]: return raw
	return "recorded"

static func _shape(committed: Dictionary) -> bool:
	return committed.get("content_id") == "opening_v1" and committed.get("completed") is Array and committed.get("completed_actions") is Array and committed.get("choices") is Dictionary and committed.get("flags") is Dictionary

static func _data() -> Dictionary:
	if _document.is_empty():
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
		if raw is Dictionary: _document = raw
	return _document
