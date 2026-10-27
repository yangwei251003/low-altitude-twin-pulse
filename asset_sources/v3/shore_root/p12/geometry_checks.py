"""Strict per-mesh triangle-crossing audit, including coplanar folded faces.

Adjacent triangles sharing a mesh vertex are excluded; contact between separate
stone/root objects is intentionally outside this self-intersection check.
"""
from mathutils.bvhtree import BVHTree
from mathutils.geometry import intersect_ray_tri

def strict_self_intersections(ob,limit=25,include_coplanar=True):
    ob.data.calc_loop_triangles()
    vertices=[ob.matrix_world@v.co for v in ob.data.vertices]
    triangles=[tuple(t.vertices) for t in ob.data.loop_triangles]
    # Blender overlap misses coplanar containment even with a small epsilon;
    # it is only used for transverse candidates. Independent AABB bins below
    # cover coplanar candidates rather than trusting this API for both.
    tree=BVHTree.FromPolygons(vertices,triangles,all_triangles=True,epsilon=0)
    candidates=tree.overlap(tree);found=[];tested=0;one_sided_contacts=[]
    def plane_distances(tri,other):
        # Use Python double arithmetic, not a float32 Vector dot. A triangle
        # wholly in one half-space can touch this plane but cannot cross it.
        u=[float(tri[1][k])-float(tri[0][k]) for k in range(3)]
        v=[float(tri[2][k])-float(tri[0][k]) for k in range(3)]
        n=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]]
        length=sum(x*x for x in n)**.5
        return [sum((float(p[k])-float(tri[0][k]))*n[k] for k in range(3))/length for p in other]
    def orient(a,b,c):return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])
    def strict_inside(p,tri):
        values=[orient(a,b,p) for a,b in zip(tri,tri[1:]+tri[:1])]
        return min(values)>1e-10 or max(values)<-1e-10
    for i,j in candidates:
        if i>=j or set(triangles[i])&set(triangles[j]):continue
        a=[vertices[k] for k in triangles[i]];b=[vertices[k] for k in triangles[j]]
        na=(a[1]-a[0]).cross(a[2]-a[0]);nb=(b[1]-b[0]).cross(b[2]-b[0])
        if na.length<1e-12 or nb.length<1e-12:continue
        na.normalize();nb.normalize();tested+=1;crossing=False;coplanar=False
        if abs(na.dot(nb))>1-1e-6 and max(abs((p-a[0]).dot(na)) for p in b)<1e-6:
            coplanar=True;drop=max(range(3),key=lambda k:abs(na[k]));axes=[k for k in range(3) if k!=drop]
            aa=[tuple(p[k] for k in axes) for p in a];bb=[tuple(p[k] for k in axes) for p in b]
            crossing=any(strict_inside(p,bb) for p in aa) or any(strict_inside(p,aa) for p in bb)
            if not crossing:
                for p,q in zip(aa,aa[1:]+aa[:1]):
                    for r,s in zip(bb,bb[1:]+bb[:1]):
                        if orient(p,q,r)*orient(p,q,s)<-1e-16 and orient(r,s,p)*orient(r,s,q)<-1e-16:crossing=True
        else:
            sides_a=plane_distances(a,b);sides_b=plane_distances(b,a)
            if not (min(sides_a)<0<max(sides_a) and min(sides_b)<0<max(sides_b)):
                if len(one_sided_contacts)<25:
                    one_sided_contacts.append({'triangles':[i,j],'other_to_plane_m':[sides_a,sides_b]})
                continue
            for tri,other in [(a,b),(b,a)]:
                for p,q in zip(tri,tri[1:]+tri[:1]):
                    d=q-p;length=d.length
                    if length<1e-8:continue
                    hit=intersect_ray_tri(other[0],other[1],other[2],d,p,True)
                    if hit is not None:
                        t=(hit-p).dot(d)/(length*length)
                        if 1e-6<t<1-1e-6:crossing=True;break
                if crossing:break
        if crossing:
            found.append({'triangles':[i,j],'coplanar':coplanar})
            if len(found)>=limit:break
    coplanar_report=None
    if include_coplanar and len(found)<limit:
        from coplanar_checks import coplanar_overlaps
        coplanar_report=coplanar_overlaps(vertices,triangles,limit-len(found))
        known={tuple(sorted(row['triangles'])) for row in found}
        found.extend(row for row in coplanar_report['overlaps'] if tuple(sorted(row['triangles'])) not in known)
    return {'mesh':ob.name,'triangle_count':len(triangles),'broadphase_pairs':len(candidates),
            'nonadjacent_pairs_tested':tested,'strict_crossings':found,'truncated_at_limit':len(found)>=limit,
            'one_sided_boundary_contacts_sample':one_sided_contacts,
            'independent_coplanar_AABB_audit':coplanar_report,
            'scope':'nonadjacent strict crossings and coplanar area overlaps only; noncoplanar crossing requires both triangles to straddle the other plane; excludes intentional inter-object embedding'}
