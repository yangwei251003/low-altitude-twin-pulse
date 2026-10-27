"""Read hashes/JSON only; no Blender, pixel edits, GLB or shared-file writes."""
from pathlib import Path
import hashlib,json

HERE=Path(__file__).resolve().parent
P1=HERE.parent/'p1'

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def write(name,value):
    (HERE/name).write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

frozen=json.loads((P1/'manifest.json').read_text(encoding='utf-8'))
p1_checks=[]
for row in frozen['files']:
    path=P1/row['path']
    p1_checks.append({'path':row['path'],'pass':path.is_file() and path.stat().st_size==row['bytes'] and sha(path)==row['sha256']})
assert all(r['pass'] for r in p1_checks),'Frozen P1 file changed.'
report=json.loads((HERE/'evidence/production_report.json').read_text(encoding='utf-8'))
process=json.loads((HERE/'process.json').read_text(encoding='utf-8'))
assert process['exit_code']==0
assert report['geometry_uv_unchanged'] and report['source_pieces']==77 and report['triangles_from_identical_source']==3276
checks=[]
for label,rel,expected in [
    ('source','clinic_ground_p2.blend',report['blend_sha256']),
    ('preview','evidence/clinic_ground_p2.png',report['preview_sha256']),
    ('atlas','source_inputs/material_atlas_UNEDITED.png','11db122c63d06f7fcd25f5614f19cd0efee1b09997149071b993ed6eff7e8406')]:
    actual=sha(HERE/rel);checks.append({'role':label,'path':rel,'sha256':actual,'pass':actual==expected})
for row in report['reopened_images']:
    path=Path(row['path']);checks.append({'role':row['role'],'path':str(path.relative_to(HERE)),'sha256':sha(path),'pass':sha(path)==row['sha256']})
assert all(r['pass'] for r in checks)
write('selfcheck.json',{'status':'FILES_VERIFIED_VISUAL_REVIEWED_PENDING_ROOT','scope':'source-only; no engine or GLB','p1_frozen_files':p1_checks,'p2_readback_hashes':checks,'geometry_uv_unchanged':True,'blender_exit_code':process['exit_code'],'visual_review':'evidence/VISUAL_REVIEW.md','note':'No hash or file check implies final aesthetic approval.'})
files=[]
for path in sorted(HERE.rglob('*')):
    if not path.is_file() or path.name in {'manifest.json','manifest_selfcheck.json'}:continue
    files.append({'path':path.relative_to(HERE).as_posix(),'bytes':path.stat().st_size,'sha256':sha(path)})
write('manifest.json',{'status':'SOURCE_FROZEN_REVIEWED_PENDING_ROOT','scope':'P2 offline preview and source only; P1 unchanged; no GLB/Godot','files':files,'file_count':len(files),'total_bytes':sum(r['bytes'] for r in files)})
saved=json.loads((HERE/'manifest.json').read_text(encoding='utf-8'))
assert all((HERE/r['path']).stat().st_size==r['bytes'] and sha(HERE/r['path'])==r['sha256'] for r in saved['files'])
result={'status':'PASS','manifest_sha256':sha(HERE/'manifest.json'),'file_count':len(files),'total_bytes':saved['total_bytes'],'p1_files_unchanged':len(p1_checks),'exclusions':['manifest.json','manifest_selfcheck.json']}
write('manifest_selfcheck.json',result)
print(json.dumps(result,ensure_ascii=False))
