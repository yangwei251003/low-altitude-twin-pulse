"""Preserve the failed typed-array fixture and corrected real-physics result."""
from pathlib import Path
import hashlib
import json
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / "docs/v3/evidence/dev18-trial-floor"
FAILED = ROOT / "artifacts/v3/trial-floor-first-run"
LOGS = ["distribution-trial-floor-20261019_042558_c6caf2.log",
        "distribution-trial-floor-fixed-20261019_042904_4212f1.log"]
ENTRIES = {"tests_v3/test_distribution_trial_floor.gd", "data/v3/terrain/i2_distribution_trial_layout.json", "project.godot"}
SCOPE = "Candidate floor only. First fixture had two untyped RID arrays; corrected test passes 109 real-physics checks. Production floor and save format are unchanged."


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    if DEST.exists():
        raise SystemExit("Refuse existing frozen evidence")
    entries = set(ENTRIES)
    queue = list(entries)
    while queue:
        relative = queue.pop()
        if not relative.endswith((".gd", ".tscn")):
            continue
        for found in re.findall(r'res://([^"\s]+\.(?:gd|json|tscn))', (ROOT / relative).read_text(encoding="utf-8-sig")):
            if found not in entries and (ROOT / found).is_file():
                entries.add(found)
                queue.append(found)
    results = []
    for name in LOGS:
        raw = (ROOT / "artifacts/v3" / name).read_text(encoding="utf-8")
        result = json.loads(raw.split("DEV_RUN_RESULT ")[-1])
        assert not result["timed_out"] and not result["orphan_cleanup"] and result["remaining_owned_processes"] == 0
        results.append({"log": name, **result})
    assert not results[0]["passed"] and results[1]["passed"] and results[1]["returncode"] == 0
    DEST.mkdir(parents=True)
    shutil.copytree(FAILED, DEST / "failed-fixture")
    for relative in entries:
        target = DEST / "source" / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / relative, target)
    (DEST / "logs").mkdir()
    for name in LOGS:
        shutil.copy2(ROOT / "artifacts/v3" / name, DEST / "logs" / name)
    files = [{"path": p.relative_to(DEST).as_posix(), "bytes": p.stat().st_size, "sha256": sha(p)}
             for p in sorted(DEST.rglob("*")) if p.is_file()]
    report = {"scope": SCOPE,
              "baseline": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
              "input_note": "Source closure copied after frozen tests; these runs did not produce self-fingerprints. First failed test and identical candidate layout retained separately.",
              "results": results, "files": files}
    (DEST / "manifest.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"files": len(files), "manifest_sha256": sha(DEST / "manifest.json")}))


if __name__ == "__main__":
    main()
