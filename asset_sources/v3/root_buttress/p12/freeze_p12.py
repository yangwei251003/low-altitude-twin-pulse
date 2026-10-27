"""P12 source-only artifact freeze. Does not touch P11 or any runtime asset."""
from pathlib import Path
import hashlib, json
from datetime import datetime, timezone
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
record=lambda p,purpose:{'path':p.relative_to(ROOT).as_posix(),'sha256':sha(p),'bytes':p.stat().st_size,'purpose':purpose}
report=json.loads((HERE/'p12_source_report.json').read_text(encoding='utf-8'))
p11=HERE.parent/'p11'
old=json.loads((p11/'p11_source_report.json').read_text(encoding='utf-8'))
dependencies=[
    p11/'root_buttress_h10_complete_p11.blend',p11/'build_complete_p11.py',p11/'p11_source_report.json',
    ROOT/'assets/v3/candidates/root_buttress_h10_p11/root_buttress_h10_p11.glb',
    ROOT/'artifacts/v3/art/20261018_051854_h10_p11/02-p11-candidate-near.png',
    ROOT/'artifacts/v3/art/20261018_051854_h10_p11/03-p11-candidate-lower-root.png',
    ROOT/'artifacts/v3/art/20261018_051854_h10_p11/capture.json',
]+[ROOT/f'assets/v3/root_buttress/root_buttress_h{h}.glb' for h in ['10','12','17','3']]
own=[p for p in HERE.rglob('*') if p.is_file() and '__pycache__' not in p.parts and p.suffix!='.blend1' and p.name not in ['manifest.json','selfcheck.json']]
manifest={'stage':'P12 source-only root-section trial; visual issues remain; no baking/export',
 'created_utc':datetime.now(timezone.utc).isoformat(),
 'files':[record(p,'P12 editable source / offline single image / validation record') for p in sorted(own)],
 'readonly_inputs':[record(p,'readonly P11 evidence or frozen runtime control') for p in dependencies],
 'preview':{'file':'h10_p12_root_sections_source.png','source_sha256':report['source_sha256'],'method':'actual editable source, same P11 camera, Cycles CPU2 8 samples; not game'},
 'not_created':['P12 candidate GLB','PBR bake','real game camera capture'],
 'visual_status':'self-review found thicker but visibly interrupted right fork and residual broad cut ends; submitted for root review'}
(HERE/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
checks=[]
def check(name,result):checks.append({'name':name,'pass':bool(result)})
for item in manifest['files']+manifest['readonly_inputs']:
 p=ROOT/item['path'];check('file:'+item['path'],p.is_file() and sha(p)==item['sha256'] and p.stat().st_size==item['bytes'])
check('original_16_geometry_gates',report['all_pass'] and report['passed']==report['total']==16 and all(c['pass'] for c in report['checks']))
check('source_matches_report',sha(HERE/'root_buttress_h10_root_sections_p12.blend')==report['source_sha256'])
check('P11_source_fixed',sha(p11/'root_buttress_h10_complete_p11.blend')=='b5ec56780e72dc12edc40b1651c518e12ed68e6243b62a50a0415ef0bb8f960c')
check('P11_GLB_fixed',sha(ROOT/'assets/v3/candidates/root_buttress_h10_p11/root_buttress_h10_p11.glb')=='d8e67fdaef057a9adb9fb10545eda90d867d730cb446511f735cfbd42d486f1f')
check('P2_runtime_all_fixed',all(sha(ROOT/f'assets/v3/root_buttress/root_buttress_h{h}.glb')==s for h,s in old['runtime_P2_sha256'].items()))
log=(HERE/'build_source.log').read_text(encoding='utf-8',errors='replace')
check('normal_Blender_completion','P12_SOURCE_DONE' in log and 'Blender quit' in log and 'Traceback (most recent call last)' not in log)
check('no_P12_GLB_created',not any((ROOT/'assets/v3/candidates/root_buttress_h10_p12').glob('*.glb')))
result={'stage':'artifact integrity only; does not imply visual approval','manifest_sha256':sha(HERE/'manifest.json'),'checks':checks,'passed':sum(c['pass'] for c in checks),'total':len(checks),'all_pass':all(c['pass'] for c in checks)}
(HERE/'selfcheck.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({k:result[k] for k in ['passed','total','all_pass','manifest_sha256']},ensure_ascii=False))
assert result['all_pass'],[c for c in checks if not c['pass']]
