extends SceneTree
## Read-only compatibility probe for the retained actual opening QA profile.
## No MAIN, network, simulation or fabricated campaign progress.
const QA=preload("res://scripts/v3/qa/twin_normal_f1_qa.gd")
func _init() -> void:
	var output:=ProjectSettings.globalize_path("res://artifacts/v3/normal-f1-preflight.json")
	var result: Dictionary=QA.preflight(PackedStringArray(["--qa-normal-f1","--qa-profile="+QA.SOURCE_PROFILE,"--qa-normal-output="+output,"--qa-normal-seconds=300"]))
	print("NORMAL_F1_READ_ONLY_PREFLIGHT "+JSON.stringify(result))
	quit(0 if result.get("ok",false) else 1)
