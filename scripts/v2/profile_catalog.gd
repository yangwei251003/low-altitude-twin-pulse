class_name ProfileCatalogV22
extends RefCounted

const IDS = ["default", "free_01", "free_02"]
const NAMES = ["低空飞行员", "自由飞行员 01", "自由飞行员 02"]
var base_path = "user://profiles"
var migration_source = ""
var selected = "default"
var notice = ""
# The host must use open_profile() so a failed import cannot become a new save.
var migration_blocked = false
var migration_staging_path = ""
# Fault injection is used only by the isolated save tests; never set by the UI.
var migration_failure_point = ""

func _init(root_path: String = "user://profiles", legacy_source: String = "") -> void:
	base_path=root_path.trim_suffix("/")
	migration_source=legacy_source

func initialize() -> void:
	notice = ""
	_migrate_read_only()
	for index in range(IDS.size()):
		var repo = open_profile(IDS[index])
		if repo.read_only or repo._load_failed: continue
		var settings: Dictionary = repo.data.settings
		var changes = {}
		var defaults = {"profile_name":NAMES[index],"profile_kind":"normal" if index==0 else "sandbox","sandbox_rules":{"invincible":false,"unlimited_power":false,"no_overheat":false},"environment_preset":"standard","environment_wind":1.0,"environment_weather":1.0,"environment_damage":1.0,"environment_interference":1.0,"tutorial_v22":{},"reduced_motion":false}
		for key in defaults:
			if not settings.has(key): changes["settings."+key] = defaults[key]
		if str(settings.get("control_mode","assisted")) == "advanced": changes["settings.control_mode"] = "manual_throttle"
		if index>0:
			var frames = repo.data.owned_airframes.duplicate()
			var modules = repo.data.owned_modules.duplicate()
			var builds = repo.data.builds.duplicate(true)
			for id in CatalogV2.airframes():
				if id not in frames: frames.append(id)
				var found = false
				for build in builds:
					if build.airframe_id == id: found=true
				if not found: builds.append(CatalogV2.default_build(id))
			for id in CatalogV2.modules():
				if id not in modules: modules.append(id)
			changes.merge({"owned_airframes":frames,"owned_modules":modules,"builds":builds})
		if not changes.is_empty():
			var result = repo.commit({"id":"v22:profile:"+str(index),"set":changes})
			if not result.ok: notice = "飞行员初始化未完成："+str(result.error)
	var cfg = ConfigFile.new()
	if cfg.load(base_path.path_join("index.cfg")) == OK:
		var id = str(cfg.get_value("selection","id","default"))
		if id in IDS: selected=id

func open_profile(id: String) -> SaveRepositoryV2:
	var safe_id = id if id in IDS else "default"
	var repo = SaveRepositoryV2.new(base_path.path_join(safe_id))
	repo.load_profile()
	if safe_id == "default" and migration_blocked:
		repo.read_only = true
		repo._load_failed = true
		repo.notice = notice
	return repo

func select(id: String) -> bool:
	if id not in IDS: return false
	if id == "default" and migration_blocked: return false
	var cfg = ConfigFile.new()
	cfg.set_value("selection","id",id)
	if cfg.save(base_path.path_join("index.cfg")) != OK: return false
	selected=id
	return true

func list_profiles() -> Array:
	var result: Array = []
	for index in range(IDS.size()):
		var repo = open_profile(IDS[index])
		result.append({"id":IDS[index],"name":str(repo.data.settings.get("profile_name",NAMES[index])),"active":selected==IDS[index],"parts":"∞" if index>0 else str(repo.data.wallet.parts),"completed":repo.data.campaign.completed_missions.size(),"kind":"normal" if index==0 else "sandbox"})
	return result

func _migrate_read_only() -> void:
	migration_blocked = false
	migration_staging_path = ""
	var destination = ProjectSettings.globalize_path(base_path.path_join("default"))
	if DirAccess.dir_exists_absolute(destination) and not _directory_empty(destination):
		# Existing progress is authoritative, including newer-schema/read-only data.
		# An unverified directory is preserved for recovery, never replaced by V2.1.
		var existing = SaveRepositoryV2.new(destination)
		if not existing.load_profile() or existing._generation_files().is_empty():
			_block_migration("现有普通飞行员存档无法验证，已保留全部文件并禁止写入。请恢复存档，或先使用自由飞行员。")
		return
	var source = ProjectSettings.globalize_path(migration_source) if not migration_source.is_empty() else OS.get_environment("APPDATA").path_join("LowAltitudeSquadV2Independent20261014/profiles/default")
	if not DirAccess.dir_exists_absolute(source): return
	var old = SaveRepositoryV2.new(source)
	var files = old._generation_files()
	if files.is_empty() and not FileAccess.file_exists(source.path_join("manifest.json")): return
	if not old.load_profile() or old.read_only:
		_block_migration("旧存档未通过校验，原文件已保留，普通飞行员导入已暂停。可先使用自由飞行员。")
		return
	# A sibling staging directory keeps publish on the same filesystem. Every
	# failure leaves the source and any staging files intact for inspection/retry.
	migration_staging_path = destination + ".migrating-" + Crypto.new().generate_random_bytes(8).hex_encode()
	if DirAccess.make_dir_recursive_absolute(migration_staging_path) != OK:
		_block_migration("无法创建导入暂存目录；旧存档保持不变。")
		return
	if migration_failure_point == "after_stage_created":
		_block_migration("导入暂存阶段中断，尚未发布普通飞行员存档。")
		return
	var hashes = {}
	if FileAccess.file_exists(source.path_join("manifest.json")): files.append("manifest.json")
	for name in files:
		var from = source.path_join(name)
		var to = migration_staging_path.path_join(name)
		var hash = FileAccess.get_sha256(from)
		if hash.is_empty() or DirAccess.copy_absolute(from,to) != OK or FileAccess.get_sha256(to)!=hash or FileAccess.get_sha256(from)!=hash:
			_block_migration("旧档复制未通过校验，原文件和暂存副本已保留，普通飞行员尚未发布。")
			return
		hashes[name]=hash
		if migration_failure_point == "after_copy":
			_block_migration("导入复制阶段中断，尚未发布普通飞行员存档。")
			return
	var staged = SaveRepositoryV2.new(migration_staging_path)
	if not staged.load_profile() or staged.read_only or staged._canonical(staged.data) != old._canonical(old.data):
		_block_migration("导入副本未通过完整存档校验，旧存档保持不变。")
		return
	# A concurrently updated legacy save must not be mistaken for the snapshot
	# we validated. Nothing in this importer opens the source for writing.
	var fresh = SaveRepositoryV2.new(source)
	if not fresh.load_profile() or fresh._canonical(fresh.data) != old._canonical(old.data):
		_block_migration("导入期间旧存档发生变化，请关闭旧版本后重试。")
		return
	var receipt_path = migration_staging_path.path_join("v21_import.json")
	var receipt = FileAccess.open(receipt_path,FileAccess.WRITE)
	if receipt == null:
		_block_migration("无法写入导入校验记录，尚未发布普通飞行员存档。")
		return
	var receipt_text = JSON.stringify({"source":source,"sha256":hashes,"imported_at":Time.get_datetime_string_from_system(true)},"\t")
	receipt.store_string(receipt_text)
	receipt.flush()
	var receipt_error = receipt.get_error()
	receipt.close()
	if receipt_error != OK or FileAccess.get_sha256(receipt_path) != receipt_text.sha256_text():
		_block_migration("导入校验记录未通过读回验证，尚未发布普通飞行员存档。")
		return
	if migration_failure_point == "before_publish":
		_block_migration("导入发布前中断，已验证的暂存副本保留。")
		return
	if DirAccess.dir_exists_absolute(destination):
		# Retry an empty directory left by the previous importer without deleting
		# anything. Re-check immediately before rename; non-empty data always wins.
		if not _directory_empty(destination):
			_block_migration("目标存档目录在导入期间出现文件，已停止发布以保护现有数据。")
			return
		var empty_backup = destination + ".empty-" + Crypto.new().generate_random_bytes(8).hex_encode()
		if DirAccess.rename_absolute(destination,empty_backup) != OK:
			_block_migration("无法保留旧的空目录，导入尚未发布。")
			return
	if DirAccess.rename_absolute(migration_staging_path,destination) != OK:
		_block_migration("导入发布失败；旧存档和已验证暂存副本均保留，可重试。")
		return
	notice="已将 V2.1 普通飞行员复制至 V2.2，原存档保持不变。"

func _directory_empty(path: String) -> bool:
	var directory = DirAccess.open(path)
	if directory == null: return false
	directory.include_hidden = true
	return directory.get_files().is_empty() and directory.get_directories().is_empty()

func _block_migration(reason: String) -> void:
	migration_blocked = true
	notice = reason
