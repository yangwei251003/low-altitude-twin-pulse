"""Prepared boundary-joint revision only. Root CPU2 window required.
Same four P2 textures. No bake/export. Frozen helpers are imported read-only.
"""
from pathlib import Path
import bpy,bmesh,importlib.util,sys,json,hashlib,time,math,os
from mathutils import Matrix,Vector
from mathutils.bvhtree import BVHTree
HERE=Path(__file__).resolve().parent;sys.dont_write_bytecode=True
spec=importlib.util.spec_from_file_location('frozen_plain_geometry_uv',HERE.parent/'plain_v1/build_plain.py')
V1=importlib.util.module_from_spec(spec);spec.loader.exec_module(V1)
H=V1.H;H.SRC=HERE
CONTRACT=json.loads((HERE/'contract.json').read_text(encoding='utf-8'))
P2=HERE.parent/'p2/clinic_ground_p2.blend'
P2_GLB=HERE.parent/'delivery_p2/clinic_ground_p2.glb'

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def bg(p):return (p[0],-p[2],p[1])
def gd(p):return (float(p[0]),float(p[2]),float(-p[1]))
def bounds(o):
 pts=[gd(v.co) for v in o.data.vertices]
 return [[min(p[a] for p in pts) for a in range(3)],[max(p[a] for p in pts) for a in range(3)]]

def pour(name,x0,x1,z0,z1,outer,material,chip):
 # Preserve only existing interior corner chips. Extra exterior irregular chips
 # are removed so the intended half-seal has a consistent manufactured edge.
 c=[.012,.018,.009,.014];c[chip%4]=.037
 corners=[(x0,z0),(x1,z0),(x1,z1),(x0,z1)]
 for i,(x,z) in enumerate(corners):
  if abs(x-outer[0])<1e-8 or abs(x-outer[1])<1e-8 or abs(z-outer[2])<1e-8 or abs(z-outer[3])<1e-8:c[i]=0
 raw=[(x0+c[0],z0),(x1-c[1],z0),(x1,z0+c[1]),(x1,z1-c[2]),(x1-c[2],z1),(x0+c[3],z1),(x0,z1-c[3]),(x0,z0+c[0])]
 p=[]
 for q in raw:
  if not p or q!=p[-1]:p.append(q)
 if p[0]==p[-1]:p.pop()
 n=len(p);vertices=[bg((x,y,z)) for y in [-.18,0] for x,z in p]
 faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
 mesh=bpy.data.meshes.new(name);mesh.from_pydata(vertices,[],faces);mesh.update()
 bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(mesh);bm.free()
 o=bpy.data.objects.new(name,mesh);bpy.context.scene.collection.objects.link(o)
 bevel=o.modifiers.new('Same_4mm_inward_manufacturing_bevel','BEVEL');bevel.width=.004;bevel.segments=1
 H.finish(o,material,'PlainPaving');return o

def make_variant(label,data,material):
 widths={side:(.02 if side in data['p2_contact_edges'] else .01) for side in ['west','east','south','north']}
 x0=-3+widths['west'];x1=3-widths['east'];z0=-3+widths['south'];z1=3-widths['north'];H.PIECES=[]
 for name,xa,xb,za,zb,chip in [('SW',x0,-.61,z0,-.66,2),('NW',x0,-.61,-.64,z1,1),('SE',-.59,x1,z0,.79,3),('NE',-.59,x1,.81,z1,0)]:
  pour('Plain_'+label+'_Pour_'+name,xa,xb,za,zb,(x0,x1,z0,z1),material,chip)
 for name,lo,hi in [('Long',[-.61,-.035,z0],[-.59,-.012,z1]),('LeftT',[x0,-.035,-.66],[-.61,-.012,-.64]),('RightT',[-.59,-.035,.79],[x1,-.012,.81])]:
  H.box('Plain_'+label+'_Seal_'+name,lo,hi,material,'PlainPaving')
 rects={'west':(-3,x0,-3,3),'east':(x1,3,-3,3),'south':(x0,x1,-3,z0),'north':(x0,x1,z1,3)}
 for side,(xa,xb,za,zb) in rects.items():
  H.box('Plain_'+label+'_EdgeBed_'+side,[xa,-.18,za],[xb,-.035,zb],material,'PlainPaving')
  H.box('Plain_'+label+'_EdgeSeal_'+side,[xa,-.035,za],[xb,-.012,zb],material,'PlainPaving')
 coll=bpy.data.collections.new('Editable_PlainV2_'+label);bpy.context.scene.collection.children.link(coll)
 root=bpy.data.objects.new('PlainPavingV2_'+label,None);coll.objects.link(root);parts=[]
 for o in H.PIECES:
  V1.apply_metric_uv(o,data['metric_offset_xz'],'Seal_' in o.name)
  for old in list(o.users_collection):old.objects.unlink(o)
  coll.objects.link(o);o.parent=root;o.matrix_basis=Matrix.Identity(4);o['runtime_group']='PlainPavingV2_'+label
  o['variant']=label;parts.append(o)
 return {'collection':coll,'root':root,'parts':parts,'widths':widths,'inner_rect':[x0,x1,z0,z1]}

def inspect(label,v):
 checks=[];records=[];allv=[];allt=[]
 def check(name,ok,detail=None):checks.append({'name':label+': '+name,'passed':bool(ok),'detail':detail})
 for o in v['parts']:
  me=o.data;me.calc_loop_triangles();bm=bmesh.new();bm.from_mesh(me);bad=sum(not e.is_manifold for e in bm.edges);bm.free()
  start=len(allv);allv.extend([x.co.copy() for x in me.vertices]);allt.extend([tuple(start+i for i in t.vertices) for t in me.loop_triangles])
  records.append({'name':o.name,'triangles':len(me.loop_triangles),'nonmanifold_edges':bad,'bounds':bounds(o)})
  check(o.name+' finite UV0',len(me.uv_layers)==1 and me.uv_layers.active.name=='SurfaceUV' and all(math.isfinite(x) and 0<=x<=1 for uv in me.uv_layers.active.data for x in uv.uv))
 points=[gd(p) for p in allv];bb=[[min(p[a] for p in points) for a in range(3)],[max(p[a] for p in points) for a in range(3)]]
 check('15 editable components, no drain/paint new geometry',len(v['parts'])==15)
 check('all individual components closed',all(x['nonmanifold_edges']==0 for x in records))
 check('exact six metre outer bound and .18 depth',all(abs(bb[k][a]-[[-3,-.18,-3],[3,0,3]][k][a])<2e-6 for k in range(2) for a in range(3)),bb)
 edge_records={}
 for side in v['widths']:
  seal=next(r for r in records if r['name'].endswith('_EdgeSeal_'+side));bed=next(r for r in records if r['name'].endswith('_EdgeBed_'+side))
  axis=0 if side in ['west','east'] else 2;actual_width=seal['bounds'][1][axis]-seal['bounds'][0][axis]
  check(side+' half/full seal actual width',abs(actual_width-v['widths'][side])<3e-7,actual_width)
  check(side+' seal sits on concrete bed / recessed same as internal',abs(seal['bounds'][0][1]-bed['bounds'][1][1])<1e-7 and abs(seal['bounds'][1][1]+.012)<1e-7)
  edge_records[side]={'width':actual_width,'bounds':seal['bounds'],'bed_bounds':bed['bounds']}
 bvh=BVHTree.FromPolygons(allv,allt,all_triangles=True);probes=[]
 for x,z,expected in [(-2,0,0),(2,0,0),(0,2,0),(0,-2,0),(-3+v['widths']['west']/2,0,-.012),(3-v['widths']['east']/2,0,-.012),(0,-3+v['widths']['south']/2,-.012),(0,3-v['widths']['north']/2,-.012)]:
  hit=bvh.ray_cast(Vector(bg((x,1,z))),Vector((0,0,-1)),2)[0];value=float(hit.z) if hit else None
  probes.append({'xz':[x,z],'expected_y':expected,'actual_y':value})
 check('actual plate/seal ray heights',all(p['actual_y'] is not None and abs(p['actual_y']-p['expected_y'])<2e-6 for p in probes),probes)
 check('shared original P2 material',{m.name for o in v['parts'] for m in o.data.materials}=={'CGround_BakedPBR'})
 return {'label':label,'triangles':len(allt),'parts':records,'bounds':bb,'edges':edge_records,'checks':checks,'material':'CGround_BakedPBR'}

def display_copies(label,dx):
 coll=bpy.data.collections['Editable_PlainV2_'+label]
 for o in coll.objects:
  if o.type!='MESH':continue
  c=bpy.data.objects.new('REVIEW_ONLY_'+o.name,o.data.copy());bpy.context.scene.collection.objects.link(c);c.location=(dx,0,0);c['review_only']=True

def main():
 start=time.time();blend=HERE/'clinic_ground_plain_v2.blend';assert not blend.exists()
 assert sha(P2)==CONTRACT['p2_source_blend_sha256'] and sha(P2_GLB)==CONTRACT['p2_delivery_glb_sha256']
 (HERE/'evidence').mkdir(exist_ok=True)
 print(json.dumps({'stage':'start','pid':os.getpid(),'threads':2,'no_bake_export_runtime':True}),flush=True)
 bpy.ops.wm.open_mainfile(filepath=str(P2));scene=bpy.context.scene;scene.render.threads_mode='FIXED';scene.render.threads=2;scene.cycles.device='CPU'
 for im in bpy.data.images:
  if im.source=='FILE' and im.filepath:im.filepath=str(Path(bpy.path.abspath(im.filepath)).resolve())
 textures=V1.verify_images();mat=bpy.data.materials['CGround_BakedPBR']
 for o in list(bpy.data.objects):
  if o.get('editable_piece',False):bpy.data.objects.remove(o,do_unlink=True)
 variants={};reports=[]
 for label,data in CONTRACT['variants'].items():variants[label]=make_variant(label,data,mat);reports.append(inspect(label,variants[label]))
 indexed={r['label']:r for r in reports};joins=[]
 for name,left,right,expected in [('ordinary_A_to_B',indexed['A']['edges']['east'],indexed['B']['edges']['west'],.02),('P2_to_plain',None,indexed['P2_W']['edges']['west'],.02)]:
  # These values use actual constructed seal bounds. The P2 edge is the frozen
  # zero-half-seal reference, not a claim that its original geometry was modified.
  actual=right['width']+(left['width'] if left else 0)
  joins.append({'name':name,'expected_seal_width_m':expected,'actual_seal_width_m':actual,'passed':abs(actual-expected)<5e-7,'bevel_note':'Both sides use original4mm bevel; visible slope+seal is about28mm, same as internal20mm joint plus two bevels.'})
 report={'status':'GEOMETRY_CHECKED_NOT_RENDERED','variants':reports,'joins':joins,'textures':textures,'frozen_p2_source_sha256':sha(P2),'frozen_p2_glb_sha256':sha(P2_GLB),'scope':'Source-only geometry candidate; Y0 conservative runtime collider unchanged. No claim of full self-intersection or real flight validation.'}
 (HERE/'evidence/production_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 if not all(c['passed'] for r in reports for c in r['checks']) or not all(j['passed'] for j in joins):
  bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'FAILED_geometry.blend'),relative_remap=False);raise RuntimeError('Boundary joint gate failed; retain source, no render.')
 for label,v in variants.items():
  if label!='A':v['collection'].hide_render=True;v['collection'].hide_viewport=True
 scene.cycles.samples=24;scene.render.resolution_x=1536;scene.render.resolution_y=864;scene.render.resolution_percentage=100;scene.camera.data.ortho_scale=16.8
 bpy.ops.wm.save_as_mainfile(filepath=str(blend),relative_remap=False)
 for im in bpy.data.images:
  if im.source=='FILE' and im.filepath:im.filepath=bpy.path.relpath(im.filepath)
 bpy.ops.wm.save_as_mainfile(filepath=str(blend),relative_remap=False)
 bpy.ops.wm.open_mainfile(filepath=str(blend));scene=bpy.context.scene;reopened=V1.verify_images()
 for label in CONTRACT['variants']:bpy.data.collections['Editable_PlainV2_'+label].hide_render=True
 display_copies('A',-3);display_copies('B',3)
 outputs=[];out=HERE/'evidence/plain_AB_2cm_joint.png';scene.render.filepath=str(out);bpy.ops.render.render(write_still=True);outputs.append({'path':str(out),'sha256':sha(out)})
 for o in list(bpy.data.objects):
  if o.get('review_only',False):bpy.data.objects.remove(o,do_unlink=True)
 before=set(bpy.data.objects);bpy.ops.import_scene.gltf(filepath=str(P2_GLB));imported=set(bpy.data.objects)-before
 imported_root=next(o for o in imported if o.name.startswith('ClinicGroundModule') and o.parent not in imported)
 imported_root.location.x=-3
 display_copies('P2_W',3)
 out=HERE/'evidence/plain_to_frozen_P2_2cm_joint.png';scene.render.filepath=str(out);bpy.ops.render.render(write_still=True);outputs.append({'path':str(out),'sha256':sha(out)})
 assert sha(P2)==CONTRACT['p2_source_blend_sha256'] and sha(P2_GLB)==CONTRACT['p2_delivery_glb_sha256']
 report.update(status='SOURCE_RENDERED_PENDING_VISUAL_REVIEW',blend_sha256=sha(blend),previews=outputs,reopened_images=reopened,elapsed_seconds=time.time()-start)
 (HERE/'evidence/production_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 print(json.dumps({'stage':'end','pid':os.getpid(),'seconds':time.time()-start,'triangles':{r['label']:r['triangles'] for r in reports}}),flush=True)

if __name__=='__main__':main()
