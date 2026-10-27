"""One bounded repair of a known image-path defect. Preserve every first-run byte."""
from pathlib import Path
import bpy,json,hashlib,time,os
SRC=Path(__file__).resolve().parent
FIRST=SRC/'clinic_gravity_production_candidate.blend'
DEST=SRC/'clinic_gravity_production_candidate_v2.blend'
EV=SRC/'evidence'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def geometry_hash():
 rows=[]
 for o in sorted(bpy.data.objects,key=lambda v:v.name):
  if o.type=='MESH':rows.append([o.name,[[float(x) for x in row] for row in o.matrix_world],[[float(x) for x in v.co] for v in o.data.vertices],[list(p.vertices) for p in o.data.polygons]])
 return hashlib.sha256(json.dumps(rows,separators=(',',':')).encode()).hexdigest()
assert not DEST.exists(),'Never overwrite a repaired candidate without archival decision.'
start=time.time();first_sha=sha(FIRST)
original=json.loads((EV/'production_report.json').read_text(encoding='utf8'))
print(json.dumps({'stage':'path_fix_start','pid':os.getpid()}),flush=True)
bpy.ops.wm.open_mainfile(filepath=str(FIRST))
before=geometry_hash();bound=[]
for im in bpy.data.images:
 name=Path(im.filepath).name
 if not name.startswith('CG_SurfaceAtlas_'):continue
 target=SRC/'textures'/name
 role=name.removeprefix('CG_SurfaceAtlas_').removesuffix('.png')
 assert target.is_file() and sha(target)==original['texture_sha256'][role]
 im.filepath=str(target.resolve());im.reload()
 assert tuple(im.size)==(2048,2048)
 bound.append(name)
assert len(bound)==4
bpy.ops.wm.save_as_mainfile(filepath=str(DEST),relative_remap=False)
for im in bpy.data.images:
 if Path(im.filepath).name in bound:im.filepath='//textures/'+Path(im.filepath).name
bpy.ops.wm.save_as_mainfile(filepath=str(DEST),relative_remap=False)
# Reopen the saved actual file; no reliance on the previous in-memory image objects or cwd.
bpy.ops.wm.open_mainfile(filepath=str(DEST))
after=geometry_hash();assert after==before,'The path repair must not alter geometry/transforms.'
image_rows=[]
for im in bpy.data.images:
 name=Path(im.filepath).name
 if name not in bound:continue
 resolved=Path(bpy.path.abspath(im.filepath)).resolve();expected=(SRC/'textures'/name).resolve()
 assert resolved==expected and resolved.is_file(),(im.filepath,str(resolved))
 im.reload();assert tuple(im.size)==(2048,2048) and im.has_data
 role=name.removeprefix('CG_SurfaceAtlas_').removesuffix('.png')
 assert sha(resolved)==original['texture_sha256'][role]
 assert im.colorspace_settings.name==('sRGB' if role=='BaseColor' else 'Non-Color')
 image_rows.append({'role':role,'saved_path':im.filepath,'resolved_path':str(resolved),'sha256':sha(resolved),'size':list(im.size),'loaded':im.has_data,'colorspace':im.colorspace_settings.name})
assert len(image_rows)==4
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.render.threads_mode='FIXED';scene.render.threads=2
image=EV/'clinic_gravity_production_candidate_v2.png';scene.render.filepath=str(image)
scene.render.image_settings.file_format='PNG'
bpy.ops.render.render(write_still=True)
assert image.is_file() and sha(FIRST)==first_sha
report={'status':'PATH_REPAIR_RENDERED_PENDING_VISUAL_REVIEW','pid':os.getpid(),'first_run_status':'FAILED_MISSING_4_TEXTURES_MAGENTA_NOT_ART_ACCEPTED','first_blend_sha256':first_sha,'geometry_hash_before':before,'geometry_hash_after_reopen':after,'geometry_unchanged':before==after,'actual_saved_blend_reopened':True,'images':image_rows,'blend_sha256':sha(DEST),'image_sha256':sha(image),'elapsed_seconds':time.time()-start,'scope':'Source-only same-geometry texture-path repair; no GLB/Godot/runtime or art acceptance.'}
(EV/'path_repair_v2.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
print(json.dumps({'stage':'path_fix_end','pid':os.getpid(),'seconds':report['elapsed_seconds'],'loaded_images':len(image_rows),'geometry_unchanged':before==after}),flush=True)
