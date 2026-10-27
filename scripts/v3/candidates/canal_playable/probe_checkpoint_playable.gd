extends "res://scripts/v3/candidates/canal_playable/probe_workbench_playable.gd"
## Complete the real player-controlled local solution, then use real F5/F9
## input events and the production Store in a unique QA profile. No seeded work.
const Repository=preload("res://scripts/v3/candidates/canal_checkpoint/checkpoint_repository.gd")
var qa_profile:=""
var roundtrip_started:=false

func _configure_playable() -> void:
	qa_profile="user://qa_v3/canal_player_roundtrip_"+str(Time.get_ticks_usec())
	play.persistence_enabled=true
	play.profile_path=qa_profile

func _work_probe_timeout() -> float:
	return 250.0

func _run() -> void:
	create_timer(250).timeout.connect(func():
		if not finished:
			_check(false,"bounded complete player checkpoint roundtrip timeout")
			_finish())
	await super._run()

func _finish() -> void:
	if finished: return
	if not failures.is_empty() or not logger.errors.is_empty():
		super._finish(); return
	if roundtrip_started: return
	roundtrip_started=true
	_roundtrip.call_deferred()

func _roundtrip() -> void:
	var first_action: Dictionary=evidence.duplicate(true)
	# The first real work is done; allow the actual return logistics to finish.
	var idle:=false
	var idle_frames:=0
	for i in 7200:
		if not await _frame(): return
		var report: Dictionary=play.executor.report()
		if report.phase=="idle" and play.context.rules.snapshot().pending_action.is_empty():
			idle_frames+=1
		else: idle_frames=0
		# A completed move has a one-frame idle before its next pick/place.
		# Only continuous quiescence means the return sequence has finished.
		if idle_frames>=24:
			idle=true; break
	if not _check(idle,"real return logistics reach a safe idle after completed work",play.executor.report()):
		_finish(); return
	if not await _select_target(play.Workbench.POWER_ID): return
	await _key(KEY_6)
	# Exercise actual add/drain commands; enough paid energy remains below full
	# after the normal 9/s regeneration during stable checkpoint observation.
	# A single 8-point charge legitimately regenerated before the prior F5 save.
	for operation in 6:
		while play.cooldown>0:
			if not await _frame(): return
		await _key(KEY_F if operation%2==0 else KEY_X)
		if not _check(play.last_action.get("ok",false),"actual add/drain device input "+str(operation+1),play.last_action):
			_finish(); return
	if not _check(play.last_action.get("ok",false) and play.entities[play.PLAYER_ID].energy<100,"actual nearby charge spends energy before save",play.last_action):
		_finish(); return
	# Declared QA damage uses the public DamageModel with zero impulse. No
	# flight pose, health, heat or battery is authored to fake the action.
	var hit: Dictionary=play.player.apply_combat_hit(6.0,Vector3.ZERO,play.player.to_global(Vector3(0,0,.4)),"pulse",{"qa_save_damage":true})
	_check(not hit.is_empty() and play.player.health<100,"public damage creates actual injury for roundtrip",hit)
	await _key(KEY_F5)
	for i in 1250:
		if not await _frame(): return
		if play.save_generation==1 or not play._save_requested: break
	if not _check(play.save_generation==1 and play.last_save_result.get("ok",false),"F5 publishes checkpoint from the actual completed player action",{"result":play.last_save_result.get("code"),"capture":play._last_save_code,"rules":play.context.rules.snapshot(),"executor":play.executor.report()}):
		_finish(); return
	var repository=Repository.new(qa_profile)
	var disk: Dictionary=repository.read()
	if not _check(disk.ok and not disk.empty and disk.generation==1,"independent repository reads the real player save"):
		_finish(); return
	var saved: Dictionary=disk.envelope
	_checkpoint_trace("first_saved",saved)
	_check(saved.site.rules.jobs_completed==1 and saved.site.rules.service_credit==1 and saved.site.rules.services_consumed==0,"save contains original sole service result")
	_check(saved.player.flight.health<100 and saved.player.flight.state.battery<100 and saved.ability.energy<100,"saved resources and injury were not refilled")
	await _capture("06-player-checkpoint-saved.png")
	var old_instance: int=play.get_instance_id()
	# The real scene becomes SceneTree.current_scene for the actual reload API.
	current_scene=play
	await _key(KEY_F9)
	var loaded:=false
	for i in 900:
		await physics_frame
		if is_instance_valid(current_scene) and current_scene.get_instance_id()!=old_instance:
			play=current_scene
			if not play.fatal.is_empty():
				_check(false,"F9 reload remains healthy",{"fatal":play.fatal,"result":play.last_save_result}); _finish(); return
			if play.boot_ready and not play.loading_checkpoint:
				loaded=true; break
	if not _check(loaded,"F9 destroys old scene and reconstructs a different actual scene"):
		_finish(); return
	play.inputs.test_enabled=true
	play.inputs.test_frame={"axes":{},"held":["brake"]}
	var resumed: Dictionary=play.last_save_result.duplicate(true)
	_checkpoint_trace("first_adopted",resumed)
	_check(resumed.get("code")=="player_scene_restored" and play.save_generation==1,"normal playable restore reaches current-frame adoption",resumed)
	_check(resumed.initial_player.health==saved.player.flight.health and _saved_equal(resumed.initial_player.state.damage,saved.player.flight.state.damage),"first adopted frame preserves hull armor and component injury")
	_check(resumed.initial_energy==saved.ability.energy and resumed.initial_player.state.battery==saved.player.flight.state.battery,"first adopted frame does not refill player power")
	_check(resumed.station_serial==saved.ability.station_serial and resumed.initial_world_clock==saved.world_clock,"device input serial and world clock survive real scene reload")
	for i in 300:
		if not await _frame(): return
	_check(play.player.health==saved.player.flight.health and play.player.collision_count==saved.player.collision_count,"restored actual player continues for five seconds without healing or a collision")
	var state: Dictionary=play.context.rules.snapshot()
	_check(state.jobs_completed==1 and state.service_credit==1 and state.services_consumed==0 and play.workbench.report().receipt_count==1,"five seconds of resumed host work do not duplicate the result")
	await _capture("07-player-checkpoint-restored.png")
	if not await _select_target(play.Workbench.POWER_ID): return
	await _key(KEY_6)
	await _key(KEY_F)
	_check(play.last_action.get("ok",false) and play.station_serial>int(saved.ability.station_serial),"post-load real device input continues its sequence",play.last_action)
	await _key(KEY_F5)
	for i in 1250:
		if not await _frame(): return
		if play.save_generation==2 or not play._save_requested: break
	_check(play.save_generation==2 and repository.read().generation==2,"new F5 commits a second generation after actual continued play")
	evidence={"scope":"actual fresh player action, real public QA damage, F5 Store write, F9 whole-scene reload and continued host work; no physical keyboard/human/LAN/MAIN claim", "profile":qa_profile,"first_action":first_action,"first_saved":saved,"first_adopted":resumed,"continued_rules":state,"last_save_code":play.last_save_result.get("code","")}
	super._finish()

func _checkpoint_trace(name: String,value: Dictionary) -> void:
	if output.is_empty(): return
	var file:=FileAccess.open(output+"/"+name+".json",FileAccess.WRITE)
	if file!=null: file.store_string(JSON.stringify(value,"\t"))

func _saved_equal(a: Variant,b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return is_finite(float(a)) and is_finite(float(b)) and absf(float(a)-float(b))<=1.0e-10
	if typeof(a)!=typeof(b): return false
	if a is Dictionary:
		if a.size()!=b.size(): return false
		for key in a:
			if not b.has(key) or not _saved_equal(a[key],b[key]): return false
		return true
	if a is Array:
		if a.size()!=b.size(): return false
		for i in a.size():
			if not _saved_equal(a[i],b[i]): return false
		return true
	return a==b
