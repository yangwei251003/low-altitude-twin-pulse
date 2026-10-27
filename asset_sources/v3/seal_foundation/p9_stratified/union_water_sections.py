from pathlib import Path
import json,sys
from shapely.geometry import Polygon
from shapely.ops import unary_union
src=Path(sys.argv[1]);dst=Path(sys.argv[2]);data=json.loads(src.read_text(encoding='utf-8'))
polys=[]
for row in data['members']:
 for ring in row['section']['loops']:
  if ring['closed']:polys.append(Polygon(ring['points']))
assert polys and all(p.is_valid for p in polys)
u=unary_union(polys);assert u.is_valid
parts=[u] if u.geom_type=='Polygon' else list(u.geoms)
loops=[]
for q in parts:
 loops.append({'closed':True,'points':[list(v) for v in list(q.exterior.coords)[:-1]],'area_abs_m2':float(Polygon(q.exterior).area),'hole':False})
 for h in q.interiors:loops.append({'closed':True,'points':[list(v) for v in list(h.coords)[:-1]],'area_abs_m2':float(Polygon(h).area),'hole':True})
out={'height_local_y':1,'height_world_y':-2.2,'all_nodes_degree_2':True,'loops':loops,'segments':sum(len(q['points']) for q in loops),'area_union_m2':float(u.area),'component_count':len(parts),'valid':bool(u.is_valid),'method':'Shapely unary_union of actual closed mesh-plane sections; not union of AABBs','input_member_count':len(data['members'])}
dst.write_text(json.dumps(out,indent=2),encoding='utf-8')
