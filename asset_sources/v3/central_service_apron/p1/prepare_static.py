"""CPU-only preparation. Does not import bpy or launch any engine."""
from pathlib import Path
import sys,ast,json,math,shutil
sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
sys.path.insert(0,str(HERE))
import geometry as geo

def main():
    for p in HERE.glob('*.py'):ast.parse(p.read_text(encoding='utf-8'),filename=str(p))
    config=json.loads((HERE/'config.json').read_text(encoding='utf-8'))
    inputs=json.loads((HERE/'inputs.json').read_text(encoding='utf-8'))
    for row in inputs['maps']:
        assert geo.sha(HERE/row['local'])==row['sha256'] and (HERE/row['local']).stat().st_size==row['bytes']
    assert geo.sha(ROOT/'data/v3/terrain/i2_clinic_layout.json')==config['layout_sha256']
    path=ROOT/config['historical_geometry'];assert geo.sha(path)==config['historical_geometry_sha256']
    source,input_report=geo.read_input(path,config['historical_group'])
    rows,remainder,report=geo.partition(source,config)
    triangles=[];residuals=[];per_part={};max_bary_error=0.0
    original={r['input_triangle']:r for r in source}
    for row in rows:
        ts,rs=geo.triangulate(row,config['origin']);triangles.extend(ts);residuals.extend(rs)
        per_part[row['part']]=per_part.get(row['part'],0)+len(ts)
        old=original[row['input_triangle']]
        for p,w in zip(row['poly'],row['barycentric']):
            actual=geo.interpolate(old['corners']['faces'],w)
            err=math.dist((p[0],0,p[1]),actual);max_bary_error=max(max_bary_error,err)
            assert err<=1e-5
    assert len(triangles)<=config['maximum_triangles']
    assert abs(report['replacement_area_m2']-config['expected_historical_area_m2'])<.0005
    assert sum(r['area_m2'] for r in residuals)<=1e-6
    # Independent polygon-set checks are optional diagnostics only; core reader
    # and output do NOT require or use Shapely hulls or reconstructed rings.
    independent={'available':False}
    try:
        from shapely.geometry import Polygon,box
        from shapely.ops import unary_union
        selected=unary_union([Polygon(r['poly']) for r in rows])
        lo,hi,bottom,top=config['outer_rect_x0_x1_z0_z1']
        expected=unary_union([Polygon(r['poly']) for r in source]).intersection(box(lo,bottom,hi,top))
        for fp in config['footprints']:
            x0,x1,z0,z1=fp['rect'];expected=expected.difference(box(x0,z0,x1,z1))
        delta=selected.symmetric_difference(expected).area
        under=next(x for x in config['footprints'] if x['id']=='UnderDeckFloor')['rect']
        floor_area=selected.intersection(box(under[0],under[2],under[1],under[3])).area
        assert delta<=1e-6 and floor_area<=1e-8
        independent={'available':True,'symmetric_difference_m2':delta,'UnderDeckFloor_overlap_m2':floor_area,
                     'sum_vs_union_overlap_m2':sum(geo.area(r['poly']) for r in rows)-selected.area}
    except ImportError:pass
    report.update(status='STATIC_HISTORICAL_INPUT_ONLY_NOT_LIVE_OR_RENDERED',actual_float32_triangles=len(triangles),
                  per_editable_part_triangles=per_part,maximum_barycentric_reconstruction_error_m=max_bary_error,
                  maximum_float32_position_error_m=max(t['max_position_error_m'] for t in triangles),
                  exact_float32_collinear_residuals=residuals,independent_set_check=independent,input=input_report,
                  note_source_area='Original Godot report accumulates float32 area; CPU area uses exact stored float32 vertices promoted to double. Per-triangle replacement+remainder is compared in double.')
    (HERE/'static_partition.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    files=[]
    for p in sorted(HERE.iterdir()):
        if p.is_file() and p.suffix in {'.py','.json','.md'} and p.name!='prepared.json':
            files.append({'path':p.name,'sha256':geo.sha(p),'bytes':p.stat().st_size})
    for row in inputs['maps']:
        files.append({'path':row['local'],'sha256':row['sha256'],'bytes':row['bytes']})
    live=None
    if (HERE/'live_verification.json').exists():
        live=json.loads((HERE/'live_verification.json').read_text(encoding='utf-8'))
        for row in live['copied_inputs']:
            assert geo.sha(HERE/row['path'])==row['sha256'];files.append(row)
    context=json.loads((HERE/'context.json').read_text(encoding='utf-8'))
    for row in context:assert geo.sha(ROOT/row['path'])==row['sha256']
    contract={'status':'PREPARED_LIVE_INPUT_VERIFIED_WAIT_ENGINE_LEASE' if live else 'PREPARED_WAIT_ROOT_LIVE_REMAINDER_AND_ENGINE_LEASE','files':files,
              'read_only_context':context,'layout':{'path':'data/v3/terrain/i2_clinic_layout.json','sha256':config['layout_sha256']},
              'historic_input':input_report,'live_verification':None if not live else {'path':'live_verification.json','sha256':geo.sha(HERE/'live_verification.json'),'live_geometry_sha256':live['live_geometry_sha256']},'expected_triangles_static':len(triangles),
              'run':'python run_preview.py --live-geometry ABSOLUTE_NEW_EXPORT_GEOMETRY_JSON --group remainder --sha256 ACTUAL_NEW_MANIFEST_SHA',
              'limits':{'seconds':180,'cpu_threads':2,'renderer':'Cycles CPU','one_image':True,'estimated_peak_memory_gib':3}}
    (HERE/'prepared.json').write_text(json.dumps(contract,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'status':contract['status'],'triangles':len(triangles),'area_m2':report['replacement_area_m2'],
                      'parts':len(per_part),'max_per_original_area_error_m2':report['max_conservation_error_m2'],
                      'independent':independent},ensure_ascii=False))

if __name__=='__main__':main()
