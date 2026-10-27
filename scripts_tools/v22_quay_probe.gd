extends SceneTree
## Owner-run real-session quay check; no production scene or content edits.
## --v2-qa=<unique> [--capture] [--probe-output=res://artifacts/v22/quay]
var session: GameSessionV2
var capture=false
var output="res://artifacts/v22/quay"
var region_id=""
var checks: Array=[]
var failures: Array=[]
var screenshots: Array=[]
var source_hashes: Dictionary={}
var archived: Dictionary={}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var qa=false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--v2-qa=") and argument.length()>8: qa=true
		elif argument=="--capture": capture=true
		elif argument.begins_with("--probe-output="): output=argument.trim_prefix("--probe-output=").trim_suffix("/")
	if not qa or not OS.is_debug_build() or not output.begins_with("res://artifacts/v22/"):
		push_error("Use a unique --v2-qa profile, debug engine and artifacts/v22 output.");quit(2);return
	if capture and DisplayServer.get_name()=="headless":
		push_error("--capture requires the actual GPU renderer.");quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	for file in ["scripts/v2/region_world.gd","scripts/v2/flight_body.gd","scripts/v2/session.gd","scripts/v2/task_runner.gd","data/v2/world_content.json","docs/v2/data/world_content.json","scripts_tools/v22_quay_probe.gd"]:
		source_hashes[file]=FileAccess.get_sha256("res://"+file)
	var reference=JSON.parse_string(FileAccess.get_file_as_string("res://docs/v2/data/world_content.json"))
	if not reference is Dictionary:
		push_error("Archived authored content is required for coordinate comparison.");quit(2);return
	archived=reference
	session=GameSessionV2.new();root.add_child(session)
	for i in 5: await process_frame
	session.repository.commit({"id":"quay-fixture:"+str(Time.get_ticks_usec()),"set":{"settings.quality":"low","settings.auto_fire":false,"settings.control_mode":"assisted","settings.environment_wind":0.0,"settings.environment_weather":0.0,"settings.environment_interference":0.0,"settings.camera_zoom":24.0},"append":{"campaign.completed_missions":session.content.missions.map(func(item):return item.id)}})
	session.active_build=CatalogV2.default_build("tr01");session.save_build(session.active_build)
	for id in ["R1","R3"]:
		region_id=id
		await _region()
	var changed: Array=[]
	for file in source_hashes:
		if FileAccess.get_sha256("res://"+file)!=source_hashes[file]: changed.append(file)
	_check(changed.is_empty(),"Production/content/probe hashes stayed unchanged",{"changed":changed})
	var report={"schema":1,"ok":failures.is_empty(),"checks":checks,"failures":failures,"screenshots":screenshots,"source_sha256":source_hashes,"renderer":DisplayServer.get_name(),"graphics_evidence":capture,"scope":"Real GameSession R1/R3 streamed foundations, PhysicsServer queries, authored coordinate comparison and real input descent into open canal. Static setup placements and optional production-camera images are not a natural exploration, human comfort or performance test. Offshore decorative ocean outside the flyable quay is not a playable immersion area."}
	var file=FileAccess.open(output+"/report.json",FileAccess.WRITE)
	if file==null: push_error("Cannot write quay report.");quit(2);return
	file.store_string(JSON.stringify(report,"\t"));file.close()
	print("V22_QUAY_REPORT ",JSON.stringify({"ok":failures.is_empty(),"checks":checks.size(),"failures":failures,"report":output+"/report.json"}))
	if is_instance_valid(session.phone): session.phone.stop_server()
	session.queue_free()
	for i in 3: await process_frame
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, label: String, detail: Dictionary={}) -> bool:
	checks.append({"region":region_id,"ok":ok,"label":label,"detail":detail})
	if not ok: failures.append(region_id+": "+label)
	return ok

func _region() -> void:
	if session.flight_active:
		session.show_hangar()
		for i in 3: await process_frame
	session.night=false;session.launch_exploration(region_id)
	if not _check(session.flight_active and session.region_id==region_id,"Actual regional exploration launched"): return
	session.encounter_director.enabled=false
	session.input.take_control("keyboard");session.input.mode="assisted";session.input.test_enabled=true
	session.input.test_frame={"axes":{},"held":["brake"]}
	_place(Vector3(194,2.8,178))
	for i in 4: await physics_frame
	var nearest: Node3D
	var best=INF
	for node in session.world.find_children("CanalQuayFoundation","Node3D",true,false):
		var d=node.global_position.distance_to(Vector3(181,0,169))
		if d<best: nearest=node;best=d
	if not _check(is_instance_valid(nearest),"Loaded local layout contains a real canal foundation",{"requested_neighborhood":[181,169]}): return
	var building=nearest.get_parent() as Node3D
	var original: Dictionary={}
	for obstacle in session.world.obstacles:
		if "Building_%d_%d" % [obstacle.x,obstacle.z]==str(building.name): original=obstacle;break
	_check(not original.is_empty() and building.position.distance_to(Vector3(original.get("x",INF),0,original.get("z",INF)))<.001,"Building remains at its authored layout coordinates",{"building":str(building.name),"position":_v(building.global_position),"requested_building_present":session.world.find_child("Building_181_169",true,false)!=null,"distance_from_requested_neighborhood_m":best})
	_check_foundation(nearest)
	_check_task_coordinates()
	var water=_open_water(building.global_position.z)
	if not _check(water.is_finite(),"Nearby open water outside buildings and bridges has a clear aircraft-sized descent"): return
	var bed=_ray(Vector3(water.x,2,water.z),Vector3(water.x,-3,water.z))
	_check(not bed.is_empty() and absf(float(bed.position.y)+2.2)<.04 and bool(session.world.surface_at(water).get("water",false)),"Open water still exposes the physical river bed",{"position":_v(water),"bed_y":bed.position.y if not bed.is_empty() else null})
	var bridge=Vector3(186,2,roundf(water.z/50.0)*50.0)
	var bridge_hit=_ray(bridge,bridge+Vector3.DOWN*5)
	var land=Vector3(196,2,water.z)
	var land_hit=_ray(land,land+Vector3.DOWN*5)
	_check(not bridge_hit.is_empty() and float(bridge_hit.position.y)>=.27 and not bool(session.world.surface_at(bridge).water),"Road bridge remains solid and dry",{"position":_v(bridge),"height":bridge_hit.position.y if not bridge_hit.is_empty() else null})
	_check(not land_hit.is_empty() and float(land_hit.position.y)>=-.02 and not bool(session.world.surface_at(land).water),"Land outside the canal retains solid dry ground",{"position":_v(land),"height":land_hit.position.y if not land_hit.is_empty() else null})
	for dark in [false,true]:
		session.set_lighting(dark)
		_place(Vector3(194,2.8,building.global_position.z+8))
		var toward=building.global_position-session.pilot.global_position
		session.pilot.heading=atan2(-toward.x,-toward.z)
		session.flight_camera.target_size=24.0;session._snap_camera()
		for i in 4: await process_frame
		if capture: await _capture("night" if dark else "day",str(building.name))
	session.set_lighting(false)
	_place(Vector3(water.x,1.0,water.z))
	for i in 3: await physics_frame
	var contacts: Array=[]
	session.pilot.water_entered.connect(func():contacts.append({"position":_v(session.pilot.global_position),"tick":Engine.get_physics_frames()}))
	session.pilot.freeze=false;session.pilot.sleeping=false
	var descent_start=session.pilot.global_position
	var min_y=descent_start.y
	for i in int(Engine.physics_ticks_per_second*4):
		session.input.test_frame={"axes":{"left_y":-.65},"held":["brake"]}
		await physics_frame
		min_y=minf(min_y,session.pilot.global_position.y)
		if session.pilot.water_contact and not contacts.is_empty(): break
	_check(session.pilot.water_contact and not contacts.is_empty() and min_y<-.37,"Actual flight input can descend into the unobstructed water",{"start":_v(descent_start),"end":_v(session.pilot.global_position),"minimum_y":min_y,"water_receipts":contacts,"health":session.pilot.health})
	session.pilot.freeze=true;session.input.test_frame={"axes":{},"held":[]}

func _check_foundation(foundation: Node3D) -> void:
	var deck: Dictionary={};var beams: Array=[];var piles: Array=[];var excluded: Array[RID]=[]
	for body in foundation.get_children():
		if not body is StaticBody3D: continue
		excluded.append(body.get_rid())
		for shape in body.get_children():
			if not shape is CollisionShape3D or not shape.shape is BoxShape3D: continue
			var box=shape.global_transform*AABB(-shape.shape.size*.5,shape.shape.size)
			var part={"body":body,"box":box}
			if box.size.y>.9: piles.append(part)
			elif box.size.x>1 and box.size.z>1: deck=part
			else: beams.append(part)
	_check(foundation.find_children("*","MeshInstance3D",true,false).size()>=15 and not deck.is_empty() and beams.size()==2 and piles.size()==6,"Foundation has rendered deck, two beams and six physical piles",{"meshes":foundation.find_children("*","MeshInstance3D",true,false).size(),"beams":beams.size(),"piles":piles.size()})
	if deck.is_empty(): return
	var connected=absf(deck.box.end.y)<.01
	var live_piles=0;var water_piles=0;var bed_contacts=0;var bottoms: Array=[]
	for pile in piles:
		var box: AABB=pile.box;var center=box.get_center();bottoms.append(box.position.y)
		var joint=false
		for beam in beams:
			if box.intersects(beam.box) and beam.box.intersects(deck.box): joint=true
		connected=connected and joint and box.position.y<=-2.2
		var sphere=SphereShape3D.new();sphere.radius=.05
		var query=PhysicsShapeQueryParameters3D.new();query.shape=sphere;query.transform=Transform3D(Basis.IDENTITY,center);query.collision_mask=1
		for hit in session.world.get_world_3d().direct_space_state.intersect_shape(query):
			if hit.collider==pile.body: live_piles+=1;break
		if center.x>182 and center.x<190:
			water_piles+=1
			var bed=_ray(Vector3(center.x,-2,center.z),Vector3(center.x,-3,center.z),excluded)
			if not bed.is_empty() and absf(float(bed.position.y)+2.2)<.04 and box.position.y<=float(bed.position.y): bed_contacts+=1
	_check(connected and live_piles==6 and water_piles>0 and bed_contacts==water_piles,"All live piles connect deck/beam to bed; canal-side piles intersect the actual bed",{"pile_bottoms":bottoms,"live_piles":live_piles,"canal_piles":water_piles,"physical_bed_contacts":bed_contacts})

func _open_water(z_near: float) -> Vector3:
	var candidate=Vector3.INF;var best=INF
	var envelope=session.pilot.get_node("Envelope") as CollisionShape3D
	var shape=BoxShape3D.new();shape.size=envelope.shape.size
	for z in range(maxi(8,int(z_near)-65),mini(492,int(z_near)+66),2):
		var point=Vector3(186,1,z)
		if not bool(session.world.surface_at(point).get("water",false)): continue
		var hit=_ray(point+Vector3.UP*18,Vector3(186,-3,z))
		if hit.is_empty() or absf(float(hit.position.y)+2.2)>.04: continue
		var query=PhysicsShapeQueryParameters3D.new();query.shape=shape;query.transform=Transform3D(Basis.IDENTITY,point);query.motion=Vector3(0,-2.3,0);query.collision_mask=1|4|8|32;query.exclude=[session.pilot.get_rid()]
		var result=session.world.get_world_3d().direct_space_state.cast_motion(query)
		if result.size()<2 or result[0]<.999: continue
		if absf(z-z_near)<best: candidate=point;best=absf(z-z_near)
	return candidate

func _check_task_coordinates() -> void:
	var archived_contract=_coordinates(archived)
	var live_contract=_coordinates(session.content)
	_check(archived_contract==live_contract,"Authored POI/mission offsets and relative heights match the original content",{"coordinate_entries":live_contract.size()})
	var runner=TaskRunnerV2.new();runner.world=session.world;runner.pilot=session.pilot
	var mismatch: Array=[];var targets=0
	for bucket in ["missions","airframe_challenges","mode_configs"]:
		for job in session.content.get(bucket,[]):
			if str(job.get("region_id",""))!=region_id: continue
			for stage in job.get("stages",[job]):
				for action in stage.get("actions",[])+stage.get("optional_actions",[]):
					runner.actions=[action];runner.action_index=0
					var actual=runner.target_position();var poi=session.world.poi_index.get(str(action.get("poi_id",session.world.region.spawn_poi)),{})
					var offset=action.get("offset_xz_m",[0,0]);targets+=1
					if poi.is_empty() or Vector2(actual.x,actual.z).distance_to(Vector2(poi.position_xz_m[0]+offset[0],poi.position_xz_m[1]+offset[1]))>.001 or absf(actual.y-session.world.surface_height(actual)-float(action.get("target_height_m",2.8)))>.001: mismatch.append(str(job.id))
	runner.free()
	_check(targets>0 and mismatch.is_empty(),"Real task resolver preserves authored target coordinates",{"targets":targets,"mismatches":mismatch})

func _coordinates(data: Dictionary) -> Dictionary:
	var values: Dictionary={}
	for region in data.regions:
		if str(region.id)==region_id:
			for poi in region.pois: values["poi/"+str(poi.id)]=poi.position_xz_m
	for bucket in ["missions","airframe_challenges","mode_configs"]:
		for job in data.get(bucket,[]):
			if str(job.get("region_id",""))!=region_id: continue
			for stage in job.get("stages",[job]):
				var index=0
				for action in stage.get("actions",[])+stage.get("optional_actions",[]):
					values[bucket+"/"+str(job.id)+"/"+str(stage.get("id",""))+"/"+str(index)]=[action.get("poi_id",""),action.get("offset_xz_m",[0,0]),action.get("target_height_m",2.8)];index+=1
	return values

func _place(point: Vector3) -> void:
	session.pilot.freeze=true;session.pilot.global_position=point
	session.pilot.linear_velocity=Vector3.ZERO;session.pilot.angular_velocity=Vector3.ZERO
	session.pilot.hold_height=point.y;session.pilot.safe_position=point
	session.world.update_stream(point,true);session._snap_camera()

func _ray(from: Vector3, to: Vector3, exclude: Array[RID]=[]) -> Dictionary:
	var query=PhysicsRayQueryParameters3D.create(from,to,1|32,exclude)
	return session.world.get_world_3d().direct_space_state.intersect_ray(query)

func _capture(label: String, building: String) -> void:
	await process_frame
	RenderingServer.viewport_set_update_mode(root.get_viewport_rid(),RenderingServer.VIEWPORT_UPDATE_ALWAYS)
	RenderingServer.force_draw(false)
	var image=root.get_texture().get_image();var path=output+"/"+region_id+"_quay_"+label+".png"
	var status=image.save_png(path);var colors: Dictionary={}
	for x in range(int(image.get_width()*.2),int(image.get_width()*.8),10):
		for y in range(int(image.get_height()*.2),int(image.get_height()*.8),10): colors[image.get_pixel(x,y).to_html(false)]=true
	_check(status==OK and image.get_width()>=640 and colors.size()>=12,"Real production-camera "+label+" close-up rendered",{"unique_colors":colors.size()})
	screenshots.append({"region":region_id,"label":label,"building":building,"path":path,"sha256":FileAccess.get_sha256(path),"camera_size":session.camera.size,"camera_position":_v(session.camera.global_position),"pilot_position":_v(session.pilot.global_position),"native_lighting":true})

static func _v(point: Vector3) -> Array: return [point.x,point.y,point.z]
