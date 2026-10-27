"""Frozen source + visible original north tiles. Run only in root's CPU2 window.

Changes review visibility/camera only; no new geometry, UV, material, bake or GLB.
"""
from pathlib import Path
import sys, json, hashlib, struct, time, os
sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import build_source as source
import bpy
from mathutils import Vector

FROZEN = HERE / 'uv_readback_corrected/editable_source.blend'
FROZEN_SHA = '367311f852b1572e8089a92bcb5ea9e88b3e8626ee231e17c0d2b9b93228739b'
OUTPUT = HERE / 'north_joint_visible_review'
CHECKS = []


def check(name, passed, detail=None):
    CHECKS.append({'name': name, 'passed': bool(passed), 'detail': detail})


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def authored_world(obj):
    # Hidden original collections retain stale evaluated matrix_world even
    # after depsgraph.update. The unchanged author hierarchy is the baseline.
    return authored_world(obj.parent) @ obj.matrix_parent_inverse @ obj.matrix_basis if obj.parent else obj.matrix_basis.copy()


def mesh_signature(objects, evaluated=False):
    digest = hashlib.sha256()
    for obj in sorted(objects, key=lambda o: o.name):
        mesh = obj.data
        digest.update(obj.name.encode())
        digest.update((obj.parent.name if obj.parent else '').encode())
        for row in obj.matrix_basis:
            digest.update(struct.pack('<4f', *row))
        for row in obj.matrix_parent_inverse:
            digest.update(struct.pack('<4f', *row))
        for row in (obj.matrix_world if evaluated else authored_world(obj)):
            digest.update(struct.pack('<4f', *row))
        for v in mesh.vertices:
            digest.update(struct.pack('<3f', *v.co))
        for face in mesh.polygons:
            digest.update(struct.pack('<II', len(face.vertices), face.material_index))
            digest.update(struct.pack('<' + 'I' * len(face.vertices), *face.vertices))
        for uv in mesh.uv_layers:
            digest.update(uv.name.encode())
            for corner in uv.data:
                digest.update(struct.pack('<2f', *corner.uv))
        for mat in mesh.materials:
            digest.update(mat.name.encode())
    return digest.hexdigest()


def material_signature(objects, evaluated=False):
    def value(raw):
        if isinstance(raw, (bool, str, int, float)) or raw is None:
            return raw
        return list(raw)
    result = []
    for mat in sorted({m for obj in objects for m in obj.data.materials}, key=lambda m: m.name):
        item = {'name': mat.name, 'nodes': [], 'links': []}
        for node in sorted(mat.node_tree.nodes, key=lambda n: n.name):
            row = {'name': node.name, 'type': node.bl_idname}
            for field in ('operation', 'blend_type', 'uv_map', 'interpolation', 'extension'):
                if hasattr(node, field):
                    row[field] = getattr(node, field)
            for direction in ('inputs', 'outputs'):
                row[direction] = [(s.identifier, value(s.default_value)) for s in getattr(node, direction)
                                  if hasattr(s, 'default_value')]
            if node.type == 'TEX_IMAGE' and node.image:
                image = node.image
                path = Path(bpy.path.abspath(image.filepath)).resolve()
                row['image'] = {'name': image.name, 'path': str(path), 'sha256': sha(path),
                                'colorspace': image.colorspace_settings.name}
            if node.type == 'TEX_COORD':
                row['coordinate_object'] = node.object.name if node.object else None
                if node.object:
                    row['coordinate_transform'] = [list(r) for r in (node.object.matrix_world if evaluated else authored_world(node.object))]
            item['nodes'].append(row)
        item['links'] = sorted((l.from_node.name, l.from_socket.identifier,
                                l.to_node.name, l.to_socket.identifier) for l in mat.node_tree.links)
        result.append(item)
    return hashlib.sha256(json.dumps(result, sort_keys=True).encode()).hexdigest()


def render_paths(obj):
    paths = []
    def visit(collection, names, hidden):
        names = names + [collection.name]
        hidden = hidden or collection.hide_render
        if obj.name in collection.objects:
            paths.append({'path': names, 'collection_hidden': hidden,
                          'object_hidden': obj.hide_render,
                          'renderable': not hidden and not obj.hide_render})
        for child in collection.children:
            visit(child, names, hidden)
    visit(bpy.context.scene.collection, [], False)
    return paths


def visibility(collection):
    objects = sorted((o for o in collection.all_objects if o.type == 'MESH'), key=lambda o: o.name)
    return {'collection': collection.name, 'hide_render': collection.hide_render,
            'hide_viewport': collection.hide_viewport, 'mesh_count': len(objects),
            'objects': [{'name': o.name, 'viewport_visible': o.visible_get(), 'paths': render_paths(o)} for o in objects]}


def visible(record):
    return record['mesh_count'] > 0 and all(o['viewport_visible'] and any(p['renderable'] for p in o['paths'])
                                           for o in record['objects'])


def north_objects():
    return [o for name in ('Editable_W3', 'Editable_E3') for o in bpy.data.collections[name].all_objects if o.type == 'MESH']


def all_objects():
    return north_objects() + [o for o in bpy.data.objects if o.type == 'MESH' and o.get('export_piece', False)]


def main():
    start = time.monotonic()
    assert sha(FROZEN) == FROZEN_SHA
    source.verify_inputs()
    OUTPUT.mkdir(exist_ok=True)
    assert not (OUTPUT / 'north_joint_review.blend').exists()
    bpy.ops.wm.open_mainfile(filepath=str(FROZEN))
    print(json.dumps({'stage': 'north_joint_start', 'pid': os.getpid(), 'bake': False, 'export': False}), flush=True)
    bpy.context.view_layer.update()
    bpy.context.evaluated_depsgraph_get().update()
    before_geometry = mesh_signature(all_objects())
    before_material = material_signature(all_objects())
    before_new = source.editable_signature()
    report = {'source': str(FROZEN), 'source_sha256': FROZEN_SHA, 'checks': CHECKS,
              'scope': 'offline frozen new source and original W3/E3 north tiles; not Godot or runtime collision',
              'visibility_before': [visibility(bpy.data.collections[n]) for n in ('Editable_W3', 'Editable_E3')]}
    # all_objects is an RNA cache. Visibility setters can invalidate its live
    # iterator; hold stable Object references before any display mutation.
    display_objects = {name: list(bpy.data.collections[name].all_objects)
                       for name in ('Editable_W3', 'Editable_E3')}
    report['display_object_counts'] = {name: len(objects) for name, objects in display_objects.items()}
    for name, objects in display_objects.items():
        assert objects and all(obj is not None for obj in objects), 'Invalid original context object: ' + name
    (OUTPUT / 'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    for name in ('Editable_W3', 'Editable_E3'):
        collection = bpy.data.collections[name]
        collection.hide_render = False
        collection.hide_viewport = False
        for obj in display_objects[name]:
            obj.hide_render = False
            obj.hide_viewport = False
            obj.hide_set(False)
    bpy.context.view_layer.update()
    bpy.context.evaluated_depsgraph_get().update()
    for name, objects in display_objects.items():
        after = list(bpy.data.collections[name].all_objects)
        check(name + ' display keeps the same valid object identities',
              len(after) == len(objects) and all(obj is not None for obj in after)
              and {obj.as_pointer() for obj in after} == {obj.as_pointer() for obj in objects},
              {'before_count': len(objects), 'after_count': len(after)})
    report['visibility_enabled'] = [visibility(bpy.data.collections[n]) for n in ('Editable_W3', 'Editable_E3')]
    check('both original north tile collections actually renderable', all(visible(v) for v in report['visibility_enabled']))
    resolved_error = max(abs(o.matrix_world[i][j]-authored_world(o)[i][j])
                         for o in all_objects() for i in range(4) for j in range(4))
    check('visible evaluated world transforms match unchanged authored hierarchy', resolved_error < 1e-6, resolved_error)
    for name, xmin, xmax in [('Editable_W3', 14.5, 19.5), ('Editable_E3', 19.5, 24.5)]:
        vertices = [o.matrix_world @ v.co for o in bpy.data.collections[name].all_objects if o.type == 'MESH' for v in o.data.vertices]
        lo = [min(v[i] for v in vertices) for i in range(3)]
        hi = [max(v[i] for v in vertices) for i in range(3)]
        actual = [lo[0]+20.7, hi[0]+20.7, -hi[1]+8.8, -lo[1]+8.8, lo[2], hi[2]]
        expected = [xmin, xmax, -2, 2, -.18, 0]
        check(name + ' original world bounds', all(abs(a-b)<1e-5 for a,b in zip(actual,expected)), actual)
    tree = source.bvh_for(all_objects())
    for x in (18.4, 22):
        for z, expected in [(1.97, 0), (1.99, -.012), (2.005, 0), (2.03, 0)]:
            hit = tree.ray_cast(Vector(source.plan.bg((x, 1, z))), Vector((0, 0, -1)), 2)[0]
            y = float(hit.z) if hit is not None else None
            check('actual assembled joint ray X%s Z%s' % (x, z), y is not None and abs(y-expected)<1e-5,
                  {'expected_y': expected, 'actual_y': y})
    check('new geometry UV and transforms unchanged by review visibility', before_new == source.editable_signature())
    check('all original and new mesh geometry UV slots unchanged', before_geometry == mesh_signature(all_objects()))
    check('all original and new material nodes textures unchanged', before_material == material_signature(all_objects()))
    report['geometry_signature'] = before_geometry
    report['material_signature'] = before_material
    evaluated_geometry = mesh_signature(all_objects(), evaluated=True)
    evaluated_material = material_signature(all_objects(), evaluated=True)
    report['evaluated_geometry_signature'] = evaluated_geometry
    report['evaluated_material_signature'] = evaluated_material
    report_path = OUTPUT / 'report.json'
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    if not all(c['passed'] for c in CHECKS):
        raise RuntimeError('North assembly gate failed; report kept, no render.')
    scene = bpy.context.scene
    assert scene.render.engine == 'CYCLES' and scene.cycles.device == 'CPU'
    assert scene.render.threads == 2 and scene.render.resolution_x == 1536 and scene.render.resolution_y == 1024
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT / 'north_joint_review.blend'), relative_remap=False)
    bpy.ops.wm.open_mainfile(filepath=str(OUTPUT / 'north_joint_review.blend'))
    bpy.context.view_layer.update()
    bpy.context.evaluated_depsgraph_get().update()
    report['visibility_reopened'] = [visibility(bpy.data.collections[n]) for n in ('Editable_W3', 'Editable_E3')]
    check('reopened review keeps both original tiles actually renderable', all(visible(v) for v in report['visibility_reopened']))
    check('reopened review keeps all geometry UV materials identical',
          before_geometry == mesh_signature(all_objects()) and before_material == material_signature(all_objects()))
    check('reopened visible review keeps identical evaluated world geometry and material coordinates',
          evaluated_geometry == mesh_signature(all_objects(), evaluated=True)
          and evaluated_material == material_signature(all_objects(), evaluated=True))
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    if not all(c['passed'] for c in CHECKS):
        raise RuntimeError('North review save readback failed; no render.')
    camera = bpy.data.objects['OfflineOblique']
    support = bpy.data.collections['REVIEW_ONLY_ExistingFiveSupports']
    report['images'] = []
    for filename, target, offset, scale, show_support in [
        ('01-visible-north-overview', (20.7,0,7), (13,18,16), 22, True),
        ('02-actual-north-joint', (20,0,2), (8,10,9), 9.5, False),
    ]:
        support.hide_render = not show_support
        source.aim(camera, target, offset, scale)
        output = OUTPUT / (filename + '.png')
        bpy.context.scene.render.filepath = str(output)
        bpy.ops.render.render(write_still=True)
        report['images'].append({'path': str(output), 'sha256': sha(output), 'target': target,
                                 'offset': offset, 'orthographic_scale': scale, 'support_proxies': show_support})
    source.verify_inputs()
    check('frozen source bytes unchanged after both renders', sha(FROZEN) == FROZEN_SHA)
    report.update(status='NORTH_ASSEMBLY_SOURCE_PREVIEW_AWAITING_ROOT_REVIEW',
                  elapsed_seconds=time.monotonic()-start,
                  review_blend_sha256=sha(OUTPUT / 'north_joint_review.blend'))
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({'pid': os.getpid(), 'checks': len(CHECKS), 'failed': sum(not c['passed'] for c in CHECKS),
                      'elapsed_seconds': report['elapsed_seconds']}), flush=True)
    assert all(c['passed'] for c in CHECKS)


if __name__ == '__main__':
    main()
