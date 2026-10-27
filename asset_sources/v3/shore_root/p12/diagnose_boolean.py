"""Locate crossings in the copied original and the bounded Boolean result."""
import bpy,json,sys,runpy
from pathlib import Path
OUT=Path(__file__).resolve().parent
sys.path.insert(0,str(OUT))
from geometry_checks import strict_self_intersections
try:
    runpy.run_path(str(OUT/'build_shore_root_p12.py'),run_name='__main__')
except AssertionError as error:
    print('EXPECTED_FAILED_GATE_FOR_DIAGNOSIS',str(error),flush=True)
def audit(ob):
    r=strict_self_intersections(ob)
    ob.data.calc_loop_triangles()
    for item in r['strict_crossings']:
        tris=[]
        for index in item['triangles']:
            tri=ob.data.loop_triangles[index]
            points=[ob.matrix_world@ob.data.vertices[k].co for k in tri.vertices]
            tris.append({'indices':list(tri.vertices),'godot_points':[[p.x,p.z,-p.y] for p in points],
                         'area':tri.area,'polygon':tri.polygon_index})
        item['geometry']=tris
    return r
before=bpy.data.objects.get('BeforeP12_P10_HighShoulder_ContinuousThickCliff')
after=bpy.data.objects.get('Rock_HighShoulder')
result={'before':audit(before),'after':audit(after)}
(OUT/'boolean_crossing_diagnosis.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print('DIAGNOSIS_COMPLETE',[(k,len(v['strict_crossings'])) for k,v in result.items()],flush=True)
