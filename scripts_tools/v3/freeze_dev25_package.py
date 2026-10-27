"""Archive the actual dev25 executable capture; no engine is launched."""
from pathlib import Path
import hashlib
import json
import shutil

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/v3/evidence/dev25-package"
CAPTURE = ROOT / "artifacts/v3/art/package-20261019_212458_aa8e0c"
EXE = ROOT / "build/V3Dev25Candidate/LowAltitudeTwinPulse-Dev.exe"
EXPECTED = "59bb91aeb2aeaa7e629b4feb8eefd72c47e458cb23634a42cfa8a52348bb9122"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    assert not OUT.exists(), "Immutable evidence already exists"
    assert sha(EXE) == EXPECTED and EXE.stat().st_size == 510263704
    validation = json.loads((CAPTURE / "validation.json").read_text(encoding="utf-8"))
    assert validation["passed"] and len(validation["checks"]) == 58 and validation["saved_png_count"] == 24
    assert validation["executable_sha256"] == EXPECTED
    pairs = [(p, Path("visual") / p.relative_to(CAPTURE)) for p in sorted(CAPTURE.rglob("*")) if p.is_file()]
    for name in ["export-20261019_212414_a1e9cf.log", "dev25-package-capture-20261019.log"]:
        pairs.append((ROOT / "artifacts/v3" / name, Path("logs") / name))
    for name in ["scripts/v3/qa/twin_packaged_capture.gd", "scripts_tools/v3/capture_package.py",
                 "scripts_tools/v3/dev.py", "scripts/v3/art/twin_i2_revetment_art.gd",
                 "scripts/v3/art/twin_i2_revetment_partition.gd", "project.godot", "export_presets.cfg"]:
        pairs.append((ROOT / name, Path("source") / name))
    pairs.append((EXE.parent / "BUILD.json", Path("BUILD-at-export.json")))
    assert all(p.is_file() for p, _ in pairs)
    rows = []
    for source, relative in pairs:
        target = OUT / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        assert sha(source) == sha(target)
        rows.append({"source": source.relative_to(ROOT).as_posix(), "path": relative.as_posix(),
                     "bytes": target.stat().st_size, "sha256": sha(target)})
    manifest = {"version": "3.0.0-dev.25", "protocol": 20,
        "exe_sha256": EXPECTED, "exe_bytes": EXE.stat().st_size,
        "production_baseline": "d9c5944", "checks": 58, "generated_images": 24,
        "root_viewed": ["I2-waterfront-channel-packaged.png", "I2-shared-access-packaged.png",
                        "I2-paving-packaged.png", "I2-arrival-packaged.png", "I1-packaged.png", "F1-packaged.png"],
        "scope": "Actual exported Compatibility 720p GPU views with frozen QA poses, not human play or frame-time acceptance. No LAN tests repeated for this visual-only source change; dev24 network proof retains its original version and hash.",
        "art_verdict": "Reviewed west-bank import retained; all whole-region final art still rejected. I2 open gray ground, unconnected material boundaries, unfinished other banks/props; F1 placeholders and repeated floor remain.",
        "files": rows}
    (OUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"files": len(rows), "bytes": sum(r["bytes"] for r in rows),
                      "manifest_sha256": sha(OUT / "manifest.json")}, ensure_ascii=False))


if __name__ == "__main__":
    main()
