class_name TwinFacilityContract
extends RefCounted
## Stable wire identities. No script paths, factories or simulation state may
## arrive from a peer. Reliable states remain separate from the motion packet.
const VERSION := 1
const MAX_COUNTER := 9007199254740000
const DEFINITIONS := [
	{"slot":1,"id":"clinic","region":"I2","envelope":1},
	{"slot":2,"id":"distribution","region":"I2","envelope":1},
	{"slot":3,"id":"trial","region":"I2","envelope":1},
	{"slot":4,"id":"shared_access","region":"I2","envelope":1}
]

static func fingerprint() -> String:
	return (str(VERSION) + ":" + JSON.stringify(DEFINITIONS)).sha256_text()

static func compatible(version: Variant, digest: Variant) -> bool:
	return version is int and version == VERSION and digest is String and digest == fingerprint()

static func valid_refs(raw: Variant) -> bool:
	if not raw is Array or raw.size() != DEFINITIONS.size(): return false
	var seen: Dictionary = {}
	for row in raw:
		if not row is Array or row.size() != 3: return false
		if not _integer(row[0], 1, DEFINITIONS.size()) or seen.has(int(row[0])): return false
		if not _integer(row[1], 1, MAX_COUNTER) or not _integer(row[2], 1, MAX_COUNTER): return false
		seen[int(row[0])] = true
	return true

static func ref_for_slot(raw: Variant, slot: int) -> Dictionary:
	if not valid_refs(raw): return {}
	for row in raw:
		if int(row[0]) == slot: return {"epoch":int(row[1]), "serial":int(row[2])}
	return {}

static func _integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= low and float(value) <= high and floor(float(value)) == float(value)
