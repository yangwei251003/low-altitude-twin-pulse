"""P4 delivery; adapted from the repository's tested pump delivery_v8 pipeline.

No engine is started by importing this file. Run only inside an assigned CPU2
Blender window. All outputs remain in this source directory, never assets/.
"""
from pathlib import Path
import hashlib
import json
import math
import shutil
import struct

import bpy
from mathutils import Matrix, Vector

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[3]
CONTRACT = json.loads((OUT / 'prepared_contract.json').read_text(encoding='utf-8'))
SOURCE = (OUT / CONTRACT['source_blend']).resolve()
SOURCE_SHA = CONTRACT['source_blend_sha256']
SIZE = 2048
PARTS = [p['name'] for p in CONTRACT['parts']]
SPEC = {p['name']: p for p in CONTRACT['parts']}
UVS = ['SurfaceUV', 'SourceXZ', 'SourceY', 'PaintPanelUV']
COLORS = ['WeatherUse']


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def gp(p):
    return [p[0], p[2], -p[1]]


def bp(p):
    return Vector((p[0], -p[2], p[1]))


def write_json(path, data):
    Path(path).write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def select(objects):
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:
        obj.hide_set(False)
        obj.hide_viewport = False
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]


def shader(material):
    nodes = [n for n in material.node_tree.nodes if n.type == 'BSDF_PRINCIPLED']
    assert len(nodes) == 1, material.name
    return nodes[0]


def audit_material(material):
    pending = [shader(material)]
    seen = set()
    rows = []
    while pending:
        node = pending.pop()
        if node.name in seen:
            continue
        seen.add(node.name)
        assert node.type not in {'TEX_COORD', 'NEW_GEOMETRY', 'OBJECT_INFO'}, (material.name, node.type)
        if node.type.startswith('TEX_') and 'Vector' in node.inputs:
            assert node.inputs['Vector'].is_linked, (material.name, node.name, 'implicit vector')
        if node.type == 'UVMAP':
            assert node.uv_map in UVS, (material.name, node.uv_map)
        if node.type == 'VERTEX_COLOR':
            assert node.layer_name in COLORS, (material.name, node.layer_name)
        if node.type == 'NORMAL_MAP':
            assert node.uv_map in UVS and node.space == 'TANGENT'
        pending.extend(link.from_node for socket in node.inputs for link in socket.links)
        rows.append({'name': node.name, 'type': node.type})
    return {'material': material.name, 'active_nodes': rows, 'explicit_source_coordinates': True}


def source_parts():
    result = [bpy.data.objects.get(name) for name in PARTS]
    assert all(o is not None and o.type == 'MESH' for o in result)
    assert {o.name for o in bpy.data.objects if o.get('source_body_id')} == set(PARTS)
    for obj in result:
        assert obj.parent.name == SPEC[obj.name]['parent']
        assert max(abs(a-b) for a,b in zip(gp(obj.location), SPEC[obj.name]['translation'])) < 1e-6
        assert max(abs(v) for v in obj.rotation_euler) < 1e-7
        assert max(abs(v-1) for v in obj.scale) < 1e-7
    return result


def geometry_fingerprint(parts):
    """Exact evaluated geometry+corner normals, excludes UV/material changes."""
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    rows = {}
    for obj in parts:
        me = bpy.data.meshes.new_from_object(obj.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
        me.calc_loop_triangles()
        data = bytearray()
        for tri in me.loop_triangles:
            for vi, li in zip(tri.vertices, tri.loops):
                data.extend(struct.pack('<6f', *me.vertices[vi].co, *me.corner_normals[li].vector))
        rows[obj.name] = {'triangles': len(me.loop_triangles), 'sha256': hashlib.sha256(data).hexdigest()}
        bpy.data.meshes.remove(me)
    return rows


def fix_end_uv(parts):
    """Only BlueSteel X-facing caps: stable Z/Y projection; no geometry edit."""
    before = geometry_fingerprint(parts)
    changes = []
    for obj in parts:
        if obj.name not in ('BridgeDeck', 'NorthGuard', 'SouthGuard'):
            continue
        me = obj.data
        layer = me.uv_layers['PaintPanelUV']
        for face in me.polygons:
            if me.materials[face.material_index].name != 'IB_BlueSteel' or abs(gp(face.normal)[0]) < .7:
                continue
            old, new = [], []
            for li in face.loop_indices:
                p = gp(obj.matrix_world @ me.vertices[me.loops[li].vertex_index].co)
                old.append(list(layer.data[li].uv))
                if obj.name == 'BridgeDeck':
                    value = (.5 + p[2]/6, .55 + (p[1]+.35)*.40)
                else:
                    center_z = SPEC[obj.name]['translation'][2]
                    value = (.5 + (p[2]-center_z)/6, p[1])
                layer.data[li].uv = value
                new.append(list(layer.data[li].uv))
            if old != new:
                changes.append({'part': obj.name, 'polygon': face.index, 'before': old, 'after': new})
        me.update()
    after = geometry_fingerprint(parts)
    assert before == after, 'UV-only edit changed evaluated triangles or normals'
    assert {r['part'] for r in changes} == {'BridgeDeck', 'NorthGuard', 'SouthGuard'}
    # Actual corrected planar faces must have nonzero projected area, not merely
    # a nonzero coordinate range across the whole object.
    for row in changes:
        points = row['after']
        area = abs(sum(points[i][0]*points[(i+1)%len(points)][1] - points[(i+1)%len(points)][0]*points[i][1] for i in range(len(points))))*.5
        assert area > 1e-12, (row['part'], row['polygon'], 'collapsed corrected cap')
    return {'geometry_before': before, 'geometry_after': after, 'changed_faces': changes,
            'scope': 'Only BlueSteel X-facing short caps; original P4 blend is immutable.'}


def copy_images():
    target = OUT / 'source_inputs'
    target.mkdir(exist_ok=True)
    rows = []
    for image in bpy.data.images:
        if image.source != 'FILE' or not image.filepath:
            continue
        src = Path(bpy.path.abspath(image.filepath)).resolve()
        dst = target / src.name
        assert src.is_file(), src
        if dst.exists():
            assert sha(src) == sha(dst)
        else:
            shutil.copyfile(src, dst)
        image.filepath = str(dst)
        image.reload()
        # reload invalidates the lazy buffer; read real pixels before has_data.
        pixel = tuple(image.pixels[:4])
        assert len(pixel) == 4 and image.has_data, (str(dst), list(image.size))
        assert sha(src) == sha(dst)
        rows.append({'source': str(src), 'copy': str(dst), 'sha256': sha(dst), 'colorspace': image.colorspace_settings.name})
    return rows


def corner_fingerprint(mesh):
    values = []
    for key in UVS:
        assert key in mesh.uv_layers, key
        values.extend(v for loop in mesh.uv_layers[key].data for v in loop.uv)
    for key in COLORS:
        attr = mesh.color_attributes.get(key)
        assert attr is not None and attr.domain == 'CORNER', key
        values.extend(v for c in attr.data for v in c.color)
    values.extend(float(v.value) for v in mesh.attributes['DeliveryGroup'].data)
    return hashlib.sha256(struct.pack('<'+'f'*len(values), *values)).hexdigest()


def make_proxy(parts):
    dg = bpy.context.evaluated_depsgraph_get()
    vertices, faces, normals, mids, groups = [], [], [], [], []
    uv = {k: [] for k in UVS}
    colors = {k: [] for k in COLORS}
    materials, source_rows = [], []
    for obj in parts:
        me = bpy.data.meshes.new_from_object(obj.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
        me.calc_loop_triangles()
        assert len(me.loop_triangles) == SPEC[obj.name]['triangles'], obj.name
        normal_matrix = obj.matrix_world.to_3x3().inverted().transposed()
        base = len(vertices)
        vertices.extend(tuple(obj.matrix_world @ v.co) for v in me.vertices)
        points = [gp(obj.matrix_world @ v.co) for v in me.vertices]
        bounds = {'min': [min(p[i] for p in points) for i in range(3)], 'max': [max(p[i] for p in points) for i in range(3)]}
        assert max(abs(a-b) for key in ('min','max') for a,b in zip(bounds[key], SPEC[obj.name]['root_bounds_expected'][key])) < 2e-6
        source_rows.append({'name': obj.name, 'triangles': len(me.loop_triangles), 'bounds': bounds})
        for tri in me.loop_triangles:
            material = me.materials[me.polygons[tri.polygon_index].material_index]
            if material not in materials:
                materials.append(material)
            faces.append(tuple(base + v for v in tri.vertices))
            mids.append(materials.index(material))
            groups.append(PARTS.index(obj.name))
            for li in tri.loops:
                normals.append(tuple((normal_matrix @ me.corner_normals[li].vector).normalized()))
                for k in UVS:
                    assert k in me.uv_layers, (obj.name, k)
                    uv[k].append(tuple(me.uv_layers[k].data[li].uv))
                for k in COLORS:
                    attr = me.color_attributes.get(k)
                    assert attr is not None and attr.domain == 'CORNER', (obj.name, k)
                    colors[k].append(tuple(attr.data[li].color))
        bpy.data.meshes.remove(me)
    assert len(faces) == 10912 and len(normals) == 32736
    mesh = bpy.data.meshes.new('BridgeBakeProxy_Exact10912Triangles')
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    for material in materials:
        mesh.materials.append(material)
    for poly, indices, mid in zip(mesh.polygons, faces, mids):
        assert tuple(poly.vertices) == indices
        poly.material_index = mid
        poly.use_smooth = True
    mesh.normals_split_custom_set(normals)
    for key, values in uv.items():
        mesh.uv_layers.new(name=key)
        for loop, value in zip(mesh.uv_layers[key].data, values):
            loop.uv = value
    for key, values in colors.items():
        mesh.color_attributes.new(name=key, type='FLOAT_COLOR', domain='CORNER')
        for loop, value in zip(mesh.color_attributes[key].data, values):
            loop.color = value
    # Reacquire by name after all allocations; never retain old RNA layer handles.
    assert all(tuple(a.uv) == b for key, values in uv.items() for a,b in zip(mesh.uv_layers[key].data, values))
    assert all(tuple(a.color) == b for key, values in colors.items() for a,b in zip(mesh.color_attributes[key].data, values))
    attr = mesh.attributes.new(name='DeliveryGroup', type='INT', domain='FACE')
    for a, g in zip(attr.data, groups):
        a.value = g
    proxy = bpy.data.objects.new('DeliveryBakeProxy', mesh)
    bpy.context.scene.collection.objects.link(proxy)
    proxy.matrix_basis = Matrix.Identity(4)
    for obj in parts:
        obj.hide_render = True
        obj.hide_set(True)
    return proxy, source_rows, [audit_material(m) for m in materials]


def unique_uv(proxy):
    mesh = proxy.data
    before = corner_fingerprint(mesh)
    mesh.uv_layers.new(name='DeliveryBakeUV')
    mesh.uv_layers.active_index = mesh.uv_layers.find('DeliveryBakeUV')
    for layer in mesh.uv_layers:
        layer.active_render = layer.name == 'DeliveryBakeUV'
    select([proxy])
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=.004)
    bpy.ops.object.mode_set(mode='OBJECT')
    assert before == corner_fingerprint(mesh), 'UV packing changed source coordinates/roles/group IDs'
    uv = mesh.uv_layers['DeliveryBakeUV']
    values = [float(v) for loop in uv.data for v in loop.uv]
    assert all(math.isfinite(v) and -1e-6 <= v <= 1.000001 for v in values)
    mesh.calc_loop_triangles()
    areas = []
    for tri in mesh.loop_triangles:
        a,b,c = [uv.data[i].uv.copy() for i in tri.loops]
        areas.append(abs((b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x))*.5)
    assert all(a > 1e-14 for a in areas), 'UV collapsed a real triangle'
    return {'loops': len(values)//2, 'float32_sha256': hashlib.sha256(struct.pack('<'+'f'*len(values), *values)).hexdigest(),
            'size': SIZE, 'island_margin': .004, 'minimum_triangle_uv_area': min(areas),
            'summed_uv_area': sum(areas), 'source_corner_sha256_before_after': before,
            'scope': 'Actual smart_project and finite noncollapsed triangles; no claim of exhaustive independent UV overlap proof.'}


def bake(proxy, channel):
    print('BAKE_BEGIN '+channel, flush=True)
    (OUT/'textures').mkdir(exist_ok=True)
    image = bpy.data.images.new('SharedBridgeDeck_'+channel, width=SIZE, height=SIZE, alpha=False, float_buffer=False)
    image.colorspace_settings.name = 'sRGB' if channel == 'BaseColor' else 'Non-Color'
    restore = []
    try:
        for material in proxy.data.materials:
            nodes, links = material.node_tree.nodes, material.node_tree.links
            p = shader(material)
            output = next(n for n in nodes if n.type == 'OUTPUT_MATERIAL' and n.is_active_output)
            old = output.inputs['Surface'].links[0].from_socket
            temporary = []
            restore.append((material, output, old, temporary))
            if channel != 'Normal':
                emission = nodes.new('ShaderNodeEmission')
                emission.inputs['Strength'].default_value = 1
                temporary.append(emission)
                if channel == 'BaseColor':
                    socket = p.inputs['Base Color']
                    if socket.is_linked:
                        links.new(socket.links[0].from_socket, emission.inputs['Color'])
                    else:
                        emission.inputs['Color'].default_value = socket.default_value
                else:
                    combine = nodes.new('ShaderNodeCombineColor')
                    combine.mode = 'RGB'
                    combine.inputs['Red'].default_value = 1
                    temporary.append(combine)
                    for name, key in [('Green','Roughness'), ('Blue','Metallic')]:
                        socket = p.inputs[key]
                        if socket.is_linked:
                            links.new(socket.links[0].from_socket, combine.inputs[name])
                        else:
                            combine.inputs[name].default_value = socket.default_value
                    links.new(combine.outputs[0], emission.inputs['Color'])
                links.new(emission.outputs[0], output.inputs['Surface'])
            target = nodes.new('ShaderNodeTexImage')
            target.image = image
            temporary.append(target)
            for node in nodes:
                node.select = False
            target.select = True
            nodes.active = target
        select([proxy])
        scene = bpy.context.scene
        scene.render.bake.normal_space = 'TANGENT'
        scene.render.bake.normal_r = 'POS_X'
        scene.render.bake.normal_g = 'POS_Y'
        scene.render.bake.normal_b = 'POS_Z'
        bpy.ops.object.bake(type='NORMAL' if channel == 'Normal' else 'EMIT', use_clear=True, margin=8, use_selected_to_active=False)
        image.filepath_raw = str(OUT/'textures'/('SharedBridgeDeck_'+channel+'.png'))
        image.file_format = 'PNG'
        image.save()
    finally:
        for material, output, old, temporary in restore:
            material.node_tree.links.new(old, output.inputs['Surface'])
            for node in temporary:
                material.node_tree.nodes.remove(node)
    loaded = bpy.data.images.load(image.filepath_raw, check_existing=False)
    loaded.colorspace_settings.name = image.colorspace_settings.name
    assert len(tuple(loaded.pixels[:4])) == 4
    assert list(loaded.size) == [SIZE,SIZE] and loaded.has_data
    print('BAKE_DONE '+channel, flush=True)
    return {'channel': channel, 'path': image.filepath_raw, 'sha256': sha(image.filepath_raw),
            'bytes': Path(image.filepath_raw).stat().st_size, 'colorspace': loaded.colorspace_settings.name, 'size': list(loaded.size)}
