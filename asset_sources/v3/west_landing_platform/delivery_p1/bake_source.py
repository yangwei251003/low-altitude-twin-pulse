"""Two shared PBR sets; exact source low triangles; matching high-only tread."""
from pathlib import Path
import sys,os,time,traceback
sys.dont_write_bytecode=True;sys.path.insert(0,str(Path(__file__).resolve().parent))
from common import *
import numpy as np

def proxy(kind,parts):
    dg=bpy.context.evaluated_depsgraph_get();verts=[];faces=[];normals=[];uvs={n:[] for n in UVS};owners=[];runtime=[];mat=None
    for ob in sorted(parts,key=lambda x:x.name):
        assert ob.matrix_world==Matrix.Identity(4)
        me=bpy.data.meshes.new_from_object(ob.evaluated_get(dg),preserve_all_data_layers=True,depsgraph=dg)
        me.calc_loop_triangles();base=len(verts);verts.extend(tuple(v.co) for v in me.vertices)
        if mat is None:mat=me.materials[0]
        assert len(me.materials)==1 and me.materials[0]==mat
        for t in me.loop_triangles:
            faces.append(tuple(base+v for v in t.vertices));owners.append(ob.name);runtime.append(NAMES.index(ob['runtime_mesh']))
            for li in t.loops:
                normals.append(tuple(me.corner_normals[li].vector))
                for n in UVS:uvs[n].append(tuple(me.uv_layers[n].data[li].uv))
        bpy.data.meshes.remove(me)
    m=bpy.data.meshes.new(kind+'_ExactLow');m.from_pydata(verts,[],faces);m.update();m.materials.append(mat)
    for p in m.polygons:p.use_smooth=True
    m.normals_split_custom_set(normals)
    for n,values in uvs.items():
        m.uv_layers.new(name=n)
        for q,value in zip(m.uv_layers[n].data,values):q.uv=value
    attr=m.attributes.new(name='RuntimeGroup',type='INT',domain='FACE')
    for q,value in zip(attr.data,runtime):q.value=value
    ob=bpy.data.objects.new(kind+'_BakeProxy',m);bpy.context.scene.collection.objects.link(ob)
    ob['source_faces']=json.dumps(owners);ob['bake_kind']=kind
    m.uv_layers.new(name='DeliveryUV');m.uv_layers.active_index=m.uv_layers.find('DeliveryUV')
    for u in m.uv_layers:u.active_render=u.name=='DeliveryUV'
    return ob,owners

def smart_faces(ob,indices,rect,margin=.012):
    select([ob]);bpy.context.tool_settings.mesh_select_mode=(False,False,True)
    bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='DESELECT');bpy.ops.object.mode_set(mode='OBJECT')
    selected=set(indices)
    for p in ob.data.polygons:p.select=p.index in selected
    bpy.ops.object.mode_set(mode='EDIT');bpy.ops.uv.smart_project(angle_limit=math.radians(66),island_margin=margin);bpy.ops.object.mode_set(mode='OBJECT')
    a,b,c,d=rect
    for index in indices:
        for li in ob.data.polygons[index].loop_indices:
            u,v=ob.data.uv_layers['DeliveryUV'].data[li].uv;ob.data.uv_layers['DeliveryUV'].data[li].uv=(a+u*(b-a),c+v*(d-c))

def unwrap(ob,owners,parts,size):
    me=ob.data;density={};primary=[]
    if ob['bake_kind']=='Steel':
        plates=sorted(o.name for o in parts if o.name.startswith('DeckPanel_'))
        assert len(plates)==8
        bounds={o.name:[[min(gp(v.co)[i] for v in o.data.vertices) for i in (0,2)],
                             [max(gp(v.co)[i] for v in o.data.vertices) for i in (0,2)]] for o in parts if o.name in plates}
        for p in me.polygons:
            if owners[p.index] in plates and p.normal.z>.75 and min(me.vertices[v].co.z for v in p.vertices)>4.99:primary.append(p.index)
        remaining=[i for i in range(len(me.polygons)) if i not in set(primary)]
        smart_faces(ob,remaining,(.676,.986,.676,.986),.025)
        for index in primary:
            name=owners[index];cell=plates.index(name);u0=.014+(cell%3)*.331;v0=.014+(cell//3)*.331
            (x0,z0),(x1,z1)=bounds[name]
            for li in me.polygons[index].loop_indices:
                p=gp(me.vertices[me.loops[li].vertex_index].co)
                me.uv_layers['DeliveryUV'].data[li].uv=(u0+.310*(p[0]-x0)/(x1-x0),v0+.310*(p[2]-z0)/(z1-z0))
            density[name]=[size*.310/(x1-x0),size*.310/(z1-z0)]
    else:smart_faces(ob,list(range(len(me.polygons))),(.012,.988,.012,.988),.008)
    me.calc_loop_triangles();areas=[]
    for t in me.loop_triangles:
        a,b,c=[me.uv_layers['DeliveryUV'].data[i].uv for i in t.loops]
        area=abs((b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x))/2
        assert area>0,(ob.name,t.index,'zero-area UV')
        areas.append(area)
    assert all(math.isfinite(v) and 0<=v<=1 for q in me.uv_layers['DeliveryUV'].data for v in q.uv)
    return {'name':ob.name,'size':size,'triangles':len(me.loop_triangles),'UV_area_sum':sum(areas),
            'min_UV_area':min(areas),'top_faces':len(primary),'top_pixels_per_metre':density,
            'atlas_semantics':'Eight large top cells + secondary cell' if density else 'Shared paint UV across both bodies'}

def bake_channel(kind,size,channel,pairs):
    im=bpy.data.images.new(kind+'_'+channel,width=size,height=size,alpha=False)
    im.colorspace_settings.name='sRGB' if channel=='BaseColor' else 'Non-Color'
    im.generated_color=(.5,.5,1,1) if channel=='Normal' else (1,1,1,1)
    scene=bpy.context.scene;scene.render.bake.normal_space='TANGENT';scene.render.bake.normal_r='POS_X';scene.render.bake.normal_g='POS_Y';scene.render.bake.normal_b='POS_Z'
    for step,(low,high) in enumerate(pairs):
        restore=[];nodes=[]
        for mat in set(m for obj in high or [low] for m in obj.data.materials if m):
            n,l=mat.node_tree.nodes,mat.node_tree.links;bs=shader(mat);out=next(n for n in n if n.type=='OUTPUT_MATERIAL' and n.is_active_output)
            old=out.inputs['Surface'].links[0].from_socket;temporary=[]
            if channel!='Normal':
                em=n.new('ShaderNodeEmission');temporary.append(em);em.inputs['Strength'].default_value=1
                if channel=='BaseColor':
                    s=bs.inputs['Base Color']
                    if s.is_linked:l.new(s.links[0].from_socket,em.inputs['Color'])
                    else:em.inputs['Color'].default_value=s.default_value
                else:
                    mix=n.new('ShaderNodeCombineColor');mix.mode='RGB';mix.inputs['Red'].default_value=1;temporary.append(mix)
                    for target,key in [('Green','Roughness'),('Blue','Metallic')]:
                        s=bs.inputs[key]
                        if s.is_linked:l.new(s.links[0].from_socket,mix.inputs[target])
                        else:mix.inputs[target].default_value=s.default_value
                    l.new(mix.outputs[0],em.inputs['Color'])
                l.new(em.outputs[0],out.inputs['Surface'])
            restore.append((mat,out,old,temporary))
        for mat in low.data.materials:
            n=mat.node_tree.nodes;t=n.new('ShaderNodeTexImage');t.image=im
            for node in n:node.select=False
            t.select=True;n.active=t;nodes.append((mat,t))
        low.hide_render=False
        for obj in high:obj.hide_render=False
        select(high+[low],low)
        print('BAKE_BEGIN '+kind+' '+channel+' '+low.name,flush=True)
        bpy.ops.object.bake(type='NORMAL' if channel=='Normal' else 'EMIT',use_clear=step==0,margin=8,
                            use_selected_to_active=bool(high),cage_extrusion=.006,max_ray_distance=.015)
        for mat,node in nodes:mat.node_tree.nodes.remove(node)
        for mat,out,old,temporary in restore:
            mat.node_tree.links.new(old,out.inputs['Surface'])
            for node in temporary:mat.node_tree.nodes.remove(node)
        low.hide_render=True
        for obj in high:obj.hide_render=True
    folder=HERE/'textures';folder.mkdir(exist_ok=True);dest=folder/(kind+'_'+channel+'.png')
    im.filepath_raw=str(dest);im.file_format='PNG';im.save()
    check=bpy.data.images.load(str(dest),check_existing=False);check.colorspace_settings.name=im.colorspace_settings.name
    px=np.asarray(check.pixels[:],dtype=np.float32).reshape(-1,4);assert check.has_data and np.isfinite(px).all() and list(check.size)==[size,size]
    return {'group':kind,'channel':channel,'path':str(dest),'sha256':sha(dest),'size':[size,size],'colorspace':im.colorspace_settings.name,
            'RGB_min':px[:,:3].min(axis=0).tolist(),'RGB_max':px[:,:3].max(axis=0).tolist(),'RGB_std':px[:,:3].std(axis=0).tolist()}

def main():
    began=time.monotonic();print(json.dumps({'stage':'bake','pid':os.getpid(),'CPU_threads':2}),flush=True)
    assert sha(SOURCE)==SOURCE_SHA and not (HERE/'bake_complete.blend').exists()
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE));bpy.context.preferences.filepaths.save_version=0
    images=image_audit(copy=True);editable=HERE/'west_landing_platform_editable.blend';save_relative(editable)
    parts=[o for o in bpy.data.objects if o.get('editable_piece')];assert len(parts)==106
    proxies={};owners={};uv_reports=[];runtime={k:0 for k in NAMES}
    for kind,size in [('Steel',2048),('Paint',1024)]:
        group=[o for o in parts if o.data.materials[0].name=='WestLanding_'+kind]
        ob,names=proxy(kind,group);proxies[kind]=ob;owners[kind]=names;uv_reports.append(unwrap(ob,names,group,size))
        for q in ob.data.attributes['RuntimeGroup'].data:runtime[NAMES[q.value]]+=1
    assert runtime==COUNTS,runtime
    normal_pairs=[];steel=proxies['Steel'];steel_owners=owners['Steel'];plates=sorted(set(n for n in steel_owners if n.startswith('DeckPanel_')))
    for name in plates:
        ids=[i for i,n in enumerate(steel_owners) if n==name]
        target=subset(steel,ids,name+'_NormalTarget')
        normal_pairs.append((target,[bpy.data.objects[name],bpy.data.objects[name+'_TreadHigh']]))
    other=[i for i,n in enumerate(steel_owners) if n not in plates]
    normal_pairs.append((subset(steel,other,'SteelHardware_NormalTarget'),[]))
    for ob in bpy.data.objects:
        if ob.type=='MESH':ob.hide_render=True
    scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=4
    scene.render.threads_mode='FIXED';scene.render.threads=2
    report={'status':'PREPARED','source_sha256':SOURCE_SHA,'editable_sha256':sha(editable),'runtime_mesh_triangles':runtime,
            'UV':uv_reports,'source_images':images,'textures':[],'AO':'ORM R=1. No new AO or baked lighting.',
            'normal':'Eight isolated matching plate+ribs high pairs; hardware/paint self bake. Fine source normal strength .25 once, baked export strength 1.',
            'cage_m':.006,'max_ray_distance_m':.015}
    write('bake_report.json',report);save_relative(HERE/'UV_checkpoint.blend')
    for kind,size in [('Steel',2048),('Paint',1024)]:
        for channel in ('BaseColor','ORM','Normal'):
            pairs=normal_pairs if kind=='Steel' and channel=='Normal' else [(proxies[kind],[])]
            report['textures'].append(bake_channel(kind,size,channel,pairs));report['status']='BAKED_'+kind+'_'+channel
            write('bake_report.json',report);save_relative(HERE/'bake_checkpoint.blend')
    final=HERE/'bake_complete.blend';save_relative(final);bpy.ops.wm.open_mainfile(filepath=str(final));report['reopened_images']=image_audit()
    assert sha(SOURCE)==SOURCE_SHA and sha(editable)==report['editable_sha256']
    report.update(status='BAKE_COMPLETE',pid=os.getpid(),seconds=time.monotonic()-began,blend_sha256=sha(final));write('bake_report.json',report)
    print(json.dumps({'stage':'bake_end','pid':os.getpid(),'seconds':report['seconds'],'textures':len(report['textures'])}),flush=True)

if __name__=='__main__':
    try:main()
    except Exception:
        write('bake_failure.json',{'traceback':traceback.format_exc(),'pid':os.getpid()})
        raise
