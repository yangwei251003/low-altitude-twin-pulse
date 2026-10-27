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
LAYOUT = (BASE / 'input_f1_growth_crossing.json') if '--frozen-layout' in sys.argv else (PROJECT / 'data/v3/terrain/f1_growth_crossing.json')
REFERENCE = PROJECT / 'references/v3/production/growth_approach/growth_approach_west_reference_v2.png'
WORLD_ORIGIN = Vector((-14.5, 0.0, 25.0))
DATA = json.loads(LAYOUT.read_text(encoding='utf-8-sig'))
WEST = next(p for p in DATA['approaches'] if p['id'] == 'west')
SECTIONS = [(s['x'] + 14.5, [(p[0]-25.0, p[1]) for p in s['top_zy']]) for s in WEST['sections']]
BASE.mkdir(parents=True, exist_ok=True)
if LAYOUT != BASE/'input_f1_growth_crossing.json':
    (BASE/'input_f1_growth_crossing.json').write_bytes(LAYOUT.read_bytes())
NO_RENDER = '--no-render' in sys.argv

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def bl(p):
    return Vector((p[0], -p[2], p[1]))

def gd(p):
    return Vector((p[0], p[2], -p[1]))

def top_height(x, z):
    """Barycentric test on the exact authoritative triangles, including tapered nose."""
    x = max(0.0, min(3.75, float(x)))
    for i in range(len(SECTIONS)-1):
        xa, a = SECTIONS[i]
        xb, b = SECTIONS[i+1]
        if xa-1e-8 <= x <= xb+1e-8:
            tx = (x-xa)/(xb-xa)
            lo=a[0][0]*(1-tx)+b[0][0]*tx
            hi=a[-1][0]*(1-tx)+b[-1][0]*tx
            z=max(lo,min(hi,float(z)))
            for j in range(len(a)-1):
                va=(xa,a[j][1],a[j][0]); vb=(xb,b[j][1],b[j][0])
                vc=(xb,b[j+1][1],b[j+1][0]); vd=(xa,a[j+1][1],a[j+1][0])
                for p,q,r in ((va,vb,vc),(va,vc,vd)):
                    den=(q[2]-r[2])*(p[0]-r[0])+(r[0]-q[0])*(p[2]-r[2])
                    u=((q[2]-r[2])*(x-r[0])+(r[0]-q[0])*(z-r[2]))/den
                    v=((r[2]-p[2])*(x-r[0])+(p[0]-r[0])*(z-r[2]))/den
                    w=1-u-v
                    if min(u,v,w)>=-1e-7:
                        return u*p[1]+v*q[1]+w*r[1]
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
BARK = material('P1_Root_Main', (.115,.063,.027))
BARK_LIGHT = material('P1_Root_FibrePlane', (.165,.097,.043))
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

exec(compile((BASE/'thickrocks_form.py').read_text(encoding='utf-8'), str(BASE/'thickrocks_form.py'), 'exec'), globals())

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
    # Keep the inward probe within the genuinely narrowing edge: at X=10um
    # the corner has already receded 6um, so a 1.5um Z inset lies outside it.
    # X=1um and Z inset=1.5um sample the measured assembly boundary safely.
    got=down(.000001,z if abs(z)<1.5 else z*.999999)
    check('west_join_actual_surface_'+str(i),got is not None and abs(got-y)<.0001,expected=y,actual=got,z=z)
for name,x,expect,half_width in (('formal_bridge_lip',3.5,5.25,1.5),('recessed_inner_nose',3.749999,5.2,1.49)):
    for i in range(21):
        z=-half_width+.00001+(half_width*2-.00002)*i/20
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
side_sections=[]
for y in (0.15,1.5,2.8,4.2):
    row={'godot_y':y}
    for label,start,direction in [('east',(5,y,0),(-1,0,0)),('south',(1.5,y,3),(0,0,-1)),('north',(1.5,y,-3),(0,0,1))]:
        hit,_,_,_=rock_bvh.ray_cast(bl(start),bl(direction),8)
        row[label]=list(gd(hit)) if hit is not None else None
    side_sections.append(row)
check('four_actual_thick_stones_no_hidden_core', len(rocks)==4 and all(o.name.startswith('Stone_') for o in rocks),sections=side_sections)
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
report={'status':'FORM_REVIEW_CANDIDATE_NOT_RUNTIME','revision':'p1 four interlocking thick rocks, natural fork roots; previous hourglass rejected','not_game_screenshot':True,
 'sources':{'script_sha256':sha(__file__),'geometry_script_sha256':sha(BASE/'thickrocks_form.py'),'natural_fork_source':str(FORK_SOURCE.relative_to(PROJECT)),'natural_fork_source_sha256':FORK_SHA,'approved_reference':str(REFERENCE.relative_to(PROJECT)),'reference_sha256':sha(REFERENCE),'layout':str(LAYOUT.relative_to(PROJECT)),'layout_sha256':sha(LAYOUT)},
 'coordinate_contract':{'blender':'Z up, front maps to Godot +Z','conversion':'Blender=(Godot.x,-Godot.z,Godot.y)','world_origin':list(WORLD_ORIGIN),'rest_root':'identity','local_bounds':[mins,maxs]},
 'anchors_godot_local':{k:list(v) for k,v in anchor_defs.items()},
 'geometry':{'editable_mesh_count':len(objects),'physical_mesh_count':len(physical),'triangles':triangles,'material_count':len({m.name for o in objects for m in o.data.materials}),'physical_meshes':[o.name for o in physical],
 'collision':'later exact same actual visible stone/root triangles; no collision boxes or hulls; moss thin non-bearing detail','motion':'static; no animated pivots'},
 'observed_reference':['compact high thick stone shoulder','unequal broad broken stone faces','two flattened branching roots on top edges','small moss in cracks'],
 'authored_unknowns':['single reference does not reveal rear face or interior; rear rock/roots are authored continuation','topological facets and exact sizes come from measured JSON, not image measurement'],
 'limits':['basic grouped color only; no final UV/PBR/baking/GLB','no full-world collision, old-terrace dense seam or human flight acceptance','offline orthographic camera DIRECTION matches game; asset framed closer for form review'],
 'checks':checks,'failures':[c for c in checks if not c['passed']],
 'central_samples':central_samples,'root_surface_stations':root_support,'actual_rock_side_sections':side_sections}

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
