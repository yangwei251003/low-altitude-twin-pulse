"""Source-only revision. DO NOT RUN until root releases CPU2 window.
No layout, Godot, reference, previous source or GLB writes.
"""
from pathlib import Path
import sys,json,hashlib,math,time,os,argparse
import bpy,bmesh
from mathutils import Vector
SRC=Path(__file__).resolve().parent
sys.path.insert(0,str(SRC))
from atlas_v3 import create_textures,mapped_uv
BASE=SRC.parent/'production_candidate/clinic_gravity_production_candidate_v2.blend'
BASE_SHA='1ccb4d5ab3a60c171ae5dd5e2fd5118cd247756f674524b4e5d445978d14caa4'
ORIGIN=Vector((-9,6,-7))
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def bp(p):
 v=Vector(p)-ORIGIN;return Vector((v.x,-v.z,v.y))
def gp(v):return Vector((v.x,v.z,-v.y))+ORIGIN
def bounds(o):
 q=[gp(o.matrix_world@v.co) for v in o.data.vertices]
 return [[min(p[i] for p in q) for i in range(3)],[max(p[i] for p in q) for i in range(3)]]
def ensure(m):
 m.use_nodes=True;n=m.node_tree.nodes;n.clear();b=n.new('ShaderNodeBsdfPrincipled');out=n.new('ShaderNodeOutputMaterial');m.node_tree.links.new(b.outputs['BSDF'],out.inputs['Surface']);return b
def simple(name,color,rough,metal=0,alpha=1):
 m=bpy.data.materials.new(name);b=ensure(m);b.inputs['Base Color'].default_value=(*color,1);b.inputs['Roughness'].default_value=rough;b.inputs['Metallic'].default_value=metal;b.inputs['Alpha'].default_value=alpha;return m,b
def geometry_digest(objects):
 rows=[(o.name,[list(row) for row in o.matrix_world],[list(v.co) for v in o.data.vertices],[list(p.vertices) for p in o.data.polygons]) for o in sorted(objects,key=lambda q:q.name) if o.type=='MESH']
 return hashlib.sha256(json.dumps(rows,separators=(',',':')).encode()).hexdigest()
def assign(o,kind,pbr):
 o.data.materials.clear();o.data.materials.append(pbr)
 while o.data.uv_layers:o.data.uv_layers.remove(o.data.uv_layers[0])
 o.data.uv_layers.new(name='SurfaceUV');uv=o.data.uv_layers['SurfaceUV'];uv.active_render=True
 pts=[gp(o.matrix_world@v.co) for v in o.data.vertices];lo,hi=bounds(o)
 for f in o.data.polygons:
  nn=o.matrix_world.to_3x3()@f.normal;normal=Vector((nn.x,nn.z,-nn.y));axis=max(range(3),key=lambda i:abs(normal[i]));axes=[0,2] if axis==1 else [0 if axis==2 else 2,1]
  for li in f.loop_indices:
   q=pts[o.data.loops[li].vertex_index]
   uv.data[li].uv=mapped_uv(kind,(q[axes[0]]-lo[axes[0]])/max(hi[axes[0]]-lo[axes[0]],.0001),(q[axes[1]]-lo[axes[1]])/max(hi[axes[1]]-lo[axes[1]],.0001))
def overlaps(a,b):return all(max(a[0][i],b[0][i])<min(a[1][i],b[1][i])-1e-6 for i in range(3))

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--render',action='store_true');args=ap.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
 started=time.time();blend=SRC/'clinic_gravity_revision_v3.blend';evid=SRC/'evidence';evid.mkdir(exist_ok=True)
 assert not blend.exists(),'Previous output exists: preserve before another explicit revision.'
 assert sha(BASE)==BASE_SHA,'Frozen input changed.'
 print(json.dumps({'stage':'start','pid':os.getpid(),'threads':2,'source_only':True}),flush=True)
 bpy.ops.wm.open_mainfile(filepath=str(BASE));scene=bpy.context.scene;source=bpy.data.collections['Editable_ClinicCistern_A'];root=bpy.data.objects['ClinicCisternDeck']
 old=[o for o in source.objects if o.type=='MESH'];old_names=[o.name for o in old];before=geometry_digest(old)
 paths=create_textures(SRC/'textures')
 pbr=bpy.data.materials['CG_AuthoredSurfacePBR'];pbr.name='CG_V3_ManufacturedSurfacePBR'
 for node in pbr.node_tree.nodes:
  if node.type=='TEX_IMAGE' and node.label in paths:
   image=bpy.data.images.load(str(paths[node.label].resolve()),check_existing=False);image.colorspace_settings.name='sRGB' if node.label=='BaseColor' else 'Non-Color';node.image=image
  if node.type=='NORMAL_MAP':node.inputs['Strength'].default_value=.60
 # Existing source geometry is retained; only superseded tiny fasteners are hidden.
 superseded=[]
 for o in old:
  if o.name.startswith(('TankCornerBolt','LevelTick_')):
   o.hide_render=True;o.hide_set(True);o['superseded_by_revision_v3']=True;superseded.append(o.name)
 # Clear pane: almost neutral, no transmission/refraction stack that greys the water.
 window=bpy.data.objects['CisternFrontWindow'];glass,bs=simple('CG_V3_ClearObservationPane',(.88,.98,1),.08,0,.035)
 bs.inputs['Specular IOR Level'].default_value=.18;bs.inputs['Transmission Weight'].default_value=0
 window.data.materials.clear();window.data.materials.append(glass)
 preview=bpy.data.objects['PreviewWater_3200L_NOT_EXPORT'];preview['exclude_export']=True;preview.parent=None
 # Opaque stylized body + opaque liquid surface: only the window is transparent.
 # Avoid promising Cycles transmission / stacked alpha can work in Compatibility.
 body,wb=simple('CG_V3_PreviewWaterBody',(.018,.43,.50),.18,0,1)
 top,wt=simple('CG_V3_PreviewWaterSurface',(.06,.58,.64),.14,0,1)
 # A small three-dimensional normal variation, not an image of a fixed waterline.
 noise=top.node_tree.nodes.new('ShaderNodeTexNoise');noise.inputs['Scale'].default_value=4;noise.inputs['Detail'].default_value=1.2
 bump=top.node_tree.nodes.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.14;bump.inputs['Distance'].default_value=.012
 top.node_tree.links.new(noise.outputs['Fac'],bump.inputs['Height']);top.node_tree.links.new(bump.outputs['Normal'],wt.inputs['Normal'])
 preview.data.materials.clear();preview.data.materials.append(body);preview.data.materials.append(top)
 for f in preview.data.polygons:f.material_index=1 if (preview.matrix_world.to_3x3()@f.normal).z>.5 else 0
 new=[]
 def register(o,kind,group):
  for c in list(o.users_collection):c.objects.unlink(o)
  source.objects.link(o);o.parent=root;o['runtime_group']=group;o['revision_v3_new']=True
  o['collision_class']='ADDITIONAL_GEOMETRY_CANDIDATE_ROOT_REVIEW_REQUIRED';assign(o,kind,pbr);new.append(o);return o
 def box(name,lo,hi,kind='paint_beam',group='ManufacturedHardware',bevel=.006):
  assert all(hi[i]>lo[i] for i in range(3)),name
  bpy.ops.mesh.primitive_cube_add(size=1,location=bp([(lo[i]+hi[i])/2 for i in range(3)]));o=bpy.context.object;o.name=name
  o.dimensions=(hi[0]-lo[0],hi[2]-lo[2],hi[1]-lo[1]);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);register(o,kind,group)
  if bevel:
   m=o.modifiers.new('Manufactured_shallow_edge','BEVEL');m.width=min(bevel,min(hi[i]-lo[i] for i in range(3))*.24);m.segments=2
   n=o.modifiers.new('WeightedNormals','WEIGHTED_NORMAL');n.keep_sharp=True
  return o
 def cyl(name,a,b,r,kind='steel',sides=6):
  a,b=bp(a),bp(b);d=b-a;bpy.ops.mesh.primitive_cylinder_add(vertices=sides,radius=r,depth=d.length,location=(a+b)/2);o=bpy.context.object;o.name=name;o.rotation_euler=d.to_track_quat('Z','Y').to_euler();bpy.ops.object.transform_apply(location=False,rotation=True,scale=True);register(o,kind,'VisibleFasteners');return o
 def bolt_z(name,x,y,z):
  cyl(name+'_Washer',[x,y,z-.002],[x,y,z+.006],.062,sides=12)
  cyl(name+'_Hex',[x,y,z+.006],[x,y,z+.027],.046,sides=6)
 def bolt_y(name,x,y,z):
  cyl(name+'_Washer',[x,y-.002,z],[x,y+.005,z],.051,sides=12)
  cyl(name+'_Hex',[x,y+.005,z],[x,y+.022,z],.037,sides=6)
 # Real shallow window seal and separately bolted retaining strips, all clear of pane centre.
 for name,lo,hi in [
  ('SealL',[-9.72,6.14,-6.375],[-9.68,8.86,-6.36]),('SealR',[-8.32,6.14,-6.375],[-8.28,8.86,-6.36]),
  ('SealBottom',[-9.68,6.14,-6.375],[-8.32,6.18,-6.36]),('SealTop',[-9.68,8.82,-6.375],[-8.32,8.86,-6.36])]:box(name,lo,hi,'rubber','WindowAssembly',.003)
 for side,x0,x1 in [('L',-9.91,-9.74),('R',-8.26,-8.09)]:
  box('WindowSteelPost_'+side,[x0,6.03,-6.38],[x1,8.98,-6.341],'paint_post','WindowAssembly',.009)
  for i,y in enumerate([6.28,6.95,7.62,8.29,8.78]):bolt_z('WindowFastener_'+side+str(i),(x0+x1)/2,y,-6.34)
 for name,y0,y1 in [('Sill',6.02,6.14),('Head',8.88,9.02)]:
  box('Window_'+name,[-9.74,y0,-6.38],[-8.26,y1,-6.34],'paint_beam','WindowAssembly',.009)
 # Yellow folded corner protectors: front flange plus side return, not painted squares.
 for side,x in [('L',-9.92),('R',-8.08)]:
  a,b=(x,x+.22) if side=='L' else (x-.22,x)
  sidea,sideb=(x-.035,x+.008) if side=='L' else (x-.008,x+.035)
  for level,y0,y1 in [('Lower',6.0,6.23),('Upper',8.78,9.04)]:
   box('YellowCorner_'+side+level,[a,y0,-6.341],[b,y1,-6.315],'yellow','TankCornerProtection',.008)
   box('YellowReturn_'+side+level,[sidea,y0,-6.58],[sideb,y1,-6.341],'yellow','TankCornerProtection',.008)
 # Exterior side panel construction: perimeter angle, one mid-height seam; not padded grid tiles.
 for side,x0,x1 in [('Left',-9.947,-9.916),('Right',-8.084,-8.053)]:
  for z0,z1 in [(-7.62,-7.53),(-6.48,-6.38)]:box('SideCorner_'+side,[x0,6.0,z0],[x1,9.02,z1],'paint_post','TankSideFrame',.007)
  box('SideServiceSeam_'+side,[x0,7.44,-7.53],[x1,7.50,-6.48],'steel','TankSideFrame',.004)
 # Larger readable graduation belongs to a fixed frame, not to the dynamic water.
 for i in range(1,12):
  y=6+i*.25;length=.085 if i%4==0 else .045
  box('V3Level_%02d'%i,[-8.246,y-.011,-6.312],[-8.246+length,y+.011,-6.308],'liner','WindowAssembly',0)
 # Deck edge angle sections are inset on top; vertical skirts extend only 18 mm outward.
 outline=[(-12,-10),(-5,-10),(-5,-5.7),(-6,-5.7),(-6,-4.4),(-9.3,-4.4),(-9.3,-5.7),(-12,-5.7)]
 for idx,a in enumerate(outline):
  b=outline[(idx+1)%len(outline)];dx,dz=b[0]-a[0],b[1]-a[1];length=math.hypot(dx,dz);d=Vector((dx/length,dz/length));inside=Vector((-d.y,d.x));a=Vector(a)
  def strip(name,s,e,in0,in1,y0,y1,kind):
   q=[a+d*t+inside*n for t in (s,e) for n in (in0,in1)];return box(name,[min(v.x for v in q),y0,min(v.y for v in q)],[max(v.x for v in q),y1,max(v.y for v in q)],kind,'DeckEdgeAssembly',.004)
  strip('DeckSkirt_%02d'%idx,.10,length-.10,-.018,.006,5.77,5.98,'paint_beam')
  strip('DeckCap_%02d'%idx,.13,length-.13,.008,.12,6,6.025,'steel')
  for end,s,e in [('A',.018,min(.29,length*.34)),('B',max(length-.29,length*.66),length-.018)]:
   strip('DeckYellow_'+str(idx)+end,s,e,.008,.14,6.026,6.048,'yellow')
   q=a+d*((s+e)/2)+inside*.07;bolt_y('DeckCornerBolt_'+str(idx)+end,q.x,6.048,q.y)
 # Actual metal joint covers: centimetre-scale shadow edges and selected fasteners.
 seams=[('X1',[-10.075,6.001,-9.8],[-10.025,6.019,-5.82]),('X2',[-7.625,6.001,-9.8],[-7.575,6.019,-4.55]),
 ('Z1a',[-11.8,6.001,-8.625],[-10.0,6.019,-8.575]),('Z1b',[-8.0,6.001,-8.625],[-5.2,6.019,-8.575]),('Z2',[-11.8,6.001,-6.075],[-5.2,6.019,-6.025])]
 for name,lo,hi in seams:box('DeckJoint_'+name,lo,hi,'steel','DeckJointAssembly',.003)
 for i,(x,z) in enumerate([(-10.05,-8.6),(-10.05,-6.05),(-7.6,-8.6),(-7.6,-6.05)]):
  box('JointClip_'+str(i),[x-.075,6.02,z-.075],[x+.075,6.036,z+.075],'paint_beam','DeckJointAssembly',.006);bolt_y('JointBolt_'+str(i),x,6.036,z)
 # Post head and foot connection plates. Short parts, no braces across flight routes.
 plan=json.loads((SRC.parent/'structure_v2/structure_plan.json').read_text(encoding='utf-8'))
 for part in plan['parts']:
  if not part['id'].startswith('SupportLeg_'):continue
  lo,hi=part['min'],part['max'];x=(lo[0]+hi[0])/2;z=hi[2]
  for nm,y0,y1 in [('Foot',.15,.40),('Head',4.83,5.13)]:
   box(part['id']+'_Connection_'+nm,[lo[0]-.015,y0,z-.002],[hi[0]+.015,y1,z+.024],'paint_beam','PostConnections',.009)
   for dx in (-.18,.18):bolt_z(part['id']+nm+str(dx),x+dx,(y0+y1)/2,z+.024)
 bpy.context.view_layer.update()
 proposals=[{'name':o.name,'world_aabb':bounds(o),'group':o['runtime_group'],'requires_root_collision_decision':True} for o in new]
 reserved=[[-8.6,6.55,-5.5],[-6.2,7.3,-3.15]]
 checks=[]
 def check(n,ok,d=None):checks.append({'name':n,'passed':bool(ok),'detail':d})
 check('frozen input SHA unchanged',sha(BASE)==BASE_SHA)
 check('all old mesh coordinates and transforms retained',geometry_digest([bpy.data.objects[n] for n in old_names])==before)
 check('SourceWaterBase local anchor unchanged',bpy.data.objects['SourceWaterBase'].location.length<1e-8)
 check('all new candidate bounds outside valve moving reserve',not any(overlaps(row['world_aabb'],reserved) for row in proposals),[row['name'] for row in proposals if overlaps(row['world_aabb'],reserved)])
 topology=[]
 for o in new:
  bm=bmesh.new();bm.from_mesh(o.data);topology.append({'name':o.name,'nonmanifold_edges':sum(not e.is_manifold for e in bm.edges)});bm.free()
 check('new pieces individually closed',all(t['nonmanifold_edges']==0 for t in topology),topology)
 check('one explicit SurfaceUV on new geometry',all(len(o.data.uv_layers)==1 and o.data.uv_layers.active.name=='SurfaceUV' and o.data.uv_layers.active.active_render for o in new))
 check('water remains separate, excluded and not a baked waterline',preview.parent is None and preview.get('exclude_export') and len(preview.data.materials)==2)
 dg=bpy.context.evaluated_depsgraph_get();tri=0
 for o in source.objects:
  if o.type=='MESH' and not o.hide_render:
   mesh=o.evaluated_get(dg).to_mesh();mesh.calc_loop_triangles();tri+=len(mesh.loop_triangles);o.evaluated_get(dg).to_mesh_clear()
 scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=32;scene.cycles.use_denoising=True;scene.render.threads_mode='FIXED';scene.render.threads=2
 scene.render.resolution_x=1280;scene.render.resolution_y=1280;scene.render.resolution_percentage=100
 scene.view_settings.view_transform='AgX';scene.view_settings.exposure=0
 report={'status':'NUMERIC_CHECKS_PENDING_IMAGE','pid':os.getpid(),'input_sha256':BASE_SHA,'old_geometry_hash':before,'checks':checks,'new_piece_count':len(new),'evaluated_visible_triangles':tri,'superseded_small_parts':superseded,'additional_collision_candidates':proposals,'scope':'Source only. Not runtime collision validation, not game art approval. Independent water is a 3200 L preview.'}
 bpy.ops.wm.save_as_mainfile(filepath=str(blend),relative_remap=False)
 for node in pbr.node_tree.nodes:
  if node.type=='TEX_IMAGE' and node.label in paths:node.image.filepath='//textures/'+paths[node.label].name
 bpy.ops.wm.save_as_mainfile(filepath=str(blend),relative_remap=False)
 (evid/'revision_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 if not all(c['passed'] for c in checks):raise RuntimeError('Exact source check failed: saved failure, no render.')
 # Reopen saved source before render and resolve Blender paths in that actual context.
 bpy.ops.wm.open_mainfile(filepath=str(blend));scene=bpy.context.scene;loaded=[]
 for node in bpy.data.materials['CG_V3_ManufacturedSurfacePBR'].node_tree.nodes:
  if node.type=='TEX_IMAGE' and node.label in paths:
   im=node.image;resolved=Path(bpy.path.abspath(im.filepath)).resolve();assert resolved==paths[node.label].resolve() and resolved.exists();assert sha(resolved)==sha(paths[node.label]);im.reload();assert tuple(im.size)==(2048,2048) and im.has_data
   loaded.append({'role':node.label,'resolved_path':str(resolved),'sha256':sha(resolved),'colorspace':im.colorspace_settings.name})
 assert len(loaded)==4
 report['reopened_texture_checks']=loaded
 if args.render:
  image=evid/'clinic_gravity_revision_v3.png';scene.render.filepath=str(image);scene.render.image_settings.file_format='PNG';bpy.ops.render.render(write_still=True);report['image_sha256']=sha(image)
 report.update(status='SOURCE_RENDERED_REQUIRES_ACTUAL_VISUAL_REVIEW',blend_sha256=sha(blend),elapsed_seconds=time.time()-started)
 (evid/'revision_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 assert sha(BASE)==BASE_SHA
 print(json.dumps({'stage':'end','pid':os.getpid(),'seconds':time.time()-started,'checks':len(checks),'source_only':True}),flush=True)
if __name__=='__main__':main()
