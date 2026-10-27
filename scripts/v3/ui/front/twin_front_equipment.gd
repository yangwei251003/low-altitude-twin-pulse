extends RefCounted
## Native equipment pages. Read actual Store/Hangar/Catalog data; all mutations
## are dispatched to Root and the original loadout/save authority.
const Kit = preload("res://scripts/v3/ui/front/twin_front_kit.gd")
const Hangar = preload("res://scripts/v3/gameplay/twin_hangar.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
const Regions = preload("res://scripts/v3/world/twin_region_catalog.gd")
const STYLES := [
	{"id":"harbor", "name":"港湾青", "gate":0, "color":"85dbc3", "body":"潮湾灯标的青绿。初次起航即可使用。"},
	{"id":"canopy", "name":"林冠金", "gate":19, "color":"e7c879", "body":"在根冠与归航灯之间留下的暖金。"},
	{"id":"furnace", "name":"炉心橙", "gate":58, "color":"efab74", "body":"热崖换班灯的橙色，纪念沿途的检修与交接。"},
	{"id":"confluence", "name":"共脉紫", "gate":84, "color":"c1a5e8", "body":"走到共脉中枢之后，为两界保留的一抹紫。"}
]
const MODULE_NOTES := {
	"pulse_base":"稳定的基础脉冲武器，适合观察预警后的短点射。",
	"scan_base":"基础调查工具，用于核对现场信息。",
	"guard_base":"基础防护装置，在原防护规则下减轻伤害。",
	"hook_base":"作业吊钩，用于有挂接条件的运输作业。",
	"delivery_base":"精确投送附件，保留同一件货物的交付关系。",
	"clearance_base":"清障工具，适合检修通路的作业配置。",
	"searchlight_base":"近场照明附件，适合昏暗位置的观察。",
	"stock_drive":"机体原装动力，不增加质量和供电占用。",
	"stock_battery":"机体原装电池，保留当前机体的基础容量。",
	"cargo_winch":"增强吊运附件，提供载货阻尼与绞盘参数。",
	"precision_gimbal":"稳定作业方向的辅助云台。",
	"racing_drive":"提高速度与加速参数，同时增加供电占用。",
	"long_range_battery":"增加供电容量，同时增加起飞质量。",
	"night_sensor":"夜间观察附件，提供扫描与航标记忆参数。",
	"cooling_duct":"提高冷却参数，适合持续使用高热量装备。",
	"reinforced_guard":"加强结构防护，同时增加质量与外形包络。",
	"burst_capacitor":"蓄能武器：需要蓄力，单发热量与供电占用更高。"}

static func build(page: String, ctx: Dictionary, dispatch: Callable) -> Control:
	var root: VBoxContainer = Kit.column(20)
	root.name = "FrontEquipment_" + page
	match page:
		"base": _base(root, ctx, dispatch)
		"inventory": _inventory(root, ctx, dispatch)
		"workshop": _workshop(root, ctx, dispatch)
		"shop": _shop(root, ctx, dispatch)
		_:
			root.add_child(Kit.heading("整备页面无法打开", "EQUIPMENT", "请返回基地选择可用工位。"))
			root.add_child(_nav("返回基地", "base", dispatch, true))
	return root

static func module_info(ctx: Dictionary, id: String) -> Dictionary:
	var modules: Dictionary = Catalog.modules()
	if not modules.has(id): return {"title":"未知模块", "body":"模块目录中没有这项记录。", "status":"无法读取", "source":"", "stats":""}
	var spec: Dictionary = modules[id]
	var profile: Dictionary = ctx.get("profile", {})
	var owned: Dictionary = Hangar.ownership(profile)
	var selected: Dictionary = Hangar.launch_build(profile, str(ctx.get("frame_id", "")))
	var possession: bool = id in owned.get("modules", [])
	var sources := PackedStringArray()
	if id in owned.get("starter_modules", []): sources.append("初始装备 · 可反复装卸")
	for row: Dictionary in owned.get("unlocks", []):
		if str(row.module_id) == id: sources.append(str(row.condition))
	if sources.is_empty(): sources.append("等待读取当前旅程的模块来源")
	var fitted := false
	var compatible := false
	var valid := false
	var errors: Array = []
	if selected.get("ok", false):
		var actual: String = str(selected.build.slots.get(str(spec.slot), ""))
		if actual == "stock": actual = "stock_" + str(spec.slot)
		fitted = actual == id
		for row: Dictionary in Hangar.module_options(profile, selected.build, str(spec.slot)):
			if str(row.id) != id: continue
			compatible = bool(row.compatible)
			valid = bool(row.valid)
			errors = row.errors.duplicate(true)
	var status: String = "等待读档" if not owned.get("ok", false) else "待探索解锁" if not possession else "等待读取有效配装" if not selected.get("ok", false) else "挂点不兼容" if not compatible else "当前配装预算不足" if not valid else "已装配" if fitted else "可安装"
	var mass: float = float(spec.get("mass_delta_kg", spec.get("mass_kg", 0.0)))
	var power: float = float(spec.get("power_pu", 0.0))
	var capacity: float = float(spec.get("capacity_delta_pu", 0.0))
	var stats: String = "附加质量 %.2f kg · 占用 %.0f PU" % [mass, power]
	if capacity != 0.0: stats += " · 容量 %+.0f PU" % capacity
	var source: String = "\n".join(sources)
	var display_frame: String = str(selected.get("build", {}).get("airframe_id", ctx.get("frame_id", ""))).to_upper()
	var body: String = str(MODULE_NOTES.get(id, "沿当前模块目录提供的参数装配。")) + "\n\n" + str(Hangar.SLOT_NAMES.get(str(spec.slot), "模块")) + " · 当前机体 " + display_frame + " · " + status + "\n" + stats
	var effects: String = _effect_text(spec.get("modifiers", {}))
	if not effects.is_empty(): body += "\n" + effects
	body += "\n\n解锁来源" + ("（任一路径均可）" if sources.size() > 1 else "") + "\n" + source
	if possession and not valid and not errors.is_empty(): body += "\n\n当前机体：" + Hangar.error_text({"code":"HANGAR_BUILD_REJECTED", "errors":errors})
	return {"id":id, "title":str(spec.name), "name":str(spec.name), "slot":str(spec.slot),
		"body":body, "status":status, "source":source, "stats":stats, "owned":possession,
		"compatible":compatible, "valid":valid, "fitted":fitted, "mass_kg":mass, "power_pu":power,
		"capacity_delta_pu":capacity, "effects":effects, "errors":errors}

static func _base(root: VBoxContainer, ctx: Dictionary, dispatch: Callable) -> void:
	var profile: Dictionary = ctx.get("profile", {})
	var selected: Dictionary = _loadout(ctx)
	var owned: Dictionary = Hangar.ownership(profile)
	var active: bool = bool(ctx.get("active", false))
	var region: String = str(profile.get("world", {}).get("region_id", "I1"))
	var region_name: String = str(Regions.definition(region).get("name", "潮湾科技港"))
	root.add_child(Kit.heading("基地", "THE SQUAD BASE", "停靠、整理装备，再决定下一段航程。所有模块都来自你的实际探索记录。"))
	var hero: VBoxContainer = Kit.card("让下一次出航准备得更从容", "上次停靠 · " + region_name, "当前旅程")
	root.add_child(hero)
	var metrics: HBoxContainer = Kit.row(24)
	metrics.add_child(Kit.metric("%d / 84" % _completed(ctx), "已完成主线目标"))
	metrics.add_child(Kit.metric("%d / %d" % [owned.get("modules", []).size(), Catalog.modules().size()], "已拥有模块"))
	metrics.add_child(Kit.metric(str(owned.get("frames", []).size()), "可整备机体"))
	hero.add_child(metrics)
	if selected.get("ok", false): hero.add_child(Kit.label(_loadout_caption(selected), 15, Kit.MUTED))
	else: hero.add_child(Kit.label(Hangar.error_text(selected), 15, Kit.GOLD))
	var launch: HBoxContainer = Kit.row(12)
	launch.add_child(_nav("返回当前飞行" if active else "选择出航方式", "combat" if active else "modes", dispatch, true))
	if active: launch.add_child(Kit.button("保存战况并返回机库", func(): _send(dispatch, "legacy", {"action":"hangar_return", "payload":{}})))
	else: launch.add_child(_nav("进入机库配装", "hangar", dispatch))
	hero.add_child(launch)
	var stations: GridContainer = Kit.grid(2)
	root.add_child(stations)
	var inventory: VBoxContainer = Kit.card("模块仓库", "按槽位、解锁状态和当前机体筛选，核对重量、供电与探索来源。", "01 / 已拥有与待发现")
	inventory.add_child(_nav("整理模块仓库", "inventory", dispatch))
	stations.add_child(inventory)
	var workshop: VBoxContainer = Kit.card("整备工坊", "调整五槽配装，或把当前机体草稿恢复原装；有效配装保存后供下次出航使用。", "02 / 实际装配")
	workshop.add_child(_nav("前往整备工坊", "workshop", dispatch))
	stations.add_child(workshop)
	var preparation: VBoxContainer = Kit.card("出航前看一眼", "先核对额定载荷与供电余量。飞行中的当前配装保持不变，修整需通过原保存与返航流程。")
	preparation.add_child(_nav("查看地区与航路", "map", dispatch))
	stations.add_child(preparation)
	var supplies: VBoxContainer = Kit.card("探索补给", "查看现有模块的解锁线索，以及随主线进展免费领取的大厅界面样式。", "03 / 免费探索回报")
	supplies.add_child(_nav("打开补给商城", "shop", dispatch))
	stations.add_child(supplies)

static func _inventory(root: VBoxContainer, ctx: Dictionary, dispatch: Callable) -> void:
	root.add_child(Kit.heading("模块仓库", "INVENTORY", "已拥有模块可以反复装卸。锁定模块显示真实来源，点击详情可查看参数与当前机体适配情况。"))
	_frame_selector(root, ctx, dispatch)
	_filters(root, ctx, dispatch)
	var modules: Dictionary = Catalog.modules()
	var selection: Dictionary = ctx.get("selection", {})
	var slot: String = str(selection.get("equipment_slot", "all"))
	var state: String = str(selection.get("equipment_owned", "all"))
	var query: String = str(selection.get("equipment_query", "")).strip_edges().to_lower()
	var ids: Array = modules.keys()
	ids.sort()
	var shown := 0
	for id: String in ids:
		var info: Dictionary = module_info(ctx, id)
		if slot != "all" and str(info.slot) != slot: continue
		if state == "owned" and not info.owned or state == "locked" and info.owned or state == "fit" and not info.valid: continue
		if not query.is_empty() and (str(info.title)+" "+str(info.source)+" "+str(info.id)).to_lower().find(query) < 0: continue
		_module_row(root, info, dispatch)
		shown += 1
	root.add_child(Kit.label("当前显示 %d 项模块" % shown, 13, Kit.MUTED))
	if shown == 0:
		var empty: VBoxContainer = Kit.card("没有符合条件的模块", "试试其他槽位或解锁状态，也可以清空关键词。")
		empty.add_child(Kit.button("清空关键词", func(): _send(dispatch, "page_filter", {"key":"equipment_query", "value":""})))
		root.add_child(empty)
	root.add_child(_nav("前往机库调整配装", "hangar", dispatch, true))

static func _workshop(root: VBoxContainer, ctx: Dictionary, dispatch: Callable) -> void:
	root.add_child(Kit.heading("整备工坊", "LOADOUT WORKSHOP", "直接使用现有模块装配与原装恢复。没有制造倒计时，只有真实重量、供电和挂点约束。"))
	_frame_selector(root, ctx, dispatch)
	var selected: Dictionary = _loadout(ctx)
	var active: bool = bool(ctx.get("active", false))
	var bench: VBoxContainer = Kit.card("当前整备方案", _loadout_caption(selected) if selected.get("ok", false) else Hangar.error_text(selected), "保存的当前机体")
	root.add_child(bench)
	var actions: HBoxContainer = Kit.row(12)
	bench.add_child(actions)
	actions.add_child(_nav("查看飞行中的配装" if active else "调整当前配装", "hangar", dispatch, true))
	var restore: Button = Kit.button("恢复原装草稿", func(): _send(dispatch, "navigate", {"page":"hangar", "restore_stock":true}))
	restore.disabled = active or not selected.get("ok", false)
	restore.tooltip_text = "只恢复机库内的当前机体草稿；检查并保存后生效。" if not active else "先保存战况并返回机库，再调整装备。"
	actions.add_child(restore)
	if active:
		bench.add_child(Kit.label("当前正在飞行。先保存战况并返航，随后才能修改下一次出航的配装。", 14, Kit.GOLD))
		bench.add_child(Kit.button("保存战况并返回机库", func(): _send(dispatch, "legacy", {"action":"hangar_return", "payload":{}})))
	else: bench.add_child(Kit.label("打开机库后先编辑草稿，再按“保存配装”。保存失败时草稿会保留。", 14, Kit.MUTED))
	if selected.get("ok", false):
		for slot: String in Catalog.SLOT_ORDER:
			var id: String = str(selected.build.slots.get(slot, ""))
			if id == "stock": id = "stock_"+slot
			_module_row(root, module_info(ctx, id), dispatch, str(Hangar.SLOT_NAMES[slot]) + " / 当前安装")
	var route: VBoxContainer = Kit.card("寻找下一件适合的装备", "同一件模块可能有不同的探索解锁路径。先看来源，再决定下一段航程。")
	var links: HBoxContainer = Kit.row(12)
	links.add_child(_nav("查看所有模块", "inventory", dispatch))
	links.add_child(_nav("查看探索补给", "shop", dispatch))
	route.add_child(links)
	root.add_child(route)

static func _shop(root: VBoxContainer, ctx: Dictionary, dispatch: Callable) -> void:
	root.add_child(Kit.heading("补给商城", "EXPLORATION SUPPLIES", "模块由实际探索记录解锁；大厅界面样式按主线进展免费领取。这里不使用货币或付款。"))
	var complete: int = _completed(ctx)
	var settings: Dictionary = ctx.get("settings", {})
	var equipped: String = str(settings.get("equipped_style", "harbor"))
	root.add_child(Kit.label("大厅界面样式 · 主线目标 %d / 84" % complete, 20, Kit.TEXT))
	var styles: GridContainer = Kit.grid(2)
	root.add_child(styles)
	for row: Dictionary in STYLES:
		var id: String = str(row.id)
		var claimed: bool = _style_claimed(settings, id)
		var eligible: bool = complete >= int(row.gate)
		var card: VBoxContainer = Kit.card(str(row.name), str(row.body), "当前使用" if id == equipped else "已领取" if claimed else "可以领取" if eligible else "主线 %d 目标后可领取" % int(row.gate))
		var strip := ColorRect.new()
		strip.color = Color(str(row.color))
		strip.custom_minimum_size.y = 8
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(strip)
		card.add_child(Kit.label("免费 · 默认提供" if int(row.gate) == 0 else "免费 · 已完成 %d / %d 个主线目标" % [mini(complete, int(row.gate)), int(row.gate)], 13, Kit.MUTED))
		var button: Button
		if claimed:
			button = Kit.button("正在使用" if id == equipped else "应用界面样式", func(): _send(dispatch, "equip_style", {"id":id}), id != equipped)
			button.disabled = id == equipped
		else:
			button = Kit.button("免费领取" if eligible else "尚未达到进度", func(): _send(dispatch, "claim_style", {"id":id}), eligible)
			button.disabled = not eligible
		card.add_child(button)
		styles.add_child(card)
	root.add_child(Kit.label("模块探索目录", 24, Kit.TEXT))
	root.add_child(Kit.label("以下来自当前机库的真实解锁条件。拥有模块即已可用，无需到这里再次领取。", 14, Kit.MUTED))
	var owned: Dictionary = Hangar.ownership(ctx.get("profile", {}))
	var modules: Dictionary = Catalog.modules()
	for id: String in modules:
		if id in owned.get("starter_modules", []): continue
		_module_row(root, module_info(ctx, id), dispatch)
	root.add_child(_nav("返回基地", "base", dispatch))

static func _frame_selector(root: VBoxContainer, ctx: Dictionary, dispatch: Callable) -> void:
	var block: HBoxContainer = Kit.row(12)
	block.add_child(Kit.label("适配机体", 14, Kit.MUTED))
	var chooser := OptionButton.new()
	chooser.custom_minimum_size.y = 44
	chooser.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chooser.focus_mode = Control.FOCUS_ALL
	var selected: String = str(ctx.get("frame_id", "tr01"))
	var frames: Dictionary = Catalog.airframes()
	for id: String in Hangar.FRAME_ORDER:
		chooser.add_item(id.to_upper()+" · "+str(frames.get(id, {}).get("name", id)))
		chooser.set_item_metadata(chooser.item_count-1, id)
		if id == selected: chooser.select(chooser.item_count-1)
	chooser.disabled = bool(ctx.get("active", false))
	chooser.tooltip_text = "飞行中的当前机体保持不变。" if chooser.disabled else "选择机体后，适配状态按该机体保存的五槽配装重新计算。"
	chooser.item_selected.connect(func(index: int): _send(dispatch, "select_frame", {"frame_id":str(chooser.get_item_metadata(index))}))
	block.add_child(chooser)
	root.add_child(block)

static func _filters(root: VBoxContainer, ctx: Dictionary, dispatch: Callable) -> void:
	var selection: Dictionary = ctx.get("selection", {})
	var filters: HBoxContainer = Kit.row(12)
	var slots: Array = [{"id":"all", "name":"全部槽位"}]
	for id: String in Catalog.SLOT_ORDER: slots.append({"id":id, "name":str(Hangar.SLOT_NAMES[id])})
	filters.add_child(_filter(slots, "equipment_slot", str(selection.get("equipment_slot", "all")), dispatch))
	filters.add_child(_filter([{"id":"all", "name":"全部模块"}, {"id":"owned", "name":"已拥有"}, {"id":"locked", "name":"待解锁"}, {"id":"fit", "name":"当前可安装"}], "equipment_owned", str(selection.get("equipment_owned", "all")), dispatch))
	root.add_child(filters)
	var search: HBoxContainer = Kit.row(10)
	var query := LineEdit.new()
	query.placeholder_text = "搜索模块名称或探索来源，回车确认"
	query.text = str(selection.get("equipment_query", ""))
	query.custom_minimum_size.y = 44
	query.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	query.text_submitted.connect(func(value: String): _send(dispatch, "page_filter", {"key":"equipment_query", "value":value.strip_edges()}))
	search.add_child(query)
	var button: Button = Kit.button("搜索", func(): _send(dispatch, "page_filter", {"key":"equipment_query", "value":query.text.strip_edges()}))
	button.size_flags_horizontal = Control.SIZE_SHRINK_END
	search.add_child(button)
	root.add_child(search)

static func _filter(rows: Array, key: String, selected: String, dispatch: Callable) -> OptionButton:
	var picker := OptionButton.new()
	picker.custom_minimum_size.y = 44
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.focus_mode = Control.FOCUS_ALL
	for row: Dictionary in rows:
		picker.add_item(str(row.name))
		picker.set_item_metadata(picker.item_count-1, str(row.id))
		if str(row.id) == selected: picker.select(picker.item_count-1)
	picker.item_selected.connect(func(index: int): _send(dispatch, "page_filter", {"key":key, "value":str(picker.get_item_metadata(index))}))
	return picker

static func _module_row(parent: VBoxContainer, info: Dictionary, dispatch: Callable, eyebrow: String = "") -> void:
	var panel: PanelContainer = Kit.panel()
	var body: VBoxContainer = Kit.column(8)
	panel.add_child(body)
	if not eyebrow.is_empty(): body.add_child(Kit.label(eyebrow, 11, Kit.ACCENT))
	var top: HBoxContainer = Kit.row(14)
	var names: VBoxContainer = Kit.column(5)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_child(Kit.label(str(info.title), 20, Kit.TEXT))
	names.add_child(Kit.label(str(Hangar.SLOT_NAMES.get(str(info.get("slot", "")), "模块"))+" · "+str(info.status), 12, Kit.ACCENT if info.get("owned", false) else Kit.GOLD))
	top.add_child(names)
	var id: String = str(info.get("id", ""))
	var detail: Button = Kit.button("查看详情", func(): _send(dispatch, "inspect_module", {"id":id}))
	detail.size_flags_horizontal = Control.SIZE_SHRINK_END
	top.add_child(detail)
	body.add_child(top)
	body.add_child(Kit.label(str(info.stats), 14, Kit.MUTED))
	body.add_child(Kit.label("来源 · "+str(info.source).replace("\n", " / "), 12, Kit.MUTED))
	parent.add_child(panel)

static func _effect_text(effects: Dictionary) -> String:
	var lines := PackedStringArray()
	if effects.has("speed_multiplier"): lines.append("速度参数 ×%.2f" % float(effects.speed_multiplier))
	if effects.has("accel_multiplier"): lines.append("加速参数 ×%.2f" % float(effects.accel_multiplier))
	if effects.has("cooling_multiplier"): lines.append("冷却参数 ×%.2f" % float(effects.cooling_multiplier))
	if effects.has("cargo_damping_multiplier"): lines.append("载货阻尼 ×%.2f" % float(effects.cargo_damping_multiplier))
	if effects.has("winch_speed_multiplier"): lines.append("绞盘速度参数 ×%.2f" % float(effects.winch_speed_multiplier))
	if effects.has("envelope_padding_each_side_m"): lines.append("每侧外形增加 %.2f m" % float(effects.envelope_padding_each_side_m))
	if effects.has("night_scan_time_multiplier"): lines.append("夜间扫描耗时参数 ×%.2f" % float(effects.night_scan_time_multiplier))
	if effects.has("tool_range_m"): lines.append("工具范围参数 %.1f m" % float(effects.tool_range_m))
	if effects.has("light_range_m"): lines.append("照明范围参数 %.0f m" % float(effects.light_range_m))
	if effects.has("weapon_charge_s") and float(effects.weapon_charge_s) > 0.0: lines.append("蓄力 %.1f s · 松开取消" % float(effects.weapon_charge_s))
	return " · ".join(lines)

static func _loadout(ctx: Dictionary) -> Dictionary:
	return Hangar.launch_build(ctx.get("profile", {}), str(ctx.get("frame_id", "")))

static func _loadout_caption(selected: Dictionary) -> String:
	if not selected.get("ok", false): return Hangar.error_text(selected)
	var stats: Dictionary = selected.resolved.derived
	var id: String = str(selected.build.airframe_id)
	var frame: Dictionary = Catalog.airframes().get(id, {})
	return "%s · %s\n起飞质量 %.2f / %.2f kg · 供电 %.0f / %.0f PU · 额定载荷 %.1f kg" % [id.to_upper(), str(frame.get("name", id)), float(stats.mass_kg), float(frame.get("max_takeoff_mass_kg", 0.0)), float(stats.power_pu), float(stats.capacity_pu), float(stats.cargo_rating_kg)]

static func _completed(ctx: Dictionary) -> int:
	var rows: Variant = ctx.get("profile", {}).get("world", {}).get("actions", {}).get("opening", {}).get("completed", [])
	return rows.size() if rows is Array else 0

static func _style_claimed(settings: Dictionary, id: String) -> bool:
	if id == "harbor": return true
	var claimed: Variant = settings.get("claimed_styles", [])
	return id in claimed if claimed is Array else bool(claimed.get(id, false)) if claimed is Dictionary else false

static func _nav(text: String, page: String, dispatch: Callable, primary: bool = false) -> Button:
	return Kit.button(text, func(): _send(dispatch, "navigate", {"page":page}), primary)

static func _send(dispatch: Callable, action: String, payload: Dictionary) -> void:
	if dispatch.is_valid(): dispatch.call(action, payload)
