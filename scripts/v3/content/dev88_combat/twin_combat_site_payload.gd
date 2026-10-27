extends CharacterBody3D
## A real optional service drone. Its only motion is ordinary move_and_slide;
## escort milestones require the actual body at a route point, never a timer.
const DamageModel = preload("res://scripts/v2/damage_model.gd")
const Fleet = preload("res://scripts/v2/fleet_visuals.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
var combat: Node3D
var authoritative := false
var hp := 64.0
var max_hp := 64.0
var damage_state: Dictionary = {}
var dimensions := Vector3(1.6, .65, 1.6)
var model: Node3D
var points: Array = []
var waypoint := 0
var mode := "escort"
var arrived := false
var dying := false
var _rotors: Array[Node3D] = []

func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2 | 4 | 8 | 32
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = dimensions
	shape.shape = box
	add_child(shape)
	model = Fleet.make_drone("tr01", Catalog.default_build("tr01").get("slots", {}))
	if is_instance_valid(model): add_child(model)
	if is_instance_valid(model):
		for node: Node in model.find_children("*", "Node3D", true, false):
			if str(node.name).begins_with("Rotor"): _rotors.append(node)
	damage_state = DamageModel.create_state(max_hp, 10.0, dimensions)
	set_physics_process(false)

func _physics_process(_delta: float) -> void:
	pass

func host_tick(delta: float, hold: bool) -> void:
	if not authoritative or dying or hp <= 0.0 or arrived: return
	_spin_rotors(delta)
	if mode == "defend" or hold or points.is_empty():
		velocity = Vector3.ZERO
		return
	if waypoint >= points.size():
		arrived = true
		velocity = Vector3.ZERO
		return
	var goal: Vector3 = points[waypoint]
	if global_position.distance_to(goal) <= 1.0:
		waypoint += 1
		if waypoint >= points.size():
			arrived = true
			velocity = Vector3.ZERO
			return
		goal = points[waypoint]
	var wanted: Vector3 = (goal - global_position).normalized() * minf(2.2, global_position.distance_to(goal) * 1.4)
	velocity = velocity.move_toward(wanted, 1.8 * delta)
	var fraction: float = combat.motion_fraction(self, global_position, velocity * delta)
	velocity *= fraction if fraction >= .999 else maxf(0.0, fraction - .001)
	move_and_slide()
	var horizontal := Vector3(velocity.x, 0, velocity.z)
	if horizontal.length() > .1: rotation.y = lerp_angle(rotation.y, atan2(-horizontal.x, -horizontal.z), minf(1.0, delta * 2.0))

func apply_combat_hit(amount: float, direction: Vector3, point: Vector3, weapon_type = "kinetic", _context: Dictionary = {}) -> Dictionary:
	if not authoritative or dying or not combat.settlement_active_for(self): return {}
	damage_state.health = hp
	var receipt: Dictionary = DamageModel.resolve(damage_state, amount, to_local(point), global_basis.inverse() * direction, weapon_type)
	if receipt.is_empty(): return {}
	hp = float(receipt.health)
	if hp <= 0.0:
		dying = true
		velocity = Vector3.ZERO
		collision_layer = 0
		collision_mask = 0
		combat.payload_disabled()
	return receipt

func present_tick(delta: float) -> void:
	if not authoritative and not dying: _spin_rotors(delta)

func _spin_rotors(delta: float) -> void:
	for index in range(_rotors.size()):
		_rotors[index].rotate_y(delta * (60.0 + velocity.length() * 4.0) * (1.0 if index % 2 == 0 else -1.0))
