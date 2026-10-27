"""Pure Python reader/partitioner. No bpy, engine invocation, or production writes."""
from pathlib import Path
import hashlib, json, math, struct

AREA_EPS = .0005

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def signed_area(poly):
    if len(poly)<3: return 0.0
    o=poly[0]
    return math.fsum((poly[i][0]-o[0])*(poly[i+1][1]-o[1])-(poly[i+1][0]-o[0])*(poly[i][1]-o[1]) for i in range(1,len(poly)-1))*.5

def area(poly):
    return abs(signed_area(poly))

def clean(poly):
    out=[]
    for p in poly:
        p=tuple(p)
        if not out or math.dist(p,out[-1])>1e-10: out.append(p)
    if len(out)>1 and math.dist(out[0],out[-1])<=1e-10: out.pop()
    return out

def split(poly,a,b,c):
    """inside: a*x+b*z<=c. Intersections shared exactly; on-plane points kept both sides."""
    inside=[]; outside=[]
    for p,q in zip(poly,poly[1:]+poly[:1]):
        dp=a*p[0]+b*p[1]-c; dq=a*q[0]+b*q[1]-c
        if dp<=0: inside.append(p)
        if dp>=0: outside.append(p)
        if (dp<0<dq) or (dq<0<dp):
            t=dp/(dp-dq); v=tuple(p[k]+(q[k]-p[k])*t for k in range(2))
            inside.append(v); outside.append(v)
    return clean(inside),clean(outside)

def cut_rect(poly,rect):
    """Returns inside and nonoverlapping outside polygons; rect=(x0,x1,z0,z1)."""
    x0,x1,z0,z1=rect; pending=poly; outside=[]
    for a,b,c in [(-1,0,-x0),(1,0,x1),(0,-1,-z0),(0,1,z1)]:
        pending,part=split(pending,a,b,c)
        if area(part)>1e-12: outside.append(part)
        if area(pending)<=1e-12: return [],outside
    return pending,outside

def read_export(path):
    path=Path(path).resolve(); data=json.loads(path.read_text(encoding='utf-8'))
    assert data.get('ok') is True and data.get('kind')=='actual_final_i2_yard_connector_input'
    assert data['geometry_input_sha256_before']==data['geometry_input_sha256_after']
    report=data['report']; assert report['ground_collision_unchanged'] and report['final_post_pit_exact_match']
    group=data['groups']['visible']; arrays={}; dependencies=[]
    for name,row in group['files'].items():
        p=(path.parent/row['file']).resolve()
        assert p.is_relative_to(path.parent) and p.stat().st_size==row['bytes'] and sha(p)==row['sha256'],str(p)
        raw=p.read_bytes(); assert len(raw)%4==0
        values=struct.unpack('<%df'%(len(raw)//4),raw)
        assert all(math.isfinite(v) for v in values),name
        arrays[name]=values; dependencies.append({'path':str(p),'bytes':len(raw),'sha256':row['sha256']})
    n=int(group['vertex_count']); assert n%3==0 and len(arrays['faces'])==n*3
    assert len(arrays['normals'])==n*3 and len(arrays['uv'])==n*2
    if 'tangents' in arrays: assert len(arrays['tangents'])==n*4
    points=[tuple(arrays['faces'][i:i+3]) for i in range(0,len(arrays['faces']),3)]
    assert all(p[1]==0 for p in points),'not actual flat Y0 field'
    ids=group['source_final_triangle_ids']; assert len(ids)==n//3
    polygons=[]
    for i in range(0,n,3):
        poly=[(p[0],p[2]) for p in points[i:i+3]]
        assert area(poly)>0,('zero source triangle',i//3)
        polygons.append({'poly':poly,'source_id':ids[i//3],'visible_id':i//3})
    actual=sum(area(p['poly']) for p in polygons)
    assert abs(actual-report['visible_replacement_m2'])<=AREA_EPS
    assert data['godot_origin']==[-5.7,0,19.25]
    for guard in report['guarded_existing_surfaces']:
        assert guard['source_overlap_m2']<=AREA_EPS
    return data,polygons,{'manifest':str(path),'manifest_sha256':sha(path),'files':dependencies,'actual_area_m2':actual}

def derive_seals(report):
    """Only actual authored paving guards. New side supplies10mm, P2 north/west20mm."""
    strips=[]
    for guard in report['guarded_existing_surfaces']:
        if guard['kind']!='authored_paving' or 'rect' not in guard: continue
        x,z,w,d=guard['rect']; e=x+w; s=z+d
        strips.extend([(x-.01,x,z,s),(e,e+.01,z,s),(x,e,z-.01,z),(x,e,s,s+.01)])
    # Original drain tile occupies [-22,-16]x[12,18] and supplies no half seam.
    # These replace (union with) only the matching ordinary 10mm edge strips.
    strips.extend([(-22.02,-22,12,18),(-22,-16,11.98,12)])
    return strips

def partition(polygons,report,config):
    """Every output remains inside its original visible triangle; never fills a boundary ring."""
    rows=[]; metrics={'by_role_m2':{},'maximum_per_source_area_error_m2':0.0}
    seals=derive_seals(report)
    inlet=tuple(config['inlet_rect']); patch=tuple(config['repair_rect']); wet=tuple(config['wet_rect'])
    joints=[tuple(r) for r in config['construction_joint_rects']]
    for original in polygons:
        todo=[(original['poly'],'unclassified')]; pieces=[]
        # One explicit use-based inlet, then actual existing paving connection.
        for rect,role in [(inlet,'inlet')]+[(r,'seal') for r in seals]:
            next_rows=[]
            for poly,old in todo:
                inn,out=cut_rect(poly,rect)
                if area(inn)>1e-12: pieces.append((inn,role))
                next_rows.extend((p,old) for p in out)
            todo=next_rows
        # Three disjoint longitudinal bands only establish a broad land-use boundary.
        # The final shoreline comes from the input triangles, not this material guide.
        hard=[]; soil=[]
        for poly,_ in todo:
            remaining=[poly]
            for z0,z1,right0,right1 in config['hardstand_bands']:
                after=[]
                for p in remaining:
                    band,outs=cut_rect(p,(config['hardstand_west'],100,z0,z1)); after.extend(outs)
                    if area(band)>1e-12:
                        slope=(right1-right0)/(z1-z0)
                        yes,no=split(band,1,-slope,right0-slope*z0)
                        if area(yes)>1e-12: hard.append(yes)
                        if area(no)>1e-12: soil.append(no)
                remaining=after
            soil.extend(remaining)
        # One saw-cut repair; seams stay physical split surfaces, not overlays.
        for rect,role in [(patch,'repair_seal')]+[(r,'seal') for r in joints]:
            next_rows=[]
            for poly in hard:
                inn,out=cut_rect(poly,rect)
                if area(inn)>1e-12: pieces.append((inn,role))
                next_rows.extend(out)
            hard=next_rows
        pieces.extend((p,'concrete') for p in hard)
        for poly in soil:
            inn,out=cut_rect(poly,wet)
            if area(inn)>1e-12: pieces.append((inn,'soil_local'))
            pieces.extend((p,'soil') for p in out)
        final=[]
        for poly,role in pieces:
            if role=='repair_seal':
                x0,x1,z0,z1=patch
                inn,out=cut_rect(poly,(x0+.01,x1-.01,z0+.01,z1-.01))
                if area(inn)>1e-12: final.append((inn,'repair'))
                final.extend((p,'seal') for p in out)
            else: final.append((poly,role))
        err=abs(area(original['poly'])-sum(area(p) for p,_ in final))
        metrics['maximum_per_source_area_error_m2']=max(metrics['maximum_per_source_area_error_m2'],err)
        assert err<=1e-6,('partition lost actual surface',original['visible_id'],err)
        for poly,role in final:
            rows.append({**original,'poly':poly,'role':role})
            metrics['by_role_m2'][role]=metrics['by_role_m2'].get(role,0)+area(poly)
    source_area=sum(area(r['poly']) for r in polygons); output_area=sum(area(r['poly']) for r in rows)
    assert abs(source_area-output_area)<=AREA_EPS
    assert abs(metrics['by_role_m2'].get('inlet',0)-((inlet[1]-inlet[0])*(inlet[3]-inlet[2])))<=AREA_EPS,'inlet not fully in actual visible domain; do not auto-move'
    assert metrics['by_role_m2'].get('repair',0)>0,'repair is outside real field'
    metrics.update(source_area_m2=source_area,output_area_m2=output_area,output_polygons=len(rows),new_connection_seals=seals,
                   scope='exact visible-domain land-use split; no change to installed collision or existing authored surfaces')
    return rows,metrics
