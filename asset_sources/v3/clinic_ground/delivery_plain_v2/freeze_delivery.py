"""Lightweight byte/readback freeze only, no Blender/Godot or image modification."""
from pathlib import Path
import json,hashlib,sys,datetime
HERE=Path(__file__).resolve().parent
sys.dont_write_bytecode=True
sys.path.insert(0,str(HERE.parent/'delivery_p2'))
from read_glb import read,node_identity
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 report=json.loads((HERE/'delivery_report.json').read_text(encoding='utf-8'))
 p=HERE/'clinic_ground_plain_v2.glb'
 assert sha(p)==report['glb_sha256'] and p.stat().st_size==report['glb_bytes']
 assert len(report['checks'])==54 and all(c['passed'] for c in report['checks'])
 j,actual,bb,images=read(p)
 assert len(actual)==6 and sum(sum(a['triangles'].values()) for a in actual.values())==2100
 assert len(j['materials'])==1 and len(j['textures'])==3 and len(images)==3
 assert all(node_identity(n) for n in j['nodes'])
 before=json.loads((HERE/'frozen_inputs_before.json').read_text(encoding='utf-8'))
 changed=[]
 for rel,item in before.items():
  q=HERE.parent/rel
  if not q.is_file() or q.stat().st_size!=item['bytes'] or sha(q)!=item['sha256']:changed.append(rel)
 assert not changed,changed
 adj=json.loads((HERE/'adjacency_report.json').read_text(encoding='utf-8'))
 assert len(adj['internal_seams'])==7 and all(s['passed'] for s in adj['internal_seams'])
 checks={'status':'BYTE_FREEZE_VERIFIED','glb_sha256':sha(p),'binary_checks':54,'frozen_input_files':len(before),'changed_frozen_files':changed,'triangles':2100,'mesh_count':6,'material_count':1,'image_count':3,'nodes_identity':True,'bounds':bb,'samplers':j.get('samplers'),'texture_sampler_indices':[t.get('sampler') for t in j['textures']],'seams':adj['internal_seams'],'scope':'Read-only binary and byte verification; no engine/render/human play result.'}
 (HERE/'delivery_selfcheck.json').write_text(json.dumps(checks,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 excluded={'manifest.json','manifest_selfcheck.json'}
 files=[{'path':str(q.relative_to(HERE)).replace('\\','/'),'bytes':q.stat().st_size,'sha256':sha(q)} for q in sorted(HERE.rglob('*')) if q.is_file() and q.name not in excluded]
 manifest={'status':'FROZEN_SHARED_GLB_DELIVERY','created_at':datetime.datetime.now().astimezone().isoformat(),'files':files,'external_frozen_inputs':'frozen_inputs_before.json','source_visual_review':'Root approved plain_v2 original AB/P2 joint PNGs before this export; no new render. Existing raw images unchanged.','limitations':['No Godot import/actual six-tile camera test performed in this task.','Only root integrates runtime scene/collision.','No whole-area art/performance pass.'],'excluded_self_referential_files':sorted(excluded)}
 (HERE/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 reloaded=json.loads((HERE/'manifest.json').read_text(encoding='utf-8'))
 bad=[x['path'] for x in reloaded['files'] if (HERE/x['path']).stat().st_size!=x['bytes'] or sha(HERE/x['path'])!=x['sha256']]
 assert not bad,bad
 summary={'status':'PASS','file_count':len(files),'total_bytes':sum(x['bytes'] for x in files),'manifest_sha256':sha(HERE/'manifest.json'),'mismatches':bad,'frozen_inputs_verified':len(before)}
 (HERE/'manifest_selfcheck.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 print(json.dumps(summary,ensure_ascii=False))
if __name__=='__main__':main()
