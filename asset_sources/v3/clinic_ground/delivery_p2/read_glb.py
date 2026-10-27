"""Binary glTF readback only. Does not modify source or generated PNG pixels."""
import json,struct,hashlib,collections,math

def f32(v):return struct.unpack('<f',struct.pack('<f',float(v)))[0]
def canon(corners):return min(tuple(corners),tuple(corners[1:]+corners[:1]),tuple(corners[2:]+corners[:2]))
def bounds(points):return [[min(p[i] for p in points) for i in range(3)],[max(p[i] for p in points) for i in range(3)]]
def node_identity(n):
 return n.get('translation',[0,0,0])==[0,0,0] and n.get('rotation',[0,0,0,1])==[0,0,0,1] and n.get('scale',[1,1,1])==[1,1,1] and n.get('matrix',[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1])==[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]

def read(path):
 data=path.read_bytes();magic,version,length=struct.unpack_from('<4sII',data,0)
 assert magic==b'glTF' and version==2 and length==len(data)
 offset=12;j=None;binary=None
 while offset<len(data):
  size,kind=struct.unpack_from('<I4s',data,offset);assert offset+8+size<=len(data)
  chunk=data[offset+8:offset+8+size];offset+=8+size
  if kind==b'JSON':assert j is None;j=json.loads(chunk.decode('utf-8'))
  elif kind==b'BIN\0':assert binary is None;binary=chunk
 assert j is not None and binary is not None and offset==len(data)
 assert len(j['buffers'])==1 and 'uri' not in j['buffers'][0]
 def accessor(index):
  a=j['accessors'][index];v=j['bufferViews'][a['bufferView']];assert 'sparse' not in a and not a.get('normalized',False)
  c={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']];fmt={5121:'B',5123:'H',5125:'I',5126:'f'}[a['componentType']]
  size=struct.calcsize('<'+fmt*c);start=v.get('byteOffset',0)+a.get('byteOffset',0);stride=v.get('byteStride',size)
  assert stride>=size and start+(a['count']-1)*stride+size<=len(binary)
  result=[struct.unpack_from('<'+fmt*c,binary,start+i*stride) for i in range(a['count'])]
  assert all(math.isfinite(x) for row in result for x in row)
  return result
 parsed={};allpos=[]
 for mesh in j['meshes']:
  assert mesh['name'] not in parsed
  tris=collections.Counter();corners=collections.Counter();surfaces=[];points=[]
  for pr in mesh['primitives']:
   assert pr.get('mode',4)==4 and 'indices' in pr and not pr.get('targets')
   attributes=pr['attributes'];ps=accessor(attributes['POSITION']);uv=accessor(attributes['TEXCOORD_0']);ns=accessor(attributes['NORMAL']);ix=[x[0] for x in accessor(pr['indices'])]
   assert len(ix)%3==0 and len(ps)==len(uv)==len(ns) and all(0<=i<len(ps) for i in ix)
   for i in range(0,len(ix),3):
    triangle=ix[i:i+3];tris[canon([ps[x] for x in triangle])]+=1
    corners[canon([tuple(ps[x])+tuple(uv[x]) for x in triangle])]+=1
   points+=ps
   surfaces.append({'triangles':len(ix)//3,'material':j['materials'][pr['material']]['name'],
                    'attributes':list(attributes),'uv0_bounds':[[min(p[i] for p in uv) for i in range(2)],[max(p[i] for p in uv) for i in range(2)]],
                    'normals_unit':all(abs(sum(t*t for t in n)-1)<2e-4 for n in ns)})
  parsed[mesh['name']]={'triangles':tris,'corner_uv':corners,'bounds':bounds(points),'surfaces':surfaces};allpos+=points
 images=[]
 for i,im in enumerate(j.get('images',[])):
  assert 'bufferView' in im and 'uri' not in im and im.get('mimeType')=='image/png'
  view=j['bufferViews'][im['bufferView']];start=view.get('byteOffset',0);raw=binary[start:start+view['byteLength']]
  assert len(raw)==view['byteLength'] and raw[:8]==b'\x89PNG\r\n\x1a\n' and raw[12:16]==b'IHDR'
  w,h=struct.unpack_from('>II',raw,16)
  images.append({'index':i,'name':im.get('name'),'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest(),'size':[w,h]})
 return j,parsed,bounds(allpos),images
