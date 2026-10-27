extends Node3D
## Read-only mechanism feedback. Four reusable mesh beams and one receiver dot;
## no light nodes, physics, timers, Store, simulation or automatic processing.
## API: view.setup(current_world); view.apply_view(host_or_guest_view_packet).
## Opt-in direction cues: attach_direction(selected_body), local +X follows its
## actual basis. Root chooses the few rotating devices that need this cue.
const MAX_SEGMENTS := 4
const BEAM_RADIUS := .035
const MAX_COORDINATE_MM := 2000000.0

static func wire(view: Dictionary) -> Dictionary:
	var packet := {"beam_segments":view.get("beam_segments",[]).duplicate(true),"beam_valid":bool(view.get("beam_valid",false))}
	return packet if valid_wire(packet) else {"beam_segments":[],"beam_valid":false}

static func valid_wire(packet: Variant) -> bool:
	if not packet is Dictionary or packet.size()!=2 or not packet.get("beam_valid") is bool or not packet.get("beam_segments") is Array or packet.beam_segments.size()>MAX_SEGMENTS: return false
	for segment in packet.beam_segments:
		if not segment is Array or segment.size()!=2 or not _valid_point(segment[0]) or not _valid_point(segment[1]): return false
	return true
var _beams: Array[MeshInstance3D] = []
var _beam_shapes: Array[CylinderMesh] = []
var _receiver: MeshInstance3D
var _valid_material: StandardMaterial3D
var _blocked_material: StandardMaterial3D

func setup(parent_world: Node3D) -> bool:
	if not is_instance_valid(parent_world): return false
	if get_parent()==null: parent_world.add_child(self)
	elif get_parent()!=parent_world: return false
	name = "CampaignMechanismView"
	_ensure_geometry()
	return true

func apply_view(packet: Dictionary) -> void:
	_ensure_geometry()
	var segments: Variant = packet.get("beam_segments",[])
	var count := 0
	var endpoint := Vector3.ZERO
	var valid: bool = packet.get("beam_valid",false)==true
	var material: StandardMaterial3D = _valid_material if valid else _blocked_material
	if segments is Array:
		for segment: Variant in segments.slice(0,MAX_SEGMENTS):
			if not segment is Array or segment.size()!=2 or not _valid_point(segment[0]) or not _valid_point(segment[1]): continue
			var from_mm: Array = segment[0]
			var to_mm: Array = segment[1]
			var from_world := Vector3(float(from_mm[0]),float(from_mm[1]),float(from_mm[2]))*.001
			var to_world := Vector3(float(to_mm[0]),float(to_mm[1]),float(to_mm[2]))*.001
			var from: Vector3 = to_local(from_world) if is_inside_tree() else from_world
			var to: Vector3 = to_local(to_world) if is_inside_tree() else to_world
			var span: Vector3 = to-from
			var length: float = span.length()
			if length<.001: continue
			var beam: MeshInstance3D = _beams[count]
			_beam_shapes[count].height = length
			beam.transform = Transform3D(Basis(Quaternion(Vector3.UP,span/length)),(from+to)*.5)
			beam.material_override = material
			beam.visible = true
			endpoint = to
			count += 1
	for index in range(count,MAX_SEGMENTS): _beams[index].hide()
	_receiver.visible = count>0
	if count>0:
		_receiver.position = endpoint
		_receiver.material_override = material

func _ensure_geometry() -> void:
	if not _beams.is_empty(): return
	_valid_material = _material(Color("9de4bf"))
	_blocked_material = _material(Color("d9ac6d"))
	for index in MAX_SEGMENTS:
		var beam := MeshInstance3D.new()
		beam.name = "Beam"+str(index+1)
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = BEAM_RADIUS
		cylinder.bottom_radius = BEAM_RADIUS
		cylinder.height = .01
		cylinder.radial_segments = 6
		cylinder.rings = 1
		beam.mesh = cylinder
		beam.material_override = _blocked_material
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beam.visible = false
		add_child(beam)
		_beams.append(beam)
		_beam_shapes.append(cylinder)
	_receiver = MeshInstance3D.new()
	_receiver.name = "ReceiverPoint"
	var sphere := SphereMesh.new()
	sphere.radius = .11
	sphere.height = .22
	sphere.radial_segments = 8
	sphere.rings = 4
	_receiver.mesh = sphere
	_receiver.material_override = _blocked_material
	_receiver.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_receiver.visible = false
	add_child(_receiver)

static func attach_direction(body: Node3D) -> Node3D:
	if not is_instance_valid(body): return null
	var existing := body.get_node_or_null("MechanismDirection") as Node3D
	if existing!=null: return existing
	var arrow := Node3D.new()
	arrow.name = "MechanismDirection"
	# Place above the real authored box without editing it. This geometry is a
	# direct child of the body, so every authoritative/guest rotation carries it.
	var top := .75
	for node: Node in body.get_children():
		if node is CollisionShape3D and node.shape is BoxShape3D:
			top = maxf(top,node.position.y+node.shape.size.y*.5)
	arrow.position.y = top+.24
	body.add_child(arrow)
	var material: StandardMaterial3D = _material(Color("efd69b"))
	var stem := MeshInstance3D.new()
	stem.name = "DirectionStem"
	var box := BoxMesh.new()
	box.size = Vector3(1.2,.075,.12)
	stem.mesh = box
	stem.material_override = material
	stem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arrow.add_child(stem)
	var tip := MeshInstance3D.new()
	tip.name = "DirectionTip"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = .23
	cone.height = .5
	cone.radial_segments = 3
	tip.mesh = cone
	tip.material_override = material
	tip.position.x = .8
	tip.rotation.z = -PI*.5
	tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arrow.add_child(tip)
	return arrow

static func _valid_point(value: Variant) -> bool:
	if not value is Array or value.size()!=3: return false
	for coordinate: Variant in value:
		if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)) or absf(float(coordinate))>MAX_COORDINATE_MM: return false
	return true

static func _material(tint: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = tint
	material.roughness = 1.0
	return material
