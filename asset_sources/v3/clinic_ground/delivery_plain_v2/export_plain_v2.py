"""Explicit shared GLB from frozen editable source. No rebake/save/render."""
from pathlib import Path
import bpy, sys, json, hashlib, collections, time, os
from mathutils import Matrix
HERE=Path(__file__).resolve().parent
sys.dont_write_bytecode=True
sys.path.insert(0,str(HERE.parent/'delivery_p2'))
from read_glb import read, canon, bounds, node_identity, f32
from contract import TEXTURES, MATERIAL
SOURCE=HERE.parent/'plain_v2/clinic_ground_plain_v2.blend'
SOURCE_SHA='02ce8caa0abf3e044d1a4e7681c84864acecc7fcb69bb54c90a6e5ad7d67e198'
OUT=HERE/'clinic_ground_plain_v2.glb'
VARIANTS={'A':('PlainA',680),'B':('PlainB',740),'P2_W':('PlainP2West',680)}
ROOT='ClinicGroundPlainVariants'
BOUNDS=[[-3.,-.18000000715255737,-3.],[3.,0.,3.]]

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def gd(v):return (float(v.x),float(v.z),float(-v.y))
def signatures(mesh):
 mesh.calc_loop_triangles();uv=mesh.uv_layers['SurfaceUV'];tr=collections.Counter();cu=collections.Counter()
 for t in mesh.loop_triangles:
  ps=[gd(mesh.vertices[i].co) for i in t.vertices]
  us=[(f32(uv.data[i].uv.x),f32(1.0-uv.data[i].uv.y)) for i in t.loops]
  tr[canon(ps)]+=1;cu[canon([ps[i]+us[i] for i in range(3)])]+=1
 return tr,cu
def frozen_inventory():
 result={}
 for name in ['p2','delivery_p2','plain_v1','plain_v2']:
  for p in sorted((HERE.parent/name).rglob('*')):
   if p.is_file():result[str(p.relative_to(HERE.parent))]={'bytes':p.stat().st_size,'sha256':sha(p)}
 return result
def edge_widths(raw):
 result={}
 for edge,axis,side in [('west',0,-1),('east',0,1),('south',2,-1),('north',2,1)]:
  pts=[p for tri in raw['triangles'] for p in tri if all(side*q[axis]>2.9 for q in tri)]
  bb=bounds(pts);result[edge]=bb[1][axis]-bb[0][axis]
 return result
def adjacency(widths):
 # Integer quarter turns avoid approximate rotation or naming assumptions.
 vectors={'west':(-1,0),'east':(1,0),'south':(0,-1),'north':(0,1)}
 reverse={v:k for k,v in vectors.items()}
 tiles=[('P2',-19,15,0),('P2_W',-13,15,0),('B',-7,15,0),('P2_W',-19,21,-1),('B',-13,21,0),('A',-7,21,0)]
 out=[];records=[]
 for label,x,z,q in tiles:
  local={k:0. for k in vectors} if label=='P2' else widths[label]
  world={}
  for side,(dx,dz) in vectors.items():
   # Y=-90deg gives (x,z)->(-z,x).
   if q==-1:dx,dz=-dz,dx
   world[reverse[(dx,dz)]]=local[side]
  out.append({'variant':label,'world_xz':[x,z],'rotation_y_degrees':90*q,'world_edge_widths_m':world})
 for i,a in enumerate(out):
  for j,b in enumerate(out[i+1:],i+1):
   dx=b['world_xz'][0]-a['world_xz'][0];dz=b['world_xz'][1]-a['world_xz'][1]
   if (dx,dz)==(6,0):s,t='east','west'
   elif (dx,dz)==(0,6):s,t='north','south'
   else:continue
   w=a['world_edge_widths_m'][s]+b['world_edge_widths_m'][t]
   records.append({'tile_indices':[i,j],'edges':[s,t],'seal_width_m':w,'expected_m':.02,'passed':abs(w-.02)<5e-7})
 return {'tiles':out,'internal_seams':records,'scope':'Actual exported Sealant triangle bounds; proposed integer transforms only, not Godot physical assembly. Exterior boundary dressing not covered.'}

def main():
 start=time.time();assert not OUT.exists(),'Do not overwrite delivery.'
 assert sha(SOURCE)==SOURCE_SHA
 before=frozen_inventory()
 (HERE/'frozen_inputs_before.json').write_text(json.dumps(before,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 print(json.dumps({'stage':'start','pid':os.getpid(),'threads':2,'no_render_rebake':True}),flush=True)
 bpy.ops.wm.open_mainfile(filepath=str(SOURCE));scene=bpy.context.scene
 scene.render.threads_mode='FIXED';scene.render.threads=2;scene.cycles.device='CPU'
 for label in VARIANTS:
  coll=bpy.data.collections['Editable_PlainV2_'+label];coll.hide_viewport=False;coll.hide_render=False
 bpy.context.view_layer.update()
 mat=bpy.data.materials[MATERIAL];assert mat.use_nodes
 assert all(n.type in {'BSDF_PRINCIPLED','OUTPUT_MATERIAL','UVMAP','TEX_IMAGE','NORMAL_MAP'} for n in mat.node_tree.nodes)
 output=next(n for n in mat.node_tree.nodes if n.type=='OUTPUT_MATERIAL');bs=output.inputs['Surface'].links[0].from_node
 assert bs.type=='BSDF_PRINCIPLED' and not bs.inputs['Emission Color'].is_linked and not bs.inputs['Emission Strength'].is_linked
 assert all(float(c)*float(bs.inputs['Emission Strength'].default_value)==0 for c in bs.inputs['Emission Color'].default_value[:3])
 assert not bs.inputs['Alpha'].is_linked and bs.inputs['Alpha'].default_value==1.0
 textures=[]
 for n in mat.node_tree.nodes:
  if n.type!='TEX_IMAGE':continue
  expected,space=TEXTURES[n.label];im=n.image;p=Path(bpy.path.abspath(im.filepath)).resolve()
  assert sha(p)==expected and im.colorspace_settings.name==space
  im.reload();assert len(list(im.pixels[:4]))==4 and im.has_data and tuple(im.size)==(2048,2048)
  links=n.inputs['Vector'].links;assert len(links)==1 and links[0].from_node.type=='UVMAP' and links[0].from_node.uv_map=='SurfaceUV'
  textures.append({'role':n.label,'path':str(p),'sha256':sha(p),'colorspace':space})
 assert len(textures)==4
 coll=bpy.data.collections.new('TEMP_EXPORT_ONLY');scene.collection.children.link(coll)
 def empty(name,parent=None):
  o=bpy.data.objects.new(name,None);coll.objects.link(o);o.parent=parent;o.matrix_basis=Matrix.Identity(4);return o
 root=empty(ROOT);selected=[root];expected={};groups={};parents={}
 dg=bpy.context.evaluated_depsgraph_get()
 for label,(rootname,target_tri) in VARIANTS.items():
  src=[o for o in bpy.data.objects if o.type=='MESH' and o.get('variant')==label]
  assert len(src)==15
  parent=empty(rootname,root);selected.append(parent)
  group_src={'Concrete':[o for o in src if 'Seal_' not in o.name], 'Sealant':[o for o in src if 'Seal_' in o.name]}
  assert len(group_src['Concrete'])==8 and len(group_src['Sealant'])==7
  subtotal=0
  for suffix,objects in group_src.items():
   name=label+'_'+suffix;fragments=[];source_tri=collections.Counter();source_uv=collections.Counter()
   for o in sorted(objects,key=lambda x:x.name):
    me=bpy.data.meshes.new_from_object(o.evaluated_get(dg),preserve_all_data_layers=True,depsgraph=dg)
    me.transform(o.matrix_world);me.update()
    assert len(me.uv_layers)==1 and me.uv_layers.active.name=='SurfaceUV' and me.uv_layers.active.active_render
    tr,uv=signatures(me);source_tri.update(tr);source_uv.update(uv)
    c=bpy.data.objects.new('TEMP_'+o.name,me);coll.objects.link(c);fragments.append(c)
   bpy.ops.object.select_all(action='DESELECT')
   for c in fragments:c.select_set(True)
   bpy.context.view_layer.objects.active=fragments[0];bpy.ops.object.join()
   c=bpy.context.object;c.name=name;c.data.name=name;c.parent=parent;c.matrix_basis=Matrix.Identity(4)
   c.data.materials.clear();c.data.materials.append(mat)
   for face in c.data.polygons:face.material_index=0
   tr,uv=signatures(c.data);assert tr==source_tri and uv==source_uv,'Merge changed source geometry/UV.'
   expected[name]=(tr,uv);subtotal+=sum(tr.values());parents[name]=rootname
   groups[name]={'source_names':sorted(o.name for o in objects),'source_pieces':len(objects),'triangles':sum(tr.values()),'bounds':bounds([gd(v.co) for v in c.data.vertices]),'parent':rootname}
   selected.append(c)
  assert subtotal==target_tri
 (HERE/'source_preflight.json').write_text(json.dumps({'source_sha256':SOURCE_SHA,'textures':textures,'groups':groups,'no_rebake':True},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 bpy.ops.object.select_all(action='DESELECT')
 for o in selected:o.select_set(True)
 bpy.context.view_layer.objects.active=root
 bpy.ops.export_scene.gltf(filepath=str(OUT),export_format='GLB',use_selection=True,export_apply=True,export_yup=True,export_texcoords=True,export_normals=True,export_materials='EXPORT',export_cameras=False,export_lights=False,export_animations=False,export_extras=False)
 j,actual,bb,images=read(OUT);checks=[]
 def check(name,ok,detail=None):checks.append({'name':name,'passed':bool(ok),'detail':detail})
 check('six exact mesh names',set(actual)==set(groups),list(actual))
 check('total 2100 source triangles',sum(sum(a['triangles'].values()) for a in actual.values())==2100)
 for name in groups:
  a=actual[name]
  check(name+' oriented float32 source triangle multiset',a['triangles']==expected[name][0])
  check(name+' oriented float32 per-corner source UV0',a['corner_uv']==expected[name][1])
  check(name+' single shared material surface',len(a['surfaces'])==1 and a['surfaces'][0]['material']==MATERIAL)
  check(name+' UV0 only finite unit normals',all(set(s['attributes'])=={'POSITION','NORMAL','TEXCOORD_0'} and s['normals_unit'] for s in a['surfaces']))
  check(name+' bounded atlas UV',all(all(-1e-6<=v<=1.000001 for row in s['uv0_bounds'] for v in row) for s in a['surfaces']))
 for label,(rootname,target_tri) in VARIANTS.items():
  items=[actual[label+'_'+s] for s in ['Concrete','Sealant']]
  check(label+' exact triangles',sum(sum(a['triangles'].values()) for a in items)==target_tri)
  check(label+' exact bounds',bounds([p for a in items for t in a['triangles'] for p in t])==BOUNDS)
  n=next(n for n in j['nodes'] if n['name']==rootname)
  check(label+' direct concrete/sealant children',{j['nodes'][i]['name'] for i in n.get('children',[])}=={label+'_Concrete',label+'_Sealant'})
 check('all actual transforms identity',all(node_identity(n) for n in j['nodes']))
 rootix=next(i for i,n in enumerate(j['nodes']) if n['name']==ROOT)
 check('single scene root and three direct variant roots',j['scenes'][j.get('scene',0)]['nodes']==[rootix] and {j['nodes'][i]['name'] for i in j['nodes'][rootix].get('children',[])}=={v[0] for v in VARIANTS.values()})
 check('only ten contract nodes',len(j['nodes'])==10 and {n['name'] for n in j['nodes']}=={ROOT}|{v[0] for v in VARIANTS.values()}|set(groups))
 check('one shared opaque material',len(j['materials'])==1 and j['materials'][0]['name']==MATERIAL and j['materials'][0].get('alphaMode','OPAQUE')=='OPAQUE')
 m=j['materials'][0];pbr=m['pbrMetallicRoughness'];roles={'BaseColor':pbr.get('baseColorTexture'),'MetallicRoughness':pbr.get('metallicRoughnessTexture'),'Normal':m.get('normalTexture')}
 check('all PBR roles UV0',all(t is not None and t.get('texCoord',0)==0 for t in roles.values()))
 check('no emission/unlit','KHR_materials_unlit' not in m.get('extensions',{}) and m.get('emissiveFactor',[0,0,0])==[0,0,0] and 'emissiveTexture' not in m)
 check('only three shared embedded 2048 PNG',len(images)==3 and len(j['textures'])==3 and all(i['size']==[2048,2048] for i in images))
 mapped={role:images[j['textures'][tex['index']]['source']] for role,tex in roles.items()}
 check('unchanged BaseColor embedded bytes',mapped['BaseColor']['sha256']==TEXTURES['BaseColor'][0])
 check('unchanged Normal embedded bytes',mapped['Normal']['sha256']==TEXTURES['Normal'][0])
 check('native packed MR exactly equals prior P2 export',mapped['MetallicRoughness']['sha256']=='fbf75ebd885ddb02bbee30561e1a8a038c7f8b42df3048b090f4154071347901')
 check('no cameras/lights/animation/collision exports',not j.get('cameras') and not j.get('animations') and not j.get('extensions',{}).get('KHR_lights_punctual'))
 widths={label:edge_widths(actual[label+'_Sealant']) for label in VARIANTS}
 adj=adjacency(widths)
 check('all seven proposed adjacent seams are 20mm',len(adj['internal_seams'])==7 and all(s['passed'] for s in adj['internal_seams']),adj)
 after=frozen_inventory();check('all frozen source/texture/helper bytes unchanged',before==after)
 (HERE/'adjacency_report.json').write_text(json.dumps(adj,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 report={'status':'READY_FOR_ROOT_IMPORT' if all(c['passed'] for c in checks) else 'FAILED_RETAINED','checks':checks,'glb_path':str(OUT),'glb_sha256':sha(OUT),'glb_bytes':OUT.stat().st_size,'source_sha256':SOURCE_SHA,'triangles':2100,'bounds_local_godot':bb,'group_contract':groups,'raw_groups':{k:{a:b for a,b in v.items() if a not in {'triangles','corner_uv'}} for k,v in actual.items()},'material':m,'images':images,'texture_role_images':mapped,'source_textures':textures,'edge_widths_m':widths,'elapsed_seconds':time.time()-start,'scope':'Shared source-only GLB delivery. Source/PBR bytes unchanged; no render/rebake/Godot/runtime write. Root selects a single named variant subtree; do not display three coincident variants. No colliders: existing Y0 conservative ground collision remains root responsibility.'}
 (HERE/'delivery_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 print(json.dumps({'stage':'end','pid':os.getpid(),'seconds':time.time()-start,'checks':len(checks),'failed':sum(not c['passed'] for c in checks),'glb_sha256':sha(OUT)}),flush=True)
 assert all(c['passed'] for c in checks),'Binary validation failed; retained evidence, no integration.'

if __name__=='__main__':main()
