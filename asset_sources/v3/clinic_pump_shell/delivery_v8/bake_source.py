from pathlib import Path
import sys,json,time,os
sys.path.insert(0,str(Path(__file__).resolve().parent))
from common import *
def main():
    start=time.time();assert sha(SOURCE)==SOURCE_SHA;assert not (OUT/'bake_complete.blend').exists()
    print(json.dumps({'stage':'start_bake','pid':os.getpid(),'threads':2}),flush=True)
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE));scene=bpy.context.scene
    scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=1;scene.render.threads_mode='FIXED';scene.render.threads=2
    inputs=copy_inputs();parts=[o for o in bpy.data.objects if o.get('editable_piece')];assert len(parts)==200
    proxy,source_rows,materials=make_proxy(parts);uv=unique_uv(proxy)
    report={'status':'UV_CHECKPOINT','source_sha256':SOURCE_SHA,'source_parts':source_rows,'input_images':inputs,'material_audit':materials,'uv':uv,'textures':[],'lighting_not_baked':True,'single_proxy_reason':'All active material coordinates explicitly UV/loop-attribute based; attributes retained per source triangle.'}
    (OUT/'bake_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'uv_checkpoint.blend'),relative_remap=False)
    for channel in ['BaseColor','ORM','Normal']:
        report['textures'].append(bake(proxy,channel));report['status']='BAKED_'+channel
        (OUT/'bake_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        bpy.ops.wm.save_as_mainfile(filepath=str(OUT/('checkpoint_'+channel+'.blend')),relative_remap=False)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'bake_complete.blend'),relative_remap=False)
    assert sha(SOURCE)==SOURCE_SHA;report.update(status='BAKE_COMPLETE_PENDING_EXPORT',elapsed_seconds=time.time()-start,blend_sha256=sha(OUT/'bake_complete.blend'))
    (OUT/'bake_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'stage':'end_bake','pid':os.getpid(),'seconds':time.time()-start}),flush=True)
if __name__=='__main__':main()
