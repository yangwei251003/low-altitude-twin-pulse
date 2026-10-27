"""Selective self-contained source/candidate manifest. No engine or shared writes."""
from pathlib import Path
import json,hashlib,shutil
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
    r=json.loads((HERE/'export_report.json').read_text(encoding='utf-8'))
    assert r['status']=='EXPORT_AND_SAME_BYTE_NUMERIC_REIMPORT_PASS_NOT_GAME_VERIFIED'
    source=HERE/'west_offset_room.glb';assert sha(source)==r['sha256']
    target=ROOT/'assets/v3/candidates/west_offset_room/west_offset_room.glb'
    target.parent.mkdir(parents=True,exist_ok=True)
    if target.exists():assert sha(target)==r['sha256'],'Do not replace a different candidate silently'
    else:shutil.copyfile(source,target)
    assert sha(target)==r['sha256']
    original=ROOT/'asset_sources/third_party/ambientCG/Metal012_1K-PNG/provenance.json'
    atlas=ROOT/'references/v3/production/clinic_pump_shell'
    provenance={'scope':'WestOffsetRoof; existing approved material inputs reused without new generation/download',
        'physical_steel_original_provenance':json.loads(original.read_text(encoding='utf-8')),
        'physical_steel_current_usage':'Only Color/Roughness/Metalness/NormalGL PNGs, no external blend or material script executed',
        'generated_colour_atlas':{'source':str(atlas/'material_atlas_v2.png'),'sha256':sha(atlas/'material_atlas_v2.png'),
            'prompt_original':str(atlas/'prompt_atlas_v2.txt'),'prompt_sha256':sha(atlas/'prompt_atlas_v2.txt'),
            'meaning':'Native imagegen colour atlas, not measured height or lighting. Authored roughness and restrained submillimetre bump.'},
        'copied_inputs':[{'path':str(p.relative_to(ROOT)).replace('\\','/'),'bytes':p.stat().st_size,'sha256':sha(p)} for p in sorted((HERE/'source_inputs').glob('*.png'))]}
    (HERE/'source_material_provenance.json').write_text(json.dumps(provenance,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    shutil.copyfile(atlas/'prompt_atlas_v2.txt',HERE/'source_inputs/pump_atlas_prompt_v2.txt')
    files=list(HERE.glob('*.py'))
    files += [HERE/n for n in ['west_offset_room_editable.blend','west_offset_room_delivery.blend','west_offset_room.glb',
        'source_report.json','bake_report.json','expected_runtime_triangles.json','raw_glb_report.json','export_report.json',
        'source_material_provenance.json','DELIVERY.md','01-single-object.png']]
    files += list((HERE/'source_inputs').glob('*'))+list((HERE/'textures').glob('*.png'))
    files += [HERE.parent/'ASSET_CARD.md',HERE.parent/'layout_readback.json']
    files += list((ROOT/'references/v3/production/west_offset_room').glob('*'))+[target]
    for d in sorted(HERE.glob('run_*')):
        if d.is_dir():files += [p for p in [d/'process.json',d/'engine.log'] if p.is_file()]
    files += [HERE/'failed_midband_overlap'/n for n in ['failure.json','build_source.py','source_report.json','01-single-object.png']]
    rows=[]
    for p in sorted(set(files)):
        assert p.is_file(),p
        rows.append({'path':str(p.relative_to(ROOT)).replace('\\','/'),'bytes':p.stat().st_size,'sha256':sha(p)})
    manifest={'status':'CANDIDATE_DELIVERED_SOURCE_APPROVED_GAME_PENDING','route_id':'5e455d78-37b2-423b-b660-0cc3185eae49',
        'candidate_sha256':r['sha256'],'source_sha256':r['source_sha256'],'files':rows,'selected_files':len(rows),
        'selected_bytes':sum(x['bytes'] for x in rows),'excluded':'uv_checkpoint/bake_complete; duplicate failed blend; stage input_snapshot; blend1; all retained on disk',
        'scope':'Editable source, offline preview and same-byte numeric GLB reimport; no Godot/game/performance/whole-area art verification'}
    (HERE/'delivery_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    (HERE/'selected_files.txt').write_text('\n'.join(x['path'] for x in rows)+'\n',encoding='utf-8')
    for row in rows:assert sha(ROOT/row['path'])==row['sha256']
    print(json.dumps({'selected_files':len(rows),'selected_bytes':manifest['selected_bytes'],'manifest_sha256':sha(HERE/'delivery_manifest.json'),'candidate_sha256':sha(target)},indent=2))
if __name__=='__main__':main()
