"""CPU-only selective artifact manifest. No engine, image changes, git or shared writes."""
from pathlib import Path
import hashlib
import json

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
BASE = HERE.parent


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def rel(path):
    return Path(path).relative_to(ROOT).as_posix()


def main():
    source = BASE / 'p1'
    reference = ROOT / 'references/v3/production/clinic_lift_deck'
    candidate = ROOT / 'assets/v3/candidates/clinic_lift_deck/clinic_lift_deck.glb'
    report = json.loads((HERE / 'export_report.json').read_text(encoding='utf-8'))
    raw = json.loads((HERE / 'raw_glb_report.json').read_text(encoding='utf-8'))
    selected = set()
    def add(path):
        path = Path(path)
        assert path.is_file(), path
        assert path.is_relative_to(BASE) or path.is_relative_to(reference) or path == candidate
        selected.add(path)
    for name in ('ASSET_CARD.md', 'layout_readback.json'):
        add(BASE / name)
    for path in source.glob('*.py'):
        add(path)
    for name in ('material_config.json', 'prepared_manifest.json', 'geometry_report.json',
                 'source_report.json', 'reopen_validation.json', 'clinic_lift_deck_editable.blend',
                 '01-single-object.png'):
        add(source / name)
    for folder in (source / 'source_inputs', source / 'provenance', reference,
                   HERE / 'textures', HERE / 'source_inputs'):
        for path in folder.iterdir():
            if path.is_file():
                add(path)
    for path in HERE.glob('*.py'):
        add(path)
    for name in ('README.md', 'bake_report.json', 'export_report.json', 'raw_glb_report.json',
                 'expected_runtime_triangles.json', 'clinic_lift_deck_delivery.blend', 'clinic_lift_deck.glb'):
        add(HERE / name)
    add(candidate)
    runs = [source / 'run_preview_20261020_084108_253921',
            HERE / 'run_bake_20261020_085005_807909',
            HERE / 'run_export_20261020_085458_575278']
    snapshot_equivalents = []
    process = []
    for run in runs:
        add(run / 'process.json')
        add(run / 'engine.log')
        row = json.loads((run / 'process.json').read_text(encoding='utf-8'))
        assert row['exit_code'] == 0 and row['remaining_owned_processes'] == 0
        assert not row.get('error_lines', [])
        process.append({'path': rel(run / 'process.json'), **row})
        for snapshot in (run / 'input_snapshot').iterdir():
            canonical = run.parent / snapshot.name
            assert canonical in selected and sha(snapshot) == sha(canonical), snapshot
            snapshot_equivalents.append({'original_snapshot': rel(snapshot),
                                         'selected_equivalent': rel(canonical),
                                         'sha256': sha(snapshot), 'equal': True})
    assert sha(source / 'clinic_lift_deck_editable.blend') == report['source_sha256']
    assert sha(candidate) == sha(HERE / 'clinic_lift_deck.glb') == report['sha256']
    assert sha(HERE / 'clinic_lift_deck_delivery.blend') == report['delivery_blend_sha256']
    for row in report['reopened_images']:
        path = Path(row['path'])
        assert path in selected and sha(path) == row['sha256'], path
    entries = [{'path': rel(path), 'bytes': path.stat().st_size, 'sha256': sha(path)}
               for path in sorted(selected)]
    result = {
        'schema': 1,
        'asset': 'ClinicLiftDeck',
        'route_id': '5e455d78-37b2-423b-b660-0cc3185eae49',
        'status': 'SOURCE_APPROVED_BAKED_GLB_NUMERIC_READBACK_PASS_GAME_REVIEW_PENDING',
        'root': 'ClinicLiftDeck',
        'identity_hierarchy': True,
        'origin': 'Existing moving_bodies.Deck centre, not world origin',
        'mesh_triangles': report['mesh_triangles'],
        'total_triangles': raw['triangles'],
        'actual_godot_local_AABB': raw['AABB'],
        'materials': 2,
        'embedded_pngs': 6,
        'source_sha256': report['source_sha256'],
        'glb_sha256': report['sha256'],
        'candidate_path': rel(candidate),
        'readback_errors': report['same_byte_reimport'],
        'raw_normal_errors': raw['source_errors'],
        'source_and_five_original_images_unchanged': True,
        'no_extra_render_after_source_approval': True,
        'no_game_engine_used_by_asset_agent': True,
        'known_limits': ['Cool uniform grey steel and weak top-fastener contrast accepted for MAIN review',
                         'Paint Normal neutral; no claimed visible paint microbump',
                         'No AO baked: occupied ORM R=1 and no GLB occlusion texture',
                         'Source high tread only in Normal, low plate 1.5mm below conservative original collider top'],
        'environment_dependencies_not_modified': [
            {'path': 'scripts_tools/v3/dev.py', 'sha256_at_freeze': sha(ROOT / 'scripts_tools/v3/dev.py')},
            {'executable': 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe',
             'CPU_threads': 2}],
        'source_snapshot_equivalents': snapshot_equivalents,
        'processes': process,
        'excluded': ['UV_checkpoint.blend', 'bake_checkpoint.blend', 'bake_complete.blend',
                     'delivery_p1/clinic_lift_deck_editable.blend', 'source_diagnostic_checkpoint.blend',
                     '*.blend1', 'duplicate input_snapshot copies', 'other frozen assets'],
        'selected_file_count': len(entries),
        'selected_total_bytes': sum(entry['bytes'] for entry in entries),
        'files': entries,
        'manifest_self_hash': 'Not recursive; send separately to Root',
    }
    manifest = HERE / 'manifest.json'
    manifest.write_text(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False) + '\n', encoding='utf-8')
    readback = json.loads(manifest.read_text(encoding='utf-8'))
    for entry in readback['files']:
        path = ROOT / entry['path']
        assert path.stat().st_size == entry['bytes'] and sha(path) == entry['sha256']
    print(json.dumps({'manifest': str(manifest), 'manifest_sha256': sha(manifest),
                      'files': len(entries), 'bytes_excluding_manifest': result['selected_total_bytes'],
                      'readback': 'ALL_SELECTED_BYTES_VERIFIED'}, ensure_ascii=False))


if __name__ == '__main__':
    main()
