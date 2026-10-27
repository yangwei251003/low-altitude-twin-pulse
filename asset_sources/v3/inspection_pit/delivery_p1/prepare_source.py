import os,sys,time,traceback
from pathlib import Path
sys.dont_write_bytecode=True;sys.path.insert(0,str(Path(__file__).resolve().parent))
from common import *

def main():
    start=time.monotonic(); source_check()
    assert not (OUT/'prepared_bake.blend').exists()
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    images=image_audit(copy=True); assert len(images)==2, 'Source input image inventory changed'
    editable=OUT/'inspection_pit_editable.blend'
    # Resolve before save, then make paths relative in the actual saved context.
    bpy.ops.wm.save_as_mainfile(filepath=str(editable),relative_remap=False)
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath:
            im.filepath=bpy.path.relpath(str(Path(bpy.path.abspath(im.filepath)).resolve()))
    bpy.ops.wm.save_as_mainfile(filepath=str(editable),relative_remap=False)
    bpy.ops.wm.open_mainfile(filepath=str(editable)); reopened=image_audit()
    assert sorted((r['sha256'],r['size'],r['space']) for r in images)==sorted((r['sha256'],r['size'],r['space']) for r in reopened)
    parts=[o for o in bpy.data.objects if o.get('asset_id')=='I2:inspection_pit']
    assert len(parts)==CONTRACT['expected_parts'] and all(o.type=='MESH' for o in parts)
    grouped={name:[] for name in GROUPS}
    for ob in parts: grouped[group_for(ob)].append(ob)
    mapping={}; reports={}; uv={}; expected={}; proxies=[]
    for name,size in GROUPS.items():
        assert grouped[name], name
        proxy,face_map,report=make_proxy(grouped[name],name); proxies.append(proxy)
        mapping[name]=face_map; reports[name]=report
        uv[name]=atlas(proxy,face_map,size); expected[name]=triangle_rows(proxy.data)
    assert sum(r['triangles'] for r in reports.values())==CONTRACT['expected_triangles']
    for ob in parts: ob.hide_render=True; ob.hide_set(True)
    for ob in proxies: ob.hide_render=True; ob.hide_set(True)
    # Paths must survive the checkpoint's different filename.
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath: im.filepath=str(Path(bpy.path.abspath(im.filepath)).resolve())
    target=OUT/'prepared_bake.blend'; bpy.ops.wm.save_as_mainfile(filepath=str(target),relative_remap=False)
    source_check(); write('face_mapping.json',mapping); write('UV_report.json',uv)
    write('expected_low_triangles.json',expected)
    write('prepare_report.json',{'status':'PREPARED_NO_BAKE','source_sha256':SOURCE_SHA,
          'editable_sha256':sha(editable),'prepared_sha256':sha(target),'images':reopened,
          'groups':reports,'triangles':sum(r['triangles'] for r in reports.values()),
          'pid':os.getpid(),'seconds':time.monotonic()-start,
          'world_anchor':CONTRACT['world_anchor'],'no_geometry_remesh':True})

if __name__=='__main__':
    try: main()
    except Exception as e:
        write('prepare_failure.json',{'exception':repr(e),'traceback':traceback.format_exc(),'pid':os.getpid()})
        try:bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'failed_prepare.blend'),relative_remap=False)
        except Exception:pass
        raise
