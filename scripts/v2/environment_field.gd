class_name EnvironmentFieldV22
extends RefCounted
## Analytic, deterministic environmental field. Velocities are m/s, density kg/m3.
## No gameplay force is applied here: the flight body owns relative-air drag.

const WEATHER = {
	"clear": {"speed":1.8,"rain":0.0,"fog":0.0,"wetness":0.0},
	"breeze": {"speed":4.6,"rain":0.0,"fog":0.04,"wetness":0.0},
	"mist": {"speed":1.4,"rain":0.0,"fog":0.55,"wetness":0.16},
	"rain": {"speed":3.4,"rain":0.75,"fog":0.24,"wetness":0.85}
}
const ANCHORS = {"R1":Vector3(112,0,80),"R2":Vector3(212,0,80),"R3":Vector3(174,0,320),"R4":Vector3(412,0,80)}
var region_id = "R1"
var _world_ref: WeakRef
var layout_anchor = Vector3.ZERO
var layout_event: Dictionary = {}
var seed_value = 1
var time_s = 0.0
var weather = "clear"
var weather_target = "clear"
var rain = 0.0
var fog = 0.0
var wetness = 0.0
var wind_speed = 1.8
var difficulty = "standard"
var wind_enabled = true
var weather_enabled = true
var damage_enabled = true
var interference_enabled = true
var wind_multiplier = 1.0
var weather_multiplier = 1.0
var interference_multiplier = 1.0
var fan_enabled = true
var interference_source_enabled = true
var obstacle_cells: Dictionary = {}
var custom_water_regions: Array = []
var phase = 0.0
var focus = Vector3(-1000,0,-1000)
var event_phase = "idle"
var event_remaining = 0.0
var event_duration = 0.0
var event_power = 1.0
var event_bearing = 0.0
var event_sequence = 0
var event_rng = RandomNumberGenerator.new()

const ENCOUNTERS = {
	"R1":{"kind":"electromagnetic","label":"分流塔电磁间歇","center":Vector3(345,1.5,370),"radius":13.0},
	"R2":{"kind":"vent_pulse","label":"风口排风脉冲","center":Vector3(212,1.8,88),"radius":10.0},
	"R3":{"kind":"coastal_gust","label":"海滨短时阵风","center":Vector3(186,3,320),"radius":24.0},
	"R4":{"kind":"updraft","label":"港区局部上升气流","center":Vector3(412,3,80),"radius":16.0}
}

func configure(id: String, value_seed: int, settings: Dictionary, obstacles: Array = []) -> void:
	region_id = id
	_world_ref = null
	layout_anchor = ANCHORS.get(id,Vector3.ZERO)
	layout_event.clear()
	seed_value = value_seed
	event_rng.seed=value_seed+int(id.hash())+22042
	event_phase="idle";event_remaining=0.0;event_duration=0.0;event_sequence=0
	weather_target = {"R1":"clear","R2":"breeze","R3":"mist","R4":"breeze"}.get(id,"clear")
	phase = float(posmod(value_seed,1009))*0.00623 + float(id.hash()%301)*0.021
	obstacle_cells.clear()
	for item in obstacles:
		var key = Vector2i(floori(float(item.x)/50.0),floori(float(item.z)/50.0))
		if not obstacle_cells.has(key): obstacle_cells[key] = []
		obstacle_cells[key].append(item)
	set_settings(settings)
	var initial: Dictionary = WEATHER[weather_target if weather_enabled and weather_multiplier>0 else "clear"]
	wind_speed = initial.speed
	rain = clampf(float(initial.rain)*weather_multiplier,0,1)
	fog = clampf(float(initial.fog)*weather_multiplier,0,.75)
	wetness = clampf(float(initial.wetness)*weather_multiplier,0,1)
	weather = weather_target if weather_enabled and weather_multiplier>0 else "clear"

func configure_world(value_world: Node3D) -> void:
	_world_ref = weakref(value_world)
	var data: Variant = value_world.get("layout")
	if not data is Dictionary or data.is_empty(): return
	var coordinates: Array = data.get("living_anchor",[])
	if coordinates.size()==3: layout_anchor=Vector3(float(coordinates[0]),float(coordinates[1]),float(coordinates[2]))
	layout_event=ENCOUNTERS.get(region_id,ENCOUNTERS.R1).duplicate(true)
	coordinates=data.get("event_center",[])
	if coordinates.size()==3: layout_event.center=Vector3(float(coordinates[0]),float(coordinates[1]),float(coordinates[2]))

func _layout_world() -> Node3D:
	return _world_ref.get_ref() if _world_ref!=null else null

func set_settings(settings: Dictionary) -> void:
	difficulty = str(settings.get("environment_preset",settings.get("environment_difficulty",settings.get("difficulty",difficulty))))
	if difficulty not in ["calm","standard","realistic"]: difficulty = "standard"
	wind_multiplier = _multiplier(settings.get("environment_wind",wind_multiplier))
	weather_multiplier = _multiplier(settings.get("environment_weather",weather_multiplier)) if not settings.get("environment_weather",weather_multiplier) is String else weather_multiplier
	interference_multiplier = _multiplier(settings.get("environment_interference",interference_multiplier))
	wind_enabled = bool(settings.get("wind_enabled",settings.get("wind",wind_enabled)))
	weather_enabled = bool(settings.get("weather_enabled",settings.get("weather",weather_enabled)))
	damage_enabled = bool(settings.get("damage_enabled",settings.get("damage",damage_enabled)))
	interference_enabled = bool(settings.get("interference_enabled",settings.get("interference",interference_enabled)))
	if settings.has("weather_preset"): set_weather(str(settings.weather_preset))

func _multiplier(value: Variant) -> float:
	var number = float(value)
	return clampf(number,0.0,2.0) if is_finite(number) else 1.0

func set_weather(value: String) -> void:
	weather_target = value if WEATHER.has(value) else "clear"

func update_focus(value: Vector3) -> void:
	if value.is_finite(): focus=value

func event_definition() -> Dictionary:
	return layout_event if not layout_event.is_empty() else ENCOUNTERS.get(region_id,ENCOUNTERS.R1)

func event_enabled() -> bool:
	if region_id=="R1": return interference_enabled and interference_source_enabled and interference_multiplier>0.0
	return wind_enabled and wind_multiplier>0.0 and (fan_enabled if region_id=="R2" else true)

func _event_near(point: Vector3) -> bool:
	var event=event_definition()
	return point.distance_to(event.center)<float(event.radius)+6.0

func _advance_event(delta: float) -> void:
	if not event_enabled():
		# Disable the effect immediately, but retain a cooldown to prevent toggle farming.
		if event_phase in ["waiting","warning","active"]:
			event_phase="cooldown";event_remaining=event_rng.randf_range(30,55);event_duration=event_remaining
		elif event_phase=="cooldown": event_remaining=maxf(0,event_remaining-delta)
		return
	if event_phase=="idle":
		if _event_near(focus):
			event_phase="waiting";event_remaining=event_rng.randf_range(1.5,4.5);event_duration=event_remaining
		return
	if event_phase=="waiting" and not _event_near(focus): return
	event_remaining=maxf(0.0,event_remaining-delta)
	if event_remaining>0.0: return
	match event_phase:
		"waiting":
			event_phase="warning";event_remaining=event_rng.randf_range(3.0,5.0)
			event_power=event_rng.randf_range(.75,1.15);event_bearing=phase+event_rng.randf_range(-.7,.7);event_sequence+=1
		"warning": event_phase="active";event_remaining=event_rng.randf_range(6.0,12.0)
		"active": event_phase="cooldown";event_remaining=event_rng.randf_range(30.0,55.0)
		"cooldown": event_phase="idle";event_remaining=0.0
	event_duration=event_remaining

func _event_envelope(point: Vector3) -> float:
	if event_phase!="active" or not event_enabled(): return 0.0
	var event=event_definition();var radius=float(event.radius)
	var spatial=1.0-smoothstep(radius*.45,radius,point.distance_to(event.center))
	var temporal=smoothstep(0,.7,event_duration-event_remaining)*smoothstep(0,1.0,event_remaining)
	return spatial*temporal*event_power

func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0: return
	time_s += delta
	_advance_event(delta)
	var target: Dictionary = WEATHER[weather_target if weather_enabled and weather_multiplier>0.0 else "clear"]
	var blend = 1.0-exp(-delta/6.0)
	wind_speed = lerpf(wind_speed,float(target.speed),blend)
	rain = lerpf(rain,clampf(float(target.rain)*weather_multiplier,0,1),blend)
	fog = lerpf(fog,clampf(float(target.fog)*weather_multiplier,0,.75),blend)
	# Pavement dries more slowly than the rain stops.
	wetness = lerpf(wetness,clampf(float(target.wetness)*weather_multiplier,0,1),1.0-exp(-delta/(14.0 if float(target.wetness)<wetness else 5.0)))
	weather = weather_target if weather_enabled and weather_multiplier>0 else "clear"

func set_water_regions(regions: Array) -> void:
	custom_water_regions = regions.duplicate(true)

func water_at(point: Vector3) -> Dictionary:
	var value_world = _layout_world()
	if is_instance_valid(value_world) and value_world.has_method("water_at"):
		return value_world.water_at(point)
	if not custom_water_regions.is_empty():
		for zone in custom_water_regions:
			var rect: Rect2 = zone.get("rect",Rect2())
			if rect.has_point(Vector2(point.x,point.z)):
				return {"over_water":true,"height":float(zone.get("height",-0.6)),"bed":float(zone.get("bed",-2.2))}
		return {"over_water":false,"height":-0.6,"bed":-2.2}
	if region_id in ["R1","R3"] and point.x>182.0 and point.x<190.0 and point.z>0.0 and point.z<500.0:
		var crossing_distance = absf(wrapf(point.z+25.0,0.0,50.0)-25.0)
		if crossing_distance>5.5: return {"over_water":true,"height":-0.6,"bed":-2.2}
	return {"over_water":false,"height":-0.6,"bed":-2.2}

func sample(point: Vector3) -> Dictionary:
	var scale_factor = {"calm":0.40,"standard":1.0,"realistic":1.35}.get(difficulty,1.0)
	# Weather is primarily visual. Ordinary air is stable and almost still;
	# substantial impulses are bounded, warned encounters rather than global noise.
	var bearing = phase
	var direction = Vector3(cos(bearing),0,sin(bearing))
	var value_world = _layout_world()
	var terrain_y = float(value_world.terrain_height(point)) if is_instance_valid(value_world) and value_world.has_method("terrain_height") else 0.0
	var height_gain = lerpf(0.28,1.0,smoothstep(0.25,8.0,maxf(0.0,point.y-terrain_y)))
	var velocity: Vector3 = direction * .08 * height_gain * float(scale_factor)
	var shelter = 1.0
	var turbulence = Vector3.ZERO
	var cell = Vector2i(floori(point.x/50.0),floori(point.z/50.0))
	for dx in range(-1,2):
		for dz in range(-1,2):
			for building in obstacle_cells.get(cell+Vector2i(dx,dz),[]):
				if point.y>float(building.get("base_y",0))+float(building.h)+1.0 or point.y<float(building.get("base_y",0))-1.0: continue
				var offset = point-Vector3(building.x,point.y,building.z)
				var along = offset.dot(direction)
				var across = absf(offset.dot(Vector3(-direction.z,0,direction.x)))
				var radius = maxf(float(building.w),float(building.l))*0.55
				if along>radius and along<radius+20.0 and across<radius+2.0:
					var fade = (1.0-smoothstep(radius,radius+20.0,along))*(1.0-smoothstep(radius,radius+2.0,across))
					shelter = minf(shelter,1.0-0.62*fade)
					turbulence += Vector3.ZERO
	velocity = velocity*shelter+turbulence
	var anchor: Vector3 = layout_anchor
	var vent_strength = 0.0
	var encounter_strength=_event_envelope(point)
	if region_id=="R2" and fan_enabled and encounter_strength>0.0:
		# Visible industrial fan points +Z; compact smooth volume, no hard force edge.
		var relative = point-(anchor+Vector3(0,1.8,0))
		if relative.z>0.0 and relative.z<16.0:
			vent_strength = (1.0-smoothstep(9.0,16.0,relative.z))*(1.0-smoothstep(1.0,3.3,absf(relative.x)))*(1.0-smoothstep(1.0,2.0,absf(relative.y)))*encounter_strength
			velocity += Vector3(0,0.22,4.2)*vent_strength*float(scale_factor)
	elif region_id=="R3":
		velocity+=Vector3(cos(event_bearing),.12,sin(event_bearing))*4.6*encounter_strength*float(scale_factor)
	elif region_id=="R4":
		velocity+=Vector3(cos(event_bearing)*.6,2.8,sin(event_bearing)*.6)*encounter_strength*float(scale_factor)
	velocity *= wind_multiplier
	if not wind_enabled or wind_multiplier<=0.0:
		velocity = Vector3.ZERO
		vent_strength = 0.0
	velocity = velocity.limit_length(9.0)
	var electromagnetic = 0.0
	var source_position: Vector3 = event_definition().center if region_id=="R1" else anchor+Vector3(0,1.5,0)
	if interference_enabled and interference_source_enabled and region_id=="R1":
		electromagnetic = clampf(encounter_strength*(0.35 if difficulty=="calm" else 0.65)*interference_multiplier,0,.85)
	var water = water_at(point)
	var event=event_definition();var visible_event=_event_near(point) and event_enabled()
	var cosmetic_velocity=velocity+direction*.45*height_gain if wind_enabled and wind_multiplier>0 else Vector3.ZERO
	return {"wind_velocity":velocity,"visual_wind_velocity":cosmetic_velocity,"density":1.225,"wetness":wetness,"weather":weather,"weather_target":weather_target,"rain":rain,"fog":fog,"wind_strength":velocity.length(),"water":bool(water.over_water) and point.y<=float(water.height),"over_water":bool(water.over_water),"water_surface":float(water.height),"water_depth":maxf(0.0,float(water.height)-point.y) if water.over_water else 0.0,"nav_quality":1.0-electromagnetic*0.45,"compass_quality":1.0-electromagnetic,"scan_quality":clampf(1.0-electromagnetic*.2-vent_strength*.15,0.5,1.0),"interference_strength":electromagnetic,"interference_source":source_position,"shelter":shelter,"vent_strength":vent_strength,"damage_enabled":damage_enabled,"difficulty":difficulty,"event_phase":event_phase if visible_event else "none","event_kind":event.kind if visible_event else "","event_seconds":event_remaining if visible_event else 0.0,"event_label":event.label if visible_event else "","event_strength":encounter_strength,"event_center":event.center,"event_radius":event.radius}

func snapshot() -> Dictionary:
	return {"time_s":time_s,"weather":weather,"weather_target":weather_target,"rain":rain,"fog":fog,"wetness":wetness,"wind_speed":wind_speed,"fan_enabled":fan_enabled,"interference_source_enabled":interference_source_enabled,"event_phase":event_phase,"event_remaining":event_remaining,"event_duration":event_duration,"event_power":event_power,"event_bearing":event_bearing,"event_sequence":event_sequence,"event_rng_state":str(event_rng.state)}

func restore(data: Dictionary) -> void:
	time_s = maxf(0.0,float(data.get("time_s",0.0)))
	set_weather(str(data.get("weather_target","clear")))
	weather = str(data.get("weather",weather_target))
	rain = clampf(float(data.get("rain",0.0)),0.0,1.0)
	fog = clampf(float(data.get("fog",0.0)),0.0,1.0)
	wetness = clampf(float(data.get("wetness",0.0)),0.0,1.0)
	wind_speed = clampf(float(data.get("wind_speed",1.8)),0.0,7.0)
	fan_enabled = bool(data.get("fan_enabled",true))
	interference_source_enabled = bool(data.get("interference_source_enabled",true))
	event_phase=str(data.get("event_phase","idle"))
	if event_phase not in ["idle","waiting","warning","active","cooldown"]: event_phase="idle"
	event_remaining=clampf(float(data.get("event_remaining",0)),0,55)
	event_duration=clampf(float(data.get("event_duration",0)),0,55)
	event_power=clampf(float(data.get("event_power",1)),.75,1.15)
	event_bearing=float(data.get("event_bearing",phase));event_sequence=int(data.get("event_sequence",0))
	if data.has("event_rng_state"): event_rng.state=int(data.event_rng_state)
