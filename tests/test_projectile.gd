extends GutTest

class ShotWorld extends Node3D:
	var in_flight=true
	var flight_bounds=Rect2(-66,-54,132,108)
	var player=null
	func effect(_pos: Vector3,_color: Color,_radius: float) -> void:pass

class DamageTarget extends StaticBody3D:
	var health=100.0
	func _ready() -> void:
		collision_layer=4;collision_mask=0
		var shape=CollisionShape3D.new();var sphere=SphereShape3D.new();sphere.radius=.8;shape.shape=sphere;add_child(shape)
	func take_damage(value: float) -> void:health-=value

func test_shots_hit_outside_the_old_graybox_boundary() -> void:
	var arena=add_child_autofree(ShotWorld.new())
	var target=DamageTarget.new();arena.add_child(target);target.position=Vector3(43,4,29)
	await wait_physics_frames(2)
	var shot=PulseShot.new();shot.world=arena;shot.direction=Vector3.RIGHT;shot.speed=48;shot.damage=15
	arena.add_child(shot);shot.position=Vector3(35,4,29)
	await wait_physics_frames(25)
	assert_eq(target.health,85.0,"Large-map targets must be reachable by actual projectile physics")

func test_heavy_shot_pierces_once_and_applies_reduced_second_hit() -> void:
	var arena=add_child_autofree(ShotWorld.new())
	var a=DamageTarget.new();arena.add_child(a);a.position=Vector3(35,4,25)
	var b=DamageTarget.new();arena.add_child(b);b.position=Vector3(39,4,25)
	await wait_physics_frames(2)
	var shot=PulseShot.new();shot.world=arena;shot.direction=Vector3.RIGHT;shot.speed=48;shot.damage=40;shot.heavy=true
	arena.add_child(shot);shot.position=Vector3(31,4,25)
	await wait_physics_frames(25)
	assert_eq(a.health,60.0)
	assert_almost_eq(b.health,78.0,.01)
