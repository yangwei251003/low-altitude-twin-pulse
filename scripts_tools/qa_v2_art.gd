extends "res://scripts_tools/qa_v2_render.gd"

func _matrix() -> void:
	DisplayServer.window_set_size(Vector2i(1440,810))
	session.ui.apply_scale(1.0)
	session.ui.show_hangar("任务")
	await _wait_rendered(1.0,false)
	await _capture("menu_art")
	session.ui.show_hangar("机库")
	await _wait_rendered(0.7,false)
	await _capture("hangar_live")
	for region_id in ["R1","R2","R3","R4"]:
		for dark in [false,true]:
			_set_flight(region_id,dark)
			session.pilot.freeze = true
			await _wait_rendered(2,false)
			await _capture(region_id+("_night" if dark else "_day"))
			current_samples.clear(); previous_us=0
			var begin = Time.get_ticks_msec()
			while Time.get_ticks_msec()-begin<5000:
				await process_frame
				var now = Time.get_ticks_usec()
				if previous_us>0: current_samples.append((now-previous_us)/1000.0)
				previous_us = now
			results.append(_sample_summary(region_id+("_night" if dark else "_day")))
	_set_flight("R1",false)
	session.pilot.freeze = true
	session.pilot.global_position = Vector3(-3,3,72)
	session.world.update_stream(session.pilot.global_position,true)
	session._snap_camera()
	await _wait_rendered(1,false)
	await _capture("road_edge_inside_boundary")
	# Capture a real modeled building crossing the orthographic line of sight.
	for entry in session.visibility_controller.entries.values():
		if not is_instance_valid(entry.root): continue
		var bounds: AABB = entry.root.global_transform*entry.bounds
		if bounds.size.y<6 or bounds.size.x<5: continue
		session.pilot.global_position = bounds.position+Vector3(-1.2,2.0,-1.2)
		session.world.update_stream(session.pilot.global_position,true)
		session._snap_camera()
		await _wait_rendered(1,false)
		await _capture("building_occlusion_faded")
		results.append({"label":"occlusion","occluded":session.visibility_controller.occluded,"pilot_position":str(session.pilot.global_position)})
		break
	for entry in session.visibility_controller.outline_entries.values():
		if not is_instance_valid(entry.root): continue
		var bounds: AABB = entry.root.global_transform*entry.bounds
		session.pilot.global_position = bounds.position+Vector3(-0.4,1.0,-0.4)
		session.world.update_stream(session.pilot.global_position,true)
		session._snap_camera()
		await _wait_rendered(1,false)
		await _capture("tree_occlusion_outline")
		results.append({"label":"tree_outline","occluded":session.visibility_controller.occluded,"tree_blocked":entry.blocked})
		if not entry.blocked: failures.append("Tree proxy did not detect the rendered sight line")
		break
	for format in [[1280,720,1.5],[1024,768,1.5],[1920,1080,1.0]]:
		DisplayServer.window_set_size(Vector2i(format[0],format[1]))
		session.ui.apply_scale(format[2])
		session.ui.show_hud()
		await _wait_rendered(.5,false)
		await _capture("hud_%d_%d_%d"%[format[0],format[1],format[2]*100])
		session.show_hangar()
		session.ui.show_hangar("任务")
		await _wait_rendered(.5,false)
		await _capture("menu_%d_%d_%d"%[format[0],format[1],format[2]*100])
		_set_flight("R1",false)
		session.pilot.freeze=true
