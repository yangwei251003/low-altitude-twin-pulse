"""Archive/check P11 evidence only. Never imports Blender or writes asset bytes."""
from pathlib import Path
import hashlib, json, sys
from datetime import datetime, timezone

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
GLB = ROOT / 'assets/v3/candidates/root_buttress_h10_p11/root_buttress_h10_p11.glb'
EXPECTED = {
    'asset_sources/v3/root_buttress/p11/root_buttress_h10_complete_p11.blend': 'b5ec56780e72dc12edc40b1651c518e12ed68e6243b62a50a0415ef0bb8f960c',
    'asset_sources/v3/root_buttress/p11/root_buttress_h10_p11_export_ready.blend': '8246fb6291399652fedea84be33d23f66064816c4fdf768f1674962bea6bfb96',
    str(GLB.relative_to(ROOT)).replace('\\', '/'): 'd8e67fdaef057a9adb9fb10545eda90d867d730cb446511f735cfbd42d486f1f',
    'asset_sources/v3/root_buttress/p10/root_buttress_h10_refined_cliff_p10.blend': 'add3d91567c459dce50a301f38a238b9c39dd738a83289cb4c33b4aa683dc855',
    'asset_sources/v3/shore_root/p9/rigid_root_main_form.blend': 'adc2218b773bef0e4b7f4a37339fe1c79abab3e0311a42014b318e6d3b2a2ed2',
    'references/v3/production/root_buttress/root_buttress_reference_v1.png': 'f8484936f0a15fd8afc7219d81b03af5b0d3c6b40b2e8e1105dfd978d8469675',
    'asset_sources/v3/root_buttress/p8/vendor/rock_face_01/rock_face_01_1k.gltf': '96c332c01d173a2431115f3bac29be101fba341e5500e2a08e384f4edd17299e',
    'asset_sources/v3/root_buttress/p8/vendor/rock_face_01/rock_face_01.bin': '873eac0319333e92bc96ddeedf8ebf69dc3c68ff1dfe32d8c14ddc165cdb20ac',
    'asset_sources/third_party/island_tree_01/island_tree_01_1k.gltf': 'a8dd768c33037151f7a86293744c5cf7fae8eeb7a04b6e35719179b9943170c6',
    'asset_sources/third_party/island_tree_01/island_tree_01.bin': '1faa817b46e24ed6fc90d3ec72188a0dc5ac75e82c89b3dd3c5fdaecf7cc005c',
    'assets/v3/root_buttress/root_buttress_h10.glb': 'ceaae98c56aa8fa3517d43a11708c352e8741fa801d78a24eba87871a8d29d53',
    'assets/v3/root_buttress/root_buttress_h12.glb': '85f1d453724b22d379b7313f23aaf0ce2d3090e8b1bc033827bb8bfab36ad536',
    'assets/v3/root_buttress/root_buttress_h17.glb': 'fd876e8ec85c736f325c4af8ae8d64ab19a24b4e8f1334bd2a422ec9b0d0545a',
    'assets/v3/root_buttress/root_buttress_h3.glb': '46eb968ed292cd9e2b74715433c30f19a51080379fc8f018cbd29109df72552b',
}

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def record(path, purpose):
    return {'path': path.relative_to(ROOT).as_posix(), 'absolute_path': path.as_posix(),
            'sha256': sha(path), 'bytes': path.stat().st_size, 'purpose': purpose}

def role(path):
    rel = path.relative_to(HERE).as_posix()
    if rel.startswith('visual_reject_'):
        return 'historical visual reject; not the final source/candidate'
    if path.name == 'h10_p11_same_byte_glb_preview.png':
        return 'actual frozen GLB reimport offline CPU image; not game camera'
    if path.name == 'h10_p11_complete_material_source.png':
        return 'final editable source offline CPU image; not GLB or game camera'
    if path.parent.name == 'textures':
        return 'external PBR source map; Sap original copy or actual stone/bark atlas bake'
    if path.suffix == '.blend':
        return 'editable author source or explicit baked export-ready source'
    if 'node_name_failure' in path.name:
        return 'historical node-name failure evidence; subsequently fixed'
    return 'P11 construction, interface or validation evidence'

manifest_path = HERE / 'manifest.json'
if '--check' not in sys.argv:
    own = [p for p in HERE.rglob('*') if p.is_file() and '__pycache__' not in p.parts
           and p.name not in {'manifest.json', 'selfcheck.json'} and p.suffix != '.blend1']
    deps = [ROOT / p for p in EXPECTED if not p.startswith('asset_sources/v3/root_buttress/p11/') and ROOT / p != GLB]
    deps += [HERE.parent / 'p3/textures' / p for p in ['RB_Stone_BaseColor_P3.png', 'RB_Bark_BaseColor_P3.png']]
    manifest = {
        'stage': 'P11 frozen complete single-height candidate; pending actual Godot review, not final art',
        'created_utc': datetime.now(timezone.utc).isoformat(),
        'files': [record(p, role(p)) for p in sorted(own)] + [record(GLB, 'frozen explicit H10 candidate GLB; no runtime P2 replacement')],
        'readonly_dependencies': [record(p, 'readonly upstream reference/source or frozen runtime control') for p in deps],
        'image_provenance': {
            'h10_p11_complete_material_source.png': {'input': 'root_buttress_h10_complete_p11.blend', 'input_sha256': EXPECTED['asset_sources/v3/root_buttress/p11/root_buttress_h10_complete_p11.blend'], 'method': 'Cycles CPU 2 threads offline source render'},
            'h10_p11_same_byte_glb_preview.png': {'input': GLB.relative_to(ROOT).as_posix(), 'input_sha256': EXPECTED[GLB.relative_to(ROOT).as_posix()], 'method': 'delete source objects, actual GLB import, same studio camera/lights; CPU offline', 'report': 'p11_glb_readback.json'},
        },
        'licenses': [
            {'asset': 'Rock Face 01', 'url': 'https://polyhaven.com/a/rock_face_01', 'authors': ['Dario Barresi'], 'license': 'CC0', 'license_url': 'https://polyhaven.com/license', 'adaptation': 'sampled natural wall, authored closed volume and local fractures'},
            {'asset': 'Island Tree 01', 'url': 'https://polyhaven.com/a/island_tree_01', 'authors': ['Rico Cilliers', 'Rob Tuytel'], 'license': 'CC0', 'license_url': 'https://polyhaven.com/license', 'adaptation': 'wood primitive fork cut/capped, flattened and conformed; not an untouched scan'},
        ],
        'exclusions': ['Blender automatic .blend1 backup', '__pycache__', 'manifest and selfcheck (avoid recursive hash)'],
        'limits': ['not final artistic acceptance', 'no Godot camera or full Crown sweep performed by this agent for P11', 'no performance/human-comfort result'],
    }
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
checks = []
def check(name, result, detail=None):
    checks.append({'name': name, 'pass': bool(result), 'detail': detail})

for item in manifest['files'] + manifest['readonly_dependencies']:
    p = ROOT / item['path']
    check('file:' + item['path'], p.is_file() and sha(p) == item['sha256'] and p.stat().st_size == item['bytes'])
for rel, expected in EXPECTED.items():
    check('frozen:' + rel, (ROOT / rel).is_file() and sha(ROOT / rel) == expected)
source = json.loads((HERE / 'p11_source_report.json').read_text(encoding='utf-8'))
readback = json.loads((HERE / 'p11_glb_readback.json').read_text(encoding='utf-8'))
bake = json.loads((HERE / 'p11_bake_report.json').read_text(encoding='utf-8'))
export = json.loads((HERE / 'p11_export_report.json').read_text(encoding='utf-8'))
check('source_16_actual_checks', source['all_pass'] and source['passed'] == source['total'] == 16 and all(c['pass'] for c in source['checks']))
check('readback_37_actual_checks', readback['all_pass'] and readback['passed'] == readback['total'] == 37 and all(c['pass'] for c in readback['checks']))
check('report_glb_hash_matches_frozen_file', readback['glb_sha256'] == export['glb_sha256'] == sha(GLB))
check('source_hash_matches_bake_and_export', source['source_sha256'] == bake['source_sha256'] == export['source_sha256'] == sha(HERE / 'root_buttress_h10_complete_p11.blend'))
check('ready_hash_matches_bake_and_readback', readback['ready_source_sha256'] == bake['ready_source_sha256'] == export['ready_source_sha256'] == sha(HERE / 'root_buttress_h10_p11_export_ready.blend'))
check('source_removed_before_actual_import', readback['source_deleted_before_import'])
check('bake_geometry_preserved', bake['source_geometry_unchanged'] and export['source_geometry_unchanged_through_bake'])
check('triangles_meshes', readback['triangles'] == 63996 and len(readback['meshes']) == 3)
for item in bake['atlas_maps'] + bake['sap_maps']:
    p = Path(item['file'])
    if not p.is_absolute(): p = ROOT / p
    check('baked_texture:' + p.name, p.is_file() and sha(p) == item['sha256'])
for name, marker in [('build_source.log', 'Blender quit'), ('bake_p11.log', 'P11_BAKE_ONLY_DONE_NO_RUNTIME_WRITE'), ('export_p11.log', 'Blender quit'), ('verify_p11.log', 'P11_SAME_BYTE_READBACK_DONE')]:
    content = (HERE / name).read_text(encoding='utf-8', errors='replace')
    check('completed_log:' + name, marker in content and 'Traceback (most recent call last)' not in content)
result = {'stage': 'lightweight frozen artifact integrity; no Blender or game launched', 'checked_utc': datetime.now(timezone.utc).isoformat(),
          'manifest_sha256': sha(manifest_path), 'candidate_sha256': sha(GLB), 'checks': checks,
          'passed': sum(c['pass'] for c in checks), 'total': len(checks), 'all_pass': all(c['pass'] for c in checks)}
(HERE / 'selfcheck.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({k: result[k] for k in ['passed', 'total', 'all_pass', 'manifest_sha256', 'candidate_sha256']}, ensure_ascii=False))
if not result['all_pass']:
    print(json.dumps([c for c in checks if not c['pass']], ensure_ascii=False))
    raise SystemExit(1)
