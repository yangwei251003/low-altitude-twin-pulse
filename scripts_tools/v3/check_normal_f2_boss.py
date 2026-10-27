"""Run exported MAIN from the same natural F2 investigation46 to Mirrorwing50.

AUTHORING ONLY. Source report/SHA and exact46 receipts are intentionally empty.
Root must bind the real successful F2 investigation report in Node AND runner.
Reports are read-only provenance; this runner never imports or rewrites progress.
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
SOURCE_REPORT = 'artifacts/v3/normal-f2-20261021_053202_afd20a38/normal-f2-20261021_053202_afd20a38.json'
SOURCE_REPORT_SHA256 = '7181560a1211c8935fabc85c61052ef16a5ff6f803faacdb7f279e0b067a3a5f'
FORTYSIX_DIGEST = '2db87ac19846e1909b90580eede8243a430956dbddadcdca9077d331f66bb5d6'
STAGES = ('plan', 'engage', 'half', 'stop', 'complete')
STAGE_COUNTS = {'plan': 47, 'engage': 48, 'half': 48, 'stop': 49, 'complete': 50}


def receipt_digest(rows):
    return hashlib.sha256(json.dumps(rows, ensure_ascii=False, sort_keys=True,
                                     separators=(',', ':')).encode('utf-8')).hexdigest()


def main():
    global PROFILE, SOURCE_REPORT, SOURCE_REPORT_SHA256, FORTYSIX_DIGEST
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe', type=Path,
                        default=PROJECT / 'build/V3Development/LowAltitudeTwinPulse-Dev.exe')
    parser.add_argument('--seconds', type=int, default=600, choices=range(60, 601),
                        metavar='60..600')
    parser.add_argument('--f2-report', type=Path, default=None,
                        help='Exact Root-bound successful natural investigation46 report')
    parser.add_argument('--stop-after', choices=STAGES, default='complete',
                        help='Stops before complete preserve explicitly incomplete goals/combat')
    add_binding_arguments(parser)
    args = parser.parse_args()
    binding = load_binding(args.source_binding, args.source_binding_sha256,
                           project=Path(__file__).resolve().parents[2],
                           entry='normal-f2-boss', segment='')
    PROFILE = binding.values['SOURCE_PROFILE']
    SOURCE_REPORT = binding.values['SOURCE_REPORT']
    SOURCE_REPORT_SHA256 = binding.values['SOURCE_REPORT_SHA256']
    FORTYSIX_DIGEST = binding.values['FORTYSIX_DIGEST']
    if args.f2_report is None:
        args.f2_report = binding.report_path
    elif args.f2_report.resolve(strict=True) != binding.report_path:
        raise RuntimeError('Explicit predecessor must equal strict binding source')
    # Fail before executable resolution, profile lookup or process/evidence creation.
    if (not re.fullmatch(r'[0-9a-f]{64}', SOURCE_REPORT_SHA256)
            or not re.fullmatch(r'[0-9a-f]{64}', FORTYSIX_DIGEST)
            or not SOURCE_REPORT):
        raise RuntimeError('UNBOUND: Root must bind actual successful natural F2 investigation46 '
                           'report path/SHA and 46 receipts in BOTH Node and runner')
    installed = PROJECT / 'scripts/v3/qa/twin_normal_f2_boss_qa.gd'
    if not installed.is_file():
        raise RuntimeError('Root must promote the staged F2 Boss Node/CLI and export first')
    node_text = installed.read_text(encoding='utf-8-sig')

    def bound_constant(name):
        if name in binding.values:
            return binding.values[name]
        match = re.search(r'^const ' + re.escape(name) + r' := "([0-9a-f]{64})"$',
                          node_text, re.M)
        if not match:
            raise RuntimeError('Actual source46 evidence is not bound: ' + name)
        return match.group(1)

    def goal_constant(name):
        match = re.search(r'^const ' + re.escape(name) + r' := (\[.*\])$', node_text, re.M)
        if not match:
            raise RuntimeError('Exact original goal order missing: ' + name)
        return json.loads(match.group(1))

    source_sha = bound_constant('SOURCE_REPORT_SHA256')
    receipts_sha = bound_constant('FORTYSIX_DIGEST')
    if source_sha != SOURCE_REPORT_SHA256 or receipts_sha != FORTYSIX_DIGEST:
        raise RuntimeError('Node and runner must bind the SAME actual evidence')
    source_goals = goal_constant('SOURCE_GOALS')
    expected = goal_constant('EXPECTED')
    if (len(source_goals) != 46 or len(expected) != 50 or expected[:46] != source_goals
            or expected[46:] != ['F2:mirrorwing_warden:plan',
                                 'F2:mirrorwing_warden:engage',
                                 'F2:mirrorwing_warden:stop',
                                 'F2:mirrorwing_warden:record']):
        raise RuntimeError('Only exact original46-to50 F2 Boss action is supported')
    source_path = (args.f2_report or PROJECT / SOURCE_REPORT).resolve(strict=True)
    if hashlib.sha256(source_path.read_bytes()).hexdigest() != source_sha:
        raise RuntimeError('Actual F2 investigation report differs from Root-bound SHA')
    source = json.loads(source_path.read_text(encoding='utf-8-sig'))
    source_exit = source.get('native_exit', {})
    source_preservation = source.get('preservation', {})
    if (not source.get('f2_segment_complete') or not source.get('complete')
            or source.get('failures') or source.get('engine_errors')
            or source.get('profile') != PROFILE
            or source.get('status', {}).get('completed') != source_goals
            or source.get('status', {}).get('region') != 'F2'
            or source.get('status', {}).get('boss_active')
            or source.get('stats', {}).get('shots')
            or source.get('reached_stages') != ['records', 'archive', 'light', 'complete']
            or not source_preservation.get('original_prefix_preserved')
            or not source_preservation.get('current_SaveGate_completed')
            or not source_preservation.get('fresh_Story_matches_live')
            or source_exit.get('through') != 'session._quit'
            or not source_exit.get('observed_scene_exit') or source_exit.get('watchdog_failed')
            or not source_exit.get('audio', {}).get('ready')):
        raise RuntimeError('Require actual successful investigation46 and original durable exit')
    rows = {key: value for key, value in source.get('story_receipts', {}).items()
            if value.get('objective_id') in source_goals}
    if len(rows) != 46 or receipt_digest(rows) != receipts_sha:
        raise RuntimeError('Actual forty-six source receipts differ')
    parent_rows = {key: value for key, value in rows.items()
                   if value.get('objective_id') in source_goals[:42]}
    if (not re.fullmatch(r'[0-9a-f]{64}', source.get('source_receipts_sha256', ''))
            or receipt_digest(parent_rows) != source['source_receipts_sha256']):
        raise RuntimeError('Investigation report must retain original actual I2Boss42 source')
    source_reader = source.get('fresh_reader', {})
    world = source_reader.get('world', {})
    mechanisms = world.get('environment', {}).get('campaign_F2', {}).get('mechanisms', {})
    story = world.get('actions', {}).get('opening', {})
    if (world.get('region_id') != 'F2' or world.get('branch_id') != 'main'
            or story.get('completed') != source_goals
            or world.get('completed_objectives') != source_goals
            or not mechanisms.get('readings', {}).get('F2:record_low')
            or not mechanisms.get('readings', {}).get('F2:record_high')
            or not mechanisms.get('histories', {}).get('F2:clock_light_path')
            or story.get('choices', {}).get('F2:mirror_evidence:decision') != 'publish_context'
            or world.get('flags', {}).get('campaign_boss:F2')):
        raise RuntimeError('Source requires actual durable original records/reflection/choice, no F2 victory')
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
    evidence = dev.POLICY.path('evidence', ('normal-f2-boss-' + stamp))
    evidence.mkdir(parents=True, exist_ok=False)
    output = evidence / ('normal-f2-boss-' + stamp + '.json')
    files = [executable, Path(__file__).resolve(), source_path]
    if executable.with_suffix('.pck').is_file():
        files.append(executable.with_suffix('.pck'))
    names = [
        'scripts/v3/qa/twin_normal_f2_boss_qa.gd', 'scripts/v3/qa/twin_normal_flight_pilot.gd',
        'scripts/v3/twin_app.gd', 'scripts/v3/twin_session.gd',
        'scripts/v3/twin_test_world.gd', 'scripts/v3/twin_interface.gd',
        'scripts/v3/gameplay/twin_opening_story.gd',
        'scripts/v3/gameplay/actions/twin_action_director.gd',
        'scripts/v3/gameplay/twin_campaign_session.gd',
        'scripts/v3/gameplay/twin_i2_result_ledger.gd',
        'scripts/v3/gameplay/twin_ability_rules.gd',
        'scripts/v3/campaign/twin_campaign_catalog.gd',
        'scripts/v3/campaign/twin_campaign_encounter.gd',
        'scripts/v3/campaign/twin_campaign_mechanisms.gd',
        'scripts/v3/campaign/twin_campaign_late_mechanisms.gd',
        'scripts/v3/world/twin_campaign_arena.gd',
        'scripts/v3/gameplay/canal/canal_transport_physics/transport_pilot.gd',
        'scripts/v3/core/twin_canal_save_gate.gd', 'scripts/v3/core/twin_world_store.gd',
        'data/v3/campaign/f2_actions.json', 'data/v3/campaign/bosses.json',
        'data/v3/campaign/layouts.json', 'data/v3/campaign/physical_bindings.json',
        'data/v3/campaign/choices.json', 'data/v3/campaign/index.json',
        'data/v3/regions.json',
    ]
    files.extend(PROJECT / name for name in names)

    files.extend(binding.evidence_files())

    def hashes():
        return {str(path): dev.file_sha256(path) for path in files}

    before = hashes()
    command = [str(executable), '--', '--qa-normal-f2-boss',
               '--qa-profile=' + PROFILE, '--qa-normal-output=' + str(output.resolve()),
               '--qa-normal-seconds=' + str(args.seconds),
               '--qa-f2-boss-stop-after=' + args.stop_after]
    command.extend(binding.cli_args())
    (evidence / 'invocation.json').write_text(json.dumps({
        **binding.metadata,
        'command': command, 'profile': PROFILE, 'output': str(output),
        'working_directory': str(executable.parent), 'stop_after': args.stop_after,
        'requested_seconds': args.seconds, 'job_timeout_seconds': args.seconds + 15,
        'source_profile_directory': str(profile_path), 'source_report_sha256': source_sha,
        'source_forty_six_receipts_sha256': receipts_sha,
        'scope': 'Exported MAIN natural46-to50 F2 Boss only. Original menu/spawn/M, '
                 'Pilot swept flight/G briefing/real arena entry, separate sustained '
                 '4/Tab/F reveal emitter and actual core shadow ray, real warning-driven '
                 'lateral movement, held original flight_fire/Host weapon and recovery '
                 'gates, real reversed phase2 and HP chains, original Store victory/'
                 'unique reward/post-Boss G record, SaveGate/fresh reader/native quit. '
                 'No scene/script override, pose/HP/clock/mechanism/environment/Story '
                 'fixture, direct fire/encounter advance, clone/rollback/report progress '
                 'import. Stops before complete remain explicitly incomplete.'
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
                    'the actual artifact. Original profile is never reset.'
        }, ensure_ascii=False, indent=2), encoding='utf-8')
    if not output.is_file():
        print(json.dumps({'complete': False, 'evidence': str(evidence),
                          'error': 'No observer report; import/CLI/timeout failure cannot '
                                   'count as successful stage.'}, ensure_ascii=False))
        raise SystemExit(1)
    report = json.loads(output.read_text(encoding='utf-8-sig'))
    binding.validate_output(report)
    runtime_cwd = report.get('runtime_cwd', '')
    own_folder = (bool(runtime_cwd)
                  and os.path.normcase(os.path.realpath(runtime_cwd))
                  == os.path.normcase(os.path.realpath(executable.parent)))
    completed = report.get('status', {}).get('completed', [])
    if completed != expected[:len(completed)] or not 46 <= len(completed) <= 50:
        raise RuntimeError('Observer reports an illegal natural Boss prefix')
    report_rows = {key: value for key, value in report.get('story_receipts', {}).items()
                   if value.get('objective_id') in source_goals}
    if len(report_rows) != 46 or receipt_digest(report_rows) != receipts_sha:
        raise RuntimeError('Observer changed actual source46 receipts')
    saved = report.get('fresh_reader', {})
    if saved.get('profile_id') != source_reader.get('profile_id') or saved.get('lineage_id') != source_reader.get('lineage_id'):
        raise RuntimeError('Original profile identity and lineage must remain unchanged')
    complete = bool(report.get('f2_boss_segment_complete'))
    if complete and (completed != expected or report.get('reached_stages') != list(STAGES)):
        raise RuntimeError('Complete requires every actual original Boss goal and all stages')
    intentional_stage = (bool(report.get('requested_stage_stopped'))
                         and args.stop_after != 'complete'
                         and args.stop_after in report.get('reached_stages', [])
                         and len(completed) >= STAGE_COUNTS[args.stop_after])
    if complete:
        disk_world = saved.get('world', {})
        disk_state = disk_world.get('environment', {}).get('campaign_F2', {}).get('encounter', {}).get('state', {})
        findings = saved.get('personal', {}).get('discoveries', [])
        if (report.get('status', {}).get('boss_active') or not disk_state.get('completed')
                or disk_state.get('phase') != 2 or disk_state.get('core_hp_milli') != 0
                or any(disk_state.get('parts', {}).get(key) != 0
                       for key in ('true_left_wing', 'true_right_wing'))
                or not disk_world.get('flags', {}).get('campaign_boss:F2')
                or not disk_world.get('flags', {}).get('F2:region_route_open')
                or findings.count('boss:F2:mirrorwing_warden') != 1
                or findings.count('F2:operation_record') != 1):
            raise RuntimeError('Original durable full victory/reward/record is missing')
        if not report.get('inherited_committed_victory'):
            if (not report.get('damage_evidence', {}).get('ok')
                    or not report.get('phase_two_observed')
                    or not report.get('actual_damage_samples')
                    or not report.get('stats', {}).get('shots')):
                raise RuntimeError('New victory requires actual weapon/phase2/damage evidence')
            current_hp = report.get('battle_baseline', {}).get('core_hp_milli')
            for row in report['actual_damage_samples']:
                if (row.get('damage_phase') not in (1, 2)
                        or row.get('before', 0) <= row.get('after', -1)
                        or row.get('after', -1) < 0
                        or row.get('drop') != row['before'] - row['after']
                        or row.get('shots_after', 0) <= row.get('shots_before', 0)):
                    raise RuntimeError('Actual HP drop must follow exact observed before/after and shot counters')
                if row['part'] == 'core':
                    if row['before'] != current_hp:
                        raise RuntimeError('Actual core HP chain has an unobserved jump')
                    current_hp = row['after']
            if current_hp != 0:
                raise RuntimeError('Actual core damage chain must finish exactly at zero')
            baseline_phase = report.get('battle_baseline', {}).get('phase')
            if baseline_phase == 1:
                phase2 = [row for row in report.get('actual_part_visits', [])
                          if row.get('phase') == 2]
                if not phase2 or phase2[0].get('part') != 'true_right_wing':
                    raise RuntimeError('Actual phase2 must begin with the reversed right wing')
            reveal = [row for row in report.get('actual_reveal_observations', [])
                      if row.get('kind') == 'powered_actual_Boss_ray']
            if not reveal or not any(row.get('ray', {}).get('entity_id') == 'campaign:F2:core'
                                     and row.get('environment', {}).get('true_body_revealed')
                                     and row.get('environment', {}).get('shadow_verified')
                                     for row in reveal):
                raise RuntimeError('Puzzle clock history cannot replace the actual separate Boss reveal ray')
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
        'actual_shots': report.get('stats', {}).get('shots'),
        'phase_two_observed': report.get('phase_two_observed'),
        'inherited_committed_victory': report.get('inherited_committed_victory'),
        'damage_evidence': report.get('damage_evidence'),
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
            or not native_exit.get('observed_scene_exit') or native_exit.get('watchdog_failed')
            or not native_exit.get('audio', {}).get('ready')
            or not (complete or intentional_stage)):
        raise SystemExit(1)


if __name__ == '__main__':
    main()

