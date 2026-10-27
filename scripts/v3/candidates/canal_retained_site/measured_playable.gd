extends "res://scripts/v3/candidates/canal_playable/canal_playable.gd"
## The original scene has only its scripted root. This subclass adds timing,
## never replaces or manually drives the existing physics implementation.
var measurement_phase := "visible_setup"
var timing: Dictionary = {}
var memory_samples: Array[Dictionary] = []
var measured_ticks := 0
const TRACE_LIMIT := 256
var transport_trace: Array[Dictionary] = []
var trace_dropped := 0
var fatal_snapshot: Dictionary = {}
var _trace_key := ""
var _last_trace_frame := -1
var _tick_before: Dictionary = {}
var serial4_handoff: Dictionary = {}
var _serial4_previous_position := Vector3.ZERO
var _serial4_previous_frame := -1

func _physics_process(delta: float) -> void:
	# Read only: preserve the command/pose entering the original callback, since
	# its fault handler replaces the carrier command with brake before returning.
	_tick_before = _before_callback()
	var begin: int = Time.get_ticks_usec()
	super._physics_process(delta)
	var elapsed: int = Time.get_ticks_usec()-begin
	if not timing.has(measurement_phase):
		timing[measurement_phase] = {"host_usec":[],"global_previous_physics_usec":[]}
	timing[measurement_phase].host_usec.append(elapsed)
	# Engine-wide completed-frame monitor, not a measurement of this viewport.
	timing[measurement_phase].global_previous_physics_usec.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000000.0)
	measured_ticks += 1
	if measured_ticks % 60 == 0:
		memory_samples.append({"phase":measurement_phase,"frame":Engine.get_physics_frames(),
			"static_bytes":OS.get_static_memory_usage(),"node_count":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			"global_active_3d_objects":Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)})
	_capture_transport_transition()
	_observe_serial4_handoff()

func _before_callback() -> Dictionary:
	if not executor_ready or not is_instance_valid(context.get("carrier")): return {}
	var carrier: RigidBody3D = context.carrier
	return {"frame":Engine.get_physics_frames(),"phase":executor._phase,
		"action":executor._action.duplicate(true),"hold":executor._hold.duplicate(true),
		"position":_xyz(carrier.global_position),"linear_velocity":_xyz(carrier.linear_velocity),
		"command":context.carrier.command.duplicate(true)}

func _capture_transport_transition() -> void:
	if not executor_ready or not is_instance_valid(context.get("carrier")): return
	var key: String = str([executor._phase,executor._code,executor._action.get("serial",0),
		executor._path_index,executor._receipt_count,workbench._phase if is_instance_valid(workbench) else ""])
	var frame: int = Engine.get_physics_frames()
	var failed: bool = not fatal.is_empty() and fatal_snapshot.is_empty()
	var periodic: bool = (executor._phase in ["approach_wait","approach","release_wait","fall","commit","departure_wait","departure"] or not executor._hold.is_empty()) and frame-_last_trace_frame>=30
	if key==_trace_key and not periodic and not failed: return
	_trace_key = key
	_last_trace_frame = frame
	var row: Dictionary = diagnostic_snapshot("fatal_after_original_callback" if failed else "phase_action_or_30frame_docking_sample")
	transport_trace.append(row)
	if transport_trace.size()>TRACE_LIMIT:
		transport_trace.pop_front()
		trace_dropped += 1
	if failed: fatal_snapshot = row.duplicate(true)

func diagnostic_snapshot(reason: String) -> Dictionary:
	# All queried APIs are read-only. Probe evidence is sampled AFTER the original
	# callback and is never passed back as permission or used to alter a command.
	var row: Dictionary = {"reason":reason,"frame":Engine.get_physics_frames(),
		"host_ticks":measured_ticks,"measurement_phase":measurement_phase,"fatal":fatal,
		"before_original_callback":_tick_before.duplicate(true)}
	if not executor_ready or not context.has("rules") or not is_instance_valid(context.get("carrier")):
		row.available = false
		return row
	row.available = true
	var state: Dictionary = context.rules.snapshot()
	var report: Dictionary = executor.report()
	var carrier: RigidBody3D = context.carrier
	var anchor_id: String = str(state.carrier_anchor)
	var source_id: String = str(report.action.get("source",""))
	row.world_clock = world.clock_seconds
	row.space = PhysicsServer3D.body_get_space(carrier.get_rid()).get_id()
	row.rules = {"revision":state.revision,"action_serial":state.action_serial,
		"carrier_anchor":anchor_id,"pending_action":state.pending_action.duplicate(true),
		"jobs_completed":state.jobs_completed,"service_credit":state.service_credit,
		"services_consumed":state.services_consumed}
	row.executor = {"phase":report.phase,"code":report.code,"action":report.action,
		"path_index":report.path_index,"path_size":report.path_size,"hold":report.hold,
		"receipt_count":report.receipt_count,"released":report.released,"departure":report.departure,
		"controller":report.controller,"latest_receipt":report.receipts[-1] if not report.receipts.is_empty() else {}}
	row.carrier = {"position":_xyz(carrier.global_position),"linear_velocity":_xyz(carrier.linear_velocity),
		"angular_velocity":_xyz(carrier.angular_velocity),"command":context.carrier.command.duplicate(true),
		"physics_origin":_xyz(PhysicsServer3D.body_get_state(carrier.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM).origin),
		"health":context.carrier.health,"collision_count":context.carrier.collision_count,
		"contacts":_contact_paths(carrier)}
	row.confirmed_anchor = _anchor_detail(anchor_id,carrier.global_position)
	row.action_source_anchor = _anchor_detail(source_id,carrier.global_position)
	row.custody = context.custody.report()
	row.cargo_physics = {}
	for id: String in context.cargos:
		var cargo: RigidBody3D = context.cargos[id]
		row.cargo_physics[id] = {"position":_xyz(cargo.global_position),"linear_velocity":_xyz(cargo.linear_velocity),
			"angular_velocity":_xyz(cargo.angular_velocity),"contacts":_contact_paths(cargo)}
	var cargo_id: String = str(report.action.get("cassette_id",""))
	var berth_id: String = str(report.action.get("destination",""))
	row.release_info = context.custody.release_info(cargo_id,berth_id) if report.action.get("kind","")=="place" else {"not_applicable":true}
	row.current_readonly_zero_intent_probe = executor._pilot.probe(Vector3.ZERO) if executor._pilot!=null else {"unavailable":true}
	row.workbench = {"phase":workbench._phase,"receipt_count":workbench._receipt_count} if is_instance_valid(workbench) else {}
	return row

func _anchor_detail(id: String, actual: Vector3) -> Dictionary:
	if id!=Executor.Rules.WAIT and not Executor.BERTH_POINTS.has(id): return {"id":id,"known":false}
	var expected: Vector3 = executor._anchor(id,2.2)
	return {"id":id,"known":true,"expected":_xyz(expected),
		"xz_distance_m":Vector2(actual.x-expected.x,actual.z-expected.z).length(),
		"source_gate_m":.20}

static func _contact_paths(body: RigidBody3D) -> Array[String]:
	var paths: Array[String] = []
	for hit: Node3D in body.get_colliding_bodies(): paths.append(str(hit.get_path()))
	return paths

static func _xyz(value: Vector3) -> Array:
	return [value.x,value.y,value.z]

func diagnostics() -> Dictionary:
	return {"limit":TRACE_LIMIT,"dropped":trace_dropped,"events":transport_trace.duplicate(true),
		"fatal":fatal_snapshot.duplicate(true),
		"serial4_handoff":serial4_handoff.duplicate(true),
		"scope":"Read-only after-callback phase/action/docking samples; pre-callback command retained. No executor decisions, poses, thresholds or player route changed. Added query time is outside host callback timer."}

func _observe_serial4_handoff() -> void:
	if not executor_ready or int(executor._action.get("serial",0))!=4 or serial4_handoff.get("travel_started",false): return
	var carrier: RigidBody3D = context.carrier
	var state: Dictionary = context.rules.snapshot()
	var custody: Dictionary = context.custody.report().cargos
	var frame: int = Engine.get_physics_frames()
	var ownership: Dictionary = {}
	for id: String in custody:
		ownership[id] = {"phase":custody[id].phase,"berth":custody[id].berth,"carrier":custody[id].carrier}
	if serial4_handoff.is_empty():
		serial4_handoff = {"first_frame":frame,"initial_position":_xyz(carrier.global_position),
			"initial_source_error":_anchor_detail(str(executor._action.source),carrier.global_position),
			"action":executor._action.duplicate(true),"initial_receipts":executor._receipt_count,
			"ownership":ownership.duplicate(true),"samples":0,"max_step_m":0.0,
			"consecutive_frames":true,"same_action_and_pending":true,"same_receipts":true,
			"same_ownership":true,"observed_live_hold":false,"travel_started":false}
	if _serial4_previous_frame>=0:
		serial4_handoff.max_step_m = maxf(float(serial4_handoff.max_step_m),carrier.global_position.distance_to(_serial4_previous_position))
		serial4_handoff.consecutive_frames = serial4_handoff.consecutive_frames and frame==_serial4_previous_frame+1
	_serial4_previous_frame = frame
	_serial4_previous_position = carrier.global_position
	serial4_handoff.samples += 1
	serial4_handoff.last_frame = frame
	for key: String in Executor.MATCH_KEYS:
		serial4_handoff.same_action_and_pending = serial4_handoff.same_action_and_pending and executor._action.get(key)==serial4_handoff.action.get(key) and state.pending_action.get(key)==serial4_handoff.action.get(key)
	serial4_handoff.same_receipts = serial4_handoff.same_receipts and executor._receipt_count==serial4_handoff.initial_receipts
	serial4_handoff.same_ownership = serial4_handoff.same_ownership and ownership==serial4_handoff.ownership
	serial4_handoff.observed_live_hold = serial4_handoff.observed_live_hold or not executor._hold.is_empty()
	if executor._phase=="travel":
		serial4_handoff.travel_started = true
		serial4_handoff.travel_frame = frame
		serial4_handoff.final_position = _xyz(carrier.global_position)
		serial4_handoff.final_source_error = _anchor_detail(str(executor._action.source),carrier.global_position)
		serial4_handoff.final_distance_m = carrier.global_position.distance_to(executor._anchor(str(executor._action.source),2.2))
		serial4_handoff.final_speed_mps = carrier.linear_velocity.length()

func measurements() -> Dictionary:
	var phases: Dictionary = {}
	for key: String in timing:
		phases[key] = {"host_chain_usec":_distribution(timing[key].host_usec),
			"global_previous_physics_usec":_distribution(timing[key].global_previous_physics_usec)}
	return {"phases":phases,"memory_samples":memory_samples.duplicate(true),"ticks":measured_ticks,
		"scope":"Headless candidate. Host chain excludes engine rigid-body solving; global monitor includes both spaces and probe. Static allocation is not process RSS. No GPU/FPS/MAIN performance acceptance."}

static func _distribution(values: Array) -> Dictionary:
	if values.is_empty(): return {"count":0}
	var sorted: Array = values.duplicate()
	sorted.sort()
	return {"count":sorted.size(),"p50":sorted[int(ceil(sorted.size()*.50))-1],
		"p95":sorted[int(ceil(sorted.size()*.95))-1],"maximum":sorted[-1]}
