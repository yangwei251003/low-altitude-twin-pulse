"""Preserve source-development evidence, including rejected runs; never export a game."""
import json
import shutil
from freeze_dev19_checkpoint import ROOT, sha, preserve, finish


def visuals():
    dest = ROOT / 'docs/v3/evidence/dev20-bridge-visual'
    assert not dest.exists(), 'Refuse overwrite'
    runs = [
        ('20261019_063731_19aecd', 'shared-access-integrated-20261019_063731_19aecd.log'),
        ('20261019_064011_10c196', 'dev20-shared-access-visual-20261019_064011_10c196.log'),
        ('20261019_065015_cc9d1b', 'dev20-shared-cutaway-20261019_065015_cc9d1b.log'),
        ('20261019_065738_168e37', 'dev20-bridge-ui-visual-20261019_065738_168e37.log'),
    ]
    evidence = []
    for stamp, log in runs:
        source = ROOT / 'artifacts/v3/art' / ('shared-access-integrated-' + stamp)
        state = json.loads((source / 'state_checks.json').read_text(encoding='utf-8'))
        target = dest / stamp
        shutil.copytree(source, target / 'capture')
        shutil.copy2(ROOT / 'artifacts/v3' / log, target / log)
        records = []
        for resource, expected in state['input_sha256_before'].items():
            relative = resource.removeprefix('res://')
            captured = source / 'captured-source' / relative
            input_path = captured if captured.is_file() else ROOT / relative
            records.append(preserve(target, relative, input_path, expected))
        assert state['input_sha256_before'] == state['input_sha256_after']
        if stamp == runs[-1][0]:
            assert state['passed'] and len(state['shots']) == 7
            assert state['physical_probes']['bridge_cutaway']['edges_intact']
        finish(target, 'Actual source MAIN Compatibility720p images and physical/save checks; graybox, not final art, human play or performance.', records,
               {'original_output': state['output'], 'passed': state['passed'], 'checks': len(state['checks']), 'shots': len(state['shots'])})
        evidence.append({'run': stamp, 'passed': state['passed'], 'shots': len(state['shots']), 'checks': len(state['checks'])})
    finish(dest, 'Four actual source capture iterations: motor endpoint failure, unfaded bridge, cutaway, then protected edges and honest interaction labels. Root reviewed final seven images.', [],
           {'runs': evidence, 'final_run': runs[-1][0], 'art_accepted': False})


def integration():
    dest = ROOT / 'docs/v3/evidence/dev20-integration'
    assert not dest.exists(), 'Refuse overwrite'
    entries = [
        'tests_v3/test_facility_contract.gd', 'tests_v3/test_i2_result_ledger.gd',
        'tests_v3/test_facility_registry.gd', 'tests_v3/test_shared_access_session.gd',
        'tests_v3/test_shared_access_bridge.gd', 'tests_v3/test_distribution_action_integration.gd',
        'tests_v3/test_clinic_progress.gd', 'tests_v3/test_clinic_session.gd',
        'scripts_tools/v3/dev.py', 'scripts_tools/v3/test_distribution_lan.py',
    ]
    records = [preserve(dest, relative, ROOT / relative, sha(ROOT / relative)) for relative in entries]
    # Logs name their actual phase; early tests predate later view-only changes.
    logs = sorted((ROOT / 'artifacts/v3').glob('dev20-*.log'))
    (dest / 'logs').mkdir(parents=True, exist_ok=True)
    for source in logs:
        shutil.copy2(source, dest / 'logs' / source.name)
    for name in [
        'facility-contract-reference-parse-failure', 'dev20-action-first-failure',
        'shared-access-trial-conflict-20261019_0630', 'shared-access-cantilever-test-first',
        'dev20-ui-radio-fixture-failure',
    ]:
        shutil.copytree(ROOT / 'artifacts/v3' / name, dest / 'failures' / name)
    finish(dest, 'Source integration and staged regressions. Final action121, history122 and clinic143; physical bridge232 predates protected visual edge additions. No headless test is graphics, LAN or fun evidence.', records,
           {'source_note': 'Listed QA inputs are the final source versions; earlier failures preserve their own source. Full production closure is preserved by actual final GPU and ENet input fingerprints, separately.',
            'final_action_log': 'dev20-bridge-ui-action-20261019_065738_168e37.log'})


def deduplicate_visual_inputs():
    """One exact-byte copy per input, including ignored .godot import products.

    Only removes duplicate copies created inside this evidence/source subtree,
    after verifying the retained copy. Original project/artifact files are read-only.
    """
    dest = (ROOT / 'docs/v3/evidence/dev20-bridge-visual').resolve()
    pool = dest / 'input_blobs'
    pool.mkdir(exist_ok=True)
    for manifest in sorted(dest.glob('*/manifest.json')):
        data = json.loads(manifest.read_text(encoding='utf-8'))
        target = manifest.parent
        for row in data['input_resources']:
            if 'frozen_path' not in row: continue
            original = (ROOT / row['frozen_path']).resolve()
            allowed = (target / 'source').resolve()
            assert original.is_relative_to(allowed) and original.is_file()
            assert sha(original) == row['sha256']
            captured = target / 'capture/captured-source' / row['resource']
            kept = captured if captured.is_file() and sha(captured) == row['sha256'] else pool / (row['sha256'] + '.bin')
            if not kept.exists(): shutil.copy2(original, kept)
            assert sha(kept) == row['sha256'] and kept.stat().st_size == row['bytes']
            row['frozen_path'] = kept.relative_to(ROOT).as_posix()
            original.unlink()  # Exact duplicate in our newly generated archive only.
        # Rebuild the file list after deduplication; input references may point to
        # the parent shared pool, which is fully hashed by its parent manifest.
        extra = {k:v for k,v in data.items() if k not in ['files','input_resources','baseline','scope']}
        manifest.unlink()
        finish(target, data['scope'], data['input_resources'], extra)
    parent = json.loads((dest/'manifest.json').read_text(encoding='utf-8'))
    extra = {k:v for k,v in parent.items() if k not in ['files','input_resources','baseline','scope']}
    # finish must not fingerprint its own previous manifest.
    (dest/'manifest.json').unlink()
    finish(dest, parent['scope'], [], extra)


if __name__ == '__main__':
    visuals()
    deduplicate_visual_inputs()
    integration()
