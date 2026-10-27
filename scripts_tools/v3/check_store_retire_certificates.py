"""Root-only bounded Source probe. Native Windows no-delete handle, never a mocked Store result."""
import argparse
import concurrent.futures
import ctypes as ct
from ctypes import wintypes as wt
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import time
import uuid


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--probe", required=True, type=Path, help="Reviewed probe promoted by Root to canonical QA")
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--expected-store-lf-sha256", required=True)
    args = parser.parse_args()
    if os.name != "nt":
        parser.error("Windows lock semantics required")
    supplied_root = args.root.resolve(strict=True)
    runner = Path(__file__).resolve(strict=True)
    if runner.parent.name == "v3" and runner.parent.parent.name == "scripts_tools" and supplied_root != runner.parents[2]:
        parser.error("canonical runner/project root mismatch")
    sys.path.insert(0, str(supplied_root / "scripts_tools/v3"))
    import dev
    from storage_policy import plain_path, atomic_json, MiB, EXPECTED_PROJECT
    expected = plain_path(dev.ROOT, existing=True)
    if supplied_root != expected or expected != plain_path(EXPECTED_PROJECT, existing=True):
        parser.error("wrong real project root")
    probe = plain_path(args.probe, existing=True)
    if not probe.is_relative_to(expected / "scripts/v3/qa") or probe.suffix != ".gd":
        parser.error("probe must be reviewed canonical project QA")
    godot = plain_path(args.godot, existing=True)
    if godot != plain_path(dev.GODOT, existing=True):
        parser.error("pinned Godot required")
    store_bytes = (expected / "scripts/v3/core/twin_world_store.gd").read_bytes()
    store_lf = store_bytes.decode("utf-8-sig").replace("\r\n","\n").encode("utf-8")
    store_sha = hashlib.sha256(store_lf).hexdigest()
    if store_sha != args.expected_store_lf_sha256:
        parser.error("reviewed Store LF SHA mismatch; no engine started")
    token = uuid.uuid4().hex[:12]
    root_name = "qa_v3_retire_cert85_" + token
    user_base = plain_path(Path(os.environ["APPDATA"]) / "LowAltitudeTwinPulseV3", existing=True)
    # MSIX may expose logical Roaming and redirected APPDATA names for one file.
    # Allow only these two known roots, fixed fresh token and exact fixed filename.
    logical_base = plain_path(Path(os.environ["USERPROFILE"]) / "AppData/Roaming/LowAltitudeTwinPulseV3")
    bases = {user_base, logical_base}
    fixtures = {plain_path(base / root_name) for base in bases}
    if any(path.exists() for path in fixtures):
        raise RuntimeError("refusing existing private fixture/known alias")
    fixture = plain_path(user_base / root_name)
    allowed_targets = {plain_path(base / root_name / "locked/profile_g000000000001.json") for base in bases}
    label = "store-retire-cert85-" + datetime.datetime.now().strftime("%Y%m%d_%H%M%S") + "_" + token
    evidence = dev.POLICY.path("evidence", label)
    dev.POLICY.preflight_qa(32 * MiB)
    dev.POLICY.preflight("evidence", 2 * MiB)
    evidence.mkdir(exist_ok=False)
    dev.LOG_LIMIT = MiB  # Existing direct-call bounded pipe; no replacement log framework.
    kernel = ct.WinDLL("kernel32", use_last_error=True)
    kernel.CreateFileW.argtypes = [wt.LPCWSTR, wt.DWORD, wt.DWORD, ct.c_void_p, wt.DWORD, wt.DWORD, wt.HANDLE]
    kernel.CreateFileW.restype = wt.HANDLE
    kernel.CloseHandle.argtypes = [wt.HANDLE]
    kernel.CloseHandle.restype = wt.BOOL
    class HandleInfo(ct.Structure):
        _fields_ = [("attributes",wt.DWORD),("creation",wt.FILETIME),("access",wt.FILETIME),("write",wt.FILETIME),
                    ("volume",wt.DWORD),("size_high",wt.DWORD),("size_low",wt.DWORD),("links",wt.DWORD),
                    ("index_high",wt.DWORD),("index_low",wt.DWORD)]
    kernel.GetFileInformationByHandle.argtypes = [wt.HANDLE,ct.POINTER(HandleInfo)]
    kernel.GetFileInformationByHandle.restype = wt.BOOL
    invalid = ct.c_void_p(-1).value
    def open_read(path, sharing):
        result = kernel.CreateFileW(str(path),0x80000000,sharing,None,3,0x80,None)
        if result == invalid:
            raise ct.WinError(ct.get_last_error())
        return result
    def identity(handle_value):
        info = HandleInfo()
        if not kernel.GetFileInformationByHandle(handle_value,ct.byref(info)):
            raise ct.WinError(ct.get_last_error())
        return (info.volume,info.index_high,info.index_low)
    handle = None
    run = {}
    notes = {"identity_verified":False,"lock_acquired":False,"lock_released":False,"fixture_removed":False}
    error = None
    command = [str(godot), "--headless", "--path", str(expected), "--script", str(probe), "--",
               "--qa-root=user://" + root_name, "--qa-evidence=" + str(evidence)]
    began = time.monotonic()
    try:
        with (evidence / "engine.log").open("xb", buffering=0) as log:
            with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
                future = pool.submit(dev._windows_run, command, log, 22)
                try:
                    while not future.done():
                        request = evidence / "lock-request.json"
                        if request.exists() and not notes["lock_acquired"]:
                            if request.stat().st_size > 4096:
                                raise RuntimeError("oversize lock request")
                            data = json.loads(request.read_text(encoding="utf-8-sig"))
                            native_path = Path(data["path"])
                            path = plain_path(native_path, existing=True)
                            expected_old = plain_path(fixture / "locked/profile_g000000000001.json",existing=True)
                            if data.get("qa_root") != "user://" + root_name or path not in allowed_targets:
                                raise RuntimeError("lock target escaped known fresh private roots")
                            # Native path is retained. Verify both names open the same volume/file ID.
                            # Real reads/writes remain allowed; only deletion/rename is denied.
                            handle = open_read(native_path,1 | 2)
                            expected_handle = open_read(expected_old,1 | 2 | 4)
                            try:
                                if identity(handle) != identity(expected_handle):
                                    raise RuntimeError("native request and APPDATA file identities differ")
                            finally:
                                kernel.CloseHandle(expected_handle)
                            notes["identity_verified"] = True
                            notes["lock_acquired"] = True
                            atomic_json(evidence / "lock-ack.json", {"real_no_delete_handle":True})
                        if handle is not None and (evidence / "release-request.json").exists():
                            if not kernel.CloseHandle(handle):
                                raise ct.WinError(ct.get_last_error())
                            handle = None
                            notes["lock_released"] = True
                            atomic_json(evidence / "release-ack.json", {"released":True})
                        time.sleep(0.02)
                finally:
                    if handle is not None:
                        kernel.CloseHandle(handle)
                        handle = None
                    # Child wall limit22s plus existing owned-job cleanup<=5s.
                    run = future.result(timeout=29)
    except Exception as exc:
        error = f"{type(exc).__name__}: {exc}"[:512]
    finally:
        if handle is not None:
            kernel.CloseHandle(handle)
        # Exact fresh fixture only, no recursive delete, reparse ancestors refused.
        try:
            for candidate_root in fixtures:
                safe = plain_path(candidate_root)
                if safe.parent not in bases or not re.fullmatch(r"qa_v3_retire_cert85_[0-9a-f]{12}",safe.name):
                    raise RuntimeError("fixture cleanup containment failed")
                if safe.exists():
                    for directory in safe.iterdir():
                        directory = plain_path(directory, existing=True)
                        if directory.parent != safe or directory.name not in {"basic","derived","locked"} or not directory.is_dir():
                            raise RuntimeError("unknown fixture directory; retaining")
                        for path in directory.iterdir():
                            path = plain_path(path, existing=True)
                            if path.parent != directory or not path.is_file() or not re.fullmatch(r"profile_g[0-9]{12}\.json(?:\.tmp)?",path.name):
                                raise RuntimeError("unknown fixture file; retaining")
                            path.unlink()
                        directory.rmdir()
                    safe.rmdir()
            notes["fixture_removed"] = all(not path.exists() for path in fixtures)
        except Exception as exc:
            error = error or f"cleanup {type(exc).__name__}: {exc}"[:512]
    report = None
    report_path = evidence / "result.json"
    if report_path.exists() and report_path.stat().st_size <= 64 * 1024:
        report = json.loads(report_path.read_text(encoding="utf-8-sig"))
    log_bytes = (evidence / "engine.log").read_bytes()
    passed = bool(report and report.get("passed") and not error and all(notes.values()) and run.get("returncode")==0
                  and not run.get("timed_out") and not run.get("orphan_cleanup") and not run.get("output_stopped")
                  and run.get("remaining_owned_processes")==0 and not run.get("log_error") and b"ERROR:" not in log_bytes)
    summary = {"schema":1,"passed":passed,"scope":"Source Store fixtures; no Main/EXE/performance claim", "error":error,
               "source_store_raw_sha256":hashlib.sha256(store_bytes).hexdigest(),"source_store_lf_sha256":store_sha,
               "probe_sha256":hashlib.sha256(probe.read_bytes()).hexdigest(),"notes":notes,"run":run,"elapsed_seconds":round(time.monotonic()-began,3),"checks":len(report.get("checks",[])) if report else 0}
    atomic_json(evidence / "controller.json", summary)
    print(json.dumps({"evidence":str(evidence),**summary},ensure_ascii=False))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
