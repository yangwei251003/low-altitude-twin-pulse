class_name TwinAbilityRules
extends RefCounted
## Authoritative, deterministic rules. No scene tree or physics access.
## Clients send intents, never resolved transactions. See GAMEPLAY_CONTRACT.md.

const DEFINITIONS := {
	"blink": {"energy": 16.0, "range": 9.0, "target": false},
	"push_pull": {"energy": 8.0, "range": 12.0, "target": true},
	"force_field": {"energy": 10.0, "range": 10.0, "target": true},
	"light": {"energy": 5.0, "range": 16.0, "target": true},
	"heat": {"energy": 8.0, "range": 12.0, "target": true},
	"charge": {"energy": 8.0, "range": 12.0, "target": true},
	"growth": {"energy": 12.0, "range": 10.0, "target": true},
	"decoy": {"energy": 10.0, "range": 8.0, "target": false},
	"echo": {"energy": 12.0, "range": 12.0, "target": true},
	"takeover": {"energy": 18.0, "range": 10.0, "target": true},
}

func validate(intent: Dictionary, entities: Dictionary, context: Dictionary = {}) -> Dictionary:
	var ability := str(intent.get("ability", ""))
	if not DEFINITIONS.has(ability):
		return _reject("unknown_ability")
	var actor_id := str(intent.get("actor_id", ""))
	if not entities.has(actor_id) or not entities[actor_id] is Dictionary:
		return _reject("actor_missing")
	var actor: Dictionary = entities[actor_id]
	var sender := str(context.get("sender_id", ""))
	if sender.is_empty() or str(actor.get("owner", "")) != sender or not _tag(actor, "player"):
		return _reject("not_owner")
	if actor.get("downed", false) or float(actor.get("health", 1.0)) <= 0.0:
		return _reject("actor_downed")
	if not _position_valid(actor.get("position")):
		return _reject("invalid_position")
	if intent.has("actor_revision") and int(intent.actor_revision) != int(actor.get("revision", 0)):
		return _reject("stale_actor")
	var definition: Dictionary = DEFINITIONS[ability]
	var energy := float(actor.get("energy", 0.0))
	if not is_finite(energy) or energy < float(definition.energy):
		return _reject("insufficient_energy")
	var target: Dictionary = {}
	var target_id := str(intent.get("target_id", ""))
	var destination: Vector3 = actor.position
	if definition.target:
		if not entities.has(target_id) or not entities[target_id] is Dictionary:
			return _reject("target_missing")
		target = entities[target_id]
		if not _position_valid(target.get("position")):
			return _reject("invalid_position")
		if _tag(target, "player"):
			return _reject("player_target_not_supported")
		if intent.has("expected_revision") and int(intent.expected_revision) != int(target.get("revision", 0)):
			return _reject("stale_target")
		destination = target.position
		# This flag must be supplied by a host ray cast, never copied from a client.
		if context.get("line_of_sight", false) != true:
			return _reject("line_of_sight_required")
	else:
		if not _position_valid(intent.get("point")):
			return _reject("invalid_destination")
		destination = intent.point
	if actor.position.distance_to(destination) > float(definition.range) + 0.001:
		return _reject("out_of_range")
	var support := _validate_support(ability, intent, target, sender)
	if not support.ok:
		return support
	return {"ok": true, "code": "valid", "actor_id": actor_id, "target_id": target_id, "ability": ability}

func resolve(intent: Dictionary, entities: Dictionary, context: Dictionary = {}) -> Dictionary:
	var checked := validate(intent, entities, context)
	if not checked.ok:
		return checked
	var ability: String = checked.ability
	var actor_id: String = checked.actor_id
	var actor: Dictionary = entities[actor_id]
	var target_id: String = checked.target_id
	var target: Dictionary = entities.get(target_id, {})
	var sender := str(context.sender_id)
	var mode := str(intent.get("mode", ""))
	var result := {"ok": true, "code": "resolved", "patches": [], "events": [], "physics_requests": []}
	var actor_changes := {"energy": float(actor.energy) - float(DEFINITIONS[ability].energy)}
	var changes: Dictionary = {}
	match ability:
		"blink":
			result.physics_requests.append({"type": "blink", "entity_id": actor_id, "from": actor.position, "to": intent.point, "require_sweep": true, "require_destination_clearance": true})
		"push_pull":
			var direction: Vector3 = (target.position - actor.position).normalized()
			if mode == "pull":
				direction = -direction
			result.physics_requests.append({"type": "impulse", "entity_id": target_id, "impulse": direction * 9.0, "from": target.position, "require_collision": true})
		"force_field":
			changes = {"pinned": mode != "release", "pinned_by": sender if mode != "release" else "", "field_remaining": 4.0 if mode != "release" else 0.0}
		"light":
			var level := 0.0 if mode == "off" else 1.0
			changes = {"light_level": level, "light_remaining": 6.0 if level > 0.0 else 0.0}
			# A powered environmental emitter holds its setting; portable illumination expires.
			if _tag(target, "sustained_light_source"): changes.light_remaining = 0.0
			if _tag(target, "rotatable") and level > 0.0:
				changes.angle = wrapf(float(target.get("angle", 0.0)) + PI / 6.0, -PI, PI)
		"heat":
			var temperature := clampf(float(target.get("temperature", 20.0)) + (-25.0 if mode == "cool" else 25.0), -40.0, 200.0)
			changes.temperature = temperature
			if _tag(target, "combustible"):
				changes.burning = temperature >= 70.0 or (target.get("burning", false) and temperature >= 40.0)
		"charge":
			var capacity := maxf(0.0, float(target.get("charge_capacity", 100.0)))
			var charge := clampf(float(target.get("charge", 0.0)) + (-35.0 if mode == "drain" else 35.0), 0.0, capacity)
			changes.charge = charge
		"growth":
			changes.growth = clampf(float(target.get("growth", 0.0)) + 0.35, 0.0, 1.0)
			result.events.append({"type": "growth_changed", "entity_id": target_id, "growth": changes.growth})
		"decoy":
			actor_changes.decoy_remaining = 6.0
			actor_changes.decoy_position = intent.point
			result.physics_requests.append({"type": "spawn_decoy", "entity_id": actor_id, "from": actor.position, "to": intent.point, "require_line_of_sight": true, "require_destination_clearance": true})
			result.events.append({"type": "decoy_started", "source_id": actor_id, "position": intent.point, "duration": 6.0, "replace_existing": true})
		"echo":
			changes = {"echo_remaining": 5.0, "echoed_by": sender, "operated": true}
			result.events.append({"type": "echo_started", "entity_id": target_id, "duration": 5.0})
		"takeover":
			changes = {"owner": sender, "return_owner": target.get("owner", ""), "takeover_remaining": 8.0, "controlled": true}
			result.events.append({"type": "control_changed", "entity_id": target_id, "owner": sender, "duration": 8.0})
	if ability in ["light", "heat", "charge"]:
		_derive_power(target, changes)
	result.patches.append(_patch(actor_id, actor, actor_changes))
	# Even pure physical target actions read-lock the target revision atomically.
	if not target.is_empty():
		result.patches.append(_patch(target_id, target, changes))
	result.events.append({"type": "ability_applied", "ability": ability, "actor_id": actor_id, "target_id": target_id})
	if not result.physics_requests.is_empty():
		result.code = "physics_required"
	return result

func commit(result: Dictionary, entities: Dictionary, physics_approved: bool = false) -> Dictionary:
	if not result.get("ok", false):
		return result
	if not result.get("physics_requests", []).is_empty() and not physics_approved:
		return _reject("physics_not_approved")
	var seen: Dictionary = {}
	for patch in result.get("patches", []):
		var entity_id := str(patch.get("entity_id", ""))
		if seen.has(entity_id) or not entities.has(entity_id):
			return _reject("invalid_transaction")
		seen[entity_id] = true
		if int(entities[entity_id].get("revision", 0)) != int(patch.expected_revision):
			return _reject("stale_transaction")
	# All preconditions passed before any energy or target state is changed.
	for patch in result.get("patches", []):
		var entity: Dictionary = entities[patch.entity_id]
		entity.merge(patch.changes.duplicate(true), true)
		entity.revision = int(entity.get("revision", 0)) + 1
	return {"ok": true, "code": "committed", "events": result.get("events", []).duplicate(true), "physics_requests": result.get("physics_requests", []).duplicate(true)}

func advance_states(entities: Dictionary, delta: float) -> Dictionary:
	var result := {"ok": true, "code": "resolved", "patches": [], "events": [], "physics_requests": []}
	if not is_finite(delta) or delta < 0.0:
		return _reject("invalid_delta")
	for entity_id in entities:
		var entity: Dictionary = entities[entity_id]
		var changes: Dictionary = {}
		for timer in ["field_remaining", "light_remaining", "decoy_remaining", "echo_remaining", "takeover_remaining"]:
			if float(entity.get(timer, 0.0)) <= 0.0:
				continue
			var remaining := maxf(0.0, float(entity[timer]) - delta)
			changes[timer] = remaining
			if remaining > 0.0:
				continue
			match timer:
				"field_remaining":
					changes.merge({"pinned": false, "pinned_by": ""})
				"light_remaining":
					changes.light_level = 0.0
				"echo_remaining":
					changes.merge({"operated": false, "echoed_by": ""})
				"takeover_remaining":
					changes.merge({"owner": entity.get("return_owner", ""), "controlled": false, "return_owner": ""})
			result.events.append({"type": "effect_expired", "entity_id": entity_id, "effect": timer.trim_suffix("_remaining")})
		if changes.has("light_level"):
			_derive_power(entity, changes)
		if not changes.is_empty():
			result.patches.append(_patch(str(entity_id), entity, changes))
	return result

func _validate_support(ability: String, intent: Dictionary, target: Dictionary, sender: String) -> Dictionary:
	var mode := str(intent.get("mode", ""))
	var modes := {"push_pull": ["", "push", "pull"], "force_field": ["", "pin", "release"], "light": ["", "on", "off"], "heat": ["", "heat", "cool"], "charge": ["", "add", "drain"]}
	if modes.has(ability) and not mode in modes[ability]:
		return _reject("invalid_mode")
	for field in ["temperature", "charge", "charge_capacity", "growth", "light_level", "environment_light", "angle", "power_threshold", "light_threshold", "heat_threshold"]:
		if target.has(field) and (not target[field] is float and not target[field] is int or not is_finite(float(target[field]))):
			return _reject("invalid_target_state")
	# Do not allow one peer's physical/control tool to override another's lease.
	if ability in ["push_pull", "force_field", "echo", "takeover"]:
		if float(target.get("takeover_remaining", 0.0)) > 0.0 and str(target.get("owner", "")) != sender:
			return _reject("target_busy")
		if float(target.get("echo_remaining", 0.0)) > 0.0 and str(target.get("echoed_by", "")) != sender:
			return _reject("target_busy")
		if target.get("pinned", false) and str(target.get("pinned_by", "")) != sender:
			return _reject("target_busy")
	match ability:
		"push_pull":
			if not _tag(target, "movable"):
				return _reject("unsupported_target")
			if target.get("pinned", false):
				return _reject("target_pinned")
		"force_field":
			if not _tag(target, "fieldable"):
				return _reject("unsupported_target")
			if target.get("pinned", false) and str(target.get("pinned_by", "")) != sender:
				return _reject("target_busy")
			if mode == "release" and not target.get("pinned", false):
				return _reject("not_pinned")
		"light":
			if not _tag(target, "photosensitive"):
				return _reject("unsupported_target")
		"heat":
			if not _tag(target, "thermal"):
				return _reject("unsupported_target")
		"charge":
			if not _tag(target, "conductive"):
				return _reject("unsupported_target")
		"growth":
			if not _tag(target, "growable"):
				return _reject("unsupported_target")
			if maxf(float(target.get("light_level", 0.0)), float(target.get("environment_light", 0.0))) < 0.25:
				return _reject("growth_needs_light")
			if float(target.get("temperature", 20.0)) < 0.0 or float(target.get("temperature", 20.0)) > 60.0:
				return _reject("growth_temperature")
			if float(target.get("growth", 0.0)) >= 1.0:
				return _reject("fully_grown")
		"echo":
			if not _tag(target, "echo_operable"):
				return _reject("unsupported_target")
			if float(target.get("echo_remaining", 0.0)) > 0.0 and str(target.get("echoed_by", "")) != sender:
				return _reject("target_busy")
		"takeover":
			if not _tag(target, "hackable") or not _tag(target, "mechanical"):
				return _reject("unsupported_target")
			if float(target.get("takeover_remaining", 0.0)) > 0.0:
				return _reject("target_busy")
			var owner := str(target.get("owner", ""))
			if not owner.is_empty() and owner != "neutral" and not _tag(target, "enemy") and owner != sender:
				return _reject("not_owner")
	return {"ok": true, "code": "supported"}

func _patch(entity_id: String, entity: Dictionary, changes: Dictionary) -> Dictionary:
	return {"entity_id": entity_id, "expected_revision": int(entity.get("revision", 0)), "changes": changes}

func _derive_power(entity: Dictionary, changes: Dictionary) -> void:
	# Authored source tags are alternatives: a solar/electrical object can stay on
	# after light expires if it still has sufficient electrical charge.
	if not (_tag(entity, "solar") or _tag(entity, "electrical") or _tag(entity, "thermal_engine")):
		return
	var state := entity.duplicate(true)
	state.merge(changes, true)
	var powered := false
	if _tag(entity, "solar"):
		powered = powered or float(state.get("light_level", 0.0)) >= float(state.get("light_threshold", 0.5))
	if _tag(entity, "electrical"):
		powered = powered or float(state.get("charge", 0.0)) >= float(state.get("power_threshold", 20.0))
	if _tag(entity, "thermal_engine"):
		powered = powered or float(state.get("temperature", 20.0)) >= float(state.get("heat_threshold", 50.0))
	changes.powered = powered

func _tag(entity: Dictionary, tag: String) -> bool:
	return tag in entity.get("tags", [])

func _position_valid(value: Variant) -> bool:
	return value is Vector3 and value.is_finite()

func _reject(code: String) -> Dictionary:
	return {"ok": false, "code": code, "patches": [], "events": [], "physics_requests": []}
