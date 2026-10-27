extends SceneTree
## Resource validation only: never instantiate a session or access user profiles.
var checks = 0
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func _initialize() -> void:
	for id in ["R1","R2","R3","R4"]:
		var path = "res://data/worldui/"+id+".json"
		check(FileAccess.file_exists(path),"Authored layout exists: "+id)
		var layout = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		check(layout is Dictionary and not layout.get("land",[]).is_empty() and not layout.get("roads",[]).is_empty(),"Authored geometry loads: "+id)
		var preview = load("res://assets/world_ui/previews/"+id+".png")
		check(preview is Texture2D and preview.get_width()>0 and preview.get_height()>0,"Actual preview imports: "+id)
	var manifest_path = "res://assets/models/worldui/manifest.json"
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	check(manifest is Dictionary and manifest.get("models",[]).size()>=15,"WorldUI model manifest")
	if manifest is Dictionary:
		for file in manifest.get("models",[]):
			var scene = load("res://assets/models/worldui/"+str(file))
			check(scene is PackedScene,"GLB imports: "+str(file))
	check(load("res://assets/shaders/worldui_ground.gdshader") is Shader,"Ground shader loads")
	for path in ["scripts/v2/region_layout.gd","scripts/v2/worldui_builder.gd","scripts_tools/worldui_models.py","scripts_tools/worldui_author_layouts.py","scripts_tools/apply_r3_maritime_layout.py","assets/source/worldui/conveyor_kenney/kenney_conveyor-kit.zip","assets/source/worldui/conveyor_kenney/License.txt","README_WORLDUI.md","docs/v2/WORLDUI_VERIFICATION.md"]:
		check(FileAccess.file_exists("res://"+path),"Editable/release input exists: "+path)
	print("WORLDUI_SOURCE_VERIFY ",JSON.stringify({"checks":checks,"failures":failures,"passed":failures.is_empty(),"scope":"Fresh source import and resource loading; no gameplay session, save access, exported GUI, performance or human play."}))
	quit(0 if failures.is_empty() else 1)
