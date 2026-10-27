from pathlib import Path
import json,hashlib
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
r=json.loads((HERE/'form_report.json').read_text(encoding='utf-8'))
assert r['all_pass'] and 'FOUNDATION_FORM_DONE' in (HERE/'form_p1.log').read_text(encoding='utf-8',errors='replace')
assert sha(HERE/'seal_foundation_form_p1.blend')==r['source_sha256']
names=['FORM_PLAN.md','FORM_REVIEW.md','build_foundation_form.py','read_door_contact.py','door_bottom_contact.json','seal_foundation_form_p1.blend','seal_foundation_form_p1.png','form_report.json','form_p1.log','freeze_form.py']
files=[{'path':(HERE/n).relative_to(ROOT).as_posix(),'bytes':(HERE/n).stat().st_size,'sha256':sha(HERE/n)} for n in names]
m={'stage':'basic-color source shape study; geometry checks passed, author visual review rejected','files':files,'readonly_inputs':r['readonly_inputs'],'no_PBR_GLB_or_game':True}
(HERE/'form_manifest.json').write_text(json.dumps(m,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
out={'file_count':len(files),'hashes_match':all(sha(ROOT/v['path'])==v['sha256'] for v in files),'readonly_inputs_match':all(sha(ROOT/p)==v for p,v in r['readonly_inputs'].items()),'source_geometry_checks':f"{r['passed']}/{r['total']}",'art_approval':False,'manifest_sha256':sha(HERE/'form_manifest.json')}
(HERE/'form_selfcheck.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print(json.dumps(out,ensure_ascii=False))
