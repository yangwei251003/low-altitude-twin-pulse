"""T03-A editable main-form study, not a runtime exporter.

Coordinates in authored arrays are Godot X/Y/Z metres.  Blender's Z is up.
Only this asset's source and review directories are written.  The frozen root
arch is imported read-only for a separately labelled offline assembly view.
"""
import bpy
import hashlib
import json
import math
import random
import sys
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree

PROJECT = Path(__file__).resolve().parents[3]
SOURCE = PROJECT / 'asset_sources/v3/shore_root'
REVIEW = PROJECT / 'artifacts/v3/art/shore_root'
BRIDGE = PROJECT / 'assets/v3/root_arch/f1_root_arch.glb'
BRIDGE_SHA = 'a14fd39f649ddd00cf2316126349b841376334879022e6c9256b6ed323ddd581'
REVISION = 'p1'
SOURCE.mkdir(parents=True, exist_ok=True)
REVIEW.mkdir(parents=True, exist_ok=True)
assert hashlib.sha256(BRIDGE.read_bytes()).hexdigest() == BRIDGE_SHA
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene
parts = []


def bpos(p):
    return Vector((p[0], -p[2], p[1]))


def godot(p):
    return [float(p.x), float(p.z), float(-p.y)]


def collection(name):
    c = bpy.data.collections.new(name)
    scene.collection.children.link(c)
    return c


model = collection('T03A_EDITABLE_MAIN_FORM')
studio = collection('STUDIO_NOT_ASSET')
bridge_collection = collection('READ_ONLY_ROOT_ARCH_ASSEMBLY')
root = bpy.data.objects.new('F1ShoreRoot_T03A', None)
model.objects.link(root)
root['status'] = 'basic-colour main-form study, not runtime asset'
root['world_position_godot'] = [-24.5, 0.0, -6.0]
root['reference_sha256'] = '5a5dace7fd687b6226cc68a7c9094f3050f6ef8c378252c32ee9a06ae30f5859'


def material(name, colour, roughness=0.87):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*colour, 1)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = (*colour, 1)
    shader.inputs['Roughness'].default_value = roughness
    shader.inputs['Specular IOR Level'].default_value = 0.23
    return mat


# Deliberately broad colour blocks. No fine noise, cracks or pretend final PBR.
stone = [material('Study_Stone_Cool', (.27, .285, .29)),
         material('Study_Stone_LightCut', (.34, .345, .33)),
         material('Study_Stone_Shadow', (.21, .235, .245)),
         material('Study_Stone_WarmFace', (.34, .315, .27))]
soil = [material('Study_Earth', (.235, .205, .153)),
        material('Study_WetSediment', (.13, .155, .15))]
bark = [material('Study_Bark_Base', (.265, .185, .113)),
        material('Study_Bark_LargePlane', (.34, .255, .16)),
        material('Study_Bark_Shadow', (.17, .13, .095))]
moss = material('Study_Moss_Patches', (.22, .265, .11))


def mesh(name, vertices, faces, materials, role, indices=None):
    data = bpy.data.meshes.new(name + '_EditableMesh')
    data.from_pydata([bpos(v) for v in vertices], [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    model.objects.link(obj)
    obj.parent = root
    obj['role'] = role
    for mat in materials:
        data.materials.append(mat)
    if indices:
        for poly, index in zip(data.polygons, indices):
            poly.material_index = index
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode='OBJECT')
    obj.select_set(False)
    parts.append(obj)
    return obj


def wedge_height(x, z):
    rise = max(0.0, min(1.0, (x + 4.5) / 8.2))
    height = .25 + 3.92 * rise
    # Flatter receiving land is functional, broken side shoulders are below it.
    height -= max(0.0, abs(z) - 2.65) * (.24 + .22 * rise)
    # A genuine trough at the southwest wet margin; it exits the west boundary.
    if x < .3 and z > 3.2:
        trough = math.exp(-((z - 4.55) / .5) ** 2)
        height = height * (1 - .87 * trough)
    return max(.08, height)


# A closed solid earth/rock matrix under the separate stone and root pieces.
# Unequal outline samples avoid an oval slab or a straight rectangular bank.
rows = [(-5.9, -2.8, 3.3), (-5.1, -3.8, 4.0), (-3.8, -4.25, 4.5),
        (-2.75, -4.5, 4.5), (-1.25, -4.3, 4.5), (.4, -4.5, 4.5),
        (1.8, -4.25, 4.5), (2.85, -4.5, 4.5), (3.5, -4.4, 4.3),
        (4.1, -4.5, 3.7), (4.55, -4.5, 3.2), (5.05, -4.4, 2.5),
        (5.75, -3.5, 1.2)]
columns = 10
vertices, faces, ids = [], [], []
for z, left, right in rows:
    for column in range(columns):
        t = column / (columns - 1)
        x = left + (right - left) * t
        vertices.append((x, max(.05, wedge_height(x, z) - .09), z))
top_count = len(vertices)
vertices += [(x, 0.0, z) for x, y, z in vertices]
for row in range(len(rows) - 1):
    for col in range(columns - 1):
        a = row * columns + col
        faces.extend([(a, a + 1, a + columns + 1), (a, a + columns + 1, a + columns)])
        ids.extend([int(rows[row][0] >= 4.1 and col < 6)] * 2)
        faces.append((a + top_count, a + columns + top_count,
                      a + columns + 1 + top_count, a + 1 + top_count))
        ids.append(0)
outline = list(range(columns))
outline += [r * columns + columns - 1 for r in range(1, len(rows))]
outline += list(range(top_count - 2, top_count - columns - 1, -1))
outline += [r * columns for r in range(len(rows) - 2, 0, -1)]
for i, a in enumerate(outline):
    b = outline[(i + 1) % len(outline)]
    faces.append((a, b, b + top_count, a + top_count))
    ids.append(0)
mesh('GroundMatrix_Continuous_WetGully', vertices, faces, soil, 'solid supporting matrix', ids)


def rock(name, center, extents, seed, top_height=None, end_join=False):
    """Three-ring fractured stone; top faces remain broad, not full noise."""
    rng = random.Random(seed)
    cx, cy, cz = center
    sx, sy, sz = extents
    perimeter = [(-.49, -.31), (-.32, -.5), (.30, -.5), (.5, -.29),
                 (.5, .32), (.28, .5), (-.34, .5), (-.5, .27)]
    verts = []
    for ring, factor in enumerate((.82, 1.0, .90)):
        for j, (px, pz) in enumerate(perimeter):
            dx = px * sx * factor
            dz = pz * sz * factor
            xx = min(4.5, cx + dx + (rng.random() - .5) * .12)
            zz = cz + dz + (rng.random() - .5) * .13
            if ring == 0:
                yy = max(0.0, cy - sy / 2)
            elif ring == 1:
                yy = cy + sy * .24 + (rng.random() - .5) * sy * .08
            else:
                yy = top_height if top_height is not None else cy + sy / 2
                yy += (rng.random() - .5) * (.04 if end_join else .13)
            verts.append((xx, yy, zz))
    fs = [tuple(reversed(range(8))), tuple(range(16, 24))]
    mat_ids = [2, 1]
    for k in range(2):
        for j in range(8):
            fs.append((k * 8 + j, k * 8 + (j + 1) % 8,
                       (k + 1) * 8 + (j + 1) % 8, (k + 1) * 8 + j))
            mat_ids.append((0, 2, 0, 3, 0, 1, 0, 2)[(j + seed) % 8])
    return mesh(name, verts, fs, stone, 'individually editable structural stone', mat_ids)


# Unequal large stone blocks form a broken continuous bank. These are not props
# sprinkled onto a smooth slab, and their bottoms penetrate the ground matrix.
rock('Receiving_Limestone_East', (3.12, 2.65, -.05), (3.45, 3.6, 6.85), 17, 4.44, True)
rock('Middle_Ledge_North', (.0, 1.75, -1.85), (3.7, 3.35, 4.9), 31, 3.38)
rock('Middle_Ledge_South', (.5, 1.25, 2.45), (3.2, 2.4, 3.9), 62, 2.60)
rock('Buried_Foot_West', (-2.5, .52, -.55), (3.7, 1.05, 5.0), 92, 1.05)
rock('North_Fracture_Lower', (-1.55, .8, -4.35), (3.6, 1.6, 2.7), 116, 1.66)
rock('North_Fracture_Upper', (2.3, 2.2, -4.0), (3.8, 3.75, 2.7), 123, 4.28)
rock('South_Ledge_Toe', (-.75, .55, 4.12), (2.15, 1.1, 1.0), 141, 1.12)
rock('South_Forefoot_Fracture', (-2.5, .26, 5.1), (2.4, .52, 1.2), 160, .57)
rock('East_South_Shoulder', (3.35, 1.35, 3.93), (1.9, 2.7, 2.35), 180, 2.75)


def path_volume():
    # A thick earth/stone ramp seats in the matrix and stones, not a floating lid.
    xs = [-4.3, -3.35, -2.2, -1.1, .2, 1.15, 2.3, 3.5, 4.5]
    heights = [.34, .88, 1.44, 2.02, 2.75, 3.45, 4.43, 4.5, 4.5]
    zs = [-2.75, -1.65, 0, 1.6, 2.75]
    vs, fs, mi = [], [], []
    for i, x in enumerate(xs):
        for z in zs:
            # Exact join; central ramp avoids ledges. Soil penetrates all supports.
            yy = heights[i] + (0 if i >= 7 else .045 * math.sin(z * 1.25 + i * .65))
            vs.append((x, yy, z))
    n = len(vs)
    vs += [(x, max(0.05, y - .65), z) for x, y, z in vs]
    for i in range(len(xs) - 1):
        for j in range(len(zs) - 1):
            a = i * len(zs) + j
            fs.append((a, a + 1, a + 1 + len(zs), a + len(zs)))
            mi.append(0)
            fs.append((a+n, a+len(zs)+n, a+1+len(zs)+n, a+1+n))
            mi.append(0)
    edge = list(range(len(zs)))
    edge += [i * len(zs) + len(zs) - 1 for i in range(1, len(xs))]
    edge += list(range(n - 2, n - len(zs) - 1, -1))
    edge += [i * len(zs) for i in range(len(xs)-2, 0, -1)]
    for i, a in enumerate(edge):
        b = edge[(i+1)%len(edge)]
        fs.append((a,b,b+n,a+n)); mi.append(0)
    return mesh('Thick_Path_Receiving_Ramp',vs,fs,[soil[0]],'5.5m receiving route with 0.65m soil depth',mi)


path_volume()


def root_branch(name, stations, seed):
    """Non-circular, varying width root with large cross-section plane changes.

    A station is (x, y, z, width, thickness). A short sequence deliberately
    defines kinks and swelling instead of a constant-width perfect pipe.
    """
    rng = random.Random(seed)
    vs, fs, indices = [], [], []
    n = 10
    for i, (x,y,z,width,thickness) in enumerate(stations):
        prev = Vector(stations[max(i-1,0)][:3])
        nxt = Vector(stations[min(i+1,len(stations)-1)][:3])
        tangent = (nxt-prev).normalized()
        side = tangent.cross(Vector((0,1,0))).normalized()
        up = side.cross(tangent).normalized()
        twist = .14 * math.sin(i * 1.8 + seed)
        for j in range(n):
            a = math.tau*j/n + twist
            r = 1 + .12*math.sin(j*2.3+i*.9+seed)
            p = Vector((x,y,z)) + side*(math.cos(a)*width*.5*r) + up*(math.sin(a)*thickness*.5*r)
            vs.append(tuple(p))
    fs.extend([tuple(reversed(range(n))),tuple((len(stations)-1)*n+j for j in range(n))])
    indices.extend([2,0])
    for i in range(len(stations)-1):
        for j in range(n):
            fs.append((i*n+j,i*n+(j+1)%n,(i+1)*n+(j+1)%n,(i+1)*n+j))
            indices.append(1 if j in (2,3,4) else (2 if j in (7,8) else 0))
    return mesh(name,vs,fs,bark,'editable broad load-bearing root',indices)


# One diagonal primary root, its unequal grounded fork, and one partly buried
# counter-root. None is a ring of vines around the outside of a rock pedestal.
root_branch('Primary_Root_Climbing_Into_Limestone', [
    (-3.85,.27,1.75,1.05,.38), (-3.15,.66,2.1,1.55,.65),
    (-2.3,1.12,2.3,1.7,.78), (-1.55,1.8,2.58,1.45,.85),
    (-.45,2.5,3.0,1.8,.85), (.55,3.0,3.18,1.8,.9),
    (1.55,3.72,3.15,1.55,.86), (2.45,4.2,3.24,1.65,.72),
    (3.35,4.34,3.4,1.35,.55), (4.15,4.31,3.37,.85,.37)],213)
root_branch('Primary_Fork_WetMargin', [
    (-2.35,1.14,2.38,1.2,.65), (-2.0,.85,3.15,1.0,.7),
    (-1.45,.72,3.85,.82,.57), (-1.15,.58,4.5,.68,.45),
    (-.7,.28,5.32,.38,.27)],217)
root_branch('StoneBound_CounterRoot_North', [
    (-3.3,.35,-3.15,.6,.36),(-2.4,.84,-3.45,.76,.47),
    (-1.4,1.7,-3.66,.95,.57),(-.2,2.78,-3.75,1.1,.65),
    (.8,3.62,-3.62,1.22,.7),(1.75,4.31,-3.42,1.0,.57),
    (2.65,4.48,-3.56,.6,.33)],311)
root_branch('Buried_Splay_At_WestToe', [
    (-2.6,.78,2.1,.9,.52),(-3.25,.48,1.35,.8,.46),
    (-3.88,.22,.45,.49,.25),(-4.35,.11,-.2,.24,.16)],313)


# Shallow stone remnants are limited to the route margins. These colour-block
# accents give the use surface a material hierarchy without fine decoration.
for i, spec in enumerate([
    ((3.8,4.43,-1.8),(1.15,.17,.72)), ((2.75,4.39,1.65),(.85,.18,.85)),
    ((.8,3.11,-2.05),(1.1,.21,.75)), ((-.7,2.21,.9),(.9,.15,.65)),
    ((-2.6,1.18,-1.8),(1.0,.17,.7)), ((-3.8,.52,.75),(.75,.14,.75))]):
    rock('Partly_Buried_Route_Stone_%02d'%i,spec[0],spec[1],410+i)


def build_bvh(objects):
    vs, fs = [], []
    for obj in objects:
        if obj.type != 'MESH':
            continue
        offset = len(vs)
        vs.extend(obj.matrix_world @ v.co for v in obj.data.vertices)
        fs.extend(tuple(offset+i for i in p.vertices) for p in obj.data.polygons)
    return BVHTree.FromPolygons(vs,fs), vs


bpy.context.view_layer.update()
solid_tree,_ = build_bvh(parts)
def top_at(x,z,tree=solid_tree):
    loc, normal, index, distance = tree.ray_cast(bpos((x,12,z)),Vector((0,0,-1)),14)
    return None if loc is None else float(loc.z)


# Thin, irregular patches conform to actual geometry. They are a main-colour
# study only, never a green layer that hides a missing shoulder or floating lid.
for k,(x,z,rx,rz) in enumerate([(-2.9,-3.8,.7,.35),(-.4,-3.0,.9,.23),
                               (2.45,-3.25,.8,.22),(.1,3.7,.55,.23),
                               (-2.8,5.15,.7,.18)]):
    verts=[]
    for j in range(10):
        a=math.tau*j/10
        rr=1+.19*math.sin(j*2.6+k)
        xx=x+rx*rr*math.cos(a);zz=z+rz*rr*math.sin(a)
        yy=top_at(xx,zz)
        if yy is not None:verts.append((xx,yy+.009,zz))
    if len(verts)>=3:mesh('Moss_Colour_Study_%02d'%k,verts,[tuple(range(len(verts)))],[moss],'visual-only thin study colour')


markers={'GroundOrigin':(0,0,0),'BridgeJoin':(4.5,4.5,0),'WestBlend':(-4.3,.34,0)}
for name,at in markers.items():
    obj=bpy.data.objects.new(name,None);model.objects.link(obj);obj.parent=root
    obj.location=bpos(at);obj.empty_display_type='PLAIN_AXES';obj.empty_display_size=.45
    obj['godot_local_metres']=list(at)


def move_to(obj,target):
    for c in list(obj.users_collection):c.objects.unlink(obj)
    target.objects.link(obj)


# Native Blender GLB importer reads the actual frozen bridge. It is not modified
# on disk. All imports are placed in a conspicuously labelled reference collection.
before=set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=str(BRIDGE))
imported=[o for o in bpy.data.objects if o not in before]
for obj in imported:move_to(obj,bridge_collection)
for obj in imported:
    if obj.parent not in imported:
        obj.location += bpos((24.5,0,0))
    obj['read_only_assembly_reference']=True
bpy.context.view_layer.update()
bridge_tree,bridge_vertices=build_bvh(imported)

join_samples=[]
for z in [-2.65,-1.8,0,1.8,2.65]:
    shoulder_y=top_at(4.48,z)
    bridge_y=top_at(4.52,z,bridge_tree)
    join_samples.append({'z':z,'shoulder_y':shoulder_y,'actual_bridge_y':bridge_y,
                         'step_m':None if bridge_y is None or shoulder_y is None else bridge_y-shoulder_y})
route_samples=[{'x':x,'z':z,'surface_y':top_at(x,z)}
               for x in [-3.9,-2.5,-1.0,.5,2.5,4.48] for z in [-2.65,0,2.65]]
gully_samples=[{'x':x,'cross_profile':[{'z':z,'y':top_at(x,z)} for z in [3.9,4.55,5.0]]}
               for x in [-3.6,-3.1]]
coordinates=[o.matrix_world@v.co for o in parts for v in o.data.vertices]
gcoords=[godot(p) for p in coordinates]
triangles=0
for obj in parts:obj.data.calc_loop_triangles();triangles+=len(obj.data.loop_triangles)
report={
    'asset':'T03-A F1 shore root', 'revision':REVISION, 'blender':bpy.app.version_string,
    'scope':'editable basic-colour main-form / native Blender BVH only; not exported or Godot verified',
    'reference_sha256':root['reference_sha256'], 'world_root_godot':[-24.5,0,-6],
    'markers_godot':markers, 'editable_meshes':len(parts), 'triangles':triangles,
    'bounds_godot':{'min':[min(v[k] for v in gcoords) for k in range(3)],
                    'max':[max(v[k] for v in gcoords) for k in range(3)]},
    'route_vertical_samples':route_samples,'actual_bridge_join_samples':join_samples,
    'gully_cross_profiles':gully_samples,
    'bridge_reference':{'path':str(BRIDGE),'sha256_before':BRIDGE_SHA,
                        'sha256_after':hashlib.sha256(BRIDGE.read_bytes()).hexdigest(),
                        'assembly_translation_godot':[24.5,0,0],
                        'imported_meshes':len([o for o in imported if o.type=='MESH'])},
    'geometry_checks':{
        'route_18_vertical_samples_all_supported':all(p['surface_y'] is not None for p in route_samples),
        'join_5_rays_hit_both_models':all(p['step_m'] is not None for p in join_samples),
        'join_max_abs_step_le_0_12m':all(p['step_m'] is not None and abs(p['step_m'])<=.12 for p in join_samples),
        'wet_gully_depressed_both_sides':all(row['cross_profile'][1]['y'] is not None and all(
            row['cross_profile'][j]['y'] is not None and row['cross_profile'][j]['y']-row['cross_profile'][1]['y']>.12
            for j in [0,2]) for row in gully_samples),
        'frozen_bridge_unchanged':hashlib.sha256(BRIDGE.read_bytes()).hexdigest()==BRIDGE_SHA},
    'objects':[{'name':o.name,'role':o['role'],'vertices':len(o.data.vertices)} for o in parts],
    'limits':['No runtime GLB produced.','No Godot, actual vehicle sweep, camera or performance validation.',
              'Base colours only; no final UV/PBR material or baked textures.',
              'Route rays and gully cross profiles do not substitute for volume sweep or artistic approval.']}


def aim(obj,target):obj.rotation_euler=(bpos(target)-obj.location).to_track_quat('-Z','Y').to_euler()
def area(name,at,power,size,colour):
    data=bpy.data.lights.new(name,'AREA');data.energy=power;data.size=size;data.color=colour
    obj=bpy.data.objects.new(name,data);studio.objects.link(obj);obj.location=bpos(at);aim(obj,(0,2,0))
area('Study_Key',(-7,17,12),2100,10,(1,.95,.88))
area('Study_Fill',(13,12,-9),1600,12,(.84,.9,1))
area('Study_Rim',(-6,12,-12),1800,9,(1,.94,.82))
bpy.ops.mesh.primitive_plane_add(size=160,location=(0,0,-.045))
floor=bpy.context.object;floor.name='Studio_Ground_NOT_ASSET';move_to(floor,studio)
floor.data.materials.append(material('Studio_Neutral',(.235,.25,.26)))
camera_data=bpy.data.cameras.new('ReviewCamera')
camera=bpy.data.objects.new('ReviewCamera',camera_data);studio.objects.link(camera);scene.camera=camera
camera_data.type='ORTHO'
def view(at,target,scale):camera.location=bpos(at);aim(camera,target);camera_data.ortho_scale=scale
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=10;scene.cycles.use_denoising=True
scene.render.threads_mode='FIXED';scene.render.threads=2
scene.render.resolution_x=1280;scene.render.resolution_y=900;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'
scene.world.use_nodes=True
scene.world.node_tree.nodes.get('Background').inputs['Color'].default_value=(.3,.33,.36,1)
scene.world.node_tree.nodes.get('Background').inputs['Strength'].default_value=.45
scene.view_settings.view_transform='AgX';scene.view_settings.look='AgX - Medium High Contrast'
bridge_collection.hide_render=True
bridge_collection.hide_viewport=True
view((15,16,20),(0,2.1,0),16.4)
source_path=SOURCE/('f1_shore_root_'+REVISION+'.blend')
scene['review_scope']='basic-colour offline study; actual bridge reference hidden in separate collection'
scene['geometry_report']=json.dumps(report,ensure_ascii=False)
bpy.ops.wm.save_as_mainfile(filepath=str(source_path))
report['source']={'path':str(source_path),'bytes':source_path.stat().st_size,
                  'sha256':hashlib.sha256(source_path.read_bytes()).hexdigest()}
(REVIEW/('geometry_'+REVISION+'.json')).write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('SHORE_ROOT_GEOMETRY '+json.dumps(report['geometry_checks']))
if '--render' in sys.argv:
    scene.render.filepath=str(REVIEW/('01-default-oblique-'+REVISION+'.png'))
    bpy.ops.render.render(write_still=True)
    bridge_collection.hide_render=False;bridge_collection.hide_viewport=False
    # The second camera shows the actual west-end seam, not a fabricated bridge.
    view((-13,17,23),(4.1,3.25,0),23.5)
    scene.render.filepath=str(REVIEW/('02-bridge-assembly-offline-'+REVISION+'.png'))
    bpy.ops.render.render(write_still=True)
assert hashlib.sha256(BRIDGE.read_bytes()).hexdigest()==BRIDGE_SHA
print('SHORE_ROOT_MAIN_FORM_DONE '+str(source_path))
