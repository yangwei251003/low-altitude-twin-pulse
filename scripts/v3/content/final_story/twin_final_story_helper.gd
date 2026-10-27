extends RefCounted
## Re-readable archive interaction only. No Store/Gate, rewards or new clock.
const Catalog = preload("res://scripts/v3/content/final_story/twin_final_story_catalog.gd")
var session
var presence: Callable

func setup(owner_session, presence_source: Callable = Callable()) -> void:
	session = owner_session
	presence = presence_source

func reset_connection() -> void:
	pass

func clear_transient() -> void:
	pass

func bind_world() -> void:
	pass

func interact(peer: int, id: String) -> bool:
	var marker: Dictionary = {}
	for row: Dictionary in Catalog.all_markers():
		if row.id == id:
			marker = row
			break
	if marker.is_empty(): return false
	if not is_instance_valid(session) or not session.active or not session.owns_world or not session.network.is_authority(): return true
	if session.simulation_paused or session.boss_active or session.pending_completion or not session.consensus.current_proposal().is_empty(): return true
	if not Catalog.marker_available(session.story.state,id) or marker.region != session.region_id: return true
	if not session.players.has(peer) or not session.players[peer].enabled: return true
	var body: Variant = session.players[peer]
	var point: Array = marker.position
	var at := Vector3(float(point[0]),float(point[1]),float(point[2]))
	if body.global_position.distance_to(at) > float(marker.radius) or not session._line_clear(body.global_position,at,body.get_rid(),id): return true
	var known_presence: Dictionary = presence.call() if presence.is_valid() else {}
	var reply: Dictionary = Catalog.revisit(session.story.state,session.world_cache.world,id,known_presence)
	if reply.is_empty(): return true
	session.network.send_event(peer,{"kind":"dialogue","character_id":reply.character_id,"speaker_name":reply.speaker_name,"lines":reply.lines})
	session._audio_event("interaction",at,id)
	return true
