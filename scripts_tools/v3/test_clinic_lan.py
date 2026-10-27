#!/usr/bin/env python3
"""Controlled Clinic ENet loopback using one shared source/package Node probe; not two-computer LAN.

Default is preparation only and starts no Godot process. After shared-code/layout freeze:
  python scripts_tools/v3/test_clinic_lan.py --run --expected-clinic-sha <frozen SHA256>
Both source and package use the application router. Add --standalone
--godot <exported EXE> for the PCK entry (no --script and no --path).
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

GRAVITY = "I2:clinic_gravity_valve"
PUMP = "I2:clinic_pump"
RELAY = "I2:clinic_relay"
DISCOVERY = "I2:clinic_priority_misroute"
DIAGNOSE = "I2:clinic_supply:diagnose"
CONNECT = "I2:clinic_supply:connect"
STABILIZE = "I2:clinic_supply:stabilize"
CONFIRM = "I2:clinic_supply:confirm"
MODEL = "data/v3/terrain/i2_clinic_layout.json"
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
    extras = [project / "scripts_tools/v3/test_clinic_lan.py"]
    extras += [p for p in (project / "assets/v3").rglob("*")
               if p.is_file() and p.suffix not in (".import", ".uid")]
    for path in extras:
        result[path.relative_to(project).as_posix()] = file_sha256(path)
    return dict(sorted(result.items()))


def peer_command(executable: Path, project: Path, entry_kind: str, user_args: list[str]) -> list[str]:
    """Both modes exercise the application router; PCK never sees source paths."""
    command = [str(executable), "--headless"]
    if entry_kind == "source_main":
        command += ["--path", str(project)]
    elif entry_kind != "package_main":
        raise ValueError("Unknown QA entry kind")
    return command + ["--"] + user_args


class Run:
    def __init__(self, project: Path, godot: Path, sha: str, lock: LanPortLock, entry_kind: str = "source_main") -> None:
        self.project, self.godot, self.sha, self.lock = project, godot, sha, lock
        self.hard_deadline = time.monotonic() + 220.0
        if entry_kind not in ("source_main", "package_main"):
            raise ValueError("Invalid entry kind")
        self.entry_kind = entry_kind
        self.runtime_cwd = godot.parent if entry_kind == "package_main" else project
        self.run_id = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
        self.evidence = self.runtime_cwd / "artifacts/v3/network/clinic" / self.run_id
        if self.evidence.resolve() != self.evidence:
            raise RuntimeError("Evidence path must not redirect outside the exact runtime run directory")
        self.evidence.mkdir(parents=True, exist_ok=False)
        self.profiles = {"host": f"qa_clinic_lan_host_{self.run_id}",
                         "guest": f"qa_clinic_lan_guest_{self.run_id}"}
        self.processes: dict[str, tuple[subprocess.Popen, object]] = {}
        self.command_sequences: dict[str, int] = {}
        self.summary = {
            "schema_version": 1, "run_id": self.run_id, "started_utc": utc_now(),
            "scope": "same-computer two-process real ENet loopback, scripted poses; not physical two-computer LAN",
            "limitations": ["No human play, GPU, performance, remote-PC/router/firewall acceptance; no artificial latency or loss injection.",
                            "Previous27 goals are explicit saved Director fixtures. Current goals, water and ability requests use production rules and transport.",
                            "QA freezes pilots and uses collision-checked initial poses. It does not test flight feel or traversing routes; it never sets water, valve fractions, completion flags or received packets.",
                            "Guest publication failure is an explicit Store fault. Earned receipt replay uses actual reliable RPC. Pause uses both participants' production votes."],
            "project": str(project), "godot": str(godot), "clinic_sha256": sha,
            "qa_suite": "clinic-lan", "entry_kind": entry_kind,
            "runtime_cwd": str(self.runtime_cwd), "source_path_passed": entry_kind != "package_main",
            "script_override_passed": False,
            "executable_sha256_before": file_sha256(godot), "source_sha256_before": fingerprints(project),
            "lock": {"path": str(lock.path), "port": 26742, "pid": os.getpid(), "backend": lock.backend},
            "profiles": self.profiles, "scenarios": [], "checks": [], "processes": {}, "passed": False,
        }
        self.heartbeat()

    def heartbeat(self) -> None:
        if time.monotonic() >= self.hard_deadline:
            raise TimeoutError("Clinic controller hard220-second limit reached")
        atomic_json(self.evidence / "controller.json", {
            "run_id": self.run_id, "pid": os.getpid(), "lock_held": self.lock.stream is not None,
            "heartbeat_unix": time.time(), "clinic_sha256": self.sha,
            "qa_suite": "clinic-lan", "entry_kind": self.entry_kind,
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
        return (state.get("qa_suite") == "clinic-lan"
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

    def observe(self, label: str, description: str) -> dict:
        # A live peer rewrites its JSON report every 50ms. read() intentionally
        # returns {} during a partial publication; only wait() may consume that
        # sentinel. Never index it or reuse an older cached report as evidence.
        return self.wait(label, lambda state: True, description, timeout=5)

    def settle(self, seconds: float) -> None:
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            self.heartbeat()
            time.sleep(0.05)

    def launch(self, label: str, role: str, reconnect: bool = False) -> None:
        if self.lock.stream is None:
            raise RuntimeError("Cannot spawn a game before shared port lock ownership")
        user_args = ["--qa-suite=clinic-lan", f"--qa-profile={self.profiles[role]}",
                     f"--qa-clinic-role={role}", f"--qa-clinic-label={label}",
                     f"--qa-clinic-run={self.run_id}", f"--qa-clinic-evidence={self.evidence}",
                     f"--qa-clinic-sha={self.sha}"]
        if reconnect:
            user_args.append("--qa-clinic-reconnect")
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

    def action(self, label: str, ability: str, target: str, mode: str = "") -> dict:
        return self.request(label, "action", {"payload": {"ability": ability, "target_id": target, "mode": mode}})

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
                and probe.get("moving_parts") == 9 and probe.get("deck_ray_correct") is True
                and probe.get("maximum_pose_error", 999) < 0.001
                and probe.get("target_error", 999) < 0.001)

    def save_case(self, name: str, **states: dict) -> None:
        atomic_json(self.evidence / (name + ".json"), states)

    def pause(self, guest_label: str) -> None:
        self.request("host", "propose_pause")
        self.wait(guest_label, lambda s: bool(s.get("proposal")), "guest receives actual pause proposal")
        self.request(guest_label, "confirm_vote")
        self.wait("host", lambda s: s.get("paused") is True, "both participant pause commits")
        self.wait(guest_label, lambda s: s.get("paused") is True, "guest pause snapshot arrives")

    def exercise(self) -> None:
        self.scenario("1 real gravity supply before first guest hydraulic/collision snapshot")
        self.launch("host", "host")
        host = self.wait("host", lambda s: s.get("region") == "I2" and s.get("story_ready")
                         and self.valid_probe(s.get("probe", {}), True), "host actual I2 module")
        self.check("explicit predecessor fixture has27 completed goals", len(host["completed"]) == 27)
        self.request("host", "g")
        self.wait("host", lambda s: DIAGNOSE in s.get("completed", []), "actual G diagnosis")
        self.request("host", "place_host", {"position": [-10, 7, -2.5]})
        count = self.observe("host", "current host ability baseline")["stats"]["abilities"]
        self.action("host", "push_pull", GRAVITY)
        host = self.wait("host", lambda s: s["stats"]["abilities"] == count + 1
                         and s["probe"]["status"]["clinic_volume_ml"] > 12000,
                         "real host push opens swept valve and transfers water")
        self.check("gravity transfer follows actual open detent", host["probe"]["state"]["gravity_fraction"] >= 0.995
                   and host["history"]["route_method"] == "gravity")
        self.launch("guest_first", "guest")
        guest = self.wait("guest_first", lambda s: bool(s.get("first_snapshot"))
                          and len(s.get("players", {})) == 2 and s.get("story_ready"), "actual ENet first guest state")
        first = guest["first_snapshot"]
        self.check("first applied guest packet has matching received reliable water", first.get("state_matches_reliable") is True
                   and first["probe"]["status"]["clinic_volume_ml"] > 0, first)
        self.check("first packet reconstructs actual nine-part deck and target collision", self.valid_probe(first.get("probe", {}), False), first.get("probe"))
        self.check("first flowing guest state retains uncommissioned amber lens",
                   first["probe"].get("service_available") is False and first["probe"].get("service_color") == "dba358")
        self.check("guest is real wider HX02", guest["players"][str(guest["peer_id"])]["airframe"] == "hx02")
        self.wait("host", lambda s: s.get("pending_receipts") == 0, "historical discovery catchup drains")
        self.settle(0.6)
        guest = self.observe("guest_first", "current guest simulation observations")
        self.check("guest world is not saved and guest ticks cannot advance water", guest.get("personal_world_unchanged") is True
                   and guest.get("guest_ticks", 0) > 0 and guest.get("guest_local_mutations") == 0)
        self.save_case("case1-first-flow", host=host, guest=guest)
        self.complete()

        self.scenario("2 guest charge/takeover, physical interlock, stable manual confirmation and failed guest receipt")
        self.request("host", "place_guest", {"position": [-7, 1.6, 10]})
        self.wait("guest_first", lambda s: abs(s["players"][str(s["peer_id"])]["position"][2] - 10) < 0.1,
                  "guest receives authorized low-room starting pose")
        count = self.observe("host", "current host ability baseline before guest charge")["stats"]["abilities"]
        self.action("guest_first", "charge", RELAY)
        self.wait("host", lambda s: s["stats"]["abilities"] == count + 1 and s["probe"]["status"]["powered"],
                  "real guest charge accepted by host authority")
        self.settle(0.5)
        count += 1
        self.action("guest_first", "takeover", PUMP)
        host = self.wait("host", lambda s: s["stats"]["abilities"] == count + 1
                         and s["probe"]["status"]["interlock_waiting"], "guest takeover respects still-open gravity interlock")
        self.check("pump cannot open through live mechanical interlock", host["probe"]["state"]["pump_fraction"] == 0.0
                   and host["probe"]["state"]["gravity_fraction"] >= 0.995)
        before_pull = host["stats"].copy()
        pulled = self.action("host", "push_pull", GRAVITY, "pull")
        # Authority send_action is synchronous. A dispatch acknowledgement is
        # not proof that the ability was accepted; retain the actual reason
        # instead of hiding an immediate rejection behind a mechanism timeout.
        self.check("host pull is accepted at the original oblique starting pose",
                   pulled["stats"]["abilities"] == before_pull["abilities"] + 1
                   and pulled["stats"]["rejected_abilities"] == before_pull["rejected_abilities"],
                   {"abilities": pulled.get("ability_outcomes", [])[-4:],
                    "notes": pulled.get("authority_notes", [])[-4:]})
        host = self.wait("host", lambda s: s["probe"]["status"]["pump_latched"]
                         and s["probe"]["state"]["gravity_fraction"] < 0.005,
                         "host closes high route and guest's legal motor signal completes selector", timeout=10)
        self.check("two real routes do not overwrite first-transfer history", host["history"]["route_method"] == "gravity"
                   and host["choices"].get(CONNECT) == "gravity")
        host = self.wait("host", lambda s: STABILIZE in s.get("completed", [])
                         and s["probe"]["status"]["clinic_volume_ml"] == 2000000,
                         "actual conserved water and clear deck stabilize", timeout=65)
        self.check("full water has actual raised collision and closed inlet", self.valid_probe(host["probe"], True)
                   and host["probe"]["status"]["inlet_closed"] is True and abs(host["probe"]["status"]["deck_top_y"]-5) < 0.001)
        self.check("full water without G leaves actual host service lens amber",
                   host["probe"].get("service_available") is False and host["probe"].get("service_color") == "dba358")
        self.request("guest_first", "receipt_write_failure", {"enabled": True})
        self.request("host", "place_guest", {"position": [7, 5.8, -1]})
        self.wait("guest_first", lambda s: abs(s["players"][str(s["peer_id"])]["position"][0]-7) < 0.1
                  and STABILIZE in s.get("completed", []),
                  "guest receives actual confirmation pose and current story objective")
        self.request("guest_first", "g")
        host = self.wait("host", lambda s: CONFIRM in s.get("completed", [])
                         and s.get("pending_receipts", 0) > 0, "real guest G commits host completion and queues receipt")
        self.settle(2.4)
        failed = self.observe("guest_first", "current guest receipt state after failed publication")
        host = self.observe("host", "current host outbox after guest publication failure")
        self.check("failed guest disk publication cannot acknowledge discovery", failed["personal"]["discoveries"].count(DISCOVERY) == 0
                   and host["pending_receipts"] > 0, failed.get("guest_received_count"))
        self.check("host holds one earned discovery", host["personal"]["discoveries"].count(DISCOVERY) == 1)
        self.check("real guest G makes committed service teal on both peers despite receipt disk failure",
                   all(state["probe"].get("service_available") is True and state["probe"].get("service_color") == "4bcdb5"
                       for state in [host, failed]))
        self.save_case("case2-real-cooperation", host=host, guest=failed)
        self.complete()

        self.scenario("3 voted pause, same-identity reconnect first collision, retry/replay exactly once and host exit")
        self.pause("guest_first")
        paused_host = self.observe("host", "current paused host water state")
        paused_guest = self.observe("guest_first", "current paused guest identity and receipt baseline")
        identity = paused_guest["profile_id"]
        baseline_received = paused_guest["guest_received_count"]
        self.request("guest_first", "shutdown")
        self.natural_exit("guest_first")
        self.wait("host", lambda s: len(s.get("players", {})) == 1, "host sees actual guest disconnect")
        self.launch("guest_reconnect", "guest", reconnect=True)
        resumed = self.wait("guest_reconnect", lambda s: bool(s.get("first_paused_snapshot"))
                            and s.get("story_ready") and CONFIRM in s.get("completed", []),
                            "paused real ENet reconnect with story")
        first = resumed["first_snapshot"]
        self.check("same guest identity reconnects", resumed["profile_id"] == identity)
        self.check("first reconnect packet already has correct full water and paused collision", first.get("paused") is True
                   and first.get("state_matches_reliable") is True and self.valid_probe(first.get("probe", {}), False)
                   and first["probe"]["status"]["clinic_volume_ml"] == 2000000, first)
        self.check("paused reconnect reconstructs committed teal service in its first accepted state",
                   first["probe"].get("service_available") is True and first["probe"].get("service_color") == "4bcdb5")
        self.check("paused reconnect water matches paused host runtime", first["probe"]["state"]["runtime"] == paused_host["probe"]["state"]["runtime"])
        resumed = self.wait("guest_reconnect", lambda s: s["personal"]["discoveries"].count(DISCOVERY) == 1,
                            "production retry recovers guest disk receipt while paused")
        self.wait("host", lambda s: s.get("pending_receipts") == 0, "real reliable ACK drains host outbox")
        self.check("only new clinic receipt is added after reconnect", resumed["guest_received_count"] == baseline_received + 1
                   and resumed.get("personal_world_unchanged") is True)
        events = sum(DISCOVERY in item.get("reward_ids", []) for item in resumed.get("events", []))
        self.request("host", "resend_earned_receipt")
        duplicate = self.wait("guest_reconnect", lambda s: sum(DISCOVERY in item.get("reward_ids", []) for item in s.get("events", [])) > events,
                              "exact earned receipt replay arrives through real ENet")
        self.check("duplicate reliable receipt never duplicates personal record", duplicate["guest_received_count"] == baseline_received + 1
                   and duplicate["personal"]["discoveries"].count(DISCOVERY) == 1 and duplicate["guest_local_mutations"] == 0)
        self.save_case("case3-paused-reconnect", host=paused_host, guest=duplicate)
        self.request("host", "shutdown")
        self.natural_exit("host")
        left = self.wait("guest_reconnect", lambda s: s.get("host_left_seen") and not s.get("active"), "real host departure event")
        self.check("host departure preserves guest record and private world", left["personal"]["discoveries"].count(DISCOVERY) == 1
                   and left.get("personal_world_unchanged") is True)
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
    entries.add_argument("--source-main", action="store_true", help="Explicit alias for the default source application entry.")
    parser.add_argument("--expected-clinic-sha", default="")
    parser.add_argument("--run", action="store_true", help="Explicitly run only after root confirms asset AND shared-code freeze.")
    args = parser.parse_args()
    if not args.run:
        print("PREPARATION ONLY: no Godot process, no ENet and no UDP lock acquired. After shared-code/layout freeze pass --run --expected-clinic-sha <final SHA256>.")
        return 0
    if args.standalone and args.godot is None:
        parser.error("--standalone requires an explicit --godot exported executable")
    project = args.project.resolve()
    godot = (args.godot or (Path(os.environ.get("LOCALAPPDATA", "")) / "Programs/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe")).resolve()
    entry_kind = "package_main" if args.standalone else "source_main"
    sha = args.expected_clinic_sha.lower()
    if len(sha) != 64 or any(char not in "0123456789abcdef" for char in sha):
        parser.error("--run requires the explicitly frozen Clinic layout SHA256")
    if not godot.is_file() or not (project / "project.godot").is_file():
        parser.error("Godot and source project must exist")
    if not (project / MODEL).is_file() or file_sha256(project / MODEL) != sha:
        parser.error("Clinic layout does not match the frozen SHA256; no process started")
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
