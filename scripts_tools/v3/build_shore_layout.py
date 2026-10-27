#!/usr/bin/env python3
"""Rebuild the F1 replaceable graybox from actual locked GLB bottom triangles.

From project root:
    python scripts_tools/v3/build_shore_layout.py
    python scripts_tools/v3/build_shore_layout.py --check

Dependencies used for this output: Python 3, numpy, shapely 2.1.2 (GEOS constrained
Delaunay triangulation). Install only if absent: python -m pip install numpy
"shapely==2.1.2". Pinned Godot 4.7.2 reads already imported geometry headlessly.
Run dev.py import first after changing assets. No Blender, GPU or source-asset mutation.

The authored inputs are JSON profile/slope_width plus the six explicit placements
below. Fixed west/east/water/bed heights are 0/2.4/-2.2/-3.2 metres. JSON holds exact
source SHA256s and a canonical nine-decimal profile SHA. --check is read-only.
After H10 replacement: run this generator, then the headless shore test, then root's
assembled physics/optics/traversal tests. This is not a final terrain art pipeline.

Only raw GLB faces with all vertices on Y0 are extruded; holes and disjoint pieces
are preserved, with no convex hull, broad box or imported-position inflation.
Godot compressed positions may differ by up to the separately measured 0.25mm
test ceiling; production foundation geometry stays inside the raw bottom union.
"""
import argparse,json,struct,pathlib,hashlib,sys,subprocess,os
import numpy as np
from shapely.geometry import Polygon
from shapely.ops import unary_union
from shapely.affinity import translate
from shapely import constrained_delaunay_triangles
base=pathlib.Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--check',action='store_true',help='Recompute and compare without writing any file')
args=parser.parse_args()
target=base/'data/v3/terrain/f1_shore_layout.json'
profile=[[-50,-8.5,17.5],[-42,-10,15],[-34,-12,14],[-28,-10,17],[-22,-13,18],[-18,-10,17],[-14,-9,13.5],[-10,-10.5,11],[-6,-11,10.5],[-2,-13,9.5],[2,-13.5,8.5],[8,-11,10],[12,-10,9.5],[17,-10.5,10],[21,-10,10.5],[25,-10.5,10.5],[29.5,-10.5,10.2],[32,-11.5,10],[38,-12.5,11.5],[46,-10,14],[50,-9,12]]
# The existing JSON owns the authored control points. Everything else below is
# derived from those rows and the current GLB bytes; no GLB/import file is written.
if target.exists():
 authored=json.loads(target.read_text(encoding='utf-8-sig'))
 profile=authored['profile']
 slope=authored['slope_width']
else:
 slope=[1.8,1.6]
assert 2<=len(profile)<=32 and profile[0][0]==-50 and profile[-1][0]==50
assert len(slope)==2 and all(1.5<=float(v)<=2.0 for v in slope)
assert all(len(row)==3 and all(np.isfinite(float(v)) for v in row) for row in profile)
assert all(profile[i][0]>profile[i-1][0] for i in range(1,len(profile)))
assert all(-52<r[1]<r[2]<52 and r[2]-r[1]-sum(slope)>=12 for r in profile)
signature_values=[v for row in profile for v in row]+slope+[0.0,2.4,-2.2,-3.2]
profile_sha256=hashlib.sha256('|'.join(f'{float(v):.9f}' for v in signature_values).encode()).hexdigest()
# This exact corridor is the region whose authored bank surface is below Y0.
uncovered=Polygon([(p[1],p[0]) for p in profile]+[(p[2]-slope[1]*(2.4/4.6),p[0]) for p in reversed(profile)])
water=Polygon([(p[1]+slope[0],p[0]) for p in profile]+[(p[2]-slope[1],p[0]) for p in reversed(profile)])
def polygons(g):
 if g.is_empty:return []
 if g.geom_type=='Polygon':return [g]
 if g.geom_type not in ['MultiPolygon','GeometryCollection']:return []
 result=[]
 for item in g.geoms:result.extend(polygons(item))
 return result
def coords(ring):return [[round(float(x),9),round(float(z),9)] for x,z in list(ring.coords)[:-1]]
def packed(g):
 # GEOS can retain collinear, sub-nanometre slivers at intersecting source
 # edges. Nine-decimal serialization collapses these to zero area. Remove
 # only those numerical rings, never a real hole or component.
 result=[]
 for p in polygons(g):
  outer=coords(p.exterior)
  if Polygon(outer).area<=1e-10:continue
  holes=[coords(h) for h in p.interiors if Polygon(coords(h)).area>1e-10]
  result.append({'outer':outer,'holes':holes})
 return result
def triangles(g):
 result=[]
 for p in polygons(g):
  for tri in constrained_delaunay_triangles(p).geoms:
   if tri.area>1e-10:result.append(coords(tri.exterior))
 return result
def source_bottom(height):
 asset=f'assets/v3/root_buttress/root_buttress_h{height}.glb';raw=(base/asset).read_bytes(); jl=struct.unpack_from('<I',raw,12)[0]; gl=json.loads(raw[20:20+jl]); blob=raw[28+jl:]; polys=[];count=0
 def acc(i):
  a=gl['accessors'][i];v=gl['bufferViews'][a['bufferView']]; n={'SCALAR':1,'VEC3':3}[a['type']];f={5121:'B',5123:'H',5125:'I',5126:'f'}[a['componentType']];unit=struct.calcsize('<'+f*n);off=v.get('byteOffset',0)+a.get('byteOffset',0);stride=v.get('byteStride',unit)
  return np.array([struct.unpack_from('<'+f*n,blob,off+j*stride) for j in range(a['count'])])
 def mat(n):
  if 'matrix'in n:return np.array(n['matrix']).reshape(4,4).T
  x,y,z,w=n.get('rotation',[0,0,0,1]);m=np.eye(4);m[:3,:3]=np.array([[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],[2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],[2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]])@np.diag(n.get('scale',[1,1,1]));m[:3,3]=n.get('translation',[0,0,0]);return m
 def walk(i,parent):
  nonlocal count
  n=gl['nodes'][i];m=parent@mat(n)
  if 'mesh'in n and not any(s in n.get('name','') for s in ['Foliage','Moss','BarkPlates']):
   for q in gl['meshes'][n['mesh']]['primitives']:
    v=acc(q['attributes']['POSITION']);v=v@m[:3,:3].T+m[:3,3]; inds=acc(q['indices']).reshape(-1,3) if'indices'in q else np.arange(len(v)).reshape(-1,3)
    for face in inds:
     tri=v[face]
     if np.max(np.abs(tri[:,1]))<1e-6:
      poly=Polygon(tri[:,[0,2]])
      if poly.area>1e-9:polys.append(poly);count+=1
  for c in n.get('children',[]):walk(c,m)
 for i in gl['scenes'][gl.get('scene',0)]['nodes']:walk(i,np.eye(4))
 return unary_union(polys),{'path':'res://'+asset,'sha256':hashlib.sha256(raw).hexdigest(),'bottom_triangle_count':count,'bottom_area_m2':unary_union(polys).area}
cache={h:source_bottom(h) for h in [10,17,12,3]}
# Store the actual imported geometry identity too: source GLBs are not shipped
# in a Godot PCK. Runtime templates verify this through ResourceLoader remaps.
godot=pathlib.Path(os.environ['LOCALAPPDATA'])/'Programs/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe'
run=subprocess.run([str(godot),'--headless','--path',str(base),'--script','res://scripts_tools/v3/shore_import_signatures.gd'],cwd=base,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=60)
marker='V3_SHORE_IMPORT_SIGNATURES '
lines=[line[len(marker):] for line in run.stdout.splitlines() if line.startswith(marker)]
if run.returncode or len(lines)!=1 or 'ERROR:' in run.stdout+run.stderr:
 raise SystemExit('Imported geometry verification failed; run dev.py import first.\n'+run.stdout[-2000:]+run.stderr[-2000:])
import_report=json.loads(lines[0])
if not import_report.get('ok'):raise SystemExit('Imported geometry signature is incomplete')
for geometry,provenance in cache.values():
 result=import_report['signatures'][provenance['path']]
 if not result['ok']:raise SystemExit('Imported model unavailable: '+provenance['path'])
 provenance['imported_geometry']={key:result[key] for key in ['algorithm','sha256','mesh_count','triangle_count']}
foundations=[];all_foundation=[];supports=[]
for id,h,x,z in [('west_host',10,0,-28),('high_host',17,10,-34),('east_host',12,20,-18),('west_landing',3,-10,-22),('high_landing',3,23,-36),('east_landing',3,34,-27)]:
 source,provenance=cache[h];placed=translate(source,xoff=x,yoff=z);exposed=placed.intersection(uncovered)
 supports.append({'id':id,'height':h,'position':[x,0,z],'source':provenance,'bottom_footprint':packed(placed),'exposed_area_m2':exposed.area})
 if exposed.is_empty:continue
 all_foundation.append(exposed)
 foundations.append({'id':id,'status':'removable_graybox_underwater_extension_not_final_art','top_y':0.0,'bottom_y':-3.2,'polygons':packed(exposed),'top_triangles_xz':triangles(exposed),'area_m2':exposed.area})
crossing_path=base/'data/v3/terrain/f1_growth_crossing.json'
crossing_raw=crossing_path.read_bytes()
crossing=json.loads(crossing_raw)
gate=crossing['gate_foundation']
gate_polygon=Polygon(gate['outer'],gate['holes'])
assert gate_polygon.is_valid and gate_polygon.area>0 and gate['bottom_y']==-3.2 and gate['top_y']==2.9
# The complete base is visible from bed to shutter contact; its exact polygon
# also removes water. It is not a cross-river bridge or an expanded AABB.
all_foundation.append(gate_polygon)
foundations.append({'id':gate['id'],'status':'removable_graybox_gate_base_not_final_art',
 'top_y':gate['top_y'],'bottom_y':gate['bottom_y'],'polygons':packed(gate_polygon),
 'top_triangles_xz':triangles(gate_polygon),'area_m2':gate_polygon.area})
visible_water=water.difference(unary_union(all_foundation))
data={'schema_version':1,'id':'f1_shore_layout_v1','status':'replaceable_graybox_geometry_not_final_art_or_blender_asset','coordinate_system':'Godot world metres; Y up; Z rows strictly increasing','extents':[-52,-50,52,50],'top_y':[0.0,2.4],'water_y':-2.2,'bottom_y':-3.2,'slope_width':slope,'minimum_water_width':12.0,'profile':profile,'generated_from':{'algorithm':'glb_bottom_union_constrained_triangulation_v1','profile_sha256':profile_sha256,'profile':profile,'slope_width':slope,'top_y':[0.0,2.4],'water_y':-2.2,'bottom_y':-3.2,'method':'Read actual GLB triangles transformed by full node hierarchy. Union nondegenerate triangles with all vertices abs(Y)<1e-6, excluding Foliage/Moss/BarkPlates exactly as CrownArena collision. Translate to existing arena placements; intersect with the piecewise bank-height<0 corridor. Preserve every disconnected component and hole; constrained Delaunay triangulation; no convex hull or AABB substitution. Clip water with exactly the same foundation union. Nine decimal metre storage. Recompute after source GLB or profile change.'},'supports':supports,'foundations':foundations,'water_triangles_xz':triangles(visible_water),'water_boundary_polygons':packed(visible_water),'water_area_m2':visible_water.area,'limitations':['Minimum width applies to the two main bank profiles, not navigable space after existing north pillars.','Only underwater exposed Y0 bottom faces are extended; original mesh openings/holes and high geometry are untouched.','Roots that overhang above the actual Y0 plane are not inventively filled.','Water geometry is visual; make_shape(water) must return null. Physical riverbed is Y=-3.2.','Ground shaders and world environmental water queries must be wired to these same profiles/footprints by root; this module does not modify them.','All current optical, task, traversal and boss regressions must be rerun after integration. No artwork, physical flight or GPU acceptance is implied.']}
data['generated_from']['growth_crossing']={'path':'res://data/v3/terrain/f1_growth_crossing.json','sha256':hashlib.sha256(crossing_raw).hexdigest()}
data['limitations'].append('South gate foundation is a separate exact graybox polygon from f1_growth_crossing.json, extending bed to shutter contact Y2.9; approach solids remain outside the water.')
# Serialize without NaN/Infinity; named source hashes and placements remain visible.
serialized=json.dumps(data,ensure_ascii=False,allow_nan=False,indent=2)+'\n'
if args.check:
 if not target.exists() or json.loads(target.read_text(encoding='utf-8-sig'))!=data:
  print('SHORE_GENERATOR stale or missing derived JSON',file=sys.stderr)
  raise SystemExit(1)
else:
 target.parent.mkdir(parents=True,exist_ok=True)
 target.write_text(serialized,encoding='utf-8')
print(json.dumps({'mode':'check' if args.check else 'write','ok':True,
 'profile_rows':len(profile),'profile_sha256':profile_sha256,
 'foundations':len(foundations),'water_triangles':len(data['water_triangles_xz']),
 'water_area_m2':visible_water.area,'output_bytes':len(serialized.encode())}))


