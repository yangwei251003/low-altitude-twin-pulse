"""Prepared, NOT executed. Run only in the next root-approved CPU2 window.

Blender 5.2: blender.exe -b -t 2 --python-exit-code 2 --python this_file.py
The caller must bound its own process tree. Source V5 is SHA-checked and read-only.
Native EMIT baking preserves V5 masks/tints; no image editing API or image synthesis.
Outputs stay beside this script. No runtime asset, Godot import or collision creation.
"""
from pathlib import Path
import importlib.util
import hashlib
import json
import math
import shutil
import struct

import bpy
from mathutils import Matrix, Quaternion, Vector

OUT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('reception_delivery_contract', OUT / 'export_contract.py')
C = importlib.util.module_from_spec(spec)
spec.loader.exec_module(C)
SIZE = 2048
EPS = 0.00001


def p(v): return Vector((v[0], -v[2], v[1]))


def godot(v): return [v.x, v.z, -v.y]


def mesh_points(obj): return [obj.matrix_world @ v.co for v in obj.data.vertices]


def bounds(points):
    return {'min': [min(v[i] for v in points) for i in range(3)],
            'max': [max(v[i] for v in points) for i in range(3)]}


def parent_keep(obj, parent):
    transform = obj.matrix_world.copy()
    obj.parent = parent
    obj.matrix_parent_inverse = Matrix.Identity(4)
    obj.matrix_world = transform


def empty(name, parent=None, position=(0, 0, 0)):
    obj = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = p(position)
    bpy.context.view_layer.update()
    if parent: parent_keep(obj, parent)
    return obj


def build_hierarchy(meshes):
    # Reparent existing meshes by world transform. No new visual geometry or modifiers.
    for obj in list(bpy.context.scene.objects):
        if obj.type == 'EMPTY':
            for child in list(obj.children): parent_keep(child, None)
            bpy.data.objects.remove(obj, do_unlink=True)
    root = empty('ClinicReception')
    root['world_origin_godot'] = C.WORLD_ORIGIN
    root['source_v5_sha256'] = C.SOURCE_SHA
    groups = {'': root}
    for obj in meshes:
        path = C.group_for(obj.name)
        parts = path.split('/')
        for i in range(1, len(parts) + 1):
            key = '/'.join(parts[:i])
            if key not in groups:
                # Unique node names simplify runtime lookup without losing semantic paths.
                node_name = parts[i-1] if i < 3 else parts[i-2] + '_' + parts[i-1]
                parent = groups['/'.join(parts[:i-1])]
                groups[key] = empty(node_name, parent, C.PIVOTS.get(key, godot(parent.matrix_world.translation)))
                groups[key]['semantic_path'] = key
        parent_keep(obj, groups[path])
        obj['collision_role'] = C.collision_for(path)
        obj['semantic_path'] = path
    anchors = empty('Anchors', root)
    for name, position in C.ANCHORS.items(): empty(name, anchors, position)
    bpy.context.view_layer.update()
    return root, groups


def principled(material):
    nodes = [n for n in material.node_tree.nodes if n.type == 'BSDF_PRINCIPLED']
    assert len(nodes) == 1, material.name
    return nodes[0]


def select(objects):
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects: obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]


def prepare_unique_uv(objects):
    for obj in objects:
        # Keep SurfaceUV as a named shader input until all source composites are baked.
        assert not obj.modifiers, 'Unexpected unapplied geometry: ' + obj.name
        layer = obj.data.uv_layers.new(name='DeliveryBakeUV')
        obj.data.uv_layers.active = layer
        layer.active_render = True
    select(objects)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=.004)
    bpy.ops.object.mode_set(mode='OBJECT')


def baking_proxy(objects):
    """ORM-only proxy, using already-proven UVs from independent source objects.

    This is not an exported/physical merge. Loop correspondence is verified before
    No BaseColor is baked on this proxy. Source roughness/metallic must be constants,
    so joining cannot change Generated/Object/Geometry Position-dependent results.
    """
    vertices, faces, face_materials, loop_uvs, mapping, materials = [], [], [], [], [], []
    for obj in objects:
        source_uv = obj.data.uv_layers.get('SurfaceUV') or obj.data.uv_layers.active
        base = len(vertices)
        vertices.extend(tuple(obj.matrix_world @ vertex.co) for vertex in obj.data.vertices)
        for face in obj.data.polygons:
            faces.append([base + index for index in face.vertices])
            material = obj.data.materials[face.material_index]
            if material not in materials: materials.append(material)
            face_materials.append(materials.index(material))
            for loop in face.loop_indices:
                mapping.append((obj.name, loop))
                loop_uvs.append(tuple(source_uv.data[loop].uv) if source_uv else (0., 0.))
    mesh = bpy.data.meshes.new('TemporaryBakeProxyMesh')
    mesh.from_pydata(vertices, [], faces); mesh.update()
    assert len(mesh.loops) == len(mapping) == len(loop_uvs)
    for face, expected, material_index in zip(mesh.polygons, faces, face_materials):
        assert list(face.vertices) == expected
        face.material_index = material_index
    for material in materials: mesh.materials.append(material)
    original_uv = mesh.uv_layers.new(name='SurfaceUV')
    for loop, uv in zip(original_uv.data, loop_uvs): loop.uv = uv
    proxy = bpy.data.objects.new('TemporaryBakeProxy_NOT_EXPORTED', mesh)
    bpy.context.scene.collection.objects.link(proxy)
    bake_uv = mesh.uv_layers.new(name='DeliveryBakeUV')
    mesh.uv_layers.active = bake_uv; bake_uv.active_render = True
    for proxy_loop, (name, source_loop) in enumerate(mapping):
        bake_uv.data[proxy_loop].uv = bpy.data.objects[name].data.uv_layers['DeliveryBakeUV'].data[source_loop].uv
    # Prove each exported loop will sample exactly the proxy UV it was baked from.
    assert all((bpy.data.objects[name].data.uv_layers['DeliveryBakeUV'].data[source_loop].uv-bake_uv.data[i].uv).length < 1e-8
               for i, (name, source_loop) in enumerate(mapping))
    return proxy


def uv_manifest(objects):
    return {obj.name: {'loops': len(obj.data.loops), 'float32_uv_sha256': hashlib.sha256(b''.join(
        struct.pack('<2f', *loop.uv) for loop in obj.data.uv_layers['DeliveryBakeUV'].data)).hexdigest()}
            for obj in objects}


def bake_map(objects, name, channel):
    print('BAKE_BEGIN ' + name, flush=True)
    image = bpy.data.images.new(name, width=SIZE, height=SIZE, alpha=False)
    image.colorspace_settings.name = 'sRGB' if channel == 'base' else 'Non-Color'
    materials = {m for obj in objects for m in obj.data.materials}
    restore = []
    for material in materials:
        nodes, links = material.node_tree.nodes, material.node_tree.links
        shader = principled(material)
        output = next(n for n in nodes if n.type == 'OUTPUT_MATERIAL' and n.is_active_output)
        old_link = output.inputs['Surface'].links[0].from_socket
        emission = nodes.new('ShaderNodeEmission')
        emission.inputs['Strength'].default_value = 1
        temporary = [emission]
        if channel == 'base':
            source = shader.inputs['Base Color']
            if source.is_linked: links.new(source.links[0].from_socket, emission.inputs['Color'])
            else: emission.inputs['Color'].default_value = source.default_value
        else:
            assert not shader.inputs['Roughness'].is_linked and not shader.inputs['Metallic'].is_linked, material.name
            combine = nodes.new('ShaderNodeCombineColor'); combine.mode = 'RGB'
            combine.inputs['Red'].default_value = 1.0  # Neutral AO; do not bake lighting into albedo.
            for key, socket_name in [('Green', 'Roughness'), ('Blue', 'Metallic')]:
                source = shader.inputs[socket_name]
                if source.is_linked: links.new(source.links[0].from_socket, combine.inputs[key])
                else: combine.inputs[key].default_value = source.default_value
            links.new(combine.outputs[0], emission.inputs['Color']); temporary.append(combine)
        links.new(emission.outputs[0], output.inputs['Surface'])
        target = nodes.new('ShaderNodeTexImage'); target.image = image
        for node in nodes: node.select = False
        target.select = True; nodes.active = target
        temporary.append(target)
        restore.append((material, output, old_link, temporary))
    select(objects)
    bpy.ops.object.bake(type='EMIT', use_clear=True, margin=8, use_selected_to_active=False)
    image.filepath_raw = str(OUT / 'textures' / (name + '.png'))
    image.file_format = 'PNG'; image.save()
    for material, output, old_link, temporary in restore:
        material.node_tree.links.new(old_link, output.inputs['Surface'])
        for node in temporary: material.node_tree.nodes.remove(node)
    # Reload native output as an external FILE texture before saving the delivery blend.
    loaded = bpy.data.images.load(image.filepath_raw, check_existing=False)
    loaded.colorspace_settings.name = image.colorspace_settings.name
    print('BAKE_SAVED ' + name, flush=True)
    return loaded


def plain_standard(name):
    mat = bpy.data.materials.new(name); mat.use_nodes = True
    nodes = mat.node_tree.nodes; nodes.clear()
    shader = nodes.new('ShaderNodeBsdfPrincipled'); shader.name = 'ClinicPrincipled'
    output = nodes.new('ShaderNodeOutputMaterial')
    mat.node_tree.links.new(shader.outputs['BSDF'], output.inputs['Surface'])
    return mat, shader


def final_materials(meshes, opaque, base, orm):
    atlas = {}
    for obj in opaque:
        path = C.group_for(obj.name)
        # Every roof, each door and each furniture group owns a distinct material resource.
        key = path if path.startswith(('Occlusion/', 'Doors/', 'Furniture/')) else 'Structure'
        if key not in atlas:
            mat, shader = plain_standard('CR5_' + key.replace('/', '_'))
            nodes, links = mat.node_tree.nodes, mat.node_tree.links
            uv = nodes.new('ShaderNodeUVMap'); uv.uv_map = 'SurfaceUV'
            tex = nodes.new('ShaderNodeTexImage'); tex.image = base
            links.new(uv.outputs[0], tex.inputs['Vector']); links.new(tex.outputs['Color'], shader.inputs['Base Color'])
            packed = nodes.new('ShaderNodeTexImage'); packed.image = orm
            links.new(uv.outputs[0], packed.inputs['Vector'])
            separate = nodes.new('ShaderNodeSeparateColor'); separate.mode = 'RGB'
            links.new(packed.outputs['Color'], separate.inputs[0])
            links.new(separate.outputs['Green'], shader.inputs['Roughness'])
            links.new(separate.outputs['Blue'], shader.inputs['Metallic'])
            atlas[key] = mat
        obj.data.materials.clear(); obj.data.materials.append(atlas[key])
        layer = obj.data.uv_layers['DeliveryBakeUV']
        for old in list(obj.data.uv_layers):
            if old != layer: obj.data.uv_layers.remove(old)
        layer.name = 'SurfaceUV'; obj.data.uv_layers.active = layer; layer.active_render = True
    for obj in meshes:
        if obj in opaque: continue
        source = principled(obj.data.materials[0])
        mat, shader = plain_standard('CR5_' + obj.name)
        for key in ('Base Color', 'Metallic', 'Roughness', 'Alpha', 'Emission Color', 'Emission Strength'):
            assert not source.inputs[key].is_linked, (obj.name, key)
            shader.inputs[key].default_value = source.inputs[key].default_value
        # Do not merge glass into opaque parts, nor share a status lamp with room lighting.
        obj.data.materials.clear(); obj.data.materials.append(mat)
        if not obj.data.uv_layers:
            obj.data.uv_layers.new(name='SurfaceUV')
        while len(obj.data.uv_layers) > 1: obj.data.uv_layers.remove(obj.data.uv_layers[-1])
        obj.data.uv_layers[0].name = 'SurfaceUV'; obj.data.uv_layers.active_index = 0
        obj.data.uv_layers[0].active_render = True
    return atlas


def read_glb(path, expected, required_nodes):
    data = path.read_bytes()
    magic, version, length = struct.unpack_from('<4sII', data)
    assert magic == b'glTF' and version == 2 and length == len(data)
    offset = 12; document = None; binary = None
    while offset < len(data):
        size, kind = struct.unpack_from('<I4s', data, offset); offset += 8
        chunk = data[offset:offset+size]; offset += size
        if kind == b'JSON': document = json.loads(chunk)
        if kind == b'BIN\x00': binary = chunk
    assert document and binary

    def accessor(index):
        a = document['accessors'][index]; view = document['bufferViews'][a['bufferView']]
        assert 'sparse' not in a and not a.get('normalized', False)
        width = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[a['type']]
        fmt, byte = {5121: ('B', 1), 5123: ('H', 2), 5125: ('I', 4), 5126: ('f', 4)}[a['componentType']]
        start = view.get('byteOffset', 0) + a.get('byteOffset', 0)
        stride = view.get('byteStride', width * byte)
        return [struct.unpack_from('<' + fmt * width, binary, start+i*stride) for i in range(a['count'])]

    rows, nodes, triangles = {}, {}, 0

    def visit(index, parent):
        nonlocal triangles
        node = document['nodes'][index]
        if 'matrix' in node:
            matrix = Matrix([node['matrix'][i:i+4] for i in range(0, 16, 4)]).transposed()
        else:
            x, y, z, w = node.get('rotation', [0, 0, 0, 1])
            matrix = Matrix.LocRotScale(Vector(node.get('translation', [0, 0, 0])),
                                       Quaternion((w, x, y, z)), Vector(node.get('scale', [1, 1, 1])))
        world = parent @ matrix; name = node.get('name', '')
        assert name not in nodes, 'Duplicate exported node name: ' + name
        nodes[name] = {'position': list(world.translation), 'matrix': [list(r) for r in world]}
        if 'mesh' in node:
            points = []
            for primitive in document['meshes'][node['mesh']]['primitives']:
                assert primitive.get('mode', 4) == 4
                assert 'TEXCOORD_0' in primitive['attributes'] and 'TEXCOORD_1' not in primitive['attributes']
                positions = accessor(primitive['attributes']['POSITION'])
                uv = accessor(primitive['attributes']['TEXCOORD_0'])
                assert len(positions) == len(uv) and all(math.isfinite(v) for pair in uv for v in pair)
                assert all(-EPS <= v <= 1+EPS for pair in uv for v in pair), name
                indices = accessor(primitive['indices'])
                assert len(indices) % 3 == 0 and all(i[0] < len(positions) for i in indices)
                triangles += len(indices)//3
                points.extend(world @ Vector(v) for v in positions)
            rows[name] = bounds(points)
        for child in node.get('children', []): visit(child, world)

    for index in document['scenes'][document.get('scene', 0)]['nodes']: visit(index, Matrix.Identity(4))
    assert set(rows) == set(expected), 'Export dropped or renamed a mesh'
    for name, row in rows.items():
        assert all(abs(row[key][i]-expected[name][key][i]) <= EPS for key in ('min', 'max') for i in range(3)), name
    assert required_nodes <= set(nodes), 'Export lost a semantic node'
    for name, value in C.ANCHORS.items(): assert (Vector(nodes[name]['position'])-Vector(value)).length <= EPS, name
    for path, value in C.PIVOTS.items():
        name = path.split('/')[-1]
        assert (Vector(nodes[name]['position'])-Vector(value)).length <= EPS, name
    return {'sha256': C.sha(path), 'bytes': len(data), 'mesh_count': len(rows), 'triangle_count': triangles,
            'nodes': nodes, 'actual_local_bounds': rows,
            'materials': [m.get('name') for m in document.get('materials', [])],
            'images': document.get('images', []), 'all_mesh_bounds_match_source_10um': True,
            'all_meshes_have_single_uv0': True, 'anchors_and_pivots_verified': True}


def main():
    assert not (OUT / 'clinic_reception_v5.glb').exists(), 'Refuse to overwrite a delivered candidate'
    original = C.inventory()
    bpy.ops.wm.open_mainfile(filepath=str(C.SOURCE / 'clinic_reception_v5.blend'))
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'; scene.cycles.device = 'CPU'; scene.cycles.samples = 1
    scene.render.threads_mode = 'FIXED'; scene.render.threads = 2
    scene.render.bake.use_selected_to_active = False
    (OUT / 'source_inputs').mkdir(exist_ok=True); (OUT / 'textures').mkdir(exist_ok=True)
    for image in bpy.data.images:
        if image.source != 'FILE': continue
        source = Path(bpy.path.abspath(image.filepath)).resolve()
        assert source.is_file(), source
        destination = OUT / 'source_inputs' / source.name
        if destination.exists(): assert C.sha(destination) == C.sha(source)
        else: shutil.copy2(source, destination)
        image.filepath = str(destination)
    meshes = sorted([o for o in scene.objects if o.type == 'MESH'], key=lambda o: o.name)
    assert len(meshes) == original['mesh_count']
    before = {o.name: [tuple(v) for v in mesh_points(o)] for o in meshes}
    expected = {o.name: bounds([godot(v) for v in mesh_points(o)]) for o in meshes}
    root, groups = build_hierarchy(meshes)
    copied_materials = {}
    for obj in meshes:
        assert all((Vector(a)-b).length <= EPS for a, b in zip(before[obj.name], mesh_points(obj))), obj.name
        # Copy each source shader once, avoiding 186 duplicate shader compilations.
        for i, mat in enumerate(obj.data.materials):
            if mat not in copied_materials: copied_materials[mat] = mat.copy()
            obj.data.materials[i] = copied_materials[mat]
    opaque = [o for o in meshes if 'Glass' not in o.name and o.name not in ('FrontWindowLeft', 'FrontWindowRight', 'EastWindow', 'ReceptionLight') and not o.name.startswith('InteriorLampDiffuser')]
    print('SOURCE_HIERARCHY_VERIFIED', flush=True)
    # BaseColor remains on every original object, including its coordinates/bounds.
    prepare_unique_uv(opaque)
    uv_before = uv_manifest(opaque)
    (OUT/'bake_uv_checkpoint.json').write_text(json.dumps(uv_before, indent=2), encoding='utf-8')
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'before_base_checkpoint.blend'), relative_remap=False)
    base = bake_map(opaque, 'ReceptionV5_BaseColor', 'base')
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'base_complete_checkpoint.blend'), relative_remap=False)
    print('BASE_COMPLETED_AND_CHECKPOINT_SAVED', flush=True)
    proxy = baking_proxy(opaque)
    print('ORM_PROXY_UV_CORRESPONDENCE_VERIFIED', flush=True)
    orm = bake_map([proxy], 'ReceptionV5_ORM', 'orm')
    assert uv_manifest(opaque) == uv_before, 'ORM proxy changed original UVs'
    proxy_mesh = proxy.data
    bpy.data.objects.remove(proxy, do_unlink=True); bpy.data.meshes.remove(proxy_mesh)
    final_materials(meshes, opaque, base, orm)
    for image in bpy.data.images:
        if image.source == 'FILE' and image.filepath:
            image.filepath = '//' + Path(image.filepath).resolve().relative_to(OUT).as_posix()
    blend = OUT / 'clinic_reception_v5_delivery.blend'
    bpy.ops.wm.save_as_mainfile(filepath=str(blend), relative_remap=False)
    members = [root] + list(root.children_recursive)
    select(members)
    glb = OUT / 'clinic_reception_v5.glb'
    print('EXPLICIT_GLB_EXPORT_BEGIN', flush=True)
    bpy.ops.export_scene.gltf(filepath=str(glb), export_format='GLB', use_selection=True,
                            export_apply=True, export_yup=True, export_texcoords=True,
                            export_normals=True, export_materials='EXPORT', export_cameras=False,
                            export_lights=False, export_animations=False, export_extras=True)
    actual = read_glb(glb, expected, {o.name for o in members})
    actual.update(status='export_candidate_binary_checked_not_game_validated',
                  source_sha256=C.SOURCE_SHA, delivery_blend_sha256=C.sha(blend),
                  source_contract=original, runtime_files_written=False,
                  textures={p.name: C.sha(p) for p in sorted((OUT/'textures').glob('*.png'))},
                  source_uv_checkpoint=uv_before,
                  limits=['No game collision/occlusion integration', 'No GLB reimport camera comparison yet',
                          '186 editable mesh objects preserved; not a draw-call budget pass',
                          'No runtime door motion, rear supports, or interactions are created'])
    (OUT / 'delivery_report.json').write_text(json.dumps(actual, ensure_ascii=False, indent=2), encoding='utf-8')
    assert C.sha(C.SOURCE / 'clinic_reception_v5.blend') == C.SOURCE_SHA
    print('RECEPTION_EXPORT_CANDIDATE ' + json.dumps({k: actual[k] for k in ('sha256', 'bytes', 'mesh_count', 'triangle_count')}), flush=True)


if __name__ == '__main__': main()
