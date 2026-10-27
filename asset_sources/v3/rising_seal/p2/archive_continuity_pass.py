from pathlib import Path
import json,hashlib,shutil
HERE=Path(__file__).resolve().parent
out=HERE/'continuous_roots_v2';out.mkdir(exist_ok=False)
names=['build_rising_seal_p2.py','build_p2.log','source_report.json','rising_seal_source_p2.blend','rising_seal_source_p2.png','README.md','manifest.json','selfcheck.json','freeze_source_p2.py']
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
items=[]
for name in names:
 a=HERE/name;b=out/name;shutil.copyfile(a,b);assert sha(a)==sha(b)
 items.append({'file':name,'sha256':sha(b),'bytes':b.stat().st_size})
(out/'archive.json').write_text(json.dumps({'stage':'root actual visual review approved continuous master roots; additional fork/copper refinement authorized; not final art','method':'byte identical copy before new geometry edits','files':items},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('Archived',len(items))
