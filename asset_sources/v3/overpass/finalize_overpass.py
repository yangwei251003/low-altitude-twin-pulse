"""Check frozen bytes and evidence provenance; no asset writes or engine calls."""
from pathlib import Path
from PIL import Image
import json,hashlib,runpy
ROOT=Path(__file__).resolve().parents[3];EVID=ROOT/'artifacts/v3/art/overpass'
runpy.run_path(str(Path(__file__).with_name('freeze_overpass.py')))
def read(name):return json.loads((EVID/name).read_text(encoding='utf-8'))
glb=ROOT/'assets/v3/overpass/maintenance_overpass.glb';digest=hashlib.sha256(glb.read_bytes()).hexdigest()
bytecheck=read('glb_inspection.json');uv=read('uv_audit_v4.json');spatial=read('source_and_clearance.json');renders=read('glb_renders_v4.json')
checks={'bytes_pass':bytecheck['all_checks_pass'],'uv_pass':uv['all_checks_pass'],'source_spatial_pass':spatial['all_checks_pass'],'sha_consistent':bytecheck['sha256']==spatial['glb_sha256']==renders['glb_sha256']==digest,'all_three_views':{r['view'] for r in renders['views']}=={'front','back','under'}}
for r in renders['views']:
 p=ROOT/r['path'];checks[r['view']+'_hash']=hashlib.sha256(p.read_bytes()).hexdigest()==r['sha256']
 with Image.open(p) as im:im.load();checks[r['view']+'_dimensions']=list(im.size)==renders['resolution']
r={'glb_sha256':digest,'counts':{'byte_checks':len(bytecheck['checks']),'uv_checks':len(uv['checks']),'source_and_spatial_checks':len(spatial['checks']),'renders':len(renders['views']),'frozen_files':18},'checks':checks,'all_checks_pass':all(checks.values()),'scope':'Offline integration candidate provenance; no human, engine or performance claim'}
(EVID/'delivery_v4.json').write_text(json.dumps(r,ensure_ascii=False,indent=2),encoding='utf-8');print(json.dumps(r))
assert r['all_checks_pass']
