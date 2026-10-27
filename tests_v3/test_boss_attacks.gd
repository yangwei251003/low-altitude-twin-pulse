extends SceneTree
## Pure rules only: no main scene, physics, saves or network.
const Attacks = preload("res://scripts/v3/gameplay/twin_boss_attacks.gd")
const EPS := 0.001
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_test_contract()
	_test_geometry()
	_test_invalid_values()
	print("V3_BOSS_ATTACK_TESTS " + JSON.stringify({"checks":checks, "failures":failures,
		"scope":"pure warning descriptors and geometric membership; no scene/physics/gameplay acceptance"}))
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)

func _test_contract() -> void:
	var valid := true
	for attack in ["low_sweep", "high_lance", "tractor"]:
		var rule: Dictionary = Attacks.definition(attack)
		valid = valid and rule.range == 42.0 and rule.shape == "locked_disc"
		valid = valid and rule.radius_inclusive == false and rule.color is Color
		valid = valid and not str(rule.name).is_empty() and not str(rule.message).is_empty()
		valid = valid and not str(rule.height_hint).is_empty() and Attacks.damage_for(attack) == 24.0
	_check(valid, "all attacks expose complete warnings, unchanged 42m range and 24 damage")
	_check(Attacks.definition("low_sweep").radius == 2.5 and Attacks.definition("high_lance").radius == 2.5 and Attacks.definition("tractor").radius == 3.5, "warning radii are the agreed 2.5/2.5/3.5m")
	_check(Attacks.definition("tractor").brake_immune and not Attacks.definition("low_sweep").brake_immune and not Attacks.definition("high_lance").brake_immune, "only tractor delegates brake immunity to the host")
	var changed: Dictionary = Attacks.definition("low_sweep")
	changed.radius = 30.0
	changed.message = "changed"
	_check(Attacks.definition("low_sweep").radius == 2.5 and Attacks.definition("low_sweep").message != "changed", "warning annotations cannot mutate authoritative definitions")
	_check(Attacks.definition("unknown").is_empty() and Attacks.damage_for("unknown") == 0.0 and not Attacks.contains("unknown", Vector3.ZERO, Vector3.ZERO), "unknown attacks fail closed")

func _test_geometry() -> void:
	var target := Vector3(11, 5, -7)
	# This reproduces the original bug: visually outside a 2.5m circle, but inside 3.5m.
	var old_bug_point := target + Vector3(3, 0, 0)
	_check(not Attacks.contains("low_sweep", old_bug_point, target) and not Attacks.contains("high_lance", old_bug_point, target) and Attacks.contains("tractor", old_bug_point, target), "3m is safe outside low/high warnings while remaining inside tractor")
	for attack in ["low_sweep", "high_lance", "tractor"]:
		var radius := 3.5 if attack == "tractor" else 2.5
		_check(Attacks.contains(attack, target + Vector3(radius - EPS, 0, 0), target), attack + " just inside translated circle")
		_check(not Attacks.contains(attack, target + Vector3(radius, 0, 0), target), attack + " exact circle edge excluded")
		_check(not Attacks.contains(attack, target + Vector3(radius + EPS, 0, 0), target), attack + " just outside circle")
	_check(Attacks.contains("high_lance", target + Vector3(1.5 - EPS, 0, 2), target) and not Attacks.contains("high_lance", target + Vector3(1.5, 0, 2), target) and not Attacks.contains("high_lance", target + Vector3(1.5 + EPS, 0, 2), target), "3-4-5 diagonal boundary is circular, not a square or single-axis check")
	_check(Attacks.contains("low_sweep", Vector3(11, 7 - EPS, -7), target) and not Attacks.contains("low_sweep", Vector3(11, 7, -7), target) and not Attacks.contains("low_sweep", Vector3(11, 7 + EPS, -7), target), "low sweep world-height threshold excludes exact 7m and above")
	_check(Attacks.contains("low_sweep", Vector3(11, -20, -7), Vector3(11, 100, -7)) and not Attacks.contains("low_sweep", Vector3(11, 8, -7), Vector3(11, -100, -7)), "low sweep height is absolute world Y, independent of target altitude")
	for sign_value in [-1.0, 1.0]:
		_check(Attacks.contains("high_lance", target + Vector3(0, sign_value * (2.5 - EPS), 0), target) and not Attacks.contains("high_lance", target + Vector3(0, sign_value * 2.5, 0), target) and not Attacks.contains("high_lance", target + Vector3(0, sign_value * (2.5 + EPS), 0), target), "high lance symmetric altitude boundary " + str(sign_value))
	_check(Attacks.contains("high_lance", Vector3(11, 100, -7), Vector3(11, 100, -7)) and not Attacks.contains("high_lance", Vector3(11, 5, -7), Vector3(11, 100, -7)), "high lance follows target altitude, not world ground")
	_check(Attacks.contains("tractor", Vector3(11, -100, -7), target) and Attacks.contains("tractor", target, target) and Attacks.contains("tractor", Vector3(11, 100, -7), target), "tractor disc membership is unbounded vertically; host range and brake still apply")

func _test_invalid_values() -> void:
	var rejected := true
	# Every component matters, even Y for a vertically unbounded tractor disc.
	for invalid in [NAN, INF, -INF]:
		for axis in range(3):
			var bad := Vector3.ZERO
			bad[axis] = invalid
			for attack in ["low_sweep", "high_lance", "tractor"]:
				rejected = rejected and not Attacks.contains(attack, bad, Vector3.ZERO)
				rejected = rejected and not Attacks.contains(attack, Vector3.ZERO, bad)
	_check(rejected, "NaN and either infinity in any point or target component are rejected")
