class_name TwinHangar
extends RefCounted
## Pure local ownership and loadout rules; persistence stays in the original Store.
const Catalog = preload("res://scripts/v2/catalog.gd")
const ExplorationRewards = preload("res://scripts/v3/content/dev88_progression/twin_dev88_rewards.gd")
const BUILD_PREFIX := "hangar_v1_"
const FRAME_ORDER := ["tr01","hx02","ag03","nx04","sh05","at06"]
const SLOT_NAMES := {"weapon":"武器","tool":"作业工具","drive":"动力","battery":"电池","utility":"辅助"}
## Existing persisted discoveries only. Derived ownership is a set: no claim or currency.
const UNLOCKS := {
	"opening:rescue_log":["hook_base"],
	"opening:extraction_record":["delivery_base"],
	"opening:other_shore_call":["searchlight_base"],
	"opening:underdeck_worker_bypass":["clearance_base"],
	"boss:I1:harbor_whale":["reinforced_guard"],
	"boss:F1:parasitic_crown":["racing_drive"],
	"I2:canal_calibration":["cargo_winch"],
	"I2:clinic_priority_misroute":["precision_gimbal"],
	"boss:I2:twin_pump_guardian":["long_range_battery"],
	"F2:aligned_timeline":["night_sensor"],
	"boss:F2:mirrorwing_warden":["burst_capacitor"],
	"I3:cooling_overdraft":["cooling_duct"]}
const UNLOCK_LABELS := {
	"opening:rescue_log":"I1 救援调查记录",
	"opening:extraction_record":"I1 撤离记录",
	"opening:other_shore_call":"两岸首次联络",
	"opening:underdeck_worker_bypass":"I1 检修廊调查",
	"boss:I1:harbor_whale":"击败港口鲸机",
	"boss:F1:parasitic_crown":"击败寄生冠兽",
	"I2:canal_calibration":"南湾校准记录",
	"I2:clinic_priority_misroute":"诊疗供水调查",
	"boss:I2:twin_pump_guardian":"击败双泵守卫",
	"F2:aligned_timeline":"F2 时间线核对",
	"boss:F2:mirrorwing_warden":"击败折翼守卫",
	"I3:cooling_overdraft":"I3 换热调查"}
## Exactly FlightBodyV2.configure() base armor and reinforced_guard bonus.
## Display only; never persisted or used to change runtime damage.
const BASE_ARMOR := {"tr01":14.0,"hx02":24.0,"ag03":10.0,"nx04":12.0,"sh05":36.0,"at06":22.0}

static func _failure(code: String, errors: Array = []) -> Dictionary:
	return {"ok":false,"code":code,"errors":errors}

static func ownership(profile: Dictionary) -> Dictionary:
	var generation: Variant = profile.get("generation")
	if not (generation is int or generation is float) or not is_finite(float(generation)) or float(generation) < 0 or floor(float(generation)) != float(generation):
		return _failure("HANGAR_PROFILE_INVALID")
	var personal: Variant = profile.get("personal")
	if not personal is Dictionary or not personal.get("discoveries") is Array or not personal.get("builds") is Array:
		return _failure("HANGAR_PROFILE_INVALID")
	for discovery: Variant in personal.discoveries:
		if not discovery is String: return _failure("HANGAR_DISCOVERIES_INVALID")
	var frames: Dictionary = Catalog.airframes()
	var modules: Dictionary = Catalog.modules()
	var catalog: Dictionary = Catalog.content().get("catalog",{})
	var starter: Array = []
	for frame: String in FRAME_ORDER:
		if not frames.has(frame): return _failure("HANGAR_CATALOG_FRAME_MISSING")
		var build: Dictionary = Catalog.default_build(frame)
		for slot: String in Catalog.SLOT_ORDER:
			var id: String = str(build.slots.get(slot,""))
			if id == "stock" and slot in ["drive","battery"]: id = str(catalog.stock_slot_ids[slot])
			if not modules.has(id): return _failure("HANGAR_STARTER_MODULE_MISSING")
			if id not in starter: starter.append(id)
	var owned: Array = starter.duplicate()
	var rewards: Array = []
	for discovery: String in UNLOCKS:
		for id: String in UNLOCKS[discovery]:
			if not modules.has(id): return _failure("HANGAR_UNLOCK_MODULE_MISSING")
			var unlocked: bool = discovery in personal.discoveries
			if unlocked and id not in owned: owned.append(id)
			rewards.append({"module_id":id,"name":str(modules[id].name),"owned":unlocked,
				"discovery_id":discovery,"condition":str(UNLOCK_LABELS[discovery])})
	for reward: Dictionary in ExplorationRewards.unlocks(personal.discoveries):
		var module_id: String = str(reward.module_id)
		if not modules.has(module_id): return _failure("HANGAR_UNLOCK_MODULE_MISSING")
		if reward.owned and module_id not in owned: owned.append(module_id)
		var row: Dictionary = reward.duplicate(true)
		row["name"] = str(modules[module_id].name)
		row["condition"] = str(row.condition) + "（%d/%d）" % [int(row.found), int(row.total)]
		rewards.append(row)
	return {"ok":true,"frames":FRAME_ORDER.duplicate(),"starter_modules":starter,"modules":owned,"unlocks":rewards}

static func validate(profile: Dictionary, proposed: Dictionary, cargo_kg: float = 0.0) -> Dictionary:
	var owned: Dictionary = ownership(profile)
	if not owned.ok: return owned
	for key: Variant in proposed:
		if key not in ["schema_version","build_id","airframe_id","slots","cosmetic_id"]:
			return _failure("HANGAR_UNKNOWN_BUILD_FIELD")
	if not proposed.get("airframe_id") is String or not proposed.get("slots") is Dictionary:
		return _failure("HANGAR_BUILD_INVALID")
	if not proposed.get("cosmetic_id","ivory_teal") is String:
		return _failure("HANGAR_COSMETIC_INVALID")
	if proposed.get("cosmetic_id","ivory_teal") != "ivory_teal": return _failure("HANGAR_COSMETIC_INVALID")
	var build: Dictionary = proposed.duplicate(true)
	var stock: Dictionary = Catalog.content().get("catalog",{}).get("stock_slot_ids",{})
	for slot: String in ["drive","battery"]:
		if build.slots.get(slot) == "stock": build.slots[slot] = str(stock[slot])
	# Catalog's nonempty owned lists preserve its existing ownership/mass/PU/
	# thrust/cargo/mount/rotor checks. Never pass loaner=true or an empty owned set.
	var resolved: Dictionary = Catalog.resolve_build(build,cargo_kg,owned.frames,owned.modules,false)
	if not resolved.valid: return {"ok":false,"code":"HANGAR_BUILD_REJECTED","errors":resolved.errors,"resolved":resolved}
	build = resolved.build.duplicate(true)
	build["build_id"] = BUILD_PREFIX+str(build.airframe_id)
	resolved["build"] = build.duplicate(true)
	var armor: float = float(BASE_ARMOR[build.airframe_id])
	if build.slots.get("utility") == "reinforced_guard": armor += 12.0
	return {"ok":true,"build":build,"resolved":resolved,"armor":armor,"owned":owned}

static func launch_build(profile: Dictionary, frame_id: String = "") -> Dictionary:
	var owned: Dictionary = ownership(profile)
	if not owned.ok: return owned
	var selected: String = ""
	var meta: Variant = profile.personal.get("hangar",{})
	if not meta is Dictionary: return _failure("HANGAR_METADATA_INVALID")
	if not meta.is_empty():
		if meta.get("schema_version") != 1 or not meta.get("selected_build_id") is String:
			return _failure("HANGAR_METADATA_INVALID")
		selected = str(meta.selected_build_id)
		if not selected.begins_with(BUILD_PREFIX): return _failure("HANGAR_METADATA_INVALID")
	if frame_id.is_empty():
		frame_id = selected.trim_prefix(BUILD_PREFIX) if selected.begins_with(BUILD_PREFIX) else "tr01"
	if frame_id not in owned.frames: return _failure("HANGAR_FRAME_NOT_OWNED")
	var id: String = BUILD_PREFIX+frame_id
	var found: Dictionary = {}
	for row: Variant in profile.personal.builds:
		if not row is Dictionary or not row.get("build_id") is String: return _failure("HANGAR_SAVED_BUILDS_INVALID")
		if row.build_id == id:
			if not found.is_empty(): return _failure("HANGAR_DUPLICATE_BUILD_ID")
			found = row.duplicate(true)
	if not found.is_empty():
		if found.get("airframe_id") != frame_id: return _failure("HANGAR_SAVED_FRAME_MISMATCH")
		return validate(profile,found)
	if selected == id: return _failure("HANGAR_SELECTED_BUILD_MISSING")
	return validate(profile,Catalog.default_build(frame_id))

static func module_options(profile: Dictionary, draft: Dictionary, slot: String) -> Array:
	if slot not in Catalog.SLOT_ORDER: return []
	var owned: Dictionary = ownership(profile)
	if not owned.get("ok",false): return []
	var modules: Dictionary = Catalog.modules()
	var rows: Array = []
	for id: String in modules:
		if modules[id].slot != slot: continue
		var candidate: Dictionary = draft.duplicate(true)
		candidate["slots"] = draft.get("slots",{}).duplicate(true)
		candidate.slots[slot] = id
		var resolved: Dictionary = Catalog.resolve_build(candidate,0.0,owned.frames,owned.modules,false)
		var compatible: bool = true
		for error: Dictionary in resolved.errors:
			if error.code in ["BUILD_SLOT_MISMATCH","BUILD_MOUNT_CONFLICT","BUILD_ROTOR_INTERSECTION","BUILD_UNKNOWN_FRAME"]:
				compatible = false
		rows.append({"id":id,"name":str(modules[id].name),"owned":id in owned.modules,"compatible":compatible,
			"valid":resolved.valid,"errors":resolved.errors,"mass_kg":float(modules[id].get("mass_kg",modules[id].get("mass_delta_kg",0.0))),
			"power_pu":float(modules[id].power_pu)})
	return rows

static func prepare_save(profile: Dictionary, proposed: Dictionary, active_session: bool, expected_generation: int = -1) -> Dictionary:
	if active_session: return _failure("HANGAR_ACTIVE_SESSION")
	if expected_generation >= 0 and int(profile.get("generation",-2)) != expected_generation:
		return _failure("HANGAR_SNAPSHOT_STALE")
	var checked: Dictionary = validate(profile,proposed)
	if not checked.ok: return checked
	var builds: Array = []
	var ids: Array = []
	for row: Variant in profile.personal.builds:
		if not row is Dictionary or not row.get("build_id") is String: return _failure("HANGAR_SAVED_BUILDS_INVALID")
		if row.build_id in ids: return _failure("HANGAR_DUPLICATE_BUILD_ID")
		ids.append(row.build_id)
		if row.build_id != checked.build.build_id: builds.append(row.duplicate(true))
	builds.append(checked.build.duplicate(true))
	var changes: Dictionary = {"personal.builds":builds,
		"personal.hangar":{"schema_version":1,"selected_build_id":str(checked.build.build_id)}}
	var digest: String = JSON.stringify(changes,"",true,true).sha256_text()
	var transaction: Dictionary = {"id":"hangar-v1:"+str(int(profile.get("generation",0)))+":"+digest,"set":changes}
	return {"ok":true,"transaction":transaction,"build":checked.build,"resolved":checked.resolved,
		"expected_generation":int(profile.get("generation",0)),"no_op":JSON.parse_string(JSON.stringify(builds,"",true,true)) == profile.personal.builds and JSON.parse_string(JSON.stringify(changes["personal.hangar"],"",true,true)) == profile.personal.get("hangar",{})}

static func error_text(result: Dictionary) -> String:
	var messages: Dictionary = {"HANGAR_ACTIVE_SESSION":"飞行中的配装保持不变；请先保存战况并返回机库。",
		"HANGAR_SNAPSHOT_STALE":"存档已更新，请刷新机库后再保存。","HANGAR_SELECTED_BUILD_MISSING":"已选配装缺失，原存档保留，请检查记录。",
		"HANGAR_FRAME_NOT_OWNED":"此机体当前不可用。","HANGAR_PROFILE_INVALID":"机库存档结构无法读取，原档未改动。"}
	var errors: Array = result.get("errors",[])
	if not errors.is_empty():
		var labels: Dictionary = {"BUILD_MODULE_NOT_OWNED":"模块尚未解锁","BUILD_FRAME_NOT_OWNED":"机体尚未拥有","BUILD_OVER_POWER":"供电预算不足",
			"BUILD_OVER_MASS":"起飞质量超限","BUILD_OVER_CARGO":"载荷超限","BUILD_LOW_THRUST_RATIO":"推重比不足","BUILD_MOUNT_CONFLICT":"挂点或外形冲突",
			"BUILD_ROTOR_INTERSECTION":"模块侵入旋翼范围","BUILD_SLOT_MISMATCH":"模块槽位不符","BUILD_MISSING_SLOT":"必须保留完整五槽配装"}
		var parts: PackedStringArray = []
		for error: Dictionary in errors:
			parts.append(str(labels.get(error.code,error.code))+ ("（"+str(SLOT_NAMES.get(error.get("slot",""),error.get("slot","")))+"）" if not str(error.get("slot","")).is_empty() else ""))
		return "；".join(parts)
	return str(messages.get(result.get("code",""),"配装未保存："+str(result.get("code","unknown"))))
