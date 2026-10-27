"""Reopen editable source, delete model, reimport actual GLBs and render.
The evidence is CPU offline. Runtime assets are strictly read-only here.
"""
from pathlib import Path
import bpy,json,hashlib,time,os
from mathutils import Vector
from mathutils.kdtree import KDTree
ROOT=Path(__file__).resolve().parents[3];SRC=Path(__file__).resolve().parent;EV=SRC/'evidence'
paths=[ROOT/'assets/v3/underdeck_door'/n for n in ['panel.glb','fixed_rail.glb']]
hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest()for p in paths};started=time.time()
bpy.ops.wm.open_mainfile(filepath=str(SRC/'underdeck_door.blend'))
collection=bpy.data.collections['Editable_UnderdeckDoor'];objects=list(collection.objects);meshes=[o for o in objects if o.type=='MESH']
checks=[]
def check(n,ok,d=None):checks.append({'name':n,'passed':bool(ok),'detail':d})
check('editable_parts_preserved',len(meshes)==126,len(meshes))
check('single_active_render_SurfaceUV',all(len(o.data.uv_layers)==1 and o.data.uv_layers.active.name=='SurfaceUV' and o.data.uv_layers.active.active_render for o in meshes))
images=[i for i in bpy.data.images if i.source=='FILE']
check('twenty_external_PBR_maps',len(images)==20 and all(Path(bpy.path.abspath(i.filepath)).is_file()for i in images),[{'name':i.name,'path':bpy.path.abspath(i.filepath),'colorspace':i.colorspace_settings.name}for i in images])
check('base_sRGB_data_noncolor',all(i.colorspace_settings.name==('sRGB'if 'BaseColor'in i.name else 'Non-Color')for i in images))
usedmats={m.name:m for o in meshes for m in o.data.materials}
check('five_source_materials',len(usedmats)==5,list(usedmats))
check('explicit_UVMap_binding',all(any(n.type=='UVMAP' and n.uv_map=='SurfaceUV'for n in m.node_tree.nodes)for m in usedmats.values()))
source_groups={};deps=bpy.context.evaluated_depsgraph_get()
for o in meshes:
    g=o['runtime_group'];s=source_groups.setdefault(g,{'points':[],'triangles':0,'source_parts':[]})
    eo=o.evaluated_get(deps);me=eo.to_mesh();me.calc_loop_triangles();s['triangles']+=len(me.loop_triangles);s['source_parts'].append(o.name)
    s['points'].extend((o.matrix_world@v.co).copy()for v in me.vertices);eo.to_mesh_clear()
for g,s in source_groups.items():
    t=KDTree(len(s['points']))
    for i,p in enumerate(s['points']):t.insert(p,i)
    t.balance();s['tree']=t
    s['bounds']=[[min(p[k]for p in s['points'])for k in range(3)],[max(p[k]for p in s['points'])for k in range(3)]]
# Crucial provenance: source model removed before either runtime GLB is loaded.
for o in objects:bpy.data.objects.remove(o,do_unlink=True)
imported=[]
for path in paths:
    before=set(bpy.data.objects.keys());bpy.ops.import_scene.gltf(filepath=str(path))
    imported.extend(o for o in bpy.data.objects if o.name not in before)
ims=[o for o in imported if o.type=='MESH'];check('six_runtime_meshes',len(ims)==6,[o.name for o in ims])
comparisons=[]
for o in ims:
    name=o.name;s=source_groups[name];o.data.calc_loop_triangles();points=[o.matrix_world@v.co for v in o.data.vertices]
    tree=KDTree(len(points))
    for i,p in enumerate(points):tree.insert(p,i)
    tree.balance()
    forward=max(s['tree'].find(p)[2]for p in points);reverse=max(tree.find(p)[2]for p in s['points'])
    bounds=[[min(p[k]for p in points)for k in range(3)],[max(p[k]for p in points)for k in range(3)]]
    check(name+':triangle_count',len(o.data.loop_triangles)==s['triangles'],{'source':s['triangles'],'reimport':len(o.data.loop_triangles)})
    check(name+':both_way_vertices',max(forward,reverse)<3e-6,{'import_to_source_max_m':forward,'source_to_import_max_m':reverse})
    check(name+':bounds',max(abs(a-b)for aa,bb in zip(bounds,s['bounds'])for a,b in zip(aa,bb))<3e-6)
    comparisons.append({'group':name,'source_parts':s['source_parts'],'source_triangles':s['triangles'],'reimport_triangles':len(o.data.loop_triangles),'reimport_to_source_max_m':forward,'source_to_reimport_max_m':reverse,'source_bounds_Blender':s['bounds'],'reimport_bounds_Blender':bounds})
check('binary_sha_before_render',all(hashlib.sha256(p.read_bytes()).hexdigest()==hashes[str(p)]for p in paths))
report={'input_glbs':hashes,'blender':bpy.app.version_string,'pid':os.getpid(),'source_editable_meshes':len(meshes),'source_removed_before_import':True,'comparisons':comparisons,'checks':checks,'passed':sum(c['passed']for c in checks),'failed':sum(not c['passed']for c in checks),'scope':'Actual final GLBs reimported after deleting source model. Evaluated geometry vertices checked bidirectionally at 3 micrometres, triangle counts and bounds. Not an independent topology equivalence proof or Godot physics/render/performance approval.'}
(EV/'reimport_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
assert not report['failed'],[c for c in checks if not c['passed']]
scene=bpy.context.scene;scene.render.threads_mode='FIXED';scene.render.threads=2;scene.cycles.device='CPU';scene.cycles.samples=24
cam=scene.camera
def bp(p):return Vector((p[0],-p[2],p[1]))
def camera(at,target,scale=10.6):
    cam.location=bp(at);cam.rotation_euler=(bp(target)-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=scale
renders=[]
for name,at,target,opening in [('underdeck_door_glb_front.png',(8,4.4,13),(2,.25,0),0),('underdeck_door_glb_rear.png',(-4,4.4,-13),(2,.25,0),0),('underdeck_door_glb_open.png',(8,4.4,13),(2,.25,0),4.2)]:
    bpy.data.objects['UnderdeckDoorPanel'].location.x=opening;camera(at,target);scene.render.filepath=str(EV/name)
    bpy.ops.render.render(write_still=True)
    renders.append({'file':name,'sha256':hashlib.sha256((EV/name).read_bytes()).hexdigest(),'panel_translation_godot':[opening,0,0],'camera_godot':list(at),'target_godot':list(target),'ortho_scale':10.6,'source':'actual imported GLB; offline CPU2 studio'})
assert all(hashlib.sha256(p.read_bytes()).hexdigest()==hashes[str(p)]for p in paths)
report.update(render_complete=True,rendered_files=renders,sha_unchanged_after_render=True,elapsed_seconds=time.time()-started)
(EV/'reimport_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('DOOR_REIMPORT_DONE',json.dumps({'pid':os.getpid(),'passed':report['passed'],'failed':report['failed'],'elapsed_seconds':report['elapsed_seconds'],'input_glbs':hashes},ensure_ascii=False),flush=True)
