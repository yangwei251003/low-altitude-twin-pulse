"""P4: same P2 body, only extend two 20mm construction channels to/over top.
Pure deterministic data; no Blender import. Original P2 source is read-only.
"""
from pathlib import Path
import sys,importlib.util
sys.dont_write_bytecode=True
P2=Path(__file__).resolve().parent.parent/'p2'
spec=importlib.util.spec_from_file_location('p4_readonly_p2_shape',P2/'shape_profile.py')
old=importlib.util.module_from_spec(spec);spec.loader.exec_module(old)
FIXINGS=old.FIXINGS;PATCH=old.PATCH;TOP_NOTCHES=old.TOP_NOTCHES
SEAMS=[(-1.10,-1.08),(.78,.80)]

def is_seam(x):return any(a<x<b for a,b in SEAMS)

def body_mesh_data():
    xs=sorted(set([-2,-1.10,-1.08,.78,.80,2]+[a+d for a,b in FIXINGS for d in [-.105,.105]]+
                  [p[0] for p in PATCH]+[x for profile in TOP_NOTCHES for x,d in profile]))
    ys=sorted(set([-2.8,-2.77,-.14,-.014,0]+[b+d for a,b in FIXINGS for d in [-.105,.105]]+[p[1] for p in PATCH]))
    verts=[];faces=[];indices=[];lookup={}
    def vertex(p):
        p=old.deform(p);key=tuple(round(v,8) for v in p)
        if key not in lookup:lookup[key]=len(verts);verts.append(p)
        return lookup[key]
    def face(ps,mat=0):faces.append(tuple(vertex(p) for p in ps));indices.append(mat)
    def dep(x,y):
        if any(abs(x-a)<.105 and abs(y-b)<.105 for a,b in FIXINGS):return -.035
        if -2.77<y<0 and is_seam(x):return -.014
        return 0.
    ni=len(xs)-1;nj=len(ys)-1;depths={}
    for i,(a,b) in enumerate(zip(xs,xs[1:])):
        for j,(c,d) in enumerate(zip(ys,ys[1:])):
            if is_seam((a+b)/2) and c>=-.014:continue
            z=dep((a+b)/2,(c+d)/2);depths[i,j]=z
            zone=0 if (a+b)/2 < -1.09 else 1 if (a+b)/2 < .79 else 2
            face([(a,c,z),(b,c,z),(b,d,z),(a,d,z)],3 if z==-.014 else zone)
    # One hidden planar back retains all original outer segments plus actual
    # top-channel steps; avoid disconnected caps or nonmatching side edges.
    back=[(xs[0],y,-.35) for y in ys]
    current_y=0.
    for i,(a,b) in enumerate(zip(xs,xs[1:])):
        top_y=-.014 if is_seam((a+b)/2) else 0.
        if top_y!=current_y:back.append((a,top_y,-.35))
        back.append((b,top_y,-.35));current_y=top_y
    back += [(xs[-1],y,-.35) for y in reversed(ys[:-1])]
    back += [(x,ys[0],-.35) for x in reversed(xs[1:-1])]
    face(back)
    for (i,j),z in depths.items():
        a,b=xs[i:i+2];c,d=ys[j:j+2]
        if (i+1,j) in depths:
            other=depths[i+1,j]
            if other!=z:face([(b,c,z),(b,d,z),(b,d,other),(b,c,other)])
        else:face([(b,c,z),(b,d,z),(b,d,-.35),(b,c,-.35)])
        if (i-1,j) not in depths:face([(a,c,-.35),(a,d,-.35),(a,d,z),(a,c,z)])
        if (i,j+1) in depths:
            other=depths[i,j+1]
            if other!=z:face([(a,d,z),(b,d,z),(b,d,other),(a,d,other)])
        else:face([(a,d,-.35),(b,d,-.35),(b,d,z),(a,d,z)],3 if is_seam((a+b)/2) else 0)
        if (i,j-1) not in depths:face([(a,c,z),(b,c,z),(b,c,-.35),(a,c,-.35)])
    return verts,faces,indices
