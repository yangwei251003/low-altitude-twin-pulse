extends RefCounted
## Host geometry/pose observation and guest-only static presentation. No Rules,
## ledger, Assembly, joints, controls, Store or dynamics are created on the guest.
## receive() must be called only by the authenticated host-event dispatch path.
const KIND := "canal_replica"
const VERSION := 1
const MAX_BODIES := 128
const MAX_SHAPES := 256
const MAX_SHAPES_PER_BODY := 8
const MAX_POINTS := 128
const MAX_TOTAL_POINTS := 4096
const MAX_BYTES := 262144
const IDS := ["I2:canal_cassette_0","I2:canal_cassette_1","I2:canal_carrier","I2:canal_cooling_relay","I2:canal_cooling_valve","I2:canal_workbench_power"]
const NAMES := ["冷却匣 0","冷却匣 1","换匣运输机","回冷供电点","回冷阀","检修台供电点"]
const PHYSICAL := ["temperature","charge","charge_capacity","power_threshold","powered"]
const TAGS := ["thermal","mechanical","hackable","conductive","electrical","movable"]
const ABILITIES := ["heat","takeover","charge","push_pull"]
var session
var installed := false
var ready := false
var error := ""
var _world: Node3D
var _container: Node3D
var _bodies: Dictionary = {}
var _registered: Dictionary = {}
var _entities: Dictionary = {}
var _definitions: Dictionary = {}
var _epoch := 0
var _serial := 0
var _geometry := ""

func setup(owner_session) -> void:
	if session == owner_session: return
	clear()
	session = owner_session

func clear() -> void:
	_unregister()
	if is_instance_valid(_container):
		# A newer owner may have mounted its own node under our container. Keep
		# such direct children when disposing this participant's known objects.
		for child in _container.get_children():
			if child not in _bodies.values() and is_instance_valid(_world): child.reparent(_world,true)
		_container.free()
	_container = null
	_world = null
	_bodies.clear()
	installed = false
	ready = false
	error = ""
	_epoch = 0
	_serial = 0
	_geometry = ""

func owns_target(id: String) -> bool:
	return installed and _registered.has(id)

func status() -> Dictionary:
	return {"installed":installed,"ready":ready,"body_count":_bodies.size(),"target_count":_registered.size(),"epoch":_epoch,"serial":_serial,"geometry_digest":_geometry,"error":error,"scope":"guest_static_geometry_no_authority"}

## A complete reliable event is deliberately used first. Root owns publication
## rate (at most 10 Hz), new epoch on site replacement, and host-only RPC routing.
func make_event(adapter, epoch: int, serial: int) -> Dictionary:
	if not _live_session() or not session.network.is_authority() or session.region_id != "I2" or adapter == null or adapter.session != session:
		return _export_no("host_current_i2_required")
	if not _integer(epoch,1,2147483647) or not _integer(serial,1,2147483647): return _export_no("export_counter")
	var site: Variant = adapter.module
	if not site is Node3D or not is_instance_valid(site) or not site.is_inside_tree() or site.get_parent() != session.world or site.get_world_3d().space != session.world.get_world_3d().space:
		return _export_no("original_live_assembly_required")
	var nodes: Array = []
	var stack: Array = [site]
	var visited := 0
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		visited += 1
		if visited > 4096: return _export_no("host_tree_limit")
		if node is PhysicsBody3D:
			if nodes.size() >= MAX_BODIES: return _export_no("host_body_limit")
			nodes.append(node)
		for child in node.get_children(): stack.append(child)
	if nodes.is_empty(): return _export_no("host_geometry_empty")
	var targets: Array = []
	var target_paths: Dictionary = {}
	var rows: Array = adapter.target_definitions()
	# Bootstrap may expose only its carrier/cassettes. Do not register a partial
	# interaction vocabulary; all real site colliders can already be displayed.
	if rows.size() == IDS.size():
		for row in rows:
			if not row is Dictionary or row.get("id") not in IDS or not row.get("body") is PhysicsBody3D: return _export_no("host_target_invalid")
			var id: String = str(row.id)
			var body: PhysicsBody3D = row.body
			var path: String = str(body.get_path())
			if body not in nodes or target_paths.has(path) or str(body.get_meta("entity_id","")) != id: return _export_no("host_target_binding")
			for existing in targets:
				if existing.id == id: return _export_no("host_duplicate_target")
			target_paths[path] = id
			var physical := {"position":_xyz(body.global_position)}
			for key in PHYSICAL:
				if row.get("state",{}).has(key): physical[key] = row.state[key]
			var definition: Dictionary = session.world.definitions.get(id,{})
			targets.append({"id":id,"body_path":path,"name":str(definition.get("name",NAMES[IDS.find(id)])),"tags":row.tags.duplicate(),"abilities":row.abilities.duplicate(),"state":physical})
	var bodies: Array = []
	for body: PhysicsBody3D in nodes:
		if body.is_queued_for_deletion() or body.get_world_3d().space != site.get_world_3d().space: return _export_no("host_body_not_live")
		var shapes: Array = []
		# CollisionShape3D only contributes to this body when it is its direct
		# child. Descendant/nested PhysicsBody shapes must never be copied twice.
		for child in body.get_children():
			if not child is CollisionShape3D: continue
			var shape: Dictionary = _export_shape(child)
			if shape.is_empty(): return _export_no("unsupported_host_shape:"+str(child.get_path()))
			shapes.append(shape)
		if shapes.is_empty(): return _export_no("host_body_without_own_shapes")
		var path: String = str(body.get_path())
		bodies.append({"path":path,"pose":_pose(body.global_transform),"layer":int(body.collision_layer),"mask":int(body.collision_mask),"target_id":str(target_paths.get(path,"")),"color":_color(body),"shapes":shapes})
	bodies.sort_custom(func(a,b): return str(a.path) < str(b.path))
	targets.sort_custom(func(a,b): return str(a.id) < str(b.id))
	var event := {"kind":KIND,"version":VERSION,"session_id":str(session.network.session_id),"region":"I2","epoch":epoch,"serial":serial,"bodies":bodies,"targets":targets,"geometry_digest":_geometry_digest(bodies,targets)}
	var checked: Dictionary = _validate(event)
	if not checked.ok: return _export_no("host_"+str(checked.code))
	error = ""
	return event

## Validate the entire envelope and all registry ownership before allocating or
## changing a live collider. No RPC, authoritative simulation, or save is called.
func receive(event: Dictionary) -> Dictionary:
	if not _live_session() or session.network.mode != "guest" or session.network.is_authority() or session.region_id != "I2": return _no("guest_current_i2_required")
	if event.get("session_id") != session.received_session or str(session.received_session).is_empty(): return _no("host_session_mismatch")
	var checked: Dictionary = _validate(event)
	if not checked.ok: return _no(str(checked.code))
	if int(event.epoch) < _epoch or int(event.epoch) == _epoch and int(event.serial) <= _serial: return _no("stale_replica_sequence")
	if is_instance_valid(_world) and _world != session.world: return _no("replica_world_changed_clear_required")
	var next_targets: Dictionary = {}
	for target in event.targets: next_targets[target.id] = target
	for id in IDS:
		var owned: Variant = _registered.get(id)
		if _registered.has(id):
			if not is_instance_valid(owned) or session.world.objects.get(id) != owned or not is_same(session.entities.get(id),_entities.get(id)) or not is_same(session.world.definitions.get(id),_definitions.get(id)): return _no("replica_registration_replaced:"+id)
		elif session.world.objects.has(id) or session.world.definitions.has(id) or session.entities.has(id): return _no("replica_registration_conflict:"+id)
	var same_geometry: bool = installed and event.geometry_digest == _geometry and is_instance_valid(_container)
	if same_geometry:
		for row in event.bodies:
			if not is_instance_valid(_bodies.get(row.path)): return _no("replica_body_missing")
		for row in event.bodies: _bodies[row.path].global_transform = _transform(row.pose)
		for id in next_targets: _entities[id].merge(_physical(next_targets[id].state),true)
	else:
		var staged: Dictionary = _build(event)
		# All construction is detached and local. Failure leaves current bodies,
		# dictionaries, packet sequence, and collisions untouched.
		if not staged.ok: return _no(str(staged.code))
		var old_container: Node3D = _container
		var old_entities: Dictionary = _entities.duplicate()
		for body in _bodies.values():
			if is_instance_valid(body): body.collision_layer = 0
		_unregister()
		_world = session.world
		_container = staged.container
		_bodies = staged.bodies
		_world.add_child(_container)
		for row in event.bodies:
			var body: StaticBody3D = _bodies[row.path]
			body.global_transform = _transform(row.pose)
			body.collision_layer = int(row.layer)
		for id in next_targets:
			var target: Dictionary = next_targets[id]
			var body: StaticBody3D = _bodies[target.body_path]
			var definition := {"id":id,"name":target.name,"tags":target.tags.duplicate(),"abilities":target.abilities.duplicate(),"owner":"neutral","revision":0}
			definition.merge(_physical(target.state),true)
			var entity: Dictionary = old_entities.get(id,definition).duplicate(true)
			entity.merge(_physical(target.state),true)
			_world.objects[id] = body
			_world.definitions[id] = definition
			_world.initial_transforms[id] = body.transform
			session.entities[id] = entity
			_registered[id] = body
			_definitions[id] = definition
			_entities[id] = entity
		if is_instance_valid(old_container): old_container.free()
	installed = true
	ready = next_targets.size() == IDS.size()
	_epoch = int(event.epoch)
	_serial = int(event.serial)
	_geometry = str(event.geometry_digest)
	error = ""
	return {"ok":true,"code":"poses_applied" if same_geometry else "geometry_installed","changed":true,"installed":installed,"ready":ready}

func _unregister() -> void:
	for id in _registered:
		if is_instance_valid(_world) and _world.objects.get(id) == _registered[id]:
			_world.objects.erase(id)
			if is_same(_world.definitions.get(id),_definitions.get(id)): _world.definitions.erase(id)
			_world.initial_transforms.erase(id)
		if is_instance_valid(session) and is_same(session.entities.get(id),_entities.get(id)): session.entities.erase(id)
	_registered.clear()
	_entities.clear()
	_definitions.clear()

func _live_session() -> bool:
	return is_instance_valid(session) and session.active and is_instance_valid(session.world) and session.world.is_inside_tree() and session.world.get("region_id") == session.region_id and session.network != null

static func _export_shape(node: CollisionShape3D) -> Dictionary:
	var shape: Shape3D = node.shape
	if shape == null: return {}
	var data: Variant
	var kind := ""
	if shape is BoxShape3D: kind = "box"; data = _xyz(shape.size)
	elif shape is SphereShape3D: kind = "sphere"; data = [shape.radius]
	elif shape is CapsuleShape3D: kind = "capsule"; data = [shape.radius,shape.height]
	elif shape is CylinderShape3D: kind = "cylinder"; data = [shape.radius,shape.height]
	elif shape is ConvexPolygonShape3D:
		kind = "convex"
		data = []
		for point in shape.points: data.append(_xyz(point))
	else: return {}
	return {"path":str(node.get_path()),"pose":_pose(node.transform),"disabled":node.disabled,"kind":kind,"data":data,"margin":float(shape.margin)}

static func _geometry_digest(bodies: Array, targets: Array) -> String:
	return _geometry_text(bodies,targets).sha256_text()

static func _geometry_text(bodies: Array, targets: Array) -> String:
	var fixed: Array = []
	for body in bodies:
		var shapes: Array = []
		for shape in body.shapes:
			var coordinates: Array = []
			if shape.kind == "convex":
				for point in shape.data: coordinates.append_array(point)
			else: coordinates = shape.data
			shapes.append({"path":shape.path,"pose_f32":_f32_hex(shape.pose),"disabled":shape.disabled,"kind":shape.kind,
				"data_f32":_f32_hex(coordinates),"margin_f32":_f32_hex([shape.margin])})
		fixed.append({"path":body.path,"layer":int(body.layer),"mask":int(body.mask),"target_id":body.target_id,"color_f32":_f32_hex(body.color),"shapes":shapes})
	var definitions: Array = []
	for target in targets:
		definitions.append({"id":target.id,"body_path":target.body_path,"name":target.name,"tags":target.tags,"abilities":target.abilities})
	# Standard Godot physics geometry, Vector3, and Color use real_t=float32.
	# JSON can differ by one binary64 ULP while constructing EXACTLY the same
	# native geometry. Hash its final float32 bits, retaining integer filters;
	# no arbitrary tolerance, decimal rounding, or collision parameter changes.
	return JSON.stringify([fixed,definitions],"",true,true)

static func _f32_hex(values: Array) -> String:
	var native := PackedFloat32Array()
	for value in values: native.append(float(value))
	return native.to_byte_array().hex_encode()

static func _validate(event: Dictionary) -> Dictionary:
	if not _keys(event,["kind","version","session_id","region","epoch","serial","bodies","targets","geometry_digest"]) or event.kind != KIND or event.version != VERSION or event.region != "I2" or not _text(event.session_id,160): return {"ok":false,"code":"replica_header"}
	if not _integer(event.epoch,1,2147483647) or not _integer(event.serial,1,2147483647): return {"ok":false,"code":"replica_counter"}
	if not event.bodies is Array or event.bodies.is_empty() or event.bodies.size() > MAX_BODIES or not event.targets is Array or event.targets.size() not in [0,IDS.size()]: return {"ok":false,"code":"replica_limits"}
	var paths: Dictionary = {}
	var shape_paths: Dictionary = {}
	var target_paths: Dictionary = {}
	var shape_count := 0
	var point_count := 0
	for body in event.bodies:
		if not _keys(body,["path","pose","layer","mask","target_id","color","shapes"]) or not _path(body.path) or paths.has(body.path) or not _pose_valid(body.pose): return {"ok":false,"code":"replica_body"}
		if not _integer(body.layer,0,4294967295) or not _integer(body.mask,0,4294967295) or not body.target_id is String or body.target_id not in IDS and body.target_id != "": return {"ok":false,"code":"replica_filter_or_target"}
		if not _vector(body.color,0.0,1.0) or not body.shapes is Array or body.shapes.is_empty() or body.shapes.size() > MAX_SHAPES_PER_BODY: return {"ok":false,"code":"replica_body_shapes"}
		paths[body.path] = body
		if not body.target_id.is_empty():
			if target_paths.has(body.target_id): return {"ok":false,"code":"replica_duplicate_target"}
			target_paths[body.target_id] = body.path
		for shape in body.shapes:
			shape_count += 1
			if shape_count > MAX_SHAPES or not _keys(shape,["path","pose","disabled","kind","data","margin"]) or not _path(shape.path) or shape_paths.has(shape.path) or str(shape.path).get_base_dir() != body.path or not _pose_valid(shape.pose) or not shape.disabled is bool or not _number(shape.margin,0.0,1.0): return {"ok":false,"code":"replica_shape"}
			shape_paths[shape.path] = true
			if not shape.data is Array: return {"ok":false,"code":"replica_shape_data"}
			match shape.kind:
				"box":
					if not _vector(shape.data,.001,128.0): return {"ok":false,"code":"replica_box"}
				"sphere":
					if shape.data.size() != 1 or not _number(shape.data[0],.001,64.0): return {"ok":false,"code":"replica_sphere"}
				"capsule","cylinder":
					if shape.data.size() != 2 or not _number(shape.data[0],.001,64.0) or not _number(shape.data[1],.001,128.0): return {"ok":false,"code":"replica_round_shape"}
					if shape.kind == "capsule" and float(shape.data[1]) < 2.0*float(shape.data[0]): return {"ok":false,"code":"replica_capsule"}
				"convex":
					if shape.data.size() < 4 or shape.data.size() > MAX_POINTS: return {"ok":false,"code":"replica_convex_count"}
					point_count += shape.data.size()
					if point_count > MAX_TOTAL_POINTS: return {"ok":false,"code":"replica_convex_total"}
					for point in shape.data:
						if not _vector(point,-64.0,64.0): return {"ok":false,"code":"replica_convex_point"}
					if not _convex_volume(shape.data): return {"ok":false,"code":"replica_convex_flat"}
				_: return {"ok":false,"code":"replica_unsupported_shape"}
	var ids: Dictionary = {}
	for target in event.targets:
		if not _keys(target,["id","body_path","name","tags","abilities","state"]) or target.id not in IDS or ids.has(target.id) or target_paths.get(target.id) != target.body_path or not _text(target.name,80): return {"ok":false,"code":"replica_target"}
		ids[target.id] = true
		if not _strings(target.tags,TAGS) or not _strings(target.abilities,ABILITIES) or not target.state is Dictionary: return {"ok":false,"code":"replica_target_data"}
		if not _vector(target.state.get("position"),-512.0,512.0) or target.state.position != paths[target.body_path].pose.slice(9,12): return {"ok":false,"code":"replica_target_position"}
		for key in target.state:
			if key == "position": continue
			if key not in PHYSICAL: return {"ok":false,"code":"replica_target_field"}
			if key == "powered":
				if not target.state[key] is bool: return {"ok":false,"code":"replica_target_powered"}
			elif not _number(target.state[key],-100.0 if key == "temperature" else 0.0,1000.0): return {"ok":false,"code":"replica_target_value"}
	if target_paths.size() != ids.size(): return {"ok":false,"code":"replica_target_set"}
	if event.geometry_digest != _geometry_digest(event.bodies,event.targets): return {"ok":false,"code":"replica_geometry_digest"}
	if JSON.stringify(event,"",true,true).to_utf8_buffer().size() > MAX_BYTES: return {"ok":false,"code":"replica_bytes"}
	return {"ok":true,"code":"replica_valid"}

static func _build(event: Dictionary) -> Dictionary:
	var container := Node3D.new()
	container.name = "CanalReplica"
	var bodies: Dictionary = {}
	var materials: Dictionary = {}
	for row in event.bodies:
		var body := StaticBody3D.new()
		body.name = "Replica_%03d" % bodies.size()
		body.collision_layer = 0
		body.collision_mask = int(row.mask)
		body.set_meta("canal_host_path",row.path)
		if not row.target_id.is_empty():
			body.set_meta("entity_id",row.target_id)
			body.set_meta("target_id",row.target_id)
		var color := Color(float(row.color[0]),float(row.color[1]),float(row.color[2]))
		var material_key := color.to_html(false)
		if not materials.has(material_key):
			var material := StandardMaterial3D.new()
			material.albedo_color = color
			material.roughness = .8
			materials[material_key] = material
		for spec in row.shapes:
			var shape: Shape3D = _shape(spec)
			shape.margin = float(spec.margin)
			var collider := CollisionShape3D.new()
			collider.name = "Shape_%02d" % body.get_child_count()
			collider.shape = shape
			collider.transform = _transform(spec.pose)
			collider.disabled = spec.disabled
			collider.set_meta("canal_host_shape",spec.path)
			body.add_child(collider)
			var view := MeshInstance3D.new()
			view.mesh = _mesh(spec,shape)
			view.transform = collider.transform
			view.material_override = materials[material_key]
			body.add_child(view)
		container.add_child(body)
		bodies[row.path] = body
	return {"ok":true,"container":container,"bodies":bodies}

static func _shape(spec: Dictionary) -> Shape3D:
	match spec.kind:
		"box":
			var shape := BoxShape3D.new(); shape.size = _v3(spec.data); return shape
		"sphere":
			var shape := SphereShape3D.new(); shape.radius = float(spec.data[0]); return shape
		"capsule":
			var shape := CapsuleShape3D.new(); shape.height = float(spec.data[1]); shape.radius = float(spec.data[0]); return shape
		"cylinder":
			var shape := CylinderShape3D.new(); shape.height = float(spec.data[1]); shape.radius = float(spec.data[0]); return shape
	var shape := ConvexPolygonShape3D.new()
	var points := PackedVector3Array()
	for point in spec.data: points.append(_v3(point))
	shape.points = points
	return shape

static func _mesh(spec: Dictionary, shape: Shape3D) -> Mesh:
	match spec.kind:
		"box":
			var mesh := BoxMesh.new(); mesh.size = _v3(spec.data); return mesh
		"sphere":
			var mesh := SphereMesh.new(); mesh.radius = float(spec.data[0]); mesh.height = mesh.radius*2.0; mesh.radial_segments = 12; mesh.rings = 6; return mesh
		"capsule":
			var mesh := CapsuleMesh.new(); mesh.height = float(spec.data[1]); mesh.radius = float(spec.data[0]); mesh.radial_segments = 12; mesh.rings = 4; return mesh
		"cylinder":
			var mesh := CylinderMesh.new(); mesh.height = float(spec.data[1]); mesh.top_radius = float(spec.data[0]); mesh.bottom_radius = mesh.top_radius; mesh.radial_segments = 12; return mesh
	return shape.get_debug_mesh()

static func _color(body: PhysicsBody3D) -> Array:
	for child in body.get_children():
		if child is MeshInstance3D and child.material_override is StandardMaterial3D:
			var color: Color = child.material_override.albedo_color
			return [clampf(color.r,0.0,1.0),clampf(color.g,0.0,1.0),clampf(color.b,0.0,1.0)]
	return [.38,.52,.58]

static func _physical(state: Dictionary) -> Dictionary:
	var result: Dictionary = state.duplicate(true)
	result.position = _v3(state.position)
	if result.has("charge") and result.has("power_threshold"): result.powered = float(result.charge) >= float(result.power_threshold)
	return result

static func _json_numbers(value):
	if value is int or value is float: return float(value)
	if value is Array:
		var result: Array = []
		for item in value: result.append(_json_numbers(item))
		return result
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value: result[key] = _json_numbers(value[key])
		return result
	return value

static func _pose(transform: Transform3D) -> Array:
	return [transform.basis.x.x,transform.basis.x.y,transform.basis.x.z,transform.basis.y.x,transform.basis.y.y,transform.basis.y.z,transform.basis.z.x,transform.basis.z.y,transform.basis.z.z,transform.origin.x,transform.origin.y,transform.origin.z]

static func _transform(value: Array) -> Transform3D:
	return Transform3D(Basis(_v3(value.slice(0,3)),_v3(value.slice(3,6)),_v3(value.slice(6,9))),_v3(value.slice(9,12)))

static func _pose_valid(value) -> bool:
	if not value is Array or value.size() != 12: return false
	for index in range(12):
		if not _number(value[index],-512.0 if index >= 9 else -8.0,512.0 if index >= 9 else 8.0): return false
	var basis: Basis = _transform(value).basis
	if absf(basis.determinant()) < .0001: return false
	for axis in [basis.x,basis.y,basis.z]:
		if axis.length() < .05 or axis.length() > 8.0: return false
	# Shear cannot be reproduced by primitive PhysicsServer shapes.
	return absf(basis.x.normalized().dot(basis.y.normalized())) < .001 and absf(basis.x.normalized().dot(basis.z.normalized())) < .001 and absf(basis.y.normalized().dot(basis.z.normalized())) < .001

static func _convex_volume(points: Array) -> bool:
	var origin: Vector3 = _v3(points[0])
	var line := Vector3.ZERO
	var normal := Vector3.ZERO
	for point in points:
		var offset: Vector3 = _v3(point)-origin
		if line.length_squared() < .00000001:
			if offset.length_squared() > .00000001: line = offset
		elif normal.length_squared() < .00000001:
			if line.cross(offset).length_squared() > .00000001: normal = line.cross(offset).normalized()
		elif absf(normal.dot(offset)) > .0001: return true
	return false

static func _strings(value, allowed: Array) -> bool:
	if not value is Array or value.is_empty() or value.size() > allowed.size(): return false
	var seen: Dictionary = {}
	for item in value:
		if item not in allowed or seen.has(item): return false
		seen[item] = true
	return true

static func _path(value) -> bool:
	if not _text(value,512) or not str(value).begins_with("/root/") or str(value).contains(":") or str(value).contains("//"): return false
	for part in str(value).split("/"):
		if part in [".",".."]: return false
	return not str(value).ends_with("/")

static func _text(value, limit: int) -> bool:
	return value is String and not value.is_empty() and value.length() <= limit and value == value.strip_edges() and not value.contains("\n") and not value.contains("\r")

static func _keys(value, expected: Array) -> bool:
	if not value is Dictionary or value.size() != expected.size(): return false
	for key in expected:
		if not value.has(key): return false
	return true

static func _number(value, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= low and float(value) <= high

static func _integer(value, low: int, high: int) -> bool:
	return _number(value,float(low),float(high)) and float(value) == floor(float(value))

static func _vector(value, low: float, high: float) -> bool:
	if not value is Array or value.size() != 3: return false
	for number in value:
		if not _number(number,low,high): return false
	return true

static func _v3(value: Array) -> Vector3:
	return Vector3(float(value[0]),float(value[1]),float(value[2]))

static func _xyz(value: Vector3) -> Array:
	return [value.x,value.y,value.z]

func _export_no(code: String) -> Dictionary:
	error = code
	return {}

func _no(code: String) -> Dictionary:
	error = code
	return {"ok":false,"code":code,"changed":false}
