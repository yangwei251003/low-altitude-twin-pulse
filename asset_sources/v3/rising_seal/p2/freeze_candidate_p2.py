"""Final artifact/provenance integrity, separate from artistic/game acceptance."""
from pathlib import Path
import json,hashlib
from datetime import datetime,timezone
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
ex=json.loads((HERE/'export_report.json').read_text(encoding='utf-8'));read=json.loads((HERE/'glb_readback.json').read_text(encoding='utf-8'));source=json.loads((HERE/'source_report.json').read_text(encoding='utf-8'));bake=json.loads((HERE/'bake_report.json').read_text(encoding='utf-8'))
glb=ROOT/ex['glb'];out=glb.parent
excluded={HERE/'manifest.json',HERE/'selfcheck.json'}
files=[p for p in HERE.rglob('*') if p.is_file() and '__pycache__' not in p.parts and p.suffix!='.blend1' and p not in excluded]
files+=[glb]
def record(p):
 historical=any(s in p.parts for s in ['envelope_reject_v1','occluded_roots_v1','continuous_roots_v2','pre_coincident_cleanup']) or p.name.startswith(('refinement_','pre_','initial_','ngon_'))
 return {'path':p.relative_to(ROOT).as_posix(),'sha256':sha(p),'bytes':p.stat().st_size,'purpose':'historical stage/negative evidence' if historical else 'current candidate source/export/evidence'}
manifest={'stage':'single P2 candidate; not final art or game acceptance','created_utc':datetime.now(timezone.utc).isoformat(),'glb_sha256':sha(glb),'source_sha256':sha(HERE/'rising_seal_source_p2.blend'),'ready_sha256':sha(ROOT/ex['ready_source']),'files':[record(p) for p in sorted(files)],'readonly_inputs':[record(ROOT/p) for p in ex['readonly_inputs']],'images':{'rising_seal_source_p2.png':{'method':'editable final source offline basic material render','source_sha256':source['source_sha256']},'rising_seal_p2_same_byte_glb_preview.png':{'method':'delete author geometry; import exact GLB bytes; same studio camera offline render','glb_sha256':read['glb_sha256']}},'limits':['remaining stone edge regularity and smooth root cut ends','not exact reference reproduction or final visual approval','no Godot/game/anti-pinch/network/performance test by this agent','source edge-manifold checks are separate from a comprehensive self-intersection audit']}
(HERE/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
checks=[]
def check(name,ok):checks.append({'name':name,'pass':bool(ok)})
for f in manifest['files']+manifest['readonly_inputs']:
 p=ROOT/f['path'];check('artifact:'+f['path'],p.exists() and p.stat().st_size==f['bytes'] and sha(p)==f['sha256'])
check('source_geometry_passes',source['all_pass'] and source['passed']==source['total'] and all(c['pass'] for c in source['checks']))
check('readback_passes',read['all_pass'] and read['passed']==read['total'] and all(c['pass'] for c in read['checks']))
check('exact_bytes_source',source['source_sha256']==ex['source_sha256']==bake['source_sha256']==sha(HERE/'rising_seal_source_p2.blend'))
check('exact_bytes_GLB',ex['glb_sha256']==read['glb_sha256']==sha(glb))
check('exact_bytes_ready',ex['ready_sha256']==read['ready_sha256']==bake['ready_sha256']==sha(ROOT/ex['ready_source']))
check('bake_kept_geometry',bake['geometry_unchanged'] and not bake['lighting_baked'])
check('actual_source_deleted_before_reimport',read['source_deleted_before_import'])
check('readonly_inputs_unchanged',all(sha(ROOT/p)==v for p,v in ex['readonly_inputs'].items()))
for name,marker in [('build_p2.log','RISING_SEAL_P2_DONE'),('bake_p2.log','SEAL_BAKE_ONLY_DONE'),('export_p2.log','SEAL_EXPORT_DONE'),('verify_p2.log','SEAL_SAME_BYTE_PREVIEW_DONE')]:
 log=(HERE/name).read_text(encoding='utf-8',errors='replace');check(name+'_completed',marker in log and ('Blender quit' in log or name=='bake_p2.log') and 'Traceback (most recent call last)' not in log and 'EXCEPTION_' not in log)
result={'stage':'file/provenance integrity only','manifest_sha256':sha(HERE/'manifest.json'),'checks':checks,'passed':sum(c['pass'] for c in checks),'total':len(checks),'all_pass':all(c['pass'] for c in checks)}
(HERE/'selfcheck.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print(json.dumps({k:result[k] for k in ['passed','total','all_pass','manifest_sha256']}));assert result['all_pass']
