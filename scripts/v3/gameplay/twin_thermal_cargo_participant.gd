extends RefCounted
## Root-owned normal Session bridge. The original module owns physical custody;
## this participant owns lifecycle/role handoff and uses only Session's Store.
const Cargo = preload("res://scripts/v3/gameplay/twin_thermal_cargo_session.gd")
const Presentation = preload("res://scripts/v3/network/twin_thermal_presentation.gd")
const PATH := "world.environment.I3_thermal_cargo"
var session
var module: RefCounted
var enabled := true
var error := ""
var _waiting_role: Dictionary = {}
var _disconnect_peer := 0
var _disconnect_attempted := false
var _retained_actor: FlightBodyV2
var _epoch := 0
var _presentation: Dictionary = {}
var _queued_join: Dictionary = {}

func setup(owner_session) -> void:
	session = owner_session

func clear() -> void:
	if module != null: module.clear()
	module = null
	if is_instance_valid(_retained_actor): _retained_actor.queue_free()
	_retained_actor = null
	_waiting_role.clear()
	_disconnect_peer = 0
	_disconnect_attempted = false
	error = ""
	_presentation.clear()
	_queued_join.clear()

func supported() -> bool:
	return enabled and module != null and session.region_id == "I3" and session.network.is_authority()

func saved_build(identity: String) -> Dictionary:
	if not enabled or session.region_id != "I3" or not session.network.is_authority(): return {}
	var saved: Dictionary = session.world_cache.world.get("environment",{}).get("I3_thermal_cargo",{})
	for role: Dictionary in Cargo.required_roles(saved):
		if role.identity == identity: return role.build.duplicate(true)
	return {}

func bind_world() -> bool:
	if not enabled or session.region_id != "I3" or not session.network.is_authority() or session.players.is_empty(): return true
	if module != null: return sync_roster()
	module = Cargo.new()
	_epoch += 1
	module.setup(session)
	var bound: Dictionary = module.bind_world()
	if not bound.get("ok",false): return _fail("bind:"+str(bound.get("code","failed")))
	var saved: Dictionary = session.world_cache.world.get("environment",{}).get("I3_thermal_cargo",{}).duplicate(true)
	if saved.is_empty(): return true
	var roles: Array = Cargo.required_roles(saved)
	if saved.get("version") == 2 and roles.is_empty(): return _fail("invalid_saved_role_build")
	for role: Dictionary in roles:
		if role.identity not in session.identities.values():
			_waiting_role = saved
			session.world.objects[Cargo.CARGO].freeze = true
			session.world.objects[Cargo.CARGO].visible = false
			session._note_all("吊载记录已保留，等待原载货队友加入后继续。")
			return true
	return _restore(saved)

func sync_roster() -> bool:
	if not supported(): return true
	var synced: Dictionary = module.sync_roster()
	if not synced.get("ok",false): return _fail("roster:"+str(synced.get("code","failed")))
	if not _waiting_role.is_empty():
		for role: Dictionary in Cargo.required_roles(_waiting_role):
			if role.identity not in session.identities.values(): return true
		var pending: Dictionary = _waiting_role.duplicate(true)
		_waiting_role.clear()
		return _restore(pending)
	var suspended: String = str(module.status().get("suspended_role",""))
	if not suspended.is_empty() and suspended in session.identities.values():
		# The original body is already durably saved. Remove its real collision
		# before the fresh restore's clearance query, within this same callback.
		if is_instance_valid(_retained_actor): _retained_actor.free()
		_retained_actor = null
		var remapped: Dictionary = module.remap_role()
		if not remapped.get("ok",false): return _fail("remap:"+str(remapped.get("code","failed")))
		if is_instance_valid(_retained_actor): _retained_actor.queue_free()
		_retained_actor = null
	return true

func _restore(saved: Dictionary) -> bool:
	var restored: Dictionary = module.restore_state(saved)
	if not restored.get("ok",false): return _fail("restore:"+str(restored.get("code","failed")))
	session.world.objects[Cargo.CARGO].visible = true
	return true

func advance(delta: float) -> void:
	if not supported() or not _waiting_role.is_empty(): return
	var step: Dictionary = module.advance(delta)
	if not step.get("ok",false):
		_fail("step:"+str(step.get("code","failed")))
		return
	if _disconnect_peer > 0: _complete_disconnect()

func begin_disconnect(peer_id: int) -> bool:
	if _queued_join.get("peer_id") == peer_id: _queued_join.clear()
	if not supported(): return false
	var requested: Dictionary = module.suspend_for_disconnect(peer_id) if module.pause_request_status().get("paused",false) else module.request_suspend_for_disconnect(peer_id)
	if not requested.get("ok",false): return false # An unloaded departing pilot.
	_disconnect_peer = peer_id
	_disconnect_attempted = false
	if session.players.has(peer_id): session.players[peer_id].command = {"active":true,"brake":true,"planar":Vector3.ZERO,"vertical":0.0}
	return true

func defer_rejoin(peer_id: int, identity: String, airframe: String) -> bool:
	if _disconnect_peer <= 0 or session.identities.get(_disconnect_peer) != identity: return false
	_queued_join = {"peer_id":peer_id,"identity":identity,"airframe":airframe}
	session._note(peer_id,"正在保全断线前的吊载记录，保存成功后自动接回。")
	return true

func _complete_disconnect() -> void:
	var captured: Dictionary = module.disconnect_state()
	if captured.get("pending",false): return
	if not captured.get("ok",false):
		_fail("disconnect:"+str(captured.get("code","failed")))
		return
	if not _disconnect_attempted:
		_disconnect_attempted = true
		session._commit("thermal-cargo-disconnect",{})
	var published: Dictionary = session.world_cache.world.get("environment",{}).get("I3_thermal_cargo",{})
	if not session.store.matches_persisted_value(captured.state,published): return
	_retained_actor = session.players.get(_disconnect_peer)
	session._finish_guest_departure(_disconnect_peer,true)
	_disconnect_peer = 0
	_disconnect_attempted = false
	session._note_all("队友的吊载与动量已保存；同一队友重连后继续。")
	if not _queued_join.is_empty():
		var queued: Dictionary = _queued_join.duplicate()
		_queued_join.clear()
		if session.network.guests.has(queued.peer_id): session._guest_joined(queued.peer_id,queued.identity,queued.airframe)

func owns_target(id: String) -> bool:
	return supported() and module.owns_target(id)

func operable_near(peer_id: int, id: String) -> bool:
	return enabled and session.region_id == "I3" and id in [Cargo.CARGO,Cargo.LOW,Cargo.HIGH] and session.players.has(peer_id) and session.world.objects.has(id) and session.players[peer_id].global_position.distance_to(session.world.objects[id].global_position)<=4.5

func operate(peer_id: int, id: String) -> void:
	if not supported() or not _waiting_role.is_empty(): return
	var result: Dictionary = module.operate(peer_id,id)
	if result.get("ok",false):
		session._audio_event("mechanism",session.world.objects[id].global_position,id)
		session._note(peer_id,"保持制动，让吊载挂稳或落稳；中途可继续手动飞行。")
	else: session._note(peer_id,"靠近泊位对准吊载，制动稳住后再按 G。")

func fact(target: String) -> String:
	return module.fact(target) if supported() and _waiting_role.is_empty() else ""

func capture() -> Dictionary:
	if not supported(): return {"ok":true}
	if not _waiting_role.is_empty():
		var original: Dictionary = session.world_cache.world.get("environment",{}).get("I3_thermal_cargo",{})
		# Both values are already original Store readbacks. Preserve exact value
		# equality; a second JSON roundtrip can itself move a fractional ULP.
		if _waiting_role != original: return {"ok":false,"code":"waiting_role_source_changed"}
		return {"ok":true,"path":PATH,"state":_waiting_role.duplicate(true)}
	var saved: Dictionary = module.paused_saved_state() if module.pause_request_status().get("paused",false) else module.save_state()
	if not saved.get("ok",false): return saved
	return {"ok":true,"path":PATH,"state":saved.state.duplicate(true)}

func prepare_save() -> Dictionary:
	var saved: Dictionary = capture()
	return {"ok":true,"ready":saved.get("ok",false),"code":saved.get("code","native_cargo_capture")}

func request_pause() -> Dictionary:
	if not supported(): return {"ok":false,"code":"cargo_not_bound"}
	if not _waiting_role.is_empty(): return {"ok":true,"ready":true,"pending":false}
	return module.request_pause()

func pause_status() -> Dictionary:
	return {"ok":true,"ready":true,"pending":false} if not _waiting_role.is_empty() else module.pause_request_status()

func set_paused(value: bool) -> Dictionary:
	if not supported() or not _waiting_role.is_empty(): return {"ok":true}
	return module.set_paused(value)

func owns_paused_body(body: Variant) -> bool:
	if not supported(): return false
	var held: bool = not _waiting_role.is_empty() or not str(module.status().get("suspended_role","")).is_empty() or module.pause_request_status().get("paused",false)
	if not held: return false
	if body == session.world.objects.get(Cargo.CARGO): return true
	return body is FlightBodyV2 and body.cargo_items.has(Cargo.CARGO)

func presentation() -> Dictionary:
	if not supported(): return {}
	var status: Dictionary = module.status()
	var row: Dictionary = status.get("custody",{}).get("cargos",{}).get(Cargo.CARGO,{})
	var phase: String = "waiting_role" if not _waiting_role.is_empty() else str(row.get("phase","free"))
	var role := ""
	if phase == "carried":
		role = str(status.get("suspended_role",""))
		for peer in module._peers:
			if module._peers[peer] == row.get("carrier",""): role = str(session.identities.get(peer,role))
	var body: RigidBody3D = session.world.objects[Cargo.CARGO]
	return {"version":1,"epoch":_epoch,"pose":Cargo._pose(PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)),"phase":phase,"role_identity":role,"visible":body.visible,"weight_kg":2.0}

func receive_presentation(value: Variant) -> bool:
	if session.network.is_authority() or not Presentation.valid(value): return false
	if value.is_empty():
		_presentation.clear()
		return true
	if session.region_id != "I3" or not session.world.objects.get(Cargo.CARGO) is RigidBody3D: return false
	if not _presentation.is_empty() and value.epoch < _presentation.epoch: return false
	var body: RigidBody3D = session.world.objects[Cargo.CARGO]
	if body.mass != 2.0 or body.collision_layer != 8 or body.collision_mask != Cargo.MASK: return false
	_presentation = value.duplicate(true)
	body.set_meta("thermal_remote_presentation",true)
	body.freeze = true
	body.visible = value.visible
	body.global_transform = Cargo._transform(value.pose)
	return true

func remote_loaded_actor(body: Variant) -> bool:
	if session.network.is_authority() or _presentation.is_empty() or _presentation.phase != "carried": return false
	for peer_id in session.players:
		if session.players[peer_id] == body: return session.identities.get(peer_id,"") == _presentation.role_identity
	return false

func _fail(code: String) -> bool:
	error = code
	session._note_all("吊载状态需要处理，原存档保留。" )
	return false
