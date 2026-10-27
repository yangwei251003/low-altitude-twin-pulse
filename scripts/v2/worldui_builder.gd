class_name WorldUIBuilder
extends RefCounted
## Regional kit assembly. Terrain geometry and queries share authored polygons.
const V=preload("res://scripts/visuals.gd")
const L=preload("res://scripts/v2/region_layout.gd")
static var models: Dictionary={}

static func model(parent: Node3D, id: String, p: Vector3=Vector3.ZERO) -> Node3D:
	var path="res://assets/models/worldui/"+id+".glb"
	if not models.has(id):models[id]=load(path)
	var node: Node3D=models[id].instantiate()
	parent.add_child(node);node.position=p
	return node

static func terrain(parent: Node3D, layout: Dictionary, collision: bool=true) -> void:
	for land in layout.get("land",[]):
		var polygon=L.polygon(land.points)
		var indices=Geometry2D.triangulate_polygon(polygon)
		var surface=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var walls=SurfaceTool.new();walls.begin(Mesh.PRIMITIVE_TRIANGLES)
		var h=float(land.height)
		for i in range(0,indices.size(),3):
			var a=polygon[indices[i]];var b=polygon[indices[i+1]];var c=polygon[indices[i+2]]
			# Godot front faces use clockwise winding. XZ polygon winding flips Y.
			for p in [a,b,c]:surface.set_normal(Vector3.UP);surface.add_vertex(Vector3(p.x,h,p.y))
		for i in range(polygon.size()):
			var a=polygon[i];var b=polygon[(i+1)%polygon.size()]
			var n=Vector3(b.y-a.y,0,a.x-b.x).normalized()
			for p in [Vector3(a.x,h,a.y),Vector3(a.x,-3,a.y),Vector3(b.x,h,b.y),Vector3(b.x,h,b.y),Vector3(a.x,-3,a.y),Vector3(b.x,-3,b.y)]:
				surface.set_normal(n);surface.add_vertex(p);walls.set_normal(n);walls.add_vertex(p)
		var node=MeshInstance3D.new();node.name="Terrain_"+str(land.id);node.mesh=surface.commit()
		var material=ShaderMaterial.new();material.shader=preload("res://assets/shaders/worldui_ground.gdshader")
		material.set_shader_parameter("tint",Color(str(land.color)).darkened(.15))
		material.set_shader_parameter("industrial",1.0 if str(layout.region_id)=="R4" else 0.0)
		node.material_override=material;parent.add_child(node)
		if h<=0:node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if collision:node.create_trimesh_collision()
		# Per-mesh light limits in Compatibility require local ground render tiles.
		# The original exact polygon retains its single collision mesh.
		node.mesh=walls.commit()
		terrain_top_tiles(parent,polygon,h,material)
		# A broad retaining lip clarifies raised terraces and engineered waterfronts.
		if str(layout.region_id) in ["R1","R4"]:
			for i in range(polygon.size()):
				var a=polygon[i];var b=polygon[(i+1)%polygon.size()]
				segment(parent,Vector3(a.x,h-.25,a.y),Vector3(b.x,h-.25,b.y),.5,.5,Color("b8b6a2"),false)
	for road in layout.get("roads",[]):
		for i in range(road.points.size()-1):
			var aa=road.points[i];var bb=road.points[i+1]
			var a=Vector3(aa[0],aa[2],aa[1]);var b=Vector3(bb[0],bb[2],bb[1])
			var bridge=bool(road.get("bridge",false))
			if bridge:
				segment(parent,a-Vector3.UP*.2,b-Vector3.UP*.2,float(road.width),.4,Color("9ca79e"),collision)
				var side=Vector3(-(b-a).z,0,(b-a).x).normalized()*float(road.width)*.48
				for sign_m in [-1,1]:
					segment(parent,a+side*sign_m+Vector3.UP*.55,b+side*sign_m+Vector3.UP*.55,.16,1.1,Color("37565a"),collision)
				for t in [.12,.88]:
					var p=a.lerp(b,t)
					for sign_m in [-1,1]:
						var q=p+side*sign_m
						V.box(parent,Vector3(q.x,(q.y-3)*.5,q.z),Vector3(.8,q.y+3,.8),Color("677973"))
						if collision:V.collider(parent,Vector3(q.x,(q.y-3)*.5,q.z),Vector3(.8,q.y+3,.8))
			else:
				var count=maxi(1,ceili(a.distance_to(b)/5.0))
				for j in range(count):
					var p=a.lerp(b,float(j)/count);var q=a.lerp(b,float(j+1)/count)
					var height=L.terrain(layout,(p+q)*.5)
					if height<-.6:continue
					p.y=height+.035;q.y=p.y
					segment(parent,p,q,float(road.width),.06,Color("777f78") if layout.region_id!="R4" else Color("525f60"),false)
					if j%3==0 and layout.region_id!="R3":segment(parent,p+Vector3.UP*.04,q+Vector3.UP*.04,.15,.015,Color("c6b787"),false)
	for route in layout.get("utility_routes",[]):
		for i in range(route.points.size()-1):
			var aa=route.points[i];var bb=route.points[i+1]
			var a=Vector3(aa[0],aa[2]+.08,aa[1]);var b=Vector3(bb[0],bb[2]+.08,bb[1])
			if a.distance_to(b)<.1:continue
			var side=Vector3(-(b-a).z,0,(b-a).x).normalized()
			if str(route.kind)=="rail":
				for sign_m in [-1,1]:segment(parent,a+side*2*sign_m,b+side*2*sign_m,.13,.13,Color("343d3d"),false)
				for j in range(ceili(a.distance_to(b)/3)):
					var p=a.lerp(b,float(j)/maxf(1,ceili(a.distance_to(b)/3)))
					segment(parent,p-side*2.5,p+side*2.5,.25,.08,Color("655e4e"),false)
			else:
				segment(parent,a,b,.65,.12,Color("425254"),false)
				segment(parent,a+Vector3.UP*.08,b+Vector3.UP*.08,.15,.04,Color("9a793e"),false)
	if collision:V.collider(parent,Vector3(300,-3.3,250),Vector3(900,.6,800))

static func segment(parent: Node3D, a: Vector3, b: Vector3, width: float, thickness: float, color: Color, collision: bool) -> Node3D:
	var root=Node3D.new();parent.add_child(root);root.position=(a+b)*.5
	root.rotation.y=atan2((b-a).x,(b-a).z)
	var size=Vector3(width,thickness,a.distance_to(b)+.03)
	var mesh=V.box(root,Vector3.ZERO,size,color)
	if not collision:mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if collision:V.collider(root,Vector3.ZERO,size)
	return root

static func terrain_top_tiles(parent: Node3D, polygon: PackedVector2Array, height: float, material: Material) -> void:
	var bounds=Rect2(polygon[0],Vector2.ZERO)
	for point in polygon:bounds=bounds.expand(point)
	for x in range(floori(bounds.position.x/48),ceili(bounds.end.x/48)):
		for z in range(floori(bounds.position.y/48),ceili(bounds.end.y/48)):
			var origin=Vector2(x*48,z*48)
			var clip=PackedVector2Array([origin,origin+Vector2(48,0),origin+Vector2(48,48),origin+Vector2(0,48)])
			for part in Geometry2D.intersect_polygons(polygon,clip):
				var indices=Geometry2D.triangulate_polygon(part)
				if indices.is_empty():continue
				var surface=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
				for index in indices:
					surface.set_normal(Vector3.UP);surface.add_vertex(Vector3(part[index].x,height,part[index].y))
				var mesh=MeshInstance3D.new();mesh.name="LocalGround";mesh.mesh=surface.commit();mesh.material_override=material
				mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;parent.add_child(mesh)

static func structure(parent: Node3D, data: Dictionary) -> Node3D:
	var root=Node3D.new();root.name=str(data.id);parent.add_child(root)
	root.position=Vector3(data.x,data.get("base_y",0),data.z)
	root.rotation.y=float(data.get("yaw",0))
	var visual=model(root,str(data.asset))
	visual.scale=Vector3.ONE*float(data.get("visual_scale",1))
	var kind=str(data.asset)
	if kind=="turbine":
		V.collider(root,Vector3(0,10.5,0),Vector3(1.6,21,1.6))
		V.collider(root,Vector3(0,20.7,0),Vector3(2.2,1.8,4.2))
		var rotor=visual.find_child("Rotor",true,false)
		if rotor:
			rotor.set_meta("wind_rotor",true)
			for i in range(3):
				var arm=Node3D.new();rotor.add_child(arm);arm.rotation.z=i*TAU/3
				var body=AnimatableBody3D.new();arm.add_child(body);body.collision_layer=1;body.collision_mask=0;body.sync_to_physics=false
				var shape=CollisionShape3D.new();shape.shape=BoxShape3D.new();shape.shape.size=Vector3(.55,7.8,.2);shape.position.y=4.5;body.add_child(shape)
	elif kind in ["test_frame","crane"]:
		var half=4.4 if kind=="test_frame" else 9.0
		var height=7.0 if kind=="test_frame" else 18.0
		for x in [-half,half]:V.collider(root,Vector3(x,height*.5,0),Vector3(1.5,height,3.5))
		V.collider(root,Vector3(0,height,0),Vector3(float(data.w),.8,3.5))
	elif kind=="solar":
		V.collider(root,Vector3(0,2.35,0),Vector3(14,.4,8))
		for x in [-5,0,5]:V.collider(root,Vector3(x,1,0),Vector3(.3,2,5))
	else:V.collider(root,Vector3(0,float(data.h)*.5,0),Vector3(data.w,data.h,data.l))
	if kind=="substation":
		for x in [-5.5,5.5]:segment(root,Vector3(x,.15,-4),Vector3(x,.15,4),.3,.3,Color("b49b58"),false)
	if kind=="warehouse" and ResourceLoader.exists("res://assets/models/worldui/conveyor.glb"):
		for i in range(4):
			var conveyor=model(root,"conveyor",Vector3(-6+i*4,0,10.5));conveyor.scale=Vector3.ONE*2
		var arm=model(root,"robot_arm",Vector3(8,0,10.5));arm.rotation.y=PI
		var scanner=model(root,"scanner_gate",Vector3(-4,0,10.5));scanner.scale=Vector3.ONE*2
		V.collider(root,Vector3(0,.55,10.5),Vector3(16,1.1,2))
	if kind=="crane":
		for x in [-7,7]:
			V.box(root,Vector3(x,17,2.3),Vector3(.8,.3,.3),Color("d4bf86"))
			var light=SpotLight3D.new();root.add_child(light);light.position=Vector3(x,17,2.3);light.rotation_degrees.x=-90
			light.spot_range=21;light.spot_angle=48;light.light_color=Color("e5bc83");light.light_energy=.7;light.shadow_enabled=false
			light.set_meta("worldui_environment_light",true)
		for x in [-9,9]:
			var pool=OmniLight3D.new();root.add_child(pool);pool.position=Vector3(x,4,0)
			pool.omni_range=12;pool.light_energy=.45;pool.light_color=Color("d6af76");pool.shadow_enabled=false
			pool.set_meta("worldui_environment_light",true)
	return root

static func work_area(parent: Node3D, region_id: String, service: bool, bridge: bool) -> void:
	var w=5.8 if bridge else (14.0 if service else 6.0)
	var d=4.6 if bridge else (9.0 if service else 5.0)
	if region_id!="R4":
		var color=Color({"R1":"788b86","R2":"847c63","R3":"53686a"}[region_id])
		var base=V.box(parent,Vector3(0,.016,0),Vector3(w,.025,d),color);base.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if region_id=="R1" and service:
			for x in [-4,0,4]:segment(parent,Vector3(x,.033,-d*.5),Vector3(x,.033,d*.5),.045,.01,Color("667a74"),false)
		if region_id=="R2":
			for x in [-w*.45,w*.45]:
				V.box(parent,Vector3(x,.038,0),Vector3(.4,.018,d*.8),Color("3a4949")).cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				for z in range(-3,4):V.box(parent,Vector3(x,.05,z*.5),Vector3(.42,.01,.07),Color("79817a")).cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if region_id=="R3":
			for i in range(5):V.box(parent,Vector3(w*.45-i*.28,.04,-d*.44),Vector3(.16,.015,.5),Color("b69b55")).cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	else:
		for x in [-4.8,4.8]:
			segment(parent,Vector3(x,.016,-5),Vector3(x,.016,5),.6,.01,Color("475553"),false)
		V.box(parent,Vector3(2,.015,1.3),Vector3(2.7,.018,1.8),Color("445450")).cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for x in [-w*.45,w*.45]:
		for z in [-d*.43,d*.43]:
			var c=Color("a0b9ad") if region_id=="R1" else Color("b7a16a")
			segment(parent,Vector3(x-signf(x)*1.2,.045,z),Vector3(x,.045,z),.10,.012,c,false)
			segment(parent,Vector3(x,.045,z-signf(z)*.7),Vector3(x,.045,z),.10,.012,c,false)

static func poi(parent: Node3D, data: Dictionary, region_id: String, repaired: bool, night: bool, bridge: bool=false) -> void:
	var hidden=bool(data.hidden)
	if hidden:
		V.asset(parent,"crate",Vector3(3,.0,2),.65)
	else:
		# The work area is ordinary ground. Facilities sit outside the action footprint.
		work_area(parent,region_id,data.has("service_function"),bridge)
		if data.has("service_function"):model(parent,"service",Vector3(4.5,0,1.8))
		else:
			V.box(parent,Vector3(4.4,.65,2),Vector3(1.1,1.3,.8),Color("667f79"))
		var lamp=V.box(parent,Vector3(4.4,1.45,2),Vector3(.65,.1,.18),Color("7bc9ad") if repaired else Color("c6a95c"))
		lamp.name="FacilityStatus";lamp.material_override=V.material(Color("7bc9ad") if repaired else Color("c6a95c"),.5)
		var label=Label3D.new();label.name="FacilityLabel";label.text=str(data.name);label.font=load("res://assets/fonts/NotoSansSC-Medium.ttf")
		label.font_size=32;label.pixel_size=.017;label.position=Vector3(0,3.5,0);label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.visibility_range_end=25;parent.add_child(label)
		if night:
			var light=OmniLight3D.new();light.position=Vector3(4.4,2.8,2);light.omni_range=8;light.light_energy=.7;light.light_color=Color("f1c28a");light.shadow_enabled=false;parent.add_child(light)
			light.set_meta("worldui_environment_light",true)

static func decoration(parent: Node3D, data: Dictionary) -> void:
	var point=Vector3(data.x,data.y,data.z)
	match str(data.asset):
		"water_buoy":
			var paint=Color("c39a49") if int(data.variant)==0 else Color("58998e")
			V.cylinder(parent,point+Vector3.UP*.22,.65,.48,Color("445e60"))
			V.cylinder(parent,point+Vector3.UP*.85,.16,1.5,paint)
			var reflector=V.box(parent,point+Vector3.UP*1.58,Vector3(.5,.24,.5),paint)
			reflector.material_override=V.material(paint,.8)
			var lamp=OmniLight3D.new();parent.add_child(lamp);lamp.position=point+Vector3.UP*1.8
			lamp.omni_range=4;lamp.light_energy=.15;lamp.light_color=paint;lamp.shadow_enabled=false;lamp.set_meta("worldui_environment_light",true)
		"planter":
			V.box(parent,point+Vector3.UP*.3,Vector3(3.2,.6,1.6),Color("8e9b8b"))
			V.asset(parent,"cypress",point+Vector3.UP*.6,.85)
		"rock":model(parent,"shore_rock",point-Vector3.UP*.25).scale=Vector3.ONE*(.4+int(data.variant)*.12)
		"cargo":V.asset(parent,"crate",point,.9+int(data.variant)*.15)
		"shore_rock":
			var rock=model(parent,"shore_rock",point+Vector3.UP*.6)
			rock.rotation.y=float(data.get("yaw",0));rock.scale=Vector3.ONE*float(data.get("scale",3.2))*.35
		"grove":
			V.box(parent,point+Vector3.UP*.10,Vector3(7,.2,5),Color("526c47"))
			for p in [Vector3(-2,0,0),Vector3(1,0,-1.5),Vector3(2.5,0,1.2)]:V.asset(parent,"garden_oak",point+p,.8)
		"scrub","coast_grove":
			for p in [Vector3(-2,0,1),Vector3(2,0,-1)]:
				model(parent,"shore_rock",point+p).scale=Vector3.ONE*.45
				V.asset(parent,"garden_hedge",point+p+Vector3(1,0,.4),.65)
		"yard":
			var frame=Node3D.new();parent.add_child(frame);frame.position=point;frame.rotation.y=float(data.get("yaw",0))
			for i in range(2):
				var scrap=load("res://assets/models/v22_combat/"+("wreck_panel" if i==0 else "wreck_rotor")+".glb").instantiate()
				frame.add_child(scrap);scrap.position=Vector3(-1.2+i*2.1,.1,i*.7);scrap.scale=Vector3.ONE*(2.4 if i==0 else 1.7);scrap.rotation.y=i*1.3
			for x in [-2,0,1]:
				var metal=V.box(frame,Vector3(x,.12,.7),Vector3(1.8,.12,.6),Color("634c3b"));metal.rotation.y=x*.3
			V.cylinder(frame,Vector3(3,.4,0),.32,.8,Color("55584c"))
