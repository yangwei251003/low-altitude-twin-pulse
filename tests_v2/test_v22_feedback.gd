extends SceneTree
## Presentation contract and real debris physics; not visual/performance evidence.

const Feedback=preload("res://scripts/v2/combat_feedback.gd")
const Damage=preload("res://scripts/v2/damage_model.gd")
var failures:Array=[]
var checks=0
var world:Node3D
var source:FakeCombat
var pilot:FakeAircraft
var enemy:FakeAircraft
var camera:Camera3D
var feedback:CombatFeedbackV22
var visibility_on=true
var shakes=0
var impacts=0

class FakeCombat extends Node3D:
	signal combat_event(event:Dictionary)
	var enemies:Array[Node3D]=[]

class FakeAircraft extends Node3D:
	var damage_state:Dictionary={}
	var entity_id=""
	var role="harasser"
	var model:Node3D
	var telegraph=0.0
	var throttle=.55
	var shield_left=0.0

func _initialize() -> void:call_deferred("run")
func check(value:bool,label:String) -> void:
	checks+=1
	if not value:failures.append(label)
	print("V22_FEEDBACK_","PASS " if value else "FAIL ",label)
func permit(_point:Vector3) -> bool:return visibility_on
func steps(count:int) -> void:
	for i in range(count):await physics_frame
func close(a:float,b:float) -> bool:return absf(a-b)<.00001

func add_body_mesh(aircraft:FakeAircraft,shared_mesh:Mesh) -> MeshInstance3D:
	aircraft.model=Node3D.new();aircraft.add_child(aircraft.model)
	var body=MeshInstance3D.new();body.name="Body";body.mesh=shared_mesh;aircraft.model.add_child(body)
	var rotor=MeshInstance3D.new();rotor.name="Rotor_0";rotor.mesh=shared_mesh;aircraft.model.add_child(rotor)
	return body

func receipt_event(id:int,target:FakeAircraft,amount:float,shield=.6) -> Dictionary:
	var receipt=Damage.resolve(target.damage_state,amount,Vector3(-.55,0,0),Vector3.RIGHT,"pulse",{"shield_multiplier":shield})
	receipt.merge({"kind":"hit","event_id":id,"receipt_id":"unit:"+str(id),"target_id":target.entity_id,"source_id":pilot.entity_id,"position":[target.position.x,target.position.y,target.position.z],"direction":[1,0,0],"friendly":true},true)
	return receipt

func run() -> void:
	world=Node3D.new();root.add_child(world)
	source=FakeCombat.new();world.add_child(source)
	pilot=FakeAircraft.new();pilot.entity_id="pilot-feedback-test";pilot.position=Vector3(-4,2,0);pilot.damage_state=Damage.create_state(100,20,Vector3(1.6,.5,1.4));world.add_child(pilot)
	enemy=FakeAircraft.new();enemy.entity_id="enemy-feedback-test";enemy.position=Vector3(0,2,0);enemy.damage_state=Damage.create_state(100,20,Vector3(1.6,.5,1.4));world.add_child(enemy);source.enemies.append(enemy)
	var shared_material=StandardMaterial3D.new();shared_material.albedo_color=Color(.25,.3,.4)
	var shared_mesh=BoxMesh.new();shared_mesh.material=shared_material
	var enemy_body=add_body_mesh(enemy,shared_mesh)
	camera=Camera3D.new();world.add_child(camera);camera.position=Vector3(0,7,12);camera.look_at(Vector3(0,2,0));camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=20
	feedback=Feedback.new();world.add_child(feedback);feedback.configure(source,pilot,camera,permit,false);feedback.set_process(false)
	feedback.shake_requested.connect(func(_strength,_direction):shakes+=1)
	feedback.wreck_impact.connect(func(_event):impacts+=1)
	await process_frame
	check(source.combat_event.get_connections().size()==1,"Configure has one event subscription")
	feedback.configure(source,pilot,camera,permit,false)
	check(source.combat_event.get_connections().size()==1,"Reconfigure does not duplicate subscription")
	var first=receipt_event(1,enemy,20)
	source.combat_event.emit(first);source.combat_event.emit(first.duplicate(true))
	feedback._process(.08)
	var second=receipt_event(2,enemy,10)
	source.combat_event.emit(second);feedback._process(.09)
	var report=feedback.diagnostics()
	check(report.popups==1,"Same target receipts within 0.16 seconds merge once")
	check(report.duplicates==1,"Repeated receipt is ignored")
	var shown:Dictionary=report.popup_receipts[0]
	check(close(float(shown.damage),float(first.damage)+float(second.damage)),"Popup hull loss equals production DamageModel actual receipts")
	check(close(float(shown.armor),float(first.armor_absorbed)+float(second.armor_absorbed)),"Armor absorption is separate")
	check(close(float(shown.shield),float(first.shield_absorbed)+float(second.shield_absorbed)),"Shield absorption is separate")
	check(shown.parts.has("rotor_left"),"Actual impacted component is retained")
	check(float(shown.damage)<30.0 and float(shown.damage)<float(first.damage)+float(second.damage)+float(first.component_damage),"Raw and component damage never inflate hull number")
	visibility_on=false;feedback._process(.01)
	check(feedback.diagnostics().popups==0,"Revoked visibility immediately removes existing popup")
	source.combat_event.emit(receipt_event(3,enemy,5));feedback._process(.3)
	visibility_on=true;feedback._process(.01)
	check(feedback.diagnostics().popups==0 and feedback.diagnostics().pending==0,"Hidden hits never replay when visibility returns")
	visibility_on=false
	var own=receipt_event(4,pilot,12,1.0);own.friendly=false;own.source_id=enemy.entity_id
	source.combat_event.emit(own)
	check(feedback.diagnostics().own_flash>0,"Player actual damage edge remains visible with hidden source")
	check(shakes==1,"Actual player hull damage requests one bounded shake")
	check(not str(feedback.diagnostics().own_status).is_empty(),"Actual component damage drives player status")
	feedback.reduced_motion=true;source.combat_event.emit(receipt_event(5,pilot,6,1.0))
	check(shakes==1,"Reduced motion disables camera shake")
	visibility_on=true;feedback.reduced_motion=false
	for i in range(700):feedback.on_event({"kind":"shot","event_id":1000+i,"position":[0,2,0],"direction":[0,0,-1],"friendly":true})
	check(feedback.diagnostics().particles<=Feedback.MAX_PARTICLES,"Burst spam stays within 192 particle pool")
	check(feedback.diagnostics().seen<=512,"Event deduplication history remains bounded")
	feedback._process(2)
	check(feedback.diagnostics().particles==0,"Expired particles return to pool")
	feedback.on_event({"kind":"shot","event_id":1900,"position":[0,2,0],"muzzle_position":[4,3,-2],"direction":[0,0,-1],"friendly":true})
	var muzzle_spark=false
	for particle in feedback._particles:
		if bool(particle.active) and str(particle.kind)=="spark":muzzle_spark=particle.position.is_equal_approx(Vector3(4,3,-2))
	check(muzzle_spark,"Shot flash uses actual Muzzle rather than aircraft event center")
	feedback._process(2)
	enemy.telegraph=2.0;feedback._refresh_aircraft()
	await steps(8);feedback._process(.01)
	check(enemy_body.material_overlay is ShaderMaterial,"Visible enemy Body receives one private rim overlay")
	check(enemy_body.mesh==shared_mesh and shared_mesh.material==shared_material and shared_material.albedo_color==Color(.25,.3,.4),"Rim leaves shared mesh and original material unchanged")
	check(enemy.model.get_node("Rotor_0").material_overlay==null,"Rim adds no rotor passes")
	check(enemy_body.material_overlay.render_priority<126 and not Feedback.RIM_SHADER.code.contains("depth_test_disabled"),"Rim retains depth test and stays below existing night veil")
	check(feedback.hud_exclusion_rects().is_empty(),"Non-session visibility callable needs no guessed UI/night context")
	var enemy_key=str(enemy.get_instance_id())
	for layout in [[1280,720,1.0],[1280,720,1.5],[1920,1080,1.25],[1024,768,1.5]]:
		root.size=Vector2i(layout[0],layout[1]);feedback.text_scale=float(layout[2])
		await process_frame
		var view=root.get_visible_rect().size
		enemy.global_position=camera.project_position(Vector2(view.x-24,30),12)
		await steps(8);feedback._process(.01)
		var card=Rect2(Vector2(view.x-280*feedback.text_scale,20),Vector2(260,300)*feedback.text_scale)
		var marker=feedback.warning_marker(enemy,enemy_key,true,view,[card])
		check(not marker.is_empty(),"Visible edge/HUD warning receives safe direction marker "+str(layout))
		if not marker.is_empty():
			check(not card.grow(8*feedback.text_scale).intersects(marker.bounds),"Marker and label clear actual HUD rectangle "+str(layout))
			var bearing=(camera.unproject_position(enemy.global_position+Vector3.UP*.6)-view*.5).normalized()
			check(marker.direction.dot(bearing)>.999,"Safe marker preserves projected bearing without distance label "+str(layout))
		check(feedback.warning_marker(enemy,"unknown",true,view,[card]).is_empty(),"Unregistered identity cannot produce warning marker")
		# Real font metrics, four successive same-target receipts as seen in the
		# playable capture. Include HUD cards and verify the complete two-line area.
		var task_card=Rect2(Vector2(20,20),Vector2(minf(430,view.x*.30),110)*Vector2(1,feedback.text_scale))
		var footer_card=Rect2(Vector2(20,view.y-180*feedback.text_scale),Vector2(minf(550*feedback.text_scale,view.x*.66),160*feedback.text_scale))
		var cards=[task_card,card,footer_card]
		var popup_bounds:Array=[]
		var text_layout=feedback._overlay.popup_text_layout("−8.7  击毁","装甲 1.3 · 左旋翼失效")
		var receipt_snapshot=feedback.diagnostics().popup_receipts
		for popup_number in range(4):
			var placed=feedback.popup_placement(Vector2(42,52),text_layout.size,view,cards,popup_bounds)
			check(not placed.is_empty(),"Four same-target two-line popups fit clear space "+str(layout)+" / "+str(popup_number))
			if placed.is_empty():continue
			var clear=true
			for occupied in cards+popup_bounds:
				if occupied.grow(8*feedback.text_scale-.01).intersects(placed.bounds):clear=false
			check(clear,"Popup footprint clears HUD and previous receipts "+str(layout)+" / "+str(popup_number))
			check(Rect2(Vector2(24,70),view-Vector2(48,140)).encloses(placed.bounds),"Full text and outline remain in safe viewport "+str(layout)+" / "+str(popup_number))
			popup_bounds.append(placed.bounds)
		var near_edge=feedback.popup_placement(view-Vector2(26,72),text_layout.size,view,[],[])
		check(not near_edge.is_empty() and Rect2(Vector2(24,70),view-Vector2(48,140)).encloses(near_edge.bounds),"Long receipt shifts fully inside bottom/right edge "+str(layout))
		check(feedback.popup_placement(Vector2(100,100),text_layout.size,view,[Rect2(Vector2.ZERO,view)],[]).is_empty(),"Fully covered screen has bounded no-placement result "+str(layout))
		check(feedback.diagnostics().popup_receipts==receipt_snapshot,"Layout does not mutate receipt accounting or merge state "+str(layout))
	visibility_on=false;feedback._process(.01)
	check(enemy_body.material_overlay==null,"Illumination revocation immediately removes rim")
	check(feedback.warning_markers(root.get_visible_rect().size,[]).is_empty(),"Dark/unknown enemy produces no edge warning")
	visibility_on=true;feedback.text_scale=1.0;enemy.position=Vector3(0,2,0)
	await steps(8);feedback._process(.01)
	check(feedback.warning_marker(enemy,enemy_key,true,root.get_visible_rect().size,[]).is_empty(),"Unobstructed central warning retains normal in-world feedback")
	enemy.telegraph=0;feedback._refresh_aircraft()
	check(feedback.warning_marker(enemy,enemy_key,true,root.get_visible_rect().size,[Rect2(Vector2.ZERO,root.get_visible_rect().size)]).is_empty(),"Completed telegraph cannot leave an edge warning")
	var wall=StaticBody3D.new();wall.collision_layer=1;world.add_child(wall);wall.position=Vector3(0,4,6)
	var wall_collision=CollisionShape3D.new();var wall_shape=BoxShape3D.new();wall_shape.size=Vector3(8,8,1);wall_collision.shape=wall_shape;wall.add_child(wall_collision)
	await steps(8)
	enemy.telegraph=2.0;feedback._refresh_aircraft();feedback._process(.01)
	check(not feedback.ui_point_visible(enemy.global_position,str(enemy.get_instance_id())),"Orthographic camera wall blocks enemy HUD despite permissive illumination callback")
	check(enemy_body.material_overlay==null,"Camera wall blocks local rim despite permissive illumination")
	var edge_view=root.get_visible_rect().size
	enemy.global_position=camera.project_position(Vector2(edge_view.x-24,30),12)
	wall.global_position=(camera.project_ray_origin(camera.unproject_position(enemy.global_position))+enemy.global_position)*.5
	await steps(8);feedback._process(.01)
	check(feedback.warning_marker(enemy,enemy_key,true,edge_view,[]).is_empty(),"A wall blocks an otherwise eligible edge warning")
	enemy.position=Vector3(0,2,0)
	wall.queue_free();await steps(8)
	feedback._process(.01)
	check(feedback.ui_point_visible(enemy.global_position,str(enemy.get_instance_id())),"Camera HUD visibility returns after wall is removed")
	check(enemy_body.material_overlay is ShaderMaterial,"Rim returns after actual camera wall is removed")
	var extra_aircraft:Array[FakeAircraft]=[]
	var protected_overlay=StandardMaterial3D.new()
	for i in range(10):
		var extra=FakeAircraft.new();extra.entity_id="rim-budget-"+str(i);extra.damage_state=Damage.create_state(30,0,Vector3.ONE);world.add_child(extra);extra.position=Vector3(i*.3,2,-2)
		var extra_body=add_body_mesh(extra,shared_mesh)
		if i==0:extra_body.material_overlay=protected_overlay
		extra.global_position=camera.project_position(edge_view*.5+Vector2.from_angle(float(i)*TAU/10)*edge_view.x,12)
		extra.telegraph=2.0;source.enemies.append(extra);extra_aircraft.append(extra)
	feedback._refresh_aircraft()
	await steps(8);feedback._process(.01)
	check(feedback.diagnostics().rim_slots==Feedback.MAX_RIMS,"Only eight Body rim slots can exist under enemy spam")
	check(extra_aircraft[0].model.get_node("Body").material_overlay==protected_overlay,"Existing per-instance overlay is preserved rather than replaced")
	var markers=feedback.warning_markers(edge_view,[])
	check(not markers.is_empty() and markers.size()<=Feedback.MAX_WARNING_MARKERS,"Visible warning spam is capped at four safe direction markers")
	for extra in extra_aircraft:extra.queue_free()
	await process_frame;await process_frame;feedback._process(.01)
	var floor_body=StaticBody3D.new();floor_body.collision_layer=1;world.add_child(floor_body);floor_body.position=Vector3(0,-.5,0)
	var floor_collision=CollisionShape3D.new();var floor_shape=BoxShape3D.new();floor_shape.size=Vector3(40,1,40);floor_collision.shape=floor_shape;floor_body.add_child(floor_collision)
	for asset in ["enemy_scout","enemy_harasser","enemy_suppressor","enemy_support","weapon_pulse","weapon_burst","weapon_lance","wreck_core","wreck_rotor","wreck_panel"]:
		check(ResourceLoader.exists(Feedback.ASSET_ROOT+asset+".glb"),"Explicit imported asset exists: "+asset)
	feedback.on_event({"kind":"destroyed","event_id":2000,"position":[0,4,0],"velocity":[1,0,0],"heading":.4,"role":"scout","target_id":enemy.entity_id})
	check(feedback.diagnostics().full_wrecks==1,"Destroyed scout retains a complete aircraft hull")
	check(feedback.diagnostics().wrecks==4,"One full hull plus three shared debris pieces")
	var complete:RigidBody3D
	for slot in feedback._wrecks:
		if bool(slot.active):check(slot.body.collision_layer==0 and slot.body.collision_mask==1,"Debris only collides with world, never cargo/player/task targets")
		if bool(slot.active) and bool(slot.full):complete=slot.body
	check(is_instance_valid(complete),"Full wreck is a real RigidBody3D")
	var initial_y=complete.global_position.y if is_instance_valid(complete) else 0.0
	await steps(75);feedback._process(1.25)
	check(is_instance_valid(complete) and complete.global_position.y<initial_y-.5,"Real gravity lowers complete wreck without teleport")
	check(impacts>0,"Real world collision emits wreck impact")
	visibility_on=false;feedback._process(.01)
	check(is_instance_valid(complete) and not complete.visible,"Night permit hides complete physical wreck")
	visibility_on=true
	for i in range(20):feedback.on_event({"kind":"destroyed","event_id":2100+i,"position":[i*.1,4,0],"role":"harasser"})
	check(feedback.diagnostics().wrecks<=12,"Mass destruction stays within 12 physical debris slots")
	feedback._process(8)
	check(feedback.diagnostics().wrecks==0,"Complete wrecks and fragments are reclaimed after lifetime")
	feedback.on_event({"kind":"destroyed","event_id":2500,"entity_kind":"power_node","role":"power_node","position":[0,2,0]})
	check(feedback.diagnostics().full_wrecks==0 and feedback.diagnostics().wrecks==2,"Destroyed power node creates core and panel only, never an aircraft")
	feedback.set_feedback_enabled(false)
	check(not feedback.visible and not feedback._canvas.visible,"Flight/overview lifecycle can suppress all feedback layers")
	check(enemy_body.material_overlay==null and feedback.diagnostics().rim_slots==0,"Overview/disable restores external aircraft materials immediately")
	print("V22_FEEDBACK_REPORT ",JSON.stringify({"ok":failures.is_empty(),"checks":checks,"failures":failures,"scope":"Receipt presentation contracts and actual rigidbody gravity/collision; no graphics, FPS or human comfort claim"}))
	world.queue_free();await process_frame;await process_frame
	quit(0 if failures.is_empty() else 1)
