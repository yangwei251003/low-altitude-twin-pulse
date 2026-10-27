"""Two authorized phases over the immutable, measured P2 UV checkpoint.

Reuses the existing native maintenance bake/export/readback implementation.
No prepare, repacking, source geometry edits, runtime writes or Godot.
"""
from pathlib import Path
import collections
import hashlib
import importlib.util
import json
import math
import os
import sys
import time

import bpy

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


BASE = load('extension_delivery_p1_reused', HERE.parent/'delivery_p1/build_delivery.py')
CLEAN = load('extension_delivery_copy_proof', HERE/'delivery_cleanup.py')
CFG = json.loads((HERE/'delivery_contract.json').read_text(encoding='utf-8'))
LOCK = json.loads((HERE/'delivery_phase_inputs.json').read_text(encoding='utf-8'))
NATIVE = BASE.NATIVE
UVS = ('SourceUV', 'ConcreteUV', 'PaintUV', 'DeliveryUV')
MERGE_REPORTS = []
ORIGINAL_MERGE = NATIVE.merged_copy


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(name, data):
    (HERE/name).write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')


def verify():
    BASE.verify()
    for path, expected in LOCK['files'].items():
        assert sha(ROOT/path) == expected, 'Frozen P2 phase input changed: '+path


def checkpoint():
    bpy.ops.wm.open_mainfile(filepath=str(HERE/'uv_checkpoint.blend'))
    bpy.context.view_layer.update()
    info = json.loads((HERE/'uv_checkpoint.json').read_text(encoding='utf-8'))
    assert info['status'] == 'PREPARE_PASSED_AWAITING_ROOT_REVIEW'
    assert sha(HERE/'uv_checkpoint.blend') == info['checkpoint_sha256']
    assert info['delivery_triangles'] == CFG['triangles'] == 16724
    assert all(c['passed'] for c in info['checks'])
    for key, group in CFG['groups'].items():
        objects = BASE.group_parts(key)
        assert NATIVE.packed_signature(objects) == info['groups'][key]['uv_sha256']
        assert sum(len(o.data.loop_triangles) for o in objects) == group['triangles']
        # P1 export reads a density field. This in-memory view uses P2's actual
        # category measurements; the immutable P2 report is never rewritten.
        info['groups'][key]['density'] = {
            'size': group['size'], 'categories': info['groups'][key]['categories'],
            'actual_uv_area': info['groups'][key]['uv_area'],
            'pixel_coverage_fraction': info['groups'][key]['pixel_coverage_fraction'],
            'min_actual_gap_pixels': info['groups'][key]['min_actual_gap_pixels']}
    bpy.context.scene.render.engine = 'CYCLES'
    bpy.context.scene.cycles.device = 'CPU'
    bpy.context.scene.render.threads_mode = 'FIXED'
    bpy.context.scene.render.threads = 2
    return info


def normal_rows(mesh):
    """Real corner directions paired by exact vertex/DeliveryUV triangle."""
    mesh.calc_loop_triangles()
    uv = mesh.uv_layers['DeliveryUV']
    result = collections.defaultdict(list)
    for tri in mesh.loop_triangles:
        corners = [tuple(float(x) for x in mesh.vertices[v].co)+tuple(float(x) for x in uv.data[l].uv)
                   for v, l in zip(tri.vertices, tri.loops)]
        order = min(range(3), key=lambda i: tuple(corners[i:]+corners[:i]))
        key = tuple(corners[order:]+corners[:order])
        ns = [tuple(float(x) for x in mesh.corner_normals[l].vector) for l in tri.loops]
        result[key].append(tuple(ns[order:]+ns[:order]))
    return result


def guarded_merge(objects, name):
    expected = {uv: (collections.Counter(), collections.Counter()) for uv in UVS}
    normals = collections.defaultdict(list)
    for obj in objects:
        assert all(obj.data.uv_layers.get(uv) is not None for uv in UVS)
        for uv in UVS:
            tris, corners = NATIVE.signatures(obj.data, uv)
            expected[uv][0].update(tris)
            expected[uv][1].update(corners)
        for key, rows in normal_rows(obj.data).items():
            normals[key].extend(rows)
    merged = ORIGINAL_MERGE(objects, name)
    for uv in UVS:
        assert NATIVE.signatures(merged.data, uv) == expected[uv], 'Join changed explicit '+uv
    observed = normal_rows(merged.data)
    assert observed.keys() == normals.keys(), 'Join changed normal-bearing triangle keys'
    max_angle = 0.0
    for key, wanted in normals.items():
        actual = list(observed[key])
        assert len(actual) == len(wanted)
        for row in wanted:
            scores = [max(CLEAN.normal_difference(a, b)[0] for a, b in zip(candidate, row))
                      for candidate in actual]
            closest = min(range(len(scores)), key=scores.__getitem__)
            max_angle = max(max_angle, scores[closest])
            assert scores[closest] <= CLEAN.CORNER_NORMAL_ANGLE_LIMIT_DEGREES, 'Join changed corner direction'
            actual.pop(closest)
    MERGE_REPORTS.append({'name': name, 'source_parts': len(objects),
                          'triangles': sum(expected['DeliveryUV'][0].values()),
                          'all_four_corner_uv_layers_exact': True,
                          'max_corner_normal_angle_degrees': max_angle})
    save('merge_validation.json', MERGE_REPORTS)
    return merged


BASE.HERE = HERE
BASE.CFG = CFG
BASE.checkpoint = checkpoint
NATIVE.merged_copy = guarded_merge


def completed_group(key):
    folder = HERE/key
    data = json.loads((folder/'completed.json').read_text(encoding='utf-8'))
    info = json.loads((HERE/'uv_checkpoint.json').read_text(encoding='utf-8'))
    assert data['source_sha256'] == CFG['source_sha256']
    assert data['uv_sha256'] == info['groups'][key]['uv_sha256']
    assert sha(folder/'baked_editable.blend') == data['baked_blend_sha256']
    assert {t['role'] for t in data['textures']} == set(NATIVE.ROLES)
    for texture in data['textures']:
        assert sha(texture['path']) == texture['sha256']
        assert texture['size'] == [CFG['groups'][key]['size']]*2
    return data


def bake_all():
    assert not (HERE/'east_maintenance_extension.glb').exists()
    for key in CFG['groups']:
        if (HERE/key/'completed.json').exists():
            completed_group(key)
            print(json.dumps({'stage': 'reuse_verified_completed_group', 'group': key}), flush=True)
        else:
            print(json.dumps({'stage': 'start_group_bake', 'group': key, 'pid': os.getpid()}), flush=True)
            BASE.bake(key)
            completed_group(key)
        verify()
    save('bake_all_completed.json', {'status': 'TWO_GROUP_NATIVE_BAKES_PASSED_NOT_EXPORTED',
         'groups': {key: completed_group(key) for key in CFG['groups']},
         'checkpoint_sha256': sha(HERE/'uv_checkpoint.blend'), 'triangles': CFG['triangles']})


def deliver():
    for key in CFG['groups']:
        completed_group(key)
    BASE.export()
    BASE.preview()
    report = json.loads((HERE/'delivery_report.json').read_text(encoding='utf-8'))
    path = Path(report['path'])
    _, binary, _, _ = NATIVE.read(path)
    readback = []
    for obj in sorted((o for o in bpy.data.objects if o.type == 'MESH'), key=lambda o: o.name):
        assert obj.name in CFG['groups'], 'Unexpected readback mesh'
        assert len(obj.data.uv_layers) == 1
        observed = NATIVE.signatures(obj.data, obj.data.uv_layers[0].name)
        assert observed == (binary[obj.name]['triangles'], binary[obj.name]['corner_uv']), 'Readback changed actual UV0'
        assert len(obj.data.materials) == 1 and obj.data.materials[0].name == CFG['groups'][obj.name]['material']
        readback.append({'mesh': obj.name, 'triangles': len(obj.data.loop_triangles),
                         'actual_triangles_and_uv0_match_binary': True,
                         'material': obj.data.materials[0].name})
    assert len(readback) == 2 and sha(path) == report['sha256']
    report['actual_reimport_uv_and_material'] = readback
    report['checkpoint_sha256'] = sha(HERE/'uv_checkpoint.blend')
    report['frozen_phase_inputs'] = LOCK['files']
    report['scope'] = 'Same-byte GLB and two offline Blender previews only; no Godot, runtime installation or final art acceptance.'
    save('delivery_report.json', report)


def main():
    args = sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    assert len(args) == 1 and args[0] in ('bake', 'deliver')
    verify()
    start = time.monotonic()
    print(json.dumps({'stage': args[0], 'pid': os.getpid(), 'cpu_threads': 2}), flush=True)
    try:
        if args[0] == 'bake': bake_all()
        else: deliver()
    except Exception as error:
        save('phase_failure_'+str(time.time_ns())+'.json', {'phase': args[0], 'error': repr(error),
             'seconds': time.monotonic()-start, 'merge_checks': MERGE_REPORTS,
             'note': 'Retain channel checkpoints. No automatic retry or repack.'})
        report_path = HERE/'delivery_report.json'
        if args[0] == 'deliver' and report_path.exists():
            report = json.loads(report_path.read_text(encoding='utf-8'))
            report['status'] = 'FAILED_PHASE_RETAINED'
            report['phase_error'] = repr(error)
            save('delivery_report.json', report)
        raise
    finally:
        verify()
    print(json.dumps({'stage': args[0], 'finished': True, 'pid': os.getpid(),
                      'elapsed_seconds': time.monotonic()-start}), flush=True)


if __name__ == '__main__':
    main()
