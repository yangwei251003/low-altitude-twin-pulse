"""Authorized P10 geometry/source-material preview; no bake, no GLB."""
from pathlib import Path
import importlib.util, json, time, os, sys, math, statistics
sys.dont_write_bytecode = True
import bpy
from mathutils import Vector
HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('p10_frozen_build', HERE/'build_asset.py')
B = importlib.util.module_from_spec(spec); spec.loader.exec_module(B)
H, P, S, M = B.H, B.P, B.S, B.M

def density_report(proxy):
    proxy.data.calc_loop_triangles()
    uv = proxy.data.uv_layers['BakeUV']
    area_world = area_uv = 0.0; values = []
    for tri in proxy.data.loop_triangles:
        mat = proxy.data.materials[tri.material_index]
        if not mat.name.startswith('SOURCE_P10_TwoScans') or tri.normal.z <= .15:
            continue
        co = [proxy.data.vertices[i].co for i in tri.vertices]
        coords = [Vector(uv.data[i].uv) for i in tri.loops]
        world = abs((co[1].x-co[0].x)*(co[2].y-co[0].y)-(co[1].y-co[0].y)*(co[2].x-co[0].x))*.5
        tex = abs((coords[1].x-coords[0].x)*(coords[2].y-coords[0].y)-(coords[1].y-coords[0].y)*(coords[2].x-coords[0].x))*.5
        if world > 1e-12:
            values.append(2048*math.sqrt(tex/world)); area_world += world; area_uv += tex
    assert values
    B.write('actual_uv_density.json', {'method':'Actual proxy loop-triangle BakeUV / XZ projected area. Planned 2048 bake density only; NO bake performed.', 'soil_triangle_count':len(values), 'projected_area_m2':area_world, 'allocated_uv_area':area_uv, 'at_2048_texels_per_m':{'min':min(values),'median':statistics.median(values),'max':max(values),'area_weighted':2048*math.sqrt(area_uv/area_world)}, 'source_texture_world_width_m':{'SoilScanUV':2.5,'RockScanUV':2.0}, 'native_source_images_px':2048})

def main():
    started=time.time()
    assert not (HERE/'geometry_attempt.blend').exists(), 'Preserve existing attempt first'
    for sub in ('evidence','source_inputs','textures'):(HERE/sub).mkdir(exist_ok=True)
    frozen={str(p):H.sha(p) for p in (HERE/'build_asset.py',HERE/'terrain_design.py',HERE/'scan_soil_material.py',HERE.parent/'p9/manifest.json',HERE.parent/'p9/editable_source.blend',HERE.parent/'p9/baked_source.blend')}
    M.verify_inputs(); bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
    atlas=bpy.data.images.load(str(H.ATLAS)); atlas.colorspace_settings.name='sRGB'
    mats={kind:P.author(kind,atlas) for kind in ('concrete','soil','seal','stone0','stone1','stone2','stone3')}
    B.build(mats)
    bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'geometry_attempt.blend'),relative_remap=False)
    report=S.OLD_GEOMETRY()
    report['checks'].append({'name':'actual_fracture_aggregate_buried_and_exposed','pass':all(r['inside_vertices']>0 and r['visible_exposed_vertices']>0 for r in P.EMBEDDED),'failed':[r for r in P.EMBEDDED if not(r['inside_vertices']>0 and r['visible_exposed_vertices']>0)]})
    report.update(highpoly_bake_triangles=0,low_mesh_changed_purposefully=True,terrain_method='Constrained XZ bed/bank height field',collision_status='No engine collision delivered or tested',budget_goal=8000,bake_performed=False,glb_exported=False)
    B.write('geometry_report.json',report)
    assert all(c['pass'] for c in report['checks']),[c for c in report['checks'] if not c['pass']]
    H.studio()
    bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'editable_source.blend'),relative_remap=False)
    editable_sha=H.sha(HERE/'editable_source.blend')
    proxy=B.proxy_uv(); H.attribute_audit(proxy); density_report(proxy)
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath:im.filepath=bpy.path.relpath(bpy.path.abspath(im.filepath))
    bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'preview_source.blend'),relative_remap=False)
    bpy.ops.wm.open_mainfile(filepath=str(HERE/'preview_source.blend'))
    images=[]
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath:
            path=Path(bpy.path.abspath(im.filepath)); assert path.exists(),str(path)
            im.reload(); assert im.has_data
            images.append({'path':str(path),'sha256':H.sha(path),'size':list(im.size),'colorspace':im.colorspace_settings.name})
    B.write('reopened_images.json',{'actual_blend':'preview_source.blend','images':images})
    scene=bpy.context.scene;scene.cycles.samples=24
    full=HERE/'evidence/transition_source_p10.png';scene.render.filepath=str(full);bpy.ops.render.render(write_still=True)
    scene.camera.location+=Vector((-1.15,-.06,0));scene.camera.data.ortho_scale=2.5
    close=HERE/'evidence/transition_contact_close_p10.png';scene.render.filepath=str(close);bpy.ops.render.render(write_still=True)
    assert all(H.sha(p)==digest for p,digest in frozen.items())
    assert H.sha(HERE/'editable_source.blend')==editable_sha
    M.verify_inputs()
    report.update(status='P10_SOURCE_ONLY_RENDERED_PENDING_ART_REVIEW_NO_BAKE_NO_GLB',reopened_images=images,render_sha256=H.sha(full),close_render_sha256=H.sha(close),editable_sha256=editable_sha,frozen_inputs_unchanged=True,seconds=time.time()-started)
    B.write('production_report.json',report)
    print(json.dumps({'pid':os.getpid(),'stage':'end','seconds':time.time()-started,'triangles':report['triangles'],'render':str(full)}),flush=True)

if __name__=='__main__':main()
