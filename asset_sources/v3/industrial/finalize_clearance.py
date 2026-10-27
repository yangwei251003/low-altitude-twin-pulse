"""Finalize exact 2.8 m gate clearance, without rebuilding material textures."""
from pathlib import Path
import bpy,json,hashlib
ROOT=Path(__file__).resolve().parents[3]
SRC=ROOT/"asset_sources/v3/industrial";OUT=ROOT/"assets/v3/industrial"
EVID=ROOT/"artifacts/v3/art/industrial";REV=4
scene=bpy.context.scene
bpy.data.objects["HeadLowerBeam"].location.z=7.665
bpy.data.objects["RollerBarrel"].location.z=7.81
source_col=bpy.data.collections["Editable_Components"]
slats=[bpy.data.objects[f"Slat_{i:02d}"] for i in range(16)]
shutter=bpy.data.objects["Shutter"]
static=[o for o in source_col.objects if o.type=="MESH" and o not in slats]
materials={n:bpy.data.materials[n] for n in ["I_B_TealSaltPaint","I_B_PorousConcrete","I_B_BrushedSteel","I_B_Grating","I_B_Rubber","I_B_SafetyWear","I_B_ShutterSteel","I_B_RustFasteners"]}
source_info={"editable_static_components":len(static),"slat_count":len(slats),"missing_uv":[o.name for o in static+slats if not o.data.uv_layers]}
bpy.ops.wm.save_as_mainfile(filepath=str(SRC/"service_bridge.blend"))
scene.render.filepath=str(EVID/"service_bridge_review_v4.png")
bpy.ops.render.render(write_still=True)
code=(SRC/"build_service_bridge.py").read_text(encoding="utf-8")
exec(compile(code[code.index("# Export a copy;"):],str(SRC/"build_service_bridge.py"),"exec"))
