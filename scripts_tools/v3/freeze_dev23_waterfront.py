"""Freeze completed dev23 evidence; preserve source bytes, not rebuildable caches."""
import hashlib
import json
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / "docs/v3/evidence/dev23-waterfront"
CAPTURES = {
    "waterfront": ("clinic-integrated-waterfront-20261019_154208_b6c305", 5, 76),
    "clinic": ("clinic-integrated-20261019_154421_8d7216", 22, 271),
}
NETWORK = {
    "waterfront-lan": "waterfront/20261019_153314_8fef61",
    "facility-lan": "distribution/20261019_154108_139870",
    "normal-lan": "20261019_154137_973840",
}
LOGS = [
    "dev23-waterfront-physics-20261019_092150.log", "dev23-water-authority-20261019_093604.log",
    "dev23-network-input-20261019_103358.log", "dev23-final-import-20261019_154100.log",
    "dev23-final-facility-lan-20261019_154100.log", "dev23-final-normal-lan-20261019_154100.log",
    "waterfront-integrated-20261019_154208_b6c305.log", "clinic-integrated-20261019_154421_8d7216.log",
]
FAILURES = [
    "dev23-waterfront-physics-20261019_0928.log", "dev23-waterfront-physics-20261019_0930.log",
    "dev23-water-authority-20261019_092150.log", "dev23-water-authority-20261019_093317.log",
    "waterfront-integrated-20261019_092501_4a2fd8.log", "dev23-waterfront-lan-20261019_103358.log",
]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    assert not DEST.exists(), "Existing evidence is immutable"
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    tree = {}
    for item in subprocess.check_output(["git", "ls-tree", "-rz", commit], cwd=ROOT).split(b"\0"):
        if item:
            header, path = item.split(b"\t", 1)
            tree[path.decode("utf8")] = header.split()[-1].decode("ascii")
    inputs, copies = {}, []

    def add_inputs(mapping):
        for path, digest in mapping.items():
            name = path.removeprefix("res://")
            assert name not in inputs or inputs[name] == digest, name
            inputs[name] = digest

    for label, (run, shots, checks) in CAPTURES.items():
        folder = ROOT / "artifacts/v3/art" / run
        report = json.loads((folder / "state_checks.json").read_text(encoding="utf8"))
        assert report["passed"] and len(report["shots"]) == shots and len(report["checks"]) == checks
        assert all(c["passed"] for c in report["checks"])
        assert report["input_sha256_before"] == report["input_sha256_after"]
        add_inputs(report["input_sha256_before"])
        copies.append((folder, label))
    for label, run in NETWORK.items():
        folder = ROOT / "artifacts/v3/network" / run
        report = json.loads((folder / "summary.json").read_text(encoding="utf8"))
        assert report["passed"] and all(c["passed"] for c in report["checks"])
        before = report.get("source_before", report.get("source_sha256_before"))
        after = report.get("source_after", report.get("source_sha256_after"))
        assert before and before == after
        add_inputs(before)
        copies.append((folder, label))
    for name in LOGS:
        lines = (ROOT / "artifacts/v3" / name).read_text(encoding="utf8").splitlines()
        result = json.loads(next(line[15:] for line in reversed(lines) if line.startswith("DEV_RUN_RESULT ")))
        assert result["passed"] and result["returncode"] == 0 and result["remaining_owned_processes"] == 0
    for name, digest in inputs.items():
        assert sha(ROOT / name) == digest, name
    # All checks precede writing. Imported caches retain their exact measured
    # fingerprints; they can be regenerated with the pinned engine from sources.
    DEST.mkdir(parents=True)
    refs = []
    for name, digest in sorted(inputs.items()):
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
    for folder, label in copies:
        shutil.copytree(folder, DEST / label)
    for name in LOGS:
        shutil.copy2(ROOT / "artifacts/v3" / name, DEST / name)
    rejected = DEST / "prior-failures"
    rejected.mkdir()
    for name in FAILURES:
        shutil.copy2(ROOT / "artifacts/v3" / name, rejected / name)
    for folder, label in [
        (ROOT / "artifacts/v3/art/clinic-integrated-waterfront-20261019_092501_4a2fd8", "surface-bobbing"),
        (ROOT / "artifacts/v3/network/waterfront/20261019_103359_703054", "overstrict-wait-observer"),
    ]:
        shutil.copytree(folder, rejected / label)
    (DEST / "input_references.json").write_text(json.dumps(refs, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    files = [{"path": p.relative_to(DEST).as_posix(), "bytes": p.stat().st_size, "sha256": sha(p)}
             for p in sorted(DEST.rglob("*")) if p.is_file()]
    manifest = {"source_commit": commit, "files": files, "input_count": len(refs),
                "scope": "dev23 source real terrain, actual MAIN captures, same-computer ENet; no new package/two-PC/performance/human-play claim",
                "whole_region_art_accepted": False,
                "root_viewed": {"waterfront": "all five", "clinic": ["21-I2-maintenance-bay-default.png"]},
                "limits": ["Rebuildable engine caches are fingerprinted, not duplicated.",
                           "Prior failures retain observed artifacts, not complete intermediate-source snapshots."]}
    (DEST / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    assert all(sha(DEST / row["path"]) == row["sha256"] for row in files)
    print(json.dumps({"files": len(files), "inputs": len(refs), "source_commit": commit,
                      "manifest_sha256": sha(DEST / "manifest.json")}, ensure_ascii=False))


if __name__ == "__main__":
    main()
