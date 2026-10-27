"""Run one newly exported EXE in its own folder; eight areas, at most16 GPU shots."""
import argparse, datetime, hashlib, json, pathlib, sys, time, uuid
sys.dont_write_bytecode = True
import dev


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe', required=True, type=pathlib.Path, help='New completed export to check; the runner never exports or uses a source --path.')
    args = parser.parse_args()
    exe = args.exe.resolve(strict=True)
    if exe.suffix.lower() != '.exe':
        parser.error('--exe must be an existing exported Windows executable')
    root = dev.ROOT
    stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S') + '_' + uuid.uuid4().hex[:6]
    output = root / 'artifacts/v3' / ('campaign-package-' + stamp)
    output.mkdir(parents=True, exist_ok=False)
    profile = 'qa_campaign_packaged_' + stamp
    command = [str(exe), '--windowed', '--resolution', '1280x720',
               '--position', '-4000,-4000', '--log-file', str(output / 'engine.log'), '--',
               '--qa-profile=' + profile, '--qa-campaign-output=' + str(output)]
    frozen = [exe]
    pck = exe.with_suffix('.pck')
    if pck.is_file():
        frozen.append(pck)
    before = {str(path): digest(path) for path in frozen}
    started = time.monotonic()
    process = {}
    caught = ''
    try:
        # _windows_run already supplies suspended start / private Job cleanup.
        # Its cwd comes from dev.ROOT; this local assignment does not edit dev.py.
        dev.ROOT = exe.parent
        with (output / 'process.log').open('xb', buffering=0) as log:
            process = dev._windows_run(command, log, 150)
    except (OSError, RuntimeError, KeyboardInterrupt) as error:
        caught = type(error).__name__ + ': ' + str(error)
    finally:
        dev.ROOT = root
        after = {str(path): digest(path) for path in frozen}
    engine_log = (output / 'engine.log').read_text(encoding='utf-8', errors='replace') if (output / 'engine.log').is_file() else ''
    process_log = (output / 'process.log').read_text(encoding='utf-8', errors='replace') if (output / 'process.log').is_file() else ''
    report_path = output / 'report.json'
    runtime = {}
    if report_path.is_file():
        try:
            runtime = json.loads(report_path.read_text(encoding='utf-8'))
        except (OSError, ValueError) as error:
            caught += ('; ' if caught else '') + type(error).__name__ + ': ' + str(error)
    files = sorted(output.glob('*.png'))
    checks = {
        'actual_project_default_mobile_vulkan': runtime.get('renderer') == runtime.get('project_renderer_default') == 'mobile' and runtime.get('rendering_driver') == runtime.get('project_rd_driver_default') == 'vulkan',
        'no_CLI_renderer_override': '--rendering-method' not in command and '--rendering-driver' not in command,
        'private_job_exit_zero': process.get('returncode') == 0 and not process.get('timed_out') and not process.get('orphan_cleanup') and process.get('remaining_owned_processes') == 0,
        'runner_no_exception': not caught,
        'runtime_passed': runtime.get('passed') is True,
        'actual_export_not_editor': runtime.get('editor_binary') is False,
        'correct_executable': pathlib.Path(runtime.get('executable', '')).resolve() == exe,
        'own_folder_cwd': pathlib.Path(runtime.get('runtime_cwd', '')).resolve() == exe.parent,
        'isolated_profile': runtime.get('profile') == profile,
        'eight_areas_in_order': [row.get('id') for row in runtime.get('regions', [])] == ['I1', 'F1', 'I2', 'F2', 'I3', 'F3', 'I4', 'F4'],
        'sixteen_rendered_frames': len(runtime.get('shots', [])) == 16 and len(files) == 16 and all(path.stat().st_size > 10000 for path in files),
        'no_engine_errors': not runtime.get('engine_errors') and 'ERROR:' not in engine_log and 'ERROR:' not in process_log and 'SCRIPT ERROR' not in engine_log + process_log,
        'frozen_export_unchanged': before == after,
        'bounded_runtime': 0 < runtime.get('elapsed_seconds', 0) < 120,
        'no_source_path_argument': '--path' not in command,
    }
    validation = {'passed': all(checks.values()), 'checks': checks, 'process': process, 'exception': caught,
                  'before_sha256': before, 'after_sha256': after, 'command': command,
                  'runtime_cwd': str(exe.parent), 'source_path_passed': False,
                  'wall_seconds': round(time.monotonic() - started, 3), 'watchdog_seconds': 150,
                  'scope': 'Actual exported EXE and GPU image/resource validity only. Unique QA; no source project path. Hidden-window FPS is not performance acceptance; inventory/meters are not human controller or listening evidence.'}
    (output / 'validation.json').write_text(json.dumps(validation, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({'passed': validation['passed'], 'output': str(output), 'checks': checks, 'process': process}, ensure_ascii=False))
    raise SystemExit(0 if validation['passed'] else 1)


if __name__ == '__main__':
    main()
