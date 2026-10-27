class_name TwinTrialAssembly
extends Node3D
## Owns the two existing physical components. No save, network or reward logic.
## The container MUST remain world identity; both children author world origins.
const Link = preload("res://scripts/v3/world/twin_trial_isolation_link.gd")
const Station = preload("res://scripts/v3/world/twin_trial_flow_station.gd")
const Runtime = preload("res://scripts/v3/environment/twin_trial_flow_runtime.gd")
const MAX_DELTA := 0.25
var link
var station
var configured := false
var authority := true
var error := ""
var target_bodies: Dictionary = {}

func configure(saved: Dictionary = {}, is_authority: bool = true) -> Dictionary:
	if configured or is_inside_tree(): return _r(false,"configure_before_tree_once")
	if not saved.is_empty() and not _pair(saved): return _r(false,"assembly_pair")
	var next_link = Link.new()
	var checked: Dictionary = next_link.configure(saved.get("link",{}),is_authority)
	if not checked.ok:
		next_link.free()
		return _r(false,"link:"+str(checked.code))
	var next_station = Station.new()
	checked=next_station.load_layout(saved.get("station",{}),is_authority)
	if not checked.ok:
		next_link.free()
		next_station.free()
		return _r(false,"station:"+str(checked.code))
	link=next_link
	station=next_station
	authority=is_authority
	link.name="IsolationLink"
	station.name="FlowStation"
	add_child(link)
	add_child(station)
	for id in link.target_bodies: target_bodies[id]=link.target_bodies[id]
	for id in station.target_bodies: target_bodies[id]=station.target_bodies[id]
	configured=true
	set_process(false)
	set_physics_process(false)
	return _r(true,"configured")

func _ready() -> void:
	if configured: bind()

func bind() -> Dictionary:
	if not configured or not is_inside_tree(): return _r(false,"world_required")
	if not global_transform.is_equal_approx(Transform3D.IDENTITY): return _r(false,"assembly_world_identity")
	var checked: Dictionary = station.attach_link(link)
	error="" if checked.ok else str(checked.code)
	return checked

func snapshot() -> Dictionary:
	if not configured: return {}
	return {"link":link.snapshot(),"station":station.snapshot()}

func validate_snapshot(raw: Variant) -> Dictionary:
	if not configured: return _r(false,"not_configured")
	if not _pair(raw): return _r(false,"assembly_pair")
	var checked: Dictionary = link.validate_snapshot(raw.link)
	if not checked.ok: return _r(false,"link:"+str(checked.code))
	checked=station.validate_snapshot(raw.station)
	return checked if checked.ok else _r(false,"station:"+str(checked.code))

func apply_snapshot(raw: Variant) -> Dictionary:
	# No await, callbacks, physics step or adoption occurs between validation of
	# BOTH children and these deterministic restores. A bad second child cannot
	# move the first. Client restores publish the real PhysicsServer poses now.
	var checked:=validate_snapshot(raw)
	if not checked.ok: return checked
	if is_inside_tree():
		checked=connection_status()
		if not checked.ok: return checked
	checked=link.apply_snapshot(raw.link)
	if not checked.ok: return checked
	checked=station.apply_snapshot(raw.station)
	if not checked.ok: return checked
	return bind() if is_inside_tree() else _r(true,"snapshot_applied")

func connection_status() -> Dictionary:
	if not configured or not is_inside_tree(): return _r(false,"world_required")
	if not global_transform.is_equal_approx(Transform3D.IDENTITY): return _r(false,"assembly_world_identity")
	return station.connection_status()

func fixed_update(delta: float, entities: Dictionary, players: Dictionary, is_authority: bool = true) -> Dictionary:
	var checked:=connection_status()
	if not checked.ok: return checked
	if not authority or not is_authority: return _r(false,"not_authority")
	if not is_finite(delta) or delta<0.0 or delta>MAX_DELTA: return _r(false,"delta_range")
	# Link publishes its actual collision before the Station traces its bores.
	# Each existing module keeps its own all-parts-before-commit physical checks.
	var moved_link: Dictionary = link.fixed_update(delta,entities,players,true)
	if not moved_link.ok: return _r(false,"link_update:"+str(moved_link.code))
	var moved_station: Dictionary = station.fixed_update(delta,entities,players,true)
	if not moved_station.ok:
		# A runtime fault is fail-closed; never continue consuming time or credit.
		set_simulation_paused(true)
		return _r(false,"station_update:"+str(moved_station.code))
	return {"ok":true,"code":"advanced","link":moved_link,"station":moved_station}

func synchronize_impulse_roster(players: Dictionary) -> Dictionary:
	if not configured: return _r(false,"not_configured")
	var checked: Dictionary = link.synchronize_impulse_roster(players)
	if not checked.ok: return checked
	return station.synchronize_impulse_roster(players)

func reset_impulse_peer(peer: int) -> Dictionary:
	if not configured: return _r(false,"not_configured")
	var checked: Dictionary = link.reset_impulse_peer(peer)
	if not checked.ok: return checked
	return station.reset_impulse_peer(peer)

func set_simulation_paused(value: bool) -> Dictionary:
	if not configured: return _r(false,"not_configured")
	var first: Dictionary = link.set_simulation_paused(value)
	var second: Dictionary = station.set_simulation_paused(value)
	return first if not first.ok else second

func target_definitions() -> Array:
	return link.target_definitions()+station.target_definitions() if configured else []

func entity_position(id: String) -> Variant:
	if not configured: return null
	return link.entity_position(id) if id==Link.HANDLE else station.entity_position(id)

func can_accept_impulse(id: String, impulse: Vector3, peer: int, action_serial: int) -> Dictionary:
	if not configured: return _r(false,"not_configured")
	return link.can_accept_impulse(id,impulse,peer,action_serial) if id==Link.HANDLE else station.can_accept_impulse(id,impulse,peer,action_serial)

func apply_authorized_impulse(id: String, impulse: Vector3, peer: int, action_serial: int) -> Dictionary:
	if not configured: return _r(false,"not_configured")
	return link.apply_authorized_impulse(id,impulse,peer,action_serial) if id==Link.HANDLE else station.apply_authorized_impulse(id,impulse,peer,action_serial)

func observe_gauge(peer: int, body: Variant, receiver: String) -> Dictionary:
	var connected:=connection_status()
	if not connected.ok: return connected
	var observed: Dictionary = station.observe_gauge(peer,body,receiver)
	if observed.ok:
		observed.link_geometry_sha256=str(link.snapshot().geometry_sha256)
		observed.station_layout_sha256=str(station.snapshot().layout_sha256)
	return observed

func request_return(peer: int, body: Variant) -> Dictionary:
	var connected:=connection_status()
	return station.request_return(peer,body) if connected.ok else connected

static func _pair(raw: Variant) -> bool:
	if not raw is Dictionary or raw.size()!=2 or not raw.get("link") is Dictionary or not raw.get("station") is Dictionary: return false
	for key in raw:
		if not key is String or key not in ["link","station"]: return false
	return true

static func _r(ok: bool, code: String) -> Dictionary:
	return {"ok":ok,"code":code}
