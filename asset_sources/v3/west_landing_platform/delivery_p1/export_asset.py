from pathlib import Path
import sys,os,time,shutil
sys.dont_write_bytecode=True;sys.path.insert(0,str(Path(__file__).resolve().parent))
from common import *
from verify_glb import verify,compare

def material(kind,textures):
    m=bpy.data.materials.new('WestLanding_'+kind+'_BakedPBR');m.use_nodes=True;m.use_backface_culling=True
    n,l=m.node_tree.nodes,m.node_tree.links;n.clear();bs=n.new('ShaderNodeBsdfPrincipled');out=n.new('ShaderNodeOutputMaterial')
    l.new(bs.outputs[0],out.inputs[0]);uv=n.new('ShaderNodeUVMap');uv.uv_map='SurfaceUV';tex={}
    for key in ('BaseColor','ORM','Normal'):
        row=next(r for r in textures if r['group']==kind and r['channel']==key);assert sha(row['path'])==row['sha256']
        im=bpy.data.images.load(row['path'],check_existing=False);im.colorspace_settings.name=row['colorspace']
        t=n.new('ShaderNodeTexImage');t.image=im;l.new(uv.outputs[0],t.inputs['Vector']);tex[key]=t
    l.new(tex['BaseColor'].outputs['Color'],bs.inputs['Base Color'])
    split=n.new('ShaderNodeSeparateColor');l.new(tex['ORM'].outputs['Color'],split.inputs[0])
    l.new(split.outputs['Green'],bs.inputs['Roughness']);l.new(split.outputs['Blue'],bs.inputs['Metallic'])
    nm=n.new('ShaderNodeNormalMap');nm.space='TANGENT';nm.uv_map='SurfaceUV';nm.inputs['Strength'].default_value=1
    l.new(tex['Normal'].outputs['Color'],nm.inputs['Color']);l.new(nm.outputs[0],bs.inputs['Normal'])
    bs.inputs['Alpha'].default_value=1;bs.inputs['Emission Strength'].default_value=0
    return m

def new_empty(name,parent=None):
    ob=bpy.data.objects.new(name,None);bpy.context.scene.collection.objects.link(ob);ob.parent=parent;ob.matrix_basis=Matrix.Identity(4);return ob

def main():
    start=time.monotonic();print(json.dumps({'stage':'export','pid':os.getpid(),'CPU_threads':2}),flush=True)
    report=json.loads((HERE/'bake_report.json').read_text(encoding='utf-8'));assert report['status']=='BAKE_COMPLETE'
    assert sha(SOURCE)==SOURCE_SHA and sha(HERE/'bake_complete.blend')==report['blend_sha256']
    bpy.ops.wm.open_mainfile(filepath=str(HERE/'bake_complete.blend'));image_audit()
    # Keep exact proxies; remove old empty roots before assigning the public hierarchy.
    proxies={kind:bpy.data.objects[kind+'_BakeProxy'] for kind in ('Steel','Paint')}
    for ob in list(bpy.data.objects):
        if ob not in proxies.values():bpy.data.objects.remove(ob,do_unlink=True)
    root=new_empty('WestLandingPlatform');parents={g:new_empty(g,root) for g in BOUNDS}
    mats={kind:material(kind,report['textures']) for kind in ('Steel','Paint')};objects=[];expected={}
    for name in NAMES:
        kind='Steel' if name.endswith('Steel') else 'Paint';src=proxies[kind]
        ids=[i for i,q in enumerate(src.data.attributes['RuntimeGroup'].data) if q.value==NAMES.index(name)]
        assert len(ids)==COUNTS[name],(name,len(ids))
        ob=subset(src,ids,name,mats[kind]);ob.parent=parents['PlatformAssembly' if name.startswith('Platform') else 'LegAssembly']
        assert ob.matrix_world==Matrix.Identity(4)
        for layer in list(ob.data.uv_layers):
            if layer.name!='DeliveryUV':ob.data.uv_layers.remove(layer)
        ob.data.uv_layers[0].name='SurfaceUV';ob.data.uv_layers.active_index=0;ob.data.uv_layers[0].active_render=True
        ob.hide_render=False;objects.append(ob);expected[name]=source_rows(ob,'SurfaceUV')
    for ob in proxies.values():bpy.data.objects.remove(ob,do_unlink=True)
    write('expected_runtime_triangles.json',expected)
    delivery=HERE/'west_landing_platform_delivery.blend';save_relative(delivery);delivery_sha=sha(delivery)
    bpy.ops.wm.open_mainfile(filepath=str(delivery));images=image_audit()
    select([bpy.data.objects[n] for n in NAMES+('WestLandingPlatform','PlatformAssembly','LegAssembly')])
    glb=HERE/'west_landing_platform.glb';assert not glb.exists()
    bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,export_yup=True,export_apply=False,
         export_texcoords=True,export_normals=True,export_tangents=True,export_materials='EXPORT',export_cameras=False,export_lights=False,export_animations=False)
    raw=verify(glb,expected,report['textures']);write('raw_glb_report.json',raw);digest=sha(glb)
    bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(glb))
    actual={o.name:source_rows(o,o.data.uv_layers[0].name) for o in bpy.data.objects if o.type=='MESH'}
    assert set(actual)==set(NAMES);errors=compare(expected,actual,reimport=True)
    for name in NAMES:
        ob=bpy.data.objects[name];assert ob.matrix_local==Matrix.Identity(4)
        assert ob.parent.name==('PlatformAssembly' if name.startswith('Platform') else 'LegAssembly')
    assert sha(SOURCE)==SOURCE_SHA and sha(glb)==digest and sha(delivery)==delivery_sha
    candidate=ROOT/'assets/v3/candidates/west_landing_platform/west_landing_platform.glb'
    candidate.parent.mkdir(parents=True,exist_ok=True);assert not candidate.exists();shutil.copyfile(glb,candidate);assert sha(candidate)==digest
    result={'status':'EXPLICIT_GLB_AND_SAME_BYTE_NUMERIC_READBACK_PASS_NOT_GAME_VERIFIED','pid':os.getpid(),
            'seconds':time.monotonic()-start,'glb':str(glb),'candidate':str(candidate),'sha256':digest,'bytes':glb.stat().st_size,
            'root':'WestLandingPlatform','origin_world':[-6,0,-4],'identity_hierarchy':True,'mesh_triangles':COUNTS,
            'materials':2,'embedded_maps':6,'textures_shared_across_bodies':True,'bounds_per_body':BOUNDS,
            'same_byte_reimport':errors,'source_unchanged':True,'source_sha256':SOURCE_SHA,
            'delivery_blend_sha256':delivery_sha,'reopened_images':images,'no_collision_lights_cameras':True}
    write('export_report.json',result);print(json.dumps(result,ensure_ascii=False),flush=True)

if __name__=='__main__':main()
