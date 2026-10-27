from pathlib import Path
import sys,os,time
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parent))
from common import *
from cleanup_microfaces import cleanup_body

def main():
    started=time.monotonic();assert sha(SOURCE)==SOURCE_SHA
    assert not (OUT/'bake_complete.blend').exists(),'preserve previous bake'
    print(json.dumps({'stage':'bake_start','pid':os.getpid(),'threads':2}),flush=True)
    report=json.loads((OUT/'prepared_clean_uv_report.json').read_text(encoding='utf-8'))
    assert report['status']=='CLEAN_UV_VERIFIED' and sha(OUT/'prepared_clean_uv.blend')==report['blend_sha256']
    bpy.ops.wm.open_mainfile(filepath=str(OUT/'prepared_clean_uv.blend'))
    scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=1
    scene.render.threads_mode='FIXED';scene.render.threads=2
    proxy=bpy.data.objects['DeliveryBakeProxy'];proxy.data.calc_loop_triangles()
    assert len(proxy.data.loop_triangles)==report['triangles']
    report.update(status='UV_CHECKPOINT',textures=[],lighting_not_baked=True,
        normal_limit='True mesh channels/bevels retained; flat panel near-neutral normal expected. No image pore color height conversion.',
        orm_ao='R constant 1; no authored ambient-occlusion claim')
    write_json(OUT/'bake_report.json',report)
    audit_images('before UV checkpoint');bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'uv_checkpoint.blend'),relative_remap=False)
    for channel in ['BaseColor','ORM','Normal']:
        report['textures'].append(bake(proxy,channel));report['status']='BAKED_'+channel
        write_json(OUT/'bake_report.json',report)
        audit_images('before '+channel+' checkpoint')
        bpy.ops.wm.save_as_mainfile(filepath=str(OUT/('checkpoint_'+channel+'.blend')),relative_remap=False)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'bake_complete.blend'),relative_remap=False)
    assert sha(SOURCE)==SOURCE_SHA
    report.update(status='BAKE_COMPLETE_PENDING_EXPORT',seconds=time.monotonic()-started,blend_sha256=sha(OUT/'bake_complete.blend'))
    write_json(OUT/'bake_report.json',report)
    print(json.dumps({'stage':'bake_exit','pid':os.getpid(),'seconds':time.monotonic()-started}),flush=True)

if __name__=='__main__':main()
