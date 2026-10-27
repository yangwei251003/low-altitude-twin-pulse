extends RefCounted
## CANDIDATE: fixed I4 local air/signal field over the ORIGINAL World3D.
## No tick, clock ownership, actor writes, acceleration, damage, facts or Store.
const ROOT_NAME := "I4StormEnvironment"
const SOURCE_NAME := "StormSource"
const MASK := 1 | 8
const PERIOD_S := 24.0
const MAX_WIND_MPS := 6.5
const RAY_LENGTH_M := 16.0
const FIELD_MIN := Vector3(8,0,-12)
const FIELD_MAX := Vector3(40,25,16)
const WALL_AT := Vector3(24,5.5,.5)
const WALL_SIZE := Vector3(.4,11,15)
const SOURCE_AT := Vector3(32,15,10)
const FOOTPRINT := [Vector3.ZERO,Vector3(0,.28,0),Vector3(0,-.28,0),Vector3(0,0,.55),Vector3(0,0,-.55)]

static func install(world: Node3D) -> Dictionary:
	if not is_instance_valid(world) or not world.is_inside_tree(): return {"ok":false,"code":"live_world_required"}
	if str(world.get("region_id"))!="I4": return {"ok":true,"code":"other_region_unchanged"}
	var previous: Node=world.get_node_or_null(ROOT_NAME)
	if previous!=null:
		return {"ok":previous.get_meta("i4_storm_owned",false)==true,"code":"already_installed" if previous.get_meta("i4_storm_owned",false)==true else "name_owned_elsewhere","root":previous}
	var owner:=Node3D.new()
	owner.name=ROOT_NAME
	owner.set_meta("i4_storm_owned",true)
	world.add_child(owner)
	var steel:=StandardMaterial3D.new()
	steel.albedo_color=Color("667a82")
	steel.roughness=.9
	var warning:=StandardMaterial3D.new()
	warning.albedo_color=Color("dcaf62")
	warning.roughness=.85
	var lamp:=StandardMaterial3D.new()
	lamp.albedo_color=Color("87cba6")
	lamp.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	var wall:=StaticBody3D.new()
	wall.name="Windbreak"
	wall.position=WALL_AT
	wall.collision_layer=1
	wall.collision_mask=0
	wall.set_meta("i4_storm_owned",true)
	owner.add_child(wall)
	var collision:=CollisionShape3D.new()
	var shape:=BoxShape3D.new()
	shape.size=WALL_SIZE
	collision.shape=shape
	wall.add_child(collision)
	_box(wall,"SolidPanel",Vector3.ZERO,WALL_SIZE,steel)
	for z: float in [-6.5,-2.0,2.5,7.0]:
		_box(owner,"VerticalRib",Vector3(23.76,5.5,z),Vector3(.08,11,.1),warning)
	# A supported instrument on existing EastLookout top14.5. It is not an
	# interactable target, waypoint, hidden stand or a new action prerequisite.
	var source:=Node3D.new()
	source.name=SOURCE_NAME
	source.position=SOURCE_AT
	owner.add_child(source)
	_box(source,"InstrumentPole",Vector3(0,-.2,0),Vector3(.08,.6,.08),steel)
	_box(source,"SignalLamp",Vector3(0,.2,0),Vector3(.32,.25,.32),lamp)
	# One fixed west-pointing windsock/arrow. Phase colour is presentation only.
	_box(owner,"WindArrow",Vector3(24,11.28,.5),Vector3(2.0,.12,.22),lamp)
	_box(owner,"ArrowWingA",Vector3(23.1,11.28,.28),Vector3(.55,.12,.12),lamp,Vector3(0,-PI/4,0))
	_box(owner,"ArrowWingB",Vector3(23.1,11.28,.72),Vector3(.55,.12,.12),lamp,Vector3(0,PI/4,0))
	owner.set_meta("phase_material",lamp)
	return {"ok":true,"code":"installed_I4_local_field_geometry","root":owner,"windbreak":wall,"source":source,"collision_bodies":1,"mesh_components":10}

static func sample(world: Node3D, at: Vector3, clock_s: float, baseline: Dictionary) -> Dictionary:
	var result: Dictionary=baseline.duplicate(true)
	if not is_instance_valid(world) or str(world.get("region_id"))!="I4": return result
	if not world.is_inside_tree() or not at.is_finite() or not world.global_transform.is_finite() or not is_finite(clock_s) or clock_s<0.0:
		result["i4_storm"]={"available":false,"code":"invalid_sample_context"}
		return result
	var local: Vector3=world.to_local(at)
	var weight: float=_weight(local)
	if weight<=0.0: return result
	var descriptor: Dictionary=phase_at(clock_s)
	var wind_direction: Vector3=(-world.global_basis.x).normalized()
	var lateral: Vector3=world.global_basis.z.normalized()
	var vertical: Vector3=world.global_basis.y.normalized()
	var hit_count := 0
	var blockers: Array[String]=[]
	var space: PhysicsDirectSpaceState3D=world.get_world_3d().direct_space_state
	# Current-world rays, not layout names or an authored protected rectangle.
	for offset: Vector3 in FOOTPRINT:
		var start: Vector3=at+vertical*offset.y+lateral*offset.z
		var query:=PhysicsRayQueryParameters3D.create(start,start-wind_direction*RAY_LENGTH_M,MASK)
		var hit: Dictionary=space.intersect_ray(query)
		if not hit.is_empty():
			hit_count+=1
			blockers.append(str(hit.collider.get_path()))
	var coverage: float=float(hit_count)/float(FOOTPRINT.size())
	var attenuation: float=1.0-.76*coverage
	var base_wind: Variant=result.get("wind_velocity",Vector3.ZERO)
	if not base_wind is Vector3 or not base_wind.is_finite(): base_wind=Vector3.ZERO
	result["wind_velocity"]=Vector3(base_wind).lerp(wind_direction*float(descriptor.speed_mps)*attenuation,weight).limit_length(MAX_WIND_MPS)
	var source: Node3D=world.get_node_or_null(ROOT_NAME+"/"+SOURCE_NAME)
	var interference := 0.0
	var signal_blocker := ""
	if is_instance_valid(source) and source.is_inside_tree() and source.get_world_3d().space==world.get_world_3d().space:
		var distance: float=at.distance_to(source.global_position)
		var falloff: float=1.0-smoothstep(6.0,20.0,distance)
		if falloff>0.0:
			var query:=PhysicsRayQueryParameters3D.create(at,source.global_position,MASK)
			var hit: Dictionary=space.intersect_ray(query)
			if not hit.is_empty(): signal_blocker=str(hit.collider.get_path())
			var visibility: float=1.0 if signal_blocker.is_empty() else .18
			interference=.78*falloff*(.18+.82*float(descriptor.gust))*visibility*weight
	interference=clampf(interference,0.0,.78)
	result["nav_quality"]=minf(_quality(result.get("nav_quality",1.0)),1.0-.45*interference)
	result["compass_quality"]=minf(_quality(result.get("compass_quality",1.0)),1.0-interference)
	result["i4_storm"]={"available":true,"code":"actual_current_world_sample","phase":descriptor.phase,"phase_seconds":descriptor.phase_seconds,
		"seconds_to_change":descriptor.seconds_to_change,"clock_input":clock_s,"field_weight":weight,"gust":descriptor.gust,"open_wind_mps":descriptor.speed_mps,
		"wind_window":descriptor.phase=="window","shelter_hits":hit_count,"shelter_rays":FOOTPRINT.size(),"shelter_factor":attenuation,"shelter_blockers":blockers,
		"interference_strength":interference,"signal_blocker":signal_blocker,"navigation_source_present":is_instance_valid(source),
		"compass_error_limit_deg":18.0*interference,"compass_error_deg":sin(clock_s*1.7+local.x*.21+local.z*.13)*18.0*interference}
	return result

static func phase_at(clock_s: float) -> Dictionary:
	if not is_finite(clock_s) or clock_s<0.0: return {}
	var t: float=fposmod(clock_s,PERIOD_S)
	var gust := 0.0
	var phase_name := "window"
	var next_change := 5.0
	if t>=18.0:
		phase_name="easing"
		next_change=24.0
		gust=1.0-smoothstep(18.0,24.0,t)
	elif t>=8.0:
		phase_name="gust"
		next_change=18.0
		gust=1.0
	elif t>=5.0:
		phase_name="warning"
		next_change=8.0
		gust=smoothstep(5.0,8.0,t)
	return {"phase":phase_name,"phase_seconds":t,"seconds_to_change":next_change-t,"gust":gust,"speed_mps":lerpf(1.6,6.0,gust)}

static func present(world: Node3D, clock_s: float) -> void:
	if not is_instance_valid(world) or str(world.get("region_id"))!="I4": return
	var owner: Node=world.get_node_or_null(ROOT_NAME)
	var phase: Dictionary=phase_at(clock_s)
	if owner==null or phase.is_empty() or owner.get_meta("last_presented_phase","")==phase.phase: return
	var material: Variant=owner.get_meta("phase_material",null)
	if material is StandardMaterial3D:
		material.albedo_color=Color("87cba6") if phase.phase=="window" else (Color("ed886d") if phase.phase=="gust" else Color("dcaf62"))
	owner.set_meta("last_presented_phase",str(phase.phase))

static func short_status(sampled: Dictionary) -> String:
	var field: Variant=sampled.get("i4_storm")
	if not field is Dictionary or not field.get("available",false): return ""
	var phase_name: String={"window":"侧风减弱窗口","warning":"阵风将增强","gust":"西向阵风","easing":"阵风正在缓和"}.get(field.get("phase"),"风况待确认")
	return phase_name+(" · 实体遮风" if int(field.get("shelter_hits",0))>=4 else " · 开阔风廊")

static func instrument_readout(sampled: Dictionary, true_heading_deg: float) -> Dictionary:
	var field: Variant=sampled.get("i4_storm")
	if not field is Dictionary or not field.get("available",false) or not is_finite(true_heading_deg): return {}
	var error: float=float(field.get("compass_error_deg",0))
	var limit: float=float(field.get("compass_error_limit_deg",0))
	return {"heading_deg":fposmod(true_heading_deg+error,360.0),"uncertainty_deg":limit,
		"nav_quality":_quality(sampled.get("nav_quality",1.0)),"compass_quality":_quality(sampled.get("compass_quality",1.0))}

static func instrument_text(sampled: Dictionary, true_heading_deg: float) -> String:
	var readout: Dictionary=instrument_readout(sampled,true_heading_deg)
	if readout.is_empty(): return ""
	var wind: Vector3=sampled.get("wind_velocity",Vector3.ZERO)
	var direction: String=("西" if wind.x<0 else "东") if absf(wind.x)>=absf(wind.z) else ("北" if wind.z<0 else "南")
	var field: Dictionary=sampled.i4_storm
	return "风→%s %.1fm/s · %s %.1fs\n导航信号 %d%% · 罗盘约 %.0f°（±%.0f°）· 保持目视标志" % [direction,wind.length(),short_status(sampled),float(field.seconds_to_change),roundi(float(readout.nav_quality)*100.0),float(readout.heading_deg),ceilf(float(readout.uncertainty_deg))]

static func _weight(at: Vector3) -> float:
	var boundary: Vector3=Vector3(minf(at.x-FIELD_MIN.x,FIELD_MAX.x-at.x),minf(at.y-FIELD_MIN.y,FIELD_MAX.y-at.y),minf(at.z-FIELD_MIN.z,FIELD_MAX.z-at.z))
	return smoothstep(0,3,boundary.x)*smoothstep(0,2,boundary.y)*smoothstep(0,3,boundary.z)

static func _quality(value: Variant) -> float:
	return clampf(float(value),0.0,1.0) if (value is int or value is float) and is_finite(float(value)) else 1.0

static func _box(parent: Node3D, label: String, at: Vector3, size: Vector3, material: StandardMaterial3D, rotation: Vector3=Vector3.ZERO) -> void:
	var visual:=MeshInstance3D.new()
	visual.name=label
	var mesh:=BoxMesh.new()
	mesh.size=size
	visual.mesh=mesh
	visual.position=at
	visual.rotation=rotation
	visual.material_override=material
	visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(visual)

