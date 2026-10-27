class_name GameData
extends RefCounted

const VERSION = "0.1.0"
const MODULES = {
	"pulse": {"name":"稳定脉冲器", "slot":"weapon", "cost":0, "load":2, "damage":15.0, "rate":0.22, "heat":9.0, "description":"持续脉冲 · 好上手\n短间隔输出，留意热量"},
	"charge": {"name":"蓄能发射器", "slot":"weapon", "cost":60, "load":3, "damage":55.0, "rate":0.90, "heat":25.0, "description":"低频重击 · 抓住窗口\n更高单发伤害与穿透冲击"},
	"stable": {"name":"稳定动力组", "slot":"drive", "cost":0, "load":2, "speed":8.0, "accel":14.0, "brake":25.0, "description":"低速稳定 · 刹车更准\n悬停、交互与首次出击之选"},
	"agile": {"name":"机动动力组", "slot":"drive", "cost":50, "load":3, "speed":11.0, "accel":20.0, "brake":17.0, "description":"高速灵活 · 提前制动\n绕行更快，停稳需要预判"},
	"shield": {"name":"应急护盾", "slot":"utility", "cost":0, "load":2, "description":"主动防护 · 14 秒冷却\nShift 开启 2.4 秒防护"},
	"cooler": {"name":"散热模块", "slot":"utility", "cost":45, "load":1, "description":"被动散热 · 输出节奏\n热量回复 +70%，无主动护盾"}
}
const MISSIONS = [
	{"name":"01 / 初航回收", "tag":"港湾训练区", "brief":"跨越石桥与运河，回收三件补给并安全返航。\n可选：依次穿越四道飞行门，寻找散落零件。", "reward":100, "time":300.0},
	{"name":"02 / 重启水岸", "tag":"运河花园区", "brief":"重启四片岛屿的电源，抵御协同巡逻编队。\n选择路线，利用高低航层和补给，完成后返航。", "reward":130, "time":420.0},
	{"name":"03 / 蜂巢协议", "tag":"工业码头区", "brief":"关闭两个安全继电器，再进入北港检修场。\n击破护盾节点、跨越冲击波，终止蜂巢协议。", "reward":180, "time":480.0}
]
const DIFFICULTY = [
	{"name":"轻松", "damage":0.60, "telegraph":1.55, "health":130.0,"attackers":1,"shot_speed":11.0,"recovery":1.35,"extra":0,"heal":65.0,"lead":0.0,"description":"长预警 · 单机轮攻 · 充足维修"},
	{"name":"标准", "damage":1.0, "telegraph":1.0, "health":100.0,"attackers":2,"shot_speed":15.0,"recovery":1.0,"extra":1,"heal":42.0,"lead":0.25,"description":"双机协同 · 掩体与制动 · 标准补给"},
	{"name":"挑战", "damage":1.20, "telegraph":0.85, "health":100.0,"attackers":3,"shot_speed":18.0,"recovery":.78,"extra":2,"heal":28.0,"lead":0.45,"description":"侧翼夹击 · 预测射击 · 紧凑恢复窗口"}
]

static func loadout_load(loadout: Dictionary) -> int:
	var total = 0
	for slot in ["weapon", "drive", "utility"]:
		if not MODULES.has(loadout.get(slot, "")):
			return 999
		var module = MODULES[loadout[slot]]
		if module.slot != slot:
			return 999
		total += module.load
	return total

static func valid_loadout(loadout: Dictionary, unlocked: Array) -> bool:
	if loadout_load(loadout) > 8:
		return false
	for slot in ["weapon", "drive", "utility"]:
		if not unlocked.has(loadout.get(slot, "")):
			return false
	return true

