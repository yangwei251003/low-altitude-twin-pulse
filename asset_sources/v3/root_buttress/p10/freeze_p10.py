from pathlib import Path
import hashlib,json,datetime
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
report=json.loads((HERE/'p10_geometry_report.json').read_text(encoding='utf-8'))
files=[]
for p in sorted(HERE.rglob('*')):
 if not p.is_file() or p.name in ['manifest.json','selfcheck.json'] or p.suffix=='.blend1' or '__pycache__' in p.parts:continue
 purpose='historical failed topology evidence' if 'technical_reject_v1' in p.parts else 'P10 bounded source refinement; not runtime'
 if p.suffix=='.png':purpose='actual offline CPU basic-color render; not game capture'
 files.append({'path':str(p.relative_to(HERE)).replace('\\','/'),'bytes':p.stat().st_size,'sha256':sha(p),'purpose':purpose})
inputs=[]
for rel in ['asset_sources/v3/root_buttress/p9/root_buttress_h10_closed_cliff_p9.blend','asset_sources/v3/root_buttress/p9/manifest.json','asset_sources/v3/root_buttress/p8/vendor/rock_face_01/rock_face_01_1k.gltf','asset_sources/v3/root_buttress/p8/vendor/rock_face_01/rock_face_01.bin','asset_sources/v3/root_buttress/p3/root_buttress_h10_p3_export_ready.blend','references/v3/production/root_buttress/root_buttress_reference_v1.png']:
 p=ROOT/rel;inputs.append({'project_path':rel,'bytes':p.stat().st_size,'sha256':sha(p),'access':'read-only source/reference'})
manifest={'stage':'P10 bounded refinement of frozen P9; visual review pending','files':files,'inputs':inputs,'runtime_p2_sha256':report['runtime_p2_sha256'],'image_provenance':{'image':'h10_p10_refined_cliff_default.png','source_blend':'root_buttress_h10_refined_cliff_p10.blend','source_sha256':report['source_sha256'],'render':report['render'],'game_capture':False},'visual_status':'Not final art: rear ridge remains slope-like with small sawtooth cut edge, one front corner stays planar, wall source repetition remains','excluded':['automatic .blend1 backup','__pycache__'],'no_runtime_export':True}
(HERE/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
checks=[{'name':'all_manifest_file_bytes_match','pass':all(sha(HERE/f['path'])==f['sha256'] for f in files),'count':len(files)},
{'name':'input_source_bytes_match','pass':all(sha(ROOT/f['project_path'])==f['sha256'] for f in inputs),'count':len(inputs)},
{'name':'runtime_p2_unchanged','pass':all(sha(ROOT/f'assets/v3/root_buttress/root_buttress_h{h}.glb')==v for h,v in report['runtime_p2_sha256'].items())},
{'name':'source_blend_matches_actual_geometry_report','pass':sha(HERE/'root_buttress_h10_refined_cliff_p10.blend')==report['source_sha256']},
{'name':'actual_blender_geometry_report_all_pass','pass':report['all_pass'],'count':report['total']},
{'name':'actual_log_render_and_normal_exit','pass':'P10_DONE_SOURCE_ONLY_NO_RUNTIME_EXPORT' in (HERE/'build_p10.log').read_text(encoding='utf-8-sig') and 'Blender quit' in (HERE/'build_p10.log').read_text(encoding='utf-8-sig')}]
out={'checks':checks,'all_pass':all(c['pass'] for c in checks),'manifest_sha256':sha(HERE/'manifest.json'),'not_evaluated':['Godot rendering','full Crown collision/migration','game performance','final artistic acceptance']}
(HERE/'selfcheck.json').write_text(json.dumps(out,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(out,ensure_ascii=False))
