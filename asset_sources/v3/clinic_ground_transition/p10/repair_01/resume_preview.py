"""Only reopen immutable P10 source, diagnose image loading, render two views.
No construction, material editing, saving over sources, bake or GLB.
"""
from pathlib import Path
import json,hashlib,time,math,os
import bpy
from mathutils import Vector
HERE=Path(__file__).resolve().parent
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def write(name,data):(HERE/name).write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')

started=time.time()
manifest=json.loads((HERE/'failure_manifest.json').read_text(encoding='utf-8'))
assert all(sha(HERE/r['path'])==r['sha256'] for r in manifest['files'])
source=HERE/'preview_source.blend';source_hash=sha(source)
bpy.ops.wm.open_mainfile(filepath=str(source))
images=[]
for im in bpy.data.images:
    if im.source!='FILE' or not im.filepath:continue
    path=Path(bpy.path.abspath(im.filepath))
    row={'name':im.name,'stored_path':im.filepath,'resolved_path':str(path),'exists':path.exists(),'before_reload_has_data':bool(im.has_data)}
    images.append(row);write('resume_image_diagnostic.json',{'status':'READING','images':images})
    assert path.exists(),row
    row['sha256']=sha(path);im.reload();row['after_reload_has_data']=bool(im.has_data)
    # An explicit read requests the CPU pixel buffer; do not alter any pixels.
    row['first_pixel_rgba']=list(im.pixels[:4]);row['pixel_float_count']=len(im.pixels)
    row['after_pixel_read_has_data']=bool(im.has_data);row['size']=list(im.size);row['colorspace']=im.colorspace_settings.name
    write('resume_image_diagnostic.json',{'status':'READING','images':images})
    assert im.has_data and len(row['first_pixel_rgba'])==4 and all(math.isfinite(v) for v in row['first_pixel_rgba']),row
    assert row['pixel_float_count']==im.size[0]*im.size[1]*im.channels,row
write('reopened_images.json',{'actual_blend':source.name,'no_image_pixels_modified':True,'images':images})
scene=bpy.context.scene
assert scene.render.engine=='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=24
scene.render.threads_mode='FIXED';scene.render.threads=2
full=HERE/'evidence/transition_source_p10.png';close=HERE/'evidence/transition_contact_close_p10.png'
assert not full.exists() and not close.exists(),'Preserve existing renders'
scene.render.filepath=str(full);bpy.ops.render.render(write_still=True)
scene.camera.location+=Vector((-1.15,-.06,0));scene.camera.data.ortho_scale=2.5
scene.render.filepath=str(close);bpy.ops.render.render(write_still=True)
assert sha(source)==source_hash
assert all(sha(HERE/r['path'])==r['sha256'] for r in manifest['files'])
report=json.loads((HERE/'geometry_report.json').read_text(encoding='utf-8'))
report.update(status='P10_SOURCE_ONLY_RENDERED_PENDING_ART_REVIEW_NO_BAKE_NO_GLB',reopened_images=images,render_sha256=sha(full),close_render_sha256=sha(close),preview_source_sha256=source_hash,immutable_failure_inputs_unchanged=True,seconds=time.time()-started)
write('production_report.json',report)
write('resume_image_diagnostic.json',{'status':'REOPEN_AND_PIXEL_READ_PASSED_RENDERED','images':images,'no_image_pixels_modified':True})
print(json.dumps({'pid':os.getpid(),'stage':'resume_preview_finished','seconds':time.time()-started,'triangles':report['triangles'],'full':str(full),'close':str(close)}),flush=True)
