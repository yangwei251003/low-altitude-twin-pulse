extends SceneTree
## Actual RegionWorld collision fixtures. These checks do not complete tasks or certify human flight.
const World=preload("res://scripts/v2/region_world.gd")
const Flight=preload("res://scripts/v2/flight_body.gd")
const Repository=preload("res://scripts/v2/save_repository.gd")
var failures: Array=[]
var details: Array=[]
var checks=0
var world: RegionWorldV2
var scene: Node3D
var pilots: Array=[]
var content: Dictionary
var fixture_root="user://qa_v2/worldui_physics_"+str(Time.get_ticks_usec())

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--worldui-fixture-root="):fixture_root=argument.trim_prefix("--worldui-fixture-root=")
	call_deferred("_run")

func check(ok: bool,label: String, evidence: Dictionary={}) -> void:
	checks+=1
	details.append({"ok":ok,"label":label,"evidence":evidence})
	if not ok:failures.append(label);printerr("WORLDUI_PHYSICS_FAIL "+label+" "+JSON.stringify(evidence))

func _run() -> void:
	content=CatalogV2.content()
	# Missing models can omit rotor bodies while leaving primitive boxes: fail before measuring.
	var assets: Dictionary={"service":true}
	for region in content.regions:
		for item in RegionLayoutWorldUI.get_layout(str(region.id)).get("structures",[]):assets[str(item.asset)]=true
	for asset in assets:
		var path="res://assets/models/worldui/"+str(asset)+".glb"
		var resource=load(path) if ResourceLoader.exists(path) else null
		check(resource is PackedScene,"required imported world model "+str(asset))
	if not failures.is_empty():
		print("WORLDUI_PHYSICS_SUMMARY "+JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures,"blocked":"required GLB resources must be generated and imported first"}))
		quit(1);return
	for region in content.regions:
		await _setup(region)
		_test_six_airframes()
		_test_land_surfaces()
		_test_bridges()
		_test_water()
		await _test_turbines()
		scene.queue_free()
		await process_frame
		await physics_frame
	_test_migration_rewards()
	var report={"suite":"worldui_actual_collision","checks":checks,"failed":failures.size(),"failures":failures,"details":details,"engine":Engine.get_version_info().string,"evidence_scope":"Actual RegionWorld and production terrain/structure/bridge/rotor collision bodies; six production FlightBody envelope shapes at task/workspace samples; physical ray/shape queries. Migration uses isolated profile transactions. No task completion, flight route, GPU appearance, controller or sustained performance claim."}
	DirAccess.make_dir_recursive_absolute(fixture_root)
	var output=fixture_root.path_join("report.json")
	var file=FileAccess.open(output,FileAccess.WRITE)
	if file:file.store_string(JSON.stringify(report,"\t",true,true));file.close()
	print("WORLDUI_PHYSICS_SUMMARY "+JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures,"report":output}))
	quit(0 if failures.is_empty() else 1)

func _setup(region: Dictionary) -> void:
	scene=Node3D.new();root.add_child(scene)
	world=World.new();world.configure(region,false,{"layout_revision":1});scene.add_child(world)
	# Test every authored cell, not just the spawn streaming neighborhood.
	for x in range(6):
		for z in range(5):world._load_chunk(Vector2i(x,z))
	world.set_physics_process(false)
	pilots.clear()
	for index in range(content.airframes.size()):
		var frame=content.airframes[index]
		var pilot=Flight.new()
		pilot.configure(CatalogV2.resolve_build(CatalogV2.default_build(str(frame.id))))
		pilot.freeze=true;pilot.enabled=false;scene.add_child(pilot)
		pilot.global_position=Vector3(20+index*5,60,20)
		pilots.append(pilot)
	await physics_frame
	await physics_frame
	check(world.chunks.size()==30,str(region.id)+" all physical chunks built")
	check(pilots.size()==6,str(region.id)+" six real frame envelopes instantiated")

func _ray(from: Vector3,to: Vector3) -> Dictionary:
	var query=PhysicsRayQueryParameters3D.create(from,to,1|32)
	return world.get_world_3d().direct_space_state.intersect_ray(query)

func _clear(shape: Shape3D,point: Vector3,yaw: float=0) -> bool:
	var query=PhysicsShapeQueryParameters3D.new()
	query.shape=shape;query.transform=Transform3D(Basis(Vector3.UP,yaw),point);query.collision_mask=1|32
	return world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _vec(point: Vector3) -> Array:
	return [point.x,point.y,point.z]

func _test_six_airframes() -> void:
	var targets: Array=[]
	var spawn=world.poi_position(str(world.region.spawn_poi))+Vector3.UP*1.2
	targets.append({"id":"spawn","position":spawn})
	for poi in world.region.pois:
		targets.append({"id":str(poi.id),"position":world.poi_position(str(poi.id))+Vector3.UP*2.8})
	for job in content.missions:
		if str(job.region_id)!=str(world.region.id):continue
		for stage in job.stages:
			for index in range(stage.actions.size()):
				var action=stage.actions[index]
				var point=world.poi_position(str(action.poi_id))
				var offset: Array=action.get("offset_xz_m",[0,0])
				point+=Vector3(float(offset[0]),0,float(offset[1]))
				point.y=world.surface_height(point)+float(action.get("target_height_m",2.8))
				targets.append({"id":str(stage.id)+":"+str(index),"position":point})
	for pilot in pilots:
		var shape: Shape3D=pilot.get_node("Envelope").shape
		var blocked: Array=[]
		for target in targets:
			for yaw in [0.0,PI*.5]:
				if not _clear(shape,target.position,yaw):blocked.append({"target":target.id,"point":_vec(target.position),"yaw":yaw})
		check(blocked.is_empty(),str(world.region.id)+" "+str(pilot.build.airframe_id)+" actual workspace envelope clearance",{"samples":targets.size()*2,"blocked":blocked})
	for item in world.obstacles:
		if str(item.asset) not in ["test_frame","crane"]:continue
		var point=Vector3(float(item.x),float(item.get("base_y",0))+3.0,float(item.z))
		for pilot in pilots:
			check(_clear(pilot.get_node("Envelope").shape,point),str(item.id)+" open portal "+str(pilot.build.airframe_id),{"position":_vec(point)})

func _test_land_surfaces() -> void:
	for land in world.layout.get("land",[]):
		var polygon=RegionLayoutWorldUI.polygon(land.points)
		var candidates: Array=[]
		var average=Vector2.ZERO
		for vertex in polygon:average+=vertex
		average/=polygon.size();candidates.append(average)
		for vertex in polygon:candidates.append(vertex.lerp(average,.4))
		# Shore strips can be narrower than a metre; sample near edges as well.
		for i in range(polygon.size()):
			var edge_mid=(polygon[i]+polygon[(i+1)%polygon.size()])*.5
			for inset in [.002,.005,.01,.02]:candidates.append(edge_mid.lerp(average,inset))
		var checked=false
		for candidate in candidates:
			if not Geometry2D.is_point_in_polygon(candidate,polygon):continue
			var point=Vector3(candidate.x,50,candidate.y)
			var expected=world.surface_at(point)
			# A higher overlapping terrace is a different test; seek this land's own support.
			if absf(float(expected.height)-float(land.height))>.02:continue
			var hit=_ray(point,Vector3(point.x,-4,point.z))
			if not hit.is_empty() and float(hit.position.y)>float(expected.height)+.15:continue
			check(not hit.is_empty() and absf(float(hit.position.y)-float(expected.height))<.08,str(world.region.id)+" physical terrain "+str(land.id),{"query_height":expected.height,"hit":_vec(hit.position) if not hit.is_empty() else []})
			checked=true;break
		check(checked,str(world.region.id)+" terrain sample found "+str(land.id))

func _test_bridges() -> void:
	var tested=0
	for road in world.layout.get("roads",[]):
		if not bool(road.get("bridge",false)):continue
		for index in range(road.points.size()-1):
			var a=road.points[index];var b=road.points[index+1]
			var point=Vector3((float(a[0])+float(b[0]))*.5,(float(a[2])+float(b[2]))*.5,(float(a[1])+float(b[1]))*.5)
			var top=_ray(point+Vector3.UP*2,point+Vector3.DOWN*.8)
			check(not top.is_empty() and absf(float(top.position.y)-point.y)<.08,str(world.region.id)+" bridge physical deck "+str(tested),{"authored":_vec(point),"hit":_vec(top.position) if not top.is_empty() else []})
			var above=world.surface_at(point+Vector3.UP*1.0)
			var below=world.surface_at(point-Vector3.UP*.7)
			check(str(above.material)=="bridge" and float(below.height)<point.y-.4,str(world.region.id)+" bridge query distinguishes above and below "+str(tested),{"above":above.height,"below":below.height})
			var bottom=_ray(point-Vector3.UP*.7,Vector3(point.x,-4,point.z))
			check(not bottom.is_empty() and absf(float(bottom.position.y)-float(below.height))<.08,str(world.region.id)+" below-bridge ray reaches real support "+str(tested))
			for pilot in pilots:
				var shape: BoxShape3D=pilot.get_node("Envelope").shape
				var under=Vector3(point.x,(point.y-.4+float(below.height))*.5,point.z)
				check(_clear(shape,point+Vector3.UP*(shape.size.y*.5+.2)),str(world.region.id)+" bridge top clearance "+str(pilot.build.airframe_id))
				if point.y-.4-float(below.height)>shape.size.y+.5:
					check(_clear(shape,under),str(world.region.id)+" under-bridge clearance "+str(pilot.build.airframe_id))
			tested+=1
	if str(world.region.id)=="R1":check(tested>=2,"R1 both authored bridges physically tested")

func _test_water() -> void:
	if str(world.region.id)=="R2":
		# The authored valley intentionally has a full dry base, not a sea underneath its work floor.
		var point=Vector3(300,30,250)
		check(world.terrain_height(point)>=0 and not bool(world.water_at(point).over_water),"R2 raised/dry ground is not misclassified as water")
		return
	var found=false
	for x in range(25,600,25):
		for z in range(25,500,25):
			var point=Vector3(x,1,z)
			var sample=world.water_at(point)
			if not bool(sample.over_water):continue
			var hit=_ray(point,Vector3(x,-4,z))
			if not hit.is_empty() and absf(float(hit.position.y)+3.0)>.08:continue
			check(not hit.is_empty() and absf(float(hit.position.y)+3.0)<.08,str(world.region.id)+" water has real seabed, no invisible dry platform",{"position":_vec(point),"water_level":sample.height})
			check(absf(float(sample.height)+.6)<.001,str(world.region.id)+" water plane matches authored level")
			found=true;break
		if found:break
	check(found,str(world.region.id)+" sampled genuine water region")

func _blade_shapes(node: Node,result: Array) -> void:
	if node is CollisionShape3D and node.get_parent() is AnimatableBody3D:result.append(node)
	for child in node.get_children():_blade_shapes(child,result)

func _test_turbines() -> void:
	if str(world.region.id)!="R3":return
	check(not world.rotating_turbines.is_empty(),"R3 authored turbines instantiated with actual rotors")
	if world.rotating_turbines.is_empty():return
	var rotor=world.rotating_turbines[0]
	var shapes: Array=[];_blade_shapes(rotor,shapes)
	check(shapes.size()==3,"R3 three physical moving blade colliders")
	for phase in range(2):
		for shape in shapes:
			var point: Vector3=shape.global_position
			var normal: Vector3=shape.global_basis.z.normalized()
			var hit=_ray(point+normal*1.0,point-normal*1.0)
			check(not hit.is_empty() and hit.collider==shape.get_parent(),"R3 blade collision agrees with actual transformed blade phase "+str(phase),{"position":_vec(point)})
		if phase==0:
			var old=rotor.rotation.z
			world._physics_process(1.0)
			await physics_frame
			check(absf(rotor.rotation.z-old)>.2,"R3 rotor animation changes physical hierarchy")

func _test_migration_rewards() -> void:
	var repo=Repository.new(fixture_root.path_join("save_"+str(Time.get_ticks_usec())))
	check(repo.load_profile(),"migration isolated repository loads")
	var legacy=repo.data.world.duplicate(true);legacy.erase("layout_revision")
	var reward_id="campaign:M05:stage:1:first"
	check(repo.commit({"id":reward_id,"parts_delta":160,"append":{"campaign.completed_stages":["M05-S1"]},"set":{"world":legacy}}).ok,"legacy rewarded stage fixture commits")
	var wallet=int(repo.data.wallet.parts)
	check(repo.ensure_layout_revision().ok and int(repo.data.world.layout_revision)==1,"legacy layout migration publishes")
	check(int(repo.data.wallet.parts)==wallet and repo.data.ledger.receipts.count(reward_id)==1,"migration keeps existing wallet and reward receipt")
	var repeated=repo.commit({"id":reward_id,"parts_delta":160,"append":{"campaign.completed_stages":["M05-S1"]}})
	check(repeated.ok and bool(repeated.get("duplicate",false)) and int(repo.data.wallet.parts)==wallet,"replayed pre-migration reward cannot pay twice")
	var generation=int(repo.data.generation)
	check(repo.ensure_layout_revision().ok and int(repo.data.generation)==generation,"migration repetition has no further write")
