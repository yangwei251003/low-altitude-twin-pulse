extends Node
## Candidate region ownership only: no Store, simulation tick, restore or MAIN.
## The World3D exists before the playable enters the tree and is never replaced.
var viewport: SubViewport
var playable: Node3D
var foreground := true
var _world: World3D
var _space := RID()
var _mounted := false
var transitions: Array[Dictionary] = []

func mount(candidate: Node3D) -> Dictionary:
	if _mounted or not is_inside_tree() or not is_instance_valid(candidate) or candidate.get_parent() != null:
		return {"ok":false,"code":"fresh_detached_candidate_and_live_owner_required"}
	_world = World3D.new()
	viewport = SubViewport.new()
	viewport.name = "RetainedI2Viewport"
	viewport.size = Vector2i(1280,720)
	viewport.world_3d = _world
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.gui_disable_input = false
	add_child(viewport)
	_space = _world.space
	playable = candidate
	viewport.add_child(candidate)
	_mounted = true
	return {"ok":candidate.get_world_3d() == _world,"code":"mounted","space":_space.get_id()}

func set_foreground(value: bool) -> Dictionary:
	if not _mounted or not is_instance_valid(playable) or viewport.world_3d != _world or _world.space != _space:
		return {"ok":false,"code":"owner_or_space_changed"}
	var before: Dictionary = identity()
	# Rendering/input routing only. Never remove nodes, change process_mode,
	# freeze actors, close a controller, or transplant a body into another space.
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if value else SubViewport.UPDATE_DISABLED
	viewport.gui_disable_input = not value
	foreground = value
	var after: Dictionary = identity()
	var row: Dictionary = {"foreground":value,"frame":Engine.get_physics_frames(),
		"same_identity":before == after,"body_count":after.bodies.size(),
		"joints":after.joints.duplicate(true),"space":_space.get_id(),
		"render_update_mode":viewport.render_target_update_mode}
	transitions.append(row)
	return {"ok":before == after,"code":"presentation_only","transition":row}

func identity() -> Dictionary:
	var result: Dictionary = {"space":_space.get_id(),"viewport":viewport.get_instance_id(),
		"playable":playable.get_instance_id(),"bodies":{},"joints":{}}
	for node in playable.find_children("*","PhysicsBody3D",true,false):
		var body: PhysicsBody3D = node
		result.bodies[str(playable.get_path_to(body))] = {"instance":body.get_instance_id(),
			"rid":body.get_rid().get_id(),"space":PhysicsServer3D.body_get_space(body.get_rid()).get_id()}
	for node in playable.find_children("*","Joint3D",true,false):
		var joint: Joint3D = node
		result.joints[str(playable.get_path_to(joint))] = {"instance":joint.get_instance_id(),
			"rid":joint.get_rid().get_id(),"a":str(joint.node_a),"b":str(joint.node_b)}
	return result

func space_rid() -> RID:
	return _space

func close() -> void:
	# Only explicit owner disposal ends the scene. Visibility never calls close.
	if is_instance_valid(viewport): viewport.free()
	viewport = null
	playable = null
	_world = null
	_space = RID()
	_mounted = false
