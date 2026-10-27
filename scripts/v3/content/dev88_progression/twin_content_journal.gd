extends RefCounted
## The Host supplies a bounded read-only notebook through the original event RPC.
const KIND := "content_journal88"
const Regions = preload("res://scripts/v3/world/twin_region_catalog.gd")
const Rewards = preload("res://scripts/v3/content/dev88_progression/twin_dev88_rewards.gd")
const Chapters = preload("res://scripts/v3/content/npc_story_next/twin_npc_story_catalog.gd")
const FieldCatalog = preload("res://scripts/v3/content/npc_story_next/twin_npc_story_catalog.gd")
const OldJobs = preload("res://scripts/v3/ecology/twin_npc_sidejob_state.gd")
const FinalStory = preload("res://scripts/v3/content/final_story/twin_final_story_catalog.gd")
var session
var tracked: Dictionary = {}

func setup(owner_session) -> void:
	session = owner_session

func reset_connection() -> void:
	tracked.clear()
	if is_instance_valid(session.interface.journal): session.interface.journal.hide()

func request(peer: int) -> void:
	if not session.active or not session.owns_world or not session.network.is_authority() or not session.players.has(peer): return
	session.network.send_event(peer, {"kind":KIND, "session_id":session.network.session_id, "document":document()})

func receive(event: Dictionary) -> void:
	if event.get("kind") != KIND or not session.active: return
	var expected: String = session.received_session if session.network.mode == "guest" else session.network.session_id
	if event.get("session_id") != expected: return
	var doc: Variant = event.get("document")
	if not doc is Dictionary or not doc.get("regions") is Array or doc.regions.size() != 8: return
	for book: Variant in doc.regions:
		if not book is Dictionary or not Regions.playable(str(book.get("id", ""))) or not book.get("sections") is Array or book.sections.size() > 6: return
		for section: Variant in book.sections:
			if not section is Dictionary or not section.get("rows") is Array or section.rows.size() > 32: return
			for row: Variant in section.rows:
				if not row is Dictionary or str(row.get("title", "")).length() > 200 or str(row.get("text", "")).length() > 6000: return
	session.interface.menu.hide()
	session.interface.travel.hide()
	session.interface.journal.show_document(doc)

func track(anchor: Dictionary) -> void:
	if anchor.is_empty():
		tracked.clear()
		session.interface.journal.hide()
		session.interface.notify("已恢复主线导航。")
		return
	var point: Variant = anchor.get("position")
	if not point is Array or point.size() != 3 or not Regions.playable(str(anchor.get("region", ""))): return
	for value: Variant in point:
		if not (value is int or value is float) or not is_finite(float(value)): return
	tracked = anchor.duplicate(true)
	session.interface.journal.hide()
	session.interface.notify("已追踪：" + str(anchor.get("label", "支线")) + " · L 打开纪事切换")

func target() -> Dictionary:
	if tracked.is_empty() or str(tracked.get("region", "")) != session.region_id: return {}
	var p: Array = tracked.position
	var at := Vector3(float(p[0]), float(p[1]), float(p[2]))
	var id: String = str(tracked.get("anchor_id", ""))
	if session.story.markers.has(id): at = session.story._point(session.story.markers[id])
	elif session.entities.has(id): at = session.entities[id].position
	elif is_instance_valid(session.ecology.view) and session.ecology.view.actors.has(id): at = session.ecology.view.actors[id].global_position
	return {"anchor_id":id,"position":at,"label":"支线 · " + str(tracked.get("label", "联络点"))}

func document() -> Dictionary:
	var books: Array = []
	var world: Dictionary = session.world_cache.world
	var discovered: Array = session.world_cache.personal.discoveries
	var old: Dictionary = OldJobs.restore(world.get("npc_sidejobs_v1", {}))
	var rows88: Array = session.story_jobs.display_rows()
	var rows87: Array = session.field_requests.display_rows()
	var original_specs: Dictionary = session.sidejobs.definitions
	var all_notes: Array = Rewards.notes()
	var choice_book: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/v3/campaign/choices.json"))
	for region: String in ["I1", "F1", "I2", "F2", "I3", "F3", "I4", "F4"]:
		var sections: Array = []
		var jobs: Array = []
		for id: String in OldJobs.SPECS:
			var spec: Dictionary = OldJobs.SPECS[id]
			if spec.region != region: continue
			var row: Dictionary = old.get("state", {}).get("jobs", {}).get(id, {})
			var actor: Dictionary = session.ecology.simulation.get_actor(str(spec.npc))
			var note: Dictionary = original_specs.get(id, {})
			jobs.append({"title":str(note.get("title", "同伴委托")), "status":_status(str(row.get("status", "available"))),
				"text":str(note.get("consequence", "")) if row.get("status") == "complete" else str(note.get("work_hint", "靠近本区活动同伴按G联络。")),
				"anchor":_marker_anchor(str(spec.npc), region, str(note.get("title", "同伴委托"))) if region == session.region_id and not actor.is_empty() else {}})
		for row: Dictionary in rows87:
			if row.region != region: continue
			jobs.append({"title":str(row.title), "status":_status(str(row.status)), "text":"靠近本区西侧联络台查看本轮巡访和同伴作业记录。",
				"anchor":_marker_anchor(str(row.npc_id), region, str(row.title))})
		if region in FieldCatalog.REGIONS:
			var saved_visit := false
			for row: Dictionary in rows87:
				if row.region == region: saved_visit = true; break
			if not saved_visit:
				var visit: Dictionary = FieldCatalog.definition(region)
				jobs.append({"title":str(visit.title),"status":"可接取","text":str(visit.work_hint).replace("{contact}", "G"),
					"anchor":_marker_anchor(FieldCatalog.contact_id(region), region, str(visit.title))})
		for row: Dictionary in rows88:
			if row.region != region: continue
			var target_id: String = str(row.get("target_id", ""))
			var anchor: Dictionary = _marker_anchor(target_id, region, str(row.title))
			if anchor.is_empty() and row.get("position") is Array:
				anchor = {"anchor_id":target_id,"region":region,"label":str(row.title),"position":row.position.duplicate()}
			jobs.append({"title":str(row.title), "status":_status(str(row.get("status", "available"))), "text":str(row.get("hint", "联络委托人。")), "anchor":anchor})
		sections.append({"title":"伙伴与支线", "rows":jobs})
		var secrets: Array = []
		for row: Dictionary in all_notes:
			if row.region != region: continue
			var found: bool = str(row.discovery_id) in discovered
			secrets.append({"title":str(row.title) if found else str(row.label), "status":"已发现" if found else "等待探索",
				"text":"\n".join(PackedStringArray(row.lines)) if found else "沿不同高度和支路留意现场痕迹；靠近后主动调查，不会自动领取。",
				"anchor":_marker_anchor(str(row.id), region, str(row.title)) if found else {}})
		sections.append({"title":"四处现场秘密", "rows":secrets})
		var combat_rows: Array = session.combat_sites.journal_rows(region)
		if not combat_rows.is_empty(): sections.append({"title":"可选战斗遭遇", "rows":combat_rows})
		var choices: Array = []
		for objective: String in session.story.state.get("choices", {}):
			if not objective.begins_with(region + ":"): continue
			var option: String = str(session.story.state.choices[objective])
			var offer: Dictionary = choice_book.get("choices", {}).get(region + ":chapter_choice", {})
			for item: Dictionary in offer.get("options", []):
				if item.id == option: choices.append({"title":str(item.label),"status":"已共同确认","text":str(item.consequence) + "\n保底：" + str(item.baseline)})
		var ending: Dictionary = Chapters.ending(session.story.state.get("choices", {}))
		if region == "F4" and not ending.is_empty(): choices.append({"title":str(ending.title),"status":"后日谈","text":"\n".join(PackedStringArray(ending.lines))})
		if not choices.is_empty(): sections.append({"title":"共同决定与后续", "rows":choices})
		var aftermath: Array = []
		for archive: Dictionary in FinalStory.journal_rows(session.story.state, world, region):
			aftermath.append({"title":str(archive.title),"status":"终章后记" if archive.status == "epilogue" else "战后留档",
				"text":"\n".join(PackedStringArray(archive.lines)),"anchor":_marker_anchor(str(archive.target_id),region,str(archive.title))})
		if not aftermath.is_empty(): sections.append({"title":"此后的日常 · 留档", "rows":aftermath})
		var reward_text := ""
		for reward: Dictionary in Rewards.unlocks(discovered):
			if reward.region == region: reward_text = "探索记录 %d/%d · 四处集齐后在机库提供现有模块的另一条解锁途径。" % [int(reward.found), int(reward.total)]
		books.append({"id":region,"name":str(Regions.definition(region).get("name", region)),"summary":reward_text + "\n纪事只记实际保存结果；追踪只改变你的导航标记，不推进任务。", "sections":sections})
	return {"region":session.region_id,"regions":books}

func _marker_anchor(id: String, region: String, label: String) -> Dictionary:
	if not session.story.markers.has(id):
		if region == session.region_id and is_instance_valid(session.ecology.view) and session.ecology.view.actors.has(id):
			var live: Vector3 = session.ecology.view.actors[id].global_position
			return {"anchor_id":id,"region":region,"label":label,"position":[live.x, live.y, live.z]}
		return {}
	var marker: Dictionary = session.story.markers[id]
	var point: Variant = marker.get("position", [])
	if point is Vector3: point = [point.x, point.y, point.z]
	if not point is Array or point.size() != 3: return {}
	return {"anchor_id":id,"region":region,"label":label,"position":point.duplicate()}

func _status(value: String) -> String:
	return str({"available":"可接取", "locked":"待章节决定", "active":"进行中", "ready":"可交接", "complete":"已完成", "completed":"已完成"}.get(value, value))
