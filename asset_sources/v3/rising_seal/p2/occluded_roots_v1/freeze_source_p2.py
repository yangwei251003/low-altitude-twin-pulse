"""Freeze first source study without running Blender or touching P1/shared files."""
from pathlib import Path
import hashlib,json
from datetime import datetime,timezone
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
record=lambda p,role:{'path':p.relative_to(ROOT).as_posix(),'sha256':sha(p),'bytes':p.stat().st_size,'purpose':role}
report=json.loads((HERE/'source_report.json').read_text(encoding='utf-8'))
dependencies=[ROOT/p for p in report['input_hashes']]
dependencies += [ROOT/'docs/v3/assets/F1_RISING_SEAL.md',ROOT/'references/v3/production/rising_seal/provenance-v1.json',HERE.parent/'p1/rising_seal_source_p1.png',HERE.parent/'p1/first_form_rejected/rising_seal_source_p1.png']
own=[p for p in HERE.rglob('*') if p.is_file() and '__pycache__' not in p.parts and p.suffix!='.blend1' and p not in [HERE/'manifest.json',HERE/'selfcheck.json']]
manifest={'stage':'P2 first source study; geometry passed, visual self-review rejected, no PBR/GLB','created_utc':datetime.now(timezone.utc).isoformat(),'files':[record(p,'historical envelope failure' if 'envelope_reject_v1' in p.parts else 'current source, offline preview or validation record') for p in sorted(own)],'readonly_inputs':[record(p,'readonly source/reference/contract') for p in dependencies],'image_provenance':{'rising_seal_source_p2.png':{'source':'rising_seal_source_p2.blend','source_sha256':report['source_sha256'],'method':'actual source render, same P1 camera; Cycles CPU2 12 samples, not game'}},'limits':['not final artistic approval','root loop visibly interrupted by unrecessed stone corners','no candidate GLB, runtime import or gameplay checks','historical script restored from inverse patch; archive metadata states limitation']}
(HERE/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
checks=[]
def check(name,ok):checks.append({'name':name,'pass':bool(ok)})
for item in manifest['files']+manifest['readonly_inputs']:
 p=ROOT/item['path'];check('file:'+item['path'],p.exists() and sha(p)==item['sha256'] and p.stat().st_size==item['bytes'])
check('source_37_geometry_checks',report['passed']==report['total']==37 and report['all_pass'] and all(c['pass'] for c in report['checks']))
check('source_hash_matches_report',sha(HERE/'rising_seal_source_p2.blend')==report['source_sha256']=='c6b3f2d3ef895c84c67558ad3a5fb3590dcc387128a51cd0a13428db9492657c')
check('P1_inputs_unchanged',all(sha(ROOT/p)==s for p,s in report['input_hashes'].items()))
log=(HERE/'build_p2.log').read_text(encoding='utf-8',errors='replace')
check('normal_build_and_render_completion','RISING_SEAL_P2_DONE' in log and 'Blender quit' in log and 'Traceback (most recent call last)' not in log)
check('no_candidate_GLB',not any((ROOT/'assets/v3/candidates/rising_seal_p2').glob('*.glb')))
out={'stage':'artifact integrity only, not visual acceptance','manifest_sha256':sha(HERE/'manifest.json'),'checks':checks,'passed':sum(c['pass'] for c in checks),'total':len(checks),'all_pass':all(c['pass'] for c in checks)}
(HERE/'selfcheck.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({k:out[k] for k in ['passed','total','all_pass','manifest_sha256']},ensure_ascii=False))
assert out['all_pass'],[c for c in checks if not c['pass']]
