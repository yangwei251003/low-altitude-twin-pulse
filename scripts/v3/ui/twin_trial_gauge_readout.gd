class_name TwinTrialGaugeReadout
extends PanelContainer
## Read-only presentation of SUCCESSFUL host observe_gauge results.
## Caller owns authority, physical checks and region/branch lifecycle. This UI
## never queries the Station, verifies an actor, polls water or emits a fact.
## Call clear_readings() on region/branch/session change; otherwise rows are
## explicitly previous readings, not a live telemetry or persistence system.
const FONT = preload("res://assets/fonts/NotoSansSC-Medium.ttf")
const RECEIVERS := ["I2:trial_receiver_a","I2:trial_receiver_b"]
const PANEL_SIZE := Vector2(236,142)
const GAP := 8.0
var help_bar: Control
var panel_obstacles: Array[Control] = []
var pilot_marker: Node2D
var layout_blocked := false
var headings: Dictionary = {}
var values: Dictionary = {}
var _readings: Dictionary = {}
var _current := ""
var _wanted_visible := false
var _built := false

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	_ensure_widgets()
	_refresh_rows()
	_update_layout()

func setup_layout(bottom_help: Control, obstacles: Array = [], pilot: Node2D = null) -> void:
	help_bar=bottom_help
	pilot_marker=pilot
	panel_obstacles.clear()
	for control in obstacles:
		if control is Control and is_instance_valid(control) and control!=self and control not in panel_obstacles:
			panel_obstacles.append(control)
	_update_layout()

func apply_observation(observation: Dictionary) -> bool:
	# These are formatting guards, NOT an authorization boundary. Only the
	# caller's successful authority-side observation may reach this method.
	if observation.get("ok")!=true or observation.get("code","")!="local_gauge_observed": return false
	var id: String = str(observation.get("receiver_id",""))
	if id not in RECEIVERS: return false
	if not _number(observation.get("volume_ml"),0,200000) or floor(float(observation.volume_ml))!=float(observation.volume_ml): return false
	if not _number(observation.get("level_m"),.25,1.25): return false
	if not _number(observation.get("mechanism_serial"),0,9007199254740000) or floor(float(observation.mechanism_serial))!=float(observation.mechanism_serial): return false
	var record := {"volume_ml":int(observation.volume_ml),"level_m":float(observation.level_m),"mechanism_serial":int(observation.mechanism_serial)}
	if _readings.has(id):
		var previous: Dictionary = _readings[id]
		if int(record.mechanism_serial)<int(previous.mechanism_serial): return false
		if int(record.mechanism_serial)==int(previous.mechanism_serial) and record!=previous: return false
	_readings[id]=record
	_current=id
	_wanted_visible=true
	_ensure_widgets()
	_refresh_rows()
	_update_layout()
	return true

func mark_previous() -> void:
	# After leaving a readable window or a failed new read, retain prior values
	# with an explicit old-reading label; do not manufacture a zero result.
	_current=""
	_refresh_rows()

func clear_readings() -> void:
	_readings.clear()
	_current=""
	_wanted_visible=false
	layout_blocked=false
	_refresh_rows()
	hide()

func readings_snapshot() -> Dictionary:
	return {"current_receiver":_current,"readings":_readings.duplicate(true),"live_telemetry":false}

func _process(_delta: float) -> void:
	_update_layout()

func _ensure_widgets() -> void:
	if _built: return
	_built=true
	name="TrialGaugeReadout"
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	custom_minimum_size=PANEL_SIZE
	size=PANEL_SIZE
	clip_contents=true
	add_theme_font_override("font",FONT)
	var style := StyleBoxFlat.new()
	style.bg_color=Color(0.035,0.085,0.095,0.96)
	style.border_color=Color("567f7b")
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	style.content_margin_left=10
	style.content_margin_right=10
	style.content_margin_top=7
	style.content_margin_bottom=7
	add_theme_stylebox_override("panel",style)
	# A fixed content rect avoids VBox minimum-size propagation silently growing
	# the panel past 150 px when the actual CJK font metrics are imported.
	var column := Control.new()
	column.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(column)
	var title := _label("试流台 · 窗口读数",14,Color("b7dcd3"))
	column.add_child(title)
	title.position=Vector2.ZERO
	title.size=Vector2(216,22)
	for index in range(2):
		var id: String = RECEIVERS[index]
		var heading := _label("",13,Color("f0d39a") if index==0 else Color("b0e5de"))
		var value := _label("",14,Color("e0e7df"))
		column.add_child(heading)
		column.add_child(value)
		heading.position=Vector2(0,22+index*43)
		heading.size=Vector2(216,20)
		value.position=Vector2(0,42+index*43)
		value.size=Vector2(216,22)
		headings[id]=heading
		values[id]=value
	var note := _label("液位相对空箱；读数不会自动刷新",11,Color("9cafad"))
	column.add_child(note)
	note.position=Vector2(0,110)
	note.size=Vector2(216,18)

static func _label(text: String, point_size: int, tint: Color) -> Label:
	var label := Label.new()
	label.text=text
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	label.clip_text=true
	label.autowrap_mode=TextServer.AUTOWRAP_OFF
	label.add_theme_font_override("font",FONT)
	label.add_theme_font_size_override("font_size",point_size)
	label.add_theme_color_override("font_color",tint)
	return label

func _refresh_rows() -> void:
	if not _built: return
	for index in range(2):
		var id: String = RECEIVERS[index]
		var letter: String = "A" if index==0 else "B"
		var heading: Label = headings[id]
		var value: Label = values[id]
		if not _readings.has(id):
			heading.text="接收箱 "+letter+" · 未读取"
			value.text="靠近并读取这一侧窗口"
			value.modulate=Color("9cafad")
			continue
		var record: Dictionary = _readings[id]
		heading.text="接收箱 "+letter+(" · 本次读取" if _current==id else " · 上次读取")
		var litres: float = float(record.volume_ml)/1000.0
		var height_cm: float = (float(record.level_m)-.25)*100.0
		value.text="%.1f / 200 L · 液位 +%.1f cm" % [litres,height_cm]
		value.modulate=Color.WHITE if _current==id else Color("bdcbc6")

func _update_layout() -> void:
	if not is_inside_tree() or not _built: return
	if not _wanted_visible:
		hide()
		return
	var viewport_rect := get_viewport_rect()
	var safe := Rect2(viewport_rect.position+Vector2(20,16),viewport_rect.size-Vector2(40,32))
	if safe.size.x<PANEL_SIZE.x or safe.size.y<PANEL_SIZE.y:
		layout_blocked=true
		hide()
		return
	# Fixed-width text and non-wrapping clipped labels prevent any long data
	# value growing the container beyond the explicitly bounded 720p footprint.
	size=PANEL_SIZE
	var blocked: Array[Rect2] = []
	var lowest_bottom: float = safe.end.y
	if is_instance_valid(help_bar) and help_bar.is_visible_in_tree():
		var help := help_bar.get_global_rect()
		lowest_bottom=minf(lowest_bottom,help.position.y-GAP)
		blocked.append(help)
	for panel in panel_obstacles:
		if is_instance_valid(panel) and panel.is_visible_in_tree(): blocked.append(panel.get_global_rect())
	if is_instance_valid(pilot_marker) and pilot_marker.is_visible_in_tree():
		# Marker position is the actual projected local pilot, not a fabricated
		# world edge point. Leave space for the visible hull/corner brackets.
		blocked.append(Rect2(pilot_marker.global_position-Vector2(52,46),Vector2(104,92)))
	var x: float = safe.end.x-PANEL_SIZE.x
	var candidates: Array[float] = [lowest_bottom-PANEL_SIZE.y,safe.position.y]
	for obstacle in blocked:
		candidates.append(obstacle.position.y-GAP-PANEL_SIZE.y)
		candidates.append(obstacle.end.y+GAP)
	candidates.sort()
	candidates.reverse()
	for y in candidates:
		var rectangle := Rect2(Vector2(x,y),PANEL_SIZE)
		if not safe.encloses(rectangle) or rectangle.end.y>lowest_bottom: continue
		var clear := true
		for obstacle in blocked:
			if rectangle.intersects(obstacle.grow(2.0)):
				clear=false
				break
		if not clear: continue
		global_position=rectangle.position
		layout_blocked=false
		show()
		return
	# Rare crowded viewport: preserve readings but show none over the pilot or
	# other panels. Processing remains enabled so a later free slot recovers it.
	layout_blocked=true
	hide()

static func _number(raw: Variant, low: float, high: float) -> bool:
	return (raw is int or raw is float) and is_finite(float(raw)) and float(raw)>=low and float(raw)<=high
