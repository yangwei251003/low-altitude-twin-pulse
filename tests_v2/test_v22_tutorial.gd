extends SceneTree

const Director = preload("res://scripts/v2/tutorial_director.gd")
const Hangar = preload("res://scripts/v2/hangar_stage.gd")

class MemoryRepository extends RefCounted:
	var data = {"settings":{},"wallet":{"parts":72},"campaign":{"completed_missions":[]}}
	var transactions: Array = []
	func commit(tx: Dictionary) -> Dictionary:
		transactions.append(tx.duplicate(true))
		data.settings.tutorial_v22 = tx.set["settings.tutorial_v22"].duplicate(true)
		return {"ok":true}

class DummyLegacy extends Node:
	var device = -1
	func binding_label(action: String) -> String: return action

class DummyInput extends Node:
	var source = "keyboard"
	var mode = "assisted"
	var legacy = DummyLegacy.new()
	func _ready() -> void: add_child(legacy)

class DummyAudio extends Node:
	signal voice_started(id: String, text: String)
	var played: Array[String] = []
	func voice_text(id: String) -> String: return "字幕:"+id
	func play_voice(id: String, _interrupt = false) -> bool:
		played.append(id)
		voice_started.emit(id,voice_text(id))
		return true
	func stop_voice() -> void: pass

class DummyWorld extends Node3D:
	var current_wind = Vector3.ZERO

class DummySession extends Node3D:
	var repository = MemoryRepository.new()
	var flight_active = true
	var camera = Camera3D.new()
	var audio = DummyAudio.new()
	var input = DummyInput.new()
	var world = DummyWorld.new()
	func _ready() -> void:
		add_child(camera); add_child(audio); add_child(input); add_child(world)
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 32
	func notify(_text: String) -> void: pass

class DummyPilot extends Node3D:
	var heading = 0.0
	var cargo_items: Dictionary = {}
	var telemetry: Dictionary = {}

class LayoutSession extends "res://scripts/v2/session.gd":
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _physics_process(_delta: float) -> void: pass
	func _notification(_what: int) -> void: pass
	func play_sound(_event: String) -> void: pass
	func list_profiles() -> Array: return [{"id":"test","name":"测试飞行员","active":true,"parts":"∞","completed":0,"kind":"sandbox"}]

var checks = 0
var failures: Array[String] = []
var session: DummySession
var pilot: DummyPilot
var director: Node

func _initialize() -> void: call_deferred("run")

func check(value: bool, text: String) -> void:
	checks += 1
	if not value: failures.append(text); print("V22_TUTORIAL_FAIL ",text)

func tick(seconds: float, position = Vector3(0,3,0), speed = 0.0, axes: Dictionary = {}, held: Array = [], grounded = false, swing = 0.0) -> void:
	for n in range(ceili(seconds*10)):
		pilot.telemetry = {"position_m":position,"velocity_mps":Vector3(speed,0,0),"altitude_agl_m":position.y,"speed_mps":speed,"grounded":grounded,"swing_deg":swing}
		director.physics_update(0.1,pilot,{"axes":axes,"held":held})

func run() -> void:
	session = DummySession.new()
	root.add_child(session)
	pilot = DummyPilot.new()
	session.add_child(pilot)
	director = Director.new()
	session.add_child(director)
	director.configure(session)
	director.start("M01")
	check(director.get_state().step == "lift","M01 starts at lift")
	director.on_ui_action("lift")
	tick(0.5,Vector3(0,0,0))
	check(director.get_state().step == "lift","UI labels cannot fake a flight skill")
	tick(0.5,Vector3(0,3,0),0,{"left_y":0.6})
	check(director.get_state().step == "hover","lift requires positive input and actual altitude")
	tick(2.2)
	check(director.get_state().step == "yaw90","stable airborne hover lasts two seconds")
	tick(0.4,Vector3(0,3,0),0,{"left_x":0.8})
	check(director.get_state().step == "yaw90","yaw input alone does not complete turning")
	pilot.heading = PI/2
	tick(0.2,Vector3(0,3,0),0,{"left_x":0.8})
	check(director.get_state().step == "forward","net 90 degree heading change completes yaw")
	tick(0.5,Vector3(0,3,0),0,{"right_y":0.8})
	tick(0.1,Vector3(0,3,-5),0,{"right_y":0.8})
	check(director.get_state().step == "forward","screen-forward movement is rejected after yaw")
	tick(0.1,Vector3(-4.2,3,0),0,{"right_y":0.8})
	check(director.get_state().step == "strafe","forward is measured in actual aircraft heading")
	tick(0.5,Vector3(-4.2,3,0),0,{"right_x":0.8})
	tick(0.1,Vector3(-4.2,3,-3.2),0,{"right_x":0.8})
	check(director.get_state().step == "brake","body-right lateral displacement completes strafe")
	tick(1,Vector3(-4,3,-3),0,{},["brake"])
	check(director.get_state().step == "brake","stationary brake button cannot bypass braking practice")
	tick(0.2,Vector3(-4,3,-3),3)
	tick(0.9,Vector3(-4,3,-3),0.2,{},["brake"])
	check(director.get_state().step == "land","real movement followed by held braking completes braking")
	tick(0.2,Vector3(-4,3,-3))
	tick(0.8,Vector3(-4,0,-3),0,{},[],true)
	check(director.get_state().step == "zoom","landing requires airborne history and a grounded sample")
	tick(0.1,Vector3(-4,0,-3),0,{},[],true)
	director.on_ui_action("zoom")
	tick(0.1,Vector3(-4,0,-3),0,{},[],true)
	check(director.get_state().step == "zoom","zoom button without changed camera does not complete")
	session.camera.size = 34
	tick(0.1,Vector3(-4,0,-3),0,{},[],true)
	check(director.get_state().status == "completed","actual camera size change completes M01")
	director.auto_start("M01")
	check(not director.get_state().active and director.get_state().status == "completed","automatic launch respects completed course")
	check(session.repository.data.wallet.parts == 72,"tutorial never changes currency")
	check(session.repository.data.campaign.completed_missions.is_empty(),"tutorial never marks campaign completion")
	check(session.audio.played.has("m01_yaw90"),"each tutorial step invokes its Chinese voice ID")
	director.replay("M01")
	check(director.get_state().step == "lift" and director.get_state().replaying,"completed tutorial can replay from first action")
	director.auto_start("M01")
	check(director.get_state().active and director.get_state().replaying,"automatic scene launch preserves explicit replay")
	director.skip()
	check(director.get_state().journal.courses.M01.completed,"skipping replay preserves earlier completion")
	director.auto_start("M01")
	check(not director.get_state().active and director.get_state().status == "skipped","automatic launch respects skip choice")
	director.start("M02")
	tick(0.1)
	pilot.cargo_items["real_load"] = {}
	tick(0.1)
	check(director.get_state().step == "swing","actual cargo attachment completes pickup")
	tick(2.2,Vector3(0,3,0),0.2,{},[],false,20)
	check(director.get_state().step == "swing","excessive swing cannot pass stability")
	tick(2.2,Vector3(0,3,0),0.2,{},[],false,5)
	check(director.get_state().step == "delivery","stable cargo requires two continuous seconds")
	director.on_task_event("delivery",{})
	tick(0.1)
	check(director.get_state().step == "delivery","unconfirmed task event cannot complete delivery")
	director.on_task_event("delivery",{"confirmed":true})
	tick(0.1)
	check(director.get_state().status == "completed","actual delivery completes M02 without requiring wind encounters")
	director.start("M03")
	for event in ["scan","route","cover"]:
		check(director.get_state().step == event,"M03 step sequence "+event)
		director.on_ui_action(event)
		tick(0.1)
		check(director.get_state().step == event,"M03 requires gameplay evidence "+event)
		director.on_task_event(event,{"confirmed":true})
		tick(0.1)
	check(director.get_state().status == "completed","M03 core lessons finish without seeking interference")
	director.replay("M02")
	session.repository.data.settings.environment_wind = 0.0
	director.later()
	check(not director.get_state().active and director.get_state().status == "deferred","later closes the current guide")
	director.auto_start("M02")
	check(not director.get_state().active and director.get_state().status == "deferred","automatic launch respects later choice")
	director.replay("M03")
	director.on_task_event("scan",{"confirmed":true})
	tick(0.1)
	director.configure(session)
	director.auto_start("M03")
	check(director.get_state().active and director.get_state().step == "route" and director.get_state().replaying,"persisted in-progress replay resumes its actual step")
	director.replay("M02")
	tick(0.1)
	pilot.cargo_items["second_load"] = {}
	tick(0.1)
	tick(2.2,Vector3(0,3,0),0.2,{},[],false,4)
	director.on_task_event("delivery",{"confirmed":true})
	tick(0.1)
	check(director.get_state().status == "completed" and director.get_state().count == 3,"disabled environmental effects never block cargo lesson")
	director.replay("M03")
	session.repository.data.settings.environment_interference = 0.0
	for event in ["scan","route","cover"]:
		director.on_task_event(event,{"confirmed":true})
		tick(0.1)
	check(director.get_state().status == "completed" and director.get_state().count == 3,"disabled interference never blocks scan route and cover lesson")
	director.on_task_event("interference",{"confirmed":true})
	check(director.get_state().status == "completed","environment encounters cannot rewrite core lesson completion")
	session.repository.data.settings.tutorial_v22 = {"version":1,"courses":{"M02":{"index":3,"status":"in_progress","completed":false,"skipped_steps":[]},"M03":{"index":3,"status":"in_progress","completed":false,"skipped_steps":["interference"]}}}
	director.configure(session)
	director.auto_start("M02")
	check(director.get_state().status == "completed","legacy journal waiting for wind migrates to core-complete")
	director.auto_start("M03")
	check(director.get_state().status == "completed" and director.get_state().skipped_steps.is_empty(),"legacy interference prerequisite is removed from core learning journal")
	for transaction in session.repository.transactions:
		check(not transaction.has("parts_delta") and transaction.set.keys() == ["settings.tutorial_v22"],"learning writes only the independent tutorial journal")
	var stage = Hangar.new()
	session.add_child(stage)
	stage.configure({"reduced_motion":true})
	var model = FleetVisualsV2.make_drone("tr01",CatalogV2.default_build("tr01").slots)
	stage.mount_preview(model)
	check(model.get_parent() == stage.preview_anchor,"workshop mounts the real FleetVisuals assembly")
	check(model.get_child_count()>0 and str(model.get_child(0).scene_file_path).ends_with("tr01.glb"),"central preview contains the imported aircraft model")
	var start_rotation = model.rotation
	var start_position = stage.preview_anchor.position
	stage.tick(1.0)
	check(model.rotation == start_rotation and stage.preview_anchor.position == start_position,"reduced motion stops both turntable and float")
	stage.set_reduced_motion(false)
	stage.tick(1.0)
	check(model.rotation != start_rotation,"normal workshop mode updates real assembly orientation")
	await verify_layout()
	session.queue_free()
	await process_frame
	print("V22_TUTORIAL_SUMMARY ",JSON.stringify({"checks":checks,"failures":failures,"ok":failures.is_empty(),"scope":"Deterministic tutorial evidence and native UI bounds; not GPU visual, hardware input or comfort evidence."}))
	quit(0 if failures.is_empty() else 1)

func settle() -> void:
	for n in range(5): await process_frame

func verify_layout() -> void:
	root.content_scale_size = Vector2i.ZERO
	var game = LayoutSession.new()
	root.add_child(game)
	game.content = CatalogV2.content()
	game.repository = SaveRepositoryV2.new("user://qa_v22/tutorial_layout_"+str(Time.get_ticks_usec()))
	game.repository.load_profile()
	game.active_build = CatalogV2.default_build()
	game.input = PilotInputV2.new()
	game.add_child(game.input)
	game.phone = PhoneServerV2.new()
	game.add_child(game.phone)
	game.ui = GameInterfaceV2.new()
	game.ui.session = game
	game.add_child(game.ui)
	for dimensions in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(1024,768)]:
		root.size = dimensions
		await settle()
		for scale in [1.0,1.25,1.5]:
			game.ui.apply_scale(scale)
			for page in ["主页","任务","机库","配装","挑战","世界","教学","设置","手机"]:
				game.ui.show_hangar(page)
				await settle()
				var ui = game.ui
				var viewport = Rect2(Vector2.ZERO,ui.root.size).grow(1)
				for card in [ui.lobby_top,ui.lobby_nav,ui.lobby_bottom,ui.lobby_drawer,ui.lobby_home,ui.lobby_tools]:
					if not is_instance_valid(card) or not card.visible: continue
					check(viewport.encloses(card.get_global_rect()),"lobby bounds "+page+" "+str(dimensions)+" "+str(scale)+" "+card.name+" "+str(card.get_global_rect()))
				check(ui.panel.get_node_or_null("WaterfrontMenuArt") == null,"all lobby pages retain actual 3D workshop")
				if is_instance_valid(ui.lobby_drawer):
					var buttons: Array[Button] = []
					collect_buttons(ui.lobby_drawer,buttons)
					for button in buttons:
						var frame = ui.lobby_drawer.get_global_rect().grow(1)
						var bounds = button.get_global_rect()
						check(bounds.position.x >= frame.position.x and bounds.end.x <= frame.end.x,"native button fits drawer "+page+" "+button.text+" "+str(dimensions)+" "+str(scale))
			game.ui.show_briefing(game.content.missions[0])
			await settle()
			check(Rect2(Vector2.ZERO,game.ui.root.size).grow(1).encloses(game.ui.shell_frame.get_global_rect()),"briefing fits viewport "+str(dimensions)+" "+str(scale))
	game.world = RegionWorldV2.new()
	game.world.configure(game.content.regions[0],false,game.repository.data.world)
	game.pilot = FlightBodyV2.new()
	game.pilot.configure(CatalogV2.resolve_build(CatalogV2.default_build()))
	game.pilot.freeze = true
	game.add_child(game.pilot)
	game.current_job = {"id":"explore:R1","name":"实飞教学"}
	game.flight_active = true
	game.tutorial = Director.new()
	game.add_child(game.tutorial)
	game.tutorial.configure(game)
	game.tutorial.start("M01")
	for dimensions in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(1024,768)]:
		root.size = dimensions
		await settle()
		for scale in [1.0,1.25,1.5]:
			game.ui.apply_scale(scale)
			game.ui.show_hud()
			await settle()
			var ui = game.ui
			var viewport = Rect2(Vector2.ZERO,ui.root.size).grow(1)
			for card in [ui.hud_task_panel,ui.hud_control_panel,ui.hud_telemetry_panel,ui.tutorial_panel]:
				check(viewport.encloses(card.get_global_rect()),"tutorial HUD inside viewport "+card.name+" "+str(dimensions)+" "+str(scale))
			check(not ui.tutorial_panel.get_global_rect().intersects(ui.hud_telemetry_panel.get_global_rect()),"tutorial does not cover telemetry "+str(dimensions)+" "+str(scale))
			check(not ui.tutorial_panel.get_global_rect().intersects(ui.hud_control_panel.get_global_rect()),"tutorial does not cover camera controls "+str(dimensions)+" "+str(scale))
	game.world.free()
	game.queue_free()
	await process_frame

func collect_buttons(node: Node, result: Array[Button]) -> void:
	if node is Button: result.append(node)
	for child in node.get_children(): collect_buttons(child,result)
