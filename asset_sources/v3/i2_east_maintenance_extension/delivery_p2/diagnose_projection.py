"""Read-only source diagnosis, no atlas packing or saved Blender output.

Recreates the failed prepare's copied meshes, records all failing projections
before and after explicit mesh/depsgraph refresh. Does not choose a new axis.
"""
from pathlib import Path
import datetime
import hashlib
import json
import os
import struct
import sys
import time
import bpy

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import prepare_uv as P


def bake_uv_fingerprint(obj):
    digest = hashlib.sha256()
    for uv in obj.data.uv_layers[P.UV].data:
        digest.update(struct.pack('<2f', *uv.uv))
    return digest.hexdigest()


def scan(objects, output):
    output.mkdir()
    P.HERE = output
    observations = []
    for obj in objects:
        for name in ['projection_failure_detail.json']:
            assert not (output/name).exists()
        try:
            charts = P.charts_for(obj)
            observations.append({'object': obj.name, 'ok': True, 'charts': len(charts)})
        except AssertionError as error:
            path = output/'projection_failure_detail.json'
            if not path.exists(): raise
            detail = json.loads(path.read_text(encoding='utf-8'))
            target = output/(obj.name+'.json')
            path.rename(target)
            observations.append({'object': obj.name, 'ok': False, 'error': str(error),
                                 'detail': target.name, 'axis': detail['projection_axis'],
                                 'polygons': detail['polygon_ids'], 'projected_bounds': detail['projected_bounds']})
    return observations


def main():
    start = time.monotonic()
    P.P1.verify()
    before = {name: P.sha(P.ROOT/name) for name in P.CFG['frozen_inputs']}
    output = HERE/('projection_diagnosis_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    output.mkdir()
    print(json.dumps({'stage': 'read_only_projection_diagnosis', 'pid': os.getpid(), 'output': str(output)}), flush=True)
    bpy.ops.wm.open_mainfile(filepath=str(P.ROOT/P.CFG['source']))
    bpy.context.view_layer.update()
    assert P.SOURCE.editable_signature() == P.CFG['source_geometry_uv_signature']
    originals = sorted((o for o in bpy.data.objects if o.type == 'MESH' and o.get('export_piece')), key=lambda o: o.name)
    copies, materials = [], {}
    for obj in originals:
        copy = bpy.data.objects.new('Delivery_'+obj.name, obj.data.copy())
        bpy.context.scene.collection.objects.link(copy)
        copy['delivery_part'] = True; copy['source_piece'] = obj.name; copy['delivery_group'] = P.P1.group_of(obj.name)
        for i, mat in enumerate(copy.data.materials):
            if mat.name not in materials:
                P.verify_author_sampling(mat)
                materials[mat.name] = mat.copy(); materials[mat.name].name = 'DELIVERY_P2_AUTHOR_'+mat.name
            copy.data.materials[i] = materials[mat.name]
        copy.data.uv_layers.new(name=P.UV)
        copy.data.uv_layers.active_index = len(copy.data.uv_layers)-1
        for layer in copy.data.uv_layers: layer.active_render = layer.name == P.UV
        copies.append(copy)
    bake_uv_before = {obj.name: bake_uv_fingerprint(obj) for obj in copies}
    # No calc_loop_triangles or depsgraph update on these new copies before
    # this first scan: reproduce the actual failed prepare sequence exactly.
    first = scan(copies, output/'before_explicit_refresh')
    for obj in copies:
        obj.data.update()
        obj.data.calc_loop_triangles()
    bpy.context.view_layer.update()
    bpy.context.evaluated_depsgraph_get().update()
    second = scan(copies, output/'after_explicit_refresh')
    for obj in copies:
        source = next(o for o in originals if o.name == obj['source_piece'])
        assert P.P1.source_uv_proof(source.data) == P.P1.source_uv_proof(obj.data)
        assert bake_uv_fingerprint(obj) == bake_uv_before[obj.name], 'Diagnostic changed initialized bake UV'
    assert before == {name: P.sha(P.ROOT/name) for name in before}
    result = {'scope': 'Read-only projection diagnosis; no atlas assignment, Blender save, bake, export or corrected axis',
              'before': first, 'after_refresh': second, 'inputs_unchanged': len(before),
              'source_triangles_and_three_uvs_unchanged': True, 'elapsed_seconds': time.monotonic()-start}
    (output/'report.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({'stage': 'diagnosis_finished', 'before_failures': sum(not r['ok'] for r in first),
                      'after_failures': sum(not r['ok'] for r in second), 'report': str(output/'report.json')}), flush=True)


if __name__ == '__main__':
    main()
