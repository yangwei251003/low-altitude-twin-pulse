"""Explicitly authorized bake stage only. No export, render or runtime writes."""
from pathlib import Path
import os
import sys
import time

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import *


def main():
    started = time.monotonic()
    assert sha(SOURCE) == SOURCE_SHA
    assert not (OUT/'bake_report.json').exists(), 'Preserve earlier failure/outputs; do not overwrite a run.'
    print(json.dumps({'stage':'bake_start', 'pid':os.getpid(), 'threads':2}), flush=True)
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = 1
    scene.render.threads_mode = 'FIXED'
    scene.render.threads = 2
    parts = source_parts()
    image_inputs = copy_images()
    cap_report = fix_end_uv(parts)
    write_json(OUT/'end_uv_correction.json', cap_report)
    corrected = OUT/'shared_access_bridge_deck_editable.blend'
    bpy.ops.wm.save_as_mainfile(filepath=str(corrected), relative_remap=False)
    proxy, rows, audit = make_proxy(parts)
    uv = unique_uv(proxy)
    report = {'status':'UV_CHECKPOINT', 'source_sha256':SOURCE_SHA, 'editable_corrected_sha256':sha(corrected),
              'source_parts':rows, 'input_images':image_inputs, 'material_audit':audit, 'uv':uv,
              'textures':[], 'lighting_not_baked':True, 'runtime_files_written':False,
              'end_uv_correction_sha256':sha(OUT/'end_uv_correction.json')}
    write_json(OUT/'bake_report.json', report)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'uv_checkpoint.blend'), relative_remap=False)
    for channel in ['BaseColor','ORM','Normal']:
        report['textures'].append(bake(proxy, channel))
        report['status'] = 'BAKED_'+channel
        write_json(OUT/'bake_report.json', report)
        bpy.ops.wm.save_as_mainfile(filepath=str(OUT/('checkpoint_'+channel+'.blend')), relative_remap=False)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'bake_complete.blend'), relative_remap=False)
    assert sha(SOURCE) == SOURCE_SHA
    report.update(status='BAKE_COMPLETE_PENDING_EXPORT', elapsed_seconds=time.monotonic()-started,
                  blend_sha256=sha(OUT/'bake_complete.blend'))
    write_json(OUT/'bake_report.json', report)
    print(json.dumps({'stage':'bake_exit', 'pid':os.getpid(), 'seconds':report['elapsed_seconds']}), flush=True)


if __name__ == '__main__':
    main()
