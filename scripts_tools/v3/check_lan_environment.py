#!/usr/bin/env python3
"""Actual export-debug EXE, ordinary MAIN, two-process ENet environment check.

Preparation is the default; --run starts the explicitly selected package.
One scenario per invocation. This is same-computer loopback, never two-PC LAN.
"""
from __future__ import annotations

import argparse
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import traceback

sys.dont_write_bytecode = True
from test_lan_local import LanPortLock, LanRunBusy, process_options, utc_now
import dev

SUITE = "environment-lan"
CONTRACT = 1
PROTOCOL = 25
WORKER_SECONDS = 220
JOB_SECONDS = 240


def sha256(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for part in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(part)
    return value.hexdigest()


def write_json(path: Path, value: object, diagnostics: dict | None = None) -> None:
    """Publish the same completed temp file; only Windows share/access races retry.

    The caller's original heartbeat timestamp/payload is never regenerated.
    A genuinely unwritable path, non-Windows error, or exhausted bound raises.
    """
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    began = time.monotonic()
    deadline = began + 1.0
    retries = 0
    last_error = None
    final_error = None
    try:
        while True:
            try:
                os.replace(temporary, path)
                return # Stop immediately on the first successful publication.
            except OSError as exc:
                last_error = {"type": type(exc).__name__, "winerror": getattr(exc, "winerror", None),
                              "errno": exc.errno, "message": str(exc)}
                remaining = deadline-time.monotonic()
                # ERROR_ACCESS_DENIED / SHARING_VIOLATION / LOCK_VIOLATION.
                if os.name != "nt" or getattr(exc, "winerror", None) not in (5, 32, 33) or remaining <= 0:
                    final_error = last_error
                    raise
                retries += 1
                time.sleep(min(.02, remaining))
    finally:
        if diagnostics is not None:
            elapsed = time.monotonic()-began
            diagnostics["writes"] += 1
            diagnostics["retries"] += retries
            diagnostics["retry_elapsed_seconds"] += elapsed if retries else 0.0
            diagnostics["max_replace_elapsed_seconds"] = max(diagnostics["max_replace_elapsed_seconds"], elapsed)
            if retries or final_error:
                diagnostics["events"].append({"path": str(path), "retries": retries,
                    "elapsed_seconds": round(elapsed, 6), "last_retry_error": last_error,
                    "final_error": final_error, "published": final_error is None})
                diagnostics["events"] = diagnostics["events"][-32:]
            if final_error:
                diagnostics["final_error"] = final_error


def read_json(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


class CheckFailed(RuntimeError):
    pass


class EnvironmentRun:
    def __init__(self, args: argparse.Namespace, lock: LanPortLock) -> None:
        self.args = args
        self.exe = args.exe.resolve()
        self.region = args.scenario
        self.run_id = args.run_id
        self.output = self.exe.parent / "artifacts/v3/network/environment" / self.region / self.run_id
        self.lock = lock
        self.started = time.monotonic()
        self.deadline = self.started + WORKER_SECONDS
        self.running: dict[str, tuple[subprocess.Popen, object, float]] = {}
        self.serials: dict[str, int] = {}
        self.last_heartbeat = None
        self.heartbeat_count = 0
        self.maximum_heartbeat_gap = 0.0
        self.loadout_expected: dict = {}
        self.saved_role_build: dict = {}
        self.atomic_writes = {"scope": "controller_and_command_publications; summary uses the same bounded helper",
            "retry_limit_seconds": 1.0, "retry_interval_seconds": .02,
            "windows_retry_errors": [5, 32, 33], "writes": 0, "retries": 0,
            "retry_elapsed_seconds": 0.0, "max_replace_elapsed_seconds": 0.0,
            "events": [], "final_error": None}
        self.summary = {
            "suite": SUITE, "contract": CONTRACT, "protocol": PROTOCOL,
            "verbose_guests": args.verbose_guests,
            "verbose_host": args.verbose_host,
            "loadout_case": args.loadout_case,
            "loadout_variant": args.loadout_variant,
            "run_id": self.run_id, "scenario": self.region, "started_utc": utc_now(),
            "scope": "actual export-debug package; ordinary MAIN; 127.0.0.1 ENet; not two-PC LAN",
            "weapon_presentation_scope": "Idle Host owner presentation/HUD only; no LAN fire/hit/heat consumption; paused new owner HUD may await original resume." if args.loadout_variant == "HBA_BURST" else "not_requested",
            "fixture": "New isolated profiles, ordinary I1 start and direct QA I2/I3 load; no Story prefix or fabricated facility/cargo state. I3 allows one initial unloaded PLAYER observation pose only."
                       + (" Optional loadout case: explicit personal-only Whale/Crown discovery unlock fixtures, native Hangar UI/Store H/B/A saves; these are not earned campaign victories." if args.loadout_case else "")
                       + (" HBA_BURST adds personal-only F2 Boss and I3 cooling discovery fixtures solely for module ownership; those histories were not played." if args.loadout_variant == "HBA_BURST" else ""),
            "limits": {"worker_wall_seconds": WORKER_SECONDS, "private_owned_job_seconds": JOB_SECONDS, "peer_wall_seconds": 210},
            "limitations": ["No second computer, physical LAN, firewall/router, packet loss, hardware controller, rendered performance or human comfort acceptance.", "No natural traversal of previous regions; no host restart or cold full-campaign Registry reopening is claimed."],
            "executable": str(self.exe), "executable_sha256": sha256(self.exe),
            "executable_bytes": self.exe.stat().st_size,
            "lock": {"path": str(lock.path), "port": 26742, "pid": os.getpid(), "backend": lock.backend, "acquired_utc": lock.acquired_utc},
            "processes": {}, "checks": [], "milestones": {}, "error": None, "passed": False,
            "atomic_json_write_retry": self.atomic_writes,
        }

        if self.region == "I4":
            self.summary["fixture"] = "New isolated Host/Guest profiles; ordinary I1 start then explicit QA I4 load; one native hull-checked PLAYER-only observation pose (20,12,1.8). No played predecessor, clock/phase/cache/HUD/HP/Story fixtures."
            self.summary["limits"]["I4_natural_phase_wait_seconds"] = 35
            self.summary["expected_processes"] = 2
            self.summary["limitations"].append("I4 is a short 2-peer wind/cache/visible-Control pause/resume test; no reconnect/loadout/combat or second-computer claim; headless Control visibility is not rendered-pixel evidence.")

    def heartbeat(self) -> None:
        now = time.time()
        monotonic = time.monotonic()
        if self.last_heartbeat is not None:
            self.maximum_heartbeat_gap = max(self.maximum_heartbeat_gap, monotonic-self.last_heartbeat)
        self.last_heartbeat = monotonic
        self.heartbeat_count += 1
        value = {
            "suite": SUITE, "run_id": self.run_id, "region": self.region, "lock_held": self.lock.stream is not None,
            "port": 26742, "controller_pid": os.getpid(), "heartbeat_unix": now,
            "heartbeat_serial": self.heartbeat_count,
            "loadout_case": self.args.loadout_case,
            "loadout_variant": self.args.loadout_variant,
        }
        write_json(self.output / "controller.json", value, self.atomic_writes)
        self.summary["controller_heartbeat"] = {"count": self.heartbeat_count,
            "maximum_monotonic_write_gap_seconds": round(self.maximum_heartbeat_gap, 6),
            "last_original_value": value}

    def state(self, label: str) -> dict:
        # Only transient Windows access/sharing races get a short fresh reread.
        # Never substitute an older state, refresh a heartbeat, or retry invalid
        # JSON/schema into apparent successful gameplay evidence.
        path = self.output / f"{label}-state.json"
        deadline = min(self.deadline, time.monotonic() + .4)
        while True:
            try:
                value = json.loads(path.read_text(encoding="utf-8"))
                return value if isinstance(value, dict) else {}
            except FileNotFoundError:
                # Windows rename removes its old destination before moving the
                # new file. Retry actual fresh IO within this same short bound;
                # never reuse a cached state or invent protocol/identity fields.
                if time.monotonic() >= deadline:
                    return {}
                time.sleep(.002)
            except OSError as error:
                diagnostics = self.summary.setdefault("state_read_errors", [])
                if len(diagnostics) < 128:
                    diagnostics.append({"label": label, "errno": error.errno,
                                        "winerror": getattr(error, "winerror", None),
                                        "seconds": round(time.monotonic()-self.started, 6)})
                # CPython Path.read_text also reports the observed Windows
                # exclusive-file race as PermissionError(errno13, winerror=None).
                transient = getattr(error, "winerror", None) in (5,32,33) or (isinstance(error, PermissionError) and error.errno == 13 and getattr(error, "winerror", None) is None)
                if os.name != "nt" or not transient or time.monotonic() >= deadline:
                    return {}
                time.sleep(.01)
            except ValueError as error:
                self.summary.setdefault("state_parse_errors", []).append({"label": label, "error": str(error)})
                return {}

    def check(self, name: str, condition: bool, detail: object = None) -> None:
        self.summary["checks"].append({"name": name, "passed": bool(condition), "detail": detail})
        if not condition:
            raise CheckFailed(name)

    def milestone(self, name: str, *labels: str) -> None:
        self.summary["milestones"][name] = {label: self.state(label) for label in labels}
        write_json(self.output / "summary.json", self.summary)
        print(f"LAN_ENVIRONMENT {self.region} {name}", flush=True)

    def wait(self, name: str, predicate, seconds: float, required: tuple[str, ...] = ()) -> dict:
        deadline = min(self.deadline, time.monotonic() + seconds)
        latest = {}
        while time.monotonic() < deadline:
            self.heartbeat()
            for label, (process, _log, _started) in self.running.items():
                state = self.state(label)
                if state:
                    if state.get("errors"):
                        self.summary["milestones"]["failure_" + name] = {label: state}
                        raise CheckFailed(f"{label} QA/engine error: {state['errors']}")
                    if (state.get("protocol") != PROTOCOL or state.get("pid") != process.pid
                        or state.get("suite") != SUITE or state.get("contract") != CONTRACT
                        or state.get("run_id") != self.run_id or state.get("label") != label
                        or state.get("actual_package") is not True
                        or state.get("loadout_case", False) is not self.args.loadout_case
                        or state.get("loadout_variant", "HBA") != self.args.loadout_variant
                        or os.path.normcase(str(Path(state.get("executable", "")).resolve())) != os.path.normcase(str(self.exe))):
                        raise CheckFailed(f"{label}: actual package/suite/protocol/PID mismatch")
                if label in required and process.poll() is not None:
                    raise CheckFailed(f"{label} exited {process.returncode} while waiting for {name}")
            latest = {label: self.state(label) for label in required}
            if predicate():
                return latest
            time.sleep(.05)
        self.summary["milestones"]["timeout_" + name] = latest
        raise TimeoutError(f"{name}: bounded wait expired ({seconds}s; total {time.monotonic()-self.started:.1f}s)")

    def launch(self, label: str) -> None:
        self.heartbeat()
        role = "host" if label == "host" else "guest"
        profile = f"qa_lan_environment_{role}_{self.region.lower()}_{self.run_id}"
        command = [str(self.exe), "--headless"]
        if role == "guest" and self.args.verbose_guests or role == "host" and self.args.verbose_host:
            command.append("--verbose")
        command.extend(["--", f"--qa-suite={SUITE}",
                   f"--qa-profile={profile}", f"--qa-lan-env-role={role}",
                   f"--qa-lan-env-label={label}", f"--qa-lan-env-region={self.region}",
                   f"--qa-lan-env-run={self.run_id}", f"--qa-lan-env-evidence={self.output}"])
        if self.args.loadout_case:
            command.append("--qa-lan-env-loadout-case=1")
        if self.args.loadout_variant == "HBA_BURST":
            command.append("--qa-lan-env-loadout-variant=HBA_BURST")
        log = (self.output / f"{label}.log").open("xb")
        try:
            process = subprocess.Popen(command, cwd=self.exe.parent, stdout=log,
                                       stderr=subprocess.STDOUT, **process_options())
        except BaseException:
            log.close()
            raise
        self.running[label] = (process, log, time.monotonic())
        self.summary["processes"][label] = {"pid": process.pid, "command": command,
            "cwd": str(self.exe.parent), "profile": profile, "started_utc": utc_now(),
            "forced_stop": False, "exit_code": None}

    def command(self, label: str, verb: str, seconds: float = 8) -> dict:
        serial = self.serials.get(label, 0) + 1
        self.serials[label] = serial
        write_json(self.output / f"{label}-command.json", {
            "run_id": self.run_id, "sequence": serial, "verb": verb,
        }, self.atomic_writes)
        self.wait(label + "_" + verb, lambda: self.state(label).get("ack", 0) == serial,
                  seconds, (label,))
        value = self.state(label)
        self.check(f"{label}.{verb}.original_api_accepted", value.get("result", {}).get("ok") is True,
                   value.get("result"))
        return value

    def finish(self, label: str, seconds: float = 12) -> None:
        process, log, started = self.running[label]
        record = self.summary["processes"][label]
        deadline = min(self.deadline, time.monotonic() + seconds)
        try:
            while process.poll() is None and time.monotonic() < deadline:
                self.heartbeat()
                time.sleep(.05)
            if process.poll() is None:
                record["forced_stop"] = True
                process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=3)
        finally:
            record.update(exit_code=process.poll(), finished_utc=utc_now(),
                          elapsed_wall_seconds=round(time.monotonic()-started, 3))
            log.close()
        record["final_state"] = self.state(label)
        text = (self.output / f"{label}.log").read_text(encoding="utf-8", errors="replace")
        record["engine_or_cleanup_errors"] = [line for line in text.splitlines()
            if "ERROR:" in line or "SCRIPT ERROR:" in line or ("objectdb" in line.lower() and "leak" in line.lower())
            or "resources still in use at exit" in line]
        self.check(label + ".natural_exit", record["exit_code"] == 0 and not record["forced_stop"],
                   {"exit_code": record["exit_code"], "forced_stop": record["forced_stop"]})
        self.check(label + ".no_engine_or_exit_leak_errors", not record["engine_or_cleanup_errors"],
                   record["engine_or_cleanup_errors"])

    def disconnect(self, label: str) -> None:
        # shutdown may exit before the next polling interval; check its final
        # acknowledged state after the real process has exited instead.
        serial = self.serials.get(label, 0) + 1
        self.serials[label] = serial
        write_json(self.output / f"{label}-command.json", {"run_id": self.run_id, "sequence": serial, "verb": "shutdown"}, self.atomic_writes)
        self.finish(label)
        final = self.state(label)
        self.check(label + ".ordinary_shutdown_ack", final.get("ack") == serial and final.get("result", {}).get("ok") is True, final.get("result"))

    def accepted(self, label: str) -> bool:
        state = self.state(label)
        first = state.get("first_accepted", {})
        basic = bool(first and first.get("region") == self.region and first.get("facilities_ready") is True
                     and first.get("sequence", -1) >= 0 and len(state.get("players", {})) == 2)
        if self.region == "I2":
            return basic and first.get("canal", {}).get("native_ok") is True
        if self.region == "I4":
            return basic and first.get("i4", {}).get("installed") is True
        cargo = first.get("cargo", {})
        return basic and cargo.get("unique_body_count") == 1 and cargo.get("mass_kg") == 2 and cargo.get("client_module_absent") is True and cargo.get("native_presentation_ok") is True

    def pause_pair(self, guest: str, target: bool) -> None:
        self.command("host", "pause")
        self.wait("received_pause_vote", lambda: self.state(guest).get("proposal", {}).get("kind") == "pause", 12, ("host", guest))
        proposal = self.state(guest)["proposal"]
        self.check("pause.two_original_participants", len(proposal.get("participants", [])) == 2, proposal)
        self.command(guest, "confirm")
        self.wait("common_pause_" + str(target), lambda: self.state("host").get("paused") is target and self.state(guest).get("paused") is target
                  and not self.state("host").get("proposal") and not self.state(guest).get("proposal"), 18, ("host", guest))

    def save_and_read(self, tag: str) -> dict:
        self.command("host", "save")
        self.wait("original_save_callback", lambda: len(self.state("host").get("save_callbacks", [])) == 1, 12, ("host",))
        callbacks = self.state("host")["save_callbacks"]
        self.check(tag + ".one_successful_original_save", callbacks[0].get("ok") is True, callbacks)
        self.command("host", "read_disk")
        disk = self.state("host").get("disk_readback", {})
        self.check(tag + ".independent_Store_exact_readback", disk.get("matches_original_store_readback") is True
                   and disk.get("profile_uuid") == self.state("host").get("profile_uuid")
                   and disk.get("generation") == self.state("host").get("generation"), disk)
        self.milestone(tag, "host")
        return disk

    def cargo_carried(self, guest: str) -> bool:
        host, client = self.state("host"), self.state(guest)
        cargo = host.get("cargo", {})
        rows = cargo.get("carried", [])
        uuid = client.get("profile_uuid")
        seen = client.get("cargo", {})
        return bool(cargo.get("unique_body_count") == 1 and cargo.get("mass_kg") == 2
            and len(rows) == 1 and rows[0].get("mass_kg") == 2 and rows[0].get("identity") == uuid
            and rows[0].get("actual_body") is True and rows[0].get("joint_valid") is True
            and not cargo.get("module", {}).get("assist")
            and seen.get("presentation", {}).get("phase") == "carried"
            and seen.get("presentation", {}).get("role_identity") == uuid
            and seen.get("local_actor_loaded_presentation") is True and seen.get("local_cargo_kg") == 2)

    @staticmethod
    def hardware(frame: str, drive: str, utility: str) -> dict:
        return {"airframe_id": frame, "slots": {"weapon": "pulse_base", "tool": "scan_base",
                "drive": drive, "battery": "stock_battery", "utility": utility}}

    @staticmethod
    def actor_by_identity(loadout: dict, identity: str) -> tuple[str, dict]:
        rows = [(peer, row) for peer, row in loadout.get("players", {}).items()
                if row.get("identity") == identity]
        return rows[0] if len(rows) == 1 else ("", {})

    def check_loadouts(self, guest: str, reconnect: bool = False, resumed: bool = False) -> None:
        """Observe original bodies and actually-applied packet data; never make a packet."""
        host, client = self.state("host"), self.state(guest)
        host_view, guest_view = host.get("loadout", {}), client.get("loadout", {})
        first = client.get("first_accepted", {}).get("loadout", {})
        h = self.hardware("tr01", "stock_drive", "reinforced_guard")
        b = self.hardware("tr01", "racing_drive", "guard_base")
        if self.args.loadout_variant == "HBA_BURST":
            b["slots"].update(weapon="burst_capacitor", utility="cooling_duct")
        a = self.hardware("ag03", "racing_drive", "guard_base")
        local_request = a if reconnect else b
        self.loadout_expected = {"host_H": h, "first_guest_B": b, "reconnect_local_A": a}
        self.summary["loadout_expected"] = self.loadout_expected
        host_uuid, guest_uuid = host.get("profile_uuid"), client.get("profile_uuid")
        for label, state, expected in (("host", host, h), (guest, client, local_request)):
            view = state.get("loadout", {})
            setup = view.get("setup", {})
            self.check(label + ".original_local_Hangar_Save_Store", setup.get("prepared") is True
                       and setup.get("world_unchanged") is True and setup.get("reader_equal") is True
                       and setup.get("network_started_at_save") is False and setup.get("network_mode_at_save") == "solo"
                       and setup.get("initial_uuid") == state.get("profile_uuid")
                       and setup.get("hardware") == expected
                       and view.get("local_profile_hardware") == expected
                       and view.get("departure_hardware") == expected, setup)
        if reconnect:
            self.check(guest + ".original_profile_change_is_unloaded_A_only",
                       client["loadout"]["setup"].get("A_rejects_2kg") is True,
                       {"local": local_request, "saved_B": b})
        self.check(guest + ".same_packaged_catalog_fingerprint", bool(host_view.get("catalog_sha256"))
                   and host_view.get("catalog_sha256") == guest_view.get("catalog_sha256"))
        for observer, view in (("host", host_view), (guest, guest_view), (guest + ".first_accepted", first)):
            for identity, expected in ((host_uuid, h), (guest_uuid, b)):
                peer, row = self.actor_by_identity(view, identity)
                self.check(observer + ".actual_original_body_" + str(identity), bool(peer)
                           and row.get("hardware") == expected
                           and row.get("catalog_and_cached_status_match") is True
                           and row.get("actual_body_matches") is True
                           and row.get("native_shape_matches") is True, row)
        peer, effective = self.actor_by_identity(host_view, guest_uuid)
        self.check(guest + ".host_received_real_handshake_hardware", bool(peer)
                   and host_view.get("announced_guest_hardware", {}).get(peer) == local_request,
                   host_view.get("announced_guest_hardware"))
        local_peer, _ = self.actor_by_identity(first, guest_uuid)
        self.check(guest + ".first_accepted_original_snapshot_echoes_B", bool(local_peer)
                   and first.get("applied_snapshot_hardware", {}).get(local_peer) == b,
                   first.get("applied_snapshot_hardware"))
        if reconnect:
            self.check("saved_cargo_B_overrides_actual_A_handshake", local_request != b
                       and host_view.get("saved_role_identity") == guest_uuid
                       and host_view.get("saved_role_native_build") == self.saved_role_build
                       and effective.get("native_build") == self.saved_role_build,
                       {"request_A": local_request, "effective_B": effective.get("native_build"),
                        "original_saved_B": self.saved_role_build})
        self.milestone("loadout_resumed_B_retained" if resumed else ("loadout_reconnect_A_requested_B_restored" if reconnect else "loadout_distinct_actual_H_B"),
                       "host", guest)

    def weapon_owner_ready(self, guest: str) -> bool:
        """Actual idle owner event/HUD only; every value is a peer observation."""
        host, client = self.state("host"), self.state(guest)
        identity = client.get("profile_uuid")
        hp, _ = self.actor_by_identity(host.get("loadout", {}), identity)
        gp, _ = self.actor_by_identity(client.get("loadout", {}), identity)
        authority, receiver = host.get("weapon_owner", {}), client.get("weapon_owner", {})
        h = authority.get("rows", {}).get(hp, {})
        g = receiver.get("rows", {}).get(gp, {})
        hv, gv = h.get("view", {}), g.get("view", {})
        expected = {"weapon_id": "burst_capacitor", "heat": 0, "capacity": 100,
                    "charge_s": 0, "charge_max_s": .7, "cooldown_s": 0,
                    "overheated": False, "reason": "released"}
        hardware = self.hardware("tr01", "racing_drive", "cooling_duct")
        hardware["slots"]["weapon"] = "burst_capacitor"
        expected_modifiers = {"damage": 28, "interval_s": 1, "charge_s": .7,
                              "heat_per_shot": 32, "cooling_multiplier": 1.25, "heat_dissipation_ps": 16}
        hud = receiver.get("hud_text", "")
        return bool(hp and gp and gp == str(client.get("local_peer"))
            and authority.get("authority") is True and receiver.get("authority") is False
            and authority.get("session_id") == receiver.get("session_id") == host.get("session_id")
            and receiver.get("accepted_remote_session") == host.get("session_id")
            and receiver.get("accepted_remote_serial", -1) >= 0
            and authority.get("host_serial", -1) >= receiver.get("accepted_remote_serial", 0)
            and authority.get("region") == receiver.get("region") == "I3"
            and authority.get("boss_active") is False and receiver.get("boss_active") is False
            and receiver.get("manager_local_cycles") == 0
            and h.get("hardware") == g.get("hardware") == hardware
            and h.get("build_hash") == g.get("build_hash") and bool(h.get("build_hash"))
            and h.get("held_fire") is False and g.get("held_fire") is False
            and h.get("body_heat") == g.get("body_heat") == 0
            and h.get("capacity") == g.get("capacity") == 100
            and h.get("actual_weapon_modifiers") == g.get("actual_weapon_modifiers") == expected_modifiers
            and hv == gv == expected and receiver.get("hud_visible") is True
            and bool(receiver.get("hud_node_path")) and hud == receiver.get("manager_hud_text")
            and "蓄能炮" in hud and "热量 0 / 100" in hud and "正在同步" not in hud)

    def check_weapon_owner(self, guest: str, resumed: bool = False) -> None:
        phase = "resumed_saved_B" if resumed else "first_departure_B"
        self.wait("burst_owner_idle_presentation_" + phase,
                  lambda: self.weapon_owner_ready(guest), 8, ("host", guest))
        host, client = self.state("host"), self.state(guest)
        setup = client.get("loadout", {}).get("setup", {})
        discoveries = setup.get("personal_discoveries", [])
        self.check(guest + ".explicit_personal_F2_I3_module_ownership_fixture",
                   "boss:F2:mirrorwing_warden" in discoveries and "I3:cooling_overdraft" in discoveries,
                   {"declared_discoveries": discoveries, "world_unchanged": setup.get("world_unchanged")})
        self.check(guest + ".original_host_owner_zero_heat_charge_and_native_burst_HUD_" + phase,
                   self.weapon_owner_ready(guest),
                   {"host": host.get("weapon_owner"), "guest": client.get("weapon_owner"),
                    "scope": "idle owner presentation only; no fire/hit/heat authoring; paused new owner may await real resume"})
        self.milestone("burst_owner_presentation_" + phase, "host", guest)

    def scenario(self) -> None:
        self.launch("host")
        self.wait("default_native_environment_ready", lambda: self.state("host").get("host_ready") is True, 90, ("host",))
        self.milestone("default_ready", "host")
        self.launch("guest_first")
        self.wait("first_guest_native_snapshot_ready", lambda: self.accepted("guest_first"), 40, ("host", "guest_first"))
        host, first = self.state("host"), self.state("guest_first")
        self.check("distinct_original_UUIDs", len(first.get("profile_uuid", "")) == 32 and first["profile_uuid"] != host.get("profile_uuid"),
                   [host.get("profile_uuid"), first.get("profile_uuid")])
        self.check("same_real_host_session_id", bool(host.get("session_id")) and first.get("session_id") == host.get("session_id"),
                   [host.get("session_id"), first.get("session_id")])
        self.milestone("first_accepted_snapshot", "host", "guest_first")
        if self.region == "I4":
            self.i4_short_scenario()
            return
        if self.args.loadout_case:
            self.check_loadouts("guest_first")
        if self.args.loadout_variant == "HBA_BURST":
            self.check_weapon_owner("guest_first")
        first_uuid = first["profile_uuid"]
        original_cargo_body = None
        original_actor_body = None
        if self.region == "I3":
            self.command("host", "place_guest_pickup")
            self.wait("guest_received_initial_observation_pose", lambda: any(
                row.get("identity") == first_uuid and sum((a-b)**2 for a, b in zip(row.get("position", []), [-10, 4.1, 18])) < .12**2
                for row in self.state("guest_first").get("players", {}).values()), 8, ("host", "guest_first"))
            self.command("guest_first", "lock_cargo")
            self.wait("guest_received_original_lock", lambda: self.state("guest_first").get("locks", {}).get(str(self.state("guest_first").get("local_peer"))) == "I3:loaded_cassette", 8, ("host", "guest_first"))
            self.command("guest_first", "g_cargo")
            self.wait("original_G_actual_pin_joint_and_unique_2kg", lambda: self.cargo_carried("guest_first"), 22, ("host", "guest_first"))
            cargo = self.state("host")["cargo"]
            original_cargo_body = cargo["body_id"]
            original_actor_body = cargo["carried"][0]["body_id"]
            self.milestone("actual_guest_G_pickup", "host", "guest_first")
        self.pause_pair("guest_first", True)
        if self.region == "I2":
            self.wait("paused_client_native_snapshot", lambda: self.state("guest_first").get("first_paused", {}).get("canal", {}).get("native_ok") is True, 8, ("host", "guest_first"))
        disk = self.save_and_read("paused_original_save")
        if self.region == "I3":
            envelope = disk.get("environment", {})
            self.check("carried_save_original_role_UUID_and_2kg", envelope.get("version") == 2
                       and envelope.get("role_identity") == first_uuid and envelope.get("joint", {}).get("weight") == 2, envelope)
            if self.args.loadout_case:
                self.saved_role_build = envelope.get("flight", {}).get("build", {})
                _, actor = self.actor_by_identity(self.state("host").get("loadout", {}), first_uuid)
                self.check("original_carried_Store_seals_actual_native_B", bool(self.saved_role_build)
                           and self.saved_role_build == actor.get("native_build")
                           and actor.get("hardware") == self.loadout_expected["first_guest_B"], self.saved_role_build)
                self.summary["original_saved_role_B"] = self.saved_role_build
        self.milestone("common_paused_before_departure", "host", "guest_first")
        self.disconnect("guest_first")
        self.wait("original_guest_departure_complete", lambda: len(self.state("host").get("players", {})) == 1, 15, ("host",))
        self.check("host_remains_paused_after_departure", self.state("host").get("paused") is True)
        if self.region == "I2":
            # New Canal presentation becomes ready through ordinary advance.
            # Resume by the ORIGINAL one-participant Consensus, never a flag write.
            self.command("host", "pause")
            self.wait("host_original_solo_resume_before_rejoin", lambda: self.state("host").get("paused") is False
                      and not self.state("host").get("proposal"), 12, ("host",))
        else:
            self.command("host", "read_disk")
            saved = self.state("host")["disk_readback"]["environment"]
            self.check("disconnect_keeps_original_carried_role", saved.get("version") == 2 and saved.get("role_identity") == first_uuid, saved)
            if self.args.loadout_case:
                self.check("disconnect_keeps_native_saved_B", saved.get("flight", {}).get("build") == self.saved_role_build)
        self.milestone("before_same_profile_reconnect", "host")
        self.launch("guest_reconnect")
        self.wait("reconnect_first_accepted_native_snapshot_ready", lambda: self.accepted("guest_reconnect"), 40, ("host", "guest_reconnect"))
        rejoined = self.state("guest_reconnect")
        self.check("same_disk_profile_UUID_reconnect", rejoined.get("profile_uuid") == first_uuid
                   and rejoined.get("initial_uuid") == first_uuid
                   and rejoined.get("profile") == first.get("profile"),
                   {"first": first_uuid, "reconnected": rejoined.get("profile_uuid"), "profile": rejoined.get("profile")})
        if self.region == "I2":
            self.check("reconnect_first_motion_snapshot_has_full_native_Canal", rejoined["first_accepted"]["canal"].get("native_ok") is True
                       and rejoined["first_accepted"].get("canal_epoch", 0) > 0
                       and rejoined["first_accepted"]["canal"]["status"].get("epoch") == rejoined["first_accepted"]["canal_epoch"], rejoined["first_accepted"])
        else:
            self.wait("same_UUID_remaps_actual_unique_load", lambda: self.cargo_carried("guest_reconnect"), 18, ("host", "guest_reconnect"))
            cargo = self.state("host")["cargo"]
            self.check("same_cargo_body_new_actual_carrier_body", cargo["body_id"] == original_cargo_body
                       and cargo["carried"][0]["body_id"] != original_actor_body, cargo)
            self.check("reconnected_guest_first_snapshot_is_paused_loaded", rejoined["first_accepted"].get("paused") is True
                       and rejoined["first_accepted"].get("cargo", {}).get("presentation", {}).get("role_identity") == first_uuid, rejoined["first_accepted"])
            if self.args.loadout_case:
                self.check_loadouts("guest_reconnect", reconnect=True)
            self.pause_pair("guest_reconnect", False)
            physics = self.state("guest_reconnect")["latest_accepted"]["physics_frame"]
            self.wait("ordinary_post_resume_physics_retains_unique_load", lambda: self.cargo_carried("guest_reconnect")
                      and self.state("guest_reconnect").get("latest_accepted", {}).get("physics_frame", 0) >= physics + 12, 10, ("host", "guest_reconnect"))
            resumed = self.save_and_read("resumed_original_save")
            if self.args.loadout_case:
                self.check("resume_and_original_Store_preserve_B_not_A", resumed.get("environment", {}).get("flight", {}).get("build") == self.saved_role_build)
                self.check_loadouts("guest_reconnect", reconnect=True, resumed=True)
            if self.args.loadout_variant == "HBA_BURST":
                self.check_weapon_owner("guest_reconnect", resumed=True)
        self.milestone("same_profile_reconnect_ready", "host", "guest_reconnect")
        self.disconnect("guest_reconnect")
        self.wait("second_original_departure_complete", lambda: len(self.state("host").get("players", {})) == 1, 15, ("host",))
        host = self.state("host")
        self.check("host_exactly_two_real_ENet_joins_and_leaves", host.get("stats", {}).get("guest_joins") == 2 and host.get("stats", {}).get("guest_leaves") == 2, host.get("stats"))
        self.check("snapshot_codec_zero_rejections", host.get("transport", {}).get("snapshot_encode_rejections") == 0, host.get("transport"))
        self.check("real_encoded_snapshots_published", host.get("transport", {}).get("snapshots_sent", 0) > 0, host.get("transport"))
        self.disconnect("host")

    def i4_paused_match(self) -> bool:
        host, guest = self.state("host"), self.state("guest_first")
        h, g = host.get("i4", {}), guest.get("i4", {})
        probe = g.get("probe", {})
        local = str(guest.get("local_peer"))
        actor = guest.get("players", {}).get(local, {})
        return bool(host.get("paused") is True and guest.get("paused") is True
                    and g.get("available") is True and g.get("installed") is True
                    and probe.get("ok") is True and probe.get("role") == "guest"
                    and probe.get("session_id") == guest.get("session_id") == host.get("session_id")
                    and probe.get("sequence", -1) >= 0
                    and probe.get("world_clock") == g.get("world_clock") == h.get("world_clock")
                    and probe.get("body_id") == actor.get("body_id") == g.get("body_id")
                    and g.get("body_space") == g.get("world_space") and g.get("frozen") is True
                    and g.get("observed_identity") == guest.get("profile_uuid"))

    def i4_short_scenario(self) -> None:
        self.command("host", "place_i4_guest")
        self.wait("I4_original_pose_packet_and_actual_field", lambda: self.state("guest_first").get("i4", {}).get("available") is True
                  and self.state("guest_first").get("i4", {}).get("observed_identity") == self.state("guest_first").get("profile_uuid"), 8, ("host", "guest_first"))
        # Natural phase only: never write clock, phase, field, HUD or cached sample.
        self.wait("I4_natural_easing", lambda: self.state("guest_first").get("i4", {}).get("cached_phase") == "easing"
                  and self.state("guest_first").get("i4", {}).get("available") is True, 35, ("host", "guest_first"))
        self.milestone("I4_real_natural_easing_before_common_pause", "host", "guest_first")
        before_host, before_guest = self.state("host"), self.state("guest_first")
        before_sequence = before_guest.get("received_sequence", -1)
        first_uuid = before_guest.get("profile_uuid")
        self.pause_pair("guest_first", True)
        self.wait("I4_new_paused_snapshot_fresh_native_sample_and_visible_HUD", lambda: self.i4_paused_match()
                  and self.state("guest_first").get("received_sequence", -1) > before_sequence, 12, ("host", "guest_first"))
        frozen_host, frozen_guest = self.state("host"), self.state("guest_first")
        h, g = frozen_host["i4"], frozen_guest["i4"]
        probe = g["probe"]
        self.check("I4.real_Guest_cache_matches_fresh_query_and_original_visible_Label", probe.get("differences") == []
                   and probe.get("fresh_query_did_not_mutate_clock_or_pose") is True
                   and probe.get("hud_visible") is True and probe.get("hud_text") == probe.get("expected_hud")
                   and "罗盘约" in probe.get("hud_text", "") and "±" in probe.get("hud_text", ""), probe)
        self.wait("I4_paused_ordinary_frames_continue_without_clock_advance", lambda: self.i4_paused_match()
                  and self.state("guest_first").get("i4", {}).get("physics_frame", 0) >= g["physics_frame"] + 12
                  and self.state("guest_first").get("i4", {}).get("probe", {}).get("process_frame", 0) > probe["process_frame"], 5, ("host", "guest_first"))
        held_host, held_guest = self.state("host"), self.state("guest_first")
        for label, initial, held in [("host", h, held_host["i4"]), ("guest", g, held_guest["i4"])]:
            self.check("I4." + label + ".pause_preserves_clock_native_body_and_space",
                       held.get("world_clock") == initial.get("world_clock")
                       and all(held.get(key) == initial.get(key) for key in ("world_id", "world_space", "body_id", "body_rid", "body_space", "position", "native_position", "native_basis"))
                       and held.get("frozen") is True, {"before": initial, "after": held})
        self.check("I4.paused_phase_countdown_and_HUD_remain_frozen", held_guest["i4"]["probe"].get("expected") == probe.get("expected")
                   and held_guest["i4"]["probe"].get("hud_text") == probe.get("hud_text"), held_guest["i4"]["probe"])
        self.milestone("I4_common_pause_native_cache_HUD_and_clock_hold", "host", "guest_first")
        disk = self.save_and_read("I4_original_paused_save")
        self.check("I4.original_Store_saves_actual_current_campaign_state", disk.get("environment_key") == "campaign_I4"
                   and self.state("host").get("region") == "I4" and disk.get("environment", {}).get("version") == 1, disk)
        self.pause_pair("guest_first", False)
        self.wait("I4_resume_original_clock_and_sample_advance", lambda: self.state("host").get("i4", {}).get("world_clock", -1) > h["world_clock"]
                  and self.state("guest_first").get("i4", {}).get("cached_clock", -1) > g["world_clock"]
                  and self.state("guest_first").get("i4", {}).get("physics_frame", 0) > g["physics_frame"]
                  and self.state("guest_first").get("paused") is False, 10, ("host", "guest_first"))
        resumed_host, resumed_guest = self.state("host"), self.state("guest_first")
        self.check("I4.original_UUIDs_session_and_actual_bodies_retained_after_resume", resumed_guest.get("profile_uuid") == first_uuid
                   and resumed_host.get("profile_uuid") == before_host.get("profile_uuid")
                   and resumed_guest.get("session_id") == resumed_host.get("session_id") == before_host.get("session_id")
                   and all(resumed_guest["i4"].get(key) == g.get(key) for key in ("world_id", "world_space", "body_id", "body_rid", "body_space")), resumed_guest["i4"])
        self.check("I4.no_Story_progress_fabricated", resumed_host.get("story_completed") == before_host.get("story_completed"), resumed_host.get("story_completed"))
        self.milestone("I4_original_common_resume_and_live_clock", "host", "guest_first")
        self.save_and_read("I4_original_resumed_save")
        self.disconnect("guest_first")
        self.wait("I4_one_original_Guest_departure", lambda: len(self.state("host").get("players", {})) == 1, 15, ("host",))
        host = self.state("host")
        self.check("I4.exactly_one_real_ENet_join_and_leave", host.get("stats", {}).get("guest_joins") == 1 and host.get("stats", {}).get("guest_leaves") == 1, host.get("stats"))
        self.check("snapshot_codec_zero_rejections", host.get("transport", {}).get("snapshot_encode_rejections") == 0, host.get("transport"))
        self.check("real_encoded_snapshots_published", host.get("transport", {}).get("snapshots_sent", 0) > 0, host.get("transport"))
        self.disconnect("host")

    def execute(self) -> int:
        try:
            self.scenario()
        except BaseException as exc:
            self.summary["error"] = f"{type(exc).__name__}: {exc}"
            (self.output / "orchestration-error.log").write_text(traceback.format_exc(), encoding="utf-8")
        finally:
            # Only this worker's exact child handles; never process-name killing.
            for label, (process, log, _started) in self.running.items():
                if log.closed:
                    continue
                try:
                    if process.poll() is None:
                        self.disconnect(label)
                    else:
                        self.finish(label, 0)
                except BaseException as exc:
                    self.summary.setdefault("cleanup_errors", []).append(f"{label}: {exc}")
            self.summary["executable_sha256_after"] = sha256(self.exe)
            self.summary["executable_unchanged"] = self.summary["executable_sha256_after"] == self.summary["executable_sha256"]
            self.summary["all_owned_processes_exited"] = all(process.poll() is not None for process, _, _ in self.running.values())
            self.summary["finished_utc"] = utc_now()
            self.summary["elapsed_wall_seconds"] = round(time.monotonic()-self.started, 3)
            self.summary["passed"] = bool(self.summary["error"] is None and not self.summary.get("cleanup_errors")
                and len(self.running) == (2 if self.region == "I4" else 3) and self.summary["executable_unchanged"]
                and (self.region != "I4" or set(self.running) == {"host", "guest_first"})
                and self.summary["all_owned_processes_exited"] and all(row["passed"] for row in self.summary["checks"]))
            write_json(self.output / "summary.json", self.summary)
        print(json.dumps({"passed": self.summary["passed"], "scenario": self.region,
                          "evidence": str(self.output), "checks": len(self.summary["checks"]),
                          "error": self.summary["error"], "executable_sha256": self.summary["executable_sha256"],
                          "scope": self.summary["scope"]}, ensure_ascii=False), flush=True)
        return 0 if self.summary["passed"] else 1


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exe", type=Path, required=True, help="Absolute actual export-debug EXE; App must include this explicit suite.")
    parser.add_argument("--scenario", choices=["I2", "I3", "I4"], default="I2")
    parser.add_argument("--loadout-case", action="store_true",
                        help="I3 only: original Hangar saves distinct nondefault H/B; same UUID requests local A on reconnect, saved cargo must restore B.")
    parser.add_argument("--loadout-variant", choices=["HBA", "HBA_BURST"], default="HBA",
                        help="Optional HBA_BURST requires --loadout-case/I3; original HBA remains unchanged. Idle owner HUD transport only, no LAN firing.")
    parser.add_argument("--verbose-guests", action="store_true",
                        help="Request engine --verbose only for guest processes; retain original leak failures.")
    parser.add_argument("--verbose-host", action="store_true",
                        help="Request engine --verbose only for the host; independent of --verbose-guests.")
    parser.add_argument("--run", action="store_true", help="Start the selected real package; otherwise print preparation only.")
    parser.add_argument("--owned-worker", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--run-id", default=None, help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.loadout_variant == "HBA_BURST" and not args.loadout_case:
        parser.error("HBA_BURST requires --loadout-case; original HBA/default semantics are unchanged")
    if args.loadout_case and args.scenario != "I3":
        parser.error("--loadout-case requires --scenario I3; default I2/I3 cases are unchanged")
    if not args.exe.is_absolute() or not args.exe.is_file() or args.exe.suffix.lower() != ".exe":
        parser.error("--exe must be an existing absolute exported Windows .exe")
    if not args.run:
        print(json.dumps({"status": "prepared_only_no_process_started", "exe": str(args.exe.resolve()),
                          "executable_sha256": sha256(args.exe), "scenario": args.scenario,
                          "verbose_guests": args.verbose_guests,
                          "verbose_host": args.verbose_host,
                          "loadout_case": args.loadout_case,
                          "loadout_variant": args.loadout_variant,
                          "run": [sys.executable, str(Path(__file__).resolve()), "--exe", str(args.exe.resolve()), "--scenario", args.scenario, "--run"] + (["--verbose-guests"] if args.verbose_guests else []) + (["--verbose-host"] if args.verbose_host else []) + (["--loadout-case"] if args.loadout_case else []) + (["--loadout-variant", "HBA_BURST"] if args.loadout_variant == "HBA_BURST" else []),
                          "requires": "Root integrates the QA child into ordinary App and exports that exact debug package; protocol25 with explicit ambient presentation; original profile gates unchanged.",
                          "scope": "127.0.0.1, not two-PC LAN"}, ensure_ascii=False, indent=2))
        return 0
    if not args.owned_worker:
        run_id = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
        output = args.exe.resolve().parent / "artifacts/v3/network/environment" / args.scenario / run_id
        output.mkdir(parents=True, exist_ok=False)
        dev.EVIDENCE = output / "driver"
        command = [sys.executable, "-B", str(Path(__file__).resolve()), "--exe", str(args.exe.resolve()),
                   "--scenario", args.scenario, "--run", "--owned-worker", "--run-id", run_id]
        if args.verbose_guests:
            command.append("--verbose-guests")
        if args.verbose_host:
            command.append("--verbose-host")
        if args.loadout_case:
            command.append("--loadout-case")
        if args.loadout_variant == "HBA_BURST":
            command.extend(["--loadout-variant", "HBA_BURST"])
        print(f"LAN_ENVIRONMENT evidence={output}", flush=True)
        dev.execute_command(command, "controller", JOB_SECONDS)
        summary = read_json(output / "summary.json")
        print(json.dumps({"passed": summary.get("passed", False), "evidence": str(output),
                          "error": summary.get("error"), "scope": summary.get("scope")}, ensure_ascii=False))
        return 0 if summary.get("passed") is True else 1
    import re
    if not args.run_id or not re.fullmatch(r"[0-9]{8}_[0-9]{6}_[0-9]{6}", args.run_id):
        parser.error("owned worker requires exact generated run ID")
    output = args.exe.resolve().parent / "artifacts/v3/network/environment" / args.scenario / args.run_id
    if not output.is_dir():
        parser.error("worker evidence directory was not prepared")
    lock = LanPortLock()
    try:
        lock.acquire()
    except LanRunBusy as exc:
        print(f"REFUSED: {exc}; no game process started.", file=sys.stderr)
        return 3
    except OSError as exc:
        print(f"REFUSED: shared port lock unavailable: {exc}; no game process started.", file=sys.stderr)
        return 2
    try:
        return EnvironmentRun(args, lock).execute()
    finally:
        lock.release()


if __name__ == "__main__":
    raise SystemExit(main())
