from pathlib import Path
import sys,os,time
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parent))
from common import *
from verify_export import verify_raw

def final_material(maps):
    material=bpy.data.materials.new(MATERIAL_NAME);material.use_nodes=True;material.use_backface_culling=True
    nodes,links=material.node_tree.nodes,material.node_tree.links;nodes.clear()
    p=nodes.new('ShaderNodeBsdfPrincipled');out=nodes.new('ShaderNodeOutputMaterial');links.new(p.outputs[0],out.inputs['Surface'])
    uv=nodes.new('ShaderNodeUVMap');uv.uv_map='SurfaceUV';textures={}
    for channel in ['BaseColor','ORM','Normal']:
        image=bpy.data.images.load(maps[channel],check_existing=False)
        image.colorspace_settings.name='sRGB' if channel=='BaseColor' else 'Non-Color'
        node=nodes.new('ShaderNodeTexImage');node.image=image;node.name='Baked_'+channel
        links.new(uv.outputs[0],node.inputs['Vector']);textures[channel]=node
    links.new(textures['BaseColor'].outputs['Color'],p.inputs['Base Color'])
    split=nodes.new('ShaderNodeSeparateColor');split.mode='RGB';links.new(textures['ORM'].outputs['Color'],split.inputs[0])
    links.new(split.outputs['Green'],p.inputs['Roughness']);links.new(split.outputs['Blue'],p.inputs['Metallic'])
    normal=nodes.new('ShaderNodeNormalMap');normal.space='TANGENT';normal.uv_map='SurfaceUV';normal.inputs['Strength'].default_value=1
    links.new(textures['Normal'].outputs['Color'],normal.inputs['Color']);links.new(normal.outputs[0],p.inputs['Normal'])
    p.inputs['Alpha'].default_value=1;p.inputs['Emission Strength'].default_value=0
    return material

def main():
    started=time.monotonic();candidate=OUT/'i2_canal_revetment_1p3.glb'
    assert not candidate.exists() and sha(SOURCE)==SOURCE_SHA
    report=json.loads((OUT/'bake_report.json').read_text(encoding='utf-8'))
    assert report['status']=='BAKE_COMPLETE_PENDING_EXPORT' and sha(OUT/'bake_complete.blend')==report['blend_sha256']
    print(json.dumps({'stage':'export_start','pid':os.getpid(),'threads':2}),flush=True)
    bpy.ops.wm.open_mainfile(filepath=str(OUT/'bake_complete.blend'))
    maps={r['channel']:r['path'] for r in report['textures']}
    assert all(sha(r['path'])==r['sha256'] for r in report['textures'])
    proxy=bpy.data.objects['DeliveryBakeProxy'];me=proxy.data;me.calc_loop_triangles();uv=me.uv_layers['DeliveryBakeUV']
    vertices=[tuple(v.co) for v in me.vertices];faces=[];uvs=[];normals=[]
    for tri in me.loop_triangles:
        faces.append(tuple(tri.vertices))
        for li in tri.loops:uvs.append(tuple(uv.data[li].uv));normals.append(tuple(me.corner_normals[li].vector))
    assert len(faces)==report['triangles']
    mesh=bpy.data.meshes.new(MESH_NAME+'_Runtime');mesh.from_pydata(vertices,[],faces);mesh.update()
    for poly in mesh.polygons:poly.use_smooth=True
    mesh.normals_split_custom_set(normals);mesh.uv_layers.new(name='SurfaceUV')
    for target,value in zip(mesh.uv_layers['SurfaceUV'].data,uvs):target.uv=value
    mesh.uv_layers.active_index=0;mesh.uv_layers[0].active_render=True;mesh.materials.append(final_material(maps))
    root=bpy.data.objects.new(ROOT_NAME,None);bpy.context.scene.collection.objects.link(root)
    obj=bpy.data.objects.new(MESH_NAME,mesh);bpy.context.scene.collection.objects.link(obj);obj.parent=root
    root['source_origin']='Top-front midpoint; Godot +Z faces water; all thickness into -Z'
    root['frozen_editable_source_sha256']=SOURCE_SHA
    root['collision_scope']='None exported; root integration owns true terrain/collision'
    assert root.matrix_world==Matrix.Identity(4) and obj.matrix_world==Matrix.Identity(4)
    mesh.calc_loop_triangles()
    expected={MESH_NAME:[[{ 'p':gp(mesh.vertices[vi].co), 'n':gp(mesh.corner_normals[li].vector), 'uv':list(mesh.uv_layers[0].data[li].uv)}
                         for vi,li in zip(tri.vertices,tri.loops)] for tri in mesh.loop_triangles]}
    write_json(OUT/'expected_runtime_triangles.json',expected)
    for o in list(bpy.data.objects):
        if o.get('editable_piece') or o==proxy:bpy.data.objects.remove(o,do_unlink=True)
    # Resolve all remaining source/baked paths before changing blend location.
    audit_images('before delivery save')
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath:im.filepath=str(Path(bpy.path.abspath(im.filepath)).resolve())
    blend=OUT/'i2_canal_revetment_delivery.blend';bpy.ops.wm.save_as_mainfile(filepath=str(blend),relative_remap=False)
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath:im.filepath=bpy.path.relpath(str(Path(bpy.path.abspath(im.filepath)).resolve()))
    bpy.ops.wm.save_as_mainfile(filepath=str(blend),relative_remap=False)
    bpy.ops.wm.open_mainfile(filepath=str(blend));images=audit_images('actual reopened delivery')
    select([bpy.data.objects[ROOT_NAME],bpy.data.objects[MESH_NAME]])
    bpy.ops.export_scene.gltf(filepath=str(candidate),export_format='GLB',use_selection=True,
        export_yup=True,export_apply=False,export_texcoords=True,export_normals=True,export_tangents=True,
        export_materials='EXPORT',export_extras=True,export_cameras=False,export_lights=False,export_animations=False)
    contract=json.loads((OUT/'prepared_contract.json').read_text(encoding='utf-8'))
    contract['parts'][0]['triangles']=report['triangles']
    contract['geometry_report']='crop_geometry_report.json'
    write_json(OUT/'actual_contract.json',contract)
    raw=verify_raw(candidate,expected,maps,contract);write_json(OUT/'raw_glb_report.json',raw)
    assert sha(SOURCE)==SOURCE_SHA
    write_json(OUT/'export_report.json',{'status':'EXPORTED_RAW_VERIFIED_PENDING_REIMPORT','pid':os.getpid(),
        'seconds':time.monotonic()-started,'source_sha256':SOURCE_SHA,'delivery_blend_sha256':sha(blend),
        'glb_sha256':raw['sha256'],'actual_reopened_images':images,'runtime_files_written':False})
    print(json.dumps({'stage':'export_exit','pid':os.getpid(),'seconds':time.monotonic()-started,'sha256':raw['sha256']}),flush=True)

if __name__=='__main__':main()
