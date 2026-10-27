class_name TwinClinicGravityArt
extends RefCounted
## Authored static shell only. Hydraulic state, actuators and lamps stay in Works.
## Identity occlusion groups retain all original works-local physical coordinates.
const MODEL_PATH := "res://assets/v3/clinic_gravity/clinic_gravity.glb"
const ORIGIN := Vector3(-9, 6, -7)
const PARTS := {"DeckStructure":2796, "CisternStructure":508,
	"DeckDetails":7820, "CisternDetails":3160, "CisternWindow":12}
const TANK_BODIES := ["CisternFloor", "CisternLeft", "CisternRight", "CisternBack", "CisternWindow"]

static func install(works: Node3D) -> Dictionary:
	if works.is_inside_tree(): return {"ok":false, "code":"gravity_art_before_tree"}
	var packed := load(MODEL_PATH) as PackedScene
	if packed == null: return {"ok":false, "code":"gravity_glb_missing"}
	var model := packed.instantiate() as Node3D
	if model == null: return {"ok":false, "code":"gravity_root_type"}
	var selected: Dictionary = {}
	var triangles := 0
	for part in PARTS:
		var found := model.find_children(part, "MeshInstance3D", true, false)
		if found.size() != 1: return _reject(model, "gravity_part:" + part)
		var mesh: MeshInstance3D = found[0]
		var ancestor: Node = mesh
		while ancestor != null:
			if ancestor is Node3D and not ancestor.transform.is_equal_approx(Transform3D.IDENTITY):
				return _reject(model, "gravity_nonidentity:" + part)
			ancestor = ancestor.get_parent()
		if mesh.mesh == null or mesh.mesh.get_surface_count() != 1:
			return _reject(model, "gravity_surface:" + part)
		var count := int(mesh.mesh.get_faces().size() / 3)
		if count != int(PARTS[part]): return _reject(model, "gravity_geometry:" + part)
		triangles += count
		var material := mesh.get_active_material(0) as BaseMaterial3D
		if material == null: return _reject(model, "gravity_material:" + part)
		if part == "CisternWindow":
			# Godot imports glTF BLEND as alpha with depth prepass. Both preserve
			# the authored translucent window; opaque/scissor are not equivalent.
			if material.transparency not in [BaseMaterial3D.TRANSPARENCY_ALPHA, BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS] or material.albedo_color.a <= 0.0 or material.albedo_color.a >= 1.0:
				return _reject(model, "gravity_glass")
		elif material.albedo_texture == null or material.normal_texture == null or material.roughness_texture == null or material.metallic_texture == null:
			return _reject(model, "gravity_pbr:" + part)
		selected[part] = mesh
	var anchors := model.find_children("SourceWaterBase", "Node3D", true, false)
	if anchors.size() != 1 or not anchors[0].transform.is_equal_approx(Transform3D.IDENTITY):
		return _reject(model, "gravity_water_anchor")
	if model.find_children("*", "MeshInstance3D", true, false).size() != PARTS.size() or not model.find_children("*", "CollisionObject3D", true, false).is_empty() or not model.find_children("*", "Camera3D", true, false).is_empty() or not model.find_children("*", "Light3D", true, false).is_empty():
		return _reject(model, "gravity_export_contract")
	# Check every dependency before mutating the caller. Model failure cannot leave
	# some boxes hidden or add only one of the supplement collision meshes.
	var deck_bodies: Array[StaticBody3D] = []
	var tank_bodies: Array[StaticBody3D] = []
	for id in ["UpperWorkDeck", "ValveWorkPad", "CisternLid", "CisternFillCap", "CisternCappedOutlet"]:
		if not works.fixed_bodies.has(id): return _reject(model, "gravity_layout:" + id)
	for id in works.fixed_bodies:
		if id in ["UpperWorkDeck", "ValveWorkPad"] or str(id).begins_with("GravitySupport") or str(id).begins_with("GravityFoot") or str(id).begins_with("GravityBearing") or str(id).begins_with("GravityLongitudinal"):
			deck_bodies.append(works.fixed_bodies[id])
		elif id in ["CisternLid", "CisternFillCap", "CisternCappedOutlet"]:
			tank_bodies.append(works.fixed_bodies[id])
	if deck_bodies.size() != 16: return _reject(model, "gravity_support_count")
	for name in TANK_BODIES:
		var body := works.get_node_or_null(NodePath(name)) as StaticBody3D
		if body == null: return _reject(model, "gravity_tank_body:" + name)
		tank_bodies.append(body)
	for body in deck_bodies + tank_bodies:
		if body.get_node_or_null("Visual") == null: return _reject(model, "gravity_old_visual")
	var shapes: Dictionary = {}
	for name in ["DeckDetails", "CisternDetails"]:
		var shape: ConcavePolygonShape3D = selected[name].mesh.create_trimesh_shape()
		if shape == null or shape.get_faces().size() != int(PARTS[name]) * 3:
			return _reject(model, "gravity_detail_shape:" + name)
		shape.backface_collision = true
		shapes[name] = shape
	var deck_group := Node3D.new()
	deck_group.name = "GravityDeckCover"
	var tank_group := Node3D.new()
	tank_group.name = "GravityCisternCover"
	works.add_child(deck_group)
	works.add_child(tank_group)
	var deck_visual := Node3D.new()
	deck_visual.name = "AuthoredVisual"
	deck_group.add_child(deck_visual)
	var tank_visual := Node3D.new()
	tank_visual.name = "AuthoredVisual"
	tank_group.add_child(tank_visual)
	# These groups stay identity. Move static bodies without changing their local
	# transform; never reparent an actuator or use the model's offset as a parent.
	for body in deck_bodies: _group_body(body, deck_group)
	for body in tank_bodies: _group_body(body, tank_group)
	var details: Dictionary = {}
	for name in PARTS:
		var mesh: MeshInstance3D = selected[name]
		mesh.owner = null
		mesh.get_parent().remove_child(mesh)
		mesh.position = ORIGIN
		mesh.set_meta("terrain_visibility_single_sided", true)
		var group: Node3D = deck_group if str(name).begins_with("Deck") else tank_group
		if shapes.has(name):
			mesh.set_meta("terrain_visibility_cutaway_detail", true)
			var body := StaticBody3D.new()
			body.name = name + "Collision"
			body.position = ORIGIN
			body.collision_layer = 1
			body.collision_mask = 0
			var collider := CollisionShape3D.new()
			collider.shape = shapes[name]
			body.add_child(collider)
			group.add_child(body)
			details[name] = body
		var visual_parent: Node3D = deck_visual if group == deck_group else tank_visual
		visual_parent.add_child(mesh)
	# Water is runtime-owned, but belongs to this visual cutaway so the opaque
	# fluid cannot become a floating blue blocker when the enclosure fades.
	for water in [works.water_surfaces["I2:clean_cistern"], works.water_volumes["I2:clean_cistern"]]:
		water.get_parent().remove_child(water)
		tank_group.add_child(water)
		water.set_meta("terrain_visibility_cutaway_detail", true)
	model.free()
	return {"ok":true, "code":"gravity_art_installed", "path":MODEL_PATH,
		"triangles":triangles, "surfaces":5, "occluders":[deck_group, tank_group], "detail_bodies":details}

static func _group_body(body: StaticBody3D, group: Node3D) -> void:
	body.get_node("Visual").hide()
	body.get_parent().remove_child(body)
	group.add_child(body)

static func _reject(model: Node3D, code: String) -> Dictionary:
	model.free()
	return {"ok":false, "code":code}
