"""SOURCE DIRECTORY export only. Await root CPU2 grant. Never saves editing source.
Evaluated temporary copies -> five identity meshes -> embedded GLB -> raw readback.
"""
from pathlib import Path
import bpy,sys,json,hashlib,struct,time,os,collections
from mathutils import Matrix
SRC=Path(__file__).resolve().parent;sys.path.insert(0,str(SRC))
from contract import GROUPS,WORLD_PLACEMENT,classify
BASE=SRC.parent/'revision_v4/clinic_gravity_material_v4.blend'
BASE_SHA='f2e574f60c72a8763ecbf16b8253ff558eb7238d29e8f3f35ac311fd0daffa40'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def pos(v):return (float(v.x),float(v.z),float(-v.y))
def canon(tri):return min(tuple(tri),tuple(tri[1:]+tri[:1]),tuple(tri[2:]+tri[:2]))
def identity(m):return all(abs(m[i][j]-(1 if i==j else 0))<1e-8 for i in range(4) for j in range(4))
def mesh_triangles(mesh):
 mesh.calc_loop_triangles();return collections.Counter(canon([pos(mesh.vertices[i].co) for i in t.vertices]) for t in mesh.loop_triangles)
def bounds(points):return [[min(p[i] for p in points) for i in range(3)],[max(p[i] for p in points) for i in range(3)]]
def read_glb(path):
 data=path.read_bytes();magic,version,length=struct.unpack_from('<4sII',data,0);assert magic==b'glTF' and version==2 and length==len(data)
 offset=12;j=None;binary=None
 while offset<len(data):
  size,kind=struct.unpack_from('<I4s',data,offset);chunk=data[offset+8:offset+8+size];offset+=8+size
  if kind==b'JSON':j=json.loads(chunk.decode('utf-8'))
  if kind==b'BIN\0':binary=chunk
 assert j is not None and binary is not None
 def accessor(index):
  a=j['accessors'][index];v=j['bufferViews'][a['bufferView']];assert 'sparse' not in a
  c={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']];fmt={5121:'B',5123:'H',5125:'I',5126:'f'}[a['componentType']];size=struct.calcsize('<'+fmt*c);start=v.get('byteOffset',0)+a.get('byteOffset',0);stride=v.get('byteStride',size)
  return [struct.unpack_from('<'+fmt*c,binary,start+i*stride) for i in range(a['count'])]
 parsed={};allpos=[]
 for mesh in j['meshes']:
  tris=collections.Counter();surfaces=[];points=[]
  for pr in mesh['primitives']:
   assert pr.get('mode',4)==4 and 'indices' in pr
   ps=accessor(pr['attributes']['POSITION']);ix=[x[0] for x in accessor(pr['indices'])];assert len(ix)%3==0
   tris.update(canon([ps[ix[i]],ps[ix[i+1]],ps[ix[i+2]]]) for i in range(0,len(ix),3));points+=ps
   surfaces.append({'triangles':len(ix)//3,'material':j['materials'][pr['material']]['name'],'attributes':list(pr['attributes'])})
  parsed[mesh['name']]={'triangles':tris,'bounds':bounds(points),'surfaces':surfaces};allpos+=points
 return j,parsed,bounds(allpos)
def main():
 start=time.time();out=SRC/'clinic_gravity_v4.glb';assert not out.exists(),'Do not overwrite delivered bytes.';assert sha(BASE)==BASE_SHA
 print(json.dumps({'stage':'start','pid':os.getpid(),'source_only':True,'threads':2}),flush=True)
 bpy.ops.wm.open_mainfile(filepath=str(BASE));scene=bpy.context.scene
 source=bpy.data.collections['Editable_ClinicCistern_A'];groups={k:[] for k in GROUPS}
 for o in source.objects:
  if o.type!='MESH' or o.hide_render or o.get('exclude_export',False):continue
  groups[classify(o.name,o.get('runtime_group'))].append(o)
 assert all(groups.values())
 source_map={k:[o.name for o in values] for k,values in groups.items()}
 active_materials={m for values in groups.values() for o in values for m in o.data.materials}
 assert {m.name for m in active_materials}=={'CG_V4_BakedPBR','CG_V3_ClearObservationPane'}
 # Node-only composition is provenance, never an exported material.
 for m in active_materials:
  assert m.use_nodes
  assert all(n.type in ('BSDF_PRINCIPLED','OUTPUT_MATERIAL','UVMAP','TEX_IMAGE','NORMAL_MAP') for n in m.node_tree.nodes)
 texture_checks=[]
 for n in bpy.data.materials['CG_V4_BakedPBR'].node_tree.nodes:
  if n.type=='TEX_IMAGE':
   path=Path(bpy.path.abspath(n.image.filepath)).resolve();assert path.exists();n.image.reload();assert tuple(n.image.size)==(2048,2048)
   texture_checks.append({'role':n.label,'path':str(path),'sha256':sha(path),'colorspace':n.image.colorspace_settings.name})
 assert len(texture_checks)==4
 export_collection=bpy.data.collections.new('TEMP_DELIVERY_EXPORT');scene.collection.children.link(export_collection)
 root=bpy.data.objects.new('ClinicGravityAssembly',None);export_collection.objects.link(root);root.matrix_world=Matrix.Identity(4)
 copies=[];expected={};group_reports={};dg=bpy.context.evaluated_depsgraph_get()
 for group,objects in groups.items():
  fragments=[]
  for o in objects:
   mesh=bpy.data.meshes.new_from_object(o.evaluated_get(dg),preserve_all_data_layers=True,depsgraph=dg)
   mesh.transform(o.matrix_world);mesh.update();c=bpy.data.objects.new('TMP_'+o.name,mesh);export_collection.objects.link(c);c.matrix_world=Matrix.Identity(4);fragments.append(c)
  bpy.ops.object.select_all(action='DESELECT')
  for c in fragments:c.select_set(True)
  bpy.context.view_layer.objects.active=fragments[0]
  if len(fragments)>1:bpy.ops.object.join()
  c=bpy.context.object;c.name=group;c.data.name=group;c.parent=root;c.matrix_basis=Matrix.Identity(4);assert identity(c.matrix_world)
  # Remove unused slots if exporter would otherwise retain obsolete material references.
  used={f.material_index for f in c.data.polygons};assert len(used)==1,group+' should have one material'
  mat=c.data.materials[next(iter(used))];c.data.materials.clear();c.data.materials.append(mat)
  for f in c.data.polygons:f.material_index=0
  c.data.calc_loop_triangles();expected[group]=mesh_triangles(c.data);group_reports[group]={'source_count':len(objects),'source_objects':source_map[group],'triangles':len(c.data.loop_triangles),'bounds_local_godot':bounds([pos(v.co) for v in c.data.vertices]),'material':mat.name,'transform':'identity'};copies.append(c)
 # Keep the editing marker but avoid Blender's global .001 object-name suffix.
 original_marker=bpy.data.objects['SourceWaterBase'];assert original_marker.location.length<1e-8;original_marker.name='EDITING_ONLY_SourceWaterBase'
 marker=bpy.data.objects.new('SourceWaterBase',None);export_collection.objects.link(marker);marker.parent=root;marker.matrix_basis=Matrix.Identity(4)
 bpy.ops.object.select_all(action='DESELECT')
 for o in copies+[root,marker]:o.select_set(True)
 bpy.context.view_layer.objects.active=root
 bpy.ops.export_scene.gltf(filepath=str(out),export_format='GLB',use_selection=True,export_apply=True,export_yup=True,export_texcoords=True,export_normals=True,export_materials='EXPORT',export_cameras=False,export_lights=False,export_animations=False,export_extras=True)
 j,actual,total_bounds=read_glb(out)
 checks=[]
 def check(n,ok,d=None):checks.append({'name':n,'passed':bool(ok),'detail':d})
 check('exact five mesh names',set(actual)==set(GROUPS),list(actual))
 check('one surface per mesh',all(len(actual[k]['surfaces'])==1 for k in GROUPS))
 for group in GROUPS:check(group+' raw GLB oriented float32 triangle multiset equals evaluated temporary source',actual[group]['triangles']==expected[group],{'source':sum(expected[group].values()),'raw_glb':sum(actual[group]['triangles'].values())})
 check('node names only contract',set(n['name'] for n in j['nodes'])==set(GROUPS)|{'ClinicGravityAssembly','SourceWaterBase'},[n['name'] for n in j['nodes']])
 def node_identity(n):
  return n.get('translation',[0,0,0])==[0,0,0] and n.get('rotation',[0,0,0,1])==[0,0,0,1] and n.get('scale',[1,1,1])==[1,1,1] and n.get('matrix',[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1])==[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]
 check('all actual GLB node transforms identity',all(node_identity(n) for n in j['nodes']))
 check('no external images',all('bufferView' in i and 'uri' not in i for i in j.get('images',[])))
 check('no animations cameras lights',not j.get('animations') and not j.get('cameras') and not j.get('extensions',{}).get('KHR_lights_punctual'))
 window=next(m for m in j['materials'] if m['name']=='CG_V3_ClearObservationPane');check('window independent alpha blend',window.get('alphaMode')=='BLEND' and 0<window['pbrMetallicRoughness']['baseColorFactor'][3]<.1)
 pbr=next(m for m in j['materials'] if m['name']=='CG_V4_BakedPBR');check('opaque material base normal and packed rough/metal textures',all(k in pbr['pbrMetallicRoughness'] for k in ('baseColorTexture','metallicRoughnessTexture')) and 'normalTexture' in pbr)
 check('editing source bytes unchanged',sha(BASE)==BASE_SHA)
 report={'status':'SOURCE_GLB_READY_FOR_ROOT_IMPORT' if all(x['passed'] for x in checks) else 'FAILED_RETAINED_NOT_FOR_INTEGRATION','checks':checks,'source_sha256':BASE_SHA,'glb_sha256':sha(out),'glb_bytes':out.stat().st_size,'world_placement':WORLD_PLACEMENT,'local_bounds_godot':total_bounds,'mesh_groups':group_reports,'raw_glb_meshes':{k:{a:b for a,b in v.items() if a!='triangles'} for k,v in actual.items()},'textures':texture_checks,'embedded_image_count':len(j.get('images',[])),'material_count':len(j['materials']),'triangles':sum(sum(v['triangles'].values()) for v in actual.values()),'elapsed_seconds':time.time()-start,'scope':'Source directory delivery only. No editing source save, no water/preview/studio/hidden source export, no Godot or runtime art/physics acceptance.'}
 (SRC/'delivery_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 print(json.dumps({'stage':'end','pid':os.getpid(),'seconds':time.time()-start,'failed':sum(not x['passed'] for x in checks)}),flush=True)
 if not all(x['passed'] for x in checks):raise RuntimeError('Strict export readback failed; retain artifact, do not integrate.')
if __name__=='__main__':main()
