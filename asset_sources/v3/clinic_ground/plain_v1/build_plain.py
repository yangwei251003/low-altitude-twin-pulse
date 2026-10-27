"""PREPARED ONLY. Root schedules CPU2. No bake, GLB, Godot or frozen-file save.
Two plain modules reuse actual clean P2 UV atlas areas, not projected concept art.
"""
from pathlib import Path
import bpy,bmesh,json,hashlib,importlib.util,sys,math,time,os
from mathutils import Matrix,Vector
from mathutils.bvhtree import BVHTree
HERE=Path(__file__).resolve().parent;sys.dont_write_bytecode=True
P2=HERE.parent/'p2';BASE=P2/'clinic_ground_p2.blend'
BASE_SHA='db2fc7404c5f39be93339b541e9f15c96c6bd5a5b9f93b176ce3cac6a90cc8cf'
spec=importlib.util.spec_from_file_location('frozen_geometry_helper',HERE.parent/'p1/build_ground.py')
H=importlib.util.module_from_spec(spec);spec.loader.exec_module(H)
H.SRC=HERE;H.PIECES=[];H.CHECKS=[]
CONFIG=json.loads((HERE/'sampling_contract.json').read_text(encoding='utf-8'))
PITCH=1.8

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def gd(p):return (float(p[0]),float(p[2]),float(-p[1]))
def bg(p):return (p[0],-p[2],p[1])
def ping(t):return 1-abs(t%2-1)
def clean_uv(a,b):
 x=-2.7+PITCH*ping(a/PITCH);z=.1+PITCH*ping(b/PITCH)
 return tuple(c[0]*x+c[1]*z+c[2] for c in CONFIG['concrete_patch']['uv_affine_x_z_constant'])
def cut_points(offset):
 return [k*PITCH-offset for k in range(-4,5) if -3+1e-6<k*PITCH-offset<3-1e-6]

def apply_metric_uv(o,offset,is_seal):
 dg=bpy.context.evaluated_depsgraph_get()
 mesh=bpy.data.meshes.new_from_object(o.evaluated_get(dg),preserve_all_data_layers=True,depsgraph=dg)
 mesh.transform(o.matrix_world);o.modifiers.clear();o.data=mesh;o.matrix_world=Matrix.Identity(4)
 if not is_seal:
  bm=bmesh.new();bm.from_mesh(mesh)
  # Split only existing faces where mirrored coordinates reverse. Never change
  # positions/silhouette or interpolate a whole face across a texture fold.
  for axis,off in [('X',offset[0]),('Z',offset[1])]:
   for value in cut_points(off):
    co=(value,0,0) if axis=='X' else (0,-value,0)
    no=(1,0,0) if axis=='X' else (0,1,0)
    bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=1e-7,plane_co=co,plane_no=no,clear_inner=False,clear_outer=False)
  bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(mesh);bm.free()
 while mesh.uv_layers:mesh.uv_layers.remove(mesh.uv_layers[0])
 mesh.uv_layers.new(name='SurfaceUV');mesh.uv_layers.active_index=0;mesh.uv_layers['SurfaceUV'].active_render=True
 uv=mesh.uv_layers['SurfaceUV'];mesh.update()
 for face in mesh.polygons:
  axis=max(range(3),key=lambda i:abs(face.normal[i]))
  for k,li in enumerate(face.loop_indices):
   if is_seal:
    center=CONFIG['dark_seal_patch']['uv_center'];r=CONFIG['dark_seal_patch']['uv_safe_radius']
    angle=2*math.pi*k/len(face.loop_indices);coord=(center[0]+r*math.cos(angle),center[1]+r*math.sin(angle))
   else:
    x,h,z=gd(mesh.vertices[mesh.loops[li].vertex_index].co)
    if axis==2:coord=clean_uv(x+offset[0],z+offset[1])
    elif axis==0:coord=clean_uv(z+offset[1],h+.2)
    else:coord=clean_uv(x+offset[0],h+.2)
   uv.data[li].uv=coord
 o['editable_piece']=True;o['source_uv_method']='P2 clean island metre mirrored, no rebake'
 return o

def build_variant(label,offset,material):
 H.PIECES=[]
 for n,x0,x1,z0,z1,chip in [('SW',-3,-.61,-3,-.66,2),('NW',-3,-.61,-.64,3,1),('SE',-.59,3,-3,.79,3),('NE',-.59,3,.81,3,0)]:
  H.slab('Plain_'+label+'_Pour_'+n,x0,x1,z0,z1,material,chip)
 for n,lo,hi in [('Long',[-.61,-.035,-3],[-.59,-.012,3]),('LeftT',[-3,-.035,-.66],[-.61,-.012,-.64]),('RightT',[-.59,-.035,.79],[3,-.012,.81])]:
  H.box('Plain_'+label+'_Seal_'+n,lo,hi,material,'PlainPaving')
 coll=bpy.data.collections.new('Editable_Plain_'+label);bpy.context.scene.collection.children.link(coll)
 root=bpy.data.objects.new('PlainPaving_'+label,None);coll.objects.link(root)
 parts=[]
 for o in H.PIECES:
  apply_metric_uv(o,offset,'_Seal_' in o.name)
  for old in list(o.users_collection):old.objects.unlink(o)
  coll.objects.link(o);o.parent=root;o.matrix_basis=Matrix.Identity(4);o['runtime_group']='PlainPaving_'+label
  parts.append(o)
 return coll,root,parts

def inspect(parts,label):
 checks=[];verts=[];tris=[];records=[]
 def check(n,p,d=None):checks.append({'name':label+': '+n,'passed':bool(p),'detail':d})
 for o in parts:
  me=o.data;me.calc_loop_triangles();bm=bmesh.new();bm.from_mesh(me);bad=sum(not e.is_manifold for e in bm.edges);bm.free()
  coords=[gd(v.co) for v in me.vertices];start=len(verts);verts.extend([v.co.copy() for v in me.vertices]);tris.extend([tuple(start+i for i in t.vertices) for t in me.loop_triangles])
  records.append({'name':o.name,'triangles':len(me.loop_triangles),'nonmanifold_edges':bad,'vertices':len(me.vertices)})
  check(o.name+' explicit UV0 finite within atlas',len(me.uv_layers)==1 and me.uv_layers.active.name=='SurfaceUV' and me.uv_layers['SurfaceUV'].active_render and all(math.isfinite(c) and 0<=c<=1 for u in me.uv_layers['SurfaceUV'].data for c in u.uv))
 points=[gd(p) for p in verts];bb=[[min(v[a] for v in points) for a in range(3)],[max(v[a] for v in points) for a in range(3)]]
 check('actual 6x6x.18 bounds',all(abs(bb[k][i]-[[-3,-.18,-3],[3,0,3]][k][i])<2e-6 for k in range(2) for i in range(3)),bb)
 check('seven editable parts / four complete pours / three seals',len(parts)==7 and sum('_Pour_' in o.name for o in parts)==4 and sum('_Seal_' in o.name for o in parts)==3)
 check('every piece closed manifold',all(r['nonmanifold_edges']==0 for r in records))
 check('one existing P2 material',{m.name for o in parts for m in o.data.materials}=={'CGround_BakedPBR'})
 bvh=BVHTree.FromPolygons(verts,tris,all_triangles=True);probes=[]
 for x,z in [(-2,-2),(-2,2),(1,-2),(1,2),(2.84,0),(2.55,2),(2.55,-2)]:
  hit=bvh.ray_cast(Vector(bg((x,1,z))),Vector((0,0,-1)),2)[0]
  probes.append({'xz':[x,z],'actual_y':float(hit.z) if hit else None})
 check('solid top Y0 including former drain strip',all(p['actual_y'] is not None and abs(p['actual_y'])<1e-6 for p in probes),probes)
 return {'label':label,'parts':records,'triangles':len(tris),'bounds':bb,'checks':checks,'runtime_plan':'one mesh/surface per variant, shared existing P2 material; export not performed'}

def verify_images():
 source=json.loads((P2/'evidence/production_report.json').read_text(encoding='utf-8'));rows=[]
 for node in bpy.data.materials['CGround_BakedPBR'].node_tree.nodes:
  if node.type!='TEX_IMAGE':continue
  im=node.image;path=Path(bpy.path.abspath(im.filepath)).resolve();r=next(x for x in source['baked_maps'] if x['role']==node.label)
  assert path.exists() and sha(path)==r['sha256'] and im.colorspace_settings.name==r['colorspace']
  im.reload();px=list(im.pixels[:4]);assert len(px)==4 and im.has_data and tuple(im.size)==(2048,2048)
  rows.append({'role':node.label,'path':str(path),'sha256':sha(path),'colorspace':im.colorspace_settings.name})
 assert len(rows)==4;return rows

def main():
 start=time.time();blend=HERE/'clinic_ground_plain_v1.blend';assert not blend.exists() and sha(BASE)==BASE_SHA
 (HERE/'evidence').mkdir(exist_ok=True)
 print(json.dumps({'stage':'start','pid':os.getpid(),'threads':2,'no_bake_or_export':True}),flush=True)
 bpy.ops.wm.open_mainfile(filepath=str(BASE));scene=bpy.context.scene;scene.render.threads_mode='FIXED';scene.render.threads=2;scene.cycles.device='CPU'
 # Resolve filepaths in their original .blend context BEFORE changing save path.
 for im in bpy.data.images:
  if im.source=='FILE' and im.filepath:im.filepath=str(Path(bpy.path.abspath(im.filepath)).resolve())
 textures=verify_images();mat=bpy.data.materials['CGround_BakedPBR']
 for o in list(bpy.data.objects):
  if o.get('editable_piece',False):bpy.data.objects.remove(o,do_unlink=True)
 versions={};reports=[]
 for label,data in CONFIG['variants'].items():
  versions[label]=build_variant(label,data['metric_offset_xz'],mat);reports.append(inspect(versions[label][2],label))
 report={'status':'GEOMETRY_CHECKED_NOT_RENDERED','source_p2_sha256':BASE_SHA,'variants':reports,'existing_textures':textures,'no_bake':True,'no_glb':True,'sampling':CONFIG,'scope':'Source-only plain module candidate; Y0 conservative collision remains root integration responsibility.'}
 (HERE/'evidence/production_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 if not all(c['passed'] for r in reports for c in r['checks']):
  bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'FAILED_geometry.blend'),relative_remap=False)
  raise RuntimeError('Plain geometry/UV check failed; no render.')
 # Both variants keep local origin and independent editable parts. B is hidden
 # only for initial source preview; no runtime scene or export is produced.
 versions['B'][0].hide_render=True;versions['B'][0].hide_viewport=True
 scene.cycles.samples=24;scene.render.resolution_x=1280;scene.render.resolution_y=960
 scene.render.resolution_percentage=100;scene.camera.data.ortho_scale=9.8
 bpy.ops.wm.save_as_mainfile(filepath=str(blend),relative_remap=False)
 for im in bpy.data.images:
  if im.source=='FILE' and im.filepath:im.filepath=bpy.path.relpath(im.filepath)
 bpy.ops.wm.save_as_mainfile(filepath=str(blend),relative_remap=False)
 bpy.ops.wm.open_mainfile(filepath=str(blend));scene=bpy.context.scene;reopened=verify_images()
 assert sha(BASE)==BASE_SHA
 outputs=[]
 one=HERE/'evidence/plain_A_full.png';scene.render.filepath=str(one);bpy.ops.render.render(write_still=True);outputs.append({'path':str(one),'sha256':sha(one)})
 # Render two original candidates side by side for repeat/readability review.
 # These are temporary display copies and are never saved back to editable source.
 for label in versions:
  coll=bpy.data.collections['Editable_Plain_'+label];coll.hide_render=True
  for o in list(coll.objects):
   if o.type!='MESH':continue
   copy=bpy.data.objects.new('REVIEW_ONLY_'+o.name,o.data.copy());scene.collection.objects.link(copy);copy.location=(3 if label=='B' else -3,0,0)
 scene.camera.data.ortho_scale=16.8;scene.render.resolution_x=1536;scene.render.resolution_y=864
 pair=HERE/'evidence/plain_AB_adjacent.png';scene.render.filepath=str(pair);bpy.ops.render.render(write_still=True);outputs.append({'path':str(pair),'sha256':sha(pair)})
 report.update(status='SOURCE_RENDERED_PENDING_VISUAL_REVIEW',reopened_images=reopened,blend_sha256=sha(blend),previews=outputs,elapsed_seconds=time.time()-start)
 (HERE/'evidence/production_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 assert sha(BASE)==BASE_SHA and all(sha(Path(r['path']))==r['sha256'] for r in reopened)
 print(json.dumps({'stage':'end','pid':os.getpid(),'seconds':time.time()-start,'triangles_by_variant':{r['label']:r['triangles'] for r in reports},'no_bake_or_export':True}),flush=True)

if __name__=='__main__':main()
