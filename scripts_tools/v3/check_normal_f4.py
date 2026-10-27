"""Exported MAIN same natural I4 decision75 -> F4 Ending84, authoring only.

All three source bindings intentionally empty. Abort before project/profile/
evidence/process I/O until Root binds successful actual I4 decision75 evidence.
Reports are read-only provenance, never imported/cloned/rolled back progress.
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
SOURCE_REPORT = 'artifacts/v3/normal-i4-20261021_061149_2f6abfd7/normal-i4-20261021_061149_2f6abfd7.json'
SOURCE_REPORT_SHA256 = 'a13ebc302fa9d12611103c02c5c09f6434ebd6a5fb7515339b14519c3165f183'
SEVENTYFIVE_DIGEST = '6e7c86de9c5ab2dc0b9e35a00fbe3c42b0f7010f60e1e986f59dd0d14c1fa8a4'
STAGES = ('council', 'industry', 'living', 'test', 'review',
          'plan', 'engage', 'half', 'stop', 'complete')
STAGE_COUNTS = dict(zip(STAGES, (76, 77, 78, 79, 80, 81, 82, 82, 83, 84)))


def receipt_digest(rows):
    return hashlib.sha256(json.dumps(rows, ensure_ascii=False, sort_keys=True,
                                     separators=(',', ':')).encode('utf-8')).hexdigest()


def validate_gui_actions(report):
    ui = report.get('actual_GUI_actions')
    if not isinstance(ui, list):
        raise RuntimeError('Observer must report actual_GUI_actions with explicit native input evidence')
    native_input = 'focused GUI ui_accept press/release'

    def native_action(row):
        return (row.get('input') == native_input and bool(row.get('path'))
                and any(action.get('kind') == 'actual_GUI_input'
                        and action.get('path') == row['path']
                        and action.get('input') == native_input for action in ui))

    completed = report.get('status', {}).get('completed', [])
    initial = report.get('initial_completed', [])
    for target, objective in [('F4:plans_reviewed', 'F4:vein_reunion:plan'),
                              ('F4:chapter_choice', 'F4:twin_vein_core:decision')]:
        if objective not in completed or objective in initial:
            continue
        read = [row for row in ui if row.get('kind') == 'actual_CheckBox'
                and row.get('target') == target]
        if (len(read) != 3 or len({row.get('option') for row in read}) != 3
                or any(not row.get('host_acknowledged') or not row.get('identity')
                       or not row.get('is_checked') for row in read)):
            raise RuntimeError('Each new preread/final target requires three actual stable-UUID read acknowledgements')
        for row in read:
            if row.get('was_checked'):
                if row.get('input') != 'previously acknowledged read':
                    raise RuntimeError('A previously acknowledged box cannot claim a new native input')
            elif not native_action(row):
                raise RuntimeError('Each newly checked box requires focused native press/release input evidence')
    if 'F4:twin_vein_core:decision' in completed and 'F4:twin_vein_core:decision' not in initial:
        pressed = [row for row in ui if row.get('kind') == 'actual_final_Button']
        if (len(pressed) != 1 or pressed[0].get('target') != 'F4:chapter_choice'
                or pressed[0].get('option') != 'shared_stewardship' or not native_action(pressed[0])):
            raise RuntimeError('New ending requires the actual focused ui_accept shared_stewardship Button')


def main():
    global PROFILE, SOURCE_REPORT, SOURCE_REPORT_SHA256, SEVENTYFIVE_DIGEST
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe', type=Path,
                        default=None)
    parser.add_argument('--seconds', type=int, default=900, choices=range(60, 901),
                        metavar='60..900')
    parser.add_argument('--i4-report', type=Path, default=None,
                        help='Exact Root-bound successful natural I4 decision75 report')
    parser.add_argument('--stop-after', choices=STAGES, default='complete',
                        help='Stops before complete preserve explicitly incomplete goals/combat')
    add_binding_arguments(parser)
    args = parser.parse_args()
    binding = load_binding(args.source_binding, args.source_binding_sha256,
                           project=Path(__file__).resolve().parents[2],
                           entry='normal-f4', segment='')
    PROFILE = binding.values['SOURCE_PROFILE']
    SOURCE_REPORT = binding.values['SOURCE_REPORT']
    SOURCE_REPORT_SHA256 = binding.values['SOURCE_REPORT_SHA256']
    SEVENTYFIVE_DIGEST = binding.values['SEVENTYFIVE_DIGEST']
    if args.i4_report is None:
        args.i4_report = binding.report_path
    elif args.i4_report.resolve(strict=True) != binding.report_path:
        raise RuntimeError('Explicit predecessor must equal strict binding source')
    # Empty bindings reject before project/profile/evidence/process I/O.
    if (not re.fullmatch(r'[0-9a-f]{64}', SOURCE_REPORT_SHA256)
            or not re.fullmatch(r'[0-9a-f]{64}', SEVENTYFIVE_DIGEST)
            or not SOURCE_REPORT):
        raise RuntimeError('UNBOUND: Root must bind actual successful I4 decision75 '
                           'report path/SHA and exact75 receipts in BOTH Node and runner')
    project = next(parent for parent in Path(__file__).resolve().parents
                   if (parent / 'project.godot').is_file()
                   and (parent / 'scripts_tools/v3/dev.py').is_file())
    sys.path.insert(0, str(project / 'scripts_tools/v3'))
    import dev
    installed = project / 'scripts/v3/qa/twin_normal_f4_qa.gd'
    if not installed.is_file():
        raise RuntimeError('Root must promote staged F4 Node/CLI and export first')
    node_text = installed.read_text(encoding='utf-8-sig')

    def bound_constant(name, digest=True):
        if name in binding.values:
            return binding.values[name]
        match = re.search(r'^const ' + re.escape(name) + r' := "([^"\r\n]*)"$',
                          node_text, re.M)
        if not match or (digest and not re.fullmatch(r'[0-9a-f]{64}', match.group(1))):
            raise RuntimeError('Actual source75 evidence not bound: ' + name)
        return match.group(1)

    def goal_constant(name):
        match = re.search(r'^const ' + re.escape(name) + r' := (\[.*\])$', node_text, re.M)
        if not match:
            raise RuntimeError('Exact original goal order missing: ' + name)
        return json.loads(match.group(1))

    source_sha = bound_constant('SOURCE_REPORT_SHA256')
    receipts_sha = bound_constant('SEVENTYFIVE_DIGEST')
    if (source_sha != SOURCE_REPORT_SHA256 or receipts_sha != SEVENTYFIVE_DIGEST
            or bound_constant('SOURCE_REPORT', False) != SOURCE_REPORT):
        raise RuntimeError('Node and runner must bind SAME actual75 evidence')
    source_goals, expected = goal_constant('SOURCE_GOALS'), goal_constant('EXPECTED')
    tail = ['F4:vein_reunion:' + name for name in ('council', 'industry', 'living', 'test', 'plan')]
    tail += ['F4:twin_vein_core:' + name for name in ('plan', 'engage', 'stop', 'decision')]
    if len(source_goals) != 75 or len(expected) != 84 or expected[:75] != source_goals or expected[75:] != tail:
        raise RuntimeError('Only exact original75-to84 F4 actions supported, no extra record85')
    source_path = (args.i4_report or project / SOURCE_REPORT).resolve(strict=True)
    if hashlib.sha256(source_path.read_bytes()).hexdigest() != source_sha:
        raise RuntimeError('Actual I4 decision75 report differs from Root-bound SHA')
    source = json.loads(source_path.read_text(encoding='utf-8-sig'))
    source_exit, source_preservation = source.get('native_exit', {}), source.get('preservation', {})
    source_reader = source.get('fresh_reader', {})
    world = source_reader.get('world', {})
    story = world.get('actions', {}).get('opening', {})
    prior = world.get('environment', {}).get('campaign_I4', {})
    prior_boss = prior.get('encounter', {}).get('state', {})
    if (not source.get('i4_segment_complete') or not source.get('complete')
            or source.get('failures') or source.get('engine_errors')
            or source.get('profile') != PROFILE
            or source.get('status', {}).get('completed') != source_goals
            or source.get('status', {}).get('region') != 'I4'
            or source.get('status', {}).get('boss_active')
            or not source_preservation.get('original_prefix_preserved')
            or not source_preservation.get('current_SaveGate_completed')
            or not source_preservation.get('fresh_Story_matches_live')
            or source_exit.get('through') != 'session._quit'
            or not source_exit.get('observed_scene_exit') or source_exit.get('watchdog_failed')
            or not source_exit.get('audio', {}).get('ready')
            or world.get('region_id') != 'I4' or world.get('branch_id') != 'main'
            or story.get('completed') != source_goals
            or world.get('completed_objectives') != source_goals
            or not world.get('flags', {}).get('I4:region_route_open')
            or not world.get('flags', {}).get('I4:chapter_decision_saved')
            or not world.get('flags', {}).get('campaign_boss:I4')
            or not prior_boss.get('completed') or prior_boss.get('phase') != 2
            or prior_boss.get('core_hp_milli') != 0
            or story.get('choices', {}).get('I4:prism_array:decision') not in ('public_caps', 'regional_cosign')
            or world.get('flags', {}).get('campaign_boss:F4')):
        raise RuntimeError('Actual completed I4 choice75, original victory/choice and durable native exit required')
    rows = {key: value for key, value in source.get('story_receipts', {}).items()
            if value.get('objective_id') in source_goals}
    disk_rows = {key: value for key, value in story.get('receipts', {}).items()
                 if value.get('objective_id') in source_goals}
    if len(rows) != 75 or receipt_digest(rows) != receipts_sha or rows != disk_rows:
        raise RuntimeError('Actual seventy-five source receipts differ from fresh original Store')
    previous = {key: value for key, value in rows.items()
                if value.get('objective_id') in source_goals[:66]}
    if (not re.fullmatch(r'[0-9a-f]{64}', source.get('source_receipts_sha256', ''))
            or receipt_digest(previous) != source['source_receipts_sha256']):
        raise RuntimeError('Actual I4 report must retain exact original F3 record66 base')
    prior_histories = prior.get('mechanisms', {}).get('histories', {})
    if any(not prior_histories.get(key) for key in ('I4:evidence_chain', 'I4:route_record', 'I4:defence_record')):
        raise RuntimeError('Actual I4 optical/continuous-route/defence histories required')
    findings = source_reader.get('personal', {}).get('discoveries', [])
    for finding in ('F3:living_isolation', 'F3:operation_record', 'I4:operation_record', 'boss:I4:prism_array'):
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
    evidence = dev.POLICY.path('evidence', ('normal-f4-' + stamp))
    evidence.mkdir(parents=True, exist_ok=False)
    output = evidence / ('normal-f4-' + stamp + '.json')
    files = [executable, Path(__file__).resolve(), source_path]
    if executable.with_suffix('.pck').is_file():
        files.append(executable.with_suffix('.pck'))
    names = [
        'scripts/v3/qa/twin_normal_f4_qa.gd',
        'scripts/v3/twin_app.gd', 'scripts/v3/twin_session.gd',
        'scripts/v3/twin_test_world.gd', 'scripts/v3/twin_interface.gd',
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
        'data/v3/campaign/f4_actions.json', 'data/v3/campaign/bosses.json',
        'data/v3/campaign/layouts.json', 'data/v3/campaign/physical_bindings.json',
        'data/v3/campaign/choices.json', 'data/v3/campaign/index.json',
        'data/v3/regions.json',
    ]
    files.extend(project / name for name in names)

    files.extend(binding.evidence_files())

    def hashes():
        return {str(path): dev.file_sha256(path) for path in files}

    before = hashes()
    command = [str(executable), '--', '--qa-normal-f4',
               '--qa-profile=' + PROFILE, '--qa-normal-output=' + str(output.resolve()),
               '--qa-normal-seconds=' + str(args.seconds),
               '--qa-f4-stop-after=' + args.stop_after]
    command.extend(binding.cli_args())
    (evidence / 'invocation.json').write_text(json.dumps({
        **binding.metadata,
        'command': command, 'profile': PROFILE, 'output': str(output),
        'working_directory': str(executable.parent), 'stop_after': args.stop_after,
        'requested_seconds': args.seconds, 'job_timeout_seconds': args.seconds + 15,
        'source_profile_directory': str(profile_path), 'source_report_sha256': source_sha,
        'source_seventy_five_receipts_sha256': receipts_sha,
        'scope': 'Exported MAIN natural75-to84 only. Ordinary menu/M/spawn and '
                 'unloaded QA Flight Pilot preserving original inertia/full hull/stopping '
                 'sweeps; original G/6F/4F/three7F; real latched hold and same-serial '
                 '120W/90W gauge G reads; three per-UUID preread checkboxes without choice; '
                 'separate real Boss charge breaker/5X sink/4F plus7F core full span; '
                 'actual entry/two reversed phases/held original weapon/LOS/HP chains; '
                 'current four Boss environment fields; original Store victory, final '
                 'three checkboxes/focused ui_accept shared_stewardship through original '
                 'prepare+commit fresh-native lifeline gates, Store/Ending84; SaveGate/'
                 'freshReader/session._quit/audio ready and native leak log rejection. '
                 'No fictional85, fixtures/pose/HP/clock/Story/environment edits, direct '
                 'fire/encounter advance, clone/rollback/progress import, abilities after '
                 'ready proposal, or LAN/human/fun/full campaign claim.'
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
        native_log = evidence / 'exported-main.log'
        native_lines = native_log.read_text(encoding='utf-8', errors='replace').splitlines() if native_log.is_file() else []
        native_leak_lines = [line for line in native_lines if re.search(
            r'ObjectDB instances leaked at exit|resources still in use at exit|RID allocations of type.*were leaked',
            line, re.I)]
        (evidence / 'inputs.json').write_text(json.dumps({
            **binding.metadata,
            'before': before, 'after': after, 'unchanged': before == after,
            'native_exit_leak_lines': native_leak_lines,
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
    if completed != expected[:len(completed)] or not 75 <= len(completed) <= 84:
        raise RuntimeError('Observer reports illegal natural F4 prefix')
    report_rows = {key: value for key, value in report.get('story_receipts', {}).items()
                   if value.get('objective_id') in source_goals}
    if len(report_rows) != 75 or receipt_digest(report_rows) != receipts_sha:
        raise RuntimeError('Observer changed actual source75 receipts')
    saved = report.get('fresh_reader', {})
    if (saved.get('profile_id') != source_reader.get('profile_id')
            or saved.get('lineage_id') != source_reader.get('lineage_id')):
        raise RuntimeError('Original identity/lineage must remain unchanged')
    validate_gui_actions(report)
    complete = bool(report.get('f4_segment_complete'))
    if complete and (completed != expected or report.get('reached_stages') != list(STAGES)):
        raise RuntimeError('Complete requires all nine original goals and all stages, exactly84')
    intentional_stage = (bool(report.get('requested_stage_stopped'))
                         and args.stop_after != 'complete'
                         and args.stop_after in report.get('reached_stages', [])
                         and len(completed) >= STAGE_COUNTS[args.stop_after])
    if complete:
        disk_world = saved.get('world', {})
        disk_story = disk_world.get('actions', {}).get('opening', {})
        disk_state = disk_world.get('environment', {}).get('campaign_F4', {}).get('encounter', {}).get('state', {})
        proof = disk_world.get('environment', {}).get('campaign_F4', {}).get('mechanisms', {})
        findings = saved.get('personal', {}).get('discoveries', [])
        histories, facts = proof.get('histories', {}), proof.get('facts', {})
        load_record = histories.get('F4:dual_load_record', {})
        load_readings = load_record.get('readings', {})
        serial = load_record.get('test_serial')
        if (report.get('status', {}).get('boss_active') or not disk_state.get('completed')
                or disk_state.get('phase') != 2 or disk_state.get('core_hp_milli') != 0
                or any(disk_state.get('parts', {}).get(key) != 0
                       for key in ('charge_return', 'thermal_return', 'living_return'))
                or not disk_world.get('flags', {}).get('campaign_boss:F4')
                or not disk_world.get('flags', {}).get('F4:region_route_open')
                or not disk_world.get('flags', {}).get('F4:chapter_decision_saved')
                or findings.count('boss:F4:twin_vein_core') != 1
                or findings.count('F4:operation_record') != 1
                or disk_story.get('choices', {}).get('F4:twin_vein_core:decision') != 'shared_stewardship'
                or facts.get('F4:industrial_link_verified') != 'limited_bus'
                or facts.get('F4:living_link_verified') != 'growth_support'
                or facts.get('F4:dual_load_verified') not in ('latched_test', 'echo_test', 'two_pilots')
                or facts.get('F4:plans_reviewed') != 'all_read'
                or len(histories.get('F4:plans_read', {})) != 3
                or len(load_readings) != 2 or not isinstance(serial, (int, float)) or serial <= 0
                or load_readings.get('industrial', {}).get('test_serial') != serial
                or load_readings.get('living', {}).get('test_serial') != serial
                or load_readings.get('industrial', {}).get('load_w') != 120
                or load_readings.get('living', {}).get('load_w') != 90):
            raise RuntimeError('Original approach/same-serial readings/preread/victory/final Store missing')
        inherited = set(report.get('inherited_goals', []))
        if 'F4:vein_reunion:test' not in inherited:
            if not any(row.get('kind') == 'actual_same_serial_pair'
                       and row.get('serial') == serial
                       and row.get('receipt', {}).get('option') == 'latched_test'
                       for row in report.get('actual_load_observations', [])):
                raise RuntimeError('New test requires actual same-serial G pair and real hold latch')
        # Actual GUI input/read acknowledgements were also required for stop-after review.
        if 'F4:twin_vein_core:decision' not in report.get('initial_completed', []):
            gates = report.get('actual_final_gate_observations', [])
            if not any(row.get('label') == 'after_three_final_reads_before_explicit_proposal'
                       and row.get('status', {}).get('ok') and not row.get('proposal')
                       for row in gates):
                raise RuntimeError('New proposal must follow a fresh actual native lifeline sample before ready')
        ending = report.get('actual_ending_observations', [])
        if not any(row.get('ending', {}).get('ending_id') == 'shared_stewardship'
                   and row.get('info', {}).get('complete')
                   and row.get('completed') == expected
                   and '一起照料的脉络' in row.get('actual_objective_text', '')
                   for row in ending):
            raise RuntimeError('Original complete Director must present actual normal Ending84 HUD')
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
                    raise RuntimeError('Actual HP drop requires exact observed chain and real shot counters')
                if row['part'] == 'core':
                    if row['before'] != current_hp:
                        raise RuntimeError('Actual core HP chain has an unobserved jump')
                    current_hp = row['after']
            if current_hp != 0:
                raise RuntimeError('Actual core damage chain must finish exactly at zero')
            if report.get('battle_baseline', {}).get('phase') == 1:
                phase2 = [row for row in report.get('actual_part_visits', []) if row.get('phase') == 2]
                if not phase2 or phase2[0].get('part') != 'living_return':
                    raise RuntimeError('Actual phase2 must begin with reversed living return')
            if not any(all(row.get('environment', {}).get(field) for field in
                           ('charge_loop_open', 'thermal_sink_ready', 'living_support_ready', 'both_lifelines_connected'))
                       for row in report.get('actual_environment_observations', [])):
                raise RuntimeError('Old approach facts cannot replace all four present-time Boss gates')
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
        'native_exit': native_exit, 'native_exit_leak_lines': native_leak_lines,
    }, ensure_ascii=False))
    if (report.get('profile') != PROFILE or report.get('source_report_sha256') != source_sha
            or report.get('source_receipts_sha256') != receipts_sha
            or report.get('requested_stage') != args.stop_after):
        raise RuntimeError('Observer result does not match actual source/stage')
    if (execution_failure is not None or native_leak_lines or before != after or not own_folder
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

