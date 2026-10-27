#!/usr/bin/env python3
"""Controlled Underdeck ENet loopback using one shared source/package Node driver; not two-computer LAN.

Default is preparation only and starts no Godot process. After shared-code/layout freeze:
  python scripts_tools/v3/test_underdeck_lan.py --run --expected-underdeck-sha <frozen SHA256>
Add --source-main to exercise the source application router, or --standalone
--godot <exported EXE> for the PCK normal entry (no --script and no --path).
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
# This exact OS-owned lock also excludes the existing source/standalone LAN suite.
from test_lan_local import (LanPortLock, LanRunBusy, file_sha256, process_options,
                            source_fingerprints, utc_now)

FRONT = "I1:underdeck_grille"
LATCH = "I1:underdeck_latch"
DISCOVERY = "opening:underdeck_worker_bypass"
ENTRY = "I1:underdeck:enter"
RELEASE = "I1:underdeck:release"
TRAVERSE = "I1:underdeck:traverse"
MODEL = "data/v3/terrain/i1_underdeck_layout.json"
PEER_SCRIPT = "res://scripts/v3/qa/twin_underdeck_lan_peer.gd"
EXPECTED_SCENARIOS = 3


def atomic_json(path: Path, value: object) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    # Godot's short FileAccess read can deny replacement on Windows. Keep the
    # previous complete publication and retry the same bytes within a bounded
    # interval; never truncate the live controller/command file as a fallback.
    deadline = time.monotonic() + 0.5
    while True:
        try:
            os.replace(temporary, path)
            return
        except PermissionError:
            if time.monotonic() >= deadline:
                raise
            time.sleep(0.01)


def fingerprints(project: Path) -> dict:
    result = source_fingerprints(project)
    extras = [project / "scripts_tools/v3/test_underdeck_lan.py"]
    extras += [p for p in (project / "assets/v3").rglob("*")
               if p.is_file() and p.suffix not in (".import", ".uid")]
    for path in extras:
        result[path.relative_to(project).as_posix()] = file_sha256(path)
    return dict(sorted(result.items()))


def peer_command(executable: Path, project: Path, entry_kind: str, user_args: list[str]) -> list[str]:
    """Pure command construction; package mode never sees a source/script override."""
    command = [str(executable), "--headless"]
    if entry_kind == "source_script":
        command += ["--path", str(project), "--script", PEER_SCRIPT]
    elif entry_kind == "source_main":
        command += ["--path", str(project)]
    elif entry_kind != "package_main":
        raise ValueError("Unknown QA entry kind")
    return command + ["--"] + user_args


class Run:
    def __init__(self, project: Path, godot: Path, sha: str, lock: LanPortLock, entry_kind: str = "source_script") -> None:
        self.project, self.godot, self.sha, self.lock = project, godot, sha, lock
        if entry_kind not in ("source_script", "source_main", "package_main"):
            raise ValueError("Invalid entry kind")
        self.entry_kind = entry_kind
        self.runtime_cwd = godot.parent if entry_kind == "package_main" else project
        self.run_id = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
        self.evidence = self.runtime_cwd / "artifacts/v3/network/underdeck" / self.run_id
        if self.evidence.resolve() != self.evidence:
            raise RuntimeError("Evidence path must not redirect outside the exact runtime run directory")
        self.evidence.mkdir(parents=True, exist_ok=False)
        self.profiles = {"host": f"qa_underdeck_lan_host_{self.run_id}",
                         "guest": f"qa_underdeck_lan_guest_{self.run_id}"}
        self.processes: dict[str, tuple[subprocess.Popen, object]] = {}
        self.command_sequences: dict[str, int] = {}
        self.summary = {
            "schema_version": 1, "run_id": self.run_id, "started_utc": utc_now(),
            "scope": "same-computer two-process real ENet loopback, scripted poses; not physical two-computer LAN",
            "limitations": ["No human play, GPU, performance, remote-PC/router/firewall acceptance; no loss or latency injection. Mid-signal disconnect and branch-reset order are covered by the separate injected Session test, not this ENet suite.",
                            "Previous 23 goals use explicit saved Director fixtures; current four goals are observed from actual actions/motion.",
                            "QA freezes bodies, places initial poses, directly pauses, and moves guest body with real host-side move_and_collide; not a control-feel or pause-vote test."],
            "project": str(project), "godot": str(godot), "underdeck_sha256": sha,
            "qa_suite": "underdeck-lan", "entry_kind": entry_kind,
            "runtime_cwd": str(self.runtime_cwd), "source_path_passed": entry_kind != "package_main",
            "script_override_passed": entry_kind == "source_script",
            "executable_sha256_before": file_sha256(godot), "source_sha256_before": fingerprints(project),
            "lock": {"path": str(lock.path), "port": 26742, "pid": os.getpid(), "backend": lock.backend},
            "profiles": self.profiles, "scenarios": [], "checks": [], "processes": {}, "passed": False,
        }
        self.heartbeat()

    def heartbeat(self) -> None:
        atomic_json(self.evidence / "controller.json", {
            "run_id": self.run_id, "pid": os.getpid(), "lock_held": self.lock.stream is not None,
            "heartbeat_unix": time.time(), "underdeck_sha256": self.sha,
            "qa_suite": "underdeck-lan", "entry_kind": self.entry_kind,
            "evidence": self.evidence.as_posix(), "profiles": self.profiles,
        })

    def read(self, label: str) -> dict:
        try:
            value = json.loads((self.evidence / f"{label}-state.json").read_text(encoding="utf-8"))
            return value if isinstance(value, dict) else {}
        except (OSError, ValueError):
            return {}

    def matches_driver_state(self, label: str, state: dict) -> bool:
        role = "host" if label == "host" else "guest"
        return (state.get("qa_suite") == "underdeck-lan"
                and state.get("entry_kind") == self.entry_kind
                and state.get("resource_layout_sha256") == self.sha
                and state.get("run_id") == self.run_id
                and state.get("label") == label and state.get("role") == role
                and state.get("profile") == self.profiles[role])

    def wait(self, label: str, predicate, description: str, timeout: float = 15) -> dict:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            self.heartbeat()
            state = self.read(label)
            if state and not self.matches_driver_state(label, state):
                raise RuntimeError(f"{label}: specialized QA entry/runtime resource handshake mismatch")
            if state.get("errors"):
                raise RuntimeError(f"{label} driver failed: {state['errors']}")
            if state and predicate(state):
                return state
            if self.processes[label][0].poll() is not None:
                raise RuntimeError(f"{label} exited before {description}")
            time.sleep(0.05)
        raise TimeoutError(f"{label}: {description}; latest state retained in evidence")

    def settle(self, seconds: float) -> None:
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            self.heartbeat()
            time.sleep(0.05)

    def launch(self, label: str, role: str, reconnect: bool = False) -> None:
        if self.lock.stream is None:
            raise RuntimeError("Cannot spawn a game before shared port lock ownership")
        user_args = ["--qa-suite=underdeck-lan", f"--qa-profile={self.profiles[role]}",
                     f"--qa-underdeck-role={role}", f"--qa-underdeck-label={label}",
                     f"--qa-underdeck-run={self.run_id}", f"--qa-underdeck-evidence={self.evidence}",
                     f"--qa-underdeck-sha={self.sha}"]
        if reconnect:
            user_args.append("--qa-underdeck-reconnect")
        command = peer_command(self.godot, self.project, self.entry_kind, user_args)
        log = (self.evidence / f"{label}.log").open("wb")
        try:
            process = subprocess.Popen(command, cwd=self.runtime_cwd, stdout=log, stderr=subprocess.STDOUT,
                                       **process_options())
        except BaseException:
            log.close()
            raise
        self.processes[label] = process, log
        self.summary["processes"][label] = {"pid": process.pid, "command": command, "started_utc": utc_now(),
                                              "profile": self.profiles[role], "forced_stop": False}
        print(f"START {label} pid={process.pid}", flush=True)

    def request(self, label: str, verb: str, args: dict | None = None) -> dict:
        sequence = self.command_sequences.get(label, 0) + 1
        self.command_sequences[label] = sequence
        atomic_json(self.evidence / f"{label}-command.json", {
            "run_id": self.run_id, "sequence": sequence, "verb": verb, "args": args or {},
        })
        state = self.wait(label, lambda s: s.get("ack", 0) >= sequence, f"command {verb}")
        if not state.get("result", {}).get("ok"):
            raise RuntimeError(f"{label} command {verb}: {state.get('result')}")
        return state

    def action(self, label: str, ability: str, target: str = LATCH) -> dict:
        return self.request(label, "action", {"verb": "ability", "payload": {"ability": ability, "target_id": target}})

    def check(self, name: str, passed: bool, actual: object = None) -> None:
        self.summary["checks"].append({"name": name, "passed": bool(passed), "actual": actual})
        if not passed:
            raise AssertionError(f"{name}: {actual!r}")

    def scenario(self, name: str) -> None:
        self.summary["scenarios"].append({"name": name, "started_utc": utc_now(), "completed": False})
        print(f"CASE {name}", flush=True)

    def complete(self) -> None:
        self.summary["scenarios"][-1]["completed"] = True
        self.summary["scenarios"][-1]["finished_utc"] = utc_now()
        atomic_json(self.evidence / "summary.json", self.summary)

    def natural_exit(self, label: str, timeout: float = 12) -> None:
        deadline = time.monotonic() + timeout
        process, log = self.processes[label]
        while process.poll() is None and time.monotonic() < deadline:
            self.heartbeat()
            time.sleep(0.05)
        self.check(f"{label} natural exit", process.poll() == 0, process.poll())
        if not log.closed:
            log.close()

    @staticmethod
    def valid_probe(probe: dict, authority: bool) -> bool:
        return (probe.get("ready") is True and probe.get("authority") is authority
                and probe.get("maximum_pose_error", 999) < 0.001
                and probe.get("target_error", 999) < 0.001)

    def save_case(self, name: str, **states: dict) -> None:
        atomic_json(self.evidence / (name + ".json"), states)

    def exercise(self) -> None:
        self.scenario("1 natural partial opening, real host force field and guest physical pose")
        self.launch("host", "host")
        host = self.wait("host", lambda s: s.get("active") and s.get("region") == "I1"
                         and s.get("story_ready"), "host predecessor fixture ready")
        self.check("explicit fixture contains exactly previous23 goals", len(host["completed"]) == 23)
        self.request("host", "read_plan")
        self.launch("guest_first", "guest")
        guest = self.wait("guest_first", lambda s: len(s.get("players", {})) == 2
                          and s.get("applied_count", 0) > 2 and s.get("story_ready"), "real guest joined")
        self.check("guest uses actual wider HX02", guest["players"][str(guest["peer_id"])]["airframe"] == "hx02")
        self.request("host", "arm_hold")
        host = self.wait("host", lambda s: bool(s.get("hold_observation")) and not s.get("hold_armed"),
                         "natural partial opening held by real ability", timeout=12)
        held = host["hold_observation"]
        self.check("host ability accepted during natural partial gate phase", held.get("accepted")
                   and 0.35 <= held.get("fraction_before", 0) < 0.75, held)
        fraction = host["probe"]["state"]["front_fraction"]
        guest = self.wait("guest_first", lambda s: s.get("probe", {}).get("state", {}).get("front_pinned")
                          and abs(s["probe"]["state"]["front_fraction"] - fraction) < 0.001,
                          "guest receives held physical door")
        self.check("host physical door and ability target aligned", self.valid_probe(host["probe"], True), host["probe"])
        self.check("guest packet application aligns visual physics target same frame",
                   self.valid_probe(guest.get("latest_probe", {}).get("probe", {}), False), guest.get("latest_probe"))
        self.check("guest does not locally advance received mechanism", guest.get("guest_ticks", 0) > 10
                   and guest.get("guest_local_mutations") == 0, {"ticks":guest.get("guest_ticks"),"mutations":guest.get("guest_local_mutations")})
        self.save_case("case1-partial-held", host=host, guest=guest)
        self.complete()

        self.scenario("2 real guest blink and echo, observed north exit, durable discovery and receipt")
        self.request("host", "place_guest", {"position":[-24.5,3.55,-23.5]})
        peer_id = str(guest["peer_id"])
        self.wait("guest_first", lambda s: abs(s["players"][peer_id]["position"][0]+24.5) < 0.15,
                  "guest receives explicit outside starting pose")
        self.request("guest_first", "action", {"payload":{"ability":"blink","target_id":"","point":[-30.5,3.55,-23.5]}})
        host = self.wait("host", lambda s: ENTRY in s.get("completed", []), "guest RPC blink becomes actual entry")
        self.check("actual blink earns side route with no client fact", host["choices"].get(ENTRY) == "side_blink", host.get("choices"))
        self.request("host", "move_guest", {"points":[[-35,3.55,-23.5],[-35,2.05,-23.5]]})
        moved = self.wait("host", lambda s: not s.get("motion_active") and bool(s.get("motion_result")), "actual turning chamber motion")
        self.check("physical turning and descent clear", moved["motion_result"].get("ok"), moved["motion_result"])
        self.wait("host", lambda s: s["players"][peer_id]["cooldown"] <= 0, "real blink cooldown expires")
        self.request("guest_first", "action", {"payload":{"ability":"echo","target_id":LATCH}})
        released = self.wait("host", lambda s: RELEASE in s.get("completed", []) and
                             s.get("probe", {}).get("state", {}).get("rear_fraction", 0) >= 0.999,
                             "actual continuous echo releases and moves rear gate")
        self.check("release does not itself grant transit discovery", TRAVERSE not in released["completed"]
                   and DISCOVERY not in released["personal"]["discoveries"])
        self.request("host", "move_guest", {"points":[[-35,2.05,-37.2]]})
        host = self.wait("host", lambda s: TRAVERSE in s.get("completed", []) and not s.get("motion_active"),
                         "real north portal crossing commits", timeout=10)
        self.check("actual north motion reached exterior", host["motion_result"].get("ok"), host["motion_result"])
        self.check("host durable unique discovery and27goals", host["personal"]["discoveries"].count(DISCOVERY) == 1
                   and len(host["completed"]) == 27)
        guest = self.wait("guest_first", lambda s: s.get("personal", {}).get("discoveries", []).count(DISCOVERY) == 1
                          and TRAVERSE in s.get("completed", []), "real reliable story and receipt arrive")
        self.wait("host", lambda s: s.get("pending_receipts") == 0, "real durable receipt ACK clears host outbox")
        self.check("guest still has no local mechanism mutations", guest.get("guest_local_mutations") == 0)
        self.save_case("case2-earned-transit", host=host, guest=guest)
        self.complete()

        self.scenario("3 completed paused reconnect, first-packet collision and duplicate receipt")
        host = self.request("host", "pause", {"value":True})
        guest = self.wait("guest_first", lambda s: s.get("paused") and s.get("latest_probe", {}).get("paused"), "guest pauses")
        self.check("paused host has fully open actual panels", host["probe"]["state"]["front_fraction"] == 1
                   and host["probe"]["state"]["rear_fraction"] == 1 and self.valid_probe(host["probe"], True))
        initial_identity = guest["profile_id"]
        count_before = guest["guest_received_count"]
        self.request("guest_first", "shutdown")
        self.natural_exit("guest_first")
        self.wait("host", lambda s: len(s.get("players", {})) == 1, "host observes disconnect")
        self.launch("guest_reconnect", "guest", reconnect=True)
        resumed = self.wait("guest_reconnect", lambda s: bool(s.get("first_paused_snapshot"))
                            and s.get("story_ready") and TRAVERSE in s.get("completed", []), "first paused reconnect snapshot and story")
        first = resumed["first_snapshot"]
        self.check("same personal identity reconnects", resumed["profile_id"] == initial_identity)
        self.check("first valid packet already paused and fully open", first.get("paused") is True
                   and first["packet_mechanism"].get("latched") is True
                   and first["packet_mechanism"]["front_fraction"] == 1 and first["packet_mechanism"]["rear_fraction"] == 1, first)
        self.check("first paused packet has immediate physical door and target", self.valid_probe(first.get("probe", {}), False), first.get("probe"))
        self.check("reconnect preserves exactly one earned discovery", resumed["personal"]["discoveries"].count(DISCOVERY) == 1
                   and resumed["guest_received_count"] == count_before)
        before_events = sum(DISCOVERY in e.get("reward_ids", []) for e in resumed.get("events", []))
        self.request("host", "resend_earned_receipt")
        duplicate = self.wait("guest_reconnect", lambda s: sum(DISCOVERY in e.get("reward_ids", []) for e in s.get("events", [])) > before_events,
                              "earned receipt deliberately repeated through reliable RPC")
        self.check("reliable duplicate does not duplicate durable reward", duplicate["guest_received_count"] == count_before
                   and duplicate["personal"]["discoveries"].count(DISCOVERY) == 1)
        self.save_case("case3-paused-reconnect", host=host, guest=duplicate)
        self.request("host", "shutdown")
        self.natural_exit("host")
        left = self.wait("guest_reconnect", lambda s: s.get("host_left_seen") and not s.get("active"), "real host departure notification")
        self.check("host departure retains personal discovery", left["personal"]["discoveries"].count(DISCOVERY) == 1)
        self.request("guest_reconnect", "shutdown")
        self.natural_exit("guest_reconnect")
        self.complete()

    def cleanup(self) -> None:
        for label, (process, log) in self.processes.items():
            record = self.summary["processes"][label]
            if process.poll() is None:
                record["forced_stop"] = True
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)
            record["exit_code"] = process.poll()
            record["finished_utc"] = utc_now()
            if not log.closed:
                log.close()
            record["report"] = self.read(label)
            lines = (self.evidence / f"{label}.log").read_text(encoding="utf-8", errors="replace").splitlines()
            record["engine_errors"] = [line for line in lines if line.startswith(("ERROR:", "SCRIPT ERROR:"))]
            record["mtu_warnings"] = [line for line in lines if "warning" in line.lower() and "mtu" in line.lower()]

    def finalize(self) -> int:
        self.cleanup()
        self.summary["source_sha256_after"] = fingerprints(self.project)
        self.summary["executable_sha256_after"] = file_sha256(self.godot)
        unchanged = self.summary["source_sha256_before"] == self.summary["source_sha256_after"]
        unchanged = unchanged and self.summary["executable_sha256_before"] == self.summary["executable_sha256_after"]
        self.summary["sources_unchanged"] = unchanged
        self.summary["checks"].append({"name": "frozen code assets executable unchanged", "passed": unchanged})
        for label, record in self.summary["processes"].items():
            passed = record["exit_code"] == 0 and not record["forced_stop"] and not record["engine_errors"] and not record["mtu_warnings"] and not record["report"].get("errors")
            self.summary["checks"].append({"name": f"{label} natural clean exit", "passed": passed})
            self.summary["checks"].append({"name": f"{label} specialized entry and runtime layout hash",
                                           "passed": self.matches_driver_state(label, record["report"])})
        host_transport = self.summary["processes"].get("host", {}).get("report", {}).get("transport", {})
        self.summary["checks"].append({"name": "measured loopback snapshot budget", "passed": 0 < host_transport.get("max_snapshot_bytes", 0) <= 1150, "actual": host_transport})
        complete = len(self.summary["scenarios"]) == EXPECTED_SCENARIOS and all(s["completed"] for s in self.summary["scenarios"])
        self.summary["passed"] = complete and not self.summary.get("error") and all(c["passed"] for c in self.summary["checks"])
        self.summary["finished_utc"] = utc_now()
        atomic_json(self.evidence / "summary.json", self.summary)
        print(json.dumps({"passed": self.summary["passed"], "evidence": str(self.evidence),
                          "completed_scenarios": sum(s["completed"] for s in self.summary["scenarios"]),
                          "error": self.summary.get("error"), "scope": self.summary["scope"]}, ensure_ascii=False, indent=2), flush=True)
        return 0 if self.summary["passed"] else 1


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--godot", type=Path, default=None)
    entries = parser.add_mutually_exclusive_group()
    entries.add_argument("--standalone", action="store_true", help="Exported EXE normal entry, without --script or --path.")
    entries.add_argument("--source-main", action="store_true", help="Editor binary normal application entry instead of --script.")
    parser.add_argument("--expected-underdeck-sha", default="")
    parser.add_argument("--run", action="store_true", help="Explicitly run only after root confirms asset AND shared-code freeze.")
    args = parser.parse_args()
    if not args.run:
        print("PREPARATION ONLY: no Godot process, no ENet and no UDP lock acquired. After shared-code/layout freeze pass --run --expected-underdeck-sha <final SHA256>.")
        return 0
    if args.standalone and args.godot is None:
        parser.error("--standalone requires an explicit --godot exported executable")
    project = args.project.resolve()
    godot = (args.godot or (Path(os.environ.get("LOCALAPPDATA", "")) / "Programs/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe")).resolve()
    entry_kind = "package_main" if args.standalone else ("source_main" if args.source_main else "source_script")
    sha = args.expected_underdeck_sha.lower()
    if len(sha) != 64 or any(char not in "0123456789abcdef" for char in sha):
        parser.error("--run requires the explicitly frozen Underdeck layout SHA256")
    if not godot.is_file() or not (project / "project.godot").is_file():
        parser.error("Godot and source project must exist")
    if not (project / MODEL).is_file() or file_sha256(project / MODEL) != sha:
        parser.error("Underdeck layout does not match the frozen SHA256; no process started")
    lock = LanPortLock()
    try:
        lock.acquire()
    except (LanRunBusy, OSError) as exc:
        print(f"REFUSED: {exc}. No Godot process started.", file=sys.stderr, flush=True)
        return 3
    run = None
    try:
        run = Run(project, godot, sha, lock, entry_kind)
        try:
            run.exercise()
        except BaseException as exc:
            run.summary["error"] = f"{type(exc).__name__}: {exc}"
            (run.evidence / "orchestration-error.log").write_text(traceback.format_exc(), encoding="utf-8")
        return run.finalize()
    finally:
        if run is not None:
            run.cleanup()  # Own PIDs only; safe after normal cleanup and on unexpected finalization error.
        lock.release()


if __name__ == "__main__":
    raise SystemExit(main())
