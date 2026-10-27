"""Run exported MAIN on the same natural Clinic31 profile, through Distribution34.

AUTHORING COPY: Root promotes the Node/CLI and exports. No progress is imported
from a report and this runner never modifies, clones or rolls back a profile.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import uuid

sys.dont_write_bytecode = True
PROJECT = next(parent for parent in Path(__file__).resolve().parents
               if (parent / 'project.godot').is_file()
               and (parent / 'scripts_tools/v3/dev.py').is_file())
sys.path.insert(0, str(PROJECT / 'scripts_tools/v3'))
import dev

PROFILE = 'qa_normal_campaign_20261021_112119_b0f35d51'
BASE_TWENTYSEVEN_SHA = '00bbacef10aa535adf424c12d4f78d4da9230d018c3c1079401c86da72dc9304'
STAGES = ('expose', 'trace', 'complete')
SOURCE_REPORT = 'artifacts/v3/normal-clinic-20261021_123525_bed1717a/normal-clinic-20261021_123525_bed1717a.json'


def receipt_digest(rows):
    return hashlib.sha256(json.dumps(rows, ensure_ascii=False, sort_keys=True,
                                     separators=(',', ':')).encode('utf-8')).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe', type=Path,
                        default=PROJECT / 'build/V3Development/LowAltitudeTwinPulse-Dev.exe')
    parser.add_argument('--seconds', type=int, default=600, choices=range(30, 601),
                        metavar='30..600')
    parser.add_argument('--clinic-report', type=Path, default=PROJECT / SOURCE_REPORT,
                        help='Exact bound dev40 actual natural Clinic COMPLETE report')
    parser.add_argument('--stop-after', choices=STAGES, default='complete',
                        help='Expose/trace stops preserve an explicitly incomplete action')
    args = parser.parse_args()
    executable = args.exe.resolve(strict=True)
    if executable.suffix.lower() != '.exe' or 'godot' in executable.name.lower():
        parser.error('Use the exported game EXE/main scene, not an engine executable')
    installed = PROJECT / 'scripts/v3/qa/twin_normal_distribution_qa.gd'
    if not installed.is_file():
        raise RuntimeError('Root must promote the staged Distribution Node/CLI and export first')
    node_text = installed.read_text(encoding='utf-8-sig')

    def bound_constant(name):
        match = re.search(r'^const ' + re.escape(name) + r' := "([0-9a-f]{64})"$',
                          node_text, re.M)
        if not match:
            raise RuntimeError('Actual successful Clinic source is not bound: ' + name)
        return match.group(1)

    def goal_constant(name):
        match = re.search(r'^const ' + re.escape(name) + r' := (\[.*\])$', node_text, re.M)
        if not match:
            raise RuntimeError('Exact original goal order missing: ' + name)
        return json.loads(match.group(1))

    source_sha = bound_constant('SOURCE_REPORT_SHA256')
    receipts_sha = bound_constant('THIRTYONE_DIGEST')
    source_goals = goal_constant('SOURCE_GOALS')
    expected = goal_constant('EXPECTED')
    source_path = args.clinic_report.resolve(strict=True)
    if hashlib.sha256(source_path.read_bytes()).hexdigest() != source_sha:
        raise RuntimeError('Actual Clinic report differs from Root-bound SHA')
    source = json.loads(source_path.read_text(encoding='utf-8-sig'))
    goals = source.get('status', {}).get('completed', [])
    source_exit = source.get('native_exit', {})
    source_preservation = source.get('preservation', {})
    if (not source.get('clinic_segment_complete') or source.get('failures')
            or source.get('engine_errors') or source.get('profile') != PROFILE
            or len(goals) != 31 or goals != source_goals
            or goals[-1] != 'I2:clinic_supply:confirm'
            or source.get('source_receipts_sha256') != BASE_TWENTYSEVEN_SHA
            or not source_preservation.get('original_prefix_preserved')
            or not source_preservation.get('current_SaveGate_completed')
            or not source_preservation.get('fresh_Story_matches_live')
            or source_exit.get('through') != 'session._quit'
            or not source_exit.get('observed_scene_exit')
            or source_exit.get('watchdog_failed')
            or not source_exit.get('audio', {}).get('ready')):
        raise RuntimeError('Require successful natural Clinic31 and original durable exit evidence')
    rows = {key: value for key, value in source['story_receipts'].items()
            if value['objective_id'] in source_goals}
    if len(rows) != 31 or receipt_digest(rows) != receipts_sha:
        raise RuntimeError('Actual thirty-one source receipts differ')
    profile_path = Path(source['user_dir']) / 'profiles_v3' / PROFILE
    if not profile_path.is_dir():
        raise RuntimeError('Original QA profile absent; no replacement is created')

    stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S') + '_' + uuid.uuid4().hex[:8]
    dev.POLICY.preflight('evidence', 64 * 1024 ** 2)
    evidence = dev.POLICY.path('evidence', 'normal-distribution-' + stamp)
    evidence.mkdir(parents=True, exist_ok=False)
    output = evidence / ('normal-distribution-' + stamp + '.json')
    files = [executable, Path(__file__).resolve(), source_path]
    if executable.with_suffix('.pck').is_file():
        files.append(executable.with_suffix('.pck'))
    names = [
        'scripts/v3/qa/twin_normal_distribution_qa.gd',
        'scripts/v3/twin_app.gd', 'scripts/v3/twin_session.gd', 'scripts/v3/twin_test_world.gd',
        'scripts/v3/gameplay/twin_opening_story.gd',
        'scripts/v3/gameplay/twin_i2_result_ledger.gd',
        'scripts/v3/gameplay/twin_clinic_session.gd',
        'scripts/v3/gameplay/actions/twin_clinic_progress.gd',
        'scripts/v3/gameplay/actions/twin_distribution_progress.gd',
        'scripts/v3/gameplay/twin_distribution_session.gd',
        'scripts/v3/world/twin_distribution_cabinet.gd',
        'scripts/v3/world/twin_distribution_layout_migration.gd',
        'scripts/v3/gameplay/twin_trial_session.gd',
        'scripts/v3/world/twin_trial_assembly.gd',
        'scripts/v3/world/twin_trial_isolation_link.gd',
        'scripts/v3/world/twin_trial_flow_station.gd',
        'scripts/v3/environment/twin_trial_flow_runtime.gd',
        'scripts/v3/gameplay/environment/twin_water_network.gd',
        'scripts/v3/gameplay/twin_shared_access_session.gd',
        'scripts/v3/world/twin_shared_access_bridge.gd',
        'scripts/v3/environment/twin_guided_axis.gd',
        'scripts/v3/gameplay/twin_ability_rules.gd',
        'scripts/v3/gameplay/canal/canal_transport_physics/transport_pilot.gd',
        'scripts/v3/core/twin_canal_save_gate.gd', 'scripts/v3/core/twin_world_store.gd',
        'data/v3/actions/clinic_action.json', 'data/v3/actions/distribution_action.json',
        'data/v3/terrain/i2_distribution_layout.json',
        'data/v3/terrain/i2_distribution_trial_layout.json',
        'data/v3/terrain/i2_trial_flow_layout.json',
        'data/v3/terrain/i2_shared_access_layout.json',
        'data/v3/environment/i2_trial_flow_network.json',
    ]
    files.extend(PROJECT / name for name in names)

    def hashes():
        return {str(path): dev.file_sha256(path) for path in files}

    before = hashes()
    command = [str(executable), '--', '--qa-normal-distribution',
               '--qa-profile=' + PROFILE, '--qa-normal-output=' + str(output.resolve()),
               '--qa-normal-seconds=' + str(args.seconds),
               '--qa-distribution-stop-after=' + args.stop_after]
    (evidence / 'invocation.json').write_text(json.dumps({
        'command': command, 'profile': PROFILE, 'output': str(output),
        'working_directory': str(executable.parent), 'stop_after': args.stop_after,
        'requested_seconds': args.seconds, 'job_timeout_seconds': args.seconds + 15,
        'source_profile_directory': str(profile_path), 'source_report_sha256': source_sha,
        'source_thirty_one_receipts_sha256': receipts_sha,
        'scope': 'Exported MAIN same natural Clinic31 profile. Normal menu/spawn, '
                 'original Pilot/Flight sweeps, ability keys/Tab/F, real upward '
                 'low-door charge/takeover, two-panel G, actual isolation handle, '
                 'actual opposite 20L samples and both window G readings, actual '
                 '8m bridge motor/pin and explicit G/solo Consensus/Store. No '
                 'script/scene override, fixture, actor/mechanism/water/HP/time/'
                 'collision/flags edit, clone/rollback, headless or quality '
                 'override. Expose/trace stops are incomplete. Legal 31..34 '
                 'prefixes resume original histories. No Canal/Boss/LAN claim.'
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
            'note': 'Working-tree hashes identify source; only EXE/PCK hashes '
                    'identify the actual artifact. The profile is never reset.'
        }, ensure_ascii=False, indent=2), encoding='utf-8')
    if not output.is_file():
        print(json.dumps({'complete': False, 'evidence': str(evidence),
                          'error': 'Missing observer result: import/CLI/process failure '
                                   'or timeout is incomplete, never a successful stage.'},
                         ensure_ascii=False))
        raise SystemExit(1)
    report = json.loads(output.read_text(encoding='utf-8-sig'))
    runtime_cwd = report.get('runtime_cwd', '')
    own_folder = (bool(runtime_cwd)
                  and os.path.normcase(os.path.realpath(runtime_cwd))
                  == os.path.normcase(os.path.realpath(executable.parent)))
    completed = report.get('status', {}).get('completed', [])
    if completed != expected[:len(completed)] or not 31 <= len(completed) <= 34:
        raise RuntimeError('Observer reports a different or illegal natural prefix')
    report_rows = {key: value for key, value in report.get('story_receipts', {}).items()
                   if value.get('objective_id') in source_goals}
    if len(report_rows) != 31 or receipt_digest(report_rows) != receipts_sha:
        raise RuntimeError('Observer changed actual source receipts')
    complete = bool(report.get('distribution_segment_complete'))
    if complete and (completed != expected or report.get('reached_stages') != list(STAGES)):
        raise RuntimeError('Complete requires all three actual natural goals and stages')
    intentional_stage = (bool(report.get('requested_stage_stopped'))
                         and args.stop_after != 'complete'
                         and args.stop_after in report.get('reached_stages', [])
                         and len(completed) >= (32 if args.stop_after == 'expose' else 33))
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
        raise RuntimeError('Observer result does not match the actual natural source/stage')
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

