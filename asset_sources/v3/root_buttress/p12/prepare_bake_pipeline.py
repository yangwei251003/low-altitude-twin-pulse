"""Copy the verified P11 bake/readback pipeline into the separately owned P12."""
from pathlib import Path
import shutil
HERE=Path(__file__).resolve().parent
PRIOR=HERE.parent/'p11'
shutil.copyfile(PRIOR/'bake_pbr_atlas.py',HERE/'bake_pbr_atlas.py')
text=(PRIOR/'bake_export_complete_p11.py').read_text(encoding='utf-8').replace('p11','p12').replace('P11','P12')
text=text.replace('root_buttress_h10_complete_p12.blend','root_buttress_h10_root_sections_p12.blend')
# Preserve current root/material geometry, plus exact source and prior candidate.
text=text.replace("runtime=report['runtime_P2_sha256'];ready=", "assert sha(HERE.parent/'p11/root_buttress_h10_complete_p11.blend')==report['input_P11_source_sha256']\nruntime=report['runtime_P2_sha256'];ready=")
(HERE/'bake_export_complete_p12.py').write_text(text,encoding='utf-8')
text=(PRIOR/'verify_complete_p11.py').read_text(encoding='utf-8').replace('p11','p12').replace('P11','P12')
text=text.replace('build_complete_p12.py','build_root_sections_p12.py')
text=text.replace("check('source_Sap_and_anchors_preserved',all(digest(bpy.data.objects[n])==v for n,v in src['fixed_hashes'].items()))", "check('source_Sap_and_anchors_preserved',all(digest(bpy.data.objects[n])==v for n,v in src['fixed_geometry_uv_transform_hashes'].items() if n!='RockMasses'))")
old="check('actual_GLB_original_bounds',all(bounds['min'][k]>=lo[k]-.0001 and bounds['max'][k]<=hi[k]+.0001 for k in range(3)),bounds)"
new="""authorized_hi=[hi[0]+.35,hi[1],hi[2]+.35]
extension={'old_min':lo,'old_max':hi,'authorized_max':authorized_hi,'actual':bounds,'actual_positive_extension':[max(0,bounds['max'][k]-hi[k]) for k in range(3)]}
check('actual_GLB_authorized_root_positive_xz_extension_bounds',all(bounds['min'][k]>=lo[k]-.0001 and bounds['max'][k]<=authorized_hi[k]+.0001 for k in range(3)),extension)"""
assert old in text
text=text.replace(old,new)
text=text.replace("'bounds_godot':bounds,'anchors_godot'", "'bounds_godot':bounds,'authorized_bounds':extension,'anchors_godot'")
text=text.replace("bpy.ops.wm.open_mainfile(filepath=str(ROOT/exp['ready_source']));", "bpy.ops.wm.open_mainfile(filepath=str(HERE/'root_buttress_h10_root_sections_p12.blend'));\ncheck('author_source_rock_Sap_anchors_fixed_to_P11',all(digest(bpy.data.objects[n])==v for n,v in src['fixed_geometry_uv_transform_hashes'].items()))\nbpy.ops.wm.open_mainfile(filepath=str(ROOT/exp['ready_source']));")
text=text.replace("check('runtime_P2_frozen',", "check('P11_candidate_frozen',sha(ROOT/'assets/v3/candidates/root_buttress_h10_p11/root_buttress_h10_p11.glb')=='d8e67fdaef057a9adb9fb10545eda90d867d730cb446511f735cfbd42d486f1f')\ncheck('runtime_P2_frozen',")
(HERE/'verify_complete_p12.py').write_text(text,encoding='utf-8')
print('P12 bake/readback scripts prepared; no Blender run, no bake/export performed')
