"""No Blender: validate actual input arrays, material dependencies and freeze launch inputs."""
from pathlib import Path
import ast,json,math,struct,sys
HERE=Path(__file__).resolve().parent; ROOT=HERE.parents[4]; sys.path.insert(0,str(HERE))
import field_geometry as g
GEOMETRY=ROOT/'scripts_tools/v3/candidates/yard_connector_layout/exports/20261020_062538_edcbfd/geometry.json'
EXPECTED='d337d057cda1beadfa45f915a2c33900713174440e52b4f3d38a759c4bd536f1'
def row(p): return {'path':p.relative_to(ROOT).as_posix(),'bytes':p.stat().st_size,'sha256':g.sha(p)}
def f32(value): return struct.unpack('<f',struct.pack('<f',value))[0]
def main():
    assert g.sha(GEOMETRY)==EXPECTED
    for p in HERE.glob('*.py'): ast.parse(p.read_text(encoding='utf-8'),filename=str(p))
    config=json.loads((HERE/'field_config.json').read_text(encoding='utf-8'))
    data,source,proof=g.read_export(GEOMETRY); rows,metrics=g.partition(source,data['report'],config)
    zero=[]; tri_count=0; max_pos=0.0
    for part in rows:
        p=part['poly']
        for i in range(1,len(p)-1):
            tri=[p[0],p[i],p[i+1]]; ar=g.area(tri)
            if ar==0:continue
            q=[(f32(v[0]+5.7),f32(-(v[1]-19.25))) for v in tri]
            max_pos=max(max_pos,max(math.dist((v[0]+5.7,-(v[1]-19.25)),s) for v,s in zip(tri,q)))
            if g.area(q)==0:
                longest=max(math.dist(tri[k],tri[(k+1)%3]) for k in range(3)); altitude=2*ar/longest
                assert altitude<=1e-5
                zero.append({'source_id':part['source_id'],'visible_id':part['visible_id'],'role':part['role'],'area_m2':ar,'altitude_m':altitude,'world_points':tri})
            else:tri_count+=1
    residual=sum(r['area_m2'] for r in zero); assert residual<=g.AREA_EPS and max_pos<=1e-5
    # Main field topology retains the exact source-domain triangulation; no union-ring fill.
    checks={'status':'STATIC_READY_ACTUAL_ARRAYS_NOT_BLENDER_TESTED','manifest_sha256':EXPECTED,'input_visible_triangles':len(source),
        'actual_partition':metrics,'expected_top_triangles_after_float32':tri_count,'hardware_triangles':40*12,
        'maximum_storage_position_error_m':max_pos,'float32_collinear_triangles':zero,'float32_collinear_area_m2':residual,
        'normal_semantics':'two independent source recipes; soil .32 once, cache1.0; no color height',
        'engine_started':False,'unverified':'bpy construction, native cache images, source renders, runtime GLB/actualMAIN'}
    (HERE/'static_actual_partition.json').write_text(json.dumps(checks,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    read_paths={GEOMETRY}
    for values in data['groups'].values():
        for r in values['files'].values():
            p=GEOMETRY.parent/r['file']; assert g.sha(p)==r['sha256']; read_paths.add(p)
    for relative,expected in data['geometry_input_sha256_before'].items():
        p=ROOT/relative; assert g.sha(p)==expected,('actual export input changed',relative); read_paths.add(p)
    inputs=HERE.parent/'revision2/inputs.json'; read_paths.add(inputs)
    for r in json.loads(inputs.read_text(encoding='utf-8'))['images']:
        p=ROOT/r['path']; assert g.sha(p)==r['sha256']; read_paths.add(p)
    for relative in ['assets/v3/clinic_ground/clinic_ground.glb','assets/v3/clinic_ground/clinic_ground_plain_v2.glb','assets/v3/environment/inspection_pit/inspection_pit.glb']:
        p=ROOT/relative; assert p.is_file(); read_paths.add(p)
    local=sorted(p for p in HERE.iterdir() if p.is_file() and p.name!='prepared.json' and p.suffix in {'.py','.json','.md'})
    prepared={'status':'STATIC_READY_WAITING_ROOT_ENGINE_LEASE','route_id':'5e455d78-37b2-423b-b660-0cc3185eae49',
        'source_preview_seconds_estimate':[120,180],'preview_hard_seconds':180,'cache_hard_seconds':180,'cpu_threads':2,
        'files':[{'path':p.name,'bytes':p.stat().st_size,'sha256':g.sha(p)} for p in local],
        'read_only_inputs':[row(p) for p in sorted(read_paths)],'actual_geometry_manifest':str(GEOMETRY),
        'next_entry':'python -B asset_sources/v3/yard_connector/p1/continuous_field/run_field.py preview',
        'cache_entry_later':'python -B asset_sources/v3/yard_connector/p1/continuous_field/run_field.py cache'}
    (HERE/'prepared.json').write_text(json.dumps(prepared,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'ready':True,'visible_m2':proof['actual_area_m2'],'predicted_triangles':tri_count+480,
        'roles':metrics['by_role_m2'],'float32_residual_area_m2':residual,'maximum_storage_position_error_m':max_pos,'engine_started':False}))
if __name__=='__main__':main()
