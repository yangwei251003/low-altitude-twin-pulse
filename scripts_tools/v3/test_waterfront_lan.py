#!/usr/bin/env python3
"""One SOURCE-only, two-real-MAIN ENet waterfront regression; not physical LAN.

Preparation by default. Run only during the assigned engine window:
  python scripts_tools/v3/test_waterfront_lan.py --run

The outer existing dev Job Object bounds this controller and both Godot trees
to 90 seconds. The controller owns the existing exclusive UDP 26742 lock.
Saved predecessor actions and one host deep-water pose are declared fixtures.
No direct timer/health injection or continuous body freeze. Facility waiting
coverage is reported NOT_COVERED when no natural waiting frame was observed.
"""
from __future__ import annotations

import argparse
from datetime import datetime
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import time
import traceback
import uuid

sys.dont_write_bytecode = True
from test_lan_local import LanPortLock, LanRunBusy, file_sha256, process_options, source_fingerprints, utc_now

ROOT = Path(__file__).resolve().parents[2]
PROBE = "res://tests_v3/test_waterfront_lan.gd"


def atomic_json(path: Path, value: object) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    deadline = time.monotonic() + 0.5
    while True:
        try:
            os.replace(temporary, path)
            return
        except PermissionError:
            if time.monotonic() >= deadline:
                raise
            time.sleep(0.01)


def distance(a: object, b: object) -> float:
    if not isinstance(a, list) or not isinstance(b, list) or len(a) != 3 or len(b) != 3:
        return math.inf
    return math.sqrt(sum((float(x) - float(y)) ** 2 for x, y in zip(a, b)))


class Run:
    def __init__(self, engine: Path, evidence: Path, lock: LanPortLock) -> None:
        self.engine, self.evidence, self.lock = engine, evidence, lock
        self.run_id = evidence.name
        self.profiles = {role: f"qa_waterfront_lan_{role}_{self.run_id}" for role in ("host", "guest")}
        self.processes: dict[str, tuple[subprocess.Popen, object]] = {}
        self.sequences = {"host": 0, "guest": 0}
        self.before = source_fingerprints(ROOT)
        self.before["tests_v3/test_waterfront_lan.gd"] = file_sha256(ROOT / "tests_v3/test_waterfront_lan.gd")
        self.before["scripts_tools/v3/test_waterfront_lan.py"] = file_sha256(Path(__file__))
        self.deadline = time.monotonic() + 80.0
        self.summary = {
            "run_id": self.run_id, "started_utc": utc_now(), "passed": False,
            "scope": "source-only two real MAIN instances, same-computer real ENet; voted I1-to-I2 travel and actual water force/rescue authority",
            "limitations": ["Not two-computer LAN, release-PCK, human input, graphics or performance evidence.",
                            "Saved predecessor action history and one collision-checked host deep-water pose are fixtures.",
                            "Normal process/physics/input RPC are retained; no injected received packet, water timer, damage result or continuing freeze.",
                            "No delayed facility packets are injected. A naturally absent waiting interval is explicitly NOT_COVERED."],
            "engine": str(engine), "engine_sha256": file_sha256(engine), "profiles": self.profiles,
            "lock": {"path": str(lock.path), "port": 26742, "backend": lock.backend},
            "hard_tree_limit_seconds": 90, "checks": [], "processes": {},
            "source_before": self.before, "error": None,
        }
        self.heartbeat()

    def heartbeat(self) -> None:
        if time.monotonic() >= self.deadline:
            raise TimeoutError("80-second controller deadline; outer owned Job Object remains bounded at 90s")
        atomic_json(self.evidence / "controller.json", {"run_id": self.run_id, "pid": os.getpid(),
                    "exclusive_port": 26742, "profiles": self.profiles, "heartbeat_unix": time.time()})

    def launch(self, role: str) -> None:
        if self.lock.stream is None:
            raise RuntimeError("No exclusive LAN port lock")
        command = [str(self.engine), "--headless", "--path", str(ROOT), "--script", PROBE, "--",
                   f"--qa-profile={self.profiles[role]}", f"--waterfront-role={role}",
                   f"--waterfront-run={self.run_id}", f"--waterfront-evidence={self.evidence}"]
        log = (self.evidence / f"{role}.log").open("xb")
        try:
            process = subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, **process_options())
        except BaseException:
            log.close()
            raise
        self.processes[role] = (process, log)
        self.summary["processes"][role] = {"pid": process.pid, "command": command, "forced_stop": False}
        print(f"START {role} pid={process.pid}", flush=True)

    def read(self, role: str) -> dict:
        try:
            result = json.loads((self.evidence / f"{role}-state.json").read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return {}
        if not isinstance(result, dict):
            return {}
        if result.get("run_id") != self.run_id or result.get("role") != role or result.get("profile") != self.profiles[role]:
            raise RuntimeError(f"{role} report identity mismatch")
        if result.get("errors") or result.get("engine_errors"):
            raise RuntimeError(f"{role} probe failed: {result.get('errors')} {result.get('engine_errors')}")
        return result

    def wait(self, role: str, predicate, description: str, timeout: float = 15.0) -> dict:
        until = min(self.deadline, time.monotonic() + timeout)
        while time.monotonic() < until:
            self.heartbeat()
            state = self.read(role)
            if state and predicate(state):
                return state
            if self.processes[role][0].poll() is not None:
                raise RuntimeError(f"{role} exited before {description}")
            time.sleep(0.025)
        raise TimeoutError(f"{role}: {description}")

    def request(self, role: str, verb: str) -> dict:
        self.sequences[role] += 1
        sequence = self.sequences[role]
        atomic_json(self.evidence / f"{role}-command.json", {"run_id": self.run_id, "sequence": sequence, "verb": verb})
        state = self.wait(role, lambda s: s.get("ack", 0) >= sequence, verb)
        self.check(f"{role} {verb} dispatched", state.get("result", {}).get("ok") is True, state.get("result"))
        return state

    def check(self, label: str, passed: bool, actual: object = None) -> None:
        self.summary["checks"].append({"check": label, "passed": bool(passed), "actual": actual})
        if not passed:
            raise AssertionError(f"{label}: {actual}")

    def save(self, name: str, **states: dict) -> None:
        atomic_json(self.evidence / f"{name}.json", states)

    @staticmethod
    def subject(state: dict) -> dict:
        return state.get("roster", {}).get(str(state.get("subject")), {})

    def exercise(self) -> None:
        self.launch("host")
        self.wait("host", lambda s: s.get("ready") and s.get("region") == "I1", "real host MAIN I1 ready", 25)
        self.launch("guest")
        guest_i1 = self.wait("guest", lambda s: s.get("ready") and s.get("region") == "I1"
                             and len(s.get("roster", {})) == 2 and s.get("old_targets_max", 0) >= 2
                             and len(s.get("old_roster", {})) == 2, "guest accepts actual I1 targets before travel", 25)
        host_i1 = self.wait("host", lambda s: len(s.get("roster", {})) == 2, "host sees connected guest")
        for role, state in (("host", host_i1), ("guest", guest_i1)):
            self.check(f"{role} real MAIN path and role flags on spawn",
                       state.get("main_node") == "/root/TwinPulseSession"
                       and state.get("network_node") == "/root/TwinPulseSession/Network"
                       and all(p.get("authority") is (role == "host") for p in state["roster"].values()), state["roster"])
        self.save("01-connected-I1", host=host_i1, guest=guest_i1)
        self.request("host", "travel")
        self.wait("guest", lambda s: s.get("proposal", {}).get("kind") == "region_change", "real travel proposal arrives")
        self.request("guest", "confirm")
        host_i2 = self.wait("host", lambda s: s.get("ready") and s.get("region") == "I2" and s.get("arrival"), "host adopts I2", 20)
        guest_i2 = self.wait("guest", lambda s: s.get("ready") and s.get("region") == "I2" and s.get("arrival")
                             and s.get("sequence", -1) > guest_i1["sequence"] and s.get("remote_targets", 0) == 2,
                             "same guest accepts new-region motion after facilities", 20)
        self.check("existing guest targets cleared during actual old-world exit",
                   guest_i2.get("old_world_exit", {}).get("remote_targets") == 0
                   and guest_i2["old_world_exit"].get("old_targets_observed", 0) >= 2, guest_i2.get("old_world_exit"))
        for role, state, old in (("host", host_i2, host_i1), ("guest", guest_i2, guest_i1)):
            arrival = state["arrival"]["roster"]
            self.check(f"{role} same bodies adopted with new safe points and correct authority",
                       set(arrival) == set(old["roster"])
                       and all(p["instance_id"] == old["roster"][peer]["instance_id"]
                               and p["authority"] is (role == "host")
                               and distance(p["safe"], [-20 + (int(peer) % 2) * 3, 3, 18]) < 0.001
                               and p["water_seconds"] == 0 and p["water_contact"] is False
                               for peer, p in arrival.items()), arrival)
        self.check("observed unavailable-facility frames do not move using old targets", not guest_i2.get("wait_violations"), guest_i2.get("wait_violations"))
        self.summary["facility_wait_coverage"] = {"status": guest_i2["wait_coverage"], "frames": guest_i2["wait_frames"],
                                                  "before_first_I2_accept": guest_i2["wait_frames"] - guest_i2["wait_after_accept_frames"],
                                                  "after_first_I2_accept": guest_i2["wait_after_accept_frames"],
                                                  "samples": guest_i2["wait_samples"],
                                                  "limitation": "No artificial reliable-packet delay; zero natural frames does not verify the waiting branch."}
        self.save("02-voted-I2", host=host_i2, guest=guest_i2)
        self.request("host", "arm")
        self.request("guest", "arm")
        self.request("guest", "zero_throttle")
        self.wait("host", lambda s: s.get("zero_input_rpc_count", 0) >= 3, "actual guest zero-throttle input RPC received")
        placed = self.request("host", "place_deep")
        self.check("single deep-water fixture preserves I2 checkpoint", placed.get("placed") is True
                   and distance(placed["placement"]["point"], [14.75, -2.2, 20]) < 0.001
                   and distance(placed["placement"]["safe_before"], host_i2["arrival"]["roster"][str(placed["subject"])]["safe"]) < 0.001, placed["placement"])
        rescued = self.wait("host", lambda s: len(s.get("rescue_events", [])) == 1, "actual timed water rescue", 10)
        predicted = self.wait("guest", lambda s: s.get("actual_water_samples", 0) > 0 and s.get("wet_integrated_steps", 0) > 0, "local prediction physically entered sampled water", 3)
        self.save("03-real-water-rescue", host=rescued, guest=predicted)
        self.request("guest", "assisted")
        expected = rescued["placement"]["expected_damage"]
        actual = rescued["rescue_events"][0]["receipt"]
        self.check("host rescue has its actual unambiguous damage receipt",
                   len(rescued["damage_receipts"]) == 1 and len(rescued["local_damage_events"]) == 1
                   and actual.get("weapon_type") == "collision" and actual.get("combat") is False
                   and actual.get("pilot_target") is True
                   and all(math.isclose(float(actual[k]), float(expected[k]), abs_tol=1e-5)
                           for k in ("raw_damage", "damage", "health_before", "health", "armor_before", "armor", "armor_absorbed", "shield_absorbed", "serial")),
                   {"expected_preview": expected, "actual_receipt": actual})
        self.check("host applied real immersion duration, forces and exactly one rescue",
                   len(rescued["rescue_events"]) == 1 and len(rescued["water_events"]) >= 1
                   and rescued["rescue_events"][0]["flight_seconds"] - rescued["water_events"][0]["flight_seconds"] > 2.45
                   and rescued["wet_integrated_steps"] >= 140 and rescued["wet_maximum_thrust"] < 1e-6
                   and rescued["zero_input_rpc_count"] >= 100
                   and self.subject(rescued)["collisions"] == rescued["placement"]["collision_count"], rescued)
        host_final = self.wait("host", lambda s: s.get("rescue_minimum_distance", 999) < 0.2, "host actual rescue checkpoint transform")
        guest_final = self.wait("guest", lambda s: math.isclose(float(self.subject(s).get("health", -1)), float(actual["health"]), abs_tol=1e-5)
                               and self.subject(s).get("position", [0, -999, 0])[1] > 1.0, "guest receives host rescue health and position", 5)
        self.check("prediction receives health but commits no local damage or rescue",
                   not guest_final["rescue_events"] and not guest_final["damage_receipts"] and not guest_final["local_damage_events"]
                   and len(guest_final["water_events"]) >= 1 and guest_final["wet_integrated_steps"] >= 100
                   and guest_final["wet_maximum_thrust"] < 1e-6 and guest_final["actual_water_samples"] >= 100
                   and self.subject(guest_final)["authority"] is False, guest_final)
        self.check("guest arrival and rescued pose remain in I2, not old I1 checkpoint",
                   distance(self.subject(guest_final)["safe"], guest_i2["arrival"]["roster"][str(guest_final["subject"])]["safe"]) < 0.001
                   and -28 <= self.subject(guest_final)["position"][0] <= 28
                   and -28 <= self.subject(guest_final)["position"][2] <= 28, self.subject(guest_final))
        self.save("04-authoritative-snapshot", host=host_final, guest=guest_final)
        self.wait("host", lambda s: s.get("last_input_rpc", {}).get("mode") == "assisted"
                  and self.subject(s).get("command_mode") == "assisted"
                  and self.subject(s).get("command_active") is True, "host receives resumed assisted input RPC", 3)
        self.wait("guest", lambda s: self.subject(s).get("command_mode") == "assisted"
                  and self.subject(s).get("command_active") is True, "guest resumes normal assisted prediction", 3)
        self.request("host", "observe_recovery")
        self.request("guest", "observe_recovery")
        recovery = {}
        for role in ("host", "guest"):
            state = self.wait(role, lambda s: len(s.get("recovery_samples", [])) >= 61
                              and s["recovery_samples"][-1]["flight_seconds"] - s["recovery_samples"][0]["flight_seconds"] >= 1.0,
                              "one second of actual assisted recovery integration", 5)
            samples = state["recovery_samples"]
            # Let the normal controller settle for ~0.5s, then judge a further
            # >=0.5s integrated window. A network pose alone cannot pass this:
            # the stale underwater hold target would retain downward velocity.
            end_time = samples[-1]["flight_seconds"]
            tail = [row for row in samples if end_time - row["flight_seconds"] <= 0.52]
            safe_y = float(self.subject(state)["safe"][1])
            ys = [row["position"][1] for row in tail]
            self.check(f"{role} resumed assisted flight stays dry and stable for >=0.5 real seconds",
                       len(tail) >= 31 and tail[-1]["flight_seconds"] - tail[0]["flight_seconds"] >= 0.5
                       and max(ys) - min(ys) < 0.35
                       and all(row["mode"] == "assisted" and row["active"] is True
                               and row["water_contact"] is False and abs(row["water_seconds"]) < 1e-6
                               and row["position"][1] > safe_y + 0.3 and row["hold_height"] > safe_y
                               and abs(row["hold_height"] - row["position"][1]) < 0.6
                               and abs(row["velocity"][1]) < 1.0
                               and math.isclose(row["health"], actual["health"], abs_tol=1e-5)
                               for row in tail), {"safe_y": safe_y, "tail": tail})
            recovery[role] = state
        self.check("assisted recovery did not trigger another authoritative or predicted rescue",
                   len(recovery["host"]["rescue_events"]) == 1 and len(recovery["host"]["damage_receipts"]) == 1
                   and not recovery["guest"]["rescue_events"] and not recovery["guest"]["damage_receipts"],
                   {role: {key: recovery[role][key] for key in ("rescue_events", "damage_receipts")} for role in recovery})
        self.check("facility waits remained frozen throughout water and recovery stages",
                   not recovery["guest"]["wait_violations"], recovery["guest"]["wait_violations"])
        self.save("05-assisted-recovery", **recovery)
        self.request("guest", "shutdown")
        self.natural_exit("guest")
        self.request("host", "shutdown")
        self.natural_exit("host")

    def natural_exit(self, role: str) -> None:
        process, log = self.processes[role]
        until = min(self.deadline, time.monotonic() + 5.0)
        while process.poll() is None and time.monotonic() < until:
            self.heartbeat()
            time.sleep(0.025)
        self.summary["processes"][role]["returncode"] = process.poll()
        self.check(f"{role} natural exit", process.poll() == 0, process.poll())
        log.close()

    def finish(self) -> None:
        for role, (process, log) in self.processes.items():
            if process.poll() is None:
                self.summary["processes"][role]["forced_stop"] = True
                process.kill()  # Exact owned process handle; the outer Job covers descendants.
                try:
                    process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    pass
            self.summary["processes"][role]["returncode"] = process.poll()
            if not log.closed:
                log.close()
            text = (self.evidence / f"{role}.log").read_text(encoding="utf-8", errors="replace")
            bad = [line for line in text.splitlines() if line.startswith(("ERROR:", "SCRIPT ERROR:"))]
            self.summary["checks"].append({"check": f"{role} engine log clean", "passed": not bad, "actual": bad})
        after = source_fingerprints(ROOT)
        after["tests_v3/test_waterfront_lan.gd"] = file_sha256(ROOT / "tests_v3/test_waterfront_lan.gd")
        after["scripts_tools/v3/test_waterfront_lan.py"] = file_sha256(Path(__file__))
        self.summary["source_after"] = after
        self.summary["checks"].append({"check": "source inputs stayed frozen", "passed": after == self.before})
        self.summary["finished_utc"] = utc_now()
        self.summary["passed"] = self.summary["error"] is None and all(c["passed"] for c in self.summary["checks"]) and all(not p["forced_stop"] for p in self.summary["processes"].values())
        atomic_json(self.evidence / "summary.json", self.summary)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--godot", type=Path, default=Path(os.environ.get("LOCALAPPDATA", "")) / "Programs/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe")
    parser.add_argument("--controller", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--evidence", type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()
    if not args.run:
        print("PREPARATION ONLY: --run is required; no engine, network or lock started.")
        return 0
    engine = args.godot.resolve()
    if os.name != "nt" or not engine.is_file():
        parser.error("Requires this project's Windows Godot executable and owned Job Object runner")
    if not args.controller:
        import dev
        run_id = datetime.now().strftime("%Y%m%d_%H%M%S_") + uuid.uuid4().hex[:6]
        evidence = ROOT / "artifacts/v3/network/waterfront" / run_id
        evidence.mkdir(parents=True, exist_ok=False)
        command = [sys.executable, "-B", str(Path(__file__).resolve()), "--run", "--controller", "--godot", str(engine), "--evidence", str(evidence)]
        began = time.monotonic()
        with (evidence / "controller.log").open("xb", buffering=0) as output:
            bounded = dev._windows_run(command, output, 90)
        bounded["elapsed_seconds"] = round(time.monotonic() - began, 3)
        bounded["hard_limit_seconds"] = 90
        atomic_json(evidence / "bounded_process.json", bounded)
        print(json.dumps({"evidence": str(evidence), "bounded": bounded}, ensure_ascii=False))
        return 0 if bounded["returncode"] == 0 and not bounded["timed_out"] and not bounded["orphan_cleanup"] else int(bounded["returncode"] or 1)
    evidence = args.evidence.resolve() if args.evidence else None
    allowed = (ROOT / "artifacts/v3/network/waterfront").resolve()
    if evidence is None or evidence.parent != allowed or not evidence.is_dir():
        parser.error("Internal controller needs its exact unique evidence directory")
    lock = LanPortLock()
    try:
        lock.acquire()
    except LanRunBusy as error:
        print(f"REFUSED: {error}", flush=True)
        return 3
    run = None
    try:
        run = Run(engine, evidence, lock)
        try:
            run.exercise()
        except BaseException as error:
            run.summary["error"] = f"{type(error).__name__}: {error}"
            (evidence / "failure.log").write_text(traceback.format_exc(), encoding="utf-8")
        finally:
            run.finish()
        print(json.dumps({"passed": run.summary["passed"], "checks": len(run.summary["checks"]), "error": run.summary["error"], "facility_wait": run.summary.get("facility_wait_coverage")}, ensure_ascii=False), flush=True)
        return 0 if run.summary["passed"] else 1
    finally:
        lock.release()


if __name__ == "__main__":
    raise SystemExit(main())
