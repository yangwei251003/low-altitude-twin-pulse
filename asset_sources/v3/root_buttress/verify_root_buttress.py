"""Independent GLB byte inspection, real reimport, point probes, actual reimport PNG.
This does not run Godot or claim gameplay/visual/performance acceptance.
"""
import bpy,json,math,struct,hashlib,sys
import numpy as np
from pathlib import Path
from mathutils import Vector,Matrix,Quaternion
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[3];SRC=ROOT/'asset_sources/v3/root_buttress';OUT=ROOT/'assets/v3/root_buttress';ART=ROOT/'artifacts/v3/art/root_buttress'
H=int(sys.argv[sys.argv.index('--height')+1]);REV=int(sys.argv[sys.argv.index('--revision')+1]) if '--revision' in sys.argv else 2
glb=OUT/f'root_buttress_h{H}.glb';blob=glb.read_bytes();sha=hashlib.sha256(blob).hexdigest()
assert blob[:4]==b'glTF' and struct.unpack_from('<I',blob,4)[0]==2
jlen=struct.unpack_from('<I',blob,12)[0];g=json.loads(blob[20:20+jlen]);bin_start=20+jlen+8;binary=blob[bin_start:]
checks=[]
def check(name,okay,detail=None):checks.append({'name':name,'pass':bool(okay),'detail':detail})
def acc(index):
 a=g['accessors'][index];v=g['bufferViews'][a['bufferView']];count={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']];dtype={5126:'<f4',5125:'<u4',5123:'<u2',5121:'u1'}[a['componentType']]
 start=v.get('byteOffset',0)+a.get('byteOffset',0);item=np.dtype(dtype).itemsize;stride=v.get('byteStride',count*item)
 return np.ndarray((a['count'],count),dtype=dtype,buffer=binary,offset=start,strides=(stride,item)).copy()
nodes=g['nodes'];world={}
def visit(i,parent):
 n=nodes[i]
 if 'matrix' in n:m=Matrix(np.array(n['matrix']).reshape((4,4),order='F').tolist())
 else:
  q=n.get('rotation',[0,0,0,1]);m=Matrix.LocRotScale(Vector(n.get('translation',[0,0,0])),Quaternion((q[3],q[0],q[1],q[2])),Vector(n.get('scale',[1,1,1])))
 world[i]=parent@m
 for c in n.get('children',[]):visit(c,world[i])
for i in g['scenes'][g.get('scene',0)]['nodes']:visit(i,Matrix.Identity(4))
anchors={'GroundOrigin':[0,0,0],'BodyPerch':[0,H+3,0],'HostTarget':[0,H+1,4.5]}
if H!=3:anchors['LowerShelf']=[-3.7,5*(H-3)/7,3.2]
anchor_actual={}
for name,expected in anchors.items():
 ids=[i for i,n in enumerate(nodes) if n.get('name')==name];check(name+'_unique',len(ids)==1,ids)
 if len(ids)==1:
  p=world[ids[0]].translation;anchor_actual[name]=list(p);check(name+'_position',(p-Vector(expected)).length<.001,list(p))
check('h3_has_no_mid_shelf',H!=3 or not any(n.get('name')=='LowerShelf' for n in nodes))
triangles=0;points=[];primitives=[]
for i,node in enumerate(nodes):
 if 'mesh' not in node:continue
 for prim in g['meshes'][node['mesh']]['primitives']:
  at=prim['attributes'];p=acc(at['POSITION']);points.extend(list(world[i]@Vector(v)) for v in p)
  count=len(acc(prim['indices'])) if 'indices' in prim else len(p);triangles+=count//3
  uv=acc(at['TEXCOORD_0']) if 'TEXCOORD_0' in at else np.array([])
  check(node['name']+'_uv0_finite',uv.size>0 and np.isfinite(uv).all())
  check(node['name']+'_only_one_uv',not any(k.startswith('TEXCOORD_') and k!='TEXCOORD_0' for k in at))
  primitives.append({'node':node['name'],'triangles':count//3,'material':prim.get('material'),'attributes':list(at)})
check('runtime_mesh_count_5_or_less',len(g['meshes'])<=5,len(g['meshes']))
check('material_count_4_or_less',len(g['materials'])<=4,len(g['materials']))
check('triangles_under_22000',triangles<22000,triangles)
check('images_embedded',all('bufferView' in im and not im.get('uri') for im in g.get('images',[])),len(g.get('images',[])))
for mat in g['materials']:
 textures=[mat.get('pbrMetallicRoughness',{}).get('baseColorTexture'),mat.get('pbrMetallicRoughness',{}).get('metallicRoughnessTexture'),mat.get('normalTexture')]
 check(mat['name']+'_pbr_uv0',all(t and t.get('texCoord',0)==0 for t in textures),textures)
bounds={'min':np.min(points,axis=0).tolist(),'max':np.max(points,axis=0).tolist()}
check('base_y0',abs(bounds['min'][1])<.001,bounds['min'][1]);check('xz_extent_under_7_35',max(abs(bounds['min'][0]),abs(bounds['min'][2]),abs(bounds['max'][0]),abs(bounds['max'][2]))<7.35,bounds)
source=SRC/f'root_buttress_h{H}_material_p{REV}.blend';bpy.ops.wm.open_mainfile(filepath=str(source))
originals=[o for o in bpy.data.collections['Editable_RootButtress'].objects if o.type=='MESH']
check('source_editable_parts_retained',len(originals)>50,len(originals))
check('source_unique_active_uv',all(len(o.data.uv_layers)==1 and o.data.uv_layers.active.name=='SurfaceUV' and o.data.uv_layers[0].active_render for o in originals))
# Delete source and the studio; only the file just hashed is imported below.
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(glb));bpy.context.view_layer.update()
meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
check('real_reimport_mesh_count',len(meshes)==len(g['meshes']),len(meshes))
def bp(p):return Vector((p[0],-p[2],p[1]))
def gp(p):return Vector((p.x,p.z,-p.y))
def tree_for(items):
 vs=[];fs=[]
 for ob in items:
  ob.data.calc_loop_triangles();off=len(vs);vs.extend(ob.matrix_world@v.co for v in ob.data.vertices);fs.extend(tuple(off+i for i in f.vertices) for f in ob.data.loop_triangles)
 return BVHTree.FromPolygons(vs,fs,all_triangles=True)
static=tree_for([o for o in meshes if o.name in ('RockMasses','LivingRoots')]);roots=tree_for([o for o in meshes if o.name=='LivingRoots']);sap=tree_for([o for o in meshes if o.name=='SapKnot']) if H!=3 else None
feet=[]
for x in [-3,3]:
 for z in [-3,3]:
  hits=[]
  for dx,dz in [(0,0),(-.35,0),(.35,0),(0,-.35),(0,.35),(-.25,-.25),(.25,-.25),(-.25,.25),(.25,.25)]:
   hit=static.ray_cast(bp((x+dx,H+4,z+dz)),bp((0,-1,0)),H+5);hits.append(list(gp(hit[0])) if hit[0] else None)
  okay=all(p is not None and abs(p[1]-H)<.015 for p in hits);check(f'foot_{x}_{z}_nine_points',okay,hits);feet.append({'centre':[x,H,z],'samples':hits})
if H!=3:
 y=anchors['LowerShelf'][1];hit=static.ray_cast(bp((-3.7,y+1,3.2)),bp((0,-1,0)),2);check('lower_shelf_support',hit[0] is not None and abs(gp(hit[0]).y-y)<.015)
if H==3:check('fall_platform_no_visible_or_target_sap',not any(o.name=='SapKnot' for o in meshes))
else:
 target=bp(anchors['HostTarget']);nearest=roots.find_nearest(target)
 normalized=gp(nearest[0])-Vector(anchors['HostTarget']) if nearest[0] else Vector((100,100,100))
 inside=(normalized.x/.57)**2+(normalized.y/.78)**2+(normalized.z/.40)**2
 check('live_root_enters_sap_volume',inside<.93,{'closest_root_point':list(gp(nearest[0])) if nearest[0] else None,'ellipsoid_squared_radius':inside})
 for k,p in enumerate([(0,H+1,8),(-3,H+2,8),(3,H+2,8)]):
  origin=bp(p);direction=(target-origin).normalized();length=(target-origin).length
  sh=sap.ray_cast(origin,direction,length+1);bh=static.ray_cast(origin,direction,length+1)
  check(f'front_target_visible_{k}',sh[0] is not None and (bh[0] is None or bh[3]>sh[3]+.01),{'sap_distance':sh[3],'static_distance':bh[3]})
report={'asset':f'RootButtressH{H}','status':'candidate byte/reimport checks, not final art or game acceptance','glb_path':str(glb.relative_to(ROOT)).replace('\\','/'),'glb_sha256':sha,'bytes':len(blob),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'height':H,'bounds_godot':bounds,'anchors_godot':anchor_actual,'meshes':primitives,'triangles':triangles,'materials':[m['name'] for m in g['materials']],'foot_samples':feet,'checks':checks,'passed':sum(c['pass'] for c in checks),'total':len(checks),'all_checks_pass':all(c['pass'] for c in checks),'render_source':'actual same-byte GLB deleted-source reimport, CPU2 8 samples','limits':'36 discrete foot points, three front rays; no actual Godot sweep/human/performance claim'}
report_path=ART/f'root_buttress_h{H}_readback_p{REV}.json';report_path.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'height':H,'sha256':sha,'passed':report['passed'],'total':report['total'],'failed':[c for c in checks if not c['pass']]},ensure_ascii=False),flush=True)
if '--render' in sys.argv:
 scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=8;scene.cycles.use_denoising=True
 scene.render.threads_mode='FIXED';scene.render.threads=2;scene.render.resolution_x=1024;scene.render.resolution_y=800;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG';scene.view_settings.view_transform='AgX'
 def aim(ob,t):ob.rotation_euler=(bp(t)-ob.location).to_track_quat('-Z','Y').to_euler()
 bpy.ops.object.camera_add(location=bp((20,H*.53+17.2,20)));cam=bpy.context.object;cam.data.type='ORTHO';cam.data.ortho_scale=23.5+(H-10)*.70;aim(cam,(0,H*.53,0));scene.camera=cam
 bpy.ops.mesh.primitive_plane_add(size=150,location=bp((0,-.05,0)));floor=bpy.context.object
 mat=bpy.data.materials.new('ReviewOnlyFloor');mat.use_nodes=True;mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(.25,.25,.25,1);floor.data.materials.append(mat)
 for at,power,size in [((-12,22,18),2700,12),((15,14,-8),2100,10),((-6,15,-14),2000,9)]:
  bpy.ops.object.light_add(type='AREA',location=bp(at));light=bpy.context.object;light.data.energy=power;light.data.size=size;aim(light,(0,H*.5,0))
 scene.world.use_nodes=True;bg=scene.world.node_tree.nodes['Background'];bg.inputs['Color'].default_value=(.40,.40,.40,1);bg.inputs['Strength'].default_value=.6
 scene.render.filepath=str(ART/f'root_buttress_h{H}_glb_preview_p{REV}.png');bpy.ops.render.render(write_still=True)
assert report['all_checks_pass'], 'Candidate failed one or more strict reimport checks; do not lower assertions'
