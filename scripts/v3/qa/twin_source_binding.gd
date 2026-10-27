extends RefCounted
## Read-only source evidence for explicit normal QA. No Store writes or gameplay.
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const Transport = preload("res://scripts/v3/twin_network.gd")
const LIMIT_BINDING := 16384
const LIMIT_REPORT := 8 * 1024 * 1024
const LIMIT_INPUTS := 1024 * 1024
const SPECS := {
	"normal-f1": [9,17,"first_segment_complete","SOURCE_RECEIPTS_SHA256"],
	"normal-whale": [17,19,"f1_segment_complete","SEVENTEEN_DIGEST"],
	"normal-crown": [19,23,"whale_segment_complete","NINETEEN_DIGEST"],
	"normal-underdeck": [23,27,"crown_segment_complete","TWENTYTHREE_DIGEST"],
	"normal-clinic": [27,31,"underdeck_segment_complete","TWENTYSEVEN_DIGEST"],
	"normal-distribution": [31,34,"clinic_segment_complete","THIRTYONE_DIGEST"],
	"normal-canal": [34,38,"distribution_segment_complete","THIRTYFOUR_DIGEST"],
	"normal-i2-boss": [38,42,"canal_segment_complete","THIRTYEIGHT_DIGEST"],
	"normal-f2": [42,46,"i2_boss_segment_complete","FORTYTWO_DIGEST"],
	"normal-f2-boss": [46,50,"f2_segment_complete","FORTYSIX_DIGEST"],
	"normal-i3:tasks": [50,58,"f2_boss_segment_complete","FIFTY_DIGEST"],
	"normal-i3:boss": [54,58,"i3_segment_complete","FIFTYFOUR_DIGEST"],
	"normal-f3": [58,66,"i3_segment_complete","FIFTYEIGHT_DIGEST"],
	"normal-i4": [66,75,"f3_segment_complete","SIXTYSIX_DIGEST"],
	"normal-f4": [75,84,"i4_segment_complete","SEVENTYFIVE_DIGEST"]}

const PREFIX_COUNTS := {"SOURCE_RECEIPTS_SHA256": 9, "FIRST_NINE_DIGEST": 9, "SEVENTEEN_DIGEST": 17, "NINETEEN_DIGEST": 19, "TWENTYTHREE_DIGEST": 23, "TWENTYSEVEN_DIGEST": 27, "THIRTYONE_DIGEST": 31}

static func prepare(args: PackedStringArray, entry: String, source_goals: Array, expected: Array) -> Dictionary:
	var clean := PackedStringArray()
	var binding_path := ""
	var binding_sha := ""
	var segment := ""
	var profile_arg := ""
	for arg: String in args:
		if arg.begins_with("--qa-source-binding="):
			if not binding_path.is_empty(): return _fail("duplicate_path")
			binding_path = arg.trim_prefix("--qa-source-binding=")
		elif arg.begins_with("--qa-source-binding-sha256="):
			if not binding_sha.is_empty(): return _fail("duplicate_sha")
			binding_sha = arg.trim_prefix("--qa-source-binding-sha256=")
		else:
			clean.append(arg)
			if arg.begins_with("--qa-profile="):
				if not profile_arg.is_empty(): return _fail("duplicate_profile")
				profile_arg = arg.trim_prefix("--qa-profile=")
			if arg.begins_with("--qa-i3-segment="):
				if not segment.is_empty(): return _fail("duplicate_segment")
				segment = arg.trim_prefix("--qa-i3-segment=")
	if binding_path.is_empty() or not _hex(binding_sha,64): return _fail("explicit_path_and_sha_required")
	if entry != "normal-i3" and not segment.is_empty(): return _fail("unexpected_segment")
	if entry == "normal-i3" and segment not in ["tasks","boss"]: return _fail("explicit_i3_segment_required")
	var key := entry + (":" + segment if entry == "normal-i3" else "")
	if not SPECS.has(key): return _fail("unknown_entry")
	var spec: Array = SPECS[key]
	var selected: Array = expected.slice(0,54) if key == "normal-i3:boss" else source_goals
	if selected.size() != int(spec[0]) or expected.size() != int(spec[1]) or selected != expected.slice(0,selected.size()): return _fail("compiled_goal_contract")
	if entry == "normal-i3" and (source_goals.size()!=50 or source_goals!=expected.slice(0,50)): return _fail("compiled_i3_base50")
	var roots := _roots()
	if roots.is_empty(): return _fail("managed_owner_unavailable")
	var loaded := _small_json(binding_path,binding_sha,LIMIT_BINDING,roots,true)
	if not loaded.ok: return loaded
	var value: Dictionary = loaded.value
	if not _keys(value,["version","entry","segment","profile","start_generation","sources","goal_contract_sha256","target"]): return _fail("schema_keys")
	if not _number(value.version,1) or value.entry!=entry or value.segment!=segment or not _positive(value.start_generation): return _fail("schema_entry_generation")
	if not _keys(value.profile,["name","id","lineage"]) or not value.profile.name is String or not str(value.profile.name).begins_with("qa_") or str(value.profile.name).length()>120 or value.profile.name!=str(value.profile.name).validate_filename() or value.profile.name!=profile_arg or not _hex(value.profile.id,32) or not _hex(value.profile.lineage,32): return _fail("profile_identity")
	if not _keys(value.target,["exe_path","exe_sha256","app_version","protocol"]) or not value.target.exe_path is String or not _hex(value.target.exe_sha256,64) or not value.target.app_version is String or not _number(value.target.protocol,Transport.PROTOCOL): return _fail("target_schema_protocol")
	if _norm(value.target.exe_path)!=_norm(OS.get_executable_path()) or value.target.app_version!=str(ProjectSettings.get_setting("application/config/version","")): return _fail("target_exe_path_or_version")
	# The CLI verifies the target EXE through dev.file_sha256; never hash it here.
	value.version = int(value.version)
	value.start_generation = int(value.start_generation)
	value.target.protocol = int(value.target.protocol)
	if JSON.stringify(value,"",true,true) != str(loaded.text).strip_edges(): return _fail("canonical_json_required_no_duplicate_keys")
	var contract := JSON.stringify([entry,segment,selected,expected],"",true,true).sha256_text()
	if value.goal_contract_sha256 != contract: return _fail("fixed_goal_contract_sha")
	var roles: Array = ["primary","base50"] if key=="normal-i3:boss" else ["primary"]
	if not _keys(value.sources,roles): return _fail("source_roles")
	var primary := _source(value.sources.primary,selected,str(spec[2]),value.profile,roots,value.target)
	if not primary.ok: return primary
	if key=="normal-i3:boss" and primary.report.get("segment")!="tasks": return _fail("i3_primary_must_be_tasks54")
	if entry=="normal-f3" and primary.report.get("segment")!="boss": return _fail("f3_primary_must_be_boss58")
	var constants: Dictionary = {"SOURCE_PROFILE":value.profile.name,"SOURCE_REPORT":value.sources.primary.report_path,"SOURCE_REPORT_SHA256":value.sources.primary.report_sha256}
	constants[str(spec[3])] = value.sources.primary.receipts_sha256
	for name: String in PREFIX_COUNTS:
		var count: int = PREFIX_COUNTS[name]
		if count <= selected.size(): constants[name] = JSON.stringify(_receipt_rows(primary.report.story_receipts,selected.slice(0,count)),"",true,true).sha256_text()
	if key=="normal-i3:boss":
		var base := _source(value.sources.base50,source_goals,"f2_boss_segment_complete",value.profile,roots,value.target)
		if not base.ok: return base
		var prefix := _receipt_rows(primary.report.story_receipts,source_goals)
		if prefix != base.report.story_receipts or primary.report.get("source_report_sha256")!=value.sources.base50.report_sha256 or primary.report.get("source_receipts_sha256")!=value.sources.base50.receipts_sha256: return _fail("i3_independent_base50_chain")
		constants.SOURCE_REPORT = value.sources.base50.report_path
		constants.SOURCE_REPORT_SHA256 = value.sources.base50.report_sha256
		constants.FIFTY_DIGEST = value.sources.base50.receipts_sha256
		constants.SOURCE54_REPORT = value.sources.primary.report_path
		constants.SOURCE54_REPORT_SHA256 = value.sources.primary.report_sha256
	var context: Dictionary = {"binding_path":binding_path,"binding_sha256":binding_sha,"entry":entry,"segment":segment,"profile":value.profile.duplicate(true),"start_generation":value.start_generation,"goal_contract_sha256":contract,"target":value.target.duplicate(true),"constants":constants}
	# Original loader reads only; the original Node still validates all business.
	var store_path := "user://profiles_v3/" + str(value.profile.name)
	if not DirAccess.dir_exists_absolute(store_path): return _fail("existing_profile_required")
	var reader = Store.new(store_path)
	var original: Dictionary = reader.load_profile()
	if not _yes(original.get("ok")) or not _no(original.get("recovered")): return _fail("original_profile_load")
	if not start_matches(context,reader.snapshot()): return _fail("initial_identity_or_generation")
	return {"ok":true,"code":"verified_read_only_source_binding","args":clean,"binding":context}

static func same_identity(context: Dictionary, saved: Dictionary) -> bool:
	return not context.is_empty() and saved.get("profile_id")==context.profile.id and saved.get("lineage_id")==context.profile.lineage

static func start_matches(context: Dictionary, saved: Dictionary) -> bool:
	return same_identity(context,saved) and _number(saved.get("generation"),int(context.start_generation)) and FileAccess.get_sha256(str(context.binding_path))==str(context.binding_sha256)

static func audit(context: Dictionary) -> Dictionary:
	return {"source_binding_path":context.binding_path,"source_binding_sha256":context.binding_sha256,"source_goal_contract_sha256":context.goal_contract_sha256,"source_profile_id":context.profile.id,"source_lineage_id":context.profile.lineage,"source_binding_target_exe_sha256":context.target.exe_sha256,"source_binding_target_sha256_verification":"cli_inputs_required"}

static func _source(row: Variant, goals: Array, success: String, identity: Dictionary, roots: Dictionary, target: Dictionary) -> Dictionary:
	if not _keys(row,["report_path","report_sha256","inputs_path","inputs_sha256","receipts_sha256"]): return _fail("source_schema")
	if not row.report_path is String or not row.inputs_path is String or not _hex(row.report_sha256,64) or not _hex(row.inputs_sha256,64) or not _hex(row.receipts_sha256,64): return _fail("source_types")
	if _norm(str(row.inputs_path).get_base_dir())!=_norm(str(row.report_path).get_base_dir()) or str(row.inputs_path).get_file()!="inputs.json": return _fail("source_inputs_pair")
	var rr := _small_json(row.report_path,row.report_sha256,LIMIT_REPORT,roots,false)
	if not rr.ok: return rr
	var ii := _small_json(row.inputs_path,row.inputs_sha256,LIMIT_INPUTS,roots,false)
	if not ii.ok: return ii
	var r: Dictionary = rr.value
	var terminal := "record" if success in ["whale_segment_complete","crown_segment_complete"] else "complete"
	if r.get("requested_stage")!=terminal or not _yes(r.get("exported_application")): return _fail("source_terminal_exported_main")
	var i: Dictionary = ii.value
	if not _yes(r.get("complete")) or not _yes(r.get(success)) or not _no(r.get("requested_stage_stopped")) or r.get("profile")!=identity.name or not _empty_array(r.get("failures")) or not _empty_array(r.get("engine_errors")): return _fail("source_not_complete")
	if not r.get("status") is Dictionary or r.status.get("completed")!=goals or not r.get("story_receipts") is Dictionary or r.story_receipts.size()!=goals.size(): return _fail("source_exact_goals_receipts")
	var rows := _receipt_rows(r.story_receipts,goals)
	if rows.size()!=goals.size() or JSON.stringify(rows,"",true,true).sha256_text()!=row.receipts_sha256: return _fail("source_actual_receipts_sha")
	var native: Variant = r.get("native_exit")
	var preserve: Variant = r.get("preservation")
	if not native is Dictionary or native.get("through")!="session._quit" or not _yes(native.get("requested")) or not _yes(native.get("observed_scene_exit")) or not _no(native.get("watchdog_failed")) or not native.get("audio") is Dictionary: return _fail("source_original_exit")
	var audio: Dictionary = native.audio
	if not _yes(audio.get("ready")) or not _number(audio.get("pending_references"),0) or not _empty_array(audio.get("pending")): return _fail("source_audio_drain")
	if not preserve is Dictionary or not _yes(preserve.get("original_prefix_preserved")) or not _yes(preserve.get("current_SaveGate_completed")) or not _yes(preserve.get("fresh_Story_matches_live")): return _fail("source_original_savegate")
	var fresh: Variant = r.get("fresh_reader")
	if not fresh is Dictionary or fresh.get("profile_id")!=identity.id or fresh.get("lineage_id")!=identity.lineage: return _fail("source_original_identity")
	var process: Variant = i.get("process")
	if not process is Dictionary or not _yes(process.get("passed")) or not _number(process.get("returncode"),0) or not _no(process.get("timed_out")) or not _no(process.get("orphan_cleanup")) or not _number(process.get("remaining_owned_processes"),0): return _fail("source_natural_process")
	if not i.has("execution_failure") or i.execution_failure!=null or not _yes(i.get("unchanged")) or not i.get("before") is Dictionary or i.before.is_empty() or i.before!=i.get("after") or not _hex(i.get("artifact_sha256"),64): return _fail("source_stable_inputs")
	var artifact_matched := false
	for path: Variant in i.before:
		if path is String and _norm(path)==_norm(str(r.get("executable",""))) and i.before[path]==i.artifact_sha256: artifact_matched = true
	if not artifact_matched or i.artifact_sha256!=target.exe_sha256 or _norm(str(r.get("executable","")))!=_norm(str(target.exe_path)): return _fail("source_artifact_identity")
	return {"ok":true,"report":r}

static func _receipt_rows(receipts: Dictionary, goals: Array) -> Dictionary:
	var rows: Dictionary = {}
	for key: Variant in receipts:
		if not key is String or not receipts[key] is Dictionary: return {}
		if receipts[key].get("objective_id") in goals: rows[key] = receipts[key].duplicate(true)
	return rows

static func _small_json(path: String, sha: String, limit: int, roots: Dictionary, binding: bool) -> Dictionary:
	if not _approved(path,roots,binding) or not _hex(sha,64): return _fail("approved_small_json_path")
	var file := FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()<=0 or file.get_length()>limit: return _fail("small_json_size")
	if FileAccess.get_sha256(path)!=sha: return _fail("small_json_sha")
	var text := file.get_as_text()
	if file.get_error()!=OK and file.get_error()!=ERR_FILE_EOF: return _fail("small_json_read")
	if FileAccess.get_sha256(path)!=sha: return _fail("small_json_changed")
	var parser := JSON.new()
	if parser.parse(text)!=OK or not parser.data is Dictionary: return _fail("small_json_schema")
	return {"ok":true,"value":parser.data,"text":text}

static func _roots() -> Dictionary:
	# CLI forwards the resolved managed root to this child only (MSIX-safe).
	var override := OS.get_environment("LOW_ALTITUDE_DEV_HOME")
	var candidates: Array[String] = []
	if not override.is_empty(): candidates.append(override)
	candidates.append(OS.get_environment("LOCALAPPDATA").path_join("LowAltitudeTwinPulseDev"))
	for managed: String in candidates:
		if not managed.is_absolute_path() or "://" in managed or ".." in managed: continue
		var owner_path := managed.path_join("owner.json")
		var file := FileAccess.open(owner_path,FileAccess.READ)
		if file==null or file.get_length()<=0 or file.get_length()>16384: continue
		var owner: Variant = JSON.parse_string(file.get_as_text())
		if not owner is Dictionary or owner.get("kind")!="LowAltitudeTwinPulseDev" or not _hex(owner.get("owner"),32) or not owner.get("home") is String or not owner.get("project") is String or str(owner.home).replace("\\","/").get_file()!="LowAltitudeTwinPulseDev": continue
		if managed==override and _norm(str(owner.home))!=_norm(managed): continue
		var canonical_owner := str(owner.home).path_join("owner.json")
		if not FileAccess.file_exists(canonical_owner) or FileAccess.get_sha256(canonical_owner)!=FileAccess.get_sha256(owner_path): continue
		return {"evidence":[managed.path_join("evidence"),str(owner.home).path_join("evidence"),str(owner.project).path_join("artifacts/v3")],"binding":[managed.path_join("evidence"),str(owner.home).path_join("evidence"),managed.path_join("authoring"),str(owner.home).path_join("authoring")]}
	return {}

static func _approved(path: String, roots: Dictionary, binding: bool) -> bool:
	if path.length()>4096 or not path.is_absolute_path() or "://" in path or ".." in path or "\n" in path or "\r" in path: return false
	var normalized := _norm(path)
	for prefix: String in roots["binding" if binding else "evidence"]:
		if normalized.begins_with(_norm(prefix).trim_suffix("/")+"/"): return true
	return false

static func _norm(path: String) -> String:
	return path.replace("\\","/").simplify_path().to_lower()

static func _keys(value: Variant, keys: Array) -> bool:
	if not value is Dictionary or value.size()!=keys.size(): return false
	for key: Variant in value:
		if not key is String or key not in keys: return false
	return true

static func _hex(value: Variant, count: int) -> bool:
	if not value is String or value.length()!=count: return false
	for c: String in value:
		if c not in "0123456789abcdef": return false
	return true

static func _yes(value: Variant) -> bool:
	return value is bool and value

static func _no(value: Variant) -> bool:
	return value is bool and not value

static func _number(value: Variant, expected: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)==float(expected)

static func _positive(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>0 and float(value)<=9007199254740991.0 and floor(float(value))==float(value)

static func _empty_array(value: Variant) -> bool:
	return value is Array and value.is_empty()

static func _fail(code: String) -> Dictionary:
	return {"ok":false,"code":"source_binding_"+code}


static func completion_audit(session, initial: Dictionary, fresh: Dictionary, callbacks: Array, expected: Array) -> Dictionary:
	var world: Dictionary = fresh.get("world",{})
	var story: Dictionary = world.get("actions",{}).get("opening",{})
	var previous: Dictionary = initial.get("world",{}).get("actions",{}).get("opening",{})
	var goals: Array = previous.get("completed",[])
	var load: Dictionary = fresh.get("loaded",{})
	var preserved: bool = _yes(load.get("ok")) and not load.get("recovered",false) and fresh.get("profile_id")==initial.get("profile_id") and fresh.get("lineage_id")==initial.get("lineage_id") and world.get("branch_id")=="main" and story.get("completed")==expected and world.get("completed_objectives")==expected and fresh.get("prefix_validation",{}).get("ok",false) and _receipt_rows(story.get("receipts",{}),goals)==previous.get("receipts",{})
	return {"requested_stage":"complete","requested_stage_stopped":false,"preservation":{"original_prefix_preserved":preserved,"current_SaveGate_completed":not callbacks.is_empty() and callbacks[-1].get("ok",false) and callbacks[-1].get("completed",false),"fresh_Story_matches_live":preserved and session.store.matches_persisted_value(session.story.state,story)}}
