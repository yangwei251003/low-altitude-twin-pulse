"""Read actual binary triangles/UV/normals/textures, not exporter status alone."""
from pathlib import Path
import json,struct,math,hashlib,collections
import numpy as np
NAMES=('PaintedShell','ConcreteBase','RoofMetal')
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def canonical(row):
    keys=[tuple(round(v,5) for v in c['p']) for c in row];i=min(range(3),key=lambda i:keys[i:]+keys[:i]);return tuple(keys[i:]+keys[:i]),row[i:]+row[:i]
def compare(expected,actual,reimport=False):
    errors={'position':0.,'UV':0.,'normal_raw':0.,'normal_quantized':0.,'normal_angle_degrees':0.,'normal_length_min':1e30,'normal_length_max':0.,'worst_normal':None}
    for name in expected:
        a,b=collections.defaultdict(list),collections.defaultdict(list)
        for r in expected[name]:k,t=canonical(r);a[k].append(t)
        for r in actual[name]:k,t=canonical(r);b[k].append(t)
        assert {k:len(v) for k,v in a.items()}=={k:len(v) for k,v in b.items()},(name,'triangle winding/multiset')
        key=lambda tri:tuple(round(v,6) for c in tri for v in c['uv']+c['n'])
        for k in a:
            for e,c in zip(sorted(a[k],key=key),sorted(b[k],key=key)):
                for x,y in zip(e,c):
                    errors['position']=max(errors['position'],max(abs(i-j) for i,j in zip(x['p'],y['p'])))
                    errors['UV']=max(errors['UV'],max(abs(i-j) for i,j in zip(x['uv'],y['uv'])))
                    errors['normal_raw']=max(errors['normal_raw'],max(abs(i-j) for i,j in zip(x['n'],y['n'])))
                    q=np.round(np.asarray([x['n']],dtype=np.float32),4);np.divide(q,np.linalg.norm(q,axis=1,keepdims=True),out=q)
                    errors['normal_quantized']=max(errors['normal_quantized'],max(abs(float(i)-j) for i,j in zip(q[0],y['n'])))
                    a0,a1,a2=map(float,x['n']);b0,b1,b2=map(float,y['n']);cross=math.sqrt((a1*b2-a2*b1)**2+(a2*b0-a0*b2)**2+(a0*b1-a1*b0)**2);dot=a0*b0+a1*b1+a2*b2
                    lengths=[math.sqrt(a0*a0+a1*a1+a2*a2),math.sqrt(b0*b0+b1*b1+b2*b2)]
                    assert all(.999<=v<=1.001 for v in lengths),(name,'zero or nonunit normal',x,y,lengths)
                    errors['normal_length_min']=min(errors['normal_length_min'],*lengths);errors['normal_length_max']=max(errors['normal_length_max'],*lengths)
                    angle=math.degrees(math.atan2(cross,dot))
                    if angle>errors['normal_angle_degrees']:
                        errors['normal_angle_degrees']=angle;errors['worst_normal']={'mesh':name,'position_local_godot':x['p'],'source_normal':x['n'],'actual_normal':y['n'],'angle_degrees':angle}
    assert errors['position']<=1e-5 and errors['UV']<=1e-5,errors
    assert (errors['normal_angle_degrees']<=.1 if reimport else errors['normal_quantized']<=1e-4),errors
    return errors
def verify(path,expected,textures):
    raw=Path(path).read_bytes();assert struct.unpack_from('<4sII',raw)==(b'glTF',2,len(raw));off=12;doc=binary=None
    while off<len(raw):
        size,kind=struct.unpack_from('<I4s',raw,off);off+=8;chunk=raw[off:off+size];off+=size
        if kind==b'JSON':doc=json.loads(chunk)
        elif kind==b'BIN\0':binary=chunk
    assert off==len(raw) and doc and binary
    assert not doc.get('animations') and not doc.get('cameras') and not doc.get('skins')
    assert len(doc['nodes'])==4 and len(doc['meshes'])==3 and len(doc['materials'])==3
    assert {n['name'] for n in doc['nodes']}==set(NAMES)|{'WestServiceRoom'}
    def accessor(index):
        a=doc['accessors'][index];v=doc['bufferViews'][a['bufferView']];w={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']];fmt,sz={5121:('B',1),5123:('H',2),5125:('I',4),5126:('f',4)}[a['componentType']]
        begin=v.get('byteOffset',0)+a.get('byteOffset',0);stride=v.get('byteStride',w*sz);values=[struct.unpack_from('<'+fmt*w,binary,begin+i*stride) for i in range(a['count'])]
        assert all(math.isfinite(x) for row in values for x in row);return values
    rows={};actual={};points=[]
    for node in doc['nodes']:
        assert max(map(abs,node.get('translation',[0,0,0])))<=1e-7
        assert node.get('rotation',[0,0,0,1])==[0,0,0,1] and node.get('scale',[1,1,1])==[1,1,1]
        assert node.get('matrix',[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1])==[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]
        if 'mesh' not in node:continue
        ps=doc['meshes'][node['mesh']]['primitives'];assert len(ps)==1;p=ps[0];assert p.get('mode',4)==4
        a=p['attributes'];assert 'TEXCOORD_0' in a and 'TEXCOORD_1' not in a and 'TANGENT' in a
        pos,norm,uv=accessor(a['POSITION']),accessor(a['NORMAL']),accessor(a['TEXCOORD_0']);indices=[r[0] for r in accessor(p['indices'])];tan=accessor(a['TANGENT'])
        assert len(indices)%3==0 and all(abs(abs(t[3])-1)<1e-6 for t in tan)
        assert all(-1e-6<=v<=1.000001 for r in uv for v in r)
        actual[node['name']]=[[{'p':list(pos[i]),'n':list(norm[i]),'uv':[uv[i][0],1-uv[i][1]]} for i in indices[j:j+3]] for j in range(0,len(indices),3)]
        points+=pos;rows[node['name']]={'triangles':len(indices)//3,'material':p['material'],'identity':True}
    errors=compare(expected,actual);assert len(doc['images'])==9;ims=[]
    for im in doc['images']:
        assert 'uri' not in im and im['mimeType']=='image/png';v=doc['bufferViews'][im['bufferView']];b=binary[v.get('byteOffset',0):v.get('byteOffset',0)+v['byteLength']];assert b[:8]==b'\x89PNG\r\n\x1a\n'
        ims.append({'sha256':hashlib.sha256(b).hexdigest(),'bytes':len(b),'size':list(struct.unpack_from('>II',b,16))})
    assert {r['sha256'] for r in ims}=={r['sha256'] for r in textures}
    def texhash(ref):
        assert ref.get('texCoord',0)==0
        return ims[doc['textures'][ref['index']]['source']]['sha256']
    for mat in doc['materials']:
        assert mat.get('alphaMode','OPAQUE')=='OPAQUE' and not mat.get('doubleSided',False) and mat.get('emissiveFactor',[0,0,0])==[0,0,0]
        group=mat['name'].removeprefix('WestService_').removesuffix('_BakedPBR');assert group in NAMES
        maps={r['channel']:r['sha256'] for r in textures if r['group']==group};p=mat['pbrMetallicRoughness']
        assert texhash(p['baseColorTexture'])==maps['BaseColor'] and texhash(p['metallicRoughnessTexture'])==maps['ORM'] and texhash(mat['normalTexture'])==maps['Normal']
    bounds=[[min(p[i] for p in points) for i in range(3)],[max(p[i] for p in points) for i in range(3)]]
    assert max(abs(a-b) for r,e in zip(bounds,[[-2,0,-2],[2,2.5,2]]) for a,b in zip(r,e))<=1e-5
    return {'status':'RAW_GLB_VERIFIED','sha256':sha(path),'bytes':len(raw),'root':'WestServiceRoom','meshes':rows,'triangles':sum(r['triangles'] for r in rows.values()),'AABB':bounds,'images':ims,'material_count':3,'materials':doc['materials'],'source_errors':errors,'normal_rule':'Installed glTF exporter float32 round(4) then normalize. Raw and quantized errors both retained.'}
