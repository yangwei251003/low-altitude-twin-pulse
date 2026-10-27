extends RefCounted
## One authority clock for burst. Pulse keeps its original attempted-shot clock.
## Reliable owner HUD events carry presentation only; no client hit parameters.
const Cycle = preload("res://scripts/v3/gameplay/twin_weapon_cycle.gd")
const KIND := "weapon_presentation_v1"
const VIEW_KEYS := ["weapon_id","heat","capacity","charge_s","charge_max_s","cooldown_s","overheated","reason"]
var session
var _cycles: Dictionary = {}
var _views: Dictionary = {}
var _publish_clock := 0.0
var _serial := 0
var _remote_serial := -1
var _remote_session := ""

func is_burst(peer: int) -> bool:
	return session.players.has(peer) and session.players[peer].build.get("slots",{}).get("weapon")=="burst_capacitor"

func advance_peer(peer: int, delta: float) -> void:
	if not session.network.is_authority() or not session.players.has(peer): return
	if peer!=session.network.local_id() and not session.network.guests.has(peer):
		forget(peer)
		return
	var body: FlightBodyV2 = session.players[peer]
	if not is_burst(peer):
		forget(peer)
		session.weapon_cooldowns[peer]=maxf(0.0,float(session.weapon_cooldowns.get(peer,0))-delta)
		if body.command.get("fire",false) and body.enabled and float(session.weapon_cooldowns[peer])<=0.0: session._fire(peer)
		return
	var record: Dictionary = _cycles.get(peer,{})
	var hash: String = str(body.stats.build_hash)
	if record.is_empty() or record.body_id!=body.get_instance_id() or record.build_hash!=hash:
		forget(peer)
		var cycle = Cycle.new()
		var configured: Dictionary = cycle.configure(body.build,body.heat,float(session.weapon_cooldowns.get(peer,0)))
		if not configured.get("ok",false): return
		record={"cycle":cycle,"body_id":body.get_instance_id(),"build_hash":hash}
		_cycles[peer]=record
		session.weapon_cooldowns.erase(peer)
	var context := _context(peer)
	var advanced: Dictionary = record.cycle.step(Engine.get_physics_frames(),delta,context)
	if not advanced.get("ok",false): return
	if advanced.has("shot_request"):
		var request: Dictionary = advanced.shot_request
		# The synchronous original fire path rechecks LOS/part/actor/sequence.
		var accepted: bool = request.target_id==str(session.locks.get(peer,"")) and request.build_hash==hash and request.weapon_id=="burst_capacitor" and session._fire(peer,float(request.damage))
		record.cycle.confirm_shot(int(request.serial),accepted)
	var state: Dictionary = record.cycle.snapshot()
	body.heat=float(state.heat)
	_views[peer]=_view(state)

func _context(peer: int) -> Dictionary:
	var body: FlightBodyV2 = session.players[peer]
	var id: String = str(session.locks.get(peer,""))
	if session.ambient_patrol.owns_target(id): return session.ambient_patrol.weapon_context(peer)
	if session.combat_sites.owns_target(id): return session.combat_sites.weapon_context(peer)
	var valid: bool = session.active and session.boss_active and session.entities.has(id)
	var los := false
	var opened := false
	if valid:
		var point: Variant = session.entities[id].get("position")
		valid=point is Vector3 and point.is_finite() and body.global_position.distance_to(point)<=36.0
		if valid:
			los=session._line_clear(body.global_position,point,body.get_rid(),id)
			opened=_part_open(id)
	return {"is_authority":true,"held_fire":bool(body.command.get("fire",false)),"enabled":bool(body.enabled),"paused":bool(session.simulation_paused),"target_id":id,"target_valid":valid,"line_of_sight":los,"part_open":opened}

func _part_open(id: String) -> bool:
	if session.campaign.active():
		return session.campaign.owns_target(id) and session.campaign.encounter.part_open(session.world.campaign_arena.part_id(id))
	if session.crown.active():
		return id==session.crown.CORE and bool(session.crown.encounter.get_state().get("core_open",false))
	if session.region_id!="I1" or not id.begins_with("boss:"): return false
	var state: Dictionary = session.encounter.get_state()
	if state.is_empty() or bool(state.get("completed",true)): return false
	var part := id.trim_prefix("boss:")
	if part=="core": return float(state.get("exposed_remaining",0))>0.0
	return bool(state.get("nodes_open",false)) and state.get("nodes",{}).has(part) and bool(state.nodes[part].get("powered",false))

func _view(state: Dictionary) -> Dictionary:
	var p: Dictionary = state.profile
	return {"weapon_id":"burst_capacitor","heat":float(state.heat),"capacity":float(p.heat_capacity),"charge_s":float(state.charge_s),"charge_max_s":float(p.charge_s),"cooldown_s":float(state.cooldown_s),"overheated":bool(state.overheated),"reason":str(state.cancel_reason)}

func cancel(peer: int, reason: String) -> void:
	if not _cycles.has(peer): return
	_cycles[peer].cycle.cancel(reason)
	_views[peer]=_view(_cycles[peer].cycle.snapshot())

func cancel_all(reason: String) -> void:
	for peer: int in _cycles: cancel(peer,reason)

func forget(peer: int) -> void:
	if _cycles.has(peer): _cycles[peer].cycle.cancel("body_or_connection_changed")
	_cycles.erase(peer)
	_views.erase(peer)

func clear() -> void:
	for peer: int in _cycles.keys(): forget(peer)
	_views.clear()
	_publish_clock=0.0
	# Keep the Host's serial monotonic across region/body changes. Session IDs
	# bind different hosts; reliable same-channel delivery orders owner updates.

func presentation(peer: int) -> Dictionary:
	return _views.get(peer,{}).duplicate(true)

func publish(delta: float) -> void:
	if not session.active or session.network.mode!="host" or session.network.guests.is_empty(): return
	_publish_clock+=delta
	if _publish_clock<.2: return
	_publish_clock=0.0
	for peer: int in session.network.guests:
		if not is_burst(peer) or not _views.has(peer): continue
		_serial+=1
		session.network.send_event(peer,{"kind":KIND,"session_id":session.network.session_id,"region":session.region_id,"sequence":_serial,"build_hash":str(session.players[peer].stats.build_hash),"view":presentation(peer)})

func receive(event: Dictionary) -> void:
	if event.get("kind")!=KIND or session.network.mode!="guest" or not session.active or event.get("session_id")!=session.received_session or event.get("region")!=session.region_id: return
	var peer: int = session.network.local_id()
	if not is_burst(peer) or event.get("build_hash")!=str(session.players[peer].stats.build_hash): return
	if event.keys().size()!=6 or not event.get("sequence") is int or event.sequence<0 or not event.get("view") is Dictionary: return
	var view: Dictionary = event.view
	if not _valid_view(view,float(session.players[peer].max_heat)): return
	if _remote_session!=session.received_session:
		_remote_session=session.received_session
		_remote_serial=-1
	if int(event.sequence)<=_remote_serial: return
	_remote_serial=int(event.sequence)
	_views[peer]=view.duplicate(true)
	# Visual telemetry only. Guest prediction never evaluates hit damage/heat.
	session.players[peer].heat=float(view.heat)

static func _valid_view(view: Dictionary, capacity: float) -> bool:
	if view.size()!=VIEW_KEYS.size(): return false
	for key: String in VIEW_KEYS:
		if not view.has(key): return false
	if view.weapon_id!="burst_capacitor" or not view.overheated is bool or not view.reason is String or view.reason.length()>64: return false
	for key: String in ["heat","capacity","charge_s","charge_max_s","cooldown_s"]:
		if not (view[key] is float or view[key] is int) or not is_finite(float(view[key])): return false
	return float(view.capacity)==capacity and float(view.heat)>=0.0 and float(view.heat)<=capacity and float(view.charge_max_s)==.7 and float(view.charge_s)>=0.0 and float(view.charge_s)<=.7+.00001 and float(view.cooldown_s)>=0.0 and float(view.cooldown_s)<=1.0

func hud(peer: int) -> String:
	var key: String = "手柄 X" if is_instance_valid(session.inputs) and session.inputs.source=="controller" else "J / 左键"
	if not is_burst(peer): return "脉冲炮 · %s 开火 · Tab 锁定" % key
	var view: Dictionary = presentation(peer)
	if view.is_empty(): return "蓄能炮 · 按住 %s 0.7秒 · 正在同步武器" % key
	var state := "按住 %s 0.7秒" % key
	if view.overheated: state="过热 · 低于40%后恢复"
	elif float(view.cooldown_s)>0.0: state="冷却 %.1f秒" % float(view.cooldown_s)
	elif float(view.charge_s)>0.0: state="蓄能 %d%%" % int(100.0*float(view.charge_s)/float(view.charge_max_s))
	elif view.reason=="armored": state="装甲关闭 · 等待开放"
	elif view.reason=="occluded": state="目标被挡住 · 换位瞄准"
	return "蓄能炮 · %s · 热量 %d / %d" % [state,int(ceilf(float(view.heat))),int(view.capacity)]
