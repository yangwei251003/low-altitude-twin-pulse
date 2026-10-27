extends SceneTree
## New isolated profile; native GUI actions + original flight/return/save APIs only.
const Main = preload("res://scenes/v3/main.tscn")
var session
var front
var output := ""
var checks: Array = []
var captures: Array = []
var scope := "full"
class ErrorLog extends Logger:
	var errors: Array = []
	var guard := Mutex.new()
	func _log_error(function: String, file: String, line: int, code: String, reason: String, _notify: bool, kind: int, _trace: Array[ScriptBacktrace]) -> void:
		if kind == Logger.ERROR_TYPE_WARNING: return
		guard.lock()
		if errors.size()<30: errors.append({"function":function,"file":file,"line":line,"code":code,"reason":reason})
		guard.unlock()
var logger := ErrorLog.new()

func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	var profile := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile=arg.trim_prefix("--qa-profile=")
		elif arg.begins_with("--output="): output=arg.trim_prefix("--output=")
		elif arg.begins_with("--front-scope="): scope=arg.trim_prefix("--front-scope=")
	if not profile.begins_with("qa_front93_") or profile!=profile.validate_filename() or not output.is_absolute_path() or FileAccess.file_exists(output) or ".." in output: quit(2); return
	if DirAccess.dir_exists_absolute("user://profiles_v3/"+profile): quit(2); return
	session=Main.instantiate()
	root.add_child(session)
	await _settle()
	front=session.interface.front
	if not _check(is_instance_valid(front) and session.profile_ready,"front-end and profile initialized"): await _finish(); return
	_check(front.page=="home" and not session.active and session.players.is_empty() and not is_instance_valid(session.world),"startup is lobby only, no automatic world or player")
	if scope=="connection":
		front.dispatch("launch",{"mode":"guest","address":"127.0.0.1"})
		var deadline:=Time.get_ticks_msec()+50000
		while (front._loading or session.network.mode!="disconnected") and Time.get_ticks_msec()<deadline: await process_frame
		await _settle()
		_check(session.network.mode=="disconnected" and not session.active and front.page=="room","failed real connection returns to usable room UI")
		_check(_button_containing("创建双人房间")!=null,"failed connection rebuilds room actions for retry")
		await _capture("connection_failed")
		front.navigate("home")
		await _capture("home_after_connection")
		await _finish()
		return
	await _capture("home")
	for page: String in ["modes","profile","map","missions","events","results","base","inventory","workshop","shop","friends"]:
		if front._nav_buttons.has(page): await _accept(front._nav_buttons[page])
		else: front.navigate(page); await _settle()
		_check(front.page==page and front._body.get_child_count()==1,"page opens through real navigation: "+page)
		await _capture(page)
	front.navigate("settings")
	await _settle()
	await _capture("settings")
	_check(front._body.find_children("*","HSlider",true,false).size()==6,"all six live audio settings present")
	front.dispatch("profile_name",{"name":"界面验收航员"})
	front.dispatch("setting",{"key":"reduced_motion","value":true})
	var preferences=load("res://scripts/v3/ui/front/twin_front_preferences.gd").new()
	preferences.open(session.store.root_path)
	_check(preferences.values.profile_name=="界面验收航员" and preferences.values.reduced_motion,"independent preference reader sees saved name and reduced motion")
	var generation: int=int(session.store.snapshot().generation)
	front.dispatch("claim_style",{"id":"confluence"})
	_check("confluence" not in front.prefs.values.claimed_styles and int(session.store.snapshot().generation)==generation,"locked style rejects without changing campaign or claim state")
	front.navigate("friends")
	await _settle()
	var edits: Array=front._body.find_children("*","LineEdit",true,false)
	if _check(edits.size()==2,"contact editor has nickname and address"):
		edits[0].text="界面验收伙伴"
		edits[1].text="invalid"
		await _accept_text("保存联系人")
		_check(front.prefs.values.contacts.is_empty(),"invalid friend address rejects")
		edits[1].text="192.0.2.10"
		await _accept_text("保存联系人")
		_check(front.prefs.values.contacts.size()==1,"friend saved locally")
		await _accept_text("移除联系人")
		_check(front._modal!=null,"destructive local contact action has confirmation")
		await _capture("confirmation")
		await _accept_text("取消 / 返回",true)
		_check(front.prefs.values.contacts.size()==1,"cancel preserves friend")
		await _accept_text("移除联系人")
		await _accept_text("确认",true)
		_check(front.prefs.values.contacts.is_empty(),"confirmed removal persists")
	front.navigate("inventory")
	await _settle()
	front.dispatch("inspect_module",{"id":"pulse_base"})
	await _settle()
	_check(front._modal!=null,"module detail opens actual catalog data")
	await _capture("module_detail")
	front.back()
	front.navigate("hangar")
	await _settle()
	_check(session.interface.hangar.visible,"real hangar opens from front-end")
	await _capture("hangar")
	await _accept(session.interface.hangar._save)
	_check(not session.interface.hangar._pending,"original hangar save returns acknowledgement")
	session._ui_action("hangar_close",{})
	front._legacy("handbook",{})
	await _settle()
	_check(session.interface.campaign_book.visible,"handbook opens from front-end")
	await _capture("handbook")
	session.final_flow.close_book()
	front.navigate("room")
	await _settle()
	await _capture("room_setup")
	front.dispatch("launch",{"mode":"guest","address":"invalid"})
	_check(not session.active,"invalid connection does not start session")
	if scope=="pages": await _finish(); return
	front.navigate("modes")
	await _settle()
	var solo: BaseButton=_button_containing("单人")
	if solo==null: _check(false,"single-player CTA exists"); await _finish(); return
	await _accept(solo)
	var until:=Time.get_ticks_msec()+30000
	while (front._loading or not session.players.has(1)) and Time.get_ticks_msec()<until: await process_frame
	await _settle()
	if not _check(session.active and session.players.has(1) and not session.interface.menu.visible and session.interface.hud.visible,"native departure from lobby loads actual world and HUD"): await _finish(); return
	await _capture("combat")
	session._ui_action("menu",{})
	await _settle()
	_check(session.interface.menu.visible and not session.inputs.active and session.simulation_paused,"solo lobby blocks input and original pause gate suspends world")
	front.resume_flight()
	await _settle()
	_check(not session.simulation_paused and not session.interface.menu.visible,"return resumes original world")
	front.navigate("base")
	await _settle()
	front._legacy("hangar_return",{})
	await _accept_text("确认",true)
	until=Time.get_ticks_msec()+15000
	while session.active and Time.get_ticks_msec()<until: await process_frame
	await _settle()
	_check(not session.active and front.page=="results" and front.summary.get("available",false),"native save return reaches real debrief")
	_check(int(front.summary.get("generation",-1))==int(session.store.snapshot().generation),"debrief bound to durable generation")
	await _capture("results_actual")
	front.navigate("room")
	await _settle()
	await _accept_text("创建双人房间")
	until=Time.get_ticks_msec()+30000
	while (front._loading or session.network.mode!="host") and Time.get_ticks_msec()<until: await process_frame
	await _settle()
	_check(session.active and session.network.mode=="host" and front.page=="room" and session.interface.menu.visible,"real ENet host remains on room page before enter")
	await _capture("room_host")
	front._legacy("hangar_return",{})
	await _accept_text("确认",true)
	until=Time.get_ticks_msec()+15000
	while session.active and Time.get_ticks_msec()<until: await process_frame
	await _settle()
	_check(not session.active and session.network.mode=="solo","return closes only own room via original lifecycle")
	await _finish()

func _button_containing(text: String) -> BaseButton:
	for button: BaseButton in front._body.find_children("*","BaseButton",true,false):
		if text in button.text and button.is_visible_in_tree() and not button.disabled: return button
	return null

func _accept_text(text: String, modal: bool=false) -> void:
	var parent: Node=front._modal if modal else front._body
	if parent==null: _check(false,"expected modal for "+text); return
	for button: BaseButton in parent.find_children("*","BaseButton",true,false):
		if button.text==text:
			await _accept(button)
			return
	_check(false,"GUI button exists: "+text)

func _accept(button: BaseButton) -> void:
	if not _check(is_instance_valid(button) and button.is_visible_in_tree() and not button.disabled,"native GUI target enabled"): return
	button.grab_focus()
	await _settle()
	if not _check(button.has_focus(),"native GUI target owns focus",button.text): return
	for pressed: bool in [true,false]:
		var event:=InputEventAction.new()
		event.action=&"ui_accept"
		event.pressed=pressed
		event.strength=1.0 if pressed else 0.0
		Input.parse_input_event(event)
		await process_frame
	await _settle()

func _settle() -> void:
	for index: int in range(8): await process_frame

func _capture(id: String) -> void:
	await _settle()
	await create_timer(0.22).timeout
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image()
	var file:=output.get_base_dir().path_join(id+".png")
	var status:=image.save_png(file)
	captures.append({"page":id,"path":file,"width":image.get_width(),"height":image.get_height(),"ok":status==OK})
	_check(status==OK,"actual GPU capture: "+id)
	if session.interface.menu.visible and front._modal==null and not session.interface.hangar.visible and not session.interface.campaign_book.visible:
		_check(front._scroll.size.x>650 and front._scroll.size.y>350,"front content has usable viewport: "+id,str(front._scroll.size))
	print("FRONT_PAGE ",id)

func _check(ok: bool, label: String, detail: Variant={}) -> bool:
	checks.append({"ok":ok,"label":label,"detail":detail})
	if not ok: print("FRONT_FAIL ",label," ",str(detail))
	return ok

func _finish() -> void:
	_check(logger.errors.is_empty(),"no recorded engine errors",logger.errors)
	var failures: Array=checks.filter(func(row: Dictionary): return not row.ok)
	var result: Dictionary={"passed":failures.is_empty(),"checks":checks,"captures":captures,"source_version":ProjectSettings.get_setting("application/config/version"),"scope":"new source front-end, real GUI activation and original lifecycle; not a full campaign replay or human comfort proof","profile_path":session.store.root_path,"final_generation":session.store.snapshot().generation,"summary":front.summary}
	var file:=FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	file.close()
	print("FRONT_RESULT ",JSON.stringify({"passed":result.passed,"checks":checks.size(),"failures":failures.size(),"output":output}))
	session._quit()
