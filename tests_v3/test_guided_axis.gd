extends SceneTree
const Axis = preload("res://scripts/v3/environment/twin_guided_axis.gd")
const CONFIG := {"travel_m":1.2,"mass_kg":2.0,"damping_per_second":0.8,"max_speed_mps":6.0,"max_impulse_ns":9.0}
var checks := 0
var failures: Array = []

func _init() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _new_axis(position: float = 0.6, speed: float = 0.0):
	var axis = Axis.new()
	_check(axis.configure(CONFIG).ok, "configure exact bounded definition")
	axis.set_active_peers([1,2])
	var saved: Dictionary = axis.snapshot()
	saved.position_m = position
	saved.velocity_mps = speed
	_check(axis.restore(saved, false).ok, "explicit motion fixture validates")
	return axis

func _run() -> void:
	_float32_impulse_boundary()
	for direction in [-1.0,1.0]:
		var axis = _new_axis()
		var before: Dictionary = axis.snapshot()
		_check(axis.can_accept(Vector3.RIGHT*9.0*direction,1,1).ok and axis.snapshot()==before,"approval is read-only")
		_check(axis.apply_impulse(Vector3.RIGHT*9.0*direction,1,1).ok,"full-axis 9Ns accepted")
		_check(float(axis.snapshot().velocity_mps)==4.5*direction,"mass converts 9Ns into 4.5mps")
		axis.advance(0.25)
		_check(float(axis.snapshot().position_m)==(0.0 if direction<0 else 1.2) and float(axis.snapshot().velocity_mps)==0.0,"complete step clamps to actual endpoint and cancels outward momentum")
		axis.apply_impulse(Vector3.RIGHT*9.0*direction,1,2)
		axis.advance(0.25)
		_check(float(axis.snapshot().position_m)==(0.0 if direction<0 else 1.2),"repeated outward input cannot leave endpoint")
	for initial_speed in [-5.0,0.0,5.0]:
		for pair in [[9.0,9.0],[-9.0,-9.0],[9.0,-9.0],[-9.0,9.0]]:
			var a = _new_axis(0.6,initial_speed)
			var b = _new_axis(0.6,initial_speed)
			for index in [0,1]: a.apply_impulse(Vector3.RIGHT*float(pair[index]),index+1,1)
			for index in [1,0]: b.apply_impulse(Vector3.RIGHT*float(pair[index]),index+1,1)
			_check(a.snapshot()==b.snapshot(),"same-tick aggregation is independent of player arrival order")
			_check(float(a.snapshot().velocity_mps)==clampf(initial_speed+(float(pair[0])+float(pair[1]))/2.0,-6.0,6.0),"saturation occurs once after total impulse")
			a.advance(1.0/60.0)
			b.advance(1.0/60.0)
			_check(a.snapshot()==b.snapshot(),"order-independent input produces identical integrated motion")
	var axis = _new_axis()
	axis.apply_impulse(Vector3.RIGHT*9.0,1,1)
	var before: Dictionary = axis.snapshot()
	for delta in [-0.1,0.251,NAN,INF]: _check(not axis.advance(delta).ok and axis.snapshot()==before,"invalid delta is atomic")
	_check(axis.advance(0.0).ok and axis.snapshot()==before,"pure zero delta does not consume or integrate momentum")
	_check(not axis.apply_impulse(Vector3.RIGHT,1,1).ok and not axis.apply_impulse(Vector3.RIGHT,1,2).ok,"duplicate and second same-peer same-tick inputs rejected")
	_check(not axis.apply_impulse(Vector3.RIGHT,3,1).ok and not axis.set_active_peers([1,2,3]).ok and axis.snapshot()==before,"unknown or excessive peers cannot grow state")
	_check(not axis.apply_impulse(Vector3(INF,0,0),2,1).ok and not axis.apply_impulse(Vector3.RIGHT*9.01,2,1).ok,"nonfinite and oversized impulses rejected")
	var clone = axis.copy_for_trial()
	clone.advance(0.1,true)
	_check(float(clone.snapshot().position_m)==0.6 and float(clone.snapshot().velocity_mps)==0.0 and axis.snapshot()==before,"blocked candidate stops without mutating original")
	var cancelled: Dictionary = axis.stop()
	_check(cancelled.cancelled.size()==1 and axis.snapshot().velocity_mps==0.0,"stop cancels accepted momentum with request identity")
	axis.advance(0.1)
	_check(axis.snapshot().position_m==0.6,"stop cannot release delayed force later")
	axis.apply_impulse(Vector3.RIGHT*9.0,1,3)
	var moving: Dictionary = axis.snapshot()
	var restored = _new_axis()
	_check(restored.restore(JSON.parse_string(JSON.stringify(moving))).ok and restored.snapshot().velocity_mps==0.0,"host restore clears momentum and contains no queued commands")
	_check(not restored.apply_impulse(Vector3.RIGHT,1,3).ok,"restore retains bounded anti-replay serial")
	var detached: Dictionary = restored.snapshot()
	detached.last_serial.clear()
	_check(restored.snapshot().last_serial.size()==2,"snapshot nested state does not alias")
	before = restored.snapshot()
	for pair in [["extra",0],["algorithm","wrong"],["config_sha256","wrong"],["position_m",1.21],["velocity_mps",6.01],["last_serial",{"01":2}],["last_serial",{"1":2.5}],["last_serial",{"1":0,"2":0,"3":0}]]:
		var bad: Dictionary = before.duplicate(true)
		bad[pair[0]]=pair[1]
		_check(not restored.restore(bad).ok and restored.snapshot()==before,"malformed restore atomically rejected")
	axis.set_active_peers([2])
	_check(axis.snapshot().last_serial.size()==1 and axis.snapshot().velocity_mps==0.0,"leaving peer cancels pending input and removes bounded slot")
	axis.set_active_peers([2,3])
	_check(axis.apply_impulse(Vector3.LEFT*9.0,3,1).ok,"new current peer may occupy released slot")
	_check(axis.reset_peer(3).ok and axis.snapshot().last_serial["3"]==-1 and axis.snapshot().velocity_mps==0.0,"explicit actor recreation clears only that actor's pending impulse and revision")
	_check(axis.apply_impulse(Vector3.RIGHT*9.0,3,1).ok,"recreated actor revision starts at one")
	before=axis.snapshot()
	_check(not axis.reset_peer(999).ok and axis.snapshot()==before,"unknown actor reset never allocates a slot")
	var lifecycle = _new_axis(0.6,1.0)
	lifecycle.apply_impulse(Vector3.RIGHT*4.0,1,50)
	lifecycle.apply_impulse(Vector3.LEFT*2.0,2,75)
	lifecycle.reset_peer(1)
	_check(lifecycle.snapshot().position_m==0.6 and lifecycle.snapshot().velocity_mps==0.0 and lifecycle.snapshot().last_serial["2"]==75,"one actor recreation preserves other pending input and original position")
	_check(not lifecycle.apply_impulse(Vector3.RIGHT,2,76).ok,"other actor still owns its accepted current-tick slot after teammate recreation")
	lifecycle.reset_peer(2)
	_check(lifecycle.snapshot().position_m==0.6 and lifecycle.snapshot().velocity_mps==1.0,"clearing both unconsumed inputs preserves already integrated physical inertia")
	var coarse = _new_axis(0.1,1.0)
	var fine = _new_axis(0.1,1.0)
	coarse.advance(0.2)
	for unused in range(20): fine.advance(0.01)
	_check(absf(float(coarse.snapshot().position_m)-float(fine.snapshot().position_m))<1e-12 and absf(float(coarse.snapshot().velocity_mps)-float(fine.snapshot().velocity_mps))<1e-12,"analytic damped integration is partition consistent away from collisions")
	print("V3_GUIDED_AXIS_TESTS "+JSON.stringify({"checks":checks,"failures":failures,"scope":"pure axis rules; collision approval tested separately by real Waterworks"}))
	quit(0 if failures.is_empty() else 1)

func _float32_impulse_boundary() -> void:
	# Actual CASE2: production Rules normalizes target-actor, reverses for pull,
	# then multiplies by 9. Do not move the QA actor to a more convenient angle.
	var actor := Vector3(-10, 7, -2.5)
	var opened_target := Vector3(-6.8, 7, -5)
	var direction: Vector3 = (opened_target - actor).normalized()
	direction = -direction
	var impulse: Vector3 = direction * 9.0
	_check(impulse.length_squared() > 81.00001 and impulse.length_squared() < 81.00003,
		"real float32 opened-valve pull reproduces original squared-length rejection")
	var axis = _new_axis()
	var before: Dictionary = axis.snapshot()
	_check(axis.can_accept(impulse, 1, 1).ok and axis.snapshot() == before,
		"legal actual CASE2 pull passes read-only approval despite float32 rounding")
	_check(axis.apply_impulse(impulse, 1, 1).ok and absf(float(axis.snapshot().velocity_mps) - float(impulse.x) / 2.0) < 1e-12,
		"approved actual pull commits the genuine projected impulse")
	axis.advance(1.0 / 60.0)
	_check(float(axis.snapshot().position_m) < 0.6 and float(axis.snapshot().velocity_mps) < 0.0,
		"accepted actual pull moves inward along the unchanged physical axis")
	var invalid_axis = _new_axis()
	before = invalid_axis.snapshot()
	for magnitude in [9.00001, 9.01]:
		for invalid in [Vector3.RIGHT * magnitude, direction * magnitude]:
			_check(not invalid_axis.can_accept(invalid, 1, 1).ok and not invalid_axis.apply_impulse(invalid, 1, 1).ok
				and invalid_axis.snapshot() == before, "oversized axial/oblique impulse remains atomically rejected at " + str(magnitude))
	# A perpendicular component also counts toward the 3D budget; axis projection
	# must not silently let an oversized full vector through.
	_check(not invalid_axis.apply_impulse(Vector3(9, 0.02, 0), 1, 1).ok and invalid_axis.snapshot() == before,
		"full 3D impulse limit is retained, not just its guided-axis component")
	print("GUIDED_AXIS_FLOAT32_BOUNDARY " + JSON.stringify({"actor":[actor.x,actor.y,actor.z],
		"target":[opened_target.x,opened_target.y,opened_target.z], "impulse":[impulse.x,impulse.y,impulse.z],
		"length_squared":impulse.length_squared(), "limit_squared":81.0,
		"squared_rounding_allowance":81.0 * Axis.IMPULSE_SQUARED_REL_TOL}))
