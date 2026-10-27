extends SceneTree
## Owner-run, headless field probe. No import, rendering, or file writes.
const Field = preload("res://scripts/v2/environment_field.gd")
var failures: Array[String] = []
var count = 0

func check(condition: bool, description: String) -> void:
	count+=1
	if not condition: failures.append(description)

func advance_to(field: RefCounted, wanted: String, maximum_s: float) -> bool:
	for i in ceili(maximum_s/.1):
		if field.event_phase==wanted: return true
		field.advance(.1)
	return field.event_phase==wanted

func _initialize() -> void:
	var settings={"environment_preset":"standard","environment_wind":1.0,"environment_weather":1.0,"environment_interference":1.0}
	for region in ["R1","R2","R3","R4"]:
		var field=Field.new();field.configure(region,2214,settings)
		var definition=field.event_definition();var center: Vector3=definition.center
		var outside=center+Vector3(float(definition.radius)+15,0,0)
		var ordinary: Vector3=field.sample(outside).wind_velocity
		check(ordinary.length()<.15,region+" ordinary air is weak and steady")
		field.set_weather("rain");field.advance(60)
		check(field.sample(outside).wind_velocity.is_equal_approx(ordinary),region+" global weather does not add global force")
		check(field.event_phase=="idle",region+" no encounter before entering local area")
		field.update_focus(center)
		check(advance_to(field,"warning",6),region+" entering starts a seeded warning")
		check(field.event_remaining>=3.0 and field.event_remaining<=5.0,region+" warning lasts 3-5 seconds")
		var before=field.sample(center)
		check(before.wind_velocity.length()<.15 and before.nav_quality==1.0,region+" warning has no force or interference")
		var warning_quiet=true
		while field.event_phase=="warning":
			var warning_sample=field.sample(center)
			warning_quiet=warning_quiet and warning_sample.wind_velocity.length()<.15 and warning_sample.nav_quality==1.0
			field.advance(.1)
		check(warning_quiet,region+" entire warning remains mechanically quiet")
		check(field.event_phase=="active" and field.event_remaining>=6 and field.event_remaining<=12,region+" active phase lasts 6-12 seconds")
		field.advance(1)
		var active=field.sample(center)
		check(active.nav_quality<.9 if region=="R1" else active.wind_velocity.length()>.5,region+" activation changes the local physical field")
		var remote=field.sample(outside)
		check(remote.wind_velocity.is_equal_approx(ordinary) and remote.nav_quality==1.0 and remote.event_phase=="none",region+" outside the area is unaffected")
		field.set_settings({"environment_preset":"calm"})
		var calm=field.sample(center)
		check(calm.nav_quality>active.nav_quality if region=="R1" else calm.wind_velocity.length()<active.wind_velocity.length(),region+" calm lowers encounter intensity")
		field.set_settings({"environment_preset":"standard"})
		var saved=field.snapshot()
		var restored=Field.new();restored.configure(region,2214,settings);restored.restore(saved);restored.update_focus(center)
		check(restored.event_rng.state==field.event_rng.state,region+" snapshot preserves RNG state exactly")
		var same=true
		for i in 170:
			field.advance(.1);restored.advance(.1)
			var a=field.sample(center);var b=restored.sample(center)
			same=same and a.wind_velocity.is_equal_approx(b.wind_velocity) and is_equal_approx(a.nav_quality,b.nav_quality) and field.event_phase==restored.event_phase and is_equal_approx(field.event_remaining,restored.event_remaining)
		check(same,region+" restored event follows the same field and timers")
		check(field.event_phase=="cooldown",region+" completed encounter enters cooldown")
		var remaining=field.event_remaining;var sequence=field.event_sequence
		field.update_focus(outside);field.advance(.5);field.update_focus(center);field.advance(.5)
		check(field.event_sequence==sequence and is_equal_approx(field.event_remaining,remaining-1),region+" leaving and reentering cannot reset cooldown")
		check(field.sample(center).wind_velocity.length()<.15 and field.sample(center).nav_quality==1.0,region+" effect clears during cooldown")
		check(advance_to(field,"active",70),region+" another seeded encounter is possible after cooldown")
		field.advance(1)
		field.set_settings({"environment_interference":0.0} if region=="R1" else {"environment_wind":0.0})
		var disabled=field.sample(center)
		check(disabled.event_phase=="none" and disabled.nav_quality==1 and disabled.wind_velocity.length()<.15,region+" zero custom intensity immediately disables the encounter")
		field.advance(.1)
		check(field.event_phase=="cooldown",region+" disabling an active event keeps cooldown")
	var water=Field.new();water.configure("R3",2214,settings)
	check(water.sample(Vector3(186,1,320)).over_water and not water.sample(Vector3(186,1,320)).water,"Canal footprint differs from submersion")
	check(water.sample(Vector3(186,-1,320)).water,"Water below its plane is immersion")
	check(not water.sample(Vector3(186,-1,300)).over_water,"Road bridge excludes water")
	check(not water.sample(Vector3(386,-1,320)).over_water,"Removed decorative canal is not a water hazard")
	var fan=Field.new();fan.configure("R2",2214,settings);fan.update_focus(Vector3(212,1.8,88))
	check(advance_to(fan,"active",12),"Fan reaches a local active pulse")
	fan.advance(1);fan.fan_enabled=false
	check(fan.sample(Vector3(212,1.8,88)).vent_strength==0.0,"Manual fan stop immediately suppresses the physical pulse")
	var weather=Field.new();weather.configure("R1",2214,settings);weather.set_weather("rain");weather.advance(.1)
	check(weather.rain>0 and weather.rain<.1,"Visual weather starts smoothly")
	for i in 600: weather.advance(.1)
	check(weather.rain>.7 and weather.wetness>.8,"Rain and pavement reach their visual target")
	weather.set_settings({"environment_weather":0.0})
	for i in 1000: weather.advance(.1)
	check(weather.rain<.001 and weather.fog<.001,"Zero weather setting clears rain and fog")
	print(JSON.stringify({"suite":"V22_local_environment_field","checks":count,"failures":failures,"passed":failures.is_empty(),"evidence_scope":"Deterministic analytic field only; not visual, GPU, landing, or human comfort evidence."}))
	quit(0 if failures.is_empty() else 1)
