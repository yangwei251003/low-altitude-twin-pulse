"""Read-only top-down exposed coverage from actual P8 mesh arrays.
No Blender / GPU / image editing. Results are geometry projection, not a camera
visibility verdict and not the final normal-map contrast coverage.
"""
from pathlib import Path
import json,math,time,hashlib
import numpy as np
P=Path(__file__).resolve().parent;SRC=P;STEP=.005
start=time.time()
raw=json.loads((SRC/'sdna_proxy_arrays.json').read_text(encoding='utf-8'))['attrs']
verts=np.array(raw['position']);faces=np.array(raw['.corner_vert']).reshape((-1,3));tri=verts[faces]
parent=list(range(len(verts)))
def find(i):
    while parent[i]!=i:parent[i]=parent[parent[i]];i=parent[i]
    return i
for t in faces:
    r=find(int(t[0]))
    for i in t[1:]:parent[find(int(i))]=r
components={}
for i in range(len(verts)):components.setdefault(find(i),[]).append(i)
soil=set(max(components.values(),key=len));soil_tri=tri[[int(f[0]) in soil for f in faces]]
shape=(round(2.4/STEP),round(6/STEP));xs=-3+(np.arange(shape[1])+.5)*STEP;zs=(np.arange(shape[0])+.5)*STEP
def raster(tris):
    heights=np.full(shape,-np.inf,dtype=np.float32)
    for t in tris:
        x=t[:,0];z=-t[:,1];h=t[:,2];a=np.array([x[0],z[0]]);b=np.array([x[1]-x[0],z[1]-z[0]]);c=np.array([x[2]-x[0],z[2]-z[0]])
        det=b[0]*c[1]-b[1]*c[0]
        if abs(det)<1e-12:continue
        x0=max(0,int(math.floor((min(x)+3)/STEP)));x1=min(shape[1],int(math.ceil((max(x)+3)/STEP)))
        z0=max(0,int(math.floor(min(z)/STEP)));z1=min(shape[0],int(math.ceil(max(z)/STEP)))
        if x1<=x0 or z1<=z0:continue
        dx=xs[x0:x1][None,:]-a[0];dz=zs[z0:z1][:,None]-a[1]
        u=(dx*c[1]-dz*c[0])/det;v=(b[0]*dz-b[1]*dx)/det;valid=(u>=-1e-6)&(v>=-1e-6)&(u+v<=1.000001)
        y=h[0]+u*(h[1]-h[0])+v*(h[2]-h[0]);region=heights[z0:z1,x0:x1];np.maximum(region,np.where(valid,y,-np.inf),out=region)
    return heights
ground=raster(soil_tri)
objects=json.loads((SRC/'actual_stone_geometry.json').read_text(encoding='utf-8'))['objects']
lowtri=[];hightri=[]
for ob in objects:
    p=np.array(ob['position']);f=np.array(ob['.corner_vert']).reshape((-1,3));t=p[f]
    (hightri if ob['name'].startswith('HIGH_ONLY_') else lowtri).append(t)
low=raster(np.concatenate(lowtri));high=raster(np.concatenate(hightri));valid=np.isfinite(ground)
exposed_low=valid&(low>ground+.001);exposed_high=valid&(high>np.maximum(ground,low)+.001)
combined=valid&(np.maximum(low,high)>ground+.001)
routes=[([(-1.10,.49),(-1.22,1.04),(-1.52,1.62),(-1.43,2.10)],1),([(-1.22,1.04),(-.96,1.38),(-.82,1.83)],.58),([(.40,.51),(.55,.91),(.90,1.22),(.74,1.72)],.83),([(.55,.91),(.28,1.18),(.06,1.50)],.46),([(1.74,.51),(1.87,.99),(1.66,1.57),(1.94,2.14)],.92),([(1.87,.99),(2.15,1.27),(2.38,1.75)],.54)]
XX,ZZ=np.meshgrid(xs,zs);bank=np.zeros(shape,dtype=bool);bed=np.zeros(shape,dtype=bool);wide=np.zeros(shape,dtype=bool)
for ri,(points,_) in enumerate(routes):
    lengths=[math.dist(a,b) for a,b in zip(points,points[1:])];total=sum(lengths);distance=np.full(shape,np.inf);along=np.zeros(shape);walk=0
    for (a,b),length in zip(zip(points,points[1:]),lengths):
        q=np.clip(((XX-a[0])*(b[0]-a[0])+(ZZ-a[1])*(b[1]-a[1]))/(length*length),0,1)
        d=np.hypot(XX-(a[0]+q*(b[0]-a[0])),ZZ-(a[1]+q*(b[1]-a[1])));better=d<distance;distance=np.where(better,d,distance);along=np.where(better,(walk+q*length)/total,along);walk+=length
    main=ri in(0,2,4);width=(.105+.085*along) if main else (.065+.035*along)
    if ri==2:width*=.86
    bank|=(distance>=width)&(distance<=width+(.20 if main else .115))&(along>.05)&(along<.95)
    bed|=distance<width*.8
    spread=(.50+.20*np.sin(along*4.3+ri*.83)**2) if main else (.24+.10*np.sin(along*4.3+ri*.83)**2)
    wide|=(distance>=width)&(distance<=width+spread)&(along>.03)&(along<.98)
bank&=valid;bed&=valid
front_z=zs[np.argmax(valid,axis=0)]
apron_depth=.45+.25*(.5+.5*np.sin(xs*1.1+.4))
wide=(wide|(ZZ<front_z[None,:]+apron_depth[None,:]))&valid&(~bed)
area=lambda mask:float(mask.sum()*STEP*STEP)
out={'source_directory':str(SRC),'method':'5mm top-down triangle z-buffer on actual named P8 low/high source meshes; exposed requires >1mm above actual soil. High counts only where it also wins over low stones. One raster resolution, no convergence proof.','grid_step_m':STEP,'soil_projected_area_m2':area(valid),'exposed_low_stone_area_m2':area(exposed_low),'exposed_high_stone_area_m2':area(exposed_high),'combined_exposed_area_m2':area(combined),'combined_percent_whole_soil':100*area(combined)/area(valid),'high_percent_whole_soil':100*area(exposed_high)/area(valid),'existing_bank_domain_m2':area(bank),'combined_percent_bank_domain':100*area(combined&bank)/area(bank),'high_percent_bank_domain':100*area(exposed_high&bank)/area(bank),'wide_deposit_domain_m2':area(wide),'combined_percent_wide_domain':100*area(combined&wide)/area(wide),'high_percent_wide_domain':100*area(exposed_high&wide)/area(wide),'bed_domain_m2':area(bed),'combined_percent_bed':100*area(combined&bed)/area(bed),'seconds':time.time()-start,'input_hashes':{name:hashlib.sha256((SRC/name).read_bytes()).hexdigest() for name in ['sdna_proxy_arrays.json','actual_stone_geometry.json','sediment_distribution.json']},'limits':['Excludes concrete embedded aggregate from soil percentage.','Camera foreshortening, normal-map filtering and material contrast are not measured by this geometry projection.','Reference 35–50% is an artistic estimate, not a calibrated pixel mask.']}
(P/'p8_coverage.json').write_text(json.dumps(out,ensure_ascii=False,indent=2),encoding='utf-8');print(json.dumps(out,ensure_ascii=True,indent=2))
