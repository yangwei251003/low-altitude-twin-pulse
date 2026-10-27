"""Read Root's completed live export. Pure CPU, no engine or source mutation."""
from pathlib import Path
import sys,json,shutil,math
sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
sys.path.insert(0,str(HERE))
import geometry as geo
LIVE=ROOT/'artifacts/v3/central-ground-20261020_095828'
SHA='5a854ff84970fedfb54764158ea039f4ef4f45f6707b63f1867b2127d456ccef'

def main():
    path=LIVE/'geometry.json';assert geo.sha(path)==SHA
    data=json.loads(path.read_text(encoding='utf-8'))
    audit=json.loads((LIVE/'inputs.json').read_text(encoding='utf-8'))
    assert audit['unchanged'] and audit['before']==audit['after']
    assert audit['process']['passed'] and audit['process']['remaining_owned_processes']==0
    current=[{'path':p,'sha256':digest,'current_sha256':geo.sha(ROOT/p)} for p,digest in audit['after'].items()]
    assert all(r['sha256']==r['current_sha256'] for r in current),'live export inputs changed before this static verification'
    c=json.loads((HERE/'config.json').read_text(encoding='utf-8'))
    old_path=ROOT/c['historical_geometry'];old=json.loads(old_path.read_text(encoding='utf-8'))
    group=data['groups']['remainder'];old_group=old['groups']['remainder']
    comparison=[]
    for name,row in group['files'].items():
        a=LIVE/row['file'];b=old_path.parent/old_group['files'][name]['file']
        equal=a.read_bytes()==b.read_bytes();assert equal,(name,'unexpected actual geometry/attribute change')
        comparison.append({'channel':name,'bytes':a.stat().st_size,'sha256':geo.sha(a),'historical_equal_bytes':equal})
    ids=group['source_final_triangle_ids'];assert ids==list(range(105))
    source,report=geo.read_input(path,'remainder');rows,remainder,partition=geo.partition(source,c)
    old_source,_=geo.read_input(old_path,'remainder');old_rows,_,old_partition=geo.partition(old_source,c)
    assert [(r['poly'],r['role'],r['part']) for r in rows]==[(r['poly'],r['role'],r['part']) for r in old_rows]
    triangles=[];residuals=[]
    for row in rows:
        ts,rs=geo.triangulate(row,c['origin']);triangles.extend(ts);residuals.extend(rs)
        assert row['source_final_triangle']==row['input_triangle']
    assert len(triangles)==1148 and abs(partition['replacement_area_m2']-c['expected_historical_area_m2'])<.0005
    from shapely.geometry import Polygon,box
    from shapely.ops import unary_union
    selected=unary_union([Polygon(r['poly']) for r in rows])
    x0,x1,z0,z1=c['outer_rect_x0_x1_z0_z1']
    expected=unary_union([Polygon(r['poly']) for r in source]).intersection(box(x0,z0,x1,z1))
    for fp in c['footprints']:
        a,b,d,e=fp['rect'];expected=expected.difference(box(a,d,b,e))
    delta=selected.symmetric_difference(expected).area
    floor_overlap=selected.intersection(box(-2,-6,2,-2)).area
    assert delta<=1e-6 and floor_overlap==0
    local=HERE/'live_input';local.mkdir(exist_ok=True)
    copied=[]
    for p in [path,LIVE/'inputs.json']+[LIVE/r['file'] for r in group['files'].values()]:
        q=local/p.name
        if q.exists():assert q.read_bytes()==p.read_bytes(),'do not overwrite a different live snapshot'
        else:shutil.copyfile(p,q)
        copied.append({'path':q.relative_to(HERE).as_posix(),'bytes':q.stat().st_size,'sha256':geo.sha(q)})
    result={'status':'LIVE_INPUT_VERIFIED_STATIC_BUILD_READY_NO_ENGINE_RUN',
            'live_geometry':str(path),'live_geometry_sha256':SHA,'input_report':report,
            'four_arrays_vs_historical':comparison,'live_process':audit['process'],'current_seven_inputs':current,
            'current_ids':ids,'historical_id_crosswalk':[{'current_triangle_id':i,'old_pre_yard_triangle_id':old_group['source_final_triangle_ids'][i]} for i in ids],
            'current_id_contract':'All new source_face_mapping IDs use current remainder0..104. Old pre-yard IDs are reference-only crosswalk.',
            'partition':partition,'actual_float32_triangles':len(triangles),'residual_area_m2':sum(r['area_m2'] for r in residuals),
            'symmetric_difference_m2':delta,'UnderDeckFloor_overlap_m2':floor_overlap,
            'copied_inputs':copied,'scope':'Root actual read-only live World build verified by CPU; no new MAIN/physics/render evidence'}
    (HERE/'live_verification.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:result[k] for k in ['status','live_geometry_sha256','actual_float32_triangles','symmetric_difference_m2','UnderDeckFloor_overlap_m2']}))

if __name__=='__main__':main()
