class_name TwinTrialFlowPresentation
extends Node3D
## Local identity signage for the connected trial bench.
## Labels/plates are presentation only. No collision, entity registration,
## liquid scaling, material replacement, observations or gameplay state writes.
## Attach this node directly under an actual Station, then call setup().
const FONT = preload("res://assets/fonts/NotoSansSC-Medium.ttf")
const RECEIVERS := ["I2:trial_receiver_a","I2:trial_receiver_b"]
const PLATE_SIZE := Vector2(0.82,0.76)
var signs: Dictionary = {}
var labels: Dictionary = {}
var configured := false
var camera: Camera3D
var _station_ref: WeakRef

func setup(station: Node3D, view_camera: Camera3D = null) -> Dictionary:
	if configured: return {"ok":false,"code":"already_configured"}
	if not is_instance_valid(station) or get_parent()!=station or not station.has_method("layout"):
		return {"ok":false,"code":"attach_to_station_first"}
	var layout: Dictionary = station.layout()
	if not layout.get("tanks") is Array or layout.get("id","") not in ["I2:trial_flow_v1","I2:trial_flow_v2"]:
		return {"ok":false,"code":"station_layout_required"}
	var receivers: Dictionary = {}
	for spec in layout.tanks:
		if spec is Dictionary and spec.get("id","") in RECEIVERS:
			if not spec.get("center_xz") is Array or spec.center_xz.size()!=2 or not spec.get("inner_size") is Array or spec.inner_size.size()!=3:
				return {"ok":false,"code":"receiver_geometry_required"}
			receivers[spec.id]=spec
	if receivers.size()!=2: return {"ok":false,"code":"both_receivers_required"}
	_station_ref=weakref(station)
	camera=view_camera
	transform=Transform3D.IDENTITY
	for index in range(2):
		var id: String = RECEIVERS[index]
		var spec: Dictionary = receivers[id]
		var side := -1.0 if index==0 else 1.0
		var rim := Vector3(float(spec.center_xz[0]),float(spec.bottom_y)+float(spec.inner_size[1]),
			float(spec.center_xz[1])+float(spec.inner_size[2])*0.5+float(spec.wall_m))
		# A short outboard identity plate, above the window rather than painted
		# over its real float. Constant world size: no amplified water/float motion.
		# Outboard of the central controller's screen-space lock marker in the
		# fixed oblique camera; the leader still points to the actual tank rim.
		var anchor := rim+Vector3(side*0.95,0.48,0.15)
		var sign := Node3D.new()
		sign.name="Receiver"+("A" if index==0 else "B")+"Identity"
		sign.position=anchor
		add_child(sign)
		var plate := MeshInstance3D.new()
		plate.name="IdentityPlate"
		var quad := QuadMesh.new()
		quad.size=PLATE_SIZE
		plate.mesh=quad
		var material := StandardMaterial3D.new()
		material.albedo_color=Color("18363b")
		material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		material.billboard_mode=BaseMaterial3D.BILLBOARD_ENABLED
		material.cull_mode=BaseMaterial3D.CULL_DISABLED
		material.no_depth_test=false
		plate.material_override=material
		plate.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sign.add_child(plate)
		var label := Label3D.new()
		label.name="ReceiverLetter"
		label.text="A" if index==0 else "B"
		label.font=FONT
		label.font_size=64
		label.pixel_size=0.0125
		label.outline_size=4
		label.modulate=Color("f0d39a") if index==0 else Color("b0e5de")
		label.outline_modulate=Color("12272c")
		label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test=false
		label.shaded=false
		sign.add_child(label)
		var stem := _line(rim,anchor-Vector3(0,PLATE_SIZE.y*.5,0),label.modulate)
		stem.name="ReceiverIdentityLeader"
		add_child(stem)
		signs[id]=sign
		labels[id]=label
	configured=true
	process_mode=Node.PROCESS_MODE_ALWAYS
	set_meta("presentation_only",true)
	set_meta("does_not_authorize_observation",true)
	_update_view()
	return {"ok":true,"code":"identity_signs_attached"}

func _process(_delta: float) -> void:
	_update_view()

func _update_view() -> void:
	if not configured: return
	var station: Variant = _station_ref.get_ref() if _station_ref!=null else null
	if not is_instance_valid(station):
		hide()
		return
	if not is_instance_valid(camera) and is_inside_tree(): camera=get_viewport().get_camera_3d()
	for label: Label3D in labels.values():
		# Offset toward the actual viewing direction avoids coplanar text/plate
		# flicker, while keeping normal depth occlusion through other solids.
		var direction := Vector3.BACK
		if is_instance_valid(camera): direction=global_basis.inverse()*camera.global_basis.z.normalized()
		label.position=direction*0.008

static func _line(start: Vector3, finish: Vector3, tint: Color) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	mesh.surface_add_vertex(start)
	mesh.surface_add_vertex(finish)
	mesh.surface_end()
	visual.mesh=mesh
	var material := StandardMaterial3D.new()
	material.albedo_color=tint
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	visual.material_override=material
	visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return visual
