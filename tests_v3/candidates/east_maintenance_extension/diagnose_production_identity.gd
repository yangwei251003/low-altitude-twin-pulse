extends SceneTree
## Minimal actual World build, no Session/profile/Store/network, no screenshots.
const World = preload("res://scripts/v3/twin_test_world.gd")
const Probe = preload("res://tests_v3/candidates/east_maintenance_extension/capture_production.gd")
const HudCapture = preload("res://scripts_tools/v3/capture_hud_visibility.gd")
var world: World
var output := ""
var checks: Array = []
var details: Dictionary = {}
var logger = HudCapture.CaptureLogger.new()
var started := 0
var finishing := false

func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	started = Time.get_ticks_usec()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size()!=1 or not args[0].begins_with("--identity-output=") or DisplayServer.get_name()!="headless":
		push_error("Identity diagnostic requires one fresh evidence path and headless")
		quit(2)
		return
	output = ProjectSettings.globalize_path(args[0].trim_prefix("--identity-output=")).replace("\\","/").simplify_path()
	var allowed: String = ProjectSettings.globalize_path("res://tests_v3/candidates/east_maintenance_extension/evidence").replace("\\","/").simplify_path()
	if output.get_base_dir().to_lower()!=allowed.to_lower() or not output.get_file().begins_with("production-identity-") \
		or DirAccess.dir_exists_absolute(output) or FileAccess.file_exists(output):
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(output)!=OK:
		quit(2)
		return
	create_timer(12.0,true,false,true).timeout.connect(_timeout)
	world = World.new()
	root.add_child(world)
	world.build("I2")
	var built: bool = world.build_errors.is_empty() and bool(world.east_maintenance_art.get("ok",false))
	checks.append({"name":"actual production World.build(I2) auto-installs the formal floor","passed":built,"actual":world.build_errors.duplicate()})
	if built:
		var identity: Dictionary = Probe.assembly_identity(world)
		checks.append_array(identity.checks)
		details = identity.details
	await _finish()

func _timeout() -> void:
	checks.append({"name":"12s internal watchdog","passed":false,"actual":"expired"})
	_finish.call_deferred()

func _finish() -> void:
	if finishing: return
	finishing = true
	if is_instance_valid(world): world.free()
	await process_frame
	await process_frame
	var logged: Dictionary = logger.snapshot()
	checks.append({"name":"zero engine errors including cleanup","passed":int(logged.error_count)==0,"actual":logged})
	var passed := true
	for row: Dictionary in checks: passed = passed and bool(row.passed)
	var report := {"passed":passed,"checks":checks,"details":details,"engine_log":logged,"images":0,
		"elapsed_seconds":float(Time.get_ticks_usec()-started)/1000000.0,
		"scope":"Actual World automatic-install identity diagnostic only; no Session, Store, second installation or new images. Preserve the first full MAIN report and its two PNGs."}
	var file := FileAccess.open(output.path_join("identity.json"),FileAccess.WRITE)
	var wrote: bool = file!=null
	if wrote:
		file.store_string(JSON.stringify(report,"\t",true,true));file.flush()
		wrote=file.get_error()==OK
		file.close()
	print("EAST_MAINTENANCE_PRODUCTION_IDENTITY ",JSON.stringify({"passed":passed and wrote,"checks":checks.size(),"output":output}))
	OS.remove_logger(logger)
	quit(0 if passed and wrote else 1)
