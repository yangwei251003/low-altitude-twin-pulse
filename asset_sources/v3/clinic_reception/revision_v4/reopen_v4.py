"""Read-only saved-source reopen; no save, render, or export."""
from pathlib import Path
import hashlib
import json
import bpy

OUT = Path(__file__).resolve().parent
SOURCE = OUT / 'clinic_reception_v4.blend'
before = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
names = ['DoorLeft','DoorRight','RearRoof','CanopyLeft','CanopyRight','ReceptionLight','Stretcher','TreatmentBedGroup','ReceptionDeskGroup','ReceptionSign']
groups = {}
for name in names:
    obj = bpy.data.objects.get(name)
    assert obj is not None, name
    groups[name] = {'type':obj.type,'parent':obj.parent.name if obj.parent else None,'mesh_descendants':len([child for child in obj.children_recursive if child.type=='MESH'])}
roofs = [material for material in bpy.data.materials if material.name.endswith('_RoofOnly')]
assert len(roofs) == 5, len(roofs)
assert all(material.node_tree.nodes['ClinicPrincipled'].inputs['Alpha'].default_value == 1.0 for material in roofs)
assert len([obj for obj in bpy.context.scene.objects if obj.type == 'MESH']) > 0
after = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
assert before == after
result = {'status':'saved_blend_opened_without_modification','source_sha256':before,'same_bytes_after':before==after,'groups':groups,'roof_materials_saved_opaque':[material.name for material in roofs],'mesh_count':len([obj for obj in bpy.context.scene.objects if obj.type=='MESH'])}
(OUT/'reopen_v4.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('RECEPTION_V4_REOPEN='+json.dumps(result,ensure_ascii=False))
