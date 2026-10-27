"""Freeze the reviewed MAIN images and changed source; no renderer is launched."""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/v3/evidence/dev25-revetment"
CAPTURE = ROOT / "artifacts/v3/art/clinic-integrated-revetment-typed-20261019"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    if OUT.exists():
        raise RuntimeError("Immutable evidence already exists")
    report = json.loads((CAPTURE / "state_checks.json").read_text(encoding="utf-8"))
    assert report["passed"] and len(report["checks"]) == 83 and len(report["shots"]) == 5
    assert report["engine_log"]["error_count"] == 0
    assert report["input_sha256_before"] == report["input_sha256_after"]
    sources = [
        "scripts/v3/art/twin_i2_revetment_art.gd",
        "scripts/v3/art/twin_i2_revetment_partition.gd",
        "scripts/v3/twin_test_world.gd",
        "scripts/v3/qa/twin_packaged_capture.gd",
        "scripts_tools/v3/capture_revetment_integrated.gd",
        "scripts_tools/v3/capture_clinic_integrated.gd",
        "scripts_tools/v3/capture_package.py",
        "tests_v3/candidates/canal_revetment/test_revetment_partition.gd",
        "docs/v3/DEV25_REVETMENT.md",
        "scripts_tools/v3/dev.py",
    ]
    sources.extend("artifacts/v3/" + name + ".log" for name in [
        "revetment-wrapper-parse-20261019", "revetment-actual-import-20261019",
        "revetment-main-first-20261019", "revetment-main-typed-20261019",
        "revetment-promoted-partition-20261019", "revetment-shared-session-20261019"])
    paths = [ROOT / p for p in sources] + [p for p in CAPTURE.iterdir() if p.is_file()]
    files = []
    for source in paths:
        relative = source.relative_to(ROOT)
        target = OUT / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        assert sha(source) == sha(target)
        files.append({"path": relative.as_posix(), "bytes": target.stat().st_size, "sha256": sha(target)})
    models = []
    for path in (ROOT / "assets/v3/i2_canal_revetment").glob("*.glb"):
        models.append({"path": path.relative_to(ROOT).as_posix(), "bytes": path.stat().st_size, "sha256": sha(path)})
    manifest = {
        "source_baseline": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "files": files, "tracked_model_references": models,
        "capture_input_hashes": report["input_sha256_before"],
        "scope": "Five actual MAIN frozen QA poses, 83 checks, reviewed by root. Visible west bank only. No performance, human, LAN or packaged-game claim.",
        "source_policy": "Changed production/capture sources copied here. Other source inputs are recorded by SHA in the actual report; imported caches are rebuildable, not a promised permanent copy.",
    }
    (OUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    for row in files:
        assert sha(OUT / row["path"]) == row["sha256"]
    print(json.dumps({"files": len(files), "manifest_sha256": sha(OUT / "manifest.json")}))


if __name__ == "__main__":
    main()
