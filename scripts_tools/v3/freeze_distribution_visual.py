"""Freeze the dev18 distribution capture, verifying every input byte first."""
from pathlib import Path
import hashlib
import json
import shutil
import sys

ROOT = Path(__file__).resolve().parents[2]
CAPTURE = ROOT / "artifacts/v3/art/clinic-integrated-distribution-20261019_033109_cd887c"
DEST = ROOT / "docs/v3/evidence/dev18-distribution-visual"
PRIOR = ROOT / "docs/v3/evidence/dev18-service-court/manifest.json"
LOG = ROOT / "artifacts/v3/distribution-capture-20261019_033109_cd887c.log"
EXPECTED_SHOTS = 4
EXPECTED_PASS = True
# Exact pre-change source bytes retained after a failed capture. Never rewrite live files.
SOURCE_OVERRIDES = {}
BASELINE = "b4ab57f"
SCOPE = "Four actual production GPU views, graybox investigation integration; not final art, LAN or performance acceptance"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    finishing = "--finish-existing" in sys.argv and DEST.is_dir() and not (DEST / "manifest.json").exists()
    if DEST.exists() and not finishing:
        raise SystemExit("Refuse existing frozen evidence")
    report = json.loads((CAPTURE / "state_checks.json").read_text(encoding="utf-8"))
    assert report["passed"] == EXPECTED_PASS and len(report["shots"]) == EXPECTED_SHOTS
    run = json.loads(LOG.read_text(encoding="utf-8").split("DEV_RUN_RESULT ")[-1])
    assert run["passed"] == EXPECTED_PASS and not run["timed_out"] and not run["orphan_cleanup"]
    assert run["remaining_owned_processes"] == 0
    inputs = report["input_sha256_before"]
    assert inputs == report["input_sha256_after"]
    for resource, expected in inputs.items():
        assert resource.startswith("res://")
        assert digest(SOURCE_OVERRIDES.get(resource, ROOT / resource[6:])) == expected, resource
    # Reuse verified immutable bytes across the evidence history, including
    # records from source-closure fixtures. Do not recopy hundreds of megabytes
    # simply because the immediately preceding report used a different closure.
    old = {}
    needed = set(inputs.values())
    manifests = [PRIOR] + sorted((ROOT / "docs/v3/evidence").glob("*/manifest.json"))
    for manifest_path in manifests:
        if not manifest_path.is_file() or manifest_path.parent == DEST:
            continue
        prior = json.loads(manifest_path.read_text(encoding="utf-8"))
        for item in prior.get("input_resources", []):
            if not item.get("frozen_path") or item["sha256"] not in needed or item["sha256"] in old:
                continue
            frozen_path = ROOT / item["frozen_path"]
            if frozen_path.is_file() and digest(frozen_path) == item["sha256"]:
                old.setdefault(item["sha256"], item["frozen_path"])
        for item in prior.get("files", []):
            if item["sha256"] not in needed or item["sha256"] in old:
                continue
            frozen_path = manifest_path.parent / item["path"]
            if frozen_path.is_file() and digest(frozen_path) == item["sha256"]:
                old.setdefault(item["sha256"], frozen_path.relative_to(ROOT).as_posix())
    DEST.mkdir(parents=True, exist_ok=finishing)
    records = []
    reused = 0
    for resource, expected in sorted(inputs.items()):
        source = SOURCE_OVERRIDES.get(resource, ROOT / resource[6:])
        frozen = ROOT / old[expected] if expected in old else DEST / "captured-inputs" / resource[6:]
        if expected in old:
            assert digest(frozen) == expected, str(frozen)
            reused += 1
        else:
            frozen.parent.mkdir(parents=True, exist_ok=True)
            if frozen.exists():
                assert finishing and digest(frozen) == expected
            else:
                shutil.copy2(source, frozen)
        records.append({"resource": resource, "sha256": expected,
                        "frozen_path": frozen.relative_to(ROOT).as_posix(), "bytes": frozen.stat().st_size})
    if finishing:
        for source in CAPTURE.rglob("*"):
            if source.is_file(): assert digest(source) == digest(DEST / "capture" / source.relative_to(CAPTURE))
        assert digest(LOG) == digest(DEST / "logs" / LOG.name)
    else:
        shutil.copytree(CAPTURE, DEST / "capture")
        (DEST / "logs").mkdir()
        shutil.copy2(LOG, DEST / "logs")
    files = [{"path": p.relative_to(DEST).as_posix(), "bytes": p.stat().st_size, "sha256": digest(p)}
             for p in sorted(DEST.rglob("*")) if p.is_file()]
    manifest = {"scope": SCOPE,
                "baseline": BASELINE, "input_resources": records, "reused_inputs": reused, "files": files}
    (DEST / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"files": len(files), "inputs": len(records), "reused": reused,
                      "bytes": sum(f["bytes"] for f in files), "manifest_sha256": digest(DEST / "manifest.json")}))


if __name__ == "__main__":
    main()
