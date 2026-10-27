"""Pure inventory contract. No Blender or production files are changed by this module."""
from pathlib import Path
import hashlib
import json

OUT = Path(__file__).resolve().parent
SOURCE = OUT.parent / 'revision_v5'
SOURCE_SHA = '5f09e7feb7c03d346a98c199d34fa710fc3444537e055bf2c07f4f1a97532efe'
WORLD_ORIGIN = [7.0, 5.0, -6.0]
PIVOTS = {
    'Doors/DoorLeft': [-2.55, 0.0, -.43],
    'Doors/DoorRight': [2.55, 0.0, -.43],
    'Furniture/Stretcher': [3.2, 0.0, -2.2],
    'Furniture/TreatmentBed': [4.3, 0.0, -2.25],
    'Furniture/ReceptionDesk': [0.0, 0.0, -3.15],
}
ANCHORS = {
    'CheckPoint': [0.0, .8, 3.0],
    'DoorOpening': [0.0, 1.4, 0.0],
    'WestJoin': [-5.0, 0.0, 2.0],
    'EastExit': [5.0, 0.0, 2.0],
    'InteriorLightDesk': [0.0, 2.82, -2.75],
    'InteriorLightBeds': [3.2, 2.82, -2.1],
}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def group_for(name):
    """Exhaustive, disjoint semantic ownership; unknown meshes must stop export."""
    if name == 'FrontDeck_existing_interface': return 'Structure/FloorFront'
    if name == 'RearDeck_PROPOSED_not_integrated': return 'Structure/FloorRear'
    for side in ('Left', 'Right'):
        if name.startswith('Door' + side):
            assert name[len('Door' + side):] in ('Bottom', 'Glass', 'Top', 'EdgeL', 'EdgeR'), name
            return 'Doors/Door' + side + ('/Glazing' if name.endswith('Glass') else '/Solid')
    if name in ('FrontWindowLeft', 'FrontWindowRight', 'EastWindow'): return 'Glazing/StaticWindows'
    for prefix, path in (
        ('RearRoofLeft_', 'Occlusion/RearRoofLeft'), ('RearRoofRight_', 'Occlusion/RearRoofRight'),
        ('CanopyLeft_', 'Occlusion/CanopyLeft'), ('CanopyRight_', 'Occlusion/CanopyRight'),
        ('Stretcher', 'Furniture/Stretcher'), ('TreatmentBed', 'Furniture/TreatmentBed'),
        ('ReceptionDesk', 'Furniture/ReceptionDesk'),
    ):
        if name.startswith(prefix): return path
    if name.startswith('ReceptionSign') or name == 'ReceptionChineseLabel': return 'Occlusion/MedicalSign'
    if name == 'ReceptionLight': return 'Lighting/ReceptionStatus'
    if name.startswith('InteriorLamp'):
        assert name.endswith(('Desk', 'Beds')), name
        return 'Lighting/InteriorFixture' + ('Desk' if name.endswith('Desk') else 'Beds')
    if name.startswith(('DoorJamb', 'DoorHeader', 'DoorTrack')): return 'Structure/DoorFrame'
    if name.startswith('FrontPost'): return 'Structure/FrontPosts'
    if name.startswith('CornerPost'): return 'Structure/CornerPosts'
    if name.startswith(('Window', 'FacadeEdge', 'EastWindow')): return 'Structure/WindowFrames'
    if name.startswith('RearDrain'): return 'Structure/Drainage'
    if name.startswith(('FrontSill', 'FrontHeader', 'DoorPocket', 'RearInner', 'RearWall', 'WestInner', 'WestWall', 'EastWall')):
        return 'Structure/ShellWalls'
    raise ValueError('Unclassified source mesh: ' + name)


def collision_for(path):
    if path.startswith(('Lighting/', 'Occlusion/MedicalSign')): return 'visual_only'
    if path.startswith('Doors/'): return 'moving_triangle_mesh_including_glass'
    if path.startswith('Furniture/'): return 'independent_triangle_mesh'
    return 'static_triangle_mesh'


def union(rows):
    return {'min': [min(r['min'][i] for r in rows) for i in range(3)],
            'max': [max(r['max'][i] for r in rows) for i in range(3)]}


def inventory():
    assert sha(SOURCE / 'clinic_reception_v5.blend') == SOURCE_SHA, 'Frozen V5 blend changed'
    report = json.loads((SOURCE / 'reception_v5_geometry.json').read_text(encoding='utf-8'))
    assert all(report['checks'].values()) and report['mesh_count'] == 186
    groups = {}
    for row in report['actual_bounds']:
        path = group_for(row['name'])
        groups.setdefault(path, []).append(row)
    result = {}
    for path, rows in sorted(groups.items()):
        local = union(rows)
        world = {key: [v + WORLD_ORIGIN[i] for i, v in enumerate(local[key])] for key in ('min', 'max')}
        result[path] = {'meshes': [r['name'] for r in rows], 'mesh_count': len(rows),
                        'source_local_aabb': local, 'source_world_aabb': world,
                        'collision_role': collision_for(path)}
    return {'status': 'prepared_from_actual_frozen_source_report_not_exported',
            'root': 'ClinicReception', 'world_origin': WORLD_ORIGIN, 'groups': result,
            'pivots_local': PIVOTS, 'anchors_local': ANCHORS,
            'mesh_count': 186, 'source_local_aabb': union(report['actual_bounds']),
            'source_manifest': {p.name: {'sha256': sha(p), 'bytes': p.stat().st_size}
                                for p in sorted(SOURCE.iterdir()) if p.is_file()},
            'limits': ['AABBs are diagnostics, not collider recipes',
                       'Rear floor support is proposed and needs root integration',
                       'Door animation and collision following are not implemented by this asset',
                       'Normal roof retains physical collision when visually faded',
                       'No GLB, game capture or human validation has run for this delivery']}


if __name__ == '__main__':
    (OUT / 'prepared_contract.json').write_text(json.dumps(inventory(), ensure_ascii=False, indent=2), encoding='utf-8')
    print('PREPARED_INVENTORY: 186 source meshes classified; no Blender or export run')
