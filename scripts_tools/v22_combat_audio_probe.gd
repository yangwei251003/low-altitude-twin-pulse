extends SceneTree
## Root runs serially after import. --capture requires a non-Dummy driver and
## records SFX-bus PCM (pre-fader); this is not human listening evidence.
var audio: Node
var scene: Node3D
var checks := 0
var failures: Array[String] = []
var capture_mode := false
var capture: AudioEffectCapture
var frames := PackedVector2Array()
var stages: Array = []

func _initialize() -> void:
	capture_mode = "--capture" in OS.get_cmdline_user_args()
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func event(kind: String, id: int, position := Vector3(7, 0, 0)) -> Dictionary:
	return {"kind":kind,"event_id":id,"source_id":"source_"+str(id),"target_id":"target_"+str(id),"position":[position.x,position.y,position.z],"pilot_target":true,"damage":8.0,"component_damage":2.0,"surface":"metal"}

func _run() -> void:
	scene = Node3D.new()
	root.add_child(scene)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.make_current()
	root.audio_listener_enable_3d = true
	audio = load("res://scripts/v2/game_audio.gd").new()
	scene.add_child(audio)
	audio.update_environment({"listener_position":Vector3.ZERO})
	audio.set_mix({"music":0.0,"ambient":0.0,"birds":0.0,"rotor":0.0,"ui":0.0,"voice":0.0,"sfx":0.85})
	await process_frame
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/v22_combat/manifest.json"))
	var total_seconds := 0.0
	var pcm_bytes := 0.0
	for item: Dictionary in manifest.files:
		var stream := load("res://assets/audio/v22_combat/"+str(item.file)) as AudioStream
		check(stream != null, "Resource loads: "+str(item.id))
		if stream != null: check(absf(stream.get_length()-float(item.seconds))<.03,"Imported duration: "+str(item.id))
		total_seconds += float(item.seconds)
		pcm_bytes += float(item.seconds)*48000*2
	check(manifest.files.size()==37 and audio.get_combat_audio_debug().loaded_streams==37,"All 37 combat assets available")
	check(pcm_bytes < 12*1024*1024,"PCM budget below 12 MiB")
	check(not audio.get_combat_audio_credits().is_empty(),"Runtime combat credits available")
	check(not audio.play_combat_event({"kind":"invented"}),"Unknown events cannot make sound")
	check(not audio.play_combat_event({"kind":"shot","position":[NAN,0,0]}),"Invalid coordinates rejected")
	check(not audio.play_combat_event(event("near_pass",1,Vector3(20,0,0))),"Distant shot cannot pretend to be a near pass")
	var other_warning := event("warning_started",2)
	other_warning.pilot_target=false
	check(not audio.play_combat_event(other_warning),"Facility warning is not a player alarm")
	var shot := event("shot",3)
	check(audio.play_combat_event(shot),"Committed shot starts")
	check(not audio.play_combat_event(shot),"Duplicate event is not replayed")
	audio.reset_combat_audio("nearpass")
	check(audio.play_combat_event(event("near_pass",10,Vector3(3,0,0))),"First real near pass starts")
	check(audio.play_combat_event(event("near_pass",11,Vector3(-3,0,0))),"Second real near pass starts")
	check(not audio.play_combat_event(event("near_pass",12,Vector3(2,0,0))),"Near-pass cap is two")
	audio.reset_combat_audio("budget")
	for index: int in 12: check(audio.play_combat_event(event("impact",100+index)),"Voice pool slot "+str(index))
	check(audio.get_combat_audio_debug().active_voices==12,"Twelve active combat voices")
	check(not audio.play_combat_event(event("shot",200)),"Low-priority shot cannot steal impact voices")
	check(audio.play_combat_event(event("critical_warning",201)),"Critical cue replaces a lower-priority voice")
	check(audio.get_combat_audio_debug().active_voices==12,"Stealing never exceeds cap")
	paused=true
	check(not audio.play_combat_event(event("shot",202)),"Paused world cannot enqueue combat sound")
	await process_frame
	await process_frame
	check(audio._combat_players[0].stream_paused,"Existing combat playback freezes with world")
	paused=false
	await process_frame
	audio.reset_combat_audio("damage")
	audio.update_flight({"health":1.0},true,"R1",false)
	check(audio._rotor_damage_target==0.0,"Low hull health cannot fabricate rotor damage")
	audio.update_flight({"rotor_damage":.4,"motor_damage":.2},true,"R1",false)
	check(is_equal_approx(audio._rotor_damage_target,.4),"Actual component telemetry controls damage timbre")
	# A real static collider tests occlusion through the actual physics world.
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size=Vector3(1,8,8)
	shape.shape=box
	wall.add_child(shape)
	scene.add_child(wall)
	wall.position=Vector3(3,0,0)
	audio.reset_combat_audio("occlusion")
	check(audio.play_combat_event(event("destroyed",300,Vector3(7,0,0))),"Impact behind test wall starts")
	for tick in 15: await physics_frame
	check(bool(audio._combat_slots[0].occluded),"Real world collider attenuates sound")
	wall.queue_free()
	await process_frame
	audio.reset_combat_audio("capture")
	if capture_mode:
		check(AudioServer.get_driver_name()!="Dummy","Capture uses a real audio driver")
		capture=AudioEffectCapture.new()
		capture.buffer_length=2.0
		AudioServer.add_bus_effect(AudioServer.get_bus_index("SFX"),capture)
		var kinds := ["shot","near_pass","hit","impact","shield_absorbed","component_damaged","destroyed","wreck_impact","approach","warning_started","critical_warning"]
		for index: int in kinds.size():
			audio.reset_combat_audio("capture_"+str(index))
			var stimulus := event(kinds[index],400+index,Vector3(4,0,-2))
			if index==3: stimulus.surface="water"
			await record_stage(kinds[index],stimulus)
		audio.reset_combat_audio("capture_saturation")
		var simultaneous: Array = []
		for index: int in 11: simultaneous.append(event("destroyed",501+index,Vector3(.2,0,-.2)))
		await record_stage("twelve_close_simultaneous",event("destroyed",500,Vector3(.2,0,-.2)),simultaneous)
		write_wave()
	var result := {"suite":"v22_combat_audio","checks":checks,"failures":failures,"passed":failures.is_empty(),"capture_mode":capture_mode,"driver":AudioServer.get_driver_name(),"physical_listening_verified":false,"seconds_of_assets":total_seconds,"manifest_sha256":FileAccess.get_sha256("res://assets/audio/v22_combat/manifest.json"),"script_sha256":FileAccess.get_sha256("res://scripts/v2/game_audio.gd"),"stages":stages,"scope":"Contract/real physics occlusion; optional real SFX pre-fader output capture. Synthetic stimuli do not prove gameplay event generation."}
	var evidence_path := "res://assets/source_audio/v22_combat/engine_validation.json" if capture_mode else "res://assets/source_audio/v22_combat/engine_contract.json"
	var out := FileAccess.open(evidence_path,FileAccess.WRITE)
	if out: out.store_string(JSON.stringify(result,"\t")); out.close()
	print("V22_COMBAT_AUDIO_RESULT ",JSON.stringify(result))
	if capture_mode:
		var bus := AudioServer.get_bus_index("SFX")
		for index: int in range(AudioServer.get_bus_effect_count(bus)-1,-1,-1):
			if AudioServer.get_bus_effect(bus,index)==capture: AudioServer.remove_bus_effect(bus,index)
	capture=null
	scene.queue_free()
	await process_frame
	audio=null
	scene=null
	# Monotonic wall time: --fixed-fps must not collapse mixer teardown to ms.
	var until := Time.get_ticks_msec()+250
	while Time.get_ticks_msec()<until: await process_frame
	quit(0 if failures.is_empty() else 1)

func record_stage(label: String, stimulus: Dictionary, additional: Array = []) -> void:
	capture.clear_buffer()
	var discarded := capture.get_discarded_frames()
	check(audio.play_combat_event(stimulus),label+" capture event starts")
	for extra: Dictionary in additional: check(audio.play_combat_event(extra),label+" additional event starts")
	if not additional.is_empty(): check(audio.get_combat_audio_debug().active_voices==12,"Saturation capture contains twelve simultaneous voices")
	var first := frames.size()
	var end := Time.get_ticks_msec()+2100
	var nonzero := 0
	var clipped := 0
	var peak := 0.0
	while Time.get_ticks_msec()<end:
		await process_frame
		var buffer := capture.get_buffer(capture.get_frames_available())
		frames.append_array(buffer)
		for sample: Vector2 in buffer:
			var amplitude := maxf(absf(sample.x),absf(sample.y))
			peak=maxf(peak,amplitude)
			if amplitude>.00001: nonzero+=1
			if amplitude>=.99997: clipped+=1
	check(nonzero>0,label+" actual spatial bus is non-silent")
	check(clipped==0,label+" has no clipped bus samples")
	check(capture.get_discarded_frames()==discarded,label+" capture did not overflow")
	stages.append({"kind":label,"start_frame":first,"end_frame":frames.size(),"nonzero_frames":nonzero,"clipped_frames":clipped,"peak":peak})

func write_wave() -> void:
	var bytes := PackedByteArray()
	bytes.resize(frames.size()*4)
	for index: int in frames.size():
		bytes.encode_s16(index*4,int(clampf(frames[index].x,-1,1)*32767))
		bytes.encode_s16(index*4+2,int(clampf(frames[index].y,-1,1)*32767))
	var wav := AudioStreamWAV.new()
	wav.format=AudioStreamWAV.FORMAT_16_BITS
	wav.stereo=true
	wav.mix_rate=int(AudioServer.get_mix_rate())
	wav.data=bytes
	check(wav.save_to_wav(ProjectSettings.globalize_path("res://assets/source_audio/v22_combat/engine_sfx.wav"))==OK,"Stereo SFX capture saved")
