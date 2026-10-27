"""Candidate exported MAIN continuation: actual natural I3 record58 -> F3 record66.

Intentionally UNBOUND. Root must bind the genuine completed58 report/path/SHA
and its exact58 receipt digest in BOTH this runner and the promoted observer.
No source report is progress import; the same existing QA profile advances only
through the ordinary game. This file never clones/resets/rolls back a profile.
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
SOURCE_REPORT = 'artifacts/v3/normal-i3-boss-20261021_060248_5956f59a/normal-i3-boss-20261021_060248_5956f59a.json'
SOURCE_REPORT_SHA256 = '814107acafcd07ce20b192a2c18435b0491a0bb95c9594232bd126106a85f740'
FIFTYEIGHT_DIGEST = '27512fd154e327bf1229a8b44da11517db2fa4038fc0716c48b3043e6bb2f7ba'
STAGES = ('sample', 'listen', 'isolate', 'feed', 'plan', 'engage', 'half', 'stop', 'complete')
MIN_GOALS = dict(zip(STAGES, (59, 60, 61, 62, 63, 64, 64, 65, 66)))
F3_GOALS = [
    'F3:separate_network:sample', 'F3:separate_network:listen',
    'F3:separate_network:isolate', 'F3:separate_network:feed',
    'F3:mycelial_choir:plan', 'F3:mycelial_choir:engage',
    'F3:mycelial_choir:stop', 'F3:mycelial_choir:record',
]


def receipt_digest(rows):
    return hashlib.sha256(json.dumps(rows, ensure_ascii=False, sort_keys=True,
                                     separators=(',', ':')).encode('utf-8')).hexdigest()


def source_receipts(report, goals):
    rows = report.get('story_receipts', {})
    if not isinstance(rows, dict) or any(not isinstance(row, dict) for row in rows.values()):
        raise RuntimeError('Original receipt Dictionary required')
    return {key: row for key, row in rows.items() if row.get('objective_id') in goals}


def native_exit_valid(report):
    exit_state = report.get('native_exit', {})
    return (exit_state.get('through') == 'session._quit'
            and exit_state.get('observed_scene_exit')
            and not exit_state.get('watchdog_failed')
            and exit_state.get('audio', {}).get('ready'))


def preservation_valid(report):
    row = report.get('preservation', {})
    return all(row.get(key) for key in ('original_prefix_preserved',
                                       'current_SaveGate_completed',
                                       'fresh_Story_matches_live'))


def main():
    global PROFILE, SOURCE_REPORT, SOURCE_REPORT_SHA256, FIFTYEIGHT_DIGEST
    project = next(parent for parent in Path(__file__).resolve().parents
                   if (parent / 'project.godot').is_file()
                   and (parent / 'scripts_tools/v3/dev.py').is_file())
    sys.path.insert(0, str(project / 'scripts_tools/v3'))
    import dev
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe', type=Path,
                        default=project / 'build/V3Development/LowAltitudeTwinPulse-Dev.exe')
    parser.add_argument('--seconds', type=int, default=600, choices=range(60, 601),
                        metavar='60..600')
    parser.add_argument('--source-report', type=Path, default=None,
                        help='Optional exact same Root-bound actual58 report path')
    parser.add_argument('--stop-after', choices=STAGES, default='complete')
    add_binding_arguments(parser)
    args = parser.parse_args()
    binding = load_binding(args.source_binding, args.source_binding_sha256,
                           project=Path(__file__).resolve().parents[2],
                           entry='normal-f3', segment='')
    PROFILE = binding.values['SOURCE_PROFILE']
    SOURCE_REPORT = binding.values['SOURCE_REPORT']
    SOURCE_REPORT_SHA256 = binding.values['SOURCE_REPORT_SHA256']
    FIFTYEIGHT_DIGEST = binding.values['FIFTYEIGHT_DIGEST']
    # Deliberately FIRST: no project discovery/import, report/profile/EXE read,
    # directory creation or process may happen before Root binds actual evidence.
    if (not SOURCE_REPORT or not re.fullmatch(r'[0-9a-f]{64}', SOURCE_REPORT_SHA256)
            or not re.fullmatch(r'[0-9a-f]{64}', FIFTYEIGHT_DIGEST)):
        raise RuntimeError('UNBOUND: Root must bind successful natural I3 record58 '
                           'SOURCE_REPORT/SHA and exact FIFTYEIGHT_DIGEST in Node+runner')
    if args.source_report is None:
        args.source_report = binding.report_path
    elif args.source_report.resolve(strict=True) != binding.report_path:
        raise RuntimeError('Explicit predecessor must equal strict binding source')
    installed = project / 'scripts/v3/qa/twin_normal_f3_qa.gd'
    if not installed.is_file():
        raise RuntimeError('Root must promote observer, App routing and export first')
    node_text = installed.read_text(encoding='utf-8-sig')

    def constant(name):
        if name in binding.values:
            return binding.values[name]
        match = re.search(r'^const ' + re.escape(name) + r' := (.+)$', node_text, re.M)
        if not match:
            raise RuntimeError('Observer constant missing: ' + name)
        return json.loads(match.group(1))

    for key, expected in (('SOURCE_PROFILE', PROFILE), ('SOURCE_REPORT', SOURCE_REPORT),
                          ('SOURCE_REPORT_SHA256', SOURCE_REPORT_SHA256),
                          ('FIFTYEIGHT_DIGEST', FIFTYEIGHT_DIGEST)):
        if constant(key) != expected:
            raise RuntimeError('Node and runner actual source bindings differ: ' + key)
    source_goals = constant('SOURCE_GOALS')
    expected = constant('EXPECTED')
    if (len(source_goals) != 58 or len(expected) != 66
            or expected[:58] != source_goals or expected[58:] != F3_GOALS):
        raise RuntimeError('Only exact original58 -> eight F3 objectives is supported')
    source_path = (project / SOURCE_REPORT).resolve(strict=True)
    if args.source_report and args.source_report.resolve(strict=True) != source_path:
        raise RuntimeError('A CLI source cannot replace Root-bound genuine58 evidence')
    if hashlib.sha256(source_path.read_bytes()).hexdigest() != SOURCE_REPORT_SHA256:
        raise RuntimeError('Genuine58 source differs from Root-bound exact file SHA')
    source = json.loads(source_path.read_text(encoding='utf-8-sig'))
    if (not source.get('complete') or source.get('failures') or source.get('engine_errors')
            or source.get('profile') != PROFILE
            or source.get('status', {}).get('region') != 'I3'
            or source.get('status', {}).get('completed') != source_goals
            or not preservation_valid(source) or not native_exit_valid(source)):
        raise RuntimeError('Require actual completed natural58, SaveGate/fresh reader/native exit')
    rows = source_receipts(source, source_goals)
    if len(rows) != 58 or receipt_digest(rows) != FIFTYEIGHT_DIGEST:
        raise RuntimeError('Genuine58 original full receipts differ')
    source_reader = source.get('fresh_reader', {})
    source_world = source_reader.get('world', {})
    source_state = source_world.get('actions', {}).get('opening', {})
    discoveries = source_reader.get('personal', {}).get('discoveries', [])
    if (source_world.get('region_id') != 'I3' or source_world.get('branch_id') != 'main'
            or source_state.get('completed') != source_goals
            or source_world.get('completed_objectives') != source_goals
            or source_state.get('receipts') != source.get('story_receipts')
            or 'I3:furnace_crawler' not in source_state.get('completed_actions', [])
            or any(not source_world.get('flags', {}).get(key)
                   for key in ('I3:cooling_ready', 'campaign_boss:I3', 'I3:region_route_open'))
            or any(discoveries.count(key) != 1
                   for key in ('boss:I3:furnace_crawler', 'I3:operation_record', 'I3:stoppable_route'))):
        raise RuntimeError('Genuine58 must carry the original durable complete I3 action')
    # Existence only: no profile files are read or written by this controller.
    profile_path = Path(source['user_dir']) / 'profiles_v3' / PROFILE
    if not profile_path.is_dir():
        raise RuntimeError('Original natural QA profile absent; no replacement/rollback')
    executable = args.exe.resolve(strict=True)
    if executable.suffix.lower() != '.exe' or 'godot' in executable.name.lower():
        parser.error('Require exported game EXE ordinary MAIN, never engine/script override')
    binding.verify_target(executable, dev.file_sha256)
    os.environ['LOW_ALTITUDE_DEV_HOME'] = str(dev.POLICY.root)
    stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S') + '_' + uuid.uuid4().hex[:8]
    dev.POLICY.preflight('evidence', 64 * 1024 ** 2)
    evidence = dev.POLICY.path('evidence', ('normal-f3-' + stamp))
    evidence.mkdir(parents=True, exist_ok=False)
    output = evidence / ('normal-f3-' + stamp + '.json')
    names = [
        'scripts/v3/qa/twin_normal_f3_qa.gd', 'scripts/v3/qa/twin_normal_flight_pilot.gd',
        'scripts/v3/twin_app.gd', 'scripts/v3/twin_session.gd',
        'scripts/v3/twin_test_world.gd', 'scripts/v3/twin_interface.gd',
        'scripts/v3/gameplay/twin_opening_story.gd',
        'scripts/v3/gameplay/actions/twin_action_director.gd',
        'scripts/v3/gameplay/twin_campaign_session.gd',
        'scripts/v3/gameplay/twin_i2_result_ledger.gd',
        'scripts/v3/gameplay/twin_ability_rules.gd',
        'scripts/v3/gameplay/twin_weapon_session.gd',
        'scripts/v3/campaign/twin_campaign_catalog.gd',
        'scripts/v3/campaign/twin_campaign_mechanisms.gd',
        'scripts/v3/campaign/twin_campaign_late_mechanisms.gd',
        'scripts/v3/campaign/twin_campaign_encounter.gd',
        'scripts/v3/campaign/twin_campaign_runtime_proofs.gd',
        'scripts/v3/campaign/twin_campaign_npc_routes.gd',
        'scripts/v3/ecology/twin_living_world.gd', 'scripts/v3/ecology/twin_ecology_state.gd',
        'scripts/v3/world/twin_region_catalog.gd',
        'scripts/v3/gameplay/canal/canal_transport_physics/transport_pilot.gd',
        'scripts/v3/core/twin_canal_save_gate.gd', 'scripts/v3/core/twin_world_store.gd',
        'data/v3/campaign/f3_actions.json', 'data/v3/campaign/layouts.json',
        'data/v3/campaign/physical_bindings.json', 'data/v3/campaign/bosses.json',
        'data/v3/campaign/index.json', 'data/v3/campaign/npc_routes.json',
        'data/v3/ecology/routes.json', 'data/v3/regions.json',
    ]
    files = [executable, Path(__file__).resolve(), source_path, dev.__file__]
    if executable.with_suffix('.pck').is_file():
        files.append(executable.with_suffix('.pck'))
    files.extend(project / name for name in names)

    files.extend(binding.evidence_files())

    def hashes():
        return {str(path): dev.file_sha256(path) for path in files}

    before = hashes()
    command = [str(executable), '--', '--qa-normal-f3', '--qa-profile=' + PROFILE,
               '--qa-normal-output=' + str(output.resolve()),
               '--qa-normal-seconds=' + str(args.seconds),
               '--qa-f3-stop-after=' + args.stop_after]
    command.extend(binding.cli_args())
    (evidence / 'invocation.json').write_text(json.dumps({
        **binding.metadata,
        'command': command, 'profile': PROFILE, 'working_directory': str(executable.parent),
        'output': str(output), 'stop_after': args.stop_after,
        'requested_seconds': args.seconds, 'job_timeout_seconds': args.seconds + 15,
        'source_profile_directory': str(profile_path), 'source_report': str(source_path),
        'source_report_sha256': SOURCE_REPORT_SHA256,
        'source_fifty_eight_receipts_sha256': FIFTYEIGHT_DIGEST,
        'scope': 'Ordinary exported MAIN same natural58 profile -> F3 record66. Actual '
                 'M travel, swept unloaded QA flight Pilot, G sample/NPC/devices/record, '
                 'original4 light/three7 growth/9 echo/G latch, native named Ecology '
                 'pickup-route-transport arrival/proof, original held fire/current part '
                 'armor/LOS/two phases/Store victory. No pose/Director/HP/temperature/'
                 'environment/cargo/event/clock fixture, direct load/start, manual '
                 'simulation, profile clone/reset/rollback or report progress import. '
                 'Intermediate stages are incomplete; not whole-game/fun/LAN evidence.'
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
            'note': 'EXE/PCK SHA identifies executed package; source hashes identify '
                    'current worktree, not package/source equivalence. The original '
                    'profile advances normally and is never reset or cloned.'
        }, ensure_ascii=False, indent=2), encoding='utf-8')
    if not output.is_file():
        print(json.dumps({'complete': False, 'evidence': str(evidence),
                          'error': 'No observer report: CLI/timeout/import is incomplete.'}))
        raise SystemExit(1)
    report = json.loads(output.read_text(encoding='utf-8-sig'))
    binding.validate_output(report)
    cwd = report.get('runtime_cwd', '')
    own_folder = bool(cwd) and os.path.normcase(os.path.realpath(cwd)) == os.path.normcase(os.path.realpath(executable.parent))
    completed = report.get('status', {}).get('completed', [])
    if completed != expected[:len(completed)] or not 58 <= len(completed) <= 66:
        raise RuntimeError('Observer reports an illegal/different natural prefix')
    report_rows = source_receipts(report, source_goals)
    if len(report_rows) != 58 or receipt_digest(report_rows) != FIFTYEIGHT_DIGEST:
        raise RuntimeError('Observer altered actual original58 receipts')
    fresh = report.get('fresh_reader', {})
    if (fresh.get('profile_id') != source_reader.get('profile_id')
            or fresh.get('lineage_id') != source_reader.get('lineage_id')
            or fresh.get('world', {}).get('actions', {}).get('opening', {}).get('completed') != completed
            or fresh.get('world', {}).get('completed_objectives') != completed):
        raise RuntimeError('Fresh saved prefix/profile identity must match actual live Story')
    complete = bool(report.get('complete') and report.get('f3_segment_complete'))
    if complete:
        if completed != expected or report.get('reached_stages') != list(STAGES):
            raise RuntimeError('Complete requires all eight actual F3 goals/nine observation stages')
        world = fresh.get('world', {})
        findings = fresh.get('personal', {}).get('discoveries', [])
        proof = world.get('environment', {}).get('campaign_F3', {}).get('mechanisms', {}).get('histories', {}).get('F3:nutrient_route_proof', {})
        event = proof.get('event', {})
        if (proof.get('branch_id') != world.get('branch_id') or proof.get('route') != 'grown_path'
                or event.get('actor_id') != 'F3:nutrient_01'
                or event.get('target_id') != 'F3:nutrient_receiver'
                or event.get('type') != 'transport_arrival' or event.get('kind') != event.get('type')
                or event.get('amount') != 1
                or any(findings.count(key) != 1 for key in ('boss:F3:mycelial_choir', 'F3:operation_record', 'F3:living_isolation'))):
            raise RuntimeError('Full result requires actual sealed named NPC arrival and unique rewards')
        if F3_GOALS[6] not in report.get('initial_completed', []):
            if not report.get('phase_two_observed') or not report.get('actual_damage_samples'):
                raise RuntimeError('New victory must show actual phase2 and original HP reductions')
        if F3_GOALS[2] not in report.get('initial_completed', []):
            abilities = report.get('actual_abilities', [])
            if (not any(row.get('accepted') and row.get('ability') == 'echo' for row in abilities)
                    or not any(row.get('accepted') and row.get('ability') == 'growth' for row in abilities)):
                raise RuntimeError('New isolation needs original actual growth and9 input evidence')
    intentional_stage = (bool(report.get('requested_stage_stopped')) and args.stop_after != 'complete'
                         and args.stop_after in report.get('reached_stages', [])
                         and len(completed) >= MIN_GOALS[args.stop_after])
    print(json.dumps({'complete': complete, 'requested_stage_stopped': intentional_stage,
        'requested_stage': args.stop_after, 'reached_stages': report.get('reached_stages'),
        'phase': report.get('phase'), 'seconds': report.get('seconds'), 'goal_count': len(completed),
        'stop_reason': report.get('stop_reason'), 'evidence': str(evidence), 'profile': PROFILE,
        'own_folder': own_folder, 'native_exit': report.get('native_exit'),
        'failures': report.get('failures', []), 'engine_errors': report.get('engine_errors', []),
        'actual_distance_m': report.get('actual_distance_m'),
        'actual_damage_samples': len(report.get('actual_damage_samples', []))}, ensure_ascii=False))
    if (report.get('profile') != PROFILE or report.get('source_report') != SOURCE_REPORT
            or report.get('source_report_sha256') != SOURCE_REPORT_SHA256
            or report.get('source_receipts_sha256') != FIFTYEIGHT_DIGEST
            or report.get('requested_stage') != args.stop_after):
        raise RuntimeError('Observer source identity/stage differs from actual pinned58')
    if (execution_failure is not None or not process or not process.get('passed')
            or process.get('remaining_owned_processes', 0) != 0 or before != after or not own_folder
            or report.get('failures') or report.get('engine_errors')
            or not preservation_valid(report) or not native_exit_valid(report)
            or not (complete or intentional_stage)):
        raise SystemExit(1)


if __name__ == '__main__':
    main()
