"""Prepared source-only I2 cistern production candidate. NOT YET EXECUTED.
Load the frozen V2 editable source; retain exact base vertices and dynamic-water anchor.
Only this directory is writable. No import, world layout edits, or runtime asset export.
"""
from pathlib import Path
import sys,json,hashlib,math,time,os,argparse
import bpy,bmesh
from mathutils import Vector
SRC=Path(__file__).resolve().parent
ROOT=SRC.parents[3]
sys.path.insert(0,str(SRC))
from atlas import create_textures,mapped_uv
BASE=SRC.parent/'structure_v2/clinic_gravity_structure_v2.blend'
BASE_SHA='cf00087e95f64e91e744d4fac7ecb529277321e323a7931a100b0bf257bbcebd'
ORIGIN=Vector((-9,6,-7))
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def bp(p):
 v=Vector(p)-ORIGIN;return Vector((v.x,-v.z,v.y))
def gp(v):return Vector((v.x,v.z,-v.y))+ORIGIN
def normal_world(v):return Vector((v.x,v.z,-v.y))

def ensure_nodes(m):
 m.use_nodes=True;n=m.node_tree.nodes;n.clear()
 bs=n.new('ShaderNodeBsdfPrincipled');out=n.new('ShaderNodeOutputMaterial')
 m.node_tree.links.new(bs.outputs['BSDF'],out.inputs['Surface']);return bs

def pbr_material(paths):
 m=bpy.data.materials.new('CG_AuthoredSurfacePBR');bs=ensure_nodes(m)
 n=m.node_tree.nodes;lk=m.node_tree.links;uv=n.new('ShaderNodeUVMap');uv.uv_map='SurfaceUV'
 for role,path in paths.items():
  im=bpy.data.images.load(str(path));im.colorspace_settings.name='sRGB' if role=='BaseColor' else 'Non-Color'
  # Keep absolute while the loaded .blend still belongs to frozen structure_v2.
  # Relative paths before Save As would resolve against that old source directory.
  im.filepath=str(path.resolve())
  tx=n.new('ShaderNodeTexImage');tx.image=im;tx.extension='EXTEND';tx.label=role;lk.new(uv.outputs['UV'],tx.inputs['Vector'])
  if role=='Normal':
   nm=n.new('ShaderNodeNormalMap');nm.uv_map='SurfaceUV';nm.inputs['Strength'].default_value=.38
   lk.new(tx.outputs['Color'],nm.inputs['Color']);lk.new(nm.outputs['Normal'],bs.inputs['Normal'])
  else:lk.new(tx.outputs['Color'],bs.inputs[{'BaseColor':'Base Color','Roughness':'Roughness','Metallic':'Metallic'}[role]])
 return m

def uv_layer(o):
 while o.data.uv_layers:o.data.uv_layers.remove(o.data.uv_layers[0])
 o.data.uv_layers.new(name='SurfaceUV');o.data.uv_layers.active_index=0
 layer=o.data.uv_layers.get('SurfaceUV');layer.active_render=True;return layer

def assign(o,kind,pbr,lo=None,hi=None):
 o.data.materials.clear();o.data.materials.append(pbr)
 uv=uv_layer(o)
 pts=[gp(o.matrix_world@v.co) for v in o.data.vertices]
 if lo is None:lo=[min(p[i] for p in pts) for i in range(3)]
 if hi is None:hi=[max(p[i] for p in pts) for i in range(3)]
 for face in o.data.polygons:
  face.material_index=0
  normal=normal_world(o.matrix_world.to_3x3()@face.normal);axis=max(range(3),key=lambda i:abs(normal[i]))
  axes=[0,2] if axis==1 else [0 if axis==2 else 2,1]
  for li in face.loop_indices:
   p=pts[o.data.loops[li].vertex_index]
   u=(p[axes[0]]-lo[axes[0]])/max(hi[axes[0]]-lo[axes[0]],.001)
   v=(p[axes[1]]-lo[axes[1]])/max(hi[axes[1]]-lo[axes[1]],.001)
   uv.data[li].uv=mapped_uv(kind,u,v)

def remap_structure(o,pbr,plan):
 o.data.materials.clear();o.data.materials.append(pbr);uv=uv_layer(o)
 pts=[gp(o.matrix_world@v.co) for v in o.data.vertices]
 for f in o.data.polygons:
  f.material_index=0;c=sum((pts[i] for i in f.vertices),Vector())/len(f.vertices)
  normal=normal_world(f.normal);axis=max(range(3),key=lambda i:abs(normal[i]))
  owner=next((p for p in reversed(plan['parts']) if all(p['min'][i]-.0001<=c[i]<=p['max'][i]+.0001 for i in range(3))),None)
  if axis==1 and normal.y>.5 and abs(c.y-6)<.001:
   kind='liner' if -9.8<c.x<-8.2 and -7.5<c.z<-6.5 else 'deck'
   lo,hi=([-12,0,-10],[-5,6,-4.4]) if kind=='deck' else ([-9.8,6,-7.5],[-8.2,9,-6.5])
  elif owner:
   name=owner['id'];kind='paint_post' if name.startswith('SupportLeg') else 'paint_beam' if name.startswith('Longitudinal') else 'steel'
   lo,hi=owner['min'],owner['max']
  else:kind='paint_beam';lo=[-12,5.6,-10];hi=[-5,6,-4.4]
  axes=[0,2] if axis==1 else [0 if axis==2 else 2,1]
  for li in f.loop_indices:
   p=pts[o.data.loops[li].vertex_index]
   uv.data[li].uv=mapped_uv(kind,(p[axes[0]]-lo[axes[0]])/max(hi[axes[0]]-lo[axes[0]],.001),(p[axes[1]]-lo[axes[1]])/max(hi[axes[1]]-lo[axes[1]],.001))

def world_bounds(o):
 pts=[gp(o.matrix_world@v.co) for v in o.data.vertices]
 return [[min(p[i] for p in pts) for i in range(3)],[max(p[i] for p in pts) for i in range(3)]]

def run():
 ap=argparse.ArgumentParser();ap.add_argument('--render',action='store_true');ap.add_argument('--export-source-glb',action='store_true')
 args=ap.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
 assert sha(BASE)==BASE_SHA,'Frozen V2 source differs; stop, do not overwrite it.'
 blend=SRC/'clinic_gravity_production_candidate.blend'
 assert not blend.exists(),'Preserve candidate evidence before any revised run.'
 started=time.time();print(json.dumps({'stage':'start','pid':os.getpid(),'threads':2}),flush=True)
 bpy.ops.wm.open_mainfile(filepath=str(BASE))
 # All bpy handles are acquired AFTER open_mainfile, preventing stale RNA reuse.
 scene=bpy.context.scene;root=bpy.data.objects['ClinicCisternDeck'];source=bpy.data.collections['Editable_ClinicCistern_A']
 plan=json.loads((SRC.parent/'structure_v2/structure_plan.json').read_text(encoding='utf8'))
 baseline={o.name:[tuple(v.co) for v in o.data.vertices] for o in source.objects if o.type=='MESH'}
 paths=create_textures(SRC/'textures');pbr=pbr_material(paths)
 groups={};details=[];proposals=[]
 def register(o,group,collision):
  for c in list(o.users_collection):c.objects.unlink(o)
  source.objects.link(o);o.parent=root;o['runtime_group']=group;o['collision_class']=collision
  groups.setdefault(group,[]).append(o);details.append(o);return o
 def box(name,lo,hi,kind='paint_beam',group='SurfaceHardware',collision='shallow_visual_relief',bevel=.005):
  bpy.ops.mesh.primitive_cube_add(size=1,location=bp([(lo[i]+hi[i])/2 for i in range(3)]));o=bpy.context.object;o.name=name
  o.dimensions=(hi[0]-lo[0],hi[2]-lo[2],hi[1]-lo[1]);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
  register(o,group,collision);assign(o,kind,pbr,lo,hi)
  if bevel:
   b=o.modifiers.new('Small_inward_manufactured_edge','BEVEL');b.width=min(bevel,min(hi[i]-lo[i] for i in range(3))*.22);b.segments=1
   n=o.modifiers.new('WeightedNormals','WEIGHTED_NORMAL');n.keep_sharp=True
  return o
 def cylinder(name,a,b,radius,kind='steel',group='SurfaceHardware',collision='shallow_visual_relief',vertices=16):
  start,end=bp(a),bp(b);delta=end-start
  bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=radius,depth=delta.length,location=(start+end)/2)
  o=bpy.context.object;o.name=name;o.rotation_euler=delta.to_track_quat('Z','Y').to_euler()
  bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
  register(o,group,collision);assign(o,kind,pbr)
  return o
 visible=[o for o in source.objects if o.type=='MESH' and not o.hide_render]
 for o in visible:
  if o.name=='DeckAssembly_VisibleUnion':
   remap_structure(o,pbr,plan);o['runtime_group']='DeckStructure';groups.setdefault('DeckStructure',[]).append(o)
  elif o.name=='CisternFrontWindow':
   glass=bpy.data.materials.new('CG_ObservationWindow');bs=ensure_nodes(glass)
   bs.inputs['Base Color'].default_value=(.91,.97,.97,1);bs.inputs['Roughness'].default_value=.13;bs.inputs['Alpha'].default_value=.10
   assign(o,'liner',pbr)
   o.data.materials.clear();o.data.materials.append(glass);o['runtime_group']='ObservationWindow';groups.setdefault('ObservationWindow',[]).append(o)
  else:
   old_indices=[p.material_index for p in o.data.polygons]
   assign(o,'tank' if o.name.startswith('Cistern') else 'paint_post',pbr)
   # The originally marked inward faces are sterile ivory; no exterior salt/rust enters water.
   uv=o.data.uv_layers.get('SurfaceUV')
   for face,old in zip(o.data.polygons,old_indices):
    if old==1:
     for li in face.loop_indices:
      uv.data[li].uv=mapped_uv('liner',.5,.5)
   o['runtime_group']='CisternShell';groups.setdefault('CisternShell',[]).append(o)
 # Static graduation, not an invented current volume readout. Existing dynamic water stays separate.
 for i in range(1,12):
  y=6+i*.25;length=.085 if i%4==0 else .045
  box('LevelTick_%02d'%i,[-8.285,y-.008,-6.38],[-8.285+length,y+.008,-6.374],'liner',bevel=0)
 # Corner straps and fasteners occupy the frame; they never cross the clear viewing pane.
 for x in (-9.75,-8.25):
  for y in (6.12,8.92):
   cylinder('TankCornerBolt', [x,y,-6.381],[x,y,-6.371],.026,'steel',vertices=8)
 # Existing supporting nodes gain visible, localized fastening, not new braces through flight space.
 for p in plan['parts']:
  if not p['id'].startswith('BearingNode_'):continue
  lo,hi=p['min'],p['max'];x=(lo[0]+hi[0])/2;z=hi[2];y=5.35
  for dx in (-.20,.20):cylinder(p['id']+'_Bolt',[x+dx,y,z-.002],[x+dx,y,z+.006],.036,vertices=8)
 # Parent-authorized NEW collision candidates, explicitly separate from old structure.
 lid=box('CisternRemovableLid',[-9.92,9,-7.62],[-8.08,9.08,-6.38],'paint_beam','ProposedCover','new_collision_required',.014)
 neck=cylinder('FillVentNeck',[-9.20,9.08,-7.05],[-9.20,9.20,-7.05],.11,'steel','ProposedCover','new_collision_required',20)
 cap=cylinder('FillVentCap',[-9.20,9.20,-7.05],[-9.20,9.24,-7.05],.16,'paint_beam','ProposedCover','new_collision_required',20)
 # A single removable-lid joint: surface strip, not an open cavity or a hidden moving mechanic.
 box('LidInspectionJoint',[-9.82,9.080,-7.33],[-8.18,9.082,-7.322],'rubber','SurfaceHardware',bevel=0)
 flange=cylinder('OutletFlange',[-8.11,6.55,-7.15],[-8.04,6.55,-7.15],.12,'steel','ProposedOutlet','new_collision_required',20)
 pipe=cylinder('CappedOutletStub',[-8.04,6.55,-7.15],[-7.82,6.55,-7.15],.09,'steel','ProposedOutlet','new_collision_required',20)
 plug=cylinder('OutletBlankingCap',[-7.82,6.55,-7.15],[-7.78,6.55,-7.15],.11,'yellow','ProposedOutlet','new_collision_required',20)
 bpy.context.view_layer.update()
 for o in (lid,neck,cap,flange,pipe,plug):proposals.append({'name':o.name,'world_bounds':world_bounds(o),'requires_root_collision':True})
 preview=bpy.data.objects.get('PreviewWater_3200L_NOT_EXPORT')
 if preview:
  preview['exclude_export']=True;preview.parent=None
  m=bpy.data.materials.new('CG_Water_PreviewOnly');bs=ensure_nodes(m)
  bs.inputs['Base Color'].default_value=(.035,.32,.36,1);bs.inputs['Roughness'].default_value=.20;bs.inputs['Alpha'].default_value=.42
  preview.data.materials.clear();preview.data.materials.append(m)
 checks=[]
 def check(n,ok,d=None):checks.append({'name':n,'passed':bool(ok),'detail':d})
 check('frozen V2 source hash unchanged',sha(BASE)==BASE_SHA)
 check('all V2 mesh vertices unchanged',all([tuple(v.co) for v in bpy.data.objects[n].data.vertices]==verts for n,verts in baseline.items()))
 check('four posts and two beams retained',len([n for n in baseline if n.startswith('SupportLeg_')])==4 and len([n for n in baseline if n.startswith('LongitudinalBeam_')])==2)
 actual=[o for rows in groups.values() for o in rows]
 check('one explicit active render UV on every actual mesh',all(len(o.data.uv_layers)==1 and o.data.uv_layers.active.name=='SurfaceUV' and o.data.uv_layers.active.active_render for o in actual))
 topology=[]
 for o in actual:
  bm=bmesh.new();bm.from_mesh(o.data);topology.append({'name':o.name,'nonmanifold_edges':sum(not e.is_manifold for e in bm.edges)});bm.free()
 check('each actual mesh closed before optional bevel',all(t['nonmanifold_edges']==0 for t in topology),topology)
 check('water remains independent and excluded',preview is not None and preview.parent is None and preview.get('exclude_export',False))
 check('SourceWaterBase remains local origin',bpy.data.objects['SourceWaterBase'].location.length<1e-8)
 check('proposal max height explicit',max(p['world_bounds'][1][1] for p in proposals)<=9.24001,proposals)
 scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=24;scene.cycles.use_denoising=True
 scene.render.threads_mode='FIXED';scene.render.threads=2
 scene.render.resolution_x=1280;scene.render.resolution_y=1280;scene.render.resolution_percentage=100
 scene.view_settings.view_transform='AgX';scene.view_settings.exposure=0
 evidence=SRC/'evidence';evidence.mkdir(exist_ok=True)
 report={'status':'SOURCE_READY_FOR_REVIEW' if all(c['passed'] for c in checks) else 'FAILED_NO_RENDER','pid':os.getpid(),'base_sha256':BASE_SHA,'checks':checks,'proposed_collisions':proposals,'groups':{k:[o.name for o in v] for k,v in groups.items()},'pbr_method':'UV-authored raster maps, NOT high/low baking; BaseColor sRGB once, other maps Non-Color, PNG v orientation + normal Y consistent','scope':'source candidate only; no real engine/collision/water/visual acceptance','outlet':'CAPPED connection point, not a connected or functioning pipe network'}
 bpy.ops.wm.save_as_mainfile(filepath=str(blend),relative_remap=False)
 for image in bpy.data.images:
  if image.source=='FILE' and image.filepath.replace(chr(92),'/').rsplit('/',1)[-1].startswith('CG_SurfaceAtlas_'):
   image.filepath='//textures/'+image.filepath.replace(chr(92),'/').rsplit('/',1)[-1]
 bpy.ops.wm.save_as_mainfile(filepath=str(blend),relative_remap=False)
 (evidence/'production_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
 if not all(c['passed'] for c in checks):raise RuntimeError('Source candidate gate failed; source/report retained, do not render.')
 if args.render:
  path=evidence/'clinic_gravity_production_candidate.png';scene.render.image_settings.file_format='PNG';scene.render.filepath=str(path)
  bpy.ops.render.render(write_still=True);report['image_sha256']=sha(path)
 # Later optional explicit export stays under this source directory only.
 if args.export_source_glb:
  export_coll=bpy.data.collections.new('EXPORT_COPY');scene.collection.children.link(export_coll);copies=[]
  for group,objects in groups.items():
   groupcopies=[]
   for o in objects:
    dg=bpy.context.evaluated_depsgraph_get();me=bpy.data.meshes.new_from_object(o.evaluated_get(dg),depsgraph=dg)
    c=bpy.data.objects.new(o.name+'_export',me);export_coll.objects.link(c);c.matrix_world=o.matrix_world;groupcopies.append(c)
   bpy.ops.object.select_all(action='DESELECT')
   for c in groupcopies:c.select_set(True)
   bpy.context.view_layer.objects.active=groupcopies[0]
   if len(groupcopies)>1:bpy.ops.object.join()
   c=bpy.context.object;c.name=group;c.parent=None;bpy.ops.object.transform_apply(location=True,rotation=True,scale=True);copies.append(c)
  # Blender names are global: avoid an unintended .001 suffix in the exported contract.
  original_marker=bpy.data.objects['SourceWaterBase'];original_marker.name='SOURCE_ONLY_SourceWaterBase'
  marker=bpy.data.objects.new('SourceWaterBase',None);export_coll.objects.link(marker);copies.append(marker)
  bpy.ops.object.select_all(action='DESELECT')
  for c in copies:c.select_set(True)
  path=SRC/'candidate_only.glb'
  bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_apply=True,export_yup=True,export_texcoords=True,export_normals=True,export_materials='EXPORT',export_cameras=False,export_lights=False,export_animations=False,export_extras=True)
  marker.name='EXPORTED_SourceWaterBase';original_marker.name='SourceWaterBase'
  report['source_glb_sha256']=sha(path);report['source_glb_needs_independent_readback']=True
 report.update(elapsed_seconds=time.time()-started,blend_sha256=sha(blend),texture_sha256={k:sha(p) for k,p in paths.items()})
 (evidence/'production_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
 print(json.dumps({'stage':'end','pid':os.getpid(),'seconds':report['elapsed_seconds'],'failed':sum(not c['passed'] for c in checks)},ensure_ascii=False),flush=True)

if __name__=='__main__':run()
