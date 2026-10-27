"""Run an exported MAIN Clinic continuation of the actual natural Underdeck record profile.

Requires a new exported package containing the installed explicit observer entry.
No source/Store/profile is edited or restored from a report by this runner.
"""
import argparse
import datetime
import hashlib
import json
import os
import re
from pathlib import Path
import sys
import uuid

sys.dont_write_bytecode = True
PROJECT = next(parent for parent in Path(__file__).resolve().parents
               if (parent / 'project.godot').is_file()
               and (parent / 'scripts_tools/v3/dev.py').is_file())
sys.path.insert(0, str(PROJECT / 'scripts_tools/v3'))
import dev

PROFILE = 'qa_normal_campaign_20261021_112119_b0f35d51'
BASE_TWENTYTHREE_SHA = 'e431f5a6abd02e7d654e6b94ea2e5318559d8ddab8df1e610579cf1c4e1c9c18'
STAGES = ('diagnosed', 'connected', 'stabilized', 'complete')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe', type=Path,
                        default=PROJECT / 'build/V3Development/LowAltitudeTwinPulse-Dev.exe')
    parser.add_argument('--seconds', type=int, default=600, choices=range(30, 601),
                        metavar='30..600')
    parser.add_argument('--underdeck-report', type=Path,
                        default=PROJECT / 'artifacts/v3/normal-underdeck-20261021_122135_0142342e/normal-underdeck-20261021_122135_0142342e.json',
                        help='Actual dev77 natural Underdeck COMPLETE report; exact bound SHA and receipts must match')
    parser.add_argument('--stop-after', choices=STAGES, default='complete',
                        help='Intentional ordinary Consensus pause; only complete means the full original action')
    args = parser.parse_args()
    executable = args.exe.resolve(strict=True)
    if executable.suffix.lower() != '.exe' or 'godot' in executable.name.lower():
        parser.error('Use the actual exported game EXE/main scene, not an engine executable')
    installed = PROJECT / 'scripts/v3/qa/twin_normal_clinic_qa.gd'
    if not installed.is_file():
        raise RuntimeError('Root must install the staged Clinic Node/CLI and export first')
    node_text = installed.read_text(encoding='utf-8-sig')

    def bound_constant(name):
        match = re.search(r'^const ' + re.escape(name) + r' := "([0-9a-f]{64})"$', node_text, re.M)
        if not match:
            raise RuntimeError('Root must bind actual successful Underdeck evidence: ' + name)
        return match.group(1)

    source_sha = bound_constant('SOURCE_REPORT_SHA256')
    receipts_sha = bound_constant('TWENTYSEVEN_DIGEST')
    source_path = args.underdeck_report.resolve(strict=True)
    if hashlib.sha256(source_path.read_bytes()).hexdigest() != source_sha:
        raise RuntimeError('Actual normal Underdeck report does not match Root-bound SHA')
    source = json.loads(source_path.read_text(encoding='utf-8-sig'))
    goals = source.get('status', {}).get('completed', [])
    if (not source.get('underdeck_segment_complete') or source.get('failures')
            or source.get('engine_errors') or source.get('profile') != PROFILE
            or len(goals) != 27 or goals[-1] != 'I1:underdeck:traverse'
            or source.get('source_receipts_sha256') != BASE_TWENTYTHREE_SHA
            or not source.get('native_exit', {}).get('observed_scene_exit')
            or not source.get('native_exit', {}).get('audio', {}).get('ready')):
        raise RuntimeError('Require actual successful natural Underdeck record and production exit evidence')
    rows = {key: value for key, value in source['story_receipts'].items()
            if value['objective_id'] in goals}
    actual_digest = hashlib.sha256(json.dumps(
        rows, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode('utf-8')).hexdigest()
    if len(rows) != 27 or actual_digest != receipts_sha:
        raise RuntimeError('Actual twenty-seven natural Underdeck-source receipts differ')
    profile_path = Path(source['user_dir']) / 'profiles_v3' / PROFILE
    if not profile_path.is_dir():
        raise RuntimeError('Original real QA profile absent; no replacement is created')
    stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S') + '_' + uuid.uuid4().hex[:8]
    evidence = PROJECT / 'artifacts/v3' / ('normal-clinic-' + stamp)
    evidence.mkdir(parents=True, exist_ok=False)
    output = evidence / ('normal-clinic-' + stamp + '.json')
    files = [executable, Path(__file__).resolve(), source_path]
    if executable.with_suffix('.pck').is_file():
        files.append(executable.with_suffix('.pck'))
    names = [
        'scripts/v3/qa/twin_normal_clinic_qa.gd',
        'scripts/v3/twin_app.gd', 'scripts/v3/twin_session.gd', 'scripts/v3/twin_test_world.gd',
        'scripts/v3/gameplay/twin_opening_story.gd', 'scripts/v3/gameplay/twin_clinic_session.gd',
        'scripts/v3/gameplay/actions/twin_clinic_progress.gd',
        'scripts/v3/gameplay/twin_i2_result_ledger.gd',
        'scripts/v3/world/twin_clinic_waterworks.gd',
        'scripts/v3/environment/twin_clinic_water_runtime.gd',
        'scripts/v3/environment/twin_guided_axis.gd',
        'scripts/v3/gameplay/twin_ability_rules.gd',
        'scripts/v3/gameplay/canal/canal_transport_physics/transport_pilot.gd',
        'scripts/v3/core/twin_canal_save_gate.gd', 'scripts/v3/core/twin_world_store.gd',
        'scripts/v3/art/twin_clinic_gravity_art.gd',
        'scripts/v3/art/twin_clinic_reception_art.gd', 'scripts/v3/art/twin_clinic_pump_art.gd',
        'assets/v3/clinic_gravity/clinic_gravity.glb',
        'data/v3/actions/clinic_action.json', 'data/v3/terrain/i2_clinic_layout.json',
        'data/v3/environment/i2_clinic_water_network.json',
    ]
    files.extend(PROJECT / name for name in names)

    def hashes():
        return {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in files}

    before = hashes()
    command = [str(executable), '--', '--qa-normal-clinic',
               '--qa-profile=' + PROFILE, '--qa-normal-output=' + str(output.resolve()),
               '--qa-normal-seconds=' + str(args.seconds),
               '--qa-clinic-stop-after=' + args.stop_after]
    (evidence / 'invocation.json').write_text(json.dumps({
        'command': command, 'profile': PROFILE, 'output': str(output),
        'working_directory': str(executable.parent), 'stop_after': args.stop_after,
        'requested_seconds': args.seconds, 'job_timeout_seconds': args.seconds + 15,
        'source_profile_directory': str(profile_path), 'source_report_sha256': source_sha,
        'source_twenty_seven_receipts_sha256': receipts_sha,
        'scope': 'Exported main scene with the same real natural Underdeck profile. '
                 'Normal M/spawn, continuous Pilot/Flight, actual southern clinic gap, '
                 'manual diagnosis G, normal 2/Tab/F high-valve impulse and original '
                 'guided rail, real 2000L clean supply/cutoff/deck/access stability, '
                 'manual confirmation G and original Store. No script/scene override, '
                 'fixtures, actor/valve/water/HP/clock/collision/flags edits, profile '
                 'clone/rollback, headless mode, affinity or quality override. '
                 'Diagnosed/connected/stabilized stops are incomplete clinic stages. '
                 'Legal 27..31 prefixes resume from the original native water history. '
                 'Distribution 31..34 is outside this four-goal segment.'
    }, ensure_ascii=False, indent=2), encoding='utf-8')
    dev.EVIDENCE = evidence
    process = None
    execution_failure = None
    original_root = dev.ROOT
    try:
        dev.ROOT = executable.parent
        process = dev.execute_command(command, 'exported-main', args.seconds + 15)
    except SystemExit as error:
        execution_failure = error.code
    finally:
        dev.ROOT = original_root
        after = hashes()
        (evidence / 'inputs.json').write_text(json.dumps({
            'before': before, 'after': after, 'unchanged': before == after,
            'process': process, 'execution_failure': execution_failure,
            'artifact_sha256': before[str(executable)],
            'note': 'Source hashes identify the working tree; only the executed EXE/PCK '
                    'hashes identify the actual artifact. The existing profile is never reset.'
        }, ensure_ascii=False, indent=2), encoding='utf-8')
    if not output.is_file():
        print(json.dumps({'complete': False, 'evidence': str(evidence),
                          'error': 'No observer result: CLI/import/runtime/process failure '
                                   'or timeout is incomplete, never a successful stage.'}, ensure_ascii=False))
        raise SystemExit(1)
    report = json.loads(output.read_text(encoding='utf-8-sig'))
    runtime_cwd = report.get('runtime_cwd', '')
    own_folder = bool(runtime_cwd) and os.path.normcase(os.path.realpath(runtime_cwd)) == os.path.normcase(os.path.realpath(executable.parent))
    completed = report.get('status', {}).get('completed', [])
    complete = bool(report.get('clinic_segment_complete'))
    intentional_stage = bool(report.get('requested_stage_stopped')) and args.stop_after != 'complete'
    preservation = report.get('preservation', {})
    native_exit = report.get('native_exit', {})
    print(json.dumps({
        'complete': complete, 'requested_stage_stopped': intentional_stage,
        'requested_stage': args.stop_after, 'reached_stages': report.get('reached_stages'),
        'stop_reason': report.get('stop_reason'), 'phase': report.get('phase'),
        'seconds': report.get('seconds'), 'completed': completed,
        'failures': report.get('failures', []), 'engine_errors': report.get('engine_errors', []),
        'evidence': str(evidence), 'profile': PROFILE,
        'source_report_sha256': source_sha, 'runtime_cwd': runtime_cwd, 'own_folder': own_folder,
        'legal_prefix_preserved': preservation.get('original_prefix_preserved'),
        'current_SaveGate_completed': preservation.get('current_SaveGate_completed'),
        'native_exit': native_exit,
    }, ensure_ascii=False))
    if (report.get('profile') != PROFILE or report.get('source_report_sha256') != source_sha
            or report.get('source_receipts_sha256') != receipts_sha
            or report.get('requested_stage') != args.stop_after):
        raise RuntimeError('Observer result does not match this actual natural source/stage')
    if (execution_failure is not None or before != after or not own_folder
            or report.get('failures') or report.get('engine_errors')
            or not preservation.get('original_prefix_preserved')
            or not preservation.get('current_SaveGate_completed')
            or not preservation.get('fresh_Story_matches_live')
            or native_exit.get('through') != 'session._quit'
            or not native_exit.get('observed_scene_exit')
            or native_exit.get('watchdog_failed')
            or not native_exit.get('audio', {}).get('ready')
            or not (complete or intentional_stage)):
        raise SystemExit(1)


if __name__ == '__main__':
    main()
