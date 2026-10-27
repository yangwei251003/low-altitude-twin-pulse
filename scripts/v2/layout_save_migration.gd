class_name LayoutSaveMigrationWorldUI
extends RefCounted
## Pure migration plan: only spatial fields change; the repository owns atomic persistence.
const Layout = preload("res://scripts/v2/region_layout.gd")
const REVISION = 1

static func plan(profile: Dictionary, content: Dictionary, supplied_layouts: Dictionary = {}) -> Dictionary:
	var current = int(profile.get("world", {}).get("layout_revision", 0))
	if current > REVISION: return {"ok":false,"error":"LAYOUT_REVISION_NEWER"}
	if current == REVISION: return {"ok":true,"changed":false}
	var layouts: Dictionary = supplied_layouts.duplicate(true)
	var regions: Dictionary = {}
	for region in content.get("regions", []):
		var rid = str(region.id)
		regions[rid] = region
		if not layouts.has(rid): layouts[rid] = Layout.get_layout(rid)
		if layouts[rid].is_empty() or int(layouts[rid].get("revision", 0)) != REVISION:
			return {"ok":false,"error":"LAYOUT_MIGRATION_MISSING_REGION:"+rid}
	if regions.size() != 4: return {"ok":false,"error":"LAYOUT_MIGRATION_CONTENT_INVALID"}
	var world: Dictionary = profile.world.duplicate(true)
	var checkpoint: Variant = profile.campaign.active_checkpoint
	if checkpoint is Dictionary:
		checkpoint = checkpoint.duplicate(true)
		var job: Dictionary = {}
		for value in content.get("missions", []) + content.get("airframe_challenges", []) + content.get("mode_configs", []):
			if str(value.id) == str(checkpoint.get("job_id", "")): job = value; break
		if checkpoint.has("run_state") and not checkpoint.run_state is Dictionary:
			return {"ok":false,"error":"LAYOUT_MIGRATION_INVALID_RUN_STATE"}
		var run: Dictionary = checkpoint.get("run_state", {})
		for field in ["cargo_records", "stage_start_cargo"]:
			if not run.get(field, {}) is Dictionary: return {"ok":false,"error":"LAYOUT_MIGRATION_INVALID_CARGO_RECORDS"}
		if not job.is_empty() and not run.is_empty():
			var rid = str(job.region_id)
			if not regions.has(rid): return {"ok":false,"error":"LAYOUT_MIGRATION_UNKNOWN_JOB_REGION:"+rid}
			for field in ["cargo_records", "stage_start_cargo"]:
				for id in run.get(field, {}):
					if not run[field][id] is Dictionary: return {"ok":false,"error":"LAYOUT_MIGRATION_INVALID_CARGO_RECORD:"+str(id)}
					var result = _migrate_cargo(str(id), run[field][id], run, job, regions[rid], layouts[rid])
					if not result.ok: return result
					run[field][id] = result.record
		elif not run.get("cargo_records", {}).is_empty() or not run.get("stage_start_cargo", {}).is_empty():
			# Unknown jobs with physical cargo need deliberate recovery, never silent deletion.
			return {"ok":false,"error":"LAYOUT_MIGRATION_UNKNOWN_CARGO_JOB:"+str(checkpoint.get("job_id", ""))}
		checkpoint["layout_revision"] = REVISION
	if not world.get("combat_regions", {}) is Dictionary: return {"ok":false,"error":"LAYOUT_MIGRATION_INVALID_COMBAT_STATE"}
	var directors: Dictionary = world.get("combat_regions", {}).duplicate(true)
	for rid in directors:
		if not layouts.has(rid): return {"ok":false,"error":"LAYOUT_MIGRATION_UNKNOWN_COMBAT_REGION:"+str(rid)}
		if not directors[rid] is Dictionary: return {"ok":false,"error":"LAYOUT_MIGRATION_INVALID_COMBAT_STATE"}
		var changed = _migrate_director(directors[rid], layouts[rid])
		if not changed.ok: return changed
		directors[rid] = changed.saved
	if world.has("combat_regions"): world["combat_regions"] = directors
	world["layout_revision"] = REVISION
	return {"ok":true,"changed":true,"set":{"world":world,"campaign.active_checkpoint":checkpoint}}

static func _cargo_action(id: String, record: Dictionary, run: Dictionary, job: Dictionary) -> Dictionary:
	var stages: Array = job.get("stages", [job])
	var current_stage = 0
	for index in range(stages.size()):
		if str(stages[index].get("id", "")) == str(run.get("stage_id", "")): current_stage = index; break
	# A carried staged item may already have been picked up again this stage.
	# Its recovery home belongs to that completed pickup, not the original source.
	if str(record.get("state",""))=="carried" and current_stage<stages.size():
		var active: Array=stages[current_stage].get("optional_actions" if bool(run.get("optional",false)) else "actions",[])
		var cursor=clampi(int(run.get("action_index",0)),0,active.size())
		for index in range(cursor-1,-1,-1):
			var action: Dictionary=active[index]
			if str(action.get("type",""))=="pickup" and str(action.get("cargo_id",""))==id:return action
	var source: Dictionary = {}
	var staged_delivery: Dictionary = {}
	var staged_pickup: Dictionary = {}
	for index in range(stages.size()):
		for action in stages[index].get("actions", []) + stages[index].get("optional_actions", []):
			if str(action.get("cargo_id", "")) != id: continue
			if str(action.get("type", "")) == "pickup":
				if bool(action.get("reuse_staged_instance", false)):
					if index >= current_stage and staged_pickup.is_empty(): staged_pickup = action
				elif source.is_empty() or str(stages[index].get("id", "")) == str(record.get("stage_id", "")):
					source = action
			if index <= current_stage and str(action.get("cargo_disposition", "")) == "staged": staged_delivery = action
	if str(record.get("state", "")) == "staged":
		if not staged_pickup.is_empty(): return staged_pickup
		if not staged_delivery.is_empty(): return staged_delivery
	return source

static func _migrate_cargo(id: String, source: Dictionary, run: Dictionary, job: Dictionary, region: Dictionary, layout: Dictionary) -> Dictionary:
	var record: Dictionary = source.duplicate(true)
	if str(record.get("state", "")) == "delivered": return {"ok":true,"record":record}
	var action = _cargo_action(id, record, run, job)
	var poi_id = str(action.get("poi_id", region.spawn_poi))
	var positions: Dictionary = layout.get("poi_positions", {})
	if not positions.has(poi_id): return {"ok":false,"error":"LAYOUT_MIGRATION_CARGO_POI:"+id+":"+poi_id}
	var xy: Array = positions[poi_id]
	var offset: Array = action.get("offset_xz_m", [0, 0])
	var desired = Vector3(float(xy[0])+float(offset[0]), 0, float(xy[1])+float(offset[1]))
	var radius = minf(3.0, maxf(0.0, float(action.get("radius_m", 5.0))-1.0))
	var point = _safe_anchor(layout, desired, radius)
	if not point.is_finite(): return {"ok":false,"error":"LAYOUT_MIGRATION_UNSAFE_CARGO:"+id+":"+poi_id}
	point.y += 0.8 if str(record.get("state", "")) == "staged" else 0.7
	record["home"] = _vec(point)
	# A saved body.position overrides home in TaskRunner, so migrate both.
	record["position"] = _vec(point)
	for key in ["linear_velocity", "angular_velocity"]:
		if record.has(key): record[key] = [0.0, 0.0, 0.0]
	return {"ok":true,"record":record}

static func _safe_anchor(layout: Dictionary, desired: Vector3, radius: float) -> Vector3:
	var offsets: Array[Vector2] = [Vector2.ZERO]
	for distance in [minf(1.25, radius), minf(2.5, radius), radius]:
		if distance <= 0.0: continue
		for direction in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			offsets.append(direction*distance)
	for offset in offsets:
		var point = desired+Vector3(offset.x, 0, offset.y)
		var surface: Dictionary = Layout.surface(layout, point, true)
		if bool(surface.water): continue
		var safe = true
		for corner in [Vector3(.6,0,.6),Vector3(.6,0,-.6),Vector3(-.6,0,.6),Vector3(-.6,0,-.6)]:
			var edge: Dictionary = Layout.surface(layout, point+corner, true)
			if bool(edge.water) or absf(float(edge.height)-float(surface.height))>.15: safe=false; break
		if not safe: continue
		for structure in layout.get("structures", []):
			var relative = Vector2(point.x-float(structure.x), point.z-float(structure.z)).rotated(-float(structure.get("yaw", 0)))
			if absf(relative.x)<float(structure.w)*.5+.8 and absf(relative.y)<float(structure.l)*.5+.8:
				safe=false; break
		if safe: return Vector3(point.x, float(surface.height), point.z)
	return Vector3(INF, INF, INF)

static func _entry(layout: Dictionary, old_id: String) -> Dictionary:
	var entries: Array = layout.get("entries", [])
	if entries.is_empty(): return {}
	for value in entries:
		if str(value.id) == old_id: return value
	return entries[posmod(old_id.hash(), entries.size())]

static func _rebind_spatial(record: Dictionary, entry: Dictionary, formation_index: int = 0) -> void:
	var point = _point(entry.position)
	var goal = _point(entry.target)
	var direction = goal-point
	direction.y = 0
	direction = direction.normalized() if direction.length_squared()>.001 else Vector3.FORWARD
	record["entry_id"] = str(entry.id)
	record["entry"] = _vec(point)
	record["target"] = _vec(goal)
	record["direction"] = _vec(direction)
	var body_point = point+Vector3(formation_index*2.3, 0, 0)
	if record.has("unit_id"):
		record["position"] = _vec(body_point)
		if str(record.get("status", "")) != "retired": record["status"] = "virtual"
		if record.get("brain") is Dictionary:
			var brain: Dictionary = record.brain
			brain["home"] = _vec(body_point)
			brain["patrol_target"] = _vec(goal)
			brain["state"] = "patrol"
			brain["heading"] = atan2(-direction.x, -direction.z)
			brain["last_seen_position"] = _vec(body_point)
			brain["last_seen_velocity"] = [0.0,0.0,0.0]
			brain["memory_age"] = 999.0
			brain["confidence"] = 0.0
			brain["reaction_time"] = 0.0
			brain["report_progress"] = 0.0
			brain["noise_position"] = _vec(body_point)
			brain["noise_left"] = 0.0
			brain["aim_error"] = [0.0,0.0,0.0]
			brain["aim_left"] = 0.0
			brain["sense_left"] = 0.0
			brain["lost_left"] = 0.0
			# Keep reported, RNG, unit ID and damage_state: changing geography is not a new enemy.
	else:
		record["progress"] = 0.0
		record["eta"] = maxf(3.0, float(record.get("eta", 0.0)))
		record["ttl"] = maxf(22.0, float(record.get("ttl", 0.0)))

static func _migrate_director(source: Dictionary, layout: Dictionary) -> Dictionary:
	var saved: Dictionary = source.duplicate(true)
	if not saved.get("pending", {}) is Dictionary or not saved.get("units", []) is Array:
		return {"ok":false,"error":"LAYOUT_MIGRATION_INVALID_COMBAT_STATE"}
	var pending: Dictionary = saved.get("pending", {})
	if not pending.is_empty():
		var entry = _entry(layout, str(pending.get("entry_id", pending.get("encounter_id", ""))))
		if entry.is_empty(): return {"ok":false,"error":"LAYOUT_MIGRATION_NO_ENEMY_ENTRY:"+str(layout.region_id)}
		_rebind_spatial(pending, entry)
		saved["pending"] = pending
	var formation: Dictionary = {}
	for unit in saved.get("units", []):
		if not unit is Dictionary: return {"ok":false,"error":"LAYOUT_MIGRATION_INVALID_COMBAT_UNIT"}
		var entry = _entry(layout, str(unit.get("entry_id", unit.get("encounter_id", ""))))
		if entry.is_empty(): return {"ok":false,"error":"LAYOUT_MIGRATION_NO_ENEMY_ENTRY:"+str(layout.region_id)}
		var group = str(unit.get("encounter_id", unit.get("unit_id", "")))
		var index = int(formation.get(group, 0))
		formation[group] = index+1
		_rebind_spatial(unit, entry, index)
	saved["noise_position"] = [0.0,0.0,0.0]
	saved["noise_age"] = 999.0
	saved["layout_revision"] = REVISION
	# Existing _entry_legal still gates restoration by real collision, visibility and safe zones.
	return {"ok":true,"saved":saved}

static func _point(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

static func _vec(value: Vector3) -> Array:
	return [value.x, value.y, value.z]
