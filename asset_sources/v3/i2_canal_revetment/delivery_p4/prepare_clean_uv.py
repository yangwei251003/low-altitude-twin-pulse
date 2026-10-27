from pathlib import Path
import sys,os,time
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parent))
from common import *
from cleanup_microfaces import cleanup_body

def main():
    started=time.monotonic();assert sha(SOURCE)==SOURCE_SHA
    print(json.dumps({'stage':'clean_uv_start','pid':os.getpid()}),flush=True)
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE));inputs=copy_inputs()
    parts=[o for o in bpy.data.objects if o.get('editable_piece')];assert len(parts)==8
    cleanup=cleanup_body(parts)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'i2_canal_revetment_editable.blend'),relative_remap=False)
    proxy,rows,materials=make_proxy(parts);uv=unique_uv(proxy)
    audit_images('clean UV checkpoint')
    path=OUT/'prepared_clean_uv.blend';bpy.ops.wm.save_as_mainfile(filepath=str(path),relative_remap=False)
    report={'status':'CLEAN_UV_VERIFIED','source_sha256':SOURCE_SHA,'input_images':inputs,'source_parts':rows,
        'material_audit':materials,'uv':uv,'local_cleanup':cleanup,'triangles':sum(r['triangles'] for r in rows),
        'blend_sha256':sha(path),'seconds':time.monotonic()-started}
    write_json(OUT/'prepared_clean_uv_report.json',report)
    print(json.dumps({'stage':'clean_uv_exit','pid':os.getpid(),'triangles':report['triangles'],'seconds':time.monotonic()-started}),flush=True)

if __name__=='__main__':main()
