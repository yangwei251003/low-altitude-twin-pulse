"""CPU-only GLB/accessor readback and byte-identical runtime landing."""
from pathlib import Path
import hashlib,json,math,shutil,struct,sys
sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
SOURCES={
    'f1_thermal_stone':ROOT/'asset_sources/v3/f1_thermal_stone/delivery_p1/delivery_20261020_210356_971083',
    'central_service_apron':ROOT/'asset_sources/v3/central_service_apron/p1/delivery_20261020_210411_148180'}
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def parse(path):
    raw=path.read_bytes();magic,version,total=struct.unpack_from('<4sII',raw)
    assert magic==b'glTF' and version==2 and total==len(raw)
    at=12;parts={}
    while at<len(raw):
        size,kind=struct.unpack_from('<II',raw,at);at+=8;parts[kind]=raw[at:at+size];at+=size
    return json.loads(parts[0x4e4f534a]),parts[0x004e4942]
def accessor(document,binary,index):
    a=document['accessors'][index];v=document['bufferViews'][a['bufferView']]
    fmt={5126:'f',5125:'I',5123:'H',5121:'B'}[a['componentType']];width={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']]
    size=struct.calcsize(fmt)*width;stride=v.get('byteStride',size);offset=v.get('byteOffset',0)+a.get('byteOffset',0)
    rows=[struct.unpack_from('<'+fmt*width,binary,offset+i*stride) for i in range(a['count'])]
    assert all(math.isfinite(x) for row in rows for x in row)
    return rows
def inspect(asset,folder):
    report=json.loads((folder/'delivery_report.json').read_text(encoding='utf-8'))
    glb=folder/(asset+'.glb');assert sha(glb)==report['glb_sha256']
    doc,binary=parse(glb);counts={};bounds=[];colors={}
    assert not doc.get('cameras') and 'KHR_lights_punctual' not in doc.get('extensions',{})
    mesh_names={n['mesh']:n['name'] for n in doc['nodes'] if 'mesh' in n}
    for node in doc['nodes']:
        assert node.get('translation',[0,0,0])==[0,0,0] and node.get('rotation',[0,0,0,1])==[0,0,0,1] and node.get('scale',[1,1,1])==[1,1,1]
        assert 'matrix' not in node
    for i,mesh in enumerate(doc['meshes']):
        name=mesh_names[i];assert len(mesh['primitives'])==1
        p=mesh['primitives'][0];assert p.get('mode',4)==4
        attrs=p['attributes'];positions=accessor(doc,binary,attrs['POSITION']);normals=accessor(doc,binary,attrs['NORMAL'])
        assert len(positions)==len(normals);bounds.extend(positions)
        assert all(abs(sum(x*x for x in n)-1)<.001 for n in normals)
        if 'TEXCOORD_0' in attrs:assert len(accessor(doc,binary,attrs['TEXCOORD_0']))==len(positions)
        index=accessor(doc,binary,p['indices']);assert len(index)%3==0
        assert all(0<=row[0]<len(positions) for row in index);counts[name]=len(index)//3
        colors[name]='COLOR_0' in attrs
        mat=doc['materials'][p['material']];assert mat.get('alphaMode','OPAQUE')=='OPAQUE'
        if asset=='central_service_apron' and name!='ApronJoint':
            assert colors[name] and 'baseColorTexture' in mat['pbrMetallicRoughness'] and 'normalTexture' in mat and 'metallicRoughnessTexture' in mat['pbrMetallicRoughness']
        if asset=='f1_thermal_stone' and name in ['TemperatureCore','HeatInlays']:
            assert colors[name] and 'baseColorTexture' not in mat['pbrMetallicRoughness']
    assert counts==report['mesh_triangles'] and len(doc['materials'])==report['materials']
    actual_bounds=[[min(p[k] for p in bounds) for k in range(3)],[max(p[k] for p in bounds) for k in range(3)]]
    if asset=='f1_thermal_stone':
        assert sum(counts.values())==7896
        assert max(abs(actual_bounds[a][k]-report['bounds_godot'][a][k]) for a in range(2) for k in range(3))<1e-6
    else:
        assert sum(counts.values())==1148 and all(p[1]==0 for p in bounds)
    # Every image embedded; explicit GLB has no external runtime dependency.
    assert all('bufferView' in image and 'uri' not in image for image in doc.get('images',[]))
    result={'asset':asset,'ok':True,'glb_sha256':sha(glb),'bytes':glb.stat().st_size,'mesh_triangles':counts,'materials':len(doc['materials']),
            'embedded_images':len(doc.get('images',[])),'bounds_godot':actual_bounds,'vertex_color_groups':colors,
            'scope':'raw GLB numeric readback; not Godot import, camera, collision or playtest evidence'}
    if asset=='central_service_apron':
        plan=json.loads((folder/'central_service_partition.json').read_text(encoding='utf-8'))
        g=plan['geometry'];area=0
        # Normalize the handoff's direct-engine winding after the build's CCW
        # source orientation. All attributes stay attached to the same corner.
        for start in range(0,len(g['faces']),3):
            a,b,c=g['faces'][start:start+3]
            cross_y=(b[2]-a[2])*(c[0]-a[0])-(b[0]-a[0])*(c[2]-a[2])
            if cross_y>0:
                for key in g:g[key][start+1],g[key][start+2]=g[key][start+2],g[key][start+1]
                cross_y=-cross_y
            assert cross_y<0
            area+=-cross_y*.5
        assert abs(area-plan['retained_area_m2'])<.0005
        (folder/'central_service_partition.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        result['retained_geometry_area_m2']=area;result['retained_geometry_triangles']=len(g['faces'])//3
    dest=ROOT/'assets/v3/environment'/asset;dest.mkdir(parents=True,exist_ok=True)
    for filename in [asset+'.glb']+(['central_service_partition.json'] if asset=='central_service_apron' else []):
        target=dest/filename;assert not target.exists();shutil.copyfile(folder/filename,target);assert sha(target)==sha(folder/filename)
    (folder/'numeric_readback.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(result),flush=True)
def main():
    for asset,folder in SOURCES.items():inspect(asset,folder)
if __name__=='__main__':main()
