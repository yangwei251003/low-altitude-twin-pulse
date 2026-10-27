"""Exported MAIN same natural F3 record66 -> I4 decision75, authoring only.

All three source bindings intentionally empty. Abort before project/profile/
evidence/process I/O until Root binds actual successful F3 record66 evidence.
Report provenance is read-only; never import/clone/rollback game progress.
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
SOURCE_REPORT = 'artifacts/v3/normal-f3-20261021_060621_8963cc4f/normal-f3-20261021_060621_8963cc4f.json'
SOURCE_REPORT_SHA256 = 'f4e6c572c935b3672c9cf9e8b373d081962406127bdac6e5c15f1ed0d069cbe4'
SIXTYSIX_DIGEST = '9efe5440fcb86e4931f3247fbd059bdfe20ef089b853914f43a7a47a9cc67421'
STAGES = ('brief', 'archive', 'witness', 'shelter', 'isolate',
          'plan', 'engage', 'half', 'stop', 'complete')
STAGE_COUNTS = dict(zip(STAGES, (67, 68, 69, 70, 71, 72, 73, 73, 74, 75)))


def receipt_digest(rows):
    return hashlib.sha256(json.dumps(rows, ensure_ascii=False, sort_keys=True,
                                     separators=(',', ':')).encode('utf-8')).hexdigest()


def main():
    global PROFILE, SOURCE_REPORT, SOURCE_REPORT_SHA256, SIXTYSIX_DIGEST
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe', type=Path,
                        default=None)
    parser.add_argument('--seconds', type=int, default=900, choices=range(60, 901),
                        metavar='60..900')
    parser.add_argument('--f3-report', type=Path, default=None,
                        help='Exact Root-bound successful natural F3 record66 report')
    parser.add_argument('--stop-after', choices=STAGES, default='complete',
                        help='Stops before complete preserve explicitly incomplete goals/combat')
    add_binding_arguments(parser)
    args = parser.parse_args()
    binding = load_binding(args.source_binding, args.source_binding_sha256,
                           project=Path(__file__).resolve().parents[2],
                           entry='normal-i4', segment='')
    PROFILE = binding.values['SOURCE_PROFILE']
    SOURCE_REPORT = binding.values['SOURCE_REPORT']
    SOURCE_REPORT_SHA256 = binding.values['SOURCE_REPORT_SHA256']
    SIXTYSIX_DIGEST = binding.values['SIXTYSIX_DIGEST']
    if args.f3_report is None:
        args.f3_report = binding.report_path
    elif args.f3_report.resolve(strict=True) != binding.report_path:
        raise RuntimeError('Explicit predecessor must equal strict binding source')
    # All actual bindings are checked before project/profile/evidence I/O.
    if (not re.fullmatch(r'[0-9a-f]{64}', SOURCE_REPORT_SHA256)
            or not re.fullmatch(r'[0-9a-f]{64}', SIXTYSIX_DIGEST)
            or not SOURCE_REPORT):
        raise RuntimeError('UNBOUND: Root must bind actual successful F3 record66 '
                           'report path/SHA and exact66 receipts in BOTH Node and runner')
    project = next(parent for parent in Path(__file__).resolve().parents
                   if (parent / 'project.godot').is_file()
                   and (parent / 'scripts_tools/v3/dev.py').is_file())
    sys.path.insert(0, str(project / 'scripts_tools/v3'))
    import dev
    installed = project / 'scripts/v3/qa/twin_normal_i4_qa.gd'
    if not installed.is_file():
        raise RuntimeError('Root must promote staged I4 Node/CLI and export first')
    node_text = installed.read_text(encoding='utf-8-sig')

    def bound_constant(name, digest=True):
        if name in binding.values:
            return binding.values[name]
        match = re.search(r'^const ' + re.escape(name) + r' := "([^"\n]*)"$',
                          node_text, re.M)
        if not match or (digest and not re.fullmatch(r'[0-9a-f]{64}', match.group(1))):
            raise RuntimeError('Actual source66 evidence is not bound: ' + name)
        return match.group(1)

    def goal_constant(name):
        match = re.search(r'^const ' + re.escape(name) + r' := (\[.*\])$', node_text, re.M)
        if not match:
            raise RuntimeError('Exact original goal order missing: ' + name)
        return json.loads(match.group(1))

    source_sha = bound_constant('SOURCE_REPORT_SHA256')
    receipts_sha = bound_constant('SIXTYSIX_DIGEST')
    if (source_sha != SOURCE_REPORT_SHA256 or receipts_sha != SIXTYSIX_DIGEST
            or bound_constant('SOURCE_REPORT', False) != SOURCE_REPORT):
        raise RuntimeError('Node and runner must bind SAME actual66 evidence')
    source_goals, expected = goal_constant('SOURCE_GOALS'), goal_constant('EXPECTED')
    tail = ['I4:array_witness:' + name for name in
            ('brief', 'archive', 'witness', 'shelter', 'isolate')]
    tail += ['I4:prism_array:' + name for name in ('plan', 'engage', 'stop', 'decision')]
    if len(source_goals) != 66 or len(expected) != 75 or expected[:66] != source_goals or expected[66:] != tail:
        raise RuntimeError('Only exact original66-to75 I4 actions supported')
    source_path = (args.f3_report or project / SOURCE_REPORT).resolve(strict=True)
    if hashlib.sha256(source_path.read_bytes()).hexdigest() != source_sha:
        raise RuntimeError('Actual F3 record66 report differs from Root-bound SHA')
    source = json.loads(source_path.read_text(encoding='utf-8-sig'))
    source_exit, source_preservation = source.get('native_exit', {}), source.get('preservation', {})
    source_reader = source.get('fresh_reader', {})
    world = source_reader.get('world', {})
    story = world.get('actions', {}).get('opening', {})
    prior = world.get('environment', {}).get('campaign_F3', {})
    prior_boss = prior.get('encounter', {}).get('state', {})
    nutrient = prior.get('mechanisms', {}).get('histories', {}).get('F3:nutrient_route_proof', {})
    if (not source.get('complete') or source.get('failures') or source.get('engine_errors')
            or source.get('profile') != PROFILE
            or source.get('status', {}).get('completed') != source_goals
            or source.get('status', {}).get('region') != 'F3'
            or source.get('status', {}).get('boss_active')
            or not source_preservation.get('original_prefix_preserved')
            or not source_preservation.get('current_SaveGate_completed')
            or not source_preservation.get('fresh_Story_matches_live')
            or source_exit.get('through') != 'session._quit'
            or not source_exit.get('observed_scene_exit') or source_exit.get('watchdog_failed')
            or not source_exit.get('audio', {}).get('ready')
            or world.get('region_id') != 'F3' or world.get('branch_id') != 'main'
            or story.get('completed') != source_goals
            or world.get('completed_objectives') != source_goals
            or not world.get('flags', {}).get('F3:region_route_open')
            or not world.get('flags', {}).get('campaign_boss:F3')
            or not prior_boss.get('completed') or prior_boss.get('phase') != 2
            or prior_boss.get('core_hp_milli') != 0 or nutrient.get('branch_id') != 'main'
            or world.get('flags', {}).get('campaign_boss:I4')):
        raise RuntimeError('Actual completed F3 record66, original nutrient/victory and durable native exit required')
    rows = {key: value for key, value in source.get('story_receipts', {}).items()
            if value.get('objective_id') in source_goals}
    disk_rows = {key: value for key, value in story.get('receipts', {}).items()
                 if value.get('objective_id') in source_goals}
    if len(rows) != 66 or receipt_digest(rows) != receipts_sha or rows != disk_rows:
        raise RuntimeError('Actual sixty-six source receipts differ from fresh original Store')
    findings = source_reader.get('personal', {}).get('discoveries', [])
    for finding in ('opening:whale_raw_command_record', 'F2:aligned_timeline',
                    'F3:living_isolation', 'F3:operation_record', 'boss:F3:mycelial_choir'):
        if findings.count(finding) != 1:
            raise RuntimeError('Unique actual prior finding missing: ' + finding)
    profile_path = Path(source['user_dir']) / 'profiles_v3' / PROFILE
    if not profile_path.is_dir():
        raise RuntimeError('Original QA profile absent; no replacement created')
    executable = (args.exe or project / 'build/V3Development/LowAltitudeTwinPulse-Dev.exe').resolve(strict=True)
    if executable.suffix.lower() != '.exe' or 'godot' in executable.name.lower():
        parser.error('Use the exported game EXE/main scene, not an engine executable')
    binding.verify_target(executable, dev.file_sha256)
    os.environ['LOW_ALTITUDE_DEV_HOME'] = str(dev.POLICY.root)
    stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S') + '_' + uuid.uuid4().hex[:8]
    dev.POLICY.preflight('evidence', 64 * 1024 ** 2)
    evidence = dev.POLICY.path('evidence', ('normal-i4-' + stamp))
    evidence.mkdir(parents=True, exist_ok=False)
    output = evidence / ('normal-i4-' + stamp + '.json')
    files = [executable, Path(__file__).resolve(), source_path]
    if executable.with_suffix('.pck').is_file():
        files.append(executable.with_suffix('.pck'))
    names = [
        'scripts/v3/qa/twin_normal_i4_qa.gd',
        'scripts/v3/twin_app.gd', 'scripts/v3/twin_session.gd',
        'scripts/v3/twin_test_world.gd', 'scripts/v3/twin_interface.gd',
        'scripts/v3/environment/twin_i4_storm_environment.gd',
        'scripts/v3/gameplay/twin_opening_story.gd',
        'scripts/v3/gameplay/actions/twin_action_director.gd',
        'scripts/v3/gameplay/twin_campaign_session.gd',
        'scripts/v3/gameplay/twin_i2_result_ledger.gd',
        'scripts/v3/gameplay/twin_ability_rules.gd',
        'scripts/v3/gameplay/twin_campaign_choices.gd',
        'scripts/v3/ui/twin_campaign_choice_panel.gd',
        'scripts/v3/campaign/twin_campaign_catalog.gd',
        'scripts/v3/campaign/twin_campaign_encounter.gd',
        'scripts/v3/campaign/twin_campaign_mechanisms.gd',
        'scripts/v3/campaign/twin_campaign_late_mechanisms.gd',
        'scripts/v3/campaign/twin_campaign_runtime_proofs.gd',
        'scripts/v3/world/twin_campaign_arena.gd',
        'scripts/v3/gameplay/canal/canal_transport_physics/transport_pilot.gd',
        'scripts/v3/qa/twin_normal_flight_pilot.gd',
        'scripts/v2/flight_body.gd',
        'scripts/v3/core/twin_canal_save_gate.gd', 'scripts/v3/core/twin_world_store.gd',
        'data/v3/campaign/i4_actions.json', 'data/v3/campaign/bosses.json',
        'data/v3/campaign/layouts.json', 'data/v3/campaign/physical_bindings.json',
        'data/v3/campaign/choices.json', 'data/v3/campaign/index.json',
        'data/v3/regions.json',
    ]
    files.extend(project / name for name in names)

    files.extend(binding.evidence_files())

    def hashes():
        return {str(path): dev.file_sha256(path) for path in files}

    before = hashes()
    command = [str(executable), '--', '--qa-normal-i4',
               '--qa-profile=' + PROFILE, '--qa-normal-output=' + str(output.resolve()),
               '--qa-normal-seconds=' + str(args.seconds),
               '--qa-i4-stop-after=' + args.stop_after]
    command.extend(binding.cli_args())
    (evidence / 'invocation.json').write_text(json.dumps({
        **binding.metadata,
        'command': command, 'profile': PROFILE, 'output': str(output),
        'working_directory': str(executable.parent), 'stop_after': args.stop_after,
        'requested_seconds': args.seconds, 'job_timeout_seconds': args.seconds + 15,
        'source_profile_directory': str(profile_path), 'source_report_sha256': source_sha,
        'source_sixty_six_receipts_sha256': receipts_sha,
        'scope': 'Exported MAIN natural66-to75 I4 only: original ordinary menu/M/spawn, '
                 'continuous Pilot/Flight, G NPC/archive, original4/Tab/F sustained source '
                 'and exact three original receipt hashes, original low-route/support rays, '
                 'normal Tab/G swept defence breaker plus supported platform/civilian supply, '
                 'actual entry/full attack cycle, current optical/isolation environment, '
                 'warning-driven diagonal movement and held original weapon/LOS, actual '
                 'two reversed phases/clamped HP chains, original Store victory/reward, '
                 'two real benefit/cost CheckBoxes and explicit regional_cosign Button/branch/'
                 'Consensus/Store, SaveGate/freshReader/session._quit audio drain. No pose/'
                 'HP/Story/flags/time/delta/environment/mechanism fixture, direct encounter/'
                 'fire/advance, clone/rollback/progress import. Formally integrated I4 storm '
                 'and visible environment_status are required at two newly flown shelter points, '
                 'with the original live clock and no phase/error/shelter difference requirement. '
                 'Partial stage stops remain explicitly incomplete.'
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
    if completed != expected[:len(completed)] or not 66 <= len(completed) <= 75:
        raise RuntimeError('Observer reports illegal natural I4 prefix')
    report_rows = {key: value for key, value in report.get('story_receipts', {}).items()
                   if value.get('objective_id') in source_goals}
    if len(report_rows) != 66 or receipt_digest(report_rows) != receipts_sha:
        raise RuntimeError('Observer changed actual source66 receipts')
    saved = report.get('fresh_reader', {})
    if (saved.get('profile_id') != source_reader.get('profile_id')
            or saved.get('lineage_id') != source_reader.get('lineage_id')):
        raise RuntimeError('Original identity/lineage must remain unchanged')
    complete = bool(report.get('i4_segment_complete'))
    if complete and (completed != expected or report.get('reached_stages') != list(STAGES)):
        raise RuntimeError('Complete requires all nine goals and all recorded stages')
    intentional_stage = (bool(report.get('requested_stage_stopped'))
                         and args.stop_after != 'complete'
                         and args.stop_after in report.get('reached_stages', [])
                         and len(completed) >= STAGE_COUNTS[args.stop_after])
    if complete:
        disk_world = saved.get('world', {})
        disk_state = disk_world.get('environment', {}).get('campaign_I4', {}).get('encounter', {}).get('state', {})
        proof = disk_world.get('environment', {}).get('campaign_I4', {}).get('mechanisms', {})
        findings = saved.get('personal', {}).get('discoveries', [])
        histories, facts = proof.get('histories', {}), proof.get('facts', {})
        if (report.get('status', {}).get('boss_active') or not disk_state.get('completed')
                or disk_state.get('phase') != 2 or disk_state.get('core_hp_milli') != 0
                or any(disk_state.get('parts', {}).get(key) != 0
                       for key in ('west_prism', 'east_prism'))
                or not disk_world.get('flags', {}).get('campaign_boss:I4')
                or not disk_world.get('flags', {}).get('I4:region_route_open')
                or not disk_world.get('flags', {}).get('I4:chapter_decision_saved')
                or findings.count('boss:I4:prism_array') != 1
                or findings.count('I4:operation_record') != 1
                or disk_world.get('actions', {}).get('opening', {}).get('choices', {}).get('I4:prism_array:decision') != 'regional_cosign'
                or facts.get('I4:evidence_delivery_verified') != 'optical'
                or len(histories.get('I4:evidence_chain', {})) != 3
                or facts.get('I4:storm_route_verified') != 'covered_low'
                or not histories.get('I4:route_record')
                or facts.get('I4:defence_isolated') not in ('mechanical_lock', 'field_lock')
                or not histories.get('I4:defence_record')):
            raise RuntimeError('Original optical/route/platform proofs and durable victory/choice missing')
        inherited = set(report.get('inherited_goals', []))
        if 'I4:array_witness:witness' not in inherited:
            delivery = report.get('actual_reveal_observations', [])
            if not any(row.get('actual_first_hit', {}).get('entity_id') == 'I4:witness_receiver'
                       and len(row.get('payload_hashes', {})) == 3
                       and row.get('payload_hashes') == row.get('received_hashes') == row.get('history')
                       for row in delivery):
                raise RuntimeError('New witness goal requires actual same-branch three-hash channel')
        if 'I4:array_witness:shelter' not in inherited:
            route_rows = report.get('actual_route_observations', [])
            if not any(row.get('kind') == 'supported_endpoint'
                       and row.get('support', {}).get('hit')
                       and 0 <= row.get('support', {}).get('gap_m', 99) <= 1.2
                       and row.get('receipt', {}).get('option') == 'covered_low'
                       for row in route_rows):
                raise RuntimeError('New low-route goal requires actual supported endpoint')
        if 'I4:array_witness:shelter' not in inherited:
            observed_storm = {row.get('point'): row for row in report.get('actual_storm_samples', [])
                              if row.get('kind') == 'native_MAIN_storm_sample'}
            for point in ('low_start', 'low_sample'):
                row = observed_storm.get(point, {})
                field = row.get('field', {})
                if (not row.get('field_valid') or not row.get('visible_hud_valid')
                        or not row.get('visible_hud') or not field.get('available')
                        or field.get('code') != 'actual_current_world_sample'
                        or not all(text in row.get('hud_text', '')
                                   for text in ('风→', '罗盘约', '±'))):
                    raise RuntimeError('New shelter route requires actual MAIN storm/HUD evidence: ' + point)
        if 'I4:prism_array:decision' not in report.get('initial_completed', []):
            ui = report.get('actual_choice_ui_actions', [])
            read = [row for row in ui if row.get('kind') == 'actual_CheckBox']
            pressed = [row for row in ui if row.get('kind') == 'actual_Button_pressed']
            if (len(read) != 2 or any(not row.get('host_acknowledged')
                                    or row.get('input') != ('inherited original read acknowledgement'
                                                           if row.get('was_checked') else 'focused ui_accept')
                                    for row in read)
                    or len(pressed) != 1 or pressed[0].get('option') != 'regional_cosign'
                    or pressed[0].get('input') != 'focused ui_accept'):
                raise RuntimeError('New decision requires two actual read acknowledgements and explicit original button')
        if not report.get('inherited_committed_victory'):
            if (not report.get('damage_evidence', {}).get('ok')
                    or not report.get('phase_two_observed')
                    or not report.get('actual_damage_samples')
                    or not report.get('stats', {}).get('shots')):
                raise RuntimeError('New victory requires actual weapon/two-phase/damage evidence')
            current_hp = report.get('battle_baseline', {}).get('core_hp_milli')
            for row in report['actual_damage_samples']:
                if (row.get('damage_phase') not in (1, 2)
                        or row.get('before', 0) <= row.get('after', -1)
                        or row.get('after', -1) < 0
                        or row.get('drop') != row['before'] - row['after']
                        or row.get('shots_after', 0) <= row.get('shots_before', 0)):
                    raise RuntimeError('Actual HP drop requires exact observed before/after and shot counters')
                if row['part'] == 'core':
                    if row['before'] != current_hp:
                        raise RuntimeError('Actual core HP chain has unobserved jump')
                    current_hp = row['after']
            if current_hp != 0:
                raise RuntimeError('Actual core damage chain must finish exactly at zero')
            if report.get('battle_baseline', {}).get('phase') == 1:
                phase2 = [row for row in report.get('actual_part_visits', []) if row.get('phase') == 2]
                if not phase2 or phase2[0].get('part') != 'east_prism':
                    raise RuntimeError('Actual phase2 must begin with reversed east prism')
            if not any(row.get('environment', {}).get('receiver_lit')
                       and row.get('environment', {}).get('defence_isolated')
                       and row.get('ray', {}).get('entity_id') == 'I4:witness_receiver'
                       for row in report.get('actual_environment_observations', [])):
                raise RuntimeError('Historical investigation cannot replace actual present Boss environment')
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


