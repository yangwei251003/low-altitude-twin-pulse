class_name TwinWeaponCycle
extends RefCounted
## Authoring candidate: host-only timing/request producer, never damage/LOS authority.
## Root supplies truth from actual body/lock/rays/Encounter, then confirms synchronously.
const Catalog = preload("res://scripts/v2/catalog.gd")
var _profile: Dictionary = {}
var _last_frame := -1
var _serial := 0
var _accepted := 0
var _rejected := 0
var _heat := 0.0
var _cooldown := 0.0
var _charge := 0.0
var _overheated := false
var _target := ""
var _pending: Dictionary = {}
var _cancel_reason := ""

static func weapon_profile(host_build: Dictionary) -> Dictionary:
	var resolved: Dictionary = Catalog.resolve_build(host_build)
	if not resolved.valid: return {"ok":false,"code":"weapon_build_invalid","errors":resolved.errors}
	var id: String = str(resolved.build.slots.get("weapon",""))
	if id not in ["pulse_base","burst_capacitor"]: return {"ok":false,"code":"weapon_not_supported"}
	var mods: Dictionary = resolved.derived.modifiers
	var burst: bool = id == "burst_capacitor"
	# Pulse deliberately retains V3's 9/.23 and no new heat/charge mechanic.
	# Never replace these with Catalog's V2 pulse 10/.28/8 values.
	var result: Dictionary = {"weapon_id":id,"build_hash":str(resolved.derived.build_hash),"damage_type":"pulse",
		"damage":float(mods.weapon_damage) if burst else 9.0,
		"interval_s":float(mods.weapon_interval_s) if burst else .23,
		"charge_s":float(mods.weapon_charge_s) if burst else 0.0,
		"heat_per_shot":float(mods.weapon_heat) if burst else 0.0,
		"heat_capacity":float(resolved.derived.heat_capacity),
		"cooling_per_s":float(mods.get("heat_dissipation_ps",16.0))*float(mods.get("cooling_multiplier",1.0)),
		"uses_heat":burst,"cancel_charge_fires":false}
	if burst and mods.get("cancel_charge_fires",false) != false:
		return {"ok":false,"code":"unsupported_charge_cancel_policy"}
	for key: String in ["damage","interval_s","heat_capacity","cooling_per_s"]:
		if not is_finite(float(result[key])) or float(result[key]) <= 0.0: return {"ok":false,"code":"invalid_weapon_parameter","field":key}
	for key: String in ["charge_s","heat_per_shot"]:
		if not is_finite(float(result[key])) or float(result[key]) < 0.0: return {"ok":false,"code":"invalid_weapon_parameter","field":key}
	return {"ok":true,"profile":result}

func configure(host_build: Dictionary, initial_heat: float = 0.0, initial_cooldown: float = 0.0) -> Dictionary:
	if not _pending.is_empty(): return _result(false,"shot_confirmation_required")
	var selected: Dictionary = weapon_profile(host_build)
	if not selected.ok: return selected
	if not is_finite(initial_heat) or initial_heat < 0.0 or initial_heat > float(selected.profile.heat_capacity) or not is_finite(initial_cooldown) or initial_cooldown < 0.0:
		return _result(false,"invalid_initial_weapon_state")
	_profile = selected.profile.duplicate(true)
	_heat = initial_heat
	_cooldown = initial_cooldown
	_charge = 0.0
	_target = ""
	_last_frame = -1
	_overheated = bool(_profile.uses_heat) and _heat >= float(_profile.heat_capacity)
	_cancel_reason = ""
	return _result(true,"configured")

## context is Host-generated, never copied from client ability/fire payloads.
## Keys: is_authority, held_fire, enabled, paused, target_id, target_valid,
## line_of_sight, part_open. Missing/incorrect booleans fail closed.
func step(physics_frame: int, delta: float, context: Dictionary) -> Dictionary:
	if _profile.is_empty(): return _result(false,"weapon_unconfigured")
	if context.get("is_authority") != true: return _result(false,"authority_required")
	for flag: String in ["is_authority","held_fire","enabled","paused","target_valid","line_of_sight","part_open"]:
		if not context.get(flag) is bool: return _result(false,"invalid_context_boolean")
	if physics_frame < 0 or not is_finite(delta) or delta <= 0.0: return _result(false,"invalid_physics_step")
	if physics_frame <= _last_frame: return _result(false,"duplicate_or_stale_physics_frame")
	if not _pending.is_empty(): return _result(false,"shot_confirmation_required")
	if _last_frame >= 0 and physics_frame != _last_frame+1: _cancel_charge("unobserved_frame_gap")
	_last_frame = physics_frame
	if context.get("paused") != false:
		_cancel_charge("paused")
		return _result(true,"paused")
	if context.get("enabled") != true:
		_cancel_charge("disabled")
		return _result(true,"disabled")
	# Existing V2 heat/overheat recovery constants and order, without catch-up shots.
	_cooldown = maxf(0.0,_cooldown-delta)
	if _profile.uses_heat:
		_heat = maxf(0.0,_heat-delta*float(_profile.cooling_per_s))
		if _overheated and _heat < float(_profile.heat_capacity)*.4: _overheated = false
	if context.get("held_fire") != true:
		_cancel_charge("released")
		return _result(true,"idle")
	if _overheated:
		_cancel_charge("overheated")
		return _result(true,"overheated")
	if _cooldown > 0.0:
		_cancel_charge("cooldown")
		return _result(true,"cooldown")
	# Original pulse starts .23s cooldown on an attempt before target validation.
	# A declined burst request consumes no heat or interval, as in V2 fire_bolt failure.
	if _profile.weapon_id == "pulse_base": _cooldown = float(_profile.interval_s)
	var target: Variant = context.get("target_id")
	if not target is String or target.is_empty() or context.get("target_valid") != true:
		_cancel_charge("invalid_target")
		return _result(true,"invalid_target")
	if context.get("line_of_sight") != true:
		_cancel_charge("occluded")
		return _result(true,"occluded")
	if context.get("part_open") != true:
		_cancel_charge("armored")
		return _result(true,"armored")
	if target != _target:
		_cancel_charge("target_changed")
		_target = str(target)
	_charge += delta
	# Same charge comparison tolerance as V2 Combat; no offline/frame-gap credit.
	if _charge+.00001 < float(_profile.charge_s): return _result(true,"charging")
	_serial += 1
	_pending = {"serial":_serial,"physics_frame":physics_frame,"target_id":_target,
		"weapon_id":str(_profile.weapon_id),"build_hash":str(_profile.build_hash),
		"damage":float(_profile.damage),"damage_type":str(_profile.damage_type)}
	var result: Dictionary = _result(true,"shot_request")
	result["shot_request"] = _pending.duplicate(true)
	return result

## Call once, synchronously after original Host hit validation. This does not
## prove or apply a hit. accepted=false cancels the transient request without heat.
func confirm_shot(serial: int, accepted: bool) -> Dictionary:
	if _pending.is_empty() or int(_pending.serial) != serial: return _result(false,"stale_shot_confirmation")
	_pending.clear()
	_cancel_charge("shot_accepted" if accepted else "shot_declined")
	if not accepted:
		_rejected += 1
		return _result(true,"shot_declined")
	_accepted += 1
	_cooldown = float(_profile.interval_s)
	if _profile.uses_heat:
		_heat = minf(float(_profile.heat_capacity),_heat+float(_profile.heat_per_shot))
		if _heat >= float(_profile.heat_capacity): _overheated = true
	return _result(true,"shot_accepted")

## Lifecycle cancellation cannot fire/refund heat. Root clears instances on new
## body/region/disconnect; charge is transient, not campaign/checkpoint proof.
func cancel(reason: String = "lifecycle") -> Dictionary:
	_pending.clear()
	_cancel_charge(reason)
	return _result(true,"cancelled")

func snapshot() -> Dictionary:
	return {"profile":_profile.duplicate(true),"physics_frame":_last_frame,
		"heat":_heat,"cooldown_s":_cooldown,"charge_s":_charge,"overheated":_overheated,
		"target_id":_target,"pending":_pending.duplicate(true),"serial":_serial,
		"accepted_shots":_accepted,"declined_shots":_rejected,"cancel_reason":_cancel_reason}

func _cancel_charge(reason: String) -> void:
	_charge = 0.0
	_target = ""
	_cancel_reason = reason

func _result(ok: bool, code: String) -> Dictionary:
	return {"ok":ok,"code":code,"state":snapshot()}
