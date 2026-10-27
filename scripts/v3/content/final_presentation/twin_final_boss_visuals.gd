extends Node3D
## Six identity silhouettes and exact-target weak-point states.
## Visual children only: no physics, hit tests, timers, input, save or transport.
const SOURCE := "res://data/v3/content/final_presentation/boss_visuals.json"
const META_KEY := "final_boss_visual_components"
const THERMAL := "res://assets/v3/thermal_bypass/thermal_bypass.glb"
const CROWN := "res://assets/v3/crown/parasitic_crown.glb"
const ROOTS := "res://assets/v3/fantasy_kit/photosensitive_roots.glb"
const RELAY := "res://assets/v3/industrial_kit/power_relay_cabinet.glb"
static var _catalog: Dictionary = {}
static var _mesh_pool: Dictionary = {}
static var _material_pool: Dictionary = {}
static var _imported_pieces: Dictionary = {}

var _arena: Node3D
var _region := ""
var _part_views: Dictionary = {}
var _original_meshes: Array = []
var _structure: Node3D
var _dormant: Node3D
var _chassis_art: Node3D
var _last_state_keys: Dictionary = {}

static func decorate(arena: Node3D) -> Dictionary:
	if not is_instance_valid(arena): return {"ok":false,"code":"arena_missing"}
	var previous: Node3D = arena.get_meta(META_KEY) as Node3D if arena.has_meta(META_KEY) else null
	if is_instance_valid(previous):
		return {"ok":true,"code":"visual_components_already_authored","root":previous,"original_meshes":previous._original_meshes.duplicate()}
	var region := str(arena.definition.get("region_id", ""))
	if not _data().get("bosses", {}).has(region): return {"ok":false,"code":"unsupported_identity"}
	var view = new()
	view.name = "FinalBossVisuals"
	view._arena = arena
	view._region = region
	arena.add_child(view)
	arena.set_meta(META_KEY, view)
	view._build()
	view._present({}, [], false)
	return {"ok":true,"code":"visual_components_authored_not_playtested","root":view,
		"original_meshes":view._original_meshes.duplicate(),"target_ids":arena.targets.keys(),
		"identity":str(arena.definition.get("id", "")),"adds_collision":false}

static func apply_view(arena: Node3D, state: Dictionary, open_parts: Array, defeated: bool) -> void:
	if not is_instance_valid(arena): return
	var view: Node3D = arena.get_meta(META_KEY) as Node3D if arena.has_meta(META_KEY) else null
	if is_instance_valid(view): view._present(state, open_parts, defeated)

static func region_material(region: String, role: String = "casing", emissive: bool = false) -> StandardMaterial3D:
	var palette: Dictionary = _data().get("regions", {}).get(region, {})
	var color := str(palette.get(role, "b0bba6"))
	if role == "broken": color = "4d5b53"
	if role == "scar": color = "89765e"
	var key := color + (":lit" if emissive else ":matte")
	if not _material_pool.has(key):
		var material := StandardMaterial3D.new()
		material.resource_name = "TwinPulseFinal_" + region + "_" + role
		material.albedo_color = Color(color)
		material.roughness = .9
		material.metallic = .18 if role == "mirror" else .04
		material.emission_enabled = emissive
		if emissive:
			material.emission = Color(color)
			material.emission_energy_multiplier = .32
		_material_pool[key] = material
	return _material_pool[key] as StandardMaterial3D

static func make_region_badge(region: String) -> Node3D:
	var root := Node3D.new()
	root.name = "RegionIdentityPlate_" + region
	root.set_meta("visual_only", true)
	_shape(root, "box", Vector3.ZERO, Vector3(1.1,.6,.045), region_material(region,"dark"))
	var fantasy := region.begins_with("F")
	var index := maxi(1, int(region.trim_prefix("F").trim_prefix("I")))
	for number in range(index):
		var piece := _shape(root, "cone" if fantasy else "box", Vector3(-.34 + number * .22,0,.04), Vector3(.12,.31,.04), region_material(region,"accent"))
		if fantasy: piece.rotation.z = .28
	_shape(root, "box", Vector3(0,-.23,.035), Vector3(.83,.035,.025), region_material(region,"trim"))
	return root

func _build() -> void:
	_structure = Node3D.new()
	_structure.name = "MatteNonTargetStructure"
	_structure.set_meta("non_target_structure", true)
	add_child(_structure)
	_dormant = Node3D.new()
	_dormant.name = "DormantRemains"
	_dormant.set_meta("only_committed_victory", true)
	_dormant.visible = false
	add_child(_dormant)
	var ordered: Array = _arena.definition.parts.duplicate()
	ordered.append("core")
	for index in range(ordered.size()):
		var part := str(ordered[index])
		var id := str(_arena.target_id(part))
		var body: Node3D = _arena.targets[id]
		for child in body.get_children():
			if child is MeshInstance3D: _original_meshes.append(child)
		var target_view := Node3D.new()
		target_view.name = "FinalTargetVisual"
		target_view.set_meta("original_target_id", id)
		body.add_child(target_view)
		var shell := Node3D.new()
		shell.name = "ClosedShell"
		target_view.add_child(shell)
		var opened := Node3D.new()
		opened.name = "OpenShell"
		target_view.add_child(opened)
		var broken := Node3D.new()
		broken.name = "BrokenShell"
		target_view.add_child(broken)
		var frame := Node3D.new()
		frame.name = "TargetFrame"
		target_view.add_child(frame)
		var weak := Node3D.new()
		weak.name = "ActualWeakPoint"
		target_view.add_child(weak)
		_identity(frame, shell, opened, broken, weak, part, index)
		_part_views[part] = {"root":target_view,"frame":frame,"closed":shell,"open":opened,"broken":broken,"weak":weak}
		var resting: Node3D = broken.duplicate() as Node3D
		resting.name = "Resting_" + part
		_dormant.add_child(resting)
		resting.position = body.position + Vector3(0,-.32,0)
		resting.rotation = Vector3(.08,0,.16 if index % 2 == 0 else -.16)
		resting.visible = true
	_context_structure()
	var stopped_structure: Node3D = _structure.duplicate() as Node3D
	stopped_structure.name = "StoppedSuspension"
	_dormant.add_child(stopped_structure)
	stopped_structure.position.y -= .18
	stopped_structure.visible = true
	if _region == "I3": _crawler_chassis()

func _identity(frame: Node3D, closed: Node3D, opened: Node3D, broken: Node3D, weak: Node3D, part: String, index: int) -> void:
	var is_core := part == "core"
	var radius := 1.1 if is_core else .88
	var casing: Material = region_material(_region,"casing")
	var dark: Material = region_material(_region,"dark")
	var trim: Material = region_material(_region,"trim")
	var accent: Material = region_material(_region,"accent")
	if is_core:
		var district_badge: Node3D = make_region_badge(_region)
		frame.add_child(district_badge)
		district_badge.position = Vector3(0,-.9,-.65)
		district_badge.scale = Vector3.ONE*.55
	match _region:
		"I2":
			var casing_piece: Node3D = _reuse(frame,THERMAL,"StaticHousing",Vector3(0,0,-.45),1.9 if is_core else 1.7,trim)
			if casing_piece != null: casing_piece.rotation.y = PI
			_ring(frame,Vector3(0,0,.2),radius, .1,trim)
			var rotor: Node3D = _reuse(weak,THERMAL,"FanBlades",Vector3(0,0,.33),1.1 if is_core else .9,accent)
			if rotor == null: _spokes(weak,Vector3(0,0,.34),.65,6,accent)
			if is_core:
				for side in [-1.0,1.0]: _shape(frame,"cylinder",Vector3(side*.55,0,-.45),Vector3(.44,1.65,.44),casing)
			_shutters(closed,opened,radius,casing,3)
		"F2":
			var side := -1.0 if part == "true_left_wing" else 1.0
			if is_core:
				_reuse(frame,CROWN,"CoreSeed",Vector3(0,0,-.15),1.9,casing)
				for direction in [-1.0,1.0]:
					var brow := _shape(frame,"cone",Vector3(direction*.42,.65,0),Vector3(.36,.8,.4),trim)
					brow.rotation.z = -direction*.38
			else:
				var wing: Node3D = _reuse(frame,CROWN,"LeafMembrane_-1" if side < 0 else "LeafMembrane_1",Vector3(side*.12,.1,-.1),1.8 if side > 0 else 1.5,region_material(_region,"mirror"))
				if wing != null: wing.rotation.z = side*.38
				for number in range(2 if side < 0 else 3):
					var spar := _shape(frame,"box",Vector3(side*.35,-.4+number*.38,-.14),Vector3(.95,.08,.12),trim)
					spar.rotation.z = side*.3
			_ring(frame,Vector3(0,0,.24),radius,.07,trim)
			_shape(weak,"octa",Vector3(0,0,.32),Vector3(.75,.85,.42),region_material(_region,"mirror"))
			_shutters(closed,opened,radius,casing,3)
		"I3":
			_ring(frame,Vector3(0,0,.1),radius,.12,dark)
			_reuse(frame,THERMAL,"HeatPipes",Vector3(0,-.1,-.25),1.65,accent)
			var fan: Node3D = _reuse(weak,THERMAL,"FanBlades",Vector3(0,0,.2),1.4 if is_core else 1.1,trim)
			if fan != null: fan.rotation.z = .35 if index % 2 else -.35
			for number in range(5): _shape(frame,"box",Vector3(-.65+number*.325,0,-.35),Vector3(.08,1.3,.32),trim)
			_shutters(closed,opened,radius,casing,4)
		"F3":
			_shape(frame,"cylinder",Vector3(0,-.65,-.12),Vector3(.43,.78,.43),region_material(_region,"organic"))
			var cap := _shape(frame,"cone",Vector3(0,.42,-.1),Vector3(1.9 if is_core else 1.65,.7,1.4),casing if is_core else accent)
			cap.rotation.z = -.1 if index % 2 else .1
			_reuse(weak,ROOTS,"Static_Core",Vector3(0,-.05,.28),.8,accent)
			for number in range(5):
				var gill := _shape(frame,"box",Vector3(-.55+number*.275,.15,.23),Vector3(.04,.8,.04),trim)
				gill.rotation.z = -.28+number*.14
			_shutters(closed,opened,.75,casing,3)
			opened.position.y = -.12
		"I4":
			# The cage has two end flanges, never a filled opaque cylinder over
			# the true prism aperture revealed by the original opening logic.
			for side in [-1.0,1.0]:
				var flange := _shape(frame,"cylinder",Vector3(0,side*.83,-.12),Vector3(1.7,.13,1.5),dark)
				flange.rotation.y = PI/6.0
			for number in range(3):
				var angle := float(number)*TAU/3.0
				_shape(frame,"box",Vector3(cos(angle)*.7,0,sin(angle)*.7),Vector3(.12,1.9,.12),trim)
			_shape(weak,"prism",Vector3(0,0,.35),Vector3(.8,1.3,.58),region_material(_region,"mirror"))
			_reuse(frame,RELAY,"Terminal_A" if index % 2 == 0 else "Terminal_B",Vector3(0,-.7,-.3),.48,accent)
			_shutters(closed,opened,radius,casing,3)
		"F4":
			_ring(frame,Vector3(0,0,0),radius,.09,trim)
			if is_core:
				_reuse(weak,CROWN,"CoreSeed",Vector3(0,0,.15),1.45,accent)
				for side in [-1.0,1.0]:
					var brace := _shape(frame,"box",Vector3(side*.68,0,-.15),Vector3(.18,1.85,.18),dark if side < 0 else region_material(_region,"organic"))
					brace.rotation.z = side*.18
			elif part == "charge_return":
				for number in range(3): _ring(weak,Vector3(0,0,-.25+number*.23),.57,.08,accent)
				_shape(frame,"box",Vector3(0,-.65,-.1),Vector3(1.1,.18,.65),dark)
			elif part == "thermal_return":
				_reuse(weak,THERMAL,"FanBlades",Vector3(0,0,.15),1.25,accent)
				for number in range(4): _shape(frame,"box",Vector3(-.5+number*.33,0,-.3),Vector3(.07,1.35,.22),trim)
			else:
				_reuse(weak,ROOTS,"Static_Core",Vector3(0,0,.17),1.05,region_material(_region,"organic"))
				for side in [-1.0,1.0]:
					var leaf := _shape(frame,"cone",Vector3(side*.4,.23,-.12),Vector3(.4,1.1,.28),region_material(_region,"organic"))
					leaf.rotation.z = side*.55
			_shutters(closed,opened,radius,casing,3)
	# Every weak highlight stays centred on the original real hit sphere. The
	# context frame never uses this material or an attackable-looking marker.
	_ring(weak,Vector3(0,0,.55),.47 if is_core else .39,.055,region_material(_region,"signal",true))
	for node in weak.find_children("*","MeshInstance3D",true,false): node.set_meta("weak_surface",true)
	_broken_identity(broken,part,index,radius)

func _shutters(closed: Node3D, opened: Node3D, radius: float, material: Material, blades: int) -> void:
	for index in range(blades):
		var angle := float(index)*TAU/float(blades)
		var direction := Vector3(cos(angle),sin(angle),0)
		var shut := _shape(closed,"box",direction*radius*.23+Vector3(0,0,.61),Vector3(radius*.85,radius*.64,.12),material)
		shut.rotation.z = angle
		var open := _shape(opened,"box",direction*radius*.73+Vector3(0,0,.13),Vector3(radius*.63,radius*.3,.12),material)
		open.rotation = Vector3(.65,0,angle)

func _broken_identity(parent: Node3D, part: String, index: int, radius: float) -> void:
	var dark: Material = region_material(_region,"broken")
	var scar: Material = region_material(_region,"scar")
	_ring(parent,Vector3(0,-.15,0),radius*.82,.1,dark)
	for number in range(3):
		var angle := float(number)*TAU/3.0 + float(index)*.2
		var piece := _shape(parent,"box",Vector3(cos(angle)*radius*.52,sin(angle)*radius*.35-.22,.1),Vector3(radius*.64,.2,.25),dark)
		piece.rotation = Vector3(.28,float(number)*.2,angle+.25)
	_shape(parent,"octa",Vector3(0,-.25,.05),Vector3(.6,.43,.4),scar)
	match _region:
		"I2":
			for side in [-1.0,1.0]: _shape(parent,"cylinder",Vector3(side*.4,-.2,-.15),Vector3(.3,1.1,.3),dark)
		"F2":
			var wing := _shape(parent,"prism",Vector3(.2,-.3,-.1),Vector3(1.35,.38,.7),dark)
			wing.rotation.z = -.18 if part == "true_left_wing" else .18
		"I3":
			for number in range(4):
				var fin := _shape(parent,"box",Vector3(-.48+number*.32,-.25,-.05),Vector3(.08,.8,.42),dark)
				fin.rotation.z = .18
		"F3":
			var cap := _shape(parent,"cone",Vector3(0,.18,-.1),Vector3(1.5,.5,1.2),dark)
			cap.rotation.z = .22
			_shape(parent,"cylinder",Vector3(-.15,-.48,-.1),Vector3(.32,.75,.32),region_material(_region,"organic"))
		"I4":
			var prism := _shape(parent,"prism",Vector3(.1,-.15,0),Vector3(.65,1.05,.5),scar)
			prism.rotation.z = .45
		"F4":
			if part == "living_return" or part == "core":
				_shape(parent,"cone",Vector3(-.2,-.12,-.1),Vector3(.42,.75,.3),region_material(_region,"organic"))
			else: _shape(parent,"cylinder",Vector3(0,-.2,-.1),Vector3(.65,.45,.65),scar)

func _context_structure() -> void:
	var centre: Vector3 = _arena.centre()
	var dark: Material = region_material(_region,"dark")
	var organic: Material = region_material(_region,"organic")
	var core: Node3D = _arena.targets[_arena.target_id("core")]
	for part: String in _arena.definition.parts:
		var body: Node3D = _arena.targets[_arena.target_id(part)]
		var from: Vector3 = body.position+Vector3(0,-.4,-1.2)
		var bend := Vector3(from.x,centre.y-.8,centre.z-1.9)
		var to: Vector3 = core.position+Vector3(0,-.35,-1.25)
		_pipe(_structure,from,bend,.18,organic if _region in ["F3","F4"] else dark)
		_pipe(_structure,bend,to,.18,dark)
	match _region:
		"I2":
			_pipe(_structure,centre+Vector3(-3.1,-1.6,-1.6),centre+Vector3(3.1,-1.6,-1.6),.32,dark)
			for side in [-1.0,1.0]: _shape(_structure,"cylinder",centre+Vector3(side*3.1,-.7,-1.6),Vector3(.58,2.0,.58),dark)
		"F2":
			for side in [-1.0,1.0]:
				var wing_spar := _shape(_structure,"box",centre+Vector3(side*1.5,.15,-1.35),Vector3(2.4,.12,.18),dark)
				wing_spar.rotation.z = side*.2
			_shape(_structure,"cone",centre+Vector3(0,1.4,-.65),Vector3(.45,.8,.7),dark)
		"I3":
			for side in [-1.0,1.0]: _pipe(_structure,centre+Vector3(side*2.4,-2.2,-.6),centre+Vector3(side*2.4,.3,-.6),.22,dark)
		"F3":
			for side in [-1.0,1.0]:
				_pipe(_structure,centre+Vector3(side*5.1,-1.7,-1.8),centre+Vector3(side*1.6,-2,-1.5),.15,organic)
				_pipe(_structure,centre+Vector3(side*1.6,-2,-1.5),centre+Vector3(0,-.2,-1.2),.15,organic)
		"I4":
			_pipe(_structure,centre+Vector3(-3.5,-1.6,-1.7),centre+Vector3(3.5,-1.6,-1.7),.18,dark)
			for side in [-1.0,1.0]:
				var vane := _shape(_structure,"box",centre+Vector3(side*2.1,1.1,-1.5),Vector3(1.1,.18,.8),dark)
				vane.rotation.z = side*.2
		"F4":
			for side in [-1.0,1.0]:
				_pipe(_structure,centre+Vector3(side*4.5,-1.8,-1.5),centre+Vector3(side*1.0,1.8,-1.5),.18,organic if side > 0 else dark)
				_pipe(_structure,centre+Vector3(side*1.0,1.8,-1.5),centre+Vector3(-side*.7,-1.8,-1.5),.15,organic if side > 0 else dark)

func _crawler_chassis() -> void:
	var world: Node = _arena.get_parent()
	var objects: Variant = world.get("objects") if is_instance_valid(world) else null
	if not objects is Dictionary or not objects.has("I3:boss_chassis"): return
	var chassis: Node3D = objects["I3:boss_chassis"]
	for child in chassis.get_children():
		if child is MeshInstance3D: _original_meshes.append(child)
	_chassis_art = Node3D.new()
	_chassis_art.name = "FinalCrawlerTreadBands"
	chassis.add_child(_chassis_art)
	var dark: Material = region_material(_region,"dark")
	var casing: Material = region_material(_region,"casing")
	_shape(_chassis_art,"box",Vector3(0,.06,0),Vector3(7.65,1.05,3.65),casing)
	for side in [-1.0,1.0]:
		_shape(_chassis_art,"box",Vector3(side*3.23,-.15,0),Vector3(.85,.95,3.8),dark)
		for number in range(5):
			var wheel := _shape(_chassis_art,"cylinder",Vector3(side*3.55,-.15,-1.4+number*.7),Vector3(.66,.14,.66),region_material(_region,"trim"))
			wheel.rotation.z = PI/2.0
		for number in range(7): _shape(_chassis_art,"box",Vector3(side*3.25,.35,-1.5+number*.5),Vector3(.92,.12,.28),dark)
	var stopped: Node3D = _chassis_art.duplicate() as Node3D
	stopped.name = "StoppedCrawlerChassis"
	_dormant.add_child(stopped)
	stopped.transform = chassis.transform

func _present(state: Dictionary, open_parts: Array, defeated: bool) -> void:
	if not is_instance_valid(_arena): return
	_structure.visible = not defeated
	_dormant.visible = defeated
	if is_instance_valid(_chassis_art): _chassis_art.visible = not defeated
	for part: String in _part_views:
		var record: Dictionary = _part_views[part]
		var maximum: int = int(_arena.definition.get("core_hp_milli",1)) if part == "core" else int(_arena.definition.get("part_hp_milli",1))
		var hp: int = int(state.get("core_hp_milli",maximum)) if part == "core" else int(state.get("parts",{}).get(part,maximum))
		var opened := part in open_parts and hp > 0 and not defeated
		var broken := hp <= 0
		var key := "%s:%s:%s" % [opened,broken,defeated]
		if str(_last_state_keys.get(part,"")) == key: continue
		_last_state_keys[part] = key
		record.root.visible = not defeated
		record.frame.visible = not broken
		record.closed.visible = not broken and not opened
		record.open.visible = not broken and opened
		record.weak.visible = not broken and opened
		record.broken.visible = broken
		for surface in record.weak.find_children("*","MeshInstance3D",true,false):
			if surface.get_meta("weak_surface",false): surface.material_override = region_material(_region,"signal",true) if opened else region_material(_region,"trim")

static func _reuse(parent: Node3D, path: String, node_name: String, at: Vector3, maximum_extent: float, override_material: Material = null) -> Node3D:
	var key := path+"::"+node_name
	if not _imported_pieces.has(key):
		var packed: PackedScene = load(path) as PackedScene
		if packed == null: return null
		var model: Node3D = packed.instantiate() as Node3D
		var source: MeshInstance3D = model.find_child(node_name,true,false) as MeshInstance3D
		if source == null or source.mesh == null:
			model.free()
			return null
		_imported_pieces[key] = {"mesh":source.mesh,"material":source.material_override}
		model.free()
	var definition: Dictionary = _imported_pieces[key]
	var mesh: Mesh = definition.mesh
	var box: AABB = mesh.get_aabb()
	var divisor := maxf(box.size.x,maxf(box.size.y,box.size.z))
	if divisor < .0001: return null
	var scale_factor := maximum_extent/divisor
	var holder := Node3D.new()
	holder.name = "Reused_"+node_name
	holder.position = at
	holder.set_meta("editable_glb_source",path)
	parent.add_child(holder)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = override_material if override_material != null else definition.material
	instance.position = -box.get_center()*scale_factor
	instance.scale = Vector3.ONE*scale_factor
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(instance)
	return holder

static func _shape(parent: Node3D, kind: String, at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = _mesh(kind)
	instance.position = at
	instance.scale = size
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance

static func _ring(parent: Node3D, at: Vector3, radius: float, thickness: float, material: Material) -> MeshInstance3D:
	var ring := _shape(parent,"ring",at,Vector3(radius*2,thickness*4,radius*2),material)
	ring.rotation.x = PI/2.0
	return ring

static func _spokes(parent: Node3D, at: Vector3, radius: float, count: int, material: Material) -> void:
	for index in range(count):
		var angle := float(index)*TAU/float(count)
		var spoke := _shape(parent,"box",at+Vector3(cos(angle),sin(angle),0)*radius*.45,Vector3(radius,.14,.08),material)
		spoke.rotation.z = angle

static func _pipe(parent: Node3D, from: Vector3, to: Vector3, diameter: float, material: Material) -> void:
	var span := to-from
	if span.length_squared() < .0001: return
	var pipe := _shape(parent,"cylinder",(from+to)*.5,Vector3(diameter,span.length(),diameter),material)
	pipe.basis = Basis(Quaternion(Vector3.UP,span.normalized()))*Basis.from_scale(Vector3(diameter,span.length(),diameter))

static func _mesh(kind: String) -> Mesh:
	if not _mesh_pool.has(kind):
		var mesh: PrimitiveMesh
		match kind:
			"cylinder","cone","prism":
				var cylinder := CylinderMesh.new()
				cylinder.radial_segments = 3 if kind == "prism" else 8
				cylinder.rings = 1
				cylinder.height = 1.0
				cylinder.bottom_radius = .5
				cylinder.top_radius = .035 if kind == "cone" else .5
				mesh = cylinder
			"ring":
				var ring := TorusMesh.new()
				ring.inner_radius = .4
				ring.outer_radius = .5
				ring.rings = 16
				ring.ring_segments = 4
				mesh = ring
			"octa":
				var sphere := SphereMesh.new()
				sphere.radius = .5
				sphere.height = 1.0
				sphere.radial_segments = 6
				sphere.rings = 2
				mesh = sphere
			_:
				var box := BoxMesh.new()
				box.size = Vector3.ONE
				mesh = box
		_mesh_pool[kind] = mesh
	return _mesh_pool[kind] as Mesh

static func _data() -> Dictionary:
	if _catalog.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
		if parsed is Dictionary: _catalog = parsed
	return _catalog
