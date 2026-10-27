class_name HangarStageV22
extends Node3D

## All geometry stays editable; the central aircraft is the actual GLB assembly.
const V = preload("res://scripts/visuals.gd")
const STREETS = preload("res://scripts/v2/street_dressing.gd")
var preview_anchor: Node3D
var preview: Node3D
var reduced_motion = false
var elapsed = 0.0
var _built = false
var _accent: StandardMaterial3D

func configure(settings: Dictionary = {}) -> void:
	reduced_motion = bool(settings.get("reduced_motion", false))
	if _built: return
	_built = true
	name = "WaterfrontWorkshopV22"
	# An open-front maintenance bay leaves the oblique view unobstructed.
	STREETS.slab(self, Vector3(0,-0.34,0), Vector3(32,0.65,25), 1, Color("687b80"))
	for x in range(-15,16,3): V.box(self, Vector3(x,0.004,0), Vector3(0.022,0.015,25), Color("435960"))
	for z in range(-12,13,3): V.box(self, Vector3(0,0.006,z), Vector3(32,0.015,0.022), Color("435960"))
	V.box(self, Vector3(0,3.5,-11.5), Vector3(32,7,0.4), Color("8d9d9a"))
	V.box(self, Vector3(0,1.15,-11.2), Vector3(32,2.3,0.25), Color("29434c"))
	for x in [-14,-7,0,7,14]:
		V.box(self, Vector3(x,3.6,-10.9), Vector3(0.35,7.2,0.5), Color("53666d"))
		V.box(self, Vector3(x,6.6,-8.8), Vector3(0.30,0.3,4.3), Color("36515c"))
		_emissive_box(Vector3(x,6.39,-8.3),Vector3(2.8,0.075,0.25),Color("e4dac0"),0.45)
	for x in [-10.5,-3.5,3.5,10.5]:
		V.box(self, Vector3(x,4.4,-11.17), Vector3(5.9,1.8,0.08), Color("537d89"))
		for offset in [-1.8,0,1.8]: V.box(self, Vector3(x+offset,4.4,-11.05), Vector3(0.06,1.8,0.07), Color("9dbbb8"))
	# Center dais, floor rings and lane marks keep the aircraft visually dominant.
	V.cylinder(self,Vector3(-1,0.10,0),4.8,0.20,Color("2f4d56"))
	V.cylinder(self,Vector3(-1,0.23,0),4.35,0.07,Color("6e888b"))
	V.ring(self,Vector3(-1,0.29,0),4.1,Color("a7ecd7"),0.085)
	for side in [-1,1]:
		for z in range(8):
			var stripe = V.box(self,Vector3(-1+side*5.1,0.027,-5.0+z*1.3),Vector3(0.42,0.022,0.70),Color("e4c67e"))
			stripe.rotation.y = -0.3
		_workbench(Vector3(side*10,0,-6.2),0 if side < 0 else PI)
		STREETS.prop(self,"utility_cabinet",Vector3(side*12.7,0,-8),PI/2*side)
		STREETS.prop(self,"planter",Vector3(side*13.0,0,5.5))
		V.box(self,Vector3(side*10,0.30,5.8),Vector3(2.7,0.6,1.6),Color("63787f"))
		V.box(self,Vector3(side*10,0.65,5.8),Vector3(2.8,0.10,1.7),Color("849b94"))
	_build_rack(Vector3(7.5,0,-9.5))
	_build_rack(Vector3(-7.5,0,-9.5))
	var sign = Label3D.new()
	sign.text = "低空小队  /  WATERFRONT WORKSHOP"
	sign.font = load("res://assets/fonts/NotoSansSC-Medium.ttf")
	sign.font_size = 48
	sign.pixel_size = 0.008
	sign.position = Vector3(0,6.0,-11.12)
	sign.modulate = Color("ebeddc")
	sign.outline_size = 0
	add_child(sign)
	preview_anchor = Node3D.new()
	preview_anchor.name = "AircraftAssemblyAnchor"
	preview_anchor.position = Vector3(-1,2.05,0)
	add_child(preview_anchor)
	var fill = OmniLight3D.new()
	fill.position = Vector3(-3,7.5,3)
	fill.light_color = Color("d6f1e8")
	fill.light_energy = 0.45
	fill.omni_range = 19
	fill.shadow_enabled = false
	add_child(fill)
	var warm = OmniLight3D.new()
	warm.position = Vector3(6,5,-6)
	warm.light_color = Color("ffd6a1")
	warm.light_energy = 0.35
	warm.omni_range = 13
	warm.shadow_enabled = false
	add_child(warm)

func mount_preview(model: Node3D) -> Node3D:
	if not _built: configure()
	if is_instance_valid(preview) and preview != model: preview.queue_free()
	preview = model
	if model.get_parent() != null: model.reparent(preview_anchor, false)
	else: preview_anchor.add_child(model)
	model.position = Vector3.ZERO
	model.scale = Vector3.ONE*3.1
	model.rotation = Vector3(0,-0.35,0)
	return model

func camera_pose() -> Dictionary:
	return {"position":Vector3(16,17,22), "target":Vector3(0,1.4,-0.8), "size":20.0}

func set_reduced_motion(value: bool) -> void:
	reduced_motion = value
	if is_instance_valid(preview_anchor): preview_anchor.position.y = 2.05

func tick(delta: float) -> void:
	if reduced_motion or not is_instance_valid(preview): return
	elapsed += delta
	preview.rotation.y += delta*0.09
	preview_anchor.position.y = 2.05+sin(elapsed*0.85)*0.035

func _workbench(pos: Vector3, yaw: float) -> void:
	var bench = Node3D.new()
	add_child(bench)
	bench.position = pos
	bench.rotation.y = yaw
	V.box(bench,Vector3(0,1.2,0),Vector3(4.7,0.18,1.5),Color("9b9d89"))
	for x in [-1.9,1.9]: V.box(bench,Vector3(x,0.6,0),Vector3(0.15,1.2,1.3),Color("294651"))
	V.box(bench,Vector3(-0.9,0.63,0),Vector3(1.5,1.1,1.25),Color("6e8c90"))
	for y in [0.35,0.65,0.95]: V.box(bench,Vector3(-0.9,y,0.65),Vector3(0.5,0.04,0.05),Color("e1dbc1"))
	V.box(bench,Vector3(0.9,1.9,-0.3),Vector3(1.25,0.85,0.10),Color("18353d"))
	var display = V.box(bench,Vector3(0.9,1.9,-0.23),Vector3(1.04,0.60,0.03),Color("7cbaa9"))
	var display_material = StandardMaterial3D.new()
	display_material.albedo_color = Color("7cbaa9")
	display_material.emission_enabled = true
	display_material.emission = Color("7cbaa9")
	display_material.emission_energy_multiplier = 0.45
	display.material_override = display_material
	V.box(bench,Vector3(-1.2,1.4,0.0),Vector3(0.7,0.22,0.44),Color("e2b976"))
	for n in range(3): V.cylinder(bench,Vector3(n*0.28-0.5,1.42,0.2),0.08,0.25,Color("5a7278"))

func _build_rack(pos: Vector3) -> void:
	var rack = Node3D.new()
	add_child(rack)
	rack.position = pos
	for x in [-1.8,1.8]: V.box(rack,Vector3(x,1.8,0),Vector3(0.13,3.6,1.0),Color("35525c"))
	for y in [0.2,1.45,2.7]:
		V.box(rack,Vector3(0,y,0),Vector3(3.8,0.1,1.1),Color("9aada9"))
		for x in [-1.1,0,1.1]:
			V.box(rack,Vector3(x,y+0.4,0),Vector3(0.85,0.7,0.8),Color("b6aa86") if y<2 else Color("668e91"))
			V.box(rack,Vector3(x,y+0.4,0.41),Vector3(0.35,0.16,0.02),Color("e2e6d5"))

func _emissive_box(pos: Vector3, dimensions: Vector3, color: Color, energy: float) -> void:
	var mesh = V.box(self,pos,dimensions,color)
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	mesh.material_override = material
