"""Freeze own production evidence. The live asset card may later gain game QA;
manifest pins an exact production snapshot, not that mutable document.
"""
from pathlib import Path
import hashlib,json,shutil,re
ROOT=Path(__file__).resolve().parents[3];SRC=Path(__file__).resolve().parent;EV=SRC/'evidence'
card=ROOT/'docs/v3/assets/I1_UNDERDECK_SHELL.md';snapshot=EV/'asset_card_production.md'
shutil.copy2(card,snapshot)
def entry(p,role):return {'path':str(p.relative_to(ROOT)).replace('\\','/'),'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'role':role}
files=[p for p in SRC.rglob('*')if p.is_file()and '__pycache__'not in p.parts and p.name not in('manifest.json','selfcheck.json')]
# Retain the older rejected_v1/manifest.json as evidence; only exclude this root's manifest.
old=SRC/'evidence/rejected_v1/manifest.json'
if old.is_file():files.append(old)
runtime=ROOT/'assets/v3/underdeck_shell/underdeck_shell.glb';files.append(runtime)
rows=[entry(p,'runtime_GL B'.replace('GL B','GLB')if p==runtime else'owned_source_and_evidence')for p in sorted(set(files))]
readonly=[ROOT/'references/v3/production/underdeck_shell'/n for n in('underdeck_shell_v1.png','prompt_v1.txt')]
readonly += [ROOT/'assets/v3/underdeck_door'/n for n in('panel.glb','fixed_rail.glb')]
refs=[entry(p,'read_only_reference_or_frozen_door')for p in readonly]
manifest={'status':'v2 development integration candidate, NOT final art acceptance','runtime_sha256':entry(runtime,'runtime')['sha256'],'production_card_source':str(card.relative_to(ROOT)).replace('\\','/'),'production_card_snapshot':str(snapshot.relative_to(ROOT)).replace('\\','/'),'files':rows,'read_only_inputs':refs,'scope':'No game-engine tests or screenshots produced by this asset task. Failed v1 evidence preserved; Blender offline source and actual GLB reimport only.'}
mp=SRC/'manifest.json';mp.write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
loaded=json.loads(mp.read_text(encoding='utf-8'));fail=[]
for r in loaded['files']+loaded['read_only_inputs']:
 p=ROOT/r['path']
 if not p.is_file()or p.stat().st_size!=r['bytes']or hashlib.sha256(p.read_bytes()).hexdigest()!=r['sha256']:fail.append(r['path'])
links=re.findall(r'\]\((C:/[^)]+)\)',snapshot.read_text(encoding='utf-8'));badlinks=[p for p in links if not Path(p).is_file()]
result={'manifest_sha256':hashlib.sha256(mp.read_bytes()).hexdigest(),'owned_files':len(rows),'read_only_inputs':len(refs),'owned_bytes':sum(r['bytes']for r in rows),'mismatches':fail,'production_snapshot_links':len(links),'missing_links':badlinks,'passed':not fail and not badlinks}
(SRC/'selfcheck.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8');print(json.dumps(result,ensure_ascii=False));assert result['passed']
