class_name ExpeditionMaps
extends RefCounted

const MAPS = [
	{"name":"港湾训练区","subtitle":"HARBOR ACADEMY","size":Vector2(100,82),"launch":Vector3(-32,1.65,20),"seed":410,
	"islands":[[-30,0,28,58],[4,-10,24,30],[32,0,26,54],[2,26,28,16]],
	"bridges":[[-12,-15,0,1.0],[18,-8,0,.8],[-12,23,0,1.0],[18,23,0,.8],[3,13,1,1.0]],
	"objectives":[Vector3(-31,0,-13),Vector3(5,0,-12),Vector3(32,0,18)],
	"enemy_groups":[[Vector3(-29,1.65,-20),"patrol"],[Vector3(5,1.65,-18),"patrol"],[Vector3(29,1.65,7),"charger"]],
	"supplies":[Vector3(-23,0,8),Vector3(36,0,-12)],
	"salvage":[Vector3(-35,0,-22),Vector3(1,0,29),Vector3(38,0,21)],
	"gates":[Vector3(-16,1.65,21),Vector3(-5,1.65,22),Vector3(8,4.1,23),Vector3(19,4.1,22)],
	"boss":Vector3(31,1.5,-6),"color":Color("337c88")},
	{"name":"运河花园区","subtitle":"CANAL CONSERVATORY","size":Vector2(128,106),"launch":Vector3(-42,1.65,31),"seed":610,
	"islands":[[-38,-27,34,34],[-38,26,38,34],[2,-1,26,30],[40,-24,36,40],[40,29,32,32],[2,39,23,14]],
	"bridges":[[-38,-1,1,1.8],[-16,-9,0,1.0],[19,-8,0,1.0],[-16,30,0,1.0],[19,34,0,1.0],[40,3,1,1.4],[2,23,1,1.8]],
	"objectives":[Vector3(-42,0,-26),Vector3(5,0,1),Vector3(43,0,-26),Vector3(39,0,32)],
	"enemy_groups":[[Vector3(-35,1.65,-28),"patrol"],[Vector3(-32,1.65,-20),"charger"],[Vector3(6,1.65,5),"repair"],[Vector3(8,1.65,-8),"patrol"],[Vector3(41,1.65,-17),"patrol"],[Vector3(35,1.65,25),"charger"]],
	"supplies":[Vector3(-30,0,25),Vector3(35,0,-11)],
	"salvage":[Vector3(-45,0,-37),Vector3(2,0,42),Vector3(50,0,-34)],
	"gates":[Vector3(-21,1.65,29),Vector3(-7,1.65,35),Vector3(7,4.1,38),Vector3(23,4.1,33)],
	"boss":Vector3(40,1.5,28),"color":Color("276d78")},
	{"name":"工业码头区","subtitle":"NORTH PIER OPERATIONS","size":Vector2(132,108),"launch":Vector3(-45,1.65,29),"seed":810,
	"islands":[[-40,19,36,42],[-37,-30,40,28],[3,12,25,40],[3,-34,25,22],[42,-3,40,76]],
	"bridges":[[-38,-9,1,1.5],[-15,23,0,1.0],[-15,-31,0,1.0],[18,17,0,1.0],[18,-30,0,1.0],[3,-13,1,1.7]],
	"objectives":[Vector3(-36,0,-29),Vector3(4,0,7)],
	"enemy_groups":[[Vector3(-31,1.65,14),"charger"],[Vector3(-35,1.65,-24),"patrol"],[Vector3(-29,1.65,-35),"repair"],[Vector3(6,1.65,15),"patrol"],[Vector3(6,4.1,-27),"patrol"],[Vector3(37,1.65,13),"charger"],[Vector3(45,1.65,-4),"repair"]],
	"supplies":[Vector3(-45,0,-25),Vector3(30,0,21)],
	"salvage":[Vector3(-47,0,8),Vector3(3,0,-35),Vector3(54,0,27)],
	"gates":[Vector3(-22,1.65,23),Vector3(-9,4.1,22),Vector3(9,4.1,19),Vector3(24,1.65,18)],
	"boss":Vector3(42,1.5,-20),"color":Color("365f72")}
]

static func data(index: int) -> Dictionary:
	return MAPS[clampi(index,0,MAPS.size()-1)]

static func bounds(index: int) -> Rect2:
	var size: Vector2=data(index).size
	return Rect2(-size*.5,size)
