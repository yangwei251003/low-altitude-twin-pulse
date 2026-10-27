"""Short native input/UI checks without OS input, project copies or asset scans."""
import argparse
import datetime
import json
import os
from pathlib import Path
import sys
import uuid

sys.dont_write_bytecode = True
import dev
from storage_policy import atomic_json


def gui_failures(report):
    failures = []
    if (report.get("finish_reason") != "observations_collected"
            or report.get("source_before") != report.get("source_after")
            or not report.get("pointer_filter")
            or any(isinstance(row, dict) and "not_covered" in row for row in report["coverage"])):
        failures.append("GUI coverage, mode, completion or source stability")
    if len(report["ui_cases"]) != 7 or any(row["actual_pressed_delta"] != 1 or row["actual_action_requested_delta"] != 1 for row in report["ui_cases"]):
        failures.append("native GUI callbacks must occur exactly once per ordinary click")
    positive = {
        "world_mouse_down", "world_origin_before_drag", "world_origin_dragged_to_UI",
        "source_Joy_before_Key", "source_Joy_to_Key", "source_Joy_before_Mouse", "source_Joy_to_Mouse",
        "logical_J_special_scan_down", "rebound_K_down", "configure_default_J_down", "rebound_joyY_down",
        "UI_virtual_J_plus_joyX", "UI_virtual_J_released_joyX_held",
        "world_mouse_plus_virtual_J", "world_mouse_virtual_J_released",
    }
    negative = {
        "neutral", "world_mouse_up", "UI_origin_before_drag", "UI_origin_dragged_to_world",
        "UI_origin_drag_release", "world_origin_drag_release", "source_switch_released",
        "logical_J_special_scan_up", "rebound_old_J_down", "rebound_K_up",
        "configure_default_K_down", "configure_default_J_up", "rebound_old_joyX_down", "rebound_joyY_up",
        "UI_virtual_J_and_joyX_released", "UI_combined_sources_released",
        "world_mouse_and_virtual_J_released",
    }
    expected = {label: True for label in positive} | {label: False for label in negative}
    for row in report["ui_cases"]:
        prefix = row["case"] + ":"
        for sample in report["samples"]:
            label = sample["label"]
            if label.startswith(prefix):
                expected[label] = ":mouse_plus_" in label or label.endswith(":mouse_up_extra_held")
    observed = {row["label"] for row in report["samples"]}
    if observed != set(expected) or len(observed) != len(report["samples"]):
        failures.append("sample coverage differs from the explicit case contract")
    for row in report["samples"]:
        if row["physics_fire"] != expected.get(row["label"]) or row["process_fire"] != expected.get(row["label"]):
            failures.append("fire command: " + row["label"])
        nav = {"source_Joy_before_Key": True, "source_Joy_to_Key": False,
               "source_Joy_before_Mouse": True, "source_Joy_to_Mouse": False}.get(row["label"])
        if nav is not None and (row["physics_controller_navigation"] != nav or row["process_controller_navigation"] != nav):
            failures.append("actual last-device navigation hint: " + row["label"])
    return failures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--packed-exe", type=Path, help="Read resources from the current immutable EXE through pinned Godot; not a direct Release EXE launch")
    parser.add_argument("--menu-entry", choices=("mouse", "keyboard"), help="Check ordinary menu entry through native in-game events; no OS input")
    parser.add_argument("--onboarding", action="store_true", help="Continue menu entry through native first contact and short physical W/Space/E flight")
    options = parser.parse_args()
    if options.onboarding and not options.menu_entry:
        parser.error("--onboarding requires --menu-entry")
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    os.environ["LOW_ALTITUDE_DEV_HOME"] = str(dev.POLICY.root)
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S") + "_" + uuid.uuid4().hex[:6]
    label = "pointer-input-" + stamp
    prefix = [dev.GODOT, "--headless", "--path", dev.ROOT]
    artifact = None
    if options.packed_exe:
        exe = options.packed_exe.resolve(strict=True)
        current = dev.POLICY._index().get("current")
        if exe != dev.POLICY.path("builds", current, "LowAltitudeTwinPulse-Dev.exe"):
            parser.error("packed resources must be the policy's current immutable EXE")
        artifact = {"exe": str(exe), "sha256": dev.file_sha256(exe),
                    "build": json.loads((exe.parent / "BUILD.json").read_text(encoding="utf-8"))}
        prefix += ["--main-pack", exe]
    inputs = ["scripts/input_router.gd", "scripts/v2/pilot_input.gd", "scripts/v3/twin_interface.gd",
              "scripts/v3/twin_session.gd", "scripts_tools/v3/probe_gui_input.gd",
              "scripts_tools/v3/probe_pointer_fire_session.gd", "scripts_tools/v3/check_pointer_input.py"]
    before = {path: dev.file_sha256(dev.ROOT / path) for path in inputs}
    cases = [("main", "scripts_tools/v3/probe_pointer_fire_session.gd", "POINTER_FIRE_SESSION_RESULT ",
              ["--qa-profile=qa_pointer_session_" + stamp], 55)]
    if options.menu_entry:
        cases[0][3].append("--native-menu=" + options.menu_entry)
        if options.onboarding:
            cases[0][3].append("--onboarding")
    elif not artifact:
        cases.insert(0, ("gui", "scripts_tools/v3/probe_gui_input.gd", "GUI_INPUT_PROBE_OBSERVATIONS ", ["--probe-pointer-filter"], 40))
        cases.append(("keyboard_modal", "tests_v3/test_keyboard_choice_focus.gd", "KEYBOARD_CHOICE_FOCUS_RESULT ", [], 15))
    summary = {"scope": "pinned Godot native headless input logic; no OS mouse/focus, screenshots, physical-controller, graphics, listening or LAN acceptance",
               "artifact": artifact, "cases": [], "failures": [], "source_before": before, "status": "INCOMPLETE"}
    try:
        for name, script, marker, args, timeout in cases:
            result = dev.execute_command(prefix + ["--script", dev.ROOT / script, "--"] + args, label + "-" + name, timeout)
            log = dev.EVIDENCE / (label + "-" + name + ".log")
            observations = [json.loads(line[len(marker):]) for line in log.read_text(encoding="utf-8").splitlines() if line.startswith(marker)]
            if len(observations) != 1:
                raise RuntimeError("one native observation result required: " + name)
            report = observations[0]
            failures = gui_failures(report) if name == "gui" else report["failures"]
            if artifact and report.get("version") != artifact["build"]["version"]:
                failures = failures + ["loaded resource version differs from BUILD"]
            atomic_json(dev.EVIDENCE / (label + "-" + name + ".json"), report)
            summary["cases"].append({"name": name, "report": str(log.with_suffix(".json")), "process": result, "failures": failures})
            summary["failures"].extend(failures)
            if failures:
                break
        summary["status"] = "FAIL" if summary["failures"] else "PASS"
    except BaseException as error:
        summary["failures"].append(type(error).__name__ + ": native check did not complete")
        raise
    finally:
        summary["source_after"] = {path: dev.file_sha256(dev.ROOT / path) for path in inputs}
        if summary["source_after"] != before:
            summary["failures"].append("source changed during native checks")
            summary["status"] = "FAIL"
        atomic_json(dev.EVIDENCE / (label + ".json"), summary)
    print(json.dumps({"report": str(dev.EVIDENCE / (label + ".json")), "cases": [row["name"] for row in summary["cases"]], "failures": summary["failures"]}, ensure_ascii=False))
    return 1 if summary["failures"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
