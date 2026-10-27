"""Freeze this explicitly owned asset's evidence and verify every saved byte."""
from pathlib import Path
import json,hashlib,datetime,re
ROOT=Path(__file__).resolve().parents[3];SRC=Path(__file__).resolve().parent
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
build=json.loads((SRC/'evidence/build_report.json').read_text(encoding='utf-8'))
binary=json.loads((SRC/'evidence/glb_report.json').read_text(encoding='utf-8'))
reimport=json.loads((SRC/'evidence/reimport_report.json').read_text(encoding='utf-8'))
assert build['failed']==0 and build['source_render_completed']
assert binary['failed']==0 and reimport['failed']==0 and reimport['render_complete']
assets=[ROOT/'assets/v3/underdeck_door'/n for n in ['panel.glb','fixed_rail.glb']]
for p in assets:
    expected=build['exports'][p.name]['sha256']
    assert sha(p)==expected==reimport['input_glbs'][str(p)]
    assert next(a for a in binary['assets']if Path(a['path']).name==p.name)['sha256']==expected
card=ROOT/'docs/v3/assets/I1_UNDERDECK_DOOR.md'
owned=[p for p in SRC.rglob('*')if p.is_file() and '__pycache__'not in p.parts and p not in [SRC/'manifest.json',SRC/'selfcheck.json']]
owned+=assets+[card]
entries=[]
for p in sorted(owned,key=lambda p:str(p)):
    entries.append({'path':p.relative_to(ROOT).as_posix(),'bytes':p.stat().st_size,'sha256':sha(p)})
inputs=[ROOT/'references/v3/production/underdeck_door'/n for n in ['underdeck_door_v1.png','prompt_v1.txt']]
manifest={'asset':'I1 underdeck sliding door','version':'material_v4','status':'frozen development integration candidate; actual Godot appearance pending','generated_local':datetime.datetime.now().astimezone().isoformat(),'files':entries,'readonly_reference_inputs':[{'path':p.relative_to(ROOT).as_posix(),'bytes':p.stat().st_size,'sha256':sha(p)}for p in inputs],'evidence_counts':{'source_checks':build['passed'],'raw_GLB_checks':binary['passed'],'reimport_checks':reimport['passed']},'remaining':'Actual game camera/material/state readability, rotating wheels, scene art and performance have not been accepted by this offline pipeline.'}
(SRC/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
read=json.loads((SRC/'manifest.json').read_text(encoding='utf-8'));failures=[]
for e in read['files']+read['readonly_reference_inputs']:
    p=ROOT/e['path']
    if not p.is_file()or p.stat().st_size!=e['bytes']or sha(p)!=e['sha256']:failures.append(e['path'])
links=[]
for target in re.findall(r'\]\(([^)]+)\)',card.read_text(encoding='utf-8')):
    p=Path(target);links.append({'path':target,'exists':p.exists()})
assert all(i['exists']for i in links)
check={'manifest_sha256':sha(SRC/'manifest.json'),'owned_file_count':len(entries),'readonly_reference_count':len(inputs),'all_sha_and_bytes_readback_match':not failures,'failures':failures,'card_link_checks':links,'total_owned_bytes':sum(e['bytes']for e in entries),'GLBs':{p.name:{'bytes':p.stat().st_size,'sha256':sha(p)}for p in assets}}
(SRC/'selfcheck.json').write_text(json.dumps(check,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(check,ensure_ascii=False));assert not failures
