"""Resume only the saved, read-back-verified source. No source-file rewrite."""
from pathlib import Path
import sys,os,time,collections,math
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parent))
from build_source import *
from crop import topology

started=time.monotonic();out=HERE/'output';source=out/'i2_revetment_closure_editable.blend'
expected='2b8be5939de4f3a98f87aa9e7b940fdb94a1d18c41ce673077c48e0fc991fcdd'
assert sha(source)==expected and sha(SOURCE)==SOURCE_SHA
bpy.ops.wm.open_mainfile(filepath=str(source));bpy.context.view_layer.update()
before=signature();rows=[];render_triangles=0
for obj in bpy.data.objects:
    if obj.get('closure_export_surface'):
        obj.data.calc_loop_triangles();render_triangles+=len(obj.data.loop_triangles)
    if not obj.name.endswith('_ClosedEditable'):continue
    mesh=obj.data;mesh.calc_loop_triangles()
    edges=topology([{'ids':list(t.vertices)} for t in mesh.loop_triangles])
    assert all(len(v)==2 and v[0][1:]==v[1][1:][::-1] for v in edges.values()),obj.name
    assert all(math.isfinite(float(c)) for layer in mesh.uv_layers for row in layer.data for c in row.uv)
    points=[gp(obj.matrix_world@v.co) for v in mesh.vertices]
    rows.append({'name':obj.name,'triangles':len(mesh.loop_triangles),'closed_oriented_edges':True,
        'bounds':{'min':[min(p[i] for p in points) for i in range(3)],'max':[max(p[i] for p in points) for i in range(3)]},
        'uv_layers':[layer.name for layer in mesh.uv_layers]})
assert len(rows)==12
report={'status':'SOURCE_PREVIEW_RUNNING','pid':os.getpid(),'source_sha256':SOURCE_SHA,'editable_sha256':expected,
        'editable_readback_exact_geometry_uv_attributes':True,'signatures':before,'pieces':rows,'piece_count':12,
        'render_triangles':render_triangles,'scope':'source-only; previous geometry/readback PASS log retained; context-only node-name failure corrected'}
dump(out/'source_report.json',report)
print(json.dumps({'stage':'preview_resume','pid':os.getpid(),'pieces':12,'render_triangles':render_triangles}),flush=True)
render_preview(build_plan(),out)
assert signature()==before and sha(source)==expected and sha(SOURCE)==SOURCE_SHA
report.update(status='SOURCE_PREVIEW_COMPLETE_NOT_GAMEPLAY',elapsed_seconds=time.monotonic()-started,
              images=[{'path':str(out/(name+'.png')),'sha256':sha(out/(name+'.png'))} for name in ['01-default','02-south-joint']],
              unchanged_source=True,unchanged_preview_geometry=True)
dump(out/'source_report.json',report)
print(json.dumps({'stage':'preview_exit','pid':os.getpid(),'seconds':report['elapsed_seconds']}),flush=True)
