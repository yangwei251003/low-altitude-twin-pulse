"""V8 bounded yellow-strip occlusion fix: two jamb foot front faces only.
Read-only V7; no new bake/GLB/material edits. Await root CPU2 window.
"""
from pathlib import Path
import bpy,json,hashlib,shutil,time,os,types
from mathutils import Vector
from mathutils.bvhtree import BVHTree
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
SOURCE=HERE.parent/'prototype_v7/pump_shell_prototype.blend'
SOURCE_SHA='e00c3cdba2f5ea9c9e8f54969d81273ee10a2309ef18d7525909d06563324da7'
GEOMETRY_SHA='9b7ee29ff3147480882f0f1ce034c0be7031791511845a5d0fd789d5b57680be'
helper=types.ModuleType('frozen_v5_helpers');helper.__file__=str(HERE/'frozen_v5_helpers.py')
exec(compile(Path(helper.__file__).read_text(encoding='utf-8'),helper.__file__,'exec'),helper.__dict__)
support=helper.support;bp=helper.bp;gp=helper.gp;bounds=helper.bounds;sha=helper.sha;ORIGIN=Vector((-7,0,8))
CHANGED={'PumpSouthWestJamb_Foot','PumpSouthEastJamb_Foot'}

def yellow_visibility(parts):
    dg=bpy.context.evaluated_depsgraph_get();verts=[];triangles=[];owners=[]
    for o in parts:
        me=bpy.data.meshes.new_from_object(o.evaluated_get(dg),preserve_all_data_layers=True,depsgraph=dg)
        me.transform(o.matrix_world);me.calc_loop_triangles();base=len(verts)
        verts.extend([v.co.copy() for v in me.vertices])
        for t in me.loop_triangles:triangles.append(tuple(base+i for i in t.vertices));owners.append(o.name)
        bpy.data.meshes.remove(me)
    bvh=BVHTree.FromPolygons(verts,triangles,all_triangles=True);rows=[]
    for prefix in ['PumpSouthWestJamb','PumpSouthEastJamb']:
        o=bpy.data.objects[prefix+'_EntryPaint'];lo,hi=bounds(helper.world_vertices(o))
        for u in [.15,.5,.85]:
            for v in [.06,.2,.4,.6,.8,.94]:
                at=Vector((lo[0]+(hi[0]-lo[0])*u,lo[1]+(hi[1]-lo[1])*v,12.35))
                hit,normal,index,dist=bvh.ray_cast(bp(at-ORIGIN),bp((0,0,-1)),.6)
                owner=owners[index] if index is not None else None
                rows.append({'paint':o.name,'origin_world':list(at),'first_hit':owner,'hit_world':list(gp(hit)+ORIGIN) if hit is not None else None,'passed':owner==o.name})
    return rows

def main():
    start=time.time();assert sha(SOURCE)==SOURCE_SHA;assert not (HERE/'pump_shell_prototype.blend').exists()
    print(json.dumps({'stage':'start','pid':os.getpid(),'threads':2,'scope':'two foot fronts only'}),flush=True)
    evidence=HERE/'evidence';inputs=HERE/'source_inputs';evidence.mkdir(exist_ok=True);inputs.mkdir(exist_ok=True)
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE));bpy.context.view_layer.update()
    parts=[o for o in bpy.data.objects if o.get('editable_piece')];before=support.geometry_digest(parts);assert before['sha256']==GEOMETRY_SHA
    unchanged_before=support.geometry_digest([o for o in parts if o.name not in CHANGED])
    source_names={o.name for o in parts};input_images=[]
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath:
            src=Path(bpy.path.abspath(im.filepath));dest=inputs/src.name;shutil.copyfile(src,dest);digest=sha(src);assert sha(dest)==digest
            im.filepath=str(dest);im.reload();input_images.append({'source':str(src),'copy':str(dest),'sha256':digest,'colorspace':im.colorspace_settings.name})
    plan=json.loads((HERE.parent/'planning/contract.json').read_text(encoding='utf-8'))
    actual=json.loads((ROOT/'data/v3/terrain/i2_clinic_layout.json').read_text(encoding='utf-8'));fixed={s['id']:s for s in actual['fixed_solids']}
    for s in plan['fixed_shell_solids']:assert fixed[s['id']]['min']==s['world_min'] and fixed[s['id']]['max']==s['world_max']
    baseline_visibility=yellow_visibility(parts)
    changed=[]
    for name in sorted(CHANGED):
        o=bpy.data.objects[name];lo,hi=bounds(helper.world_vertices(o));old=[lo.copy(),hi.copy()]
        hi[2]=12.244;helper.resize_box(name,lo,hi);helper.refresh_uv(o)
        changed.append({'object':name,'before_world_bounds':old,'after_world_bounds':[lo,hi],'front_inset_m':.006,'method':'Only front face recessed; same closed component, original height/width/material/bevel retained.'})
    bpy.context.view_layer.update();geometry=support.geometry_digest(parts);report=helper.inspect(parts,plan)
    after_visibility=yellow_visibility(parts);unchanged_after=support.geometry_digest([o for o in parts if o.name not in CHANGED])
    report['checks'].extend([
        {'name':'all 198 other pieces including both yellow strips byte-identical evaluated geometry','passed':unchanged_before['sha256']==unchanged_after['sha256'],'detail':{'before':unchanged_before['sha256'],'after':unchanged_after['sha256']}},
        {'name':'actual editable object names unchanged','passed':source_names=={o.name for o in parts}},
        {'name':'source topology remains 13600 triangles','passed':geometry['triangles']==13600},
        {'name':'36 real triangle front rays first hit original yellow strips','passed':all(r['passed'] for r in after_visibility),'detail':after_visibility},
    ])
    report.update(status='GEOMETRY_CHECKED_PENDING_RENDER',geometry=geometry,source_v7_sha256=SOURCE_SHA,changes=changed,baseline_yellow_rays=baseline_visibility,image_inputs=input_images,no_material_changes=True,no_bake_no_glb_no_runtime=True)
    (evidence/'geometry_material_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    if not all(c['passed'] for c in report['checks']):
        bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'FAILED_geometry.blend'));raise RuntimeError('Source protection/actual visibility gate failed; no render.')
    scene=bpy.context.scene;scene.cycles.device='CPU';scene.cycles.samples=24;scene.render.threads_mode='FIXED';scene.render.threads=2
    report['camera']={'location':list(scene.camera.location),'rotation':list(scene.camera.rotation_euler),'ortho':scene.camera.data.ortho_scale,'resolution':[scene.render.resolution_x,scene.render.resolution_y],'view':scene.view_settings.view_transform,'exposure':scene.view_settings.exposure}
    assert (scene.camera.location-Vector((16,-16,21))).length<1e-5
    blend=HERE/'pump_shell_prototype.blend';bpy.ops.wm.save_as_mainfile(filepath=str(blend),relative_remap=False)
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath:im.filepath=bpy.path.relpath(im.filepath)
    bpy.ops.wm.save_as_mainfile(filepath=str(blend),relative_remap=False);bpy.ops.wm.open_mainfile(filepath=str(blend));scene=bpy.context.scene
    readback=[]
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath:
            p=Path(bpy.path.abspath(im.filepath));im.reload();pix=tuple(im.pixels[:4]);assert len(pix)==4 and im.has_data
            digest=sha(p);assert digest in {r['sha256'] for r in input_images}
            readback.append({'relative':im.filepath,'resolved':str(p),'sha256':digest,'colorspace':im.colorspace_settings.name,'size':list(im.size)})
    assert support.geometry_digest([o for o in bpy.data.objects if o.get('editable_piece')])['sha256']==geometry['sha256']
    path=evidence/'pump_shell_full.png';scene.render.filepath=str(path);bpy.ops.render.render(write_still=True)
    assert sha(SOURCE)==SOURCE_SHA
    report.update(status='SOURCE_RENDERED_PENDING_VISUAL_REVIEW',images=[{'path':str(path),'sha256':sha(path),'scope':'Source-only default review camera, no game acceptance.'}],reopened_images=readback,blend_sha256=sha(blend),elapsed_seconds=time.time()-start)
    (evidence/'geometry_material_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'stage':'end','pid':os.getpid(),'seconds':time.time()-start,'triangles':geometry['triangles']}),flush=True)
if __name__=='__main__':main()
