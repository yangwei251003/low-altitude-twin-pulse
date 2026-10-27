"""Actual GLB binary contract. No rendering or filesystem mutation."""
from pathlib import Path
import json,struct,math,hashlib,collections
import numpy as np

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def canonical(row):
    keys=[tuple(round(v,5) for v in c['p']) for c in row];i=min(range(3),key=lambda i:keys[i:]+keys[:i]);return tuple(keys[i:]+keys[:i]),row[i:]+row[:i]

def verify_raw(path,expected,textures):
    raw=Path(path).read_bytes();assert struct.unpack_from('<4sII',raw)==(b'glTF',2,len(raw));offset=12;doc=binary=None
    while offset<len(raw):
        size,kind=struct.unpack_from('<I4s',raw,offset);offset+=8;chunk=raw[offset:offset+size];offset+=size
        if kind==b'JSON':doc=json.loads(chunk)
        elif kind==b'BIN\0':binary=chunk
    assert doc is not None and binary is not None and offset==len(raw)
    assert not doc.get('animations') and not doc.get('cameras') and not doc.get('skins')
    def accessor(index):
        a=doc['accessors'][index];v=doc['bufferViews'][a['bufferView']];assert not a.get('normalized') and 'sparse' not in a
        width={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']];fmt,size={5121:('B',1),5123:('H',2),5125:('I',4),5126:('f',4)}[a['componentType']]
        start=v.get('byteOffset',0)+a.get('byteOffset',0);stride=v.get('byteStride',width*size)
        values=[struct.unpack_from('<'+fmt*width,binary,start+i*stride) for i in range(a['count'])]
        assert all(math.isfinite(x) for row in values for x in row);return values
    assert len(doc['nodes'])==3 and len(doc['meshes'])==2 and len(doc['materials'])==2
    expected_names={'CalibrationRack','DeckSurface','StructureAndHardware'};assert {n['name'] for n in doc['nodes']}==expected_names
    root=next(i for i,n in enumerate(doc['nodes']) if n['name']=='CalibrationRack')
    assert set(doc['nodes'][root]['children'])==set(range(3))-{root}
    actual={};bounds=[];node_rows={}
    for node in doc['nodes']:
        assert max(abs(x) for x in node.get('translation',[0,0,0]))<=1e-7
        assert max(abs(a-b) for a,b in zip(node.get('rotation',[0,0,0,1]),[0,0,0,1]))<=1e-7
        assert max(abs(v-1) for v in node.get('scale',[1,1,1]))<=1e-7
        assert node.get('matrix',[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1])==[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]
        if 'mesh' not in node:continue
        primitives=doc['meshes'][node['mesh']]['primitives'];assert len(primitives)==1
        p=primitives[0];assert p.get('mode',4)==4;attrs=p['attributes'];assert 'TEXCOORD_0' in attrs and 'TEXCOORD_1' not in attrs and 'TANGENT' in attrs
        ps,ns,uv=accessor(attrs['POSITION']),accessor(attrs['NORMAL']),accessor(attrs['TEXCOORD_0']);ts=accessor(attrs['TANGENT']);indices=[v[0] for v in accessor(p['indices'])]
        assert all(abs(abs(t[3])-1)<1e-6 for t in ts) and len(indices)%3==0
        assert all(-1e-6<=v<=1.000001 for row in uv for v in row)
        actual[node['name']]=[[{'p':list(ps[j]),'n':list(ns[j]),'uv':[uv[j][0],1-uv[j][1]]} for j in indices[i:i+3]] for i in range(0,len(indices),3)]
        bounds+=ps;node_rows[node['name']]={'triangles':len(indices)//3,'material':p['material'],'identity':True}
    assert set(actual)==set(expected)
    errors={'position':0.,'UV':0.,'normal_raw':0.,'normal_quantized':0.}
    for name in expected:
        a,b=collections.defaultdict(list),collections.defaultdict(list)
        for row in expected[name]:key,tri=canonical(row);a[key].append(tri)
        for row in actual[name]:key,tri=canonical(row);b[key].append(tri)
        assert {k:len(v) for k,v in a.items()}=={k:len(v) for k,v in b.items()},(name,'triangle multiset or winding')
        sort=lambda t:tuple(round(v,6) for c in t for v in c['uv']+c['n'])
        for key in a:
            for left,right in zip(sorted(a[key],key=sort),sorted(b[key],key=sort)):
                for e,c in zip(left,right):
                    errors['position']=max(errors['position'],max(abs(x-y) for x,y in zip(e['p'],c['p'])))
                    errors['UV']=max(errors['UV'],max(abs(x-y) for x,y in zip(e['uv'],c['uv'])))
                    q=np.round(np.asarray([e['n']],dtype=np.float32),4);np.divide(q,np.linalg.norm(q,axis=1,keepdims=True),out=q)
                    errors['normal_raw']=max(errors['normal_raw'],max(abs(x-y) for x,y in zip(e['n'],c['n'])))
                    errors['normal_quantized']=max(errors['normal_quantized'],max(abs(float(x)-y) for x,y in zip(q[0],c['n'])))
    assert errors['position']<=1e-5 and errors['UV']<=1e-5 and errors['normal_quantized']<=1e-4,errors
    assert sum(r['triangles'] for r in node_rows.values())==4740
    assert len(doc['images'])==6;image_rows=[]
    for image in doc['images']:
        assert 'uri' not in image and image['mimeType']=='image/png';v=doc['bufferViews'][image['bufferView']];data=binary[v.get('byteOffset',0):v.get('byteOffset',0)+v['byteLength']]
        assert data[:8]==b'\x89PNG\r\n\x1a\n';image_rows.append({'sha256':hashlib.sha256(data).hexdigest(),'bytes':len(data),'size':list(struct.unpack_from('>II',data,16))})
    assert {r['sha256'] for r in image_rows}=={r['sha256'] for r in textures}
    def image_digest(tex):
        assert tex.get('texCoord',0)==0
        return image_rows[doc['textures'][tex['index']]['source']]['sha256']
    for mat in doc['materials']:
        assert not mat.get('doubleSided',False) and mat.get('alphaMode','OPAQUE')=='OPAQUE' and mat.get('emissiveFactor',[0,0,0])==[0,0,0]
        label='Deck' if mat['name']=='CalibrationRack_Deck_PBR' else 'Structure';assert mat['name']=='CalibrationRack_'+label+'_PBR'
        maps={r['channel']:r['sha256'] for r in textures if r['set']==label};p=mat['pbrMetallicRoughness']
        assert image_digest(p['baseColorTexture'])==maps['BaseColor'] and image_digest(p['metallicRoughnessTexture'])==maps['ORM'] and image_digest(mat['normalTexture'])==maps['Normal']
    actual_bounds=[[min(p[i] for p in bounds) for i in range(3)],[max(p[i] for p in bounds) for i in range(3)]]
    assert max(abs(a-b) for row,exp in zip(actual_bounds,[[-1.2,0,-1.2],[1.2,.32,1.2]]) for a,b in zip(row,exp))<=1e-5
    return {'status':'RAW_GLB_VERIFIED_NOT_GODOT','sha256':sha(path),'bytes':len(raw),'nodes':node_rows,'root':'CalibrationRack',
            'meshes':2,'materials':doc['materials'],'images':image_rows,'triangles':4740,'AABB':actual_bounds,'source_errors':errors,
            'normal_rule':'Installed glTF exporter float32 round(4) then normalize; raw delta also reported.'}
