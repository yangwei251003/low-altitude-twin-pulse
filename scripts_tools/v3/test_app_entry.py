#!/usr/bin/env python3
"""Negative normal-entry process checks. Default prepares only; --run is explicit.

Source: --run --expected-underdeck-sha <frozen hash> --expected-clinic-sha <frozen hash>
PCK: add --standalone --godot <exported EXE>. No --script/source --path in PCK.
Selected --case runs require only their suite's expected SHA.
Only uniquely owned qa_underdeck_lan_* / qa_clinic_lan_* / qa_distribution_lan_* profiles are inspected or seeded.
"""
from __future__ import annotations

import argparse
from datetime import datetime
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import traceback

sys.dont_write_bytecode = True
from test_lan_local import (LanPortLock, LanRunBusy, USER_DIR_NAME, file_sha256,
                            process_options, utc_now)

LAYOUT = "data/v3/terrain/i1_underdeck_layout.json"
CLINIC_LAYOUT = "data/v3/terrain/i2_clinic_layout.json"
DISTRIBUTION_LAYOUT = "data/v3/terrain/i2_distribution_layout.json"
CASES = {
    "bare_underdeck": "unknown_qa_argument",
    "misspelled_suite": "unknown_qa_argument",
    "bare_suite": "missing_suite_value",
    "unknown_suite": "unknown_or_duplicate_suite",
    "duplicate_suite": "unknown_or_duplicate_suite",
    "missing_suite": "specialized_arguments_require_suite",
    "duplicate_profile": "unknown_or_duplicate_argument",
    "mixed_network": "unknown_or_duplicate_argument",
    "mixed_capture": "unknown_or_duplicate_argument",
    "existing_profile": "fresh_profile_or_reconnect_required",
    "host_reconnect": "profile_role_run_mismatch",
    "missing_heartbeat": "live_locked_controller_required",
    "expired_heartbeat": "live_locked_controller_required",
    "wrong_heartbeat_kind": "live_locked_controller_required",
    "wrong_layout_sha": "runtime_layout_hash_mismatch",
    "wrong_evidence_root": "evidence_path_not_exact_run_directory",
    "clinic_missing_suite": "specialized_arguments_require_suite",
    "clinic_suite_parameter_mismatch": "unknown_or_duplicate_argument",
    "clinic_wrong_profile": "profile_role_run_mismatch",
    "clinic_wrong_evidence_root": "evidence_path_not_exact_run_directory",
    "clinic_wrong_layout_sha": "runtime_layout_hash_mismatch",
    "clinic_wrong_heartbeat_kind": "live_locked_controller_required",
    "clinic_existing_profile": "fresh_profile_or_reconnect_required",
    "clinic_mixed_distribution_argument": "unknown_or_duplicate_argument",
    "distribution_missing_suite": "specialized_arguments_require_suite",
    "distribution_suite_parameter_mismatch": "unknown_or_duplicate_argument",
    "distribution_wrong_profile": "profile_role_run_mismatch",
    "distribution_wrong_evidence_root": "evidence_path_not_exact_run_directory",
    "distribution_wrong_layout_sha": "runtime_layout_hash_mismatch",
    "distribution_wrong_heartbeat_kind": "live_locked_controller_required",
    "distribution_existing_profile": "fresh_profile_or_reconnect_required",
    "distribution_mixed_clinic_argument": "unknown_or_duplicate_argument",
}
INPUTS = ["project.godot", "scenes/v3/app.tscn", "scenes/v3/main.tscn",
          "scripts/v3/twin_app.gd", "scripts/v3/twin_session.gd",
          "scripts/v3/twin_network.gd", "scripts/v3/qa/twin_underdeck_lan_runner.gd",
          "scripts/v3/qa/twin_underdeck_lan_peer.gd", LAYOUT,
          "scripts/v3/tests/clinic_lan_probe.gd", CLINIC_LAYOUT,
          "scripts/v3/tests/distribution_lan_probe.gd", DISTRIBUTION_LAYOUT,
          "scripts/v3/network/twin_facility_contract.gd", "scripts/v3/network/twin_snapshot_codec.gd",
          "scripts/v3/gameplay/twin_facility_registry.gd", "scripts/v3/gameplay/twin_clinic_session.gd",
          "scripts/v3/gameplay/twin_distribution_session.gd", "scripts/v3/gameplay/twin_trial_session.gd",
          "scripts/v3/gameplay/twin_shared_access_session.gd", "scripts/v3/gameplay/twin_i2_result_ledger.gd",
          "data/v3/terrain/i2_trial_flow_layout.json", "data/v3/terrain/i2_shared_access_layout.json",
          "data/v3/actions/clinic_action.json", "data/v3/actions/distribution_action.json",
          "scripts_tools/v3/test_app_entry.py", "scripts_tools/v3/test_lan_local.py"]


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def source_hashes(project: Path) -> dict:
    return {name: file_sha256(project / name) for name in INPUTS}


def profile_snapshot(path: Path) -> dict:
    """Called only for this run's exact, previously checked profile paths."""
    if not path.exists():
        return {"exists": False}
    if not path.is_dir() or path.resolve() != path:
        raise RuntimeError(f"Owned profile is not a plain directory: {path}")
    files, directories = {}, []
    for entry in sorted(path.rglob("*")):
        if entry.resolve() != entry:
            raise RuntimeError(f"Unexpected redirected entry in owned profile: {entry}")
        relative = entry.relative_to(path).as_posix()
        if entry.is_dir():
            directories.append(relative)
        elif entry.is_file():
            files[relative] = {"bytes": entry.stat().st_size, "sha256": file_sha256(entry)}
        else:
            raise RuntimeError(f"Unexpected owned profile entry: {entry}")
    return {"exists": True, "directories": directories, "files": files}


def case_spec(name: str, run_id: str, runtime_root: Path, case_dir: Path,
              sha: str, kind: str, now: float) -> dict:
    """Pure argument/fixture description; no process, directory or lock operations."""
    if name.startswith(("clinic_", "distribution_")):
        return facility_case_spec(name, run_id, runtime_root, case_dir, sha, kind, now)
    profile = f"qa_underdeck_lan_host_{run_id}"
    guest = f"qa_underdeck_lan_guest_{run_id}"
    evidence = runtime_root / "artifacts/v3/network/underdeck" / run_id
    values = {"qa-suite": "underdeck-lan", "qa-profile": profile,
              "qa-underdeck-role": "host", "qa-underdeck-label": "host",
              "qa-underdeck-run": run_id, "qa-underdeck-evidence": str(evidence),
              "qa-underdeck-sha": sha}
    controller = {"run_id": run_id, "pid": os.getpid(), "lock_held": True,
                  "heartbeat_unix": now, "underdeck_sha256": sha,
                  "qa_suite": "underdeck-lan", "entry_kind": kind,
                  "evidence": evidence.as_posix(), "profiles": {"host": profile, "guest": guest}}
    extra, owned_profiles = [], [profile]
    if name in ("bare_underdeck", "misspelled_suite", "bare_suite"):
        token = {"bare_underdeck": "--qa-underdeck", "misspelled_suite": "--qa-suitejunk=underdeck-lan",
                 "bare_suite": "--qa-suite"}[name]
        args = [token, f"--qa-profile={profile}"]
    else:
        if name == "unknown_suite": values["qa-suite"] = "not-a-suite"
        elif name == "duplicate_suite": extra.append("--qa-suite=underdeck-lan")
        elif name == "missing_suite": del values["qa-suite"]
        elif name == "duplicate_profile":
            extra.append(f"--qa-profile={guest}")
            owned_profiles.append(guest)
        elif name == "mixed_network": extra.append("--qa-network=host")
        elif name == "mixed_capture": extra.append(f"--qa-capture-output={case_dir / 'unexpected-capture'}")
        elif name == "host_reconnect": extra.append("--qa-underdeck-reconnect")
        elif name == "missing_heartbeat": controller = None
        elif name == "expired_heartbeat": controller["heartbeat_unix"] = now - 60.0
        elif name == "wrong_heartbeat_kind": controller["entry_kind"] = "source_script"
        elif name == "wrong_layout_sha":
            wrong_sha = ("1" if sha[0] == "0" else "0") + sha[1:]
            values["qa-underdeck-sha"] = wrong_sha
            controller["underdeck_sha256"] = wrong_sha
        elif name == "wrong_evidence_root":
            values["qa-underdeck-evidence"] = str(case_dir / "wrong-network-root" / run_id)
        args = [f"--{key}={value}" for key, value in values.items()] + extra
    return {"name": name, "run_id": run_id, "args": args, "evidence": evidence,
            "controller": controller, "profiles": owned_profiles,
            "seed_sentinel": name in ("existing_profile", "host_reconnect"),
            "expected_code": CASES[name]}


def facility_case_spec(name: str, run_id: str, runtime_root: Path, case_dir: Path,
                     sha: str, kind: str, now: float) -> dict:
    """One invalid facility boundary per case; all other fields remain valid."""
    suite = "distribution" if name.startswith("distribution_") else "clinic"
    case = name.removeprefix(suite + "_")
    profile = f"qa_{suite}_lan_host_{run_id}"
    guest = f"qa_{suite}_lan_guest_{run_id}"
    evidence = runtime_root / f"artifacts/v3/network/{suite}" / run_id
    values = {"qa-suite": f"{suite}-lan", "qa-profile": profile,
              f"qa-{suite}-role": "host", f"qa-{suite}-label": "host",
              f"qa-{suite}-run": run_id, f"qa-{suite}-evidence": str(evidence),
              f"qa-{suite}-sha": sha}
    controller = {"run_id": run_id, "pid": os.getpid(), "lock_held": True,
                  "heartbeat_unix": now, f"{suite}_sha256": sha,
                  "qa_suite": f"{suite}-lan", "entry_kind": kind,
                  "evidence": evidence.as_posix(), "profiles": {"host": profile, "guest": guest}}
    owned_profiles = [profile]
    if case == "missing_suite":
        del values["qa-suite"]
    elif case == "suite_parameter_mismatch":
        values["qa-suite"] = "underdeck-lan"
    elif case == "wrong_profile":
        # Still exclusively ours; never probe another user's or an existing save.
        wrong_profile = profile + "_wrong"
        values["qa-profile"] = wrong_profile
        controller["profiles"]["host"] = wrong_profile
        owned_profiles.append(wrong_profile)
    elif case == "wrong_evidence_root":
        values[f"qa-{suite}-evidence"] = str(case_dir / "wrong-network-root" / run_id)
    elif case == "wrong_layout_sha":
        wrong_sha = ("1" if sha[0] == "0" else "0") + sha[1:]
        values[f"qa-{suite}-sha"] = wrong_sha
        controller[f"{suite}_sha256"] = wrong_sha
    elif case == "wrong_heartbeat_kind":
        # A controller for the other runtime must not authorize this process.
        controller["entry_kind"] = "source_main" if kind == "package_main" else "package_main"
    elif case == "mixed_distribution_argument":
        values["qa-distribution-role"] = "host"
    elif case == "mixed_clinic_argument":
        values["qa-clinic-role"] = "host"
    elif case != "existing_profile":
        raise ValueError(f"Unknown facility rejection case: {name}")
    return {"name": name, "run_id": run_id,
            "args": [f"--{key}={value}" for key, value in values.items()],
            "evidence": evidence, "controller": controller, "profiles": owned_profiles,
            "seed_sentinel": case == "existing_profile", "expected_code": CASES[name]}


def game_command(exe: Path, project: Path, standalone: bool, log: Path, args: list[str]) -> list[str]:
    return ([str(exe), "--headless"] + ([] if standalone else ["--path", str(project)])
            + ["--log-file", str(log), "--"] + args)


def run_case(spec: dict, exe: Path, project: Path, runtime_root: Path, case_dir: Path,
             profiles_root: Path, standalone: bool, timeout: float) -> dict:
    case_dir.mkdir(parents=True, exist_ok=False)
    evidence: Path = spec["evidence"]
    if evidence.resolve() != evidence:
        raise RuntimeError("QA evidence directory must not redirect")
    evidence.mkdir(parents=True, exist_ok=False)
    paths = {name: profiles_root / name for name in spec["profiles"]}
    suite = suite_for(spec["name"])
    profile_prefix = f"qa_{suite}_lan_"
    for name, path in paths.items():
        if not name.startswith(profile_prefix) or path.resolve() != path or path.exists():
            raise RuntimeError(f"Refusing any reused or redirected QA profile: {path}")
    if spec["seed_sentinel"]:
        target = next(iter(paths.values()))
        target.mkdir(parents=True, exist_ok=False)
        (target / "sentinel.txt").write_bytes(b"Owned negative QA fixture; not a game save.\n")
        (target / "nested").mkdir()
        (target / "nested" / "sentinel.bin").write_bytes(bytes(range(32)))
    if spec["name"] in ("wrong_evidence_root", "clinic_wrong_evidence_root", "distribution_wrong_evidence_root"):
        (case_dir / "wrong-network-root" / spec["run_id"]).mkdir(parents=True, exist_ok=False)
    if spec["controller"] is not None:
        # Valid leases are published immediately before spawn. Expired stays expired.
        if spec["name"] != "expired_heartbeat": spec["controller"]["heartbeat_unix"] = time.time()
        write_json(evidence / "controller.json", spec["controller"])
    before = {name: profile_snapshot(path) for name, path in paths.items()}
    command = game_command(exe, project, standalone, case_dir / "engine.log", spec["args"])
    stdout = case_dir / "stdout-stderr.log"
    record = {"name": spec["name"], "expected_code": spec["expected_code"], "command": command,
              "cwd": str(runtime_root), "profile_paths": {k: str(v) for k, v in paths.items()},
              "profiles_before": before, "controller_path": str(evidence / "controller.json"),
              "forced_stop": False, "started_utc": utc_now()}
    with stdout.open("wb") as log:
        process = subprocess.Popen(command, cwd=runtime_root, stdout=log, stderr=subprocess.STDOUT,
                                   **process_options())
        record["pid"] = process.pid
        deadline = time.monotonic() + timeout
        try:
            while process.poll() is None:
                text = stdout.read_text(encoding="utf-8", errors="replace")
                if any(marker in text for marker in ("V3_READY", "UNDERDECK_QA_READY", "CLINIC_QA_READY", "DISTRIBUTION_QA_READY")) or time.monotonic() >= deadline:
                    record["forced_stop"] = True
                    record["stop_reason"] = "unexpected ready or bounded timeout"
                    process.terminate()
                    try: process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait(timeout=3)
                    break
                time.sleep(0.03)
        finally:
            if process.poll() is None:
                record["forced_stop"] = True
                process.kill()
                process.wait(timeout=3)
        record["exit_code"] = process.returncode
    text = stdout.read_text(encoding="utf-8", errors="replace")
    engine_log = case_dir / "engine.log"
    if engine_log.is_file(): text += "\n" + engine_log.read_text(encoding="utf-8", errors="replace")
    after = {name: profile_snapshot(path) for name, path in paths.items()}
    checks = {"exit_two": record["exit_code"] == 2,
              "not_forced": not record["forced_stop"],
              "specific_rejection": f"QA_ENTRY_REJECTED {spec['expected_code']}" in text,
              "no_profile_ready": "V3_READY" not in text,
              "no_specialized_ready": "UNDERDECK_QA_READY" not in text and "CLINIC_QA_READY" not in text and "DISTRIBUTION_QA_READY" not in text,
              "no_script_parse_error": "SCRIPT ERROR:" not in text and "Parse Error:" not in text,
              "owned_profile_bytes_unchanged": before == after,
              "fresh_profiles_absent": all(not after[name]["exists"] for name in paths if not before[name]["exists"])}
    record.update({"finished_utc": utc_now(), "profiles_after": after, "checks": checks,
                   "passed": all(checks.values()), "stdout_sha256": file_sha256(stdout)})
    write_json(case_dir / "result.json", record)
    print(f"{spec['name']}: {'PASS' if record['passed'] else 'FAIL'} exit={record['exit_code']}", flush=True)
    return record


def suite_for(name: str) -> str:
    return "distribution" if name.startswith("distribution_") else "clinic" if name.startswith("clinic_") else "underdeck"


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"): sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--godot", type=Path)
    parser.add_argument("--standalone", action="store_true")
    parser.add_argument("--expected-underdeck-sha", default="")
    parser.add_argument("--expected-clinic-sha", default="")
    parser.add_argument("--expected-distribution-sha", default="")
    parser.add_argument("--case", choices=tuple(CASES), action="append", dest="selected")
    parser.add_argument("--run", action="store_true")
    args = parser.parse_args()
    if not args.run:
        print("PREPARATION ONLY: no directories, profiles, locks or game processes created. Cases: " + ", ".join(args.selected or CASES))
        return 0
    if os.name != "nt" or not os.environ.get("APPDATA"):
        parser.error("This entry suite targets the verified Windows custom user directory")
    if args.standalone and args.godot is None: parser.error("--standalone requires an explicit exported --godot EXE")
    project = args.project.resolve()
    exe = (args.godot or Path(os.environ.get("LOCALAPPDATA", "")) / "Programs/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe").resolve()
    names = list(dict.fromkeys(args.selected or CASES))
    expected_shas = {"underdeck": args.expected_underdeck_sha.lower(), "clinic": args.expected_clinic_sha.lower(), "distribution": args.expected_distribution_sha.lower()}
    needed = {suite_for(name) for name in names}
    if not exe.is_file(): parser.error("Executable missing")
    for suite in sorted(needed):
        sha = expected_shas[suite]
        if len(sha) != 64 or any(c not in "0123456789abcdef" for c in sha):
            parser.error(f"Explicit frozen --expected-{suite}-sha required")
        layout = {"clinic": CLINIC_LAYOUT, "distribution": DISTRIBUTION_LAYOUT, "underdeck": LAYOUT}[suite]
        if not (project / layout).is_file() or file_sha256(project / layout) != sha:
            parser.error(f"Source evidence project/frozen {suite} layout mismatch")
    config = (project / "project.godot").read_text(encoding="utf-8")
    if 'config/use_custom_user_dir=true' not in config or f'config/custom_user_dir_name="{USER_DIR_NAME}"' not in config:
        parser.error("Unrecognized user directory contract; refusing profile assumptions")
    runtime_root = exe.parent if args.standalone else project
    profiles_root = (Path(os.environ["APPDATA"]) / USER_DIR_NAME / "profiles_v3").resolve()
    lock = LanPortLock()
    try: lock.acquire()
    except (LanRunBusy, OSError) as error:
        print(f"REFUSED: {error}; no game started", file=sys.stderr)
        return 3
    output = runtime_root / "artifacts/v3/app-entry" / datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    report = {"schema_version": 1, "started_utc": utc_now(), "standalone": args.standalone,
              "runtime_cwd": str(runtime_root), "source_path_passed": not args.standalone,
              "expected_layout_shas": {suite: expected_shas[suite] for suite in sorted(needed)},
              "script_override_passed": False, "cases": [], "passed": False,
              "scope": "negative process startup and own QA profile immutability; no gameplay or ENet success claim",
              "socket_evidence_limit": "Rejection precedes Session creation/ENet calls, with no ready markers; no OS-level transient socket trace is collected."}
    try:
        if output.resolve() != output: raise RuntimeError("Evidence root redirects")
        output.mkdir(parents=True, exist_ok=False)
        report["exe_sha256_before"] = file_sha256(exe)
        report["inputs_before"] = source_hashes(project)
        report["lock"] = {"path": str(lock.path), "backend": lock.backend, "port": 26742, "pid": os.getpid()}
        kind = "package_main" if args.standalone else "source_main"
        for index, name in enumerate(names):
            run_id = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
            case_dir = output / f"{index+1:02d}-{name}"
            suite = suite_for(name)
            spec = case_spec(name, run_id, runtime_root, case_dir, expected_shas[suite], kind, time.time())
            result = run_case(spec, exe, project, runtime_root, case_dir, profiles_root, args.standalone, 20.0)
            report["cases"].append(result)
            write_json(output / "summary.json", report)
        report["exe_sha256_after"] = file_sha256(exe)
        report["inputs_after"] = source_hashes(project)
        report["inputs_unchanged"] = report["inputs_before"] == report["inputs_after"] and report["exe_sha256_before"] == report["exe_sha256_after"]
        report["passed"] = len(report["cases"]) == len(names) and all(c["passed"] for c in report["cases"]) and report["inputs_unchanged"]
    except BaseException as error:
        report["error"] = f"{type(error).__name__}: {error}"
        if output.is_dir(): (output / "orchestration-error.log").write_text(traceback.format_exc(), encoding="utf-8")
    finally:
        report["finished_utc"] = utc_now()
        if output.is_dir(): write_json(output / "summary.json", report)
        lock.release()
    print(json.dumps({"passed": report["passed"], "cases": len(report["cases"]), "output": str(output)}, ensure_ascii=False), flush=True)
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
