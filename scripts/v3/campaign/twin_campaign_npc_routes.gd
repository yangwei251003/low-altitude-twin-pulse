class_name TwinCampaignNpcRoutes
extends RefCounted
## Expands the existing ecology implementation. No second simulation or save bank.
const EXTRA_PATH := "res://data/v3/campaign/npc_routes.json"

static func combined_definition(base: Dictionary, extra_path: String = EXTRA_PATH) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(extra_path))
	if not parsed is Dictionary or parsed.get("schema_version") != 1:
		return {"ok":false, "code":"campaign_npc_definition_invalid"}
	if not base.get("regions") is Array or not base.get("actors") is Array:
		return {"ok":false, "code":"base_npc_definition_invalid"}
	var merged: Dictionary = base.duplicate(true)
	var region_ids: Array = []
	var actor_ids: Array = []
	for region in merged.regions: region_ids.append(str(region.id))
	for actor in merged.actors: actor_ids.append(str(actor.id))
	for region in parsed.get("regions", []):
		if not region is Dictionary or region_ids.has(str(region.get("id", ""))):
			return {"ok":false, "code":"duplicate_campaign_npc_region"}
		region_ids.append(str(region.id))
		merged.regions.append(region.duplicate(true))
	for actor in parsed.get("actors", []):
		if not actor is Dictionary or actor_ids.has(str(actor.get("id", ""))):
			return {"ok":false, "code":"duplicate_campaign_npc_actor"}
		actor_ids.append(str(actor.id))
		merged.actors.append(actor.duplicate(true))
	# Existing limit is 12; the authored expansion adds exactly 7 to the old 5.
	if merged.regions.size() > 8 or merged.actors.size() > 12:
		return {"ok":false, "code":"existing_ecology_budget_exceeded"}
	return {"ok":true, "code":"combined", "definition":merged}

static func migrate_snapshot(previous, expanded) -> Dictionary:
	# Both instances are the real TwinEcologyState, configured independently.
	# Validate the old snapshot against its old graph before changing the digest.
	var old: Dictionary = previous.snapshot()
	var checked: Dictionary = previous.validate_snapshot(old)
	if not checked.get("ok", false): return checked
	var fresh: Dictionary = expanded.snapshot()
	if old.get("content_id") != fresh.get("content_id"):
		return {"ok":false, "code":"npc_content_identity_changed"}
	for region in old.contexts:
		if not fresh.contexts.has(region): return {"ok":false, "code":"npc_old_region_removed"}
		fresh.contexts[region] = old.contexts[region].duplicate(true)
	for id in old.actors:
		if not fresh.actors.has(id): return {"ok":false, "code":"npc_old_actor_removed"}
		fresh.actors[id] = old.actors[id].duplicate(true)
	for key in ["seed", "rng_state", "tick", "pending_usec", "event_serial"]:
		fresh[key] = old[key]
	# This rechecks every old actor's route/position/cargo under the new definition.
	# Changing an old route makes migration fail instead of teleporting the actor.
	checked = expanded.validate_snapshot(fresh)
	if not checked.get("ok", false): return checked
	return {"ok":true, "code":"npc_migration_prepared", "snapshot":fresh}

static func region_context(region: String, flags: Dictionary, weather: String = "clear", dangerous_nodes: Array = []) -> Dictionary:
	var service: bool = bool(flags.get({"I2":"I2:canal_service_ready", "I3":"I3:cooling_ready", "F3":"F3:signal_isolated", "I4":"I4:defence_isolated", "F4":"F4:living_link_ready"}.get(region, ""), false))
	# Flight remains possible when a facility is unpowered; the old actor policies
	# implement reserve, waiting, return-to-supply and weather shelter behavior.
	return {"powered":true, "supply_powered":service,
		"maintenance_powered":service, "weather":weather, "danger_nodes":dangerous_nodes.duplicate()}

static func objective_fact(event: Dictionary, verified_route: String = "") -> Dictionary:
	# Caller must pass an event from the authoritative ecology.advance return,
	# after committing its state. Never call this on a client supplied payload.
	if event.get("actor_id") != "F3:nutrient_01" or event.get("kind", event.get("type")) != "transport_arrival" or event.get("target_id") != "F3:nutrient_receiver":
		return {}
	if verified_route not in ["grown_path", "existing_bypass"]: return {}
	return {"type":"fact", "target_id":"F3:nutrient_delivery_verified", "option":verified_route,
		"source_event_id":event.get("event_id", event.get("id", "")), "source_serial":event.get("serial", -1)}
