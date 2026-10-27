"""Natural tree-base extraction / continuous deformation study. No runtime export.

Only glTF mesh 0 primitive 0 is decoded. Original vendor bytes are read-only.
Left: exact clipped source at 3x for inspection. Right: deformed editable copy.
"""
import bpy
import bmesh
import hashlib
import json
import math
import struct
from pathlib import Path
from mathutils import Vector

PROJECT = Path(__file__).resolve().parents[4]
SOURCE = PROJECT / 'asset_sources/third_party/island_tree_01'
OUT = PROJECT / 'asset_sources/v3/shore_root/p7'
ART = PROJECT / 'artifacts/v3/art/shore_root/p7'
OUT.mkdir(parents=True, exist_ok=True)
ART.mkdir(parents=True, exist_ok=True)
GLTF = SOURCE / 'island_tree_01_1k.gltf'
BIN = SOURCE / 'island_tree_01.bin'
hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in [GLTF, BIN]}
data = json.loads(GLTF.read_text(encoding='utf-8'))
primitive = data['meshes'][0]['primitives'][0]
assert primitive['attributes']['POSITION'] == 0 and primitive['indices'] == 3
assert data['accessors'][3]['count'] == 104361
assert data['nodes'] == [{'mesh': 0, 'name': 'island_tree_01_LOD0'}]


def decode(accessor_id):
    a = data['accessors'][accessor_id]
    v = data['bufferViews'][a['bufferView']]
    n = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3}[a['type']]
    fmt = {5126: 'f', 5125: 'I', 5123: 'H'}[a['componentType']]
    s = struct.Struct('<' + fmt*n)
    stride = v.get('byteStride', s.size)
    offset = v.get('byteOffset', 0) + a.get('byteOffset', 0)
    # Seek only this primitive's accessor; never deserialize foliage geometry.
    with BIN.open('rb') as f:
        f.seek(offset)
        blob = f.read(stride*(a['count']-1) + s.size)
    return [s.unpack_from(blob, i*stride) for i in range(a['count'])]


positions = decode(0)
indices = [i[0] for i in decode(3)]
faces = [indices[i:i+3] for i in range(0, len(indices), 3)]
inside_source_faces = [i for i, f in enumerate(faces) if max(positions[j][1] for j in f) <= .95]
intersected_source_faces = [i for i, f in enumerate(faces) if min(positions[j][1] for j in f) <= .95 < max(positions[j][1] for j in f)]


def bp(p):
    return Vector((p[0], -p[2], p[1]))


def gp(p):
    return [float(p.x), float(p.z), float(-p.y)]


def bounds(vertices):
    return {'min': [min(p[i] for p in vertices) for i in range(3)],
            'max': [max(p[i] for p in vertices) for i in range(3)]}


bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene


def collection(name):
    c = bpy.data.collections.new(name)
    scene.collection.children.link(c)
    return c


original = collection('READ_ONLY_PRIMITIVE_COPY_NO_FOLIAGE')
study = collection('EDITABLE_ROOT_FRAGMENT_STUDY')
studio = collection('STUDIO_NOT_ASSET')


def make_material(name, color):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = (*color, 1)
    p.inputs['Roughness'].default_value = .86
    p.inputs['Specular IOR Level'].default_value = .18
    return m


clay = make_material('Source_Clay_No_Texture', (.28, .29, .27))
wood = make_material('Root_Base_Colour_No_Texture', (.29, .215, .14))
label_mat = make_material('Study_Label', (.65, .68, .66))
mesh = bpy.data.meshes.new('Primitive0_Exact_Source_Positions_Indices')
mesh.from_pydata([bp(p) for p in positions], [], faces)
mesh.update()
source_obj = bpy.data.objects.new('Exact_Primitive0_Unchanged_Copy', mesh)
original.objects.link(source_obj)
source_obj['source_mesh'] = 0
source_obj['source_primitive'] = 0
source_obj['source_material_index'] = 0
source_obj['not_used_for_render'] = True
original.hide_render = True
original.hide_viewport = True

fragment_mesh = mesh.copy()
fragment_mesh.name = 'TreeBase_Clipped_At_SourceY_095'
bm = bmesh.new()
bm.from_mesh(fragment_mesh)
before_vertices = len(bm.verts)
bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-6)
welded_vertices = len(bm.verts)
result = bmesh.ops.bisect_plane(
    bm, geom=list(bm.verts)+list(bm.edges)+list(bm.faces),
    dist=1e-6, plane_co=Vector((0, 0, .95)), plane_no=Vector((0, 0, 1)),
    clear_outer=True, clear_inner=False, use_snap_center=False)
cut_edges = [e for e in result['geom_cut'] if isinstance(e, bmesh.types.BMEdge) and e.is_boundary]
cap_faces = bmesh.ops.holes_fill(bm, edges=cut_edges, sides=0)['faces'] if cut_edges else []
cap_count = len(cap_faces)
for f in cap_faces:
    f.material_index = 0
bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
bm.to_mesh(fragment_mesh)
bm.free()
fragment_mesh.update()
fragment_mesh.calc_loop_triangles()
fragment_vertices = [gp(v.co) for v in fragment_mesh.vertices]
source_fragment_bounds = bounds(fragment_vertices)
fragment_triangles = len(fragment_mesh.loop_triangles)
raw = bpy.data.objects.new('Source_Base_Fragment_Display_3x', fragment_mesh)
study.objects.link(raw)
raw.data.materials.append(clay)
raw.scale = (3, 3, 3)
raw.location = bp((-7.1, .07, -.7))
raw['display_only_scale'] = 3.0
raw['clip_plane_in_original_gltf'] = 'Y = 0.95; retain lower side; cap only new cut boundary'

# Compute robust source cross-section centres from the selected geometry. A
# smoothed centre curve retains real bark / root cross sections, not an invented
# circular or swept polygon profile.
knots = []
for height in [0, .15, .30, .45, .60, .75, .90, .95]:
    band = [v for v in positions if abs(v[1]-height) <= .055]
    xs = sorted(v[0] for v in band)
    zs = sorted(v[2] for v in band)
    knots.append((height, xs[len(xs)//2], zs[len(zs)//2]))


def source_centre(y):
    if y <= knots[0][0]:
        return knots[0][1], knots[0][2]
    for a, b in zip(knots, knots[1:]):
        if y <= b[0]:
            t = (y-a[0])/(b[0]-a[0])
            t = t*t*(3-2*t)
            return a[1]+(b[1]-a[1])*t, a[2]+(b[2]-a[2])*t
    return knots[-1][1], knots[-1][2]


def centre(t):
    return Vector((-3.6+7*t,
                   .72+3.53*t+.24*math.sin(math.pi*t),
                   2.1+.32*math.sin(math.pi*t*1.3)))


def deform(p):
    x, y, z = p
    t = max(0.0, min(1.0, (y+.020327899605035782)/.9703278996050357))
    cx, cz = source_centre(y)
    tangent = (centre(min(1, t+.002))-centre(max(0, t-.002))).normalized()
    side = tangent.cross(Vector((0, 1, 0))).normalized()
    up = side.cross(tangent).normalized()
    twist = .14*math.sin(math.pi*t)-.10*t
    s = side*math.cos(twist)+up*math.sin(twist)
    u = up*math.cos(twist)-side*math.sin(twist)
    # Unequal source root buttresses remain distinct; the transverse scale varies
    # slowly instead of imposing a constant-width tube or faceted ribbon.
    width_scale = 3.20-.40*t
    depth_scale = 1.45-.20*t
    return centre(t)+s*((x-cx)*width_scale)+u*((z-cz)*depth_scale)


adapted_mesh = fragment_mesh.copy()
adapted_mesh.name = 'Continuous_Deformed_Source_Base_Editable'
adapted_mesh.materials.clear()
adapted_mesh.materials.append(wood)
for v, p in zip(adapted_mesh.vertices, fragment_vertices):
    v.co = bp(deform(p))
adapted_mesh.update()
for p in adapted_mesh.polygons:
    p.use_smooth = True
adapted = bpy.data.objects.new('Natural_Root_Continuous_Deformation_Study', adapted_mesh)
study.objects.link(adapted)
adapted['method'] = 'Source root/base cross sections continuously mapped along authored oblique centreline; no swept replacement mesh.'
adapted['status'] = 'method test only, not a finished root or shore asset'
reduce = adapted.modifiers.new('Prototype_Reduction_NOT_Final_Retopology', 'DECIMATE')
reduce.ratio = .70
reduce.use_collapse_triangulate = True


def aim(obj, at):
    obj.rotation_euler = (bp(at)-obj.location).to_track_quat('-Z', 'Y').to_euler()


def light(name, at, energy, size, colour):
    d = bpy.data.lights.new(name, 'AREA')
    d.energy, d.size, d.color = energy, size, colour
    o = bpy.data.objects.new(name, d)
    studio.objects.link(o)
    o.location = bp(at)
    aim(o, (-2.5, 1.8, 1))


light('Study_Key', (-6, 17, 12), 2300, 11, (1, .95, .88))
light('Study_Fill', (11, 10, -8), 1600, 11, (.86, .92, 1))
light('Study_Rim', (-9, 10, -8), 1500, 9, (1, .94, .83))
bpy.ops.mesh.primitive_plane_add(size=100, location=(0, 0, -.003))
floor = bpy.context.object
for c in list(floor.users_collection):
    c.objects.unlink(floor)
studio.objects.link(floor)
floor.name = 'Studio_Ground_NOT_Contact_Proof'
floor.data.materials.append(make_material('Studio_Neutral', (.20, .22, .23)))

camera_data = bpy.data.cameras.new('ReviewCamera')
camera = bpy.data.objects.new('ReviewCamera', camera_data)
studio.objects.link(camera)
scene.camera = camera
camera_data.type = 'ORTHO'
camera_data.ortho_scale = 17.0
camera.location = bp((11, 14, 21))
aim(camera, (-2.9, 2.1, 1.1))


def label(name, text, at):
    d = bpy.data.curves.new(name, 'FONT')
    d.body = text
    d.size = .25
    d.align_x = 'CENTER'
    d.extrude = 0
    o = bpy.data.objects.new(name, d)
    studio.objects.link(o)
    o.location = bp(at)
    o.rotation_euler = camera.rotation_euler
    d.materials.append(label_mat)


label('Raw_Label', 'SOURCE BASE / DISPLAY x3', (-7.1, 3.65, -.7))
label('Study_Label', 'CONTINUOUS DEFORMATION / NO TEXTURES', (0, 5.2, 2.2))
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 12
scene.cycles.use_denoising = True
scene.render.threads_mode = 'FIXED'
scene.render.threads = 2
scene.render.resolution_x = 1440
scene.render.resolution_y = 900
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.world.use_nodes = True
scene.world.node_tree.nodes.get('Background').inputs['Color'].default_value = (.30, .33, .36, 1)
scene.world.node_tree.nodes.get('Background').inputs['Strength'].default_value = .45
scene.view_settings.view_transform = 'AgX'
scene.view_settings.look = 'AgX - Medium High Contrast'
bpy.context.view_layer.update()
evaluated = adapted.evaluated_get(bpy.context.evaluated_depsgraph_get())
evmesh = evaluated.to_mesh()
evmesh.calc_loop_triangles()
eval_triangles = len(evmesh.loop_triangles)
eval_bounds = bounds([gp(v.co) for v in evmesh.vertices])
evaluated.to_mesh_clear()
# Never hide a warped lower surface inside the studio floor to imply contact.
floor.location.z = min(-.003, eval_bounds['min'][1]-.01)

report = {
    'study': 'T03-A p7 natural root source extraction and continuous deformation',
    'scope': 'one offline basic-colour method trial, no complete shore / runtime export / final topology',
    'blender': bpy.app.version_string,
    'source': {'asset_url': 'https://polyhaven.com/a/island_tree_01',
               'license_url': 'https://polyhaven.com/license', 'license': 'CC0',
               'artists': ['Rico Cilliers', 'Rob Tuytel'], 'file_sha256': hashes,
               'mesh': 0, 'primitive': 0, 'position_accessor': 0, 'index_accessor': 3,
               'source_vertices': len(positions), 'source_triangles': len(faces),
               'primitive_bounds_gltf': bounds(positions),
               'other_primitives_deserialized': False},
    'fragment': {'cut_plane_gltf_y': .95, 'retained_side': 'lower',
                 'original_faces_fully_inside': inside_source_faces,
                 'original_faces_intersecting_plane': intersected_source_faces,
                 'welded_vertices_before_clip': before_vertices-welded_vertices,
                 'new_cut_caps': cap_count, 'triangles': fragment_triangles,
                 'bounds_gltf': source_fragment_bounds,
                 'raw_display_uniform_scale': 3,
                 'source_centre_knots_y_x_z': knots},
    'deformation': {'method': adapted['method'],
                    'authored_centre_low_godot': list(centre(0)),
                    'authored_centre_high_godot': list(centre(1)),
                    'editable_mesh_triangles': fragment_triangles,
                    'evaluated_reduced_triangles': eval_triangles,
                    'bounds_godot': eval_bounds,
                    'studio_floor_godot_y': float(floor.location.z),
                    'non_destructive_decimate_ratio': .7,
                    'not_final_retopology': True},
    'limits': ['The original base has short radial buttresses, not a complete long forked shore root.',
               'The source is longitudinally stretched; shape suitability must be judged from the rendered geometry.',
               'No stone support/contact, bridge interface, collision, UV transfer, final topology or game camera validation.',
               'The comparison is source fragment x3 versus a deformed copy, not two equal-scale final assets.']}
source_path = OUT / 'natural_root_method_study.blend'
scene['study_report'] = json.dumps(report, ensure_ascii=False)
bpy.ops.wm.save_as_mainfile(filepath=str(source_path))
report['editable_source'] = {'path': str(source_path), 'bytes': source_path.stat().st_size,
                           'sha256': hashlib.sha256(source_path.read_bytes()).hexdigest()}
(OUT / 'source_fragment_report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
scene.render.filepath = str(ART / 'natural-root-source-and-deformation.png')
bpy.ops.render.render(write_still=True)
assert hashes == {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in [GLTF, BIN]}, 'Vendor source was changed'
print('NATURAL_ROOT_STUDY_DONE ' + json.dumps({'source_fragment_triangles': fragment_triangles,
                                            'deformed_triangles': eval_triangles,
                                            'bounds_godot': eval_bounds, 'source_unchanged': True}))
