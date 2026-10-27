"""P13 source-only broad-form study; no voxel, PBR, export or runtime writes.

The source density is inherited temporarily, not a production budget claim.
The continuous map fixes X/Z and scales Y above a buried base by a strictly
positive amount. Existing polygon tessellation still requires later auditing.
"""
import bpy
import bmesh
import hashlib
import json
import math
import numpy as np
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree

OUT = Path(__file__).resolve().parent
PROJECT = OUT.parents[3]
SOURCE = OUT.parent / 'p12/upper_cut_before_cleanup.blend'
BRIDGE = PROJECT / 'assets/v3/root_arch/f1_root_arch.glb'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
frozen = {str(p.relative_to(PROJECT)): sha(p) for p in (SOURCE, BRIDGE)}
assert frozen[str(SOURCE.relative_to(PROJECT))] == '9e7e5c9c32f7bcb3480af86b1f32b45ea7ce329d2e7325492d6e5c577c89a011'
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
camera_matrix = scene.camera.matrix_world.copy()
camera_size = scene.camera.data.ortho_scale
collection = bpy.data.collections['P12_SHORE_ROOT_EDITABLE']
collection.name = 'P13_SHORE_ROOT_FORM_STUDY'
high = bpy.data.objects['P10_HighShoulder_ContinuousThickCliff']
root = bpy.data.objects['P10_NaturalMainRoot_TrueCrossSectionCuts']
parts = [o for o in collection.objects if o.type == 'MESH' and not o.hide_render]
assert len(parts) == 5


def gp(p):
    return Vector((p.x, p.z, -p.y))


def bp(p):
    return Vector((p[0], -p[2], p[1]))


def world_array(ob):
    local = np.empty(len(ob.data.vertices) * 3, dtype=np.float64)
    ob.data.vertices.foreach_get('co', local)
    local = local.reshape((-1, 3))
    matrix = np.asarray(ob.matrix_world, dtype=np.float64)
    world = local @ matrix[:3, :3].T + matrix[:3, 3]
    return local, world[:, [0, 2, 1]] * [1, 1, -1]


def put_world_array(ob, godot):
    blender = godot[:, [0, 2, 1]] * [1, -1, 1]
    matrix = np.asarray(ob.matrix_world.inverted(), dtype=np.float64)
    local = blender @ matrix[:3, :3].T + matrix[:3, 3]
    ob.data.vertices.foreach_set('co', np.asarray(local, dtype=np.float32).reshape(-1))
    ob.data.update()


def smooth(t):
    t = np.clip(t, 0., 1.)
    return t * t * (3. - 2. * t)


def shoulder_height(x, z):
    # Three broad nonparallel stone shoulders, not periodic teeth/noise.
    # Different lengths and cross slopes leave two unequal low notches.
    shoulders = []
    for cx, cz, degrees, height, half_length, cross_slope, end_slope in (
        (1.05, -2.62, 22., 3.74, 1.42, .88, .72),
        (1.55, -.18, -28., 3.92, .83, 1.32, .95),
        (.92, 2.03, 34., 3.24, 1.18, .97, .62),
    ):
        angle = math.radians(degrees)
        dx, dz = x - cx, z - cz
        along = dx * math.cos(angle) + dz * math.sin(angle)
        across = -dx * math.sin(angle) + dz * math.cos(angle)
        height_field = height - .10 * along - cross_slope * np.abs(across)
        height_field -= end_slope * np.maximum(np.abs(along) - half_length, 0.)
        shoulders.append(height_field)
    value = np.maximum.reduce(shoulders + [1.72 + .10 * x - .045 * z])
    value = np.clip(value, 1.65, 4.08)
    # The final metre is exactly the original, not a sampled approximation.
    join = smooth((x - 2.65) / .85)
    return value * (1. - join) + 4.5 * join


def sculpt_columns(points):
    result = points.copy()
    x, y, z = points.T
    factor = (shoulder_height(x, z) - .55) / (4.5 - .55)
    factor = np.where(x >= 3.5, 1., factor)
    # Positive vertical derivative; buried bottom, X and Z are unchanged.
    result[:, 1] = np.where(y > .55, .55 + (y - .55) * factor, y)
    return result, factor


old_local, old_high = world_array(high)
old_root_local, old_root = world_array(root)
high.data = high.data.copy()
root.data = root.data.copy()
new_high, factors = sculpt_columns(old_high)
put_world_array(high, new_high)
high.name = 'P13_ThreeThickObliqueRockShoulders'

# The high-end root is buried using the same field only near its old source
# cut. The rest of the fork and the three lower supports retain their points.
mapped_root, _ = sculpt_columns(old_root)
cap_weight = 1. - smooth((old_root_local[:, 2] - .1) / .42)
new_root = old_root + (mapped_root - old_root) * cap_weight[:, None]

# Recess only the already pruned two short necks towards their parent bark.
# No global plane cut, scaling, new branches or change to the main fork span.
stump_records = []
matrix = np.asarray(root.matrix_world, dtype=np.float64)
local_down_godot = (matrix[:3, :3] @ np.asarray([0., 0., -1.]))[[0, 2, 1]] * [1, 1, -1]
for label, height, x, source_z, radius, recess in (
    ('upper_pruned_neck', 1.40, -.381, -.195, .245, .095),
    ('front_pruned_neck', 1.65, .071, -.552, .185, .075),
):
    dx = old_root_local[:, 0] - x
    dy = old_root_local[:, 1] + source_z
    radial = np.sqrt(dx * dx + dy * dy)
    weight = (1. - smooth(radial / radius)) * smooth((old_root_local[:, 2] - (height - .27)) / .22)
    # Branches beyond the retained neck are already removed in the input.
    weight *= (old_root_local[:, 2] <= height + 1e-5)
    new_root += weight[:, None] * local_down_godot * recess
    stump_records.append({'label': label, 'affected_vertices': int(np.sum(weight > 0)),
                          'max_world_recess_m': float(np.max(weight) * np.linalg.norm(local_down_godot) * recess)})
put_world_array(root, new_root)
root.name = 'P13_NaturalMainFork_LocalNeckBurial'


def tree(ob):
    ob.data.calc_loop_triangles()
    return BVHTree.FromPolygons([ob.matrix_world @ v.co for v in ob.data.vertices],
        [tuple(t.vertices) for t in ob.data.loop_triangles], all_triangles=True)


def topo(ob):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    result = {'boundary_edges': sum(e.is_boundary for e in bm.edges),
              'nonmanifold_edges': sum(not e.is_manifold for e in bm.edges),
              'signed_volume': bm.calc_volume(signed=True)}
    bm.free()
    return result


ht = tree(high)
top_probes = []
for x in (3.55, 4., 4.49):
    for z in (-2.75, -1.375, 0., 1.375, 2.75):
        hit = ht.ray_cast(bp((x, 6, z)), bp((0, -1, 0)), 8)[0]
        point = list(gp(hit)) if hit is not None else None
        top_probes.append({'xz': [x, z], 'point': point,
                           'pass': point is not None and abs(point[1] - 4.5) < .001})
side_probes = []
for y in (.25, 1., 2., 3., 4.25):
    for z in (-2.75, -1.375, 0., 1.375, 2.75):
        hit = ht.ray_cast(bp((7, y, z)), bp((-1, 0, 0)), 5)[0]
        point = list(gp(hit)) if hit is not None else None
        side_probes.append({'yz': [y, z], 'point': point,
                           'pass': point is not None and abs(point[0] - 4.5) < .001})
topology = {o.name: topo(o) for o in (high, root)}
triangles = {}
for ob in parts:
    ob.data.calc_loop_triangles()
    triangles[ob.name] = len(ob.data.loop_triangles)
unchanged_main = np.max(np.linalg.norm(new_root[old_root_local[:, 2] > 1.67] - old_root[old_root_local[:, 2] > 1.67], axis=1))
report = {
    'status': 'source silhouette study; not low-poly, PBR, export or runtime acceptance',
    'method': 'existing topology, fixed X/Z and positive column-wise vertical scaling above Y0.55; three oblique nonperiodic shoulders',
    'no_voxel_no_boolean_no_added_triangles': True,
    'input_sha256': frozen,
    'last_metre_vertex_displacement_max_m': float(np.max(np.abs(new_high[old_high[:, 0] >= 3.5] - old_high[old_high[:, 0] >= 3.5]))),
    'column_derivative_min': float(np.min(factors)),
    'upper_rock_max_displacement_m': float(np.max(np.linalg.norm(new_high - old_high, axis=1))),
    'root_max_local_displacement_m': float(np.max(np.linalg.norm(new_root - old_root, axis=1))),
    'distal_main_fork_source_y_gt_1_67_max_displacement_m': float(unchanged_main),
    'short_necks': stump_records,
    'interface_top_15': top_probes,
    'interface_side_25': side_probes,
    'topology_scope_only_edges_and_volume': topology,
    'triangles_inherited_not_new_reconstruction': triangles,
    'limits': [
        'Dense source is inherited solely for a quick silhouette judgment, not rebuilt with voxels.',
        'Existing source micro-coplanar reports are unresolved; no full triangle self-intersection acceptance is asserted.',
        'A positive continuous deformation does not by itself prove the finite polygon tessellation is intersection-free.',
        'Root high cap vertices may move locally by explicit parent authorization; the old 183 coordinates are not frozen.',
        'One offline assembly view, not an actual engine screenshot. Materials remain basic source colors.',
    ],
}
assert report['last_metre_vertex_displacement_max_m'] == 0.
assert report['column_derivative_min'] > 0.25
assert all(p['pass'] for p in top_probes + side_probes)
assert all(t['boundary_edges'] == 0 and t['nonmanifold_edges'] == 0 and t['signed_volume'] > 0 for t in topology.values())
assert unchanged_main == 0.

for name, p in [('GroundOrigin', (0, 0, 0)), ('BridgeJoin', (4.5, 4.5, 0)), ('WestBlend', (-4.3, .34, 0))]:
    anchor = bpy.data.objects.new(name, None)
    collection.objects.link(anchor)
    anchor.location = bp(p)
    anchor.empty_display_size = .15

scene.render.threads_mode = 'FIXED'
scene.render.threads = 2
scene.cycles.device = 'CPU'
scene.cycles.samples = 8
scene.render.resolution_x = 1000
scene.render.resolution_y = 750
scene.render.resolution_percentage = 100
source = OUT / 'shore_root_t03a_p13_basic.blend'
bpy.ops.wm.save_as_mainfile(filepath=str(source))
report['editable_source_sha256'] = sha(source)

before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=str(BRIDGE))
imported = [o for o in bpy.data.objects if o not in before]
bridge_root = next(o for o in imported if o.name == 'F1RootArch')
bridge_root.location += bp((24.5, 0, 0))
colors = {'WalkableRoot': (.285, .225, .165), 'StoneRemnants': (.28, .285, .27),
          'Moss': (.17, .23, .14), 'Foliage': (.21, .27, .16)}
for ob in imported:
    if ob.type != 'MESH':
        continue
    mat = bpy.data.materials.new('P13_ReadonlyBridgeBasic_' + ob.name)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = (*colors[ob.name], 1)
    shader.inputs['Roughness'].default_value = .87
    for i in range(len(ob.data.materials)):
        ob.data.materials[i] = mat
bpy.context.view_layer.update()
assert scene.camera.matrix_world == camera_matrix and scene.camera.data.ortho_scale == camera_size
report['unchanged_camera'] = True
report['bridge_local_translation_godot'] = [24.5, 0, 0]
image = OUT / 'p13-basic-readonly-bridge-assembly.png'
scene.render.filepath = str(image)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / 'p13_basic_assembly.blend'))
bpy.ops.render.render(write_still=True)
report['image_sha256'] = sha(image)
assert all(sha(PROJECT / p) == value for p, value in frozen.items())
report['frozen_inputs_unchanged'] = True
(OUT / 'p13_form_report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print('P13_FORM_ONLY', json.dumps({'image': str(image), 'source': str(source),
    'triangles': triangles, 'last_metre_max_m': report['last_metre_vertex_displacement_max_m'],
    'column_derivative_min': report['column_derivative_min']}), flush=True)
