class_name TaskRunnerV2
extends Node3D

signal stage_ready(stage: Dictionary)
signal failed(reason: String)
signal action_changed
signal action_completed(action: Dictionary)

var world: RegionWorldV2
var pilot: FlightBodyV2
var combat: CombatV2
var stage: Dictionary = {}
var actions: Array = []
var action_index = 0
var progress_s = 0.0
var elapsed_s = 0.0
var condition = ""
var pending = false
var marker: Node3D
var facility: WorkFacility
var cargo: Dictionary = {}
var action_started = false
var wave_index = 0
var wave_wait = 0.0
var warning_observed = false
var path_distance = 0.0
var last_scan_position = Vector3.ZERO
var escort_path: PackedVector3Array = []
var escort_index = 0
var escort_water_route: Dictionary = {}
var navigation: AStarGrid2D
var optional = false
var cargo_records: Dictionary = {}
var preparation_flags: Dictionary = {}
var stage_start_cargo: Dictionary = {}
var stage_start_flags: Dictionary = {}
var metrics: Dictionary = {}
var extraction_manifest: Array[Dictionary] = []
var delivered_reward_parts = 0
var gate_normal = Vector3.FORWARD
var gate_previous_position = Vector3.ZERO
var gate_crossed = false
var gate_entry_side = 0.0
var action_enemies: Array = []
var last_overheated = false
var last_target = Vector3.ZERO
var has_last_target = false
var safe_stop_targets: Array[int] = []
var escort_released_stops: Array[int] = []
var module_specs: Dictionary = {}
var facility_kind = ""
var action_elapsed_s = 0.0
var was_in_sweep = false
var delivery_invalid_s = 0.0
var staged_restorations: Array[String] = []

func _ready() -> void:
	module_specs = CatalogV2.modules()
	combat.warning_seen.connect(func(): warning_observed = true)
	pilot.collision_event.connect(_on_collision)
	pilot.disabled.connect(func(): metrics["disabled_count"] = int(metrics.get("disabled_count",0))+1; _fail("无人机受损停机，请重试当前阶段"))
	navigation = AStarGrid2D.new()
	navigation.region = Rect2i(0,0,120,100)
	navigation.cell_size = Vector2(5,5)
	navigation.offset = Vector2(2.5,2.5)
	navigation.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	navigation.update()
	for item in world.obstacles:
		for x in range(maxi(0,floori((item.x-item.w/2-2)/5)),mini(120,ceili((item.x+item.w/2+2)/5))):
			for z in range(maxi(0,floori((item.z-item.l/2-2)/5)),mini(100,ceili((item.z+item.l/2+2)/5))): navigation.set_point_solid(Vector2i(x,z))

func start_stage(value: Dictionary, is_optional = false, resume_state: Dictionary = {}) -> void:
	_cleanup_action()
	combat.clear_enemies()
	if not resume_state.is_empty():
		_restore_cargo_records(resume_state.get("cargo_records",{}))
		preparation_flags = resume_state.get("preparation_flags",{}).duplicate(true)
		stage_start_cargo = resume_state.get("stage_start_cargo",{}).duplicate(true)
		stage_start_flags = resume_state.get("stage_start_flags",{}).duplicate(true)
	elif str(stage.get("id","")) == str(value.get("id","")) and optional == is_optional and not stage.is_empty():
		_restore_cargo_records(stage_start_cargo)
		preparation_flags = stage_start_flags.duplicate(true)
	else:
		stage_start_cargo = cargo_records.duplicate(true)
		stage_start_flags = preparation_flags.duplicate(true)
	stage = value.duplicate(true)
	actions = stage.get("optional_actions" if is_optional else "actions", []).duplicate(true)
	optional = is_optional
	action_index = 0
	progress_s = 0
	pending = false
	elapsed_s = 0
	condition = ""
	has_last_target = false
	extraction_manifest.clear()
	delivered_reward_parts = 0
	staged_restorations.clear()
	metrics = {"collision_count":0,"clearance_collision_count":0,"disabled_count":0,"replacement_count":0,"landing_count":0,"overheat_count":0,"mechanical_sweep_intrusions":0,"cargo_integrity_min":1.0,"facility_integrity_min":1.0,"escort_integrity_min":1.0,"swing_above_s":0.0,"delivery_errors_m":[]}
	last_overheated = false
	if not resume_state.is_empty():
		action_index = clampi(int(resume_state.get("action_index",0)),0,actions.size())
		elapsed_s = maxf(0.0,float(resume_state.get("elapsed_s",0)))
		metrics.merge(resume_state.get("metrics",{}),true)
		delivered_reward_parts = int(resume_state.get("delivered_reward_parts",0))
		for item in resume_state.get("extraction_manifest",[]): extraction_manifest.append(item.duplicate(true))
		for id in resume_state.get("staged_restorations",[]): staged_restorations.append(str(id))
	world.pin_pois(stage.get("poi_ids", []))
	_prepare_action()

func resume_stage(value: Dictionary, saved: Dictionary, is_optional = false) -> bool:
	if str(saved.get("stage_id","")) != str(value.get("id","")): return false
	# Restore retained cargo and index atomically; completed pickups must not respawn.
	start_stage(value,is_optional,saved)
	return true

func current_action() -> Dictionary:
	return actions[action_index] if action_index < actions.size() else {}

func target_position() -> Vector3:
	var action = current_action()
	if action.is_empty(): return pilot.global_position
	var water_route=_water_route_for_action(action)
	if not water_route.is_empty():
		var point: Array=water_route.points_xz_m[0]
		var water_target=Vector3(float(point[0]),float(world.layout.water_level)+float(action.get("target_height_m",2.8)),float(point[1]))
		if is_instance_valid(facility) and not facility.vessel_kind.is_empty():
			water_target.x=facility.global_position.x;water_target.z=facility.global_position.z
		return water_target
	var p = world.poi_position(str(action.get("poi_id",world.region.get("spawn_poi",str(world.region.id)+"-P01"))))
	var offset: Array = action.get("offset_xz_m", [0.0,0.0])
	p.x += float(offset[0]); p.z += float(offset[1])
	p.y = world.surface_height(p) + float(action.get("target_height_m", 2.8))
	return p

func _cleanup_action() -> void:
	world.set_maintenance_window(Vector3.ZERO,false,false)
	escort_water_route = {}
	if is_instance_valid(marker): marker.queue_free()
	if is_instance_valid(facility):
		metrics["facility_integrity_min"] = minf(float(metrics.get("facility_integrity_min",1.0)),facility.hp/100.0)
		if facility_kind == "escort": metrics["escort_integrity_min"] = minf(float(metrics.get("escort_integrity_min",1.0)),facility.hp/100.0)
		facility.queue_free()
	combat.facility = null
	marker = null
	facility = null
	facility_kind = ""

func _prepare_action() -> void:
	_cleanup_action()
	progress_s = 0
	action_started = false
	wave_index = 0
	wave_wait = 0
	path_distance = 0
	escort_index = 0
	gate_crossed = false
	gate_entry_side = 0.0
	action_elapsed_s = 0.0
	was_in_sweep = false
	delivery_invalid_s = 0.0
	action_enemies.clear()
	escort_released_stops.clear()
	last_scan_position = pilot.global_position
	if action_index >= actions.size(): _finish_stage(); return
	var action = current_action()
	var target = target_position()
	if bool(action.get("warning_observed_required",false)): warning_observed = false
	if combat.has_method("configure_objective"): combat.configure_objective(action,target)
	world.pin_pois([action.poi_id])
	marker = Node3D.new()
	add_child(marker)
	var support_y = world.surface_height(target)
	marker.global_position = Vector3(target.x,support_y+0.2,target.z)
	GameVisuals.ring(marker,Vector3.ZERO,float(action.get("radius_m",3.0)),Color("a5f3c7"),0.15)
	if action.type == "gate":
		var approach: Vector3 = target - (last_target if has_last_target else pilot.global_position)
		approach.y = 0
		gate_normal = approach.normalized() if approach.length()>0.2 else Vector3.FORWARD
		gate_previous_position = pilot.global_position
		var signed_distance = (pilot.global_position-target).dot(gate_normal)
		if absf(signed_distance)>0.2: gate_entry_side = signf(signed_distance)
		var ring = GameVisuals.ring(marker,Vector3(0,target.y-support_y-0.2,0),2.8,Color("cde8ad"),0.2)
		ring.rotation.x = PI/2
		marker.rotation.y = atan2(gate_normal.x,gate_normal.z)
		GameVisuals.cylinder(marker,Vector3(-3,(target.y-support_y)/2,0),0.07,target.y-support_y,Color("b8dcd3"))
		GameVisuals.cylinder(marker,Vector3(3,(target.y-support_y)/2,0),0.07,target.y-support_y,Color("b8dcd3"))
	if action.type == "pickup": _ensure_cargo(action)
	if action.type in ["defend","escort"]:
		facility_kind = str(action.type)
		facility = WorkFacility.new()
		escort_water_route=_water_route_for_action(action)
		if not escort_water_route.is_empty():facility.vessel_kind=str(escort_water_route.get("vessel","maintenance_boat"))
		add_child(facility)
		facility.global_position = Vector3(target.x,float(world.layout.water_level)+.25 if not escort_water_route.is_empty() else world.surface_height(target)+1.1,target.z)
		facility.failure.connect(func(): pending = true; failed.emit("设施受损，请从本阶段重新出发"))
		combat.facility = facility
		if action.type == "escort":
			escort_path.clear()
			safe_stop_targets.clear()
			if not escort_water_route.is_empty():
				if not _prepare_water_escort(action):return
			else:
				var route: Array = action.get("escort_path", [])
				var previous = Vector2i(clampi(int(target.x/5),0,119),clampi(int(target.z/5),0,99))
				for route_index in range(route.size()):
					var point: Variant = route[route_index]
					var destination = world.poi_position(str(point)) if point is String else Vector3(float(point[0]),1.1,float(point[1]))
					var goal = Vector2i(clampi(int(destination.x/5),0,119),clampi(int(destination.z/5),0,99))
					var segment = navigation.get_point_path(previous,goal)
					if segment.is_empty(): _fail("护送航路不可达，请检查场景路径"); return
					for p in segment: escort_path.append(Vector3(p.x,world.surface_height(Vector3(p.x,0,p.y))+1.1,p.y))
					if route_index in action.get("safe_stop_indices",[]): safe_stop_targets.append(escort_path.size()-1)
					previous = goal
	action_changed.emit()

func _ensure_cargo(action: Dictionary) -> void:
	var id = str(action.cargo_id)
	if bool(action.get("reuse_staged_instance",false)):
		if not cargo_records.has(id) or str(cargo_records[id].get("state","")) != "staged": _fail("没有可取回的暂存货物，请恢复阶段检查点"); return
	elif cargo_records.has(id) and str(cargo_records[id].get("state","")) == "delivered": _fail("该货物已交付，不能重复生成"); return
	if cargo.has(id) and is_instance_valid(cargo[id]): return
	if not cargo_records.has(id):
		var home = target_position()+Vector3(0,-2.1,0)
		cargo_records[id] = {"state":"available","mass_kg":float(action.get("cargo_kg",1.0)),"home":[home.x,home.y,home.z],"value":int(action.get("cargo_value",0)),"integrity":1.0,"stage_id":str(stage.get("id",""))}
	_spawn_cargo(id,cargo_records[id])

func _spawn_cargo(id: String, record: Dictionary) -> void:
	var body = RigidBody3D.new()
	body.name = "TaskCargo"
	body.mass = maxf(0.1,float(record.mass_kg))
	body.collision_layer = 8
	body.collision_mask = 1
	body.continuous_cd = true
	body.contact_monitor = true
	body.max_contacts_reported = 8
	var collider = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(0.7,0.5,0.65)
	collider.shape = box
	body.add_child(collider)
	GameVisuals.box(body,Vector3.ZERO,box.size,Color("d0c689"))
	GameVisuals.box(body,Vector3(0,0.27,0),Vector3(0.3,0.03,0.45),Color("438b7d"))
	body.set_meta("cargo_id",id)
	body.set_meta("previous_velocity",Vector3.ZERO)
	body.set_meta("impact_cooldown",0.0)
	add_child(body)
	var home: Array = record.home
	body.global_position = Vector3(home[0],home[1],home[2])
	body.set_meta("home",body.global_position)
	body.freeze = str(record.state) == "staged"
	cargo[id] = body

func recover_cargo() -> bool:
	var action = current_action()
	var id = str(action.get("cargo_id",pilot.cargo_id))
	if not cargo_records.has(id) or str(cargo_records[id].state) == "delivered": return false
	var body = pilot.release_cargo(id)
	if not is_instance_valid(body): body = cargo.get(id)
	if not is_instance_valid(body): _spawn_cargo(id,cargo_records[id]); body = cargo[id]
	var home: Array = cargo_records[id].home
	if action.has("recovery_poi_id"):
		var p = world.poi_position(str(action.recovery_poi_id))+Vector3(0,0.7,0)
		home = [p.x,p.y,p.z]
		cargo_records[id].home = home
	body.freeze = true
	body.global_position = Vector3(home[0],home[1],home[2])
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.set_meta("home",body.global_position)
	cargo_records[id].state = "available"
	body.freeze = false
	metrics["replacement_count"] = int(metrics.get("replacement_count",0))+1
	return true

func _physics_process(delta: float) -> void:
	if pending or actions.is_empty() or not pilot.enabled: return
	elapsed_s += delta
	action_elapsed_s += delta
	var action = current_action()
	var target = target_position()
	if str(stage.get("id","")).begins_with("M09-") and action.has("safe_window_s"):
		world.set_maintenance_window(target,true,_safe_window(action))
	var position_m = pilot.global_position
	var horizontal_distance = Vector2(position_m.x-target.x, position_m.z-target.z).length()
	var support = world.surface_at(target)
	if is_instance_valid(marker):
		if not escort_water_route.is_empty():marker.global_position=Vector3(target.x,float(world.layout.water_level)+.12,target.z)
		else:marker.global_position.y=float(support.get("height",0.0))+0.2
	var relative_velocity: Vector3 = pilot.linear_velocity-Vector3(support.get("surface_velocity",Vector3.ZERO))
	var relative_height = position_m.y-float(support.get("height",0.0))
	var speed = Vector2(relative_velocity.x,relative_velocity.z).length()
	var tool = str(pilot.build.slots.tool)
	var needed_tool = str(action.get("tool_id", ""))
	var equipped: Dictionary = module_specs.get(tool,{})
	var needed: Dictionary = module_specs.get(needed_tool,{})
	var tool_ok = needed_tool.is_empty() or tool == needed_tool or (not needed.is_empty() and str(equipped.get("ability","")) == str(needed.get("ability","missing")))
	if "basic_light" in stage.get("equipment_plan",{}).get("utility_required",[]): tool_ok = tool_ok and str(pilot.build.slots.utility) == "searchlight_base"
	var radius = float(action.get("radius_m",5.0))
	var close = horizontal_distance <= radius
	var stable = speed <= float(action.get("max_speed_mps",2.0))
	var held = bool(pilot.command.get("interact",false))
	condition = ""
	_update_metrics(delta)
	if action.has("enemy_roles") and not action_started and horizontal_distance < 38.0:
		_spawn_wave(action,target)
	if not tool_ok: condition = "工具不匹配，请在安全服务柜更换"
	elif not close: condition = "距目标 %.0f m" % horizontal_distance
	elif not stable: condition = "减速停稳"
	else: condition = "保持交互"
	var within_height = absf(position_m.y-target.y)<=3.0
	var valid = close and stable and tool_ok and held and within_height
	match str(action.type):
		"gate":
			_check_gate_crossing(position_m,target,action)
			valid = gate_crossed
			condition = "穿过门平面  |  高度 %.1f m  |  距离 %.0f m" % [target.y,horizontal_distance]
		"scan":
			if action.has("scan_facing_deg"):
				var bearing = fposmod(rad_to_deg(atan2(position_m.x-target.x,position_m.z-target.z)),360)
				var angle_delta = absf(wrapf(bearing - float(action.scan_facing_deg),-180,180))
				valid = valid and angle_delta < 38 and horizontal_distance >= 1.5
				if angle_delta >= 38: condition = "绕到标记朝向 %.0f°" % float(action.scan_facing_deg)
			if valid: path_distance += position_m.distance_to(last_scan_position)
			last_scan_position = position_m
			if action.has("scan_path_m") and path_distance < float(action.scan_path_m):
				progress_s = 0
				condition = "扫描覆盖 %.1f / %.1f m" % [path_distance,float(action.scan_path_m)]
				return
		"pickup":
			valid = valid and relative_height >= 1.2 and relative_height <= 3.0 and not pilot.cargo_items.has(str(action.cargo_id))
			var body: RigidBody3D = cargo.get(str(action.cargo_id))
			valid = valid and is_instance_valid(body)
			if is_instance_valid(body):
				var aligned = Vector2(position_m.x-body.global_position.x,position_m.z-body.global_position.z).length() <= 0.85
				valid = valid and aligned and position_m.distance_to(body.global_position) <= float(pilot.stats.get("modifiers",{}).get("tool_range_m",5.0))
				if not aligned: condition = "对准货物上方"
			if relative_height < 1.2 or relative_height > 3.0: condition = "悬停高度 1.2 - 3.0 m"
			if bool(action.get("optional",false)): condition += "；可跳过或立即撤离"
		"deliver":
			if not pilot.cargo_items.has(str(action.cargo_id)): _try_recover_pickup(action,tool_ok,held,stable)
			valid = valid and pilot.cargo_items.has(str(action.cargo_id)) and pilot.cargo_swing() <= float(action.get("max_swing_deg",25)) and relative_height < 4.2
			if not pilot.cargo_items.has(str(action.cargo_id)): condition = "先领取任务货物；丢失时可恢复至领取座"
			elif pilot.cargo_swing() > float(action.get("max_swing_deg",25)): condition = "等待货物摆动稳定"
		"return":
			valid = close and stable and pilot.is_landed() and absf(pilot.linear_velocity.y)<=float(action.get("max_descent_mps",0.8))
			condition = "在标记内缓降至地面"
		"defend":
			valid = false
			if action_started and _alive_action_enemies() == 0:
				wave_wait += delta
				if wave_index < int(action.get("waves",1)):
					condition = "整备 %.0f s" % maxf(0,float(action.get("wave_break_s",8))-wave_wait)
					if wave_wait >= float(action.get("wave_break_s",8)):
						_spawn_wave(action,target)
						wave_wait = 0
				else:
					valid = wave_wait >= float(action.get("wave_break_s",0))
			if action.has("target_nodes") or action.has("boss_phase"):
				valid = valid and combat.has_method("objective_complete") and combat.objective_complete()
			condition = "敌机 %d  |  设施 %.0f%%" % [_alive_action_enemies(),facility.hp] if not valid else "防守完成"
			if valid and facility.hp < float(action.get("facility_integrity_min",0))*100: pending = true; failed.emit("设施完整度未达本次目标"); return
		"escort":
			valid = false
			if not escort_water_route.is_empty():
				condition="护送维修艇" if facility.vessel_kind=="maintenance_boat" else "护送救援筏"
				condition+="  |  %.0f%%" % facility.hp
				if position_m.distance_to(facility.global_position)>=25:
					condition="船只等待护航 · 靠近至 25 米内"
				elif _alive_action_enemies()>0:condition="先清除威胁，船只在水面等候"
				else:valid=_advance_water_escort(delta,held)
			else:
				if position_m.distance_to(facility.global_position)<25 and _alive_action_enemies()==0:
					if escort_index < escort_path.size():
						if escort_index in safe_stop_targets and escort_index not in escort_released_stops:
							if not held: condition = "安全停车台：按交互继续护送"; return
							escort_released_stops.append(escort_index)
						facility.global_position = facility.global_position.move_toward(escort_path[escort_index],delta*3.2)
						if facility.global_position.distance_to(escort_path[escort_index])<0.3: escort_index += 1
					else: valid = true
				condition = "护送车辆  |  %.0f%%" % facility.hp
			if valid and facility.hp < float(action.get("escort_integrity_min",0))*100: _fail("护送物完整度未达本次目标"); return
	if action.has("safe_window_s"):
		var open = _safe_window(action)
		valid = valid and open
		var in_sweep = not open and close and horizontal_distance<1.2 and held
		if in_sweep and not was_in_sweep: metrics["mechanical_sweep_intrusions"] = int(metrics.get("mechanical_sweep_intrusions",0))+1
		was_in_sweep = in_sweep
		if not open:
			condition = "机械运动中，请等待安全窗口"
	var duration = float(action.get("duration_s",0.05 if action.type in ["gate","defend","escort"] else 1.5))
	if action.type == "scan": duration /= maxf(0.35,float(pilot.environment_sample.get("scan_quality",1.0)))
	if action.type == "scan" and world.night: duration *= float(pilot.stats.get("modifiers",{}).get("night_scan_time_multiplier",1.0))
	if action.type == "pickup": duration /= float(pilot.stats.get("modifiers",{}).get("winch_speed_multiplier",1.0))
	if valid:
		progress_s += delta
		delivery_invalid_s = 0.0
	else:
		delivery_invalid_s += delta
		var safe_pause = action.has("safe_window_s") and not _safe_window(action) and close and stable and tool_ok and held
		var gimbal_grace = action.type=="deliver" and held and tool_ok and delivery_invalid_s<=float(pilot.stats.get("modifiers",{}).get("delivery_grace_s",0.0))
		if not safe_pause and not gimbal_grace: progress_s = 0.0
	if valid and progress_s + 0.00001 >= duration: _complete_action()

func _complete_action() -> void:
	var action = current_action()
	var target = target_position()
	if action.type == "pickup":
		var id = str(action.cargo_id)
		var body: RigidBody3D = cargo.get(id)
		if not is_instance_valid(body): _fail("任务货物已丢失，请恢复领取座"); return
		body.freeze = false
		if not pilot.attach_cargo(body,id,body.mass): condition = "此配装无法承载，请更换工具或机体"; progress_s = 0; return
		cargo_records[id].state = "carried"
	if action.type == "deliver":
		var id = str(action.cargo_id)
		var body = pilot.release_cargo(id)
		if not is_instance_valid(body): _fail("交付货物不存在"); return
		metrics.delivery_errors_m.append(Vector2(body.global_position.x-target.x,body.global_position.z-target.z).length())
		metrics.cargo_integrity_min = minf(float(metrics.cargo_integrity_min),float(cargo_records[id].integrity))
		if str(action.get("cargo_disposition","")) == "staged":
			var seat = Vector3(target.x,world.surface_height(target)+0.8,target.z)
			body.freeze = true
			body.global_position = seat
			body.linear_velocity = Vector3.ZERO
			body.angular_velocity = Vector3.ZERO
			body.set_meta("home",seat)
			cargo_records[id].state = "staged"
			cargo_records[id].home = [seat.x,seat.y,seat.z]
		else:
			cargo_records[id].state = "delivered"
			delivered_reward_parts += int(cargo_records[id].get("value",0))
			body.queue_free()
			cargo.erase(id)
	if action.type == "return":
		metrics.landing_count = int(metrics.landing_count)+1
		if bool(action.get("extract_carried_cargo",false)):
			for id in pilot.cargo_items.keys():
				if not cargo_records.has(id): continue
				var record: Dictionary = cargo_records[id]
				extraction_manifest.append({"cargo_id":id,"value":int(record.get("value",0)),"mass_kg":float(record.mass_kg),"integrity":float(record.integrity)})
				delivered_reward_parts += int(record.get("value",0))
				record.state = "delivered"
				var extracted = pilot.release_cargo(str(id))
				if is_instance_valid(extracted): extracted.queue_free()
				cargo.erase(id)
	if action.has("retained_flag"): preparation_flags[str(action.retained_flag)] = true
	if action.has("seeded_target_group"): preparation_flags[str(action.seeded_target_group)] = str(action.poi_id)
	if action.type in ["scan","clear","deliver","interact"] and str(action.poi_id) not in staged_restorations: staged_restorations.append(str(action.poi_id))
	action_completed.emit(action.duplicate(true))
	last_target = target
	has_last_target = true
	action_index += 1
	_prepare_action()

func skip_optional() -> bool:
	if pending or not bool(current_action().get("optional",false)): return false
	action_index += 1
	_prepare_action()
	return true

func begin_extract() -> bool:
	if pending: return false
	for index in range(action_index,actions.size()):
		if bool(actions[index].get("extract_carried_cargo",false)):
			action_index = index
			_prepare_action()
			return true
	return false

func _spawn_wave(action: Dictionary, target: Vector3) -> void:
	var previous = combat.enemies.size()
	combat.spawn_wave(action.get("enemy_roles",[]),target)
	for index in range(previous,combat.enemies.size()): action_enemies.append(combat.enemies[index])
	action_started = true
	wave_index += 1

func _alive_action_enemies() -> int:
	var count = 0
	for enemy in action_enemies:
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion() and float(enemy.hp)>0: count += 1
	return count

func _safe_window(action: Dictionary) -> bool:
	if int(action.get("boss_phase",0)) == 2 and combat.has_method("is_safe_window"): return combat.is_safe_window()
	var window = float(action.get("safe_window_s",4.0))
	return fmod(action_elapsed_s,window+2.0)<window

func _check_gate_crossing(position_m: Vector3, target: Vector3, action: Dictionary) -> void:
	var before = (gate_previous_position-target).dot(gate_normal)
	var after = (position_m-target).dot(gate_normal)
	if gate_entry_side == 0.0 and absf(before)>0.2: gate_entry_side = signf(before)
	if gate_entry_side != 0.0 and after*gate_entry_side<0.0 and before*gate_entry_side>=0.0:
		var fraction = clampf(before/(before-after),0.0,1.0)
		var intersection = gate_previous_position.lerp(position_m,fraction)-target
		var lateral = intersection-gate_normal*intersection.dot(gate_normal)
		var permitted = lateral.length()<=2.8 and absf(intersection.y)<=1.6
		if bool(action.get("warning_observed_required",false)): permitted = permitted and warning_observed
		if permitted: gate_crossed = true
		else: gate_entry_side = signf(after)
	gate_previous_position = position_m

func _try_recover_pickup(action: Dictionary, tool_ok: bool, held: bool, stable: bool) -> void:
	var id = str(action.cargo_id)
	if not tool_ok or not held or not stable or not cargo_records.has(id): return
	if str(cargo_records[id].state) not in ["available","staged"]: return
	var body: RigidBody3D = cargo.get(id)
	if not is_instance_valid(body) or pilot.global_position.distance_to(body.global_position)>4.0: return
	if pilot.global_position.y-world.surface_height(body.global_position)<1.2 or pilot.global_position.y-world.surface_height(body.global_position)>3.0 or Vector2(pilot.global_position.x-body.global_position.x,pilot.global_position.z-body.global_position.z).length()>0.85: return
	body.freeze = false
	if pilot.attach_cargo(body,id,body.mass): cargo_records[id].state = "carried"

func _on_collision(event: Dictionary) -> void:
	if pending: return
	metrics["collision_count"] = int(metrics.get("collision_count",0))+1
	if str(event.get("kind","")) in ["scrape","frontal"]: metrics["clearance_collision_count"] = int(metrics.get("clearance_collision_count",0))+1

func _update_metrics(delta: float) -> void:
	if combat.overheat and not last_overheated: metrics.overheat_count = int(metrics.get("overheat_count",0))+1
	last_overheated = combat.overheat
	var threshold = float(stage.get("completion_metrics",{}).get("swing_above_deg",25.0))
	if pilot.cargo_swing()>threshold: metrics.swing_above_s = float(metrics.get("swing_above_s",0.0))+delta
	for id in cargo.keys():
		var body: RigidBody3D = cargo[id]
		if not is_instance_valid(body) or body.is_queued_for_deletion(): continue
		var cooldown = maxf(0.0,float(body.get_meta("impact_cooldown",0.0))-delta)
		var previous: Vector3 = body.get_meta("previous_velocity",Vector3.ZERO)
		if not body.freeze and not body.get_colliding_bodies().is_empty() and previous.length()>2.0 and cooldown<=0.0:
			cargo_records[id].integrity = maxf(0.0,float(cargo_records[id].integrity)-(previous.length()-2.0)*0.04)
			cooldown = 0.5
		body.set_meta("impact_cooldown",cooldown)
		body.set_meta("previous_velocity",body.linear_velocity)
		metrics.cargo_integrity_min = minf(float(metrics.get("cargo_integrity_min",1.0)),float(cargo_records[id].integrity))

func record_metrics() -> Dictionary:
	var result = metrics.duplicate(true)
	result.elapsed_s = elapsed_s
	result.extraction_manifest = extraction_manifest.duplicate(true)
	result.delivered_reward_parts = delivered_reward_parts
	var errors: Array = metrics.get("delivery_errors_m",[])
	var squared = 0.0
	for error in errors: squared += float(error)*float(error)
	result.delivery_rms_m = sqrt(squared/maxi(1,errors.size()))
	return result

func _finish_stage() -> void:
	var requirements: Dictionary = stage.get("completion_metrics",{})
	for key in requirements:
		var name = str(key)
		if name.ends_with("_max"):
			if float(metrics.get(name.trim_suffix("_max"),0))>float(requirements[key]): _fail("本次挑战超过容许失误次数，请重试"); return
		elif name.ends_with("_min"):
			var metric = name if metrics.has(name) else name.trim_suffix("_min")
			if float(metrics.get(metric,0))<float(requirements[key]): _fail("本次挑战完整度或完成次数不足，请重试"); return
	if requirements.has("swing_above_limit_s") and float(metrics.get("swing_above_s",0))>float(requirements.swing_above_limit_s): _fail("货物大摆角累计时间超限，请重试"); return
	if bool(requirements.get("single_departure",false)) and int(metrics.get("replacement_count",0))>0: _fail("本次挑战需要一次出航完成，请重试"); return
	# Session publishes restoration only after the relevant transaction succeeds.
	pending = true
	stage_ready.emit(stage)

func _fail(reason: String) -> void:
	pending = true
	condition = reason
	failed.emit(reason)

func snapshot_run_state() -> Dictionary:
	var records = cargo_records.duplicate(true)
	for id in cargo:
		if is_instance_valid(cargo[id]):
			var p: Vector3 = cargo[id].global_position
			records[id].position = [p.x,p.y,p.z]
	return {"stage_id":str(stage.get("id","")),"action_index":action_index,"elapsed_s":elapsed_s,"cargo_records":records,"preparation_flags":preparation_flags.duplicate(true),"metrics":metrics.duplicate(true),"stage_start_cargo":stage_start_cargo.duplicate(true),"stage_start_flags":stage_start_flags.duplicate(true),"extraction_manifest":extraction_manifest.duplicate(true),"delivered_reward_parts":delivered_reward_parts,"staged_restorations":staged_restorations.duplicate(),"optional":optional}

func restore_run_state(saved: Dictionary) -> bool:
	if str(saved.get("stage_id","")) != str(stage.get("id","")): return false
	_restore_cargo_records(saved.get("cargo_records",{}))
	preparation_flags = saved.get("preparation_flags",{}).duplicate(true)
	metrics.merge(saved.get("metrics",{}),true)
	stage_start_cargo = saved.get("stage_start_cargo",{}).duplicate(true)
	stage_start_flags = saved.get("stage_start_flags",{}).duplicate(true)
	extraction_manifest.clear()
	for item in saved.get("extraction_manifest",[]): extraction_manifest.append(item.duplicate(true))
	delivered_reward_parts = int(saved.get("delivered_reward_parts",0))
	staged_restorations.clear()
	for id in saved.get("staged_restorations",[]): staged_restorations.append(str(id))
	action_index = clampi(int(saved.get("action_index",0)),0,actions.size())
	elapsed_s = maxf(0.0,float(saved.get("elapsed_s",0)))
	pending = false
	_prepare_action()
	return true

func _restore_cargo_records(records: Dictionary) -> void:
	for id in pilot.cargo_items.keys(): pilot.release_cargo(str(id))
	for body in cargo.values():
		if is_instance_valid(body): body.queue_free()
	cargo.clear()
	cargo_records = records.duplicate(true)
	for id in cargo_records:
		var record: Dictionary = cargo_records[id]
		if str(record.state)=="delivered": continue
		_spawn_cargo(str(id),record)
		if record.has("position"):
			var p: Array = record.position
			cargo[id].global_position = Vector3(p[0],p[1],p[2])
		if str(record.state)=="carried":
			cargo[id].global_position = pilot.global_position+Vector3.DOWN*1.5
			if not pilot.attach_cargo(cargo[id],str(id),float(record.mass_kg)): record.state = "available"

# Water routes are authored separately from land navigation and are keyed by the
# unchanged action POI sequence. A harbor service POI is not a boat destination.
func _water_route_for_action(action: Dictionary) -> Dictionary:
	var routes: Dictionary=world.layout.get("water_routes",{})
	if str(action.get("type",""))=="escort":
		var ids: Array=action.get("escort_path",[])
		for id in ids:
			if not id is String:return {}
		return routes.get(">".join(PackedStringArray(ids)),{}).duplicate(true)
	if str(action.get("type",""))=="defend":
		for route in routes.values():
			if str(route.get("defend_stage_id",""))==str(stage.get("id","")) and str(action.get("poi_id",""))==str(route.poi_ids[0]):return route.duplicate(true)
	return {}

func _water_point_clear(point: Vector3) -> bool:
	var radius=float(escort_water_route.get("clearance_radius_m",3.4))
	var water_level=float(world.layout.water_level)
	for i in range(17):
		var sample=point if i==16 else point+Vector3(cos(i*TAU/16.0),0,sin(i*TAU/16.0))*radius
		if world.terrain_height(sample)>=water_level-.1:return false
	return true

func _prepare_water_escort(action: Dictionary) -> bool:
	var points: Array=escort_water_route.get("points_xz_m",[])
	if points.size()<2:_fail("水上护送航路缺少泊位");return false
	for point in points:
		escort_path.append(Vector3(float(point[0]),float(world.layout.water_level)+.25,float(point[1])))
	for i in range(escort_path.size()-1):
		var length=escort_path[i].distance_to(escort_path[i+1]);var samples=maxi(1,ceili(length))
		for j in range(samples+1):
			if not _water_point_clear(escort_path[i].lerp(escort_path[i+1],float(j)/samples)):
				_fail("水上航路与岸线冲突，船只保持停泊");return false
	var stops: Array=escort_water_route.get("poi_waypoint_indices",[])
	for index in action.get("safe_stop_indices",[]):
		if int(index)<0 or int(index)>=stops.size():_fail("水上航路缺少安全泊位");return false
		var waypoint=int(stops[int(index)])
		if waypoint<0 or waypoint>=escort_path.size():_fail("水上安全泊位无效");return false
		safe_stop_targets.append(waypoint)
	return true

func _water_move_clear(destination: Vector3) -> bool:
	if not _water_point_clear(destination):return false
	var query=PhysicsShapeQueryParameters3D.new()
	var envelope=BoxShape3D.new();envelope.size=Vector3(3.2,2.2,5.9)
	query.shape=envelope;query.collision_mask=1|32;query.exclude=[facility.get_rid()]
	var heading=destination-facility.global_position
	var yaw=atan2(-heading.x,-heading.z) if heading.length()>.001 else facility.rotation.y
	var center=facility.global_position+Vector3.UP*.5
	query.transform=Transform3D(Basis(Vector3.UP,yaw),center)
	var space=world.get_world_3d().direct_space_state
	if not space.intersect_shape(query,1).is_empty():return false
	query.motion=destination-facility.global_position
	var fractions=space.cast_motion(query)
	return fractions.size()==2 and fractions[0]>=.99999

func _advance_water_escort(delta: float,held: bool) -> bool:
	if escort_index>=escort_path.size():return true
	var destination=escort_path[escort_index]
	if facility.global_position.distance_to(destination)>.001:
		var next=facility.global_position.move_toward(destination,maxf(0,delta)*float(escort_water_route.get("speed_mps",3.2)))
		if not _water_move_clear(next):condition="水上航道受阻 · 船只停泊等候";return false
		var heading=next-facility.global_position
		if heading.length()>.001:facility.rotation.y=atan2(-heading.x,-heading.z)
		facility.global_position=next
	if facility.global_position.distance_to(destination)<=.001:
		if escort_index in safe_stop_targets and escort_index not in escort_released_stops:
			if not held:condition="安全泊位：按交互继续护送";return false
			escort_released_stops.append(escort_index)
		escort_index+=1
	return escort_index>=escort_path.size()

class WorkFacility extends AnimatableBody3D:
	signal failure
	var hp = 100.0
	var vessel_kind = ""
	func _ready() -> void:
		collision_layer = 32
		collision_mask = 0
		# The runner advances this body in its physics tick, never AnimationPlayer.
		sync_to_physics = false
		var shape = CollisionShape3D.new()
		var box = BoxShape3D.new()
		box.size = Vector3(2.8,1.9,5.5) if not vessel_kind.is_empty() else Vector3(2.6,1.8,2.6)
		shape.shape = box
		if not vessel_kind.is_empty():shape.position.y=.5
		add_child(shape)
		if not vessel_kind.is_empty():_build_vessel();return
		GameVisuals.box(self,Vector3.ZERO,box.size,Color("a9c4b3"))
		GameVisuals.box(self,Vector3(0,1.0,0),Vector3(1.8,0.2,1.8),Color("49ae90"))
	func _build_vessel() -> void:
		name="MaintenanceBoat" if vessel_kind=="maintenance_boat" else "RescueRaft"
		# Editable seven-sided hull with a pointed bow facing -Z, separate deck/cabin.
		var outline=PackedVector2Array([Vector2(-1.25,2.3),Vector2(1.25,2.3),Vector2(1.4,-.9),Vector2(.85,-2.15),Vector2(0,-2.75),Vector2(-.85,-2.15),Vector2(-1.4,-.9)])
		var surface=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in range(outline.size()):
			var a=outline[i];var b=outline[(i+1)%outline.size()]
			for p in [Vector3(a.x,-.4,a.y),Vector3(a.x,.3,a.y),Vector3(b.x,.3,b.y),Vector3(a.x,-.4,a.y),Vector3(b.x,.3,b.y),Vector3(b.x,-.4,b.y)]:surface.add_vertex(p)
		var indices=Geometry2D.triangulate_polygon(outline)
		for i in indices:surface.add_vertex(Vector3(outline[i].x,.3,outline[i].y))
		surface.generate_normals()
		var hull=MeshInstance3D.new();hull.name="PointedBoatHull";hull.mesh=surface.commit();hull.material_override=GameVisuals.material(Color("b15d38") if vessel_kind=="rescue_raft" else Color("315c65"));hull.material_override.cull_mode=BaseMaterial3D.CULL_DISABLED;add_child(hull)
		GameVisuals.box(self,Vector3(0,.35,.25),Vector3(2.35,.12,3.6),Color("b9bba5"))
		if vessel_kind=="maintenance_boat":
			GameVisuals.box(self,Vector3(0,.85,-.45),Vector3(1.55,1.0,1.65),Color("d2d9ce"))
			GameVisuals.box(self,Vector3(0,1.0,-1.29),Vector3(1.25,.4,.04),Color("3e7c8c"))
			GameVisuals.box(self,Vector3(0,1.4,-.45),Vector3(1.8,.12,1.9),Color("ba773b"))
			GameVisuals.cylinder(self,Vector3(.5,1.78,-.2),.035,.7,Color("354a4f"))
		else:
			for z in [-.8,.65]:GameVisuals.box(self,Vector3(0,.6,z),Vector3(2,.35,.4),Color("c5ac6d"))
		for x in [-1.28,1.28]:
			GameVisuals.box(self,Vector3(x,.55,.5),Vector3(.12,.28,2.8),Color("c6a36c"))
			var ring=GameVisuals.ring(self,Vector3(x,.75,.9),.33,Color("df9b45"),.1);ring.rotation.z=PI/2
		GameVisuals.box(self,Vector3(-.85,.7,-1.65),Vector3(.15,.15,.15),Color("c66054"))
		GameVisuals.box(self,Vector3(.85,.7,-1.65),Vector3(.15,.15,.15),Color("73b69d"))
	func take_damage(amount: float, _direction: Vector3 = Vector3.ZERO) -> void:
		hp = maxf(0,hp-amount)
		if hp<=0: failure.emit()
