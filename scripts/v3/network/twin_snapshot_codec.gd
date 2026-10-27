class_name TwinSnapshotCodec
extends RefCounted
## Protocol25 adds an explicit single F2 ambient view; exact hardware remains.
const BuildContract = preload("res://scripts/v3/network/twin_build_contract.gd")
const FacilityContract = preload("res://scripts/v3/network/twin_facility_contract.gd")
const ThermalPresentation = preload("res://scripts/v3/network/twin_thermal_presentation.gd")
const PatrolView = preload("res://scripts/v3/gameplay/twin_f2_patrol_view.gd")
const BOSS_FIELDS = ["attempt", "core_health", "core_max_health", "phase", "overdrive", "exposed_remaining", "nodes", "attack_state", "attack_remaining", "telegraph", "nodes_open", "completed"]
const CROWN_FIELDS = ["type", "position", "core_health", "core_open", "phase", "mode", "attempt", "anchors", "attacks"]
const CROWN_HOSTS = ["F1:crown_host_west", "F1:crown_host_high", "F1:crown_host_east"]
const CROWN_MODES = ["attached", "migration_warning", "awaiting_route", "moving", "bound", "fallen", "unrooted", "defeated"]
const ATTACK_KINDS = ["root_pollen", "burning_spores"]
const SHAPE_KINDS = ["annular_prism", "cylinder"]
const HOST_FIELDS = ["temperature", "lit", "burning", "growth", "recovering"]
const ATTACK_FIELDS = ["token", "kind", "shapes", "active", "remaining"]
const SHAPE_FIELDS = ["kind", "centre_xz_mm", "inner_mm", "outer_mm", "y_min_mm", "y_max_mm"]
# Every region uses the same reversible envelope. Protocol handshake rejects older peers.
const PACKET_ALIASES = {"session_id":"s", "sequence":"q", "region":"r", "players":"p", "entities":"e",
	"mechanisms":"m", "ecology_serial":"es", "ecology_epoch":"ee", "locks":"l", "vote":"v",
	"boss_marks":"bm", "boss_defeated":"bd", "paused":"u", "gate_saved":"g", "story_serial":"ss", "facility_refs":"fr", "campaign_epoch":"ce", "canal_epoch":"cae", "thermal_cargo":"tc", "ambient":"am"}
const MECHANISM_FIELDS = ["gate", "open", "platform", "rotor", "light", "hit", "clock"]
const UNDERDECK_FIELDS = ["schema_version", "layout_sha256", "phase_usec", "front_fraction", "rear_fraction", "latched", "front_obstructed", "rear_obstructed", "front_pinned", "serial"]
const PLAYER_FIELDS = ["position", "velocity", "heading", "health", "enabled", "identity", "airframe", "build"]
# Presence bits retain the difference between an absent field and false/0/"".
# Adding a new authority property requires an explicit wire schema extension.
const ENTITY_FIELDS = ["position", "revision", "owner", "energy", "temperature", "powered", "charge",
	"light_level", "angle", "growth", "environment_light", "mass", "pinned", "operated", "pinned_by",
	"field_remaining", "light_remaining", "burning", "decoy_remaining", "decoy_position", "echo_remaining",
	"echoed_by", "return_owner", "takeover_remaining", "controlled", "charge_capacity", "power_threshold",
	"light_threshold", "heat_threshold"]

static func encode(packet: Dictionary) -> Dictionary:
	if not PatrolView.valid(packet.get("ambient")): return {}
	if not packet.ambient.is_empty() and packet.ambient.region!=packet.get("region"): return {}
	if not packet.get("boss", {}) is Dictionary: return {}
	if not ThermalPresentation.valid(packet.get("thermal_cargo",{})): return {}
	if packet.has("facility_refs") and not FacilityContract.valid_refs(packet.facility_refs): return {}
	var wire: Dictionary = packet.duplicate(true)
	var boss: Dictionary = packet.get("boss", {})
	var values: Array = []
	for field in packet:
		if field != "boss" and not PACKET_ALIASES.has(field): return {}
	for field in ["players", "entities"]:
		if not packet.has(field): continue
		if not wire[field] is Dictionary: return {}
		var table: Dictionary = _encode_players(wire[field]) if field == "players" else _encode_entities(wire[field])
		if table.size() != wire[field].size(): return {}
		wire[field] = table
	if packet.has("mechanisms"):
		var mechanisms := _encode_mechanisms(packet.mechanisms)
		if mechanisms.is_empty(): return {}
		wire.mechanisms = mechanisms
	if not boss.is_empty():
		if boss.get("type") == "parasitic_crown":
			if not _valid_crown(boss): return {}
			values = _encode_crown(boss)
		else:
			if not _valid_whale(boss): return {}
			for key in BOSS_FIELDS: values.append(boss[key])
	for field in PACKET_ALIASES:
		if wire.has(field):
			wire[PACKET_ALIASES[field]] = wire[field]
			wire.erase(field)
	wire.boss = values.duplicate(true)
	return wire

static func decode(wire: Dictionary) -> Dictionary:
	if not wire.get("boss") is Array: return {}
	for field in wire:
		if field != "boss" and not field in PACKET_ALIASES.values(): return {}
	var packet: Dictionary = wire.duplicate(true)
	for field in PACKET_ALIASES:
		var alias: String = PACKET_ALIASES[field]
		if packet.has(alias):
			packet[field] = packet[alias]
			packet.erase(alias)
	if packet.has("facility_refs") and not FacilityContract.valid_refs(packet.facility_refs): return {}
	if not PatrolView.valid(packet.get("ambient")): return {}
	if not packet.ambient.is_empty() and packet.ambient.region!=packet.get("region"): return {}
	if not ThermalPresentation.valid(packet.get("thermal_cargo",{})): return {}
	for field in ["players", "entities"]:
		if not packet.has(field): continue
		if not packet[field] is Dictionary: return {}
		var table: Dictionary = _decode_players(packet[field]) if field == "players" else _decode_entities(packet[field])
		if table.size() != packet[field].size(): return {}
		packet[field] = table
	if packet.has("mechanisms"):
		var mechanisms := _decode_mechanisms(packet.mechanisms)
		if mechanisms.is_empty(): return {}
		packet.mechanisms = mechanisms
	var boss: Dictionary = {}
	if not wire.boss.is_empty():
		if wire.boss[0] is String:
			if wire.boss[0] != "c": return {}
			boss = _decode_crown(wire.boss)
			if boss.is_empty(): return {}
		else:
			if wire.boss.size() != BOSS_FIELDS.size(): return {}
			for index in range(wire.boss.size()): boss[BOSS_FIELDS[index]] = wire.boss[index]
			if not _valid_whale(boss): return {}
	packet.boss = boss.duplicate(true)
	return packet

static func _encode_players(players: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for peer in players:
		if not _integer(peer, 1, 2147483647) or not _valid_player(players[peer]): return {}
		var values: Array = []
		for field in PLAYER_FIELDS: values.append(players[peer][field])
		result[peer] = values
	return result

static func _decode_players(players: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for peer in players:
		var values = players[peer]
		if not _integer(peer, 1, 2147483647) or not values is Array or values.size() != PLAYER_FIELDS.size(): return {}
		var state: Dictionary = {}
		for index in range(PLAYER_FIELDS.size()): state[PLAYER_FIELDS[index]] = values[index]
		if not _valid_player(state): return {}
		result[peer] = state
	return result

static func _valid_player(state) -> bool:
	if not state is Dictionary or not _exact_keys(state, PLAYER_FIELDS): return false
	for field in ["position", "velocity"]:
		if not state[field] is Vector3 or not state[field].is_finite(): return false
	if not _number(state.heading, -1.0e100, 1.0e100) or not _number(state.health, 0.0, 1.0e100) or not state.enabled is bool: return false
	if not (state.identity is String and not state.identity.is_empty() and state.identity.length() <= 96 and state.airframe is String): return false
	return BuildContract.valid(state.build) and state.airframe == state.build.airframe_id

static func _encode_entities(entities: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for id in entities:
		if not id is String or id.is_empty() or not entities[id] is Dictionary: return {}
		var state: Dictionary = entities[id]
		for field in state:
			if not field in ENTITY_FIELDS: return {}
		var mask: int = 0
		var values: Array = [0]
		for index in range(ENTITY_FIELDS.size()):
			var field: String = ENTITY_FIELDS[index]
			if state.has(field):
				mask |= 1 << index
				values.append(state[field])
		values[0] = mask
		result[id] = values
	return result

static func _decode_entities(entities: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for id in entities:
		var values = entities[id]
		if not id is String or id.is_empty() or not values is Array or values.is_empty() or not _integer(values[0], 0, (1 << ENTITY_FIELDS.size()) - 1): return {}
		var mask: int = values[0]
		var cursor: int = 1
		var state: Dictionary = {}
		for index in range(ENTITY_FIELDS.size()):
			if mask & (1 << index):
				if cursor >= values.size(): return {}
				state[ENTITY_FIELDS[index]] = values[cursor]
				cursor += 1
		if cursor != values.size(): return {}
		result[id] = state
	return result

static func _encode_mechanisms(state) -> Array:
	if not state is Dictionary: return []
	var fields: Array = MECHANISM_FIELDS.duplicate()
	if state.has("underdeck"): fields.append("underdeck")
	if not _exact_keys(state, fields): return []
	if not _valid_mechanisms(state): return []
	var values: Array = []
	for field in MECHANISM_FIELDS: values.append(state[field])
	var underdeck: Array = []
	if state.has("underdeck"):
		var u = state.underdeck
		if not _valid_underdeck(u): return []
		var flags: int = int(u.latched) | (int(u.front_obstructed) << 1) | (int(u.rear_obstructed) << 2) | (int(u.front_pinned) << 3)
		underdeck = [u.schema_version, u.layout_sha256.hex_decode(), u.phase_usec, u.front_fraction, u.rear_fraction, flags, u.serial]
	values.append(underdeck)
	return values

static func _decode_mechanisms(values) -> Dictionary:
	if not values is Array or values.size() != 8 or not values[7] is Array: return {}
	var state: Dictionary = {}
	for index in range(MECHANISM_FIELDS.size()): state[MECHANISM_FIELDS[index]] = values[index]
	if not _valid_mechanisms(state): return {}
	var u: Array = values[7]
	if not u.is_empty():
		if u.size() != 7 or not u[1] is PackedByteArray or u[1].size() != 32 or not _index(u[5], 16): return {}
		var flags: int = u[5]
		state.underdeck = {"schema_version":u[0], "layout_sha256":u[1].hex_encode(), "phase_usec":u[2],
			"front_fraction":u[3], "rear_fraction":u[4], "latched":bool(flags & 1),
			"front_obstructed":bool(flags & 2), "rear_obstructed":bool(flags & 4), "front_pinned":bool(flags & 8), "serial":u[6]}
		if not _valid_underdeck(state.underdeck): return {}
	return state

static func _valid_mechanisms(state: Dictionary) -> bool:
	if not _number(state.gate, 0.0, 1.0) or not state.open is bool or not state.light is bool: return false
	if not _number(state.platform, 2.0, 7.5) or not _number(state.rotor, -1.0e100, 1.0e100): return false
	return state.hit is Vector3 and state.hit.is_finite() and _number(state.clock, 0.0, 1.0e100)

static func _valid_underdeck(u) -> bool:
	if not u is Dictionary or not _exact_keys(u, UNDERDECK_FIELDS): return false
	if not _integer(u.schema_version, 1, 1) or not u.layout_sha256 is String or u.layout_sha256.length() != 64: return false
	for character in u.layout_sha256:
		if not character in "0123456789abcdef": return false
	if not _integer(u.phase_usec, 0, 7999999) or not _integer(u.serial, 0, 9007199254740000): return false
	for field in ["front_fraction", "rear_fraction"]:
		if not _number(u[field], 0.0, 1.0): return false
	for field in ["latched", "front_obstructed", "rear_obstructed", "front_pinned"]:
		if not u[field] is bool: return false
	return true

static func _encode_crown(boss: Dictionary) -> Array:
	var hosts: Array = []
	for id in CROWN_HOSTS:
		var host: Dictionary = boss.anchors[id]
		var flags: int = int(host.lit) | (int(host.burning) << 1) | (int(host.recovering) << 2)
		hosts.append([host.temperature, host.growth, flags])
	var attacks: Array = []
	for attack in boss.attacks:
		var shapes: Array = []
		for shape in attack.shapes:
			shapes.append(PackedInt32Array([SHAPE_KINDS.find(shape.kind), shape.centre_xz_mm[0], shape.centre_xz_mm[1],
				shape.inner_mm, shape.outer_mm, shape.y_min_mm, shape.y_max_mm]))
		attacks.append([attack.token, ATTACK_KINDS.find(attack.kind), attack.active, attack.remaining, shapes])
	return ["c", boss.position, boss.core_health, boss.core_open, boss.phase, CROWN_MODES.find(boss.mode), boss.attempt, hosts, attacks]

static func _decode_crown(values: Array) -> Dictionary:
	if values.size() != 9 or not _index(values[5], CROWN_MODES.size()) or not values[7] is Array or values[7].size() != 3 or not values[8] is Array or values[8].size() > 4: return {}
	var hosts: Dictionary = {}
	for index in range(3):
		var host = values[7][index]
		if not host is Array or host.size() != 3 or not _index(host[2], 8): return {}
		var flags: int = int(host[2])
		hosts[CROWN_HOSTS[index]] = {"temperature":host[0], "growth":host[1], "lit":bool(flags & 1), "burning":bool(flags & 2), "recovering":bool(flags & 4)}
	var attacks: Array = []
	for attack in values[8]:
		if not attack is Array or attack.size() != 5 or not _index(attack[1], ATTACK_KINDS.size()) or not attack[4] is Array or attack[4].is_empty() or attack[4].size() > 2: return {}
		var shapes: Array = []
		for shape in attack[4]:
			if not shape is PackedInt32Array or shape.size() != 7 or not _index(shape[0], SHAPE_KINDS.size()): return {}
			shapes.append({"kind":SHAPE_KINDS[int(shape[0])], "centre_xz_mm":[shape[1], shape[2]],
				"inner_mm":shape[3], "outer_mm":shape[4], "y_min_mm":shape[5], "y_max_mm":shape[6]})
		attacks.append({"token":attack[0], "kind":ATTACK_KINDS[int(attack[1])], "active":attack[2], "remaining":attack[3], "shapes":shapes})
	var boss: Dictionary = {"type":"parasitic_crown", "position":values[1], "core_health":values[2], "core_open":values[3],
		"phase":values[4], "mode":CROWN_MODES[int(values[5])], "attempt":values[6], "anchors":hosts, "attacks":attacks}
	return boss if _valid_crown(boss) else {}

static func _valid_crown(boss: Dictionary) -> bool:
	if not _exact_keys(boss, CROWN_FIELDS) or boss.type != "parasitic_crown" or not boss.position is Vector3 or not boss.position.is_finite(): return false
	if absf(boss.position.x) > 1000.0 or absf(boss.position.y) > 1000.0 or absf(boss.position.z) > 1000.0: return false
	if not _number(boss.core_health, 0.0, 160.0) or not boss.core_open is bool or not _integer(boss.phase, 1, 2) or not boss.mode in CROWN_MODES or not _integer(boss.attempt, 1, 9007199254740991): return false
	if (boss.mode == "defeated") != (boss.core_health == 0) or (boss.mode == "defeated" and boss.core_open): return false
	if not boss.anchors is Dictionary or not _exact_keys(boss.anchors, CROWN_HOSTS): return false
	for host in boss.anchors.values():
		if not host is Dictionary or not _exact_keys(host, HOST_FIELDS) or not _integer(host.temperature, -40, 200) or not _number(host.growth, 0.0, 1.0): return false
		if not host.lit is bool or not host.burning is bool or not host.recovering is bool: return false
	if not boss.attacks is Array or boss.attacks.size() > 4: return false
	var tokens: Dictionary = {}
	var normal_count := 0
	var burn_count := 0
	for attack in boss.attacks:
		if not attack is Dictionary or not _exact_keys(attack, ATTACK_FIELDS): return false
		if not attack.token is String or attack.token.is_empty() or attack.token.length() > 128 or tokens.has(attack.token): return false
		if not attack.kind in ATTACK_KINDS or not attack.active is bool or not _number(attack.remaining, 0.0, 20.0): return false
		if not attack.shapes is Array or attack.shapes.is_empty() or attack.shapes.size() > 2: return false
		if attack.kind == "root_pollen": normal_count += 1
		else:
			burn_count += 1
			if attack.shapes.size() != 1: return false
		for shape in attack.shapes:
			if not _valid_shape(shape): return false
		tokens[attack.token] = true
	return normal_count <= 1 and burn_count <= 3

static func _valid_shape(shape) -> bool:
	if not shape is Dictionary or not _exact_keys(shape, SHAPE_FIELDS) or not shape.kind in SHAPE_KINDS: return false
	if not shape.centre_xz_mm is Array or shape.centre_xz_mm.size() != 2: return false
	for value in shape.centre_xz_mm:
		if not _integer(value, -1000000, 1000000): return false
	for field in ["inner_mm", "outer_mm", "y_min_mm", "y_max_mm"]:
		if not _integer(shape[field], 0, 1000000): return false
	return shape.inner_mm < shape.outer_mm and shape.y_min_mm < shape.y_max_mm

static func _valid_whale(boss: Dictionary) -> bool:
	if not _exact_keys(boss, BOSS_FIELDS) or not _integer(boss.attempt, 1, 9007199254740991): return false
	for field in ["core_health", "core_max_health", "exposed_remaining", "attack_remaining"]:
		if not _number(boss[field], 0.0, 1000000.0): return false
	if not boss.phase in ["shielded", "exposed", "overdrive", "defeated"] or not boss.attack_state in ["windup", "active", "recovery"] or not boss.telegraph in ["low_sweep", "high_lance", "tractor", ""]: return false
	for field in ["overdrive", "nodes_open", "completed"]:
		if not boss[field] is bool: return false
	if not boss.nodes is Dictionary or not _exact_keys(boss.nodes, ["port", "starboard"]): return false
	for node in boss.nodes.values():
		if not node is Dictionary or not _exact_keys(node, ["health", "powered"]) or not _number(node.health, 0.0, 1000000.0) or not node.powered is bool: return false
	return true

static func _exact_keys(value: Dictionary, fields: Array) -> bool:
	if value.size() != fields.size(): return false
	for field in fields:
		if not value.has(field): return false
	return true

static func _number(value, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum

static func _integer(value, minimum: int, maximum: int) -> bool:
	return value is int and value >= minimum and value <= maximum

static func _index(value, count: int) -> bool:
	return _integer(value, 0, count - 1)
