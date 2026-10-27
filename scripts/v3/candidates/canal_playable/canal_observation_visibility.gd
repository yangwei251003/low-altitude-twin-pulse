extends "res://scripts/v3/art/twin_terrain_visibility.gd"
## One owner for all local material copies. Nearby observed machinery gets the
## same physical-ray cutaway as the pilot; collision and ability LOS stay solid.
const OBSERVATION_RANGE := 14.0
var subjects: Array[Node3D] = []

func observe(target: Node3D, bench: Node3D) -> void:
	subjects.clear()
	if is_instance_valid(target): subjects.append(target)
	if is_instance_valid(bench) and is_instance_valid(bench.beneficiary):
		subjects.append(bench.beneficiary)
		if bench.report().phase != "departed": subjects.append(bench.head)

func _sample_points() -> Array[Vector3]:
	var points: Array[Vector3] = super._sample_points()
	var view: Rect2 = _camera.get_viewport().get_visible_rect()
	for subject: Node3D in subjects:
		if not is_instance_valid(subject) or not subject.is_visible_in_tree(): continue
		var at: Vector3 = subject.global_position
		if _pilot.global_position.distance_to(at) > OBSERVATION_RANGE or _camera.is_position_behind(at): continue
		if not view.has_point(_camera.unproject_position(at)): continue
		points.append(at)
		points.append(at + _camera.global_basis.x * .32)
		points.append(at - _camera.global_basis.x * .32)
	return points

func report() -> Dictionary:
	var faded: Array = []
	for entry: Dictionary in _entries.values():
		if entry.alpha < .99:
			faded.append({"body":str(entry.root.name),"alpha":entry.alpha})
	return {"occluded":occluded,"faded":faded,"subjects":subjects.size()}
