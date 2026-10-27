from pathlib import Path
import shutil,json,hashlib
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];out=HERE/'pre_coincident_cleanup';out.mkdir(exist_ok=False)
names=['build_rising_seal_p2.py','rising_seal_source_p2.blend','rising_seal_source_p2.png','source_report.json','rising_seal_p2_export_ready.blend','bake_report.json','export_report.json','glb_readback.json','duplicate_face_classification.json','bake_export_p2.py','verify_glb_p2.py']
items=[];sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
for name in names:
 p=HERE/name;target=out/name;shutil.copyfile(p,target);assert sha(p)==sha(target);items.append({'source':p.relative_to(ROOT).as_posix(),'copy':target.name,'sha256':sha(target)})
p=ROOT/'assets/v3/candidates/rising_seal_p2/rising_seal_p2.glb';shutil.copyfile(p,out/p.name);items.append({'source':p.relative_to(ROOT).as_posix(),'copy':p.name,'sha256':sha(p)})
(out/'archive.json').write_text(json.dumps({'stage':'failed strict geometry audit; before authorized exact reversed-face cleanup','items':items},indent=2)+'\n',encoding='utf-8')
print('Saved',len(items),'byte-identical artifacts')
