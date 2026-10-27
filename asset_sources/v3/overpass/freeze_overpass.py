"""Lock source blend, runtime GLB and all PBR PNG bytes; later runs verify."""
from pathlib import Path
import json,hashlib,datetime
from PIL import Image
ROOT=Path(__file__).resolve().parents[3];EVID=ROOT/'artifacts/v3/art/overpass'
paths=[ROOT/'asset_sources/v3/overpass/maintenance_overpass.blend',ROOT/'assets/v3/overpass/maintenance_overpass.glb',*sorted((ROOT/'assets/v3/overpass/textures').glob('*.png'))]
rows=[]
for p in paths:
 row={'path':str(p.relative_to(ROOT)).replace('\\','/'),'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'bytes':p.stat().st_size}
 if p.suffix=='.png':
  with Image.open(p) as im:im.load();row['dimensions']=list(im.size)
 rows.append(row)
assert len(rows)==18,'Expected one editable blend, one GLB and sixteen textures'
lock=EVID/'frozen_v4.json'
if lock.exists():
 old=json.loads(lock.read_text(encoding='utf-8'));assert old['files']==rows,'Frozen files changed; do not refresh the lock silently'
else:
 lock.write_text(json.dumps({'frozen_at':datetime.datetime.now().isoformat(timespec='seconds'),'status':'integration candidate; not final art approval','files':rows},ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'frozen_files':len(rows),'unchanged':True,'lock':str(lock)}))
