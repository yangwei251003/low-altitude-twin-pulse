"""Read frozen V2 SDNA corner attributes without starting Blender or touching V2."""
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
        f=by_type[typename]['fields'][key]
        return raw[f['offset']:f['offset']+f['size']]
    def ptrval(raw):return int.from_bytes(raw[:ptr],'little' if e=='<' else 'big')
    selected=['RoofBatten_1','PumpSouthWestJamb_Panel_0_0','PumpEastWall_Foot']
    found=[]
    for block in blocks:
        if block[2]>=len(schemas) or schemas[block[2]]['name']!='Mesh':continue
        name=idname(block)[2:]
        if name not in selected:continue
        # Blender emits some temporary AttributeArray wrappers with reused old
        # addresses across ID blocks. Resolve those within THIS Mesh's DATA run.
        idx=blocks.index(block)+1;end=idx
        while end<len(blocks) and blocks[end][0]==b'DATA':end+=1
        addresses={**global_addresses,**{b[1]:b for b in blocks[idx:end]}}
        schema=schemas[block[2]]
        raw=get(block,'attribute_storage')
        layer_address=ptrval(fields(raw,'AttributeStorage','dna_attributes'))
        layer_count=struct.unpack(e+'i',fields(raw,'AttributeStorage','dna_attributes_num')[:4])[0]
        layer_blob=addresses[layer_address][4];stride=by_type['Attribute']['length'];attrs=[]
        for i in range(layer_count):
            row=layer_blob[i*stride:(i+1)*stride]
            attr=addresses[ptrval(fields(row,'Attribute','name'))][4].split(b'\0')[0].decode()
            if attr not in ['SurfaceUse','FaceSize','WearControl','PanelUV']:continue
            storage=addresses[ptrval(fields(row,'Attribute','data'))]
            storage_name=schemas[storage[2]]['name']
            assert storage_name in ['AttributeArray','AttributeSingle'],storage_name
            at=ptrval(fields(storage[4],storage_name,'data'));data=addresses[at][4]
            channel=2 if attr=='PanelUV' else 4
            values=[tuple(round(v,7) for v in x) for x in struct.iter_unpack(e+str(channel)+'f',data)]
            attrs.append({'name':attr,'sample_count':len(values),'unique_values':sorted(set(values)),
                          'minimum':[min(x[j] for x in values) for j in range(channel)],
                          'maximum':[max(x[j] for x in values) for j in range(channel)]})
        found.append({'mesh':name,'attributes':attrs})
    assert len(found)==3 and all(len(x['attributes'])==4 for x in found),'Three meshes and four actual attributes each required'
    return {'method':'Frozen native .blend SDNA read; no Blender, shader evaluation or raster test',
            'blend_sha256':hashlib.sha256(compressed).hexdigest(),'representatives':found,
            'not_tested':'Attribute-to-shader evaluated effects still require next authorized Blender window.'}
'''
ns={'__file__':str(HERE/'_sdna_in_memory.py')}
exec(compile(source,str(reader),'exec'),ns)
result=ns['inspect'](HERE.parent/'prototype_v2/pump_shell_prototype.blend')
result['reader_source_sha256']=hashlib.sha256(reader.read_bytes()).hexdigest()
(HERE/'v2_attribute_readback.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps(result,ensure_ascii=False,indent=2))

