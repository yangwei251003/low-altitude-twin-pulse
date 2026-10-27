"""Preserve the first isolated trial-flow rule/physics evidence and exact inputs."""
from pathlib import Path
import hashlib
import json
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / "docs/v3/evidence/dev18-trial-flow-candidate"
LOGS = [
    "trial-runtime-20261019_041420_43fdee.log",
    "trial-station-import-20261019_041648_9c555f.log",
    "trial-station-20261019_041648_9c555f.log",
]
ENTRIES = ["tests_v3/test_trial_flow_runtime.gd", "tests_v3/test_trial_flow_station.gd"]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    if DEST.exists():
        raise SystemExit("Refuse to overwrite frozen evidence")
    inputs = set(ENTRIES + ["project.godot"])
    queue = list(ENTRIES)
    while queue:
        relative = queue.pop()
        text = (ROOT / relative).read_text(encoding="utf-8-sig")
        for found in re.findall(r'res://([^"\s]+\.(?:gd|json|tscn))', text):
            if found not in inputs and (ROOT / found).is_file():
                inputs.add(found)
                if found.endswith((".gd", ".tscn")):
                    queue.append(found)
    results = []
    for name in LOGS:
        source = ROOT / "artifacts/v3" / name
        log = source.read_text(encoding="utf-8")
        result = json.loads(log.split("DEV_RUN_RESULT ")[-1])
        assert result["passed"] and result["returncode"] == 0
        assert not result["timed_out"] and not result["orphan_cleanup"]
        assert result["remaining_owned_processes"] == 0
        results.append({"log": name, **result})
    DEST.mkdir(parents=True)
    for relative in sorted(inputs):
        target = DEST / "source" / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / relative, target)
    (DEST / "logs").mkdir()
    for name in LOGS:
        shutil.copy2(ROOT / "artifacts/v3" / name, DEST / "logs" / name)
    files = [{"path": p.relative_to(DEST).as_posix(), "bytes": p.stat().st_size, "sha256": sha(p)}
             for p in sorted(DEST.rglob("*")) if p.is_file()]
    report = {
        "scope": "Independent disconnected bench; 82 pure-rule and 101 real-physics fixture checks. Not integrated Session gameplay, ENet, art or human acceptance.",
        "baseline": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "input_note": "Exact source/resource closure copied immediately after the runs; agents froze owned files before testing. These tests do not produce their own before/after input digest.",
        "engine": "Godot 4.7.2.stable.official.ed1daf0bf",
        "results": results,
        "files": files,
    }
    (DEST / "manifest.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"files": len(files), "inputs": len(inputs), "bytes": sum(r["bytes"] for r in files), "manifest_sha256": sha(DEST / "manifest.json")}))


if __name__ == "__main__":
    main()
