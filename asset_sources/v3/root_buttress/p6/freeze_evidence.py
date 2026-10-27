"""Hash source-only failed form study without touching any runtime resource."""
from pathlib import Path
import hashlib,json,re
from datetime import datetime,timezone
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
files=[]
for p in sorted(HERE.rglob('*')):
    if not p.is_file() or '__pycache__' in p.parts or p.name in ('manifest.json','selfcheck.json'):continue
    rel=p.relative_to(HERE).as_posix()
    use='current source-only study'
    if rel.startswith('vendor/'):use='unchanged official CC0 source geometry or provenance; photographic maps not downloaded'
    elif rel.startswith('technical_reject_v1/'):use='historical failed numeric build, no rendered image'
    elif p.suffix=='.png':use='current stone-only source render; visual form rejected, not game view'
    files.append({'file':rel,'bytes':p.stat().st_size,'sha256':sha(p),'purpose':use})
report=json.loads((HERE/'p6_geometry_report.json').read_text(encoding='utf-8'))
manifest={'created_utc':datetime.now(timezone.utc).isoformat(),'status':'FORM_REJECTED','stage':'source-only natural geometry method study; no runtime GLB or PBR','source_blend_sha256':sha(HERE/'root_buttress_h10_natural_p6.blend'),'numeric_checks':{'passed':report['passed'],'total':report['total']},'files':files}
(HERE/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
runtime={str(h):sha(ROOT/f'assets/v3/root_buttress/root_buttress_h{h}.glb')==v for h,v in report['runtime_p2_sha256'].items()}
checks={i['file']:(HERE/i['file']).is_file() and sha(HERE/i['file'])==i['sha256'] for i in files}
frozen={'p3_export_ready':('p3/root_buttress_h10_p3_export_ready.blend','800aab5470b0c088d5fb9a36c48f659e726fb8ee4d54180af738c97f28e65e6a'),'p4':('p4/root_buttress_h10_form_p4.blend','38fcabb2c98cdd3f3ef2d07b8a5a357b7d013882e77d8dd396e7859d6f5e48fb'),'p5':('p5/root_buttress_h10_form_p5.blend','e32f515eea0dd041e5e4eef8e0b98d5dd395f785849c5a5d4ba733355d81d1d7')}
frozen_checks={n:sha(HERE.parent/p)==h for n,(p,h) in frozen.items()}
pngs=[i['file'] for i in files if i['file'].endswith('.png')]
result={'status':'EVIDENCE_CHECK_ONLY','manifest_sha256':sha(HERE/'manifest.json'),'file_count':len(files),'pngs':pngs,'file_sha_match':checks,'runtime_p2_unchanged':runtime,'prior_source_unchanged':frozen_checks,'source_hash_matches_report':manifest['source_blend_sha256']==report['source_sha256'],'all_pass':all(checks.values()) and all(runtime.values()) and all(frozen_checks.values()) and manifest['source_blend_sha256']==report['source_sha256'],'limits':'Does not validate aesthetic quality, renderer performance, whole-body collision or human comfort; form review failed.'}
(HERE/'selfcheck.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'files':len(files),'pngs':pngs,'all_pass':result['all_pass'],'source_sha256':manifest['source_blend_sha256'],'image_sha256':sha(HERE/'h10_p6_natural_stone_default.png'),'manifest_sha256':result['manifest_sha256']},ensure_ascii=False))
assert result['all_pass']
