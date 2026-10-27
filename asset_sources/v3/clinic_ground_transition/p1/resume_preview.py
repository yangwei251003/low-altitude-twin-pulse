from pathlib import Path
import bpy,json,time,hashlib,os
OUT=Path(__file__).resolve().parent
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
start=time.time();bpy.ops.wm.open_mainfile(filepath=str(OUT/'baked_source.blend'));reopened=[]
for im in bpy.data.images:
    if im.source=='FILE' and im.filepath:
        path=Path(bpy.path.abspath(im.filepath));assert path.is_file(),str(path);im.reload();pixel=tuple(im.pixels[:4]);assert len(pixel)==4 and im.has_data,(im.name,str(path));reopened.append({'path':str(path),'sha256':sha(path),'colorspace':im.colorspace_settings.name,'size':list(im.size)})
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.render.threads_mode='FIXED';scene.render.threads=2;scene.cycles.samples=24
image=OUT/'evidence/transition_source_p1.png';scene.render.filepath=str(image);bpy.ops.render.render(write_still=True)
report=json.loads((OUT/'geometry_report.json').read_text());maps=json.loads((OUT/'bake_report.json').read_text())['maps'];assert len(maps)==3
for r in maps:assert sha(r['path'])==r['sha256']
report.update(status='SOURCE_BAKED_RENDERED_PENDING_VISUAL_REVIEW',maps=maps,reopened_images=reopened,source_sha256=sha(OUT/'editable_source.blend'),baked_source_sha256=sha(OUT/'baked_source.blend'),preview_sha256=sha(image),seconds=time.time()-start,repair='No rebake: explicitly materialize image.pixels after reload before testing has_data (Blender lazy image load).')
(OUT/'production_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print(json.dumps({'pid':os.getpid(),'stage':'resume_end','seconds':time.time()-start}),flush=True)
