extends RefCounted
## Flight-deck home and actual offline/LAN departure routes.
## Read-only campaign/loadout presentation; every action goes through dispatch.
const Kit = preload("res://scripts/v3/ui/front/twin_front_kit.gd")
const Backdrop = preload("res://scripts/v3/ui/front/twin_front_backdrop.gd")
const AIRFRAME_STAGE := "res://scripts/v3/ui/front/twin_front_airframe3d.gd"
const Catalog = preload("res://scripts/v2/catalog.gd")
const Hangar = preload("res://scripts/v3/gameplay/twin_hangar.gd")
const Regions = preload("res://scripts/v3/world/twin_region_catalog.gd")
const REGION_ORDER := ["I1","F1","I2","F2","I3","F3","I4","F4"]
const REGION_SHORT := {"I1":"潮湾","F1":"巨木","I2":"水城","F2":"镜湖","I3":"热崖","F3":"菌谷","I4":"离岸","F4":"冠峰"}
const FRAME_ROLES := {"tr01":"护圈稳定 · 综合作业","hx02":"六旋重载 · 运输整备","ag03":"轻型机体 · 灵活穿行","nx04":"传感观察 · 搜索作业","sh05":"共轴护航 · 稳重支援","at06":"双舱机体 · 战斗支援"}

static func build(page: String, ctx: Dictionary, dispatch: Callable) -> Control:
	if page == "modes": return _modes(ctx,dispatch)
	return _home(ctx,dispatch)

static func _home(ctx: Dictionary, dispatch: Callable) -> Control:
	var root := Kit.column(16)
	root.name = "FrontHome"
	var active := bool(ctx.get("active",false))
	var settings: Dictionary = ctx.get("settings",{})
	var profile: Dictionary = ctx.get("profile",{})
	var journey: Dictionary = _journey(ctx)
	var aircraft: Dictionary = _aircraft(ctx)
	var region := str(journey.region)
	var welcome := Kit.row(12)
	root.add_child(welcome)
	var emblem := TextureRect.new()
	emblem.texture = load("res://assets/ui/front/twinpulse_emblem.svg")
	emblem.custom_minimum_size = Vector2(30,30)
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	welcome.add_child(emblem)
	var welcome_text := Kit.column(2)
	welcome.add_child(welcome_text)
	welcome_text.add_child(Kit.label("欢迎回到甲板，"+str(settings.get("profile_name","新航员")),16,Kit.TEXT))
	welcome_text.add_child(Kit.label("旅程已接续 · 准备你的下一次出航" if int(profile.get("generation",0))>0 else "从第一声呼叫开始，连起两界的路。",11,Kit.MUTED))
	var hero := Kit.panel()
	hero.name = "FlightDeckHero"
	hero.clip_contents = true
	var hero_style := Kit.box(Color("071b25"),Color("5a887e"),14,20)
	hero_style.shadow_color = Color(0,.01,.015,.46)
	hero_style.shadow_size = 12
	hero_style.shadow_offset = Vector2(0,7)
	hero.add_theme_stylebox_override("panel",hero_style)
	root.add_child(hero)
	# Native PanelContainer overlays its children in the same content rect.
	# The generated scene stays behind native controls without a second
	# layout pass, a custom min-size override, or an input-catching overlay.
	var scenery := Backdrop.new()
	scenery.name = "FlightDeckArtwork"
	scenery.set_scene_card()
	scenery.set_reduce_motion(bool(settings.get("reduced_motion",false)))
	scenery.set_accent(_accent(settings))
	hero.add_child(scenery)
	var hero_grid := Kit.grid(2)
	hero_grid.add_theme_constant_override("h_separation",22)
	hero.add_child(hero_grid)
	_responsive_columns(hero_grid,2,740.0)
	var message := Kit.column(10)
	message.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hero_grid.add_child(message)
	message.add_child(Kit.label("FLIGHT DECK  /  两界出航台",11,_accent(settings)))
	var headline := "低空起航，\n连接两界。"
	if bool(journey.complete): headline = "两界已相连。\n下一程仍有回声。"
	var title := Kit.label(headline,40,Kit.TEXT)
	title.add_theme_color_override("font_shadow_color",Color(0,.03,.04,.85))
	title.add_theme_constant_override("shadow_offset_y",3)
	title.add_theme_constant_override("shadow_outline_size",4)
	message.add_child(title)
	var description := "从港口的一声救援呼叫起飞。穿过海风与树影，接回另一端的回应。"
	if int(journey.completed)>0:
		description = ""+str(journey.region_name)+"的记录仍在。带上已保存的配装，沿着同伴的呼叫继续你的旅程。"
	if active: description = "你的小队仍在"+str(journey.region_name)+"。继续当前航行，或回到大厅整理下一程。"
	message.add_child(Kit.label(description,14,Color("c1d2cf")))
	var location := Kit.row(8)
	location.add_child(_pill("当前航区" if active else "存档停靠",Kit.ACCENT))
	location.add_child(Kit.label(str(journey.region_name),13,Kit.TEXT))
	if active:
		message.add_child(Kit.button("继续当前航行   →",func(): dispatch.call("legacy",{"action":"resume","payload":{}}),true))
	var departure := Kit.button("选择出航模式   →" if active else "开始出航   →",func(): dispatch.call("navigate",{"page":"modes"}),not active)
	departure.name = "MainDepartureButton"
	departure.custom_minimum_size.y = 56
	departure.add_theme_font_size_override("font_size",19)
	message.add_child(departure)
	var prep := Kit.row(10)
	message.add_child(prep)
	prep.add_child(Kit.button("基地整备",func(): dispatch.call("navigate",{"page":"base"})))
	prep.add_child(Kit.button("查看任务",func(): dispatch.call("navigate",{"page":"missions"})))
	message.add_child(location)
	message.add_child(Kit.label("单人离线  /  局域网双人",11,Kit.MUTED))
	var flight := Kit.column(8)
	hero_grid.add_child(flight)
	var nameplate := Kit.panel()
	nameplate.add_theme_stylebox_override("panel",Kit.box(Color(.018,.075,.092,.78),Color(.37,.65,.61,.25),7,10))
	flight.add_child(nameplate)
	var aircraft_title := Kit.row(8)
	nameplate.add_child(aircraft_title)
	var airframe_identity := Kit.column(2)
	aircraft_title.add_child(airframe_identity)
	airframe_identity.add_child(Kit.label("AIRFRAME / "+str(aircraft.id).to_upper(),10,_accent(settings)))
	airframe_identity.add_child(Kit.label(str(aircraft.name),21,Kit.TEXT))
	var edit := Kit.button("机库配装",func(): dispatch.call("navigate",{"page":"hangar"}))
	edit.size_flags_horizontal = Control.SIZE_SHRINK_END
	edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	aircraft_title.add_child(edit)
	flight.add_child(_airframe_view(aircraft,settings))
	flight.add_child(Kit.label(str(FRAME_ROLES.get(str(aircraft.id),"模块化机体 · 起飞前整备")),11,Color("c3d6d0")))
	var telemetry := Kit.panel()
	telemetry.add_theme_stylebox_override("panel",Kit.box(Color(.018,.075,.092,.88),Color(.37,.65,.61,.42),7,10))
	flight.add_child(telemetry)
	var metrics := Kit.row(12)
	telemetry.add_child(metrics)
	if bool(aircraft.valid):
		metrics.add_child(_small_metric("%.1f kg" % float(aircraft.derived.get("mass_kg",0)),"当前空载整机"))
		metrics.add_child(_small_metric("%.1f kg" % float(aircraft.derived.get("cargo_rating_kg",0)),"当前额定载荷"))
		metrics.add_child(_small_metric("%.0f m/s" % float(aircraft.derived.get("speed_mps",0)),"当前配装速度上限"))
	else:
		metrics.add_child(Kit.label("配装暂不可读取，请到机库检查。",13,Kit.GOLD))
	# A long, quiet mission strip is the second hierarchy, rather than another
	# grid of identical dashboard cards competing with the departure hero.
	var mission := Kit.panel()
	mission.add_theme_stylebox_override("panel",Kit.box(Color(.025,.095,.12,.94),Color("365c63"),10,18))
	root.add_child(mission)
	var mission_col := Kit.column(12)
	mission.add_child(mission_col)
	var mission_head := Kit.row(12)
	mission_col.add_child(mission_head)
	var mission_copy := Kit.column(5)
	mission_head.add_child(mission_copy)
	mission_copy.add_child(Kit.label("NEXT SIGNAL  /  旅程中的下一声呼叫",11,Kit.ACCENT))
	mission_copy.add_child(Kit.label(str(journey.title),24,Kit.TEXT))
	mission_copy.add_child(Kit.label(str(journey.objective),14,Kit.MUTED))
	var progress_text := Kit.metric("%02d / %d" % [int(journey.completed),int(journey.total)],"主线目标记录")
	progress_text.custom_minimum_size.x = 116
	progress_text.size_flags_horizontal = Control.SIZE_SHRINK_END
	mission_head.add_child(progress_text)
	mission_col.add_child(_progress(int(journey.completed),int(journey.total)))
	mission_col.add_child(_district_ribbon(region,journey.state))
	var mission_actions := Kit.row(10)
	mission_col.add_child(mission_actions)
	mission_actions.add_child(Kit.button("查看两界航图",func(): dispatch.call("navigate",{"page":"map"})))
	mission_actions.add_child(Kit.button("打开任务中心",func(): dispatch.call("navigate",{"page":"missions"})))
	var lower := Kit.grid(3)
	root.add_child(lower)
	_responsive_columns(lower,3,800.0)
	lower.add_child(_shortcut("01","前哨基地","检视机体与模块，让下一次出航准备充分。","前往基地","base",dispatch))
	lower.add_child(_shortcut("02","探索纪事","跟进可选委托、航路遭遇与留在各地的发现。","查看探索","events",dispatch))
	lower.add_child(_shortcut("03","小队同行","管理本机保存的伙伴地址，准备局域网协作。","联机好友","friends",dispatch))
	var summary: Dictionary = ctx.get("summary",{})
	if bool(summary.get("available",false)):
		var recap := Kit.panel()
		root.add_child(recap)
		var recap_row := Kit.row(12)
		recap.add_child(recap_row)
		var discoveries: Array = summary.get("discovery_ids",[])
		var objectives: Array = summary.get("objective_ids",[])
		recap_row.add_child(Kit.label("上次归航  ·  %.0f 分钟  ·  %d 项目标  ·  %d 份发现" % [float(summary.get("duration_seconds",0))/60.0,objectives.size(),discoveries.size()],13,Kit.MUTED))
		recap_row.add_child(Kit.button("查看结算",func(): dispatch.call("navigate",{"page":"results"})))
	return root

static func _modes(ctx: Dictionary,dispatch: Callable) -> Control:
	var root := Kit.column(18)
	root.name = "FrontModes"
	var active := bool(ctx.get("active",false))
	var aircraft: Dictionary = _aircraft(ctx)
	var settings: Dictionary = ctx.get("settings",{})
	root.add_child(Kit.heading("选择下一程","DEPARTURE  /  出航方式","一个人沿着自己的节奏探索，或和一位伙伴在同一局域网共同修复。"))
	if active:
		var current := Kit.panel()
		current.add_theme_stylebox_override("panel",Kit.box(Color("163d42"),Kit.ACCENT,12,18))
		root.add_child(current)
		var current_col := Kit.column(10)
		current.add_child(current_col)
		current_col.add_child(Kit.label("当前航行仍在进行",23,Kit.TEXT))
		current_col.add_child(Kit.label("继续飞行，或先保存战况并返回基地，再更换出航方式。",14,Kit.MUTED))
		var current_actions := Kit.row(12)
		current_col.add_child(current_actions)
		current_actions.add_child(Kit.button("继续当前航行",func(): dispatch.call("legacy",{"action":"resume","payload":{}}),true))
		current_actions.add_child(Kit.button("保存并返回基地",func(): dispatch.call("legacy",{"action":"hangar_return","payload":{}})))
	var columns := Kit.grid(2)
	root.add_child(columns)
	_responsive_columns(columns,2,760.0)
	var solo := Kit.panel()
	solo.clip_contents = true
	solo.add_theme_stylebox_override("panel",Kit.box(Color("09232c"),Color("6a9b90"),14,24))
	columns.add_child(solo)
	var solo_scenery := Backdrop.new()
	solo_scenery.set_scene_card()
	solo_scenery.set_reduce_motion(bool(settings.get("reduced_motion",false)))
	solo_scenery.set_accent(_accent(settings))
	solo_scenery.modulate.a = .37
	solo.add_child(solo_scenery)
	var single := Kit.column(14)
	solo.add_child(single)
	single.add_child(Kit.label("01  /  SOLO FLIGHT",11,Kit.ACCENT))
	single.add_child(Kit.label("单人航行",31,Kit.TEXT))
	single.add_child(Kit.label("一架飞机，\n也能连起两界。",24,Kit.TEXT))
	single.add_child(Kit.label("直接接续本机存档。探索、战斗、章节选择与可选委托都沿原有旅程推进。",15,Kit.MUTED))
	var launch := Kit.button("单人出航   →",func(): dispatch.call("legacy",{"action":"solo","payload":{"frame":maxi(0,Hangar.FRAME_ORDER.find(str(aircraft.id)))}}),true)
	launch.custom_minimum_size.y = 54
	launch.disabled = active or not bool(aircraft.valid)
	if active: launch.tooltip_text = "先保存当前航行并返回基地。"
	elif not bool(aircraft.valid): launch.tooltip_text = "先在机库确认可用配装。"
	single.add_child(launch)
	for item in ["按自己的节奏观察、制动与行动","既有目标、发现和配装继续保留","回到大厅后，可继续整理下一次出航"]:
		single.add_child(Kit.label("—  "+str(item),13,Kit.MUTED))
	single.add_child(Kit.label("离线游玩 · 无需账号或互联网",11,Kit.MUTED))
	var team := Kit.column(14)
	columns.add_child(team)
	var host := Kit.card("创建双人房间","由这台电脑担任房主。伙伴输入你的局域网地址加入，双方共同完成行动与重要决定。","02  /  局域网房主")
	team.add_child(host)
	host.add_child(Kit.label("共同世界由房主沿原存档保存。",12,Kit.GOLD))
	var host_action := Kit.button("准备创建房间   →",func(): dispatch.call("navigate",{"page":"room","intent":"host"}))
	host_action.disabled = active
	host.add_child(host_action)
	var join := Kit.card("加入伙伴","已有房主在等待？前往小队房间，输入或选择已保存的房主地址。","03  /  局域网来宾")
	team.add_child(join)
	join.add_child(Kit.label("使用同一局域网；不使用全球匹配或在线账号。",12,Kit.MUTED))
	var join_action := Kit.button("前往加入房间   →",func(): dispatch.call("navigate",{"page":"room","intent":"join"}))
	join_action.disabled = active
	join.add_child(join_action)
	var prepare := Kit.panel()
	root.add_child(prepare)
	var prepare_col := Kit.column(12)
	prepare.add_child(prepare_col)
	prepare_col.add_child(Kit.label("出航前，确认你的搭档",21,Kit.TEXT))
	prepare_col.add_child(Kit.label(str(aircraft.id).to_upper()+" · "+str(aircraft.name)+"  /  "+str(FRAME_ROLES.get(str(aircraft.id),"模块化机体")),14,Kit.ACCENT))
	prepare_col.add_child(Kit.label("当前配装已从本地档案读取。" if bool(aircraft.valid) else "当前配装暂不可用，请先进入机库检查。",13,Kit.MUTED if bool(aircraft.valid) else Kit.GOLD))
	var prep_actions := Kit.row(10)
	prepare_col.add_child(prep_actions)
	prep_actions.add_child(Kit.button("检查机库配装",func(): dispatch.call("navigate",{"page":"hangar"})))
	prep_actions.add_child(Kit.button("管理伙伴地址",func(): dispatch.call("navigate",{"page":"friends"})))
	prep_actions.add_child(Kit.button("返回大厅",func(): dispatch.call("navigate",{"page":"home"})))
	return root

static func _journey(ctx: Dictionary) -> Dictionary:
	var profile: Dictionary = ctx.get("profile",{})
	var world: Dictionary = profile.get("world",{})
	var state: Dictionary = world.get("actions",{}).get("opening",{})
	var region := str(world.get("region_id","I1"))
	var session: Variant = ctx.get("session")
	var director: Variant
	if session is Object and is_instance_valid(session):
		if bool(ctx.get("active",false)): region = str(session.region_id)
		var story: Variant = session.get("story")
		if story is Object and is_instance_valid(story): director = story.get("director")
	var definitions: Dictionary = {}
	var hud: Dictionary = {}
	if director is Object and is_instance_valid(director):
		definitions = director.definitions()
		if state.is_empty(): state = director.default_state()
		hud = director.hud(state,region)
	var total := 0
	for action: Dictionary in definitions.get("actions",[]): total += action.get("objectives",[]).size()
	if total <= 0: total = 84
	var completed: Array = state.get("completed",[])
	var objective := "接听林岚的呼叫，先接回桥后失联的检修机。"
	var objectives: Array = hud.get("objectives",[])
	if not objectives.is_empty(): objective = str(objectives[0].get("text",objective))
	if bool(hud.get("complete",false)): objective = "共同决定与修复记录已保留。回访各地伙伴，继续探索尚未完成的支路。"
	var definition: Dictionary = Regions.definition(region)
	return {"state":state,"region":region,"region_name":str(definition.get("name",region)),
		"completed":completed.size(),"total":total,"title":str(hud.get("title","断流之后")),
		"objective":objective,"complete":bool(hud.get("complete",false))}

static func _aircraft(ctx: Dictionary) -> Dictionary:
	var frames: Dictionary = Catalog.airframes()
	var frame_id := str(ctx.get("frame_id","tr01"))
	if not frames.has(frame_id): frame_id = "tr01"
	var frame: Dictionary = frames.get(frame_id,{})
	var profile: Dictionary = ctx.get("profile",{})
	var selected: Dictionary = Hangar.launch_build(profile,frame_id)
	var resolved: Dictionary = selected.get("resolved",{})
	var build: Dictionary = selected.get("build",{})
	return {"id":frame_id,"frame":frame,"name":str(frame.get("name",frame_id)),
		"valid":bool(selected.get("ok",false)),"derived":resolved.get("derived",{}),"slots":build.get("slots",{})}

static func _airframe_view(aircraft: Dictionary,settings: Dictionary) -> Control:
	var view: Control
	if ResourceLoader.exists(AIRFRAME_STAGE):
		view = load(AIRFRAME_STAGE).new()
		view.set_airframe(str(aircraft.id),aircraft.frame,aircraft.get("slots",{}))
	else:
		# Preserve a readable selected-frame view if the optional preview
		# resource cannot be loaded; the real hangar action is independent.
		view = Backdrop.new()
		view.set_airframe(str(aircraft.id),aircraft.frame)
	view.name = "SelectedAirframePreview"
	view.custom_minimum_size.y = 240
	view.set_reduce_motion(bool(settings.get("reduced_motion",false)))
	view.set_accent(_accent(settings))
	return view

static func _small_metric(value: String,caption: String) -> VBoxContainer:
	var root := Kit.column(3)
	root.add_child(Kit.label(value,19,Kit.TEXT))
	root.add_child(Kit.label(caption,10,Kit.MUTED))
	return root

static func _pill(text: String,color: Color) -> PanelContainer:
	var node := PanelContainer.new()
	node.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	node.add_theme_stylebox_override("panel",Kit.box(Color(color.r,color.g,color.b,.08),Color(color.r,color.g,color.b,.3),5,7))
	var caption:=Kit.label(text,10,color)
	caption.autowrap_mode=TextServer.AUTOWRAP_OFF
	node.add_child(caption)
	return node

static func _progress(value: int,maximum: int) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.max_value = maxi(1,maximum)
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size.y = 5
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background",Kit.box(Color("1b3b43"),Color("1b3b43"),3,0))
	bar.add_theme_stylebox_override("fill",Kit.box(Kit.ACCENT,Kit.ACCENT,3,0))
	return bar

static func _district_ribbon(current: String,state: Dictionary) -> Control:
	var grid := Kit.grid(8)
	grid.add_theme_constant_override("h_separation",5)
	grid.add_theme_constant_override("v_separation",7)
	var completed_actions: Array = state.get("completed_actions",[])
	for region: String in REGION_ORDER:
		var recorded := false
		for id: String in completed_actions:
			if id.begins_with(region+":"): recorded = true; break
		var color: Color = Kit.ACCENT if region == current else Kit.TEXT if recorded else Color("6f8c91")
		var node := Kit.column(3)
		node.add_child(Kit.label(("●  " if region == current else "·  ")+str(REGION_SHORT[region]),11,color))
		node.tooltip_text = "存档当前地区" if region == current else "此地已有行动记录" if recorded else "尚无此地行动完成记录"
		grid.add_child(node)
	var responsive := func():
		var desired := 4 if grid.size.x < 600 else 8
		if grid.columns != desired: grid.columns = desired
	grid.resized.connect(responsive)
	grid.ready.connect(responsive,CONNECT_ONE_SHOT)
	return grid

static func _shortcut(number: String,title: String,description: String,cta: String,page: String,dispatch: Callable) -> PanelContainer:
	var root := Kit.panel()
	root.add_theme_stylebox_override("panel",Kit.box(Color("0d2731"),Kit.LINE,10,17))
	var body := Kit.column(8)
	root.add_child(body)
	body.add_child(Kit.label(number,11,Kit.GOLD))
	body.add_child(Kit.label(title,20,Kit.TEXT))
	body.add_child(Kit.label(description,13,Kit.MUTED))
	body.add_child(Kit.button(cta,func(): dispatch.call("navigate",{"page":page})))
	return root

static func _responsive_columns(grid: GridContainer,wide: int,threshold: float) -> void:
	var update := func():
		var desired := 1 if grid.size.x < threshold else wide
		if grid.columns != desired: grid.columns = desired
	grid.resized.connect(update)
	grid.ready.connect(update,CONNECT_ONE_SHOT)

static func _accent(settings: Dictionary) -> Color:
	match str(settings.get("equipped_style","harbor")):
		"canopy": return Color("c9dd88")
		"furnace": return Color("ffb179")
		"confluence": return Color("bfb0ff")
	return Kit.ACCENT
