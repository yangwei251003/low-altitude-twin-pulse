"""Deterministic P2 local damage only; pure data, no Blender execution.

All coordinates are source-local Godot XYZ. The old stepped closed core is
retained; shared vertices receive the same small inward deformation. No global
shape/noise change, no water-side protrusion, no change to bolt positions.
"""
import math

FIXINGS = [(-1.55, -.65), (.38, -.89)]
PATCH = [(1.00,-1.57),(1.16,-1.47),(1.28,-1.53),(1.52,-1.43),
         (1.68,-1.63),(1.61,-1.81),(1.76,-1.99),(1.60,-2.23),
         (1.32,-2.30),(1.14,-2.11),(1.00,-1.97)]
TOP_NOTCHES = [[(-1.70,0),(-1.54,.014),(-1.47,.024),(-1.34,0)],
               [(1.62,0),(1.73,.032),(1.82,.018),(1.94,0)]]
AGGREGATES = [(1.13,-1.70,.030,.023,0.18),
              (1.32,-1.61,.047,.031,-0.24),
              (1.55,-1.70,.035,.048,0.57),
              (1.62,-1.99,.044,.027,-0.41),
              (1.43,-2.14,.029,.042,0.13),
              (1.18,-1.96,.040,.027,0.66)]

def clamp(v): return max(0.,min(1.,v))

def patch_weight(x,y):
    inside=False;dist=100.
    for a,b in zip(PATCH,PATCH[1:]+PATCH[:1]):
        dx=b[0]-a[0];dy=b[1]-a[1]
        t=clamp(((x-a[0])*dx+(y-a[1])*dy)/(dx*dx+dy*dy))
        dist=min(dist,math.hypot(x-a[0]-t*dx,y-a[1]-t*dy))
        if (a[1]>y)!=(b[1]>y) and x < (b[0]-a[0])*(y-a[1])/(b[1]-a[1])+a[0]:inside=not inside
    if not inside:return 0.
    # A 3cm irregular but deterministic broken perimeter, not a circular stamp.
    t=clamp(dist/.03);return t*t*(3-2*t)

def patch_depth(x,y):
    w=patch_weight(x,y)
    return w*(.009+.0025*math.sin((x-1.0)*14)*math.sin((y+2.3)*11))

def notch_depth(x):
    for profile in TOP_NOTCHES:
        for (a,da),(b,db) in zip(profile,profile[1:]):
            if a<=x<=b:return da+(db-da)*(x-a)/(b-a)
    return 0.

def deform(p):
    x,y,z=p;front=clamp((z+.12)/.12)
    return (x,y-notch_depth(x)*front*clamp((y+.14)/.14),z-patch_depth(x,y)*front)

def body_mesh_data():
    xs=sorted(set([-2,-1.10,-1.08,.78,.80,2]+[a+d for a,b in FIXINGS for d in [-.105,.105]]+
                  [p[0] for p in PATCH]+[x for profile in TOP_NOTCHES for x,d in profile]))
    ys=sorted(set([-2.8,-2.77,-.14,0]+[b+d for a,b in FIXINGS for d in [-.105,.105]]+
                  [p[1] for p in PATCH]))
    verts=[];faces=[];indices=[];lookup={}
    def vertex(p):
        p=deform(p);key=tuple(round(v,8) for v in p)
        if key not in lookup:lookup[key]=len(verts);verts.append(p)
        return lookup[key]
    def face(ps,mat=0):faces.append(tuple(vertex(p) for p in ps));indices.append(mat)
    def dep(x,y):
        if any(abs(x-a)<.105 and abs(y-b)<.105 for a,b in FIXINGS):return -.035
        if -2.77<y<-.14 and (-1.10<x<-1.08 or .78<x<.80):return -.014
        return 0.
    depths={}
    for i,(a,b) in enumerate(zip(xs,xs[1:])):
        for j,(c,d) in enumerate(zip(ys,ys[1:])):
            z=dep((a+b)/2,(c+d)/2);depths[i,j]=z
            zone=0 if (a+b)/2 < -1.09 else 1 if (a+b)/2 < .79 else 2
            face([(a,c,z),(b,c,z),(b,d,z),(a,d,z)],3 if z==-.014 else zone)
    # The dry-bank back stays flat: retain every boundary segment, without
    # duplicating the local repair sampling lattice across this hidden plane.
    back=[(xs[0],y,-.35) for y in ys]
    back += [(x,ys[-1],-.35) for x in xs[1:]]
    back += [(xs[-1],y,-.35) for y in reversed(ys[:-1])]
    back += [(x,ys[0],-.35) for x in reversed(xs[1:-1])]
    face(back)
    ni=len(xs)-1;nj=len(ys)-1
    for i in range(ni):
        for j in range(nj):
            a,b=xs[i:i+2];c,d=ys[j:j+2];z=depths[i,j]
            if i+1<ni:
                other=depths[i+1,j]
                if other!=z:face([(b,c,z),(b,d,z),(b,d,other),(b,c,other)])
            if j+1<nj:
                other=depths[i,j+1]
                if other!=z:face([(a,d,z),(b,d,z),(b,d,other),(a,d,other)])
            if i==0:face([(a,c,-.35),(a,d,-.35),(a,d,z),(a,c,z)])
            if i==ni-1:face([(b,c,z),(b,d,z),(b,d,-.35),(b,c,-.35)])
            if j==0:face([(a,c,z),(b,c,z),(b,c,-.35),(a,c,-.35)])
            if j==nj-1:face([(a,d,-.35),(b,d,-.35),(b,d,z),(a,d,z)])
    return verts,faces,indices

def aggregate_mesh_data(surface_samples=None):
    verts=[];faces=[];records=[]
    ring=[(-.52,-.20),(-.14,-.53),(.49,-.28),(.40,.37),(-.32,.49)]
    for i,(x,y,w,h,angle) in enumerate(AGGREGATES):
        surface=-patch_depth(x,y) if surface_samples is None else surface_samples[i]
        back=surface-.010;front=min(-.0015,surface+.0045)
        assert patch_weight(x,y)>.8 and back<surface<front<0
        start=len(verts);co=math.cos(angle);si=math.sin(angle)
        for z in [back,front-.002]:
            for u,v in ring:
                dx=u*w;dy=v*h;verts.append((x+dx*co-dy*si,y+dx*si+dy*co,z))
        verts.append((x+.07*w,y-.05*h,front))
        faces.append(tuple(start+k for k in range(4,-1,-1)))
        for k in range(5):
            j=(k+1)%5;faces.append((start+k,start+j,start+5+j,start+5+k));faces.append((start+5+k,start+5+j,start+10))
        records.append({'index':i,'center_xy':[x,y],'width_height_m':[w,h],'body_surface_z':surface,'back_z':back,'front_z':front,'exposed_at_center_m':front-surface})
    return verts,faces,records
