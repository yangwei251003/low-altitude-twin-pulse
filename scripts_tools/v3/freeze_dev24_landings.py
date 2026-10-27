"""Archive the reviewed source capture, referring to committed exact input bytes."""
import hashlib
import json
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / "docs/v3/evidence/dev24-landings"
RUN = "shared-access-integrated-20261019_171107_59909e"
LOGS = ["dev24-landings-import-20261019_170437.log",
        "dev24-landings-physics-20261019_170437.log", RUN + ".log"]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    assert not DEST.exists(), "Existing evidence is immutable"
    source = ROOT / "artifacts/v3/art" / RUN
    report = json.loads((source / "state_checks.json").read_text(encoding="utf8"))
    assert report["passed"] and len(report["shots"]) == 7 and len(report["checks"]) == 153
    assert all(row["passed"] for row in report["checks"])
    inputs = report["input_sha256_before"]
    assert inputs == report["input_sha256_after"]
    for path, digest in inputs.items():
        assert sha(ROOT / path.removeprefix("res://")) == digest, path
    for name in LOGS:
        lines = (ROOT / "artifacts/v3" / name).read_text(encoding="utf8").splitlines()
        result = json.loads(next(line[15:] for line in reversed(lines) if line.startswith("DEV_RUN_RESULT ")))
        assert result["passed"] and result["returncode"] == 0 and result["remaining_owned_processes"] == 0
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    tree = {}
    for item in subprocess.check_output(["git", "ls-tree", "-rz", commit], cwd=ROOT).split(b"\0"):
        if item:
            header, path = item.split(b"\t", 1)
            tree[path.decode("utf8")] = header.split()[-1].decode("ascii")
    DEST.mkdir(parents=True)
    refs = []
    for path, digest in sorted(inputs.items()):
        name = path.removeprefix("res://")
        raw = (ROOT / name).read_bytes()
        blob = hashlib.sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest()
        row = {"resource": name, "sha256": digest, "bytes": len(raw)}
        if name.startswith(".godot/"):
            row["availability"] = "rebuildable_cache_fingerprint_only_not_archived"
        elif tree.get(name) == blob:
            row.update(source_commit=commit, git_blob=blob)
        else:
            target = DEST / "captured-inputs" / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(raw)
            row["frozen_path"] = target.relative_to(DEST).as_posix()
        refs.append(row)
    shutil.copytree(source, DEST / "bridge")
    for name in LOGS:
        shutil.copy2(ROOT / "artifacts/v3" / name, DEST / name)
    (DEST / "input_references.json").write_text(json.dumps(refs, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    files = [{"path": p.relative_to(DEST).as_posix(), "bytes": p.stat().st_size, "sha256": sha(p)}
             for p in sorted(DEST.rglob("*")) if p.is_file()]
    manifest = {"source_commit": commit, "files": files, "input_count": len(refs),
                "root_viewed": "all seven actual MAIN images",
                "scope": "fixed landing source integration and scripted physics; no new package/LAN/performance/human-play claim",
                "whole_region_art_accepted": False,
                "source_failures": "asset_sources/v3/shared_access_landings/delivery_p4/failed_missing_paint_20261019_1636",
                "limits": ["Rebuildable caches are fingerprinted, not duplicated.",
                           "Failure source/log/render history remains in the editable asset directory."]}
    (DEST / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    assert all(sha(DEST / f["path"]) == f["sha256"] for f in files)
    print(json.dumps({"files": len(files), "inputs": len(refs), "source_commit": commit,
                      "manifest_sha256": sha(DEST / "manifest.json")}, ensure_ascii=False))


if __name__ == "__main__":
    main()
