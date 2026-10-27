extends RefCounted
## Content presentation only. Original Story, Boss and choice commits own facts.
## Development batch 87: authored and integrated, not playtested.
const Catalog = preload("res://scripts/v3/content/npc_story_next/twin_npc_story_catalog.gd")
const Props = preload("res://scripts/v3/content/presentation_next/twin_content_prop_factory.gd")
const Regions = preload("res://scripts/v3/world/twin_region_catalog.gd")
const Routes = preload("res://scripts/v3/content/world_content_next/twin_world_content_catalog.gd")
const Voices88 = preload("res://scripts/v3/content/dev88_presentation/twin_dev88_sound_routes.gd")
var session
var _context := ""
var _queue: Array[Dictionary] = []
var _shown: Dictionary = {}
var _board: Node3D
var _caption: Label3D
var _visual_key := ""
var _victory := false
var _clock := 0.0

func setup(owner_session) -> void:
	session = owner_session

static func markers() -> Array:
	var result: Array = []
	for region: String in ["I1", "F1", "I2", "F2", "I3", "F3", "I4", "F4"]:
		var at: Vector3 = Regions.spawn(region) + Vector3(-6.5, 1.0, -2.5)
		result.append({"id":region + ":chapter_notice", "region":region, "kind":"inspect", "position":[at.x, at.y, at.z], "radius":5.0, "optional":true, "label":"阅读航路、伙伴与共同决定"})
	return result

func interact(peer: int, id: String) -> bool:
	if id != session.region_id + ":chapter_notice": return false
	if not session.owns_world or not session.network.is_authority() or not session.players.has(peer): return true
	var lines: Array = []
	var entry: Dictionary = Catalog.entry(session.story.state, session.region_id)
	lines.append_array(entry.get("lines", []))
	var response: Dictionary = Catalog.reaction(session.story.state, session.region_id, "choice_after")
	lines.append_array(response.get("lines", []))
	for route: Dictionary in Routes.route_rows(session.region_id):
		lines.append(str(route.get("name", route.get("title", "可选支路"))) + "：" + str(route.get("hint", route.get("description", "沿侧边航标探索，再回原主路继续。"))))
	var ending: Dictionary = Catalog.ending(session.story.state.get("choices", {}))
	if not ending.is_empty():
		lines.append(str(ending.title))
		lines.append_array(ending.get("lines", []))
		lines.append(str(ending.get("postgame", "")))
	if lines.is_empty(): lines.append("保留原主路；侧边航标通向可选调查与能力练习。完成后可以原路返航。")
	session.network.send_event(peer, {"kind":"dialogue", "character_id":"npc:linlan", "speaker_name":"两界航路纪事", "lines":lines})
	session._audio_event("interaction", session.story._point(session.story.markers[id]), id)
	return true

func reset_connection() -> void:
	clear_transient()
	_shown.clear()

func clear_transient() -> void:
	_context = ""
	_queue.clear()
	_board = null
	_caption = null
	_visual_key = ""
	_clock = 0.0

func bind_world() -> void:
	clear_transient()
	_victory = _victory_committed()
	if not is_instance_valid(session.world): return
	_board = Node3D.new()
	_board.name = "ChapterNotice87"
	session.world.add_child(_board)
	# A non-colliding information bay beside the original arrival, never a gate.
	_board.position = session.world.spawn_position + Vector3(-6.5, -1.0, -2.5)
	_board.add_child(Props.make("archive_stela", session.region_id))
	_caption = Label3D.new()
	_caption.position = Vector3(0, 3.4, 0)
	_caption.font_size = 25
	_caption.pixel_size = .011
	_caption.outline_size = 5
	_caption.modulate = Color("d0eee2")
	_caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_board.add_child(_caption)

func advance(delta: float) -> void:
	if not session.active or not is_instance_valid(session.world) or not session.story.ready: return
	_clock += delta
	if _clock < .25: return
	_clock = 0.0
	var state: Dictionary = session.story.state
	_present(state)
	if not session.network.is_authority() or not session.owns_world: return
	var context := "%s:%s:%s" % [session.network.session_id, str(session.world_cache.world.branch_id), session.region_id]
	if context != _context:
		_context = context
		_enqueue(Catalog.entry(state, session.region_id), "radio_" + session.region_id.to_lower() + "_entry")
	var victory := _victory_committed()
	if victory and not _victory:
		_enqueue(Catalog.reaction(state, session.region_id, "boss_after"), "radio_f4_victory" if session.region_id == "F4" else "")
	_victory = victory
	if _queue.is_empty() or not _can_broadcast(): return
	var item: Dictionary = _queue.pop_front()
	var key := _context + ":" + str(item.get("key", item.get("title", "")))
	if _shown.has(key): return
	_shown[key] = true
	for peer in session.players:
		session.network.send_event(int(peer), {"kind":"dialogue", "character_id":str(item.get("character_id", "npc:linlan")),
			"speaker_name":str(item.get("speaker_name", "两界联络")), "lines":item.get("lines", [])})
	var cue := str(item.get("cue", ""))
	var lines: Array = item.get("lines", [])
	var line_cue := Voices88.cue_for_line(str(item.get("character_id", "")), str(lines[0]) if not lines.is_empty() else "", str(item.get("speaker_name", "")))
	if not cue.is_empty() and line_cue.is_empty(): session._audio_event(cue, session.world.spawn_position, "chapter:" + session.region_id)

func story_committed(target: String) -> void:
	if not session.network.is_authority() or not session.owns_world: return
	var state: Dictionary = session.story.state
	_enqueue(Catalog.reaction(state, session.region_id, "boss_after"), "radio_f4_victory" if session.region_id == "F4" else "")
	if target.ends_with(":chapter_choice"):
		if session.region_id == "F4":
			var ending: Dictionary = Catalog.ending(state.get("choices", {}))
			if not ending.is_empty():
				var lines: Array = [str(ending.title)]
				lines.append_array(ending.get("lines", []))
				lines.append(str(ending.get("postgame", "")))
				var cue: String = str({"shared_stewardship":"radio_ending_care", "industrial_lifeline":"radio_ending_industry", "living_vein":"radio_ending_living"}.get(str(ending.get("ending_id", "")), "radio_final"))
				_enqueue({"key":"ending:" + str(ending.get("ending_id", "")), "character_id":"npc:guanzhi", "speaker_name":"两界共脉 · 后日谈", "title":ending.title, "lines":lines}, str(cue))
		else:
			_enqueue(Catalog.reaction(state, session.region_id, "choice_after"))
	elif target == "F4:plans_reviewed":
		_enqueue({"key":"F4:plans_explained87", "character_id":"npc:guanzhi", "speaker_name":"冠枝 · 方案阅读", "title":"三种方案都留在确认台",
			"lines":["共同照料、工业生命线、活体脉络都有要承担的代价。已读记录不会替你们选择；恢复两路底线后，再在确认台作最后决定。"]}, "radio_final")
	elif target.ends_with(":boss_briefing"):
		_enqueue(Catalog.reaction(state, session.region_id, "boss_before"))
	elif target.ends_with(":boss_record"):
		_enqueue(Catalog.reaction(state, session.region_id, "chapter_after"))
	_present(state)

func _enqueue(item: Dictionary, cue := "") -> void:
	if item.is_empty() or item.get("lines", []).is_empty(): return
	var key := str(item.get("key", item.get("title", "")))
	if _shown.has(_context + ":" + key): return
	for pending: Dictionary in _queue:
		if str(pending.get("key", pending.get("title", ""))) == key: return
	if _queue.size() >= 6: _queue.pop_front()
	var copy := item.duplicate(true)
	copy["cue"] = cue
	_queue.append(copy)

func _can_broadcast() -> bool:
	var ui = session.interface
	return not session.simulation_paused and not session.boss_active and not session.pending_completion and session.consensus.current_proposal().is_empty() and not ui.radio.visible and not ui.journal.visible and not ui.menu.visible and not ui.hangar.visible and not ui.travel.visible and not ui.chapter_choice.visible and not ui.vote.visible

func _victory_committed() -> bool:
	if session == null or not session.owns_world: return false
	if session.region_id == "I1": return session.story.whale_victory_committed()
	if session.region_id == "F1": return session.story.crown_victory_committed()
	return session.campaign.victory_committed() if session.campaign.supported() else false

func _present(state: Dictionary) -> void:
	if not is_instance_valid(_board) or not is_instance_valid(_caption): return
	var entry: Dictionary = Catalog.entry(state, session.region_id)
	var ending: Dictionary = Catalog.ending(state.get("choices", {}))
	var reaction: Dictionary = Catalog.reaction(state, session.region_id, "choice_after")
	var text := str(entry.get("title", "两界联络记录"))
	if not reaction.is_empty(): text += "\n共同决定已记录 · G 阅读后续"
	if session.region_id == "F4" and not ending.is_empty(): text = str(ending.title) + "\n返航与各地维护继续开放"
	if _visual_key == text: return
	_visual_key = text
	_caption.text = text
	if session.region_id == "F4" and not ending.is_empty():
		var tableau = _board.get_node_or_null("EpilogueTableau")
		if tableau != null: tableau.free()
		tableau = Node3D.new()
		tableau.name = "EpilogueTableau"
		_board.add_child(tableau)
		var ending_id := str(ending.get("ending_id", ""))
		var kinds: Array = ["refuge_shelter", "memorial_lantern", "root_canopy"]
		if ending_id == "industrial_lifeline": kinds = ["coolant_stack", "memorial_lantern", "resonance_pylon"]
		elif ending_id == "living_vein": kinds = ["fungus_garden", "memorial_lantern", "root_canopy"]
		for index in range(3):
			var prop := Props.make(str(kinds[index]), "F4", index)
			prop.position = Vector3((index - 1) * 3.0, 0, -3)
			tableau.add_child(prop)
