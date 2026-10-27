"""Explicit milestone packaging: one current candidate + one retained share ZIP.

Export and packaging are delivery production, not gameplay acceptance.
Keep the current candidate's actual verification scope in its version-matched report.
"""
import argparse
import hashlib
import json
import zipfile

import storage_policy as st


def package(policy):
    policy._require_lock()
    index = policy._index()
    candidate = policy.candidate_id(index.get("current") or "")
    source = policy.path("builds", candidate)
    policy.size(source)  # Reject every nested reparse before reading payloads.
    marker = json.loads((source / ".owned.json").read_text(encoding="utf-8"))
    if marker != {"owner": policy.owner["owner"], "kind": "candidate", "id": candidate}:
        raise st.PolicyError("current candidate ownership mismatch")
    build = json.loads((source / "BUILD.json").read_text(encoding="utf-8"))
    paths = sorted(p for p in source.rglob("*") if p.is_file() and p.name != ".owned.json")
    observed = {p: (p.stat().st_size, p.stat().st_mtime_ns, p.stat().st_ino) for p in paths}
    total = sum(row[0] for row in observed.values())
    policy.preflight("builds", total + total // 1000 + len(paths) * 4096 + st.MiB)
    target = policy.path("builds", "share", "LowAltitudeTwinPulse-" + candidate + ".zip")
    if target.exists():
        raise st.PolicyError("existing milestone ZIP preserved; do not package an unchanged candidate again")
    target.parent.mkdir(exist_ok=True)
    committed = False
    try:
        with zipfile.ZipFile(target, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=6, allowZip64=True) as archive:
            for path in paths:
                digest = hashlib.sha256()
                with path.open("rb") as stream, archive.open(candidate + "/" + path.relative_to(source).as_posix(), "w", force_zip64=True) as member:
                    for block in iter(lambda: stream.read(st.MiB), b""):
                        digest.update(block)
                        member.write(block)
                if path.name == "LowAltitudeTwinPulse-Dev.exe" and (digest.hexdigest() != build.get("exe_sha256") or observed[path][0] != build.get("exe_bytes")):
                    raise st.PolicyError("candidate EXE no longer matches its successful export BUILD")
                if (path.stat().st_size, path.stat().st_mtime_ns, path.stat().st_ino) != observed[path]:
                    raise st.PolicyError("candidate changed during packaging")
        if not any(p.name == "LowAltitudeTwinPulse-Dev.exe" for p in paths):
            raise st.PolicyError("candidate EXE missing")
        policy.preflight("builds", 0)
        # One new ZIP SHA and CRC pass; old share is removed only after success.
        policy.register_share(target.name)
        committed = True
        return {"share": str(target), "zip_bytes": target.stat().st_size, "exe_sha256": build["exe_sha256"],
                "scope": "Content development package; exact source-check scope is in VERIFICATION.md; export is not gameplay acceptance"}
    finally:
        if not committed and target.exists():
            # register_share commits its index before old-share retirement. If a
            # retirement error follows, keep the newly registered valid ZIP.
            saved = policy._index().get("share")
            if not saved or saved.get("file") != target.name:
                st.plain_path(target, existing=True).unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args()
    policy = st.StoragePolicy()
    with policy.lock():
        print(json.dumps(package(policy), ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except (st.PolicyError, OSError, ValueError, zipfile.BadZipFile) as error:
        raise SystemExit("Package refused: " + str(error)) from error
