"""Only six measured shells, eleven healthy tips and one old-defect cavity.

No rendering, PBR or export. Immutable unfiltered bytes and source are checked.
"""
import bpy,bmesh,json,hashlib,math,sys
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree
OUT=Path(__file__).resolve().parent;sys.path.insert(0,str(OUT))
from geometry_checks import strict_self_intersections
SOURCE=OUT.parent/'p10/root_shoulder_contact_p10.blend';RAW=OUT/'plain_voxel_unfiltered.blend'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
meta=json.loads((OUT/'plain_voxel_diagnosis.json').read_text())
assert sha(SOURCE)==meta['source_sha256'] and sha(RAW)==meta['unfiltered_blend_sha256']
assert len(meta['small_components'])==6 and len(meta['points_exceeding_authorized_local_repair_rule'])==11
bpy.ops.wm.open_mainfile(filepath=str(RAW))
ob=bpy.data.objects['P10_HighShoulder_ContinuousThickCliff'];ob.data=ob.data.copy()
with bpy.data.libraries.load(str(SOURCE),link=False) as (available,data):
    data.objects=['P10_HighShoulder_ContinuousThickCliff']
original=data.objects[0]
def gp(p):return [p.x,p.z,-p.y]
def bp(p):return Vector((p[0],-p[2],p[1]))
def tree(target):
    target.data.calc_loop_triangles()
    return BVHTree.FromPolygons([target.matrix_world@v.co for v in target.data.vertices],
        [tuple(t.vertices) for t in target.data.loop_triangles],all_triangles=True)
old_tree=tree(original);old_points=[original.matrix_world@v.co for v in original.data.vertices]
old_triangles=[tuple(t.vertices) for t in original.data.loop_triangles]
bad_tree=BVHTree.FromPolygons(old_points,[old_triangles[i] for i in meta['old_self_intersecting_triangle_ids']],all_triangles=True)
removal=[];bm=bmesh.new();bm.from_mesh(ob.data);bm.verts.ensure_lookup_table()
for row in meta['small_components']:
    assert row['source_component_count']==1 and not row['intersects_protected_join_zone']
    assert row['distance_to_root_cap_min_m']>3 and row['nearest_old_self_intersection_max_m']<.02
    ids=row['vertices'];members={bm.verts[i] for i in ids}
    assert len(ids)==row['vertex_count'] and all(e.other_vert(v) in members for v in members for e in v.link_edges)
    points=[gp(ob.matrix_world@v.co) for v in members]
    bounds={'min':[min(p[i] for p in points) for i in range(3)],'max':[max(p[i] for p in points) for i in range(3)]}
    assert max(abs(bounds[k][i]-row['bounds_godot'][k][i]) for k in bounds for i in range(3))<1e-6
    removal.append(dict(row))
indices={i for row in removal for i in row['vertices']}
bmesh.ops.delete(bm,geom=[bm.verts[i] for i in sorted(indices)],context='VERTS')
bm.to_mesh(ob.data);bm.free()
new_tree=tree(ob);positions=[ob.matrix_world@v.co for v in ob.data.vertices]
kd=KDTree(len(positions))
for i,p in enumerate(positions):kd.insert(p,i)
kd.balance();patches=[];proposals={}
for row in meta['points_exceeding_authorized_local_repair_rule']:
    assert row['distance_to_old_crossing_triangle_m']>.02 and .04<row['error_m']<.06
    index=row['source_vertex'];p=old_points[index];q,_,_,distance=new_tree.find_nearest(p)
    assert (p-bp(row['point_godot'])).length<1e-6 and distance<.065
    delta=(p-q).normalized()*max(0,distance-.027)
    assert delta.length<.04
    affected=[]
    for location,vertex_id,dist in kd.find_range(q,.15):
        weight=(1-dist/.15)**2
        proposals.setdefault(vertex_id,[]).append((delta,weight))
        affected.append(vertex_id)
    patches.append({'source_vertex':index,'source_point_godot':gp(p),'old_nearest_new_surface_godot':gp(q),
                    'old_error_m':distance,'intended_offset_godot':gp(delta),'radius_m':.15,'affected_vertices':len(affected)})
inv=ob.matrix_world.inverted();moves=[]
for index,items in proposals.items():
    total=sum(w for d,w in items)
    displacement=sum((d*w for d,w in items),Vector())/max(1.,total)
    p=positions[index];amount=1.
    while amount>.001 and old_tree.find_nearest(p+displacement*amount)[3]>.039:
        amount*=.5
    displacement*=amount
    # All eleven patches are far from the engineering plane and root base.
    assert not (p.x>3.35 and p.z>4.35 and abs(p.y)<2.9)
    assert displacement.length<.04
    ob.data.vertices[index].co=inv@(p+displacement)
    moves.append({'vertex':index,'before_godot':gp(p),'after_godot':gp(p+displacement),'distance_m':displacement.length})
ob.data.update()
# Shell removal exposed one known bad-source cavity. Restore only a small
# continuous portion of the main surface; never recreate its detached shell.
temporary=tree(ob);cavity_id=8703;p=old_points[cavity_id]
assert (p-bp((-.0602379106,3.5069487095,-.9662302732))).length<1e-6
assert bad_tree.find_nearest(p)[3]<1e-6
q,_,_,distance=temporary.find_nearest(p)
assert .06<distance<.07
delta=(p-q).normalized()*(distance-.049)
cavity_affected=[]
for vertex in ob.data.vertices:
    current=ob.matrix_world@vertex.co;dist=(current-q).length
    if dist>=.15:continue
    weight=(1-dist/.15)**2;displacement=delta*weight;amount=1.
    while amount>.001 and old_tree.find_nearest(current+displacement*amount)[3]>.039:
        amount*=.5
    displacement*=amount
    vertex.co=inv@(current+displacement);cavity_affected.append(vertex.index)
patches.append({'source_vertex':cavity_id,'source_point_godot':gp(p),'old_nearest_new_surface_godot':gp(q),
                'old_error_m':distance,'intended_offset_godot':gp(delta),'radius_m':.15,
                'affected_vertices':len(cavity_affected),'reason':'known old self-intersection cavity after removal of listed shell',
                'permitted_error_m':.06})
changed=set(proposals)|set(cavity_affected)
moves=[]
for index in sorted(changed):
    p=positions[index];q=ob.matrix_world@ob.data.vertices[index].co
    assert (p-q).length<.04
    moves.append({'vertex':index,'before_godot':gp(p),'after_godot':gp(q),'distance_m':(p-q).length})
ob.data.update();after=tree(ob)
forward=[after.find_nearest(p)[3] for p in old_points]
reverse=max(old_tree.find_nearest(ob.matrix_world@v.co)[3] for v in ob.data.vertices)
violations=[];exceptions=[]
for i,distance in enumerate(forward):
    if distance<=.04:continue
    p=old_points[i];near_bad=bad_tree.find_nearest(p)[3]
    row={'source_vertex':i,'point_godot':gp(p),'error_m':distance,'distance_to_old_crossing_triangle_m':near_bad}
    exceptions.append(row)
    if near_bad>.02 or distance>.06:violations.append(row)
for patch in patches:
    patch['repaired_error_m']=forward[patch['source_vertex']]
bm=bmesh.new();bm.from_mesh(ob.data);pending=set(bm.verts);components=[]
while pending:
    stack=[pending.pop()];n=0
    while stack:
        v=stack.pop();n+=1
        for edge in v.link_edges:
            q=edge.other_vert(v)
            if q in pending:pending.remove(q);stack.append(q)
    components.append(n)
topology={'components':components,'boundary':sum(e.is_boundary for e in bm.edges),
          'nonmanifold':sum(not e.is_manifold for e in bm.edges),'signed_volume':bm.calc_volume(signed=True)};bm.free()
crossings=strict_self_intersections(ob)
result={'stage':'measured source topology repair only, no upper-edge redesign or asset acceptance',
        'source_sha256':sha(SOURCE),'unfiltered_blend_sha256':sha(RAW),
        'removed_shells':removal,'removed_vertex_count':len(indices),'patches':patches,
        'changed_vertex_count':len(moves),'max_vertex_displacement_m':max(m['distance_m'] for m in moves),
        'source_to_repaired_sampled_max_m':max(forward),'repaired_to_source_sampled_max_m':reverse,
        'authorized_bad_source_exceptions':exceptions,'violations':violations,
        'topology':topology,'crossings':crossings,'not_analytic_hausdorff_bound':True}
result['all_pass']=not violations and reverse<.04 and len(components)==1 and topology['boundary']==0 and topology['nonmanifold']==0 and not crossings['strict_crossings']
(OUT/'measured_surface_displacements.json').write_text(json.dumps(moves,indent=2),encoding='utf-8')
(OUT/'measured_surface_repair.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
assert sha(SOURCE)==meta['source_sha256'] and sha(RAW)==meta['unfiltered_blend_sha256']
if result['all_pass']:
    bpy.data.objects.remove(original,do_unlink=True)
    target=OUT/'measured_surface_repair.blend';bpy.ops.wm.save_as_mainfile(filepath=str(target))
    result['repaired_blend_sha256']=sha(target)
    (OUT/'measured_surface_repair.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print('MEASURED_SURFACE_REPAIR',json.dumps({k:v for k,v in result.items() if k not in ['removed_shells','patches','authorized_bad_source_exceptions','violations']}),flush=True)
if violations:print('REMAINING_RULE_VIOLATIONS',json.dumps(violations),flush=True)
