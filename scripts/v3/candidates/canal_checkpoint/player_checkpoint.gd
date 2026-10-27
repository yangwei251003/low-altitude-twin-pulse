extends RefCounted
## Candidate-only save boundary. Caller supplies host-validated ability state
## after checking that no entity lease (takeover etc.) is still active.
## This observer never advances a world, changes a command, heals or writes disk.
const Site = preload("res://scripts/v3/candidates/canal_checkpoint/canal_checkpoint.gd")
const State = preload("res://scripts/v3/candidates/canal_checkpoint/flight_state.gd")
const Flight = preload("res://scripts/v2/flight_body.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
const VERSION := 1
const KIND := "canal_player_checkpoint_v1"
const PLAYER_ID := "player:1"
const BODY_MASK := 45 # The actual candidate player's unchanged Flight default.
const QUERY_MASK := 47 # Clearance still includes other live aircraft.
const ABILITIES := ["push_pull","heat","charge","takeover"]
const ABILITY_KEYS := ["energy","selected","cooldown","actor_revision","station_serial"]
const KEYS := ["version","kind","layout","site","player","ability","world_clock","physics"]
var _site = Site.new()
var _first_frame := -1
var _last_frame := -1
var _player: WeakRef

func capture(context: Dictionary, executor: RefCounted, workbench: Node3D, cooling: Node3D,
        player: Flight, ability_state: Dictionary, world_clock: float,
        authority: bool = true, paused: bool = false) -> Dictionary:
    if not authority: return _failed("authority_required")
    if paused: return _failed("paused")
    if Engine.physics_ticks_per_second != 60: return _failed("physics_rate")
    if not _ability_valid(ability_state) or not State.number(world_clock,0,1.0e12): return _failed("ability_or_clock")
    var issue: String = _live_issue(player)
    if not issue.is_empty(): return _failed(issue)
    var carrier: Variant = context.get("carrier")
    if not carrier is Flight or not is_instance_valid(carrier) or not carrier.is_inside_tree() or carrier == player or carrier.get_world_3d() != player.get_world_3d(): return _failed("same_world_distinct_player_required")
    var frame: int = Engine.get_physics_frames()
    if _player == null or _player.get_ref() != player or (_last_frame >= 0 and frame != _last_frame and frame != _last_frame+1):
        _site.reset_observation()
        _first_frame = frame
        _player = weakref(player)
    if _first_frame < 0: _first_frame = frame
    _last_frame = frame
    var row: Dictionary = {"flight":State.capture(player,PLAYER_ID),"collision_count":player.collision_count}
    var result: Dictionary = _site.capture(context,executor,workbench,cooling,true,false)
    if not result.ok:
        if result.code != "stability_pending": return _failed("site:"+str(result.code))
        return {"ok":false,"code":"stability_pending","observed_usec":mini(Site.STABLE_USEC,roundi(float(frame-_first_frame)*1000000.0/60.0))}
    var observed_usec: int = mini(Site.STABLE_USEC,roundi(float(frame-_first_frame)*1000000.0/60.0))
    if observed_usec < Site.STABLE_USEC: return {"ok":false,"code":"stability_pending","observed_usec":observed_usec}
    if frame != Engine.get_physics_frames() or row.flight != State.capture(player,PLAYER_ID) or row.collision_count != player.collision_count: return _failed("capture_changed_during_read")
    var envelope: Dictionary = {"version":VERSION,"kind":KIND,"layout":_layout(),"site":result.envelope,
        "player":row,"ability":ability_state.duplicate(true),"world_clock":world_clock,
        "physics":{"frame":frame,"observed_usec":observed_usec}}
    var valid: Dictionary = validate(envelope)
    if not valid.ok: return _failed("capture_schema:"+str(valid.code))
    return {"ok":true,"code":"captured_player_and_site","envelope":envelope.duplicate(true)}

func reset_observation() -> void:
    _site.reset_observation()
    _first_frame = -1
    _last_frame = -1
    _player = null

func _failed(code: String) -> Dictionary:
    reset_observation()
    return _bad(code)

static func validate(raw: Variant) -> Dictionary:
    if not Site._json_safe(raw) or not State.exact(raw,KEYS): return _bad("envelope_keys_or_types")
    if not State.integer(raw.version,VERSION,VERSION) or raw.kind != KIND: return _bad("version_kind")
    if not State.exact(raw.layout,["id","schema","sha256"]) or raw.layout.id != Site.LAYOUT_ID or not State.integer(raw.layout.schema,1,1) or raw.layout.sha256 != layout_fingerprint(): return _bad("layout")
    var site_check: Dictionary = Site.validate(raw.site)
    if not site_check.ok: return _bad("site:"+str(site_check.code))
    if not _player_valid(raw.player): return _bad("player_state")
    if not _ability_valid(raw.ability): return _bad("ability_state")
    if not State.number(raw.world_clock,0,1.0e12): return _bad("world_clock")
    if not State.exact(raw.physics,["frame","observed_usec"]) or not State.integer(raw.physics.frame,1,Site.MAX_COUNTER) or int(raw.physics.frame) != int(raw.site.physics.frame) or not State.integer(raw.physics.observed_usec,Site.STABLE_USEC,Site.STABLE_USEC): return _bad("physics_sample")
    var minimum_serial: int = maxi(int(raw.site.checkpoint.cooling.charge_serial),int(raw.site.checkpoint.workbench_charge_serial))
    minimum_serial = maxi(minimum_serial,int(raw.site.checkpoint.cooling.axis.last_serial["1"]))
    if int(raw.ability.station_serial) < minimum_serial: return _bad("device_serial_would_replay")
    return {"ok":true,"code":"valid_player_checkpoint"}

## No existing-body argument. A failure allocates nothing; caller owns a fresh
## isolated parent and adopts it only after the separate site's ready check.
## The same collision size is obtained from the real default TR01 definition.
static func restore_player_fresh(parent: Node3D, row: Dictionary, environment: Callable) -> Dictionary:
    if not is_instance_valid(parent) or not parent.is_inside_tree() or not parent.global_transform.is_equal_approx(Transform3D.IDENTITY) or not environment.is_valid(): return _bad("fresh_identity_parent_required")
    if parent.has_node(PLAYER_ID.replace(":","_")): return _bad("player_already_created")
    if not _player_valid(row): return _bad("player_state")
    var excluded: Array[RID] = []
    var clear: Dictionary = _clearance(parent,State.transform(row.flight.pose),excluded)
    if not clear.ok: return clear
    var made: Dictionary = State.create(parent,row.flight,PLAYER_ID,BODY_MASK,environment)
    if not made.ok: return made
    # Historical count is retained. Expired old object IDs are deliberately not
    # serialized/reinstalled; capture already required >=0.7s since every hit.
    made.body.collision_count = int(row.collision_count)
    return {"ok":true,"code":"created_fresh_player_only","body":made.body}

static func layout_fingerprint() -> String:
    var resolved: Dictionary = Catalog.resolve_build(Catalog.default_build("tr01"))
    return JSON.stringify({"site":Site.layout_fingerprint(),"player_build":resolved.build,"player_stats":resolved.derived,
        "box":State.xyz(_dimensions()),"body_mask":BODY_MASK,"query_mask":QUERY_MASK,"schema":1},"",true,true).sha256_text()

static func _layout() -> Dictionary:
    return {"id":Site.LAYOUT_ID,"schema":1,"sha256":layout_fingerprint()}

static func _player_valid(row: Variant) -> bool:
    return State.exact(row,["flight","collision_count"]) and State.validate(row.flight,PLAYER_ID) and State.integer(row.collision_count,0,Site.MAX_COUNTER)

static func _ability_valid(value: Variant) -> bool:
    return State.exact(value,ABILITY_KEYS) and State.number(value.energy,0,100) and value.selected is String and value.selected in ABILITIES and State.number(value.cooldown,0,.35) and State.integer(value.actor_revision,0,Site.MAX_COUNTER) and State.integer(value.station_serial,0,2147483647)

static func _live_issue(body: Flight) -> String:
    if not is_instance_valid(body) or not body.is_inside_tree() or body.is_queued_for_deletion(): return "live_player_required"
    var resolved: Dictionary = Catalog.resolve_build(Catalog.default_build("tr01"))
    if body.build != resolved.build or not body.enabled or body.freeze or body.practice or not body.sandbox_rules.is_empty() or body.crash_reported or body.health <= 0: return "normal_live_tr01_required"
    if not body.cargo_items.is_empty() or is_instance_valid(body.cargo_joint) or not is_zero_approx(body.cargo_kg): return "player_carrying_cargo"
    if body.water_contact or body.water_seconds != 0.0 or not body.get_colliding_bodies().is_empty(): return "player_current_contact"
    if body.collision_layer != 2 or body.collision_mask != BODY_MASK or not is_equal_approx(body.mass,float(resolved.derived.mass_kg)) or body.max_altitude != 18.0 or not body.environment_hazards_authoritative or body.collision_damage_scale != 1.0 or not body.environment_acceleration.is_zero_approx(): return "player_physics_changed"
    if not State.integer(body.collision_count,0,Site.MAX_COUNTER) or not State.number(body.flight_seconds,0,1.0e12): return "player_collision_history"
    for stamp: Variant in body.contact_cooldowns.values():
        if not State.number(stamp,0,body.flight_seconds) or body.flight_seconds-float(stamp) < .7: return "recent_player_collision"
    if not State.validate(State.capture(body,PLAYER_ID),PLAYER_ID): return "player_state_or_speed"
    if not Site._single_box(body,_dimensions()): return "player_collider_changed"
    for node: Node in body.get_tree().root.find_children("*","Joint3D",true,false):
        var joint: Joint3D = node as Joint3D
        if joint.get_node_or_null(joint.node_a) == body or joint.get_node_or_null(joint.node_b) == body: return "player_attachment_present"
    var excluded: Array[RID] = [body.get_rid()]
    var clear: Dictionary = _clearance(body,body.global_transform,excluded)
    return "" if clear.ok else str(clear.code)

static func _dimensions() -> Vector3:
    var stats: Dictionary = Catalog.resolve_build(Catalog.default_build("tr01")).derived
    return Vector3(float(stats.width_m),float(stats.height_m),float(stats.length_m))

static func _clearance(owner: Node3D, pose: Transform3D, excluded: Array[RID]) -> Dictionary:
    var query := PhysicsShapeQueryParameters3D.new()
    var shape := BoxShape3D.new()
    shape.size = _dimensions()
    query.shape = shape
    query.transform = pose
    query.margin = .003
    query.collision_mask = QUERY_MASK
    query.exclude = excluded
    var hits: Array[Dictionary] = owner.get_world_3d().direct_space_state.intersect_shape(query,8)
    if not hits.is_empty():
        var names: Array = []
        for hit: Dictionary in hits:
            var node: Variant = hit.get("collider")
            names.append(str(node.get_path()) if node is Node else "non_node_collider")
        return {"ok":false,"code":"player_envelope_obstructed","colliders":names}
    return {"ok":true,"code":"player_envelope_clear"}

static func _bad(code: String) -> Dictionary:
    return {"ok":false,"code":code}
