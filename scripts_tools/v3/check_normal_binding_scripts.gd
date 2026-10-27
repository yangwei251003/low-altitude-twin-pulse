extends SceneTree
## Load the full normal observer closure without creating a Session or Store.
const ENTRIES := ["campaign","f1","whale","crown","underdeck","clinic","distribution","canal","i2_boss","f2","f2_boss","i3","f3","i4","f4"]

func _initialize() -> void:
	var checked: Array = []
	var failed := false
	for entry: String in ENTRIES:
		var script: Script = load("res://scripts/v3/qa/twin_normal_"+entry+"_qa.gd")
		if script == null:
			failed = true
			checked.append({"entry":entry,"loaded":false})
			continue
		var rejected: Dictionary = script.preflight(PackedStringArray())
		var ok := not bool(rejected.get("ok",true))
		failed = failed or not ok
		checked.append({"entry":entry,"loaded":true,"empty_cli_rejected":ok,"code":rejected.get("code","")})
	print("NORMAL_BINDING_CLOSURE "+JSON.stringify({"checks":checked,"passed":not failed,"scope":"native source parse and missing-argument refusal only; no Session, Store or gameplay acceptance"}))
	quit(1 if failed else 0)
