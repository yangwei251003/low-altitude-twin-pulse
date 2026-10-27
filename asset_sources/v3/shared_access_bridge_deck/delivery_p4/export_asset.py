"""Split one baked atlas into original 12 parts; explicit GLB, raw readback.

Uses the repository pump exporter method, preserving local part translations.
Writes only this authorized source delivery directory. No rendering/production.
"""
from pathlib import Path
import collections
import os
import sys
import time

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import *
from verify_export import verify_raw


def empty(name, parent=None, position=(0,0,0)):
    obj = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(obj)
    obj.parent = parent
    obj.matrix_basis = Matrix.Identity(4)
    obj.location = bp(position)
    return obj


def final_material(maps):
    material = bpy.data.materials.new('SharedBridgeDeck_PBR')
    material.use_nodes = True
    material.use_backface_culling = True
    nodes, links = material.node_tree.nodes, material.node_tree.links
    nodes.clear()
    p = nodes.new('ShaderNodeBsdfPrincipled')
    output = nodes.new('ShaderNodeOutputMaterial')
    links.new(p.outputs[0], output.inputs['Surface'])
    uv = nodes.new('ShaderNodeUVMap')
    uv.uv_map = 'SurfaceUV'
    textures = {}
    for channel in ['BaseColor','ORM','Normal']:
        image = bpy.data.images.load(maps[channel], check_existing=False)
        image.colorspace_settings.name = 'sRGB' if channel == 'BaseColor' else 'Non-Color'
        node = nodes.new('ShaderNodeTexImage')
        node.name = 'Baked_'+channel
        node.image = image
        links.new(uv.outputs[0], node.inputs['Vector'])
        textures[channel] = node
    links.new(textures['BaseColor'].outputs['Color'], p.inputs['Base Color'])
    split = nodes.new('ShaderNodeSeparateColor')
    split.mode = 'RGB'
    links.new(textures['ORM'].outputs['Color'], split.inputs[0])
    links.new(split.outputs['Green'], p.inputs['Roughness'])
    links.new(split.outputs['Blue'], p.inputs['Metallic'])
    normal = nodes.new('ShaderNodeNormalMap')
    normal.space = 'TANGENT'
    normal.uv_map = 'SurfaceUV'
    normal.inputs['Strength'].default_value = 1
    links.new(textures['Normal'].outputs['Color'], normal.inputs['Color'])
    links.new(normal.outputs[0], p.inputs['Normal'])
    p.inputs['Alpha'].default_value = 1
    p.inputs['Emission Strength'].default_value = 0
    return material


def split_parts(proxy, material):
    mesh = proxy.data
    mesh.calc_loop_triangles()
    uv = mesh.uv_layers['DeliveryBakeUV']
    group = mesh.attributes['DeliveryGroup']
    for obj in list(bpy.data.objects):
        if obj != proxy and (obj.get('source_body_id') or obj.type == 'EMPTY'):
            bpy.data.objects.remove(obj, do_unlink=True)
    root = empty('SharedBridgeDeck')
    root['world_origin_godot'] = [15,5,0]
    root['p4_source_sha256'] = SOURCE_SHA
    moving = empty('MovingDeck', root)
    pin = empty('LockPin', root)
    pin['godot_translation_when_inserted'] = [0,-.3,0]
    parents = {'SharedBridgeDeck':root, 'MovingDeck':moving, 'LockPin':pin}
    selected = [root,moving,pin]
    expected = {}
    for index, name in enumerate(PARTS):
        center = bp(SPEC[name]['translation'])
        remap, vertices, faces, uvs, normals = {}, [], [], [], []
        for tri in mesh.loop_triangles:
            if group.data[tri.polygon_index].value != index:
                continue
            face = []
            for vi, li in zip(tri.vertices, tri.loops):
                if vi not in remap:
                    remap[vi] = len(vertices)
                    vertices.append(tuple(mesh.vertices[vi].co-center))
                face.append(remap[vi])
                uvs.append(tuple(uv.data[li].uv))
                normals.append(tuple(mesh.corner_normals[li].vector))
            faces.append(face)
        local = bpy.data.meshes.new(name+'_RuntimeMesh')
        local.from_pydata(vertices, [], faces)
        local.update()
        for poly in local.polygons:
            poly.use_smooth = True
        local.normals_split_custom_set(normals)
        local.uv_layers.new(name='SurfaceUV')
        for loop, value in zip(local.uv_layers['SurfaceUV'].data, uvs):
            loop.uv = value
        local.uv_layers.active_index = 0
        local.uv_layers[0].active_render = True
        local.materials.append(material)
        obj = bpy.data.objects.new(name, local)
        bpy.context.scene.collection.objects.link(obj)
        obj.parent = parents[SPEC[name]['parent']]
        obj.location = center
        obj['source_body_id'] = name
        obj['collision_scope'] = 'No authored physics; root preserves production bodies/hidden Visual.'
        selected.append(obj)
        local.calc_loop_triangles()
        assert len(local.loop_triangles) == SPEC[name]['triangles'], name
        expected[name] = [[{'p':gp(local.vertices[vi].co), 'n':gp(local.corner_normals[li].vector),
                           'uv':list(local.uv_layers[0].data[li].uv)} for vi,li in zip(tri.vertices,tri.loops)] for tri in local.loop_triangles]
    for row in CONTRACT['anchors']:
        selected.append(empty(row['name'], parents[row['parent']], row['translation']))
    bpy.data.objects.remove(proxy, do_unlink=True)
    assert sum(len(v) for v in expected.values()) == 10912
    return selected, expected


def main():
    started = time.monotonic()
    candidate = OUT/'shared_access_bridge_deck.glb'
    assert not candidate.exists(), 'Never overwrite previous exported bytes.'
    assert sha(SOURCE) == SOURCE_SHA
    report = json.loads((OUT/'bake_report.json').read_text(encoding='utf-8'))
    assert report['status'] == 'BAKE_COMPLETE_PENDING_EXPORT'
    assert sha(OUT/'bake_complete.blend') == report['blend_sha256']
    print(json.dumps({'stage':'export_start','pid':os.getpid(),'threads':2}), flush=True)
    bpy.ops.wm.open_mainfile(filepath=str(OUT/'bake_complete.blend'))
    maps = {r['channel']:r['path'] for r in report['textures']}
    assert all(sha(r['path']) == r['sha256'] for r in report['textures'])
    selected, expected = split_parts(bpy.data.objects['DeliveryBakeProxy'], final_material(maps))
    write_json(OUT/'expected_runtime_triangles.json', expected)
    blend = OUT/'shared_access_bridge_deck_delivery.blend'
    bpy.ops.wm.save_as_mainfile(filepath=str(blend), relative_remap=False)
    for image in bpy.data.images:
        if image.source == 'FILE' and image.filepath:
            image.filepath = bpy.path.relpath(bpy.path.abspath(image.filepath))
    bpy.ops.wm.save_as_mainfile(filepath=str(blend), relative_remap=False)
    names = [o.name for o in selected]
    bpy.ops.wm.open_mainfile(filepath=str(blend))
    for image in bpy.data.images:
        if image.source == 'FILE' and image.filepath:
            assert Path(bpy.path.abspath(image.filepath)).is_file()
            image.reload()
            pixel = tuple(image.pixels[:4])
            assert len(pixel) == 4 and image.has_data
    select([bpy.data.objects[n] for n in names])
    bpy.ops.export_scene.gltf(filepath=str(candidate), export_format='GLB', use_selection=True,
        export_yup=True, export_apply=False, export_texcoords=True, export_normals=True,
        export_tangents=True, export_materials='EXPORT', export_extras=True,
        export_cameras=False, export_lights=False, export_animations=False)
    raw = verify_raw(candidate, expected, maps, CONTRACT)
    write_json(OUT/'raw_glb_report.json', raw)
    assert sha(SOURCE) == SOURCE_SHA
    write_json(OUT/'export_report.json', {'status':'EXPORTED_RAW_VERIFIED_PENDING_SAME_BYTE_REIMPORT',
        'pid':os.getpid(),'seconds':time.monotonic()-started,'source_sha256':SOURCE_SHA,
        'delivery_blend_sha256':sha(blend),'glb_sha256':raw['sha256'],
        'runtime_files_written':False,'limits':['No Godot, actual movement, visibility or game-camera verification.']})
    print(json.dumps({'stage':'export_exit','pid':os.getpid(),'seconds':time.monotonic()-started,'sha256':raw['sha256']}), flush=True)


if __name__ == '__main__':
    main()
