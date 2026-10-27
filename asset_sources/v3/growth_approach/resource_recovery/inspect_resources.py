"""Bounded read-only source-asset research. Python standard library only.
Powered by Poly Haven: https://polyhaven.com
Only this directory receives small metadata, official reference previews and
selected source files (per-file cap 8 MB; no texture packages).
Does not run Blender, Godot, GPU or alter any production/imported asset.
"""
from pathlib import Path
import urllib.request,json,hashlib,struct,collections
BASE=Path(__file__).resolve().parent
PROJECT=BASE.parents[3]
BASE.mkdir(parents=True,exist_ok=True)
HEAD={'User-Agent':'LowAltitudeSquad-AssetResearch/1.0 (Powered by Poly Haven; bounded asset review)'}
def get(url,path,cap=8_000_000):
    if path.exists():
        blob=path.read_bytes()
        return blob,{'url':url,'reused_small_file_from_this_task':True,'bytes':len(blob),'sha256':hashlib.sha256(blob).hexdigest()}
    request=urllib.request.Request(url,headers=HEAD)
    with urllib.request.urlopen(request,timeout=25) as r:
        blob=r.read(cap+1)
        if len(blob)>cap:raise RuntimeError('bounded download exceeded: '+url)
        info={'url':r.url,'status':r.status,'bytes':len(blob),'sha256':hashlib.sha256(blob).hexdigest(),'content_type':r.headers.get('Content-Type')}
    path.write_bytes(blob)
    return blob,info
summary=[]
for aid in ['rock_face_01','rock_face_02','boulder_01','namaqualand_boulder_03','rock_moss_set_01']:
    folder=BASE/aid;folder.mkdir(exist_ok=True)
    info_raw,info_ev=get('https://api.polyhaven.com/info/'+aid,folder/'info.json',100_000)
    files_raw,files_ev=get('https://api.polyhaven.com/files/'+aid,folder/'files.json',200_000)
    info=json.loads(info_raw);files=json.loads(files_raw)
    g=files['gltf']['1k']['gltf'];blend_record=files['blend']['1k']['blend']
    gr,ge=get(g['url'],folder/(aid+'_1k.gltf'),100_000);gltf=json.loads(gr)
    bins=[(k,v) for k,v in g.get('include',{}).items() if k.endswith('.bin')]
    bin_ev=[]
    for name,entry in bins:
        local=PROJECT/'asset_sources/v3/root_buttress/p8/vendor'/aid/name
        if aid=='rock_moss_set_01':local=PROJECT/'asset_sources/v3/root_buttress/p6/vendor'/name
        if local.exists():
            blob=local.read_bytes();ev={'read_existing':str(local.relative_to(PROJECT)),'bytes':len(blob),'sha256':hashlib.sha256(blob).hexdigest()}
        else:blob,ev=get(entry['url'],folder/name)
        assert hashlib.md5(blob).hexdigest().lower()==entry['md5'].lower()
        bin_ev.append(ev)
    # glTF byte-level connectivity and coordinates; split UV seam positions
    # are welded only for edge-count diagnostics, never to change the mesh.
    records=[]
    for mesh in gltf.get('meshes',[]):
        for prim in mesh['primitives']:
            def read_accessor(index):
                a=gltf['accessors'][index];v=gltf['bufferViews'][a['bufferView']]
                n={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']]
                fmt={5123:'H',5125:'I',5126:'f'}[a['componentType']]
                size=struct.calcsize('<'+fmt*n);stride=v.get('byteStride',size)
                start=v.get('byteOffset',0)+a.get('byteOffset',0)
                return [struct.unpack_from('<'+fmt*n,blob,start+i*stride) for i in range(a['count'])]
            pos=read_accessor(prim['attributes']['POSITION']);ids=[p[0] for p in read_accessor(prim['indices'])]
            assert prim.get('mode',4)==4 and len(ids)%3==0
            canonical={};mapping=[]
            for p in pos:
                key=tuple(round(x,6) for x in p);mapping.append(canonical.setdefault(key,len(canonical)))
            edges=collections.Counter()
            for i in range(0,len(ids),3):
                tri=[mapping[k] for k in ids[i:i+3]]
                for a,b in zip(tri,tri[1:]+tri[:1]):edges[tuple(sorted((a,b)))]+=1
            records.append({'name':mesh.get('name'),'triangles':len(ids)//3,'vertices':len(pos),'position_min':[min(p[k] for p in pos) for k in range(3)],'position_max':[max(p[k] for p in pos) for k in range(3)],'boundary_edges_position_welded_1um':sum(c==1 for c in edges.values()),'edges_more_than_two_faces':sum(c>2 for c in edges.values())})
    render='https://cdn.polyhaven.com/asset_img/renders/'+aid+'/clay.png?width=768&quality=90&v='+info.get('img_version','')
    _,preview_ev=get(render,folder/'official_clay_preview.png',2_000_000)
    # Only one small native source needs retrieval: known LODs absent from glTF.
    blend_ev=None
    if info.get('lods',False):
        _,blend_ev=get(files['blend']['1k']['blend']['url'],folder/(aid+'_1k.blend'))
    summary.append({'id':aid,'name':info['name'],'authors':info.get('authors'),'page':'https://polyhaven.com/a/'+aid,'license':'CC0 (models and textures; official example renders are research references, not claimed CC0 runtime art)','api_polycount':info.get('polycount'),'api_dimensions_mm':info.get('dimensions'),'has_lods':info.get('lods',False),'actual_gltf_meshes':records,'gltf_nodes':gltf.get('nodes',[]),'gltf_1k_package_bytes':g['size']+sum(v['size'] for v in g.get('include',{}).values()),'blend_1k_package_bytes':blend_record['size']+sum(v['size'] for v in blend_record.get('include',{}).values()),'blend_file_only_bytes':blend_record['size'],'gltf_geometry_only_bytes':g['size']+sum(v['size'] for k,v in bins),'map_types':list(files),'evidence':{'info':info_ev,'files':files_ev,'gltf':ge,'binary':bin_ev,'preview':preview_ev,'blend':blend_ev}})
(BASE/'resource_facts.json').write_text(json.dumps({'at':'2026-10-18','powered_by':'Poly Haven https://polyhaven.com','assets':summary},ensure_ascii=False,indent=2),encoding='utf8')
for a in summary:print(a['id'],json.dumps({k:a[k] for k in ['actual_gltf_meshes','gltf_1k_package_bytes','blend_file_only_bytes','has_lods']},ensure_ascii=False))
