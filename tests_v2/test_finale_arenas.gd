extends SceneTree
## Static scene integration. Independently instantiate every authored finale action;
## do not progress a mission, teleport a live playthrough, or inject any damage.
var failures: Array=[]
var checks=0
var scenes: Array=[]
var scene: Node3D
var world: RegionWorldV2
var pilot: FlightBodyV2
var combat: CombatV2
var runner: TaskRunnerV2
var grid: AStarGrid2D
var space: PhysicsDirectSpaceState3D
var query: PhysicsShapeQueryParameters3D
var cached_edges: Dictionary={}
var cruise=30.0

func _initialize() -> void:call_deferred("run")
func expect(value: bool,label: String) -> void:
	checks+=1
	if not value:failures.append(label);printerr("FINALE_FAIL "+label)

func run() -> void:
	var content=CatalogV2.content()
	var widest=Vector3.ZERO
	for id in CatalogV2.airframes():
		var build=CatalogV2.default_build(str(id));build.slots.utility="reinforced_guard"
		var resolved=CatalogV2.resolve_build(build)
		if resolved.valid and float(resolved.derived.width_m)>widest.x:widest=Vector3(resolved.derived.width_m,resolved.derived.height_m,resolved.derived.length_m)
	query=PhysicsShapeQueryParameters3D.new();var box=BoxShape3D.new();box.size=widest;query.shape=box;query.collision_mask=1|4|32
	for job in content.missions:
		if str(job.id) not in ["M04","M08","M12","M16"]:continue
		var region: Dictionary
		for candidate in content.regions:
			if candidate.id==job.region_id:region=candidate
		await setup(region)
		for stage in job.stages:
			for index in stage.actions.size():await inspect_action(job,stage,index)
		scene.queue_free();await process_frame;await process_frame
	var report={"suite":"finale_arena_integration","checks":checks,"failed":failures.size(),"failures":failures,"scenes":scenes,"envelope_m":vec(widest),"scope":"Actual authored World geometry, TaskRunner per-action scene construction, production combat spawns, actual collider overlaps, max-frame swept routes from each stage service to distinct line-of-fire positions. Separate scene fixtures; no damage injection or forced action completion. Not a full playthrough or GPU evidence."}
	var file=FileAccess.open("res://artifacts/v2/finale_arena_summary.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t",true,true));file.close()
	print("FINALE_SUMMARY "+JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures,"scenes":scenes.size()}))
	quit(0 if failures.is_empty() else 1)

func setup(region: Dictionary) -> void:
	scene=Node3D.new();root.add_child(scene)
	world=RegionWorldV2.new();world.configure(region,false,{});scene.add_child(world);world.set_physics_process(false)
	for x in 6:
		for z in 5:
			if not world.chunks.has(Vector2i(x,z)):world._load_chunk(Vector2i(x,z))
	pilot=FlightBodyV2.new();pilot.configure(CatalogV2.resolve_build(CatalogV2.default_build()));pilot.freeze=true;scene.add_child(pilot);pilot.position=Vector3(20,35,20);pilot.set_physics_process(false)
	combat=CombatV2.new();combat.pilot=pilot;combat.navigation_world=world;combat.auto_fire=false;scene.add_child(combat);combat.set_physics_process(false)
	runner=TaskRunnerV2.new();runner.world=world;runner.pilot=pilot;runner.combat=combat;scene.add_child(runner);runner.set_physics_process(false)
	await physics_frame;await physics_frame
	space=world.get_world_3d().direct_space_state
	grid=AStarGrid2D.new();grid.region=Rect2i(0,0,150,125);grid.cell_size=Vector2(4,4);grid.offset=Vector2(2,2);grid.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES;grid.update()
	for x in 150:
		for z in 125:grid.set_point_solid(Vector2i(x,z),not clear(Vector3(x*4+2,cruise,z*4+2)))
	cached_edges.clear()

func inspect_action(job: Dictionary,stage: Dictionary,index: int) -> void:
	# Resume at an action is a scene-construction fixture, never a victory receipt.
	runner.start_stage(stage,false,{"action_index":index})
	await process_frame;await physics_frame;await physics_frame
	var action=runner.current_action();var label=str(stage.id)+":"+str(index)+":"+str(action.type)
	expect(not runner.pending,label+" actual action initializes")
	var target=runner.target_position()
	var entry_id=str(stage.get("equipment_plan",{}).get("entry_service_poi",world.region.spawn_poi))
	var entry=world.poi_position(entry_id)+Vector3.UP*2.8
	var launch=connect_up(entry)
	expect(not launch.is_empty(),label+" max-frame stage entry has a swept legal ascent "+entry_id)
	var record={"mission":job.id,"stage":stage.id,"action_index":index,"action":action.type,"poi":action.poi_id,"target":vec(target),"entry":entry_id,"phase":combat.boss_phase,"objects":[]}
	if action.type in ["defend","escort"]:
		runner._spawn_wave(action,target)
		for enemy in combat.enemies:enemy.set_physics_process(false)
		await physics_frame;await physics_frame
		expect(runner.action_enemies.size()==action.get("enemy_roles",[]).size(),label+" spawns every authored enemy")
		if is_instance_valid(runner.facility):
			expect(actor_clear(runner.facility).is_empty(),label+" facility actual collider is outside world solid geometry")
		expect(combat.target_nodes.size()==int(action.get("target_nodes",0)),label+" creates every required power node")
		expect(combat.boss_phase==int(action.get("boss_phase",0)),label+" preserves authored boss phase")
		var objects: Array=[];objects.append_array(combat.enemies);objects.append_array(combat.target_nodes)
		for actor in objects:
			var role=str(actor.role) if actor is EnemyActorV22 else "power_node"
			var overlap=actor_clear(actor)
			expect(overlap.is_empty(),label+" "+role+" actual collider has no spawn overlap "+str(overlap))
			expect(actor.global_position.y+actor_half_height(actor)<pilot.max_altitude,label+" "+role+" stays within aircraft altitude ceiling")
			var positions=shoot_positions(actor,launch)
			expect(positions.size()>=3,label+" "+role+" has at least three separated reachable firing bearings")
			record.objects.append({"role":role,"position":vec(actor.global_position),"overlap":overlap,"firing_positions":positions})
		if int(action.get("boss_phase",0))==3:
			expect(combat.boss_spawned and combat.objective_bosses.size()==1 and not combat.objective_complete(),label+" real boss is tracked and cannot finish before defeat")
		if label=="M16-S1:0:defend":
			var node=combat.target_nodes[0]
			var blocker=GameVisuals.collider(world,node.global_position,Vector3(4,8,4))
			await physics_frame;await physics_frame
			expect(not actor_clear(node).is_empty(),"negative control: actual enclosure is detected as node overlap")
			expect(shoot_positions(node,launch).is_empty(),"negative control: enclosed node loses every legal line of fire")
			blocker.queue_free();await process_frame;await physics_frame
	elif int(action.get("boss_phase",0))==2:
		expect(combat.boss_phase==2 and is_instance_valid(combat._safe_ring) and is_instance_valid(combat._sweep_beam),label+" delivery phase instantiates safe ring and sweep")
		expect(connected(launch,connect_up(target)),label+" safe-window target has legal entry route and escape ascent")
	else:
		expect(connected(launch,connect_up(target)),label+" noncombat target connects to entry through actual swept ascent and cruise")
	scenes.append(record)
	print("FINALE_SCENE "+label+" objects="+str(record.objects.size()))

func actor_half_height(actor: CollisionObject3D) -> float:
	var high=0.0
	for shape in actor.find_children("*","CollisionShape3D",true,false):
		if shape.shape is BoxShape3D:high=maxf(high,shape.position.y+shape.shape.size.y*.5)
	return high

func actor_clear(actor: CollisionObject3D) -> Array:
	var blockers: Array=[]
	for shape in actor.find_children("*","CollisionShape3D",true,false):
		if shape.disabled or shape.shape==null:continue
		var q=PhysicsShapeQueryParameters3D.new();q.shape=shape.shape;q.transform=shape.global_transform;q.collision_mask=1|4|32;q.exclude=[actor.get_rid()]
		for hit in space.intersect_shape(q,8):blockers.append(str(hit.collider.get_path()))
	return blockers

func clear(point: Vector3) -> bool:
	query.transform=Transform3D(Basis.IDENTITY,point);query.motion=Vector3.ZERO
	return space.intersect_shape(query,1).is_empty()

func sweep(a: Vector3,b: Vector3) -> bool:
	query.transform=Transform3D(Basis.IDENTITY,a);query.motion=b-a
	var fractions=space.cast_motion(query);query.motion=Vector3.ZERO
	return fractions.size()==2 and fractions[0]>=.99999

func connect_up(point: Vector3) -> Dictionary:
	if point.y>cruise or not clear(point):return {}
	var high=Vector3(point.x,cruise,point.z)
	if not clear(high) or not sweep(point,high):return {}
	var cell=Vector2i(floori(point.x/4),floori(point.z/4))
	for dx in range(-1,2):
		for dz in range(-1,2):
			var candidate=cell+Vector2i(dx,dz)
			if not grid.region.has_point(candidate) or grid.is_point_solid(candidate):continue
			var node=Vector3(candidate.x*4+2,cruise,candidate.y*4+2)
			if clear(node) and sweep(high,node):return {"cell":candidate,"point":point}
	return {}

func connected(a: Dictionary,b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty():return false
	var path=grid.get_id_path(a.cell,b.cell)
	if path.is_empty():return false
	for i in range(1,path.size()):
		var key=str(path[i-1])+":"+str(path[i])
		if not cached_edges.has(key):
			var from=Vector3(path[i-1].x*4+2,cruise,path[i-1].y*4+2);var to=Vector3(path[i].x*4+2,cruise,path[i].y*4+2)
			cached_edges[key]=sweep(from,to)
		if not cached_edges[key]:return false
	return true

func shoot_positions(actor: CollisionObject3D,launch: Dictionary) -> Array:
	var positions: Array=[]
	# Independent 90-degree bearings, actual collision envelopes and LOS. These
	# three proofs need not use the same height or radius; all remain legal flight.
	for direction in 4:
		var angle=float(direction)*PI*.5
		var found=false
		for radius in [8.0,14.0,22.0]:
			if found:break
			for altitude in [actor.global_position.y,6.0,12.0,20.0,29.0]:
				var point=actor.global_position+Vector3(cos(angle)*radius,0,sin(angle)*radius);point.y=maxf(float(altitude),world.surface_height(point)+2.8)
				if point.distance_to(actor.global_position)>35.0 or not clear(point):continue
				if not combat.line_clear(point,actor.global_position,pilot.get_rid(),actor.get_rid()):continue
				if not connected(launch,connect_up(point)):continue
				positions.append(vec(point));found=true;break
	return positions

func vec(p: Vector3) -> Array:return [p.x,p.y,p.z]
