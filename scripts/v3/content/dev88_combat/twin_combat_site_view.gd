extends RefCounted
## Read-only reliable projection. A packet can never request motion or damage.
const Catalog = preload("res://scripts/v3/content/dev88_combat/twin_combat_sites_catalog.gd")
const State = preload("res://scripts/v3/content/dev88_combat/twin_combat_sites_state.gd")
const KIND := "combat_sites88_v1"
const MAX_COUNTER := 2147483000
const MAX_UNITS := 3
const MAX_BOLTS := 24
const ROLES := ["scout", "harasser", "support", "suppressor"]
const PHASES := ["idle", "approach", "running", "ready", "failed", "blocked", "completed"]
const REASONS := ["none", "approach", "pause", "boss", "radio", "menu", "journal", "wheel", "travel", "choice", "vote", "no_active_pilots", "pinned", "fault"]
const KEYS := ["version", "session_id", "region", "epoch", "serial", "site_id", "phase", "wave", "total_waves", "actors", "payload", "bullets", "saved", "error"]
const ACTOR_KEYS := ["id", "role", "position", "velocity", "heading", "health", "armor", "alive", "neutralized", "controlled", "charge", "temperature", "pinned", "ceasefire", "recoil", "warning_id", "warning_ms", "warning_end"]
const PAYLOAD_KEYS := ["id", "position", "velocity", "heading", "health", "waypoint", "arrived", "alive"]

static func valid(value: Variant) -> bool:
	if not _keys(value, KEYS) or value.version != 1 or not value.session_id is String or value.session_id.is_empty() or value.session_id.length() > 96: return false
	if value.region not in ["F2", "I3", "F3", "I4", "F4"] or not _int(value.epoch, 1, MAX_COUNTER) or not _int(value.serial, 0, MAX_COUNTER): return false
	if not value.site_id is String or not value.phase is String or value.phase not in PHASES or not value.error is String or value.error.length() > 96: return false
	var spec: Dictionary = Catalog.definition(value.site_id)
	if value.site_id.is_empty():
		if value.phase != "idle" or value.wave != 0 or value.total_waves != 0: return false
	elif spec.is_empty() or str(spec.region) != value.region or not _int(value.wave, 0, spec.waves.size()) or value.total_waves != spec.waves.size(): return false
	if not State.valid(value.saved): return false
	if not value.actors is Array or value.actors.size() > MAX_UNITS or not value.bullets is Array or value.bullets.size() > MAX_BOLTS or not value.payload is Dictionary: return false
	var ids: Dictionary = {}
	for a: Variant in value.actors:
		if not _keys(a, ACTOR_KEYS) or not a.id is String or not a.id.begins_with(str(value.region) + ":combat88:unit:") or a.id.length() > 96 or ids.has(a.id): return false
		ids[a.id] = true
		if a.role not in ROLES or not _point(a.position) or not _vector(a.velocity) or a.velocity.length() > 60.0 or not _number(a.heading, -1000000, 1000000): return false
		var hp: float = float({"scout":32.0, "harasser":42.0, "support":64.0, "suppressor":76.0}[a.role])
		var armor: float = float({"scout":5.0, "harasser":8.0, "support":14.0, "suppressor":22.0}[a.role])
		if not _number(a.health, 0.0, hp) or not _number(a.armor, 0.0, armor) or not a.alive is bool or not a.neutralized is bool or not a.controlled is bool: return false
		if a.alive != (float(a.health) > 0.0 and not a.neutralized): return false
		if not _number(a.charge, 0.0, 100.0) or not _number(a.temperature, -40.0, 200.0) or not a.pinned is bool: return false
		if not a.ceasefire is String or a.ceasefire not in REASONS or not _number(a.recoil, 0.0, .12): return false
		if not _int(a.warning_id, 0, MAX_COUNTER) or not _int(a.warning_ms, 0, 1250) or not _point(a.warning_end, 150.0, -50.0, 80.0): return false
		if int(a.warning_ms) > 0 and (not a.alive or a.ceasefire != "none" or int(a.warning_id) <= 0): return false
	if not value.payload.is_empty():
		var p: Dictionary = value.payload
		if not _keys(p, PAYLOAD_KEYS) or p.id != str(value.region) + ":combat88:payload" or not _point(p.position) or not _vector(p.velocity) or p.velocity.length() > 20.0 or not _number(p.heading, -1000000, 1000000): return false
		if not _number(p.health, 0.0, 64.0) or not _int(p.waypoint, 0, 8) or not p.arrived is bool or not p.alive is bool or p.alive != (float(p.health) > 0.0): return false
	var bullet_ids: Dictionary = {}
	for row: Variant in value.bullets:
		if not _keys(row, ["id", "position", "basis", "friendly"]) or not _int(row.id, 1, MAX_COUNTER) or bullet_ids.has(row.id) or not row.friendly is bool: return false
		bullet_ids[row.id] = true
		if not _point(row.position, 150.0, -50.0, 80.0) or not row.basis is Basis: return false
		for axis in range(3):
			if not row.basis[axis].is_finite(): return false
		if absf(row.basis.x.length() - .45) > .0001 or absf(row.basis.y.length() - .45) > .0001 or absf(row.basis.z.length() - 2.6) > .0001: return false
		if absf(row.basis.x.normalized().dot(row.basis.y.normalized())) > .0001 or absf(row.basis.x.normalized().dot(row.basis.z.normalized())) > .0001 or absf(row.basis.y.normalized().dot(row.basis.z.normalized())) > .0001: return false
	return true

static func _keys(value: Variant, keys: Array) -> bool:
	if not value is Dictionary or value.size() != keys.size(): return false
	for key: Variant in value:
		if not key is String or key not in keys: return false
	return true

static func _point(value: Variant, horizontal: float = 40.0, low: float = -1.0, high: float = 27.0) -> bool:
	return _vector(value) and absf(value.x) <= horizontal and absf(value.z) <= horizontal and value.y >= low and value.y <= high

static func _vector(value: Variant) -> bool:
	return value is Vector3 and value.is_finite()

static func _number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= low and float(value) <= high

static func _int(value: Variant, low: int, high: int) -> bool:
	return value is int and value >= low and value <= high
