extends RefCounted
## Optional authored field evidence; the original Story owns range/LOS/Store.
const PATH := "res://data/v3/content/dev88_progression/secrets.json"
const Props = preload("res://scripts/v3/content/presentation_next/twin_content_prop_factory.gd")
static var _notes: Array = []

static func notes(region: String = "") -> Array:
	if _notes.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if data is Dictionary: _notes = data.get("notes", [])
	var result: Array = []
	for row: Dictionary in _notes:
		if region.is_empty() or row.region == region: result.append(row.duplicate(true))
	return result

static func install(world: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "Dev88FieldEvidence"
	world.add_child(root)
	for row: Dictionary in notes(str(world.region_id)):
		var p: Array = row.position
		var prop := Props.make(str(row.get("prop", "archive_stela")), str(world.region_id))
		prop.name = str(row.id).replace(":", "_")
		prop.position = Vector3(float(p[0]), float(p[1]) - 2.4, float(p[2]))
		prop.scale = Vector3.ONE * .55
		root.add_child(prop)
	return root
