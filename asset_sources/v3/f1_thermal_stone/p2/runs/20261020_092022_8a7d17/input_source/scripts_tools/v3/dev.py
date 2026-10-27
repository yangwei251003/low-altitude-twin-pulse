"""Pinned local tools for the V3 development project; no V2 player save writes."""
import argparse
import datetime
import json
import hashlib
import os
import re
from pathlib import Path
import subprocess
import shutil
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]
GODOT = Path(os.environ["LOCALAPPDATA"]) / "Programs/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe"
EVIDENCE = ROOT / "artifacts/v3"
TEST_TIMEOUT = 120
IMPORT_TIMEOUT = 600
EXPORT_TIMEOUT = 900
CAPTURE_TIMEOUT = 240
LAN_TIMEOUT = 420  # Multi-scenario controllers; their engine children share our job.


def _windows_run(command, output, timeout):
    """Start suspended, attach our private job, then resume: no child-spawn race.

    Windows owns descendant membership, even if the original process exits.
    Never enumerate/kill by image name or an unrelated/recycled PID.
    https://learn.microsoft.com/windows/win32/procthread/job-objects
    """
    import _winapi
    import ctypes as ct
    from ctypes import wintypes as wt
    import msvcrt

    class BasicLimit(ct.Structure):
        _fields_ = [("process_time", ct.c_longlong), ("job_time", ct.c_longlong),
                    ("flags", wt.DWORD), ("min_working_set", ct.c_size_t),
                    ("max_working_set", ct.c_size_t), ("active_limit", wt.DWORD),
                    ("affinity", ct.c_size_t), ("priority", wt.DWORD), ("scheduling", wt.DWORD)]

    class ExtendedLimit(ct.Structure):
        _fields_ = [("basic", BasicLimit), ("io_counters", ct.c_ulonglong * 6),
                    ("memory_limits", ct.c_size_t * 4)]

    class Accounting(ct.Structure):
        _fields_ = [("times", ct.c_longlong * 4), ("page_faults", wt.DWORD),
                    ("total", wt.DWORD), ("active", wt.DWORD), ("terminated", wt.DWORD)]

    kernel = ct.WinDLL("kernel32", use_last_error=True)
    signatures = {
        "CreateJobObjectW": ([ct.c_void_p, wt.LPCWSTR], wt.HANDLE),
        "SetInformationJobObject": ([wt.HANDLE, ct.c_int, ct.c_void_p, wt.DWORD], wt.BOOL),
        "QueryInformationJobObject": ([wt.HANDLE, ct.c_int, ct.c_void_p, wt.DWORD, ct.c_void_p], wt.BOOL),
        "AssignProcessToJobObject": ([wt.HANDLE, wt.HANDLE], wt.BOOL),
        "TerminateJobObject": ([wt.HANDLE, wt.UINT], wt.BOOL),
        "ResumeThread": ([wt.HANDLE], wt.DWORD),
    }
    for name, (arguments, result) in signatures.items():
        getattr(kernel, name).argtypes = arguments
        getattr(kernel, name).restype = result

    def require(ok):
        if not ok:
            raise ct.WinError(ct.get_last_error())

    job = kernel.CreateJobObjectW(None, None)  # Unnamed, non-inheritable, owned here.
    require(job)
    process = thread = None
    assigned = False
    try:
        limits = ExtendedLimit()
        limits.basic.flags = 0x2000  # JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE; no breakaway.
        require(kernel.SetInformationJobObject(job, 9, ct.byref(limits), ct.sizeof(limits)))
        with open(os.devnull, "rb") as stdin:
            handles = [msvcrt.get_osfhandle(stdin.fileno()), msvcrt.get_osfhandle(output.fileno())]
            startup = subprocess.STARTUPINFO()
            startup.dwFlags = subprocess.STARTF_USESTDHANDLES
            startup.hStdInput, startup.hStdOutput, startup.hStdError = handles[0], handles[1], handles[1]
            startup.lpAttributeList = {"handle_list": handles}
            inherited = [os.get_handle_inheritable(handle) for handle in handles]
            try:
                for handle in handles:
                    os.set_handle_inheritable(handle, True)
                process, thread, pid, _ = _winapi.CreateProcess(
                    command[0], subprocess.list2cmdline(command), None, None, True,
                    0x4 | subprocess.CREATE_NO_WINDOW,  # CREATE_SUSPENDED
                    None, str(ROOT), startup)
            finally:
                for handle, original in zip(handles, inherited):
                    os.set_handle_inheritable(handle, original)
        require(kernel.AssignProcessToJobObject(job, process))
        assigned = True
        require(kernel.ResumeThread(thread) != 0xFFFFFFFF)
        deadline = time.monotonic() + timeout
        timed_out = False
        while _winapi.WaitForSingleObject(process, 100) == _winapi.WAIT_TIMEOUT:
            if time.monotonic() >= deadline:
                timed_out = True
                break
        code = 124 if timed_out else _winapi.GetExitCodeProcess(process)
        accounting = Accounting()
        require(kernel.QueryInformationJobObject(job, 1, ct.byref(accounting), ct.sizeof(accounting), None))
        # A signalled root handle can precede the job's active-count update.
        # Allow that bounded bookkeeping tail before diagnosing orphan children.
        settle_deadline = time.monotonic() + 0.25
        while not timed_out and accounting.active and time.monotonic() < settle_deadline:
            time.sleep(0.01)
            require(kernel.QueryInformationJobObject(job, 1, ct.byref(accounting), ct.sizeof(accounting), None))
        orphaned = not timed_out and accounting.active > 0
        # Also clean descendants if their parent exits naturally or fails early.
        require(kernel.TerminateJobObject(job, 124 if timed_out else 1))
        cleanup_deadline = time.monotonic() + 5.0
        while True:
            require(kernel.QueryInformationJobObject(job, 1, ct.byref(accounting), ct.sizeof(accounting), None))
            if accounting.active == 0:
                break
            if time.monotonic() >= cleanup_deadline:
                raise RuntimeError("Owned job did not become empty within cleanup deadline")
            time.sleep(0.02)
        return {"returncode":code, "timed_out":timed_out, "orphan_cleanup":orphaned,
                "pid":pid, "remaining_owned_processes":int(accounting.active)}
    finally:
        # On setup/interrupt failure the process may still be suspended, before
        # assignment. Kill that exact handle; otherwise job close owns cleanup.
        if process is not None and not assigned:
            _winapi.TerminateProcess(process, 1)
        _winapi.CloseHandle(job)
        if thread is not None:
            _winapi.CloseHandle(thread)
        if process is not None:
            _winapi.CloseHandle(process)


def execute_command(command, label, timeout):
    """Bounded non-interactive command; emitted stdout goes directly to evidence."""
    if not 0 < timeout <= 7200:
        raise ValueError("Automated timeout must be explicit and between 0 and 7200 seconds")
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    log = EVIDENCE / (label + ".log")
    began = time.monotonic()
    result = {"returncode":1, "timed_out":False}
    # A regular file avoids communicate() hanging on inherited child pipe ends;
    # it also preserves already-emitted output if the driver is interrupted.
    with log.open("xb", buffering=0) as output:
        try:
            result = _windows_run([str(value) for value in command], output, timeout)
        except (OSError, RuntimeError, KeyboardInterrupt) as error:
            result["error"] = f"{type(error).__name__}: {error}"
    stdout = log.read_text(encoding="utf-8", errors="replace")
    bad = result["returncode"] != 0 or result["timed_out"] or result.get("orphan_cleanup", False) or "ERROR:" in stdout
    result.update(timeout_seconds=timeout, elapsed_seconds=round(time.monotonic() - began, 3), passed=not bad)
    with log.open("a", encoding="utf-8") as output:
        output.write("\nDEV_RUN_RESULT " + json.dumps(result, ensure_ascii=False) + "\n")
    outcome = "FAIL timeout" if result["timed_out"] else "FAIL" if bad else "PASS"
    print(f'{label}: {outcome} ({log})')
    if bad:
        print(stdout[-6000:])
        print(json.dumps(result, ensure_ascii=False))
        raise SystemExit(result["returncode"] or 1)
    return result


def execute(args, label, timeout=None):
    if timeout is None:
        timeout = (IMPORT_TIMEOUT if "--import" in args else
                   EXPORT_TIMEOUT if "--export-debug" in args else
                   TEST_TIMEOUT if "--headless" in args else CAPTURE_TIMEOUT)
    return execute_command([str(GODOT), "--path", str(ROOT), *args], label, timeout)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["run", "import", "test", "test-logic", "capture", "capture-assets", "capture-kit", "capture-whale", "capture-crown", "capture-shore", "capture-growth-crossing", "capture-guidance", "capture-growth-approach-west-p1", "capture-growth-approach-west-p2", "capture-rootstone-candidate", "capture-rising-seal-integrated", "capture-forest-floor-integrated", "capture-hud-visibility", "capture-thermal-bypass-integrated", "capture-underdeck-integrated", "capture-clinic-integrated", "capture-distribution-integrated", "capture-pump-integrated", "capture-trial-candidate", "capture-trial-integrated", "capture-shared-access-integrated", "capture-waterfront-integrated", "capture-combat", "capture-living-world", "profile-crown-smoke", "profile-crown", "profile-crown-endurance", "export", "export-candidate"])
    options = parser.parse_args()
    if not GODOT.is_file():
        raise SystemExit(f"Pinned Godot 4.7.2 is missing: {GODOT}")
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S") + "_" + uuid.uuid4().hex[:6]
    if options.action == "run":
        return subprocess.call([str(GODOT), "--path", str(ROOT)], cwd=ROOT)
    if options.action == "import":
        execute(["--headless", "--editor", "--import", "--quit"], "import-" + stamp)
    elif options.action == "capture":
        execute(["--script", "res://scripts_tools/v3/capture_graybox.gd", "--",
                 "--qa-profile=qa_visual_" + stamp], "visual-" + stamp)
    elif options.action == "capture-hud-visibility":
        output = EVIDENCE / "art" / ("hud-visibility-" + stamp)
        execute(["--rendering-method", "gl_compatibility", "--windowed", "--resolution", "1280x720",
                 "--position", "-4000,-4000", "--script", "res://scripts_tools/v3/capture_hud_visibility.gd", "--",
                 "--qa-profile=qa_visual_hud_" + stamp, "--capture-output=" + str(output)], "hud-visibility-" + stamp)
    elif options.action == "capture-clinic-integrated":
        output = EVIDENCE / "art" / ("clinic-integrated-" + stamp)
        execute(["--rendering-method", "gl_compatibility", "--windowed", "--resolution", "1280x720",
                 "--position", "-4000,-4000", "--script", "res://scripts_tools/v3/capture_clinic_integrated.gd", "--",
                 "--qa-profile=qa_visual_clinic_" + stamp, "--capture-output=" + str(output)], "clinic-integrated-" + stamp)
    elif options.action == "capture-distribution-integrated":
        output = EVIDENCE / "art" / ("clinic-integrated-distribution-" + stamp)
        execute(["--rendering-method", "gl_compatibility", "--windowed", "--resolution", "1280x720",
                 "--position", "-4000,-4000", "--script", "res://scripts_tools/v3/capture_distribution_integrated.gd", "--",
                 "--qa-profile=qa_visual_clinic_distribution_" + stamp, "--capture-output=" + str(output)], "distribution-integrated-" + stamp)
    elif options.action == "capture-pump-integrated":
        output = EVIDENCE / "art" / ("clinic-pump-integrated-" + stamp)
        execute(["--rendering-method", "gl_compatibility", "--windowed", "--resolution", "1280x720",
                 "--position", "-4000,-4000", "--script", "res://scripts_tools/v3/capture_clinic_pump_integrated.gd", "--",
                 "--qa-profile=qa_visual_clinic_pump_" + stamp, "--capture-output=" + str(output)], "pump-integrated-" + stamp)
    elif options.action == "capture-waterfront-integrated":
        output = EVIDENCE / "art" / ("clinic-integrated-waterfront-" + stamp)
        execute(["--rendering-method", "gl_compatibility", "--windowed", "--resolution", "1280x720",
                 "--position", "-4000,-4000", "--script", "res://scripts_tools/v3/capture_waterfront_integrated.gd", "--",
                 "--qa-profile=qa_visual_clinic_waterfront_" + stamp, "--capture-output=" + str(output)], "waterfront-integrated-" + stamp)
    elif options.action == "capture-shared-access-integrated":
        output = EVIDENCE / "art" / ("shared-access-integrated-" + stamp)
        execute(["--rendering-method", "gl_compatibility", "--windowed", "--resolution", "1280x720",
                 "--position", "-4000,-4000", "--script", "res://scripts_tools/v3/capture_shared_access_integrated.gd", "--",
                 "--qa-profile=qa_visual_clinic_shared_access_" + stamp, "--capture-output=" + str(output)], "shared-access-integrated-" + stamp)
    elif options.action == "capture-trial-integrated":
        output = EVIDENCE / "art" / ("trial-integrated-" + stamp)
        execute(["--rendering-method", "gl_compatibility", "--windowed", "--resolution", "1280x720",
                 "--position", "-4000,-4000", "--script", "res://scripts_tools/v3/capture_trial_integrated.gd", "--",
                 "--qa-profile=qa_visual_clinic_trial_integrated_" + stamp, "--capture-output=" + str(output)], "trial-integrated-" + stamp)
    elif options.action == "capture-trial-candidate":
        raise SystemExit("The standalone candidate is archived under dev18 evidence. Production World now owns Trial; use capture-trial-integrated.")
    elif options.action == "capture-underdeck-integrated":
        output = EVIDENCE / "art" / ("underdeck-integrated-" + stamp)
        execute(["--rendering-method", "gl_compatibility", "--windowed", "--resolution", "1280x720",
                 "--position", "-4000,-4000", "--script", "res://scripts_tools/v3/capture_underdeck_integrated.gd", "--",
                 "--qa-profile=qa_visual_underdeck_" + stamp, "--capture-output=" + str(output)], "underdeck-integrated-" + stamp)
    elif options.action == "capture-thermal-bypass-integrated":
        output = EVIDENCE / "art" / ("thermal-bypass-" + stamp)
        execute(["--rendering-method", "gl_compatibility", "--windowed", "--resolution", "1280x720",
                 "--position", "-4000,-4000", "--script", "res://scripts_tools/v3/capture_thermal_bypass_integrated.gd", "--",
                 "--qa-profile=qa_visual_thermal_" + stamp, "--capture-output=" + str(output)], "thermal-bypass-" + stamp)
    elif options.action == "capture-forest-floor-integrated":
        output = EVIDENCE / "art" / ("forest-floor-integrated-" + stamp)
        execute(["--rendering-method", "gl_compatibility", "--windowed", "--resolution", "1280x720",
                 "--position", "-4000,-4000", "--script", "res://scripts_tools/v3/capture_forest_floor_integrated.gd", "--",
                 "--qa-profile=qa_visual_forest_integrated_" + stamp, "--capture-output=" + str(output)], "forest-floor-integrated-" + stamp)
    elif options.action in ("capture-assets", "capture-kit", "capture-whale", "capture-crown", "capture-shore", "capture-growth-crossing", "capture-guidance", "capture-growth-approach-west-p1", "capture-growth-approach-west-p2", "capture-rootstone-candidate", "capture-rising-seal-integrated", "capture-combat", "capture-living-world"):
        output = EVIDENCE / "art" / ("capture-" + stamp)
        driver = options.action.replace("-", "_")
        execute(["--position", "-4000,-4000", "--script", "res://scripts_tools/v3/" + driver + ".gd", "--",
                 "--qa-profile=qa_visual_" + stamp, "--capture-output=" + str(output)], "asset-visual-" + stamp)
    elif options.action in ("profile-crown-smoke", "profile-crown", "profile-crown-endurance"):
        seconds = {"profile-crown-smoke": 30, "profile-crown": 300, "profile-crown-endurance": 1800}[options.action]
        output = EVIDENCE / "performance" / ("crown-flight-" + stamp)
        execute(["--windowed", "--resolution", "1280x720", "--position", "0,0",
                 "--script", "res://scripts_tools/v3/profile_crown_flight.gd", "--", "--perf-run",
                 "--perf-seconds=" + str(seconds), "--qa-profile=qa_perf_" + stamp,
                 "--perf-output=" + str(output)], "crown-flight-perf-" + stamp, timeout=seconds + 120)
    elif options.action in ("test", "test-logic"):
        for script, prefix in [("test_core", "qa_core_"), ("test_gameplay", "qa_gameplay_"),
                               ("test_network_pilot_input", "qa_network_input_"),
                               ("test_i2_waterfront_terrain", "qa_waterfront_terrain_"),
                               ("test_waterfront_authority", "qa_waterfront_authority_"),
                               ("test_thermal_bypass", "qa_thermal_"),
                               ("test_underdeck_passage", "qa_underdeck_"),
                               ("test_underdeck_visibility", "qa_underdeck_visibility_"),
                               ("test_underdeck_action_data", "qa_underdeck_data_"),
                               ("test_underdeck_action", "qa_underdeck_action_"),
                               ("test_underdeck_snapshot", "qa_underdeck_wire_"),
                               ("test_underdeck_session", "qa_underdeck_"),
                               ("test_water_network", "qa_water_"),
                               ("test_clinic_water_runtime", "qa_clinic_water_"),
                               ("test_clinic_waterworks", "qa_clinic_waterworks_"),
                               ("test_guided_axis", "qa_guided_axis_"),
                               ("test_clinic_progress", "qa_clinic_progress_"),
                               ("test_clinic_action", "qa_clinic_action_"),
                               ("test_clinic_session", "qa_clinic_session_"),
                               ("test_distribution_cabinet", "qa_distribution_"),
                               ("test_distribution_trial_floor", "qa_trial_floor_"),
                               ("test_distribution_layout_migration", "qa_distribution_migration_"),
                               ("test_distribution_floor_session", "qa_distribution_floor_"),
                               ("test_persistent_values", "qa_persistent_values_"),
                               ("test_distribution_progress", "qa_distribution_progress_"),
                               ("test_distribution_session", "qa_distribution_session_"),
                               ("test_trial_flow_runtime", "qa_trial_flow_"),
                               ("test_trial_flow_station", "qa_trial_station_"),
                               ("test_trial_isolation_link", "qa_trial_link_"),
                               ("test_trial_connected_flow", "qa_trial_connected_"),
                               ("test_trial_session", "qa_trial_session_"),
                               ("test_trial_integration", "qa_trial_integration_"),
                               ("test_facility_contract", "qa_facility_contract_"),
                               ("test_i2_result_ledger", "qa_i2_ledger_"),
                               ("test_facility_registry", "qa_facility_registry_"),
                               ("test_shared_access_bridge", "qa_shared_access_"),
                               ("test_shared_access_session", "qa_shared_access_session_"),
                               ("test_distribution_action", "qa_distribution_action_"),
                               ("test_distribution_action_integration", "qa_distribution_action_"),
                               ("test_clinic_pump_art", "qa_pump_art_"),
                               ("test_clinic_layout_migration", "qa_clinic_migration_"),
                               ("test_clinic_gravity_art", "qa_clinic_gravity_art_"),
                               ("test_clinic_reception", "qa_clinic_reception_"),
                               ("test_ecology_state", "qa_ecology_state_"),
                               ("test_living_world", "qa_ecology_"),
                               ("test_crown_encounter", "qa_crown_"),
                               ("test_crown_attack_schedule", "qa_crown_schedule_"),
                               ("test_crown_action_data", "qa_crown_data_"),
                               ("test_crown_snapshot", "qa_snapshot_"),
                               ("test_crown_asset", "qa_crownasset_"),
                               ("test_crown_combat", "qa_crowncombat_"),
                               ("test_crown_profile_contract", "qa_crownprofile_"),
                               ("test_imported_geometry", "qa_imported_"),
                               ("test_shore_layout", "qa_shorelayout_"),
                               ("test_shore_world", "qa_shore_"),
                               ("test_growth_crossing", "qa_growth_"),
                               ("test_world_build_contract", "qa_worldbuild_"),
                               ("test_terrain_visibility", "qa_visibility_"),
                               ("test_boss_attacks", "qa_boss_"),
                               ("test_whale_action_data", "qa_whale_data_"),
                               ("test_whale_asset", "qa_whale_asset_"),
                               ("test_whale_combat", "qa_whalecombat_"),
                               ("test_whale_action_session", "qa_whale_"),
                               ("test_session_persistence", "qa_session_"),
                               ("test_session_physics", "qa_physics_"),
                               ("test_effect_lifetime", "qa_effects_"),
                               ("test_action_director", "qa_actions_"),
                               ("test_receipt_channel", "qa_receipts_"),
                               ("test_opening_actions", "qa_opening_"),
                               ("test_opening_guidance_session", "qa_guidance_"),
                               ("test_target_marker_layout", "qa_markerlayout_"),
                               ("test_gate_clearance", "qa_clearance_"),
                               ("test_traversal_structures", "qa_traversal_"),
                               ("test_terrain_kit", "qa_terrain_"),
                               ("test_art_integration", "qa_art_")]:
            execute(["--headless", "--script", "res://tests_v3/" + script + ".gd", "--",
                     "--qa-profile=" + prefix + stamp] + (["--with-fantasy"] if script == "test_terrain_kit" else []), script + "-" + stamp)
        execute(["--headless", "--script", "res://scripts/v3/tests/test_opening_guidance.gd"], "test_opening_guidance-" + stamp)
        if options.action == "test-logic":
            return 0  # Explicitly excludes UDP, rendering, performance and human play.
        execute_command([sys.executable, str(ROOT / "scripts_tools/v3/test_lan_local.py")],
                        "test_lan_local-" + stamp, LAN_TIMEOUT)
        crown_sha = hashlib.sha256((ROOT / "assets/v3/crown/parasitic_crown.glb").read_bytes()).hexdigest()
        execute_command([sys.executable, str(ROOT / "scripts_tools/v3/test_crown_lan.py"),
                         "--run", "--expected-crown-sha", crown_sha], "test_crown_lan-" + stamp, LAN_TIMEOUT)
        underdeck_sha = hashlib.sha256((ROOT / "data/v3/terrain/i1_underdeck_layout.json").read_bytes()).hexdigest()
        execute_command([sys.executable, str(ROOT / "scripts_tools/v3/test_underdeck_lan.py"),
                         "--run", "--expected-underdeck-sha", underdeck_sha], "test_underdeck_lan-" + stamp, LAN_TIMEOUT)
        clinic_sha = hashlib.sha256((ROOT / "data/v3/terrain/i2_clinic_layout.json").read_bytes()).hexdigest()
        execute_command([sys.executable, str(ROOT / "scripts_tools/v3/test_clinic_lan.py"),
                         "--run", "--expected-clinic-sha", clinic_sha], "test_clinic_lan-" + stamp, LAN_TIMEOUT)
        distribution_sha = hashlib.sha256((ROOT / "data/v3/terrain/i2_distribution_layout.json").read_bytes()).hexdigest()
        execute_command([sys.executable, str(ROOT / "scripts_tools/v3/test_distribution_lan.py"),
                         "--run", "--expected-distribution-sha", distribution_sha], "test_distribution_lan-" + stamp, LAN_TIMEOUT)
        execute_command([sys.executable, "-B", str(ROOT / "scripts_tools/v3/test_waterfront_lan.py"), "--run"],
                        "test_waterfront_lan-" + stamp, 110)
        print("Logic / physics / loopback checks only; human play, graphics and two-PC LAN are separate.")
    elif options.action in ("export", "export-candidate"):
        version = re.search(r'config/version="([^"]+)"', (ROOT / "project.godot").read_text(encoding="utf-8")).group(1)
        development = re.fullmatch(r"3\.0\.0-dev\.(\d+)", version)
        if options.action == "export-candidate" and development is None:
            raise SystemExit("Candidate export requires an explicit 3.0.0-dev.N source version")
        folder = "V3Dev" + development.group(1) + "Candidate" if options.action == "export-candidate" else "V3Development"
        output = ROOT / "build" / folder / "LowAltitudeTwinPulse-Dev.exe"
        if output.exists():
            raise SystemExit("Existing build preserved. Choose a new development version or archive this candidate before exporting again.")
        output.parent.mkdir(parents=True, exist_ok=True)
        exported = execute(["--headless", "--export-debug", "Windows V3 Development", str(output)], "export-" + stamp)
        if not exported["passed"] or not output.is_file():
            print("Export failed; original log and any partial output retained. No build metadata or successful-package claim written.")
            return 1
        shutil.copy2(ROOT / "README_V3.md", output.parent / "README.md")
        shutil.copy2(ROOT / "THIRD_PARTY_NOTICES.md", output.parent / "THIRD_PARTY_NOTICES.md")
        shutil.copytree(ROOT / "assets/licenses", output.parent / "licenses", dirs_exist_ok=True)
        shutil.copy2(ROOT / "assets/fonts/OFL.txt", output.parent / "licenses/NotoSansSC-OFL.txt")
        report = "docs/v3/PROGRESS.md" if options.action == "export-candidate" else "docs/v3/VERIFICATION.md"
        shutil.copy2(ROOT / report, output.parent / "VERIFICATION.md")
        protocol = int(re.search(r'const PROTOCOL = (\d+)', (ROOT / "scripts/v3/twin_network.gd").read_text(encoding="utf-8")).group(1))
        build = {"version": version, "network_protocol": protocol,
                 "scope": "partial development build; full eight-region game incomplete",
                 "exe_sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
                 "exe_bytes": output.stat().st_size, "export_log": (EVIDENCE / ("export-" + stamp + ".log")).relative_to(ROOT).as_posix(),
                 "verification_report": "VERIFICATION.md",
                 "verification_scope": "Export is not acceptance. Match the report version and EXE hash before using its conclusions."}
        (output.parent / "BUILD.json").write_text(json.dumps(build, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"Partial art + mechanics development build, NOT the completed game: {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
