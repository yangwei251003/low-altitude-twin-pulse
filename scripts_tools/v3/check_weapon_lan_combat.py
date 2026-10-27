#!/usr/bin/env python3
"""Actual debug EXE, ordinary MAIN, one remote Crown burst; loopback, not two PCs."""
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
ROOT = next(parent for parent in Path(__file__).resolve().parents
            if (parent / "scripts_tools/v3/dev.py").is_file())
sys.path.insert(0, str(ROOT / "scripts_tools/v3"))
import dev
from test_lan_local import LanPortLock, LanRunBusy, process_options, utc_now
from check_lan_environment import write_json, read_json, sha256

SUITE = "weapon-lan-combat"
PROTOCOL = 25
CORE = "boss:crown_core"
JOB_SECONDS = 90
WORKER_SECONDS = 85
B = {"airframe_id": "tr01", "slots": {"weapon": "burst_capacitor", "tool": "scan_base",
     "drive": "stock_drive", "battery": "stock_battery", "utility": "cooling_duct"}}


class Run:
    def __init__(self, args, lock):
        self.args, self.lock = args, lock
        self.exe = args.exe.resolve()
        self.output = self.exe.parent / "artifacts/v3/network/weapon-combat" / args.run_id
        self.began = time.monotonic()
        self.deadline = self.began + WORKER_SECONDS
        self.children, self.sequences = {}, {}
        self.writes = {"writes": 0, "retries": 0, "retry_elapsed_seconds": 0.0,
                       "max_replace_elapsed_seconds": 0.0, "events": [], "final_error": None}
        self.summary = {"suite": SUITE, "protocol": PROTOCOL, "run_id": args.run_id,
            "started_utc": utc_now(), "executable": str(self.exe), "executable_sha256": sha256(self.exe),
            "processes": {}, "checks": [], "milestones": {}, "error": None, "passed": False,
            "limits": {"peer_wall_seconds": 80, "worker_wall_seconds": WORKER_SECONDS,
                       "private_owned_job_seconds": JOB_SECONDS}, "atomic_writes": self.writes,
            "scope": "Actual packaged ordinary MAIN, two real ENet loopback peers, original Hangar ownership fixture and development Crown start; one original held-fire burst and owner HUD. Not natural history, two-PC LAN, whole fight, reward or cold restore.",
            "lock": {"path": str(lock.path), "port": 26742, "backend": lock.backend}}

    def state(self, role):
        return read_json(self.output / (role + "-state.json"))

    def beat(self):
        write_json(self.output / "controller.json", {"suite": SUITE, "run_id": self.args.run_id,
            "port": 26742, "lock_held": self.lock.stream is not None,
            "controller_pid": os.getpid(), "heartbeat_unix": time.time()}, self.writes)

    def check(self, label, passed, detail=None):
        self.summary["checks"].append({"label": label, "passed": bool(passed), "detail": detail})
        if not passed:
            raise AssertionError(label)

    def wait(self, label, predicate, seconds=10, required=("host", "guest")):
        deadline = min(self.deadline, time.monotonic() + seconds)
        while time.monotonic() < deadline:
            self.beat()
            for role in required:
                process, log = self.children[role]
                value = self.state(role)
                if value:
                    if value.get("errors"):
                        raise AssertionError(f"{role} engine/QA errors: {value['errors']}")
                    if (value.get("suite") != SUITE or value.get("protocol") != PROTOCOL
                        or value.get("contract") != 1 or value.get("run_id") != self.args.run_id
                        or value.get("role") != role or value.get("pid") != process.pid
                        or value.get("actual_package") is not True
                        or os.path.normcase(str(Path(value.get("executable", "")).resolve())) != os.path.normcase(str(self.exe))):
                        raise AssertionError(role + " actual package/identity mismatch")
                if process.poll() is not None:
                    raise AssertionError(role + f" exited {process.returncode} during " + label)
            if predicate():
                return
            time.sleep(.03)
        self.summary["milestones"]["timeout_" + label] = {role: self.state(role) for role in required}
        raise TimeoutError(label)

    def milestone(self, label):
        self.summary["milestones"][label] = {role: self.state(role) for role in self.children}
        write_json(self.output / "summary.json", self.summary)
        print("WEAPON_LAN " + label, flush=True)

    def launch(self, role):
        self.beat()
        command = [str(self.exe), "--headless"] + (["--verbose"] if self.args.verbose else [])
        command += ["--", "--qa-suite=" + SUITE,
            "--qa-profile=qa_lan_weapon_" + role + "_" + self.args.run_id,
            "--qa-lan-weapon-role=" + role, "--qa-lan-weapon-run=" + self.args.run_id,
            "--qa-lan-weapon-evidence=" + str(self.output)]
        log = (self.output / (role + ".log")).open("xb")
        try:
            process = subprocess.Popen(command, cwd=self.exe.parent, stdout=log,
                                       stderr=subprocess.STDOUT, **process_options())
        except BaseException:
            log.close()
            raise
        self.children[role] = (process, log)
        self.summary["processes"][role] = {"pid": process.pid, "command": command,
            "cwd": str(self.exe.parent), "started_utc": utc_now(), "forced_stop": False}

    def command(self, role, verb):
        sequence = self.sequences.get(role, 0) + 1
        self.sequences[role] = sequence
        write_json(self.output / (role + "-command.json"), {"run_id": self.args.run_id,
            "sequence": sequence, "verb": verb}, self.writes)
        if verb == "shutdown":
            return sequence
        self.wait(role + "_" + verb, lambda: self.state(role).get("ack") == sequence,
                  required=(role,))
        self.check(role + "." + verb, self.state(role).get("result", {}).get("ok") is True,
                   self.state(role).get("result"))
        return sequence

    def stop(self, role):
        process, log = self.children[role]
        if log.closed:
            return
        record = self.summary["processes"][role]
        sequence = self.command(role, "shutdown") if process.poll() is None else None
        deadline = min(self.deadline, time.monotonic() + 8)
        try:
            while process.poll() is None and time.monotonic() < deadline:
                self.beat()
                time.sleep(.03)
            if process.poll() is None:
                record["forced_stop"] = True
                process.terminate()
                try:
                    process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=2)
        finally:
            log.close()
            record.update(exit_code=process.poll(), finished_utc=utc_now(), final_state=self.state(role))
        text = (self.output / (role + ".log")).read_text(encoding="utf-8", errors="replace")
        bad = [line for line in text.splitlines() if "ERROR:" in line or "SCRIPT ERROR:" in line
               or "resources still in use at exit" in line
               or ("objectdb" in line.lower() and "leak" in line.lower())]
        record["engine_or_cleanup_errors"] = bad
        self.check(role + ".clean_original_quit", process.returncode == 0 and not record["forced_stop"]
                   and not bad and sequence is not None and record["final_state"].get("ack") == sequence
                   and record["final_state"].get("result", {}).get("ok") is True, record)

    def scenario(self):
        self.launch("host")
        self.wait("original_F1_ready", lambda: self.state("host").get("ready") is True, 25, ("host",))
        self.launch("guest")
        self.wait("original_guest_snapshot", lambda: self.state("guest").get("received_sequence", -1) >= 0
                  and self.state("guest").get("region") == "F1"
                  and self.state("guest").get("facilities_ready") is True
                  and len(self.state("guest").get("players", {})) == 2, 25)
        host, guest = self.state("host"), self.state("guest")
        peer = str(guest["local_peer"])
        setup = guest.get("guest_setup", {})
        self.check("actual_local_Hangar_Store_and_two_distinct_UUIDs", setup.get("hardware") == B
            and setup.get("reader_equal") is True and setup.get("world_unchanged") is True
            and setup.get("earned_campaign") is False
            and len(guest.get("profile_uuid", "")) == 32 and guest["profile_uuid"] != host.get("profile_uuid"), setup)
        self.check("real_UUID_B_handshake_and_original_snapshot", bool(host.get("session_id"))
            and guest.get("session_id") == host["session_id"]
            and host.get("announced_guest_hardware", {}).get(peer) == B
            and host["players"][peer]["hardware"] == guest["players"][peer]["hardware"] == B
            and host["players"][peer]["identity"] == guest["profile_uuid"], host["players"][peer])
        self.milestone("actual_departure_and_ENet")
        self.command("host", "prepare_crown")
        self.wait("real_light_growth_open", lambda: self.state("host").get("prepared", {}).get("ok") is True)
        self.check("real_Crown_original_HP_and_development_scope", self.state("host")["prepared"].get("core_hp_milli") == 160000
            and self.state("host")["prepared"].get("core_open") is True
            and self.state("host").get("boss_campaign") is False, self.state("host")["prepared"])
        self.command("guest", "lock_core")
        self.wait("original_reliable_core_lock", lambda: self.state("host").get("locks", {}).get(peer) == CORE
                  and self.state("guest").get("locks", {}).get(peer) == CORE)
        self.command("guest", "hold_once")
        self.wait("original_host_hit_and_nonzero_owner_HUD", lambda: bool(self.state("host").get("hit_receipt"))
                  and bool(self.state("guest").get("hot_owner")))
        host, guest = self.state("host"), self.state("guest")
        hit, hot = host["hit_receipt"], guest["hot_owner"]
        cycle = hit.get("cycle", {})
        profile = cycle.get("profile", {})
        self.check("original_remote_held_input_hit28_exact32heat_1second_once", hit.get("delta_milli") == 28000
            and hit.get("after_hp_milli") == 132000 and hit.get("body_heat") == 32
            and cycle.get("heat") == 32 and cycle.get("cooldown_s") == 1
            and cycle.get("accepted_shots") == 1 and cycle.get("declined_shots") == 0
            and hit.get("original_shot_sequence") == hit.get("original_player_sequence") == 1
            and hit.get("original_input_sequence", -1) > 0 and hit.get("native_command", {}).get("fire") is True
            and hit.get("identity") == guest["profile_uuid"]
            and profile.get("damage") == 28 and profile.get("charge_s") == .7
            and profile.get("heat_per_shot") == 32 and profile.get("cooling_per_s") == 20
            and profile.get("build_hash") == host["players"][peer].get("build_hash") == guest["players"][peer].get("build_hash")
            and hit.get("charged_frame_span", 0) >= 42, hit)
        view = hot.get("view", {})
        self.check("original_reliable_owner_nonzero_heat_and_native_Label", view.get("weapon_id") == "burst_capacitor"
            and 0 < view.get("heat", 0) <= 32 and view.get("capacity") == 100
            and view.get("charge_max_s") == .7 and view.get("charge_s") == 0
            and 0 < view.get("cooldown_s", 0) <= 1 and hot.get("serial", -1) >= 0
            and hot.get("session_id") == host["session_id"] and hot.get("local_cycle_count") == 0
            and hot.get("hud_visible") is True and "蓄能炮" in hot.get("hud", "")
            and "热量 0 /" not in hot.get("hud", "") and "正在同步" not in hot.get("hud", ""), hot)
        self.command("guest", "release")
        self.wait("released_more_than_complete_cooldown_and_charge", lambda: self.state("host").get("physics_frame", 0) >= hit["physics_frame"] + 132
                  and self.state("host")["players"][peer].get("command_fire") is False
                  and self.state("guest").get("holding") is False)
        self.check("release_prevents_a_second_original_hit", len(self.state("host").get("hp_changes", [])) == 1
            and self.state("host")["boss"].get("core_hp_milli") == 132000
            and self.state("host").get("stats", {}).get("shots") == 1, self.state("host").get("hp_changes"))
        self.command("host", "pause")
        self.wait("guest_received_pause_vote", lambda: self.state("guest").get("proposal", {}).get("kind") == "pause")
        self.check("pause_two_real_participants", len(self.state("guest")["proposal"].get("participants", [])) == 2)
        self.command("guest", "confirm")
        self.wait("original_common_pause", lambda: self.state("host").get("paused") is True
                  and self.state("guest").get("paused") is True
                  and not self.state("host").get("proposal") and not self.state("guest").get("proposal"))
        frozen = self.state("host")
        self.wait("paused_native_observation_frames", lambda: self.state("host").get("physics_frame", 0) >= frozen["physics_frame"] + 18)
        after = self.state("host")
        self.check("pause_preserves_original_HP_and_same_weapon_clock", after["boss"].get("core_hp_milli") == 132000
            and len(after.get("hp_changes", [])) == 1 and after.get("cycle") == frozen.get("cycle"),
            {"before_cycle": frozen.get("cycle"), "after_cycle": after.get("cycle")})
        self.check("original_codec_has_no_rejections", after.get("transport", {}).get("snapshot_encode_rejections") == 0
            and after.get("transport", {}).get("snapshots_sent", 0) > 0, after.get("transport"))
        self.milestone("single_remote_hit_release_and_common_pause")
        self.stop("guest")
        self.wait("original_guest_departure", lambda: len(self.state("host").get("players", {})) == 1,
                  required=("host",))
        self.stop("host")

    def execute(self):
        try:
            self.scenario()
        except BaseException as error:
            self.summary["error"] = f"{type(error).__name__}: {error}"
            (self.output / "orchestration-error.log").write_text(traceback.format_exc(), encoding="utf-8")
        finally:
            for role in reversed(list(self.children)):
                try:
                    self.stop(role)
                except BaseException as error:
                    self.summary.setdefault("cleanup_errors", []).append(f"{role}: {error}")
            self.summary["executable_sha256_after"] = sha256(self.exe)
            self.summary["elapsed_wall_seconds"] = time.monotonic() - self.began
            self.summary["all_owned_processes_exited"] = all(p.poll() is not None for p, log in self.children.values())
            self.summary["passed"] = bool(not self.summary["error"] and not self.summary.get("cleanup_errors")
                and len(self.children) == 2 and self.summary["all_owned_processes_exited"]
                and self.summary["executable_sha256_after"] == self.summary["executable_sha256"]
                and all(row["passed"] for row in self.summary["checks"]))
            write_json(self.output / "summary.json", self.summary)
        print(json.dumps({"passed": self.summary["passed"], "error": self.summary["error"],
                          "evidence": str(self.output), "scope": self.summary["scope"]}, ensure_ascii=False), flush=True)
        return 0 if self.summary["passed"] else 1


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exe", type=Path, required=True)
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--verbose", action="store_true")
    parser.add_argument("--owned-worker", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--run-id", default="", help=argparse.SUPPRESS)
    args = parser.parse_args()
    if not args.exe.is_absolute() or not args.exe.is_file() or args.exe.suffix.lower() != ".exe":
        parser.error("existing absolute exported Windows EXE required")
    if not args.run:
        print(json.dumps({"status": "prepared_no_process_or_port_lock", "suite": SUITE,
            "executable": str(args.exe), "sha256": sha256(args.exe), "protocol": PROTOCOL,
            "requires": "Root promotes observer/App entry and exports; ordinary EXE main, no --script or --path",
            "scope": "two peers on one computer, not two PCs or full fight"}, ensure_ascii=False))
        return 0
    if not args.owned_worker:
        run_id = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
        output = args.exe.parent / "artifacts/v3/network/weapon-combat" / run_id
        output.mkdir(parents=True, exist_ok=False)
        dev.EVIDENCE = output / "driver"
        command = [sys.executable, "-B", str(Path(__file__).resolve()), "--exe", str(args.exe),
                   "--run", "--owned-worker", "--run-id", run_id] + (["--verbose"] if args.verbose else [])
        dev.execute_command(command, "controller", JOB_SECONDS)
        summary = read_json(output / "summary.json")
        print(json.dumps({"passed": summary.get("passed", False), "evidence": str(output),
                          "error": summary.get("error")}, ensure_ascii=False))
        return 0 if summary.get("passed") is True else 1
    import re
    if not re.fullmatch(r"[0-9]{8}_[0-9]{6}_[0-9]{6}", args.run_id):
        parser.error("exact owned run ID required")
    lock = LanPortLock()
    try:
        lock.acquire()
    except LanRunBusy as error:
        print(str(error))
        return 3
    try:
        return Run(args, lock).execute()
    finally:
        lock.release()


if __name__ == "__main__":
    raise SystemExit(main())
