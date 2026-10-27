"""Run after loading service_bridge.blend; validates source and renders open pose."""
from pathlib import Path
import bpy,json,sys
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[3]
EVID=ROOT/"artifacts/v3/art/industrial"
scene=bpy.context.scene
deps=bpy.context.evaluated_depsgraph_get()
components=list(bpy.data.collections["Editable_Components"].objects)
shutter=bpy.data.objects["Shutter"]
slats=[bpy.data.objects[f"Slat_{i:02d}"] for i in range(16)]
image_paths=[(im.name,Path(bpy.path.abspath(im.filepath))) for im in bpy.data.images if im.source=="FILE"]
underpass=[]
for y in (-1.5,0,1.5):
    for z in (.5,2.0,3.6):
        hit=scene.ray_cast(deps,Vector((-3.9,y,z)),Vector((1,0,0)),distance=7.8)
        underpass.append({"y":y,"z":z,"clear":not hit[0],"hit":hit[4].name if hit[0] else None})
bounds=[]
for o in components:
    if o.type=="MESH":
        bounds.extend([o.matrix_world@Vector(c) for c in o.bound_box])
lo=[min(v[i] for v in bounds) for i in range(3)]
hi=[max(v[i] for v in bounds) for i in range(3)]
report={"blend":bpy.data.filepath,"blender_version":bpy.app.version_string,
"reopened_source":True,"editable_objects":len(components),
"source_dimensions_z_up":[hi[i]-lo[i] for i in range(3)],"source_bounds":{"min":lo,"max":hi},
"shutter_type":shutter.type,"shutter_origin":list(shutter.location),
"slats_direct_children":all(o.parent==shutter for o in slats),
"all_slats_same_material":len({o.data.materials[0].name for o in slats})==1,
"textures_existing":all(p.is_file() for _,p in image_paths),"external_texture_count":len(image_paths),
"texture_paths":[{"name":n,"path":str(p),"exists":p.is_file()} for n,p in image_paths],
"underpass_geometry_rays":underpass,"underpass_all_clear":all(row["clear"] for row in underpass),
"rails_gap_center_clear":not scene.ray_cast(deps,Vector((0,-2.5,5.3)),Vector((0,1,0)),distance=3.9)[0],
"collision_test_status":"Blender mesh rays only; no Godot collider test"}
# Check the complete nominal rail interval, including feet, not only its centre.
rail_nodes=[o for o in components if o.type=="MESH" and o.name.startswith(("RailTube","RailPost","RailFoot","YellowPostCap"))]
rail_intrusions=[]
for o in rail_nodes:
    points=[o.matrix_world@Vector(c) for c in o.bound_box]
    xmin=min(p.x for p in points); xmax=max(p.x for p in points)
    if xmin<2.3 and xmax> -2.3:rail_intrusions.append(o.name)
report["rail_gap_full_interval_clear"]=not rail_intrusions
report["rail_gap_intrusions"]=rail_intrusions
report["outer_width_within_4m"]=hi[1]-lo[1]<=4.0001
opening_intrusions=[]
gate_lo=(-2.2,1.60,4.80); gate_hi=(2.2,1.90,7.60)
for o in components:
    if o.type!="MESH" or o in slats:continue
    points=[o.matrix_world@Vector(c) for c in o.bound_box]
    omin=[min(p[k] for p in points) for k in range(3)]
    omax=[max(p[k] for p in points) for k in range(3)]
    if all(omin[k]<gate_hi[k]-.0001 and omax[k]>gate_lo[k]+.0001 for k in range(3)):
        opening_intrusions.append(o.name)
report["open_gate_static_aabb_intrusions"]=opening_intrusions
report["open_gate_4_4_by_2_8_clear"]=not opening_intrusions
(EVID/"source_validation.json").write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding="utf-8")
# Show the fully open state without saving this pose into the closed .blend.
for o in slats:o.hide_render=True
scene.cycles.samples=20
scene.render.filepath=str(EVID/"service_bridge_open.png")
bpy.ops.render.render(write_still=True)
print("SOURCE_VALIDATION "+json.dumps(report,ensure_ascii=False))
