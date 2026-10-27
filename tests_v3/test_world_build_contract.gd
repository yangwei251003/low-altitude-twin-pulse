extends SceneTree
## Faulty candidate instances only; no source asset or save mutations.
const World = preload("res://scripts/v3/twin_test_world.gd")
class BrokenBossWorld:
	extends World
	func _build_boss() -> void:
		super._build_boss()
		if region_id == "I1":
			art_whale.imported = false
			art_whale.import_errors.append("fixture_missing_pivot")
		else:
			crown_arena.imported = false
			crown_arena.model.imported = false
			crown_arena.model.import_errors.append("fixture_missing_core")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _run() -> void:
	for region in ["I1", "F1"]:
		var healthy := World.new()
		root.add_child(healthy)
		healthy.build(region)
		_check(healthy.build_errors.is_empty(), region + " healthy production import accepted")
		root.remove_child(healthy)
		healthy.free()
		var broken := BrokenBossWorld.new()
		root.add_child(broken)
		broken.build(region)
		_check(broken.build_errors.size() == 1, region + " invalid required model rejects complete region")
		_check(str(broken.build_errors).contains("fixture_missing_"), region + " preserves actionable wrapper diagnostic")
		root.remove_child(broken)
		broken.free()
	print("V3_WORLD_BUILD_CONTRACT ", JSON.stringify({"checks":checks, "failures":failures}))
	quit(0 if failures.is_empty() else 1)
