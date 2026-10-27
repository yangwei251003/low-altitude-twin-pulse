"""Explicit exported Mobile/Vulkan diagnostic; never normal performance acceptance."""
import argparse, csv, datetime, json, pathlib, sys, time, uuid
sys.dont_write_bytecode = True
root = next(p for p in pathlib.Path(__file__).resolve().parents if (p / 'scripts_tools/v3/dev.py').is_file())
sys.path.insert(0, str(root / 'scripts_tools/v3'))
import dev
from check_campaign_performance import sha


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe', type=pathlib.Path, required=True)
    parser.add_argument('--seconds', type=float, default=12, help='5..30 seconds per I2/I3/F4 ROI')
    args = parser.parse_args()
    if not 5 <= args.seconds <= 30:
        parser.error('--seconds must be 5..30')
    exe = args.exe.resolve(strict=True)
    if exe.suffix.lower() != '.exe':
        parser.error('--exe must be a completed Windows export')
    stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S') + '_mobile_' + uuid.uuid4().hex[:6]
    output = root / 'artifacts/v3/performance' / ('campaign-performance-' + stamp)
    output.mkdir(parents=True, exist_ok=False)
    profile = 'qa_campaign_performance_' + stamp
    command = [str(exe), '--windowed', '--resolution', '1280x720', '--position', '40,40',
               '--rendering-method', 'mobile', '--rendering-driver', 'vulkan',
               '--log-file', str(output / 'engine.log'), '--', '--qa-profile=' + profile,
               '--qa-performance-output=' + str(output), '--qa-performance-seconds=' + str(args.seconds),
               '--qa-renderer-mobile-diagnostic']
    frozen = [exe] + ([exe.with_suffix('.pck')] if exe.with_suffix('.pck').is_file() else [])
    before = {str(path): sha(path) for path in frozen}
    started = time.monotonic()
    process, caught, documents, rows = {}, '', {}, []
    original_root = dev.ROOT
    try:
        dev.ROOT = exe.parent
        with (output / 'process.log').open('xb', buffering=0) as log:
            process = dev._windows_run(command, log, 240)
    except (OSError, RuntimeError, KeyboardInterrupt) as error:
        caught = type(error).__name__ + ': ' + str(error)
    finally:
        dev.ROOT = original_root
    after = {str(path): sha(path) if path.is_file() else 'MISSING' for path in frozen}
    try:
        for name in ['prepared', 'report']:
            documents[name] = json.loads((output / (name + '.json')).read_text(encoding='utf-8'))
        with (output / 'frames.csv').open(encoding='utf-8', newline='') as stream:
            rows = list(csv.DictReader(stream))
    except (OSError, ValueError) as error:
        caught += ('; ' if caught else '') + str(error)
    report = documents.get('report', {})
    environments = [documents.get(name, {}).get('environment', {}) for name in ['prepared', 'report']]
    rois = report.get('regions', [])
    logs = ''.join(p.read_text(encoding='utf-8', errors='replace') for p in
                   [output / 'engine.log', output / 'process.log'] if p.is_file())
    checks = {
        'private_job_clean': process.get('returncode') == 0 and not process.get('timed_out') and not process.get('orphan_cleanup') and process.get('remaining_owned_processes') == 0,
        'no_runner_exception': not caught,
        'actual_mobile_vulkan_no_fallback': all(e.get('renderer') == 'mobile' and e.get('driver') == 'vulkan' and e.get('renderer_mobile_diagnostic') is True for e in environments),
        'actual_export_and_own_cwd': all(e.get('editor_binary') is False and e.get('display') not in [None, '', 'headless'] and pathlib.Path(e.get('executable', '')).resolve() == exe and pathlib.Path(e.get('runtime_cwd', '')).resolve() == exe.parent and e.get('executable_sha256') == before[str(exe)] for e in environments),
        'unique_QA': all(e.get('profile') == profile for e in environments),
        'unchanged_resolution_physics_and_camera': all(e.get('window_size') == '(1280, 720)' and e.get('viewport_size') == '(1280, 720)' and e.get('physics_ticks_per_second') == 60 and e.get('time_scale') == 1 and e.get('quality', {}).get('camera_target_size') == 26 and e.get('quality', {}).get('vsync') == 1 for e in environments),
        'quality_and_production_settings_unchanged': environments[0].get('quality') == environments[1].get('quality') and environments[0].get('renderer_settings') == environments[1].get('renderer_settings'),
        'original_time_bridge_retained': all(e.get('time_alignment', {}).get('elapsed_before', -1) >= 0 and e.get('time_alignment', {}).get('elapsed_after', -1) >= e.get('time_alignment', {}).get('elapsed_before', 0) and e.get('time_alignment', {}).get('unix_seconds', 0) > 0 for e in environments),
        'no_normal_acceptance': report.get('valid_measurement') is False and report.get('screening_target_met') is False,
        'explicit_diagnostic_complete': report.get('renderer_mobile_diagnostic') is True and report.get('diagnostic_only') is True and report.get('valid_diagnostic_measurement') is True and report.get('diagnostic_complete') is True,
        'regions_in_order': [r.get('region') for r in rois] == ['I2', 'I3', 'F4'],
        'all_ROIs_enabled_3D': len(rois) == 3 and all(r.get('render_diagnostic', {}).get('renderer_mobile_diagnostic') is True and r.get('render_diagnostic', {}).get('diagnostic_only') is True and r.get('render_diagnostic', {}).get('disable_3d') is False for r in rois),
        'original_measurement_intervals': report.get('seconds_per_region') == args.seconds and len(rois) == 3 and all(r.get('seconds', 0) >= args.seconds and r.get('physics_frames', 0) > 0 for r in rois),
        'raw_all_phase_CSV': len(rows) == report.get('raw_frames') and len(rows) > 3 and all(r.get('disable_3d') == 'false' and r.get('diagnostic_only') == 'true' for r in rows) and all(sum(r.get('phase') == 'measure:' + roi.get('region', '') for r in rows) == roi.get('frames') for roi in rois),
        'bounded_original_observer': 0 < report.get('elapsed_seconds', 0) < 220,
        'native_audio_drained': report.get('qa_audio_shutdown', {}).get('ready') is True,
        'frozen_export': before == after,
        'no_engine_error': not report.get('engine_errors') and 'ERROR:' not in logs and 'SCRIPT ERROR' not in logs,
        'no_source_or_disable3D_command': '--path' not in command and '--script' not in command and '--disable-3d-diagnostic' not in command,
    }
    accepted = all(checks.values())
    result = {'normal_acceptance': False, 'screening_passed': False, 'valid_measurement': False,
              'screening_target_met': False, 'diagnostic_only': True,
              'valid_diagnostic_measurement': accepted, 'diagnostic_complete': accepted,
              'diagnostic_frame_target_met': report.get('diagnostic_frame_target_met') is True,
              'checks': checks, 'command': command, 'process': process, 'exception': caught,
              'before_sha256': before, 'after_sha256': after, 'runtime_cwd': str(exe.parent),
              'watchdog_seconds': 240, 'wall_seconds': round(time.monotonic() - started, 3),
              'scope': 'Explicit Mobile/Vulkan graphical diagnostic only; source quality/physics/Store/audio and all CSV phases retained. No resolution, VSync, affinity or production setting override. No normal-performance, visual-equivalence or game-completion claim.'}
    (output / 'mobile-validation.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({'output': str(output), 'diagnostic_complete': accepted, 'normal_acceptance': False, 'checks': checks, 'process': process}, ensure_ascii=False))
    raise SystemExit(0 if accepted else 1)


if __name__ == '__main__':
    main()
