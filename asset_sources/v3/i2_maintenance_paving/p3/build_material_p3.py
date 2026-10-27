"""P3 material-only source comparison. Requires root's explicit CPU2 window.

Open frozen P2, preserve every geometry/UV/transform and its existing review rig.
No mesh construction, image editing, baking, GLB export or runtime writes.
"""
from pathlib import Path
import sys, importlib.util, hashlib, json, struct, time, os
import bpy

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
CFG = json.loads((HERE / 'contract.json').read_text(encoding='utf-8'))
spec = importlib.util.spec_from_file_location('frozen_paving_p2', HERE.parent / 'p2/build_paving.py')
P2 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(P2)
REPORT = {'status': 'STATIC_NOT_RUN', 'checks': [], 'variants': [], 'limits': [
    'Offline source material comparison, not a game screenshot or aesthetic acceptance.',
    'Geometry is inherited unchanged from P2; no new collision or gameplay validation.',
    'Image colours are an artistic base colour, not measured roughness or material response.',
    'The upper intact-paint image window excludes broad lower peeling; sparse pictured rust is nonmetallic.']}
P2.REPORT = REPORT


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def inputs():
    actual = {p: sha(ROOT / p) for p in CFG['frozen_inputs']}
    assert actual == CFG['frozen_inputs'], 'Frozen P2 or approved original bytes changed.'
    return actual


def record(name, ok, detail=None):
    REPORT['checks'].append({'name': name, 'passed': bool(ok), 'detail': detail})


def geometry_signature():
    """Exact float32 mesh/UV data plus original hierarchy and local transforms."""
    digest = hashlib.sha256()
    objects = sorted((o for o in bpy.data.objects if o.get('variant') or o.name.startswith('MaintenancePaving_')), key=lambda o: o.name)
    for obj in objects:
        digest.update(json.dumps([obj.name, obj.type, obj.parent.name if obj.parent else None,
            [v for row in obj.matrix_basis for v in row], [v for row in obj.matrix_world for v in row]], separators=(',', ':')).encode())
        if obj.type != 'MESH':
            continue
        assert len(obj.modifiers) == 0, 'Unexpected unevaluated P2 geometry modifier.'
        mesh = obj.data
        for vertex in mesh.vertices:
            digest.update(struct.pack('<3f', *vertex.co))
        for polygon in mesh.polygons:
            digest.update(struct.pack('<II?', polygon.loop_start, polygon.loop_total, polygon.use_smooth))
        for loop in mesh.loops:
            digest.update(struct.pack('<I', loop.vertex_index))
        for edge in mesh.edges:
            digest.update(struct.pack('<2I', *edge.vertices))
        for uv in mesh.uv_layers:
            digest.update(uv.name.encode())
            digest.update(bytes([uv.active_render, uv.active_clone]))
            for value in uv.data:
                digest.update(struct.pack('<2f', *value.uv))
        digest.update(struct.pack('<i', mesh.uv_layers.active_index))
        digest.update(json.dumps([m.name for m in mesh.materials]).encode())
    return {'sha256': digest.hexdigest(), 'objects': len(objects)}


def rig_state():
    scene = bpy.context.scene
    lights = []
    for obj in sorted((o for o in scene.objects if o.type == 'LIGHT'), key=lambda o: o.name):
        lights.append({'name': obj.name, 'matrix': [v for row in obj.matrix_world for v in row],
            'type': obj.data.type, 'energy': obj.data.energy, 'colour': list(obj.data.color),
            'size': obj.data.size, 'shape': obj.data.shape})
    backgrounds = [{s.name: list(s.default_value) if s.type == 'RGBA' else s.default_value
        for s in n.inputs} for n in scene.world.node_tree.nodes if n.type == 'BACKGROUND']
    return {'lights': lights, 'background': backgrounds,
        'camera_matrix': [v for row in scene.camera.matrix_world for v in row],
        'camera_type': scene.camera.data.type, 'ortho_scale': scene.camera.data.ortho_scale,
        'resolution': [scene.render.resolution_x, scene.render.resolution_y, scene.render.resolution_percentage],
        'colour': [scene.view_settings.view_transform, scene.view_settings.look,
            scene.view_settings.exposure, scene.view_settings.gamma],
        'samples': scene.cycles.samples, 'denoise': scene.cycles.use_denoising}


def math_node(material, operation, a, b=0):
    n = material.node_tree.nodes.new('ShaderNodeMath'); n.operation = operation
    for value, socket in ((a, n.inputs[0]), (b, n.inputs[1])):
        if hasattr(value, 'node'):
            material.node_tree.links.new(value, socket)
        else:
            socket.default_value = value
    return n.outputs[0]


def change_concrete(material):
    nodes, links = material.node_tree.nodes, material.node_tree.links
    image = next(n for n in nodes if n.type == 'TEX_IMAGE' and n.label == 'Native imagegen old concrete, 4m pitch, unedited candidate')
    consumers = [link.to_socket for link in list(image.outputs['Color'].links)]
    assert consumers
    scale = nodes.new('ShaderNodeMixRGB'); scale.name = 'P3_LinearConcreteScale'
    scale.label = 'Same source image, linear colour x0.45'; scale.blend_type = 'MULTIPLY'
    scale.inputs[0].default_value = 1
    scale.inputs[2].default_value = (CFG['concrete']['linear_multiplier'],) * 3 + (1,)
    links.new(image.outputs['Color'], scale.inputs[1])
    calm = nodes.new('ShaderNodeMixRGB'); calm.name = 'P3_QuietConcreteBlend'
    calm.label = '72% scaled source / 28% quiet middle grey'
    calm.inputs[0].default_value = CFG['concrete']['texture_weight']
    calm.inputs[1].default_value = CFG['concrete']['quiet_linear_rgba']
    links.new(scale.outputs[0], calm.inputs[2])
    for target in consumers:
        links.new(calm.outputs[0], target)
    bsdf = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')
    record(material.name + ' preserves neutral normal and nonmetal concrete', not bsdf.inputs['Normal'].is_linked and bsdf.inputs['Metallic'].default_value == 0)


def change_paint(material, image, row):
    nodes, links = material.node_tree.nodes, material.node_tree.links
    bsdf = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')
    mix = bsdf.inputs['Base Color'].links[0].from_node
    assert mix.type == 'MIX_RGB' and mix.blend_type == 'MIX'
    assert mix.inputs[0].is_linked, 'P2 actual lid-edge/grip wear mask missing.'
    wear = mix.inputs[0].links[0].from_socket
    coords = next(n for n in nodes if n.type == 'TEX_COORD')
    sep = nodes.new('ShaderNodeSeparateXYZ'); links.new(coords.outputs['Object'], sep.inputs[0])
    z = math_node(material, 'MULTIPLY', sep.outputs['Y'], -1)
    z = math_node(material, 'ADD', z, row['center_xz'][1])
    length = math_node(material, 'FRACT', math_node(material, 'DIVIDE', z, 4))
    u = math_node(material, 'ADD', .02, math_node(material, 'MULTIPLY', length, .96))
    width = math_node(material, 'DIVIDE', math_node(material, 'SUBTRACT', sep.outputs['X'], 2.02), .45)
    width = math_node(material, 'MINIMUM', 1, math_node(material, 'MAXIMUM', 0, width))
    v = math_node(material, 'ADD', .60, math_node(material, 'MULTIPLY', width, .32))
    uv = nodes.new('ShaderNodeCombineXYZ'); links.new(u, uv.inputs['X']); links.new(v, uv.inputs['Y'])
    tex = nodes.new('ShaderNodeTexImage'); tex.name = 'P3_IntactPaint_UpperWindow'
    tex.label = 'Original PNG, only top 8–40%; 4m longitudinal coverage'
    tex.image = image; tex.extension = 'EXTEND'; links.new(uv.outputs[0], tex.inputs['Vector'])
    # Preserve the exact physical cover/grip wear and its original exposed colour.
    links.new(tex.outputs['Color'], mix.inputs[1])
    metal = math_node(material, 'MULTIPLY', wear, CFG['painted_steel']['exposed_metallic'] / .7)
    metal.node.label = 'Paint/oxide 0; actual exposed edge/grip 0.65'
    bsdf.inputs['Metallic'].default_value = 0
    links.new(metal, bsdf.inputs['Metallic'])
    record(material.name + ' keeps original wear factor and separate paint/metal',
        mix.inputs[0].links[0].from_socket == wear and bsdf.inputs['Metallic'].is_linked)


def variants_from_source():
    variants = {}
    for row in P2.CFG['tiles']:
        label = row['id']
        variants[label] = {'row': row, 'root': bpy.data.objects['MaintenancePaving_' + label],
            'collection': bpy.data.collections['Editable_' + label],
            'parts': sorted((o for o in bpy.data.objects if o.type == 'MESH' and o.get('variant') == label), key=lambda o: o.name),
            'widths': {edge: .01 if mode == 'pair_half' else .02 for edge, mode in row['edges'].items()}}
    return variants


def write_report():
    (HERE / 'evidence/production_report.json').write_text(json.dumps(REPORT, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def main():
    start = time.monotonic(); original_hashes = inputs()
    blend = HERE / 'maintenance_paving_p3.blend'
    assert not blend.exists(), 'Preserve completed attempts.'
    (HERE / 'evidence').mkdir(exist_ok=True)
    bpy.ops.wm.open_mainfile(filepath=str(ROOT / CFG['source_blend']))
    scene = bpy.context.scene
    assert scene.render.engine == 'CYCLES' and scene.cycles.device == 'CPU' and scene.render.threads == 2
    original_geometry, original_rig = geometry_signature(), rig_state()
    image = bpy.data.images.load(CFG['painted_steel']['copy_path'], check_existing=False)
    image.colorspace_settings.name = 'sRGB'
    record('approved intact paint image dimensions', list(image.size) == CFG['painted_steel']['dimensions'], list(image.size))
    for row in P2.CFG['tiles']:
        change_concrete(bpy.data.materials['SOURCE_' + row['id'] + '_concrete'])
        change_paint(bpy.data.materials['SOURCE_' + row['id'] + '_teal'], image, row)
    bpy.context.view_layer.update()
    record('exact P2 geometry/UV/hierarchy/slot signature unchanged', geometry_signature() == original_geometry, original_geometry)
    record('P2 lighting camera exposure and sample count unchanged', rig_state() == original_rig, original_rig)
    REPORT['input_hashes_before'] = original_hashes
    REPORT['material_contract'] = {k: CFG[k] for k in ('concrete', 'painted_steel')}
    for im in bpy.data.images:
        if im.source == 'FILE' and im.filepath:
            im.filepath = str(Path(bpy.path.abspath(im.filepath)).resolve())
    bpy.ops.wm.save_as_mainfile(filepath=str(blend), relative_remap=False)
    bpy.ops.wm.open_mainfile(filepath=str(blend))
    scene = bpy.context.scene
    record('saved source reopens with identical geometry/UV', geometry_signature() == original_geometry)
    record('saved source retains P2 review rig', rig_state() == original_rig)
    variants = variants_from_source()
    for variant in variants.values():
        REPORT['variants'].append(P2.inspect(variant))
    P2.check_assembled_boundaries(variants)
    REPORT['status'] = 'MATERIAL_SOURCE_CHECKED_NOT_RENDERED'; write_report()
    if not all(c['passed'] for c in REPORT['checks']):
        raise RuntimeError('Source comparison gate failed; preserve report and blend, no render.')
    previews = []
    for label, variant in variants.items():
        variant['collection'].hide_render = label != 'W1'
    assert scene.render.resolution_x == 1280 and scene.render.resolution_y == 960 and scene.camera.data.ortho_scale == 8
    out = HERE / 'evidence/maintenance_single_p3.png'
    scene.render.filepath = str(out); bpy.ops.render.render(write_still=True)
    previews.append({'path': str(out), 'sha256': sha(out), 'scope': 'Offline source material comparison, same P2 rig'})
    for variant in variants.values():
        variant['collection'].hide_render = True
    for row in P2.CFG['tiles']:
        P2.review_copy(variants[row['id']], (row['center_xz'][0] - 19.5, row['center_xz'][1] + 6))
    scene.render.resolution_x = 1536; scene.render.resolution_y = 864; scene.camera.data.ortho_scale = 24.5
    out = HERE / 'evidence/maintenance_eight_tile_layout_p3.png'
    scene.render.filepath = str(out); bpy.ops.render.render(write_still=True)
    previews.append({'path': str(out), 'sha256': sha(out), 'scope': 'Offline eight-tile comparison, same P2 rig, no game objects'})
    REPORT.update(status='SOURCE_RENDERED_AWAITING_ROOT_REVIEW', previews=previews,
        blend_sha256=sha(blend), input_hashes_after=inputs(), elapsed_seconds=time.monotonic() - start)
    write_report()
    print(json.dumps({'stage': 'done', 'pid': os.getpid(), 'checks': len(REPORT['checks']),
        'failed': sum(not c['passed'] for c in REPORT['checks']), 'seconds': REPORT['elapsed_seconds']}), flush=True)


if __name__ == '__main__':
    main()
