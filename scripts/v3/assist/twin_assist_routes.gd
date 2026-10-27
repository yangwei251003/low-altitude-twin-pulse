extends RefCounted
## Product route geometry. These are destinations and intended normal actions,
## never actor poses or completed objectives. Original collision/Rules decide.
const CanalAdapter = preload("res://scripts/v3/gameplay/twin_canal_session.gd")
const CanalRules = CanalAdapter.Assembly.Runtime
const CanalBench = CanalAdapter.Assembly.Workbench
const ISOLATION := "I2:trial_isolation_handle"
const GAUGE_A := "I2:trial_gauge_a"
const GAUGE_B := "I2:trial_gauge_b"
const BRIEF_TARGET := "I2:canal_briefing"
const DISPATCH_TARGET := "I2:canal_dispatch"
const Cargo = preload("res://scripts/v3/gameplay/twin_thermal_cargo_session.gd")
const Pump = preload("res://scripts/v3/gameplay/twin_pump_guardian_mechanisms.gd")
var session: Node
var body: FlightBodyV2
func setup(owner_session: Node, local_body: FlightBodyV2) -> void:
	session = owner_session
	body = local_body
func _body() -> FlightBodyV2: return body
func _v(value: Variant) -> Vector3:
	if value is Vector3: return value
	if value is Array and value.size() == 3: return Vector3(value[0], value[1], value[2])
	return Vector3.INF
func _target_position(id: String) -> Vector3:
	var value: Variant = session.entities.get(id, {}).get("position")
	if value is Vector3: return value
	return _v(session.story.markers.get(id, {}).get("position"))

func build(goal: Dictionary) -> Array:
	var id := str(goal.get("id", ""))
	var region := id.get_slice(":", 0)
	var steps: Array = []
	match id:
		"I1:rescue:channel":
			steps = [flight([Vector3(-14,3.3,32),Vector3(-13,3,22)]), cast("I1:relay","charge", "", {"type":"goal"})]
		"I1:rescue:contact": steps = [flight([Vector3(-16,9.8,22),Vector3(-24,9.8,21.2),Vector3(-24,7.2,21.2)])]
		"I1:rescue:evacuate": steps = [flight([Vector3(-24,9.8,21.2),Vector3(-16,9.8,32),Vector3(-20,3.4,32)])]
		"I1:evidence:trace": steps = [flight([Vector3(-11,3.4,32),Vector3(-11,3.4,14),Vector3(-11,2.6,14)]), contact("I1:burn_trace")]
		"I1:evidence:engineer": steps = [flight([Vector3(-9,2.6,18)]),contact("npc:ruanheng")]
		"I1:evidence:ledger": steps = [flight([Vector3(-16,9.8,25),Vector3(-21,9.8,25),Vector3(-21,6.8,25)]),contact("I1:energy_ledger")]
		"I1:evidence:echo": steps = [flight([Vector3(-16,9.8,32),Vector3(26.5,9.8,32),Vector3(26.9,5,32)]),contact("I1:beacon_echo")]
		"F1:needs:listen", "F1:repair:plan": steps = [flight([Vector3(-27.2,7.5,32),Vector3(-27.2,2.7,31)]),contact("npc:atai")]
		"F1:needs:nursery": steps = [flight([Vector3(-18.5,3.3,31)]),contact("F1:dry_nursery")]
		"F1:needs:route": steps = [flight([Vector3(13,7,32),Vector3(13,4.7,32)])]
		"F1:repair:light": steps = [flight([Vector3(-24,5.2,29)]),cast("F1:mirror","light","",{"type":"angle","target":"F1:mirror","value":0.0})]
		"F1:repair:grow": steps = [flight([Vector3(-18,6.4,29)]),cast("F1:growth","growth","",{"type":"goal"})]
		"F1:repair:confirm": steps = [flight([Vector3(-16,9.8,32),Vector3(26.5,9.8,32),Vector3(26.9,5,32)]),contact("F1:shared_junction")]
		"I1:whale:brief": steps = [flight([Vector3(-16,11.8,body.global_position.z),Vector3(-16,11.8,-14.5),Vector3(-9,6.2,-14.5)]),contact("I1:whale_briefing")]
		"I1:whale:engage", "I1:whale:disable": steps = [{"kind":"boss", "region":"I1"}]
		"I1:whale:record":
			var point: Vector3 = session.world.whale_record_position()
			steps = [approach(point+Vector3(0,1.2,2),14),contact("I1:whale_raw_record")]
		"F1:crown:brief": steps = [flight([Vector3(body.global_position.x,12.2,body.global_position.z),Vector3(-18,12.2,8),Vector3(0,12.2,1)]),contact("F1:crown_briefing")]
		"F1:crown:engage", "F1:crown:disable": steps = [{"kind":"boss", "region":"F1"}]
		"F1:crown:restore": steps = [visit("F1:crown_recovered",Vector3(0,1.2,2),16),contact("F1:crown_recovered")]
		"I1:underdeck:read", "I1:underdeck:enter", "I1:underdeck:release", "I1:underdeck:traverse": steps = _underdeck_plan(id)
		"I2:clinic_supply:diagnose", "I2:clinic_supply:connect", "I2:clinic_supply:stabilize", "I2:clinic_supply:confirm": steps = _clinic_plan(id)
		"I2:distribution_audit:expose", "I2:distribution_audit:trace", "I2:distribution_audit:share_access": steps = _distribution_plan(id)
		"I2:canal_service:brief", "I2:canal_service:exchange", "I2:canal_service:service", "I2:canal_service:order": steps = _canal_plan(id)
		"F2:mirror_evidence:records": steps = [visit("F2:record_low",Vector3.UP*.1,16),contact("F2:record_low",false),visit("F2:record_high",Vector3.UP*.1,16),contact("F2:record_high",false)]
		"F2:mirror_evidence:archive": steps = [visit("npc:shuyao",Vector3.UP*.1,16),contact("npc:shuyao")]
		"F2:mirror_evidence:light": steps = [visit("F2:clock_mirror",Vector3(3.5,1.8,2),16),cast("F2:clock_mirror","light","",{"type":"angle","target":"F2:clock_mirror","value":PI/4.0})]
		"F2:mirror_evidence:decision":
			# This console is only two metres from Shuyao. Stay over the
			# console itself so the original nearest-contact rule selects it.
			steps = [visit("F2:choice_terminal",Vector3.UP*.1,16),{"kind":"choice","target":"F2:choice_terminal"}]
		"I3:cooling_route:exchange": steps = [visit("I3:cooling_valve",Vector3.UP*2.7,16),operate("I3:cooling_valve",{"type":"view","key":"thermal_connected"}),wait_for({"type":"goal"},40)]
		"I3:cooling_route:dock": steps = [{"kind":"cargo"}]
		"F3:separate_network:isolate":
			steps = [visit("F3:nutrient_bridge",Vector3.UP*3.4,15),cast("F3:nutrient_bridge","light"),cast("F3:nutrient_bridge","growth","",entity("F3:nutrient_bridge","growth",1)),visit("F3:signal_breaker",Vector3.UP*3.4,15),operate("F3:signal_breaker",{"type":"position","target":"F3:signal_breaker","value":Vector3(12,7,9)}),cast("F3:signal_hold","echo"),wait_for({"type":"goal"},12)]
		"F3:separate_network:feed": steps = [visit("F3:signal_hold",Vector3.UP*3.4,15),operate("F3:signal_hold",{"type":"latched","target":"F3:signal_hold"}),wait_for({"type":"goal"},240)]
		"I4:array_witness:witness": steps = [visit("I4:witness_source",Vector3(0,2,3),16),cast("I4:witness_source","light","",entity("I4:witness_source","light_level",.5)),wait_for({"type":"goal"},12)]
		"I4:array_witness:brief": steps = [visit("npc:wenxu",Vector3(0,.2,2),18),contact("npc:wenxu")]
		"I4:array_witness:archive": steps = [visit("I4:protocol_archive",Vector3(0,.1,2),18),contact("I4:protocol_archive")]
		"I4:array_witness:shelter": steps = [approach(Vector3(20,12,1.8),16),flight([Vector3(20,12,-.5),Vector3(20,5.6,-.5),Vector3(20,5.6,1.8),Vector3(14,6.4,-3)])]
		"I4:array_witness:isolate": steps = [flight([Vector3(12,maxf(6.4,body.global_position.y),-3),Vector3(12,6.4,-3)]),operate("I4:defence_breaker",{"type":"position","target":"I4:defence_breaker","value":Vector3(14,5.2,-.5)}),approach(Vector3(-6,9,-3),12),cast("I4:civilian_feed","charge","",entity("I4:civilian_feed","charge",20))]
		"F4:vein_reunion:industry": steps = [approach(Vector3(-12,11,9),20),operate("F4:limited_bus",{"type":"position","target":"F4:limited_bus","value":Vector3(-12,9,6)}),cast("F4:limited_bus","charge","",entity("F4:limited_bus","charge",20)),approach(Vector3(-12,11,15),20),cast("F4:lifeline_bus","charge","",entity("F4:lifeline_bus","charge",20))]
		"F4:vein_reunion:council": steps = [visit("npc:guanzhi",Vector3(0,.2,2),20),contact("npc:guanzhi")]
		"F4:vein_reunion:living": steps = [approach(Vector3(5,15,9),20),cast("F4:living_emitter","light","",{"type":"emitter_aligned","target":"F4:living_emitter"}),approach(Vector3(14,15.5,9),20),cast("F4:living_support","growth","",entity("F4:living_support","growth",1))]
		"F4:vein_reunion:test": steps = [approach(Vector3(10,17.5,-2.5),20),operate("F4:test_hold",{"type":"latched","target":"F4:test_hold"}),wait_for({"type":"load_test"},12),approach(Vector3(15,17.4,-3),20),contact("F4:industrial_gauge",false),approach(Vector3(21,17.4,-3),20),contact("F4:living_gauge",false)]
		"F4:vein_reunion:plan": steps = [visit("F4:choice_terminal",Vector3(0,.5,2),20),{"kind":"choice", "target":"F4:choice_terminal", "review":true}]
		_:
			if id.ends_with(":decision"):
				steps = [visit(region+":choice_terminal",Vector3(0,.5,2),_altitude(region)),{"kind":"choice", "target":region+":choice_terminal"}]
			elif id.ends_with(":engage") or id.ends_with(":stop"):
				if not session.boss_active: steps.append_array(boss_preparation(region))
				steps.append({"kind":"boss", "region":region})
			else:
				var events: Array = goal.get("events",[])
				if not events.is_empty():
					var target := str(events[0].get("target_id",""))
					if id.ends_with(":plan") and ":boss_briefing" in target:
						steps.append_array(boss_preparation(region))
					var offset := Vector3(0,1.6,1)
					if target.ends_with(":boss_briefing") and region in ["I4","F4"]: offset = Vector3(0,.2,1.6)
					steps.append(visit(target,offset,_altitude(region)))
					if str(events[0].get("type")) != "reach": steps.append(contact(target))
	steps.append(wait_for({"type":"goal"},30))
	return steps

func gate(region: String) -> Array:
	if region == "I1": return [flight([Vector3(-16,9.8,32),Vector3(26.5,9.8,32),Vector3(26.9,5,32)]),{"kind":"gate"}]
	if region == "F1": return [flight([Vector3(-16,9.8,32),Vector3(26.5,9.8,32),Vector3(26.9,5,32)]),cast("F1:beacon","takeover","",{"type":"entity_bool","target":"F1:beacon","key":"controlled"}),{"kind":"gate"}]
	return []

func boss_preparation(region: String) -> Array:
	match region:
		"I2":
			var at := _target_position(Pump.PLUG)
			var start: Vector3 = body.global_position
			var points: Array = []
			# The dispatch record is below the real bridge. Leave by its same
			# open aisle before climbing; a direct ascent would meet the deck.
			if start.y < 6.5 and start.x > 8 and start.x < 22 and start.z > -2 and start.z < 15:
				points.append_array([Vector3(start.x,start.y,1.9),Vector3(3.5,start.y,1.9)])
				start = Vector3(3.5,start.y,1.9)
			points.append(Vector3(start.x,12,start.z))
			if start.z>0: points.append_array([Vector3(-23,12,start.z),Vector3(-23,12,-17)])
			points.append_array([Vector3(at.x,12,-17),Vector3(at.x,12,at.z),at+Vector3.UP*3.4])
			return [flight(points),operate(Pump.PLUG,{"type":"position","target":Pump.PLUG,"value":Pump.PLUG_OPEN})]
		"F2": return [visit("F2:reveal_source",Vector3(0,2,3),18),cast("F2:reveal_source","light","",entity("F2:reveal_source","light_level",.5))]
		"I3": return [approach(Vector3(-5,10,-17),16),cast("I3:boss_radiator","heat","cool",entity("I3:boss_radiator","temperature",35,false))]
		"F4": return [approach(Vector3(-7.5,15.5,-24.5),20),operate("F4:core_charge_breaker",{"type":"position","target":"F4:core_charge_breaker","value":Vector3(-5,14,-24.5)}),approach(Vector3(0,16,-17),20),cast("F4:core_thermal_sink","heat","cool",entity("F4:core_thermal_sink","temperature",35,false)),approach(Vector3(5,16,-23),20),cast("F4:core_living_support","light"),cast("F4:core_living_support","growth","",entity("F4:core_living_support","growth",1))]
	return []

func _underdeck_plan(id: String) -> Array:
	var r := underdeck()
	if r.is_empty(): return []
	var ingress: Array = [approach(r.log_approach,14),flight([r.south_east,r.side_align,r.side_outside,r.side_inside,r.side_lower,r.turn_overlap,r.turn_low])]
	var at: Vector3=body.global_position
	var inside := false
	for space: Dictionary in session.world.underdeck.layout().get("voids",[]):
		var low:=_v(space.min)
		var high:=_v(space.max)
		if at.x>=low.x and at.x<=high.x and at.y>=low.y and at.y<=high.y and at.z>=low.z and at.z<=high.z: inside=true
	# Entry is earned while still in the side duct. Keep the common height
	# until the whole hull reaches the main corridor before descending.
	var settle: Array=[flight([r.turn_low])]
	if inside and absf(at.x-float(r.turn_low.x))>.7:
		settle=[flight([Vector3(at.x,float(r.overlap_centre_y),at.z),Vector3(at.x,float(r.overlap_centre_y),float(r.turn_overlap.z)),r.turn_overlap,r.turn_low])]
	match id.get_slice(":",2):
		"read": return [approach(r.log_approach,14),contact("I1:underdeck_log")]
		"enter": return ingress
		"release": return (settle if inside else ingress)+[cast("I1:underdeck_latch","echo","",{"type":"goal"})]
		"traverse": return (settle if inside else ingress)+[wait_for({"type":"underdeck_open"},12),flight([r.north_inside,r.north_outside])]
	return []

func _clinic_plan(id: String) -> Array:
	var r := clinic()
	if r.is_empty(): return []
	var front: Vector3 = r.south_opening
	var enter: Array = [approach(front,float(r.external_altitude)),flight([r.check])]
	match id.get_slice(":",2):
		"diagnose": return enter+[contact("I2:clinic_demand")]
		"connect": return [flight([front]),approach(r.valve_approach,float(r.external_altitude)),cast("I2:clinic_gravity_valve","push_pull","",{"type":"clinic_connected"})]
		"stabilize": return [flight([r.valve_overhead])]+enter+[wait_for({"type":"goal"},300)]
		"confirm": return enter+[contact("I2:clinic_water_check")]
	return []

func _distribution_plan(id: String) -> Array:
	var r := distribution()
	if r.is_empty(): return []
	var west := float(r.west_airlane_x)
	match id.get_slice(":",2):
		"expose": return [approach(r.east_airlane,float(r.external_altitude)),flight([r.east_device_candidates[0]]),cast("I2:distribution_relay","charge","",entity("I2:distribution_relay","charge",20)),cast("I2:distribution_lock","takeover","",{"type":"cabinet_open"}),wait_for({"type":"cabinet_open"},15),flight([r.east_airlane,r.front,r.inside]),contact("I2:distribution_back_exposed")]
		"trace":
			var handle: Vector3 = _target_position(ISOLATION)+Vector3(-2.8,1.25,2.7)
			return [flight([r.front,Vector3(west,2.8,-5),handle]),cast(ISOLATION,"push_pull","",{"type":"trial_ready"}),wait_for({"type":"trial_ready"},15),flight([Vector3(west,2.8,-5),Vector3(west,2.8,r.station_front_z),Vector3(r.trial_control.x,2.8,r.station_front_z),r.trial_control]),cast("I2:trial_relay","charge","",entity("I2:trial_relay","charge",20)),cast("I2:trial_controller","takeover","",{"type":"trial_samples"}),wait_for({"type":"trial_samples"},45),flight([r.gauge_A]),contact(GAUGE_A,false),flight([r.gauge_B]),contact(GAUGE_B,false)]
		"share_access": return [flight([Vector3(west,body.global_position.y,r.station_front_z),Vector3(west,2.8,-5)]),approach(r.bridge_inspection,float(r.external_altitude)),cast("I2:shared_bridge_relay","charge","",entity("I2:shared_bridge_relay","charge",20)),cast("I2:shared_bridge_service_control","takeover","",{"type":"bridge_locked"}),wait_for({"type":"bridge_locked"},20),{"kind":"choice","target":"I2:shared_bridge_service_control","facility":true}]
	return []

func _canal_plan(id: String) -> Array:
	var r := canal()
	if r.is_empty(): return []
	var west: Vector3 = r.west_service_view
	var south := Vector3(west.x,3.2,r.south_approach_z)
	var ctx: Dictionary = session.canal.context()
	match id.get_slice(":",2):
		"brief": return [visit(BRIEF_TARGET,Vector3(0,.2,1.2),8),contact(BRIEF_TARGET)]
		"exchange":
			var cassette: Node3D = ctx.cargos[CanalRules.CASSETTES[1]]
			# The shallow west view clips WestPier1 once the hull yaws toward
			# the cartridge. Keep the complete rotated hull south of that pier.
			return [flight([south,Vector3(west.x,2.8,9.5),cassette.global_position+Vector3(-3.2,2.55,2)]),cast(CanalRules.CASSETTES[1],"heat","cool",{"type":"canal_cold"}),wait_for({"type":"goal"},20)]
		"service":
			var carrier: Vector3 = ctx.carrier.global_position+Vector3(-3.5,1,0)
			return [flight([south,Vector3(carrier.x,carrier.y,r.south_approach_z),carrier]),cast(CanalAdapter.Assembly.CARRIER_ID,"takeover","",{"type":"canal_ordered"}),flight([south,Vector3(west.x,3.2,west.z),west]),cast(CanalBench.POWER_ID,"charge","",entity(CanalBench.POWER_ID,"charge",20)),wait_for({"type":"canal_credit"},420),contact(CanalBench.POWER_ID)]
		"order":
			var dispatch: Vector3 = r.dispatch_candidates[0]
			var points: Array = []
			if body.global_position.x < west.x-1.0: points.append(south)
			# Cross the open aisle between the real bridge piers, then turn
			# toward the record. A direct eastward line intersects WestPier1.
			points.append_array([Vector3(west.x,3,1.9),Vector3(dispatch.x,dispatch.y,1.9),dispatch])
			return [flight(points),contact(DISPATCH_TARGET)]
	return []

static func flight(points: Array) -> Dictionary: return {"kind":"flight", "points":points}
static func approach(point: Vector3, height: float = 15.0) -> Dictionary: return {"kind":"approach", "point":point, "height":height}
static func visit(target: String, offset: Vector3 = Vector3(0,1.6,1), height: float = 15.0) -> Dictionary: return {"kind":"visit", "target":target, "offset":offset, "height":height}
static func contact(target: String, completes_goal: bool = true) -> Dictionary: return {"kind":"contact", "target":target, "goal":completes_goal}
static func cast(target: String, ability: String, mode: String = "", condition: Dictionary = {}) -> Dictionary: return {"kind":"ability", "target":target, "ability":ability, "mode":mode, "condition":condition}
static func operate(target: String, condition: Dictionary = {}) -> Dictionary: return {"kind":"operate", "target":target, "condition":condition}
static func wait_for(condition: Dictionary, seconds: float) -> Dictionary: return {"kind":"wait", "condition":condition, "timeout":seconds}
static func entity(target: String, key: String, value: float, above: bool = true) -> Dictionary: return {"type":"entity_gte" if above else "entity_lte", "target":target, "key":key, "value":value}
static func _altitude(region: String) -> float: return float({"I1":12,"F1":15,"I2":12,"F2":18,"I3":16,"F3":15,"I4":18,"F4":20}.get(region,15))

func underdeck() -> Dictionary:
	var layout: Dictionary = session.world.underdeck.layout()
	if layout.get("id")!="i1_underdeck_layout_v1": return {}
	var anchors: Dictionary = layout.get("anchors",{})
	var log_at: Vector3 = _v(anchors.get("inspection_log"))
	var side: Vector3 = _v(anchors.get("side_entry"))
	var entry: Vector3 = _v(anchors.get("entry"))
	var exit: Vector3 = _v(anchors.get("exit"))
	if not log_at.is_finite() or not side.is_finite() or not entry.is_finite() or not exit.is_finite(): return {}
	var main_void: Dictionary = {}
	var side_void: Dictionary = {}
	for space: Dictionary in layout.get("voids",[]):
		if space.get("id")=="main_corridor": main_void=space
		if space.get("id")=="side_duct": side_void=space
	if main_void.is_empty() or side_void.is_empty(): return {}
	var overlap_low: float = maxf(_v(main_void.min).y,_v(side_void.min).y)
	var overlap_high: float = minf(_v(main_void.max).y,_v(side_void.max).y)
	if not is_finite(overlap_low) or not is_finite(overlap_high) or overlap_low>=overlap_high: return {}
	var overlap_y: float = (overlap_low+overlap_high)*.5
	var outside_x: float = side.x+3.0
	var log_approach := Vector3(log_at.x,entry.y,log_at.z+1.2)
	# The shell is the union of all authored voids, including turning_chamber.
	# Use the narrower common main/side Y band for this conservative transition:
	# descend while still in the side duct, move sideways, then descend in main.
	return {"log_approach":log_approach,"south_east":Vector3(outside_x,entry.y,log_approach.z),
		"side_align":Vector3(outside_x,side.y,log_approach.z),"side_outside":Vector3(outside_x,side.y,side.z),
		"side_inside":Vector3(side.x-3.0,side.y,side.z),"side_lower":Vector3(side.x-3.0,overlap_y,side.z),
		"turn_overlap":Vector3(entry.x,overlap_y,side.z),"turn_low":Vector3(entry.x,entry.y,side.z),
		"north_inside":Vector3(exit.x,exit.y,exit.z+3.0),"north_outside":Vector3(exit.x,exit.y,exit.z-3.0),
		"overlap_low_y":overlap_low,"overlap_high_y":overlap_high,"overlap_centre_y":overlap_y,"anchors":anchors}


func clinic() -> Dictionary:
	var layout: Dictionary = session.clinic.module.layout()
	if layout.get("id")!="i2_clinic_waterworks_v1": return {}
	var solids: Dictionary = {}
	var roof_top := 0.0
	for solid: Dictionary in layout.get("fixed_solids",[]):
		solids[str(solid.id)]=solid
		roof_top=maxf(roof_top,_v(solid.max).y)
	for id: String in ["ClinicCanopyLeft","ClinicCanopyRight","EastLanding","GravityClosedStop"]:
		if not solids.has(id): return {}
	var left: Dictionary = solids.ClinicCanopyLeft
	var right: Dictionary = solids.ClinicCanopyRight
	var landing: Dictionary = solids.EastLanding
	var stop: Dictionary = solids.GravityClosedStop
	var check_at: Vector3 = _v(layout.anchors.water_check)
	var valve_at: Vector3 = _v(layout.gravity_valve.center)
	if not check_at.is_finite() or not valve_at.is_finite(): return {}
	var gap_low: float = _v(left.max).x
	var gap_high: float = _v(right.min).x
	var floor_y: float = _v(landing.max).y
	var canopy_y: float = minf(_v(left.min).y,_v(right.min).y)
	var projected_half := Vector3(float(_body().stats.width_m),float(_body().stats.height_m),float(_body().stats.length_m))*.5+Vector3.ONE*.19
	var check_y: float = check_at.y+.2
	if gap_high-gap_low<=projected_half.x*2.0 or check_y-projected_half.y<=floor_y or check_y+projected_half.y>=canopy_y: return {}
	var check := Vector3((gap_low+gap_high)*.5,check_y,check_at.z)
	var front := Vector3(check.x,check.y,_v(landing.max).z+2.5)
	var altitude: float = minf(_body().max_altitude,roof_top+3.0)
	if altitude<=roof_top+projected_half.y: return {}
	# Pure west is occluded by the real closed end-stop. Derive a south offset
	# whose ray is outside its z-max at the stop's closest-to-valve x face.
	var west_dx := 2.5
	var stop_dx: float = valve_at.x-_v(stop.max).x
	if stop_dx<=0.0: return {}
	var south_offset: float = maxf(2.5,(_v(stop.max).z-valve_at.z+.08)*west_dx/stop_dx+.12)
	var approach := Vector3(valve_at.x-west_dx,valve_at.y,valve_at.z+south_offset)
	return {"check":check,"south_opening":front,"external_altitude":altitude,
		"valve_approach":approach,"valve_overhead":Vector3(approach.x,altitude,approach.z),
		"south_gap_x":[gap_low,gap_high],"landing_top_y":floor_y,"canopy_bottom_y":canopy_y,
		"actual_valve_anchor":valve_at,"actual_closed_stop":stop,"gap_half_extent_with_margin":projected_half}


func distribution() -> Dictionary:
	var layout: Dictionary = session.distribution.module.layout()
	if layout.get("id")!="i2_distribution_cabinet_v1": return {}
	var origin: Vector3 = _v(layout.origin)
	var opening: Dictionary = layout.observation.door_opening
	var interior: Dictionary = layout.observation.interior
	var low: Vector3 = _v(interior.min)
	var high: Vector3 = _v(interior.max)
	var half: Vector3 = Vector3(float(_body().stats.width_m),float(_body().stats.height_m),float(_body().stats.length_m))*.5+Vector3.ONE*.19
	var center_y: float = clampf(2.8,low.y+half.y+.1,high.y-half.y-.1)
	var middle_x: float = (_v(opening.min).x+_v(opening.max).x)*.5
	if high.y-low.y<=half.y*2.0+.2 or _v(opening.max).x-_v(opening.min).x<=half.x*2.0+.2: return {}
	var inside: Vector3 = origin+Vector3(middle_x,center_y,0)
	var front: Vector3 = origin+Vector3(middle_x,center_y,5)
	var isolation: Variant = session.trial.module.entity_position(ISOLATION)
	if not isolation is Vector3 or not isolation.is_finite(): return {}
	var gauge_a: Vector3 = _v(session.story.markers.get(GAUGE_A,{}).get("position"))
	var gauge_b: Vector3 = _v(session.story.markers.get(GAUGE_B,{}).get("position"))
	var inspect: Vector3 = session.shared_access.inspection_position("service_span",float(_body().stats.height_m)*.5)
	if not gauge_a.is_finite() or not gauge_b.is_finite() or not inspect.is_finite(): return {}
	var altitude: float = minf(float(_body().max_altitude),11.0)
	if altitude<inspect.y+half.y+.2: return {}
	return {"inside":inside,"front":front,"east_airlane":Vector3(origin.x+5,center_y,origin.z+5),
		"east_device_candidates":[Vector3(origin.x+5,center_y,origin.z+2.8),Vector3(origin.x+4.6,center_y+.3,origin.z+3.3)],
		# Native ray/sweep query proved the shallow west views hit HandleStop-1.
		# A wider south angle clears its complete box and still gives +X impulse.
		"isolation_reference":isolation,"isolation_candidate_offsets":[Vector3(-2.8,1.25,2.7),Vector3(-2.8,1.4,3.1),Vector3(-3.2,1.25,3.1)],
		"west_airlane_x":origin.x-3.2,"station_front_z":1.2,"trial_control":Vector3(18,2.6,1.2),
		"gauge_A":gauge_a+Vector3(-.75,.85,3.93),"gauge_B":gauge_b+Vector3(.75,.85,3.93),
		"bridge_inspection":inspect,"external_altitude":altitude,"aircraft_half_extent_with_margin":half,
		"layout_origin":origin,"door_opens_direction":"UP","door_opening":opening,"interior":interior,
		"gauge_note":"Lateral readings keep the nearer return switch from receiving G; actual nearest is rechecked."}


func canal() -> Dictionary:
	var ctx: Dictionary = session.canal.context()
	if ctx.is_empty() or ctx.get("rules")==null or ctx.get("custody")==null or not is_instance_valid(ctx.get("workbench")): return {}
	var work: Variant = ctx.berths.get(CanalRules.WORK)
	var south0: Variant = ctx.berths.get(CanalRules.SOUTH_0)
	var south1: Variant = ctx.berths.get(CanalRules.SOUTH_1)
	var hot: Variant = ctx.cargos.get(CanalRules.CASSETTES[1])
	if not work is StaticBody3D or not south0 is StaticBody3D or not south1 is StaticBody3D or not hot is RigidBody3D: return {}
	var power: Vector3 = ctx.workbench.power_target.global_position
	var west: Vector3 = power+Vector3(-1.6,1.75,0)
	var brief: Vector3 = _v(session.story.markers.get(BRIEF_TARGET,{}).get("position"))
	var dispatch: Vector3 = _v(session.story.markers.get(DISPATCH_TARGET,{}).get("position"))
	if not brief.is_finite() or not dispatch.is_finite() or not power.is_finite() or west.y>=_body().max_altitude: return {}
	return {"work_berth":work.global_position,"work_cassette_initial_native":hot.global_position,"power_actual":power,"west_service_view":west,
		"south_approach_z":maxf(south0.global_position.z,south1.global_position.z)-6.0,
		"brief_actual":brief,"dispatch_actual":dispatch,
		"cooling_offsets":[Vector3(-2.8,2.35,1),Vector3(-3.0,2.35,2),Vector3(-3.2,2.55,1)],
		"carrier_offsets":[Vector3(-3.5,1,0),Vector3(-4,1.2,.8),Vector3(-3.5,1.5,-.8)],
		"dispatch_candidates":[dispatch+Vector3(1.5,0,0)],
		"canonical_namespace":CanalAdapter.IDS.duplicate()}

