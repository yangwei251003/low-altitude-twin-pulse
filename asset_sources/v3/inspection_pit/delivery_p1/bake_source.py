import os,sys,time,traceback
from pathlib import Path
sys.dont_write_bytecode=True;sys.path.insert(0,str(Path(__file__).resolve().parent))
from common import *

def bake_channel(proxy, label, size, channel):
    image=bpy.data.images.new(label+'_'+channel,width=size,height=size,alpha=False)
    image.colorspace_settings.name='sRGB' if channel=='BaseColor' else 'Non-Color'
    image.generated_color=(.5,.5,1,1) if channel=='Normal' else (1,1,1,1)
    restore=[]
    for mat in proxy.data.materials:
        nodes,links=mat.node_tree.nodes,mat.node_tree.links; bs=shader(mat)
        output=next(n for n in nodes if n.type=='OUTPUT_MATERIAL' and n.is_active_output)
        original=output.inputs['Surface'].links[0].from_socket; temporary=[]
        if channel!='Normal':
            emit=nodes.new('ShaderNodeEmission');emit.inputs['Strength'].default_value=1;temporary.append(emit)
            if channel=='BaseColor':
                s=bs.inputs['Base Color']
                if s.is_linked:links.new(s.links[0].from_socket,emit.inputs['Color'])
                else:emit.inputs['Color'].default_value=s.default_value
            else:
                combine=nodes.new('ShaderNodeCombineColor');combine.mode='RGB'
                combine.inputs['Red'].default_value=1;temporary.append(combine)
                for target,key in [('Green','Roughness'),('Blue','Metallic')]:
                    s=bs.inputs[key]
                    if s.is_linked:links.new(s.links[0].from_socket,combine.inputs[target])
                    else:combine.inputs[target].default_value=s.default_value
                links.new(combine.outputs[0],emit.inputs['Color'])
            links.new(emit.outputs[0],output.inputs['Surface'])
        target=nodes.new('ShaderNodeTexImage');target.image=image;temporary.append(target)
        for node in nodes:node.select=False
        target.select=True;nodes.active=target;restore.append((mat,output,original,temporary))
    proxy.hide_render=False;select([proxy]);scene=bpy.context.scene
    scene.render.bake.normal_space='TANGENT';scene.render.bake.normal_r='POS_X'
    scene.render.bake.normal_g='POS_Y';scene.render.bake.normal_b='POS_Z'
    print('BAKE_BEGIN '+label+' '+channel,flush=True)
    bpy.ops.object.bake(type='NORMAL' if channel=='Normal' else 'EMIT',
                        use_clear=True,margin=2,use_selected_to_active=False)
    path=OUT/'textures'/(label+'_'+channel+'.png');path.parent.mkdir(exist_ok=True)
    image.filepath_raw=str(path);image.file_format='PNG';image.save()
    for mat,output,original,temporary in restore:
        mat.node_tree.links.new(original,output.inputs['Surface'])
        for node in temporary:mat.node_tree.nodes.remove(node)
    proxy.hide_render=True;proxy.hide_set(True)
    loaded=bpy.data.images.load(str(path),check_existing=False)
    loaded.colorspace_settings.name=image.colorspace_settings.name
    pixel=list(loaded.pixels[:4])
    assert loaded.has_data and list(loaded.size)==[size,size] and all(math.isfinite(x) for x in pixel)
    # Full image numeric check without editing the native bake.
    import numpy as np
    data=np.empty(size*size*4,dtype=np.float32);loaded.pixels.foreach_get(data)
    assert np.isfinite(data).all()
    data=data.reshape(-1,4);stats={'min_rgb':data[:,:3].min(axis=0).tolist(),
                                  'max_rgb':data[:,:3].max(axis=0).tolist(),
                                  'mean_rgb':data[:,:3].mean(axis=0).tolist()}
    print('BAKE_DONE '+label+' '+channel,flush=True)
    return {'set':label,'channel':channel,'path':str(path),'sha256':sha(path),
            'bytes':path.stat().st_size,'size':[size,size],'space':loaded.colorspace_settings.name,
            'pixel':pixel,'finite':True,'statistics':stats}

def main():
    start=time.monotonic();source_check()
    prep=json.loads((OUT/'prepare_report.json').read_text(encoding='utf-8'))
    assert prep['status']=='PREPARED_NO_BAKE' and prep['source_sha256']==SOURCE_SHA
    assert sha(OUT/'prepared_bake.blend')==prep['prepared_sha256']
    assert not (OUT/'bake_complete.blend').exists()
    bpy.ops.wm.open_mainfile(filepath=str(OUT/'prepared_bake.blend'));image_audit()
    for ob in bpy.data.objects:
        if ob.type=='MESH':ob.hide_render=True
    scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=8
    scene.render.threads_mode='FIXED';scene.render.threads=2
    report={'status':'BAKING','source_sha256':SOURCE_SHA,'textures':[],
            'normal':'Same evaluated source triangles and split normals; original Bump, no stain-derived height.',
            'AO':'ORM R neutral 1; no AO measurement or painted light bake.'}
    for group,size in GROUPS.items():
        proxy=bpy.data.objects[group+'_BakeProxy']
        for channel in ('BaseColor','ORM','Normal'):
            report['textures'].append(bake_channel(proxy,group,size,channel))
            report['status']='BAKED_'+group+'_'+channel;write('bake_report.json',report)
            bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'checkpoint.blend'),relative_remap=False)
    target=OUT/'bake_complete.blend';bpy.ops.wm.save_as_mainfile(filepath=str(target),relative_remap=False)
    source_check();report.update(status='BAKE_COMPLETE_PENDING_EXPORT',blend_sha256=sha(target),
                                 pid=os.getpid(),seconds=time.monotonic()-start)
    write('bake_report.json',report)

if __name__=='__main__':
    try:main()
    except Exception as e:
        write('bake_failure.json',{'exception':repr(e),'traceback':traceback.format_exc(),'pid':os.getpid()})
        try:bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'failed_bake.blend'),relative_remap=False)
        except Exception:pass
        raise
