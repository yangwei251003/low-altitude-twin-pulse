class_name TwinBossAttacks
extends RefCounted
## Shared warning geometry and hit rules. World range, occlusion and braking are host checks.

const _DEFINITIONS := {
	"low_sweep": {
		"name":"低空脉冲", "shape":"locked_disc", "radius":2.5, "range":42.0,
		"height_mode":"below_world", "height_limit":7.0, "radius_inclusive":false,
		"brake_immune":false, "color":Color("ed815f"),
		"message":"低空脉冲：离开预警圈、升高或借地形阻挡。",
		"height_hint":"仅世界高度低于 7 米受影响；达到 7 米可避开。",
	},
	"high_lance": {
		"name":"高位瞄准", "shape":"locked_disc", "radius":2.5, "range":42.0,
		"height_mode":"around_target", "height_limit":2.5, "radius_inclusive":false,
		"brake_immune":false, "color":Color("f5bf65"),
		"message":"高位瞄准：离开预警圈、改变高度或下降到掩体。",
		"height_hint":"与锁定高度相差至少 2.5 米可避开。",
	},
	"tractor": {
		"name":"牵引", "shape":"locked_disc", "radius":3.5, "range":42.0,
		"height_mode":"unbounded", "height_limit":0.0, "radius_inclusive":false,
		"brake_immune":true, "color":Color("62c9e6"),
		"message":"牵引即将启动：离开预警圈、制动或切断视线。",
		"height_hint":"圆盘内不区分高度；制动可抵抗牵引。",
	},
}

static func definition(attack: String) -> Dictionary:
	# Callers may annotate a warning without changing future authoritative rules.
	return _DEFINITIONS.get(attack, {}).duplicate(true)

static func contains(attack: String, point: Vector3, target: Vector3) -> bool:
	if not _DEFINITIONS.has(attack) or not point.is_finite() or not target.is_finite():
		return false
	var rule: Dictionary = _DEFINITIONS[attack]
	var offset := Vector2(point.x - target.x, point.z - target.z)
	if offset.length_squared() >= float(rule.radius) * float(rule.radius):
		return false
	match str(rule.height_mode):
		"below_world":
			return point.y < float(rule.height_limit)
		"around_target":
			return absf(point.y - target.y) < float(rule.height_limit)
		"unbounded":
			return true
	return false

static func damage_for(attack: String) -> float:
	return 24.0 if _DEFINITIONS.has(attack) else 0.0
