class_name CombatFeedbackV22
extends Node3D
## Presentation only. Damage, aiming and rewards remain owned by production combat.

signal shake_requested(strength: float, direction: Vector3)
signal wreck_impact(event: Dictionary)

const MAX_PARTICLES = 192
const MAX_WRECKS = 12
const MAX_POPUPS = 24
const MAX_BARS = 16
const MAX_WARNING_MARKERS = 4
const MAX_RIMS = 8
const RIM_SHADER = preload("res://assets/shaders/v22_combat/visible_body_rim.gdshader")
const MERGE_SECONDS = 0.16
const ASSET_ROOT = "res://assets/models/v22_combat/"
const ROLE_MODELS = {"scout":"enemy_scout", "harasser":"enemy_harasser", "shooter":"enemy_harasser", "charger":"enemy_harasser", "suppressor":"enemy_suppressor", "boss":"enemy_suppressor", "support":"enemy_support"}
const ROLE_NAMES = {"scout":"侦察", "harasser":"骚扰", "shooter":"巡逻", "charger":"突击", "suppressor":"压制", "boss":"重型", "support":"支援", "power_node":"供能节点"}
const PART_NAMES = {"hull":"机体", "rotor_left":"左旋翼", "rotor_right":"右旋翼", "power":"动力电池", "sensor":"传感器"}
const COLOR_HIT = Color("f6d68d")
const COLOR_SHIELD = Color("9ee4ef")
const COLOR_OWN = Color("e88771")
const COLOR_DARK = Color("10232a")

var combat: Node
var pilot: Node3D
var camera: Camera3D
var visibility_test: Callable
var reduced_motion = false
var text_scale = 1.0
var feedback_enabled = true
var _configured = false
var _time = 0.0
var _refresh_clock = 0.0
var _particle_cursor = 0
var _wreck_cursor = 0
var _seen: Dictionary = {}
var _seen_order: Array[String] = []
var _pending: Dictionary = {}
var _popups: Array[Dictionary] = []
var _aircraft: Dictionary = {}
var _particles: Array[Dictionary] = []
var _meshes: Dictionary = {}
var _wrecks: Array[Dictionary] = []
var _scenes: Dictionary = {}
var _canvas: CanvasLayer
var _overlay: FeedbackSurface
var _rng = RandomNumberGenerator.new()
var _own_flash = 0.0
var _own_sector = Vector2.ZERO
var _own_status = ""
var _own_status_until = 0.0
var _received_damage = 0.0
var _visible_damage = 0.0
var _dropped_hidden_events = 0
var _deduplicated_events = 0
var _wreck_serial = 0
var _los_clock = 0.0
var _camera_los: Dictionary = {}
var _rims: Dictionary = {}
var _hud_owner: WeakRef
var _hud_fields: Array[String] = []

func configure(value_combat: Node, value_pilot: Node3D, value_camera: Camera3D, visibility_callable: Callable, value_reduced_motion = false) -> void:
	if is_instance_valid(combat) and combat.has_signal("combat_event") and combat.is_connected("combat_event",on_event): combat.disconnect("combat_event",on_event)
	_restore_all_rims()
	combat=value_combat;pilot=value_pilot;camera=value_camera;visibility_test=visibility_callable;reduced_motion=value_reduced_motion
	_bind_hud_context()
	if not _configured:
		name="CombatFeedbackV22";_rng.seed=220151
		_build_particles();_build_wrecks()
		_canvas=CanvasLayer.new();_canvas.layer=0;add_child(_canvas)
		_overlay=FeedbackSurface.new();_overlay.feedback=self;_overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE
		_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);_canvas.add_child(_overlay)
		_configured=true
	if is_instance_valid(combat) and combat.has_signal("combat_event"):combat.connect("combat_event",on_event)
	_refresh_aircraft()

func set_feedback_enabled(value: bool) -> void:
	feedback_enabled=value
	if not value:_restore_all_rims()
	if is_instance_valid(_canvas):_canvas.visible=value
	visible=value

func _exit_tree() -> void:
	_restore_all_rims()
	if is_instance_valid(combat) and combat.has_signal("combat_event") and combat.is_connected("combat_event",on_event):combat.disconnect("combat_event",on_event)

static func vector_value(value: Variant, fallback = Vector3.ZERO) -> Vector3:
	if value is Vector3:return value if value.is_finite() else fallback
	if (value is Array or value is PackedFloat32Array or value is PackedFloat64Array) and value.size()>=3:
		var result=Vector3(float(value[0]),float(value[1]),float(value[2]))
		return result if result.is_finite() else fallback
	return fallback

func _visible(point: Vector3) -> bool:
	return feedback_enabled and point.is_finite() and (not visibility_test.is_valid() or bool(visibility_test.call(point)))

func _pilot_id_matches(value: Variant) -> bool:
	if not is_instance_valid(pilot):return false
	var id=str(value)
	if id==str(pilot.get_instance_id()):return true
	if id==str(pilot.get_meta("combat_id","__none__")) or id==str(pilot.get_meta("entity_id","__none__")) or id==str(pilot.get_meta("unit_id","__none__")):return true
	var row:Dictionary=_aircraft.get(str(pilot.get_instance_id()),{})
	return not id.is_empty() and id==str(row.get("entity_id","__none__"))

func on_event(event: Dictionary) -> void:
	if not _configured or event.is_empty():return
	var kind=str(event.get("kind",""))
	var receipt=str(event.get("receipt_id",""))
	var key=("receipt:"+receipt) if not receipt.is_empty() and kind in ["hit","shield_absorbed"] else kind+":"+str(event.get("event_id",""))
	if key.ends_with(":"):return # No identity means no reliable replay deduplication.
	if _seen.has(key):_deduplicated_events+=1;return
	_seen[key]=true;_seen_order.append(key)
	while _seen_order.size()>512:_seen.erase(_seen_order.pop_front())
	var position=vector_value(event.get("position"))
	# Shot position is the aircraft center for gameplay/audio. Visual emission
	# and its visibility check belong at the actual weapon Muzzle when supplied.
	if kind=="shot":position=vector_value(event.get("muzzle_position"),position)
	var direction=vector_value(event.get("direction"),Vector3.FORWARD).normalized()
	var damage=maxf(0.0,float(event.get("damage",0)))
	var own_hit=bool(event.get("target_is_pilot",event.get("pilot_target",false))) or _pilot_id_matches(event.get("target_id",""))
	if kind in ["hit","shield_absorbed"]:
		_received_damage+=damage
		if own_hit:_show_own_impact(event,direction,damage)
	if not _visible(position):
		_dropped_hidden_events+=1
		# Physics wrecks still exist in darkness, but never emit a delayed popup.
		if kind=="destroyed":_spawn_destroyed(event,position,direction)
		return
	match kind:
		"shot":
			var friendly=bool(event.get("friendly",false)) or _pilot_id_matches(event.get("source_id",""))
			var color=Color("b1f0d9") if friendly else COLOR_HIT
			_emit_particle("spark",position,direction*.6,.075,.17,color)
			# A short muzzle streak represents the shot; production Bolt owns travel.
			_emit_particle("streak",position+direction*.15,direction*7,.07,.055,color,direction)
		"hit","shield_absorbed":
			_queue_receipt(event,position)
			var shield=maxf(0.0,float(event.get("shield_absorbed",0)))
			if shield>0 or kind=="shield_absorbed":_emit_particle("ring",position,Vector3.ZERO,.23,.48,COLOR_SHIELD)
			if damage>0 or float(event.get("armor_absorbed",0))>0:_surface_impact(event,position,direction)
			_mark_target(event.get("target_id",""),event)
		"destroyed":
			_spawn_destroyed(event,position,direction)
			_burst(position,8,1.8,COLOR_HIT)
		"wreck_impact":_surface_impact(event,position,direction)
		"warning_started","reinforcement_call":
			_emit_particle("ring",position+Vector3.UP*.2,Vector3.ZERO,.48,.72,COLOR_HIT)
			_mark_target(event.get("source_id",""),{"warning":true})

func _show_own_impact(event: Dictionary, direction: Vector3, damage: float) -> void:
	var absorbed=maxf(0.0,float(event.get("shield_absorbed",0)))
	if damage<=0 and absorbed<=0:return
	_own_flash=maxf(_own_flash,.30 if damage>0 else .15)
	if is_instance_valid(camera) and direction.length_squared()>.01:
		var incoming=-direction
		var screen=Vector2(incoming.dot(camera.global_basis.x),-incoming.dot(camera.global_basis.y))
		if screen.length_squared()>.01:
			# Eight broad impact sectors communicate the actual incoming side only.
			var angle=roundf(screen.angle()/(PI/4.0))*(PI/4.0)
			_own_sector=Vector2.from_angle(angle)
	if float(event.get("component_damage",0))>0:
		_own_status=str(event.get("component_name",PART_NAMES.get(str(event.get("component","")),"部件")))+("失效" if bool(event.get("component_disabled",false)) else "受损")
		_own_status_until=_time+2.6
	elif damage<=0:
		_own_status="护盾抵挡";_own_status_until=_time+1.1
	if damage>0 and not reduced_motion:shake_requested.emit(clampf(damage/100.0,.025,.12),direction)

func _queue_receipt(event: Dictionary, position: Vector3) -> void:
	var target=str(event.get("target_id",""))
	if target.is_empty():return
	var row:Dictionary=_pending.get(target,{})
	if row.is_empty():
		if _pending.size()>=MAX_POPUPS:return
		row={"target":target,"position":position,"due":_time+MERGE_SECONDS,"damage":0.0,"armor":0.0,"shield":0.0,"parts":{},"killed":false,"own":_pilot_id_matches(target) or bool(event.get("target_is_pilot",event.get("pilot_target",false)))}
	row.position=position
	row.damage+=maxf(0.0,float(event.get("damage",0)))
	row.armor+=maxf(0.0,float(event.get("armor_absorbed",0)))
	row.shield+=maxf(0.0,float(event.get("shield_absorbed",0)))
	if float(event.get("component_damage",0))>0:
		var part=str(event.get("component",""))
		row.parts[part]=bool(row.parts.get(part,false)) or bool(event.get("component_disabled",false))
	row.killed=bool(row.killed) or bool(event.get("killed",false))
	_pending[target]=row

func _flush_receipts() -> void:
	for target in _pending.keys():
		var row:Dictionary=_pending[target]
		if not _visible(row.position):_pending.erase(target);continue
		if _time<float(row.due):continue
		_pending.erase(target)
		if float(row.damage)<=0 and float(row.armor)<=0 and float(row.shield)<=0:continue
		row["born"]=_time;row["life"]=1.15 if not bool(row.killed) else 1.55
		if _popups.size()>=MAX_POPUPS:_popups.pop_front()
		_popups.append(row);_visible_damage+=float(row.damage)

func _mark_target(id: Variant, event: Dictionary) -> void:
	for key in _aircraft:
		var row:Dictionary=_aircraft[key]
		if str(id)!=key and str(id)!=str(row.get("entity_id","")):continue
		row["show_until"]=_time+2.3
		if event.has("health"):row.health=float(event.health)
		if event.has("max_health"):row.max_health=float(event.max_health)
		if event.has("warning"):row.warning=bool(event.warning)

func update_aircraft(body: Node3D, state: Dictionary) -> void:
	if not is_instance_valid(body):return
	var key=str(body.get_instance_id())
	var row:Dictionary=_aircraft.get(key,{})
	if row.is_empty():
		if _aircraft.size()>=32:return
		row={"ref":weakref(body),"show_until":0.0,"smoke_at":0.0}
	var health_state:Dictionary=state.get("damage_state",state)
	row["health"]=float(state.get("health",health_state.get("health",1)))
	row["max_health"]=maxf(.001,float(state.get("max_health",health_state.get("maximum_health",1))))
	row["components"]=health_state.get("components",{}).duplicate(true)
	row["role"]=str(state.get("role",""));row["friendly"]=bool(state.get("friendly",body==pilot))
	row["warning"]=bool(state.get("warning",false));row["shield"]=bool(state.get("shield",false))
	row["entity_id"]=str(state.get("entity_id",body.get_meta("entity_id",key)))
	row["throttle"]=clampf(float(state.get("throttle",.55)),0,1)
	_aircraft[key]=row
	_ensure_body_rim(body,row)

func _read_property(object: Object, property: StringName, fallback: Variant) -> Variant:
	for item in object.get_property_list():
		if item.name==property:return object.get(property)
	return fallback

func _aircraft_properties(object: Object) -> Dictionary:
	# One fresh enumeration per actor, rather than one per field and eagerly
	# evaluated fallback. No persistent cache can outlive a changed script/schema.
	var wanted={"damage_state":true,"health":true,"hp":true,"maximum_health":true,"max_health":true,"max_hp":true,"role":true,"telegraph":true,"shield_left":true,"entity_id":true,"throttle":true}
	var values:Dictionary={}
	for item in object.get_property_list():
		if wanted.has(item.name):values[item.name]=object.get(item.name)
	return values

func _refresh_aircraft() -> void:
	var bodies:Array=[]
	var power_nodes:Array=[]
	if is_instance_valid(combat):
		# duplicate() preserves Array[CharacterBody3D]; this list also needs the
		# player's RigidBody3D and static task objects, so copy into untyped [].
		for enemy in _read_property(combat,"enemies",[]):bodies.append(enemy)
		for target in _read_property(combat,"target_nodes",[]):power_nodes.append(target)
		bodies.append_array(power_nodes)
	if is_instance_valid(pilot):bodies.append(pilot)
	for body in bodies:
		if not is_instance_valid(body) or body.is_queued_for_deletion():continue
		var properties=_aircraft_properties(body)
		var damage_state:Dictionary=properties.get("damage_state",{})
		var health=float(damage_state.get("health",properties.get("health",properties.get("hp",1))))
		var maximum=float(damage_state.get("maximum_health",properties.get("maximum_health",properties.get("max_health",properties.get("max_hp",1)))))
		var stable_id=body.get_meta("entity_id",body.get_meta("unit_id",str(body.get_instance_id())))
		update_aircraft(body,{"health":health,"max_health":maximum,"damage_state":damage_state,"friendly":body==pilot,"role":properties.get("role","power_node" if body in power_nodes else ""),"warning":float(properties.get("telegraph",0))>0,"shield":float(properties.get("shield_left",0))>0,"entity_id":properties.get("entity_id",stable_id),"throttle":properties.get("throttle",.55)})

func _process(delta: float) -> void:
	if not _configured:return
	_time+=delta;_refresh_clock-=delta;_own_flash=maxf(0,_own_flash-delta)
	if _refresh_clock<=0:_refresh_clock=.1;_refresh_aircraft()
	_flush_receipts()
	for i in range(_popups.size()-1,-1,-1):
		if _time-float(_popups[i].born)>=float(_popups[i].life) or not _visible(_popups[i].position):_popups.remove_at(i)
	_update_aircraft_visuals(delta);_update_particles(delta);_update_wrecks(delta)
	_overlay.queue_redraw()

func _physics_process(delta: float) -> void:
	if not _configured or not is_instance_valid(camera):return
	_los_clock-=delta
	if _los_clock>0:return
	_los_clock=.06
	var next_cache:Dictionary={}
	for key in _aircraft:
		var body:Node3D=_aircraft[key].ref.get_ref()
		if is_instance_valid(body):next_cache[key]=_camera_ray_clear(body.global_position+Vector3.UP*.25)
	for row in _popups:next_cache["popup:"+str(row.target)]=_camera_ray_clear(row.position)
	for row in _pending.values():next_cache["popup:"+str(row.target)]=_camera_ray_clear(row.position)
	_camera_los=next_cache

func _camera_ray_clear(point: Vector3) -> bool:
	if not _visible(point) or camera.is_position_behind(point):return false
	var origin=camera.global_position
	if camera.projection==Camera3D.PROJECTION_ORTHOGONAL:
		origin=camera.project_ray_origin(camera.unproject_position(point))
	var direction=point-origin
	if direction.length_squared()<.01:return true
	# Only world collision (layer 1). The target itself and cargo are not walls.
	var query=PhysicsRayQueryParameters3D.create(origin,point-direction.normalized()*.08,1)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func ui_point_visible(point: Vector3, key: String) -> bool:
	# Cache is refreshed on physics ticks; the shared permit is checked again
	# during every draw, so illumination/visibility revocation is immediate.
	return _visible(point) and bool(_camera_los.get(key,false))

func _bind_hud_context() -> void:
	_hud_owner=null;_hud_fields.clear()
	if not visibility_test.is_valid():return
	# Production passes Session.combat_point_visible. Read its existing UI fields
	# once; a test/other permit callable can simply omit this optional context.
	var permit_owner=visibility_test.get_object()
	if not is_instance_valid(permit_owner):return
	var ui:Variant=_read_property(permit_owner,"ui",null)
	if not is_instance_valid(ui):return
	_hud_owner=weakref(ui)
	for property in ui.get_property_list():
		if str(property.name) in ["hud_task_panel","hud_control_panel","hud_telemetry_panel","tutorial_panel"]:_hud_fields.append(str(property.name))

func hud_exclusion_rects() -> Array[Rect2]:
	var rectangles:Array[Rect2]=[]
	var ui=_hud_owner.get_ref() if _hud_owner!=null else null
	if not is_instance_valid(ui):return rectangles
	for field in _hud_fields:
		var control=ui.get(field)
		if control is Control and control.is_visible_in_tree():rectangles.append(control.get_global_rect())
	return rectangles

func popup_placement(preferred: Vector2, footprint: Vector2, viewport_size: Vector2, excluded: Array, occupied: Array) -> Dictionary:
	# Screen layout only: no receipt values, lifetimes, merge windows or visibility
	# permissions are changed. Newer receipts reserve space before older ones.
	var safe=Rect2(Vector2(24,70),viewport_size-Vector2(48,140))
	if not preferred.is_finite() or not footprint.is_finite() or footprint.x<=0 or footprint.y<=0:return {}
	if footprint.x>safe.size.x or footprint.y>safe.size.y:return {}
	var gap=8.0*clampf(text_scale,1.0,1.5)
	var blockers:Array[Rect2]=[]
	for rectangle in excluded+occupied:
		if rectangle is Rect2 and rectangle.has_area():blockers.append(rectangle.grow(gap))
	var candidates:Array[Vector2]=[preferred]
	var seen:Dictionary={}
	var index=0
	# Bounded breadth-first pushes out of HUD/previous text rectangles. Vertical
	# alternatives are preferred, producing a legible stack for repeated hits.
	while index<candidates.size() and index<64:
		var point=candidates[index];index+=1
		point=Vector2(clampf(point.x,safe.position.x,safe.end.x-footprint.x),clampf(point.y,safe.position.y,safe.end.y-footprint.y))
		if seen.has(point):continue
		seen[point]=true
		var bounds=Rect2(point,footprint)
		var blocked=false
		for rectangle in blockers:
			if not rectangle.intersects(bounds):continue
			blocked=true
			for alternative in [Vector2(point.x,rectangle.position.y-footprint.y),Vector2(point.x,rectangle.end.y),Vector2(rectangle.position.x-footprint.x,point.y),Vector2(rectangle.end.x,point.y)]:
				if candidates.size()<64:candidates.append(alternative)
			break
		if not blocked:return {"position":point,"bounds":bounds}
	return {}

func warning_marker(body: Node3D, key: String, is_warning: bool, viewport_size: Vector2, excluded: Array) -> Dictionary:
	if not is_warning or not is_instance_valid(body) or not body.is_visible_in_tree() or not is_instance_valid(camera):return {}
	if not _aircraft.has(key) or not bool(_aircraft[key].warning) or bool(_aircraft[key].friendly) or float(_aircraft[key].health)<=0:return {}
	if not ui_point_visible(body.global_position,key) or camera.is_position_behind(body.global_position):return {}
	var scale_value=clampf(text_scale,1.0,1.5)
	var margin=Vector2(36,48)*scale_value
	var safe=Rect2(margin,viewport_size-margin*2)
	if safe.size.x<80 or safe.size.y<80:return {}
	var projected=camera.unproject_position(body.global_position+Vector3.UP*.6)
	var footprint=Rect2(projected-Vector2(42,36)*scale_value,Vector2(84,60)*scale_value)
	var obscured=not safe.encloses(footprint)
	for rectangle in excluded:
		if rectangle is Rect2 and rectangle.intersects(footprint):obscured=true;break
	if not obscured:return {}
	var center=viewport_size*.5
	var offset=projected-center
	if offset.length_squared()<1:return {}
	var direction=offset.normalized()
	var edge_distance=offset.length()
	if absf(direction.x)>.0001:edge_distance=minf(edge_distance,(safe.end.x-center.x if direction.x>0 else center.x-safe.position.x)/absf(direction.x))
	if absf(direction.y)>.0001:edge_distance=minf(edge_distance,(safe.end.y-center.y if direction.y>0 else center.y-safe.position.y)/absf(direction.y))
	# Walk inward along the true projected bearing until both the arrow and its
	# short label clear the actual HUD rectangles. No distance/role is revealed.
	for step in range(65):
		var point=center+direction*edge_distance*(1.0-float(step)/64.0)
		var marker_bounds=Rect2(point-Vector2(23,14)*scale_value,Vector2(46,43)*scale_value)
		if not safe.encloses(marker_bounds):continue
		var blocked=false
		for rectangle in excluded:
			if rectangle is Rect2 and rectangle.grow(8*scale_value).intersects(marker_bounds):blocked=true;break
		if not blocked:return {"position":point,"direction":direction,"bounds":marker_bounds}
	return {}

func warning_markers(viewport_size: Vector2, excluded: Array) -> Array[Dictionary]:
	var markers:Array[Dictionary]=[]
	if not feedback_enabled:return markers
	for key in _aircraft:
		var row:Dictionary=_aircraft[key]
		var marker=warning_marker(row.ref.get_ref(),key,bool(row.warning),viewport_size,excluded)
		if marker.is_empty():continue
		var crowded=false
		for existing in markers:
			if existing.position.distance_to(marker.position)<48*clampf(text_scale,1.0,1.5):crowded=true;break
		if crowded:continue
		markers.append(marker)
		if markers.size()>=MAX_WARNING_MARKERS:break
	return markers

func _ensure_body_rim(body: Node3D, row: Dictionary) -> void:
	var key=str(body.get_instance_id())
	if not feedback_enabled or bool(row.friendly) or not ROLE_MODELS.has(str(row.role)) or _rims.has(key) or _rims.size()>=MAX_RIMS or bool(row.get("rim_unavailable",false)):return
	var model:Variant=_read_property(body,"model",null)
	if not is_instance_valid(model) or not model is Node3D:return
	var mesh=model.find_child("Body",true,false)
	if not mesh is MeshInstance3D or mesh.mesh==null or mesh.material_overlay!=null:
		# Never replace another system's overlay, nor add passes to every rotor.
		row["rim_unavailable"]=true;return
	var material=ShaderMaterial.new();material.shader=RIM_SHADER
	material.resource_local_to_scene=true;material.render_priority=0
	_rims[key]={"mesh":weakref(mesh),"material":material,"previous":mesh.material_overlay}

func _set_rim_active(key: String, active: bool) -> void:
	if not _rims.has(key):return
	var binding:Dictionary=_rims[key]
	var mesh=binding.mesh.get_ref()
	if not is_instance_valid(mesh):_rims.erase(key);return
	if active:
		if mesh.material_overlay==binding.previous:mesh.material_overlay=binding.material
	elif mesh.material_overlay==binding.material:mesh.material_overlay=binding.previous

func _release_rim(key: String) -> void:
	_set_rim_active(key,false);_rims.erase(key)

func _restore_all_rims() -> void:
	for key in _rims.keys():_release_rim(key)

func _component_ratio(parts: Dictionary, part: String) -> float:
	var value:Variant=parts.get(part,1.0)
	if value is Dictionary:return clampf(float(value.get("health",1))/maxf(.001,float(value.get("maximum",1))),0,1)
	return clampf(float(value),0,1)

func _update_aircraft_visuals(_delta: float) -> void:
	for key in _aircraft.keys():
		var row:Dictionary=_aircraft[key];var body:Node3D=row.ref.get_ref()
		if not is_instance_valid(body) or body.is_queued_for_deletion():_release_rim(key);_aircraft.erase(key);continue
		_set_rim_active(key,float(row.health)>0 and body.is_visible_in_tree() and ui_point_visible(body.global_position,key))
		var parts:Dictionary=row.components
		var left=_component_ratio(parts,"rotor_left");var right=_component_ratio(parts,"rotor_right")
		# EnemyActor owns rotor transforms; feedback never animates them twice.
		if not _visible(body.global_position) or _time<float(row.smoke_at):continue
		var health_ratio=float(row.health)/float(row.max_health)
		var power=_component_ratio(parts,"power")
		if health_ratio<.45 or power<.45:
			row.smoke_at=_time+(.22 if reduced_motion else .13)
			_emit_particle("smoke",body.global_position+Vector3.UP*.15,Vector3(0,.6,0),1.0,.22,Color(.24,.29,.31,.48))
		if minf(left,right)<.5:
			row.smoke_at=_time+.20
			var point=body.to_global(Vector3(-.5 if left<right else .5,0,0))
			_emit_particle("spark",point,Vector3(0,-.5,0),.20,.035,COLOR_HIT)

func _particle_material(smoke = false) -> StandardMaterial3D:
	var material=StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo=true
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	material.no_depth_test=false
	if not smoke:material.emission_enabled=true;material.emission=Color(.18,.16,.12)
	return material

func _build_particles() -> void:
	for kind in ["spark","streak","smoke","ring"]:
		var mesh:PrimitiveMesh
		if kind=="ring":
			var torus=TorusMesh.new();torus.inner_radius=.44;torus.outer_radius=.5;torus.rings=16;torus.ring_segments=4;mesh=torus
		elif kind=="smoke":
			var sphere=SphereMesh.new();sphere.radius=.5;sphere.height=1;sphere.radial_segments=8;sphere.rings=4;mesh=sphere
		else:
			var box=BoxMesh.new();box.size=Vector3.ONE;mesh=box
		mesh.material=_particle_material(kind=="smoke")
		var instance=MultiMeshInstance3D.new();instance.name="Pool_"+kind
		instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var multimesh=MultiMesh.new();multimesh.transform_format=MultiMesh.TRANSFORM_3D;multimesh.use_colors=true;multimesh.mesh=mesh;multimesh.instance_count=MAX_PARTICLES;multimesh.visible_instance_count=0
		instance.multimesh=multimesh;add_child(instance);_meshes[kind]=instance
	for i in range(MAX_PARTICLES):_particles.append({"active":false})

func _emit_particle(kind: String, point: Vector3, velocity: Vector3, life: float, size: float, color: Color, direction=Vector3.FORWARD) -> void:
	if not _visible(point) or not _meshes.has(kind):return
	for i in range(MAX_PARTICLES):
		var index=(_particle_cursor+i)%MAX_PARTICLES
		if bool(_particles[index].active):continue
		_particles[index]={"active":true,"kind":kind,"position":point,"velocity":velocity,"life":life,"remaining":life,"size":size,"color":color,"direction":direction}
		_particle_cursor=(index+1)%MAX_PARTICLES;return

func _burst(point: Vector3, count: int, speed: float, color: Color) -> void:
	for i in range(count if not reduced_motion else mini(count,3)):
		var velocity=Vector3(_rng.randf_range(-1,1),_rng.randf_range(.2,1),_rng.randf_range(-1,1)).normalized()*speed*_rng.randf_range(.5,1)
		_emit_particle("spark",point,velocity,_rng.randf_range(.16,.33),.035,color)

func _surface_impact(event: Dictionary, point: Vector3, direction: Vector3) -> void:
	var surface=str(event.get("surface",event.get("surface_type","metal")))
	if surface in ["water","sea"]:
		_emit_particle("ring",point,Vector3.UP*.02,.6,.5,Color(.67,.85,.88,.7))
		for i in range(3):_emit_particle("spark",point,Vector3(_rng.randf_range(-.5,.5),1.1,_rng.randf_range(-.5,.5)),.25,.04,COLOR_SHIELD)
	elif surface in ["concrete","ground","stone","wall","terrain"]:
		for i in range(3):_emit_particle("smoke",point,-direction*.2+Vector3.UP*.25,.42,.12,Color(.66,.63,.52,.45))
	else:_burst(point,5,1.5,COLOR_HIT)

func _update_particles(delta: float) -> void:
	var counts={"spark":0,"streak":0,"smoke":0,"ring":0}
	for particle in _particles:
		if not bool(particle.active):continue
		particle.remaining-=delta
		if float(particle.remaining)<=0:particle.active=false;continue
		particle.position+=particle.velocity*delta
		if not _visible(particle.position):particle.active=false;continue
		if particle.kind=="spark":particle.velocity+=Vector3.DOWN*delta*4
		var fraction=clampf(float(particle.remaining)/float(particle.life),0,1)
		var scale_value=Vector3.ONE*float(particle.size)
		var basis=Basis.IDENTITY
		if particle.kind=="smoke":scale_value*=1.0+(1.0-fraction)*2.2
		elif particle.kind=="ring":scale_value*=1.0+(1.0-fraction)*1.3
		elif particle.kind=="streak":
			scale_value.z*=10
			if absf(particle.direction.dot(Vector3.UP))<.99:basis=Basis.looking_at(particle.direction,Vector3.UP)
		var color:Color=particle.color;color.a*=fraction
		var multimesh:MultiMesh=_meshes[particle.kind].multimesh
		var index=int(counts[particle.kind]);multimesh.set_instance_transform(index,Transform3D(basis.scaled(scale_value),to_local(particle.position)));multimesh.set_instance_color(index,color)
		counts[particle.kind]=index+1
	for kind in _meshes:_meshes[kind].multimesh.visible_instance_count=counts[kind]

func _build_wrecks() -> void:
	for i in range(MAX_WRECKS):
		var body=RigidBody3D.new();body.name="WreckPool_"+str(i);body.mass=.8;body.freeze=true;body.visible=false
		# World only: cargo uses layer 8 and task objects 32. Debris must not
		# secretly alter deliveries or introduce unreceipted gameplay damage.
		body.collision_layer=0;body.collision_mask=1
		body.contact_monitor=true;body.max_contacts_reported=2;body.continuous_cd=true
		body.linear_damp=.25;body.angular_damp=.35
		var shape=CollisionShape3D.new();var box=BoxShape3D.new();box.size=Vector3(.4,.25,.5);shape.shape=box;shape.disabled=true;body.add_child(shape)
		add_child(body);body.body_entered.connect(_wreck_collision.bind(i))
		_wrecks.append({"body":body,"shape":shape,"active":false,"life":0.0,"model_id":"","visual":null,"collided":false,"serial":0,"full":false,"smoke_at":0.0})

func _scene(asset: String) -> PackedScene:
	if not _scenes.has(asset):
		var path=ASSET_ROOT+asset+".glb"
		if ResourceLoader.exists(path):_scenes[asset]=load(path)
	return _scenes.get(asset,null)

func _spawn_destroyed(event: Dictionary, position: Vector3, direction: Vector3) -> void:
	var role=str(event.get("role",event.get("target_role","harasser")))
	var velocity=vector_value(event.get("velocity"),direction*.5)
	var heading=float(event.get("heading",0))
	if role=="power_node" or str(event.get("entity_kind",""))=="power_node":
		_activate_wreck("wreck_core",position,velocity,heading,false)
		_activate_wreck("wreck_panel",position+Vector3.UP*.15,velocity+Vector3(.3,.7,.2),heading,false)
		return
	var full_asset=str(ROLE_MODELS.get(role,"enemy_harasser"))
	_activate_wreck(full_asset,position,velocity,heading,true)
	for i in range(3):
		var asset=["wreck_core","wreck_rotor","wreck_panel"][i]
		var scatter=Vector3(_rng.randf_range(-1.2,1.2),_rng.randf_range(.3,1.1),_rng.randf_range(-1.2,1.2))
		_activate_wreck(asset,position+scatter*.12,velocity+scatter,heading,false)

func _activate_wreck(asset: String, point: Vector3, velocity: Vector3, heading: float, full: bool) -> void:
	var index=-1
	for offset in range(MAX_WRECKS):
		var candidate=(_wreck_cursor+offset)%MAX_WRECKS
		if not bool(_wrecks[candidate].active):index=candidate;break
	# Preserve the readable full hull over optional fragments; never steal a young hull.
	if index<0 and full:
		for candidate in range(MAX_WRECKS):
			if not bool(_wrecks[candidate].full):index=candidate;break
	if index<0:return
	var slot:Dictionary=_wrecks[index];var body:RigidBody3D=slot.body
	if str(slot.model_id)!=asset:
		if is_instance_valid(slot.visual):slot.visual.queue_free()
		var packed=_scene(asset)
		if packed==null:return
		slot.visual=packed.instantiate();StreetDressingV2._enable_vertex_colors(slot.visual)
		body.add_child(slot.visual);slot.model_id=asset
		for mesh in slot.visual.find_children("*","GeometryInstance3D",true,false):mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shape:BoxShape3D=slot.shape.shape;shape.size=Vector3(1.25,.32,1.0) if full else Vector3(.4,.18,.42)
	body.freeze=true;body.global_transform=Transform3D(Basis(Vector3.UP,heading),point);body.linear_velocity=velocity.limit_length(16)
	body.angular_velocity=Vector3(_rng.randf_range(-1,1),_rng.randf_range(-.5,.5),_rng.randf_range(-1,1))*(1.4 if full else 3.0)
	body.mass=2.3 if full else .35;slot.shape.set_deferred("disabled",false);body.freeze=false;body.sleeping=false
	_wreck_serial+=1;slot.serial=_wreck_serial;slot.active=true;slot.full=full;slot.collided=false;slot.life=7.0 if full else 4.0;slot.smoke_at=_time
	body.visible=_visible(point);_wreck_cursor=(index+1)%MAX_WRECKS

func _wreck_collision(other: Node, index: int) -> void:
	var slot:Dictionary=_wrecks[index]
	if not bool(slot.active) or bool(slot.collided):return
	slot.collided=true
	var point:Vector3=slot.body.global_position
	var surface=str(other.get_meta("surface","ground")) if is_instance_valid(other) else "ground"
	var event={"kind":"wreck_impact","event_id":"wreck:"+str(slot.serial),"position":[point.x,point.y,point.z],"surface":surface,"direction":[0,-1,0],"damage":0.0,"friendly":false}
	if _visible(point):_surface_impact(event,point,Vector3.DOWN)
	wreck_impact.emit(event)

func _update_wrecks(delta: float) -> void:
	for slot in _wrecks:
		if not bool(slot.active):continue
		slot.life-=delta
		var body:RigidBody3D=slot.body
		if float(slot.life)<=0 or body.global_position.y < -20:
			body.freeze=true;body.visible=false;slot.shape.set_deferred("disabled",true);slot.active=false;continue
		body.visible=_visible(body.global_position)
		if bool(slot.full) and body.visible and _time>=float(slot.smoke_at):
			slot.smoke_at=_time+.16
			_emit_particle("smoke",body.global_position+Vector3.UP*.2,Vector3.UP*.6,.9,.23,Color(.22,.27,.30,.45))

func diagnostics() -> Dictionary:
	var particle_count=0;var wreck_count=0;var full_wrecks=0;var active_rims=0
	for particle in _particles:
		if bool(particle.active):particle_count+=1
	for slot in _wrecks:
		if bool(slot.active):wreck_count+=1;full_wrecks+=1 if bool(slot.full) else 0
	for binding in _rims.values():
		var mesh=binding.mesh.get_ref()
		if is_instance_valid(mesh) and mesh.material_overlay==binding.material:active_rims+=1
	return {"particles":particle_count,"wrecks":wreck_count,"full_wrecks":full_wrecks,"popups":_popups.size(),"pending":_pending.size(),"received_damage":_received_damage,"visible_damage":_visible_damage,"hidden_events":_dropped_hidden_events,"duplicates":_deduplicated_events,"popup_receipts":_popups.duplicate(true),"own_flash":_own_flash,"own_status":_own_status,"seen":_seen.size(),"rim_slots":_rims.size(),"active_rims":active_rims}

class FeedbackSurface extends Control:
	var feedback: CombatFeedbackV22
	var font: Font
	var bar_style: StyleBoxFlat
	func _ready() -> void:
		process_mode=Node.PROCESS_MODE_ALWAYS
		font=load("res://assets/fonts/NotoSansSC-Medium.ttf")
		bar_style=StyleBoxFlat.new();bar_style.bg_color=Color(.035,.08,.1,.85);bar_style.corner_radius_top_left=2;bar_style.corner_radius_top_right=2;bar_style.corner_radius_bottom_left=2;bar_style.corner_radius_bottom_right=2
	func _process(_delta: float) -> void:queue_redraw()
	func _text(point: Vector2, value: String, color: Color, font_size=15) -> void:
		font_size=int(font_size*clampf(feedback.text_scale,1.0,1.5))
		draw_string_outline(font,point,value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,4,Color(.03,.08,.10,color.a))
		draw_string(font,point,value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)
	func _project(point: Vector3) -> Vector2:
		return feedback.camera.unproject_position(point)
	func popup_text_layout(headline: String, detail: String) -> Dictionary:
		var scale_value=clampf(feedback.text_scale,1.0,1.5)
		var headline_size=int(20*scale_value);var detail_size=int(12*scale_value)
		var detail_offset=maxf(18*scale_value,font.get_descent(headline_size)+font.get_ascent(detail_size)+3*scale_value)
		var top=-font.get_ascent(headline_size)-4.0
		var bottom=font.get_descent(headline_size)+4.0
		var width=font.get_string_size(headline,HORIZONTAL_ALIGNMENT_LEFT,-1,headline_size).x
		if not detail.is_empty():
			bottom=maxf(bottom,detail_offset+font.get_descent(detail_size)+4.0)
			width=maxf(width,font.get_string_size(detail,HORIZONTAL_ALIGNMENT_LEFT,-1,detail_size).x)
		return {"size":Vector2(width+8,bottom-top),"baseline":Vector2(4,-top),"detail_offset":detail_offset}
	func _draw() -> void:
		if not is_instance_valid(feedback) or not feedback.feedback_enabled or get_tree().paused or not is_instance_valid(feedback.camera) or font==null:return
		var viewport_size=get_viewport_rect().size
		var safe=Rect2(Vector2(24,70),viewport_size-Vector2(48,140))
		var exclusions=feedback.hud_exclusion_rects()
		var marker_scale=clampf(feedback.text_scale,1.0,1.5)
		var popup_occupied:Array=[]
		for marker in feedback.warning_markers(viewport_size,exclusions):
			var point:Vector2=marker.position;var direction:Vector2=marker.direction
			var side=direction.orthogonal()
			draw_circle(point,13*marker_scale,Color(.025,.065,.08,.85))
			draw_colored_polygon(PackedVector2Array([point+direction*9*marker_scale,point-direction*6*marker_scale+side*5*marker_scale,point-direction*6*marker_scale-side*5*marker_scale]),Color(COLOR_HIT,.90))
			_text(point+Vector2(-12,25)*marker_scale,"预警",COLOR_HIT,11)
			popup_occupied.append(marker.bounds)
		var count=0
		for row in feedback._aircraft.values():
			if bool(row.friendly) or float(row.health)<=0 or (feedback._time>float(row.show_until) and not bool(row.warning)):continue
			var body:Node3D=row.ref.get_ref()
			if not is_instance_valid(body) or not feedback.ui_point_visible(body.global_position,str(body.get_instance_id())) or feedback.camera.is_position_behind(body.global_position):continue
			var position=_project(body.global_position+Vector3.UP*.6)
			if not safe.has_point(position):continue
			var bar_bounds=Rect2(position-Vector2(42,38)*marker_scale,Vector2(84,48)*marker_scale)
			var covered=false
			for rectangle in exclusions:
				if rectangle.intersects(bar_bounds):covered=true;break
			if covered:continue
			var width=54.0;var ratio=clampf(float(row.health)/float(row.max_health),0,1)
			draw_style_box(bar_style,Rect2(position+Vector2(-width*.5,-19),Vector2(width,5)))
			draw_rect(Rect2(position+Vector2(-width*.5+1,-18),Vector2((width-2)*ratio,3)),COLOR_HIT if ratio>.3 else COLOR_OWN)
			_text(position+Vector2(-23,-24),str(ROLE_NAMES.get(row.role,""))+(" · 预警" if bool(row.warning) else ""),COLOR_HIT,12)
			popup_occupied.append(bar_bounds)
			count+=1
			if count>=MAX_BARS:break
		for popup_index in range(feedback._popups.size()-1,-1,-1):
			var row:Dictionary=feedback._popups[popup_index]
			if not feedback.ui_point_visible(row.position,"popup:"+str(row.target)) or feedback.camera.is_position_behind(row.position):continue
			var age=feedback._time-float(row.born);var alpha=clampf((float(row.life)-age)*3.0,0,1)
			var position=_project(row.position)+Vector2(12,-30-(0 if feedback.reduced_motion else age*24))
			if not safe.has_point(position):continue
			var color=(COLOR_OWN if bool(row.own) else COLOR_HIT) if float(row.damage)>0 else COLOR_SHIELD;color.a=alpha
			var headline="−"+_number(float(row.damage)) if float(row.damage)>0 else "抵挡"
			if bool(row.killed):headline+="  击毁"
			var detail:PackedStringArray=[]
			if float(row.shield)>0:detail.append("护盾 "+_number(float(row.shield)))
			if float(row.armor)>0:detail.append("装甲 "+_number(float(row.armor)))
			for part in row.parts:detail.append(str(PART_NAMES.get(part,part))+("失效" if bool(row.parts[part]) else "受损"))
			var detail_text=" · ".join(detail)
			var text_layout=popup_text_layout(headline,detail_text)
			var placement=feedback.popup_placement(position-text_layout.baseline,text_layout.size,viewport_size,exclusions,popup_occupied)
			if placement.is_empty():continue
			popup_occupied.append(placement.bounds)
			position=placement.position+text_layout.baseline
			_text(position,headline,color,20)
			if not detail.is_empty():_text(position+Vector2(0,text_layout.detail_offset),detail_text,Color(.83,.89,.88,alpha),12)
		if feedback._own_flash>0:
			var strength=clampf(feedback._own_flash/.3,0,1)
			var color=Color(COLOR_OWN,.30*strength)
			var edge=4.0 if feedback.reduced_motion else 8.0
			draw_rect(Rect2(Vector2.ZERO,Vector2(viewport_size.x,edge)),color)
			draw_rect(Rect2(Vector2(0,viewport_size.y-edge),Vector2(viewport_size.x,edge)),color)
			draw_rect(Rect2(Vector2.ZERO,Vector2(edge,viewport_size.y)),color)
			draw_rect(Rect2(Vector2(viewport_size.x-edge,0),Vector2(edge,viewport_size.y)),color)
			if feedback._own_sector.length_squared()>.1:
				var center=viewport_size*.5;var radius=minf(viewport_size.x,viewport_size.y)*.28
				var angle=feedback._own_sector.angle()
				draw_arc(center,radius,angle-.28,angle+.28,12,Color(COLOR_OWN,strength*.8),4,true)
		if feedback._time<feedback._own_status_until:
			var text_size=font.get_string_size(feedback._own_status,HORIZONTAL_ALIGNMENT_LEFT,-1,15)
			_text(Vector2((viewport_size.x-text_size.x)*.5,viewport_size.y*.72),feedback._own_status,COLOR_OWN,15)
	func _number(value: float) -> String:
		if value>0 and value<.1:return "%.2f"%value
		return str(int(roundf(value))) if absf(value-roundf(value))<.05 else "%.1f"%value
