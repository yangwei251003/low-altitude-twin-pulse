"""Source-only explicit GLB. Run via run_bounded.py --export (CPU2/240 s).

Reopens the frozen editable source; copies/join only support descendants in RAM.
Never saves the edited scene, never includes the reference clinic or studio.
"""
from pathlib import Path
from collections import Counter
import hashlib
import json
import math
import struct
import time
import bpy
from mathutils import Matrix

HERE = Path(__file__).resolve().parent
SOURCE = HERE / 'clinic_reception_support_v1.blend'
SOURCE_SHA = 'a408f11c5abda5adae8cfe33c1a41830e49f89c740a770106a243b83eab4606c'
GROUPS = {'SupportStructure': 30, 'SupportDetails': 64}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def godot(v):
    return (float(v.x), float(v.z), float(-v.y))


def canonical(triangle):
    return min(tuple(triangle), tuple(triangle[1:] + triangle[:1]), tuple(triangle[2:] + triangle[:2]))


def triangles(mesh):
    mesh.calc_loop_triangles()
    return Counter(canonical([godot(mesh.vertices[i].co) for i in t.vertices]) for t in mesh.loop_triangles)


def bounds(points):
    return [[min(p[a] for p in points) for a in range(3)], [max(p[a] for p in points) for a in range(3)]]


def read_glb(path):
    data = path.read_bytes()
    magic, version, length = struct.unpack_from('<4sII', data, 0)
    assert magic == b'glTF' and version == 2 and length == len(data)
    offset = 12
    document = binary = None
    while offset < len(data):
        size, kind = struct.unpack_from('<I4s', data, offset)
        chunk = data[offset + 8:offset + 8 + size]
        assert len(chunk) == size
        offset += 8 + size
        if kind == b'JSON':
            document = json.loads(chunk.decode('utf-8'))
        elif kind == b'BIN\0':
            binary = chunk
    assert document is not None and binary is not None

    def accessor(index):
        item = document['accessors'][index]
        view = document['bufferViews'][item['bufferView']]
        assert 'sparse' not in item and view.get('buffer', 0) == 0
        components = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[item['type']]
        component_format = {5121: 'B', 5123: 'H', 5125: 'I', 5126: 'f'}[item['componentType']]
        format_string = '<' + component_format * components
        size = struct.calcsize(format_string)
        stride = view.get('byteStride', size)
        start = view.get('byteOffset', 0) + item.get('byteOffset', 0)
        end = start + (item['count'] - 1) * stride + size
        assert end <= view.get('byteOffset', 0) + view['byteLength'] <= len(binary)
        return [struct.unpack_from(format_string, binary, start + i * stride) for i in range(item['count'])]

    parsed = {}
    all_points = []
    for mesh in document['meshes']:
        actual_triangles = Counter()
        points = []
        surfaces = []
        for primitive in mesh['primitives']:
            assert primitive.get('mode', 4) == 4 and 'indices' in primitive
            positions = accessor(primitive['attributes']['POSITION'])
            normals = accessor(primitive['attributes']['NORMAL'])
            uv = accessor(primitive['attributes']['TEXCOORD_0'])
            indices = [v[0] for v in accessor(primitive['indices'])]
            assert len(indices) % 3 == 0 and len(positions) == len(normals) == len(uv)
            assert indices and min(indices) >= 0 and max(indices) < len(positions)
            assert all(math.isfinite(v) for p in positions + normals + uv for v in p)
            assert all(0 <= v <= 1 for p in uv for v in p) and len(set(uv)) > 4
            actual_triangles.update(canonical([positions[indices[i]], positions[indices[i + 1]], positions[indices[i + 2]]]) for i in range(0, len(indices), 3))
            points += positions
            surfaces.append({'triangle_count': len(indices) // 3, 'vertex_count': len(positions),
                             'uv0_count': len(uv), 'uv0_bounds': [[min(p[a] for p in uv) for a in range(2)], [max(p[a] for p in uv) for a in range(2)]],
                             'material': document['materials'][primitive['material']]['name'],
                             'attributes': list(primitive['attributes'])})
        parsed[mesh['name']] = {'triangles': actual_triangles, 'bounds': bounds(points), 'surfaces': surfaces}
        all_points += points
    images = []
    for item in document.get('images', []):
        assert 'bufferView' in item and 'uri' not in item and item['mimeType'] == 'image/png'
        view = document['bufferViews'][item['bufferView']]
        blob = binary[view.get('byteOffset', 0):view.get('byteOffset', 0) + view['byteLength']]
        assert blob[:8] == b'\x89PNG\r\n\x1a\n'
        size = struct.unpack_from('>II', blob, 16)
        images.append({'name': item.get('name', ''), 'sha256': hashlib.sha256(blob).hexdigest(), 'bytes': len(blob), 'size': size})
    return document, parsed, bounds(all_points), images


def identity_node(node):
    return (node.get('translation', [0, 0, 0]) == [0, 0, 0]
            and node.get('rotation', [0, 0, 0, 1]) == [0, 0, 0, 1]
            and node.get('scale', [1, 1, 1]) == [1, 1, 1]
            and node.get('matrix', [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]) == [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])


def main():
    start = time.monotonic()
    out = HERE / 'clinic_reception_support_v1.glb'
    assert not out.exists(), 'Do not overwrite delivered bytes'
    assert sha(SOURCE) == SOURCE_SHA
    source_report = json.loads((HERE / 'support_geometry.json').read_text(encoding='utf-8'))
    assert all(source_report['checks'].values())
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    root = bpy.data.objects['ClinicReceptionSupport']
    groups = {name: list(bpy.data.objects[name].children) for name in GROUPS}
    assert all(len(objects) == GROUPS[name] and all(o.type == 'MESH' and not o.get('exclude_export', False) for o in objects) for name, objects in groups.items())
    materials = {m for objects in groups.values() for o in objects for m in o.data.materials}
    assert {m.name for m in materials} == {'ReceptionSupport_GravityV4_PBR'}
    textures = []
    for node in next(iter(materials)).node_tree.nodes:
        if node.type != 'TEX_IMAGE':
            continue
        path = Path(bpy.path.abspath(node.image.filepath)).resolve()
        assert path.exists()
        node.image.reload()
        assert tuple(node.image.size) == (2048, 2048)
        textures.append({'role': node.label, 'path': str(path), 'sha256': sha(path), 'colorspace': node.image.colorspace_settings.name})
    assert len(textures) == 4
    root.name = 'EDITING_ClinicReceptionSupport'
    for name in GROUPS:
        bpy.data.objects[name].name = 'EDITING_' + name
    collection = bpy.data.collections.new('TEMP_EXPORT_SUPPORT_ONLY')
    bpy.context.scene.collection.children.link(collection)
    export_root = bpy.data.objects.new('ClinicReceptionSupport', None)
    collection.objects.link(export_root)
    export_root['world_placement'] = [7, 0, -6]
    copies = []
    expected = {}
    group_reports = {}
    depsgraph = bpy.context.evaluated_depsgraph_get()
    for name, objects in groups.items():
        fragments = []
        before_join = Counter()
        for original in objects:
            mesh = bpy.data.meshes.new_from_object(original.evaluated_get(depsgraph), preserve_all_data_layers=True, depsgraph=depsgraph)
            mesh.transform(original.matrix_world)
            mesh.update()
            assert len(mesh.uv_layers) == 1 and mesh.uv_layers.active.name == 'SurfaceUV'
            before_join.update(triangles(mesh))
            copy = bpy.data.objects.new('TMP_' + original.name, mesh)
            collection.objects.link(copy)
            fragments.append(copy)
        bpy.ops.object.select_all(action='DESELECT')
        for copy in fragments:
            copy.select_set(True)
        bpy.context.view_layer.objects.active = fragments[0]
        bpy.ops.object.join()
        copy = bpy.context.object
        copy.name = name
        copy.data.name = name
        copy.parent = export_root
        copy.matrix_basis = Matrix.Identity(4)
        copy['collision_role'] = 'actual_structure' if name == 'SupportStructure' else 'visual_fastener'
        material = next(iter(materials))
        copy.data.materials.clear()
        copy.data.materials.append(material)
        for face in copy.data.polygons:
            face.material_index = 0
        expected[name] = triangles(copy.data)
        assert expected[name] == before_join, 'Joining changed geometry'
        copies.append(copy)
        group_reports[name] = {'source_count': len(objects), 'source_names': [o.name for o in objects],
                              'triangles': sum(expected[name].values()), 'bounds_local_godot': bounds([godot(v.co) for v in copy.data.vertices]),
                              'collision_role': copy['collision_role']}
    bpy.ops.object.select_all(action='DESELECT')
    for obj in copies + [export_root]:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = export_root
    bpy.ops.export_scene.gltf(filepath=str(out), export_format='GLB', use_selection=True, export_apply=True,
                             export_yup=True, export_texcoords=True, export_normals=True, export_materials='EXPORT',
                             export_cameras=False, export_lights=False, export_animations=False, export_extras=True)
    document, actual, aabb, images = read_glb(out)
    checks = []
    def check(name, passed, detail=None):
        checks.append({'name': name, 'passed': bool(passed), 'detail': detail})
    check('exact two mesh names', set(actual) == set(GROUPS), list(actual))
    check('exact three node names', {n['name'] for n in document['nodes']} == set(GROUPS) | {'ClinicReceptionSupport'})
    check('all node transforms identity', all(identity_node(n) for n in document['nodes']))
    for name in GROUPS:
        check(name + ' exact oriented source triangles', actual[name]['triangles'] == expected[name])
        check(name + ' single material surface', len(actual[name]['surfaces']) == 1)
    check('total 4520 triangles', sum(sum(m['triangles'].values()) for m in actual.values()) == source_report['triangle_count'] == 4520)
    expected_bounds = [[-4.92, 0, -3.92], [4.92, 4.6, 3.92]]
    check('complete original local envelope', all(abs(aabb[i][j] - expected_bounds[i][j]) < 1e-5 for i in range(2) for j in range(3)), aabb)
    check('one material', len(document['materials']) == 1)
    pbr = document['materials'][0]
    check('base color packed roughness metallic and normal exported', all(k in pbr['pbrMetallicRoughness'] for k in ['baseColorTexture', 'metallicRoughnessTexture']) and 'normalTexture' in pbr)
    check('three embedded 2048 PNGs', len(images) == 3 and all(i['size'] == (2048, 2048) for i in images), images)
    check('basecolor original bytes preserved', any(i['sha256'] == next(t['sha256'] for t in textures if t['role'] == 'BaseColor') for i in images))
    check('no animation camera light', not document.get('animations') and not document.get('cameras') and not document.get('extensions', {}).get('KHR_lights_punctual'))
    check('frozen editing source unchanged', sha(SOURCE) == SOURCE_SHA)
    report = {'status': 'source_only_GLb_ready_for_root_import' if all(c['passed'] for c in checks) else 'FAILED_RETAINED',
              'checks': checks, 'source_sha256': SOURCE_SHA, 'glb_sha256': sha(out), 'glb_bytes': out.stat().st_size,
              'world_placement': [7, 0, -6], 'local_bounds_godot': aabb,
              'world_bounds': [[aabb[i][j] + [7, 0, -6][j] for j in range(3)] for i in range(2)],
              'mesh_groups': group_reports, 'actual_meshes': {k: {a: b for a, b in v.items() if a != 'triangles'} for k, v in actual.items()},
              'actual_nodes': document['nodes'], 'materials': document['materials'], 'textures': textures, 'embedded_images': images,
              'elapsed_seconds': time.monotonic() - start,
              'limitations': ['Source export only; no Godot or game camera/physics verification.', 'Reference clinic/studio excluded.',
                              'Structure is disconnected closed manufactured parts, not one welded manifold; source retains 94 editable pieces.',
                              'Detail bolts are visual only; root controls actual 14 box production collision contract.']}
    (HERE / 'support_delivery_report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({'checks': len(checks), 'failures': sum(not c['passed'] for c in checks), 'glb_sha256': report['glb_sha256'], 'elapsed_seconds': report['elapsed_seconds']}), flush=True)
    assert all(c['passed'] for c in checks), 'Export readback failed; retain bytes, do not integrate'


if __name__ == '__main__':
    main()
