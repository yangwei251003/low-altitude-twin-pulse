"""Preserve the bounded real-flight candidate test without rerunning or rewriting it."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / "docs/v3/evidence/i2-loaded-route"
LOG = ROOT / "artifacts/v3/i2-loaded-route-first-20261019_193602_668f23.log"
TEST = "tests_v3/candidates/canal_transport_physics/test_i2_loaded_route.gd"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    if DEST.exists():
        raise RuntimeError("Immutable evidence already exists")
    lines = LOG.read_text(encoding="utf-8").splitlines()
    matches = [line.split(" ", 1)[1] for line in lines
               if line.startswith("V3_I2_LOADED_ROUTE_RESULT ")]
    if len(matches) != 1:
        raise RuntimeError("Expected one actual test result")
    result = json.loads(matches[0])
    if result["checks"] != 44 or result["failures"] or result["engine_errors"]:
        raise RuntimeError("Test was not successful")
    inputs = []
    for uri, expected in result["input_sha256"].items():
        path = ROOT / uri.removeprefix("res://")
        if sha(path) != expected:
            raise RuntimeError(f"Recorded input changed: {uri}")
        inputs.append({"path": path.relative_to(ROOT).as_posix(),
                       "sha256": expected, "bytes": path.stat().st_size})
    DEST.mkdir(parents=True)
    files = []
    sources = [LOG, ROOT / TEST,
               ROOT / "docs/v3/planning/I2_LOADED_ROUTE_PROBE.md",
               ROOT / "scripts_tools/v3/dev.py"]
    sources.extend(ROOT / row["path"] for row in inputs
                   if not row["path"].endswith(".glb"))
    for source in sources:
        relative = source.relative_to(ROOT)
        target = DEST / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        if sha(source) != sha(target):
            raise RuntimeError(f"Copy mismatch: {relative}")
        files.append({"path": relative.as_posix(), "sha256": sha(target),
                      "bytes": target.stat().st_size})
    manifest = {
        "source_baseline": subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "checks": 44, "failures": 0, "inputs": inputs, "files": files,
        "scope": "Actual production I2 in an isolated physics world, real TR01/HX02 and 2 kg jointed cargo. Default facility poses, low return and high return paths. No Session, real loading/unloading, service loop, package, graphics, performance or human acceptance.",
        "binary_inputs": "Recorded GLBs remain tracked at their production paths; hashes checked before freeze. No duplicate model binary is stored here.",
    }
    path = DEST / "manifest.json"
    path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for row in files:
        if sha(DEST / row["path"]) != row["sha256"]:
            raise RuntimeError("Final evidence readback failed")
    print(json.dumps({"files": len(files), "inputs": len(inputs),
                      "manifest_sha256": sha(path)}))


if __name__ == "__main__":
    main()
