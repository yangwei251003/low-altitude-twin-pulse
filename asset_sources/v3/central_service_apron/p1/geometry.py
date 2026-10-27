"""CPU-only clipping of real triangle soup. Never reconstruct a hull or fill holes.

Half-plane split derives from the approved yard field_geometry.py. This version
keeps the complementary remainder and barycentric corner correspondence.
"""
from pathlib import Path
import hashlib, json, math, struct

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def signed_area(poly):
    if len(poly) < 3: return 0.0
    a = poly[0]
    return math.fsum((poly[i][0]-a[0])*(poly[i+1][1]-a[1])-
                     (poly[i][1]-a[1])*(poly[i+1][0]-a[0])
                     for i in range(1,len(poly)-1)) / 2

def area(poly): return abs(signed_area(poly))

def clean(poly):
    result=[]
    for p in poly:
        p=tuple(p)
        if not result or p != result[-1]: result.append(p)
    if len(result)>1 and result[0]==result[-1]: result.pop()
    return result

def split(poly, a, b, c):
    yes=[]; no=[]
    for p,q in zip(poly,poly[1:]+poly[:1]):
        dp=a*p[0]+b*p[1]-c; dq=a*q[0]+b*q[1]-c
        if dp<=0: yes.append(p)
        if dp>=0: no.append(p)
        if dp<0<dq or dq<0<dp:
            t=dp/(dp-dq)
            v=(p[0]+t*(q[0]-p[0]),p[1]+t*(q[1]-p[1]))
            yes.append(v); no.append(v)
    return clean(yes),clean(no)

def cut_rect(poly, rect):
    x0,x1,z0,z1=rect; current=poly; outside=[]
    for a,b,c in [(-1,0,-x0),(1,0,x1),(0,-1,-z0),(0,1,z1)]:
        current,part=split(current,a,b,c)
        if area(part)>0: outside.append(part)
        if area(current)==0: return [],outside
    return current,outside

def read_input(path, group_name):
    path=Path(path).resolve(); data=json.loads(path.read_text(encoding='utf-8'))
    assert data.get('ok') is True, 'export did not pass its own readback'
    if data.get('kind')=='current_world_post_yard_raw_arrays':
        assert data['read_only_unchanged'] and data['engine_errors']==[]
    if 'geometry_input_sha256_before' in data:
        assert data['geometry_input_sha256_before']==data['geometry_input_sha256_after']
    group=data['groups'][group_name]; arrays={}; dependencies=[]
    for name,width in [('faces',3),('normals',3),('uv',2),('tangents',4)]:
        row=group['files'][name]; p=(path.parent/row['file']).resolve()
        assert p.is_relative_to(path.parent) and p.is_file()
        raw=p.read_bytes(); assert len(raw)==row['bytes'] and sha(p)==row['sha256']
        values=struct.unpack('<%df'%(len(raw)//4),raw)
        assert len(values)==group['vertex_count']*width and all(map(math.isfinite,values))
        arrays[name]=[tuple(values[i:i+width]) for i in range(0,len(values),width)]
        dependencies.append({'path':str(p),'bytes':len(raw),'sha256':row['sha256']})
    count=group['triangle_count']; assert group['vertex_count']==count*3
    ids=group['source_final_triangle_ids']; assert len(ids)==count
    rows=[]
    for i in range(count):
        corners={k:v[i*3:i*3+3] for k,v in arrays.items()}
        assert all(p[1]==0 for p in corners['faces']), 'non-Y0 surface needs a new contract'
        assert len(set(corners['normals']))==1, 'nonconstant source normals need explicit handling'
        assert all(math.degrees(math.atan2(math.hypot(n[0],n[2]),n[1]))<=0.1 for n in corners['normals'])
        assert len(set(corners['tangents']))==1, 'nonconstant tangent must not be guessed'
        p=[(v[0],v[2]) for v in corners['faces']]
        assert area(p)>0, ('zero original triangle',i)
        rows.append({'input_triangle':i,'source_final_triangle':ids[i],'poly':p,'corners':corners})
    return rows, {'manifest':str(path),'manifest_sha256':sha(path),'group':group_name,
                  'input_kind':data.get('kind'),'id_scope':data.get('scope'),
                  'ground_collision_sha256':data.get('ground_collision_sha256'),
                  'files':dependencies,'triangle_count':count,'area_m2':sum(area(x['poly']) for x in rows)}

def barycentric(point, poly):
    a,b,c=poly; x,z=point
    det=(b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])
    v=((x-a[0])*(c[1]-a[1])-(z-a[1])*(c[0]-a[0]))/det
    w=((b[0]-a[0])*(z-a[1])-(b[1]-a[1])*(x-a[0]))/det
    return (1-v-w,v,w)

def interpolate(corners, weights):
    return tuple(math.fsum(weights[i]*corners[i][k] for i in range(3)) for k in range(len(corners[0])))

def classify(original, config):
    inside, outside=cut_rect(original['poly'],config['outer_rect_x0_x1_z0_z1'])
    remainder=[{'poly':p,'reason':'outside_apron'} for p in outside]
    todo=[inside] if area(inside)>0 else []
    for footprint in config['footprints']:
        next_rows=[]
        for p in todo:
            removed,rest=cut_rect(p,footprint['rect']); next_rows.extend(rest)
            if area(removed)>0: remainder.append({'poly':removed,'reason':footprint['id']})
        todo=next_rows
    return todo,remainder

def finish_role(poly, role, config, label):
    """One repair and 20mm seal strips occupy original top, never overlay it."""
    todo=[poly]; result=[]; width=config['joint_width']/2
    patch=config['repair_rect']
    for p in todo:
        pin,rest=cut_rect(p,patch)
        result.extend({'poly':q,'role':role,'part':label} for q in rest)
        if area(pin)>0:
            x0,x1,z0,z1=patch; core,rim=cut_rect(pin,(x0+width,x1-width,z0+width,z1-width))
            if area(core)>0: result.append({'poly':core,'role':'repair','part':'SawCutRepair'})
            result.extend({'poly':q,'role':'joint','part':'RepairSeal'} for q in rim)
    return result

def partition(source, config):
    output=[]; remainder=[]; mapping=[]
    for old in source:
        selected, rest=classify(old,config); pieces=[]
        # T-shaped route is a union of two rectangles, not a new physical road.
        routes=[]; dark=selected
        for ri,rect in enumerate(config['routes']):
            after=[]
            for p in dark:
                yes,no=cut_rect(p,rect); after.extend(no)
                if area(yes)>0: routes.append((yes,'route'))
            dark=after
        zones=routes+[(p,'maintenance') for p in dark]
        # 3-6m panel rhythm is tied to existing structures. Shared edges cut once.
        for poly,role in zones:
            pending=[poly]
            xedges=config['slab_x_edges']; zedges=config['slab_z_edges']
            for ix in range(len(xedges)-1):
                for iz in range(len(zedges)-1):
                    after=[]
                    rect=(xedges[ix],xedges[ix+1],zedges[iz],zedges[iz+1])
                    for p in pending:
                        cell,outs=cut_rect(p,rect); after.extend(outs)
                        if area(cell)==0: continue
                        current=[cell]; seals=[]; w=config['joint_width']/2
                        # Do not add an outer border; only actual internal construction joints.
                        strips=[]
                        if ix>0: strips.append((rect[0],rect[0]+w,rect[2],rect[3]))
                        if ix<len(xedges)-2: strips.append((rect[1]-w,rect[1],rect[2],rect[3]))
                        if iz>0: strips.append((rect[0],rect[1],rect[2],rect[2]+w))
                        if iz<len(zedges)-2: strips.append((rect[0],rect[1],rect[3]-w,rect[3]))
                        for s in strips:
                            more=[]
                            for q in current:
                                yes,no=cut_rect(q,s);more.extend(no)
                                if area(yes)>0:seals.append(yes)
                            current=more
                        label=f'Slab_{ix:02d}_{iz:02d}_{role}'
                        pieces.extend({'poly':q,'role':'joint','part':'ConstructionSeals'} for q in seals)
                        for q in current: pieces.extend(finish_role(q,role,config,label))
                    pending=after
            assert sum(area(p) for p in pending)<1e-8, 'panel frame did not cover selected source'
        a=area(old['poly']); out_area=sum(area(p['poly']) for p in pieces); rem_area=sum(area(p['poly']) for p in rest)
        error=abs(a-out_area-rem_area)
        assert error<=1e-6, ('source triangle conservation',old['input_triangle'],error)
        for p in pieces:
            weights=[barycentric(v,old['poly']) for v in p['poly']]
            assert all(min(w)>=-1e-5 and max(w)<=1.00001 for w in weights)
            output.append({**p,'input_triangle':old['input_triangle'],'source_final_triangle':old['source_final_triangle'],
                           'barycentric':weights,'original_uv':[interpolate(old['corners']['uv'],w) for w in weights],
                           'original_normal':old['corners']['normals'][0],
                           'original_tangent':old['corners']['tangents'][0]})
        remainder.extend({**p,'input_triangle':old['input_triangle'],'source_final_triangle':old['source_final_triangle']} for p in rest)
        mapping.append({'input_triangle':old['input_triangle'],'source_final_triangle':old['source_final_triangle'],
                        'original_area_m2':a,'replacement_area_m2':out_area,'remainder_area_m2':rem_area,'conservation_error_m2':error})
    by_role={}
    for p in output:by_role[p['role']]=by_role.get(p['role'],0)+area(p['poly'])
    return output,remainder,{'per_original_triangle':mapping,'by_role_m2':by_role,
        'replacement_area_m2':sum(by_role.values()),'remainder_area_m2':sum(area(p['poly']) for p in remainder),
        'max_conservation_error_m2':max(x['conservation_error_m2'] for x in mapping),
        'fan_triangle_estimate':sum(len(p['poly'])-2 for p in output),'editable_parts':len({p['part'] for p in output}),
        'note':'Original float32 micro gaps preserved; structure interiors remain in original remainder. No convex hull, snap, or hole fill.'}

def f32(v):return struct.unpack('<f',struct.pack('<f',v))[0]

def triangulate(row, origin):
    indices=list(range(len(row['poly'])))
    if signed_area(row['poly'])>0: indices.reverse()
    triangles=[]; residuals=[]
    for k in range(1,len(indices)-1):
        ids=[indices[0],indices[k],indices[k+1]]
        xyz=[(row['poly'][i][0]-origin[0],-(row['poly'][i][1]-origin[2]),0.0) for i in ids]
        actual=[tuple(f32(v) for v in p) for p in xyz]; ar=area([(p[0],p[1]) for p in xyz])
        if ar==0:continue
        err=max(math.dist(p,q) for p,q in zip(xyz,actual));assert err<=1e-5
        if area([(p[0],p[1]) for p in actual])==0:
            longest=max(math.dist(xyz[i],xyz[(i+1)%3]) for i in range(3)); width=2*ar/longest
            assert width<=1e-5
            residuals.append({'input_triangle':row['input_triangle'],'area_m2':ar,'width_m':width})
        else:triangles.append({'indices':ids,'positions':actual,'max_position_error_m':err})
    return triangles,residuals
