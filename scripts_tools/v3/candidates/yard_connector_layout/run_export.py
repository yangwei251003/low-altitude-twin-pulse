"""One explicitly authorized read-only Godot export; CPU2/private job/60s.

Never invoked by import. Production files and original mesh/collision are not
written. Logs and selected source snapshots stay in this candidate's evidence.
"""
from __future__ import annotations

import ctypes
import datetime
import hashlib
import json
from pathlib import Path
import sys
import uuid

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[4]
BASE = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / 'scripts_tools/v3'))
import dev
from build_blender_input import convert


def main():
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.GetCurrentProcess.restype = ctypes.c_void_p
    kernel.SetProcessAffinityMask.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
    if not kernel.SetProcessAffinityMask(kernel.GetCurrentProcess(), 3):
        raise ctypes.WinError(ctypes.get_last_error())
    label = datetime.datetime.now().strftime('%Y%m%d_%H%M%S') + '_' + uuid.uuid4().hex[:6]
    output = BASE / 'exports' / label
    evidence = ROOT / 'tests_v3/candidates/yard_connector_layout/evidence' / label
    evidence.mkdir(parents=True, exist_ok=False)
    contract = json.loads((BASE / 'input_contract.json').read_text(encoding='utf-8'))
    paths = sorted(set(contract['geometry_inputs_sha256']) | {
        'project.godot', 'scripts_tools/v3/dev.py',
        *[p.relative_to(ROOT).as_posix() for p in BASE.iterdir()
          if p.is_file() and p.suffix in ('.gd', '.json', '.py', '.md')],
    })

    def hashes():
        return {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in paths}

    before = hashes()
    for path in paths:
        dest = evidence / 'source' / path
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes((ROOT / path).read_bytes())
    # Read-only imported asset provenance; never duplicate large GLBs.
    asset_sha = {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                 for p in sorted((ROOT / 'assets/v3').rglob('*'))
                 if p.is_file() and p.suffix in ('.glb', '.gltf')}
    dev.EVIDENCE = evidence
    process = None
    try:
        process = dev.execute(['--headless', '--script',
            'res://scripts_tools/v3/candidates/yard_connector_layout/export_yard_connector.gd',
            '--', '--output=res://' + output.relative_to(ROOT).as_posix()], 'engine', 60)
        manifest = json.loads((output / 'geometry.json').read_text(encoding='utf-8'))
        if not manifest['ok'] or not process['passed']:
            raise RuntimeError('export not successful')
        derived = convert(output / 'geometry.json')
        (evidence / 'derivation.json').write_text(json.dumps(derived, indent=2), encoding='utf-8')
    finally:
        after = hashes()
        report = {'before': before, 'after': after, 'unchanged': before == after,
                  'glb_input_sha256': asset_sha, 'process': process,
                  'output': output.relative_to(ROOT).as_posix(),
                  'scope': 'Selected geometry/tool inputs snapshotted; all V3 GLB/glTF hashes recorded. No gameplay ticks, collision replacement, render or art verdict.'}
        (evidence / 'inputs.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps({'process': process, 'evidence': str(evidence),
                      'output': str(output), 'derived': derived,
                      'selected_inputs_unchanged': before == after}, ensure_ascii=False, indent=2))
    if before != after:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
