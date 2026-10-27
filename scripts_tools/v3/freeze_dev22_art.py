"""Retain the actual dev22 captures and exact source inputs, without rerunning."""
import hashlib
import json
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / "docs/v3/evidence/dev22-art"
RUNS = [
    ("bridge", "shared-access-integrated-20261019_082120_2bf573", 7, 153,
     "dev22-bridge-art-capture-20261019_082120_2bf573.log"),
    ("bay", "clinic-integrated-20261019_082258_f8f83f", 22, 440,
     "dev22-bay-art-capture-20261019_082258_f8f83f.log"),
]
LOGS = ["dev22-art-import-20261019_081817.log",
        "dev22-bridge-art-physics-20261019_081947.log",
        "dev22-shared-session-20261019_083145.log"]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    assert not DEST.exists(), "Refuse to overwrite a frozen evidence set"
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    tree = {}
    for item in subprocess.check_output(["git", "ls-tree", "-rz", commit], cwd=ROOT).split(b"\0"):
        if item:
            header, path = item.split(b"\t", 1)
            tree[path.decode("utf8")] = header.split()[-1].decode("ascii")
    inputs, captures = {}, []
    for label, directory, shots, count, logfile in RUNS:
        source = ROOT / "artifacts/v3/art" / directory
        report = json.loads((source / "state_checks.json").read_text(encoding="utf8"))
        assert report["passed"] and len(report["shots"]) == shots and len(report["checks"]) == count
        assert all(row["passed"] for row in report["checks"])
        assert report["input_sha256_before"] == report["input_sha256_after"]
        for resource, digest in report["input_sha256_before"].items():
            assert resource not in inputs or inputs[resource] == digest
            inputs[resource] = digest
        captures.append({"label": label, "source": source, "directory": directory,
                         "shots": shots, "checks": count, "log": logfile})
    # Verify every input while the checked working tree still exists, before copying.
    references = []
    for resource, digest in sorted(inputs.items()):
        relative = resource.removeprefix("res://")
        source = ROOT / relative
        raw = source.read_bytes()
        assert hashlib.sha256(raw).hexdigest() == digest, relative
        blob = hashlib.sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest()
        row = {"resource": relative, "bytes": len(raw), "sha256": digest}
        if tree.get(relative) == blob:
            row.update(source_commit=commit, git_blob=blob)
        else:
            target = DEST / "inputs" / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(raw)
            row["frozen_path"] = target.relative_to(ROOT).as_posix()
        references.append(row)
    DEST.mkdir(parents=True, exist_ok=True)
    for row in captures:
        shutil.copytree(row["source"], DEST / row["label"])
    for name in LOGS + [row["log"] for row in captures]:
        source = ROOT / "artifacts/v3" / name
        result_line = next(line for line in reversed(source.read_text(encoding="utf8").splitlines()) if line.startswith("DEV_RUN_RESULT "))
        result = json.loads(result_line.split(" ", 1)[1])
        assert result["passed"] and result["returncode"] == 0 and result["remaining_owned_processes"] == 0
        shutil.copy2(source, DEST / name)
    (DEST / "input_references.json").write_text(json.dumps(references, ensure_ascii=False, indent=2)+"\n", encoding="utf8")
    files = [{"path": p.relative_to(DEST).as_posix(), "bytes": p.stat().st_size, "sha256": sha(p)}
             for p in sorted(DEST.rglob("*")) if p.is_file()]
    manifest = {"source_commit": commit, "scope": "Two source art integrations, real MAIN GPU captures and isolated physics. Not a new standalone package, two-PC LAN, performance or human playtest.",
                "root_viewed": {"bridge": "all seven images", "bay": ["17-I2-service-court.png", "19-I2-receiving-approach.png", "21-I2-maintenance-bay-default.png", "22-I2-maintenance-bay-zoom.png"]},
                "whole_region_art_accepted": False, "input_count": len(references), "files": files}
    (DEST / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+"\n", encoding="utf8")
    assert all(sha(DEST / row["path"]) == row["sha256"] for row in files)
    print(json.dumps({"files": len(files), "inputs": len(references), "source_commit": commit,
                      "manifest_sha256": sha(DEST / "manifest.json")}, ensure_ascii=False))


if __name__ == "__main__":
    main()
