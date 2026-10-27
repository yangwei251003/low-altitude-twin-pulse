extends RefCounted
## Read-only addition AFTER original Host NpcContact.prepare succeeds.
## No arrival forecast, service attempt, stock reservation or transaction.
const LivingWorld = preload("res://scripts/v3/ecology/twin_living_world.gd")
const CONTACTS := ["I1:water_01","I1:repair_01"]

static func extra_lines(session, peer_id: int, actor_id: String) -> Array:
	if actor_id not in CONTACTS or not is_instance_valid(session): return []
	if not session.active or not session.owns_world or not session.network.is_authority(): return []
	if session.region_id != "I1" or not session.ecology.ready or not session.players.has(peer_id): return []
	var actor: Dictionary = session.ecology.simulation.get_actor(actor_id)
	if actor.is_empty() or actor.get("region") != "I1": return []
	var body: Variant = session.players[peer_id]
	if not is_instance_valid(body) or not body is Node3D or not body.global_position.is_finite(): return []
	var health: float = float(body.health)
	var maximum: float = float(body.maximum_health)
	var temperature: float = float(session.entities.get("I1:thermal",{}).get("temperature",20))
	if not is_finite(health) or not is_finite(maximum) or maximum <= 0.0 or not is_finite(temperature): return []
	var stock: int = int(session.ecology.facilities.coolant)
	var service: Vector3 = LivingWorld.SERVICE_POSITION
	var distance: float = body.global_position.distance_to(service)
	var height: float = service.y-body.global_position.y
	var vertical: String = "大致与你同高"
	# This rounding affects wording only. The actual service range below is exact.
	if absf(height) >= 0.1:
		vertical = "在你上方 %.1f 米" % height if height > 0.0 else "在你下方 %.1f 米" % -height
	var location: String = "检修台现有冷却液 %d 份；距你 %.1f 米，%s。" % [stock,distance,vertical]
	var status: String
	# Same global gates, then this requesting pilot's eligibility as _try_service.
	if session.boss_active:
		status = "战斗中检修台暂停服务，战斗结束后再来。"
	elif session.pending_completion:
		status = "战后处理尚未结束，检修台暂时不能服务。"
	elif session.simulation_paused:
		status = "世界正在共同暂停，检修服务也暂停了。"
	elif stock <= 0:
		status = "当前没有可用冷却液；需有实际补给到货后才能检修。"
	elif not session.consensus.current_proposal().is_empty():
		status = "小队正在确认共同决定，检修台先暂停服务。"
	elif temperature >= 85.0:
		status = "热交换旁路过热；先降到 85℃以下，再到台边检修。"
	elif not bool(body.enabled):
		status = "当前机体已失能，检修台不能直接提供服务。"
	elif health >= maximum:
		status = "你的机体耐久已满，目前无需检修。"
	elif distance > 4.0:
		status = "靠近检修台 4 米内，才会尝试自动检修。"
	else:
		status = "你已在检修范围内，可以等候自动检修。"
	return [location,status]
