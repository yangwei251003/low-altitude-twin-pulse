"""One bounded continuation of the preserved P13 geometry, no mesh rebuild.

Diagnose the exact failed point against the saved triangle boundary first.
Only if it is outside may the same twelve cross sections exclude outside
samples. Every inside sample still requires an actual upper-surface ray hit.
"""
from pathlib import Path
import collections
import importlib.util
import json
import math
import os
import sys
import time
sys.dont_write_bytecode = True
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('p13_frozen_build', HERE / 'build_preview.py')
B = importlib.util.module_from_spec(spec)
spec.loader.exec_module(B)
PREVIOUS = HERE / 'source_run_20261019_213428_064334'
CHECKPOINT = PREVIOUS / 'geometry_checkpoint.blend'


def boundary_from_actual(soil):
    soil.data.calc_loop_triangles()
    points = B.actual_points(soil)
    top = [tuple(int(i) for i in t.vertices) for t in soil.data.loop_triangles
           if all(points[j].z > -.17 for j in t.vertices)]
    counts = collections.Counter()
    for a, b, c in top:
        for u, v in ((a, b), (b, c), (c, a)):
            counts[tuple(sorted((u, v)))] += 1
    edges = [e for e, n in counts.items() if n == 1]
    adjacency = {}
    for a, b in edges:
        adjacency.setdefault(a, []).append(b)
        adjacency.setdefault(b, []).append(a)
    assert edges and all(len(v) == 2 for v in adjacency.values())
    loop, previous = [min(adjacency)], None
    while True:
        current = loop[-1]
        nxt = next(i for i in adjacency[current] if i != previous)
        if nxt == loop[0]:
            break
        assert nxt not in loop
        loop.append(nxt)
        previous = current
    assert len(loop) == len(edges), 'Actual top must have one complete boundary, no interior holes.'
    return [B.H.gp(points[i]) for i in loop], top


def contains(loop, x, z):
    crossings, distance = 0, float('inf')
    for a, b in zip(loop, loop[1:] + loop[:1]):
        dx, dz = b[0] - a[0], b[2] - a[2]
        denom = dx * dx + dz * dz
        assert denom > 0
        t = max(0, min(1, ((x - a[0]) * dx + (z - a[2]) * dz) / denom))
        distance = min(distance, math.hypot(x - a[0] - t * dx, z - a[2] - t * dz))
        if (a[2] > z) != (b[2] > z):
            ix = a[0] + (z - a[2]) * dx / dz
            crossings += int(x < ix)
    return crossings % 2 == 1, distance


def main():
    started = time.time()
    frozen = json.loads((PREVIOUS / 'failure_manifest.json').read_text(encoding='utf-8'))
    for row in frozen['files']:
        assert B.sha(PREVIOUS / row['path']) == row['sha256'], row
    contract = json.loads((HERE / 'input_contract.json').read_text(encoding='utf-8'))
    for row in contract['files']:
        assert B.sha(B.ROOT / row['path']) == row['sha256'], row
    bpy.ops.wm.open_mainfile(filepath=str(CHECKPOINT))
    B.normalize_source_paths()
    before = {o.name: B.R.mesh_record(o) for o in B.authored()}
    before_uv = {o.name: B.R.uv_signature(o.data) for o in B.authored()}
    assert len(before) == 14
    soil = bpy.data.objects['CompactedSoil_ContinuousSupport']
    boundary, top = boundary_from_actual(soil)
    points = B.actual_points(soil)
    B.SOIL_BVH = BVHTree.FromPolygons(points, top, all_triangles=True)
    x, z = 2.430400776789371, .6492153117550612
    inside, margin = contains(boundary, x, z)
    crossings = []
    for a, b in zip(boundary, boundary[1:] + boundary[:1]):
        if min(a[0], b[0]) <= x <= max(a[0], b[0]) and abs(a[0] - b[0]) > 1e-12:
            t = (x - a[0]) / (b[0] - a[0])
            crossings.append({'a': a, 'b': b, 'z_at_failed_x': a[2] + t * (b[2] - a[2])})
    diagnostic = {'checkpoint_sha256': B.sha(CHECKPOINT), 'actual_boundary': boundary,
        'actual_upper_triangle_count': len(top), 'actual_boundary_single_loop': True,
        'failed_point_xz': [x, z], 'failed_point_inside_actual_boundary': inside,
        'nearest_actual_boundary_distance_m': margin, 'actual_vertical_line_intersections': crossings,
        'source_geometry_changed': False}
    B.write('actual_boundary_diagnosis.json', diagnostic)
    assert not inside and margin > 1e-6, 'Do not treat an inside ray miss as a harmless sampling error.'
    rows, excluded = [], []
    for ri, route in enumerate(B.T.ROUTES):
        for t in (.18, .38, .62, .82):
            center, normal = B.T.route_frame(route, t)
            in_center, center_margin = contains(boundary, *center)
            assert in_center and center_margin > 1e-6, (ri, t, center)
            samples = []
            for k in range(101):
                d = -.70 + 1.40 * k / 100
                sx, sz = center[0] + normal[0] * d, center[1] + normal[1] * d
                isin, clearance = contains(boundary, sx, sz)
                if not isin or clearance <= 1e-6:
                    excluded.append({'route': ri, 'fraction': t, 'offset_m': d,
                        'xz_m': [sx, sz], 'inside_actual_boundary': isin,
                        'boundary_distance_m': clearance, 'reason': 'outside or exactly on actual upper triangle boundary'})
                    continue
                samples.append({'offset_m': d, 'actual_y_m': B.surface_height(sx, sz)})
            h = B.T.halfwidth(ri, t)
            left = [p['actual_y_m'] for p in samples if p['offset_m'] < -h]
            right = [p['actual_y_m'] for p in samples if p['offset_m'] > h]
            assert left and right, (ri, t, 'actual shoulders missing')
            bed, banks = B.surface_height(*center), [max(left), max(right)]
            rows.append({'route': ri, 'fraction': t, 'center_xz_m': list(center),
                'center_unchanged_from_first_attempt': True, 'actual_center_y_m': bed,
                'actual_left_right_shoulder_max_y_m': banks,
                'actual_relative_depth_each_side_m': [v - bed for v in banks], 'samples': samples})
    B.write('actual_channel_sections.json', {'method': 'Actual saved upper triangle boundary plus actual upper triangle rays; same 12 centers. Outside samples explicitly excluded, interior misses remain fatal.', 'sections': rows, 'excluded_samples': excluded})
    uv = B.source_uv_report(soil)
    collision_count, _ = B.collision_candidate(B.authored())
    # Replace the initial analytical outline selection with the exact ordered
    # side/outer chain. Actual upper boundary contains both front and outer.
    right = min((i for i, p in enumerate(boundary) if abs(p[0] - 3) < 1e-6), key=lambda i: boundary[i][2])
    left = min((i for i, p in enumerate(boundary) if abs(p[0] + 3) < 1e-6), key=lambda i: boundary[i][2])
    paths = []
    for step in (1, -1):
        path, k = [boundary[right]], right
        while k != left:
            k = (k + step) % len(boundary)
            path.append(boundary[k])
            assert len(path) <= len(boundary)
        paths.append(path)
    outer_path = max(paths, key=lambda path: max(p[2] for p in path))
    footprint = [[-3, 0, 0], [3, 0, 0]] + outer_path + [[-3, 0, 0]]
    assert max(abs(p[1]) for p in footprint) < 1e-6
    cpath = B.OUT / 'collision_surface.json'
    collision = json.loads(cpath.read_text(encoding='utf-8'))
    collision['footprint_godot_closed'] = footprint
    collision['footprint_method'] = 'Actual ordered soil side/outer boundary, joined to original straight paving edge.'
    B.write('collision_surface.json', collision)
    images = B.check_images('image_preflight')
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'; scene.cycles.device = 'CPU'; scene.cycles.samples = 24
    scene.render.threads_mode = 'FIXED'; scene.render.threads = 2
    camera = json.loads((HERE.parent / 'p12/sample_review_01/study_report.json').read_text(encoding='utf-8'))['full_camera']
    scene.camera.location = camera['location']; scene.camera.rotation_euler = camera['rotation']
    scene.camera.data.ortho_scale = camera['ortho_scale']
    scene.render.resolution_x = 1440; scene.render.resolution_y = 860; scene.render.resolution_percentage = 100
    for im in B.used_images():
        im.filepath = bpy.path.relpath(bpy.path.abspath(im.filepath), start=str(B.OUT))
    path = B.OUT / 'editable_source.blend'
    bpy.ops.wm.save_as_mainfile(filepath=str(path), relative_remap=False)
    source_sha = B.sha(path)
    bpy.ops.wm.open_mainfile(filepath=str(path))
    reopened = B.check_images('actual_reopen_images')
    assert {r['absolute_path']: r['sha256'] for r in images} == {r['absolute_path']: r['sha256'] for r in reopened}
    assert before == {o.name: B.R.mesh_record(o) for o in B.authored()}
    assert before_uv == {o.name: B.R.uv_signature(o.data) for o in B.authored()}
    scene = bpy.context.scene
    scene.render.filepath = str(B.OUT / '01_full_source.png'); bpy.ops.render.render(write_still=True)
    direction = scene.camera.rotation_euler.to_matrix() @ Vector((0, 0, -1))
    target = Vector(B.H.bp(-1.14, -.005, 1.04))
    scene.camera.location = target - direction * 8; scene.camera.data.ortho_scale = 2.35
    scene.render.filepath = str(B.OUT / '02_contact_close.png'); bpy.ops.render.render(write_still=True)
    assert B.sha(path) == source_sha
    for row in frozen['files']:
        assert B.sha(PREVIOUS / row['path']) == row['sha256'], row
    for row in contract['files']:
        assert B.sha(B.ROOT / row['path']) == row['sha256'], row
    report = json.loads((PREVIOUS / 'geometry_report.json').read_text(encoding='utf-8'))
    report.update(status='SOURCE_RENDERED_PENDING_IMAGE_REVIEW', pid=os.getpid(), seconds=time.time() - started,
        resumed_checkpoint_unchanged=True, source_geometry_uv_material_transforms_unchanged=True,
        editable_source_sha256=source_sha, actual_collision_triangles=collision_count,
        uv=uv, actual_section_count=len(rows), excluded_outside_samples=len(excluded),
        reopened_images=reopened, frozen_inputs_unchanged=True,
        renders=[{'path': p.name, 'bytes': p.stat().st_size, 'sha256': B.sha(p)} for p in [B.OUT / '01_full_source.png', B.OUT / '02_contact_close.png']],
        baked=False, glb_exported=False, engine_tested=False, production_placement_approved=False)
    B.write('source_report.json', report)
    print(json.dumps({'pid': os.getpid(), 'seconds': report['seconds'], 'triangles': report['actual_visual_triangles'], 'status': report['status']}), flush=True)


if __name__ == '__main__':
    main()
