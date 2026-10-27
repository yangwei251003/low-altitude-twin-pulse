"""Load only a measured, accepted source-shape repair into the P12 builder."""
import bpy,json,hashlib
from pathlib import Path
OUT=Path(__file__).resolve().parent
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def repair(target,collection):
    report=json.loads((OUT/'measured_surface_repair.json').read_text())
    path=OUT/'measured_surface_repair.blend'
    assert report['all_pass'] and sha(path)==report['repaired_blend_sha256']
    assert sha(OUT/'plain_voxel_unfiltered.blend')==report['unfiltered_blend_sha256']
    with bpy.data.libraries.load(str(path),link=False) as (available,data):
        data.objects=['P10_HighShoulder_ContinuousThickCliff']
    source=data.objects[0]
    assert max(abs(target.matrix_world[r][c]-source.matrix_world[r][c]) for r in range(4) for c in range(4))<1e-6
    target.data=source.data.copy();bpy.data.objects.remove(source,do_unlink=True)
    return {'method':'measured plain-volume repair with six listed artifact shells removed, eleven healthy tips restored and one known defective-source cavity corrected',
            'repaired_blend_sha256':sha(path),'bounded_source_repair_rule_pass':True,
            'source_vertex_to_repaired_surface_max_m':report['source_to_repaired_sampled_max_m'],
            'repaired_vertex_to_source_surface_max_m':report['repaired_to_source_sampled_max_m'],
            'removed_shell_vertices':report['removed_vertex_count'],
            'max_local_vertex_displacement_m':report['max_vertex_displacement_m'],
            'complete_report':'measured_surface_repair.json','not_analytic_hausdorff_bound':True}
