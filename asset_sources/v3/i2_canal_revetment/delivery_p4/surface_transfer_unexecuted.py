"""Delivery-only <=1 micrometre cleanup of measured bevel slivers, never P4."""
import bmesh, json, math
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from common import *

LIMIT=1e-6

def body_stats(me):
    bm=bmesh.new();bm.from_mesh(me)
    result={'vertices':len(bm.verts),'edges':len(bm.edges),'polygons':len(bm.faces),
        'nonmanifold_edges':sum(not e.is_manifold for e in bm.edges),'volume':bm.calc_volume(signed=True)}
    bm.free();me.calc_loop_triangles();result['triangles']=len(me.loop_triangles)
    result['volume_same_loop_triangle_rule']=sum(me.vertices[t.vertices[0]].co.dot(me.vertices[t.vertices[1]].co.cross(me.vertices[t.vertices[2]].co))/6. for t in me.loop_triangles)
    points=[gp(v.co) for v in me.vertices]
    result['bounds']={'min':[min(v[i] for v in points) for i in range(3)],'max':[max(v[i] for v in points) for i in range(3)]}
    return result

def cleanup_body(parts):
    obj=next(o for o in parts if o.name=='ConcreteBody_4m_Closed')
    assert obj.matrix_world==Matrix.Identity(4)
    dg=bpy.context.evaluated_depsgraph_get()
    me=bpy.data.meshes.new_from_object(obj.evaluated_get(dg),preserve_all_data_layers=True,depsgraph=dg)
    me.calc_loop_triangles();old_triangles=list(me.loop_triangles)
    old_points=[v.co.copy() for v in me.vertices]
    source=[]
    for tri in old_triangles:
        source.append({'ids':tuple(tri.vertices),'p':[old_points[i].copy() for i in tri.vertices],
            'n':[me.corner_normals[i].vector.copy() for i in tri.loops],'area':tri.area,
            'material':me.polygons[tri.polygon_index].material_index,
            'uv':{n:[tuple(me.uv_layers[n].data[i].uv) for i in tri.loops] for n in UVS},
            'attrs':{n:[me.attributes[n].data[i].value for i in tri.loops] for n in ATTRS}})
    diagnosis=json.loads((OUT/'uv_diagnostic_01/diagnostic.json').read_text(encoding='utf-8'))
    ids={r['index'] for r in diagnosis['bad_triangles']}
    assert len(ids)==129 and len(old_triangles)==3284
    for r in diagnosis['bad_triangles']:
        assert r['source_piece']==obj.name and tuple(r['vertices'])==source[r['index']]['ids']
    before=body_stats(me)
    # Explicit triangles retain source face IDs and every corner UV/attribute.
    mesh=bpy.data.meshes.new('ConcreteBody_DeliveryLocalMicroCleanup')
    mesh.from_pydata(old_points,[],[r['ids'] for r in source]);mesh.update()
    for m in me.materials:mesh.materials.append(m)
    for p,r in zip(mesh.polygons,source):p.material_index=r['material']
    for name in UVS:
        mesh.uv_layers.new(name=name)
        for p,r in zip(mesh.polygons,source):
            for li,v in zip(p.loop_indices,r['uv'][name]):mesh.uv_layers[name].data[li].uv=v
    for name in ATTRS:
        mesh.attributes.new(name=name,type='FLOAT',domain='CORNER')
        for p,r in zip(mesh.polygons,source):
            for li,v in zip(p.loop_indices,r['attrs'][name]):mesh.attributes[name].data[li].value=v
    mesh.attributes.new(name='DeliveryOriginalTriangle',type='INT',domain='FACE')
    for i,v in enumerate(mesh.attributes['DeliveryOriginalTriangle'].data):v.value=i
    bm=bmesh.new();bm.from_mesh(mesh);bm.verts.ensure_lookup_table();bm.faces.ensure_lookup_table()
    affected_verts={v for i in ids for v in bm.faces[i].verts}
    affected_edges={e for i in ids for e in bm.faces[i].edges}
    bmesh.ops.remove_doubles(bm,verts=sorted(affected_verts,key=lambda v:v.index),dist=LIMIT)
    bmesh.ops.dissolve_degenerate(bm,edges=sorted([e for e in affected_edges if e.is_valid],key=lambda e:e.index),dist=LIMIT)
    bmesh.ops.triangulate(bm,faces=list(bm.faces))
    bm.to_mesh(mesh);bm.free();mesh.update()
    after=body_stats(mesh)
    old_bvh=BVHTree.FromPolygons(old_points,[r['ids'] for r in source],all_triangles=True)
    mapping=[];normals=[];max_vertex_deviation=0.;max_uv_delta=0.;retained=set();interpolated=0
    for poly in mesh.polygons:
        inherited=mesh.attributes['DeliveryOriginalTriangle'].data[poly.index].value
        center=sum((mesh.vertices[v].co for v in poly.vertices),Vector())/len(poly.vertices)
        hit=old_bvh.find_nearest(center);assert hit[3]<=LIMIT
        original=hit[2];retained.add(original);poly.use_smooth=True
        mapped_corners=[]
        for li in poly.loop_indices:
            p=mesh.vertices[mesh.loops[li].vertex_index].co
            candidates=old_bvh.find_nearest_range(p,LIMIT)
            candidates=[h for h in candidates if source[h[2]]['material']==poly.material_index and source[h[2]]['area']>1e-9]
            assert candidates,(poly.index,li,list(p))
            chosen=max(candidates,key=lambda h:(h[1].dot(poly.normal),-h[3],-h[2]))
            r=source[chosen[2]];distance=chosen[3]
            max_vertex_deviation=max(max_vertex_deviation,distance)
            assert distance<=LIMIT,(original,poly.index,distance)
            j=min(range(3),key=lambda j:(p-r['p'][j]).length)
            if (p-r['p'][j]).length<=LIMIT:
                weights=[float(k==j) for k in range(3)]
            else:
                a,b,c=r['p'];v0=b-a;v1=c-a;v2=chosen[0]-a
                aa=v0.dot(v0);ab=v0.dot(v1);bb=v1.dot(v1);ac=v0.dot(v2);bc=v1.dot(v2)
                den=aa*bb-ab*ab;assert abs(den)>1e-20
                v=(bb*ac-ab*bc)/den;w=(aa*bc-ab*ac)/den;weights=[1-v-w,v,w];interpolated+=1
            normals.append(tuple(sum((r['n'][k]*weights[k] for k in range(3)),Vector()).normalized()))
            for name in UVS:
                value=tuple(sum(r['uv'][name][k][axis]*weights[k] for k in range(3)) for axis in range(2))
                old=tuple(mesh.uv_layers[name].data[li].uv)
                mesh.uv_layers[name].data[li].uv=value
                max_uv_delta=max(max_uv_delta,max(abs(a-b) for a,b in zip(old,value)))
            for name in ATTRS:mesh.attributes[name].data[li].value=sum(r['attrs'][name][k]*weights[k] for k in range(3))
            mapped_corners.append({'source_triangle':chosen[2],'weights':weights,'distance_m':distance})
        mapping.append({'new_triangle':poly.index,'source_surface_at_centroid':original,'inherited_id_not_authoritative':inherited,'corner_mapping':mapped_corners})
    removed=sorted(set(range(len(source)))-retained)
    assert before['nonmanifold_edges']==after['nonmanifold_edges']==0
    assert before['volume']>0 and after['volume']>0
    assert abs(before['volume_same_loop_triangle_rule']-after['volume_same_loop_triangle_rule'])<1e-6
    assert max(abs(before['bounds'][k][i]-after['bounds'][k][i]) for k in ['min','max'] for i in range(3))<=LIMIT
    mesh.normals_split_custom_set(normals)
    new_bvh=BVHTree.FromPolygons([v.co for v in mesh.vertices],[tuple(p.vertices) for p in mesh.polygons],all_triangles=True)
    symmetric=[]
    for label,points,faces,target in [('old_to_new',old_points,[r['ids'] for r in source],new_bvh),('new_to_old',[v.co.copy() for v in mesh.vertices],[tuple(p.vertices) for p in mesh.polygons],old_bvh)]:
        maximum=0.
        for face in faces:
            a,b,c=[points[i] for i in face]
            for p in (a,b,c,(a+b)*.5,(b+c)*.5,(c+a)*.5,(a+b+c)/3):
                h=target.find_nearest(p);assert h[0] is not None
                maximum=max(maximum,h[3])
        assert maximum<=LIMIT,(label,maximum)
        symmetric.append({'direction':label,'max_distance_m':maximum,'samples':'every triangle vertex, edge midpoint and centroid'})
    samples=[]
    # Seams front/top, waterline, repair, exterior bounds. Both true meshes ray-read.
    for x in [-1.10,-1.09,-1.08,.78,.79,.80,-1.5,0.,1.5]:
        for y in [-.07,-1.2,-2.7]:samples.append((Vector((x,-1,y)),Vector((0,1,0)),f'front {x}/{y}'))
        for depth in [.03,.17,.32]:samples.append((Vector((x,depth,1)),Vector((0,0,-1)),f'top {x}/{depth}'))
    rays=[]
    for origin,direction,label in samples:
        a=old_bvh.ray_cast(origin,direction,5);b=new_bvh.ray_cast(origin,direction,5)
        assert (a[0] is None)==(b[0] is None),label
        error=0. if a[0] is None else (a[0]-b[0]).length
        assert error<=LIMIT,(label,error)
        rays.append({'label':label,'difference_m':error})
    obj.modifiers.clear();obj.data=mesh
    report={'scope':'Only delivery ConcreteBody evaluated copy; frozen P4 and other seven pieces untouched',
        'tolerance_m':LIMIT,'target_original_triangles':sorted(ids),'before':before,'after':after,
        'source_triangles_without_new_centroid_mapping':[{'id':i,'area':source[i]['area']} for i in removed],
        'retained_triangle_mapping':mapping,'maximum_vertex_displacement_m':max_vertex_deviation,
        'maximum_corner_uv_change_from_bmesh_inherited_values':max_uv_delta,'interpolated_corners':interpolated,
        'uv_transfer':'actual source surface barycentric corner data; inherited triangle IDs are diagnostic only',
        'symmetric_surface_sample_distances':symmetric,'ray_differences':rays,
        'maximum_ray_displacement_m':max(r['difference_m'] for r in rays),
        'source_sha256':sha(SOURCE),'original_bevel_applied_in_delivery_copy_only':True}
    write_json(OUT/'local_cleanup_report.json',report)
    bpy.data.meshes.remove(me)
    return report
