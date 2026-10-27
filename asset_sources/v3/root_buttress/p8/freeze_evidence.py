from pathlib import Path
import json,hashlib
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
report=json.loads((HERE/'contact_report.json').read_text())
files=[]
for p in sorted(HERE.rglob('*')):
 if not p.is_file() or '__pycache__' in p.parts or p.name in ('manifest.json','selfcheck.json') or p.suffix=='.blend1':continue
 files.append({'file':p.relative_to(HERE).as_posix(),'bytes':p.stat().st_size,'sha256':sha(p),'purpose':'official raw geometry/provenance' if 'vendor' in p.parts else 'source research only; not a built platform or game image'})
manifest={'status':'SOURCE_STUDY_COMPLETE; A recommended, B local use, C rejected for main cliff','files':files,'limits':'Source suitability is not high-platform visual/physics acceptance; no bake/export/runtime changes.'}
(HERE/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
checks={i['file']:sha(HERE/i['file'])==i['sha256'] for i in files}
checks['source_hash_matches_report']=sha(HERE/'source_geometry_contact_p8.blend')==report['source_blend_sha256']
checks['image_hash_matches_report']=sha(HERE/'source_geometry_contact_p8.png')==report['image_sha256']
for src in json.loads((HERE/'provenance.json').read_text()):
 for file in src['files']:checks['vendor_original_'+file['file']]=sha(HERE/file['file'])==file['sha256']
older=json.loads((HERE.parent/'p7/p7_geometry_report.json').read_text())
for h,s in older['runtime_p2_sha256'].items():checks['runtime_p2_'+h]=sha(ROOT/f'assets/v3/root_buttress/root_buttress_h{h}.glb')==s
checks['p7_source_frozen']=sha(HERE.parent/'p7/root_buttress_h10_natural_layers_p7.blend')=='60b006915fdf647f25288efaeaff80f2874ced08038be1141a866f844ba751ca'
research=json.loads((HERE/'source_geometry_research.json').read_text());c=research['coast_original'];cp=ROOT/c['gltf']
checks['coast_gltf_frozen']=sha(cp)==c['gltf_sha256'];checks['coast_bin_frozen']=sha(cp.parent/'coast_rocks_01.bin')==c['bin_sha256']
result={'manifest_sha256':sha(HERE/'manifest.json'),'all_pass':all(checks.values()),'checks':checks,'pngs':[i['file'] for i in files if i['file'].endswith('.png')],'limits':'Evidence integrity only, no platform acceptance.'}
(HERE/'selfcheck.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'files':len(files),'all_pass':result['all_pass'],'pngs':result['pngs'],'source_sha256':report['source_blend_sha256'],'image_sha256':report['image_sha256'],'manifest_sha256':result['manifest_sha256']}));assert result['all_pass']
