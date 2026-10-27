extends SceneTree
## Pure settlement and save contracts. No collision or audiovisual claims.
const Damage = preload("res://scripts/v2/damage_model.gd")
const Body = preload("res://scripts/v2/flight_body.gd")
const Enemy = preload("res://scripts/v2/enemy_actor.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
const SIZE = Vector3(2,.6,2)
const SNAPSHOT_EPSILON = 0.0000000001
var checks = 0
var failures: Array[String] = []
var metrics: Dictionary = {}

func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)
	print("V22_DAMAGE_", "PASS " if value else "FAIL ", label)
func close(a: float, b: float) -> bool: return absf(a-b)<.00001

func components_match(expected: Dictionary, actual: Dictionary, label: String) -> bool:
	var valid = expected.size()==actual.size()
	var maximum_error = 0.0
	var values: Array = []
	for id in expected:
		if not actual.has(id) or not actual[id] is Dictionary:
			valid=false
			continue
		var original: Dictionary = expected[id]
		var restored: Dictionary = actual[id]
		if original.size()!=restored.size(): valid=false
		for field in ["health","maximum"]:
			if not original.has(field) or not restored.has(field):
				valid=false
				continue
			var before = float(original[field])
			var after = float(restored[field])
			var error = absf(after-before)
			if not is_finite(before) or not is_finite(after) or error>SNAPSHOT_EPSILON: valid=false
			maximum_error=maxf(maximum_error,error)
			values.append({"component":str(id),"field":field,"before":before,"after":after,"absolute_error":error})
	metrics[label]={"max_absolute_error":maximum_error,"tolerance":SNAPSHOT_EPSILON,"values":values}
	print("V22_DAMAGE_COMPONENT_ROUNDTRIP ",label," ",JSON.stringify(metrics[label],"",true,true))
	return valid

func run() -> void:
	test_conservation()
	test_regions()
	test_components_and_overkill()
	test_round_trip()
	var result = {"suite":"v22_damage","checks":checks,"failures":failures,"ok":failures.is_empty(),"metrics":metrics,"scope":"Pure production DamageModel contracts and aircraft JSON snapshot restoration; no physics, graphics or listening evidence."}
	var output = FileAccess.open("res://artifacts/v22/damage_summary.json",FileAccess.WRITE)
	if output: output.store_string(JSON.stringify(result,"\t",true,true)); output.close()
	print("V22_DAMAGE_SUMMARY ",JSON.stringify(result,"",true,true))
	quit(0 if failures.is_empty() else 1)

func test_conservation() -> void:
	var state = Damage.create_state(100,20,SIZE)
	var hit = Damage.resolve(state,20,Vector3.ZERO,Vector3.BACK,"pulse",{"shield_multiplier":.6})
	check(close(float(hit.damage)+float(hit.armor_absorbed)+float(hit.shield_absorbed),20), "Hull plus armor plus shield equals raw damage before overkill")
	check(close(100-float(state.health),float(hit.damage)), "Actual hull receipt exactly matches authoritative health loss")
	check(close(20-float(state.armor),float(hit.armor_absorbed)), "Armor receipt exactly matches consumed armor")
	check(float(hit.shield_absorbed)>0 and float(hit.armor_absorbed)>0 and float(hit.damage)>0, "Partial shield and finite armor both participate in one settlement")
	check(str(hit.component)=="hull" and float(hit.component_damage)==0, "Central hull hit does not fabricate component damage")
	var serial: int = int(state.serial)
	var before = state.duplicate(true)
	for amount in [-1.0,0.0,NAN,INF]:
		check(Damage.resolve(state,amount,Vector3.ZERO,Vector3.FORWARD).is_empty(), "Invalid amount is rejected: "+str(amount))
	check(Damage.resolve(state,5,Vector3(NAN,0,0),Vector3.FORWARD).is_empty(), "Invalid hit point is rejected")
	check(Damage.resolve(state,5,Vector3.ZERO,Vector3(INF,0,0)).is_empty(), "Invalid direction is rejected")
	check(state==before and int(state.serial)==serial, "Rejected hits neither mutate health nor consume receipt serials")
	var protected = Damage.resolve(state,80,Vector3(-.9,0,0),Vector3.RIGHT,"lance",{"invulnerable":true})
	check(close(float(protected.damage),0) and close(float(protected.shield_absorbed),80) and close(float(protected.armor_absorbed),0), "Invulnerability consumes neither hull nor armor")
	check(close(float(state.components.rotor_left.health),float(before.components.rotor_left.health)), "Invulnerability also protects the genuinely struck component")
	check(not bool(protected.killed) and str(protected.hit_result)=="protected", "Protected receipt cannot claim a kill")
	var scarce = Damage.create_state(100,1,SIZE)
	var depleted = Damage.resolve(scarce,20,Vector3.ZERO,Vector3.FORWARD,"kinetic")
	check(close(float(scarce.armor),0) and close(float(depleted.armor_absorbed),1) and close(float(depleted.damage),19), "Armor cannot absorb more than its remaining capacity")
	var uncovered = Damage.resolve(scarce,10,Vector3.ZERO,Vector3.FORWARD,"kinetic")
	check(close(float(uncovered.damage),10) and close(float(uncovered.armor_absorbed),0), "Depleted armor cannot absorb the next hit")

func test_regions() -> void:
	var regions = [
		["rotor_left",Vector3(-.9,0,0),Vector3.RIGHT],
		["rotor_right",Vector3(.9,0,0),Vector3.LEFT],
		["sensor",Vector3(0,0,-.9),Vector3.BACK],
		["power",Vector3(0,0,.8),Vector3.FORWARD],
		["hull",Vector3.ZERO,Vector3.DOWN]]
	for row in regions:
		var state = Damage.create_state(100,0,SIZE)
		var hit = Damage.resolve(state,10,row[1],row[2],"pulse")
		check(str(hit.component)==str(row[0]), "Authored local contact selects "+str(row[0]))
		if row[0]!="hull":
			check(float(hit.component_damage)>0 and close(float(state.components[row[0]].maximum)-float(state.components[row[0]].health),float(hit.component_damage)), "Only actual "+str(row[0])+" damage changes its health")
			for other in state.components:
				if other!=row[0]: check(close(float(state.components[other].health),float(state.components[other].maximum)), "Hit on "+str(row[0])+" leaves "+str(other)+" intact")
	for row in [["rotor_left",Vector3(-1.2,0,0),Vector3.RIGHT],["rotor_right",Vector3(1.2,0,0),Vector3.LEFT],["sensor",Vector3(0,0,-1.2),Vector3.BACK],["power",Vector3(0,0,1.2),Vector3.FORWARD]]:
		check(Damage.hit_region(row[1],row[2],SIZE)==row[0], "Swept entry selects the nearest real "+str(row[0])+" region")
	var transform = Transform3D(Basis(Vector3.UP,PI*.5),Vector3(200,6,200))
	var local_point = Vector3(-.9,0,0)
	var world_point: Vector3 = transform*local_point
	var world_direction: Vector3 = transform.basis*Vector3.RIGHT
	check(Damage.hit_region(transform.affine_inverse()*world_point,transform.basis.inverse()*world_direction,SIZE)=="rotor_left", "Rotated world-space impact still identifies the aircraft's own left side")

func test_components_and_overkill() -> void:
	var left = Damage.create_state(100,0,SIZE)
	var right = Damage.create_state(100,0,SIZE)
	Damage.resolve(left,30,Vector3(-.9,0,0),Vector3.RIGHT)
	Damage.resolve(right,30,Vector3(.9,0,0),Vector3.LEFT)
	var left_effect = Damage.impairment(left)
	var right_effect = Damage.impairment(right)
	check(float(left_effect.rotor_damage)>0 and float(left_effect.thrust)<1 and float(left_effect.stability)<1, "Real rotor loss reduces thrust reserve and stability")
	check(float(left_effect.roll_bias)<0 and float(right_effect.roll_bias)>0 and close(absf(float(left_effect.roll_bias)),absf(float(right_effect.roll_bias))), "Left and right rotor losses produce opposite symmetric roll bias")
	var power = Damage.create_state(100,0,SIZE)
	Damage.resolve(power,30,Vector3(0,0,.8),Vector3.FORWARD)
	var power_effect = Damage.impairment(power)
	check(float(power_effect.motor_damage)>0 and float(power_effect.power_use)>1 and float(power_effect.thrust)<1, "Power component loss changes power consumption and available thrust")
	var hull = Damage.create_state(100,0,SIZE)
	Damage.resolve(hull,80,Vector3.ZERO,Vector3.FORWARD)
	var hull_effect = Damage.impairment(hull)
	check(close(float(hull_effect.rotor_damage),0) and close(float(hull_effect.motor_damage),0) and close(float(hull_effect.thrust),1), "Low hull health alone cannot fabricate broken motors or rotors")
	var broken = Damage.create_state(100,0,SIZE)
	var disabled_part = Damage.resolve(broken,60,Vector3(-.9,0,0),Vector3.RIGHT)
	check(bool(disabled_part.component_disabled) and not bool(disabled_part.killed) and float(broken.health)>0, "A real component can fail while the hull remains alive")
	var repeated_part = Damage.resolve(broken,5,Vector3(-.9,0,0),Vector3.RIGHT)
	check(not bool(repeated_part.component_disabled) and close(float(repeated_part.component_damage),0), "Already broken component is not destroyed or charged twice")
	var dying = Damage.create_state(7,0,SIZE)
	var kill = Damage.resolve(dying,200,Vector3.ZERO,Vector3.FORWARD)
	check(bool(kill.killed) and close(float(kill.damage),7) and close(float(dying.health),0), "Overkill receipt reports only the seven actual remaining hull points")
	var serial: int = int(dying.serial)
	check(Damage.resolve(dying,200,Vector3.ZERO,Vector3.FORWARD).is_empty() and int(dying.serial)==serial, "Dead target cannot produce a second damage or death receipt")

func test_round_trip() -> void:
	# Unparented bodies do not instantiate visual assets or enter physics. These
	# are the real production snapshot/restore methods, not a test-side copier.
	var body = Body.new()
	body.configure(Catalog.resolve_build(Catalog.default_build()))
	var point = Vector3(-float(body.damage_state.dimensions.x)*.45,0,0)
	Damage.resolve(body.damage_state,25,point,Vector3.RIGHT,"kinetic")
	body.health=float(body.damage_state.health)
	var saved = body.damage_snapshot()
	var wire: Dictionary = JSON.parse_string(JSON.stringify(saved))
	check(not wire.has("dimensions"), "Snapshot excludes Vector3 model dimensions from JSON")
	var restored = Body.new()
	restored.configure(Catalog.resolve_build(Catalog.default_build()))
	var original_dimensions: Vector3 = restored.damage_state.dimensions
	restored.restore_damage_state(wire)
	check(close(restored.health,body.health) and close(float(restored.damage_state.armor),float(body.damage_state.armor)), "Player hull and armor survive JSON checkpoint restoration")
	check(components_match(body.damage_state.components,restored.damage_state.components,"player_component_roundtrip"), "Player component health and maximum survive JSON checkpoint within 1e-10")
	check(int(restored.damage_state.serial)==int(body.damage_state.serial), "Player receipt serial survives a same-run checkpoint without ID reuse")
	check(restored.damage_state.dimensions==original_dimensions and float(restored.component_effects.rotor_damage)>0, "Restoration preserves authored dimensions and recomputes actual impairment")
	var enemy = Enemy.new()
	enemy.max_hp=80;enemy.hp=80;enemy.dimensions=SIZE
	enemy.damage_state=Damage.create_state(80,12,SIZE)
	Damage.resolve(enemy.damage_state,25,Vector3(0,0,.8),Vector3.FORWARD,"lance")
	enemy.hp=float(enemy.damage_state.health)
	var enemy_wire: Dictionary = JSON.parse_string(JSON.stringify(enemy.damage_snapshot()))
	var restored_enemy = Enemy.new()
	restored_enemy.max_hp=80;restored_enemy.hp=80;restored_enemy.dimensions=SIZE
	restored_enemy.damage_state=Damage.create_state(80,12,SIZE)
	restored_enemy.restore_damage_state(enemy_wire)
	var enemy_parts_match = components_match(enemy.damage_state.components,restored_enemy.damage_state.components,"enemy_component_roundtrip")
	check(close(restored_enemy.hp,enemy.hp) and close(float(restored_enemy.damage_state.armor),float(enemy.damage_state.armor)) and enemy_parts_match, "Enemy hull, armor and parts survive director-style JSON restoration within 1e-10")
	check(int(restored_enemy.damage_state.serial)==int(enemy.damage_state.serial), "Enemy receipt serial survives restoration")
	var dead = body.damage_snapshot();dead.health=0
	restored.restore_damage_state(dead)
	check(not restored.enabled and close(restored.health,0), "A restored zero-health aircraft cannot return to enabled immortal flight")
	body.free();restored.free();enemy.free();restored_enemy.free()
