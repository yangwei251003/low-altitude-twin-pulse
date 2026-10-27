"""P13 source-only composition, invoked by its bounded authorized runner.

Opens a frozen P10 source, keeps six concrete/seal objects and the actual soil
XY topology, removes the old 137 decorations, and adds four native Rock07s and
three slab-profile fragments. No bake/export/runtime writes or pixel editing.
"""
from pathlib import Path
import collections
import hashlib
import importlib.util
import json
import math
import os
import struct
import sys
import time

sys.dont_write_bytecode = True
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
OUT = Path(os.environ['TRANSITION_P13_OUTPUT']).resolve()
assert OUT.parent == HERE and OUT.name.startswith('source_run_'), OUT
OLD = HERE.parent / 'p10/repair_01'
INPUT = HERE.parent / 'p12/inputs/polyhaven_rock_07_1k'


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


H = load('p13_frozen_basic_helper', HERE.parent / 'p3/build_asset.py')
R = load('p13_frozen_rock_helper', HERE.parent / 'p12/build_sample.py')
T = load('p13_terrain', HERE / 'terrain_design.py')
H.OUT = OUT
SOIL_BVH = None
CONTACTS = []


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write(name, value):
    (OUT / name).write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')


def authored():
    return [o for o in bpy.context.scene.objects if o.type == 'MESH' and o.get('editable_piece', False)]


def actual_points(obj):
    return [obj.matrix_world @ v.co for v in obj.data.vertices]


def godot_bounds(points):
    pts = [H.gp(p) for p in points]
    return {'min': [min(p[i] for p in pts) for i in range(3)],
            'max': [max(p[i] for p in pts) for i in range(3)]}


def topology(obj):
    me = obj.data
    me.calc_loop_triangles()
    pts = actual_points(obj)
    edges = collections.Counter()
    signed_volume = 0.0
    min_area = float('inf')
    for tri in me.loop_triangles:
        a, b, c = [int(i) for i in tri.vertices]
        for u, v in ((a, b), (b, c), (c, a)):
            edges[tuple(sorted((u, v)))] += 1
        signed_volume += pts[a].dot(pts[b].cross(pts[c])) / 6
        min_area = min(min_area, (pts[b] - pts[a]).cross(pts[c] - pts[a]).length * .5)
    return {'name': obj.name, 'triangles': len(me.loop_triangles), 'vertices': len(me.vertices),
            'boundary_edges': sum(v == 1 for v in edges.values()),
            'nonmanifold_edges': sum(v > 2 for v in edges.values()),
            'signed_volume_m3': signed_volume, 'min_triangle_area_m2': min_area,
            'bounds_godot': godot_bounds(pts), 'native_geometry_sha256': R.signature(obj),
            'uv_sha256': R.uv_signature(me)}


def surface_height(x, z):
    hit, normal, _, _ = SOIL_BVH.ray_cast(Vector(H.bp(x, 1, z)), Vector((0, 0, -1)), 3)
    assert hit is not None and normal.z > .01, ('Missing upper soil support', x, z)
    return float(hit.z)


def normalize_source_paths():
    for image in bpy.data.images:
        if image.source == 'FILE' and image.filepath and image.users > 0:
            image.filepath = bpy.path.abspath(image.filepath)


def used_images():
    found = {}
    for obj in authored():
        for mat in obj.data.materials:
            if not mat or not mat.use_nodes:
                continue
            for node in mat.node_tree.nodes:
                if node.type == 'TEX_IMAGE' and node.image:
                    found[node.image.name] = node.image
    return list(found.values())


def check_images(label):
    rows = []
    for image in used_images():
        path = Path(bpy.path.abspath(image.filepath))
        row = {'name': image.name, 'filepath': image.filepath, 'absolute_path': str(path),
               'exists': path.is_file(), 'colorspace': image.colorspace_settings.name}
        rows.append(row)
        write(label + '.json', rows)
        assert path.is_file(), row
        row['sha256'] = sha(path)
        image.reload()
        row['first_actual_pixel'] = list(image.pixels[:4])
        row['has_data_after_read'] = bool(image.has_data)
        row['size'] = list(image.size)
        assert image.has_data and len(row['first_actual_pixel']) == 4 and all(
            math.isfinite(v) for v in row['first_actual_pixel']), row
        assert min(image.size) > 0, row
    write(label + '.json', rows)
    return rows


def remodel_soil(soil):
    global SOIL_BVH
    me = soil.data
    old_xy = [(float(v.co.x), float(v.co.y)) for v in me.vertices]
    old_uv = R.uv_signature(me)
    moved = 0
    for v in me.vertices:
        if v.co.z > -.17:  # all P10 upper vertices, not the structural base
            v.co.z = T.field(float(v.co.x), float(-v.co.y), H.front, H.outer)['height']
            moved += 1
    me.update()
    assert old_xy == [(float(v.co.x), float(v.co.y)) for v in me.vertices]
    assert old_uv == R.uv_signature(me)
    control = me.color_attributes['SurfaceControl']
    for poly in me.polygons:
        upper = all(me.vertices[i].co.z > -.17 for i in poly.vertices)
        for li in poly.loop_indices:
            v = me.vertices[me.loops[li].vertex_index].co
            f = T.field(float(v.x), float(-v.y), H.front, H.outer)
            control.data[li].color = (f['wet'], f['silt'], f['deposit'], 1) if upper else (0, 0, 0, 1)
    mat = me.materials[0].copy()
    mat.name = 'P13_ExistingScans_CoherentWideApron'
    mat['adaptation'] = 'Original P10 two-scan shader and source pixels; new shared geometry/wet/silt/deposit coordinates.'
    me.materials.clear()
    me.materials.append(mat)
    me.calc_loop_triangles()
    SOIL_BVH = BVHTree.FromPolygons(actual_points(soil), [tuple(t.vertices) for t in me.loop_triangles], all_triangles=True)
    # Real free boundary, including actual CDT split vertices, stays at Y0.
    boundary = []
    for v in me.vertices:
        x, y, z = H.gp(v.co)
        if v.co.z > -.17 and (abs(abs(x) - 3) < 1e-6 or abs(z - H.outer(x)) < 1e-6):
            boundary.append([x, y, z])
    assert boundary and max(abs(p[1]) for p in boundary) < 1e-6
    write('soil_change.json', {'upper_vertices_repositioned': moved, 'topology_xy_unchanged': True,
        'source_uv_unchanged': old_uv == R.uv_signature(me), 'free_boundary_godot': boundary,
        'absolute_height_bounds': godot_bounds(actual_points(soil)),
        'scope': 'One height field preserves shared topology; no local folded surface or new high-only gravel.'})


def adapt_full_join(parts):
    changes = []
    for obj in parts:
        if obj.name == 'CompactedSoil_ContinuousSupport':
            continue
        ids = []
        for v in obj.data.vertices:
            if abs(float(-v.co.y) - .01) < 1e-6:
                v.co.y = -.02
                ids.append(v.index)
        obj.data.update()
        changes.append({'object': obj.name, 'vertex_ids': ids, 'change': 'local Z .01 -> .02; other components unchanged'})
    seal = bpy.data.objects['JoinSeal_10mm']
    seal.name = 'JoinSeal_Full20mm'
    seal['adapter'] = 'P2 original tile has zero half-seal. This side contributes 20mm, recessed 12mm.'
    write('join_adapter.json', {'width_m': .02, 'top_y_m': -.012, 'changes': changes,
        'plain_10mm_variant': 'Not instantiated in this preview; frozen P10 geometry retains its 10mm variant.',
        'production_placement_approved': False})


def seat(obj, x, z, rotation, uniform_scale, native_matrix, center, burial):
    obj.matrix_world = (Matrix.Translation(Vector(H.bp(x, 0, z))) @ rotation
        @ Matrix.Scale(uniform_scale, 4) @ Matrix.Translation(-center) @ native_matrix)
    points = actual_points(obj)
    offsets = [surface_height(p.x, -p.y) - float(p.z) for p in points]
    first_contact = max(offsets)
    obj.matrix_world = Matrix.Translation(Vector((0, 0, first_contact - burial))) @ obj.matrix_world
    points = actual_points(obj)
    clearances = [float(p.z) - surface_height(p.x, -p.y) for p in points]
    row = {'object': obj.name, 'uniform_scale': uniform_scale, 'burial_m': burial,
           'actual_first_contact_translation_m': first_contact,
           'actual_min_max_soil_clearance_m': [min(clearances), max(clearances)],
           'buried_vertices': sum(v < -.0001 for v in clearances),
           'exposed_vertices': sum(v > .0001 for v in clearances),
           'bounds_godot': godot_bounds(points),
           'exceeds_old_plus_3cm_suggestion': max(p.z for p in points) > .03,
           'actual_matrix_world_blender': [list(r) for r in obj.matrix_world]}
    CONTACTS.append(row)
    write('contact_report.json', CONTACTS)
    assert row['buried_vertices'] and row['exposed_vertices'], row
    assert abs(min(clearances) + burial) < 2e-6, row
    assert row['bounds_godot']['min'][1] >= -.180001, row
    assert row['bounds_godot']['min'][0] >= -3 and row['bounds_godot']['max'][0] <= 3, row
    assert row['bounds_godot']['min'][2] >= 0 and row['bounds_godot']['max'][2] <= 2.400001, row
    # +3cm is explicitly no longer a hard cap; report every actual protrusion.
    obj['collision_inclusion'] = 'Actual full source triangles included in the CollisionSurface candidate.'
    return row


def add_scans():
    old_materials = set(bpy.data.materials)
    with bpy.data.libraries.load(str(INPUT / 'rock_07_1k.blend'), link=False) as (src, dst):
        assert 'rock_07_LOD3' in src.objects
        dst.objects = ['rock_07_LOD3']
    native = dst.objects[0]
    assert native is not None and len(native.modifiers) == 0
    geometry, uv = R.signature(native), R.uv_signature(native.data)
    smooth_flags = [bool(p.use_smooth) for p in native.data.polygons]
    native_matrix = native.matrix_world.copy()
    points = [native_matrix @ v.co for v in native.data.vertices]
    lo = Vector([min(p[i] for p in points) for i in range(3)])
    hi = Vector([max(p[i] for p in points) for i in range(3)])
    dims = hi - lo
    source_yaw = 0 if dims.x >= dims.y else math.pi / 2
    center = Vector(((lo.x + hi.x) * .5, (lo.y + hi.y) * .5, lo.z))
    mats = {}
    for key, rough in [('Dry', .72), ('Damp', .42)]:
        m = R.material(native.data.uv_layers.active.name)
        m.name = 'P13_Rock07_' + key
        bs = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
        for socket in ('Roughness', 'Metallic'):
            for link in list(bs.inputs[socket].links):
                m.node_tree.links.remove(link)
        bs.inputs['Roughness'].default_value = rough
        bs.inputs['Metallic'].default_value = 0
        bs.inputs['IOR'].default_value = 1.45
        bs.inputs['Coat Weight'].default_value = 0
        bs.inputs['Transmission Weight'].default_value = 0
        m['roughness_authored_override'] = rough
        mats[key] = m
    specs = [(-1.48, 1.05, .14, 24, 8, -6, .010, 'Damp'),
             (-.84, .86, .12, -39, -7, 11, .008, 'Dry'),
             (1.08, 1.22, .12, 82, 9, 5, .012, 'Damp'),
             (-2.20, 1.32, .10, -12, -5, -8, .006, 'Dry')]
    rows = []
    for i, (x, z, length, yaw, tilt_x, tilt_y, burial, state) in enumerate(specs):
        ob = native.copy()
        ob.data = native.data.copy()
        bpy.context.scene.collection.objects.link(ob)
        ob.name = f'Rock07_LOD3_{i:02d}_{state}'
        ob.hide_render = False
        ob.hide_viewport = False
        ob.hide_set(False)
        ob['editable_piece'] = True
        ob['source_asset'] = 'Poly Haven Rock07 / Jenelle van Heerden / CC0'
        ob['material_kind'] = 'natural_scan_stone'
        ob.data.materials.clear()
        ob.data.materials.append(mats[state])
        for poly in ob.data.polygons:
            poly.material_index = 0
        rot = (Matrix.Rotation(math.radians(yaw) - source_yaw, 4, 'Z')
               @ Matrix.Rotation(math.radians(tilt_y), 4, 'Y')
               @ Matrix.Rotation(math.radians(tilt_x), 4, 'X'))
        row = seat(ob, x, z, rot, length / max(dims.x, dims.y), native_matrix, center, burial)
        assert R.signature(ob) == geometry and R.uv_signature(ob.data) == uv
        assert [bool(p.use_smooth) for p in ob.data.polygons] == smooth_flags
        ob.data.calc_loop_triangles()
        assert len(ob.data.loop_triangles) == 1854
        ob.data.calc_tangents(uvmap=ob.data.uv_layers.active.name)
        assert all(math.isfinite(c) for loop in ob.data.loops for c in loop.tangent)
        row.update(native_geometry_identical=True, native_uv_identical=True,
                   smooth_flags_identical=True, uniform_long_axis_m=length,
                   native_geometry_sha256=geometry, native_uv_sha256=uv,
                   material_state=state, authored_roughness=mats[state]['roughness_authored_override'])
        rows.append(row)
    bpy.data.objects.remove(native, do_unlink=True)
    # Appended unused author material references a separate roughness EXR not
    # acquired by this study. Never leave it as an active missing-image source.
    for m in list(bpy.data.materials):
        if m not in old_materials and m not in mats.values() and m.users == 0:
            bpy.data.materials.remove(m)
    write('rock_native_preservation.json', {'source_dimensions_m': list(dims), 'rocks': rows,
        'native_mesh_not_transformed': True, 'materials_only_dry_wet_overrides': True})


def add_fragments(concrete):
    rows = []
    # Source profile x, placement x/z, length, former slab thickness, yaw,
    # rigid tilt. The upper former walking plane is actually planar.
    specs = [(-1.10, -1.06, .79, .34, .12, -21, 10, -5, .065),
             (.42, .33, .88, .29, .105, 34, -8, 13, .058),
             (1.74, 1.93, .89, .25, .10, -48, 12, 7, .052)]
    for i, (source_x, x, z, length, thick, yaw, tx, ty, burial) in enumerate(specs):
        xs = [-length * .5, -length * .18, length * .21, length * .5]
        fronts = [H.front(source_x + dx) for dx in xs]
        rear = min(fronts) - length * .56
        poly = [(xs[0], rear), (xs[-1], rear)] + list(reversed(list(zip(xs, fronts))))
        cx = sum(v[0] for v in poly) / len(poly)
        cz = sum(v[1] for v in poly) / len(poly)
        top = [H.bp(px - cx, 0, pz - cz) for px, pz in poly]
        vs = top + [(p[0] * .96, p[1] * .94, -thick * (1 + .06 * math.sin(k * 1.7))) for k, p in enumerate(top)]
        n = len(top)
        fs = [tuple(range(n)), tuple(reversed(range(n, n * 2)))]
        fs.extend((k, (k + 1) % n, (k + 1) % n + n, k + n) for k in range(n))
        ob = H.mesh(f'ConcreteBreakFragment_{i:02d}', vs, fs, concrete, H.GROUPS[0], 'concrete')
        control = ob.data.color_attributes['SurfaceControl']
        for face in ob.data.polygons:
            former_top = all(ob.data.vertices[j].co.z > -.000001 for j in face.vertices)
            for li in face.loop_indices:
                control.data[li].color = (.20, .10 if former_top else 1, 1 if former_top else 0, 1)
        rotation = (Matrix.Rotation(math.radians(yaw), 4, 'Z')
                    @ Matrix.Rotation(math.radians(ty), 4, 'Y')
                    @ Matrix.Rotation(math.radians(tx), 4, 'X'))
        row = seat(ob, x, z, rotation, 1.0, Matrix.Identity(4), Vector((0, 0, 0)), burial)
        row.update(source_profile_x_m=source_x, original_slab_thickness_m=thick,
                   method='Closed prism from the actual P10 broken-edge profile, with a planar former walking face. Not a natural scan and not claimed a Boolean-excised piece.')
        rows.append(row)
    write('concrete_fragment_report.json', rows)


def sections():
    rows = []
    for ri, route in enumerate(T.ROUTES):
        for t in (.18, .38, .62, .82):
            center, normal = T.route_frame(route, t)
            samples = []
            for k in range(101):
                d = -.70 + 1.40 * k / 100
                x, z = center[0] + normal[0] * d, center[1] + normal[1] * d
                if -3 < x < 3 and H.front(x) + .00001 < z < H.outer(x) - .00001:
                    samples.append({'offset_m': d, 'actual_y_m': surface_height(x, z)})
            h = T.halfwidth(ri, t)
            left = [p['actual_y_m'] for p in samples if p['offset_m'] < -h]
            right = [p['actual_y_m'] for p in samples if p['offset_m'] > h]
            assert left and right, (ri, t)
            bed = surface_height(*center)
            banks = [max(left), max(right)]
            rows.append({'route': ri, 'fraction': t, 'center_xz_m': list(center),
                'actual_center_y_m': bed, 'actual_left_right_shoulder_max_y_m': banks,
                'actual_relative_depth_each_side_m': [b - bed for b in banks], 'samples': samples})
    write('actual_channel_sections.json', {'method': 'Actual soil triangle rays; no engine physics claim.', 'sections': rows})
    return rows


def collision_candidate(parts):
    vertices, faces, included = [], [], []
    for ob in parts:
        ob.data.calc_loop_triangles()
        pts = actual_points(ob)
        offset = len(vertices)
        vertices.extend(pts)
        count = 0
        for t in ob.data.loop_triangles:
            # Omit only the buried structural bottom. Complete scan geometry
            # and fragments are retained; no unmeasured collision decimation.
            if all(abs(pts[j].z + .18) < 1e-6 for j in t.vertices):
                continue
            faces.append(tuple(offset + int(j) for j in t.vertices))
            count += 1
        included.append({'object': ob.name, 'actual_triangles_included': count})
    me = bpy.data.meshes.new('CollisionSurface_CandidateTriangles')
    me.from_pydata(vertices, [], faces)
    me.update()
    ob = bpy.data.objects.new('CollisionSurface', me)
    bpy.context.scene.collection.objects.link(ob)
    ob.hide_render = True
    ob.hide_set(True)
    ob['collision_candidate_only'] = True
    ob['not_engine_tested'] = True
    ob['automatic_collision_import'] = False
    soil = bpy.data.objects['CompactedSoil_ContinuousSupport']
    outer = []
    for v in soil.data.vertices:
        x, y, z = H.gp(v.co)
        if v.co.z > -.17 and abs(z - H.outer(x)) < 1e-6:
            outer.append([x, y, z])
    # Actual sampled outer chain, with the real straight joining edge. Side
    # edges are exactly planar Y0 and need only their endpoint representation.
    outer.sort(key=lambda p: p[0], reverse=True)
    footprint = [[-3, 0, 0], [3, 0, 0]] + outer
    if footprint[-1] != footprint[0]:
        footprint.append(footprint[0])
    write('collision_surface.json', {'status': 'SOURCE_GEOMETRY_CANDIDATE_NOT_ENGINE_VERIFIED',
        'vertices_godot': [H.gp(p) for p in vertices], 'triangles': faces,
        'triangle_count': len(faces), 'source_objects': included, 'simplification': 'None',
        'actual_source_to_collision_vertex_deviation_m': 0,
        'footprint_godot_closed': footprint,
        'proposed_world_transform_not_approved': {'origin': [-22, 0, 15], 'yaw_degrees': -90},
        'integration_requirement': 'Root must remove exact footprint from actual dry_surface visual AND terrain triangles, including authored_support Y0. No invisible plane beneath channels.'})
    return len(faces), footprint


def source_uv_report(soil):
    metric = soil.data.uv_layers['MetricUV']
    errors = []
    for layer, width, phase in [('SoilScanUV', 2.5, (.13, .27)), ('RockScanUV', 2, (.31, .09))]:
        target = soil.data.uv_layers[layer]
        for m, a in zip(metric.data, target.data):
            errors.extend(abs(a.uv[j] - (m.uv[j] * 1.5 / width + phase[j])) for j in (0, 1))
    assert max(errors) < 1e-6
    row = {'actual_max_coordinate_error': max(errors), 'native_source_sizes_px': [2048, 2048],
        'world_width_m': {'SoilScanUV': 2.5, 'RockScanUV': 2.0},
        'projected_source_texels_per_m': {'sandy_gravel': 2048 / 2.5, 'rocky_trail': 2048 / 2.0},
        'rock07': 'Four unchanged native UV datasets; do not equate native packing with the soil metric UV.'}
    write('uv_report.json', row)
    return row


def main():
    started = time.time()
    contract = json.loads((HERE / 'input_contract.json').read_text(encoding='utf-8'))
    for row in contract['files']:
        path = ROOT / row['path']
        assert path.is_file() and sha(path) == row['sha256'], row
    bpy.ops.wm.open_mainfile(filepath=str(OLD / 'editable_source.blend'))
    normalize_source_paths()
    baseline = {o.name: R.mesh_record(o) for o in authored()}
    assert len(baseline) == 144 and sum(r['triangles'] for r in baseline.values()) == 7456
    remove = [o for o in authored() if o.name.startswith(('FractureAggregate_', 'SedimentBankStone_', 'FallenConcreteFragment_'))]
    assert len(remove) == 137
    removed = [{'name': o.name, 'triangles': baseline[o.name]['triangles']} for o in remove]
    assert sum(r['triangles'] for r in removed) == 3340
    for o in remove:
        bpy.data.objects.remove(o, do_unlink=True)
    parts = authored()
    assert len(parts) == 7
    write('removed_old_decorations.json', removed)
    adapt_full_join(parts)
    soil = bpy.data.objects['CompactedSoil_ContinuousSupport']
    remodel_soil(soil)
    add_scans()
    add_fragments(bpy.data.objects['ConcreteResidual_00'].data.materials[0])
    for mat in list(bpy.data.materials):
        if mat.users == 0:
            bpy.data.materials.remove(mat)
    for image in list(bpy.data.images):
        if image.users == 0:
            bpy.data.images.remove(image)
    normalize_source_paths()
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / 'geometry_checkpoint.blend'), relative_remap=False)
    parts = authored()
    assert len(parts) == 14
    rows = [topology(o) for o in parts]
    bounds = godot_bounds([p for o in parts for p in actual_points(o)])
    checks = [{'name': 'each_part_closed', 'pass': all(r['boundary_edges'] == 0 and r['nonmanifold_edges'] == 0 for r in rows)},
              {'name': 'each_part_positive_volume', 'pass': all(r['signed_volume_m3'] > 0 for r in rows)},
              {'name': 'all_triangle_areas_positive', 'pass': all(r['min_triangle_area_m2'] > 0 for r in rows)},
              {'name': 'horizontal_footprint_and_structural_bottom', 'pass': bounds['min'][0] >= -3.000001 and bounds['max'][0] <= 3.000001 and bounds['min'][2] >= -.000001 and bounds['max'][2] <= 2.400001 and bounds['min'][1] >= -.180001},
              {'name': 'four_scans_and_three_fragments_buried_and_exposed', 'pass': len(CONTACTS) == 7 and all(r['buried_vertices'] and r['exposed_vertices'] for r in CONTACTS)}]
    report = {'status': 'GEOMETRY_CHECKPOINT', 'objects': rows, 'checks': checks, 'bounds_godot': bounds,
        'actual_visual_triangles': sum(r['triangles'] for r in rows), 'old_3cm_cap_withdrawn_by_root': True,
        'self_intersection_scope': 'Soil remains a single-valued XY height field. No comprehensive triangle self-intersection audit performed for every solid; closure is reported separately.',
        'physics_status': 'No engine/FlightBody execution; geometric contact only.'}
    write('geometry_report.json', report)
    assert all(c['pass'] for c in checks), [c for c in checks if not c['pass']]
    actual_sections = sections()
    uv = source_uv_report(soil)
    collision_triangles, footprint = collision_candidate(parts)
    images = check_images('image_preflight')
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = 24
    scene.render.threads_mode = 'FIXED'
    scene.render.threads = 2
    reference_camera = json.loads((HERE.parent / 'p12/sample_review_01/study_report.json').read_text(encoding='utf-8'))['full_camera']
    scene.camera.location = reference_camera['location']
    scene.camera.rotation_euler = reference_camera['rotation']
    scene.camera.data.ortho_scale = reference_camera['ortho_scale']
    scene.render.resolution_x = 1440
    scene.render.resolution_y = 860
    scene.render.resolution_percentage = 100
    for image in used_images():
        image.filepath = bpy.path.relpath(bpy.path.abspath(image.filepath), start=str(OUT))
    before_save_records = {o.name: R.mesh_record(o) for o in authored()}
    before_save_uvs = {o.name: R.uv_signature(o.data) for o in authored()}
    editable = OUT / 'editable_source.blend'
    bpy.ops.wm.save_as_mainfile(filepath=str(editable), relative_remap=False)
    source_sha = sha(editable)
    bpy.ops.wm.open_mainfile(filepath=str(editable))
    reopened = check_images('actual_reopen_images')
    assert {r['absolute_path']: r['sha256'] for r in images} == {r['absolute_path']: r['sha256'] for r in reopened}
    assert len(authored()) == 14
    assert before_save_records == {o.name: R.mesh_record(o) for o in authored()}
    assert before_save_uvs == {o.name: R.uv_signature(o.data) for o in authored()}
    scene = bpy.context.scene
    scene.render.filepath = str(OUT / '01_full_source.png')
    bpy.ops.render.render(write_still=True)
    # Same lighting/view direction, but a genuinely unobscured sample group.
    direction = scene.camera.rotation_euler.to_matrix() @ Vector((0, 0, -1))
    target = Vector(H.bp(-1.14, -.005, 1.04))
    scene.camera.location = target - direction * 8
    scene.camera.data.ortho_scale = 2.35
    scene.render.filepath = str(OUT / '02_contact_close.png')
    close_camera = {'location': list(scene.camera.location), 'rotation': list(scene.camera.rotation_euler), 'ortho_scale': scene.camera.data.ortho_scale, 'target_godot': H.gp(target)}
    bpy.ops.render.render(write_still=True)
    for row in contract['files']:
        assert sha(ROOT / row['path']) == row['sha256'], row
    assert sha(editable) == source_sha
    report.update(status='SOURCE_RENDERED_PENDING_ACTUAL_IMAGE_REVIEW', pid=os.getpid(),
        seconds=time.time() - started, frozen_inputs_unchanged=True, editable_source_sha256=source_sha,
        actual_collision_triangles=collision_triangles, footprint_vertices=len(footprint),
        uv=uv, actual_section_count=len(actual_sections), reopened_images=reopened,
        full_camera=reference_camera, close_camera=close_camera,
        output_renders=[{'path': p.name, 'bytes': p.stat().st_size, 'sha256': sha(p)} for p in [OUT / '01_full_source.png', OUT / '02_contact_close.png']],
        baked=False, glb_exported=False, production_placement_approved=False, engine_tested=False)
    write('source_report.json', report)
    print(json.dumps({'pid': os.getpid(), 'seconds': report['seconds'], 'triangles': report['actual_visual_triangles'], 'status': report['status']}), flush=True)


if __name__ == '__main__':
    main()
