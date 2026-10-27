"""Selective read-back freeze after completed Blender delivery; no engine calls."""
from pathlib import Path
import hashlib
import json
import shutil
from datetime import datetime, timezone

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[3]
EXPECTED = '19ce8114fdd7f6d3a3c8c991db2cee1ee12cffc9113d1a14f7fd0d92dc0e8de9'

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def row(path):
    return {'path': path.relative_to(ROOT).as_posix(), 'bytes': path.stat().st_size,
            'sha256': digest(path)}

def copy_once(src, dst):
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists():
        assert digest(dst) == digest(src), str(dst)
    else:
        shutil.copyfile(src, dst)
    assert digest(dst) == digest(src)

def main():
    assert ROOT.name == '低空小队-两界共脉', str(ROOT)
    assert not (OUT/'manifest.json').exists(), 'Frozen delivery manifest exists'
    candidate = ROOT/'assets/v3/candidates/canal_calibration_rack/calibration_rack.glb'
    assert digest(candidate) == digest(OUT/'calibration_rack.glb') == EXPECTED
    provenance = [
        ('asset_sources/third_party/ambientCG/Metal012_1K-PNG/provenance.json', 'ambientCG_Metal012_provenance.json'),
        ('references/v3/production/clinic_pump_shell/provenance.json', 'paint_atlas_provenance.json'),
        ('references/v3/production/clinic_pump_shell/prompt_atlas_v2.txt', 'paint_atlas_prompt_v2.txt'),
        ('references/v3/production/canal_calibration/rack-p1.prompt.txt', 'rack_reference_prompt.txt'),
    ]
    for original, name in provenance:
        copy_once(ROOT/original, OUT/'provenance'/name)
    names = [
        'README.md', 'ACTUAL_REVIEW.md', 'PLAN.md', 'freeze_delivery.py',
        'calibration_rack_editable.blend', 'calibration_rack_delivery.blend',
        'calibration_rack.glb', 'bake_complete.blend', 'bake_manifest.json',
        'bake_report.json', 'bake_texture_inspection.json', 'editable_source_report.json',
        'expected_low_triangles.json', 'expected_runtime_triangles.json',
        'export_report.json', 'preview_report.json', 'raw_glb_report.json',
        'source_images.json', 'UV_report.json', 'prepared.json',
        'common.py', 'bake_source.py', 'export_asset.py', 'verify_export.py',
        'preview_glb.py', 'run_stage.py',
    ]
    files = [OUT/name for name in names]
    for folder in ('source_inputs', 'textures', 'provenance', 'same_byte_reimport'):
        files.extend(p for p in (OUT/folder).rglob('*') if p.is_file() and p.suffix != '.blend1')
    stages = []
    for folder in sorted(OUT.glob('run_*_20261020_*')):
        process = json.loads((folder/'process.json').read_text(encoding='utf-8'))
        assert process['passed'] and process['exit_code'] == 0
        assert process['remaining_owned_processes'] == 0 and not process['error_lines']
        stages.append({k: process[k] for k in ('stage', 'pid', 'elapsed_seconds', 'hard_seconds',
                                              'exit_code', 'remaining_owned_processes')})
        files.extend(p for p in folder.rglob('*') if p.is_file())
    external = [
        OUT.parent/'p4/preview_20261020_035045_756760/calibration_rack_p4_editable.blend',
        OUT.parent/'p4/preview_20261020_035045_756760/01_reference_oblique.png',
        ROOT/'references/v3/production/canal_calibration/rack-p1.png',
    ]
    files = sorted(set(files), key=lambda p: p.as_posix())
    records = [row(p) for p in files]
    raw = json.loads((OUT/'raw_glb_report.json').read_text(encoding='utf-8'))
    manifest = {
        'schema': 'calibration-rack-selective-delivery-1',
        'created_utc': datetime.now(timezone.utc).isoformat(),
        'routeId': '5e455d78-37b2-423b-b660-0cc3185eae49',
        'status': 'ROOT_REVIEWED_BLENDER_REIMPORT_ACCEPTED_FOR_GODOT_CANDIDATE',
        'not_claimed': ['Godot render acceptance', 'occupied/empty work-chain validation',
                        'collision or performance acceptance', 'whole-area final art'],
        'candidate_copy': row(candidate), 'root': raw['root'],
        'meshes': raw['nodes'], 'triangles': raw['triangles'], 'AABB': raw['AABB'],
        'stages': stages,
        'copied_provenance': [{'source': original, 'copy': 'provenance/'+name}
                              for original, name in provenance],
        'files': records, 'selected_file_count': len(records),
        'selected_bytes': sum(x['bytes'] for x in records),
        'external_frozen_inputs': [row(p) for p in external],
        'excluded': ['.blend1 backups', 'repeated checkpoints', 'rejected P1/P2/P3 directories'],
        'relative_dependencies': {'editable': 'source_inputs/', 'delivery': 'textures/',
                                  'GLB': 'six embedded PNGs', 'reimport': 'packed images'},
        'readback': 'All selected files and candidate copy byte count/SHA re-read after writing manifest.',
    }
    path = OUT/'manifest.json'
    path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    actual = json.loads(path.read_text(encoding='utf-8'))
    for item in actual['files'] + actual['external_frozen_inputs'] + [actual['candidate_copy']]:
        p = ROOT/item['path']
        assert p.stat().st_size == item['bytes'] and digest(p) == item['sha256'], item['path']
    print(json.dumps({'manifest': str(path), 'manifest_sha256': digest(path),
                      'files': len(records), 'bytes': actual['selected_bytes'],
                      'candidate': actual['candidate_copy'], 'readback_pass': True}, ensure_ascii=False))

if __name__ == '__main__':
    main()
