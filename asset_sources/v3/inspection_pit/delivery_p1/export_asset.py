import os,sys,time
from pathlib import Path
sys.dont_write_bytecode=True;sys.path.insert(0,str(Path(__file__).resolve().parent))
from common import *
from verify_export import verify_raw

def material(name,maps):
    mat=bpy.data.materials.new('InspectionPit_'+name+'_PBR');mat.use_nodes=True;mat.use_backface_culling=True
    n,l=mat.node_tree.nodes,mat.node_tree.links;n.clear()
    bs=n.new('ShaderNodeBsdfPrincipled');out=n.new('ShaderNodeOutputMaterial');l.new(bs.outputs[0],out.inputs[0])
    uv=n.new('ShaderNodeUVMap');uv.uv_map='SurfaceUV';textures={}
    for channel in ('BaseColor','ORM','Normal'):
        im=bpy.data.images.load(maps[channel],check_existing=False)
        im.colorspace_settings.name='sRGB' if channel=='BaseColor' else 'Non-Color'
        tex=n.new('ShaderNodeTexImage');tex.image=im;l.new(uv.outputs[0],tex.inputs['Vector']);textures[channel]=tex
    l.new(textures['BaseColor'].outputs['Color'],bs.inputs['Base Color'])
    sep=n.new('ShaderNodeSeparateColor');sep.mode='RGB';l.new(textures['ORM'].outputs[0],sep.inputs[0])
    l.new(sep.outputs['Green'],bs.inputs['Roughness']);l.new(sep.outputs['Blue'],bs.inputs['Metallic'])
    normal=n.new('ShaderNodeNormalMap');normal.space='TANGENT';normal.uv_map='SurfaceUV';normal.inputs['Strength'].default_value=1
    l.new(textures['Normal'].outputs['Color'],normal.inputs['Color']);l.new(normal.outputs[0],bs.inputs['Normal'])
    bs.inputs['Alpha'].default_value=1;bs.inputs['Emission Strength'].default_value=0
    mat['contract']='Opaque glTF PBR, tangent +Y normal. ORM R=1, no AO claim.'
    return mat

def main():
    start=time.monotonic();source_check()
    report=json.loads((OUT/'bake_report.json').read_text(encoding='utf-8'))
    prep=json.loads((OUT/'prepare_report.json').read_text(encoding='utf-8'))
    assert report['status']=='BAKE_COMPLETE_PENDING_EXPORT' and sha(OUT/'bake_complete.blend')==report['blend_sha256']
    assert sha(OUT/'inspection_pit_editable.blend')==prep['editable_sha256']
    assert all(sha(r['path'])==r['sha256'] for r in report['textures'])
    candidate=OUT/'inspection_pit.glb';assert not candidate.exists()
    bpy.ops.wm.open_mainfile(filepath=str(OUT/'bake_complete.blend'));image_audit()
    root=bpy.data.objects.new(ROOT_NAME,None);bpy.context.scene.collection.objects.link(root)
    objects=[];expected={}
    for group in GROUPS:
        source=bpy.data.objects[group+'_BakeProxy'].data;source.calc_loop_triangles()
        vertices=[tuple(v.co) for v in source.vertices];faces=[];normals=[];uv=[]
        for tri in source.loop_triangles:
            faces.append(tuple(tri.vertices))
            for li in tri.loops:
                normals.append(tuple(source.corner_normals[li].vector));uv.append(tuple(source.uv_layers['DeliveryUV'].data[li].uv))
        mesh=bpy.data.meshes.new(group);mesh.from_pydata(vertices,[],faces);mesh.update()
        for p in mesh.polygons:p.use_smooth=True
        mesh.normals_split_custom_set(normals);mesh.uv_layers.new(name='SurfaceUV')
        for loop,p in zip(mesh.uv_layers['SurfaceUV'].data,uv):loop.uv=p
        mesh.uv_layers.active_index=0;mesh.uv_layers['SurfaceUV'].active_render=True
        maps={r['channel']:r['path'] for r in report['textures'] if r['set']==group}
        mesh.materials.append(material(group,maps));ob=bpy.data.objects.new(group,mesh)
        bpy.context.scene.collection.objects.link(ob);ob.parent=root;objects.append(ob)
        assert ob.matrix_world==Matrix.Identity(4)
        expected[group]=triangle_rows(mesh,'SurfaceUV')
    assert sum(len(v) for v in expected.values())==CONTRACT['expected_triangles']
    assert root.matrix_world==Matrix.Identity(4)
    write('expected_runtime_triangles.json',expected)
    for ob in list(bpy.data.objects):
        if ob not in objects and ob!=root and ob.type=='MESH' and ob.name!='Studio_NOT_ASSET':bpy.data.objects.remove(ob,do_unlink=True)
    image_audit();blend=OUT/'inspection_pit_delivery.blend'
    # Remove unused source image datablocks so the delivery dependency inventory
    # contains only the nine maps actually referenced by the exported materials.
    used={node.image for ob in objects for mat in ob.data.materials for node in mat.node_tree.nodes if node.type=='TEX_IMAGE' and node.image}
    for im in list(bpy.data.images):
        if im.source=='FILE' and im not in used and im.users==0:bpy.data.images.remove(im)
    bpy.ops.wm.save_as_mainfile(filepath=str(blend),relative_remap=False)
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath:im.filepath=bpy.path.relpath(str(Path(bpy.path.abspath(im.filepath)).resolve()))
    bpy.ops.wm.save_as_mainfile(filepath=str(blend),relative_remap=False)
    bpy.ops.wm.open_mainfile(filepath=str(blend));images=image_audit()
    select([bpy.data.objects[ROOT_NAME]]+[bpy.data.objects[name] for name in GROUPS])
    bpy.ops.export_scene.gltf(filepath=str(candidate),export_format='GLB',use_selection=True,
        export_yup=True,export_apply=False,export_texcoords=True,export_normals=True,export_tangents=True,
        export_materials='EXPORT',export_extras=True,export_cameras=False,export_lights=False,export_animations=False)
    raw=verify_raw(candidate,expected,report['textures']);write('raw_glb_report.json',raw)
    source_check();write('export_report.json',{'status':'RAW_VERIFIED_PENDING_REIMPORT',
        'pid':os.getpid(),'seconds':time.monotonic()-start,'glb_sha256':raw['sha256'],'bytes':raw['bytes'],
        'delivery_blend_sha256':sha(blend),'images':images,'source_geometry_triangles':CONTRACT['expected_triangles'],
        'world_anchor':CONTRACT['world_anchor'],'runtime_written':False})

if __name__=='__main__':main()
