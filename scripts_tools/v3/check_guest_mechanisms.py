"""Two actual MAIN/ENet peers through pinned editor; optionally load current84 pack resources."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import sys
import time
import uuid
sys.dont_write_bytecode = True
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--packed-exe", type=Path,
                        help="Current immutable84 EXE resources via pinned editor, not a standalone Release launch")
    args = parser.parse_args()
    sys.path.insert(0, str(args.root / "scripts_tools/v3"))
    import dev
    from storage_policy import plain_path
    from test_lan_local import LanPortLock
    root = plain_path(args.root, existing=True)
    if root != dev.ROOT.resolve():
        raise RuntimeError("Only the real current project is permitted")
    godot = plain_path(args.godot, existing=True)
    if godot.name != "Godot_v4.7.2-stable_win64_console.exe":
        raise RuntimeError("Pinned editor required; never exported --script")
    probe = plain_path(Path(__file__).parent / "probe_guest_mechanisms.gd", existing=True)
    artifact = None
    if args.packed_exe:
        exe = plain_path(args.packed_exe, existing=True)
        current = dev.POLICY._index().get("current")
        if exe != dev.POLICY.path("builds", current, "LowAltitudeTwinPulse-Dev.exe"):
            raise RuntimeError("Only the current registered immutable build is permitted")
        build = json.loads((exe.parent / "BUILD.json").read_text(encoding="utf-8-sig"))
        if build.get("version") != "3.0.0-dev.84" or build.get("network_protocol") != 27:
            raise RuntimeError("Actual84/LAN27 resources required")
        artifact = {"exe": str(exe), "sha256": dev.file_sha256(exe), "build": build}
    dev.POLICY.preflight_qa(128 * 1024**2)
    dev.POLICY.preflight("evidence", 3 * 1024**2)
    dev.LOG_LIMIT = 1024**2
    os.environ["LOW_ALTITUDE_DEV_HOME"] = str(dev.POLICY.root)
    run_id = datetime.now().strftime("%Y%m%d_%H%M%S_") + uuid.uuid4().hex[:6]
    evidence = dev.POLICY.path("evidence", "guest-mechanisms-" + run_id)
    evidence.mkdir(exist_ok=False)
    watched = [probe, Path(__file__)] + [root / p for p in (
        "scripts/v3/twin_session.gd", "scripts/v3/twin_network.gd",
        "scripts/v3/twin_test_world.gd", "scripts/v3/network/twin_snapshot_codec.gd",
        "scripts/v3/gameplay/twin_opening_story.gd", "scripts/v3/gameplay/twin_ability_rules.gd",
        "scripts/v3/gameplay/twin_campaign_session.gd", "scripts/v3/campaign/twin_campaign_mechanisms.gd",
        "scripts/v3/campaign/twin_optical_path.gd", "scripts/v3/world/twin_campaign_mechanism_view.gd",
        "data/v3/campaign/physical_bindings.json", "project.godot")]

    def hashes():
        return {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in watched}

    before = hashes()
    commands = {}
    for role in ("host", "guest"):
        profile = "qa_guest_mechanisms_" + role + "_" + run_id
        command = [str(godot), "--headless", "--path", str(root)]
        if artifact:
            command += ["--main-pack", artifact["exe"]]
        commands[role] = command + ["--script", str(probe), "--", "--qa-profile=" + profile,
                                   "--mechanism-role=" + role, "--mechanism-run=" + run_id,
                                   "--mechanism-evidence=" + str(evidence)]
    summary = {"run_id": run_id, "evidence": str(evidence), "passed": False,
               "scope": "same-PC source MAIN ENet; optional84 pack resources through pinned editor, not direct Release/2PC/graphics/natural campaign",
               "processes": {}, "reports": {}, "error": None, "source_before": before,
               "artifact": artifact, "commands": commands}
    (evidence / "prepared.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    lock = LanPortLock()
    began = time.monotonic()
    futures = {}

    def run_peer(role):
        with (evidence / (role + ".log")).open("xb", buffering=0) as stream:
            return dev._windows_run(commands[role], stream, 100)

    try:
        lock.acquire()
        summary["port_lock"] = {"path": str(lock.path), "port": 26742, "backend": lock.backend}
        with ThreadPoolExecutor(max_workers=2) as pool:
            futures["host"] = pool.submit(run_peer, "host")
            while not (evidence / "host-started.json").exists():
                if futures["host"].done():
                    raise RuntimeError("Host ended before real F2 host readiness")
                if time.monotonic() - began >= 35:
                    raise TimeoutError("Host F2 readiness exceeded35s; Guest not started")
                time.sleep(.05)
            futures["guest"] = pool.submit(run_peer, "guest")
            for role, future in futures.items():
                summary["processes"][role] = future.result(timeout=max(.1, began + 137 - time.monotonic()))
    except BaseException as exc:
        summary["error"] = f"{type(exc).__name__}: {exc}"[:1024]
    finally:
        for role, future in futures.items():
            if future.done() and role not in summary["processes"]:
                try:
                    summary["processes"][role] = future.result()
                except BaseException as exc:
                    summary["processes"][role] = {"error": str(exc)[:512]}
        lock.release()
    for role in ("host", "guest"):
        try:
            path = evidence / (role + ".json")
            if path.stat().st_size > 65536:
                raise ValueError("Peer report exceeds64KiB")
            report = json.loads(path.read_text(encoding="utf-8-sig"))
            if report.get("version") != "3.0.0-dev.84" or report.get("protocol") != 27:
                raise ValueError("Peer did not load actual84/LAN27 resources")
            if report.get("profile") != "qa_guest_mechanisms_" + role + "_" + run_id:
                raise ValueError("Peer profile does not match this fresh run")
            summary["reports"][role] = report
        except (OSError, ValueError) as exc:
            summary["reports"][role] = {"passed": False, "error": str(exc)[:512]}
        path = evidence / (role + ".log")
        record = summary["processes"].setdefault(role, {})
        record["engine_error_lines"] = []
        record["audio_shutdown_ready"] = False
        if path.exists():
            with path.open(encoding="utf-8", errors="replace") as stream:
                for line in stream:
                    if line.startswith(("ERROR:", "SCRIPT ERROR:", "GUEST_MECHANISMS_QUIT_WATCHDOG_FAILED")) and len(record["engine_error_lines"]) < 16:
                        record["engine_error_lines"].append(line[:512])
                    if line.startswith("V3_AUDIO_SHUTDOWN_EXIT "):
                        try:
                            record["audio_shutdown_ready"] = json.loads(line.split(" ", 1)[1]).get("ready") is True
                        except ValueError:
                            pass
        record["natural_clean_exit"] = (record.get("returncode") == 0 and record.get("remaining_owned_processes") == 0
            and not any(record.get(k) for k in ("timed_out", "orphan_cleanup", "output_stopped", "output_limit_exceeded", "log_error")))
    summary["source_after"] = hashes()
    summary["source_unchanged"] = before == summary["source_after"]
    summary["seconds"] = round(time.monotonic() - began, 3)
    summary["passed"] = (summary["error"] is None and summary["source_unchanged"] and summary["seconds"] <= 140
        and all(summary["reports"][r].get("passed") and summary["processes"][r].get("natural_clean_exit")
                and summary["processes"][r].get("audio_shutdown_ready") and not summary["processes"][r]["engine_error_lines"]
                for r in ("host", "guest")))
    (evidence / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: summary[k] for k in ("passed", "evidence", "seconds", "error")}, ensure_ascii=False), flush=True)
    return 0 if summary["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
