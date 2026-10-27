"""Reopen editable blend and ray-check actual geometry. No Godot import."""
from pathlib import Path
import bpy,json,math
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[3];EVID=ROOT/'artifacts/v3/art/industrial_kit'
name=Path(bpy.data.filepath).stem
source=next(c for c in bpy.data.collections if c.name.startswith('Editable_'))
meshes=[o for o in source.objects if o.type=='MESH'];checks={}
checks['all_meshes_uv']=all(o.data.uv_layers for o in meshes)
paths=[bpy.path.abspath(im.filepath) for im in bpy.data.images if im.filepath and im.source=='FILE']
checks['all_linked_maps_exist']=all(Path(p).is_file() for p in paths)
checks['cpu_render']=bpy.context.scene.cycles.device=='CPU' and bpy.context.scene.render.threads==2
ray_results=[]
if name=='coastal_work_terrace':
    deps=bpy.context.evaluated_depsgraph_get()
    for i in range(16):
        z=4-(i+.5)*.275
        ok,loc,normal,face,obj,mat=bpy.context.scene.ray_cast(deps,Vector((-4.4,-z,5)),Vector((0,0,-1)),distance=6)
        expected=(i+1)*.25;passed=ok and abs(loc.z-expected)<.02
        ray_results.append({'type':'stair','index':i,'expected_height':expected,'actual':loc.z if ok else None,'object':obj.name if ok else None,'pass':passed})
    for x in [-2,0,2,4,5.5]:
        for z in [-3,-1,1,2.5]:
            ok,loc,normal,face,obj,mat=bpy.context.scene.ray_cast(deps,Vector((x,-z,5)),Vector((0,0,-1)),distance=6)
            ray_results.append({'type':'worktop','at':[x,z],'actual':loc.z if ok else None,'pass':ok and abs(loc.z-4)<.03})
    for x in [-2.99,1.01,4.01]:
        ok,loc,normal,face,obj,mat=bpy.context.scene.ray_cast(deps,Vector((x,-3.325,5)),Vector((0,0,-1)),distance=6)
        ray_results.append({'type':'drain_gap','at':[x,3.325],'actual':loc.z if ok else None,'pass':ok and loc.z<3.80})
    checks['stair_heights_real']=all(r['pass'] for r in ray_results if r['type']=='stair')
    checks['work_surface_real']=all(r['pass'] for r in ray_results if r['type']=='worktop')
    checks['drain_recess_real']=all(r['pass'] for r in ray_results if r['type']=='drain_gap')
else:
    checks['independent_switch_pivot']='SwitchPivot' in bpy.data.objects
    checks['independent_signal']='StatusLamp' in bpy.data.objects
    pivot=bpy.data.objects.get('SwitchPivot')
    checks['switch_has_moving_children']=pivot is not None and len(pivot.children)==2
    deps=bpy.context.evaluated_depsgraph_get();verts=[]
    for obj in meshes:
        evaluated=obj.evaluated_get(deps)
        verts.extend(evaluated.matrix_world@v.co for v in evaluated.data.vertices)
    low=[min(v[k] for v in verts) for k in range(3)];high=[max(v[k] for v in verts) for k in range(3)]
    checks['nominal_bounds']=all(abs(a-b)<.005 for a,b in zip(low+high,[-1,-.8,0,1,.8,2.8]))
report={'source_blend':bpy.data.filepath,'editable_meshes':len(meshes),'texture_paths':paths,'checks':checks,'all_checks_pass':all(checks.values()),'geometry_rays':ray_results,'blender':bpy.app.version_string,'scope':'source geometry only, not runtime collision or full performance'}
(EVID/(name+'_source_validation.json')).write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('KIT_SOURCE_VERIFY '+json.dumps({k:v for k,v in report.items() if k not in ['texture_paths','geometry_rays']},ensure_ascii=False))
if name=='power_relay_cabinet':
    # Separate offline state preview; do not save the changed authoring state.
    pivot.rotation_euler.x=math.radians(40)
    bpy.context.scene.render.filepath=str(EVID/'power_relay_cabinet_switch_on.png')
    bpy.ops.render.render(write_still=True)
if not report['all_checks_pass']:raise RuntimeError('Source geometry validation failed')
