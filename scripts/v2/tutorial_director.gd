class_name TutorialDirectorV22
extends Node

## A separate, reward-free learning journal. Gameplay owns all task outcomes.
signal state_changed(state: Dictionary)

const COURSES = {
	"M01": [
		["lift", "轻轻起飞", "左杆向上，升到约 3 米。辅助模式松杆定高；手动模式需自己维持油门。", "flight_vertical", 0.4],
		["hover", "稳稳悬停", "把位置稳定下来，保持两秒。先观察机头，再决定下一步。", "flight_sticks", 2.0],
		["yaw90", "认识机头方向", "左杆向左或右，原地转向约 90°。机头箭头会告诉你接下来前飞的方向。", "flight_yaw", 0.0],
		["forward", "向前飞行", "右杆向前，朝机头前方飞出约 4 米。两种模式都跟随机头方向。", "flight_sticks", 0.0],
		["strafe", "横向移动", "右杆向左或右，侧移约 3 米。小幅输入更容易控制。", "flight_sticks", 0.0],
		["brake", "及时制动", "先轻推右杆飞起来，再按住制动，直到地速接近零。", "flight_brake", 0.8],
		["land", "轻柔着陆", "飞到平坦地面上，降低高度，停稳着陆。", "flight_vertical", 0.7],
		["zoom", "找到合适视野", "使用 + / − 或滚轮调整视野。固定斜视方向保持不变。", "camera_zoom", 0.0]
	],
	"M02": [
		["cargo_pickup", "对准货物", "对准领取座，在 1.2—3 米高度保持交互，直到吊具确实挂上货物。", "flight_interact", 0.0],
		["swing", "稳定吊挂", "轻推轻停，让货物摆角回到 15° 内，并稳定两秒。", "flight_brake", 2.0],
		["delivery", "准确交付", "飞到任务交付点，停稳并保持交互，等待任务确认交付。", "flight_interact", 0.0]
	],
	"M03": [
		["scan", "完成扫描", "装配扫描工具，在标记处按要求保持交互，完成一次真实扫描。", "flight_interact", 0.0],
		["route", "沿航线作业", "观察航图与世界目标，实际完成一段取送路线。", "map", 0.0],
		["cover", "利用掩体", "警报出现后移动到建筑掩护后，让墙体挡住敌机视线至少一秒。", "flight_cover", 0.0]
	]
}

var session: Node
var journal: Dictionary = {"version":2, "courses":{}}
var course = "M01"
var index = 0
var active = false
var status = "idle"
var replaying = false
var hold = 0.0
var baseline: Dictionary = {}
var evidence: Dictionary = {}
var pending_events: Dictionary = {}
var subtitle = ""
var _publish_clock = 0.0
var _dirty = false
var skipped_steps: Array[String] = []

func configure(value: Node) -> void:
	session = value
	var stored: Variant = session.repository.data.settings.get("tutorial_v22", {})
	if stored is Dictionary and stored.get("courses", {}) is Dictionary:
		journal = {"version":2, "courses":stored.get("courses", {}).duplicate(true)}
	else:
		journal = {"version":2, "courses":{}}
	# Wind and interference are now occasional world encounters, not prerequisites.
	# Old journals waiting at those final steps already finished the core lesson.
	for id in ["M02","M03"]:
		var saved: Dictionary = journal.courses.get(id,{})
		if saved.is_empty(): continue
		if int(saved.get("index",0)) >= COURSES[id].size():
			saved["index"] = COURSES[id].size()
			saved["status"] = "completed"
			saved["completed"] = true
			saved["evidence_complete"] = true
		var legacy_skips: Array = saved.get("skipped_steps",[])
		legacy_skips.erase("wind")
		legacy_skips.erase("interference")
		saved["skipped_steps"] = legacy_skips
	active = false
	status = "idle"
	_dirty = false
	subtitle = ""
	skipped_steps.clear()
	baseline.clear()
	evidence.clear()
	pending_events.clear()
	if stored is Dictionary and not stored.is_empty() and int(stored.get("version",1)) < 2: _persist()
	if is_instance_valid(session.audio) and session.audio.has_signal("voice_started"):
		if not session.audio.voice_started.is_connected(_voice_started): session.audio.voice_started.connect(_voice_started)
	_publish()

func start(value = "M01", automatic = false) -> void:
	if not COURSES.has(value): return
	# A new flight may rebuild the aircraft. Preserve explicit replay while resetting
	# position evidence so a scene transition cannot count as real displacement.
	if automatic and active and course == value:
		_enter_step()
		return
	course = value
	replaying = false
	var saved: Dictionary = journal.courses.get(course, {})
	pending_events=saved.get("task_evidence",{}).duplicate(true) if saved.get("task_evidence",{}) is Dictionary else {}
	skipped_steps.assign(saved.get("skipped_steps",[]))
	if automatic and str(saved.get("status","")) in ["skipped","deferred","completed"]:
		active = false
		status = str(saved.status)
		index = clampi(int(saved.get("index",0)),0,COURSES[course].size())
		_stop_voice()
		_publish()
		return
	var resume_in_progress = automatic and str(saved.get("status","")) in ["in_progress","active"]
	if bool(saved.get("completed", false)) and not resume_in_progress:
		active = false
		status = "completed"
		index = COURSES[course].size()
		_publish()
		return
	if resume_in_progress and bool(saved.get("completed",false)): replaying = true
	index = clampi(int(saved.get("index", 0)), 0, COURSES[course].size()-1)
	active = true
	status = "active"
	_enter_step()

func auto_start(value = "M01") -> void:
	start(value,true)

func replay(value = "M01") -> void:
	if not COURSES.has(value): return
	course = value
	index = 0
	replaying = true
	pending_events.clear()
	skipped_steps.clear()
	active = true
	status = "active"
	_enter_step()

func skip() -> void:
	active = false
	status = "skipped"
	_stop_voice()
	_save()
	_publish()

func later() -> void:
	active = false
	status = "deferred"
	_stop_voice()
	_save()
	_publish()

func on_ui_action(id: String) -> void:
	# UI can acknowledge camera adjustment only; flight skills need telemetry.
	if active and _step_id() == "zoom" and id in ["zoom", "camera_zoom", "zoom_in", "zoom_out"]:
		evidence["zoom_requested"] = true

func on_task_event(id: String, payload: Dictionary = {}) -> void:
	# Callers are gameplay completion hooks, never menu buttons.
	if not active or not bool(payload.get("confirmed", false)): return
	for step in COURSES[course]:
		if id == str(step[0]):
			pending_events[id] = payload.duplicate(true)
			_save()
			break

func physics_update(delta: float, pilot: Node3D, input_frame: Dictionary) -> void:
	if not active or not is_instance_valid(pilot) or delta <= 0.0: return
	if not is_instance_valid(session) or not session.flight_active or get_tree().paused: return
	var telemetry: Dictionary = pilot.get("telemetry") if pilot.get("telemetry") is Dictionary else {}
	if telemetry.is_empty(): return
	var position_m: Vector3 = telemetry.get("position_m", pilot.global_position)
	var velocity: Vector3 = telemetry.get("velocity_mps", Vector3.ZERO)
	var altitude = float(telemetry.get("altitude_agl_m", 0.0))
	var speed = float(telemetry.get("speed_mps", Vector2(velocity.x, velocity.z).length()))
	var heading = float(pilot.get("heading"))
	var axes: Dictionary = input_frame.get("axes", {})
	var held: Array = input_frame.get("held", [])
	if baseline.is_empty(): _capture_baseline(position_m, heading, pilot)
	var step = _step_id()
	var valid = false
	var rx = float(axes.get("right_x", input_frame.get("roll", 0.0)))
	var ry = float(axes.get("right_y", input_frame.get("pitch", 0.0)))
	var ly = float(axes.get("left_y", input_frame.get("vertical", 0.0)))
	var yaw = float(axes.get("left_x", input_frame.get("yaw", 0.0)))
	var brake = held.has("brake") or bool(input_frame.get("brake", false))
	if altitude > 1.5: evidence["airborne"] = true
	match step:
		"lift":
			if ly > 0.12: evidence["lift_input"] = true
			valid = altitude >= 2.6 and altitude <= 6.0 and bool(evidence.get("lift_input", false))
		"hover": valid = altitude > 1.5 and altitude < 8.0 and speed < 0.55 and absf(velocity.y) < 0.35 and Vector2(rx, ry).length() < 0.15
		"yaw90":
			if absf(yaw) > 0.2: evidence["yaw_input_s"] = float(evidence.get("yaw_input_s", 0.0))+delta
			valid = absf(wrapf(heading-float(baseline.heading), -PI, PI)) >= deg_to_rad(80.0) and float(evidence.get("yaw_input_s", 0.0)) >= 0.35
		"forward":
			if ry > 0.25: evidence["move_input_s"] = float(evidence.get("move_input_s", 0.0))+delta
			valid = (position_m-baseline.position).dot(baseline.forward) >= 4.0 and float(evidence.get("move_input_s", 0.0)) >= 0.35
		"strafe":
			if absf(rx) > 0.25: evidence["move_input_s"] = float(evidence.get("move_input_s", 0.0))+delta
			valid = absf((position_m-baseline.position).dot(baseline.right)) >= 3.0 and float(evidence.get("move_input_s", 0.0)) >= 0.35
		"brake":
			if speed > 2.0: evidence["was_moving"] = true
			valid = brake and speed < 0.65 and bool(evidence.get("was_moving", false))
		"land": valid = bool(telemetry.get("grounded", false)) and absf(velocity.y) < 0.3 and speed < 0.45 and bool(evidence.get("airborne", false))
		"zoom": valid = bool(evidence.get("zoom_requested", false)) and is_instance_valid(session.camera) and absf(session.camera.size-float(baseline.camera_size)) > 0.3
		"cargo_pickup": valid = int(_cargo_count(pilot)) > int(baseline.cargo_count) or pending_events.has("cargo_pickup")
		"swing": valid = (_cargo_count(pilot) > 0 and float(telemetry.get("swing_deg", 180.0)) <= 15.0 and speed < 1.2) or bool(pending_events.get("delivery",{}).get("stable_delivery",false))
		"delivery", "scan", "route", "cover": valid = pending_events.has(step)
	var required = float(COURSES[course][index][4])
	hold = hold + delta if valid else 0.0
	if valid and hold >= required:
		_advance()
	else:
		_publish_clock += delta
		if _publish_clock >= 0.15:
			_publish_clock = 0.0
			_publish()

func _capture_baseline(position_m: Vector3, heading: float, pilot: Node3D) -> void:
	var forward = Vector3(-sin(heading), 0.0, -cos(heading))
	var right = Vector3(cos(heading), 0.0, -sin(heading))
	baseline = {"position":position_m, "heading":heading, "forward":forward, "right":right, "cargo_count":_cargo_count(pilot), "camera_size":session.camera.size if is_instance_valid(session.camera) else 32.0}

func _cargo_count(pilot: Node3D) -> int:
	var cargo: Variant = pilot.get("cargo_items")
	return cargo.size() if cargo is Dictionary or cargo is Array else 0

func _enter_step() -> void:
	hold = 0.0
	baseline.clear()
	# Landing can start on the ground after another skill; require a new airborne sample.
	evidence.clear()
	# Real task evidence may occur one step before the instruction. Keep it until
	# consumed, so releasing delivered cargo cannot make the lesson impossible.
	var voice = course.to_lower()+"_"+_step_id()
	subtitle = str(COURSES[course][index][2])
	if is_instance_valid(session.audio):
		if session.audio.has_method("voice_text"):
			var spoken = str(session.audio.voice_text(voice))
			if not spoken.is_empty(): subtitle = spoken
		if session.audio.has_method("play_voice"): session.audio.play_voice(voice, true)
	_save()
	_publish()

func _advance() -> void:
	pending_events.erase(_step_id())
	index += 1
	if index < COURSES[course].size():
		_enter_step()
		return
	active = false
	status = "completed"
	_save()
	subtitle = "这一组操作已完成。可以继续出航，也可以随时重播引导。" if skipped_steps.is_empty() else "本组引导结束；%d 项效果因设置关闭而略过，可开启后重播。" % skipped_steps.size()
	if skipped_steps.is_empty() and is_instance_valid(session.audio) and session.audio.has_method("play_voice"): session.audio.play_voice("tutorial_complete", true)
	_publish()

func _step_id() -> String:
	return str(COURSES[course][index][0]) if index >= 0 and index < COURSES[course].size() else ""

func get_state() -> Dictionary:
	var step: Array = COURSES[course][index] if index < COURSES[course].size() else ["", "本组学习完成", "随时可以在教学菜单重播。", "", 0.0]
	var instruction = str(step[2])
	return {"active":active, "course":course, "index":index, "count":COURSES[course].size(), "step":str(step[0]), "step_id":str(step[0]), "title":str(step[1]), "instruction":instruction, "text":instruction, "subtitle":subtitle, "bindings":_binding_hint(str(step[0])), "highlight":str(step[3]), "hold":hold, "hold_required":float(step[4]), "status":status, "step_status":status, "skipped_steps":skipped_steps.duplicate(), "replaying":replaying, "journal":journal.duplicate(true), "save_pending":_dirty}

func _binding_hint(step: String) -> String:
	if not is_instance_valid(session) or not is_instance_valid(session.input): return ""
	var names = {"lift":["high","low"],"land":["high","low"],"yaw90":["yaw_left","yaw_right"],"forward":["forward","back"],"strafe":["left","right"],"brake":["brake"],"cargo_pickup":["interact"],"delivery":["interact"],"scan":["interact"],"swing":["brake"]}
	if step == "zoom": return "滚轮 / 右上角 + −"
	if session.input.source == "phone" or session.input.legacy.device >= 0: return "左杆：升降 / 偏航　右杆：前后 / 横移"
	var keys: Array[String] = []
	for action in names.get(step,[]): keys.append(session.input.legacy.binding_label(action))
	return "当前按键  "+" / ".join(keys) if not keys.is_empty() else "小幅修正，观察地速与高度"

func _save() -> void:
	var previous: Dictionary = journal.courses.get(course, {})
	journal.courses[course] = {"index":index, "status":"in_progress" if active else status, "completed":status == "completed" or bool(previous.get("completed", false)), "evidence_complete":status == "completed" and skipped_steps.is_empty(), "skipped_steps":skipped_steps.duplicate(),"task_evidence":pending_events.duplicate(true)}
	_persist()

func _persist() -> void:
	if not is_instance_valid(session): return
	var result: Dictionary = session.repository.commit({"id":"tutorial-v22:"+str(Time.get_ticks_usec()), "set":{"settings.tutorial_v22":journal.duplicate(true)}})
	_dirty = not bool(result.get("ok", false))
	if _dirty and session.has_method("notify"): session.notify("教学进度暂未保存，可继续练习；请在安全退出前重试保存。")

func retry_save() -> void:
	_save()
	_publish()

func _stop_voice() -> void:
	if is_instance_valid(session) and is_instance_valid(session.audio) and session.audio.has_method("stop_voice"): session.audio.stop_voice()

func _voice_started(id: String, text: String) -> void:
	if active and id == course.to_lower()+"_"+_step_id():
		subtitle = text
		_publish()

func _publish() -> void:
	state_changed.emit(get_state())
