"""Read-only source/GLB analysis and rectangular budget; never imports bpy.

Writes only this candidate directory. Rectangles budget future UV charts;
they are not an executed Blender unwrap or a bake-quality claim.
"""
from pathlib import Path
import hashlib
import importlib.util
import json
import math
import statistics
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
SOURCE = HERE.parent/'p1/uv_readback_corrected/geometry_report.json'
OLD = ROOT/'assets/v3/i2_maintenance_paving/maintenance_paving.glb'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    obj = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(obj)
    return obj


def measure_old():
    reader = module('read_actual_glb', ROOT/'asset_sources/v3/clinic_ground/delivery_p2/read_glb.py')
    _, meshes, _, _ = reader.read(OLD)
    results = {}
    for name, mesh in meshes.items():
        densities = []
        area_sum = uv_sum = 0.0
        for tri, count in mesh['corner_uv'].items():
            a, b, c = tri
            e = [b[i]-a[i] for i in range(3)]
            f = [c[i]-a[i] for i in range(3)]
            cross = [e[1]*f[2]-e[2]*f[1], e[2]*f[0]-e[0]*f[2], e[0]*f[1]-e[1]*f[0]]
            length = math.sqrt(sum(x*x for x in cross))
            if length < 1e-12 or abs(cross[1])/length < .99 or min(v[1] for v in tri) < -.01201:
                continue
            area = length/2
            uv_area = abs((b[3]-a[3])*(c[4]-a[4])-(b[4]-a[4])*(c[3]-a[3]))/2
            assert uv_area > 0
            densities.extend([2048*math.sqrt(uv_area/area)]*count)
            area_sum += area*count
            uv_sum += uv_area*count
        results[name] = {'area_m2': area_sum, 'uv_area': uv_sum,
                         'min_px_m': min(densities), 'median_px_m': statistics.median(densities),
                         'max_px_m': max(densities)}
    return results


def pack(rectangles, width, height):
    """Fixed-size, optional quarter-turn rectangles. No implicit rescaling."""
    free = [(0, 0, width, height)]
    placed = []
    for name, w, h in sorted(rectangles, key=lambda r: max(r[1:]), reverse=True):
        options = []
        for index, (x, y, fw, fh) in enumerate(free):
            for tw, th, rotate in [(w, h, False), (h, w, True)]:
                if tw <= fw and th <= fh:
                    options.append((min(fw-tw, fh-th), max(fw-tw, fh-th), index, tw, th, rotate))
        if not options:
            return None
        _, _, index, w, h, rotate = min(options)
        x, y, _, _ = free[index]
        placed.append({'name': name, 'rect_px': [x, y, w, h], 'quarter_turn': rotate})
        next_free = []
        for fx, fy, fw, fh in free:
            if x >= fx+fw or x+w <= fx or y >= fy+fh or y+h <= fy:
                next_free.append((fx, fy, fw, fh))
                continue
            if x > fx: next_free.append((fx, fy, x-fx, fh))
            if x+w < fx+fw: next_free.append((x+w, fy, fx+fw-x-w, fh))
            if y > fy: next_free.append((fx, fy, fw, y-fy))
            if y+h < fy+fh: next_free.append((fx, y+h, fw, fy+fh-y-h))
        free = [a for i, a in enumerate(next_free) if not any(
            i != j and a[0] >= b[0] and a[1] >= b[1]
            and a[0]+a[2] <= b[0]+b[2] and a[1]+a[3] <= b[1]+b[3]
            and (a != b or i > j) for j, b in enumerate(next_free))]
    for i, a in enumerate(placed):
        x, y, w, h = a['rect_px']
        assert x >= 0 and y >= 0 and x+w <= width and y+h <= height
        for b in placed[i+1:]:
            bx, by, bw, bh = b['rect_px']
            assert x+w <= bx or bx+bw <= x or y+h <= by or by+bh <= y
    return placed


def plan_areas():
    plan = module('frozen_geometry_plan', HERE.parent/'p1/plan.py')
    parts, _ = plan.build()
    groups = {g: {'up_m2': 0.0, 'down_m2': 0.0, 'side_m2': 0.0} for g in ['floor', 'inspection']}
    objects = {}
    for part in parts:
        g = 'floor' if part['name'] in ['FullBearingBed', 'ShallowSeals'] or part['name'].startswith(('Bank', 'Service', 'ClearRoute')) else 'inspection'
        values = {'up_m2': 0.0, 'down_m2': 0.0, 'side_m2': 0.0}
        for face in part['faces']:
            a, b, c = [part['vertices'][i] for i in face[:3]]
            e = [b[i]-a[i] for i in range(3)]
            f = [c[i]-a[i] for i in range(3)]
            v = [e[1]*f[2]-e[2]*f[1], e[2]*f[0]-e[0]*f[2], e[0]*f[1]-e[1]*f[0]]
            # The frozen pre-bevel plan consists of axis-aligned rectangles.
            area = math.sqrt(sum(x*x for x in v))
            key = 'up_m2' if v[2] > .99*area else 'down_m2' if v[2] < -.99*area else 'side_m2'
            values[key] += area
            groups[g][key] += area
        objects[part['name']] = values
    return {'scope': 'Exact pre-bevel plan areas, not final evaluated mesh areas; 20 fasteners excluded.',
            'groups': groups, 'FullBearingBed': objects['FullBearingBed'], 'InspectionBed': objects['InspectionBed']}


def main():
    contract = json.loads((HERE.parent/'delivery_p1/contract.json').read_text(encoding='utf-8'))
    before = {p: sha(ROOT/p) for p in contract['frozen_inputs']}
    assert before == contract['frozen_inputs']
    source = json.loads(SOURCE.read_text(encoding='utf-8'))
    floor = []
    for obj in source['parts']:
        if not obj['name'].startswith(('Bank', 'Service', 'ClearRoute')):
            continue
        lo, hi = obj['bounds_local_blender']
        # Each chart has 5px padding: 10px between rectangles, >=8px required.
        floor.append((obj['name'], math.ceil((hi[0]-lo[0])*175)+10, math.ceil((hi[1]-lo[1])*175)+10))
    floor_positions = pack(floor, 2032, 1720)
    assert floor_positions is not None and len(floor_positions) == 9
    inspection = []
    for obj in source['parts']:
        if obj['name'].startswith('SolidCover'):
            lo, hi = obj['bounds_local_blender']
            inspection.append((obj['name'], math.ceil((hi[0]-lo[0])*275)+10, math.ceil((hi[1]-lo[1])*275)+10))
    inspection_positions = pack(inspection, 640, 1008)
    assert inspection_positions is not None and len(inspection_positions) == 10
    result = {
        'status': 'CPU_BUDGET_ONLY_NO_BLENDER_NO_NEW_UV',
        'prior_runtime_glb': {'path': str(OLD.relative_to(ROOT)).replace('\\', '/'), 'sha256': sha(OLD), 'top_density': measure_old()},
        'pre_bevel_areas': plan_areas(),
        'floor': {'atlas_size': 2048, 'top_target_px_m': 175, 'side_target_px_m': 64,
                  'seal_target_px_m': 96, 'buried_target_px_m': 16,
                  'top_zone_px': [8, 8, 2032, 1720], 'bottom_reserve_px': [8, 1736, 2032, 304],
                  'placed_padded_top_rectangles': floor_positions,
                  'scope': 'Nine real broad-top bounds fit; seals/sides/buried charts require actual extraction and final packing.'},
        'inspection': {'atlas_size': 1024, 'cover_top_target_px_m': 275, 'frame_top_target_px_m': 275,
                       'side_target_px_m': 128, 'buried_target_px_m': 24,
                       'minimum_visible_fastener_cap_pixels': 8,
                       'cover_zone_px': [8, 8, 640, 1008], 'detail_reserve_px': [656, 8, 360, 1008],
                       'placed_padded_cover_rectangles': inspection_positions,
                       'scope': 'Ten real cover bounds fit; frames split into four edge-strip charts, never whole empty ring bounding boxes. All actual detail charts still need final packing.'},
        'spacing': {'chart_padding_px': 5, 'guaranteed_rect_gap_px': 10, 'required_actual_island_gap_px': 8,
                    'atlas_outer_border_px': 8, 'bake_dilation_px': 4},
        'invariants': ['All 16728 source triangles unchanged', 'SourceUV/ConcreteUV/PaintUV unchanged',
                       'No overlapping bake islands', 'No shape/position/collider/image-pixel changes',
                       'Only DeliveryUV on new copies may change'],
        'inputs': before, 'inputs_unchanged': before == {p: sha(ROOT/p) for p in before},
    }
    assert result['inputs_unchanged']
    path = HERE/'static_atlas_plan.json'
    path.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    assert json.loads(path.read_text(encoding='utf-8')) == result
    print(json.dumps({'status': result['status'], 'inputs_unchanged': True, 'inputs': len(before),
                      'floor_top_rectangles': 9, 'inspection_cover_rectangles': 10,
                      'sha256': sha(path)}, ensure_ascii=False))


if __name__ == '__main__':
    main()
