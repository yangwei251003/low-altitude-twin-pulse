from pathlib import Path
import json,hashlib
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
report=json.loads((HERE/'form_report.json').read_text(encoding='utf-8'))
files=[]
for p in sorted(HERE.rglob('*')):
 if not p.is_file() or p.name in ['manifest.json','selfcheck.json'] or '__pycache__' in p.parts:continue
 files.append({'path':p.relative_to(HERE).as_posix(),'bytes':p.stat().st_size,'sha256':sha(p)})
manifest={'stage':'P2 first-form self-rejected, frozen; no runtime output','files':files,'source_sha256':sha(HERE/'seal_foundation_p2.blend'),'visual_status':'FAIL_SELF_REVIEW','geometry_checks':{'passed':report['passed'],'total':report['total'],'all_pass':report['all_pass']}}
(HERE/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
readonly=[{'path':p,'expected':h,'actual':sha(ROOT/p),'pass':sha(ROOT/p)==h} for p,h in report['readonly_inputs'].items()]
check={'files_checked':len(files),'file_hashes_match':all(sha(HERE/f['path'])==f['sha256'] for f in files),'readonly_inputs':readonly,'readonly_inputs_unchanged':all(r['pass'] for r in readonly),'blend_matches_original_report':sha(HERE/'seal_foundation_p2.blend')==report['source_sha256'],'manifest_sha256':sha(HERE/'manifest.json'),'note':'Hash/archive verification does not upgrade failed form or incomplete support checks.'}
(HERE/'selfcheck.json').write_text(json.dumps(check,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
assert check['file_hashes_match'] and check['readonly_inputs_unchanged'] and check['blend_matches_original_report']
print(json.dumps({'files':len(files),'manifest_sha256':check['manifest_sha256'],'source_sha256':manifest['source_sha256'],'status':manifest['visual_status']},ensure_ascii=False))
