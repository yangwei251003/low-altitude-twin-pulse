"""Await root CPU2. Export evaluated copies only, no save/rebake/render/Godot."""
from pathlib import Path
import bpy,sys,json,hashlib,collections,time,os
from mathutils import Matrix
HERE=Path(__file__).resolve().parent;sys.dont_write_bytecode=True;sys.path.insert(0,str(HERE))
from contract import SOURCE_SHA,ROOT_NAME,MATERIAL,GROUPS,TOTAL_TRIANGLES,BOUNDS,TEXTURES,SUGGESTED_WORLD_PLACEMENT
from read_glb import read,canon,bounds,node_identity,f32
BASE=HERE.parent/'p2/clinic_ground_p2.blend'

def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def pos(v):return (float(v.x),float(v.z),float(-v.y))
def identity(m):return all(abs(m[i][j]-(1 if i==j else 0))<1e-8 for i in range(4) for j in range(4))
def signatures(mesh):
 mesh.calc_loop_triangles();uv=mesh.uv_layers['SurfaceUV'];tris=collections.Counter();corners=collections.Counter()
 for tri in mesh.loop_triangles:
  ps=[pos(mesh.vertices[i].co) for i in tri.vertices]
  uvs=[(f32(uv.data[i].uv.x),f32(1.0-uv.data[i].uv.y)) for i in tri.loops]
  tris[canon(ps)]+=1;corners[canon([ps[i]+uvs[i] for i in range(3)])]+=1
 return tris,corners

def main():
 start=time.time();out=HERE/'clinic_ground_p2.glb';assert not out.exists(),'Do not overwrite delivery.'
 assert sha(BASE)==SOURCE_SHA
 print(json.dumps({'stage':'start','pid':os.getpid(),'threads':2,'source_only':True}),flush=True)
 bpy.ops.wm.open_mainfile(filepath=str(BASE));scene=bpy.context.scene;scene.render.threads_mode='FIXED';scene.render.threads=2;scene.cycles.device='CPU'
 pieces=[o for o in bpy.data.objects if o.type=='MESH' and o.get('editable_piece',False)]
 assert len(pieces)==77 and all(not o.hide_render for o in pieces)
 group_map={info['source_group']:name for name,info in GROUPS.items()};groups={name:[] for name in GROUPS}
 for o in pieces:
  assert o.get('runtime_group') in group_map,o.name
  groups[group_map[o['runtime_group']]].append(o)
 assert {m.name for o in pieces for m in o.data.materials}=={MATERIAL}
 mat=bpy.data.materials[MATERIAL];assert mat.use_nodes
 assert all(n.type in {'BSDF_PRINCIPLED','OUTPUT_MATERIAL','UVMAP','TEX_IMAGE','NORMAL_MAP'} for n in mat.node_tree.nodes)
 output=next(n for n in mat.node_tree.nodes if n.type=='OUTPUT_MATERIAL');bs=output.inputs['Surface'].links[0].from_node
 assert bs.type=='BSDF_PRINCIPLED' and not bs.inputs['Emission Color'].is_linked and not bs.inputs['Emission Strength'].is_linked
 assert all(float(c)*float(bs.inputs['Emission Strength'].default_value)==0 for c in bs.inputs['Emission Color'].default_value[:3])
 texture_checks=[]
 for n in mat.node_tree.nodes:
  if n.type!='TEX_IMAGE':continue
  expected,space=TEXTURES[n.label];im=n.image;path=Path(bpy.path.abspath(im.filepath)).resolve()
  assert path.is_file() and sha(path)==expected and im.colorspace_settings.name==space
  im.reload();pixel=list(im.pixels[:4]);assert len(pixel)==4 and im.has_data and tuple(im.size)==(2048,2048)
  incoming=n.inputs['Vector'].links;assert len(incoming)==1 and incoming[0].from_node.type=='UVMAP' and incoming[0].from_node.uv_map=='SurfaceUV'
  texture_checks.append({'role':n.label,'path':str(path),'sha256':sha(path),'colorspace':space})
 assert len(texture_checks)==4
 old_root=bpy.data.objects.get(ROOT_NAME)
 if old_root:old_root.name='EDITING_ONLY_'+ROOT_NAME
 coll=bpy.data.collections.new('TEMP_EXPORT_ONLY');scene.collection.children.link(coll)
 root=bpy.data.objects.new(ROOT_NAME,None);coll.objects.link(root);root.matrix_world=Matrix.Identity(4)
 dg=bpy.context.evaluated_depsgraph_get();copies=[];expected={};group_report={}
 for name,objects in groups.items():
  assert len(objects)==GROUPS[name]['pieces'];fragments=[];source_tri=collections.Counter();source_uv=collections.Counter()
  for o in sorted(objects,key=lambda x:x.name):
   mesh=bpy.data.meshes.new_from_object(o.evaluated_get(dg),preserve_all_data_layers=True,depsgraph=dg)
   mesh.transform(o.matrix_world);mesh.update()
   assert len(mesh.uv_layers)==1 and mesh.uv_layers.active.name=='SurfaceUV' and mesh.uv_layers['SurfaceUV'].active_render
   tr,uv=signatures(mesh);source_tri.update(tr);source_uv.update(uv)
   c=bpy.data.objects.new('TEMP_'+o.name,mesh);coll.objects.link(c);c.matrix_world=Matrix.Identity(4);fragments.append(c)
  bpy.ops.object.select_all(action='DESELECT')
  for c in fragments:c.select_set(True)
  bpy.context.view_layer.objects.active=fragments[0];bpy.ops.object.join()
  c=bpy.context.object;c.name=name;c.data.name=name;c.parent=root;c.matrix_basis=Matrix.Identity(4);assert identity(c.matrix_world)
  c.data.materials.clear();c.data.materials.append(mat)
  for face in c.data.polygons:face.material_index=0
  tr,uv=signatures(c.data);assert tr==source_tri and uv==source_uv,'Merge changed source triangle/UV multiset.'
  assert sum(tr.values())==GROUPS[name]['triangles']
  expected[name]=(tr,uv)
  group_report[name]={'pieces':len(objects),'source_names':sorted(o.name for o in objects),'triangles':sum(tr.values()),'bounds':bounds([pos(v.co) for v in c.data.vertices]),'transform':'identity','uv':'SurfaceUV / first and only layer','material':MATERIAL}
  copies.append(c)
 (HERE/'source_preflight.json').write_text(json.dumps({'source_sha256':SOURCE_SHA,'textures':texture_checks,'groups':group_report,'no_rebake':True},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 bpy.ops.object.select_all(action='DESELECT')
 for o in [root]+copies:o.select_set(True)
 bpy.context.view_layer.objects.active=root
 # Blender's native glTF exporter packs the existing roughness/metallic maps into
 # G/B automatically. No custom pixel editing, author rebake or new material atlas.
 bpy.ops.export_scene.gltf(filepath=str(out),export_format='GLB',use_selection=True,export_apply=True,export_yup=True,export_texcoords=True,export_normals=True,export_materials='EXPORT',export_cameras=False,export_lights=False,export_animations=False,export_extras=False)
 j,actual,total_bounds,images=read(out);checks=[]
 def check(name,ok,detail=None):checks.append({'name':name,'passed':bool(ok),'detail':detail})
 check('exact two mesh names',set(actual)==set(GROUPS),list(actual))
 check('exact source triangle count',sum(sum(a['triangles'].values()) for a in actual.values())==TOTAL_TRIANGLES)
 for name in GROUPS:
  check(name+' raw oriented float32 triangle multiset equals unmerged source',actual[name]['triangles']==expected[name][0])
  check(name+' raw oriented per-corner UV0 matches source with glTF V flip',actual[name]['corner_uv']==expected[name][1])
  check(name+' one surface shared PBR',len(actual[name]['surfaces'])==1 and actual[name]['surfaces'][0]['material']==MATERIAL)
  check(name+' explicit UV0 only and finite unit normals',all(set(s['attributes'])=={'POSITION','NORMAL','TEXCOORD_0'} and s['normals_unit'] for s in actual[name]['surfaces']))
  check(name+' UV0 remains inside atlas',all(all(-1e-6<=v<=1.000001 for row in s['uv0_bounds'] for v in row) for s in actual[name]['surfaces']))
 check('exact 6x6x0.18 evaluated source bounds',total_bounds==[list(x) for x in BOUNDS],total_bounds)
 check('only contract nodes',set(n['name'] for n in j['nodes'])==set(GROUPS)|{ROOT_NAME})
 check('all actual node transforms identity',all(node_identity(n) for n in j['nodes']))
 root_index=next(i for i,n in enumerate(j['nodes']) if n['name']==ROOT_NAME)
 check('single scene root and exactly two direct mesh children',j['scenes'][j.get('scene',0)]['nodes']==[root_index] and {j['nodes'][i]['name'] for i in j['nodes'][root_index].get('children',[])}==set(GROUPS))
 check('one opaque standard material',len(j['materials'])==1 and j['materials'][0]['name']==MATERIAL and j['materials'][0].get('alphaMode','OPAQUE')=='OPAQUE')
 m=j['materials'][0];pbr=m['pbrMetallicRoughness'];roles={'BaseColor':pbr.get('baseColorTexture'),'MetallicRoughness':pbr.get('metallicRoughnessTexture'),'Normal':m.get('normalTexture')}
 check('three native PBR texture roles present and use UV0',all(t is not None and t.get('texCoord',0)==0 for t in roles.values()),roles)
 check('not unlit and no emission','KHR_materials_unlit' not in m.get('extensions',{}) and m.get('emissiveFactor',[0,0,0])==[0,0,0] and 'emissiveTexture' not in m)
 check('three embedded 2048 PNGs only',len(images)==3 and all(x['size']==[2048,2048] for x in images),images)
 mapped={}
 for role,texture in roles.items():
  if texture is not None:mapped[role]=images[j['textures'][texture['index']]['source']]
 check('basecolor embedded bytes preserve existing bake',mapped.get('BaseColor',{}).get('sha256')==TEXTURES['BaseColor'][0])
 check('normal embedded bytes preserve existing bake',mapped.get('Normal',{}).get('sha256')==TEXTURES['Normal'][0])
 check('no cameras lights animations collision or preview exports',not j.get('cameras') and not j.get('animations') and not j.get('extensions',{}).get('KHR_lights_punctual') and len(j['nodes'])==3)
 check('P2 editable source bytes unchanged',sha(BASE)==SOURCE_SHA)
 check('all four source PBR files unchanged',all(sha(Path(r['path']))==r['sha256'] for r in texture_checks))
 report={'status':'SOURCE_GLB_READY_FOR_ROOT_IMPORT' if all(c['passed'] for c in checks) else 'FAILED_RETAINED_NOT_FOR_INTEGRATION',
  'checks':checks,'source_sha256':SOURCE_SHA,'glb_sha256':sha(out),'glb_bytes':out.stat().st_size,'triangles':sum(sum(a['triangles'].values()) for a in actual.values()),
  'bounds_local_godot':total_bounds,'group_contract':group_report,'raw_glb_groups':{k:{a:b for a,b in v.items() if a not in {'triangles','corner_uv'}} for k,v in actual.items()},
  'material':m,'embedded_images':images,'texture_role_images':mapped,'source_textures':texture_checks,'elapsed_seconds':time.time()-start,
  'collision_contract':'No collider exported. Root retains conservative Y0 Ground collision for 20mm seals and shallow 75mm drain. No physical drainage network.',
  'suggested_world_placement_not_integrated':SUGGESTED_WORLD_PLACEMENT,'scope':'Source-directory delivery only; no editing source save/rebake/render/Godot. Old visible ground top must be cut, never coplanar overlaid.'}
 (HERE/'delivery_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 print(json.dumps({'stage':'end','pid':os.getpid(),'seconds':time.time()-start,'checks':len(checks),'failed':sum(not c['passed'] for c in checks)}),flush=True)
 if not all(c['passed'] for c in checks):raise RuntimeError('Binary readback failed; retain output, do not integrate.')

if __name__=='__main__':main()
