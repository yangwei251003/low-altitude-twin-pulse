class_name TwinBuildContract
extends RefCounted
## Hardware-only LAN projection. The owner verifies personal ownership before
## departure; the host verifies this exact wire and its own Catalog compatibility.
## Neither remote derived stats nor local build metadata can enter the resolver.
## Catalog resources are immutable for one running process. fingerprint() hashes
## the actual packaged content, once, rather than trusting an embedded source tag.
const Catalog = preload("res://scripts/v2/catalog.gd")
const WIRE_KEYS := ["airframe_id", "slots"]
const SLOT_KEYS := ["weapon", "tool", "drive", "battery", "utility"]
const MAX_ID_BYTES := 64
const CACHE_LIMIT := 128
static var _catalog_sha := ""
static var _stock_ids: Dictionary = {}
# Only successful original Catalog results are cached. All public wire inputs
# are checked again before lookup, including when their six IDs were seen before.
static var _resolved_cache: Dictionary = {}
static var _cache_order: Array[String] = []


## Returns a fresh exact wire, or {}. This is a projection of a trusted native
## build, so schema/build_id/cosmetic/derived metadata is deliberately omitted.
## Native legacy "stock" aliases become explicit current Catalog IDs on wire.
static func view(build: Variant) -> Dictionary:
	if not build is Dictionary or not build.get("airframe_id") is String or not build.get("slots") is Dictionary:
		return {}
	if not _exact_keys(build["slots"], SLOT_KEYS) or not _initialize(): return {}
	var slots: Dictionary = {}
	for slot: String in SLOT_KEYS:
		var id: Variant = build["slots"][slot]
		if id is String and id == "stock" and slot in ["drive", "battery"]:
			id = _stock_ids[slot]
		slots[slot] = id
	var wire: Dictionary = {"airframe_id":build["airframe_id"], "slots":slots}
	var checked: Dictionary = _lookup(wire)
	return wire if checked.get("ok", false) else {}


## Always checks the exact wire shape. Successful build/resolved dictionaries
## are independent deep copies; mutating any returned nested value cannot alter
## a later validation. No ownership claim is made about a visitor's local disk.
## Native builds use explicit stock IDs, matching the normal Hangar's output.
## Flight visuals must treat raw stock and those stock IDs consistently. Never
## normalize/reconfigure an already-restored thermal-cargo role's original build.
## Read-only hot-path predicate; the exact input shape is still checked each call.
static func valid(wire: Variant) -> bool:
	return _lookup(wire).get("ok",false)


static func validate(wire: Variant) -> Dictionary:
	var checked: Dictionary = _lookup(wire)
	if not checked.get("ok", false): return checked
	var resolved: Dictionary = checked["resolved"].duplicate(true)
	return {"ok":true, "code":"BUILD_WIRE_OK",
		"build":resolved["build"].duplicate(true), "resolved":resolved}


## Compares only legal hardware; ignores native metadata and stock spelling.
## The caller still preserves an original saved role's complete native build.
static func matches(build: Variant, wire: Variant) -> bool:
	var checked: Dictionary = _lookup(wire)
	if not checked.get("ok", false): return false
	var projected: Dictionary = view(build)
	return not projected.is_empty() and projected == wire


static func fingerprint() -> String:
	return _catalog_sha if _initialize() else ""


static func _initialize() -> bool:
	if not _catalog_sha.is_empty(): return true
	var digest: String = FileAccess.get_sha256(Catalog.CONTENT_PATH)
	if digest.length() != 64: return false
	var content: Dictionary = Catalog.content()
	var catalog: Variant = content.get("catalog")
	if not catalog is Dictionary or not catalog.get("stock_slot_ids") is Dictionary:
		return false
	var stock: Dictionary = catalog["stock_slot_ids"]
	for slot: String in ["drive", "battery"]:
		if not _id_valid(stock.get(slot)) or stock[slot] == "stock": return false
	_stock_ids = {"drive":str(stock["drive"]), "battery":str(stock["battery"])}
	_catalog_sha = digest
	return true


static func _exact_keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size(): return false
	for key: Variant in value:
		# StringName is not the JSON wire contract, even if its text is equal.
		if not key is String or key not in expected: return false
	return true


static func _id_valid(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > MAX_ID_BYTES: return false
	# Current Catalog IDs are bounded ASCII. Reject control/Unicode/alias strings
	# before hashing; actual existence and slot/mount legality remain Catalog's.
	for index: int in range(value.length()):
		var point: int = value.unicode_at(index)
		if not ((point >= 97 and point <= 122) or (point >= 48 and point <= 57) or point == 95 or point == 45):
			return false
	return value != "stock"


static func _shape_code(wire: Variant) -> String:
	if not wire is Dictionary or not _exact_keys(wire, WIRE_KEYS): return "BUILD_WIRE_FIELDS"
	if not _id_valid(wire.get("airframe_id")): return "BUILD_WIRE_FRAME_ID"
	var slots: Variant = wire.get("slots")
	if not slots is Dictionary or not _exact_keys(slots, SLOT_KEYS): return "BUILD_WIRE_SLOTS"
	for slot: String in SLOT_KEYS:
		if not _id_valid(slots[slot]): return "BUILD_WIRE_MODULE_ID"
	return ""


# Private lookup may reference its private cache. Only validate() exposes resolved
# data, and it deep-copies before returning; view()/matches() expose no cache rows.
static func _lookup(wire: Variant) -> Dictionary:
	var code: String = _shape_code(wire)
	if not code.is_empty(): return {"ok":false, "code":code, "build":{}, "resolved":{}}
	if not _initialize(): return {"ok":false, "code":"BUILD_WIRE_CATALOG_UNAVAILABLE", "build":{}, "resolved":{}}
	var identity: Array = [_catalog_sha, wire["airframe_id"]]
	for slot: String in SLOT_KEYS: identity.append(wire["slots"][slot])
	var key: String = JSON.stringify(identity).sha256_text()
	if not _resolved_cache.has(key):
		var native_slots: Dictionary = {}
		for slot: String in SLOT_KEYS: native_slots[slot] = str(wire["slots"][slot])
		var native: Dictionary = {"schema_version":2, "build_id":"network_v1_"+key.substr(0, 16),
			"airframe_id":str(wire["airframe_id"]), "slots":native_slots, "cosmetic_id":"ivory_teal"}
		# Zero cargo describes the hardware. Actual custody/Flight applies and
		# validates its own live payload exactly once; the wire carries no mass.
		var resolved: Dictionary = Catalog.resolve_build(native)
		if not resolved.get("valid", false):
			return {"ok":false, "code":"BUILD_WIRE_CATALOG_REJECTED", "build":{},
				"resolved":resolved.duplicate(true), "errors":resolved.get("errors", []).duplicate(true)}
		if _cache_order.size() >= CACHE_LIMIT:
			_resolved_cache.erase(_cache_order.pop_front())
		_resolved_cache[key] = resolved.duplicate(true)
		_cache_order.append(key)
	return {"ok":true, "code":"BUILD_WIRE_OK", "resolved":_resolved_cache[key]}
