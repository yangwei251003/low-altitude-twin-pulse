"""No Blender imports or engine launch. Freeze current prepared source inputs."""
from pathlib import Path
import ast,json,hashlib,runpy,datetime
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]

def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    scripts=sorted(HERE.glob('*.py'))
    for p in scripts:ast.parse(p.read_text(encoding='utf-8-sig'))
    config=json.loads((HERE/'material_config.json').read_text(encoding='utf-8'))
    assert config['Steel']['fine_normal_strength_once']==0.25
    design=runpy.run_path(str(HERE/'design.py'));contract=design['static_contract']()
    current=json.loads((ROOT/'data/v3/terrain/i2_clinic_layout.json').read_text(encoding='utf-8'))
    records={s['id']:s for s in current['fixed_solids']}
    saved=json.loads((HERE.parent/'layout_readback.json').read_text(encoding='utf-8'))
    for row in saved['fixed_solids']:assert records[row['id']]==row,row['id']
    inputs=scripts+[HERE/'material_config.json',HERE.parent/'layout_readback.json',
        ROOT/'references/v3/production/west_landing_platform/west_landing_platform_reference_v1.png',
        ROOT/'references/v3/production/clinic_pump_shell/material_atlas_v2.png',
        ROOT/'asset_sources/third_party/ambientCG/Metal012_1K-PNG/provenance.json']
    inputs += [ROOT/'asset_sources/third_party/ambientCG/Metal012_1K-PNG'/('Metal012_1K-PNG_'+key+'.png') for key in ('Color','Roughness','Metalness','NormalGL')]
    locked=[{'path':p.relative_to(ROOT).as_posix(),'bytes':p.stat().st_size,'sha256':digest(p)} for p in inputs]
    result={'status':'STATIC_READY_WAITING_ROOT_ENGINE_WINDOW','prepared_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'route_id':'5e455d78-37b2-423b-b660-0cc3185eae49','locked_inputs':locked,'pure_parameter_check':contract,
            'actual_layout_at_preparation_sha256':digest(ROOT/'data/v3/terrain/i2_clinic_layout.json'),
            'runtime_hierarchy':{'WestLandingPlatform':{'PlatformAssembly':['PlatformSteel','PlatformPaint'],'LegAssembly':['LegSteel','LegPaint']}},
            'planned_preview':{'entry':str(HERE/'run_preview.py'),'expected_seconds':[60,110],'hard_seconds':180,
                               'CPU_threads':2,'private_Job':True,'engine_executed':False,'render_count':1,
                               'expected_peak_memory_GB':[1,3],'memory_estimate_not_OS_limit':True},
            'next_steps':'One actual source image then Root review; no automatic bake or export'}
    (HERE/'prepared_manifest.json').write_text(json.dumps(result,ensure_ascii=False,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({'status':result['status'],'inputs':len(locked),'parameter_check':contract},ensure_ascii=False))

if __name__=='__main__':main()
