"""Read actual saved material links through SDNA; no Blender process or image edits."""
from pathlib import Path
import json
HERE=Path(__file__).resolve().parent
wrapper=(HERE/'read_proxy_arrays.py').read_text(encoding='utf-8')
prefix=wrapper[:wrapper.index("source=source[:source.index(")]
ns={'__file__':str(HERE/'read_proxy_arrays.py')};exec(prefix,ns)
source=ns['source'];source=source[:source.index('    meshes={};objects=[]')]+r'''
    addresses={b[1]:b for b in blocks}
    def pv(raw):return int.from_bytes(raw[:ptr],'little' if e=='<' else 'big')
    def text(raw):return raw.split(b'\0')[0].decode('utf-8','replace')
    def linked_list(owner,key):
        address=pv(get(owner,key));result=[]
        while address:
            item=addresses[address];result.append(item);address=pv(get(item,'next'))
        return result
    mat=next(b for b in blocks if b[2]<len(schemas) and schemas[b[2]]['name']=='Material' and idname(b)[2:]=='GroundTransition_PreviewContactAO_P8')
    tree=addresses[pv(get(mat,'nodetree'))]
    nodes=linked_list(tree,'nodes');links=linked_list(tree,'links');node_names={b[1]:text(get(b,'name')) for b in nodes}
    out=[]
    for b in nodes:
        row={'name':text(get(b,'name')),'type':text(get(b,'idname'))}
        image=pv(get(b,'id'))
        if image:
            image_block=addresses[image];row['data_id']=idname(image_block)
            fields=schemas[image_block[2]]['fields']
            if 'filepath' in fields:row['image_filepath']=text(get(image_block,'filepath'))
        store=pv(get(b,'storage'))
        if store:
            block=addresses[store];kind=schemas[block[2]]['name'];row['storage_type']=kind
            if kind=='NodeShaderNormalMap':
                row['normal_space_enum']=integer(block,'space');row['uv_map']=text(get(block,'uv_map'))
            if kind=='NodeShaderUVMap':row['uv_map']=text(get(block,'uv_map'))
        values={}
        for socket in linked_list(b,'inputs'):
            key=text(get(socket,'identifier'));address=pv(get(socket,'default_value'))
            if address and key in ['Strength','Emission Strength']:
                value=addresses[address];kind=schemas[value[2]]['name']
                if kind=='bNodeSocketValueFloat':values[key]=struct.unpack(e+'f',get(value,'value')[:4])[0]
        if values:row['unlinked_default_values']=values
        out.append(row)
    edges=[]
    for b in links:
        fn=pv(get(b,'fromnode'));tn=pv(get(b,'tonode'));fs=addresses[pv(get(b,'fromsock'))];ts=addresses[pv(get(b,'tosock'))]
        edges.append({'from_node':node_names[fn],'from_socket':text(get(fs,'identifier')),'to_node':node_names[tn],'to_socket':text(get(ts,'identifier'))})
    return {'blend_sha256':hashlib.sha256(compressed).hexdigest(),'material':idname(mat)[2:],'nodes':out,'links':edges,'method':'Read saved .blend SDNA node-tree links; no Blender execution'}
'''
exec(compile(source,str(ns['reader']),'exec'),ns)
result=ns['inspect'](HERE/'baked_source.blend')
(HERE/'actual_material_graph.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(result,ensure_ascii=True,indent=2))
