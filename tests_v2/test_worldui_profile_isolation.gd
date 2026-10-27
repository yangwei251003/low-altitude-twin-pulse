extends SceneTree
## Targeted owner-run proposal. Hashes real profile files read-only; gameplay uses QA only.
## Does not claim human input, rendering, performance or absence of previous save changes.
var qa_case = ""
var qa_root = ""
var explicit_root = ""
var game: GameSessionV2
var checks = 0
var failures: Array[String] = []
var normal_before: Dictionary = {}

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--v2-qa=catalog_isolation_"):
			qa_case = argument.trim_prefix("--v2-qa=").validate_filename()
	if qa_case.is_empty() or DisplayServer.get_name() != "headless":
		printerr("Requires headless and fresh --v2-qa=catalog_isolation_<unique>")
		quit(2); return
	qa_root = "user://qa_v2/session_"+qa_case
	explicit_root = "user://qa_v22/"+qa_case
	if DirAccess.dir_exists_absolute(qa_root) or DirAccess.dir_exists_absolute(explicit_root):
		printerr("Existing QA fixtures preserved; choose a new case")
		quit(2); return
	var source = FileAccess.get_file_as_string("res://scripts/v2/session.gd")
	if not source.contains('if qa_mode and profiles.base_path == "user://profiles":'):
		printerr("Apply the isolated catalog fix before invoking production _ready")
		quit(2); return
	normal_before = _normal_snapshot()
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
	print("WORLDUI_QA_CATALOG_CHECK ",JSON.stringify({"pass":condition,"check":label}))

func settle() -> void:
	for tick in 6: await process_frame

func _scan(directory: String, relative: String, output: Dictionary) -> void:
	for name in DirAccess.get_files_at(directory):
		var file_path = directory.path_join(name)
		var stream = FileAccess.open(file_path,FileAccess.READ)
		if stream == null:
			failures.append("Cannot hash protected profile file: "+relative.path_join(name))
			continue
		var bytes = stream.get_length()
		stream.close()
		output.files[relative.path_join(name)] = {"bytes":bytes,"sha256":FileAccess.get_sha256(file_path)}
	for name in DirAccess.get_directories_at(directory):
		var child = relative.path_join(name)
		output.directories.append(child)
		_scan(directory.path_join(name),child,output)

func _normal_snapshot() -> Dictionary:
	var exists = DirAccess.dir_exists_absolute("user://profiles")
	var result = {"exists":exists,"files":{},"directories":[]}
	if exists: _scan("user://profiles","",result)
	return result

func _profile_buttons(node: Node, output: Array[Button]) -> void:
	if node is Button and node.is_visible_in_tree() and node.text == "进入此档案": output.append(node)
	for child in node.get_children(): _profile_buttons(child,output)

func _switch_via_ui(index: int, expected_base: String) -> void:
	game.ui.show_profiles()
	await settle()
	var buttons: Array[Button] = []
	_profile_buttons(game.ui.panel,buttons)
	check(buttons.size()==3,"Selector exposes three actual native buttons")
	if buttons.size()!=3: return
	check(not buttons[index].disabled,"QA profile selector is enabled")
	buttons[index].pressed.emit()
	await settle()
	var id: String = ProfileCatalogV22.IDS[index]
	check(game.profiles.selected==id,"Button selects QA profile "+id)
	check(game.repository.root_path==expected_base.path_join(id),"Selected repository stays in assigned QA catalog: "+id)
	# Fail closed before making any representative write if a future regression escapes QA.
	if game.repository.root_path!=expected_base.path_join(id): return
	check(game.rename_profile("QA隔离 "+id),"Representative profile-name transaction succeeds in QA: "+id)
	check(FileAccess.file_exists(expected_base.path_join("index.cfg")),"Selected index is written inside QA catalog")
	check(_normal_snapshot()==normal_before,"Normal profile/index file hashes unchanged after switch and write: "+id)

func _run() -> void:
	game = GameSessionV2.new()
	root.add_child(game)
	await settle()
	check(game.qa_mode,"Actual production _ready enables explicit QA mode")
	check(game.repository.root_path==qa_root,"Initial standalone QA repository preserves session_<case> harness contract")
	var catalog_root = qa_root.path_join("profiles")
	check(game.profiles.base_path==catalog_root,"Default profile catalog is relocated under this QA session")
	check(game.profiles.migration_source==qa_root.path_join("nonexistent_legacy_source"),"QA initialization does not fall back to the old player's migration source")
	check(_normal_snapshot()==normal_before,"Normal profile tree unchanged through initial real lobby construction")
	if game.profiles.base_path!=catalog_root:
		await _finish(); return
	check(game.list_profiles().size()==3,"QA list builds all three profile cards")
	for index in 3: await _switch_via_ui(index,catalog_root)
	check(game.repository.root_path.begins_with(qa_root+"/"),"QA selection never leaves this session subtree")
	# Catalog/default is intentionally a DIFFERENT QA save from the initial standalone repo.
	check(catalog_root.path_join("default")!=qa_root,"QA catalog progress is not confused with standalone startup progress")
	game.queue_free()
	await settle()
	game = GameSessionV2.new()
	var explicit_catalog = ProfileCatalogV22.new(explicit_root.path_join("profiles"),explicit_root.path_join("nonexistent_legacy_source"))
	explicit_catalog.initialize()
	check(explicit_catalog.select("free_01"),"Explicit fixture prepares its own selected index")
	game.profiles = explicit_catalog
	root.add_child(game)
	await settle()
	check(game.profiles==explicit_catalog,"Production _ready preserves the explicit isolated catalog object")
	check(game.profiles.base_path==explicit_root.path_join("profiles"),"Explicit test fixture path remains authoritative")
	check(game.profiles.selected=="free_01","Production _ready preserves explicit fixture selection")
	check(game.repository.root_path==qa_root,"Explicit fixture still retains original session_<case> startup repository contract")
	await _switch_via_ui(2,explicit_root.path_join("profiles"))
	await _finish()

func _finish() -> void:
	if is_instance_valid(game): game.queue_free()
	await settle()
	var after = _normal_snapshot()
	check(after==normal_before,"Final normal profile directories, index and save hashes equal baseline")
	var report = {"suite":"worldui_qa_profile_isolation","checks":checks,"failures":failures,"ok":failures.is_empty(),"qa_case":qa_case,"qa_root":qa_root,"explicit_fixture_root":explicit_root,"normal_files":normal_before.files.size(),"normal_snapshot_before_sha256":JSON.stringify(normal_before).sha256_text(),"normal_snapshot_after_sha256":JSON.stringify(after).sha256_text(),"scope":"Headless production Session/UI callbacks with standalone and explicit QA catalogs. Normal profile files are read only to compare hashes. Not native input, graphics or performance evidence; does not infer any past file modification."}
	var output = FileAccess.open(qa_root.path_join("catalog_isolation_summary.json"),FileAccess.WRITE)
	if output!=null:
		output.store_string(JSON.stringify(report,"\t")); output.close()
	print("WORLDUI_QA_CATALOG_SUMMARY ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
