"""P9: one natural wood fragment, rigidly turned with uniform scale only.

Source research, not a shore asset or a contact-validated game mesh. The vendor
mesh is retained intact in a hidden source collection. Only primitive 0 is read.
Run only after the root agent releases the performance/render window.
"""
import bpy
import bmesh
import hashlib
import json
import struct
from pathlib import Path
from mathutils import Matrix, Vector

OUT = Path(__file__).resolve().parent
PROJECT = OUT.parents[3]
VENDOR = PROJECT / 'asset_sources/third_party/island_tree_01'
GLTF = VENDOR / 'island_tree_01_1k.gltf'
BIN = VENDOR / 'island_tree_01.bin'
EXPECTED_HASHES = {
    GLTF.name: 'a8dd768c33037151f7a86293744c5cf7fae8eeb7a04b6e35719179b9943170c6',
    BIN.name: '1faa817b46e24ed6fc90d3ec72188a0dc5ac75e82c89b3dd3c5fdaecf7cc005c',
}
assert EXPECTED_HASHES == {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in (GLTF, BIN)}
gltf = json.loads(GLTF.read_text(encoding='utf-8'))
assert gltf['nodes'] == [{'mesh': 0, 'name': 'island_tree_01_LOD0'}]
search = json.loads((OUT / 'rigid_pose_search_trimmed_fine_branches.json').read_text(encoding='utf-8'))
trial = search['results'][0]
pose = trial['best_poses'][0]
assert trial['source_clip_gltf_y'] == [.1, 2.2]
assert trial['source_clip_gltf_x_max'] == .4
assert pose['fits_full_9x12x4_93_envelope'] and pose['scale_uniform'] == 3.0
assert pose['downward_degrees'] == 25 and pose['roll_degrees'] == 100


def decode(accessor_id):
    a = gltf['accessors'][accessor_id]
    v = gltf['bufferViews'][a['bufferView']]
    width = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3}[a['type']]
    fmt = {5126: 'f', 5125: 'I', 5123: 'H'}[a['componentType']]
    parser = struct.Struct('<' + fmt * width)
    stride = v.get('byteStride', parser.size)
    with BIN.open('rb') as f:
        f.seek(v.get('byteOffset', 0) + a.get('byteOffset', 0))
        blob = f.read(stride * (a['count'] - 1) + parser.size)
    return [parser.unpack_from(blob, i * stride) for i in range(a['count'])]


def bp(p):
    return Vector((p[0], -p[2], p[1]))


def gp(p):
    return [float(p.x), float(p.z), float(-p.y)]


def bounds(points):
    return {'min': [min(p[i] for p in points) for i in range(3)],
            'max': [max(p[i] for p in points) for i in range(3)]}


primitive = gltf['meshes'][0]['primitives'][0]
assert primitive['attributes']['POSITION'] == 0 and primitive['indices'] == 3
positions = decode(0)
indices = [p[0] for p in decode(3)]
faces = [indices[i:i + 3] for i in range(0, len(indices), 3)]
assert len(faces) == 34787
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene


def collection(name):
    value = bpy.data.collections.new(name)
    scene.collection.children.link(value)
    return value


originals = collection('SOURCE_ORIGINAL_PRIMITIVE0_HIDDEN')
originals.hide_render = True
originals.hide_viewport = True
study = collection('P9_RIGID_ROOT_DIRECTION_ONLY')
studio = collection('STUDIO_NOT_ASSET')


def material(name, colour):
    value = bpy.data.materials.new(name)
    value.diffuse_color = (*colour, 1)
    value.use_nodes = True
    shader = value.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = (*colour, 1)
    shader.inputs['Roughness'].default_value = .87
    shader.inputs['Specular IOR Level'].default_value = .16
    return value


wood = material('P9_Plain_Wood_No_Texture', (.285, .225, .165))
cut_material = material('P9_New_Cut_Surface_No_Texture', (.32, .282, .225))
source_mesh = bpy.data.meshes.new('Vendor_Primitive0_Original_Positions_Indices')
source_mesh.from_pydata([bp(p) for p in positions], [], faces)
source_mesh.update()
source_obj = bpy.data.objects.new('Vendor_Wood_Original_Proportions_Do_Not_Edit', source_mesh)
originals.objects.link(source_obj)
source_obj['vendor_geometry_unchanged'] = True
mesh = source_mesh.copy()
mesh.name = 'P9_SourceY_010_220_Xmax040_Cut_Only'
mesh.materials.append(wood)
mesh.materials.append(cut_material)
for face in mesh.polygons:
    face.use_smooth = True
bm = bmesh.new()
bm.from_mesh(mesh)
bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-6)
cut_records = []
for label, plane_co, plane_no in [
        ('base_source_Y_010', (0, 0, .1), (0, 0, -1)),
        ('tips_source_Y_220', (0, 0, 2.2), (0, 0, 1)),
        ('two_fine_branches_source_Xmax040', (.4, 0, 0), (1, 0, 0))]:
    result = bmesh.ops.bisect_plane(
        bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces), dist=1e-6,
        plane_co=Vector(plane_co), plane_no=Vector(plane_no),
        clear_outer=True, clear_inner=False, use_snap_center=False)
    cut_edges = [edge for edge in result['geom_cut']
                 if isinstance(edge, bmesh.types.BMEdge) and edge.is_boundary]
    caps = bmesh.ops.holes_fill(bm, edges=cut_edges, sides=0)['faces'] if cut_edges else []
    for face in caps:
        face.material_index = 1
        face.smooth = False
    cut_records.append({'cut': label, 'cut_edges': len(cut_edges), 'cap_polygons': len(caps)})
bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
component_sizes = []
pending = set(bm.verts)
while pending:
    stack = [pending.pop()]
    count = 0
    while stack:
        vertex = stack.pop()
        count += 1
        for edge in vertex.link_edges:
            other = edge.other_vert(vertex)
            if other in pending:
                pending.remove(other)
                stack.append(other)
    component_sizes.append(count)
boundary_edges = sum(edge.is_boundary for edge in bm.edges)
bm.to_mesh(mesh)
bm.free()
mesh.update()
mesh.calc_loop_triangles()
root = bpy.data.objects.new('P9_Natural_Fork_Rigid_3x_No_Stretch', mesh)
study.objects.link(root)

# glTF/Godot right-handed Y-up -> Blender right-handed Z-up.
B = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))
rotation = Matrix(pose['rotation_gltf_to_godot_rows'])
scale = pose['scale_uniform']
pivot = Vector(pose['source_pivot_gltf'])
translation = Vector(pose['translated_base_pivot_godot'])
affine = (B @ rotation @ B.transposed()).to_4x4()
affine.translation = B @ (translation - rotation @ pivot * scale)
root.matrix_world = affine
root.scale = (scale, scale, scale)
root['nonuniform_scale_or_warp'] = False
root['uniform_scale'] = scale
root['source_clip_y'] = [.1, 2.2]
root['source_clip_x_max'] = .4
root['meaning'] = 'Natural tree fork repurposing experiment; not a scanned exposed root or supported shore.'
bpy.context.view_layer.update()
actual_points = [gp(root.matrix_world @ v.co) for v in mesh.vertices]
actual_bounds = bounds(actual_points)
max_bound_error = max(abs(actual_bounds[side][axis] - pose['bounds_godot'][side][axis])
                      for side in ('min', 'max') for axis in range(3))
assert max_bound_error < .0001, (actual_bounds, pose['bounds_godot'], max_bound_error)
assert max(root.scale) - min(root.scale) < 1e-6

# Inspection anchors are not rendered, and do not assert a successful join.
for name, position in [('BridgeJoin_Engineering_Target_Not_Contact', (4.5, 4.5, 0)),
                       ('HighBasePivot_Study', pose['translated_base_pivot_godot']),
                       ('GroundOrigin_Study', (0, 0, 0))]:
    anchor = bpy.data.objects.new(name, None)
    study.objects.link(anchor)
    anchor.empty_display_type = 'PLAIN_AXES'
    anchor.empty_display_size = .25
    anchor.location = bp(position)


def aim(obj, target):
    obj.rotation_euler = (bp(target) - obj.location).to_track_quat('-Z', 'Y').to_euler()


def light(name, at, energy, size, colour):
    data = bpy.data.lights.new(name, 'AREA')
    data.energy, data.size, data.color = energy, size, colour
    obj = bpy.data.objects.new(name, data)
    studio.objects.link(obj)
    obj.location = bp(at)
    aim(obj, (0, 2.1, 0))


light('Key', (-7, 14, 12), 2300, 9, (1, .95, .88))
light('Fill', (9, 10, -8), 1500, 10, (.88, .94, 1))
light('Rim', (-10, 10, -8), 1300, 8, (1, .95, .88))
bpy.ops.mesh.primitive_plane_add(size=100, location=(0, 0, -.015))
floor = bpy.context.object
for linked in list(floor.users_collection):
    linked.objects.unlink(floor)
studio.objects.link(floor)
floor.name = 'Studio_Floor_Not_A_Supporting_Shore'
floor.data.materials.append(material('P9_Neutral_Studio', (.27, .29, .30)))
camera_data = bpy.data.cameras.new('P9_Reference_Direction_Camera')
camera = bpy.data.objects.new('P9_Reference_Direction_Camera', camera_data)
studio.objects.link(camera)
scene.camera = camera
camera_data.type = 'ORTHO'
camera_data.ortho_scale = 13.4
camera.location = bp((15, 16, 20))
aim(camera, (0, 2.15, .3))
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 12
scene.cycles.use_denoising = True
scene.render.threads_mode, scene.render.threads = 'FIXED', 2
scene.render.resolution_x, scene.render.resolution_y = 1400, 1050
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.world.use_nodes = True
scene.world.node_tree.nodes.get('Background').inputs['Color'].default_value = (.30, .33, .36, 1)
scene.world.node_tree.nodes.get('Background').inputs['Strength'].default_value = .45
scene.view_settings.view_transform = 'AgX'
scene.view_settings.look = 'AgX - Medium High Contrast'
scene.render.filepath = str(OUT / 'rigid-root-main-form.png')

report = {
    'scope': 'P9 one rigid natural-root direction experiment, offline Blender only',
    'source_asset': 'https://polyhaven.com/a/island_tree_01',
    'license': 'CC0', 'license_url': 'https://polyhaven.com/license',
    'artists': ['Rico Cilliers', 'Rob Tuytel'],
    'vendor_sha256': EXPECTED_HASHES,
    'source_mesh': 0, 'source_primitive': 0, 'source_triangles': len(faces),
    'leaves_and_twig_primitives_read': False,
    'source_coordinate_system': 'glTF Y-up, original identity node',
    'clip_gltf': {'y_min': .1, 'y_max': 2.2, 'x_max': .4},
    'fine_branch_trim_evidence': 'pruning_sections.json: X=.4 intersects only two fine side branches',
    'cut_records': cut_records,
    'connected_component_vertex_counts': sorted(component_sizes, reverse=True),
    'remaining_boundary_edges': boundary_edges,
    'actual_triangles_including_cut_caps': len(mesh.loop_triangles),
    'actual_bounds_godot': actual_bounds,
    'numerical_pose_bounds_max_error_m': max_bound_error,
    'pose': pose,
    'transform_policy': 'one rigid rotation and uniform 3x scale; no warp, remesh, decimation, or stretch',
    'camera_godot': {'position': [15, 16, 20], 'target': [0, 2.15, .3], 'orthographic_size': 13.4},
    'render': {'renderer': 'Cycles CPU', 'threads': 2, 'samples': 12, 'resolution': [1400, 1050]},
    'limits': [
        'Original geometry is a tree base and branch fork, not an exposed-root scan.',
        'Three coarse tips are at different levels; four thinner cropped tips still remain.',
        'The high base cut plane is about 0.964m from BridgeJoin; no bridge contact is established.',
        'No supporting rocks, whole shoulder, game collision, texture work, GLB export or runtime test.',
        'An envelope fit and an offline render do not establish artistic acceptance or structural support.',
    ],
}
scene['P9_Study_Report'] = json.dumps(report, ensure_ascii=False)
blend_path = OUT / 'rigid_root_main_form.blend'
bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))
report['blend_sha256'] = hashlib.sha256(blend_path.read_bytes()).hexdigest()
(OUT / 'rigid_root_main_form.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
bpy.ops.render.render(write_still=True)
assert EXPECTED_HASHES == {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in (GLTF, BIN)}
report['image_sha256'] = hashlib.sha256((OUT / 'rigid-root-main-form.png').read_bytes()).hexdigest()
report['vendor_unchanged_after_render'] = True
(OUT / 'rigid_root_main_form.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print('P9_RIGID_ROOT_DONE ' + json.dumps({
    'triangles': len(mesh.loop_triangles), 'bounds': actual_bounds,
    'components': component_sizes, 'bounds_max_error_m': max_bound_error,
    'source_unchanged': True, 'no_runtime_export': True,
}))
