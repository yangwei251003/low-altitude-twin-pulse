from pathlib import Path
import shutil,hashlib,json
HERE=Path(__file__).resolve().parent;DEST=HERE/'envelope_reject_v1';DEST.mkdir(exist_ok=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
items=[]
for name in ['build_rising_seal_p2.py','build_p2.log','source_report.json','rising_seal_source_p2.blend']:
 source=HERE/name;target=DEST/name
 assert not target.exists(),'Do not overwrite original failure evidence'
 shutil.copyfile(source,target);assert sha(source)==sha(target)
 items.append({'name':name,'sha256':sha(target),'bytes':target.stat().st_size})
(DEST/'archive.json').write_text(json.dumps({'reason':'No image rendered; X max .5067397356 exceeds .5m by .0067397356m; all other 36 checks pass','files':items},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('Archived original 4 failure files byte-identically')
