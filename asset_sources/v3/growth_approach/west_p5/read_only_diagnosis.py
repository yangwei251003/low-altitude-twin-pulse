"""Read only original 4.02 source SDNA + saved P5 report; no Blender/GPU/model.
Reuses frozen parser definitions in memory, never executes its output writer.
"""
import ast,json,struct
from pathlib import Path
BASE=Path(__file__).resolve().parent
parser=BASE.parent/'resource_recovery/read_blend_lods.py'
tree=ast.parse(parser.read_text(encoding='utf-8'))
tree.body=[n for n in tree.body if isinstance(n,(ast.Import,ast.ImportFrom,ast.FunctionDef)) or isinstance(n,ast.Assign) and not any(isinstance(t,ast.Name) and t.id=='out' for t in n.targets)]
# Keep zstd signature declarations but remove the frozen parser's final writes.
for n in tree.body:
    if isinstance(n,ast.FunctionDef) and n.name=='inspect':
        n.body[-1]=ast.Return(value=ast.Call(func=ast.Name(id='locals',ctx=ast.Load()),args=[],keywords=[]))
ns={'__file__':str(parser)};exec(compile(ast.fix_missing_locations(tree),str(parser),'exec'),ns)
report=json.loads((BASE/'geometry_report.json').read_text())
objects=[]
for item in report['inputs']:
    state=ns['inspect'](BASE.parents[3]/item['file'])
    blocks=state['blocks'];schemas=state['schemas'];by_type=state['by_type'];get=state['get'];idname=state['idname']
    by_address={b[1]:b for b in blocks};endian=state['e']
    def field(blob,typename,key):
        f=by_type[typename]['fields'][key]
        return blob[f['offset']:f['offset']+f['size']]
    def pointer(blob):return int.from_bytes(blob,'little' if endian=='<' else 'big')
    for b in blocks:
        if b[2]>=len(schemas) or schemas[b[2]]['name']!='Object' or idname(b)[2:]!=item['source_object']:continue
        raw=get(b,'modifiers');address=pointer(field(raw,'ListBase','first'));mods=[]
        while address:
            m=by_address[address];schema=schemas[m[2]]
            raw=m[4] if schema['name']=='ModifierData' else field(m[4],schema['name'],'modifier')
            mods.append({'name':field(raw,'ModifierData','name').split(b'\0')[0].decode(),'sdna_type':schema['name'],'type_enum':struct.unpack(endian+'i',field(raw,'ModifierData','type'))[0]})
            address=pointer(field(raw,'ModifierData','next'))
        objects.append({'object':item['name'],'original_source_modifiers':mods})
cuts=[]
for ob in objects:
    ops=[o for o in report['operations'] if o['object']==ob['object']]
    start=ops[0]['before']['signed_volume']
    check=next(c for c in report['checks'] if c['name']=='closed_positive_nonzero_'+ob['object'])
    final=check['signed_volume_m3']
    cuts.append({'object':ob['object'],'placed_original_m3':start,'final_raw_mesh_m3':final,'retained_volume_fraction':final/start})
result={'read_only':True,'blender_or_gpu_started':False,'objects':objects,'cut_volumes':cuts,
    'limitations':['raw mesh volumes, before any remaining modifiers','modifier list read from the original 4.02 source, not the saved 5.2 candidate','new Blender 5.2 binary header is not supported by the prior 4.02 reader; no claim to have reread candidate modifiers','no candidate-only ID mask exists; cannot measure precise occlusion fraction from one combined PNG','manual visible silhouette estimate is not an isolated projection ratio']}
(BASE/'read_only_diagnosis.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps(result,ensure_ascii=False,indent=2))
