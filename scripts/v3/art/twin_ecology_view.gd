class_name TwinEcologyView
extends Node3D
## Existing fleet/procedural proxies for behavior review, not final character art.
const Cabinet = preload("res://scenes/v3/assets/power_relay_cabinet.tscn")
const DroneStaticBatch = preload("res://scripts/v3/art/twin_drone_static_batch.gd")
const STATUS = {"traveling":"执行航线", "detouring":"绕开危险", "working":"正在作业", "waiting":"等待", "seeking_shelter":"寻找避风点", "sheltered":"避风等待"}
const REASONS = {"power_unavailable":"等待供能恢复", "reserve_depleted":"备用电已耗尽", "supply_unavailable":"等待供应点供能", "retreat_from_danger":"前方危险，沿原路退回", "both_edge_ends_dangerous":"航线两端危险，悬停等待"}
var region_id = ""
var actors: Dictionary = {}
var targets: Dictionary = {}
var transition_from: Dictionary = {}
var transition_time: Dictionary = {}
var labels: Dictionary = {}
var props: Dictionary = {}
var service_label: Label3D
var service_cabinets: Array = []
var label_clock = 0.0
var view_camera: Camera3D

func configure(region: String, definitions: Dictionary) -> void:
	region_id = region
	for spec in definitions.get("actors", []):
		if spec.region != region: continue
		var actor = Node3D.new()
		actor.name = str(spec.id).replace(":", "_")
		add_child(actor)
		var model: Node3D
		if spec.role == "pollination": model = _pollinator_proxy()
		else: model = FleetVisualsV2.make_drone("ag03" if spec.role == "water_transport" else "nx04")
		actor.add_child(model)
		model.scale *= 0.72
		if str(model.name) == "Airframe_nx04":
			var visual_batch: Dictionary = DroneStaticBatch.install(model, true)
			if visual_batch.get("ok", false):
				model.set_meta("v3_drone_static_batch_report", visual_batch.report)
			else:
				push_warning("NX04 visual batch kept original geometry: " + str(visual_batch.get("code", "unavailable")))
		var label = _label(actor, str(spec.name), Vector3(0, 1.6, 0))
		label.visible = false
		actors[spec.id] = actor
		labels[spec.id] = label
		props[spec.id] = {"name":spec.name, "role":spec.role}
	if region == "I1":
		for site in [Vector3(-31, 0, 13), Vector3(18, 2.4, 17.5)]:
			var cabinet = Cabinet.instantiate()
			cabinet.scale = Vector3.ONE * 0.7
			cabinet.create_collision = true
			cabinet.position = site
			add_child(cabinet)
			service_cabinets.append(cabinet)
		service_label = _label(self, "检修台 · 等待运水", Vector3(-29, 3.8, 13))
		service_label.visible = false

func apply_state(packet: Dictionary) -> void:
	for state in packet.get("actors", []):
		if not state is Dictionary or not actors.has(state.get("id")): continue
		if not state.get("p") is Vector3 or not state.p.is_finite(): continue
		if not targets.has(state.id):
			actors[state.id].position = state.p
			transition_from[state.id] = state.p
			transition_time[state.id] = 1.0
		elif targets[state.id].p != state.p:
			transition_from[state.id] = actors[state.id].position
			transition_time[state.id] = 0.0
		targets[state.id] = state.duplicate(true)
		var label: Label3D = labels[state.id]
		var status = str(REASONS.get(state.get("reason", ""), STATUS.get(state.get("phase", ""), "巡视")))
		if state.get("cargo", false): status += " · 已装水" if props[state.id].role == "water_transport" else " · 已装载"
		label.text = str(props[state.id].name) + "\n" + status
	if is_instance_valid(service_label):
		service_label.text = "检修台 · 冷却液 %d/3\n低空靠近自动修复 · 战斗中停用" % clampi(int(packet.get("coolant", 0)), 0, 3)
	if service_cabinets.size() == 2:
		service_cabinets[0].set_state({"powered":int(packet.get("maintenance", {}).get("I1:thermal", 0)) > 0})
		service_cabinets[1].set_state({"powered":int(packet.get("coolant", 0)) > 0})

func update_presentation(delta: float, focus: Vector3, paused: bool) -> void:
	# Orthographic zoom changes Label3D's apparent size even with fixed_size.
	# Match a readable screen height using the actual active camera projection.
	var camera: Camera3D = view_camera if is_instance_valid(view_camera) else get_viewport().get_camera_3d()
	if is_instance_valid(camera):
		var pixels_per_metre = camera.unproject_position(focus + camera.global_basis.y).distance_to(camera.unproject_position(focus))
		if pixels_per_metre > 0.001:
			for label in labels.values(): label.pixel_size = 18.0 / (label.font_size * pixels_per_metre)
			if is_instance_valid(service_label): service_label.pixel_size = 18.0 / (service_label.font_size * pixels_per_metre)
	var nearest = ""
	var best = 10.0
	for id in actors:
		if not targets.has(id): continue
		var actor: Node3D = actors[id]
		var target: Vector3 = targets[id].p
		var movement = target - actor.position
		if paused:
			actor.position = target
			transition_from[id] = target
			transition_time[id] = 1.0
		else:
			# The authority moves at 1 Hz. Interpolate the entire one-second leg
			# instead of easing rapidly then hovering at every network sample.
			transition_time[id] = minf(1.0, float(transition_time.get(id, 1.0)) + delta)
			actor.position = Vector3(transition_from.get(id, target)).lerp(target, float(transition_time[id]))
			if Vector2(movement.x, movement.z).length() > 0.03:
				actor.rotation.y = lerp_angle(actor.rotation.y, atan2(movement.x, movement.z), minf(1, delta * 6))
		var distance = actor.global_position.distance_to(focus)
		if distance < best:
			best = distance
			nearest = id
	for id in labels: labels[id].visible = id == nearest
	if is_instance_valid(service_label): service_label.visible = service_label.global_position.distance_to(focus) < 13

func _label(parent: Node3D, text: String, at: Vector3) -> Label3D:
	var label = Label3D.new()
	label.text = text
	label.position = at
	label.font = load("res://assets/fonts/NotoSansSC-Medium.ttf")
	label.font_size = 48
	label.outline_size = 4
	label.pixel_size = 0.008
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color("ecf4df")
	parent.add_child(label)
	return label

func _pollinator_proxy() -> Node3D:
	var proxy = Node3D.new()
	var material = StandardMaterial3D.new()
	material.albedo_color = Color("68866e")
	material.roughness = 0.9
	var body = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.23
	sphere.height = 0.65
	sphere.radial_segments = 8
	sphere.rings = 4
	body.mesh = sphere
	body.rotation.x = PI / 2
	body.material_override = material
	proxy.add_child(body)
	for side in [-1, 1]:
		var wing = MeshInstance3D.new()
		var shape = BoxMesh.new()
		shape.size = Vector3(0.7, 0.035, 0.27)
		wing.mesh = shape
		wing.position = Vector3(side * 0.4, 0.1, 0)
		wing.rotation.z = side * 0.2
		wing.material_override = material
		proxy.add_child(wing)
	return proxy
