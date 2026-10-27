"""Stage A: check original bad pixels, then build projection tools without baking."""
from pathlib import Path
import os,time,json,math,sys
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parent))
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree
import repair_common as R


def bary(point,a,b,c):
    n=(b-a).cross(c-a);den=n.length_squared;assert den>1e-28
    v=(point-a).cross(c-a).dot(n)/den
    w=(b-a).cross(point-a).dot(n)/den
    return (1-v-w,v,w)


def pixel_bary(me,t,uv):
    a,b,c=[me.uv_layers['BakeUV'].data[i].uv for i in t.loops]
    d=(b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x)
    v=((uv[0]-a.x)*(c.y-a.y)-(uv[1]-a.y)*(c.x-a.x))/d
    w=((b.x-a.x)*(uv[1]-a.y)-(b.y-a.y)*(uv[0]-a.x))/d
    return (1-v-w,v,w)


def components(me):
    parents=list(range(len(me.vertices)))
    def find(i):
        while parents[i]!=i:parents[i]=parents[parents[i]];i=parents[i]
        return i
    for e in me.edges:
        a,b=map(find,e.vertices)
        if a!=b:parents[b]=a
    roots={x:i for i,x in enumerate(sorted({find(v.index) for v in me.vertices}))}
    return {t.index:roots[find(t.vertices[0])] for t in me.loop_triangles}


def make_tree(me):
    me.calc_loop_triangles()
    return BVHTree.FromPolygons([v.co for v in me.vertices],[tuple(t.vertices) for t in me.loop_triangles],all_triangles=True)


def main():
    start=time.monotonic();inputs=R.verify_frozen();R.write('inputs_before.json',inputs)
    bpy.ops.wm.open_mainfile(filepath=str(R.ROOT/R.CONTRACT['preview_source']))
    R.write('source_images.json',R.images());lock=R.scene_lock(bpy.context.scene)
    names=('HighGround','LowGround','HighSolids','LowSolids','HighFull','LowFull')
    objects={n:bpy.data.objects[n] for n in names}
    for o in objects.values():o.data.calc_loop_triangles()
    original={n:R.digest(o.data,True) for n,o in objects.items()}
    full=objects['LowFull'].data;low=objects['LowGround'].data;solids=objects['LowSolids'].data
    full_ground={R.geom_key(low,t):t for t in low.loop_triangles}
    solid_lookup={R.geom_key(solids,t):t for t in solids.loop_triangles}
    comp=components(solids);assert len(set(comp.values()))==8,len(set(comp.values()))
    group_names=[];origin_tri=[]
    for t in full.loop_triangles:
        key=R.geom_key(full,t)
        if key in full_ground:
            ot=full_ground[key];group_names.append('ground_'+R.face_kind(low,ot));origin_tri.append(('Ground',ot.index))
        else:
            ot=solid_lookup[key];group_names.append('solid_%02d'%comp[ot.index]);origin_tri.append(('Solids',ot.index))
    lows={k:objects['Low'+k].data for k in ('Ground','Solids')}
    highs={k:objects['High'+k].data for k in ('Ground','Solids')}
    trees={k:make_tree(m) for k,m in highs.items()}
    offsets={k:[v.normal.copy()*R.CAGE_OFFSET for v in m.vertices] for k,m in lows.items()}
    rows=[];failures=[]
    bad=json.loads((R.INSPECTION/'negative_normal_pixels.json').read_text(encoding='utf-8'))['pixels']
    for pixel in bad:
        t=full.loop_triangles[pixel['triangle']];w=pixel_bary(full,t,pixel['uv'])
        pos=sum((full.vertices[vi].co*weight for vi,weight in zip(t.vertices,w)),Vector())
        ln=sum((full.corner_normals[li].vector*weight for li,weight in zip(t.loops,w)),Vector()).normalized()
        category,oi=origin_tri[t.index];ot=lows[category].loop_triangles[oi]
        # Full/part corner ordering is verified by position, never assumed.
        bypos={tuple(lows[category].vertices[i].co):offsets[category][i] for i in ot.vertices}
        off=sum((bypos[tuple(full.vertices[i].co)]*weight for i,weight in zip(t.vertices,w)),Vector())
        hit,hn,idx,distance=trees[category].ray_cast(pos+off,-off.normalized(),.12)
        row={'pixel':pixel['pixel_xy_bottom_origin'],'uv':pixel['uv'],'low_full_triangle':t.index,'group':group_names[t.index],
             'low_position':list(pos),'cage_offset':list(off),'original_rgb':pixel['normal_rgb'],'hit':idx,'ray_distance':distance}
        if hit is None:row['failure']='source_ray_miss'
        else:
            hm=highs[category];ht=hm.loop_triangles[idx]
            hw=bary(hit,*[hm.vertices[i].co for i in ht.vertices])
            sn=sum((hm.corner_normals[li].vector*weight for li,weight in zip(ht.loops,hw)),Vector()).normalized()
            row.update(hit_position=list(hit),high_geometric_normal=list(hn),high_interpolated_corner_normal=list(sn),
                       high_barycentric=list(hw),high_geometry_dot_low=hn.dot(ln),high_corner_dot_low=sn.dot(ln),
                       high_geometry_angle_deg=R.angle(hn,ln),high_corner_angle_deg=R.angle(sn,ln))
            if hn.dot(ln)<=0 or sn.dot(ln)<=0:row['failure']='source_normal_faces_away_from_target'
            if category=='Ground' and R.face_kind(hm,ht)!=R.face_kind(low,ot):row['failure']='source_ray_wrong_face_class'
        if 'failure' in row:failures.append(row)
        rows.append(row)
    R.write('bad_pixel_source_normals.json',{'samples':rows,'failures':failures,'scope':'External actual high geometry and corner normals at the original fixed cage rays; not instrumented Cycles history.'})
    # Save a diagnostic before a meaningful source-normal failure can abort.
    if failures:
        bpy.ops.wm.save_as_mainfile(filepath=str(R.OUT/'source_normal_failure.blend'),relative_remap=False)
        raise AssertionError(('Source-normal prerequisite failed; no bake prepared',len(failures)))
    full_low,_,lowmeta=R.subset(objects['LowFull'],range(len(full.loop_triangles)),'RepairLowFull')
    hf=objects['HighFull'];hf.data.calc_loop_triangles()
    full_high,_,highmeta=R.subset(hf,range(len(hf.data.loop_triangles)),'RepairHighFull')
    assert R.digest(full_low.data)==R.digest(full),'Low positions/winding/BakeUV changed'
    assert R.digest(full_high.data)==R.digest(hf.data),'High positions/winding changed'
    high_ground_lookup={R.geom_key(objects['HighGround'].data,t):R.face_kind(objects['HighGround'].data,t) for t in objects['HighGround'].data.loop_triangles}
    high_side_faces=[t.index for t in full_high.data.loop_triangles if high_ground_lookup.get(R.geom_key(full_high.data,t))=='side']
    uvreports=[R.side_source_uv(full_high,high_side_faces)]
    full_low.data.calc_tangents(uvmap='BakeUV')
    # Compare all original target corners after explicit triangulation.
    normal_max=max(R.angle(full.corner_normals[a].vector,full_low.data.corner_normals[b].vector)
                   for t,p in zip(full.loop_triangles,full_low.data.polygons) for a,b in zip(t.loops,p.loop_indices))
    groups=[];corner_reports=[]
    high_comp_lookup={R.geom_key(solids,t):comp[t.index] for t in solids.loop_triangles}
    for name in sorted(set(group_names)):
        category='Ground' if name.startswith('ground_') else 'Solids';lo=objects['Low'+category];hi=objects['High'+category]
        if category=='Ground':
            kind=name.split('_',1)[1]
            li=[t.index for t in lo.data.loop_triangles if R.face_kind(lo.data,t)==kind]
            hii=[t.index for t in hi.data.loop_triangles if R.face_kind(hi.data,t)==kind]
        else:
            cid=int(name.split('_')[1]);li=[i for i,c in comp.items() if c==cid]
            hii=[t.index for t in hi.data.loop_triangles if high_comp_lookup[R.geom_key(hi.data,t)]==cid]
        l,used,lm=R.subset(lo,li,'RepairTarget_'+name);h,_,hm=R.subset(hi,hii,'RepairSource_'+name)
        if name=='ground_side':uvreports.append(R.side_source_uv(h,list(range(len(h.data.polygons)))))
        l.data.calc_tangents(uvmap='BakeUV')
        final_by_key={R.geom_key(full_low.data,t):t for t in full_low.data.loop_triangles}
        maxn=maxt=0.;signs=0
        for t in l.data.loop_triangles:
            ft=final_by_key[R.geom_key(l.data,t)];lookup={tuple(full_low.data.vertices[full_low.data.loops[i].vertex_index].co):i for i in ft.loops}
            for i in t.loops:
                j=lookup[tuple(l.data.vertices[l.data.loops[i].vertex_index].co)]
                assert tuple(l.data.uv_layers['BakeUV'].data[i].uv)==tuple(full_low.data.uv_layers['BakeUV'].data[j].uv)
                maxn=max(maxn,R.angle(l.data.corner_normals[i].vector,full_low.data.corner_normals[j].vector))
                maxt=max(maxt,R.angle(l.data.loops[i].tangent,full_low.data.loops[j].tangent))
                signs+=int(l.data.loops[i].bitangent_sign!=full_low.data.loops[j].bitangent_sign)
        check={'group':name,'max_normal_deg':maxn,'max_tangent_deg':maxt,'sign_flips':signs}
        corner_reports.append(check);assert maxn<.1 and maxt<.1 and signs==0,check
        cage=l.copy();cage.data=l.data.copy();bpy.context.scene.collection.objects.link(cage);cage.name='RepairCage_'+name;cage['repair_part']=True
        # All offsets captured from frozen original low before any cage mutation.
        for v,old_index in zip(cage.data.vertices,used):v.co=l.data.vertices[v.index].co+offsets[category][old_index]
        cage.data.update();cage.hide_render=True
        groups.append({'name':name,'source':h.name,'target':l.name,'cage':cage.name,'cage_offset_m':R.CAGE_OFFSET,'low_meta':lm,'high_meta':hm})
    owner=R.raster_owners(full_low.data)
    R.write('projection_groups.json',{'groups':groups,'full_triangle_groups':group_names,'full_low_meta':lowmeta,'full_high_meta':highmeta,
                                    'split_normal_max_deg':normal_max,'target_basis':corner_reports,'side_uv':uvreports,
                                    'occupied_pixels':int((owner>=0).sum()),'cage_policy':'Original vertex-normal 35mm offsets, prefetched before mutation; no strength search.',
                                    'normal_margin_policy':'Isolated raw group images margin0, native final composition margin1 EXTEND; BakeUV unchanged.'})
    assert {n:R.digest(o.data,True) for n,o in objects.items()}==original,'Original scene input object mutated'
    R.write('semantics.json',{'original_geometry_uv':original,'low_geometry_bakeuv':R.digest(full_low.data),
                             'high_geometry':R.digest(full_high.data),'low_triangles':len(full_low.data.loop_triangles),
                             'high_triangles':len(full_high.data.loop_triangles),'camera':lock,'geometry_changed':False,
                             'intentional_change':'Only copied high vertical source UV; explicit same-surface triangle tools, existing corner normals.'})
    R.images();R.show([full_high]);saved=R.OUT/'prepared_repair.blend'
    bpy.ops.wm.save_as_mainfile(filepath=str(saved),relative_remap=False)
    R.verify_frozen()
    R.write('result.json',{'stage':'prepare','status':'PASS','pid':os.getpid(),'seconds':time.monotonic()-start,
                         'blend':saved.name,'blend_sha256':R.sha(saved),'bad_pixels_checked':len(rows),
                         'groups':len(groups),'source_normal_failures':0,'baked':False,'rendered':False})


if __name__=='__main__':main()
