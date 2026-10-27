"""Run only the actual exported EXE/main-scene normal I1 -> first F1 observer."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import sys
import uuid

sys.dont_write_bytecode = True
import dev


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe', type=Path,
                        default=dev.ROOT / 'build/V3Development/LowAltitudeTwinPulse-Dev.exe')
    parser.add_argument('--seconds', type=int, default=300, choices=range(30, 301),
                        metavar='30..300')
    args = parser.parse_args()
    executable = args.exe.resolve(strict=True)
    if executable.suffix.lower() != '.exe' or 'godot' in executable.name.lower():
        parser.error('Use the actual exported game EXE, not the editor/runtime binary')
    stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S') + '_' + uuid.uuid4().hex[:8]
    profile = 'qa_normal_campaign_' + stamp
    evidence = dev.ROOT / 'artifacts/v3' / ('normal-campaign-' + stamp)
    evidence.mkdir(parents=True, exist_ok=False)
    output = evidence / ('normal-campaign-' + stamp + '.json')
    appdata = Path(os.environ['APPDATA'])
    for root in [appdata / 'LowAltitudeTwinPulseV3',
                 appdata / 'Godot/app_userdata/LowAltitudeTwinPulseV3']:
        if (root / 'profiles_v3' / profile).exists():
            raise RuntimeError('Refuse existing QA profile; no profile is deleted or reused')
    files = [executable]
    if executable.with_suffix('.pck').exists():
        files.append(executable.with_suffix('.pck'))
    source_names = [
        'scripts/v3/qa/twin_normal_campaign_qa.gd',
        'scripts/v3/twin_app.gd', 'scripts/v3/twin_session.gd',
        'scripts/v3/gameplay/twin_opening_story.gd',
        'scripts/v3/gameplay/twin_ability_rules.gd',
        'scripts/v3/gameplay/canal/canal_transport_physics/transport_pilot.gd',
        'data/v3/actions/opening_actions.json', 'data/v3/regions.json',
        'scripts_tools/v3/check_normal_campaign.py',
    ]
    files.extend(dev.ROOT / name for name in source_names)

    def hashes():
        return {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in files}

    before = hashes()
    command = [str(executable), '--', '--qa-normal-campaign',
               '--qa-profile=' + profile, '--qa-normal-output=' + str(output.resolve()),
               '--qa-normal-seconds=' + str(args.seconds)]
    (evidence / 'invocation.json').write_text(json.dumps({
        'command': command, 'profile': profile, 'output': str(output),
        'working_directory': str(executable.parent),
        'requested_seconds': args.seconds, 'job_timeout_seconds': args.seconds + 15,
        'initial_profile_checked_absent': True,
        'scope': 'Exported application default main scene and native physics. No --script, '
                 'scene override, external fixture progress/pose, headless mode, affinity, '
                 'graphics-quality override or whole-campaign claim.'
    }, ensure_ascii=False, indent=2), encoding='utf-8')
    dev.EVIDENCE = evidence
    process = None
    execution_failure = None
    project_root = dev.ROOT
    try:
        dev.ROOT = executable.parent  # Match launching the delivered EXE in its own folder.
        process = dev.execute_command(command, 'exported-main', args.seconds + 15)
    except SystemExit as error:
        execution_failure = error.code
    finally:
        dev.ROOT = project_root
        after = hashes()
        (evidence / 'inputs.json').write_text(json.dumps({
            'before': before, 'after': after, 'unchanged': before == after,
            'process': process, 'execution_failure': execution_failure,
            'artifact_sha256': before[str(executable)],
            'note': 'Source hashes identify the working tree only; only the EXE/PCK '
                    'hashes identify the actual executed artifact.'
        }, ensure_ascii=False, indent=2), encoding='utf-8')
    if not output.is_file():
        print(json.dumps({'complete': False, 'evidence': str(evidence),
                          'error': 'No observer result. CLI/import/runtime/process failure '
                                   'or timeout is incomplete, never a pass.'}, ensure_ascii=False))
        raise SystemExit(1)
    report = json.loads(output.read_text(encoding='utf-8-sig'))
    runtime_cwd = report.get('runtime_cwd', '')
    own_folder = bool(runtime_cwd) and os.path.normcase(os.path.realpath(runtime_cwd)) == os.path.normcase(os.path.realpath(executable.parent))
    print(json.dumps({
        'complete': report.get('first_segment_complete', False),
        'stop_reason': report.get('stop_reason'), 'phase': report.get('phase'),
        'seconds': report.get('seconds'), 'region': report.get('status', {}).get('region'),
        'completed': report.get('status', {}).get('completed', []),
        'failures': report.get('failures', []), 'engine_errors': report.get('engine_errors', []),
        'evidence': str(evidence), 'profile': profile,
        'runtime_cwd': runtime_cwd, 'own_folder': own_folder,
    }, ensure_ascii=False))
    if execution_failure is not None or before != after or not own_folder or not report.get('first_segment_complete') or report.get('failures') or report.get('engine_errors'):
        raise SystemExit(1)


if __name__ == '__main__':
    main()
