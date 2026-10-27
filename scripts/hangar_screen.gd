extends Control

var ui
var world
const INK=Color("173645")
const PAPER=Color("eee9dc")
const TEAL=Color("397f86")
const GOLD=Color("d79b49")

func _ready() -> void:
	world=ui.world
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	ui.rect(self,Vector2.ZERO,Vector2(1600,900),Color("e9e5da"))
	ui.rect(self,Vector2.ZERO,Vector2(1600,108),INK)
	ui.label(self,"低空小队",Vector2(34,16),Vector2(340,50),34,PAPER)
	ui.label(self,"HARBOR GARDEN  /  机库行动",Vector2(36,69),Vector2(590,28),15,Color("a0cbc6"))
	ui.label(self,"飞行计划  /  装配与出击",Vector2(627,36),Vector2(540,38),20,PAPER)
	ui.label(self,"零件  %03d"%world.profile.data.parts,Vector2(1320,29),Vector2(247,45),28,Color("efd29f"))
	ui.label(self,"选择你的下一片空域",Vector2(35,127),Vector2(400,38),23,INK)
	for i in range(3):_mission_card(i)
	ui.button(self,"自由练飞 · 无敌人",Vector2(34,748),Vector2(388,38),world.start_practice)
	ui.button(self,"飞行设置",Vector2(34,798),Vector2(187,38),ui.show_settings)
	ui.button(self,"飞行手册",Vector2(234,798),Vector2(187,38),ui.show_help)
	ui.button(self,"退出游戏",Vector2(34,847),Vector2(387,36),func():world.profile.save_profile();get_tree().quit())
	var aircraft=ui.panel(self,Vector2(446,129),Vector2(654,501),Color("dddcd1"))
	ui.label(aircraft,"TR–01",Vector2(22,14),Vector2(260,58),43,INK)
	ui.label(aircraft,"四旋翼 · 模块化试验机",Vector2(25,77),Vector2(500,28),18,TEAL)
	ui.label(aircraft,"FLIGHT READY",Vector2(438,25),Vector2(190,29),16,TEAL)
	ui._preview(Vector2(457,241),Vector2(630,332))
	var d=GameData.MODULES[world.profile.data.loadout.drive]
	ui.label(aircraft,"速度  %02d m/s       制动  %02d       负载  %d / 8"%[d.speed,d.brake,GameData.loadout_load(world.profile.data.loadout)],Vector2(30,443),Vector2(610,35),18,INK)
	var briefing=ui.panel(self,Vector2(446,648),Vector2(654,137),INK)
	ui.label(briefing,GameData.MISSIONS[ui.selected].tag+"  /  任务简报",Vector2(20,12),Vector2(610,33),21,PAPER)
	ui.label(briefing,GameData.MISSIONS[ui.selected].brief,Vector2(21,56),Vector2(610,75),17,Color("bed6cf"))
	var launch=ui.button(self,"开始行动   →",Vector2(446,808),Vector2(654,58),func():world.start_mission(ui.selected),not world.profile.can_play(ui.selected))
	launch.grab_focus()
	ui.label(self,"装配工坊",Vector2(1126,127),Vector2(440,42),24,INK)
	var slots=[["weapon","01 / 主武器",["pulse","charge"]],["drive","02 / 动力组",["stable","agile"]],["utility","03 / 功能模块",["shield","cooler"]]]
	for i in range(slots.size()):_slot(slots[i],Vector2(1124,179+i*134))
	ui.label(self,"空域难度",Vector2(1127,586),Vector2(417,33),20,INK)
	var difficulty=OptionButton.new();difficulty.position=Vector2(1124,629);difficulty.size=Vector2(442,43)
	for item in GameData.DIFFICULTY:difficulty.add_item(item.name+"  /  "+item.description)
	difficulty.selected=int(world.profile.data.settings.difficulty)
	difficulty.add_theme_font_size_override("font_size",14)
	difficulty.item_selected.connect(func(value):world.profile.data.settings.difficulty=value;world.profile.save_profile())
	add_child(difficulty)
	ui.label(self,"设施升级  /  每项 50 零件",Vector2(1127,690),Vector2(417,29),17,TEAL)
	ui.button(self,"装配工坊  ·  解锁蓄能器" if not world.profile.data.unlocked.has("charge") else "✓ 蓄能器蓝图已拥有",Vector2(1124,730),Vector2(442,44),func():_upgrade("workshop"),world.profile.data.unlocked.has("charge"))
	ui.button(self,"试验终端  ·  解锁机动组" if not world.profile.data.unlocked.has("agile") else "✓ 机动组蓝图已拥有",Vector2(1124,785),Vector2(442,44),func():_upgrade("terminal"),world.profile.data.unlocked.has("agile"))
	ui.label(self,"蓝图永久保留。免费换装，选择自己的节奏。",Vector2(1127,842),Vector2(440,30),14,TEAL)

func _upgrade(id: String) -> void:
	var result=world.profile.upgrade_facility(id)
	ui.show_hangar()
	ui.toast("设施升级完成，蓝图已解锁。" if result else "需要 50 零件才能升级；完成行动可获得零件。")

func _mission_card(i: int) -> void:
	var chosen=i==ui.selected
	var open=world.profile.can_play(i)
	var card=ui.panel(self,Vector2(34,179+i*185),Vector2(388,171),INK if chosen else Color("d5dbd1"))
	card.clip_contents=true
	var path="res://assets/ui/maps/map%d.png"%i
	if ResourceLoader.exists(path):
		var picture=TextureRect.new();picture.texture=load(path)
		picture.position=Vector2(1,1);picture.size=Vector2(386,89)
		picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
		picture.mouse_filter=Control.MOUSE_FILTER_IGNORE;card.add_child(picture)
		picture.size=Vector2(386,89)
	else:
		ui.rect(card,Vector2(1,1),Vector2(386,89),Color("356773"))
		var spec=ExpeditionMaps.data(i)
		for isle in spec.islands:
			ui.rect(card,Vector2(185+isle[0]*1.1,43+isle[1]*.7),Vector2(isle[2]*1.1,isle[3]*.7),Color("b7c3ac"))
	ui.label(card,GameData.MISSIONS[i].name,Vector2(14,94),Vector2(300,31),21,PAPER if chosen else INK)
	var state="已完成 · 可重玩" if world.profile.data.completed.has(i) else ("可出击" if open else "待解锁")
	ui.label(card,state,Vector2(16,134),Vector2(220,26),14,Color("a9d4c9") if chosen else TEAL)
	var choose=ui.button(card,"已选择" if chosen else "查看",Vector2(280,126),Vector2(92,34),func():ui.selected=i;ui.show_hangar())
	choose.add_theme_font_size_override("font_size",14)

func _slot(slot: Array,pos: Vector2) -> void:
	var id=world.profile.data.loadout[slot[0]]
	var card=ui.panel(self,pos,Vector2(442,121),Color("d7dcd1"))
	ui.label(card,slot[1]+"   "+GameData.MODULES[id].name,Vector2(14,8),Vector2(410,31),18,INK)
	for j in range(2):
		var option=slot[2][j]
		var owned=world.profile.data.unlocked.has(option)
		var text=GameData.MODULES[option].name
		if option==id:text="✓ "+text
		elif not owned:text+=" · %d"%GameData.MODULES[option].cost
		var button=ui.button(card,text,Vector2(13+j*211,47),Vector2(202,37),func():
			var result=false
			if owned:result=world.profile.equip(option)
			else:result=world.profile.buy_module(option)
			ui.show_hangar()
			if not result:ui.toast("零件不足或负载超限；先完成行动，再调整配装。")
			elif not owned:ui.toast("蓝图已购买，再次点击即可装备。")
		)
		button.add_theme_font_size_override("font_size",14)
	ui.label(card,GameData.MODULES[id].description.split("\n")[0],Vector2(16,91),Vector2(414,23),14,TEAL)
