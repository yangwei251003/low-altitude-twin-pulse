"""Prepared material-only revision. No Blender execution until root grants CPU2.
Generated PNG is copied byte-for-byte, never pixel-edited by Python. Image remix,
UV alignment and derived PBR maps are Blender shader nodes + native EMIT bake.
"""
from pathlib import Path
import bpy,sys,json,hashlib,time,os,argparse,shutil
SRC=Path(__file__).resolve().parent
ROOT=SRC.parents[3]
BASE=SRC.parent/'revision_v3/clinic_gravity_revision_v3.blend'
BASE_SHA='6d265617795066ff6318ae8521e9ad5441b533bb17e8a822672e530f1240572f'
GENERATED=ROOT/'references/v3/production/clinic_gravity/material_atlas_v4/clinic_gravity_basecolor_v4.png'
GENERATED_SHA='ada26062121fa77b22ca23a1d9738b684fe9b7490448e99702685b6a566bfd75'
LEGACY=SRC.parent/'revision_v3/textures/CG_SurfaceAtlas_BaseColor.png'
LEGACY_SHA='588aa24bad069f4af3f73b4ac6dfe3a9498175b5449ef60a9da5596da6499a47'
SIZE=2048
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def geometry_hash():
 rows=[]
 for o in sorted(bpy.data.objects,key=lambda o:o.name):
  if o.type=='MESH':rows.append((o.name,[list(x) for x in o.matrix_world],[list(v.co) for v in o.data.vertices],[list(p.vertices) for p in o.data.polygons],o.hide_render))
 return hashlib.sha256(json.dumps(rows,separators=(',',':')).encode()).hexdigest()
def uv_hash():
 rows=[(o.name,[(u.name,[list(d.uv) for d in u.data]) for u in o.data.uv_layers]) for o in sorted(bpy.data.objects,key=lambda o:o.name) if o.type=='MESH']
 return hashlib.sha256(json.dumps(rows,separators=(',',':')).encode()).hexdigest()

def source_graph(generated,legacy):
 m=bpy.data.materials.new('CG_V4_SOURCE_NodeComposite');m.use_nodes=True;m.use_fake_user=True;n=m.node_tree.nodes;n.clear();links=m.node_tree.links
 def link_or_value(value,target):
  if hasattr(value,'node'):links.new(value,target)
  else:target.default_value=value
 def mathop(op,a,b=0):
  q=n.new('ShaderNodeMath');q.operation=op;link_or_value(a,q.inputs[0]);link_or_value(b,q.inputs[1]);return q.outputs[0]
 def mul(a,b):return mathop('MULTIPLY',a,b)
 def add(a,b):return mathop('ADD',a,b)
 def sub(a,b):return mathop('SUBTRACT',a,b)
 def gt(a,b):return mathop('GREATER_THAN',a,b)
 def lt(a,b):return mathop('LESS_THAN',a,b)
 def blend(a,b,t):return add(mul(a,sub(1,t)),mul(b,t))
 uv=n.new('ShaderNodeUVMap');uv.uv_map='SurfaceUV';sep=n.new('ShaderNodeSeparateXYZ');links.new(uv.outputs['UV'],sep.inputs[0]);u,v=sep.outputs['X'],sep.outputs['Y']
 deck=mul(lt(u,.5),lt(v,.5));clean=mul(gt(u,.5),gt(v,.75))
 def piecewise(value,xs,ys):
  result=ys[0]
  for i in range(len(xs)-1):
   q=n.new('ShaderNodeMapRange');q.clamp=True;link_or_value(value,q.inputs['Value']);q.inputs['From Min'].default_value=xs[i];q.inputs['From Max'].default_value=xs[i+1];q.inputs['To Min'].default_value=0;q.inputs['To Max'].default_value=1
   result=add(result,mul(q.outputs['Result'],ys[i+1]-ys[i]))
  return result
 pad=6/2048;span=.5-2*pad
 old_u=lambda worldx:pad+span*(worldx+12)/7
 old_v=lambda worldz:pad+span*(worldz+10)/5.6
 # Read-only image measurement: seam valleys x173/395, y812/1097, drain frame1206..1233.
 # UV pixel-center targets have ~2 px source uncertainty; 5 cm real caps cover it.
 xk=[-12,-10.05,-7.6,-5];u_dest=[.003,173.5/1254,394.5/1254,.497]
 zk=[-10,-9.785,-9.70,-9.615,-8.6,-6.05,-4.4]
 v_dest=[.003,(1254-1233.5)/1254,(1254-1220)/1254,(1254-1205.5)/1254,(1254-1097.5)/1254,(1254-812.5)/1254,.497]
 aligned_u=piecewise(u,[old_u(x) for x in xk],u_dest);aligned_v=piecewise(v,[old_v(z) for z in zk],v_dest)
 comb=n.new('ShaderNodeCombineXYZ');links.new(blend(u,aligned_u,deck),comb.inputs['X']);links.new(blend(v,aligned_v,deck),comb.inputs['Y'])
 gen=n.new('ShaderNodeTexImage');gen.image=bpy.data.images.load(str(generated),check_existing=False);gen.image.colorspace_settings.name='sRGB';gen.extension='EXTEND';gen.label='Unedited native imagegen input';links.new(comb.outputs[0],gen.inputs['Vector'])
 old=n.new('ShaderNodeTexImage');old.image=bpy.data.images.load(str(legacy),check_existing=False);old.image.colorspace_settings.name='sRGB';old.extension='EXTEND';old.label='Frozen clean liner + rubber ONLY';links.new(uv.outputs['UV'],old.inputs['Vector'])
 mix=n.new('ShaderNodeMixRGB');mix.blend_type='MIX';links.new(clean,mix.inputs[0]);links.new(gen.outputs['Color'],mix.inputs[1]);links.new(old.outputs['Color'],mix.inputs[2]);base=mix.outputs[0]
 # Conservative material classification, NOT measured physical PBR recovered by AI.
 channels=n.new('ShaderNodeSeparateColor');channels.mode='RGB';links.new(base,channels.inputs[0]);r,g,b=channels.outputs['Red'],channels.outputs['Green'],channels.outputs['Blue']
 maximum=mathop('MAXIMUM',mathop('MAXIMUM',r,g),b);minimum=mathop('MINIMUM',mathop('MINIMUM',r,g),b)
 gray=mul(mul(lt(sub(maximum,minimum),.075),gt(maximum,.10)),lt(maximum,.55))
 rust=mul(mul(gt(r,mul(g,1.2)),gt(r,mul(b,1.45))),gt(r,.045))
 steel=mul(mul(mul(gt(u,.5),lt(u,.75)),gt(v,.5)),lt(v,.75))
 yellow=mul(mul(gt(u,.75),gt(v,.5)),lt(v,.75))
 liner=mul(mul(gt(u,.5),lt(u,.75)),gt(v,.75));rubber=mul(gt(u,.75),gt(v,.75))
 rough=add(sub(.64,mul(gray,.13)),mul(rust,.26));rough=blend(rough,.84,deck);rough=blend(rough,add(.35,mul(rust,.5)),steel);rough=blend(rough,add(.67,mul(rust,.2)),yellow);rough=blend(rough,.35,liner);rough=blend(rough,.84,rubber)
 metal=mul(add(.08,mul(gray,.57)),sub(1,rust));metal=blend(metal,mul(.76,sub(1,mul(rust,.92))),steel);metal=mul(metal,sub(1,mathop('MINIMUM',1,add(add(deck,liner),rubber))))
 normal=n.new('ShaderNodeRGB');normal.outputs[0].default_value=(.5,.5,1,1);normal.label='Neutral tangent normal: no false relief from generated color'
 emission=n.new('ShaderNodeEmission');emission.inputs['Strength'].default_value=1;out=n.new('ShaderNodeOutputMaterial');links.new(emission.outputs[0],out.inputs['Surface'])
 targets={'BaseColor':base,'Roughness':rough,'Metallic':metal,'Normal':normal.outputs[0]}
 mapping={'image_size':[1254,1254],'deck_world_x':xk,'deck_source_u':u_dest,'deck_world_z':zk,'deck_source_v':v_dest,'source_measurement_uncertainty_pixels':2,'note':'shader UV warp, then native bake to existing SurfaceUV; no generated-PNG pixel edits'}
 return m,emission,targets,mapping

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--render',action='store_true');args=ap.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
 blend=SRC/'clinic_gravity_material_v4.blend';assert not blend.exists(),'Preserve previous run before revision.'
 assert sha(BASE)==BASE_SHA and sha(GENERATED)==GENERATED_SHA and sha(LEGACY)==LEGACY_SHA
 start=time.time();print(json.dumps({'stage':'start','pid':os.getpid(),'threads':2}),flush=True)
 bpy.ops.wm.open_mainfile(filepath=str(BASE));scene=bpy.context.scene;before_geo=geometry_hash();before_uv=uv_hash()
 for im in bpy.data.images:
  if im.source=='FILE' and im.filepath:im.filepath=str(Path(bpy.path.abspath(im.filepath)).resolve())
 inp=SRC/'source_inputs';inp.mkdir(exist_ok=True);tex=SRC/'textures';tex.mkdir(exist_ok=True);evid=SRC/'evidence';evid.mkdir(exist_ok=True)
 generated=inp/'imagegen_basecolor_v4_UNEDITED.png';legacy=inp/'frozen_v3_basecolor.png';shutil.copyfile(GENERATED,generated);shutil.copyfile(LEGACY,legacy)
 assert sha(generated)==GENERATED_SHA and sha(legacy)==LEGACY_SHA
 author,emission,targets,mapping=source_graph(generated,legacy)
 helper=bpy.data.collections.new('TEMP_BAKE_ONLY');scene.collection.children.link(helper)
 bpy.ops.mesh.primitive_plane_add(size=2,location=(1000,1000,1000));plane=bpy.context.object;plane.name='TEMP_ATLAS_BAKE_PLANE'
 for c in list(plane.users_collection):c.objects.unlink(plane)
 helper.objects.link(plane);plane.data.uv_layers.active.name='SurfaceUV';plane.data.materials.append(author)
 bpy.ops.object.select_all(action='DESELECT');plane.select_set(True);bpy.context.view_layer.objects.active=plane
 scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=1;scene.render.threads_mode='FIXED';scene.render.threads=2
 outputs={};bake_rows=[]
 for role,socket in targets.items():
  for link in list(emission.inputs['Color'].links):author.node_tree.links.remove(link)
  author.node_tree.links.new(socket,emission.inputs['Color'])
  image=bpy.data.images.new('CG_V4_'+role,width=SIZE,height=SIZE,alpha=False,float_buffer=False);image.colorspace_settings.name='sRGB' if role=='BaseColor' else 'Non-Color'
  target=author.node_tree.nodes.new('ShaderNodeTexImage');target.image=image;target.label='BAKED_'+role
  for node in author.node_tree.nodes:node.select=False
  target.select=True;author.node_tree.nodes.active=target
  print(json.dumps({'stage':'bake','role':role,'pid':os.getpid()}),flush=True)
  bpy.ops.object.bake(type='EMIT',use_clear=True,margin=0)
  path=tex/('CG_V4_'+role+'.png');image.filepath_raw=str(path);image.file_format='PNG';image.save()
  # Final material references a real FILE image, not an unsaved GENERATED buffer.
  loaded=bpy.data.images.load(str(path),check_existing=False);loaded.colorspace_settings.name='sRGB' if role=='BaseColor' else 'Non-Color';target.image=loaded;outputs[role]=(loaded,path)
  bake_rows.append({'role':role,'sha256':sha(path),'colorspace':loaded.colorspace_settings.name,'method':'native Blender EMIT node bake'})
 # Restore author graph to basecolor for editable provenance, not last normal channel.
 for link in list(emission.inputs['Color'].links):author.node_tree.links.remove(link)
 author.node_tree.links.new(targets['BaseColor'],emission.inputs['Color'])
 helper_mesh=plane.data;bpy.data.objects.remove(plane,do_unlink=True);bpy.data.meshes.remove(helper_mesh);bpy.data.collections.remove(helper)
 pbr=bpy.data.materials['CG_V3_ManufacturedSurfacePBR'];pbr.name='CG_V4_BakedPBR';n=pbr.node_tree.nodes;n.clear();links=pbr.node_tree.links
 bs=n.new('ShaderNodeBsdfPrincipled');out=n.new('ShaderNodeOutputMaterial');links.new(bs.outputs['BSDF'],out.inputs['Surface']);uv=n.new('ShaderNodeUVMap');uv.uv_map='SurfaceUV'
 for role,(image,path) in outputs.items():
  node=n.new('ShaderNodeTexImage');node.image=image;node.label=role;node.extension='EXTEND';links.new(uv.outputs['UV'],node.inputs['Vector'])
  if role=='Normal':
   nm=n.new('ShaderNodeNormalMap');nm.uv_map='SurfaceUV';links.new(node.outputs['Color'],nm.inputs['Color']);links.new(nm.outputs['Normal'],bs.inputs['Normal'])
  else:links.new(node.outputs['Color'],bs.inputs[{'BaseColor':'Base Color','Roughness':'Roughness','Metallic':'Metallic'}[role]])
 checks=[{'name':'frozen source SHA unchanged','passed':sha(BASE)==BASE_SHA},{'name':'all geometry/transforms/visibility unchanged','passed':geometry_hash()==before_geo},{'name':'all actual SurfaceUV coordinates unchanged','passed':uv_hash()==before_uv},{'name':'native generated input exact bytes','passed':sha(GENERATED)==GENERATED_SHA and sha(generated)==GENERATED_SHA}]
 report={'status':'BAKED_PENDING_IMAGE_REVIEW','pid':os.getpid(),'checks':checks,'geometry_hash':before_geo,'uv_hash':before_uv,'input_sha256':BASE_SHA,'generated_sha256':GENERATED_SHA,'baked_maps':bake_rows,'mapping':mapping,'scope':'material-only source, no GLB / Godot; not full physically measured PBR; clean liner and rubber from frozen v3, old mismatched normals removed'}
 scene.cycles.samples=32;scene.cycles.use_denoising=True;scene.render.resolution_x=1280;scene.render.resolution_y=1280;scene.render.resolution_percentage=100
 bpy.ops.wm.save_as_mainfile(filepath=str(blend),relative_remap=False)
 for image in bpy.data.images:
  if image.source=='FILE' and image.filepath:image.filepath=bpy.path.relpath(str(Path(bpy.path.abspath(image.filepath)).resolve()))
 bpy.ops.wm.save_as_mainfile(filepath=str(blend),relative_remap=False)
 (evid/'material_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 if not all(c['passed'] for c in checks):raise RuntimeError('Material-only preservation failed, saved evidence, no render.')
 bpy.ops.wm.open_mainfile(filepath=str(blend));scene=bpy.context.scene;loaded=[]
 for node in bpy.data.materials['CG_V4_BakedPBR'].node_tree.nodes:
  if node.type=='TEX_IMAGE' and node.label in outputs:
   im=node.image;path=Path(bpy.path.abspath(im.filepath)).resolve();assert path==outputs[node.label][1].resolve() and path.exists();assert sha(path)==next(row['sha256'] for row in bake_rows if row['role']==node.label);im.reload();assert tuple(im.size)==(2048,2048) and im.has_data
   loaded.append({'role':node.label,'resolved_path':str(path),'sha256':sha(path),'colorspace':im.colorspace_settings.name})
 assert len(loaded)==4 and geometry_hash()==before_geo and uv_hash()==before_uv
 report['reopened_images']=loaded
 if args.render:
  path=evid/'clinic_gravity_material_v4.png';scene.render.filepath=str(path);scene.render.image_settings.file_format='PNG';bpy.ops.render.render(write_still=True);report['image_sha256']=sha(path)
 report.update(status='SOURCE_RENDERED_PENDING_ACTUAL_VISUAL_REVIEW',blend_sha256=sha(blend),elapsed_seconds=time.time()-start)
 (evid/'material_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 print(json.dumps({'stage':'end','pid':os.getpid(),'seconds':time.time()-start}),flush=True)
if __name__=='__main__':main()
