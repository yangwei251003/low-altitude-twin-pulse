"""Actual frozen candidate GLB readback, collision geometry, UVs and one image."""
import bpy,bmesh,hashlib,json,struct,sys
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
OUT=Path(__file__).resolve().parent;PROJECT=OUT.parents[3]
meta=json.loads((OUT/'p12_export_report.json').read_text());GLB=Path(meta['glb'])
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(GLB)==meta['sha256']
ready=OUT/'shore_root_t03a_p12_export_ready.blend';assert sha(ready)==meta['ready_source_sha256']
retopo=json.loads((OUT/'p12_retopology_report.json').read_text())
raw=GLB.read_bytes();assert raw[:4]==b'glTF';length,kind=struct.unpack_from('<II',raw,12);gltf=json.loads(raw[20:20+length])
bpy.ops.wm.open_mainfile(filepath=str(ready));scene=bpy.context.scene
source_root=bpy.data.objects['ShoreRootT03A'];source_parts=[o for o in source_root.children if o.type=='MESH']
def gp(v):return Vector((v.x,v.z,-v.y))
def bp(v):return Vector((v[0],-v[2],v[1]))
def tree(obs):
 points=[];faces=[]
 for o in obs:
  o.data.calc_loop_triangles();off=len(points);points.extend(o.matrix_world@v.co for v in o.data.vertices)
  faces.extend(tuple(off+i for i in t.vertices) for t in o.data.loop_triangles)
 return BVHTree.FromPolygons(points,faces,all_triangles=True)
def topo(o):
 bm=bmesh.new();bm.from_mesh(o.data);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-5)
 unseen=set(bm.verts);parts=[]
 while unseen:
  stack=[unseen.pop()];n=0
  while stack:
   v=stack.pop();n+=1
   for e in v.link_edges:
    j=e.other_vert(v)
    if j in unseen:unseen.remove(j);stack.append(j)
  parts.append(n)
 result={'components':sorted(parts,reverse=True),'boundary_edges':sum(e.is_boundary for e in bm.edges),'nonmanifold_edges':sum(not e.is_manifold for e in bm.edges),'volume':bm.calc_volume(signed=True)};bm.free();return result
def inside(t,p):
 votes=0
 for d in [Vector((.937,.281,.207)),Vector((-.193,.931,.311)),Vector((.271,-.347,.898))]:
  d.normalize();q=p.copy();n=0
  for _ in range(80):
   hit=t.ray_cast(q,d,50)[0]
   if hit is None:break
   n+=1;q=hit+d*.0001
  votes+=n%2
 return votes>=2
source_trees={'RockMasses':tree([o for o in source_parts if o.name.startswith('Rock_')]),'LivingRoots':tree([bpy.data.objects['Root_MainFork']])}
source_vertices={kind:[o.matrix_world@v.co for o in source_parts if (o.name.startswith('Rock_') if kind=='RockMasses' else o.name=='Root_MainFork') for v in o.data.vertices] for kind in source_trees}
for o in source_parts:o.hide_render=True
for name in ['ShoreRootT03A','GroundOrigin','BridgeJoin','WestBlend']:bpy.data.objects[name].name='Source_'+name
old=set(bpy.data.objects);bpy.ops.import_scene.gltf(filepath=str(GLB));imported=[o for o in bpy.data.objects if o not in old]
mesh_objects={o.name:o for o in imported if o.type=='MESH'};anchors={o.name:list(gp(o.matrix_world.translation)) for o in imported if o.type=='EMPTY'}
checks=[]
def check(n,ok,detail=None):checks.append({'name':n,'pass':bool(ok),'detail':detail})
check('actual_byte_hash',sha(GLB)==meta['sha256'],meta['sha256'])
check('two_actual_meshes',set(mesh_objects)=={'RockMasses','LivingRoots'},list(mesh_objects))
check('two_pbr_materials',len(gltf.get('materials',[]))==2,len(gltf.get('materials',[])))
check('all_textures_embedded',len(gltf.get('images',[]))>=6 and all('bufferView' in i and 'uri' not in i for i in gltf['images']),gltf.get('images'))
check('all_mesh_primitives_have_UV0',all('TEXCOORD_0' in p['attributes'] for m in gltf['meshes'] for p in m['primitives']))
for name,target in [('GroundOrigin',(0,0,0)),('BridgeJoin',(4.5,4.5,0)),('WestBlend',(-4.3,.34,0))]:
 matches=[o for o in imported if o.name==name]
 check(name+'_unique_position',len(matches)==1 and (gp(matches[0].matrix_world.translation)-Vector(target)).length<2e-5,anchors.get(name))
newtrees={name:tree([o]) for name,o in mesh_objects.items()};bounds={};triangles={}
for name,o in mesh_objects.items():
 t=topo(o);expected=4 if name=='RockMasses' else 1
 check(name+'_closed_components',len(t['components'])==expected and t['boundary_edges']==0 and t['nonmanifold_edges']==0 and t['volume']>0,t)
 f=max(newtrees[name].find_nearest(p)[3] for p in source_vertices[name]);r=max(source_trees[name].find_nearest(o.matrix_world@v.co)[3] for v in o.data.vertices)
 check(name+'_source_actual_geometry_match',max(f,r)<.00003,{'source_to_glb_max_m':f,'glb_to_source_max_m':r})
 check(name+'_one_UV_layer',len(o.data.uv_layers)==1,len(o.data.uv_layers))
 ps=[gp(o.matrix_world@v.co) for v in o.data.vertices];bounds[name]={'min':[min(p[i] for p in ps) for i in range(3)],'max':[max(p[i] for p in ps) for i in range(3)]}
 o.data.calc_loop_triangles();triangles[name]=len(o.data.loop_triangles)
check('whole_candidate_engineering_envelope',all(b['min'][0]>=-4.55 and b['max'][0]<=4.501 and b['min'][2]>=-6 and b['max'][2]<=6 and b['max'][1]<=5.001 for b in bounds.values()),bounds)
rocktree=newtrees['RockMasses'];root_tree=newtrees['LivingRoots'];contacts=[]
for x,z in [(-2.43,-2.5),(-2.31,3.03),(-1.45,3.65)]:
 wp=root_tree.ray_cast(bp((x,-3,z)),bp((0,1,0)),12)[0];sp=rocktree.ray_cast(bp((x,8,z)),bp((0,-1,0)),15)[0]
 burial=gp(sp).y-gp(wp).y if sp is not None and wp is not None else None
 contacts.append({'xz':[x,z],'burial_m':burial});check('contact_'+str((x,z)),burial is not None and .025<burial<.035,contacts[-1])
base_points=[bp(p) for p in retopo['base_cap_points_godot']]
bad=[list(gp(p)) for p in base_points if rocktree.find_nearest(p)[3]<.008 or not inside(rocktree,p)]
check('actual_root_base_183_inside',len(base_points)==183 and not bad,bad)
hits=[]
for x in [3.55,4.,4.49]:
 for z in [-2.75,-1.375,0,1.375,2.75]:
  p=rocktree.ray_cast(bp((x,8,z)),bp((0,-1,0)),15)[0];hits.append(list(gp(p)) if p is not None else None)
check('actual_join_15_probes',all(p is not None and abs(p[1]-4.5)<.001 for p in hits),hits)
face_hits=[]
for y in [.25,1.,2.,3.,4.25]:
 for z in [-2.75,-1.375,0,1.375,2.75]:
  point=rocktree.ray_cast(bp((7,y,z)),bp((-1,0,0)),5)[0]
  face_hits.append(list(gp(point)) if point is not None else None)
check('actual_side_join_25_probes',all(p is not None and abs(p[0]-4.5)<.001 for p in face_hits),face_hits)
result={'stage':'actual same-byte GLB offline reimport, not Godot acceptance','sha256':sha(GLB),'bytes':GLB.stat().st_size,'anchors':anchors,'bounds':bounds,'triangles':triangles,'checks':checks,'passed':sum(c['pass'] for c in checks),'total':len(checks),'all_pass':all(c['pass'] for c in checks),'limits':['No real engine import, flight-body sweep or game camera.','Four stones and roots intentionally intersect at support contacts.','Source scan-derived geometry and authored closures are both retained in editable sources.']}
(OUT/'p12_glb_readback.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
for c in checks:
 if not c['pass']:print('P12_READBACK_FAIL '+json.dumps(c),flush=True)
assert result['all_pass'],'Do not render or promote a failed GLB'
if '--render' in sys.argv:
 bridge=PROJECT/'assets/v3/root_arch/f1_root_arch.glb';bridge_sha=sha(bridge)
 old=set(bpy.data.objects);bpy.ops.import_scene.gltf(filepath=str(bridge));new=[o for o in bpy.data.objects if o not in old]
 bridge_root=next(o for o in new if o.name=='F1RootArch');bridge_root.location+=bp((24.5,0,0))
 colours={'WalkableRoot':(.285,.225,.165),'StoneRemnants':(.28,.285,.27),'Moss':(.17,.23,.14),'Foliage':(.21,.27,.16)}
 for o in new:
  if o.type!='MESH':continue
  m=bpy.data.materials.new('BridgeAssemblyBasic_'+o.name);m.use_nodes=True;p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*colours[o.name],1);p.inputs['Roughness'].default_value=.87
  for i in range(len(o.data.materials)):o.data.materials[i]=m
 scene.render.filepath=str(OUT/'p12-actual-glb-bridge-assembly.png');scene.cycles.samples=12;scene.cycles.device='CPU';scene.render.threads_mode='FIXED';scene.render.threads=2
 bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'p12_actual_glb_readback_assembly.blend'));bpy.ops.render.render(write_still=True)
 assert sha(bridge)==bridge_sha
 result['image_sha256']=sha(OUT/'p12-actual-glb-bridge-assembly.png');(OUT/'p12_glb_readback.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
assert sha(GLB)==meta['sha256']
print('P12_ACTUAL_READBACK '+json.dumps({'passed':result['passed'],'total':result['total'],'sha256':result['sha256']}),flush=True)
