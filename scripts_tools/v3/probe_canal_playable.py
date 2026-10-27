"""Bounded real-GPU/input probe for the isolated canal interaction candidate.

Run from the repository: python scripts_tools/v3/probe_canal_playable.py
This is scripted QA, not a human playthrough or a production save migration.
"""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import shutil
import sys
import uuid

import dev


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workbench", action="store_true", help="Run the actual local-cooling work and beneficiary flight probe")
    options = parser.parse_args()
    label = ("canal-playable-work-" if options.workbench else "canal-playable-input-") + datetime.datetime.now().strftime("%Y%m%d_%H%M%S") + "_" + uuid.uuid4().hex[:6]
    evidence = dev.EVIDENCE / "art" / label
    evidence.mkdir(parents=True, exist_ok=False)
    paths = ["project.godot", "scripts/v3/twin_test_world.gd",
             "scripts/v2/flight_body.gd", "scripts/v2/flight_camera.gd",
             "scripts/v2/pilot_input.gd", "scripts/v3/gameplay/twin_ability_rules.gd",
             "scripts_tools/v3/probe_canal_playable.py", "scripts_tools/v3/dev.py"]
    for group in ["canal_playable", "canal_transport_executor", "canal_transport_physics",
                  "canal_cooling_station", "canal_service_loop", "canal_workbench"]:
        paths.extend(str(p.relative_to(dev.ROOT)).replace("\\", "/")
                     for p in sorted((dev.ROOT / "scripts/v3/candidates" / group).rglob("*"))
                     if p.suffix in (".gd", ".tscn"))
    paths.extend(str(p.relative_to(dev.ROOT)).replace("\\", "/")
                 for p in sorted((dev.ROOT / "data/v3/terrain").glob("i2_*.json")))
    before = []
    for name in paths:
        path = dev.ROOT / name
        content = path.read_bytes()
        dest = evidence / "source" / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(content)
        before.append({"path": name, "bytes": len(content), "sha256": hashlib.sha256(content).hexdigest()})
    (evidence / "before.json").write_text(json.dumps(before, indent=2) + "\n", encoding="utf-8")
    code = 0
    try:
        script = "probe_workbench_playable.gd" if options.workbench else "probe_playable.gd"
        result = dev.execute(["--rendering-method", "gl_compatibility", "--windowed",
                              "--resolution", "1280x720", "--position", "-4000,-4000",
                              "--script", "res://scripts/v3/candidates/canal_playable/" + script,
                              "--", "--capture-output=" + str(evidence)], label, 190 if options.workbench else 140)
        print(json.dumps(result))
    except SystemExit as error:
        code = error.code if isinstance(error.code, int) else 1
    finally:
        after = [{"path": row["path"], "sha256": hashlib.sha256((dev.ROOT / row["path"]).read_bytes()).hexdigest()}
                 for row in before]
        unchanged = all(a["sha256"] == b["sha256"] for a, b in zip(before, after))
        (evidence / "after.json").write_text(json.dumps({"all_unchanged": unchanged, "files": after}, indent=2) + "\n", encoding="utf-8")
        log = dev.EVIDENCE / (label + ".log")
        if log.is_file():
            shutil.copyfile(log, evidence / "original-run.log")
        if not unchanged:
            code = 1
        print(str(evidence))
    return code


if __name__ == "__main__":
    sys.exit(main())
