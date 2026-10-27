"""Pure Python preparation only. Does not open Blender or write runtime assets."""
from pathlib import Path
import json, hashlib

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
P1 = HERE.parent / 'p1'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    report = json.loads((P1/'uv_readback_corrected/geometry_report.json').read_text(encoding='utf-8'))
    assert len(report['checks']) == 211 and all(c['passed'] for c in report['checks'])
    assembly = json.loads((P1/'north_joint_visible_review/report.json').read_text(encoding='utf-8'))
    assert len(assembly['checks']) == 21 and all(c['passed'] for c in assembly['checks'])
    source = P1/'uv_readback_corrected/editable_source.blend'
    assert sha(source) == report['blend_sha256']
    groups = {'FloorSurface': {'size': 2048, 'material': 'EastMaintenance_FloorPBR', 'pieces': []},
              'InspectionBand': {'size': 1024, 'material': 'EastMaintenance_InspectionPBR', 'pieces': []}}
    for part in report['parts']:
        key = 'FloorSurface' if part['role'] == 'concrete' or part['name'] == 'ShallowSeals' else 'InspectionBand'
        groups[key]['pieces'].append({'name': part['name'], 'triangles': part['triangles']})
    for group in groups.values():
        group['triangles'] = sum(p['triangles'] for p in group['pieces'])
    points = [point for part in report['parts'] for point in part['bounds_local_blender']]
    bb = [[min(p[i] for p in points) for i in range(3)], [max(p[i] for p in points) for i in range(3)]]
    gd_bounds = [[bb[0][0], bb[0][2], -bb[1][1]], [bb[1][0], bb[1][2], -bb[0][1]]]
    prepared = json.loads((P1/'prepared.json').read_text(encoding='utf-8'))
    legacy = ROOT/'asset_sources/v3/i2_maintenance_paving/delivery_p3/contract.json'
    old = json.loads(legacy.read_text(encoding='utf-8'))
    inputs = {name: data['sha256'] for name, data in prepared['inputs'].items()}
    inputs.update(old['frozen_inputs'])
    for f in [source, P1/'uv_readback_corrected/geometry_report.json', P1/'north_joint_visible_review/report.json',
              legacy, legacy.parent/'build_delivery.py', P1/'build_source.py', P1/'plan.py']:
        inputs[f.relative_to(ROOT).as_posix()] = sha(f)
    for name, expected in inputs.items():
        assert sha(ROOT/name) == expected, name
    cfg = {'status': 'STATIC_PREPARED_NOT_BAKED_OR_EXPORTED', 'source': source.relative_to(ROOT).as_posix(),
           'source_sha256': sha(source), 'source_geometry_uv_signature': report['source_readback'],
           'root': 'EastMaintenanceExtension', 'world_origin_godot': [20.7, 0, 8.8],
           'local_bounds_godot': gd_bounds, 'triangles': report['triangles'], 'groups': groups,
           'body_holes': report['body_holes'], 'net_paving_m2': report['net_paving_m2'],
           'frozen_inputs': inputs,
           'scope': 'Explicit standard GLB candidate, two meshes/two materials. No colliders, no runtime install.',
           'method': 'Reuse frozen maintenance native EMIT/NORMAL bake and exact binary GLB readback. Separate 2K/1K UV0 atlases; source UV layers retained through baking.'}
    (HERE/'contract.json').write_text(json.dumps(cfg, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({'groups': {k: {'pieces': len(g['pieces']), 'triangles': g['triangles'], 'atlas': g['size']} for k,g in groups.items()},
                      'triangles': cfg['triangles'], 'bounds': gd_bounds, 'frozen_inputs': len(inputs)}))


if __name__ == '__main__':
    main()
