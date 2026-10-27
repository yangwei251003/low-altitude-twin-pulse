extends SceneTree
## Actual MAIN and monotonic wall time; accepted lethal DamageModel fixture.
var main: Node
var checks: Array = []
var output := ""
func _initialize() -> void:
 _run.call_deferred()
func check(value: bool, label: String) -> void:
 checks.append({"passed":value,"label":label})
func wait_wall(seconds: float) -> void:
 var deadline := Time.get_ticks_usec()+int(seconds*1000000.0)
 while Time.get_ticks_usec()<deadline: await process_frame
func wait_paused(value: bool) -> bool:
 var deadline := Time.get_ticks_usec()+5000000
 while main.simulation_paused!=value and Time.get_ticks_usec()<deadline: await process_frame
 return main.simulation_paused==value
func _run() -> void:
 var profile := ""
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--qa-profile="): profile=arg.trim_prefix("--qa-profile=")
  elif arg.begins_with("--pause-report="): output=arg.trim_prefix("--pause-report=")
 if not profile.begins_with("qa_pause_downed72_") or not output.is_absolute_path(): quit(2);return
 main=load("res://scenes/v3/main.tscn").instantiate()
 root.add_child(main)
 check(main.start_flight("solo"),"original MAIN solo begins")
 await process_frame
 var body=main.players[1]
 var crash_edges: Array=[]
 var disabled_edges: Array=[]
 body.crash_started.connect(func():crash_edges.append(Time.get_ticks_usec()))
 body.disabled.connect(func():disabled_edges.append(Time.get_ticks_usec()))
 body.apply_combat_hit(100000.0,Vector3.RIGHT,body.global_position,"pulse",{"source":"explicit_pause_lifecycle_QA"})
 check(not body.enabled and body.health<=0.0 and crash_edges.size()==1,"original accepted lethal damage starts one crash")
 main._request_pause()
 check(await wait_paused(true),"original solo consensus applies common pause")
 var clock: float=body.crash_seconds
 var begin := Time.get_ticks_usec()
 await wait_wall(2.4)
 var elapsed := float(Time.get_ticks_usec()-begin)/1000000.0
 check(elapsed>=2.4,"pause wait uses at least 2.4 monotonic wall seconds")
 check(main.simulation_paused and not body.is_processing() and body.freeze,"paused body stays process-stopped and physics-frozen")
 check(not body.enabled and body.health<=0.0 and absf(body.crash_seconds-clock)<0.001 and disabled_edges.is_empty(),"downed clock and delayed recovery remain held during pause")
 main._request_pause()
 check(await wait_paused(false),"original solo consensus resumes")
 check(body.is_processing() and not body.freeze,"resume restores original processing and physics")
 var deadline := Time.get_ticks_usec()+6000000
 while not body.enabled and Time.get_ticks_usec()<deadline: await process_frame
 check(body.enabled and body.health==body.maximum_health and disabled_edges.size()==1,"original delayed callback restores body exactly once after resume")
 main._request_pause()
 check(await wait_paused(true),"common pause can be applied again")
 main._restore_player(1,body.global_position)
 check(main.simulation_paused and body.freeze and not body.is_processing(),"accepted restore while paused cannot unfreeze or restart body lifecycle")
 main._request_pause()
 check(await wait_paused(false),"second pause resumes normally")
 var passed: bool=checks.all(func(row: Dictionary):return row.passed)
 var report={"passed":passed,"checks":checks,"pause_wall_seconds":elapsed,"crash_edges":crash_edges.size(),"delayed_disabled_edges":disabled_edges.size(),"scope":"Source MAIN original DamageModel lethal fixture / solo consensus / real wall wait / original retry and normal SaveQuit. Not OS input, Boss, cargo ownership, two-peer pause or human comfort evidence."}
 var file=FileAccess.open(output,FileAccess.WRITE)
 if file==null: quit(2);return
 file.store_string(JSON.stringify(report,"\t"));file.close()
 print("PAUSE_DOWNED72_RESULT "+JSON.stringify(report))
 if not passed: quit(1);return
 main._quit()
 create_timer(20).timeout.connect(func():push_error("Pause regression normal quit timeout");quit(1))
