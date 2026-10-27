"""Read-only natural-wood pose search, preserving ratios and branch curvature.

Only outputs in p9. No Blender, rendering, runtime files or texture work.
"""
import os
os.environ['OPENBLAS_NUM_THREADS'] = '1'
os.environ['OMP_NUM_THREADS'] = '1'
import hashlib
import json
import math
import struct
import argparse
from pathlib import Path
import numpy as np

OUT = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('--x-max', type=float, default=None)
parser.add_argument('--output', default='rigid_pose_search.json')
options = parser.parse_args()
assert Path(options.output).name == options.output
PROJECT = OUT.parents[3]
VENDOR = PROJECT/'asset_sources/third_party/island_tree_01'
GLTF = VENDOR/'island_tree_01_1k.gltf'
BIN = VENDOR/'island_tree_01.bin'
data = json.loads(GLTF.read_text(encoding='utf-8'))


def decode(aid):
    a = data['accessors'][aid]
    v = data['bufferViews'][a['bufferView']]
    n = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3}[a['type']]
    fmt = {5126: 'f', 5125: 'I', 5123: 'H'}[a['componentType']]
    s = struct.Struct('<'+fmt*n)
    stride = v.get('byteStride', s.size)
    with BIN.open('rb') as f:
        f.seek(v.get('byteOffset', 0)+a.get('byteOffset', 0))
        blob = f.read(stride*(a['count']-1)+s.size)
    return [s.unpack_from(blob, i*stride) for i in range(a['count'])]


pos = np.array(decode(0), dtype=np.float64)
idx = np.array(decode(3), dtype=np.int32).reshape(-1, 3)
assert idx.shape[0] == 34787
source_hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in [GLTF, BIN]}


def clip_polygon(points, height, keep_above, axis=1):
    out = []
    for a, b in zip(points, points[1:]+points[:1]):
        da, db = a[axis]-height, b[axis]-height
        ia = da >= 0 if keep_above else da <= 0
        ib = db >= 0 if keep_above else db <= 0
        if ia:
            out.append(a)
        if ia != ib:
            out.append(a+(b-a)*(-da/(db-da)))
    return out


def crop(low, high):
    points = []
    face_ids = []
    for i, face in enumerate(idx):
        tri = [pos[int(j)] for j in face]
        if min(v[1] for v in tri) > high or max(v[1] for v in tri) < low:
            continue
        polygon = clip_polygon(tri, low, True)
        polygon = clip_polygon(polygon, high, False) if polygon else []
        if polygon and options.x_max is not None:
            polygon = clip_polygon(polygon, options.x_max, False, axis=0)
        if len(polygon) >= 3:
            points.extend(polygon)
            face_ids.append(i)
    return np.unique(np.array(points), axis=0), face_ids


def pose_matrix(downward_degrees, roll_degrees):
    t, r = math.radians(downward_degrees), math.radians(roll_degrees)
    direction = np.array([-math.cos(t), -math.sin(t), 0.0])
    side0 = np.array([0.0, 0.0, 1.0])
    normal0 = np.cross(side0, direction)
    side = side0*math.cos(r)+normal0*math.sin(r)
    normal = normal0*math.cos(r)-side0*math.sin(r)
    return np.column_stack((side, direction, normal))


LIMIT_MIN = np.array([-4.5, .02, -6.0])
LIMIT_MAX = np.array([4.5, 4.95, 6.0])
DESIRED_BASE = np.array([3.6, 4.15, 0.0])
results = []
for high in [2.2, 2.4]:
    low = .1
    points, face_ids = crop(low, high)
    base_points = points[points[:, 1] < .15]
    pivot = np.array([np.median(base_points[:, 0]), low, np.median(base_points[:, 2])])
    rel = points-pivot
    poses = []
    feasible_count = 0
    for scale in [3.0, 3.25, 3.5, 3.75, 4.0]:
        for tilt in range(10, 46, 5):
            for roll in range(0, 360, 10):
                rotation = pose_matrix(tilt, roll)
                assert abs(np.linalg.det(rotation)-1) < 1e-9
                moved = (rel@rotation.T)*scale
                lo, hi = moved.min(axis=0), moved.max(axis=0)
                dimensions = hi-lo
                span_excess = np.maximum(0, dimensions-(LIMIT_MAX-LIMIT_MIN))
                feasible = bool(np.all(span_excess < 1e-8))
                tmin, tmax = LIMIT_MIN-lo, LIMIT_MAX-hi
                if feasible:
                    translation = np.clip(DESIRED_BASE, tmin, tmax)
                    feasible_count += 1
                else:
                    # Centre the excess rather than hiding it outside report bounds.
                    translation = (LIMIT_MIN+LIMIT_MAX-lo-hi)*.5
                world = moved+translation
                base_world = world[points[:, 1] < .15]
                tips_world = world[points[:, 1] > high-.025]
                # The high cut is only a sampling family, not proof of root contact.
                low_tip_count = int(np.sum(tips_world[:, 1] < 1.4))
                high_base_error = abs(translation[0]-DESIRED_BASE[0])+1.8*abs(translation[1]-DESIRED_BASE[1])
                score = 40*float(span_excess.sum())+high_base_error
                if world[:, 0].min() > -3:
                    score += (world[:, 0].min()+3)*2
                if low_tip_count == 0:
                    score += 2
                poses.append({
                    'scale_uniform': scale, 'downward_degrees': tilt, 'roll_degrees': roll,
                    'rotation_gltf_to_godot_rows': rotation.tolist(),
                    'source_pivot_gltf': pivot.tolist(), 'translated_base_pivot_godot': translation.tolist(),
                    'bounds_godot': {'min': world.min(axis=0).tolist(), 'max': world.max(axis=0).tolist()},
                    'dimensions_xyz': dimensions.tolist(), 'span_excess_xyz': span_excess.tolist(),
                    'fits_full_9x12x4_93_envelope': feasible,
                    'base_fragment_bounds_godot': {'min': base_world.min(axis=0).tolist(), 'max': base_world.max(axis=0).tolist()},
                    'cut_tip_sample_bounds_godot': {'min': tips_world.min(axis=0).tolist(), 'max': tips_world.max(axis=0).tolist()},
                    'tip_vertices_below_y1_4': low_tip_count,
                    'bridge_anchor_local': [4.5, 4.5, 0],
                    'nearest_sampled_base_vertex_to_bridge_anchor_m': float(np.linalg.norm(base_world-np.array([4.5, 4.5, 0]), axis=1).min()),
                    'score_for_selection_only': score})
    poses.sort(key=lambda item: item['score_for_selection_only'])
    results.append({'source_clip_gltf_y': [low, high],
                    'source_clip_gltf_x_max': options.x_max,
                    'bounds_gltf': {'min': points.min(axis=0).tolist(), 'max': points.max(axis=0).tolist()},
                    'clipped_unique_points_including_edge_intersections': len(points),
                    'source_face_ids_intersecting_crop': face_ids,
                    'poses_scanned': len(poses), 'full_envelope_feasible_count': feasible_count,
                    'best_poses': poses[:12]})
report = {
    'scope': 'P9 numerical rigid pose search only; no Blender, terrain, contact or visual approval',
    'source': 'mesh0 primitive0 Island Tree 01; original glTF metre coordinates',
    'vendor_sha256': source_hashes, 'triangle_source_count': len(idx),
    'target_engineering_envelope': {'min': LIMIT_MIN.tolist(), 'max': LIMIT_MAX.tolist()},
    'results': results,
    'limits': ['Only an explicit source X maximum may clip two measured fine side branches; other branches remain included.',
               'A fitting AABB cannot prove supported root tips or interface contact.',
               'Nearest vertex distance is only an interface-gap diagnostic, not a mesh distance or collision guarantee.',
               'No stretching or bending is applied. This is numerical clipping only, not a finished mesh edit.']}
(OUT/options.output).write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
assert source_hashes == {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in [GLTF, BIN]}
for result in results:
    best = result['best_poses'][0]
    print(json.dumps({'clip': result['source_clip_gltf_y'], 'scanned': result['poses_scanned'],
        'fits': result['full_envelope_feasible_count'], 'best': best}, ensure_ascii=False))
