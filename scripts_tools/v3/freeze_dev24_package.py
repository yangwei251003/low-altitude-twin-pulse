"""Freeze explicitly named dev24 package checks, preserving their original bytes."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / "docs/v3/evidence/dev24-package"
EXE = ROOT / "build/V3Dev24Candidate/LowAltitudeTwinPulse-Dev.exe"
EXPECTED = "c47bce67c662eac6d4ee4e51f0c228c5f005b56b1322bfb91f178ffbebd6d35a"
SOURCES = {
    "visual": "artifacts/v3/art/package-20261019_181130_f07bc2",
    "network": "artifacts/v3/network/20261019_181533_302408",
    "distribution": "build/V3Dev24Candidate/artifacts/v3/network/distribution/20261019_181503_259616",
    "entry": "build/V3Dev24Candidate/artifacts/v3/app-entry/20261019_182324_445217",
}
LOGS = [
    "export-20261019_180728_40cd76.log",
    "import-20261019_180515_8c91a4.log",
    "dev24-package-capture-20261019_181130.log",
    "dev24-package-facilities-20261019_181503.log",
    "dev24-package-normal-20261019_181503.log",
    "dev24-package-entry-20261019_182324.log",
]
QA = [
    "scripts/v3/qa/twin_packaged_capture.gd", "scripts_tools/v3/capture_package.py",
    "scripts_tools/v3/test_distribution_lan.py", "scripts_tools/v3/test_lan_local.py",
    "scripts_tools/v3/test_app_entry.py", "scripts_tools/v3/dev.py",
    "scripts/v3/tests/distribution_lan_probe.gd",
]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    if sha(EXE) != EXPECTED or EXE.stat().st_size != 500720424:
        raise RuntimeError("The tested executable changed")
    if DEST.exists():
        raise RuntimeError("Immutable destination already exists")
    for name, source in SOURCES.items():
        report = ROOT / source / ("validation.json" if name == "visual" else "summary.json")
        if json.loads(report.read_text(encoding="utf-8"))["passed"] is not True:
            raise RuntimeError(f"Failed proof: {name}")
    for path in [*(ROOT / "artifacts/v3" / name for name in LOGS),
                 *(ROOT / name for name in QA), EXE.parent / "BUILD.json"]:
        if not path.is_file():
            raise RuntimeError(f"Missing source: {path}")
    DEST.mkdir(parents=True)
    files = []

    def copy(source, relative):
        target = DEST / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        if sha(source) != sha(target):
            raise RuntimeError(f"Copy changed: {source}")
        files.append({"source": source.relative_to(ROOT).as_posix(),
                      "path": target.relative_to(DEST).as_posix(),
                      "bytes": target.stat().st_size, "sha256": sha(target)})

    for name, source in SOURCES.items():
        base = ROOT / source
        for path in sorted(base.rglob("*")):
            if path.is_file():
                copy(path, Path(name) / path.relative_to(base))
    for name in LOGS:
        copy(ROOT / "artifacts/v3" / name, Path("logs") / name)
    for name in QA:
        copy(ROOT / name, Path("qa-source") / name)
    copy(EXE.parent / "BUILD.json", Path("BUILD-at-export.json"))
    manifest = {
        "version": "3.0.0-dev.24", "protocol": 20,
        "exe_sha256": EXPECTED, "exe_bytes": EXE.stat().st_size,
        "source_baseline": subprocess.check_output(["git","rev-parse","HEAD"],cwd=ROOT,text=True).strip(), "production_art_baseline": "c1e87fe",
        "source_note": "Same dev24 production and package probe bytes as export. Independently evolving rule/flight candidates are excluded via scripts/v3/candidates/*. Exact QA files are archived below; module fixes do not change this EXE.",
        "scope": "Partial development checkpoint: actual exported GPU capture and same-computer ENet; no full-game, two-PC, performance or human-playtest acceptance.",
        "visual_review": {
            "generated_images": 24,
            "root_viewed": ['I1-packaged.png', 'F1-packaged.png', 'I1-whale-packaged.png', 'F1-crown-packaged.png', 'I2-arrival-packaged.png', 'I2-high-valve-packaged.png', 'I2-full-water-packaged.png', 'I2-reception-interior-packaged.png', 'I2-reception-skylight-packaged.png', 'I2-gravity-undercroft-packaged.png', 'I2-paving-packaged.png', 'I2-distribution-packaged.png', 'I2-trial-connected-packaged.png', 'I2-shared-access-packaged.png', 'I2-waterfront-channel-packaged.png'],
            "whole_region_final_art": "rejected; flat remainder, repeated placeholder elements remain",
        },
        "files": files,
    }
    (DEST / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for row in files:
        if sha(DEST / row["path"]) != row["sha256"]:
            raise RuntimeError("Final readback failed")
    print(json.dumps({"files": len(files), "bytes": sum(r["bytes"] for r in files),
                      "manifest_sha256": sha(DEST / "manifest.json")}, ensure_ascii=False))


if __name__ == "__main__":
    main()
