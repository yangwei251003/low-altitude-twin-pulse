"""Explicit asset-batch recovery refresh, never part of routine QA.

Reuse one existing verified full ZIP, keep one current overlay, and retire the
old chain only after current file coverage is proved. No extraction or Git diff.
Freeze source writers before invoking. Existing source/Git/saves are read-only.
"""
from pathlib import Path, PurePosixPath
import argparse
import datetime
import hashlib
import json
import os
import re
import shutil
import subprocess
import uuid
import zipfile

import storage_policy as st


def identity(path):
    info = path.stat()
    return [info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns]


def read_json(path):
    return json.loads(st.plain_path(path, existing=True).read_text(encoding="utf-8-sig"))


def safe_member(name):
    path = PurePosixPath(name)
    if not name or path.is_absolute() or ".." in path.parts or "\\" in name or ":" in name:
        raise st.PolicyError("unsafe source member")
    return path


def selected_sources(root):
    names = subprocess.check_output(["git", "-C", str(root), "ls-files", "--cached", "--others", "--exclude-standard", "-z"]).decode("utf-8").split("\0")
    selected = []
    for name in sorted(set(names) - {""}):
        parts = safe_member(name).parts
        if any(part in {"evidence", "exports", "node_modules", "__pycache__"} for part in parts):
            continue
        path = st.plain_path(root / name)
        if not path.is_relative_to(root):
            raise st.PolicyError("source path escaped root")
        if path.is_file():
            selected.append(name)
    return selected


def baseline(policy):
    record = read_json(policy.path("recovery", "baseline-manifest.json"))
    archive = policy.path("recovery", "baseline.zip")
    if record.get("owner") != policy.owner["owner"] or record.get("archive_identity") != identity(archive):
        raise st.PolicyError("baseline identity changed; inspect instead of silently rehashing/replacing")
    return record


def initialize(policy, manifest_path):
    policy._require_lock()
    destination = policy.path("recovery", "baseline.zip")
    manifest = policy.path("recovery", "baseline-manifest.json")
    if destination.exists() or manifest.exists():
        raise st.PolicyError("fixed baseline already exists")
    legacy = policy.path("recovery", "legacy-checkpoints")
    source = st.plain_path(manifest_path, existing=True)
    if source.name != "manifest.json" or source.parent.parent != legacy:
        raise st.PolicyError("only an explicit relocated legacy baseline can be adopted")
    data = read_json(source)
    if st.plain_path(data["root"], existing=True) != policy.project or data.get("base_manifest") or not data.get("zip_crc_verified") or not data.get("sources_unchanged_during_cut"):
        raise st.PolicyError("not a verified full baseline")
    original = st.plain_path(source.parent / "source-assets.zip", existing=True)
    policy.preflight("recovery", source.stat().st_size + st.MiB)
    # Once at migration, trust neither filename nor size alone. The matching
    # whole ZIP SHA carries the original completed CRC proof forward.
    before = identity(original)
    if st.sha256(original) != data["zip_sha256"] or identity(original) != before:
        raise st.PolicyError("legacy baseline SHA mismatch")
    expected = {row["path"]: row["bytes"] for row in data["files"]}
    for name in expected:
        safe_member(name)
    with zipfile.ZipFile(original) as archive:
        rows = archive.infolist()
        if len(rows) != len(expected) or {row.filename: row.file_size for row in rows} != expected:
            raise st.PolicyError("full baseline member coverage mismatch")
    data.update(owner=policy.owner["owner"], archive="baseline.zip", adopted_from=str(source),
                proof="Whole archive SHA matched original CRC-verified full archive; same-volume move, no payload copy")
    os.replace(original, destination)
    try:
        if identity(destination) != before:
            raise st.PolicyError("baseline move identity changed")
        data["archive_identity"] = before
        st.atomic_json(manifest, data)
    except BaseException:
        if not original.exists() and destination.exists() and identity(destination) == before:
            os.replace(destination, original)
        raise
    return {"baseline": str(destination), "bytes": before[2], "files": len(expected), "full_archive_duplicated": False}


def verify_overlay(path, rows):
    with zipfile.ZipFile(path) as archive:
        if archive.namelist() != [r["path"] for r in rows]:
            raise st.PolicyError("overlay whitelist mismatch")
        for row in rows:
            digest = hashlib.sha256()
            count = 0
            with archive.open(row["path"]) as stream:
                for block in iter(lambda: stream.read(st.MiB), b""):
                    digest.update(block)
                    count += len(block)
            # Reading to EOF also checks each ZIP CRC, in the same pass.
            if count != row["bytes"] or digest.hexdigest() != row["sha256"]:
                raise st.PolicyError("overlay member SHA/size mismatch")


def refresh(policy):
    policy._require_lock()
    base = baseline(policy)
    current_path = policy.path("recovery", "current-source-manifest.json")
    old = read_json(current_path) if current_path.exists() else None
    retired = None
    if old:
        old_name = old.get("overlay", "")
        if old.get("owner") != policy.owner["owner"] or not re.fullmatch(r"overlay-[0-9a-f]{32}\.zip", old_name):
            raise st.PolicyError("old overlay owner/name mismatch; preserved for inspection")
        retired = policy.path("recovery", old_name)
        if identity(retired) != old.get("overlay_identity"):
            raise st.PolicyError("old overlay changed; preserved for inspection")
    previous = {row["path"]: row for row in base["files"]}
    paths = selected_sources(policy.project)
    rows, changed, observed = [], [], {}
    for name in paths:
        source = policy.project / name
        before = identity(source)
        digest = st.sha256(source)
        if identity(source) != before:
            raise st.PolicyError("source changed during manifest read")
        observed[name] = before
        same = previous.get(name, {}).get("sha256") == digest and previous.get(name, {}).get("bytes") == before[2]
        row = {"path": name, "bytes": before[2], "sha256": digest, "source_identity": before,
               "archive": "baseline" if same else "overlay"}
        rows.append(row)
        if not same:
            changed.append(row)
    raw = sum(row["bytes"] for row in changed)
    estimate = raw + raw // 1000 + sum(4 * len(row["path"].encode("utf-8")) + 1024 for row in changed) + len(rows) * 1024 + st.MiB
    policy.preflight("recovery", estimate)
    filename = "overlay-" + uuid.uuid4().hex + ".zip"
    output = policy.path("recovery", filename)
    committed = False
    try:
        with zipfile.ZipFile(output, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=6, allowZip64=True) as archive:
            for row in changed:
                source = policy.project / row["path"]
                digest = hashlib.sha256()
                with source.open("rb") as stream, archive.open(row["path"], "w", force_zip64=True) as target:
                    for block in iter(lambda: stream.read(st.MiB), b""):
                        target.write(block)
                        digest.update(block)
                if digest.hexdigest() != row["sha256"] or identity(source) != observed[row["path"]]:
                    raise st.PolicyError("source changed while archiving")
        verify_overlay(output, changed)
        if selected_sources(policy.project) != paths or any(identity(policy.project / name) != observed[name] for name in paths):
            raise st.PolicyError("source set changed during recovery cut")
        record = {"schema": 1, "owner": policy.owner["owner"], "project": str(policy.project),
                  "created": datetime.datetime.now().isoformat(), "files": rows,
                  "deleted_since_baseline": sorted(set(previous) - set(paths)),
                  "baseline_sha256": base["zip_sha256"], "overlay": filename,
                  "overlay_bytes": output.stat().st_size, "overlay_sha256": st.sha256(output),
                  "overlay_identity": identity(output), "overlay_crc_and_member_sha_verified": True,
                  "sources_unchanged_during_cut": True, "source_bytes": sum(row["bytes"] for row in rows),
                  "scope": "Restore only this whitelist, selecting each file from baseline.zip or this overlay. Deleted baseline paths must not be restored. Git metadata/saves remain in their original locations."}
        policy.preflight("recovery", 0)
        st.atomic_json(current_path, record)
        committed = True
        warning = None
        if retired:
            try:
                if identity(retired) != old["overlay_identity"]:
                    raise st.PolicyError("old overlay changed after validation")
                retired.unlink()
            except (OSError, st.PolicyError) as error:
                warning = "New current committed; old overlay retained and still counts toward quota: " + str(error)
        return {"manifest": str(current_path), "files": len(rows), "changed_files": len(changed), "overlay_bytes": record["overlay_bytes"], "source_bytes": record["source_bytes"], "coverage_verified": True, "retirement_warning": warning}
    finally:
        if not committed and output.exists():
            st.plain_path(output, existing=True).unlink()


def retire_legacy(policy):
    policy._require_lock()
    base = baseline(policy)
    current = read_json(policy.path("recovery", "current-source-manifest.json"))
    if current.get("owner") != policy.owner["owner"] or current.get("baseline_sha256") != base["zip_sha256"] or not current.get("sources_unchanged_during_cut") or not current.get("overlay_crc_and_member_sha_verified"):
        raise st.PolicyError("verified replacement recovery required")
    overlay = policy.path("recovery", current["overlay"])
    if not re.fullmatch(r"overlay-[0-9a-f]{32}\.zip", overlay.name) or identity(overlay) != current["overlay_identity"]:
        raise st.PolicyError("replacement overlay identity mismatch")
    base_rows = {r["path"]: r for r in base["files"]}
    names = [r["path"] for r in current["files"]]
    if names != selected_sources(policy.project) or len(names) != len(set(names)):
        raise st.PolicyError("replacement is not the complete current source whitelist")
    if current.get("deleted_since_baseline") != sorted(set(base_rows) - set(names)):
        raise st.PolicyError("replacement deletion set mismatch")
    for row in current["files"]:
        safe_member(row["path"])
        if row["archive"] not in {"baseline", "overlay"} or identity(policy.project / row["path"]) != row.get("source_identity"):
            raise st.PolicyError("replacement source identity/archive mismatch")
        if row["archive"] == "baseline" and any(base_rows.get(row["path"], {}).get(k) != row[k] for k in ("bytes", "sha256")):
            raise st.PolicyError("replacement baseline member mismatch")
    verify_overlay(overlay, [r for r in current["files"] if r["archive"] == "overlay"])
    mapping_path = policy.path("recovery", "checkpoint-relocation.json")
    mapping = read_json(mapping_path)
    legacy = policy.path("recovery", "legacy-checkpoints")
    targets = []
    for row in mapping["relocations"]:
        target = st.plain_path(row["new"], existing=True)
        if target.parent != legacy or not re.fullmatch(r"低空小队-源码检查点-[0-9]{8}_[0-9]{6}", target.name):
            raise st.PolicyError("legacy target boundary mismatch")
        if set(x.name for x in target.iterdir()) - {"manifest.json", "source-assets.zip", "git-status.txt", "working-tree.patch"}:
            raise st.PolicyError("unexpected legacy contents; preserve")
        if st.sha256(target / "manifest.json") != row["manifest_unchanged_sha256"]:
            raise st.PolicyError("legacy manifest identity mismatch")
        targets.append(target)
    if set(legacy.iterdir()) != set(targets):
        raise st.PolicyError("unknown legacy directory; preserve")
    amount = policy.size(legacy)  # All nested reparse points rejected before any deletion.
    st.atomic_json(policy.path("recovery", "retired-checkpoints.json"), {"replaced_by": "current-source-manifest.json", "baseline": "baseline.zip", "net_bytes_retired": amount, "directories": mapping["relocations"]})
    for target in targets:
        st.plain_path(target, existing=True)
        shutil.rmtree(target)
    legacy.rmdir()
    mapping.update(legacy_retired=True, replacement="current-source-manifest.json", baseline="baseline.zip")
    st.atomic_json(mapping_path, mapping)
    return {"retired_directories": len(targets), "bytes_retired": amount, "replacement_coverage_verified": True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--initialize", type=Path, help="Adopt one relocated verified full manifest, moving its ZIP within recovery")
    parser.add_argument("--refresh", action="store_true", help="One explicit asset batch, reads current source once; not routine QA")
    parser.add_argument("--retire-legacy", action="store_true", help="Only after verified complete baseline+overlay replacement")
    options = parser.parse_args()
    if not any((options.initialize, options.refresh, options.retire_legacy)):
        parser.error("choose an explicit asset-batch operation")
    policy = st.StoragePolicy()
    with policy.lock():
        for enabled, operation in ((options.initialize, lambda: initialize(policy, options.initialize)), (options.refresh, lambda: refresh(policy)), (options.retire_legacy, lambda: retire_legacy(policy))):
            if enabled:
                print(json.dumps(operation(), ensure_ascii=False), flush=True)


if __name__ == "__main__":
    try:
        main()
    except (st.PolicyError, OSError, ValueError, zipfile.BadZipFile) as error:
        raise SystemExit("Recovery refused: " + str(error)) from error
