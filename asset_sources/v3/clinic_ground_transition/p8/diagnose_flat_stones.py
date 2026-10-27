"""Read actual frozen mesh/UV/PNG evidence. No Blender, image edits or render."""
from pathlib import Path
import json,math,hashlib
import numpy as np
from PIL import Image
P=Path(__file__).resolve().parent
r=json.loads((P/'sdna_proxy_arrays.json').read_text(encoding='utf-8'));a=r['attrs']
pos=np.array(a['position']);idx=np.array(a['.corner_vert']).reshape((-1,3));uv=np.array(a['BakeUV']).reshape((-1,3,2));tri=pos[idx]
control=np.array(a['SurfaceControl']).reshape((-1,3,4));normals=np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0])
parent=list(range(len(pos)))
def find(i):
    while parent[i]!=i:parent[i]=parent[parent[i]];i=parent[i]
    return i
for t in idx:
    root=find(int(t[0]))
    for i in t[1:]:parent[find(int(i))]=root
comp={}
for i in range(len(pos)):comp.setdefault(find(i),[]).append(i)
soil_key=max(comp,key=lambda k:len(comp[k]));soil_ids=set(comp[soil_key]);soil_faces=np.array([int(t[0]) in soil_ids for t in idx])
xy0=tri[:,0,:2];v1=tri[:,1,:2]-xy0;v2=tri[:,2,:2]-xy0;det=v1[:,0]*v2[:,1]-v1[:,1]*v2[:,0]
images={k:np.asarray(Image.open(P/'textures'/('Transition_'+k+'.png')).convert('RGB'),dtype=float) for k in ['BaseColor','Normal','ORM']}
def sample_image(im,q):
    h,w=im.shape[:2];fx=min(w-1,max(0,q[0]*w-.5));fy=min(h-1,max(0,(1-q[1])*h-.5));x=int(fx);y=int(fy);dx=fx-x;dy=fy-y
    return ((1-dy)*((1-dx)*im[y,x]+dx*im[y,min(x+1,w-1)])+dy*((1-dx)*im[min(y+1,h-1),x]+dx*im[min(y+1,h-1),min(x+1,w-1)]))
def at(x,z,ground_only=False):
    delta=np.array([x,-z])-xy0
    with np.errstate(divide='ignore',invalid='ignore'):
        b=(delta[:,0]*v2[:,1]-delta[:,1]*v2[:,0])/det;c=(v1[:,0]*delta[:,1]-v1[:,1]*delta[:,0])/det
    bc=np.stack([1-b-c,b,c],axis=1);mask=(np.min(bc,axis=1)>=-1e-7)&(normals[:,2]>1e-12)&np.isfinite(bc).all(axis=1)
    if ground_only:mask &= soil_faces
    choices=np.flatnonzero(mask)
    if not len(choices):return None
    y=np.einsum('ij,ij->i',bc[choices],tri[choices,:,2]);i=int(choices[np.argmax(y)]);q=bc[i]@uv[i]
    colors={k:sample_image(im,q).tolist() for k,im in images.items()}
    return {'point':[x,float(bc[i]@tri[i,:,2]),z],'triangle':i,'uv':q.tolist(),'surface_control':(bc[i]@control[i]).tolist(),**colors}
data=json.loads((P/'sediment_distribution.json').read_text(encoding='utf-8'))
source_objects={o['name']:o for o in json.loads((P/'actual_stone_geometry.json').read_text(encoding='utf-8'))['objects']}
large=[]
for row in data['low_stones']:
    if not row['name'].startswith('Fallen'):continue
    x,expected,z=row['ground_center'];g=at(x,z,True);visible=at(x,z)
    # Actual mesh heights, rather than the analytic soil_y used to place pieces.
    actual=[]
    for v in source_objects[row['name']]['position']:
        ground=at(float(v[0]),float(-v[1]),True)
        if ground:actual.append(float(v[2]-ground['point'][1]))
    large.append({'name':row['name'],'diameter_m':row['diameter_m'],'recorded_protrusion_vs_formula_m':row['protrusion_m'],'actual_max_vertex_protrusion_m':max(actual),'actual_top_center_protrusion_m':visible['point'][1]-g['point'][1],'center_note':'Highest visible scene triangle at center can belong to an overlapping fragment; per-object max vertex uses exact named source mesh.','actual_center':visible,'ground_at_center':g})
fine=[]
for stone in data['fine_stones'][::63]:
    x,z,d=stone['x'],stone['z'],stone['diameter'];points=[]
    for dx,dz in [(0,0),(.20*d,0),(-.20*d,0),(0,.20*d),(0,-.20*d)]:
        value=at(x+dx,z+dz,True)
        if value:
            vector=np.array(value['Normal'])/127.5-1;vector/=max(np.linalg.norm(vector),1e-10)
            value['normal_tilt_degrees']=float(np.degrees(np.arccos(np.clip(vector[2],-1,1))))
            points.append(value)
    fine.append({'source_center':[x,z],'diameter':d,'samples':points})
channels=[('main1-mouth',-1.10,.55),('main1-mid',-1.22,1.04),('main1-tail',-1.52,1.62),('main1-adjacent',-1.68,1.04),('main2-mid',.55,.91),('main2-adjacent',.0,.91),('main3-mid',1.87,.99),('main3-adjacent',2.35,.99)]
channels=[{'label':name,**at(x,z,True)} for name,x,z in channels]
n=images['Normal'];old=np.asarray(Image.open(P.parent/'p7/textures/Transition_Normal.png').convert('RGB'))
result={'method':'Actual saved Blender SDNA geometry, connected-component soil, barycentric BakeUV lookup and unmodified PNG samples. No engine.', 'blend_sha':r['blend_sha256'],'normal_global_stats':{'min':n.min(axis=(0,1)).tolist(),'max':n.max(axis=(0,1)).tolist(),'neutral_percent':float(np.mean(np.all(n==[128,128,255],axis=2))*100),'P7_neutral_percent':float(np.mean(np.all(old==[128,128,255],axis=2))*100),'RG_std':n[:,:,:2].std(axis=(0,1)).tolist(),'note':'Whole atlas includes unused/background pixels; not a surface coverage percentage.'},'large_stone_actual_geometry':large,'fine_bake_samples':fine,'channel_samples':channels,'ao_red_channel_unique':np.unique(images['ORM'][:,:,0]).tolist(),'cage':{'extrusion_m':.035,'max_ray_distance_m':.09,'source':'actual build script and successful bake logs'},'geometry_height_is_not_normal_map':True}
(P/'flat_stone_diagnosis.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'large':[{k:v for k,v in row.items() if k in ['name','diameter_m','actual_max_vertex_protrusion_m','actual_top_center_protrusion_m']} for row in large],'fine_sample_tilts':[[round(v['normal_tilt_degrees'],2) for v in f['samples']] for f in fine],'channels':[{'label':v['label'],'RGB':[round(c) for c in v['BaseColor']],'roughness':round(v['ORM'][1]/255,3),'wet_attr':round(v['surface_control'][0],3)} for v in channels],'AO_unique':result['ao_red_channel_unique']},indent=2))
