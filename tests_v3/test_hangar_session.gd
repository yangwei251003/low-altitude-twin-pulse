extends SceneTree
## Isolated actual MAIN, Store and Flight. Discovery below is an explicit loadout
## fixture; this test is not natural campaign, hardware-controller or LAN proof.
const MAIN = preload("res://scenes/v3/main.tscn")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const Hangar = preload("res://scripts/v3/gameplay/twin_hangar.gd")
var session: Node
var checks: Array = []
var failed := false
var profile := ""
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile = arg.trim_prefix("--qa-profile=")
	if not profile.begins_with("qa_hangar_session_") or profile != profile.validate_filename() or DirAccess.dir_exists_absolute("user://profiles_v3/"+profile): quit(2); return
	root.content_scale_size = Vector2i(1024,576)
	root.size = Vector2i(1024,576)
	session = MAIN.instantiate()
	root.add_child(session)
	if not _check(session.profile_ready,"original fresh MAIN profile opens"): await _finish(); return
	var initial: Dictionary = session.store.snapshot()
	_check(initial.personal.discoveries.is_empty(),"no natural campaign progress in the explicit loadout fixture")
	session._ui_action("hangar",{})
	await process_frame
	_check(session.interface.hangar.visible and session.interface.hangar.size.x <= 1024 and session.interface.hangar.size.y <= 576,"native loadout modal fits 1024x576 viewport")
	var unlocked: Dictionary = session.store.commit({"id":"qa-loadout-unlock-fixture","append":{"personal.discoveries":["boss:I1:harbor_whale"]}})
	if not _check(unlocked.get("ok",false),"explicit fixture uses the original Store discovery transaction"): await _finish(); return
	session._open_hangar()
	var draft: Dictionary = Hangar.launch_build(session.store.snapshot(),"tr01").build
	draft.slots.utility = "reinforced_guard"
	var before: Dictionary = session.store.snapshot()
	session.store.failure_point = "before_write"
	session._ui_action("hangar_save",{"build":draft,"generation":before.generation})
	_check(session.store.snapshot() == before and session.interface.hangar._status.text.contains("草稿保留"),"original failed save preserves loadout and allows retry")
	session.store.failure_point = ""
	session._ui_action("hangar_save",{"build":draft,"generation":before.generation})
	var reader: RefCounted = Store.new("user://profiles_v3/"+profile)
	_check(reader.load_profile().ok and Hangar.launch_build(reader.snapshot()).build.slots.utility == "reinforced_guard","fresh original Store reads saved loadout")
	session._ui_action("hangar_close",{})
	session._ui_action("solo",{"frame":0})
	if not _check(session.active and session.players.has(1),"ordinary menu launches a new Flight"): await _finish(); return
	session.inputs.test_enabled = true
	session.inputs.test_frame = {"axes":{},"held":["brake"],"edges":[]}
	var body: FlightBodyV2 = session.players[1]
	_check(body.build.slots.utility == "reinforced_guard" and is_equal_approx(body.damage_state.armor,26.0) and body.model.get_child_count() > 0,"actual Flight receives saved hardware, original armor and native visuals")
	var actor_id: int = body.get_instance_id()
	var actual_build: Dictionary = body.build.duplicate(true)
	body.health = 71.0 # Explicit damage fixture checks that menu actions never reconfigure/heal it.
	session._ui_action("menu",{})
	session._ui_action("solo",{"frame":1})
	_check(session.players[1].get_instance_id() == actor_id and body.health == 71.0 and body.build == actual_build,"active launch button resumes same Flight without changing frame or healing")
	session._ui_action("hangar",{})
	var active_store: Dictionary = session.store.snapshot()
	session._ui_action("hangar_save",{"build":Hangar.launch_build(active_store,"hx02").build,"generation":active_store.generation})
	await physics_frame
	await process_frame
	_check(session.store.snapshot() == active_store and body.build == actual_build and not session.inputs.active,"forged active save is rejected and modal suppresses flight inputs")
	session.interface._update_controller_focus()
	var focus: Control = root.gui_get_focus_owner()
	_check(focus != null and session.interface.hangar.is_ancestor_of(focus),"keyboard native focus remains inside loadout modal")
	var tabs_contained := true
	for index: int in 8:
		var tab := InputEventKey.new()
		tab.keycode = KEY_TAB
		tab.physical_keycode = KEY_TAB
		tab.pressed = true
		root.push_input(tab)
		await process_frame
		var next_focus: Control = root.gui_get_focus_owner()
		tabs_contained = tabs_contained and next_focus!=null and session.interface.hangar.is_ancestor_of(next_focus)
		tab.pressed = false
		root.push_input(tab)
	_check(tabs_contained and session.interface.address.focus_mode == Control.FOCUS_NONE,"native Tab traversal cannot focus the background LAN address")
	session.store.failure_point = "before_write"
	session._ui_action("hangar_return",{})
	for i: int in 12:
		await physics_frame
		await process_frame
	_check(session.active and session.players[1].get_instance_id() == actor_id and session.store.snapshot() == active_store and not session.environment_save_gate.pending(),"original lifecycle save failure retains actual world and Flight")
	session.store.failure_point = ""
	session._ui_action("hangar_return",{})
	for i: int in 12:
		await physics_frame
		await process_frame
	_check(not session.active and session.players.is_empty() and not is_instance_valid(session.world) and session.interface.hangar.visible and not session.environment_save_gate.pending(),"successful original SaveGate returns to editable hangar after releasing region")
	_check(session.store.snapshot().personal.discoveries == ["boss:I1:harbor_whale"],"hangar and departure add no campaign reward")
	await _finish()
func _check(ok: bool,label: String) -> bool:
	checks.append({"ok":ok,"label":label})
	if not ok: failed = true; push_error("HANGAR_SESSION: "+label)
	return ok
func _finish() -> void:
	if is_instance_valid(session):
		session.store.failure_point = ""
		session.active = false
		session.audio.shutdown()
		session.network.close()
		var bound: int = Time.get_ticks_msec()+1000
		while not session.audio.shutdown_status().ready and Time.get_ticks_msec()<bound: await process_frame
		_check(session.audio.shutdown_status().ready,"native audio references drain")
		session.queue_free()
		await process_frame
	print("HANGAR_SESSION_RESULT "+JSON.stringify({"checks":checks,"pass":not failed,"profile":profile,"scope":"isolated source MAIN/loadout/Store/lifecycle; not natural campaign, actual controller or LAN"}))
	quit(1 if failed else 0)
