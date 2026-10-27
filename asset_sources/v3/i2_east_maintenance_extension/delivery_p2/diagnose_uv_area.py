"""Read-only files; temporary copies measure every assigned UV triangle.

No Blender checkpoint, rendering, bake, image editing or export. Original
source bytes remain frozen. Small positive faces are never discarded here.
"""
from collections import Counter
from fractions import Fraction
from pathlib import Path
import datetime
import json
import math
import os
import struct
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import prepare_uv as P

RAW_UVS = {}
AREA_THRESHOLD_PX2 = 1e-10


def signed_area_exact(points):
    a, b, c = [[Fraction(float(v)) for v in p] for p in points]
    return ((b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0]))/2


def f32(value):
    return struct.unpack('<f', struct.pack('<f', value))[0]


def f32_ulp(value):
    absolute = abs(f32(value))
    bits = struct.unpack('<I', struct.pack('<f', absolute))[0]
    return struct.unpack('<f', struct.pack('<I', bits+1))[0]-absolute


def observe_assignment(chart, face, loop, before_storage, after_storage):
    key = (chart['obj'].name, loop)
    assert key not in RAW_UVS, 'A source corner assigned by more than one UV island'
    assert tuple(f32(v) for v in before_storage) == after_storage, 'Recorded pre-write UV does not produce actual float32 storage'
    RAW_UVS[key] = (before_storage, after_storage)


def classification(area3d_mathutils, projection_area, raw_area, stored_area, numeric_area):
    reasons = []
    if area3d_mathutils <= 0: reasons.append('mathutils_3d_area_nonpositive')
    if projection_area == 0: reasons.append('projection_exactly_zero_before_atlas')
    elif projection_area < 0: reasons.append('projection_negative_winding')
    if raw_area == 0: reasons.append('atlas_double_input_exactly_zero')
    elif raw_area < 0: reasons.append('atlas_double_input_negative_winding')
    if stored_area == 0: reasons.append('float32_stored_uv_exactly_zero')
    elif stored_area < 0: reasons.append('float32_stored_uv_negative_winding')
    elif numeric_area <= AREA_THRESHOLD_PX2: reasons.append('positive_stored_uv_below_script_numeric_floor_not_zero')
    return reasons


def inspect_all(charts, size, group):
    failures, reason_counts = [], Counter()
    examined = 0
    min_positive = {'area_3d_m2': math.inf, 'raw_uv_area_px2': math.inf, 'stored_uv_area_px2': math.inf}
    for chart in charts:
        obj, faces = chart['obj'], set(chart['faces'])
        mesh = obj.data
        mesh.calc_loop_triangles()
        for index, tri in enumerate(mesh.loop_triangles):
            if tri.polygon_index not in faces: continue
            examined += 1
            points = [tuple(float(v) for v in mesh.vertices[i].co) for i in tri.vertices]
            cross3d = P.CLEAN.cross_exact(points)
            area3d = math.sqrt(sum(float(c)**2 for c in cross3d))/2
            assert area3d > 0, 'Approved zero cleanup unexpectedly left a geometrically zero triangle'
            vectors = [mesh.vertices[i].co for i in tri.vertices]
            area_mathutils = (vectors[1]-vectors[0]).cross(vectors[2]-vectors[0]).length/2
            projected = [P.project(mesh.vertices[i].co, chart['axis'], chart['sign']) for i in tri.vertices]
            projection_area = signed_area_exact(projected)
            raw = [RAW_UVS[(obj.name, i)][0] for i in tri.loops]
            actual = [tuple(mesh.uv_layers[P.UV].data[i].uv) for i in tri.loops]
            assert actual == [RAW_UVS[(obj.name, i)][1] for i in tri.loops]
            assert all(math.isfinite(v) and 0 <= v <= 1 for p in actual for v in p)
            raw_px = [tuple(v*size for v in p) for p in raw]
            actual_px = [tuple(v*size for v in p) for p in actual]
            raw_area, stored_area = signed_area_exact(raw_px), signed_area_exact(actual_px)
            numeric_area = P.AG.cross(*actual_px)/2
            min_positive['area_3d_m2'] = min(min_positive['area_3d_m2'], area3d)
            if raw_area > 0: min_positive['raw_uv_area_px2'] = min(min_positive['raw_uv_area_px2'], float(raw_area))
            if stored_area > 0: min_positive['stored_uv_area_px2'] = min(min_positive['stored_uv_area_px2'], float(stored_area))
            # The exact original failing predicate, plus explicitly distinguish
            # zero/negative projection and float32 storage. Never relabel a
            # positive exact value as zero just because it is sub-pixel.
            reasons = classification(area_mathutils, projection_area, raw_area, stored_area, numeric_area)
            if not reasons: continue
            reason_counts.update(reasons)
            lengths = [math.dist(points[i-1], points[i]) for i in range(3)]
            polygon = mesh.polygons[tri.polygon_index]
            normal = [float(c)/(2*area3d) for c in cross3d]
            record = {
                'object': obj.name, 'source_piece': obj['source_piece'], 'chart': chart['id'],
                'category': chart['category'], 'requested_px_m': chart['density'], 'atlas_size': size,
                'triangle_index_after_authorized_cleanup': index,
                'polygon_index_after_authorized_cleanup': tri.polygon_index,
                'vertex_ids': list(tri.vertices), 'loop_ids': list(tri.loops),
                'vertices_local_blender': points,
                'vertices_world_godot': [[p[0]+20.7, p[2], -p[1]+8.8] for p in points],
                'coordinate_float32_ulps_m': [[f32_ulp(v) for v in p] for p in points],
                'vertex_bounds_local_blender': [[min(p[k] for p in points) for k in range(3)],
                                                [max(p[k] for p in points) for k in range(3)]],
                'edge_lengths_m': lengths, 'shortest_altitude_m': 2*area3d/max(lengths),
                'area_3d_m2_exact_cross_evaluated_double': area3d,
                'cross_3d_exact_rational': [str(c) for c in cross3d],
                'area_3d_m2_mathutils_original_guard': area_mathutils,
                'geometric_unit_normal': normal, 'cached_polygon_normal': list(polygon.normal),
                'projection_axis': chart['axis'], 'projection_sign': chart['sign'],
                'projected_points_m': projected,
                'projected_area_m2_exact': str(projection_area),
                'projected_area_m2': float(projection_area),
                'uv_before_storage': raw, 'uv_after_float32_storage': actual,
                'uv_storage_absolute_errors': [[abs(a-b) for a, b in zip(r, q)] for r, q in zip(raw, actual)],
                'uv_storage_float32_ulps': [[f32_ulp(v) for v in p] for p in actual],
                'raw_uv_area_exact': str(raw_area/(size*size)),
                'stored_uv_area_exact': str(stored_area/(size*size)),
                'raw_continuous_coverage_px2': abs(float(raw_area)),
                'stored_continuous_coverage_px2': abs(float(stored_area)),
                'raw_signed_area_px2_exact': str(raw_area),
                'stored_signed_area_px2_exact': str(stored_area),
                'stored_signed_area_px2_original_double_guard': numeric_area,
                'raw_pixel_centres_covered': P.AG.occupied_pixels([raw_px], size) if raw_area > 0 else 0,
                'stored_pixel_centres_covered': P.AG.occupied_pixels([actual_px], size) if stored_area > 0 else 0,
                'pixel_coverage_scope': 'Level-0 mathematical triangle coverage, no bake dilation or filter. Zero pixel centres does not mean zero continuous area.',
                'original_guard_area_floor_px2': AREA_THRESHOLD_PX2,
                'overlap_helper_cross_floor_px2': 1e-10,
                'overlap_helper_equivalent_signed_area_floor_px2': 5e-11,
                'reasons': reasons,
                'same_face_triangle_indices': [i for i, t in enumerate(mesh.loop_triangles) if t.polygon_index == tri.polygon_index],
                'same_face_vertex_ids': list(polygon.vertices),
                'same_face_vertices_local_blender': [list(mesh.vertices[i].co) for i in polygon.vertices],
            }
            failures.append(record)
    detail = {'group': group, 'triangles_examined': examined, 'failed_triangles': len(failures),
              'reason_counts': dict(reason_counts), 'min_positive_values': min_positive,
              'failures': failures,
              'threshold_origin': {'value_px2': AREA_THRESHOLD_PX2,
                                   'location': 'prepare_uv.py inspect_atlas, check_area > 1e-10',
                                   'source': 'Local script numeric floor chosen during atlas validation; not a Blender/Godot/glTF limit and not a geometric-zero definition',
                                   'decision': 'Diagnosis does not lower this bound or delete nonzero faces.'}}
    P.save(group+'_uv_area_failures.json', detail)
    return {k: v for k, v in detail.items() if k != 'failures'}


def main():
    output = HERE/('uv_area_diagnosis_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    output.mkdir()
    P.HERE = output
    print(json.dumps({'stage': 'uv_area_diagnostic_output', 'pid': os.getpid(), 'output': str(output)}), flush=True)
    try:
        report = P.main(diagnostic_inspector=inspect_all, uv_observer=observe_assignment)
        print(json.dumps({'stage': 'all_uv_triangles_diagnosed', 'groups': report['groups'],
                          'report': str(output/'uv_diagnosis_report.json')}), flush=True)
    except Exception as error:
        P.save('diagnostic_interrupted.json', {'error': repr(error), 'checks': P.CHECKS,
                                              'scope': 'Partial diagnostic only; no saved Blender checkpoint, image, bake or export'})
        raise


if __name__ == '__main__':
    main()
