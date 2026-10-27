"""Stage B: reopen exact checkpoint, native1K bake, same-camera high/low source views."""
import os, time, json, math, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import numpy as np
import bpy
import common as C

def image_new(role):
    im=bpy.data.images.new('Study1K_'+role,width=1024,height=1024,alpha=False,float_buffer=False)
    im.colorspace_settings.name='sRGB' if role=='BaseColor' else 'Non-Color'
    im.generated_color=(1,0,1,1) # Explicit miss sentinel; not a source image edit.
    im.file_format='PNG';im.filepath_raw=str(C.OUT/'textures'/('Study_'+role+'.png'));return im

def material_override(high,low,role,image):
    restore=[]
    mats={m for o in (high,low) for m in o.data.materials if m}
    for m in mats:
        n=m.node_tree.nodes;l=m.node_tree.links;out=next(x for x in n if x.type=='OUTPUT_MATERIAL');old=out.inputs[0].links[0].from_socket
        created=[]
        if role!='Normal':
            em=n.new('ShaderNodeEmission');em.inputs[1].default_value=1;created.append(em)
            if role=='BaseColor':l.new(n['DIAG_Base'].outputs[0],em.inputs[0])
            else:
                rgb=n.new('ShaderNodeCombineColor');rgb.mode='RGB';created.append(rgb)
                l.new(n['DIAG_AO'].outputs['AO'],rgb.inputs['Red']);l.new(n['DIAG_Rough'].outputs[0],rgb.inputs['Green']);rgb.inputs['Blue'].default_value=0
                l.new(rgb.outputs[0],em.inputs[0])
            l.new(em.outputs[0],out.inputs[0])
        target=n.new('ShaderNodeTexImage');target.image=image;created.append(target)
        for node in n:node.select=False
        target.select=True;n.active=target;restore.append((m,out,old,created))
    return restore

def bake_pair(high,low,role,image):
    C.show([high,low]);C.select([high,low],low)
    for layer in low.data.uv_layers:layer.active_render=layer.name=='BakeUV'
    low.data.uv_layers.active_index=low.data.uv_layers.find('BakeUV')
    restore=material_override(high,low,role,image)
    cage=low.copy();cage.data=low.data.copy();bpy.context.scene.collection.objects.link(cage);cage.name='TEMP_BoundedCage';cage.hide_render=True
    for v in cage.data.vertices:v.co+=v.normal*.035
    C.select([high,low],low);s=bpy.context.scene;s.cycles.samples=1;s.render.bake.use_selected_to_active=True;s.render.bake.use_cage=True
    print('BAKE_BEGIN',role,high.name,low.name,flush=True)
    bpy.ops.object.bake(type='NORMAL' if role=='Normal' else 'EMIT',use_selected_to_active=True,use_cage=True,cage_object=cage.name,normal_space='TANGENT',margin=8,use_clear=False)
    for mat,out,old,created in restore:
        mat.node_tree.links.new(old,out.inputs[0])
        for n in created:mat.node_tree.nodes.remove(n)
    s.render.bake.use_cage=False;s.render.bake.use_selected_to_active=False
    bpy.data.objects.remove(cage,do_unlink=True)
    image.save();print('BAKE_END',role,flush=True)

def map_report(im,low):
    data=np.empty(len(im.pixels),dtype=np.float32);im.pixels.foreach_get(data);data=data.reshape((1024,1024,4))
    assert np.isfinite(data).all(),im.name
    uv=low.data.uv_layers['BakeUV'];low.data.calc_loop_triangles();samples=[]
    for t in low.data.loop_triangles:
        u=sum(uv.data[li].uv.x for li in t.loops)/3;v=sum(uv.data[li].uv.y for li in t.loops)/3
        ix=max(0,min(1023,int(u*1024)));iy=max(0,min(1023,int(v*1024)));samples.append(data[iy,ix,:3])
    sample=np.asarray(samples);sentinel=(sample[:,0]>.98)&(sample[:,1]<.01)&(sample[:,2]>.98)
    row={'image':im.name,'path':im.filepath_raw,'sha256':C.sha(im.filepath_raw),'size':list(im.size),'space':im.colorspace_settings.name,
         'centroid_samples':len(samples),'magenta_miss_samples':int(sentinel.sum()),'visible_sample_min':sample.min(axis=0).tolist(),'visible_sample_max':sample.max(axis=0).tolist(),'visible_sample_std':sample.std(axis=0).tolist()}
    assert not sentinel.any(),row
    return row

def final_material(maps):
    m=bpy.data.materials.new('Study_BakedLow_ExplicitPBR');m.use_nodes=True;n=m.node_tree.nodes;l=m.node_tree.links;n.clear()
    uv=n.new('ShaderNodeUVMap');uv.uv_map='BakeUV';nodes={}
    for role,im in maps.items():
        q=n.new('ShaderNodeTexImage');q.image=im;q.extension='EXTEND';l.new(uv.outputs[0],q.inputs[0]);nodes[role]=q
    sep=n.new('ShaderNodeSeparateColor');l.new(nodes['ORM'].outputs[0],sep.inputs[0])
    mult=n.new('ShaderNodeMixRGB');mult.blend_type='MULTIPLY';mult.inputs[0].default_value=1;l.new(nodes['BaseColor'].outputs[0],mult.inputs[1]);l.new(sep.outputs['Red'],mult.inputs[2])
    normal=n.new('ShaderNodeNormalMap');normal.space='TANGENT';normal.uv_map='BakeUV';normal.inputs['Strength'].default_value=1;l.new(nodes['Normal'].outputs[0],normal.inputs['Color'])
    bs=n.new('ShaderNodeBsdfPrincipled');bs.inputs['IOR'].default_value=1.45;l.new(mult.outputs[0],bs.inputs['Base Color']);l.new(sep.outputs['Green'],bs.inputs['Roughness']);l.new(sep.outputs['Blue'],bs.inputs['Metallic']);l.new(normal.outputs[0],bs.inputs['Normal'])
    out=n.new('ShaderNodeOutputMaterial');l.new(bs.outputs[0],out.inputs[0]);return m

def main():
    started=time.monotonic();C.verify_frozen()
    source=Path(os.environ['RECOVERY_SAMPLE_CHECKPOINT']).resolve();assert source.is_relative_to(C.HERE)
    source_sha=C.sha(source);bpy.ops.wm.open_mainfile(filepath=str(source));before=C.images_report();C.write('reopened_source_images.json',before)
    objs={name:bpy.data.objects[name] for name in ('HighGround','LowGround','HighSolids','LowSolids','HighFull','LowFull')}
    lowfull=objs['LowFull'];highfull=objs['HighFull'];(C.OUT/'textures').mkdir()
    maps={role:image_new(role) for role in ('BaseColor','ORM','Normal')};stats=[]
    for role in ('BaseColor','Normal'):
        for suffix in ('Ground','Solids'):bake_pair(objs['High'+suffix],objs['Low'+suffix],role,maps[role])
        stats.append(map_report(maps[role],lowfull));C.write('map_checkpoint_'+role+'.json',stats[-1])
    # AO must see the true full source in one object (only_local), not the low duplicate.
    bake_pair(highfull,lowfull,'ORM',maps['ORM']);stats.append(map_report(maps['ORM'],lowfull));C.write('map_checkpoint_ORM.json',stats[-1])
    material=final_material(maps);lowfull.data.materials.clear();lowfull.data.materials.append(material)
    for face in lowfull.data.polygons:face.material_index=0
    C.show([lowfull]);scene=bpy.context.scene;scene.cycles.samples=24
    saved=C.OUT/'low_baked_preview.blend';bpy.ops.wm.save_as_mainfile(filepath=str(saved),relative_remap=False)
    bpy.ops.wm.open_mainfile(filepath=str(saved));scene=bpy.context.scene;after=C.images_report();C.write('reopened_baked_images.json',after)
    assert {(r['absolute_path'],r['sha256']) for r in before}.issubset({(r['absolute_path'],r['sha256']) for r in after})
    camera={'location':list(scene.camera.location),'rotation':list(scene.camera.rotation_euler),'ortho_scale':scene.camera.data.ortho_scale}
    renders=[]
    for name,file in [('HighFull','01_high_source.png'),('LowFull','02_low_baked.png')]:
        C.show([bpy.data.objects[name]]);scene=bpy.context.scene;scene.cycles.samples=24
        scene.render.filepath=str(C.OUT/file);bpy.ops.render.render(write_still=True)
        renders.append({'path':file,'bytes':(C.OUT/file).stat().st_size,'sha256':C.sha(C.OUT/file)})
    assert C.sha(source)==source_sha;C.verify_frozen()
    C.write('stage_b_result.json',{'status':'RENDERED_PENDING_ACTUAL_VISUAL_REVIEW','pid':os.getpid(),'seconds':time.monotonic()-started,'source_checkpoint':str(source),'checkpoint_unchanged_sha256':source_sha,'low_preview_source':str(saved),'low_preview_sha256':C.sha(saved),'maps':stats,'camera_same_for_both':camera,'renders':renders,'exported':False,'engine_tested':False,'proof_only_not_full_asset_approval':True})
    print('STAGE_B_COMPLETE',os.getpid(),flush=True)

if __name__=='__main__':main()
