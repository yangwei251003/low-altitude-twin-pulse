"""Read exact candidate bytes, delete author geometry, import and render GLB."""
from pathlib import Path
import bpy,math,json,hashlib,struct
from collections import Counter
from mathutils import Vector,Matrix,Quaternion
from mathutils.bvhtree import BVHTree
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
ex=json.loads((HERE/'export_report.json').read_text(encoding='utf-8'));sr=json.loads((HERE/'source_report.json').read_text(encoding='utf-8'))
glb=ROOT/ex['glb'];assert sha(glb)==ex['glb_sha256'];blob=glb.read_bytes();length=struct.unpack_from('<I',blob,12)[0];g=json.loads(blob[20:20+length]);binary=blob[28+length:];checks=[]
def check(name,passed,detail=None):checks.append({'name':name,'pass':bool(passed),'detail':detail})
def accessor(index):
 a=g['accessors'][index];v=g['bufferViews'][a['bufferView']];w={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']];t={5126:'f',5125:'I',5123:'H',5121:'B'}[a['componentType']];fmt=struct.Struct('<'+t*w);off=v.get('byteOffset',0)+a.get('byteOffset',0);stride=v.get('byteStride',fmt.size)
 return [fmt.unpack_from(binary,off+i*stride) for i in range(a['count'])]
check('four_runtime_meshes',len(g.get('meshes',[]))==4)
check('four_runtime_materials',len(g.get('materials',[]))==4)
check('all_images_embedded',len(g.get('images',[]))>=12 and all('bufferView' in im and 'uri' not in im for im in g['images']),len(g.get('images',[])))
statistics=[]
for n in g['nodes']:
 if 'mesh' not in n:continue
 triangles=0
 for primitive in g['meshes'][n['mesh']]['primitives']:
  a=primitive['attributes'];uv=accessor(a['TEXCOORD_0']) if 'TEXCOORD_0' in a else []
  triangles+=len(accessor(primitive['indices']))//3
  check(n['name']+'_single_finite_UV0',bool(uv) and all(math.isfinite(c) and -.0001<=c<=1.0001 for pair in uv for c in pair) and not any(k.startswith('TEXCOORD_') and k!='TEXCOORD_0' for k in a))
  check(n['name']+'_finite_normal',bool(a.get('NORMAL') is not None) and all(math.isfinite(c) for v in accessor(a['NORMAL']) for c in v))
 statistics.append({'name':n['name'],'triangles':triangles})
for m in g['materials']:
 t=[m.get('pbrMetallicRoughness',{}).get('baseColorTexture'),m.get('pbrMetallicRoughness',{}).get('metallicRoughnessTexture'),m.get('normalTexture')]
 check(m['name']+'_PBR_bound_to_UV0',all(x and x.get('texCoord',0)==0 for x in t),t)
bpy.ops.wm.open_mainfile(filepath=str(ROOT/ex['ready_source']));scene=bpy.context.scene;root=bpy.data.objects['RisingSeal'];parts=[o for o in root.children if o.type=='MESH']
check('ready_source_hash',sha(ROOT/ex['ready_source'])==ex['ready_sha256'])
check('active_render_SurfaceUV',all(o.data.uv_layers.active.name=='SurfaceUV' and o.data.uv_layers.active.active_render for o in parts))
groups={'StoneMasses':[o for o in parts if o.name.startswith(('StoneMass_','SeamClosure','SealRecess'))],'LivingRoots':[o for o in parts if o.name.startswith('RootWrap_')],'BronzeFittings':[o for o in parts if o.name.startswith(('BronzeChannel_','PanelClamp_','SealBronzeBoss','SealOuterRing','SealPatinaRing'))],'SealEnergyGlass':[bpy.data.objects['SealEnergyGlass']]}
def triangle_list(obs):
 triangles=[]
 for o in obs:
  o.data.calc_loop_triangles();p=[tuple(round(float(c)*10000) for c in o.matrix_world@v.co) for v in o.data.vertices]
  triangles.extend(tuple(sorted(p[i] for i in f.vertices)) for f in o.data.loop_triangles)
 return sorted(triangles)
def signature(obs):return hashlib.sha256(repr(triangle_list(obs)).encode()).hexdigest()
expected={n:signature(obs) for n,obs in groups.items()};expected_triangles={n:triangle_list(obs) for n,obs in groups.items()};studio=[];camera_name=scene.camera.name
source_entries={};allverts=[];allfaces=[]
for ob in parts:
 ob.data.calc_loop_triangles();ps=[ob.matrix_world@v.co for v in ob.data.vertices];offset=len(allverts);allverts.extend(ps)
 for tri in ob.data.loop_triangles:
  allfaces.append(tuple(offset+i for i in tri.vertices));p=[ps[i] for i in tri.vertices];key=tuple(sorted(tuple(round(float(c)*10000) for c in q) for q in p));cross=(p[1]-p[0]).cross(p[2]-p[0]);centre=sum(p,Vector())/3
  source_entries.setdefault(key,[]).append({'object':ob.name,'polygon':tri.polygon_index,'vertices':list(tri.vertices),'area_m2':cross.length*.5,'centre_blender':list(centre),'geometric_normal':list(cross.normalized())})
tree=BVHTree.FromPolygons(allverts,allfaces,all_triangles=True);duplicate_details=[]
for key,entries in source_entries.items():
 if len(entries)<2:continue
 centre=Vector(entries[0]['centre_blender']);direction=(scene.camera.matrix_world.translation-centre).normalized();hit=tree.ray_cast(centre+direction*25,-direction,25.01)
 dots=[Vector(entries[0]['geometric_normal']).dot(Vector(e['geometric_normal'])) for e in entries[1:]]
 duplicate_details.append({'triangle_quantized_0_1mm':key,'entries':entries,'normal_dot_first_to_rest':dots,'same_original_object':len({e['object'] for e in entries})==1,'same_original_polygon':len({(e['object'],e['polygon']) for e in entries})==1,'default_camera_first_hit_distance_from_25m':hit[3],'default_camera_occluded':hit[0] is not None and hit[3]<24.995})
(HERE/'duplicate_face_classification.json').write_text(json.dumps({'source_sha256':sr['source_sha256'],'groups':duplicate_details,'note':'actual geometric winding and ray evidence, not a general self-intersection certificate'},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
# GLB node transforms are column-major; compare raw binary triangles BEFORE
# Blender import validation can remove duplicate coincident faces.
parents={c:i for i,n in enumerate(g['nodes']) for c in n.get('children',[])}
def gltf_world(i):
 n=g['nodes'][i]
 if 'matrix' in n:local=Matrix([n['matrix'][k:k+4] for k in range(0,16,4)]).transposed()
 else:
  x,y,z,w=n.get('rotation',[0,0,0,1]);local=Matrix.Translation(Vector(n.get('translation',[0,0,0])))@Quaternion((w,x,y,z)).to_matrix().to_4x4()@Matrix.Diagonal(Vector([*n.get('scale',[1,1,1]),1]))
 return gltf_world(parents[i])@local if i in parents else local
raw_triangles={}
for i,n in enumerate(g['nodes']):
 if 'mesh' not in n:continue
 mat=gltf_world(i);triangles=[]
 for primitive in g['meshes'][n['mesh']]['primitives']:
  positions=[]
  for p in accessor(primitive['attributes']['POSITION']):
   q=mat@Vector(p);positions.append(tuple(round(float(c)*10000) for c in (q.x,-q.z,q.y)))
  indices=[x[0] for x in accessor(primitive['indices'])]
  triangles.extend(tuple(sorted(positions[j] for j in indices[k:k+3])) for k in range(0,len(indices),3))
 raw_triangles[n['name']]=sorted(triangles)
for o in scene.objects:
 if o.type in ['LIGHT','CAMERA'] or (o.type=='MESH' and o not in parts and not o.hide_render and not any(c.hide_render for c in o.users_collection)):
  cp=o.copy();cp.data=o.data.copy();studio.append((o.name,cp))
for o in list(bpy.data.objects):bpy.data.objects.remove(o,do_unlink=True)
bpy.ops.import_scene.gltf(filepath=str(glb));bpy.context.view_layer.update();meshes=[o for o in scene.objects if o.type=='MESH']
check('actual_reimport_exact_mesh_names',sorted(o.name for o in meshes)==sorted(groups),[o.name for o in meshes])
for name,s in expected.items():
 items=[o for o in meshes if o.name==name];actual=triangle_list(items);detail=None
 if signature(items)!=s:
  a=set(expected_triangles[name]);b=set(actual);missing=Counter(expected_triangles[name])-Counter(actual)
  multiplicities=[{'triangle':t,'removed_copies':count,'area_m2':(Vector(t[1])-Vector(t[0])).cross(Vector(t[2])-Vector(t[0])).length/2e8} for t,count in missing.items()]
  detail={'source_triangle_count':len(expected_triangles[name]),'import_triangle_count':len(actual),'only_source_count':len(a-b),'only_import_count':len(b-a),'only_source_examples':list(a-b)[:12],'only_import_examples':list(b-a)[:12],'multiplicity_differences':multiplicities,'coordinates_unit':'0.1mm rounded Blender world'}
 raw=raw_triangles[name]
 check(name+'_raw_GLB_triangle_multiset_exact_source',raw==expected_triangles[name],{'source_count':len(expected_triangles[name]),'raw_GLB_count':len(raw)})
 c_raw=Counter(raw);c_actual=Counter(actual)
 check(name+'_actual_reimport_all_unique_faces_no_added_faces',set(raw)==set(actual) and all(c_actual[t]<=c_raw[t] for t in c_actual),detail or {'removed_coincident_copies':len(raw)-len(actual)})
gp=lambda p:Vector((p.x,p.z,-p.y))
anchors={}
for name,p in ex['anchors_godot'].items():
 obs=[o for o in scene.objects if o.name==name];check(name+'_unique',len(obs)==1)
 if obs:
  actual=gp(obs[0].matrix_world.translation);anchors[name]=list(actual);check(name+'_exact_position',(actual-Vector(p)).length<1e-5,anchors[name])
points=[gp(o.matrix_world@v.co) for o in meshes for v in o.data.vertices];bounds={'min':[min(p[k] for p in points) for k in range(3)],'max':[max(p[k] for p in points) for k in range(3)]}
check('actual_GLB_moving_1x5x7_envelope',all(bounds['min'][k]>=lo-.00001 and bounds['max'][k]<=hi+.00001 for k,(lo,hi) in enumerate([(-.5,.5),(-2.5,2.5),(-3.5,3.5)])),bounds)
check('actual_GLB_source_bounds_match',all(abs(bounds[s][k]-sr['bounds_godot'][s][k])<.00001 for s in ['min','max'] for k in range(3)))
check('unchanged_readonly_sources',all(sha(ROOT/p)==v for p,v in ex['readonly_inputs'].items()))
check('external_PBR_files_match',all(sha(ROOT/m['path'])==m['sha256'] for m in ex['maps']))
result={'stage':'actual same-byte GLB reimport; offline only, no game acceptance','glb_sha256':sha(glb),'bytes':len(blob),'source_sha256':ex['source_sha256'],'ready_sha256':ex['ready_sha256'],'source_deleted_before_import':True,'meshes':statistics,'triangles':sum(s['triangles'] for s in statistics),'bounds_godot':bounds,'anchors_godot':anchors,'raw_nodes':g['nodes'],'materials':[m['name'] for m in g['materials']],'images':len(g['images']),'checks':checks,'passed':sum(c['pass'] for c in checks),'total':len(checks),'all_pass':all(c['pass'] for c in checks),'limits':['not final artistic approval','no Godot import, movement, anti-pinch, network or GPU performance test','edge closure/source tests do not independently prove no self intersections']}
(HERE/'glb_readback.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print('SEAL_READBACK',result['passed'],result['total'],json.dumps([c for c in checks if not c['pass']]),flush=True)
assert result['all_pass']
for name,o in studio:
 scene.collection.objects.link(o)
 if name==camera_name:scene.camera=o
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=12;scene.cycles.use_denoising=True;scene.render.threads_mode='FIXED';scene.render.threads=2
scene.render.resolution_x=1200;scene.render.resolution_y=960;scene.render.resolution_percentage=100;scene.render.filepath=str(HERE/'rising_seal_p2_same_byte_glb_preview.png');bpy.ops.render.render(write_still=True)
assert sha(glb)==ex['glb_sha256'];print('SEAL_SAME_BYTE_PREVIEW_DONE',flush=True)
