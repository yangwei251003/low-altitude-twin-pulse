"""Explicit opt-in, bounded import + real MAIN candidate capture. No UDP."""
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
MODEL = ROOT / "assets/v3/candidates/i2_east_maintenance_extension/east_maintenance_extension.glb"
MODEL_SHA = "946a7ee1c91741302627f6c63489b37a5bb5861ebc79d093959814b4876978b0"
SCRIPT = "res://tests_v3/candidates/east_maintenance_extension/capture_assembly.gd"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true", help="Requires the parent's exclusive engine window")
    parser.add_argument("--diagnose-only", action="store_true", help="Existing import, one headless MAIN attribute diagnostic, no images")
    options = parser.parse_args()
    if not (ROOT / "project.godot").is_file() or sha(MODEL) != MODEL_SHA:
        raise SystemExit("Wrong project root or candidate GLB differs from the frozen delivery")
    owned = [HERE / "capture_assembly.gd", Path(__file__).resolve(), MODEL,
             ROOT / "scripts/v3/candidates/east_maintenance_art/east_maintenance_art.gd",
             ROOT / "scripts_tools/v3/dev.py"]
    before = {str(path.relative_to(ROOT)).replace("\\", "/"): sha(path) for path in owned}
    if not options.run:
        print(json.dumps({"prepared_only": True, "engine_started": False, "hard_seconds": 40 if options.diagnose_only else 120,
                          "scope": "headless MAIN attributes only; no new images or import" if options.diagnose_only else "import then three actual MAIN views; no physics or gameplay modification",
                          "inputs": before}, ensure_ascii=False, indent=2))
        return 0
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S") + "_" + uuid.uuid4().hex[:6]
    evidence = HERE / "evidence"
    logs = evidence / ("run-" + stamp)
    capture = evidence / (("diagnose-" if options.diagnose_only else "capture-") + stamp)
    logs.mkdir(parents=True, exist_ok=False)
    profile = "qa_visual_clinic_east_maintenance_" + stamp
    spec = importlib.util.spec_from_file_location("east_maintenance_dev", ROOT / "scripts_tools/v3/dev.py")
    dev = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(dev)
    dev.EVIDENCE = logs
    started = time.monotonic()
    results = []
    passed = False
    failure = ""
    budget = 40 if options.diagnose_only else 120
    try:
        if not options.diagnose_only:
            results.append(dev.execute_command([str(dev.GODOT), "--path", str(ROOT), "--headless", "--editor", "--import", "--quit"], "import", 35))
        remaining = budget - (time.monotonic() - started)
        if remaining <= 10:
            raise RuntimeError("Import exhausted the bounded whole-run budget")
        display = ["--headless"] if options.diagnose_only else ["--rendering-method", "gl_compatibility", "--windowed", "--resolution", "1280x720", "--position", "-4000,-4000"]
        results.append(dev.execute_command([str(dev.GODOT), "--path", str(ROOT), *display, "--script", SCRIPT, "--",
                        "--qa-profile=" + profile, "--capture-output=" + capture.as_posix(),
                        *(["--diagnose-only"] if options.diagnose_only else [])], "diagnose" if options.diagnose_only else "capture", remaining))
        report = json.loads((capture / "state_checks.json").read_text(encoding="utf-8"))
        expected_shots = 0 if options.diagnose_only else 3
        if not report.get("passed") or len(report.get("shots", [])) != expected_shots:
            raise RuntimeError("Capture did not report all requested views and checks passed")
        for shot in report["shots"]:
            picture = Path(shot["file"])
            if picture.parent.resolve() != capture.resolve() or sha(picture) != shot["png_sha256"]:
                raise RuntimeError("Captured PNG does not match its recorded path/hash")
        passed = True
    except (SystemExit, RuntimeError, OSError, ValueError, KeyError) as error:
        failure = f"{type(error).__name__}: {error}"
    finally:
        after = {str(path.relative_to(ROOT)).replace("\\", "/"): sha(path) for path in owned}
        passed = passed and before == after
        summary = {"passed": passed, "profile": profile, "capture": str(capture), "results": results,
                   "elapsed_seconds": round(time.monotonic() - started, 3), "whole_engine_budget_seconds": budget,
                   "input_sha256_before": before, "input_sha256_after": after,
                   "inputs_unchanged": before == after, "failure": failure,
                   "scope": "Actual MAIN diagnostic candidate, no human/playthrough/performance acceptance"}
        (logs / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
