extends RefCounted
## Presentation only: original native route points, no interaction or proof.
const Cargo = preload("res://scripts/v3/gameplay/twin_thermal_cargo_session.gd")
const IDS := ["I3:cargo_outer_guide_1","I3:cargo_outer_guide_2","I3:cargo_outer_guide_3"]

static func markers() -> Array:
	var result: Array = []
	for index: int in Cargo.OUTER.size():
		var at: Vector3 = Cargo.OUTER[index]
		result.append({"id":IDS[index],"region":"I3","kind":"navigation","radius":0.0,
			"position":[at.x,at.y,at.z],"label":"外廊 %d/3 · 高度 %.0fm" % [index+1,at.y]})
	return result

static func active_ids(region: String, targets: Array) -> Array:
	if region != "I3": return []
	for target: Dictionary in targets:
		if str(target.get("target_id","")) == Cargo.FACT: return IDS.duplicate()
	return []
