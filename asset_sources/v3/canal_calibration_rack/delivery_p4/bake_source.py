import os,time,sys,traceback
from pathlib import Path
sys.dont_write_bytecode=True;sys.path.insert(0,str(Path(__file__).resolve().parent))
from common import *

def bake_channel(label,size,channel,targets):
    image=bpy.data.images.new(label+'_'+channel,width=size,height=size,alpha=False)
    image.colorspace_settings.name='sRGB' if channel=='BaseColor' else 'Non-Color'
    image.generated_color=(.5,.5,1,1) if channel=='Normal' else (1,1,1,1)
    scene=bpy.context.scene;scene.render.bake.normal_space='TANGENT';scene.render.bake.normal_r='POS_X';scene.render.bake.normal_g='POS_Y';scene.render.bake.normal_b='POS_Z'
    for index,(low,high) in enumerate(targets):
        print('BAKE '+label+' '+channel+' '+low.name,flush=True)
        restore=[];target_nodes=[];materials=set(m for o in high or [low] for m in o.data.materials if m)
        for mat in materials:
            n,l=mat.node_tree.nodes,mat.node_tree.links;bs=shader(mat);out=next(n for n in n if n.type=='OUTPUT_MATERIAL' and n.is_active_output)
            old=out.inputs['Surface'].links[0].from_socket;temporary=[]
            if channel!='Normal':
                emit=n.new('ShaderNodeEmission');emit.inputs['Strength'].default_value=1;temporary.append(emit)
                if channel=='BaseColor':
                    s=bs.inputs['Base Color']
                    if s.is_linked:l.new(s.links[0].from_socket,emit.inputs[0])
                    else:emit.inputs[0].default_value=s.default_value
                else:
                    combine=n.new('ShaderNodeCombineColor');combine.mode='RGB';combine.inputs['Red'].default_value=1;temporary.append(combine)
                    for c,key in [('Green','Roughness'),('Blue','Metallic')]:
                        s=bs.inputs[key]
                        if s.is_linked:l.new(s.links[0].from_socket,combine.inputs[c])
                        else:combine.inputs[c].default_value=s.default_value
                    l.new(combine.outputs[0],emit.inputs[0])
                l.new(emit.outputs[0],out.inputs['Surface'])
            restore.append((mat,out,old,temporary))
        for mat in low.data.materials:
            n=mat.node_tree.nodes;node=n.new('ShaderNodeTexImage');node.image=image
            for other in n:other.select=False
            node.select=True;n.active=node;target_nodes.append((mat,node))
        low.hide_render=False
        for h in high:h.hide_render=False
        select(high+[low],low)
        bpy.ops.object.bake(type='NORMAL' if channel=='Normal' else 'EMIT',use_clear=index==0,margin=2 if label=='Deck' else 6,
                            use_selected_to_active=bool(high),cage_extrusion=.006,max_ray_distance=.015)
        for mat,node in target_nodes:mat.node_tree.nodes.remove(node)
        for mat,out,old,temporary in restore:
            mat.node_tree.links.new(old,out.inputs['Surface'])
            for node in temporary:mat.node_tree.nodes.remove(node)
        low.hide_render=True
        for h in high:h.hide_render=True
    folder=OUT/'textures';folder.mkdir(exist_ok=True);path=folder/(label+'_'+channel+'.png')
    image.filepath_raw=str(path);image.file_format='PNG';image.save()
    check=bpy.data.images.load(str(path),check_existing=False);check.colorspace_settings.name=image.colorspace_settings.name
    pixel=list(check.pixels[:4]);assert check.has_data and list(check.size)==[size,size]
    return {'set':label,'channel':channel,'path':str(path),'sha256':sha(path),'size':[size,size],'space':image.colorspace_settings.name,'pixel':pixel}

def main():
    start=time.monotonic();assert sha(SOURCE)==SOURCE_SHA;assert not (OUT/'bake_complete.blend').exists()
    print(json.dumps({'stage':'bake_start','pid':os.getpid(),'cpu_threads':2}),flush=True)
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE));images=audit_images(copy=True);write('source_images.json',images)
    originals=sorted([o for o in bpy.data.objects if o.get('editable_piece')],key=lambda o:o.name)
    assert len(originals)==51
    plates=[o for o in originals if o.name in PLATES];structure=proxy([o for o in originals if o.name not in PLATES],'StructureBakeProxy')
    deck=unwrap(plates,structure);assert len(deck.data.polygons)==944 and len(structure.data.polygons)==3796
    targets=split_deck(deck,plates)
    for o in bpy.data.objects:
        if o.type=='MESH':o.hide_render=True
    scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=8
    scene.render.threads_mode='FIXED';scene.render.threads=2
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'prepared_bake.blend'),relative_remap=False)
    report={'status':'PREPARED','source_sha256':SOURCE_SHA,'triangles':4740,'textures':[],
            'normal':'Each plate projects only its matching P4 high plate and real rib mesh; other 47 parts self bake.',
            'AO':'ORM red is neutral 1. No new AO bake or painted contact shadow.',
            'UV':'Deck primary top atlas has continuous physical coordinates; bottom/sides are separate.'}
    deck_pairs=[(low,[bpy.data.objects[name+'_P4_HighPlate'],bpy.data.objects[name+'_P4_EditableRibs']]) for name,low in targets]
    for label,size,pairs in [('Deck',2048,deck_pairs),('Structure',1024,[(structure,[])])]:
        for channel in ('BaseColor','ORM','Normal'):
            report['textures'].append(bake_channel(label,size,channel,pairs));report['status']='BAKED_'+label+'_'+channel;write('bake_report.json',report)
            bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'checkpoint.blend'),relative_remap=False)
    write('expected_low_triangles.json',{'DeckSurface':source_rows(deck.data),'StructureAndHardware':source_rows(structure.data)})
    final=OUT/'bake_complete.blend';bpy.ops.wm.save_as_mainfile(filepath=str(final),relative_remap=False)
    report.update(status='BAKE_COMPLETE_PENDING_EXPORT',pid=os.getpid(),seconds=time.monotonic()-start,blend_sha256=sha(final))
    assert sha(SOURCE)==SOURCE_SHA;write('bake_report.json',report)

if __name__=='__main__':
    try:main()
    except Exception as e:
        write('bake_failure.json',{'exception':repr(e),'traceback':traceback.format_exc(),'pid':os.getpid()})
        try:bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'failed_bake.blend'),relative_remap=False)
        except Exception:pass
        raise
