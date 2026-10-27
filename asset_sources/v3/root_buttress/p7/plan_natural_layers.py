"""Read-only source geometry planning, no DCC launch and no asset export."""
from pathlib import Path
import json,struct,math
import numpy as np
HERE=Path(__file__).resolve().parent
VENDOR=HERE.parent/'p6/vendor'
g=json.loads((VENDOR/'rock_moss_set_01_1k.gltf').read_text())
b=(VENDOR/'rock_moss_set_01.bin').read_bytes()
def acc(index):
 a=g['accessors'][index];v=g['bufferViews'][a['bufferView']];typ={5126:'f',5125:'I',5123:'H',5121:'B'}[a['componentType']];w={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']];s=struct.Struct('<'+typ*w);off=v.get('byteOffset',0)+a.get('byteOffset',0);stride=v.get('byteStride',s.size)
 return np.array([s.unpack_from(b,off+i*stride) for i in range(a['count'])])
feet=[(-2.54,2.17),(2.51,2.22),(-2.28,-2.5),(2.31,-2.48)]
pts=np.array([(x+r*math.cos(a*math.tau/32),z+r*math.sin(a*math.tau/32)) for x,z in feet for r in [0,.75] for a in range(32)])
def segments(v,f,y):
 ts=v[f];ends=[]
 for tri in ts:
  p=[]
  for a,c in [(tri[0],tri[1]),(tri[1],tri[2]),(tri[2],tri[0])]:
   if (a[1]<y)!=(c[1]<y):
    q=a+(c-a)*(y-a[1])/(c[1]-a[1]);p.append(q[[0,2]])
  if len(p)==2:ends.append(p)
 return np.array(ends)
def within(points,segs):
 a=segs[:,0];c=segs[:,1];x=points[:,0,None];z=points[:,1,None]
 crossing=(a[None,:,1]>z)!=(c[None,:,1]>z)
 hitx=(c[:,0]-a[:,0])[None,:]*(z-a[:,1][None,:])/(c[:,1]-a[:,1]+1e-30)[None,:]+a[:,0][None,:]
 return np.count_nonzero(crossing & (x<hitx),axis=1)%2==1
meta=[];options=[]
for i,mesh in enumerate(g['meshes']):
 p=mesh['primitives'][0];v=acc(p['attributes']['POSITION']);f=acc(p['indices']).reshape(-1,3).astype(int);lo=v.min(0);hi=v.max(0);v-=(lo+hi)/2;span=hi-lo
 meta.append({'index':i,'name':g['nodes'][i]['name'],'span':span.tolist(),'tris':len(f)})
 for frac in [.35,.45,.55]:
  cut=(frac-.5)*span[1];ss=segments(v,f,cut)
  for yaw in [a*math.pi/12 for a in range(12)]:
   c,s=math.cos(yaw),math.sin(yaw);rot=np.array([[c,-s],[s,c]])
   for scale in [4.0,4.5,5.0,5.5,6.0]:
    # Uniform geometry proportions first; later y scale may be <=25% lower.
    vv=v[:,[0,2]]*scale@rot.T
    for offset in [(0,0),(.5,-.3),(1,-.5),(.5,-.7)]:
     q=vv+offset
     if np.any(q.min(0)<[-6.61,-6.804]) or np.any(q.max(0)>[6.905,6.879]):continue
     seg=ss*scale@rot.T+offset
     inside=within(pts,seg);passed=int(inside.sum())
     if passed!=len(pts):continue
     # Prefer a broad low rock layer, useful clearance above lower Y5 shelf.
     thickness=span[1]*frac*scale
     options.append({'index':i,'source':g['nodes'][i]['name'],'scale':scale,'yaw':yaw,'xz_offset':offset,'cut_source_y':cut,'cut_fraction':frac,'remaining_thickness':thickness,'source_bounds_after_yaw_xz':[q.min(0).tolist(),q.max(0).tolist()],'foot_probes':len(pts),'all_covered':True,'score':abs(thickness-3.5)+.05*(q.max(0)-q.min(0)).sum()})
options.sort(key=lambda x:x['score'])
result={'method':'horizontal plane cross-section of original mesh; rigid yaw + uniform scale; four R0.75 disks must lie inside one source rock cross-section','sources':meta,'valid_options':len(options),'top_options':options[:16],'limits':'planning only: does not replace actual mesh ray/boolean/fixed marker validation or visual review'}
(HERE/'paper_geometry_plan.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(result,indent=2))
