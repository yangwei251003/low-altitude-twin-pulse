"""Candidate only. Root invokes through dev.execute_command(..., timeout=55)."""
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

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--packed-exe", type=Path, help="Current immutable EXE resources through pinned editor; not a direct Release EXE launch")
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
        raise RuntimeError("Pinned source Godot required; no exported EXE")
    artifact = None
    if args.packed_exe:
        exe = plain_path(args.packed_exe, existing=True)
        current = dev.POLICY._index().get("current")
        if exe != dev.POLICY.path("builds", current, "LowAltitudeTwinPulse-Dev.exe"):
            raise RuntimeError("Only current immutable build resources are permitted")
        artifact = {"exe":str(exe),"sha256":dev.file_sha256(exe),
                    "build":json.loads((exe.parent/"BUILD.json").read_text(encoding="utf-8"))}
    candidate = plain_path(Path(__file__).parent / "probe_npc_contact_lan.gd", existing=True)
    dev.POLICY.preflight("evidence", 3 * 1024**2)
    dev.LOG_LIMIT = 1024**2
    os.environ["LOW_ALTITUDE_DEV_HOME"] = str(dev.POLICY.root)
    run_id = datetime.now().strftime("%Y%m%d_%H%M%S_") + uuid.uuid4().hex[:6]
    evidence = dev.POLICY.path("evidence", "npc-contact-lan-" + run_id)
    evidence.mkdir(exist_ok=False)
    watched = [candidate, Path(__file__), root/"scripts/v3/ecology/twin_npc_contact.gd", root/"scripts/v3/ecology/twin_npc_anchors.gd", root/"scripts/v3/ecology/twin_living_world.gd", root/"scripts/v3/gameplay/twin_opening_story.gd", root/"scripts/v3/twin_session.gd", root/"scripts/v3/twin_network.gd", root/"scripts/v3/twin_interface.gd"]
    def hashes():
        return {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in watched}
    before = hashes()
    summary = {"run_id":run_id, "evidence":str(evidence), "passed":False,
               "scope":"same-PC two-source-MAIN ENet loopback; not physical LAN, graphics or human play",
               "processes":{}, "reports":{}, "error":None, "source_before":before,"artifact":artifact}
    lock = LanPortLock()
    began = time.monotonic()
    futures = {}
    def run_peer(role):
        profile = "qa_npc_contact_lan_" + role + "_" + run_id
        command = [str(godot), "--headless", "--path", str(root)]
        if artifact:
            command += ["--main-pack",artifact["exe"]]
        command += ["--script", str(candidate), "--",
                   "--qa-profile="+profile, "--contact-role="+role, "--contact-run="+run_id,
                   "--contact-evidence="+str(evidence)]
        with (evidence/(role+".log")).open("xb", buffering=0) as stream:
            result = dev._windows_run(command, stream, 30)
        result.update(profile=profile, command=command)
        return result
    try:
        lock.acquire()
        summary["port_lock"] = {"path":str(lock.path), "port":26742, "backend":lock.backend, "held":True}
        # Each peer owns a separate private Windows Job. No unowned Popen or image kill.
        with ThreadPoolExecutor(max_workers=2) as pool:
            futures["host"] = pool.submit(run_peer, "host")
            ready_deadline = began + 8.0
            while not (evidence/"host-started.json").exists():
                if futures["host"].done():
                    raise RuntimeError("Host exited before original MAIN host readiness")
                if time.monotonic() >= ready_deadline:
                    raise TimeoutError("Host readiness exceeded8s; Guest not launched")
                time.sleep(.05)
            futures["guest"] = pool.submit(run_peer, "guest")
            for role, future in futures.items():
                summary["processes"][role] = future.result(timeout=max(.1, began+49-time.monotonic()))
    except BaseException as exc:
        summary["error"] = f"{type(exc).__name__}: {exc}"[:1024]
    finally:
        for role, future in futures.items():
            if future.done() and role not in summary["processes"]:
                try: summary["processes"][role] = future.result()
                except BaseException as exc: summary["processes"][role] = {"error":str(exc)[:512]}
        lock.release()
    for role in ("host", "guest"):
        path = evidence/(role+".json")
        try:
            if path.stat().st_size > 65536: raise ValueError("Peer report exceeds64KiB")
            report = json.loads(path.read_text(encoding="utf-8-sig"))
            if artifact and (report.get("version") != artifact["build"]["version"] or report.get("protocol") != artifact["build"]["network_protocol"]):
                raise ValueError("Loaded pack version/protocol differs from current BUILD")
            summary["reports"][role] = report
        except (OSError, ValueError) as exc:
            summary["reports"][role] = {"passed":False, "error":str(exc)[:512]}
        log = evidence/(role+".log")
        raw = log.read_text(encoding="utf-8", errors="replace") if log.exists() else ""
        record = summary["processes"].setdefault(role,{})
        record["engine_error_lines"] = [line[:512] for line in raw.splitlines() if line.startswith(("ERROR:","SCRIPT ERROR:"))][:16]
        record["audio_shutdown_ready"] = False
        for line in raw.splitlines():
            if line.startswith("V3_AUDIO_SHUTDOWN_EXIT "):
                try: record["audio_shutdown_ready"] = json.loads(line.split(" ",1)[1]).get("ready") is True
                except ValueError: pass
        record["natural_clean_exit"] = (record.get("returncode")==0 and record.get("remaining_owned_processes")==0 and not any(record.get(k) for k in ("timed_out","orphan_cleanup","output_stopped","output_limit_exceeded","log_error")))
    summary["source_after"] = hashes()
    summary["source_unchanged"] = before == summary["source_after"]
    summary["seconds"] = round(time.monotonic()-began,3)
    summary["passed"] = (summary["error"] is None and summary["source_unchanged"] and summary["seconds"]<=55
                         and all(summary["reports"][r].get("passed") and summary["processes"][r].get("natural_clean_exit") and summary["processes"][r].get("audio_shutdown_ready") and not summary["processes"][r]["engine_error_lines"] for r in ("host","guest")))
    (evidence/"summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2)+"\n",encoding="utf-8")
    print(json.dumps({"passed":summary["passed"],"evidence":str(evidence),"seconds":summary["seconds"],"error":summary["error"]},ensure_ascii=False),flush=True)
    return 0 if summary["passed"] else 1

if __name__ == "__main__":
    raise SystemExit(main())
