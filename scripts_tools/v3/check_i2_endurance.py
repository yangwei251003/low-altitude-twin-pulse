"""One continuous 300s I2 idle baseline, then 12s I3 cargo/F4 optics; not full-load acceptance."""
import argparse, csv, datetime, json, pathlib, sys, time, uuid
sys.dont_write_bytecode = True
ROOT = next(p for p in pathlib.Path(__file__).resolve().parents if (p / 'scripts_tools/v3/dev.py').is_file())
sys.path.insert(0, str(ROOT / 'scripts_tools/v3'))
import dev
from check_campaign_performance import sha

TARGETS = {'I2': 300, 'I3': 12, 'F4': 12}
EXTRA = sum(TARGETS.values()) - 3 * 12
INNER, JOB = 210 + EXTRA, 240 + EXTRA


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe', type=pathlib.Path, required=True)
    args = parser.parse_args()
    exe = args.exe.resolve(strict=True)
    if exe.suffix.lower() != '.exe':
        parser.error('--exe must be a completed Windows export')
    stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S') + '_' + uuid.uuid4().hex[:6]
    output = ROOT / 'artifacts/v3/performance' / ('campaign-performance-long-i2-' + stamp)
    output.mkdir(parents=True, exist_ok=False)
    profile = 'qa_campaign_performance_long_i2_' + stamp
    command = [str(exe), '--windowed', '--resolution', '1280x720', '--position', '40,40',
               '--log-file', str(output / 'engine.log'), '--', '--qa-profile=' + profile,
               '--qa-performance-output=' + str(output), '--qa-performance-seconds=12', '--qa-performance-long-i2']
    frozen = [exe] + ([exe.with_suffix('.pck')] if exe.with_suffix('.pck').is_file() else [])
    before = {str(p): sha(p) for p in frozen}
    started, old_root = time.monotonic(), dev.ROOT
    process, caught, docs, raw = {}, '', {}, []
    try:
        dev.ROOT = exe.parent
        with (output / 'process.log').open('xb', buffering=0) as log:
            process = dev._windows_run(command, log, JOB)
    except (OSError, RuntimeError, KeyboardInterrupt) as error:
        caught = type(error).__name__ + ': ' + str(error)
    finally:
        dev.ROOT = old_root
    after = {str(p): sha(p) if p.is_file() else 'MISSING' for p in frozen}
    try:
        for name in ['prepared', 'report']:
            docs[name] = json.loads((output / (name + '.json')).read_text(encoding='utf-8'))
        with (output / 'frames.csv').open(encoding='utf-8', newline='') as stream:
            raw = list(csv.DictReader(stream))
    except (OSError, ValueError) as error:
        caught += ('; ' if caught else '') + str(error)
    report, prepared = docs.get('report', {}), docs.get('prepared', {})
    envs = [prepared.get('environment', {}), report.get('environment', {})]
    rois = report.get('regions', [])
    logs = ''.join(p.read_text(encoding='utf-8', errors='replace') for p in
                   [output / 'engine.log', output / 'process.log'] if p.is_file())
    windows = {}
    for region, target in TARGETS.items():
        indices = [i for i, row in enumerate(raw) if row.get('phase') == 'measure:' + region]
        rows = [raw[i] for i in indices]
        try:
            windows[region] = {'frames': len(rows), 'span_seconds': float(rows[-1]['end_s']) - float(rows[0]['start_s']),
                               'contiguous': indices[-1] - indices[0] + 1 == len(rows) and
                               all(a['end_s'] == b['start_s'] for a, b in zip(rows, rows[1:]))}
        except (KeyError, IndexError, ValueError):
            windows[region] = {'frames': 0, 'span_seconds': 0, 'contiguous': False}
    checks = {
        'private_job_clean': process.get('returncode') == 0 and not process.get('timed_out') and not process.get('orphan_cleanup') and process.get('remaining_owned_processes') == 0,
        'no_runner_exception': not caught,
        'actual_default_mobile_vulkan': all(e.get('project_renderer_default') == e.get('renderer') == 'mobile' and e.get('project_rd_driver_default') == e.get('driver') == 'vulkan' for e in envs),
        'actual_export_profile_and_cwd': all(e.get('editor_binary') is False and e.get('display') not in [None, '', 'headless'] and pathlib.Path(e.get('executable', '')).resolve() == exe and pathlib.Path(e.get('runtime_cwd', '')).resolve() == exe.parent and e.get('executable_sha256') == before[str(exe)] and e.get('profile') == profile for e in envs),
        'ordinary_resolution_physics_camera_vsync': all(e.get('window_size') == '(1280, 720)' and e.get('viewport_size') == '(1280, 720)' and e.get('physics_ticks_per_second') == 60 and e.get('time_scale') == 1 and e.get('max_fps') == 0 and e.get('quality', {}).get('camera_target_size') == 26 and e.get('quality', {}).get('vsync') == 1 for e in envs),
        'quality_unchanged': envs[0].get('quality') == envs[1].get('quality') and envs[0].get('renderer_settings') == envs[1].get('renderer_settings'),
        'explicit_long_targets': all(d.get('long_i2') is True and d.get('target_seconds') == TARGETS and d.get('seconds_per_region') == 12 and d.get('observer_watchdog_seconds') == INNER for d in [prepared, report]),
        'normal_not_diagnostic': report.get('diagnostic_only') is False and report.get('renderer_mobile_diagnostic') is False and report.get('valid_measurement') is True and report.get('valid_diagnostic_measurement') is False and all(e.get('renderer_mobile_diagnostic') is False for e in envs),
        'original_P95_target': report.get('screening_target_met') is True and len(rois) == 3 and all(r.get('statistics', {}).get('p95_ms', float('inf')) <= 33.3 for r in rois),
        'regions_and_targets': [r.get('region') for r in rois] == list(TARGETS) and all(r.get('target_seconds') == TARGETS[r['region']] and r.get('seconds', 0) >= TARGETS[r['region']] and r.get('physics_frames', 0) > 0 for r in rois),
        'one_continuous_window_each': [r.get('region') for r in rois] == list(TARGETS) and all(windows[r['region']]['contiguous'] and windows[r['region']]['span_seconds'] >= TARGETS[r['region']] and windows[r['region']]['frames'] == r.get('frames') for r in rois),
        'all_raw_frames_retained': len(raw) == report.get('raw_frames') and len(raw) > 3 and all(r.get('diagnostic_only') == 'false' and r.get('disable_3d') == 'false' for r in raw),
        'I2_idle_no_Boss': len(rois) == 3 and rois[0].get('setup', {}).get('kind') == 'idle_baseline' and rois[0].get('active_boss_frames') == 0,
        'I3_original_cargo_Pilot': len(rois) == 3 and rois[1].get('setup', {}).get('kind') == 'original_G_2kg_Pilot_commands' and rois[1].get('valid_joint_carry_frames', 0) == rois[1].get('frames', -1) and rois[1].get('actual_distance_m', 0) > 0 and rois[1].get('actual_Pilot_waypoints', 0) > 0,
        'F4_original_optical_no_Boss': len(rois) == 3 and rois[2].get('setup', {}).get('kind') == 'actual_original_optical_baseline' and rois[2].get('actual_optical_frames', 0) == rois[2].get('frames', -1) and rois[2].get('active_boss_frames') == 0,
        'bounded_total': 0 < report.get('elapsed_seconds', 0) < INNER + 10,
        'all_memory_samples_retained': isinstance(report.get('resource_samples'), list) and len(report['resource_samples']) >= 300,
        'original_saves_and_reader': len(report.get('save_callbacks', [])) == 3 and all(c.get('result', {}).get('ok') is True and c.get('result', {}).get('completed') is True for c in report.get('save_callbacks', [])) and any(c.get('label') == 'independent original Store exact readback; no fabricated progression' and c.get('passed') is True for c in report.get('checks', [])),
        'native_audio_drained': report.get('qa_audio_shutdown', {}).get('ready') is True,
        'frozen_export': before == after,
        'no_engine_errors': not report.get('engine_errors') and not report.get('failures') and not report.get('issues') and 'ERROR:' not in logs and 'SCRIPT ERROR' not in logs,
        'no_renderer_or_source_override': all(flag not in command for flag in ['--rendering-method', '--rendering-driver', '--qa-renderer-mobile-diagnostic', '--disable-3d-diagnostic', '--qa-performance-cpu', '--path', '--script']),
    }
    accepted = all(checks.values())
    result = {'i2_idle_endurance_passed': accepted, 'normal_classification': report.get('diagnostic_only') is False and report.get('renderer_mobile_diagnostic') is False, 'diagnostic_only': report.get('diagnostic_only'),
              'full_load_or_final_acceptance': False, 'checks': checks, 'target_seconds': TARGETS, 'continuous_windows': windows,
              'observer_watchdog_seconds': INNER, 'private_job_watchdog_seconds': JOB, 'process': process, 'exception': caught,
              'before_sha256': before, 'after_sha256': after, 'command': command, 'wall_seconds': round(time.monotonic() - started, 3),
              'scope': 'Continuous I2 300s default idle baseline only; I3 12s real 2kg/Pilot and F4 12s optics. No Boss load, LAN, 30-minute stability or human acceptance claim.'}
    (output / 'long-validation.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({'output': str(output), 'i2_idle_endurance_passed': accepted, 'checks': checks, 'process': process}, ensure_ascii=False))
    raise SystemExit(0 if accepted else 1)


if __name__ == '__main__':
    main()
