"""Read frozen P9 SDNA corner attributes without starting Blender or touching any inputs."""
from pathlib import Path
import json,hashlib,struct
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
reader=ROOT/'asset_sources/v3/growth_approach/resource_recovery/read_blend_lods.py'
source=reader.read_text(encoding='utf-8').split('\nout=[inspect(')[0]
source=source.replace("ptr=8 if blob[7:8]==b'-' else 4;e='<' if blob[8:9]==b'v' else '>'", "large=blob[7:9].isdigit();ptr=8 if large or blob[7:8]==b'-' else 4;e='<' if (blob[12:13] if large else blob[8:9])==b'v' else '>'")
source=source.replace("fmt=e+'4sI'+('Q' if ptr==8 else 'I')+'II';head=struct.calcsize(fmt)","fmt=e+'4sIQQII' if large else e+'4sI'+('Q' if ptr==8 else 'I')+'II';head=struct.calcsize(fmt)")
source=source.replace('blocks=[];offset=12','blocks=[];offset=int(blob[7:9]) if large else 12')
source=source.replace('code,size,address,sdna,count=struct.unpack_from(fmt,blob,offset);offset+=head',"if large:code,sdna,address,size,count,pad=struct.unpack_from(fmt,blob,offset)\n        else:code,size,address,sdna,count=struct.unpack_from(fmt,blob,offset)\n        offset+=head")
source=source[:source.index('    meshes={};objects=[]')]+r'''
    global_addresses={b[1]:b for b in blocks}
    def fields(raw,typename,key):
        f=by_type[typename]['fields'][key];return raw[f['offset']:f['offset']+f['size']]
    def ptrval(raw):return int.from_bytes(raw[:ptr],'little' if e=='<' else 'big')
    objects=[b for b in blocks if b[2]<len(schemas) and schemas[b[2]]['name']=='Object']
    ob=next(b for b in objects if idname(b)[2:]=='BakeProxy')
    address=ptrval(get(ob,'data'));block=next(b for b in blocks if b[1]==address and schemas[b[2]]['name']=='Mesh')
    idx=blocks.index(block)+1;end=idx
    while end<len(blocks) and blocks[end][0]==b'DATA':end+=1
    addresses={**global_addresses,**{b[1]:b for b in blocks[idx:end]}}
    raw=get(block,'attribute_storage');layer_address=ptrval(fields(raw,'AttributeStorage','dna_attributes'));layer_count=struct.unpack(e+'i',fields(raw,'AttributeStorage','dna_attributes_num')[:4])[0]
    layer_blob=addresses[layer_address][4];stride=by_type['Attribute']['length'];attrs={};info=[]
    for i in range(layer_count):
        row=layer_blob[i*stride:(i+1)*stride];attr=addresses[ptrval(fields(row,'Attribute','name'))][4].split(b'\0')[0].decode()
        storage=addresses[ptrval(fields(row,'Attribute','data'))];kind=schemas[storage[2]]['name'];at=ptrval(fields(storage[4],kind,'data'));data=addresses[at][4]
        info.append({'name':attr,'storage_type':kind,'bytes':len(data)})
        if attr in ['position','.corner_vert','BakeUV','MetricUV','SoilScanUV','SurfaceControl','RuntimeGroup']:
            fmt={'position':'3f','.corner_vert':'i','BakeUV':'2f','MetricUV':'2f','SoilScanUV':'2f','SurfaceControl':'4f','RuntimeGroup':'i'}[attr];attrs[attr]=list(struct.iter_unpack(e+fmt,data))
    return {'info':info,'mesh_name':idname(block)[2:],'attrs':attrs,'blend_sha256':hashlib.sha256(compressed).hexdigest()}
'''
ns={'__file__':str(HERE/'_sdna_in_memory.py')}
exec(compile(source,str(reader),'exec'),ns)
result=ns['inspect'](HERE.parent/'p9/baked_source.blend')
(HERE/'sdna_proxy_arrays.json').write_text(json.dumps(result,separators=(',',':')),encoding='utf-8')
print(json.dumps({'mesh':result['mesh_name'],'attributes':result['info'],'sha256':result['blend_sha256']},indent=2))
