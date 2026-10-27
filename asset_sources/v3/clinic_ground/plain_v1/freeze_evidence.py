"""Hash-only archive. Does not launch Blender/Godot or alter frozen dependencies."""
from pathlib import Path
import hashlib,json
HERE=Path(__file__).resolve().parent
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,r):p.write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
report=json.loads((HERE/'evidence/production_report.json').read_text(encoding='utf-8'))
assert all(c['passed'] for r in report['variants'] for c in r['checks'])
assert [r['triangles'] for r in report['variants']]==[632,676]
assert sha(HERE/'clinic_ground_plain_v1.blend')==report['blend_sha256']
for r in report['previews']+report['reopened_images']:assert sha(Path(r['path']))==r['sha256']
dep={}
for folder in ['p2','delivery_p2']:
 root=HERE.parent/folder;m=json.loads((root/'manifest.json').read_text(encoding='utf-8'))
 assert all((root/r['path']).stat().st_size==r['bytes'] and sha(root/r['path'])==r['sha256'] for r in m['files'])
 dep[folder]={'files_unchanged':len(m['files']),'manifest_sha256':sha(root/'manifest.json')}
write(HERE/'selfcheck.json',{'status':'PASS_SOURCE_ONLY','checks':sum(len(r['checks']) for r in report['variants']),'source_and_png_hashes_pass':True,'frozen_dependencies':dep,'new_texture_files':0,'glb_exports':0,'visual_review':'evidence/VISUAL_REVIEW.md'})
rows=[]
for p in sorted(HERE.rglob('*')):
 if p.is_file() and p.name not in {'manifest.json','manifest_selfcheck.json'}:rows.append({'path':p.relative_to(HERE).as_posix(),'bytes':p.stat().st_size,'sha256':sha(p)})
write(HERE/'manifest.json',{'status':'FROZEN_SOURCE_REVIEWED_PENDING_ROOT','files':rows,'file_count':len(rows),'total_bytes':sum(r['bytes'] for r in rows),'external_texture_dependencies':report['reopened_images'],'scope':'No GLB/runtime/shared modifications; source preview only.'})
saved=json.loads((HERE/'manifest.json').read_text(encoding='utf-8'))
assert all((HERE/r['path']).stat().st_size==r['bytes'] and sha(HERE/r['path'])==r['sha256'] for r in saved['files'])
result={'status':'PASS','manifest_sha256':sha(HERE/'manifest.json'),'file_count':len(rows),'total_bytes':saved['total_bytes'],'exclusions':['manifest.json','manifest_selfcheck.json']}
write(HERE/'manifest_selfcheck.json',result);print(json.dumps(result))
