"""One bounded repair: normalize existing source UV names and explicitly export.
No geometry generation, material changes, scene rebuild or rendering.
"""
import bpy,json,hashlib
from pathlib import Path
SOURCE=Path(__file__).resolve().parent
ROOT=SOURCE.parents[2]
OUT=ROOT/'assets/v3/fantasy'
ART=ROOT/'artifacts/v3/art/fantasy'
scene=bpy.context.scene
model_collection=bpy.data.collections['Editable_TempleGate']
model_objects=[o for o in model_collection.objects if o.type=='MESH']
rotor=bpy.data.objects['Rotor']
def geometry_signature():
    values=[(o.name,tuple(tuple(float(n) for n in row) for row in o.matrix_world),[tuple(float(n) for n in v.co) for v in o.data.vertices],[tuple(p.vertices) for p in o.data.polygons],[m.name for m in o.data.materials]) for o in sorted(model_objects,key=lambda o:o.name)]
    return hashlib.sha256(json.dumps(values,separators=(',',':')).encode()).hexdigest()
before=geometry_signature()
old_hash=hashlib.sha256((OUT/'temple_gate.glb').read_bytes()).hexdigest()
renamed=0
for obj in model_objects:
    assert len(obj.data.uv_layers)==1,(obj.name,len(obj.data.uv_layers))
    uv=obj.data.uv_layers[0]
    if uv.name!='PaintUV': renamed+=1
    uv.name='PaintUV'; obj.data.uv_layers.active_index=0; uv.active_render=True
assert geometry_signature()==before
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'temple_gate.blend'))
audit=json.loads((ART/'temple_gate_audit.json').read_text(encoding='utf-8'))
source=(SOURCE/'build_temple_gate.py').read_text(encoding='utf-8')
export_code=source.split('# Explicit GLB export.')[1].split('# Render the actual editable model.')[0]
exec('# Explicit GLB export.'+export_code,globals())
assert geometry_signature()==before
report={'status':'PASS','repair':'UV layer names and active UV only','source_mesh_count':len(model_objects),'renamed_uv_layers':renamed,'geometry_and_material_assignment_sha256_before':before,'geometry_and_material_assignment_sha256_after':geometry_signature(),'previous_glb_sha256':old_hash,'glb_sha256':hashlib.sha256((OUT/'temple_gate.glb').read_bytes()).hexdigest(),'glb_bytes':(OUT/'temple_gate.glb').stat().st_size,'rendered':False}
(ART/'temple_gate_uv_repair.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(report))
