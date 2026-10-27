"""Three 1K source-derived PBR sets. Source UV and corner normals retained exactly."""
from pathlib import Path
import sys,os,time
sys.dont_write_bytecode=True;sys.path.insert(0,str(Path(__file__).resolve().parent))
from common import *
import numpy as np
GROUPS={'PaintedShell':'Paint','ConcreteBase':'Concrete','RoofMetal':'Steel'}
def proxy(name,parts):
    verts=[];faces=[];normals=[];uvs={k:[] for k in UVS};dg=bpy.context.evaluated_depsgraph_get();rows=[]
    material=None
    for o in sorted(parts,key=lambda o:o.name):
        me=bpy.data.meshes.new_from_object(o.evaluated_get(dg),preserve_all_data_layers=True,depsgraph=dg);me.calc_loop_triangles();base=len(verts);verts.extend(tuple(v.co) for v in me.vertices)
        if material is None:material=me.materials[0]
        assert len(me.materials)==1 and me.materials[0]==material
        for t in me.loop_triangles:
            faces.append(tuple(base+i for i in t.vertices))
            for li in t.loops:
                normals.append(tuple(me.corner_normals[li].vector))
                for k in UVS:uvs[k].append(tuple(me.uv_layers[k].data[li].uv))
        rows.append({'source':o.name,'triangles':len(me.loop_triangles)});bpy.data.meshes.remove(me)
    me=bpy.data.meshes.new(name+'_ExactSourceTriangles');me.from_pydata(verts,[],faces);me.update();me.materials.append(material)
    for p in me.polygons:p.use_smooth=True
    me.normals_split_custom_set(normals)
    for nameUV,values in uvs.items():
        me.uv_layers.new(name=nameUV)
        for l,v in zip(me.uv_layers[nameUV].data,values):l.uv=v
    ob=bpy.data.objects.new(name+'_BakeProxy',me);bpy.context.scene.collection.objects.link(ob)
    me.uv_layers.new(name='DeliveryUV');me.uv_layers.active_index=me.uv_layers.find('DeliveryUV')
    for layer in me.uv_layers:layer.active_render=layer.name=='DeliveryUV'
    select([ob]);bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.uv.smart_project(angle_limit=math.radians(66),island_margin=.008);bpy.ops.object.mode_set(mode='OBJECT')
    me.calc_loop_triangles();bad=[];areas=[]
    for t in me.loop_triangles:
        a,b,c=[me.uv_layers['DeliveryUV'].data[i].uv for i in t.loops];area=abs((b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x))/2
        if area<=1e-14:bad.append(t.index)
        areas.append(area)
    assert not bad,(name,bad)
    return ob,{'name':name,'source_parts':rows,'triangles':len(faces),'size':1024,'UV_area_sum':sum(areas),'min_triangle_UV_area':min(areas),'zero_UV_triangles':bad,'island_margin':.008}
def bake_one(ob,group,channel):
    m=ob.data.materials[0];n,l=m.node_tree.nodes,m.node_tree.links;bs=n['Principled'];out=next(n for n in n if n.type=='OUTPUT_MATERIAL');old=out.inputs[0].links[0].from_socket;temp=[]
    im=bpy.data.images.new(group+'_'+channel,width=1024,height=1024,alpha=False);im.colorspace_settings.name='sRGB' if channel=='BaseColor' else 'Non-Color'
    if channel!='Normal':
        emit=n.new('ShaderNodeEmission');emit.inputs['Strength'].default_value=1;temp.append(emit)
        if channel=='BaseColor':
            s=bs.inputs['Base Color'];l.new(s.links[0].from_socket,emit.inputs['Color']) if s.is_linked else setattr(emit.inputs['Color'],'default_value',s.default_value)
        else:
            combine=n.new('ShaderNodeCombineColor');combine.mode='RGB';combine.inputs['Red'].default_value=1;temp.append(combine)
            for ch,key in [('Green','Roughness'),('Blue','Metallic')]:
                s=bs.inputs[key];l.new(s.links[0].from_socket,combine.inputs[ch]) if s.is_linked else setattr(combine.inputs[ch],'default_value',s.default_value)
            l.new(combine.outputs[0],emit.inputs['Color'])
        l.new(emit.outputs[0],out.inputs[0])
    target=n.new('ShaderNodeTexImage');target.image=im;temp.append(target)
    for node in n:node.select=False
    target.select=True;n.active=target;select([ob]);scene=bpy.context.scene;scene.render.bake.normal_space='TANGENT';scene.render.bake.normal_r='POS_X';scene.render.bake.normal_g='POS_Y';scene.render.bake.normal_b='POS_Z'
    print('BAKE_BEGIN '+group+' '+channel,flush=True)
    bpy.ops.object.bake(type='NORMAL' if channel=='Normal' else 'EMIT',margin=8,use_clear=True,use_selected_to_active=False)
    dest=HERE/'textures';dest.mkdir(exist_ok=True);im.filepath_raw=str(dest/(group+'_'+channel+'.png'));im.file_format='PNG';im.save()
    l.new(old,out.inputs[0])
    for node in temp:n.remove(node)
    im.reload();pixels=np.asarray(im.pixels[:],dtype=np.float64).reshape(-1,4);assert im.has_data and np.isfinite(pixels).all()
    row={'group':group,'channel':channel,'path':im.filepath_raw,'sha256':sha(im.filepath_raw),'size':list(im.size),'colorspace':im.colorspace_settings.name,'RGB_min':pixels[:,:3].min(axis=0).tolist(),'RGB_max':pixels[:,:3].max(axis=0).tolist(),'RGB_std':pixels[:,:3].std(axis=0).tolist()}
    print('BAKE_DONE '+group+' '+channel,flush=True);return row
def main():
    started=time.monotonic();print(json.dumps({'stage':'bake','pid':os.getpid(),'threads':2}),flush=True)
    source=HERE/'west_service_room_editable.blend';src_report=json.loads((HERE/'source_report.json').read_text(encoding='utf-8'));assert sha(source)==src_report['source_sha256']
    assert not (HERE/'bake_complete.blend').exists();bpy.ops.wm.open_mainfile(filepath=str(source));parts=[o for o in bpy.data.objects if o.get('editable_piece')];assert geometry(parts)['geometry_sha256']==src_report['geometry_sha256'];inputs=image_audit()
    scene=bpy.context.scene;scene.cycles.samples=1;scene.cycles.device='CPU';scene.render.threads_mode='FIXED';scene.render.threads=2
    groups={};rows=[]
    for name,mat in GROUPS.items():
        selected=[o for o in parts if o.data.materials[0].name=='WestService_'+mat];groups[name],row=proxy(name,selected);rows.append(row)
    assert sum(r['triangles'] for r in rows)==src_report['triangles']
    for o in parts:o.hide_render=True;o.hide_set(True)
    report={'status':'UV_READY','source_sha256':sha(source),'source_geometry_sha256':src_report['geometry_sha256'],'groups':rows,'textures':[],'input_images':inputs,'AO':'ORM R=1; no ambient occlusion bake or baked light','normal':'Real source tangent normal + restrained source bump, baked once into DeliveryUV; no concept image used as geometric displacement'}
    write('bake_report.json',report);save_relative(HERE/'uv_checkpoint.blend')
    for name,ob in groups.items():
        for channel in ('BaseColor','ORM','Normal'):
            report['textures'].append(bake_one(ob,name,channel));report['status']='BAKED_'+name+'_'+channel;write('bake_report.json',report)
    save_relative(HERE/'bake_complete.blend');bpy.ops.wm.open_mainfile(filepath=str(HERE/'bake_complete.blend'));report['reopened_images']=image_audit()
    assert sha(source)==src_report['source_sha256'];report.update(status='BAKE_COMPLETE',seconds=time.monotonic()-started,pid=os.getpid(),blend_sha256=sha(HERE/'bake_complete.blend'));write('bake_report.json',report)
    print(json.dumps({'stage':'bake_end','pid':os.getpid(),'seconds':report['seconds']}),flush=True)
if __name__=='__main__':main()
