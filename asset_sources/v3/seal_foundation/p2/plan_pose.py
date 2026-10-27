"""Rigid-pose study on the actual native LOD3, no mesh deformation."""
from pathlib import Path
import json,numpy as np,math
HERE=Path(__file__).resolve().parent
source=json.loads((HERE/'native_mesh_read.json').read_text())[0]
v=(np.array(source['vertices'])-source['centre'])@source['principal_basis_columns']
t=np.array(source['triangles'],dtype=int)
base=v[:,[2,0,1]]
def slice_segments(p,y):
 tri=p[t];out=[]
 use=(tri[:,:,1].min(1)<y)&(tri[:,:,1].max(1)>y)
 for q in tri[use]:
  pp=[]
  for a,b in zip(q,np.roll(q,-1,axis=0)):
   if (a[1]<y)!=(b[1]<y):pp.append((a+(b-a)*(y-a[1])/(b[1]-a[1]))[[0,2]])
  if len(pp)==2:out.append(pp)
 return np.array(out)
def inside(segments,x,z):
 a=segments[:,0];b=segments[:,1]
 m=(a[:,1]>z)!=(b[:,1]>z)
 xx=a[m,0]+(z-a[m,1])*(b[m,0]-a[m,0])/(b[m,1]-a[m,1])
 return np.count_nonzero(xx>x)%2==1
cases=[]
for flip,tilt in [(1,-5),(-1,4),(1,1)]:
 for scale in [3.08]:
  p=base.copy();p[:,[0,2]]*=flip
  a=math.radians(tilt);M=np.array([[1,0,0],[0,math.cos(a),-math.sin(a)],[0,math.sin(a),math.cos(a)]])
  p=p@M.T*scale;p[:,0]-=(p[:,0].max()+p[:,0].min())*.5
  for fraction in [.80,.82,.84,.86,.88]:
   y=p[:,1].min()+np.ptp(p[:,1])*fraction;s=slice_segments(p,y)
   zz=np.arange(s[:,:,1].min()+.01,s[:,:,1].max()-.01,.025)
   valid=[z for z in zz if all(inside(s,x,z) for x in np.linspace(-.5,.5,11))]
   intervals=[]
   for z in valid:
    if not intervals or z-intervals[-1][1]>.026:intervals.append([float(z),float(z)])
    else:intervals[-1][1]=float(z)
   interval=max(intervals,key=lambda q:q[1]-q[0]) if intervals else [0,0]
   cases.append({'flip':flip,'tilt_deg':tilt,'scale':scale,'fraction':fraction,'gate_plane_before_translate':float(y),'guaranteed_seat_z_interval':interval,'seat_length':interval[1]-interval[0],'y_offset':6.1-float(y),'min_height':float(p[:,1].min()+6.1-y),'source_bounds': [p.min(0).tolist(),p.max(0).tolist()]})
(HERE/'rigid_pose_candidates.json').write_text(json.dumps(cases,indent=2),encoding='utf-8')
for c in cases:print({k:c[k] for k in ['flip','tilt_deg','fraction','seat_length','min_height','guaranteed_seat_z_interval']})
