"""Validate the authoritative V2 catalog and reproducibly generate runtime JSON."""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs/v2/data/world_content.json"
RUNTIME = ROOT / "data/v2/world_content.json"
SLOTS = ("weapon", "tool", "drive", "battery", "utility")
ACTIONS = {"scan", "clear", "pickup", "deliver", "defend", "escort", "gate", "interact", "return"}
FRAME_FIELDS = {"id", "name", "version", "dry_mass_kg", "max_takeoff_mass_kg", "cargo_rating_kg", "max_thrust_n", "width_m", "length_m", "height_m", "motion_limits", "health", "heat_capacity", "capacity_pu", "base_flight_pu", "cost", "unlock_mission", "rotor_count", "silhouette", "innate_ability", "modifiers", "recommended_tags", "mount_types"}
MODULE_FIELDS = {"id", "name", "slot", "cost", "mass_kg", "mass_delta_kg", "power_pu", "capacity_delta_pu", "mount_type", "free", "ability", "unlock_mission", "modifiers", "envelope_size_m", "exclusive_tags"}
ROOT_FIELDS = {"schema_version", "document_version", "status", "content_version", "catalog", "airframes", "mount_layout", "modules", "mode_configs", "units", "count_contract", "regions", "missions", "airframe_challenges", "difficulty_presets", "economy", "side_modes", "references", "difficulty_schedule", "airframe_challenge_loaner_tool_policy", "service_points", "tool_slot_policy"}


def validate(data: dict, require_actions: bool = True) -> list[str]:
    errors: list[str] = []

    def check(condition: bool, message: str) -> None:
        if not condition:
            errors.append(message)

    def indexed(items: list, label: str) -> dict:
        result: dict = {}
        for item in items:
            if not isinstance(item, dict) or not isinstance(item.get("id"), str):
                errors.append(f"{label}: item lacks string id")
                continue
            identifier = item["id"]
            check(identifier not in result, f"{label}: duplicate id {identifier}")
            result[identifier] = item
        return result

    def finite(value, path: str = "root") -> None:
        if isinstance(value, float):
            check(math.isfinite(value), f"{path}: non-finite number")
        elif isinstance(value, dict):
            for key, child in value.items():
                finite(child, f"{path}.{key}")
        elif isinstance(value, list):
            for index, child in enumerate(value):
                finite(child, f"{path}[{index}]")

    check(data.get("schema_version") == 2, "schema_version must be 2")
    check(not set(data) - ROOT_FIELDS, f"unknown root fields: {sorted(set(data) - ROOT_FIELDS)}")
    finite(data)
    regions = indexed(data.get("regions", []), "regions")
    frames = indexed(data.get("airframes", []), "airframes")
    modules = indexed(data.get("modules", []), "modules")
    missions = indexed(data.get("missions", []), "missions")
    challenges = indexed(data.get("airframe_challenges", []), "challenges")
    modes = indexed(data.get("mode_configs", []), "mode_configs")
    pois: dict = {}
    sectors: dict = {}
    for region_id, region in regions.items():
        region_pois = indexed(region.get("pois", []), region_id + " pois")
        region_sectors = indexed(region.get("sectors", []), region_id + " sectors")
        check(len(region_pois) == 24 and len(region_sectors) == 6, f"{region_id}: expected 24 POIs and 6 sectors")
        check(sum(bool(p.get("hidden")) for p in region_pois.values()) == 6, f"{region_id}: expected 6 hidden POIs")
        check(region.get("size_xz_m") == [600, 500], f"{region_id}: wrong bounds")
        for poi_id, poi in region_pois.items():
            check(poi_id not in pois, f"duplicate POI {poi_id}")
            sector = region_sectors.get(poi.get("sector_id"))
            check(sector is not None, f"{poi_id}: missing sector")
            if sector is not None:
                x, z = poi["position_xz_m"]
                x0, z0, x1, z1 = sector["bounds_xz_m"]
                check(x0 <= x <= x1 and z0 <= z <= z1, f"{poi_id}: outside sector")
            check(bool(poi.get("purpose")), f"{poi_id}: missing gameplay purpose")
        pois.update(region_pois)
        sectors.update(region_sectors)
    paid_modules = {key: item for key, item in modules.items() if item.get("cost", 0) > 0}
    counts = {"regions": len(regions), "sectors": len(sectors), "pois": len(pois), "hidden_pois_subset": sum(bool(p.get("hidden")) for p in pois.values()), "main_missions": len(missions), "airframes": len(frames), "airframe_challenges": len(challenges), "repeatable_mode_types": len(data.get("side_modes", []))}
    check(counts == data.get("count_contract"), f"count contract mismatch: {counts}")
    check(len(paid_modules) == 8, "expected exactly 8 paid modules")
    check(len(modes) == 12, "expected exactly 12 regional side modes")
    check(sum(x["cost"] for x in paid_modules.values()) == 1360, "paid modules must total 1360")
    check(sum(x["cost"] for x in frames.values()) == 1300, "airframes must total 1300")
    economy = data.get("economy", {})
    check(sum(m["first_reward_parts"] for m in missions.values()) == 4960 == economy.get("campaign_first_total"), "campaign first rewards must total 4960")
    check(sum(p["reward"]["parts_first_discovery"] for p in pois.values()) == 360, "secret first rewards must total 360")
    check(economy.get("total_fixed_once_rewards_excluding_repeats") == 6900, "fixed first reward total must be 6900")
    for entry in economy.get("fleet", []):
        frame = frames.get(entry["id"], {})
        check(frame.get("cost") == entry["craft_cost"] and frame.get("unlock_mission") == entry["blueprint_mission"], f"fleet economic drift: {entry['id']}")
    for entry in economy.get("modules", []):
        check(modules.get(entry["id"], {}).get("cost") == entry["cost"], f"module economic drift: {entry['id']}")
    for frame_id, frame in frames.items():
        check(not set(frame) - FRAME_FIELDS, f"{frame_id}: unknown fields {sorted(set(frame) - FRAME_FIELDS)}")
        for key in ("dry_mass_kg", "max_takeoff_mass_kg", "cargo_rating_kg", "max_thrust_n", "width_m", "length_m", "height_m", "health", "heat_capacity", "capacity_pu", "base_flight_pu"):
            check(isinstance(frame.get(key), (float, int)) and frame.get(key, 0) > 0, f"{frame_id}: invalid {key}")
        for key in ("speed_mps", "accel_mps2", "brake_mps2", "tilt_deg", "yaw_deg_s", "rise_mps", "fall_mps"):
            check(frame.get("motion_limits", {}).get(key, 0) > 0, f"{frame_id}: missing motion limit {key}")
        check(frame.get("unlock_mission") is None or frame["unlock_mission"] in missions, f"{frame_id}: unknown unlock mission")
    for module_id, module in modules.items():
        check(not set(module) - MODULE_FIELDS, f"{module_id}: unknown fields {sorted(set(module) - MODULE_FIELDS)}")
        slot = module.get("slot")
        check(slot in SLOTS, f"{module_id}: invalid slot")
        full, delta = "mass_kg" in module, "mass_delta_kg" in module
        check(full != delta, f"{module_id}: must use exactly one mass convention")
        check((delta if slot in ("drive", "battery") else full), f"{module_id}: wrong mass convention for slot")
        for key in ("power_pu", "capacity_delta_pu", "modifiers", "mount_type"):
            check(key in module, f"{module_id}: missing {key}")
        check(module.get("power_pu", -1) >= 0, f"{module_id}: negative power")
    tools = {t["id"]: t for t in economy.get("free_tools", [])}
    tool_map = data.get("catalog", {}).get("free_tool_map", {})
    for ability, module_id in tool_map.items():
        check(module_id in modules and ability in tools, f"invalid free tool mapping {ability}")

    def actions_check(owner: dict, label: str) -> None:
        actions = owner.get("actions", [])
        if require_actions:
            check(bool(actions), f"{label}: no executable actions")
        picked: set[str] = set()
        for action in actions:
            kind = action.get("type")
            check(kind in ACTIONS, f"{label}: unknown action {kind}")
            check(action.get("poi_id") in pois, f"{label}: unknown action POI {action.get('poi_id')}")
            check(bool(action.get("label")), f"{label}: missing action label")
            if "tool_id" in action:
                check(action["tool_id"] in modules, f"{label}: unknown action tool")
            if kind in ("pickup", "deliver"):
                cargo_id = action.get("cargo_id")
                check(isinstance(cargo_id, str) and bool(cargo_id), f"{label}: cargo lacks stable id")
                if kind == "pickup":
                    check(action.get("cargo_kg", 0) > 0 and action.get("cargo_kg", 99) <= 3, f"{label}: cargo not TR01-compatible")
                    check(cargo_id not in picked, f"{label}: duplicate pickup {cargo_id}")
                    picked.add(cargo_id)
                else:
                    check(cargo_id in picked, f"{label}: delivery without preceding pickup {cargo_id}")
                    picked.discard(cargo_id)
            if kind == "defend":
                check(action.get("waves", 0) > 0 and bool(action.get("enemy_roles")), f"{label}: defend must have finite enemy waves")
            roles = action.get("enemy_roles", [])
            check(all(role in {"shooter", "charger", "support", "boss"} for role in roles), f"{label}: unknown enemy role")
            check(roles.count("support") <= 2, f"{label}: support cap exceeds 2")
            for path_id in action.get("escort_path", []):
                check(path_id in pois, f"{label}: unknown escort waypoint {path_id}")
    stage_count = 0
    receipts: set[str] = set()
    for mission_id, mission in missions.items():
        check(mission.get("region_id") in regions, f"{mission_id}: unknown region")
        check(mission.get("prerequisite_mission") is None or mission["prerequisite_mission"] in missions, f"{mission_id}: unknown prerequisite")
        stages = mission.get("stages", [])
        check(len(stages) == 3, f"{mission_id}: requires 3 stages")
        check(sum(s["first_reward_parts"] for s in stages) == mission["first_reward_parts"], f"{mission_id}: reward split mismatch")
        for ordinal, stage in enumerate(stages, 1):
            stage_count += 1
            stage_id = stage.get("id")
            check(stage_id == f"{mission_id}-S{ordinal}", f"{mission_id}: invalid stable stage ID")
            receipt = stage.get("reward_id")
            check(receipt == f"campaign:{mission_id}:stage:{ordinal}:first" and receipt not in receipts, f"{stage_id}: receipt mismatch or duplicate")
            receipts.add(receipt)
            for poi_id in stage.get("poi_ids", []):
                check(poi_id in pois, f"{stage_id}: unknown POI {poi_id}")
            for ability in stage.get("required_free_tools", []):
                check(ability in tools and tools[ability]["mission"] <= mission_id, f"{stage_id}: tool used before grant {ability}")
            plan = stage.get("equipment_plan", {})
            check(plan.get("simultaneous_tool_limit") == 1, f"{stage_id}: single tool slot violated")
            check(plan.get("entry_service_poi") in pois, f"{stage_id}: missing entry service POI")
            actions_check(stage, str(stage_id))
            if "optional_actions" in stage:
                actions_check({"actions": stage["optional_actions"]}, str(stage_id) + " optional")
    check(stage_count == 48, "expected 48 stages")
    for challenge_id, challenge in challenges.items():
        check(challenge.get("airframe_id") in frames, f"{challenge_id}: unknown frame")
        check(challenge.get("first_reward_parts") == 60 and challenge.get("repeat_reward_parts") == 25, f"{challenge_id}: invalid rewards")
        limits = challenge.get("medal_time_limit_s", {})
        check(0 < limits.get("gold", 0) <= limits.get("silver", 0) <= limits.get("bronze", 0), f"{challenge_id}: invalid medal order")
        actions_check(challenge, challenge_id)
    for frame_id in frames:
        check(sum(c["airframe_id"] == frame_id for c in challenges.values()) == 3, f"{frame_id}: requires 3 challenges")
    for mode_id, mode in modes.items():
        check(mode.get("region_id") in regions, f"{mode_id}: unknown region")
        actions_check(mode, mode_id)
        if mode.get("mode") == "race":
            gate_count = sum(a.get("type") == "gate" for a in mode.get("actions", []))
            check(gate_count == mode.get("gate_count") and 12 <= gate_count <= 18, f"{mode_id}: gate count must match 12-18 actual gates")
        elif mode.get("mode") == "precision":
            check(sum(a.get("type") == "deliver" for a in mode.get("actions", [])) == 3, f"{mode_id}: requires three deliveries")
        elif mode.get("mode") == "salvage":
            cargo = [a for a in mode.get("actions", []) if a.get("type") == "pickup"]
            check(len(cargo) == 3 and sum(a.get("cargo_value", 0) for a in cargo) == 90, f"{mode_id}: salvage must total 90")
            check(all(a.get("optional") for a in cargo), f"{mode_id}: salvage selection must be optional")
    if "M02" in missions:
        check(missions["M02"]["enemy_composition_max_by_role"]["support"] == 1, "M02 must allow its required support enemy")
    return errors


def generate(data: dict, source_bytes: bytes) -> dict:
    runtime = copy.deepcopy(data)
    runtime["_source_sha256"] = hashlib.sha256(source_bytes).hexdigest()
    runtime["_source_path"] = "docs/v2/data/world_content.json"
    runtime["_generator_version"] = 1
    for frame in runtime["airframes"]:
        frame["model_scene"] = f"res://assets/v2/models/{frame['id']}.glb"
    for module in runtime["modules"]:
        module["visual_scene"] = "" if module["id"].startswith("stock_") else f"res://assets/v2/models/{module['id']}.glb"
    return runtime


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="Generate runtime JSON after validation")
    parser.add_argument("--self-test", action="store_true", help="Exercise malformed-content rejection")
    parser.add_argument("--allow-pending-actions", action="store_true", help="Development-only partial catalog generation")
    args = parser.parse_args()
    source_bytes = SOURCE.read_bytes()
    data = json.loads(source_bytes.decode("utf-8-sig"))
    errors = validate(data, require_actions=not args.allow_pending_actions)
    mutation_cases = 0
    if args.self_test:
        cases = []
        bad = copy.deepcopy(data)
        bad["schema_version"] = 3
        cases.append(bad)
        bad = copy.deepcopy(data)
        bad["regions"][0]["pois"][0]["id"] = bad["regions"][0]["pois"][1]["id"]
        cases.append(bad)
        bad = copy.deepcopy(data)
        bad["missions"][0]["stages"][0]["reward_id"] = "campaign:M01:stage:M01-S1:first"
        cases.append(bad)
        bad = copy.deepcopy(data)
        bad["modules"][0]["mass_delta_kg"] = 0.25
        cases.append(bad)
        bad = copy.deepcopy(data)
        bad["regions"][0]["pois"][0]["position_xz_m"] = [999, 999]
        cases.append(bad)
        bad = copy.deepcopy(data)
        bad["airframes"][0]["dry_mass_kg"] = float("nan")
        cases.append(bad)
        bad = copy.deepcopy(data)
        bad["modules"][0]["masss_kg"] = 2.0
        cases.append(bad)
        bad = copy.deepcopy(data)
        bad["missions"][0]["stages"][0]["actions"][0]["poi_id"] = "R1-P99"
        cases.append(bad)
        bad = copy.deepcopy(data)
        bad["missions"][1]["stages"][0]["actions"][1]["cargo_id"] = "phantom_cargo"
        cases.append(bad)
        for case in cases:
            mutation_cases += 1
            if not validate(case, require_actions=False):
                errors.append(f"self-test {mutation_cases} did not reject malformed content")
    runtime = generate(data, source_bytes)
    encoded = json.dumps(runtime, ensure_ascii=False, indent=2, allow_nan=False) + "\n"
    if not errors:
        if args.write:
            RUNTIME.parent.mkdir(parents=True, exist_ok=True)
            RUNTIME.write_text(encoded, encoding="utf-8", newline="\n")
        elif not RUNTIME.exists() or RUNTIME.read_text(encoding="utf-8") != encoded:
            errors.append("Runtime content is stale. Run scripts_tools/validate_v2_content.py --write.")
    report = {"ok": not errors, "errors": errors, "source_sha256": runtime["_source_sha256"], "mutation_cases": mutation_cases, "counts": data["count_contract"], "mode_configs": len(data["mode_configs"]), "paid_modules": sum(m["cost"] > 0 for m in data["modules"]), "actions_complete": not args.allow_pending_actions}
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
