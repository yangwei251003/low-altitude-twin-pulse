"""Read natural cliff sections before construction. No DCC or asset export."""
from pathlib import Path
import json,struct,math,sys
import numpy as np
HERE=Path(__file__).resolve().parent;VENDOR=HERE.parent/'p8/vendor'
def load(asset):
 p=VENDOR/asset/(asset+'_1k.gltf');g=json.loads(p.read_text());b=(p.parent/g['buffers'][0]['uri']).read_bytes()
 def acc(index):
  a=g['accessors'][index];v=g['bufferViews'][a['bufferView']];typ={5126:'f',5125:'I',5123:'H',5121:'B'}[a['componentType']];w={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']];s=struct.Struct('<'+typ*w);off=v.get('byteOffset',0)+a.get('byteOffset',0);stride=v.get('byteStride',s.size)
  return np.array([s.unpack_from(b,off+i*stride) for i in range(a['count'])])
 p=g['meshes'][0]['primitives'][0]
 return acc(p['attributes']['POSITION']),acc(p['indices']).reshape(-1,3).astype(int)
def front_raster(v,f,nx=151,ny=121):
 lo=v.min(0);hi=v.max(0);xs=np.linspace(lo[0],hi[0],nx);ys=np.linspace(lo[1],hi[1],ny);z=np.full((ny,nx),-np.inf)
 for tri in v[f]:
  denom=(tri[1,1]-tri[2,1])*(tri[0,0]-tri[2,0])+(tri[2,0]-tri[1,0])*(tri[0,1]-tri[2,1])
  if abs(denom)<1e-14:continue
  x0=max(0,int(np.searchsorted(xs,tri[:,0].min()))-1);x1=min(nx,int(np.searchsorted(xs,tri[:,0].max()))+1);y0=max(0,int(np.searchsorted(ys,tri[:,1].min()))-1);y1=min(ny,int(np.searchsorted(ys,tri[:,1].max()))+1)
  if x1<=x0 or y1<=y0:continue
  xx,yy=np.meshgrid(xs[x0:x1],ys[y0:y1]);a=((tri[1,1]-tri[2,1])*(xx-tri[2,0])+(tri[2,0]-tri[1,0])*(yy-tri[2,1]))/denom;b=((tri[2,1]-tri[0,1])*(xx-tri[2,0])+(tri[0,0]-tri[2,0])*(yy-tri[2,1]))/denom;c=1-a-b
  zz=a*tri[0,2]+b*tri[1,2]+c*tri[2,2];valid=(a>=-1e-7)&(b>=-1e-7)&(c>=-1e-7);tile=z[y0:y1,x0:x1];tile[:]=np.where(valid,np.maximum(tile,zz),tile)
 return xs,ys,z
def upright_source():
 v,f=load('rock_face_01');xs,ys,z=front_raster(v,f);xx,yy=np.meshgrid(xs,ys)
 good=np.isfinite(z)&(xx>=-1.4)&(xx<=2.1)&(yy>=.3)&(yy<=3.15)
 fit=np.linalg.lstsq(np.column_stack([xx[good],yy[good],np.ones(good.sum())]),z[good],rcond=None)[0]
 n=np.array([-fit[0],-fit[1],1.0]);n/=np.linalg.norm(n);target=np.array([0.,0.,1.]);axis=np.cross(n,target);s=np.linalg.norm(axis);c=np.dot(n,target)
 k=np.array([[0,-axis[2],axis[1]],[axis[2],0,-axis[0]],[-axis[1],axis[0],0]])
 rot=np.eye(3)+k+k@k*((1-c)/(s*s)) if s>1e-12 else np.eye(3)
 rv=v@rot.T;rx,ry,rz=front_raster(rv,f,201,181)
 scale=11.8/(ry[-1]-ry[0]);xcentre=(rx[0]+rx[-1])/2
 # A shared rigid transform only; this is not y-dependent column stretching.
 gx=(rx-xcentre)*scale;gy=(ry-ry[0])*scale-.15
 central=np.isfinite(rz)&(np.abs(gx[None,:])<3.8)&(gy[:,None]>.1)&(gy[:,None]<10.1)
 reference=float(np.median(rz[central]));delta=(rz-reference)*scale
 return {'vertices':rv,'faces':f,'x':gx,'y':gy,'delta':delta,'matrix':rot,'scale':scale,'reference_z':reference,'raw_fit':fit}
def bilinear_sample(field,u,y):
 xs=field['x'];ys=field['y'];z=field['delta'];i=int(np.clip(np.searchsorted(xs,u)-1,0,len(xs)-2));j=int(np.clip(np.searchsorted(ys,y)-1,0,len(ys)-2));fx=(u-xs[i])/(xs[i+1]-xs[i]);fy=(y-ys[j])/(ys[j+1]-ys[j]);q=z[j:j+2,i:i+2]
 if np.isfinite(q).all():return float((q[0,0]*(1-fx)+q[0,1]*fx)*(1-fy)+(q[1,0]*(1-fx)+q[1,1]*fx)*fy),0.0
 # Missing scan samples are reported and only nearest observations returned;
 # callers must reject excessive unsupported surface rather than hiding it.
 for radius in range(1,12):
  x0=max(0,i-radius);x1=min(len(xs),i+radius+2);y0=max(0,j-radius);y1=min(len(ys),j+radius+2);part=z[y0:y1,x0:x1];jj,ii=np.where(np.isfinite(part))
  if len(ii):
   distances=(xs[x0+ii]-u)**2+(ys[y0+jj]-y)**2;k=np.argmin(distances)
   return float(part[jj[k],ii[k]]),float(math.sqrt(distances[k]))
 raise ValueError('no observed natural source near requested point')
def analyze():
 v,f=load('rock_face_01');xs,ys,z=front_raster(v,f);rows=[]
 for y in [.15,.5,1,1.5,2,2.5,3,3.2,3.35]:
  i=int(np.argmin(abs(ys-y)));mask=np.isfinite(z[i]);central=mask&(xs>=-1.4)&(xs<=2.1)
  rows.append({'raw_y':float(ys[i]),'x_visible_span':[float(xs[mask].min()),float(xs[mask].max())] if mask.any() else None,'central_coverage':float(central.sum()/((xs>=-1.4)&(xs<=2.1)).sum()),'front_z_quantiles':np.quantile(z[i,central],[0,.1,.5,.9,1]).tolist() if central.any() else []})
 xx,yy=np.meshgrid(xs,ys);good=np.isfinite(z)&(xx>=-1.4)&(xx<=2.1)&(yy>=.3)&(yy<=3.15)
 fit=np.linalg.lstsq(np.column_stack([xx[good],yy[good],np.ones(good.sum())]),z[good],rcond=None)[0]
 out={'source':'rock_face_01 raw CC0 geometry','raw_sections':rows,'best_fit_front_z_equals_ax_by_c':fit.tolist(),'front_slope_degrees':math.degrees(math.atan(fit[1])),'source_scale_policy':'uniform scale only; rigid rotation may align average cliff face; no vertical column deformation','planned_gates':['single connected closed outer shell, zero boundary/nonmanifold edges','four R0.75 foot disks at Y10 on same connected top','all original fixed markers and Sap preserved','sections at Y2/5/8/9.9 keep thick body; no narrow middle supporting wider lid','no full platform generated until this source section analysis is inspected']}
 (HERE/'source_section_plan.json').write_text(json.dumps(out,indent=2),encoding='utf-8');print(json.dumps(out,indent=2))
if __name__=='__main__':analyze()
