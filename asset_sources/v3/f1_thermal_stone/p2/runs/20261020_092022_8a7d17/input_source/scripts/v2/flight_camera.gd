class_name FlightCameraV22
extends RefCounted

const OFFSET = Vector3(32,39,32)
var camera: Camera3D
var target_size = 32.0
var focus = Vector3.ZERO
var lead = Vector3.ZERO
var overview = false
var overview_focus = Vector3(300,0,250)
var saved_size = 32.0
var zoom_count = 0
var impact_strength = 0.0
var impact_direction = Vector3.ZERO
var impact_clock = 0.0

func impact(strength: float, direction: Vector3) -> void:
	if not is_finite(strength) or not direction.is_finite():return
	impact_strength=maxf(impact_strength,clampf(strength,0,.28))
	impact_direction=Vector3(direction.x,0,direction.z).normalized()
	impact_clock=0.0

func configure(value: Camera3D) -> void:
	camera=value

func snap(position_m: Vector3) -> void:
	overview=false
	impact_strength=0
	lead=Vector3.ZERO
	focus=position_m+Vector3.UP*0.8
	camera.size=target_size
	camera.far=260.0
	camera.global_position=focus+OFFSET
	camera.look_at(focus,Vector3.UP)

func zoom(steps: float) -> void:
	if overview: return
	target_size=clampf(target_size*pow(0.86,steps),12.0,70.0)
	zoom_count+=1

func update(delta: float, position_m: Vector3, velocity: Vector3, reduced: bool=false) -> void:
	if overview:
		camera.global_position=overview_focus+OFFSET.normalized()*1100.0
		camera.look_at(overview_focus,Vector3.UP)
		return
	var desired_lead = Vector3(velocity.x,0,velocity.z)*0.16
	lead=lead.lerp(desired_lead.limit_length(1.4),1.0-exp(-delta*2.3))
	focus=focus.lerp(position_m+Vector3.UP*0.8+(Vector3.ZERO if reduced else lead),1.0-exp(-delta*7.0))
	camera.size=lerpf(camera.size,target_size,1.0-exp(-delta*8.0))
	if not camera.get_tree().paused:
		impact_clock+=delta
		impact_strength=move_toward(impact_strength,0,delta*1.5)
	var shift=Vector3.ZERO if reduced else impact_direction*impact_strength*cos(impact_clock*32)
	camera.global_position=focus+OFFSET+shift
	camera.look_at(focus+shift,Vector3.UP)

func enter_overview(viewport_size: Vector2) -> void:
	if overview:return
	saved_size=target_size
	overview=true
	overview_focus=Vector3(300,4,250)
	camera.global_position=overview_focus+OFFSET.normalized()*1100.0
	camera.look_at(overview_focus,Vector3.UP)
	var width=0.0
	var height=0.0
	for x in [-16.0,616.0]:
		for z in [-16.0,516.0]:
			for y in [-2.0,32.0]:
				var local=camera.global_basis.inverse()*(Vector3(x,y,z)-overview_focus)
				width=maxf(width,absf(local.x)*2.0)
				height=maxf(height,absf(local.y)*2.0)
	var aspect=maxf(0.5,viewport_size.x/maxf(1.0,viewport_size.y))
	camera.size=maxf(height,width/aspect)*1.15
	camera.far=2200.0

func exit_overview(position_m: Vector3) -> void:
	target_size=saved_size
	snap(position_m)

func pan_overview(delta_xz: Vector2) -> void:
	if not overview:return
	overview_focus.x=clampf(overview_focus.x+delta_xz.x,-16,616)
	overview_focus.z=clampf(overview_focus.z+delta_xz.y,-16,516)

static func build_overview(world: RegionWorldV2) -> Node3D:
	var root=Node3D.new();root.name="OverviewProxy";root.visible=false
	GameVisuals.box(root,Vector3(300,-.7,250),Vector3(880,.1,780),Color("367b83"))
	WorldUIBuilder.terrain(root,world.layout,false)
	for obstacle in world.obstacles:
		GameVisuals.box(root,Vector3(obstacle.x,float(obstacle.get("base_y",0))+obstacle.h*.5,obstacle.z),Vector3(obstacle.w,obstacle.h,obstacle.l),Color("b9c1b2"))
	return root
