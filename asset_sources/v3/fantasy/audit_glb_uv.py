"""Read-only GLB UV-merge regression; writes only an audit artifact."""
import json,struct,hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
path=ROOT/'assets/v3/fantasy/temple_gate.glb'
blob=path.read_bytes(); size=struct.unpack_from('<I',blob,12)[0]
doc=json.loads(blob[20:20+size]); binary=blob[28+size:]

def uv_values(index):
    accessor=doc['accessors'][index]; view=doc['bufferViews'][accessor['bufferView']]
    assert accessor['componentType']==5126 and accessor['type']=='VEC2'
    offset=view.get('byteOffset',0)+accessor.get('byteOffset',0)
    stride=view.get('byteStride',8)
    return [struct.unpack_from('<ff',binary,offset+i*stride) for i in range(accessor['count'])]

warnings=[]; checked=[]
for mesh_index,mesh in enumerate(doc['meshes']):
    node=next(n for n in doc['nodes'] if n.get('mesh')==mesh_index)
    for primitive in mesh['primitives']:
        material=doc['materials'][primitive['material']]
        texture=material.get('pbrMetallicRoughness',{}).get('baseColorTexture')
        if texture is None: continue
        primary=primitive['attributes']['TEXCOORD_'+str(texture.get('texCoord',0))]
        values=uv_values(primary)
        index_accessor=doc['accessors'][primitive['indices']]
        index_view=doc['bufferViews'][index_accessor['bufferView']]
        index_format={5121:'B',5123:'H',5125:'I'}[index_accessor['componentType']]
        index_size=struct.calcsize('<'+index_format)
        index_start=index_view.get('byteOffset',0)+index_accessor.get('byteOffset',0)
        indices=[struct.unpack_from('<'+index_format,binary,index_start+i*index_size)[0] for i in range(index_accessor['count'])]
        flat_default=sum(all(abs(values[j][0])+abs(values[j][1]-1)<1e-8 for j in indices[i:i+3]) for i in range(0,len(indices),3))
        missing=0
        if 'TEXCOORD_1' in primitive['attributes'] and texture.get('texCoord',0)==0:
            alternate=uv_values(primitive['attributes']['TEXCOORD_1'])
            missing=sum(abs(u)+abs(v-1)<1e-8 and abs(u1)+abs(v1-1)>1e-8 for (u,v),(u1,v1) in zip(values,alternate))
        row={'node':node['name'],'material':material['name'],'vertex_count':len(values),'missing_active_uv_with_alternate':missing,'flat_default_uv_triangles':flat_default}
        checked.append(row)
        if missing or flat_default: warnings.append(row)
report={'status':'PASS' if not warnings else 'FAIL','sha256':hashlib.sha256(blob).hexdigest(),'checked':checked,'warnings':warnings,'criterion':'A textured UV0 vertex must not retain the join default (0,1) while its real per-object UV coordinates exist only in UV1.'}
target=ROOT/'artifacts/v3/art/fantasy/temple_gate_uv_audit.json'
target.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(report,ensure_ascii=False))
raise SystemExit(0 if not warnings else 1)
