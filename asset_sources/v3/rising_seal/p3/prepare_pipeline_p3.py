"""Copy proven P2 pipeline into owned P3; preserve original checks and add P2 equality."""
from pathlib import Path
import py_compile
HERE=Path(__file__).resolve().parent;P2=HERE.parent/'p2'
s=(P2/'bake_export_p2.py').read_text(encoding='utf-8').replace('_p2','_p3').replace('SealP2','SealP3').replace('default_value=.12','default_value=.75').replace("'core_emission_strength':.12","'core_emission_strength':.75")
s=s.replace("detail=data.uv_layers.new(name='DetailUV');target=data.uv_layers.new(name='SurfaceUV')","data.uv_layers.new(name='DetailUV');data.uv_layers.new(name='SurfaceUV');detail=data.uv_layers['DetailUV'];target=data.uv_layers['SurfaceUV']")
(HERE/'bake_export_p3.py').write_text(s,encoding='utf-8')
s=(P2/'verify_glb_p2.py').read_text(encoding='utf-8').replace('_p2','_p3')
needle="for o in scene.objects:\n if o.type in ['LIGHT','CAMERA']"
insert='''# Strict raw GLB geometry comparison with the frozen runtime P2, independent
# of Blender reimport and of any repeated author-side triangulation.
def exact_float_meshes():
 result={}
 for i,node in enumerate(g['nodes']):
  if 'mesh' not in node:continue
  mat=gltf_world(i);triangles=[]
  for primitive in g['meshes'][node['mesh']]['primitives']:
   ps=[tuple(mat@Vector(p)) for p in accessor(primitive['attributes']['POSITION'])]
   ids=[v[0] for v in accessor(primitive['indices'])]
   triangles.extend(tuple(sorted(ps[j] for j in ids[k:k+3])) for k in range(0,len(ids),3))
  result[node['name']]=sorted(triangles)
 return result
p3_float_exact=exact_float_meshes()
saved_g,saved_binary=g,binary
p2_glb=ROOT/'assets/v3/candidates/rising_seal_p2/rising_seal_p2.glb'
p2_bytes=p2_glb.read_bytes();p2_length=struct.unpack_from('<I',p2_bytes,12)[0]
g=json.loads(p2_bytes[20:20+p2_length]);binary=p2_bytes[28+p2_length:]
parents={c:i for i,n in enumerate(g['nodes']) for c in n.get('children',[])}
p2_float_exact=exact_float_meshes()
p2_raw={}
for i,n in enumerate(g['nodes']):
 if 'mesh' not in n:continue
 mat=gltf_world(i);triangles=[]
 for primitive in g['meshes'][n['mesh']]['primitives']:
  ps=[]
  for pos in accessor(primitive['attributes']['POSITION']):
   q=mat@Vector(pos);ps.append(tuple(round(float(c)*10000) for c in (q.x,-q.z,q.y)))
  ids=[v[0] for v in accessor(primitive['indices'])]
  triangles.extend(tuple(sorted(ps[j] for j in ids[k:k+3])) for k in range(0,len(ids),3))
 p2_raw[n['name']]=sorted(triangles)
for name in groups:
 check(name+'_raw_GLB_multiset_strict_frozen_P2',raw_triangles[name]==p2_raw[name],{'P2':len(p2_raw[name]),'P3':len(raw_triangles[name])})
 check(name+'_raw_GLB_float_coordinates_exact_P2_no_rounding',p3_float_exact[name]==p2_float_exact[name])
g,binary=saved_g,saved_binary
parents={c:i for i,n in enumerate(g['nodes']) for c in n.get('children',[])}
check('exact_18528_triangles',sum(len(v) for v in raw_triangles.values())==18528)
emitting=[m['name'] for m in g['materials'] if max(m.get('emissiveFactor',[0,0,0]))>0]
check('only_core_material_emits',emitting==['SealP3_core'],emitting)
'''
assert needle in s;s=s.replace(needle,insert+needle)
s=s.replace("set(raw)==set(actual) and all(c_actual[t]<=c_raw[t] for t in c_actual)","raw==actual")
s=s.replace("'_actual_reimport_all_unique_faces_no_added_faces'","'_actual_reimport_strict_multiset_source'")
(HERE/'verify_glb_p3.py').write_text(s,encoding='utf-8')
for p in ['build_material_p3.py','bake_export_p3.py','verify_glb_p3.py']:py_compile.compile(str(HERE/p),doraise=True)
print('P3 scripts prepared; no Blender or frozen file write')
