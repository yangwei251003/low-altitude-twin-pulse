"""Audit render-active source UV and actual glTF texture coordinate selection.
Read-only toward source/runtime assets. Writes only versioned evidence JSON.
"""
import bpy,json,struct,sys,collections
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3];SRC=ROOT/'asset_sources/v3/overpass';EVID=ROOT/'artifacts/v3/art/overpass'
version=sys.argv[sys.argv.index('--revision')+1] if '--revision' in sys.argv else 'unknown'
bpy.ops.wm.open_mainfile(filepath=str(SRC/'maintenance_overpass.blend'))
meshes=[o for o in bpy.data.collections['Editable_Overpass'].objects if o.type=='MESH']
rows=[];active=collections.Counter()
for o in meshes:
 layers=[{'name':uv.name,'active_render':uv.active_render,'min':[min(c.uv[k] for c in uv.data) for k in range(2)],'max':[max(c.uv[k] for c in uv.data) for k in range(2)]} for uv in o.data.uv_layers]
 names=[l['name'] for l in layers if l['active_render']];active[','.join(names)]+=1
 rows.append({'object':o.name,'active_index':o.data.uv_layers.active_index,'layers':layers})
p=ROOT/'assets/v3/overpass/maintenance_overpass.glb';raw=p.read_bytes();length=struct.unpack_from('<I',raw,12)[0];g=json.loads(raw[20:20+length]);blob=raw[28+length:]
def uv_array(i):
 a=g['accessors'][i];v=g['bufferViews'][a['bufferView']];offset=v.get('byteOffset',0)+a.get('byteOffset',0);stride=v.get('byteStride',8)
 return [struct.unpack_from('<ff',blob,offset+k*stride) for k in range(a['count'])]
export=[]
for mesh in g['meshes']:
 for p in mesh['primitives']:
  m=g['materials'][p['material']];selected=m['pbrMetallicRoughness']['baseColorTexture'].get('texCoord',0);sets={}
  for key,index in p['attributes'].items():
   if key.startswith('TEXCOORD_'):
    uv=uv_array(index);sets[key]={'min':[min(c[k] for c in uv) for k in range(2)],'max':[max(c[k] for c in uv) for k in range(2)]}
  export.append({'mesh':mesh['name'],'material':m['name'],'base_color_selected_texcoord':selected,'sets':sets})
one_source_uv=all(len(o.data.uv_layers)==1 and o.data.uv_layers[0].name=='SurfaceUV' and o.data.uv_layers[0].active_render for o in meshes)
one_glb_uv=all(list(e['sets'])==['TEXCOORD_0'] and e['base_color_selected_texcoord']==0 for e in export)
authored_uv_bounds=all(all(v>=.005 for v in e['sets']['TEXCOORD_0']['min']) and all(v<=.995 for v in e['sets']['TEXCOORD_0']['max']) for e in export)
r={'revision':version,'mesh_count':len(meshes),'active_render_uv_counts':dict(active),'source_samples':rows[:12],'glb_primitives':export,'checks':{'one_source_uv_named_surface_and_render_active':one_source_uv,'one_glb_uv0_selected':one_glb_uv,'uv0_matches_authored_inset_bounds':authored_uv_bounds},'all_checks_pass':one_source_uv and one_glb_uv and authored_uv_bounds,'note':'Pre-fix audit intentionally records failures; not a relaxed acceptance gate.'}
(EVID/f'uv_audit_v{version}.json').write_text(json.dumps(r,ensure_ascii=False,indent=2),encoding='utf-8')
print('OVERPASS_UV_AUDIT '+json.dumps({k:v for k,v in r.items() if k!='source_samples'}),flush=True)
