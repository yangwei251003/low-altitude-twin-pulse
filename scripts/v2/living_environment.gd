class_name LivingEnvironmentV22
extends Node3D
## Bounded near-field activity. Configure once; the owner only supplies focus and input.
signal environment_event(event: Dictionary)
signal environment_changed(state: Dictionary)

const Field = preload("res://scripts/v2/environment_field.gd")
const FOLIAGE = preload("res://assets/shaders/v22/foliage.gdshader")
const RAIN = preload("res://assets/shaders/v22/rain.gdshader")
const WATER = preload("res://assets/shaders/v22/water_response.gdshader")
const AIRFLOW = preload("res://assets/shaders/v22/airflow.gdshader")
const ANCHORS = Field.ANCHORS
const MODEL_PATH = "res://assets/models/v22/"
const MAX_CARS = 8
const MAX_PEDESTRIANS = 16
const MAX_MACHINES = 2
const MAX_EXTRA_RIGID_BODIES = 8
var field = Field.new()
var world: Node3D
var region_id = "R1"
var layout: Dictionary = {}
var _road_segment: Dictionary = {}
var dock_base_y = -.5
var settings: Dictionary = {}
var focus = Vector3.ZERO
var anchor = Vector3.ZERO
var interaction_hint = ""
var platform_locked = false
var dock_locked = false
var scenery_root: Node3D
var platform: AnimatableBody3D
var crane_hook_body: AnimatableBody3D
var dock: AnimatableBody3D
var platform_velocity = Vector3.ZERO
var dock_velocity = Vector3.ZERO
var platform_top = 0.45
var dock_top = 0.65
var platform_clock = 0.0
var dock_clock = 0.0
var fan_rotor: Node3D
var crane_hook: Node3D
var crane_trolley: Node3D
var weather_vane: Node3D
var anemometer: Node3D
var control_label: Label3D
var status_beacon: MeshInstance3D
var cars: Array[Dictionary] = []
var pedestrians: Array[Dictionary] = []
var birds: Array[Dictionary] = []
var loose_props: Array[Dictionary] = []
var passive_surfaces: Array[Dictionary] = []
var shore_surfaces: Array[Dictionary] = []
var wind_material: ShaderMaterial
var reed_material: ShaderMaterial
var water_materials: Array[ShaderMaterial] = []
var rain_material: ShaderMaterial
var rain_mesh: MultiMeshInstance3D
var fan_flow: MultiMeshInstance3D
var fan_flow_material: ShaderMaterial
var fan_visual_speed = 0.0
var interference_label: Label3D
var interference_beacon: MeshInstance3D
var interference_ring: MeshInstance3D
var _was_interference = false
var adopted_chunks: Dictionary = {}
var model_cache: Dictionary = {}
var _scene_scan_left = 0.0
var _event_left = 0.0
var _interact_left = 0.0
var _last_machine_phase = -1
var _warned_machine_leg = -1
var _last_encounter_phase = "idle"
var encounter_beacons: Array[MeshInstance3D] = []
var _configured = false
var _cached_sample: Dictionary = {}
var _rain_rng = RandomNumberGenerator.new()

func configure(value_world: Node3D, id: String, value_seed: int, value_settings: Dictionary) -> void:
	world = value_world; region_id = id; settings = value_settings.duplicate(true)
	anchor = ANCHORS.get(id,Vector3(112,0,80))
	var authored: Variant = world.get("layout") if world!=null else null
	layout = authored if authored is Dictionary else {}
	var coordinates: Array = layout.get("living_anchor",[])
	if coordinates.size()==3: anchor=Vector3(float(coordinates[0]),float(coordinates[1]),float(coordinates[2]))
	focus = anchor
	var obstacles: Array = world.get("obstacles") if world != null and world.get("obstacles") != null else []
	field.configure(id,value_seed,settings,obstacles)
	if world!=null: field.configure_world(world)
	_rain_rng.seed = value_seed+2210
	process_priority = 20
	wind_material = ShaderMaterial.new(); wind_material.shader = FOLIAGE
	reed_material = ShaderMaterial.new(); reed_material.shader = FOLIAGE; reed_material.set_shader_parameter("sway_scale",0.045)
	scenery_root = Node3D.new(); scenery_root.name = "LivingDistrictV22"; add_child(scenery_root)
	_build_station()
	match region_id:
		"R1": _build_technology()
		"R2": _build_industry()
		"R3": _build_coast()
		"R4": _build_port()
	_build_encounter_markers()
	_build_rain()
	_configured = true
	_cached_sample = field.sample(focus)
	update_focus(focus)

func set_settings(value: Dictionary) -> void:
	settings.merge(value,true)
	field.set_settings(settings)

func set_weather(value: String) -> void:
	field.set_weather(value)
	settings["weather_preset"] = field.weather_target
	_emit("weather_selected",anchor,{"weather":field.weather_target})

func update_focus(position_m: Vector3) -> void:
	if not position_m.is_finite(): return
	focus = position_m
	field.update_focus(position_m)
	interaction_hint = get_interaction_hint(position_m)

func sample(position_m: Vector3) -> Dictionary:
	return field.sample(position_m)

func get_interaction_hint(position_m: Vector3) -> String:
	if position_m.distance_to(_control_position()+Vector3.UP*1.2)>5.5: return ""
	match region_id:
		"R1": return "F · 气象站：切换观测天气（缓慢变化）"
		"R2": return "F · "+("关闭风机，开启避风通道" if field.fan_enabled else "启动通风机")
		"R3": return "F · "+("固定浮码头，平稳降落" if not dock_locked else "释放浮码头，观察水面起伏")
		"R4": return "F · "+("暂停吊机并锁定卸货台" if not platform_locked else "解除锁定，恢复港口作业")
	return ""

func interact(position_m: Vector3) -> Dictionary:
	if _interact_left>0.0 or get_interaction_hint(position_m).is_empty(): return {"used":false,"message":""}
	_interact_left = 0.5
	var message = ""
	var kind = ""
	match region_id:
		"R1":
			if not field.weather_enabled or field.weather_multiplier<=0.0: return {"used":true,"message":"天气变化已关闭，可在环境设置中调高天气强度","event":"weather_disabled"}
			var options = ["clear","breeze","mist","rain"]
			set_weather(options[(options.find(field.weather_target)+1)%options.size()])
			message = "气象观测："+{"clear":"晴朗","breeze":"海风","mist":"薄雾","rain":"小雨"}[field.weather_target]+"，环境正在平滑变化"
			kind = "weather_selected"
		"R2":
			field.fan_enabled = not field.fan_enabled
			field.interference_source_enabled = field.fan_enabled
			message = "通风机已停止，风口附近可以平稳作业" if not field.fan_enabled else "通风机已启动，旗帜提示出风方向"
			kind = "fan_stopped" if not field.fan_enabled else "fan_started"
		"R3":
			dock_locked = not dock_locked
			message = "浮码头已固定，可以缓降停靠" if dock_locked else "浮码头已释放，海风推动水面与码头起伏"
			kind = "dock_locked" if dock_locked else "dock_released"
		"R4":
			platform_locked = not platform_locked
			field.interference_source_enabled = not platform_locked
			message = "卸货台已锁定，吊机暂停，可在平台上降落" if platform_locked else "港口作业恢复，观察黄灯和停靠窗口"
			kind = "platform_locked" if platform_locked else "platform_released"
	_refresh_label()
	if kind!="weather_selected": _emit(kind,_control_position(),{"active":field.fan_enabled if region_id=="R2" else not platform_locked})
	return {"used":true,"message":message,"event":kind}

func get_surface_at(position_m: Vector3) -> Dictionary:
	# Only advertise surfaces actually created here. Terrain remains the world's responsibility.
	var best: Dictionary = {"valid":false}
	for shore in shore_surfaces:
		var bounds: AABB=shore.bounds
		if not bounds.has_point(Vector3(position_m.x,bounds.get_center().y,position_m.z)): continue
		var vertices: PackedVector3Array=shore.faces
		for index in range(0,vertices.size(),3):
			var a=vertices[index];var b=vertices[index+1];var c=vertices[index+2]
			var denominator=(b.z-c.z)*(a.x-c.x)+(c.x-b.x)*(a.z-c.z)
			if absf(denominator)<.00001: continue
			var u=((b.z-c.z)*(position_m.x-c.x)+(c.x-b.x)*(position_m.z-c.z))/denominator
			var v=((c.z-a.z)*(position_m.x-c.x)+(a.x-c.x)*(position_m.z-c.z))/denominator
			var w=1.0-u-v
			if minf(u,minf(v,w)) < -.0001: continue
			var height=u*a.y+v*b.y+w*c.y
			if not best.valid or height>float(best.height):
				var normal=(b-a).cross(c-a).normalized()
				if normal.y<0: normal=-normal
				best={"valid":true,"height":height,"normal":normal,"material":"rock","water":height<float(layout.get("water_level",-.6)),"water_height":float(layout.get("water_level",-.6)),"surface_velocity":Vector3.ZERO,"id":"shore_bank"}
	for surface in passive_surfaces:
		var rect: Rect2 = surface.rect
		if rect.has_point(Vector2(position_m.x,position_m.z)):
			if not best.valid or float(surface.height)>float(best.height): best = {"valid":true,"height":surface.height,"normal":Vector3.UP,"material":"wood","water":false,"surface_velocity":Vector3.ZERO,"id":surface.id}
	for entry in [{"body":platform,"top":platform_top,"size":Vector2(4.6,3.4),"velocity":platform_velocity,"id":"port_platform"},{"body":dock,"top":dock_top,"size":Vector2(3.1,5.1),"velocity":dock_velocity,"id":"floating_dock"}]:
		var body = entry.body
		if not is_instance_valid(body): continue
		var p: Vector3 = body.global_position
		var half: Vector2 = entry.size*0.5
		if absf(position_m.x-p.x)<=half.x and absf(position_m.z-p.z)<=half.y:
			var top: float = p.y+float(entry.top)
			if not best.valid or top>float(best.height): best = {"valid":true,"height":top,"normal":Vector3.UP,"material":"wood","water":false,"surface_velocity":entry.velocity,"id":entry.id}
	return best

func snapshot() -> Dictionary:
	var traffic: Array = []
	for car in cars: traffic.append(float(car.distance))
	return {"version":1,"field":field.snapshot(),"platform_locked":platform_locked,"dock_locked":dock_locked,"platform_clock":platform_clock,"dock_clock":dock_clock,"traffic":traffic}

func restore(data: Dictionary) -> void:
	field.restore(data.get("field",{}))
	_last_encounter_phase=field.event_phase
	platform_locked = bool(data.get("platform_locked",false)); dock_locked = bool(data.get("dock_locked",false))
	platform_clock = maxf(0,float(data.get("platform_clock",0.0))); dock_clock = maxf(0,float(data.get("dock_clock",0.0)))
	var traffic: Array = data.get("traffic",[])
	for i in mini(traffic.size(),cars.size()): cars[i].distance = maxf(0,float(traffic[i]))
	_place_machines(0.0)
	_refresh_label()

func _control_position() -> Vector3:
	return anchor+Vector3(5,0,4) if region_id=="R4" else anchor+Vector3(-4,.2 if region_id in ["R1","R2"] else 0,-2)

func _build_station() -> void:
	var station = _model("weather_station",scenery_root,_control_position())
	weather_vane = _find_part(station,"WindVane")
	anemometer = _find_part(station,"Anemometer")
	_add_collider(scenery_root,_control_position()+Vector3(0,0.7,0),Vector3(0.8,1.4,0.65))
	control_label = Label3D.new()
	control_label.font = load("res://assets/fonts/NotoSansSC-Medium.ttf")
	control_label.font_size = 30; control_label.pixel_size = 0.018
	control_label.position = _control_position()+Vector3(0,4.3,0)
	control_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	control_label.no_depth_test = false
	control_label.visibility_range_end = 34
	control_label.modulate = Color("e3e9d7")
	scenery_root.add_child(control_label)
	status_beacon = _beacon(scenery_root,_control_position()+Vector3(0.5,1.25,0),Color("7ed8a1"),0.1)
	_refresh_label()

func _authored_segment() -> Dictionary:
	if not _road_segment.is_empty(): return _road_segment
	var best_distance = INF
	for road in layout.get("roads",[]):
		if bool(road.get("bridge",false)): continue
		var points: Array = road.get("points",[])
		for i in range(points.size()-1):
			var a=Vector3(float(points[i][0]),float(points[i][2]),float(points[i][1]))
			var b=Vector3(float(points[i+1][0]),float(points[i+1][2]),float(points[i+1][1]))
			var along=Vector3(b.x-a.x,0,b.z-a.z).normalized()
			if a.distance_to(b)<18: continue
			var near=Geometry3D.get_closest_point_to_segment(Vector3(anchor.x,a.y,anchor.z),a,b)
			var length_m=a.distance_to(b)
			near=a+along*clampf(a.distance_to(near),9.0,length_m-9.0)
			var distance_m=Vector2(near.x-anchor.x,near.z-anchor.z).length()
			if distance_m>=best_distance: continue
			near.y=world.surface_height(near)
			best_distance=distance_m
			_road_segment={"center":near,"along":along,"side":Vector3(along.z,0,-along.x),"half":float(road.get("width",10))*.5}
	if _road_segment.is_empty():
		_road_segment={"center":anchor,"along":Vector3.FORWARD,"side":Vector3.LEFT,"half":5.0}
	return _road_segment

func _road_route() -> PackedVector3Array:
	var result=PackedVector3Array()
	for road in layout.get("roads",[]):
		if bool(road.get("bridge",false)): continue
		for raw in road.get("points",[]):
			var p=Vector3(float(raw[0]),float(raw[2]),float(raw[1]))
			p.y=world.surface_height(p)
			result.append(p)
		if result.size()>=2:
			# Out-and-back, never close an open authored road with a cross-country chord.
			for i in range(result.size()-2,0,-1): result.append(result[i])
			return result
	return PackedVector3Array([anchor+Vector3(-10,0,-28),anchor+Vector3(86,0,-28),anchor+Vector3(86,0,18),anchor+Vector3(-10,0,18)])

func _crossing_markings(segment: Dictionary) -> void:
	var center: Vector3=segment.center
	var side: Vector3=segment.side
	var along: Vector3=segment.along
	var material=StandardMaterial3D.new();material.albedo_color=Color("b9c0b5");material.roughness=1.0
	for i in range(7):
		var mark=MeshInstance3D.new();var box=BoxMesh.new()
		box.size=Vector3(float(segment.half)*2.0/9.0,.018,2.1);mark.mesh=box;mark.material_override=material
		mark.position=center+side*(float(i)-3.0)*float(segment.half)*2.0/7.0+Vector3.UP*.025
		mark.basis=Basis(side,Vector3.UP,along);mark.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		scenery_root.add_child(mark)

func _build_technology() -> void:
	var route = _road_route()
	for i in 4:
		var actor = AnimatableBody3D.new(); actor.name = "TrafficCar_%d"%i
		actor.collision_layer = 1; actor.collision_mask = 2|8; actor.sync_to_physics = true
		scenery_root.add_child(actor)
		var car_model = _external_model("res://assets/v2/streets/"+["car_sedan","car_suv","car_delivery","car_sedan"][i]+".glb",actor,Vector3.ZERO)
		var shape = CollisionShape3D.new(); var box = BoxShape3D.new(); box.size = Vector3(1.75,1.3,3.9)
		shape.shape=box; shape.position.y=.65; actor.add_child(shape)
		cars.append({"body":actor,"distance":i*71.0,"route":route,"speed":3.6,"collider":shape})
	_build_pedestrians(12)
	_build_interference_marker()
	_crossing_markings(_authored_segment())
	for p in [route[0],route[mini(2,route.size()-1)]]:
		_model("construction_barrier",scenery_root,p+Vector3(7,0,5),PI/2)

func _build_industry() -> void:
	var fan = _model("ventilator",scenery_root,anchor)
	fan_rotor = _find_part(fan,"FanRotor")
	_add_collider(scenery_root,anchor+Vector3(0,1.5,0),Vector3(2.15,3.0,1.15))
	for side in [-1,1]:
		_model("construction_barrier",scenery_root,anchor+Vector3(side*4,0,4),PI/2)
		_add_collider(scenery_root,anchor+Vector3(side*4,.65,4),Vector3(.3,1.3,2.8))
	for i in 3:
		var body = RigidBody3D.new(); body.name = "LightWorkCrate_%d"%i
		body.mass = 0.8; body.collision_layer = 1; body.collision_mask = 1|2|8
		body.continuous_cd = true; body.linear_damp = .5; body.angular_damp = 1.5
		var material = PhysicsMaterial.new();material.friction=.7;material.bounce=.04;body.physics_material_override=material
		scenery_root.add_child(body)
		body.position = anchor+Vector3(-1+i,.4,7+i)
		var shape = CollisionShape3D.new(); var box=BoxShape3D.new();box.size=Vector3(.6,.6,.6);shape.shape=box;body.add_child(shape)
		var model = _external_model("res://assets/models/crate.glb",body,Vector3(0,-.3,0))
		if model != null: model.scale=Vector3.ONE*.6
		loose_props.append({"body":body,"home":body.position})
	_build_pedestrians(4)
	_build_airflow()

func _build_interference_marker() -> void:
	var position_m: Vector3=field.event_definition().center
	position_m.y=world.surface_height(position_m)+.07
	interference_ring=MeshInstance3D.new()
	var ring=TorusMesh.new();ring.inner_radius=12.93;ring.outer_radius=13.07;ring.rings=64;ring.ring_segments=6
	interference_ring.mesh=ring;interference_ring.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material=StandardMaterial3D.new();material.albedo_color=Color("c5a467");material.roughness=1.0
	interference_ring.material_override=material;interference_ring.visibility_range_end=70
	scenery_root.add_child(interference_ring);interference_ring.position=position_m
	interference_beacon=_beacon(scenery_root,position_m+Vector3(-5,1.5,-5),Color("e3ae55"),.16)
	interference_label=Label3D.new();interference_label.font=load("res://assets/fonts/NotoSansSC-Medium.ttf")
	interference_label.font_size=28;interference_label.pixel_size=.021;interference_label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	interference_label.no_depth_test=false;interference_label.visibility_range_end=38
	interference_label.position=position_m+Vector3(-5,3,-5);scenery_root.add_child(interference_label)
	interference_label.text="分流塔 · 导航干扰范围\n离开黄色环线后恢复"

func _build_airflow() -> void:
	fan_flow_material=ShaderMaterial.new();fan_flow_material.shader=AIRFLOW
	var quad=QuadMesh.new();quad.size=Vector2(.05,.36);quad.material=fan_flow_material
	var multi=MultiMesh.new();multi.transform_format=MultiMesh.TRANSFORM_3D;multi.use_custom_data=true;multi.mesh=quad;multi.instance_count=24
	for i in multi.instance_count:
		multi.set_instance_transform(i,Transform3D(Basis(Vector3.UP,PI*.25),Vector3(_rain_rng.randf_range(-.8,.8),_rain_rng.randf_range(-.7,.7),0)))
		multi.set_instance_custom_data(i,Color(_rain_rng.randf(),_rain_rng.randf(),0,1))
	multi.custom_aabb=AABB(Vector3(-2,-2,0),Vector3(4,4,14))
	fan_flow=MultiMeshInstance3D.new();fan_flow.multimesh=multi;fan_flow.position=anchor+Vector3(0,1.8,.8);fan_flow.visibility_range_end=60
	fan_flow.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;scenery_root.add_child(fan_flow)

func _build_encounter_markers() -> void:
	# Small status lamps locate the effect without turning it into a mission gate.
	var positions: Array[Vector3]=[]
	match region_id:
		"R2": positions=[anchor+Vector3(-3.5,.85,2),anchor+Vector3(3.5,.85,12)]
		"R3": positions=[anchor+Vector3(6.6,1.0,-12),anchor+Vector3(6.6,1.0,12)]
		"R4": positions=[anchor+Vector3(-5,.85,-5),anchor+Vector3(5,.85,7)]
	for p in positions:
		var post=MeshInstance3D.new();var cylinder=CylinderMesh.new();cylinder.top_radius=.05;cylinder.bottom_radius=.07;cylinder.height=.8;cylinder.radial_segments=8;post.mesh=cylinder
		var material=StandardMaterial3D.new();material.albedo_color=Color("597677");post.material_override=material
		scenery_root.add_child(post);post.position=p-Vector3.UP*.4
		encounter_beacons.append(_beacon(scenery_root,p,Color("7ed8a1"),.13))

func _build_coast() -> void:
	dock_base_y=float(layout.get("water_level",-.6))+.1
	dock = _moving_body("FloatingDock",Vector3(anchor.x+12,dock_base_y,anchor.z),"floating_dock",Vector3(3.1,.18,5.1),.56)
	var bridge = _model("bridge_deck",scenery_root,anchor+Vector3(7.4,-.1,0))
	if bridge != null: bridge.scale=Vector3(.55,.55,.5)
	_add_collider(scenery_root,anchor+Vector3(7.4,.04,0),Vector3(6.6,.28,2.8))
	passive_surfaces.append({"id":"dock_access_bridge","rect":Rect2(anchor.x+4.1,anchor.z-1.4,6.6,2.8),"height":anchor.y+.18})
	for side in [-1,1]:
		var bank = _model("shore_bank",scenery_root,anchor+Vector3(12+side*2.0,-1.5,12),side*PI/2)
		_add_shore_surface(bank)
	_build_reeds()
	for i in 6:
		var gull=_model("seagull",scenery_root,anchor+Vector3(12,7,0))
		birds.append({"body":gull,"phase":float(i)*1.04,"left":_find_part(gull,"WingLeft"),"right":_find_part(gull,"WingRight")})
	_build_pedestrians(6)

func _build_reeds() -> void:
	var source=load(MODEL_PATH+"shore_reeds.glb").instantiate()
	var mesh_node=_find_mesh(source)
	if mesh_node==null: source.free();return
	var multi=MultiMesh.new();multi.transform_format=MultiMesh.TRANSFORM_3D;multi.mesh=mesh_node.mesh;multi.instance_count=18
	var origin=anchor+Vector3(12,.22,0)
	for i in multi.instance_count:
		var p=anchor+Vector3(6.4 if i%2==0 else 17.5,.22,-13+i*1.5)-origin
		multi.set_instance_transform(i,Transform3D(Basis(Vector3.UP,float(i)*1.2),p))
	var reeds=MultiMeshInstance3D.new();reeds.name="CoastalReeds";reeds.multimesh=multi;reeds.material_override=reed_material
	reeds.position=origin;reeds.visibility_range_end=80;reeds.extra_cull_margin=.5;reeds.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scenery_root.add_child(reeds)
	source.free()

func _build_port() -> void:
	var crane = _model("gantry_crane",scenery_root,anchor)
	crane_hook = _find_part(crane,"Hook"); crane_trolley = _find_part(crane,"Trolley")
	for side in [-1,1]: _add_collider(scenery_root,anchor+Vector3(side*4,3,0),Vector3(.55,6,.65))
	_add_collider(scenery_root,anchor+Vector3(0,6.1,0),Vector3(8.8,.7,.8))
	crane_hook_body=AnimatableBody3D.new();crane_hook_body.name="CraneHookContact";crane_hook_body.collision_layer=1;crane_hook_body.collision_mask=2|8;crane_hook_body.sync_to_physics=true
	scenery_root.add_child(crane_hook_body);crane_hook_body.position=anchor+Vector3(0,3.08,0)
	var hook_shape=CollisionShape3D.new();var hook_box=BoxShape3D.new();hook_box.size=Vector3(1.2,.35,.65);hook_shape.shape=hook_box;crane_hook_body.add_child(hook_shape)
	platform = _moving_body("PortLiftPlatform",anchor+Vector3(0,.1,4),"lift_platform",Vector3(4.6,.38,3.4),.26)
	_model("construction_barrier",scenery_root,anchor+Vector3(-5,0,5),PI/2)
	_build_pedestrians(6)

func _build_pedestrians(count: int) -> void:
	var segment=_authored_segment()
	var center: Vector3=segment.center
	var along: Vector3=segment.along
	var side: Vector3=segment.side
	var half=float(segment.half)
	var route=PackedVector3Array([center-along*8+side*(half+1.5),center+along*8+side*(half+1.5),center+along*8+side*(half+2.8),center-along*8+side*(half+2.8)])
	for j in route.size(): route[j].y=world.surface_height(route[j])+.2

	var walkers=8 if region_id=="R1" else mini(count,MAX_PEDESTRIANS)
	var route_length=0.0
	for j in route.size(): route_length+=route[j].distance_to(route[(j+1)%route.size()])
	for i in mini(count,MAX_PEDESTRIANS):
		var person_route=route
		var crossing=region_id=="R1" and i in [8,9]
		var waiting=region_id=="R1" and i>=10
		var distance_m=route_length*float(i)/maxf(1.0,float(walkers))+3.0
		if crossing:
			var cross_center=center+along*(-.4 if i==8 else .4)+Vector3.UP*.2
			person_route=PackedVector3Array([cross_center-side*(half+2.4),cross_center+side*(half+2.4)])
			distance_m=0.0 if i==8 else (half+2.4)*2.0
		var initial=_route_point(person_route,distance_m)
		if waiting: initial={"position":center+side*(half+3.8)+along*(-4+float(i-10)*1.1)+Vector3.UP*.2,"direction":-side}
		var model=_model(["pedestrian_worker","pedestrian_walker","pedestrian_citizen"][i%3],scenery_root,initial.position)
		if model==null: continue
		var direction: Vector3=initial.direction
		model.rotation.y=atan2(direction.x,direction.z)
		var animation=_find_animation(model)
		if animation != null:
			for animation_name in animation.get_animation_list():
				if animation_name=="RESET": continue
				var resource=animation.get_animation(animation_name);resource.loop_mode=Animation.LOOP_LINEAR
				animation.play(animation_name);animation.seek(0.0 if waiting else float(i)*.13,true);animation.speed_scale=0.0 if waiting else 1.0;break
		pedestrians.append({"body":model,"route":person_route,"distance":distance_m,"speed":.82+float(i%3)*.12,"animation":animation,"crossing":crossing,"waiting":waiting,"crossing_center":center,"crossing_axis":side,"road_half":half})

func _moving_body(id: String, p: Vector3, model_id: String, size: Vector3, shape_y: float) -> AnimatableBody3D:
	var body=AnimatableBody3D.new();body.name=id;body.collision_layer=1;body.collision_mask=2|8;body.sync_to_physics=true
	scenery_root.add_child(body);body.position=p
	_model(model_id,body,Vector3.ZERO)
	var shape=CollisionShape3D.new();var box=BoxShape3D.new();box.size=size;shape.shape=box;shape.position.y=shape_y;body.add_child(shape)
	return body

func _physics_process(delta: float) -> void:
	if not _configured: return
	field.advance(delta)
	if field.event_phase!=_last_encounter_phase:
		var previous_phase=_last_encounter_phase
		_last_encounter_phase=field.event_phase
		var definition=field.event_definition()
		var payload={"event_phase":field.event_phase,"event_kind":definition.kind,"event_seconds":field.event_remaining,"event_label":definition.label,"radius":float(definition.radius)+6.0}
		if field.event_phase=="warning": _emit("environment_warning",definition.center,payload)
		elif field.event_phase=="active": _emit("environment_active",definition.center,payload)
		elif previous_phase in ["warning","active"]: _emit("environment_cleared",definition.center,payload)
	_interact_left=maxf(0,_interact_left-delta)
	_cached_sample=field.sample(focus)
	_place_machines(delta)
	_update_cars(delta)
	_update_pedestrians(delta)
	_update_birds(delta)
	for item in loose_props:
		var body: RigidBody3D=item.body
		var near=body.global_position.distance_to(focus)<55.0
		body.freeze=not near
		if near:
			var relative=body.linear_velocity-Vector3(field.sample(body.global_position).wind_velocity)
			body.apply_central_force((-relative*relative.length()*.018).limit_length(2.0))
		if body.global_position.y < -3 or body.global_position.distance_to(item.home)>22:
			body.global_position=item.home;body.linear_velocity=Vector3.ZERO;body.angular_velocity=Vector3.ZERO
	_event_left-=delta
	if _event_left<=0:
		_event_left=.25
		environment_changed.emit(_cached_sample)
		var affected=float(_cached_sample.get("interference_strength",0))>.015
		if affected!=_was_interference:
			_was_interference=affected
			_emit("interference_enter" if affected else "interference_exit",focus,{"nav_quality":_cached_sample.get("nav_quality",1.0)})
		_refresh_label()
	_scene_scan_left-=delta
	if _scene_scan_left<=0:
		_scene_scan_left=.75
		_adopt_streamed_scenery()

func _place_machines(delta: float) -> void:
	if is_instance_valid(platform):
		var previous=platform.position
		if not platform_locked: platform_clock+=delta
		var cycle=fmod(platform_clock,16.0)
		var blend=0.0
		if cycle>4.0 and cycle<8.0: blend=smoothstep(4.0,8.0,cycle)
		elif cycle>=8.0 and cycle<12.0: blend=1.0
		elif cycle>=12.0: blend=1.0-smoothstep(12.0,16.0,cycle)
		platform.position=anchor+Vector3(0,.1+blend*1.6,4+blend*1.5)
		platform_velocity=(platform.position-previous)/delta if delta>0 else Vector3.ZERO
		var trolley_x=lerpf(-1.25,1.25,blend)
		if is_instance_valid(crane_trolley): crane_trolley.position.x=trolley_x
		if is_instance_valid(crane_hook): crane_hook.position.x=trolley_x
		if is_instance_valid(crane_hook_body): crane_hook_body.position=anchor+Vector3(trolley_x,3.08,0)
		var phase=int(cycle/4)
		if phase!=_last_machine_phase and not platform_locked:
			_last_machine_phase=phase
			if phase in [0,2]: _emit("machine_docked",platform.global_position,{"moving":false})
		var warning_leg=int(platform_clock/8.0)
		if not platform_locked and fmod(platform_clock,8.0)>=3.0 and fmod(platform_clock,8.0)<4.0 and warning_leg!=_warned_machine_leg:
			_warned_machine_leg=warning_leg
			_emit("machine_warning",platform.global_position,{"moving":false,"starts_in_s":4.0-fmod(platform_clock,8.0)})
	if is_instance_valid(dock):
		var previous=dock.position
		if not dock_locked: dock_clock+=delta
		var amplitude=.015+.005*float(_cached_sample.get("wind_strength",0))
		dock.position.y=dock_base_y+sin(dock_clock*.8)*amplitude
		dock_velocity=(dock.position-previous)/delta if delta>0 else Vector3.ZERO
	var rotor_target=0.0
	if field.fan_enabled: rotor_target=14.0 if field.event_phase=="active" else (9.0 if field.event_phase=="warning" else 3.0)
	fan_visual_speed=move_toward(fan_visual_speed,rotor_target,delta*12.0)
	if is_instance_valid(fan_rotor): fan_rotor.rotate_z(delta*fan_visual_speed)

func _route_point(route: PackedVector3Array, distance_m: float) -> Dictionary:
	var length=0.0
	for i in route.size(): length+=route[i].distance_to(route[(i+1)%route.size()])
	var remaining=fposmod(distance_m,maxf(.01,length))
	for i in route.size():
		var a=route[i];var b=route[(i+1)%route.size()];var size=a.distance_to(b)
		if remaining<=size: return {"position":a.lerp(b,remaining/maxf(.01,size)),"direction":(b-a).normalized(),"corner_distance":size-remaining}
		remaining-=size
	return {"position":route[0],"direction":Vector3.FORWARD,"corner_distance":0.0}

func _update_cars(delta: float) -> void:
	for car in cars:
		var body: AnimatableBody3D=car.body
		var near=body.global_position.distance_to(focus)<90
		body.visible=near
		var result=_route_point(car.route,car.distance)
		var p: Vector3=result.position
		var yield_to_pilot=Vector2(p.x-focus.x,p.z-focus.z).length()<6 and focus.y-p.y<2.8
		var yield_to_crossing=false
		for person in pedestrians:
			if bool(person.get("crossing",false)) and p.distance_to(person.body.position)<4.5:
				yield_to_crossing=true;break
		var red_light=fmod(field.time_s,18.0)>12.0 and float(result.corner_distance)<5
		var speed=0.0 if yield_to_pilot or yield_to_crossing or red_light else float(car.speed)
		car.distance+=speed*delta
		var next=_route_point(car.route,car.distance)
		body.position=next.position+Vector3.UP*.03
		var direction: Vector3=next.direction
		body.rotation.y=lerp_angle(body.rotation.y,atan2(direction.x,direction.z),minf(1,delta*5))
		car.collider.disabled=not near

func _update_pedestrians(delta: float) -> void:
	for person in pedestrians:
		var body: Node3D=person.body
		var near=body.global_position.distance_to(focus)<65
		body.visible=near
		if bool(person.get("waiting",false)): continue
		var result=_route_point(person.route,person.distance)
		var p: Vector3=result.position
		var yield_to_pilot=Vector2(p.x-focus.x,p.z-focus.z).length()<3.5 and focus.y-p.y<3
		var wait_for_traffic=false
		if bool(person.get("crossing",false)):
			# Wait on the curb for nearby cars; once crossing, vehicles yield to people.
			var crossing_offset=absf((p-Vector3(person.crossing_center)).dot(Vector3(person.crossing_axis)))
			if crossing_offset>float(person.road_half)+.6:
				for car in cars:
					if p.distance_to(car.body.position)<11.0: wait_for_traffic=true;break
			p.y=Vector3(person.crossing_center).y+(.055 if crossing_offset<float(person.road_half)+.6 else .2)
		if not yield_to_pilot and not wait_for_traffic: person.distance+=float(person.speed)*delta
		body.position=p
		var direction: Vector3=result.direction
		body.rotation.y=lerp_angle(body.rotation.y,atan2(direction.x,direction.z),minf(1,delta*4))
		var animation: AnimationPlayer=person.animation
		if is_instance_valid(animation): animation.speed_scale=0.0 if yield_to_pilot or wait_for_traffic or not near else float(person.speed)

func _update_birds(delta: float) -> void:
	for item in birds:
		var bird: Node3D=item.body
		if not is_instance_valid(bird): continue
		var angle=field.time_s*.23+float(item.phase)
		var p=anchor+Vector3(12+cos(angle)*13,7+sin(angle*.7+float(item.phase))*1.4,sin(angle)*10)
		if p.distance_to(focus)<4: p.y+=2
		bird.position=p;bird.rotation.y=atan2(-sin(angle),cos(angle));bird.rotation.z=sin(angle)*.12
		bird.visible=p.distance_to(focus)<90
		if is_instance_valid(item.left): item.left.rotation.z=sin(field.time_s*4+float(item.phase))*.22
		if is_instance_valid(item.right): item.right.rotation.z=-sin(field.time_s*4+float(item.phase))*.22

var _flag_sample_left=0.0

func _process(_delta: float) -> void:
	if not _configured: return
	var wind: Vector3=_cached_sample.get("wind_velocity",Vector3.ZERO)
	var canopy_wind: Vector3=field.sample(Vector3(focus.x,world.terrain_height(focus)+8.0 if world.has_method("terrain_height") else 8.0,focus.z)).visual_wind_velocity
	for material in [wind_material,reed_material]:
		material.set_shader_parameter("wind_velocity",canopy_wind)
		material.set_shader_parameter("wind_time",field.time_s)
	if is_instance_valid(weather_vane): weather_vane.rotation.y=-atan2(wind.z,wind.x)
	if is_instance_valid(anemometer): anemometer.rotation.y=field.time_s*wind.length()*1.5
	_flag_sample_left-=_delta
	if world != null and _flag_sample_left<=0:
		_flag_sample_left=.1
		var flags=world.get("wind_flags")
		if flags is Array:
			for flag in flags:
				if not is_instance_valid(flag) or flag.global_position.distance_to(focus)>85: continue
				var local_wind: Vector3=field.sample(flag.global_position+Vector3.UP*2.0).wind_velocity
				flag.rotation.y=-atan2(local_wind.z,local_wind.x)
				flag.rotation.z=sin(field.time_s*2.5+flag.global_position.x)*minf(.12,local_wind.length()*.025)
	for material in water_materials:
		material.set_shader_parameter("wind_velocity",_cached_sample.get("visual_wind_velocity",wind))
		material.set_shader_parameter("weather_time",field.time_s)
		material.set_shader_parameter("rain_amount",field.rain)
		material.set_shader_parameter("downwash_position",focus)
		material.set_shader_parameter("downwash_strength",(1.0-smoothstep(.8,5.0,focus.y))*0.65)
	if is_instance_valid(rain_mesh):
		rain_mesh.position=Vector3(focus.x,5,focus.z)
		rain_mesh.visible=field.rain>.015
		rain_material.set_shader_parameter("rain_amount",field.rain)
		rain_material.set_shader_parameter("weather_time",field.time_s)
		rain_material.set_shader_parameter("wind_velocity",canopy_wind)
	if is_instance_valid(fan_flow):
		var active=field.fan_enabled and field.wind_enabled and field.wind_multiplier>0.0 and field.event_phase=="active"
		fan_flow.visible=active
		var pulse=float(field.sample(anchor+Vector3(0,1.8,8)).vent_strength)
		fan_flow_material.set_shader_parameter("airflow_strength",minf(1.0,pulse*field.wind_multiplier) if active else 0.0)
		fan_flow_material.set_shader_parameter("weather_time",field.time_s)
	interaction_hint=get_interaction_hint(focus)

func _build_rain() -> void:
	rain_material=ShaderMaterial.new();rain_material.shader=RAIN
	var mesh=QuadMesh.new();mesh.size=Vector2(.025,.6);mesh.material=rain_material
	var multi=MultiMesh.new();multi.transform_format=MultiMesh.TRANSFORM_3D;multi.use_custom_data=true;multi.mesh=mesh;multi.instance_count=256
	for i in multi.instance_count:
		multi.set_instance_transform(i,Transform3D(Basis(Vector3.UP,PI*.25),Vector3(_rain_rng.randf_range(-24,24),0,_rain_rng.randf_range(-24,24))))
		multi.set_instance_custom_data(i,Color(_rain_rng.randf(),0,0,1))
	multi.custom_aabb=AABB(Vector3(-36,-12,-36),Vector3(72,28,72))
	rain_mesh=MultiMeshInstance3D.new();rain_mesh.name="LocalWeatherRain";rain_mesh.multimesh=multi;rain_mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rain_mesh)

func _adopt_streamed_scenery() -> void:
	if world==null: return
	var chunks=world.get("chunks")
	if not chunks is Dictionary: return
	var alive: Dictionary={}
	for chunk in chunks.values():
		if not is_instance_valid(chunk): continue
		var id=chunk.get_instance_id();alive[id]=true
		if adopted_chunks.has(id): continue
		_adopt_node(chunk)
		adopted_chunks[id]=true
	for id in adopted_chunks.keys():
		if id!=-1 and not alive.has(id): adopted_chunks.erase(id)
	# Materials are shared, so retain only the region's handful of color variants.
	if not adopted_chunks.has(-1):
		for child in world.get_children():
			if child is MeshInstance3D: _adopt_node(child)
		adopted_chunks[-1]=true

func _adopt_node(node: Node) -> void:
	if node is MultiMeshInstance3D and node.multimesh != null and node.multimesh.mesh != null:
		if "street_tree" in node.multimesh.mesh.resource_path:
			node.material_override=wind_material
			node.extra_cull_margin=.6
	if node is MeshInstance3D:
		var old=node.material_override
		if old is ShaderMaterial and old.shader != null and old.shader.resource_path.ends_with("/water.gdshader"):
			var color=old.get_shader_parameter("water_color")
			var material: ShaderMaterial
			for candidate in water_materials:
				if candidate.get_shader_parameter("water_color")==color: material=candidate;break
			if material==null:
				material=ShaderMaterial.new();material.shader=WATER
				if color != null: material.set_shader_parameter("water_color",color)
				water_materials.append(material)
			node.material_override=material
	for child in node.get_children(): _adopt_node(child)

func _model(id: String, parent: Node3D, p: Vector3, yaw=0.0) -> Node3D:
	var model=_external_model(MODEL_PATH+id+".glb",parent,p)
	if model != null: model.rotation.y=yaw
	return model

func _external_model(path: String, parent: Node3D, p: Vector3) -> Node3D:
	if not ResourceLoader.exists(path): push_warning("V2.2 model missing: "+path); return null
	if not model_cache.has(path): model_cache[path]=load(path)
	var model: Node3D=model_cache[path].instantiate()
	parent.add_child(model);model.position=p
	_prepare_model(model)
	return model

func _prepare_model(node: Node) -> void:
	if node is GeometryInstance3D: node.visibility_range_end=130.0
	if node is MeshInstance3D:
		for index in node.mesh.get_surface_count():
			var arrays=node.mesh.surface_get_arrays(index);var material=node.get_active_material(index)
			if arrays[Mesh.ARRAY_COLOR] != null and not arrays[Mesh.ARRAY_COLOR].is_empty() and material is BaseMaterial3D:
				var copy=material.duplicate();copy.vertex_color_use_as_albedo=true;copy.vertex_color_is_srgb=false
				node.set_surface_override_material(index,copy)
	for child in node.get_children(): _prepare_model(child)

func _find_part(node: Node, part: String) -> Node3D:
	if node==null: return null
	if str(node.name)==part and node is Node3D: return node
	for child in node.get_children():
		var found=_find_part(child,part)
		if found != null: return found
	return null

func _find_animation(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer: return node
	for child in node.get_children():
		var found=_find_animation(child)
		if found != null: return found
	return null

func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D: return node
	for child in node.get_children():
		var result=_find_mesh(child)
		if result != null: return result
	return null

func _apply_material(node: Node, material: Material) -> void:
	if node==null: return
	if node is GeometryInstance3D: node.material_override=material;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children(): _apply_material(child,material)

func _add_collider(parent: Node3D, p: Vector3, size: Vector3) -> StaticBody3D:
	var body=StaticBody3D.new();body.collision_layer=1;body.collision_mask=2|8
	parent.add_child(body);body.position=p
	var shape=CollisionShape3D.new();var box=BoxShape3D.new();box.size=size;shape.shape=box;body.add_child(shape)
	return body

func _add_shore_surface(node: Node) -> void:
	if node==null: return
	if node is MeshInstance3D:
		var body=StaticBody3D.new();body.collision_layer=1;body.collision_mask=2|8
		node.add_child(body)
		var shape=CollisionShape3D.new();var triangle_shape: ConcavePolygonShape3D=node.mesh.create_trimesh_shape();triangle_shape.backface_collision=true
		shape.shape=triangle_shape;body.add_child(shape)
		var faces: PackedVector3Array=node.mesh.get_faces()
		for i in faces.size(): faces[i]=node.global_transform*faces[i]
		shore_surfaces.append({"bounds":node.global_transform*node.get_aabb(),"faces":faces})
	for child in node.get_children():
		if not child is StaticBody3D: _add_shore_surface(child)

func _beacon(parent: Node3D, p: Vector3, color: Color, radius: float) -> MeshInstance3D:
	var node=MeshInstance3D.new();var sphere=SphereMesh.new();sphere.radius=radius;sphere.height=radius*2;sphere.radial_segments=8;sphere.rings=4;node.mesh=sphere
	var material=StandardMaterial3D.new();material.albedo_color=color;material.emission_enabled=true;material.emission=color;node.material_override=material
	parent.add_child(node);node.position=p;return node

func _refresh_label() -> void:
	if not is_instance_valid(control_label): return
	var heading={"R1":"气象与交通观测","R2":"风机检修通道","R3":"海滨浮码头","R4":"港口升降卸货台"}.get(region_id,"环境观测")
	var status="风 %.1f m/s"%float(_cached_sample.get("wind_strength",0))
	if region_id=="R2": status="风机待机 · F 关闭" if field.fan_enabled else "风机关闭 · 通道平稳"
	if region_id=="R3": status="已固定 · 可降落" if dock_locked else "随水起伏 · F 固定"
	if region_id=="R4":
		var cycle=fmod(platform_clock,8.0)
		status="已锁定 · 可降落" if platform_locked else ("即将移动 · F 锁定" if cycle>=3 and cycle<4 else ("升降台移动中 · F 锁定" if cycle>=4 else "停靠窗口 · F 锁定后降落"))
	control_label.text=heading+"\n"+status
	if region_id!="R1" and field.event_phase in ["warning","active"] and field.event_enabled():
		control_label.text+="\n"+("环境预警 " if field.event_phase=="warning" else "短时变化 ")+str(ceili(field.event_remaining))+"秒 · "+str(field.event_definition().label)
	var event_color=Color("7ed8a1")
	if field.event_enabled() and field.event_phase=="warning": event_color=Color("e3ae55") if fmod(field.time_s,1.0)<.65 else Color("655b39")
	elif field.event_enabled() and field.event_phase=="active": event_color=Color("e8734d")
	for beacon in encounter_beacons:
		beacon.material_override.albedo_color=event_color;beacon.material_override.emission=event_color
	if is_instance_valid(interference_label):
		interference_label.text="分流塔 · 信号正常\n附近可能出现短时电磁变化"
		if field.event_enabled() and field.event_phase in ["warning","active"]:
			interference_label.text="电磁变化"+("预警" if field.event_phase=="warning" else "持续中")+" · "+str(ceili(field.event_remaining))+"秒\n离开环线后信号恢复"
		interference_beacon.material_override.albedo_color=event_color
		interference_beacon.material_override.emission=event_color
		interference_ring.material_override.albedo_color=event_color.darkened(.1)
	if is_instance_valid(status_beacon):
		var material: StandardMaterial3D=status_beacon.material_override
		var machine_active=region_id=="R4" and not platform_locked and fmod(platform_clock,8.0)>=3
		var color=Color("e3ae55") if machine_active else (event_color if region_id!="R1" else Color("7ed8a1"))
		material.albedo_color=color;material.emission=color

func _emit(kind: String, p: Vector3, extra: Dictionary = {}) -> void:
	var event={"kind":kind,"position":p,"region_id":region_id,"time_s":field.time_s}
	event.merge(extra,true);environment_event.emit(event)
