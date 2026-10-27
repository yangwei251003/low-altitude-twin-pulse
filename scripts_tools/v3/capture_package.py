"""Render the exported executable from its own folder, without a source --path."""
from datetime import datetime
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--exe", type=Path, default=ROOT / "build/V3Development/LowAltitudeTwinPulse-Dev.exe")
parser.add_argument("--timeout-seconds", type=int, default=180,
                    help="Whole 26-view capture including live clinic flow and four facilities, not a frame-time acceptance limit (30-300).")
args = parser.parse_args()
if not 30 <= args.timeout_seconds <= 300:
    parser.error("--timeout-seconds must be between 30 and 300")
EXE = args.exe.resolve(strict=True)
stamp = datetime.now().strftime("%Y%m%d_%H%M%S") + "_" + uuid.uuid4().hex[:6]
output = ROOT / "artifacts/v3/art" / ("package-" + stamp)
output.mkdir(parents=True)
before = hashlib.sha256(EXE.read_bytes()).hexdigest()
command = [str(EXE), "--position", "-4000,-4000", "--log-file", str(output / "engine.log"), "--",
           "--qa-profile=qa_visual_packaged_" + stamp, "--qa-capture-output=" + str(output)]
started = time.monotonic()
try:
    result = subprocess.run(command, cwd=EXE.parent, capture_output=True, timeout=args.timeout_seconds,
                            creationflags=subprocess.CREATE_NO_WINDOW)
    capture = json.loads((output / "capture.json").read_text(encoding="utf-8"))
    log = (output / "engine.log").read_text(encoding="utf-8", errors="replace")
    legacy = capture["shots"][:13]
    clinic_all = capture["shots"][13:20]
    facility_shots = capture["shots"][20:23]
    waterfront_shots = capture["shots"][23:24]
    waterfront = waterfront_shots[0]["waterfront"] if len(waterfront_shots) == 1 else {}
    extension_shots = capture["shots"][24:26]
    extension_probes = [waterfront.get("extensions", {})] + [shot["extensions"] for shot in extension_shots]
    expected_closure_json = {name: hashlib.sha256((ROOT / f"data/v3/terrain/{name}.json").read_bytes()).hexdigest()
                             for name in ("i2_revetment_closure_layout", "i2_revetment_closure_delivery")}
    facility_probes = [shot["facilities"] for shot in facility_shots]
    clinic = clinic_all[:3]
    art_probes = [shot["clinic"] for shot in clinic_all]
    clinic_probes = [shot["clinic"] for shot in clinic]
    expected_clinic_sha = hashlib.sha256((ROOT / "data/v3/terrain/i2_clinic_layout.json").read_bytes()).hexdigest()
    expected_layouts = {name: hashlib.sha256((ROOT / f"data/v3/terrain/{name}.json").read_bytes()).hexdigest()
                        for name in ("i2_clinic_layout", "i2_distribution_layout", "i2_trial_flow_layout", "i2_shared_access_layout")}
    water_totals = [sum(int(node["clean_ml"]) + int(node["dirty_ml"])
                        for node in probe["state"]["runtime"]["simulation"]["nodes"].values())
                    for probe in clinic_probes]
    checks = {
        "exit_zero": result.returncode == 0,
        "no_engine_error": "ERROR:" not in log,
        "exported_runtime": capture["editor_binary"] is False,
        "original_twenty_four_views_then_pit_and_north_closure": [shot["view"] for shot in capture["shots"]] == ["I1", "F1", "I1-whale", "I1-overpass", "F1-root-arch", "I1-ecology", "F1-crown", "F1-shore", "F1-growth-gap", "F1-growth-open", "I1-thermal", "I1-underdeck-south", "I1-underdeck-inside", "I2-arrival", "I2-high-valve", "I2-full-water", "I2-reception-interior", "I2-reception-skylight", "I2-gravity-undercroft", "I2-paving", "I2-distribution", "I2-trial-connected", "I2-shared-access", "I2-waterfront-channel", "I2-inspection-pit-default", "I2-closure-north"],
        "whale_loaded": capture["shots"][2]["whale_imported"] is True,
        "imports_loaded": all(shot["landmark_imported"] and shot["prop_imported"] for shot in legacy),
        "terrain_loaded": [shot["terrain_modules"] for shot in legacy] == [6, 3, 6, 6, 3, 6, 3, 3, 3, 3, 6, 6, 6],
        "traversal_loaded": all(shot["traversal_imported"] for shot in legacy),
        "ecology_loaded": [shot["ecology_actors"] for shot in legacy] == [3, 2, 3, 3, 2, 3, 2, 2, 2, 2, 3, 3, 3],
        "transport_produced_stock": capture["shots"][5]["coolant"] > 0 and capture["shots"][5]["deliveries"] > 0,
        "crown_loaded": capture["shots"][6]["crown_imported"] is True,
        "production_seal_imported": all(s["seal_imported"] and s["seal_triangles"] == 18528 for s in capture["shots"] if s["region"] == "F1"),
        "production_forest_texture_imported_with_mipmaps": all(len(s.get("ground_materials", [])) == 2 and all(m["fantasy"] is True and m["imported_texture"] is True and m["texture_path"] == "res://assets/v3/materials/forest_floor_surface_v1.png" and m["width"] == 1254 and m["height"] == 1254 and m["mipmaps"] is True for m in s["ground_materials"]) for s in capture["shots"] if s["region"] == "F1"),
        "industrial_material_has_no_forest_binding": all(len(s.get("ground_materials", [])) == 2 and all(m["fantasy"] is False and m["imported_texture"] is False for m in s["ground_materials"]) for s in capture["shots"] if s["region"] == "I1"),
        "ungrown_gap_has_no_bridge_collision": capture["shots"][8]["growth_crossing"]["bridge_visible"] is False and capture["shots"][8]["growth_crossing"]["bridge_collision"] == 0,
        "growth_bridge_and_gate_respond_to_real_abilities": capture["shots"][9]["growth_crossing"]["bridge_visible"] is True and capture["shots"][9]["growth_crossing"]["bridge_collision"] == 1 and capture["shots"][9]["growth_crossing"]["gate_fraction"] > .99 and capture["shots"][9]["growth_crossing"]["abilities_total"] - capture["shots"][8]["growth_crossing"]["abilities_total"] == 5 and capture["shots"][9]["growth_crossing"]["rejected_total"] == capture["shots"][8]["growth_crossing"]["rejected_total"],
        "both_growth_approaches_loaded": all(s["growth_crossing"]["approaches_loaded"] for s in capture["shots"] if s["view"].startswith("F1-growth")),
        "thermal_imported_with_final_geometry": capture["shots"][10]["thermal"]["imported"] is True and capture["shots"][10]["thermal"]["import_errors"] == [] and capture["shots"][10]["thermal"]["meshes"] == 6 and capture["shots"][10]["thermal"]["surfaces"] == 10 and capture["shots"][10]["thermal"]["triangles"] == 11868,
        "thermal_replaces_placeholder_with_same_collision": capture["shots"][10]["thermal"]["old_placeholder_hidden"] is True and capture["shots"][10]["thermal"]["collision_box"] == "(3.0, 2.0, 2.0)",
        "underdeck_actual_module_and_unreleased_state": all(s["underdeck"]["configured"] is True and s["underdeck"]["collision_triangles"] == 696 and s["underdeck"]["state"]["latched"] is False and s["underdeck"]["state"]["front_fraction"] == 0 and s["underdeck"]["state"]["rear_fraction"] == 0 and s["underdeck"]["front_target_matches_body"] is True for s in capture["shots"][11:13]),
        "underdeck_floor_survives_interior_cover_fade": all(s["underdeck"]["floor_opaque"] is True for s in capture["shots"][11:13]) and capture["shots"][12]["underdeck"]["cover_faded"] is True,
        "underdeck_both_authored_gates_and_imported_materials": all(len(s["underdeck"].get("authored_gates", [])) == 2 and all(g["meshes"] == 7 and g["surfaces"] == 14 and g["triangles"] == 16644 and g["pbr_textures_imported"] is True and g["lamp_is_authored_lens"] is True for g in s["underdeck"]["authored_gates"]) for s in capture["shots"][11:13]),
        "underdeck_authored_four_mesh_shell_pbr": all(s["underdeck"]["authored_shell"]["installed"] is True
            and s["underdeck"]["authored_shell"]["path"] == "res://assets/v3/underdeck_shell/underdeck_shell.glb"
            and s["underdeck"]["authored_shell"]["meshes"] == 4 and s["underdeck"]["authored_shell"]["surfaces"] == 8
            and s["underdeck"]["authored_shell"]["triangles"] == 16872
            and s["underdeck"]["authored_shell"]["pbr_textures_imported"] is True
            and s["underdeck"]["authored_shell"]["hidden_collision_visuals"] == 3
            and s["underdeck"]["authored_shell"]["legacy_visuals_hidden"] is True
            and len(s["underdeck"]["authored_shell"]["covers"]) == 3 for s in capture["shots"][11:13]),
        "underdeck_interior_details_exit_at_full_cutaway": len([m for m in capture["shots"][12]["underdeck"]["authored_shell"]["covers"] if m["detail"]]) == 2
            and all(m["alphas"] and all(abs(alpha - (0.0 if m["detail"] else 0.2)) < 0.001 for alpha in m["alphas"])
                    for m in capture["shots"][12]["underdeck"]["authored_shell"]["covers"]),
        "clinic_three_actual_hydraulic_views": len(clinic) == 3 and all(s["region"] == "I2" and s["stage"] == "authored_clinic_partial"
            and s["camera_size"] == 26 and s["viewport"] == [1280, 720] for s in clinic),
        "clinic_visible_module_and_packaged_layout": len(clinic_probes) == 3 and all(p["module_ready"] is True
            and p["world_owns_module"] is True and p["background_absent"] is True and p["authority"] is True
            and p["build_errors"] == [] and p["layout_sha256"] == expected_clinic_sha for p in clinic_probes),
        "clinic_live_gravity_fills_conserved_water": len(clinic_probes) == 3
            and clinic_probes[0]["status"]["clinic_volume_ml"] == 0 and clinic_probes[0]["history"]["route_method"] == ""
            and 0 < clinic_probes[1]["status"]["clinic_volume_ml"] < 2000000
            and clinic_probes[1]["status"]["gravity_fraction"] >= 0.995 and clinic_probes[1]["history"]["route_method"] == "gravity"
            and clinic_probes[2]["status"]["clinic_volume_ml"] == 2000000
            and clinic_probes[2]["history"]["route_method"] == "gravity"
            and clinic_probes[2]["status"]["inlet_closed"] is True
            and clinic_probes[2]["history"]["stable_usec"] == 2000000
            and water_totals[0] > 2000000 and len(set(water_totals)) == 1,
        "clinic_nine_moving_parts_and_targets_are_real_physics": len(clinic_probes) == 3
            and all(p["physics_matches"] is True and len(p["moving_parts"]) == 9 and p["maximum_pose_error"] < 0.001
                and p["targets_match"] is True and p["deck_ray_correct"] is True for p in clinic_probes),
        "clinic_full_deck_y5_water_surface_and_open_access": len(clinic_probes) == 3
            and abs(clinic_probes[2]["status"]["deck_top_y"] - 5.0) < 0.001
            and clinic_probes[2]["physical_access"] is True and clinic_probes[2]["water_is_noncolliding"] is True
            and all(p["water_surface_matches"] is True for p in clinic_probes),
        "clinic_exact_saved_water_without_goal_or_reward_injection": len(clinic_probes) == 3
            and all(p["persistence_matches"] is True and p["store_reread_matches"] is True
                and p["capture_state_stable"] is True and p["no_new_objectives_or_discoveries"] is True
                and p["commissioned"] is False and p["ready_flag"] is False for p in clinic_probes),
        "clinic_bounded_production_steps_and_internal_checks": len(capture.get("clinic_live_windows", [])) == 2
            and all(w["reached"] is True and 0 < w["simulated_seconds"] <= w["limit_seconds"] + 0.001
                and w["fixed_steps"] > 0 for w in capture["clinic_live_windows"])
            and bool(capture.get("clinic_checks")) and all(c["passed"] is True for c in capture["clinic_checks"]),
        "clinic_seven_current_art_views": len(clinic_all) == 7 and {s["view"] for s in clinic_all} == {
            "I2-arrival", "I2-high-valve", "I2-full-water", "I2-reception-interior", "I2-reception-skylight", "I2-gravity-undercroft", "I2-paving"},
        "clinic_imported_gravity_and_support_pbr": len(art_probes) == 7 and all(
            p["art"]["gravity"] == {"meshes":5,"triangles":14296,"surfaces":5,"textured_surfaces":4,"normal_surfaces":4}
            and p["art"]["support"] == {"meshes":2,"triangles":4520,"surfaces":2,"textured_surfaces":2,"normal_surfaces":2} for p in art_probes),
        "clinic_imported_room_atlas_and_paving_pbr": len(art_probes) == 7 and all(
            p["art"]["reception"] == {"meshes":186,"triangles":15951,"surfaces":186,"textured_surfaces":178,"normal_surfaces":0}
            and p["art"]["paving"] == {"meshes":2,"triangles":3276,"surfaces":2,"textured_surfaces":2,"normal_surfaces":2} for p in art_probes),
        "west_rooms_remapped_glb_and_pbr_loaded_from_package": len(art_probes) == 7 and all(
            [r["id"] for r in p["art"]["west_rooms"]] == ["WestLowRoof","WestOffsetRoof"]
            and [r["imported"]["stats"]["triangles"] for r in p["art"]["west_rooms"]] == [3608,5696]
            and all(r["imported"]["ok"] is True and r["imported"]["pbr"] == {"ok":True,"source_materials":3}
                    for r in p["art"]["west_rooms"]) for p in art_probes),
        "west_rooms_original_boxes_retained_in_packaged_world": len(art_probes) == 7 and all(
            all(r["original_box_and_hidden_placeholder"] is True for r in p["art"]["west_rooms"]) for p in art_probes),
        "clinic_eight_tile_courtyard_and_receiving_approach": len(art_probes) == 7 and all(
            p["art"]["courtyard"] == {"meshes":16,"triangles":8216,"surfaces":16,"textured_surfaces":16,"normal_surfaces":16}
            and [t["id"] for t in p["art"]["courtyard_tiles"]] == ["DrainEdge","ServiceWest","ServiceEast","ArrivalWest","ArrivalMiddle","ArrivalEast","ReceivingApproachWest","ReceivingApproachEast"]
            for p in art_probes),
        "maintenance_eight_variants_real_imported_meshes": len(art_probes) == 7 and all(
            p["art"]["maintenance"]["ok"] is True
            and p["art"]["maintenance"]["path"] == "res://assets/v3/i2_maintenance_paving/maintenance_paving.glb"
            and p["art"]["maintenance"]["stats"] == {"meshes":12,"triangles":14280,"surfaces":12,"textured_surfaces":12,"normal_surfaces":12}
            and p["art"]["maintenance"]["pbr"] == {"ok":True,"source_materials":1}
            and p["art"]["maintenance"]["area_m2"] == 160
            and [t["id"] for t in p["art"]["maintenance"]["tiles"]] == ["W0","W1","W2","W3","E0","E1","E2","E3"]
            and all(t["bounds_match"] is True for t in p["art"]["maintenance"]["tiles"]) for p in art_probes),
        "clinic_art_views_preserve_saved_unconfirmed_water": len(art_probes) == 7 and all(
            p["persistence_matches"] is True and p["store_reread_matches"] is True and p["capture_state_stable"] is True
            and p["no_new_objectives_or_discoveries"] is True and p["commissioned"] is False
            and p["art"]["service_available"] is False and p["art"]["service_color"] == "dba358" for p in art_probes),
        "current_definitions_and_protocol_loaded_from_package": capture.get("protocol") == 21
            and capture.get("content", {}).get("actions") == 9 and capture["content"]["objectives"] == 34
            and len(set(capture["content"]["action_ids"])) == 9 and capture["content"]["historical_fixture_used"] is False,
        "four_required_facility_slots": capture.get("facility_contract", {}).get("version") == 1
            and [(d["slot"], d["id"], d["region"], d["envelope"]) for d in capture["facility_contract"]["definitions"]]
                == [(1,"clinic","I2",1),(2,"distribution","I2",1),(3,"trial","I2",1),(4,"shared_access","I2",1)]
            and len(capture["facility_contract"]["fingerprint"]) == 64,
        "three_facility_views_default_camera_and_clear_body": len(facility_shots) == 3
            and all(s["region"] == "I2" and s["camera_size"] == 26 and s["viewport"] == [1280,720] for s in facility_shots)
            and bool(capture.get("facility_checks")) and all(c["passed"] is True for c in capture["facility_checks"]),
        "four_actual_world_modules_saved_and_physical": len(facility_probes) == 3 and all(
            p["ok"] is True and p["layout_hashes"] == expected_layouts
            and [m["id"] for m in p["modules"]] == ["clinic","distribution","trial","shared_access"]
            and all(m["ok"] is True and m["ready"] is True and m["world_owned"] is True and m["authority"] is True
                and m["snapshot_validation"]["ok"] is True and m["persisted"] is True and bool(m["state"])
                and m["physics_matches"] is True and bool(m["physics"]) and all(b["matches"] is True for b in m["physics"])
                and m["targets_match"] is True and bool(m["targets"]) and all(t["matches"] is True for t in m["targets"])
                for m in p["modules"]) for p in facility_probes),
        "four_facility_wire_refs_lossless_local_codec": len(facility_probes) == 3 and all(
            p["protocol"] == 21 and p["refs_valid"] is True and sorted(r[0] for r in p["refs"]) == [1,2,3,4]
            and all(r[1] >= 1 and r[2] >= 1 for r in p["refs"]) and p["codec_roundtrip"] is True
            and p["contract_fingerprint"] == capture["facility_contract"]["fingerprint"] for p in facility_probes),
        "connected_trial_and_locked_public_bridge_real_routes": len(facility_probes) == 3 and all(
            p["connection"]["ok"] is True and p["connection"]["trial_ready"] is False
            and p["bridge"]["pose_valid"] is True and p["bridge"]["locked"] is True and p["bridge"]["mode"] == "public_span"
            and p["access"]["choice_ready"] is True and p["access"]["public_access"] is True and p["access"]["service_access"] is True
            and p["access"]["width_m"] == 3 and p["access"]["height_m"] == 2.8 and p["access"]["resident_ai"] is False for p in facility_probes),
        "facility_views_do_not_fabricate_observation_sample_or_choice": len(facility_probes) == 3 and all(
            p["capture_state_stable"] is True and p["story_and_personal_unchanged"] is True for p in facility_probes),
        "moving_bridge_twelve_imported_parts_pbr": len(facility_probes) == 3 and all(
            p["bridge_art"]["ok"] is True and p["bridge_art"]["mesh_count"] == 18
            and p["bridge_art"]["groups"]["moving"]["path"] == "res://assets/v3/shared_access_bridge_deck/shared_access_bridge_deck.glb"
            and p["bridge_art"]["groups"]["moving"]["stats"] == {"meshes":12,"triangles":10912,"surfaces":12,"textured_surfaces":12,"normal_surfaces":12}
            and p["bridge_art"]["groups"]["moving"]["pbr"] == {"ok":True,"source_materials":1} for p in facility_probes),
        "fixed_landings_six_imported_parts_two_pbr": len(facility_probes) == 3 and all(
            p["bridge_art"]["groups"]["fixed"]["path"] == "res://assets/v3/shared_access_landings/shared_access_landings.glb"
            and p["bridge_art"]["groups"]["fixed"]["stats"] == {"meshes":6,"triangles":13908,"surfaces":12,"textured_surfaces":12,"normal_surfaces":12}
            and p["bridge_art"]["groups"]["fixed"]["pbr"] == {"ok":True,"source_materials":2} for p in facility_probes),
        "eighteen_bridge_parts_follow_original_body_and_collision": len(facility_probes) == 3 and all(
            len(p["bridge_art"]["groups"]["moving"]["parts"]) == 12 and len(p["bridge_art"]["groups"]["fixed"]["parts"]) == 6
            and all(r["pose_matches"] is True and r["original_box_matches"] is True
                    for group in p["bridge_art"]["groups"].values() for r in group["parts"]) for p in facility_probes),
        "waterfront_default_view_and_bounded_checks": len(waterfront_shots) == 1
            and waterfront_shots[0]["view"] == "I2-waterfront-channel" and waterfront_shots[0]["region"] == "I2"
            and waterfront_shots[0]["camera_size"] == 26 and waterfront_shots[0]["viewport"] == [1280,720]
            and waterfront.get("ok") is True and waterfront["state_unchanged"] is True
            and bool(capture.get("waterfront_checks")) and all(c["passed"] is True for c in capture["waterfront_checks"]),
        "waterfront_actual_six_render_parts_and_ground_concave_shape": waterfront.get("shape_matches") is True
            and waterfront["ground_identity_matches"] is True and waterfront["legacy_visuals_hidden"] is True
            and waterfront["original_bank_shape_matches"] is True
            and waterfront["collision_triangles"] > 0 and len(waterfront["meshes"]) == 6
            and {m["id"] for m in waterfront["meshes"]} == {"dry_surface","bank","bed","outer","underside","water"}
            and all(m["source_matches"] is True and m["triangles"] > 0 and m["visible"] is (m["id"] != "bank") for m in waterfront["meshes"]),
        "waterfront_initial_partition_preserves_448m2_paving_baseline": waterfront.get("partition_matches") is True
            and waterfront["summary"]["cut_area_m2"] == 212.6 and waterfront["summary"]["authored_area_m2"] == 448
            and abs(waterfront["summary"]["visible_dry_area_m2"] - 2475.4) < 1e-6,
        "waterfront_authored_west_bank_four_real_imports": waterfront.get("revetment", {}).get("ok") is True
            and [p["width_m"] for p in waterfront["revetment"]["parts"]] == [4,4,4,1.3]
            and all(p["matches"] is True for p in waterfront["revetment"]["parts"])
            and abs(waterfront["revetment"]["summary"]["parts"]["bank"]["removed_area_m2"] - 37.24) < .0002
            and abs(waterfront["revetment"]["summary"]["parts"]["dry_surface"]["removed_area_m2"] - 4.655) < .0002,
        "waterfront_authored_east_bank_four_reused_imports": waterfront.get("east_revetment", {}).get("ok") is True
            and [p["width_m"] for p in waterfront["east_revetment"]["parts"]] == [4,4,4,1.3]
            and all(p["matches"] is True for p in waterfront["east_revetment"]["parts"])
            and abs(waterfront["east_revetment"]["summary"]["parts"]["bank"]["removed_area_m2"] - 37.24) < .0002
            and abs(waterfront["east_revetment"]["summary"]["parts"]["dry_surface"]["removed_area_m2"] - 4.655) < .0002,
        "waterfront_first_hit_bed_bank_paving_and_open_mouth": len(waterfront.get("rays", [])) == 5
            and [r["id"] for r in waterfront["rays"]] == ["bed","paving","bank","water_surface","south_mouth"]
            and all(r["matches"] is True for r in waterfront["rays"])
            and all(r["collider"].endswith("/Ground") for r in waterfront["rays"][:3])
            and all(r["collider"] == "" for r in waterfront["rays"][3:]),
        "waterfront_real_world_samples_and_shader_share_profile": waterfront.get("water_shader_profile_matches") is True
            and waterfront["water_surface_y_matches"] is True and waterfront["water_has_no_body"] is True and len(waterfront["samples"]) == 6
            and [s["water"] for s in waterfront["samples"]] == [True,True,False,False,False,False]
            and all(s["matches"] is True for s in waterfront["samples"]),
        "waterfront_current_pilot_hull_has_start_end_and_sweep_clearance": waterfront.get("hull", {}).get("ok") is True
            and waterfront["hull"]["start_clear"] is True and waterfront["hull"]["end_clear"] is True
            and len(waterfront["hull"]["fractions"]) == 2 and all(f >= .99999 for f in waterfront["hull"]["fractions"]),
        "pit_default_and_north_closure_real_package_views": len(extension_shots) == 2
            and [s["view"] for s in extension_shots] == ["I2-inspection-pit-default", "I2-closure-north"]
            and [s["zoom_steps"] for s in extension_shots] == [0,3]
            and abs(extension_shots[0]["camera_size"]-26) < .001
            and abs(extension_shots[1]["camera_size"]-26*.86**3) < .001
            and all(s["region"] == "I2" and s["viewport"] == [1280,720] and s["physics_pose_matches"] is True
                    and s["extensions"]["state_unchanged"] is True and s["extensions"]["collision_unchanged_during_capture"] is True for s in extension_shots),
        "production_extension_resources_use_actual_remapped_imports": len(extension_probes) == 3 and all(
            p["ok"] is True and all(p[key]["ok"] is True and p[key]["path_matches"] is True
                and p[key]["binding_matches"] is True and p[key]["visual_only"] is True
                and p[key]["source_glb_bytes_checked"] is False
                for key in ("east_maintenance","closure","pit","yard")) for p in extension_probes),
        "east_extension_two_meshes_16724_triangles_two_imported_pbr": len(extension_probes) == 3 and all(
            p["east_maintenance"]["path"] == "res://assets/v3/i2_east_maintenance_extension/east_maintenance_extension.glb"
            and p["east_maintenance"]["stats"] == {"meshes":2,"triangles":16724,"surfaces":2}
            and p["east_maintenance"]["pbr"] == {"ok":True,"source_materials":2}
            and abs(p["east_maintenance"]["removed_area_m2"]-97.545) < .0002 for p in extension_probes),
        "closure_twelve_meshes_32122_triangles_and_raw_json_contract": len(extension_probes) == 3 and all(
            p["closure"]["path"] == "res://assets/v3/environment/i2_revetment_closure/revetment_closure.glb"
            and p["closure"]["stats"] == {"meshes":12,"triangles":32122,"surfaces":14}
            and p["closure"]["pbr"] == {"ok":True,"source_materials":2}
            and p["closure"]["json_hashes"] == expected_closure_json
            and p["closure"]["old_bank_hidden"] is True and p["closure"]["original_collision_preserved_at_install"] is True
            and abs(p["closure"]["report"]["bank"]["removed_area_m2"]-94.281507675845) < .0005
            and abs(p["closure"]["report"]["dry_surface"]["removed_area_m2"]-11.631794036146) < .0005 for p in extension_probes),
        "pit_three_meshes_19640_triangles_three_imported_pbr": len(extension_probes) == 3 and all(
            p["pit"]["path"] == "res://assets/v3/environment/inspection_pit/inspection_pit.glb"
            and p["pit"]["stats"] == {"meshes":3,"triangles":19640,"surfaces":3}
            and p["pit"]["pbr"] == {"ok":True,"source_materials":3}
            and [row["id"] for row in p["old_pit_parts"]] == ["floor","walls","coping","ramp"]
            and all(row["hidden_geometry_matches"] is True and row["triangles"] > 0 for row in p["old_pit_parts"]) for p in extension_probes),
        "pit_floor_ramp_yard_are_real_ground_first_hits_and_dry": len(extension_probes) == 3 and all(
            p["pit_is_dry"] is True and [r["id"] for r in p["pit_rays"]] == ["pit_floor","pit_ramp","pit_yard"]
            and all(r["matches"] is True and r["collider"].endswith("/Ground") for r in p["pit_rays"]) for p in extension_probes),
        "yard_three_meshes_1202_triangles_three_imported_pbr": len(extension_probes) == 3 and all(
            p["yard"]["path"] == "res://assets/v3/environment/yard_connector/yard_connector_field.glb"
            and p["yard"]["stats"] == {"meshes":3,"triangles":1202,"surfaces":3}
            and p["yard"]["pbr"] == {"ok":True,"source_materials":3} for p in extension_probes),
        "final_dry_surface_accounts_for_banks_extension_closure_pit_and_yard": len(extension_probes) == 3 and all(
            p["areas"]["ok"] is True and abs(p["areas"]["pit_cut_m2"]-83.125) < .0002
            and abs(p["areas"]["pit_visible_cut_m2"]-83.125) < .0002
            and abs(p["areas"]["original_collision_area_m2"]-p["areas"]["retained_collision_area_m2"]-83.125) < .001
            and abs(p["areas"]["final_dry_m2"]-p["areas"]["expected_final_dry_m2"]) < .001
            and abs(p["areas"]["final_dry_m2"]-1977.207571565) < .001 for p in extension_probes),
        "export_geometry_verified_without_source_glb": all(s["shore_verification"].get("imported_geometry_verified") is True and s["shore_verification"].get("source_verified") is False and s["raw_glb_present"] is False for s in capture["shots"] if s["region"] == "F1"),
        "compact_hud_fits_after_first_layout": all(0 < shot["task_panel_height"] <= 320 and abs(shot["task_panel_height"] - shot["task_panel_min_height"]) <= 1 for shot in capture["shots"]),
        "screenshots_saved": all(Path(shot["path"]).stat().st_size > 10000 for shot in capture["shots"]),
        "executable_unchanged": hashlib.sha256(EXE.read_bytes()).hexdigest() == before,
    }
except Exception as error:
    checks = {"capture_completed": False, "error": str(error)}
passed = all(value is True for value in checks.values())
report = {"passed": passed, "checks": checks, "executable_sha256": before,
          "wall_seconds": time.monotonic() - started, "watchdog_seconds": args.timeout_seconds,
          "saved_png_count": len(list(output.glob("*.png"))),
          "runtime_cwd": str(EXE.parent), "source_path_passed": False, "command": command,
          "scope": "exported executable actual GPU screenshots; original24 views plus pit/default and north-closure QA poses. Actual dev29 low/offset service rooms, continuous forecourt, east maintenance extension, closure and inspection pit imports alongside all existing paving/bridge/bank checks. Seven clinic probes verify both remapped room models and original boxes; no new room flight route is claimed. Same original Ground body with intentionally replaced pit shape; final raw geometry, cut areas, floor/ramp first-hit rays and original canal/water checks. JSON raw hashes are checked; remapped GLB original bytes are not claimed. North seam only visible portions require image review. Scripted frozen poses and direct QA region initialization; no historical27 seed, observation/sample/bridge-choice or action completion injection. Local codec and static hull queries are not ENet/reconnect, real-input canal traversal, water-rescue, human comfort, performance or final-art proof"}
(output / "validation.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps({"passed": passed, "output": str(output), "checks": checks}, ensure_ascii=False, indent=2))
raise SystemExit(0 if passed else 1)
