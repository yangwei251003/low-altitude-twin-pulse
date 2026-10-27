"""Read editable source, remove it, import frozen runtime GLB, then render.
Runtime bytes are read-only. Cutaway is an explicitly offline visibility study.
"""
from pathlib import Path
import bpy,json,time,os,hashlib
from mathutils import Vector
from mathutils.kdtree import KDTree
ROOT=Path(__file__).resolve().parents[3];SRC=Path(__file__).resolve().parent;EV=SRC/'evidence'
PATH=ROOT/'assets/v3/underdeck_shell/underdeck_shell.glb';before=hashlib.sha256(PATH.read_bytes()).hexdigest();t0=time.time()
print('SHELL_REIMPORT_START',os.getpid(),before,flush=True)
bpy.ops.wm.open_mainfile(filepath=str(SRC/'underdeck_shell.blend'))
coll=bpy.data.collections['Editable_UnderdeckShell'];source_objects=list(coll.objects);meshes=[o for o in source_objects if o.type=='MESH'];checks=[]
def check(n,ok,d=None):checks.append({'name':n,'passed':bool(ok),'detail':d})
check('413_editable_source_components',len(meshes)==413,len(meshes))
check('one_explicit_active_render_UV',all(len(o.data.uv_layers)==1 and o.data.uv_layers.active.name=='SurfaceUV'and o.data.uv_layers.active.active_render for o in meshes))
ims=[i for i in bpy.data.images if i.source=='FILE']
check('four_external_shared_PBR_maps',len(ims)==4 and all(Path(bpy.path.abspath(i.filepath)).is_file()for i in ims),[{'name':i.name,'path':bpy.path.abspath(i.filepath),'colorspace':i.colorspace_settings.name}for i in ims])
check('color_and_data_spaces',all(i.colorspace_settings.name==('sRGB'if 'BaseColor'in i.name else'Non-Color')for i in ims))
mats={m.name:m for o in meshes for m in o.data.materials}
check('three_materials_explicit_SurfaceUV',len(mats)==3 and all(any(n.type=='UVMAP'and n.uv_map=='SurfaceUV'for n in m.node_tree.nodes)for m in mats.values()),list(mats))
src={};dg=bpy.context.evaluated_depsgraph_get()
for o in meshes:
    s=src.setdefault(o['runtime_group'],{'points':[],'triangles':0,'source_parts':[]});eo=o.evaluated_get(dg);me=eo.to_mesh();me.calc_loop_triangles()
    s['triangles']+=len(me.loop_triangles);s['points']+=[(o.matrix_world@v.co).copy()for v in me.vertices];s['source_parts'].append(o.name);eo.to_mesh_clear()
for s in src.values():
    tr=KDTree(len(s['points']))
    for i,p in enumerate(s['points']):tr.insert(p,i)
    tr.balance();s['tree']=tr
# Do not keep source-model pixels in the render: remove all editable objects.
for o in source_objects:bpy.data.objects.remove(o,do_unlink=True)
names=set(bpy.data.objects.keys());bpy.ops.import_scene.gltf(filepath=str(PATH));objects=[o for o in bpy.data.objects if o.name not in names];imported=[o for o in objects if o.type=='MESH']
check('exact_four_runtime_meshes',set(o.name for o in imported)==set(src),[o.name for o in imported])
comparisons=[]
for o in imported:
    s=src[o.name];o.data.calc_loop_triangles();pts=[(o.matrix_world@v.co).copy()for v in o.data.vertices];tr=KDTree(len(pts))
    for i,p in enumerate(pts):tr.insert(p,i)
    tr.balance();a=max(s['tree'].find(p)[2]for p in pts);b=max(tr.find(p)[2]for p in s['points'])
    check(o.name+':triangle_count',len(o.data.loop_triangles)==s['triangles'],{'source':s['triangles'],'reimport':len(o.data.loop_triangles)})
    check(o.name+':bidirectional_vertices_3micrometres',max(a,b)<3e-6,{'source_to_reimport':b,'reimport_to_source':a})
    comparisons.append({'group':o.name,'source_triangles':s['triangles'],'reimport_triangles':len(o.data.loop_triangles),'source_to_import_max_m':b,'import_to_source_max_m':a,'source_parts':s['source_parts']})
check('runtime_sha_unchanged_before_render',hashlib.sha256(PATH.read_bytes()).hexdigest()==before)
report={'pid':os.getpid(),'blender':bpy.app.version_string,'input_glb':str(PATH),'input_sha256':before,'source_deleted_before_import':True,'checks':checks,'passed':sum(c['passed']for c in checks),'failed':sum(not c['passed']for c in checks),'comparisons':comparisons,'scope':'Actual GLB reimport after deletion of source; CPU2 offline studio; no Godot, collision, motion, performance or final art acceptance.'}
(EV/'reimport_report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
assert not report['failed'],[c for c in checks if not c['passed']]
scene=bpy.context.scene;scene.cycles.device='CPU';scene.cycles.samples=18;scene.render.threads_mode='FIXED';scene.render.threads=2;cam=scene.camera;cam.data.ortho_scale=35
bp=lambda p:Vector((p[0],-p[2],p[1]))
renders=[]
for name,at,cutaway in [('underdeck_shell_glb_front.png',(32,43.8,32),False),('underdeck_shell_glb_rear.png',(-32,43.8,-32),False),('underdeck_shell_glb_navigation_study.png',(32,43.8,32),True)]:
    for o in imported:o.hide_render=cutaway and o.name!='NavigationSurface'
    cam.location=bp(at);cam.rotation_euler=(bp((0,4.8,0))-cam.location).to_track_quat('-Z','Y').to_euler();scene.render.filepath=str(EV/name)
    bpy.ops.render.render(write_still=True)
    renders.append({'file':name,'sha256':hashlib.sha256((EV/name).read_bytes()).hexdigest(),'camera_godot':list(at),'target_godot':[0,4.8,0],'orthographic_width':35,'cover_hidden':cutaway,'limitation':'Offline hard-hide study, NOT production alpha fader'if cutaway else'Actual imported GLB, offline CPU2 studio'})
report.update(render_complete=True,renders=renders,elapsed_seconds=time.time()-t0,sha_unchanged_after_render=hashlib.sha256(PATH.read_bytes()).hexdigest()==before)
(EV/'reimport_report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
assert report['sha_unchanged_after_render']
print('SHELL_REIMPORT_DONE',json.dumps({'pid':os.getpid(),'seconds':report['elapsed_seconds'],'passed':report['passed'],'failed':report['failed'],'sha256':before}),flush=True)
