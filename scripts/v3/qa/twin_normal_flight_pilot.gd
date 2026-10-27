extends "res://scripts/v3/gameplay/canal/canal_transport_physics/transport_pilot.gd"
## Unloaded QA flight commands only. Retains the original actual-inertia,
## full hull, stopping-distance and candidate-speed probes. Never sets poses,
## forces, velocity, stats, damage, clocks or cargo. Production transport stays
## at its original1.8m/s; the real aircraft's assisted command handles motion.
const FLIGHT_SPEED := 6.0
const VERTICAL_SPEED := 3.0

func tick(delta: float, host_authority: bool = true, suspended: bool = false) -> Dictionary:
	var original: Dictionary = super.tick(delta,host_authority,suspended)
	if not host_authority or suspended or not is_finite(delta) or delta<=0.0 or delta>.1 or not is_instance_valid(body) or not body.enabled or not body.cargo_items.is_empty() or mode!="route" or state!="traveling" or not speed_plan.get("commanded",false): return original
	var offset: Vector3 = target-body.global_position
	var desired: Vector3 = Vector3(offset.x,0,offset.z).limit_length(minf(FLIGHT_SPEED,float(body.stats.speed_mps)))
	var vertical: float = clampf(offset.y*1.2,-minf(VERTICAL_SPEED,float(body.stats.fall_mps)),minf(VERTICAL_SPEED,float(body.stats.rise_mps)))
	speed_plan = _select_velocity(Vector3(desired.x,vertical,desired.z))
	last_probe = speed_plan.probe
	if not last_probe.clear:
		state="blocked"
		clear_seconds=0.0
		settled_seconds=0.0
		_brake()
		return report()
	var selected: Vector3 = speed_plan.selected_velocity
	body.hold_height=body.global_position.y+selected.y*.5
	var rise: float = float(body.stats.rise_mps if selected.y>=0 else body.stats.fall_mps)
	body.command={"active":true,"mode":"assisted","body_relative":false,
		"planar":Vector3(selected.x,0,selected.z)/float(body.stats.speed_mps),
		"vertical":selected.y/rise,"yaw":0.0,"brake":false,"fire":false}
	speed_plan.commanded=true
	return report()
