"""Run exported MAIN on the same natural I2Boss42 profile, to F2 investigation46.

AUTHORING ONLY: both source constants intentionally remain unbound. Root must
bind a genuinely successful I2Boss42 report and its exact 42 receipt digest.
No report progress is imported; no profile is written, reset, cloned or rolled
back by this runner. Only the exported game's ordinary gameplay writes saves.
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
SOURCE_REPORT = 'artifacts/v3/normal-i2-boss-20261021_052256_37608812/normal-i2-boss-20261021_052256_37608812.json'
SOURCE_REPORT_SHA256 = '8a2e036263902d7298e2437a49936b4f629b15c000527d7e4fe57c608ced41b2'
FORTYTWO_DIGEST = '4f6c3eeb673cd61239c6ddc6365af60144c3ced07e8bacddcd6d3d4b6ed383c3'
STAGES = ('records', 'archive', 'light', 'complete')
STAGE_COUNTS = {'records': 43, 'archive': 44, 'light': 45, 'complete': 46}


def receipt_digest(rows):
    return hashlib.sha256(json.dumps(rows, ensure_ascii=False, sort_keys=True,
                                     separators=(',', ':')).encode('utf-8')).hexdigest()


def main():
    global PROFILE, SOURCE_REPORT, SOURCE_REPORT_SHA256, FORTYTWO_DIGEST
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe', type=Path,
                        default=PROJECT / 'build/V3Development/LowAltitudeTwinPulse-Dev.exe')
    parser.add_argument('--seconds', type=int, default=600, choices=range(60, 601),
                        metavar='60..600')
    parser.add_argument('--i2-boss-report', type=Path, default=None,
                        help='Exact Root-bound successful natural I2Boss42 report')
    parser.add_argument('--stop-after', choices=STAGES, default='complete',
                        help='Intermediate stops preserve a legal incomplete action')
    add_binding_arguments(parser)
    args = parser.parse_args()
    binding = load_binding(args.source_binding, args.source_binding_sha256,
                           project=Path(__file__).resolve().parents[2],
                           entry='normal-f2', segment='')
    PROFILE = binding.values['SOURCE_PROFILE']
    SOURCE_REPORT = binding.values['SOURCE_REPORT']
    SOURCE_REPORT_SHA256 = binding.values['SOURCE_REPORT_SHA256']
    FORTYTWO_DIGEST = binding.values['FORTYTWO_DIGEST']
    if args.i2_boss_report is None:
        args.i2_boss_report = binding.report_path
    elif args.i2_boss_report.resolve(strict=True) != binding.report_path:
        raise RuntimeError('Explicit predecessor must equal strict binding source')
    # Fail before EXE resolution, profile lookup, evidence creation or execution.
    if (not re.fullmatch(r'[0-9a-f]{64}', SOURCE_REPORT_SHA256)
            or not re.fullmatch(r'[0-9a-f]{64}', FORTYTWO_DIGEST)
            or not SOURCE_REPORT):
        raise RuntimeError('UNBOUND: Root must bind actual successful natural I2Boss42 '
                           'report path/SHA and 42 receipts in BOTH Node and runner')
    installed = PROJECT / 'scripts/v3/qa/twin_normal_f2_qa.gd'
    if not installed.is_file():
        raise RuntimeError('Root must promote the staged F2 Node/CLI and export first')
    node_text = installed.read_text(encoding='utf-8-sig')

    def bound_constant(name):
        if name in binding.values:
            return binding.values[name]
        match = re.search(r'^const ' + re.escape(name) + r' := "([0-9a-f]{64})"$',
                          node_text, re.M)
        if not match:
            raise RuntimeError('Actual successful I2Boss42 source is not bound: ' + name)
        return match.group(1)

    def goal_constant(name):
        match = re.search(r'^const ' + re.escape(name) + r' := (\[.*\])$',
                          node_text, re.M)
        if not match:
            raise RuntimeError('Exact original goal order missing: ' + name)
        return json.loads(match.group(1))

    source_sha = bound_constant('SOURCE_REPORT_SHA256')
    receipts_sha = bound_constant('FORTYTWO_DIGEST')
    if source_sha != SOURCE_REPORT_SHA256 or receipts_sha != FORTYTWO_DIGEST:
        raise RuntimeError('Node and runner must be bound to the SAME actual evidence')
    source_goals = goal_constant('SOURCE_GOALS')
    expected = goal_constant('EXPECTED')
    if (len(source_goals) != 42 or len(expected) != 46
            or expected[:42] != source_goals
            or expected[42:] != ['F2:mirror_evidence:records',
                                 'F2:mirror_evidence:archive',
                                 'F2:mirror_evidence:light',
                                 'F2:mirror_evidence:decision']):
        raise RuntimeError('Only exact original 42-to-46 investigation is supported')
    source_path = (args.i2_boss_report or PROJECT / SOURCE_REPORT).resolve(strict=True)
    if hashlib.sha256(source_path.read_bytes()).hexdigest() != source_sha:
        raise RuntimeError('Actual I2Boss report differs from Root-bound SHA')
    source = json.loads(source_path.read_text(encoding='utf-8-sig'))
    goals = source.get('status', {}).get('completed', [])
    source_exit = source.get('native_exit', {})
    source_preservation = source.get('preservation', {})
    if (not source.get('i2_boss_segment_complete') or not source.get('complete')
            or source.get('failures') or source.get('engine_errors')
            or source.get('profile') != PROFILE or goals != source_goals
            or source.get('reached_stages') != ['plan', 'engage', 'half', 'stop', 'complete']
            or source.get('status', {}).get('region') != 'I2'
            or not source_preservation.get('original_prefix_preserved')
            or not source_preservation.get('current_SaveGate_completed')
            or not source_preservation.get('fresh_Story_matches_live')
            or source_exit.get('through') != 'session._quit'
            or not source_exit.get('observed_scene_exit')
            or source_exit.get('watchdog_failed')
            or not source_exit.get('audio', {}).get('ready')):
        raise RuntimeError('Require actual natural I2Boss42 and original durable native exit')
    rows = {key: value for key, value in source.get('story_receipts', {}).items()
            if value.get('objective_id') in source_goals}
    if len(rows) != 42 or receipt_digest(rows) != receipts_sha:
        raise RuntimeError('Actual forty-two source receipts differ')
    parent_rows = {key: value for key, value in rows.items()
                   if value.get('objective_id') in source_goals[:38]}
    if (not re.fullmatch(r'[0-9a-f]{64}', source.get('source_receipts_sha256', ''))
            or receipt_digest(parent_rows) != source['source_receipts_sha256']):
        raise RuntimeError('I2Boss report must retain its actual original Canal38 source')
    source_reader = source.get('fresh_reader', {})
    source_world = source_reader.get('world', {})
    source_personal = source_reader.get('personal', {})
    source_completed = source_world.get('actions', {}).get('opening', {}).get('completed')
    if (source_world.get('region_id') != 'I2' or source_world.get('branch_id') != 'main'
            or source_completed != source_goals
            or source_world.get('completed_objectives') != source_goals
            or not source_world.get('flags', {}).get('campaign_boss:I2')
            or not source_world.get('flags', {}).get('I2:region_route_open')
            or source_personal.get('discoveries', []).count('boss:I2:twin_pump_guardian') != 1
            or source_personal.get('discoveries', []).count('I2:operation_record') != 1):
        raise RuntimeError('Source report must contain original durable complete I2 action')
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
    evidence = dev.POLICY.path('evidence', ('normal-f2-' + stamp))
    evidence.mkdir(parents=True, exist_ok=False)
    output = evidence / ('normal-f2-' + stamp + '.json')
    files = [executable, Path(__file__).resolve(), source_path]
    if executable.with_suffix('.pck').is_file():
        files.append(executable.with_suffix('.pck'))
    names = [
        'scripts/v3/qa/twin_normal_f2_qa.gd', 'scripts/v3/qa/twin_normal_flight_pilot.gd',
        'scripts/v3/twin_app.gd', 'scripts/v3/twin_session.gd',
        'scripts/v3/twin_test_world.gd', 'scripts/v3/twin_interface.gd',
        'scripts/v3/gameplay/twin_opening_story.gd',
        'scripts/v3/gameplay/actions/twin_action_director.gd',
        'scripts/v3/gameplay/twin_campaign_session.gd',
        'scripts/v3/gameplay/twin_campaign_choices.gd',
        'scripts/v3/gameplay/twin_i2_result_ledger.gd',
        'scripts/v3/gameplay/twin_ability_rules.gd',
        'scripts/v3/campaign/twin_campaign_catalog.gd',
        'scripts/v3/campaign/twin_campaign_mechanisms.gd',
        'scripts/v3/campaign/twin_campaign_late_mechanisms.gd',
        'scripts/v3/ui/twin_campaign_choice_panel.gd',
        'scripts/v3/world/twin_region_catalog.gd',
        'scripts/v3/gameplay/canal/canal_transport_physics/transport_pilot.gd',
        'scripts/v3/core/twin_canal_save_gate.gd',
        'scripts/v3/core/twin_world_store.gd',
        'data/v3/campaign/f2_actions.json', 'data/v3/campaign/layouts.json',
        'data/v3/campaign/physical_bindings.json', 'data/v3/campaign/choices.json',
        'data/v3/campaign/index.json', 'data/v3/regions.json',
    ]
    files.extend(PROJECT / name for name in names)

    files.extend(binding.evidence_files())

    def hashes():
        return {str(path): dev.file_sha256(path) for path in files}

    before = hashes()
    command = [str(executable), '--', '--qa-normal-f2',
               '--qa-profile=' + PROFILE, '--qa-normal-output=' + str(output.resolve()),
               '--qa-normal-seconds=' + str(args.seconds),
               '--qa-f2-stop-after=' + args.stop_after]
    command.extend(binding.cli_args())
    (evidence / 'invocation.json').write_text(json.dumps({
        **binding.metadata,
        'command': command, 'profile': PROFILE, 'output': str(output),
        'working_directory': str(executable.parent), 'stop_after': args.stop_after,
        'requested_seconds': args.seconds, 'job_timeout_seconds': args.seconds + 15,
        'source_profile_directory': str(profile_path), 'source_report_sha256': source_sha,
        'source_forty_two_receipts_sha256': receipts_sha,
        'scope': 'Actual exported MAIN I2Boss42-to-F2 investigation46 only. Original '
                 'menu/spawn/M travel, continuous Pilot/Flight, near/LOS G records '
                 'and NPC, real 4/Tab/F mirror, original two physical ray segments, '
                 'two actual cost-panel CheckBoxes and explicit publish_context '
                 'Button through original branch/Consensus/Store, SaveGate/fresh '
                 'reader/native quit. No F2 Boss, script/scene/pose/mechanism/HP/'
                 'clock/collision/flags/proof override, clone/rollback or report '
                 'progress import. Intermediate stops are incomplete.'
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
            'note': 'Source hashes identify the worktree; EXE/PCK hashes identify '
                    'the executed artifact. Original profile is never reset.'
        }, ensure_ascii=False, indent=2), encoding='utf-8')
    if not output.is_file():
        print(json.dumps({'complete': False, 'evidence': str(evidence),
                          'error': 'No observer report; timeout/CLI/import failure '
                                   'cannot count as a successful stage.'}, ensure_ascii=False))
        raise SystemExit(1)
    report = json.loads(output.read_text(encoding='utf-8-sig'))
    binding.validate_output(report)
    runtime_cwd = report.get('runtime_cwd', '')
    own_folder = (bool(runtime_cwd)
                  and os.path.normcase(os.path.realpath(runtime_cwd))
                  == os.path.normcase(os.path.realpath(executable.parent)))
    completed = report.get('status', {}).get('completed', [])
    if completed != expected[:len(completed)] or not 42 <= len(completed) <= 46:
        raise RuntimeError('Observer reports a different or illegal natural investigation prefix')
    report_rows = {key: value for key, value in report.get('story_receipts', {}).items()
                   if value.get('objective_id') in source_goals}
    if len(report_rows) != 42 or receipt_digest(report_rows) != receipts_sha:
        raise RuntimeError('Observer changed actual source42 receipts')
    complete = bool(report.get('f2_segment_complete'))
    status = report.get('status', {})
    if status.get('boss_active') or report.get('stats', {}).get('shots'):
        raise RuntimeError('F2 investigation must not begin Boss combat or fire')
    if complete and (completed != expected or report.get('reached_stages') != list(STAGES)):
        raise RuntimeError('Complete requires all four actual natural goals and stages')
    intentional_stage = (bool(report.get('requested_stage_stopped'))
                         and args.stop_after != 'complete'
                         and args.stop_after in report.get('reached_stages', [])
                         and len(completed) >= STAGE_COUNTS[args.stop_after])
    preservation = report.get('preservation', {})
    native_exit = report.get('native_exit', {})
    saved = report.get('fresh_reader', {})
    if saved.get('profile_id') != source_reader.get('profile_id') or saved.get('lineage_id') != source_reader.get('lineage_id'):
        raise RuntimeError('Original profile and lineage must remain unchanged')
    if complete:
        environment = saved.get('world', {}).get('environment', {})
        mechanisms = environment.get('campaign_F2', {}).get('mechanisms', {})
        if (not mechanisms.get('readings', {}).get('F2:record_low')
                or not mechanisms.get('readings', {}).get('F2:record_high')
                or not mechanisms.get('histories', {}).get('F2:clock_light_path')
                or mechanisms.get('facts', {}).get('F2:clock_light_path') != 'manual_mirror'
                or saved.get('world', {}).get('actions', {}).get('opening', {}).get('choices', {}).get('F2:mirror_evidence:decision') != 'publish_context'):
            raise RuntimeError('Actual original reading, reflection and choice proof missing')
        new_choice = 'F2:mirror_evidence:decision' not in report.get('initial_completed', [])
        if new_choice:
            gui = report.get('actual_cost_panel_actions', [])
            checks = [row for row in gui if row.get('kind') == 'actual_CheckBox']
            submits = [row for row in gui if row.get('kind') == 'actual_Button_pressed']
            if (len(checks) != 2 or {row.get('option') for row in checks} != {'publish_raw', 'publish_context'}
                    or not all(row.get('host_acknowledged') and row.get('is_checked')
                               and row.get('visible_benefit_cost') for row in checks)
                    or len(submits) != 1 or submits[0].get('option') != 'publish_context'):
                raise RuntimeError('New choice must use both actual CheckBoxes and one actual proposal Button')
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

