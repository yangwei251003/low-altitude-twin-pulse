extends SceneTree
## Pure protocol-13 serialization regression. Explicit packet fixtures only;
## no Session, world construction, profile, ENet, render or packet-budget claim.
const Codec = preload("res://scripts/v3/network/twin_snapshot_codec.gd")
const Whale = preload("res://scripts/v3/gameplay/twin_encounter_state.gd")
const Network = preload("res://scripts/v3/twin_network.gd")
const MAX_PASSAGE_SERIAL := 9007199254740000
const DIGEST := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
var checks := 0
var failures: Array = []

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error("UNDERDECK_SNAPSHOT " + label)

func _run() -> void:
	_test_roundtrip()
	_test_source_rejection()
	_test_wire_rejection()
	_test_aliases_and_copies()
	_test_player_rows()
	_test_entity_presence()
	_test_rejected_publication()
	print("UNDERDECK_SNAPSHOT_RESULT ", JSON.stringify({"checks":checks, "failures":failures,
		"scope":"Codec/Variant/ZSTD and rejected-publication telemetry with explicit fixtures; no Session/ENet/physics or production packet-budget evidence."}))
	quit(0 if failures.is_empty() else 1)

func _test_rejected_publication() -> void:
	var transport := Network.new()
	transport.mode = "host"
	transport.guests = {2:"qa_no_socket"}
	# No tree or multiplayer peer: an invalid packet must return before any RPC.
	var invalid := _packet()
	invalid.entities = {"I1:test":{"future_unregistered_field":1}}
	transport.publish(invalid)
	transport.publish(invalid)
	_check(transport.telemetry.snapshot_encode_rejections == 2, "unregistered authority fields produce explicit bounded rejection telemetry")
	_check(transport.telemetry.snapshots_sent == 0 and transport.telemetry.reliable_fallbacks == 0, "rejected encoding is never counted or sent as an empty valid snapshot")
	transport.free()

func _underdeck(flags: int = 0) -> Dictionary:
	return {"schema_version":1, "layout_sha256":DIGEST, "phase_usec":5739461,
		"front_fraction":0.1234567890123456, "rear_fraction":0.9876543210987654,
		"latched":bool(flags & 1), "front_obstructed":bool(flags & 2),
		"rear_obstructed":bool(flags & 4), "front_pinned":bool(flags & 8), "serial":MAX_PASSAGE_SERIAL}

func _mechanisms(with_underdeck: bool = true) -> Dictionary:
	var result := {"gate":0.3764312987654321, "open":true, "platform":5.231987654321,
		"rotor":-1.0471975511965976, "light":false, "hit":Vector3(-15.3917,5.2,26.35), "clock":12345.987654321}
	if with_underdeck: result.underdeck = _underdeck()
	return result

func _packet(region: String = "I1", boss: Dictionary = {}) -> Dictionary:
	return {"session_id":"9ad8e01c5e42917b53d204e6", "sequence":91731, "region":region,
		"players":{}, "entities":{}, "mechanisms":_mechanisms(region == "I1"),
		"ecology_serial":593, "ecology_epoch":7, "locks":{}, "vote":{}, "boss":boss, "ambient":{},
		"boss_marks":{}, "boss_defeated":false, "paused":true, "gate_saved":false, "story_serial":27}

func _whale_view() -> Dictionary:
	var encounter := Whale.new()
	encounter.start({"players":{"1":{"position":Vector3.ZERO,"max_health":100.0}}})
	var result: Dictionary = encounter.get_state()
	for key in ["players", "boss_id", "reset_reason", "attack_index"]: result.erase(key)
	return result

func _serialized_copy(value: Dictionary) -> Dictionary:
	var raw := var_to_bytes(value)
	var compressed := raw.compress(FileAccess.COMPRESSION_ZSTD)
	var decoded: Variant = bytes_to_var(compressed.decompress(raw.size(), FileAccess.COMPRESSION_ZSTD))
	return decoded if decoded is Dictionary else {}

func _reject_source(packet: Dictionary, label: String) -> void:
	# Use source bytes: Dictionary equality treats a NAN value as unequal to itself.
	var before := var_to_bytes(packet)
	_check(Codec.encode(packet).is_empty() and var_to_bytes(packet) == before, "atomic encode rejection: " + label)

func _reject_wire(wire: Dictionary, label: String) -> void:
	var before := var_to_bytes(wire)
	_check(Codec.decode(wire).is_empty() and var_to_bytes(wire) == before, "atomic decode rejection: " + label)

func _test_roundtrip() -> void:
	for flags in range(16):
		var packet := _packet()
		packet.mechanisms.underdeck = _underdeck(flags)
		var original: Dictionary = packet.duplicate(true)
		var wire: Dictionary = Codec.encode(packet)
		_check(not wire.is_empty() and wire.has("m") and wire.m is Array and wire.m.size() == 8, "I1 fixed mechanism envelope flags " + str(flags))
		if wire.is_empty() or not wire.has("m"): continue
		_check(wire.m[7] is Array and wire.m[7].size() == 7 and wire.m[7][1] is PackedByteArray
			and wire.m[7][1].size() == 32 and wire.m[7][1].hex_encode() == DIGEST and wire.m[7][5] == flags,
			"all four independent bool bits and exact full hash encode " + str(flags))
		_check(Codec.decode(_serialized_copy(wire)) == packet and packet == original,
			"all sixteen passage states roundtrip with fractional poses and maximum serial " + str(flags))
	for pair in [[0.0,1.0], [1.0e-12,1.0-1.0e-12], [0.1234567890123456,0.3333333333333333]]:
		var packet := _packet()
		packet.mechanisms.underdeck.front_fraction = pair[0]
		packet.mechanisms.underdeck.rear_fraction = pair[1]
		var decoded: Dictionary = Codec.decode(_serialized_copy(Codec.encode(packet)))
		_check(decoded == packet and var_to_bytes(decoded.mechanisms.underdeck.front_fraction) == var_to_bytes(pair[0])
			and var_to_bytes(decoded.mechanisms.underdeck.rear_fraction) == var_to_bytes(pair[1]), "fractions retain exact serialized floating value, including endpoints")
	for phase in [0,7999999]:
		var packet := _packet()
		packet.mechanisms.underdeck.phase_usec = phase
		packet.mechanisms.underdeck.serial = 0
		_check(Codec.decode(_serialized_copy(Codec.encode(packet))) == packet, "integer phase endpoints preserve without time quantization " + str(phase))
	var fantasy := _packet("F1")
	var encoded: Dictionary = Codec.encode(fantasy)
	_check(not encoded.is_empty() and encoded.m[7] == [] and Codec.decode(_serialized_copy(encoded)) == fantasy,
		"F1 empty passage slot decodes to absent underdeck key, not an empty or default state")
	var empty := {"boss":{}, "region":"I1", "ambient":{}}
	_check(Codec.decode(Codec.encode(empty)) == empty, "absent mechanisms remain absent for minimal codec fixture")

func _test_source_rejection() -> void:
	var valid := _packet()
	for field in valid.mechanisms.underdeck:
		var missing: Dictionary = valid.duplicate(true)
		missing.mechanisms.underdeck.erase(field)
		_reject_source(missing, "missing passage field " + str(field))
	var extra: Dictionary = valid.duplicate(true)
	extra.mechanisms.underdeck["unknown"] = 1
	_reject_source(extra, "extra passage field")
	for invalid in [null, [], "state", {}]:
		var packet: Dictionary = valid.duplicate(true)
		packet.mechanisms.underdeck = invalid
		_reject_source(packet, "wrong passage container " + str(typeof(invalid)))
	var mutations := {
		"schema_version":[0,2,1.0,true,"1"], "layout_sha256":["",DIGEST.left(63),DIGEST+"0",DIGEST.to_upper(),"g"+DIGEST.substr(1),DIGEST.hex_decode()],
		"phase_usec":[-1,8000000,0.5,1.0,true,"1"], "serial":[-1,MAX_PASSAGE_SERIAL+1,1.5,1.0,true,"1"],
		"front_fraction":[-0.00001,1.00001,NAN,INF,true,"0.5",null],
		"rear_fraction":[-0.00001,1.00001,NAN,-INF,false,"0.5",null]}
	for field in mutations:
		for value in mutations[field]:
			var packet: Dictionary = valid.duplicate(true)
			packet.mechanisms.underdeck[field] = value
			_reject_source(packet, "invalid passage " + field + "=" + str(value))
	for field in ["latched","front_obstructed","rear_obstructed","front_pinned"]:
		for value in [0,1,0.0,"false",null]:
			var packet: Dictionary = valid.duplicate(true)
			packet.mechanisms.underdeck[field] = value
			_reject_source(packet, "non-bool " + field)
	for field in ["gate","open","platform","rotor","light","hit","clock"]:
		var missing: Dictionary = valid.duplicate(true)
		missing.mechanisms.erase(field)
		_reject_source(missing, "missing mechanism field " + field)
	extra = valid.duplicate(true)
	extra.mechanisms["extra"] = 7
	_reject_source(extra, "extra mechanism field")
	for invalid in [null,[],"mechanisms",true]:
		var packet: Dictionary = valid.duplicate(true)
		packet.mechanisms = invalid
		_reject_source(packet, "wrong mechanism container")
	var invalid_mechanisms := {
		"gate":[-0.001,1.001,NAN,INF,true,"0.5"], "open":[0,1,"true"],
		"platform":[1.999,7.501,NAN,INF,true,"2"], "rotor":[NAN,INF,true,"0"],
		"light":[0,1,"false"], "hit":[Vector3(NAN,0,0),Vector3.INF,[0,0,0],null],
		"clock":[-0.001,NAN,INF,true,"0"]}
	for field in invalid_mechanisms:
		for value in invalid_mechanisms[field]:
			var packet: Dictionary = valid.duplicate(true)
			packet.mechanisms[field] = value
			_reject_source(packet, "invalid mechanism " + field + "=" + str(value))

func _test_wire_rejection() -> void:
	var valid: Dictionary = Codec.encode(_packet())
	_check(not valid.is_empty(), "valid encoded fixture exists before wire rejection tests")
	if valid.is_empty(): return
	for count in range(8):
		var wire: Dictionary = valid.duplicate(true)
		wire.m = wire.m.slice(0,count)
		_reject_wire(wire, "truncated mechanisms length " + str(count))
	var extra: Dictionary = valid.duplicate(true)
	extra.m.append(1)
	_reject_wire(extra, "extra mechanism slot")
	for invalid in [null,{},"mechanisms",true,PackedInt32Array([0,1,2,3,4,5,6,7])]:
		var wire: Dictionary = valid.duplicate(true)
		wire.m = invalid
		_reject_wire(wire, "wrong encoded mechanism container")
	# Empty is intentional absence for F1; lengths 1..6 are corrupt partial states.
	for count in range(1,7):
		var wire: Dictionary = valid.duplicate(true)
		wire.m[7] = wire.m[7].slice(0,count)
		_reject_wire(wire, "truncated underdeck length " + str(count))
	extra = valid.duplicate(true)
	extra.m[7].append(1)
	_reject_wire(extra, "extra underdeck slot")
	for value in [null,{},"state",PackedInt32Array([1,2])]:
		var wire: Dictionary = valid.duplicate(true)
		wire.m[7] = value
		_reject_wire(wire, "wrong encoded underdeck container")
	var mutations := {0:[0,2,1.0,true], 1:[null,DIGEST,Array(DIGEST.hex_decode()),PackedByteArray(),DIGEST.hex_decode().slice(0,31),DIGEST.hex_decode()+PackedByteArray([0])],
		2:[-1,8000000,1.0,true], 3:[-0.001,1.001,NAN,INF,true], 4:[-0.001,1.001,NAN,-INF,"0.5"],
		5:[-1,16,255,0.0,1.5,true,"3"], 6:[-1,MAX_PASSAGE_SERIAL+1,0.0,true]}
	for slot in mutations:
		for value in mutations[slot]:
			var wire: Dictionary = valid.duplicate(true)
			wire.m[7][slot] = value
			_reject_wire(wire, "wrong underdeck slot " + str(slot) + "=" + str(value))
	for pair in [[0,NAN],[0,1.01],[1,1],[2,1.0],[2,INF],[3,INF],[4,0],[5,Vector3.INF],[5,[0,0,0]],[6,-1.0],[6,NAN]]:
		var wire: Dictionary = valid.duplicate(true)
		wire.m[pair[0]] = pair[1]
		_reject_wire(wire, "invalid decoded mechanism slot " + str(pair[0]))
	# A different 32-byte digest is structurally valid. Layout equality belongs to
	# the actual Passage.apply_snapshot, not a codec tied to one locally loaded map.
	var different: Dictionary = valid.duplicate(true)
	different.m[7][1][0] = int(different.m[7][1][0]) ^ 1
	var decoded: Dictionary = Codec.decode(different)
	_check(not decoded.is_empty() and decoded.mechanisms.underdeck.layout_sha256 != DIGEST,
		"codec preserves another complete digest; never substitutes local layout hash")

func _test_aliases_and_copies() -> void:
	for boss in [{},_whale_view()]:
		var packet := _packet("I1", boss)
		packet.entities = {"I1:underdeck_latch":{"owner":"1","echo_remaining":1.231987654,"operated":true}}
		var original: Dictionary = packet.duplicate(true)
		var wire: Dictionary = Codec.encode(packet)
		_check(not wire.is_empty() and wire.has("s") and wire.has("m") and not wire.has("session_id") and not wire.has("mechanisms"),
			"idle and whale both use protocol13 reversible aliases")
		if wire.is_empty(): continue
		_check(Codec.decode(_serialized_copy(wire)) == packet, "idle/whale full fixture state survives serializer and ZSTD")
		for field in ["session_id","mechanisms","players","entities"]:
			var mixed: Dictionary = packet.duplicate(true)
			mixed[Codec.PACKET_ALIASES[field]] = packet[field]
			_reject_source(mixed, "idle/whale source alias collision " + field)
			mixed = wire.duplicate(true)
			mixed[field] = packet[field]
			_reject_wire(mixed, "idle/whale mixed long+short wire " + field)
		var unknown: Dictionary = packet.duplicate(true)
		unknown["extra"] = 7
		_reject_source(unknown, "idle/whale unknown source field")
		unknown = wire.duplicate(true)
		unknown["extra"] = 7
		_reject_wire(unknown, "idle/whale unknown wire field")
		_reject_wire(packet, "unencoded long-key packet is not protocol13 wire")
		var untouched_wire: Dictionary = wire.duplicate(true)
		var decoded: Dictionary = Codec.decode(wire)
		decoded.mechanisms.underdeck.front_fraction = 0.0
		decoded.entities["I1:underdeck_latch"].owner = "tampered"
		_check(wire == untouched_wire and packet == original and Codec.decode(wire) == original, "decoded nested data never aliases wire or caller packet")
		wire.m[7][1][0] = 0
		wire.m[7][3] = 0.75
		wire.e["I1:underdeck_latch"][1] = "changed_wire" # owner is the first present value.
		_check(packet == original, "encoded packed hash and nested values never alias source packet")

func _player() -> Dictionary:
	return {"position":Vector3(-25.5317,3.55,-23.5179), "velocity":Vector3(-0.137,0.023,0.091),
		"heading":-1.23456789012345, "health":83.1234567890123, "enabled":true,
		"identity":"pilot_identity_01", "airframe":"hx02", "build":preload("res://scripts/v3/network/twin_build_contract.gd").view(CatalogV2.default_build("hx02"))}

func _test_player_rows() -> void:
	var packet := _packet()
	packet.players = {1:_player(),2147483647:_player()}
	packet.players[2147483647].identity = "队".repeat(96)
	packet.players[2147483647].enabled = false
	packet.players[2147483647].health = 0.0
	var original: Dictionary = packet.duplicate(true)
	var wire: Dictionary = Codec.encode(packet)
	_check(not wire.is_empty() and wire.p[1] is Array and wire.p[1].size() == 8
		and wire.p[1][0] == packet.players[1].position and wire.p[1][6] == "hx02",
		"two canonical integer peer IDs use eight slots without changing order or identity")
	if wire.is_empty(): return
	var restored: Dictionary = Codec.decode(_serialized_copy(wire))
	_check(restored == packet and var_to_bytes(restored.players[1].heading) == var_to_bytes(packet.players[1].heading)
		and var_to_bytes(restored.players[1].health) == var_to_bytes(packet.players[1].health),
		"player moving pose/fractional heading and health, disabled state and 96-character identity roundtrip exactly")
	for field in _player():
		var missing: Dictionary = packet.duplicate(true)
		missing.players[1].erase(field)
		_reject_source(missing, "missing player field " + str(field))
	var extra: Dictionary = packet.duplicate(true)
	extra.players[1]["unknown"] = 7
	_reject_source(extra, "unknown player field cannot silently disappear")
	var invalid_fields := {"position":[null,[0,0,0],Vector3(NAN,0,0)], "velocity":[null,Vector3.INF,"stopped"],
		"heading":[NAN,INF,true,"0"], "health":[-0.001,NAN,INF,false,"1"],
		"enabled":[0,1,0.0,"false",null], "identity":["","x".repeat(97),1,null],
		"airframe":["","x".repeat(65),1,null,"tr01"],"build":[null,{}, {"airframe_id":"hx02","slots":{}}, {"airframe_id":"hx02","slots":{},"stats":{"health":999}}]}
	var slots := {"position":0,"velocity":1,"heading":2,"health":3,"enabled":4,"identity":5,"airframe":6,"build":7}
	for field in invalid_fields:
		for value in invalid_fields[field]:
			var source: Dictionary = packet.duplicate(true)
			source.players[1][field] = value
			_reject_source(source, "bad player " + field + "=" + str(value))
			var encoded: Dictionary = wire.duplicate(true)
			encoded.p[1][slots[field]] = value
			_reject_wire(encoded, "bad player wire " + field + "=" + str(value))
	for count in range(8):
		var truncated: Dictionary = wire.duplicate(true)
		truncated.p[1] = truncated.p[1].slice(0,count)
		_reject_wire(truncated, "truncated player row length " + str(count))
	var extended: Dictionary = wire.duplicate(true)
	extended.p[1].append(0)
	_reject_wire(extended, "extra player slot")
	for invalid in [null,{},"player",PackedFloat64Array([0,0,0,0,0,0,0])]:
		var encoded: Dictionary = wire.duplicate(true)
		encoded.p[1] = invalid
		_reject_wire(encoded, "player wire row requires untyped positional Array")
		var source: Dictionary = packet.duplicate(true)
		source.players[1] = invalid
		_reject_source(source, "player source requires complete Dictionary")
	for peer in [0,-1,2147483648,1.0,true,"1",null]:
		var source := _packet()
		source.players = {7:_player()}
		source.players[peer] = _player()
		_reject_source(source, "bad peer key rejects whole roster including valid predecessor: " + str(peer))
		var encoded: Dictionary = wire.duplicate(true)
		encoded.p = {7:wire.p[1].duplicate(true)}
		encoded.p[peer] = wire.p[1].duplicate(true)
		_reject_wire(encoded, "bad decoded peer key rejects whole roster: " + str(peer))
	for invalid in [null,[],"players"]:
		var source: Dictionary = packet.duplicate(true)
		source.players = invalid
		_reject_source(source, "non-Dictionary player table")
		var encoded: Dictionary = wire.duplicate(true)
		encoded.p = invalid
		_reject_wire(encoded, "non-Dictionary wire player table")
	var retained_wire: Dictionary = wire.duplicate(true)
	restored.players[1].position = Vector3.ZERO
	restored.players[1].identity = "changed_return"
	_check(wire == retained_wire and packet == original and Codec.decode(wire) == original, "decoded player dictionaries do not alias retained wire/source")
	wire.p[1][0] = Vector3.ZERO
	wire.p[1][5] = "changed_wire"
	_check(packet == original, "encoded player arrays do not alias caller dictionaries")

func _full_entity() -> Dictionary:
	# Explicit structural fixture of every current field, not a legal single target
	# combining all abilities. The codec preserves state; Rules owns target support.
	return {"position":Vector3(-30.1731,2.05,-18.5), "revision":1234567, "owner":"1", "energy":74.123456789,
		"temperature":-25.0, "powered":false, "charge":0.0, "light_level":0.75, "angle":-1.0471975511965976,
		"growth":0.35, "environment_light":0.0, "mass":3.0, "pinned":true, "operated":false, "pinned_by":"1",
		"field_remaining":3.123456789, "light_remaining":5.234567891, "burning":false, "decoy_remaining":4.987654321,
		"decoy_position":Vector3(1.937,5.271,-8.317), "echo_remaining":0.0, "echoed_by":"", "return_owner":"neutral",
		"takeover_remaining":7.123456789, "controlled":true, "charge_capacity":100.0, "power_threshold":20.0,
		"light_threshold":0.5, "heat_threshold":55.0}

func _test_entity_presence() -> void:
	var packet := _packet()
	packet.entities = {"I1:underdeck_latch":{}, "I1:relay":{"powered":false,"charge":0.0,"owner":""},
		"player:1":{"energy":0}, "I1:all_fields_fixture":_full_entity()}
	var original: Dictionary = packet.duplicate(true)
	var wire: Dictionary = Codec.encode(packet)
	_check(not wire.is_empty() and wire.e["I1:underdeck_latch"] == [0]
		and wire.e["I1:all_fields_fixture"].size() == 30 and wire.e["I1:all_fields_fixture"][0] == (1 << 29)-1,
		"empty entity and all29 present fields have distinct complete positional masks")
	if wire.is_empty(): return
	var restored: Dictionary = Codec.decode(_serialized_copy(wire))
	_check(restored == packet and restored.entities["I1:underdeck_latch"].is_empty()
		and restored.entities["I1:relay"].has("powered") and restored.entities["I1:relay"].powered == false
		and restored.entities["I1:relay"].has("charge") and restored.entities["I1:relay"].charge == 0.0
		and restored.entities["I1:relay"].has("owner") and restored.entities["I1:relay"].owner == ""
		and not restored.entities["I1:underdeck_latch"].has("powered"), "missing is distinct from explicit false/zero/empty string")
	_check(typeof(restored.entities["player:1"].energy) == TYPE_INT
		and typeof(restored.entities["I1:relay"].charge) == TYPE_FLOAT
		and var_to_bytes(restored.entities["I1:all_fields_fixture"].field_remaining) == var_to_bytes(packet.entities["I1:all_fields_fixture"].field_remaining),
		"entity numeric Variant types and fractional countdowns are preserved without quantization")
	for field in _full_entity():
		var sparse := _packet()
		sparse.entities = {"I1:sparse_fixture":{field:_full_entity()[field]}}
		var encoded: Dictionary = Codec.encode(sparse)
		_check(not encoded.is_empty() and encoded.e["I1:sparse_fixture"].size() == 2 and Codec.decode(_serialized_copy(encoded)) == sparse,
			"single presence bit preserves exactly one field: " + str(field))
	for field in ["unknown","name","tags","health","downed"]:
		var source: Dictionary = packet.duplicate(true)
		source.entities["I1:relay"][field] = 7
		_reject_source(source, "unsupported entity property never silently lost: " + field)
	for invalid in [null,[],"entity",true]:
		var source: Dictionary = packet.duplicate(true)
		source.entities["I1:relay"] = invalid
		_reject_source(source, "non-Dictionary entity source")
	for id in ["",1,true,null]:
		var source: Dictionary = packet.duplicate(true)
		source.entities[id] = {"charge":0}
		_reject_source(source, "bad entity id rejects whole table " + str(id))
		var encoded: Dictionary = wire.duplicate(true)
		encoded.e[id] = [0]
		_reject_wire(encoded, "bad encoded entity id rejects whole table " + str(id))
	for invalid in [null,[],"entities"]:
		var source: Dictionary = packet.duplicate(true)
		source.entities = invalid
		_reject_source(source, "non-Dictionary entities table")
		var encoded: Dictionary = wire.duplicate(true)
		encoded.e = invalid
		_reject_wire(encoded, "non-Dictionary wire entities table")
	for mask in [-1,1 << 29,(1 << 29)|1,9223372036854775807,0.0,1.5,true,"0",null]:
		var encoded: Dictionary = wire.duplicate(true)
		encoded.e["I1:relay"] = [mask]
		_reject_wire(encoded, "invalid/noncanonical entity mask " + str(mask))
	for invalid in [null,{},"row",[],PackedInt32Array([0]),[0,7],[1],[1,Vector3.ZERO,7]]:
		var encoded: Dictionary = wire.duplicate(true)
		encoded.e["I1:relay"] = invalid
		_reject_wire(encoded, "entity row container/presence count mismatch " + str(invalid))
	for count in range(1,30):
		var truncated: Dictionary = wire.duplicate(true)
		truncated.e["I1:all_fields_fixture"] = truncated.e["I1:all_fields_fixture"].slice(0,count)
		_reject_wire(truncated, "full mask missing positional values length " + str(count))
	var extra: Dictionary = wire.duplicate(true)
	extra.e["I1:all_fields_fixture"].append(0)
	_reject_wire(extra, "full mask with extra positional value")
	var retained_wire: Dictionary = wire.duplicate(true)
	restored.entities["I1:all_fields_fixture"].charge = 97.0
	restored.entities["I1:underdeck_latch"]["owner"] = "changed_return"
	_check(wire == retained_wire and packet == original and Codec.decode(wire) == original, "decoded sparse entity maps cannot mutate wire/source or create missing source fields")
	wire.e["I1:all_fields_fixture"][1] = Vector3.ZERO
	wire.e["I1:underdeck_latch"].append(9)
	_check(packet == original, "encoded entity rows and empty rows do not alias source maps")
