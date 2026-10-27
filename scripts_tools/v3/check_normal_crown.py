"""Run an exported MAIN Crown continuation of the actual natural Whale record profile.

AUTHORING COPY: Root must install the Node/CLI and export before this is runnable.
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
BASE_SEVENTEEN_SHA = 'e9c3d0dff74fdff6a79c6fb47f2adc8c7bb8bd05bf4463d1a6716b6bdb4f41a4'
STAGES = ('brief', 'engage', 'first_bound', 'half', 'second_bound', 'victory', 'record')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe', type=Path,
                        default=PROJECT / 'build/V3Development/LowAltitudeTwinPulse-Dev.exe')
    parser.add_argument('--seconds', type=int, default=300, choices=range(30, 301),
                        metavar='30..300')
    parser.add_argument('--whale-report', type=Path,
                        default=PROJECT / 'artifacts/v3/normal-whale-20261021_115707_bb95717b/normal-whale-20261021_115707_bb95717b.json',
                        help='Actual dev75 natural Whale report; exact bound SHA and receipts must match')
    parser.add_argument('--stop-after', choices=STAGES, default='record',
                        help='Intentional ordinary Consensus pause; only record means segment complete')
    args = parser.parse_args()
    executable = args.exe.resolve(strict=True)
    if executable.suffix.lower() != '.exe' or 'godot' in executable.name.lower():
        parser.error('Use the actual exported game EXE/main scene, not an engine executable')
    installed = PROJECT / 'scripts/v3/qa/twin_normal_crown_qa.gd'
    if not installed.is_file():
        raise RuntimeError('Root must install the staged Crown Node/CLI and export first')
    node_text = installed.read_text(encoding='utf-8-sig')

    def bound_constant(name):
        match = re.search(r'^const ' + re.escape(name) + r' := "([0-9a-f]{64})"$', node_text, re.M)
        if not match:
            raise RuntimeError('Root must bind actual successful Whale evidence: ' + name)
        return match.group(1)

    source_sha = bound_constant('SOURCE_REPORT_SHA256')
    receipts_sha = bound_constant('NINETEEN_DIGEST')
    source_path = args.whale_report.resolve(strict=True)
    if hashlib.sha256(source_path.read_bytes()).hexdigest() != source_sha:
        raise RuntimeError('Actual normal Whale report does not match Root-bound SHA')
    source = json.loads(source_path.read_text(encoding='utf-8-sig'))
    goals = source.get('status', {}).get('completed', [])
    if (not source.get('whale_segment_complete') or source.get('failures')
            or source.get('engine_errors') or source.get('profile') != PROFILE
            or len(goals) != 19 or goals[-1] != 'I1:whale:record'
            or source.get('source_receipts_sha256') != BASE_SEVENTEEN_SHA
            or not source.get('native_exit', {}).get('observed_scene_exit')
            or not source.get('native_exit', {}).get('audio', {}).get('ready')):
        raise RuntimeError('Require actual successful natural Whale record and production exit evidence')
    rows = {key: value for key, value in source['story_receipts'].items()
            if value['objective_id'] in goals}
    actual_digest = hashlib.sha256(json.dumps(
        rows, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode('utf-8')).hexdigest()
    if len(rows) != 19 or actual_digest != receipts_sha:
        raise RuntimeError('Actual nineteen natural Whale-source receipts differ')
    profile_path = Path(source['user_dir']) / 'profiles_v3' / PROFILE
    if not profile_path.is_dir():
        raise RuntimeError('Original real QA profile absent; no replacement is created')
    stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S') + '_' + uuid.uuid4().hex[:8]
    evidence = PROJECT / 'artifacts/v3' / ('normal-crown-' + stamp)
    evidence.mkdir(parents=True, exist_ok=False)
    output = evidence / ('normal-crown-' + stamp + '.json')
    files = [executable, Path(__file__).resolve(), source_path]
    if executable.with_suffix('.pck').is_file():
        files.append(executable.with_suffix('.pck'))
    names = [
        'scripts/v3/qa/twin_normal_crown_qa.gd',
        'scripts/v3/twin_app.gd', 'scripts/v3/twin_session.gd',
        'scripts/v3/gameplay/twin_opening_story.gd',
        'scripts/v3/gameplay/twin_crown_encounter.gd',
        'scripts/v3/gameplay/twin_crown_session.gd',
        'scripts/v3/world/twin_crown_arena.gd',
        'scripts/v3/gameplay/twin_ability_rules.gd',
        'scripts/v3/gameplay/canal/canal_transport_physics/transport_pilot.gd',
        'scripts/v3/core/twin_canal_save_gate.gd',
        'scripts/v3/core/twin_world_store.gd',
        'scripts/v3/art/twin_parasitic_crown.gd',
        'assets/v3/crown/parasitic_crown.glb',
        'assets/v3/root_buttress/root_buttress_h10.glb',
        'assets/v3/root_buttress/root_buttress_h17.glb',
        'assets/v3/root_buttress/root_buttress_h12.glb',
        'data/v3/actions/crown_action.json', 'data/v3/bosses/crown_parasite.json',
    ]
    files.extend(PROJECT / name for name in names)

    def hashes():
        return {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in files}

    before = hashes()
    command = [str(executable), '--', '--qa-normal-crown',
               '--qa-profile=' + PROFILE, '--qa-normal-output=' + str(output.resolve()),
               '--qa-normal-seconds=' + str(args.seconds),
               '--qa-crown-stop-after=' + args.stop_after]
    (evidence / 'invocation.json').write_text(json.dumps({
        'command': command, 'profile': PROFILE, 'output': str(output),
        'working_directory': str(executable.parent), 'stop_after': args.stop_after,
        'requested_seconds': args.seconds, 'job_timeout_seconds': args.seconds + 15,
        'source_profile_directory': str(profile_path), 'source_report_sha256': source_sha,
        'source_nineteen_receipts_sha256': receipts_sha,
        'scope': 'Exported main scene, original physical Flight/Pilot and native inputs, '
                 'real imported host/core rays, half-health clamp and native migration, original rewards/Store. '
                 'No --script, scene override, profile clone/rollback, fixture progression, '
                 'pose/HP/clock/cooldown writes, headless mode, affinity or quality override. '
                 'A requested stage stop is not a Crown victory or segment completion. '
                 'Valid 19/20/21/22/23-goal partial prefixes continue without reset. '
                 'Unfinished encounter state is not claimed to persist across app restarts.'
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
    complete = bool(report.get('crown_segment_complete'))
    intentional_stage = bool(report.get('requested_stage_stopped')) and args.stop_after != 'record'
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
