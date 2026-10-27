"""Hash deliverables without changing source textures, blend or runtime GLB."""
from pathlib import Path
import hashlib,json,struct
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[2]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
paths=[p for p in SRC.rglob('*') if p.is_file() and p.name not in ('manifest.json','selfcheck.json') and '__pycache__' not in p.parts and not p.name.endswith('.blend1')]
paths += [ROOT/'assets/v3/thermal_bypass/thermal_bypass.glb',ROOT/'docs/v3/assets/I1_THERMAL_BYPASS.md']
entries=[]
for p in sorted(paths):
    item={'path':str(p.relative_to(ROOT)).replace('\\','/'),'bytes':p.stat().st_size,'sha256':sha(p)}
    if p.suffix=='.png':
        b=p.read_bytes();item['width'],item['height']=struct.unpack('>II',b[16:24])
    item['purpose']='historical rejected first round' if 'rejected_v1' in p.parts else ('historical pre-neutral-window source view' if p.name.startswith('thermal_bypass_source_front') else 'current source, runtime or evidence')
    entries.append(item)
references=[]
for name in ['thermal_bypass_v1.png','thermal_bypass_v1.prompt.txt']:
    p=ROOT/'references/v3/production/thermal_bypass'/name;references.append({'path':str(p.relative_to(ROOT)).replace('\\','/'),'sha256':sha(p),'bytes':p.stat().st_size,'ownership':'root read-only reference'})
data={'asset':'ThermalBypass','status':'frozen integration candidate, not final visual approval','glb_sha256':'c9ae203562a36038b807dccea4e410f26356273c9130251e9d972e80491ab7f9','files':entries,'references':references,'exclusions':['.blend1 automatic backups','__pycache__','manifest/selfcheck avoid recursive hash'],'limitations':['No Godot/performance/human play validation by this worker','Blender process exit codes were not captured independently; normal complete logs and process absence recorded','PBR maps are original UV authored, not claimed high-low geometry bake']}
manifest=SRC/'manifest.json';manifest.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
failures=[e['path'] for e in entries+references if sha(ROOT/e['path'])!=e['sha256']]
selfcheck={'manifest_sha256':sha(manifest),'files_checked':len(entries),'references_checked':len(references),'failures':failures,'passed':not failures,'glb_matches_lock':sha(ROOT/'assets/v3/thermal_bypass/thermal_bypass.glb')==data['glb_sha256']}
(SRC/'selfcheck.json').write_text(json.dumps(selfcheck,ensure_ascii=False,indent=2),encoding='utf-8');print(json.dumps(selfcheck,ensure_ascii=False));assert selfcheck['passed'] and selfcheck['glb_matches_lock']
