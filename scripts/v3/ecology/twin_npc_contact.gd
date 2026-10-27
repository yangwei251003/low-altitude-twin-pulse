extends RefCounted
## Read-only contact. Clients nominate an ID; only Host prepares the reply.
const RANGE_M := 4.5
const Ecology = preload("res://scripts/v3/ecology/twin_ecology_state.gd")
const Anchors = preload("res://scripts/v3/ecology/twin_npc_anchors.gd")
const ServiceReply = preload("res://scripts/v3/ecology/twin_npc_service_reply.gd")
const PURPOSE_TEXT := {
	"F3:nutrient_01":"我从供应点取养分，再送到育苗台；需要保持养分线供能。",
	"F3:pollinator_01":"我往返两处花簇授粉，遇到危险就回棚避让。",
	"F4:care_01":"我巡查两界接口，照料支脉和接续装置。"}
const PHASE_TEXT := {
	"traveling":"我正在沿当前航线前进。", "detouring":"我正在绕开危险航点。",
	"working":"我正在当前作业点工作。", "waiting":"我现在停留等待。",
	"seeking_shelter":"我正在前往避风点。", "sheltered":"我正在避风点等待。"}
const REASON_TEXT := {
	"initializing":"我正在准备本轮工作。", "power_unavailable":"我正在等待供能恢复。",
	"reserve_depleted":"备用电已耗尽，我正在原地等待供能。",
	"supply_unavailable":"我正在等待供应点恢复供能。", "cargo_required":"我正在等待本轮载荷。",
	"route_blocked":"目前没有安全的通路，我在等待航线恢复。",
	"retreat_from_danger":"前方航点出现危险，我正沿原路退回。",
	"both_edge_ends_dangerous":"这段航线两端都有危险，我正在原地等待。",
	"inspect":"我正在核对当前作业点。", "repair":"我正在进行本轮维护。",
	"pickup":"我正在装载本轮载荷。", "deliver":"我正在交接本轮载荷。",
	"pollinate":"我正在当前花簇授粉。", "job_completed":"这一处工作已结束，正准备前往下一处。"}
const CARGO_ROLES := ["water_transport","service_transport","nutrient_transport"]

static func nearest(view: Node3D, current_region: String, at: Vector3, max_distance: float = RANGE_M) -> String:
	if not is_instance_valid(view) or not view.is_inside_tree() or not at.is_finite(): return ""
	if not is_finite(max_distance) or max_distance <= 0.0: return ""
	if str(view.get("region_id")) != current_region: return ""
	var actors: Variant = view.get("actors")
	var targets: Variant = view.get("targets")
	if not actors is Dictionary or not targets is Dictionary: return ""
	var best: String = ""
	var limit: float = minf(RANGE_M,max_distance)
	var ids: Array = targets.keys()
	ids.sort()
	for raw_id: Variant in ids:
		if not raw_id is String: continue
		var id: String = raw_id
		if not id.begins_with(current_region+":") or not actors.has(id): continue
		if not targets[id] is Dictionary or targets[id].get("id") != id: continue
		var actor: Variant = actors[id]
		if not is_instance_valid(actor) or not actor is Node3D or not actor.is_inside_tree(): continue
		if not actor.is_visible_in_tree() or not actor.global_position.is_finite(): continue
		var distance: float = at.distance_to(actor.global_position)
		if distance <= limit and (best.is_empty() or distance < limit):
			best = id
			limit = distance
	return best

static func prepare(session, peer_id: int, actor_id: String) -> Dictionary:
	if not is_instance_valid(session) or not session.active:
		return _reject("session_inactive","先进入当前世界，再联络附近的同伴。")
	if not session.owns_world or not session.network.is_authority():
		return _reject("host_required","请由当前世界房主确认这次联络。")
	if session.simulation_paused:
		return _reject("paused","世界正在共同暂停；恢复后再查看当前工作。")
	if peer_id < 1 or not session.players.has(peer_id):
		return _reject("player_missing","当前机体尚未就绪。")
	var body: Variant = session.players[peer_id]
	if not is_instance_valid(body) or not body is CollisionObject3D or not bool(body.get("enabled")):
		return _reject("player_disabled","当前机体暂时不能联络。")
	if not is_instance_valid(session.world) or not session.ecology.ready:
		return _reject("ecology_not_ready","当前地区联络尚未就绪。")
	if session.ecology.simulation.get_script() != Ecology:
		return _reject("ecology_unavailable","当前地区联络尚未就绪。")
	var actor: Dictionary = session.ecology.simulation.get_actor(actor_id)
	if actor.is_empty() or actor.get("id") != actor_id:
		return _reject("actor_missing","这位同伴目前不在可联络名单中。")
	if actor.get("region") != session.region_id:
		return _reject("other_region","请到这位同伴所在的地区再联络。")
	var view: Variant = session.ecology.view
	if not is_instance_valid(view) or str(view.region_id) != session.region_id or not view.is_inside_tree():
		return _reject("view_not_ready","当前地区联络尚未就绪。")
	if not view.actors.has(actor_id) or not view.targets.has(actor_id):
		return _reject("actor_not_present","这位同伴目前不在现场。")
	var presented: Variant = view.actors[actor_id]
	if not is_instance_valid(presented) or not presented is Node3D or not presented.is_inside_tree():
		return _reject("actor_not_present","这位同伴目前不在现场。")
	var raw_position: Variant = actor.get("position")
	if not raw_position is Array or raw_position.size() != 3:
		return _reject("actor_position_invalid","暂时无法确认这位同伴的位置。")
	for value: Variant in raw_position:
		if not (value is int or value is float) or not is_finite(float(value)):
			return _reject("actor_position_invalid","暂时无法确认这位同伴的位置。")
	var position: Vector3 = session.world.to_global(Anchors.local_position(actor))
	if not body.global_position.is_finite() or not position.is_finite():
		return _reject("position_invalid","暂时无法确认联络位置。")
	if body.global_position.distance_to(position) > RANGE_M:
		return _reject("out_of_range","这位同伴已移出联络距离，请再靠近。")
	if not session._line_clear(body.global_position,position,body.get_rid(),actor_id):
		return _reject("occluded","同伴被结构遮住了，请换到能看清的一侧。")
	var phase: String = str(actor.get("phase",""))
	var reason: String = str(actor.get("reason",""))
	if not PHASE_TEXT.has(phase) or not actor.get("cargo") is bool:
		return _reject("actor_state_invalid","暂时无法确认这位同伴的工作状态。")
	var lines: Array = [str(PURPOSE_TEXT.get(actor_id,actor.purpose)),str(REASON_TEXT.get(reason,PHASE_TEXT[phase]))]
	if str(actor.role) in CARGO_ROLES:
		lines.append("当前带着本轮待交付的载荷。" if actor.cargo else "当前没有携带本轮待交付的载荷。")
	lines.append_array(ServiceReply.extra_lines(session,peer_id,actor_id))
	return {"ok":true,"code":"npc_contact_ready","source_actor_id":actor_id,"position":position,
		"character_id":actor_id,"speaker_name":str(actor.name),"lines":lines,
		"phase":phase,"reason":reason,"cargo":bool(actor.cargo)}

static func _reject(code: String, text: String) -> Dictionary:
	return {"ok":false,"code":code,"text":text}
