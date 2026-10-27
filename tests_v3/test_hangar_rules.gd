extends SceneTree
## Isolated rules + original Store contract. Discovery strings below are explicit
## QA receipt fixtures, not a normally played campaign or earned reward claim.
## No MAIN, natural QA profile, UI, LAN, flight, battery or weapon-damage evidence.
const Hangar = preload("res://scripts/v3/gameplay/twin_hangar.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const Flight = preload("res://scripts/v2/flight_body.gd")
var checks: Array = []
var output := ""
var qa_root := ""
var finished := false
var body: FlightBodyV2

class ErrorLogger extends Logger:
	var errors: Array = []
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _notify: bool, kind: int, _traces: Array[ScriptBacktrace]) -> void:
		errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale,"type":kind})

var logger := ErrorLogger.new()

func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	if not output.begins_with("res://artifacts/v3/hangar-rules-") or ".." in output or DirAccess.dir_exists_absolute(output):
		quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	qa_root = "user://qa_v3/hangar_rules_"+Crypto.new().generate_random_bytes(12).hex_encode()
	if not _check(not DirAccess.dir_exists_absolute(qa_root),"unique empty QA Store path, never a natural profile",qa_root):
		_finish(); return
	create_timer(12.0).timeout.connect(func() -> void:
		if not finished:
			_check(false,"bounded hangar rules/Store check")
			_finish())
	var store := Store.new(qa_root)
	if not _check(store.load_profile().get("ok",false) and store.commit({"id":"qa-hangar-bootstrap"}).get("ok",false),"original new Store loads and commits"):
		_finish(); return
	var initial: Dictionary = store.snapshot()
	var owned: Dictionary = Hangar.ownership(initial)
	if not _check(owned.get("ok",false),"new original Store envelope is accepted by ownership rules",owned):
		_finish(); return
	var starters: Array = owned.get("modules",[]).duplicate()
	starters.sort()
	var expected: Array = ["pulse_base","scan_base","guard_base","stock_drive","stock_battery"]
	expected.sort()
	_check(owned.get("ok",false) and starters == expected and owned.frames == Hangar.FRAME_ORDER,"only five actual default modules are starter-owned",owned)
	_check(owned.unlocks.size() == 12 and owned.unlocks.all(func(row: Dictionary) -> bool: return not row.owned),"all twelve extra modules initially locked")
	for frame: String in Hangar.FRAME_ORDER:
		var starter: Dictionary = Hangar.launch_build(initial,frame)
		_check(starter.get("ok",false) and starter.resolved.valid and starter.build.airframe_id == frame,"starter default remains original Catalog legal: "+frame,starter.get("errors",[]))
	var draft: Dictionary = Catalog.default_build("tr01")
	draft.slots.drive = "racing_drive"
	var denied: Dictionary = Hangar.validate(initial,draft)
	_check(not denied.ok and _has_error(denied,"BUILD_MODULE_NOT_OWNED"),"original Catalog rejects a locked module",denied)
	_check(store.snapshot() == initial,"rules rejected loadout performs no Store mutation")
	var cross_slot: Dictionary = Catalog.default_build("tr01")
	cross_slot.slots.tool = "pulse_base"
	_check(_has_error(Hangar.validate(initial,cross_slot),"BUILD_SLOT_MISMATCH"),"original Catalog rejects wrong slot")
	var missing: Dictionary = Catalog.default_build("tr01")
	missing.slots.erase("tool")
	_check(_has_error(Hangar.validate(initial,missing),"BUILD_MISSING_SLOT"),"mandatory slot cannot be silently unequipped")
	var unknown: Dictionary = Catalog.default_build("tr01")
	unknown.slots.drive = "qa_nonexistent_module"
	_check(_has_error(Hangar.validate(initial,unknown),"BUILD_UNKNOWN_MODULE"),"unknown module ID is refused")
	_check(_has_error(Hangar.validate(initial,Catalog.default_build("ag03"),1.01),"BUILD_OVER_CARGO"),"original AG03 1kg cargo rating rejects excess")
	var fixture: Dictionary = {"id":"qa-hangar-existing-discoveries-fixture",
		"append":{"personal.discoveries":["boss:I1:harbor_whale","boss:F1:parasitic_crown"]}}
	if not _check(store.commit(fixture).get("ok",false),"original Store records two explicitly declared existing-discovery fixtures"):
		_finish(); return
	var unlocked: Dictionary = store.snapshot()
	var acquired: Dictionary = Hangar.ownership(unlocked)
	_check(acquired.modules.size() == 7 and "reinforced_guard" in acquired.modules and "racing_drive" in acquired.modules and "burst_capacitor" not in acquired.modules,
		"two actual discovery IDs unlock only their mapped modules",acquired.modules)
	var repeated: Dictionary = store.commit(fixture)
	_check(repeated.get("ok",false) and repeated.get("duplicate",false) and store.snapshot() == unlocked,"same original receipt retry grants nothing twice",repeated)
	_check(store.commit({"id":"qa-hangar-repeated-discovery-fixture","append":{"personal.discoveries":["boss:F1:parasitic_crown"]}}).get("ok",false)
		and store.snapshot().personal.discoveries.count("boss:F1:parasitic_crown") == 1 and Hangar.ownership(store.snapshot()).modules.size() == 7,
		"original append dedup and derived ownership keep one nonconsumable unlock")
	var option_rows: Array = Hangar.module_options(store.snapshot(),Catalog.default_build("tr01"),"drive")
	var racing: Array = option_rows.filter(func(row: Dictionary) -> bool: return row.id == "racing_drive")
	_check(racing.size() == 1 and racing[0].owned and racing[0].compatible,"unlocked module becomes one compatible actual slot option")
	# A third exact receipt is only for proving the existing PU rejection; do not
	# grant all discoveries or edit Catalog's capacity values to manufacture it.
	_check(store.commit({"id":"qa-hangar-pu-fixture","append":{"personal.discoveries":["boss:F2:mirrorwing_warden"]}}).get("ok",false),"existing F2 discovery fixture persisted for PU boundary")
	var overpower: Dictionary = Catalog.default_build("ag03")
	overpower.slots.weapon = "burst_capacitor"
	overpower.slots.drive = "racing_drive"
	_check(_has_error(Hangar.validate(store.snapshot(),overpower),"BUILD_OVER_POWER"),"original 84/75 PU AG03 build is refused")
	draft.slots.utility = "reinforced_guard"
	var before: Dictionary = store.snapshot()
	var active: Dictionary = Hangar.prepare_save(before,draft,true,int(before.generation))
	_check(not active.ok and active.code == "HANGAR_ACTIVE_SESSION" and store.snapshot() == before,"active-session save rejected without persistence",active)
	var stale: Dictionary = Hangar.prepare_save(before,draft,false,int(before.generation)-1)
	_check(not stale.ok and stale.code == "HANGAR_SNAPSHOT_STALE" and store.snapshot() == before,"stale UI generation cannot overwrite a new Store",stale)
	var prepared: Dictionary = Hangar.prepare_save(before,draft,false,int(before.generation))
	if not _check(prepared.get("ok",false),"valid owned draft prepares original Store payload",prepared.get("errors",[])):
		_finish(); return
	var paths: Array = prepared.transaction.set.keys()
	paths.sort()
	_check(paths == ["personal.builds","personal.hangar"] and not prepared.transaction.has("append") and not prepared.transaction.has("guest_rewards"),
		"payload changes only loadouts/selection, never rewards or world",paths)
	var draft_before: Dictionary = draft.duplicate(true)
	store.read_only = true
	var read_only: Dictionary = store.commit(prepared.transaction)
	store.read_only = false
	_check(not read_only.ok and read_only.error == "SAVE_SCHEMA_NEWER" and store.snapshot() == before and draft == draft_before,
		"original read-only Store failure retains selected build, generation and draft",read_only)
	store.failure_point = "before_publish"
	var failed: Dictionary = store.commit(prepared.transaction)
	store.failure_point = ""
	_check(not failed.ok and failed.error == "SAVE_PUBLISH_FAILED" and store.snapshot() == before and draft == draft_before,
		"original pre-publish fault cannot publish loadout or consume draft",failed)
	var failed_reader := Store.new(qa_root)
	_check(failed_reader.load_profile().get("ok",false) and failed_reader.snapshot() == before,
		"independent reader ignores failed temporary generation")
	var committed: Dictionary = store.commit(prepared.transaction)
	if not _check(committed.get("ok",false) and not committed.get("duplicate",false),"same valid draft retries through original Store commit",committed):
		_finish(); return
	var saved: Dictionary = store.snapshot()
	_check(saved.personal.builds.size() == 1 and store.matches_persisted_value(prepared.build,saved.personal.builds[0]) and saved.personal.hangar.selected_build_id == prepared.build.build_id,
		"selected five-slot build read back exactly across original JSON boundary",saved.personal)
	_check(saved.world == before.world and saved.personal.discoveries == before.personal.discoveries and saved.personal.collections == before.personal.collections and saved.world_revision == before.world_revision,
		"hangar save leaves original world/rewards/world revision unchanged")
	var duplicate: Dictionary = store.commit(prepared.transaction)
	_check(duplicate.get("ok",false) and duplicate.get("duplicate",false) and store.snapshot() == saved,"same save receipt is idempotent",duplicate)
	var reader := Store.new(qa_root)
	if not _check(reader.load_profile().get("ok",false) and reader.snapshot() == saved,"fresh original Store reads published selected loadout"):
		_finish(); return
	var selected: Dictionary = Hangar.launch_build(reader.snapshot())
	if not _check(selected.get("ok",false) and selected.build.slots.drive == "racing_drive" and selected.build.slots.utility == "reinforced_guard",
		"next-launch rules read persisted modules instead of default loadout",selected.get("errors",[])):
		_finish(); return
	body = Flight.new()
	body.configure(selected.resolved)
	var original: Dictionary = Catalog.resolve_build(Catalog.default_build("tr01"))
	_check(body.build == selected.build and body.stats == selected.resolved.derived and is_equal_approx(body.mass,float(selected.resolved.derived.mass_kg)),
		"new actual FlightBody.configure consumes saved build and original derived mass",{"build":body.build,"mass":body.mass,"derived":body.stats})
	_check(is_equal_approx(float(body.stats.speed_mps),float(original.derived.speed_mps)*1.12) and body.damage_state.armor == 26.0 and body.damage_state.armor == selected.armor,
		"real racing speed and reinforced armor agree with displayed original values",{"speed":body.stats.speed_mps,"armor":body.damage_state.armor})
	var again: Dictionary = Hangar.prepare_save(reader.snapshot(),selected.build,false,int(saved.generation))
	_check(again.get("ok",false) and again.get("no_op",false) and reader.snapshot() == saved,"unchanged loadout recognized without another write")
	_finish()

func _has_error(result: Dictionary, code: String) -> bool:
	for error: Dictionary in result.get("errors",[]):
		if error.get("code") == code: return true
	return false

func _check(ok: bool, label: String, actual: Variant = null) -> bool:
	checks.append({"passed":ok,"label":label,"actual":actual})
	return ok

func _finish() -> void:
	if finished: return
	finished = true
	if is_instance_valid(body): body.free()
	await process_frame
	var failures: Array = checks.filter(func(row: Dictionary) -> bool: return not row.passed)
	FileAccess.open(output+"/result.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failures.size(),"engine_errors":logger.errors,"qa_root":qa_root,
		"scope":"Pure hangar rules, original isolated QA Store, exact known discovery fixtures and new FlightBody.configure. No earned-campaign, natural-profile, MAIN, UI, LAN, actual flight, power-consumption or weapon-damage acceptance."},"\t"))
	print("HANGAR_RULES_RESULT "+JSON.stringify({"checks":checks.size(),"failures":failures,"engine_errors":logger.errors,"qa_root":qa_root}))
	quit(0 if failures.is_empty() and logger.errors.is_empty() else 1)
