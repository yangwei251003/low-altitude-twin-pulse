"""CPU-only selective source/candidate evidence list, no engine or commit."""
from pathlib import Path
import json,hashlib
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];P1=HERE.parent/'p1'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    report=json.loads((HERE/'export_report.json').read_text(encoding='utf-8'))
    candidate=ROOT/'assets/v3/candidates/west_landing_platform/west_landing_platform.glb'
    assert sha(candidate)==report['sha256']==sha(HERE/'west_landing_platform.glb')
    asset={'status':'CANDIDATE_NUMERIC_READBACK_PASS_PENDING_ACTUAL_MAIN','asset':'WestLandingPlatform','glb':'west_landing_platform.glb',
           'sha256':report['sha256'],'bytes':candidate.stat().st_size,'origin_world':[-6,0,-4],
           'groups':{'PlatformAssembly':['PlatformSteel','PlatformPaint'],'LegAssembly':['LegSteel','LegPaint']},
           'triangles':report['mesh_triangles'],'body_local_bounds':report['bounds_per_body'],
           'materials':2,'embedded_PNG':6,'no_collision_lights_cameras':True,
           'source_manifest':'asset_sources/v3/west_landing_platform/delivery_p1/manifest.json'}
    cm=candidate.parent/'asset_manifest.json';cm.write_text(json.dumps(asset,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    paths=[HERE/n for n in ['common.py','bake_source.py','export_asset.py','verify_glb.py','run_stage.py','freeze_delivery.py',
        'DELIVERY.md','bake_report.json','bake_texture_inspection.json','export_report.json','raw_glb_report.json',
        'expected_runtime_triangles.json','west_landing_platform_delivery.blend','west_landing_platform.glb']]
    paths+=sorted((HERE/'textures').glob('*.png'))+sorted((HERE/'provenance').glob('*'))
    for folder in ['run_bake_20261020_081407_306232','run_export_20261020_081614_991419']:
        paths += [HERE/folder/n for n in ['process.json','engine.log']]
    paths += [P1/n for n in ['west_landing_platform_editable.blend','build_source.py','common.py','design.py','material_config.json',
        'run_preview.py','prepare_static.py','prepared_manifest.json','geometry_report.json','inspect_reopen.py','run_inspection.py',
        'resume_preview.py','run_resume_preview.py','SOURCE_CONTRACT.md','SOURCE_REVIEW.md']]
    paths+=sorted((P1/'source_inputs').glob('*.png'))
    paths += [P1/'resume_preview_01'/n for n in ['01-single-object.png','result.json','validation.json']]
    paths += [P1/'reopen_diagnosis/report.json',P1/'failed_first_reopen/source_failure.txt']
    for folder in ['run_preview_20261020_075900_406140','run_inspection_20261020_080143_874359','run_resume_20261020_080416_589309']:
        paths += [P1/folder/n for n in ['process.json','engine.log']]
    paths += [HERE.parent/'ASSET_CARD.md',HERE.parent/'layout_readback.json']
    paths += sorted((ROOT/'references/v3/production/west_landing_platform').glob('*'))
    paths += [candidate,cm]
    paths=sorted(set(p.resolve() for p in paths));assert all(p.is_file() for p in paths)
    rows=[{'path':p.relative_to(ROOT).as_posix(),'bytes':p.stat().st_size,'sha256':sha(p)} for p in paths]
    listing=HERE/'selected_files.txt';listing.write_text('\n'.join(r['path'] for r in rows)+'\n'+(HERE/'manifest.json').relative_to(ROOT).as_posix()+'\n'+listing.relative_to(ROOT).as_posix()+'\n',encoding='utf-8')
    rows.append({'path':listing.relative_to(ROOT).as_posix(),'bytes':listing.stat().st_size,'sha256':sha(listing)})
    manifest={'status':'FROZEN_CANDIDATE_SOURCE_AND_NUMERIC_EVIDENCE_PENDING_MAIN','root':'WestLandingPlatform',
              'files':rows,'file_count_excluding_this_manifest':len(rows),'total_bytes_excluding_this_manifest':sum(r['bytes'] for r in rows),
              'candidate_sha256':report['sha256'],'editable_source':'asset_sources/v3/west_landing_platform/p1/west_landing_platform_editable.blend',
              'scope':'Approved offline source; actual UV/PBR bake and raw/same-byte numeric GLB readback. No actual MAIN claim.',
              'selected_exclusions':['UV/bake/prepared intermediate blends','duplicate source image copies in delivery_p1','duplicate input snapshots','.blend1','unrelated frozen asset versions'],
              'first_failure':'Original strict evaluated-UV SHA failure retained in first process/source_failure plus explicit read-only diagnosis; no geometry rebuild',
              'input_source_sha256':report['source_sha256']}
    (HERE/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    for row in rows:assert sha(ROOT/row['path'])==row['sha256']
    print(json.dumps({'selected_file_count_including_manifest':len(rows)+1,'bytes_excluding_manifest':manifest['total_bytes_excluding_this_manifest'],
                      'manifest_sha256':sha(HERE/'manifest.json'),'candidate_sha256':report['sha256']}))
if __name__=='__main__':main()
