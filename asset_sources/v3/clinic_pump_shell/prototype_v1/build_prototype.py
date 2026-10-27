"""Prepared source-only prototype. Requires root-approved atlas + CPU2 window.
Godot contract coordinates -> Blender (localX,-localZ,localY).
Never imports/exports runtime GLB or modifies shared files.
"""
from pathlib import Path
import bpy,bmesh,sys,json,hashlib,math,time,os,shutil
from mathutils import Vector,Matrix
from mathutils.bvhtree import BVHTree
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
PLAN=HERE.parent/'planning/contract.json'
REF=ROOT/'references/v3/production/clinic_pump_shell/pump_shell_reference_v2.png'
REF_SHA='fd12b090b14ff16b56e606ab7be4e0e09c8a997608656ede62807896581b9236'
ATLAS=ROOT/'references/v3/production/clinic_pump_shell/material_atlas_v1.png'
ORIGIN=Vector((-7,0,8));PARTS=[];GROUPS={};MATERIALS={}
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def bp(p):return Vector((p[0],-p[2],p[1]))
def gp(p):return Vector((p[0],p[2],-p[1]))
def local(p):return Vector(p)-ORIGIN
def bounds(points):return [[min(p[a] for p in points) for a in range(3)],[max(p[a] for p in points) for a in range(3)]]

def material(name,image,region,scale,roughness,metallic,weather=False,tint=None,calm=None):
 m=bpy.data.materials.new(name);m.use_nodes=True;n=m.node_tree.nodes;n.clear();lk=m.node_tree.links
 def inp(value,socket):
  if hasattr(value,'node'):lk.new(value,socket)
  else:socket.default_value=value
 def op(kind,a,b=0):
  q=n.new('ShaderNodeMath');q.operation=kind;inp(a,q.inputs[0]);inp(b,q.inputs[1]);return q.outputs[0]
 def add(a,b):return op('ADD',a,b)
 def sub(a,b):return op('SUBTRACT',a,b)
 def mul(a,b):return op('MULTIPLY',a,b)
 metric=n.new('ShaderNodeUVMap');metric.uv_map='MetricUV';se=n.new('ShaderNodeSeparateXYZ');lk.new(metric.outputs['UV'],se.inputs[0])
 a,b,c,d=region;pad=.006
 phase=n.new('ShaderNodeVertexColor');phase.layer_name='UVPhase';ph=n.new('ShaderNodeSeparateColor');lk.new(phase.outputs['Color'],ph.inputs[0])
 cu=add(a+pad,mul(op('FRACT',add(op('DIVIDE',se.outputs['X'],scale),ph.outputs['Red'])),c-a-2*pad))
 cv=add(b+pad,mul(op('FRACT',add(op('DIVIDE',se.outputs['Y'],scale),ph.outputs['Green'])),d-b-2*pad))
 comb=n.new('ShaderNodeCombineXYZ');lk.new(cu,comb.inputs['X']);lk.new(cv,comb.inputs['Y'])
 tx=n.new('ShaderNodeTexImage');tx.image=image;tx.extension='EXTEND';tx.label='Unedited root imagegen material atlas; no concept projection';lk.new(comb.outputs[0],tx.inputs['Vector'])
 base=tx.outputs['Color'];mask=0
 if calm:
  mix=n.new('ShaderNodeMixRGB');mix.inputs[0].default_value=calm[0];mix.inputs[1].default_value=(*calm[1],1);lk.new(base,mix.inputs[2]);base=mix.outputs[0]
 face=n.new('ShaderNodeUVMap');face.uv_map='PanelUV';fs=n.new('ShaderNodeSeparateXYZ');lk.new(face.outputs['UV'],fs.inputs[0]);u,v=fs.outputs['X'],fs.outputs['Y']
 if tint:
  mix=n.new('ShaderNodeMixRGB');mix.blend_type='MULTIPLY';mix.inputs[0].default_value=1;lk.new(base,mix.inputs[1]);mix.inputs[2].default_value=(*tint,1);base=mix.outputs[0]
 if weather:
  control=n.new('ShaderNodeVertexColor');control.layer_name='WearControl';cs=n.new('ShaderNodeSeparateColor');lk.new(control.outputs['Color'],cs.inputs[0])
  # Actual panel bolts are at normalized u=.045/.955, v=.92; masks run down.
  dist=sub(.92,v);active=mul(op('GREATER_THAN',dist,0),op('LESS_THAN',dist,cs.outputs['Blue']))
  left=op('MAXIMUM',0,sub(1,op('DIVIDE',op('ABSOLUTE',sub(u,add(.045,mul(dist,.008)))),.012)))
  right=op('MAXIMUM',0,sub(1,op('DIVIDE',op('ABSOLUTE',sub(u,sub(.955,mul(dist,.006)))),.009)))
  taper=op('MAXIMUM',0,sub(1,op('DIVIDE',dist,cs.outputs['Blue'])))
  mask=mul(mul(active,taper),mul(add(mul(left,cs.outputs['Red']),mul(right,cs.outputs['Green'])),.34))
  mix=n.new('ShaderNodeMixRGB');lk.new(mask,mix.inputs[0]);lk.new(base,mix.inputs[1]);mix.inputs[2].default_value=(.085,.043,.019,1);base=mix.outputs[0]
 bs=n.new('ShaderNodeBsdfPrincipled');bs.name='PumpPrincipled';out=n.new('ShaderNodeOutputMaterial');lk.new(bs.outputs['BSDF'],out.inputs['Surface']);lk.new(base,bs.inputs['Base Color'])
 inp(add(roughness,mul(mask,.16)),bs.inputs['Roughness']);inp(mul(metallic,sub(1,mask)),bs.inputs['Metallic']);bs.inputs['Emission Strength'].default_value=0
 noise=n.new('ShaderNodeTexNoise');noise.inputs['Scale'].default_value=110 if 'Concrete' in name else 160;noise.inputs['Detail'].default_value=2;lk.new(metric.outputs['UV'],noise.inputs['Vector'])
 bump=n.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.12 if 'Concrete' in name else .045;bump.inputs['Distance'].default_value=.0015 if 'Concrete' in name else .00035;lk.new(noise.outputs['Fac'],bump.inputs['Height']);lk.new(bump.outputs['Normal'],bs.inputs['Normal'])
 m['author_only']='MetricUV + region sampling + physical microbump; future native bake required for standard glTF.'
 return m

def register(o,source_id,group,finish,seed=0):
 o.parent=GROUPS[group];o.matrix_basis=Matrix.Identity(4);o['source_solid']=source_id;o['runtime_group']=group;o['finish']=finish;o['editable_piece']=True
 me=o.data;me.materials.append(MATERIALS[finish]);bb=bounds([gp(v.co) for v in me.vertices])
 metric=me.uv_layers.new(name='MetricUV');panel=me.uv_layers.new(name='PanelUV');me.uv_layers.active_index=0;metric=me.uv_layers['MetricUV'];panel=me.uv_layers['PanelUV'];metric.active_render=True
 me.color_attributes.new(name='WearControl',type='FLOAT_COLOR',domain='CORNER');me.color_attributes.new(name='UVPhase',type='FLOAT_COLOR',domain='CORNER')
 wear=me.color_attributes['WearControl'];phase=me.color_attributes['UVPhase'];key=hashlib.sha256(o.name.encode('utf-8')).digest();phase_uv=(key[0]/255*.71,key[1]/255*.63,0,1)
 for p in me.polygons:
  gn=gp(p.normal);axis=max(range(3),key=lambda a:abs(gn[a]));axes=(0,2) if axis==1 else ((2,1) if axis==0 else (0,1))
  for li in p.loop_indices:
   q=gp(me.vertices[me.loops[li].vertex_index].co)
   metric.data[li].uv=(q[axes[0]],q[axes[1]])
   panel.data[li].uv=tuple((q[a]-bb[0][a])/max(1e-9,bb[1][a]-bb[0][a]) for a in axes)
   exterior=(source_id=='PumpWestWall' and gn.x<-.9) or (source_id=='PumpEastWall' and gn.x>.9) or (source_id=='PumpNorthWall' and gn.z<-.9) or ('South' in source_id and gn.z>.9)
   wear.data[li].color=(1.0 if exterior and seed%3==0 else 0.,1.0 if exterior and seed%4==1 else 0.,.26+.065*(seed%3),1);phase.data[li].color=phase_uv
 PARTS.append(o);return o

def box(name,lo,hi,source,group,finish,bevel=0.,seed=0):
 lo=local(lo);hi=local(hi)
 vs=[bp((lo.x if i&1==0 else hi.x,lo.y if i&2==0 else hi.y,lo.z if i&4==0 else hi.z)) for i in range(8)]
 faces=[(0,4,6,2),(1,3,7,5),(0,1,5,4),(2,6,7,3),(0,2,3,1),(4,5,7,6)]
 me=bpy.data.meshes.new(name);me.from_pydata(vs,[],faces);me.update()
 bm=bmesh.new();bm.from_mesh(me);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free()
 o=bpy.data.objects.new(name,me);bpy.context.scene.collection.objects.link(o);register(o,source,group,finish,seed)
 if bevel:
  b=o.modifiers.new('SmallManufacturingBevel','BEVEL');b.width=bevel;b.segments=1
 return o

def bolt(name,centre,normal,source,group,radius=.034):
 center=local(centre);n=Vector(normal);u=n.cross(Vector((0,1,0)))
 if u.length<.1:u=n.cross(Vector((1,0,0)))
 u.normalize();v=n.cross(u);depth=.010;count=10
 vs=[bp(center+n*(d*depth*.5)+radius*(math.cos(k*2*math.pi/count)*u+math.sin(k*2*math.pi/count)*v)) for d in [-1,1] for k in range(count)]
 faces=[tuple(reversed(range(count))),tuple(range(count,count*2))]+[(k,(k+1)%count,(k+1)%count+count,k+count) for k in range(count)]
 me=bpy.data.meshes.new(name);me.from_pydata(vs,[],faces);me.update();bm=bmesh.new();bm.from_mesh(me);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free()
 o=bpy.data.objects.new(name,me);bpy.context.scene.collection.objects.link(o);return register(o,source,group,'Zinc')

def build(plan):
 specs={p['id']:p for p in plan['fixed_shell_solids']}
 floor=specs['PumpFloor'];box('FloorBase',floor['world_min'],[-2,.37,12],'PumpFloor','FloorSurface','Concrete')
 # Actual 12mm sealed T-joints; no fake line image stretched over new geometry.
 for side,(xa,xb,cut) in enumerate([(-12,-7.006,7.4),(-6.994,-2,9.1)]):
  for j,(za,zb) in enumerate([(4,cut-.006),(cut+.006,12)]):box('FloorPour_%d_%d'%(side,j),[xa,.37,za],[xb,.4,zb],'PumpFloor','FloorSurface','Concrete',.002)
  box('FloorTSeal_%d'%side,[xa,.37,cut-.006],[xb,.394,cut+.006],'PumpFloor','FloorSurface','Seal')
 box('FloorLongSeal',[-7.006,.37,4],[-6.994,.394,12],'PumpFloor','FloorSurface','Seal')
 for source in ['PumpWestWall','PumpEastWall','PumpNorthWall','PumpSouthWestJamb','PumpSouthEastJamb']:
  s=specs[source];lo=s['world_min'];hi=s['world_max'];axis=0 if source in ['PumpWestWall','PumpEastWall'] else 2;long=2 if axis==0 else 0
  group={'PumpWestWall':'WestCover','PumpEastWall':'EastCover','PumpNorthWall':'NorthCover'}.get(source,'WallFeetAndJambs')
  lowhi=hi.copy();lowhi[1]=.75;box(source+'_Foot',lo,lowhi,source,'WallFeetAndJambs','Concrete',.003)
  sign=-1 if source in ['PumpWestWall','PumpNorthWall'] else 1
  # Two broad side tiers, single full front-jamb panel. All frames stay INSIDE
  # the original collision box and never narrow the doorway.
  count=3 if source in ['PumpWestWall','PumpEastWall','PumpNorthWall'] else 1
  edges=[lo[long]+(hi[long]-lo[long])*i/count for i in range(count+1)]
  intervals=[]
  for i in range(count):
   a=edges[i]+(.16 if i==0 else .065);b=edges[i+1]-(.16 if i==count-1 else .065);intervals.append((a,b))
  rails=[(lo[long],intervals[0][0])]+[(intervals[i-1][1],intervals[i][0]) for i in range(1,count)]+[(intervals[-1][1],hi[long])]
  for i,(a,b) in enumerate(rails):
   p=lo.copy();q=hi.copy();p[long]=a;q[long]=b;p[1]=.75;p[axis]+=.006;q[axis]-=.006
   box(source+'_Upright_'+str(i),p,q,source,group,'Teal',.003)
  rows=[(.79,3.04)] if count==1 else [(.79,1.91),(1.938,3.04)]
  for k,(a,b) in enumerate(intervals):
   for r,(y0,y1) in enumerate(rows):
    p=lo.copy();q=hi.copy();p[long]=a;q[long]=b;p[1]=y0;q[1]=y1;p[axis]+=.018;q[axis]-=.018
    seed=k+2*r+['PumpWestWall','PumpEastWall','PumpNorthWall','PumpSouthWestJamb','PumpSouthEastJamb'].index(source)
    box(source+'_Panel_%d_%d'%(k,r),p,q,source,group,'Wall',.004,seed)
    surface=(hi[axis]-.013 if sign>0 else lo[axis]+.013)
    for iu,u in enumerate([.045,.955]):
     for iv,v in enumerate([.08,.92]):
      c=[0.,y0+(y1-y0)*v,0.];c[long]=a+(b-a)*u;c[axis]=surface;normal=[0.,0.,0.];normal[axis]=sign
      bolt(source+'_Fastener_%d_%d_%d_%d'%(k,r,iu,iv),c,normal,source,group,.026)
   for j,(y0,y1) in enumerate([(.75,.79),(3.04,3.2)]+([] if count==1 else [(1.91,1.938)])):
    p=lo.copy();q=hi.copy();p[long]=a;q[long]=b;p[1]=y0;q[1]=y1;p[axis]+=.006;q[axis]-=.006
    box(source+'_Horizontal_%d_%d'%(k,j),p,q,source,group,'Teal',.002)
  if 'South' in source:
   # Yellow is restricted to a real entry-side frame; no solid intrudes into gap.
   xa=hi[0]-.13 if 'WestJamb' in source else lo[0]+.025
   box(source+'_EntryPaint',[xa,.42,hi[2]-.004],[xa+.105,1.15,hi[2]-.001],source,group,'Yellow',0)
 roof=specs['PumpRoof'];lo=roof['world_min'];hi=roof['world_max']
 box('RoofContinuousCore',lo,[hi[0],3.43,hi[2]],'PumpRoof','RoofCover','Teal',.003)
 roof_x=[lo[0],-8.7,-5.3,hi[0]]
 for i in range(3):
  a=roof_x[i]+.12;b=roof_x[i+1]-.12
  box('RoofZincPanel_'+str(i),[a,3.43,lo[2]+.18],[b,3.482,hi[2]-.18],'PumpRoof','RoofCover','Zinc',.004)
 for i,x in enumerate(roof_x):
  a=max(lo[0],x-.12);b=min(hi[0],x+.12)
  box('RoofBatten_'+str(i),[a,3.43,lo[2]],[b,3.49,hi[2]],'PumpRoof','RoofCover','Teal',.003)
  for z in [lo[2]+.13,hi[2]-.13]:bolt('RoofBattenBolt_%d_%.2f'%(i,z),[(a+b)/2,3.495,z],[0,1,0],'PumpRoof','RoofCover',.042)
 for z0,z1 in [(lo[2],lo[2]+.18),(hi[2]-.18,hi[2])]:
  for i in range(3):box('RoofEdge_%s_%d'%(z0,i),[roof_x[i]+.12,3.43,z0],[roof_x[i+1]-.12,3.49,z1],'PumpRoof','RoofCover','Teal',.003)

def inspect(plan):
 dg=bpy.context.evaluated_depsgraph_get();specs={s['id']:s for s in plan['fixed_shell_solids']};records=[];verts=[];tris=[];checks=[]
 for o in PARTS:
  me=bpy.data.meshes.new_from_object(o.evaluated_get(dg),preserve_all_data_layers=True,depsgraph=dg);me.transform(o.matrix_world);me.calc_loop_triangles()
  points=[gp(v.co) for v in me.vertices];bb=bounds(points);s=specs[o['source_solid']];lo=s['local_min'];hi=s['local_max']
  contained=all(bb[0][i]>=lo[i]-2e-6 and bb[1][i]<=hi[i]+2e-6 for i in range(3))
  bm=bmesh.new();bm.from_mesh(me);nonmanifold=sum(not e.is_manifold for e in bm.edges);bm.free()
  start=len(verts);verts.extend([v.co.copy() for v in me.vertices]);tris.extend([tuple(start+i for i in t.vertices) for t in me.loop_triangles])
  records.append({'name':o.name,'source_solid':o['source_solid'],'group':o['runtime_group'],'triangles':len(me.loop_triangles),'local_bounds':bb,'inside_original_solid':contained,'nonmanifold_edges':nonmanifold,'uv_layers':[u.name for u in me.uv_layers]})
  bpy.data.meshes.remove(me)
 def check(name,ok,detail=None):checks.append({'name':name,'passed':bool(ok),'detail':detail})
 check('every authored part stays within its original one of seven solids',all(r['inside_original_solid'] for r in records))
 check('every individual editable part closed',all(r['nonmanifold_edges']==0 for r in records))
 check('all parts explicit author UV layers',all(r['uv_layers']==['MetricUV','PanelUV'] for r in records))
 check('only expected navigation and four cover groups',{r['group'] for r in records}==set(GROUPS))
 check('no device/door/water body authored',not any('Selector' in r['name'] or 'Relay' in r['name'] for r in records))
 bvh=BVHTree.FromPolygons(verts,tris,all_triangles=True)
 rays=[]
 for x in [-8.69,-7,-5.31]:
  for y in [.41,1.8,3.19]:
   hit=bvh.ray_cast(bp(local((x,y,13))),bp((0,0,-1)),1.05)[0]
   rays.append({'world_x_y':[x,y],'opening_clear':hit is None})
 check('nine front rays leave exact doorway clear',all(r['opening_clear'] for r in rays),rays)
 hit=bvh.ray_cast(bp(local((-7.2,1,11.8))),Vector((0,0,-1)),1.2)[0]
 check('inside floor remains Y.4',hit is not None and abs(gp(hit).y-.4)<2e-6)
 hit=bvh.ray_cast(bp(local((-7,1,12.125))),Vector((0,0,-1)),1.2)[0]
 check('no fabricated threshold beyond floor Z12',hit is None)
 return {'status':'GEOMETRY_CHECKED_PENDING_VISUAL_REVIEW','checks':checks,'parts':records,'editable_pieces':len(records),'triangles':sum(r['triangles'] for r in records),'local_bounds':bounds([gp(v) for v in verts]),'author_material_count':len(MATERIALS),'scope':'Source prototype. Individual closure and containment, not full inter-part self-intersection or Godot flight/LOS tests. Existing full-box collision remains root-owned; shallow panel recesses are visual manufacture.'}

def setup_render():
 scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=24;scene.render.threads_mode='FIXED';scene.render.threads=2
 scene.render.resolution_x=1280;scene.render.resolution_y=900;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG';scene.view_settings.view_transform='AgX';scene.view_settings.exposure=0
 world=bpy.data.worlds.new('NeutralWorld');world.use_nodes=True;world.node_tree.nodes['Background'].inputs['Color'].default_value=(.65,.65,.65,1);world.node_tree.nodes['Background'].inputs['Strength'].default_value=.55;scene.world=world
 for name,at,power,size in [('Key',(-8,15,10),1700,10),('Fill',(10,9,-7),1000,9)]:
  light=bpy.data.lights.new(name,'AREA');light.energy=power;light.shape='DISK';light.size=size;o=bpy.data.objects.new(name,light);scene.collection.objects.link(o);o.location=bp(at);o.rotation_euler=(-o.location+bp((0,1,0))).to_track_quat('-Z','Y').to_euler()
 cam=bpy.data.cameras.new('SourceReviewCamera');o=bpy.data.objects.new('SourceReviewCamera',cam);scene.collection.objects.link(o);target=bp((0,1.5,0));o.location=target+bp((16,19.5,16));o.rotation_euler=(target-o.location).to_track_quat('-Z','Y').to_euler();cam.type='ORTHO';cam.ortho_scale=17;scene.camera=o
 # Neutral background plane is REVIEW_ONLY, outside asset roots and never exported.
 bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.015));floor=bpy.context.object;floor.name='REVIEW_ONLY_Background';m=bpy.data.materials.new('NeutralReviewFloor');m.use_nodes=True;bs=next((n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None)or m.node_tree.nodes.new('ShaderNodeBsdfPrincipled');bs.inputs['Base Color'].default_value=(.15,.15,.15,1);bs.inputs['Roughness'].default_value=.9;floor.data.materials.append(m)

def main():
 start=time.time();assert not (HERE/'pump_shell_prototype.blend').exists(),'Preserve previous run first.'
 config=json.loads((HERE/'input_config.json').read_text(encoding='utf-8'))
 assert config['atlas_sha256'] and ATLAS.is_file() and sha(ATLAS)==config['atlas_sha256'],'Root atlas must be received/visually reviewed and SHA locked before running.'
 assert sha(REF)==REF_SHA
 plan=json.loads(PLAN.read_text(encoding='utf-8'));current=json.loads((ROOT/'data/v3/terrain/i2_clinic_layout.json').read_text(encoding='utf-8'));old={s['id']:s for s in plan['fixed_shell_solids']}
 for s in current['fixed_solids']:
  if s['id'] in old:assert s['min']==old[s['id']]['world_min'] and s['max']==old[s['id']]['world_max'],'Seven source solids changed.'
 print(json.dumps({'stage':'start','pid':os.getpid(),'threads':2,'no_glb_no_runtime':True}),flush=True)
 bpy.ops.wm.read_factory_settings(use_empty=True);scene=bpy.context.scene;scene.unit_settings.system='METRIC'
 for d in ['source_inputs','evidence']: (HERE/d).mkdir(exist_ok=True)
 copied=HERE/'source_inputs/material_atlas_UNEDITED.png';shutil.copyfile(ATLAS,copied);assert sha(copied)==config['atlas_sha256']
 image=bpy.data.images.load(str(copied),check_existing=False);image.colorspace_settings.name='sRGB'
 MATERIALS.update(Wall=material('PS_WallPaint',image,(0,.5,.5,1),2.4,.68,.04,True,calm=(.74,(.32,.38,.40))),Zinc=material('PS_Zinc',image,(.5,.5,1,1),.9,.48,.55,calm=(.32,(.30,.31,.31))),Concrete=material('PS_Concrete',image,(0,0,.5,.5),1.8,.86,0,calm=(.52,(.31,.295,.27))),Teal=material('PS_Teal',image,(.5,0,1,.5),2.0,.67,.06,calm=(.70,(.06,.13,.15))),Seal=material('PS_Seal',image,(.5,0,1,.5),1.8,.89,0,tint=(.12,.14,.14)),Yellow=material('PS_YellowSafety',image,(0,.5,.5,1),1.8,.72,.02,tint=(1.7,1.05,.12)))
 root=bpy.data.objects.new('ClinicPumpShell',None);scene.collection.objects.link(root)
 for name in ['FloorSurface','WallFeetAndJambs','WestCover','EastCover','NorthCover','RoofCover']:
  o=bpy.data.objects.new(name,None);scene.collection.objects.link(o);o.parent=root;GROUPS[name]=o
 build(plan);bpy.context.view_layer.update();report=inspect(plan)
 report.update(reference_sha256=sha(REF),atlas_sha256=sha(copied),atlas_original=str(ATLAS),root_world_placement=[-7,0,8],no_runtime_or_layout_edits=True)
 (HERE/'evidence/geometry_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 if not all(c['passed'] for c in report['checks']):
  bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'FAILED_geometry.blend'));raise RuntimeError('Geometry gate failed; no review render.')
 setup_render();blend=HERE/'pump_shell_prototype.blend';bpy.ops.wm.save_as_mainfile(filepath=str(blend),relative_remap=False)
 image.filepath=bpy.path.relpath(str(copied));bpy.ops.wm.save_as_mainfile(filepath=str(blend),relative_remap=False)
 bpy.ops.wm.open_mainfile(filepath=str(blend));scene=bpy.context.scene
 for im in bpy.data.images:
  if im.source=='FILE' and im.filepath:
   p=Path(bpy.path.abspath(im.filepath));assert p.is_file() and sha(p)==config['atlas_sha256'];im.reload();assert len(list(im.pixels[:4]))==4 and im.has_data
 outputs=[]
 for name,cutaway in [('pump_shell_full',False),('pump_shell_source_cutaway',True)]:
  if cutaway:
   for o in bpy.data.objects:
    if o.get('runtime_group') in ['WestCover','EastCover','NorthCover','RoofCover']:o.hide_render=True
  path=HERE/'evidence'/f'{name}.png';scene.render.filepath=str(path);bpy.ops.render.render(write_still=True);outputs.append({'path':str(path),'sha256':sha(path),'scope':'Offline source shape/material review. Cutaway hides upper source groups, not a claim of production fader state.'})
 report.update(status='SOURCE_RENDERED_PENDING_ACTUAL_VISUAL_REVIEW',blend_sha256=sha(blend),images=outputs,elapsed_seconds=time.time()-start)
 (HERE/'evidence/geometry_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 print(json.dumps({'stage':'end','pid':os.getpid(),'seconds':time.time()-start,'triangles':report['triangles']}),flush=True)
if __name__=='__main__':main()
