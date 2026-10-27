"""Read-only fixed-camera boundary/texture diagnosis. No bake, save or render."""
from pathlib import Path
import sys, os, json, hashlib, time, math, collections
sys.dont_write_bytecode = True
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from bpy_extras.object_utils import world_to_camera_view

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[5]
OUT = Path(os.environ['BOUNDARY_INSPECTION_OUTPUT']).resolve()
assert OUT.is_relative_to(HERE)
CONTRACT = json.loads((HERE/'input_contract.json').read_text(encoding='utf-8'))


def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def write(name, value):
    (OUT/name).write_text(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False)+'\n', encoding='utf-8')


def inputs():
    rows=[]
    for rel, expected in CONTRACT['inputs'].items():
        p=ROOT/rel; actual={'sha256':sha(p),'bytes':p.stat().st_size}
        assert actual==expected, (rel,actual,expected)
        rows.append({'path':rel,**actual})
    return rows


def key(points): return tuple(sorted(tuple(float(v) for v in p) for p in points))


def mesh_data(ob, tangents=False):
    me=ob.data; assert not ob.modifiers, ob.name
    me.calc_loop_triangles()
    if tangents: me.calc_tangents(uvmap='BakeUV')
    co=np.asarray([tuple(v.co) for v in me.vertices],np.float64)
    vi=np.asarray([tuple(t.vertices) for t in me.loop_triangles],np.int32)
    loops=np.asarray([tuple(t.loops) for t in me.loop_triangles],np.int32)
    world=np.asarray([tuple(ob.matrix_world @ Vector(p)) for p in co],np.float64)
    d={'object':ob,'mesh':me,'co':co,'vi':vi,'loops':loops,'local_tri':co[vi],
       'world':world,'tri':world[vi],'corner':np.asarray([tuple(n.vector) for n in me.corner_normals],np.float64)[loops]}
    d['tree']=BVHTree.FromPolygons([Vector(v) for v in world],[tuple(t) for t in vi],all_triangles=True)
    if 'BakeUV' in me.uv_layers:
        d['uv']=np.asarray([tuple(x.uv) for x in me.uv_layers['BakeUV'].data],np.float64)[loops]
    if tangents:
        d['tangent']=np.asarray([tuple(x.tangent) for x in me.loops],np.float64)[loops]
        d['sign']=np.asarray([x.bitangent_sign for x in me.loops],np.float64)[loops]
    edges=np.sort(vi[:,[[0,1],[1,2],[2,0]]].reshape(-1,2),axis=1)
    _,inv,cnt=np.unique(edges,axis=0,return_inverse=True,return_counts=True)
    d['edge_adjacency']=cnt[inv].reshape(-1,3)
    return d


def bary(p, q):
    a,b,c=q; n=np.cross(b-a,c-a); den=float(n@n); assert den>1e-28
    v=float(np.cross(p-a,c-a)@n)/den; w=float(np.cross(b-a,p-a)@n)/den
    return np.asarray([1-v-w,v,w])


def normalize(a):
    size=float(np.linalg.norm(a)); assert size>1e-15
    return a/size


def owners(d, size):
    # Exact pixel-centre occupancy, not island-centroid guesses. Margin pixels
    # intentionally retain owner=-1 but their actual image values are reported.
    owner=np.full((size,size),-1,np.int32)
    for tid,q in enumerate(d['uv']):
        a,b,c=q; det=float(np.cross(b-a,c-a)); assert abs(det)>1e-14
        x0=max(0,int(math.floor(q[:,0].min()*size-.5)));x1=min(size-1,int(math.ceil(q[:,0].max()*size-.5)))
        y0=max(0,int(math.floor(q[:,1].min()*size-.5)));y1=min(size-1,int(math.ceil(q[:,1].max()*size-.5)))
        yy,xx=np.mgrid[y0:y1+1,x0:x1+1];px=(xx+.5)/size-a[0];py=(yy+.5)/size-a[1]
        u=(px*(c[1]-a[1])-py*(c[0]-a[0]))/det;v=((b[0]-a[0])*py-(b[1]-a[1])*px)/det
        mask=(u>1e-7)&(v>1e-7)&(1-u-v>1e-7);block=owner[y0:y1+1,x0:x1+1]
        assert not np.any(mask&(block>=0)), 'Actual UV pixel-centre overlap'
        block[mask]=tid
    return owner


def image_arrays(low):
    mat=low['object'].data.materials[0]; n=mat.node_tree.nodes; rows=[]; arrays={}
    bs=next(x for x in n if x.type=='BSDF_PRINCIPLED')
    nm=bs.inputs['Normal'].links[0].from_node
    assert nm.type=='NORMAL_MAP' and nm.uv_map=='BakeUV' and nm.space=='TANGENT'
    assert abs(nm.inputs['Strength'].default_value-1.)<1e-8
    for role in ('BaseColor','Normal','ORM'):
        tex=n['Repair_'+role]; assert tex.type=='TEX_IMAGE'
        uv=tex.inputs['Vector'].links[0].from_node; assert uv.type=='UVMAP' and uv.uv_map=='BakeUV'
        im=tex.image; p=Path(bpy.path.abspath(im.filepath)).resolve(); assert p.is_file()
        a=np.empty(len(im.pixels),np.float32); im.pixels.foreach_get(a)
        assert im.has_data and np.isfinite(a).all()
        arrays[role]=a.reshape((im.size[1],im.size[0],4))
        rows.append({'role':role,'image':im.name,'path':str(p),'size':list(im.size),'sha256':sha(p),
                     'space':im.colorspace_settings.name,'interpolation':tex.interpolation,'extension':tex.extension})
        assert tex.interpolation=='Linear' and tex.extension=='EXTEND'
    assert bs.inputs['Base Color'].links[0].from_node.type=='MIX_RGB'
    return arrays,rows


def sample_maps(uv, arrays, owner, labels):
    size=arrays['Normal'].shape[0]; xy=uv*size-.5; x0,y0=np.floor(xy).astype(int); fx,fy=xy-[x0,y0]
    taps=[]; values={k:np.zeros(4) for k in arrays}
    for dx,dy,w in [(0,0,(1-fx)*(1-fy)),(1,0,fx*(1-fy)),(0,1,(1-fx)*fy),(1,1,fx*fy)]:
        x=int(np.clip(x0+dx,0,size-1)); y=int(np.clip(y0+dy,0,size-1)); tid=int(owner[y,x])
        vals={k:a[y,x].tolist() for k,a in arrays.items()}
        for k in arrays: values[k]+=w*arrays[k][y,x]
        taps.append({'pixel_bottom_origin':[x,y],'weight':float(w),'interior_owner':tid,
                     'owner_group':labels[tid] if tid>=0 else None,'values':vals})
    return {'uv':uv.tolist(),'taps':taps,'bilinear':{k:v.tolist() for k,v in values.items()},
            'note':'CPU level0 Linear approximation; actual Cycles derivative filtering can differ.'}


def hit(d, origin, direction):
    p,n,tid,dist=d['tree'].ray_cast(origin,direction,10.)
    if p is None:return {'hit':False}
    weights=bary(np.asarray(p),d['tri'][tid]); corner=normalize(np.sum(d['corner'][tid]*weights[:,None],axis=0))
    normal_matrix=np.asarray(d['object'].matrix_world.to_3x3().inverted().transposed())
    corner=normalize(normal_matrix@corner)
    return {'hit':True,'triangle':int(tid),'group':d['labels'][tid],'position':list(p),'distance_m':float(dist),
            'geometric_normal':list(n),'corner_normal':corner.tolist(),'barycentric':weights.tolist(),
            'triangle_vertices_world':d['tri'][tid].tolist(),'triangle_edge_adjacent_face_counts':d['edge_adjacency'][tid].tolist()}


def ray_segments(tree, origin, direction, maximum=.06):
    records=[]; travelled=0.; start=origin.copy()
    for _ in range(12):
        pos,n,tid,dist=tree.ray_cast(start,direction,maximum-travelled)
        if pos is None:break
        travelled+=float(dist); records.append({'position':list(pos),'triangle':int(tid),'distance_from_start_m':travelled,'normal_dot_direction':float(n.dot(direction))})
        travelled+=1e-6
        if travelled>=maximum:break
        start=pos+direction*1e-6
    return records


def main():
    started=time.monotonic(); before=inputs(); write('inputs_before.json',before)
    bpy.ops.wm.open_mainfile(filepath=str(ROOT/CONTRACT['blend']))
    plan=json.loads((ROOT/CONTRACT['projection_groups']).read_text(encoding='utf-8'))
    low=mesh_data(bpy.data.objects['RepairLowFull'],True);high=mesh_data(bpy.data.objects['RepairHighFull'])
    low['labels']=plan['full_triangle_groups'];assert len(low['labels'])==len(low['vi'])
    group_trees={'high':{},'low':{}}; high_lookup={}
    for g in plan['groups']:
        for role,name in [('high',g['source']),('low',g['target'])]:
            d=mesh_data(bpy.data.objects[name]); group_trees[role][g['name']]=d['tree']
            if role=='high':
                for points in d['local_tri']:
                    high_lookup.setdefault(key(points),set()).add(g['name'])
    high['labels']=['|'.join(sorted(high_lookup[key(p)])) for p in high['local_tri']]
    arrays,image_records=image_arrays(low);write('actual_images_and_nodes.json',image_records)
    size=arrays['Normal'].shape[0];assert all(a.shape==(size,size,4) for a in arrays.values())
    owner=owners(low,size)
    scene=bpy.context.scene;cam=scene.camera;assert cam.data.type=='ORTHO'
    frame=cam.data.view_frame(scene=scene);xmin=min(p.x for p in frame);xmax=max(p.x for p in frame);ymin=min(p.y for p in frame);ymax=max(p.y for p in frame)
    w,h=CONTRACT['render_size']; assert (scene.render.resolution_x,scene.render.resolution_y)==(w,h)
    direction=(cam.matrix_world.to_3x3()@Vector((0,0,-1))).normalized()
    selections=json.loads((HERE/'screen_samples.json').read_text(encoding='utf-8'));rows=[]
    for sample in selections['samples']:
        x,y=sample['pixel'];u=(x+.5)/w;v=1-(y+.5)/h
        origin=cam.matrix_world@Vector((xmin+(xmax-xmin)*u,ymin+(ymax-ymin)*v,-cam.data.clip_start))
        lo=hit(low,origin,direction);hi=hit(high,origin,direction);row={**sample,'low':lo,'high':hi}
        if lo['hit']:
            pp=world_to_camera_view(scene,cam,Vector(lo['position']));assert abs(pp.x-u)<2e-5 and abs(pp.y-v)<2e-5,('Camera ray mapping mismatch',x,y,list(pp),u,v)
            tid=lo['triangle'];weights=np.asarray(lo['barycentric']);uv=np.sum(low['uv'][tid]*weights[:,None],axis=0)
            row['maps']=sample_maps(uv,arrays,owner,low['labels'])
            nlocal=normalize(np.sum(low['corner'][tid]*weights[:,None],axis=0))
            tlocal=np.sum(low['tangent'][tid]*weights[:,None],axis=0);tlocal=normalize(tlocal-nlocal*(tlocal@nlocal))
            sign=float(np.sign(np.sum(low['sign'][tid]*weights)));blocal=sign*np.cross(nlocal,tlocal)
            encoded=np.asarray(row['maps']['bilinear']['Normal'][:3])*2-1
            mapped=normalize(tlocal*encoded[0]+blocal*encoded[1]+nlocal*encoded[2])
            nm=np.asarray(low['object'].matrix_world.to_3x3().inverted().transposed());mapped=normalize(nm@mapped)
            row['shader_normal_estimate']={'normal_world':mapped.tolist(),'dot_geometric':float(mapped@np.asarray(lo['geometric_normal'])),
                'dot_to_camera':float(mapped@(-np.asarray(direction))),'decoded_tangent_z':float(encoded[2]),
                'note':'Level0 bilinear plus interpolated Mikk frame estimate, not instrumented Cycles shading.'}
            gn=group_trees['high'][lo['group']];near=gn.find_nearest(Vector(lo['position']))
            row['nearest_matching_high']={'source_object':'RepairSource_'+lo['group'],'position':list(near[0]),'normal':list(near[1]),
                'triangle':int(near[2]),'unsigned_distance_m':float(near[3]),'note':'BVH nearest distance; not a signed gap or penetration depth.'} if near[0] is not None else None
            if hi['hit']:row['camera_high_minus_low_depth_m']=hi['distance_m']-lo['distance_m']
        rows.append(row)
    write('pixel_geometry_and_maps.json',{'samples':rows,'scope':'Actual fixed-camera first-hit geometry and level0 texture-neighborhood samples. No images edited.'})
    # Small local axis sections expose nearby component surfaces; no unsupported
    # boolean/gap verdict is inferred from unsigned nearest distance alone.
    sections=[]
    for region in selections['regions']:
        candidates=[x for x in rows if x['region']==region and x['low']['hit']]
        candidates.sort(key=lambda x:x['high_luma']-x['low_luma'],reverse=True)
        chosen=[]
        for row in candidates:
            if all(np.linalg.norm(np.asarray(row['pixel'])-np.asarray(q['pixel']))>=12 for q in chosen):chosen.append(row)
            if len(chosen)==3:break
        for row in chosen:
            center=Vector(row['low']['position']); rec={'region':region,'pixel':row['pixel'],'center':list(center),'axes':[]}
            for axis in range(3):
                direction=Vector(tuple(1. if j==axis else 0. for j in range(3)));origin=center-direction*.03
                hits={role:{name:ray_segments(tree,origin,direction) for name,tree in trees.items()} for role,trees in group_trees.items()}
                rec['axes'].append({'world_axis':axis,'segment_start':list(origin),'segment_length_m':.06,'surface_intersections':hits})
            sections.append(rec)
    write('local_surface_sections.json',{'sections':sections,'scope':'Actual intersections within six-centimetre local axis segments; direction signs and positions retained. Not a global self-intersection or volumetric certification.'})
    aggregate={}
    for region in selections['regions']:
        rr=[x for x in rows if x['region']==region];both=[x for x in rr if x['low']['hit'] and x['high']['hit']]
        mapped=[x for x in rr if 'maps' in x];dark=[x for x in mapped if x['low_luma']<.15 and x['high_luma']-x['low_luma']>.06]
        aggregate[region]={'samples':len(rr),'low_miss':sum(not x['low']['hit'] for x in rr),'high_miss':sum(not x['high']['hit'] for x in rr),
            'different_visible_group':sum(x['low']['group']!=x['high']['group'] for x in both),
            'max_camera_depth_difference_m':max((abs(x['camera_high_minus_low_depth_m']) for x in both),default=0.),
            'max_nearest_same_group_high_distance_m':max((x['nearest_matching_high']['unsigned_distance_m'] for x in mapped if x['nearest_matching_high']),default=0.),
            'new_dark_samples':len(dark),'new_dark_AO_range':[min((x['maps']['bilinear']['ORM'][0] for x in dark),default=1.),max((x['maps']['bilinear']['ORM'][0] for x in dark),default=1.)],
            'new_dark_Normal_B_range':[min((x['maps']['bilinear']['Normal'][2] for x in dark),default=1.),max((x['maps']['bilinear']['Normal'][2] for x in dark),default=1.)]}
    after=inputs();assert before==after;write('inputs_after.json',after)
    write('result.json',{'status':'READONLY_BOUNDARY_DIAGNOSTIC_COMPLETE','pid':os.getpid(),'seconds':time.monotonic()-started,
        'regions':aggregate,'input_hashes_unchanged':True,'source_saved':False,'objects_created':False,'baked':False,'rendered':False,
        'limit':'Evidence requires interpretation; no visual/geometry repair or automatic pass conclusion.'})


if __name__=='__main__': main()
