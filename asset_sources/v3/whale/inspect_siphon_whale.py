"""Inspect exported bytes independently; no Godot invocation."""
from pathlib import Path
import json,struct,hashlib
ROOT=Path(__file__).resolve().parents[3];EVID=ROOT/'artifacts/v3/art/whale';p=ROOT/'assets/v3/whale/siphon_whale.glb'
raw=p.read_bytes();length=struct.unpack_from('<I',raw,12)[0];g=json.loads(raw[20:20+length]);blob=raw[28+length:]
def ident():return [[float(i==j) for j in range(4)] for i in range(4)]
def multiply(a,b):return [[sum(a[i][k]*b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]
def transform(n):
 if 'matrix' in n:return [[n['matrix'][j*4+i] for j in range(4)] for i in range(4)]
 x,y,z,w=n.get('rotation',[0,0,0,1]);sx,sy,sz=n.get('scale',[1,1,1]);t=n.get('translation',[0,0,0])
 m=[[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w),t[0]],[2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w),t[1]],[2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y),t[2]],[0,0,0,1]]
 for i in range(3):
  for j,s in enumerate([sx,sy,sz]):m[i][j]*=s
 return m
worlds={};parents={}
def walk(i,parent):
 worlds[i]=multiply(parent,transform(g['nodes'][i]))
 for c in g['nodes'][i].get('children',[]):parents[c]=i;walk(c,worlds[i])
for i in g['scenes'][g.get('scene',0)]['nodes']:walk(i,ident())
def floats(index):
 a=g['accessors'][index];b=g['bufferViews'][a['bufferView']];n={'VEC2':2,'VEC3':3,'VEC4':4}[a['type']];off=b.get('byteOffset',0)+a.get('byteOffset',0);stride=b.get('byteStride',4*n)
 return [struct.unpack_from('<'+'f'*n,blob,off+j*stride) for j in range(a['count'])]
nodes={};points=[];triangles=0;uv=True
for i,n in enumerate(g['nodes']):
 entry={'translation':n.get('translation',[0,0,0]),'world_translation':[worlds[i][k][3] for k in range(3)],'rotation':n.get('rotation',[0,0,0,1]),'scale':n.get('scale',[1,1,1]),'parent':g['nodes'][parents[i]]['name'] if i in parents else None,'children':[g['nodes'][j]['name'] for j in n.get('children',[])],'extras':n.get('extras',{})}
 if 'mesh' in n:
  entry['materials']=[];entry['triangles']=0;np=[]
  for prim in g['meshes'][n['mesh']]['primitives']:
   count=g['accessors'][prim['indices']]['count']//3;entry['triangles']+=count;triangles+=count;uv &= 'TEXCOORD_0' in prim['attributes'];entry['materials'].append(g['materials'][prim['material']]['name'])
   for x,y,z in floats(prim['attributes']['POSITION']):
    v=[x,y,z,1];np.append([sum(worlds[i][j][k]*v[k] for k in range(4)) for j in range(3)])
  entry['bounds']={'min':[min(v[k] for v in np) for k in range(3)],'max':[max(v[k] for v in np) for k in range(3)]};points.extend(np)
 nodes[n['name']]=entry
checks={'triangles_50k':triangles<=50000,'materials_6':len(g['materials'])<=6,'uv_on_all_primitives':uv,'images_embedded':all('bufferView' in im and 'uri' not in im for im in g['images']),'no_exported_lights':'KHR_lights_punctual' not in g.get('extensions',{}),'no_exported_cameras':'cameras' not in g}
required=['SiphonWhale','StaticHull','PortHatchPivot','StarboardHatchPivot','PortHatch','StarboardHatch','CoreShield','CoreGlow','PortGlow','StarboardGlow','CoreWeakpoint','PortWeakpoint','StarboardWeakpoint','AttackOrigin','RetryEntry','RawCommandRecordAnchor']
checks['all_required_nodes']=all(n in nodes for n in required)
for name in ['PortHatchPivot','StarboardHatchPivot']:
 checks[name+'_basis_identity']=nodes[name]['rotation']==[0,0,0,1] and nodes[name]['scale']==[1,1,1]
for name in ['CoreGlow','PortGlow','StarboardGlow']:checks[name+'_only_emissive_material']=nodes[name]['materials']==['Whale_CoreCyan']
checks['separate_hatch_children']=nodes['PortHatch']['parent']=='PortHatchPivot' and nodes['StarboardHatch']['parent']=='StarboardHatchPivot'
checks['hatch_local_origin_zero']=all(abs(v)<1e-5 for n in ['PortHatch','StarboardHatch'] for v in nodes[n]['translation'])
checks['unique_node_names']=len(nodes)==len(g['nodes'])
checks['raw_record_parent']=nodes['RawCommandRecordAnchor']['parent']=='CoreWeakpoint'
expected={'CoreWeakpoint':[0,2.02,3.1],'PortWeakpoint':[-7,.65,0],'StarboardWeakpoint':[7,.65,0],'AttackOrigin':[0,-.2,6.9],'RetryEntry':[-28,-.8,14],'RawCommandRecordAnchor':[0,3.05,3.1]}
for name,value in expected.items():checks[name+'_exact_world_position']=all(abs(a-b)<1e-5 for a,b in zip(nodes[name]['world_translation'],value))
report={'sha256':hashlib.sha256(raw).hexdigest(),'bytes':len(raw),'triangles':triangles,'materials':len(g['materials']),'mesh_count':len(g['meshes']),'embedded_images':len(g['images']),'bounds':{'min':[min(v[k] for v in points) for k in range(3)],'max':[max(v[k] for v in points) for k in range(3)]},'nodes':nodes,'checks':checks,'all_checks_pass':all(checks.values()),'scope':'GLB binary/interface only; no engine or motion probes'}
(EVID/'glb_inspection.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({k:v for k,v in report.items() if k!='nodes'},ensure_ascii=False));raise SystemExit(0 if report['all_checks_pass'] else 1)
