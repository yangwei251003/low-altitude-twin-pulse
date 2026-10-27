extends Node
## Explicit QA-only two-process ENet. No injected received packets or cabinet
## success states. Prior27 goals and collision-checked starting poses are fixtures.
## Early observation is not a formal action/reward; both peers must stay reward-free.
const Contract = preload("res://scripts/v3/network/twin_facility_contract.gd")
const Director = preload("res://scripts/v3/gameplay/actions/twin_action_director.gd")
const Cabinet = preload("res://scripts/v3/world/twin_distribution_cabinet.gd")
const Progress = preload("res://scripts/v3/gameplay/actions/twin_distribution_progress.gd")
const LAYOUT := "res://data/v3/terrain/i2_distribution_layout.json"
const COVER := "I2:distribution_cover"
const RELAY := "I2:distribution_relay"
const LOCK := "I2:distribution_lock"
const DISCOVERY := "I2:distribution_back_route"

class PeerSession extends "res://scripts/v3/twin_session.gd":
	var qa_owner
	func _use_ability(peer_id: int, payload: Dictionary) -> void:
		# Observe the real authority operation; never substitute a resolver or
		# change a rejected input to make a scenario continue.
		var actor: Dictionary = entities.get(_actor_id(peer_id), {}).duplicate(true)
		var before: Dictionary = stats.duplicate()
		var cooldown: float = float(cooldowns.get(peer_id, 0.0))
		super._use_ability(peer_id, payload)
		qa_owner.record_ability(self, peer_id, payload, actor, before, cooldown)
	func _note(peer_id: int, message: String) -> void:
		super._note(peer_id, message)
		qa_owner.record_note(peer_id, message)
	func _physics_process(delta: float) -> void:
		qa_owner.hold_bodies(self)
		var before: Dictionary = {"cabinet":distribution.module.snapshot(),"water":clinic.module.snapshot(),"trial":trial.module.snapshot(),"bridge":shared_access.module.snapshot() if shared_access.ready and is_instance_valid(shared_access.module) else {}} if network.mode=="guest" and distribution.ready and clinic.ready and trial.ready and is_instance_valid(trial.module) and is_instance_valid(distribution.module) and is_instance_valid(clinic.module) else {}
		super._physics_process(delta)
		qa_owner.after_tick(self,before)
		qa_owner.advance_crossing(self,delta)
		qa_owner.hold_bodies(self)
	func _process(delta: float) -> void:
		var incoming: Dictionary = pending_packet.duplicate(true)
		super._process(delta)
		if not incoming.is_empty() and received_sequence==int(incoming.get("sequence",-2)):
			qa_owner.applied_snapshot(self,incoming)
		qa_owner.hold_bodies(self)

	func _commit(receipt: String, changes: Dictionary, discovery = "") -> bool:
		var watched: bool = receipt=="distribution-observation" and is_instance_valid(distribution.module)
		var physical: Dictionary = distribution.module.snapshot() if watched else {}
		var before: Dictionary = store.snapshot() if watched else {}
		var accepted: bool = super._commit(receipt,changes,discovery)
		if watched: qa_owner.record_commit(self,accepted,physical,before)
		return accepted

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
var ability_outcomes: Array = []
var authority_notes: Array = []
var reliable_samples: Dictionary = {}
var facility_samples: Dictionary = {}
var guest_bridge_mutations := 0
var water_samples: Dictionary = {}
var trial_samples: Dictionary = {}
var guest_trial_mutations := 0
var observation_commits: Array = []
var movement: Dictionary = {}
var guest_water_mutations := 0
var accepted_msec: Array = []
var first_snapshot: Dictionary = {}
var first_paused_snapshot: Dictionary = {}
var latest_probe: Dictionary = {}
var applied_count := 0
var guest_ticks := 0
var guest_local_mutations := 0
var started_msec := 0
var host_left_seen := false
var initial_profile_id := ""
var initial_personal: Dictionary = {}
var initial_world: Dictionary = {}
var last_controller_heartbeat := 0.0
var entry_kind := ""
var _started := false
var _launch_args: PackedStringArray = []
var _launch_config: Dictionary = {}

## No writes, Session creation or sockets. Both source entries share one root.
static func preflight(args: PackedStringArray, kind: String) -> Dictionary:
	if kind not in ["source_main", "package_main"]:
		return {"ok":false, "code":"invalid_entry_kind"}
	if (kind == "package_main") == OS.has_feature("editor"):
		return {"ok":false, "code":"entry_runtime_mismatch"}
	var fields: Dictionary = {"--qa-suite":"suite", "--qa-profile":"profile", "--qa-distribution-role":"role", "--qa-distribution-label":"label", "--qa-distribution-run":"run_id", "--qa-distribution-evidence":"evidence", "--qa-distribution-sha":"expected_sha"}
	var config: Dictionary = {"reconnect":false}
	var seen: Dictionary = {}
	for argument in args:
		if argument == "--qa-distribution-reconnect":
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
	if config.suite != "distribution-lan" or config.role not in ["host", "guest"]:
		return {"ok":false, "code":"invalid_suite_or_role"}
	var run_pattern := RegEx.new()
	run_pattern.compile("^[0-9]{8}_[0-9]{6}_[0-9]{6}$")
	if run_pattern.search(str(config.run_id)) == null: return {"ok":false, "code":"invalid_run_id"}
	var wanted_label: String = "host" if config.role == "host" else ("guest_reconnect" if config.reconnect else "guest_first")
	var wanted_profile: String = "qa_distribution_lan_" + str(config.role) + "_" + str(config.run_id)
	if config.label != wanted_label or config.profile != wanted_profile or (config.reconnect and config.role != "guest"):
		return {"ok":false, "code":"profile_role_run_mismatch"}
	if config.profile != str(config.profile).validate_filename(): return {"ok":false, "code":"invalid_profile"}
	var runtime_root: String = OS.get_executable_path().get_base_dir() if kind == "package_main" else ProjectSettings.globalize_path("res://")
	var required_path: String = _normalized_path(runtime_root.path_join("artifacts/v3/network/distribution").path_join(str(config.run_id)))
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
	if controller.get("run_id") != config.run_id or controller.get("lock_held") != true or controller.get("distribution_sha256") != config.expected_sha: return false
	if controller.get("qa_suite") != "distribution-lan" or controller.get("entry_kind") != config.entry_kind or controller.get("evidence") != config.evidence: return false
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
	var verified: Dictionary = preflight(_launch_args,entry_kind)
	if not verified.ok:
		_fail("deferred preflight: "+str(verified.code))
		_finish(2)
		return
	session = PeerSession.new()
	session.qa_owner = self
	add_child(session)
	if not session.profile_ready or session.network.PROTOCOL!=21:
		_fail("isolated profile and protocol21 required")
		_finish(2)
		return
	session.inputs.set_process(false)
	session.inputs.set_physics_process(false)
	session.frame_id = "hx02" if role=="guest" else "tr01"
	session.network.status_changed.connect(func(message): _bounded_append(notices,{"text":message,"time_ms":Time.get_ticks_msec()-started_msec}))
	session.network.event_received.connect(_network_event)
	var saved: Dictionary = session.store.snapshot()
	initial_profile_id = str(saved.profile_id)
	initial_personal = saved.personal.duplicate(true)
	initial_world = saved.world.duplicate(true)
	if not session.start_flight(role,"127.0.0.1"):
		_fail("production start failed")
		_finish(2)
		return
	if role=="host" and not _seed_prerequisites():
		_fail("explicit previous27 fixture or I2 travel failed")
		_finish(2)
		return
	var timer := Timer.new()
	timer.wait_time = 0.05
	timer.timeout.connect(_poll)
	add_child(timer)
	timer.start()
	print("DISTRIBUTION_QA_READY "+JSON.stringify({"qa_suite":"distribution-lan","entry_kind":entry_kind,"run_id":run_id,"profile":profile,"resource_layout_sha256":expected_sha}))
	_write_state()

func _seed_prerequisites() -> bool:
	var legacy = Director.new()
	if not legacy.load_definitions(Director.DEFAULT_PATH,["res://data/v3/actions/whale_action.json","res://data/v3/actions/crown_action.json","res://data/v3/actions/underdeck_action.json"]).ok: return false
	var state: Dictionary = legacy.default_state()
	for action in legacy.definitions().actions:
		for objective in action.objectives:
			var matcher: Dictionary = objective.events[0]
			var event := {"id":"qa-distribution-predecessor:"+str(objective.id),"type":matcher.type,"target_id":matcher.target_id,"option":matcher.options[0]}
			var next: Dictionary = legacy.apply_event(state,event,{"is_authority":true,"validated":true,"region_id":action.region_id})
			if not next.get("changed",false): return false
			state = next.state
	if state.completed.size()!=27 or not session.story.director.validate_state(state).ok: return false
	if not session.store.commit({"id":"qa-distribution-seven-actions-fixture","set":{"world.actions.opening":state,"world.flags":state.flags,"world.completed_objectives":state.completed},"append":{"personal.discoveries":state.discoveries}}).ok: return false
	session.world_cache = session.store.snapshot()
	if not session._load_region("I1"): return false
	session.consensus.configure([1],int(session.world_cache.world_revision))
	session._ui_action("travel_to",{"region_id":"I2"})
	hold_bodies(session)
	return session.region_id=="I2" and session.clinic.ready and session.distribution.ready and _place(1,Vector3(17.6,5.75,-10.6))

func hold_bodies(current) -> void:
	for body in current.players.values():
		body.freeze = true
		body.set_process(false)
		body.set_physics_process(false)
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO

func after_tick(current,before: Dictionary) -> void:
	if role=="guest" and not before.is_empty() and is_instance_valid(current.distribution.module) and is_instance_valid(current.clinic.module):
		guest_ticks += 1
		if current.distribution.module.snapshot()!=before.cabinet: guest_local_mutations += 1
		if current.clinic.module.snapshot()!=before.water: guest_water_mutations += 1
		if current.trial.module.snapshot()!=before.trial: guest_trial_mutations += 1
		if not before.bridge.is_empty() and is_instance_valid(current.shared_access.module) and current.shared_access.module.snapshot()!=before.bridge: guest_bridge_mutations += 1

func applied_snapshot(current,packet: Dictionary) -> void:
	if packet.get("region")!="I2": return
	applied_count += 1
	accepted_msec.append(Time.get_ticks_msec())
	if accepted_msec.size()>512: accepted_msec.pop_front()
	var serial: int = current.distribution.applied_serial
	var key: String = str(current.distribution.expected_epoch)+":"+str(serial)
	var reliable: Dictionary = reliable_samples.get(key,{})
	var water_key: String = str(current.clinic.expected_epoch)+":"+str(current.clinic.applied_serial)
	var water_reliable: Dictionary = water_samples.get(water_key,{})
	var trial_key: String=str(current.trial.expected_epoch)+":"+str(current.trial.applied_serial)
	var trial_reliable: Dictionary=trial_samples.get(trial_key,{})
	var trial_actual: Dictionary=current.trial.persistent_state()
	var trial_physics:=true
	if is_instance_valid(current.trial.module):
		var assembly=current.trial.module
		for moving in assembly.link.moving_bodies.values()+assembly.station.selector_bodies.values()+assembly.station.float_bodies.values()+assembly.station.valve_bodies.values():
			var pose: Transform3D=PhysicsServer3D.body_get_state(moving.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
			trial_physics=trial_physics and pose.is_equal_approx(moving.global_transform)
	else: trial_physics=false
	var actual: Dictionary = current.distribution.module.snapshot() if is_instance_valid(current.distribution.module) else {}
	var water: Dictionary = current.clinic.module.snapshot() if is_instance_valid(current.clinic.module) else {}
	var observation := {"sequence":packet.sequence,"paused":packet.paused,"reference_serial":Contract.ref_for_slot(packet.get("facility_refs"),2).get("serial",-1),"applied_serial":serial,"epoch":current.distribution.expected_epoch,"physics_frame":Engine.get_physics_frames(),"probe":_cabinet_probe(),"state_matches_reliable":not reliable.is_empty() and actual==reliable.get("mechanism",{}),"water_matches_reliable":not water_reliable.is_empty() and water==water_reliable.get("mechanism",{}),"trial_ready":current.trial.ready,"trial_matches_reliable":not trial_reliable.is_empty() and trial_actual==trial_reliable,"trial_physics_match":trial_physics,"trial_reference_serial":Contract.ref_for_slot(packet.get("facility_refs"),3).get("serial",-1),"trial_applied_serial":current.trial.applied_serial,"water_ready":current.clinic.ready,"water_applied_serial":current.clinic.applied_serial,"water_reference_serial":Contract.ref_for_slot(packet.get("facility_refs"),1).get("serial",-1)}
	var verified: Dictionary = _facility_proof(current,packet)
	observation["facilities"] = verified.facilities
	observation["all_facilities_match"] = verified.ok
	if not verified.ok and errors.is_empty(): _fail("accepted motion lacks four matching reliable/physical facility states: "+JSON.stringify(verified))
	latest_probe = observation
	if first_snapshot.is_empty(): first_snapshot = observation.duplicate(true)
	if packet.paused and first_paused_snapshot.is_empty(): first_paused_snapshot = observation.duplicate(true)

func _cabinet_probe() -> Dictionary:
	if not session._facilities_ready() or not is_instance_valid(session.distribution.module): return {"ready":false}
	var module = session.distribution.module
	var state: Dictionary = module.snapshot()
	var layout: Dictionary = module.layout()
	var maximum_error := 0.0
	var expected_cover: Vector3 = module.to_global(_v(layout.cover.center)+Vector3.RIGHT*float(state.axis.position_m))
	var expected_door: Vector3 = module.to_global(_v(layout.door.center)+Vector3.UP*float(state.door_fraction)*float(layout.door.travel_m))
	for pair in [[module.cover,expected_cover],[module.door,expected_door]]:
		var body: PhysicsBody3D = pair[0]
		var physical: Transform3D = PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
		maximum_error = maxf(maximum_error,maxf(body.global_position.distance_to(pair[1]),physical.origin.distance_to(pair[1])))
	var target_error := 0.0
	for id in [COVER,RELAY,LOCK]:
		var position: Vector3 = session.entities.get(id,{}).get("position",Vector3.INF)
		target_error = maxf(target_error,position.distance_to(module.entity_position(id)))
	var ray := PhysicsRayQueryParameters3D.create(Vector3(18,2.3,-7.7),Vector3(18,2.3,-10.6),1|8)
	var hit: Dictionary = module.get_world_3d().direct_space_state.intersect_ray(ray)
	var fraction: float = float(state.door_fraction)
	var endpoint_pose: bool = fraction==0.0 or fraction==1.0
	var ray_correct: bool = (not hit.is_empty() and hit.collider==module.door) if fraction==0.0 else hit.is_empty() if fraction==1.0 else true
	var well_ray := PhysicsRayQueryParameters3D.create(Vector3(18,5.5,-11.45),Vector3(18,3.5,-11.45),1|8)
	var well_hit: Dictionary = module.get_world_3d().direct_space_state.intersect_ray(well_ray)
	var proof: Dictionary = {}
	if role=="host":
		for peer in session.players: proof[str(peer)]=module.observe_back(peer,session.players[peer])
	var water: Dictionary = _water_pose()
	return {"ready":true,"authority":module.authority,"state":state,"maximum_pose_error":maximum_error,"target_error":target_error,"door_endpoint":endpoint_pose,"door_ray_correct":ray_correct,"door_hit":str(hit.collider.get_path()) if not hit.is_empty() else "", "well_cover_hit":not well_hit.is_empty() and well_hit.collider==module.cover,"well_clear":well_hit.is_empty(),"proof":proof,"local_ready":session.distribution.ready,"applied_serial":session.distribution.applied_serial,"expected_serial":session.distribution.expected_serial,"epoch":session.distribution.expected_epoch,"water_ready":session.clinic.ready,"water_pose_error":water.error,"water_parts":water.parts}

func _water_pose() -> Dictionary:
	if not session.clinic.ready or not is_instance_valid(session.clinic.module): return {"error":999.0,"parts":0}
	var module = session.clinic.module
	var layout: Dictionary = module.layout()
	var state: Dictionary = module.snapshot()
	var status: Dictionary = module.status()
	var parts: Array = []
	for spec in layout.moving_parts:
		parts.append([module.moving_bodies[spec.id],_v(spec.offset)+Vector3.UP*float(status.deck_top_y)])
	parts.append([module.gravity_valve,_v(layout.gravity_valve.center)+_v(layout.gravity_valve.travel)*float(state.gravity_fraction)])
	parts.append([module.pump_selector,_v(layout.pump_selector.center)+_v(layout.pump_selector.travel)*float(state.pump_fraction)])
	var error := 0.0
	for item in parts:
		var body: PhysicsBody3D = item[0]
		var physical: Transform3D = PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
		error = maxf(error,maxf(body.global_position.distance_to(item[1]),physical.origin.distance_to(item[1])))
	return {"error":error,"parts":parts.size()}

func record_commit(current,accepted: bool,physical: Dictionary,before: Dictionary) -> void:
	var after: Dictionary = current.store.snapshot()
	var envelope: Dictionary = after.world.get("environment",{}).get("I2_distribution",{})
	_bounded_append(observation_commits,{"accepted":accepted,"pose_unchanged":current.distribution.module.snapshot()==physical,"latest_saved":accepted and _disk(envelope.get("mechanism",{}))==_disk(physical),"failed_save_unchanged":not accepted and before==after,"generation_before":before.generation,"generation_after":after.generation,"physical":physical,"history":envelope.get("history",{}),"time_ms":Time.get_ticks_msec()-started_msec})

func advance_crossing(current,delta: float) -> void:
	if role!="host" or not movement.get("active",false): return
	var peer: int = int(movement.peer)
	if not current.players.has(peer):
		movement.active=false
		movement.error="peer_left_during_sweep"
		return
	var body = current.players[peer]
	var target: Vector3 = _v(movement.target)
	var collision: KinematicCollision3D = body.move_and_collide((target-body.global_position).limit_length(minf(delta,0.1)*2.0))
	body.force_update_transform()
	PhysicsServer3D.body_set_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,body.global_transform)
	current.entities[current._actor_id(peer)].position=body.global_position
	movement.steps=int(movement.steps)+1
	movement.actual=_json_value(body.global_position)
	if collision!=null:
		movement.active=false
		movement.error="actual_collision"
		movement.collider=str(collision.get_collider().get_path())
	elif body.global_position.distance_to(target)<0.002:
		movement.active=false
		movement.done=true
		movement.end_clear=_body_clear(peer,body.global_transform)

func _disk(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value,"",true,true))

func _poll() -> void:
	if not _controller_alive() or Time.get_ticks_msec()-started_msec>240000:
		_fail("controller lease expired or four-minute bound reached")
		_finish(2)
		return
	var request: Variant = _read_json(evidence.path_join(label+"-command.json"))
	if request is Dictionary and request.get("run_id")==run_id and int(request.get("sequence",0))>ack:
		# A real player can retry after the first-frame gate. Delay this single
		# scripted input until that same production gate permits it; never bypass it.
		if str(request.get("verb","")) in ["action","g"] and not session._facilities_ready():
			_write_state()
			return
		ack = int(request.sequence)
		var args: Variant = request.get("args",{})
		result = _execute(str(request.get("verb","")),args if args is Dictionary else {})
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
		var payload: Dictionary = args.get("payload",{}).duplicate(true)
		session.network.send_action("ability",payload)
		return {"ok":true,"transport_sequence":session.network._sequence,"dispatch_only":true}
	if verb=="g":
		session.interface.clear_dialogue()
		session.interface.menu.hide()
		var key := InputEventKey.new()
		key.pressed = true
		key.keycode = KEY_G
		key.physical_keycode = KEY_G
		session._unhandled_input(key)
		return {"ok":true,"transport_sequence":session.network._sequence,"method":"actual G through network transport"}
	if verb=="propose_pause":
		session.network.send_action("propose",{"kind":"pause","payload":{}})
		return {"ok":true,"dispatch_only":true}
	if verb=="confirm_vote":
		var proposal: Dictionary = session.consensus.current_proposal() if role=="host" else session.choice_proposal
		if proposal.is_empty(): return {"ok":false,"error":"no received proposal"}
		session.network.send_action("confirm",{"proposal_id":proposal.proposal_id,"world_revision":proposal.world_revision})
		return {"ok":true,"dispatch_only":true}
	if role!="host": return {"ok":false,"error":"host-only fixture"}
	if verb=="place_host": return {"ok":_place(1,_v(args.get("position"))),"fixture":"collision-checked starting pose"}
	if verb=="place_guest": return {"ok":_guest_peer()>0 and _place(_guest_peer(),_v(args.get("position"))),"fixture":"collision-checked starting pose"}
	if verb=="observation_write_failure":
		session.store.failure_point = "before_publish" if bool(args.get("enabled",false)) else ""
		return {"ok":true,"fixture":"host Store publication fault; actual automatic pending retry retained"}
	if verb=="cross_guest":
		var peer: int = _guest_peer()
		var destination: Vector3 = _v(args.get("position"))
		if peer==0 or not destination.is_finite() or movement.get("active",false): return {"ok":false,"error":"invalid_crossing"}
		var clear: bool = _body_clear(peer,session.players[peer].global_transform)
		if not clear: return {"ok":false,"error":"crossing_start_occupied"}
		movement={"active":true,"done":false,"peer":peer,"target":_json_value(destination),"start":_json_value(session.players[peer].global_position),"start_clear":clear,"steps":0,"error":""}
		return {"ok":true,"fixture":"host advances actual guest FlightBody with move_and_collide every physics frame"}

	return {"ok":false,"error":"unknown command"}

func _body_clear(peer: int,at: Transform3D) -> bool:
	if not session.players.has(peer): return false
	var body = session.players[peer]
	var envelope: CollisionShape3D = body.get_node("Envelope")
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape=envelope.shape
	query.transform=at*envelope.transform
	query.collision_mask=1|2|8|32
	query.exclude=[body.get_rid()]
	query.margin=0.0
	return session.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _place(peer: int,point: Vector3) -> bool:
	if not session.players.has(peer) or not point.is_finite(): return false
	var body = session.players[peer]
	var envelope: CollisionShape3D = body.get_node("Envelope")
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = envelope.shape
	query.transform = Transform3D(Basis.IDENTITY,point)*envelope.transform
	query.collision_mask = 1|2|8|32
	query.exclude = [body.get_rid()]
	if not session.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): return false
	body.global_transform = Transform3D(Basis.IDENTITY,point)
	body.safe_position = point
	body.hold_height = point.y
	body.freeze = true
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.force_update_transform()
	PhysicsServer3D.body_set_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,body.global_transform)
	session.entities[session._actor_id(peer)].position = point
	return true

func _guest_peer() -> int: return int(session.network.guests.keys()[0]) if session.network.guests.size()==1 else 0
func _v(raw: Variant) -> Vector3:
	if not raw is Array or raw.size()!=3: return Vector3.INF
	for value in raw:
		if not (value is int or value is float) or not is_finite(float(value)): return Vector3.INF
	return Vector3(raw[0],raw[1],raw[2])

func _network_event(event: Dictionary) -> void:
	_record_facility_event(event)
	if event.get("kind")=="host_left": host_left_seen=true
	if event.get("kind") in ["distribution_state","clinic_state","trial_state"] and event.get("state") is Dictionary:
		var key: String=str(event.get("epoch"))+":"+str(event.get("serial"))
		var destination: Dictionary=reliable_samples if event.kind=="distribution_state" else (water_samples if event.kind=="clinic_state" else trial_samples)
		destination[key]=event.state.duplicate(true)
		while destination.size()>32: destination.erase(destination.keys()[0])
	_bounded_append(received_events,{"kind":event.get("kind"),"epoch":event.get("epoch",0),"serial":event.get("serial",0),"text":event.get("text",""),"time_ms":Time.get_ticks_msec()-started_msec,"reward_ids":event.get("receipts",[]).map(func(item):return item.get("reward_id","")) if event.get("kind")=="receipt_batch" else []})

func record_note(peer_id: int, message: String) -> void:
	_bounded_append(authority_notes, {"peer_id":peer_id, "text":message, "time_ms":Time.get_ticks_msec()-started_msec})

func record_ability(owner_session, peer_id: int, payload: Dictionary, actor_before: Dictionary, stats_before: Dictionary, cooldown_before: float) -> void:
	var actor_after: Dictionary = owner_session.entities.get("player:"+str(peer_id), {})
	var target: Dictionary = owner_session.entities.get(str(payload.get("target_id", "")), {})
	_bounded_append(ability_outcomes, {"peer_id":peer_id, "payload":payload.duplicate(true),
		"accepted":int(owner_session.stats.abilities)==int(stats_before.abilities)+1,
		"rejected":int(owner_session.stats.rejected_abilities)>int(stats_before.rejected_abilities),
		"actor_position":actor_before.get("position"), "target_position":target.get("position"),
		"energy_before":actor_before.get("energy"), "energy_after":actor_after.get("energy"),
		"revision_before":actor_before.get("revision"), "revision_after":actor_after.get("revision"),
		"cooldown_before":cooldown_before, "time_ms":Time.get_ticks_msec()-started_msec})


func _record_facility_event(event: Dictionary) -> void:
	for spec in Contract.DEFINITIONS:
		if event.get("kind") != str(spec.id)+"_state" or not event.get("state") is Dictionary: continue
		var key: String = str(event.get("session_id"))+":"+str(event.get("epoch"))+":"+str(event.get("serial"))
		if not facility_samples.has(spec.id): facility_samples[spec.id] = {}
		var cache: Dictionary = facility_samples[spec.id]
		cache[key] = event.state.duplicate(true)
		while cache.size()>32: cache.erase(cache.keys()[0])

func _facility_proof(current, packet: Dictionary) -> Dictionary:
	var proof: Dictionary = {}
	var all_match: bool = Contract.valid_refs(packet.get("facility_refs")) and current._facilities_ready()
	for spec in Contract.DEFINITIONS:
		var id: String = spec.id
		var adapter = current.get(id)
		if adapter == null:
			proof[id] = {"ready":false,"error":"adapter_missing"}
			all_match = false
			continue
		var reference: Dictionary = Contract.ref_for_slot(packet.get("facility_refs"),int(spec.slot))
		var exists: bool = adapter != null and adapter.ready and is_instance_valid(adapter.module)
		var key: String = str(packet.get("session_id"))+":"+str(adapter.expected_epoch)+":"+str(adapter.applied_serial)
		var reliable: Dictionary = facility_samples.get(id,{}).get(key,{})
		var actual: Dictionary = adapter.persistent_state() if exists else {}
		var bodies: Array = []
		var authored_pose := exists
		if exists:
			var module = adapter.module
			match id:
				"clinic": bodies = module.moving_bodies.values()+[module.gravity_valve,module.pump_selector,module.interlock_bolt]
				"distribution":
					bodies = [module.cover,module.door]
					authored_pose = module._poses_match()
				"trial":
					bodies = module.link.moving_bodies.values()+module.station.selector_bodies.values()+module.station.valve_bodies.values()+module.station.float_bodies.values()
					authored_pose = module.link._poses_match() and module.station._poses_match() and module.connection_status().ok
				"shared_access":
					bodies = module.moving_bodies.values()+module.pin_bodies.values()
					authored_pose = module._poses_match()
		var mismatches: Array = []
		for body in bodies:
			if not is_instance_valid(body) or not body is PhysicsBody3D:
				mismatches.append("missing_physics_body")
				continue
			var pose: Transform3D = PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
			if not pose.is_equal_approx(body.global_transform): mismatches.append(str(body.name))
		var state_matches: bool = exists and not reliable.is_empty() and actual==reliable
		# Clinic/cabinet intentionally allow an older compatible reliable serial;
		# Trial and bridge retain their production exact-reference requirement.
		var reference_matches: bool = reference.get("epoch",-1)==adapter.expected_epoch and adapter.applied_serial>0 and adapter.applied_serial<=int(reference.get("serial",-1))
		if id in ["trial","shared_access"]: reference_matches = reference_matches and adapter.applied_serial==reference.get("serial",-1)
		var physics_match: bool = authored_pose and not bodies.is_empty() and mismatches.is_empty()
		proof[id] = {"ready":exists,"reference_epoch":reference.get("epoch",-1),"reference_serial":reference.get("serial",-1),"epoch":adapter.expected_epoch,"applied_serial":adapter.applied_serial,"reference_matches":reference_matches,"state_matches_reliable":state_matches,"mechanism_matches_reliable":exists and not reliable.is_empty() and actual.get("mechanism",{})==reliable.get("mechanism",{}),"history_matches_reliable":exists and not reliable.is_empty() and actual.get("history",{})==reliable.get("history",{}),"state_differences":_state_differences(actual,reliable) if not state_matches else [],"physics_match":physics_match,"parts":bodies.size(),"mismatches":mismatches}
		all_match = all_match and state_matches and reference_matches and physics_match
	return {"ok":all_match,"facilities":proof}

# Exact comparison above remains the acceptance gate. These bounded leaf diffs
# only explain a failure; they never normalize, omit history, or tolerate drift.
func _state_differences(actual: Variant, expected: Variant) -> Array:
	var differences: Array = []
	_append_state_differences(actual,expected,"$",differences,0)
	return differences

func _append_state_differences(actual: Variant, expected: Variant, path: String, differences: Array, depth: int) -> void:
	if differences.size()>=24: return
	if depth>16:
		differences.append({"path":path,"kind":"diagnostic_depth_limit"})
		return
	if typeof(actual)!=typeof(expected):
		differences.append({"path":path,"kind":"type","actual_type":type_string(typeof(actual)),"expected_type":type_string(typeof(expected)),"actual":actual,"expected":expected})
		return
	if actual==expected: return
	if actual is Dictionary:
		for key in expected:
			if differences.size()>=24: return
			var child: String = path+"/"+str(key)
			if not actual.has(key): differences.append({"path":child,"kind":"missing_actual","expected":expected[key]})
			else: _append_state_differences(actual[key],expected[key],child,differences,depth+1)
		for key in actual:
			if differences.size()>=24: return
			if not expected.has(key): differences.append({"path":path+"/"+str(key),"kind":"unexpected_actual","actual":actual[key]})
	elif actual is Array:
		if actual.size()!=expected.size(): differences.append({"path":path,"kind":"array_size","actual":actual.size(),"expected":expected.size()})
		for index in range(mini(actual.size(),expected.size())):
			if differences.size()>=24: return
			_append_state_differences(actual[index],expected[index],path+"/"+str(index),differences,depth+1)
	else:
		differences.append({"path":path,"kind":"value","actual":actual,"expected":expected})

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
	var stored: Dictionary=session.store.snapshot()
	var history: Dictionary=session.distribution.progress.snapshot() if session.distribution.ready else {}
	var saved_envelope: Dictionary=stored.world.get("environment",{}).get("I2_distribution",{}) if role=="host" else {}
	var cadence: Dictionary={"count":accepted_msec.size(),"span_ms":0,"mean_gap_ms":0.0,"max_gap_ms":0}
	if accepted_msec.size()>1:
		cadence.span_ms=int(accepted_msec[-1])-int(accepted_msec[0])
		cadence.mean_gap_ms=float(cadence.span_ms)/float(accepted_msec.size()-1)
		for index in range(1,accepted_msec.size()): cadence.max_gap_ms=maxi(cadence.max_gap_ms,int(accepted_msec[index])-int(accepted_msec[index-1]))
	return {"qa_scripted":true,"qa_suite":"distribution-lan","entry_kind":entry_kind,"resource_layout_sha256":expected_sha,"role":role,"label":label,"run_id":run_id,"profile":profile,"profile_id":initial_profile_id,"initial_personal":initial_personal,"personal_world_unchanged":stored.world==initial_world,"protocol":session.network.PROTOCOL,"network_mode":session.network.mode,"active":session.active,"region":session.region_id,"session_id":session.network.session_id if role=="host" else session.received_session,"peer_id":session.network.local_id(),"players":roster,"stats":session.stats.duplicate(),"transport":session.network.telemetry.duplicate(),"paused":session.simulation_paused,"proposal":session.consensus.current_proposal() if role=="host" else session.choice_proposal,"received_sequence":session.received_sequence,"applied_count":applied_count,"cadence":cadence,"first_snapshot":first_snapshot,"first_paused_snapshot":first_paused_snapshot,"latest_probe":latest_probe,"probe":_cabinet_probe(),"guest_ticks":guest_ticks,"guest_bridge_mutations":guest_bridge_mutations,"guest_local_mutations":guest_local_mutations,"guest_water_mutations":guest_water_mutations,"guest_trial_mutations":guest_trial_mutations,"story_ready":session.story.ready,"completed":session.story.state.get("completed",[]),"history":history,"pending_observation":session.distribution.has_pending_observation(),"pending_history":session.distribution.pending_observation.get("history",{}),"adapter_error":session.distribution.error,"saved_envelope":saved_envelope,"observation_commits":observation_commits,"movement":movement,"generation":stored.generation,"personal":stored.personal,"guest_received_count":stored.ledger.guest_received.size(),"pending_receipts":session.store.pending_guest_receipts(str(session.identities.get(_guest_peer(),""))).size() if role=="host" else 0,"host_left_seen":host_left_seen,"notices":notices,"events":received_events,"ability_outcomes":ability_outcomes,"authority_notes":authority_notes,"commands":commands,"ack":ack,"result":result,"errors":errors,"elapsed_ms":Time.get_ticks_msec()-started_msec}

func _write_state(final: bool=false) -> void:
	if not is_instance_valid(session): return
	var state: Dictionary = _state()
	state.final = final
	var file := FileAccess.open(evidence.path_join(label+"-state.json"),FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(_json_value(state),"\t"))
	else: _fail("Unable to write distribution peer evidence")

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
