"""Editable fixed landing parts in Godot metres. Primitives reused from approved P4 bridge source.

One Mesh per production body. Named closed construction pieces stay editable
inside that Mesh; intended weld/fastener intersections are not Boolean unions.
This file does not claim collision or triangle-intersection verification.
"""
from __future__ import annotations

from collections import Counter
from dataclasses import dataclass, field
import hashlib
import json
import math
from pathlib import Path

ORIGIN = (15.0, 5.0, 0.0)
LAYOUT_SHA = "ad357fc68c68692a99f2d5394f8774569e3fa3caceaade0920a917468104b556"
MATERIALS = ("IB_BlueSteel", "IB_DeckSteel")


def add(a, b):
    return tuple(x + y for x, y in zip(a, b))


def sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def mul(a, s):
    return tuple(x * s for x in a)


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def cross(a, b):
    return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])


def unit(a):
    n = math.sqrt(dot(a, a))
    if n <= 1e-12:
        raise ValueError("zero direction")
    return mul(a, 1.0/n)


def triangulate_profile(points):
    """Ear clipping only for the authored 12-corner guard cross-section."""
    area=sum(points[i][0]*points[(i+1)%len(points)][1]-points[(i+1)%len(points)][0]*points[i][1]
             for i in range(len(points)))
    order=list(range(len(points))) if area>0 else list(reversed(range(len(points))))
    def turn(a,b,c):return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])
    result=[]
    while len(order)>3:
        for j,b in enumerate(order):
            a,c=order[j-1],order[(j+1)%len(order)]
            if turn(points[a],points[b],points[c])<=1e-12:continue
            if any(all(turn(points[u],points[v],points[p])>=-1e-12 for u,v in ((a,b),(b,c),(c,a)))
                   for p in order if p not in (a,b,c)):continue
            result.append((a,b,c));order.pop(j);break
        else:raise ValueError('authored guard profile cannot triangulate')
    result.append(tuple(order))
    return result


@dataclass
class Part:
    name: str
    group: str
    center: tuple
    size: tuple
    vertices: list = field(default_factory=list)
    faces: list = field(default_factory=list)
    face_materials: list = field(default_factory=list)
    pieces: list = field(default_factory=list)

    def append(self, label, vertices, faces, material, smooth=False):
        first_v, first_f = len(self.vertices), len(self.faces)
        self.vertices.extend(vertices)
        self.faces.extend(tuple(first_v+i for i in face) for face in faces)
        materials = [material]*len(faces) if isinstance(material, str) else material
        assert len(materials) == len(faces)
        self.face_materials.extend(materials)
        self.pieces.append({"name": label, "vertex_start": first_v, "vertex_count": len(vertices),
                            "face_start": first_f, "face_count": len(faces), "smooth_sides": smooth})

    def box(self, label, center, size, material):
        hx, hy, hz = (v/2 for v in size)
        vertices = [add(center, p) for p in ((-hx,-hy,-hz),(hx,-hy,-hz),(hx,hy,-hz),(-hx,hy,-hz),
                                            (-hx,-hy,hz),(hx,-hy,hz),(hx,hy,hz),(-hx,hy,hz))]
        # Six outward faces in Godot's right handed XYZ frame.
        faces = [(0,3,2,1),(4,5,6,7),(0,4,7,3),(1,2,6,5),(0,1,5,4),(3,7,6,2)]
        self.append(label, vertices, faces, material)

    def cylinder(self, label, a, b, radius, material, sides=16):
        axis = unit(sub(b, a))
        ref = (0,1,0) if abs(axis[1]) < .9 else (1,0,0)
        u, v = unit(cross(axis, ref)), None
        v = cross(axis, u)
        rings = []
        for p in (a,b):
            rings.extend(add(p, add(mul(u, radius*math.cos(i*math.tau/sides)),
                                    mul(v, radius*math.sin(i*math.tau/sides)))) for i in range(sides))
        faces = [(i,(i+1)%sides,(i+1)%sides+sides,i+sides) for i in range(sides)]
        faces += [tuple(reversed(range(sides))),tuple(range(sides,2*sides))]
        self.append(label, rings, faces, material, True)

    def profiled_y(self, label, x, z, rings, material, sides=24):
        vertices = [(x+r*math.cos(i*math.tau/sides), y, z+r*math.sin(i*math.tau/sides))
                    for y,r in rings for i in range(sides)]
        # XZ circular order points toward -Y, so reverse side/cap convention.
        faces = []
        for j in range(len(rings)-1):
            a,b = j*sides,(j+1)*sides
            faces.extend((a+i,b+i,b+(i+1)%sides,a+(i+1)%sides) for i in range(sides))
        faces += [tuple(range(sides)),tuple(reversed(range((len(rings)-1)*sides,len(rings)*sides)))]
        self.append(label, vertices, faces, material, True)

    def tube_xy(self, label, path, z, radius, material, sides=12):
        vertices = []
        for i,(x,y) in enumerate(path):
            p0,p3 = path[max(0,i-1)],path[min(len(path)-1,i+1)]
            tangent = unit((p3[0]-p0[0],p3[1]-p0[1],0))
            u,v = (0,0,1),cross(tangent,(0,0,1))
            vertices.extend(add((x,y,z),add(mul(u,radius*math.cos(k*math.tau/sides)),
                                           mul(v,radius*math.sin(k*math.tau/sides)))) for k in range(sides))
        faces=[]
        for i in range(len(path)-1):
            a,b=i*sides,(i+1)*sides
            faces.extend((a+k,a+(k+1)%sides,b+(k+1)%sides,b+k) for k in range(sides))
        faces += [tuple(reversed(range(sides))),tuple(range((len(path)-1)*sides,len(path)*sides))]
        self.append(label,vertices,faces,material,True)

    def ring_xz(self, label, center, ring_radius, tube_radius, material, segments=32, sides=12):
        vertices=[]
        for i in range(segments):
            a=i*math.tau/segments
            for j in range(sides):
                b=j*math.tau/sides
                r=ring_radius+tube_radius*math.cos(b)
                vertices.append(add(center,(r*math.cos(a),tube_radius*math.sin(b),r*math.sin(a))))
        faces=[]
        for i in range(segments):
            for j in range(sides):
                faces.append((i*sides+j,i*sides+(j+1)%sides,((i+1)%segments)*sides+(j+1)%sides,
                              ((i+1)%segments)*sides+j))
        self.append(label,vertices,faces,material,True)

    def folded_guard(self,z):
        # A single closed extrusion, not three coplanar intersecting boxes.
        yz=[(0,-.05),(.05,-.05),(.05,-.033),(.95,-.033),(.95,-.05),(1,-.05),
            (1,.05),(.95,.05),(.95,.033),(.05,.033),(.05,.05),(0,.05)]
        assert sum(yz[i][0]*yz[(i+1)%12][1]-yz[(i+1)%12][0]*yz[i][1] for i in range(12))>0
        vertices=[(x,y,z+dz) for x in (-3,3) for y,dz in yz]
        faces=[(i,(i+1)%12,(i+1)%12+12,i+12) for i in range(12)]
        for a,b,c in triangulate_profile(yz):faces.extend([(c,b,a),(a+12,b+12,c+12)])
        self.append('continuous_folded_guard',vertices,faces,'IB_BlueSteel')

    def tread(self,label,x,z,angle):
        # Real 2.8mm trapezoidal emboss, low tapered slopes; can later bake to a low mesh.
        vertices=[]
        for y,s in ((-.0028,1.0),(0,.70)):
            for u,v in ((-.055,0),(0,-.012),(.055,0),(0,.012)):
                vertices.append((x+s*(u*math.cos(angle)-v*math.sin(angle)),y,
                                 z+s*(u*math.sin(angle)+v*math.cos(angle))))
        faces=[(0,1,2,3),(7,6,5,4),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)]
        self.append(label,vertices,faces,'IB_DeckSteel')


HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
TREAD_PITCH=.26
FLOOR_IDS=('WestLanding','EastLanding','SouthBypass')
RAIL_IDS=('WestOuterRail','EastOuterRail','SouthOuterRail')


def source_layout():
    path=ROOT/'data/v3/terrain/i2_shared_access_layout.json'
    assert hashlib.sha256(path.read_bytes()).hexdigest()==LAYOUT_SHA,'layout changed, reread before construction'
    return json.loads(path.read_text(encoding='utf-8'))


def bounds(part):
    return ([min(v[i] for v in part.vertices) for i in range(3)],
            [max(v[i] for v in part.vertices) for i in range(3)])


def make_floor(name,body,cx,cz,width,length):
    p=Part(name,body,(cx,-.2,cz),(width,.4,length))
    # Continuous load-bearing slab fills all seams below the walking plates.
    p.box('structural_slab',(cx,-.209,cz),(width,.382,length),'IB_BlueSteel')
    rim=.008
    if body=='WestLanding':
        # Existing guard is 100mm wide: a full-height shoulder supports its foot.
        p.box('guard_bearing_shoulder',(cx-width/2+.05,-.009,cz),(.1,.018,length),'IB_BlueSteel')
    elif body=='EastLanding':
        p.box('guard_bearing_shoulder',(cx+width/2-.05,-.009,cz),(.1,.018,length),'IB_BlueSteel')
    if cz+length/2>14.79:
        shift=.05 if body=='WestLanding' else (-.05 if body=='EastLanding' else 0)
        p.box('south_guard_bearing',(cx+shift,-.009,cz+length/2-.05),(width-(.1 if body!='SouthBypass' else 0),.018,.1),'IB_BlueSteel')
    # Flush perimeter trim is below the original top; there is no added curb.
    for x in (cx-width/2+rim/2,cx+width/2-rim/2):
        p.box('side_edge_trim',(x,-.0098,cz),(rim,.0152,length),'IB_DeckSteel')
    for z in (cz-length/2+rim/2,cz+length/2-rim/2):
        p.box('end_edge_trim',(cx,-.0098,z),(width-2*rim,.0152,rim),'IB_DeckSteel')
    # Real-size plates, last plate takes exact residual. No scaled UV/model.
    nx=max(1,round((width-2*rim)/1.65));nz=max(1,round((length-2*rim)/1.6))
    cellx=(width-2*rim)/nx;cellz=(length-2*rim)/nz;gap=.004
    for ix in range(nx):
        for iz in range(nz):
            x0=cx-width/2+rim+ix*cellx+gap/2;x1=x0+cellx-gap
            z0=cz-length/2+rim+iz*cellz+gap/2;z1=z0+cellz-gap
            p.box('walking_plate_%d_%d'%(ix,iz),((x0+x1)/2,-.0104,(z0+z1)/2),
                  (x1-x0,.0152,z1-z0),'IB_DeckSteel')
            # 260mm pitch, between P4 200mm and rejected P1 380mm.
            startx=math.ceil((x0+.085)/TREAD_PITCH);endx=math.floor((x1-.085)/TREAD_PITCH)
            startz=math.ceil((z0+.085)/TREAD_PITCH);endz=math.floor((z1-.085)/TREAD_PITCH)
            for tx in range(startx,endx+1):
                for tz in range(startz,endz+1):
                    p.tread('tread_%d_%d'%(tx,tz),tx*TREAD_PITCH,tz*TREAD_PITCH,
                            (1 if (tx+tz)%2 else -1)*math.pi/4)
            # Four low steel fixings per plate: within the old top plane.
            for bx in (x0+.045,x1-.045):
                for bz in (z0+.045,z1-.045):
                    p.cylinder('plate_fixing',(bx,-.0028,bz),(bx,-.0009,bz),.013,'IB_DeckSteel',8)
    return p


def make_guard(name,body,center,length,axis):
    size=(.1,1,length) if axis==2 else (length,1,.1)
    p=Part(name,body,center,size)
    # Reuse the continuous closed P4 folded profile, then rigidly reorient it.
    temp=Part('profile','', (0,.5,0),(6,1,.1));temp.folded_guard(0)
    local=[]
    for x,y,z in temp.vertices:
        along=x*length/6
        local.append((center[0]+z, y,center[2]-along) if axis==2 else (center[0]+along,y,center[2]+z))
    p.append('continuous_folded_guard',local,temp.faces,'IB_BlueSteel')
    # Broad sheet bays, not dozens of decorative posts. All are within 100mm.
    count=max(1,math.ceil(length/1.8))
    for i in range(count+1):
        along=-length/2+.035+(length-.07)*i/count
        for side in (-1,1):
            c=(center[0]+side*.038,.5,center[2]+along) if axis==2 else (center[0]+along,.5,center[2]+side*.038)
            s=(.01,.90,.038) if axis==2 else (.038,.90,.01)
            p.box('shallow_stiffener',c,s,'IB_BlueSteel')
            for y in (.10,.90):
                a=(center[0]+side*.043,y,center[2]+along) if axis==2 else (center[0]+along,y,center[2]+side*.043)
                b=(center[0]+side*.048,y,center[2]+along) if axis==2 else (center[0]+along,y,center[2]+side*.048)
                p.cylinder('recessed_fastener',a,b,.012,'IB_DeckSteel',8)
    return p


def build_parts(layout=None):
    layout=layout or source_layout();by_id={r['id']:r for r in layout['fixed']}
    parts=[]
    for body,lengths in [('WestLanding',[4,4,4,4.8]),('EastLanding',[4,4,4,4.5])]:
        spec=by_id[body];cx=spec['center'][0]-ORIGIN[0];width=spec['size'][0]
        start=spec['center'][2]-spec['size'][2]/2
        rail='WestOuterRail' if body=='WestLanding' else 'EastOuterRail'
        rx=by_id[rail]['center'][0]-ORIGIN[0]
        for index,length in enumerate(lengths):
            cz=start+length/2
            parts.append(make_floor(body+'_%02d'%(index+1),body,cx,cz,width,length))
            parts.append(make_guard(rail+'_%02d'%(index+1),rail,(rx,.5,cz),length,2))
            start+=length
    for i in range(2):
        parts.append(make_floor('SouthBypass_%02d'%(i+1),'SouthBypass',-1.5+3*i,13.1,3,3.4))
    # Southern rail spans three floors. Three distinct lengths; no duplicated rail.
    for i,(start,length) in enumerate([(-6.5,3.5),(-3,6),(3,3.3)]):
        parts.append(make_guard('SouthOuterRail_%02d'%(i+1),'SouthOuterRail',(start+length/2,.5,14.75),length,0))
    return parts


def audit(parts,layout=None):
    layout=layout or source_layout();by_id={r['id']:r for r in layout['fixed']}
    checks=[];rows=[]
    def ck(label,passed,detail=None):
        checks.append({'label':label,'passed':bool(passed),'detail':detail})
    for p in parts:
        lo,hi=bounds(p);spec=by_id[p.group]
        slo=[spec['center'][i]-ORIGIN[i]-spec['size'][i]/2 for i in range(3)]
        shi=[spec['center'][i]-ORIGIN[i]+spec['size'][i]/2 for i in range(3)]
        ck(p.name+' fits only its original body',all(lo[i]>=slo[i]-1e-8 and hi[i]<=shi[i]+1e-8 for i in range(3)))
        piece_valid=True
        for piece in p.pieces:
            faces=p.faces[piece['face_start']:piece['face_start']+piece['face_count']]
            edges=Counter(tuple(sorted((f[j],f[(j+1)%len(f)]))) for f in faces for j in range(len(f)))
            volume=0
            for f in faces:
                for j in range(1,len(f)-1):volume+=dot(p.vertices[f[0]],cross(p.vertices[f[j]],p.vertices[f[j+1]]))/6
            piece_valid &= all(v==2 for v in edges.values()) and volume>1e-12
        ck(p.name+' construction pieces closed outward',piece_valid)
        rows.append({'name':p.name,'body':p.group,'center_local_godot':p.center,'size':p.size,
                     'bounds_min':lo,'bounds_max':hi,'triangles':sum(len(f)-2 for f in p.faces),
                     'construction_pieces':len(p.pieces),'treads':sum(q['name'].startswith('tread_') for q in p.pieces)})
    floors=[p for p in parts if p.group in FLOOR_IDS]
    for body in FLOOR_IDS:
        group=[p for p in floors if p.group==body]
        area=sum(p.size[0]*p.size[2] for p in group)
        ck(body+' exact area',abs(area-by_id[body]['size'][0]*by_id[body]['size'][2])<1e-8,area)
        for i,p in enumerate(group):
            for q in group[i+1:]:
                a,b=bounds(p);c,d=bounds(q)
                area_overlap=max(0,min(b[0],d[0])-max(a[0],c[0]))*max(0,min(b[2],d[2])-max(a[2],c[2]))
                ck(p.name+'/'+q.name+' no doubled walking top',area_overlap<1e-8)
    ck('exact floor area 136.98 m2',abs(sum(p.size[0]*p.size[2] for p in floors)-136.98)<1e-8)
    ck('ten floor modules plus eleven guard modules',len(floors)==10 and len(parts)==21)
    ck('only original six floor/rail body groups',set(p.group for p in parts)==set(FLOOR_IDS+RAIL_IDS))
    ck('no model part below original slab bottom',min(r['bounds_min'][1] for r in rows)>=-.40000001)
    # Existing moving deck interfaces remain free above the slab.
    for center_z in (0,8):
        for x in (-3,3):
            obstructed=False
            for p in parts:
                if p.group not in RAIL_IDS:continue
                lo,hi=bounds(p)
                obstructed |= lo[0]-1e-8<=x<=hi[0]+1e-8 and max(lo[2],center_z-1.7)<min(hi[2],center_z+1.7)
            ck('inner bridge connection x%s z%s remains unrailed'%(x,center_z),not obstructed)
    return {'check_count':len(checks),'failed':sum(not c['passed'] for c in checks),'checks':checks,
            'mesh_count':len(parts),'triangles_pre_bevel':sum(r['triangles'] for r in rows),
            'tread_count':sum(r['treads'] for r in rows),'tread_pitch_m':TREAD_PITCH,'parts':rows,
            'scope':'Pure source primitive closure / envelopes / exact areas; not a whole-mesh intersection or engine sweep proof.'}


if __name__=='__main__':
    report=audit(build_parts())
    (HERE/'geometry_static_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:report[k] for k in ('check_count','failed','mesh_count','triangles_pre_bevel','tread_count')}))
    raise SystemExit(bool(report['failed']))

