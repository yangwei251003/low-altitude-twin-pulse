"""AUTHORING ONLY: exported MAIN, same natural Canal38 QA profile -> I2 Boss42.

Root must bind the real38 COMPLETE report, promote the observer/CLI and export.
This runner does not clone/reset/write a profile or start the engine directly.
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
SOURCE_REPORT = 'artifacts/v3/normal-canal-20261021_045050_067aca42/normal-canal-20261021_045050_067aca42.json'
STAGES = ('plan', 'engage', 'half', 'stop', 'complete')
MIN_GOALS = {'plan': 39, 'engage': 40, 'half': 40, 'stop': 41, 'complete': 42}


def receipt_digest(rows):
    return hashlib.sha256(json.dumps(rows, ensure_ascii=False, sort_keys=True,
                                     separators=(',', ':')).encode('utf-8')).hexdigest()


def main():
    global PROFILE, SOURCE_REPORT, SOURCE_REPORT_SHA256, THIRTYEIGHT_DIGEST
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe', type=Path,
                        default=PROJECT / 'build/V3Development/LowAltitudeTwinPulse-Dev.exe')
    parser.add_argument('--seconds', type=int, default=600, choices=range(60, 601),
                        metavar='60..600')
    parser.add_argument('--canal-report', type=Path, default=None)
    parser.add_argument('--stop-after', choices=STAGES, default='complete')
    parser.add_argument('--choice', choices=('clinic_reserve', 'balanced_service'),
                        default='balanced_service', help='Explicit automated QA story choice')
    add_binding_arguments(parser)
    args = parser.parse_args()
    binding = load_binding(args.source_binding, args.source_binding_sha256,
                           project=Path(__file__).resolve().parents[2],
                           entry='normal-i2-boss', segment='')
    PROFILE = binding.values['SOURCE_PROFILE']
    SOURCE_REPORT = binding.values['SOURCE_REPORT']
    SOURCE_REPORT_SHA256 = binding.values['SOURCE_REPORT_SHA256']
    THIRTYEIGHT_DIGEST = binding.values['THIRTYEIGHT_DIGEST']
    # Explicitly fail before profile, executable, Job, or evidence-directory I/O.
    if not SOURCE_REPORT:
        raise RuntimeError('Root must bind actual successful natural Canal38 SOURCE_REPORT; no fixture fallback')
    if args.canal_report is None:
        args.canal_report = binding.report_path
    elif args.canal_report.resolve(strict=True) != binding.report_path:
        raise RuntimeError('Explicit predecessor must equal strict binding source')
    installed = PROJECT / 'scripts/v3/qa/twin_normal_i2_boss_qa.gd'
    if not installed.is_file():
        raise RuntimeError('Root must promote the staged observer/CLI and export first')
    node_text = installed.read_text(encoding='utf-8-sig')

    def bound_constant(name):
        if name in binding.values:
            return binding.values[name]
        match = re.search(r'^const ' + re.escape(name) + r' := "([0-9a-f]{64})"$',
                          node_text, re.M)
        if not match:
            raise RuntimeError('Actual successful Canal38 source is not bound: ' + name)
        return match.group(1)

    def goal_constant(name):
        match = re.search(r'^const ' + re.escape(name) + r' := (\[.*\])$', node_text, re.M)
        if not match:
            raise RuntimeError('Exact natural goal order missing: ' + name)
        return json.loads(match.group(1))

    node_report = binding.values['SOURCE_REPORT']
    if node_report != SOURCE_REPORT:
        raise RuntimeError('Runner/observer Root-bound source report paths differ')
    source_sha = bound_constant('SOURCE_REPORT_SHA256')
    receipts_sha = bound_constant('THIRTYEIGHT_DIGEST')
    source_goals = goal_constant('SOURCE_GOALS')
    expected = goal_constant('EXPECTED')
    if len(source_goals) != 38 or len(expected) != 42:
        raise RuntimeError('Require exact38 source and42 final authored goal order')
    source_path = args.canal_report.resolve(strict=True)
    if source_path != (PROJECT / SOURCE_REPORT).resolve(strict=True):
        raise RuntimeError('Require exact Root-bound source report path')
    if hashlib.sha256(source_path.read_bytes()).hexdigest() != source_sha:
        raise RuntimeError('Actual Canal38 report differs from Root-bound SHA')
    source = json.loads(source_path.read_text(encoding='utf-8-sig'))
    goals = source.get('status', {}).get('completed', [])
    source_exit = source.get('native_exit', {})
    source_preservation = source.get('preservation', {})
    if (not source.get('canal_segment_complete') or source.get('failures')
            or source.get('engine_errors') or source.get('profile') != PROFILE
            or goals != source_goals or goals[-1] != 'I2:canal_service:order'
            or not source_preservation.get('original_prefix_preserved')
            or not source_preservation.get('current_SaveGate_completed')
            or not source_preservation.get('fresh_Story_matches_live')
            or source_exit.get('through') != 'session._quit'
            or not source_exit.get('observed_scene_exit')
            or source_exit.get('watchdog_failed')
            or not source_exit.get('audio', {}).get('ready')):
        raise RuntimeError('Require actual natural Canal38 with original durable save/exit evidence')
    rows = {key: value for key, value in source.get('story_receipts', {}).items()
            if value.get('objective_id') in source_goals}
    if len(rows) != 38 or receipt_digest(rows) != receipts_sha:
        raise RuntimeError('Actual38 source receipts differ')
    profile_path = Path(source['user_dir']) / 'profiles_v3' / PROFILE
    if not profile_path.is_dir():
        raise RuntimeError('Original QA profile absent; no replacement is created')
    executable = args.exe.resolve(strict=True)
    if executable.suffix.lower() != '.exe' or 'godot' in executable.name.lower():
        parser.error('Use the exported game EXE/main scene, not an engine executable')
    binding.verify_target(executable, dev.file_sha256)
    os.environ['LOW_ALTITUDE_DEV_HOME'] = str(dev.POLICY.root)
    stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S') + '_' + uuid.uuid4().hex[:8]
    dev.POLICY.preflight('evidence', 64 * 1024 ** 2)
    evidence = dev.POLICY.path('evidence', ('normal-i2-boss-' + stamp))
    evidence.mkdir(parents=True, exist_ok=False)
    output = evidence / ('normal-i2-boss-' + stamp + '.json')
    files = [executable, Path(__file__).resolve(), source_path, installed]
    if executable.with_suffix('.pck').is_file():
        files.append(executable.with_suffix('.pck'))
    names = [
        'scripts/v3/twin_app.gd', 'scripts/v3/twin_session.gd',
        'scripts/v3/twin_test_world.gd', 'scripts/v3/gameplay/twin_opening_story.gd',
        'scripts/v3/gameplay/twin_i2_result_ledger.gd',
        'scripts/v3/gameplay/twin_campaign_session.gd',
        'scripts/v3/gameplay/twin_pump_guardian_mechanisms.gd',
        'scripts/v3/gameplay/twin_campaign_choices.gd',
        'scripts/v3/campaign/twin_campaign_encounter.gd',
        'scripts/v3/world/twin_campaign_arena.gd',
        'scripts/v3/gameplay/twin_ability_rules.gd',
        'scripts/v3/gameplay/twin_weapon_session.gd',
        'scripts/v3/gameplay/environment/twin_water_network.gd',
        'scripts/v3/gameplay/canal/canal_transport_physics/transport_pilot.gd',
        'scripts/v3/core/twin_canal_save_gate.gd', 'scripts/v3/core/twin_world_store.gd',
        'data/v3/campaign/i2_actions.json', 'data/v3/campaign/bosses.json',
        'data/v3/campaign/choices.json', 'data/v3/regions.json',
    ]
    files.extend(PROJECT / name for name in names)

    files.extend(binding.evidence_files())

    def hashes():
        return {str(path): dev.file_sha256(path) for path in files}

    before = hashes()
    command = [str(executable), '--', '--qa-normal-i2-boss',
               '--qa-profile=' + PROFILE, '--qa-normal-output=' + str(output.resolve()),
               '--qa-normal-seconds=' + str(args.seconds),
               '--qa-i2-boss-stop-after=' + args.stop_after,
               '--qa-i2-boss-choice=' + args.choice]
    command.extend(binding.cli_args())
    (evidence / 'invocation.json').write_text(json.dumps({
        **binding.metadata,
        'command': command, 'profile': PROFILE, 'output': str(output),
        'working_directory': str(executable.parent), 'stop_after': args.stop_after,
        'choice': args.choice, 'requested_seconds': args.seconds,
        'job_timeout_seconds': args.seconds + 15,
        'source_profile_directory': str(profile_path), 'source_report_sha256': source_sha,
        'source_thirty_eight_receipts_sha256': receipts_sha,
        'scope': 'Actual exported MAIN, same natural Canal38 QA profile. Ordinary menu/spawn, '
                 'continuous original swept Pilot flight, original G isolation/valve, charge '
                 'keys/Tab/F/X, actual conservative combat water, normal held input shooting, '
                 'original Host LOS/part/HP/two-phase gates, actual cost-panel GUI read/choice, '
                 'original branch/Consensus/Story/Store/SaveGate/native audio quit. No scene/ '
                 'script override, ActorPose/Director/environment fixture, direct Boss start, '
                 'load_region, profile clone/reset/rollback or headless/affinity/quality override. '
                 'Partial stages are incomplete; not whole-game/LAN/human/performance acceptance.'
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
            'note': 'Only EXE/PCK hashes identify the actual artifact. Original QA profile '
                    'progresses normally; it is never reset, cloned or rolled back.'
        }, ensure_ascii=False, indent=2), encoding='utf-8')
    if not output.is_file():
        print(json.dumps({'complete': False, 'evidence': str(evidence),
                          'error': 'Missing observer report is incomplete, never success.'},
                         ensure_ascii=False))
        raise SystemExit(1)
    report = json.loads(output.read_text(encoding='utf-8-sig'))
    binding.validate_output(report)
    runtime_cwd = report.get('runtime_cwd', '')
    own_folder = (bool(runtime_cwd) and os.path.normcase(os.path.realpath(runtime_cwd))
                  == os.path.normcase(os.path.realpath(executable.parent)))
    completed = report.get('status', {}).get('completed', [])
    if completed != expected[:len(completed)] or not 38 <= len(completed) <= 42:
        raise RuntimeError('Observer reports another or illegal natural prefix')
    report_rows = {key: value for key, value in report.get('story_receipts', {}).items()
                   if value.get('objective_id') in source_goals}
    if len(report_rows) != 38 or receipt_digest(report_rows) != receipts_sha:
        raise RuntimeError('Observer changed actual source receipts')
    complete = bool(report.get('i2_boss_segment_complete'))
    if complete and (completed != expected or report.get('reached_stages') != list(STAGES)):
        raise RuntimeError('Complete requires all four actual goals and recorded stages')
    intentional_stage = (bool(report.get('requested_stage_stopped'))
                         and args.stop_after != 'complete'
                         and args.stop_after in report.get('reached_stages', [])
                         and len(completed) >= MIN_GOALS[args.stop_after])
    preservation = report.get('preservation', {})
    native_exit = report.get('native_exit', {})
    print(json.dumps({'complete': complete, 'requested_stage_stopped': intentional_stage,
        'requested_stage': args.stop_after, 'reached_stages': report.get('reached_stages'),
        'choice': args.choice, 'stop_reason': report.get('stop_reason'),
        'phase': report.get('phase'), 'seconds': report.get('seconds'), 'completed': completed,
        'failures': report.get('failures', []), 'engine_errors': report.get('engine_errors', []),
        'evidence': str(evidence), 'profile': PROFILE, 'runtime_cwd': runtime_cwd,
        'own_folder': own_folder, 'native_exit': native_exit,
        'actual_distance_m': report.get('actual_distance_m'),
        'actual_damage_samples': len(report.get('actual_damage_samples', []))}, ensure_ascii=False))
    if (report.get('profile') != PROFILE or report.get('source_report_sha256') != source_sha
            or report.get('source_receipts_sha256') != receipts_sha
            or report.get('requested_stage') != args.stop_after):
        raise RuntimeError('Observer result does not match actual natural source/stage')
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
