"""Resume existing native bake; no geometry or texture regeneration."""
from pathlib import Path
import bpy,json,hashlib,time,os
SRC=Path(__file__).resolve().parent
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
start=time.time();blend=SRC/'clinic_ground_p1.blend';before=sha(blend)
report=json.loads((SRC/'evidence/production_report.json').read_text(encoding='utf-8'))
assert report['status']=='BAKED_CHECKPOINT_PENDING_PREVIEW'
bpy.ops.wm.open_mainfile(filepath=str(blend));scene=bpy.context.scene
scene.render.threads_mode='FIXED';scene.render.threads=2;scene.cycles.device='CPU'
readback=[]
for n in bpy.data.materials['CGround_BakedPBR'].node_tree.nodes:
    if n.type!='TEX_IMAGE':continue
    im=n.image;p=Path(bpy.path.abspath(im.filepath)).resolve();row=next(r for r in report['baked_maps'] if r['role']==n.label)
    record={'role':n.label,'filepath':im.filepath,'resolved_path':str(p),'exists':p.exists(),'before_has_data':im.has_data,'before_size':list(im.size)}
    assert p.exists() and sha(p)==row['sha256']
    im.reload();record['after_reload_has_data']=im.has_data
    # In5.2 reload invalidates cache; actual pixel access forces lazy file loading.
    record['first_pixel']=list(im.pixels[:4]);record['actual_size']=list(im.size);record['has_data_after_pixel_access']=im.has_data
    record['sha256']=sha(p);record['colorspace']=im.colorspace_settings.name;readback.append(record)
    (SRC/'evidence/reopened_images_diagnostic.json').write_text(json.dumps(readback,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    assert len(record['first_pixel'])==4 and record['actual_size']==[2048,2048] and im.has_data
assert len(readback)==4 and sha(blend)==before
image_path=SRC/'evidence/clinic_ground_p1.png';scene.render.filepath=str(image_path);bpy.ops.render.render(write_still=True)
report.update(status='SOURCE_RENDERED_PENDING_HUMAN_REVIEW',reopened_images=readback,blend_sha256=sha(blend),render_sha256=sha(image_path),recovery_elapsed_seconds=time.time()-start,
              recovery_note='Actual PNG pixel access after reload verifies lazy loading. No rebake, no geometry change, no source save.')
(SRC/'evidence/production_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'stage':'end','pid':os.getpid(),'seconds':time.time()-start,'source_unchanged':sha(blend)==before}),flush=True)
