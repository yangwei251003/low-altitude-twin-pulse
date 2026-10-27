"""One evidence-backed export correction; no bake or render."""
from pathlib import Path
import bpy,hashlib,json,shutil
HERE=Path(__file__).resolve().parent
OUT=HERE/'delivery_20261020_210356_971083'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    report=json.loads((OUT/'delivery_report.json').read_text())
    glb=OUT/'f1_thermal_stone.glb';assert sha(glb)==report['glb_sha256']
    shutil.copyfile(glb,OUT/'f1_thermal_stone.pre_color_fix.glb')
    bpy.ops.wm.open_mainfile(filepath=str(OUT/'f1_thermal_stone_delivery.blend'))
    for name in ['TemperatureCore','HeatInlays']:
        ob=bpy.data.objects[name];assert len(ob.data.color_attributes)==1
        ob.data.color_attributes.render_color_index=0;ob.data.color_attributes.active_color_index=0
    # Local relative cached textures remain usable when the project is moved.
    for im in bpy.data.images:
        if im.source=='FILE' and not im.packed_file:
            path=Path(bpy.path.abspath(im.filepath)).resolve()
            if path.is_relative_to(OUT):im.filepath=bpy.path.relpath(str(path),start=str(OUT))
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'f1_thermal_stone_delivery.blend'),relative_remap=False)
    bpy.ops.wm.open_mainfile(filepath=str(OUT/'f1_thermal_stone_delivery.blend'))
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,export_yup=True,
        export_apply=False,export_texcoords=True,export_normals=True,export_tangents=True,export_materials='EXPORT',
        export_vertex_color='ACTIVE',export_all_vertex_colors=False,export_cameras=False,export_lights=False,export_animations=False)
    report['previous_glb_sha256']=report['glb_sha256'];report['glb_sha256']=sha(glb);report['bytes']=glb.stat().st_size
    report['export_correction']='explicit render_color_index=0 after replacing source color layers; no rebake/render'
    (OUT/'delivery_report.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print('THERMAL_COLOR_REEXPORT_PASS',flush=True)
if __name__=='__main__':main()
