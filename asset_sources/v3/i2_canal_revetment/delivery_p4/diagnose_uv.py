"""One deterministic, non-rendering reproduction of the original UV failure."""
from pathlib import Path
import sys, os, time
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parent))
from common import *

def main():
    print(json.dumps({'stage':'uv_diagnostic_start','pid':os.getpid(),'threads':2}),flush=True)
    started=time.monotonic();dest=OUT/'uv_diagnostic_01';dest.mkdir(exist_ok=False)
    assert sha(SOURCE)==SOURCE_SHA
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    # Resolve paths before writing the diagnostic blend into a different directory.
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath:im.filepath=bpy.path.abspath(im.filepath)
    parts=[o for o in bpy.data.objects if o.get('editable_piece')]
    proxy,source_rows,materials=make_proxy(parts)
    failure=None
    try:unique_uv(proxy)
    except AssertionError as exc:failure=str(exc)
    assert failure=='collapsed BakeUV triangle',failure
    me=proxy.data;uv=me.uv_layers['DeliveryBakeUV'];me.calc_loop_triangles()
    source_at=[]
    for row in source_rows:source_at.extend([row['name']]*row['triangles'])
    bad=[];areas=[]
    for index,tri in enumerate(me.loop_triangles):
        a,b,c=[uv.data[i].uv.copy() for i in tri.loops]
        area=abs((b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x))*.5;areas.append(area)
        if area<=1e-14:
            p=[me.vertices[i].co.copy() for i in tri.vertices]
            cross=(p[1]-p[0]).cross(p[2]-p[0]);size=cross.length*.5
            bad.append({'index':index,'source_piece':source_at[index], 'polygon':tri.polygon_index,
                'vertices':list(tri.vertices),'positions_blender':[list(x) for x in p],
                'positions_godot':[gp(x) for x in p],'3d_area':size,'normal':list(cross.normalized()),
                'polygon_normal':list(me.polygons[tri.polygon_index].normal),'bake_uv_area':area,
                'bake_uv':[list(x) for x in (a,b,c)],
                'source_uv':{n:[list(me.uv_layers[n].data[i].uv) for i in tri.loops] for n in UVS},
                'edge_lengths':[(p[(j+1)%3]-p[j]).length for j in range(3)]})
    report={'failure':failure,'triangle_count':len(areas),'bad_count':len(bad),'min_area':min(areas),
        'source_sha256':sha(SOURCE),'native_operator':'uv.smart_project','angle_limit_degrees':66,
        'island_margin':.004,'source_rows':source_rows,'bad_triangles':bad,
        'geometry_changed':False,'bake_or_render_run':False,'seconds':time.monotonic()-started}
    write_json(dest/'diagnostic.json',report)
    bpy.ops.wm.save_as_mainfile(filepath=str(dest/'failed_bake_uv.blend'),relative_remap=False)
    assert sha(SOURCE)==SOURCE_SHA
    print(json.dumps({'stage':'uv_diagnostic_exit','pid':os.getpid(),'bad_count':len(bad),'seconds':time.monotonic()-started}),flush=True)

if __name__=='__main__':main()
