extends SceneTree
## Native Button.pressed callbacks and actual Session/UI, with temporary profile storage.
## A controlled UI fixture: not pointer/controller hardware, manual flight or GPU evidence.

class IsolatedSession:
	extends "res://scripts/v2/session.gd"
	var fixture_path = ""
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		qa_mode = true
		content = CatalogV2.content()
		profiles = ProfileCatalogV22.new(fixture_path+"/profiles",fixture_path+"/nonexistent_legacy_source")
		profiles.initialize()
		repository = profiles.open_profile("default")
		repository.commit({"id":"ui-smoke:init","set":{"settings.fullscreen":false,"settings.mute":true,"settings.auto_fire":false}})
		active_build = selected_build()
		selected_frame = str(active_build.airframe_id)
		input = PilotInputV2.new()
		add_child(input)
		input.configure_input(repository.data.settings.get("input",{}))
		input.pause_requested.connect(func(reason): pause_game(reason))
		phone = PhoneServerV2.new()
		add_child(phone)
		phone.status_changed.connect(_phone_changed)
		_setup_view()
		ui = GameInterfaceV2.new()
		ui.session = self
		add_child(ui)
		if ResourceLoader.exists("res://scripts/v2/tutorial_director.gd"):
			tutorial = load("res://scripts/v2/tutorial_director.gd").new()
			add_child(tutorial)
			tutorial.configure(self)
		apply_settings()
		show_hangar()

var game: IsolatedSession
var fixture_root = ""
var checks = 0
var failures: Array[String] = []

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--status-root="): fixture_root=argument.trim_prefix("--status-root=").replace("\\","/")
	if DisplayServer.get_name() != "headless" or fixture_root.is_empty() or not fixture_root.is_absolute_path() or DirAccess.dir_exists_absolute(fixture_root):
		printerr("Requires headless and a fresh absolute --status-root=<temporary directory>.")
		quit(2); return
	call_deferred("run")

func check(value: bool, description: String) -> void:
	checks+=1
	if not value: failures.append(description); print("WORLDUI_STATUS_FAIL ",description)

func settle(frames = 6) -> void:
	for tick in frames: await process_frame

func click_tag(id: String) -> void:
	var button: Variant = game.ui.action_controls.get(id)
	check(button is Button and button.is_visible_in_tree() and not button.disabled,"Native actionable button "+id)
	if not button is Button: return
	button.pressed.emit()
	await settle()

func labels(node: Node) -> String:
	var text = node.text+"\n" if node is Label else ""
	for child in node.get_children(): text+=labels(child)
	return text

func progress_snapshot() -> String:
	var d: Dictionary=game.repository.data
	return JSON.stringify({"campaign":d.campaign,"wallet":d.wallet,"records":d.records,"owned_modules":d.owned_modules,"world":d.world})

func run() -> void:
	root.content_scale_size=Vector2i.ZERO
	root.size=Vector2i(1280,720)
	game=IsolatedSession.new();game.fixture_path=fixture_root;root.add_child(game)
	await settle()
	var initial=game.ui._departure_context(true)
	check(initial.action=="教学起飞 →" and initial.job.id=="M01","New player main action uses the real M01 teaching route")
	check(root.gui_get_focus_owner()==game.ui.action_controls.departure,"Departure receives first primary focus")
	var status=game.ui._region_status("R1")
	check(int(status.completed)==0 and int(status.total)==4,"Region uses real 0/4 mission completion")
	check(str(game.ui._region_status("R2").state).contains("M04"),"Locked card names concrete unlock mission")
	var wrong_build=CatalogV2.default_build("tr01")
	wrong_build.slots.tool="scan_base"
	var first_stages: Array = []
	for stage in game.get_job("M01").stages: first_stages.append(stage.id)
	var setup=game.repository.commit({"id":"status-fixture:wrong-tool","set":{"builds":[wrong_build],"selected_build_id":wrong_build.build_id,"campaign.completed_missions":["M01"],"campaign.completed_stages":first_stages},"append":{"owned_modules":["hook_base"]}})
	check(bool(setup.get("ok",false)),"Validated wrong-tool fixture")
	game.ui.show_hangar("任务");await settle()
	status=game.ui._region_status("R1")
	check(bool(status.missing) and str(status.tools).contains("需准备"),"Card exposes actual missing equipment")
	await click_tag("region_tools_R1")
	check(str(game.ui.prepared_job.get("id",""))=="M02" and game.ui.screen_mode=="modal","Missing-tool remedy opens actual mission preflight")
	var completed: Array=[]
	for id in ["M01","M02"]:
		for stage in game.get_job(id).stages: completed.append(stage.id)
	completed.append("M03-S1")
	var cp={"layout_revision":1,"job_id":"M03","stage_index":1,"run_id":"status-formal-M03","seconds":32.5,"repeat":false,"night":false}
	setup=game.repository.commit({"id":"status-fixture:checkpoint","set":{"campaign.completed_missions":["M01","M02"],"campaign.completed_stages":completed,"campaign.active_checkpoint":cp}})
	check(bool(setup.get("ok",false)),"Validated different-stage checkpoint fixture")
	game.region_id="R4"
	for dimensions in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(1024,768)]:
		root.size=dimensions
		for scale in [1.0,1.25,1.5]:
			game.ui.apply_scale(scale);game.ui.show_hangar("主页");await settle()
			var context=game.ui._departure_context(true)
			check(bool(context.resume) and context.job.id=="M03" and context.action=="继续任务 →","Homepage prioritizes actual checkpoint across selected regions")
			check(str(context.objective).contains(str(game.get_job("M03").stages[1].name)),"Home summary names actual checkpoint stage")
			var screen=Rect2(Vector2.ZERO,game.ui.root.size).grow(1)
			for panel in [game.ui.lobby_top,game.ui.lobby_nav,game.ui.lobby_home,game.ui.lobby_bottom]: check(screen.encloses(panel.get_global_rect()),"Responsive summary card fits "+str(dimensions)+" "+str(scale))
			check(not game.ui.lobby_home.get_global_rect().intersects(game.ui.lobby_bottom.get_global_rect()),"Summary and departure do not overlap")
	await click_tag("departure")
	check(game.ui.prepared_job.id=="M03" and not game.flight_active,"Continue opens checkpoint briefing before flight")
	await click_tag("launch")
	check(game.flight_active and game.stage_index==1 and game.run_id=="status-formal-M03","Checkpoint primary action resumes actual saved stage/run")
	game.pilot.freeze=true
	for dimensions in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(1024,768)]:
		root.size=dimensions
		for scale in [1.0,1.25,1.5]:
			game.ui.apply_scale(scale);game.ui.show_hud();game.ui.update_hud();await settle()
			var overlay=game.ui.hud_overlay
			var font=overlay.get_theme_default_font()
			var extent=font.get_string_size("服务柜 999m",HORIZONTAL_ALIGNMENT_LEFT,-1,roundi(14*scale))
			for projected in [Vector2(-200,0),Vector2(-200,900),Vector2(2200,0),Vector2(2200,900),Vector2(2200,400),Vector2(500,-500),Vector2(500,1800)]:
				var placement=overlay.service_marker_placement(projected,extent)
				var label_rect=Rect2(placement.label_position,extent)
				check(Rect2(Vector2.ZERO,overlay.size).encloses(label_rect),"Whole service distance label stays within viewport")
				for card in [game.ui.hud_task_panel,game.ui.hud_control_panel,game.ui.hud_telemetry_panel,game.ui.tutorial_panel]:
					if is_instance_valid(card) and card.is_visible_in_tree(): check(not card.get_global_rect().intersects(label_rect),"Service label avoids visible HUD card")
	game.guide_to_service()
	check(not game.service_navigation_id.is_empty() and game.waypoint.is_finite(),"Guidance creates a real known service waypoint")
	game.clear_service_guidance()
	check(game.service_navigation_id.is_empty() and not game.waypoint.is_finite() and not is_instance_valid(game.waypoint_marker),"Service guidance clears its own marker and waypoint")
	game.guide_to_service()
	game.set_waypoint(Vector3(50,0,50))
	game.clear_service_guidance()
	check(game.service_navigation_id.is_empty() and game.waypoint.is_finite(),"Manual navigation replaces service guidance and is not erased")
	game.show_hangar();await settle()
	# Explicit transaction/event fixture. These calls test result presentation;
	# they do not claim the mission was flown or combat objectives achieved.
	completed.clear()
	for id in ["M01","M02","M03"]:
		for stage in game.get_job(id).stages: completed.append(stage.id)
	setup=game.repository.commit({"id":"status-fixture:unlock-M04","set":{"campaign.completed_missions":["M01","M02","M03"],"campaign.completed_stages":completed,"campaign.active_checkpoint":null}})
	check(bool(setup.get("ok",false)),"Validated final mission presentation fixture")
	game.launch_job("M04");await settle();game.pilot.freeze=true
	game._stage_complete(game.current_job.stages[0]);await settle()
	game.fail_run("Result presentation failure fixture");await settle()
	var result=game.result_progress_summary()
	check(result.stages.size()==1 and result.new_regions.is_empty() and str(result.status).begins_with("未完成目标"),"Failure lists only actually committed stages and no fictitious unlock")
	check(labels(game.ui.panel).contains(str(game.current_job.stages[0].name)),"Failure result renders committed stage name")
	game.retry_current_run();await settle();game.pilot.freeze=true
	for ignored in 2: game._stage_complete(game.current_job.stages[game.stage_index]);await settle()
	result=game.result_progress_summary()
	check(game.run_result_success and result.stages.size()==2 and result.new_regions==[str(game.get_region("R2").name)],"Final transaction shows this sortie's stages and newly unlocked R2")
	check(str(result.saved_progress)=="正式修复进度 3 / 3 阶段","Result reports actual persisted campaign stage count")
	check(labels(game.ui.panel).contains("新开放航区："+str(game.get_region("R2").name)),"Result renders real new region")
	game.show_hangar();await settle()
	check(int(game.ui._region_status("R1").completed)==4 and str(game.ui._region_status("R1").state).contains("全部修复"),"Finished region distinguishes 4/4 completion from no-task state")
	var before=progress_snapshot()
	game.launch_tutorial_practice("M01");await settle();game.pilot.freeze=true
	for ignored in 3: game._stage_complete(game.current_job.stages[game.stage_index]);await settle()
	result=game.result_progress_summary()
	check(bool(result.practice) and result.stages.size()==3 and result.new_regions.is_empty(),"Practice result lists practice stages without unlocks")
	check(game.run_parts==0 and progress_snapshot()==before,"Practice summary does not award currency or mutate formal progress")
	game.show_hangar();await settle()
	game.launch_job("M04");await settle();game.pilot.freeze=true
	for ignored in 3: game._stage_complete(game.current_job.stages[game.stage_index]);await settle()
	result=game.result_progress_summary()
	check(result.stages.size()==3 and result.new_regions.is_empty(),"Replay lists this run's stages without announcing old unlocks")
	print("WORLDUI_STATUS_SUMMARY ",JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures,"scope":"Headless actual UI callbacks and result/save event fixtures. No native pointer/controller, completed gameplay, GPU visual-quality or performance claim.","fixture_root":fixture_root}))
	game.queue_free();await settle();quit(0 if failures.is_empty() else 1)
