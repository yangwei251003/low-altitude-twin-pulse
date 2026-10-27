"""Five bounded section pairs, no Blender or geometric mutation.
Read native Boulder LOD3 extraction; preserve X/Z, consider invertible Y scale.
"""
from pathlib import Path
import json, hashlib, numpy as np
from shapely.geometry import LineString, box, mapping
from shapely.ops import polygonize, unary_union
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
src=HERE.parent/'p2/native_mesh_read.json'
native=json.loads(src.read_text())[0]
vertices=(np.array(native['vertices'])-native['centre'])@native['principal_basis_columns']
p=vertices[:,[2,1,0]];p[:,2]*=-1
scale=9.0/np.ptp(p[:,2]);p*=scale
p[:,0]-=(p[:,0].min()+p[:,0].max())/2
p[:,2]-=(p[:,2].min()+p[:,2].max())/2
p[:,1]-=p[:,1].min()
t=np.array(native['triangles'],int);q=p[t]
H=float(p[:,1].max())
def inside(point):
    # Generic non-axis ray avoids source-plane coincidences; full source mesh.
    d=np.array([.932717,.213657,.290183]);d/=np.linalg.norm(d)
    e1=q[:,1]-q[:,0];e2=q[:,2]-q[:,0];h=np.cross(d,e2);a=np.einsum('ij,ij->i',e1,h)
    valid=np.abs(a)>1e-11;f=np.zeros_like(a);f[valid]=1/a[valid]
    s=np.array(point)-q[:,0];u=f*np.einsum('ij,ij->i',s,h);v=f*np.einsum('ij,j->i',np.cross(s,e1),d)
    dist=f*np.einsum('ij,ij->i',e2,np.cross(s,e1))
    hits=np.sort(dist[valid&(u>=-1e-10)&(v>=-1e-10)&(u+v<=1+1e-10)&(dist>1e-8)])
    unique=[]
    for a in hits:
        if not unique or abs(a-unique[-1])>1e-7:unique.append(float(a))
    return len(unique)%2==1
def section(y):
    segments=[]
    for tri in q:
        cut=[]
        for a,b in zip(tri,np.roll(tri,-1,axis=0)):
            if (a[1]<y)!=(b[1]<y):
                v=a+(b-a)*(y-a[1])/(b[1]-a[1]);cut.append((round(float(v[0]),6),round(float(v[2]),6)))
        if len(cut)==2 and cut[0]!=cut[1]:segments.append(LineString(cut))
    polys=[]
    for poly in polygonize(unary_union(segments)):
        a=poly.representative_point()
        if inside([a.x,y,a.y]):polys.append(poly)
    solid=unary_union(polys)
    return solid,len(segments)
seat=box(-.65,-3.65,.65,3.65)
margin=box(-.75,-3.75,.75,3.75)
rows=[]
for i,upper_fraction in enumerate([.38,.43,.48,.53,.58],1):
    lo=.17*H;hi=upper_fraction*H
    bottom,nb=section(lo);top,nt=section(hi)
    fail=seat.difference(top);mfail=margin.difference(top)
    centre_cut=top.intersection(LineString([(0,-5),(0,5)]))
    row={'candidate':i,'lower_source_y_scaled':lo,'upper_source_y_scaled':hi,
         'global_y_stretch':5.65/(hi-lo),'source_slice_height_m':hi-lo,
         'top_area_m2':top.area,'bottom_area_m2':bottom.area,'top_bounds_xz':list(top.bounds),
         'top_section_segments':nt,'bottom_section_segments':nb,
         'full_beam_1_3x7_3_covered':top.covers(seat),
         'beam_missing_area_m2':fail.area,'missing_region_bounds_xz':list(fail.bounds) if not fail.is_empty else None,
         'plus_0_1m_margin_covered':top.covers(margin),'margin_missing_area_m2':mfail.area,
         'beam_width_line_diagnostics':[{'x':x,'solid_section':mapping(top.intersection(LineString([(x,-5),(x,5)])))} for x in [-.65,0,.65]],
         'centre_z_section':mapping(centre_cut),
         'top_section':mapping(top),'bottom_section':mapping(bottom),
         'missing_geometry':mapping(fail)}
    rows.append(row)
report={'scope':'Five predeclared horizontal slice pairs only; no Blender, no model build, no pose search.',
        'original_native_source_sha256':native['source_sha256'],
        'extraction_sha256':hashlib.sha256(src.read_bytes()).hexdigest(),
        'axis_mapping':'PCA longest -> Godot -Z; middle -> Y; thinnest -> X; centred X/Z; original minimum Y=0.',
        'uniform_scale_before_cut':scale,'original_scaled_bounds':[p.min(0).tolist(),p.max(0).tolist()],
        'section_numeric_rounding_m':1e-6,'beam_target_m':[1.3,7.3],'explicit_margin_each_side_m':.1,
        'candidate_lower_fraction':.17,'candidate_upper_fractions':[.38,.43,.48,.53,.58],
        'candidates':rows,'qualified_candidates':[r['candidate'] for r in rows if r['plus_0_1m_margin_covered']],
        'decision':'Proceed only if a real section covers the full rectangle and margin. Otherwise report insufficiency; no sculpt or rendering.'}
(HERE/'section_assessment.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({k:v for k,v in report.items() if k!='candidates'},ensure_ascii=False,indent=2))
for r in rows:print(json.dumps({k:v for k,v in r.items() if k not in ['top_section','bottom_section','missing_geometry','centre_z_section','beam_width_line_diagnostics']},ensure_ascii=False))
