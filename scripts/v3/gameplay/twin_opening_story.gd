class_name TwinOpeningStory
extends RefCounted
## Adapts authored actions to real players, physics, durable storage and transport.
## Clients submit only a nearby marker ID. Facts and route choices are host-derived.
const Director = preload("res://scripts/v3/gameplay/actions/twin_action_director.gd")
const CampaignCatalog = preload("res://scripts/v3/campaign/twin_campaign_catalog.gd")
const PostbossRevisits = preload("res://scripts/v3/campaign/twin_postboss_revisits.gd")
const CanalPreparationProof = preload("res://scripts/v3/gameplay/twin_canal_preparation_proof.gd")
const StateUpgrade = preload("res://scripts/v3/campaign/twin_campaign_state_upgrade.gd")
const Guidance = preload("res://scripts/v3/ui/twin_opening_guidance.gd")
const CargoGuidance = preload("res://scripts/v3/campaign/twin_i3_cargo_guidance.gd")
const WorldContent = preload("res://scripts/v3/content/world_content_next/twin_world_content_catalog.gd")
const NpcStoryContent = preload("res://scripts/v3/content/npc_story_next/twin_npc_story_catalog.gd")
const ChapterContent = preload("res://scripts/v3/content/twin_content_chapters.gd")
const Secrets88 = preload("res://scripts/v3/content/dev88_progression/twin_dev88_secrets.gd")
const Presentation88 = preload("res://scripts/v3/content/dev88_presentation/twin_dev88_presentation.gd")
const SideStories88 = preload("res://scripts/v3/content/dev88_story/twin_side_story_catalog.gd")
const CombatSites88 = preload("res://scripts/v3/content/dev88_combat/twin_combat_sites_catalog.gd")
const FinalStory = preload("res://scripts/v3/content/final_story/twin_final_story_catalog.gd")
const NpcContact = preload("res://scripts/v3/ecology/twin_npc_contact.gd")
const Regions = preload("res://scripts/v3/world/twin_region_catalog.gd")
const UnderdeckAction = preload("res://scripts/v3/gameplay/actions/twin_underdeck_action.gd")
const DistributionProgress = preload("res://scripts/v3/gameplay/actions/twin_distribution_progress.gd")
const TrialSession = preload("res://scripts/v3/gameplay/twin_trial_session.gd")
const SharedAccess = preload("res://scripts/v3/gameplay/twin_shared_access_session.gd")
const ACCESS_MARKERS := {SharedAccess.Bridge.PUBLIC_CONTROL:"public_span", SharedAccess.Bridge.SERVICE_CONTROL:"service_span"}
const TRIAL_MARKERS := [TrialSession.GAUGE_A,TrialSession.GAUGE_B,TrialSession.RETURN_SWITCH]
const WHALE_RECORD = "I1:whale_raw_record"
const CROWN_RECOVERED = "F1:crown_recovered"
var director = Director.new()
var legacy_director = Director.new()
var session
var state: Dictionary = {}
var markers: Dictionary = {}
var visuals: Dictionary = {}
var serial = 0
var expected_serial = -1
var applied_serial = -1
var state_applications = 0
var pending: Dictionary = {}
var clock = 0.0
var ready = false
var last_blink: Dictionary = {}
var _hud_key = ""
var _hud: Dictionary = {}
var _root_route: Dictionary = {}
var rescue_drone: Node3D
var rescue_status: Label3D
var rescue_return = 0.0
var _rescue_pose_initialized = false
var found_notes: Array = []
var underdeck_action = UnderdeckAction.new()
var _underdeck_retry = 0.0

func setup(owner_session) -> bool:
	session = owner_session
	var original_extensions: Array = CampaignCatalog.extension_paths(false)
	var all_extensions: Array = CampaignCatalog.extension_paths()
	var legacy_extensions: Array = all_extensions.slice(0, all_extensions.size() - original_extensions.size())
	if not legacy_director.load_definitions(Director.DEFAULT_PATH, legacy_extensions).get("ok", false): return false
	var loaded: Dictionary = director.load_definitions(Director.DEFAULT_PATH, all_extensions)
	if not loaded.get("ok", false):
		push_error("Opening action data invalid: " + str(loaded.get("code")))
		return false
	for marker in director.definitions().get("markers", []): markers[str(marker.id)] = marker
	# Early physical observations survive until the corresponding action opens.
	# The anchor only selects G; the real cabinet's ten rays validate the reading.
	markers[DistributionProgress.FACT_TARGET] = {"id":DistributionProgress.FACT_TARGET,
		"region":"I2", "kind":"inspect", "position":[18,3.5,-10.6], "radius":5.0,
		"label":"核对配流柜背面的出水关系", "optional":false}
	for row in [[TrialSession.GAUGE_A,[16.85,.85,-2.73],"读取试流接收箱 A"],
		[TrialSession.GAUGE_B,[19.15,.85,-2.73],"读取试流接收箱 B"],
		[TrialSession.RETURN_SWITCH,[18,.55,-2.42],"启动试流回收泵"]]:
		markers[row[0]]={"id":row[0],"region":"I2","kind":"inspect","position":row[1],"radius":4.5,"label":row[2],"optional":false}
	for id in ACCESS_MARKERS:
		markers[id] = {"id":id, "region":"I2", "kind":"inspect", "position":[], "radius":4.5,
			"label":"确认住区通路安排" if ACCESS_MARKERS[id] == "public_span" else "确认巡检通路安排", "optional":false}
	for id in ["F4:industrial_gauge","F4:living_gauge"]:
		markers[id] = {"id":id,"region":"F4","kind":"inspect","position":[],"radius":3.0,"physical_target":true,
			"label":"读取本轮工业负载" if id.ends_with("industrial_gauge") else "读取本轮活脉负载","optional":false}
	var notes = JSON.parse_string(FileAccess.get_file_as_string("res://data/v3/exploration_notes.json"))
	if notes is Dictionary:
		for note in notes.get("notes", []):
			if note is Dictionary and note.get("optional", false) and note.get("position", []).size() == 3:
				markers[str(note.id)] = note
	for note: Dictionary in WorldContent.notes(): markers[str(note.id)] = note
	for marker: Dictionary in NpcStoryContent.markers(): markers[str(marker.id)] = marker
	for marker: Dictionary in ChapterContent.markers(): markers[str(marker.id)] = marker
	for note: Dictionary in Secrets88.notes(): markers[str(note.id)] = note
	for marker: Dictionary in SideStories88.markers(): markers[str(marker.id)] = marker
	for marker: Dictionary in CombatSites88.markers(): markers[str(marker.id)] = marker
	for marker: Dictionary in FinalStory.all_markers(): markers[str(marker.id)] = marker
	return true

func reset_connection() -> void:
	reset_underdeck_tracking()
	state = {}
	ready = false
	_rescue_pose_initialized = false
	expected_serial = -1
	applied_serial = -1
	pending = {}
	last_blink.clear()
	_root_route.clear()
	found_notes.clear()
	session.interface.clear_dialogue()

func load_world() -> void:
	reset_underdeck_tracking()
	if is_instance_valid(session.world.underdeck):
		var loaded: Dictionary = underdeck_action.configure(session.world.underdeck.layout())
		if not loaded.ok: push_error("Underdeck action layout: " + str(loaded.code))
	_hud_key = ""
	last_blink.clear()
	_root_route.clear()
	session.interface.clear_dialogue()
	if session.owns_world:
		found_notes.clear()
		for id in markers:
			if markers[id].get("optional", false) and session.world_cache.world.get("flags", {}).get("note:" + id, false): found_notes.append(id)
		var saved: Dictionary = session.world_cache.world.get("actions", {}).get("opening", director.default_state())
		var upgraded: Dictionary = StateUpgrade.prepare(legacy_director, director, saved)
		if upgraded.get("ok", false) and upgraded.get("migrated", false):
			# Record only the validated state shape upgrade. Do not republish old
			# discoveries, dialogues or guest reward receipts while replaying it.
			if session._commit("campaign-action-upgrade-v1", {"world.actions.opening":upgraded.state}): saved = upgraded.state
		ready = bool(director.validate_state(saved).get("ok", false))
		state = saved.duplicate(true) if ready else {}
		if not ready: session.interface.notify("行动记录无法读取，原存档已保留；探索和飞行仍可继续。")
		serial += 1
	_build_markers()
	if session.owns_world: publish()

func publish(peer_id = 0) -> void:
	if not session.network.is_authority(): return
	var event = {"kind":"story_state", "session_id":session.network.session_id, "serial":serial, "state":state, "ready":ready, "notes":found_notes.duplicate()}
	if peer_id > 1: session.network.send_event(peer_id, event)
	else:
		for id in session.network.guests: session.network.send_event(int(id), event)

func receive(event: Dictionary) -> void:
	if session.network.mode != "guest": return
	if str(event.get("session_id", "")).is_empty(): return
	if not session.received_session.is_empty() and str(event.session_id) != session.received_session: return
	if not event.get("state", {}) is Dictionary: return
	if int(event.get("serial", -1)) <= applied_serial: return
	if not pending.is_empty() and int(event.get("serial", -1)) < int(pending.get("serial", -1)): return
	if int(event.get("serial", -1)) < expected_serial: return
	pending = event.duplicate(true)
	consume(expected_serial)

func consume(snapshot_serial: int) -> void:
	if session.network.mode != "guest": return
	if snapshot_serial != expected_serial:
		expected_serial = snapshot_serial
		ready = false
	if snapshot_serial == applied_serial: return
	if pending.is_empty() or session.received_session.is_empty(): return
	if str(pending.session_id) != session.received_session or int(pending.serial) != expected_serial: return
	if not director.validate_state(pending.state).get("ok", false): return
	state = pending.state.duplicate(true)
	found_notes = pending.get("notes", []).duplicate()
	ready = bool(pending.get("ready", true))
	applied_serial = expected_serial
	state_applications += 1
	pending = {}

func _point(marker: Dictionary) -> Vector3:
	if marker.get("physical_target",false):
		var actual: Variant = session.world.objects.get(str(marker.id)) if is_instance_valid(session.world) else null
		return actual.global_position if is_instance_valid(actual) else Vector3.INF
	if ACCESS_MARKERS.has(marker.get("id")):
		var anchor: Dictionary = session.shared_access.choice_anchor(ACCESS_MARKERS[marker.id])
		return anchor.get("position", Vector3.INF)
	if marker.get("id", "") == CROWN_RECOVERED:
		return session.world.crown_arena.host_position("F1:crown_host_west") if session.crown.ready() else Vector3.INF
	if marker.get("id", "") == WHALE_RECORD:
		return session.world.whale_record_position() if session.world.has_method("whale_record_position") else Vector3.INF
	var p: Array = marker.position
	return Vector3(p[0], p[1], p[2])

func _build_markers() -> void:
	for marker: Dictionary in CargoGuidance.markers(): markers[str(marker.id)] = marker
	visuals.clear()
	markers.erase(WHALE_RECORD)
	markers.erase(CROWN_RECOVERED)
	for id in ["I1:underdeck_entry", "I1:underdeck_transit"]: markers.erase(id)
	if session.region_id == "I1" and is_instance_valid(session.world.underdeck):
		for row in [["I1:underdeck_entry", "entry", "检修廊 · 南口 / 东侧高窗"], ["I1:underdeck_transit", "exit", "检修廊 · 北出口"]]:
			var at: Vector3 = session.world.underdeck.anchor_position(row[1])
			# Navigation-only markers never accept G or complete a proximity goal.
			markers[row[0]] = {"id":row[0], "region":"I1", "kind":"navigation", "label":row[2], "radius":0.0, "position":[at.x,at.y,at.z]}
	if session.region_id == "F1" and session.crown.ready():
		var host_at: Vector3 = session.world.crown_arena.host_position("F1:crown_host_west")
		if host_at.is_finite():
			markers[CROWN_RECOVERED] = {"id":CROWN_RECOVERED, "region":"F1", "kind":"inspect", "label":"西侧宿主 · 恢复读数", "radius":3.0, "position":[host_at.x, host_at.y, host_at.z]}
	if session.region_id == "I1" and session.world.has_method("whale_record_position"):
		var record_at: Vector3 = session.world.whale_record_position()
		if record_at.is_finite():
			markers[WHALE_RECORD] = {"id":WHALE_RECORD, "region":"I1", "kind":"inspect", "label":"鲸机 · 原始指令记录", "radius":3.0, "position":[record_at.x, record_at.y, record_at.z]}
	rescue_drone = null
	rescue_status = null
	rescue_return = 0.0
	_rescue_pose_initialized = false
	for id in markers:
		var marker: Dictionary = markers[id]
		if marker.region != session.region_id: continue
		var root = Node3D.new()
		root.name = str(id).replace(":", "_")
		if not _point(marker).is_finite():
			root.free()
			continue
		session.world.add_child(root)
		root.position = _point(marker)
		var ring = MeshInstance3D.new()
		var mesh = TorusMesh.new()
		mesh.inner_radius = 0.4
		mesh.outer_radius = 0.52
		mesh.rings = 16
		mesh.ring_segments = 6
		ring.mesh = mesh
		var material = StandardMaterial3D.new()
		material.albedo_color = Color("d7c59a") if marker.kind == "inspect" else Color("7ed3c6")
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring.material_override = material
		root.add_child(ring)
		var label = Label3D.new()
		label.name = "Hint"
		label.font = load("res://assets/fonts/NotoSansSC-Medium.ttf")
		label.text = str(marker.label)
		label.position.y = 1.0
		label.font_size = 21
		label.pixel_size = 0.025
		label.outline_size = 3
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		root.add_child(label)
		root.visible = false
		visuals[id] = root
		if id == "I1:rescue_pocket":
			rescue_drone = FleetVisualsV2.make_drone("tr01", CatalogV2.default_build("tr01").get("slots", {}))
			rescue_drone.name = "MaintenanceDrone"
			session.world.add_child(rescue_drone)
			rescue_drone.position = _point(marker)
			rescue_status = Label3D.new()
			rescue_status.name = "RescueStatus"
			rescue_status.font = load("res://assets/fonts/NotoSansSC-Medium.ttf")
			rescue_status.text = "检修机 · 安全待命"
			rescue_status.font_size = 18
			rescue_status.pixel_size = 0.025
			rescue_status.position.y = 1.0
			rescue_status.modulate = Color("a3d8c4")
			rescue_status.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			rescue_status.visible = false
			rescue_drone.add_child(rescue_status)
		elif marker.kind == "npc" or id in ["I1:whale_briefing", "F1:crown_briefing"]:
			# Small functional radio prop; still a study awaiting its single-asset art pass.
			var station = Node3D.new()
			station.name = "RadioStudy_" + str(id).replace(":", "_")
			session.world.add_child(station)
			station.position = _point(marker)
			session.world._box(station, Vector3(0, -0.5, 0), Vector3(0.16, 1.0, 0.16), Color("575d59"))
			session.world._box(station, Vector3.ZERO, Vector3(0.7, 0.45, 0.3), Color("b4b8a4"))
			session.world._box(station, Vector3(0.28, 0.45, 0), Vector3(0.025, 0.7, 0.025), Color("747a72"))
			session.world._box(station, Vector3(-0.13, 0, 0.16), Vector3(0.27, 0.2, 0.025), Color("5dc5b6"))
		elif id == "I1:energy_ledger":
			session.world._box(session.world, _point(marker) - Vector3(0, 0.4, 0), Vector3(0.8, 0.3, 0.5), Color("d0b08a"))
		elif id == "I1:burn_trace":
			for i in range(9):
				var fraction = float(i) / 8
				var p = Vector3(-14, 0.12, 17).lerp(Vector3(-12, 0.12, 14), fraction)
				var segment = session.world._box(session.world, p, Vector3(0.16, 0.14, 0.55), Color("38332b") if i > 3 else Color("9a6b43"))
				segment.rotation.y = -0.58
		elif marker.get("optional", false):
			# Small readable cue studies on authored terrain, separate from the marker UI.
			for i in range(3):
				var color = Color("d8ba72") if marker.region == "I1" else Color("657357")
				session.world._box(session.world, _point(marker) + Vector3((i - 1) * 0.22, -0.55, 0), Vector3(0.075, 0.035, 0.65), color)
	_refresh_rescue(0.0)
	var previous = session.world.get_node_or_null("Dev88Presentation")
	if previous != null: previous.free()
	var contacts: Array = []
	for marker: Dictionary in markers.values():
		if marker.get("region") == session.region_id and not marker.get("combat_site", false): contacts.append(marker)
	session.world.add_child(Presentation88.build(session.region_id, contacts))

func current_targets() -> Array:
	if not ready: return []
	var result: Array = []
	for objective in info().get("objectives", []):
		for target in objective.get("targets", []): result.append(target)
	return result

func info() -> Dictionary:
	var key = "%s:%d:%d:%s" % [session.region_id, int(state.get("revision", -1)), serial if session.owns_world else expected_serial, str(ready)]
	if key != _hud_key:
		_hud_key = key
		_hud = director.hud(state, session.region_id) if ready else {}
	return _hud

func refresh(at: Vector3, delta = 0.0) -> void:
	var active_ids: Array = []
	var captioned_id := str(display_anchor().get("anchor_id", ""))
	var targets: Array = current_targets()
	active_ids.append_array(CargoGuidance.active_ids(session.region_id, targets))
	for target in targets:
		active_ids.append(str(target.target_id))
		var anchor = target_anchor(str(target.target_id))
		if not anchor.is_empty(): active_ids.append(str(anchor.anchor_id))
	for id in visuals:
		if not is_instance_valid(visuals[id]): continue
		if not FinalStory.marker_available(state, str(id)):
			visuals[id].visible = false
			continue
		if not markers.has(id):
			visuals[id].visible = false
			continue # A restoring owned subtree may temporarily remove its target.
		var selected = id in active_ids
		if id == DistributionProgress.FACT_TARGET:
			selected = session.distribution.ready and at.distance_to(_point(markers[id])) < 7.0
		if id in TRIAL_MARKERS: selected=session.trial.ready and at.distance_to(_point(markers[id]))<5.5
		if ACCESS_MARKERS.has(id): selected=session.shared_access.ready and at.distance_to(_point(markers[id]))<5.5
		if id in [WHALE_RECORD, CROWN_RECOVERED]:
			var point = _point(markers[id])
			if point.is_finite(): visuals[id].position = point
		visuals[id].visible = selected or ((markers[id].kind == "npc" or markers[id].get("optional", false)) and at.distance_to(_point(markers[id])) < 7)
		# The current objective already has a screen-space destination caption.
		# Keep nearby optional/contact labels without drawing that same text twice.
		# The nearby G button already names this inspection. Keep its small ring
		# without a second large caption covering the cabinet and its backplates.
		visuals[id].get_node("Hint").visible = id != captioned_id and id != DistributionProgress.FACT_TARGET and id not in TRIAL_MARKERS and not ACCESS_MARKERS.has(id) and at.distance_to(_point(markers[id])) < 15
	_refresh_rescue(delta, at)

func _refresh_rescue(delta: float, at = Vector3.INF) -> void:
	if not is_instance_valid(rescue_drone): return
	# A joining visitor must receive committed story state before showing a pose.
	rescue_drone.visible = ready
	if not ready:
		return
	var rescued = "I1:rescue:evacuate" in state.get("completed", [])
	if not _rescue_pose_initialized:
		# Restoring an already completed rescue must not replay its evacuation.
		rescue_return = 1.0 if rescued else 0.0
		_rescue_pose_initialized = true
	else:
		rescue_return = minf(1.0, rescue_return + maxf(delta, 0.0) * 0.2) if rescued else 0.0
	var from = _point(markers["I1:rescue_pocket"])
	var to = _point(markers["I1:rescue_exit"]) + Vector3.UP * 2
	# Cosmetic flight, then persistent standby above the existing reception beacon.
	# No new task, reward, collision body or simulation authority is introduced.
	rescue_drone.position = from.lerp(to, rescue_return) + Vector3.UP * sin(rescue_return * PI) * 4
	if is_instance_valid(rescue_status):
		rescue_status.visible = rescued and rescue_return >= 1.0 and at.distance_to(rescue_drone.position) < 12.0

func nearest(at: Vector3) -> String:
	_update_canal_service_marker()
	var best = ""
	var distance = INF
	var allowed: Array = []
	# Reuse the original south-radio marker only after its complete saved route.
	if session.region_id == "I2" and "I2:twin_pump_guardian:decision" in state.get("completed", []):
		allowed.append("I2:canal_briefing")
	if session.region_id == "I2" and session.distribution.ready:
		allowed.append(DistributionProgress.FACT_TARGET)
	if session.region_id=="I2" and session.trial.ready: allowed.append_array(TRIAL_MARKERS)
	if session.region_id=="I2" and session.shared_access.ready:
		var mode: String = session.shared_access.module.status().mode
		# These adjacent consoles select motor direction with F. G inspects the
		# current locked arrangement, so half-metre hovering drift cannot select
		# the opposite (physically unavailable) arrangement.
		for id in ACCESS_MARKERS:
			if mode not in SharedAccess.Bridge.MODES or ACCESS_MARKERS[id] == mode: allowed.append(id)
	for target in current_targets():
		if target.target_id == "I2:canal_service_verified" and markers.has("I2:canal_workbench_power"):
			allowed.append("I2:canal_workbench_power")
		if target.type in ["talk", "inspect"] or target.target_id in [WHALE_RECORD, CROWN_RECOVERED, "I2:clinic_demand", "I2:clinic_water_check"]: allowed.append(str(target.target_id))
	allowed.append_array(session.campaign.manual_targets())
	for id in markers:
		var marker: Dictionary = markers[id]
		if marker.region != session.region_id or (id not in allowed and marker.kind != "npc" and not marker.get("optional", false)): continue
		if not FinalStory.marker_available(state, str(id)): continue
		var d = at.distance_to(_point(marker))
		if d <= float(marker.radius) and d < distance:
			distance = d
			best = id
	# Current tasks, investigations and stationary contacts keep G priority.
	if best.is_empty(): best = NpcContact.nearest(session.ecology.view,session.region_id,at)
	return best

func interaction_label(id: String) -> String:
	if ACCESS_MARKERS.has(id):
		if SharedAccess.OBJECTIVE in state.get("completed", []): return "查看通路记录"
		if not shared_choice_available(): return "查看当前桥位"
	if not markers.has(id) and is_instance_valid(session.ecology.view) and session.ecology.view.props.has(id):
		return "查看 " + str(session.ecology.view.props[id].name) + " 的工作"
	return str(markers.get(id, {}).get("label", "联络 / 调查"))

func _access_name(mode: String) -> String:
	return {"public_span":"住区短接", "service_span":"巡检短接"}.get(mode, "尚未锁定")

func request_nearby() -> void:
	if session.network.mode == "guest" and not session._facilities_ready(): return
	var peer = session.network.local_id()
	if not session.players.has(peer): return
	var locked: String = str(session.locks.get(peer,""))
	if session.thermal_cargo.operable_near(peer,locked):
		session.network.send_action("thermal_cargo_operate",{"target_id":locked})
		return
	if session.campaign.operable_near(peer,locked):
		session.network.send_action("campaign_operate",{"target_id":locked})
		return
	var id = nearest(session.players[peer].global_position)
	if id.is_empty():
		session.interface.notify("靠近无线电联络点或调查线索，再按 G。")
		return
	session.network.send_action("explore", {"target_id":id})

func interact(peer_id: int, payload: Dictionary) -> void:
	if not _can_advance() or not session.players.has(peer_id) or not session.players[peer_id].enabled: return
	var id = str(payload.get("target_id", ""))
	if id == "I2:canal_workbench_power" and session.canal != null:
		var confirmation: Dictionary = session.canal.prepare_story_service(peer_id)
		if not confirmation.get("ok",false):
			session._note(peer_id,"工序服务尚未就绪："+str(confirmation.get("code","not_ready")))
			return
		_submit("fact","I2:canal_service_verified","repaired",{},{},confirmation)
		return
	if not markers.has(id):
		# Sender identity is supplied by the original action dispatcher. Never use
		# guest coordinates or dialogue text to prepare an authoritative reply.
		if session.ecology.simulation.get_actor(id).is_empty(): return
		var reply: Dictionary = NpcContact.prepare(session,peer_id,id)
		if not reply.get("ok",false):
			session._note(peer_id,str(reply.text))
			return
		if session.story_jobs.block_existing_contact(peer_id,id): return
		if session.field_requests.block_legacy_contact(peer_id,id): return
		if session.sidejobs.contact(peer_id,reply): return
		session.network.send_event(peer_id,{"kind":"dialogue","character_id":reply.character_id,
			"speaker_name":reply.speaker_name,"lines":reply.lines})
		session._audio_event("interaction",reply.position,reply.source_actor_id)
		return
	var marker: Dictionary = markers[id]
	if marker.region != session.region_id or marker.kind not in ["npc", "inspect"]: return
	if ACCESS_MARKERS.has(id):
		var observer = session.players[peer_id]
		if observer.global_position.distance_to(_point(marker)) > float(marker.radius):
			session._note(peer_id, "靠近桥头控制台，再查看通路。")
			return
		if not session._line_clear(observer.global_position, _point(marker), observer.get_rid(), id):
			session._note(peer_id, "控制台被结构遮住了。换到能看清控制面的一侧。")
			return
		var current: String = session.shared_access.module.status().mode
		if SharedAccess.OBJECTIVE in state.get("completed", []):
			var first: String = str(state.get("choices", {}).get(SharedAccess.OBJECTIVE, ""))
			session._note(peer_id, "首次记录：%s · 当前桥位：%s。可继续调整桥位，原调查记录不会重复领奖。" % [_access_name(first), _access_name(current)])
			return
		if not shared_choice_available():
			session._note(peer_id, "当前桥位：%s。可以使用控制台调整桥位；完成双窗试流调查后，再共同确认通路安排。" % _access_name(current))
			return
		session._action_received(peer_id, "propose", {"kind":"facility_choice", "payload":{"mode":ACCESS_MARKERS[id]}})
		return
	if id in TRIAL_MARKERS:
		if id==TrialSession.RETURN_SWITCH: session.trial.request_return(peer_id)
		else: session.trial.observe_gauge(peer_id,TrialSession.Runtime.RECEIVER_A if id==TrialSession.GAUGE_A else TrialSession.Runtime.RECEIVER_B)
		return
	if id == DistributionProgress.FACT_TARGET:
		# Neither a client's method/pose nor a ray to the marker centre is proof.
		session.distribution.observe(peer_id)
		return
	if id == "F1:shared_junction" and (_fact("F1:light_receiver").is_empty() or _fact("F1:growth_bridge").is_empty()):
		session._note(peer_id, "支路还未稳定：请保持光束对齐，并恢复枝桥，再核对读数。")
		return
	var body = session.players[peer_id]
	if body.global_position.distance_to(_point(marker)) > float(marker.radius):
		session._note(peer_id, "请靠近联络点或线索。")
		return
	var collider_id = {"I1:beacon_echo":"I1:beacon", "F1:shared_junction":"F1:beacon", WHALE_RECORD:"boss:core", CROWN_RECOVERED:"F1:crown_host_west"}.get(id, id)
	if not session._line_clear(body.global_position, _point(marker), body.get_rid(), collider_id):
		session._note(peer_id, "线索被遮挡，请换一侧靠近。")
		return
	if session.content_chapters.interact(peer_id,id): return
	if session.final_story.interact(peer_id,id): return
	if session.combat_sites.interact(peer_id,id): return
	if session.story_jobs.interact(peer_id,id): return
	if session.story_jobs.block_existing_contact(peer_id,id): return
	if session.field_requests.interact(peer_id,id): return
	if marker.get("optional", false):
		if id not in found_notes and not _content_note_ready(peer_id, marker): return
		_collect_note(peer_id, id)
		return
	if session.chapter_choices.open(peer_id,id): return
	if session.campaign.read_manual(peer_id,id): return
	if id == WHALE_RECORD:
		if whale_victory_committed(): _submit("fact", WHALE_RECORD, "retrieved")
		return
	if id == CROWN_RECOVERED:
		if crown_victory_committed() and session.world.crown_defeated and session.world.crown_arena.last_view.is_empty(): _submit("fact", CROWN_RECOVERED, "verified")
		return
	if id in ["I2:clinic_demand", "I2:clinic_water_check"]:
		if not session.clinic.ready: return
		var selected := false
		for target in current_targets():
			if target.target_id == id: selected = true
		if not selected: return
		if id == "I2:clinic_demand":
			_submit("fact", id, "identified")
		else:
			var candidate: Dictionary = session.clinic.progress.prepare_confirm(session.clinic.module.snapshot(), session.clinic.module.status(), session.clinic.access_clear())
			if not candidate.ok:
				session._note(peer_id, "储水尚未稳定或通路被挡住；让开浮台上方，再核对病房读数。")
				return
			_submit("fact", id, "commissioned", candidate)
		return
	for target in current_targets():
		if str(target.target_id) == id and target.type in ["talk", "inspect"]:
			var options: Array = target.get("options", [])
			_submit(str(target.type), id, str(options[0]) if not options.is_empty() else "")
			return
	# Current task/manual/choice G handling above always wins over optional revisits.
	var revisit: Dictionary = PostbossRevisits.reply(state, session.region_id, id)
	if not revisit.is_empty():
		session.network.send_event(peer_id, {"kind":"dialogue", "character_id":revisit.character_id, "lines":revisit.lines})
		session._audio_event("interaction", _point(marker), id)
		return
	if marker.kind == "npc":
		var lines: Array = director.dialogue_lines(state, id)
		if not lines.is_empty():
			session.network.send_event(peer_id, {"kind":"dialogue", "character_id":id, "lines":lines})
			session._audio_event("interaction", _point(marker), id)

func _collect_note(peer_id: int, id: String) -> void:
	var note: Dictionary = markers[id]
	if id not in found_notes:
		if not session._commit("note:" + id, {"world.flags.note:" + id:true}, str(note.discovery_id)): return
		found_notes.append(id)
		serial += 1
		publish()
		session._note_all("发现已记录 · " + str(note.title))
		session._audio_event("task_complete", _point(note), id)
	session.network.send_event(peer_id, {"kind":"dialogue", "character_id":note.character_id, "lines":note.lines})

func _content_note_ready(peer_id: int, marker: Dictionary) -> bool:
	# Read the Host's actual ability state and physical velocity. A marker never
	# changes an entity, bypasses an ability, or completes itself on approach.
	for requirement: Dictionary in marker.get("requires", []):
		var actual: Variant
		if requirement.get("kind", "") == "player_speed":
			actual = session.players[peer_id].linear_velocity.length()
		else:
			var target: String = str(requirement.get("target_id", ""))
			var field: String = str(requirement.get("field", ""))
			if not session.entities.has(target) or not session.entities[target].has(field):
				session._note(peer_id, str(marker.get("requires_hint", "请先恢复这处设备，再读取现场记录。")))
				return false
			actual = session.entities[target][field]
		var expected: Variant = requirement.get("value")
		var satisfied := false
		match str(requirement.get("op", "")):
			"eq": satisfied = actual == expected
			"gte": satisfied = (actual is int or actual is float) and (expected is int or expected is float) and float(actual) >= float(expected)
			"lte": satisfied = (actual is int or actual is float) and (expected is int or expected is float) and float(actual) <= float(expected)
		if not satisfied:
			session._note(peer_id, str(marker.get("requires_hint", "先完成提示中的能力操作，再调查现场。")))
			return false
	return true

func _can_advance() -> bool:
	return ready and session.active and session.owns_world and session.network.is_authority() and not session.simulation_paused and not session.pending_completion and session.consensus.current_proposal().is_empty()

func shared_choice_available() -> bool:
	if not ready or session.region_id != "I2" or SharedAccess.OBJECTIVE in state.get("completed", []): return false
	for target in current_targets():
		if target.type == "fact" and target.target_id == SharedAccess.FACT: return true
	return false

func commit_shared_choice(proposal_id: String, mode: String) -> bool:
	return _submit("fact", SharedAccess.FACT, mode, {}, {"proposal_id":proposal_id})

func commit_campaign_choice(proposal_id: String, target: String, option: String) -> bool:
	var proposal: Dictionary = session.consensus.current_proposal()
	if not session._resolving_decision or proposal.get("kind") != "campaign_choice" or proposal.get("state") != "ready" or proposal.get("proposal_id") != proposal_id: return false
	if proposal.payload.get("target") != target or proposal.payload.get("option") != option: return false
	return _submit("fact",target,option,{}, {"proposal_id":proposal_id})

func observe(delta: float) -> void:
	observe_underdeck(delta)
	clock += delta
	if clock < 0.25 or not _can_advance(): return
	clock = 0.0
	_observe_whale()
	_observe_crown()
	if session.region_id == "F1" and session.world.growth_bridge.collision_layer != 0:
		for peer in session.players:
			var p: Vector3 = session.players[peer].global_position
			if session.players[peer].enabled and absf(p.x) < 11 and absf(p.z - 25) < 1.6 and p.y >= 5.25 and p.y <= 8:
				_root_route[peer] = Time.get_ticks_msec()
	for target in current_targets():
		var id = str(target.target_id)
		if target.type == "fact":
			var option = _fact(id)
			if not option.is_empty():
				if id == "I2:canal_exchange_verified" and session.canal != null: session.request_canal_exchange_fact(option)
				else: _submit("fact", id, option)
				return
		elif target.type == "reach" and markers.has(id):
			var marker: Dictionary = markers[id]
			if marker.region != session.region_id: continue
			for peer in session.players:
				var body = session.players[peer]
				if body.enabled and body.global_position.distance_to(_point(marker)) <= float(marker.radius):
					var option = ""
					if id == "F1:nursery_landing":
						option = "growth" if Time.get_ticks_msec() - int(_root_route.get(peer, -100000)) < 20000 else "flight"
						var blink: Dictionary = last_blink.get(peer, {})
						if Time.get_ticks_msec() - int(blink.get("time", -10000)) < 3000 and Vector3(blink.get("position", Vector3.INF)).distance_to(_point(marker)) <= float(marker.radius): option = "blink"
					_submit("reach", id, option)
					return

func reset_underdeck_tracking(peer_id: int = 0) -> void:
	if peer_id > 0:
		underdeck_action.reset_peer(peer_id)
	else:
		underdeck_action.reset()
		_underdeck_retry = 0.0

func note_underdeck_blink(peer_id: int, from: Vector3, to: Vector3) -> void:
	if session.region_id == "I1" and _can_advance(): underdeck_action.note_blink(peer_id, from, to)

func observe_underdeck(delta: float) -> void:
	if session.region_id != "I1" or not is_instance_valid(session.world.underdeck): return
	# Pauses and votes freeze verified progress; world/respawn resets own its lifetime.
	if not _can_advance(): return
	var objective_id := ""
	for objective in info().get("objectives", []):
		if str(objective.id).begins_with("I1:underdeck:"):
			objective_id = str(objective.id)
			break
	var flags: Dictionary = session.world_cache.get("world", {}).get("flags", {})
	var candidate: Dictionary = underdeck_action.step(delta, session.players, session.entities, objective_id, bool(flags.get("opening:underdeck_latched", false)))
	_underdeck_retry = maxf(0.0, _underdeck_retry - delta)
	if candidate.is_empty() or _underdeck_retry > 0.0: return
	if _submit(str(candidate.kind), str(candidate.target), str(candidate.option)):
		underdeck_action.acknowledge(objective_id)
	else:
		# Keep verified evidence after a disk failure, without writing every frame.
		_underdeck_retry = 1.0

func _fact(id: String) -> String:
	var cargo_fact: String = session.thermal_cargo.fact(id)
	if not cargo_fact.is_empty(): return cargo_fact
	if id == "I2:canal_exchange_verified" and session.canal != null: return session.canal.exchange_fact()
	if session.campaign.supported():
		var campaign_fact: String = session.campaign.fact(id)
		if not campaign_fact.is_empty(): return campaign_fact
	if id == TrialSession.TRACE_TARGET:
		return str(session.trial.committed_flow_fact().get("option", ""))
	if id == DistributionProgress.FACT_TARGET and session.region_id == "I2" and session.distribution.ready:
		return str(session.distribution.progress.fact_for(DistributionProgress.EXPOSE).get("option", ""))
	if session.region_id == "I2" and session.clinic.ready:
		var objective := "I2:clinic_supply:connect" if id == "I2:clinic_feed" else "I2:clinic_supply:stabilize" if id == "I2:clinic_water_ready" else ""
		if not objective.is_empty(): return str(session.clinic.progress.fact_for(objective).get("option", ""))
	if id == "F1:crown_engaged" and session.region_id == "F1":
		if (session.boss_active and session.boss_campaign) or crown_victory_committed(): return "started"
	if id == "F1:crown_defeated" and session.region_id == "F1" and crown_victory_committed(): return "committed"
	if id == "I1:whale_engaged" and session.region_id == "I1":
		if (session.boss_active and session.boss_campaign) or whale_victory_committed(): return "started"
	if id == "I1:whale_defeated" and session.region_id == "I1" and whale_victory_committed(): return "committed"
	if id == "I1:rescue_channel" and session.region_id == "I1":
		if session.world.gate_fraction >= 0.95:
			if float(session.entities.get("I1:thermal", {}).get("temperature", 20)) >= 55: return "heat"
			if bool(session.entities.get("I1:beacon", {}).get("controlled", false)): return "takeover"
			return "charge"
		# Flying around the structure to its rear deck is an actual alternative route.
		for body in session.players.values():
			var p: Vector3 = body.global_position
			if body.enabled and absf(p.x + 24) < 3.5 and p.z >= 19 and p.z <= 23 and p.y >= 5.5 and p.y <= 8: return "aerial"
	if id == "F1:light_receiver" and session.region_id == "F1" and float(session.entities.get("F1:growth", {}).get("environment_light", 0)) >= 1: return "aligned"
	if id == "F1:growth_bridge" and session.region_id == "F1" and float(session.entities.get("F1:growth", {}).get("growth", 0)) >= 0.5 and session.world.growth_bridge.collision_layer != 0: return "grown"
	return ""

func whale_victory_committed() -> bool:
	var flags: Dictionary = session.world_cache.get("world", {}).get("flags", {})
	return bool(flags.get("I1_boss", false)) and bool(flags.get("campaign_whale_v1", false))

func crown_victory_committed() -> bool:
	var flags: Dictionary = session.world_cache.get("world", {}).get("flags", {})
	return bool(flags.get("F1_boss", false)) and bool(flags.get("campaign_crown_v1", false))

func _observe_crown() -> void:
	if session.region_id != "F1" or session.boss_active or crown_victory_committed(): return
	if "F1:crown:brief" not in state.get("completed", []) or not session.crown.ready(): return
	for body in session.players.values():
		if body.enabled and session.world.crown_arena.engagement(body.global_position):
			session._start_boss(true)
			return

func _observe_whale() -> void:
	if session.region_id != "I1" or session.boss_active or whale_victory_committed(): return
	if "I1:whale:brief" not in state.get("completed", []): return
	if not session.world.has_method("whale_ready") or not session.world.whale_ready(): return
	for body in session.players.values():
		if body.enabled and body.global_position.distance_to(session.world.boss_position) <= 18.0:
			session._start_boss(true)
			return

func _submit(type: String, target: String, option: String, clinic_confirmation: Dictionary = {}, shared_confirmation: Dictionary = {}, canal_confirmation: Dictionary = {}) -> bool:
	var shared_choice := target == SharedAccess.FACT
	var campaign_choice := target.ends_with(":chapter_choice")
	if campaign_choice:
		var proposal: Dictionary = session.consensus.current_proposal()
		if not session._resolving_decision or proposal.get("kind") != "campaign_choice" or proposal.get("state") != "ready" or proposal.get("proposal_id") != shared_confirmation.get("proposal_id"): return false
		if proposal.payload.get("target") != target or proposal.payload.get("option") != option or not ready or not session.active or not session.owns_world or not session.network.is_authority() or session.simulation_paused or session.pending_completion: return false
	elif shared_choice:
		var proposal: Dictionary = session.consensus.current_proposal()
		if not session._resolving_decision or proposal.is_empty() or proposal.get("kind") != "facility_choice" or proposal.get("state") != "ready" or proposal.get("proposal_id") != shared_confirmation.get("proposal_id"): return false
		if not ready or not session.active or not session.owns_world or not session.network.is_authority() or session.simulation_paused or session.pending_completion: return false
		if proposal.payload.get("mode") != option or not shared_choice_available(): return false
		# Re-read real pose, lock, routes and observer at the transaction boundary.
		var confirmation: Dictionary = session.shared_access.choice_confirmation(int(proposal.payload.get("observer", 0)), option)
		if not confirmation.ok:
			session._note_all("桥位、锁销或通路已经变化，尚未提交；检查现场后重新确认。")
			return false
	elif not _can_advance(): return false
	if target == TrialSession.TRACE_TARGET and option != str(session.trial.committed_flow_fact().get("option", "")): return false
	if target == DistributionProgress.FACT_TARGET and option != str(session.distribution.progress.fact_for(DistributionProgress.EXPOSE).get("option", "")): return false
	if target == "I2:clinic_water_check" and clinic_confirmation.is_empty(): return false
	if target == "I2:canal_service_verified" and (canal_confirmation.is_empty() or session.canal == null or not canal_confirmation.get("ok",false)): return false
	var event = {"id":"opening:%d:%s:%s" % [int(state.get("revision", 0)), type, target], "type":type, "target_id":target, "option":option}
	var result: Dictionary = director.apply_event(state, event, {"is_authority":true, "validated":true, "region_id":session.region_id})
	if not result.get("ok", false) or not result.get("changed", false): return false
	var changes: Dictionary = {"world.actions.opening":result.state}
	# The action and the physical state it describes are saved in one transaction.
	changes["world.entities." + session.region_id] = session._persistent_environment()
	var discoveries: Array = []
	var objectives: Array = []
	for effect in result.effects:
		if effect.type == "flag": changes["world.flags." + str(effect.key)] = effect.value
		if effect.type == "discovery": discoveries.append(str(effect.discovery_id))
		if effect.type == "objective_completed": objectives.append(str(effect.objective_id))
	var tx = {"id":"%s:%s:%d" % [event.id, str(session.world_cache.world.branch_id), int(session.world_cache.generation)], "set":changes, "append":{"world.completed_objectives":objectives, "personal.discoveries":discoveries}, "guest_rewards":[]}
	tx.set["world.ecology"] = session.ecology.persistent_state()
	tx.set.merge(session.facilities.persistent_states(), false)
	tx.set.merge(session.campaign.persistent_states(), false)
	tx.set.merge(session.chapter_choices.persistent_states(), false)
	var cargo_saved: Dictionary = session.thermal_cargo.capture()
	if not cargo_saved.get("ok",false): return false
	if cargo_saved.has("state"): tx.set[session.ThermalParticipant.PATH] = cargo_saved.state
	var canal_saved: Dictionary = session._canal_persistence()
	if not canal_saved.get("ok", false): return false
	if canal_saved.has("envelope"): tx.set["world.environment.I2_canal"] = canal_saved.envelope
	if target == "I2:canal_exchange_verified" and option == "local_cooling":
		if not canal_saved.has("envelope") or _fact(target) != option: return false
		var preparation: Dictionary = CanalPreparationProof.capture(canal_saved.envelope)
		if not preparation.get("ok",false):
			session._note_all("准备记录尚未形成可恢复证据，请保持现场后重试。")
			return false
		# First completion only: director.changed has already rejected a replay.
		# The real cold snapshot and its original objective share this Store write.
		tx.set["world.environment.I2_canal_preparation"] = preparation.proof
	if not canal_confirmation.is_empty():
		# The exact validated consumption and the original Story receipt/reward
		# share one durable transaction. No second service repository is used.
		tx.set["world.environment.I2_canal"] = canal_confirmation.envelope
	if session.clinic.ready:
		tx.set["world.environment.I2_water"] = session.clinic.persistent_state(clinic_confirmation.get("history", {}))
	for peer in session.network.guests:
		for discovery in discoveries: tx.guest_rewards.append({"guest_id":session.identities[peer], "reward_id":discovery, "payload":{"discoveries":[discovery]}})
	var committed: Dictionary = session.store.commit(tx)
	if not committed.get("ok", false):
		session._note_all("行动记录保存失败，成果尚未提交；可以再次调查或联络。")
		return false
	if not canal_confirmation.is_empty():
		var adopted_service: Dictionary = session.canal.adopt_story_service(canal_confirmation)
		if not adopted_service.get("ok",false):
			session._stop_failed_region_load("工序成果已保存，现场采用未完成；请重新打开此存档继续："+str(adopted_service.get("code","reload_required")))
			return false
	if not clinic_confirmation.is_empty():
		if not session.clinic.progress.adopt_confirm(clinic_confirmation):
			push_error("Committed clinic confirmation could not be adopted")
			return false
		session.clinic.publish()
	session.world_cache = session.store.snapshot()
	session.world.apply_committed_flags(session.world_cache.world.get("flags", {}))
	if not session._resolving_decision: session.consensus.set_world_revision(int(session.world_cache.world_revision))
	state = result.state.duplicate(true)
	serial += 1
	publish()
	session._note_all("")
	for effect in result.effects:
		if effect.type == "dialogue":
			for peer in session.players: session.network.send_event(int(peer), {"kind":"dialogue", "character_id":effect.character_id, "lines":effect.lines})
		elif effect.type == "action_completed": session._note_all(completion_text(str(effect.action_id)))
	session.content_chapters.story_committed(target)
	return true

func completion_text(action_id: String) -> String:
	for action in director.definitions().get("actions", []):
		if action.id == action_id:
			return str(action.get("completion_text", "行动完成 · 记录已保存。"))
	return "行动完成 · 记录已保存。"

func target_anchor(id: String) -> Dictionary:
	_update_canal_service_marker()
	if id == "I2:canal_service_verified" and markers.has("I2:canal_workbench_power"):
		var destination := "I2:canal_workbench_power"
		var label := "先对运输机使用 0 机械接管 / F 下工单，再用 6 电荷 / F 给检修台供电"
		if session.canal!=null and is_instance_valid(session.canal.module):
			var live: Dictionary=session.canal.module.status()
			if not live.get("ready",false) or live.get("restore_pending",false):
				label="等待运输机完成真实对齐与现场恢复"
			elif not live.get("ordered",false):
				destination="I2:canal_carrier"
				label="换匣运输机 · 0 机械接管 / F 启动检修工单"
			else:
				label="检修台 · 6 电荷 / F 供电，扫描完成后 G 领取记录"
		var anchor:=Guidance.resolve_anchor(destination,session.region_id,markers,session.entities)
		if not anchor.is_empty(): anchor.label=label
		return anchor
	if session.campaign.supported():
		var physical_target: String = session.campaign.navigation_target(id)
		if not physical_target.is_empty():
			return Guidance.resolve_anchor(physical_target,session.region_id,markers,session.entities)
	if id == TrialSession.TRACE_TARGET and session.region_id == "I2" and session.trial.ready:
		var readings: Dictionary = session.trial.observed_gauges()
		var label := TrialSession.GAUGE_A if readings.A.is_empty() else TrialSession.GAUGE_B
		return Guidance.resolve_anchor(label, session.region_id, markers, session.entities)
	if id == SharedAccess.FACT and session.region_id == "I2" and session.shared_access.ready:
		var mode: String = session.shared_access.module.status().mode
		if mode not in SharedAccess.Bridge.MODES: mode = "public_span"
		var actual: Dictionary = session.shared_access.choice_anchor(mode)
		if actual.is_empty(): return {}
		var marker: Dictionary = markers[actual.target_id].duplicate(true)
		var half_height := .34
		var local: int = session.network.local_id()
		if session.players.has(local): half_height = float(session.players[local].stats.height_m) * .5
		marker.position = session.shared_access.inspection_position(mode, half_height)
		marker.label = "从落台内侧上方核对，让开桥面与绕廊"
		return Guidance.resolve_anchor(actual.target_id, session.region_id, {actual.target_id:marker}, {})
	if id == "I2:clinic_feed" and session.region_id == "I2" and session.clinic.ready:
		var target := "I2:clinic_gravity_valve"
		var local: int = session.network.local_id()
		if session.players.has(local):
			var at: Vector3 = session.players[local].global_position
			if at.distance_to(session.clinic.module.entity_position("I2:clinic_pump")) < at.distance_to(session.clinic.module.entity_position(target)): target = "I2:clinic_pump"
		var anchor := Guidance.resolve_anchor(target, session.region_id, markers, session.entities)
		if not anchor.is_empty(): anchor.label = "低层电泵（或走高位机械旁路）" if target == "I2:clinic_pump" else "高位机械旁路（或走低层电泵）"
		return anchor
	var live_markers = markers.duplicate()
	for dynamic_id in [WHALE_RECORD, CROWN_RECOVERED]:
		if live_markers.has(dynamic_id):
			live_markers[dynamic_id] = markers[dynamic_id].duplicate()
			live_markers[dynamic_id].position = _point(markers[dynamic_id])
	return Guidance.resolve_anchor(id, session.region_id, live_markers, session.entities)

func display_anchor() -> Dictionary:
	for target in current_targets():
		var anchor = target_anchor(str(target.target_id))
		if not anchor.is_empty(): return anchor
	return {}

func _update_canal_service_marker() -> void:
	var id := "I2:canal_workbench_power"
	if session.region_id != "I2" or not is_instance_valid(session.world) or not session.world.objects.has(id):
		markers.erase(id)
		return
	var at: Vector3 = session.world.objects[id].global_position
	markers[id] = {"id":id,"region":"I2","position":[at.x,at.y,at.z],"kind":"inspect","label":"确认实际扫描与维修服务","radius":4.0}

func objective_text(at: Vector3, detailed: bool = true) -> String:
	if not ready: return "正在同步行动记录…"
	var display: Dictionary = info()
	if display.get("complete", false):
		var ending: Dictionary = CampaignCatalog.ending(state.get("choices",{}))
		if ending.is_empty(): return "共同修复记录已保存。\n按 M 返回各地，继续探索与维护。"
		var summary: String = str(ending.title)
		if detailed:
			for line: String in ending.lines: summary += "\n"+line
			summary += "\n"+str(ending.postgame)
		else: summary += "\n主线行动与共同决定已保存 · M 返回各地"
		return summary
	var text = str(display.get("title", "两界共脉"))
	for objective in display.get("objectives", []):
		text += "\n" + str(objective.text)
		if detailed: text += "\n" + str(objective.get("hint", ""))
		if str(objective.id) == "I1:underdeck:enter" and is_instance_valid(session.world.underdeck) and at.distance_to(session.world.underdeck.anchor_position("entry")) < 12.0:
			text += "\n" + session.world.underdeck.entrance_status_text()
		if session.region_id == "I2" and session.clinic.ready and detailed:
			var water: Dictionary = session.clinic.module.status()
			text += "\n病房储水 %.0f / 2000 L · 浮台顶 %.2fm" % [float(water.clinic_volume_ml) / 1000.0, float(water.deck_top_y)]
			if water.platform_blocked: text += "\n浮台上方或连杆行程受阻，入口已自动停水。"
			elif water.interlock_waiting: text += "\n两路互锁：先关闭高位滑阀，再接通电泵。"
			elif water.selector_blocked: text += "\n选择阀或高处互锁栓的路径被挡住。"
			elif water.gravity_blocked: text += "\n滑阀行程受阻；清障后重新推拉。"
		for target in objective.get("targets", []):
			var anchor = target_anchor(str(target.target_id))
			if not anchor.is_empty():
				var point: Vector3 = anchor.position
				text += ("\n%s  %.1fm · 高差 %+.1fm" % [anchor.label, at.distance_to(point), point.y - at.y]) if detailed else ("\n%.0fm · 高差 %+.1fm" % [at.distance_to(point), point.y - at.y])
				break
	if not str(display.get("next_region", "")).is_empty() and display.next_region != session.region_id:
		if session._can_travel_to(str(display.next_region)):
			var destination = str(Regions.definition(str(display.next_region)).get("name", display.next_region))
			text += ("\n航路已开放 · 按 M 选择" if detailed else "\nM 选择") + destination
			if session.players.size() > 1: text += "（双方确认）"
		else:
			var required: String = Regions.required_action(session.region_id,str(display.next_region))
			if not required.is_empty(): text += "\n完成本区的调查、首领与战后决定后，按 M 确认下一航路。"
			else: text += "\n靠近跨界信标提交修复，然后按 M 跨界。" if detailed else "\n先到跨界信标提交修复。"
	var nearby = nearest(at)
	if detailed and not nearby.is_empty(): text += "\n[G] " + interaction_label(nearby)
	return text
