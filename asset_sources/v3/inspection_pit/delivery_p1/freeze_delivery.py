"""Compact submission inventory; no engine, no changes to Root-owned inputs."""
from pathlib import Path
import json, hashlib, shutil
from datetime import datetime, timezone

OUT=Path(__file__).resolve().parent
ROOT=OUT.parents[3]
EXPECTED='0e977a7e93df47015ba58ebde01e0a39efbb53c40aba8ed66474e96877f1b30f'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def entry(p,role):return {'path':p.relative_to(ROOT).as_posix(),'role':role,'bytes':p.stat().st_size,'sha256':sha(p)}
def copy_once(src,dst):
    dst.parent.mkdir(exist_ok=True,parents=True)
    if dst.exists():assert sha(src)==sha(dst)
    else:shutil.copyfile(src,dst)
    assert sha(src)==sha(dst)

def main():
    assert ROOT.name=='低空小队-两界共脉'
    target=OUT/'manifest.json';assert not target.exists()
    contract=json.loads((OUT/'input_contract.json').read_text(encoding='utf-8'))
    source=ROOT/contract['source'];assert sha(source)==contract['source_sha256']
    candidate=ROOT/'assets/v3/candidates/inspection_pit/inspection_pit.glb'
    assert sha(candidate)==sha(OUT/'inspection_pit.glb')==EXPECTED
    provenance=[
        ('references/v3/production/clinic_ground/material_atlas_provenance_v1.json','ground_atlas_provenance.json'),
        ('references/v3/production/clinic_ground/material_atlas_prompt_v1.txt','ground_atlas_prompt.txt'),
        ('references/v3/production/i2_canal_revetment/material_front_v2/provenance.json','wall_color_provenance.json'),
        ('references/v3/production/i2_canal_revetment/material_front_v2/prompt_sent.txt','wall_color_prompt_sent.txt'),
        ('references/v3/production/inspection_pit/p3.prompt.txt','pit_reference_prompt.txt'),
    ]
    for origin,name in provenance:copy_once(ROOT/origin,OUT/'provenance'/name)
    selected={}
    def add(p,role):
        assert p.is_file(),str(p)
        selected[p]=role
    for name in ['inspection_pit_editable.blend','inspection_pit_delivery.blend','inspection_pit.glb']:
        add(OUT/name,'delivery')
    for folder in ('source_inputs','textures','provenance'):
        for p in (OUT/folder).iterdir():
            if p.is_file():add(p,folder)
    for p in OUT.glob('*.py'):add(p,'delivery_script')
    for name in ['README.md','ACTUAL_REVIEW.md','PLAN.md','input_contract.json','prepared.json',
                 'prepare_report.json','UV_report.json','bake_report.json','bake_texture_inspection.json',
                 'export_report.json','raw_glb_report.json','preview_report.json']:
        add(OUT/name,'selected_report')
    add(OUT/'same_byte_reimport/01-reference-oblique.png','actual_reimport_image')
    # The packed reimport scene is recoverable from GLB + source studio, so omit it.
    stages=[]
    for folder in sorted(OUT.glob('run_*_20261020_*')):
        process=json.loads((folder/'process.json').read_text(encoding='utf-8'))
        assert process['exit_code']==0 and process['remaining_owned_processes']==0 and not process['error_lines']
        stages.append({k:process[k] for k in ('stage','pid','elapsed_seconds','hard_seconds','exit_code','remaining_owned_processes')})
        add(folder/'process.json','actual_stage_process');add(folder/'engine.log','actual_stage_log')
    for name in ('inspection_pit_editable.blend','01-reference-oblique.png','source_report.json',
                 'build_source.py.txt','completed.json','source.log','inputs.json','inputs_after.json'):
        add(source.parent/name,'root_frozen_final_source_readonly')
    for name in ('build_source.py','run_preview.py'):
        add(OUT.parent/'p1'/name,'root_source_script_readonly')
    add(ROOT/'references/v3/production/inspection_pit/p3-geometry-constrained.png','approved_AI_reference_readonly')
    add(candidate,'authorized_same_byte_candidate_copy')
    rows=[entry(p,selected[p]) for p in sorted(selected)]
    raw=json.loads((OUT/'raw_glb_report.json').read_text(encoding='utf-8'))
    manifest={
        'schema':'inspection-pit-compact-delivery-1','created_utc':datetime.now(timezone.utc).isoformat(),
        'routeId':'5e455d78-37b2-423b-b660-0cc3185eae49',
        'status':'ROOT_VIEWED_SOURCE_AND_REIMPORT_ACCEPTED_FOR_GODOT_CANDIDATE',
        'not_claimed':['actual Godot art acceptance','physical flight or work-chain validation','whole-area final art'],
        'root':raw['root'],'world_anchor':contract['world_anchor'],'local_AABB':raw['AABB'],
        'triangles':raw['triangles'],'meshes':raw['nodes'],'glb_sha256':EXPECTED,
        'editable_relative_dependencies':'source_inputs/ (also packed)',
        'delivery_relative_dependencies':'textures/ plus source_inputs/ for retained unused source datablocks',
        'GLB_dependencies':'nine exact embedded PNGs',
        'selected_file_count':len(rows),'selected_bytes':sum(r['bytes'] for r in rows),'files':rows,'stages':stages,
        'excluded':['prepared_bake.blend','bake_complete.blend','checkpoint.blend','failed/backup blend files',
                    'all input_snapshot duplicates','expected_low_triangles.json','expected_runtime_triangles.json',
                    'face_mapping.json','same_byte_reimport/reimported_candidate.blend','historical prior previews'],
        'excluded_note':'Remain intact locally; not required for reopening delivered editable/baked source or viewing GLB.',
        'provenance_copies':[{'original':a,'copy':'provenance/'+b} for a,b in provenance],
        'readback_verified':True,
    }
    target.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    for row in json.loads(target.read_text(encoding='utf-8'))['files']:
        p=ROOT/row['path'];assert p.stat().st_size==row['bytes'] and sha(p)==row['sha256'],row['path']
    print(json.dumps({'files':len(rows),'bytes':manifest['selected_bytes'],'manifest_sha256':sha(target),
                      'candidate_sha256':sha(candidate),'readback':True},ensure_ascii=True))

if __name__=='__main__':main()
