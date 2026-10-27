"""One-time p6 export-name correction; no geometry, UV, image or shader edits.
Future full rebuilds use the corrected bake_candidate_surfaces runtime_name.
"""
import bpy,json,hashlib
from pathlib import Path
HERE=Path(__file__).resolve().parent;PROJECT=HERE.parents[4]
BLEND=HERE/'parasitic_crown_p6.blend';GLB=PROJECT/'assets/v3/candidates/crown_p6/parasitic_crown.glb'
bpy.ops.wm.open_mainfile(filepath=str(BLEND))
objects=list(bpy.data.collections['Crown_EDITABLE_MASTER'].objects)
meshes=[o for o in objects if o.type=='MESH'];unique=set(o.data.materials[0]for o in meshes)
names=['Crown_WarmStone','Crown_ChestnutBark','Crown_LeafMembrane','Crown_AmberCore'];changes=[]
for m in unique:
    desired=next(name for name in names if m.name.startswith(name))
    assert bpy.data.materials.get(desired)is None
    changes.append({'before':m.name,'after':desired});m.name=desired
assert {m.name for m in unique}==set(names)
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
bpy.ops.object.select_all(action='DESELECT')
for o in objects:o.select_set(True)
bpy.context.view_layer.objects.active=bpy.data.objects['ParasiticCrown']
bpy.ops.export_scene.gltf(filepath=str(GLB),export_format='GLB',use_selection=True,export_apply=True,export_yup=True,export_extras=True,export_texcoords=True,export_normals=True,export_materials='EXPORT',export_cameras=False,export_lights=False,export_animations=False)
digest=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
report=json.loads((HERE/'surface_review.json').read_text(encoding='utf-8'))
report['material_name_correction']=changes;report['blend_sha256']=digest(BLEND);report['glb_sha256']=digest(GLB);report['glb_bytes']=GLB.stat().st_size
report['rebuild_script_sha256']=digest(HERE/'build_p6_surfaces.py');report['bake_helper_sha256']=digest(HERE/'bake_candidate_surfaces.py')
(HERE/'surface_review.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('P6_NAMES_NORMALIZED',report['glb_sha256'],flush=True)
