"""Explicit representative map, keeping source triangle corner data. No dissolve."""
from common import *
from mathutils.bvhtree import BVHTree
import collections
from surface_distance import nearest
LIMIT=1e-6

def bounds(points):return {'min':[min(p[i] for p in points) for i in range(3)],'max':[max(p[i] for p in points) for i in range(3)]}
def edge_counts(rows):
    d=collections.defaultdict(list)
    for i,r in enumerate(rows):
        for j in range(3):
            a,b=r['ids'][j],r['ids'][(j+1)%3];d[tuple(sorted((a,b)))].append((i,a,b))
    return d
def volume(points,rows):return sum(points[r['ids'][0]].dot(points[r['ids'][1]].cross(points[r['ids'][2]]))/6 for r in rows)

def cleanup_body(parts):
    obj=next(o for o in parts if o.name=='ConcreteBody_4m_Closed');assert obj.matrix_world==Matrix.Identity(4)
    dg=bpy.context.evaluated_depsgraph_get();me=bpy.data.meshes.new_from_object(obj.evaluated_get(dg),preserve_all_data_layers=True,depsgraph=dg)
    me.calc_loop_triangles();points=[v.co.copy() for v in me.vertices];source=[]
    for i,tri in enumerate(me.loop_triangles):
        source.append({'original':i,'ids':list(tri.vertices),'n':[tuple(me.corner_normals[li].vector) for li in tri.loops],
            'material':me.polygons[tri.polygon_index].material_index,
            'uv':{n:[tuple(me.uv_layers[n].data[li].uv) for li in tri.loops] for n in UVS},
            'attrs':{n:[me.attributes[n].data[li].value for li in tri.loops] for n in ATTRS}})
    diag=json.loads((OUT/'uv_diagnostic_01/diagnostic.json').read_text(encoding='utf-8'));target={r['index'] for r in diag['bad_triangles']}
    assert len(target)==129 and len(source)==3284
    for r in diag['bad_triangles']:assert list(r['vertices'])==source[r['index']]['ids']
    additional=json.loads((OUT/'additional_local_microfaces.json').read_text(encoding='utf-8'))
    assert additional['source_sha256']==SOURCE_SHA
    target.update(r['original_triangle'] for r in additional['triangles'])
    assert len(target)==132
    selected_set={v for i in target for v in source[i]['ids']};local_expansion=[]
    # Stabilize the connected micro-sliver neighborhood, never general decimation.
    while True:
        added=set();new_faces=[]
        for r in source:
            if not any(v in selected_set for v in r['ids']):continue
            a,b,c=[points[i] for i in r['ids']];longest=max((a-b).length,(b-c).length,(c-a).length)
            if (b-a).cross(c-a).length<=LIMIT*longest:
                added.update(set(r['ids'])-selected_set)
                if r['original'] not in target:new_faces.append(r['original'])
                target.add(r['original'])
        if not added:break
        local_expansion.append({'new_vertices':sorted(added),'new_micro_triangles':new_faces,'criterion':'adjacent and altitude <=1 micrometre'})
        selected_set.update(added)
    selected=sorted(selected_set);parent={i:i for i in selected}
    def find(i):
        while parent[i]!=i:parent[i]=parent[parent[i]];i=parent[i]
        return i
    for k,a in enumerate(selected):
        for b in selected[k+1:]:
            if (points[a]-points[b]).length<=LIMIT:
                x,y=find(a),find(b);parent[max(x,y)]=min(x,y)
    representative={i:find(i) for i in selected}
    maxmove=max((points[i]-points[j]).length for i,j in representative.items());assert maxmove<=LIMIT
    rows=[];removed=[]
    for r in source:
        ids=[representative.get(i,i) for i in r['ids']];a,b,c=[points[i] for i in ids]
        area=(b-a).cross(c-a).length*.5;longest=max((a-b).length,(b-c).length,(c-a).length)
        if len(set(ids))<3 or ((r['original'] in target or any(v in selected_set for v in r['ids'])) and 2*area<=LIMIT*longest):
            removed.append({'original_triangle':r['original'],'reason':'repeated representative vertex' if len(set(ids))<3 else 'measured near-collinear sliver','area_after_mapping':area});continue
        row=dict(r);row['ids']=ids;rows.append(row)
    # Only subdivide an exposed collinear edge using its existing middle vertex.
    # The original source edge supplies its own interpolated corner data.
    splits=[]
    for iteration in range(16):
        edges=edge_counts(rows);boundary={e:owners for e,owners in edges.items() if len(owners)==1}
        if not boundary:break
        boundary_vertices=sorted({i for e in boundary for i in e});choice=None
        for edge,owners in sorted(boundary.items()):
            a,b=edge;ab=points[b]-points[a]
            if ab.length<=LIMIT:continue
            candidates=[]
            for v in boundary_vertices:
                if v in edge:continue
                t=(points[v]-points[a]).dot(ab)/ab.length_squared
                if t<=1e-7 or t>=1-1e-7:continue
                deviation=(points[v]-(points[a]+ab*t)).length
                if deviation<=LIMIT:candidates.append((t,v,deviation))
            if candidates:choice=(owners[0],min(candidates));break
        if choice is None:break
        (index,a,b),(unused_t,v,deviation)=choice;r=rows[index];j=r['ids'].index(a);assert r['ids'][(j+1)%3]==b
        k=(j+1)%3;l=(j+2)%3;c=r['ids'][l]
        t=(points[v]-points[a]).dot(points[b]-points[a])/(points[b]-points[a]).length_squared
        norm=tuple((Vector(r['n'][j])*(1-t)+Vector(r['n'][k])*t).normalized())
        mid={'n':norm,'uv':{n:tuple(r['uv'][n][j][q]*(1-t)+r['uv'][n][k][q]*t for q in range(2)) for n in UVS},
             'attrs':{n:r['attrs'][n][j]*(1-t)+r['attrs'][n][k]*t for n in ATTRS}}
        def sub(ids,order):
            return {'original':r['original'],'ids':ids,'material':r['material'],
                'n':[mid['n'] if q is None else r['n'][q] for q in order],
                'uv':{n:[mid['uv'][n] if q is None else r['uv'][n][q] for q in order] for n in UVS},
                'attrs':{n:[mid['attrs'][n] if q is None else r['attrs'][n][q] for q in order] for n in ATTRS}}
        rows[index:index+1]=[sub([a,v,c],[j,None,l]),sub([v,b,c],[None,k,l])]
        splits.append({'source_triangle':r['original'],'edge':[a,b],'existing_midpoint':v,'edge_fraction':t,'deviation_m':deviation})
    edges=edge_counts(rows);bad={str(e):owners for e,owners in edges.items() if len(owners)!=2 or owners[0][1:]==owners[1][1:]}
    report={'scope':'delivery copy only; frozen P4 unchanged','method':'explicit representative map plus identified collinear edge subdivision; no bmesh dissolve',
        'limit_m':LIMIT,'affected_source_piece':obj.name,'target_original_triangles':sorted(target),'connected_micro_expansion':local_expansion,
        'original_triangles':len(source),'clean_triangles':len(rows),'maximum_vertex_displacement_m':maxmove,
        'representatives':[{'original_vertex':i,'representative':j,'distance_m':(points[i]-points[j]).length} for i,j in representative.items() if i!=j],
        'removed_original_triangles':removed,'collinear_shared_edge_splits':splits,'bad_edges':bad,
        'new_to_original_triangles':[r['original'] for r in rows],'source_corner_data':'original tuple copies; only inserted existing edge points interpolate their actual source edge'}
    write_json(OUT/'local_cleanup_report.json',report)
    assert not bad,('local cleanup not closed',len(bad))
    old_bvh=BVHTree.FromPolygons(points,[r['ids'] for r in source],all_triangles=True)
    new_bvh=BVHTree.FromPolygons(points,[r['ids'] for r in rows],all_triangles=True)
    distances=[];new_by_original=collections.defaultdict(list)
    for i,r in enumerate(rows):new_by_original[r['original']].append(i)
    for label,collection,target_bvh in [('old_to_new',source,new_bvh),('new_to_old',rows,old_bvh)]:
        target_rows=rows if label=='old_to_new' else source
        target_geometry=[[[float(x) for x in points[i]] for i in r['ids']] for r in target_rows]
        maximum=0.;worst=None;bvh_maximum=0.;bvh_worst=None
        for row_index,r in enumerate(collection):
            a,b,c=[points[i] for i in r['ids']]
            ids=new_by_original.get(r['original'],[]) if label=='old_to_new' else [r['original']]
            if not ids:ids=list(range(len(target_rows)))
            geometry=[target_geometry[i] for i in ids]
            # Use double precision samples, not Vector float32 midpoint rounding.
            points64=[[float(v) for v in p] for p in (a,b,c)]
            samples=points64+[[sum(points64[j][q] for j in pair)/len(pair) for q in range(3)] for pair in [(0,1),(1,2),(2,0),(0,1,2)]]
            for p in samples:
                distance,index=nearest(p,geometry)
                if distance>maximum:
                    maximum=distance;worst={'source_triangle':row_index,'sample':p,'target_triangle':ids[index],
                        'target_vertices':geometry[index],'source_vertices':points64}
                hit=target_bvh.find_nearest(Vector(p))
                if hit[3]>bvh_maximum:bvh_maximum=hit[3];bvh_worst={'source_triangle':row_index,'sample':p,'target_triangle':hit[2]}
        distances.append({'direction':label,'maximum_sample_distance_m':maximum,'worst':worst,
            'blender_bvh_comparison_only_maximum':bvh_maximum,'blender_bvh_worst':bvh_worst})
        report['symmetric_surface_samples']=distances;write_json(OUT/'local_cleanup_report.json',report)
        assert maximum<=LIMIT,(label,maximum,worst)
    rays=[]
    for x in [-1.10,-1.09,-1.08,.78,.79,.80,-1.5,0.,1.5]:
        probes=[(Vector((x,-1,y)),Vector((0,1,0)),f'front {x}/{y}') for y in [-.07,-1.2,-2.7]]
        probes.extend((Vector((x,d,1)),Vector((0,0,-1)),f'top {x}/{d}') for d in [.03,.17,.32])
        for origin,direction,label in probes:
            a=old_bvh.ray_cast(origin,direction,5);b=new_bvh.ray_cast(origin,direction,5)
            assert (a[0] is None)==(b[0] is None),label
            error=0. if a[0] is None else (a[0]-b[0]).length;assert error<=LIMIT,(label,error)
            rays.append({'label':label,'difference_m':error})
    b0=bounds([gp(p) for p in points]);b1=bounds([gp(points[i]) for r in rows for i in r['ids']]);assert b0==b1
    v0=volume(points,source);v1=volume(points,rows);assert v0>0 and v1>0 and abs(v0-v1)<1e-6
    used=sorted({i for r in rows for i in r['ids']});compact={v:i for i,v in enumerate(used)}
    mesh=bpy.data.meshes.new('ConcreteBody_DeliveryExplicitMicroWeld');mesh.from_pydata([points[i] for i in used],[],[[compact[i] for i in r['ids']] for r in rows]);mesh.update()
    for m in me.materials:mesh.materials.append(m)
    for p,r in zip(mesh.polygons,rows):p.material_index=r['material'];p.use_smooth=True
    mesh.normals_split_custom_set([n for r in rows for n in r['n']])
    for name in UVS:
        mesh.uv_layers.new(name=name)
        for p,r in zip(mesh.polygons,rows):
            for li,v in zip(p.loop_indices,r['uv'][name]):mesh.uv_layers[name].data[li].uv=v
    for name in ATTRS:
        mesh.attributes.new(name=name,type='FLOAT',domain='CORNER')
        for p,r in zip(mesh.polygons,rows):
            for li,v in zip(p.loop_indices,r['attrs'][name]):mesh.attributes[name].data[li].value=v
    obj.modifiers.clear();obj.data=mesh
    report.update(symmetric_surface_samples=distances,bounds_before=b0,bounds_after=b1,volume_before=v0,volume_after=v1,
        ray_differences=rays,maximum_ray_difference_m=max(r['difference_m'] for r in rays),closed=True)
    write_json(OUT/'local_cleanup_report.json',report);bpy.data.meshes.remove(me);return report
