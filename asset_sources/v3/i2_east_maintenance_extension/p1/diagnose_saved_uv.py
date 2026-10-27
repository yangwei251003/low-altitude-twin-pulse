"""Read-only saved-source UV diagnosis. Needs root's serial Blender window."""
from pathlib import Path
import json, hashlib, math
import bpy

HERE = Path(__file__).resolve().parent
SOURCE = HERE / 'editable_source.blend'
ORIGIN = (20.7, 0.0, 8.8)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


before = sha(SOURCE)
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
records = []
top_count = 0
projection_bad = []
for obj in bpy.data.objects:
    if obj.type != 'MESH' or not obj.get('export_piece', False):
        continue
    mesh = obj.data
    mesh.update()
    for poly in mesh.polygons:
        normal = tuple(float(v) for v in poly.normal)
        axis = max(range(3), key=lambda i: abs(normal[i]))
        top_error = 0.0
        projection_error = 0.0
        for li in poly.loop_indices:
            p = mesh.vertices[mesh.loops[li].vertex_index].co
            x, y, z = p.x + ORIGIN[0], p.z, -p.y + ORIGIN[2]
            uv = tuple(mesh.uv_layers['ConcreteUV'].data[li].uv)
            pair = (x, z) if axis == 2 else (z, y) if axis == 0 else (x, y)
            projection_error = max(projection_error, math.hypot(uv[0]-pair[0]/4, uv[1]-pair[1]/4))
            top_error = max(top_error, math.hypot(uv[0]-x/4, uv[1]-z/4))
        record = {'object': obj.name, 'polygon': poly.index, 'normal': normal,
                  'dominant_axis': axis, 'top_uv_error': top_error,
                  'projection_uv_error': projection_error}
        if projection_error >= 1e-6:
            projection_bad.append(record)
        if normal[2] >= .7:
            top_count += 1
            if top_error >= 1e-6:
                records.append(record)
assert sha(SOURCE) == before
result = {'source_sha256': before, 'source_unchanged': True,
          'old_top_candidate_polygons': top_count, 'old_top_mismatches': records,
          'actual_projection_mismatches': projection_bad,
          'all_old_top_mismatches_are_nondominant_z': bool(records) and all(r['dominant_axis'] != 2 for r in records),
          'scope': 'read-only saved mesh; no material, geometry or scene change saved; no render'}
out = HERE / 'saved_uv_diagnosis.json'
assert not out.exists()
out.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps({'top_mismatches': len(records), 'projection_mismatches': len(projection_bad),
                  'all_old_top_mismatches_are_nondominant_z': result['all_old_top_mismatches_are_nondominant_z'],
                  'source_unchanged': True}), flush=True)
