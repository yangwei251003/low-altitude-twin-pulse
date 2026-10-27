"""Bounded read-only visibility comparison. Explicit root Blender window only."""
from pathlib import Path
import sys, json, hashlib, struct
sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import render_north_joint as review
import bpy


def matrix(m):
    return [list(row) for row in m]


def authored_world(obj):
    return authored_world(obj.parent) @ obj.matrix_parent_inverse @ obj.matrix_basis if obj.parent else obj.matrix_basis.copy()


def mesh_data_hash(obj):
    h = hashlib.sha256()
    for v in obj.data.vertices:
        h.update(struct.pack('<3f', *v.co))
    for p in obj.data.polygons:
        h.update(struct.pack('<II', len(p.vertices), p.material_index))
        h.update(struct.pack('<'+'I'*len(p.vertices), *p.vertices))
    for uv in obj.data.uv_layers:
        h.update(uv.name.encode())
        for corner in uv.data:
            h.update(struct.pack('<2f', *corner.uv))
    for mat in obj.data.materials:
        h.update(mat.name.encode())
    return h.hexdigest()


def objects_state():
    result = {}
    objects = review.all_objects()
    roots = {o.parent for o in objects if o.parent}
    for obj in objects + list(roots):
        result[obj.name] = {'mesh_data': mesh_data_hash(obj) if obj.type == 'MESH' else None,
                            'parent': obj.parent.name if obj.parent else None,
                            'basis': matrix(obj.matrix_basis), 'parent_inverse': matrix(obj.matrix_parent_inverse),
                            'evaluated_world': matrix(obj.matrix_world), 'authored_world': matrix(authored_world(obj))}
    return result


def material_state():
    records = {}
    for mat in {m for o in review.all_objects() for m in o.data.materials}:
        nodes = []
        for n in sorted(mat.node_tree.nodes, key=lambda v: v.name):
            record = {'name': n.name, 'type': n.bl_idname}
            for field in ('operation', 'blend_type', 'uv_map', 'interpolation', 'extension'):
                if hasattr(n, field): record[field] = getattr(n, field)
            for direction in ('inputs', 'outputs'):
                values = []
                for s in getattr(n, direction):
                    if not hasattr(s, 'default_value'): continue
                    value = s.default_value
                    values.append((s.identifier, value if isinstance(value, (str, int, float, bool)) or value is None else list(value)))
                record[direction] = values
            if n.type == 'TEX_IMAGE' and n.image:
                path = Path(bpy.path.abspath(n.image.filepath)).resolve()
                record['image'] = [n.image.name, str(path), review.sha(path), n.image.colorspace_settings.name]
            if n.type == 'TEX_COORD' and n.object:
                record['coordinate_object'] = n.object.name
                record['authored_coordinate_world'] = matrix(authored_world(n.object))
            nodes.append(record)
        records[mat.name] = hashlib.sha256(json.dumps({'nodes': nodes,
            'links': sorted((l.from_node.name, l.from_socket.identifier, l.to_node.name, l.to_socket.identifier)
                            for l in mat.node_tree.links)}, sort_keys=True).encode()).hexdigest()
    return records


assert review.sha(review.FROZEN) == review.FROZEN_SHA
bpy.ops.wm.open_mainfile(filepath=str(review.FROZEN))
cached = objects_state()
bpy.context.view_layer.update()
bpy.context.evaluated_depsgraph_get().update()
before = objects_state()
materials_before = material_state()
objects = {n: list(bpy.data.collections[n].all_objects) for n in ('Editable_W3', 'Editable_E3')}
assert all(o is not None for values in objects.values() for o in values)
for name, values in objects.items():
    collection = bpy.data.collections[name]
    collection.hide_render = False
    collection.hide_viewport = False
    for obj in values:
        obj.hide_render = False
        obj.hide_viewport = False
        obj.hide_set(False)
bpy.context.view_layer.update()
bpy.context.evaluated_depsgraph_get().update()
after = objects_state()
materials_after = material_state()
differences = [{'object': name, 'field': key, 'before': before[name][key], 'after': after[name][key]}
               for name in before for key in before[name] if before[name][key] != after[name][key]]
invalid_resolved = [name for name in after if any(abs(after[name]['evaluated_world'][i][j]-after[name]['authored_world'][i][j])>1e-6
                    for i in range(4) for j in range(4))]
assert review.sha(review.FROZEN) == review.FROZEN_SHA
result = {'source_unchanged': True, 'objects': len(before), 'differences': differences,
          'pre_baseline_update_changes': [{'object': name, 'field': key}
              for name in cached for key in cached[name] if cached[name][key] != before[name][key]],
          'only_evaluated_world_changed': bool(differences) and all(d['field']=='evaluated_world' for d in differences),
          'resolved_world_disagrees_with_authored_chain': invalid_resolved,
          'material_graphs_and_authored_coordinate_transforms_unchanged': materials_before == materials_after,
          'changed_materials': [name for name in materials_before if materials_before[name] != materials_after[name]],
          'scope': 'read-only source opened, visibility toggled in memory, no save/render'}
out = HERE / 'north_visibility_diagnosis.json'
assert not out.exists()
out.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps({k:v for k,v in result.items() if k!='differences'}), flush=True)
