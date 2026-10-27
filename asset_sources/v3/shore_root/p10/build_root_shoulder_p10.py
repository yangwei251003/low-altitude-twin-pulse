"""P10 bounded natural-fork pruning and real stone-contact candidate.

Offline source only. All writes stay in p10. No textures, bake, GLB, Godot or
shared documents. Render only after the geometric gates below have passed.
"""
import bpy
import bmesh
import hashlib
import json
import math
import struct
import sys
from pathlib import Path
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

OUT = Path(__file__).resolve().parent
PROJECT = OUT.parents[3]
P9 = OUT.parent / 'p9'
VENDOR = PROJECT / 'asset_sources/v3/root_buttress/p8/vendor'
MOSS = PROJECT / 'asset_sources/v3/root_buttress/p6/vendor/rock_moss_set_01_1k.gltf'
SOURCE = P9 / 'rigid_root_main_form.blend'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
frozen_paths = [SOURCE, P9 / 'rigid-root-main-form.png',
                PROJECT / 'assets/v3/root_arch/f1_root_arch.glb',
                VENDOR / 'rock_face_01/rock_face_01_1k.gltf',
                VENDOR / 'rock_face_01/rock_face_01.bin', MOSS,
                MOSS.parent / 'rock_moss_set_01.bin']
frozen = {str(p.relative_to(PROJECT)): sha(p) for p in frozen_paths}
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
root = bpy.data.objects['P9_Natural_Fork_Rigid_3x_No_Stretch']
root.name = 'P10_NaturalMainRoot_TrueCrossSectionCuts'
root.data = root.data.copy()
root.data.name = 'P10_PrunedSource_NoWarp'
study = root.users_collection[0]
study.name = 'P10_RootAndStone_ContactCandidate'
studio = bpy.data.collections['STUDIO_NOT_ASSET']
archive = bpy.data.collections['SOURCE_ORIGINAL_PRIMITIVE0_HIDDEN']


def bp(p):
    return Vector((p[0], -p[2], p[1]))


def gp(p):
    return Vector((p.x, p.z, -p.y))


def material(name, colour):
    value = bpy.data.materials.new(name)
    value.diffuse_color = (*colour, 1)
    value.use_nodes = True
    p = value.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = (*colour, 1)
    p.inputs['Roughness'].default_value = .88
    p.inputs['Specular IOR Level'].default_value = .15
    return value


stone = material('P10_ColdMidGrey_Stone_BasicOnly', (.25, .275, .285))
warm_stone = material('P10_LowerStone_BasicOnly', (.28, .285, .27))


def mesh_obj(name, points, faces, mat=stone, col=study):
    mesh = bpy.data.meshes.new(name + '_Mesh')
    mesh.from_pydata([bp(p) for p in points], [], faces)
    mesh.update()
    ob = bpy.data.objects.new(name, mesh)
    col.objects.link(ob)
    mesh.materials.append(mat)
    return ob


def clean(ob, recalc=True):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-6)
    bmesh.ops.dissolve_degenerate(bm, edges=list(bm.edges), dist=1e-7)
    isolated = [v for v in bm.verts if not v.link_faces]
    if isolated:
        bmesh.ops.delete(bm, geom=isolated, context='VERTS')
    if recalc:
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.update()


def clip(ob, point, normal, keep_negative=True, cap_index=0):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    r = bmesh.ops.bisect_plane(
        bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces),
        plane_co=bp(point), plane_no=bp(normal), dist=1e-6,
        clear_outer=keep_negative, clear_inner=not keep_negative)
    edges = [e for e in r['geom_cut'] if isinstance(e, bmesh.types.BMEdge) and e.is_boundary]
    caps = bmesh.ops.holes_fill(bm, edges=edges, sides=0)['faces'] if edges else []
    for f in caps:
        f.material_index = cap_index
        f.smooth = False
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.update()
    return {'cut_edges': len(edges), 'cap_polygons': len(caps)}


def boolean(target, cutter, operation):
    # The hand-authored cutter must have outward normals before an exact solid
    # operation. Recalculation is geometric, not a change to the requested cut.
    clean(cutter)
    bpy.context.view_layer.objects.active = target
    mod = target.modifiers.new('P10_Explicit_Contact_Volume', 'BOOLEAN')
    mod.operation, mod.solver, mod.object = operation, 'EXACT', cutter
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cutter, do_unlink=True)


def voxel_closed(ob, size):
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    ob.data.remesh_voxel_size = size
    ob.data.remesh_voxel_adaptivity = 0
    bpy.ops.object.voxel_remesh()
    clean(ob)


def gltf_mesh(path, mesh_id=0):
    data = json.loads(path.read_text(encoding='utf-8'))
    blob_path = path.parent / data['buffers'][0]['uri']
    primitive = data['meshes'][mesh_id]['primitives'][0]
    def acc(aid):
        a = data['accessors'][aid]
        view = data['bufferViews'][a['bufferView']]
        width = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[a['type']]
        code = {5126: 'f', 5125: 'I', 5123: 'H', 5121: 'B'}[a['componentType']]
        fmt = struct.Struct('<' + code * width)
        stride = view.get('byteStride', fmt.size)
        with blob_path.open('rb') as f:
            f.seek(view.get('byteOffset', 0) + a.get('byteOffset', 0))
            raw = f.read(stride * (a['count'] - 1) + fmt.size)
        return [fmt.unpack_from(raw, i * stride) for i in range(a['count'])]
    points = [Vector(p) for p in acc(primitive['attributes']['POSITION'])]
    indices = [v[0] for v in acc(primitive['indices'])]
    faces = [indices[i:i+3] for i in range(0, len(indices), 3)]
    return points, faces


# This source-space plane intersects only the identified unwanted long/high
# offshoots. The three large lower branches are on the retained side.
pruning = clip(root, (-.6, 0, 0), (1, 0, 0), False, 1)
root['p10_source_clip_x_min'] = -.6
root['source_transform_unchanged_from_p9'] = True
root.data.calc_loop_triangles()
root_matrix_before = root.matrix_world.copy()


def bvh(ob):
    ob.data.calc_loop_triangles()
    return BVHTree.FromPolygons(
        [ob.matrix_world @ v.co for v in ob.data.vertices],
        [tuple(t.vertices) for t in ob.data.loop_triangles], all_triangles=True)


def topology(ob):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    pending = set(bm.verts)
    counts = []
    while pending:
        stack = [pending.pop()]
        count = 0
        while stack:
            v = stack.pop()
            count += 1
            for e in v.link_edges:
                other = e.other_vert(v)
                if other in pending:
                    pending.remove(other)
                    stack.append(other)
        counts.append(count)
    result = {'components': sorted(counts, reverse=True),
              'boundary_edges': sum(e.is_boundary for e in bm.edges),
              'nonmanifold_edges': sum(not e.is_manifold for e in bm.edges),
              'signed_volume': bm.calc_volume(signed=True)}
    bm.free()
    return result


def object_bounds(ob):
    points = [gp(ob.matrix_world @ v.co) for v in ob.data.vertices]
    return {'min': [min(p[k] for p in points) for k in range(3)],
            'max': [max(p[k] for p in points) for k in range(3)]}


# Main stone: preserve the scan's real front triangles, rigidly align the mean
# rock face, then give it a continuous thick interior. This authored closure is
# explicitly recorded; it is not presented as unchanged scan geometry.
raw, faces = gltf_mesh(VENDOR / 'rock_face_01/rock_face_01_1k.gltf')
# Two source scanning flaps each create a three-face edge after UV seam weld.
# Exact source IDs/areas/normals are recorded in cliff_source_topology.json.
source_flaps_removed = [12891, 13431]
faces = [f for i, f in enumerate(faces) if i not in source_flaps_removed]
upright_plan = json.loads((PROJECT / 'asset_sources/v3/root_buttress/p9/upright_projection_plan.json').read_text())
upright = Matrix(upright_plan['matrix'])
aligned = [upright @ p for p in raw]
uniform_scale = 1.10
xcentre = (min(p.x for p in aligned) + max(p.x for p in aligned)) * .5
ymin = min(p.y for p in aligned)
zref = sorted(p.z for p in aligned)[len(aligned)//2]
angle = math.radians(35)
tangent = Vector((math.cos(angle), 0, math.sin(angle)))
normal = Vector((-math.sin(angle), 0, math.cos(angle)))
origin = Vector((2.1, -.30, .62))
front = [origin + tangent * ((p.x-xcentre)*uniform_scale)
         + Vector((0, (p.y-ymin)*uniform_scale, 0))
         + normal * ((p.z-zref)*uniform_scale) for p in aligned]
front_ob = mesh_obj('P10_NaturalCliffFront_OriginalTriangles', front, faces)
clean(front_ob)
bm = bmesh.new()
bm.from_mesh(front_ob.data)
bm.verts.ensure_lookup_table()
bm.verts.index_update()
front_vertices = [gp(v.co) for v in bm.verts]
front_faces = [tuple(v.index for v in f.verts) for f in bm.faces]
boundary = [e for e in bm.edges if e.is_boundary]
nonmanifold_source = sum(len(e.link_faces) > 2 for e in bm.edges)
assert nonmanifold_source == 0, ('source cleanup left a nonmanifold cliff edge', nonmanifold_source)
side_edges = []
for edge in boundary:
    loop = edge.link_loops[0]
    side_edges.append((loop.vert.index, loop.link_loop_next.vert.index))
bm.free()
source_archive = front_ob.copy()
source_archive.data = front_ob.data.copy()
archive.objects.link(source_archive)
source_archive.name = 'P10_AlignedNaturalCliffBeforeThickness'
source_archive.hide_render = True
source_archive.hide_viewport = True
bpy.data.objects.remove(front_ob, do_unlink=True)
depth = 4.5
n = len(front_vertices)
back_vertices = [v-normal*depth for v in front_vertices]
solid_faces = list(front_faces) + [tuple(n+i for i in reversed(f)) for f in front_faces]
solid_faces += [(a, n+a, n+b, b) for a, b in side_edges]
high = mesh_obj('P10_HighShoulder_ContinuousThickCliff', front_vertices+back_vertices, solid_faces)
clean(high)
construction_topology = [{'stage': 'raw_closed_extrusion', 'topology': topology(high)}]
for poly in high.data.polygons:
    poly.use_smooth = len(poly.vertices) == 3
for point, direction, negative in [
        ((0, -.18, 0), (0, 1, 0), False), ((0, 4.95, 0), (0, 1, 0), True),
        ((4.5, 0, 0), (1, 0, 0), True), ((-.9, 0, 0), (1, 0, 0), False),
        ((0, 0, -3.8), (0, 0, 1), False), ((0, 0, 3.4), (0, 0, 1), True)]:
    clip(high, point, direction, negative)
construction_topology.append({'stage': 'after_outer_cuts', 'topology': topology(high)})

# The last metre is an explicit engineering join to the existing 5.5m bridge.
# Its wedge meets the thick cliff, never a separate lid or hidden supporting box.
wedge_points = [(x, y, z) for y in [-.18, 4.5]
                for x, z in [(3.45, -3.15), (4.5, -3.15), (4.5, 3.0), (3.45, 3.0)]]
wedge_faces = [(3,2,1,0),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]
wedge = mesh_obj('Temporary_BridgeInterface_Volume', wedge_points, wedge_faces)
clean(wedge)
# Exact union of the folded scan perimeter and the coplanar join produced
# internal duplicate faces in the recorded failed trial. Keep the closed
# source bodies as editable hidden copies, and make a volumetric union of the
# copied stone only. The natural root and its proportions are never remeshed.
for ob in [high, wedge]:
    saved = ob.copy()
    saved.data = ob.data.copy()
    archive.objects.link(saved)
    saved.name = ob.name+'_BeforeContactVolumeUnion'
    saved.hide_render = True
    saved.hide_viewport = True
bpy.ops.object.select_all(action='DESELECT')
high.select_set(True)
wedge.select_set(True)
bpy.context.view_layer.objects.active = high
bpy.ops.object.join()
voxel_closed(high, .065)
# The engineering limits are cut again after the volume discretization.
clip(high, (4.5,0,0), (1,0,0), True)
clip(high, (0,4.95,0), (0,1,0), True)
clip(high, (0,-.18,0), (0,1,0), False)
construction_topology.append({'stage': 'after_065m_volume_interface_union', 'topology': topology(high)})
# Cut the entire final metre to the exact join height, from the same volume.
box_points = [(x,y,z) for y in [4.5, 8] for x,z in [(3.5,-8),(8,-8),(8,8),(3.5,8)]]
cutter = mesh_obj('Temporary_JoinTop_Cut', box_points, wedge_faces)
boolean(high, cutter, 'DIFFERENCE')
clean(high)
bm = bmesh.new()
bm.from_mesh(high.data)
unseen = set(bm.verts)
generated_islands = []
while unseen:
    start = unseen.pop()
    pending = [start]
    component = [start]
    while pending:
        v = pending.pop()
        for edge in v.link_edges:
            other = edge.other_vert(v)
            if other in unseen:
                unseen.remove(other)
                pending.append(other)
                component.append(other)
    if len(component) > 16:
        continue
    points = [gp(v.co) for v in component]
    lo = [min(p[k] for p in points) for k in range(3)]
    hi = [max(p[k] for p in points) for k in range(3)]
    extents = [b-a for a,b in zip(lo,hi)]
    # The failed-e report identified this detached 0.254x0.164x0.170m remesh
    # island, away from every root/bridge/ground contact. Remove only that
    # measured artifact, not arbitrary larger disconnected stone pieces.
    measured_detached_island = (len(component) == 8
        and -.23 < lo[0] < -.22 and .02 < hi[0] < .04
        and 3.50 < lo[1] < 3.52 and 3.66 < hi[1] < 3.68
        and -.87 < lo[2] < -.85 and -.70 < hi[2] < -.68)
    small_generated_fragment = (max(extents) < .15 and math.prod(extents) < .001) or measured_detached_island
    generated_islands.append({'vertices': len(component), 'min': lo, 'max': hi,
                              'removed_after_verified_size': small_generated_fragment})
    if small_generated_fragment:
        bmesh.ops.delete(bm, geom=component, context='VERTS')
bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
bm.to_mesh(high.data)
bm.free()
high.data.update()
construction_topology.append({'stage': 'after_join_top_cut', 'topology': topology(high)})
bpy.context.view_layer.update()
root_tree = bvh(root)


def root_lower_at(x, z):
    hit = root_tree.ray_cast(bp((x,-3,z)), bp((0,1,0)), 12)
    return gp(hit[0]) if hit[0] is not None else None


def stone_surface_at(tree, x, z):
    hit = tree.ray_cast(bp((x,8,z)), bp((0,-1,0)), 15)
    return gp(hit[0]) if hit[0] is not None else None


contacts = []
low_stones = []
for name, mesh_id, uniform, yaw, target in [
        ('P10_BackMiddle_NaturalRock01', 0, 1.75, 180, (-2.43, -2.50)),
        ('P10_FrontLower_NaturalRock04', 3, 1.40, -90, (-2.31, 3.03)),
        ('P10_LowToe_NaturalRock03', 2, .50, 30, (-1.45, 3.65))]:
    points, rock_faces = gltf_mesh(MOSS, mesh_id)
    yaw_r = math.radians(yaw)
    rotation = Matrix(((math.cos(yaw_r),0,math.sin(yaw_r)),(0,1,0),(-math.sin(yaw_r),0,math.cos(yaw_r))))
    positioned = [rotation @ p * uniform for p in points]
    ob = mesh_obj(name, positioned, rock_faces, warm_stone)
    clean(ob)
    raw_topology = topology(ob)
    # Rock04 has tiny scan gaps. Only a copied stone is resampled; no natural
    # root is remeshed, and no source file is modified. Closed originals stay.
    remesh_size = .035 if raw_topology['nonmanifold_edges'] else 0.0
    if remesh_size:
        voxel_closed(ob, remesh_size)
    for p in ob.data.polygons:
        p.use_smooth = True
    peak = max((gp(v.co) for v in ob.data.vertices), key=lambda p:p.y)
    ob.location = bp((target[0]-peak.x, 0, target[1]-peak.z))
    bpy.context.view_layer.update()
    wood_point = root_lower_at(*target)
    stone_point = stone_surface_at(bvh(ob), *target)
    assert wood_point is not None and stone_point is not None, (name, target, wood_point, stone_point)
    # A 3cm buried contact avoids a merely tangent floating point. No wood or
    # stone vertices are stretched to force the contact height.
    dy = wood_point.y - stone_point.y + .03
    ob.location += bp((0,dy,0))
    bpy.context.view_layer.update()
    contacts.append({'name': name, 'source_mesh': mesh_id, 'uniform_scale': uniform, 'yaw_degrees': yaw,
                     'source_topology': raw_topology, 'copy_voxel_repair_size': remesh_size,
                     'real_highest_vertex_before_rigid_placement': list(peak),
                     'target_xz': list(target), 'root_lower_point': list(wood_point),
                     'stone_surface_before_shift': list(stone_point), 'rigid_y_shift': dy,
                     'stone_bounds': object_bounds(ob)})
    low_stones.append(ob)

checks = []


def check(name, ok, detail=None):
    checks.append({'name': name, 'pass': bool(ok), 'detail': detail})


root_topology = topology(root)
check('root_cut_remains_single_closed_component', root_topology['boundary_edges'] == 0
      and root_topology['nonmanifold_edges'] == 0 and len(root_topology['components']) == 1, root_topology)
check('root_transform_unchanged_from_p9', root.matrix_world == root_matrix_before)
for ob in [high, *low_stones]:
    t = topology(ob)
    check(ob.name+'_closed_solid', t['boundary_edges'] == 0 and t['nonmanifold_edges'] == 0
          and len(t['components']) == 1 and t['signed_volume'] > 0, t)
for record, ob in zip(contacts, low_stones):
    wp = Vector(record['root_lower_point'])
    sp = stone_surface_at(bvh(ob), wp.x, wp.z)
    depth_here = sp.y-wp.y if sp is not None else None
    record['actual_stone_contact_point'] = list(sp) if sp else None
    record['actual_wood_burial_m'] = depth_here
    check(ob.name+'_actual_surface_contact', depth_here is not None and .025 < depth_here < .035, record)
    check(ob.name+'_not_floating_above_ground', record['stone_bounds']['min'][1] <= .01, record['stone_bounds'])

high_tree = bvh(high)
base_cap_vertices = [v for v in root.data.vertices if abs(v.co.z-.1) < 1e-5]
outside = []
for v in base_cap_vertices:
    pt = root.matrix_world @ v.co
    near, normal_at, _, distance = high_tree.find_nearest(pt)
    if near is None or (pt-near).dot(normal_at) > -.008:
        outside.append({'point_godot': list(gp(pt)), 'signed_nearest_m': (pt-near).dot(normal_at) if near else None})
check('entire_high_base_cut_buried_in_real_stone', len(base_cap_vertices) > 100 and not outside,
      {'cap_vertices': len(base_cap_vertices), 'outside_or_shallow': outside})
join_hits = []
for x in [3.55, 4.0, 4.49]:
    for z in [-2.75,-1.375,0,1.375,2.75]:
        hit = stone_surface_at(high_tree, x, z)
        join_hits.append({'xz': [x,z], 'hit': list(hit) if hit else None})
check('last_metre_5_5m_bridge_join_Y4_5', all(h['hit'] and abs(h['hit'][1]-4.5)<.001 for h in join_hits), join_hits)
all_ob = [root, high, *low_stones]
bounds = {ob.name: object_bounds(ob) for ob in all_ob}
triangle_counts = {}
for ob in all_ob:
    ob.data.calc_loop_triangles()
    triangle_counts[ob.name] = len(ob.data.loop_triangles)
check('all_above_ground_geometry_inside_engineering_XZ',
      all(b['min'][0] >= -4.55 and b['max'][0] <= 4.501 and b['min'][2] >= -6 and b['max'][2] <= 6 for b in bounds.values()), bounds)
check('height_under_5m', all(b['max'][1] <= 5.001 for b in bounds.values()), bounds)
check('readonly_inputs_unchanged', all(sha(PROJECT/p)==value for p,value in frozen.items()))

scene.camera.data.ortho_scale = 16.2
target = bp((0,2.15,0))
scene.camera.location = bp((15,16,20))
scene.camera.rotation_euler = (target-scene.camera.location).to_track_quat('-Z','Y').to_euler()
scene.render.filepath = str(OUT/'root-shoulder-contact-p10.png')
scene.render.threads_mode, scene.render.threads = 'FIXED', 2
scene.cycles.device, scene.cycles.samples = 'CPU', 12
scene.render.resolution_x, scene.render.resolution_y = 1400, 1050
scene.render.resolution_percentage = 100
report = {
    'stage': 'P10 basic-form contact candidate only; no textures, baking, GLB or runtime changes',
    'pruning': {'source_plane_x_min': -.6, 'actual_cut': pruning,
                'removed_source_tip_sections': [4,5], 'root_uniform_scale': 3.0,
                'root_rigid_transform_unchanged': True},
    'main_stone_method': {'source': 'Poly Haven Rock Face 01', 'original_front_triangles_archived_except_named_flaps': True,
                          'source_scanning_flap_face_ids_removed': source_flaps_removed,
                          'final_copied_stone_volumetric_union_size_m': .065,
                          'rigid_upright_matrix': list(map(list,upright)), 'source_uniform_scale': uniform_scale,
                          'yaw_degrees': 35, 'authored_thickness_direction': list(-normal), 'thickness_m': depth,
                          'authored_geometry': 'back copy, perimeter closure, ground/top cuts and last-metre bridge interface',
                          'not_unchanged_scan': True},
    'construction_topology': construction_topology,
    'generated_volume_cut_islands': generated_islands,
    'sources': ['https://polyhaven.com/a/island_tree_01', 'https://polyhaven.com/a/rock_face_01',
                'https://polyhaven.com/a/rock_moss_set_01'], 'license': 'CC0',
    'frozen_input_sha256': frozen, 'contacts': contacts, 'bounds': bounds,
    'triangle_counts': triangle_counts, 'checks': checks,
    'passed': sum(c['pass'] for c in checks), 'total': len(checks), 'all_pass': all(c['pass'] for c in checks),
    'limits': ['contact probes do not establish visual approval',
               'root/rock embedding is intentional; exposed crossing still needs the one-frame review',
               'this is not the complete T03-A shore, wet channel, final terrain or game integration',
               'no old candidate, runtime or shared document was edited'],
}
blend = OUT/'root_shoulder_contact_p10.blend'
bpy.ops.wm.save_as_mainfile(filepath=str(blend))
report['blend_sha256'] = sha(blend)
(OUT/'p10_geometry_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('P10_CONTACT_REPORT '+json.dumps({'passed':report['passed'],'total':report['total'],'all_pass':report['all_pass']}),flush=True)
for c in checks:
    if not c['pass']:
        print('P10_FAIL '+json.dumps(c,ensure_ascii=False),flush=True)
if '--render' in sys.argv:
    assert report['all_pass'], 'Geometry/contact gates failed; do not render an unsupported candidate'
    bpy.ops.render.render(write_still=True)
assert all(sha(PROJECT/p)==value for p,value in frozen.items())
print('P10_DONE_SOURCE_ONLY',flush=True)
