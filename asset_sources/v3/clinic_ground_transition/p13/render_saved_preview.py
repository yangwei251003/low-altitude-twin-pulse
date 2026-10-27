"""Render the already-saved P13 source; normalize file identity, not pixels.

The preceding run completed geometry, actual-boundary sampling, collision and
all ten image pixel reads. It failed only by comparing non-normalized paths.
This entry does not rebuild, reshape, re-material, bake or export anything.
"""
from pathlib import Path
import importlib.util
import json
import math
import os
import sys
import time
sys.dont_write_bytecode = True
import bpy
from mathutils import Vector, Matrix

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('p13_frozen_build', HERE / 'build_preview.py')
B = importlib.util.module_from_spec(spec); spec.loader.exec_module(B)
FIRST = HERE / 'source_run_20261019_213428_064334'
SECOND = HERE / 'source_run_20261019_213859_639023'
SOURCE = SECOND / 'editable_source.blend'


def identity(rows):
    return {str(Path(r['absolute_path']).resolve()): (r['sha256'], r['size'], r['colorspace']) for r in rows}


def main():
    start = time.time()
    for folder in (FIRST, SECOND):
        for row in json.loads((folder / 'failure_manifest.json').read_text(encoding='utf-8'))['files']:
            assert B.sha(folder / row['path']) == row['sha256'], row
    source_sha = B.sha(SOURCE)
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    report = json.loads((FIRST / 'geometry_report.json').read_text(encoding='utf-8'))
    parts = {o.name: o for o in B.authored()}
    assert len(parts) == 14
    for row in report['objects']:
        ob = parts[row['name']]
        assert B.R.signature(ob) == row['native_geometry_sha256'], ob.name
        assert B.R.uv_signature(ob.data) == row['uv_sha256'], ob.name
    contacts = json.loads((FIRST / 'contact_report.json').read_text(encoding='utf-8'))
    contact_by_name = {r['object']: r for r in contacts}
    for name, ob in parts.items():
        expected = Matrix(contact_by_name[name]['actual_matrix_world_blender']) if name in contact_by_name else Matrix.Identity(4)
        assert max(abs(ob.matrix_world[i][j] - expected[i][j]) for i in range(4) for j in range(4)) < 1e-7, name
    before_images = json.loads((SECOND / 'image_preflight.json').read_text(encoding='utf-8'))
    images = B.check_images('actual_reopen_images')
    assert identity(before_images) == identity(images), 'Resolved path + SHA + size + color-space must all match.'
    B.write('normalized_image_identity.json', {'actual_source': str(SOURCE),
        'source_sha256': source_sha, 'normalized_same_files': True,
        'file_count': len(images), 'actual_identity': identity(images),
        'correction': 'Normalize Path(bpy.path.abspath()).resolve(); retain raw stored paths and all actual pixel/size/SHA checks.'})
    material_rows = []
    for name, ob in parts.items():
        if not name.startswith('Rock07_'):
            continue
        mat = ob.data.materials[0]
        bs = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
        material_rows.append({'name': name, 'material': mat.name,
            'roughness': bs.inputs['Roughness'].default_value, 'IOR': bs.inputs['IOR'].default_value,
            'metallic': bs.inputs['Metallic'].default_value, 'normal_connected': bool(bs.inputs['Normal'].links),
            'source_geometry_identical': True, 'source_uv_identical': True})
    scene = bpy.context.scene
    assert scene.render.engine == 'CYCLES' and scene.cycles.device == 'CPU' and scene.render.threads == 2
    full_camera = {'location': list(scene.camera.location), 'rotation': list(scene.camera.rotation_euler), 'ortho_scale': scene.camera.data.ortho_scale}
    scene.render.filepath = str(B.OUT / '01_full_source.png'); bpy.ops.render.render(write_still=True)
    direction = scene.camera.rotation_euler.to_matrix() @ Vector((0, 0, -1))
    target = Vector(B.H.bp(-1.14, -.005, 1.04))
    scene.camera.location = target - direction * 8; scene.camera.data.ortho_scale = 2.35
    close_camera = {'location': list(scene.camera.location), 'rotation': list(scene.camera.rotation_euler), 'ortho_scale': scene.camera.data.ortho_scale, 'target_godot': B.H.gp(target)}
    scene.render.filepath = str(B.OUT / '02_contact_close.png'); bpy.ops.render.render(write_still=True)
    assert B.sha(SOURCE) == source_sha
    for row in json.loads((HERE / 'input_contract.json').read_text(encoding='utf-8'))['files']:
        assert B.sha(B.ROOT / row['path']) == row['sha256'], row
    sections = json.loads((SECOND / 'actual_channel_sections.json').read_text(encoding='utf-8'))
    collision = json.loads((SECOND / 'collision_surface.json').read_text(encoding='utf-8'))
    report.update(status='SOURCE_RENDERED_PENDING_ACTUAL_IMAGE_REVIEW', pid=os.getpid(), seconds=time.time() - start,
        editable_source_path=str(SOURCE), editable_source_sha256=source_sha,
        saved_source_not_rewritten=True, all14_geometry_uv_transform_match_checkpoint=True,
        scan_materials=material_rows, source_images=images,
        actual_sections_path=str(SECOND / 'actual_channel_sections.json'), actual_section_count=len(sections['sections']),
        excluded_outside_samples=len(sections['excluded_samples']), actual_collision_triangles=collision['triangle_count'],
        collision_path=str(SECOND / 'collision_surface.json'), full_camera=full_camera, close_camera=close_camera,
        frozen_inputs_unchanged=True, engine_tested=False, baked=False, glb_exported=False,
        production_placement_approved=False,
        renders=[{'path': p.name, 'bytes': p.stat().st_size, 'sha256': B.sha(p)} for p in [B.OUT / '01_full_source.png', B.OUT / '02_contact_close.png']])
    B.write('source_report.json', report)
    print(json.dumps({'pid': os.getpid(), 'status': report['status'], 'seconds': report['seconds'], 'triangles': report['actual_visual_triangles']}), flush=True)


if __name__ == '__main__':
    main()
