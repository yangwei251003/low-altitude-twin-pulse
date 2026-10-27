"""Inspect exact GLB bytes, delete source, reimport those bytes and probe/render."""
import bpy,bmesh,math,json,hashlib,struct,ast,sys
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
for node in ast.parse((HERE/'build_root_sections_p12.py').read_text(encoding='utf-8')).body:
 if isinstance(node,ast.FunctionDef) and node.name in ['bp','gp','digest','tree']:exec(compile(ast.Module(body=[node],type_ignores=[]),'p12-verified-helper','exec'))
exp=json.loads((HERE/'p12_export_report.json').read_text(encoding='utf-8'));src=json.loads((HERE/'p12_source_report.json').read_text(encoding='utf-8'))
glb=ROOT/exp['glb'];assert sha(glb)==exp['glb_sha256'];blob=glb.read_bytes();assert blob[:4]==b'glTF';length=struct.unpack_from('<I',blob,12)[0];g=json.loads(blob[20:20+length]);binary=blob[28+length:]
checks=[]
def check(name,passed,detail=None):checks.append({'name':name,'pass':bool(passed),'detail':detail})
check('three_runtime_meshes',len(g.get('meshes',[]))==3,len(g.get('meshes',[])))
check('three_materials',len(g.get('materials',[]))==3,len(g.get('materials',[])))
check('embedded_images',all('bufferView' in im and not im.get('uri') for im in g.get('images',[])),len(g.get('images',[])))
def accessor(index):
 a=g['accessors'][index];v=g['bufferViews'][a['bufferView']];w={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']];t={5126:'f',5125:'I',5123:'H',5121:'B'}[a['componentType']];s=struct.Struct('<'+t*w);off=v.get('byteOffset',0)+a.get('byteOffset',0);stride=v.get('byteStride',s.size);return [s.unpack_from(binary,off+i*stride) for i in range(a['count'])]
mesh_stats=[]
for node in g['nodes']:
 if 'mesh' not in node:continue
 count=0
 for primitive in g['meshes'][node['mesh']]['primitives']:
  at=primitive['attributes'];uv=accessor(at['TEXCOORD_0']) if 'TEXCOORD_0' in at else [];count+=len(accessor(primitive['indices']))//3
  check(node['name']+'_single_finite_uv0',bool(uv) and all(math.isfinite(c) for v in uv for c in v) and not any(k.startswith('TEXCOORD_') and k!='TEXCOORD_0' for k in at))
  check(node['name']+'_finite_normals',all(math.isfinite(c) for v in accessor(at['NORMAL']) for c in v))
 mesh_stats.append({'name':node['name'],'triangles':count})
for mat in g['materials']:
 textures=[mat.get('pbrMetallicRoughness',{}).get('baseColorTexture'),mat.get('pbrMetallicRoughness',{}).get('metallicRoughnessTexture'),mat.get('normalTexture')]
 check(mat['name']+'_explicit_PBR_uv0',all(t and t.get('texCoord',0)==0 for t in textures),textures)
bpy.ops.wm.open_mainfile(filepath=str(HERE/'root_buttress_h10_root_sections_p12.blend'));
check('author_source_rock_Sap_anchors_fixed_to_P11',all(digest(bpy.data.objects[n])==v for n,v in src['fixed_geometry_uv_transform_hashes'].items()))
bpy.ops.wm.open_mainfile(filepath=str(ROOT/exp['ready_source']));scene=bpy.context.scene;asset=bpy.data.objects['RootButtress'];parts=[o for o in asset.children_recursive if o.type=='MESH']
def signature(items):
 tris=[]
 for o in items:
  o.data.calc_loop_triangles();ps=[tuple(round(float(c)*10000) for c in o.matrix_world@v.co) for v in o.data.vertices]
  tris.extend(tuple(sorted(ps[i] for i in f.vertices)) for f in o.data.loop_triangles)
 return hashlib.sha256(repr(sorted(tris)).encode()).hexdigest()
source_signatures={'RockMasses':signature([bpy.data.objects['RockMasses']]),'LivingRoots':signature([o for o in parts if o.name.startswith('Root_')]),'SapKnot':signature([bpy.data.objects['SapKnot']])}
check('source_Sap_and_anchors_preserved',all(digest(bpy.data.objects[n])==v for n,v in src['fixed_geometry_uv_transform_hashes'].items() if n!='RockMasses'))
check('source_explicit_single_active_SurfaceUV',all(len(o.data.uv_layers)==1 and o.data.uv_layers.active.name=='SurfaceUV' and o.data.uv_layers.active.active_render for o in parts))
studio=[];camera_name=scene.camera.name;original_objects=list(bpy.data.objects)
for o in scene.objects:
 if o.type in ['LIGHT','CAMERA'] or (o.type=='MESH' and o not in parts and not o.hide_render and not any(c.hide_render for c in o.users_collection)):
  cp=o.copy();cp.data=o.data.copy();studio.append((o.name,cp))
# Actual source deletion, including hidden reference objects; only then GLB import.
for o in original_objects:bpy.data.objects.remove(o,do_unlink=True)
bpy.ops.import_scene.gltf(filepath=str(glb));bpy.context.view_layer.update();meshes=[o for o in scene.objects if o.type=='MESH']
check('actual_reimport_exact_mesh_names',sorted(o.name for o in meshes)==['LivingRoots','RockMasses','SapKnot'],[o.name for o in meshes])
for name,expected in source_signatures.items():check(name+'_export_triangle_geometry_matches_source',signature([o for o in meshes if o.name==name])==expected)
actual_anchors={}
for name,expected in src['anchors_godot'].items():
 found=[o for o in scene.objects if o.name==name];check(name+'_unique',len(found)==1)
 if len(found)==1:
  pos=list(gp(found[0].matrix_world.translation));actual_anchors[name]=pos;check(name+'_position',(Vector(pos)-Vector(expected)).length<.001,pos)
static=tree([o for o in meshes if o.name in ['RockMasses','LivingRoots']]);roots=tree([o for o in meshes if o.name=='LivingRoots']);sap=tree([o for o in meshes if o.name=='SapKnot'])
feet=[(-2.54,2.17),(2.51,2.22),(-2.28,-2.5),(2.31,-2.48)]
for i,(x,z) in enumerate(feet):
 ps=[(x,z)]+[(x+r*math.cos(a*math.tau/64),z+r*math.sin(a*math.tau/64)) for r in [.25,.5,.75] for a in range(64)];bad=[]
 for a,b in ps:
  hit=static.ray_cast(bp((a,15,b)),bp((0,-1,0)),18);p=list(gp(hit[0])) if hit[0] else None
  if p is None or abs(p[1]-10)>.001:bad.append({'xz':[a,b],'hit':p})
 check(f'actual_GLB_foot_{i}_193_Y10',not bad,{'count':len(ps),'failures':bad})
lower=[]
for dx,dz in [(0,0),(-.25,0),(.25,0),(0,-.25),(0,.25)]:
 hit=static.ray_cast(bp((-3.7+dx,6,3.2+dz)),bp((0,-1,0)),2);lower.append(list(gp(hit[0])) if hit[0] else None)
check('actual_GLB_LowerShelf_5_Y5',all(p and abs(p[1]-5)<.001 for p in lower),lower)
target=bp((0,11,4.5));near=roots.find_nearest(target);d=gp(near[0])-Vector((0,11,4.5)) if near[0] else Vector((100,100,100));ell=(d.x/.57)**2+(d.y/.78)**2+(d.z/.4)**2
check('actual_GLB_root_connects_Sap',ell<.93,{'closest':list(gp(near[0])) if near[0] else None,'ellipsoid':ell})
for i,p in enumerate([(0,11,8),(-3,12,8),(3,12,8)]):
 origin=bp(p);d=target-origin;sh=sap.ray_cast(origin,d.normalized(),d.length+1);bh=static.ray_cast(origin,d.normalized(),d.length+1);check(f'actual_GLB_Sap_LOS_{i}',sh[0] is not None and (bh[0] is None or bh[3]>sh[3]+.01),{'sap_distance':sh[3],'solid_distance':bh[3]})
points=[gp(o.matrix_world@v.co) for o in meshes for v in o.data.vertices];bounds={'min':[min(p[k] for p in points) for k in range(3)],'max':[max(p[k] for p in points) for k in range(3)]};lo=[-6.610198020935059,0,-6.804511547088623];hi=[6.905734539031982,11.93212890625,6.879329681396484]
authorized_hi=[hi[0]+.35,hi[1],hi[2]+.35]
extension={'old_min':lo,'old_max':hi,'authorized_max':authorized_hi,'actual':bounds,'actual_positive_extension':[max(0,bounds['max'][k]-hi[k]) for k in range(3)]}
check('actual_GLB_authorized_root_positive_xz_extension_bounds',all(bounds['min'][k]>=lo[k]-.0001 and bounds['max'][k]<=authorized_hi[k]+.0001 for k in range(3)),extension)
check('P11_candidate_frozen',sha(ROOT/'assets/v3/candidates/root_buttress_h10_p11/root_buttress_h10_p11.glb')=='d8e67fdaef057a9adb9fb10545eda90d867d730cb446511f735cfbd42d486f1f')
check('runtime_P2_frozen',all(sha(ROOT/f'assets/v3/root_buttress/root_buttress_h{h}.glb')==v for h,v in exp['runtime_P2_sha256'].items()))
report={'stage':'same-byte GLB real reimport; not game or final artistic acceptance','glb_sha256':sha(glb),'bytes':len(blob),'ready_source_sha256':exp['ready_source_sha256'],'meshes':mesh_stats,'triangles':sum(m['triangles'] for m in mesh_stats),'bounds_godot':bounds,'authorized_bounds':extension,'anchors_godot':actual_anchors,'checks':checks,'passed':sum(c['pass'] for c in checks),'total':len(checks),'all_pass':all(c['pass'] for c in checks),'source_deleted_before_import':True,'limits':['772 discrete foot probes do not replace full Crown motion/sweeps','no Godot scene import, actual lighting, human test or performance measurement','candidate only; all unresolved visual differences remain']}
report['raw_glb_nodes']=[{k:n[k] for k in ['name','mesh','translation','rotation','scale','matrix','children'] if k in n} for n in g['nodes']]
report['raw_glb_materials']=[m['name'] for m in g['materials']]
(HERE/'p12_glb_readback.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8');print('P12_READBACK '+json.dumps(report,ensure_ascii=False),flush=True)
assert report['all_pass'],'Do not render or claim a passing candidate with failed contract'
for name,o in studio:
 scene.collection.objects.link(o)
 if name==camera_name:scene.camera=o
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=8;scene.cycles.use_denoising=True;scene.render.threads_mode='FIXED';scene.render.threads=2;scene.render.resolution_x=1024;scene.render.resolution_y=800;scene.render.resolution_percentage=100
scene.render.filepath=str(HERE/'h10_p12_same_byte_glb_preview.png');bpy.ops.render.render(write_still=True)
assert sha(glb)==exp['glb_sha256'];print('P12_SAME_BYTE_READBACK_DONE',flush=True)
