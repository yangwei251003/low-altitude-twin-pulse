"""Bounded P12 coplanar audit: AABB bins generate candidates, not verdicts."""
import math
import numpy as np

def coplanar_overlaps(vertices,triangles,limit=25,cell_size=.05):
    points=np.asarray([tuple(v) for v in vertices],dtype=np.float64)
    indices=np.asarray(triangles,dtype=np.int32);p=points[indices]
    lo=p.min(axis=1);hi=p.max(axis=1)
    cells_lo=np.floor((lo-1e-7)/cell_size).astype(np.int32)
    cells_hi=np.floor((hi+1e-7)/cell_size).astype(np.int32)
    normals=np.cross(p[:,1]-p[:,0],p[:,2]-p[:,0]);lengths=np.linalg.norm(normals,axis=1)
    normals/=np.maximum(lengths[:,None],1e-30)
    normal_rows=[tuple(n) for n in normals];point_rows=[[tuple(q) for q in tri] for tri in p]
    bins={};found=[];duplicate_keys={};checked=0;plane_candidates=0
    def orient(a,b,c):return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])
    def inside(q,tri):
        s=[orient(a,b,q) for a,b in zip(tri,tri[1:]+tri[:1])]
        return min(s)>1e-10 or max(s)<-1e-10
    for i,tri in enumerate(triangles):
        if lengths[i]<1e-12:continue
        key=tuple(sorted(tri))
        if key in duplicate_keys:
            found.append({'triangles':[duplicate_keys[key],i],'coplanar':True,'same_vertex_ids':True})
            if len(found)>=limit:break
        else:duplicate_keys[key]=i
        mn=cells_lo[i];mx=cells_hi[i];ni=normal_rows[i];pi=point_rows[i]
        for x in range(int(mn[0]),int(mx[0])+1):
          for y in range(int(mn[1]),int(mx[1])+1):
            for z in range(int(mn[2]),int(mx[2])+1):
              cell=(x,y,z);bucket=bins.setdefault(cell,[])
              for j in bucket:
                # Each AABB pair belongs to exactly its first common bin.
                mj=cells_lo[j]
                if x!=max(mn[0],mj[0]) or y!=max(mn[1],mj[1]) or z!=max(mn[2],mj[2]):continue
                tj=triangles[j]
                if any(v in tj for v in tri):continue
                if any(lo[i,k]>hi[j,k]+1e-7 or lo[j,k]>hi[i,k]+1e-7 for k in range(3)):continue
                checked+=1;nj=normal_rows[j]
                if abs(sum(ni[k]*nj[k] for k in range(3)))<1-1e-9:continue
                pj=point_rows[j]
                if max(abs(sum((q[k]-pi[0][k])*ni[k] for k in range(3))) for q in pj)>1e-7:continue
                plane_candidates+=1;drop=max(range(3),key=lambda k:abs(ni[k]));axes=[k for k in range(3) if k!=drop]
                a=[tuple(q[k] for k in axes) for q in pi];b=[tuple(q[k] for k in axes) for q in pj]
                overlap=any(inside(q,b) for q in a) or any(inside(q,a) for q in b)
                # Coincident triangles with distinct IDs have no strict vertex
                # inclusion, but their centroids lie in the overlapping area.
                overlap|=inside(tuple(sum(q[k] for q in a)/3 for k in range(2)),b)
                overlap|=inside(tuple(sum(q[k] for q in b)/3 for k in range(2)),a)
                if not overlap:
                    for aa,ab in zip(a,a[1:]+a[:1]):
                        for ba,bb in zip(b,b[1:]+b[:1]):
                            if orient(aa,ab,ba)*orient(aa,ab,bb)<-1e-16 and orient(ba,bb,aa)*orient(ba,bb,ab)<-1e-16:overlap=True
                if overlap:
                    found.append({'triangles':[j,i],'coplanar':True,'same_vertex_ids':False})
                    if len(found)>=limit:return {'overlaps':found,'truncated':True,'candidate_pairs':checked,'plane_candidates':plane_candidates,'bin_size_m':cell_size}
              bucket.append(i)
    return {'overlaps':found,'truncated':len(found)>=limit,'candidate_pairs':checked,'plane_candidates':plane_candidates,'bin_size_m':cell_size}
