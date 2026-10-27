extends SceneTree
## Actual MAIN key routing regression; fresh QA profile is required by caller.
var main: Node
var checks: Array = []
func _initialize() -> void:
 _run.call_deferred()
func check(value: bool, label: String) -> void:
 checks.append({"passed":value,"label":label})
func send(physical: int, logical: int, pressed: bool=true, echo: bool=false) -> void:
 var event := InputEventKey.new()
 event.physical_keycode=physical; event.keycode=logical
 event.pressed=pressed; event.echo=echo
 main._unhandled_input(event)
func _run() -> void:
 var profile := ""
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--qa-profile="): profile=arg.trim_prefix("--qa-profile=")
 if not profile.begins_with("qa_special_keys71_"): quit(2); return
 main=load("res://scenes/v3/main.tscn").instantiate()
 root.add_child(main)
 check(main.start_flight("solo"),"ordinary MAIN starts original solo")
 await process_frame
 main.interface.menu.hide()
 send(KEY_PAUSE,KEY_ESCAPE)
 check(main.interface.menu.visible,"actual Windows virtual Esc opens menu despite unrelated physical Pause")
 send(KEY_PAUSE,KEY_ESCAPE)
 check(not main.interface.menu.visible,"same virtual Esc closes menu")
 send(KEY_ESCAPE,KEY_ESCAPE)
 check(main.interface.menu.visible,"hardware Esc still opens menu")
 send(KEY_ESCAPE,KEY_ESCAPE)
 check(not main.interface.menu.visible,"hardware Esc still closes menu")
 send(0,KEY_ESCAPE)
 check(main.interface.menu.visible,"logical special key works when physical is absent")
 send(0,KEY_ESCAPE)
 send(KEY_A,KEY_ESCAPE)
 check(not main.interface.menu.visible,"physical letter layout retains priority")
 send(KEY_PAUSE,KEY_ESCAPE,true,true)
 send(KEY_PAUSE,KEY_ESCAPE,false)
 check(not main.interface.menu.visible,"echo and key release do not toggle")
 main.interface.travel.show()
 send(KEY_PAUSE,KEY_ESCAPE)
 check(not main.interface.travel.visible and not main.interface.menu.visible,"Esc closes travel without opening menu")
 main.interface.chapter_choice.show()
 send(KEY_PAUSE,KEY_ESCAPE)
 check(not main.interface.chapter_choice.visible and not main.interface.menu.visible,"Esc closes chapter choice without opening menu")
 var passed: bool=checks.all(func(row: Dictionary):return row.passed)
 print("SPECIAL_KEYS71_RESULT "+JSON.stringify({"passed":passed,"checks":checks,"scope":"Source MAIN explicit key fixtures; not OS input, gamepad, performance or full gameplay"}))
 if not passed: quit(1); return
 main._quit()
 create_timer(20).timeout.connect(func():push_error("Special key ordinary quit timeout");quit(1))
