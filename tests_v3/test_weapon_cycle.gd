extends SceneTree
## Pure candidate rule fixtures only. No campaign discovery, actual physics,
## player/Boss HP, Store, LOS ray or normal combat acceptance is claimed.
const Weapon = preload("res://scripts/v3/gameplay/twin_weapon_cycle.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
const DT := 1.0/60.0
var checks := 0
var failures: Array = []

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _context(held: bool = true) -> Dictionary:
	return {"is_authority":true,"held_fire":held,"enabled":true,"paused":false,
		"target_id":"qa_fixture_target","target_valid":true,"line_of_sight":true,"part_open":true}

func _burst(duct: bool = false) -> Dictionary:
	var build: Dictionary = Catalog.default_build("tr01")
	build.slots.weapon = "burst_capacitor"
	if duct: build.slots.utility = "cooling_duct"
	return build

func _run() -> void:
	var pulse := Weapon.new()
	_check(pulse.configure(Catalog.default_build("tr01")).ok,"canonical pulse build configures")
	var p: Dictionary = pulse.snapshot().profile
	_check(p.damage == 9.0 and p.interval_s == .23 and p.charge_s == 0.0 and not p.uses_heat,"V3 pulse 9/.23/no new heat preserved")
	var pulse_shots := 0
	for frame in range(1,31):
		var row: Dictionary = pulse.step(frame,DT,_context())
		if row.has("shot_request"):
			pulse_shots += 1
			_check(row.shot_request.weapon_id == "pulse_base" and row.shot_request.damage == 9.0,"held pulse retains original shot amount")
			pulse.confirm_shot(int(row.shot_request.serial),true)
	_check(pulse_shots == 3 and pulse.snapshot().heat == 0.0,"pulse requests at original tick cadence without heat")
	var blocked_pulse := Weapon.new()
	blocked_pulse.configure(Catalog.default_build("tr01"))
	var invalid: Dictionary = _context()
	invalid.target_valid = false
	_check(not blocked_pulse.step(1,DT,invalid).has("shot_request") and blocked_pulse.snapshot().cooldown_s == .23,"invalid pulse attempt retains existing attempt cooldown")
	_check(not blocked_pulse.step(2,DT,_context()).has("shot_request"),"new valid pulse target cannot bypass attempt cooldown")
	var burst := Weapon.new()
	_check(burst.configure(_burst()).ok,"actual burst weapon ID configures")
	var b: Dictionary = burst.snapshot().profile
	_check(b.damage == 28.0 and b.interval_s == 1.0 and b.charge_s == .7 and b.heat_per_shot == 32.0 and b.heat_capacity == 100.0,"all burst values come from real Catalog")
	var shot: Dictionary = {}
	var early_request := false
	for frame in range(1,43):
		var row: Dictionary = burst.step(frame,DT,_context())
		if frame < 42: early_request = early_request or row.has("shot_request")
		else: shot = row.get("shot_request",{})
	_check(not early_request,"no burst request before 42 ordinary60Hz input steps")
	_check(not shot.is_empty() and burst.snapshot().heat == 0.0 and burst.snapshot().accepted_shots == 0,"charged burst is only an uncommitted request")
	if shot.is_empty(): _finish(); return
	var unchanged: Dictionary = burst.snapshot()
	_check(not burst.step(43,DT,_context()).ok and burst.snapshot() == unchanged,"unconfirmed request blocks a second request")
	_check(burst.confirm_shot(int(shot.serial),false).ok and burst.snapshot().heat == 0.0 and burst.snapshot().cooldown_s == 0.0,"declined original hit costs no burst heat or cooldown")
	_check(not burst.confirm_shot(int(shot.serial),true).ok and burst.snapshot().accepted_shots == 0,"old token cannot later become an accepted shot")
	for frame in range(43,85):
		var row: Dictionary = burst.step(frame,DT,_context())
		if row.has("shot_request"): shot = row.shot_request
	_check(burst.confirm_shot(int(shot.serial),true).ok and burst.snapshot().heat == 32.0 and burst.snapshot().cooldown_s == 1.0 and burst.snapshot().accepted_shots == 1,"accepted original hit commits exactly 32 heat/1s once")
	_check(not burst.confirm_shot(int(shot.serial),true).ok and burst.snapshot().accepted_shots == 1,"duplicate accepted confirmation cannot repeat shot credit")
	for flag: String in ["held_fire","target_valid","line_of_sight","part_open","enabled"]:
		var cycle := Weapon.new()
		cycle.configure(_burst())
		for frame in range(1,31): cycle.step(frame,DT,_context())
		var context: Dictionary = _context()
		context[flag] = false
		_check(not cycle.step(31,DT,context).has("shot_request") and cycle.snapshot().charge_s == 0.0 and cycle.snapshot().heat == 0.0,"release/invalid/LOS/armor/disabled cancels: "+flag)
	var changed := Weapon.new()
	changed.configure(_burst())
	for frame in range(1,31): changed.step(frame,DT,_context())
	var new_target: Dictionary = _context()
	new_target.target_id = "qa_other_target"
	_check(not changed.step(31,DT,new_target).has("shot_request") and is_equal_approx(changed.snapshot().charge_s,DT),"changed target starts fresh charge")
	var native_guard := Weapon.new()
	native_guard.configure(_burst(),50.0,.8)
	var paused: Dictionary = _context()
	paused.paused = true
	native_guard.step(1,DT,paused)
	_check(native_guard.snapshot().heat == 50.0 and native_guard.snapshot().cooldown_s == .8 and native_guard.snapshot().charge_s == 0.0,"pause freezes heat/cooldown and cancels transient charge")
	var frozen: Dictionary = native_guard.snapshot()
	_check(not native_guard.step(1,DT,_context()).ok and native_guard.snapshot() == frozen,"same physics frame cannot advance twice")
	var guest: Dictionary = _context()
	guest.is_authority = false
	_check(not native_guard.step(2,DT,guest).ok and native_guard.snapshot() == frozen,"non-authority cannot advance/request/consume state")
	var normal := Weapon.new()
	var duct := Weapon.new()
	normal.configure(_burst(),50.0)
	duct.configure(_burst(true),50.0)
	for frame in range(1,61):
		normal.step(frame,DT,_context(false))
		duct.step(frame,DT,_context(false))
	_check(is_equal_approx(normal.snapshot().heat,34.0) and is_equal_approx(duct.snapshot().heat,30.0),"real cooling duct yields 20/s versus base16/s")
	var overheat := Weapon.new()
	overheat.configure(_burst(),100.0)
	var hot_request := false
	for frame in range(1,100):
		var row: Dictionary = overheat.step(frame,DT,_context())
		hot_request = hot_request or row.has("shot_request")
	_check(not hot_request,"overheat never fires above recovery threshold")
	_check(overheat.snapshot().overheated and overheat.snapshot().heat > 40.0,"V2 overheat recovery remains below 40 percent")
	for frame in range(100,228): overheat.step(frame,DT,_context(false))
	_check(not overheat.snapshot().overheated and overheat.snapshot().heat < 40.0,"ordinary cooling really clears V2 overheat only below40percent")
	var gap := Weapon.new()
	gap.configure(_burst())
	for frame in range(1,31): gap.step(frame,DT,_context())
	_check(not gap.step(45,DT,_context()).has("shot_request") and is_equal_approx(gap.snapshot().charge_s,DT),"unobserved physics gap gives no charge credit")
	_finish()

func _finish() -> void:
	print("WEAPON_CYCLE_CANDIDATE_RESULT "+JSON.stringify({"checks":checks,"failures":failures,
		"scope":"Pure explicit rule fixtures; not real combat/physics/Store evidence."}))
	quit(0 if failures.is_empty() else 1)
