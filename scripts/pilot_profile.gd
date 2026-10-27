class_name PilotProfile
extends RefCounted

var file_path = "user://pilot.json"
var data: Dictionary
var notice = ""
var read_only = false

func _init(path: String = "user://pilot.json") -> void:
	file_path = path
	data = defaults()

func defaults() -> Dictionary:
	return {
		"version":1, "parts":0, "unlocked":["pulse","stable","shield"],
		"loadout":{"weapon":"pulse","drive":"stable","utility":"shield"},
		"completed":[], "claimed_runs":[], "records":{}, "facility":[],
		"settings":{"difficulty":0,"auto_fire":false,"volume":0.55,"camera":0,"fullscreen":false,"input":{}}
	}

func _parse_file(path: String):
	if not FileAccess.file_exists(path):return null
	var source = FileAccess.open(path, FileAccess.READ)
	if source == null:return null
	if source.get_length() > 8 * 1024 * 1024:
		source.close()
		return null
	var parser=JSON.new()
	var text = source.get_as_text()
	source.close()
	if parser.parse(text)!=OK:return null
	return parser.data

func _finite_number(value) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func _valid_record(value) -> bool:
	return value is Dictionary and _finite_number(value.get("time")) and float(value.time) >= 0 and _finite_number(value.get("collisions")) and float(value.collisions) >= 0 and _finite_number(value.get("damage")) and float(value.damage) >= 0

func _string_list(raw: Array, limit: int = 10000) -> Array:
	var clean = []
	for item in raw.slice(0, limit):
		if item is String and item.length() <= 256 and not clean.has(item):clean.append(item)
	return clean

func load_profile() -> void:
	notice = ""
	read_only = false
	var parsed = _parse_file(file_path)
	if not parsed is Dictionary:
		parsed = _parse_file(file_path + ".bak")
		if parsed is Dictionary:notice = "主存档缺失或损坏：已恢复备份。"
	if not parsed is Dictionary:
		if FileAccess.file_exists(file_path) or FileAccess.file_exists(file_path + ".bak"):
			notice = "无法读取存档，原文件已保留；请恢复备份后重试。"
			read_only = true
		return
	if _finite_number(parsed.get("version")) and float(parsed.version) > 1:
		notice = "存档来自更新版本，当前版本不会覆盖它。"
		read_only = true
		return
	var fresh = defaults()
	for key in fresh:
		if parsed.has(key) and typeof(parsed[key]) == typeof(fresh[key]):
			fresh[key] = parsed[key]
		elif key == "parts" and _finite_number(parsed.get(key)):
			fresh[key] = maxi(0, int(parsed[key]))
	var settings = defaults().settings
	for key in settings:
		var value=fresh.settings.get(key)
		if typeof(value)==typeof(settings[key]) or (_finite_number(value) and (settings[key] is float or settings[key] is int)):
			settings[key]=value
		if (settings[key] is float or settings[key] is int) and not _finite_number(settings[key]):settings[key] = defaults().settings[key]
	settings.difficulty=clampi(int(settings.difficulty),0,GameData.DIFFICULTY.size()-1)
	settings.camera=clampi(int(settings.camera),0,1)
	settings.volume=clampf(float(settings.volume),0.0,1.0)
	fresh.settings = settings
	fresh.parts = maxi(0, int(fresh.parts))
	fresh.unlocked = _string_list(fresh.unlocked)
	fresh.claimed_runs = _string_list(fresh.claimed_runs)
	fresh.facility = _string_list(fresh.facility)
	var records = {}
	for key in fresh.records:
		if records.size() >= 10000:break
		if key is String and key.length() <= 256 and _valid_record(fresh.records[key]):
			records[key] = fresh.records[key].duplicate(true)
	fresh.records = records
	var completed=[]
	for item in fresh.completed:
		if _finite_number(item) and int(item)>=0 and int(item)<3 and not completed.has(int(item)):
			completed.append(int(item))
	fresh.completed=completed
	fresh.version = 1
	for base in ["pulse","stable","shield"]:
		if not fresh.unlocked.has(base):
			fresh.unlocked.append(base)
	if not GameData.valid_loadout(fresh.loadout, fresh.unlocked):
		fresh.loadout = defaults().loadout
	data = fresh

func save_profile() -> bool:
	if read_only:return false
	var temp = file_path + ".tmp"
	var file = FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		notice = "存档写入失败，当前进度仍保留在本次会话。"
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	var write_error = file.get_error()
	file.close()
	if write_error != OK or not _parse_file(temp) is Dictionary:
		notice = "存档验证失败，旧存档和备份已保留。"
		return false
	# Only rotate a readable primary; recovery must not destroy its good backup.
	if FileAccess.file_exists(file_path) and _parse_file(file_path) is Dictionary:
		if DirAccess.copy_absolute(file_path, file_path + ".bak") != OK:
			notice = "备份写入失败，旧存档已保留。"
			return false
	elif FileAccess.file_exists(file_path):
		var quarantine = file_path + ".corrupt." + str(Time.get_ticks_usec())
		if DirAccess.copy_absolute(file_path, quarantine) != OK:
			notice = "无法保留损坏存档，已停止覆盖。"
			return false
	var err = DirAccess.rename_absolute(temp, file_path)
	if err != OK:
		notice = "保存替换失败，请检查用户目录写入权限。"
	return err == OK

func can_play(index: int) -> bool:
	return index>=0 and index<GameData.MISSIONS.size() and (index == 0 or data.completed.has(index - 1))

func buy_module(id: String) -> bool:
	if not GameData.MODULES.has(id) or data.unlocked.has(id):
		return false
	var price = int(GameData.MODULES[id].cost)
	if data.parts < price:
		return false
	var old = data.duplicate(true)
	data.parts -= price
	data.unlocked.append(id)
	if not save_profile():
		data = old
		return false
	return true

func equip(id: String) -> bool:
	if not GameData.MODULES.has(id) or not data.unlocked.has(id):
		return false
	var next = data.loadout.duplicate()
	next[GameData.MODULES[id].slot] = id
	if not GameData.valid_loadout(next, data.unlocked):
		return false
	var old = data.loadout
	data.loadout = next
	if not save_profile():
		data.loadout = old
		return false
	return true

func upgrade_facility(id: String) -> bool:
	if id not in ["workshop","terminal"] or data.facility.has(id) or data.parts < 50:
		return false
	var old = data.duplicate(true)
	data.parts -= 50
	data.facility.append(id)
	var gift = "charge" if id == "workshop" else "agile"
	if not data.unlocked.has(gift):
		data.unlocked.append(gift)
	if not save_profile():
		data = old
		return false
	return true

func claim(mission: int, run_id: String, seconds: float, collisions: int, damage: float, difficulty: int, assisted: bool, bonus: int=0) -> int:
	if mission < 0 or mission >= GameData.MISSIONS.size() or data.claimed_runs.has(run_id) or not is_finite(seconds) or seconds < 0 or not is_finite(damage) or damage < 0 or collisions < 0:
		return 0
	var old = data.duplicate(true)
	var reward = int(GameData.MISSIONS[mission].reward) if not data.completed.has(mission) else 25
	reward+=clampi(bonus,0,65)
	if not data.completed.has(mission):
		data.completed.append(mission)
	data.parts += reward
	data.claimed_runs.append(run_id)
	var record_key = "%s:%s:%s:%s:%s:%s" % [mission, difficulty, assisted, data.loadout.weapon, data.loadout.drive, data.loadout.utility]
	var existing = data.records.get(record_key, {})
	if not _valid_record(existing) or seconds < float(existing.time):
		data.records[record_key] = {"time":seconds,"collisions":collisions,"damage":damage,"version":GameData.VERSION}
	if not save_profile():
		data = old
		return -1
	return reward

func best_time(mission: int, difficulty: int, assisted: bool) -> float:
	var key="%s:%s:%s:%s:%s:%s"%[mission,difficulty,assisted,data.loadout.weapon,data.loadout.drive,data.loadout.utility]
	var record=data.records.get(key,{})
	if not record is Dictionary:return -1.0
	var seconds=record.get("time",-1.0)
	return float(seconds) if _finite_number(seconds) and float(seconds) >= 0 else -1.0

