"""West short stone/root approach, editable FORM REVIEW p1, not runtime art.

Blender 5.2 bundled Python only. From project root:
  blender --background --factory-startup --threads 2 --python-exit-code 1
    --python asset_sources/v3/growth_approach/west_p1/build_west_approach.py
    -- [--no-render]

Writes ONLY beside this script. No GLB, baking, Godot import, shared helpers,
source-asset mutation or runtime output. Geometry coordinates are specified in
Godot local metres then converted to Blender (x,-z,y). World placement is
(-14.5,0,25); model root remains identity. Source JSON is the height authority.
Single-view reference controls broad stone/root language, NOT measured sizes.
"""
import bpy
import bmesh
import math
import json
import hashlib
import sys
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree

BASE = Path(__file__).resolve().parent
PROJECT = BASE.parents[3]
LAYOUT = PROJECT / 'data/v3/terrain/f1_growth_crossing.json'
REFERENCE = PROJECT / 'references/v3/production/growth_approach/growth_approach_west_reference_v2.png'
WORLD_ORIGIN = Vector((-14.5, 0.0, 25.0))
DATA = json.loads(LAYOUT.read_text(encoding='utf-8-sig'))
WEST = next(p for p in DATA['approaches'] if p['id'] == 'west')
SECTIONS = [(s['x'] + 14.5, [(p[0]-25.0, p[1]) for p in s['top_zy']]) for s in WEST['sections']]
BASE.mkdir(parents=True, exist_ok=True)
NO_RENDER = '--no-render' in sys.argv

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def bl(p):
    return Vector((p[0], -p[2], p[1]))

def gd(p):
    return Vector((p[0], p[2], -p[1]))

def top_height(x, z):
    """Identical diagonal and piecewise planar interpolation to _quad in JSON consumer."""
    x = max(0.0, min(3.75, float(x)))
    z = max(-1.5, min(1.5, float(z)))
    for i in range(len(SECTIONS)-1):
        xa, a = SECTIONS[i]
        xb, b = SECTIONS[i+1]
        if x <= xb + 1e-8:
            tx = (x-xa)/(xb-xa)
            for j in range(len(a)-1):
                za, ha = a[j]
                zb, hd = a[j+1]
                if z <= zb + 1e-8:
                    tz = (z-za)/(zb-za)
                    hb, hc = b[j][1], b[j+1][1]
                    if tx >= tz:
                        return ha + tx*(hb-ha) + tz*(hc-hb)
                    return ha + tx*(hc-hd) + tz*(hd-ha)
    raise AssertionError((x, z))

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene
scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1.0
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 16
scene.cycles.use_denoising = True
scene.render.threads_mode = 'FIXED'
scene.render.threads = 2
scene.render.resolution_x = 1000
scene.render.resolution_y = 1000
scene.render.resolution_percentage = 100
scene.view_settings.view_transform = 'AgX'
scene.view_settings.look = 'AgX - Medium High Contrast'
scene.render.image_settings.file_format = 'PNG'
scene.world.use_nodes = True
scene.world.node_tree.nodes['Background'].inputs[0].default_value = (.24,.27,.29,1)
scene.world.node_tree.nodes['Background'].inputs[1].default_value = .45
model = bpy.data.collections.new('EDITABLE_WEST_P1')
scene.collection.children.link(model)
studio = bpy.data.collections.new('OFFLINE_STUDIO_NOT_ASSET')
scene.collection.children.link(studio)
root = bpy.data.objects.new('GrowthApproachWest', None)
model.objects.link(root)
root['world_origin_godot'] = list(WORLD_ORIGIN)
root['status'] = 'form_candidate_not_baked_not_exported_not_game_accepted'
root['reference_sha256'] = sha(REFERENCE)
root['layout_sha256'] = sha(LAYOUT)
objects = []
rocks = []

def material(name, color, rough=.86):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = (*color, 1)
    p.inputs['Roughness'].default_value = rough
    return m

# Basic grouped materials intentionally omit fine texture: assess shape first.
STONE = material('P1_Stone_WarmGrey', (.34,.315,.267))
STONE_LIGHT = material('P1_Stone_WideCut', (.43,.405,.345))
STONE_COOL = material('P1_Stone_Recess', (.235,.253,.244))
BARK = material('P1_Root_Main', (.205,.123,.064))
BARK_LIGHT = material('P1_Root_FibrePlane', (.265,.169,.09))
MOSS = material('P1_Moss_SeamsOnly', (.18,.225,.071), .98)

def mesh_object(name, vertices_gd, faces, materials, collision=True):
    me = bpy.data.meshes.new(name + '_EditableMesh')
    me.from_pydata([bl(p) for p in vertices_gd], [], faces)
    me.update()
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    model.objects.link(ob)
    ob.parent = root
    for mat in materials:
        me.materials.append(mat)
    ob['collision_source'] = 'same_visible_triangles' if collision else 'thin_non_bearing_detail'
    ob['source'] = 'authored_profile_sculpt_from_approved_single_object_reference'
    objects.append(ob)
    return ob

# One continuous profiled mantle: exact top, broad angled side facets, an inset
# lower footprint. This is a real surface, NOT a full invisible rectangular box.
verts = []
top_ids = []
for x, row in SECTIONS:
    ids = []
    for z, y in row:
        ids.append(len(verts))
        verts.append((x,y,z))
    top_ids.append(ids)
faces = []
for i in range(3):
    for j in range(4):
        a,b,c,d = top_ids[i][j],top_ids[i+1][j],top_ids[i+1][j+1],top_ids[i][j+1]
        faces.extend([(a,b,c),(a,c,d)])
# Clockwise top perimeter when viewed in XZ. Several side corners are intentionally
# pulled in at different heights; their broad planes form the rock's mass.
rim = top_ids[0][:] + [top_ids[i][-1] for i in range(1,4)] + list(reversed(top_ids[-1][:-1])) + [top_ids[i][0] for i in (2,1)]
previous = rim
for level, frac in enumerate((.89,.56,.27,0.0)):
    current = []
    for k, idx in enumerate(rim):
        x, y, z = verts[idx]
        px,pz = x,z
        # Buried west join stays at local x=0; east taper and faceted faces never
        # extend outside the hard contract. Values are deterministic sculpt data.
        if x > 3.49:
            px -= (.08,.32,.19,.40)[level] * (1.0+.23*math.sin(k*1.7))
        elif x > .001:
            px += (.045,-.095,.07,-.035)[level]*math.sin(k*1.27+.2)
        if abs(z)>1.49:
            inset=(.07,.27,.16,.10)[level]*(1.0+.32*math.sin(k*1.6+.8))
            pz -= math.copysign(inset,z)
        elif x>3.49:
            pz *= (1.0,.93,.9,.94)[level]
        # Deeper two broad concavities on the visible south wall, actual geometry.
        if z>1.49 and level in (1,2) and .9<x<3.6:
            pz -= .13 if level==1 else .06
        current.append(len(verts))
        verts.append((max(0.,min(3.75,px)), y*frac, max(-1.5,min(1.5,pz))))
    for k in range(len(rim)):
        kk=(k+1)%len(rim)
        # Avoid a uniform checkerboard; alternating broad quads and irregular cuts.
        if (k+level)%3==0:
            faces.extend([(previous[k],current[k],current[kk]),(previous[k],current[kk],previous[kk])])
        else:
            faces.append((previous[k],current[k],current[kk],previous[kk]))
    previous=current
faces.append(tuple(reversed(previous)))
core = mesh_object('Stone_ContinuousShoulder', verts, faces, [STONE,STONE_LIGHT,STONE_COOL])
rocks.append(core)
for poly in core.data.polygons:
    n=gd(poly.normal)
    if n.y>.6: poly.material_index=1
    elif n.y<-.1 or poly.index%17==8: poly.material_index=2
    else: poly.material_index=0

def relief_rock(name, cx, cy, cz, sx, sy, sz, phase):
    """A thick irregular stone lobe intersecting the continuous mantle, not a tile."""
    vv=[]
    # The asymmetrical octagonal footprint is offset/rotated across height.
    for ring,(t,scale,shiftx,shiftz) in enumerate(((0,.70,-.09,-.04),(.16,1,.0,.0),(.78,.90,.08,-.03),(1,.58,.04,-.08))):
        for j in range(7):
            a=2*math.pi*j/7 + phase + .035*ring
            variation=1+.10*math.sin(j*2.7+phase)
            x=cx+sx*.5*scale*math.cos(a)*variation+shiftx
            z=cz+sz*.5*scale*math.sin(a)*variation+shiftz
            y=cy+sy*t
            vv.append((max(.015,min(3.72,x)),min(top_height(x,z)-.12,max(0,y)),max(-1.49,min(1.49,z))))
    ff=[]
    for r in range(3):
        for j in range(7):
            q=(j+1)%7
            ff.append((r*7+j,r*7+q,(r+1)*7+q,(r+1)*7+j))
    ff += [tuple(reversed(range(7))),tuple(range(21,28))]
    ob=mesh_object(name,vv,ff,[STONE,STONE_LIGHT,STONE_COOL])
    for p in ob.data.polygons:
        p.material_index=1 if gd(p.normal).y>.35 else (2 if p.index in (3,10,19) else 0)
    rocks.append(ob)
    return ob

# Three unequal geological masses; no repeating brick rows or separate pedestal.
relief_rock('Stone_LowSouthToe', .68,.0,1.18,1.42,1.95,.66,.32)
relief_rock('Stone_SouthObliqueCheek', 2.05,.82,1.19,1.66,3.20,.65,-.26)
relief_rock('Stone_EastBrokenNose', 3.31,.10,.24,.70,3.65,1.65,.13)

def bvh_for(obs):
    points=[]; tris=[]
    for ob in obs:
        ob.data.calc_loop_triangles()
        off=len(points)
        points += [ob.matrix_world@v.co for v in ob.data.vertices]
        tris += [tuple(off+i for i in t.vertices) for t in ob.data.loop_triangles]
    return BVHTree.FromPolygons(points,tris,all_triangles=True)

bpy.context.view_layer.update()
rock_bvh=bvh_for(rocks)

def project_surface(p, normal):
    """Project each root station onto actual edited rock, never onto a fake box."""
    p=Vector(p); normal=Vector(normal).normalized()
    start=bl(p+normal*2.2)
    hit, hn, fi, distance=rock_bvh.ray_cast(start,bl(-normal),5.0)
    if hit is None:
        raise AssertionError('Root support missing: '+str((tuple(p),tuple(normal))))
    return gd(hit), gd(hn)

def catmull(points, per=5):
    result=[]
    pp=[Vector(p) for p in points]
    for i in range(len(pp)-1):
        a,b,c,d=pp[max(0,i-1)],pp[i],pp[i+1],pp[min(len(pp)-1,i+2)]
        for j in range(per):
            t=j/per
            result.append((b*2+(c-a)*t+(a*2-b*5+c*4-d)*t*t+(-a+b*3-c*3+d)*t*t*t)*.5)
    result.append(pp[-1])
    return result

root_support=[]
def attached_root(name, control, width, thickness, side=1, fibre=False):
    samples=catmull(control,5)
    centers=[]; normals=[]
    for i,p in enumerate(samples):
        # A final explicit attribute controls blend from top to side projection.
        blend=max(0.,min(1.,p[3]))
        normal=Vector((0,1-blend,side*blend)).normalized()
        hit,hitnormal=project_surface(p[:3],normal)
        # Root is partially embedded. Tapered ends sink into real rock, rather
        # than ending in circular saw-cut caps hovering outside the surface.
        t=i/(len(samples)-1)
        taper=min(1.,t*8.,(1.-t)*8.)
        centers.append(hit+normal*(thickness*(.20 if taper>.7 else -.55)))
        normals.append(normal)
        root_support.append({'object':name,'sample':i,'support_godot':[round(v,6) for v in hit],'taper':taper})
    vv=[]
    for i,c in enumerate(centers):
        t=i/(len(centers)-1)
        tangent=(centers[min(i+1,len(centers)-1)]-centers[max(0,i-1)]).normalized()
        normal=normals[i]
        across=tangent.cross(normal).normalized()
        if across.length<.001: across=Vector((1,0,0))
        normal=across.cross(tangent).normalized()
        if normal.dot(normals[i])<0: normal=-normal
        taper=max(.025,min(1.,t*8.,(1.-t)*8.))
        # Long, broad irregular fibre planes, not high-frequency corrugation.
        w=width*taper*(1+.14*math.sin(t*8.5)+.09*math.sin(t*15.0+.4))
        h=thickness*taper*(1+.15*math.sin(t*10.0+1.2))
        for j in range(8):
            a=math.tau*j/8
            q=c+across*(w*math.cos(a))+normal*(h*math.sin(a))
            vv.append((max(.02,min(3.45,q.x)),min(5.245,max(.01,q.y)),max(-1.49,min(1.49,q.z))))
    ff=[]
    for i in range(len(centers)-1):
        for j in range(8):
            ff.append((i*8+j,i*8+(j+1)%8,(i+1)*8+(j+1)%8,(i+1)*8+j))
    ff += [tuple(reversed(range(8))),tuple(range((len(centers)-1)*8,len(centers)*8))]
    ob=mesh_object(name,vv,ff,[BARK,BARK_LIGHT])
    for p in ob.data.polygons:
        p.material_index=1 if p.index%8 in (1,2) and not fibre else 0
    ob['source']='continuous_surface_projected_root_bundle; authored from reference, not a cylinder primitive'
    return ob

def top_point(x,z):
    return (x,top_height(x,z),z,0.)

south=[top_point(.07,1.22),top_point(.55,1.20),top_point(1.20,1.16),top_point(1.85,1.24),top_point(2.45,1.16),
       (2.74,4.72,1.42,.65),(2.85,4.12,1.42,1),(2.66,3.38,1.42,1),(2.94,2.82,1.36,1)]
north=[top_point(.07,-1.16),top_point(.64,-1.23),top_point(1.27,-1.20),top_point(1.92,-1.23),top_point(2.48,-1.17),
       (2.71,4.65,-1.42,.7),(2.58,3.88,-1.42,1),(2.80,3.23,-1.36,1)]
attached_root('Root_Main_South',south,.235,.082,1)
attached_root('Root_Main_North',north,.215,.078,-1)
attached_root('Root_South_LateralBranch',[top_point(1.01,1.17),top_point(1.34,.98),top_point(1.68,.80),top_point(1.97,.69)],.105,.045,1)
attached_root('Root_North_LateralBranch',[top_point(.70,-1.20),top_point(.98,-.96),top_point(1.29,-.83),top_point(1.48,-.78)],.09,.039,-1)
# Two unequal smaller strands reinforce the main fibres, beginning and ending
# inside the parent bundle. They are not repeated parallel ropes all along it.
attached_root('Root_South_JoinedFibre',[top_point(.31,1.26),top_point(.87,1.31),top_point(1.48,1.30),top_point(1.75,1.25)],.065,.046,1,True)
attached_root('Root_North_JoinedFibre',[top_point(1.38,-1.30),top_point(1.82,-1.32),top_point(2.19,-1.24),top_point(2.43,-1.20)],.059,.043,-1,True)

# Moss is a small coherent strip at a damp root/stone junction, not scattered
# circles. Each strip follows real rock, with irregular feathered outline.
def moss_strip(name, control, widths, side):
    vv=[]
    for i,(p,w) in enumerate(zip(control,widths)):
        for sign in (-1,1):
            q=Vector(p);q.x+=sign*w*(.85+.15*math.sin(i*2.3))
            hit,n=project_surface(q,(0,0,side))
            vv.append(tuple(hit+Vector((0,0,side))*.006))
    ff=[]
    for i in range(len(control)-1):
        ff.append((i*2,i*2+1,i*2+3,i*2+2))
    ob=mesh_object(name,vv,ff,[MOSS],False)
    return ob

moss_strip('Moss_South_Recess',[(1.18,1.28,1.5),(1.28,1.80,1.5),(1.19,2.23,1.5),(1.36,2.69,1.5),(1.29,3.10,1.5)], [.015,.05,.036,.063,.012],1)
moss_strip('Moss_South_RootContact',[(2.60,3.13,1.5),(2.62,3.59,1.5),(2.72,3.93,1.5),(2.72,4.29,1.5)], [.018,.06,.047,.008],1)
moss_strip('Moss_North_Contact',[(1.48,2.11,-1.5),(1.43,2.59,-1.5),(1.57,3.10,-1.5),(1.50,3.52,-1.5)], [.01,.045,.05,.008],-1)

anchor_defs={'OuterJoin':(0,SECTIONS[0][1][2][1],0),'BridgeLip':(3.5,5.25,0),'InnerEnd':(3.75,5.20,0)}
for i,(z,y) in enumerate(SECTIONS[0][1]):
    anchor_defs['OuterJoin_'+str(i)]=(0,y,z)
for name,p in anchor_defs.items():
    ob=bpy.data.objects.new(name,None);model.objects.link(ob);ob.parent=root;ob.location=bl(p);ob.empty_display_size=.09
    ob['godot_local']=list(p);ob['world']=list(Vector(p)+WORLD_ORIGIN)

bpy.context.view_layer.update()
physical=[o for o in objects if o['collision_source']=='same_visible_triangles']
bvh=bvh_for(physical)
checks=[]
def check(name,ok,**values):
    checks.append({'name':name,'passed':bool(ok),**values})

def down(x,z,obs_bvh=bvh):
    hit,normal,face,d=obs_bvh.ray_cast(bl((x,8,z)),bl((0,-1,0)),10.)
    return gd(hit).y if hit is not None else None

all_points=[gd(o.matrix_world@v.co) for o in objects for v in o.data.vertices]
mins=[min(p[i] for p in all_points) for i in range(3)]
maxs=[max(p[i] for p in all_points) for i in range(3)]
check('all_visible_vertices_inside_hard_godot_local_bounds', all(mins[i]>=v-1e-5 for i,v in enumerate((0,0,-1.5))) and all(maxs[i]<=v+1e-5 for i,v in enumerate((3.75,5.25,1.5))),minimum=mins,maximum=maxs)
check('base_reaches_Y0',abs(mins[1])<1e-6)
for i,(z,y) in enumerate(SECTIONS[0][1]):
    got=down(.00001,z if abs(z)<1.5 else z*.999999)
    check('west_join_actual_surface_'+str(i),got is not None and abs(got-y)<.0001,expected=y,actual=got,z=z)
for name,x,expect in (('formal_bridge_lip',3.5,5.25),('recessed_inner_nose',3.749999,5.2)):
    for i in range(21):
        z=-1.49999+2.99998*i/20
        got=down(x,z)
        check(name+'_width_'+str(i),got is not None and abs(got-expect)<.0001,expected=expect,actual=got,z=z)
central_samples=[]
for ix in range(31):
    x=.001+3.748*ix/30
    for z in (-.85,0,.85):
        got=down(x,z)
        expected=top_height(x,z)
        central_samples.append({'x':x,'z':z,'expected':expected,'actual':got})
check('central_strip_has_no_new_railing_or_missing_surface',all(v['actual'] is not None and -.0002 <= v['actual']-v['expected'] <= .12 for v in central_samples),sample_count=len(central_samples),max_extra_height=max((v['actual']-v['expected'] for v in central_samples if v['actual'] is not None),default=-999))
check('light_segment_X_separation_at_least_0_5m',mins[0]+WORLD_ORIGIN.x>=-14.5-1e-6,west_world_x=mins[0]+WORLD_ORIGIN.x,light_endpoint_x=-15.)
check('root_identity_transform',root.matrix_basis.is_identity)
for ob in physical:
    bm=bmesh.new();bm.from_mesh(ob.data)
    bad=sum(1 for e in bm.edges if not e.is_manifold)
    degenerate=sum(1 for face in bm.faces if face.calc_area()<1e-10)
    bm.free()
    check('physical_mesh_closed_'+ob.name,bad==0,nonmanifold_edges=bad)
    check('physical_mesh_nondegenerate_'+ob.name,degenerate==0,zero_area_faces=degenerate)
for ob in objects:
    ob.data.calc_loop_triangles()
triangles=sum(len(o.data.loop_triangles) for o in objects)
report={'status':'FORM_REVIEW_CANDIDATE_NOT_RUNTIME','not_game_screenshot':True,
 'sources':{'script_sha256':sha(__file__),'approved_reference':str(REFERENCE.relative_to(PROJECT)),'reference_sha256':sha(REFERENCE),'layout':str(LAYOUT.relative_to(PROJECT)),'layout_sha256':sha(LAYOUT)},
 'coordinate_contract':{'blender':'Z up, front maps to Godot +Z','conversion':'Blender=(Godot.x,-Godot.z,Godot.y)','world_origin':list(WORLD_ORIGIN),'rest_root':'identity','local_bounds':[mins,maxs]},
 'anchors_godot_local':{k:list(v) for k,v in anchor_defs.items()},
 'geometry':{'editable_mesh_count':len(objects),'physical_mesh_count':len(physical),'triangles':triangles,'material_count':6,'physical_meshes':[o.name for o in physical],
 'collision':'later exact same actual visible stone/root triangles; no collision boxes or hulls; moss thin non-bearing detail','motion':'static; no animated pivots'},
 'observed_reference':['compact high thick stone shoulder','unequal broad broken stone faces','two flattened branching roots on top edges','small moss in cracks'],
 'authored_unknowns':['single reference does not reveal rear face or interior; rear rock/roots are authored continuation','topological facets and exact sizes come from measured JSON, not image measurement'],
 'limits':['basic grouped color only; no final UV/PBR/baking/GLB','no full-world collision, old-terrace dense seam or human flight acceptance','offline orthographic camera DIRECTION matches game; asset framed closer for form review'],
 'checks':checks,'failures':[c for c in checks if not c['passed']],
 'central_samples':central_samples,'root_surface_stations':root_support}

def move_to_studio(ob):
    for c in list(ob.users_collection): c.objects.unlink(ob)
    studio.objects.link(ob)

floor_mat=material('Offline_Studio_Grey',(.165,.185,.19),.9)
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.045))
floor=bpy.context.object;floor.name='Offline_Studio_Floor';move_to_studio(floor);floor.data.materials.append(floor_mat)
target=bl((1.85,2.6,0.))
for name,loc,power,size,color in [('Key',(-4,-6,11),900,7,(1,.94,.84)),('Fill',(7,2,7),600,6,(.75,.85,1)),('Rim',(-3,5,9),700,5,(1,.95,.85))]:
    data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size;data.color=color
    ob=bpy.data.objects.new(name,data);studio.objects.link(ob);ob.location=loc;ob.rotation_euler=(target-ob.location).to_track_quat('-Z','Y').to_euler()
cam_data=bpy.data.cameras.new('Offline_DefaultDirection')
cam=bpy.data.objects.new('Offline_DefaultDirection',cam_data);studio.objects.link(cam);scene.camera=cam;cam_data.type='ORTHO';cam_data.ortho_scale=8.1
cam.location=target+bl((32,39,32))
cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler()
report['camera']={'source':'scripts/v2/flight_camera.gd OFFSET=(32,39,32)','godot_direction_offset':[32,39,32],'orthographic_scale':8.1,'crop':'asset form detail, not actual gameplay framing'}
blend_path=BASE/'growth_approach_west_p1.blend'
bpy.ops.wm.save_as_mainfile(filepath=str(blend_path),check_existing=False)
report['editable_blend_sha256']=sha(blend_path)
(BASE/'geometry_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
if report['failures']:
    print('WEST_FORM_GEOMETRY_FAIL',json.dumps(report['failures'],ensure_ascii=False))
    raise RuntimeError('Geometry/interface checks failed; inspect report before any rendering.')
if not NO_RENDER:
    scene.render.filepath=str(BASE/'west_p1_default_direction.png')
    bpy.ops.render.render(write_still=True)
    # A second, labelled reverse view reveals the uncertain rear/intersection side.
    cam.location=target+bl((-32,28,-32))
    cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler()
    scene.render.filepath=str(BASE/'west_p1_reverse_direction.png')
    bpy.ops.render.render(write_still=True)
    manifest={'render_engine':'Cycles CPU','threads':2,'samples':16,'not_game_screenshot':True,'input_blend_sha256':sha(blend_path),'images':{p.name:sha(p) for p in (BASE/'west_p1_default_direction.png',BASE/'west_p1_reverse_direction.png')}}
    (BASE/'preview_provenance.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print('WEST_FORM_READY',json.dumps({'checks':len(checks),'failures':len(report['failures']),'triangles':triangles,'blend_sha256':report['editable_blend_sha256']},ensure_ascii=False))
