"""Freeze explicitly named dev20 package checks, preserving their original bytes."""
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / "docs/v3/evidence/dev20-package"
EXE = ROOT / "build/V3Dev20Candidate/LowAltitudeTwinPulse-Dev.exe"
EXPECTED = "dd83d7fb69aea46f7404e3943f4b6e382289de012eaf33ccaedee873eda1c9bb"
SOURCES = {
    "visual": "artifacts/v3/art/package-20261019_071256_f5060a",
    "network": "artifacts/v3/network/20261019_071637_896162",
    "distribution": "build/V3Dev20Candidate/artifacts/v3/network/distribution/20261019_071430_945712",
    "entry": "build/V3Dev20Candidate/artifacts/v3/app-entry/20261019_071707_921248",
}
LOGS = [
    "export-20261019_071156_62743d.log",
    "dev20-package-import-20261019_071015_024a0c.log",
    "dev20-package-capture-20261019_071256_f503f2.log",
    "dev20-package-distribution-20261019_071256_f503f2.log",
    "dev20-package-normal-lan-20261019_071637_421962.log",
    "dev20-package-entry-20261019_071637_421962.log",
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
    if sha(EXE) != EXPECTED or EXE.stat().st_size != 488953720:
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
        "version": "3.0.0-dev.20", "protocol": 19,
        "exe_sha256": EXPECTED, "exe_bytes": EXE.stat().st_size,
        "source_baseline": "2656793", "production_baseline": "8893b66",
        "source_note": "No production delta after 2656793; engine-generated UID files were untracked at export and are recorded with this checkpoint. Art candidates outside production remain excluded.",
        "scope": "Partial development checkpoint: actual exported GPU capture and same-computer ENet; no full-game, two-PC, performance or human-playtest acceptance.",
        "visual_review": {
            "generated_images": 23,
            "root_viewed": ["I2-distribution-packaged.png", "I2-trial-connected-packaged.png",
                            "I2-shared-access-packaged.png", "I1-packaged.png", "F1-packaged.png",
                            "I2-arrival-packaged.png", "I2-paving-packaged.png"],
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
