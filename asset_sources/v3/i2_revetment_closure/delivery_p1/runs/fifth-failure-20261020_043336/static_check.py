"""Pure Python checks only. Never imports bpy or launches an engine."""
from pathlib import Path
import ast,sys,json,math,hashlib,tempfile
sys.dont_write_bytecode=True
if hasattr(sys.stdout,'reconfigure'):sys.stdout.reconfigure(encoding='utf-8')
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
sys.path.insert(0,str(HERE))
from transfer import *

def main():
    for path in HERE.glob('*.py'):compile(path.read_text(encoding='utf-8'),str(path),'exec')
    original=ROOT/'asset_sources/v3/i2_canal_revetment/delivery_p4/i2_canal_revetment_p4.glb'
    raw,images=original_glb_triangles(original);source=[]
    for index,(points,uvs) in enumerate(raw.items()):
        if index%41:continue
        uv=uvs[0]
        source.append({'p':points,'material':'fixture','uv':{'SurfaceMetric':uv,'FrontFaceUV':uv},
            'attrs':{'SourceX':[q[0] for q in points]},'bake':uv})
        if len(source)==126:break
    transfer=SourceTransfer(source);checks=0
    for row in source:
        weights=[(.6,.2,.2),(.2,.6,.2),(.2,.2,.6)]
        target={'p':[mix(row['p'],w) for w in weights],'material':'fixture',
            'uv':{name:[mix(values,w) for w in weights] for name,values in row['uv'].items()},
            'attrs':{name:[sum(v*w for v,w in zip(values,ws)) for ws in weights] for name,values in row['attrs'].items()}}
        actual=transfer.map_triangle(target,'real_glb_subtriangle_fixture')
        expected=[mix(row['bake'],w) for w in weights]
        assert max(abs(a-b) for u,v in zip(actual,expected) for a,b in zip(u,v))<2e-6
        assert transfer.map_triangle(target,'exact_repeat')==actual
        checks+=1
    assert transfer.memo_hits==126
    bad=dict(target,p=[(q[0]+10,q[1],q[2]) for q in target['p']])
    try:transfer.map_triangle(bad,'displaced_negative')
    except AssertionError:pass
    else:raise AssertionError('displaced geometry accepted')
    # Extract only pure helpers instead of importing the Blender stage.
    tree=ast.parse((HERE/'prepare.py').read_text(encoding='utf-8'))
    functions=[n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name in ('encoded','digest','map_object')]
    with tempfile.TemporaryDirectory(dir=HERE,prefix='static-cache-') as temporary:
        temp=Path(temporary);(temp/'transfer.py').write_bytes((HERE/'transfer.py').read_bytes())
        scope=dict(json=json,hashlib=hashlib,math=math,HERE=temp,sha=sha,SOURCE_SHA='fixture_source',
            REFERENCE_SHA='fixture_reference',GLB_SHA=sha(original),PLAN_SHA='fixture_plan',
            GEOMETRY_EPS=GEOMETRY_EPS,SOURCE_UV_EPS=SOURCE_UV_EPS,ATTRIBUTE_EPS=ATTRIBUTE_EPS)
        exec(compile(ast.Module(body=functions,type_ignores=[]),'cache_helper','exec'),scope)
        fixture_transfer=SourceTransfer([row]);rows=[{'slot':0,'source_triangle':7,'target':target}]
        first,rec1=scope['map_object']('fixture',rows,fixture_transfer)
        def cannot_remap(*args):raise AssertionError('cache unexpectedly remapped')
        fixture_transfer.map_triangle=cannot_remap
        second,rec2=scope['map_object']('fixture',rows,fixture_transfer)
        assert first==second and not rec1['reused'] and rec2['reused']
        cache=temp/rec1['path'];saved=json.loads(cache.read_text(encoding='utf-8'))
        saved['payload']['bake_uv'][0][0][0]+=.1;cache.write_text(json.dumps(saved),encoding='utf-8')
        try:scope['map_object']('fixture',rows,fixture_transfer)
        except AssertionError as error:assert 'payload hash' in str(error)
        else:raise AssertionError('tampered cache accepted')
    report={'status':'STATIC_ONLY_PENDING_ENGINE','python_files':{f.name:sha(f) for f in HERE.glob('*.py')},
        'original_glb_sha256':sha(original),'actual_original_images':images,
        'real_original_glb_subtriangle_fixtures':checks,'exact_repeat_memo_fixtures':transfer.memo_hits,
        'displaced_geometry_rejected':True,'object_cache_roundtrip_no_remap':True,'altered_cache_rejected':True,
        'predicted_evaluated_source_triangles':32536,'actual_count_diagnostic_pending':True,
        'limitation':'No Blender started; final count, cap UV and prepared checkpoint still require real run.'}
    (HERE/'static_validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(report,ensure_ascii=False))

if __name__=='__main__':main()
