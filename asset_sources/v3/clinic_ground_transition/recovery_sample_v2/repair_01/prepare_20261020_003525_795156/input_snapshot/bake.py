"""Stage B: matched-group normal projection and native Blender composition only."""
import os,time,json
import bpy
import numpy as np
import repair_common as R


def output_mat(name):
    m=bpy.data.materials.new(name);m.use_nodes=True;m.node_tree.nodes.clear()
    out=m.node_tree.nodes.new('ShaderNodeOutputMaterial')
    return m,out


def target_node(mat,im):
    n=mat.node_tree.nodes
    for q in n:q.select=False
    q=n.new('ShaderNodeTexImage');q.image=im;q.select=True;n.active=q
    return q


def tex(mat,im):
    n=mat.node_tree.nodes;l=mat.node_tree.links
    uv=n.new('ShaderNodeUVMap');uv.uv_map='BakeUV'
    q=n.new('ShaderNodeTexImage');q.image=im;q.extension='EXTEND';q.interpolation='Closest'
    l.new(uv.outputs[0],q.inputs['Vector']);return q.outputs['Color']


def store_image(im):
    im.save();p=R.Path(im.filepath_raw)
    saved=bpy.data.images.load(str(p),check_existing=False);saved.colorspace_settings.name=im.colorspace_settings.name
    px=tuple(saved.pixels[:4]);assert saved.has_data and px
    return saved,{'file':str(p.relative_to(R.OUT)),'sha256':R.sha(p),'bytes':p.stat().st_size,
                  'size':list(saved.size),'space':saved.colorspace_settings.name}


def project(group,role,image):
    hi=bpy.data.objects[group['source']];lo=bpy.data.objects[group['target']];cage=bpy.data.objects[group['cage']]
    original_mats=list(hi.data.materials);copies=[]
    if role!='Normal':
        for old in original_mats:
            mat=old.copy();mat.name='RepairSource_'+role+'_'+old.name
            n=mat.node_tree.nodes;l=mat.node_tree.links
            out=next(q for q in n if q.type=='OUTPUT_MATERIAL')
            em=n.new('ShaderNodeEmission');em.inputs['Strength'].default_value=1
            l.new(n['DIAG_Base' if role=='BaseColor' else 'DIAG_Rough'].outputs[0],em.inputs['Color'])
            l.new(em.outputs[0],out.inputs['Surface']);copies.append(mat)
        hi.data.materials.clear()
        for mat in copies:hi.data.materials.append(mat)
    else:
        for m in original_mats:
            for q in m.node_tree.nodes:
                if q.type=='BSDF_PRINCIPLED':assert not q.inputs['Normal'].links,'Unexpected source macro normal'
    target,out=output_mat('RepairRawTarget_'+group['name']+'_'+role)
    bs=target.node_tree.nodes.new('ShaderNodeBsdfPrincipled');target.node_tree.links.new(bs.outputs[0],out.inputs[0]);target_node(target,image)
    lo.data.materials.clear();lo.data.materials.append(target)
    for p in lo.data.polygons:p.material_index=0
    R.show([hi,lo]);cage.hide_render=True;R.select([hi,lo],lo)
    lo.data.uv_layers.active_index=lo.data.uv_layers.find('BakeUV')
    for u in lo.data.uv_layers:u.active_render=u.name=='BakeUV'
    bpy.context.scene.cycles.samples=1
    print('PROJECT_BEGIN',group['name'],role,flush=True)
    bpy.ops.object.bake(type='NORMAL' if role=='Normal' else 'EMIT',use_selected_to_active=True,
                        use_cage=True,cage_object=cage.name,cage_extrusion=0.,max_ray_distance=0.,
                        normal_space='TANGENT',uv_layer='BakeUV',margin=0,margin_type='EXTEND',use_clear=True)
    hi.data.materials.clear()
    for m in original_mats:hi.data.materials.append(m)
    print('PROJECT_END',group['name'],role,flush=True)


def compose(full,labels,role,raw,old,target):
    mats={};full.data.materials.clear()
    for group in sorted(set(labels)):
        mat,out=output_mat('RepairCompose_'+role+'_'+group);n=mat.node_tree.nodes;l=mat.node_tree.links
        if role=='Normal':color=tex(mat,raw[group])
        elif role=='BaseColor':color=tex(mat,raw['SideBase'] if group=='ground_side' else old['BaseColor'])
        else:
            split=n.new('ShaderNodeSeparateColor');split.mode='RGB';l.new(tex(mat,old['ORM']),split.inputs[0])
            combine=n.new('ShaderNodeCombineColor');combine.mode='RGB'
            l.new(split.outputs['Red'],combine.inputs['Red']) # Frozen physical full-source AO.
            if group=='ground_side':
                sr=n.new('ShaderNodeSeparateColor');sr.mode='RGB';l.new(tex(mat,raw['SideRough']),sr.inputs[0]);rough=sr.outputs['Red']
            else:rough=split.outputs['Green']
            l.new(rough,combine.inputs['Green']);l.new(split.outputs['Blue'],combine.inputs['Blue']);color=combine.outputs[0]
        em=n.new('ShaderNodeEmission');em.inputs['Strength'].default_value=1;l.new(color,em.inputs['Color']);l.new(em.outputs[0],out.inputs[0])
        target_node(mat,target);mats[group]=len(full.data.materials);full.data.materials.append(mat)
    assert len(full.data.polygons)==len(labels)
    for p,label in zip(full.data.polygons,labels):p.material_index=mats[label]
    R.show([full]);R.select([full],full)
    bpy.ops.object.bake(type='EMIT',use_selected_to_active=False,use_cage=False,uv_layer='BakeUV',
                        margin=1,margin_type='EXTEND',use_clear=True)


def final_material(maps):
    m,out=output_mat('Repair_ExplicitPBR_NormalAndAO');n=m.node_tree.nodes;l=m.node_tree.links
    uv=n.new('ShaderNodeUVMap');uv.uv_map='BakeUV';textures={}
    for role,im in maps.items():
        q=n.new('ShaderNodeTexImage');q.name='Repair_'+role;q.image=im;q.extension='EXTEND';q.interpolation='Linear'
        l.new(uv.outputs[0],q.inputs['Vector']);textures[role]=q
    split=n.new('ShaderNodeSeparateColor');split.mode='RGB';l.new(textures['ORM'].outputs[0],split.inputs[0])
    multiply=n.new('ShaderNodeMixRGB');multiply.blend_type='MULTIPLY';multiply.inputs[0].default_value=1
    l.new(textures['BaseColor'].outputs[0],multiply.inputs[1]);l.new(split.outputs['Red'],multiply.inputs[2])
    nm=n.new('ShaderNodeNormalMap');nm.space='TANGENT';nm.uv_map='BakeUV';nm.inputs['Strength'].default_value=1
    l.new(textures['Normal'].outputs[0],nm.inputs['Color'])
    bs=n.new('ShaderNodeBsdfPrincipled');bs.inputs['IOR'].default_value=1.45
    l.new(multiply.outputs[0],bs.inputs['Base Color']);l.new(split.outputs['Green'],bs.inputs['Roughness'])
    l.new(split.outputs['Blue'],bs.inputs['Metallic']);l.new(nm.outputs[0],bs.inputs['Normal']);l.new(bs.outputs[0],out.inputs[0])
    return m


def main():
    started=time.monotonic();R.verify_frozen();prev,result,blend=R.source_stage_result('prepare')
    bpy.ops.wm.open_mainfile(filepath=str(blend));R.write('reopened_prepared_images.json',R.images())
    plan=json.loads((prev/'projection_groups.json').read_text(encoding='utf-8'))
    semantics=json.loads((prev/'semantics.json').read_text(encoding='utf-8'))
    R.write('projection_groups.json',plan);R.write('semantics.json',semantics)
    full=bpy.data.objects['RepairLowFull'];high=bpy.data.objects['RepairHighFull']
    assert R.digest(full.data)==semantics['low_geometry_bakeuv'] and R.digest(high.data)==semantics['high_geometry']
    old={k:bpy.data.images['Study1K_'+k] for k in ('BaseColor','ORM','Normal')}
    raw={};records=[];(R.OUT/'raw_maps').mkdir();(R.OUT/'textures').mkdir()
    for group in plan['groups']:
        im=R.new_image('RawNormal_'+group['name'],'Non-Color',R.OUT/'raw_maps');project(group,'Normal',im)
        raw[group['name']],row=store_image(im);records.append(row);R.write('bake_checkpoint.json',records)
    side=next(g for g in plan['groups'] if g['name']=='ground_side')
    for role,key,space in [('BaseColor','SideBase','sRGB'),('Roughness','SideRough','Non-Color')]:
        im=R.new_image(key,space,R.OUT/'raw_maps');project(side,role,im)
        raw[key],row=store_image(im);records.append(row);R.write('bake_checkpoint.json',records)
    maps={};final_records=[]
    for role in ('BaseColor','Normal','ORM'):
        im=R.new_image('Repair_'+role,'sRGB' if role=='BaseColor' else 'Non-Color',R.OUT/'textures')
        compose(full,plan['full_triangle_groups'],role,raw,old,im)
        maps[role],row=store_image(im);final_records.append(row);R.write('final_map_checkpoint.json',final_records)
    owner=R.raster_owners(full.data);valid=owner>=0
    labels=np.array(plan['full_triangle_groups']);top=np.zeros_like(valid);top[valid]=labels[owner[valid]]=='ground_top'
    arrays={k:R.array(im) for k,im in maps.items()};old_ao=R.array(old['ORM'])[:,:,0]
    sample=json.loads((R.INSPECTION/'negative_normal_pixels.json').read_text(encoding='utf-8'))['pixels'];after=[]
    for row in sample:
        x,y=row['pixel_xy_bottom_origin'];rgb=arrays['Normal'][y,x,:3]
        after.append({'pixel':[x,y],'surface':row['surface'],'before_rgb':row['normal_rgb'],'after_rgb':rgb.tolist(),
                      'after_negative_tangent_z':bool(rgb[2]<.5)})
    aoerr=float(np.max(np.abs(arrays['ORM'][:,:,0][valid]-old_ao[valid])))
    stats={'occupied_pixels':int(valid.sum()),'top_negative_before':1550,'top_negative_after':int((top&(arrays['Normal'][:,:,2]<.5)).sum()),
           'old_bad_pixel_before_after':after,'AO_max_absolute_channel_difference':aoerr,
           'AO_policy':'Frozen full-source AO sampled at unchanged BakeUV, native EMIT recomposition, at most one 8-bit level quantization.',
           'normal_RGB_std_occupied':arrays['Normal'][:,:,:3][valid].std(axis=0).tolist(),
           'normal_RGB_range_occupied':[arrays['Normal'][:,:,:3][valid].min(axis=0).tolist(),arrays['Normal'][:,:,:3][valid].max(axis=0).tolist()]}
    R.write('normal_before_after.json',stats)
    errors=[]
    for k,a in arrays.items():
        sentinel=(a[:,:,0]>.98)&(a[:,:,1]<.01)&(a[:,:,2]>.98)&valid
        if not np.isfinite(a).all() or sentinel.any():errors.append([k,'invalid or unbaked occupied pixel',int(sentinel.sum())])
    if stats['top_negative_after']:errors.append(['Normal','reversed top normals remain',stats['top_negative_after']])
    if aoerr>1/255+1e-6:errors.append(['AO','changed beyond one 8bit level',aoerr])
    mat=final_material(maps);full.data.materials.clear();full.data.materials.append(mat)
    for p in full.data.polygons:p.material_index=0
    assert R.digest(full.data)==semantics['low_geometry_bakeuv'] and R.digest(high.data)==semantics['high_geometry']
    assert R.scene_lock(bpy.context.scene)==semantics['camera']
    R.show([full]);R.images();saved=R.OUT/('bake_failure.blend' if errors else 'baked_repair.blend')
    bpy.ops.wm.save_as_mainfile(filepath=str(saved),relative_remap=False)
    R.verify_frozen();R.write('validation_errors.json',errors)
    assert not errors,errors
    R.write('result.json',{'stage':'bake','status':'PASS','pid':os.getpid(),'seconds':time.monotonic()-started,
                         'blend':saved.name,'blend_sha256':R.sha(saved),'maps':final_records,'raw_maps':records,
                         'low_triangles':semantics['low_triangles'],'geometry_changed':False,'rendered':False,
                         'AO_enabled':True,'Normal_enabled':True,'visual_approval':False})


if __name__=='__main__':main()
