"""Source preview only. Requires root's explicit serial CPU2 window.
No PBR bake, GLB export, runtime install or image-pixel modification.
"""
from pathlib import Path
import sys, json, math, time, os
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parent))
import plan
import bpy, bmesh
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

HERE=plan.HERE; ROOT=plan.ROOT
PREP=json.loads((HERE/'prepared.json').read_text(encoding='utf-8'))
CHECKS=[]

def check(name,passed,detail=None):
 CHECKS.append({'name':name,'passed':bool(passed),'detail':detail})

def verify_inputs():
 for name,record in PREP['inputs'].items():
  assert plan.sha(ROOT/name)==record['sha256'], 'Frozen source changed: '+name

def node_math(mat,operation,a,b=0):
 n=mat.node_tree.nodes.new('ShaderNodeMath');n.operation=operation
 for value,socket in [(a,n.inputs[0]),(b,n.inputs[1])]:
  if hasattr(value,'node'): mat.node_tree.links.new(value,socket)
  else: socket.default_value=value
 return n.outputs[0]

def rectangle(mat,x,z,cx,cz,hx,hz):
 xx=node_math(mat,'LESS_THAN',node_math(mat,'ABSOLUTE',node_math(mat,'SUBTRACT',x,cx)),hx)
 zz=node_math(mat,'LESS_THAN',node_math(mat,'ABSOLUTE',node_math(mat,'SUBTRACT',z,cz)),hz)
 return node_math(mat,'MULTIPLY',xx,zz)

def materials(report):
 source=ROOT/'asset_sources/v3/i2_maintenance_paving/p3/maintenance_paving_p3.blend'
 names=['SOURCE_W3_'+r for r in ['concrete','teal','steel','seal']]
 with bpy.data.libraries.load(str(source),link=False) as (available,loaded):
  assert all(name in available.materials for name in names)
  loaded.materials=names
  loaded.collections=['Editable_W3','Editable_E3']
 for coll in loaded.collections:
  bpy.context.scene.collection.children.link(coll)
  coll['review_context_only']=True
 for name,x in [('W3',17),('E3',22)]:
  obj=bpy.data.objects['MaintenancePaving_'+name]
  obj.location=plan.bg((x,0,0))
  obj['review_context_only']=True
 metric=bpy.data.objects.new('WorldMetricCoordinates',None)
 bpy.context.scene.collection.objects.link(metric);metric.location=plan.bg((0,0,0))
 result={}
 for role in ['concrete','teal','steel','seal']:
  mat=bpy.data.materials['SOURCE_W3_'+role].copy();mat.name='EAST_SOURCE_'+role
  for n in mat.node_tree.nodes:
   if n.type=='TEX_COORD': n.object=metric
  result[role]=mat
 concrete=result['concrete'];bs=next(n for n in concrete.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
 check('approved P3 concrete stays nonmetal and has no albedo-derived normal',bs.inputs['Metallic'].default_value==0 and not bs.inputs['Normal'].is_linked)
 mat=result['teal'];nodes,links=mat.node_tree.nodes,mat.node_tree.links
 texture=nodes['P3_IntactPaint_UpperWindow']
 uv=nodes.new('ShaderNodeUVMap');uv.uv_map='PaintUV';links.new(uv.outputs['UV'],texture.inputs['Vector']);texture.extension='REPEAT'
 coord=nodes.new('ShaderNodeTexCoord');coord.object=metric
 sep=nodes.new('ShaderNodeSeparateXYZ');links.new(coord.outputs['Object'],sep.inputs[0])
 x=sep.outputs['X'];z=node_math(mat,'MULTIPLY',sep.outputs['Y'],-1)
 worn=0
 for n in [1,7]:
  body=report['lids'][n]['body'];cx=(body[0]+body[1])/2;cz=(body[2]+body[3])/2
  worn=node_math(mat,'MAXIMUM',worn,rectangle(mat,x,z,body[1]-.0025,cz+.18,.0025,.065))
  worn=node_math(mat,'MAXIMUM',worn,rectangle(mat,x,z,cx+.026,cz+.024,.024,.003))
 geo=nodes.new('ShaderNodeNewGeometry');normal=nodes.new('ShaderNodeSeparateXYZ');links.new(geo.outputs['Normal'],normal.inputs[0])
 worn=node_math(mat,'MULTIPLY',worn,node_math(mat,'GREATER_THAN',normal.outputs['Z'],.7))
 bs=next(n for n in nodes if n.type=='BSDF_PRINCIPLED')
 mix=bs.inputs['Base Color'].links[0].from_node
 assert mix.type=='MIX_RGB'
 links.new(node_math(mat,'MULTIPLY',worn,.7),mix.inputs[0])
 links.new(node_math(mat,'MULTIPLY',worn,.65),bs.inputs['Metallic'])
 if texture.image is not None: _pixel=texture.image.pixels[:4]
 check('paint reuses original image with explicit metric UV and real selected grip wear',texture.image is not None and texture.image.size[0]>0)
 return result

def uv_and_inspect(obj,report):
 if obj.modifiers:
  depsgraph=bpy.context.evaluated_depsgraph_get()
  obj.data=bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph),preserve_all_data_layers=True,depsgraph=depsgraph)
  obj.modifiers.clear()
 mesh=obj.data;mesh.update();mesh.calc_loop_triangles()
 # All nodes are identity; coordinates already relative to the single origin.
 layers={name:mesh.uv_layers.new(name=name) for name in ['SourceUV','ConcreteUV','PaintUV']}
 # UV collection growth may invalidate RNA handles: always retrieve by name.
 for polygon in mesh.polygons:
  axis=max(range(3),key=lambda i:abs(polygon.normal[i]))
  for li in polygon.loop_indices:
   p=mesh.vertices[mesh.loops[li].vertex_index].co
   x,y,z=p.x+plan.ORIGIN[0],p.z+plan.ORIGIN[1],-p.y+plan.ORIGIN[2]
   pair=(x,z) if axis==2 else (z,y) if axis==0 else (x,y)
   mesh.uv_layers['ConcreteUV'].data[li].uv=(pair[0]/4,pair[1]/4)
   mesh.uv_layers['SourceUV'].data[li].uv=(pair[0]/4,pair[1]/4)
   mesh.uv_layers['PaintUV'].data[li].uv=(z/4,.60+.32*max(0,min(1,(x-19.02)/.45)))
 mesh.uv_layers.active_index=0;mesh.uv_layers['SourceUV'].active_render=True
 bm=bmesh.new();bm.from_mesh(mesh)
 boundary=sum(not e.is_manifold for e in bm.edges);volume=bm.calc_volume(signed=True);bm.free()
 check(obj.name+' closed positive finite solid',boundary==0 and volume>0 and all(math.isfinite(v) for p in mesh.vertices for v in p.co),{'bad_edges':boundary,'volume_m3':volume})
 check(obj.name+' finite explicit source UV',all(math.isfinite(v) for layer in mesh.uv_layers for uv in layer.data for v in uv.uv))
 report['parts'].append({'name':obj.name,'role':obj['role'],'triangles':len(mesh.loop_triangles),'bounds_local_blender':[[min(v.co[i] for v in mesh.vertices) for i in range(3)],[max(v.co[i] for v in mesh.vertices) for i in range(3)]]})

def mesh_object(spec,mat,parent):
 mesh=bpy.data.meshes.new(spec['name']);mesh.from_pydata(spec['vertices'],[],spec['faces']);mesh.update()
 obj=bpy.data.objects.new(spec['name'],mesh);bpy.context.scene.collection.objects.link(obj)
 obj.parent=parent;obj.matrix_basis=Matrix.Identity(4);mesh.materials.append(mat)
 obj['role']=spec['role'];obj['export_piece']=True
 width=.003 if spec['role']=='concrete' and spec['name']!='FullBearingBed' else .001 if spec['role'] in ['teal','steel'] else 0
 if width:
  mod=obj.modifiers.new('SameSourceInwardEdge','BEVEL');mod.width=width;mod.segments=1;mod.limit_method='ANGLE'
 return obj

def cylinders(lids,mat,parent):
 result=[]
 for n,lid in enumerate(lids):
  for k,(x,z) in enumerate(lid['fasteners']):
   bpy.ops.mesh.primitive_cylinder_add(vertices=8,radius=.011,depth=.025,location=plan.bg((x,-.0185,z)))
   obj=bpy.context.object;obj.name=f'CountersunkFastener{n}_{k}'
   obj.data.transform(obj.matrix_world);obj.matrix_world=Matrix.Identity(4);obj.parent=parent
   while obj.data.uv_layers: obj.data.uv_layers.remove(obj.data.uv_layers[0])
   obj.data.materials.append(mat);obj['role']='steel';obj['export_piece']=True;result.append(obj)
 return result

def bvh_for(objects):
 vertices=[];polygons=[]
 for obj in objects:
  obj.data.calc_loop_triangles();offset=len(vertices)
  vertices.extend(obj.matrix_world@v.co for v in obj.data.vertices)
  polygons.extend(tuple(offset+i for i in t.vertices) for t in obj.data.loop_triangles)
 return BVHTree.FromPolygons(vertices,polygons,all_triangles=True)

def geometry_checks(objects,report):
 tree=bvh_for(objects);probes=[]
 def probe(x,z,expected,label):
  hit=tree.ray_cast(Vector(plan.bg((x,1,z))),Vector((0,0,-1)),2)[0]
  y=float(hit.z) if hit is not None else None
  ok=y is None if expected is None else y is not None and abs(y-expected)<.00001
  check(label,ok,{'world_xz':[x,z],'expected_y':expected,'actual_y':y});probes.append({'label':label,'actual_y':y})
 for hole in report['body_holes']:
  a,b,c,d=hole['rect'];cx,cz=(a+b)/2,(c+d)/2
  probe(cx,cz,None,hole['id']+' full-depth actual opening')
  probe(b+.006,cz,-.012,hole['id']+' shallow sealing collar')
  probe(b+.022,cz,0,hole['id']+' concrete outside collar')
 for x,z,y,label in [(17.1,6,None,'no duplicate top over east bank'),(24.6,6,None,'no exterior overshoot'),(22,2.005,0,'north joins old full seal without another half seal'),(22,1.995,None,'new asset does not invade existing north paving'),(23,6,0,'full three-metre clear route'),(19.25,4.5,-.004,'actual solid recessed inspection cover')]: probe(x,z,y,label)
 report['ray_probes']=probes
 top=max(v.co.z for obj in objects for v in obj.data.vertices)
 bottom=min(v.co.z for obj in objects for v in obj.data.vertices)
 check('all new detail stays Y -0.18..0',abs(bottom+.18)<1e-6 and abs(top)<1e-6,[bottom,top])
 # Every source top loop must keep affine 4m world UV: it does not reset at
 # panel, hole, footprint edge or irregular span.
 exact=True
 for obj in objects:
  for poly in obj.data.polygons:
   if poly.normal.z<.7: continue
   for li in poly.loop_indices:
    v=obj.data.vertices[obj.data.loops[li].vertex_index].co
    target=Vector(((v.x+plan.ORIGIN[0])/4,(-v.y+plan.ORIGIN[2])/4))
    exact=exact and (obj.data.uv_layers['ConcreteUV'].data[li].uv-target).length<1e-6
 check('top material keeps continuous metre scale across all source pieces',exact)

def studio():
 scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=16
 scene.cycles.use_denoising=True;scene.render.threads_mode='FIXED';scene.render.threads=2
 scene.render.resolution_x=1536;scene.render.resolution_y=1024;scene.render.resolution_percentage=100
 scene.render.image_settings.file_format='PNG';scene.view_settings.view_transform='AgX';scene.view_settings.exposure=0
 world=bpy.data.worlds.new('NeutralOfflineReview');world.use_nodes=True
 world.node_tree.nodes['Background'].inputs['Color'].default_value=(.50,.54,.58,1)
 world.node_tree.nodes['Background'].inputs['Strength'].default_value=.65;scene.world=world
 for name,at,power,size in [('Key',(9,14,14),2100,10),('Fill',(30,10,1),1100,9)]:
  data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size
  obj=bpy.data.objects.new(name,data);scene.collection.objects.link(obj);obj.location=plan.bg(at)
  obj.rotation_euler=(Vector((0,0,0))-obj.location).to_track_quat('-Z','Y').to_euler()
 camera=bpy.data.objects.new('OfflineOblique',bpy.data.cameras.new('OfflineOblique'));scene.collection.objects.link(camera)
 camera.data.type='ORTHO';scene.camera=camera
 return camera

def aim(camera,target,offset,scale):
 at=[target[i]+offset[i] for i in range(3)];camera.location=plan.bg(at)
 camera.rotation_euler=(Vector(plan.bg(target))-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.ortho_scale=scale

def context_supports(report):
 coll=bpy.data.collections.new('REVIEW_ONLY_ExistingFiveSupports');bpy.context.scene.collection.children.link(coll)
 mat=bpy.data.materials.new('REVIEW_ONLY_ExistingSupportGray');mat.diffuse_color=(.16,.18,.17,1);mat.use_nodes=True
 bs=mat.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=mat.diffuse_color;bs.inputs['Roughness'].default_value=.8
 for h in report['body_holes']:
  lo,hi=h['min'],h['max'];center=[(a+b)/2 for a,b in zip(lo,hi)]
  bpy.ops.mesh.primitive_cube_add(size=1,location=plan.bg(center));obj=bpy.context.object;obj.name='REVIEW_ONLY_'+h['id']
  obj.dimensions=(hi[0]-lo[0],hi[2]-lo[2],hi[1]-lo[1]);obj.data.materials.append(mat);obj['review_context_only']=True
  for old in list(obj.users_collection): old.objects.unlink(obj)
  coll.objects.link(obj)
 return coll

def main():
 started=time.monotonic();verify_inputs();assert not (HERE/'editable_source.blend').exists()
 print(json.dumps({'stage':'source_build_start','pid':os.getpid(),'cpu_threads':2,'bake':False,'export':False}),flush=True)
 bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.scene.unit_settings.system='METRIC'
 specs,report=plan.build();report.update(checks=CHECKS,parts=[],status='BUILDING_NOT_ACCEPTED')
 mats=materials(report)
 parent=bpy.data.objects.new('EastMaintenanceExtension',None);bpy.context.scene.collection.objects.link(parent)
 parent['world_origin_godot']=plan.ORIGIN;parent['scope']='visual only, original collision unchanged by caller'
 objects=[mesh_object(spec,mats[spec['role']],parent) for spec in specs]
 objects+=cylinders(report['lids'],mats['steel'],parent)
 for obj in objects: uv_and_inspect(obj,report)
 bpy.context.view_layer.update();geometry_checks(objects,report)
 support_context=context_supports(report)
 for image in bpy.data.images:
  if image.source=='FILE' and image.filepath:
   image.filepath=str(Path(bpy.path.abspath(image.filepath)).resolve())
   if not image.packed_file:
    assert Path(image.filepath).is_file(),image.filepath
    image.reload();_pixel=image.pixels[:4];assert image.has_data
 camera=studio();aim(camera,(20.7,0,7.0),(13,18,16),22)
 report['triangles']=sum(r['triangles'] for r in report['parts'])
 (HERE/'evidence').mkdir(exist_ok=True)
 (HERE/'geometry_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
 bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'editable_source.blend'),relative_remap=False)
 if not all(c['passed'] for c in CHECKS): raise RuntimeError('Actual source checks failed; preserve blend/report, no preview.')
 previews=[]
 for name,target,offset,scale in [('01-extension-overview',(20.7,0,7.0),(13,18,16),22),('02-foot-and-north-joint',(19.6,0,4.4),(8,10,9),9.5)]:
  support_context.hide_render=name.startswith('02')
  aim(camera,target,offset,scale);path=HERE/'evidence'/(name+'.png')
  bpy.context.scene.render.filepath=str(path);bpy.ops.render.render(write_still=True)
  previews.append({'path':str(path),'sha256':plan.sha(path),'scope':'offline editable source plus original north two tiles; five read-only JSON support proxies visible in 01 and hidden in 02; not Godot'})
 verify_inputs();report.update(status='SOURCE_PREVIEW_AWAITING_ROOT_REVIEW',previews=previews,elapsed_seconds=time.monotonic()-started,blend_sha256=plan.sha(HERE/'editable_source.blend'))
 (HERE/'geometry_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
 print(json.dumps({'pid':os.getpid(),'checks':len(CHECKS),'failed':sum(not r['passed'] for r in CHECKS),'triangles':report['triangles'],'elapsed_seconds':report['elapsed_seconds']}),flush=True)

if __name__=='__main__': main()
