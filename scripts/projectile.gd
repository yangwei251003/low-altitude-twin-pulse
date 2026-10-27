class_name PulseShot
extends Node3D

var world
var direction: Vector3
var damage = 10.0
var friendly = true
var heavy = false
var speed = 32.0
var life = 2.5
var penetrations=0
var ignored: Array[RID]=[]

func _ready() -> void:
	var color = Color("65dfdc") if friendly else Color("ef9562")
	var trail = GameVisuals.box(self,Vector3.ZERO,Vector3(0.11 if not heavy else 0.2,0.11,0.72),color)
	trail.material_override = GameVisuals.material(color,1.4)
	if direction.length() > 0.1: look_at(global_position+direction,Vector3.UP)

func _physics_process(delta: float) -> void:
	if not world.in_flight: return
	life -= delta
	var next = global_position+direction*speed*delta
	var query = PhysicsRayQueryParameters3D.create(global_position,next,5 if friendly else 3)
	query.exclude=ignored
	if is_instance_valid(world.player) and friendly:query.exclude.append(world.player.get_rid())
	var result = get_world_3d().direct_space_state.intersect_ray(query)
	if not result.is_empty():
		var object = result.collider
		if object.has_method("take_damage"):
			object.take_damage(damage)
		world.effect(result.position,Color("89e4dc") if friendly else Color("efa473"),0.25 if not heavy else 0.7)
		if heavy and friendly and penetrations==0 and object.has_method("take_damage"):
			ignored.append(object.get_rid())
			penetrations+=1;damage*=.55
			global_position=result.position+direction*.12
		else:queue_free()
	else:
		global_position = next
	if life < 0 or not world.flight_bounds.grow(4).has_point(Vector2(position.x,position.z)):queue_free()
