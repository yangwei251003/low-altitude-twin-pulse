extends SceneTree
## Run serially: --headless --path . --script tests_v2/test_v22_night.gd -- --v2-qa=night_<fresh_unique_id>
## Real GameSession/renderer objects and combat queries; no visual pass is claimed.
const Session = preload("res://scripts/v2/session.gd")
const Combat = preload("res://scripts/v2/combat.gd")
var game: GameSessionV2
var checks = 0
var failures: Array[String] = []
var qa_case = ""

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--v2-qa=night_"): qa_case=argument.trim_prefix("--v2-qa=").validate_filename()
	if qa_case.length()<12 or DirAccess.dir_exists_absolute("user://qa_v2/session_"+qa_case):
		printerr("Night test requires a fresh --v2-qa=night_<unique_id>; no normal profile access.")
		quit(2);return
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks+=1
	print("V22_NIGHT_", "PASS " if value else "FAIL ",label)
	if not value: failures.append(label)

func frames(count: int) -> void:
	for i in count: await process_frame

func physics_steps(count: int) -> void:
	for i in count: await physics_frame

func move_to(point: Vector3, yaw: float=0.0) -> void:
	game.pilot.global_position=point;game.pilot.heading=yaw
	game.pilot.linear_velocity=Vector3.ZERO;game.pilot.angular_velocity=Vector3.ZERO
	game.night_visibility._last_light_refresh_ms=-1000
	game.night_visibility.update_state(point,yaw,false)

func run() -> void:
	game=Session.new();root.add_child(game)
	game.set_physics_process(false);game.set_process(false)
	await frames(3)
	if not game.qa_mode or not game.repository.root_path.begins_with("user://qa_v2/"):
		printerr("GameSession did not honor isolated QA profile");game.queue_free();quit(2);return
	var applied=game.repository.commit({"id":"qa:night_low_settings","set":{"settings.quality":"low","settings.mute":true,"settings.fullscreen":false}})
	check(applied.ok,"low quality fixture is committed only to an isolated QA profile")
	game.apply_settings();game.night=true;game.launch_exploration("R1")
	check(game.flight_active and is_instance_valid(game.night_visibility),"real R1 Session constructs the night controller")
	if not game.flight_active or not is_instance_valid(game.night_visibility):
		await finish();return
	game.pilot.freeze=true;game.pilot.set_physics_process(false)
	game.combat.set_physics_process(false)
	if is_instance_valid(game.living): game.living.set_physics_process(false)
	await physics_steps(2)
	var night=game.night_visibility
	check(str(game.repository.data.settings.quality)=="low" and root.msaa_3d==Viewport.MSAA_DISABLED,"real Session uses its low quality path")
	check(night.night and night.veil.visible,"night veil is enabled in the real Session")
	check(night.veil.get_parent()==game.camera,"veil follows the actual camera, including overview")
	check(night.veil.material_override==night.veil_material,"visible veil uses the controller shader material")
	check(night.veil_material.shader.resource_path=="res://assets/shaders/v22/night_visibility.gdshader","expected night shader is assigned")
	# The industrial night art direction deliberately retains legible silhouettes.
	# Darkness is therefore a bounded lighting reduction, while enemies are explicitly hidden.
	var night_light=game.environment.environment.ambient_light_energy*game.environment.environment.ambient_light_color.get_luminance()+game.sun.light_energy*game.sun.light_color.get_luminance()
	check(game.environment.environment.ambient_light_energy<=.6 and game.sun.light_energy<=.2 and not game.sun.shadow_enabled,"night art lighting stays bounded and does not add global shadow passes")
	game.set_lighting(false)
	var day_light=game.environment.environment.ambient_light_energy*game.environment.environment.ambient_light_color.get_luminance()+game.sun.light_energy*game.sun.light_color.get_luminance()
	check(night_light<=day_light*.70,"color-weighted global night illumination stays at least 30 percent below day")
	game.set_lighting(true)
	check(night.headlamp.shadow_enabled and not night.navigation_fill.shadow_enabled,"only the drone beam adds a local shadow map")
	check(night.pool_lights.size()<=6,"warm real-light pool has a fixed six-light budget")
	var pool_shadow_count=0
	for light in night.pool_lights:
		if light.shadow_enabled: pool_shadow_count+=1
	check(pool_shadow_count==0,"street pools do not add cube shadow passes")
	await test_uniforms_and_direction()
	await test_overview()
	await test_day_night_restoration()
	await test_combat_filter()
	await finish()

func test_uniforms_and_direction() -> void:
	var night=game.night_visibility
	# Above rooftops, so lamp pools and building collisions cannot confound beam tests.
	var p=Vector3(125,24,125)
	move_to(p)
	check(night.point_visible(p),"own aircraft remains visible")
	check(night.point_visible(p+Vector3(0,-3,-9)),"front cone reveals a nearby point")
	check(not night.point_visible(p+Vector3(0,0,9)),"same-distance point behind the aircraft remains hidden")
	check(not night.point_visible(p+Vector3(0,0,-31)),"far world stays hidden beyond the bounded envelope")
	check(game.night_point_visible(p+Vector3(0,-3,-9))==night.point_visible(p+Vector3(0,-3,-9)),"Session forwards the actual night visibility rule")
	var material: ShaderMaterial=night.veil_material
	check(Vector3(material.get_shader_parameter("pilot_position")).is_equal_approx(p),"shader receives the same pilot center as CPU visibility")
	check(Vector3(material.get_shader_parameter("beam_origin")).is_equal_approx(night.beam_origin),"shader receives the actual light origin")
	check(Vector3(material.get_shader_parameter("beam_direction")).is_equal_approx(night.beam_direction),"shader receives the actual light direction")
	check(is_equal_approx(float(material.get_shader_parameter("beam_range")),night.BEAM_RANGE) and is_equal_approx(night.headlamp.spot_range,night.BEAM_RANGE),"shader, CPU and real spotlight share range")
	check(is_equal_approx(float(material.get_shader_parameter("beam_cos_outer")),cos(deg_to_rad(night.headlamp.spot_angle))),"shader cone matches the real spotlight angle")
	check(is_equal_approx(float(material.get_shader_parameter("self_radius")),night.navigation_fill.omni_range),"near visibility sphere matches the actual fill light")
	check((-night.headlamp.global_basis.z).dot(night.beam_direction)>.999,"actual Spotlight -Z points in the declared beam direction")
	move_to(p,PI/2)
	check(night.point_visible(p+Vector3(-9,-3,0)) and not night.point_visible(p+Vector3(0,-3,-9)),"90 degree yaw rotates visibility to the aircraft nose")
	check((-night.headlamp.global_basis.z).x<-.9 and night.beam_direction.y<0,"real headlamp rotates left and remains pitched downward")
	check(Vector3(material.get_shader_parameter("beam_direction")).is_equal_approx(-night.headlamp.global_basis.z),"yaw update reaches shader and physical light together")
	move_to(game.world.route_lamps[0].global_position+Vector3(0,4,3))
	check(night.active_pools.size()>0 and night.active_pools.size()<=6,"actual nearby R1 lamps produce bounded warm pools")
	var pool_positions=material.get_shader_parameter("light_pools")
	var pool_gains=material.get_shader_parameter("pool_gains")
	check(pool_positions.size()==6 and pool_gains.size()==6 and int(material.get_shader_parameter("pool_count"))==night.active_pools.size(),"fixed-length shader arrays carry the live pool count")
	var pool_alignment=true
	for i in night.active_pools.size():
		var pool: Dictionary=night.active_pools[i];var encoded: Vector4=pool_positions[i]
		pool_alignment=pool_alignment and Vector3(encoded.x,encoded.y,encoded.z).is_equal_approx(pool.position) and is_equal_approx(encoded.w,float(pool.radius))
		pool_alignment=pool_alignment and night.pool_lights[i].global_position.is_equal_approx(pool.position) and is_equal_approx(float(pool_gains[i]),float(pool.gain))
	check(pool_alignment,"shader pools, CPU pools and actual street lights use identical centers and gains")
	check(not night.point_visible(Vector3(500,0,400)),"distant city cannot become visible through street lighting")
	var shader_source=FileAccess.get_file_as_string("res://assets/shaders/v22/night_visibility.gdshader")
	check(shader_source.contains("RENDERER_COMPATIBILITY") and shader_source.contains("vec3(SCREEN_UV, depth) * 2.0 - 1.0"),"shader source includes OpenGL -1..1 depth reconstruction")
	check(not shader_source.contains("hint_screen_texture") and shader_source.contains("depth_draw_never"),"night overlay preserves existing color composition without writing scene depth")

func test_overview() -> void:
	var night=game.night_visibility
	move_to(Vector3(125,24,125),0)
	var before=night.visibility_snapshot()
	var close_point=game.pilot.global_position+Vector3(0,-3,-9)
	var far_point=Vector3(500,0,400)
	var close_before=night.visibility_strength(close_point)
	game.open_overview()
	check(game.flight_camera.overview and night.overview,"real Session overview updates the night controller")
	check(is_equal_approx(game.camera.size,80.0) and game.flight_camera.overview_focus.distance_to(game.pilot.global_position)<0.1,"night overview opens near the aircraft at a legible local scale")
	game.camera_zoom(1.0)
	check(game.camera.size<80.0,"night overview zooms continuously from its starting scale")
	check(is_equal_approx(night.visibility_strength(close_point),close_before) and not game.night_point_visible(far_point),"overview keeps the same local visibility and hides far markers")
	var after=night.visibility_snapshot()
	check(after.beam_range==before.beam_range and after.maximum_radius==before.maximum_radius,"overview does not enlarge world-space light ranges")
	check(night.veil.visible and night.veil.get_parent()==game.camera,"night overlay remains attached and visible while the map is open")
	game.close_overview()
	check(not game.flight_camera.overview and not night.overview,"returning from overview restores local camera state")
	paused=false

func test_day_night_restoration() -> void:
	var night=game.night_visibility
	move_to(game.world.route_lamps[0].global_position+Vector3(0,4,3))
	var authored=authored_lights(game.world)
	check(not authored.is_empty(),"authored facility lights exist in actual streamed world")
	check(authored.all(func(light):return light.visible and not light.shadow_enabled),"facility illumination survives legacy suppression without extra shadow maps")
	# Explicit old untagged light checks backward compatibility independently of new art.
	var old_fixture=OmniLight3D.new();game.world.chunks.values()[0].add_child(old_fixture);night._suppress_node(old_fixture)
	check(not night._legacy_lights.is_empty(),"real night POI lamps are registered for reversible replacement")
	var legacy: Node3D
	for entry in night._legacy_lights:
		if bool(entry.visible) and is_instance_valid(entry.node.get_ref()): legacy=entry.node.get_ref();break
	check(is_instance_valid(legacy) and not legacy.visible,"old POI light is suppressed while its bounded replacement is active")
	# Activate the existing searchlight module through FlightBody's real constructor path.
	game.pilot.stats.modifiers["searchlight_enabled"]=true
	game.pilot._sync_searchlight()
	check(is_instance_valid(game.pilot.searchlight) and game.pilot.searchlight.visible,"legacy module spotlight exists before night management")
	night.update_state(game.pilot.global_position,game.pilot.heading,false)
	check(not game.pilot.searchlight.visible and night.headlamp.visible,"night management prevents duplicate drone spotlights")
	var original_priority=int(night._silhouette_priority)
	check(game.pilot.silhouette_material.render_priority>night.veil_material.render_priority,"only the emergency aircraft silhouette draws above the veil")
	game.set_lighting(false)
	check(not night.night and not night.veil.visible and not night.headlamp.visible and not night.navigation_fill.visible,"day mode disables all night-only rendering")
	check(night.point_visible(Vector3(500,0,400)),"day mode restores ordinary distant visibility")
	check(is_instance_valid(legacy) and legacy.visible,"day mode restores the original POI light state")
	check(game.pilot.searchlight.visible,"day mode restores the module spotlight state")
	check(game.pilot.silhouette_material.render_priority==original_priority,"day mode restores the original silhouette priority")
	var transitions_ok=true
	for i in 3:
		game.set_lighting(true)
		transitions_ok=transitions_ok and night.night and not game.pilot.searchlight.visible and is_instance_valid(legacy) and not legacy.visible
		game.set_lighting(false)
		transitions_ok=transitions_ok and game.pilot.searchlight.visible and is_instance_valid(legacy) and legacy.visible
	check(transitions_ok,"repeated day/night transitions restore original lamp states without duplication")
	game.set_lighting(true)

func foe(point: Vector3) -> Combat.Foe:
	var enemy=Combat.Foe.new();enemy.role="shooter";enemy.combat=game.combat
	game.combat.add_child(enemy);enemy.global_position=point;enemy.home=point
	enemy.set_physics_process(false);game.combat.enemies.append(enemy)
	return enemy

func test_combat_filter() -> void:
	var p=Vector3(125,24,125)
	move_to(p,0)
	check(game.combat.target_visibility.is_valid(),"real Session connects combat to the visibility callable")
	var hidden=foe(p+Vector3(0,0,7))
	await physics_steps(2)
	check(not game.night_point_visible(hidden.global_position),"combat fixture places the close enemy outside all night light volumes")
	game._sync_world_visibility()
	check(is_instance_valid(hidden.model) and not hidden.model.is_visible_in_tree(),"dark enemy body is actually hidden, independently of world illumination")
	check(not is_instance_valid(hidden.shield) or not hidden.shield.is_visible_in_tree(),"dark enemy shield cannot reveal its position")
	check(game.combat.nearest_target(36.0)==null,"auto aim does not select a nearby enemy in darkness")
	var bolt_count=game.combat.bolts.size()
	game.pilot.command={"active":true,"fire":true};game.combat.auto_fire=true
	game.combat._physics_process(.05)
	check(game.combat.aim_status=="no_visible_target" and game.combat.bolts.size()==bolt_count,"actual firing update does not create a shot at a dark enemy")
	check(game.combat.request_warning(hidden,game.pilot)==0,"dark enemy cannot begin an unobservable attack warning")
	var lit=foe(p+Vector3(0,-3,-9))
	await physics_steps(2)
	check(game.night_point_visible(lit.global_position),"second combat fixture is inside the nose light")
	game._sync_world_visibility()
	check(is_instance_valid(lit.model) and lit.model.is_visible_in_tree(),"illuminated enemy body is restored through the real Session visibility pass")
	check(game.combat.nearest_target(36.0)==lit,"aim chooses the visible enemy even when a dark enemy is closer")
	game.combat._warning_gap=0
	check(game.combat.request_warning(lit,game.pilot)>0,"visible enemy can start its observable attack warning")
	game.set_lighting(false)
	game._sync_world_visibility()
	check(hidden.model.is_visible_in_tree() and lit.model.is_visible_in_tree(),"day mode restores both enemy bodies")
	check(game.combat.nearest_target(36.0)==hidden,"day mode restores normal nearest-visible-target selection")
	game.set_lighting(true)
	game._sync_world_visibility()
	check(not hidden.model.is_visible_in_tree() and lit.model.is_visible_in_tree(),"returning to night hides only the unlit enemy body again")
	check(game.combat.nearest_target(36.0)==lit,"returning to night immediately restores target filtering")

func authored_lights(node: Node) -> Array:
	var found: Array=[]
	if node is Light3D and bool(node.get_meta("worldui_environment_light",false)):found.append(node)
	for child in node.get_children():found.append_array(authored_lights(child))
	return found

func finish() -> void:
	paused=false
	var camera_ref: Camera3D=game.camera if is_instance_valid(game) else null
	if is_instance_valid(game):
		game.show_hangar()
		await frames(3)
		var veil_count=0
		if is_instance_valid(camera_ref):
			for child in camera_ref.get_children():
				if str(child.name).begins_with("NightWorldVisibilityVeil"): veil_count+=1
		check(veil_count==0,"leaving flight releases the camera-attached veil")
		game.queue_free()
	await frames(3)
	await create_timer(.2).timeout
	print("V22_NIGHT_SUMMARY ",JSON.stringify({"suite":"v22_night","checks":checks,"failures":failures,"ok":failures.is_empty(),"qa_case":qa_case,"engine":Engine.get_version_info().string,"evidence_scope":"Real low-quality GameSession, material uniform bindings, visibility envelope, light transforms, overview state, reversible lamp ownership with actual enemy body visibility, bounded world light energy and actual combat target/ray queries. Headless execution is NOT GPU shader compilation, rendered darkness, transparency composition, frame-time, or human night-flight comfort evidence."}))
	quit(0 if failures.is_empty() else 1)
