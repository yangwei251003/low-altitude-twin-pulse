extends Node
## Player-requested flight assistant. Produces ordinary input and reliable
## local-player actions. It owns no physics, Story completion or Store writes.
signal changed(snapshot: Dictionary)
const Pilot = preload("res://scripts/v3/assist/twin_assist_pilot.gd")
const Routes = preload("res://scripts/v3/assist/twin_assist_routes.gd")
const Combat = preload("res://scripts/v3/assist/twin_assist_combat.gd")
const Rules = preload("res://scripts/v3/gameplay/twin_ability_rules.gd")
const Cargo = preload("res://scripts/v3/gameplay/twin_thermal_cargo_session.gd")
var session
var enabled := false
var state := "idle"
var message := "驾驶助手待命"
var scope := "objective"
var objective: Dictionary = {}
var _first_region := ""
var _first_goal := ""
var _steps: Array = []
var _cursor := 0
var _step_data: Dictionary = {}
var _pilot: RefCounted
var _routes: RefCounted
var _combat: RefCounted
var _body_id := 0
var _region := ""
var _clock := 0.0
var _next_action := 0.0
var _radio_clock := 0.0
var _radio_line := ""
var _last_status := ""
var _waiting_choice := false
var _gate_route := false
var _last_goal := ""
var _nav_target := Vector3.INF
var _hold_position := Vector3.INF
var _best_distance := INF
var _stalled := 0.0

func setup(owner_session: Node) -> void:
	session = owner_session
	_routes = Routes.new()
	_combat = Combat.new()
	_combat.setup(self)
	set_process(false)
	set_physics_process(false)

func start(requested_scope: String = "objective") -> Dictionary:
	if not is_instance_valid(session) or not session.active:
		return {"ok":false,"message":"先进入单人或局域网航行，再启动当前任务助手。"}
	if not _bind_body(): return {"ok":false,"message":"本机飞机尚未就绪。"}
	if not _body().enabled: return {"ok":false,"message":"先按原救援／重试恢复飞机，再启动助手。"}
	scope = requested_scope if requested_scope in ["objective","chapter","journey"] else "objective"
	objective = current_objective()
	if objective.is_empty(): return {"ok":false,"message":"主线已经完成，可以手动回访与自由探索。"}
	_first_goal = str(objective.id)
	_first_region = _first_goal.get_slice(":",0)
	_last_goal = ""
	_steps.clear()
	_cursor = 0
	_step_data.clear()
	_waiting_choice = false
	_gate_route = false
	_clock = 0.0
	_next_action = 0.0
	_radio_clock = 0.0
	_radio_line = ""
	_hold_position = Vector3.INF
	enabled = true
	_set_state("flying","已接手当前任务；移动、转向、制动或战斗操作可随时接管。")
	return {"ok":true,"message":message,"objective_id":_first_goal}

func stop(reason: String = "已交还手动驾驶") -> void:
	enabled = false
	_steps.clear()
	_cursor = 0
	_step_data.clear()
	_waiting_choice = false
	_pilot = null
	_body_id = 0
	_nav_target = Vector3.INF
	_hold_position = Vector3.INF
	if _combat != null: _combat.reset()
	_set_state("idle",reason)

func status() -> Dictionary:
	var shown: Dictionary=objective if enabled else current_objective()
	return {"enabled":enabled,"state":state,"message":message,"scope":scope,
		"objective_id":str(shown.get("id","")),"objective_text":str(shown.get("text","")),
		"step":_cursor+1,"steps":_steps.size(),"player_control_available":true}

func current_objective() -> Dictionary:
	if not is_instance_valid(session) or session.story == null or session.story.director == null: return {}
	var completed: Array = session.story.state.get("completed",[])
	var definitions: Dictionary = session.story.director.definitions()
	for action: Dictionary in definitions.get("actions",[]):
		for goal: Dictionary in action.get("objectives",[]):
			if str(goal.get("id","")) not in completed: return goal.duplicate(true)
	return {}

func manual_event(event: InputEvent) -> void:
	if not enabled or not is_instance_valid(session) or not session.inputs.active: return
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.physical_keycode
		if key == 0 or key >= KEY_SPECIAL: key = event.keycode
		if key in [KEY_W,KEY_A,KEY_S,KEY_D,KEY_Q,KEY_E,KEY_Z,KEY_C,KEY_SPACE,KEY_J,KEY_F,KEY_X,KEY_G,KEY_TAB,KEY_R,KEY_0,KEY_1,KEY_2,KEY_3,KEY_4,KEY_5,KEY_6,KEY_7,KEY_8,KEY_9,KEY_UP,KEY_DOWN,KEY_LEFT,KEY_RIGHT]: stop("已接管：助手停止，控制权交还给你。")
	elif event is InputEventJoypadButton and event.pressed:
		if event.button_index not in [JOY_BUTTON_START,JOY_BUTTON_BACK]: stop("手柄已接管，助手停止。")
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		stop("手动战斗操作已接管，助手停止。")

func compose_command(manual: Dictionary, delta: float) -> Dictionary:
	if not enabled: return manual
	if not is_instance_valid(session) or not session.active or not is_instance_valid(session.world):
		stop("会话已结束，助手停止。")
		return manual
	if not _bind_body() or not _body().enabled:
		stop("飞机需要救援，助手已停止；恢复后可重新开启。")
		return manual
	if not is_finite(delta) or delta <= 0.0: return manual
	if bool(manual.get("active",false)) and _manual_axes(manual):
		stop("检测到手动操控，已立即交还驾驶。")
		return manual
	objective = current_objective()
	if objective.is_empty():
		stop("主线旅程已经完成，欢迎继续手动探索。")
		return Pilot.neutral()
	var next_id := str(objective.id)
	if (scope == "objective" and next_id != _first_goal) or (scope == "chapter" and next_id.get_slice(":",0) != _first_region):
		stop("当前任务已完成，控制权交还给你。")
		return Pilot.neutral()
	if next_id != _last_goal:
		_last_goal = next_id
		_hold_position = Vector3.INF
		_steps.clear()
		_cursor = 0
		_step_data.clear()
		_waiting_choice = false
		_gate_route = false
		_combat.reset()
	if session.interface.chapter_choice.visible or session.interface.vote.visible:
		_hold_position = Vector3.INF
		_waiting_choice = true
		_set_state("waiting_choice","请亲自阅读并确认这个决定；助手不会替你选择。")
		return manual
	# The original panel owns reading, selection and consensus. If it closes,
	# re-evaluate the actual goal/step; never keep a stale wait after a commit.
	if _waiting_choice:
		_waiting_choice = false
		_next_action = maxf(_next_action,_clock+1.5)
	if not bool(manual.get("active",false)) or session.simulation_paused:
		_hold_position = Vector3.INF
		_set_state("suspended","界面或暂停已接管；关闭后助手继续。")
		return manual
	if session.interface.radio.visible:
		var line := str(session.interface.radio_text.text)
		if line != _radio_line:
			_radio_line = line
			_radio_clock = 0.0
		_radio_clock += delta
		_set_state("dialogue","正在听取当前联络；按 G 可接管阅读。")
		var reading_seconds := maxf(3.0,float(line.length())/5.5+1.0)
		if _radio_clock >= reading_seconds and not _radio_playing():
			_radio_clock = 0.0
			_radio_line = ""
			session.interface.advance_dialogue()
		# A live encounter must keep its existing avoidance/weapon strategy
		# during radio. This never enters a battle on behalf of the dialogue.
		if session.boss_active and next_id.get_slice(":",0) == str(session.region_id) and next_id.get_slice(":",2) in ["engage","disable","stop"]:
			_hold_position = Vector3.INF
			_clock += minf(delta,.1)
			return _combat.compose(delta,str(session.region_id))
		return _hold_command(delta)
	_radio_clock = 0.0
	_radio_line = ""
	# Only active flight advances AI deadlines. Menus and dialogue do not time
	# out the same suspended ability/navigation step.
	_clock += minf(delta,.1)
	var target_region := next_id.get_slice(":",0)
	if str(session.region_id) != target_region:
		return _travel(target_region,delta)
	if _steps.is_empty():
		_routes.setup(session,_body())
		_steps = _routes.build(objective)
		_cursor = 0
		_step_data.clear()
		if _steps.size() <= 1:
			stop("当前现场没有可用航路，请手动调整位置后再启动助手。")
			return Pilot.neutral()
	if _cursor >= _steps.size():
		stop("现场条件尚未满足，助手已停下；可以手动处理后再启动。")
		return Pilot.neutral()
	return _tick_step(delta)

func _travel(destination: String, delta: float) -> Dictionary:
	if session._can_travel_to(destination):
		if _clock >= _next_action:
			_next_action = _clock+3.0
			session._ui_action("travel_to",{"region_id":destination})
		_set_state("travelling","正在按已开放航路前往下一航区。")
		return _hold_command(delta)
	if str(session.region_id) in ["I1","F1"] and not bool(session.world.restored_gate):
		if not _gate_route:
			_routes.setup(session,_body())
			_steps = _routes.gate(str(session.region_id))
			_cursor = 0
			_step_data.clear()
			_gate_route = true
		if _cursor < _steps.size(): return _tick_step(delta)
	stop("下一航区尚未开放；请查看任务提示，助手没有跳过旅行条件。")
	return Pilot.neutral()

func _tick_step(delta: float) -> Dictionary:
	var step: Dictionary = _steps[_cursor]
	if not _step_data.has("started"):
		_step_data["started"] = _clock
		_step_data["attempts"] = 0
	var kind := str(step.get("kind",""))
	match kind:
		"flight", "visit", "approach": return _navigation(step,delta)
		"boss":
			_hold_position = Vector3.INF
			_set_state("combat","助手正在按实际预警、部件与窗口作战。")
			return _combat.compose(delta,str(step.get("region",session.region_id)))
		"cargo":
			# Original DockLift can own this step's input; do not overlay a hold.
			_hold_position = Vector3.INF
			return _cargo(delta)
		"wait":
			_set_state("working","正在等待真实机关、运输或任务条件完成。")
			if condition(step.get("condition",{})): _advance_step()
			elif _clock-float(_step_data.started) > float(step.get("timeout",30)): stop("现场条件尚未完成，助手已停止；已完成的进度保留。")
		"ability":
			_set_state("working","正在使用能力处理当前机关。")
			var target := str(step.target)
			var requirement: Dictionary = step.get("condition",{})
			if not requirement.is_empty() and condition(requirement): _advance_step()
			elif _clock >= _next_action:
				if int(_step_data.attempts) >= 14 or _clock-float(_step_data.started)>65:
					stop("能力操作尚未满足条件；请检查目标距离、遮挡或任务提示。")
				elif cast(target,str(step.ability),str(step.get("mode",""))):
					_step_data.attempts = int(_step_data.attempts)+1
					if requirement.is_empty(): _advance_step()
		"operate":
			_set_state("working","正在操作当前机械装置。")
			var requirement: Dictionary = step.get("condition",{})
			if not requirement.is_empty() and condition(requirement): _advance_step()
			elif _clock >= _next_action:
				if int(_step_data.attempts) >= 3 or _clock-float(_step_data.started)>18: stop("机械操作未完成，已停止重试，原现场与进度保留。")
				elif operate(str(step.target)):
					_step_data.attempts = int(_step_data.attempts)+1
					if requirement.is_empty(): _advance_step()
		"contact":
			_set_state("contact","正在联络或读取当前任务记录。")
			if not bool(step.get("goal",true)) and _contact_recorded(str(step.target)):
				_advance_step()
			elif _clock >= _next_action:
				if _clock-float(_step_data.started)>20: stop("未能读取目标记录；请调整到能看见控制台的位置再继续。")
				elif contact(str(step.target)):
					if not bool(step.get("goal",true)) and session.interface.radio.visible: _advance_step()
		"gate":
			_set_state("working","正在完成已修复航标的正常提交。")
			if bool(session.world.restored_gate): _advance_step()
			elif _clock >= _next_action:
				_next_action = _clock+1.5
				session._ui_action("interact",{})
			if _clock-float(_step_data.get("started",_clock))>20: stop("航标尚不满足提交条件，助手停止。")
		"choice":
			if bool(step.get("facility",false)):
				# G at this console commits the selected physical bridge mode in
				# solo play, so this final input must belong to the player.
				_set_state("waiting_choice","巡检桥已锁定。请亲自按 G 确认通路；这会交还手动，确认后可再次启动助手。")
			elif _clock >= _next_action:
				_set_state("waiting_choice","请亲自阅读方案并确认；助手不会代替你决定。")
				contact(str(step.target))
				if session.interface.chapter_choice.visible or session.interface.vote.visible: _waiting_choice = true
				elif _clock-float(_step_data.started)>20: stop("决定面板尚未打开，请手动靠近确认台后继续。")
		_:
			stop("助手遇到未知步骤，已安全交还控制。")
	return _hold_command(delta)

func _navigation(step: Dictionary, delta: float) -> Dictionary:
	_hold_position = Vector3.INF
	if not _step_data.has("points"):
		var points: Array = step.get("points",[]).duplicate()
		if str(step.kind) in ["visit","approach"]:
			var point: Vector3 = step.get("point",Vector3.INF)
			if str(step.kind) == "visit":
				point = target_position(str(step.target)) + Vector3(step.get("offset",Vector3(0,1.6,1)))
			if not point.is_finite():
				stop("当前目标尚未出现在真实场景中，助手停止。")
				return Pilot.neutral()
			var height := minf(float(_body().max_altitude)-.4,maxf(float(step.get("height",15)),point.y+1.5))
			var current: Vector3 = _body().global_position
			points = [Vector3(current.x,height,current.z),Vector3(point.x,height,point.z),point]
			if current.distance_to(point)<3 and hull_clear(point): points = [point]
		_step_data.points = points
		_step_data.point_index = 0
		_nav_target = Vector3.INF
	var index := int(_step_data.get("point_index",0))
	var points: Array = _step_data.get("points",[])
	if index >= points.size():
		_advance_step()
		return _hold_command(delta)
	var point: Vector3 = points[index]
	_set_state("flying","助手正在飞往任务位置；可随时接管。")
	var command := move_to(point,delta)
	if not enabled: return command
	if _pilot.state == "arrived":
		_step_data.point_index = index+1
		_nav_target = Vector3.INF
	return command

func move_to(point: Vector3, delta: float, precision: bool = false) -> Dictionary:
	_hold_position = Vector3.INF
	if not enabled or _pilot == null: return Pilot.neutral()
	if not point.is_finite() or point.y > _body().max_altitude:
		stop("目标超出当前飞机航行范围，已交还控制。")
		return Pilot.neutral()
	if _nav_target != point:
		_nav_target = point
		_best_distance = _body().global_position.distance_to(point)
		_stalled = 0.0
		_pilot.settled_seconds = 0.0
	var distance := _body().global_position.distance_to(point)
	if distance < _best_distance-.08:
		_best_distance = distance
		_stalled = 0.0
	else: _stalled += delta
	var command: Dictionary = _pilot.compose(delta,point,precision)
	if _stalled > 18.0 and str(_pilot.state) != "arrived":
		stop("尚未稳定到达当前航点，助手已停止；请调整位置后再继续。" if bool(_pilot.last_probe.get("clear",false)) else "航路被当前机体或现场障碍挡住，已停止助手；请移到开阔处再继续。")
	return command

func _hold_command(delta: float) -> Dictionary:
	if not enabled or _pilot == null: return Pilot.neutral()
	var body := _body()
	if not is_instance_valid(body) or not body.enabled: return Pilot.neutral()
	if not _hold_position.is_finite():
		# Capture once on entering a stationary action, not every frame: wind
		# displacement must become a real position error for normal input.
		_hold_position = body.global_position
		_pilot.settled_seconds = 0.0
	return _pilot.compose(delta,_hold_position,true)

func prepend(steps: Array) -> void:
	for index in range(steps.size()-1,-1,-1): _steps.insert(_cursor,steps[index])
	_step_data.clear()
	_nav_target = Vector3.INF
	_hold_position = Vector3.INF

func _advance_step() -> void:
	_cursor += 1
	_step_data.clear()
	_nav_target = Vector3.INF
	_hold_position = Vector3.INF

func cast(target: String, ability: String, mode: String = "") -> bool:
	if not enabled or _clock < _next_action or not Rules.DEFINITIONS.has(ability): return false
	var local: int = session.network.local_id()
	var definition: Dictionary = Rules.DEFINITIONS[ability]
	var actor: Dictionary = session.entities.get(session._actor_id(local),{})
	if float(session.cooldowns.get(local,0))>0 or float(actor.get("energy",0))<float(definition.get("energy",0)): return false
	var point := target_position(target)
	if not point.is_finite() or _body().global_position.distance_to(point)>float(definition.get("range",12)): return false
	if not session._line_clear(_body().global_position,point,_body().get_rid(),target): return false
	session.network.send_action("lock",{"target_id":target})
	session._ui_action("select",{"ability":ability})
	session.network.send_action("ability",{"ability":ability,"target_id":target,"mode":mode})
	_next_action = _clock+.65
	return true

func operate(target: String) -> bool:
	if not enabled or _clock < _next_action: return false
	var local: int = session.network.local_id()
	if not session.thermal_cargo.operable_near(local,target) and not session.campaign.operable_near(local,target): return false
	if target in [Cargo.CARGO,Cargo.LOW,Cargo.HIGH]:
		# Ordinary player G arrives outside this command-composition tick.
		# Defer the same action so native custody observes the next physics
		# frame after attachment, never attachment and observation together.
		_perform_cargo_operation.call_deferred(target,_body_id,_region)
		_next_action = _clock+1.2
		return true
	session.network.send_action("lock",{"target_id":target})
	session._ui_action("explore",{})
	_next_action = _clock+1.2
	return true

func _perform_cargo_operation(target: String, body_id: int, region_id: String) -> void:
	if not enabled or not is_instance_valid(session) or not session.active or session.simulation_paused: return
	if _body_id != body_id or _region != region_id: return
	var local: int = session.network.local_id()
	if not session.thermal_cargo.operable_near(local,target): return
	session.network.send_action("lock",{"target_id":target})
	session._ui_action("explore",{})

func contact(target: String) -> bool:
	if not enabled or _clock < _next_action: return false
	if session.story.nearest(_body().global_position) != target: return false
	# Clear a prior device lock so normal G does not re-operate the old device.
	session.network.send_action("lock",{"target_id":""})
	session._ui_action("explore",{})
	_next_action = _clock+1.2
	return true

func target_position(target: String) -> Vector3:
	var value: Variant = session.entities.get(target,{}).get("position")
	if value is Vector3: return value
	if session.story.markers.has(target): return session.story._point(session.story.markers[target])
	return Vector3.INF

func hull_clear(point: Vector3) -> bool:
	if not point.is_finite(): return false
	var shape := BoxShape3D.new()
	shape.size = Vector3(float(_body().stats.width_m),float(_body().stats.height_m),float(_body().stats.length_m))+Vector3.ONE*.36
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY,point)
	query.collision_mask = 1|2|4|8|32
	query.exclude = [_body().get_rid()]
	return _body().get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func condition(specification: Dictionary) -> bool:
	var kind := str(specification.get("type",""))
	var target := str(specification.get("target",""))
	var entry: Dictionary = session.entities.get(target,{})
	match kind:
		"goal": return str(objective.get("id","")) in session.story.state.get("completed",[])
		"entity_gte": return float(entry.get(str(specification.key),-INF)) >= float(specification.value)
		"entity_lte": return float(entry.get(str(specification.key),INF)) <= float(specification.value)
		"entity_bool": return bool(entry.get(str(specification.key),false))
		"angle": return absf(wrapf(float(entry.get("angle",INF))-float(specification.value),-PI,PI))<.01
		"emitter_aligned": return absf(wrapf(float(entry.get("angle",INF)),-PI,PI))<.01 and float(entry.get("light_level",0))>=.5
		"position": return target_position(target).distance_to(Vector3(specification.value))<.05
		"latched":
			var node: Variant = session.world.objects.get(target)
			return node is Node3D and node.global_basis.x.normalized().dot(Vector3.FORWARD)>.95
		"view": return bool(session.campaign.mechanisms.view_state().get(str(specification.key),false))
		"underdeck_open":
			var view: Dictionary = session.world.underdeck.snapshot()
			return view.get("latched",false) and float(view.get("front_fraction",0))>=.999 and float(view.get("rear_fraction",0))>=.999
		"clinic_connected": return not str(session.clinic.progress.snapshot().get("route_method","")).is_empty()
		"cabinet_open": return bool(session.distribution.module.snapshot().get("electric_latched",false))
		"trial_ready": return bool(session.trial.module.link.status().get("trial_ready",false))
		"trial_samples": return bool(session.trial.module.station.status().get("both_samples_recorded",false))
		"bridge_locked":
			var view: Dictionary = session.shared_access.module.status()
			return bool(view.get("locked",false)) and str(view.get("mode","")) == "service_span"
		"canal_cold": return session.canal.exchange_fact() == "local_cooling"
		"canal_ordered": return bool(session.canal.module.status().get("ordered",false))
		"canal_credit": return bool(session.canal.story_service_status().get("ready_credit",false))
		"load_test": return bool(session.campaign.mechanisms.persistent_state().get("histories",{}).get("F4:load_test",{}).get("active",false))
	return false

func _contact_recorded(target: String) -> bool:
	if target in ["F2:record_low","F2:record_high"]: return session.campaign.mechanisms.persistent_state().get("readings",{}).has(target)
	if target in ["I2:trial_gauge_a","I2:trial_gauge_b"]: return not session.trial.observed_gauges().get("A" if target.ends_with("_a") else "B",{}).is_empty()
	if target in ["F4:industrial_gauge","F4:living_gauge"]:
		return session.campaign.mechanisms.persistent_state().get("histories",{}).get("F4:load_test",{}).get("readings",{}).has("industrial" if "industrial" in target else "living")
	return false

func _cargo(delta: float) -> Dictionary:
	_set_state("working","正在按真实吊载、飞行与落架条件运输检修匣。")
	var cargo_state: Dictionary = session.thermal_cargo.module.status()
	if not str(cargo_state.get("assist","")).is_empty():
		# Native DockLift owns this physical operation; do not overwrite its input.
		return _body().command.duplicate(true)
	var row: Dictionary = cargo_state.get("custody",{}).get("cargos",{}).get(Cargo.CARGO,{})
	var phase := str(row.get("phase",""))
	if phase == "docked" and row.get("berth") == Cargo.HIGH:
		_advance_step()
		return Pilot.neutral()
	if phase == "docked" and row.get("berth") == Cargo.LOW:
		if _step_data.has("recovery_route"):
			_step_data.erase("recovery_route")
			_step_data.erase("recovery_index")
			_step_data.departed_low = false
		var point := target_position(Cargo.CARGO)+Vector3.UP*1.1
		if _body().global_position.distance_to(point)>3.0:
			prepend([Routes.approach(point,16)])
			return Pilot.neutral()
		if _body().global_position.distance_to(point)>.35: return move_to(point,delta,true)
		if _body().linear_velocity.length()<.12 and _body().angular_velocity.length()<.1: operate(Cargo.CARGO)
		return Pilot.neutral()
	if phase == "carried":
		if bool(cargo_state.get("journey",{}).get("broken",false)):
			return _return_cargo_low(delta)
		var progress := int(cargo_state.get("journey",{}).get("outer_progress",0))
		if progress == 0 and not bool(_step_data.get("departed_low",false)):
			if _body().global_position.y<6.5:
				var climb := Pilot.neutral()
				climb.vertical = .65
				climb.brake = false
				return climb
			# Departure is a completed control phase, not a permanent minimum
			# altitude. The first real outer waypoint is lower, at y=6 metres.
			_step_data.departed_low = true
		if progress < Cargo.OUTER.size(): return move_to(Cargo.OUTER[progress],delta,true)
		var high := target_position(Cargo.HIGH)+Vector3.UP*2.1
		if not _step_data.has("high_route"):
			_step_data.high_route = [Vector3(high.x,14,5),Vector3(high.x,14,high.z),high]
			_step_data.high_index = 0
		var index := int(_step_data.high_index)
		if index < _step_data.high_route.size():
			var command := move_to(_step_data.high_route[index],delta,true)
			if _pilot != null and _pilot.state == "arrived":
				_step_data.high_index = index+1
				_nav_target = Vector3.INF
			return command
		if _body().global_position.distance_to(high)>.35: return move_to(high,delta,true)
		if _body().linear_velocity.length()<.15: operate(Cargo.HIGH)
		return Pilot.neutral()
	if phase in ["dropping","attaching"]: return _body().command.duplicate(true)
	if _clock-float(_step_data.get("started",_clock))>45: stop("吊载现场尚未就绪，助手已停止；原货物与保存状态保留。")
	return Pilot.neutral()

func _return_cargo_low(delta: float) -> Dictionary:
	_set_state("working","本次吊载航程记录已中断，正在实际返回低泊位重新挂接。")
	var low := target_position(Cargo.LOW)+Vector3.UP*2.1
	if not _step_data.has("recovery_route"):
		if int(_step_data.get("cargo_recoveries",0)) >= 1:
			stop("重新挂接后的运输记录仍未连续，助手停止；货匣与原进度保留。")
			return Pilot.neutral()
		_step_data.cargo_recoveries = int(_step_data.get("cargo_recoveries",0))+1
		var at: Vector3 = _body().global_position
		var height := maxf(8,at.y)
		_step_data.recovery_route = [Vector3(at.x,height,at.z),Vector3(low.x,height,low.z),low]
		_step_data.recovery_index = 0
	var index := int(_step_data.recovery_index)
	var points: Array = _step_data.recovery_route
	if index < points.size():
		var command := move_to(points[index],delta,true)
		if _pilot != null and _pilot.state == "arrived":
			_step_data.recovery_index = index+1
			_nav_target = Vector3.INF
		return command
	if _body().global_position.distance_to(low)>.35: return move_to(low,delta,true)
	if _body().linear_velocity.length()<.15: operate(Cargo.LOW)
	return Pilot.neutral()

func _bind_body() -> bool:
	if not is_instance_valid(session): return false
	var local: int = session.network.local_id()
	var body: Variant = session.players.get(local)
	if not body is FlightBodyV2 or not is_instance_valid(body): return false
	if body.get_instance_id()!=_body_id or _region != str(session.region_id):
		_pilot = Pilot.new()
		if not _pilot.bind(body): return false
		_body_id = body.get_instance_id()
		_region = str(session.region_id)
		_nav_target = Vector3.INF
		_hold_position = Vector3.INF
		_steps.clear()
		_cursor = 0
		_step_data.clear()
		_gate_route = false
		if _routes != null: _routes.setup(session,body)
	return true

func _body() -> FlightBodyV2: return session.players.get(session.network.local_id())

func _manual_axes(command: Dictionary) -> bool:
	for key in ["pitch","roll","vertical","yaw"]:
		if absf(float(command.get(key,0)))>.08: return true
	return bool(command.get("brake",false)) or bool(command.get("fire",false)) or bool(command.get("interact",false)) or not command.get("edges",[]).is_empty()

func _radio_playing() -> bool:
	if not is_instance_valid(session.audio): return false
	var slot := int(session.audio._radio_slot)
	if slot < 0 or slot >= session.audio._ui.size(): return false
	if int(session.audio._ui_slots[slot].get("radio_token",-1)) != int(session.audio._radio_token): return false
	var player: AudioStreamPlayer = session.audio._ui[slot]
	return is_instance_valid(player) and player.playing

func _set_state(next_state: String, text: String) -> void:
	state = next_state
	message = text
	var fingerprint := str(enabled)+":"+state+":"+message+":"+str(objective.get("id",""))
	if fingerprint != _last_status:
		_last_status = fingerprint
		changed.emit(status())
