class_name HangarUI
extends CanvasLayer

const INK = Color("#173645")
const PAPER = Color("#eee9dc")
const TEAL = Color("#397f86")
const GOLD = Color("#d79b49")
const MUTED = Color("#8da2aa")
var world
var root: Control
var theme_file: Theme
var toast_label: Label
var toast_left = 0.0
var hp: ProgressBar
var heat: ProgressBar
var status_label: Label
var target_label: Label
var health_label: Label
var height_label: Label
var boss_bar: ProgressBar
var boss_label: Label
var timer_label: Label
var interaction_label: Label
var selected = 0
var preview_model: Node3D
var calibration_label: Label
var axis_label: Label
var binding_action = ""
var current_screen = ""
var hud_marker: Control
var utility_label: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 5
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	theme_file = Theme.new()
	if ResourceLoader.exists("res://assets/fonts/NotoSansSC-Medium.ttf"):
		theme_file.default_font=load("res://assets/fonts/NotoSansSC-Medium.ttf")
	theme_file.default_font_size = 19
	for state in ["normal","hover","pressed","focus","disabled"]:
		var style = StyleBoxFlat.new()
		style.bg_color = INK if state=="normal" else (TEAL if state in ["hover","pressed"] else Color("#718289"))
		if state=="focus":
			style.bg_color = Color(0,0,0,0)
			style.border_color = GOLD
			style.set_border_width_all(3)
		style.set_corner_radius_all(5)
		style.content_margin_left = 17
		style.content_margin_right = 17
		style.content_margin_top = 10
		style.content_margin_bottom = 10
		theme_file.set_stylebox(state,"Button",style)
	theme_file.set_color("font_color","Button",PAPER)
	theme_file.set_color("font_hover_color","Button",Color.WHITE)
	theme_file.set_color("font_disabled_color","Button",Color("#b6c0c2"))
	theme_file.set_color("font_color","Label",INK)
	root.theme = theme_file
	world.router.calibration_done.connect(func():
		world.profile.data.settings.input = world.router.config.duplicate(true)
		world.profile.save_profile()
	)

func clear() -> void:
	for child in root.get_children():
		root.remove_child(child)
		child.queue_free()
	preview_model = null
	toast_label = null
	calibration_label = null
	axis_label = null
	binding_action = ""

func rect(parent: Control, pos: Vector2, size: Vector2, color: Color) -> ColorRect:
	var item = ColorRect.new()
	item.color = color
	item.position = pos
	item.size = size
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(item)
	return item

func panel(parent: Control, pos: Vector2, size: Vector2, color: Color=PAPER) -> Panel:
	var item = Panel.new()
	item.position = pos
	item.size = size
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(8)
	style.border_color=Color("#809b96") if color==INK else Color("#c8cebf")
	style.set_border_width_all(1)
	item.add_theme_stylebox_override("panel",style)
	parent.add_child(item)
	item.size=size
	return item

func label(parent: Control, text: String, pos: Vector2, size: Vector2, font_size: int=20, color: Color=INK) -> Label:
	var item = Label.new()
	item.text = text
	item.position = pos
	item.size = size
	item.add_theme_font_size_override("font_size",font_size)
	item.add_theme_color_override("font_color",color)
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(item)
	item.size=size
	return item

func button(parent: Control, text: String, pos: Vector2, size: Vector2, callback: Callable, disabled: bool=false) -> Button:
	var item = Button.new()
	item.text = text
	item.position = pos
	item.size = size
	item.disabled = disabled
	item.pressed.connect(func():
		world.sound("ui")
		callback.call()
	)
	parent.add_child(item)
	if size.y<45:
		for state in ["normal","hover","pressed","disabled"]:
			var small=theme_file.get_stylebox(state,"Button").duplicate()
			small.content_margin_top=1;small.content_margin_bottom=1
			item.add_theme_stylebox_override(state,small)
	item.size=size
	return item

func bar(parent: Control, pos: Vector2, size: Vector2, color: Color) -> ProgressBar:
	var item = ProgressBar.new()
	item.position = pos
	item.size = size
	item.show_percentage = false
	item.add_theme_font_size_override("font_size",1)
	var fill = StyleBoxFlat.new();fill.bg_color=color;fill.set_corner_radius_all(3)
	var bg = StyleBoxFlat.new();bg.bg_color=Color("#ced4cc");bg.set_corner_radius_all(3)
	item.add_theme_stylebox_override("fill",fill)
	item.add_theme_stylebox_override("background",bg)
	parent.add_child(item)
	item.size=size
	return item

func show_hangar() -> void:
	clear()
	current_screen="hangar"
	selected=clampi(selected,0,GameData.MISSIONS.size()-1)
	var screen=preload("res://scripts/hangar_screen.gd").new()
	screen.ui=self
	root.add_child(screen)
	_make_toast()
func _preview(pos: Vector2, size: Vector2) -> void:
	var container = SubViewportContainer.new()
	container.position=pos;container.size=size;container.stretch=true
	container.mouse_filter=Control.MOUSE_FILTER_IGNORE
	root.add_child(container)
	var viewport = SubViewport.new()
	viewport.size=Vector2i(size)
	viewport.transparent_bg=true
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d=Viewport.MSAA_2X
	container.add_child(viewport)
	var stage = Node3D.new();viewport.add_child(stage)
	var env=WorldEnvironment.new();var settings=Environment.new()
	settings.background_mode=Environment.BG_COLOR
	settings.background_color=Color(0.9,0.88,0.83,0)
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color=Color("#d5dfdd");settings.ambient_light_energy=.38
	settings.tonemap_mode=Environment.TONE_MAPPER_ACES
	settings.ssao_enabled=true
	env.environment=settings;stage.add_child(env)
	var key=DirectionalLight3D.new();key.rotation_degrees=Vector3(-45,-20,0);key.light_energy=1.0;key.shadow_enabled=true;stage.add_child(key)
	var cam=Camera3D.new();cam.projection=Camera3D.PROJECTION_ORTHOGONAL;cam.size=2.7;stage.add_child(cam)
	cam.position=Vector3(3.5,2.7,4);cam.look_at(Vector3(0,0,0),Vector3.UP)
	preview_model=GameVisuals.asset(stage,"player")
	GameVisuals.asset(preview_model,"module_"+world.profile.data.loadout.weapon,Vector3(0,-.28,-.12))
	GameVisuals.asset(preview_model,"module_"+world.profile.data.loadout.utility,Vector3(0,.25,.2))
	GameVisuals.asset(preview_model,"module_"+world.profile.data.loadout.drive)
	GameVisuals.cylinder(stage,Vector3(0,-.62,0),1.65,.08,Color("#d0d2c5"))

func show_hud() -> void:
	clear();current_screen="hud"
	var instruments=preload("res://scripts/flight_instruments.gd").new()
	instruments.world=world;root.add_child(instruments)
	var card=panel(root,Vector2(30,26),Vector2(358,128),INK)
	label(card,"TR–01  /  飞行遥测",Vector2(17,9),Vector2(320,30),18,PAPER)
	hp=bar(card,Vector2(18,48),Vector2(231,12),TEAL)
	heat=bar(card,Vector2(18,83),Vector2(231,9),GOLD)
	health_label=label(card,"",Vector2(262,37),Vector2(88,29),18,PAPER)
	height_label=label(card,"",Vector2(17,101),Vector2(325,24),14,Color("#a9d8cf"))
	label(card,"热量",Vector2(260,75),Vector2(90,27),15,PAPER)
	var mission=panel(root,Vector2(1050,26),Vector2(522,133),INK)
	label(mission,"自由练飞 / 无敌人 · 无受伤" if world.practice_mode else GameData.MISSIONS[world.selected_mission].name,Vector2(20,9),Vector2(480,35),22,PAPER)
	status_label=label(mission,"",Vector2(20,52),Vector2(480,76),17,Color("#b9d1ce"))
	timer_label=label(root,"",Vector2(430,29),Vector2(220,35),19,PAPER)
	target_label=label(root,"",Vector2(580,92),Vector2(450,36),20,PAPER)
	target_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var controls=panel(root,Vector2(316,812),Vector2(1255,48),INK)
	label(controls,"WASD 飞行   %s 制动   %s/%s 航层   %s 开火   %s 交互   %s 功能   Tab 目标   M 全图   Esc 暂停"%[world.router.binding_label("brake"),world.router.binding_label("low"),world.router.binding_label("high"),world.router.binding_label("fire"),world.router.binding_label("interact"),world.router.binding_label("utility")],Vector2(18,7),Vector2(1200,34),15,PAPER)
	var detail=panel(root,Vector2(1280,662),Vector2(290,132),INK)
	label(detail,GameData.DIFFICULTY[world.difficulty].name+"空域  /  "+world.map_spec.name,Vector2(16,9),Vector2(260,27),15,Color("#a9d8cf"))
	hud_marker=detail
	utility_label=label(detail,"",Vector2(16,41),Vector2(260,80),16,PAPER)
	interaction_label=label(root,"",Vector2(505,741),Vector2(610,45),20,PAPER)
	interaction_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	boss_label=label(root,"",Vector2(525,170),Vector2(550,36),20,PAPER)
	boss_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	boss_bar=bar(root,Vector2(568,207),Vector2(464,10),GOLD)
	_make_toast()
	update_hud()

func update_hud() -> void:
	if current_screen!="hud" or not is_instance_valid(world.player):return
	var p=world.player
	var utility="护盾  %0.1fs"%p.shield_cooldown if p.shield_cooldown>0 else "护盾就绪  [%s]"%world.router.binding_label("utility")
	if p.loadout.utility=="cooler":utility="散热模块  /  被动运行"
	utility_label.text=utility+"\n航线 %d/4    额外零件 +%d\n已击退 %d 架"%[world.gates_passed,world.bonus_parts,world.enemies_defeated]
	if world.practice_mode:utility_label.text="练飞模式 · 不结算奖励\n航线 %d / 4\nEsc 返回 / R 重练"%world.gates_passed
	hp.value=p.health/p.maximum_health*100
	heat.value=p.heat
	health_label.text="%d / %d"%[ceil(p.health),p.maximum_health]
	height_label.text=("高航层" if world.router.layer else "低航层")+"   ·   %0.1f m   ·   %0.1f m/s"%[p.position.y,Vector2(p.velocity.x,p.velocity.z).length()]
	status_label.text=world.mission_status()
	timer_label.text="%02d : %02d"%[int(world.mission_time)/60,int(world.mission_time)%60]
	target_label.text=""
	if is_instance_valid(p.target):target_label.text="锁定  "+p.target.name_label
	if p.overheated:target_label.text="武器过热 · 停火散热"
	interaction_label.text=""
	for objective in world.objectives:
		if not objective.done and Vector2(p.position.x-objective.position.x,p.position.z-objective.position.z).length()<2.6:
			if p.position.y>2.2:interaction_label.text="%s 降至低航层，再靠近交互"%world.router.binding_label("low")
			elif p.velocity.length()>2.6:interaction_label.text="%s 制动，停稳后按住 %s"%[world.router.binding_label("brake"),world.router.binding_label("interact")]
			else:interaction_label.text="按住 %s  ·  %s  %d%%"%[world.router.binding_label("interact"),objective.title,int(objective.progress*100)]
	var boss=world.get_boss()
	boss_bar.visible=is_instance_valid(boss)
	boss_label.visible=is_instance_valid(boss)
	if is_instance_valid(boss):
		boss_bar.value=boss.health/boss.maximum_health*100
		boss_label.text="蜂巢管家  /  "+["","扫描协议","护盾协议","核心暴露"][boss.phase]

func _modal(title: String, subtitle: String="") -> Panel:
	clear()
	rect(root,Vector2.ZERO,Vector2(1600,900),Color(0.035,0.09,0.12,0.79))
	var p=panel(root,Vector2(440,130),Vector2(720,640),PAPER)
	label(p,title,Vector2(42,28),Vector2(640,63),37)
	label(p,subtitle,Vector2(44,100),Vector2(634,80),18,TEAL)
	return p

func show_pause(reason: String) -> void:
	var p=_modal("飞行暂停",reason if not reason.is_empty() else "稳住节奏，准备好了再出发。")
	current_screen="pause"
	var resume=button(p,"继续飞行",Vector2(45,202),Vector2(630,55),world.resume_game)
	button(p,"重新练飞" if world.practice_mode else "重新挑战",Vector2(45,280),Vector2(630,55),world.restart_mission)
	button(p,"飞行设置 / 控制器",Vector2(45,358),Vector2(630,55),show_settings)
	button(p,"返回机库",Vector2(45,436),Vector2(630,55),world.show_hangar)
	label(p,"本次未完成行动不结算奖励；已有蓝图与零件保留。",Vector2(45,531),Vector2(630,45),16)
	resume.grab_focus()

func show_results(success: bool) -> void:
	var p=_modal("练飞完成" if world.practice_mode else ("行动完成" if success else "返回修整"),"已完成回收与返航练习。可继续练飞，或回机库开始正式行动。" if world.practice_mode else GameData.MISSIONS[world.selected_mission].name+("\n天空又恢复了平静。准备下一次出击。" if success else "\n读懂预警，提前制动。失败不会损失永久进度。"))
	current_screen="results"
	var player=world.player
	label(p,"飞行时间     %02d:%02d\n受到损伤     %d\n碰撞次数     %d\n回收零件     +%d"%[int(world.mission_time)/60,int(world.mission_time)%60,player.damage_taken,player.collision_count,maxi(0,world.last_reward)],Vector2(46,213),Vector2(630,195),25)
	if world.last_reward<0:label(p,"保存失败：进度未结算，请检查磁盘权限。",Vector2(45,423),Vector2(630,36),17,Color("#b45439"))
	elif not world.practice_mode:
		var best=world.profile.best_time(world.selected_mission,world.difficulty,world.used_auto_fire)
		if best>=0:label(p,"同难度 / 配装 / 辅助状态的个人最佳  %02d:%02d"%[int(best)/60,int(best)%60],Vector2(45,423),Vector2(630,36),17,TEAL)
	var back=button(p,"返回机库 · 配装与解锁",Vector2(45,478),Vector2(630,54),func():selected=mini(2,world.selected_mission+1) if success and not world.practice_mode else world.selected_mission;world.show_hangar())
	button(p,"再试一次",Vector2(45,549),Vector2(630,47),world.restart_mission)
	back.grab_focus()

func show_help() -> void:
	var p=_modal("飞行手册","先飞稳，再飞快。")
	current_screen="help"
	label(p,"1   WASD / 方向键移动，松杆自动减速。\n2   按空格加强制动，让无人机稳稳停下。\n3   Q 低航层，E 高航层；地面圆环显示位置。\n4   低处靠近补给或节点，停稳并按住 F。\n5   J / 鼠标左键开火，Tab 切换辅助锁定目标。\n6   敌人先预警再攻击；先躲开，再还击。\n7   Shift 开启护盾。散热模块则提供被动效果。\n8   回机库换装。配置会改变外观与飞行节奏。",Vector2(46,187),Vector2(640,350),21)
	button(p,"明白，返回机库",Vector2(46,553),Vector2(630,52),world.show_hangar).grab_focus()

func show_settings() -> void:
	clear();current_screen="settings"
	rect(root,Vector2.ZERO,Vector2(1600,900),INK)
	var left=panel(root,Vector2(35,35),Vector2(715,826),PAPER)
	var right=panel(root,Vector2(778,35),Vector2(787,826),PAPER)
	label(left,"飞行设置",Vector2(30,19),Vector2(650,61),32)
	label(left,"画面稳定，操作清楚。设置不会改变镜头朝向。",Vector2(32,85),Vector2(640,39),17,TEAL)
	var diff=OptionButton.new();diff.position=Vector2(35,149);diff.size=Vector2(645,48)
	for item in GameData.DIFFICULTY:diff.add_item(item.name)
	diff.selected=int(world.profile.data.settings.difficulty)
	diff.item_selected.connect(func(i):world.profile.data.settings.difficulty=i;world.profile.save_profile())
	left.add_child(diff)
	var auto=CheckButton.new();auto.position=Vector2(31,220);auto.size=Vector2(650,45);auto.text="辅助自动开火（所有输入设备均可使用）"
	auto.button_pressed=world.profile.data.settings.auto_fire
	auto.toggled.connect(func(v):world.profile.data.settings.auto_fire=v;if_player_auto(v);world.profile.save_profile())
	left.add_child(auto)
	var cam=CheckButton.new();cam.position=Vector2(31,288);cam.size=Vector2(650,45);cam.text="更高俯角（静态镜头预设）";cam.button_pressed=world.profile.data.settings.camera==1
	cam.toggled.connect(func(v):world.profile.data.settings.camera=1 if v else 0;world._set_camera();world.profile.save_profile())
	left.add_child(cam)
	var fullscreen=CheckButton.new();fullscreen.position=Vector2(31,354);fullscreen.size=Vector2(650,45);fullscreen.text="全屏显示"
	fullscreen.button_pressed=DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN
	fullscreen.toggled.connect(func(v):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if v else DisplayServer.WINDOW_MODE_WINDOWED)
		world.profile.data.settings.fullscreen=v;world.profile.save_profile()
	)
	left.add_child(fullscreen)
	label(left,"音量",Vector2(33,425),Vector2(620,36),21)
	var slider=HSlider.new();slider.position=Vector2(35,482);slider.size=Vector2(640,30);slider.min_value=0;slider.max_value=1;slider.step=.05;slider.value=world.profile.data.settings.volume
	slider.value_changed.connect(func(v):world.set_volume(v);world.profile.save_profile());left.add_child(slider)
	label(left,"键盘重映射：点击动作后按一个键或手柄按钮",Vector2(33,544),Vector2(650,35),17)
	var binds=[["fire","开火"],["brake","制动"],["interact","交互"],["utility","功能"],["high","升高"],["low","降低"]]
	for i in range(binds.size()):
		var item=binds[i]
		button(left,item[1]+" · "+world.router.binding_label(item[0]),Vector2(34+(i%3)*217,595+(i/3)*52),Vector2(207,43),func():binding_action=item[0];toast("请按下用于「"+item[1]+"」的键/按钮；Esc 取消"))
	button(left,"返回",Vector2(35,744),Vector2(645,51),_return_from_settings).grab_focus()
	label(right,"控制器与遥控器",Vector2(31,20),Vector2(720,61),32)
	var devices=Input.get_connected_joypads()
	var selector=OptionButton.new();selector.position=Vector2(34,106);selector.size=Vector2(718,45)
	if devices.is_empty():selector.add_item("未检测到设备 · 键盘可完整游玩")
	for id in devices:
		selector.add_item(Input.get_joy_name(id),id)
		if id==world.router.device:selector.selected=selector.item_count-1
	selector.item_selected.connect(func(i):world.router.device=selector.get_item_id(i))
	right.add_child(selector)
	label(right,"逐轴观察 → 选择映射 → 中立/行程校准",Vector2(34,172),Vector2(718,34),19,TEAL)
	var mapping=[["axis_x","左右轴"],["axis_y","前后轴"],["axis_height","航层轴（非回中油门可用）"]]
	for i in range(3):
		var item=mapping[i]
		label(right,item[1],Vector2(35,230+i*57),Vector2(443,40),18)
		var option=OptionButton.new();option.position=Vector2(500,230+i*57);option.size=Vector2(249,40)
		option.add_item("不使用",-1)
		for j in range(8):option.add_item("轴 "+str(j),j)
		option.selected=int(world.router.config[item[0]])+1
		option.item_selected.connect(func(n):world.router.config[item[0]]=option.get_item_id(n))
		right.add_child(option)
	for i in range(2):
		var inverse=CheckButton.new();inverse.position=Vector2(34+i*355,410);inverse.size=Vector2(338,40)
		inverse.text="反转左右轴" if i==0 else "反转前后轴"
		var key="invert_x" if i==0 else "invert_y";inverse.button_pressed=world.router.config[key]
		inverse.toggled.connect(func(v):world.router.config[key]=v)
		right.add_child(inverse)
	label(right,"死区",Vector2(35,470),Vector2(120,40),18)
	var dead=HSlider.new();dead.position=Vector2(150,481);dead.size=Vector2(590,25);dead.min_value=.05;dead.max_value=.4;dead.step=.01;dead.value=world.router.config.deadzone
	dead.value_changed.connect(func(v):world.router.config.deadzone=v);right.add_child(dead)
	button(right,"开始校准（先居中，再推动至两端）",Vector2(34,531),Vector2(718,47),func():world.router.begin_calibration(),devices.is_empty())
	calibration_label=label(right,"只读取游戏输入，不改变遥控器固件或射频设置。",Vector2(36,595),Vector2(716,58),17,TEAL)
	axis_label=label(right,"",Vector2(36,667),Vector2(716,73),16)
	label(right,"设备未实测时，不表示型号已兼容。断连自动暂停。",Vector2(36,763),Vector2(716,33),16)
	_make_toast()

func if_player_auto(value: bool) -> void:
	if is_instance_valid(world.player):world.player.auto_fire=value

func _return_from_settings() -> void:
	world.profile.data.settings.input=world.router.config.duplicate(true)
	world.profile.save_profile()
	if world.in_flight:
		show_pause("")
	else:
		world.show_hangar()

func _unhandled_input(event: InputEvent) -> void:
	if binding_action.is_empty():return
	if event is InputEventKey and event.pressed:
		if event.physical_keycode==KEY_ESCAPE:binding_action=""
		else:
			world.router.rebind(binding_action,{"type":"key","code":event.physical_keycode})
			binding_action=""
			toast("映射已设置")
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed:
		world.router.rebind(binding_action,{"type":"joy","code":event.button_index})
		binding_action=""
		get_viewport().set_input_as_handled()

func _make_toast() -> void:
	toast_label=label(root,"",Vector2(360,860),Vector2(880,32),16,Color("#e6b66e"))
	toast_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER

func toast(message: String) -> void:
	if not is_instance_valid(toast_label):_make_toast()
	toast_label.text=message
	toast_left=6.0

func _process(delta: float) -> void:
	if is_instance_valid(preview_model):GameVisuals.rotors(preview_model,delta*.20)
	if is_instance_valid(toast_label):
		toast_left-=delta
		toast_label.visible=toast_left>0
	if current_screen=="settings":
		if is_instance_valid(calibration_label) and not world.router.calibration_phase.is_empty():
			calibration_label.text=world.router.calibration_phase
		if is_instance_valid(axis_label):
			var text=""
			if world.router.device>=0:
				for i in range(8):
					text+="轴%d  %+.2f   "%[i,Input.get_joy_axis(world.router.device,i)]
					if i==3:text+="\n"
			axis_label.text=text


