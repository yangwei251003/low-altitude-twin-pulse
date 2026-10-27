from pathlib import Path
import shutil,hashlib,json
HERE=Path(__file__).resolve().parent;DEST=HERE/'occluded_roots_v1';DEST.mkdir(exist_ok=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
items=[]
for name in ['build_rising_seal_p2.py','build_p2.log','source_report.json','rising_seal_source_p2.blend','rising_seal_source_p2.png','README.md','manifest.json','selfcheck.json','freeze_source_p2.py']:
 p=HERE/name;q=DEST/name
 assert not q.exists(),'Do not overwrite prior archive'
 shutil.copyfile(p,q);assert sha(p)==sha(q)
 items.append({'name':name,'sha256':sha(q),'bytes':q.stat().st_size})
(DEST/'archive.json').write_text(json.dumps({'reason':'Geometry 37/37, actual image rejected: main roots occluded at side turns and stone faces too regular','files':items},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('Archived 9 current files before any further source edit')
