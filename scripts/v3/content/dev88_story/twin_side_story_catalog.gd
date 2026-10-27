extends RefCounted
## Fifteen voluntary, actionable short stories; no main-story state mutation.
const SOURCE := "res://data/v3/content/dev88_story/side_stories.json"
static var _document: Dictionary = {}

static func definitions(region: String = "") -> Array:
	var rows: Array = []
	for row: Dictionary in _read().get("jobs",[]):
		if region.is_empty() or str(row.region) == region: rows.append(row.duplicate(true))
	return rows

static func definition(id: String) -> Dictionary:
	for row: Dictionary in _read().get("jobs",[]):
		if row.id == id: return row.duplicate(true)
	return {}

static func contact(id: String) -> Dictionary:
	for row: Dictionary in _read().get("jobs",[]):
		if str(row.contact.id) == id: return row.duplicate(true)
	return {}

static func markers() -> Array:
	var rows: Array = []
	for spec: Dictionary in definitions():
		rows.append({"id":str(spec.contact.id),"region":str(spec.region),"position":spec.contact.position.duplicate(),
			"kind":"npc","radius":4.0,"label":str(spec.speaker_name)+" · "+str(spec.title),"character_id":str(spec.character_id),
			"speaker_name":str(spec.speaker_name),"role":str(spec.role),"optional":false,"side_story88":true})
	return rows

static func entities(region: String) -> Array:
	var result: Array = []
	for spec: Dictionary in definitions(region): result.append_array(spec.get("entities",[]))
	return result

static func vector(point: Array) -> Vector3:
	return Vector3(float(point[0]),float(point[1]),float(point[2]))

static func chapter_extra(committed: Dictionary, region: String) -> Array:
	var result: Array = []
	var choices: Dictionary = committed.get("choices",{})
	var final: String = str(choices.get("F4:twin_vein_core:decision",""))
	if not final.is_empty():
		if region == "I1": result.append("林岚：结局的方案已经写下，低空的下一声呼叫仍有人接；返航灯和打捞小队的日常继续。")
		elif region == "F1": result.append("阿苔：冠峰的决定不替代林下的照护。慢开的花、回铃和检修孢，都值得你再看一眼。")
		elif region == "I2": result.append("林岚：病房与南湾继续照着记录轮换。支线不会改写你们已签的安排，也不用重新完成旧病房工序。")
	return result

static func completion_lines(spec: Dictionary, committed: Dictionary) -> Array:
	var lines: Array = spec.get("complete",[]).duplicate()
	var choice_key: String = str(spec.get("choice_key",""))
	var selected: String = str(committed.get("choices",{}).get(choice_key,""))
	lines.append_array(spec.get("choice_replies",{}).get(selected,[]))
	lines.append_array(chapter_extra(committed,str(spec.region)))
	return lines

static func prerequisite_text(spec: Dictionary, committed: Dictionary) -> String:
	var key: String = str(spec.get("requires_choice",""))
	if not key.is_empty() and str(committed.get("choices",{}).get(key,"")).is_empty():
		return str(spec.get("prerequisite_hint","先完成原章节的知情决定，再来接这条后续委托；这里不会替你选择。"))
	return ""

static func _read() -> Dictionary:
	if _document.is_empty():
		var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
		if value is Dictionary: _document = value
	return _document
