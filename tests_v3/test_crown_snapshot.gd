extends SceneTree
## Real presentation/packet serialization, no ENet or combat execution.
const Codec = preload("res://scripts/v3/network/twin_snapshot_codec.gd")
const Crown = preload("res://scripts/v3/gameplay/twin_crown_encounter.gd")
const Adapter = preload("res://scripts/v3/gameplay/twin_crown_session.gd")
const Whale = preload("res://scripts/v3/gameplay/twin_encounter_state.gd")
const Session = preload("res://scripts/v3/twin_session.gd")
const HOSTS = ["F1:crown_host_west", "F1:crown_host_high", "F1:crown_host_east"]

class FixtureArena extends RefCounted:
	func vector(value) -> Vector3: return Vector3(value[0], value[1], value[2])
class FixtureWorld extends RefCounted:
	var crown_arena = FixtureArena.new()
class FixtureSession extends RefCounted:
	var boss_active := true
	var region_id := "F1"
	var world = FixtureWorld.new()

var checks := 0
var failures: Array = []
var profile := ""
var metrics: Dictionary = {}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile = arg.trim_prefix("--qa-profile=")
		if arg.begins_with("--qa-network="):
			push_error("Snapshot test refuses network automation.")
			quit(2)
			return
	if not profile.begins_with("qa_snapshot_") or profile != profile.validate_filename() or DirAccess.dir_exists_absolute("user://profiles_v3/" + profile):
		push_error("Pass a fresh isolated --qa-profile=qa_snapshot_<unique>; never opens an existing or default profile.")
		quit(2)
		return
	_run.call_deferred()

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func _run() -> void:
	_test_whale_compatibility()
	var boss: Dictionary = _crown_presentation()
	_test_crown_roundtrip(boss)
	_test_malformed(boss)
	await _test_production_packet(boss)
	print("V3_CROWN_SNAPSHOT_TESTS " + JSON.stringify({"checks":checks,"failures":failures,"metrics":metrics,
		"scope":"codec roundtrip and local production packet budget; no live Crown/ENet/LAN/graphics/performance or human evidence"}))
	quit(0 if failures.is_empty() else 1)

func _whale_view(encounter) -> Dictionary:
	var view: Dictionary = encounter.get_state()
	for key in ["players", "boss_id", "reset_reason", "attack_index"]: view.erase(key)
	return view

func _test_whale_compatibility() -> void:
	var whale = Whale.new()
	whale.start({"players":{"1":{"position":Vector3.ZERO,"max_health":100.0}}})
	var cases: Array = [_whale_view(whale)]
	whale.advance(3.2)
	cases.append(_whale_view(whale))
	var completed: Dictionary = cases[0].duplicate(true)
	completed.core_health = 0.0
	completed.phase = "defeated"
	completed.completed = true
	completed.telegraph = ""
	cases.append(completed)
	for view in cases:
		var packet: Dictionary = {"ambient":{},"boss":view,"region":"I1","sequence":7}
		var original: Dictionary = packet.duplicate(true)
		var encoded: Dictionary = Codec.encode(packet)
		_check(not encoded.is_empty() and encoded.boss.size() == 12 and encoded.boss[0] == view.attempt, "whale retains original untagged twelve-slot representation")
		_check(Codec.decode(bytes_to_var(var_to_bytes(encoded))) == packet, "whale presentation roundtrips all existing fields losslessly")
		var decoded: Dictionary = Codec.decode(encoded)
		decoded.boss.nodes.port.health = 3.0
		_check(encoded.boss[6].port.health == original.boss.nodes.port.health, "decoded whale nodes do not alias retained wire")
		encoded.boss[6].port.health = 2.0
		_check(packet == original, "encoded whale nodes do not alias source packet")
	var malformed: Dictionary = Codec.encode({"ambient":{},"boss":cases[0]})
	malformed.boss[6] = {"port":{"health":INF,"powered":true},"starboard":{"health":40.0,"powered":true}}
	_check(Codec.decode(malformed).is_empty(), "whale malformed nested numeric value is rejected")
	_check(Codec.decode(Codec.encode({"ambient":{},"boss":{},"region":"F1"})) == {"ambient":{},"boss":{},"region":"F1"}, "inactive boss remains empty array on wire and empty dictionary on return")

func _crown_presentation() -> Dictionary:
	var state = Crown.new()
	_check(state.start({"player:1":{"owner":"1","position":Vector3.ZERO,"health":100.0,"max_health":100.0,"downed":false},
		"player:2":{"owner":"2","position":Vector3(1, 20, -3),"health":100.0,"max_health":100.0,"downed":false}}).ok, "pure Crown fixture starts with two canonical actors")
	var context: Dictionary = {"is_authority":true,"sender_id":"1","line_of_sight":true,"hit_confirmed":true}
	for id in HOSTS:
		var point: Array = state.get_state().anchors[id].target_position_mm
		var position := Vector3(point[0], point[1], point[2]) / 1000.0
		state.set_player_position("player:1", position)
		var actors: Dictionary = {"player:1":{"owner":"1","tags":["player"],"position":position,"health":100.0,"downed":false,"energy":500.0,"revision":0}}
		for _heat in range(2):
			var transaction: Dictionary = state.resolve_ability({"ability":"heat","actor_id":"player:1","target_id":id,"mode":""}, actors, context)
			_check(transaction.ok and state.commit_ability(transaction, actors, true).ok, "actual rules produce each independent burning host warning")
	state.approve_migration(state.get_state().movement.token, false)
	_check(state.hit_core("player:1", 50.0, 1, context).ok, "open fixture accepts first core shot")
	state.advance(0.23)
	_check(state.hit_core("player:1", 50.0, 2, context).ok, "fixture reaches phase two through real half-health transition")
	state.advance(1.3)
	var adapter = Adapter.new()
	adapter.setup(FixtureSession.new())
	adapter.encounter = state
	var result: Dictionary = adapter.presentation()
	_check(result.phase == 2 and result.attacks.size() == 4 and result.attacks[3].shapes.size() == 2 and result.anchors.size() == 3, "production presentation includes three spores and phase-two double volume")
	return result

func _test_crown_roundtrip(boss: Dictionary) -> void:
	var packet: Dictionary = {"ambient":{},"boss":boss,"region":"F1","sequence":818,"paused":true}
	var original: Dictionary = packet.duplicate(true)
	var wire: Dictionary = Codec.encode(packet)
	_check(not wire.is_empty() and wire.boss.size() == 9 and wire.boss[0] == "c" and wire.boss[7].size() == 3, "crown uses discriminated compact presentation rather than whale slots")
	_check(Codec.decode(bytes_to_var(var_to_bytes(wire))) == packet and packet == original, "all Crown host attack and fractional values roundtrip losslessly without input mutation")
	var decoded: Dictionary = Codec.decode(wire)
	decoded.boss.anchors[HOSTS[0]].temperature = -40
	_check(packet == original and Codec.decode(wire) == original, "decoded state cannot mutate source packet or retained wire")
	for mode in Codec.CROWN_MODES:
		var view: Dictionary = boss.duplicate(true)
		view.mode = mode
		view.core_open = mode in ["bound","fallen","unrooted"]
		if mode == "defeated":
			view.core_health = 0.0
			view.attacks = []
		var state_packet: Dictionary = {"ambient":{},"boss":view}
		_check(Codec.decode(Codec.encode(state_packet)) == state_packet, "mode survives pause/reconnect presentation " + mode)

func _test_malformed(boss: Dictionary) -> void:
	var valid: Dictionary = Codec.encode({"ambient":{},"boss":boss})
	for bad in [null, {}, "c", ["unknown"], ["c"], [1, 2, 3]]:
		_check(Codec.decode({"boss":bad,Codec.PACKET_ALIASES["ambient"]:{}}).is_empty(), "malformed top-level boss representation rejected")
	var cases: Array = []
	var altered: Dictionary = valid.duplicate(true)
	altered.boss[1] = Vector3(NAN, 1, 1)
	cases.append(altered)
	altered = valid.duplicate(true)
	altered.boss[5] = 99
	cases.append(altered)
	altered = valid.duplicate(true)
	altered.boss[7][0][2] = 8
	cases.append(altered)
	altered = valid.duplicate(true)
	altered.boss[7].pop_back()
	cases.append(altered)
	altered = valid.duplicate(true)
	altered.boss[8][0][2] = 1
	cases.append(altered)
	altered = valid.duplicate(true)
	altered.boss[8][0][3] = INF
	cases.append(altered)
	altered = valid.duplicate(true)
	altered.boss[8][1][0] = altered.boss[8][0][0]
	cases.append(altered)
	altered = valid.duplicate(true)
	altered.boss[8][0][4][0][0] = 9
	cases.append(altered)
	altered = valid.duplicate(true)
	altered.boss[8][0][4][0][4] = 0
	cases.append(altered)
	altered = valid.duplicate(true)
	altered.boss[8][0][4][0][5] = 13000
	cases.append(altered)
	altered = valid.duplicate(true)
	altered.boss[6] = 1.5
	cases.append(altered)
	altered = valid.duplicate(true)
	altered.boss[8].append(altered.boss[8][0].duplicate(true))
	cases.append(altered)
	altered = valid.duplicate(true)
	altered.boss[8][0][4][0] = [1, 100.5, 0, 0, 5000, 0, 13000]
	cases.append(altered)
	for packet in cases: _check(Codec.decode(packet).is_empty(), "invalid Crown typed field or geometry rejected atomically")
	for field in ["rng","players","history"]:
		var extra: Dictionary = boss.duplicate(true)
		extra[field] = {}
		_check(Codec.encode({"ambient":{},"boss":extra}).is_empty(), "host-only field cannot silently enter presentation wire: " + field)
	var wrong_host: Dictionary = boss.duplicate(true)
	wrong_host.anchors["unknown_host"] = wrong_host.anchors[HOSTS[0]]
	wrong_host.anchors.erase(HOSTS[0])
	_check(Codec.encode({"ambient":{},"boss":wrong_host}).is_empty(), "unknown host cannot be reinterpreted by positional mapping")
	_check(Codec.encode({"ambient":{},"boss":[]}).is_empty(), "encode refuses already encoded or malformed input")
	var alias_conflict: Dictionary = {"ambient":{},"boss":boss,"players":{},"p":{}}
	_check(Codec.encode(alias_conflict).is_empty(), "envelope alias collision cannot silently drop caller data")
	alias_conflict = valid.duplicate(true)
	alias_conflict.players = {}
	alias_conflict.p = {}
	_check(Codec.decode(alias_conflict).is_empty(), "mixed long and short Crown envelope keys are rejected")
	_check(Codec.encode({"ambient":{},"boss":boss,"unknown_field":7}).is_empty(), "unknown Crown envelope field requires explicit protocol extension")
	var unknown_wire: Dictionary = valid.duplicate(true)
	unknown_wire["unknown_field"] = 7
	_check(Codec.decode(unknown_wire).is_empty(), "unknown Crown wire field is not silently forwarded")

func _test_production_packet(boss: Dictionary) -> void:
	var session = Session.new()
	root.add_child(session)
	session.set_process(false)
	session.set_physics_process(false)
	session.inputs.set_process(false)
	session.inputs.set_physics_process(false)
	_check(session.profile_ready and session.start_flight("solo"), "production session opens fresh isolated profile without ENet")
	if not session.active:
		session.queue_free()
		await process_frame
		return
	session._load_region("F1")
	session.simulation_paused = true
	session._spawn_player(18700321, "qa_guest_49fa7560771d1c63bd77c64ba865ec80", Vector3(14.125, 20.375, -22.625), "hx02")
	session._apply_pause_state()
	# Deterministic nonzero poses prevent accidental all-zero compression optimism.
	var local = session.players[1]
	local.global_position = Vector3(-9.125, 17.875, -29.625)
	local.linear_velocity = Vector3(2.25, 0.125, -1.5)
	local.heading = 0.7123
	local.health = 83.375
	var guest = session.players[18700321]
	guest.linear_velocity = Vector3(-1.75, 0.375, 2.125)
	guest.heading = -1.231
	guest.health = 71.625
	var packet: Dictionary = session._snapshot()
	packet.boss = boss
	packet.session_id = "8aab8c7084714dfd85afce9ed1855238"
	packet.sequence = 67319
	packet.locks = {1:HOSTS[0],18700321:HOSTS[1]}
	_check(packet.region == "F1" and packet.players.size() == 2 and not packet.entities.is_empty(), "budget uses actual F1 production entity and mechanism snapshot with two bodies")
	var wire: Dictionary = Codec.encode(packet)
	var raw: PackedByteArray = var_to_bytes(wire)
	var packed: PackedByteArray = raw.compress(FileAccess.COMPRESSION_ZSTD)
	var deflate: PackedByteArray = raw.compress(FileAccess.COMPRESSION_DEFLATE)
	metrics = {"raw_bytes":raw.size(),"zstd_bytes":packed.size(),"deflate_comparison_bytes":deflate.size(),
		"entities":packet.entities.size(),"players":packet.players.size(),"attacks":boss.attacks.size(),"budget_bytes":1150}
	_check(not wire.is_empty() and packed.size() <= 1150, "two-player F1 with three spores and phase-two double shape fits production 1150-byte budget")
	_check(Codec.decode(bytes_to_var(packed.decompress(raw.size(), FileAccess.COMPRESSION_ZSTD))) == packet, "production serializer and ZSTD roundtrip whole packet without loss")
	var varied_max := packed.size()
	var varied_min := packed.size()
	var varied_roundtrip := true
	for index in range(12):
		var varied: Dictionary = packet.duplicate(true)
		var step := float(index + 1)
		varied.sequence += index
		varied.boss.position += Vector3(step * 0.13731, step * 0.07131, step * -0.17713)
		for id in varied.players:
			varied.players[id].position += Vector3(step * 0.19371, step * -0.02319, step * 0.17391)
			varied.players[id].velocity += Vector3(step * 0.07931, step * -0.01379, step * 0.07193)
			varied.players[id].heading += step * 0.02371
		for attack in varied.boss.attacks: attack.remaining = maxf(0.1, float(attack.remaining) - step * 0.1)
		var variation_raw: PackedByteArray = var_to_bytes(Codec.encode(varied))
		var variation_packed: PackedByteArray = variation_raw.compress(FileAccess.COMPRESSION_ZSTD)
		varied_max = maxi(varied_max, variation_packed.size())
		varied_min = mini(varied_min, variation_packed.size())
		varied_roundtrip = varied_roundtrip and Codec.decode(bytes_to_var(variation_packed.decompress(variation_raw.size(), FileAccess.COMPRESSION_ZSTD))) == varied
	metrics["varied_zstd_min_bytes"] = varied_min
	metrics["varied_zstd_max_bytes"] = varied_max
	metrics["varied_packet_samples"] = 12
	_check(varied_roundtrip, "twelve moving-pose and countdown packet variants roundtrip losslessly")
	_check(varied_max <= 1150, "changing floating poses velocities and attack timers stay within 1150-byte budget")
	_check(not session.boss_active and session.network.mode == "solo", "packet budget test does not start Crown combat or host a network game")
	session.queue_free()
	await process_frame
