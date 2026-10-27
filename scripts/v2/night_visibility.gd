class_name NightVisibilityV22
extends Node3D
## Shared world-space visibility envelope for graphics, minimap and overview.
## Real lights shade the visible geometry; the veil prevents camera zoom cheating.

const VEIL_SHADER = preload("res://assets/shaders/v22/night_visibility.gdshader")
const MAX_POOLS = 6
const BEAM_RANGE = 20.0
const BEAM_ANGLE = 38.0
const BEAM_INNER_ANGLE = 29.0
const SELF_RADIUS = 4.5
const LOCAL_INNER = 24.0
const LOCAL_OUTER = 30.0
const VISIBLE_THRESHOLD = 0.06
const STREET_RANGE = 8.5
const WARM = Color("ffd09a")
const COOL = Color("b6dfff")

var camera: Camera3D
var world: Node3D
var pilot: Node3D
var living: Node3D
var night = false
var overview = false
var pilot_position = Vector3.ZERO
var heading = 0.0
var beam_origin = Vector3.ZERO
var beam_direction = Vector3(0,-.37,-.93)
var active_pools: Array[Dictionary] = []
var headlamp: SpotLight3D
var navigation_fill: OmniLight3D
var pool_lights: Array[OmniLight3D] = []
var veil: MeshInstance3D
var veil_material: ShaderMaterial
var reflector_root: Node3D
var shore_posts: Array[Node3D] = []
var port_posts: Array[Node3D] = []
var _legacy_lights: Array[Dictionary] = []
var _scanned_chunks: Dictionary = {}
var _last_light_refresh_ms = -1000
var _configured = false
var _pilot_searchlight_ref: WeakRef
var _pilot_searchlight_visible = false
var _silhouette_material: Material
var _silhouette_priority = 20
var combat_flashes: Array[Dictionary] = []

func reveal_flash(point: Vector3) -> void:
	if not night or not is_instance_valid(world) or not point.is_finite():return
	if point.distance_to(pilot_position)>LOCAL_OUTER:return
	var ray=PhysicsRayQueryParameters3D.create(pilot_position,point,1)
	if not world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():return
	# Tiny source reveal cannot expose a whole enemy group or a distant map cell.
	combat_flashes.append({"position":point,"remaining":.28,"radius":1.4})
	while combat_flashes.size()>3:combat_flashes.pop_front()
	_sync_shader()

func _process(delta: float) -> void:
	if combat_flashes.is_empty():return
	for i in range(combat_flashes.size()-1,-1,-1):
		combat_flashes[i].remaining-=delta
		if float(combat_flashes[i].remaining)<=0:combat_flashes.remove_at(i)
	if _configured and night:_sync_shader()

func configure(value_camera: Camera3D, value_world: Node3D, value_pilot: Node3D, value_living: Node3D = null) -> void:
	if _configured: return
	camera=value_camera;world=value_world;pilot=value_pilot;living=value_living
	name="NightVisibilityV22"
	_build_lights()
	_build_veil()
	_build_reflectors()
	_configured=true
	if is_instance_valid(pilot):
		pilot_position=pilot.global_position
		var value=pilot.get("heading")
		heading=float(value) if value!=null else 0.0
	set_night(bool(world.get("night")) if is_instance_valid(world) else false)

func set_night(value: bool) -> void:
	night=value
	if not _configured: return
	if is_instance_valid(veil): veil.visible=night
	headlamp.visible=night;navigation_fill.visible=night;reflector_root.visible=night
	if night:
		_last_light_refresh_ms=-1000
		update_state(pilot_position,heading,overview)
	else:
		combat_flashes.clear()
		for light in pool_lights: light.visible=false
		active_pools.clear()
		_restore_legacy_lights()
		_restore_pilot_overrides()

func update_state(position_m: Vector3, heading_radians: float, is_overview: bool = false) -> void:
	if not _configured or not position_m.is_finite() or not is_finite(heading_radians): return
	pilot_position=position_m;heading=heading_radians;overview=is_overview
	if not night: return
	_sync_pilot_overrides()
	var forward=Vector3(-sin(heading),0,-cos(heading))
	beam_origin=pilot_position+Vector3.UP*.18+forward*.32
	beam_direction=(forward+Vector3.DOWN*.40).normalized()
	headlamp.global_position=beam_origin
	headlamp.look_at(beam_origin+beam_direction,Vector3.UP)
	navigation_fill.global_position=pilot_position+Vector3.UP*.1
	if Time.get_ticks_msec()-_last_light_refresh_ms>=250:
		_last_light_refresh_ms=Time.get_ticks_msec()
		_refresh_local_pools()
		_suppress_legacy_lights()
		_position_shore_posts()
	_sync_shader()

func point_visible(world_position: Vector3) -> bool:
	return not night or visibility_strength(world_position)>=VISIBLE_THRESHOLD

func visibility_strength(point: Vector3) -> float:
	if not night: return 1.0
	if not point.is_finite(): return 0.0
	var near_light=1.0-smoothstep(SELF_RADIUS*.65,SELF_RADIUS,point.distance_to(pilot_position))
	var offset=point-beam_origin
	var distance_m=offset.length()
	var facing=offset.dot(beam_direction)/maxf(distance_m,.0001)
	var beam=smoothstep(cos(deg_to_rad(BEAM_ANGLE)),cos(deg_to_rad(BEAM_INNER_ANGLE)),facing)
	beam*=1.0-smoothstep(BEAM_RANGE*.68,BEAM_RANGE,distance_m)
	var strength=maxf(near_light,beam)
	for pool in active_pools:
		var radius=float(pool.radius)
		var local=1.0-smoothstep(radius*.65,radius,point.distance_to(pool.position))
		strength=maxf(strength,local*float(pool.gain))
	for flash in combat_flashes:
		var radius=float(flash.radius)
		strength=maxf(strength,(1.0-smoothstep(radius*.4,radius,point.distance_to(flash.position)))*clampf(float(flash.remaining)/.10,0,1))
	var distance_xz=Vector2(point.x-pilot_position.x,point.z-pilot_position.z).length()
	return clampf(strength*(1.0-smoothstep(LOCAL_INNER,LOCAL_OUTER,distance_xz)),0,1)

func visibility_snapshot() -> Dictionary:
	return {"night":night,"overview":overview,"pilot_position":pilot_position,"beam_origin":beam_origin,"beam_direction":beam_direction,"beam_range":BEAM_RANGE,"beam_angle":BEAM_ANGLE,"self_radius":SELF_RADIUS,"maximum_radius":LOCAL_OUTER,"pool_count":active_pools.size(),"pools":active_pools.duplicate(true),"marker_threshold":VISIBLE_THRESHOLD}

func _build_lights() -> void:
	headlamp=SpotLight3D.new();headlamp.name="DroneColdHeadlamp"
	headlamp.spot_range=BEAM_RANGE;headlamp.spot_angle=BEAM_ANGLE
	headlamp.spot_attenuation=.85;headlamp.spot_angle_attenuation=.7
	headlamp.light_color=COOL;headlamp.light_energy=3.0
	headlamp.shadow_enabled=true;headlamp.shadow_bias=.035;headlamp.shadow_normal_bias=.6
	headlamp.light_specular=.35;add_child(headlamp)
	navigation_fill=OmniLight3D.new();navigation_fill.name="DroneNavigationFill"
	navigation_fill.omni_range=SELF_RADIUS;navigation_fill.omni_attenuation=.9
	navigation_fill.light_energy=.8;navigation_fill.light_color=Color("8bbbd6")
	navigation_fill.shadow_enabled=false;navigation_fill.light_specular=.2;add_child(navigation_fill)
	for i in MAX_POOLS:
		var light=OmniLight3D.new();light.name="LocalStreetPool_%d"%i
		light.omni_range=STREET_RANGE;light.omni_attenuation=.8
		light.light_color=WARM;light.light_energy=2.1;light.light_specular=.4
		light.shadow_enabled=false;light.visible=false;add_child(light);pool_lights.append(light)

func _build_veil() -> void:
	veil_material=ShaderMaterial.new();veil_material.shader=VEIL_SHADER
	# The pilot's emergency occlusion silhouette alone draws over the veil.
	veil_material.render_priority=126
	veil_material.set_shader_parameter("beam_range",BEAM_RANGE)
	veil_material.set_shader_parameter("beam_cos_outer",cos(deg_to_rad(BEAM_ANGLE)))
	veil_material.set_shader_parameter("beam_cos_inner",cos(deg_to_rad(BEAM_INNER_ANGLE)))
	veil_material.set_shader_parameter("self_radius",SELF_RADIUS)
	veil_material.set_shader_parameter("local_inner",LOCAL_INNER)
	veil_material.set_shader_parameter("local_outer",LOCAL_OUTER)
	veil=MeshInstance3D.new();veil.name="NightWorldVisibilityVeil"
	var quad=QuadMesh.new();quad.size=Vector2(2,2);quad.flip_faces=true
	veil.mesh=quad;veil.material_override=veil_material;veil.extra_cull_margin=16384
	veil.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	camera.add_child(veil);veil.position=Vector3(0,0,-1)

func _candidate(candidates: Array[Dictionary], id: String, position_m: Vector3, radius: float, color: Color, energy: float) -> void:
	var distance_m=position_m.distance_to(pilot_position)
	if distance_m>28.0: return
	candidates.append({"id":id,"position":position_m,"radius":radius,"color":color,"energy":energy,"distance":distance_m,"gain":1.0-smoothstep(21.0,28.0,distance_m)})

func _refresh_local_pools() -> void:
	var candidates: Array[Dictionary]=[]
	if is_instance_valid(world):
		var lamps=world.get("route_lamps")
		if lamps is Array:
			for i in lamps.size():
				if is_instance_valid(lamps[i]):_candidate(candidates,"route_"+str(i),lamps[i].global_position+Vector3.UP*.6,STREET_RANGE,WARM,1.2)
	# POI street lamps reuse their existing mesh; suppress the old unlimited pool.
	if is_instance_valid(world):
		var region=world.get("region")
		if region is Dictionary:
			for poi in region.get("pois",[]):
				if bool(poi.get("hidden",false)): continue
				var p=Vector3(float(poi.position_xz_m[0]),0,float(poi.position_xz_m[1]))
				if p.distance_to(pilot_position)>37 or not _chunk_loaded(Vector2i(floori(p.x/100),floori(p.z/100))): continue
				if world.has_method("surface_height"): p.y=float(world.surface_height(p))
				_candidate(candidates,str(poi.id)+"_lamp",p+Vector3(4.4,2.8,2),STREET_RANGE,WARM,1.2)
			if str(region.get("id",""))=="R4":
				for i in port_posts.size(): _candidate(candidates,"port_beacon_%d"%i,port_posts[i].global_position+Vector3.UP*1.25,3.4,Color("ffb85e"),1.35)
	candidates.sort_custom(func(a: Dictionary,b: Dictionary): return float(a.distance)<float(b.distance))
	active_pools.clear()
	for i in MAX_POOLS:
		var light=pool_lights[i]
		if i>=candidates.size(): light.visible=false;continue
		var pool=candidates[i]
		active_pools.append(pool)
		light.global_position=pool.position;light.omni_range=pool.radius
		light.light_color=pool.color;light.light_energy=float(pool.energy)*float(pool.gain)
		light.visible=night and float(pool.gain)>.001

func _chunk_loaded(cell: Vector2i) -> bool:
	if not is_instance_valid(world): return false
	var chunks=world.get("chunks")
	return chunks is Dictionary and chunks.has(cell) and is_instance_valid(chunks[cell])

func _sync_shader() -> void:
	veil_material.set_shader_parameter("pilot_position",pilot_position)
	veil_material.set_shader_parameter("beam_origin",beam_origin)
	veil_material.set_shader_parameter("beam_direction",beam_direction)
	var positions=PackedVector4Array();var gains=PackedFloat32Array()
	for i in MAX_POOLS:
		if i<active_pools.size():
			var pool=active_pools[i];var p: Vector3=pool.position
			positions.append(Vector4(p.x,p.y,p.z,float(pool.radius)));gains.append(float(pool.gain))
		else: positions.append(Vector4.ZERO);gains.append(0.0)
	veil_material.set_shader_parameter("light_pools",positions)
	veil_material.set_shader_parameter("pool_gains",gains)
	veil_material.set_shader_parameter("pool_count",active_pools.size())
	var flashes=PackedVector4Array();var flash_gains=PackedFloat32Array()
	for i in 3:
		if i<combat_flashes.size():
			var f=combat_flashes[i];var p:Vector3=f.position
			flashes.append(Vector4(p.x,p.y,p.z,float(f.radius)));flash_gains.append(clampf(float(f.remaining)/.10,0,1))
		else:flashes.append(Vector4.ZERO);flash_gains.append(0)
	veil_material.set_shader_parameter("combat_flashes",flashes)
	veil_material.set_shader_parameter("flash_gains",flash_gains)
	veil_material.set_shader_parameter("flash_count",combat_flashes.size())

func _suppress_legacy_lights() -> void:
	if not is_instance_valid(world): return
	var chunks=world.get("chunks")
	if not chunks is Dictionary: return
	var live: Dictionary={}
	for chunk in chunks.values():
		if not is_instance_valid(chunk): continue
		var id=chunk.get_instance_id();live[id]=true
		if not _scanned_chunks.has(id): _suppress_node(chunk);_scanned_chunks[id]=true
	for id in _scanned_chunks.keys():
		if not live.has(id): _scanned_chunks.erase(id)
	for i in range(_legacy_lights.size()-1,-1,-1):
		if not is_instance_valid(_legacy_lights[i].node.get_ref()): _legacy_lights.remove_at(i)

func _suppress_node(node: Node) -> void:
	if (node is OmniLight3D or node is SpotLight3D) and not bool(node.get_meta("worldui_environment_light",false)):
		_legacy_lights.append({"node":weakref(node),"visible":node.visible});node.visible=false
	for child in node.get_children(): _suppress_node(child)

func _restore_legacy_lights() -> void:
	for entry in _legacy_lights:
		var node=entry.node.get_ref()
		if is_instance_valid(node): node.visible=bool(entry.visible)
	_legacy_lights.clear();_scanned_chunks.clear()

func _sync_pilot_overrides() -> void:
	if not is_instance_valid(pilot): return
	var existing=pilot.get("searchlight")
	if is_instance_valid(existing):
		if _pilot_searchlight_ref==null or _pilot_searchlight_ref.get_ref()!=existing:
			_pilot_searchlight_ref=weakref(existing);_pilot_searchlight_visible=existing.visible
		existing.visible=false
	var silhouette=pilot.get("silhouette_material")
	if silhouette is Material:
		if _silhouette_material!=silhouette:
			_silhouette_material=silhouette;_silhouette_priority=silhouette.render_priority
		silhouette.render_priority=127

func _restore_pilot_overrides() -> void:
	if _pilot_searchlight_ref!=null:
		var existing=_pilot_searchlight_ref.get_ref()
		if is_instance_valid(existing): existing.visible=_pilot_searchlight_visible
	_pilot_searchlight_ref=null
	if is_instance_valid(_silhouette_material): _silhouette_material.render_priority=_silhouette_priority
	_silhouette_material=null

func _build_reflectors() -> void:
	reflector_root=Node3D.new();reflector_root.name="EditableNightWayfinding";add_child(reflector_root)
	# Regional authored route lamps already supply continuous static navigation.
	# No synthetic city-grid or straight-canal reflectors are spawned.

func _reflector_post(amber: bool) -> Node3D:
	# Editable primitive components: base, powder-coated post, reflector band, cap.
	var root=Node3D.new();root.name="AmberWorkBeacon" if amber else "ShoreReflector"
	var dark=StandardMaterial3D.new();dark.albedo_color=Color("384f59");dark.roughness=.72
	var reflective=StandardMaterial3D.new();reflective.albedo_color=Color("e3e5d3");reflective.roughness=.18;reflective.metallic=.30
	var cap=StandardMaterial3D.new();cap.albedo_color=Color("f7bb58") if amber else Color("d8e9e7")
	cap.roughness=.18;cap.metallic=.16
	if amber: cap.emission_enabled=true;cap.emission=Color("bd6e25");cap.emission_energy_multiplier=.4
	var height=1.25 if amber else .86
	for part in [{"y":.06,"radius":.19,"height":.12,"material":dark},{"y":height*.5,"radius":.075,"height":height,"material":dark},{"y":height*.72,"radius":.081,"height":.16,"material":reflective},{"y":height,"radius":.105,"height":.12,"material":cap}]:
		var mesh=MeshInstance3D.new();var cylinder=CylinderMesh.new()
		cylinder.top_radius=part.radius;cylinder.bottom_radius=part.radius;cylinder.height=part.height;cylinder.radial_segments=8;cylinder.rings=1
		mesh.mesh=cylinder;mesh.material_override=part.material;mesh.position.y=part.y
		mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;root.add_child(mesh)
	return root

func _position_shore_posts() -> void:
	pass

func _exit_tree() -> void:
	_restore_legacy_lights()
	_restore_pilot_overrides()
	if is_instance_valid(veil): veil.queue_free()
