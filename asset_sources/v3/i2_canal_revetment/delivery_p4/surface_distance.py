"""Float64 distances, independent of Blender single precision BVHTree."""
import numpy as np

def nearest(point,triangles):
    p=np.asarray(point,dtype=np.float64);t=np.asarray(triangles,dtype=np.float64)
    a,b,c=t[:,0],t[:,1],t[:,2];ab=b-a;ac=c-a;ap=p-a
    n=np.cross(ab,ac);n2=np.einsum('ij,ij->i',n,n)
    safe=np.where(n2>1e-30,n2,1.)
    v=np.einsum('ij,ij->i',np.cross(ap,ac),n)/safe
    w=np.einsum('ij,ij->i',np.cross(ab,ap),n)/safe
    inside=(n2>1e-30)&(v>=0)&(w>=0)&(v+w<=1)
    plane=np.abs(np.einsum('ij,ij->i',ap,n))/np.sqrt(safe)
    distances=np.where(inside,plane,np.inf)
    for x,y in [(a,b),(b,c),(c,a)]:
        e=y-x;length2=np.einsum('ij,ij->i',e,e)
        fraction=np.einsum('ij,ij->i',p-x,e)/np.where(length2>0,length2,1.)
        closest=x+np.clip(fraction,0.,1.)[:,None]*e
        distances=np.minimum(distances,np.linalg.norm(closest-p,axis=1))
    index=int(np.argmin(distances));return float(distances[index]),index
