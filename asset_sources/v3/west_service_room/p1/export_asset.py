from pathlib import Path
import sys,os,time
sys.dont_write_bytecode=True;sys.path.insert(0,str(Path(__file__).resolve().parent))
from common import *
from verify_glb import verify,compare,NAMES
def material(name,textures):
    m=bpy.data.materials.new('WestService_'+name+'_BakedPBR');m.use_nodes=True;m.use_backface_culling=True;n,l=m.node_tree.nodes,m.node_tree.links;n.clear();bs=n.new('ShaderNodeBsdfPrincipled');out=n.new('ShaderNodeOutputMaterial');l.new(bs.outputs[0],out.inputs[0]);uv=n.new('ShaderNodeUVMap');uv.uv_map='SurfaceUV';tex={}
    for key in ('BaseColor','ORM','Normal'):
        row=next(r for r in textures if r['group']==name and r['channel']==key);assert sha(row['path'])==row['sha256'];im=bpy.data.images.load(row['path'],check_existing=False);im.colorspace_settings.name=row['colorspace'];t=n.new('ShaderNodeTexImage');t.image=im;l.new(uv.outputs[0],t.inputs['Vector']);tex[key]=t
    l.new(tex['BaseColor'].outputs['Color'],bs.inputs['Base Color']);split=n.new('ShaderNodeSeparateColor');l.new(tex['ORM'].outputs['Color'],split.inputs[0]);l.new(split.outputs['Green'],bs.inputs['Roughness']);l.new(split.outputs['Blue'],bs.inputs['Metallic'])
    nm=n.new('ShaderNodeNormalMap');nm.space='TANGENT';nm.uv_map='SurfaceUV';nm.inputs['Strength'].default_value=1;l.new(tex['Normal'].outputs['Color'],nm.inputs['Color']);l.new(nm.outputs[0],bs.inputs['Normal']);bs.inputs['Alpha'].default_value=1;bs.inputs['Emission Strength'].default_value=0
    return m
def triangles(o):
    me=o.data;me.calc_loop_triangles();return [[{'p':gp(o.matrix_world@me.vertices[vi].co),'n':gp(me.corner_normals[li].vector),'uv':list(me.uv_layers[0].data[li].uv)} for vi,li in zip(t.vertices,t.loops)] for t in me.loop_triangles]
def main():
    started=time.monotonic();print(json.dumps({'stage':'export','pid':os.getpid(),'threads':2}),flush=True)
    report=json.loads((HERE/'bake_report.json').read_text(encoding='utf-8'));assert report['status']=='BAKE_COMPLETE';source=HERE/'west_service_room_editable.blend';assert sha(source)==report['source_sha256'];assert sha(HERE/'bake_complete.blend')==report['blend_sha256']
    bpy.ops.wm.open_mainfile(filepath=str(HERE/'bake_complete.blend'));image_audit();root=bpy.data.objects.new('WestServiceRoom',None);bpy.context.scene.collection.objects.link(root);objects=[];expected={}
    for name in NAMES:
        src=bpy.data.objects[name+'_BakeProxy'].data;src.calc_loop_triangles();vertices=[tuple(v.co) for v in src.vertices];faces=[];normals=[];uv=[]
        for t in src.loop_triangles:
            faces.append(tuple(t.vertices))
            for li in t.loops:normals.append(tuple(src.corner_normals[li].vector));uv.append(tuple(src.uv_layers['DeliveryUV'].data[li].uv))
        mesh=bpy.data.meshes.new(name);mesh.from_pydata(vertices,[],faces);mesh.update()
        for p in mesh.polygons:p.use_smooth=True
        mesh.normals_split_custom_set(normals);mesh.uv_layers.new(name='SurfaceUV')
        for loop,v in zip(mesh.uv_layers[0].data,uv):loop.uv=v
        mesh.uv_layers[0].active_render=True;mesh.materials.append(material(name,report['textures']));ob=bpy.data.objects.new(name,mesh);bpy.context.scene.collection.objects.link(ob);ob.parent=root;assert ob.matrix_world==Matrix.Identity(4);objects.append(ob);expected[name]=triangles(ob)
    for ob in list(bpy.data.objects):
        if ob not in objects and ob!=root:bpy.data.objects.remove(ob,do_unlink=True)
    write('expected_runtime_triangles.json',expected);delivery=HERE/'west_service_room_delivery.blend';save_relative(delivery);bpy.ops.wm.open_mainfile(filepath=str(delivery));images=image_audit()
    select([bpy.data.objects['WestServiceRoom']]+[bpy.data.objects[n] for n in NAMES]);glb=HERE/'west_service_room.glb';assert not glb.exists()
    bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,export_yup=True,export_apply=False,export_texcoords=True,export_normals=True,export_tangents=True,export_materials='EXPORT',export_cameras=False,export_lights=False,export_animations=False)
    raw=verify(glb,expected,report['textures']);write('raw_glb_report.json',raw);digest=sha(glb)
    bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(glb));actual={o.name:triangles(o) for o in bpy.data.objects if o.type=='MESH'};assert set(actual)==set(NAMES);reimport=compare(expected,actual,reimport=True);assert sha(glb)==digest
    assert sha(source)==report['source_sha256'];write('export_report.json',{'status':'EXPORT_AND_SAME_BYTE_NUMERIC_REIMPORT_PASS_NOT_GAME_VERIFIED','pid':os.getpid(),'seconds':time.monotonic()-started,'glb':str(glb),'sha256':digest,'bytes':glb.stat().st_size,'raw_report':'raw_glb_report.json','source_unchanged':True,'source_sha256':sha(source),'delivery_blend_sha256':sha(delivery),'reopened_images':images,'reimport_errors':reimport,'reimport_triangles':{k:len(v) for k,v in actual.items()},'origin_world':[-14,0,-8],'no_collision_lights_cameras':True})
    print(json.dumps({'stage':'export_end','pid':os.getpid(),'seconds':time.monotonic()-started,'glb_sha256':digest,'bytes':glb.stat().st_size}),flush=True)
if __name__=='__main__':main()
