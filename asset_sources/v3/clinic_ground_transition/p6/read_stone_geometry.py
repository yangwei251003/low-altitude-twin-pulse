"""Exact source object geometry via SDNA, no model execution or mutation."""
from pathlib import Path
import json
HERE=Path(__file__).resolve().parent
wrapper=(HERE/'read_proxy_arrays.py').read_text(encoding='utf-8')
prefix=wrapper[:wrapper.index("source=source[:source.index(")]
ns={'__file__':str(HERE/'read_proxy_arrays.py')};exec(prefix,ns)
source=ns['source'];source=source[:source.index('    meshes={};objects=[]')]+r'''
    global_addresses={b[1]:b for b in blocks}
    def fields(raw,typename,key):
        f=by_type[typename]['fields'][key];return raw[f['offset']:f['offset']+f['size']]
    def pv(raw):return int.from_bytes(raw[:ptr],'little' if e=='<' else 'big')
    result=[]
    for ob in blocks:
        if ob[2]>=len(schemas) or schemas[ob[2]]['name']!='Object':continue
        name=idname(ob)[2:]
        if not name.startswith(('FallenConcreteFragment_','SedimentBankStone_','HIGH_ONLY_')):continue
        block=global_addresses[pv(get(ob,'data'))]
        idx=blocks.index(block)+1;end=idx
        while end<len(blocks) and blocks[end][0]==b'DATA':end+=1
        addresses={**global_addresses,**{b[1]:b for b in blocks[idx:end]}}
        raw=get(block,'attribute_storage');at=pv(fields(raw,'AttributeStorage','dna_attributes'));count=struct.unpack(e+'i',fields(raw,'AttributeStorage','dna_attributes_num')[:4])[0]
        data=addresses[at][4];stride=by_type['Attribute']['length'];attrs={}
        for i in range(count):
            layer=data[i*stride:(i+1)*stride];key=addresses[pv(fields(layer,'Attribute','name'))][4].split(b'\0')[0].decode()
            if key not in ['position','.corner_vert']:continue
            storage=addresses[pv(fields(layer,'Attribute','data'))];kind=schemas[storage[2]]['name'];values=addresses[pv(fields(storage[4],kind,'data'))][4]
            attrs[key]=list(struct.iter_unpack(e+('3f' if key=='position' else 'i'),values))
        result.append({'name':name,**attrs})
    return {'blend_sha256':hashlib.sha256(compressed).hexdigest(),'objects':result}
'''
exec(compile(source,str(ns['reader']),'exec'),ns)
result=ns['inspect'](HERE/'editable_source.blend')
(HERE/'actual_stone_geometry.json').write_text(json.dumps(result,separators=(',',':')),encoding='utf-8')
print(json.dumps({'objects':len(result['objects']),'sha':result['blend_sha256']}))
