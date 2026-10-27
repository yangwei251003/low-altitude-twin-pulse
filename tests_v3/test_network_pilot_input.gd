extends SceneTree
## Pure production input-validator contract. No sockets, MAIN, physics or LAN.
const Network = preload("res://scripts/v3/twin_network.gd")
var checks := 0
var failures: Array = []

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	_defaults_and_modes()
	_bounds_and_rejections()
	_isolation_and_payload_limit()
	print("V3_NETWORK_PILOT_INPUT_TESTS "+JSON.stringify({"checks":checks,"failures":failures,
		"scope":"production static validator only; no real input RPC, process, flight, damage or LAN evidence"}))
	quit(0 if failures.is_empty() else 1)

func _defaults_and_modes() -> void:
	var defaults: Dictionary=Network.validated_input({})
	_check(not defaults.is_empty() and defaults.get("mode")=="assisted" and defaults.get("planar")==Vector3.ZERO
		and defaults.get("active")==true and defaults.get("body_relative")==false
		and defaults.get("brake")==false and defaults.get("fire")==false,
		"old/default command retains assisted, active, neutral world-space controls",defaults)
	for field: String in ["vertical","yaw","pitch","roll","throttle"]:
		_check(defaults.has(field) and defaults[field]==0.0,"absent "+field+" defaults to zero",defaults)
	for mode: String in ["assisted","advanced","manual_throttle"]:
		var source: Dictionary={"mode":mode,"planar":Vector3(.3,0,-.4),"vertical":-.6,"yaw":.25,"pitch":-.4,"roll":.3,
			"throttle":.37,"active":true,"brake":true,"fire":false,"body_relative":true}
		var result: Dictionary=Network.validated_input(source)
		_check(not result.is_empty() and result.get("mode")==mode and result.get("throttle")==.37
			and result.get("vertical")==-.6 and result.get("yaw")==.25 and result.get("pitch")==-.4 and result.get("roll")==.3
			and result.get("planar")==source.planar and result.get("body_relative")==false,
			"preserve actual "+mode+" control values while enforcing world-space interpretation",result)
	var stopped: Dictionary=Network.validated_input({"mode":"manual_throttle","throttle":0.0,"vertical":-1.0})
	_check(not stopped.is_empty() and stopped.get("mode")=="manual_throttle" and stopped.get("throttle")==0.0
		and stopped.get("vertical")==-1.0,"manual zero throttle survives without conversion to assisted",stopped)
	var inactive: Dictionary=Network.validated_input({"active":false,"brake":true,"fire":false,"throttle":.4})
	_check(not inactive.is_empty() and inactive.get("active")==false and inactive.get("brake")==true
		and inactive.get("fire")==false,"inactive command stays inactive rather than regaining control",inactive)

func _bounds_and_rejections() -> void:
	var bounded: Dictionary=Network.validated_input({"planar":Vector3(3,90,4),"vertical":-9,"yaw":9,"pitch":-2,"roll":2,"throttle":3})
	_check(not bounded.is_empty() and bounded.get("planar") is Vector3
		and Vector3(bounded.planar).is_equal_approx(Vector3(.6,0,.8)) and Vector3(bounded.planar).length()<=1.000001,
		"planar ignores Y before clamping horizontal magnitude",bounded)
	_check(bounded.get("vertical")==-1.0 and bounded.get("yaw")==1.0 and bounded.get("pitch")==-1.0
		and bounded.get("roll")==1.0 and bounded.get("throttle")==1.0,"finite out-of-range scalars clamp to documented limits",bounded)
	var low: Dictionary=Network.validated_input({"throttle":-1})
	_check(not low.is_empty() and low.get("throttle")==0.0,"negative finite throttle clamps to zero",low)
	for field: String in ["vertical","yaw","pitch","roll","throttle"]:
		var accidentally_accepted: Array=[]
		for value: Variant in [NAN,INF,-INF,"0",true,null,Vector3.ZERO]:
			var command: Dictionary={"mode":"manual_throttle","throttle":.4}
			command[field]=value
			if not Network.validated_input(command).is_empty(): accidentally_accepted.append(str(value))
		_check(accidentally_accepted.is_empty(),field+" rejects nonfinite values and nonnumeric types atomically",{"accepted":accidentally_accepted})
	for value: Variant in [Vector3(NAN,0,0),Vector3(0,INF,0),Vector3(0,0,-INF),Vector2.ZERO,[0,0,0],null]:
		_check(Network.validated_input({"planar":value}).is_empty(),"invalid full planar vector rejected before Y flattening",{"value":str(value)})
	for field: String in ["active","brake","fire"]:
		var accidentally_accepted: Array=[]
		for value: Variant in [0,1,"false",null]:
			var command: Dictionary={field:value}
			if not Network.validated_input(command).is_empty(): accidentally_accepted.append(str(value))
		_check(accidentally_accepted.is_empty(),field+" requires an actual bool",{"accepted":accidentally_accepted})
	for value: Variant in ["unknown","MANUAL_THROTTLE",0,null]:
		_check(Network.validated_input({"mode":value}).is_empty(),"unknown or non-string mode rejected",{"value":value})

func _isolation_and_payload_limit() -> void:
	# Optional legacy bookkeeping fields need not enter the canonical command.
	# Their presence is accepted within the existing 18-key transport bound.
	var source: Dictionary={"planar":Vector3(3,9,4),"throttle":2,"mode":"manual_throttle","body_relative":true}
	for index in range(14): source["legacy_"+str(index)]=index
	var untouched: Dictionary=source.duplicate(true)
	var accepted: Dictionary=Network.validated_input(source)
	_check(source.size()==18 and not accepted.is_empty() and source==untouched,"18-field legacy payload accepted without mutating caller",accepted)
	accepted["mode"]="changed only in returned dictionary"
	_check(source==untouched,"returned canonical command does not alias caller")
	source["one_too_many"]=0
	var rejected_before: Dictionary=source.duplicate(true)
	_check(Network.validated_input(source).is_empty() and source==rejected_before,"19-field payload rejected wholly without normalizing caller")

func _check(ok: bool,label: String,details: Dictionary={}) -> void:
	checks+=1
	if not ok:
		failures.append({"check":label,"details":details})
		print("NETWORK_PILOT_INPUT_FAIL "+label+" "+JSON.stringify(details))
