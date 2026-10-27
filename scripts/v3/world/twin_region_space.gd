extends Node
## A region owns its physics space for its whole online lifetime. The main
## viewport may view that space without moving any region body or joint.
## Does not advance simulation, restore saves, transfer players or own input.
var viewport: SubViewport
var region: Node3D
var world: World3D
var _space := RID()

func mount(content: Node3D) -> Dictionary:
	if is_instance_valid(viewport) or not is_inside_tree() or not is_instance_valid(content) or content.get_parent() != null:
		return {"ok":false,"code":"fresh_detached_region_required"}
	world = World3D.new()
	viewport = SubViewport.new()
	viewport.name = "RegionPhysicsOwner"
	viewport.size = Vector2i(2,2)
	viewport.world_3d = world
	# Rendering is performed only by the normal game viewport. This owner is
	# never a second render pass or a texture which needs input remapping.
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.gui_disable_input = true
	add_child(viewport)
	_space = world.space
	region = content
	viewport.add_child(region)
	return status()

func present_on(destination: Viewport) -> Dictionary:
	if not status().ok or not is_instance_valid(destination) or not destination.is_inside_tree() or destination == viewport or is_ancestor_of(destination):
		return {"ok":false,"code":"live_external_viewport_required"}
	# own_world_3d would silently make a copy; never change a caller's setting.
	if destination.own_world_3d:
		return {"ok":false,"code":"shared_world_viewport_required"}
	destination.world_3d = world
	return {"ok":destination.find_world_3d() == world and world.space == _space,
		"code":"presented","space":_space.get_id()}

func status() -> Dictionary:
	var valid: bool = is_instance_valid(viewport) and is_instance_valid(region) and world != null and viewport.is_inside_tree() and region.get_parent() == viewport and viewport.world_3d == world and world.space == _space and region.get_world_3d() == world
	return {"ok":valid,"code":"stable_region_space" if valid else "region_space_unavailable",
		"space":_space.get_id(),"render_disabled":is_instance_valid(viewport) and viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED}
