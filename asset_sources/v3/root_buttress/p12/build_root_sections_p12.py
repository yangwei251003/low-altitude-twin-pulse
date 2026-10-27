"""P12 root-only section restoration. Frozen P11 rock/Sap/anchors unchanged."""
import bpy, bmesh, math, json, hashlib, struct, sys
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
SOURCE = HERE.parent / 'p11/root_buttress_h10_complete_p11.blend'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
SOURCE_SHA = 'b5ec56780e72dc12edc40b1651c518e12ed68e6243b62a50a0415ef0bb8f960c'
P11_GLB = ROOT / 'assets/v3/candidates/root_buttress_h10_p11/root_buttress_h10_p11.glb'
P11_SHA = 'd8e67fdaef057a9adb9fb10545eda90d867d730cb446511f735cfbd42d486f1f'
assert sha(SOURCE) == SOURCE_SHA and sha(P11_GLB) == P11_SHA
runtime = json.loads((HERE.parent / 'p11/p11_source_report.json').read_text(encoding='utf-8'))['runtime_P2_sha256']
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
root = bpy.data.objects['RootButtress']
body = bpy.data.objects['RockMasses']
sap = bpy.data.objects['SapKnot']
col = bpy.data.collections['Editable_RootButtress']
anchors = {n: bpy.data.objects[n] for n in ['GroundOrigin', 'BodyPerch', 'HostTarget', 'LowerShelf']}
def bp(p): return Vector((p[0], -p[2], p[1]))
def gp(p): return Vector((p.x, p.z, -p.y))

def digest(ob):
    h = hashlib.sha256()
    h.update(struct.pack('<16d', *(v for row in ob.matrix_world for v in row)))
    if ob.type == 'MESH':
        for v in ob.data.vertices: h.update(struct.pack('<3d', *v.co))
        for f in ob.data.polygons: h.update(struct.pack('<' + str(len(f.vertices)) + 'I', *f.vertices))
        for layer in ob.data.uv_layers:
            h.update(layer.name.encode())
            for v in layer.data: h.update(struct.pack('<2d', *v.uv))
    return h.hexdigest()

fixed = {o.name: digest(o) for o in [body, sap, *anchors.values()]}

def tree(items):
    vs, fs = [], []
    for ob in items:
        ob.data.calc_loop_triangles()
        off = len(vs)
        vs.extend(ob.matrix_world @ v.co for v in ob.data.vertices)
        fs.extend(tuple(off + i for i in f.vertices) for f in ob.data.loop_triangles)
    return BVHTree.FromPolygons(vs, fs, all_triangles=True)

def clean(ob):
    bm = bmesh.new(); bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-6)
    bmesh.ops.dissolve_degenerate(bm, edges=list(bm.edges), dist=1e-7)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(ob.data); bm.free(); ob.data.update()

bpy.context.view_layer.update()
rock_bvh = tree([body])

def wall_depth(side, u, y):
    origin, direction, component, fallback = ((u, y, 9), (0, 0, -1), 2, 4.5) if side == 'front' else ((9, y, u), (-1, 0, 0), 0, 4.8)
    hit = rock_bvh.ray_cast(bp(origin), bp(direction), 18)
    if hit[0] is None: return fallback
    value = gp(hit[0])[component]
    return value if value >= 2 else fallback

fork = bpy.data.objects['Original_ClippedFork_LocalCoordinates']
original = [gp(v.co) for v in fork.data.vertices]
raw_bounds = {'min': [min(p[k] for p in original) for k in range(3)], 'max': [max(p[k] for p in original) for k in range(3)]}
bark = bpy.data.objects['Root_FrontSap'].data.materials[0]
for name in ['Root_FrontSap', 'Root_RightFork']:
    bpy.data.objects.remove(bpy.data.objects[name], do_unlink=True)

# Restore the wall-normal section while slightly reducing lateral fork breadth.
# This is not an all-axis scaling: length/height and material recipe remain P11.
specs = [
    dict(name='Root_FrontSap', side='front', scale=3.9, top=10.9, offset=-.25, normal=.78, lateral=.90, old_normal=.34),
    dict(name='Root_RightFork', side='right', scale=3.3, top=9.2, offset=-.6, normal=.82, lateral=.88, old_normal=.36),
]
roots, adaptation = [], []
for spec in specs:
    ob = bpy.data.objects.new(spec['name'], fork.data.copy())
    col.objects.link(ob); ob.parent = root
    ob.data.materials.clear(); ob.data.materials.append(bark)
    for layer in list(ob.data.uv_layers): ob.data.uv_layers.remove(layer)
    uv = ob.data.uv_layers.new(name='RecipeUV'); uv.active_render = True
    for poly in ob.data.polygons:
        for li in poly.loop_indices:
            p = original[ob.data.loops[li].vertex_index]
            uv.data[li].uv = (p.z * .33 + p.x * .17, p.y * .46)
    coords = []
    for p in original:
        u = -p.z * spec['scale'] * spec['lateral'] + spec['offset']
        y = spec['top'] - (p.y - .1) * spec['scale']
        # A 20cm soft wall reference follows geological relief, not each fine face.
        surface = (wall_depth(spec['side'], u, y) * 2 + wall_depth(spec['side'], u-.20, y) + wall_depth(spec['side'], u+.20, y)) / 4
        tip = max(0, min(1, (p.y - 2.03) / .17))
        bury = -.40 + 1.15 * (tip * tip * (3 - 2 * tip))
        if spec['side'] != 'front': bury += .50 * max(0, min(1, (.32-p.y) / .22))
        thickness = (p.x + .10) * spec['scale'] * spec['normal']
        # Restore depth asymmetrically: preserve native grooves, soften the small
        # planar cut shoulder without flattening the whole section again.
        thickness += .06 * math.sin(p.y * 2.4 + p.z * 1.8) * math.cos(p.x * 2.1)
        if spec['side'] == 'front':
            t = max(0, min(1, (y-9.1) / 1.8)); surface = surface*(1-t) + 4.05*t
        coords.append([u, y, surface-bury+thickness])
    # Root may extend +0.35m beyond prior positive X/Z bounds. Do not bury
    # whole sections to force the former conservative box. Only the authored
    # small end taper above enters the rock; the root section stays full.
    for v, q in zip(ob.data.vertices, coords):
        u, y, depth = q
        v.co = bp((u,y,depth) if spec['side']=='front' else (depth,y,u))
    clean(ob)
    bpy.context.view_layer.objects.active = ob
    mod = ob.modifiers.new('P12_NaturalForkModerateRetopology', 'DECIMATE')
    mod.ratio = .60; mod.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=mod.name); clean(ob)
    for f in ob.data.polygons: f.use_smooth = True
    ob['source'] = 'frozen P11 clipped natural fork; original Island Tree 01 wood primitive'
    ob['adaptation'] = 'restored normal section; continuous main fork lightly exposed; only last 0.17 source m enters rock; no section translation for bounds'
    adaptation.append({**spec, 'normal_restoration_multiplier':spec['normal']/spec['old_normal'], 'main_bury':-.40,'tip_source_interval':[2.03,2.2],'boundary_driven_translation':False, 'original_source_godot_axes_bounds':raw_bounds})
    roots.append(ob)

bpy.context.view_layer.update()
static, sap_bvh, root_bvh = tree([body,*roots]), tree([sap]), tree(roots)
checks = []
def check(name, ok, detail=None): checks.append({'name':name,'pass':bool(ok),'detail':detail})
def topology(ob):
    bm = bmesh.new(); bm.from_mesh(ob.data)
    result = {'boundary_edges':sum(e.is_boundary for e in bm.edges), 'nonmanifold_edges':sum(not e.is_manifold for e in bm.edges), 'signed_volume':bm.calc_volume(signed=True)}
    left = set(bm.verts); counts=[]
    while left:
        stack=[left.pop()]; count=0
        while stack:
            v=stack.pop(); count+=1
            for e in v.link_edges:
                w=e.other_vert(v)
                if w in left: left.remove(w); stack.append(w)
        counts.append(count)
    result['components']=counts; bm.free(); return result
for ob in [body,*roots]:
    t=topology(ob)
    check(ob.name+'_closed_one_component', t['boundary_edges']==0 and t['nonmanifold_edges']==0 and len(t['components'])==1 and t['signed_volume']>0, t)
feet=[(-2.54,2.17),(2.51,2.22),(-2.28,-2.5),(2.31,-2.48)]
for i,(x,z) in enumerate(feet):
    points=[(x,z)]+[(x+r*math.cos(a*math.tau/64), z+r*math.sin(a*math.tau/64)) for r in [.25,.5,.75] for a in range(64)]
    bad=[]
    for a,b in points:
        hit=static.ray_cast(bp((a,15,b)),bp((0,-1,0)),18)
        p=list(gp(hit[0])) if hit[0] else None
        if p is None or abs(p[1]-10)>.001: bad.append({'xz':[a,b],'hit':p})
    check(f'foot_{i}_193_Y10',not bad,{'probes':len(points),'failures':bad})
lower=[]
for dx,dz in [(0,0),(-.25,0),(.25,0),(0,-.25),(0,.25)]:
    h=static.ray_cast(bp((-3.7+dx,6,3.2+dz)),bp((0,-1,0)),2)
    lower.append(list(gp(h[0])) if h[0] else None)
check('LowerShelf_5_points_Y5', all(h and abs(h[1]-5)<.001 for h in lower),lower)
target=bp((0,11,4.5))
for i,o in enumerate([(0,11,8),(-3,12,8),(3,12,8)]):
    origin=bp(o); direction=target-origin
    sh=sap_bvh.ray_cast(origin,direction.normalized(),direction.length+1)
    rh=static.ray_cast(origin,direction.normalized(),direction.length+1)
    check('Sap_LOS_'+str(i),sh[0] is not None and (rh[0] is None or rh[3]>sh[3]+.01),{'sap_distance':sh[3],'solid_distance':rh[3]})
nearest=root_bvh.find_nearest(target)
delta=gp(nearest[0])-Vector((0,11,4.5)) if nearest[0] else Vector((100,100,100))
ellipsoid=(delta.x/.57)**2+(delta.y/.78)**2+(delta.z/.4)**2
check('living_root_enters_Sap_volume',ellipsoid<.93,{'closest':list(gp(nearest[0])) if nearest[0] else None,'ellipsoid':ellipsoid})
parts=[body,*roots,sap]
points=[gp(ob.matrix_world@v.co) for ob in parts for v in ob.data.vertices]
bounds={'min':[min(p[k] for p in points) for k in range(3)],'max':[max(p[k] for p in points) for k in range(3)]}
lo=[-6.610198020935059,0,-6.804511547088623]; hi=[6.905734539031982,11.93212890625,6.879329681396484]
authorized_hi=[hi[0]+.35,hi[1],hi[2]+.35]
extension={'old_min':lo,'old_max':hi,'authorized_max':authorized_hi,'actual':bounds,'actual_positive_extension':[max(0,bounds['max'][k]-hi[k]) for k in range(3)]}
check('authorized_root_positive_xz_extension_bounds',all(bounds['min'][k]>=lo[k]-.0001 and bounds['max'][k]<=authorized_hi[k]+.0001 for k in range(3)),extension)
check('Rock_Sap_and_4_anchors_unchanged',fixed=={ob.name:digest(ob) for ob in [body,sap,*anchors.values()]})
check('P11_source_and_candidate_unchanged',sha(SOURCE)==SOURCE_SHA and sha(P11_GLB)==P11_SHA)
check('runtime_P2_frozen',all(sha(ROOT/f'assets/v3/root_buttress/root_buttress_h{h}.glb')==v for h,v in runtime.items()))
stats=[]
for ob in parts:
    ob.data.calc_loop_triangles(); stats.append({'name':ob.name,'triangles':len(ob.data.loop_triangles),'vertices':len(ob.data.vertices)})
scene.render.engine='CYCLES'; scene.cycles.device='CPU'; scene.cycles.samples=8; scene.cycles.use_denoising=True
scene.render.threads_mode='FIXED'; scene.render.threads=2
scene.render.resolution_x=1024; scene.render.resolution_y=800; scene.render.resolution_percentage=100
blend=HERE/'root_buttress_h10_root_sections_p12.blend'
bpy.ops.wm.save_as_mainfile(filepath=str(blend))
report={'stage':'P12 root-section-only source; no bake or GLB', 'source_sha256':sha(blend),'input_P11_source_sha256':SOURCE_SHA,'fixed_geometry_uv_transform_hashes':fixed,'root_adaptation_specs':adaptation,'stats':stats,'bounds_godot':bounds,'authorized_bounds':extension,'runtime_P2_sha256':runtime,'anchors_godot':{n:list(gp(ob.matrix_world.translation)) for n,ob in anchors.items()},'checks':checks,'passed':sum(c['pass'] for c in checks),'total':len(checks),'all_pass':all(c['pass'] for c in checks),'limits':['basic material source preview only; no GLB, actual camera or final artistic approval','772 foot probes do not replace full-Crown sweep','restored root thickness needs actual oblique image review']}
(HERE/'p12_source_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('P12_SOURCE '+json.dumps(report,ensure_ascii=False),flush=True)
assert report['all_pass'],'Concrete geometry failure: stop before render'
if '--render' in sys.argv:
    scene.render.filepath=str(HERE/'h10_p12_root_sections_source.png'); bpy.ops.render.render(write_still=True)
print('P12_SOURCE_DONE',flush=True)
