extends "res://scripts_tools/v3/acceptance_flight_driver.gd"
## Actual GPU viewport and native game UI; no desktop mouse/keyboard input.
var outcomes: Array = []
var folder := ""

func play_region(_region: String, _mode: String) -> bool:
	folder = str(get_tree().get_meta("acceptance_output")).get_base_dir()
	var regions: Array = [] if _mode=="panels" else ["I1","F1","I2","F2","I3","F3","I4","F4"]
	for region: String in regions:
		_event("before_GPU_region",{"destination":region,"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),"resources":Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),"video_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)})
		if not await travel(region) or not await _dismiss(): return false
		for _frame in range(20): await _next()
		if not await _capture("region-"+region): return false
		if region=="I1":
			if not await fly_to(Vector3(30,7,20),"actual_repaired_salvage_platform") or not await _capture("I1-salvage-platform"):return false
		if region=="F1":
			if not await fly_to(Vector3(31,11,35),"actual_relocated_bells") or not await _capture("F1-twin-bells"):return false
			if not await fly_to(Vector3(28,18.0,24),"actual_treecrown_record") or not await _capture("F1-treecrown-record"):return false
		var loops: Array = []
		for id: String in session.audio._loops:
			var player: AudioStreamPlayer = session.audio._loops[id]
			if player.playing and player.stream!=null: loops.append({"id":id,"volume_db":player.volume_db,"length":player.stream.get_length()})
		if not _check(not loops.is_empty() and session.audio._missing.is_empty(),"real audio loops decode and no runtime cue is missing",{"region":region,"loops":loops,"missing":session.audio._missing}): return false
	_key(KEY_L)
	for _frame in range(8):await _next()
	var journal: Control=session.interface.journal
	if not _check(journal.visible and journal._selector.item_count==8 and journal._body.get_child_count()>0,"normal L renders the real completed notebook for all eight regions"):return false
	if not await _capture("completed-notebook") or not await ui_accept(journal._close):return false
	if not _check(not journal.visible,"notebook return control restores the flight view"):return false
	_key(KEY_H)
	await _next()
	var book: Control = session.interface.campaign_book
	if not _check(book.visible and book.pages.size()>=8,"normal H opens real flight handbook with region guidance"): return false
	if not await _capture("handbook"): return false
	if not await ui_accept(book._close): return false
	session._ui_action("ending_book",{})
	await _next()
	if not _check(book.visible and book.pages.size()==19,"real ending book has 18 epilogue cards and credits"): return false
	if not await _capture("ending"): return false
	var played_voice := false
	for index in range(book.pages.size()):
		if book._voice.visible and not played_voice:
			if not await ui_accept(book._voice): return false
			for _frame in range(12): await _next()
			var slot: int = session.audio._radio_slot
			if not _check(slot>=0 and session.audio._ui[slot].playing and session.audio._ui[slot].stream.get_length()>.2,"real page button starts decoded Chinese synthetic voice",{"slot":slot,"cue":book.pages[index].get("voice_id")}): return false
			played_voice=true
		if index<book.pages.size()-1 and not await ui_accept(book._next): return false
	if not _check(played_voice and book._index==18 and book._next.disabled,"all actual ending pages and final credits are reachable by GUI input"): return false
	if not await _capture("credits") or not await ui_accept(book._close): return false
	return _check(not book.visible and not session.interface.menu.visible,"return button restores flight after reading")

func _capture(id: String) -> bool:
	var drawn: Array=[false]
	var observed:=func():drawn[0]=true
	RenderingServer.frame_post_draw.connect(observed,CONNECT_ONE_SHOT)
	var until:=Time.get_ticks_msec()+12000
	while not drawn[0] and Time.get_ticks_msec()<until:await get_tree().process_frame
	if not drawn[0] and RenderingServer.frame_post_draw.is_connected(observed):RenderingServer.frame_post_draw.disconnect(observed)
	if not _check(drawn[0],"actual GPU rendering completes a frame within the bounded observation",id):return false
	var frame := get_tree().root.get_texture().get_image()
	if not _check(frame!=null and frame.get_width()==1280 and frame.get_height()==720,"real GPU viewport produces expected full frame",id): return false
	var path := folder.path_join(id+".png")
	if not _check(frame.save_png(path)==OK,"actual viewport capture is written to managed evidence",path): return false
	outcomes.append({"kind":"actual_GPU_frame","id":id,"path":path,"region":session.region_id,"renderer":RenderingServer.get_current_rendering_method(),"driver":RenderingServer.get_current_rendering_driver_name()})
	_event("actual_GPU_frame",outcomes[-1])
	return true
