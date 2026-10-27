from pathlib import Path
import json,hashlib
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
r=json.loads((HERE/'form_report.json').read_text(encoding='utf-8'))
files=[{'path':p.relative_to(HERE).as_posix(),'bytes':p.stat().st_size,'sha256':sha(p)} for p in sorted(HERE.rglob('*')) if p.is_file() and p.name not in ['manifest.json','selfcheck.json'] and '__pycache__' not in p.parts]
manifest={'status':'FAIL_SELF_REVIEW_AND_GEOMETRY; first-round evidence only','files':files,'source_sha256':sha(HERE/'seal_foundation_p3.blend'),'geometry_checks':{'passed':r['passed'],'total':r['total'],'all_pass':r['all_pass']},'image_limitation':'basic view clips far end; not complete silhouette proof'}
(HERE/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
readonly=[{'path':p,'expected':h,'actual':sha(ROOT/p),'pass':sha(ROOT/p)==h} for p,h in r['frozen_inputs'].items()]
check={'files_checked':len(files),'all_file_hashes_match':all(sha(HERE/f['path'])==f['sha256'] for f in files),'readonly_inputs':readonly,'readonly_inputs_unchanged':all(q['pass'] for q in readonly),'source_matches_original_report':sha(HERE/'seal_foundation_p3.blend')==r['source_sha256'],'manifest_sha256':sha(HERE/'manifest.json'),'note':'Archive integrity only, not artwork or physics acceptance.'}
(HERE/'selfcheck.json').write_text(json.dumps(check,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
assert check['all_file_hashes_match'] and check['readonly_inputs_unchanged'] and check['source_matches_original_report']
print(json.dumps({'files':len(files),'source_sha256':manifest['source_sha256'],'manifest_sha256':check['manifest_sha256']},ensure_ascii=False))
