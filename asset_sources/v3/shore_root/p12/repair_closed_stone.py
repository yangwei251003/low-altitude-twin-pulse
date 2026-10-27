"""Bounded volume repair of copied stone, retaining its original bridge strip."""
import bpy,bmesh,json
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from geometry_checks import strict_self_intersections
def bp(p):return Vector((p[0],-p[2],p[1]))
def tree(ob):
    ob.data.calc_loop_triangles()
    return BVHTree.FromPolygons([ob.matrix_world@v.co for v in ob.data.vertices],
        [tuple(t.vertices) for t in ob.data.loop_triangles],all_triangles=True)
def clip(ob,x,negative):
    bm=bmesh.new();bm.from_mesh(ob.data)
    cut=bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),
        plane_co=bp((x,0,0)),plane_no=bp((1,0,0)),dist=1e-6,
        clear_outer=negative,clear_inner=not negative)
    edges=[e for e in cut['geom_cut'] if isinstance(e,bmesh.types.BMEdge) and e.is_boundary]
    if edges:bmesh.ops.holes_fill(bm,edges=edges,sides=0)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(ob.data);bm.free()
def repair(ob,collection):
    stages=[]
    def audit(label,target):
        bm=bmesh.new();bm.from_mesh(target.data)
        row={'stage':label,'vertices':len(bm.verts),'boundary':sum(e.is_boundary for e in bm.edges),
             'nonmanifold':sum(not e.is_manifold for e in bm.edges),'volume':bm.calc_volume(signed=True)};bm.free()
        row['crossings']=strict_self_intersections(target,limit=5)
        stages.append(row)
        (Path(__file__).resolve().parent/'p12_repair_stages.json').write_text(json.dumps(stages,indent=2),encoding='utf-8')
        print('REPAIR_STAGE',label,row['boundary'],row['nonmanifold'],len(row['crossings']['strict_crossings']),flush=True)
    before=tree(ob);points=[ob.matrix_world@v.co for v in ob.data.vertices]
    strip=ob.copy();strip.data=ob.data.copy();collection.objects.link(strip)
    strip.name='P12_Protected_Original_JoinStrip'
    # One millimetre inside the original strip avoids retaining the old
    # zero-volume vertical wall exactly on the original step's x=3.5 plane.
    clip(strip,3.501,False);audit('original_join_strip_x3_501',strip)
    bpy.ops.object.select_all(action='DESELECT');ob.select_set(True);bpy.context.view_layer.objects.active=ob
    ob.data.remesh_voxel_size=.025;ob.data.remesh_voxel_adaptivity=0
    bpy.ops.object.voxel_remesh();audit('raw_voxel',ob)
    clip(ob,3.55,True);audit('voxel_core_clipped',ob)
    # Re-cut the tiny overlap to the exact existing top before union; a
    # discretized voxel corner must not add a 1--2cm lip at the bridge join.
    corners=[(x,y,z) for y in [4.5,8] for x,z in [(3.5,-9),(8,-9),(8,9),(3.5,9)]]
    mesh=bpy.data.meshes.new('P12_ExactJoinOverlapCutMesh')
    mesh.from_pydata([bp(p) for p in corners],[],[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]);mesh.update()
    cutter=bpy.data.objects.new('P12_ExactJoinOverlapCut',mesh);collection.objects.link(cutter)
    bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(mesh);bm.free()
    mod=ob.modifiers.new('ExactJoinOverlapHeight','BOOLEAN');mod.operation='DIFFERENCE';mod.solver='EXACT';mod.object=cutter
    bpy.ops.object.modifier_apply(modifier=mod.name);bpy.data.objects.remove(cutter,do_unlink=True)
    audit('voxel_overlap_exact_height',ob)
    mod=ob.modifiers.new('Rejoin_Unchanged_LastMetre','BOOLEAN');mod.operation='UNION';mod.solver='EXACT';mod.object=strip
    bpy.ops.object.modifier_apply(modifier=mod.name)
    audit('union_before_cleanup',ob)
    bpy.data.objects.remove(strip,do_unlink=True)
    bm=bmesh.new();bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-6)
    bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=1e-7)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(ob.data);bm.free()
    audit('union_after_cleanup',ob)
    after=tree(ob)
    distances=[after.find_nearest(p)[3] for p in points]
    worst=max(range(len(points)),key=lambda i:distances[i]);forward=distances[worst]
    reverse=max(before.find_nearest(ob.matrix_world@v.co)[3] for v in ob.data.vertices)
    p=points[worst];q=after.find_nearest(p)[0]
    return {'method':'2.5cm voxel repair of copied original shape, exact union with unchanged original x>=3.501 join strip',
            'stages':stages,
            'source_vertex_to_repaired_surface_max_m':forward,
            'worst_source_vertex':worst,'worst_source_point_godot':[p.x,p.z,-p.y],
            'nearest_repaired_point_godot':[q.x,q.z,-q.y],
            'repaired_vertex_to_source_surface_max_m':reverse,
            'sampled_error_under_4cm':max(forward,reverse)<.04,
            'not_analytic_hausdorff_bound':True}
