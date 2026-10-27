"""Run exported MAIN on the same actual Distribution34 profile through Canal38.

Authoring only. Root must promote, bind actual Distribution source and export.
No profile reset, progress import, detached scene, simulation tick or fixture.
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
from qa_source_binding import add_binding_arguments, load_binding
PROJECT = next(parent for parent in Path(__file__).resolve().parents
               if (parent / 'project.godot').is_file()
               and (parent / 'scripts_tools/v3/dev.py').is_file())
sys.path.insert(0, str(PROJECT / 'scripts_tools/v3'))
import dev

PROFILE = 'qa_normal_campaign_20261021_012725_b90f8a6f'
BASE_THIRTYONE_SHA = 'aeab313d370932bf70a7fc9ecd28579d2c124b37751059ce3ac2ade56c507a7e'
STAGES = ('cooling', 'ordered', 'served', 'complete')
STAGE_GOALS = {'cooling': 36, 'ordered': 36, 'served': 37, 'complete': 38}


def digest(rows):
    return hashlib.sha256(json.dumps(rows, ensure_ascii=False, sort_keys=True,
                                     separators=(',', ':')).encode('utf-8')).hexdigest()


def main():
    global PROFILE, SOURCE_REPORT, SOURCE_REPORT_SHA256, THIRTYFOUR_DIGEST
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe', type=Path,
                        default=PROJECT / 'build/V3Development/LowAltitudeTwinPulse-Dev.exe')
    parser.add_argument('--distribution-report', type=Path, default=None,
                        help='Actual successful natural Distribution COMPLETE report, never imported')
    parser.add_argument('--seconds', type=int, default=600, choices=range(30, 601),
                        metavar='30..600')
    parser.add_argument('--stop-after', choices=STAGES, default='complete')
    add_binding_arguments(parser)
    args = parser.parse_args()
    binding = load_binding(args.source_binding, args.source_binding_sha256,
                           project=Path(__file__).resolve().parents[2],
                           entry='normal-canal', segment='')
    PROFILE = binding.values['SOURCE_PROFILE']
    SOURCE_REPORT = binding.values['SOURCE_REPORT']
    SOURCE_REPORT_SHA256 = binding.values['SOURCE_REPORT_SHA256']
    THIRTYFOUR_DIGEST = binding.values['THIRTYFOUR_DIGEST']
    if args.distribution_report is None:
        args.distribution_report = binding.report_path
    elif args.distribution_report.resolve(strict=True) != binding.report_path:
        raise RuntimeError('Explicit predecessor must equal strict binding source')
    executable = args.exe.resolve(strict=True)
    if executable.suffix.lower() != '.exe' or 'godot' in executable.name.lower():
        parser.error('Use the exported game EXE/main scene, not an engine executable')
    installed = PROJECT / 'scripts/v3/qa/twin_normal_canal_qa.gd'
    if not installed.is_file():
        raise RuntimeError('Root must promote the staged Canal Node/CLI and export first')
    source_code = installed.read_text(encoding='utf-8-sig')

    def constant(name, array=False):
        if name in binding.values:
            return binding.values[name]
        pattern = (r'^const ' + re.escape(name) + r' := (\[.*\])$' if array else
                   r'^const ' + re.escape(name) + r' := "([0-9a-f]{64})"$')
        match = re.search(pattern, source_code, re.M)
        if not match:
            raise RuntimeError('Actual Distribution34 binding/goal contract absent: ' + name)
        return json.loads(match.group(1)) if array else match.group(1)

    source_sha = constant('SOURCE_REPORT_SHA256')
    receipts_sha = constant('THIRTYFOUR_DIGEST')
    source_goals = constant('SOURCE_GOALS', True)
    expected = constant('EXPECTED', True)
    source_path = args.distribution_report.resolve(strict=True)
    if hashlib.sha256(source_path.read_bytes()).hexdigest() != source_sha:
        raise RuntimeError('Actual Distribution report differs from Root-bound SHA')
    source = json.loads(source_path.read_text(encoding='utf-8-sig'))
    source_exit = source.get('native_exit', {})
    saved = source.get('preservation', {})
    goals = source.get('status', {}).get('completed', [])
    if (not source.get('distribution_segment_complete') or source.get('failures')
            or source.get('engine_errors') or source.get('profile') != PROFILE
            or len(goals) != 34 or goals != source_goals
            or goals[-1] != 'I2:distribution_audit:share_access'
            or source.get('source_receipts_sha256') != BASE_THIRTYONE_SHA
            or not saved.get('original_prefix_preserved')
            or not saved.get('current_SaveGate_completed')
            or not saved.get('fresh_Story_matches_live')
            or source_exit.get('through') != 'session._quit'
            or not source_exit.get('observed_scene_exit')
            or source_exit.get('watchdog_failed')
            or not source_exit.get('audio', {}).get('ready')):
        raise RuntimeError('Require actual successful natural Distribution34 and durable original exit')
    rows = {key: value for key, value in source['story_receipts'].items()
            if value['objective_id'] in source_goals}
    if len(rows) != 34 or digest(rows) != receipts_sha:
        raise RuntimeError('Actual thirty-four natural source receipts differ')
    profile_path = Path(source['user_dir']) / 'profiles_v3' / PROFILE
    if not profile_path.is_dir():
        raise RuntimeError('Original QA profile absent; no replacement is created')

    binding.verify_target(executable, dev.file_sha256)
    os.environ['LOW_ALTITUDE_DEV_HOME'] = str(dev.POLICY.root)
    stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S') + '_' + uuid.uuid4().hex[:8]
    dev.POLICY.preflight('evidence', 64 * 1024 ** 2)
    evidence = dev.POLICY.path('evidence', ('normal-canal-' + stamp))
    evidence.mkdir(parents=True, exist_ok=False)
    output = evidence / ('normal-canal-' + stamp + '.json')
    files = [executable, Path(__file__).resolve(), source_path]
    if executable.with_suffix('.pck').is_file():
        files.append(executable.with_suffix('.pck'))
    names = [
        'scripts/v3/qa/twin_normal_canal_qa.gd',
        'scripts/v3/twin_app.gd', 'scripts/v3/twin_session.gd', 'scripts/v3/twin_test_world.gd',
        'scripts/v3/gameplay/twin_opening_story.gd',
        'scripts/v3/gameplay/actions/twin_action_director.gd',
        'scripts/v3/gameplay/actions/twin_clinic_progress.gd',
        'scripts/v3/gameplay/actions/twin_distribution_progress.gd',
        'scripts/v3/world/twin_distribution_cabinet.gd',
        'scripts/v3/gameplay/twin_i2_result_ledger.gd',
        'scripts/v3/gameplay/twin_canal_session.gd',
        'scripts/v3/gameplay/twin_ability_rules.gd',
        'scripts/v3/core/twin_canal_save_gate.gd', 'scripts/v3/core/twin_world_store.gd',
        'data/v3/campaign/i2_actions.json',
        'assets/v3/environment/canal_calibration_rack/calibration_rack.glb',
    ]
    files.extend(PROJECT / name for name in names)
    files.extend(sorted((PROJECT / 'scripts/v3/gameplay/canal').rglob('*.gd')))

    files.extend(binding.evidence_files())

    def hashes():
        return {str(path): dev.file_sha256(path) for path in files}

    before = hashes()
    command = [str(executable), '--', '--qa-normal-canal',
               '--qa-profile=' + PROFILE, '--qa-normal-output=' + str(output.resolve()),
               '--qa-normal-seconds=' + str(args.seconds),
               '--qa-canal-stop-after=' + args.stop_after]
    command.extend(binding.cli_args())
    (evidence / 'invocation.json').write_text(json.dumps({
        **binding.metadata,
        'command': command, 'profile': PROFILE, 'output': str(output),
        'working_directory': str(executable.parent), 'stop_after': args.stop_after,
        'requested_seconds': args.seconds, 'job_timeout_seconds': args.seconds + 15,
        'source_profile_directory': str(profile_path), 'source_report_sha256': source_sha,
        'source_thirty_four_receipts_sha256': receipts_sha,
        'scope': 'Exported MAIN same natural Distribution34 profile. Original '
                 'bootstrap/restore, current canonical IDs/native WORK, continuous '
                 'Flight/Pilot sweeps, normal 5/Tab/X thermal cooling and actual '
                 '350ms Custody, 0/Tab/F original order, 6/Tab/F bench power, real '
                 'scan/departure/cleanup transport/docks/Safe readiness, near/LOS '
                 'G same-Store service, dispatch G. No fixture, actor/thermal/'
                 'water/HP/clock/flags edit, controller tick, profile clone, '
                 'rollback, progress import, headless mode or quality override. '
                 'Cooling/ordered/served stages remain incomplete. '
                 'No I2Boss, whole campaign or LAN acceptance.'
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
            **binding.metadata,
            'before': before, 'after': after, 'unchanged': before == after,
            'process': process, 'execution_failure': execution_failure,
            'artifact_sha256': before[str(executable)],
            'note': 'Only EXE/PCK hashes identify the executed artifact; source '
                    'hashes identify the worktree. The profile is never reset.'
        }, ensure_ascii=False, indent=2), encoding='utf-8')
    if not output.is_file():
        print(json.dumps({'complete': False, 'evidence': str(evidence),
                          'error': 'No observer result: process/import/CLI failure '
                                   'or timeout never means a successful stage.'}, ensure_ascii=False))
        raise SystemExit(1)
    report = json.loads(output.read_text(encoding='utf-8-sig'))
    binding.validate_output(report)
    runtime_cwd = report.get('runtime_cwd', '')
    own_folder = (bool(runtime_cwd)
                  and os.path.normcase(os.path.realpath(runtime_cwd))
                  == os.path.normcase(os.path.realpath(executable.parent)))
    completed = report.get('status', {}).get('completed', [])
    if completed != expected[:len(completed)] or not 34 <= len(completed) <= 38:
        raise RuntimeError('Observer reports a different or illegal natural prefix')
    rows = {key: value for key, value in report.get('story_receipts', {}).items()
            if value.get('objective_id') in source_goals}
    if len(rows) != 34 or digest(rows) != receipts_sha:
        raise RuntimeError('Observer changed actual source receipts')
    complete = bool(report.get('canal_segment_complete'))
    if complete and (completed != expected or report.get('reached_stages') != list(STAGES)):
        raise RuntimeError('Complete requires all four actual Canal goals and all stages')
    intentional_stage = (bool(report.get('requested_stage_stopped'))
                         and args.stop_after != 'complete'
                         and args.stop_after in report.get('reached_stages', [])
                         and len(completed) >= STAGE_GOALS[args.stop_after])
    preservation = report.get('preservation', {})
    native_exit = report.get('native_exit', {})
    print(json.dumps({
        'complete': complete, 'requested_stage_stopped': intentional_stage,
        'requested_stage': args.stop_after, 'reached_stages': report.get('reached_stages'),
        'stop_reason': report.get('stop_reason'), 'phase': report.get('phase'),
        'seconds': report.get('seconds'), 'completed': completed,
        'failures': report.get('failures', []), 'engine_errors': report.get('engine_errors', []),
        'evidence': str(evidence), 'profile': PROFILE, 'runtime_cwd': runtime_cwd,
        'own_folder': own_folder, 'preservation': preservation,
        'source_report_sha256': source_sha, 'native_exit': native_exit,
    }, ensure_ascii=False))
    if (report.get('profile') != PROFILE or report.get('source_report_sha256') != source_sha
            or report.get('source_receipts_sha256') != receipts_sha
            or report.get('requested_stage') != args.stop_after):
        raise RuntimeError('Observer result does not match actual source/stage')
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

