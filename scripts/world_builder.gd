class_name HarborWorld
extends RefCounted

static func build(parent: Node3D) -> void:
	var floor_color = Color("c9c5b8")
	GameVisuals.box(parent,Vector3(0,-0.85,0),Vector3(45,1.5,30),Color("899b99"))
	GameVisuals.box(parent,Vector3(0,-0.08,0),Vector3(44.5,0.2,29.5),floor_color)
	GameVisuals.collider(parent,Vector3(0,-0.5,0),Vector3(44.5,1,29.5))
	# Deliberately quiet paving and broad cross paths.
	for x in range(-21,22,3):
		GameVisuals.box(parent,Vector3(x,0.028,0),Vector3(0.023,0.012,29.3),Color("b4b7ad"))
	for z in range(-14,15,3):
		GameVisuals.box(parent,Vector3(0,0.032,z),Vector3(44.2,0.012,0.023),Color("b4b7ad"))
	GameVisuals.box(parent,Vector3(0,0.035,0),Vector3(43,0.03,4.5),Color("d9d6c9"))
	GameVisuals.box(parent,Vector3(-12,0.036,0),Vector3(4.5,0.03,27),Color("d9d6c9"))
	GameVisuals.box(parent,Vector3(11,0.035,0),Vector3(4.8,0.03,27),Color("d9d6c9"))
	for x in [-21.6,21.6]:
		GameVisuals.box(parent,Vector3(x,0.04,0),Vector3(0.28,0.16,29.0),Color("e3dfcf"))
	for z in [-14.3,14.3]:
		GameVisuals.box(parent,Vector3(0,0.04,z),Vector3(43.3,0.16,0.28),Color("e3dfcf"))
	# Non-occluding border collision; the view never leaves the island.
	for pair in [[Vector3(-22,4,0),Vector3(0.5,10,30)],[Vector3(22,4,0),Vector3(0.5,10,30)],[Vector3(0,4,-14.5),Vector3(44,10,0.5)],[Vector3(0,4,14.5),Vector3(44,10,0.5)]]:
		GameVisuals.collider(parent,pair[0],pair[1])
	var water = GameVisuals.box(parent,Vector3(0,-1.45,0),Vector3(160,0.10,130),Color("367d88"))
	var shader = Shader.new()
	shader.code = "shader_type spatial; render_mode cull_disabled; void fragment(){ vec2 p=VERTEX.xz; float w=sin(p.x*2.4+TIME*0.25)*sin(p.y*1.7-TIME*0.18); ALBEDO=mix(vec3(0.05,0.25,0.30),vec3(0.11,0.40,0.44),w*0.18+0.62); ROUGHNESS=0.25; METALLIC=0.20; }"
	var water_mat = ShaderMaterial.new(); water_mat.shader=shader; water.material_override=water_mat
	GameVisuals.asset(parent,"hangar",Vector3(-16,0,-11.2))
	GameVisuals.collider(parent,Vector3(-16,1.8,-11.2),Vector3(6.6,3.6,4.5))
	GameVisuals.asset(parent,"hangar",Vector3(15.8,0,-11.2)).rotation.y=0.0
	GameVisuals.collider(parent,Vector3(15.8,1.8,-11.2),Vector3(6.6,3.6,4.5))
	for pos in [Vector3(-19,0,-5),Vector3(-18,0,3),Vector3(-5,0,-11),Vector3(4,0,-11),Vector3(19,0,8)]:
		GameVisuals.asset(parent,"tree",pos)
		GameVisuals.collider(parent,pos+Vector3(0,1,0),Vector3(1.3,2,1.3))
	for pos in [Vector3(-5,0,5),Vector3(5,0,-5),Vector3(5,0,8),Vector3(-3,0,-5)]:
		GameVisuals.asset(parent,"planter",pos)
		GameVisuals.collider(parent,pos+Vector3(0,0.42,0),Vector3(2.8,0.84,1.4))
	for pos in [Vector3(-9,0,-2),Vector3(6,0,3),Vector3(14,0,5),Vector3(-2,0,9)]:
		GameVisuals.asset(parent,"cover",pos)
		GameVisuals.collider(parent,pos+Vector3(0,0.8,0),Vector3(2.4,1.6,1.0))
	GameVisuals.asset(parent,"canopy",Vector3(0,0,-2.5))
	for x in [-2,2]:GameVisuals.collider(parent,Vector3(x,1.75,-2.5),Vector3(0.35,3.5,0.55))
	GameVisuals.collider(parent,Vector3(0,3.55,-2.5),Vector3(4.5,0.28,1.8))
	for x in [-18,-8,3,16]:
		GameVisuals.asset(parent,"dock",Vector3(x,-0.2,16.3))
		GameVisuals.asset(parent,"lamp",Vector3(x,0,13.3))
	GameVisuals.asset(parent,"pad",Vector3(-14,0,8))
	GameVisuals.ring(parent,Vector3(11,0.05,-4),5.0,Color("a3b8b1"),0.07)
	GameVisuals.ring(parent,Vector3(11,0.052,-4),5.3,Color("a3b8b1"),0.025)
	# Lawn islands at quiet edge areas.
	for pos in [Vector3(-18,0.02,6),Vector3(-6,0.02,-10),Vector3(3,0.02,11),Vector3(19,0.02,5)]:
		GameVisuals.box(parent,pos,Vector3(3,0.04,3),Color("829582"))
	for x in range(-20,22,2):
		GameVisuals.box(parent,Vector3(x,0.22,14),Vector3(0.12,0.42,0.12),Color("657f80"))
	# Distant rocks below the play plane make an intentional miniature silhouette.
	var rng = RandomNumberGenerator.new();rng.seed=313
	for i in range(30):
		var a = float(i)/30*TAU
		var pos = Vector3(cos(a)*25,-1.0,sin(a)*18)
		var rock=GameVisuals.sphere(parent,pos,rng.randf_range(0.7,1.4),Color("879c99"))
		rock.scale=Vector3(1.6,0.6,1.0)
