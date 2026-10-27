"""Selective byte manifest only, no engine or production changes."""
from pathlib import Path
import json,hashlib,shutil
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
    r=json.loads((HERE/'export_report.json').read_text(encoding='utf-8'));assert r['status'].endswith('NOT_GAME_VERIFIED')
    original=ROOT/'asset_sources/third_party/ambientCG/Metal012_1K-PNG/provenance.json';atlas=ROOT/'references/v3/production/clinic_pump_shell'
    prov={'scope':'WestLowRoof source inputs; no new download/generation in modeling stage','physical_steel_original_provenance':json.loads(original.read_text(encoding='utf-8')),'physical_steel_current_usage':'Color/Roughness/Metalness/NormalGL only; no external blend executed','generated_colour_atlas':{'source':str(atlas/'material_atlas_v2.png'),'sha256':sha(atlas/'material_atlas_v2.png'),'prompt_original':str(atlas/'prompt_atlas_v2.txt'),'prompt_sha256':sha(atlas/'prompt_atlas_v2.txt'),'meaning':'Existing native imagegen colour atlas; authored roughness and shallow material response are not measured PBR recovered from the picture.'},'copied_inputs':[{'path':str(p.relative_to(ROOT)).replace('\\','/'),'bytes':p.stat().st_size,'sha256':sha(p)} for p in sorted((HERE/'source_inputs').glob('*.png'))]}
    (HERE/'source_material_provenance.json').write_text(json.dumps(prov,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');shutil.copyfile(atlas/'prompt_atlas_v2.txt',HERE/'source_inputs/pump_atlas_prompt_v2.txt')
    files=[]
    files+=list(HERE.glob('*.py'))
    files += [HERE/n for n in ['west_service_room_editable.blend','west_service_room_delivery.blend','west_service_room.glb','source_report.json','bake_report.json','expected_runtime_triangles.json','raw_glb_verified_final.json','export_report.json','source_material_provenance.json','DELIVERY.md','01-single-object-repaired.png','02-26m-scale-source.png']]
    files+=list((HERE/'source_inputs').glob('*'))+list((HERE/'textures').glob('*.png'))
    files += [HERE.parent/'ASSET_CARD.md',HERE.parent/'layout_readback.json']
    files+=list((ROOT/'references/v3/production/west_service_room').glob('*'))
    files += [ROOT/'assets/v3/candidates/west_service_room/west_service_room.glb']
    for d in sorted(HERE.glob('run_*')):
        if d.is_dir():files += [p for p in [d/'process.json',d/'engine.log'] if p.exists()]
    # Selected failures retain visible evidence and original executable text, not duplicate large blends.
    files += [HERE/'failed_cap_overlap'/n for n in ['failure.json','source_report.json','01-single-object.png','common.py','build_source.py']]
    files += list((HERE/'failed_reimport_normal_component').glob('*'))
    files=sorted(set(files));rows=[]
    for p in files:
        assert p.is_file(),p
        rows.append({'path':str(p.relative_to(ROOT)).replace('\\','/'),'bytes':p.stat().st_size,'sha256':sha(p)})
    report={'status':'CANDIDATE_DELIVERED_SOURCE_APPROVED_GAME_PENDING','route_id':'5e455d78-37b2-423b-b660-0cc3185eae49','candidate_sha256':r['sha256'],'source_sha256':r['source_sha256'],'files':rows,'selected_files':len(rows),'selected_bytes':sum(x['bytes'] for x in rows),'excluded':'bake_complete/uv_checkpoint, duplicate failed source blend, repeated input_snapshot, any blend1; old bytes remain on disk','scope':'Source previews and same-byte numeric reimport, not Godot/performance/final area art'}
    (HERE/'delivery_manifest.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');(HERE/'selected_files.txt').write_text('\n'.join(x['path'] for x in rows)+'\n',encoding='utf-8')
    for row in rows:assert sha(ROOT/row['path'])==row['sha256']
    print(json.dumps({'selected_files':len(rows),'bytes':report['selected_bytes'],'manifest_sha256':sha(HERE/'delivery_manifest.json')},indent=2))
if __name__=='__main__':main()
