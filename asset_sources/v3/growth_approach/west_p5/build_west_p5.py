"""One bounded West P5 source/form study. No GLB, textures or runtime writes.

Run ONLY after coordinated CPU2 permission:
  Blender 5.2 --background --factory-startup --threads 2 --python-exit-code 1
    --python asset_sources/v3/growth_approach/west_p5/build_west_p5.py

Append actual CC0 artist LOD meshes; retain uncut editable copies. Three stones
are placed by uniform scale/rigid rotation, then locally cut to the contractual
roof/boundary. No box core, complete lid, convex-hull stand-in or invented scan.
One basic-color assembly image is produced even if numerical checks fail;
failure stops acceptance and must not trigger an unapproved new version.
"""
import bpy, bmesh, json, math, hashlib
from pathlib import Path
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

BASE = Path(__file__).resolve().parent
PROJECT = BASE.parents[3]
RECOVERY = BASE.parent / 'resource_recovery'
LAYOUT = PROJECT / 'data/v3/terrain/f1_growth_crossing.json'
REFERENCE = PROJECT / 'references/v3/production/growth_approach/growth_approach_west_reference_v2.png'
TERRACE = PROJECT / 'asset_sources/v3/fantasy_kit/rootstone_terrace.blend'
SOURCE_BOULDER = RECOVERY / 'boulder_01/boulder_01_1k.blend'
SOURCE_NAMA = RECOVERY / 'namaqualand_boulder_03/namaqualand_boulder_03_1k.blend'

def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def bl(p): return Vector((p[0], -p[2], p[1]))
def gd(p): return Vector((p[0], p[2], -p[1]))

assert sha(SOURCE_BOULDER) == '8f8004fb52ebd00c4702a50873ac799e7bd7a0bea3415f2d8bc9986e1c58e371'
assert sha(SOURCE_NAMA) == '43e8e12ebbd694b73b1c8ffd2ca75983f7b5c8f41672792d98a7cfde328f5e66'
data = json.loads(LAYOUT.read_text(encoding='utf-8-sig'))
west = next(a for a in data['approaches'] if a['id'] == 'west')
sections = [(s['x'] + 14.5, [(z - 25, y) for z, y in s['top_zy']]) for s in west['sections']]
original_top = []
for k in range(len(sections)-1):
    xa, a = sections[k]; xb, b = sections[k+1]
    for j in range(len(a)-1):
        p = Vector((xa, a[j][1], a[j][0])); q = Vector((xb, b[j][1], b[j][0]))
        r = Vector((xb, b[j+1][1], b[j+1][0])); s = Vector((xa, a[j+1][1], a[j+1][0]))
        original_top.extend([(p,q,r),(p,r,s)])

def top_height(x,z):
    for p,q,r in original_top:
        den = (q.z-r.z)*(p.x-r.x)+(r.x-q.x)*(p.z-r.z)
        u = ((q.z-r.z)*(x-r.x)+(r.x-q.x)*(z-r.z))/den
        v = ((r.z-p.z)*(x-r.x)+(p.x-r.x)*(z-r.z))/den
        if min(u,v,1-u-v) >= -1e-6: return u*p.y+v*q.y+(1-u-v)*r.y
    raise ValueError(('outside top',x,z))

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.engine = 'CYCLES'; scene.cycles.device = 'CPU'
scene.render.threads_mode = 'FIXED'; scene.render.threads = 2
scene.cycles.samples = 12; scene.cycles.use_denoising = True
scene.render.resolution_x = 1200; scene.render.resolution_y = 1000
scene.render.resolution_percentage = 100; scene.view_settings.view_transform = 'AgX'
scene.unit_settings.system = 'METRIC'; scene.unit_settings.scale_length = 1.0

def collection(name):
    c=bpy.data.collections.new(name); scene.collection.children.link(c); return c
MODEL=collection('WEST_P5_EDITABLE_MODEL')
AUTHOR=collection('SOURCE_AND_EDITABLE_CURVES_NOT_RENDERED')
CONTEXT=collection('ASSEMBLY_CONTEXT_NOT_ASSET')
STUDIO=collection('STUDIO_NOT_ASSET')
root=bpy.data.objects.new('GrowthApproachWest',None); MODEL.objects.link(root)
root['world_origin_godot']=[-14.5,0,25]
root['status']='p5_source_form_candidate_not_accepted_no_runtime_export'

def material(name,color):
    m=bpy.data.materials.new(name); m.diffuse_color=(*color,1); m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value=(*color,1); p.inputs['Roughness'].default_value=.9
    return m
STONE=material('P5_Basic_WarmGrey_Stone',(.38,.36,.315))
STONE2=material('P5_Basic_Second_Stone',(.33,.325,.30))
BARK=material('P5_Basic_Root_Wood',(.245,.125,.052))
CONTEXT_STONE=material('Context_Desaturated_Stone',(.21,.245,.225))
CONTEXT_ROOT=material('Context_Desaturated_Root',(.16,.145,.11))
CONTEXT_PATH=material('Context_Desaturated_Path',(.245,.25,.21))
INPUTS=[]; OPERATIONS=[]; rocks=[]; roots=[]; anchors=[]

def move_to(ob,c):
    for prev in list(ob.users_collection): prev.objects.unlink(ob)
    c.objects.link(ob)
def hide(ob): ob.hide_render=True; ob.hide_set(True)
def raw_mesh(name,verts,faces,c=MODEL):
    me=bpy.data.meshes.new(name+'_Mesh'); me.from_pydata([bl(v) for v in verts],[],faces); me.update()
    ob=bpy.data.objects.new(name,me); c.objects.link(ob)
    if c==MODEL: ob.parent=root
    return ob
def clean(ob,label):
    bm=bmesh.new(); bm.from_mesh(ob.data)
    before={'verts':len(bm.verts),'faces':len(bm.faces),'signed_volume':bm.calc_volume(signed=True)}
    bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-7)
    bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=1e-9)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    volume=bm.calc_volume(signed=True); flipped=volume<0
    if flipped: bmesh.ops.reverse_faces(bm,faces=list(bm.faces))
    bm.to_mesh(ob.data); bm.free(); ob.data.update()
    OPERATIONS.append({'object':ob.name,'operation':label,'before':before,'negative_orientation_corrected':flipped})
def archive(ob,name):
    cp=ob.copy(); cp.data=ob.data.copy(); cp.name=name; AUTHOR.objects.link(cp); cp.parent=None; hide(cp)
    return cp

def append_scan(path,object_name,name,scale,orientation,centre,mat):
    with bpy.data.libraries.load(str(path),link=False) as (src,dst):
        assert object_name in src.objects, (path,object_name)
        dst.objects=[object_name]
    ob=dst.objects[0]; MODEL.objects.link(ob); ob.name=name
    source_world=ob.matrix_world.copy()
    archive(ob,name+'_UntouchedArtistMesh')
    coordinates=[gd(source_world@v.co) for v in ob.data.vertices]
    low=Vector(tuple(min(p[i] for p in coordinates) for i in range(3)))
    high=Vector(tuple(max(p[i] for p in coordinates) for i in range(3)))
    mid=(low+high)*.5
    ob.data=ob.data.copy()
    ob.parent=root; ob.matrix_world=Matrix.Identity(4)
    for v,p in zip(ob.data.vertices,coordinates): v.co=bl(orientation@(p-mid)*scale+Vector(centre))
    ob.data.materials.clear(); ob.data.materials.append(mat)
    for f in ob.data.polygons: f.material_index=0
    ob.data.update()
    ob['source_url']='https://polyhaven.com/a/'+('boulder_01' if path==SOURCE_BOULDER else 'namaqualand_boulder_03')
    ob['source_license']='CC0'; ob['source_object']=object_name
    ob['placement_uniform_scale']=scale; ob['artist_shape_preserved_before_local_cuts']=True
    INPUTS.append({'name':name,'file':str(path.relative_to(PROJECT)),'sha256':sha(path),
        'source_object':object_name,'source_bounds_godot':[list(low),list(high)],
        'scale_uniform':scale,'rigid_orientation_rows':[list(row) for row in orientation],
        'centre_godot_local':centre,'source_triangles':sum(len(f.vertices)-2 for f in ob.data.polygons)})
    clean(ob,'artist_mesh_orientation_and_numerical_degenerate_cleanup')
    archive(ob,name+'_PlacedBeforeLocalCuts')
    return ob

# Largest natural axis upright only on the lower diagonal mass. Two thick
# upper blocks remain broad; there is no slender stretched column or lid.
R_Y90=Matrix.Rotation(math.pi/2,3,'Y')
R_X90=Matrix.Rotation(math.pi/2,3,'X')
A=append_scan(SOURCE_BOULDER,'boulder_01_LOD2','Stone_A_NaturalDiagonalFoot',1.80,
    Matrix.Rotation(math.radians(-12),3,'Z')@Matrix.Rotation(math.radians(10),3,'Y')@R_X90,
    (1.25,1.52,-.04),STONE2)
B=append_scan(SOURCE_NAMA,'namaqualand_boulder_03_LOD2','Stone_B_NaturalWestBearing',1.22,
    R_Y90,(1.10,4.05,0),STONE)
C=append_scan(SOURCE_BOULDER,'boulder_01_LOD3','Stone_C_NaturalBridgeShoulder',1.98,
    Matrix.Rotation(math.radians(-7),3,'Y')@R_Y90,(2.78,4.52,-.02),STONE2)

# This closed volume is a CUTTER only; it never becomes a mesh in the asset.
verts=[(x,y,z) for x,zy in sections for z,y in zy]
verts += [(x,0,z) for x,zy in sections for z,y in zy]
faces=[]; n=20
for k in range(3):
    for j in range(4):
        a=k*5+j; b=(k+1)*5+j; c=b+1; d=a+1
        faces.extend([(a,b,c),(a,c,d),(a+n,d+n,c+n,b+n)])
rim=[0,5,10,15,16,17,18,19,14,9,4,3,2,1]
for a,b in zip(rim,rim[1:]+rim[:1]): faces.append((a,a+n,b+n,b))
roof=raw_mesh('MeasuredInterface_CUTTER_NOT_ASSET',verts,faces,AUTHOR); clean(roof,'closed_cutter_orientation')

def boolean(ob,other,operation,label):
    bpy.context.view_layer.objects.active=ob
    mod=ob.modifiers.new(label,'BOOLEAN'); mod.operation=operation; mod.solver='EXACT'; mod.object=other
    bpy.ops.object.modifier_apply(modifier=mod.name)
    clean(ob,label)

for ob in (A,B,C):
    boolean(ob,roof,'INTERSECT','LocalContractBoundaryAndRoof')
    # Remove only overlapping stone volume. This prevents coplanar double
    # roof faces while retaining three independently editable natural masses.
    for earlier in rocks: boolean(ob,earlier,'DIFFERENCE','OwnedSolidJoin_'+earlier.name)
    rocks.append(ob)
hide(roof)
bpy.context.view_layer.update()

def bvh(obs):
    vv=[]; ff=[]
    for ob in obs:
        ob.data.calc_loop_triangles(); off=len(vv)
        vv += [ob.matrix_world@v.co for v in ob.data.vertices]
        ff += [tuple(off+i for i in t.vertices) for t in ob.data.loop_triangles]
    return BVHTree.FromPolygons(vv,ff,all_triangles=True)
stone_tree=bvh(rocks)

def front_surface(x,y,sign):
    hit,_,_,_=stone_tree.ray_cast(bl((x,y,sign*4)),bl((0,0,-sign)),8)
    return gd(hit).z if hit is not None else None

ROOT_DATA=[]
def catmull(a,b,c,d,t):
    return .5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t)

def root_sweep(name,guide,sign,widths):
    xy=[Vector(p) for p in guide]; samples=[]
    for i in range(len(xy)-1):
        for k in range(7):
            t=k/7; p=catmull(xy[max(0,i-1)],xy[i],xy[i+1],xy[min(len(xy)-1,i+2)],t)
            radius=widths[i]*(1-t)+widths[i+1]*t
            samples.append((p,radius))
    samples.append((xy[-1],widths[-1]))
    points=[]; missing=[]; depths=[]
    for i,(p,w) in enumerate(samples):
        # At each guide location, prefer an adjacent actual natural recess
        # that can expose the root without crossing the z budget. Never move
        # or flatten the stone just to make the curve work.
        choices=[]
        for dx in (0,-.06,.06,-.12,.12):
            x=p.x+dx
            if .17<x<3.42:
                z=front_surface(x,p.y,sign)
                if z is not None: choices.append((abs(dx)+max(0,abs(z)-1.22)*2,x,z))
        if not choices:
            missing.append(i); x=p.x; z=sign*1.05
        else:
            _,x,z=min(choices)
        depth=.155*w
        embed=-.17 if i in (0,len(samples)-1) else .035
        # Account for the full three-bundle radial profile, not only its
        # nominal centreline radius (the P4 radius-only bound was wrong).
        actual_z=sign*min(1.5-depth*1.155-.003,abs(z)+embed)
        points.append(Vector((x,p.y,actual_z))); depths.append({'index':i,'surface_z':z,'centre_z':actual_z,'normal_radius':depth})
    vv=[]; ff=[]; N=14
    for i,((p,w),co) in enumerate(zip(samples,points)):
        tangent=points[min(i+1,len(points)-1)]-points[max(0,i-1)]
        tangent.z=0; tangent.normalize(); across=Vector((tangent.y,-tangent.x,0))
        for j in range(N):
            a=math.tau*j/N
            # Three broad bundles, not an even circular hose. No fine noise.
            fibre=1+.12*math.cos(3*a+.5)+.035*math.cos(5*a)
            v=co+across*(.245*w*math.cos(a)*fibre)+Vector((0,0,.155*w*math.sin(a)*fibre))
            vv.append(v)
    for i in range(len(points)-1):
        for j in range(N):
            k=(j+1)%N; ff.append((i*N+j,i*N+k,(i+1)*N+k,(i+1)*N+j))
    ff.append(tuple(reversed(range(N)))); ff.append(tuple((len(points)-1)*N+j for j in range(N)))
    ob=raw_mesh(name,vv,ff); ob.data.materials.append(BARK); clean(ob,'continuous_full_section_root_sweep')
    for f in ob.data.polygons: f.use_smooth=True
    cu=bpy.data.curves.new(name+'_EditablePath','CURVE'); cu.dimensions='3D'
    sp=cu.splines.new('POLY'); sp.points.add(len(points)-1)
    for p,co in zip(sp.points,points): p.co=(*bl(co),1)
    author=bpy.data.objects.new(name+'_EditableCurve',cu); AUTHOR.objects.link(author); hide(author)
    ob['authoring_curve']=author.name; ob['section']='three-bundle full cross-section, widths in source script'
    ROOT_DATA.append({'name':name,'missing_surface_samples':missing,'surface_relation':depths,
        'centreline_godot':[list(p) for p in points],'end_caps_intended_inside':True})
    roots.append(ob); return ob

root_sweep('Root_South_MainContinuous',[(2.95,4.78),(2.61,4.48),(2.19,4.18),(1.81,3.75),(1.69,3.19),(1.85,2.61),(2.02,2.10)],1,[.30,.88,1.08,1.05,.95,.72,.17])
root_sweep('Root_North_Secondary',[(.38,4.04),(.62,3.78),(.92,3.46),(1.12,2.95),(1.06,2.35),(.80,1.91)],-1,[.26,.83,.93,.85,.61,.15])

anchor_values={'OuterJoin':[0,sections[0][1][2][1],0],'BridgeLip':[3.5,5.25,0],'InnerEnd':[3.75,5.2,0]}
for i,(z,y) in enumerate(sections[0][1]): anchor_values['OuterJoin_'+str(i)]=[0,y,z]
for name,p in anchor_values.items():
    ob=bpy.data.objects.new(name,None); MODEL.objects.link(ob); ob.parent=root; ob.location=bl(p); ob.empty_display_size=.08; anchors.append(ob)
bpy.context.view_layer.update()

checks=[]
def check(name,ok,**extra): checks.append({'name':name,'passed':bool(ok),**extra})
all_objects=rocks+roots
tree=bvh(all_objects)
def down(x,z):
    hit,_,_,_=tree.ray_cast(bl((x,8,z)),bl((0,-1,0)),10)
    return gd(hit).y if hit is not None else None
vertices=[gd(ob.matrix_world@v.co) for ob in all_objects for v in ob.data.vertices]
minimum=[min(p[i] for p in vertices) for i in range(3)]
maximum=[max(p[i] for p in vertices) for i in range(3)]
check('all_actual_vertices_inside_original_envelope',all(minimum[i]>=lo-1e-5 and maximum[i]<=hi+1e-5 for i,(lo,hi) in enumerate(((0,3.75),(0,5.25),(-1.5,1.5)))),minimum=minimum,maximum=maximum)
for ob in all_objects:
    bm=bmesh.new(); bm.from_mesh(ob.data)
    boundary=sum(e.is_boundary for e in bm.edges); nonmanifold=sum(not e.is_manifold for e in bm.edges)
    zero=sum(f.calc_area()<1e-10 for f in bm.faces); volume=bm.calc_volume(signed=True); bm.free()
    check('closed_positive_nonzero_'+ob.name,boundary==0 and nonmanifold==0 and zero==0 and volume>0,
        boundary_edges=boundary,nonmanifold_edges=nonmanifold,zero_area_faces=zero,signed_volume_m3=volume)
for i,(z,y) in enumerate(sections[0][1]):
    actual=down(.00001,z*.999999)
    check('west_join_'+str(i),actual is not None and abs(actual-y)<.0002,actual=actual,expected=y)
for name,x,y,w in [('lip',3.5,5.25,1.5),('nose',3.74999,5.20,1.49)]:
    samples=[{'z':-w+.00001+(2*w-.00002)*i/30,'y':down(x,-w+.00001+(2*w-.00002)*i/30)} for i in range(31)]
    check(name+'_full_width_31',all(s['y'] is not None and abs(s['y']-y)<.0002 for s in samples),expected_y=y,samples=samples)
samples=[]
for i in range(41):
    x=.001+3.748*i/40
    for z in (-.85,-.425,0,.425,.85): samples.append({'x':x,'z':z,'actual':down(x,z),'expected':top_height(x,z)})
check('central_carrying_strip_205',all(s['actual'] is not None and abs(s['actual']-s['expected'])<.0002 for s in samples),samples=samples)
for name,p in anchor_values.items(): check('anchor_'+name,(gd(bpy.data.objects[name].matrix_world.translation)-Vector(p)).length<1e-7)
for entry in ROOT_DATA: check('root_actual_stone_support_'+entry['name'],not entry['missing_surface_samples'],missing=entry['missing_surface_samples'])
check('scan_sources_unchanged',sha(SOURCE_BOULDER)=='8f8004fb52ebd00c4702a50873ac799e7bd7a0bea3415f2d8bc9986e1c58e371' and sha(SOURCE_NAMA)=='43e8e12ebbd694b73b1c8ffd2ca75983f7b5c8f41672792d98a7cfde328f5e66')

# Assembly context is the actual frozen terrace source, not invented terrain.
with bpy.data.libraries.load(str(TERRACE),link=False) as (src,dst):
    dst.collections=['Editable_rootstone_terrace']
assert dst.collections[0] is not None
context_collection=dst.collections[0]; CONTEXT.children.link(context_collection)
context_matrix=Matrix.Translation(bl((-1,0,1.35)))@Matrix.Scale(.75,4)
for ob in list(context_collection.all_objects):
    if ob.type!='MESH': continue
    world=ob.matrix_world.copy(); ob.parent=None; ob.matrix_world=context_matrix@world
    ob.data=ob.data.copy()
    previous=ob.data.materials[0].name if ob.data.materials else ''
    ob.data.materials.clear(); ob.data.materials.append(CONTEXT_ROOT if 'Bark' in previous else (CONTEXT_PATH if 'Mud' in previous else CONTEXT_STONE))
    for f in ob.data.polygons: f.material_index=0
    ob['context_not_new_asset']=True

# True growth bridge dimensions/position; model only, no new gameplay claim.
bpy.ops.mesh.primitive_cube_add(size=1)
bridge=bpy.context.object; bridge.name='ExistingGrowthBridge_ContextOnly'; move_to(bridge,CONTEXT)
bridge.location=bl((14.5,5,0)); bridge.dimensions=(22,3,.5)
bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
bridge.data.materials.append(CONTEXT_ROOT)

floor=raw_mesh('PreviewGround_NotAsset',[(-35,-.035,-35),(35,-.035,-35),(35,-.035,35),(-35,-.035,35)],[(0,1,2,3)],STUDIO)
floor.data.materials.append(material('PreviewNeutralGround',(.135,.155,.15)))
target=bl((.9,3.0,.2))
camdata=bpy.data.cameras.new('DefaultGameDirectionCamera'); camera=bpy.data.objects.new('DefaultGameDirectionCamera',camdata); STUDIO.objects.link(camera)
camera.location=target+bl((32,39,32)); camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler()
camdata.type='ORTHO'; camdata.ortho_scale=10.3; scene.camera=camera
def light(name,at,energy,size):
    d=bpy.data.lights.new(name,'AREA'); d.energy=energy; d.shape='DISK'; d.size=size
    ob=bpy.data.objects.new(name,d); STUDIO.objects.link(ob); ob.location=bl(at)
    ob.rotation_euler=(target-ob.location).to_track_quat('-Z','Y').to_euler()
light('BroadKey',(-3,11,8),1700,7); light('SoftFill',(8,7,-3),850,6)
scene.world=bpy.data.worlds.new('NeutralWorld'); scene.world.use_nodes=True
scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.25,.28,.30,1)
scene.world.node_tree.nodes['Background'].inputs[1].default_value=.35
for ob in AUTHOR.objects: hide(ob)

for ob in all_objects: ob.data.calc_loop_triangles()
report={'status':'p5_single_form_candidate_pending_visual_review_not_runtime','world_origin':[-14.5,0,25],
    'coordinate_system':'Godot metres Y-up; Blender X,-Z,Y conversion only; unit scale1',
    'inputs':INPUTS,'layout_sha256':sha(LAYOUT),'reference_sha256':sha(REFERENCE),'script_sha256':sha(__file__),
    'context_terrace_sha256':sha(TERRACE),'context_terrace_position_relative':[-1,0,1.35],'context_terrace_uniform_scale':.75,
    'method':'three actual artist LOD stones, uniform transforms, local interface clipping, no full top lid; continuous editable root curves',
    'mesh_count':len(all_objects),'triangles':sum(len(ob.data.loop_triangles) for ob in all_objects),
    'local_bounds':[minimum,maximum],'anchors_godot_local':anchor_values,'root_data':ROOT_DATA,'operations':OPERATIONS,
    'checks':checks,'failures':[c for c in checks if not c['passed']],
    'limitations':['offline assembly direction preview, not engine screenshot','no GLB or PBR','no self-intersection or player sweep acceptance','cross-mesh root/stone embedding intentional','failed checks retained without threshold relaxation']}
blend=BASE/'growth_approach_west_p5.blend'
bpy.ops.wm.save_as_mainfile(filepath=str(blend),check_existing=False)
report['blend_sha256']=sha(blend)
(BASE/'input_f1_growth_crossing.json').write_bytes(LAYOUT.read_bytes())
report_path=BASE/'geometry_report.json'
report_path.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('WEST_P5_CHECKS',json.dumps({'checks':len(checks),'failures':[c['name'] for c in report['failures']],'triangles':report['triangles']}),flush=True)
scene.render.filepath=str(BASE/'west_p5_default_direction_assembly.png')
bpy.ops.render.render(write_still=True)
report['preview']={'path':'west_p5_default_direction_assembly.png','sha256':sha(scene.render.filepath),
    'direction':[32,39,32],'orthographic_size':10.3,'not_game_screenshot':True,'actual_frozen_terrace_context':True}
report_path.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('WEST_P5_SINGLE_REVIEW_READY',flush=True)
