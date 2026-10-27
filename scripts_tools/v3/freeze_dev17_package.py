"""Freeze the explicitly named dev17 package checks without changing the EXE."""
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / "docs/v3/evidence/dev17-package"
EXE = ROOT / "build/V3Dev17Candidate/LowAltitudeTwinPulse-Dev.exe"
EXPECTED = "7b368740526d85baa4f25476894d8b4058f63a57a92b844d1ce91aafc40e59b1"
SOURCES = {
    "visual": "artifacts/v3/art/package-20261019_020042_ddfe95",
    "network": "artifacts/v3/network/20261019_020449_739500",
    "clinic": "build/V3Dev17Candidate/artifacts/v3/network/clinic/20261019_020246_803469",
    "underdeck": "build/V3Dev17Candidate/artifacts/v3/network/underdeck/20261019_020555_538618",
    "entry": "build/V3Dev17Candidate/artifacts/v3/app-entry/20261019_020721_813605",
}
LOGS = [
    "export-20261019_015633_da80a2.log",
    "package_visual_dev17-20261019_020042.log",
    "package_clinic_dev17-20261019_020246.log",
    "package_lan_dev17-20261019_020449.log",
    "package_underdeck_dev17-20261019_020555.log",
    "package_entry_dev17-20261019_020721.log",
]
QA = [
    "scripts/v3/qa/twin_packaged_capture.gd", "scripts_tools/v3/capture_package.py",
    "scripts_tools/v3/test_clinic_lan.py", "scripts_tools/v3/test_lan_local.py",
    "scripts_tools/v3/test_underdeck_lan.py", "scripts_tools/v3/test_app_entry.py",
    "scripts_tools/v3/dev.py",
]

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    if sha(EXE) != EXPECTED or EXE.stat().st_size != 467689440:
        raise RuntimeError("The tested executable changed")
    if DEST.exists():
        raise RuntimeError("Immutable destination already exists")
    for name, source in SOURCES.items():
        report = ROOT / source / ("validation.json" if name == "visual" else "summary.json")
        if json.loads(report.read_text(encoding="utf-8"))["passed"] is not True:
            raise RuntimeError(f"Failed proof: {name}")
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
            if path.is_file(): copy(path, Path(name) / path.relative_to(base))
    for name in LOGS: copy(ROOT / "artifacts/v3" / name, Path("logs") / name)
    for name in QA: copy(ROOT / name, Path("qa-source") / name)
    copy(ROOT / "build/V3Dev17Candidate/BUILD.json", Path("BUILD-at-export.json"))
    manifest = {"version":"3.0.0-dev.17", "protocol":15,
        "exe_sha256":EXPECTED, "exe_bytes":EXE.stat().st_size,
        "source_baseline":"739d195", "source_delta":[QA[0],QA[1]],
        "source_note":"Gameplay/assets at baseline; two export QA changes copied here. Per-run input hashes remain in original reports.",
        "scope":"Partial development checkpoint: actual exported GPU capture and same-computer ENet; no full-game, two-PC, performance or human-playtest acceptance.",
        "files":files}
    (DEST / "manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    for row in files:
        if sha(DEST / row["path"]) != row["sha256"]: raise RuntimeError("Final readback failed")
    print(json.dumps({"files":len(files),"bytes":sum(r["bytes"] for r in files),
                      "manifest_sha256":sha(DEST / "manifest.json")},ensure_ascii=False))

if __name__ == "__main__": main()
