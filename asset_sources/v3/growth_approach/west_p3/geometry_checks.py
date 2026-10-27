"""Per-mesh strict triangle crossing, with double-precision plane rejection.

BVH is only broadphase. Non-coplanar triangles must straddle each other's
planes; one-sided triangles merely touching a plane are NOT penetration.
Coplanar pairs use clipped positive intersection AREA, including adjacent
folded polygons. Deliberate inter-object root/stone embedding is excluded.
"""
from mathutils.bvhtree import BVHTree

def sub(a,b):return tuple(a[k]-b[k] for k in range(3))
def dot(a,b):return sum(a[k]*b[k] for k in range(3))
def cross(a,b):return (a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])
def normal(t):
    n=cross(sub(t[1],t[0]),sub(t[2],t[0]));length=dot(n,n)**.5
    return tuple(v/length for v in n) if length>1e-13 else None
def orient(a,b,c):return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])

def area_overlap(a,b,n):
    drop=max(range(3),key=lambda k:abs(n[k]));axes=[k for k in range(3) if k!=drop]
    a=[tuple(p[k] for k in axes) for p in a];b=[tuple(p[k] for k in axes) for p in b]
    winding=1 if orient(*b)>0 else -1
    for r,s in zip(b,b[1:]+b[:1]):
        out=[]
        for p,q in zip(a,a[1:]+a[:1]):
            dp=winding*orient(r,s,p);dq=winding*orient(r,s,q)
            if dp>=-1e-12:out.append(p)
            if (dp>1e-12 and dq<-1e-12) or (dp<-1e-12 and dq>1e-12):
                t=dp/(dp-dq);out.append(tuple(p[k]+(q[k]-p[k])*t for k in range(2)))
        a=out
        if len(a)<3:return False
    area=abs(sum(p[0]*q[1]-q[0]*p[1] for p,q in zip(a,a[1:]+a[:1])))*.5
    return area>1e-10

def inside(p,t,n):
    signs=[dot(cross(sub(b,a),sub(p,a)),n) for a,b in zip(t,t[1:]+t[:1])]
    return min(signs)>=-1e-9 or max(signs)<=1e-9

def strict_cross(a,b,shared):
    na=normal(a);nb=normal(b)
    if na is None or nb is None:return False,False
    da=[dot(sub(p,b[0]),nb) for p in a];db=[dot(sub(p,a[0]),na) for p in b]
    if abs(dot(na,nb))>1-1e-9 and max(abs(v) for v in da+db)<2e-7:
        return area_overlap(a,b,na),True
    if shared>=2:return False,False
    # Proper penetration, not a point or edge touching an adjacent cut plane.
    if min(da)>=-1e-7 or max(da)<=1e-7 or min(db)>=-1e-7 or max(db)<=1e-7:return False,False
    for tri,dist,other,n in [(a,da,b,nb),(b,db,a,na)]:
        for i in range(3):
            j=(i+1)%3
            if dist[i]*dist[j]>=-1e-16:continue
            t=dist[i]/(dist[i]-dist[j])
            p=tuple(tri[i][k]+(tri[j][k]-tri[i][k])*t for k in range(3))
            if inside(p,other,n):return True,False
    return False,False

def strict_self_intersections(ob,limit=24):
    ob.data.calc_loop_triangles()
    vectors=[ob.matrix_world@v.co for v in ob.data.vertices]
    vertices=[tuple(float(v) for v in p) for p in vectors]
    triangles=[tuple(t.vertices) for t in ob.data.loop_triangles]
    tree=BVHTree.FromPolygons(vectors,triangles,all_triangles=True,epsilon=0)
    pairs=tree.overlap(tree);found=[];tested=0;total=0
    for i,j in pairs:
        if i>=j:continue
        shared=len(set(triangles[i])&set(triangles[j]))
        a=[vertices[k] for k in triangles[i]];b=[vertices[k] for k in triangles[j]]
        yes,coplanar=strict_cross(a,b,shared);tested+=1
        if yes:
            total+=1
            if len(found)<limit:found.append({'triangles':[i,j],'coplanar':coplanar,'shared_vertices':shared})
    return {'mesh':ob.name,'triangles':len(triangles),'broadphase_pairs':len(pairs),'pairs_checked':tested,
            'strict_crossing_count':total,'examples':found,'scope':'within one mesh; contacts and deliberate cross-object root embedding excluded'}
