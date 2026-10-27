"""Static spatial plan only: no Blender, mesh construction, render or image edits."""
from pathlib import Path
import json, math
import numpy as np
P=Path(__file__).resolve().parent
source=(P/'measure_p7_coverage.py').read_text(encoding='utf-8').split("out={'source_directory'")[0]
exec(compile(source,str(P/'measure_p7_coverage.py'),'exec'))
new_bank=np.zeros(shape,dtype=bool)
for ri,(points,_) in enumerate(routes):
    lengths=[math.dist(a,b) for a,b in zip(points,points[1:])];total=sum(lengths);distance=np.full(shape,np.inf);along=np.zeros(shape);walk=0
    for (a,b),length in zip(zip(points,points[1:]),lengths):
        q=np.clip(((XX-a[0])*(b[0]-a[0])+(ZZ-a[1])*(b[1]-a[1]))/(length*length),0,1)
        d=np.hypot(XX-(a[0]+q*(b[0]-a[0])),ZZ-(a[1]+q*(b[1]-a[1])));better=d<distance;distance=np.where(better,d,distance);along=np.where(better,(walk+q*length)/total,along);walk+=length
    main=ri in(0,2,4);width=(.105+.085*along) if main else (.065+.035*along)
    if ri==2:width*=.86
    spread=(.50+.20*np.sin(along*4.3+ri*.83)**2) if main else (.24+.10*np.sin(along*4.3+ri*.83)**2)
    new_bank|=(distance>=width)&(distance<=width+spread)&(along>.03)&(along<.98)
# An upper 0.45–0.70m apron joins the banks across the fracture. Its final density
# will fade continuously, not terminate as this planning support mask does.
front_row=np.argmax(valid,axis=0);front_z=zs[front_row]
apron_depth=.45+.25*(.5+.5*np.sin(xs*1.1+.4))
apron=valid&(ZZ<front_z[None,:]+apron_depth[None,:])
domain=(new_bank|apron)&valid&(~bed)
size_mix=[{'fraction':.65,'diameter_m':[.038,.052]},{'fraction':.25,'diameter_m':[.028,.038]},{'fraction':.10,'diameter_m':[.020,.028]}]
mean_d2=sum(r['fraction']*(r['diameter_m'][0]**2+np.prod(r['diameter_m'])+r['diameter_m'][1]**2)/3 for r in size_mix)
old=json.loads((SRC/'sediment_distribution.json').read_text(encoding='utf-8'));raw_old=sum(r['area'] for r in old['fine_stones']);old_ratio=area(exposed_high)/raw_old
estimates=[]
for count in [3500,4500,5000]:
    raw_area=count*math.pi*.775/4*mean_d2
    estimates.append({'count':count,'high_only_triangles':count*20,'raw_ellipse_sum_m2':raw_area,'empirical_visible_area_m2':raw_area*old_ratio,'combined_whole_soil_percent_if_old_ratio_holds':100*(raw_area*old_ratio+area(exposed_low))/area(valid)})
out={'status':'STATIC_PLAN_NOT_BUILT','method':'5mm support-domain union clipped against actual P7 soil projection. No new meshes or texture files.','soil_area_m2':area(valid),'old_bank_area_m2':area(bank),'proposed_bank_plus_fracture_apron_area_m2':area(domain),'protected_low_density_bed_area_m2':area(bed),'new_domain_existing_stone_coverage_percent':100*area(combined&domain)/area(domain),'size_mixture':size_mix,'P7_high_visible_area_divided_by_raw_ellipse_sum':old_ratio,'estimates':estimates,'limits':['These are support areas; final density must vary continuously, not use hard mask edges.','Raw ellipse sum is not visible union. The P7 empirical ratio is a planning estimate, not a guarantee for changed placement/diameters.','Reference 35–50% is a visual target estimate, not a numerical acceptance gate.','Actual top-down exposed union, native bake and the unchanged camera must be checked after any authorized run.']}
(P/'layout_plan.json').write_text(json.dumps(out,ensure_ascii=False,indent=2),encoding='utf-8');print(json.dumps(out,ensure_ascii=True,indent=2))
