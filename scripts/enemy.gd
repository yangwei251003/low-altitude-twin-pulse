class_name DroneEnemy
extends CharacterBody3D

var world
var kind = "patrol"
var health = 60.0
var maximum_health = 60.0
var state = "recover"
var clock = 1.0
var phase = 1
var cycle = 0
var model: Node3D
var warning: Node3D
var committed = Vector3.ZERO
var anchor = Vector3.ZERO
var shield_nodes: Array = []
var dead = false
var healing_clock = 0.0
var hurt_tint = 0.0
var name_label: String
var encounter_id=0

func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	maximum_health = {"patrol":65.0,"charger":85.0,"repair":55.0,"boss":750.0,"node":100.0}[kind]
	health = maximum_health
	name_label = {"patrol":"巡逻射手机","charger":"冲撞护卫机","repair":"护盾维修机","boss":"蜂巢管家","node":"护盾节点"}[kind]
	var col = CollisionShape3D.new()
	var shape = SphereShape3D.new()
	shape.radius = 2.2 if kind == "boss" else (0.8 if kind == "node" else 0.7)
	col.shape = shape
	add_child(col)
	model = GameVisuals.asset(self, "boss" if kind == "boss" else ("node" if kind == "node" else "enemy_"+kind))
	anchor = position
	clock = 0.6+fmod(absf(position.x),1.3)

func take_damage(amount: float) -> void:
	if dead: return
	if kind == "boss" and phase == 2:
		world.effect(global_position,Color("67ccd3"),2.0)
		return
	health = maxf(0,health-amount)
	if health <= 0:
		dead = true
		collision_layer = 0
		world.enemy_destroyed(self)
		world.effect(global_position,Color("f4ba7d"),2 if kind=="boss" else 0.9)
		world.sound("destroy")
		queue_free()
