extends SceneTree
## Read-only headless signature source for build_shore_layout.py.
## Godot --headless --path . --script res://scripts_tools/v3/shore_import_signatures.gd
## Parse ONLY the line beginning with V3_SHORE_IMPORT_SIGNATURES .
## No artifacts, raw GLBs, import settings or runtime assets are written.
const Geometry = preload("res://scripts/v3/world/twin_imported_geometry.gd")
const MARKER := "V3_SHORE_IMPORT_SIGNATURES "
const HEIGHTS := [3,10,12,17]

func _init() -> void:
	var signatures: Dictionary = {}
	var ok := true
	for height in HEIGHTS:
		var path := "res://assets/v3/root_buttress/root_buttress_h%d.glb" % height
		var result: Dictionary = Geometry.signature(path)
		signatures[path]=result
		ok=ok and bool(result.ok)
	print(MARKER+JSON.stringify({"ok":ok,"algorithm":Geometry.ALGORITHM,"signatures":signatures}))
	quit(0 if ok else 1)

