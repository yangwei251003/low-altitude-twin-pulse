"""CPU-only conversion of the authorized Godot raw export; no modeling/rendering.

Python + existing Shapely 2.1.2. No install, snap, buffer, shore offset or remesh.
Usage: python .../build_blender_input.py .../exports/<fresh-id>/geometry.json
Writes a NEW derived/ child. Godot source/visible float32 bytes remain untouched.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import struct

import shapely
from shapely.geometry import Polygon, box, mapping
from shapely.geometry.polygon import orient
from shapely.ops import unary_union

AREA_EPS = 0.0005  # Accounting only. Never shifts vertices or cut lines.
BASE = Path(__file__).resolve().parent


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def unpack_attribute(root: Path, info: dict, width: int) -> list[tuple[float, ...]]:
    if Path(info['file']).name != info['file']:
        raise ValueError('attribute path must be a direct filename')
    raw = (root / info['file']).read_bytes()
    if len(raw) != info['bytes'] or sha(raw) != info['sha256'] or len(raw) % (4 * width):
        raise ValueError('raw attribute length/hash mismatch')
    rows = list(struct.iter_unpack('<' + 'f' * width, raw))
    if any(not math.isfinite(x) for row in rows for x in row):
        raise ValueError('nonfinite raw attribute')
    return rows


def triangle_union(vertices: list[tuple[float, ...]]):
    if len(vertices) % 3:
        raise ValueError('triangle corner count')
    polygons = []
    for i in range(0, len(vertices), 3):
        points = vertices[i:i + 3]
        if any(p[1] != 0.0 for p in points):
            raise ValueError('raw top is not exactly Y0')
        triangle = Polygon([(p[0], p[2]) for p in points])
        if not triangle.is_valid or triangle.area <= 0:
            raise ValueError('invalid or zero area triangle')
        polygons.append(triangle)
    union = unary_union(polygons)
    if not union.is_valid:
        raise ValueError('raw triangle union invalid; no repair attempted')
    total = math.fsum(p.area for p in polygons)
    if abs(total - union.area) > AREA_EPS:
        raise ValueError('positive triangle overlap exceeds float32 accounting bound')
    return union, total


def rings(geometry) -> list[dict]:
    if geometry.is_empty:
        return []
    parts = [geometry] if geometry.geom_type == 'Polygon' else list(geometry.geoms)
    if any(p.geom_type != 'Polygon' for p in parts):
        raise ValueError('nonpolygon boundary')
    result = []
    for index, poly in enumerate(sorted(parts, key=lambda p: (-p.area, p.bounds))):
        poly = orient(poly, sign=1.0)
        result.append({'component': index, 'area_m2': poly.area,
                       'exterior_world_xz': list(poly.exterior.coords),
                       'holes_world_xz': [list(r.coords) for r in poly.interiors]})
    return result


def convert(path: Path) -> dict:
    path = path.resolve()
    permitted = (BASE / 'exports').resolve()
    if path.name != 'geometry.json' or not path.is_relative_to(permitted):
        raise ValueError('only this tool exports/<id>/geometry.json is accepted')
    raw_manifest = path.read_bytes()
    data = json.loads(raw_manifest)
    if data.get('schema_version') != 1 or data.get('kind') != 'actual_final_i2_yard_connector_input' or data.get('ok') is not True:
        raise ValueError('actual Godot final-world export required')
    report = data['report']
    if not report['final_post_pit_exact_match'] or not report['ground_collision_unchanged']:
        raise ValueError('final-source/read-only proof missing')
    if data['geometry_input_sha256_before'] != data['geometry_input_sha256_after']:
        raise ValueError('changed production inputs')
    groups = {}
    for name, row in data['groups'].items():
        vertices = unpack_attribute(path.parent, row['files']['faces'], 3)
        normals = unpack_attribute(path.parent, row['files']['normals'], 3)
        uv = unpack_attribute(path.parent, row['files']['uv'], 2)
        tangents = unpack_attribute(path.parent, row['files']['tangents'], 4)
        if len(vertices) != row['vertex_count'] or len(vertices) != row['triangle_count'] * 3 or len(vertices) != len(normals) or len(uv) != len(vertices) or len(tangents) != len(vertices):
            raise ValueError('raw geometry attribute count')
        ids = row['source_final_triangle_ids']
        if len(ids) != row['triangle_count'] or any(type(i) is not int or i < 0 or i >= data['groups']['source']['triangle_count'] for i in ids):
            raise ValueError('original final triangle IDs')
        geom, area = triangle_union(vertices)
        groups[name] = {'vertices': vertices, 'normals': normals, 'uv': uv, 'ids': ids, 'geom': geom, 'area': area}
    visible = groups['visible']; source = groups['source']; retained = groups['remainder']
    if abs(source['area'] - visible['area'] - retained['area']) > AREA_EPS or abs(visible['area'] - report['visible_replacement_m2']) > AREA_EPS:
        raise ValueError('exported area accounting mismatch')
    x, z, w, d = data['rect_xz']
    if visible['geom'].difference(box(x, z, x + w, z + d)).area > AREA_EPS or visible['geom'].difference(source['geom']).area > AREA_EPS:
        raise ValueError('visible triangles outside real source or requested region')
    for exclusion in report['exclusions']:
        x, z, w, d = exclusion['rect']
        if visible['geom'].intersection(box(x, z, x + w, z + d)).area > AREA_EPS:
            raise ValueError('protected live structure overlapped: ' + exclusion['id'])
    out = path.parent / 'derived'
    out.mkdir(exist_ok=False)
    origin = data['godot_origin']
    # A proper rotation Godot(x,y,z)->Blender(x,-z,y); reverse Godot clockwise
    # triangle winding for Blender's counterclockwise outward faces.
    obj = ['# Raw clipped Y0 layout input only; no thickness/material/art acceptance',
           '# Godot world origin: ' + repr(origin), 'o ActualSouthwestYardInput']
    for px, py, pz in visible['vertices']:
        obj.append(f'v {px-origin[0]:.17g} {-(pz-origin[2]):.17g} {py-origin[1]:.17g}')
    for nx, ny, nz in visible['normals']:
        obj.append(f'vn {nx:.17g} {-nz:.17g} {ny:.17g}')
    for i in range(0, len(visible['vertices']), 3):
        obj.append(f'f {i+1}//{i+1} {i+3}//{i+3} {i+2}//{i+2}')
    (out / 'yard_visible_blender_local.obj').write_text('\n'.join(obj) + '\n', encoding='utf-8', newline='\n')
    boundary = {'world_axes': 'Godot XZ metres; Y0', 'godot_origin': origin,
                'rings': rings(visible['geom']), 'geojson_xz': mapping(visible['geom']),
                'visible_triangle_area_m2': visible['area'], 'union_area_m2': visible['geom'].area,
                'union_minus_triangle_area_m2': visible['geom'].area-visible['area'],
                'method': 'Exact-coordinate Shapely union. No grid snapping, buffering, simplification, convex hull or remesh. Raw source/visible arrays are canonical.',
                'shapely_version': shapely.__version__}
    (out / 'boundary_world_xz.json').write_text(json.dumps(boundary, indent=2), encoding='utf-8')
    (out / 'visible_triangles_world.json').write_text(json.dumps({'vertices_world_xyz': visible['vertices'], 'normals_world_xyz': visible['normals'], 'source_final_triangle_ids': visible['ids']}, indent=2), encoding='utf-8')
    result = {'ok': True, 'source_manifest_sha256': sha(raw_manifest), 'visible_area_m2': visible['area'], 'components': len(boundary['rings']),
              'holes': sum(len(p['holes_world_xz']) for p in boundary['rings']), 'triangles': len(visible['ids']),
              'files': {p.name: sha(p.read_bytes()) for p in sorted(out.iterdir())}, 'scope': 'Actual site input for later editable art; not runtime/collision change or final art approval'}
    (out / 'derivation.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path)
    args = parser.parse_args()
    print(json.dumps(convert(args.manifest), ensure_ascii=False, indent=2))
