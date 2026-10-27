extends SceneTree
const State=preload("res://scripts/v3/candidates/canal_checkpoint/flight_state.gd")
func _initialize() -> void:
    var body=State.Flight.new()
    body.configure(State.Catalog.resolve_build(State.Catalog.default_build("tr01")))
    var expected_mass: float=float(State.Catalog.resolve_build(State.Catalog.default_build("tr01")).derived.mass_kg)
    print("WAIT_NATIVE_MASS ",JSON.stringify({"mass":body.mass,"expected":expected_mass,"equal":body.mass==expected_mass}))
    body.free()
    var evidence: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests_v3/candidates/canal_session/evidence/20261020_082820_37bc8b/result.json"))
    var row: Dictionary=evidence.snapshots.beneficiary_capture.state
    var native_added: Dictionary=row.duplicate(true)
    var waiting: Dictionary=native_added.wait
    native_added.erase("wait")
    native_added.wait=waiting
    var string_added: Dictionary=row.duplicate(true)
    string_added.erase("wait")
    string_added["wait"]=waiting
    var key_types: Dictionary={}
    for key: Variant in native_added: key_types[str(key)]=typeof(key)
    print("WAIT_NATIVE_KEY ",JSON.stringify({"dot_keys":key_types,"dot_issue":State.wait_validation_issue(native_added,row.id),"string_issue":State.wait_validation_issue(string_added,row.id)}))
    var base: Dictionary=row.duplicate(true)
    base.erase("wait")
    base.velocity=[0.0,0.0,0.0]
    base.angular_velocity=[0.0,0.0,0.0]
    var command: Dictionary=row.wait.command
    var keys: Array=State.KEYS.duplicate()
    keys.append("wait")
    print("WAIT_VALIDATION ",JSON.stringify({"full":State.validate_wait(row,row.id),"base":State.validate(base,row.id),"keys":State.exact(row,keys),"velocity":State.vector_valid(row.velocity,.5),"angular":State.vector_valid(row.angular_velocity,.5),"wait_keys":State.exact(row.wait,["collision_count","last_velocity","command"]),"count":State.integer(row.wait.collision_count,0,2147483647),"last":State.vector_valid(row.wait.last_velocity,10),"command_size":command.size(),"active":command.get("active")==true,"mode":command.get("mode") in ["assisted","manual_throttle"],"relative":command.get("body_relative")==false,"planar":State.vector_valid(command.get("planar"),1),"brake":command.get("brake") is bool,"fire":command.get("fire") is bool,"pose":State.pose_valid(row.pose),"base_keys":State.exact(base,State.KEYS)}))
    quit()
