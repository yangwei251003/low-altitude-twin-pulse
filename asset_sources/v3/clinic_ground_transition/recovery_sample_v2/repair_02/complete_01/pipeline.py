"""One authorized run: proven boundary clip, matched AO, same-camera high/low.

Normal and BaseColor images are immutable inputs. No export/runtime writes.
"""
from pathlib import Path
import sys, os, time, json, math, traceback
sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parent))
import bpy
import numpy as np
from mathutils import Vector
import common as C
import prepare_boundary as B

SIZE=1024


def verify_prepared_inputs():
    manifest=json.loads((HERE/'prepared_manifest.json').read_text(encoding='utf-8'));rows=[]
    for base,items in [(HERE,manifest['files']),(HERE.parent,manifest['readonly_parent_inputs'])]:
        for item in items:
            p=base/item['path'];assert p.stat().st_size==item['bytes'] and C.sha(p)==item['sha256'],str(p)
            rows.append({'path':str(p),**item})
    return rows


def checkpoint(stage,started,extra=None):
    C.write('checkpoint_'+stage+'.json',{'stage':stage,'pid':os.getpid(),'elapsed_seconds':time.monotonic()-started,**(extra or {})})


def select(objects,active):
    bpy.ops.object.select_all(action='DESELECT')
    for ob in objects:ob.hide_set(False);ob.hide_viewport=False;ob.select_set(True)
    bpy.context.view_layer.objects.active=active


def visibility(names):
    wanted=set(names)
    for ob in bpy.data.objects:
        if ob.type=='MESH':ob.hide_render=ob.name not in wanted
    bpy.context.view_layer.update()
    actual={o.name for o in bpy.data.objects if o.type=='MESH' and not o.hide_render}
    assert actual==wanted,(actual,wanted)
    return sorted(actual)


def scene_lock(scene):
    return {'camera_matrix':[list(r) for r in scene.camera.matrix_world],
            'ortho_scale':scene.camera.data.ortho_scale,
            'resolution':[scene.render.resolution_x,scene.render.resolution_y,scene.render.resolution_percentage],
            'view_transform':scene.view_settings.view_transform,'look':scene.view_settings.look,
            'exposure':scene.view_settings.exposure,'gamma':scene.view_settings.gamma,
            'lights':[{'name':o.name,'matrix':[list(r) for r in o.matrix_world],
                       'energy':o.data.energy,'color':list(o.data.color),'size':o.data.size}
                      for o in bpy.data.objects if o.type=='LIGHT']}


def image_array(im):
    values=np.empty(len(im.pixels),np.float32);im.pixels.foreach_get(values)
    assert im.has_data and np.isfinite(values).all(),im.name
    return values.reshape((im.size[1],im.size[0],4))


def new_image(name,folder):
    im=bpy.data.images.new(name,width=SIZE,height=SIZE,alpha=False,float_buffer=False)
    im.colorspace_settings.name='Non-Color';im.generated_color=(1,0,1,1)
    im.file_format='PNG';im.filepath_raw=str(folder/(name+'.png'));return im


def save_image(im):
    im.save();p=Path(im.filepath_raw)
    loaded=bpy.data.images.load(str(p),check_existing=False);loaded.colorspace_settings.name='Non-Color'
    a=image_array(loaded);assert a.shape==(SIZE,SIZE,4)
    return loaded,{'path':str(p),'bytes':p.stat().st_size,'sha256':C.sha(p),'space':loaded.colorspace_settings.name,'size':list(loaded.size)}


def subset(data,ids,name):
    ids=np.asarray(ids,np.int32);old=data['mesh'];used=np.unique(data['vi'][ids]);remap=np.full(len(data['co']),-1,np.int32);remap[used]=np.arange(len(used))
    me=bpy.data.meshes.new(name);me.from_pydata(data['co'][used].tolist(),[],remap[data['vi'][ids]].tolist());me.update()
    for m in old.materials:me.materials.append(m)
    for p,i in zip(me.polygons,ids):p.material_index=int(data['materials'][i]);p.use_smooth=bool(data['smooth'][i])
    for u in old.uv_layers:me.uv_layers.new(name=u.name)
    for u in old.uv_layers:me.uv_layers[u.name].data.foreach_set('uv',data['uv'][u.name][ids].astype(np.float32).ravel())
    for attr in old.color_attributes:
        assert attr.domain=='CORNER',attr.name
        a=np.asarray([tuple(x.color) for x in attr.data],np.float64)[data['li'][ids]]
        me.color_attributes.new(name=attr.name,type=attr.data_type,domain='CORNER').data.foreach_set('color',a.astype(np.float32).ravel())
    me.normals_split_custom_set(data['normals'][ids].reshape((-1,3)).tolist());me.update()
    if 'BakeUV' in me.uv_layers:
        me.uv_layers.active_index=me.uv_layers.find('BakeUV')
        for u in me.uv_layers:u.active_render=u.name=='BakeUV'
    ob=bpy.data.objects.new(name,me);bpy.context.scene.collection.objects.link(ob);ob.matrix_world=data['object'].matrix_world.copy();ob['boundary_AO_tool']=True
    actual=C.read(ob);assert np.array_equal(actual['tri'],data['tri'][ids])
    for u in data['uv']:assert np.array_equal(actual['uv'][u],data['uv'][u][ids])
    n=actual['normals']/np.linalg.norm(actual['normals'],axis=-1)[...,None];s=data['normals'][ids]/np.linalg.norm(data['normals'][ids],axis=-1)[...,None]
    angle=np.degrees(np.arccos(np.clip(np.sum(n*s,axis=-1),-1,1)))
    assert angle.max()<.1,(name,'split normals',float(angle.max()))
    return ob,used


def raster(data):
    owner=np.full((SIZE,SIZE),-1,np.int32)
    for i,q in enumerate(data['uv']['BakeUV']):
        a,b,c=q;den=float((b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0]));assert abs(den)>1e-14
        x0=max(0,int(math.floor(q[:,0].min()*SIZE-.5)));x1=min(SIZE-1,int(math.ceil(q[:,0].max()*SIZE-.5)))
        y0=max(0,int(math.floor(q[:,1].min()*SIZE-.5)));y1=min(SIZE-1,int(math.ceil(q[:,1].max()*SIZE-.5)))
        yy,xx=np.mgrid[y0:y1+1,x0:x1+1];px=(xx+.5)/SIZE-a[0];py=(yy+.5)/SIZE-a[1]
        u=(px*(c[1]-a[1])-py*(c[0]-a[0]))/den;v=((b[0]-a[0])*py-(b[1]-a[1])*px)/den
        mask=(u>1e-7)&(v>1e-7)&(1-u-v>1e-7);block=owner[y0:y1+1,x0:x1+1]
        assert not (mask&(block>=0)).any(),'Candidate UV overlap'
        block[mask]=i
    return owner


def target_material(image,name):
    mat=bpy.data.materials.new(name);mat.use_nodes=True;mat.node_tree.nodes.clear()
    n=mat.node_tree.nodes;l=mat.node_tree.links;out=n.new('ShaderNodeOutputMaterial');bs=n.new('ShaderNodeBsdfPrincipled');l.new(bs.outputs[0],out.inputs[0])
    tex=n.new('ShaderNodeTexImage');tex.image=image;tex.select=True;n.active=tex
    return mat


def texture(mat,image):
    n=mat.node_tree.nodes;l=mat.node_tree.links;uv=n.new('ShaderNodeUVMap');uv.uv_map='BakeUV'
    tex=n.new('ShaderNodeTexImage');tex.image=image;tex.extension='EXTEND';tex.interpolation='Closest';l.new(uv.outputs[0],tex.inputs['Vector'])
    return tex


def corner_cage_offsets(oldlow,plan):
    lookup={}
    for g in plan['groups']:
        lo=C.read(bpy.data.objects[g['target']]);ca=C.read(bpy.data.objects[g['cage']])
        assert np.array_equal(lo['vi'],ca['vi'])
        for tri,offset in zip(lo['tri'],ca['tri']-lo['tri']):lookup[(g['name'],C.key(tri))]=(tri,offset)
    offsets=[]
    for label,tri in zip(plan['full_triangle_groups'],oldlow['tri']):
        other,off=lookup[(label,C.key(tri))];bypos={tuple(p):v for p,v in zip(other,off)}
        offsets.append([bypos[tuple(p)] for p in tri])
    return np.asarray(offsets)


def verify_tangent_mapping(old,new,ids,weights):
    # Normal map stays byte-identical: verify its basis at newly interpolated
    # target corners instead of assuming an unchanged UV name is sufficient.
    for d in (old,new):d['mesh'].calc_tangents(uvmap='BakeUV')
    ot=np.asarray([tuple(x.tangent) for x in old['mesh'].loops],np.float64)[old['li']]
    osign=np.asarray([x.bitangent_sign for x in old['mesh'].loops],np.float64)[old['li']]
    nt=np.asarray([tuple(x.tangent) for x in new['mesh'].loops],np.float64)[new['li']]
    nsign=np.asarray([x.bitangent_sign for x in new['mesh'].loops],np.float64)[new['li']]
    expected=np.einsum('nij,njk->nik',weights,ot[ids]);normal=new['normals']/np.linalg.norm(new['normals'],axis=-1)[...,None]
    expected-=normal*np.sum(expected*normal,axis=-1)[...,None];expected/=np.linalg.norm(expected,axis=-1)[...,None]
    nt/=np.linalg.norm(nt,axis=-1)[...,None]
    angle=np.degrees(np.arccos(np.clip(np.sum(nt*expected,axis=-1),-1,1)))
    esign=np.sign(np.einsum('nij,nj->ni',weights,osign[ids]))
    report={'max_tangent_angle_deg':float(angle.max()),'sign_flips':int((esign!=nsign).sum()),'normal_map_rebaked':False}
    C.write('retained_normal_basis.json',report)
    assert angle.max()<.1 and not (esign!=nsign).any(),report


def main():
    started=time.monotonic();static_inputs=verify_prepared_inputs();inputs=C.verify_inputs();C.write('complete_inputs_before.json',inputs)
    C.write('prepared_files_before.json',static_inputs)
    bpy.ops.wm.open_mainfile(filepath=str(C.ROOT/C.CONTRACT['blend']))
    context={o.name for o in bpy.data.objects if o.type=='MESH' and not o.hide_render and not(o.get('study_part') or o.get('repair_part'))}
    semantics=json.loads((C.ROOT/Path(C.CONTRACT['blend']).parent/'semantics.json').read_text(encoding='utf-8'))
    B.main() # Existing bounded local geometry operation only. No bake/render.
    (C.OUT/'result.json').rename(C.OUT/'boundary_result.json');checkpoint('boundary',started)
    plan=json.loads((C.ROOT/C.CONTRACT['projection_groups']).read_text(encoding='utf-8'))
    oldlow=C.read(bpy.data.objects['RepairLowFull']);oldhigh=C.read(bpy.data.objects['RepairHighFull'])
    low=C.read(bpy.data.objects['BoundaryLowFull']);high=C.read(bpy.data.objects['BoundaryHighFull'])
    lm=json.loads((C.OUT/'BoundaryLowFull_original_face_and_corner_mapping.json').read_text());hm=json.loads((C.OUT/'BoundaryHighFull_original_face_and_corner_mapping.json').read_text())
    li=np.asarray(lm['original_triangle'],np.int32);lw=np.asarray(lm['original_corner_barycentrics'],np.float64)
    hi=np.asarray(hm['original_triangle'],np.int32)
    lowlabels=np.asarray(plan['full_triangle_groups'])[li];highlabels=np.asarray(C.labels(oldhigh,plan))[hi]
    verify_tangent_mapping(oldlow,low,li,lw)
    offsets=np.einsum('nij,njk->nik',lw,corner_cage_offsets(oldlow,plan)[li])
    oldmat=low['mesh'].materials[0]
    maps={role:oldmat.node_tree.nodes['Repair_'+role].image for role in ('BaseColor','ORM','Normal')}
    original_map_records={role:{'path':str(Path(bpy.path.abspath(im.filepath)).resolve()),'sha256':C.sha(Path(bpy.path.abspath(im.filepath)).resolve())} for role,im in maps.items()}
    C.write('immutable_map_inputs.json',original_map_records)
    owner=raster(low);valid=owner>=0;groupmask={name:valid&(np.take(lowlabels,np.maximum(owner,0))==name) for name in sorted(set(lowlabels))}
    (C.OUT/'raw_AO').mkdir();(C.OUT/'textures').mkdir()
    groups=[];copies={};restore=[]
    for name in sorted(set(lowlabels)):
        lids=np.flatnonzero(lowlabels==name);hids=np.flatnonzero(highlabels==name)
        source,_=subset(high,hids,'BoundaryAOSource_'+name);target,used=subset(low,lids,'BoundaryAOTarget_'+name)
        cage=target.copy();cage.data=target.data.copy();bpy.context.scene.collection.objects.link(cage);cage.name='BoundaryAOCage_'+name;cage.hide_render=True;cage['boundary_AO_tool']=True
        vertex_offsets={}
        for tid,off in zip(lids,offsets[lids]):
            for vid,v in zip(low['vi'][tid],off):
                if int(vid) in vertex_offsets:assert np.linalg.norm(vertex_offsets[int(vid)]-v)<1e-7
                vertex_offsets[int(vid)]=v
        for v,oldid in zip(cage.data.vertices,used):v.co=target.data.vertices[v.index].co+Vector(vertex_offsets[int(oldid)])
        cage.data.update()
        # A target remains available to the bake operator but cannot become an
        # AO occluder; only the eleven real high groups are ray-visible.
        for prop in ('visible_camera','visible_diffuse','visible_glossy','visible_transmission','visible_volume_scatter','visible_shadow'):
            assert hasattr(target,prop),prop;setattr(target,prop,False)
        original=list(source.data.materials);source.data.materials.clear()
        for old in original:
            if old.name not in copies:
                mat=old.copy();mat.name='BoundaryGlobalAO_'+old.name;n=mat.node_tree.nodes;l=mat.node_tree.links
                ao=n['DIAG_AO'];ao.only_local=False
                assert not ao.inside and abs(ao.inputs['Distance'].default_value-.035)<1e-7 and not ao.inputs['Normal'].links
                out=next(x for x in n if x.type=='OUTPUT_MATERIAL');socket=out.inputs[0].links[0].from_socket
                em=n.new('ShaderNodeEmission');em.inputs['Strength'].default_value=1;l.new(ao.outputs['AO'],em.inputs['Color']);l.new(em.outputs[0],out.inputs[0])
                restore.append((mat,out,socket,em));copies[old.name]=mat
            source.data.materials.append(copies[old.name])
        groups.append({'name':name,'source':source,'target':target,'cage':cage,'high_count':len(hids),'low_count':len(lids)})
    assert len(groups)==11 and sum(g['high_count'] for g in groups)==len(high['tri'])
    sources=[g['source'].name for g in groups];raw={};bakes=[]
    for g in groups:
        image=new_image('AO_'+g['name'],C.OUT/'raw_AO');target=g['target'];mat=target_material(image,'AOTarget_'+g['name'])
        target.data.materials.clear();target.data.materials.append(mat)
        for p in target.data.polygons:p.material_index=0
        visible=visibility(sources+[target.name]);select([g['source'],target],target)
        selected=sorted(o.name for o in bpy.context.selected_objects);assert selected==sorted([g['source'].name,target.name])
        bpy.context.scene.cycles.device='CPU';bpy.context.scene.cycles.samples=1
        print('AO_GROUP_BEGIN',g['name'],flush=True)
        bpy.ops.object.bake(type='EMIT',use_selected_to_active=True,use_cage=True,cage_object=g['cage'].name,
                            cage_extrusion=0.,max_ray_distance=0.,uv_layer='BakeUV',margin=0,use_clear=True)
        saved,record=save_image(image);raw[g['name']]=saved;arr=image_array(saved)
        sentinel=(arr[:,:,0]>.98)&(arr[:,:,1]<.01)&(arr[:,:,2]>.98)&groupmask[g['name']]
        assert not sentinel.any(),('Unbaked group pixel',g['name'],int(sentinel.sum()))
        bakes.append({'group':g['name'],'map':record,'selected_sources':[g['source'].name],'render_visible':visible,
                      'other_high_groups_only_occluders':10,'only_local':False,'target_all_ray_visibility_off':True,
                      'occupied_pixel_AO_range':[float(arr[:,:,0][groupmask[g['name']]].min()),float(arr[:,:,0][groupmask[g['name']]].max())]})
        C.write('AO_group_checkpoint.json',bakes)
    for mat,out,socket,em in restore:
        mat.node_tree.links.new(socket,out.inputs[0]);mat.node_tree.nodes.remove(em)
    checkpoint('matched_AO',started,{'groups':bakes})
    # Native self-EMIT composition: only R is replaced; existing G/B and entire
    # Normal/BaseColor images keep their actual original data and UV meaning.
    orm=new_image('Boundary_ORM',C.OUT/'textures');composition={};low['mesh'].materials.clear()
    for name in sorted(raw):
        mat=target_material(orm,'AOCompose_'+name);n=mat.node_tree.nodes;l=mat.node_tree.links;out=next(x for x in n if x.type=='OUTPUT_MATERIAL')
        oldtex=texture(mat,maps['ORM']);split=n.new('ShaderNodeSeparateColor');l.new(oldtex.outputs['Color'],split.inputs[0])
        aotex=texture(mat,raw[name]);asep=n.new('ShaderNodeSeparateColor');l.new(aotex.outputs['Color'],asep.inputs[0])
        combine=n.new('ShaderNodeCombineColor');l.new(asep.outputs['Red'],combine.inputs['Red']);l.new(split.outputs['Green'],combine.inputs['Green']);l.new(split.outputs['Blue'],combine.inputs['Blue'])
        em=n.new('ShaderNodeEmission');em.inputs['Strength'].default_value=1;l.new(combine.outputs[0],em.inputs['Color']);l.new(em.outputs[0],out.inputs[0])
        composition[name]=len(low['mesh'].materials);low['mesh'].materials.append(mat)
    for p,name in zip(low['mesh'].polygons,lowlabels):p.material_index=composition[name]
    visibility([low['object'].name]);select([low['object']],low['object'])
    bpy.ops.object.bake(type='EMIT',use_selected_to_active=False,use_cage=False,uv_layer='BakeUV',margin=1,margin_type='EXTEND',use_clear=True)
    neworm,ormrecord=save_image(orm);oldarr=image_array(maps['ORM']);newarr=image_array(neworm)
    err=float(np.abs(newarr[:,:,1:3][valid]-oldarr[:,:,1:3][valid]).max());assert err<=1/255+1e-6,err
    aoevidence=C.HERE/'ao_20261020_022434_439283/old_cage_ray_identity.json'
    previous=json.loads(aoevidence.read_text());comparisons=[]
    for row in previous['actual_texel_centers']:
        x,y=row['pixel_bottom_origin'];comparisons.append({'pixel':[x,y],'old_AO':float(oldarr[y,x,0]),'new_AO':float(newarr[y,x,0]),'old_projection_group':row['full_source'].get('group'),'still_ground_pixel':bool(valid[y,x] and lowlabels[owner[y,x]]=='ground_top')})
    C.write('AO_before_after_neighborhood.json',{'old_known_pixels':comparisons,'R_range_occupied':[float(newarr[:,:,0][valid].min()),float(newarr[:,:,0][valid].max())],
        'G_B_max_error':err,'no_artistic_brightness_multiplier':True,'warning':'Numeric changes are not a visual pass; actual contact shade must be reviewed.'})
    final=oldmat.copy();final.name='Boundary_ExistingNormal_NewPhysicalAO';final.node_tree.nodes['Repair_ORM'].image=neworm
    low['mesh'].materials.clear();low['mesh'].materials.append(final)
    for p in low['mesh'].polygons:p.material_index=0
    # High reference uses full actual candidate geometry and global AO, with its
    # original BSDF/material colors retained. No high tools remain visible.
    original=list(high['mesh'].materials);high['mesh'].materials.clear()
    for mat in original:high['mesh'].materials.append(copies[mat.name])
    C.write('image_readback_before_save.json',C.images_before_save())
    visibility([low['object'].name]+list(context));saved=C.OUT/'boundary_AO_repair.blend';bpy.ops.wm.save_as_mainfile(filepath=str(saved),relative_remap=False)
    saved_sha=C.sha(saved);checkpoint('bake_saved',started,{'blend':str(saved),'sha256':saved_sha,'ORM':ormrecord})
    bpy.ops.wm.open_mainfile(filepath=str(saved));C.write('actual_reopened_images.json',C.images_before_save())
    for role,rec in original_map_records.items():assert C.sha(rec['path'])==rec['sha256'],role
    lowob=bpy.data.objects['BoundaryLowFull'];highob=bpy.data.objects['BoundaryHighFull'];scene=bpy.context.scene
    reopened_low=C.read(lowob);reopened_high=C.read(highob)
    assert np.array_equal(reopened_low['tri'],low['tri']) and np.array_equal(reopened_high['tri'],high['tri'])
    for uv in low['uv']:assert np.array_equal(reopened_low['uv'][uv],low['uv'][uv])
    for uv in high['uv']:assert np.array_equal(reopened_high['uv'][uv],high['uv'][uv])
    assert scene_lock(scene)==semantics['camera']
    finalmat=lowob.data.materials[0];nodes=finalmat.node_tree.nodes
    bs=next(n for n in nodes if n.type=='BSDF_PRINCIPLED');nm=bs.inputs['Normal'].links[0].from_node
    assert nm.type=='NORMAL_MAP' and nm.uv_map=='BakeUV' and nm.inputs['Strength'].default_value==1.
    assert bs.inputs['Base Color'].links[0].from_node.type=='MIX_RGB'
    assert C.sha(Path(bpy.path.abspath(nodes['Repair_Normal'].image.filepath)).resolve())==original_map_records['Normal']['sha256']
    C.write('actual_reopen_contract.json',{'high_low_positions_exact':True,'UV_layers_exact':True,'camera_lights_exact':True,
        'Normal_enabled_unchanged':True,'AO_enabled':True,'global_AO_high_materials':[{'name':m.name,'only_local':m.node_tree.nodes['DIAG_AO'].only_local} for m in highob.data.materials]})
    scene.cycles.device='CPU';scene.cycles.samples=24;renders=[]
    for ob,name in [(highob,'01_high_source.png'),(lowob,'02_low_baked.png')]:
        assert scene_lock(scene)==semantics['camera']
        visibility([ob.name]+list(context));scene.render.filepath=str(C.OUT/name)
        bpy.ops.render.render(write_still=True);p=C.OUT/name
        renders.append({'path':str(p),'sha256':C.sha(p),'bytes':p.stat().st_size});C.write('render_checkpoint.json',renders)
    after=C.verify_inputs();assert after==inputs and C.sha(saved)==saved_sha
    assert C.sha(ormrecord['path'])==ormrecord['sha256']
    assert verify_prepared_inputs()==static_inputs
    C.write('complete_inputs_after.json',after)
    C.write('result.json',{'status':'COMPLETE_PENDING_ACTUAL_IMAGE_REVIEW','pid':os.getpid(),'seconds':time.monotonic()-started,
        'blend':str(saved),'sha256':saved_sha,'renders':renders,'AO_projection_groups':11,'AO_full_high_occluders':True,
        'Normal_BaseColor_unchanged':original_map_records,'normal_rebaked':False,'exported':False,'whole_asset_approved':False})


if __name__=='__main__':
    try:main()
    except Exception as exc:
        failure={'status':'FAIL_STOP','pid':os.getpid(),'exception':repr(exc),'traceback':traceback.format_exc()}
        try:
            C.images_before_save();saved=C.OUT/'failed_pipeline.blend';bpy.ops.wm.save_as_mainfile(filepath=str(saved),relative_remap=False);failure['blend']=str(saved)
        except Exception as save_error:failure['save_error']=repr(save_error)
        C.write('failure.json',failure);raise
