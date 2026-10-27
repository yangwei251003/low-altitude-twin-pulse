"""Opt-in import + two real MAIN views of the automatic production installation."""
from __future__ import annotations
import argparse
import datetime
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import time
import uuid

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
MODEL = ROOT / "assets/v3/i2_east_maintenance_extension/east_maintenance_extension.glb"
MODEL_SHA = "946a7ee1c91741302627f6c63489b37a5bb5861ebc79d093959814b4876978b0"
SCRIPT = "res://tests_v3/candidates/east_maintenance_extension/capture_production.gd"
BUDGET = 60


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true", help="Requires the parent's exclusive engine window")
    parser.add_argument("--identity-only", action="store_true", help="Existing imports; actual World identity only, headless, no new images")
    options = parser.parse_args()
    budget = 15 if options.identity_only else BUDGET
    if not (ROOT / "project.godot").is_file() or sha(MODEL) != MODEL_SHA:
        raise SystemExit("Wrong project root or production GLB differs from the approved delivery")
    owned = [HERE / "capture_production.gd", Path(__file__).resolve(), HERE / "capture_assembly.gd", HERE / "diagnose_production_identity.gd", MODEL,
             ROOT / "scripts/v3/art/twin_i2_east_maintenance_art.gd", ROOT / "scripts/v3/twin_test_world.gd",
             ROOT / "scripts_tools/v3/capture_clinic_integrated.gd", ROOT / "scripts_tools/v3/dev.py"]
    before = {path.relative_to(ROOT).as_posix(): sha(path) for path in owned}
    if not options.run:
        print(json.dumps({"prepared_only": True, "engine_started": False, "whole_engine_budget_seconds": budget,
                          "scope": "headless actual World identity only; no import, images, Session or Store" if options.identity_only else "import + two actual production MAIN views; no manual installation or physics mutation",
                          "inputs": before}, ensure_ascii=False, indent=2))
        return 0
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S") + "_" + uuid.uuid4().hex[:6]
    evidence = HERE / "evidence"
    logs = evidence / (("production-identity-run-" if options.identity_only else "production-run-") + stamp)
    capture = evidence / (("production-identity-" if options.identity_only else "production-") + stamp)
    logs.mkdir(parents=True, exist_ok=False)
    profile = "qa_visual_clinic_east_maintenance_production_" + stamp
    spec = importlib.util.spec_from_file_location("east_maintenance_production_dev", ROOT / "scripts_tools/v3/dev.py")
    dev = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(dev)
    dev.EVIDENCE = logs
    started = time.monotonic()
    results = []
    passed = False
    failure = ""
    try:
        if not options.identity_only:
            results.append(dev.execute_command([str(dev.GODOT), "--path", str(ROOT), "--headless", "--editor", "--import", "--quit"], "import", 25))
        remaining = budget - (time.monotonic() - started)
        if remaining <= 10:
            raise RuntimeError("Import exhausted the bounded whole-run budget")
        command = ([str(dev.GODOT), "--path", str(ROOT), "--headless", "--script",
                    "res://tests_v3/candidates/east_maintenance_extension/diagnose_production_identity.gd",
                    "--", "--identity-output=" + capture.as_posix()] if options.identity_only else
                   [str(dev.GODOT), "--path", str(ROOT), "--rendering-method", "gl_compatibility",
                    "--windowed", "--resolution", "1280x720", "--position", "-4000,-4000", "--script", SCRIPT,
                    "--", "--qa-profile=" + profile, "--capture-output=" + capture.as_posix()])
        results.append(dev.execute_command(command, "identity" if options.identity_only else "capture", remaining))
        report = json.loads((capture / ("identity.json" if options.identity_only else "state_checks.json")).read_text(encoding="utf-8"))
        checks = report.get("checks", [])
        if not report.get("passed") or not checks or not all(row.get("passed") is True for row in checks):
            raise RuntimeError("Production probe did not report every check passed")
        if len(report.get("shots", [])) != (0 if options.identity_only else 2) or report.get("engine_log", {}).get("error_count") != 0:
            raise RuntimeError("Production probe requires two images and zero engine errors")
        if not options.identity_only and (not report.get("input_sha256_before") or report["input_sha256_before"] != report.get("input_sha256_after")):
            raise RuntimeError("Production probe inputs changed")
        measured_path = report.get("details", {}).get("scene_file_path") if options.identity_only else report.get("measurements", {}).get("imported", {}).get("path")
        if measured_path != "res://" + MODEL.relative_to(ROOT).as_posix():
            raise RuntimeError("Measured model did not come from the production asset path")
        for shot in report.get("shots", []):
            picture = Path(shot["file"])
            if picture.parent.resolve() != capture.resolve() or sha(picture) != shot["png_sha256"]:
                raise RuntimeError("Captured PNG does not match its recorded path/hash")
        passed = True
    except (SystemExit, RuntimeError, OSError, ValueError, KeyError) as error:
        failure = f"{type(error).__name__}: {error}"
    finally:
        after = {path.relative_to(ROOT).as_posix(): sha(path) for path in owned}
        passed = passed and before == after
        summary = {"passed": passed, "profile": profile, "capture": str(capture), "results": results,
                   "elapsed_seconds": round(time.monotonic() - started, 3), "whole_engine_budget_seconds": budget,
                   "input_sha256_before": before, "input_sha256_after": after,
                   "inputs_unchanged": before == after, "failure": failure,
                   "scope": "Headless production World identity only; no new images, Store or Session" if options.identity_only else "Production World automatic installation; no manual candidate install, gameplay or final region-art acceptance"}
        (logs / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
