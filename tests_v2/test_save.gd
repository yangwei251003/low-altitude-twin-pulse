extends SceneTree

const Repository = preload("res://scripts/v2/save_repository.gd")
var failures: Array = []
var checks: int = 0
var sandbox: String

func _initialize() -> void:
	sandbox = "user://qa_v2/save_" + Crypto.new().generate_random_bytes(8).hex_encode()
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	checks += 1
	print("SAVE_V2_", "PASS " if condition else "FAIL ", description)
	if not condition:failures.append(description)

func write_json(path: String, value) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value, "", true, true))
	file.close()

func write_envelope(repo, path: String, payload: Dictionary) -> void:
	write_json(path, {"payload":payload, "payload_sha256":repo._canonical(payload).sha256_text()})

func fresh(case_id: String):
	var repo = Repository.new(sandbox.path_join(case_id))
	check(repo.load_profile(), case_id + " new profile loads")
	return repo

func run() -> void:
	test_transactions()
	test_physics_float_roundtrip()
	test_recovery()
	test_validation()
	test_fault_boundaries()
	test_migration()
	var summary = {"suite":"save_v2", "checks":checks, "failures":failures, "ok":failures.is_empty(), "sandbox":sandbox}
	write_json(sandbox.path_join("summary.json"), summary)
	print("SAVE_V2_SUMMARY ", JSON.stringify(summary))
	quit(0 if failures.is_empty() else 1)

func test_transactions() -> void:
	var repo = fresh("transactions")
	var tx = {"id":"campaign:M01:stage:1:first", "parts_delta":80, "set":{"campaign.active_checkpoint":{"mission_id":"M01", "stage":2}, "world.restored_objects.R1_station":"restored"}, "append":{"campaign.completed_stages":["M01_stage_1", "M01_stage_1"]}}
	check(repo.commit(tx).ok, "stage commit succeeds")
	for index in range(100):
		var result = repo.commit(tx)
		if not result.ok or not result.duplicate:failures.append("duplicate receipt " + str(index))
	check(repo.data.wallet.parts == 80 and repo.data.ledger.receipts.size() == 1, "100 duplicate receipts pay once")
	check(repo.data.campaign.completed_stages == ["M01_stage_1"] and repo.data.world.restored_objects.R1_station == "restored", "stage and world commit together with unique append")
	var reload = Repository.new(repo.root_path)
	check(reload.load_profile() and reload.data.wallet.parts == 80 and reload.data.campaign.active_checkpoint.stage == 2, "stage survives restart")
	var before = repo.data.duplicate(true)
	check(not repo.commit({"id":"overspend", "parts_delta":-81}).ok and repo.data == before, "negative balance rejects without mutation")
	check(not repo.commit({"id":"bypass", "set":{"wallet.parts":999}}).ok, "wallet cannot bypass transactional delta")
	check(not repo.commit({"id":"erase-ledger", "set":{"ledger":{"receipts":[]}}}).ok, "receipt ledger cannot be replaced")
	check(repo.commit({"id":"buy", "parts_delta":-20, "append":{"owned_modules":["cooling_duct"]}}).ok, "purchase has one atomic wallet and ownership change")
	check(repo.commit({"id":"settings", "set":{"settings.volume":0.654321987654321}}).ok, "fractional settings persist with canonical hash")
	reload = Repository.new(repo.root_path)
	check(reload.load_profile() and is_equal_approx(reload.data.settings.volume, 0.654321987654321), "canonical numeric hash survives JSON round trip")
	check(repo._generation_files().size() == 2, "two complete generations retained")

func test_recovery() -> void:
	var repo = fresh("recovery")
	repo.commit({"id":"one", "parts_delta":10})
	repo.commit({"id":"two", "parts_delta":20})
	write_json(repo.root_path.path_join("manifest.json"), {"broken":true})
	var reload = Repository.new(repo.root_path)
	check(reload.load_profile() and reload.data.wallet.parts == 30, "broken manifest recovers newest complete generation")
	DirAccess.remove_absolute(repo.root_path.path_join("profile_g000002.json"))
	reload = Repository.new(repo.root_path)
	check(reload.load_profile() and reload.data.wallet.parts == 10, "missing newest generation recovers previous generation")
	write_json(repo.root_path.path_join("profile_g000002.json"), {"broken":true})
	reload = Repository.new(repo.root_path)
	check(reload.load_profile() and reload.data.wallet.parts == 10, "corrupt newest generation recovers previous generation")
	check(reload.commit({"id":"three", "parts_delta":1}).ok and reload.data.generation == 3, "recovery saves a fresh generation without overwriting corrupt evidence")
	check(FileAccess.file_exists(repo.root_path.path_join("profile_g000001.json")), "recovery retains previous valid generation")
	var both_bad = fresh("both_bad")
	both_bad.commit({"id":"one"})
	write_json(both_bad.root_path.path_join("profile_g000001.json"), {"broken":true})
	reload = Repository.new(both_bad.root_path)
	check(not reload.load_profile() and not reload.commit({"id":"overwrite"}).ok, "no valid generation blocks writing instead of replacing history")

func test_physics_float_roundtrip() -> void:
	var repo = fresh("physics_floats")
	var checkpoint = {"job_id":"M02", "stage_index":1, "seconds":124.45000649094582, "run_state":{"cargo_records":{"cargo":{"integrity":0.9640512752532959,"position":[128.47596740722656,0.3499789535999298,159.69802856445312]}}}}
	check(repo.commit({"id":"cargo-stage", "parts_delta":72, "set":{"campaign.active_checkpoint":checkpoint}}).ok,"real M02 physics decimals publish a complete generation")
	var consistent = true
	for index in range(20):
		var reload = Repository.new(repo.root_path)
		consistent = consistent and reload.load_profile() and reload.data == repo.data
		consistent = consistent and reload.commit({"id":"float-reload-"+str(index),"set":{"campaign.active_checkpoint":reload.data.campaign.active_checkpoint}}).ok
		repo = reload
	check(consistent and repo.data.wallet.parts == 72,"20 float checkpoint reloads preserve disk/live equality and wallet")
	check(absf(float(repo.data.campaign.active_checkpoint.run_state.cargo_records.cargo.integrity)-0.9640512752532959)<0.000000000001,"cargo integrity retains sub-picounit precision")
	var path = repo.root_path.path_join(repo._generation_files()[0])
	var envelope = repo._parse(path)
	envelope.payload_json = str(envelope.payload_json).replace("0.964051", "0.864051")
	write_json(path,envelope)
	check(repo._read_generation(path).is_empty(),"raw JSON payload tampering fails checksum")

func test_validation() -> void:
	var repo = fresh("validation")
	check(not repo.commit({"id":"nan", "parts_delta":NAN}).ok, "nonfinite values rejected")
	check(not repo.commit({"id":"fraction", "parts_delta":0.5}).ok, "fractional currency rejected")
	check(not repo.commit({"id":"wrong-nested", "set":{"campaign.completed_stages":{}}}).ok, "nested wrong type rejected")
	check(not repo.commit({"id":"bad-record", "append":{"records":[{"time":{}}]}}).ok, "malformed numeric record rejected")
	check(not repo.commit({"id":"traversal", "set":{"settings..volume":1}}).ok, "invalid transaction path rejected")
	var future = repo.defaults()
	future.schema_version = 3
	future.generation = 2
	write_envelope(repo, repo.root_path.path_join("profile_g000002.json"), future)
	check(not repo.load_profile() and repo.read_only and not repo.commit({"id":"downgrade"}).ok, "future schema prevents downgrade writes")
	var nested = fresh("nested_file")
	var invalid = nested.defaults()
	invalid.wallet = {"parts":[]}
	invalid.generation = 1
	write_envelope(nested, nested.root_path.path_join("profile_g000001.json"), invalid)
	check(not nested.load_profile(), "valid hash does not bypass nested schema validation")

func test_fault_boundaries() -> void:
	for point in ["before_write", "after_write", "after_validate", "after_generation", "before_manifest", "after_manifest_write", "after_manifest"]:
		var repo = fresh("fault_" + point)
		repo.commit({"id":"base", "parts_delta":10})
		var before = repo.data.duplicate(true)
		var tx = {"id":"reward", "parts_delta":40, "append":{"campaign.completed_stages":["M01_stage_1"]}}
		repo.failure_point = point
		check(not repo.commit(tx).ok and repo.data == before, point + " keeps live state unchanged")
		var reload = Repository.new(repo.root_path)
		var published = point in ["after_generation", "before_manifest", "after_manifest_write", "after_manifest"]
		check(reload.load_profile() and reload.data.wallet.parts == (50 if published else 10), point + " restart recovers a complete generation")
		repo.failure_point = ""
		check(repo.commit(tx).ok and repo.data.wallet.parts == 50 and repo.data.ledger.receipts.count("reward") == 1, point + " retry awards exactly once")
		check(repo.commit(tx).duplicate, point + " retried receipt remains idempotent")
	var unavailable = fresh("unavailable")
	write_json(unavailable.root_path, {"file_blocks_directory":true})
	check(not unavailable.commit({"id":"blocked", "parts_delta":9}).ok and unavailable.data.wallet.parts == 0, "filesystem directory failure preserves wallet")

func test_migration() -> void:
	var repo = fresh("migration")
	var source = sandbox.path_join("v1_source/pilot.json")
	var old = {"version":1, "parts":321, "unlocked":["pulse", "stable", "shield", "charge", "agile", "cooler", "unknown_item"], "loadout":{"weapon":"charge", "drive":"agile", "utility":"cooler"}, "completed":[0,1,2], "records":{"old":{"time":20}}, "facility":["workshop", "terminal"], "settings":{"difficulty":2, "volume":0.7, "auto_fire":true, "input":{"center":{"0":{}}, "axis_x":2}}, "custom_old_field":"keep me"}
	write_json(source, old)
	write_json(source + ".bak", old)
	var original_hash = FileAccess.get_sha256(source)
	var initialized = fresh("migration_after_application_init")
	check(initialized.commit({"id":"profile:init","set":{"settings.auto_fire":true}}).ok,"application creates default settings receipt")
	check(initialized.migrate_v1(source).ok and initialized.data.wallet.parts == 321,"fresh application initialization does not block explicit V1 migration")
	var changed = fresh("migration_after_user_transaction")
	changed.commit({"id":"profile:init","set":{"settings.auto_fire":true}})
	changed.commit({"id":"setting:changed","set":{"settings.volume":0.5}})
	check(not changed.migrate_v1(source).ok,"migration still refuses a profile with subsequent user transactions")
	var migration = repo.migrate_v1(source)
	check(migration.ok, "V1 migrates successfully: " + str(migration.error))
	for index in range(10):
		var result = repo.migrate_v1(source)
		if not result.ok or not result.duplicate:failures.append("migration duplicate " + str(index))
	check(repo.data.wallet.parts == 321 and repo.data.ledger.receipts.size() == 1, "ten migration retries do not duplicate currency")
	check(FileAccess.get_sha256(source) == original_hash and FileAccess.get_sha256(repo.root_path.path_join("migration_backups/v1_" + original_hash + "/pilot.json")) == original_hash, "original and private backup bytes match")
	check(repo.data.owned_modules.has("burst_capacitor") and repo.data.owned_modules.has("racing_drive") and repo.data.owned_modules.has("cooling_duct"), "old purchased modules inherited for free")
	check(repo.data.campaign.completed_missions.is_empty() and repo.data.legacy_v1.completed.size() == 3, "legacy campaign history does not bypass V2 missions")
	check(repo.data.legacy_v1.unmapped.size() == 2 and repo.data.settings.input.center.is_empty(), "unknown data preserved and malformed calibration sanitized")
	var backup_source = sandbox.path_join("v1_missing/pilot.json")
	write_json(backup_source + ".bak", old)
	var backup_repo = fresh("migration_backup")
	check(backup_repo.migrate_v1(backup_source).ok and backup_repo.data.wallet.parts == 321, "V1 missing primary migrates from backup")
	var corrupt_source = sandbox.path_join("v1_corrupt/pilot.json")
	write_json(corrupt_source, "broken primary")
	write_json(corrupt_source + ".bak", old)
	var corrupt_repo = fresh("migration_corrupt")
	check(corrupt_repo.migrate_v1(corrupt_source).ok and corrupt_repo.data.wallet.parts == 321, "V1 corrupt primary migrates from verified backup")
	var wrong_type_source = sandbox.path_join("v1_wrong_type/pilot.json")
	write_json(wrong_type_source, {"version":1, "parts":[]})
	write_json(wrong_type_source + ".bak", old)
	var wrong_type_repo = fresh("migration_wrong_type")
	check(wrong_type_repo.migrate_v1(wrong_type_source).ok and wrong_type_repo.data.wallet.parts == 321, "V1 invalid primary schema migrates from verified backup")
	var bad_source = sandbox.path_join("v1_invalid/pilot.json")
	write_json(bad_source, {"version":1,"parts":-8})
	var bad_repo = fresh("migration_invalid")
	check(not bad_repo.migrate_v1(bad_source).ok and bad_repo.data.wallet.parts == 0, "invalid V1 balance never silently resets progress")
