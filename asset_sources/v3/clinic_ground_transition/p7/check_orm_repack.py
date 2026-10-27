"""Read-only UV-aware comparison of native ORM repacking; no image writes."""
from pathlib import Path
import json, hashlib
import numpy as np
from PIL import Image
P=Path(__file__).resolve().parent
data=json.loads((P/'sdna_proxy_arrays.json').read_text(encoding='utf-8'))
uv=np.array(data['attrs']['BakeUV']).reshape((-1,3,2))
before=np.asarray(Image.open(P/'textures/Transition_ORM_before_AO.png').convert('RGB'),dtype=np.int16)
after=np.asarray(Image.open(P/'textures/Transition_ORM.png').convert('RGB'),dtype=np.int16)
h,w=after.shape[:2];mask=np.zeros((h,w),dtype=bool);core=np.zeros_like(mask)
for t in uv:
    p=t*np.array([w,h]);p[:,1]=h-p[:,1]
    lo=np.maximum(0,np.floor(p.min(axis=0)).astype(int));hi=np.minimum([w,h],np.ceil(p.max(axis=0)).astype(int))
    if np.any(hi<=lo):continue
    a,b,c=p[0],p[1]-p[0],p[2]-p[0];det=b[0]*c[1]-b[1]*c[0]
    if abs(det)<1e-10:continue
    dx=np.arange(lo[0],hi[0])[None,:]+.5-a[0];dy=np.arange(lo[1],hi[1])[:,None]+.5-a[1]
    u=(dx*c[1]-dy*c[0])/det;v=(b[0]*dy-b[1]*dx)/det
    region=np.s_[lo[1]:hi[1],lo[0]:hi[0]]
    mask[region]|=(u>=0)&(v>=0)&(u+v<=1)
    # Three-pixel geometric distance from every triangle edge, not just islands.
    dist=np.minimum.reduce([u*abs(det)/np.linalg.norm(c),v*abs(det)/np.linalg.norm(b),(1-u-v)*abs(det)/np.linalg.norm(b-c)])
    core[region]|=dist>=3
delta=np.abs(after-before)
def stats(m):
    d=delta[m]
    return {'pixels':int(m.sum()),'max_abs_RGB':d.max(axis=0).tolist(),'mean_abs_RGB':d.mean(axis=0).tolist(),'roughness_abs_quantiles':[float(v) for v in np.quantile(d[:,1],[.5,.95,.99,1])],'roughness_pixels_over_3_codes':int((d[:,1]>3).sum())}
result={'method':'Exact saved BakeUV triangle raster, pixel centers; compares native PNG bytes without modifying images. Interior excludes a 3px band around each triangle edge.','all':stats(np.ones_like(mask)),'inside_uv_faces':stats(mask),'triangle_interior_3px':stats(core),'outside_uv_faces':stats(~mask),'note':'Native shader re-bake resamples G; preservation means same author channel, not byte identity. Any boundary outliers remain documented.','hashes':{f:hashlib.sha256((P/'textures'/f).read_bytes()).hexdigest() for f in ['Transition_ORM_before_AO.png','Transition_ORM.png']}}
(P/'orm_repack_check.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(result,ensure_ascii=True,indent=2))
