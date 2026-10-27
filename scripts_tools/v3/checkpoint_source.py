"""Opt-in small code snapshots: two good copies, 256 MiB total, never Desktop.

Ordinary QA constants/docs do not require a checkpoint. Full assets recovery is
an explicit separate migration; this first bounded version refuses that mode.
"""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import os
import re
import uuid
import zipfile

import storage_policy as storage

CODE_ROOTS = ("scripts", "scenes", "data", "config", "docs", "scripts_tools", "tests_v3", "addons")
SUFFIXES = {".py", ".gd", ".uid", ".tscn", ".tres", ".godot", ".gdextension", ".gdshader", ".gdshaderinc", ".glsl", ".json", ".cfg", ".ini", ".md", ".txt", ".yaml", ".yml", ".toml", ".csv", ".bat", ".cmd", ".ps1", ".sh"}
OMIT = {".git", ".godot", "__pycache__", "node_modules", "evidence", "exports"}
MAX_FILE = 8 * storage.MiB


def source_files(root):
    selected = []
    for item in root.iterdir():
        if item.is_file() and (item.suffix.lower() in SUFFIXES or item.name == ".gitignore"):
            selected.append(storage.plain_path(item, existing=True))
    for name in CODE_ROOTS:
        folder = root / name
        if not folder.exists():
            continue
        storage.plain_path(folder, existing=True)
        for directory, dirs, files in os.walk(folder, followlinks=False):
            dirs[:] = [n for n in dirs if n not in OMIT]
            for child in dirs:
                storage.plain_path(Path(directory) / child, existing=True)
            for child in files:
                path = Path(directory) / child
                if path.suffix.lower() in SUFFIXES:
                    selected.append(storage.plain_path(path, existing=True))
    return sorted(set(selected), key=lambda p: p.relative_to(root).as_posix())


def validate_archive(path, rows):
    with zipfile.ZipFile(path) as archive:
        if archive.testzip() is not None:
            raise storage.PolicyError("snapshot CRC failure")
        if archive.namelist() != [row["path"] for row in rows]:
            raise storage.PolicyError("snapshot whitelist mismatch")
        for row in rows:
            if hashlib.sha256(archive.read(row["path"])).hexdigest() != row["sha256"]:
                raise storage.PolicyError("snapshot member SHA mismatch")


def create_code_snapshot(policy):
    """Caller holds lock. Reads only the explicit small-code roots, never assets."""
    policy._require_lock()
    root = policy.project
    paths = source_files(root)
    if not paths:
        raise storage.PolicyError("no code files selected")
    sizes = [p.stat().st_size for p in paths]
    if any(size > MAX_FILE for size in sizes):
        raise storage.PolicyError("large code file refused; review explicit assets workflow")
    # Includes ZIP/manifest/name overhead conservatively; no full-asset hashing.
    estimate = sum(sizes) + sum(4 * len(p.relative_to(root).as_posix().encode("utf-8")) + 1024 for p in paths) + 65536 + sum(sizes) // 1000
    code = policy.path("recovery", "code")
    used = policy.size(code)
    if used + estimate > storage.CODE_LIMIT:
        raise storage.PolicyError("code snapshots plus temporary candidate exceed 256 MiB")
    policy.preflight("recovery", estimate)
    code.mkdir(parents=True, exist_ok=True)
    index_path = policy.path("recovery", "code", "index.json")
    index = json.loads(index_path.read_text(encoding="utf-8")) if index_path.exists() else {"owner": policy.owner["owner"], "snapshots": []}
    if index.get("owner") != policy.owner["owner"] or not isinstance(index.get("snapshots"), list):
        raise storage.PolicyError("code snapshot index owner/schema mismatch")
    for identity in index["snapshots"]:
        if not isinstance(identity, str) or not re.fullmatch(r"snapshot-[0-9]{8}_[0-9]{6}-[0-9a-f]{8}", identity):
            raise storage.PolicyError("invalid snapshot identity")
    identity = "snapshot-" + datetime.datetime.now().strftime("%Y%m%d_%H%M%S") + "-" + uuid.uuid4().hex[:8]
    stage = policy.path("recovery", "code", ".pending-" + identity)
    final = policy.path("recovery", "code", identity)
    stage.mkdir(exist_ok=False)
    policy.mark(stage, "code", identity)
    try:
        rows = []
        archive = stage / "code.zip"
        with zipfile.ZipFile(archive, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
            for path in paths:
                before = path.stat()
                data = path.read_bytes()
                after = path.stat()
                if len(data) > MAX_FILE or (before.st_size, before.st_mtime_ns, before.st_ino) != (after.st_size, after.st_mtime_ns, after.st_ino):
                    raise storage.PolicyError("code changed during read")
                relative = path.relative_to(root).as_posix()
                bundle.writestr(relative, data)
                rows.append({"path": relative, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()})
        validate_archive(archive, rows)
        if source_files(root) != paths or any(storage.sha256(root / row["path"]) != row["sha256"] for row in rows):
            raise storage.PolicyError("code changed during snapshot; last good copies untouched")
        manifest = {"schema": 1, "kind": "small-code-only", "root": str(root), "owner": policy.owner["owner"], "files": rows,
                    "zip_sha256": storage.sha256(archive), "zip_crc_verified": True, "sources_unchanged_during_cut": True,
                    "scope": "Explicit small code roots/suffixes only. No assets, evidence, Git binary diff or full recovery claim."}
        storage.atomic_json(stage / "manifest.json", manifest)
        policy.preflight("recovery", 0)
        if policy.size(code) > storage.CODE_LIMIT:
            raise storage.PolicyError("actual code snapshot capacity exceeded; old copies untouched")
        os.replace(stage, final)
    except BaseException:
        if stage.exists():
            policy.remove_owned(stage, "code", identity)
        raise
    # New CRC/SHA/stability proof exists before any old copy is retired.
    index["snapshots"].append(identity)
    storage.atomic_json(index_path, index)
    while len(index["snapshots"]) > 2:
        old = index["snapshots"][0]
        policy.remove_owned(policy.path("recovery", "code", old), "code", old)
        index["snapshots"].pop(0)
        storage.atomic_json(index_path, index)
    return {"output": str(final), "files": len(rows), "source_bytes": sum(sizes), "zip_bytes": (final / "code.zip").stat().st_size,
            "zip_sha256": manifest["zip_sha256"], "crc_verified": True, "retained": len(index["snapshots"]), "scope": manifest["scope"]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assets", action="store_true")
    parser.add_argument("--refresh", action="store_true")
    parser.add_argument("--initialize", type=Path)
    options = parser.parse_args()
    if options.assets or options.refresh or options.initialize:
        parser.error("assets baseline/overlay migration is not implemented in this first bounded candidate; legacy ZIPs remain untouched")
    policy = storage.StoragePolicy()
    with policy.lock():
        print(json.dumps(create_code_snapshot(policy), ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except (storage.PolicyError, OSError, ValueError, zipfile.BadZipFile) as error:
        raise SystemExit("Checkpoint refused: " + str(error)) from error
