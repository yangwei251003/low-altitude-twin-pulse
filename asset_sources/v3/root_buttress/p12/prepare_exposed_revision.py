"""Archive the first P12 source trial and prepare only the authorized local fit revision."""
from pathlib import Path
import shutil, hashlib, json
HERE=Path(__file__).resolve().parent
archive=HERE/'recessed_roots_v1'
archive.mkdir(exist_ok=True)
names=['.gdignore','build_root_sections_p12.py','root_buttress_h10_root_sections_p12.blend','h10_p12_root_sections_source.png','p12_source_report.json','build_source.log','README.md','manifest.json','selfcheck.json','freeze_p12.py']
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
items=[]
for name in names:
    src=HERE/name; dst=archive/name
    if dst.exists():
        raise RuntimeError('Archive already exists; do not overwrite/reapply: '+name)
    shutil.copyfile(src,dst)
    assert sha(src)==sha(dst)
    items.append({'name':name,'sha256':sha(dst),'bytes':dst.stat().st_size})
(archive/'archive_inventory.json').write_text(json.dumps({'status':'historical recessed-root trial; not current revision','files':items},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
p=HERE/'build_root_sections_p12.py'
text=p.read_text(encoding='utf-8')
text=text.replace('tip = max(0, min(1, (p.y - 1.95) / .25))','tip = max(0, min(1, (p.y - 2.03) / .17))')
text=text.replace('bury = .10 + 1.35 * (tip * tip * (3 - 2 * tip))','bury = -.40 + 1.15 * (tip * tip * (3 - 2 * tip))')
text=text.replace("if spec['side'] != 'front': bury += 1.05 *", "if spec['side'] != 'front': bury += .50 *")
start=text.index('    # Shift a short local section INTO the rock')
end=text.index('    clean(ob)',start)
text=text[:start]+'''    # Root may extend +0.35m beyond prior positive X/Z bounds. Do not bury
    # whole sections to force the former conservative box. Only the authored
    # small end taper above enters the rock; the root section stays full.
    for v, q in zip(ob.data.vertices, coords):
        u, y, depth = q
        v.co = bp((u,y,depth) if spec['side']=='front' else (depth,y,u))
'''+text[end:]
text=text.replace("'normal section restored; lateral width slightly reduced; local section translated inward only at bounds; end tips embedded'", "'restored normal section; continuous main fork lightly exposed; only last 0.17 source m enters rock; no section translation for bounds'")
text=text.replace("'max_local_inward_shift':max(corrections)","'main_bury':-.40,'tip_source_interval':[2.03,2.2],'boundary_driven_translation':False")
old="check('original_bounds',all(bounds['min'][k]>=lo[k]-.0001 and bounds['max'][k]<=hi[k]+.0001 for k in range(3)),bounds)"
new="""authorized_hi=[hi[0]+.35,hi[1],hi[2]+.35]
extension={'old_min':lo,'old_max':hi,'authorized_max':authorized_hi,'actual':bounds,'actual_positive_extension':[max(0,bounds['max'][k]-hi[k]) for k in range(3)]}
check('authorized_root_positive_xz_extension_bounds',all(bounds['min'][k]>=lo[k]-.0001 and bounds['max'][k]<=authorized_hi[k]+.0001 for k in range(3)),extension)"""
assert old in text
text=text.replace(old,new)
text=text.replace("'bounds_godot':bounds,'anchors_godot'", "'bounds_godot':bounds,'authorized_bounds':extension,'runtime_P2_sha256':runtime,'anchors_godot'")
p.write_text(text,encoding='utf-8')
print(json.dumps({'archived_files':len(items),'archive':str(archive),'source_change':'main bury .10→-.40; only local tip burial; remove all boundary pushing; permit +.35m positive X/Z roots'},ensure_ascii=False))
