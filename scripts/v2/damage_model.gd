class_name DamageModelV22
extends RefCounted
## Game balance units, never real weapon/aircraft specifications.
## One mutation produces one receipt. Presentation consumes the receipt only.

const COMPONENT_NAMES = {"hull":"机身", "rotor_left":"左旋翼组", "rotor_right":"右旋翼组", "power":"动力电池", "sensor":"前部传感器"}
const ARMOR_RATIO = {"pulse":0.28, "kinetic":0.48, "lance":0.14, "collision":0.0}

static func create_state(maximum_health: float, armor: float, dimensions: Vector3) -> Dictionary:
	var capacity = maxf(1.0,maximum_health)
	var components = {}
	for id in ["rotor_left","rotor_right","power","sensor"]:
		var hp = capacity*(0.28 if id.begins_with("rotor") else 0.32)
		components[id] = {"health":hp,"maximum":hp}
	return {"health":capacity,"maximum_health":capacity,"armor":maxf(0,armor),"maximum_armor":maxf(0,armor),"dimensions":dimensions,"components":components,"serial":0}

static func hit_regions(dimensions: Vector3) -> Dictionary:
	var width=maxf(.1,dimensions.x);var height=maxf(.1,dimensions.y);var length_m=maxf(.1,dimensions.z)
	# These authored local volumes divide the collision envelope into mechanical
	# regions. A swept hit is tested against them; no random critical-part roll.
	return {
		"rotor_left":AABB(Vector3(-width*.5,-height*.5,-length_m*.5),Vector3(width*.25,height,length_m)),
		"rotor_right":AABB(Vector3(width*.25,-height*.5,-length_m*.5),Vector3(width*.25,height,length_m)),
		"sensor":AABB(Vector3(-width*.25,-height*.5,-length_m*.5),Vector3(width*.5,height,length_m*.22)),
		"power":AABB(Vector3(-width*.25,-height*.5,length_m*.18),Vector3(width*.5,height,length_m*.32)),
		"hull":AABB(Vector3(-width*.25,-height*.5,-length_m*.28),Vector3(width*.5,height,length_m*.46))}

static func hit_region(point: Vector3, direction: Vector3, dimensions: Vector3) -> String:
	if not point.is_finite():return "hull"
	var regions=hit_regions(dimensions)
	var from=point-direction.normalized()*.02
	var to=point+direction.normalized()*dimensions.length()*2.0
	var nearest=INF;var selected="hull"
	for id in regions:
		var box: AABB=regions[id]
		if box.grow(.002).has_point(point):return id
		var intersection: Variant=box.intersects_segment(from,to)
		if intersection is Vector3:
			var distance_m=from.distance_squared_to(intersection)
			if distance_m<nearest:nearest=distance_m;selected=id
	return selected

static func resolve(state: Dictionary, amount: float, local_point: Vector3, local_direction: Vector3, weapon_type="pulse", protection: Dictionary={}) -> Dictionary:
	if state.is_empty() or not is_finite(amount) or amount<=0 or not local_point.is_finite() or not local_direction.is_finite():return {}
	var before=maxf(0,float(state.health))
	if before<=0:return {}
	state.serial=int(state.get("serial",0))+1
	var component=hit_region(local_point,local_direction,state.dimensions)
	var invulnerable=bool(protection.get("invulnerable",false))
	var shield_multiplier=clampf(float(protection.get("shield_multiplier",1.0)),0,1)
	var remaining=0.0 if invulnerable else amount*shield_multiplier
	var shield_absorbed=amount if invulnerable else amount-remaining
	var armor_before=float(state.armor)
	var armor_factor=float(ARMOR_RATIO.get(weapon_type,.28))
	if component.begins_with("rotor"):armor_factor*=.45
	var armor_absorbed=minf(armor_before,remaining*armor_factor)
	state.armor=maxf(0,armor_before-armor_absorbed)
	remaining-=armor_absorbed
	var actual=minf(before,maxf(0,remaining))
	state.health=before-actual
	var part_before=0.0;var part_after=0.0;var part_damage=0.0
	if component!="hull" and state.components.has(component):
		var part:Dictionary=state.components[component]
		part_before=float(part.health)
		part_damage=minf(part_before,actual*(.85 if weapon_type=="lance" else .60))
		part.health=part_before-part_damage
		part_after=float(part.health)
	var killed=before>0 and float(state.health)<=0
	var result="destroyed" if killed else ("component" if part_damage>0 else "hit")
	if actual<=.00001:result="protected" if shield_absorbed>0 else "blocked"
	return {"serial":state.serial,"raw_damage":amount,"damage":actual,"health_before":before,"health":state.health,"max_health":state.maximum_health,"armor_before":armor_before,"armor":state.armor,"max_armor":state.maximum_armor,"armor_absorbed":armor_absorbed,"shield_absorbed":shield_absorbed,"component":component,"component_name":COMPONENT_NAMES[component],"component_damage":part_damage,"component_before":part_before,"component_health":part_after,"component_disabled":part_before>0 and part_after<=0,"killed":killed,"hit_result":result,"weapon_type":weapon_type}

static func impairment(state: Dictionary) -> Dictionary:
	var output={"rotor_damage":0.0,"motor_damage":0.0,"sensor_damage":0.0,"stability":1.0,"thrust":1.0,"power_use":1.0}
	if state.is_empty():return output
	var parts:Dictionary=state.get("components",{})
	var left=_part_loss(parts,"rotor_left");var right=_part_loss(parts,"rotor_right")
	output.rotor_damage=maxf(left,right)
	output.motor_damage=_part_loss(parts,"power")
	output.sensor_damage=_part_loss(parts,"sensor")
	# Partial failure remains recoverable with assisted control. Cargo and manual
	# collective make the lost reserve felt without unexplained random input.
	output.stability=1.0-output.rotor_damage*.22
	output.thrust=1.0-output.rotor_damage*.12-output.motor_damage*.08
	output.power_use=1.0+output.motor_damage*.30
	output["roll_bias"]=(right-left)*.28
	return output

static func _part_loss(parts: Dictionary,id: String) -> float:
	if not parts.has(id):return 0.0
	return clampf(1.0-float(parts[id].health)/maxf(.001,float(parts[id].maximum)),0,1)

static func status_text(state: Dictionary) -> String:
	if state.is_empty():return ""
	var messages:PackedStringArray=[]
	for id in state.components:
		var ratio=float(state.components[id].health)/maxf(.001,float(state.components[id].maximum))
		if ratio<.70:messages.append(COMPONENT_NAMES[id]+("严重受损" if ratio<.30 else "受损"))
	return " · ".join(messages)
