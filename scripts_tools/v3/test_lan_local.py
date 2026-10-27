#!/usr/bin/env python3
"""Repeatable headless ENet loopback smoke test, not a two-computer LAN test.

Run from any directory:
    python scripts_tools/v3/test_lan_local.py
Optional:
    --godot PATH_TO_GODOT --project PATH_TO_PROJECT
Exported executable, launched from its own directory without --path:
    --standalone --godot PATH_TO_EXPORTED_EXE --project PATH_TO_EVIDENCE_PROJECT

Evidence is written under artifacts/v3/network/<unique timestamp>/.
Standalone --project must be a new empty directory inside managed STATE/evidence.
The host runs for at least 24 seconds and waits for both guest departures (60s
deadline). Each guest observes 8 seconds after authoritative world readiness.
Only processes started here are stopped
on timeout. Existing player profiles and earlier evidence are never removed.
Source and standalone runs share a machine-wide Windows file lock for UDP 26742.
A competing validator exits with code 3 before starting any game process. The
operating system releases the lock when its owning process exits, even abnormally.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import errno
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import traceback
import dev
from storage_policy import plain_path

HOST_SECONDS = 24
GUEST_SECONDS = 8
USER_DIR_NAME = "LowAltitudeTwinPulseV3"
SNAPSHOT_BUDGET_BYTES = 1150
LAN_PORT = 26742
PEER_LOG_LIMIT_BYTES = 8 * 1024 ** 2


class LanRunBusy(RuntimeError):
    """Another validator owns the shared loopback test port."""


class LanPortLock:
    """OS-owned, nonblocking file lock, independent of project/export directory.

    Do not delete the lock file: a persistent file is harmless once unlocked,
    whereas unlinking it can let concurrent processes lock different files.
    PID/JSON contents are diagnostic only; ownership comes from the OS lock.
    """

    def __init__(self) -> None:
        if os.name == "nt":
            root = Path(os.environ.get("PROGRAMDATA", r"C:\ProgramData"))
            self.backend = "msvcrt.locking/LK_NBLCK"
        else:
            root = Path(tempfile.gettempdir())
            self.backend = "fcntl.flock/LOCK_NB"
        self.path = root / "LowAltitudeTwinPulseV3" / "qa-locks" / f"enet-{LAN_PORT}.lock"
        self.stream = None
        self.acquired_utc = None

    def acquire(self) -> None:
        if self.stream is not None:
            raise RuntimeError("LAN port lock is already acquired by this instance")
        self.path.parent.mkdir(parents=True, exist_ok=True)
        flags = os.O_RDWR | os.O_CREAT | getattr(os, "O_BINARY", 0)
        descriptor = os.open(self.path, flags, 0o600)
        try:
            os.set_inheritable(descriptor, False)
            stream = os.fdopen(descriptor, "r+b", buffering=0)
        except BaseException:
            os.close(descriptor)
            raise
        try:
            stream.seek(0)
            try:
                if os.name == "nt":
                    import msvcrt
                    # Windows permits locking beyond EOF, so initialization does
                    # not need a separate racing write before the lock is held.
                    msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
                else:
                    import fcntl
                    fcntl.flock(stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            except OSError as exc:
                if exc.errno in (errno.EACCES, errno.EAGAIN, errno.EDEADLK):
                    raise LanRunBusy(
                        f"Another LAN validation run already owns UDP {LAN_PORT}. "
                        "Source and standalone checks must run serially to avoid "
                        f"connecting to each other's host. Lock: {self.path}"
                    ) from exc
                raise
            self.acquired_utc = utc_now()
            metadata = {
                "pid": os.getpid(), "acquired_utc": self.acquired_utc,
                "port": LAN_PORT, "backend": self.backend,
            }
            stream.seek(0)
            stream.write(b"\0" + json.dumps(metadata).encode("utf-8") + b"\n")
            stream.truncate()
            stream.flush()
        except BaseException:
            stream.close()  # Also releases an acquired OS lock if metadata failed.
            raise
        self.stream = stream

    def release(self) -> None:
        if self.stream is None:
            return
        stream, self.stream = self.stream, None
        try:
            stream.seek(0)
            if os.name == "nt":
                import msvcrt
                msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                import fcntl
                fcntl.flock(stream.fileno(), fcntl.LOCK_UN)
        finally:
            stream.close()


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def write_json(path: Path, data: object) -> None:
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def file_sha256(path: Path) -> str:
    return dev.file_sha256(path)


def process_options() -> dict:
    options = {"stdin": subprocess.DEVNULL, "shell": False}
    if os.name == "nt":
        options["creationflags"] = subprocess.CREATE_NO_WINDOW
        startup = subprocess.STARTUPINFO()
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = subprocess.SW_HIDE
        options["startupinfo"] = startup
    return options


def source_fingerprints(project: Path) -> dict:
    paths = {"project.godot", "scripts_tools/v3/test_lan_local.py"}
    for pattern in ("scripts/v3/**/*.gd", "scripts/v2/*.gd", "scenes/v3/**/*.tscn",
                    "data/v3/**/*.json", "assets/v3/**/*.glb"):
        paths.update(path.relative_to(project).as_posix() for path in project.glob(pattern))
    return {
        name: hashlib.sha256((project / name).read_bytes()).hexdigest()
        for name in sorted(paths) if (project / name).is_file()
    }


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--godot", type=Path, default=None)
    parser.add_argument("--standalone", action="store_true",
                        help="Run an exported executable from its directory, without --path.")
    args = parser.parse_args()
    project = args.project.resolve()
    if args.standalone and args.godot is None:
        parser.error("--standalone requires an explicit --godot exported executable path")
    godot = (args.godot or (Path(os.environ.get("LOCALAPPDATA", "")) /
             "Programs/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe")).resolve()
    if not project.is_dir():
        parser.error(f"Evidence project directory not found: {project}")
    if not args.standalone and not (project / "project.godot").is_file():
        parser.error(f"Missing project.godot in {project}")
    if not godot.is_file():
        parser.error(f"Godot executable not found: {godot}")
    if args.standalone:
        project = plain_path(args.project, existing=True)
        managed = dev.POLICY.path("evidence")
        if project == managed or not project.is_relative_to(managed) or any(project.iterdir()):
            parser.error("standalone --project must be a new empty managed evidence directory")
    runtime_cwd = godot.parent if args.standalone else project

    run_lock = LanPortLock()
    try:
        run_lock.acquire()
    except LanRunBusy as exc:
        print(f"REFUSED: {exc} No Godot process was started.", file=sys.stderr, flush=True)
        return 3
    except OSError as exc:
        # Never fall back to a per-project lock or proceed without protection.
        print(f"REFUSED: cannot acquire shared LAN validation lock {run_lock.path}: "
              f"{exc}. No Godot process was started.", file=sys.stderr, flush=True)
        return 2
    try:
        return run_locked(args, project, godot, runtime_cwd, run_lock)
    finally:
        # Includes version probing, launch, natural exit/cleanup, and evidence.
        run_lock.release()


def run_locked(args: argparse.Namespace, project: Path, godot: Path,
               runtime_cwd: Path, run_lock: LanPortLock) -> int:
    if run_lock.stream is None:
        raise RuntimeError("Cannot start LAN validation without its port lock")

    dev.POLICY.preflight_qa(128 * 1024 ** 2)
    dev.POLICY.preflight("evidence", 64 * 1024 ** 2)
    dev.LOG_LIMIT = PEER_LOG_LIMIT_BYTES  # This LAN controller process only; parent stays64MiB.
    run_id = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    evidence = project / "artifacts" / "v3" / "network" / run_id
    evidence.mkdir(parents=True, exist_ok=False)
    host_profile = f"qa_lan_host_{run_id}"
    guest_profile = f"qa_lan_guest_{run_id}"
    summary = {
        "schema_version": 1,
        "run_id": run_id,
        "started_utc": utc_now(),
        "scope": "same-computer ENet loopback at 127.0.0.1; not two-computer LAN",
        "limitations": [
            "No second computer, physical LAN, router or firewall traversal was tested.",
            "Headless execution is not visual, GPU-performance or human-playtest evidence.",
        ],
        "project": str(project),
        "godot": str(godot),
        "standalone": args.standalone,
        "runtime_cwd": str(runtime_cwd),
        "runtime_passes_project_path": not args.standalone,
        "exclusive_run_lock": {
            "path": str(run_lock.path), "port": LAN_PORT,
            "pid": os.getpid(), "backend": run_lock.backend,
            "acquired_utc": run_lock.acquired_utc,
        },
        "executable_sha256": file_sha256(godot),
        "executable_bytes": godot.stat().st_size,
        "standalone_directory_files_before": [entry.name for entry in runtime_cwd.iterdir()]
        if args.standalone else None,
        "host_profile": host_profile,
        "guest_profile": guest_profile,
        "guest_profile_reused": True,
        "simple_scene_snapshot_budget_bytes": SNAPSHOT_BUDGET_BYTES,
        "peer_log_limit_bytes": PEER_LOG_LIMIT_BYTES,
        "source_sha256_before": source_fingerprints(project),
        "processes": {},
        "checks": [],
        "orchestration_error": None,
        "passed": False,
    }
    running: dict[str, tuple[subprocess.Popen, object, float]] = {}
    pipes = {}

    def logs_failed() -> bool:
        return any(pipe.stop.is_set() for pipe in pipes.values()) or any(
            record.get("log_error") for record in summary["processes"].values())

    def close_log(record, log, pipe) -> None:
        try:
            pipe.finish()  # Existing helper joins the reader for at most5s.
        except BaseException as exc:
            record["log_error"] = f"{type(exc).__name__}: {exc}"[:512]
        finally:
            record["log_limit_bytes"] = PEER_LOG_LIMIT_BYTES
            record["log_payload_bytes"] = pipe.written
            record["output_limit_exceeded"] = pipe.limited
            record["log_error"] = record.get("log_error") or pipe.error
            record["log_reader_finished"] = not pipe.thread.is_alive()
            log.close()

    def launch(label: str, mode: str, profile: str, seconds: int) -> None:
        if logs_failed():
            raise RuntimeError("Peer log limit/capture failed; further peer launch refused")
        report_path = evidence / f"{label}.json"
        log_path = evidence / f"{label}.log"
        command = [str(godot), "--headless"]
        if not args.standalone:
            command.extend(["--path", str(project)])
        command.extend([
            "--",
            f"--qa-profile={profile}", f"--qa-network={mode}",
            f"--qa-duration={seconds}", f"--qa-report={report_path}",
        ])
        log = log_path.open("xb", buffering=0)
        record = {
            "mode": mode, "profile": profile, "duration_requested": seconds,
            "command": command, "log": log_path.name, "report": report_path.name,
            "cwd": str(runtime_cwd),
            "started_utc": utc_now(), "exit_code": None, "timed_out": False,
            "forced_stop": False, "report_data": None, "output_stopped": False,
            "log_error": None, "output_limit_exceeded": False, "log_reader_finished": False,
        }
        summary["processes"][label] = record
        pipe = None
        try:
            pipe = dev._BoundedLogPipe(log)
            process = subprocess.Popen(
                command, cwd=runtime_cwd, stdout=pipe.writer, stderr=subprocess.STDOUT,
                **process_options(),
            )
        except BaseException:
            if pipe is not None:
                close_log(record, log, pipe)
            else:
                log.close()
            raise
        record["pid"] = process.pid
        running[label] = (process, log, time.monotonic())
        pipes[label] = pipe
        pipe.writer.close()  # Child owns the only inherited write handles.
        write_json(evidence / "summary.json", summary)
        print(f"START {label} profile={profile}", flush=True)

    def finish(label: str, timeout: float) -> None:
        process, log, started = running[label]
        record = summary["processes"][label]
        # Each timeout is an absolute process lifetime, and serial client waits
        # cannot extend the host beyond the suite's 75s wall-clock boundary.
        deadline = min(started + timeout, running["host"][2] + 75.0)
        remaining = max(0.0, deadline - time.monotonic())
        record["absolute_process_limit_seconds"] = timeout
        record["remaining_wait_seconds"] = round(remaining, 3)
        try:
            while process.poll() is None:
                record["output_stopped"] = logs_failed()
                remaining = max(0.0, deadline - time.monotonic())
                if record["output_stopped"] or remaining == 0:
                    raise subprocess.TimeoutExpired(process.args, timeout)
                try:
                    process.wait(timeout=min(0.1, remaining))
                except subprocess.TimeoutExpired:
                    pass
        except subprocess.TimeoutExpired:
            record["timed_out"] = not record["output_stopped"]
            record["forced_stop"] = True
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
        finally:
            record["exit_code"] = process.poll()
            record["elapsed_wall_seconds"] = round(time.monotonic() - started, 3)
            record["finished_utc"] = utc_now()
            close_log(record, log, pipes[label])
        print(f"EXIT {label} code={record['exit_code']} timeout={record['timed_out']}", flush=True)

    def check(name: str, passed: bool, actual: object, expected: object) -> None:
        summary["checks"].append(
            {"name": name, "passed": bool(passed), "actual": actual, "expected": expected}
        )

    def wait_world_ready(label: str, timeout: float = 30.0) -> None:
        deadline = time.monotonic() + timeout
        process = running[label][0]
        log_path = evidence / summary["processes"][label]["log"]
        while time.monotonic() < deadline:
            if logs_failed():
                raise RuntimeError("Peer log limit/capture failed during world readiness")
            if process.poll() is not None:
                raise RuntimeError(f"{label} exited before world readiness")
            if "V3_QA_NETWORK_READY " in log_path.read_text(encoding="utf-8", errors="replace"):
                summary["processes"][label]["ready_observed_utc"] = utc_now()
                return
            time.sleep(0.05)
        raise TimeoutError(f"{label} world readiness exceeded {timeout}s")

    try:
        version = subprocess.run(
            [str(godot), "--version"], cwd=runtime_cwd, capture_output=True,
            timeout=15, **process_options(),
        )
        summary["godot_version"] = version.stdout.decode("utf-8", errors="replace").strip()
        summary["godot_version_exit_code"] = version.returncode
        launch("host", "host", host_profile, HOST_SECONDS)
        wait_world_ready("host")
        if running["host"][0].poll() is not None:
            raise RuntimeError("Host exited before the first guest launch.")
        launch("guest_first", "guest", guest_profile, GUEST_SECONDS)
        finish("guest_first", 45)
        first = summary["processes"]["guest_first"]
        if first["timed_out"] or first["forced_stop"] or first["exit_code"] != 0 or logs_failed():
            raise RuntimeError("First guest did not exit naturally with code 0; reconnect skipped.")
        if running["host"][0].poll() is not None:
            raise RuntimeError("Host exited before same-profile reconnect.")
        launch("guest_reconnect", "guest", guest_profile, GUEST_SECONDS)
        finish("guest_reconnect", 45)
        finish("host", 75)
    except BaseException as exc:
        summary["orchestration_error"] = f"{type(exc).__name__}: {exc}"
        (evidence / "orchestration_error.log").write_text(traceback.format_exc(), encoding="utf-8")
    finally:
        for label, (process, log, _) in running.items():
            if not log.closed:
                # Retain the host's own QA report where possible; a failed guest
                # must not make us stop the host before its bounded peer deadline.
                finish(label, 75 if label == "host" else 5)

    for label in ("host", "guest_first", "guest_reconnect"):
        record = summary["processes"].get(label)
        check(f"{label}.started", record is not None, record is not None, True)
        if record is None:
            continue
        check(f"{label}.natural_exit", record["exit_code"] == 0 and not record["forced_stop"],
              {"exit_code": record["exit_code"], "forced_stop": record["forced_stop"]},
              {"exit_code": 0, "forced_stop": False})
        check(f"{label}.bounded_log",
              not record["output_limit_exceeded"] and not record["log_error"] and record["log_reader_finished"],
              {key: record.get(key) for key in ("log_limit_bytes", "log_payload_bytes",
               "output_limit_exceeded", "log_error", "log_reader_finished")},
              "capture completed within8MiB without overflow/pipe/reader error")
        log_text = (evidence / record["log"]).read_text(encoding="utf-8", errors="replace")
        error_lines = [line for line in log_text.splitlines()
                       if line.startswith(("ERROR:", "SCRIPT ERROR:"))]
        check(f"{label}.no_engine_errors", not error_lines, error_lines, [])
        record["warning_lines"] = [line for line in log_text.splitlines()
                                   if "warning:" in line.lower()]
        mtu_warnings = [line for line in record["warning_lines"] if "mtu" in line.lower()]
        check(f"{label}.no_mtu_warnings", not mtu_warnings, mtu_warnings, [])
        check(f"{label}.profile_in_ready_log",
              f"profile={record['profile']}" in log_text,
              f"profile={record['profile']}" in log_text, True)
        report_path = evidence / record["report"]
        try:
            report = json.loads(report_path.read_text(encoding="utf-8"))
            if not isinstance(report, dict):
                raise ValueError("QA report must be an object")
            record["report_data"] = report
            check(f"{label}.report_readable", True, True, True)
        except (OSError, ValueError) as exc:
            check(f"{label}.report_readable", False, str(exc), "valid JSON object")
            continue
        check(f"{label}.scripted", report.get("qa_scripted") is True,
              report.get("qa_scripted"), True)
        observation = report.get("observation", {})
        check(f"{label}.complete_ready_observation",
              observation.get("started_after_ready") is True
              and observation.get("stop_reason") == "observation_complete"
              and report.get("seconds", -1) >= record["duration_requested"]
              and 5 <= observation.get("action_seconds", -1) < report.get("seconds", -1)
              and report.get("seconds", -1) - observation.get("action_seconds", -1) >= 2.0
              and (record["mode"] != "guest" or observation.get("first_sequence", -1) >= 0),
              observation, "ready -> one action after 5s -> full observation, valid guest first sequence")
        check(f"{label}.mode", report.get("mode") == record["mode"],
              report.get("mode"), record["mode"])
        user_dir = str(report.get("user_dir", "")).replace("\\", "/").rstrip("/")
        check(f"{label}.v3_user_dir", user_dir.split("/")[-1] == USER_DIR_NAME,
              user_dir, f"directory ending /{USER_DIR_NAME}")
        stats = report.get("stats", {})
        ecology = report.get("ecology", {})
        check(f"{label}.ecology_visible", ecology.get("visible_actors") == 3,
              ecology.get("visible_actors"), 3)
        if record["mode"] == "guest":
            check(f"{label}.ecology_authority_received", ecology.get("applied_serial", -1) > 0,
                  ecology.get("applied_serial"), "> 0")
            check(f"{label}.ecology_not_locally_simulated", ecology.get("simulated_seconds") == 0,
                  ecology.get("simulated_seconds"), 0)
        if not isinstance(stats, dict):
            stats = {}
        if label == "host":
            for key in ("guest_joins", "guest_leaves"):
                check(f"host.{key}", stats.get(key) == 2, stats.get(key), 2)
            abilities = stats.get("abilities")
            check("host.abilities", isinstance(abilities, (int, float)) and abilities >= 3,
                  abilities, ">= 3")
            check("host.players_after_disconnect", report.get("players") == 1,
                  report.get("players"), 1)
            network = report.get("network", {})
            if not isinstance(network, dict):
                network = {}
            maximum_bytes = network.get("max_snapshot_bytes")
            check("host.snapshot_budget",
                  type(maximum_bytes) is int and 0 < maximum_bytes <= SNAPSHOT_BUDGET_BYTES,
                  maximum_bytes, f"0 < bytes <= {SNAPSHOT_BUDGET_BYTES}")
            fallbacks = network.get("reliable_fallbacks")
            check("host.no_reliable_fallbacks",
                  type(fallbacks) is int and fallbacks == 0, fallbacks, 0)
        else:
            check(f"{label}.players", report.get("players") == 2, report.get("players"), 2)
            snapshots = stats.get("snapshots")
            check(f"{label}.snapshots",
                  isinstance(snapshots, (int, float)) and snapshots > 40,
                  snapshots, "> 40")

    check("guest.same_profile_reconnect",
          all(summary["processes"].get(label, {}).get("profile") == guest_profile
              for label in ("guest_first", "guest_reconnect")),
          [summary["processes"].get(label, {}).get("profile")
           for label in ("guest_first", "guest_reconnect")],
          [guest_profile, guest_profile])
    summary["source_sha256_after"] = source_fingerprints(project)
    summary["executable_sha256_after"] = file_sha256(godot)
    summary["executable_changed_during_run"] = (
        summary["executable_sha256"] != summary["executable_sha256_after"]
    )
    summary["sources_changed_during_run"] = (
        summary["source_sha256_before"] != summary["source_sha256_after"]
    )
    summary["finished_utc"] = utc_now()
    summary["passed"] = summary["orchestration_error"] is None and all(
        item["passed"] for item in summary["checks"]
    )
    write_json(evidence / "summary.json", summary)
    failures = [item for item in summary["checks"] if not item["passed"]]
    print(json.dumps({
        "passed": summary["passed"], "evidence": str(evidence),
        "failed_checks": failures, "orchestration_error": summary["orchestration_error"],
        "sources_changed_during_run": summary["sources_changed_during_run"],
        "standalone": summary["standalone"],
        "executable_sha256": summary["executable_sha256"],
        "scope": summary["scope"],
    }, ensure_ascii=False, indent=2), flush=True)
    return 0 if summary["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())

