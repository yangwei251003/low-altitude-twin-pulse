extends Node3D
## Isolated playable candidate with a separate checkpoint profile.
## No MAIN, campaign rewards, travel or LAN writes.
const World=preload("res://scripts/v3/twin_test_world.gd")
const Flight=preload("res://scripts/v2/flight_body.gd")
const Catalog=preload("res://scripts/v2/catalog.gd")
const CameraRig=preload("res://scripts/v2/flight_camera.gd")
const Inputs=preload("res://scripts/v2/pilot_input.gd")
const Ability=preload("res://scripts/v3/gameplay/twin_ability_rules.gd")
const Bootstrap=preload("res://scripts/v3/candidates/canal_transport_executor/canal_transport_bootstrap.gd")
const Executor=preload("res://scripts/v3/candidates/canal_transport_executor/canal_transport_executor.gd")
const Station=preload("res://scripts/v3/candidates/canal_cooling_station/cooling_station.gd")
const Workbench=preload("res://scripts/v3/candidates/canal_workbench/workbench.gd")
const Observation=preload("res://scripts/v3/candidates/canal_playable/canal_observation_visibility.gd")
const RackArt=preload("res://scripts/v3/candidates/canal_calibration_art/calibration_rack_art.gd")
const PlayerCheckpoint=preload("res://scripts/v3/candidates/canal_checkpoint/player_checkpoint.gd")
const CheckpointRepository=preload("res://scripts/v3/candidates/canal_checkpoint/checkpoint_repository.gd")
const CheckpointRestore=preload("res://scripts/v3/candidates/canal_checkpoint/canal_checkpoint_restore.gd")
const PlayerService=preload("res://scripts/v3/candidates/canal_player_service/player_service.gd")
const Runtime=Executor.Rules
const RELAY_ID:="I2:canal_cooling_relay"
const VALVE_ID:="I2:canal_cooling_valve"
const CARRIER_ID:="I2:canal_carrier"
const PLAYER_ID:="player:1"
const MASK:=1|2|4|8|32
var world: World
var player: Flight
var camera: Camera3D
var camera_rig=CameraRig.new()
var observation=Observation.new()
var inputs: Inputs
var bootstrap=Bootstrap.new()
var executor=Executor.new()
var waiting_pilot=Executor.Pilot.new()
var waiting_report: Dictionary={}
var station: Station
var workbench: Workbench
var rack_art: Dictionary={}
var context: Dictionary={}
var entities: Dictionary={}
var bodies: Dictionary={}
var ability=Ability.new()
var selected_ability:="takeover"
var target:=""
var boot_ready:=false
var executor_ready:=false
var site_created:=false
var paused:=false
var fatal:=""
var notes:="运输机正在从南座起飞。可以先查看回冷座。"
var last_action: Dictionary={}
var status_text: Label
var hint_text: Label
var note_text: Label
var target_panel: PanelContainer
var target_text: Label
var beneficiary_label: Label3D
var cursor: MeshInstance3D
var rule_frames:=0
var rule_usec:=0
var command_serial:=0
var station_serial:=0
var cooldown:=0.0
var _setup_frames:=0
var _frozen: Dictionary={}
var _cargo_views: Dictionary={}
var _last_work_notice:=""
var cooling_transfer_delay_count:=0
var cooling_transfer_wait: Dictionary={}
var persistence_enabled:=true
var profile_path:=CheckpointRepository.DEFAULT_PATH
var loading_checkpoint:=false
var save_generation:=0
var last_save_result: Dictionary={}
var checkpoint_status:="尚未保存"
var _repository: RefCounted
var _save_observer=PlayerCheckpoint.new()
var _restorer=CheckpointRestore.new()
var _pending_resume: Dictionary={}
var _resume_started:=false
var _resume_frames:=0
var _save_requested:=false
var _save_wait_frames:=0
var _last_save_code:=""
var _save_scope: Label
var _player_service: RefCounted
var _service_requested:=false
var _service_wait_frames:=0
var _service_serial:=0
var last_service_result: Dictionary={}

func _ready() -> void:
	world=World.new()
	add_child(world)
	world.build("I2",{},true)
	if not world.build_errors.is_empty(): fatal="地区装配失败："+str(world.build_errors)
	var fresh:=false
	if persistence_enabled:
		var reload: Dictionary=get_tree().get_meta("canal_candidate_reload",{})
		if not reload.is_empty():
			profile_path=str(reload.path)
			fresh=bool(reload.fresh)
			get_tree().remove_meta("canal_candidate_reload")
		_repository=CheckpointRepository.new(profile_path)
		var saved: Dictionary=_repository.read()
		if not saved.ok:
			if not fresh: fatal="检查点暂时无法读取，原档已保留。按 R 可开始新演练。"
			else:
				checkpoint_status="原档读取异常"
				notes="新演练已开始，先前的检查点文件仍保留。"
			last_save_result=saved
		elif not saved.empty:
			save_generation=int(saved.generation)
			checkpoint_status="已有检查点"
			if not fresh:
				_pending_resume=saved.envelope
				loading_checkpoint=true
				world.clock_seconds=float(_pending_resume.world_clock)
				notes="正在恢复检修现场……"
	if not loading_checkpoint: _create_fresh_player()
	inputs=Inputs.new()
	add_child(inputs)
	inputs.pause_requested.connect(func(_reason: String):
		if not paused: toggle_pause())
	camera=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.current=true
	add_child(camera)
	camera_rig.configure(camera)
	camera_rig.target_size=26
	camera_rig.snap(player.position if is_instance_valid(player) else Vector3(3.5,2.8,20))
	if is_instance_valid(player):
		_install_observation()
		_register_player()
	_build_hud()
	cursor=_view(null,"TargetMarker",Vector3(.58,.03,.58),Color("78deca"))
	cursor.visible=false
	if loading_checkpoint: note_text.text=notes
	elif not fatal.is_empty(): note_text.text=fatal

func _create_fresh_player() -> void:
	player=Flight.new()
	player.name="CanalPreviewPilot"
	player.configure(Catalog.resolve_build(Catalog.default_build("tr01")))
	player.max_altitude=18.0
	player.position=Vector3(3.5,2.8,20)
	player.hold_height=player.position.y
	player.safe_position=player.position
	player.environment_query=world.sample_environment
	player.environment_hazards_authoritative=true
	add_child(player)

func _register_player() -> void:
	entities[PLAYER_ID]={"owner":"1","tags":["player"],"health":player.health,"energy":100.0,"position":player.global_position,"revision":0}

func _resume_tick(delta: float) -> void:
	inputs.active=false
	_resume_frames+=1
	if _resume_frames>600:
		_resume_failed({"code":"reconstruction_timeout"}); return
	if _resume_frames<3: return
	if not _resume_started:
		var prepared: Dictionary=_restorer.prepare(world,_pending_resume.site,world.sample_environment,true)
		if not prepared.ok: _resume_failed(prepared); return
		_resume_started=true
		return
	var advanced: Dictionary=_restorer.tick(delta,true,false)
	if not advanced.ok: _resume_failed(advanced); return
	if not advanced.ready: return
	# Only create a new body, after all current support has been reacquired.
	# A blocked saved position fails before creating/healing an existing player.
	var made: Dictionary=PlayerCheckpoint.restore_player_fresh(self,_pending_resume.player,world.sample_environment)
	if not made.ok: _resume_failed(made); return
	var adopted: Dictionary=_restorer.adopt(true)
	if not adopted.ok:
		made.body.free()
		_resume_failed(adopted); return
	player=made.body
	context=adopted.context
	executor=adopted.executor
	station=adopted.cooling
	workbench=adopted.workbench
	_register_player()
	var saved_ability: Dictionary=_pending_resume.ability
	entities[PLAYER_ID].energy=float(saved_ability.energy)
	entities[PLAYER_ID].revision=int(saved_ability.actor_revision)
	selected_ability=str(saved_ability.selected)
	cooldown=float(saved_ability.cooldown)
	station_serial=int(saved_ability.station_serial)
	site_created=true
	boot_ready=true
	executor_ready=true
	_add_site_views()
	_register_station()
	if not _bind_workbench():
		loading_checkpoint=false; return
	_last_work_notice="departed"
	beneficiary_label.text="巡检恢复"
	_install_observation()
	camera_rig.snap(player.global_position)
	_sync_entities()
	loading_checkpoint=false
	checkpoint_status="检查点已恢复"
	notes="检修现场已恢复。巡检成果与机体状态已保留；剩余维修 %d 次。"%int(context.rules.snapshot().service_credit)
	last_save_result={"ok":true,"code":"player_scene_restored","generation":save_generation,
		"initial_player":PlayerCheckpoint.State.capture(player,PLAYER_ID),
		"initial_energy":float(entities[PLAYER_ID].energy),"station_serial":station_serial,
		"initial_world_clock":world.clock_seconds}

func _resume_failed(result: Dictionary) -> void:
	_restorer.discard()
	loading_checkpoint=false
	last_save_result=result.duplicate(true)
	fatal="检查点未能恢复，原档已保留。按 R 可开始新演练。"
	if is_instance_valid(note_text): note_text.text=fatal

func _physics_process(delta: float) -> void:
	if not is_instance_valid(world) or not fatal.is_empty():
		if is_instance_valid(player): player.command={"active":false,"brake":true}
		return
	if loading_checkpoint:
		_resume_tick(delta); return
	if not is_instance_valid(player): return
	inputs.active=not paused and player.enabled
	if paused: return
	world.clock_seconds+=delta
	player.environment_sample=world.sample_environment(player.global_position)
	player.command=inputs.command(camera.global_basis)
	player.command.body_relative=false
	player.command.fire=false
	cooldown=maxf(0,cooldown-delta)
	entities[PLAYER_ID].position=player.global_position
	entities[PLAYER_ID].health=player.health
	entities[PLAYER_ID].energy=minf(100.0,float(entities[PLAYER_ID].energy)+delta*9.0)
	var timed: Dictionary=ability.advance_states(entities,delta)
	if timed.ok: ability.commit(timed,entities)
	if not site_created:
		_setup_frames+=1
		if _setup_frames<3: return
		var made: Dictionary=bootstrap.create(world,world.sample_environment,true)
		if not made.ok:
			_fail("实际泊位空间检查失败",made); return
		site_created=true
		context=bootstrap.context()
		_add_site_views()
		return
	if not boot_ready:
		var row: Dictionary=bootstrap.tick(delta,true,false)
		if not row.ok:
			_fail("运输机准备中止",row); return
		context=bootstrap.context()
		if row.ready:
			boot_ready=true
			notes="运输机已在宽湾等候。接管后留下一次工作单，机器会自行搬运。"
			if not waiting_pilot.bind(context.carrier) or not waiting_pilot.go_to(Executor.WAIT_POINT,1):
				_fail("运输机驻位准备失败",{"code":"wait_controller_bind"}); return
			if not _install_workbench(): return
	else:
		if executor_ready:
			var row: Dictionary=executor.tick(delta,true,false)
			if not row.ok:
				_fail("自动搬运已停止",row); return
		else:
			var row: Dictionary=context.custody.step(delta,true,false)
			if not row.ok:
				_fail("货物状态检查失败",row); return
			# Braking holds velocity, not horizontal position in persistent wind.
			# Keep the already-reached real WAIT through ordinary swept controls;
			# never advance a transport action before the player leaves an order.
			context.carrier.environment_sample=world.sample_environment(context.carrier.global_position)
			waiting_report=waiting_pilot.tick(delta,true,false)
	if station==null and context.get("custody")!=null:
		station=Station.new()
		world.add_child(station)
		var installed: Dictionary=station.configure(context.cargos,context.berths,context.custody,true)
		if not installed.ok:
			_fail("回冷座装配失败",installed); return
		_register_station()
	if is_instance_valid(station):
		var moved: Dictionary=station.advance(delta,true)
		if not moved.ok:
			_fail("回冷阀检查失败",moved); return
	if boot_ready:
		rule_frames+=1
		var next_usec: int=roundi(float(rule_frames)*1000000.0/float(Engine.physics_ticks_per_second))
		var facts: Dictionary=_cooling_facts()
		var advanced: Dictionary=context.rules.step(next_usec-rule_usec,facts,true,false)
		if not advanced.ok:
			_fail("回冷循环检查失败",advanced); return
		rule_usec=next_usec
	if is_instance_valid(workbench):
		var processed: Dictionary=workbench.advance(delta,true,false)
		if not processed.ok:
			_fail("标定工位已停止",processed); return
		if processed.committed and _last_work_notice.is_empty():
			_last_work_notice="committed"
			notes="标定完成，巡检机正在离架。回收结束后可在工位旁按 G 修复机体，最多恢复25点生命。"
		if processed.phase=="departed" and _last_work_notice!="departed":
			_last_work_notice="departed"
			notes="巡检机已重新出发。运输机继续回收原匣；之后可在标定架旁按 G 使用一次维修。"
		beneficiary_label.text="巡检恢复" if processed.phase=="departed" else "巡检机" if processed.committed else "待标定巡检机"
	_sync_entities()
	if _service_requested: _advance_player_service()
	if _save_requested: _capture_requested_checkpoint()

func request_player_service() -> Dictionary:
	if paused or loading_checkpoint or not fatal.is_empty(): return {"ok":false,"code":"session_unavailable"}
	if _service_requested: return {"ok":true,"code":"service_already_requested"}
	if not persistence_enabled or _repository==null:
		notes="本次验证没有开启检查点，维修暂不可用。"
		return {"ok":false,"code":"persistence_disabled"}
	if _save_requested:
		notes="正在保存检查点，请保存结束后再维修。"
		return {"ok":false,"code":"save_pending"}
	if not executor_ready or not is_instance_valid(workbench) or not is_instance_valid(station) or workbench.report().phase!="departed":
		notes="先帮助巡检机完成标定并离架，即可获得一次机体维修。"
		return {"ok":false,"code":"completed_live_work_required"}
	var state: Dictionary=context.rules.snapshot()
	if int(state.service_credit)<1:
		notes="这次检修提供的维修机会已用完。巡检成果仍然保留。"
		return {"ok":false,"code":"awaiting_new_beneficiary"}
	if player.health>=player.maximum_health:
		notes="机体完好，无需维修；这次维修机会已保留。"
		return {"ok":false,"code":"hull_already_full"}
	if _player_service==null:
		_player_service=PlayerService.new()
		var bound: Dictionary=_player_service.configure(context,executor,workbench,station,player,_repository)
		if not bound.ok:
			_player_service=null
			return bound
	var access: Dictionary=_player_service.interaction()
	if not access.ok:
		notes="请靠近标定架的供电触点（4米内），并保持直视工位。"
		return access
	_service_serial=int(state.service_serial)+1
	_service_wait_frames=0
	_service_requested=true
	_player_service.reset_observation()
	notes="正在准备维修，请在工位旁空中制动，等待货物回位。"
	return {"ok":true,"code":"service_requested"}

func _advance_player_service() -> void:
	_service_wait_frames+=1
	for entity: Dictionary in entities.values():
		if float(entity.get("takeover_remaining",0))>0:
			_player_service.reset_observation()
			if _service_wait_frames>=1200: _end_service_wait()
			return
	var ability_state: Dictionary={"energy":float(entities[PLAYER_ID].energy),"selected":selected_ability,"cooldown":cooldown,"actor_revision":int(entities[PLAYER_ID].revision),"station_serial":station_serial}
	_player_service.observe(ability_state,world.clock_seconds,true,false)
	last_service_result=_player_service.request(_service_serial,save_generation,ability_state,world.clock_seconds,true,false)
	if last_service_result.get("reload_required",false):
		_service_requested=false
		_save_requested=false
		if not paused: toggle_pause()
		fatal="维修记录需要重新载入，现场已暂停。请按 F9 恢复已保存的结果。"
		return
	if last_service_result.ok:
		_service_requested=false
		save_generation=int(last_service_result.generation)
		checkpoint_status="维修结果已保存"
		entities[PLAYER_ID].health=player.health
		notes="机体恢复 %.0f 点生命，维修结果已保存。电池、装甲与部件状态保持原样。"%float(last_service_result.healed_hp)
		return
	var code: String=str(last_service_result.code)
	if code.begins_with("safe_checkpoint:"):
		if _service_wait_frames>=1200: _end_service_wait()
		return
	_service_requested=false
	_player_service.reset_observation()
	if code in ["service_out_of_range","service_obstructed"]:
		notes="已取消维修：请靠近标定架触点，并保持直视工位。维修机会未消耗。"
	elif code=="hull_already_full": notes="机体完好，维修机会已保留。"
	elif code=="awaiting_new_beneficiary": notes="这次维修机会已用完，巡检成果仍然保留。"
	else: notes="维修未能保存，机体与维修机会均保留。请稍后重试。"

func _end_service_wait() -> void:
	_service_requested=false
	_player_service.reset_observation()
	notes="现场尚未稳定，维修机会未消耗。货物回位后，在工位旁制动并再次按 G。"

func _register_station() -> void:
	bodies[RELAY_ID]=station.relay
	bodies[VALVE_ID]=station.valve
	entities[RELAY_ID]={"owner":"neutral","tags":["conductive","electrical"],"charge":float(station.report().charge),"charge_capacity":100.0,"power_threshold":20.0,"position":station.relay.global_position,"revision":0}
	entities[VALVE_ID]={"owner":"neutral","tags":["movable"],"position":station.valve.global_position,"revision":0}

func request_save_checkpoint() -> Dictionary:
	if _service_requested:
		notes="正在准备维修，结果会一同保存；可先等待维修结束。"
		return {"ok":false,"code":"service_pending"}
	if not persistence_enabled or _repository==null:
		return {"ok":false,"code":"persistence_disabled"}
	if paused or loading_checkpoint or not fatal.is_empty() or not executor_ready or not is_instance_valid(workbench) or workbench.report().phase!="departed":
		notes="巡检机完成标定并离架后，可在空中制动保存检查点。"
		return {"ok":false,"code":"completed_live_work_required"}
	_save_observer.reset_observation()
	_save_requested=true
	_save_wait_frames=0
	notes="正在等待运输机与货物落稳；请在空旷处按住空格制动。"
	return {"ok":true,"code":"save_requested"}

func _capture_requested_checkpoint() -> void:
	_save_wait_frames+=1
	var active_lease:=false
	for entity: Dictionary in entities.values():
		if float(entity.get("takeover_remaining",0))>0: active_lease=true
	var sampled: Dictionary={"ok":false,"code":"active_control_lease"}
	if active_lease: _save_observer.reset_observation()
	else:
		var state: Dictionary={"energy":float(entities[PLAYER_ID].energy),"selected":selected_ability,"cooldown":cooldown,"actor_revision":int(entities[PLAYER_ID].revision),"station_serial":station_serial}
		sampled=_save_observer.capture(context,executor,workbench,station,player,state,world.clock_seconds,true,false)
	_last_save_code=str(sampled.code)
	if not sampled.ok:
		if _save_wait_frames>=1200:
			_save_requested=false
			last_save_result=sampled.duplicate(true)
			notes="暂未形成安全检查点。等待货物落稳，在无接触的空中制动后再按 F5。"
		return
	_save_requested=false
	var id: String=Crypto.new().generate_random_bytes(16).hex_encode()
	last_save_result=_repository.save(sampled.envelope,id,save_generation)
	if last_save_result.ok:
		save_generation=int(last_save_result.generation)
		checkpoint_status="检查点已保存"
		notes="检查点已保存。下次进入可从这里继续；按 F9 可立即恢复。"
	else:
		notes="保存未成功，先前的检查点已保留。可稍后重试。"

func reload_checkpoint(fresh: bool=false) -> Dictionary:
	if not persistence_enabled or _repository==null: return {"ok":false,"code":"persistence_disabled"}
	if not fresh:
		var saved: Dictionary=_repository.read()
		if not saved.ok or saved.empty:
			notes="尚无可恢复的检查点。"
			return saved if not saved.ok else {"ok":false,"code":"no_checkpoint"}
	get_tree().set_meta("canal_candidate_reload",{"path":profile_path,"fresh":fresh})
	var error: int=get_tree().reload_current_scene()
	if error!=OK: get_tree().remove_meta("canal_candidate_reload")
	return {"ok":error==OK,"code":"scene_reload_requested" if error==OK else "scene_reload_failed"}

func _cooling_facts() -> Dictionary:
	var facts: Dictionary=station.facts() if is_instance_valid(station) else {"powered":false,"valve_open":false,"sweep_clear":false,"contacts":{Runtime.SOUTH_0:"",Runtime.SOUTH_1:""}}
	cooling_transfer_wait={}
	if not executor_ready: return facts
	var state: Dictionary=context.rules.snapshot()
	var physical: Dictionary=executor.report()
	var pending: Dictionary=state.pending_action
	# Actual contact can become stable in the frame before the executor commits
	# its place receipt. The cooling coupler stays disconnected during this known
	# ownership handoff. Do not suppress any other rules/physics discrepancy.
	if pending.get("kind","")!="place" or physical.phase not in ["fall","commit"] or not physical.released: return facts
	if not context.carrier.cargo_items.is_empty(): return facts
	for key: String in Executor.MATCH_KEYS:
		if not physical.action.has(key) or physical.action[key]!=pending[key]: return facts
	var id: String=str(pending.cassette_id)
	var berth: String=str(pending.destination)
	if berth not in [Runtime.SOUTH_0,Runtime.SOUTH_1] or facts.contacts[berth]!=id: return facts
	if state.cassettes[id].holder!=Runtime.CARRIER or not context.custody.support_info(id,berth).get("supported",false): return facts
	facts.contacts[berth]=""
	cooling_transfer_delay_count+=1
	cooling_transfer_wait={"cassette_id":id,"berth":berth,"pending_serial":pending.serial,"executor_phase":physical.phase,"code":"stable_contact_waiting_for_place_commit"}
	return facts

func _process(delta: float) -> void:
	if is_instance_valid(_save_scope): _save_scope.text="交互样板 · "+checkpoint_status if persistence_enabled else "交互样板 · 验证中"
	if not is_instance_valid(player): return
	camera_rig.update(delta,player.global_position,player.linear_velocity)
	observation.observe(bodies.get(target),workbench)
	observation.update(delta)
	if not is_instance_valid(status_text): return
	var caption: String="暂停" if paused else "准备起飞" if not boot_ready else "等待工作单" if not executor_ready else _phase_name(str(executor.report().get("phase","")))
	if not paused and is_instance_valid(workbench):
		var work: Dictionary=workbench.report()
		if work.phase=="departed":
			var credit: int=int(context.rules.snapshot().service_credit)
			caption="巡检已出发 · 可维修一次" if credit>0 else "巡检已恢复 · 本次维修已用"
		elif work.committed: caption="标定完成 · 巡检机离架中"
		elif not work.action.is_empty():
			var reason: String=str(work.code)
			caption="标定工位待通电" if not work.powered else "标定中" if reason=="tool_moving" else "工位匣过热" if reason=="work_cassette_overheated" else "标定工具被挡" if reason=="tool_blocked" else "等待工位匣落稳" if reason in ["actual_work_cassette_required","work_cassette_contact_required"] else "标定暂候"
	status_text.text="南湾检修线    生命 %.0f    能量 %.0f    %s"%[player.health,float(entities.get(PLAYER_ID,{}).get("energy",0)),caption]
	var temperatures: Dictionary=context.rules.status().temperatures_c if boot_ready else {}
	var extra: String=""
	if not temperatures.is_empty(): extra="蓝标匣 %.1f°C · 橙标匣 %.1f°C"%[float(temperatures[Runtime.CASSETTES[0]]),float(temperatures[Runtime.CASSETTES[1]])]
	if is_instance_valid(station) and station.configured:
		var facts: Dictionary=station.facts()
		extra+="  回冷：%s / %s"%["有电" if facts.powered else "断电","阀开" if facts.valve_open else "阀关"]
	hint_text.text=extra+"    当前能力："+_ability_name(selected_ability)
	note_text.text=fatal if not fatal.is_empty() else notes
	if target in bodies and is_instance_valid(bodies[target]):
		cursor.visible=true
		cursor.global_position=bodies[target].global_position+Vector3.UP*.36
		_update_target_hint()
	else:
		cursor.visible=false
		target_panel.visible=false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index==MOUSE_BUTTON_WHEEL_UP: camera_rig.zoom(1)
		elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN: camera_rig.zoom(-1)
	if not event is InputEventKey or not event.pressed or event.echo: return
	var key: int=event.physical_keycode
	if key==0: key=event.keycode
	if key in [KEY_P,KEY_ESCAPE]:
		if loading_checkpoint or not is_instance_valid(player) or not fatal.is_empty(): return
		toggle_pause(); return
	if key==KEY_R:
		reload_checkpoint(true); return
	if key==KEY_F9:
		reload_checkpoint(false); return
	if key==KEY_F5:
		request_save_checkpoint(); return
	if paused or not fatal.is_empty(): return
	if key==KEY_G: request_player_service()
	elif key==KEY_2: selected_ability="push_pull"
	elif key==KEY_5: selected_ability="heat"
	elif key==KEY_6: selected_ability="charge"
	elif key==KEY_0: selected_ability="takeover"
	elif key==KEY_TAB: cycle_target()
	elif key in [KEY_F,KEY_X]: use_selected(key==KEY_X)

func cycle_target() -> void:
	var candidates: Array=[]
	for id: String in bodies:
		if is_instance_valid(bodies[id]) and player.global_position.distance_to(bodies[id].global_position)<=45.0: candidates.append(id)
	candidates.sort_custom(func(a: String,b: String): return player.global_position.distance_squared_to(bodies[a].global_position)<player.global_position.distance_squared_to(bodies[b].global_position))
	if candidates.is_empty(): return
	target=candidates[(candidates.find(target)+1)%candidates.size()]

func use_selected(reverse: bool = false) -> Dictionary:
	if paused or not fatal.is_empty() or cooldown>0.0: return {"ok":false,"code":"not_ready"}
	_sync_entities()
	var modes: Dictionary={"heat":"cool","charge":"drain","push_pull":"pull"}
	var intent: Dictionary={"actor_id":PLAYER_ID,"ability":selected_ability,"target_id":target,"mode":modes.get(selected_ability,"") if reverse else ""}
	var los:=false
	if target in bodies and is_instance_valid(bodies[target]):
		var query:=PhysicsRayQueryParameters3D.create(player.global_position,bodies[target].global_position,MASK,[player.get_rid()])
		var hit: Dictionary=get_world_3d().direct_space_state.intersect_ray(query)
		los=not hit.is_empty() and hit.get("collider")==bodies[target]
	var resolved: Dictionary=ability.resolve(intent,entities,{"sender_id":"1","line_of_sight":los})
	if not resolved.ok: return _decline(resolved)
	# Stage the generic energy/entity transaction in a private candidate. Only
	# adopt it after the actual device accepted the same synchronous operation.
	var candidate: Dictionary=entities.duplicate(true)
	var checked: Dictionary=ability.commit(resolved,candidate,true)
	if not checked.ok: return _decline(checked)
	var applied: Dictionary={"ok":false,"code":"unsupported_target"}
	if selected_ability=="heat" and target in Runtime.CASSETTES:
		if not boot_ready: return _decline({"ok":false,"code":"boot_required"})
		command_serial=int(context.rules.snapshot().command_serial)+1
		applied=context.rules.apply_command({"serial":command_serial,"expected_revision":context.rules.snapshot().revision,"kind":"thermal","cassette_id":target,"delta_mc":-25000 if reverse else 25000},true,false)
	elif selected_ability=="charge" and target==RELAY_ID:
		station_serial+=1
		applied=station.apply_charge(-35.0 if reverse else 35.0,station_serial,true)
	elif selected_ability=="charge" and target==Workbench.POWER_ID and is_instance_valid(workbench):
		station_serial+=1
		applied=workbench.apply_charge(-35.0 if reverse else 35.0,station_serial,true,false)
	elif selected_ability=="push_pull" and target==VALVE_ID:
		station_serial+=1
		if resolved.physics_requests.size()==1: applied=station.apply_impulse(resolved.physics_requests[0].impulse,station_serial,true)
	elif selected_ability=="takeover" and target==CARRIER_ID:
		if not boot_ready: return _decline({"ok":false,"code":"boot_required"})
		if executor_ready: return _decline({"ok":false,"code":"work_order_exists"})
		applied=executor.configure(context.carrier,context.cargos,context.berths,context.custody,context.rules,context.environment_query,true)
		if applied.ok: executor_ready=true
		else: applied.actual_wait={"position":context.carrier.global_position,"speed":context.carrier.linear_velocity.length(),"distance":context.carrier.global_position.distance_to(Executor.WAIT_POINT),"anchor":context.rules.snapshot().carrier_anchor,"pending":context.rules.snapshot().pending_action,"controller":waiting_report.duplicate(true)}
	if not applied.ok: return _decline(applied)
	entities=candidate
	cooldown=.35
	notes="已留下工作单。可以离开处理回冷座，运输机会自己继续。" if selected_ability=="takeover" else "已%s：%s"%[_ability_name(selected_ability),_target_name(target)]
	last_action={"ok":true,"ability":selected_ability,"target":target,"mode":intent.mode,"physical":applied.duplicate(true)}
	_sync_entities()
	return last_action.duplicate(true)

func toggle_pause() -> void:
	paused=not paused
	inputs.clear()
	if _player_service!=null: _player_service.reset_observation()
	if paused:
		_frozen.clear()
		for node in find_children("*","RigidBody3D",true,false):
			_frozen[node.get_instance_id()]={"node":weakref(node),"was_frozen":node.freeze}
			node.freeze=true
	else:
		for row: Dictionary in _frozen.values():
			var body: Variant=row.node.get_ref()
			if is_instance_valid(body): body.freeze=bool(row.was_frozen)
		_frozen.clear()
	if is_instance_valid(station): station.set_paused(paused,true)

func _sync_entities() -> void:
	if not site_created: return
	for id: String in bodies:
		if id in entities and is_instance_valid(bodies[id]): entities[id].position=bodies[id].global_position
	if boot_ready:
		var temperatures: Dictionary=context.rules.status().temperatures_c
		for id: String in Runtime.CASSETTES:
			entities[id].temperature=float(temperatures[id])
			var material: StandardMaterial3D=_cargo_views[id].material_override
			material.albedo_color=Color("689baf").lerp(Color("c88450"),clampf((float(temperatures[id])-20.0)/50.0,0.0,1.0))
	if is_instance_valid(station) and RELAY_ID in entities: entities[RELAY_ID].charge=float(station.report().charge)
	if is_instance_valid(workbench) and Workbench.POWER_ID in entities: entities[Workbench.POWER_ID].charge=float(workbench.report().charge)

func _install_workbench() -> bool:
	workbench=Workbench.new()
	world.add_child(workbench)
	var installed: Dictionary=workbench.configure(context,true)
	if not installed.ok:
		_fail("标定工位装配失败",installed)
		return false
	return _bind_workbench()

func _bind_workbench() -> bool:
	rack_art=RackArt.install(workbench.rack)
	if not rack_art.ok:
		_fail("标定台模型装配失败",rack_art)
		return false
	for entry: Dictionary in workbench.targets():
		var id: String=entry.id
		bodies[id]=entry.body
		entities[id]={"owner":"neutral","tags":["conductive","electrical"],"charge":entry.charge,"charge_capacity":100.0,"power_threshold":20.0,"position":entry.body.global_position,"revision":0}
	beneficiary_label=Label3D.new()
	beneficiary_label.text="待标定巡检机"
	beneficiary_label.font=load("res://assets/fonts/NotoSansSC-Medium.ttf")
	beneficiary_label.font_size=32
	beneficiary_label.pixel_size=.012
	beneficiary_label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	beneficiary_label.position=Vector3(0,.9,0)
	workbench.beneficiary.add_child(beneficiary_label)
	beneficiary_label.name="BeneficiaryName"
	return true

func _add_site_views() -> void:
	for id: String in context.berths:
		_view(context.berths[id],"BerthSurface",Vector3(2,.5,2),Color("748888"))
	for index in 2:
		var id: String=Runtime.CASSETTES[index]
		_cargo_views[id]=_view(context.cargos[id],"ThermalCartridge",Vector3(.4,.4,.4),Color("689baf") if index==0 else Color("c88450"))
		var stripe:=_view(context.cargos[id],"FixedIdentityStripe",Vector3(.30,.015,.12),Color("4694ce") if index==0 else Color("e3a04c"))
		stripe.position.y=.205
		bodies[id]=context.cargos[id]
		entities[id]={"owner":"neutral","tags":["thermal"],"temperature":20.0 if index==0 else 70.0,"position":context.cargos[id].global_position,"revision":0}
	bodies[CARRIER_ID]=context.carrier
	entities[CARRIER_ID]={"owner":"neutral","tags":["mechanical","hackable"],"position":context.carrier.global_position,"revision":0}
	target=CARRIER_ID

func _install_observation() -> void:
	var covers: Array=[]
	if is_instance_valid(world.underdeck): covers.append(world.underdeck.shell)
	if is_instance_valid(world.clinic):
		for id: String in ["PumpRoof","PumpWestWall","PumpEastWall","PumpNorthWall"]:
			covers.append(world.clinic.fixed_bodies[id])
		covers.append_array(world.clinic.gravity_art.get("occluders",[]))
		covers.append_array(world.clinic.reception_art.get("occluders",[]))
	if is_instance_valid(world.distribution):
		for id: String in ["LeftWall","RightWall","BackWall","RoofLeft","RoofRight","RoofBack","RoofFront","UpperDeckLeft","UpperDeckRight","UpperDeckBack","UpperDeckFront","UpperFrontApron"]:
			covers.append(world.distribution.fixed_bodies[id])
		covers.append(world.distribution.door)
	if is_instance_valid(world.shared_access):
		var controls: Array=world.shared_access.target_bodies.values()
		for structure in world.shared_access.fixed_bodies.values()+world.shared_access.moving_bodies.values():
			if structure not in controls: covers.append(structure)
	observation.setup(camera,player,covers)

func _exit_tree() -> void:
	observation.clear()

func _view(parent: Node3D,label: String,size: Vector3,color: Color) -> MeshInstance3D:
	var mesh:=MeshInstance3D.new()
	mesh.name=label
	var box:=BoxMesh.new()
	box.size=size
	var material:=StandardMaterial3D.new()
	material.albedo_color=color
	material.roughness=.7
	mesh.mesh=box
	mesh.material_override=material
	(parent if parent!=null else self).add_child(mesh)
	return mesh

func _build_hud() -> void:
	var layer:=CanvasLayer.new()
	add_child(layer)
	var hud:=Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var theme:=Theme.new()
	theme.default_font=load("res://assets/fonts/NotoSansSC-Medium.ttf")
	theme.default_font_size=16
	hud.theme=theme
	layer.add_child(hud)
	var panel:=PanelContainer.new()
	panel.position=Vector2(20,16)
	panel.size=Vector2(1240,70)
	var style:=StyleBoxFlat.new()
	style.bg_color=Color(.025,.07,.08,.94)
	style.content_margin_left=16
	style.content_margin_top=8
	style.content_margin_bottom=8
	style.content_margin_right=16
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel",style)
	panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	hud.add_child(panel)
	var top_stack:=VBoxContainer.new()
	panel.add_child(top_stack)
	status_text=Label.new()
	status_text.add_theme_font_size_override("font_size",18)
	top_stack.add_child(status_text)
	hint_text=Label.new()
	hint_text.add_theme_font_size_override("font_size",15)
	hint_text.add_theme_color_override("font_color",Color("acd4ca"))
	top_stack.add_child(hint_text)
	var bottom:=PanelContainer.new()
	bottom.position=Vector2(20,620)
	bottom.size=Vector2(1240,84)
	bottom.add_theme_stylebox_override("panel",style)
	bottom.mouse_filter=Control.MOUSE_FILTER_IGNORE
	hud.add_child(bottom)
	var stack:=VBoxContainer.new()
	bottom.add_child(stack)
	note_text=Label.new()
	note_text.add_theme_color_override("font_color",Color("acd4ca"))
	note_text.add_theme_font_size_override("font_size",16)
	stack.add_child(note_text)
	var controls:=Label.new()
	controls.text="WASD 飞行 · E/Q 升降 · 空格制动 · Tab 换目标 · F 使用 / X 反向 · 滚轮缩放\n2 推拉 · 5 热量 · 6 充能 · 0 接管 · G 工位维修 · P 暂停 · F5 保存 · F9 恢复 · R 新演练"
	controls.add_theme_font_size_override("font_size",15)
	stack.add_child(controls)
	var scope:=Label.new()
	_save_scope=scope
	scope.position=Vector2(1028,28)
	scope.text="交互样板 · "+checkpoint_status
	scope.add_theme_font_size_override("font_size",14)
	scope.add_theme_color_override("font_outline_color",Color("15272b"))
	scope.add_theme_constant_override("outline_size",4)
	hud.add_child(scope)
	target_panel=PanelContainer.new()
	target_panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var target_style: StyleBoxFlat=style.duplicate()
	target_style.bg_color=Color(.025,.07,.08,.85)
	target_style.border_color=Color("7bbbad")
	target_style.set_border_width_all(1)
	target_panel.add_theme_stylebox_override("panel",target_style)
	hud.add_child(target_panel)
	target_text=Label.new()
	target_text.add_theme_font_size_override("font_size",15)
	target_panel.add_child(target_text)
	target_panel.visible=false

func _update_target_hint() -> void:
	var body: Node3D=bodies[target]
	var distance: float=player.global_position.distance_to(body.global_position)
	var detail: String=""
	if target==CARRIER_ID:
		detail="正在准备起飞" if not boot_ready else "工作单已留下 · 可离开" if executor_ready else "0 接管 → F 留下工作单"
	elif target==RELAY_ID:
		detail="已通电" if station.facts().powered else "6 充能 → F 通电"
	elif target==Workbench.POWER_ID:
		detail="工位已通电" if workbench.report().powered else "6 充能 → F 通电"
		if workbench.report().phase=="departed":
			detail="G 工位维修 · 最多恢复25点" if int(context.rules.snapshot().service_credit)>0 else "本次维修已用 · 巡检成果保留"
	elif target==VALVE_ID:
		var operation: String="F 推开" if player.global_position.z<body.global_position.z else "X 拉开"
		detail="阀门已开" if station.facts().valve_open else "2 推拉 → "+operation
	elif target in Runtime.CASSETTES:
		detail="5 热量 → X 降温"
	var screen: Vector2=camera.unproject_position(body.global_position+Vector3.UP*.65)
	var outside: bool=camera.is_position_behind(body.global_position) or screen.x<24 or screen.x>1010 or screen.y<110 or screen.y>558
	target_text.text="%s · %.1fm%s\n%s"%[_target_name(target),distance,"（画面边缘）" if outside else "",detail]
	target_panel.reset_size()
	var preferred:=Vector2(screen.x-target_panel.size.x*.5,screen.y-target_panel.size.y-8)
	var pilot_screen: Vector2=camera.unproject_position(player.global_position)
	var pilot_clearance:=Rect2(pilot_screen-Vector2(52,42),Vector2(104,84))
	# A nearby device can project onto the aircraft. Keep its label outside the
	# player's flight silhouette instead of hiding the very body being piloted.
	var placements: Array[Vector2]=[preferred,
		Vector2(pilot_clearance.end.x+12,preferred.y),
		Vector2(pilot_clearance.position.x-target_panel.size.x-12,preferred.y),
		Vector2(preferred.x,pilot_clearance.position.y-target_panel.size.y-12),
		Vector2(preferred.x,pilot_clearance.end.y+12)]
	for proposed: Vector2 in placements:
		var position_in_hud:=Vector2(clampf(proposed.x,24,1256-target_panel.size.x),clampf(proposed.y,104,610-target_panel.size.y))
		if not Rect2(position_in_hud,target_panel.size).intersects(pilot_clearance):
			target_panel.position=position_in_hud
			break
	target_panel.visible=true

func _decline(result: Dictionary) -> Dictionary:
	var messages: Dictionary={"out_of_range":"距离太远，请靠近目标。","line_of_sight_required":"中间有遮挡，请换一个角度。","unsupported_target":"这个物件不支持当前作用。","insufficient_energy":"能量不足。","target_busy":"正在使用中。","boot_required":"先让运输机安全到达宽湾。","work_order_exists":"已有工作单，运输机会自行继续。","fresh_actual_wait_required":"运输机正在重新驻稳，稍候再留下工作单。"}
	notes=str(messages.get(str(result.get("code","")),"操作未执行："+str(result.get("code",""))))
	last_action=result.duplicate(true)
	return last_action

func _fail(message: String,details: Dictionary) -> void:
	fatal=message+"："+str(details.get("code",details))
	if not paused: toggle_pause()
	push_error(fatal)

static func _target_name(id: String) -> String:
	return {CARRIER_ID:"运输机",RELAY_ID:"回冷继电器",VALVE_ID:"回冷旁路阀",Workbench.POWER_ID:"标定工位供电",Runtime.CASSETTES[0]:"蓝标密封匣",Runtime.CASSETTES[1]:"橙标密封匣"}.get(id,"无")

static func _ability_name(id: String) -> String:
	return {"takeover":"接管","push_pull":"推拉","heat":"热量","charge":"充能"}.get(id,id)

static func _phase_name(phase: String) -> String:
	if phase=="awaiting_external": return "已到工位，等待检修接续"
	if phase=="idle": return "调度中"
	if phase=="fault": return "需要处理阻挡或物件变化"
	return "自动搬运中"
