"""Download two small official geometry sources; inspect an existing coast crop."""
from pathlib import Path
import urllib.request,json,hashlib,struct
import numpy as np
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def acc(g,b,index):
 a=g['accessors'][index];v=g['bufferViews'][a['bufferView']];typ={5126:'f',5125:'I',5123:'H',5121:'B'}[a['componentType']];w={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']];s=struct.Struct('<'+typ*w);off=v.get('byteOffset',0)+a.get('byteOffset',0);stride=v.get('byteStride',s.size)
 return np.array([s.unpack_from(b,off+i*stride) for i in range(a['count'])])
def read_geometry(path):
 g=json.loads(path.read_text());b=(path.parent/g['buffers'][0]['uri']).read_bytes();p=g['meshes'][0]['primitives'][0]
 return g,acc(g,b,p['attributes']['POSITION']),acc(g,b,p['indices']).reshape(-1,3).astype(int)
provenance=[];meshes=[]
for asset in ['rock_face_01','rock_face_02']:
 folder=HERE/'vendor'/asset;j=json.loads((folder/'files.json').read_text());spec=j['gltf']['1k']['gltf'];info=json.loads((folder/'info.json').read_text())
 rec={'asset':asset,'source_url':f'https://polyhaven.com/a/{asset}','license':'CC0-1.0','license_url':'https://polyhaven.com/license','authors':info['authors'],'purpose':'raw source-only geometry study; photographic materials not downloaded','files':[]}
 for filename,d in [(asset+'_1k.gltf',spec),*[(k,v) for k,v in spec['include'].items() if k.endswith('.bin')]]:
  p=folder/filename
  if not p.exists():p.write_bytes(urllib.request.urlopen(urllib.request.Request(d['url'],headers={'User-Agent':'LowAltitudeTwinPulseAssetStudy/1.0 (CC0 geometry source research)'}),timeout=30).read())
  md5=hashlib.md5(p.read_bytes()).hexdigest();assert md5==d['md5'] and p.stat().st_size==d['size']
  rec['files'].append({'file':str(p.relative_to(HERE)).replace('\\','/'),'url':d['url'],'bytes':p.stat().st_size,'md5_verified':md5,'sha256':sha(p)})
 g,v,f=read_geometry(folder/(asset+'_1k.gltf'));lo=v.min(0);hi=v.max(0)
 meshes.append({'asset':asset,'triangles':len(f),'vertices':len(v),'bounds_godot_yup':[lo.tolist(),hi.tolist()],'span':(hi-lo).tolist(),'nodes':g['nodes'],'source_gltf_sha256':sha(folder/(asset+'_1k.gltf'))});provenance.append(rec)
(HERE/'provenance.json').write_text(json.dumps(provenance,ensure_ascii=False,indent=2),encoding='utf-8')
coast=ROOT/'asset_sources/third_party/coast_rocks_01/coast_rocks_01_1k.gltf';g,v,f=read_geometry(coast)
ts=v[f];centres=ts.mean(1);cross=np.cross(ts[:,1]-ts[:,0],ts[:,2]-ts[:,0]);length=np.linalg.norm(cross,axis=1);steep=np.abs(cross[:,1])/(length+1e-30)<.5
cells=[]
for x in np.arange(v[:,0].min(),v[:,0].max()-4,2):
 for z in np.arange(v[:,2].min(),v[:,2].max()-4,2):
  mask=(centres[:,0]>=x)&(centres[:,0]<=x+4)&(centres[:,2]>=z)&(centres[:,2]<=z+4)
  if mask.sum()<100:continue
  c=ts[mask].reshape(-1,3);span=c.max(0)-c.min(0);total=length[mask].sum();area=length[mask&steep].sum()
  cells.append({'min_xz':[float(x),float(z)],'size_xz':[4,4],'triangles':int(mask.sum()),'span':span.tolist(),'steep_surface_fraction':float(area/total),'score':float(span[1]*(area/total))})
cells.sort(key=lambda c:c['score'],reverse=True)
result={'official_sources':meshes,'coast_original':{'gltf':str(coast.relative_to(ROOT)).replace('\\','/'),'gltf_sha256':sha(coast),'bin_sha256':sha(coast.parent/'coast_rocks_01.bin'),'triangles':len(f),'span':(v.max(0)-v.min(0)).tolist()},'coast_top_crop_candidates':cells[:5],'crop_method':'4x4m cells; score actual height span times fraction of surface with abs(normalY)<0.5, no source reshaping','limits':'numeric source suitability only; one basic-shape render still required'}
(HERE/'source_geometry_research.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(result,ensure_ascii=False,indent=2))
