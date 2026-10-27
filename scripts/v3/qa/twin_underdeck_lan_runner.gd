extends Node
## Scripted real two-process ENet QA; only the controller may launch this peer.
## Previous 23 objectives and initial poses are fixtures. New four goals use
## production G/actions, real body motion, authority observations and Store.
const Director = preload("res://scripts/v3/gameplay/actions/twin_action_director.gd")
const LAYOUT := "res://data/v3/terrain/i1_underdeck_layout.json"
const FRONT := "I1:underdeck_grille"
const LATCH := "I1:underdeck_latch"
const DISCOVERY := "opening:underdeck_worker_bypass"
const ENTRY := "I1:underdeck:enter"
const RELEASE := "I1:underdeck:release"
const TRAVERSE := "I1:underdeck:traverse"

class PeerSession extends "res://scripts/v3/twin_session.gd":
	var qa_owner
	func _physics_process(delta: float) -> void:
		qa_owner.hold_bodies(self)
		qa_owner.before_tick(self, delta)
		var before: Dictionary = world.underdeck.snapshot() if is_instance_valid(world) and is_instance_valid(world.underdeck) and network.mode == "guest" else {}
		super._physics_process(delta)
		qa_owner.after_tick(self, before)
		qa_owner.hold_bodies(self)
	func _process(delta: float) -> void:
		var incoming: Dictionary = pending_packet.duplicate(true)
		super._process(delta)
		if not incoming.is_empty() and received_sequence == int(incoming.get("sequence", -2)):
			qa_owner.applied_snapshot(self, incoming)
		qa_owner.hold_bodies(self)

var session
var role := ""
var label := ""
var profile := ""
var run_id := ""
var evidence := ""
var expected_sha := ""
var reconnect := false
var ack := 0
var result: Dictionary = {}
var errors: Array = []
var commands: Array = []
var notices: Array = []
var received_events: Array = []
var first_snapshot: Dictionary = {}
var first_paused_snapshot: Dictionary = {}
var latest_probe: Dictionary = {}
var applied_count := 0
var guest_ticks := 0
var guest_local_mutations := 0
var hold_armed := false
var hold_observation: Dictionary = {}
var motion: Dictionary = {}
var motion_result: Dictionary = {}
var started_msec := 0
var host_left_seen := false
var initial_profile_id := ""
var initial_personal: Dictionary = {}
var last_controller_heartbeat := 0.0
var entry_kind := ""
var _started := false
var _launch_args: PackedStringArray = []
var _launch_config: Dictionary = {}

## No writes, Session creation or sockets. Both source entries share one root.
static func preflight(args: PackedStringArray, kind: String) -> Dictionary:
	if kind not in ["source_script", "source_main", "package_main"]:
		return {"ok":false, "code":"invalid_entry_kind"}
	if (kind == "package_main") == OS.has_feature("editor"):
		return {"ok":false, "code":"entry_runtime_mismatch"}
	var fields: Dictionary = {"--qa-suite":"suite", "--qa-profile":"profile", "--qa-underdeck-role":"role", "--qa-underdeck-label":"label", "--qa-underdeck-run":"run_id", "--qa-underdeck-evidence":"evidence", "--qa-underdeck-sha":"expected_sha"}
	var config: Dictionary = {"reconnect":false}
	var seen: Dictionary = {}
	for argument in args:
		if argument == "--qa-underdeck-reconnect":
			if seen.has(argument): return {"ok":false, "code":"duplicate_argument"}
			seen[argument] = true
			config.reconnect = true
			continue
		var separator: int = argument.find("=")
		if separator < 1: return {"ok":false, "code":"unknown_argument"}
		var key: String = argument.substr(0, separator)
		if not fields.has(key) or seen.has(key): return {"ok":false, "code":"unknown_or_duplicate_argument"}
		seen[key] = true
		config[fields[key]] = argument.substr(separator + 1)
	for field in fields.values():
		if not config.has(field) or str(config[field]).is_empty(): return {"ok":false, "code":"missing_argument"}
	if config.suite != "underdeck-lan" or config.role not in ["host", "guest"]:
		return {"ok":false, "code":"invalid_suite_or_role"}
	var run_pattern := RegEx.new()
	run_pattern.compile("^[0-9]{8}_[0-9]{6}_[0-9]{6}$")
	if run_pattern.search(str(config.run_id)) == null: return {"ok":false, "code":"invalid_run_id"}
	var wanted_label: String = "host" if config.role == "host" else ("guest_reconnect" if config.reconnect else "guest_first")
	var wanted_profile: String = "qa_underdeck_lan_" + str(config.role) + "_" + str(config.run_id)
	if config.label != wanted_label or config.profile != wanted_profile or (config.reconnect and config.role != "guest"):
		return {"ok":false, "code":"profile_role_run_mismatch"}
	if config.profile != str(config.profile).validate_filename(): return {"ok":false, "code":"invalid_profile"}
	var runtime_root: String = OS.get_executable_path().get_base_dir() if kind == "package_main" else ProjectSettings.globalize_path("res://")
	var required_path: String = _normalized_path(runtime_root.path_join("artifacts/v3/network/underdeck").path_join(str(config.run_id)))
	var supplied_path: String = _normalized_path(str(config.evidence))
	if not str(config.evidence).is_absolute_path() or supplied_path != required_path or not DirAccess.dir_exists_absolute(required_path):
		return {"ok":false, "code":"evidence_path_not_exact_run_directory"}
	config.evidence = required_path
	var digest_pattern := RegEx.new()
	digest_pattern.compile("^[0-9a-f]{64}$")
	if digest_pattern.search(str(config.expected_sha)) == null or not FileAccess.file_exists(LAYOUT) or FileAccess.get_sha256(LAYOUT) != config.expected_sha:
		return {"ok":false, "code":"runtime_layout_hash_mismatch"}
	var exists: bool = DirAccess.dir_exists_absolute("user://profiles_v3/" + str(config.profile))
	if exists != bool(config.reconnect): return {"ok":false, "code":"fresh_profile_or_reconnect_required"}
	config.entry_kind = kind
	var controller: Variant = _read_json_file(required_path.path_join("controller.json"))
	if not _valid_controller(controller, config): return {"ok":false, "code":"live_locked_controller_required"}
	config.controller_heartbeat = float(controller.heartbeat_unix)
	return {"ok":true, "code":"ready", "config":config}

static func _normalized_path(path: String) -> String:
	return path.replace("\\", "/").simplify_path().trim_suffix("/")

static func _valid_controller(controller: Variant, config: Dictionary) -> bool:
	if not controller is Dictionary: return false
	if controller.get("run_id") != config.run_id or controller.get("lock_held") != true or controller.get("underdeck_sha256") != config.expected_sha: return false
	if controller.get("qa_suite") != "underdeck-lan" or controller.get("entry_kind") != config.entry_kind or controller.get("evidence") != config.evidence: return false
	var profiles: Variant = controller.get("profiles")
	if not profiles is Dictionary or profiles.get(config.role) != config.profile: return false
	var stamp: Variant = controller.get("heartbeat_unix")
	if not (stamp is float or stamp is int) or not is_finite(float(stamp)): return false
	var age: float = Time.get_unix_time_from_system() - float(stamp)
	return age >= 0.0 and age < 20.0

static func _read_json_file(path: String) -> Variant:
	if not FileAccess.file_exists(path): return null
	var content: String = FileAccess.get_file_as_string(path)
	if content.is_empty(): return null
	var parser := JSON.new()
	return parser.data if parser.parse(content) == OK else null

func start(args: PackedStringArray, kind: String) -> Dictionary:
	if _started or not is_inside_tree(): return {"ok":false, "code":"already_started_or_not_in_tree"}
	# TwinSession reads these same process arguments when opening its profile.
	if args != OS.get_cmdline_user_args(): return {"ok":false, "code":"actual_process_arguments_required"}
	var verified: Dictionary = preflight(args, kind)
	if not verified.ok: return verified
	_launch_args = args.duplicate()
	_launch_config = verified.config.duplicate(true)
	role = str(_launch_config.role)
	label = str(_launch_config.label)
	profile = str(_launch_config.profile)
	run_id = str(_launch_config.run_id)
	evidence = str(_launch_config.evidence)
	expected_sha = str(_launch_config.expected_sha)
	reconnect = bool(_launch_config.reconnect)
	entry_kind = kind
	last_controller_heartbeat = float(_launch_config.controller_heartbeat)
	started_msec = Time.get_ticks_msec()
	_started = true
	_boot.call_deferred()
	return {"ok":true, "code":"scheduled", "entry_kind":entry_kind}

func _boot() -> void:
	# Recheck the deferred boundary before any profile bootstrap or socket exists.
	var verified: Dictionary = preflight(_launch_args, entry_kind)
	if not verified.ok:
		_fail("deferred preflight: " + str(verified.code))
		_finish(2)
		return
	session = PeerSession.new()
	session.qa_owner = self
	add_child(session)
	if not session.profile_ready or session.network.PROTOCOL != 21:
		_fail("isolated profile and protocol21 required")
		_finish(2)
		return
	session.inputs.set_process(false)
	session.inputs.set_physics_process(false)
	session.frame_id = "hx02" if role == "guest" else "tr01"
	session.network.status_changed.connect(func(message): _bounded_append(notices, {"text":message,"time_ms":Time.get_ticks_msec()-started_msec}))
	session.network.event_received.connect(_network_event)
	var saved: Dictionary = session.store.snapshot()
	initial_profile_id = str(saved.profile_id)
	initial_personal = saved.personal.duplicate(true)
	if not session.start_flight(role, "127.0.0.1"):
		_fail("production session start failed")
		_finish(2)
		return
	if role == "host" and not _seed_prerequisites():
		_fail("explicit predecessor fixture failed")
		_finish(2)
		return
	var timer := Timer.new()
	timer.wait_time = 0.05
	timer.timeout.connect(_poll)
	add_child(timer)
	timer.start()
	print("UNDERDECK_QA_READY " + JSON.stringify({"qa_suite":"underdeck-lan", "entry_kind":entry_kind, "run_id":run_id, "profile":profile, "resource_layout_sha256":expected_sha}))
	_write_state()

func _seed_prerequisites() -> bool:
	var legacy = Director.new()
	if not legacy.load_definitions(Director.DEFAULT_PATH, ["res://data/v3/actions/whale_action.json","res://data/v3/actions/crown_action.json"]).ok: return false
	var state: Dictionary = legacy.default_state()
	for action in legacy.definitions().actions:
		for objective in action.objectives:
			var matcher: Dictionary = objective.events[0]
			var event := {"id":"qa-predecessor:"+str(objective.id),"type":matcher.type,"target_id":matcher.target_id,"option":matcher.options[0]}
			var next: Dictionary = legacy.apply_event(state,event,{"is_authority":true,"validated":true,"region_id":action.region_id})
			if not next.get("changed",false): return false
			state = next.state
	if state.completed.size() != 23 or not session.story.director.validate_state(state).ok: return false
	if not session.store.commit({"id":"qa-six-actions-fixture","set":{"world.actions.opening":state,"world.flags":state.flags,"world.completed_objectives":state.completed},"append":{"personal.discoveries":state.discoveries}}).ok: return false
	session.world_cache = session.store.snapshot()
	if not session._load_region("I1"): return false
	hold_bodies(session)
	return _place(1,Vector3(-35,2.05,-16.8))

func hold_bodies(current) -> void:
	for body in current.players.values():
		body.freeze = true
		body.set_process(false)
		body.set_physics_process(false)
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO

func before_tick(current, delta: float) -> void:
	if role != "host" or current.simulation_paused or motion.is_empty(): return
	var peer := int(motion.peer)
	if not current.players.has(peer):
		motion_result = {"ok":false,"error":"moving peer left"}
		motion.clear()
		return
	var body = current.players[peer]
	var target: Vector3 = motion.points[0]
	var collision: KinematicCollision3D = body.move_and_collide((target-body.global_position).limit_length(minf(0.15,delta*6.0)))
	motion.steps += 1
	if collision != null:
		motion_result = {"ok":false,"error":"actual motion blocked","collider":str(collision.get_collider().get_path()),"position":body.global_position,"target":target,"steps":motion.steps}
		motion.clear()
	elif body.global_position.distance_to(target) < 0.005:
		motion.points.pop_front()
		if motion.points.is_empty():
			motion_result = {"ok":true,"position":body.global_position,"steps":motion.steps,"method":"real host-authority FlightBody.move_and_collide QA autopilot"}
			motion.clear()

func after_tick(current, before: Dictionary) -> void:
	if role == "guest" and not before.is_empty() and is_instance_valid(current.world) and is_instance_valid(current.world.underdeck):
		guest_ticks += 1
		if current.world.underdeck.snapshot() != before: guest_local_mutations += 1
	if role != "host" or not hold_armed or current.simulation_paused: return
	var state: Dictionary = current.world.underdeck.snapshot()
	if state.front_fraction >= 0.35 and state.front_fraction < 0.75 and float(current.cooldowns.get(1,0)) <= 0:
		var count: int = current.stats.abilities
		current.network.send_action("ability",{"ability":"force_field","target_id":FRONT})
		hold_observation = {"fraction_before":state.front_fraction,"phase_usec":state.phase_usec,"abilities_before":count,"abilities_after":current.stats.abilities,"accepted":current.stats.abilities==count+1}
		hold_armed = false

func applied_snapshot(current, packet: Dictionary) -> void:
	if not packet.get("mechanisms",{}).has("underdeck"): return
	applied_count += 1
	var observation := {"sequence":packet.sequence,"paused":packet.paused,"packet_mechanism":packet.mechanisms.underdeck.duplicate(true),"probe":_gate_probe(),"physics_frame":Engine.get_physics_frames()}
	latest_probe = observation
	if first_snapshot.is_empty(): first_snapshot = observation.duplicate(true)
	if packet.paused and first_paused_snapshot.is_empty(): first_paused_snapshot = observation.duplicate(true)

func _gate_probe() -> Dictionary:
	if not is_instance_valid(session.world) or not is_instance_valid(session.world.underdeck): return {"ready":false}
	var module = session.world.underdeck
	var snapshot: Dictionary = module.snapshot()
	var poses: Dictionary = {}
	var maximum_error := 0.0
	for side in ["front","rear"]:
		var body: PhysicsBody3D = module.gates[side]
		var spec: Dictionary = module.layout().gates[side]
		var expected := _v(spec.center)+_v(spec.travel)*float(snapshot[side+"_fraction"])
		var actual: Transform3D = PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
		maximum_error = maxf(maximum_error,maxf(body.global_position.distance_to(expected),actual.origin.distance_to(expected)))
		poses[side] = {"position":body.global_position,"physics_position":actual.origin,"expected":expected}
	var target_error: float = session.entities.get(FRONT,{}).get("position",Vector3.INF).distance_to(module.gates.front.global_position)
	return {"ready":true,"authority":module.authority,"state":snapshot,"poses":poses,"maximum_pose_error":maximum_error,"target_error":target_error}

func _poll() -> void:
	if not _controller_alive() or Time.get_ticks_msec()-started_msec > 180000:
		_fail("controller lease expired or three-minute bound reached")
		_finish(2)
		return
	var request = _read_json(evidence.path_join(label+"-command.json"))
	if request is Dictionary and request.get("run_id")==run_id and int(request.get("sequence",0))>ack:
		ack=int(request.sequence)
		var args=request.get("args",{})
		result=_execute(str(request.get("verb","")),args if args is Dictionary else {})
		_bounded_append(commands,{"sequence":ack,"verb":request.get("verb"),"args":args,"result":result.duplicate(true),"time_ms":Time.get_ticks_msec()-started_msec})
		if not result.get("ok",false): _fail("command "+str(request.get("verb"))+": "+str(result))
		if request.get("verb")=="shutdown":
			_write_state(true)
			session._quit()
			return
	_write_state()

func _execute(verb: String,args: Dictionary) -> Dictionary:
	if verb in ["shutdown","state"]: return {"ok":true}
	if verb=="action":
		var payload: Dictionary=args.get("payload",{}).duplicate(true)
		if payload.has("point"): payload.point=_v(payload.point)
		session.network.send_action("ability",payload)
		return {"ok":true,"transport_sequence":session.network._sequence}
	if role!="host": return {"ok":false,"error":"host fixture required"}
	var guest := _guest_peer()
	if verb=="read_plan":
		session.interface.clear_dialogue()
		var key:=InputEventKey.new()
		key.pressed=true
		key.keycode=KEY_G
		key.physical_keycode=KEY_G
		session._unhandled_input(key)
		return {"ok":"I1:underdeck:read" in session.story.state.completed,"method":"real G input at actual inspect marker"}
	if verb=="arm_hold":
		hold_armed=true
		return {"ok":true,"method":"wait natural cycle then real force_field action; no phase fixture"}
	if verb=="place_guest": return {"ok":guest>0 and _place(guest,_v(args.get("position"))),"fixture":"explicit starting pose only; clears that actor route history"}
	if verb=="move_guest":
		if guest==0 or not motion.is_empty() or not args.get("points") is Array: return {"ok":false,"error":"invalid motion request"}
		var points: Array=[]
		for point in args.points:
			var at:=_v(point)
			if not at.is_finite(): return {"ok":false,"error":"invalid waypoint"}
			points.append(at)
		if points.is_empty() or points.size()>8: return {"ok":false,"error":"bounded waypoints required"}
		motion={"peer":guest,"points":points,"steps":0}
		motion_result={}
		return {"ok":true,"fixture":"QA autopilot uses host real FlightBody collisions, not guest control feel"}
	if verb=="pause":
		session.simulation_paused=bool(args.get("value",true))
		session._apply_pause_state()
		return {"ok":true,"fixture":"QA direct pause, not consensus UI test"}
	if verb=="resend_earned_receipt":
		if guest==0: return {"ok":false,"error":"no current guest"}
		for item in session.store.snapshot().ledger.guest_outbox.values():
			var receipt: Dictionary=item.receipt
			if receipt.guest_id==session.identities[guest] and receipt.reward_id==DISCOVERY:
				session.network.send_event(guest,{"kind":"receipt_batch","session_id":session.network.session_id,"receipts":[receipt.duplicate(true)]})
				return {"ok":true,"receipt_id":receipt.receipt_id,"fixture":"replay exact already-earned receipt over production reliable transport"}
		return {"ok":false,"error":"earned underdeck receipt absent"}
	return {"ok":false,"error":"unknown command"}

func _place(peer: int,point: Vector3) -> bool:
	if not session.players.has(peer) or not point.is_finite(): return false
	var body=session.players[peer]
	var envelope: CollisionShape3D=body.get_node("Envelope")
	var query:=PhysicsShapeQueryParameters3D.new()
	query.shape=envelope.shape
	query.transform=Transform3D(Basis.IDENTITY,point)*envelope.transform
	query.collision_mask=1|2|8
	query.exclude=[body.get_rid()]
	if not session.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): return false
	session.story.reset_underdeck_tracking(peer)
	body.global_transform=Transform3D(Basis.IDENTITY,point)
	body.safe_position=point
	body.hold_height=point.y
	body.freeze=true
	body.linear_velocity=Vector3.ZERO
	body.angular_velocity=Vector3.ZERO
	body.force_update_transform()
	PhysicsServer3D.body_set_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,body.global_transform)
	session.entities[session._actor_id(peer)].position=point
	return true

func _guest_peer() -> int: return int(session.network.guests.keys()[0]) if session.network.guests.size()==1 else 0
func _v(raw: Variant) -> Vector3:
	if not raw is Array or raw.size()!=3: return Vector3.INF
	for number in raw:
		if not (number is float or number is int) or not is_finite(number): return Vector3.INF
	return Vector3(raw[0],raw[1],raw[2])
func _network_event(event: Dictionary) -> void:
	if event.get("kind")=="host_left": host_left_seen=true
	_bounded_append(received_events,{"kind":event.get("kind"),"time_ms":Time.get_ticks_msec()-started_msec,"reward_ids":event.get("receipts",[]).map(func(item):return item.get("reward_id","")) if event.get("kind")=="receipt_batch" else []})
func _controller_alive() -> bool:
	var controller: Variant = _read_json_file(evidence.path_join("controller.json"))
	var now: float = Time.get_unix_time_from_system()
	if controller == null:
		# An atomic Windows publication may briefly be unreadable. Reuse only the
		# previously verified lease; a failed read never renews it.
		var age: float = now - last_controller_heartbeat
		return last_controller_heartbeat > 0.0 and age >= 0.0 and age < 20.0
	if not _valid_controller(controller, _launch_config): return false
	last_controller_heartbeat = float(controller.heartbeat_unix)
	return true
func _read_json(path: String) -> Variant:
	return _read_json_file(path)
func _state() -> Dictionary:
	var roster: Dictionary={}
	for peer in session.players:
		var body=session.players[peer]
		roster[str(peer)]={"position":body.global_position,"health":body.health,"enabled":body.enabled,"identity":session.identities[peer],"airframe":body.build.airframe_id,"cooldown":session.cooldowns.get(peer,0)}
	var personal: Dictionary=session.store.snapshot()
	return {"qa_scripted":true,"qa_suite":"underdeck-lan","entry_kind":entry_kind,"resource_layout_sha256":expected_sha,"role":role,"label":label,"run_id":run_id,"profile":profile,"profile_id":initial_profile_id,"initial_personal":initial_personal,"protocol":session.network.PROTOCOL,"network_mode":session.network.mode,"active":session.active,"region":session.region_id,"session_id":session.network.session_id if role=="host" else session.received_session,"peer_id":session.network.local_id(),"players":roster,"stats":session.stats.duplicate(),"transport":session.network.telemetry.duplicate(),"paused":session.simulation_paused,"received_sequence":session.received_sequence,"applied_count":applied_count,"first_snapshot":first_snapshot,"first_paused_snapshot":first_paused_snapshot,"latest_probe":latest_probe,"probe":_gate_probe(),"guest_ticks":guest_ticks,"guest_local_mutations":guest_local_mutations,"hold_armed":hold_armed,"hold_observation":hold_observation,"motion_active":not motion.is_empty(),"motion_result":motion_result,"story_ready":session.story.ready,"completed":session.story.state.get("completed",[]),"choices":session.story.state.get("choices",{}),"adapter":session.story.underdeck_action.debug_state() if role=="host" else {},"generation":personal.generation,"personal":personal.personal,"guest_received_count":personal.ledger.guest_received.size(),"pending_receipts":session.store.pending_guest_receipts(str(session.identities.get(_guest_peer(),""))).size() if role=="host" else 0,"host_left_seen":host_left_seen,"notices":notices,"events":received_events,"commands":commands,"ack":ack,"result":result,"errors":errors,"elapsed_ms":Time.get_ticks_msec()-started_msec}
func _write_state(final: bool=false) -> void:
	if not is_instance_valid(session): return
	var state:=_state()
	state.final=final
	var file:=FileAccess.open(evidence.path_join(label+"-state.json"),FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(_json_value(state),"\t"))
	else: push_error("Unable to write underdeck peer evidence")
func _json_value(value):
	if value is Vector3: return [value.x,value.y,value.z]
	if value is Dictionary:
		var mapped: Dictionary={}
		for key in value: mapped[str(key)]=_json_value(value[key])
		return mapped
	if value is Array:
		var mapped: Array=[]
		for item in value: mapped.append(_json_value(item))
		return mapped
	return value
func _bounded_append(items: Array,value: Dictionary) -> void:
	items.append(value)
	if items.size()>64: items.pop_front()
func _fail(message: String) -> void:
	errors.append(message)
	push_error(message)
func _finish(code: int) -> void:
	_write_state(true)
	if is_instance_valid(session): session.network.close()
	get_tree().quit(code)
