extends SceneTree
## Source MAIN only; run after original patrol, core review and bullet view promote.
const MAIN=preload("res://scenes/v3/main.tscn")
const Store=preload("res://scripts/v3/core/twin_world_store.gd")
const Codec=preload("res://scripts/v3/network/twin_snapshot_codec.gd")
const Pilot=preload("res://scripts/v3/qa/twin_normal_flight_pilot.gd")
const HOST_PATH="res://scripts/v3/gameplay/twin_f2_patrol_host.gd"
const VIEW_PATH="res://scripts/v3/gameplay/twin_f2_patrol_view.gd"
const ID="F2:patrol_01"
const MODEL="res://assets/models/v22_combat/enemy_scout.glb"
const MASK=1|2|4|8|32
const MAX_WALL_S=85.0

class ErrorLogger extends Logger:
	var errors: Array=[]
	var guard:=Mutex.new()
	func _log_error(function: String,file: String,line: int,code: String,rationale: String,_notify: bool,kind: int,_trace: Array[ScriptBacktrace]) -> void:
		if kind==Logger.ERROR_TYPE_WARNING: return
		guard.lock()
		errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale})
		guard.unlock()

class FlightDriver extends Node:
	var suite: Object
	func _physics_process(delta: float) -> void:
		if is_instance_valid(suite): suite._pilot_step(delta)

class ReceiverContext extends RefCounted:
	## Contract bookkeeping only: never bind a Guest actor or apply any view.
	var network: Dictionary={"mode":"guest"}
	var world: Node3D
	var region_id="F2"
	var received_session=""
	var entities: Dictionary={}

var logger:=ErrorLogger.new()
var session: Node
var driver: FlightDriver
var pilot
var host_script: Script
var view_script: Script
var profile=""
var output=""
var began_usec:=0
var stopping:=false
var native_exit_requested:=false
var wanted_fire:=false
var command_serial:=0
var checks: Array=[]
var fixtures: Array=[]
var observations: Array=[]
var pause_cycles: Array=[]
var contract_checks: Array=[]
var original_events: Array=[]
var baseline: Dictionary={}
var report_cache: Dictionary={}
var physics_samples:=0
var flown_distance:=0.0
var max_frame_motion:=0.0
var previous_position:=Vector3.ZERO
var phase="preflight"

func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile=arg.trim_prefix("--qa-profile=")
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	if not OS.is_debug_build() or not profile.begins_with("qa_f2_patrol_") or profile!=profile.validate_filename() or DirAccess.dir_exists_absolute("user://profiles_v3/"+profile) or not output.begins_with("res://artifacts/v3/f2-patrol-native-") or ".." in output or DirAccess.dir_exists_absolute(output):
		print("F2_PATROL_NATIVE_ARGUMENTS_REJECTED"); quit(2); return
	if not ResourceLoader.exists(HOST_PATH) or not ResourceLoader.exists(VIEW_PATH):
		print("F2_PATROL_NATIVE_PROMOTION_REQUIRED"); quit(2); return
	host_script=load(HOST_PATH)
	view_script=load(VIEW_PATH)
	if DirAccess.make_dir_recursive_absolute(output)!=OK: quit(2); return
	began_usec=Time.get_ticks_usec()
	_wall_watchdog.call_deferred()
	session=MAIN.instantiate()
	root.add_child(session)
	if not _check(session.profile_ready and session.store.root_path=="user://profiles_v3/"+profile and session.get("ambient_patrol")!=null,"ordinary MAIN opened only the fresh named QA profile and promoted helper",_status()): _stop("factory_preflight"); return
	# Location only. No Director, reward, discoveries, Boss or mechanism fixture.
	var located: Dictionary=session.store.commit({"id":"qa-f2-patrol-start-location-only","set":{"world.region_id":"F2"}})
	if not _check(located.get("ok",false),"original private Store accepts explicit empty F2 starting-region fixture",located): _stop("location_fixture_rejected"); return
	fixtures.append({"kind":"new_QA_starting_region_only","region":"F2","natural_predecessors_played":false})
	session.world_cache=session.store.snapshot()
	session.ambient_patrol.enabled=true # Before the normal factory bind, never allocate/assign a replacement.
	if not _check(session.start_flight("solo") and session.region_id=="F2" and session.world.build_errors.is_empty(),"normal MAIN factory binds the one optional actual scout before ordinary ticks",_status()): _stop("factory_bind"); return
	session.inputs.test_enabled=true
	for unused in 3:
		if not await _frame(): return
	baseline=_progress()
	if not _check(_body().build.slots.weapon=="pulse_base","fresh original departure retains the default V3 pulse weapon",_body().build): _stop("default_weapon_changed"); return
	if not _geometry(): _stop("actual_import_or_shape"); return
	phase="ordinary_patrol"
	var patrol_before: Dictionary=_actor_state()
	for unused in 120:
		if not await _frame(): return
	var patrol_after: Dictionary=_actor_state()
	if not _check(patrol_after.rid==patrol_before.rid and float(patrol_after.age)>float(patrol_before.age) and Vector3(patrol_after.pose.origin).distance_to(patrol_before.pose.origin)>.3 and int(session.ambient_patrol.serial)>0,"actual CharacterBody patrol moves under one ordinary Host tick stream",{"before":patrol_before,"after":patrol_after}): _stop("patrol_did_not_move"); return
	if not await _initial_blocked_observation(): _stop("initial_QA_observation_candidate_blocked"); return
	pilot=Pilot.new()
	if not _check(pilot.bind(_body()),"original continuous Pilot binds the actual aircraft"): _stop("pilot_bind"); return
	driver=FlightDriver.new()
	driver.suite=self
	session.add_child(driver) # After Session: the same QA-only normal command adapter as natural observers.
	previous_position=_body().global_position
	if not await _select_target(): _stop("Tab_target"); return
	phase="actual_occluded_held_fire"
	var before_hp: float=_scout().hp
	var before_serial: int=int(_scout().damage_state.serial)
	var before_shots: int=int(session.stats.shots)
	wanted_fire=true
	var blocked_frames:=0
	for unused in 24:
		var blocker: Dictionary=_ray()
		if blocker.is_empty() or blocker.get("rid")==_scout().get_rid() or not blocker.get("collider") is StaticBody3D: break
		if not await _frame(): return
		blocked_frames+=1
		if _scout().hp!=before_hp: break
	wanted_fire=false
	if not _check(blocked_frames>=12 and _scout().hp==before_hp and int(_scout().damage_state.serial)==before_serial and int(session.stats.shots)==before_shots,"native existing solid blocks locked held-fire without HP/receipt/accepted-shot change",{"frames":blocked_frames,"ray":_ray_detail(),"status":_status()}): _stop("occlusion_gate"); return
	phase="continuous_clear_side_flight"
	if not await _navigate(Vector3(8,14,10),24.0): _stop("continuous_route_failed"); return
	if not _check(flown_distance>3.0 and max_frame_motion<2.0,"after the single labelled initial pose, observation uses continuous native flight only",{"distance_m":flown_distance,"max_per_frame_m":max_frame_motion,"pilot":pilot.report()}): _stop("flight_continuity"); return
	phase="real_warning_pause"
	if not await _wait_warning(15.0): _stop("no_actual_warning"); return
	if not await _pause_cycle("warning_before_next_patrol_tick",true,false): _stop("warning_pause_failed"); return
	phase="real_live_projectile_pause"
	var bolt_deadline: float=_elapsed()+5.0
	while _healthy() and session.ambient_patrol._bolts.is_empty() and _elapsed()<bolt_deadline:
		if not await _frame(): return
	if not _check(not session.ambient_patrol._bolts.is_empty(),"original warning completion launches a real Host native-ray projectile",_status()): _stop("no_actual_bolt"); return
	# A separate nonempty-bolt case avoids claiming an empty warning-time table proves TTL freeze.
	if not await _pause_cycle("actual_nonempty_projectile",false,true): _stop("projectile_pause_failed"); return
	phase="original_locked_pulse_to_zero"
	if not await _select_target(): _stop("relock_after_pause"); return
	var damage_deadline: float=_elapsed()+8.0
	var damage_start:=int(session.stats.shots)
	wanted_fire=true
	while _healthy() and not _scout().dying and _elapsed()<damage_deadline:
		if not await _frame(): return
	wanted_fire=false
	original_events=session.ambient_patrol.events.duplicate(true)
	if not _check(_scout().dying and _scout().hp==0.0 and int(session.stats.shots)>damage_start and _damage_chain(before_hp,before_serial),"original Tab/held pulse and actual DamageModel receipts reach one genuine HP0 tombstone",{"events":original_events,"status":_status()}): _stop("real_damage_chain"); return
	var dead_state: Dictionary=_actor_state()
	var disabled_before: int=_event_count("disabled")
	wanted_fire=true
	for unused in 24:
		if not await _frame(): return
	wanted_fire=false
	if not _check(_scout().get_rid()==dead_state.rid and _scout().hp==0.0 and int(_scout().damage_state.serial)==int(dead_state.damage_serial) and _event_count("disabled")==disabled_before and disabled_before==1 and not session.entities.has(ID) and _scout().collision_layer==0 and not _scout().visible,"same-visit HP0 remains dead and cannot award/replay a second disabled or hit",_status()): _stop("tombstone_replayed"); return
	if not _check(_progress()==baseline,"patrol combat grants no Story receipt, personal reward, choice or Boss progress",{"before":baseline,"after":_progress()}): _stop("unexpected_progress"); return
	phase="original_save_reader"
	var saved: bool=session._save_environment()
	var reader=Store.new(session.store.root_path)
	var opened: Dictionary=reader.load_profile()
	var disk: Dictionary=reader.snapshot() if opened.get("ok",false) else {}
	if not _check(saved and opened.get("ok",false) and disk==session.store.snapshot() and not JSON.stringify(disk.world).contains(ID) and _progress()==baseline,"original save and fresh Store reader retain real environment without serializing transient patrol or granting rewards",{"saved":saved,"opened":opened,"generation":disk.get("generation"),"last_commit":session.last_commit_result}): _stop("original_save_reader"); return
	_stop("native_patrol_segment_completed")

func _geometry() -> bool:
	var scout=_scout()
	if not is_instance_valid(scout) or not scout is CharacterBody3D: return _check(false,"actual original CharacterBody scout exists",_status())
	var shapes: Array=[]
	for child: Node in scout.get_children():
		if child is CollisionShape3D and not child.disabled: shapes.append(child)
	var rid: RID=scout.get_rid()
	var valid: bool=shapes.size()==1 and shapes[0].shape is BoxShape3D and is_instance_valid(scout.model) and scout.model.scene_file_path==MODEL and scout.model.find_children("*","MeshInstance3D",true,false).size()>0 and scout.authoritative and not scout.is_physics_processing() and scout.get_world_3d().space==session.world.get_world_3d().space
	if valid:
		valid=shapes[0].shape.size==scout.dimensions and shapes[0].position==scout.damage_origin and PhysicsServer3D.body_get_space(rid)==session.world.get_world_3d().space and PhysicsServer3D.body_get_shape_count(rid)==1 and PhysicsServer3D.body_get_shape(rid,0)==shapes[0].shape.get_rid() and PhysicsServer3D.shape_get_data(shapes[0].shape.get_rid())==scout.dimensions*.5 and scout.collision_layer==4 and scout.collision_mask==MASK and PhysicsServer3D.body_get_collision_layer(rid)==4 and PhysicsServer3D.body_get_collision_mask(rid)==MASK and scout.hp==32.0 and scout.max_hp==32.0 and scout.damage_state.armor==5.0
	valid=valid and session.ambient_patrol.get_script().resource_path==HOST_PATH and scout.get_script().resource_path=="res://scripts/v3/gameplay/twin_f2_patrol_actor.gd" and scout.brain.get_script().resource_path=="res://scripts/v3/gameplay/twin_f2_patrol_brain.gd"
	var initial_view: Dictionary=session.ambient_patrol.presentation()
	valid=valid and view_script.valid(initial_view) and initial_view.get("bullets") is Array
	observations.append({"kind":"real_import_and_native_shape","model":scout.model.scene_file_path if is_instance_valid(scout.model) else "","dimensions":scout.dimensions,"damage_origin":scout.damage_origin,"native":_actor_state(),"actor_script":scout.get_script().resource_path,"brain_script":scout.brain.get_script().resource_path,"initial_source_view":initial_view})
	return _check(valid,"original imported GLB bounds make the same actual BoxShape/RID/mask in MAIN",observations.back())

func _initial_blocked_observation() -> bool:
	# One PLAYER-only pose fixture, selected against existing actual geometry; no QA obstacle.
	for solid: Node in session.world.find_children("Pad2","StaticBody3D",true,false):
		var away: Vector3=(solid.global_position-_scout().global_position).normalized()
		for distance_m: float in [8.0,10.0,12.0]:
			var at: Vector3=solid.global_position+away*distance_m
			if not _hull_clear(at) or session.ambient_patrol._protected_point(at,_pilot_half()): continue
			var hit: Dictionary=_ray_from(at)
			if hit.is_empty() or hit.get("rid")==_scout().get_rid() or not hit.get("collider") is StaticBody3D: continue
			var body: FlightBodyV2=_body()
			body.freeze=true
			body.global_transform=Transform3D(body.global_basis,at)
			body.force_update_transform()
			PhysicsServer3D.body_set_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,body.global_transform)
			body.linear_velocity=Vector3.ZERO; body.angular_velocity=Vector3.ZERO; body.hold_height=at.y
			fixtures.append({"kind":"one_explicit_PLAYER_initial_observation_pose","position":at,"occluder":str(hit.collider.get_path()),"actual_hull_clear":true,"natural_flight":false,"enemy_or_mechanism_pose_changed":false})
			for unused in 2:
				if not await _frame(): return false
			body.freeze=false
			var actual: Dictionary=_ray()
			return _check(not actual.is_empty() and actual.get("collider") is StaticBody3D and actual.get("rid")!=_scout().get_rid(),"single QA PLAYER observation begins behind an existing native opaque solid",_ray_detail())
	return _check(false,"initial blocked viewpoint candidate found without moving any original solid",_status())

func _navigate(target: Vector3,limit_s: float) -> bool:
	if not _hull_clear(target): return _check(false,"candidate continuous waypoint has native full-aircraft clearance",target)
	command_serial+=1
	if not pilot.go_to(target,command_serial): return false
	var deadline: float=_elapsed()+limit_s
	while _healthy() and _elapsed()<deadline:
		if not await _frame(): return false
		if _body().global_position.distance_to(target)<.22 and _body().linear_velocity.length()<.22: return true
	return _check(false,"ordinary continuous Pilot reached clear-side waypoint within bound",{"target":target,"position":_body().global_position,"pilot":pilot.report()})

func _pilot_step(delta: float) -> void:
	if stopping or not _healthy() or session.simulation_paused or pilot==null: return
	var at: Vector3=_body().global_position
	var moved: float=at.distance_to(previous_position)
	previous_position=at
	physics_samples+=1; flown_distance+=moved; max_frame_motion=maxf(max_frame_motion,moved)
	pilot.tick(delta,true,false) # Commands only; never manually advance MAIN, AI or PhysicsServer.

func _wait_warning(limit_s: float) -> bool:
	var deadline: float=_elapsed()+limit_s
	while _healthy() and _elapsed()<deadline:
		var view: Dictionary=session.ambient_patrol.presentation()
		if not view.is_empty() and view.actor.warning.active and _scout().telegraph>0.0:
			return _check(_ray().get("rid")==_scout().get_rid(),"real Brain/FOV/reaction sees the actual pilot and starts its original warning",view)
		if not await _frame(): return false
	return _check(false,"real warning starts within the observation bound",_status())

func _pause_cycle(label: String,require_warning: bool,require_bolt: bool) -> bool:
	var before: Dictionary=_actor_state()
	var view_before: Dictionary=session.ambient_patrol.presentation()
	if require_warning and not _check(view_before.actor.warning.active and _scout().telegraph>0.0,"pause begins inside a real warning before any extra patrol tick",view_before): return false
	if require_bolt and not _check(not session.ambient_patrol._bolts.is_empty() and not view_before.bullets.is_empty(),"projectile pause baseline has a real nonempty Host and source-view bullet table",view_before): return false
	var sequence: int=session.consensus._sequence
	session.network.send_action("propose",{"kind":"pause","payload":{}})
	if not _check(session.simulation_paused and session.consensus._sequence==sequence+1 and session.consensus.current_proposal().is_empty(),"original solo Consensus applies pause immediately at the observed real warning/bolt boundary",_status()): return false
	var context:=ReceiverContext.new()
	context.world=session.world; context.received_session=session.network.session_id
	var receiver=host_script.new()
	receiver.setup(context); receiver.enabled=true
	receiver._remote_session=view_before.session_id; receiver._remote_epoch=int(view_before.epoch); receiver._remote_serial=int(view_before.serial); receiver._remote_view=view_before.duplicate(true)
	var stable:=true
	var accepted:=0
	var source_rows: Array=[]
	for unused in 12:
		if not await _frame(): receiver.free(); return false
		var packet: Dictionary=session._snapshot() # Original message sequence only; no physics advancement.
		var wire: Dictionary=Codec.encode(packet)
		var decoded: Dictionary=Codec.decode(wire) if not wire.is_empty() else {}
		var view: Dictionary=decoded.get("ambient",{})
		var admitted: bool=not decoded.is_empty() and not view.is_empty() and receiver.can_receive(view,context.received_session,"F2")
		stable=stable and _actor_state()==before and view==view_before and admitted
		if admitted: accepted+=1
		source_rows.append({"physics_frame":Engine.get_physics_frames(),"packet_sequence":packet.get("sequence"),"ambient_epoch":view.get("epoch"),"ambient_serial":view.get("serial"),"paused":decoded.get("paused"),"can_receive":admitted})
		stable=stable and decoded.get("paused")==true
	# Same-rank contradiction and old-visit negatives call only the real pure gate.
	var bad: Dictionary=view_before.duplicate(true)
	bad.actor.recoil=.01 if float(bad.actor.recoil)==0.0 else 0.0
	var rejects_conflict: bool=view_script.valid(bad) and not receiver.can_receive(bad,context.received_session,"F2")
	context.region_id="I1" # Explicit logical prior-region fixture, not a second actual World/Guest.
	receiver._required_epoch=1
	var rejects_old_visit: bool=not receiver.can_receive(view_before,context.received_session,"F2")
	contract_checks.append({"label":label,"real_source_rank":[view_before.epoch,view_before.serial],"duplicate_source_views_accepted":accepted,"same_rank_conflict_rejected":rejects_conflict,"prior_region_old_epoch_rejected_before_bind":rejects_old_visit,"scope":"Production can_receive on a standalone read-only logical Guest context/high-watermark seeded from the real source. No bind/receive/GuestActor/ENet or world mutation; I1 is a bookkeeping fixture only."})
	receiver.free()
	var paused: Dictionary=_actor_state()
	pause_cycles.append({"label":label,"before":before,"after_12_real_frames":paused,"sealed_before":view_before,"source_snapshots":source_rows,"require_warning":require_warning,"require_nonempty_bolt":require_bolt})
	var ok: bool=_check(stable and accepted==12 and rejects_conflict and rejects_old_visit,"original common pause freezes real Actor/native/age/Brain/warning/projectiles and all duplicate source views remain admissible: "+label,pause_cycles.back())
	session.network.send_action("propose",{"kind":"pause","payload":{}})
	return _check(ok and not session.simulation_paused and session.consensus.current_proposal().is_empty(),"original Consensus resumes without a manual clock or pose write: "+label,_status())

func _select_target() -> bool:
	for unused in session.entities.size()+2:
		if str(session.locks.get(1,""))==ID: return true
		var key:=InputEventKey.new(); key.pressed=true; key.physical_keycode=KEY_TAB; key.keycode=KEY_TAB
		session._unhandled_input(key)
		if not await _frame(): return false
	return _check(false,"ordinary Tab locks the original live entity",_status())

func _damage_chain(initial_hp: float,initial_serial: int) -> bool:
	var hp: float=initial_hp
	var serial: int=initial_serial
	var hits:=0
	var killed:=0
	for event: Dictionary in session.ambient_patrol.events:
		if event.kind!="hit" or event.detail.get("target")!=ID: continue
		var receipt: Dictionary=event.detail.receipt
		if int(receipt.serial)!=serial+1 or float(receipt.health_before)!=hp or float(receipt.raw_damage)!=9.0 or float(receipt.damage)<=0.0 or float(receipt.health)!=hp-float(receipt.damage) or receipt.weapon_type!="pulse": return false
		hp=float(receipt.health); serial=int(receipt.serial); hits+=1
		if receipt.killed: killed+=1
	return hp==0.0 and hits>0 and killed==1 and serial==int(_scout().damage_state.serial) and _event_count("disabled")==1

func _actor_state() -> Dictionary:
	if not is_instance_valid(_scout()): return {}
	var scout=_scout()
	var bolts: Array=[]
	for row: Dictionary in session.ambient_patrol._bolts:
		bolts.append({"id":row.get("id"),"position":row.position,"remaining":row.remaining,"visual_pose":row.visual.global_transform,"direction":row.direction,"warning_id":row.warning_id})
	return {"rid":scout.get_rid(),"pose":scout.global_transform,"native_pose":PhysicsServer3D.body_get_state(scout.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM),"velocity":scout.velocity,"age":scout.age,"brain_time":scout.brain.time_s,"telegraph":scout.telegraph,"cooldown":scout.cooldown,"hp":scout.hp,"armor":scout.damage_state.armor,"damage_serial":scout.damage_state.serial,"dying":scout.dying,"layer":scout.collision_layer,"mask":scout.collision_mask,"bolts":bolts}

func _hull_clear(at: Vector3) -> bool:
	if not at.is_finite() or absf(at.x)>39 or absf(at.z)>39 or at.y<1 or at.y>26: return false
	var found:=false
	for child: Node in _body().get_children():
		if not child is CollisionShape3D or child.disabled: continue
		found=true
		var query:=PhysicsShapeQueryParameters3D.new()
		query.shape=child.shape; query.margin=.08
		query.transform=Transform3D(_body().global_basis,at)*child.transform
		query.collision_mask=MASK; query.exclude=[_body().get_rid()]
		if not session.world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): return false
	return found

func _ray_from(at: Vector3) -> Dictionary:
	return session.world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at,_scout().global_position,MASK,[_body().get_rid()]))

func _ray() -> Dictionary: return _ray_from(_body().global_position)
func _ray_detail() -> Dictionary:
	var hit: Dictionary=_ray()
	return {"from":_body().global_position,"target":_scout().global_position,"hit_rid":str(hit.get("rid")),"first_collider":str(hit.collider.get_path()) if hit.has("collider") else "","first_entity":str(hit.collider.get_meta("entity_id","")) if hit.has("collider") else ""}
func _pilot_half() -> Vector3:
	return Vector3.ONE*Vector3(float(_body().stats.width_m),float(_body().stats.height_m),float(_body().stats.length_m)).length()*.5
func _body() -> FlightBodyV2: return session.players[1]
func _scout(): return session.ambient_patrol.scout if is_instance_valid(session) and session.get("ambient_patrol")!=null else null
func _event_count(kind: String) -> int:
	var count:=0
	for event: Dictionary in session.ambient_patrol.events:
		if event.kind==kind: count+=1
	return count
func _progress() -> Dictionary:
	var saved: Dictionary=session.store.snapshot()
	return {"personal":saved.personal,"choices":saved.world.choices,"completed_objectives":saved.world.completed_objectives,"story_completed":session.story.state.get("completed",[]).duplicate(true),"story_receipts":session.story.state.get("receipts",{}).duplicate(true),"encounter":saved.encounter}
func _healthy() -> bool:
	return not stopping and is_instance_valid(session) and session.active and session.players.has(1) and is_instance_valid(_scout()) and _body().enabled and _body().health>0 and session.ambient_patrol.error.is_empty() and logger.errors.is_empty()
func _elapsed() -> float: return float(Time.get_ticks_usec()-began_usec)/1000000.0
func _status() -> Dictionary:
	if not is_instance_valid(session): return {"session":"not_installed"}
	var result: Dictionary={"phase":phase,"region":session.region_id,"active":session.active,"paused":session.simulation_paused,"profile_ready":session.profile_ready,"message":session.interface.message.text if is_instance_valid(session.interface) else "","last_commit":session.last_commit_result,"proposal":session.consensus.current_proposal(),"generation":session.store.snapshot().generation if session.store!=null else -1}
	if is_instance_valid(_scout()): result["actor"]=_actor_state(); result["patrol_error"]=session.ambient_patrol.error
	if session.players.has(1): result["player"]={"position":_body().global_position,"health":_body().health,"enabled":_body().enabled,"locked":session.locks.get(1,""),"shots":session.stats.shots,"command_active":_body().command.get("active")}
	if is_instance_valid(session.interface): result["UI"]={"radio":session.interface.radio.visible,"menu":session.interface.menu.visible,"choice":session.interface.chapter_choice.visible,"vote":session.interface.vote.visible,"travel":session.interface.travel.visible}
	return result
func _check(ok: bool,label: String,actual: Variant=null) -> bool:
	checks.append({"passed":ok,"label":label,"actual":_plain(actual)})
	return ok
func _supply_input() -> void:
	if is_instance_valid(session) and is_instance_valid(session.inputs): session.inputs.test_frame={"axes":{},"held":["brake","fire"] if wanted_fire else ["brake"],"edges":[]}
func _frame() -> bool:
	_supply_input()
	await physics_frame
	await process_frame
	if stopping: return false
	if not _healthy(): _check(false,"actual MAIN remains healthy without forced HP or native error recovery",_status()); _stop("runtime_or_actor_failure"); return false
	return true

func _wall_watchdog() -> void:
	var deadline: int=began_usec+int(MAX_WALL_S*1000000.0)
	while not stopping and Time.get_ticks_usec()<deadline: await process_frame
	if not stopping: _check(false,"bounded85-second source native observation",_status()); _stop("bounded_incomplete")

func _stop(reason: String) -> void:
	if stopping: return
	stopping=true; wanted_fire=false; _supply_input()
	var failures: Array=checks.filter(func(row: Dictionary): return not row.passed)
	var complete: bool=reason=="native_patrol_segment_completed" and failures.is_empty() and logger.errors.is_empty()
	report_cache=_plain({"complete":complete,"reason":reason,"profile":profile,"scope":"Source MAIN single-player native patrol only. Fresh private QA F2 start-location and one explicitly collision-checked PLAYER initial observation pose, then ordinary continuous Pilot, Tab and held pulse. No prior Director/Story/discovery/Boss/HP/time/environment/AI fixture, manual simulation or real Guest/ENet. Logical Guest contract contexts are separately labelled and never bind/apply an actor. Warning-boundary and nonempty-bolt pause cases both use original Consensus; complete source view is immutable per rank. Original save/fresh reader and original Session._quit/audio drain, not a forced exit. No natural-campaign, graphics, listening, performance, human comfort or two-PC claim.","checks":checks,"failures":failures,"engine_errors":logger.errors,"fixtures":fixtures,"observations":observations,"pause_cycles":pause_cycles,"contract_checks":contract_checks,"events":session.ambient_patrol.events.duplicate(true) if is_instance_valid(session) and session.get("ambient_patrol")!=null else [],"physics_samples":physics_samples,"flown_distance_m_after_fixture":flown_distance,"max_frame_motion_after_fixture_m":max_frame_motion,"seconds":_elapsed(),"status":_status(),"native_exit":{"requested":true,"through":"session._quit","observed_scene_exit":false,"watchdog_failed":false}})
	_flush()
	if not is_instance_valid(session): quit(1); return # No MAIN exists to preserve or shut down.
	native_exit_requested=true
	session.tree_exiting.connect(_observed_native_exit,CONNECT_ONE_SHOT)
	_exit_watchdog.call_deferred()
	session._quit() # Original SaveGate then audio terminal drain; no tree.quit/OS.kill fallback.

func _exit_watchdog() -> void:
	var deadline: int=Time.get_ticks_usec()+8000000
	while native_exit_requested and Time.get_ticks_usec()<deadline: await process_frame
	if not native_exit_requested: return
	report_cache.complete=false
	report_cache.reason="original_exit_gate_incomplete"
	report_cache.native_exit.watchdog_failed=true
	report_cache.failures.append({"passed":false,"label":"original quit stayed pending/refused; no Store bypass or process kill","actual":_plain(_status())})
	_flush()
	print("F2_PATROL_NATIVE_EXIT_INCOMPLETE "+JSON.stringify(report_cache.native_exit))

func _observed_native_exit() -> void:
	if not native_exit_requested: return
	native_exit_requested=false
	report_cache.native_exit.observed_scene_exit=true
	report_cache.native_exit.audio=_plain(session.last_audio_shutdown_result)
	report_cache.native_exit.last_commit=_plain(session.last_commit_result)
	report_cache.engine_errors=_plain(logger.errors)
	if not session.last_audio_shutdown_result.get("ready",false) or not logger.errors.is_empty(): report_cache.complete=false
	_flush()
	print("F2_PATROL_NATIVE_EXIT "+JSON.stringify(report_cache.native_exit))

func _flush() -> void:
	var file=FileAccess.open(output+"/result.json",FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report_cache,"\t"))
	else: push_error("F2 patrol native report write failed: "+output)
	print("F2_PATROL_NATIVE_RESULT "+JSON.stringify({"complete":report_cache.get("complete",false),"reason":report_cache.get("reason"),"failures":report_cache.get("failures"),"engine_errors":report_cache.get("engine_errors")}))

static func _plain(value: Variant) -> Variant:
	if value is Vector3: return [value.x,value.y,value.z]
	if value is Basis: return [_plain(value.x),_plain(value.y),_plain(value.z)]
	if value is Transform3D: return {"basis":_plain(value.basis),"origin":_plain(value.origin)}
	if value is Array:
		var rows: Array=[]
		for item: Variant in value: rows.append(_plain(item))
		return rows
	if value is Dictionary:
		var result: Dictionary={}
		for key: Variant in value: result[str(key)]=_plain(value[key])
		return result
	if value is Object or value is RID: return str(value)
	return value
