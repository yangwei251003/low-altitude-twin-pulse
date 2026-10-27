"""Editable bridge components in Godot metres; pure Python, no scene side effects.

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
MATERIALS = ("IB_BlueSteel", "IB_DeckSteel", "IB_DarkSteel", "IB_BurnishedSteel", "IB_OchreGrip")


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


def _guard(part):
    z=part.center[2]
    part.folded_guard(z)
    # Raised stiffening strips and bolts remain in the existing 100mm envelope.
    for x in (-2.965,-2,-1,0,1,2,2.965):
        for sign in (-1,1):
            part.box("rib_%s_%s"%(x,sign),(x,.5,z+sign*.038),(.045,.9,.01),"IB_BlueSteel")
            for y in (.09,.91):
                part.cylinder("fastener_%s_%s_%s"%(x,y,sign),(x,y,z+sign*.043),
                              (x,y,z+sign*.05),.014,"IB_BurnishedSteel",8)


def _carriage(part):
    x=part.center[0]
    part.box("longitudinal_bogie_frame",(x,-.410,0),(.20,.12,1.20),"IB_DarkSteel")
    for z in (-.38,.38):
        # Steel rail wheels, fixed axles along X, travel along Z. No swivel casters.
        part.cylinder("wheel_%s"%z,(x-.074,-.58,z),(x+.074,-.58,z),.18,"IB_DarkSteel",24)
        for sign in (-1,1):
            part.cylinder("running_rim_%s_%s"%(z,sign),(x+sign*.065,-.58,z),
                          (x+sign*.080,-.58,z),.174,"IB_BurnishedSteel",24)
            part.cylinder("axle_boss_%s_%s"%(z,sign),(x+sign*.079,-.58,z),
                          (x+sign*.11,-.58,z),.067,"IB_DarkSteel",16)
            part.cylinder("axle_cap_%s_%s"%(z,sign),(x+sign*.109,-.58,z),
                          (x+sign*.12,-.58,z),.035,"IB_BurnishedSteel",8)


def build_parts(layout):
    parts={}
    for group in ("moving","pin_parts"):
        for row in layout[group]:
            parts[row['id']]=Part(row['id'],group,sub(row['center'],ORIGIN),tuple(row['size']))
    assert len(parts)==12
    deck=parts['BridgeDeck']
    deck.box('continuous_structural_deck',(0,-.178,0),(6,.344,3.4),
             ['IB_BlueSteel','IB_BlueSteel','IB_BlueSteel','IB_BlueSteel','IB_DarkSteel','IB_DeckSteel'])
    # Root-authorized P3 connection repair only: 6mm steel bearing shoulders
    # close the P2 daylight gap beneath both guard feet, within the same deck.
    # No additional runtime part; lower faces contact the structural core.
    for z in (-1.65,1.65):
        deck.box('guard_bearing_shoulder_%s'%z,(0,-.003,z),(6,.006,.10),'IB_BlueSteel')
    # Six 3.2mm raised deck sheets with real 4mm seams over an unbroken structural core.
    # Sheet top -.0028, emboss crest 0: nothing rises above the original collision plane.
    for i in range(6):
        deck.box('deck_sheet_%d'%i,(-2.5+i,-.0044,0),(.996,.0032,3.196),'IB_DeckSteel')
    for ix in range(29):
        x=-2.8+ix*.20
        for iz in range(15):
            z=-1.4+iz*.20
            # Keep a quiet clean seam strip; do not place emboss across plate joints.
            if abs(x-round(x))<.065:continue
            deck.tread('emboss_%d_%d'%(ix,iz),x,z,(1 if (ix+iz)%2 else -1)*math.pi/4)
    for name in ('NorthGuard','SouthGuard'):
        _guard(parts[name])
    for name in ('WestCarriage','EastCarriage'):
        _carriage(parts[name])
    handle=parts['BridgeHandle']
    # Rounded U grip; lower ends meet the real guard top at local Y=1.
    path=[(-2.632,1.018),(-2.632,1.150)]
    path += [(-2.600+.032*math.cos(a),1.150+.032*math.sin(a))
             for a in (math.pi-math.pi*k/8 for k in range(1,5))]
    path += [(-2.400,1.182)]
    path += [(-2.400+.032*math.cos(a),1.150+.032*math.sin(a))
             for a in (math.pi/2-math.pi*k/8 for k in range(1,5))]
    path += [(-2.368,1.018)]
    handle.tube_xy('manual_push_pull_grip',path,-1.65,.018,'IB_OchreGrip')
    for x in (-2.632,-2.368):
        handle.box('grip_foot_%s'%x,(x,1.009,-1.65),(.036,.018,.10),'IB_DarkSteel')
    for name in ('PinBracketLeft','PinBracketRight','PinBracketFront','PinBracketBack'):
        p=parts[name]
        p.box('guide_frame_segment',p.center,p.size,'IB_DarkSteel')
    rod=parts['LockRod']
    rod.profiled_y('independent_telescoping_rod',2.4,-1.9,
                   [(-.70,.034),(-.683,.05),(.38,.05),(.40,.044)],'IB_BurnishedSteel')
    grip=parts['LockGrip']
    grip.cylinder('grip_hub',(2.4,.40,-1.9),(2.4,.525,-1.9),.045,'IB_BurnishedSteel',20)
    grip.ring_xz('compact_low_lock_handle',(2.4,.525,-1.9),.125,.025,'IB_OchreGrip')
    for dx in (-.085,.085):
        grip.box('grip_spoke_%s'%dx,(2.4+dx,.515,-1.9),(.10,.025,.028),'IB_OchreGrip')
    return list(parts.values())


def load_layout():
    path=Path(__file__).with_name('layout_intake.json')
    raw=path.read_bytes()
    if hashlib.sha256(raw).hexdigest()!=LAYOUT_SHA:
        raise ValueError('frozen p3 layout bytes changed')
    return json.loads(raw)


def triangles(part):
    for f in part.faces:
        for i in range(1,len(f)-1):
            yield f[0],f[i],f[i+1]


def measure(parts):
    records=[]
    all_vertices=[]
    for p in parts:
        lo=[min(v[i] for v in p.vertices) for i in range(3)]
        hi=[max(v[i] for v in p.vertices) for i in range(3)]
        expected_lo=[p.center[i]-p.size[i]/2 for i in range(3)]
        expected_hi=[p.center[i]+p.size[i]/2 for i in range(3)]
        overshoot=max([expected_lo[i]-lo[i] for i in range(3)]+[hi[i]-expected_hi[i] for i in range(3)]+[0])
        if overshoot>1e-8:
            raise ValueError('%s exceeds original envelope by %.9fm'%(p.name,overshoot))
        if len(p.face_materials)!=len(p.faces) or any(m not in MATERIALS for m in p.face_materials):
            raise ValueError('material face indexing')
        volumes=[]
        for piece in p.pieces:
            faces=p.faces[piece['face_start']:piece['face_start']+piece['face_count']]
            edges=Counter(tuple(sorted((f[i],f[(i+1)%len(f)]))) for f in faces for i in range(len(f)))
            directed=Counter((f[i],f[(i+1)%len(f)]) for f in faces for i in range(len(f)))
            assert all(n==2 for n in edges.values()),(p.name,piece['name'],'boundary/nonmanifold')
            assert all(directed.get((b,a),0)==n for (a,b),n in directed.items()),(p.name,piece['name'],'winding')
            volume=0
            for f in faces:
                for i in range(1,len(f)-1):
                    a,b,c=(p.vertices[k] for k in (f[0],f[i],f[i+1]))
                    assert dot(cross(sub(b,a),sub(c,a)),cross(sub(b,a),sub(c,a)))>1e-20
                    volume+=dot(a,cross(b,c))/6
            assert volume>1e-10,(p.name,piece['name'],'nonpositive volume',volume)
            volumes.append(volume)
        records.append({'name':p.name,'group':p.group,'center':p.center,'source_size':p.size,
                        'actual_min':lo,'actual_max':hi,'max_envelope_overshoot_m':overshoot,
                        'vertices':len(p.vertices),'triangles':sum(len(f)-2 for f in p.faces),
                        'closed_construction_pieces':len(p.pieces),'min_piece_signed_volume':min(volumes),
                        'materials':sorted(set(p.face_materials))})
        all_vertices.extend(p.vertices)
    assert {p.name for p in parts}=={'BridgeDeck','NorthGuard','SouthGuard','WestCarriage','EastCarriage',
        'BridgeHandle','PinBracketLeft','PinBracketRight','PinBracketFront','PinBracketBack','LockRod','LockGrip'}
    # Original guide aperture 160mm squared, rod diameter100mm: 30mm each side through full .3m stroke.
    gap_x=(parts_by_name(parts)['PinBracketRight'].center[0]-.07)-(parts_by_name(parts)['PinBracketLeft'].center[0]+.07)
    gap_z=(-1.76-.06)-(-2.02+.04)
    assert abs(gap_x-.16)<1e-8 and abs(gap_z-.16)<1e-8
    return {'scope':'pure mesh-data construction only; Blender/import/visual/actual collision not executed',
            'layout_sha256':LAYOUT_SHA,'mesh_count':len(parts),'material_count':len(MATERIALS),
            'triangles_before_bevel':sum(r['triangles'] for r in records),
            'bounds_min':[min(v[i] for v in all_vertices) for i in range(3)],
            'bounds_max':[max(v[i] for v in all_vertices) for i in range(3)],
            'pin_guide_radial_clearance_m':.03,'pin_travel_m':.3,'parts':records,
            'limits':['Closed construction pieces can intersect at intentional welds/fasteners.',
                      'No claim of globally Boolean-unioned manifold or no triangle self-intersections.',
                      'UV is source procedural projection, not a unique baked atlas.',
                      'No runtime GLB, Godot import, collision sweep or camera evidence yet.']}


def parts_by_name(parts):
    return {p.name:p for p in parts}


if __name__=='__main__':
    print(json.dumps(measure(build_parts(load_layout())),indent=2))
