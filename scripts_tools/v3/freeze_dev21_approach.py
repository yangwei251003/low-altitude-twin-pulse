"""Freeze a named actual approach capture, reusing verified immutable inputs."""
import argparse
import json
import shutil
import hashlib
from pathlib import Path
from freeze_dev19_checkpoint import ROOT, BASE, TREE, sha, finish


def freeze(stamp, expected_pass):
    source = ROOT / 'artifacts/v3/art' / ('clinic-integrated-' + stamp)
    dest = ROOT / 'docs/v3/evidence/dev21-approach' / stamp
    assert not dest.exists(), 'Refuse overwrite'
    report = json.loads((source / 'state_checks.json').read_text(encoding='utf8'))
    assert report['passed'] is expected_pass
    assert report['input_sha256_before'] == report['input_sha256_after']
    # Reuse an exact retained file only after verifying its current original
    # bytes. Never make an evidence record depend on a mutable working asset.
    known = {}
    for manifest in (ROOT / 'docs/v3/evidence').rglob('manifest.json'):
        data = json.loads(manifest.read_text(encoding='utf8'))
        if not isinstance(data, dict):
            continue
        for row in data.get('files', []):
            if not isinstance(row, dict) or 'path' not in row or 'sha256' not in row:
                continue
            candidate = manifest.parent / row['path']
            if candidate.is_file():
                known.setdefault(row['sha256'], candidate)
    records = []
    for resource, expected in report['input_sha256_before'].items():
        relative = resource.removeprefix('res://')
        original = ROOT / relative
        assert sha(original) == expected, relative
        raw = original.read_bytes()
        oid = hashlib.sha1(b'blob ' + str(len(raw)).encode() + b'\0' + raw).hexdigest()
        row = {'resource': relative, 'sha256': expected, 'bytes': len(raw)}
        if TREE.get(relative) == oid:
            row.update(source_commit=BASE, git_blob=oid)
        elif expected in known and sha(known[expected]) == expected:
            row['frozen_path'] = known[expected].relative_to(ROOT).as_posix()
        else:
            target = dest / 'source' / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(original, target)
            assert sha(target) == expected
            row['frozen_path'] = target.relative_to(ROOT).as_posix()
        records.append(row)
    shutil.copytree(source, dest / 'capture')
    log = ROOT / 'artifacts/v3' / ('dev21-approach-capture-' + stamp + '.log')
    shutil.copy2(log, dest / log.name)
    finish(dest, 'Source MAIN Compatibility720p approach reuse, real original physics and water commit. Frozen poses and shape sweeps; not human flight, performance, final art or a new standalone package.', records,
           {'run': stamp, 'passed': report['passed'], 'checks': len(report['checks']),
            'shots': len(report['shots']), 'art_accepted': False,
            'root_viewed': ['17-I2-service-court.png', '19-I2-receiving-approach.png', '20-I2-approach-joint.png'],
            'failed_checks': [row for row in report['checks'] if not row['passed']]})


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('stamp')
    parser.add_argument('--passed', action='store_true')
    args = parser.parse_args()
    freeze(args.stamp, args.passed)
