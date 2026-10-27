class_name TwinCampaignCatalog
extends RefCounted
const INDEX_PATH := "res://data/v3/campaign/index.json"
const BINDINGS_PATH := "res://data/v3/campaign/physical_bindings.json"
const StoryContent = preload("res://scripts/v3/content/npc_story_next/twin_npc_story_catalog.gd")

static func extension_paths(include_existing: bool = true) -> Array:
	var index: Dictionary = _json(INDEX_PATH)
	var paths: Array = index.get("base_extension_paths", []).duplicate() if include_existing else []
	paths.append_array(index.get("extension_paths", []))
	return paths

static func facts() -> Dictionary:
	var result: Dictionary = {}
	for path in extension_paths(false):
		var pack: Dictionary = _json(str(path))
		for action in pack.get("actions", []):
			for objective in action.get("objectives", []):
				for event in objective.get("events", []):
					if event.get("type") != "fact": continue
					var target: String = str(event.target_id)
					result[target] = {"objective_id":objective.id,"action_id":action.id,"region_id":action.region_id,
						"options":event.options.duplicate(),"binding":pack.get("host_bindings", {}).get(target, {}).duplicate(true)}
	var physical: Dictionary = _json(BINDINGS_PATH).get("facts", {})
	for target in physical:
		if result.has(target): result[target]["physical"] = physical[target].duplicate(true)
	return result

static func physical_entities(region: String = "") -> Array:
	var result: Array = []
	for entity in _json(BINDINGS_PATH).get("entities", []):
		if region.is_empty() or entity.get("region") == region: result.append(entity.duplicate(true))
	return result

static func ending(choices: Dictionary) -> Dictionary:
	var authored: Dictionary = StoryContent.ending(choices)
	if not authored.is_empty(): return authored
	var final: String = str(choices.get("F4:twin_vein_core:decision", ""))
	var endings := {
		"shared_stewardship":{"title":"一起照料的脉络","lines":["两界按实际负载恢复，保留彼此可核查的维护记录。","林岚协调民用底线，阮衡与阿苔共同照料新支路；恢复需要长期协作。"]},
		"industrial_lifeline":{"title":"先把应急的灯点亮","lines":["应急与生产恢复较快，活脉扩展按较慢节奏继续。","阮衡负责公开限流，阿苔看护保留的幼根；两界的底线服务继续。"]},
		"living_vein":{"title":"先让根重新连起来","lines":["活脉与生态恢复较快，工业扩产按较慢节奏继续。","阿苔负责支脉维护，阮衡调整工厂轮班；居民应急线继续供能。"]}
	}
	if not endings.has(final): return {}
	var result: Dictionary = endings[final].duplicate(true)
	result["ending_id"] = final
	var i2: String = str(choices.get("I2:twin_pump_guardian:decision", ""))
	var f2: String = str(choices.get("F2:mirror_evidence:decision", ""))
	var i4: String = str(choices.get("I4:prism_array:decision", ""))
	result.lines.append("林岚保留病房应急储水，南湾补给按较慢节奏继续。" if i2 == "clinic_reserve" else "水城实行均衡轮换，病房回储与南湾补给共同排班。")
	result.lines.append("疏谣整理原件公开后留下的争议，逐条补上校时说明。" if f2 == "publish_raw" else "疏谣与阮衡共同发布校时说明，原件持续可查。")
	result.lines.append("闻序维护公开上限，所有地区都能核查异常。" if i4 == "public_caps" else "地区共同签署跨界配额，闻序负责记录较慢但明确的协商。")
	result["postgame"] = "从机库返回已修复地区继续探索；不重置已保存的目标、奖励或居民服务。"
	return result

static func _json(path: String) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}
