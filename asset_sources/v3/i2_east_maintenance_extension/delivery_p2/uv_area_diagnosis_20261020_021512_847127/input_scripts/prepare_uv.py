"""Prepare only. Run inside an explicitly granted CPU2 Blender window.

Keeps frozen source intact. Only proven exact zero-area faces may be removed
from delivery copies; all remaining geometry/material UVs stay exact.
No bake, export or rendering.
DeliveryUV is the new bake UV and the future exported UV0.
"""
from pathlib import Path
from collections import defaultdict
import hashlib
import importlib.util
import json
import math
import os
import statistics
import sys
import time
import bpy

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
sys.path.insert(0, str(HERE))
import atlas_geometry as AG
import plan_atlas_cpu as BUDGET
import delivery_cleanup as CLEAN

spec = importlib.util.spec_from_file_location('frozen_p1_delivery', HERE.parent/'delivery_p1/build_delivery.py')
P1 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(P1)
CFG, NATIVE, SOURCE = P1.CFG, P1.NATIVE, P1.SOURCE
UV = 'DeliveryUV'
CHECKS = []


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def save(name, value): (HERE/name).write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')
def check(name, ok, detail=None):
    CHECKS.append({'name': name, 'passed': bool(ok), 'detail': detail})
    assert ok, name


def project(point, axis, sign):
    a, b = [(1, 2), (2, 0), (0, 1)][axis]
    return float(point[a]), sign*float(point[b])


def descriptor(obj, poly):
    name, normal = obj['source_piece'], poly.normal
    points = [obj.data.vertices[i].co for i in poly.vertices]
    low, high = min(p.z for p in points), max(p.z for p in points)
    axis = max(range(3), key=lambda i: abs(normal[i]))
    sign = 1 if normal[axis] > 0 else -1
    if name == 'FullBearingBed':
        return ('buried', 16, 2, 1 if normal.z > 0 else -1) if abs(normal.z) > .99 else ('side', 64, axis, sign)
    if name == 'ShallowSeals':
        if normal.z > .99: return ('seal_top', 96, 2, 1)
        if normal.z < -.99: return ('buried', 16, 2, -1)
        return 'side', 64, axis, sign
    if name.startswith(('Bank', 'Service', 'ClearRoute')):
        if normal.z > .001 and low >= -.00301: return 'wide_top', 175, 2, 1
        if normal.z < -.001 and high <= -.04699: return 'buried', 16, 2, -1
        return 'side', 64, axis, sign
    if name == 'InspectionBed': return 'buried', 24, axis, sign
    if name.startswith(('SolidCover', 'CoverFrame')):
        top = -.004 if name.startswith('SolidCover') else -.002
        bottom = -.03 if name.startswith('SolidCover') else -.04
        if normal.z > .001 and low >= top-.00101:
            if name.startswith('SolidCover'): return 'cover_top', 275, 2, 1
            bb = obj['_uv_bounds_xy']
            center = sum(points, points[0]*0)/len(points)
            edge = min(range(4), key=lambda i: [center.x-bb[0], bb[2]-center.x, center.y-bb[1], bb[3]-center.y][i])
            return 'frame_top_'+str(edge), 275, 2, 1
        if normal.z < -.001 and high <= bottom+.00101: return 'buried', 24, 2, -1
        return 'detail_side', 128, axis, sign
    if name.startswith('CountersunkFastener'):
        if normal.z > .99: return 'fastener_top', 400, 2, 1
        if normal.z < -.99: return 'buried', 24, 2, -1
        return 'detail_side', 128, axis, sign
    if name.startswith('RecessedGrip'):
        if normal.z > .001 and low >= -.01801: return 'grip_top', 275, 2, 1
        if normal.z < -.001 and high <= -.02999: return 'buried', 24, 2, -1
        return 'detail_side', 128, axis, sign
    if name.startswith(('GripPocket', 'FastenerPocket')):
        if normal.z > .99: return 'recess_floor', 64, 2, 1
        if normal.z < -.99: return 'buried', 24, 2, -1
        return 'detail_side', 128, axis, sign
    raise AssertionError('Unclassified source part: '+name)


def connected_sets(mesh, ids):
    members = set(ids)
    edge_faces = defaultdict(list)
    for index in members:
        for edge in mesh.polygons[index].edge_keys:
            edge_faces[tuple(sorted(edge))].append(index)
    neighbors = defaultdict(set)
    for faces in edge_faces.values():
        for a in faces:
            neighbors[a].update(faces)
    while members:
        todo = [min(members)]
        component = set()
        while todo:
            face = todo.pop()
            if face in component: continue
            component.add(face)
            todo.extend(neighbors[face]-component)
        members -= component
        yield sorted(component)


def seal_rectangles(mesh, ids):
    """Merge original coplanar grid quads into strips, changing UV seams only."""
    rows = defaultdict(list)
    for index in ids:
        poly = mesh.polygons[index]
        points = [tuple(mesh.vertices[i].co[:2]) for i in poly.vertices]
        bb = AG.bounds(points)
        assert len(points) == 4 and all(abs(AG.cross(points[i-1], points[i], points[(i+1) % 4])) > 0 for i in range(4))
        assert abs(abs(AG.cross(points[0], points[1], points[2]))-(bb[2]-bb[0])*(bb[3]-bb[1])) < 1e-7
        key = (round(bb[1], 6), round(bb[3], 6))
        rows[key].append((bb[0], bb[2], [index]))
    strips = []
    for (y0, y1), row in sorted(rows.items()):
        merged = []
        for x0, x1, faces in sorted(row):
            if merged and abs(merged[-1][1]-x0) < 1e-6:
                merged[-1][1] = x1
                merged[-1][2].extend(faces)
            else:
                merged.append([x0, x1, faces])
        strips.extend((round(x0, 6), round(x1, 6), y0, y1, faces) for x0, x1, faces in merged)
    columns = defaultdict(list)
    for x0, x1, y0, y1, faces in strips:
        columns[(x0, x1)].append((y0, y1, faces))
    result = []
    for rows in columns.values():
        merged = []
        for y0, y1, faces in sorted(rows):
            if merged and abs(merged[-1][1]-y0) < 1e-6:
                merged[-1][1] = y1
                merged[-1][2].extend(faces)
            else:
                merged.append([y0, y1, list(faces)])
        result.extend(item[2] for item in merged)
    assert sorted(f for part in result for f in part) == sorted(ids)
    return result


def charts_for(obj):
    mesh = obj.data
    obj['_uv_bounds_xy'] = AG.bounds([tuple(v.co[:2]) for v in mesh.vertices])
    buckets = defaultdict(list)
    for poly in mesh.polygons:
        buckets[descriptor(obj, poly)].append(poly.index)
    charts = []
    for desc, ids in buckets.items():
        groups = seal_rectangles(mesh, ids) if desc[0] == 'seal_top' else [ids]
        for faces in groups:
            for component in connected_sets(mesh, faces):
                category, density, axis, sign = desc
                points = [project(mesh.vertices[v].co, axis, sign) for index in component for v in mesh.polygons[index].vertices]
                bb = AG.bounds(points)
                if not (bb[2] > bb[0] and bb[3] > bb[1]):
                    detail = projection_failure_detail(obj, component, desc, bb, len(charts))
                    save('projection_failure_detail.json', detail)
                    print(json.dumps({'stage': 'projection_failure', 'object': obj.name,
                                      'source_piece': obj['source_piece'], 'island_index': len(charts),
                                      'category': category, 'axis': axis, 'sign': sign,
                                      'polygon_ids': component, 'projected_bounds': bb}), flush=True)
                    raise AssertionError('Zero projected extent: '+obj.name+' island '+str(len(charts)))
                charts.append({'id': obj.name+'_'+str(len(charts)), 'obj': obj, 'faces': component,
                               'category': category, 'density': density, 'axis': axis, 'sign': sign,
                               'bounds_m': bb, 'w': math.ceil((bb[2]-bb[0])*density)+10,
                               'h': math.ceil((bb[3]-bb[1])*density)+10})
    assert sorted(f for c in charts for f in c['faces']) == list(range(len(mesh.polygons)))
    return charts


def projection_failure_detail(obj, component, desc, projected_bounds, island_index):
    mesh = obj.data
    coordinates = [mesh.vertices[v].co for i in component for v in mesh.polygons[i].vertices]
    records = []
    for index in component:
        poly = mesh.polygons[index]
        vertices = [mesh.vertices[v].co.copy() for v in poly.vertices]
        # Independent geometric normal from ordered vertices, never the cached
        # MeshPolygon normal. Records only; does not replace the projection.
        geometric = vertices[0]*0
        for i in range(1, len(vertices)-1):
            geometric += (vertices[i]-vertices[0]).cross(vertices[i+1]-vertices[0])
        length = geometric.length
        if length: geometric /= length
        records.append({'polygon': index, 'vertex_ids': list(poly.vertices),
                        'vertices': [list(v) for v in vertices], 'cached_normal': list(poly.normal),
                        'cached_normal_length': poly.normal.length,
                        'geometric_normal': list(geometric), 'double_geometric_area': length,
                        'vertex_bounds': [[min(v[k] for v in vertices) for k in range(3)],
                                          [max(v[k] for v in vertices) for k in range(3)]]})
    return {'object': obj.name, 'source_piece': obj['source_piece'],
            'group': obj['delivery_group'], 'island_index': island_index,
            'category': desc[0], 'density': desc[1], 'projection_axis': desc[2], 'projection_sign': desc[3],
            'projected_bounds': projected_bounds, 'polygon_ids': component,
            'island_vertex_bounds': [[min(v[k] for v in coordinates) for k in range(3)],
                                     [max(v[k] for v in coordinates) for k in range(3)]],
            'polygons': records, 'scope': 'Diagnostic data only; no axis, density, geometry or UV correction'}


def subtract_free(free, rect):
    x, y, w, h = rect
    result = []
    for fx, fy, fw, fh in free:
        if x >= fx+fw or x+w <= fx or y >= fy+fh or y+h <= fy:
            result.append((fx, fy, fw, fh)); continue
        if x > fx: result.append((fx, fy, x-fx, fh))
        if x+w < fx+fw: result.append((x+w, fy, fx+fw-x-w, fh))
        if y > fy: result.append((fx, fy, fw, y-fy))
        if y+h < fy+fh: result.append((fx, y+h, fw, fy+fh-y-h))
    return [a for i, a in enumerate(result) if not any(i != j and a[0] >= b[0] and a[1] >= b[1]
            and a[0]+a[2] <= b[0]+b[2] and a[1]+a[3] <= b[1]+b[3]
            and (a != b or i > j) for j, b in enumerate(result))]


def place_charts(charts, size, group, uv_observer=None):
    primary = [c for c in charts if c['category'] in ['wide_top', 'cover_top']]
    zone = (2032, 1720) if group == 'FloorSurface' else (640, 1008)
    packed = BUDGET.pack([(c['id'], c['w'], c['h']) for c in primary], *zone)
    assert packed is not None, 'Primary charts do not fit fixed density'
    locations = {p['name']: p for p in packed}
    free = [(0, 0, size-16, size-16)]
    for item in packed:
        free = subtract_free(free, item['rect_px'])
    for chart in sorted((c for c in charts if c not in primary), key=lambda c: max(c['w'], c['h']), reverse=True):
        options = []
        for i, (x, y, fw, fh) in enumerate(free):
            for w, h, turn in [(chart['w'], chart['h'], False), (chart['h'], chart['w'], True)]:
                if w <= fw and h <= fh: options.append((min(fw-w, fh-h), max(fw-w, fh-h), i, w, h, turn))
        assert options, ('Detail chart packing failed; no density auto-reduction', chart['id'], chart['w'], chart['h'])
        _, _, i, w, h, turn = min(options)
        x, y, _, _ = free[i]
        locations[chart['id']] = {'rect_px': [x, y, w, h], 'quarter_turn': turn}
        free = subtract_free(free, (x, y, w, h))
    boxes = list(locations.values())
    for i, item in enumerate(boxes):
        x, y, w, h = item['rect_px']
        assert x >= 0 and y >= 0 and x+w <= size-16 and y+h <= size-16
        for other in boxes[i+1:]:
            bx, by, bw, bh = other['rect_px']
            assert x+w <= bx or bx+bw <= x or y+h <= by or by+bh <= y, 'Packed chart rectangles overlap'
    for chart in charts:
        item = locations[chart['id']]
        x, y, w, h = item['rect_px']
        chart['rect_px'] = [x+8, y+8, w, h]
        chart['quarter_turn'] = item['quarter_turn']
        uv = chart['obj'].data.uv_layers[UV]
        bb, density = chart['bounds_m'], chart['density']
        for face in chart['faces']:
            for li in chart['obj'].data.polygons[face].loop_indices:
                vertex = chart['obj'].data.vertices[chart['obj'].data.loops[li].vertex_index].co
                px, py = project(vertex, chart['axis'], chart['sign'])
                px, py = (px-bb[0])*density, (py-bb[1])*density
                if item['quarter_turn']: px, py = (bb[3]-bb[1])*density-py, px
                before_storage = ((x+13+px)/size, (y+13+py)/size)
                uv.data[li].uv = before_storage
                if uv_observer is not None:
                    uv_observer(chart, face, li, before_storage, tuple(uv.data[li].uv))


def inspect_atlas(charts, size):
    categories = defaultdict(lambda: {'surface_area_m2': 0.0, 'uv_area': 0.0, 'pixels': 0, 'densities': [], 'islands': 0})
    all_triangles, island_triangles, records = [], [], []
    for chart in charts:
        mesh = chart['obj'].data
        mesh.calc_loop_triangles()
        faces = set(chart['faces'])
        uv = mesh.uv_layers[UV]
        triangles, area_sum, uv_area = [], 0.0, 0.0
        cat = categories[chart['category']]
        for tri in mesh.loop_triangles:
            if tri.polygon_index not in faces: continue
            p = [mesh.vertices[i].co for i in tri.vertices]
            area = (p[1]-p[0]).cross(p[2]-p[0]).length/2
            t = [tuple(float(v)*size for v in uv.data[i].uv) for i in tri.loops]
            check_area = AG.cross(*t)/2
            assert area > 0 and check_area > 1e-10
            assert all(math.isfinite(v) and 0 <= v <= size for q in t for v in q)
            triangles.append(t)
            area_sum += area
            uv_area += check_area/(size*size)
            cat['densities'].append(math.sqrt(check_area/area))
        assert triangles
        overlap_candidates = AG.check_triangle_overlap(triangles)
        pixels = AG.occupied_pixels(triangles, size)
        records.append({'id': chart['id'], 'source_piece': chart['obj']['source_piece'],
                        'category': chart['category'], 'requested_px_m': chart['density'],
                        'triangles': len(triangles), 'surface_area_m2': area_sum, 'uv_area': uv_area,
                        'pixel_centres_covered': pixels, 'rect_px': chart['rect_px'],
                        'quarter_turn': chart['quarter_turn'], 'overlap_candidates_checked': overlap_candidates})
        cat['surface_area_m2'] += area_sum; cat['uv_area'] += uv_area
        cat['pixels'] += pixels; cat['islands'] += 1
        all_triangles.extend(triangles); island_triangles.append(triangles)
    print(json.dumps({'stage': 'actual_island_distances', 'islands': len(charts), 'size': size}), flush=True)
    distances, nearest = AG.shortest_distances(island_triangles)
    assert all(d >= 8 for d in distances), ('Actual island gap below 8 pixels', min(distances))
    for i, record in enumerate(records):
        record['nearest_island'] = records[nearest[i]]['id']
        record['nearest_boundary_pixels'] = distances[i]
    pixels = AG.occupied_pixels(all_triangles, size)
    assert pixels == sum(r['pixel_centres_covered'] for r in records), 'Raster overlap between islands'
    for cat in categories.values():
        ds = cat.pop('densities')
        cat.update({'min_px_m': min(ds), 'median_px_m': statistics.median(ds), 'max_px_m': max(ds)})
    return {'size': size, 'island_count': len(records), 'pixel_centres_covered': pixels,
            'pixel_coverage_fraction': pixels/(size*size), 'min_actual_gap_pixels': min(distances),
            'uv_area': sum(r['uv_area'] for r in records), 'categories': dict(categories), 'islands': records}


def verify_author_sampling(material):
    reachable = set()
    todo = [n for n in material.node_tree.nodes if n.type == 'OUTPUT_MATERIAL' and n.is_active_output]
    while todo:
        node = todo.pop()
        if node in reachable: continue
        reachable.add(node)
        todo.extend(link.from_node for socket in node.inputs for link in socket.links)
    for node in reachable:
        if node.type == 'TEX_IMAGE':
            assert node.inputs['Vector'].is_linked, ('Implicit active UV would change source sampling', material.name, node.name)
        if node.type == 'UVMAP':
            assert node.uv_map in ['SourceUV', 'ConcreteUV', 'PaintUV'], ('Unexpected author UV map', node.uv_map)
        if node.type == 'TEX_COORD':
            assert not any(link.to_node in reachable for link in node.outputs['UV'].links), 'Implicit TexCoord UV depends on active bake layer'
        if node.type == 'NORMAL_MAP':
            assert node.uv_map in ['SourceUV', 'ConcreteUV', 'PaintUV'], 'Author tangent normal must keep its explicit source UV'


def verify_cleaned_openings(originals, copies):
    """Independent surface probes, in addition to the exact nonzero-face proof."""
    from mathutils import Vector
    old_tree, new_tree = SOURCE.bvh_for(originals), SOURCE.bvh_for(copies)
    samples = []
    for hole in CFG['body_holes']:
        a, b, c, d = hole['rect']; x, z = (a+b)/2, (c+d)/2
        samples.extend([(hole['id']+' center', x, z, None),
                        (hole['id']+' collar', b+.006, z, -.012),
                        (hole['id']+' outside collar', b+.022, z, 0)])
    samples.extend([('no bank overlay', 17.1, 6, None),
                    ('no exterior overshoot', 24.6, 6, None),
                    ('north new top', 22, 2.005, 0),
                    ('north old seal left free', 22, 1.995, None),
                    ('clear route', 23, 6, 0),
                    ('recessed cover', 19.25, 4.5, -.004)])
    records = []
    for name, x, z, expected in samples:
        origin = Vector(SOURCE.plan.bg((x, 1, z)))
        a = old_tree.ray_cast(origin, Vector((0, 0, -1)), 2)[0]
        b = new_tree.ray_cast(origin, Vector((0, 0, -1)), 2)[0]
        same = a is None and b is None if a is None or b is None else (a-b).length < 1e-6
        correct = b is None if expected is None else b is not None and abs(b.z-expected) < 1e-5
        record = {'name': name, 'world_xz': [x, z], 'expected_y': expected,
                  'source_y': None if a is None else a.z, 'delivery_y': None if b is None else b.z,
                  'unchanged': same, 'matches_contract': correct}
        records.append(record)
        assert same and correct, ('Cleanup affected physical opening/boundary', record)
    return records


def main(diagnostic_inspector=None, uv_observer=None):
    start = time.monotonic()
    assert not (HERE/'uv_checkpoint.blend').exists(), 'Never overwrite a completed prepare'
    P1.verify()
    before = {p: sha(ROOT/p) for p in CFG['frozen_inputs']}
    print(json.dumps({'stage': 'weighted_prepare' if diagnostic_inspector is None else 'read_only_uv_area_diagnosis',
                      'pid': os.getpid(), 'cpu_threads': 2}), flush=True)
    bpy.ops.wm.open_mainfile(filepath=str(ROOT/CFG['source']))
    bpy.context.view_layer.update()
    check('original editable signature', SOURCE.editable_signature() == CFG['source_geometry_uv_signature'])
    originals = sorted((o for o in bpy.data.objects if o.type == 'MESH' and o.get('export_piece')), key=lambda o: o.name)
    check('92 real source parts', len(originals) == 92)
    copies, materials = [], {}
    for obj in originals:
        copy = bpy.data.objects.new('Delivery_'+obj.name, obj.data.copy())
        bpy.context.scene.collection.objects.link(copy)
        copy['delivery_part'] = True; copy['source_piece'] = obj.name; copy['delivery_group'] = P1.group_of(obj.name)
        check(copy.name+' begins with exact source geometry and three UVs', P1.source_uv_proof(obj.data) == P1.source_uv_proof(copy.data))
        for i, mat in enumerate(copy.data.materials):
            if mat.name not in materials:
                verify_author_sampling(mat)
                materials[mat.name] = mat.copy(); materials[mat.name].name = 'DELIVERY_P2_AUTHOR_'+mat.name
            copy.data.materials[i] = materials[mat.name]
        copy.data.uv_layers.new(name=UV)
        copy.data.uv_layers.active_index = len(copy.data.uv_layers)-1
        for layer in copy.data.uv_layers: layer.active_render = layer.name == UV
        copies.append(copy)
    check('author materials never sample implicit active bake UV', bool(materials))
    # Enumerate before deletion. Only the observed Bank0 face133 may use its
    # original loop-triangle split; no global re-tessellation is authorized.
    audits = [CLEAN.audit(obj) for obj in copies]
    audit_report = {'status': 'FULL_SOURCE_ZERO_AREA_AUDIT', 'threshold_m2': 0.0,
                    'source_sha256': CFG['source_sha256'], 'parts': audits,
                    'zero_triangles': sum(a['zero_triangle_count'] for a in audits),
                    'removable_faces': sum(len(a['removable_faces']) for a in audits),
                    'mixed_positive_faces': [{'object': a['object'], 'polygons': a['mixed_positive_faces']}
                                             for a in audits if a['mixed_positive_faces']]}
    save('zero_area_audit.json', audit_report)
    check('only the proved Bank0 face133 has a mixed zero triangle',
          audit_report['mixed_positive_faces'] == [{'object': 'Delivery_Bank0', 'polygons': [133]}]
          and audit_report['zero_triangles'] == 3 and audit_report['removable_faces'] == 1)
    clean_records = [CLEAN.remove_proven_faces(obj, audit) for obj, audit in zip(copies, audits)]
    bpy.context.view_layer.update()
    openings = verify_cleaned_openings(originals, copies)
    check('five openings, collars and six boundary surfaces retain actual rays', len(openings) == 21)
    save('cleanup_report.json', {'status': 'COPY_CLEANUP_PASSED', 'parts': clean_records,
                                'ray_probes': openings, 'threshold_m2': 0.0,
                                'scope': 'Only Bank0 face286 removed and face133 keeps its original positive loop-triangle; no source edits or global re-tessellation'})
    proofs = {r['source_piece']: r['remaining_source_proof_sha256'] for r in clean_records}
    delivery_cfg = json.loads(json.dumps(CFG))
    delivery_cfg.update({'status': 'MEASURED_AFTER_COPY_CLEANUP_NOT_EXPORTED',
                         'frozen_source_triangles': CFG['triangles'],
                         'copy_cleanup_report': 'cleanup_report.json'})
    for group in delivery_cfg['groups'].values():
        for part in group['pieces']:
            part['frozen_source_triangles'] = part['triangles']
            part['triangles'] = next(r['after_triangles'] for r in clean_records if r['source_piece'] == part['name'])
        group['frozen_source_triangles'] = group['triangles']
        group['triangles'] = sum(p['triangles'] for p in group['pieces'])
    delivery_cfg['triangles'] = sum(g['triangles'] for g in delivery_cfg['groups'].values())
    check('delivery count equals frozen source minus exactly zero triangles',
          delivery_cfg['triangles'] == CFG['triangles']-audit_report['zero_triangles'])
    save('delivery_contract.json', delivery_cfg)
    print(json.dumps({'stage': 'copy_cleanup_validated', 'removed_faces': audit_report['removable_faces'],
                      'removed_zero_triangles': audit_report['zero_triangles'],
                      'delivery_triangles': delivery_cfg['triangles']}), flush=True)
    report = {'status': 'PREPARE_IN_PROGRESS_NOT_BAKED', 'source_sha256': CFG['source_sha256'],
              'scope': 'Actual UV prepare only; no GLB, bake, game or visual-quality approval', 'groups': {},
              'cleanup_report_sha256': sha(HERE/'cleanup_report.json'),
              'delivery_contract_sha256': sha(HERE/'delivery_contract.json'),
              'source_triangles': CFG['triangles'], 'delivery_triangles': delivery_cfg['triangles']}
    for group, config in delivery_cfg['groups'].items():
        objects = [o for o in copies if o['delivery_group'] == group]
        charts = [c for obj in objects for c in charts_for(obj)]
        save('classification_attempt.json', {'group': group, 'islands': [{k: c[k] for k in ['id', 'category', 'density', 'w', 'h']} for c in charts]})
        place_charts(charts, config['size'], group, uv_observer)
        for obj in objects:
            check(obj.name+' remaining geometry/material/three UVs unchanged', CLEAN.proof(obj.data) == proofs[obj['source_piece']])
        check(group+' measured cleaned triangle count retained', sum(len(o.data.loop_triangles) for o in objects) == config['triangles'])
        record = inspect_atlas(charts, config['size']) if diagnostic_inspector is None else diagnostic_inspector(charts, config['size'], group)
        record['uv_sha256'] = NATIVE.packed_signature(objects)
        report['groups'][group] = record
        save('prepare_progress.json', report)
        if diagnostic_inspector is None:
            print(json.dumps({'stage': 'group_validated', 'group': group, 'islands': record['island_count'],
                              'coverage': record['pixel_coverage_fraction'], 'min_gap': record['min_actual_gap_pixels']}), flush=True)
        else:
            print(json.dumps({'stage': 'group_diagnosed_not_approved', 'group': group,
                              'triangles': record['triangles_examined'], 'failed_triangles': record['failed_triangles']}), flush=True)
    if diagnostic_inspector is not None:
        check('diagnosis leaves original in-memory source unchanged', SOURCE.editable_signature() == CFG['source_geometry_uv_signature'])
        P1.verify()
        check('diagnosis leaves all 33 frozen input bytes unchanged', before == {p: sha(ROOT/p) for p in before})
        report.update({'status': 'READ_ONLY_DIAGNOSIS_COMPLETE_NOT_PREPARE_PASS', 'checks': CHECKS,
                       'scope': 'Temporary copies reproduce approved cleanup and UV assignment for diagnosis only; no blend/checkpoint/image/bake/export writes',
                       'elapsed_seconds': time.monotonic()-start, 'frozen_inputs': before})
        save('uv_diagnosis_report.json', report)
        return report
    for obj in list(bpy.data.objects):
        if obj.type == 'MESH' and not obj.get('delivery_part'): obj.hide_render = True
    for image in bpy.data.images:
        if image.source == 'FILE' and image.filepath:
            image.filepath = str(Path(bpy.path.abspath(image.filepath)).resolve())
    check('original in-memory source unchanged', SOURCE.editable_signature() == CFG['source_geometry_uv_signature'])
    bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'uv_checkpoint.blend'), relative_remap=False)
    bpy.ops.wm.open_mainfile(filepath=str(HERE/'uv_checkpoint.blend'))
    bpy.context.view_layer.update()
    for group in CFG['groups']:
        objects = sorted((o for o in bpy.data.objects if o.get('delivery_part') and o['delivery_group'] == group), key=lambda o: o.name)
        check(group+' saved UVs reloaded exactly', NATIVE.packed_signature(objects) == report['groups'][group]['uv_sha256'])
        for obj in objects:
            check(obj.name+' saved remaining source data reloaded exactly', CLEAN.proof(obj.data) == proofs[obj['source_piece']])
    P1.verify()
    check('all 33 frozen inputs unchanged', before == {p: sha(ROOT/p) for p in before})
    report.update({'status': 'PREPARE_PASSED_AWAITING_ROOT_REVIEW', 'checks': CHECKS,
                   'elapsed_seconds': time.monotonic()-start, 'frozen_inputs': before,
                   'checkpoint_sha256': sha(HERE/'uv_checkpoint.blend')})
    save('uv_checkpoint.json', report)
    print(json.dumps({'stage': 'weighted_prepare_finished', 'checks': len(CHECKS), 'elapsed_seconds': report['elapsed_seconds']}), flush=True)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        save('prepare_failure.json', {'error': repr(error), 'checks': CHECKS, 'scope': 'No bake/export was attempted'})
        raise
