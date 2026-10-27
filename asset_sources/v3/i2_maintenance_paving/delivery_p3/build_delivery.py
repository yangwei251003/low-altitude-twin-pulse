"""Shared 2K atlas / eight-variant source-only GLB. Run only in root's CPU2 window.

Reuses courtyard's native EMIT/NORMAL bake and strict binary glTF readback.
Frozen P3 stays editable and untouched. No Godot, runtime assets or pixel editing.
"""
from pathlib import Path
import bpy, sys, json, hashlib, importlib.util, collections, math, time, os
from mathutils import Matrix

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
CFG = json.loads((HERE / 'contract.json').read_text(encoding='utf-8'))
sys.path.insert(0, str(ROOT / 'asset_sources/v3/clinic_ground/delivery_p2'))
from read_glb import read, canon, bounds, node_identity, f32
spec = importlib.util.spec_from_file_location('frozen_paving', HERE.parent / 'p2/build_paving.py')
P2 = importlib.util.module_from_spec(spec); spec.loader.exec_module(P2)
UV = 'DeliveryUV'
ROLES = ('BaseColor', 'Roughness', 'Metallic', 'Normal')
CHECKS = []


def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def gd(p): return (float(p.x), float(p.z), float(-p.y))
def save_json(path, data): path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
def check(name, passed, detail=None): CHECKS.append({'name': name, 'passed': bool(passed), 'detail': detail})
def verify_inputs():
    assert all(sha(ROOT / p) == h for p, h in CFG['frozen_inputs'].items()), 'Frozen source/input changed.'


def signatures(mesh, uvname=UV):
    mesh.calc_loop_triangles(); triangles = collections.Counter(); corners = collections.Counter()
    uv = mesh.uv_layers.get(uvname)
    for tri in mesh.loop_triangles:
        ps = [gd(mesh.vertices[i].co) for i in tri.vertices]
        triangles[canon(ps)] += 1
        if uv:
            us = [(f32(uv.data[i].uv.x), f32(1 - uv.data[i].uv.y)) for i in tri.loops]
            corners[canon([ps[i] + us[i] for i in range(3)])] += 1
    return triangles, corners


def packed_signature(parts):
    digest = hashlib.sha256()
    for obj in sorted(parts, key=lambda o: o.name):
        tri, uv = signatures(obj.data)
        digest.update(repr((obj.name, sorted(tri.items()), sorted(uv.items()))).encode())
    return digest.hexdigest()


def select(objects):
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects: obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]


def merged_copy(objects, name):
    copies = []
    expected_tri, expected_uv = collections.Counter(), collections.Counter()
    for obj in sorted(objects, key=lambda o: o.name):
        tri, uv = signatures(obj.data); expected_tri.update(tri); expected_uv.update(uv)
        copy = bpy.data.objects.new('TEMP_' + obj.name, obj.data.copy())
        bpy.context.scene.collection.objects.link(copy); copies.append(copy)
    select(copies); bpy.ops.object.join()
    result = bpy.context.object; result.name = name; result.data.name = name
    assert signatures(result.data) == (expected_tri, expected_uv), 'Joining changed geometry or per-corner UV.'
    return result


def prepare():
    checkpoint = HERE / 'uv_checkpoint.blend'
    if checkpoint.exists():
        bpy.ops.wm.open_mainfile(filepath=str(checkpoint))
        parts = sorted((o for o in bpy.data.objects if o.get('delivery_part')), key=lambda o: o.name)
        prior = json.loads((HERE / 'uv_checkpoint.json').read_text(encoding='utf-8'))
        assert prior['source_sha256'] == CFG['source_sha256'] and prior['uv_sha256'] == packed_signature(parts)
        return parts, prior['uv_sha256']
    bpy.ops.wm.open_mainfile(filepath=str(ROOT / CFG['source']))
    originals = sorted((o for o in bpy.data.objects if o.type == 'MESH' and o.get('variant')), key=lambda o: o.name)
    parts = []
    for obj in originals:
        copy = bpy.data.objects.new('Delivery_' + obj.name, obj.data.copy())
        bpy.context.scene.collection.objects.link(copy)
        copy['delivery_part'] = True; copy['variant'] = obj['variant']; copy['runtime_group'] = obj['runtime_group']
        copy['source_piece'] = obj.name
        copy.data.uv_layers.new(name=UV)
        for layer in copy.data.uv_layers: layer.active_render = layer.name == UV
        copy.data.uv_layers.active_index = len(copy.data.uv_layers) - 1
        parts.append(copy)
    select(parts)
    bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=.005)
    bpy.ops.object.mode_set(mode='OBJECT')
    for original, copy in zip(originals, parts):
        assert signatures(original.data)[0] == signatures(copy.data)[0]
        assert all(math.isfinite(c) and 0 <= c <= 1 for u in copy.data.uv_layers[UV].data for c in u.uv)
    for label in [v['id'] for v in CFG['variants']]:
        bpy.data.collections['Editable_' + label].hide_render = True
    for image in bpy.data.images:
        if image.source == 'FILE' and image.filepath:
            image.filepath = str(Path(bpy.path.abspath(image.filepath)).resolve())
    uv_sha = packed_signature(parts)
    bpy.ops.wm.save_as_mainfile(filepath=str(checkpoint), relative_remap=False)
    save_json(HERE / 'uv_checkpoint.json', {'source_sha256': CFG['source_sha256'], 'uv_sha256': uv_sha,
        'pieces': len(parts), 'atlas_size': CFG['size'], 'margin_pixels': 4,
        'method': 'Native multi-object Smart UV Project; original SourceUV/ConcreteUV and root-coordinate author nodes preserved.'})
    return parts, uv_sha


def bake(parts, uv_sha):
    scene = bpy.context.scene; scene.cycles.device = 'CPU'; scene.cycles.samples = 1
    scene.render.threads_mode = 'FIXED'; scene.render.threads = 2
    scene.render.bake.use_selected_to_active = False
    temporary = merged_copy(parts, 'TEMP_NATIVE_BAKE_ONLY')
    materials = sorted({m for o in parts for m in o.data.materials}, key=lambda m: m.name)
    authors = []
    for material in materials:
        nodes = material.node_tree.nodes
        bs = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')
        out = next(n for n in nodes if n.type == 'OUTPUT_MATERIAL')
        emission = nodes.new('ShaderNodeEmission'); emission.inputs['Strength'].default_value = 1
        channels = {}
        for role, field in [('BaseColor', 'Base Color'), ('Roughness', 'Roughness'), ('Metallic', 'Metallic')]:
            socket = bs.inputs[field]
            channels[role] = socket.links[0].from_socket if socket.is_linked else (list(socket.default_value) if socket.type == 'RGBA' else socket.default_value)
        authors.append((material, bs, out, emission, channels))
    progress_path = HERE / 'bake_progress.json'
    progress = json.loads(progress_path.read_text(encoding='utf-8')) if progress_path.exists() else {'source_sha256': CFG['source_sha256'], 'uv_sha256': uv_sha, 'completed': []}
    assert progress['source_sha256'] == CFG['source_sha256'] and progress['uv_sha256'] == uv_sha
    images = {}
    for role in ROLES:
        path = HERE / 'textures' / ('MaintenancePaving_' + role + '.png')
        prior = next((r for r in progress['completed'] if r['role'] == role), None)
        space = 'sRGB' if role == 'BaseColor' else 'Non-Color'
        if prior:
            assert path.exists() and sha(path) == prior['sha256'], 'Completed bake bytes changed.'
        else:
            if path.exists():
                path.rename(path.with_name(path.stem + '_uncommitted_' + str(time.time_ns()) + '.png'))
            image = bpy.data.images.new('Bake_' + role, width=CFG['size'], height=CFG['size'], alpha=False)
            image.colorspace_settings.name = space
            for material, bs, out, emission, channels in authors:
                nodes, links = material.node_tree.nodes, material.node_tree.links
                for node in nodes: node.select = False
                target = nodes.new('ShaderNodeTexImage'); target.image = image; target.select = True; nodes.active = target
                if role == 'Normal':
                    links.new(bs.outputs['BSDF'], out.inputs['Surface'])
                else:
                    for link in list(emission.inputs['Color'].links): links.remove(link)
                    value = channels[role]
                    if hasattr(value, 'node'): links.new(value, emission.inputs['Color'])
                    else: emission.inputs['Color'].default_value = (value, value, value, 1) if isinstance(value, (float, int)) else value
                    links.new(emission.outputs[0], out.inputs['Surface'])
            select([temporary]); print(json.dumps({'stage': 'native_bake', 'role': role, 'pid': os.getpid()}), flush=True)
            bpy.ops.object.bake(type='NORMAL' if role == 'Normal' else 'EMIT', use_clear=True, margin=4, normal_space='TANGENT')
            image.filepath_raw = str(path); image.file_format = 'PNG'; image.save()
            progress['completed'].append({'role': role, 'path': str(path), 'sha256': sha(path), 'size': [CFG['size']] * 2, 'colorspace': space})
            save_json(progress_path, progress)
        images[role] = bpy.data.images.load(str(path), check_existing=False); images[role].colorspace_settings.name = space
        images[role].reload(); _pixel = images[role].pixels[:4]
        assert images[role].has_data and list(images[role].size) == [CFG['size']] * 2
    for material, bs, out, emission, channels in authors:
        material.node_tree.links.new(bs.outputs['BSDF'], out.inputs['Surface'])
    bpy.data.objects.remove(temporary, do_unlink=True)
    material = bpy.data.materials.new(CFG['material']); material.use_nodes = True
    nodes = material.node_tree.nodes; nodes.clear(); links = material.node_tree.links
    bs = nodes.new('ShaderNodeBsdfPrincipled'); out = nodes.new('ShaderNodeOutputMaterial'); links.new(bs.outputs['BSDF'], out.inputs['Surface'])
    uv = nodes.new('ShaderNodeUVMap'); uv.uv_map = UV
    for role, image in images.items():
        node = nodes.new('ShaderNodeTexImage'); node.image = image; node.label = role; links.new(uv.outputs['UV'], node.inputs['Vector'])
        if role == 'Normal':
            normal = nodes.new('ShaderNodeNormalMap'); normal.uv_map = UV
            links.new(node.outputs['Color'], normal.inputs['Color']); links.new(normal.outputs['Normal'], bs.inputs['Normal'])
        else:
            links.new(node.outputs['Color'], bs.inputs[{'BaseColor': 'Base Color', 'Roughness': 'Roughness', 'Metallic': 'Metallic'}[role]])
    for obj in parts:
        obj.data.materials.clear(); obj.data.materials.append(material)
        for polygon in obj.data.polygons: polygon.material_index = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(HERE / 'baked_editable.blend'), relative_remap=False)
    return material, progress['completed']


def export(parts, material, textures):
    path = HERE / 'maintenance_paving_variants.glb'
    assert not path.exists(), 'Never overwrite a completed GLB attempt.'
    def empty(name, parent=None):
        obj = bpy.data.objects.new(name, None); bpy.context.scene.collection.objects.link(obj); obj.parent = parent; obj.matrix_basis = Matrix.Identity(4); return obj
    root = empty(CFG['root']); selected = [root]; expected = {}; groups = {}
    for variant in CFG['variants']:
        old = bpy.data.objects.get(variant['root'])
        if old: old.name = 'AUTHOR_ONLY_' + variant['root']
        parent = empty(variant['root'], root); selected.append(parent)
        for group, target_tri in variant['groups'].items():
            objects = [o for o in parts if o['variant'] == variant['id'] and (o['runtime_group'] == 'InspectionBand') == (group == 'InspectionBand')]
            name = variant['id'] + '_' + group
            obj = merged_copy(objects, name)
            for layer in list(obj.data.uv_layers):
                if layer.name != UV: obj.data.uv_layers.remove(layer)
            obj.data.uv_layers.active_index = 0; obj.data.uv_layers[UV].active_render = True
            obj.data.materials.clear(); obj.data.materials.append(material)
            for face in obj.data.polygons: face.material_index = 0
            obj.parent = parent; obj.matrix_basis = Matrix.Identity(4)
            expected[name] = signatures(obj.data); assert sum(expected[name][0].values()) == target_tri
            groups[name] = {'parent': variant['root'], 'triangles': target_tri, 'source_pieces': [o['source_piece'] for o in objects]}
            selected.append(obj)
    select(selected)
    bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB', use_selection=True, export_apply=True,
        export_yup=True, export_texcoords=True, export_normals=True, export_materials='EXPORT', export_cameras=False,
        export_lights=False, export_animations=False, export_extras=False)
    j, actual, bb, images = read(path)
    check('twelve exact runtime mesh groups', set(actual) == set(expected), list(actual))
    check('exact complete bounds', bb == CFG['bounds'], bb)
    for name in expected:
        check(name + ' exact float32 triangles and UV0', actual[name]['triangles'] == expected[name][0] and actual[name]['corner_uv'] == expected[name][1])
        check(name + ' one shared material surface and finite unit normals', len(actual[name]['surfaces']) == 1 and all(s['material'] == CFG['material'] and s['normals_unit'] and set(s['attributes']) == {'POSITION', 'NORMAL', 'TEXCOORD_0'} for s in actual[name]['surfaces']))
    check('all root and child transforms identity', all(node_identity(n) for n in j['nodes']))
    expected_nodes = {CFG['root']} | {v['root'] for v in CFG['variants']} | set(groups)
    check('exact 21 nodes, no hidden coincident copies', {n['name'] for n in j['nodes']} == expected_nodes and len(j['nodes']) == 21)
    root_index = next(i for i, n in enumerate(j['nodes']) if n['name'] == CFG['root'])
    check('single root with eight direct variants', j['scenes'][j.get('scene', 0)]['nodes'] == [root_index] and {j['nodes'][i]['name'] for i in j['nodes'][root_index].get('children', [])} == {v['root'] for v in CFG['variants']})
    for variant in CFG['variants']:
        node = next(n for n in j['nodes'] if n['name'] == variant['root'])
        check(variant['id'] + ' exact children and triangle count', {j['nodes'][i]['name'] for i in node.get('children', [])} == {variant['id'] + '_' + g for g in variant['groups']} and sum(sum(actual[variant['id'] + '_' + g]['triangles'].values()) for g in variant['groups']) == variant['triangles'])
    check('one shared opaque standard PBR material', len(j['materials']) == 1 and j['materials'][0]['name'] == CFG['material'] and j['materials'][0].get('alphaMode', 'OPAQUE') == 'OPAQUE')
    mat = j['materials'][0]; pbr = mat['pbrMetallicRoughness']
    roles = {'BaseColor': pbr.get('baseColorTexture'), 'MR': pbr.get('metallicRoughnessTexture'), 'Normal': mat.get('normalTexture')}
    check('three texture roles use UV0', all(t is not None and t.get('texCoord', 0) == 0 for t in roles.values()))
    check('exactly three shared embedded 2K PNGs', len(images) == 3 and len(j['textures']) == 3 and all(i['size'] == [2048, 2048] for i in images), images)
    byrole = {t['role']: t for t in textures}
    for role in ('BaseColor', 'Normal'):
        embedded = images[j['textures'][roles[role]['index']]['source']]
        check(role + ' native bake embedded bytes unchanged', embedded['sha256'] == byrole[role]['sha256'])
    check('no emission/unlit/cameras/lights/animations', 'KHR_materials_unlit' not in mat.get('extensions', {}) and mat.get('emissiveFactor', [0, 0, 0]) == [0, 0, 0] and not j.get('cameras') and not j.get('animations') and not j.get('extensions', {}).get('KHR_lights_punctual'))
    verify_inputs()
    report = {'status': 'BINARY_CHECKED_AWAITING_READBACK_IMAGES' if all(c['passed'] for c in CHECKS) else 'FAILED_RETAINED',
        'source_sha256': CFG['source_sha256'], 'glb_path': str(path), 'glb_sha256': sha(path), 'glb_bytes': path.stat().st_size,
        'checks': CHECKS, 'groups': groups, 'textures': textures, 'images': images, 'bounds': bb,
        'triangles': sum(v['triangles'] for v in CFG['variants']), 'collision_contract': 'No colliders exported. Root retains existing Y0 ground collision; these are sealed inspection covers, not playable drains.'}
    save_json(HERE / 'delivery_report.json', report)
    assert all(c['passed'] for c in CHECKS), 'Actual GLB validation failed; retained evidence.'
    return path, report


def previews(path, report):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(path))
    scene = bpy.context.scene; scene.render.engine = 'CYCLES'; scene.cycles.device = 'CPU'
    scene.render.threads_mode = 'FIXED'; scene.render.threads = 2
    P2.H.studio(); scene.cycles.samples = 16
    roots = {v['id']: bpy.data.objects[v['root']] for v in CFG['variants']}
    for label, root in roots.items():
        for obj in root.children_recursive: obj.hide_render = label != 'W1'
    scene.render.resolution_x = 1280; scene.render.resolution_y = 960; scene.camera.data.ortho_scale = 8
    outputs = []
    out = HERE / 'evidence/maintenance_single_glb_p3.png'; scene.render.filepath = str(out); bpy.ops.render.render(write_still=True)
    outputs.append({'path': str(out), 'sha256': sha(out)})
    for row in P2.CFG['tiles']:
        root = roots[row['id']]
        root.location = P2.bg((row['center_xz'][0] - 19.5, 0, row['center_xz'][1] + 6))
        for obj in root.children_recursive: obj.hide_render = False
    scene.render.resolution_x = 1536; scene.render.resolution_y = 864; scene.camera.data.ortho_scale = 24.5
    out = HERE / 'evidence/maintenance_eight_tile_glb_p3.png'; scene.render.filepath = str(out); bpy.ops.render.render(write_still=True)
    outputs.append({'path': str(out), 'sha256': sha(out)})
    verify_inputs(); assert sha(path) == report['glb_sha256']
    report.update(status='SOURCE_DELIVERY_AWAITING_ROOT_GAME_REVIEW', readback_previews=outputs,
        scope='Same-byte GLB imported into Blender, offline original review rig; not Godot art or performance acceptance.')
    save_json(HERE / 'delivery_report.json', report)


def main():
    start = time.monotonic(); verify_inputs()
    (HERE / 'textures').mkdir(exist_ok=True); (HERE / 'evidence').mkdir(exist_ok=True)
    path = HERE / 'maintenance_paving_variants.glb'
    if path.exists():
        report = json.loads((HERE / 'delivery_report.json').read_text(encoding='utf-8'))
        assert report['status'] == 'BINARY_CHECKED_AWAITING_READBACK_IMAGES' and report['glb_sha256'] == sha(path)
    else:
        parts, uv_sha = prepare(); material, textures = bake(parts, uv_sha); path, report = export(parts, material, textures)
    previews(path, report)
    print(json.dumps({'stage': 'done', 'pid': os.getpid(), 'seconds': time.monotonic() - start, 'glb_sha256': sha(path)}), flush=True)


if __name__ == '__main__': main()
