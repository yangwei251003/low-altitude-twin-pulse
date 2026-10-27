"""Exact zero-area face removal on delivery copies only; no tolerance cleanup.

Coordinates are Blender's stored float32 values represented exactly as Python
Fractions. A positive-area face is never removed, however small it is.
"""
from collections import Counter, defaultdict
from fractions import Fraction
import hashlib
import math

AUTHOR_UVS = ('SourceUV', 'ConcreteUV', 'PaintUV')


def cross_exact(points):
    p = [[Fraction(float(c)) for c in q] for q in points]
    a = [p[1][k]-p[0][k] for k in range(3)]
    b = [p[2][k]-p[0][k] for k in range(3)]
    return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])


def cyclic(values):
    values = tuple(values)
    return min(values[i:]+values[:i] for i in range(len(values)))


def corners(mesh, loop_ids):
    return tuple((mesh.loops[i].vertex_index,
                  *(tuple(float(v) for v in mesh.uv_layers[name].data[i].uv) for name in AUTHOR_UVS))
                 for i in loop_ids)


def face_records(mesh, excluded=()):
    excluded = set(excluded)
    return Counter((cyclic(corners(mesh, p.loop_indices)), p.material_index, p.use_smooth)
                   for p in mesh.polygons if p.index not in excluded)


def triangle_records(mesh, excluded=()):
    excluded = set(excluded)
    mesh.calc_loop_triangles()
    return Counter((cyclic(corners(mesh, t.loops)), mesh.polygons[t.polygon_index].material_index,
                    mesh.polygons[t.polygon_index].use_smooth)
                   for t in mesh.loop_triangles if t.polygon_index not in excluded)


def positive_triangle_records(mesh):
    mesh.calc_loop_triangles()
    result = Counter()
    for tri in mesh.loop_triangles:
        if all(c == 0 for c in cross_exact([mesh.vertices[i].co for i in tri.vertices])): continue
        poly = mesh.polygons[tri.polygon_index]
        result[(cyclic(corners(mesh, tri.loops)), poly.material_index, poly.use_smooth)] += 1
    return result


def area_metrics(mesh, excluded=()):
    """Same visible-top boundary as P1; zero area contributes exactly nothing."""
    excluded = set(excluded)
    mesh.calc_loop_triangles()
    total, visible = [], []
    for tri in mesh.loop_triangles:
        if tri.polygon_index in excluded: continue
        points = [tuple(mesh.vertices[i].co) for i in tri.vertices]
        cross = cross_exact(points)
        area = math.sqrt(sum(float(c)**2 for c in cross))/2
        total.append(area)
        if area and float(cross[2])/(2*area) >= .99 and min(p[2] for p in points) >= -.01201:
            visible.append(area)
    return {'total_triangle_area_m2': math.fsum(sorted(total)),
            'visible_upward_area_m2': math.fsum(sorted(visible))}


def vertex_positions(mesh):
    return tuple(tuple(float(c) for c in v.co) for v in mesh.vertices)


def edge_records(mesh):
    return Counter((tuple(sorted(e.vertices)), e.use_seam, e.use_edge_sharp) for e in mesh.edges)


def bounds(mesh):
    points = vertex_positions(mesh)
    return [[min(p[k] for p in points) for k in range(3)],
            [max(p[k] for p in points) for k in range(3)]]


def audit(obj):
    mesh = obj.data
    mesh.calc_loop_triangles()
    by_face = defaultdict(list)
    zeros, positive = [], []
    for index, tri in enumerate(mesh.loop_triangles):
        points = [tuple(float(c) for c in mesh.vertices[i].co) for i in tri.vertices]
        assert all(math.isfinite(c) for p in points for c in p), 'Nonfinite source coordinate'
        cross = cross_exact(points)
        is_zero = all(c == 0 for c in cross)
        by_face[tri.polygon_index].append((index, is_zero))
        if is_zero:
            zeros.append({'triangle': index, 'source_polygon': tri.polygon_index,
                          'vertex_ids': list(tri.vertices), 'loop_ids': list(tri.loops),
                          'vertices_local_blender': points, 'area_m2': 0.0,
                          'exact_cross': [str(c) for c in cross]})
        else:
            positive.append(math.sqrt(sum(float(c)**2 for c in cross))/2)
    removable = [i for i, rows in by_face.items() if all(z for _, z in rows)]
    mixed = [i for i, rows in by_face.items() if any(z for _, z in rows) and not all(z for _, z in rows)]
    assert len(by_face) == len(mesh.polygons), 'A polygon has no actual tessellation'
    faces = []
    for index in removable:
        poly = mesh.polygons[index]
        faces.append({'polygon': index, 'vertex_ids': list(poly.vertices),
                      'vertices_local_blender': [list(mesh.vertices[i].co) for i in poly.vertices],
                      'material_index': poly.material_index, 'use_smooth': poly.use_smooth,
                      'corner_uvs': {n: [list(mesh.uv_layers[n].data[i].uv) for i in poly.loop_indices]
                                     for n in AUTHOR_UVS},
                      'triangle_ids': [i for i, _ in by_face[index]], 'area_m2': 0.0})
    return {'object': obj.name, 'source_piece': obj['source_piece'],
            'group': obj['delivery_group'], 'source_triangles': len(mesh.loop_triangles),
            'source_polygons': len(mesh.polygons), 'zero_triangle_count': len(zeros),
            'zero_triangles': zeros, 'removable_faces': faces,
            'mixed_positive_faces': mixed, 'min_positive_triangle_area_m2': min(positive),
            'threshold_m2': 0.0,
            'criterion': 'All 3 cross components exactly zero over stored coordinates, with rational arithmetic',
            'bounds_local_blender': bounds(mesh), 'area_metrics': area_metrics(mesh)}


def proof(mesh):
    payload = (vertex_positions(mesh), sorted(edge_records(mesh).items()),
               sorted(face_records(mesh).items()), sorted(triangle_records(mesh).items()),
               tuple(tuple(float(c) for c in n.vector) for n in mesh.corner_normals))
    return hashlib.sha256(repr(payload).encode()).hexdigest()


def remove_proven_faces(obj, observed):
    """Only Bank0:133 gets its existing nonzero loop-triangle as a face.

    All other surviving polygons keep their original loops. No weld, global
    triangulation, inferred diagonal, face expansion or point movement.
    """
    import bpy
    mesh = obj.data
    removed = {p['polygon'] for p in observed['removable_faces']}
    mixed = set(observed['mixed_positive_faces'])
    if removed or mixed:
        assert obj['source_piece'] == 'Bank0' and removed == {286} and mixed == {133}, 'Unapproved topology change'
        assert observed['zero_triangle_count'] == 3, 'Unexpected degeneracy beyond the approved three triangles'
    before_points, before_edges = vertex_positions(mesh), edge_records(mesh)
    expected_triangles = positive_triangle_records(mesh)
    expected_faces = face_records(mesh, removed | mixed)
    before_slots = list(mesh.materials)
    source_custom_normals = mesh.has_custom_normals
    normal_error = 0.0
    added_edges = []
    if removed or mixed:
        rows = []
        by_face = defaultdict(list)
        for tri in mesh.loop_triangles:
            by_face[tri.polygon_index].append(tuple(tri.loops))
        for poly in mesh.polygons:
            if poly.index in removed: continue
            loop_sets = by_face[poly.index] if poly.index in mixed else [tuple(poly.loop_indices)]
            for loops in loop_sets:
                vertex_ids = tuple(mesh.loops[i].vertex_index for i in loops)
                if poly.index in mixed:
                    if all(c == 0 for c in cross_exact([mesh.vertices[i].co for i in vertex_ids])): continue
                    expected_faces[(cyclic(corners(mesh, loops)), poly.material_index, poly.use_smooth)] += 1
                rows.append({'source_polygon': poly.index, 'loops': loops, 'vertices': vertex_ids,
                             'material': poly.material_index, 'smooth': poly.use_smooth})
        # Preserve all original vertices and edges, even loose zero-width edges.
        # The one genuine existing loop-triangle diagonal is the only new edge.
        old_edges = {tuple(sorted(e.vertices)): (e.use_seam, e.use_edge_sharp) for e in mesh.edges}
        fresh = bpy.data.meshes.new(mesh.name+'_ExactZeroCleanup')
        fresh.from_pydata(before_points, [tuple(e.vertices) for e in mesh.edges], [r['vertices'] for r in rows])
        fresh.update()
        for mat in before_slots: fresh.materials.append(mat)
        for poly, row in zip(fresh.polygons, rows):
            assert tuple(poly.vertices) == row['vertices'], 'Rebuild changed the original polygon winding'
            poly.material_index = row['material']; poly.use_smooth = row['smooth']
        for name in [layer.name for layer in mesh.uv_layers]: fresh.uv_layers.new(name=name)
        for name in [layer.name for layer in mesh.uv_layers]:
            source_uv, target_uv = mesh.uv_layers[name], fresh.uv_layers[name]
            for poly, row in zip(fresh.polygons, rows):
                for new_loop, old_loop in zip(poly.loop_indices, row['loops']):
                    target_uv.data[new_loop].uv = source_uv.data[old_loop].uv
            target_uv.active_render = source_uv.active_render
        fresh.uv_layers.active_index = mesh.uv_layers.active_index
        for edge in fresh.edges:
            key = tuple(sorted(edge.vertices))
            if key in old_edges:
                edge.use_seam, edge.use_edge_sharp = old_edges[key]
            else:
                added_edges.append(list(key))
        expected_edge_keys = set(old_edges)
        for row in rows:
            vs = row['vertices']
            expected_edge_keys.update(tuple(sorted((vs[i-1], vs[i]))) for i in range(len(vs)))
        assert {tuple(sorted(e.vertices)) for e in fresh.edges} == expected_edge_keys
        # Reuse original per-corner split normals through the exact loop map.
        # Blender may quantize a custom normal; refuse any change over 1e-6 in
        # unit-vector length, record the actual error, and never alter geometry.
        normals = [tuple(mesh.corner_normals[i].vector) for row in rows for i in row['loops']]
        fresh.update()
        if source_custom_normals or any(tuple(n.vector) != wanted for n, wanted in zip(fresh.corner_normals, normals)):
            fresh.normals_split_custom_set(normals)
        assert len(fresh.corner_normals) == len(normals)
        normal_error = max(math.sqrt(sum((n.vector[k]-wanted[k])**2 for k in range(3)))
                           for n, wanted in zip(fresh.corner_normals, normals))
        assert normal_error <= 1e-6, ('Copied corner normals changed', normal_error)
        obj.data = fresh
        mesh = fresh
    mesh.calc_loop_triangles()
    assert vertex_positions(mesh) == before_points, 'Face-only cleanup moved or reordered vertices'
    assert not (before_edges-edge_records(mesh)), 'Cleanup changed an original edge or its flags'
    assert face_records(mesh) == expected_faces, 'Remaining face winding/material/smooth/corner UV changed'
    assert triangle_records(mesh) == expected_triangles, 'Remaining triangle tessellation or three corner UVs changed'
    assert list(mesh.materials) == before_slots, 'Cleanup changed copied material slots'
    assert bounds(mesh) == observed['bounds_local_blender'], 'Cleanup changed envelope'
    after_metrics = area_metrics(mesh)
    assert after_metrics == observed['area_metrics'], 'Cleanup changed total or visible surface area'
    # No new re-tessellation degeneration may have appeared.
    after = audit(obj)
    assert after['zero_triangle_count'] == 0, 'Remaining zero triangle after exact face removal'
    assert len(mesh.loop_triangles) == observed['source_triangles']-observed['zero_triangle_count']
    return {'source_piece': obj['source_piece'], 'removed_polygon_ids': sorted(removed),
            'locally_split_polygon_ids': sorted(mixed), 'added_existing_triangle_diagonal_edges': added_edges,
            'removed_triangle_ids': [t['triangle'] for t in observed['zero_triangles']],
            'before_triangles': observed['source_triangles'], 'after_triangles': len(mesh.loop_triangles),
            'remaining_vertices_edges_faces_material_and_three_uvs_exact': True,
            'source_has_custom_normals': source_custom_normals,
            'delivery_has_custom_normals': mesh.has_custom_normals,
            'copied_corner_normal_max_vector_error': normal_error,
            'bounds_unchanged': True, 'area_metrics_unchanged': True, 'area_metrics': after_metrics,
            'remaining_source_proof_sha256': proof(mesh)}
