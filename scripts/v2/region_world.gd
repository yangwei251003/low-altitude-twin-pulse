class_name RegionWorldV2
extends Node3D

signal discovered(poi: Dictionary)
signal secret_prepared(id: String, step: int)
signal visibility_occluder_added(root: Node3D)
signal scenery_used

const V = preload("res://scripts/visuals.gd")
const Layout = preload("res://scripts/v2/region_layout.gd")
const Builder = preload("res://scripts/v2/worldui_builder.gd")
var layout: Dictionary = {}
var rotating_turbines: Array[Node3D] = []
var maintenance_target = Vector3.ZERO
var maintenance_active = false
var maintenance_safe = false
var route_lamps: Array[Node3D] = []
var facility_lights: Array[Light3D] = []
const Streets = preload("res://scripts/v2/street_dressing.gd")
const FLIGHT_BOUNDS = Rect2(-16,-16,632,532)
var visibility_occluders: Array[Node3D] = []
var district_panels: Array[Node3D] = []
var scenery_hint = ""
var scenery_cooldown = 0.0
var scenery_held = false
const PALETTES = {
	"R1": [Color("8aaf9a"), Color("d8e2da"), Color("287e80"), Color("b7c9cb")],
	"R2": [Color("6a9779"), Color("c9d4d0"), Color("a0b649"), Color("7f929b")],
	"R3": [Color("8eb9b3"), Color("e4e8df"), Color("d28364"), Color("9aafa7")],
	"R4": [Color("8b9994"), Color("d0d6d4"), Color("d0af49"), Color("708b93")]
}
var region: Dictionary
var night = false
var chunks: Dictionary = {}
var poi_nodes: Dictionary = {}
var known: Array = []
var restored: Dictionary = {}
var pinned: Array[Vector2i] = []
var obstacles: Array[Dictionary] = []
var poi_index: Dictionary = {}
var low_quality = true
var last_cell = Vector2i(-99, -99)
var last_scan = 0.0
var secret_steps: Dictionary = {}
var secret_dwell = 0.0
var secret_hint = ""
var completed_missions: Array = []
var completed_stages: Array = []
var active_job_id = ""
static var asset_bounds: Dictionary = {}
var protected_positions: Array[Vector2] = []
var wind_flags: Array[Node3D] = []
var wind_time = 0.0
var wind_enabled = true
var current_wind = Vector3.ZERO
var wind_strength_mps2 = 0.0
var wind_phase = 0.0
var pending_chunks: Array[Vector2i] = []
var retained_chunks: Array[Vector2i] = []
var chunk_load_ms: Array[float] = []
var living: Node3D

func wind_acceleration(point: Vector3, seconds: float, altitude_agl = 3.0) -> Vector3:
	if not wind_enabled: return Vector3.ZERO
	var gust = 0.72+0.28*sin(seconds*0.42+point.z*0.008+wind_phase)
	var bearing = wind_phase+sin(seconds*0.16+point.x*0.01)*0.30
	return Vector3(cos(bearing),0,sin(bearing))*wind_strength_mps2*gust*clampf((altitude_agl-0.6)/2.0,0,1)

func _process(delta: float) -> void:
	wind_time += delta
	# V2.2 owns the shared-field wind flags. Avoid sampling every flag twice.
	if is_instance_valid(living): return
	for flag in wind_flags:
		if is_instance_valid(flag):
			var wind: Vector3 = living.sample(flag.global_position).get("wind_velocity",Vector3.ZERO) if is_instance_valid(living) else wind_acceleration(flag.global_position,wind_time)
			flag.rotation.y = -atan2(wind.z,wind.x)
			flag.rotation.z = sin(wind_time*3.0+flag.global_position.x)*0.06*clampf(wind.length(),0.0,1.0)

func configure(value: Dictionary, is_night: bool, saved_world: Dictionary) -> void:
	region = value
	layout = Layout.get_layout(str(region.id))
	night = is_night
	# Content returns a defensive deep copy; never request it in per-frame wind sampling.
	wind_strength_mps2 = float(CatalogV2.content().catalog.wind_strength_mps2.get(str(region.id),0.0))
	wind_phase = float(str(region.id).hash()%1000)*0.017
	known = saved_world.get("discovered_pois", []).duplicate()
	restored = saved_world.get("restored_objects", {}).duplicate(true)
	secret_steps = saved_world.get("secret_steps", {}).duplicate(true)
	for poi in region.pois: poi_index[poi.id] = poi
	protected_positions = protected_points(region)
	obstacles = obstacle_layout(region)

static func obstacle_layout(value: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in Layout.get_layout(str(value.id)).get("structures",[]):result.append(item.duplicate(true))
	return result

static func protected_points(value: Dictionary) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var pois = {}
	for poi in value.pois:
		var p = Vector2(poi.position_xz_m[0],poi.position_xz_m[1])
		result.append(p); pois[poi.id] = p
	var source = CatalogV2.content()
	for job in source.missions+source.airframe_challenges+source.mode_configs:
		if job.region_id != value.id: continue
		for stage in job.get("stages",[job]):
			for action in stage.get("actions",[])+stage.get("optional_actions",[]):
				var offset: Array = action.get("offset_xz_m",[0,0])
				if pois.has(action.get("poi_id","")): result.append(pois[action.poi_id]+Vector2(offset[0],offset[1]))
	return result

func _ready() -> void:
	var water = V.box(self,Vector3(300,-.65,250),Vector3(880,.1,780),Color("427e88"))
	var water_mat = ShaderMaterial.new()
	water_mat.shader=preload("res://assets/v2/water.gdshader")
	water_mat.set_shader_parameter("water_color",(Color("234a59") if night else Color("367b83")).srgb_to_linear())
	water.material_override=water_mat;water.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Builder.terrain(self,layout)
	_build_perimeter()
	_build_navigation_lamps()
	update_stream(poi_position(str(region.spawn_poi)),true)

func _register_occluder(node: Node3D) -> void:
	visibility_occluders.append(node)
	visibility_occluder_added.emit(node)

func decoration_clear(point: Vector3, radius: float) -> bool:
	if point.x < -10 or point.x > 610 or point.z < -10 or point.z > 510: return false
	if terrain_height(point)<-.6:return false
	for protected in protected_positions:
		if Vector2(point.x,point.z).distance_to(protected) < radius+4.3: return false
	for obstacle in obstacles:
		if absf(point.x-obstacle.x)<obstacle.w/2+radius and absf(point.z-obstacle.z)<obstacle.l/2+radius: return false
	return true

func _build_perimeter() -> void:
	var edge=Node3D.new();edge.name="FlightBoundary";add_child(edge)
	for wall in [Vector4(-16.5,250,1,534),Vector4(616.5,250,1,534),Vector4(300,-16.5,634,1),Vector4(300,516.5,634,1)]:
		V.collider(edge,Vector3(wall.x,19,wall.y),Vector3(wall.z,40,wall.w)).name="OuterFlightBoundary"
	for x in range(-16,617,60):
		for z in [-16,516]:_boundary_post(edge,Vector3(x,maxf(-.5,terrain_height(Vector3(x,0,z))),z))
	for z in range(44,517,60):
		for x in [-16,616]:_boundary_post(edge,Vector3(x,maxf(-.5,terrain_height(Vector3(x,0,z))),z))

func _boundary_post(parent: Node3D, pos: Vector3) -> void:
	V.cylinder(parent,pos+Vector3.UP*1.2,0.13,2.4,Color("3b5962"))
	V.sphere(parent,pos+Vector3.UP*2.5,0.17,Color("e5be72"))
	if (int(pos.x)+int(pos.z))%60==0:
		var label = Label3D.new()
		label.text = "航区边界"
		label.font = load("res://assets/fonts/NotoSansSC-Medium.ttf")
		label.font_size = 28; label.pixel_size = 0.025
		label.position = pos+Vector3.UP*3.5
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.visibility_range_end = 40
		parent.add_child(label)

func work_scenery(pilot: FlightBodyV2, delta: float) -> void:
	scenery_cooldown = maxf(0.0,scenery_cooldown-delta)
	var held = bool(pilot.command.get("interact",false))
	var pressed = held and not scenery_held
	scenery_held = held
	scenery_hint = ""
	var p = pilot.global_position
	var edge_distance = minf(minf(p.x+16,616-p.x),minf(p.z+16,516-p.z))
	if edge_distance < 10: scenery_hint = "接近航区边界 · 沿海堤转向"
	for station in district_panels:
		if not is_instance_valid(station): continue
		if station.global_position.distance_to(p)>4.5: continue
		var enabled = bool(station.get_meta("guide_on",false))
		scenery_hint = "[F] " + ("关闭" if enabled else "开启") + "街区起降引导灯 · "+str(station.get_meta("district",""))
		if pressed and scenery_cooldown<=0 and pilot.linear_velocity.length()<2.5:
			station.set_meta("guide_on",not enabled)
			for route_lamp in route_lamps:
				if is_instance_valid(route_lamp):route_lamp.material_override=V.material(Color("96cfb4") if not enabled else Color("756e58"),1.3 if not enabled else .12)
			var ring: MeshInstance3D = station.get_node("GuideLight")
			ring.material_override = V.material(Color("59e3bd") if not enabled else Color("698682"),1.2 if not enabled else 0.0)
			scenery_cooldown = 0.5
			scenery_used.emit()
		break

func poi_position(id: String) -> Vector3:
	var data = poi_index.get(id, {})
	if data.is_empty(): return Vector3(50, 0, 55)
	var position_m = Vector3(float(data.position_xz_m[0]), 0, float(data.position_xz_m[1]))
	position_m.y = surface_height(position_m)
	return position_m

func surface_at(point: Vector3) -> Dictionary:
	var result=Layout.surface(layout,point)
	if is_instance_valid(living) and living.has_method("get_surface_at"):
		var moving: Dictionary=living.get_surface_at(point)
		if bool(moving.get("valid",false)) and float(moving.height)<=point.y+.2 and float(moving.height)>float(result.height):return moving
	return result

func surface_height(point: Vector3) -> float:
	var high=Vector3(point.x,40,point.z)
	var result=surface_at(high)
	return maxf(float(result.height),float(layout.get("water_level",-.6)))

func terrain_height(point: Vector3) -> float:
	return Layout.terrain(layout,point)

func water_at(point: Vector3) -> Dictionary:
	var result=Layout.water_at(layout,point)
	if is_instance_valid(living):
		var deck: Dictionary=living.get_surface_at(point)
		if bool(deck.get("valid",false)) and not bool(deck.get("water",false)) and float(deck.height)<=point.y+.2:result.over_water=false
	return result

func pin_pois(ids: Array) -> void:
	pinned.clear()
	for id in ids:
		var p = poi_position(str(id))
		var cell = Vector2i(floori(p.x / 100), floori(p.z / 100))
		if not pinned.has(cell): pinned.append(cell)
	last_cell = Vector2i(-99, -99)

func update_stream(player: Vector3, force = false) -> void:
	var cell = Vector2i(floori(player.x / 100), floori(player.z / 100))
	var changed = force or cell != last_cell or not pending_chunks.is_empty()
	if force or cell != last_cell:
		last_cell = cell
		retained_chunks.clear()
		pending_chunks.clear()
		# The 70 m maximum camera span fits inside the 100 m neighboring ring.
		# Keep a 3x3 neighborhood plus mission targets; the overview uses its proxy.
		for x in range(maxi(0, cell.x - 1), mini(6, cell.x + 2)):
			for z in range(maxi(0, cell.y - 1), mini(5, cell.y + 2)): retained_chunks.append(Vector2i(x,z))
		for p in pinned:
			if not retained_chunks.has(p): retained_chunks.append(p)
		for p in retained_chunks:
			if chunks.has(p): continue
			# Nearby collision and mission chunks are immediate; the outer 100 m buffer is staggered.
			if force or pinned.has(p) or p==cell: _load_chunk(p)
			else: pending_chunks.append(p)
		pending_chunks.sort_custom(func(a,b): return a.distance_squared_to(cell)<b.distance_squared_to(cell))
	if not pending_chunks.is_empty(): _load_chunk(pending_chunks.pop_front())
	var retired = false
	for p in chunks.keys():
		if p not in retained_chunks and (force or not retired):
			chunks[p].queue_free()
			chunks.erase(p)
			retired = true
	if not changed and not retired:return
	visibility_occluders = visibility_occluders.filter(func(item): return is_instance_valid(item) and not item.is_queued_for_deletion())
	district_panels = district_panels.filter(func(item): return is_instance_valid(item) and not item.is_queued_for_deletion())
	wind_flags = wind_flags.filter(func(flag): return is_instance_valid(flag) and not flag.is_queued_for_deletion())
	for id in poi_nodes.keys():
		if not is_instance_valid(poi_nodes[id]): poi_nodes.erase(id)

func scan_nearby(player: Vector3, delta: float, sensor_range = 15.0) -> void:
	last_scan += delta
	if last_scan < 0.5: return
	last_scan = 0.0
	for poi in region.pois:
		if poi.id in known: continue
		if poi.hidden: continue
		var range_m = sensor_range
		if poi_position(poi.id).distance_to(player) <= range_m:
			known.append(poi.id)
			discovered.emit(poi)

func work_secrets(pilot: FlightBodyV2, delta: float) -> void:
	secret_hint = ""
	var near = false
	for poi in region.pois:
		if not poi.hidden or poi.id in known: continue
		var pos = poi_position(poi.id)
		if pos.distance_to(pilot.global_position)>14: continue
		near = true
		secret_hint = str(poi.night if night else poi.day)
		var required = str(poi.get("discovery_requires_mission",""))
		if not required.is_empty() and required not in completed_missions:
			# Tool grants occur on accepting the brief, before mission completion.
			if not (required in ["M05","M06"] and (pilot.build.slots.tool == "clearance_base" or pilot.build.slots.utility == "searchlight_base")): break
		if bool(poi.get("discovery_night_only",false)) and not night: break
		var steps: Array = poi.get("discovery_steps",[])
		if steps.is_empty(): break
		var index = mini(int(secret_steps.get(poi.id,0)),steps.size()-1)
		var step: Dictionary = steps[index]
		var offset: Array = step.get("offset_xz_m",[0,0])
		var seat = pos + Vector3(offset[0],0,offset[1])
		var needed = str(step.tool_id)
		var tool_ok = needed == "interact" or needed in [pilot.build.slots.tool,pilot.build.slots.utility] or (needed == "hook_base" and pilot.build.slots.tool == "cargo_winch")
		var distance_m = Vector2(pilot.global_position.x-seat.x,pilot.global_position.z-seat.z).length()
		var valid = tool_ok and distance_m < float(step.radius_m) and pilot.linear_velocity.length()<float(step.max_speed_mps) and bool(pilot.command.get("interact",false))
		if step.has("bearing_deg"):
			var bearing = rad_to_deg(atan2(pilot.global_position.x-pos.x,pilot.global_position.z-pos.z))
			valid = valid and absf(wrapf(bearing-float(step.bearing_deg),-180,180))<25
		secret_hint += "  [%d/%d]" % [index+1,steps.size()]
		if not tool_ok: secret_hint += " · 工具未就绪"
		if valid: secret_dwell += delta
		else: secret_dwell = 0
		if secret_dwell >= float(step.duration_s):
			secret_dwell = 0
			secret_steps[poi.id] = index+1
			secret_prepared.emit(poi.id,index+1)
			if index+1>=steps.size(): known.append(poi.id); discovered.emit(poi)
		break
	if not near: secret_dwell = 0

func restore_object(id: String) -> void:
	restored[id]=true
	if poi_nodes.has(id) and is_instance_valid(poi_nodes[id]):
		var indicator=poi_nodes[id].get_node_or_null("FacilityStatus")
		if indicator:indicator.material_override=V.material(Color("7bc9ad"),.5)
	_sync_facility_recovery()

func _build_navigation_lamps() -> void:
	for road in layout.get("roads",[]):
		for i in range(road.points.size()-1):
			var aa=road.points[i];var bb=road.points[i+1]
			var a=Vector3(aa[0],aa[2],aa[1]);var b=Vector3(bb[0],bb[2],bb[1])
			var side=Vector3(-(b-a).z,0,(b-a).x).normalized()*(float(road.width)*.5+(-.25 if bool(road.get("bridge",false)) else 1.0))
			var count=maxi(1,ceili(a.distance_to(b)/18.0))
			for j in range(count):
				var point=a.lerp(b,float(j)/count)+side
				point.y=a.lerp(b,float(j)/count).y+.12 if bool(road.get("bridge",false)) else surface_height(point)
				if terrain_height(point)<-.6 and not bool(road.get("bridge",false)):continue
				V.cylinder(self,point+Vector3.UP*.6,.10,1.2,Color("4b6263"))
				var lamp=V.box(self,point+Vector3.UP*1.25,Vector3(.28,.22,.28),Color("b9a065"))
				lamp.material_override=V.material(Color("b9a065"),.5);route_lamps.append(lamp)
				if night and j%3==0:
					var pool=OmniLight3D.new();add_child(pool);pool.position=point+Vector3.UP*2.3
					pool.omni_range=10;pool.light_color=Color("9dceb6");pool.light_energy=.18;pool.shadow_enabled=false
					facility_lights.append(pool)
			if bool(road.get("bridge",false)):
				for sign_m in [-1,1]:
					var strip=Builder.segment(self,a+side*sign_m+Vector3.UP*.05,b+side*sign_m+Vector3.UP*.05,.12,.08,Color("bd9c55"),false)
					route_lamps.append(strip.get_child(0))
	_sync_facility_recovery()

func _sync_facility_recovery() -> void:
	var recovered=false
	for id in layout.get("restoration_pois",[]):
		if bool(restored.get(id,false)):recovered=true
	for lamp in route_lamps:
		if is_instance_valid(lamp):lamp.material_override=V.material(Color("96cfb4") if recovered else Color("b9a065"),1.3 if recovered else .5)
	for pool in facility_lights:
		if is_instance_valid(pool):pool.light_energy=.65 if recovered else .18
	set_meta("facility_recovered",recovered)

func set_maintenance_window(target: Vector3, active: bool, safe: bool) -> void:
	maintenance_target=target
	maintenance_active=active
	maintenance_safe=safe

func _physics_process(delta: float) -> void:
	for rotor in rotating_turbines:
		if not is_instance_valid(rotor):continue
		var within_service = maintenance_active and Vector2(rotor.global_position.x-maintenance_target.x,rotor.global_position.z-maintenance_target.z).length()<45.0
		if not (within_service and maintenance_safe):rotor.rotation.z+=delta*.24
		rotor.set_meta("maintenance_locked",within_service and maintenance_safe)

func _load_chunk(cell: Vector2i) -> void:
	if chunks.has(cell):return
	var began=Time.get_ticks_usec()
	var node=Node3D.new();node.name="Chunk_%d_%d" % [cell.x,cell.y];add_child(node);chunks[cell]=node
	for item in obstacles:
		if floori(item.x/100)!=cell.x or floori(item.z/100)!=cell.y:continue
		var building=Builder.structure(node,item)
		_register_occluder(building)
		var rotor=building.find_child("Rotor",true,false)
		if rotor:rotating_turbines.append(rotor)
	for item in layout.get("decorations",[]):
		if floori(item.x/100)==cell.x and floori(item.z/100)==cell.y:Builder.decoration(node,item)
	for poi in region.pois:
		var pos=poi_position(poi.id)
		if floori(pos.x/100)==cell.x and floori(pos.z/100)==cell.y:_build_poi(node,poi,pos,PALETTES[region.id])
	rotating_turbines=rotating_turbines.filter(func(rotor):return is_instance_valid(rotor) and not rotor.is_queued_for_deletion())
	chunk_load_ms.append((Time.get_ticks_usec()-began)/1000.0)
	if chunk_load_ms.size()>2048:chunk_load_ms.pop_front()









func _set_lod(node: Node, distance: float) -> void:
	if node is GeometryInstance3D: node.visibility_range_end = distance
	for child in node.get_children(): _set_lod(child, distance)

func _build_poi(parent: Node3D, poi: Dictionary, pos: Vector3, _palette: Array) -> void:
	var node=Node3D.new();node.name=str(poi.id).replace("-","_");parent.add_child(node);node.position=pos;poi_nodes[poi.id]=node
	Builder.poi(node,poi,str(region.id),bool(restored.get(poi.id,false)),night,str(surface_at(pos+Vector3.UP).material)=="bridge")
	if str(poi.id)==str(region.spawn_poi):
		var station=Node3D.new();node.add_child(station);station.position=Vector3(-7,0,0)
		station.set_meta("district",str(poi.name));station.set_meta("guide_on",false)
		V.box(station,Vector3(0,.9,0),Vector3(.6,1.8,.4),Color("4d6f70"))
		var indicator=V.box(station,Vector3(0,1.6,.23),Vector3(.42,.3,.06),Color("698682"));indicator.name="GuideLight"
		district_panels.append(station)

func nearest_service(player: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var distance_m = 12.0
	for poi in region.pois:
		if not poi.has("service_function"): continue
		if not service_unlocked(str(poi.id)): continue
		var d = poi_position(poi.id).distance_to(player)
		if d < distance_m: distance_m = d; best = poi
	return best

func service_unlocked(id: String) -> bool:
	var rule: Dictionary = CatalogV2.content().catalog.service_unlocks.get(id,{})
	if rule.has("stage") and rule.stage not in completed_stages: return false
	if rule.has("mission") and rule.mission not in completed_missions: return false
	if rule.has("mission_or_active") and rule.mission_or_active not in completed_missions and active_job_id != rule.mission_or_active: return false
	return true




