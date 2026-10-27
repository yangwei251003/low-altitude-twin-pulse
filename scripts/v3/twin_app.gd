extends Node
## Route explicit packaged QA before TwinSession can open a player profile.
## Ordinary play keeps the original scene; test drivers may still load it directly.
const MAIN = preload("res://scenes/v3/main.tscn")
const UNDERDECK_RUNNER = preload("res://scripts/v3/qa/twin_underdeck_lan_runner.gd")

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var selection := select_entry(args)
	if not selection.ok:
		_reject(str(selection.code))
		return
	if selection.entry in ["normal-campaign","normal-f1","normal-whale","normal-crown","normal-underdeck","normal-clinic","normal-distribution","normal-canal","normal-i2-boss","normal-f2","normal-f2-boss","normal-i3","normal-f3","normal-i4","normal-f4","environment-lan","weapon-lan-combat","f2-patrol-lan"]:
		var paths := {"normal-campaign":"res://scripts/v3/qa/twin_normal_campaign_qa.gd","normal-f1":"res://scripts/v3/qa/twin_normal_f1_qa.gd","normal-whale":"res://scripts/v3/qa/twin_normal_whale_qa.gd","normal-crown":"res://scripts/v3/qa/twin_normal_crown_qa.gd","normal-underdeck":"res://scripts/v3/qa/twin_normal_underdeck_qa.gd","normal-clinic":"res://scripts/v3/qa/twin_normal_clinic_qa.gd","normal-distribution":"res://scripts/v3/qa/twin_normal_distribution_qa.gd","normal-canal":"res://scripts/v3/qa/twin_normal_canal_qa.gd","normal-i2-boss":"res://scripts/v3/qa/twin_normal_i2_boss_qa.gd","normal-f2":"res://scripts/v3/qa/twin_normal_f2_qa.gd","normal-f2-boss":"res://scripts/v3/qa/twin_normal_f2_boss_qa.gd","normal-i3":"res://scripts/v3/qa/twin_normal_i3_qa.gd","normal-f3":"res://scripts/v3/qa/twin_normal_f3_qa.gd","normal-i4":"res://scripts/v3/qa/twin_normal_i4_qa.gd","normal-f4":"res://scripts/v3/qa/twin_normal_f4_qa.gd","environment-lan":"res://scripts/v3/qa/twin_lan_environment_qa.gd","weapon-lan-combat":"res://scripts/v3/qa/twin_weapon_lan_combat_qa.gd","f2-patrol-lan":"res://scripts/v3/qa/twin_f2_patrol_lan_qa.gd"}
		var path: String=paths[selection.entry]
		var observer_script = load(path)
		if observer_script==null:
			_reject("observer_script_unavailable")
			return
		var checked: Dictionary=observer_script.preflight(args)
		if not checked.get("ok",false):
			_reject(str(checked.get("code","observer_preflight_rejected")))
			return
		_open_observed_game.call_deferred(observer_script,args,checked.get("config",{}),str(selection.entry))
		return
	if selection.entry == "game":
		_open_game.call_deferred()
		return
	var runner: Node
	match selection.entry:
		"underdeck-lan":
			runner = UNDERDECK_RUNNER.new()
			runner.name = "UnderdeckLanRunner"
		"clinic-lan":
			runner = load("res://scripts/v3/tests/clinic_lan_probe.gd").new()
			runner.name = "ClinicLanProbe"
		"distribution-lan":
			runner = load("res://scripts/v3/tests/distribution_lan_probe.gd").new()
			runner.name = "DistributionLanProbe"
	add_child(runner)
	var kind := "source_main" if OS.has_feature("editor") else "package_main"
	var result: Dictionary = runner.start(args, kind)
	if not result.ok:
		runner.queue_free()
		_reject(str(result.code))

func _open_game() -> void:
	# Keep the production RPC NodePath used by direct MAIN launches and dev.14.
	# The disposable routing shell must not become a new network ancestor.
	var session := MAIN.instantiate()
	get_tree().root.add_child(session)
	get_tree().current_scene = session
	queue_free()

func _open_observed_game(observer_script: Script,args: PackedStringArray,config: Dictionary,entry: String) -> void:
	# Preflight above finishes before even creating MAIN and opening its Store.
	# Preserve the same direct-root production Session/RPC path as ordinary play.
	var session := MAIN.instantiate()
	get_tree().root.add_child(session)
	get_tree().current_scene = session
	var observer: Node=observer_script.new()
	observer.name="EnvironmentLanObserver" if entry=="environment-lan" else "NormalCampaignObserver"
	session.add_child(observer)
	var accepted: Dictionary=observer.run(session,args if entry=="environment-lan" else config)
	if not accepted.get("ok",false): _reject(str(accepted.get("code","observer_start_rejected")))
	queue_free()

static func select_entry(args: PackedStringArray) -> Dictionary:
	if "--qa-performance-long-i2" in args:
		var long_checked: Dictionary = load("res://scripts/v3/qa/twin_campaign_performance.gd").long_i2_preflight(args)
		if not long_checked.ok: return long_checked
	var suites: Array[String] = []
	var specialized := false
	var normal_entry := ""
	var render_diagnostic := false
	var mobile_diagnostic := false
	var performance_output := ""
	var performance_profile := ""
	for argument in args:
		if argument=="--qa-renderer-mobile-diagnostic":
			if mobile_diagnostic: return {"ok":false,"code":"duplicate_mobile_renderer_diagnostic_flag"}
			mobile_diagnostic=true
		if argument=="--disable-3d-diagnostic":
			if render_diagnostic: return {"ok":false,"code":"duplicate_render_diagnostic_flag"}
			render_diagnostic=true
		if argument.begins_with("--qa-performance-output="): performance_output=argument.trim_prefix("--qa-performance-output=")
		if argument.begins_with("--qa-profile="): performance_profile=argument.trim_prefix("--qa-profile=")
		if argument == "--qa-suite": return {"ok":false, "code":"missing_suite_value"}
		if argument.begins_with("--qa-suite="):
			suites.append(argument.trim_prefix("--qa-suite="))
		if argument.begins_with("--qa-underdeck-") or argument.begins_with("--qa-clinic-") or argument.begins_with("--qa-distribution-") or argument.begins_with("--qa-canal-") or argument.begins_with("--qa-i2-boss-") or argument.begins_with("--qa-f2-") or argument.begins_with("--qa-i3-") or argument.begins_with("--qa-f3-") or argument.begins_with("--qa-i4-") or argument.begins_with("--qa-f4-") or argument.begins_with("--qa-lan-env-") or argument.begins_with("--qa-lan-weapon-") or argument.begins_with("--qa-lan-patrol-"): specialized = true
		if argument in ["--qa-normal-campaign","--qa-normal-f1","--qa-normal-whale","--qa-normal-crown","--qa-normal-underdeck","--qa-normal-clinic","--qa-normal-distribution","--qa-normal-canal","--qa-normal-i2-boss","--qa-normal-f2","--qa-normal-f2-boss","--qa-normal-i3","--qa-normal-f3","--qa-normal-i4","--qa-normal-f4"]:
			if not normal_entry.is_empty(): return {"ok":false,"code":"duplicate_normal_observer"}
			normal_entry={"--qa-normal-campaign":"normal-campaign","--qa-normal-f1":"normal-f1","--qa-normal-whale":"normal-whale","--qa-normal-crown":"normal-crown","--qa-normal-underdeck":"normal-underdeck","--qa-normal-clinic":"normal-clinic","--qa-normal-distribution":"normal-distribution","--qa-normal-canal":"normal-canal","--qa-normal-i2-boss":"normal-i2-boss","--qa-normal-f2":"normal-f2","--qa-normal-f2-boss":"normal-f2-boss","--qa-normal-i3":"normal-i3","--qa-normal-f3":"normal-f3","--qa-normal-i4":"normal-i4","--qa-normal-f4":"normal-f4"}[argument]
	if mobile_diagnostic and render_diagnostic: return {"ok":false,"code":"incompatible_render_diagnostics"}
	if mobile_diagnostic and (Array(args).filter(func(value: String): return value.begins_with("--qa-profile=")).size()!=1 or Array(args).filter(func(value: String): return value.begins_with("--qa-performance-output=")).size()!=1): return {"ok":false,"code":"duplicate_or_missing_mobile_profile_or_output"}
	if (render_diagnostic or mobile_diagnostic) and (not suites.is_empty() or not normal_entry.is_empty() or specialized or not performance_output.is_absolute_path() or not performance_output.get_file().begins_with("campaign-performance-") or ".." in performance_output or not performance_profile.begins_with("qa_campaign_performance_") or performance_profile!=performance_profile.validate_filename()):
		return {"ok":false,"code":"render_diagnostic_requires_isolated_performance_observer"}
	if suites.is_empty():
		if specialized and normal_entry not in ["normal-underdeck","normal-clinic","normal-distribution","normal-canal","normal-i2-boss","normal-f2","normal-f2-boss","normal-i3","normal-f3","normal-i4","normal-f4"]: return {"ok":false, "code":"specialized_arguments_require_suite"}
		if not normal_entry.is_empty(): return {"ok":true,"entry":normal_entry}
		var legacy_prefixes := ["--qa-profile=", "--qa-network=", "--qa-duration=", "--qa-report=", "--qa-capture-output=", "--qa-campaign-output=", "--qa-performance-output=", "--qa-performance-seconds="]
		for argument in args:
			if not argument.begins_with("--qa-"): continue
			if argument in ["--qa-performance-cpu","--qa-renderer-mobile-diagnostic","--qa-performance-long-i2"]: continue
			var known := false
			for prefix in legacy_prefixes:
				if argument.begins_with(prefix): known = true
			if not known: return {"ok":false, "code":"unknown_qa_argument"}
		return {"ok":true, "entry":"game"}
	if not normal_entry.is_empty() or suites.size() != 1 or suites[0] not in ["underdeck-lan", "clinic-lan", "distribution-lan","environment-lan","weapon-lan-combat","f2-patrol-lan"]:
		return {"ok":false, "code":"unknown_or_duplicate_suite"}
	# The runner verifies the complete exact argument set before any Session exists.
	return {"ok":true, "entry":suites[0]}

func _reject(code: String) -> void:
	push_error("QA_ENTRY_REJECTED " + code)
	get_tree().quit(2)
