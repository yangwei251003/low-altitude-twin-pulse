"""P3 material-only edit of the frozen, actually reopened P1 geometry."""
from pathlib import Path
import bpy,sys,os,json,hashlib,time,math,traceback
sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
OUT=Path(os.environ['RACK_PREVIEW_OUTPUT']).resolve();assert OUT.is_relative_to(HERE)
sys.path.insert(0,str(HERE));import materials


def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def write(name,data):(OUT/name).write_text(json.dumps(data,ensure_ascii=False,indent=2,allow_nan=False),encoding='utf-8')


def frozen_geometry():
    rows=[]
    for ob in sorted((x for x in bpy.data.objects if x.get('editable_piece')),key=lambda x:x.name):
        me=ob.data;me.calc_loop_triangles()
        row={'name':ob.name,'matrix':[list(r) for r in ob.matrix_world],
             'vertices':[list(v.co) for v in me.vertices],'triangles':[list(t.vertices) for t in me.loop_triangles],
             'polygons':[[list(p.vertices),p.material_index,p.use_smooth] for p in me.polygons],
             'corner_normals':[list(n.vector) for n in me.corner_normals],
             'UV':{u.name:[list(x.uv) for x in u.data] for u in me.uv_layers},
             'UV_active':[me.uv_layers.active_index,[(u.name,u.active_render) for u in me.uv_layers]],
             'SurfaceUse':[list(x.color) for x in me.color_attributes['SurfaceUse'].data]}
        rows.append(row)
    payload=json.dumps(rows,sort_keys=True,separators=(',',':')).encode()
    return {'sha256':hashlib.sha256(payload).hexdigest(),'parts':len(rows),'triangles':sum(len(x['triangles']) for x in rows)}


def scene_lock():
    s=bpy.context.scene
    return {'camera':[list(x) for x in s.camera.matrix_world],'ortho_scale':s.camera.data.ortho_scale,
            'resolution':[s.render.resolution_x,s.render.resolution_y,s.render.resolution_percentage],
            'look':[s.view_settings.view_transform,s.view_settings.look,s.view_settings.exposure],
            'lights':[(o.name,[list(x) for x in o.matrix_world],o.data.energy,list(o.data.color),o.data.size) for o in bpy.data.objects if o.type=='LIGHT']}


def images_check(contract):
    rows=[];matched={}
    for im in bpy.data.images:
        if im.source!='FILE':continue
        p=Path(bpy.path.abspath(im.filepath)).resolve();assert p.is_file(),(im.name,str(p))
        pixel=list(im.pixels[:4]);assert len(pixel)==4 and im.has_data and all(math.isfinite(x) for x in pixel),im.name
        actual=sha(p);rows.append({'image':im.name,'path':str(p),'sha256':actual,'size':list(im.size),'space':im.colorspace_settings.name,'pixel':pixel})
        im.filepath=str(p)
        for role,expected in contract['textures'].items():
            if p.name==Path(expected['path']).name:
                assert actual==expected['sha256'] and im.colorspace_settings.name==expected['space'],role
                matched[role]=im
    assert set(matched)==set(contract['textures'])
    return rows,matched


def material_check(new_materials):
    deck=new_materials['DeckSteel'];nodes=deck.node_tree.nodes;links=deck.node_tree.links
    normal=nodes['OriginalSteelNormal'];bump=nodes['ManufacturedAntiSlipBump'];bs=nodes['SourcePrincipled']
    assert normal.uv_map=='SteelUV' and normal.space=='TANGENT'
    assert any(x.from_node==normal and x.to_node==bump and x.to_socket.name=='Normal' for x in links)
    assert any(x.from_node==bump and x.to_node==bs and x.to_socket.name=='Normal' for x in links)
    assert bump.inputs['Height'].is_linked and bump.inputs['Distance'].default_value>0
    green=[]
    for ob in bpy.data.objects:
        if ob.get('editable_piece') and ob.get('finish')=='DeckSteel':
            green.extend(x.color[1] for x in ob.data.color_attributes['SurfaceUse'].data)
    assert green and max(green)>.9,'Actual top SurfaceUse mask must exist'
    return {'normal_chain':'NonColor NormalGL / SteelUV tangent NormalMap -> manufactured Bump.Normal -> Principled.Normal',
            'bump_height_linked':True,'bump_distance_m':bump.inputs['Distance'].default_value,'bump_strength':bump.inputs['Strength'].default_value,
            'rib_pitch_m':.07,'rib_nominal_size_m':[.028,.005],'mask_green_max':max(green),'mask_positive_corners':sum(x>.9 for x in green),
            'material_count':len(new_materials),'opaque':all(m.node_tree.nodes['SourcePrincipled'].inputs['Alpha'].default_value==1 for m in new_materials.values()),
            'emission_zero':all(m.node_tree.nodes['SourcePrincipled'].inputs['Emission Strength'].default_value==0 for m in new_materials.values())}


def main():
    started=time.monotonic();print(json.dumps({'status':'BLENDER_STARTED','pid':os.getpid(),'cpu_threads':2,'output':str(OUT)}),flush=True)
    contract=json.loads((HERE/'input_contract.json').read_text(encoding='utf-8'));src=ROOT/contract['source']['path']
    assert sha(src)==contract['source']['sha256'] and src.stat().st_size==contract['source']['bytes']
    bpy.ops.wm.open_mainfile(filepath=str(src));before=frozen_geometry();camera=scene_lock();image_before,images=images_check(contract)
    new_materials=materials.build(images);slot_report=[]
    for ob in bpy.data.objects:
        if ob.get('editable_piece'):
            used={int(p.material_index) for p in ob.data.polygons}
            old_slots=[None if m is None else m.name for m in ob.data.materials]
            indices=[int(p.material_index) for p in ob.data.polygons]
            for i,mat in enumerate(ob.data.materials):
                if mat is None:
                    assert i not in used,(ob.name,'used empty material slot',i)
                    continue
                role=mat.name.removeprefix('CalibrationP2_')
                assert mat.name=='CalibrationP2_'+role and role in new_materials,(ob.name,i,mat.name)
                ob.data.materials[i]=new_materials[role]
            assert [int(p.material_index) for p in ob.data.polygons]==indices
            slot_report.append({'object':ob.name,'old_slots':old_slots,'new_slots':[None if m is None else m.name for m in ob.data.materials],
                                'face_count_by_slot':{str(i):indices.count(i) for i in sorted(used)},'polygon_indices_unchanged':True})
    write('actual_material_slots.json',slot_report)
    bpy.context.view_layer.update();assert frozen_geometry()==before and scene_lock()==camera
    write('material_chain_check.json',material_check(new_materials));write('images_before_save.json',image_before)
    saved=OUT/'calibration_rack_p3_editable.blend';bpy.ops.wm.save_as_mainfile(filepath=str(saved),relative_remap=False);saved_sha=sha(saved)
    bpy.ops.wm.open_mainfile(filepath=str(saved));after=frozen_geometry();assert after==before and scene_lock()==camera
    images_after,_=images_check(contract)
    assert [(x['sha256'],x['space'],x['size']) for x in images_after]==[(x['sha256'],x['space'],x['size']) for x in image_before]
    mats={kind:bpy.data.materials['CalibrationP3_'+kind] for kind in ('PaintSteel','DeckSteel','HardwareSteel')}
    write('actual_reopen.json',{'geometry_UV_normals_exact':after,'camera_and_lights_exact':True,'images':images_after,'material_chain':material_check(mats)})
    scene=bpy.context.scene;scene.cycles.device='CPU';scene.render.threads_mode='FIXED';scene.render.threads=2
    scene.render.filepath=str(OUT/'01_reference_oblique.png');bpy.ops.render.render(write_still=True)
    assert sha(src)==contract['source']['sha256'] and sha(saved)==saved_sha
    write('result.json',{'status':'SOURCE_RENDERED_PENDING_ACTUAL_REVIEW','pid':os.getpid(),'elapsed_seconds':time.monotonic()-started,
                        'blend':str(saved),'blend_sha256':saved_sha,'image':str(OUT/'01_reference_oblique.png'),
                        'image_sha256':sha(OUT/'01_reference_oblique.png'),'source_P2_unchanged':True,'geometry_exact':after,
                        'baked':False,'exported':False,'runtime_written':False})


if __name__=='__main__':
    try:main()
    except Exception as exc:
        write('failure.json',{'exception':repr(exc),'traceback':traceback.format_exc(),'pid':os.getpid()})
        try:bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'failed_source.blend'),relative_remap=False)
        except Exception:pass
        raise
