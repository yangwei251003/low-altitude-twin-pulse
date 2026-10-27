"""One untextured source-structure sheet: wood skeleton + coarse fork, no warp.

This is source selection research. It creates no game asset and edits no vendor
file. The two crops are the same geometry at two rigid orientations.
"""
import bpy
import bmesh
import json
import hashlib
import math
import struct
from pathlib import Path
from mathutils import Vector, Quaternion

PROJECT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent
VENDOR = PROJECT / 'asset_sources/third_party/island_tree_01'
GLTF = VENDOR / 'island_tree_01_1k.gltf'
BIN = VENDOR / 'island_tree_01.bin'
hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in [GLTF, BIN]}
data = json.loads(GLTF.read_text(encoding='utf-8'))
assert data['nodes'] == [{'mesh': 0, 'name': 'island_tree_01_LOD0'}]


def decode(aid):
    a = data['accessors'][aid]
    v = data['bufferViews'][a['bufferView']]
    n = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3}[a['type']]
    fmt = {5126: 'f', 5125: 'I', 5123: 'H'}[a['componentType']]
    s = struct.Struct('<'+fmt*n)
    stride = v.get('byteStride', s.size)
    with BIN.open('rb') as f:
        f.seek(v.get('byteOffset', 0)+a.get('byteOffset', 0))
        blob = f.read(stride*(a['count']-1)+s.size)
    return [s.unpack_from(blob, i*stride) for i in range(a['count'])]


def bp(p):
    return Vector((p[0], -p[2], p[1]))


def gp(p):
    return [float(p.x), float(p.z), float(-p.y)]


def bounds(points):
    return {'min': [min(p[i] for p in points) for i in range(3)],
            'max': [max(p[i] for p in points) for i in range(3)]}


primitive = data['meshes'][0]['primitives'][0]
positions = decode(primitive['attributes']['POSITION'])
indices = [v[0] for v in decode(primitive['indices'])]
faces = [indices[i:i+3] for i in range(0, len(indices), 3)]
assert len(faces) == 34787
metadata = []
for i, p in enumerate(data['meshes'][0]['primitives']):
    a = data['accessors'][p['attributes']['POSITION']]
    metadata.append({'primitive': i, 'material': data['materials'][p['material']],
                     'vertices': a['count'], 'triangles': data['accessors'][p['indices']]['count']//3,
                     'bounds_gltf': {'min': a['min'], 'max': a['max']},
                     'decoded_in_blender': i == 0})

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene


def collection(name):
    c = bpy.data.collections.new(name)
    scene.collection.children.link(c)
    return c


source_collection = collection('SOURCE_STRUCTURE_NO_STRETCH')
studio = collection('STUDIO_NOT_ASSET')


def material(name, colour):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*colour, 1)
    m.use_nodes = True
    p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = (*colour, 1)
    p.inputs['Roughness'].default_value = .84
    p.inputs['Specular IOR Level'].default_value = .17
    return m


wood = material('Basic_Colour_No_Textures', (.28, .215, .15))
clay = material('Context_Wood_Clay_No_Textures', (.245, .26, .255))
cut_material = material('Cut_Caps_Only', (.33, .30, .255))
label_mat = material('Label', (.64, .68, .67))
full_mesh = bpy.data.meshes.new('Primitive0_Original_Positions_Indices')
full_mesh.from_pydata([bp(p) for p in positions], [], faces)
full_mesh.update()
full_mesh.materials.append(clay)
for p in full_mesh.polygons:
    p.use_smooth = True
full = bpy.data.objects.new('Full_Wood_Skeleton_Original_Proportions', full_mesh)
source_collection.objects.link(full)

# The source has a continuous coarse side fork beginning near glTF Y=1.0.
# Clip only two horizontal planes; no proportional stretch or newly drawn branch.
LOW, HIGH = .85, 1.80
crop_mesh = full_mesh.copy()
crop_mesh.name = 'Actual_Coarse_Fork_SourceY_085_180'
crop_mesh.materials.clear()
crop_mesh.materials.append(wood)
crop_mesh.materials.append(cut_material)
bm = bmesh.new()
bm.from_mesh(crop_mesh)
bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-6)
cut_record = []
for height, outward in [(LOW, -1), (HIGH, 1)]:
    result = bmesh.ops.bisect_plane(bm,
        geom=list(bm.verts)+list(bm.edges)+list(bm.faces),
        dist=1e-6, plane_co=Vector((0, 0, height)),
        plane_no=Vector((0, 0, outward)), clear_outer=True,
        clear_inner=False, use_snap_center=False)
    edges = [e for e in result['geom_cut'] if isinstance(e, bmesh.types.BMEdge) and e.is_boundary]
    caps = bmesh.ops.holes_fill(bm, edges=edges, sides=0)['faces'] if edges else []
    for f in caps:
        f.material_index = 1
        f.smooth = False
    cut_record.append({'gltf_y': height, 'outward': outward, 'cap_faces': len(caps)})
bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
bm.to_mesh(crop_mesh)
bm.free()
crop_mesh.update()
crop_mesh.calc_loop_triangles()
crop_bounds = bounds([gp(v.co) for v in crop_mesh.vertices])

# Arrange panels along camera-right. Display scales are uniform and explicit.
screen_right = Vector((.894427, 0, -.447214))


def arrange(obj, offset, uniform_scale, yaw):
    q = Quaternion((0, 0, 1), math.radians(yaw))
    pts = [q@v.co*uniform_scale for v in obj.data.vertices]
    xmid = (max(v.x for v in pts)+min(v.x for v in pts))*.5
    ymid = (max(v.y for v in pts)+min(v.y for v in pts))*.5
    zmin = min(v.z for v in pts)
    obj.rotation_mode = 'QUATERNION'
    obj.rotation_quaternion = q
    obj.scale = (uniform_scale,)*3
    obj.location = bp(screen_right*offset)-Vector((xmid, ymid, zmin))
    obj.location.z += .025
    obj['display_uniform_scale'] = uniform_scale
    obj['display_yaw_degrees'] = yaw
    obj['geometry_stretched'] = False


arrange(full, -5.45, 1.35, 0)
front = bpy.data.objects.new('Coarse_Fork_A_Original_Proportions', crop_mesh)
source_collection.objects.link(front)
arrange(front, 0, 2.35, 0)
back = bpy.data.objects.new('Coarse_Fork_B_Same_Mesh_Rigid_View', crop_mesh)
source_collection.objects.link(back)
arrange(back, 5.45, 2.35, 155)


def aim(obj, target):
    obj.rotation_euler = (bp(target)-obj.location).to_track_quat('-Z', 'Y').to_euler()


def light(name, at, energy, size, colour):
    d = bpy.data.lights.new(name, 'AREA')
    d.energy, d.size, d.color = energy, size, colour
    o = bpy.data.objects.new(name, d)
    studio.objects.link(o)
    o.location = bp(at)
    aim(o, (0, 1.8, 0))


light('Key', (-7, 18, 13), 2600, 13, (1, .95, .88))
light('Fill', (12, 12, -9), 2000, 13, (.86, .92, 1))
light('Rim', (-11, 12, -8), 1700, 10, (1, .94, .83))
bpy.ops.mesh.primitive_plane_add(size=120, location=(0, 0, -.003))
floor = bpy.context.object
for c in list(floor.users_collection):
    c.objects.unlink(floor)
studio.objects.link(floor)
floor.name = 'Studio_Floor_Not_Root_Contact'
floor.data.materials.append(material('Neutral_Studio', (.195, .215, .225)))
cd = bpy.data.cameras.new('SourceReviewCamera')
camera = bpy.data.objects.new('SourceReviewCamera', cd)
studio.objects.link(camera)
scene.camera = camera
cd.type, cd.ortho_scale = 'ORTHO', 18.5
camera.location = bp((10, 10, 20))
aim(camera, (0, 2.3, 0))


def label(name, body, offset, height):
    c = bpy.data.curves.new(name, 'FONT')
    c.body, c.size, c.align_x = body, .245, 'CENTER'
    o = bpy.data.objects.new(name, c)
    studio.objects.link(o)
    pos = screen_right*offset
    pos.y = height
    o.location = bp(pos)
    o.rotation_euler = camera.rotation_euler
    c.materials.append(label_mat)


label('ContextLabel', 'WOOD SKELETON / x1.35', -5.45, 5.35)
label('FrontLabel', 'COARSE FORK / x2.35', 0, 4.05)
label('BackLabel', 'SAME FORK / ROTATED 155 deg', 5.45, 4.05)
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 12
scene.cycles.use_denoising = True
scene.render.threads_mode, scene.render.threads = 'FIXED', 2
scene.render.resolution_x, scene.render.resolution_y = 1680, 960
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.world.use_nodes = True
scene.world.node_tree.nodes.get('Background').inputs['Color'].default_value = (.30, .33, .36, 1)
scene.world.node_tree.nodes.get('Background').inputs['Strength'].default_value = .45
scene.view_settings.view_transform = 'AgX'
scene.view_settings.look = 'AgX - Medium High Contrast'
bpy.context.view_layer.update()
report = {
    'scope': 'p8 source structure comparison only; no deformation / complete shore / runtime export',
    'source_asset': 'https://polyhaven.com/a/island_tree_01',
    'license': 'CC0', 'license_url': 'https://polyhaven.com/license',
    'artists': ['Rico Cilliers', 'Rob Tuytel'],
    'vendor_sha256': hashes, 'source_nodes': data['nodes'],
    'primitives': metadata,
    'source_skeleton_triangles': len(faces),
    'fragment': {'mesh': 0, 'primitive': 0, 'low_gltf_y': LOW, 'high_gltf_y': HIGH,
                 'bounds_gltf': crop_bounds, 'triangles': len(crop_mesh.loop_triangles),
                 'clip_caps': cut_record,
                 'original_face_ids_fully_inside': [i for i, f in enumerate(faces)
                     if all(LOW <= positions[j][1] <= HIGH for j in f)],
                 'original_face_ids_crossing_cut': [i for i, f in enumerate(faces)
                     if min(positions[j][1] for j in f) <= HIGH and max(positions[j][1] for j in f) >= LOW
                     and not all(LOW <= positions[j][1] <= HIGH for j in f)],
                 'display_only_transforms': [
                     {'panel': 'full', 'uniform_scale': 1.35, 'yaw': 0},
                     {'panel': 'crop A', 'uniform_scale': 2.35, 'yaw': 0},
                     {'panel': 'crop B same mesh', 'uniform_scale': 2.35, 'yaw': 155}],
                 'nonuniform_scaling': False, 'continuous_deformation': False,
                 'retopology_or_decimation': False},
    'limits': ['This is an above-ground tree branch fork, not a scanned exposed root system.',
               'Horizontal cropping can truncate useful branches; evaluate shape using the full skeleton too.',
               'No stone contact, shoreline, bridge connection, game collision or graphics evidence.']}
path = OUT/'branch_source_structure.blend'
scene['source_structure_report'] = json.dumps(report, ensure_ascii=False)
bpy.ops.wm.save_as_mainfile(filepath=str(path))
report['blend_sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
(OUT/'branch_source_structure.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
scene.render.filepath = str(OUT/'branch-source-structure.png')
bpy.ops.render.render(write_still=True)
assert hashes == {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in [GLTF, BIN]}
print('BRANCH_SOURCE_STRUCTURE_DONE '+json.dumps({'source_triangles': len(faces),
    'crop_triangles': len(crop_mesh.loop_triangles), 'crop_bounds': crop_bounds,
    'source_unchanged': True}))
