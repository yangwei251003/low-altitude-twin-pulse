"""Static preparation only; validate parameters, copy provenance, lock inputs."""
from pathlib import Path
import ast,json,hashlib,runpy,datetime
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def main():
    scripts=sorted(HERE.glob('*.py'))
    for p in scripts:ast.parse(p.read_text(encoding='utf-8-sig'))
    cfg=json.loads((HERE/'material_config.json').read_text(encoding='utf-8'))
    assert cfg['Steel']['fine_normal_strength_once']==.25
    design=runpy.run_path(str(HERE/'design.py'));contract=design['static_contract']()
    current=json.loads((ROOT/'data/v3/terrain/i2_clinic_layout.json').read_text(encoding='utf-8'))
    saved=json.loads((HERE.parent/'layout_readback.json').read_text(encoding='utf-8'))
    assert len(current['moving_parts'])==9
    assert [{k:r[k] for k in ('id','offset','size')} for r in current['moving_parts']]==[{k:r[k] for k in ('id','offset','size')} for r in saved['moving_parts']]
    inputs=scripts+[HERE/'material_config.json',HERE.parent/'layout_readback.json',
        ROOT/'references/v3/production/clinic_lift_deck/clinic_lift_deck_reference_v1.png']
    inputs+=sorted((HERE/'source_inputs').glob('*'))+sorted((HERE/'provenance').glob('*'))
    locked=[{'path':p.relative_to(ROOT).as_posix(),'bytes':p.stat().st_size,'sha256':digest(p)} for p in inputs]
    result={'status':'STATIC_READY_NOT_ENGINE_EXECUTED','prepared_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'route_id':'5e455d78-37b2-423b-b660-0cc3185eae49','locked_inputs':locked,'pure_parameter_check':contract,
        'runtime_hierarchy_planned':{'ClinicLiftDeck':['DeckSteel','DeckPaint']},
        'source_hierarchy':'ClinicLiftDeck/DeckAssembly/<independent editable pieces>',
        'source_origin':'moving_bodies.Deck centre; no runtime animation or collision exported',
        'planned_preview':{'entry':str(HERE/'run_preview.py'),'expected_seconds':[35,75],'hard_seconds':120,'CPU_threads':2,
            'private_Job':True,'engine_executed':False,'render_count':1,'expected_peak_memory_GB':[1,2],'memory_estimate_not_OS_limit':True},
        'next_steps':'Root review of source image before any baking or export'}
    (HERE/'prepared_manifest.json').write_text(json.dumps(result,ensure_ascii=False,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({'status':result['status'],'locked_input_files':len(locked),'parameter_check':contract},ensure_ascii=False))
if __name__=='__main__':main()

