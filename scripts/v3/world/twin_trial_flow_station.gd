class_name TwinTrialFlowStation
extends Node3D
## Five-port low-pressure trial bench; requires a real same-world isolation Link.
## Four separate routing seats, two return intakes and one outlet check shutter.
## Pipe bores, tank penetrations and valves are actual render/collision geometry.
## No save IO, RPC, objective flags, rewards, or automatic process callbacks.
const Runtime = preload("res://scripts/v3/environment/twin_trial_flow_runtime.gd")
const Axis = preload("res://scripts/v3/environment/twin_guided_axis.gd")
const FlightBody = preload("res://scripts/v2/flight_body.gd")
const IsolationLink = preload("res://scripts/v3/world/twin_trial_isolation_link.gd")
const PATH := "res://data/v3/terrain/i2_trial_flow_layout.json"
const SELECTOR := "I2:trial_selector"
const RELAY := "I2:trial_relay"
const CONTROLLER := "I2:trial_controller"
const RETURN_SWITCH := "I2:trial_return_switch"
const SAVE_KEYS := ["version","layout_sha256","serial","axis","runtime","return_requested","return_valves","blocked"]
const LAYOUT_KEYS := ["version","id","stage","origin","bounds","external_bounds","connection","axis","motor_speed_mps","tanks","solids","pipes","selector_parts","targets","observation","service_ports","valves","ports"]
const VALVE_IDS := ["SourceA","SourceB","ReceiveA","ReceiveB","ReturnA","ReturnB","Check"]
const ROUTES := {"Supply":["S","Split"],"SourceA":["Split","EA"],"SourceB":["Split","EB"],"ReceiveA":["EA","RA"],"ReceiveB":["EB","RB"],"ExternalA":["EA","PortA"],"ExternalB":["EB","PortB"],"ReturnA":["DrainA","Pump"],"ReturnB":["DrainB","Pump"],"Check":["Pump","FillS"]}
const MASK := 0xFFFFFFFF
const MARGIN := 0.001
# Repeated pipe walls and gauge ticks must not allocate fresh GPU buffers for
# every instance (or every prepared region). Exact authored dimensions remain
# on the BoxMesh, so the physical/render geometry checks stay unchanged.
static var _shared_box_meshes: Dictionary = {}
static var _shared_materials: Dictionary = {}
var configured := false
var authority := true
var fixed_bodies: Dictionary = {}
var target_bodies: Dictionary = {}
var selector_bodies: Dictionary = {}
var float_bodies: Dictionary = {}
var window_bodies: Dictionary = {}
var water_visuals: Dictionary = {}
var valve_bodies: Dictionary = {}
var _link_ref: WeakRef
var _link_geometry: Dictionary = {}
var _fixed_rest: Dictionary = {}
var _pipe_segments: Dictionary = {}
var _layout: Dictionary = {}
var _state: Dictionary = {}
var _axis = Axis.new()
var _runtime = Runtime.new()
var _paused := false
var _pinned := false
var _require_control_release := false
var qa_cpu_owner: WeakRef

func _qa_cpu_begin() -> int:
	return Time.get_ticks_usec() if qa_cpu_owner!=null else 0

func _qa_cpu_end(label: String, began: int) -> void:
	if began==0 or qa_cpu_owner==null: return
	var observer=qa_cpu_owner.get_ref()
	if is_instance_valid(observer): observer._qa_cpu_end("trial."+label,began)

func load_layout(saved: Dictionary = {}, is_authority: bool = true) -> Dictionary:
	if not FileAccess.file_exists(PATH): return _r(false,"layout_missing")
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not data is Dictionary: return _r(false,"layout_json")
	return configure(data,saved,is_authority)

func configure(data: Dictionary, saved: Dictionary = {}, is_authority: bool = true) -> Dictionary:
	if configured or is_inside_tree(): return _r(false,"configure_before_tree_once")
	var checked := _validate_layout(data)
	if not checked.ok: return checked
	var axis = Axis.new()
	checked=axis.configure(data.axis)
	if not checked.ok: return checked
	var neutral: Dictionary = axis.snapshot()
	neutral.position_m=float(data.axis.travel_m)*0.5
	axis.restore(neutral)
	var runtime = Runtime.new()
	checked=runtime.load_definition()
	if not checked.ok: return checked
	var digest := JSON.stringify(data,"",true,true).sha256_text()
	var next := {"version":2,"layout_sha256":digest,"serial":0,"axis":axis.snapshot(),"runtime":runtime.snapshot(),"return_requested":false,"return_valves":{"a":0.0,"b":0.0,"check":0.0},"blocked":false}
	if not saved.is_empty():
		checked=_check_snapshot(saved,digest,axis,runtime)
		if not checked.ok: return checked
		axis.restore(saved.axis,is_authority)
		if is_authority: axis.set_active_peers([])
		runtime.restore(saved.runtime)
		next=saved.duplicate(true)
		next.axis=axis.snapshot()
		if is_authority: next.return_requested=false
	_layout=data.duplicate(true)
	_axis=axis
	_runtime=runtime
	_state=next
	authority=is_authority
	_require_control_release=is_authority and not saved.is_empty()
	position=_v(data.origin)
	_build_geometry()
	configured=true
	set_meta("stage","connected_low_trial_candidate")
	set_meta("cabinet_connected",false)
	set_process(false)
	set_physics_process(false)
	_sync_poses()
	return _r(true,"configured")

func _ready() -> void:
	if configured: _sync_poses()

func layout() -> Dictionary:
	return _layout.duplicate(true)

func snapshot() -> Dictionary:
	return _state.duplicate(true)

func status() -> Dictionary:
	if not configured: return {}
	var result: Dictionary = _runtime.status()
	var connection := connection_status()
	result.stage="connected_low_trial_candidate"
	result.cabinet_connected=connection.ok
	result.trial_ready=connection.get("trial_ready",false)
	result.connection_code=connection.code
	result.selector_position=_selector_value(_state.axis)
	result.blocked=_state.blocked
	result.return_requested=_state.return_requested
	result.valves=_valve_values(float(_state.axis.position_m),_state.return_valves)
	return result

func attach_link(value: Variant) -> Dictionary:
	if not configured or not is_inside_tree(): return _r(false,"world_required")
	if not value is IsolationLink or not is_instance_valid(value) or not value.configured or not value.is_inside_tree(): return _r(false,"real_link_required")
	if value.get_world_3d()!=get_world_3d() or value.authority!=authority: return _r(false,"link_world_or_authority")
	if not value.global_transform.is_equal_approx(Transform3D(Basis.IDENTITY,IsolationLink.ORIGIN)): return _r(false,"link_transform")
	var previous: WeakRef=_link_ref
	var previous_geometry: Dictionary=_link_geometry
	_link_ref=weakref(value)
	_link_geometry=value.layout()
	for spec in _link_geometry.fixed:
		spec["expected_pose"]=Transform3D(Basis.IDENTITY,_v(spec.center))
		spec["expected_size"]=_v(spec.size)
	var checked:=connection_status()
	if not checked.ok:
		_link_ref=previous
		_link_geometry=previous_geometry
	return checked

func connection_status() -> Dictionary:
	if not configured or not is_inside_tree() or _link_ref==null: return _r(false,"link_required")
	var link: Variant=_link_ref.get_ref()
	if not is_instance_valid(link) or not link is IsolationLink or not link.is_inside_tree(): return _r(false,"link_missing")
	if link.get_world_3d()!=get_world_3d() or link.authority!=authority or not link.global_transform.is_equal_approx(Transform3D(Basis.IDENTITY,IsolationLink.ORIGIN)): return _r(false,"link_world_or_authority")
	# Authored expected geometry is immutable for this attached Link. Keep all
	# actual body/shape/pose/socket checks below live on every invocation.
	var data: Dictionary=_link_geometry
	for spec in data.fixed:
		if not link.fixed_bodies.has(spec.id) or not _body_matches_pose(link.fixed_bodies[spec.id],spec.expected_pose,spec.expected_size): return _r(false,"link_geometry_changed")
	var link_state: Dictionary=link.snapshot()
	var position_m: float=float(link_state.axis.position_m)
	for spec in data.moving:
		if not link.moving_bodies.has(spec.id): return _r(false,"link_leaf_missing")
		var body: StaticBody3D=link.moving_bodies[spec.id]
		var expected: Vector3=IsolationLink._part_position(spec,position_m)
		if not _body_matches(body,expected,_v(spec.size)): return _r(false,"link_leaf_shape_or_pose")
	# Every fixed/moving body's actual pose, collider and visual just passed
	# above. No await, callbacks, adoption or pose write occurs before this
	# current-state projection; public Link.status() retains its own full check.
	var live: Dictionary=link._status_from_verified_pose(true)
	if not live.pose_valid: return _r(false,"link_pose_changed")
	# Both imported socket coordinates are checked against actual same-world
	# geometry, not a cached connection flag or a network-only dictionary.
	for index in range(2):
		var endpoint:=to_global(_v(_layout.service_ports[index].position))
		var expected:=Vector3(15.55 if index==0 else 20.45,.15,-12.44)
		if endpoint.distance_to(expected)>.00001: return _r(false,"socket_mismatch")
	return {"ok":true,"code":"connected","trial_ready":bool(live.trial_ready),"link_serial":int(link_state.serial),"link_geometry_sha256":str(link_state.geometry_sha256)}

func flow_paths() -> Dictionary:
	if not configured or not is_inside_tree() or not _poses_match(): return _r(false,"geometry_unavailable")
	return _trace_paths(_runtime,float(_state.axis.position_m),_state.return_valves)

func get_water_node(id: String) -> Dictionary:
	return _runtime.get_node(id) if configured else {}

func validate_snapshot(raw: Variant) -> Dictionary:
	if not configured: return _r(false,"not_configured")
	return _check_snapshot(raw,str(_state.layout_sha256),_axis,_runtime)

func apply_snapshot(raw: Variant) -> Dictionary:
	var checked := validate_snapshot(raw)
	if not checked.ok: return checked
	var axis = _axis.copy_for_trial()
	axis.restore(raw.axis,authority)
	if authority: axis.set_active_peers([])
	var runtime = _copy_runtime()
	if runtime==null: return _r(false,"runtime_candidate_invalid")
	checked=runtime.restore(raw.runtime)
	if not checked.ok: return checked
	var next: Dictionary = raw.duplicate(true)
	next.axis=axis.snapshot()
	if authority: next.return_requested=false
	_axis=axis
	_runtime=runtime
	_state=next
	_pinned=false
	_require_control_release=authority
	_sync_poses()
	return _r(true,"snapshot_applied")

func set_simulation_paused(value: bool) -> Dictionary:
	if not configured: return _r(false,"not_configured")
	if authority and int(_state.serial)>=Axis.MAX_SERIAL: return _r(false,"serial_limit")
	_paused=value
	# Pause never integrates motion or wall-clock water. Clear unconsumed input
	# so a pause/resume cannot release a previously queued impulse.
	if value and authority:
		var stopped: Dictionary = _axis.stop()
		_publish_axis()
		return {"ok":true,"code":"paused","cancelled":stopped.cancelled}
	return _r(true,"paused" if value else "resumed")

func synchronize_impulse_roster(players: Dictionary) -> Dictionary:
	var checked := _host_guard()
	if not checked.ok: return checked
	checked=_validate_players(players)
	if not checked.ok: return checked
	var result: Dictionary = _axis.set_active_peers(_active_peers(players))
	_publish_axis()
	return result

func reset_impulse_peer(peer: int) -> Dictionary:
	var checked := _host_guard()
	if not checked.ok: return checked
	var result: Dictionary = _axis.reset_peer(peer)
	if result.ok: _publish_axis()
	return result

func can_accept_impulse(id: String, impulse: Vector3, peer: int, action_serial: int) -> Dictionary:
	var checked := _host_guard()
	if not checked.ok: return checked
	if id!=SELECTOR: return _r(false,"unknown_impulse_target")
	if _paused or _pinned or _state.return_requested or _return_active(_state.return_valves): return _r(false,"mechanism_stopped")
	if not _poses_match(): return _r(false,"unauthorized_pose")
	return _axis.can_accept(impulse,peer,action_serial)

func apply_authorized_impulse(id: String, impulse: Vector3, peer: int, action_serial: int) -> Dictionary:
	var checked := can_accept_impulse(id,impulse,peer,action_serial)
	if not checked.ok: return checked
	var result: Dictionary = _axis.apply_impulse(impulse,peer,action_serial)
	_publish_axis()
	return result

func request_return(peer: int, body: Variant) -> Dictionary:
	var checked := _observer_guard(peer,body)
	if not checked.ok: return checked
	if _paused: return _r(false,"paused")
	var target: StaticBody3D = target_bodies[RETURN_SWITCH]
	if body.global_position.distance_to(target.global_position)>4.5: return _r(false,"too_far")
	var hit := _ray(body.global_position,target.global_position,[body.get_rid()])
	if hit.is_empty() or hit.get("rid")!=target.get_rid(): return _r(false,"switch_blocked")
	var next := snapshot()
	next.return_requested=true
	_adopt(next)
	return _r(true,"return_requested")

func fixed_update(delta: float, entities: Dictionary, players: Dictionary, is_authority: bool = true) -> Dictionary:
	var checked := _host_guard()
	if not checked.ok: return checked
	if not is_authority: return _r(false,"not_authority")
	if not _number(delta,0.0,0.25): return _r(false,"delta_range")
	if _paused or delta==0.0: return _r(true,"paused")
	var cpu_began:=_qa_cpu_begin()
	if not _poses_match(): return _r(false,"unauthorized_pose")
	_qa_cpu_end("poses",cpu_began)
	cpu_began=_qa_cpu_begin()
	checked=_inputs(entities,players)
	if not checked.ok: return checked
	var control_release: bool=_require_control_release and float(checked.remaining)>0.0
	var remaining: float=0.0 if control_release else float(checked.remaining)
	var returning: bool=_state.return_requested
	var pulse: bool=remaining>0.0 and not returning
	var axis=_axis.copy_for_trial()
	var roster: Dictionary=axis.set_active_peers(_active_peers(players))
	var cancelled: Array=roster.cancelled.duplicate(true)
	var start: float=float(_state.axis.position_m)
	var finish:=start
	var desired: Variant=_runtime.desired_selector_for_step()
	if returning or _return_active(_state.return_valves): desired=0.0
	var motor: bool=bool(checked.powered) and (returning or remaining>0.0 or _return_active(_state.return_valves)) and desired!=null
	if checked.pinned:
		cancelled.append_array(axis.stop().cancelled)
	elif motor:
		cancelled.append_array(axis.stop().cancelled)
		var goal: float=(float(desired)+1.0)*float(_layout.axis.travel_m)*.5
		finish=move_toward(start,goal,float(_layout.motor_speed_mps)*minf(delta,remaining if pulse else delta))
		var pose: Dictionary=axis.snapshot()
		pose.position_m=finish
		pose.velocity_mps=0.0
		axis.restore(pose,false)
	else:
		var proposed: Dictionary=axis.preview(delta)
		if not proposed.ok: return proposed
		finish=float(proposed.position_m)
		axis.advance(delta)
		var neutral: float=float(_layout.axis.travel_m)*.5
		if (start<neutral and finish>=neutral) or (start>neutral and finish<=neutral):
			var pose: Dictionary=axis.snapshot()
			pose.position_m=neutral
			pose.velocity_mps=0.0
			axis.restore(pose,false)
			finish=neutral
	# All 7 leaf poses are proposed, not applied. Return intake change is
	# CLOSE current + check -> OPEN next intake -> OPEN check, in that order.
	var returns:=_advance_returns(delta,finish,returning and bool(checked.powered) and finish==start,_runtime)
	var leaves_before:=_valve_values(start,_state.return_valves)
	var leaves_after:=_valve_values(finish,returns)
	_qa_cpu_end("inputs_axis",cpu_began)
	cpu_began=_qa_cpu_begin()
	var axis_blocked:=not _selector_clear(start,finish)
	var valve_blocked:=not _valves_clear(leaves_before,leaves_after)
	_qa_cpu_end("sweeps",cpu_began)
	cpu_began=_qa_cpu_begin()
	var runtime=_copy_runtime()
	if runtime==null: return _r(false,"runtime_candidate_invalid")
	_qa_cpu_end("copy_runtime",cpu_began)
	var flow: Dictionary={"ok":true,"code":"advanced","moved_ml":0,"new_samples":[]}
	cpu_began=_qa_cpu_begin()
	var connection:=connection_status()
	_qa_cpu_end("connection",cpu_began)
	var motionless: bool=finish==start and leaves_before==leaves_after and absf(float(axis.snapshot().velocity_mps))<.000001
	var floats_clear:=true
	if not axis_blocked and not valve_blocked and connection.ok:
		# Split only at EXISTING hydraulic boundaries. Never let a call that
		# empties A credit B while the physical A intake is still selected.
		var left:=delta
		var elapsed:=0.0
		var loops:=0
		while left>.000000001 and loops<8:
			var part:=minf(left,(100000.0-float(runtime.pending_usec_for_step()))/1000000.0)
			cpu_began=_qa_cpu_begin()
			# The Link has not advanced or changed geometry since this local
			# connection check. Keep each actual bore ray live in every substep.
			var paths:=_trace_paths_connected(runtime,start,_state.return_valves,connection)
			_qa_cpu_end("trace",cpu_began)
			var valid: bool=bool(paths.return_clear) if returning else (bool(paths.forward_clear) or bool(paths.neutral_clear))
			var facts: Dictionary={"selector_position":_selector_value(axis.snapshot()),"sweep_clear":motionless and valid,
				"powered":bool(checked.powered),"takeover_remaining":maxf(0.0,remaining-elapsed),"pulse_requested":pulse,"return_requested":returning}
			cpu_began=_qa_cpu_begin()
			var step: Dictionary=runtime.step(part,facts,true,false)
			_qa_cpu_end("runtime_step",cpu_began)
			if not step.ok: return step
			flow.moved_ml+=int(step.moved_ml)
			flow.new_samples.append_array(step.new_samples)
			cpu_began=_qa_cpu_begin()
			var clear_floats:=_floats_clear(runtime,leaves_after,finish)
			_qa_cpu_end("floats",cpu_began)
			if not clear_floats:
				floats_clear=false
				break
			left-=part
			elapsed+=part
			loops+=1
		if left>.000000001 and floats_clear: return _r(false,"hydraulic_boundary_limit")
	elif not connection.ok:
		flow.code="disconnected"
	var blocked: bool=axis_blocked or valve_blocked or not floats_clear
	if blocked:
		# A swept leaf OR float obstruction rejects water, tick credit and all
		# proposed poses together. Only accepted input velocity is cancelled.
		axis=_axis.copy_for_trial()
		axis.set_active_peers(_active_peers(players))
		cancelled.append_array(axis.stop().cancelled)
		returns=_state.return_valves.duplicate(true)
		runtime=_copy_runtime()
		if runtime==null: return _r(false,"runtime_candidate_invalid")
		flow={"ok":true,"code":"physical_blocked","moved_ml":0,"new_samples":[]}
	var next:=snapshot()
	next.axis=axis.snapshot()
	next.return_valves=returns
	next.runtime=runtime.snapshot()
	next.blocked=blocked
	if returning and runtime.return_complete_for_step(): next.return_requested=false
	cpu_began=_qa_cpu_begin()
	checked=_check_snapshot(next,str(_state.layout_sha256),axis,runtime)
	_qa_cpu_end("validation",cpu_began)
	if not checked.ok: return checked
	_axis=axis
	_runtime=runtime
	_pinned=bool(entities[SELECTOR].pinned) and float(entities[SELECTOR].field_remaining)>0.0
	if float(entities[CONTROLLER].takeover_remaining)==0.0 or not entities[CONTROLLER].controlled: _require_control_release=false
	_adopt(next)
	cpu_began=_qa_cpu_begin()
	_sync_poses()
	_qa_cpu_end("sync",cpu_began)
	return {"ok":true,"code":"blocked" if blocked else "advanced","axis_blocked":axis_blocked,"valve_blocked":valve_blocked,"float_blocked":not floats_clear,"flow":flow,"cancelled":cancelled,"cabinet_connected":connection.ok}

func target_definitions() -> Array:
	if not configured: return []
	return [
		{"id":SELECTOR,"name":"接柜试流三位滑芯","position":entity_position(SELECTOR),"tags":["movable","fieldable","mechanical"],"pinned":false,"pinned_by":"","field_remaining":0.0,"revision":0},
		{"id":RELAY,"name":"试流台供能器","position":entity_position(RELAY),"tags":["conductive","electrical"],"charge":0.0,"charge_capacity":100.0,"power_threshold":20.0,"powered":false,"revision":0},
		{"id":CONTROLLER,"name":"试流脉冲控制器","position":entity_position(CONTROLLER),"tags":["mechanical","hackable"],"controlled":false,"owner":"","takeover_remaining":0.0,"revision":0}]

func entity_position(id: String) -> Variant:
	if not configured or not target_bodies.has(id): return null
	var body: Node3D = target_bodies[id]
	return body.global_position if is_inside_tree() else transform*body.position

func observe_gauge(peer: int, body: Variant, receiver_id: String) -> Dictionary:
	var checked := _observer_guard(peer,body)
	if not checked.ok: return checked
	if receiver_id not in [Runtime.RECEIVER_A,Runtime.RECEIVER_B]: return _r(false,"unknown_receiver")
	var spec := _tank(receiver_id)
	var center := _window_center(spec)
	var front := center+Vector3.BACK*float(spec.wall_m)*0.5
	var hits := 0
	var center_hit := false
	var sensor: Vector3 = body.global_position
	var window: StaticBody3D = window_bodies[receiver_id]
	for offset in [Vector2.ZERO,Vector2(-0.09,-0.15),Vector2(0.09,-0.15),Vector2(-0.09,0.15),Vector2(0.09,0.15)]:
		var point := to_global(front+Vector3(offset.x,offset.y,0))
		var sight := sensor-point
		if sight.length()<0.0001 or sight.length()>float(_layout.observation.max_distance_m): continue
		if sight.normalized().dot(Vector3.BACK)<float(_layout.observation.min_facing_dot): continue
		var hit := _ray(sensor,point-sight.normalized()*0.002,[body.get_rid()])
		if not hit.is_empty() and hit.get("rid")==window.get_rid():
			hits+=1
			if offset==Vector2.ZERO: center_hit=true
	if not center_hit or hits<int(_layout.observation.min_hits): return {"ok":false,"code":"window_not_visible","hits":hits,"center_hit":center_hit}
	var selector: String = "B" if receiver_id==Runtime.RECEIVER_A else "A"
	var sample: Dictionary = _runtime.status().samples[selector]
	return {"ok":true,"code":"local_gauge_observed","scope":"connected_low_trial_gauge_only","cabinet_connected":connection_status().ok,
		"receiver_id":receiver_id,"mechanism_serial":int(_state.serial),"level_m":float(_runtime.get_node(receiver_id).level_m),
		"volume_ml":int(_runtime.get_node(receiver_id).volume_ml),"float_world_position":float_bodies[receiver_id].global_position,
		"sample":sample.duplicate(true),"hits":hits,"center_hit":center_hit}

func _observer_guard(peer: int, body: Variant) -> Dictionary:
	var checked := _host_guard()
	if not checked.ok: return checked
	if not _poses_match(): return _r(false,"unauthorized_pose")
	checked=_validate_players({peer:body})
	if not checked.ok: return checked
	if not body.enabled or float(body.health)<=0.0: return _r(false,"body_inactive")
	for owner in body.get_shape_owners():
		if body.is_shape_owner_disabled(owner): continue
		for index in range(body.shape_owner_get_shape_count(owner)):
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape=body.shape_owner_get_shape(owner,index)
			query.transform=body.global_transform*body.shape_owner_get_transform(owner)
			query.exclude=[body.get_rid()]
			query.collision_mask=MASK
			query.margin=0.0
			if not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): return _r(false,"body_occupied")
	return _r(true,"observer_valid")

func _inputs(entities: Dictionary, players: Dictionary) -> Dictionary:
	var checked := _validate_players(players)
	if not checked.ok: return checked
	for id in [SELECTOR,RELAY,CONTROLLER]:
		if not entities.get(id) is Dictionary: return _r(false,"missing_entity")
	var selector: Dictionary = entities[SELECTOR]
	var relay: Dictionary = entities[RELAY]
	var control: Dictionary = entities[CONTROLLER]
	if not selector.get("pinned") is bool or not _number(selector.get("field_remaining"),0,8): return _r(false,"field_state")
	if not relay.get("powered") is bool: return _r(false,"power_state")
	if not control.get("controlled") is bool or not control.get("owner") is String or not _number(control.get("takeover_remaining"),0,8): return _r(false,"control_state")
	var owner_valid := false
	for peer in _active_peers(players):
		if str(peer)==control.owner: owner_valid=true
	return {"ok":true,"code":"valid","pinned":selector.pinned and float(selector.field_remaining)>0.0,
		"powered":relay.powered,"remaining":float(control.takeover_remaining) if control.controlled and owner_valid else 0.0}

func _validate_players(players: Dictionary) -> Dictionary:
	if players.size()>2: return _r(false,"player_limit")
	for peer in players:
		var body: Variant = players[peer]
		if not peer is int or peer<=0 or peer>2147483647 or not body is FlightBody or not is_instance_valid(body): return _r(false,"real_player_required")
		if not body.is_inside_tree() or body.get_world_3d()!=get_world_3d() or (body.collision_layer&2)==0 or not is_finite(float(body.health)): return _r(false,"player_world_or_health")
		var shapes := 0
		for owner in body.get_shape_owners():
			if not body.is_shape_owner_disabled(owner): shapes+=body.shape_owner_get_shape_count(owner)
		if shapes==0: return _r(false,"player_shape_required")
	return _r(true,"valid")

func _active_peers(players: Dictionary) -> Array:
	var peers: Array = []
	for peer in players:
		if players[peer].enabled and float(players[peer].health)>0.0: peers.append(peer)
	peers.sort()
	return peers

func _host_guard() -> Dictionary:
	if not configured or not is_inside_tree(): return _r(false,"world_required")
	if not authority: return _r(false,"not_authority")
	if not global_basis.is_equal_approx(Basis.IDENTITY) or not global_position.is_equal_approx(_v(_layout.origin)): return _r(false,"world_aligned_module_required")
	if int(_state.serial)>=Axis.MAX_SERIAL: return _r(false,"serial_limit")
	return _r(true,"valid")

func _copy_runtime():
	return _runtime.copy_for_trial()

func _publish_axis() -> void:
	var next := snapshot()
	next.axis=_axis.snapshot()
	_adopt(next)

func _adopt(next: Dictionary) -> void:
	if next==_state: return
	next.serial=int(_state.serial)+1
	_state=next

func _selector_value(raw: Dictionary) -> float:
	return 2.0*float(raw.position_m)/float(_layout.axis.travel_m)-1.0

func _moving_rids(include_floats: bool=true) -> Array[RID]:
	var result: Array[RID] = []
	var collections: Array=[selector_bodies,valve_bodies]
	if include_floats: collections.append(float_bodies)
	for collection in collections:
		for body in collection.values(): result.append(body.get_rid())
	return result

func _selector_clear(start: float, finish: float) -> bool:
	for spec in _layout.selector_parts:
		var a := _v(spec.center)+Vector3.RIGHT*(start-float(_layout.axis.travel_m)*0.5)
		var b := _v(spec.center)+Vector3.RIGHT*(finish-float(_layout.axis.travel_m)*0.5)
		if not _sweep_clear(_v(spec.size),a,b,_moving_rids(false)): return false
	return true

func _floats_clear(runtime,values: Dictionary,position_m: float) -> bool:
	for spec in _layout.tanks:
		var start:=_float_position(spec,_runtime)
		var finish:=_float_position(spec,runtime)
		var excluded: Array[RID]=[float_bodies[spec.id].get_rid()]
		if not _sweep_clear(_float_size(spec),start,finish,excluded): return false
		var swept_size:=_float_size(spec)+(finish-start).abs()
		var swept:=AABB((start+finish)*.5-swept_size*.5,swept_size).grow(MARGIN)
		for valve in _layout.valves:
			var point:=_v(valve.center)+_v(valve.travel)*float(values[valve.id])
			var size:=_v(valve.size)
			if swept.intersects(AABB(point-size*.5,size)): return false
		for part in _layout.selector_parts:
			var point:=_v(part.center)+Vector3.RIGHT*(position_m-.4)
			var size:=_v(part.size)
			if swept.intersects(AABB(point-size*.5,size)): return false
	return true

func _sweep_clear(size: Vector3, start: Vector3, finish: Vector3, excluded: Array[RID]) -> bool:
	var shape := BoxShape3D.new()
	shape.size=size+(finish-start).abs()
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape=shape
	query.transform=global_transform*Transform3D(Basis.IDENTITY,(start+finish)*0.5)
	query.collision_mask=MASK
	query.exclude=excluded
	query.margin=MARGIN
	return get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _poses_match() -> bool:
	for id in _fixed_rest:
		if not fixed_bodies.has(id) or not _body_matches_pose(fixed_bodies[id],_fixed_rest[id].pose,_fixed_rest[id].size): return false
	var values:=_valve_values(float(_state.axis.position_m),_state.return_valves)
	for spec in _layout.valves:
		if not _body_matches(valve_bodies[spec.id],_v(spec.center)+_v(spec.travel)*float(values[spec.id]),_v(spec.size)): return false
	for spec in _layout.selector_parts:
		var expected := _v(spec.center)+Vector3.RIGHT*(float(_state.axis.position_m)-float(_layout.axis.travel_m)*0.5)
		if not _body_matches(selector_bodies[spec.id],expected,_v(spec.size)): return false
	for spec in _layout.tanks:
		if not _body_matches(float_bodies[spec.id],_float_position(spec,_runtime),_float_size(spec)): return false
	return true

func _sync_poses() -> void:
	var values:=_valve_values(float(_state.axis.position_m),_state.return_valves)
	for spec in _layout.valves: _set_pose(valve_bodies[spec.id],_v(spec.center)+_v(spec.travel)*float(values[spec.id]))
	for spec in _layout.selector_parts:
		_set_pose(selector_bodies[spec.id],_v(spec.center)+Vector3.RIGHT*(float(_state.axis.position_m)-float(_layout.axis.travel_m)*0.5))
	for spec in _layout.tanks:
		_set_pose(float_bodies[spec.id],_float_position(spec,_runtime))
		var level: float = float(_runtime.get_node(spec.id).level_m)
		var depth := maxf(0.0,level-float(spec.bottom_y))
		var water: MeshInstance3D = water_visuals[spec.id]
		water.visible=depth>0.0
		water.scale.y=maxf(depth,0.0001)
		water.position=Vector3(float(spec.center_xz[0]),float(spec.bottom_y)+depth*0.5,float(spec.center_xz[1]))

func _set_pose(body: StaticBody3D, point: Vector3) -> void:
	# A stationary leaf needs no repeat native write. Check BOTH current Node
	# and native transforms exactly; a stale PhysicsServer pose is still fixed.
	if is_inside_tree() and body.position==point and PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)==body.global_transform: return
	body.position=point
	if is_inside_tree():
		body.force_update_transform()
		PhysicsServer3D.body_set_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,body.global_transform)

func _tank(id: String) -> Dictionary:
	for spec in _layout.tanks:
		if spec.id==id: return spec
	return {}

static func _float_size(spec: Dictionary) -> Vector3:
	return Vector3(float(spec.inner_size[0])-0.12,0.04,float(spec.inner_size[2])-0.12)

static func _float_position(spec: Dictionary, runtime) -> Vector3:
	return Vector3(float(spec.center_xz[0]),float(runtime.get_node(spec.id).level_m)+0.027,float(spec.center_xz[1]))

static func _window_center(spec: Dictionary) -> Vector3:
	return Vector3(float(spec.center_xz[0]),float(spec.bottom_y)+float(spec.inner_size[1])*0.5,float(spec.center_xz[1])+float(spec.inner_size[2])*0.5+float(spec.wall_m)*0.5)


func _build_geometry() -> void:
	for spec in _layout.solids: _fixed(spec.id,_v(spec.center),_v(spec.size),Color(spec.color))
	_build_channels()
	for spec in _layout.tanks: _build_tank(spec)
	for spec in _layout.selector_parts:
		var part:=_solid(spec.id,_v(spec.center),_v(spec.size),Color("c1a367"),8)
		part.set_meta("entity_id",SELECTOR)
		selector_bodies[spec.id]=part
	for spec in _layout.valves:
		var part:=_solid(spec.id,_v(spec.center),_v(spec.size),Color("d0af72"),8)
		part.set_meta("flow_seat",spec.id)
		valve_bodies[spec.id]=part
	target_bodies[SELECTOR]=selector_bodies.SelectorGrip
	for spec in _layout.targets:
		var target:=_solid(str(spec.id).replace(":","_"),_v(spec.center),_v(spec.size),Color(spec.color),8)
		target.set_meta("entity_id",spec.id)
		target_bodies[spec.id]=target
	for id in fixed_bodies:
		var body: StaticBody3D=fixed_bodies[id]
		_fixed_rest[id]={"center":body.position,"pose":Transform3D(Basis.IDENTITY,body.position),"size":body.get_child(0).shape.size}

func _fixed(id: String,point: Vector3,size: Vector3,color: Color) -> void:
	fixed_bodies[id]=_solid(id,point,size,color)

func _build_channels() -> void:
	var joints: Dictionary={}
	for pipe in _layout.pipes:
		var segments: Array=[]
		for i in range(pipe.points.size()-1):
			var a:=_v(pipe.points[i])
			var b:=_v(pipe.points[i+1])
			segments.append([a,b])
			for row in [[a,(b-a).normalized()],[b,(a-b).normalized()]]:
				var key:=_point_key(row[0])
				if not joints.has(key): joints[key]={"point":row[0],"faces":[]}
				if row[1] not in joints[key].faces: joints[key].faces.append(row[1])
		_pipe_segments[pipe.id]=segments
	var index:=0
	for joint in joints.values():
		if joint.faces.size()<2: continue
		for axis in range(3):
			for sign_value in [-1,1]:
				var direction:=Vector3.ZERO
				direction[axis]=sign_value
				if direction in joint.faces: continue
				var size:=Vector3.ONE*.07
				size[axis]=.015
				_fixed("Joint_"+str(index)+"_"+str(axis)+"_"+str(sign_value),joint.point+direction*.0275,size,Color("718c92"))
		index+=1
	for pipe in _layout.pipes:
		var part:=0
		for segment in _pipe_segments[pipe.id]:
			var a: Vector3=segment[0]
			var b: Vector3=segment[1]
			var direction: Vector3=(b-a).normalized()
			if joints[_point_key(a)].faces.size()>=2: a+=direction*.035
			if joints[_point_key(b)].faces.size()>=2: b-=direction*.035
			if (b-a).dot(direction)<.000001: continue
			var pieces: Array=[[a,b]]
			if pipe.valve!="":
				var valve:=_valve_spec(pipe.valve)
				var center:=_v(valve.center)
				if _on_segment(center,a,b): pieces=[[a,center-direction*.014],[center+direction*.014,b]]
			for pair in pieces:
				_tube(str(pipe.id)+"_"+str(part),pair[0],pair[1])
				part+=1

func _tube(id: String,a: Vector3,b: Vector3) -> void:
	var axis: int=(b-a).abs().max_axis_index()
	var other: Array=[]
	for i in range(3):
		if i!=axis: other.append(i)
	for index in range(2):
		for sign_value in [-1,1]:
			var size:=Vector3.ZERO
			size[axis]=absf(b[axis]-a[axis])
			size[other[index]]=.015
			size[other[1-index]]=.07 if index==0 else .04
			var center: Vector3=(a+b)*.5
			center[other[index]]+=sign_value*.0275
			_fixed(id+"_Wall"+str(index)+"_"+str(sign_value),center,size,Color("718c92"))

func _build_tank(spec: Dictionary) -> void:
	var x:=float(spec.center_xz[0])
	var z:=float(spec.center_xz[1])
	var y:=float(spec.bottom_y)
	var size:=_v(spec.inner_size)
	var t:=float(spec.wall_m)
	var prefix: String=str(spec.id).replace(":","_")
	# Real wall holes; the full float stroke stays inside the tanks.
	_wall_hole(prefix+"Bottom",Vector3(x,y-t*.5,z),Vector3(size.x+2*t,t,size.z+2*t),1,Vector3(x,y-t*.5,z))
	var inlet_y:=1.46 if spec.id==Runtime.SOURCE else .8
	var inlet_x:=.25 if spec.id==Runtime.SOURCE else x
	_wall_hole(prefix+"Back",Vector3(x,y+size.y*.5,z-(size.z+t)*.5),Vector3(size.x,size.y,t),2,Vector3(inlet_x,inlet_y,z-(size.z+t)*.5))
	for row in [["Left",Vector3(x-(size.x+t)*.5,y+size.y*.5,z),Vector3(t,size.y,size.z+2*t)],
		["Right",Vector3(x+(size.x+t)*.5,y+size.y*.5,z),Vector3(t,size.y,size.z+2*t)]]:
		_fixed(prefix+row[0],row[1],row[2],Color("657f85"))
	var window:=_solid(prefix+"GaugeWindow",_window_center(spec),Vector3(size.x,size.y,t),Color(.68,.83,.86,.19))
	window.set_meta("gauge_window",spec.id)
	window_bodies[spec.id]=window
	window.get_node("Visual").material_override.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	float_bodies[spec.id]=_solid(prefix+"Float",_float_position(spec,_runtime),_float_size(spec),Color("d9b265"),8)
	var water:=_mesh(prefix+"Water",Vector3(size.x-.004,1,size.z-.004),Color("518f9c"))
	water.set_meta("visual_only_water",true)
	add_child(water)
	water_visuals[spec.id]=water
	for index in range(11):
		var tick:=_mesh(prefix+"Tick"+str(index),Vector3(.06 if index%5 else .1,.008,.004),Color("d3ddd8"))
		tick.position=Vector3(x-size.x*.5+.065,y+size.y*float(index)/10.0,z+size.z*.5+t+.003)
		add_child(tick)

func _wall_hole(id: String,center: Vector3,size: Vector3,normal: int,hole: Vector3) -> void:
	var axes: Array=[]
	for i in range(3):
		if i!=normal: axes.append(i)
	var u: int=axes[0]
	var v: int=axes[1]
	var lo:=center-size*.5
	var hi:=center+size*.5
	var left: float=hole[u]-.035
	var right: float=hole[u]+.035
	var bottom: float=hole[v]-.035
	var top: float=hole[v]+.035
	var regions: Array=[[lo[u],left,lo[v],hi[v]],[right,hi[u],lo[v],hi[v]],[left,right,lo[v],bottom],[left,right,top,hi[v]]]
	for i in range(4):
		var area: Array=regions[i]
		var point:=center
		var dimensions:=size
		point[u]=(float(area[0])+float(area[1]))*.5
		point[v]=(float(area[2])+float(area[3]))*.5
		dimensions[u]=float(area[1])-float(area[0])
		dimensions[v]=float(area[3])-float(area[2])
		_fixed(id+str(i),point,dimensions,Color("657f85"))

func _solid(label: String, center: Vector3, size: Vector3, color: Color, layer: int = 1) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name=label
	body.position=center
	body.collision_layer=layer
	body.collision_mask=0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size=size
	collision.shape=shape
	body.add_child(collision)
	var visual := _mesh("Visual",size,color)
	body.add_child(visual)
	add_child(body)
	return body

static func _mesh(label: String, size: Vector3, color: Color) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.name=label
	if not _shared_box_meshes.has(size):
		var mesh := BoxMesh.new()
		mesh.size=size
		_shared_box_meshes[size]=mesh
	visual.mesh=_shared_box_meshes[size]
	if not _shared_materials.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color=color
		material.roughness=0.75
		if color.a<1.0: material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		_shared_materials[color]=material
	visual.material_override=_shared_materials[color]
	return visual

func _ray(start: Vector3, finish: Vector3, excluded: Array[RID]) -> Dictionary:
	return get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start,finish,MASK,excluded))


func _advance_returns(delta: float,position_m: float,enabled: bool,runtime) -> Dictionary:
	var old: Dictionary=_state.return_valves
	var next: Dictionary=old.duplicate(true)
	var target: String=""
	if enabled and absf(position_m-.4)<=.002:
		if int(runtime.get_node(Runtime.RECEIVER_A).volume_ml)>0: target="a"
		elif int(runtime.get_node(Runtime.RECEIVER_B).volume_ml)>0: target="b"
	var other: String="b" if target=="a" else "a"
	var amount:=delta*8.0
	if target=="" or float(old[other])>0.0:
		for key in next: next[key]=move_toward(float(old[key]),0.0,amount)
	elif float(old[target])<1.0:
		next[target]=move_toward(float(old[target]),1.0,amount)
		next.check=0.0
	else:
		next.check=move_toward(float(old.check),1.0,amount)
	return next

static func _return_active(raw: Dictionary) -> bool:
	return float(raw.a)>0.0 or float(raw.b)>0.0 or float(raw.check)>0.0

static func _valve_values(position_m: float,returns: Dictionary) -> Dictionary:
	var a:=1.0-clampf(position_m/.2,0.0,1.0)
	var b:=clampf((position_m-.6)/.2,0.0,1.0)
	return {"SourceA":a,"SourceB":b,"ReceiveA":b,"ReceiveB":a,"ReturnA":float(returns.a),"ReturnB":float(returns.b),"Check":float(returns.check)}

func _valves_clear(before: Dictionary,after: Dictionary) -> bool:
	for spec in _layout.valves:
		var start:=_v(spec.center)+_v(spec.travel)*float(before[spec.id])
		var finish:=_v(spec.center)+_v(spec.travel)*float(after[spec.id])
		if not _sweep_clear(_v(spec.size),start,finish,_moving_rids(false)): return false
	return true

func _valve_spec(id: String) -> Dictionary:
	for row in _layout.valves:
		if row.id==id: return row
	return {}

func _trace_paths(runtime,position_m: float,returns: Dictionary) -> Dictionary:
	return _trace_paths_connected(runtime,position_m,returns,connection_status())

func _trace_paths_connected(runtime,position_m: float,returns: Dictionary,connection: Dictionary) -> Dictionary:
	var values:=_valve_values(position_m,returns)
	var graph: Dictionary={}
	var active: Array=[]
	for pipe in _layout.pipes:
		if pipe.valve!="" and float(values[pipe.valve])<.995: continue
		if not _bore_clear(_pipe_segments[pipe.id]): continue
		_add_edge(graph,pipe.a,pipe.b,pipe.id=="Check")
		active.append(pipe.id)
	var cross: bool=bool(connection.get("trial_ready",false)) and _link_bore_clear()
	if cross: _add_edge(graph,"PortA","PortB",false)
	var reached:=_reachable(graph,"S")
	var destinations: Array=[]
	for label in ["RA","RB"]:
		if label in reached: destinations.append(label)
	var expected: String="RB" if position_m<=.002 else "RA" if position_m>=.798 else ""
	var forward: bool=connection.ok and cross and expected!="" and destinations==[expected] and not _return_active(returns)
	# Neutral is a valid settled mechanical state, not an open water route.
	# Runtime needs it to advance A -> neutral -> B; its detent gate still grants no flow here.
	var neutral: bool=connection.ok and cross and absf(position_m-.4)<=.002 and destinations.is_empty() and not _return_active(returns)
	for id in ["SourceA","SourceB","ReceiveA","ReceiveB"]:
		neutral=neutral and float(values[id])==0.0
	var return_start: String="DrainA" if int(runtime.get_node(Runtime.RECEIVER_A).volume_ml)>0 else "DrainB" if int(runtime.get_node(Runtime.RECEIVER_B).volume_ml)>0 else ""
	var back:=_reachable(graph,return_start)
	var other: String="DrainB" if return_start=="DrainA" else "DrainA"
	var returning: bool=connection.ok and absf(position_m-.4)<=.002 and return_start!="" and "FillS" in back and other not in back
	return {"ok":true,"code":"traced","forward_clear":forward,"neutral_clear":neutral,"return_clear":returning,"destinations":destinations,"active_channels":active,"low_cross_open":cross,"return_source":return_start}

func _bore_clear(segments: Array) -> bool:
	var excluded: Array[RID]=[]
	for body in float_bodies.values(): excluded.append(body.get_rid())
	for pair in segments:
		var a: Vector3=pair[0]
		var b: Vector3=pair[1]
		var axis: int=(b-a).abs().max_axis_index()
		var across: Array=[]
		for i in range(3):
			if i!=axis: across.append(i)
		for offset in [Vector2.ZERO,Vector2(-.008,-.008),Vector2(.008,.008)]:
			var shift:=Vector3.ZERO
			shift[across[0]]=offset.x
			shift[across[1]]=offset.y
			if not _ray(to_global(a+shift),to_global(b+shift),excluded).is_empty(): return false
	return true

func _link_bore_clear() -> bool:
	var points: Array=[Vector3(-2.45,.15,-9.44),Vector3(-1.55,.15,-9.44),Vector3(-1.55,1.28,-9.44),Vector3(1.55,1.28,-9.44),Vector3(1.55,.15,-9.44),Vector3(2.45,.15,-9.44)]
	var segments: Array=[]
	for i in range(points.size()-1): segments.append([points[i],points[i+1]])
	return _bore_clear(segments)

static func _add_edge(graph: Dictionary,a: String,b: String,directed: bool) -> void:
	if not graph.has(a): graph[a]=[]
	if not graph.has(b): graph[b]=[]
	graph[a].append(b)
	if not directed: graph[b].append(a)

static func _reachable(graph: Dictionary,start: String) -> Array:
	var visited: Array=[]
	var pending: Array=[start]
	while not pending.is_empty() and visited.size()<16:
		var id: String=pending.pop_front()
		if id in visited: continue
		visited.append(id)
		for neighbor in graph.get(id,[]):
			if neighbor not in visited and neighbor not in pending: pending.append(neighbor)
	return visited

static func _body_matches(body: Variant,point: Vector3,size: Vector3) -> bool:
	return _body_matches_pose(body,Transform3D(Basis.IDENTITY,point),size)

static func _body_matches_pose(body: Variant,expected: Transform3D,size: Vector3) -> bool:
	if not is_instance_valid(body) or not body is StaticBody3D: return false
	var actual: StaticBody3D=body
	if actual.collision_layer==0 or not actual.transform.is_equal_approx(expected) or actual.get_child_count()==0: return false
	var collision: CollisionShape3D=actual.get_child(0) as CollisionShape3D
	if collision==null or collision.disabled: return false
	var shape: BoxShape3D=collision.shape as BoxShape3D
	if shape==null or not shape.size.is_equal_approx(size): return false
	var visual: MeshInstance3D=actual.get_node_or_null(^"Visual") as MeshInstance3D
	if visual==null: return false
	var mesh: BoxMesh=visual.mesh as BoxMesh
	return mesh!=null and mesh.size.is_equal_approx(size)

static func _point_key(point: Vector3) -> String:
	return "%.6f,%.6f,%.6f" % [point.x,point.y,point.z]

static func _on_segment(point: Vector3,a: Vector3,b: Vector3) -> bool:
	var direction:=b-a
	var t:=direction.dot(point-a)/direction.length_squared()
	return t>.0001 and t<.9999 and (a+direction*t).distance_to(point)<.00001

static func _check_snapshot(raw: Variant, digest: String, axis, runtime) -> Dictionary:
	if not raw is Dictionary or not _exact(raw,SAVE_KEYS): return _r(false,"snapshot_keys")
	if not _number(raw.version,2,2) or not raw.layout_sha256 is String or raw.layout_sha256!=digest or not _number(raw.serial,0,Axis.MAX_SERIAL) or floor(float(raw.serial))!=float(raw.serial): return _r(false,"snapshot_identity")
	if not raw.return_requested is bool or not raw.blocked is bool: return _r(false,"snapshot_flags")
	if not raw.return_valves is Dictionary or not _exact(raw.return_valves,["a","b","check"]): return _r(false,"return_valve_schema")
	for value in raw.return_valves.values():
		if not _number(value,0,1): return _r(false,"return_valve_range")
	var valves: Dictionary=raw.return_valves
	if float(valves.a)>0 and float(valves.b)>0: return _r(false,"return_intake_interlock")
	# A closing check and its selected intake may both be partially closed.
	if float(valves.check)>0 and float(valves.a)==0 and float(valves.b)==0: return _r(false,"check_without_intake")
	var checked: Dictionary = axis.validate_snapshot(raw.axis)
	if not checked.ok: return checked
	if _return_active(raw.return_valves) and absf(float(raw.axis.position_m)-.4)>.002: return _r(false,"return_axis_interlock")
	return runtime.validate_snapshot(raw.runtime)

static func _validate_layout(data: Dictionary) -> Dictionary:
	if not _exact(data,LAYOUT_KEYS) or not _number(data.version,2,2) or data.id!="I2:trial_flow_v2" or data.stage!="connected_low_trial_candidate": return _r(false,"layout_schema")
	if not _vector(data.origin) or _v(data.origin)!=Vector3(18,0,-3): return _r(false,"layout_origin")
	if data.connection!="five_port_actual_same_world_link_required": return _r(false,"connection_claim")
	if not _bounds(data.bounds) or not _bounds(data.external_bounds): return _r(false,"layout_bounds")
	if _v(data.bounds.min)!=Vector3(-1.8,0,-.7) or _v(data.bounds.max)!=Vector3(1.8,2.6,.7): return _r(false,"bench_envelope")
	if not _v(data.external_bounds.min).is_equal_approx(Vector3(-2.52,.06,-9.475)) or not _v(data.external_bounds.max).is_equal_approx(Vector3(2.52,1.09,-.24)): return _r(false,"external_scope")
	if not data.axis is Dictionary or not _exact(data.axis,Axis.CONFIG_KEYS): return _r(false,"axis_schema")
	for pair in [["travel_m",.8],["mass_kg",2.0],["damping_per_second",.8],["max_speed_mps",2.0],["max_impulse_ns",9.0]]:
		if not _number(data.axis[pair[0]],pair[1],pair[1]): return _r(false,"axis_contract")
	if not _number(data.motor_speed_mps,.9,.9): return _r(false,"motor_speed")
	if not data.tanks is Array or data.tanks.size()!=3: return _r(false,"tank_count")
	for i in range(3):
		var spec: Variant = data.tanks[i]
		var id: String = [Runtime.SOURCE,Runtime.RECEIVER_A,Runtime.RECEIVER_B][i]
		if not spec is Dictionary or not _exact(spec,["id","center_xz","bottom_y","inner_size","wall_m"]) or spec.id!=id: return _r(false,"tank_schema")
		if not spec.center_xz is Array or spec.center_xz.size()!=2 or not _number(spec.center_xz[0],-1.15,1.15) or not _number(spec.center_xz[1],-.2,.05): return _r(false,"tank_position")
		var expected := Vector3(.8,.5,.5) if i==0 else Vector3(.5,1,.4)
		var expected_x: float = [0.0,-1.15,1.15][i]
		if float(spec.center_xz[0])!=expected_x or float(spec.center_xz[1])!=(-.2 if i==0 else .05): return _r(false,"tank_position_contract")
		if not _vector(spec.inner_size) or not _v(spec.inner_size).is_equal_approx(expected) or not _number(spec.bottom_y,1.4 if i==0 else .25,1.4 if i==0 else .25) or not _number(spec.wall_m,.04,.04): return _r(false,"tank_hydraulics")
	for key in ["solids","selector_parts","targets"]:
		if not data[key] is Array or data[key].is_empty() or data[key].size()>32: return _r(false,"part_count")
		var ids: Dictionary = {}
		for spec in data[key]:
			var keys := ["id","center","size"] if key=="selector_parts" else ["id","center","size","color"]
			if not spec is Dictionary or not _exact(spec,keys) or not spec.id is String or ids.has(spec.id) or not _vector(spec.center) or not _positive_vector(spec.size): return _r(false,"part_schema")
			if key!="selector_parts" and not _color(spec.color): return _r(false,"part_color")
			ids[spec.id]=true
			var size := _v(spec.size)
			if key=="selector_parts": size.x+=float(data.axis.travel_m)
			if not _inside(AABB(_v(spec.center)-size*.5,size),data.bounds): return _r(false,"part_scope")
		if key=="selector_parts" and ids.keys()!=["SelectorGrip","SelectorShaft","SelectorSpool"]: return _r(false,"selector_contract")
		if key=="targets" and ids.keys()!=[RELAY,CONTROLLER,RETURN_SWITCH]: return _r(false,"target_contract")

	if not data.ports is Dictionary or not _exact(data.ports,["S","Split","EA","EB","RA","RB","PortA","PortB","DrainA","DrainB","Pump","FillS"]): return _r(false,"port_schema")
	var contract: Dictionary={"S":[0,1.4,-.2],"Split":[0,1.05,-.2],"EA":[-.76,1.05,-.28],"EB":[.76,1.05,-.28],"RA":[-1.15,.8,-.15],"RB":[1.15,.8,-.15],"PortA":[-2.45,.15,-9.44],"PortB":[2.45,.15,-9.44],"DrainA":[-1.15,.25,.05],"DrainB":[1.15,.25,.05],"Pump":[.25,.15,-.48],"FillS":[.25,1.46,-.45]}
	for id in contract:
		if not _vector(data.ports[id]) or not _v(data.ports[id]).is_equal_approx(_v(contract[id])): return _r(false,"port_position")
	if not data.valves is Array or data.valves.size()!=7: return _r(false,"valve_count")
	var valves: Dictionary={}
	for index in range(7):
		var spec: Variant=data.valves[index]
		if not spec is Dictionary or not _exact(spec,["id","center","size","travel","mode"]) or spec.id!=VALVE_IDS[index]: return _r(false,"valve_schema")
		if not _vector(spec.center) or not _positive_vector(spec.size) or not _vector(spec.travel) or spec.mode not in ["A","B","return_a","return_b","check"]: return _r(false,"valve_geometry")
		var expected_mode: String=["A","B","B","A","return_a","return_b","check"][index]
		var expected_size:=Vector3(.08,.012,.08) if index==6 else Vector3(.012,.08,.08)
		var expected_travel:=Vector3.LEFT*.14 if index==6 else Vector3.BACK*.14 if index>=4 else Vector3.UP*.14
		if spec.mode!=expected_mode or not _v(spec.size).is_equal_approx(expected_size) or not _v(spec.travel).is_equal_approx(expected_travel): return _r(false,"valve_seat_contract")
		var size:=_v(spec.size)+_v(spec.travel).abs()
		if not _inside(AABB(_v(spec.center)+_v(spec.travel)*.5-size*.5,size),data.bounds): return _r(false,"valve_scope")
		valves[spec.id]=spec
	if not data.pipes is Array or data.pipes.size()!=10: return _r(false,"pipe_count")
	var pipe_ids: Dictionary={}
	for pipe in data.pipes:
		if not pipe is Dictionary or not _exact(pipe,["id","a","b","points","valve","kind","width","bore"]): return _r(false,"pipe_schema")
		if not pipe.id is String or not ROUTES.has(pipe.id) or pipe_ids.has(pipe.id): return _r(false,"pipe_id")
		if [pipe.a,pipe.b]!=ROUTES[pipe.id] or pipe.valve!=(pipe.id if valves.has(pipe.id) else "") or pipe.kind not in ["gravity","pump","isolated"]: return _r(false,"pipe_topology")
		if not _number(pipe.width,.07,.07) or not _number(pipe.bore,.04,.04) or not pipe.points is Array or pipe.points.size()<2 or pipe.points.size()>10: return _r(false,"pipe_dimensions")
		for point in pipe.points:
			if not _vector(point): return _r(false,"pipe_point")
		if not _v(pipe.points[0]).is_equal_approx(_v(data.ports[pipe.a])) or not _v(pipe.points[-1]).is_equal_approx(_v(data.ports[pipe.b])): return _r(false,"pipe_junction")
		var seat_count:=0
		for i in range(pipe.points.size()-1):
			var a:=_v(pipe.points[i])
			var b:=_v(pipe.points[i+1])
			var diff: Vector3=(b-a).abs()
			if int(diff.x>0)+int(diff.y>0)+int(diff.z>0)!=1: return _r(false,"pipe_axis")
			var size:=diff+Vector3.ONE*.07
			var bounds: Dictionary=data.external_bounds if str(pipe.id).begins_with("External") else data.bounds
			if not _inside(AABB((a+b)*.5-size*.5,size),bounds): return _r(false,"pipe_scope")
			if pipe.valve!="" and _on_segment(_v(valves[pipe.valve].center),a,b):
				var normal: int=_v(valves[pipe.valve].size).min_axis_index()
				if normal!=diff.max_axis_index(): return _r(false,"valve_plane")
				seat_count+=1
		if pipe.valve!="" and seat_count!=1: return _r(false,"seat_not_in_channel")
		pipe_ids[pipe.id]=true
	if not data.service_ports is Array or data.service_ports.size()!=2: return _r(false,"service_ports")
	for i in range(2):
		var spec: Variant=data.service_ports[i]
		if not spec is Dictionary or not _exact(spec,["id","position"]) or spec.id!=["A","B"][i] or not _vector(spec.position): return _r(false,"service_port_schema")
		if not _v(spec.position).is_equal_approx(_v(data.ports["PortA" if i==0 else "PortB"])): return _r(false,"service_port_position")
	if not data.observation is Dictionary or not _exact(data.observation,["max_distance_m","min_facing_dot","min_hits"]) or data.observation.max_distance_m!=4.5 or data.observation.min_facing_dot!=.35 or data.observation.min_hits!=3: return _r(false,"observation_contract")
	return _r(true,"valid")

static func _inside(box: AABB, bounds: Dictionary) -> bool:
	var outer := AABB(_v(bounds.min),_v(bounds.max)-_v(bounds.min)).grow(0.00001)
	return outer.encloses(box)

static func _bounds(raw: Variant) -> bool:
	return raw is Dictionary and _exact(raw,["min","max"]) and _vector(raw.min) and _vector(raw.max) and _positive_vector([float(raw.max[0])-float(raw.min[0]),float(raw.max[1])-float(raw.min[1]),float(raw.max[2])-float(raw.min[2])])

static func _vector(raw: Variant) -> bool:
	return raw is Array and raw.size()==3 and _number(raw[0],-100,100) and _number(raw[1],-100,100) and _number(raw[2],-100,100)

static func _positive_vector(raw: Variant) -> bool:
	return _vector(raw) and float(raw[0])>0 and float(raw[1])>0 and float(raw[2])>0

static func _v(raw: Array) -> Vector3:
	return Vector3(float(raw[0]),float(raw[1]),float(raw[2]))

static func _exact(raw: Dictionary, keys: Array) -> bool:
	if raw.size()!=keys.size(): return false
	for key in raw:
		if not key is String or key not in keys: return false
	return true

static func _number(raw: Variant, low: float, high: float) -> bool:
	return (raw is int or raw is float) and is_finite(float(raw)) and float(raw)>=low and float(raw)<=high

static func _color(raw: Variant) -> bool:
	if not raw is String or raw.length()!=6: return false
	for character in raw:
		if character not in "0123456789abcdefABCDEF": return false
	return true

static func _r(ok: bool, code: String) -> Dictionary:
	return {"ok":ok,"code":code}
