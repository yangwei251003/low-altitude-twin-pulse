"""Read-only source/identity-delivery normal diagnosis, no mapping or save."""
import sys,os,json,time,math
from pathlib import Path
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parent))
from prepare import *

start=time.monotonic();assert sha(SOURCE)==SOURCE_SHA
bpy.ops.wm.open_mainfile(filepath=str(SOURCE));bpy.context.view_layer.update()
records=[];invalid=[]
for obj in sorted([o for o in bpy.data.objects if o.get('closure_export_surface')],key=lambda o:o.name):
    dg=bpy.context.evaluated_depsgraph_get()
    source=bpy.data.meshes.new_from_object(obj.evaluated_get(dg),preserve_all_data_layers=True,depsgraph=dg);source.calc_loop_triangles()
    transform=obj.matrix_world.to_3x3().inverted().transposed();positions=[];normals=[];origins=[]
    for tri in source.loop_triangles:
        local=[tuple(source.vertices[i].co) for i in tri.vertices]
        world=[tuple(obj.matrix_world@source.vertices[i].co) for i in tri.vertices]
        for vi,li,p in zip(tri.vertices,tri.loops,world):
            original=tuple(source.corner_normals[li].vector);n=tuple((transform@source.corner_normals[li].vector).normalized())
            positions.append(p);normals.append(n);origins.append({'object':obj.name,'source_triangle':tri.index,'source_polygon':tri.polygon_index,
                'source_loop':li,'local_points':local,'world_points':world,'local_area_m2':area(local),'world_double_area_m2':area(world),
                'source_corner_normal':original,'expected_world_normal':n})
    copy=bpy.data.meshes.new('DiagnosticOnly');copy.from_pydata(positions,[],[(i,i+1,i+2) for i in range(0,len(positions),3)]);copy.update()
    for p in copy.polygons:p.use_smooth=True
    copy.normals_split_custom_set(normals)
    count=0;max_angle=0.
    for i,n in enumerate(normals):
        actual=tuple(copy.corner_normals[i].vector)
        if norm(n)==0 or norm(actual)==0:
            record=dict(origins[i],delivery_corner=i,actual_normal=actual,source_length=norm(n),actual_length=norm(actual))
            invalid.append(record);count+=1
            dump(HERE/'zero_normal_diagnostic.json',{'status':'READ_ONLY_RUNNING','pid':os.getpid(),'invalid':invalid})
        else:max_angle=max(max_angle,normal_difference(n,actual)['degrees'])
    records.append({'object':obj.name,'triangles':len(source.loop_triangles),'invalid_corners':count,'max_nonzero_angle':max_angle})
    bpy.data.meshes.remove(copy);bpy.data.meshes.remove(source)
assert sha(SOURCE)==SOURCE_SHA
report={'status':'READ_ONLY_COMPLETE','pid':os.getpid(),'source_sha256':SOURCE_SHA,'source_unchanged':True,
    'seconds':time.monotonic()-start,'objects':records,'invalid':invalid,'invalid_count':len(invalid),
    'limits':'Identity delivery geometry diagnosis only; no source rewrite, mapping, bake or export.'}
dump(HERE/'zero_normal_diagnostic.json',report)
print(json.dumps({'stage':'normal_diagnostic_exit','pid':os.getpid(),'invalid_count':len(invalid),'seconds':report['seconds']}),flush=True)
