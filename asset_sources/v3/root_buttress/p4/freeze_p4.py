"""Archive source-only p4 evidence without touching frozen assets."""
from pathlib import Path
import hashlib,json
from PIL import Image

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
report=json.loads((HERE/'p4_geometry_report.json').read_text(encoding='utf-8'))
assert report['all_checks_pass'] and report['passed']==report['total']==17
assert report['output_source_sha256']==sha(HERE/'root_buttress_h10_form_p4.blend')
assert not list(HERE.rglob('*.glb')),'Source-only stage must not export GLB'
p3=json.loads((HERE.parent/'p3/p3_manifest.json').read_text(encoding='utf-8'))
assert all(sha(ROOT/e['path'])==e['sha256'] for e in p3['entries'])
assert all(sha(ROOT/f'assets/v3/root_buttress/root_buttress_h{h}.glb')==v for h,v in p3['runtime_p2_sha256'].items())
files=['build_h10_form_p4.py','root_buttress_h10_form_p4.blend','p4_geometry_report.json','h10_p4_gray_default.png','h10_p4_basic_default.png','build_p4.log','README.md','freeze_p4.py']
for version in ['review_v1','review_v2']:
 files.extend(f'{version}/{name}' for name in ['build_h10_form_p4.py','build_p4.log','p4_geometry_report.json','h10_p4_gray_default.png','h10_p4_basic_default.png'])
entries=[]
for name in files:
 path=HERE/name;item={'path':str(path.relative_to(ROOT)).replace('\\','/'),'sha256':sha(path),'bytes':path.stat().st_size}
 if path.suffix=='.png':
  with Image.open(path) as im:im.verify()
  with Image.open(path) as im:item['pixels']=list(im.size)
 entries.append(item)
inputs=['references/v3/production/root_buttress/root_buttress_reference_v1.png','asset_sources/v3/root_buttress/p3/root_buttress_h10_p3_export_ready.blend','asset_sources/v3/root_buttress/p3/root_buttress_h10_material_p3.blend']
inputs.extend('artifacts/v3/art/capture-20261018_022355_7ec161/'+name for name in ['02-p2-baseline-near.png','05-p3-candidate-near.png','04-p3-candidate-core-open.png','06-p3-candidate-default.png'])
manifest={'stage':'p4 H10 source shape candidate; no GLB, no baking, no runtime replacement','entries':entries,'readonly_inputs':[{'path':p,'sha256':sha(ROOT/p)} for p in inputs],'runtime_p2_sha256':p3['runtime_p2_sha256'],'p3_manifest_sha256':sha(HERE.parent/'p3/p3_manifest.json'),'checks':{'geometry':str(report['passed'])+'/'+str(report['total']),'p3_files_unchanged':True,'runtime_unchanged':True,'source_matches_report':True,'png_decode':True,'no_p4_glb':True},'limits':['Blender geometry probes are not Godot flight/body sweep','offline gray/basic renders are not gameplay screenshots','visual review remains open; numerical checks do not mean final art approval']}
out=HERE/'p4_manifest.json';out.write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
selfcheck={'status':'PASS','manifest_sha256':sha(out),'files':len(entries),'pngs':sum('pixels' in e for e in entries),'all_manifest_sha256_rechecked':all(sha(ROOT/e['path'])==e['sha256'] for e in entries),'p3_and_p2_unchanged':True,'no_runtime_export':True}
(HERE/'p4_selfcheck.json').write_text(json.dumps(selfcheck,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(selfcheck,ensure_ascii=False))
