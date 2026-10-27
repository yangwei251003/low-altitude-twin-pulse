"""Readback/hashes only; never starts Blender or edits PNG/GLB bytes."""
from pathlib import Path
import json,hashlib,struct
HERE=Path(__file__).resolve().parent
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,value):p.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
report=json.loads((HERE/'delivery_report.json').read_text(encoding='utf-8'))
assert len(report['checks'])==25 and all(r['passed'] for r in report['checks'])
glb=HERE/'clinic_ground_p2.glb';assert glb.stat().st_size==report['glb_bytes'] and sha(glb)==report['glb_sha256']
b=glb.read_bytes();n=struct.unpack_from('<I',b,12)[0];j=json.loads(b[20:20+n])
assert len(j['samplers'])==1 and all(t['sampler']==0 for t in j['textures'])
source=HERE.parent/'p2';manifest=json.loads((source/'manifest.json').read_text(encoding='utf-8'))
assert all((source/r['path']).stat().st_size==r['bytes'] and sha(source/r['path'])==r['sha256'] for r in manifest['files'])
write(HERE/'selfcheck.json',{'status':'PASS_SOURCE_DELIVERY_ONLY','binary_checks':25,'frozen_p2_files_unchanged':len(manifest['files']),'glb_sha256':sha(glb),'glb_bytes':glb.stat().st_size,'actual_samplers':j['samplers'],'actual_texture_sampler_bindings':j['textures'],'limits':['No Godot import/physics/GPU in this task.','Source preview previously viewed; no separate reimport render.','Sampler-combination warning retained in original logs.']})
rows=[]
for p in sorted(HERE.rglob('*')):
 if p.is_file() and p.name not in {'manifest.json','manifest_selfcheck.json'}:rows.append({'path':p.relative_to(HERE).as_posix(),'bytes':p.stat().st_size,'sha256':sha(p)})
write(HERE/'manifest.json',{'status':'FROZEN_SOURCE_GLB_READY_FOR_ROOT_IMPORT','files':rows,'file_count':len(rows),'total_bytes':sum(r['bytes'] for r in rows),'scope':'Source-only asset export; no runtime/shared modifications.'})
reread=json.loads((HERE/'manifest.json').read_text(encoding='utf-8'))
assert all((HERE/r['path']).stat().st_size==r['bytes'] and sha(HERE/r['path'])==r['sha256'] for r in reread['files'])
result={'status':'PASS','manifest_sha256':sha(HERE/'manifest.json'),'file_count':len(rows),'total_bytes':reread['total_bytes'],'exclusions':['manifest.json','manifest_selfcheck.json']}
write(HERE/'manifest_selfcheck.json',result);print(json.dumps(result))
