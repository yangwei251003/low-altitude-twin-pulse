#!/usr/bin/env python3
"""Controlled Crown ENet loopback, source project only; never a two-computer LAN claim.

Default is preparation only and starts no Godot process. After asset/code freeze:
  python scripts_tools/v3/test_crown_lan.py --run --expected-crown-sha <frozen SHA256>
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

WEST = "F1:crown_host_west"
CORE = "boss:crown_core"
MODEL = "assets/v3/crown/parasitic_crown.glb"
PEER_SCRIPT = "res://scripts/v3/qa/twin_crown_lan_peer.gd"
EXPECTED_SCENARIOS = 7


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
    extras = [project / "scripts_tools/v3/test_crown_lan.py"]
    extras += [p for p in (project / "assets/v3").rglob("*")
               if p.is_file() and p.suffix not in (".import", ".uid")]
    for path in extras:
        result[path.relative_to(project).as_posix()] = file_sha256(path)
    return dict(sorted(result.items()))


class Run:
    def __init__(self, project: Path, godot: Path, sha: str, lock: LanPortLock) -> None:
        self.project, self.godot, self.sha, self.lock = project, godot, sha, lock
        self.run_id = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
        self.evidence = project / "artifacts/v3/network/crown" / self.run_id
        self.evidence.mkdir(parents=True, exist_ok=False)
        self.profiles = {"host": f"qa_crown_lan_host_{self.run_id}",
                         "guest": f"qa_crown_lan_guest_{self.run_id}"}
        self.processes: dict[str, tuple[subprocess.Popen, object]] = {}
        self.command_sequences: dict[str, int] = {}
        self.summary = {
            "schema_version": 1, "run_id": self.run_id, "started_utc": utc_now(),
            "scope": "same-computer two-process real ENet loopback, scripted poses; not physical two-computer LAN",
            "limitations": ["No human play, GPU, performance, real LAN/router/firewall acceptance.",
                            "QA freezes real bodies and stages poses, pause and direct practice encounter start.",
                            "Receipt uses a labeled QA discovery; this suite does not prove campaign first-victory rewards."],
            "project": str(project), "godot": str(godot), "crown_sha256": sha,
            "executable_sha256_before": file_sha256(godot), "source_sha256_before": fingerprints(project),
            "lock": {"path": str(lock.path), "port": 26742, "pid": os.getpid(), "backend": lock.backend},
            "profiles": self.profiles, "scenarios": [], "checks": [], "processes": {}, "passed": False,
        }
        self.heartbeat()

    def heartbeat(self) -> None:
        atomic_json(self.evidence / "controller.json", {
            "run_id": self.run_id, "pid": os.getpid(), "lock_held": self.lock.stream is not None,
            "heartbeat_unix": time.time(), "crown_sha256": self.sha,
        })

    def read(self, label: str) -> dict:
        try:
            value = json.loads((self.evidence / f"{label}-state.json").read_text(encoding="utf-8"))
            return value if isinstance(value, dict) else {}
        except (OSError, ValueError):
            return {}

    def wait(self, label: str, predicate, description: str, timeout: float = 15) -> dict:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            self.heartbeat()
            state = self.read(label)
            if state.get("errors"):
                raise RuntimeError(f"{label} driver failed: {state['errors']}")
            if state and predicate(state):
                return state
            if self.processes[label][0].poll() is not None:
                raise RuntimeError(f"{label} exited before {description}")
            time.sleep(0.05)
        raise TimeoutError(f"{label}: {description}; latest state retained in evidence")

    def observe(self, label: str, description: str) -> dict:
        # The live peer truncates/replaces its JSON contents every report tick.
        # read() may return {} during publication; only wait() consumes that
        # sentinel. Return a newly parsed complete report, never a cached one.
        return self.wait(label, lambda state: True, description, timeout=5)

    def settle(self, seconds: float) -> None:
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            self.heartbeat()
            time.sleep(0.05)

    def launch(self, label: str, role: str, reconnect: bool = False) -> None:
        if self.lock.stream is None:
            raise RuntimeError("Cannot spawn a game before shared port lock ownership")
        command = [str(self.godot), "--headless", "--path", str(self.project), "--script", PEER_SCRIPT, "--",
                   f"--qa-profile={self.profiles[role]}", f"--qa-crown-role={role}",
                   f"--qa-crown-label={label}", f"--qa-crown-run={self.run_id}",
                   f"--qa-crown-evidence={self.evidence}", f"--qa-crown-sha={self.sha}"]
        if reconnect:
            command.append("--qa-crown-reconnect")
        log = (self.evidence / f"{label}.log").open("wb")
        try:
            process = subprocess.Popen(command, cwd=self.project, stdout=log, stderr=subprocess.STDOUT,
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

    def action(self, label: str, ability: str, target: str = WEST) -> dict:
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

    def paused_roundtrip(self, guest: str, opened: bool) -> dict:
        host = self.request("host", "pause", {"value": True})
        self.check("authoritative core state matches collision expectation", host.get("boss", {}).get("core_open") is opened,
                   host.get("boss", {}))
        peer = self.wait(guest, lambda s: s.get("paused") and s.get("boss") == host.get("boss")
                         and s.get("latest_probe", {}).get("paused"), "matching paused Crown presentation")
        expected = CORE if opened else "boss:crown_armor"
        self.check("host actual nine-point core probe", host.get("host_probe", {}).get("hits") == [expected] * 9,
                   host.get("host_probe"))
        self.check("guest same-application-frame nine-point probe", peer.get("latest_probe", {}).get("probe", {}).get("hits") == [expected] * 9,
                   peer.get("latest_probe"))
        return peer

    def shoot(self, guest: str) -> tuple[dict, dict]:
        self.request("host", "shooter")
        self.request(guest, "action", {"verb": "lock", "payload": {"target_id": CORE}})
        peer_id = str(self.observe(guest, "current shooting peer identity")["peer_id"])
        self.wait("host", lambda s: s.get("players", {}).get(peer_id, {}).get("lock") == CORE, "guest lock arrives through ENet")
        before = self.request("host", "state")
        self.request(guest, "fire", {"seconds": 0.3})
        self.wait(guest, lambda s: s.get("fire_remaining", 1) == 0, "guest completes input burst")
        self.settle(0.35)
        after = self.request("host", "state")
        shots = after["stats"]["shots"] - before["stats"]["shots"]
        self.check("real guest input damages open core through host ray", shots > 0 and
                   abs(before["boss"]["core_health"] - after["boss"]["core_health"] - shots * 9) < 0.001,
                   {"shots": shots, "before": before["boss"]["core_health"], "after": after["boss"]["core_health"]})
        return before, after

    def natural_exit(self, label: str, timeout: float = 12) -> None:
        deadline = time.monotonic() + timeout
        process, log = self.processes[label]
        while process.poll() is None and time.monotonic() < deadline:
            self.heartbeat()
            time.sleep(0.05)
        self.check(f"{label} natural exit", process.poll() == 0, process.poll())
        if not log.closed:
            log.close()

    def exercise(self) -> None:
        self.scenario("1 F1 separation and participant boundary")
        self.launch("host", "host")
        host = self.wait("host", lambda s: s.get("active") and s.get("region") == "F1", "host ready")
        self.launch("guest_first", "guest")
        first = self.wait("guest_first", lambda s: len(s.get("players", {})) == 2 and s.get("region") == "F1", "first F1 snapshot")
        self.check("guest belongs to this controller's host", first["session_id"] == host["session_id"])
        self.request("host", "fixture_split")
        split = self.wait("host", lambda s: len(s.get("crown_players", {})) == 1, "one northern combat participant")
        guest_id = str(first["peer_id"])
        self.check("southern guest is not a combat actor", list(split["crown_players"]) == ["player:1"] and split["players"][guest_id]["position"][2] > -12, split["crown_players"])
        self.complete()

        self.scenario("2 host/guest abilities and busy recovery")
        rejected = split["stats"]["rejected_abilities"]
        self.action("guest_first", "light")
        self.wait("host", lambda s: s["stats"]["rejected_abilities"] > rejected, "outside participant ability rejection")
        self.action("host", "light")
        self.wait("host", lambda s: s["boss"]["anchors"][WEST]["lit"], "host light authority state")
        self.request("host", "near_host", {"peer": "guest"})
        self.wait("host", lambda s: "player:" + guest_id in s["crown_players"], "guest enters combat by real body position")
        self.action("guest_first", "growth")
        bound = self.wait("host", lambda s: s["boss"].get("mode") == "bound", "guest growth opens real crown")
        rejected = bound["stats"]["rejected_abilities"]
        accepted = bound["stats"]["abilities"]
        self.action("guest_first", "growth")
        self.wait("host", lambda s: s["stats"]["rejected_abilities"] > rejected, "immediate busy action refused")
        self.settle(0.45)
        self.action("guest_first", "growth")
        busy = self.wait("host", lambda s: s["stats"]["rejected_abilities"] >= rejected + 2, "recovering roots refuse repeated payment")
        self.check("busy/recovering actions create no second success", busy["stats"]["abilities"] == accepted)
        self.complete()

        self.scenario("3 open plates and paused same-frame guest collision")
        self.paused_roundtrip("guest_first", True)
        self.complete()

        self.scenario("4 real shooting, stale input rejection and durable duplicate receipt")
        self.request("host", "pause", {"value": False})
        _, shot = self.shoot("guest_first")
        self.request("guest_first", "replay_fire")
        self.settle(0.4)
        replay = self.request("host", "state")
        self.check("old input sequence cannot fire again", replay["stats"]["shots"] == shot["stats"]["shots"] and replay["boss"]["core_health"] == shot["boss"]["core_health"])
        receipt = self.request("host", "receipt")["result"]
        reward = receipt["reward_id"]
        delivered = self.wait("guest_first", lambda s: s["personal"]["discoveries"].count(reward) == 1, "reliable persisted discovery receipt")
        self.wait("host", lambda s: s.get("pending_receipts") == 0, "real guest receipt ACK")
        before_events = len([e for e in delivered["events"] if e["kind"] == "receipt_batch"])
        self.request("host", "resend_receipt")
        duplicate = self.wait("guest_first", lambda s: len([e for e in s["events"] if e["kind"] == "receipt_batch"]) > before_events, "duplicate actually delivered over reliable ENet")
        self.check("duplicate creates no personal reward or receipt", duplicate["personal"]["discoveries"].count(reward) == 1 and duplicate["guest_received_count"] == delivered["guest_received_count"])
        self.complete()

        self.scenario("5 paused spore reconnect and first-frame closed armor")
        self.request("host", "reset_pair")
        self.action("host", "heat")
        self.wait("host", lambda s: s["boss"]["anchors"][WEST]["temperature"] == 45, "first heat")
        self.settle(0.4)
        self.action("host", "heat")
        self.wait("host", lambda s: s["boss"]["anchors"][WEST]["burning"], "second heat creates real spore")
        paused = self.paused_roundtrip("guest_first", False)
        self.check("spore fixture exists in authoritative snapshot", any(a["kind"] == "burning_spores" for a in paused["boss"]["attacks"]))
        old_identity = paused["profile_id"]
        self.request("guest_first", "shutdown")
        self.natural_exit("guest_first")
        self.wait("host", lambda s: len(s["players"]) == 1, "host observes first guest departure")
        self.launch("guest_reconnect", "guest", reconnect=True)
        rejoined = self.wait("guest_reconnect", lambda s: bool(s.get("first_paused_snapshot")) and len(s.get("players", {})) == 2, "fresh process applies paused spore state")
        first_pause = rejoined["first_paused_snapshot"]
        expected_warnings = sum(len(a["shapes"]) for a in first_pause["boss"]["attacks"])
        self.check("same personal identity survives process restart", rejoined["profile_id"] == old_identity and rejoined["initial_personal"]["discoveries"].count(reward) == 1)
        self.check("first paused packet restores actual closed armor and warnings", first_pause["probe"].get("hits") == ["boss:crown_armor"] * 9 and first_pause["warning_count"] == expected_warnings and expected_warnings > 0, first_pause)
        current_host = self.observe("host", "current paused host attempt and transient state")
        self.check("paused rejoin retains host attempt and transient state", rejoined["boss"] == current_host["boss"])
        self.complete()

        self.scenario("6 reverse abilities, fresh shooting sequence and repeated receipt after reconnect")
        self.request("host", "pause", {"value": False})
        self.request("host", "reset_pair")
        self.action("guest_reconnect", "light")
        self.wait("host", lambda s: s["boss"]["anchors"][WEST]["lit"], "guest light authority state")
        self.action("host", "growth")
        self.wait("host", lambda s: s["boss"].get("mode") == "bound", "host growth authority state")
        self.paused_roundtrip("guest_reconnect", True)
        new_peer = str(self.observe("guest_reconnect", "current reconnected peer identity")["peer_id"])
        fresh = self.observe("host", "current reconnected combat roster")["crown_players"].get("player:" + new_peer, {})
        self.check("new combat roster has no prior accepted shot", fresh.get("last_shot_sequence") == 0, fresh)
        self.request("host", "pause", {"value": False})
        _, after_rejoin_shot = self.shoot("guest_reconnect")
        self.check("reconnected actor gets accepted new shot sequence", after_rejoin_shot["crown_players"]["player:" + new_peer]["last_shot_sequence"] > 0)
        current_guest = self.observe("guest_reconnect", "current receipt count and received events")
        count_before = current_guest["guest_received_count"]
        events_before = len([e for e in current_guest["events"] if e["kind"] == "receipt_batch"])
        self.request("host", "resend_receipt")
        again = self.wait("guest_reconnect", lambda s: len([e for e in s["events"] if e["kind"] == "receipt_batch"]) > events_before, "same receipt reaches new process")
        self.check("reconnect cannot collect duplicate discovery", again["guest_received_count"] == count_before and again["personal"]["discoveries"].count(reward) == 1)
        self.complete()

        self.scenario("7 host departure notification and retained guest personal progress")
        self.request("host", "shutdown")
        self.natural_exit("host")
        left = self.wait("guest_reconnect", lambda s: s.get("host_left_seen") and not s.get("active") and s.get("network_mode") == "disconnected", "production host-left notification")
        self.check("host departure clears remote world and retains personal discovery", not left["players"] and left["personal"]["discoveries"].count(reward) == 1)
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
    parser.add_argument("--godot", type=Path, default=Path(os.environ.get("LOCALAPPDATA", "")) / "Programs/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe")
    parser.add_argument("--expected-crown-sha", default="")
    parser.add_argument("--run", action="store_true", help="Explicitly run only after root confirms asset AND shared-code freeze.")
    args = parser.parse_args()
    if not args.run:
        print("PREPARATION ONLY: no Godot process, no ENet and no UDP lock acquired. After asset/code freeze pass --run --expected-crown-sha <final SHA256>.")
        return 0
    project, godot = args.project.resolve(), args.godot.resolve()
    sha = args.expected_crown_sha.lower()
    if len(sha) != 64 or any(char not in "0123456789abcdef" for char in sha):
        parser.error("--run requires the explicitly frozen Crown GLB SHA256")
    if not godot.is_file() or not (project / "project.godot").is_file():
        parser.error("Godot and source project must exist")
    if not (project / MODEL).is_file() or file_sha256(project / MODEL) != sha:
        parser.error("Crown GLB does not match the frozen SHA256; no process started")
    lock = LanPortLock()
    try:
        lock.acquire()
    except (LanRunBusy, OSError) as exc:
        print(f"REFUSED: {exc}. No Godot process started.", file=sys.stderr, flush=True)
        return 3
    run = None
    try:
        run = Run(project, godot, sha, lock)
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
