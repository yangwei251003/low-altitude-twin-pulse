extends RefCounted
## Journey pages only read snapshots. The front coordinator owns every action.
const Kit = preload("res://scripts/v3/ui/front/twin_front_kit.gd")
const Regions = preload("res://scripts/v3/world/twin_region_catalog.gd")
const Director = preload("res://scripts/v3/gameplay/actions/twin_action_director.gd")
const Campaign = preload("res://scripts/v3/campaign/twin_campaign_catalog.gd")
const Frames = preload("res://scripts/v2/catalog.gd")
const OldJobs = preload("res://scripts/v3/ecology/twin_npc_sidejob_state.gd")
const Field = preload("res://scripts/v3/content/npc_story_next/twin_npc_story_catalog.gd")
const Stories = preload("res://scripts/v3/content/dev88_story/twin_side_story_catalog.gd")
const Rewards = preload("res://scripts/v3/content/dev88_progression/twin_dev88_rewards.gd")
const Combat = preload("res://scripts/v3/content/dev88_combat/twin_combat_sites_catalog.gd")
const CombatState = preload("res://scripts/v3/content/dev88_combat/twin_combat_sites_state.gd")
const FinalStory = preload("res://scripts/v3/content/final_story/twin_final_story_catalog.gd")
const Anchors = preload("res://scripts/v3/ecology/twin_npc_anchors.gd")
const ORDER := ["I1","F1","I2","F2","I3","F3","I4","F4"]
const SHORT_NAMES := {"I1":"潮湾科技港","F1":"巨木神殿","I2":"潮汐水城","F2":"镜湖悬庭","I3":"热崖制造带","F3":"鸣菌幽谷","I4":"离岸阵列","F4":"天脉冠峰"}
const BOSSES := {"I1":"抽能鲸机","F1":"寄生冠兽","I2":"双泵守卫","F2":"折翼守望者","I3":"熔炉履带兽","F3":"鸣菌共生体","I4":"棱镜防御阵列","F4":"共脉中枢"}
const REGION_ACTIONS := {"I2":"I2:twin_pump_guardian","F2":"F2:mirrorwing_warden","I3":"I3:furnace_crawler","F3":"F3:mycelial_choir","I4":"I4:prism_array","F4":"F4:twin_vein_core"}
const OPEN_FROM := {"I2":"I1:underdeck","F2":"I2:twin_pump_guardian","I3":"F2:mirrorwing_warden","F3":"I3:furnace_crawler","I4":"F3:mycelial_choir","F4":"I4:prism_array"}
const DESCRIPTIONS := {
	"I1":"从港口救援与第一声跨界呼叫起步，留下原始指令与可用返程。",
	"F1":"沿活根、枝桥与育苗棚辨认两岸共同的需要，解除寄生控制。",
	"I2":"病房供水、居民通路与南湾工序各有去处，轮换安排由小队共同决定。",
	"F2":"用真实光路核对原件与时间线，沿高低悬庭接回末班的灯。",
	"I3":"冷却、制动、真实载荷与换班相连，交付之后还要留好返程。",
	"F3":"分清命令与养分，留下授粉、育苗和不同花期继续生活的路。",
	"I4":"在风与光路中保住应急，留下可核查的上限、例外与下一班。",
	"F4":"接住工业与活体两路底线，读清三种方案，再留下自己的签名。"}
static var _actions: Array = []
static var _choice_data: Dictionary = {}
static var _old_data: Dictionary = {}
static var _names: Dictionary = {}

class RouteChart extends Control:
	var nodes: Dictionary = {}
	var links: Array = []
	var points: Dictionary = {}

	func _ready() -> void:
		resized.connect(_arrange)
		_arrange()

	func _arrange() -> void:
		var wide: bool = size.x >= 640.0
		var required_height: float = 224.0 if wide else 386.0
		if not is_equal_approx(custom_minimum_size.y,required_height): custom_minimum_size.y = required_height
		var width: float = minf(174.0,maxf(72.0,size.x/(5.0 if wide else 2.5)))
		for id: String in nodes:
			var index: int = int(id.substr(1))-1
			var fantasy: bool = id.begins_with("F")
			var at: Vector2
			if wide: at = Vector2(size.x*(.13+.245*index),62.0 if not fantasy else 166.0)
			else: at = Vector2(size.x*(.26+.48*(index%2)),50.0+88.0*(index/2)+(176.0 if fantasy else 0.0))
			points[id] = at
			var button: Button = nodes[id]
			button.position = at-Vector2(width*.5,31)
			button.size = Vector2(width,62)
		queue_redraw()

	func _draw() -> void:
		for edge: Dictionary in links:
			if not points.has(edge.from) or not points.has(edge.to): continue
			var color := Color("4b8d83") if bool(edge.open) else Color("2a4650")
			draw_line(points[edge.from],points[edge.to],color,2.0,true)
			var middle: Vector2 = points[edge.from].lerp(points[edge.to],.5)
			draw_circle(middle,3.0,color)

static func build(page: String, ctx: Dictionary, dispatch: Callable) -> Control:
	var body: VBoxContainer = Kit.column(20)
	body.name = "Journey_"+page
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	match page:
		"profile": _profile_page(body,ctx,dispatch)
		"map": _map_page(body,ctx,dispatch)
		"missions": _missions_page(body,ctx,dispatch)
		"events": _events_page(body,ctx,dispatch)
		"results": _results_page(body,ctx,dispatch)
		_:
			body.add_child(Kit.heading("还没有这一页","JOURNEY","返回大厅，继续准备下一次出航。"))
			body.add_child(Kit.button("返回大厅",func(): _go(dispatch,"home"),true))
	return body

static func _profile_page(body: VBoxContainer, ctx: Dictionary, dispatch: Callable) -> void:
	var profile: Dictionary = _profile(ctx)
	var state: Dictionary = _story(ctx)
	var current: String = _current_region(ctx)
	var settings: Dictionary = _dictionary(ctx.get("settings",{}))
	var nickname: String = str(settings.get("profile_name",settings.get("nickname",settings.get("name","低空飞行员"))))
	body.add_child(Kit.heading(nickname,"PILOT DOSSIER · 个人履历",_ownership(ctx)))
	var hero: VBoxContainer = Kit.card("每一次回应，都留在这里",_current_story_text(state),"当前旅程")
	var metrics: HBoxContainer = Kit.row(20)
	metrics.add_child(Kit.metric(str(_completed_goals(state))+" / "+str(_total_goals()),"已留下的主线目标"))
	metrics.add_child(Kit.metric(str(_array(state.get("completed_actions",[])).size()),"已完成行动"))
	metrics.add_child(Kit.metric(str(_discoveries(ctx).size()),"个人发现记录"))
	metrics.add_child(Kit.metric(str(_visited_count(ctx))+" / 8","已有到访记录的地区"))
	hero.add_child(metrics)
	hero.add_child(_progress(_completed_goals(state),_total_goals()))
	var actions: HBoxContainer = Kit.row()
	actions.add_child(Kit.button("继续这段旅程",func(): _continue(ctx,dispatch),true))
	actions.add_child(Kit.button("查看任务",func(): _go(dispatch,"missions")))
	hero.add_child(actions)
	body.add_child(hero)
	var details: GridContainer = Kit.grid(2)
	var identity: VBoxContainer = Kit.card("本机称呼","这会修改大厅显示的昵称。","身份")
	var name_row: HBoxContainer = Kit.row(8)
	var edit := LineEdit.new()
	edit.text = nickname
	edit.placeholder_text = "输入你的称呼"
	edit.max_length = 24
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.custom_minimum_size.y = 46
	edit.add_theme_font_override("font",Kit.font())
	edit.add_theme_stylebox_override("normal",Kit.box(Color("0b242d"),Kit.LINE,8,12))
	edit.add_theme_stylebox_override("focus",Kit.box(Color("102e37"),Kit.ACCENT,8,12))
	edit.add_theme_color_override("font_color",Kit.TEXT)
	edit.text_submitted.connect(func(value: String): dispatch.call("profile_name",{"name":value}))
	name_row.add_child(edit)
	name_row.add_child(Kit.button("保存昵称",func(): dispatch.call("profile_name",{"name":edit.text})))
	identity.add_child(name_row)
	identity.add_child(Kit.label("最近驻地 · "+_region_name(current),14,Kit.MUTED))
	var saved: String = str(profile.get("saved_at_utc",""))
	identity.add_child(Kit.label("最近保存 · "+(_saved_time(saved) if not saved.is_empty() else "出航并保存后记录"),13,Kit.MUTED))
	details.add_child(identity)
	var choices: VBoxContainer = Kit.card("一起留下的决定","只展示已经明确签署的安排。","共同记录")
	var selected: Array = _choice_rows(state)
	if selected.is_empty(): choices.add_child(Kit.label("下一次选择到来时，先读清收益与负担；已签的结果会留在这里。",14,Kit.MUTED))
	for entry: Dictionary in selected:
		choices.add_child(Kit.label(str(entry.title),16,Kit.ACCENT))
		choices.add_child(Kit.label(str(entry.text),13,Kit.MUTED))
	if FinalStory.ending_ready(state): choices.add_child(Kit.button("重读终章留档",func(): _legacy(dispatch,"ending_book")))
	details.add_child(choices)
	body.add_child(details)
	_branch_panel(body,ctx,dispatch)
	body.add_child(Kit.heading("已经走过的地方","ROUTE MEMORY","按保存的到访与行动记录排列；开放航路不等于已经到过。"))
	var places: GridContainer = Kit.grid(2)
	for region: String in ORDER:
		if not _visited(ctx,region): continue
		var progress: Dictionary = _region_progress(state,region)
		var place: VBoxContainer = Kit.card(_region_name(region),"主线记录 %d / %d · %s" % [int(progress.done),int(progress.total),"首领停机已记录" if _boss_done(state,region) else "继续本区调查"],region)
		place.add_child(Kit.button("查看航图",func(): _region_page(dispatch,"map",region)))
		places.add_child(place)
	if places.get_child_count() == 0: body.add_child(Kit.label("尚无到访记录。先从潮湾科技港出航，履历会随你的实际行动留下。",15,Kit.MUTED))
	else: body.add_child(places)

static func _map_page(body: VBoxContainer, ctx: Dictionary, dispatch: Callable) -> void:
	var state: Dictionary = _story(ctx)
	var current: String = _current_region(ctx)
	var selected: String = str(_selection(ctx).get("map_region",current if current in ORDER else "I1"))
	if selected not in ORDER: selected = "I1"
	body.add_child(Kit.heading("两界航图","WORLD ATLAS · 八区航路","浏览所有地区，沿实际开放的相邻航路出发。跨区仍由原房主与共同确认规则决定。"))
	var chart := RouteChart.new()
	chart.custom_minimum_size.y = 224
	chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var drawn: Dictionary = {}
	for region: String in ORDER:
		var id: String = region
		var status: String = "当前" if region == current else ("已到访" if _visited(ctx,region) else ("已开放" if _unlocked(ctx,region) else "未开放"))
		var tile: Button = Kit.button(region+" · "+status+"\n"+str(SHORT_NAMES[region]),func(): dispatch.call("page_filter",{"key":"map_region","value":id}),region == selected)
		tile.add_theme_font_size_override("font_size",13)
		chart.add_child(tile)
		chart.nodes[region] = tile
		for destination: String in Regions.destinations(region):
			var reverse: String = destination+":"+region
			if drawn.has(reverse): continue
			drawn[region+":"+destination] = true
			chart.links.append({"from":region,"to":destination,"open":_unlocked(ctx,region) and _unlocked(ctx,destination)})
	body.add_child(chart)
	var destination: VBoxContainer = Kit.card(_region_name(selected),str(DESCRIPTIONS.get(selected,"")),"工业岸" if selected.begins_with("I") else "幻境岸")
	var status_row: HBoxContainer = Kit.row(18)
	var progress: Dictionary = _region_progress(state,selected)
	var secrets: Dictionary = _secret_progress(ctx,selected)
	status_row.add_child(Kit.metric(str(progress.done)+" / "+str(progress.total),"本区主线目标"))
	status_row.add_child(Kit.metric(str(secrets.found)+" / "+str(secrets.total),"已找到的现场秘密"))
	status_row.add_child(Kit.metric("已停机" if _boss_done(state,selected) else "未记停机",str(BOSSES[selected])))
	destination.add_child(status_row)
	destination.add_child(Kit.label(_travel_reason(ctx,selected),15,Kit.ACCENT if _unlocked(ctx,selected) else Kit.GOLD))
	var buttons: HBoxContainer = Kit.row()
	if _active(ctx) and selected == current:
		buttons.add_child(Kit.button("返回当前飞行",func(): _legacy(dispatch,"resume"),true))
	elif _travel_available(ctx,selected):
		buttons.add_child(Kit.button("前往此区",func(): _legacy(dispatch,"travel_to",{"region_id":selected}),true))
	elif not _active(ctx): buttons.add_child(Kit.button("准备出航",func(): _go(dispatch,"modes"),true))
	buttons.add_child(Kit.button("查看本区任务",func(): _region_page(dispatch,"missions",selected)))
	buttons.add_child(Kit.button("查看探索记录",func(): _region_page(dispatch,"events",selected)))
	destination.add_child(buttons)
	body.add_child(destination)
	var links: PackedStringArray = []
	for neighbor: String in Regions.destinations(selected): links.append(_region_name(neighbor))
	body.add_child(Kit.label("相邻航路 · "+" / ".join(links)+"\n青绿连线表示两端已有开放记录；实际出航仍核对当前地区、设施与共同决定。",13,Kit.MUTED))

static func _missions_page(body: VBoxContainer, ctx: Dictionary, dispatch: Callable) -> void:
	var selection: Dictionary = _selection(ctx)
	var kind: String = str(selection.get("mission_kind","main"))
	var region: String = str(selection.get("mission_region","all"))
	var status_filter: String = str(selection.get("mission_status","all"))
	body.add_child(Kit.heading("下一次，向哪里回应","MISSIONS · 主线与支线",_ownership(ctx)))
	var state: Dictionary = _story(ctx)
	var current_action: Dictionary = _current_action(state)
	var lead: VBoxContainer = Kit.card(str(current_action.get("title","共同修复记录已留存")),_current_story_text(state),"当前主线")
	var lead_actions: HBoxContainer = Kit.row()
	lead_actions.add_child(Kit.button("追踪当前主线" if _active(ctx) else "出航后继续",func(): _track_main(ctx,dispatch),true))
	lead_actions.add_child(Kit.button("飞行与能力手册",func(): _legacy(dispatch,"handbook")))
	lead_actions.add_child(Kit.button("自动驾驶辅助",func(): dispatch.call("navigate",{"page":"assist"})))
	lead.add_child(lead_actions)
	body.add_child(lead)
	var tabs: HBoxContainer = Kit.row(6)
	for tab: Array in [["main","主线行动"],["side","伙伴委托"],["exploration","现场探索"],["combat","战斗遭遇"],["archives","回访留档"]]:
		var value: String = tab[0]
		tabs.add_child(Kit.button(str(tab[1]),func(): dispatch.call("page_filter",{"key":"mission_kind","value":value}),kind == value))
	body.add_child(tabs)
	var filters: HBoxContainer = Kit.row()
	filters.add_child(_region_selector(region,"mission_region",dispatch))
	filters.add_child(_selector([["all","全部状态"],["active","进行中 / 可交接"],["available","可开始"],["complete","已完成"],["locked","待开放 / 待同步"]],status_filter,"mission_status",dispatch))
	body.add_child(filters)
	var rows: Array = _mission_rows(ctx,kind)
	var visible_rows := 0
	for row: Dictionary in rows:
		if region != "all" and str(row.region) != region: continue
		if not _status_matches(str(row.status),status_filter): continue
		visible_rows += 1
		var item: VBoxContainer = Kit.card(str(row.title),_plain(str(row.get("text",""))),_region_name(str(row.region))+" · "+_status_name(str(row.status)))
		if kind == "main":
			var count: Dictionary = row.get("progress",{})
			item.add_child(_progress(int(count.get("done",0)),int(count.get("total",0))))
			var expanded: bool = str(selection.get("mission_action",current_action.get("id",""))) == str(row.id)
			if expanded:
				var next_pending:=true
				for goal: Dictionary in row.get("objectives",[]):
					item.add_child(Kit.label(("✓  " if bool(goal.done) else "○  ")+str(goal.text),15,Kit.ACCENT if bool(goal.done) else Kit.TEXT))
					if not bool(goal.done):
						item.add_child(Kit.label(_plain(str(goal.hint)),13,Kit.MUTED))
						var available: bool=next_pending and str(row.id)==str(current_action.get("id",""))
						var assist:=Kit.button("人机辅助完成此目标" if available else "辅助待前置目标完成",func(): dispatch.call("assist_start",{"scope":"objective"}))
						assist.disabled=not available
						assist.tooltip_text="从当前真实进度执行，不跳过前置或自动填写完成记录。"
						item.add_child(assist)
						next_pending=false
			var action_id: String = row.id
			item.add_child(Kit.button("收起目标" if expanded else "查看目标",func(): dispatch.call("page_filter",{"key":"mission_action","value":"" if expanded else action_id})))
		_add_row_actions(item,row,ctx,dispatch)
		body.add_child(item)
	if visible_rows == 0: body.add_child(Kit.card("这一筛选下还没有记录","可以切换地区或状态；任务与发现都随实际行动保存。"))
	if _is_guest(ctx): body.add_child(Kit.button("打开房主同步纪事",func(): _legacy(dispatch,"journal")))

static func _events_page(body: VBoxContainer, ctx: Dictionary, dispatch: Callable) -> void:
	var selected: String = str(_selection(ctx).get("event_region","all"))
	var state: Dictionary = _story(ctx)
	body.add_child(Kit.heading("把探索变成下一次准备","FIELD MILESTONES · 活动与里程碑","来自当前记录的长期探索活动。现场发现会打开现有模块的另一条解锁途径。"))
	var completed := 0
	var unlocks: Array = Rewards.unlocks(_discoveries(ctx))
	for entry: Dictionary in unlocks:
		if bool(entry.owned): completed += 1
	var summary: VBoxContainer = Kit.card("八区现场探索", "每区四处独立线索。不同高度、能力与支路都可能留下新的记录。", "长期活动")
	var metrics: HBoxContainer = Kit.row(20)
	metrics.add_child(Kit.metric(str(completed)+" / 8","已集齐的地区记录"))
	metrics.add_child(Kit.metric(str(_known_secrets(ctx))+" / "+str(Rewards.notes().size()),"已找到的独立秘密"))
	metrics.add_child(Kit.metric(str(_boss_count(state))+" / 8","主线首领停机记录"))
	summary.add_child(metrics)
	var explore := func():
		dispatch.call("page_filter",{"key":"mission_kind","value":"exploration"})
		_go(dispatch,"missions")
	summary.add_child(Kit.button("查看探索任务",explore,true))
	body.add_child(summary)
	body.add_child(_region_selector(selected,"event_region",dispatch))
	var grid: GridContainer = Kit.grid(2)
	for entry: Dictionary in unlocks:
		var region: String = str(entry.region)
		if selected != "all" and region != selected: continue
		var module: String = str(entry.module_id)
		var found: bool = bool(entry.owned)
		var card: VBoxContainer = Kit.card(_region_name(region),"集齐本区现场记录，可在机库使用「"+_module_name(module)+"」的探索解锁。", "已达成" if found else ("探索中" if int(entry.found)>0 else "尚待探索"))
		card.add_child(Kit.label(str(entry.found)+" / "+str(entry.total),27,Kit.ACCENT if found else Kit.TEXT))
		card.add_child(_progress(int(entry.found),int(entry.total)))
		if found: card.add_child(Kit.button("查看已解锁模块",func(): dispatch.call("inspect_module",{"id":module})))
		else:
			var find := func():
				dispatch.call("page_filter",{"key":"mission_kind","value":"exploration"})
				_region_page(dispatch,"missions",region)
			card.add_child(Kit.button("寻找本区线索",find))
		grid.add_child(card)
	body.add_child(grid)
	body.add_child(Kit.heading("八场停机之后","CHAPTER MILESTONES","来自主线已经提交的停机记录；回访不会重复领取同一份发现。"))
	var boss_grid: GridContainer = Kit.grid(2)
	for region: String in ORDER:
		if selected != "all" and region != selected: continue
		var done: bool = _boss_done(state,region)
		var boss: VBoxContainer = Kit.card(str(BOSSES[region]),_region_name(region)+" · "+("停机记录已经留下。" if done else "沿原主线调查与战区继续。"),"已记录" if done else "待行动")
		boss.add_child(Kit.button("查看地区任务",func(): _region_page(dispatch,"missions",region)))
		boss_grid.add_child(boss)
	body.add_child(boss_grid)
	if FinalStory.ending_ready(state):
		var ending: VBoxContainer = Kit.card("终章已经签署","三种未来只留下你们实际选择的那一份。回访与日常仍可继续。","共同决定")
		ending.add_child(Kit.button("重读终章与角色去向",func(): _legacy(dispatch,"ending_book"),true))
		body.add_child(ending)

static func _results_page(body: VBoxContainer, ctx: Dictionary, dispatch: Callable) -> void:
	var summary: Dictionary = _dictionary(ctx.get("summary",{}))
	if not bool(summary.get("available",not summary.is_empty())):
		body.add_child(Kit.heading("下一次出航，会从这里留下","FLIGHT DEBRIEF · 出航记录","完成一次实际出航并返回后，这里展示那一趟留下的新目标、发现与任务交接。"))
		var empty: VBoxContainer = Kit.card("还没有本次出航结算","你已有的履历与发现都保留在个人页面。","准备下一程")
		var row: HBoxContainer = Kit.row()
		row.add_child(Kit.button("准备出航",func(): _go(dispatch,"modes"),true))
		row.add_child(Kit.button("查看个人履历",func(): _go(dispatch,"profile")))
		empty.add_child(row)
		body.add_child(empty)
		return
	var region: String = str(summary.get("region_id",""))
	body.add_child(Kit.heading(str(summary.get("title","本次出航记录")),"FLIGHT DEBRIEF · 最近一次出航",_region_name(region)+" · "+_mode_name(str(summary.get("mode","")))))
	var report: VBoxContainer = Kit.card("这一趟留下了什么",str(summary.get("description","本页只汇总这次实际出航产生的记录。已有履历与装备继续保留。")),"出航回顾")
	var metrics: HBoxContainer = Kit.row(20)
	metrics.add_child(Kit.metric(_duration(summary.get("duration_seconds")),"实际出航用时"))
	metrics.add_child(Kit.metric(_array_count(summary,"objective_ids"),"新增主线目标"))
	metrics.add_child(Kit.metric(_array_count(summary,"discovery_ids"),"新增个人发现"))
	metrics.add_child(Kit.metric(_array_count(summary,"completed_missions"),"本次任务交接"))
	report.add_child(metrics)
	var frame: String = str(summary.get("frame_id",ctx.get("frame_id","")))
	if not frame.is_empty(): report.add_child(Kit.label("出航机体 · "+_frame_name(frame),14,Kit.MUTED))
	var buttons: HBoxContainer = Kit.row()
	buttons.add_child(Kit.button("继续飞行" if _active(ctx) else "准备下一次出航",func(): _continue(ctx,dispatch),true))
	buttons.add_child(Kit.button("查看仓库",func(): _go(dispatch,"inventory")))
	buttons.add_child(Kit.button("返回大厅",func(): _go(dispatch,"home")))
	report.add_child(buttons)
	body.add_child(report)
	var changes: GridContainer = Kit.grid(2)
	var goals: VBoxContainer = Kit.card("主线推进","本次实际新增的目标记录。","旅程")
	_add_summary_list(goals,summary,"objective_ids","本次没有新增主线目标；已有成果保留。",true)
	changes.add_child(goals)
	var discoveries: VBoxContainer = Kit.card("新的发现","以个人发现收据为准。","探索")
	_add_summary_list(discoveries,summary,"discovery_ids","本次没有新增个人发现；已有记录保留。",false)
	changes.add_child(discoveries)
	body.add_child(changes)
	var mission_card: VBoxContainer = Kit.card("任务交接","这一趟真正完成交接的委托。","伙伴")
	_add_summary_list(mission_card,summary,"completed_missions","本次没有新的任务交接；进行中的委托可以继续。",false)
	body.add_child(mission_card)
	var stats: Dictionary = _dictionary(summary.get("stats",{}))
	var statistics: HBoxContainer = Kit.row(20)
	for pair: Array in [["shots","实际发射"],["abilities","能力使用"],["hits","记录命中"]]:
		if stats.has(pair[0]) and (stats[pair[0]] is int or stats[pair[0]] is float): statistics.add_child(Kit.metric(str(int(stats[pair[0]])),str(pair[1])))
	if statistics.get_child_count()>0: body.add_child(statistics)

static func _mission_rows(ctx: Dictionary, kind: String) -> Array:
	if kind == "main": return _main_rows(_story(ctx))
	if kind == "side": return _side_rows(ctx)
	if kind == "exploration": return _exploration_rows(ctx)
	if kind == "combat": return _combat_rows(ctx)
	if kind == "archives":
		var result: Array = []
		for entry: Dictionary in FinalStory.journal_rows(_story(ctx),_world(ctx)):
			result.append({"id":entry.id,"region":entry.region,"title":entry.title,"status":"available","text":"\n".join(PackedStringArray(entry.lines)),
				"category":"archives","anchor":{"anchor_id":entry.target_id,"region":entry.region,"position":entry.position.duplicate(),"label":entry.title}})
		return result
	return []

static func _main_rows(state: Dictionary) -> Array:
	var rows: Array = []
	var done: Array = _array(state.get("completed",[]))
	var actions_done: Array = _array(state.get("completed_actions",[]))
	for action: Dictionary in _definitions():
		var objectives: Array = []
		var count := 0
		for objective: Dictionary in action.get("objectives",[]):
			var completed: bool = str(objective.id) in done
			if completed: count += 1
			objectives.append({"id":str(objective.get("id","")),"text":str(objective.get("text","")),"hint":str(objective.get("hint","")),"done":completed})
		var complete: bool = str(action.id) in actions_done
		var ready := true
		var missing := PackedStringArray()
		for prerequisite: String in action.get("prerequisites",[]):
			if prerequisite not in actions_done:
				ready = false
				missing.append(_action_name(prerequisite))
		var status: String = "complete" if complete else ("active" if ready else "locked")
		var text: String = str(action.get("completion_text","行动记录已保留。")) if complete else ("先完成："+"、".join(missing) if not ready else "按当前目标继续调查、交互与行动。")
		rows.append({"id":str(action.id),"region":str(action.region_id),"title":str(action.title),"category":"main","status":status,
			"text":text,"progress":{"done":count,"total":objectives.size()},"objectives":objectives})
	return rows

static func _side_rows(ctx: Dictionary) -> Array:
	var doc: Dictionary = _journal(ctx)
	var from_journal: Array = _journal_section(doc,"伙伴与支线","side")
	if not from_journal.is_empty(): return from_journal
	var result: Array = []
	var world: Dictionary = _world(ctx)
	var old: Dictionary = OldJobs.restore(world.get("npc_sidejobs_v1",{}))
	for id: String in OldJobs.SPECS:
		var spec: Dictionary = OldJobs.SPECS[id]
		var row: Dictionary = old.get("state",{}).get("jobs",{}).get(id,{})
		var definition: Dictionary = _old_specs().get(id,{})
		var status: String = str(row.get("status","available")) if old.get("ok",false) else "unavailable"
		if _is_guest(ctx) and not world.has("npc_sidejobs_v1"): status = "unavailable"
		result.append({"id":id,"region":str(spec.region),"title":str(definition.get("title","同伴委托")),"category":"side","status":status,
			"text":str(definition.get("consequence","")) if status == "complete" else str(definition.get("work_hint","靠近本区活动同伴，主动联络。")),
			"anchor":_actor_anchor(ctx,str(spec.npc),str(spec.region),str(definition.get("title","同伴委托")))})
	var fields: Dictionary = _dictionary(_dictionary(world.get("field_requests_next_v1",{})).get("jobs",{}))
	for region: String in Field.REGIONS:
		var spec: Dictionary = Field.definition(region)
		var row: Dictionary = _dictionary(fields.get(region,{}))
		var status := "available"
		if not row.is_empty(): status = "complete" if row.get("complete") == true else ("ready" if int(row.get("survey_bits",0)) == 3 and not str(row.get("native_event_id","")).is_empty() else "active")
		elif _is_guest(ctx) and not world.has("field_requests_next_v1"): status = "unavailable"
		result.append({"id":"field:"+region,"region":region,"title":str(spec.title),"category":"side","status":status,
			"text":"已交接；可回访，原发现保留。" if status == "complete" else str(spec.work_hint),
			"anchor":_known_anchor(ctx,Field.contact_id(region),region,str(spec.title),[-29,5.8,18])})
	var saved: Dictionary = _dictionary(_dictionary(world.get("side_stories_dev88_v1",{})).get("jobs",{}))
	for spec: Dictionary in Stories.definitions():
		var row: Dictionary = _dictionary(saved.get(str(spec.id),{}))
		var prerequisite: String = Stories.prerequisite_text(spec,_story(ctx))
		var status: String = "available" if prerequisite.is_empty() else "locked"
		var text: String = str(spec.offer[0]) if not spec.get("offer",[]).is_empty() else "先联络，再决定是否接单。"
		var anchor: Dictionary = _known_anchor(ctx,str(spec.contact.id),str(spec.region),str(spec.title),spec.contact.position)
		if not prerequisite.is_empty(): text = prerequisite
		if not row.is_empty():
			var stage_index: int = int(row.get("stage",0))
			if row.get("complete") == true:
				status = "complete"
				text = "已经交接，原发现保留；可以回来听同伴的后续。"
			elif stage_index >= spec.stages.size():
				status = "ready"
				text = "现场步骤已记录，回委托台主动联络交接。"
			else:
				status = "active"
				var stage: Dictionary = spec.stages[maxi(0,stage_index)]
				text = "%d / %d · %s" % [stage_index+1,spec.stages.size(),str(stage.get("hint",stage.get("label","")))]
				anchor = _stage_anchor(ctx,spec,stage,row)
		elif _is_guest(ctx) and not world.has("side_stories_dev88_v1"): status = "unavailable"
		result.append({"id":str(spec.id),"region":str(spec.region),"title":str(spec.title),"category":"side","status":status,"text":text,"anchor":anchor})
	return result

static func _exploration_rows(ctx: Dictionary) -> Array:
	var rows: Array = []
	var discoveries: Array = _discoveries(ctx)
	for note: Dictionary in Rewards.notes():
		var found: bool = str(note.discovery_id) in discoveries
		rows.append({"id":str(note.id),"region":str(note.region),"title":str(note.title) if found else str(note.label),"category":"exploration",
			"status":"complete" if found else ("available" if _unlocked(ctx,str(note.region)) else "locked"),
			"text":"\n".join(PackedStringArray(note.lines)) if found else "沿本区不同高度与支路观察现场痕迹；靠近后主动调查。尚未发现的线索保留探索的余地。",
			"anchor":_known_anchor(ctx,str(note.id),str(note.region),str(note.title),note.position) if found else {}})
	return rows

static func _combat_rows(ctx: Dictionary) -> Array:
	var from_journal: Array = _journal_section(_journal(ctx),"可选战斗遭遇","combat")
	if not from_journal.is_empty(): return from_journal
	var result: Array = []
	var saved: Variant = _world(ctx).get("combat_sites_v1",CombatState.empty())
	var valid: bool = CombatState.valid(saved)
	var completed: Dictionary = saved.completed if valid else {}
	for spec: Dictionary in Combat.sites():
		var status: String = "complete" if completed.has(str(spec.id)) else ("available" if _unlocked(ctx,str(spec.region)) else "locked")
		if not valid or _is_guest(ctx) and not _world(ctx).has("combat_sites_v1"): status = "unavailable"
		var mode: String = str({"escort":"实体护送","defend":"服务机防守","intercept":"分批截击"}.get(str(spec.mode),"可选遭遇"))
		result.append({"id":str(spec.id),"region":str(spec.region),"title":str(spec.name),"category":"combat","status":status,
			"text":mode+" · "+("到站交接与唯一发现已经保留。" if status == "complete" else "到行动站牌主动联络；真实作业完成后回站交接。可以沿标线撤回，不重置原有成果。"),
			"anchor":_known_anchor(ctx,str(spec.id),str(spec.region),str(spec.name),spec.terminal)})
	return result

static func _journal(ctx: Dictionary) -> Dictionary:
	var supplied: Dictionary = _dictionary(ctx.get("journal",{}))
	if supplied.get("regions") is Array: return supplied
	var session: Variant = ctx.get("session")
	if _active(ctx) and is_instance_valid(session) and session.owns_world and session.story.ready: return session.content_journal.document()
	return {}

static func _journal_section(document: Dictionary, title: String, category: String) -> Array:
	var rows: Array = []
	for book: Dictionary in document.get("regions",[]):
		for section: Dictionary in book.get("sections",[]):
			if section.get("title") != title: continue
			var index := 0
			for entry: Dictionary in section.get("rows",[]):
				rows.append({"id":str(book.id)+":"+category+":"+str(index),"region":str(book.id),"category":category,"title":str(entry.get("title","")),
					"status":_normalize_status(str(entry.get("status","available"))),"text":str(entry.get("text","")),"anchor":_dictionary(entry.get("anchor",{}))})
				index += 1
	return rows

static func _add_row_actions(parent: VBoxContainer, row: Dictionary, ctx: Dictionary, dispatch: Callable) -> void:
	var buttons: HBoxContainer = Kit.row(8)
	var category: String = str(row.get("category",""))
	var status: String = str(row.get("status",""))
	var anchor: Dictionary = _dictionary(row.get("anchor",{}))
	if category == "main" and status == "active": buttons.add_child(Kit.button("追踪主线" if _active(ctx) else "出航后继续",func(): _track_main(ctx,dispatch),true))
	elif _valid_anchor(anchor) and status not in ["locked","unavailable"]:
		if _active(ctx): buttons.add_child(Kit.button("追踪此处" if str(row.region) == _current_region(ctx) else "追踪 · 抵达本区后显示",func(): _legacy(dispatch,"journal_track",anchor),status in ["active","ready"]))
		else: buttons.add_child(Kit.button("出航后前往",func(): _go(dispatch,"modes"),status in ["active","ready"]))
	var region: String = str(row.get("region","I1"))
	buttons.add_child(Kit.button("查看地区航图",func(): _region_page(dispatch,"map",region)))
	parent.add_child(buttons)
	if status == "unavailable": parent.add_child(Kit.label("当前未取得这部分世界记录；进入飞行后打开房主同步纪事。",13,Kit.GOLD))

static func _stage_anchor(ctx: Dictionary, spec: Dictionary, stage: Dictionary, saved: Dictionary) -> Dictionary:
	var region: String = str(spec.region)
	var title: String = str(spec.title)+" · "+str(stage.get("label","当前步骤"))
	match str(stage.get("type","")):
		"route":
			var points: Array = stage.get("points",[])
			var index: int = int(saved.get("route_index",0))
			if index >= 0 and index < points.size(): return _known_anchor(ctx,"",region,title,points[index])
		"dock": return _known_anchor(ctx,str(stage.body),region,title,stage.position,false)
		"combat":
			var site: Dictionary = Combat.definition(str(stage.site_id))
			if not site.is_empty(): return _known_anchor(ctx,str(site.id),region,title,site.terminal)
		"ability":
			for target: String in stage.get("targets",[]):
				for entity: Dictionary in spec.get("entities",[]):
					if entity.id == target: return _known_anchor(ctx,target,region,title,entity.position)
	return _known_anchor(ctx,str(spec.contact.id),region,title,spec.contact.position)

static func _actor_anchor(ctx: Dictionary, id: String, region: String, title: String) -> Dictionary:
	var session: Variant = ctx.get("session")
	if _active(ctx) and is_instance_valid(session) and session.region_id == region and is_instance_valid(session.ecology.view) and session.ecology.view.actors.has(id):
		var p: Vector3 = session.ecology.view.actors[id].global_position
		return {"anchor_id":id,"region":region,"label":title,"position":[p.x,p.y,p.z]}
	var simulation: Dictionary = _dictionary(_dictionary(_world(ctx).get("ecology",{})).get("simulation",{}))
	var actor: Dictionary = _dictionary(_dictionary(simulation.get("actors",{})).get(id,{}))
	if actor.get("position") is Array and actor.position.size() == 3:
		var p: Vector3 = Anchors.local_position(actor)
		return {"anchor_id":id,"region":region,"label":title,"position":[p.x,p.y,p.z]}
	return {}

static func _known_anchor(ctx: Dictionary, id: String, region: String, title: String, fallback: Array, follow_entity: bool = true) -> Dictionary:
	var position: Array = fallback.duplicate()
	var session: Variant = ctx.get("session")
	if follow_entity and not id.is_empty() and _active(ctx) and is_instance_valid(session) and session.region_id == region:
		if session.entities.get(id,{}).get("position") is Vector3:
			var p: Vector3 = session.entities[id].position
			position = [p.x,p.y,p.z]
	var saved_region: Dictionary = _dictionary(_dictionary(_world(ctx).get("entities",{})).get(region,{}))
	if follow_entity and not _active(ctx) and saved_region.get(id,{}).get("position") is Array: position = saved_region[id].position.duplicate()
	if not follow_entity: id = "" # A docking circle is a destination, not the moving cargo.
	var anchor := {"anchor_id":id,"region":region,"label":title,"position":position}
	return anchor if _valid_anchor(anchor) else {}

static func _branch_panel(body: VBoxContainer, ctx: Dictionary, dispatch: Callable) -> void:
	var session: Variant = ctx.get("session")
	var panel: VBoxContainer = Kit.card("自己的剧情分支","原有的选择前留档继续保留。切换只在自己的单人会话进行，个人发现不重复领取。","分支记录")
	if not is_instance_valid(session) or session.store == null:
		panel.add_child(Kit.label("本机分支记录尚未载入。",14,Kit.MUTED))
		body.add_child(panel)
		return
	var branches: Array = session.store.list_branches()
	var solo: bool = _active(ctx) and session.network.mode == "solo" and session.owns_world and session.profile_ready
	var busy: bool = session.boss_active or session.pending_completion or not session.consensus.current_proposal().is_empty()
	if not solo: panel.add_child(Kit.label("先从模式页进入自己的单人世界，再切换已有分支；这里不会自动开始飞行。",14,Kit.GOLD))
	elif busy: panel.add_child(Kit.label("先结束当前战斗或共同决定，再切换分支；原记录保留。",14,Kit.GOLD))
	for branch: Dictionary in branches:
		var row: HBoxContainer = Kit.row(8)
		row.add_child(Kit.label(str(branch.get("label","剧情留档"))+"\n"+_region_name(str(branch.get("region_id","")))+(" · 本机当前" if bool(branch.get("active",false)) else ""),14))
		var id: String = str(branch.get("branch_id",""))
		if not bool(branch.get("active",false)):
			var button: Button = Kit.button("切换此分支",func(): _legacy(dispatch,"branch",{"id":id}))
			button.disabled = not solo or busy
			if button.disabled: button.tooltip_text = "仅自己的单人世界且无战斗或待确认决定时可切换。"
			row.add_child(button)
		panel.add_child(row)
	if not _active(ctx): panel.add_child(Kit.button("选择单人出航",func(): _go(dispatch,"modes")))
	body.add_child(panel)

static func _profile(ctx: Dictionary) -> Dictionary:
	return _dictionary(ctx.get("profile",{}))

static func _world(ctx: Dictionary) -> Dictionary:
	return _dictionary(_profile(ctx).get("world",{}))

static func _story(ctx: Dictionary) -> Dictionary:
	return _dictionary(_dictionary(_world(ctx).get("actions",{})).get("opening",{}))

static func _discoveries(ctx: Dictionary) -> Array:
	return _array(_dictionary(_profile(ctx).get("personal",{})).get("discoveries",[]))

static func _selection(ctx: Dictionary) -> Dictionary:
	return _dictionary(ctx.get("selection",{}))

static func _active(ctx: Dictionary) -> bool:
	return bool(ctx.get("active",false))

static func _is_guest(ctx: Dictionary) -> bool:
	var session: Variant = ctx.get("session")
	return _active(ctx) and is_instance_valid(session) and session.network.mode == "guest"

static func _ownership(ctx: Dictionary) -> String:
	return "世界行动来自当前房主同步；个人发现与装备来自你本机的记录。" if _is_guest(ctx) else ("当前世界与个人发现来自本机已保存记录。" if _active(ctx) else "本机离线履历 · 真实保存的世界行动与个人发现。")

static func _current_region(ctx: Dictionary) -> String:
	var session: Variant = ctx.get("session")
	if _active(ctx) and is_instance_valid(session): return str(session.region_id)
	return str(_world(ctx).get("region_id",""))

static func _visited(ctx: Dictionary, region: String) -> bool:
	if region == _current_region(ctx): return true
	if _dictionary(_world(ctx).get("entities",{})).has(region): return true
	for id: String in _array(_story(ctx).get("completed",[])):
		if id.begins_with(region+":"): return true
	return false

static func _visited_count(ctx: Dictionary) -> int:
	var count := 0
	for region: String in ORDER:
		if _visited(ctx,region): count += 1
	return count

static func _unlocked(ctx: Dictionary, region: String) -> bool:
	if not Regions.playable(region): return false
	if region == "I1" or _visited(ctx,region): return true
	if region == "F1": return _dictionary(_world(ctx).get("flags",{})).get("I1_gate") == true
	return str(OPEN_FROM.get(region,"")) in _array(_story(ctx).get("completed_actions",[]))

static func _travel_available(ctx: Dictionary, region: String) -> bool:
	var session: Variant = ctx.get("session")
	return _active(ctx) and is_instance_valid(session) and is_instance_valid(session.world) and session._can_travel_to(region)

static func _travel_reason(ctx: Dictionary, region: String) -> String:
	var current: String = _current_region(ctx)
	if not _unlocked(ctx,region):
		if region == "F1": return "待开放 · 先在潮湾恢复跨界信标与通航，再前往巨木神殿。"
		return "待开放 · 完成「"+_action_name(str(OPEN_FROM.get(region,"")))+"」后接续此段航路。"
	if not _active(ctx): return "航图可查看。出航将回到当前存档驻地，再沿相邻航路继续。"
	if region == current: return "你正在这一区域。返回飞行即可沿原主线与支路继续。"
	if _travel_available(ctx,region): return "当前相邻航路可提出前往；房主保存与多人共同确认仍沿原流程。"
	if not Regions.can_travel(current,region): return "已有开放记录；当前并不直接相邻，请沿航图逐区接续。"
	var required: String = Regions.required_action(current,region)
	if not required.is_empty(): return "先完成当前航路所需的「"+_action_name(required)+"」。"
	return "相邻通航尚待现场恢复。先完成本区信标、调查与必要交接，再提出跨区。"

static func _region_progress(state: Dictionary, region: String) -> Dictionary:
	var done := 0
	var total := 0
	var saved: Array = _array(state.get("completed",[]))
	for action: Dictionary in _definitions():
		if str(action.region_id) != region: continue
		for goal: Dictionary in action.get("objectives",[]):
			total += 1
			if str(goal.id) in saved: done += 1
	return {"done":done,"total":total}

static func _boss_done(state: Dictionary, region: String) -> bool:
	var flags: Dictionary = _dictionary(state.get("flags",{}))
	if region == "I1": return flags.get("opening:whale_stopped") == true
	if region == "F1": return flags.get("opening:crown_control_released") == true
	return flags.get(region+":boss_stopped") == true

static func _boss_count(state: Dictionary) -> int:
	var result := 0
	for region: String in ORDER:
		if _boss_done(state,region): result += 1
	return result

static func _secret_progress(ctx: Dictionary, region: String) -> Dictionary:
	var count := 0
	var notes: Array = Rewards.notes(region)
	var saved: Array = _discoveries(ctx)
	for note: Dictionary in notes:
		if str(note.discovery_id) in saved: count += 1
	return {"found":count,"total":notes.size()}

static func _known_secrets(ctx: Dictionary) -> int:
	var result := 0
	for region: String in ORDER: result += int(_secret_progress(ctx,region).found)
	return result

static func _choice_rows(state: Dictionary) -> Array:
	var result: Array = []
	var saved: Dictionary = _dictionary(state.get("choices",{}))
	var keys := {"I2":"I2:twin_pump_guardian:decision","F2":"F2:mirror_evidence:decision","I4":"I4:prism_array:decision","F4":"F4:twin_vein_core:decision"}
	for region: String in ["I2","F2","I4","F4"]:
		var selected: String = str(saved.get(keys[region],""))
		for option: Dictionary in _choices().get(region+":chapter_choice",{}).get("options",[]):
			if str(option.id) == selected: result.append({"title":_region_name(region)+" · "+str(option.label),"text":str(option.get("consequence",""))})
	return result

static func _current_action(state: Dictionary) -> Dictionary:
	var done: Array = _array(state.get("completed_actions",[]))
	for action: Dictionary in _definitions():
		if str(action.id) in done: continue
		var eligible := true
		for id: String in action.get("prerequisites",[]):
			if id not in done: eligible = false
		if eligible: return action
	return {}

static func _current_story_text(state: Dictionary) -> String:
	var current: Dictionary = _current_action(state)
	if current.is_empty(): return "共同修复与已签决定继续保留。可以回访八区，接着完成尚未交接的日常。" if FinalStory.ending_ready(state) else "出航后继续当前世界的调查与伙伴交接。"
	var done: Array = _array(state.get("completed",[]))
	for objective: Dictionary in current.get("objectives",[]):
		if str(objective.id) in done: continue
		var eligible := true
		for id: String in objective.get("after",[]):
			if id not in done: eligible = false
		if eligible: return _region_name(str(current.region_id))+" · "+str(objective.get("text",current.title))
	return str(current.title)

static func _definitions() -> Array:
	if _actions.is_empty():
		var loader = Director.new()
		var loaded: Dictionary = loader.load_definitions(Director.DEFAULT_PATH,Campaign.extension_paths())
		if loaded.get("ok",false): _actions = loader.definitions().get("actions",[])
	return _actions

static func _choices() -> Dictionary:
	if _choice_data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/v3/campaign/choices.json"))
		if parsed is Dictionary: _choice_data = parsed.get("choices",{})
	return _choice_data

static func _old_specs() -> Dictionary:
	if _old_data.is_empty():
		for region: String in ["i1","i2","f2","i3"]:
			var row: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/v3/campaign/npc_sidejob_"+region+".json"))
			if row is Dictionary: _old_data[str(row.id)] = row
	return _old_data

static func _action_name(id: String) -> String:
	for action: Dictionary in _definitions():
		if str(action.id) == id: return str(action.title)
	return "前一段地区行动" if id.is_empty() else id

static func _total_goals() -> int:
	var count := 0
	for action: Dictionary in _definitions(): count += action.get("objectives",[]).size()
	return count

static func _completed_goals(state: Dictionary) -> int:
	return _array(state.get("completed",[])).size()

static func _region_name(id: String) -> String:
	return str(Regions.definition(id).get("name","尚未选择地区"))

static func _module_name(id: String) -> String:
	return str(Frames.modules().get(id,{}).get("name",id))

static func _frame_name(id: String) -> String:
	return str(Frames.airframes().get(id,{}).get("name",id.to_upper()))

static func _mode_name(value: String) -> String:
	return str({"solo":"离线单人","host":"局域网房主","guest":"局域网协作","join":"局域网协作"}.get(value,"出航记录"))

static func _status_name(value: String) -> String:
	return str({"available":"可开始","active":"进行中","ready":"待交接","complete":"已完成","locked":"待开放","unavailable":"待同步记录"}.get(value,value))

static func _normalize_status(value: String) -> String:
	return str({"已完成":"complete","已交接":"complete","已发现":"complete","进行中":"active","可交接":"ready","可接取":"available","未开始":"available","待章节决定":"locked","等待探索":"available","completed":"complete"}.get(value,value))

static func _status_matches(value: String, selected: String) -> bool:
	if selected == "all": return true
	if selected == "active": return value in ["active","ready"]
	if selected == "locked": return value in ["locked","unavailable"]
	return value == selected

static func _plain(text: String) -> String:
	return text.replace("{contact}","联络键").replace("{ability}","能力键").replace("{brake}","制动键")

static func _saved_time(value: String) -> String:
	return value.replace("T"," ").replace("Z"," UTC")

static func _duration(value: Variant) -> String:
	if not (value is int or value is float) or not is_finite(float(value)) or float(value)<0: return "—"
	var seconds: int = int(value)
	return "%d时%02d分" % [seconds/3600,(seconds%3600)/60] if seconds>=3600 else "%d分%02d秒" % [seconds/60,seconds%60]

static func _array_count(source: Dictionary, key: String) -> String:
	return str(source[key].size()) if source.get(key) is Array else "—"

static func _add_summary_list(parent: VBoxContainer, summary: Dictionary, key: String, empty_text: String, objectives: bool) -> void:
	if not summary.get(key) is Array:
		parent.add_child(Kit.label("这次出航没有记录这一项统计。",14,Kit.MUTED))
		return
	var entries: Array = summary[key]
	if entries.is_empty(): parent.add_child(Kit.label(empty_text,14,Kit.MUTED))
	for item: Variant in entries:
		var text: String = str(item.get("title",item.get("name","已保存记录"))) if item is Dictionary else _record_name(str(item),objectives)
		parent.add_child(Kit.label("•  "+text,15,Kit.TEXT))

static func _record_name(id: String, objective: bool = false) -> String:
	if _names.is_empty():
		for action: Dictionary in _definitions():
			_names[str(action.id)] = str(action.title)
			for goal: Dictionary in action.get("objectives",[]):
				_names[str(goal.id)] = str(goal.text)
				for effect: Dictionary in goal.get("effects",[]):
					if effect.get("type") == "discovery": _names[str(effect.discovery_id)] = str(effect.get("title","世界调查记录"))
		for note: Dictionary in Rewards.notes(): _names[str(note.discovery_id)] = str(note.title)
		for job: Dictionary in Stories.definitions():
			_names[str(job.id)] = str(job.title)
			_names[str(job.reward_id)] = str(job.title)
		for id_old: String in _old_specs():
			_names[id_old] = str(_old_specs()[id_old].title)
			_names[str(OldJobs.SPECS[id_old].reward)] = str(_old_specs()[id_old].title)
		for region: String in Field.REGIONS: _names[str(Field.definition(region).reward_id)] = str(Field.definition(region).title)
		for site: Dictionary in Combat.sites():
			_names[str(site.id)] = str(site.name)
			_names[str(site.reward_id)] = str(site.name)
		for region: String in ORDER: _names["gate:"+region] = _region_name(region)+" · 通航恢复"
	return str(_names.get(id,id if objective else "已保存发现 · "+id))

static func _progress(value: int, maximum: int) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.custom_minimum_size.y = 7
	bar.show_percentage = false
	bar.max_value = maxi(1,maximum)
	bar.value = clampi(value,0,maxi(0,maximum))
	bar.add_theme_stylebox_override("background",Kit.box(Color("09232c"),Color("24434c"),4,0))
	bar.add_theme_stylebox_override("fill",Kit.box(Kit.ACCENT,Kit.ACCENT,4,0))
	return bar

static func _region_selector(selected: String, key: String, dispatch: Callable) -> OptionButton:
	var entries: Array = [["all","全部地区"]]
	for region: String in ORDER: entries.append([region,region+" · "+_region_name(region)])
	return _selector(entries,selected,key,dispatch)

static func _selector(entries: Array, selected: String, key: String, dispatch: Callable) -> OptionButton:
	var option := OptionButton.new()
	option.custom_minimum_size.y = 44
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.focus_mode = Control.FOCUS_ALL
	option.add_theme_font_override("font",Kit.font())
	option.add_theme_font_size_override("font_size",14)
	option.add_theme_color_override("font_color",Kit.TEXT)
	for state: String in ["normal","hover","pressed","focus"]: option.add_theme_stylebox_override(state,Kit.box(Color("15353e"),Kit.ACCENT if state == "focus" else Kit.LINE,8,12))
	var index := 0
	for entry: Array in entries:
		option.add_item(str(entry[1]))
		option.set_item_metadata(index,str(entry[0]))
		if str(entry[0]) == selected: option.select(index)
		index += 1
	option.item_selected.connect(func(chosen: int): dispatch.call("page_filter",{"key":key,"value":str(option.get_item_metadata(chosen))}))
	return option

static func _valid_anchor(anchor: Dictionary) -> bool:
	var point: Variant = anchor.get("position")
	if not point is Array or point.size()!=3 or not Regions.playable(str(anchor.get("region",""))): return false
	for value: Variant in point:
		if not (value is int or value is float) or not is_finite(float(value)): return false
	return true

static func _continue(ctx: Dictionary, dispatch: Callable) -> void:
	if _active(ctx): _legacy(dispatch,"resume")
	else: _go(dispatch,"modes")

static func _track_main(ctx: Dictionary, dispatch: Callable) -> void:
	if _active(ctx): _legacy(dispatch,"journal_track",{})
	else: _go(dispatch,"modes")

static func _region_page(dispatch: Callable, page: String, region: String) -> void:
	var key: String = str({"map":"map_region","missions":"mission_region","events":"event_region"}.get(page,"map_region"))
	dispatch.call("page_filter",{"key":key,"value":region})
	_go(dispatch,page)

static func _go(dispatch: Callable, page: String) -> void:
	dispatch.call("navigate",{"page":page})

static func _legacy(dispatch: Callable, action: String, payload: Dictionary = {}) -> void:
	dispatch.call("legacy",{"action":action,"payload":payload.duplicate(true)})

static func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

static func _array(value: Variant) -> Array:
	return value if value is Array else []
