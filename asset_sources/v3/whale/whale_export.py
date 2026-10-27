"""Export evaluated, merged copies; retain editable source and local motion axes."""
import hashlib
from mathutils import Matrix
# Save true closed state before making disposable export copies.
bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'siphon_whale.blend'))
deps=bpy.context.evaluated_depsgraph_get();exp=bpy.data.collections.new('Export_Disposable');scene.collection.children.link(exp)
export_root=bpy.data.objects.new('Export_SiphonWhale',None);exp.objects.link(export_root)
export_root['asset_version']='I1-whale-production-v'+str(REV);export_root['godot_forward']='+Z'
exports=[export_root];epivots={}
for name,p in pivots.items():
 e=bpy.data.objects.new('Export_'+name,None);exp.objects.link(e);e.location=p.location;e.parent=export_root
 e['godot_local_axis']=[0,0,1];e['open_degrees']=-68 if name.startswith('Port') else 68;epivots[name]=e;exports.append(e)
bpy.context.view_layer.update()
origins={'StaticHull':(0,0,0),'PortHatch':(-5.75,.10,0),'StarboardHatch':(5.75,.10,0),'CoreShield':(0,2.2,2.8),'CoreGlow':core_pos,'PortGlow':(-7,.25,0),'StarboardGlow':(7,.25,0)}
statistics=[];bounds=[];total=0
for group,objects in groups.items():
 copies=[]
 for obj in objects:
  c=obj.copy();c.data=bpy.data.meshes.new_from_object(obj.evaluated_get(deps),preserve_all_data_layers=True,depsgraph=deps);c.modifiers.clear();exp.objects.link(c);c.parent=None;c.matrix_world=obj.matrix_world.copy();copies.append(c)
 bpy.ops.object.select_all(action='DESELECT')
 for c in copies:c.select_set(True)
 bpy.context.view_layer.objects.active=copies[0];bpy.ops.object.join();o=bpy.context.object;o.name='Export_'+group
 bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
 scene.cursor.location=pos(origins[group]);bpy.ops.object.origin_set(type='ORIGIN_CURSOR');world=o.matrix_world.copy()
 o.parent=epivots['PortHatchPivot'] if group=='PortHatch' else (epivots['StarboardHatchPivot'] if group=='StarboardHatch' else export_root);o.matrix_world=world
 o.data.calc_loop_triangles();tris=len(o.data.loop_triangles);total+=tris
 bounds.extend(o.matrix_world@v.co for v in o.data.vertices);exports.append(o)
 statistics.append({'node':group,'triangles':tris,'materials':[m.name for m in o.data.materials],'source_objects':[p.name for p in objects]})
 if group=='CoreShield':o['open_translation_godot']=[0,.30,-3.2]
 if group.endswith('Glow'):o['emissive_only']=True
export_markers={}
for name in ['CoreWeakpoint','PortWeakpoint','StarboardWeakpoint','AttackOrigin','RetryEntry','RawCommandRecordAnchor']:
 marker=bpy.data.objects[name];e=bpy.data.objects.new('Export_'+name,None);exp.objects.link(e);e.location=marker.location;e.parent=export_markers['CoreWeakpoint'] if name=='RawCommandRecordAnchor' else export_root;exports.append(e);export_markers[name]=e
# Remove the prefix only from exported nodes; preserve source names as saved above.
for o in exports:
 target=o.name.removeprefix('Export_');original=bpy.data.objects.get(target)
 if original is not None and original!=o:original.name='Source_'+target
 o.name=target
assert total<=50000,f'Whale has {total} triangles, exceeds 50k'
bpy.ops.object.select_all(action='DESELECT')
for o in exports:o.select_set(True)
bpy.context.view_layer.objects.active=export_root
glb=OUT/'siphon_whale.glb'
bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,export_apply=True,export_yup=True,export_materials='EXPORT',export_cameras=False,export_lights=False,export_extras=True,export_animations=False,export_normals=True,export_texcoords=True)
lo=[min(p[k] for p in bounds) for k in range(3)];hi=[max(p[k] for p in bounds) for k in range(3)]
report={'asset':'I1 siphon whale','version':1,'source_blend':str(SRC/'siphon_whale.blend'),'glb':str(glb),'sha256':hashlib.sha256(glb.read_bytes()).hexdigest(),'bytes':glb.stat().st_size,'triangles':total,'materials':6,'editable_source_meshes':len(parts),'blender':bpy.app.version_string,'bounds_godot':{'min':[lo[0],lo[2],-hi[1]],'max':[hi[0],hi[2],-lo[1]]},'groups':statistics,'hull_sections_z_rx_ry_center_y':HULL,'core_recess':{'z':[1.2,4.4],'angular_radians':[theta_a,theta_b],'floor_y':1.10,'note':'Do not seal with a convex hull. CoreGlow is inside a real opening.'},'motion':{'PortHatchPivot':{'axis_godot':[0,0,1],'degrees':-68},'StarboardHatchPivot':{'axis_godot':[0,0,1],'degrees':68},'CoreShield':{'translation_godot':[0,.30,-3.2]}},'markers_godot':{'CoreWeakpoint':list(core_pos),'PortWeakpoint':[-7,.65,0],'StarboardWeakpoint':[7,.65,0],'AttackOrigin':[0,-.20,6.9],'RetryEntry':[0,.5,11]},'render':'Cycles CPU2','scope':'asset only; engine collision and camera owned by root'}
report['version']=REV;report['markers_godot']=dict(MARKERS);report['markers_godot']['RawCommandRecordAnchor']=[0,3.05,3.1];report['raw_anchor_parent']='CoreWeakpoint';report['raw_anchor_local_godot']=[0,1.03,0]
(EVID/f'siphon_whale_build_v{REV}.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
exp.hide_render=True
print('WHALE_EXPORT '+json.dumps({k:v for k,v in report.items() if k!='groups'},ensure_ascii=False))
