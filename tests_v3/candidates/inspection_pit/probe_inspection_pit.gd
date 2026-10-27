extends SceneTree
## Exact physics queries and QA camera poses; not a flown route or final art.
const World=preload("res://scripts/v3/twin_test_world.gd")
const Pit=preload("res://scripts/v3/candidates/inspection_pit/inspection_pit.gd")
const Flight=preload("res://scripts/v2/flight_body.gd")
const Catalog=preload("res://scripts/v2/catalog.gd")
const Capture=preload("res://scripts_tools/v3/capture_hud_visibility.gd")
const Art=preload("res://scripts/v3/candidates/inspection_pit/inspection_pit_art.gd")
const Pilot=preload("res://scripts/v3/candidates/canal_transport_physics/transport_pilot.gd")
var logger=Capture.CaptureLogger.new()
var world: World
var checks: Array=[]
var details: Dictionary={}
var output: String
var done:=false
var with_art:=false
var flown: Array=[]

func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()<1 or args.size()>2 or not args[0].begins_with("--pit-output="):
		quit(2); return
	with_art=args.size()==2 and args[1]=="--with-art-and-flight"
	if args.size()==2 and not with_art: quit(2); return
	output=args[0].trim_prefix("--pit-output=")
	if not output.begins_with("res://artifacts/v3/inspection-pit-") or ".." in output or DirAccess.dir_exists_absolute(output):
		quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	create_timer(180 if with_art else 22).timeout.connect(func():
		if not done: _finish("timeout"))
	world=World.new()
	world.include_inspection_pit=false # This comparison fixture installs its own pit.
	world.include_revetment_closure=false
	root.add_child(world)
	world.build("I2")
	_check(world.build_errors.is_empty(),"real I2 builds",world.build_errors)
	if not world.build_errors.is_empty(): _finish("world"); return
	var states: Array=[world.clinic.snapshot(),world.distribution.snapshot(),world.trial.snapshot(),world.shared_access.snapshot()]
	var ground: StaticBody3D=world.waterfront_install.ground
	var rid: RID=ground.get_rid()
	var pit=Pit.new()
	var installed: Dictionary=pit.install(world.waterfront_install)
	_check(installed.get("ok",false),"real pit installed",{"code":installed.get("code"),"cut_m2":installed.get("cut_m2"),"visible_cut_m2":installed.get("visible_cut_m2")})
	if not installed.get("ok",false): _finish("install"); return
	_check(ground.get_rid()==rid,"same Ground identity")
	_check(states==[world.clinic.snapshot(),world.distribution.snapshot(),world.trial.snapshot(),world.shared_access.snapshot()],"four facility state envelopes unchanged")
	_check(absf(float(installed.cut_m2)-83.125)<.0002 and absf(float(installed.visible_cut_m2)-83.125)<.0002,"visible and physical top independently cut 83.125 square metres")
	var original_shape: ConcavePolygonShape3D=installed.shape
	var repeat: Dictionary=pit.install(world.waterfront_install)
	_check(not repeat.ok and world.waterfront_install.shape_node.shape==original_shape,"duplicate install atomic rejection")
	if with_art:
		var physical_before: PackedVector3Array=original_shape.get_faces()
		var authored: Dictionary=Art.install(installed)
		_check(authored.get("ok",false),"baked editable pit installed in the real I2",{"code":authored.get("code"),"triangles":authored.get("triangles"),"materials":authored.get("materials")})
		if not authored.get("ok",false): _finish("art_install"); return
		_check(ground.get_rid()==rid and original_shape==world.waterfront_install.shape_node.shape and original_shape.get_faces()==physical_before,"art preserves the exact excavated ground collision")
	var geom: Dictionary={"status":"graybox_no_approved_art","unit":"metres","godot_up":"Y","region":[-22,1,8.75,9.5],"parts":{}}
	for part: String in Pit.PARTS:
		var row: Dictionary={"vertices":[],"normals":[],"uv":[]}
		for p: Vector3 in pit.parts[part].faces: row.vertices.append([p.x,p.y,p.z])
		for n: Vector3 in pit.parts[part].normals: row.normals.append([n.x,n.y,n.z])
		for uv: Vector2 in pit.parts[part].uv: row.uv.append([uv.x,uv.y])
		geom.parts[part]=row
	FileAccess.open(output+"/geometry.json",FileAccess.WRITE).store_string(JSON.stringify(geom,"\t"))
	await physics_frame
	await physics_frame
	var space: PhysicsDirectSpaceState3D=world.get_world_3d().direct_space_state
	var exclude: Array[RID]=[]
	for node: Node in world.find_children("*","CollisionObject3D",true,false):
		if node!=ground: exclude.append(node.get_rid())
	var failures: Array=[]
	var samples:=0
	for ix in 17:
		for iz in 19:
			var x: float=-21.85+ix*.5
			var z: float=1.15+iz*.5
			var expected: float=pit.surface_height(x,z)
			var query:=PhysicsRayQueryParameters3D.create(Vector3(x,1,z),Vector3(x,-3,z),1,exclude)
			var hit: Dictionary=space.intersect_ray(query)
			samples+=1
			if hit.is_empty() or hit.collider!=ground or absf(hit.position.y-expected)>.00002: failures.append({"x":x,"z":z,"expected":expected,"actual":hit.get("position")})
	_check(failures.is_empty(),"pit floor coping ramp share physics and surface samples",{"samples":samples,"failures":failures})
	for point: Vector2 in [Vector2(-20,18),Vector2(-12.75,5),Vector2(-17,11.2),Vector2(14.75,10),Vector2(22,10)]:
		var query:=PhysicsRayQueryParameters3D.create(Vector3(point.x,1,point.y),Vector3(point.x,-3,point.y),1,exclude)
		var hit: Dictionary=space.intersect_ray(query)
		var expected: float=-2.8 if point.x==14.75 else 0.0
		_check(not hit.is_empty() and absf(hit.position.y-expected)<.00002,"existing neighbouring support/water bed retained",{"xz":point,"actual":hit.get("position")})
	_check(not world.sample_environment(Vector3(-17,-1.4,2.7)).water,"drained pit is not a new water volume")
	for id: String in ["tr01","hx02"]:
		var resolved: Dictionary=Catalog.resolve_build(Catalog.default_build(id))
		var body:=Flight.new()
		body.configure(resolved)
		body.freeze=true
		body.position=Vector3(-25,10,25)
		world.add_child(body)
		body.set_physics_process(false)
		var shape:=BoxShape3D.new()
		shape.size=Vector3(float(body.stats.width_m),float(body.stats.height_m),float(body.stats.length_m))
		var blocked: Array=[]
		for step in 40:
			var z: float=11.5-step*8.8/39
			var y: float=(0.0 if z>10.5 else pit.surface_height(-19,z))+.85
			for pitch: float in [0.0,.2,-.2]:
				var query:=PhysicsShapeQueryParameters3D.new()
				query.shape=shape
				query.transform=Transform3D(Basis(Vector3.RIGHT,pitch),Vector3(-19,y,z))
				query.collision_mask=1|2|4|8|32
				query.exclude=[body.get_rid()]
				var hits: Array=space.intersect_shape(query,8)
				if not hits.is_empty(): blocked.append({"z":z,"pitch":pitch,"names":hits.map(func(row: Dictionary): return str(row.collider.name))})
		_check(blocked.is_empty(),"full "+id+" pitched box has continuous ramp clearance",{"poses":120,"size":shape.size,"blocked":blocked})
		body.free()
	if DisplayServer.get_name()!="headless":
		root.size=Vector2i(1280,720)
		var camera:=Camera3D.new()
		camera.projection=Camera3D.PROJECTION_ORTHOGONAL
		camera.size=26
		camera.current=true
		world.add_child(camera)
		for row: Array in [["01-yard-default",Vector3(-20,3,18),26.0],["02-pit-default",Vector3(-17,-1.6,2.7),26.0],["03-pit-structure",Vector3(-17.625,-.8,5.75),15.0]]:
			camera.size=float(row[2]); camera.position=row[1]+Vector3(32,39,32); camera.look_at(row[1],Vector3.UP)
			await process_frame
			await RenderingServer.frame_post_draw
			var error:=root.get_texture().get_image().save_png(output+"/"+str(row[0])+".png")
			_check(error==OK,"actual camera capture "+str(row[0]))
	if with_art:
		for id: String in ["tr01","hx02"]:
			if not await _fly_pit(id,pit): _finish("actual_flight"); return
	_finish("")

func _fly_pit(id: String,_pit: RefCounted) -> bool:
	var body:=Flight.new()
	body.name="ActualPitFlight_"+id
	body.configure(Catalog.resolve_build(Catalog.default_build(id)))
	var clearance:=1.5 if id=="hx02" else 1.2
	var low: float=Pit.BOTTOM+clearance
	body.position=Vector3(-19,clearance,11.5)
	body.max_altitude=18
	body.environment_query=world.sample_environment
	body.environment_hazards_authoritative=true
	world.add_child(body)
	body.safe_position=body.global_position
	body.hold_height=body.global_position.y
	body.command={"active":true,"mode":"assisted","body_relative":false,"planar":Vector3.ZERO,"vertical":0.0,"yaw":0.0,"brake":true,"fire":false}
	var pilot=Pilot.new()
	if not pilot.bind(body): return false
	# Cross the lip at yard height before descending. A direct low waypoint
	# from outside rightly swept into the still-solid yard and was rejected.
	# The 1.04m-high HX02 hull needs 1.5m centre clearance at the ramp foot:
	# its rear overhang remains above the slope while braking. TR01 uses 1.2m.
	# Physical hulls and their existing predictive safety margin are unchanged.
	var route: Array[Vector3]=[Vector3(-19,clearance,10.2),Vector3(-19,low,4),Vector3(-19,low,2.7),Vector3(-19,low,4),Vector3(-19,clearance,10.2),Vector3(-19,clearance,11.5)]
	var serial:=0
	var steps: Array=[]
	var lowest:=body.global_position.y
	var health_before: float=body.health
	for target: Vector3 in route:
		serial+=1
		if not pilot.go_to(target,serial): return false
		var arrived:=false
		var report: Dictionary={}
		for frame in 1500:
			await physics_frame
			if done: return false
			report=pilot.tick(1.0/Engine.physics_ticks_per_second,true,false)
			lowest=minf(lowest,body.global_position.y)
			if report.get("arrived",false): arrived=true; break
		steps.append({"target":target,"position":body.global_position,"report":report})
		_check(arrived and body.health==health_before and body.collision_count==0,"actual "+id+" reaches ramp route leg "+str(serial)+" without impact",steps[-1])
		if not arrived or body.health!=health_before or body.collision_count!=0:
			flown.append({"airframe":id,"steps":steps,"lowest_y":lowest}); body.free(); return false
		if serial==3 and DisplayServer.get_name()!="headless":
			var camera:=root.get_camera_3d()
			camera.size=26
			camera.global_position=body.global_position+Vector3(32,39,32)
			camera.look_at(body.global_position,Vector3.UP)
			await process_frame
			await RenderingServer.frame_post_draw
			_check(root.get_texture().get_image().save_png(output+"/04-"+id+"-actual-pit-floor.png")==OK,"actual "+id+" below-yard camera capture")
	_check(lowest<low+.15 and lowest<-.7 and body.global_position.z>11.3,"actual "+id+" enters below yard and flies back out",{"lowest_y":lowest,"clearance_m":clearance,"end":body.global_position,"battery":body.battery})
	flown.append({"airframe":id,"steps":steps,"lowest_y":lowest,"health":body.health,"collisions":body.collision_count})
	body.free()
	return true

func _check(passed: bool,label: String,actual: Variant=null) -> void:
	checks.append({"passed":passed,"label":label,"actual":actual})

func _finish(reason: String) -> void:
	if done: return
	done=true
	if not reason.is_empty(): _check(false,reason)
	var failures: Array=checks.filter(func(row: Dictionary): return not row.passed)
	var result: Dictionary={"checks":checks,"failed":failures.size(),"engine_errors":logger.errors,"flown":flown,"scope":"physical geometry, QA shape poses and actual camera; baked art and actual pilot-driven rigid flight only when with_art_and_flight is true; no human or MAIN claim","with_art_and_flight":with_art}
	FileAccess.open(output+"/result.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("INSPECTION_PIT_RESULT "+JSON.stringify({"checks":checks.size(),"failures":failures,"engine_errors":logger.errors}))
	quit(0 if failures.is_empty() and logger.errors.is_empty() else 1)
