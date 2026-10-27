"""Finalize P12 evidence hashes only after actual same-byte GLB reimport."""
from pathlib import Path
import json,hashlib
from datetime import datetime,timezone
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
record=lambda p,purpose:{'path':p.relative_to(ROOT).as_posix(),'bytes':p.stat().st_size,'sha256':sha(p),'purpose':purpose}
src=json.loads((HERE/'p12_source_report.json').read_text(encoding='utf-8'))
exp=json.loads((HERE/'p12_export_report.json').read_text(encoding='utf-8'))
bake=json.loads((HERE/'p12_bake_report.json').read_text(encoding='utf-8'))
readback=json.loads((HERE/'p12_glb_readback.json').read_text(encoding='utf-8'))
glb=ROOT/exp['glb']
assert src['source_sha256']=='eabf6a942e075ab43934adbee3d84daf40d38aedb709fb16829a304b8596dd0c'
assert src['all_pass'] and readback['all_pass']
own=[p for p in HERE.rglob('*') if p.is_file() and '__pycache__' not in p.parts and p.suffix!='.blend1'
     and p not in [HERE/'manifest.json',HERE/'selfcheck.json']]
deps=[HERE.parent/'p11/root_buttress_h10_complete_p11.blend',HERE.parent/'p11/manifest.json',
      ROOT/'assets/v3/candidates/root_buttress_h10_p11/root_buttress_h10_p11.glb',
      ROOT/'artifacts/v3/art/20261018_051854_h10_p11/02-p11-candidate-near.png',
      ROOT/'artifacts/v3/art/20261018_051854_h10_p11/03-p11-candidate-lower-root.png',
      ROOT/'artifacts/v3/art/20261018_051854_h10_p11/capture.json']
deps += [ROOT/f'assets/v3/root_buttress/root_buttress_h{h}.glb' for h in src['runtime_P2_sha256']]
def purpose(p):
 if 'recessed_roots_v1' in p.parts:return 'historical recessed-root visual reject; exact bytes archived; do not execute relocated scripts'
 if p.name=='h10_p12_root_sections_source.png':return 'current editable source offline CPU image, not game'
 if p.name=='h10_p12_same_byte_glb_preview.png':return 'actual frozen GLB reimport offline CPU image, not game'
 if p.parent.name=='textures':return 'external explicit PBR map; original Sap copy or actual stone/bark atlas bake'
 return 'P12 editable source, reproducible workflow, contract or validation evidence'
manifest={'stage':'P12 root-only complete single-height candidate, not final art or game physics acceptance','created_utc':datetime.now(timezone.utc).isoformat(),
 'files':[record(p,purpose(p)) for p in sorted(own)]+[record(glb,'explicit frozen P12 candidate GLB; runtime P2 untouched')],
 'readonly_dependencies':[record(p,'readonly upstream reference or frozen prior/runtime control') for p in deps],
 'image_provenance':{
  'h10_p12_root_sections_source.png':{'input':'root_buttress_h10_root_sections_p12.blend','input_sha256':src['source_sha256'],'method':'actual editable source Cycles CPU2 8 samples, same oblique camera as P11'},
  'h10_p12_same_byte_glb_preview.png':{'input':exp['glb'],'input_sha256':exp['glb_sha256'],'method':'delete source objects; import exact GLB bytes; same studio CPU2 8 samples'}},
 'authorized_bounds':src['authorized_bounds'],
 'limits':['P12 complete Crown sweep, scene physics, real GPU camera and performance require new root-thread checks','positive X/Z allowance changed by explicit root authorization; not original-AABB passing','wide cut ends remain; not final artistic approval'],
 'exclusions':['.blend1 backups','__pycache__','top-level manifest/selfcheck to avoid recursive hashes']}
(HERE/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
checks=[]
def check(name,ok,detail=None):checks.append({'name':name,'pass':bool(ok),'detail':detail})
for item in manifest['files']+manifest['readonly_dependencies']:
 p=ROOT/item['path'];check('file:'+item['path'],p.is_file() and sha(p)==item['sha256'] and p.stat().st_size==item['bytes'])
check('source_16_geometry_checks',src['passed']==src['total']==16 and src['all_pass'] and all(c['pass'] for c in src['checks']))
check('actual_GLBreimport_39_checks',readback['passed']==readback['total']==39 and readback['all_pass'] and all(c['pass'] for c in readback['checks']))
check('GLB_hash_matches_readback_export',sha(glb)==exp['glb_sha256']==readback['glb_sha256'])
check('author_source_hash_matches_all_reports',sha(HERE/'root_buttress_h10_root_sections_p12.blend')==src['source_sha256']==exp['source_sha256']==bake['source_sha256'])
check('ready_source_hash_matches_all_reports',sha(ROOT/exp['ready_source'])==exp['ready_source_sha256']==bake['ready_source_sha256']==readback['ready_source_sha256'])
check('source_deleted_before_GLBreimport',readback['source_deleted_before_import'])
check('geometry_preserved_through_bake',bake['source_geometry_unchanged'] and exp['source_geometry_unchanged_through_bake'])
check('P11_source_frozen',sha(HERE.parent/'p11/root_buttress_h10_complete_p11.blend')=='b5ec56780e72dc12edc40b1651c518e12ed68e6243b62a50a0415ef0bb8f960c')
check('P11_GLB_frozen',sha(ROOT/'assets/v3/candidates/root_buttress_h10_p11/root_buttress_h10_p11.glb')=='d8e67fdaef057a9adb9fb10545eda90d867d730cb446511f735cfbd42d486f1f')
check('runtime_P2_frozen',all(sha(ROOT/f'assets/v3/root_buttress/root_buttress_h{h}.glb')==v for h,v in src['runtime_P2_sha256'].items()))
archive=HERE/'recessed_roots_v1';arch=json.loads((archive/'archive_inventory.json').read_text(encoding='utf-8'))
check('recessed_trial_archived_exact_bytes',all(sha(archive/item['name'])==item['sha256'] and (archive/item['name']).stat().st_size==item['bytes'] for item in arch['files']))
for item in bake['atlas_maps']+bake['sap_maps']:
 p=Path(item['file']);p=p if p.is_absolute() else ROOT/p
 check('texture:'+p.name,sha(p)==item['sha256'])
for name,marker in [('build_source.log','P12_SOURCE_DONE'),('bake_p12.log','P12_BAKE_ONLY_DONE_NO_RUNTIME_WRITE'),('export_p12.log','P12_EXPORT'),('verify_p12.log','P12_SAME_BYTE_READBACK_DONE')]:
 log=(HERE/name).read_text(encoding='utf-8',errors='replace');check('completion:'+name,marker in log and 'Traceback (most recent call last)' not in log)
out={'stage':'file integrity and report consistency; not further graphics/physics testing','manifest_sha256':sha(HERE/'manifest.json'),'candidate_sha256':sha(glb),'checks':checks,'passed':sum(c['pass'] for c in checks),'total':len(checks),'all_pass':all(c['pass'] for c in checks)}
(HERE/'selfcheck.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({k:out[k] for k in ['passed','total','all_pass','manifest_sha256','candidate_sha256']},ensure_ascii=False))
assert out['all_pass'],[c for c in checks if not c['pass']]
