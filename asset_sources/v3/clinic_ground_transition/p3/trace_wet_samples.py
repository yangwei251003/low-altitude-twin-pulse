from pathlib import Path
import json,math,hashlib
import numpy as np
from PIL import Image
P=Path(__file__).resolve().parent
raw=json.loads((P/'sdna_proxy_arrays.json').read_text(encoding='utf-8'));a=raw['attrs'];pos=np.array(a['position']);idx=np.array(a['.corner_vert']).reshape((-1,3));uv=np.array(a['BakeUV']).reshape((-1,3,2));control=np.array(a['SurfaceControl']).reshape((-1,3,4));metric=np.array(a['MetricUV']).reshape((-1,3,2));tris=pos[idx]
code=(P/'build_asset.py').read_text(encoding='utf-8');ns={'math':math};start=code.index('X=[');end=code.index('def select(');exec(code[start:end],ns)
atlas_srgb=np.array(Image.open(P/'source_inputs/material_atlas_v1_UNEDITED.png').convert('RGB'),dtype=float)/255
atlas=np.where(atlas_srgb<=.04045,atlas_srgb/12.92,((atlas_srgb+.055)/1.055)**2.4)
base=np.array(Image.open(P/'textures/Transition_BaseColor.png').convert('RGB'),dtype=float)/255;orm=np.array(Image.open(P/'textures/Transition_ORM.png').convert('RGB'),dtype=float)/255

def pixel(im,u,v):
    h,w=im.shape[:2];xx=min(w-1,max(0,u*w-.5));yy=min(h-1,max(0,(1-v)*h-.5));x=int(xx);y=int(yy);dx=xx-x;dy=yy-y
    return ((1-dy)*((1-dx)*im[y,x]+dx*im[y,min(x+1,w-1)])+dy*((1-dx)*im[min(y+1,h-1),x]+dx*im[min(y+1,h-1),min(x+1,w-1)])).tolist()
def sample(label,x,z):
    matches=[]
    for i,t in enumerate(tris):
        if np.cross(t[1]-t[0],t[2]-t[0])[2]<=1e-10:continue
        xy=t[:,:2];M=np.stack((xy[1]-xy[0],xy[2]-xy[0]),axis=1)
        if abs(np.linalg.det(M))<1e-12:continue
        f,g=np.linalg.solve(M,np.array([x,-z])-xy[0]);bc=np.array([1-f-g,f,g])
        if min(bc)<-1e-7:continue
        matches.append((float(bc@t[:,2]),i,bc))
    assert matches,label
    y,i,bc=max(matches,key=lambda r:r[0]);q=bc@uv[i];attr=bc@control[i];b=pixel(base,*q);o=pixel(orm,*q);linear=[v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in b]
    formula=ns['wet'](x,z);expectedrough=.86-.32*attr[0]
    mq=bc@metric[i]
    ping=lambda x:1-abs((x%2)-1)
    tex=lambda q,phase:np.array(pixel(atlas,q[0]+.008+.484*ping(mq[0]+phase[0]),q[1]+.008+.484*ping(mq[1]+phase[1])))
    dry=.62*np.array([.185,.158,.12])+.38*tex((0,0),(.17,.23))
    damp=.60*np.array([.095,.083,.065])+.40*tex((.5,0),(.41,.13))
    factor=min(1,float(attr[0])*1.08);predicted=(1-factor)*dry+factor*damp
    return {'label':label,'godot_point':[x,y,z],'triangle':i,'barycentric':bc.tolist(),'wet_formula':formula,'actual_interpolated_wet_attribute':float(attr[0]),'attribute_minus_formula':float(attr[0])-formula,'actual_bake_uv':q.tolist(),'base_srgb_0_255':[v*255 for v in b],'base_linear':linear,'base_linear_luminance':sum(c*w for c,w in zip(linear,[.2126,.7152,.0722])),'orm_0_1':o,'expected_rough_from_actual_attribute':float(expectedrough),'rough_pixel_minus_expected':o[1]-expectedrough,'metal':o[2],'actual_metric_uv':mq.tolist(),'reconstructed_dry_linear':dry.tolist(),'reconstructed_damp_linear':damp.tolist(),'predicted_author_base_linear':predicted.tolist(),'baked_minus_predicted_linear':[float(x-y) for x,y in zip(linear,predicted)]}
points=[('main1-mouth',-1.1,.55),('main1-mid',-1.22,1.04),('main1-tail',-1.52,1.62),('main1-dry-adjacent',-1.68,1.04),('branch1-mid',-1.0,1.33),('main2-mouth',.4,.57),('main2-mid',.55,.91),('main2-tail',.85,1.35),('main2-dry-adjacent',.0,.91),('main3-mouth',1.74,.58),('main3-mid',1.87,.99),('main3-tail',1.66,1.57),('main3-dry-adjacent',2.35,.99),('far-dry',.0,2.1)]
rows=[sample(*p) for p in points];result={'method':'Read-only actual .blend SDNA arrays -> barycentric world point -> actual BakeUV -> original PNG bilinear sample. No Blender/GPU; no pixels modified.','source_blend_sha256':raw['blend_sha256'],'samples':rows,'input_hashes':{f:hashlib.sha256((P/f).read_bytes()).hexdigest() for f in ['build_asset.py','textures/Transition_BaseColor.png','textures/Transition_ORM.png']}}
(P/'wet_pixel_trace.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
for r in rows:print(r['label'],'formula/attr',round(r['wet_formula'],3),round(r['actual_interpolated_wet_attribute'],3),'RGB',[round(v) for v in r['base_srgb_0_255']],'rough',round(r['orm_0_1'][1],3),'expected',round(r['expected_rough_from_actual_attribute'],3),'Y',round(r['godot_point'][1],4))
