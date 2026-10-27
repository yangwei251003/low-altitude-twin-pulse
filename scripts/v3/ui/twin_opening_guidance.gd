class_name TwinOpeningGuidance
extends RefCounted
## Read-only presentation helpers. They never advance objectives, choose a route,
## select/cast an ability, validate LOS, or approve host/physics actions.
## Caller supplies current-region live entities and story.markers (including any
## dynamic record anchors). No copied world coordinates or static state cache.

const Rules = preload("res://scripts/v3/gameplay/twin_ability_rules.gd")

# Existing authored objective IDs -> their existing event target IDs.
const OBJECTIVE_TARGETS = {
	"I1:rescue:brief":"npc:linlan", "I1:rescue:channel":"I1:rescue_channel",
	"I1:rescue:contact":"I1:rescue_pocket", "I1:rescue:evacuate":"I1:rescue_exit",
	"I1:evidence:trace":"I1:burn_trace", "I1:evidence:engineer":"npc:ruanheng",
	"I1:evidence:ledger":"I1:energy_ledger", "I1:evidence:echo":"I1:beacon_echo",
	"F1:needs:listen":"npc:atai", "F1:needs:nursery":"F1:dry_nursery",
	"F1:needs:route":"F1:nursery_landing", "F1:repair:plan":"npc:atai",
	"F1:repair:light":"F1:light_receiver", "F1:repair:grow":"F1:growth_bridge",
	"F1:repair:confirm":"F1:shared_junction",
	"I1:whale:brief":"I1:whale_briefing", "I1:whale:engage":"I1:whale_engaged",
	"I1:whale:disable":"I1:whale_defeated", "I1:whale:record":"I1:whale_raw_record",
	"F1:crown:brief":"F1:crown_briefing", "F1:crown:engage":"F1:crown_engaged",
	"F1:crown:disable":"F1:crown_defeated", "F1:crown:restore":"F1:crown_recovered",
	"I1:underdeck:read":"I1:underdeck_log", "I1:underdeck:enter":"I1:underdeck_entry",
	"I1:underdeck:release":"I1:underdeck_safety_lock", "I1:underdeck:traverse":"I1:underdeck_transit",
	"I2:clinic_supply:diagnose":"I2:clinic_demand", "I2:clinic_supply:connect":"I2:clinic_feed",
	"I2:clinic_supply:stabilize":"I2:clinic_water_ready", "I2:clinic_supply:confirm":"I2:clinic_water_check",
}

# A display destination is NOT the required interaction or the completion test.
# Rescue points at the stranded drone, leaving gate/overflight routes open.
const FACT_DESTINATIONS = {
	"I1:rescue_channel":"I1:rescue_pocket",
	"F1:light_receiver":"F1:mirror",
	"F1:growth_bridge":"F1:growth",
	"I1:whale_engaged":"boss:core", "I1:whale_defeated":"boss:core",
	"F1:crown_engaged":"boss:crown_core", "F1:crown_defeated":"boss:crown_core",
	"I1:underdeck_safety_lock":"I1:underdeck_latch",
	"I2:clinic_water_ready":"I2:clinic_water_check",
}

# Text follows TwinSession._send_ability's default F / X modes. Returning ONE
# selected ability does not expand the ten-ability bar or alter early access.
const ACTIONS = {
	"blink":{"name":"折跃", "action":"向移动方向折跃", "reverse":"", "note":"路径与落点须畅通；松开方向时朝镜头前方"},
	"push_pull":{"name":"牵引 / 排斥", "action":"推开物件", "reverse":"拉近物件"},
	"force_field":{"name":"局部力场", "action":"固定物件", "reverse":"解除固定"},
	"light":{"name":"光束", "action":"照亮目标", "reverse":"熄灭光源"},
	"heat":{"name":"热量", "action":"加热", "reverse":"降温"},
	"charge":{"name":"电荷", "action":"充能", "reverse":"抽能"},
	"growth":{"name":"生长", "action":"催生幼根", "reverse":"", "note":"需要光照与适宜温度"},
	"decoy":{"name":"诱导分身", "action":"在前方放出分身", "reverse":""},
	"echo":{"name":"协作分身", "action":"协助操作目标", "reverse":""},
	"takeover":{"name":"机械接管", "action":"暂时接管机械", "reverse":""},
}

static func resolve_anchor(id: String, region: String, markers: Dictionary, entities: Dictionary) -> Dictionary:
	if id.is_empty() or region.is_empty(): return {}
	# Presence, even if invalid, is deliberate: a stale/bad exact entity must
	# not silently turn into a different fallback destination.
	if entities.has(id) or markers.has(id): return _direct(id, id, region, markers, entities)
	var target_id: String = str(OBJECTIVE_TARGETS.get(id, id))
	if not _id_matches_region(target_id, region) or not _id_matches_region(id, region): return {}
	if entities.has(target_id) or markers.has(target_id): return _direct(id, target_id, region, markers, entities)
	if not FACT_DESTINATIONS.has(target_id): return {}
	var result: Dictionary = _direct(id, str(FACT_DESTINATIONS[target_id]), region, markers, entities)
	if not result.is_empty(): result["fallback"] = true
	return result

static func _direct(requested_id: String, anchor_id: String, region: String, markers: Dictionary, entities: Dictionary) -> Dictionary:
	if not _id_matches_region(anchor_id, region) or not _id_matches_region(requested_id, region): return {}
	var is_entity: bool = entities.has(anchor_id)
	var value: Variant = entities.get(anchor_id) if is_entity else markers.get(anchor_id)
	if not value is Dictionary: return {}
	var source: Dictionary = value
	var source_region: String = str(source.get("region", source.get("region_id", "")))
	if not source_region.is_empty() and source_region != region: return {}
	# NPC IDs do not encode a region. Marker metadata is required, rather than
	# inferring that every NPC belongs to the currently displayed world.
	if not is_entity and source_region.is_empty(): return {}
	var point: Variant = _position(source.get("position"))
	if point == null: return {}
	return {"requested_id":requested_id, "anchor_id":anchor_id, "region":region,
		"position":point, "label":str(source.get("name", source.get("label", anchor_id))),
		"source":"entity" if is_entity else "marker", "fallback":false}

static func _id_matches_region(id: String, region: String) -> bool:
	for prefix in ["I1", "F1", "I2"]:
		if id.begins_with(prefix + ":") and region != prefix: return false
	return true

static func _position(value: Variant) -> Variant:
	if value is Vector3: return value if value.is_finite() else null
	if value is Array and value.size() == 3:
		for component in value:
			if not (component is int or component is float) or not is_finite(float(component)): return null
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return null

## At most two contextual suggestions. This is not support/energy/LOS approval,
## a route requirement, a selection change, or a full ability menu.
static func recommended_abilities(target_id: String, target: Dictionary) -> Array[String]:
	# Explicitly assign to a typed container: Godot 4.7 can preserve untyped
	# ternary-array literals across a typed function return boundary.
	var result: Array[String] = []
	result.assign(_recommend_ids(target_id, target).slice(0, 2))
	return result

static func _recommend_ids(target_id: String, target: Dictionary) -> Array:
	var tags: Variant = target.get("tags", [])
	if not tags is Array or target.is_empty(): return []
	if "rotatable" in tags and "photosensitive" in tags: return ["light"]
	if target_id.begins_with("F1:crown_host_"):
		if not ("growable" in tags and "photosensitive" in tags and "thermal" in tags): return []
		if bool(target.get("recovering", false)): return ["heat"]
		return ["growth", "heat"] if _light_level(target) >= 0.25 else ["light", "heat"]
	if "growable" in tags:
		# This story root must receive the physical ring beam, not self-light,
		# for F1:light_receiver. Do not recommend a misleading shortcut here.
		if target_id == "F1:growth": return ["growth"]
		if _light_level(target) >= 0.25: return ["growth"]
		return ["light", "growth"] if "photosensitive" in tags else ["growth"]
	if "conductive" in tags:
		return ["charge", "takeover"] if "mechanical" in tags and "hackable" in tags else ["charge"]
	if "thermal" in tags: return ["heat"]
	if "movable" in tags: return ["push_pull", "force_field"] if "fieldable" in tags else ["push_pull"]
	if "photosensitive" in tags: return ["light"]
	if "echo_operable" in tags: return ["echo", "takeover"] if "mechanical" in tags and "hackable" in tags else ["echo"]
	if "mechanical" in tags and "hackable" in tags: return ["takeover"]
	if "fieldable" in tags: return ["force_field"]
	return []

static func _light_level(target: Dictionary) -> float:
	var level = 0.0
	for key in ["light_level", "environment_light"]:
		var value: Variant = target.get(key, 0.0)
		if (value is int or value is float) and is_finite(float(value)): level = maxf(level, float(value))
	return level

## range_m is the Rules limit, not a promised move length or readiness verdict.
## For targetless blink/decoy, pass the Session's actual planned point (currently
## generated 6m ahead); the locked entity must NOT become their destination.
## in_range only measures Euclidean range; host LOS/support/energy/physics remain
## authoritative. Missing positions omit distance fields instead of inventing 0.
static func ability_hint(ability: String, actor_position: Variant = null, target: Dictionary = {}, aim_point: Variant = null) -> Dictionary:
	if not ACTIONS.has(ability) or not Rules.DEFINITIONS.has(ability): return {}
	var definition: Dictionary = Rules.DEFINITIONS[ability]
	var words: Dictionary = ACTIONS[ability]
	var action: String = str(words.action)
	var tags: Variant = target.get("tags", [])
	if ability == "light" and tags is Array and "rotatable" in tags: action = "点亮并转环30°"
	var reverse: String = str(words.reverse)
	var range_m: float = float(definition.range)
	var targeted: bool = bool(definition.target)
	var range_text: String = ("作用距离 ≤ %.0fm" if targeted else "落点距离上限 %.0fm") % range_m
	var action_text: String = "F " + action + (" · X " + reverse if not reverse.is_empty() else "")
	var result: Dictionary = {"ability":ability, "name":str(words.name), "action":action,
		"name_text":str(words.name), "action_text":action_text, "reverse":reverse, "has_reverse":not reverse.is_empty(),
		"reverse_text":"X " + reverse if not reverse.is_empty() else "无反向作用（当前 X 与 F 相同）",
		"range_m":range_m, "range_text":range_text, "target_required":targeted,
		"note":str(words.get("note", "")), "distance_known":false, "distance_text":"",
		"text":str(words.name) + " · " + action_text + "\n" + range_text}
	if ability == "growth" and str(target.get("id", "")) == "F1:growth": result.note = "先用折光环把光引到幼根"
	var from: Variant = _position(actor_position)
	var to: Variant = _position(target.get("position")) if targeted else _position(aim_point)
	if from == null or to == null: return result
	var distance_m: float = Vector3(from).distance_to(Vector3(to))
	var approach_m: float = maxf(0.0, distance_m - range_m)
	# Match the rules' 1mm range tolerance exactly. Never claim cast readiness.
	var in_range: bool = distance_m <= range_m + 0.001
	var distance_text: String = "距离 %.1fm · 范围内" % distance_m if in_range else "距离 %.1fm · 还需靠近 %.1fm" % [distance_m, ceilf(approach_m * 10.0) / 10.0]
	result.merge({"distance_known":true, "distance_m":distance_m, "height_delta_m":Vector3(to).y - Vector3(from).y,
		"approach_m":approach_m, "in_range":in_range, "distance_text":distance_text}, true)
	result.text += "\n" + distance_text
	return result
