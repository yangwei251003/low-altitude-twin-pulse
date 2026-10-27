class_name HarborDistrict
extends RefCounted

var parent: Node3D
var rng=RandomNumberGenerator.new()
var obstacles: Array[Rect2]=[]
var bounds: Rect2
var map_id=0

func build(target: Node3D,index: int) -> void:
	parent=target;map_id=index
	var spec=ExpeditionMaps.data(index)
	rng.seed=spec.seed
	bounds=ExpeditionMaps.bounds(index)
	_water(spec.color)
	for island in spec.islands:_island(Vector2(island[0],island[1]),Vector2(island[2],island[3]))
	for item in spec.bridges:
		var b=GameVisuals.asset(parent,"bridge",Vector3(item[0],0,item[1]))
		b.scale.x=item[3]
		b.rotation.y=PI/2 if item[2]==1 else 0.0
		# Flight above the bridge, water-level passage underneath is decorative.
		var dims=Vector3(5.5,.25,10*item[3]) if item[2]==1 else Vector3(10*item[3],.25,5.5)
		GameVisuals.collider(parent,Vector3(item[0],-.2,item[1]),dims)
	if index==0:_academy()
	elif index==1:_gardens()
	else:_industrial()
	_set_dressing()
	var launch: Vector3=spec.launch
	GameVisuals.asset(parent,"pad",Vector3(launch.x,.07,launch.z),1.5)
	for item in spec.gates:
		var ring=GameVisuals.ring(parent,item,1.85,Color("64ccd0"),.085)
		ring.rotation.x=PI/2
		GameVisuals.cylinder(parent,Vector3(item.x,.12,item.z),.24,.2,Color("37636c"))
	# Far islands break the horizon but cannot become combat obstructions.
	for i in range(14):
		var angle=i*TAU/14
		var rock=GameVisuals.asset(parent,"coast_rock",Vector3(cos(angle)*91,-4.3,sin(angle)*76),rng.randf_range(2,4))
		rock.rotation.y=angle

func solid(id: String,pos: Vector3,size: Vector3,rotation: float=0.0,scale_factor: float=1.0) -> Node3D:
	var model=GameVisuals.asset(parent,id,pos,scale_factor)
	model.rotation.y=rotation
	var dims=size*scale_factor
	if dims.is_zero_approx():return model
	if absf(sin(rotation))>.7:dims=Vector3(dims.z,dims.y,dims.x)
	GameVisuals.collider(parent,pos+Vector3(0,dims.y*.5,0),dims)
	if dims.y>3.3:obstacles.append(Rect2(Vector2(pos.x-dims.x*.5-.8,pos.z-dims.z*.5-.8),Vector2(dims.x+1.6,dims.z+1.6)))
	return model

func _island(center: Vector2,size: Vector2) -> void:
	var foundation=GameVisuals.box(parent,Vector3(center.x,-1.85,center.y),Vector3(size.x,3.7,size.y),Color("b2b1a1"))
	foundation.material_override=GameVisuals.surface("stone")
	var top=GameVisuals.box(parent,Vector3(center.x,-.10,center.y),Vector3(size.x+.2,.26,size.y+.2),Color("cfccb9"))
	top.material_override=GameVisuals.surface("paving")
	GameVisuals.collider(parent,Vector3(center.x,-.5,center.y),Vector3(size.x,1,size.y))
	for side in [-1,1]:
		GameVisuals.box(parent,Vector3(center.x+side*size.x*.5,-.02,center.y),Vector3(.32,.3,size.y+.4),Color("d7cfb7"))
		GameVisuals.box(parent,Vector3(center.x,-.02,center.y+side*size.y*.5),Vector3(size.x,.3,.32),Color("d7cfb7"))
	for x in range(int(center.x-size.x*.5)+2,int(center.x+size.x*.5),4):
		for z in range(int(center.y-size.y*.5)+2,int(center.y+size.y*.5),4):
			# Fine paving seams are part of the ground, not busy floor markings.
			GameVisuals.box(parent,Vector3(x,.042,z),Vector3(3.97,.008,.018),Color("989f95"))
	# Planted promenade around selected edges, with gaps at canal crossings.
	for i in range(int(size.y/6)):
		var z=center.y-size.y*.5+3+i*6
		var x=center.x-size.x*.5+2.8
		if i%3==0:solid("planter",Vector3(x,0,z),Vector3(2.8,.85,1.4),PI/2)
		_tree(Vector3(x,0,z),i%3==1,rng.randf_range(.78,1.1))
	for i in range(int((size.x+size.y)/2.5)):
		var side=i%4
		var p=Vector3(center.x,-2.85,center.y)
		if side<2:p.x+=(size.x*.5+rng.randf_range(.1,1.8))*(1 if side==0 else -1);p.z+=rng.randf_range(-size.y*.5,size.y*.5)
		else:p.z+=(size.y*.5+rng.randf_range(.1,1.8))*(1 if side==2 else -1);p.x+=rng.randf_range(-size.x*.5,size.x*.5)
		var rock=GameVisuals.asset(parent,"rock_large",p,rng.randf_range(1.9,3.4));rock.rotation.y=rng.randf()*TAU
	for i in range(int(size.x/7)):
		var x=center.x-size.x*.5+3+i*7
		GameVisuals.asset(parent,"lamp",Vector3(x,0,center.y+size.y*.5-1.2),.8)
		if i%2==0:
			var rail=GameVisuals.asset(parent,"railing",Vector3(x,.07,center.y+size.y*.5-.3))
			rail.scale.x=1.4

func _tree(pos: Vector3,cypress: bool=false,s: float=1.0) -> void:
	var tree=GameVisuals.asset(parent,"cypress" if cypress else "garden_oak",pos,s)
	tree.rotation.y=rng.randf()*TAU
	GameVisuals.collider(parent,pos+Vector3(0,1.5,0),Vector3(.45,3,.45))
	obstacles.append(Rect2(Vector2(pos.x-.9,pos.z-.9),Vector2(1.8,1.8)))

func _garden(pos: Vector3,size: Vector2) -> void:
	var lawn=GameVisuals.box(parent,pos+Vector3(0,.10,0),Vector3(size.x,.18,size.y),Color("6b7952"))
	lawn.material_override=GameVisuals.surface("lawn")
	for x in [-size.x*.5,size.x*.5]:GameVisuals.box(parent,pos+Vector3(x,.25,0),Vector3(.20,.36,size.y),Color("dad2bd"))
	for z in [-size.y*.5,size.y*.5]:GameVisuals.box(parent,pos+Vector3(0,.25,z),Vector3(size.x,.36,.20),Color("dad2bd"))
	for i in range(10):
		var p=pos+Vector3(rng.randf_range(-size.x*.42,size.x*.42),.20,rng.randf_range(-size.y*.42,size.y*.42))
		GameVisuals.asset(parent,"garden_hedge",p,rng.randf_range(.6,1.1))
	for i in range(12):
		var p=pos+Vector3(rng.randf_range(-size.x*.45,size.x*.45),.24,rng.randf_range(-size.y*.45,size.y*.45))
		GameVisuals.sphere(parent,p,.10,Color("ded3a1") if i%2==0 else Color("b9a5b5"))

func _set_dressing() -> void:
	# Per-map authored spaces preserve objective clearance and alternative lanes.
	var terraces=[]
	var offices=[]
	if map_id==0:
		terraces=[[Vector3(-25,0,10),Vector2(8,9)],[Vector3(-37,0,-10),Vector2(6,10)],[Vector3(31,0,-2),Vector2(11,8)],[Vector3(7,0,29),Vector2(11,5)]]
		offices=[Vector3(-22,0,-19),Vector3(37,0,-18)]
	elif map_id==1:
		terraces=[[Vector3(-29,0,16),Vector2(10,9)],[Vector3(-32,0,-21),Vector2(10,9)],[Vector3(47,0,-17),Vector2(12,9)],[Vector3(42,0,23),Vector2(10,8)],[Vector3(-2,0,6),Vector2(7,7)]]
		offices=[Vector3(-49,0,36),Vector3(29,0,-36),Vector3(48,0,38)]
	else:
		terraces=[[Vector3(-47,0,20),Vector2(9,8)],[Vector3(1,0,27),Vector2(12,5)],[Vector3(-29,0,-39),Vector2(12,6)]]
		offices=[Vector3(-48,0,4),Vector3(55,0,-8),Vector3(-4,0,-39)]
	for entry in terraces:
		var p: Vector3=entry[0];var s: Vector2=entry[1]
		# Raised planted courts, accessible above their low stone walls.
		var terrace=GameVisuals.box(parent,p+Vector3(0,.38,0),Vector3(s.x+1.2,.76,s.y+1.2),Color("b6baaa"))
		terrace.material_override=GameVisuals.surface("stone")
		GameVisuals.collider(parent,p+Vector3(0,.3,0),Vector3(s.x+1.2,.6,s.y+1.2))
		GameVisuals.asset(parent,"stairs",p+Vector3(0,0,s.y*.5+1.7),.48)
		p.y+=.76
		_garden(p,s)
		for i in [-1,1]:
			_tree(p+Vector3(s.x*.30*i,.2,s.y*.23),true,.85)
			GameVisuals.asset(parent,"railing",p+Vector3(i*s.x*.27,.3,-s.y*.5))
		# Stone edge benches and small maintenance cargo are readable at flight scale.
		GameVisuals.box(parent,p+Vector3(0,.6,-s.y*.5-.3),Vector3(3,.22,.7),Color("687c72"))
	for p in offices:
		solid("lab",p,Vector3(7,5,5.2),PI,.82)
		GameVisuals.asset(parent,"stairs",p+Vector3(0,0,3.7),.6)
		for i in [-1,1]:GameVisuals.asset(parent,"planter",p+Vector3(3.0*i,0,3.1),.8)
	for item in ExpeditionMaps.data(map_id).islands:
		var cx=float(item[0]);var cz=float(item[1]);var w=float(item[2]);var d=float(item[3])
		# Terraced limestone bank and masonry buttresses, with repeating metal details.
		for x in range(int(cx-w*.5)+2,int(cx+w*.5),5):
			for z in [cz-d*.5,cz+d*.5]:
				var buttress=GameVisuals.box(parent,Vector3(x,-1.55,z),Vector3(.65,3.2,.70),Color("c4bfa9"))
				buttress.material_override=GameVisuals.surface("stone")
		for i in range(2):
			var p=Vector3(cx+w*.5-2.6,0,cz-d*.5+4+i*5)
			_tree(p,true,.9)
			GameVisuals.asset(parent,"crate",p+Vector3(-1.3,0,1),.6)

func _academy() -> void:
	solid("tower",Vector3(-39,0,-21),Vector3(4,6,4))
	solid("lab",Vector3(-25,0,-25),Vector3(7,5,5.2))
	solid("hangar",Vector3(-24,0,24),Vector3(6.6,3.6,4.5),PI)
	solid("greenhouse",Vector3(3,0,-18),Vector3(6.4,4.3,9.4),PI/2)
	solid("fountain",Vector3(4,0,-2),Vector3(5.4,1.8,5.4))
	solid("lab",Vector3(32,0,-21),Vector3(7,5,5.2))
	solid("lighthouse",Vector3(41,0,21),Vector3(3,10,3))
	solid("canopy",Vector3(-29,0,0),Vector3(0,0,0))
	_canopy_collision(Vector3(-29,0,0))
	for p in [Vector3(-24,0,-7),Vector3(9,0,-2),Vector3(29,0,9),Vector3(2,0,26)]:
		solid("planter",p,Vector3(2.8,.85,1.4));_tree(p+Vector3(0,.6,0),true,.68)
	for p in [Vector3(-39,0,5),Vector3(-23,0,-16),Vector3(10,0,-20),Vector3(39,0,-7)]:_garden(p,Vector2(5,7))
	_port(Vector3(31,0,28),false)

func _gardens() -> void:
	solid("tower",Vector3(-49,0,-36),Vector3(4,6,4))
	solid("greenhouse",Vector3(-35,0,-33),Vector3(6.4,4.3,9.4),PI/2,1.3)
	solid("lab",Vector3(-27,0,37),Vector3(7,5,5.2),PI)
	solid("fountain",Vector3(-39,0,21),Vector3(5.4,1.8,5.4),0,1.25)
	solid("greenhouse",Vector3(1,0,-9),Vector3(6.4,4.3,9.4))
	solid("lab",Vector3(48,0,-37),Vector3(7,5,5.2),0,1.25)
	solid("lighthouse",Vector3(51,0,39),Vector3(3,10,3))
	for p in [Vector3(-47,0,15),Vector3(-43,0,-18),Vector3(9,0,7),Vector3(30,0,-25),Vector3(47,0,24),Vector3(2,0,39)]:
		_garden(p,Vector2(6,7));_tree(p+Vector3(1,0,1),true,1.1)
	for p in [Vector3(-31,0,27),Vector3(36,0,-9),Vector3(35,0,36)]:
		solid("canopy",p,Vector3.ZERO);_canopy_collision(p)
	_port(Vector3(-39,0,44),false)

func _industrial() -> void:
	solid("hangar",Vector3(-49,0,33),Vector3(6.6,3.6,4.5),PI)
	solid("lab",Vector3(-48,0,-37),Vector3(7,5,5.2))
	solid("crane",Vector3(45,0,20),Vector3.ZERO)
	for x in [40,50]:
		for z in [18,22]:GameVisuals.collider(parent,Vector3(x,4.5,z),Vector3(.8,9,.8))
	solid("lab",Vector3(48,0,-36),Vector3(7,5,5.2),0,1.2)
	solid("tower",Vector3(55,0,8),Vector3(4,6,4))
	solid("lighthouse",Vector3(58,0,29),Vector3(3,10,3))
	for p in [Vector3(-29,0,-31),Vector3(5,0,-38),Vector3(8,0,21),Vector3(32,0,7),Vector3(50,0,8),Vector3(-31,0,8)]:
		solid("container",p,Vector3(2.5,2.35,6.0),PI/2)
	for p in [Vector3(-50,0,11),Vector3(0,0,0),Vector3(32,0,-32)]:_garden(p,Vector2(6,5))
	GameVisuals.asset(parent,"industry_tank",Vector3(-42,0,-34),2.0)
	_port(Vector3(40,0,36),true)

func _canopy_collision(pos: Vector3) -> void:
	for x in [-2,2]:GameVisuals.collider(parent,pos+Vector3(x,1.7,0),Vector3(.35,3.4,.55))
	GameVisuals.collider(parent,pos+Vector3(0,3.55,0),Vector3(4.5,.3,1.8))
	obstacles.append(Rect2(Vector2(pos.x-3,pos.z-1.6),Vector2(6,3.2)))

func _port(pos: Vector3,industrial: bool) -> void:
	for x in [-6,6]:GameVisuals.asset(parent,"pier",pos+Vector3(x,-.6,4))
	GameVisuals.asset(parent,"yacht",pos+Vector3(10,-2.65,6))
	if not industrial:GameVisuals.asset(parent,"crane",pos+Vector3(-8,0,-5),.65)

func _water(color: Color) -> void:
	var water=GameVisuals.box(parent,Vector3(0,-3.1,0),Vector3(600,.15,600),color)
	var shader=load("res://assets/shaders/harbor_water.gdshader")
	var mat=ShaderMaterial.new();mat.shader=shader;mat.set_shader_parameter("water_color",color)
	water.material_override=mat
