"""AUTHORING ONLY: exported ordinary MAIN, same natural QA50->54 / QA54->58.

The selected independent report/SHA/receipt binding must exist before this runner
looks at EXE, original QA profile, output directories, or Windows private Job.
Root promotes, binds actual evidence, exports and is the sole engine operator.
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
PROFILE = 'qa_normal_campaign_20261021_012725_b90f8a6f'
SOURCE_REPORT = 'artifacts/v3/normal-f2-boss-20261021_054010_cb585820/normal-f2-boss-20261021_054010_cb585820.json'
SOURCE_REPORT_SHA256 = '54103bb3ca1c1d5ba4d31dd4c936a80ceb352a9e047bd372df52f04092311942'
FIFTY_DIGEST = '419b5811badc7edfdaee5e8ec89d84478ebfca9739c5b512ece7d4947e9cb324'
SOURCE54_REPORT = 'artifacts/v3/normal-i3-tasks-20261021_060005_46de93c6/normal-i3-tasks-20261021_060005_46de93c6.json'
SOURCE54_REPORT_SHA256 = '073957917797b59c7e5c913b197d0ca9447a456b53a610c0f83d714c7178e72c'
FIFTYFOUR_DIGEST = 'b9aad745e539152b7b5ecd3978c11d23b3f0011947e9f9da4fe421b81000ff2a'
STAGES = {
    'tasks': ('brief', 'ledger', 'exchange', 'dock', 'complete'),
    'boss': ('plan', 'engage', 'half', 'stop', 'complete'),
}
MIN_GOALS = {
    'tasks': {'brief': 51, 'ledger': 52, 'exchange': 53, 'dock': 54, 'complete': 54},
    'boss': {'plan': 55, 'engage': 56, 'half': 56, 'stop': 57, 'complete': 58},
}


def digest(rows):
    return hashlib.sha256(json.dumps(rows, ensure_ascii=False, sort_keys=True,
                                     separators=(',', ':')).encode('utf-8')).hexdigest()


def main():
    global PROFILE, SOURCE_REPORT, SOURCE_REPORT_SHA256, FIFTY_DIGEST, SOURCE54_REPORT, SOURCE54_REPORT_SHA256, FIFTYFOUR_DIGEST
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--segment', choices=('tasks', 'boss'), default='tasks')
    parser.add_argument('--stop-after', default='complete')
    parser.add_argument('--seconds', type=int, default=600, choices=range(60, 601),
                        metavar='60..600')
    parser.add_argument('--exe', type=Path)
    add_binding_arguments(parser)
    args = parser.parse_args()
    binding = load_binding(args.source_binding, args.source_binding_sha256,
                           project=Path(__file__).resolve().parents[2],
                           entry='normal-i3', segment=args.segment)
    PROFILE = binding.values['SOURCE_PROFILE']
    SOURCE_REPORT = binding.values['SOURCE_REPORT']
    SOURCE_REPORT_SHA256 = binding.values['SOURCE_REPORT_SHA256']
    FIFTY_DIGEST = binding.values['FIFTY_DIGEST']
    if 'SOURCE54_REPORT' in binding.values:
        SOURCE54_REPORT = binding.values['SOURCE54_REPORT']
    if 'SOURCE54_REPORT_SHA256' in binding.values:
        SOURCE54_REPORT_SHA256 = binding.values['SOURCE54_REPORT_SHA256']
    if 'FIFTYFOUR_DIGEST' in binding.values:
        FIFTYFOUR_DIGEST = binding.values['FIFTYFOUR_DIGEST']
    which = args.segment
    path, report_sha, receipts_sha, count, end = (
        (SOURCE_REPORT, SOURCE_REPORT_SHA256, FIFTY_DIGEST, 50, 54)
        if which == 'tasks' else
        (SOURCE54_REPORT, SOURCE54_REPORT_SHA256, FIFTYFOUR_DIGEST, 54, 58))
    # Deliberately before installed observer/profile/EXE reads and mkdir/Job.
    if (not SOURCE_REPORT or not re.fullmatch('[0-9a-f]{64}', SOURCE_REPORT_SHA256)
            or not path or not re.fullmatch('[0-9a-f]{64}', report_sha)
            or not re.fullmatch('[0-9a-f]{64}', receipts_sha)
            or not re.fullmatch('[0-9a-f]{64}', FIFTY_DIGEST)):
        raise RuntimeError('Root must bind actual successful natural50/independent54 '
                           'report, exact SHA and receipt digest; no fixture fallback')
    if args.stop_after not in STAGES[which]:
        parser.error('The selected segment stage must be one of ' + ', '.join(STAGES[which]))
    PROJECT = next(p for p in Path(__file__).resolve().parents
                   if (p / 'project.godot').is_file()
                   and (p / 'scripts_tools/v3/dev.py').is_file())
    if args.exe is None:
        args.exe = PROJECT / 'build/V3Development/LowAltitudeTwinPulse-Dev.exe'
    installed = PROJECT / 'scripts/v3/qa/twin_normal_i3_qa.gd'
    node_text = installed.read_text(encoding='utf-8-sig')

    def constant(name):
        if name in binding.values:
            return binding.values[name]
        match = re.search(r'^const ' + re.escape(name) + r' := "([^"\r\n]*)"$',
                          node_text, re.M)
        if not match:
            raise RuntimeError('Missing installed observer binding: ' + name)
        return match.group(1)

    def array_constant(name):
        match = re.search(r'^const ' + re.escape(name) + r' := (\[.*\])$', node_text, re.M)
        if not match:
            raise RuntimeError('Missing exact natural goal array: ' + name)
        return json.loads(match.group(1))

    names = ('SOURCE_REPORT', 'SOURCE_REPORT_SHA256', 'FIFTY_DIGEST') if which == 'tasks' else (
        'SOURCE54_REPORT', 'SOURCE54_REPORT_SHA256', 'FIFTYFOUR_DIGEST')
    if tuple(constant(name) for name in names) != (path, report_sha, receipts_sha):
        raise RuntimeError('Runner/installed observer independent source bindings differ')
    if constant('FIFTY_DIGEST') != FIFTY_DIGEST:
        raise RuntimeError('Original50 receipt binding differs')
    if (constant('SOURCE_REPORT'), constant('SOURCE_REPORT_SHA256')) != (
            SOURCE_REPORT, SOURCE_REPORT_SHA256):
        raise RuntimeError('Original50 report binding differs')
    expected = array_constant('EXPECTED')
    original50 = array_constant('SOURCE_GOALS')
    source_goals = expected[:count]
    if len(expected) != 58 or len(original50) != 50 or original50 != expected[:50]:
        raise RuntimeError('Require exact authored natural50 /54 /58 order')
    source_path = (PROJECT / path).resolve(strict=True)
    if source_path != binding.report_path or source_path.suffix != '.json':
        raise RuntimeError('Actual source report must be the explicit project evidence JSON')
    if hashlib.sha256(source_path.read_bytes()).hexdigest() != report_sha:
        raise RuntimeError('Root-bound actual report SHA changed')
    source = json.loads(source_path.read_text(encoding='utf-8-sig'))
    preservation = source.get('preservation', {})
    native = source.get('native_exit', {})
    completed = source.get('status', {}).get('completed')
    success = (source.get('f2_boss_segment_complete') if which == 'tasks' else
               source.get('i3_segment_complete') and source.get('segment') == 'tasks')
    if (not success or not source.get('complete') or source.get('failures')
            or source.get('engine_errors') or source.get('profile') != PROFILE
            or completed != source_goals
            or not preservation.get('original_prefix_preserved')
            or not preservation.get('current_SaveGate_completed')
            or not preservation.get('fresh_Story_matches_live')
            or native.get('through') != 'session._quit'
            or not native.get('observed_scene_exit') or native.get('watchdog_failed')
            or not native.get('audio', {}).get('ready')):
        raise RuntimeError('Actual complete source must include original durable save/native exit')
    rows = {key: row for key, row in source.get('story_receipts', {}).items()
            if isinstance(row, dict) and row.get('objective_id') in source_goals}
    rows50 = {key: row for key, row in rows.items() if row.get('objective_id') in original50}
    if len(rows) != count or digest(rows) != receipts_sha or digest(rows50) != FIFTY_DIGEST:
        raise RuntimeError('Actual complete source receipts differ from exact bound digest')
    source_identity = source.get('fresh_reader', {})
    if not source_identity.get('profile_id') or not source_identity.get('lineage_id'):
        raise RuntimeError('Actual source report must retain original Store profile/lineage IDs')
    profile_path = Path(source['user_dir']) / 'profiles_v3' / PROFILE
    if not profile_path.is_dir():
        raise RuntimeError('Original natural QA profile absent; no substitute is created')
    executable = args.exe.resolve(strict=True)
    if executable.suffix.lower() != '.exe' or 'godot' in executable.name.lower():
        parser.error('Use actual exported MAIN EXE, not an engine executable')
    # Import only after strict source gating. No use of --path, hidden mode,
    # affinity, quality overrides, profile cloning or external save manipulation.
    sys.path.insert(0, str(PROJECT / 'scripts_tools/v3'))
    import dev
    binding.verify_target(executable, dev.file_sha256)
    os.environ['LOW_ALTITUDE_DEV_HOME'] = str(dev.POLICY.root)
    stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S') + '_' + uuid.uuid4().hex[:8]
    label = 'normal-i3-' + which + '-' + stamp
    dev.POLICY.preflight('evidence', 64 * 1024 ** 2)
    evidence = dev.POLICY.path('evidence', label)
    evidence.mkdir(parents=True, exist_ok=False)
    output = evidence / (label + '.json')
    files = [executable, installed, Path(__file__).resolve(), source_path]
    if executable.with_suffix('.pck').is_file():
        files.append(executable.with_suffix('.pck'))
    files.extend(PROJECT / name for name in (
        'scripts/v3/twin_app.gd', 'scripts/v3/twin_session.gd',
        'scripts/v3/twin_test_world.gd', 'scripts/v3/gameplay/twin_opening_story.gd',
        'scripts/v3/gameplay/twin_i2_result_ledger.gd',
        'scripts/v3/gameplay/twin_campaign_session.gd',
        'scripts/v3/campaign/twin_campaign_mechanisms.gd',
        'scripts/v3/campaign/twin_campaign_encounter.gd',
        'scripts/v3/gameplay/twin_thermal_cargo_session.gd',
        'scripts/v3/gameplay/twin_thermal_cargo_participant.gd',
        'scripts/v3/gameplay/canal/canal_transport_physics/transport_pilot.gd',
        'scripts/v3/gameplay/canal/canal_transport_physics/cargo_custody.gd',
        'scripts/v3/gameplay/canal/canal_transport_physics/dock_lift.gd',
        'scripts/v3/qa/twin_normal_flight_pilot.gd',
        'scripts/v3/gameplay/twin_ability_rules.gd',
        'scripts/v3/gameplay/twin_weapon_session.gd', 'scripts/v2/flight_body.gd',
        'scripts/v3/core/twin_canal_save_gate.gd', 'scripts/v3/core/twin_world_store.gd',
        'data/v3/campaign/i3_actions.json', 'data/v3/campaign/layouts.json',
        'data/v3/campaign/physical_bindings.json', 'data/v3/campaign/bosses.json',
        'data/v3/regions.json'))

    files.extend(binding.evidence_files())

    def hashes():
        return {str(file): dev.file_sha256(file) for file in files}

    before = hashes()
    command = [str(executable), '--', '--qa-normal-i3', '--qa-profile=' + PROFILE,
               '--qa-normal-output=' + str(output.resolve()),
               '--qa-normal-seconds=' + str(args.seconds), '--qa-i3-segment=' + which,
               '--qa-i3-stop-after=' + args.stop_after]
    command.extend(binding.cli_args())
    (evidence / 'invocation.json').write_text(json.dumps({
        **binding.metadata,
        'command': command, 'working_directory': str(executable.parent),
        'source_report': str(source_path), 'source_report_sha256': report_sha,
        'source_receipts_sha256': receipts_sha, 'source_profile_directory': str(profile_path),
        'segment': which, 'stop_after': args.stop_after,
        'job_timeout_seconds': args.seconds + 15,
        'scope': 'Unflown candidate ordinary MAIN same natural profile. No '
                 'ActorPose/Director/environment/HP/clock fixture, direct scene start, '
                 'load_region, manual simulation, profile clone/reset/rollback. Original '
                 'G/heat5X, real2kg/PinJoint/DockLift/Custody outer route; independent '
                 'Boss radiator and original Host weapons/armour/two-phase victory. '
                 'No whole-game/fun/LAN/controller/performance acceptance.'
    }, ensure_ascii=False, indent=2), encoding='utf-8')
    dev.EVIDENCE = evidence
    original_root = dev.ROOT
    process = None
    execution_failure = None
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
            'note': 'The actual natural QA profile progresses normally and is not '
                    'hashed as an unchanged input, cloned, reset, restored or rolled back.'
        }, ensure_ascii=False, indent=2), encoding='utf-8')
    if not output.is_file():
        raise RuntimeError('Missing observer output is incomplete: ' + str(evidence))
    report = json.loads(output.read_text(encoding='utf-8-sig'))
    binding.validate_output(report)
    completed = report.get('status', {}).get('completed', [])
    if completed != expected[:len(completed)] or not count <= len(completed) <= end:
        raise RuntimeError('Observer reports another or illegal natural prefix')
    result_rows = {key: row for key, row in report.get('story_receipts', {}).items()
                   if isinstance(row, dict) and row.get('objective_id') in source_goals}
    if len(result_rows) != count or digest(result_rows) != receipts_sha:
        raise RuntimeError('Observer changed actual original source receipts')
    complete = bool(report.get('i3_segment_complete'))
    if complete and (completed != expected[:end]
                     or report.get('reached_stages') != list(STAGES[which])):
        raise RuntimeError('Complete requires all selected actual goals and observed stages')
    intentional = (bool(report.get('requested_stage_stopped'))
                   and args.stop_after != 'complete'
                   and args.stop_after in report.get('reached_stages', [])
                   and len(completed) >= MIN_GOALS[which][args.stop_after])
    cwd = report.get('runtime_cwd', '')
    own_folder = (bool(cwd) and os.path.normcase(os.path.realpath(cwd))
                  == os.path.normcase(os.path.realpath(executable.parent)))
    preservation = report.get('preservation', {})
    native = report.get('native_exit', {})
    print(json.dumps({'complete': complete, 'requested_stage_stopped': intentional,
        'segment': which, 'phase': report.get('phase'), 'seconds': report.get('seconds'),
        'completed': completed, 'failures': report.get('failures'),
        'engine_errors': report.get('engine_errors'), 'preservation': preservation,
        'native_exit': native, 'evidence': str(evidence), 'own_folder': own_folder,
        'actual_distance_m': report.get('actual_distance_m')}, ensure_ascii=False))
    if (report.get('profile') != PROFILE or report.get('segment') != which
            or report.get('source_report_sha256') != report_sha
            or report.get('source_receipts_sha256') != receipts_sha
            or report.get('source_profile_id') != source_identity['profile_id']
            or report.get('source_lineage_id') != source_identity['lineage_id']
            or report.get('requested_stage') != args.stop_after):
        raise RuntimeError('Observer/source/segment/stage identity mismatch')
    if (execution_failure is not None or before != after or not own_folder
            or report.get('failures') or report.get('engine_errors')
            or not preservation.get('original_prefix_preserved')
            or not preservation.get('current_SaveGate_completed')
            or not preservation.get('fresh_Story_matches_live')
            or native.get('through') != 'session._quit'
            or not native.get('observed_scene_exit') or native.get('watchdog_failed')
            or not native.get('audio', {}).get('ready') or not (complete or intentional)):
        raise SystemExit(1)


if __name__ == '__main__':
    main()
