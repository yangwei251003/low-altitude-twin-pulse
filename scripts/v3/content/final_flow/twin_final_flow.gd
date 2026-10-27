extends RefCounted
## Completion presentation reads committed Story state, with no new save/clock.
const Story = preload("res://scripts/v3/content/final_story/twin_final_story_catalog.gd")
const HANDBOOK := "res://data/v3/content/final_flow/flight_handbook.json"
var session
var _return_to_menu := true
var _ending_shown := false
var _intro_hint_shown := false

func setup(owner_session) -> void:
	session = owner_session

func reset_connection() -> void:
	_ending_shown = false
	_intro_hint_shown = false
	if is_instance_valid(session.interface.campaign_book): session.interface.campaign_book.hide()

func open_handbook(page := "") -> void:
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(HANDBOOK))
	if not doc is Dictionary or not doc.get("pages") is Array: return
	var initial: String = page
	if initial.is_empty(): initial = session.region_id if session.active and not session.story.state.get("completed", []).is_empty() else "begin"
	_open("飞行手册与八区导览", doc.pages, initial)

func open_ending() -> void:
	var host_world: Dictionary = session.world_cache.world if session.owns_world else {}
	var cards: Array = Story.ending_cards(session.story.state, host_world)
	if cards.is_empty():
		session.interface.notify("终章记录尚未开放。请沿当前主线完成中枢与共同决定。")
		return
	var book: Variant = JSON.parse_string(FileAccess.get_file_as_string(HANDBOOK))
	if book is Dictionary:
		for page: Dictionary in book.get("pages", []):
			if page.get("id") == "credits": cards.append(page.duplicate(true))
	_open("两界共脉 · 终章与此后的日常", cards)
	_ending_shown = true

func close_book() -> void:
	session.interface.campaign_book.hide()
	session.audio.stop_radio()
	session.interface.menu.visible = _return_to_menu

func advance() -> void:
	if not session.active or not is_instance_valid(session.world): return
	if not _intro_hint_shown and session.story.ready:
		_intro_hint_shown = true
		if session.story.state.get("completed", []).is_empty(): session.interface.notify("第一次出航先试短距起步、制动和升降。H可重读飞行手册；左上目标指向下一步。")
	if _ending_shown or not Story.ending_ready(session.story.state): return
	var ui = session.interface
	if ui.radio.visible or ui.menu.visible or ui.hangar.visible or ui.journal.visible or ui.campaign_book.visible or ui.chapter_choice.visible or ui.vote.visible or ui.travel.visible or ui.wheel.visible: return
	if session.boss_active or session.campaign.active() or session.pending_completion: return
	open_ending()

func _open(title: String, cards: Array, selected := "") -> void:
	_return_to_menu = session.interface.menu.visible
	# The existing menu owns flight blocking and optional-combat ceasefire.
	# In cooperation this remains a local menu, never a new shared pause.
	session.interface.menu.show()
	session.audio.stop_radio()
	session.interface.campaign_book.show_book(title, cards, selected)
