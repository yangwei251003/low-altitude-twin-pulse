extends RefCounted
## A complete snapshot slice, never custody, a client joint or a save envelope.
const Cargo = preload("res://scripts/v3/gameplay/twin_thermal_cargo_session.gd")
const KEYS := ["version","epoch","pose","phase","role_identity","visible","weight_kg"]

static func valid(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.is_empty(): return true
	if value.size() != KEYS.size(): return false
	for key in KEYS:
		if not value.has(key): return false
	if value.version != 1 or not value.epoch is int or value.epoch < 1: return false
	if not Cargo._pose_valid(value.pose) or not value.visible is bool or value.weight_kg != 2.0: return false
	if value.phase not in ["free","docked","carried","dropping","waiting_role"]: return false
	if not value.role_identity is String or value.role_identity.length()>96: return false
	return not value.role_identity.is_empty() if value.phase == "carried" else true
