extends SceneTree
## Editor --script adapter only. Packaged main uses the exact same Node runner.
const Runner = preload("res://scripts/v3/qa/twin_underdeck_lan_runner.gd")

func _initialize() -> void:
	_launch.call_deferred()

func _launch() -> void:
	var runner = Runner.new()
	root.add_child(runner)
	var result: Dictionary = runner.start(OS.get_cmdline_user_args(), "source_script")
	if not result.get("ok", false):
		push_error("Underdeck QA preflight refused: " + str(result.get("code", "unknown")))
		quit(2)
