"""Candidate only: subtract proven concrete coverage from the left soil wall.

The old scene and maps stay immutable. No top displacement, material revision,
AO/Normal bake, rendering or export. New loops interpolate their original face.
"""
from pathlib import Path
import sys, time, os, json, collections, hashlib
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parent))
import bpy
import numpy as np
from mathutils import Vector
import common as C
import planar_clip as P


def weights_point(weights, data, tid):
    return np.asarray(weights,np.float64) @ data['tri'][tid]


def edge_info(weights, ids):
    z=[i for i,x in enumerate(weights) if abs(x)<1e-10]
    if len(z)!=1:return None
    a,b=[i for i in range(3) if i!=z[0]]
    if ids[a]>ids[b]:a,b=b,a
    t=float(weights[b]/(weights[a]+weights[b]))
    return (int(ids[a]),int(ids[b])),t


def interpolate_points(poly, candidates):
    """Keep shared edge segments, including collinear boundary vertices."""
    result=[]
    for a,b in zip(poly,poly[1:]+poly[:1]):
        a=np.asarray(a);b=np.asarray(b);direction=b-a;den=float(direction@direction)
        assert den>1e-26
        values=[(0.,tuple(a))]
        for p in candidates:
            p=np.asarray(p);t=float((p-a)@direction)/den
            if 1e-11<t<1.-1e-11 and np.linalg.norm(p-a-t*direction)<1e-11:
                values.append((t,tuple(p)))
        values.sort(key=lambda x:x[0]);last=-1.
        for t,p in values:
            if t-last>1e-11:result.append(p);last=t
    return result


def topology(me):
    me.calc_loop_triangles();counts=collections.Counter()
    for t in me.loop_triangles:
        for a,b in zip(t.vertices,tuple(t.vertices[1:])+tuple(t.vertices[:1])):
            counts[tuple(sorted((a,b)))]+=1
    return {'open_edges':sum(n==1 for n in counts.values()),'overused_edges':sum(n>2 for n in counts.values()),
            'triangles':len(me.loop_triangles),'vertices':len(me.vertices)}


def clip_records(data, labels, masks, low):
    """Restrict edits to ground-side coplanar triangles meeting the proven masks."""
    mask_min=np.min(np.asarray([p for m in masks for p in m]),axis=0)
    mask_max=np.max(np.asarray([p for m in masks for p in m]),axis=0)
    changed={};edge_points=collections.defaultdict(list);audit=[]
    for tid,tri in enumerate(data['tri']):
        if labels[tid]!='ground_side':continue
        yz=tri[:,1:3]
        if np.any(yz.max(axis=0)<mask_min) or np.any(yz.min(axis=0)>mask_max):continue
        # High wall inherits float noise; no point is flattened to the low plane.
        if np.max(np.abs(tri[:,0]-C.CONTRACT['left_plane_x']))>1e-6:continue
        cross=np.cross(tri[1]-tri[0],tri[2]-tri[0]);cross/=np.linalg.norm(cross)
        if cross[0]>-.999:continue
        original=P.triangle(yz.tolist());keep,gone=P.subtract(original,masks)
        removed=sum(P.area([p[0] for p in q]) for q in gone)
        if removed<=1e-18:continue
        if low:assert tid in C.CONTRACT['low_soil_triangles'],('New overlap outside authorized low list',tid,removed)
        before=P.area(yz.tolist());after=sum(P.area([p[0] for p in q]) for q in keep)
        residual=sum(P.area([p[0] for p in g]) for q in keep for m in masks for g in [P.difference(q,m)[1]] if g)
        covered_error=sum(P.area([p[0] for p in q]) for g in gone for q in P.subtract(g,masks)[0])
        assert abs(before-after-removed)<1e-12 and residual<1e-12 and covered_error<1e-12
        changed[tid]=[[p[1] for p in q] for q in keep]
        for q in keep:
            for _,w in q:
                info=edge_info(w,data['vi'][tid])
                if info and 1e-11<info[1]<1.-1e-11:edge_points[info[0]].append(info[1])
        audit.append({'original_triangle':tid,'before_yz_area_m2':before,'kept_yz_area_m2':after,
                      'removed_yz_area_m2':removed,'remaining_overlap_m2':residual,'removed_not_covered_m2':covered_error,
                      'source_plane_max_offset_m':float(np.max(np.abs(tri[:,0]-C.CONTRACT['left_plane_x']))),
                      'retained_polygons_barycentric':changed[tid]})
    if low:assert set(changed)==set(C.CONTRACT['low_soil_triangles']),('Changed triangle identity',sorted(changed))
    assert changed,'No authorized overlap found'
    # Insert new edge nodes into the adjacent triangles without moving their
    # surface. This avoids T junctions while preserving original UV seams.
    records=[];edge_refinements=[]
    for tid,ids in enumerate(data['vi']):
        edge_candidates=[]
        for a,b in ((0,1),(1,2),(2,0)):
            edge=tuple(sorted((int(ids[a]),int(ids[b]))))
            for t in edge_points.get(edge,[]):
                w=[0.,0.,0.];w[a]=1.-t if ids[a]==edge[0] else t;w[b]=1.-w[a]
                edge_candidates.append(tuple(w))
        polygons=changed.get(tid, [[(1.,0.,0.),(0.,1.,0.),(0.,0.,1.)]])
        allpoints=[w for q in polygons for w in q]+edge_candidates
        for poly in polygons:
            expanded=interpolate_points(poly,allpoints)
            if len(expanded)==3:
                records.append((tid,expanded))
            else:
                center=tuple(np.mean(np.asarray(expanded),axis=0))
                for a,b in zip(expanded,expanded[1:]+expanded[:1]):records.append((tid,[center,a,b]))
        if tid not in changed and edge_candidates:edge_refinements.append(tid)
    return records,audit,edge_refinements


def rebuild(data, records, name):
    old=data['mesh'];coords=[tuple(v) for v in data['co']];vertex_lookup={};faces=[]
    source_ids=[];weights=[]
    for tid,ww in records:
        indices=[]
        for w in ww:
            w=np.asarray(w,np.float64)
            assert abs(float(w.sum())-1.)<1e-9 and float(w.min())>=-1e-9
            unit=np.flatnonzero(w==1.)
            if len(unit)==1 and np.count_nonzero(w)==1:
                index=int(data['vi'][tid,unit[0]])
            else:
                info=edge_info(w,data['vi'][tid])
                if info:
                    edge,t=info;k=('edge',*edge,round(t,12))
                    pos=data['co'][edge[0]]*(1.-t)+data['co'][edge[1]]*t
                else:
                    k=('face',tid,*(round(float(v),12) for v in w));pos=weights_point(w,data,tid)
                if k not in vertex_lookup:
                    vertex_lookup[k]=len(coords);coords.append(tuple(pos))
                index=vertex_lookup[k]
            indices.append(index)
        assert len(set(indices))==3,('Degenerate emitted indices',tid,ww)
        faces.append(tuple(indices));source_ids.append(tid);weights.append(ww)
    source_ids=np.asarray(source_ids,np.int32);weights=np.asarray(weights,np.float64)
    me=bpy.data.meshes.new(name);me.from_pydata(coords,[],faces);me.update()
    for m in old.materials:me.materials.append(m)
    for p,tid in zip(me.polygons,source_ids):p.material_index=int(data['materials'][tid]);p.use_smooth=bool(data['smooth'][tid])
    for u in old.uv_layers:me.uv_layers.new(name=u.name)
    for u in old.uv_layers:
        values=np.einsum('nij,njk->nik',weights,data['uv'][u.name][source_ids]).astype(np.float32)
        me.uv_layers[u.name].data.foreach_set('uv',values.ravel())
    for attr in old.color_attributes:
        assert attr.domain=='CORNER',('Unhandled color domain',attr.name,attr.domain)
        src=np.asarray([tuple(x.color) for x in attr.data],np.float64)[data['li']]
        values=np.einsum('nij,njk->nik',weights,src[source_ids]).astype(np.float32)
        me.color_attributes.new(name=attr.name,type=attr.data_type,domain='CORNER').data.foreach_set('color',values.ravel())
    # Reject unknown data rather than silently dropping source shader attributes.
    known={u.name for u in old.uv_layers}|{a.name for a in old.color_attributes}
    for a in old.attributes:
        assert a.name in known or a.name.startswith('.') or a.name in {'position','sharp_face','sharp_edge','material_index'},('Uncopied source attribute',a.name,a.domain,a.data_type)
    expected_normals=np.einsum('nij,njk->nik',weights,data['normals'][source_ids])
    expected_normals/=np.linalg.norm(expected_normals,axis=-1)[...,None]
    me.normals_split_custom_set(expected_normals.reshape((-1,3)).tolist());me.update();me.calc_loop_triangles()
    assert len(me.loop_triangles)==len(records)
    oldedge={tuple(sorted(e.vertices)):(e.use_seam,e.use_edge_sharp) for e in old.edges}
    # Keep original edge flags and carry them onto their subdivided pieces.
    support={i:{i} for i in range(len(data['co']))}
    for k,index in vertex_lookup.items():support[index]=set(k[1:3]) if k[0]=='edge' else set()
    for edge in me.edges:
        a,b=edge.vertices;key=tuple(sorted((a,b)))
        flags=oldedge.get(key)
        if flags is None:
            union=support[a]|support[b]
            if len(union)==2:flags=oldedge.get(tuple(sorted(union)))
        if flags:edge.use_seam,edge.use_edge_sharp=flags
    if old.uv_layers.active:
        me.uv_layers.active_index=me.uv_layers.find(old.uv_layers.active.name)
        for u in me.uv_layers:u.active_render=old.uv_layers[u.name].active_render
    ob=bpy.data.objects.new(name,me);bpy.context.scene.collection.objects.link(ob);ob.matrix_world=data['object'].matrix_world.copy()
    ob['boundary_repair_candidate']=True
    actual=C.read(ob)
    expected=np.einsum('nij,njk->nik',weights,data['tri'][source_ids])
    errors=np.linalg.norm(actual['tri']-expected,axis=-1)
    nf=actual['normals']/np.linalg.norm(actual['normals'],axis=-1)[...,None]
    angles=np.degrees(np.arccos(np.clip(np.sum(nf*expected_normals,axis=-1),-1.,1.)))
    cross=np.cross(actual['tri'][:,1]-actual['tri'][:,0],actual['tri'][:,2]-actual['tri'][:,0])
    area=np.linalg.norm(cross,axis=-1)*.5
    assert float(area.min())>0.,'New zero-area triangle'
    winding=np.sum(cross*np.cross(data['tri'][source_ids,1]-data['tri'][source_ids,0],data['tri'][source_ids,2]-data['tri'][source_ids,0]),axis=-1)
    assert np.all(winding>0.),'Changed triangle winding'
    uv_errors={u:float(np.max(np.abs(actual['uv'][u]-np.einsum('nij,njk->nik',weights,data['uv'][u][source_ids])))) for u in data['uv']}
    matrix_same=all(tuple(a)==tuple(b) for a,b in zip(ob.matrix_world,data['object'].matrix_world))
    report={'name':name,'original_triangles':len(data['tri']),'candidate_triangles':len(actual['tri']),
        'max_float32_position_rounding_m':float(errors.max()),'max_interpolated_corner_normal_error_deg':float(angles.max()),
        'UV_max_interpolation_float32_error':uv_errors,'minimum_triangle_area_m2':float(area.min()),
        'matrix_identical':matrix_same,'topology_before':topology(old),'topology_after':topology(me),
        'local_used_bounds_before':[data['tri'].min(axis=(0,1)).tolist(),data['tri'].max(axis=(0,1)).tolist()],
        'local_used_bounds_after':[actual['tri'].min(axis=(0,1)).tolist(),actual['tri'].max(axis=(0,1)).tolist()]}
    C.write(name+'_original_face_and_corner_mapping.json',{'original_triangle':source_ids.tolist(),'original_corner_barycentrics':weights.tolist()})
    assert errors.max()<1e-7 and angles.max()<.1 and matrix_same
    assert report['local_used_bounds_before']==report['local_used_bounds_after']
    assert all(v<2e-7 for v in uv_errors.values()),uv_errors
    return ob,actual,report,source_ids,weights


def main():
    started=time.monotonic();P.self_check();before=C.verify_inputs();C.write('inputs_before.json',before)
    bpy.ops.wm.open_mainfile(filepath=str(C.ROOT/C.CONTRACT['blend']))
    plan=json.loads((C.ROOT/C.CONTRACT['projection_groups']).read_text(encoding='utf-8'))
    low=C.read(bpy.data.objects['RepairLowFull']);high=C.read(bpy.data.objects['RepairHighFull'])
    low_labels=plan['full_triangle_groups'];high_labels=C.labels(high,plan)
    evidence=json.loads((C.ROOT/C.CONTRACT['overlap_evidence']).read_text(encoding='utf-8'))
    assert len(evidence['pairs'])==10
    # Use the three actual source triangles, not rounded intersection-polygon
    # coordinates, so adjacent shared edges have one deterministic definition.
    masks=[low['tri'][i,:,1:3].tolist() for i in C.CONTRACT['concrete_mask_triangles']]
    for i in C.CONTRACT['concrete_mask_triangles']:
        assert low_labels[i]=='solid_00' and np.all(low['tri'][i,:,0]==C.CONTRACT['left_plane_x'])
    expected_area=sum(p['area_m2'] for p in evidence['pairs'])
    outputs=[];reports=[];removed=[]
    for role,data,labels in [('Low',low,low_labels),('High',high,high_labels)]:
        rec,audit,adjacent=clip_records(data,labels,masks,role=='Low')
        C.write(role+'_clip_area_proof.json',{'source_triangle_changes':audit,'edge_only_refinement_triangles':adjacent,
            'coverage_rule':'Every removed point lies under unchanged concrete; every retained polygon is the original soil face subset. Union outline is preserved in YZ.'})
        ob,actual,report,source_ids,weights=rebuild(data,rec,'Boundary'+role+'Full');outputs.append(ob)
        report['removed_projected_area_m2']=sum(r['removed_yz_area_m2'] for r in audit)
        removed.append(report['removed_projected_area_m2']);report['changed_original_faces']=[r['original_triangle'] for r in audit]
        report['edge_only_refinements']=adjacent
        # Check actual stored float32 output, not only ideal polygons.
        residual=0.
        for index,tid in enumerate(source_ids):
            if tid not in report['changed_original_faces']:continue
            poly=P.triangle(actual['tri'][index,:,1:3].tolist())
            residual+=sum(P.area([p[0] for p in gone]) for mask in masks for gone in [P.difference(poly,mask)[1]] if gone)
        report['actual_float32_remaining_overlap_m2']=residual
        assert residual<1e-9,('Stored candidate overlap',role,residual)
        gaps=[]
        for tid in report['changed_original_faces']:
            newids=np.flatnonzero(source_ids==tid)
            covers=masks+[actual['tri'][i,:,1:3].tolist() for i in newids]
            missing,_=P.subtract(P.triangle(data['tri'][tid,:,1:3].tolist()),covers)
            missing_area=sum(P.area([p[0] for p in q]) for q in missing)
            if missing_area:
                gaps.append({'original_triangle':tid,'uncovered_yz_area_m2':missing_area,
                             'polygons_yz':[[p[0] for p in q] for q in missing]})
        report['actual_float32_uncovered_projected_area_m2']=sum(g['uncovered_yz_area_m2'] for g in gaps)
        C.write(role+'_float32_coverage_gaps.json',{'gaps':gaps,'scope':'Original local soil coverage minus actual retained float32 triangles and unchanged concrete. Numerical slivers are quantified, not discarded from this report.'})
        assert report['actual_float32_uncovered_projected_area_m2']<1e-9,('Stored outer coverage gap',role,gaps)
        # Other solids, soil top relief and material slots remain geometrically
        # identical. Edge refinement only changes tessellation, not the surface.
        untouched=[i for i,tid in enumerate(source_ids) if tid not in report['changed_original_faces'] and tid not in adjacent]
        assert np.array_equal(actual['tri'][untouched],data['tri'][source_ids[untouched]])
        for u in data['uv']:assert np.array_equal(actual['uv'][u][untouched],data['uv'][u][source_ids[untouched]])
        report['untouched_triangles_exact']=len(untouched);reports.append(report)
    assert abs(removed[0]-expected_area)<1e-12 and abs(removed[0]-removed[1])<1e-9
    # Original objects stay in the candidate for editable provenance; only new
    # candidate Low is visible. No original projection tool or texture is edited.
    for ob in bpy.data.objects:
        if ob.type=='MESH':ob.hide_render=ob.name!='BoundaryLowFull'
    C.write('image_readback.json',C.images_before_save())
    C.write('surface_report.json',{'objects':reports,'same_high_low_removed_area_difference_m2':abs(removed[0]-removed[1]),
        'expected_local_overlap_area_m2':expected_area,
        'individual_shell_closure_claim':False,
        'outer_union_coverage':'Retained soil + unchanged concrete equals the previous left exterior coverage; no positive-area patch outside concrete removed.',
        'scope_limit':'Only documented local coplanar overlaps. Intentional covered boundary is reported, not silently called a closed standalone soil solid.'})
    saved=C.OUT/'boundary_candidate.blend';bpy.ops.wm.save_as_mainfile(filepath=str(saved),relative_remap=False)
    after=C.verify_inputs();assert before==after;C.write('inputs_after.json',after)
    C.write('result.json',{'status':'LOCAL_CLIP_CANDIDATE_PENDING_REVIEW','pid':os.getpid(),'seconds':time.monotonic()-started,
        'blend':str(saved),'sha256':C.sha(saved),'input_hashes_unchanged':True,'baked':False,'rendered':False,
        'normal_AO_images_unchanged':True,'report':'surface_report.json'})


if __name__=='__main__':
    try:
        main()
    except Exception as exc:
        import traceback
        failure={'status':'FAIL_STOP_NO_BAKE_RENDER','pid':os.getpid(),'exception':repr(exc),'traceback':traceback.format_exc()}
        if any(o.get('boundary_repair_candidate') for o in bpy.data.objects):
            try:
                C.images_before_save()
                saved=C.OUT/'failed_boundary_candidate.blend'
                bpy.ops.wm.save_as_mainfile(filepath=str(saved),relative_remap=False)
                failure['diagnostic_blend']=str(saved)
            except Exception as save_error:
                failure['save_error']=repr(save_error)
        C.write('failure.json',failure)
        raise
