"""Read actual GLB bytes without an engine or Blender runtime."""
from pathlib import Path
import json,struct,hashlib
ROOT=Path(__file__).resolve().parents[3];EVID=ROOT/'artifacts/v3/art/overpass';p=ROOT/'assets/v3/overpass/maintenance_overpass.glb'
raw=p.read_bytes();length=struct.unpack_from('<I',raw,12)[0];g=json.loads(raw[20:20+length]);blob=raw[28+length:]
def ident():return [[float(i==j) for j in range(4)] for i in range(4)]
def mul(a,b):return [[sum(a[i][k]*b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]
def trans(n):
 if 'matrix' in n:return [[n['matrix'][j*4+i] for j in range(4)] for i in range(4)]
 x,y,z,w=n.get('rotation',[0,0,0,1]);sc=n.get('scale',[1,1,1]);t=n.get('translation',[0,0,0]);m=[[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w),t[0]],[2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w),t[1]],[2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y),t[2]],[0,0,0,1]]
 for i in range(3):
  for j in range(3):m[i][j]*=sc[j]
 return m
worlds={};parents={}
def walk(i,parent):
 worlds[i]=mul(parent,trans(g['nodes'][i]))
 for c in g['nodes'][i].get('children',[]):parents[c]=i;walk(c,worlds[i])
for i in g['scenes'][g.get('scene',0)]['nodes']:walk(i,ident())
def floats(index):
 a=g['accessors'][index];b=g['bufferViews'][a['bufferView']];n={'VEC2':2,'VEC3':3,'VEC4':4}[a['type']];off=b.get('byteOffset',0)+a.get('byteOffset',0);stride=b.get('byteStride',4*n)
 return [struct.unpack_from('<'+'f'*n,blob,off+j*stride) for j in range(a['count'])]
nodes={};points=[];total=0;uv=True
for i,n in enumerate(g['nodes']):
 e={'parent':g['nodes'][parents[i]]['name'] if i in parents else None,'translation':n.get('translation',[0,0,0]),'rotation':n.get('rotation',[0,0,0,1]),'scale':n.get('scale',[1,1,1]),'world_position':[worlds[i][k][3] for k in range(3)]}
 if 'mesh' in n:
  e['triangles']=0;e['materials']=[];ps=[]
  for prim in g['meshes'][n['mesh']]['primitives']:
   c=g['accessors'][prim['indices']]['count']//3;e['triangles']+=c;total+=c;e['materials'].append(g['materials'][prim['material']]['name']);uv &= 'TEXCOORD_0' in prim['attributes']
   for xyz in floats(prim['attributes']['POSITION']):
    v=(*xyz,1);ps.append([sum(worlds[i][j][k]*v[k] for k in range(4)) for j in range(3)])
  e['bounds']={'min':[min(v[k] for v in ps) for k in range(3)],'max':[max(v[k] for v in ps) for k in range(3)]};points+=ps
 nodes[n['name']]=e
bounds={'min':[min(v[k] for v in points) for k in range(3)],'max':[max(v[k] for v in points) for k in range(3)]}
checks={'triangle_budget_12k_22k':12000<=total<=22000,'four_materials':len(g['materials'])==4,'four_meshes':len(g['meshes'])==4,'all_primitives_uv':uv,'all_images_embedded':all('bufferView' in im and 'uri' not in im for im in g['images']),'unique_names':len(nodes)==len(g['nodes']),'no_cameras':'cameras' not in g,'no_lights':'KHR_lights_punctual' not in g.get('extensions',{}),'no_baked_animation':'animations' not in g}
for n in ['MaintenanceOverpass','DeckPanels','SteelStructure','RailingsHardware','SafetyMarkings','DeckLanding','UnderpassEntry','UnderpassExit']:checks['node_'+n]=n in nodes
checks['identity_bases']=all(n['rotation']==[0,0,0,1] and n['scale']==[1,1,1] for n in nodes.values())
checks['exact_entity_bounds']=all(abs(a-b)<.003 for key,expected in [('min',[-17.5,-7.5,-3.5]),('max',[17.5,1.7,3.5])] for a,b in zip(bounds[key],expected))
checks['one_surface_per_mesh']=all(len(n['materials'])==1 for n in nodes.values() if 'materials' in n)
checks['single_uv0_per_primitive']=all([k for k in p['attributes'] if k.startswith('TEXCOORD_')]==['TEXCOORD_0'] for m in g['meshes'] for p in m['primitives'])
checks['base_color_selects_uv0']=all(m['pbrMetallicRoughness']['baseColorTexture'].get('texCoord',0)==0 for m in g['materials'])
checks['all_pbr_textures_select_uv0']=all(t.get('texCoord',0)==0 for m in g['materials'] for t in [m['pbrMetallicRoughness']['baseColorTexture'],m['pbrMetallicRoughness']['metallicRoughnessTexture'],m['normalTexture']])
checks['authored_uv_inset_bounds']=all(.005<=v<=.995 for m in g['meshes'] for p in m['primitives'] for xy in floats(p['attributes']['TEXCOORD_0']) for v in xy)
geometry_bytes=b''.join(blob[v.get('byteOffset',0):v.get('byteOffset',0)+v['byteLength']] for v in g['bufferViews'] if v.get('target') in [34962,34963])
r={'sha256':hashlib.sha256(raw).hexdigest(),'geometry_buffer_sha256':hashlib.sha256(geometry_bytes).hexdigest(),'bytes':len(raw),'triangles':total,'materials':len(g['materials']),'mesh_count':len(g['meshes']),'embedded_images':len(g['images']),'samplers':g.get('samplers',[]),'bounds_godot':bounds,'nodes':nodes,'checks':checks,'all_checks_pass':all(checks.values()),'scope':'GLB bytes and nodes, not engine collision or performance'}
(EVID/'glb_inspection.json').write_text(json.dumps(r,ensure_ascii=False,indent=2),encoding='utf-8');print(json.dumps({k:v for k,v in r.items() if k!='nodes'}));raise SystemExit(0 if r['all_checks_pass'] else 1)
