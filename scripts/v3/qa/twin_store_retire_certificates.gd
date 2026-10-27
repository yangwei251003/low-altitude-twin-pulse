extends SceneTree
# Explicit private Store fixtures; no Main/gameplay/profile cloning or performance claim.
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
class Derived:
	extends "res://scripts/v3/core/twin_world_store.gd"
	var validations := 0
	var reads := 0
	func _init(path: String) -> void: super(path)
	func _validate(value: Dictionary) -> bool:
		validations += 1
		return super._validate(value)
	func _read_generation(path: String) -> Dictionary:
		reads += 1
		return super._read_generation(path)

var qa_root := ""
var evidence := ""
var checks: Array[Dictionary] = []
var done := false

func _init() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-root="): qa_root = arg.trim_prefix("--qa-root=")
		if arg.begins_with("--qa-evidence="): evidence = arg.trim_prefix("--qa-evidence=")
	_run.call_deferred()

func _check(ok: bool, name: String, detail: Dictionary = {}) -> void:
	checks.append({"name":name,"ok":ok,"detail":detail})

func _json(path: String, value: Dictionary) -> bool:
	var temporary := path+".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(value)); file.close()
	return DirAccess.rename_absolute(temporary,path) == OK

func _finish() -> void:
	if done: return
	done = true
	var passed := not checks.is_empty()
	for item: Dictionary in checks: passed = passed and item.ok
	var written := _json(evidence.path_join("result.json"), {"schema":1,"passed":passed,"checks":checks,
		"scope":"Source Store fixtures, real file IO; not gameplay, EXE or normal performance evidence"})
	print("RETIRE_CERT_PROBE ", "PASS" if passed and written else "FAIL", " checks=", checks.size())
	quit(0 if passed and written else 1)

func _watchdog() -> void:
	if not done:
		_check(false,"native_watchdog_18s")
		_finish()

func _seed(store, count: int) -> bool:
	store.qa_phase_enabled = true
	for index in range(count):
		var result: Dictionary = store.commit({"id":"fixture_%d" % index,"set":{"world.choices.qa_tick":index}})
		if not result.ok: return false
	return true

func _observe(store, path: String, normal: bool = false) -> Dictionary:
	# Real diagnostic clock and file APIs. Only phase context is an explicit QA fixture.
	store._qa_begin_phases()
	if not normal: store._qa_phase_mark("retire")
	var valid: bool
	var generation := -1
	if normal:
		var payload: Dictionary = store._read_generation(path)
		valid = not payload.is_empty() and not payload.get("future",false)
		if valid: generation = int(payload.generation)
	else: valid = store._retirement_generation_valid(path)
	store._qa_phase_mark("")
	store.qa_last_phases.total_usec = Time.get_ticks_usec()-int(store.qa_last_phases.start_usec)
	store.qa_last_phases.complete = true
	store._qa_cost_active = false; store._qa_read_group = ""; store._qa_read_stage = ""
	var group := "ready" if normal else "retire"
	return {"valid":valid,"generation":generation,"stats":store.qa_last_phases.read_groups[group].duplicate(true),
		"cert_count":store._retire_certificates.size()}

func _counts(observed: Dictionary, valid: bool, json_count: int, validate_count: int) -> bool:
	return observed.valid == valid and observed.stats.calls == 1 and observed.stats.read_count == 1 \
		and observed.stats.json_sha_count == json_count and observed.stats.validate_count == validate_count

func _has_path(store, path: String) -> bool:
	for certificate: Dictionary in store._retire_certificates:
		if certificate.path == path: return true
	return false

func _has_text(store, text: String) -> bool:
	for certificate: Dictionary in store._retire_certificates:
		if certificate.text == text: return true
	return false

func _bounded(store) -> bool:
	if store._retire_certificates.size() > Store.RETIRE_CERT_LIMIT: return false
	var chars := 0
	for certificate: Dictionary in store._retire_certificates:
		if certificate.keys().size() != 2 or not certificate.path is String or not certificate.text is String: return false
		if certificate.text.length() > Store.RETIRE_CERT_MAX_CHARS: return false
		chars += certificate.text.length()
	return chars <= Store.RETIRE_CERT_LIMIT * Store.RETIRE_CERT_MAX_CHARS

func _wrap(payload: Dictionary) -> String:
	var serialized := JSON.stringify(payload,"",true,true)
	return JSON.stringify({"format":1,"schema_version":Store.SCHEMA_VERSION,
		"payload_json":serialized,"payload_sha256":serialized.sha256_text()},"",true,true)

func _wait_for(name: String) -> bool:
	var until := Time.get_ticks_msec()+3000
	while Time.get_ticks_msec() < until and not FileAccess.file_exists(evidence.path_join(name)):
		await process_frame
	return FileAccess.file_exists(evidence.path_join(name))

func _run() -> void:
	if not qa_root.begins_with("user://qa_v3_retire_cert85_") or qa_root.contains("..") or qa_root.contains("\\") \
		or qa_root.trim_prefix("user://").contains("/") or not evidence.is_absolute_path() or evidence.contains(".."):
		push_error("Private QA root/evidence required"); quit(1); return
	if DirAccess.dir_exists_absolute(qa_root):
		push_error("Private QA root already exists; refusing reuse"); quit(1); return
	create_timer(18.0).timeout.connect(_watchdog)
	var store = Store.new(qa_root.path_join("basic"))
	if not _seed(store,4):
		_check(false,"four_real_commits"); _finish(); return
	var stats: Dictionary = store.qa_last_phases.read_groups.retire.duplicate(true)
	var ready: Dictionary = store.qa_last_phases.read_groups.ready.duplicate(true)
	var tmp: Dictionary = store.qa_last_phases.read_groups.tmp.duplicate(true)
	_check(ready.calls==1 and ready.read_count==1 and ready.json_sha_count==1 and ready.validate_count==1 \
		and tmp.calls==1 and tmp.read_count==1 and tmp.json_sha_count==1 and tmp.validate_count==1,
		"real_commit_ready_and_tmp_keep_full_validation",{"ready":ready,"tmp":tmp})
	var old_path: String = store.root_path.path_join("profile_g000000000001.json")
	_check(store._generation_files().size()==3 and not FileAccess.file_exists(old_path) and not _has_path(store,old_path),
		"three_legal_generations_and_deleted_certificate_cleared")
	_check(stats.calls==4 and stats.read_count==4 and stats.json_sha_count==0 and stats.validate_count==0,
		"warm_fourth_commit_retire_reads_all_files_skips_only_revalidation",stats)
	var path: String = store.root_path.path_join(store._generation_files()[0])
	var good := FileAccess.get_file_as_string(path)
	var observed := _observe(store,path)
	_check(_counts(observed,true,0,0),"identical_fresh_read_hits_certificate",observed)
	observed = _observe(store,path,true)
	_check(_counts(observed,true,1,1) and observed.generation==4,"ordinary_reader_still_returns_full_validated_payload",observed)
	var changed := good+"\n" # One actual character, still valid JSON; no content-hash shortcut.
	_check(store._write_text(path,changed),"write_single_character_fixture")
	observed = _observe(store,path)
	_check(_counts(observed,true,1,1),"single_character_change_misses_and_fully_revalidates",observed)
	observed = _observe(store,path)
	_check(_counts(observed,true,0,0),"newly_validated_text_can_hit",observed)
	var envelope: Dictionary = JSON.parse_string(good)
	envelope.payload_sha256 = "0".repeat(64)
	var bad_sha := JSON.stringify(envelope)
	_check(store._write_text(path,bad_sha),"write_corrupt_sha_fixture")
	observed = _observe(store,path)
	_check(_counts(observed,false,1,0) and not _has_text(store,bad_sha),"corruption_is_freshly_read_rejected_not_cached",observed)
	envelope = JSON.parse_string(good); envelope.schema_version = Store.SCHEMA_VERSION+1
	var future := JSON.stringify(envelope)
	_check(store._write_text(path,future),"write_future_envelope_fixture")
	observed = _observe(store,path)
	_check(_counts(observed,false,1,0) and not _has_text(store,future),"future_envelope_rejected_not_cached",observed)
	var payload: Dictionary = JSON.parse_string(JSON.parse_string(good).payload_json)
	payload.schema_version = Store.SCHEMA_VERSION+1
	var future_payload := _wrap(payload)
	_check(store._write_text(path,future_payload),"write_future_payload_fixture")
	observed = _observe(store,path)
	_check(_counts(observed,false,1,0) and not _has_text(store,future_payload),"future_payload_rejected_not_cached",observed)
	payload = JSON.parse_string(JSON.parse_string(good).payload_json)
	payload.world.branch_id = "missing_branch"
	var invalid := _wrap(payload)
	_check(store._write_text(path,invalid),"write_schema_invalid_fixture")
	observed = _observe(store,path)
	_check(_counts(observed,false,1,1) and not _has_text(store,invalid),"valid_sha_invalid_state_rejected_not_cached",observed)
	var long_text := good+" ".repeat(Store.RETIRE_CERT_MAX_CHARS)
	_check(store._write_text(path,long_text),"write_over_certificate_limit_below_file_limit_fixture")
	observed = _observe(store,path)
	_check(_counts(observed,true,1,1) and not _has_text(store,long_text),"long_text_remains_full_validation_only",observed)
	long_text = ""
	_check(store._write_text(path,good),"restore_fixture_file")
	_observe(store,path,true)
	# Invalid/future files must never consume the three legal-generation slots.
	var bad_path: String = store.root_path.path_join("profile_g000000000999.json")
	var future_path: String = store.root_path.path_join("profile_g000000001000.json")
	_check(store._write_text(bad_path,bad_sha) and store._write_text(future_path,future),"write_uncounted_invalid_future_files")
	store._retire_generations()
	var retained := FileAccess.file_exists(bad_path) and FileAccess.file_exists(future_path)
	for ordinal in [2,3,4]: retained = retained and FileAccess.file_exists(store.root_path.path_join("profile_g%012d.json" % ordinal))
	_check(retained and store._generation_files().size()==5,"bad_and_future_do_not_count_or_get_deleted")
	var reader = Store.new(store.root_path)
	var loaded: Dictionary = reader.load_profile()
	_check(not loaded.ok and loaded.error=="SAVE_SCHEMA_NEWER" and reader.read_only,"normal_load_retains_future_schema_gate")
	_check(_bounded(store),"certificate_shape_and_character_caps")
	var derived = Derived.new(qa_root.path_join("derived"))
	if _seed(derived,1):
		derived.validations = 0; derived.reads = 0
		var derived_path: String = derived.root_path.path_join(derived._generation_files()[0])
		observed = _observe(derived,derived_path)
		_check(_counts(observed,true,1,1) and derived.validations==1 and derived.reads==1 \
			and derived._retire_certificates.is_empty(),"derived_script_retains_original_overridable_reader_and_validation",observed)
	else: _check(false,"derived_fixture_commit")
	var locked = Store.new(qa_root.path_join("locked"))
	if not _seed(locked,3):
		_check(false,"locked_fixture_seed"); _finish(); return
	var locked_old: String = locked.root_path.path_join("profile_g000000000001.json")
	_check(_json(evidence.path_join("lock-request.json"),{"path":ProjectSettings.globalize_path(locked_old),"qa_root":qa_root}),"request_real_windows_delete_lock")
	if not await _wait_for("lock-ack.json"):
		_check(false,"windows_lock_ack"); _finish(); return
	var result: Dictionary = locked.commit({"id":"while_locked","set":{"world.choices.qa_tick":4}})
	_check(result.ok and locked.notice=="SAVE_BACKUP_CLEANUP_DEFERRED" and locked._generation_files().size()==4 \
		and FileAccess.file_exists(locked_old) and _has_path(locked,locked_old),"real_delete_failure_keeps_publish_and_notice_and_certificate",{"notice":locked.notice,"generation":result.generation})
	_json(evidence.path_join("release-request.json"),{"ready":true})
	if not await _wait_for("release-ack.json"):
		_check(false,"windows_release_ack"); _finish(); return
	result = locked.commit({"id":"after_unlock","set":{"world.choices.qa_tick":5}})
	_check(result.ok and locked.notice.is_empty() and locked._generation_files().size()==3 \
		and not FileAccess.file_exists(locked_old) and not _has_path(locked,locked_old) and _bounded(locked),
		"cleanup_after_real_unlock_keeps_three_and_clears_deleted_certificate")
	var final_reader = Store.new(locked.root_path)
	loaded = final_reader.load_profile()
	_check(loaded.ok and final_reader.snapshot()==locked.snapshot(),"independent_final_reader_matches_committed_state")
	_finish()
