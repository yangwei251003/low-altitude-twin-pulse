"""Visible exported-EXE I2/I3/F4 foreground screening; no affinity/hidden window."""
import argparse, csv, datetime, hashlib, json, pathlib, sys, time, uuid
sys.dont_write_bytecode = True
import dev


def sha(path):
    return dev.file_sha256(path)


def store_phases_valid(sample):
    value = sample.get('store_phases')
    phases = {'ready','transaction_candidate','candidate_validate','prepare_generation',
              'encode_hash_size','write_flush','tmp_readback','rename','retire'}
    if not isinstance(value, dict) or value.get('schema') != 1 or value.get('complete') is not True:
        return False
    if type(value.get('start_usec')) is not int or type(value.get('total_usec')) is not int:
        return False
    if not (sample['begin_usec'] <= value['start_usec'] <= sample['end_usec']
            and 0 <= value['total_usec'] <= sample['wall_usec']):
        return False
    times, counts, groups = value.get('phase_usec'), value.get('phase_count'), value.get('read_groups')
    if not isinstance(times, dict) or set(times) != phases or not isinstance(counts, dict) or set(counts) != phases:
        return False
    if not all(type(times[p]) is int and times[p] >= 0 and type(counts[p]) is int and 0 <= counts[p] <= 1 for p in phases):
        return False
    if sum(times.values()) > value['total_usec'] or not isinstance(groups, dict) or set(groups) != {'ready','tmp','retire'}:
        return False
    for group, parent in [('ready','ready'),('tmp','tmp_readback'),('retire','retire')]:
        row = groups[group]
        keys = {'calls','read_usec','read_count','json_sha_usec','json_sha_count','validate_usec','validate_count'}
        if not isinstance(row, dict) or set(row) != keys or not all(type(v) is int and v >= 0 for v in row.values()):
            return False
        if not (row['read_count'] == row['calls'] and row['validate_count'] <= row['json_sha_count'] <= row['read_count']):
            return False
        if row['read_usec']+row['json_sha_usec']+row['validate_usec'] > times[parent]:
            return False
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe', type=pathlib.Path, required=True)
    parser.add_argument('--seconds', type=float, default=30, help='5..30 measured seconds per area; 12 is a short screening, never full acceptance.')
    parser.add_argument('--cpu', action='store_true', help='Collect inclusive CPU scope diagnostics in the actual graphical ROI; includes timing overhead')
    parser.add_argument('--disable-3d-diagnostic', action='store_true', help='Explicit presentation-only diagnostic; never normal performance acceptance')
    args = parser.parse_args()
    diagnostic_only = args.cpu or args.disable_3d_diagnostic
    diagnostic_reasons = (['cpu_scopes'] if args.cpu else []) + (['disabled_3d'] if args.disable_3d_diagnostic else [])
    if not 5 <= args.seconds <= 30:
        parser.error('--seconds must be between 5 and 30')
    exe = args.exe.resolve(strict=True)
    if exe.suffix.lower() != '.exe':
        parser.error('--exe must be a completed exported Windows executable')
    root = dev.ROOT
    stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S') + '_' + uuid.uuid4().hex[:6]
    dev.POLICY.preflight_qa(64 * 1024 ** 2)
    dev.POLICY.preflight('evidence', 64 * 1024 ** 2)
    output = dev.POLICY.path('evidence', 'performance', 'campaign-performance-' + stamp)
    output.mkdir(parents=True, exist_ok=False)
    profile = 'qa_campaign_performance_' + stamp
    command = [str(exe), '--windowed', '--resolution', '1280x720', '--position', '40,40',
               '--',
               '--qa-profile=' + profile, '--qa-performance-output=' + str(output),
               '--qa-performance-seconds=' + str(args.seconds)]
    if args.cpu:
        command.append('--qa-performance-cpu')
    if args.disable_3d_diagnostic:
        command.append('--disable-3d-diagnostic')
    frozen = [exe]
    if exe.with_suffix('.pck').is_file():
        frozen.append(exe.with_suffix('.pck'))
    before = {str(path): sha(path) for path in frozen}
    started = time.monotonic()
    process = {}
    caught = ''
    try:
        dev.ROOT = exe.parent
        with (output / 'process.log').open('xb', buffering=0) as log:
            process = dev._windows_run(command, log, 240)
    except (OSError, RuntimeError, KeyboardInterrupt) as error:
        caught = type(error).__name__ + ': ' + str(error)
    finally:
        dev.ROOT = root
        after = {str(path): sha(path) for path in frozen}
    report = {}
    if (output / 'report.json').is_file():
        try:
            report = json.loads((output / 'report.json').read_text(encoding='utf-8'))
        except (OSError, ValueError) as error:
            caught += ('; ' if caught else '') + str(error)
    engine_error_found = False
    for path in (output / 'engine.log', output / 'process.log'):
        if not path.is_file():
            continue
        carry = b''
        with path.open('rb') as stream:
            for block in iter(lambda: stream.read(65536), b''):
                window = carry + block
                engine_error_found |= b'ERROR:' in window or b'SCRIPT ERROR' in window
                carry = window[-32:]
    env = report.get('environment', {})
    prepared, raw_rows = {}, []
    try:
        prepared = json.loads((output / 'prepared.json').read_text(encoding='utf-8'))
        with (output / 'frames.csv').open(encoding='utf-8', newline='') as stream:
            raw_rows = list(csv.DictReader(stream))
    except (OSError, ValueError) as error:
        caught += ('; ' if caught else '') + str(error)
    environments = [prepared.get('environment', {}), env]
    checks = {
        'actual_project_default_mobile_vulkan': all(e.get('project_renderer_default') == e.get('renderer') == 'mobile' and e.get('project_rd_driver_default') == e.get('driver') == 'vulkan' and e.get('profile') == profile for e in environments),
        'same_prepared_and_final_quality': environments[0].get('quality') == environments[1].get('quality') and environments[0].get('renderer_settings') == environments[1].get('renderer_settings'),
        'no_CLI_renderer_override': '--rendering-method' not in command and '--rendering-driver' not in command and '--qa-renderer-mobile-diagnostic' not in command,
        'all_CSV_frames_preserved_and_classified': len(raw_rows) == report.get('raw_frames') and len(raw_rows) > 3 and all(r.get('diagnostic_only') == str(diagnostic_only).lower() and r.get('disable_3d') == str(args.disable_3d_diagnostic).lower() for r in raw_rows),
        'private_job_clean': process.get('returncode') == 0 and not process.get('timed_out') and not process.get('orphan_cleanup') and process.get('remaining_owned_processes') == 0,
        'no_runner_exception': not caught,
        'measurement_valid': report.get('valid_measurement') is True,
        'diagnostic_P95_target_met': report.get('screening_target_met') is True,
        'exported_binary': env.get('editor_binary') is False and pathlib.Path(env.get('executable', '')).resolve() == exe,
        'own_folder_cwd': pathlib.Path(env.get('runtime_cwd', '')).resolve() == exe.parent,
        'unique_QA': env.get('profile') == profile,
        'regions_in_order': [row.get('region') for row in report.get('regions', [])] == ['I2', 'I3', 'F4'],
        'bounded_total': 0 < report.get('elapsed_seconds', 0) < 220,
        'raw_csv_retained': (output / 'frames.csv').is_file() and (output / 'frames.csv').stat().st_size > 1000,
        'frozen_export': before == after,
        'no_engine_error': not report.get('engine_errors') and not engine_error_found,
        'no_source_path': '--path' not in command,
    }
    checks['diagnostic_flags_match_invocation'] = (
        report.get('diagnostic_only') is diagnostic_only
        and report.get('diagnostic_reasons') == diagnostic_reasons
        and prepared.get('diagnostic_only') is diagnostic_only
        and prepared.get('diagnostic_reasons') == diagnostic_reasons)
    checks['cpu_scope_flag_matches_invocation'] = all(
        row.get('cpu_scopes', {}).get('enabled') is args.cpu for row in report.get('regions', []))
    if diagnostic_only:
        del checks['measurement_valid']
        del checks['diagnostic_P95_target_met']
        checks.update({
            'valid_diagnostic_measurement': report.get('valid_diagnostic_measurement') is True,
            'diagnostic_complete': report.get('diagnostic_complete') is True,
            'no_normal_performance_pass_from_diagnostics': report.get('valid_measurement') is False and report.get('screening_target_met') is False,
        })
    if args.disable_3d_diagnostic:
        checks['all_ROIs_explicitly_disabled_3D'] = len(report.get('regions', [])) == 3 and all(row.get('render_diagnostic', {}).get('disable_3d') is True and row.get('render_diagnostic', {}).get('diagnostic_only') is True for row in report['regions'])
    else:
        checks['all_non_render_diagnostic_ROIs_keep_3D'] = all(row.get('render_diagnostic', {}).get('disable_3d') is False and row.get('render_diagnostic', {}).get('diagnostic_only') is False for row in report.get('regions', []))
    wall_rows_valid = True
    for region in report.get('regions', []):
        wall = region.get('cpu_scopes', {}).get('store_commit_wall', {})
        samples = wall.get('samples')
        valid = (wall.get('enabled') is args.cpu and wall.get('max_samples') == 8 and wall.get('phase_schema') == 1
                 and type(wall.get('time_origin_usec')) is int and wall['time_origin_usec'] > 0
                 and isinstance(samples, list) and len(samples) <= 8 and (args.cpu or not samples))
        if valid:
            for sample in samples:
                valid = valid and isinstance(sample, dict) and all(type(sample.get(key)) is int for key in
                    ('begin_usec', 'end_usec', 'wall_usec', 'physics_frame', 'generation_before', 'generation_after'))
                if valid:
                    valid = (wall['time_origin_usec'] <= sample['begin_usec'] <= sample['end_usec']
                             and sample['wall_usec'] == sample['end_usec'] - sample['begin_usec']
                             and sample['physics_frame'] >= 0 and sample['generation_before'] >= 0
                             and sample['generation_after'] >= 0 and type(sample.get('ok')) is bool
                             and isinstance(sample.get('receipt'), str) and isinstance(sample.get('error'), str)
                             and store_phases_valid(sample))
        wall_rows_valid = wall_rows_valid and valid
    checks['bounded_store_wall_scope_rows'] = wall_rows_valid
    accepted = all(checks.values())
    result = {'screening_passed': accepted and not diagnostic_only, 'measurement_valid': report.get('valid_measurement') is True,
              'diagnostic_only': diagnostic_only, 'diagnostic_reasons': diagnostic_reasons,
              'valid_diagnostic_measurement': report.get('valid_diagnostic_measurement') is True,
              'diagnostic_complete': accepted and diagnostic_only,
              'screening_target_met': report.get('screening_target_met') is True, 'checks': checks, 'before_sha256': before,
              'after_sha256': after, 'process': process, 'exception': caught, 'command': command,
              'wall_seconds': round(time.monotonic() - started, 3), 'watchdog_seconds': 240,
              'runtime_cwd': str(exe.parent), 'source_path_passed': False, 'affinity_override': False,
              'optional_CPU_timing_overhead': args.cpu,
              'scope': 'Visible foreground current-package run; requested CPU scopes carry observer overhead and are diagnostic only. Render disablement is classified separately. Normal short screening only without diagnostics; per-frame focus/visible guards. Default30 or first12 seconds per area do not replace five-minute/30-minute performance, full Boss load, LAN or human acceptance.'}
    (output / 'validation.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({'output': str(output), 'screening_passed': result['screening_passed'], 'measurement_valid': result['measurement_valid'],
                      'diagnostic_only': result['diagnostic_only'], 'valid_diagnostic_measurement': result['valid_diagnostic_measurement'],
                      'diagnostic_complete': result['diagnostic_complete'], 'checks': checks, 'process': process}, ensure_ascii=False))
    raise SystemExit(0 if accepted else 1)


if __name__ == '__main__':
    main()
