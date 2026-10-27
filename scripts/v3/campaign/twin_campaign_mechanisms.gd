class_name TwinCampaignMechanisms
extends RefCounted
## Mechanism adapter over the original entities and real bodies, not a world bank.
## Call only on host physics frames; Root saves this history with those entities.
const Catalog = preload("res://scripts/v3/campaign/twin_campaign_catalog.gd")
const OpticalPath = preload("res://scripts/v3/campaign/twin_optical_path.gd")
const STEP_USEC := 100000
var world: Node3D
var bodies: Dictionary = {}
var region := ""
var authority := false
var _entities: Dictionary = {}
var _players: Dictionary = {}
var _markers: Dictionary = {}
var _facts: Dictionary = {}
var _state: Dictionary = {}
var _view: Dictionary = {"beam_valid":false,"beam_segments":[],"thermal_connected":false}

func configure(owner_world: Node3D, real_bodies: Dictionary = {}, is_authority: bool = true) -> Dictionary:
	if not _state.is_empty() or not is_instance_valid(owner_world): return _no("already_configured_or_world_missing")
	world = owner_world
	region = str(world.region_id)
	if region not in ["F2","I3","F3","I4","F4"]: return _no("unsupported_mechanism_region")
	bodies = real_bodies if not real_bodies.is_empty() else world.objects
	authority = is_authority
	_facts = Catalog.facts()
	var path := "res://data/v3/campaign/" + region.to_lower() + "_actions.json"
	var pack: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not pack is Dictionary: return _no("campaign_data_missing")
	for marker in pack.get("markers", []): _markers[str(marker.id)] = marker.duplicate(true)
	_state = {"schema_version":1,"region_id":region,"tick":0,"pending_usec":0,"serial":0,
		"readings":{},"methods":{},"facts":{},"histories":{},
		"thermal":{"source_loss_j":0,"sink_gain_j":0,"dissipated_j":0,"transfers":0,"first_record":{}}}
	return _yes("configured")

func advance(delta: float, entities: Dictionary, players: Dictionary, paused: bool = false) -> Dictionary:
	if not authority: return _no("authority_required")
	if _state.is_empty() or not is_instance_valid(world): return _no("not_configured")
	if not is_finite(delta) or delta < 0.0 or delta > 1.0: return _no("invalid_delta")
	_entities = entities
	_players = players
	if paused or delta == 0.0: return _yes("paused")
	_state.pending_usec += int(round(delta * 1000000.0))
	var before: Dictionary = _state.facts.duplicate(true)
	var changes: Dictionary = {}
	while int(_state.pending_usec) >= STEP_USEC:
		_state.pending_usec -= STEP_USEC
		_state.tick += 1
		match region:
			"F2": _observe_mirror()
			"I3": _exchange_heat(changes)
	return {"ok":true,"code":"advanced","events":[],"entity_changes":changes,
		"facts_changed":before != _state.facts}

func fact(target: String) -> String:
	return str(_state.get("facts", {}).get(target,""))

func persistent_state() -> Dictionary:
	return _state.duplicate(true)

func view_state() -> Dictionary:
	return _view.duplicate(true)

func observe_interaction(peer, id: String, method: String = "") -> Dictionary:
	# Root first verifies the live marker, input, range and LOS. Recheck identity
	# and distance here so this cannot be an arbitrary remote journal write.
	if not authority or _state.is_empty(): return _no("authority_required")
	if not _players.has(peer) or not _active(_players[peer]): return _no("actor_inactive")
	if not _markers.has(id): return _no("not_a_manual_marker")
	var at: Vector3 = _marker_point(id)
	if _player_position(_players[peer]).distance_to(at) > float(_markers[id].radius) + 0.05: return _no("reading_out_of_range")
	if not _line_clear(_player_position(_players[peer]),at,[_player_rid(_players[peer])],id): return _no("reading_occluded")
	if _state.readings.has(id): return _yes("already_read")
	_state.serial += 1
	_state.readings[id] = {"peer":str(peer),"serial":int(_state.serial)}
	if not method.is_empty(): _state.methods[id] = method
	if region == "F2" and _state.readings.has("F2:record_low") and _state.readings.has("F2:record_high"):
		_set_fact("F2:paired_records","both_read")
	return _yes("manual_reading_recorded")

func observe_ability(peer, id: String, ability: String) -> Dictionary:
	# Call after the original Rules/physics transaction succeeds. This records
	# method attribution only; no ability call directly completes a fact.
	if not authority or not _players.has(peer) or not _active(_players[peer]): return _no("actor_inactive")
	if not is_instance_valid(_body(id)) or ability not in ["push_pull","light","heat","charge","growth","force_field","echo","takeover"]: return _no("invalid_ability_observation")
	_state.methods[id] = ability
	return _yes("method_recorded")

func boss_environment(requested_region: String = "") -> Dictionary:
	var target: String = region if requested_region.is_empty() else requested_region
	if target != region: return {}
	# Root supplies I2 via the original waterwork modules. New fields are exposed
	# only when their real scene targets exist; puzzle completion is insufficient.
	if target == "I3":
		var radiator: Variant = _entities.get("I3:boss_radiator")
		var crawler: Node3D = _body("I3:boss_chassis")
		if not radiator is Dictionary or not _number(radiator.get("temperature")) or not crawler is RigidBody3D: return {}
		return {"radiator_temperature_milli_c":int(round(float(radiator.temperature)*1000.0)),"crawler_speed_mm_s":int(round(crawler.linear_velocity.length()*1000.0))}
	if target == "F2":
		var source: Node3D = _body("F2:reveal_source")
		var real_body: Node3D = _body("F2:true_body")
		var receiver: Node3D = _body("F2:shadow_receiver")
		if not is_instance_valid(source) or not is_instance_valid(real_body) or not is_instance_valid(receiver): return {}
		var light: Dictionary = _entities.get("F2:reveal_source",{})
		if maxf(float(light.get("light_level",0.0)),float(light.get("environment_light",0.0))) < .5:
			return {"true_body_revealed":false,"shadow_verified":false}
		var actual: Dictionary = _ray(source.global_position,receiver.global_position,[_rid(source)])
		var blocked_by_true: bool = _is_body(actual.get("collider"),real_body,"F2:true_body")
		return {"true_body_revealed":blocked_by_true,"shadow_verified":blocked_by_true}
	return {}

func validate_state(saved: Dictionary) -> Dictionary:
	if _state.is_empty() or saved.size() != _state.size() or saved.get("schema_version") != 1 or saved.get("region_id") != region: return _no("mechanism_state_identity")
	for key in _state:
		if not saved.has(key): return _no("mechanism_state_keys")
	for key in ["tick","pending_usec","serial"]:
		if not _integer(saved.get(key),0,2147483647): return _no("mechanism_state_counter")
	if int(saved.pending_usec) >= STEP_USEC: return _no("mechanism_state_fraction")
	for key in ["readings","methods","facts","histories","thermal"]:
		if not saved[key] is Dictionary: return _no("mechanism_state_dictionary")
	if saved.readings.size() > _markers.size() or saved.methods.size() > 64 or saved.facts.size() > 32 or saved.histories.size() > 32: return _no("mechanism_state_limit")
	for id in saved.readings:
		var reading: Variant = saved.readings[id]
		if not _markers.has(id) or not reading is Dictionary or reading.size() != 2 or not reading.get("peer") is String or not _integer(reading.get("serial"),1,int(saved.serial)): return _no("mechanism_reading_invalid")
	for id in saved.methods:
		if not id is String or id.length() > 160 or not saved.methods[id] is String or saved.methods[id].length() > 80: return _no("mechanism_method_invalid")
	for target in saved.facts:
		if not _facts.has(target) or _facts[target].region_id != region or saved.facts[target] not in _facts[target].options: return _no("mechanism_fact_invalid")
	var heat: Dictionary = saved.thermal
	if heat.size() != 5 or not heat.get("first_record") is Dictionary: return _no("mechanism_heat_invalid")
	for key in ["source_loss_j","sink_gain_j","dissipated_j","transfers"]:
		if not _integer(heat.get(key),0,9007199254740000): return _no("mechanism_heat_invalid")
	if int(heat.source_loss_j) != int(heat.sink_gain_j) + int(heat.dissipated_j): return _no("mechanism_heat_not_conserved")
	if not heat.first_record.is_empty():
		if heat.first_record.size() != 4: return _no("mechanism_heat_record_invalid")
		for key in ["source_before_milli_c","source_after_milli_c","sink_before_milli_c","sink_after_milli_c"]:
			if not _integer(heat.first_record.get(key),-40000,200000): return _no("mechanism_heat_record_invalid")
	if saved.facts.has("F2:paired_records") and (not saved.readings.has("F2:record_low") or not saved.readings.has("F2:record_high")): return _no("mechanism_reading_proof_missing")
	if saved.facts.has("F2:clock_light_path") and not saved.histories.has("F2:clock_light_path"): return _no("mechanism_light_proof_missing")
	if saved.facts.has("I3:thermal_transfer_verified") and (int(heat.source_loss_j) < 10000 or heat.first_record.is_empty()): return _no("mechanism_heat_proof_missing")
	return _yes("mechanism_state_valid")

func restore(saved: Dictionary) -> Dictionary:
	var checked: Dictionary = validate_state(saved)
	if not checked.ok: return checked
	_state = saved.duplicate(true)
	for key in ["tick","pending_usec","serial"]: _state[key] = int(_state[key])
	for key in ["source_loss_j","sink_gain_j","dissipated_j","transfers"]: _state.thermal[key] = int(_state.thermal[key])
	return _yes("mechanism_history_restored")

func _observe_mirror() -> void:
	_view.beam_valid = false
	_view.beam_segments = []
	var source: Node3D = _body("F2:clock_source")
	var mirror: Node3D = _body("F2:clock_mirror")
	var receiver: Node3D = _body("F2:clock_receiver")
	if not is_instance_valid(source) or not is_instance_valid(mirror) or not is_instance_valid(receiver): return
	var state: Dictionary = _entities.get("F2:clock_source",{})
	if float(state.get("light_level",0.0)) < .5: return
	var path: Dictionary = OpticalPath.trace(world,source as PhysicsBody3D,mirror as PhysicsBody3D,receiver as PhysicsBody3D,_body("F2:clock_mirror_bypass") as PhysicsBody3D)
	for segment: Array in path.segments: _view.beam_segments.append([_mm(segment[0]),_mm(segment[1])])
	if not path.valid: return
	_view.beam_valid = true
	if not _state.histories.has("F2:clock_light_path"):
		# Preserve the original four-field accepted-evidence schema. The second
		# mirror's angle uses normal entity persistence, never a new reward/fact.
		_state.histories["F2:clock_light_path"] = {"source_mm":_mm(source.global_position),"mirror_hit_mm":_mm(path.mirror_hits[0].position),"receiver_hit_mm":_mm(path.receiver_hit),"tick":int(_state.tick)}
	var method: String = "takeover_mirror" if _state.methods.get("F2:clock_mirror","") == "takeover" else "manual_mirror"
	_set_fact("F2:clock_light_path",method)

func _exchange_heat(changes: Dictionary) -> void:
	_view.thermal_connected = false
	var source: Node3D = _body("I3:hot_cassette")
	var sink: Node3D = _body("I3:cooling_sink")
	var valve: Node3D = _body("I3:cooling_valve")
	if not is_instance_valid(source) or not is_instance_valid(sink) or not is_instance_valid(valve): return
	# Ports are transformed from the real body. Rotating the actual valve by 90
	# degrees breaks this connection even if a UI/controlled flag remains true.
	var port_a: Vector3 = valve.global_transform*Vector3(-4,0,0)
	var port_b: Vector3 = valve.global_transform*Vector3(4,0,0)
	if port_a.distance_to(source.global_position) > .4 or port_b.distance_to(sink.global_position) > .4: return
	var hot: Dictionary = _entities.get("I3:hot_cassette",{})
	var cold: Dictionary = _entities.get("I3:cooling_sink",{})
	if not _number(hot.get("temperature")) or not _number(cold.get("temperature")): return
	var capacity_a := float(hot.get("heat_capacity_j_per_c",1000.0))
	var capacity_b := float(cold.get("heat_capacity_j_per_c",4000.0))
	if not is_finite(capacity_a) or not is_finite(capacity_b) or capacity_a < 100.0 or capacity_b < 100.0 or capacity_a > 100000.0 or capacity_b > 100000.0: return
	_view.thermal_connected = true
	var a: float = float(hot.temperature)
	var b: float = float(cold.temperature)
	if a <= b: return
	var equalizing_j: float = (a-b)/(1.0/capacity_a+1.0/capacity_b)
	var transfer_j: int = int(floor(minf(equalizing_j,(a-b)*1200.0*.1)))
	if transfer_j < 1: return
	var next_a: float = a-float(transfer_j)/capacity_a
	var next_b: float = b+float(transfer_j)/capacity_b
	# Modify the original entity dictionaries as one accepted physics step. Root
	# captures these states and this history in its original Store transaction.
	hot.temperature = next_a
	cold.temperature = next_b
	hot.revision = int(hot.get("revision",0))+1
	cold.revision = int(cold.get("revision",0))+1
	changes["I3:hot_cassette"] = {"temperature":next_a,"revision":hot.revision}
	changes["I3:cooling_sink"] = {"temperature":next_b,"revision":cold.revision}
	_state.thermal.source_loss_j += transfer_j
	_state.thermal.sink_gain_j += transfer_j
	_state.thermal.transfers += 1
	if _state.thermal.first_record.is_empty():
		_state.thermal.first_record = {"source_before_milli_c":int(round(a*1000)),"source_after_milli_c":int(round(next_a*1000)),"sink_before_milli_c":int(round(b*1000)),"sink_after_milli_c":int(round(next_b*1000))}
	if next_a <= 35.0 and next_b > 20.0 and int(_state.thermal.source_loss_j) >= 10000:
		_set_fact("I3:thermal_transfer_verified","pumped_sink" if _state.methods.get("I3:cooling_valve","") == "takeover" else "manual_sink")

func _set_fact(target: String, option: String) -> void:
	if _state.facts.has(target) or not _facts.has(target) or option not in _facts[target].options: return
	_state.facts[target] = option
	_state.serial += 1

func _body(id: String) -> Node3D:
	var body: Variant = bodies.get(id)
	return body if body is Node3D and is_instance_valid(body) else null

func _marker_point(id: String) -> Vector3:
	var body: Node3D = _body(id)
	if is_instance_valid(body): return body.global_position
	var at: Array = _markers[id].position
	return Vector3(float(at[0]),float(at[1]),float(at[2]))

func _ray(from: Vector3, to: Vector3, excluded: Array = []) -> Dictionary:
	if not is_instance_valid(world) or not world.is_inside_tree() or from.distance_squared_to(to) < .000001: return {}
	# Terrain, actual ambient scout layer4, mechanisms/Boss layer8 all
	# participate in nearest-hit occlusion; never ray through an opaque scout.
	var query := PhysicsRayQueryParameters3D.create(from,to,1 | 4 | 8)
	var rids: Array[RID] = []
	for rid in excluded:
		if rid is RID and rid.is_valid(): rids.append(rid)
	query.exclude = rids
	return world.get_world_3d().direct_space_state.intersect_ray(query)

func _line_clear(from: Vector3, to: Vector3, excluded: Array, target_id: String) -> bool:
	var hit: Dictionary = _ray(from,to,excluded)
	return hit.is_empty() or _is_body(hit.get("collider"),_body(target_id),target_id)

static func _rid(body) -> RID:
	return body.get_rid() if body is CollisionObject3D else RID()

static func _player_rid(body) -> RID:
	return _rid(body)

static func _is_body(collider, expected, id: String) -> bool:
	if not collider is Node or not is_instance_valid(collider): return false
	if str(collider.get_meta("entity_id","")) == id: return true
	return is_instance_valid(expected) and (collider == expected or expected.is_ancestor_of(collider))

static func _active(player) -> bool:
	if player is Dictionary: return bool(player.get("active",player.get("enabled",false)))
	return player is Node3D and is_instance_valid(player) and bool(player.enabled)

static func _player_position(player) -> Vector3:
	if player is Dictionary:
		var at: Variant = player.get("position",Vector3.ZERO)
		return at if at is Vector3 else Vector3.ZERO
	return player.global_position

static func _number(value) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _integer(value, low: int, high: int) -> bool:
	return _number(value) and float(value) == floor(float(value)) and float(value) >= float(low) and float(value) <= float(high)

static func _mm(at: Vector3) -> Array:
	return [int(round(at.x*1000)),int(round(at.y*1000)),int(round(at.z*1000))]

static func _yes(code: String) -> Dictionary:
	return {"ok":true,"code":code,"events":[],"entity_changes":{},"facts_changed":false}

static func _no(code: String) -> Dictionary:
	return {"ok":false,"code":code,"events":[],"entity_changes":{},"facts_changed":false}
