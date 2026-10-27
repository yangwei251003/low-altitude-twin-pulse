"""Freeze the actual dev19 ENet run and separate, unintegrated bridge/action candidates."""
from pathlib import Path
import hashlib
import json
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
BASE = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
TREE = {}
for row in subprocess.check_output(['git', 'ls-tree', '-rz', BASE], cwd=ROOT).split(b'\0'):
    if row:
        head, name = row.split(b'\t', 1)
        TREE[name.decode('utf-8')] = head.split()[2].decode()


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def preserve(dest, relative, source, expected):
    assert sha(source) == expected, relative
    raw = source.read_bytes()
    oid = hashlib.sha1(b'blob ' + str(len(raw)).encode() + b'\0' + raw).hexdigest()
    row = {'resource': relative, 'sha256': expected, 'bytes': len(raw)}
    if TREE.get(relative) == oid:
        row.update(source_commit=BASE, git_blob=oid)
    else:
        target = dest / 'source' / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.exists():
            assert sha(target) == expected
        else:
            shutil.copy2(source, target)
        row['frozen_path'] = target.relative_to(ROOT).as_posix()
    return row


def finish(dest, scope, records, extra):
    files = [{'path': p.relative_to(dest).as_posix(), 'bytes': p.stat().st_size, 'sha256': sha(p)}
             for p in sorted(dest.rglob('*')) if p.is_file()]
    manifest = {'scope': scope, 'baseline': BASE, 'input_resources': records, **extra, 'files': files}
    (dest / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'directory': dest.name, 'files': len(files), 'inputs': len(records),
                      'bytes': sum(p['bytes'] for p in files), 'manifest_sha256': sha(dest / 'manifest.json')}))


def enet():
    dest = ROOT / 'docs/v3/evidence/dev19-enet'
    assert not dest.exists(), 'Refuse overwrite'
    runs = ['20261019_054941_319164', '20261019_055235_917460', '20261019_055701_296176', '20261019_055758_878401']
    outer = ['dev19-distribution-enet-20261019_054941_bbaccc.log',
             'dev19-distribution-enet-reference-20261019_055235_e91141.log',
             'dev19-distribution-enet-aligned-20261019_055701_fb6dd6.log',
             'dev19-distribution-enet-cavity-20261019_055758_83f185.log']
    final = json.loads((ROOT / 'artifacts/v3/network/distribution' / runs[-1] / 'summary.json').read_text(encoding='utf-8'))
    assert final['passed'] and len(final['checks']) == 38 and len(final['scenarios']) == 3
    assert final['source_sha256_before'] == final['source_sha256_after']
    records = [preserve(dest, rel, ROOT / rel, expected) for rel, expected in final['source_sha256_before'].items()]
    for run, log in zip(runs, outer):
        source = ROOT / 'artifacts/v3/network/distribution' / run
        summary = json.loads((source / 'summary.json').read_text(encoding='utf-8'))
        assert summary['source_sha256_before'] == summary['source_sha256_after']
        # Only the two orchestration/probe files changed between these runs.
        for rel, expected in summary['source_sha256_before'].items():
            if expected == final['source_sha256_before'].get(rel):
                continue
            assert sha(source / 'failed-inputs' / Path(rel).name) == expected, (run, rel)
        shutil.copytree(source, dest / 'runs' / run)
        (dest / 'logs').mkdir(exist_ok=True)
        shutil.copy2(ROOT / 'artifacts/v3' / log, dest / 'logs' / log)
    finish(dest, 'Source protocol18 actual same-machine ENet; distribution operations with trial third-stream recovery. Scripted prior27 goals and checked pilot poses; no active remote Trial flow/gauge, two-PC, GPU, human or performance acceptance.', records,
           {'final_run': runs[-1], 'checks': 38, 'scenarios': 3, 'max_snapshot_bytes': 852,
            'failed_input_note': 'Each prior run contains its exact changed driver/probe. Every other input matches the final manifest.'})


def candidates():
    dest = ROOT / 'docs/v3/evidence/dev19-access-candidates'
    assert not dest.exists(), 'Refuse overwrite'
    entries = {'tests_v3/test_shared_access_bridge.gd', 'tests_v3/test_distribution_action.gd', 'project.godot'}
    queue = list(entries)
    while queue:
        rel = queue.pop()
        if not rel.endswith(('.gd', '.tscn')): continue
        for found in re.findall(r'res://([^"\s]+\.(?:gd|json|tscn))', (ROOT / rel).read_text(encoding='utf-8-sig')):
            if found not in entries and (ROOT / found).is_file():
                entries.add(found)
                queue.append(found)
    records = [preserve(dest, rel, ROOT / rel, sha(ROOT / rel)) for rel in sorted(entries)]
    for name in ['shared-access-bridge-first-run-20261019_054032_adf306', 'shared-access-bridge-route-failure-20261019_054450_f26252']:
        shutil.copytree(ROOT / 'artifacts/v3' / name, dest / name)
    (dest / 'logs').mkdir(exist_ok=True)
    for name in ['shared-access-bridge-first-20261019_054032_adf306.log', 'shared-access-bridge-lifecycle-fixed-20261019_054450_f26252.log',
                 'shared-access-bridge-handle-fixed-20261019_054751_92c775.log', 'distribution-action-data-20261019_055930_bd5093.log']:
        shutil.copy2(ROOT / 'artifacts/v3' / name, dest / 'logs' / name)
    finish(dest, 'Unintegrated bridge actual physical tests191 and pure Director candidate110. No Story/Store/LAN integration or visual acceptance. Failed lifecycle/blocked handle source preserved.', records,
           {'input_note': 'Source closure preserved after runs; not runtime self-fingerprints. The action and bridge are not loaded into the eight-action production campaign.'})


if __name__ == '__main__':
    enet()
    candidates()
