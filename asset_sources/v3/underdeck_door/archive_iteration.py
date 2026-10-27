from pathlib import Path
import shutil,hashlib,json,sys
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[2]
label=sys.argv[1];out=SRC/'evidence'/label
assert not out.exists(),out
out.mkdir()
paths=[SRC/'build_underdeck_door.py',SRC/'underdeck_door.blend',SRC/'evidence/build_report.json',SRC/'evidence/glb_report.json',SRC/'evidence/underdeck_door_source_front.png',ROOT/'assets/v3/underdeck_door/panel.glb',ROOT/'assets/v3/underdeck_door/fixed_rail.glb']+list((SRC/'textures').glob('*.png'))
paths += [SRC/'evidence/reimport_report.json']+list((SRC/'evidence').glob('underdeck_door_glb_*.png'))
entries=[]
for p in paths:
    if not p.exists():continue
    target=out/('textures/'+p.name if p.parent.name=='textures'else p.name);target.parent.mkdir(exist_ok=True)
    shutil.copy2(p,target);data=p.read_bytes();a=hashlib.sha256(data).hexdigest();assert hashlib.sha256(target.read_bytes()).hexdigest()==a
    entries.append({'source':str(p),'copy':str(target.relative_to(out)),'bytes':len(data),'sha256':a})
(out/'manifest.json').write_text(json.dumps({'label':label,'files':entries,'reason':'Material iteration retained before deterministic PNG/UV vertical-orientation correction. Geometry unchanged.'},ensure_ascii=False,indent=2),encoding='utf-8')
print(len(entries))
