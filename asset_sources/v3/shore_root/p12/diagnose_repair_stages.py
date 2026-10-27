"""Diagnostic only: stop after repair, before upper cut or any rendering."""
import bpy,bmesh,sys,json
from pathlib import Path
OUT=Path(__file__).resolve().parent;sys.path.insert(0,str(OUT))
from repair_closed_stone import repair,clip
from geometry_checks import strict_self_intersections
bpy.ops.wm.open_mainfile(filepath=str(OUT.parent/'p10/root_shoulder_contact_p10.blend'))
high=bpy.data.objects['P10_HighShoulder_ContinuousThickCliff'];collection=high.users_collection[0]
oldstrip=high.copy();oldstrip.data=high.data.copy();collection.objects.link(oldstrip);clip(oldstrip,3.5,False)
legacy=strict_self_intersections(oldstrip,limit=10)
(OUT/'p12_original_strip_x3_5.json').write_text(json.dumps(legacy,indent=2),encoding='utf-8')
bpy.data.objects.remove(oldstrip,do_unlink=True)
report=repair(high,collection)
report['remesh_preserve_volume']=high.data.use_remesh_preserve_volume
(OUT/'p12_repair_stage_diagnosis.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('REPAIR_DIAGNOSIS_COMPLETE',report['source_vertex_to_repaired_surface_max_m'],flush=True)
