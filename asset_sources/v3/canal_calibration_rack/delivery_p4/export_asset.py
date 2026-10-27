import os,time,sys
from pathlib import Path
sys.dont_write_bytecode=True;sys.path.insert(0,str(Path(__file__).resolve().parent))
from common import *
from verify_export import verify_raw

def material(label,maps):
    mat=bpy.data.materials.new('CalibrationRack_'+label+'_PBR');mat.use_nodes=True;mat.use_backface_culling=True
    n,l=mat.node_tree.nodes,mat.node_tree.links;n.clear();bs=n.new('ShaderNodeBsdfPrincipled');out=n.new('ShaderNodeOutputMaterial');l.new(bs.outputs[0],out.inputs[0])
    uv=n.new('ShaderNodeUVMap');uv.uv_map='SurfaceUV';textures={}
    for key in ('BaseColor','ORM','Normal'):
        im=bpy.data.images.load(maps[key],check_existing=False);im.colorspace_settings.name='sRGB' if key=='BaseColor' else 'Non-Color'
        tex=n.new('ShaderNodeTexImage');tex.image=im;tex.name='Baked_'+key;l.new(uv.outputs[0],tex.inputs['Vector']);textures[key]=tex
    l.new(textures['BaseColor'].outputs['Color'],bs.inputs['Base Color'])
    split=n.new('ShaderNodeSeparateColor');split.mode='RGB';l.new(textures['ORM'].outputs['Color'],split.inputs[0]);l.new(split.outputs['Green'],bs.inputs['Roughness']);l.new(split.outputs['Blue'],bs.inputs['Metallic'])
    normal=n.new('ShaderNodeNormalMap');normal.space='TANGENT';normal.uv_map='SurfaceUV';normal.inputs['Strength'].default_value=1
    l.new(textures['Normal'].outputs['Color'],normal.inputs['Color']);l.new(normal.outputs[0],bs.inputs['Normal'])
    bs.inputs['Alpha'].default_value=1;bs.inputs['Emission Strength'].default_value=0
    mat['contract']='Standard glTF metallic/roughness, tangent +Y normal; AO channel neutral 1. No source procedural nodes.'
    return mat

def main():
    start=time.monotonic();assert sha(SOURCE)==SOURCE_SHA;report=json.loads((OUT/'bake_report.json').read_text(encoding='utf-8'))
    assert report['status']=='BAKE_COMPLETE_PENDING_EXPORT' and sha(OUT/'bake_complete.blend')==report['blend_sha256']
    candidate=OUT/'calibration_rack.glb';assert not candidate.exists()
    # A clean, reopenable editable-source copy precedes runtime assembly. It
    # preserves the P4 visible high / hidden low state, not the bake checkpoint's
    # temporarily hidden projection objects. Only image dependency paths change.
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE));source_images=audit_images(copy=True)
    editable=OUT/'calibration_rack_editable.blend'
    bpy.ops.wm.save_as_mainfile(filepath=str(editable),relative_remap=False)
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath:im.filepath=bpy.path.relpath(str(Path(bpy.path.abspath(im.filepath)).resolve()))
    bpy.ops.wm.save_as_mainfile(filepath=str(editable),relative_remap=False)
    bpy.ops.wm.open_mainfile(filepath=str(editable));editable_images=audit_images()
    assert [(r['sha256'],r['space'],r['size']) for r in source_images]==[(r['sha256'],r['space'],r['size']) for r in editable_images]
    original_pieces=[o for o in bpy.data.objects if o.get('editable_piece')]
    for o in original_pieces:o.data.calc_loop_triangles()
    assert len(original_pieces)==51 and sum(len(o.data.loop_triangles) for o in original_pieces)==4740
    write('editable_source_report.json',{'source_p4_sha256':SOURCE_SHA,'copy_sha256':sha(editable),'low_pieces':51,'low_triangles':4740,
          'only_dependency_paths_changed':True,'actual_reopened_images':editable_images,'relative_dependency_root':'source_inputs/'})
    bpy.ops.wm.open_mainfile(filepath=str(OUT/'bake_complete.blend'))
    maps={kind:{r['channel']:r['path'] for r in report['textures'] if r['set']==kind} for kind in ('Deck','Structure')}
    assert all(sha(r['path'])==r['sha256'] for r in report['textures'])
    expected={};objects=[];root=bpy.data.objects.new(ROOT_NAME,None);bpy.context.scene.collection.objects.link(root)
    for name,proxy_name,label in [('DeckSurface','DeckBakeProxy','Deck'),('StructureAndHardware','StructureBakeProxy','Structure')]:
        source=bpy.data.objects[proxy_name].data;source.calc_loop_triangles();verts=[tuple(v.co) for v in source.vertices]
        faces=[];normals=[];uvs=[]
        for tri in source.loop_triangles:
            faces.append(tuple(tri.vertices))
            for li in tri.loops:normals.append(tuple(source.corner_normals[li].vector));uvs.append(tuple(source.uv_layers['DeliveryUV'].data[li].uv))
        assert len(faces)==PARTS[name]
        mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update()
        for p in mesh.polygons:p.use_smooth=True
        mesh.normals_split_custom_set(normals);mesh.uv_layers.new(name='SurfaceUV')
        for li,uv in zip(mesh.uv_layers[0].data,uvs):li.uv=uv
        mesh.uv_layers.active_index=0;mesh.uv_layers[0].active_render=True;mesh.materials.append(material(label,maps[label]))
        obj=bpy.data.objects.new(name,mesh);bpy.context.scene.collection.objects.link(obj);obj.parent=root
        assert obj.matrix_world==Matrix.Identity(4);obj.hide_render=False;objects.append(obj)
        mesh.calc_loop_triangles();expected[name]=[[{'p':gp(mesh.vertices[v].co),'n':gp(mesh.corner_normals[l].vector),'uv':list(mesh.uv_layers[0].data[l].uv)} for v,l in zip(t.vertices,t.loops)] for t in mesh.loop_triangles]
    assert root.matrix_world==Matrix.Identity(4)
    write('expected_runtime_triangles.json',expected)
    for o in list(bpy.data.objects):
        if o not in objects and o!=root and o.type=='MESH' and o.name!='ReviewGround_NOT_ASSET':bpy.data.objects.remove(o,do_unlink=True)
    # Runtime scene is deliberately separate from the 51-piece editable source.
    audit_images();blend=OUT/'calibration_rack_delivery.blend';bpy.ops.wm.save_as_mainfile(filepath=str(blend),relative_remap=False)
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath:im.filepath=bpy.path.relpath(str(Path(bpy.path.abspath(im.filepath)).resolve()))
    bpy.ops.wm.save_as_mainfile(filepath=str(blend),relative_remap=False);bpy.ops.wm.open_mainfile(filepath=str(blend));images=audit_images()
    select([bpy.data.objects[ROOT_NAME]]+[bpy.data.objects[n] for n in PARTS])
    bpy.ops.export_scene.gltf(filepath=str(candidate),export_format='GLB',use_selection=True,export_yup=True,
        export_apply=False,export_texcoords=True,export_normals=True,export_tangents=True,export_materials='EXPORT',
        export_extras=True,export_cameras=False,export_lights=False,export_animations=False)
    raw=verify_raw(candidate,expected,report['textures']);write('raw_glb_report.json',raw)
    assert sha(SOURCE)==SOURCE_SHA
    write('export_report.json',{'status':'RAW_VERIFIED_PENDING_REIMPORT','pid':os.getpid(),'seconds':time.monotonic()-start,
                              'glb_sha256':raw['sha256'],'bytes':raw['bytes'],'delivery_blend_sha256':sha(blend),'images':images,
                              'source_geometry_triangles':4740,'runtime_written':False})

if __name__=='__main__':main()
