extends SceneTree

var failures: Array[String] = []
var checks = 0

func _initialize() -> void: call_deferred("_run")

func _expect(value: bool, label: String) -> void:
	checks+=1
	if not value: failures.append(label)

func _run() -> void:
	var region = CatalogV2.content().regions[0]
	var world = RegionWorldV2.new()
	world.configure(region,false,{})
	root.add_child(world)
	world.update_stream(Vector3(0,3,75),true)
	await physics_frame
	await physics_frame
	var space = world.get_world_3d().direct_space_state
	for z in [18.0,27.0,42.0,68.0,77.0,92.0]:
		var ray = PhysicsRayQueryParameters3D.create(Vector3(-8,3,z),Vector3(4,3,z),1)
		_expect(space.intersect_ray(ray).is_empty(),"Peripheral road is clear across old x=0 boundary at "+str(z))
		var fence = PhysicsRayQueryParameters3D.create(Vector3(-10,3,z),Vector3(-20,3,z),1)
		var hit = space.intersect_ray(fence)
		_expect(not hit.is_empty() and absf(hit.position.x+16)<0.1,"Visible perimeter aligns to physical fence")
	_expect(world.visibility_occluders.size()>4,"Independent modeled structures register for fading")
	_expect(not world.district_panels.is_empty(),"Street guide-light interaction exists")
	var pilot = FlightBodyV2.new()
	pilot.configure(CatalogV2.resolve_build(CatalogV2.default_build()))
	world.add_child(pilot)
	pilot.freeze = true
	if not world.district_panels.is_empty():
		var station = world.district_panels[0]
		pilot.global_position=station.global_position+Vector3.UP
		pilot.command={"interact":false}; world.work_scenery(pilot,.1)
		_expect(not world.scenery_hint.is_empty(),"Nearby scenery explains interaction")
		pilot.command={"interact":true}; world.work_scenery(pilot,.1)
		_expect(station.get_meta("guide_on",false),"F activates landing guidance")
		world.work_scenery(pilot,1)
		_expect(station.get_meta("guide_on",false),"Holding F does not repeatedly toggle")
		pilot.command={"interact":false}; world.work_scenery(pilot,1)
		pilot.command={"interact":true}; world.work_scenery(pilot,.1)
		_expect(not station.get_meta("guide_on",false),"Second press switches guidance off")
	for id in ["office_pavilion","waterfront_cafe","harbor_warehouse","bus_stop","street_lamp","car_sedan","street_tree"]:
		_expect(ResourceLoader.exists("res://assets/v2/streets/"+id+".glb"),"Imported model: "+id)
		var model = StreetDressingV2.prop(world,id,Vector3(400,0,400))
		_check_colors(model)
	pilot.queue_free(); world.queue_free()
	await process_frame; await process_frame
	print("V2_ART_WORLD_SUMMARY ",JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)

func _check_colors(node: Node) -> void:
	if node is MeshInstance3D:
		for index in node.mesh.get_surface_count():
			var colors = node.mesh.surface_get_arrays(index)[Mesh.ARRAY_COLOR]
			if colors != null and not colors.is_empty():
				var material = node.get_active_material(index)
				_expect(material is BaseMaterial3D and material.vertex_color_use_as_albedo,"Imported authored colors enabled: "+str(node.name))
	for child in node.get_children(): _check_colors(child)
