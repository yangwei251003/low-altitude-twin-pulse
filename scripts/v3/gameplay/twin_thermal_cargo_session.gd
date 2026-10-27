extends RefCounted
## I3 one-load journey. Original player Flight, Custody, PinJoint, Pilot and
## DockLift own all actual forces/attachment/contact. No second save or Rules.
const Flight = preload("res://scripts/v2/flight_body.gd")
const Custody = preload("res://scripts/v3/gameplay/canal/canal_transport_physics/cargo_custody.gd")
const DockLift = preload("res://scripts/v3/gameplay/canal/canal_transport_physics/dock_lift.gd")
const Pilot = preload("res://scripts/v3/gameplay/canal/canal_transport_physics/transport_pilot.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
const CARGO := "I3:loaded_cassette"
const LOW := "I3:low_dock"
const HIGH := "I3:high_dock"
const FACT := "I3:loaded_dock_verified"
const MASK := 1|2|4|8|32
const LOW_POINT := Vector3(-10,2.55,18)
const HIGH_POINT := Vector3(17,11.45,-3)
const OUTER := [Vector3(-20,6,18),Vector3(-24,12,5),Vector3(8,14,5)]
const UPDRAFT := AABB(Vector3(-3,2,3),Vector3(6,12,6))
const SAVE_KEYS := ["version","cargo_id","custody","cargo_pose","linear_velocity","angular_velocity","operation_serial","proof"]
const PROGRESS_KEYS := ["version","cargo_id","role_identity","custody","joint","cargo","carrier","flight","operation_serial","journey"]
const FLIGHT_SCALARS := ["battery","heat","heading","hold_height","shield_left","shield_cooldown","recovery_left","ability_left","ability_cooldown","flight_seconds","damage_taken","max_altitude","water_seconds","crash_seconds","collision_damage_scale"]
var session
var ready := false
var error := ""
var _world: Node3D
var _cargo: RigidBody3D
var _berths: Dictionary = {}
var _carriers: Dictionary = {}
var _peers: Dictionary = {}
var _custody
var _last_frame := -1
var _operation_serial := 0
var _journey: Dictionary = {}
var _proof: Dictionary = {}
var _release_route := ""
var _release_serial := 0
var _assist: Dictionary = {}
var _fields: Dictionary = {}
var _owned_joint: WeakRef
var _owned_carrier: WeakRef
var _restore: Dictionary = {}
var _restoring := false
var _suspended: Dictionary = {}
var _disconnect_request: Dictionary = {}
var _capture_diagnostic: Dictionary = {}
var _pause_request: Dictionary = {}
var _pause_error := ""
var _physics_paused := false
var _pause_saved: Dictionary = {}
var _pause_bodies: Array = []
var _pause_resume_count := 0

## Root calls this BEFORE World.definitions is copied into Session.entities.
## Replaces the unique placeholder at its existing ID, not a shadow cargo.
static func install(world: Node3D) -> Dictionary:
	if not is_instance_valid(world) or not world.is_inside_tree() or world.get("region_id") != "I3" or not world.has_method("_entity"): return {"ok":false,"code":"live_i3_factory_required"}
	if world.has_meta("thermal_cargo_installed"):
		return {"ok":world.objects.get(CARGO) is RigidBody3D,"code":"already_installed"}
	if not world.objects.has(CARGO) or not world.objects.has(HIGH) or world.objects.has(LOW): return {"ok":false,"code":"unique_existing_targets_required"}
	var old: Variant = world.objects[CARGO]
	var high: Variant = world.objects[HIGH]
	if not old is PhysicsBody3D or not high is StaticBody3D or old.get_parent() != world or high.get_parent() != world: return {"ok":false,"code":"owned_placeholder_required"}
	var old_definition: Dictionary = world.definitions.get(CARGO,{}).duplicate(true)
	var cargo := RigidBody3D.new()
	cargo.name = "loaded_cassette"
	cargo.mass = 2.0
	cargo.can_sleep = false
	cargo.continuous_cd = true
	cargo.contact_monitor = true
	cargo.max_contacts_reported = 16
	cargo.collision_layer = 8
	cargo.collision_mask = MASK
	var physical := PhysicsMaterial.new()
	physical.friction = .55
	physical.bounce = 0.0
	cargo.physics_material_override = physical
	_box(cargo,Vector3(.4,.4,.4),Color("c1a367"))
	cargo.set_meta("entity_id",CARGO)
	for child in old.get_children():
		if child is Label3D: world._labels.erase(child)
	world.remove_child(old)
	old.free()
	world.add_child(cargo)
	cargo.position = Vector3(-10,3,18)
	world._label(cargo,"检修吊载匣 · G挂接/落架",Vector3(0,.9,0),Color("dac39c"),23)
	world._base_object_materials[CARGO] = cargo.get_node("Shape").material_override
	world.objects[CARGO] = cargo
	world.initial_transforms[CARGO] = cargo.transform
	old_definition.merge({"id":CARGO,"name":"检修吊载匣 · G挂接/落架","position":cargo.position,"tags":["movable","fieldable"],"owner":"neutral","revision":0},true)
	world.definitions[CARGO] = old_definition
	high.position = HIGH_POINT
	for child in high.get_children():
		if child is CollisionShape3D:
			var shape := BoxShape3D.new()
			shape.size = Vector3(2,.5,2)
			child.shape = shape
			child.transform = Transform3D.IDENTITY
		elif child is MeshInstance3D and child.mesh is BoxMesh:
			var mesh := BoxMesh.new()
			mesh.size = Vector3(2,.5,2)
			child.mesh = mesh
	world.initial_transforms[HIGH] = high.transform
	world.definitions[HIGH].position = HIGH_POINT
	world._entity("low_dock","低泊位 · 机腹对准后G挂接",LOW_POINT,Vector3(2,.5,2),["mechanical"],{},Color("6e8e99"))
	var stand := StaticBody3D.new()
	stand.name = "ThermalCargoLowStand"
	stand.position = Vector3(-10,1.15,18)
	stand.collision_layer = 1
	stand.collision_mask = MASK
	_box(stand,Vector3(1.4,2.3,1.4),Color("596d77"))
	world.add_child(stand)
	world.set_meta("thermal_cargo_installed",true)
	return {"ok":true,"code":"unique_cargo_and_berths_installed","cargo_id":CARGO,"low_id":LOW,"high_id":HIGH}

func setup(owner_session) -> void:
	if session == owner_session: return
	clear()
	session = owner_session

func bind_world() -> Dictionary:
	if _custody != null: return _no("already_bound_clear_first")
	if not _live_host(): return _no("host_live_i3_required")
	var world: Node3D = session.world
	if not world.objects.get(CARGO) is RigidBody3D or not world.objects.get(LOW) is StaticBody3D or not world.objects.get(HIGH) is StaticBody3D: return _no("installed_cargo_and_berths_required")
	var carriers: Dictionary = {}
	var peers: Dictionary = {}
	for peer in session.players:
		var body: Variant = session.players[peer]
		if not body is Flight or not is_instance_valid(body) or not body.enabled or body.get_world_3d().space != world.get_world_3d().space: continue
		var id := "pilot:"+str(peer)
		carriers[id] = body
		peers[peer] = id
	if carriers.is_empty() or carriers.size() > 2: return _no("one_or_two_current_players_required")
	var candidate = Custody.new()
	var berths := {LOW:world.objects[LOW],HIGH:world.objects[HIGH]}
	var configured: Dictionary = candidate.configure({CARGO:world.objects[CARGO]},berths,carriers,true)
	if not configured.ok: return _no("custody_configure:"+str(configured.code))
	_world = world
	_cargo = world.objects[CARGO]
	_berths = berths
	_carriers = carriers
	_peers = peers
	_custody = candidate
	ready = false # Initial support is still observed on actual physics frames.
	return _yes("bound_waiting_actual_support")

func clear() -> void:
	_stop_assist()
	_clear_fields()
	# This is teardown only, never a logistics completion or docking operation.
	# Remove exactly our still-owned joint, then restore the original Flight list.
	var carrier: Variant = _owned_carrier.get_ref() if _owned_carrier != null else null
	var joint: Variant = _owned_joint.get_ref() if _owned_joint != null else null
	if carrier is Flight and is_instance_valid(carrier) and is_instance_valid(_cargo) and carrier.cargo_items.has(CARGO):
		var item: Dictionary = carrier.cargo_items[CARGO]
		if item.body == _cargo and is_instance_valid(joint) and item.joint == joint:
			joint.free()
			carrier.release_cargo(CARGO)
	# On disconnect the old Flight may already be gone; the exact weak-owned
	# joint can still be a sibling in Session. Never leave that orphan behind.
	if is_instance_valid(joint): joint.free()
	_owned_joint = null
	_owned_carrier = null
	_custody = null
	_world = null
	_cargo = null
	_berths.clear()
	_carriers.clear()
	_peers.clear()
	_journey.clear()
	_proof.clear()
	_assist.clear()
	_restore.clear()
	_restoring = false
	_suspended.clear()
	_disconnect_request.clear()
	_capture_diagnostic.clear()
	_pause_request.clear()
	_pause_error = ""
	_physics_paused = false
	_pause_saved.clear()
	_pause_bodies.clear()
	_pause_resume_count = 0
	_release_route = ""
	_release_serial = 0
	_last_frame = -1
	_operation_serial = 0
	ready = false
	error = ""

## Root calls once AFTER ordinary input commands, before the next physics step.
## This module applies its bounded updraft once; Root must not add it again.
func advance(delta: float) -> Dictionary:
	if not _bound_host(): return _no("host_live_bound_i3_required")
	if not is_finite(delta) or delta < 0.0 or delta > .1: return _no("invalid_physics_delta")
	if delta == 0.0: return _yes("zero_delta")
	var frame: int = Engine.get_physics_frames()
	if frame == _last_frame: return _no("same_physics_frame")
	_last_frame = frame
	if _physics_paused:
		if not _journey.is_empty(): _journey.last_frame = frame
		return _yes("native_cargo_pause_held_no_credit")
	if not _pause_request.is_empty():
		_pause_request.frames = int(_pause_request.frames)+1
		if int(_pause_request.frames) > 1200:
			_pause_error = "pause_native_snapshot_timeout:"+str(_pause_request.code)
			_pause_request.clear()
	if not _suspended.is_empty(): return _yes("carried_role_suspended_waiting_same_identity")
	if session.simulation_paused:
		_stop_assist()
		_clear_fields()
		if _restoring: _custody.restore_docked_fresh(_restore.custody,true,true)
		else: _custody.set_paused(true,true)
		if not _journey.is_empty(): _journey.last_frame = frame
		return _yes("paused")
	if not _restoring: _custody.set_paused(false,true)
	if _restoring:
		var restored: Dictionary = _custody.restore_docked_fresh(_restore.custody,true,false)
		if not restored.ok:
			if str(restored.code) in ["restore_support_pending","restore_stability_pending"]: return _yes(str(restored.code))
			return _no("docked_restore:"+str(restored.code))
		_proof = _restore.proof.duplicate(true)
		_operation_serial = int(_restore.operation_serial)
		_restoring = false
		_restore.clear()
		ready = true
		_sync_entity()
		_service_pause_request()
		return _yes("docked_restored_without_new_receipt")
	if not _disconnect_request.is_empty(): _stop_assist()
	var row: Dictionary = _row()
	if row.phase == "free":
		var first_seat: Dictionary = _custody.seat(CARGO,LOW,int(_custody.last_serial)+1,int(_custody.revision))
		if not first_seat.ok:
			ready = false
			return _yes("waiting_initial_support:"+str(first_seat.code))
	var observed: Dictionary = _custody.step(delta,true,false)
	if not observed.ok: return _no("custody_step:"+str(observed.code))
	row = _row()
	if row.phase == "fault": _clear_fields(); _stop_assist(); ready = false; return _no("custody_fault:"+str(row.fault))
	ready = row.phase in ["docked","carried","dropping"]
	if row.phase == "carried": _observe_route(frame)
	_apply_updraft()
	_advance_assist(delta)
	for change in observed.changes:
		if change.get("cargo_id") == CARGO and change.get("phase") == "docked" and int(change.get("serial",0)) == _release_serial and row.berth == HIGH and not _release_route.is_empty() and _proof.is_empty():
			_proof = {"version":1,"cargo_id":CARGO,"pickup_serial":int(_journey.pickup_serial),"release_serial":_release_serial,
				"completed_serial":int(row.completed_serial),"route":_release_route,"frames_observed":int(_journey.frames_observed),
				"outer_progress":int(_journey.outer_progress),"updraft_ticks":int(_journey.updraft_ticks),"updraft_rise_mm":int(_journey.updraft_rise_mm)}
	_sync_entity()
	_service_pause_request()
	if not _disconnect_request.is_empty():
		_disconnect_request.frames = int(_disconnect_request.frames)+1
		var captured: Dictionary = suspend_for_disconnect(_disconnect_request.peer)
		if captured.ok:
			_disconnect_request.clear()
			error = ""
			return _yes("disconnect_captured_at_actual_physics_boundary")
		_disconnect_request.code = str(captured.code)
		if int(_disconnect_request.frames) >= 30: return _no("disconnect_capture_pending_timeout:"+str(captured.code))
	return _yes("observed_actual_cargo")

func operate(peer, target: String) -> Dictionary:
	if target not in [CARGO,LOW,HIGH]: return {"handled":false,"ok":false,"code":"not_thermal_cargo"}
	if not _bound_host() or not ready or _restoring or session.simulation_paused: return _operation_no("cargo_not_ready")
	if not _proof.is_empty(): return {"handled":true,"ok":true,"code":"already_delivered"}
	if not _peers.has(peer) or not _actor_near(peer,target): return _operation_no("actor_or_target_not_near")
	if not _assist.is_empty(): return _operation_no("local_assistance_in_progress")
	var row: Dictionary = _row()
	var actor: Flight = _carriers[_peers[peer]]
	if row.phase == "docked":
		if target != CARGO: return _operation_no("aim_at_cassette_to_pickup")
		var picked: Dictionary = _pickup(peer)
		if picked.ok: return {"handled":true,"ok":true,"code":"actual_joint_attached"}
		if picked.code == "grip_too_far":
			var alignment = Pilot.new()
			_operation_serial += 1
			if alignment.bind(actor) and alignment.go_to_pickup_alignment(_cargo,_operation_serial):
				_assist = {"kind":"pickup_alignment","peer":peer,"pilot":alignment,"frames":0}
				return {"handled":true,"ok":true,"code":"bounded_empty_hook_alignment_started"}
		return _operation_no("pickup:"+str(picked.code))
	if row.phase != "carried" or row.carrier != _peers[peer]: return _operation_no("not_your_carried_load")
	var destination := target if target in [LOW,HIGH] else _near_berth()
	if destination.is_empty(): return _operation_no("move_slowly_above_a_berth")
	var release: Dictionary = _release(destination)
	if release.ok: return {"handled":true,"ok":true,"code":"actual_joint_released_waiting_contact"}
	var approach = DockLift.new()
	_operation_serial += 1
	var begun: Dictionary = approach.begin_approach(actor,_berths[destination],_operation_serial,true)
	if begun.ok:
		_assist = {"kind":"approach_release","peer":peer,"dock":approach,"destination":destination,"frames":0}
		return {"handled":true,"ok":true,"code":"bounded_loaded_approach_started"}
	# Pilot arrival allows a .3m/s load, whereas original DockLift requires
	# .2m/s and Custody release requires .12m/s. A local G request can wait for
	# the real pendulum to settle; it never turns arrival into release credit.
	if str(begun.code) in ["carrier_not_settled","load_not_settled"] and _settle_column(destination,release):
		_assist = {"kind":"settle_release","peer":peer,"destination":destination,"frames":0,"height":actor.global_position.y}
		_brake_assist(actor,float(_assist.height))
		return {"handled":true,"ok":true,"code":"bounded_release_waiting_actual_settle"}
	return _operation_no("release:"+str(release.code)+";approach:"+str(begun.code))

func fact(target: String) -> String:
	return str(_proof.get("route","")) if target == FACT and _bound_host() and ready and not _restoring else ""

func status() -> Dictionary:
	return {"bound":_custody != null,"ready":ready,"restoring":_restoring,"error":error,"custody":_custody.report() if _custody != null else {},
		"assist":str(_assist.get("kind","")),"journey":_journey.duplicate(true),"proof":_proof.duplicate(true),"suspended_role":str(_suspended.get("state",{}).get("role_identity","")),"disconnect_pending":not _disconnect_request.is_empty(),"capture_diagnostic":_capture_diagnostic.duplicate(true),"pause":pause_request_status(),"save_scope":"native_docked_v1_or_carried_v2"}

func owns_target(target: String) -> bool:
	return target in [CARGO,LOW,HIGH] and _custody != null

func save_state() -> Dictionary:
	if not _bound_host() or _restoring: return _no("docked_save_not_ready")
	if _physics_paused: return {"ok":true,"code":"cached_native_pause_candidate","state":_pause_saved.duplicate(true)}
	if not _suspended.is_empty(): return {"ok":true,"code":"suspended_original_carried_candidate","state":_suspended.state.duplicate(true)}
	if not _assist.is_empty(): return _no("local_assistance_in_progress")
	if _row().get("phase") == "carried": return _capture_progress()
	var checkpoint: Dictionary = _custody.docked_snapshot()
	if checkpoint.is_empty(): return _no("in_transit_save_not_supported:"+str(_row().get("phase","")))
	var row: Dictionary = checkpoint.cargos[CARGO]
	if not _custody.support_info(CARGO,str(row.berth)).get("supported",false): return _no("actual_docked_support_required")
	var state := {"version":1,"cargo_id":CARGO,"custody":checkpoint,"cargo_pose":_pose(_cargo.global_transform),
		"linear_velocity":_xyz(_cargo.linear_velocity),"angular_velocity":_xyz(_cargo.angular_velocity),"operation_serial":_operation_serial,"proof":_proof.duplicate(true)}
	var valid: Dictionary = _validate_save(state)
	return {"ok":true,"code":"docked_checkpoint_only","state":state} if valid.ok else valid

## Fresh bind only. Pose/velocity restoration is explicit construction work;
## it never imports contact credit. advance() must re-observe native 350ms.
func restore_docked_state(state: Dictionary) -> Dictionary:
	if not _bound_host() or _last_frame != -1 or _restoring or int(_custody.revision) != 0 or int(_custody.last_serial) != 0: return _no("fresh_bound_restore_required")
	var valid: Dictionary = _validate_save(state)
	if not valid.ok: return valid
	_cargo.global_transform = _transform(state.cargo_pose)
	_cargo.linear_velocity = _vector(state.linear_velocity)
	_cargo.angular_velocity = _vector(state.angular_velocity)
	_cargo.freeze = false
	_cargo.force_update_transform()
	PhysicsServer3D.body_set_state(_cargo.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,_cargo.global_transform)
	_restore = state.duplicate(true)
	_restoring = true
	ready = false
	return {"ok":true,"code":"docked_restore_pending_actual_support","pending":true}

func restore_state(state: Dictionary) -> Dictionary:
	return restore_carried_state(state) if state.get("version") == 2 else restore_docked_state(state)

## A hint for Root's spawning order, never permission to accept a snapshot.
## Root must use its own profile identity and configure this exact legal build
## before bind_world/restore_state; saved transient peer IDs are never roles.
static func required_roles(state: Dictionary) -> Array:
	if state.get("version") != 2 or not _identity_valid(state.get("role_identity")) or not state.get("flight") is Dictionary or not state.flight.get("build") is Dictionary: return []
	if not Catalog.resolve_build(state.flight.build).valid: return []
	return [{"identity":str(state.role_identity),"build":state.flight.build.duplicate(true)}]

func sync_roster() -> Dictionary:
	if not _bound_host(): return _no("host_live_bound_i3_required")
	if not _suspended.is_empty(): return _yes("same_role_remap_required")
	var next: Dictionary = _current_roster()
	if not next.ok: return next
	var row: Dictionary = _row()
	if row.phase == "carried" and (not next.carriers.has(row.carrier) or next.carriers[row.carrier] != _carriers.get(row.carrier)):
		return _no("carried_disconnect_must_capture_before_old_body_free")
	_carriers = next.carriers
	_peers = next.peers
	_custody._carriers.clear()
	for id in _carriers: _custody._carriers[id] = weakref(_carriers[id])
	return _yes("actual_roster_synchronized")

## Host disconnect hook BEFORE Session removes or queues the original Flight.
## Root commits returned state through its existing Store transaction. No IO
## or new ledger is owned here. cancel_disconnect resumes a rejected commit.
func suspend_for_disconnect(peer) -> Dictionary:
	if not _bound_host() or not _suspended.is_empty() or not _peers.has(peer) or _row().get("carrier") != _peers[peer]: return _no("current_carried_role_required")
	if _physics_paused:
		var held: Dictionary = _paused_readback()
		if not held.ok: return held
	var captured: Dictionary = save_state()
	if not captured.ok or captured.state.get("version") != 2: return captured if not captured.ok else _no("actual_carried_snapshot_required")
	var actor: Flight = _carriers[_peers[peer]]
	_suspended = {"state":captured.state.duplicate(true),"actor":weakref(actor),"actor_frozen":actor.freeze,"cargo_frozen":_cargo.freeze}
	_clear_fields()
	actor.freeze = true
	_cargo.freeze = true
	ready = false
	return {"ok":true,"code":"original_role_suspended_no_credit","state":captured.state}

## Network callbacks can arrive between native integration and Node sync.
## Keep the original player alive; capture on advance, never patch its pose.
func request_suspend_for_disconnect(peer) -> Dictionary:
	if not _bound_host() or not _suspended.is_empty() or not _peers.has(peer) or _row().get("carrier") != _peers[peer]: return _no("current_carried_role_required")
	if not _disconnect_request.is_empty(): return {"ok":_disconnect_request.peer == peer,"pending":true,"code":"disconnect_capture_already_requested"}
	_disconnect_request = {"peer":peer,"frames":0,"code":"waiting_actual_physics_boundary"}
	return {"ok":true,"pending":true,"code":"waiting_actual_physics_boundary"}

func disconnect_state() -> Dictionary:
	if not _suspended.is_empty(): return {"ok":true,"pending":false,"code":"original_role_suspended_no_credit","state":_suspended.state.duplicate(true)}
	if not _disconnect_request.is_empty(): return {"ok":false,"pending":true,"code":str(_disconnect_request.code),"frames":int(_disconnect_request.frames)}
	return {"ok":false,"pending":false,"code":"no_disconnect_candidate"}

## Root retains the existing Consensus proposal until ready. Call before the
## generic Session pause flag/freezer; requests never install a callback or
## patch Node/PhysicsServer transforms to manufacture a coherent snapshot.
func request_pause() -> Dictionary:
	if not _bound_host(): return _no("pause_requires_actual_bound_i3_helper")
	if _physics_paused: return {"ok":true,"ready":true,"pending":false,"paused":true,"code":"already_native_paused"}
	if session.simulation_paused: return _no("request_before_generic_physics_freeze_required")
	if not _suspended.is_empty() or not _disconnect_request.is_empty(): return _no("disconnect_role_transition_in_progress")
	if _pause_request.is_empty():
		_pause_error = ""
		_pause_request = {"frames":0,"code":"waiting_actual_physics_snapshot"}
	return {"ok":true,"ready":false,"pending":true,"paused":false,"code":str(_pause_request.code)}

func pause_request_status() -> Dictionary:
	return {"ok":_pause_error.is_empty(),"ready":_physics_paused,"pending":not _pause_request.is_empty(),"paused":_physics_paused,"failed":not _pause_error.is_empty(),
		"code":_pause_error if not _pause_error.is_empty() else ("native_snapshot_frozen" if _physics_paused else str(_pause_request.get("code","idle"))),"frames":int(_pause_request.get("frames",0)),"resume_count":_pause_resume_count}

func paused_saved_state() -> Dictionary:
	if not _bound_host() or not _physics_paused or _pause_saved.is_empty(): return _no("no_actual_native_pause_candidate")
	return {"ok":true,"code":"cached_native_pause_candidate","state":_pause_saved.duplicate(true)}

func set_paused(value: bool) -> Dictionary:
	if not _bound_host(): return _no("pause_requires_actual_bound_i3_helper")
	if value: return {"ok":true,"ready":true,"pending":false,"paused":true,"code":"already_native_paused"} if _physics_paused else request_pause()
	_pause_request.clear()
	_pause_error = ""
	if not _physics_paused: return _yes("already_native_running_no_momentum_write")
	var checked: Dictionary = _paused_readback()
	if not checked.ok: return checked
	for record in _pause_bodies:
		var body: RigidBody3D = record.body.get_ref()
		body.freeze = bool(record.was_frozen)
		if not body.freeze: _write_momentum(body,record.physical)
	_physics_paused = false
	_pause_resume_count += 1
	_pause_saved.clear()
	_pause_bodies.clear()
	_last_frame = Engine.get_physics_frames()
	if not _journey.is_empty():
		_journey.last_frame = _last_frame
		var actor: Flight = _carriers.get(str(_row().carrier))
		if is_instance_valid(actor): _journey.last_mm = _mm(actor.global_position)
	ready = _row().phase in ["docked","carried","dropping"]
	return _yes("native_momentum_resumed_once_no_pose_write")

func _paused_readback() -> Dictionary:
	# Validate every original identity before any body resumes. An unrelated
	# replacement role cannot inherit frozen bodies or cached native momentum.
	for record in _pause_bodies:
		var body: Variant = record.body.get_ref()
		if not is_instance_valid(body) or not body is RigidBody3D or not body.is_inside_tree() or body.get_world_3d().space != _world.get_world_3d().space or not body.freeze or not _physical_tree_equal(record.physical.contract,_shape_contract(body)):
			return _no("paused_body_missing_changed_or_unfrozen")
		if body == _cargo:
			if _world.objects.get(CARGO) != body: return _no("paused_original_cargo_changed")
		elif not session.players.values().has(body): return _no("paused_original_role_changed")
		var pose: Transform3D = PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
		var expected: Transform3D = _transform(record.physical.native_pose)
		if not pose.basis.is_equal_approx(expected.basis) or not _f32_equal(_xyz(pose.origin),_xyz(expected.origin)): return _no("paused_body_was_moved")
	return _yes("original_paused_bodies_unchanged")

func _service_pause_request() -> void:
	if _pause_request.is_empty() or _physics_paused: return
	var captured: Dictionary = save_state()
	if not captured.ok:
		_pause_request.code = str(captured.code)
		return # Short assistance/support continues through ordinary physics.
	var bodies: Array = [_cargo]
	for actor in _carriers.values():
		if not is_instance_valid(actor): continue
		for item in actor.cargo_items.values():
			if item.get("body") == _cargo and not bodies.has(actor): bodies.append(actor)
	var records: Array = []
	for body in bodies:
		var physical: Dictionary = _body_snapshot(body)
		var issue: String = _body_snapshot_issue(physical,body)
		if not issue.is_empty():
			_pause_request.code = "pause_boundary:"+issue
			return
		records.append({"body":weakref(body),"physical":physical,"was_frozen":body.freeze})
	# Candidate, body set and original momentum all precede the first freeze.
	_pause_saved = captured.state.duplicate(true)
	_pause_bodies = records
	_stop_assist()
	_clear_fields()
	for record in _pause_bodies: record.body.get_ref().freeze = true
	_physics_paused = true
	_pause_request.clear()
	ready = false

func cancel_disconnect() -> Dictionary:
	if _suspended.is_empty(): return _no("no_suspended_role")
	var actor: Variant = _suspended.actor.get_ref() if _suspended.actor != null else null
	var peer: Variant = _peer_for_identity(str(_suspended.state.role_identity))
	if not is_instance_valid(actor) or peer == null or session.players[peer] != actor: return _no("original_role_already_departed")
	var state: Dictionary = _suspended.state
	actor.freeze = bool(_suspended.actor_frozen)
	_cargo.freeze = bool(_suspended.cargo_frozen)
	_write_momentum(actor,state.carrier)
	_write_momentum(_cargo,state.cargo)
	_suspended.clear()
	_last_frame = Engine.get_physics_frames()
	if not _journey.is_empty(): _journey.last_frame = _last_frame; _journey.last_mm = _mm(actor.global_position)
	ready = true
	return _yes("original_disconnect_cancelled_no_credit")

func remap_role() -> Dictionary:
	if not _bound_host() or _suspended.is_empty(): return _no("suspended_original_role_required")
	var state: Dictionary = _suspended.state.duplicate(true)
	var checked: Dictionary = _validate_progress(state)
	if not checked.ok: return checked # Entire preflight remains read-only.
	var peer: Variant = _peer_for_identity(str(state.role_identity))
	var old_actor: Variant = _suspended.actor.get_ref() if _suspended.actor != null else null
	if is_instance_valid(old_actor) and session.players[peer] == old_actor: return _no("replacement_role_body_required")
	clear()
	var bound: Dictionary = bind_world()
	if not bound.ok: return bound
	var restored: Dictionary = restore_carried_state(state)
	if not restored.ok:
		_suspended = {"state":state,"actor":null,"actor_frozen":true,"cargo_frozen":true}
		_cargo.freeze = true
		ready = false
	return restored

func _pickup(peer) -> Dictionary:
	var before: Dictionary = _row()
	var result: Dictionary = _custody.pickup(CARGO,str(_peers[peer]),int(_custody.last_serial)+1,int(_custody.revision))
	if not result.ok: return result
	var actor: Flight = _carriers[_peers[peer]]
	_owned_joint = weakref(actor.cargo_items[CARGO].joint)
	_owned_carrier = weakref(actor)
	_journey = {} if before.berth != LOW else {"pickup_serial":int(_row().serial),"carrier":str(_peers[peer]),"last_frame":Engine.get_physics_frames(),"last_mm":_mm(actor.global_position),"frames_observed":0,"outer_progress":0,"updraft_ticks":0,"updraft_origin_mm":-1,"updraft_rise_mm":0,"broken":false}
	_release_route = ""
	_release_serial = 0
	var departure = DockLift.new()
	_operation_serial += 1
	var started: Dictionary = departure.begin(actor,_berths[before.berth],_operation_serial,true)
	if started.ok: _assist = {"kind":"departure","peer":peer,"dock":departure,"frames":0}
	return result

func _release(destination: String) -> Dictionary:
	var route := ""
	if destination == HIGH and not _journey.is_empty() and not bool(_journey.broken):
		if int(_journey.outer_progress) == OUTER.size(): route = "outer_corridor"
		elif int(_journey.updraft_ticks) >= 12 and int(_journey.updraft_rise_mm) >= 4000: route = "updraft"
	var result: Dictionary = _custody.release_to(CARGO,destination,int(_custody.last_serial)+1,int(_custody.revision))
	if result.ok:
		_release_serial = int(_row().serial)
		_release_route = route
		_owned_joint = null
		_owned_carrier = null
		_clear_fields()
	return result

func _advance_assist(delta: float) -> void:
	if _assist.is_empty(): return
	_assist.frames = int(_assist.frames)+1
	if int(_assist.frames) > 1200: error = "local_assistance_timeout"; _stop_assist(); return
	var peer: Variant = _assist.peer
	if not _peers.has(peer) or not is_instance_valid(_carriers.get(_peers[peer])): _stop_assist(); return
	if _assist.kind == "settle_release":
		var actor: Flight = _carriers[_peers[peer]]
		var destination: String = str(_assist.destination)
		var row: Dictionary = _row()
		var info: Dictionary = _custody.release_info(CARGO,destination)
		if int(_assist.frames) > 600 or row.phase != "carried" or row.carrier != _peers[peer] or not _actor_near(peer,destination) or not _settle_column(destination,info):
			error = "release_settling_left_safe_column_or_timeout"
			_stop_assist()
			return
		_brake_assist(actor,float(_assist.height))
		if info.ok:
			_stop_assist()
			var released: Dictionary = _release(destination)
			if not released.ok: error = "settled_release:"+str(released.code)
			return
		# DockLift arrival and Custody release have different native speed gates.
		# Once at release height, keep braking here until the FULL release_info
		# succeeds, instead of re-entering the already completed approach.
		if _assist.get("at_release_height",false): return
		# begin_approach repeats its complete native body/support/sweep checks.
		# Rejected attempts have no custody or attachment side effects.
		if actor.linear_velocity.length() <= .2 and _cargo.linear_velocity.length() <= .2:
			var approach = DockLift.new()
			_operation_serial += 1
			var begun: Dictionary = approach.begin_approach(actor,_berths[destination],_operation_serial,true)
			if begun.ok:
				_assist = {"kind":"approach_release","peer":peer,"dock":approach,"destination":destination,"frames":0}
			elif str(begun.code) not in ["carrier_not_settled","load_not_settled"]:
				error = "settled_approach:"+str(begun.code)
				_stop_assist()
		return
	if _assist.kind == "pickup_alignment":
		var observed: Dictionary = _assist.pilot.tick(delta,true,false)
		if observed.get("arrived",false):
			_assist.clear()
			var picked: Dictionary = _pickup(peer)
			if not picked.ok: error = "alignment_pickup:"+str(picked.code)
		elif observed.get("state") == "blocked": error = "alignment_obstructed"; _stop_assist()
	else:
		var observed: Dictionary = _assist.dock.tick(delta,true,false)
		if not observed.ok: error = "dock_assistance:"+str(observed.code); _stop_assist(); return
		if observed.get("clear",false): _stop_assist()
		elif observed.get("ready_for_release",false):
			var destination: String = str(_assist.destination)
			_stop_assist()
			var actor: Flight = _carriers[_peers[peer]]
			_assist = {"kind":"settle_release","peer":peer,"destination":destination,"frames":0,"height":actor.global_position.y,"at_release_height":true}
			_brake_assist(actor,float(_assist.height))

func _stop_assist() -> void:
	if not _assist.is_empty():
		var peer: Variant = _assist.get("peer")
		if _peers.has(peer) and is_instance_valid(_carriers.get(_peers[peer])):
			var actor: Flight = _carriers[_peers[peer]]
			_brake_assist(actor,actor.global_position.y)
	_assist.clear()

static func _brake_assist(actor: Flight, height: float) -> void:
	actor.hold_height = height
	actor.command = {"active":true,"mode":"assisted","body_relative":false,"planar":Vector3.ZERO,"vertical":0.0,"yaw":0.0,"brake":true,"fire":false}

func _settle_column(destination: String, info: Dictionary) -> bool:
	if destination not in [LOW,HIGH] or not info.get("diagnostic") is Dictionary: return false
	var geometry: Dictionary = info.diagnostic
	# Wait only within the exact original berth footprint, at most the native
	# one-metre approach height. Changed/obstructed geometry never becomes ready.
	return str(info.get("code","")) in ["ok","moving_too_fast","drop_pose_mismatch"] and bool(geometry.get("footprint_inside",false)) and float(geometry.get("bottom_gap_m",-100.0)) >= -.025 and float(geometry.get("bottom_gap_m",100.0)) <= 1.0 and float(geometry.get("up_dot",0.0)) >= .985

func _observe_route(frame: int) -> void:
	if _journey.is_empty() or bool(_journey.broken): return
	var row: Dictionary = _row()
	var actor: Flight = _carriers.get(row.carrier)
	var grip: Dictionary = _custody.grip_info(CARGO)
	if not is_instance_valid(actor) or not grip.has("anchor_error_m") or float(grip.anchor_error_m) > .15: _journey.broken = true; return
	var at: Vector3 = actor.global_position
	var last: Vector3 = _metres(_journey.last_mm)
	if frame != int(_journey.last_frame)+1 or at.distance_to(last) > 1.0: _journey.broken = true; return
	_journey.last_frame = frame
	_journey.last_mm = _mm(at)
	_journey.frames_observed = int(_journey.frames_observed)+1
	var progress: int = int(_journey.outer_progress)
	if progress < OUTER.size() and at.distance_to(OUTER[progress]) <= 3.0: _journey.outer_progress = progress+1
	var applied: Vector3 = actor.telemetry.get("environment_acceleration",Vector3.ZERO)
	if UPDRAFT.has_point(at) and applied.y >= 1.0:
		_journey.updraft_ticks = int(_journey.updraft_ticks)+1
		if int(_journey.updraft_origin_mm) < 0: _journey.updraft_origin_mm = roundi(at.y*1000.0)
		_journey.updraft_rise_mm = maxi(int(_journey.updraft_rise_mm),roundi(at.y*1000.0)-int(_journey.updraft_origin_mm))

func _apply_updraft() -> void:
	var row: Dictionary = _row()
	var carrier_id: String = str(row.get("carrier",""))
	for id in _carriers:
		var actor: Flight = _carriers[id]
		if not is_instance_valid(actor): continue
		if row.phase == "carried" and id == carrier_id and UPDRAFT.has_point(actor.global_position):
			if not _fields.has(id): _fields[id] = {"body":weakref(actor),"before":actor.environment_acceleration,"applied":Vector3.ZERO}
			var next: Vector3 = Vector3(_fields[id].before)+Vector3.UP*2.0
			actor.environment_acceleration = next
			_fields[id].applied = actor.environment_acceleration
		else: _clear_field(id)

func _clear_field(id: String) -> void:
	if not _fields.has(id): return
	var record: Dictionary = _fields[id]
	var body: Variant = record.body.get_ref()
	if body is Flight and is_instance_valid(body) and body.environment_acceleration.is_equal_approx(record.applied): body.environment_acceleration = record.before
	_fields.erase(id)

func _clear_fields() -> void:
	for id in _fields.keys(): _clear_field(str(id))

func _near_berth() -> String:
	for id in [HIGH,LOW]:
		var at: Vector3 = _berths[id].global_position
		if Vector2(_cargo.global_position.x-at.x,_cargo.global_position.z-at.z).length() <= .65 and _cargo.global_position.y > at.y: return id
	return ""

func _actor_near(peer, target: String) -> bool:
	var actor: Flight = _carriers[_peers[peer]]
	var body: PhysicsBody3D = _cargo if target == CARGO else _berths[target]
	if not is_instance_valid(actor) or not actor.enabled or actor.global_position.distance_to(body.global_position) > 4.5: return false
	var query := PhysicsRayQueryParameters3D.create(actor.global_position,body.global_position,MASK,[actor.get_rid()])
	var hit: Dictionary = _world.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == body or target in [LOW,HIGH] and hit.get("collider") == _cargo

func _sync_entity() -> void:
	if not is_instance_valid(_cargo) or not session.entities.has(CARGO): return
	var entity: Dictionary = session.entities[CARGO]
	entity.position = _cargo.global_position
	entity["cargo_phase"] = str(_row().get("phase",""))

func _row() -> Dictionary:
	return _custody.report().cargos[CARGO] if _custody != null else {}

func _live_host() -> bool:
	return is_instance_valid(session) and session.active and session.region_id == "I3" and session.network.is_authority() and is_instance_valid(session.world) and session.world.is_inside_tree()

func _bound_host() -> bool:
	return _live_host() and _custody != null and _world == session.world and is_instance_valid(_cargo) and _world.objects.get(CARGO) == _cargo

func _current_roster() -> Dictionary:
	var carriers: Dictionary = {}
	var peers: Dictionary = {}
	for peer in session.players:
		var actor: Variant = session.players[peer]
		if not actor is Flight or not is_instance_valid(actor) or not actor.enabled or actor.get_world_3d().space != _world.get_world_3d().space: continue
		if _shape_contract(actor).is_empty(): return _no("current_player_single_box_required")
		var id := "pilot:"+str(peer)
		carriers[id] = actor
		peers[peer] = id
	if carriers.is_empty() or carriers.size() > 2: return _no("one_or_two_current_players_required")
	return {"ok":true,"carriers":carriers,"peers":peers}

func _peer_for_identity(identity: String):
	var identities: Variant = session.get("identities")
	if not identities is Dictionary or not _identity_valid(identity): return null
	var found: Variant = null
	for peer in session.players:
		if identities.get(peer) != identity: continue
		if found != null: return null # Duplicate identities cannot select a role.
		var actor: Variant = session.players[peer]
		if not actor is Flight or not is_instance_valid(actor) or not actor.is_inside_tree() or not actor.enabled: return null
		found = peer
	return found

func _capture_progress() -> Dictionary:
	var row: Dictionary = _row()
	var carrier_id: String = str(row.carrier)
	var actor: Flight = _carriers.get(carrier_id)
	var peer: Variant = null
	for key in _peers:
		if _peers[key] == carrier_id: peer = key
	var identities: Variant = session.get("identities")
	if peer == null or not identities is Dictionary or not _identity_valid(identities.get(peer)) or _peer_for_identity(str(identities[peer])) != peer: return _no("current_stable_role_identity_required")
	if not _custody._integrity(CARGO).is_empty() or not is_instance_valid(actor) or actor.freeze or _cargo.freeze or actor.water_contact or actor.crash_reported or not actor.contact_cooldowns.is_empty(): return _no("carried_native_integrity_or_contact_transient")
	var joint: Dictionary = _custody._progress_joint_snapshot(CARGO,carrier_id)
	if joint.is_empty(): return _no("actual_native_joint_required")
	var role: String = str(identities[peer])
	var saved_row: Dictionary = row.duplicate(true)
	saved_row.carrier = role
	joint.carrier_id = role
	for index in range(joint.cargo_exceptions.size()):
		if joint.cargo_exceptions[index] == carrier_id: joint.cargo_exceptions[index] = role
	var journey: Dictionary = _journey.duplicate(true)
	if not journey.is_empty(): journey.carrier = role
	var flight := {"build":actor.build.duplicate(true),"damage":actor.damage_snapshot(),"safe_position":_xyz(actor.safe_position),"last_velocity":_xyz(actor.last_velocity),
		"collision_count":actor.collision_count,"sandbox_rules":actor.sandbox_rules.duplicate(true),"practice":actor.practice,
		"base_acceleration":_xyz(_fields[carrier_id].before if _fields.has(carrier_id) else actor.environment_acceleration)}
	for key in FLIGHT_SCALARS: flight[key] = actor.get(key)
	var state := {"version":2,"cargo_id":CARGO,"role_identity":role,"custody":{"revision":_custody.revision,"last_serial":_custody.last_serial,"row":saved_row},
		"joint":joint,"cargo":_body_snapshot(_cargo),"carrier":_body_snapshot(actor),"flight":flight,"operation_serial":_operation_serial,"journey":journey}
	var valid: Dictionary = _validate_progress(state)
	return {"ok":true,"code":"native_carried_progress_no_new_credit","state":state} if valid.ok else valid

## Fresh-only physical construction. The original generic joint constructor
## is reused; only its Canal-specific 2-cargo validator is replaced by the
## exact one-cargo contract below. No call to pickup/seat/release occurs.
func restore_carried_state(state: Dictionary) -> Dictionary:
	if not _bound_host() or _last_frame != -1 or _restoring or not _suspended.is_empty() or int(_custody.revision) != 0 or int(_custody.last_serial) != 0: return _no("fresh_bound_carried_restore_required")
	var checked: Dictionary = _validate_progress(state)
	if not checked.ok: return checked
	var peer: Variant = _peer_for_identity(str(state.role_identity))
	if not _peers.has(peer): return _no("saved_role_requires_current_bound_roster")
	var actor: Flight = session.players[peer]
	if not actor.cargo_items.is_empty() or actor.cargo_kg != 0.0 or not actor.get_collision_exceptions().is_empty() or not _cargo.get_collision_exceptions().is_empty(): return _no("fresh_unowned_collision_filters_required")
	if not _restore_space_clear(state,actor): return _no("saved_carried_body_obstructed")
	var previous_cargo: Dictionary = _body_snapshot(_cargo)
	var previous_carrier: Dictionary = _body_snapshot(actor)
	var cargo_frozen: bool = _cargo.freeze
	var actor_frozen: bool = actor.freeze
	_cargo.freeze = true
	actor.freeze = true
	_write_pose(_cargo,state.cargo)
	_write_pose(actor,state.carrier)
	var data: Dictionary = state.joint.duplicate(true)
	var carrier_id: String = str(_peers[peer])
	data.carrier_id = carrier_id
	for index in range(data.cargo_exceptions.size()):
		if data.cargo_exceptions[index] == state.role_identity: data.cargo_exceptions[index] = carrier_id
	var attached: Dictionary = _custody._restore_progress_joint_fresh(data)
	if not attached.ok:
		_write_pose(_cargo,previous_cargo)
		_write_pose(actor,previous_carrier)
		_cargo.freeze = cargo_frozen
		actor.freeze = actor_frozen
		_write_momentum(_cargo,previous_cargo)
		_write_momentum(actor,previous_carrier)
		return _no("native_joint_restore:"+str(attached.code))
	_cargo.freeze = false
	actor.freeze = false
	_write_momentum(_cargo,state.cargo)
	_write_momentum(actor,state.carrier)
	if not _native_readback(_cargo,state.cargo) or not _native_readback(actor,state.carrier):
		var joint: PinJoint3D = actor.cargo_items[CARGO].joint
		joint.free()
		actor.release_cargo(CARGO)
		if actor.get_collision_exceptions().has(_cargo): actor.remove_collision_exception_with(_cargo)
		if _cargo.get_collision_exceptions().has(actor): _cargo.remove_collision_exception_with(actor)
		_custody._grip_records.erase(CARGO)
		_cargo.freeze = true
		actor.freeze = true
		_write_pose(_cargo,previous_cargo)
		_write_pose(actor,previous_carrier)
		_cargo.freeze = cargo_frozen
		actor.freeze = actor_frozen
		_write_momentum(_cargo,previous_cargo)
		_write_momentum(actor,previous_carrier)
		return _no("native_progress_pose_or_momentum_readback")
	var row: Dictionary = state.custody.row.duplicate(true)
	row.carrier = carrier_id
	for key in ["serial","completed_serial","stable_usec"]: row[key] = int(row[key])
	_custody._states = {CARGO:row}
	_custody.revision = int(state.custody.revision)
	_custody.last_serial = int(state.custody.last_serial)
	_custody._restored = true
	_owned_joint = weakref(actor.cargo_items[CARGO].joint)
	_owned_carrier = weakref(actor)
	actor.restore_damage_state(state.flight.damage)
	for key in FLIGHT_SCALARS: actor.set(key,float(state.flight[key]))
	actor.safe_position = _vector(state.flight.safe_position)
	actor.last_velocity = _vector(state.flight.last_velocity)
	actor.collision_count = int(state.flight.collision_count)
	actor.sandbox_rules = state.flight.sandbox_rules.duplicate(true)
	actor.practice = bool(state.flight.practice)
	actor.environment_acceleration = _vector(state.flight.base_acceleration)
	actor.environment_sample = _world.sample_environment(actor.global_position)
	actor.command = {"active":true,"mode":"assisted","body_relative":false,"planar":Vector3.ZERO,"vertical":0.0,"yaw":0.0,"brake":true,"fire":false}
	_operation_serial = int(state.operation_serial)
	_journey = state.journey.duplicate(true)
	if not _journey.is_empty():
		_journey.carrier = carrier_id
		_journey.last_frame = Engine.get_physics_frames()
		_journey.last_mm = _mm(actor.global_position)
	_sync_entity()
	ready = true
	if session.simulation_paused:
		# Reconnection may occur during an existing shared pause. The original
		# saved momentum has just passed native readback; freeze those restored
		# bodies and cache that exact candidate before any physics can advance.
		_pause_saved = state.duplicate(true)
		_pause_bodies = [{"body":weakref(_cargo),"physical":state.cargo.duplicate(true),"was_frozen":false},
			{"body":weakref(actor),"physical":state.carrier.duplicate(true),"was_frozen":false}]
		_cargo.freeze = true
		actor.freeze = true
		_physics_paused = true
		ready = false
	return {"ok":true,"code":"carried_role_and_native_joint_restored_no_credit","changes":[]}

func _validate_progress(state: Dictionary) -> Dictionary:
	if not _keys(state,PROGRESS_KEYS) or state.version != 2 or state.cargo_id != CARGO or not _identity_valid(state.role_identity): return _no("carried_snapshot_keys_or_role")
	var peer: Variant = _peer_for_identity(str(state.role_identity))
	if peer == null: return _no("saved_role_identity_missing_or_duplicated")
	var actor: Flight = session.players[peer]
	if actor.get_world_3d().space != _world.get_world_3d().space: return _no("saved_role_requires_current_world")
	var history: Variant = state.custody
	if not _keys(history,["revision","last_serial","row"]) or not _integer(history.revision,1,Custody.MAX_SERIAL) or not _integer(history.last_serial,1,Custody.MAX_SERIAL): return _no("carried_custody_counters")
	var row: Variant = history.row
	if not _keys(row,["phase","carrier","berth","serial","completed_serial","stable_usec","fault"]) or row.phase != "carried" or row.carrier != state.role_identity or row.berth != "" or row.stable_usec != 0 or row.fault != "" or not _integer(row.serial,1,int(history.last_serial)) or not _integer(row.completed_serial,0,int(row.serial)-1): return _no("carried_custody_occupancy")
	var joint: Variant = state.joint
	if not _keys(joint,["cargo_id","carrier_id","weight","node_pose","local_a","local_b","bias","damping","impulse_clamp","exclude_pair","solver_priority","grip","carrier_exceptions","cargo_exceptions"]) or joint.cargo_id != CARGO or joint.carrier_id != state.role_identity or joint.weight != 2.0 or not joint.exclude_pair is bool or not _integer(joint.solver_priority,1,8) or not _pose_valid(joint.node_pose) or not _xyz_valid(joint.local_a,2) or not _xyz_valid(joint.local_b,2): return _no("carried_joint_contract")
	for key in ["bias","damping","impulse_clamp"]:
		if not _number(joint[key],0,1 if key == "bias" else 100): return _no("carried_joint_parameter")
	for pair in [["carrier_exceptions",CARGO],["cargo_exceptions",state.role_identity]]:
		var values: Variant = joint[pair[0]]
		if not values is Array or values.size() > 1 or values.size() == 1 and values[0] != pair[1]: return _no("carried_external_collision_exception")
	var grip: Variant = joint.grip
	if not _keys(grip,["serial","carrier_local","cargo_local","pickup_offset","pickup_cargo_basis","pickup_up_dot"]) or not _integer(grip.serial,int(row.serial),int(row.serial)) or not _xyz_valid(grip.carrier_local,2) or not _xyz_valid(grip.cargo_local,2) or not _xyz_valid(grip.pickup_offset,.18) or not _number(grip.pickup_up_dot,.985,1.00001) or not grip.pickup_cargo_basis is Array or grip.pickup_cargo_basis.size() != 3: return _no("carried_original_grip_history")
	for axis in grip.pickup_cargo_basis:
		if not _xyz_valid(axis,1.00001): return _no("carried_grip_basis")
	var pickup_basis := Basis(_vector(grip.pickup_cargo_basis[0]),_vector(grip.pickup_cargo_basis[1]),_vector(grip.pickup_cargo_basis[2]))
	if not pickup_basis.is_equal_approx(pickup_basis.orthonormalized()) or pickup_basis.determinant() < .9999 or not _f32_equal(grip.carrier_local,joint.local_a) or not _f32_equal(grip.cargo_local,joint.local_b): return _no("carried_grip_anchor_mismatch")
	for pair in [["cargo",_cargo],["carrier",actor]]:
		var issue: String = _body_snapshot_issue(state[pair[0]],pair[1])
		if not issue.is_empty():
			_capture_diagnostic = {"body":pair[0],"issue":issue,"saved":state[pair[0]],"current_contract":_shape_contract(pair[1])}
			return _no("carried_"+str(pair[0])+":"+issue)
	_capture_diagnostic.clear()
	if (_transform(state.carrier.native_pose)*_vector(joint.local_a)).distance_to(_transform(state.cargo.native_pose)*_vector(joint.local_b)) > .08: return _no("saved_native_joint_endpoints_separated")
	if not _flight_valid(state.flight,actor): return _no("carried_flight_build_or_state")
	if not _integer(state.operation_serial,0,2147483647) or not state.journey is Dictionary: return _no("carried_operation_or_journey")
	var journey: Dictionary = state.journey
	if not journey.is_empty():
		if not _keys(journey,["pickup_serial","carrier","last_frame","last_mm","frames_observed","outer_progress","updraft_ticks","updraft_origin_mm","updraft_rise_mm","broken"]) or journey.carrier != state.role_identity or not _integer(journey.pickup_serial,int(row.serial),int(row.serial)) or not journey.broken is bool or not _xyz_valid(journey.last_mm,100000): return _no("carried_journey_identity")
		for key in ["last_frame","frames_observed","updraft_ticks","updraft_rise_mm"]:
			if not _integer(journey[key],0,2147483647): return _no("carried_journey_counter")
		if not _integer(journey.outer_progress,0,OUTER.size()) or not _integer(journey.updraft_origin_mm,-1,100000) or int(journey.updraft_ticks) > int(journey.frames_observed): return _no("carried_journey_bounds")
	return _yes("strict_one_cargo_progress_valid")

static func _body_snapshot(body: RigidBody3D) -> Dictionary:
	var shape: Dictionary = _shape_contract(body)
	return {"pose":_pose(body.global_transform),"velocity":_xyz(body.linear_velocity),"angular_velocity":_xyz(body.angular_velocity),
		"native_pose":_pose(PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)),
		"native_velocity":_xyz(PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)),
		"native_angular_velocity":_xyz(PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)),"contract":shape}

static func _shape_contract(body: RigidBody3D) -> Dictionary:
	var owners = body.get_shape_owners()
	if owners.size() != 1 or body.is_shape_owner_disabled(owners[0]) or body.shape_owner_get_shape_count(owners[0]) != 1: return {}
	var shape: Shape3D = body.shape_owner_get_shape(owners[0],0)
	if not shape is BoxShape3D: return {}
	var locks: Array = []
	for axis in [PhysicsServer3D.BODY_AXIS_LINEAR_X,PhysicsServer3D.BODY_AXIS_LINEAR_Y,PhysicsServer3D.BODY_AXIS_LINEAR_Z,PhysicsServer3D.BODY_AXIS_ANGULAR_X,PhysicsServer3D.BODY_AXIS_ANGULAR_Y,PhysicsServer3D.BODY_AXIS_ANGULAR_Z]: locks.append(body.get_axis_lock(axis))
	var material: PhysicsMaterial = body.physics_material_override
	return {"size":_xyz(shape.size),"shape_pose":_pose(body.shape_owner_get_transform(owners[0])),"margin":shape.margin,
		"mass":body.mass,"layer":body.collision_layer,"mask":body.collision_mask,"linear_damp":body.linear_damp,"angular_damp":body.angular_damp,
		"linear_damp_mode":body.linear_damp_mode,"angular_damp_mode":body.angular_damp_mode,"gravity_scale":body.gravity_scale,"custom_integrator":body.custom_integrator,
		"continuous_cd":body.continuous_cd,"contact_monitor":body.contact_monitor,"max_contacts":body.max_contacts_reported,"can_sleep":body.can_sleep,"freeze_mode":body.freeze_mode,"locks":locks,
		"material":{} if material == null else {"friction":material.friction,"bounce":material.bounce,"rough":material.rough,"absorbent":material.absorbent}}

static func _body_snapshot_valid(saved, body: RigidBody3D) -> bool:
	return _body_snapshot_issue(saved,body).is_empty()

static func _body_snapshot_issue(saved, body: RigidBody3D) -> String:
	if not _keys(saved,["pose","velocity","angular_velocity","native_pose","native_velocity","native_angular_velocity","contract"]): return "body_snapshot_keys"
	if not _pose_valid(saved.pose): return "node_pose_invalid"
	if not _pose_valid(saved.native_pose): return "native_pose_invalid"
	for pair in [["velocity","native_velocity",15.0],["angular_velocity","native_angular_velocity",8.0]]:
		if not _xyz_valid(saved[pair[0]],pair[2]) or not _xyz_valid(saved[pair[1]],pair[2]): return str(pair[0])+"_invalid"
		if not _f32_equal(saved[pair[0]],saved[pair[1]]): return "node_native_"+str(pair[0])+"_mismatch"
	if not _f32_equal(saved.pose,saved.native_pose): return "node_native_pose_mismatch"
	var actual: Dictionary = _shape_contract(body)
	if actual.is_empty(): return "current_single_box_missing"
	if not saved.contract is Dictionary: return "physical_contract_invalid"
	if not _keys(saved.contract,actual.keys()): return "physical_contract_keys"
	for key in actual:
		if not _physical_tree_equal(saved.contract[key],actual[key]): return "physical_contract_"+str(key)
	return ""

static func _physical_tree_equal(a, b) -> bool:
	if a is Dictionary and b is Dictionary:
		if not _keys(a,b.keys()): return false
		for key in b:
			if not _physical_tree_equal(a[key],b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for index in range(a.size()):
			if not _physical_tree_equal(a[index],b[index]): return false
		return true
	if b is int: return _integer(a,b,b)
	if b is float: return _number(a,-1.0e12,1.0e12) and _f32_equal([a],[b])
	return typeof(a) == typeof(b) and a == b

static func _f32_equal(a: Array,b: Array) -> bool:
	return PackedFloat32Array(a).to_byte_array() == PackedFloat32Array(b).to_byte_array()

static func _write_pose(body: RigidBody3D,saved: Dictionary) -> void:
	body.global_transform = _transform(saved.native_pose)
	body.force_update_transform()
	PhysicsServer3D.body_set_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,_transform(saved.native_pose))

static func _write_momentum(body: RigidBody3D,saved: Dictionary) -> void:
	body.linear_velocity = _vector(saved.native_velocity)
	body.angular_velocity = _vector(saved.native_angular_velocity)
	PhysicsServer3D.body_set_state(body.get_rid(),PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY,_vector(saved.native_velocity))
	PhysicsServer3D.body_set_state(body.get_rid(),PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY,_vector(saved.native_angular_velocity))

static func _native_readback(body: RigidBody3D,saved: Dictionary) -> bool:
	var pose: Transform3D = PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
	var expected: Transform3D = _transform(saved.native_pose)
	# Jolt stores orientation as a quaternion; Basis -> quaternion -> Basis may
	# change final basis ULPs. Require an orthonormal equal orientation, while
	# position and the actual native linear/angular momentum retain exact bits.
	return pose.basis.is_equal_approx(expected.basis) and _f32_equal(_xyz(pose.origin),_xyz(expected.origin)) and _f32_equal(_xyz(PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)),saved.native_velocity) and _f32_equal(_xyz(PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)),saved.native_angular_velocity)

func _restore_space_clear(state: Dictionary, actor: Flight) -> bool:
	for pair in [[actor,state.carrier],[_cargo,state.cargo]]:
		var query := PhysicsShapeQueryParameters3D.new()
		var shape := BoxShape3D.new()
		shape.size = _vector(pair[1].contract.size)
		query.shape = shape
		query.transform = _transform(pair[1].native_pose)*_transform(pair[1].contract.shape_pose)
		query.margin = .001
		query.collision_mask = int(pair[1].contract.mask)
		query.exclude = [actor.get_rid(),_cargo.get_rid()]
		var hits: Array = _world.get_world_3d().direct_space_state.intersect_shape(query,16)
		if hits.size()==16: return false
		for hit: Dictionary in hits:
			# Jolt may save a carried load while it still rests on its original
			# berth. That native top contact is not a new obstacle. Keep the exact
			# saved pose/momentum; never exempt aircraft, side walls or other bodies.
			if pair[0]!=_cargo or not _restore_berth_contact(shape.size,query.transform,hit.get("collider")): return false
	return true

func _restore_berth_contact(size: Vector3, pose: Transform3D, berth: Variant) -> bool:
	if not is_instance_valid(berth) or berth not in [_berths.get(LOW),_berths.get(HIGH)]: return false
	var collision: CollisionShape3D
	for child: Node in berth.get_children():
		if child is CollisionShape3D and not child.disabled:
			if collision!=null: return false
			collision=child
	if collision==null or not collision.shape is BoxShape3D: return false
	var to_berth: Transform3D=(berth.global_transform*collision.transform).affine_inverse()
	var half: Vector3=size*.5
	var low:=Vector3(INF,INF,INF)
	var high:=Vector3(-INF,-INF,-INF)
	for x: int in [-1,1]:
		for y: int in [-1,1]:
			for z: int in [-1,1]:
				var point: Vector3=to_berth*(pose*(half*Vector3(x,y,z)))
				low=low.min(point)
				high=high.max(point)
	var support: Vector3=collision.shape.size*.5
	var slop: float=clampf(float(ProjectSettings.get_setting("physics/jolt_physics_3d/simulation/penetration_slop",.02)),0,.02)
	return low.y>=support.y-slop and low.y<=support.y+.001 and high.y>support.y and low.x>=-support.x-.001 and high.x<=support.x+.001 and low.z>=-support.z-.001 and high.z<=support.z+.001

static func _flight_valid(saved, actor: Flight) -> bool:
	var keys: Array = FLIGHT_SCALARS.duplicate()
	keys.append_array(["build","damage","safe_position","last_velocity","collision_count","sandbox_rules","practice","base_acceleration"])
	if not _keys(saved,keys) or not saved.build is Dictionary or not _physical_tree_equal(saved.build,actor.build) or not Catalog.resolve_build(saved.build).valid or not _xyz_valid(saved.safe_position,150) or not _xyz_valid(saved.last_velocity,15) or not _xyz_valid(saved.base_acceleration,Flight.MAX_ENVIRONMENT_ACCELERATION) or not _integer(saved.collision_count,0,2147483647) or not saved.practice is bool or (not _keys(saved.sandbox_rules,[]) and not _keys(saved.sandbox_rules,["unlimited_power"])): return false
	if saved.sandbox_rules.has("unlimited_power") and not saved.sandbox_rules.unlimited_power is bool: return false
	for key in FLIGHT_SCALARS:
		if not _number(saved[key],-1.0e9 if key in ["heading","hold_height"] else 0.0,1.0e12): return false
	if not _number(saved.battery,0,100) or not _number(saved.heat,0,actor.max_heat) or not _number(saved.max_altitude,.1,100) or saved.water_seconds != 0.0 or saved.crash_seconds != 0.0 or not _number(saved.collision_damage_scale,0,10): return false
	for key in ["shield_left","shield_cooldown","recovery_left","ability_left","ability_cooldown"]:
		if float(saved[key]) > 3600: return false
	var damage: Variant = saved.damage
	var expected: Dictionary = actor.damage_snapshot()
	if not _keys(damage,expected.keys()) or not _number(damage.health,.000001,actor.maximum_health) or damage.maximum_health != actor.maximum_health or damage.maximum_armor != expected.maximum_armor or not _number(damage.armor,0,expected.maximum_armor) or not _integer(damage.serial,0,Custody.MAX_SERIAL) or not _keys(damage.components,expected.components.keys()): return false
	for key in expected.components:
		var part: Variant = damage.components[key]
		if not _keys(part,["health","maximum"]) or not _number(part.maximum,float(expected.components[key].maximum)-.0000001,float(expected.components[key].maximum)+.0000001) or not _number(part.health,0,float(part.maximum)): return false
	return true

static func _identity_valid(value) -> bool:
	return value is String and not value.is_empty() and value.length() <= 96 and not value.contains("\n") and not value.contains("\r")

static func _number(value, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= low and float(value) <= high

func _validate_save(state: Dictionary) -> Dictionary:
	if not _keys(state,SAVE_KEYS) or state.version != 1 or state.cargo_id != CARGO or not state.custody is Dictionary or not Custody.validate_docked_snapshot(state.custody).ok: return _no("invalid_docked_checkpoint")
	if not _keys(state.custody.cargos,[CARGO]) or state.custody.cargos[CARGO].berth not in [LOW,HIGH] or not _integer(state.operation_serial,0,2147483647): return _no("docked_checkpoint_registry")
	if not _pose_valid(state.cargo_pose) or not _xyz_valid(state.linear_velocity,.12) or not _xyz_valid(state.angular_velocity,.15) or not state.proof is Dictionary: return _no("docked_checkpoint_physics")
	var pose: Transform3D = _transform(state.cargo_pose)
	var support: StaticBody3D = _berths[str(state.custody.cargos[CARGO].berth)]
	var top: float = support.global_position.y+.25
	var box: AABB = pose*AABB(Vector3(-.2,-.2,-.2),Vector3(.4,.4,.4))
	var centre: Vector3 = support.global_position
	if box.position.x < centre.x-.97 or box.end.x > centre.x+.97 or box.position.z < centre.z-.97 or box.end.z > centre.z+.97 or absf(box.position.y-top) > .025 or pose.basis.y.dot(Vector3.UP) < .985: return _no("saved_cargo_not_on_claimed_berth")
	if not state.proof.is_empty():
		var proof: Dictionary = state.proof
		if not _keys(proof,["version","cargo_id","pickup_serial","release_serial","completed_serial","route","frames_observed","outer_progress","updraft_ticks","updraft_rise_mm"]) or proof.version != 1 or proof.cargo_id != CARGO or proof.route not in ["outer_corridor","updraft"]: return _no("invalid_delivery_proof")
		for key in ["pickup_serial","release_serial","completed_serial"]:
			if not _integer(proof[key],1,9007199254740000): return _no("delivery_serial_type")
		if state.custody.cargos[CARGO].berth != HIGH or not _integer(proof.pickup_serial,1,int(proof.release_serial)-1) or int(proof.release_serial) != int(state.custody.cargos[CARGO].serial) or int(proof.completed_serial) != int(proof.release_serial): return _no("delivery_custody_serial_mismatch")
		for key in ["frames_observed","updraft_ticks","updraft_rise_mm"]:
			if not _integer(proof[key],0,2147483647): return _no("delivery_counter")
		if not _integer(proof.outer_progress,0,OUTER.size()) or int(proof.frames_observed) < 3: return _no("delivery_route_count")
		if proof.route == "outer_corridor" and int(proof.outer_progress) != OUTER.size(): return _no("outer_route_incomplete")
		if proof.route == "updraft" and (int(proof.updraft_ticks) < 12 or int(proof.updraft_rise_mm) < 4000): return _no("actual_updraft_rise_missing")
	return _yes("docked_checkpoint_valid")

static func _box(parent: Node3D, size: Vector3, color: Color) -> void:
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	parent.add_child(collision)
	var view := MeshInstance3D.new()
	view.name = "Shape"
	var mesh := BoxMesh.new()
	mesh.size = size
	view.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .8
	view.material_override = material
	parent.add_child(view)

static func _pose(value: Transform3D) -> Array:
	return _xyz(value.basis.x)+_xyz(value.basis.y)+_xyz(value.basis.z)+_xyz(value.origin)

static func _transform(value: Array) -> Transform3D:
	return Transform3D(Basis(_vector(value.slice(0,3)),_vector(value.slice(3,6)),_vector(value.slice(6,9))),_vector(value.slice(9,12)))

static func _pose_valid(value) -> bool:
	if not value is Array or value.size() != 12: return false
	for number in value:
		if not (number is int or number is float) or not is_finite(float(number)) or absf(float(number)) > 100.0: return false
	var basis: Basis = _transform(value).basis
	return basis.get_scale().is_equal_approx(Vector3.ONE) and absf(basis.determinant()-1.0) < .0001

static func _xyz_valid(value, maximum: float) -> bool:
	if not value is Array or value.size() != 3: return false
	for number in value:
		if not (number is int or number is float) or not is_finite(float(number)): return false
	return _vector(value).length() <= maximum+.000001

static func _xyz(value: Vector3) -> Array:
	return [value.x,value.y,value.z]

static func _vector(value: Array) -> Vector3:
	return Vector3(float(value[0]),float(value[1]),float(value[2]))

static func _mm(value: Vector3) -> Array:
	return [roundi(value.x*1000.0),roundi(value.y*1000.0),roundi(value.z*1000.0)]

static func _metres(value: Array) -> Vector3:
	return _vector(value)/1000.0

static func _keys(value, expected: Array) -> bool:
	if not value is Dictionary or value.size() != expected.size(): return false
	for key in expected:
		if not value.has(key): return false
	return true

static func _integer(value, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and floor(float(value)) == float(value) and float(value) >= float(low) and float(value) <= float(high)

func _operation_no(code: String) -> Dictionary:
	error = code
	return {"handled":true,"ok":false,"code":code}

func _no(code: String) -> Dictionary:
	error = code
	return {"ok":false,"code":code}

static func _yes(code: String) -> Dictionary:
	return {"ok":true,"code":code}
