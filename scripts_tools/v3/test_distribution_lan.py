#!/usr/bin/env python3
"""Controlled Distribution ENet loopback using one shared source/package Node probe; not two-computer LAN.

Default is preparation only and starts no Godot process. After shared-code/layout freeze:
  python scripts_tools/v3/test_distribution_lan.py --run --expected-distribution-sha <frozen SHA256>
Both source and package use the application router. Add --standalone
--godot <exported EXE> for the PCK entry (no --script and no --path).
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

sys.dont_write_bytecode = True
# This exact OS-owned lock also excludes the existing source/standalone LAN suite.
from test_lan_local import (LanPortLock, LanRunBusy, file_sha256, process_options,
                            source_fingerprints, utc_now)

COVER = "I2:distribution_cover"
RELAY = "I2:distribution_relay"
LOCK = "I2:distribution_lock"
DISCOVERY = "I2:distribution_back_route"
FORMAL_OBJECTIVE = "I2:distribution_audit:expose"
MODEL = "data/v3/terrain/i2_distribution_layout.json"
EXPECTED_SCENARIOS = 3
FACILITY_IDS = ("clinic", "distribution", "trial", "shared_access")


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
    extras = [project / "scripts_tools/v3/test_distribution_lan.py"]
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
        self.evidence = self.runtime_cwd / "artifacts/v3/network/distribution" / self.run_id
        if self.evidence.resolve() != self.evidence:
            raise RuntimeError("Evidence path must not redirect outside the exact runtime run directory")
        self.evidence.mkdir(parents=True, exist_ok=False)
        self.profiles = {"host": f"qa_distribution_lan_host_{self.run_id}",
                         "guest": f"qa_distribution_lan_guest_{self.run_id}"}
        self.processes: dict[str, tuple[subprocess.Popen, object]] = {}
        self.command_sequences: dict[str, int] = {}
        self.summary = {
            "schema_version": 1, "run_id": self.run_id, "started_utc": utc_now(),
            "scope": "same-computer two-process real ENet loopback, scripted poses; not physical two-computer LAN",
            "limitations": ["No human play, GPU, performance, remote-PC/router/firewall acceptance; no artificial latency or loss injection.",
                            "Previous27 goals are explicit saved Director fixtures. The ninth action now exists but its completed-clinic prerequisite is unmet here; this suite must prove no premature EXPOSE objective or discovery reward.",
                            "Pilots are frozen at collision-checked scripted starting poses. Low-door travel uses the actual host FlightBody.move_and_collide; this is not normal flight feel.",
                            "Observation, abilities, reliable states, receipts and reconnect use production RPC. The only save fault is Store.before_publish. No cabinet fraction/history/completion or received packet is injected.",
                            "The electric route demonstrates its own actual ten-ray proof but must preserve the first manual history; it is not a second independent campaign completion."],
            "project": str(project), "godot": str(godot), "distribution_sha256": sha,
            "qa_suite": "distribution-lan", "entry_kind": entry_kind,
            "runtime_cwd": str(self.runtime_cwd), "source_path_passed": entry_kind != "package_main",
            "script_override_passed": False,
            "executable_sha256_before": file_sha256(godot), "source_sha256_before": fingerprints(project),
            "lock": {"path": str(lock.path), "port": 26742, "pid": os.getpid(), "backend": lock.backend},
            "profiles": self.profiles, "scenarios": [], "checks": [], "processes": {}, "passed": False,
        }
        self.heartbeat()

    def heartbeat(self) -> None:
        if time.monotonic() >= self.hard_deadline:
            raise TimeoutError("Distribution controller hard220-second limit reached")
        atomic_json(self.evidence / "controller.json", {
            "run_id": self.run_id, "pid": os.getpid(), "lock_held": self.lock.stream is not None,
            "heartbeat_unix": time.time(), "distribution_sha256": self.sha,
            "qa_suite": "distribution-lan", "entry_kind": self.entry_kind,
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
        return (state.get("qa_suite") == "distribution-lan"
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
        user_args = ["--qa-suite=distribution-lan", f"--qa-profile={self.profiles[role]}",
                     f"--qa-distribution-role={role}", f"--qa-distribution-label={label}",
                     f"--qa-distribution-run={self.run_id}", f"--qa-distribution-evidence={self.evidence}",
                     f"--qa-distribution-sha={self.sha}"]
        if reconnect:
            user_args.append("--qa-distribution-reconnect")
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
                and probe.get("water_ready") is True
                and probe.get("water_parts") == 11 and probe.get("water_pose_error", 999) < 0.001
                and probe.get("maximum_pose_error", 999) < 0.001
                and probe.get("target_error", 999) < 0.001
                and (not probe.get("door_endpoint") or probe.get("door_ray_correct") is True))

    @staticmethod
    def valid_facility_proof(observation: object) -> bool:
        """Check the actual probe's four independent reliable/physical proofs.

        Do not trust only its aggregate flag, invent fixed body counts or
        tighten clinic/cabinet's compatible-older-serial production semantics.
        """
        def counter(value: object) -> bool:
            return (type(value) in (int, float) and 0 < value <= 9007199254740000
                    and math.isfinite(value) and value == int(value))

        if (not isinstance(observation, dict)
                or observation.get("all_facilities_match") is not True
                or not counter(observation.get("sequence"))
                or not counter(observation.get("physics_frame"))
                or type(observation.get("paused")) is not bool):
            return False
        facilities = observation.get("facilities")
        if not isinstance(facilities, dict) or set(facilities) != set(FACILITY_IDS):
            return False
        for facility_id in FACILITY_IDS:
            proof = facilities[facility_id]
            if not isinstance(proof, dict):
                return False
            if not all(proof.get(key) is True for key in
                       ("ready", "reference_matches", "state_matches_reliable", "physics_match")):
                return False
            if (not all(counter(proof.get(key)) for key in
                        ("reference_epoch", "reference_serial", "epoch", "applied_serial", "parts"))
                    or proof.get("mismatches") != []):
                return False
            if (proof["epoch"] != proof["reference_epoch"]
                    or proof["applied_serial"] > proof["reference_serial"]):
                return False
            if (facility_id in ("trial", "shared_access")
                    and proof["applied_serial"] != proof["reference_serial"]):
                return False
        return True

    @staticmethod
    def own_player(state: dict, peer: int | None = None) -> dict:
        return state.get("players", {}).get(str(state.get("peer_id") if peer is None else peer), {})

    def accepted_ability(self, label: str, ability: str, target: str, mode: str = "") -> dict:
        peer = 1 if label == "host" else self.observe(label, "current acting identity")["peer_id"]
        before = self.wait("host", lambda s: s.get("players", {}).get(str(peer), {}).get("cooldown", 999) <= 0,
                           "production cooldown clears before next command")
        count, rejected = before["stats"]["abilities"], before["stats"]["rejected_abilities"]
        self.action(label, ability, target, mode)
        outcome = self.wait("host", lambda s: s["stats"]["abilities"] > count
                            or s["stats"]["rejected_abilities"] > rejected,
                            f"authority resolves actual {label} {ability}")
        self.check(f"{label} real {ability} accepted", outcome["stats"]["abilities"] == count + 1
                   and outcome["stats"]["rejected_abilities"] == rejected,
                   {"outcomes": outcome.get("ability_outcomes", [])[-2:], "notes": outcome.get("authority_notes", [])[-2:]})
        return outcome

    def guest_at(self, label: str, point: list[float]) -> dict:
        self.request("host", "place_guest", {"position": point})
        return self.wait(label, lambda s: len(self.own_player(s).get("position", [])) == 3
                         and max(abs(a-b) for a, b in zip(self.own_player(s)["position"], point)) < 0.04,
                         "guest receives collision-checked scripted starting pose")

    def no_early_reward(self, host: dict, guest: dict) -> bool:
        return (FORMAL_OBJECTIVE not in host.get("completed", [])
                and len(host.get("completed", [])) == 27
                and DISCOVERY not in host.get("personal", {}).get("discoveries", [])
                and DISCOVERY not in guest.get("personal", {}).get("discoveries", [])
                and not any(DISCOVERY in event.get("reward_ids", []) for event in guest.get("events", [])))

    def save_case(self, name: str, **states: dict) -> None:
        atomic_json(self.evidence / (name + ".json"), states)

    def pause(self, guest_label: str) -> None:
        self.request("host", "propose_pause")
        self.wait(guest_label, lambda s: bool(s.get("proposal")), "guest receives actual pause proposal")
        self.request(guest_label, "confirm_vote")
        self.wait("host", lambda s: s.get("paused") is True, "both participant pause commits")
        self.wait(guest_label, lambda s: s.get("paused") is True, "guest pause snapshot arrives")

    def exercise(self) -> None:
        self.scenario("1 manual well, actual guest G, failed host publication and latest-pose retry")
        self.launch("host", "host")
        host = self.wait("host", lambda s: s.get("region") == "I2" and s.get("story_ready")
                         and self.valid_probe(s.get("probe", {}), True), "host builds the production facilities", timeout=30)
        self.check("explicit predecessor fixture has27 goals and unobserved closed cabinet",
                   len(host["completed"]) == 27 and not host["history"]["back_observed"]
                   and host["probe"]["state"]["axis"]["position_m"] == 0
                   and host["probe"]["well_cover_hit"] and host["probe"]["door_ray_correct"])
        self.request("host", "g")
        closed = self.observe("host", "closed G refusal")
        self.check("real closed-well G grants no observation", not closed["history"]["back_observed"]
                   and not closed["pending_observation"] and not closed["observation_commits"])
        # The oblique high-well impulse opens the well but may settle just
        # short of the stop. Its handle then moves UNDER the right upper deck:
        # repeating from above can be occluded. Use the same collision-checked
        # east service cavity already exercised by the closing action below.
        self.accepted_ability("host", "push_pull", COVER)
        self.wait("host", lambda s: s["probe"]["well_clear"], "first actual impulse exposes the high well")
        self.request("host", "place_host", {"position": [22, 4.6, -11.45]})
        self.accepted_ability("host", "push_pull", COVER, "pull")
        host = self.wait("host", lambda s: s["probe"]["state"]["axis"]["position_m"] >= 1.2
                         and s["probe"]["well_clear"], "actual impulses uncover the high well")
        self.request("host", "place_host", {"position": [24, 8, -10]})
        self.launch("guest_first", "guest")
        guest = self.wait("guest_first", lambda s: bool(s.get("first_snapshot")) and s.get("story_ready")
                          and len(s.get("players", {})) == 2, "guest actual ENet first four-facility state", timeout=30)
        first = guest["first_snapshot"]
        self.check("first accepted guest frame already matches both reliable mechanisms",
                   first.get("state_matches_reliable") is True and first.get("water_matches_reliable") is True
                   and first.get("water_ready") is True and first.get("trial_ready") is True
                   and first.get("trial_matches_reliable") is True and first.get("trial_physics_match") is True and self.valid_probe(first.get("probe", {}), False), first)
        self.check("initial accepted frame has four genuine reliable and PhysicsServer proofs",
                   self.valid_facility_proof(first), first.get("facilities"))
        self.check("first physical pose shows open cover and still-closed low door",
                   first["probe"]["state"]["axis"]["position_m"] == 1.2
                   and first["probe"]["state"]["door_fraction"] == 0 and first["probe"]["door_ray_correct"])
        self.check("guest is actual HX02", self.own_player(guest)["airframe"] == "hx02")
        self.wait("host", lambda s: s.get("pending_receipts") == 0, "historical lawful receipt catchup drains")
        guest = self.guest_at("guest_first", [18, 5.75, -10.6])
        guest_id = str(guest["peer_id"])
        host = self.wait("host", lambda s: s["probe"]["proof"].get(guest_id, {}).get("ok")
                         and s["probe"]["proof"][guest_id].get("method") == "manual",
                         "host first-hit rays actually see both plates through the well")
        self.check("manual proof uses both physical plate centers", all(host["probe"]["proof"][guest_id]["center_hits"])
                   and min(host["probe"]["proof"][guest_id]["panel_hits"]) >= 3)
        baseline_receipts = guest["guest_received_count"]
        baseline_discoveries = guest["personal"]["discoveries"]
        self.request("host", "observation_write_failure", {"enabled": True})
        self.request("guest_first", "g")
        failed = self.wait("host", lambda s: s.get("pending_observation")
                           and any(not item["accepted"] for item in s.get("observation_commits", [])),
                           "real guest G reaches host and fails the actual Store publication")
        observed = failed["pending_history"]
        self.check("failed publication keeps first proof pending without adoption",
                   not failed["history"]["back_observed"]
                   and not failed["saved_envelope"]["history"]["back_observed"]
                   and all(item["failed_save_unchanged"] and item["pose_unchanged"]
                           for item in failed["observation_commits"] if not item["accepted"]))
        self.request("host", "place_host", {"position": [22, 4.6, -11.45]})
        self.accepted_ability("host", "push_pull", COVER)
        moved = self.wait("host", lambda s: s["probe"]["state"]["axis"]["position_m"] < 0.9
                          and s.get("pending_observation"), "cover continues moving while first observation awaits storage")
        failed_guest = self.wait("guest_first", lambda s: self.valid_probe(s.get("probe", {}), False)
                                and s["probe"]["state"]["axis"]["position_m"] < 0.9,
                                "guest receives actual moving cover even before history is saved")
        self.check("failed history is not broadcast as committed", not failed_guest["history"]["back_observed"]
                   and self.no_early_reward(moved, failed_guest))
        self.request("host", "observation_write_failure", {"enabled": False})
        saved = self.wait("host", lambda s: s.get("history", {}).get("back_observed")
                          and not s.get("pending_observation"), "automatic production retry saves without another G")
        successful = [item for item in saved["observation_commits"] if item["accepted"]]
        self.check("single successful retry saves current mechanism and never rewinds it", len(successful) == 1
                   and successful[0]["latest_saved"] and successful[0]["pose_unchanged"]
                   and successful[0]["physical"]["serial"] > observed["evidence"]["mechanism_serial"], successful)
        self.check("first validated manual evidence survives later motion", saved["history"] == observed)
        guest = self.wait("guest_first", lambda s: self.valid_probe(s.get("probe", {}), False)
                          and s.get("history") == saved["history"], "guest receives only committed first-observation history")
        self.check("early observation creates no formal goal or reward receipt", self.no_early_reward(saved, guest)
                   and guest["guest_received_count"] == baseline_receipts
                   and guest["personal"]["discoveries"] == baseline_discoveries)
        self.save_case("case1-manual-pending", failed_host=failed, failed_guest=failed_guest, committed_host=saved, committed_guest=guest)
        self.complete()

        self.scenario("2 guest electrical route, real wide-body low-door crossing and duplicate observation")
        self.wait("host", lambda s: s["probe"]["state"]["axis"]["position_m"] == 0,
                  "cover naturally settles at its closed stop")
        guest = self.guest_at("guest_first", [17.8, 2.7, -7.4])
        self.accepted_ability("guest_first", "charge", RELAY)
        charged = self.observe("host", "post-charge door state")
        self.check("actual charge alone leaves low door closed", charged["probe"]["state"]["door_fraction"] == 0)
        self.accepted_ability("guest_first", "takeover", LOCK)
        partial = self.wait("host", lambda s: 0 < s["probe"]["state"]["door_fraction"] < 1,
                            "host advances a real intermediate motor stroke")
        self.check("partial door PhysicsServer and target positions match", self.valid_probe(partial["probe"], True))
        opened = self.wait("host", lambda s: s["probe"]["state"]["electric_latched"]
                           and s["probe"]["state"]["door_fraction"] == 1, "actual legal guest control fully opens the door")
        self.wait("guest_first", lambda s: self.valid_probe(s.get("probe", {}), False)
                  and s["probe"]["state"]["door_fraction"] == 1, "guest receives fully open actual collision")
        self.request("host", "cross_guest", {"position": [18, 2.7, -10.8]})
        crossed = self.wait("host", lambda s: not s.get("movement", {}).get("active", True),
                            "real FlightBody completes bounded low-door sweep", timeout=10)
        route = crossed["movement"]
        self.check("wide-body traversal starts clear, sweeps and finishes clear", route.get("done") is True
                   and route.get("start_clear") is True and route.get("end_clear") is True
                   and route.get("steps", 0) > 1 and not route.get("error"), route)
        guest = self.wait("guest_first", lambda s: abs(self.own_player(s).get("position", [0, 0, 0])[2]+10.8) < 0.04,
                          "guest receives host-authoritative swept arrival")
        guest_id = str(guest["peer_id"])
        inside = self.wait("host", lambda s: s["probe"]["proof"].get(guest_id, {}).get("ok")
                           and s["probe"]["proof"][guest_id].get("method") == "service_lock",
                           "actual inside sensor sees physical plates along electric route")
        commits = len([item for item in inside["observation_commits"] if item["accepted"]])
        self.request("guest_first", "g")
        self.settle(0.4)
        repeat = self.observe("host", "duplicate real G result")
        duplicate_guest = self.observe("guest_first", "duplicate observation guest personal state")
        self.check("second real route preserves first history and creates no second commit",
                   repeat["history"] == saved["history"]
                   and len([item for item in repeat["observation_commits"] if item["accepted"]]) == commits
                   and self.no_early_reward(repeat, duplicate_guest))
        self.wait("guest_first", lambda s: s.get("applied_count", 0) >= 40 and s.get("cadence", {}).get("span_ms", 0) >= 2000,
                  "sustained real reliable plus motion traffic")
        continuous = self.observe("guest_first", "current network cadence evidence")
        self.check("guest ticks do not integrate any authoritative mechanism", continuous["guest_ticks"] > 0
                   and continuous["guest_local_mutations"] == 0 and continuous["guest_water_mutations"] == 0
                   and continuous["guest_trial_mutations"] == 0 and continuous.get("guest_bridge_mutations") == 0)
        latest = continuous.get("latest_probe", {})
        self.check("latest running guest frame retains all four facility proofs",
                   self.valid_facility_proof(latest)
                   and latest.get("sequence") == continuous.get("received_sequence"), latest)
        self.save_case("case2-electric-crossing", partial=partial, open_host=opened, crossed=crossed, observed=inside, guest=continuous)
        self.complete()

        self.scenario("3 voted pause and same-identity reconnect restores all four facilities")
        self.pause("guest_first")
        paused_host = self.observe("host", "paused host cabinet baseline")
        paused_guest = self.wait("guest_first", lambda s: bool(s.get("first_paused_snapshot")),
                                 "actual first paused four-facility snapshot before departure")
        paused_first = paused_guest["first_paused_snapshot"]
        self.check("first voted-pause frame contains all four reliable and physical states",
                   self.valid_facility_proof(paused_first) and paused_first.get("paused") is True,
                   paused_first)
        identity = paused_guest["profile_id"]
        baseline_receipts = paused_guest["guest_received_count"]
        self.request("guest_first", "shutdown")
        self.natural_exit("guest_first")
        self.wait("host", lambda s: len(s.get("players", {})) == 1, "actual guest departure reaches authority")
        self.launch("guest_reconnect", "guest", reconnect=True)
        resumed = self.wait("guest_reconnect", lambda s: bool(s.get("first_paused_snapshot")) and s.get("story_ready")
                            and self.valid_probe(s.get("probe", {}), False),
                            "paused ENet reconnect receives actual four-facility first packet", timeout=30)
        first = resumed["first_snapshot"]
        self.check("same persisted guest identity reconnects", resumed["profile_id"] == identity)
        self.check("first reconnect packet restores both mechanisms before motion acceptance",
                   first.get("paused") is True and first.get("state_matches_reliable") is True
                   and first.get("water_matches_reliable") is True and first.get("trial_ready") is True
                   and first.get("trial_matches_reliable") is True and first.get("trial_physics_match") is True and self.valid_probe(first.get("probe", {}), False), first)
        self.check("same-identity reconnect first frame restores all four facilities before motion",
                   self.valid_facility_proof(first) and first.get("paused") is True, first)
        resumed_paused = resumed["first_paused_snapshot"]
        self.check("reconnect first paused proof is the actual first accepted paused frame",
                   self.valid_facility_proof(resumed_paused) and resumed_paused.get("paused") is True
                   and resumed_paused.get("sequence") == first.get("sequence"), resumed_paused)
        self.check("paused reconnect has the real closed cover and open low door", first["probe"]["state"]["axis"]["position_m"] == 0
                   and first["probe"]["state"]["door_fraction"] == 1 and first["probe"]["well_cover_hit"]
                   and first["probe"]["door_ray_correct"])
        self.check("reconnect preserves history without premature reward", resumed["history"] == paused_host["history"]
                   and resumed["guest_received_count"] == baseline_receipts
                   and resumed["personal_world_unchanged"] is True and self.no_early_reward(paused_host, resumed))
        self.settle(0.6)
        still = self.wait("guest_reconnect", lambda s: self.valid_probe(s.get("probe", {}), False),
                          "paused received mechanism after local ticks")
        # Join/leave legitimately updates the host axis input roster. Compare
        # actual physical pose/history rather than requiring its ledger unchanged.
        self.check("paused reconnect stays physically stationary", still["probe"]["state"]["axis"]["position_m"] == first["probe"]["state"]["axis"]["position_m"]
                   and still["probe"]["state"]["door_fraction"] == first["probe"]["state"]["door_fraction"]
                   and still["guest_local_mutations"] == 0 and still["guest_water_mutations"] == 0
                   and still["guest_trial_mutations"] == 0 and still.get("guest_bridge_mutations") == 0)
        latest_paused = still.get("latest_probe", {})
        self.check("latest paused reconnect frame keeps all four proofs and current motion reference",
                   self.valid_facility_proof(latest_paused) and latest_paused.get("paused") is True
                   and latest_paused.get("sequence") == still.get("received_sequence"), latest_paused)
        self.save_case("case3-paused-reconnect", host=paused_host, guest=still)
        self.request("host", "shutdown")
        self.natural_exit("host")
        left = self.wait("guest_reconnect", lambda s: s.get("host_left_seen") and not s.get("active"), "host departure event")
        self.check("host exit preserves guest personal world and reward ledger", left.get("personal_world_unchanged") is True
                   and left["guest_received_count"] == baseline_receipts and DISCOVERY not in left["personal"]["discoveries"])
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
        self.summary["checks"].append({"name": "measured loopback snapshot budget", "passed": 0 < host_transport.get("max_snapshot_bytes", 0) <= 1150 and host_transport.get("reliable_fallbacks", 0) == 0 and host_transport.get("snapshot_encode_rejections", 0) == 0, "actual": host_transport})
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
    parser.add_argument("--expected-distribution-sha", default="")
    parser.add_argument("--run", action="store_true", help="Explicitly run only after root confirms asset AND shared-code freeze.")
    args = parser.parse_args()
    if not args.run:
        print("PREPARATION ONLY: no Godot process, no ENet and no UDP lock acquired. After shared-code/layout freeze pass --run --expected-distribution-sha <final SHA256>.")
        return 0
    if args.standalone and args.godot is None:
        parser.error("--standalone requires an explicit --godot exported executable")
    project = args.project.resolve()
    godot = (args.godot or (Path(os.environ.get("LOCALAPPDATA", "")) / "Programs/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe")).resolve()
    entry_kind = "package_main" if args.standalone else "source_main"
    sha = args.expected_distribution_sha.lower()
    if len(sha) != 64 or any(char not in "0123456789abcdef" for char in sha):
        parser.error("--run requires the explicitly frozen Distribution layout SHA256")
    if not godot.is_file() or not (project / "project.godot").is_file():
        parser.error("Godot and source project must exist")
    if not (project / MODEL).is_file() or file_sha256(project / MODEL) != sha:
        parser.error("Distribution layout does not match the frozen SHA256; no process started")
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
