extends Control
## One front-end coordinator. Every campaign mutation stays in the original Session.
const Kit = preload("res://scripts/v3/ui/front/twin_front_kit.gd")
const Prefs = preload("res://scripts/v3/ui/front/twin_front_preferences.gd")
const Hangar = preload("res://scripts/v3/gameplay/twin_hangar.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
const PAGES := {"home":"指挥大厅","modes":"选择模式","room":"小队房间","waiting":"出航准备","profile":"航员档案","settings":"设置","results":"航行结算","combat":"对局战斗","base":"前哨基地","hangar":"HANGAR 机库","inventory":"模块仓库","workshop":"整备工坊","map":"两界航图","missions":"任务中心","events":"探索活动","friends":"联机好友","shop":"补给商城","assist":"自动驾驶辅助"}
var session
var interface
var prefs = Prefs.new()
var page := "home"
var selection: Dictionary = {}
var history: Array[String] = []
var summary: Dictionary = {}
var _start: Dictionary = {}
var _return_destination := ""
var _body: VBoxContainer
var _scroll: ScrollContainer
var _crumb: Label
var _identity: Button
var _status: Label
var _back: Button
var _backdrop: Control
var _modal: Control
var _modal_return_focus: WeakRef
var _toast_time := 0.0
var _transition: Tween
var _loading := false
var _launch_serial := 0
var _waiting_since := 0
var _room_line: Label
var _waiting_line: Label
var _room_signature := ""
var _room_waiting := false
var _departure_mode := "solo"
var _departure_address := ""
var _menu_was_visible := true
var _auto_pause := false
var _nav_buttons: Dictionary = {}
var _cached_journal: Dictionary = {}
var _page_serial := 0
var _page_accent: Control
var _last_hover_sound := 0
var _pending_assist_scope := ""
var _assist_line: Label

func setup(owner_session) -> void:
	session = owner_session
	interface = session.interface
	name = "FrontEnd"
	prefs.open(session.store.root_path)
	summary = prefs.values.last_summary.duplicate(true)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var front_theme := Theme.new()
	front_theme.default_font = load("res://assets/fonts/NotoSansSC-Medium.ttf")
	front_theme.default_font_size = int(prefs.values.font_size)
	theme = front_theme
	Kit.configure_feedback(bool(prefs.values.reduced_motion),_button_feedback)
	_build_shell()
	_apply_display()
	session.network.status_changed.connect(notify)
	session.network.event_received.connect(func(event: Dictionary):
		if event.get("kind")=="content_journal88" and event.get("document") is Dictionary: _cached_journal=event.document.duplicate(true))
	interface.menu.visibility_changed.connect(_menu_changed)
	navigate("home",false)
	if not prefs.error.is_empty(): notify(prefs.error)

func _build_shell() -> void:
	_backdrop = load("res://scripts/v3/ui/front/twin_front_backdrop.gd").new()
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_backdrop)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,22)
	add_child(margin)
	var shell := Kit.column(16)
	margin.add_child(shell)
	var top := Kit.row(16)
	shell.add_child(top)
	var emblem:=TextureRect.new()
	emblem.texture=load("res://assets/ui/front/twinpulse_emblem.svg")
	emblem.custom_minimum_size=Vector2(42,42)
	emblem.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.mouse_filter=Control.MOUSE_FILTER_IGNORE
	top.add_child(emblem)
	var brand := Kit.column(0)
	brand.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	top.add_child(brand)
	brand.add_child(Kit.label("低空小队  /  两界共脉",23))
	brand.add_child(Kit.label("TWIN PULSE  ·  FLIGHT OPERATIONS",11,Color("83aaa9")))
	_identity=Kit.button("",func(): navigate("profile"))
	_identity.size_flags_horizontal=Control.SIZE_SHRINK_END
	_identity.custom_minimum_size.x=190
	top.add_child(_identity)
	var settings_button:=Kit.button("设置",func(): navigate("settings"))
	_set_icon(settings_button,"settings")
	settings_button.size_flags_horizontal=Control.SIZE_SHRINK_END
	settings_button.custom_minimum_size.x=92
	top.add_child(settings_button)
	var middle := Kit.row(24)
	middle.size_flags_vertical=Control.SIZE_EXPAND_FILL
	shell.add_child(middle)
	var navigation := ScrollContainer.new()
	navigation.custom_minimum_size.x=184
	navigation.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	navigation.follow_focus=true
	middle.add_child(navigation)
	var rail := Kit.column(5)
	rail.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	navigation.add_child(rail)
	for group: Array in [["出 航",["home","modes","room","map","missions","assist"]],["整 备",["base","hangar","inventory","workshop","shop"]],["小 队",["events","friends","profile","results"]]]:
		rail.add_child(Kit.label(str(group[0]),11,Color("78979a")))
		for id: String in group[1]:
			var button := Kit.button(str(PAGES[id]),func(): navigate(id))
			_set_icon(button,id)
			button.alignment=HORIZONTAL_ALIGNMENT_LEFT
			button.custom_minimum_size.y=30
			button.add_theme_font_size_override("font_size",14)
			for style_name: String in ["normal","hover","pressed","disabled"]:
				var style: StyleBoxFlat=button.get_theme_stylebox(style_name).duplicate()
				style.content_margin_top=4
				style.content_margin_bottom=4
				button.add_theme_stylebox_override(style_name,style)
			rail.add_child(button)
			_nav_buttons[id]=button
	var work := Kit.column(12)
	work.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	middle.add_child(work)
	_crumb=Kit.label("",12,Color("91b4b2"))
	work.add_child(_crumb)
	_scroll=ScrollContainer.new()
	_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus=true
	work.add_child(_scroll)
	_body=Kit.column(14)
	_body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var page_margin:=MarginContainer.new()
	page_margin.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for side: String in ["left","right","top","bottom"]: page_margin.add_theme_constant_override("margin_"+side,8)
	_scroll.add_child(page_margin)
	page_margin.add_child(_body)
	_page_accent=load("res://scripts/v3/ui/front/twin_front_transition.gd").new()
	_scroll.add_child(_page_accent)
	var footer := Kit.row(16)
	shell.add_child(footer)
	_back=Kit.button("返回",back)
	_back.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	_back.custom_minimum_size.x=124
	footer.add_child(_back)
	_status=Kit.label("离线档案 · 自动保存  /  局域网双人协作",12,Color("b7cec8"))
	_status.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	footer.add_child(_status)
	var guide_button:=Kit.button("飞行手册",func(): _legacy("handbook",{}))
	guide_button.size_flags_horizontal=Control.SIZE_SHRINK_END
	footer.add_child(guide_button)
	var quit_button:=Kit.button("退出",func(): _confirm("结束本次航行？","飞行进度会沿原存档流程保存；如果保存失败，将留在游戏内。",func(): session._ui_action("quit",{})))
	quit_button.size_flags_horizontal=Control.SIZE_SHRINK_END
	footer.add_child(quit_button)

func context() -> Dictionary:
	var profile: Dictionary = session.world_cache.duplicate(true) if session.active else session.store.snapshot()
	return {"session":session,"profile":profile,"active":session.active,"frame_id":session.frame_id,"settings":prefs.values.duplicate(true),"summary":summary.duplicate(true),"selection":selection.duplicate(true),"journal":_cached_journal.duplicate(true)}

func navigate(target: String, remember: bool = true) -> void:
	if _loading: notify("正在准备场景，请稍候。"); return
	if not PAGES.has(target): notify("此页面不存在："+target); return
	if _modal!=null: _close_modal()
	if target=="hangar":
		session._ui_action("hangar",{})
		return
	if target=="combat":
		if session.active: resume_flight()
		else: navigate("modes")
		return
	if remember and target!=page:
		history.append(page)
		if history.size()>24: history.pop_front()
	page=target
	interface.menu.show()
	if not session.active: interface.hud.hide()
	_render_page()

func _render_page() -> void:
	_page_serial+=1
	if _transition and _transition.is_valid(): _transition.kill()
	for child: Node in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_scroll.scroll_vertical=0
	_crumb.text="指挥终端   /   "+str(PAGES[page])
	_identity.text=str(prefs.values.profile_name)+"   •   "+session.frame_id.to_upper()
	for id: String in _nav_buttons:
		_nav_buttons[id].modulate=Color("ffffff") if id==page else Color("91acaa")
		var selected_style:=Kit.box(Color("174d52") if id==page else Color(0.025,0.08,0.105,.72),Color("7be1ce") if id==page else Color("29434c"),6,12)
		selected_style.content_margin_top=4
		selected_style.content_margin_bottom=4
		selected_style.border_width_left=3 if id==page else 1
		_nav_buttons[id].add_theme_stylebox_override("normal",selected_style)
	var content: Control
	var ctx := context()
	match page:
		"home","modes": content=load("res://scripts/v3/ui/front/twin_front_home.gd").build(page,ctx,dispatch)
		"profile","map","missions","events","results": content=load("res://scripts/v3/ui/front/twin_front_journey.gd").build(page,ctx,dispatch)
		"base","inventory","workshop","shop": content=load("res://scripts/v3/ui/front/twin_front_equipment.gd").build(page,ctx,dispatch)
		"settings": content=_settings_page()
		"friends": content=_friends_page()
		"room": content=_room_page()
		"waiting": content=_waiting_page()
		"assist": content=_assist_page()
	if content==null:
		content=Kit.heading("页面暂不可用","SYSTEM","请返回大厅后重试。")
	_body.add_child(content)
	_body.modulate.a=1.0
	if not prefs.values.reduced_motion:
		_body.modulate.a=0.0
		_transition=create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_transition.tween_property(_body,"modulate:a",1.0,0.18)
	_back.text="返回飞行" if history.is_empty() and session.active else "返回大厅" if history.is_empty() else "返回"
	_focus_page.call_deferred()
	_apply_accent()
	_page_accent.play(bool(prefs.values.reduced_motion),_crumb.modulate)

func _set_icon(button: Button, id: String) -> void:
	var path:="res://assets/ui/front/dev94/nav_"+id+".svg"
	if ResourceLoader.exists(path):
		button.icon=load(path)
		button.expand_icon=true
		button.add_theme_constant_override("icon_max_width",18)
		button.add_theme_constant_override("h_separation",9)

func _button_feedback(event: String, primary: bool) -> void:
	if not is_instance_valid(session) or not is_instance_valid(session.audio): return
	# Programmatic page focus stays silent. Hover is short and rate limited;
	# actual activation uses the existing pool, UI volume and mute settings.
	if event=="focus": return
	if event=="hover":
		var now:=Time.get_ticks_msec()
		if now-_last_hover_sound<110: return
		_last_hover_sound=now
		session.audio.play_event("front_hover",Vector3.ZERO,{"emitter":"front_navigation"})
	elif event=="press":
		session.audio.play_event("front_engage" if primary else "front_press",Vector3.ZERO,{"emitter":"front_navigation"})

func _focus_page() -> void:
	var serial:=_page_serial
	await get_tree().process_frame
	await get_tree().process_frame
	if serial!=_page_serial: return
	if not is_visible_in_tree() or _modal!=null or interface.hangar.visible or interface.campaign_book.visible: return
	interface._update_controller_focus()
	for node: Node in _body.find_children("*","Control",true,false):
		if node is BaseButton and node.is_visible_in_tree() and not node.disabled and node.focus_mode!=Control.FOCUS_NONE:
			node.grab_focus()
			_scroll.set_deferred("scroll_vertical",0)
			return
	_back.grab_focus()
	_scroll.set_deferred("scroll_vertical",0)

func dispatch(action: String, payload: Dictionary = {}) -> void:
	if _loading: notify("正在准备场景，请稍候。"); return
	match action:
		"navigate":
			if payload.has("intent"): selection.room_intent=str(payload.intent)
			navigate(str(payload.get("page","home")))
			if payload.get("page")=="hangar" and payload.get("restore_stock",false) and interface.hangar.has_method("restore_stock_draft"):
				interface.hangar.restore_stock_draft()
		"legacy": _legacy(str(payload.get("action","")),payload.get("payload",{}))
		"select_frame":
			if session.active: notify("当前机体已出航；先保存并返回基地再更换。"); return
			var id: String=str(payload.get("frame_id",""))
			if id not in Hangar.FRAME_ORDER: notify("无法识别此机体。"); return
			session.frame_id=id
			interface.frames.select(Hangar.FRAME_ORDER.find(id))
			_render_page()
			notify("本次出航机体："+id.to_upper()+"；配装保存在机库内管理。")
		"page_filter":
			selection[str(payload.get("key",""))]=payload.get("value","")
			_render_page()
		"profile_name":
			var value: String=str(payload.get("name","")).strip_edges()
			if value.is_empty() or value.length()>16 or "\n" in value: notify("呼号请输入 1–16 个字。 "); return
			_save_setting("profile_name",value)
		"setting": _save_setting(str(payload.get("key","")),payload.get("value"))
		"claim_style","equip_style": _style_action(action,str(payload.get("id","")))
		"inspect_module":
			var info: Dictionary=load("res://scripts/v3/ui/front/twin_front_equipment.gd").module_info(context(),str(payload.get("id","")))
			_confirm(str(info.get("title","模块资料")),str(info.get("body",""))+"\n\n"+str(info.get("stats",""))+"\n"+str(info.get("source",""))+"\n"+str(info.get("status","")),func(): navigate("workshop"),"前往工坊")
		"launch": _launch(str(payload.get("mode","solo")),str(payload.get("address","")))
		"assist_start": _start_assist(str(payload.get("scope","objective")))
		_: notify("操作尚未识别："+action)

func _legacy(action: String, payload: Dictionary) -> void:
	match action:
		"solo","host","join":
			_launch("guest" if action=="join" else action,str(payload.get("address",selection.get("room_address",""))))
		"resume": resume_flight()
		"hangar_return":
			_confirm("保存战况并返回基地？","当前航行将结束；已取得成果沿原保存流程保留。房主返回会关闭当前局域网房间。",func():
				_return_destination="results"
				session._return_to_hangar())
		"travel_to":
			if not session.active: navigate("modes"); return
			_travel_when_ready(payload)
		"journal_track":
			if not session.active: notify("先出航，再使用实地导航。"); return
			session._ui_action(action,payload)
			resume_flight()
		"handbook","ending_book","journal","hangar","branch","confirm","cancel": session._ui_action(action,payload)
		_: notify("此操作不在当前终端中开放："+action)

func _travel_when_ready(payload: Dictionary) -> void:
	resume_flight()
	var deadline:=Time.get_ticks_msec()+5000
	while session.active and session.simulation_paused and Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
	if not session.active: return
	if session.simulation_paused:
		notify("航路尚未提交；请先完成当前共同恢复决定。")
		return
	session._ui_action("travel_to",payload)

func back() -> void:
	if _modal!=null: _close_modal(); return
	if _loading: return
	if not history.is_empty(): navigate(history.pop_back(),false)
	elif page!="home": navigate("home",false)
	elif session.active: resume_flight()

func handle_cancel() -> bool:
	if not interface.menu.visible or interface.hangar.visible or interface.campaign_book.visible or interface.journal.visible: return false
	back()
	return true

func _menu_changed() -> void:
	if interface.menu.visible:
		_menu_was_visible=true
		if not _loading:
			_render_page()
			# Solo menus suspend through the original authority and custody pause gate.
			if session.active and session.network.mode=="solo" and not session.simulation_paused and session.consensus.current_proposal().is_empty():
				_auto_pause=true
				session._request_pause()
	else:
		_menu_was_visible=false
		if _auto_pause and session.active and session.simulation_paused and session.network.mode=="solo" and session.consensus.current_proposal().is_empty():
			session._request_pause()
		if not session.active: _auto_pause=false

func resume_flight() -> void:
	if not session.active: navigate("modes"); return
	if _room_waiting and session.network.mode=="guest" and (not session.players.has(session.network.local_id()) or not session._facilities_ready()):
		notify("正在接收房主世界，完成后即可进入。")
		return
	_room_waiting=false
	interface.menu.hide()
	interface.hud.show()
	session.inputs.clear()

func _launch(mode: String, address: String = "") -> void:
	if session.active: navigate("room"); return
	if mode not in ["solo","host","guest"]: notify("请选择单人出航或局域网双人。"); return
	if mode=="guest" and not Prefs.valid_address(address): notify("请输入有效的房主 IPv4 地址，例如 192.168.1.20。"); return
	_departure_mode=mode
	_departure_address=address.strip_edges()
	_start={"profile":session.store.snapshot(),"stats":session.stats.duplicate(true),"time":Time.get_ticks_msec(),"frame_id":session.frame_id,"mode":mode,"region_id":session.region_id}
	navigate("waiting")
	_loading=true
	_launch_serial+=1
	_waiting_since=Time.get_ticks_msec()
	_deferred_launch.call_deferred(_launch_serial)

func _deferred_launch(serial: int) -> void:
	# Render the real preparation page before synchronous region construction.
	await get_tree().process_frame
	await get_tree().process_frame
	if serial!=_launch_serial: return
	var success: bool=session.start_flight(_departure_mode,_departure_address)
	_loading=false
	if not success:
		_pending_assist_scope=""
		navigate("modes",false)
		notify("未能出航。请查看上方提示或检查存档／局域网连接。")
		return
	if _departure_mode=="solo":
		history.clear()
		page="home"
		interface.menu.hide()
		if not _pending_assist_scope.is_empty():
			var requested:=_pending_assist_scope
			_pending_assist_scope=""
			_start_assist.call_deferred(requested)
	else:
		_room_waiting=true
		_waiting_since=Time.get_ticks_msec()
		navigate("room",false)

func on_returned() -> void:
	if _start.has("profile"):
		var before: Dictionary=_start.profile
		var after: Dictionary=session.store.snapshot()
		var prior: Array=before.get("world",{}).get("actions",{}).get("opening",{}).get("completed",[])
		var completed: Array=after.get("world",{}).get("actions",{}).get("opening",{}).get("completed",[])
		var gained: Array=[]
		for id: Variant in completed:
			if id not in prior: gained.append(id)
		var discoveries: Array=[]
		for id: Variant in after.get("personal",{}).get("discoveries",[]):
			if id not in before.get("personal",{}).get("discoveries",[]): discoveries.append(id)
		var stats: Dictionary={}
		for id: String in ["shots","abilities","actions"]: stats[id]=maxi(0,int(session.stats.get(id,0))-int(_start.stats.get(id,0)))
		var old_missions:=_completed_missions(before)
		var missions:=_completed_missions(after).filter(func(id: String): return id not in old_missions)
		summary={"available":true,"title":"航行已归档","region_id":session.region_id,"mode":str(_start.mode),"frame_id":str(_start.frame_id),"duration_seconds":float(Time.get_ticks_msec()-int(_start.time))/1000.0,"objective_ids":gained,"discovery_ids":discoveries,"completed_missions":missions,"stats":stats,"generation":int(after.get("generation",0))}
		var next: Dictionary=prefs.values.duplicate(true)
		next.last_summary=summary.duplicate(true)
		if not prefs.write(next): notify("战况已保存，但本机结算摘要未写入。")
		_start.clear()
	_room_waiting=false
	_auto_pause=false
	if not _return_destination.is_empty():
		var destination:=_return_destination
		_return_destination=""
		interface.hangar.hide()
		history.clear()
		navigate(destination,false)

func _completed_missions(profile: Dictionary) -> Array:
	var result: Array=[]
	var saved: Dictionary=profile.get("world",{})
	for bank: String in ["npc_sidejobs_v1","field_requests_next_v1","side_stories_dev88_v1"]:
		var jobs: Dictionary=saved.get(bank,{}).get("jobs",{})
		for id: String in jobs:
			var row: Dictionary=jobs[id]
			if row.get("status")=="complete" or row.get("complete")==true: result.append(id)
	return result

func notify(text: String) -> void:
	if _status==null: return
	_status.text=text
	_status.modulate=Color("ffe0ac")
	_toast_time=9.0
	if is_instance_valid(_waiting_line): _waiting_line.text=text

func _process(delta: float) -> void:
	# A carried-body pause can complete asynchronously at a native safe boundary.
	# If the menu closed meanwhile, resume only the pause this menu requested.
	if _auto_pause and not _menu_was_visible and session.active and session.network.mode=="solo" and session.consensus.current_proposal().is_empty():
		if session.simulation_paused: session._request_pause()
		if not session.simulation_paused: _auto_pause=false
	if not is_visible_in_tree(): return
	if page=="assist" and is_instance_valid(_assist_line) and is_instance_valid(session.flight_assist):
		var assist_state: Dictionary=session.flight_assist.status()
		_assist_line.text=str(assist_state.get("objective_text",""))+"\n"+str(assist_state.get("message","等待选择辅助方式。"))
	_toast_time=maxf(0.0,_toast_time-delta)
	if _toast_time<=0 and _status!=null:
		_status.text="局域网航行中 · 世界仍在运行" if session.active and session.network.mode in ["host","guest"] else "单人已暂停 · 返回继续航行" if session.active and session.simulation_paused else "离线档案 · 自动保存  /  局域网双人协作"
		_status.modulate=Color.WHITE
	if page=="room" and is_instance_valid(_room_line):
		var signature:=str(session.active)+str(session.network.mode)+str(session.network.guests.size())+str(session.players.size())+str(session.active and session._facilities_ready())
		if signature!=_room_signature:
			_room_signature=signature
			_render_page()
		if _room_waiting and session.network.mode=="disconnected":
			_room_waiting=false
			notify("连接已断开。可保存返回基地，或重新选择房间。")
		elif _room_waiting and session.network.mode=="guest" and Time.get_ticks_msec()-_waiting_since>45000:
			notify("同步时间较长，可取消连接后核对版本和房主地址。")
			_room_waiting=false

func _assist_page() -> Control:
	var col:=Kit.column(18)
	col.add_child(Kit.heading("让领航员带你走一程","FLIGHT ASSIST / 自动辅助","观看真实驾驶、能力使用与任务操作；你随时可以接回操控。"))
	var status:=Kit.card("当前辅助状态","","NOW")
	_assist_line=Kit.label("从当前已开放的主线目标开始。",17)
	status.add_child(_assist_line)
	col.add_child(status)
	var choices:=Kit.grid(3)
	col.add_child(choices)
	for entry: Array in [["objective","当前目标","完成当前这一步后停下，方便观察与学习。"],["chapter","当前航区","继续本区主线，章节决定交由你确认。"],["journey","连续主线","沿已开放航路逐区推进；遇到重要决定时等待你。"]]:
		var scope: String=entry[0]
		var card:=Kit.card(str(entry[1]),str(entry[2]))
		choices.add_child(card)
		card.add_child(Kit.button("开启辅助" if session.active else "单人出航并开启",func(): _start_assist(scope),scope=="objective"))
	var stop:=Kit.button("停止辅助，交还手动驾驶",func():
		if is_instance_valid(session.flight_assist): session.flight_assist.stop("已交还手动驾驶")
		if session.active: resume_flight()
		else: notify("当前未在飞行。"))
	col.add_child(stop)
	col.add_child(Kit.label("W / S / A / D、升降、制动或手动动作可接管。打开菜单时辅助暂停；不会替你选择剧情方案。已完成的任务仍按原存档记录，尚未开放的任务不会跳过前置。\n伙伴委托与自由探索由你选择；本页的连续范围是八区主线。",14,Kit.MUTED))
	col.add_child(Kit.button("查看任务步骤",func(): navigate("missions")))
	return col

func _start_assist(scope: String) -> void:
	if scope not in ["objective","chapter","journey"]: return
	if not session.active:
		_pending_assist_scope=scope
		_launch("solo")
		return
	resume_flight()
	var deadline:=Time.get_ticks_msec()+5000
	while session.simulation_paused and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	if not session.active or interface.menu.visible: return
	var result: Dictionary=session.start_flight_assist(scope)
	if not result.get("ok",false):
		navigate("assist")
		notify(str(result.get("message",result.get("error","辅助暂不可用，请核对当前目标。"))))

func _settings_page() -> Control:
	var col:=Kit.column(16)
	col.add_child(Kit.heading("把驾驶舱调成你的习惯","SETTINGS","设置即时生效并保存至当前本地档案。"))
	var display:=Kit.card("显示与界面","","01 / DISPLAY")
	col.add_child(display)
	for pair: Array in [["fullscreen","全屏显示"],["vsync","垂直同步"],["reduced_motion","减少界面动效"]]:
		var key: String=pair[0]
		var toggle:=CheckButton.new()
		toggle.text=pair[1]
		toggle.button_pressed=bool(prefs.values[key])
		toggle.custom_minimum_size.y=38
		display.add_child(toggle)
		toggle.toggled.connect(func(value: bool): _save_setting(key,value,false))
	var fps:=OptionButton.new()
	for cap: int in [30,60,120]: fps.add_item("画面上限  %d FPS"%cap)
	fps.select([30,60,120].find(int(prefs.values.fps_limit)))
	fps.item_selected.connect(func(index: int): _save_setting("fps_limit",[30,60,120][index],false))
	display.add_child(fps)
	var sound:=Kit.card("声音混音","对白采用中文合成配音，可分别调节环境、音乐和提示音。","02 / AUDIO")
	col.add_child(sound)
	var audio_settings=load("res://scripts/v3/audio/twin_audio_settings.gd").new()
	sound.add_child(audio_settings)
	audio_settings.ready.connect(func():
		audio_settings.setup(session.audio)
		audio_settings._toggle.button_pressed=true,CONNECT_ONE_SHOT)
	var controls:=Kit.card("飞行与交互","机头跟随：W / S 前进后退，A / D 转向；镜头在机头后上方平滑跟随。\n固定视角：WASD 沿原固定画面方向移动，Z / C 转向。\nE / Q 升降   空格制动\nTab 选目标   F 使用能力   X 反向   G 联络\nJ / 左键开火   M 航路   L 纪事   H 手册\nEsc 返回 / 大厅   P 共同暂停\n手柄：右杆飞行 · 左杆升降 / 转向 · A 制动；菜单方向键 / A 确认 / B 返回。","03 / CONTROLS")
	col.add_child(controls)
	var flight_style:=OptionButton.new()
	flight_style.add_item("机头跟随 · W沿机头前进 / A D转向")
	flight_style.add_item("固定视角 · 保留原地图方向操控")
	flight_style.select(0 if prefs.values.flight_control=="heading" else 1)
	flight_style.item_selected.connect(func(index: int): _save_setting("flight_control","heading" if index==0 else "map",false))
	controls.add_child(flight_style)
	controls.add_child(Kit.button("阅读完整飞行手册",func(): _legacy("handbook",{})))
	return col

func _friends_page() -> Control:
	var col:=Kit.column(16)
	col.add_child(Kit.heading("熟悉的声音，在同一片天空","SQUAD / CONTACTS","本机联机联系人；不代表在线状态。两位玩家需在同一局域网并使用相同游戏版本。"))
	var form:=Kit.card("添加联机好友","房主在房间页可查看本机局域网地址。","LOCAL ADDRESS BOOK")
	col.add_child(form)
	var name_edit:=LineEdit.new()
	name_edit.placeholder_text="伙伴昵称（最多16字）"
	name_edit.max_length=16
	name_edit.custom_minimum_size.y=40
	form.add_child(name_edit)
	var address_edit:=LineEdit.new()
	address_edit.placeholder_text="IPv4，例如 192.168.1.20"
	address_edit.max_length=15
	address_edit.custom_minimum_size.y=40
	form.add_child(address_edit)
	form.add_child(Kit.button("保存联系人",func():
		var nickname:=name_edit.text.strip_edges()
		var address:=address_edit.text.strip_edges()
		if nickname.is_empty() or not Prefs.valid_address(address): notify("请填写昵称和有效 IPv4 地址。"); return
		var next: Dictionary=prefs.values.duplicate(true)
		if next.contacts.size()>=24: notify("通讯录最多保留24位伙伴。"); return
		for entry: Dictionary in next.contacts:
			if entry.address==address: notify("此地址已在通讯录中。"); return
		next.contacts.append({"name":nickname,"address":address})
		if prefs.write(next): _render_page(); notify("联系人已保存至本机。")
		else: notify("联系人未保存，请检查可写空间。"),true))
	if prefs.values.contacts.is_empty(): col.add_child(Kit.card("通讯录还是空的","先保存伙伴的地址，再前往房间加入。单人出航始终可用。"))
	for contact: Dictionary in prefs.values.contacts:
		var row:=Kit.card(str(contact.name),str(contact.address)+"  ·  在线状态未探测")
		col.add_child(row)
		var buttons:=Kit.row()
		row.add_child(buttons)
		buttons.add_child(Kit.button("选择并加入房间",func(): selection.room_address=str(contact.address); navigate("room")))
		buttons.add_child(Kit.button("移除联系人",func(): _confirm("移除此联机联系人？",str(contact.name)+"的本机地址记录将被移除；不会影响游戏存档。",func():
			var next: Dictionary=prefs.values.duplicate(true)
			next.contacts=next.contacts.filter(func(item: Dictionary): return item.address!=contact.address)
			if prefs.write(next): _render_page(); notify("联系人已移除。")
			else: notify("未能保存通讯录。"))))
	return col

func _room_status() -> String:
	if not session.active: return "尚未创建房间 · 选择机体和模式后出航"
	if session.network.mode=="host": return "房主已就绪  ·  伙伴 %d / 1\n%s"%[session.network.guests.size(),"伙伴已加入，可一同进入航行。" if not session.network.guests.is_empty() else "房间真实开放，等待同一局域网伙伴连接；也可先行出航。"]
	if session.network.mode=="guest": return "已接收房主世界 · 可进入航行" if session.players.has(session.network.local_id()) and session._facilities_ready() else "连接中 · 正在接收房主的地区、机关与进度"
	if session.network.mode=="disconnected": return "连接已断开 · 已确认个人成果保留"
	return "当前为单人航行 · 更换房间前先保存并返回基地"

func _room_page() -> Control:
	var col:=Kit.column(16)
	col.add_child(Kit.heading("两架飞行器，同一条航线","LAN / ROOM","房主保存世界进度；伙伴保留已确认的个人发现。最多2人，使用同版本游戏。"))
	var state:=Kit.card("小队席位","","ROOM STATUS")
	col.add_child(state)
	_room_line=Kit.label(_room_status(),20)
	state.add_child(_room_line)
	if session.active:
		state.add_child(Kit.button("进入当前航行",resume_flight,true))
		state.add_child(Kit.button("保存并返回基地 / 取消连接",func(): _legacy("hangar_return",{})))
		if session.network.mode in ["host","guest"]:
			state.add_child(Kit.label("联机房间内世界仍在运行。需要暂停时，请进入航行后按 P，由小队共同确认。",14,Color("e4c895")))
	else:
		state.add_child(Kit.button("创建双人房间",func(): _launch("host"),true))
	var addresses: PackedStringArray=[]
	for address: String in IP.get_local_addresses():
		if Prefs.valid_address(address) and not address.begins_with("127.") and not address.begins_with("169.254."): addresses.append(address)
	col.add_child(Kit.card("本机地址",("\n".join(addresses) if not addresses.is_empty() else "未检测到可用局域网 IPv4，请检查网络连接。")+"\n游戏端口：26742 · 请将地址告诉同一局域网的伙伴。"))
	if not session.active:
		var join:=Kit.card("加入伙伴房间","请先让伙伴创建房间；本机不会自动搜索或伪造房间列表。")
		col.add_child(join)
		var edit:=LineEdit.new()
		edit.placeholder_text="房主 IPv4 地址"
		edit.text=str(selection.get("room_address",""))
		edit.max_length=15
		edit.custom_minimum_size.y=44
		join.add_child(edit)
		edit.text_changed.connect(func(value: String): selection.room_address=value)
		join.add_child(Kit.button("连接房主",func(): _launch("guest",edit.text),true))
		join.add_child(Kit.button("从联机好友选择",func(): navigate("friends")))
	return col

func _waiting_page() -> Control:
	var col:=Kit.column(24)
	col.add_child(Kit.heading("飞行前的最后准备","DEPARTURE / CHECKLIST","正在读取当前档案与场景。完成后进入单人航行或小队房间。"))
	var card:=Kit.card("准备出航","机体  "+session.frame_id.to_upper()+"\n档案  "+str(prefs.values.profile_name))
	col.add_child(card)
	_waiting_line=Kit.label("正在准备地区、装配机体和连接状态……",20,Color("8ce1ce"))
	card.add_child(_waiting_line)
	card.add_child(Kit.label("使用 E / Q 控制高度，空格制动。接近联络点后按 G。",16))
	return col

func _save_setting(key: String, value: Variant, rebuild: bool = true) -> void:
	if key not in ["profile_name","fullscreen","vsync","reduced_motion","fps_limit","font_size","flight_control"]: notify("此设置不可修改。"); return
	if key=="flight_control" and value not in ["heading","map"]: notify("飞行操控模式无效。"); return
	if key in ["fullscreen","vsync","reduced_motion"] and not value is bool: notify("设置值无效。"); return
	if key=="fps_limit" and int(value) not in [30,60,120]: return
	var next: Dictionary=prefs.values.duplicate(true)
	next[key]=value
	if not prefs.write(next):
		notify("设置未保存；当前值保持不变。")
		if rebuild: _render_page()
		return
	_apply_display()
	if rebuild: _render_page()
	notify("设置已保存。")

func _apply_display() -> void:
	if DisplayServer.get_name()!="headless":
		var desired:=DisplayServer.WINDOW_MODE_FULLSCREEN if prefs.values.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode()!=desired: DisplayServer.window_set_mode(desired)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if prefs.values.vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps=int(prefs.values.fps_limit)
	if session.inputs.has_method("set_control_scheme"): session.inputs.set_control_scheme(str(prefs.values.flight_control))
	session.flight_camera.follow_heading=prefs.values.flight_control=="heading"
	interface.heading_controls=prefs.values.flight_control=="heading"
	interface._update_controller_focus()
	_apply_accent()

func _apply_accent() -> void:
	var style: Dictionary=Prefs.STYLES.get(str(prefs.values.equipped_style),Prefs.STYLES.harbor)
	Kit.configure_feedback(bool(prefs.values.reduced_motion),_button_feedback)
	if _backdrop!=null:
		if _backdrop.has_method("set_reduce_motion"): _backdrop.set_reduce_motion(bool(prefs.values.reduced_motion))
		if _backdrop.has_method("set_accent"): _backdrop.set_accent(Color(str(style.color)))
	if _crumb!=null: _crumb.modulate=Color(str(style.color))
	if is_instance_valid(interface.hangar): interface.hangar.set_visual_preferences(bool(prefs.values.reduced_motion),Color(str(style.color)))

func _style_action(action: String, id: String) -> void:
	if not Prefs.STYLES.has(id): notify("未知的界面纪念样式。"); return
	var completed: Array=session.store.snapshot().get("world",{}).get("actions",{}).get("opening",{}).get("completed",[])
	if completed.size()<int(Prefs.STYLES[id].goals): notify("该样式的旅程条件尚未完成。"); return
	var next: Dictionary=prefs.values.duplicate(true)
	if action=="claim_style":
		if id in next.claimed_styles: notify("此样式已领取，可直接应用。"); return
		next.claimed_styles.append(id)
	else:
		if id not in next.claimed_styles: notify("先领取该样式，再应用。"); return
		next.equipped_style=id
	if prefs.write(next): _render_page(); notify("界面纪念样式已保存。")
	else: notify("样式未保存，请检查可写空间。")

func _confirm(title: String, body: String, accepted: Callable, affirmative: String = "确认") -> void:
	if _modal!=null: _close_modal()
	var focus:=get_viewport().gui_get_focus_owner()
	if focus!=null: _modal_return_focus=weakref(focus)
	_modal=Control.new()
	_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.mouse_filter=Control.MOUSE_FILTER_STOP
	add_child(_modal)
	var shade:=ColorRect.new()
	shade.color=Color(0.015,0.03,0.04,0.9)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.add_child(shade)
	var center:=CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.add_child(center)
	var box:=Kit.panel()
	box.custom_minimum_size=Vector2(530,0)
	center.add_child(box)
	var col:=Kit.column(20)
	box.add_child(col)
	col.add_child(Kit.label(title,24))
	var description:=Kit.label(body,16)
	description.custom_minimum_size.x=480
	description.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	col.add_child(description)
	var row:=Kit.row(14)
	col.add_child(row)
	var cancel:=Kit.button("取消 / 返回",_close_modal)
	row.add_child(cancel)
	row.add_child(Kit.button(affirmative,func(): _close_modal(); accepted.call(),true))
	Kit.animate_in(box,bool(prefs.values.reduced_motion))
	cancel.grab_focus()

func _close_modal() -> void:
	if _modal==null: return
	remove_child(_modal)
	_modal.queue_free()
	_modal=null
	interface._update_controller_focus()
	var focus = _modal_return_focus.get_ref() if _modal_return_focus!=null else null
	if is_instance_valid(focus) and focus.is_visible_in_tree(): focus.grab_focus()
	else: _focus_page.call_deferred()
	_modal_return_focus=null

func focus_scope() -> Control:
	return _modal if _modal!=null else self

func _exit_tree() -> void:
	Kit.configure_feedback(true,Callable())
	if _transition and _transition.is_valid(): _transition.kill()
