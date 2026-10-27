"""Exact world-metre plan; pure Python, no engine and no asset mutation."""
from pathlib import Path
import json, math, hashlib

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
SOURCE = ROOT/'asset_sources/v3/i2_canal_revetment/delivery_p4/i2_canal_revetment_editable.blend'
SOURCE_SHA = '2e14f59de71971596226af0ecf2c2d59ea4b8e6bffea60c07d2a0308ac563b71'

def add(a,b): return tuple(x+y for x,y in zip(a,b))
def sub(a,b): return tuple(x-y for x,y in zip(a,b))
def mul(a,k): return tuple(x*k for x in a)
def dot(a,b): return sum(x*y for x,y in zip(a,b))
def cross(a,b): return a[0]*b[1]-a[1]*b[0]
def unit(v): return mul(v,1/math.hypot(*v))
def area(p): return abs(sum(cross(a,b) for a,b in zip(p,p[1:]+p[:1])))/2

def intersection(a,t,b,u):
    denominator=cross(t,u)
    assert abs(denominator)>1e-12
    return add(a,mul(t,cross(sub(b,a),u)/denominator))

def signed_plane(a,b,inside):
    n=unit((-(b[1]-a[1]),b[0]-a[0])); d=dot(n,a)
    if dot(n,inside)<d: n=mul(n,-1);d=-d
    return [n[0],n[1],d]

def overlap_area(polygon,clipper):
    center=mul(tuple(map(sum,zip(*clipper))),1/len(clipper));current=list(polygon)
    for a,b in zip(clipper,clipper[1:]+clipper[:1]):
        nx,nz,d=signed_plane(a,b,center);out=[]
        for p,q in zip(current,current[1:]+current[:1]):
            dp=nx*p[0]+nz*p[1]-d;dq=nx*q[0]+nz*q[1]-d
            if dp>=0:out.append(p)
            if (dp>=0)!=(dq>=0):out.append(add(p,mul(sub(q,p),dp/(dp-dq))))
        current=out
    return area(current) if len(current)>2 else 0.

def build_plan():
    specs=[
        ('WestWiden',(12.6,15.6),(9.5,19.),'west',2,.35),
        ('WestMouth',(9.5,19.),(9.5,28.),'west',3,.35),
        ('EastWiden',(16.9,15.6),(22.5,19.),'east',2,.35),
        ('EastMouth',(22.5,19.),(24.5,28.),'east',3,.35),
        # West wing fills the old bare corner. The east corner is already the
        # accepted extension floor; stop at X16.9 rather than overlap it.
        ('NorthHead',(12.25,2.3),(16.9,2.3),'north',2,.30),
    ]
    rows=[]
    for name,a,b,side,count,depth in specs:
        t=unit(sub(b,a))
        water=(t[1],-t[0]) if side=='west' else (-t[1],t[0])
        local_x=mul(t,-1) if side=='west' else t
        back_a=add(a,mul(water,-depth));back_b=add(b,mul(water,-depth))
        rows.append(dict(id=name,a=a,b=b,t=t,water=water,local_x=local_x,depth=depth,count=count,
                         back_a=back_a,back_b=back_b,length=math.dist(a,b)))
    for first,second in [(rows[0],rows[1]),(rows[2],rows[3])]:
        miter=intersection(first['back_a'],first['t'],second['back_a'],second['t'])
        first['back_b']=miter;second['back_a']=miter
        # Exact abutment at old source endpoint; do not touch the old straight.
        first['back_a']=intersection(first['back_a'],first['t'],first['a'],(1.,0.))
        second['back_b']=intersection(second['back_a'],second['t'],second['b'],(1.,0.))
    pieces=[]
    for row in rows:
        row['footprint']=[row['a'],row['b'],row['back_b'],row['back_a']]
        row['top_area_m2']=area(row['footprint'])
        for i in range(row['count']):
            a=add(row['a'],mul(sub(row['b'],row['a']),i/row['count']))
            b=add(row['a'],mul(sub(row['b'],row['a']),(i+1)/row['count']))
            ba=row['back_a'] if i==0 else add(a,mul(row['water'],-row['depth']))
            bb=row['back_b'] if i==row['count']-1 else add(b,mul(row['water'],-row['depth']))
            middle=mul(add(a,b),.5)
            def local(p):
                q=sub(p,middle);return [dot(q,row['local_x']),dot(q,row['water'])]
            footprint=[a,b,bb,ba]
            # Source local coordinates are (X,Z); front +Z always faces water.
            planes=[signed_plane(local(a),local(ba),(0.,-row['depth']/2)),
                    signed_plane(local(b),local(bb),(0.,-row['depth']/2))]
            if row['depth']<.35:planes.append([0.,1.,-row['depth']])
            bounds=[min(local(p)[k] for p in footprint) for k in range(2)]+[max(local(p)[k] for p in footprint) for k in range(2)]
            assert bounds[0]>-2 and bounds[2]<2,('crop exceeds source',row['id'],i,bounds)
            pieces.append(dict(id=f"{row['id']}_{i+1:02}",segment=row['id'],origin=[middle[0],0,middle[1]],
                local_x=list(row['local_x']),water=list(row['water']),depth=row['depth'],
                front=[list(a),list(b)],footprint=[list(p) for p in footprint],clip_planes=planes,
                bounds_xz=bounds,top_area_m2=area(footprint),source_scale=[1,1,1],
                source_uv='interpolated unchanged; new caps use adjacent metric front strip',
                internal_end_caps='editable closure only; excluded from final surface at shared assembly joins'))
    assert len(pieces)==12
    overlap_rows=[]
    for i,first in enumerate(pieces):
        for second in pieces[i+1:]:
            measured=overlap_area(first['footprint'],second['footprint'])
            assert measured<1e-10,('piece overlap',first['id'],second['id'],measured)
            overlap_rows.append(measured)
    water_segments=[dict(id=r['id'],a=list(r['a']),b=list(r['b']),water=list(r['water']),length=r['length']) for r in rows[:4]]
    water_segments.append(dict(id='NorthHead',a=[12.6,2.3],b=[16.9,2.3],water=[0,1],length=4.3))
    result=dict(version=1,stage='static_source_plan_not_engine_verified',source=str(SOURCE.relative_to(ROOT)),source_sha256=SOURCE_SHA,
        scope='remaining original A-channel banks only; no cross-water south closure',
        height=2.8,top_y=0,bed_y=-2.8,pieces=pieces,segments=rows,water_segments=water_segments,
        removed_bank_area_m2=sum(r['length'] for r in water_segments)*2.8,
        top_footprint_area_m2=sum(r['top_area_m2'] for r in rows),
        north_thickness_exception='Root approved actual 0.30 m crop; Z2.0..2.3 abuts existing maintenance paving at Z2',
        maximum_pair_overlap_m2=max(overlap_rows),
        unchanged=['original source bytes','both straight banks','water','bed','Ground collision','all facilities'])
    assert abs(sum(p['top_area_m2'] for p in pieces)-result['top_footprint_area_m2'])<1e-10
    return result

if __name__=='__main__':
    p=build_plan();assert hashlib.sha256(SOURCE.read_bytes()).hexdigest()==SOURCE_SHA
    HERE.mkdir(parents=True,exist_ok=True)
    (HERE/'layout_plan.json').write_text(json.dumps(p,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    candidate=ROOT/'assets/v3/candidates/i2_revetment_closure'
    candidate.mkdir(parents=True,exist_ok=True)
    (candidate/'layout_plan.json').write_bytes((HERE/'layout_plan.json').read_bytes())
    print(json.dumps({k:p[k] for k in ['stage','removed_bank_area_m2','top_footprint_area_m2']},ensure_ascii=False))
