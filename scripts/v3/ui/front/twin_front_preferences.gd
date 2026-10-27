extends RefCounted
## Local presentation preferences; never edits campaign, receipt or loadout data.
const DEFAULTS := {"profile_name":"新航员", "reduced_motion":false, "fullscreen":false, "vsync":true, "fps_limit":60, "font_size":16, "flight_control":"heading", "contacts":[], "claimed_styles":["harbor"], "equipped_style":"harbor", "last_summary":{}}
const STYLES := {"harbor":{"name":"港湾青","goals":0,"color":"80e4cf"},"canopy":{"name":"林冠金","goals":19,"color":"c9dd88"},"furnace":{"name":"炉心橙","goals":58,"color":"ffb179"},"confluence":{"name":"共脉紫","goals":84,"color":"bfb0ff"}}
var values: Dictionary = DEFAULTS.duplicate(true)
var path := ""
var error := ""

func open(profile_root: String) -> void:
	path = profile_root.path_join("front_ui_v1.json")
	if not FileAccess.file_exists(path): return
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null:
		error = "界面偏好未能读取；原文件保留。"
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		error = "界面偏好格式无法读取；原文件保留，暂用默认显示。"
		return
	for key: String in DEFAULTS:
		if parsed.has(key) and typeof(parsed[key]) == typeof(DEFAULTS[key]): values[key] = parsed[key]
	values.profile_name = str(values.profile_name).strip_edges().left(16)
	if values.profile_name.is_empty(): values.profile_name = "新航员"
	values.fps_limit = int(parsed.get("fps_limit",60)) if int(parsed.get("fps_limit",60)) in [30,60,120] else 60
	values.font_size = clampi(int(parsed.get("font_size",16)),14,20)
	var contacts: Array = []
	for row: Variant in values.contacts:
		if row is Dictionary and valid_address(str(row.get("address",""))) and contacts.size()<24:
			contacts.append({"name":str(row.get("name","伙伴")).strip_edges().left(16),"address":str(row.address).strip_edges()})
	values.contacts = contacts
	var styles: Array = ["harbor"]
	for id: Variant in values.claimed_styles:
		if id is String and STYLES.has(id) and id not in styles: styles.append(id)
	values.claimed_styles = styles
	if values.equipped_style not in styles: values.equipped_style = "harbor"
	if values.flight_control not in ["heading","map"]: values.flight_control="heading"

func write(next: Dictionary) -> bool:
	# Failed writes leave both current memory and previous durable preferences intact.
	if path.is_empty() or not error.is_empty(): return false
	var pending := path+".pending"
	var backup := path+".previous"
	var output := FileAccess.open(pending,FileAccess.WRITE)
	if output == null: return false
	output.store_string(JSON.stringify(next,"\t"))
	output.flush()
	var status := output.get_error()
	output.close()
	if status != OK: return false
	var check := FileAccess.open(pending,FileAccess.READ)
	if check == null: return false
	var actual: Variant = JSON.parse_string(check.get_as_text())
	check.close()
	if not actual is Dictionary: return false
	if FileAccess.file_exists(backup) and DirAccess.remove_absolute(backup)!=OK: return false
	var had_previous := FileAccess.file_exists(path)
	if had_previous and DirAccess.rename_absolute(path,backup)!=OK: return false
	if DirAccess.rename_absolute(pending,path)!=OK:
		if had_previous: DirAccess.rename_absolute(backup,path)
		return false
	values = next.duplicate(true)
	return true

static func valid_address(value: String) -> bool:
	var pieces := value.strip_edges().split(".")
	if pieces.size()!=4: return false
	for part: String in pieces:
		if not part.is_valid_int() or part.is_empty() or part.length()>3 or int(part)<0 or int(part)>255: return false
	return int(pieces[0])>0 and int(pieces[0])<224 and value.strip_edges()!="255.255.255.255"
