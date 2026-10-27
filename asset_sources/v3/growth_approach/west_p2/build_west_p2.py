"""Bounded p2 edit of the frozen p1 editable scene; no runtime outputs.

Blender 5.2 bundled Python only, from the project root:
  blender --background --factory-startup --threads 2 --python-exit-code 1
    --python asset_sources/v3/growth_approach/west_p2/build_west_p2.py
    -- [--no-render]

Only this script's directory is written. The p1 .blend, reference, JSON and
natural-source archive are read-only inputs. Rebuilds keep the p1 source hash.
Exact west samples, lip, recessed nose and central Z[-.85,.85] carrying surface
are protected; free side edges may recede/down-carve inside the same envelope.
Basic material GLB is for actual scene-placement review, NOT final PBR art.
"""
import bpy, bmesh, math, json, hashlib, sys
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree

BASE=Path(__file__).resolve().parent
PROJECT=BASE.parents[3]
P1=BASE.parent/'west_p1'
SOURCE=P1/'growth_approach_west_p1.blend'
LAYOUT=PROJECT/'data/v3/terrain/f1_growth_crossing.json'
REFERENCE=PROJECT/'references/v3/production/growth_approach/growth_approach_west_reference_v2.png'
BASE.mkdir(parents=True,exist_ok=True)
(BASE/'.gdignore').write_text('\n',encoding='utf8')
def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
source_sha=sha(SOURCE)
assert source_sha=='a1d22875f043bcc2360d6b7b83a56f447e9d598e19f9b58e7e257790c1106168'
data=json.loads(LAYOUT.read_text(encoding='utf-8-sig'))
(BASE/'input_f1_growth_crossing.json').write_bytes(LAYOUT.read_bytes())
west=next(p for p in data['approaches'] if p['id']=='west')
sections=[(s['x']+14.5,[(z-25,y) for z,y in s['top_zy']]) for s in west['sections']]
def bl(p): return Vector((p[0],-p[2],p[1]))
def gd(p): return Vector((p[0],p[2],-p[1]))

def top_height(x,z):
    x=max(0.,min(3.75,x))
    for k in range(len(sections)-1):
        xa,a=sections[k];xb,b=sections[k+1]
        if xa-1e-8<=x<=xb+1e-8:
            t=(x-xa)/(xb-xa)
            z=max(a[0][0]*(1-t)+b[0][0]*t,min(a[-1][0]*(1-t)+b[-1][0]*t,z))
            for j in range(len(a)-1):
                aa=(xa,a[j][1],a[j][0]);bb=(xb,b[j][1],b[j][0]);cc=(xb,b[j+1][1],b[j+1][0]);dd=(xa,a[j+1][1],a[j+1][0])
                for p,q,r in ((aa,bb,cc),(aa,cc,dd)):
                    den=(q[2]-r[2])*(p[0]-r[0])+(r[0]-q[0])*(p[2]-r[2])
                    u=((q[2]-r[2])*(x-r[0])+(r[0]-q[0])*(z-r[2]))/den
                    v=((r[2]-p[2])*(x-r[0])+(p[0]-r[0])*(z-r[2]))/den
                    if min(u,v,1-u-v)>=-1e-7:return u*p[1]+v*q[1]+(1-u-v)*r[1]
    raise AssertionError((x,z))

bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene=bpy.context.scene
scene.render.engine='CYCLES';scene.cycles.device='CPU'
scene.render.threads_mode='FIXED';scene.render.threads=2
scene.cycles.samples=12;scene.cycles.use_denoising=True
scene.render.resolution_x=1000;scene.render.resolution_y=1000
scene.render.resolution_percentage=100
root=bpy.data.objects['GrowthApproachWest']
model=root.users_collection[0]
model.name='EDITABLE_WEST_P2'
root['status']='basic_material_p2_source_candidate_pending_actual_assembly_review'
root['p1_input_sha256']=source_sha
root['world_origin_godot']=[-14.5,0.,25.]
rocks=[bpy.data.objects[n] for n in ['Stone_A_WestJoinedMass','Stone_B_UpperOffsetMass','Stone_C_WestBasalFracture','Stone_D_EastDeepLayer']]
rock_before={o.name:[gd(v.co).copy() for v in o.data.vertices] for o in rocks}
changes=[]

def smooth(a,b,x):
    t=max(0.,min(1.,(x-a)/(b-a)))
    return t*t*(3-2*t)

for ob in rocks:
    n=ob.name
    changed=0;kept=0
    for vert,old in zip(ob.data.vertices,rock_before[n]):
        x,y,z=old
        is_top=abs(y-top_height(x,z))<2e-5
        # Retain the existing adjacent Z1 row so interpolation across its
        # triangles cannot lower the required Z.85 carrying-strip boundary.
        fixed_top=is_top and (abs(z)<=1.0+1e-7 or x<.0001 or x>=3.4999)
        if fixed_top:
            kept+=1;continue
        # Free top borders retreat DOWN into the stone, not into a new railing.
        # The bridge lip/nose and measured west end are excluded from this mask.
        edge=smooth(.85,1.18,abs(z))
        end_mask=smooth(.015,.24,x)*(1-smooth(3.10,3.50,x))
        if is_top:
            drop=(.22+.12*math.sin(x*2.0+.55))*edge*end_mask
            y-=drop
            z-=math.copysign(.09*edge*end_mask,z)
        else:
            # Different oblique fracture cuts per actual thick stone, rather
            # than a single circumference-wide waist or parallel shelf bands.
            h=min(1.,y/.35)
            if 'Stone_A' in n:
                y+=h*(.13*math.sin(x*2.2)+.12*z)*(1-smooth(3.9,4.5,y))
                if z>0:z-=.17*h*smooth(.60,1.15,z)
                if x>.8 and z>.55:x-=.08*h
            elif 'Stone_B' in n:
                y+=h*(.18*(x-2.5)+.16*z)*(1-smooth(4.7,5.15,y))
                if z>0:z-=.24*h*smooth(.65,1.12,z)
                # Remove the old outward-returning lower sharp lip. The east
                # assembly face at its top remains precise and full width.
                if x>2.9:
                    x=min(x,2.92+.18*smooth(2.8,4.9,y)+.10*(1-abs(z)/1.5))
            elif 'Stone_C' in n:
                y+=h*(.16*(x-.8)-.11*z)
                if z>0:z-=.13*h*smooth(.65,1.15,z)
            else:
                y+=h*(-.15*(x-2.4)+.16*z)
                if z>0:z-=.21*h*smooth(.65,1.15,z)
                if x>3.05:x-=.10*h
        # Side relief under the major visible natural root. A broad, shallow
        # inward carving, not a thin pasted-on trim or hidden collider box.
        if z>0 and not fixed_top:
            facing=smooth(.67,1.00,z)
            near_root=smooth(.25,.60,x)*(1-smooth(2.9,3.2,x))*smooth(1.65,2.1,y)*(1-smooth(4.50,4.90,y))
            z-=.15*facing*near_root
        # All carving is bounded, base contact remains Y0.
        p=Vector((max(0.,min(3.75,x)),max(0.,min(5.25,y)),max(-1.5,min(1.5,z))))
        vert.co=bl(p)
        if (p-old).length>1e-7:changed+=1
    ob.data.update()
    bm=bmesh.new();bm.from_mesh(ob.data)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(ob.data);bm.free()
    ob['p2_edit']='free edge down-carve and unequal oblique thick-rock cuts; central/end assembly vertices protected'
    changes.append({'mesh':n,'changed_vertices':changed,'protected_top_vertices':kept})

# Retain the exact p1 south-root part as hidden editable evidence; replace only
# its displayed copy with the same real fork source, laid down the visible face.
old_root=bpy.data.objects['Root_NaturalSouthFork']
archive=bpy.data.collections.new('P1_EDITABLE_PART_COPY_NOT_EXPORTED')
scene.collection.children.link(archive);archive.hide_render=True;archive.hide_viewport=True
for col in list(old_root.users_collection):col.objects.unlink(old_root)
archive.objects.link(old_root);old_root.parent=None;old_root.hide_render=True
old_root.name='P1_SouthFork_Buried_Form_Preserved'
source=bpy.data.objects['OriginalNaturalFork_SourceCoordinates']
main=bpy.data.objects.new('Root_NaturalSouthFork',source.data.copy())
model.objects.link(main);main.parent=root
bm=bmesh.new();bm.from_mesh(main.data)
for point,normal in [((-.6,0,0),(-1,0,0)),((.4,0,0),(1,0,0))]:
    result=bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),plane_co=bl(point),plane_no=bl(normal),dist=1e-6,clear_outer=True)
    edges=[e for e in result['geom_cut'] if isinstance(e,bmesh.types.BMEdge) and e.is_boundary]
    if edges:bmesh.ops.holes_fill(bm,edges=edges,sides=0)
bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(main.data);bm.free()
originals=[gd(v.co) for v in main.data.vertices]
slice_max=[]
for j in range(44):
    yy=.1+j*.05;values=[p.x for p in originals if abs(p.y-yy)<=.075]
    slice_max.append(max(values) if values else .4)
def outer_x(yy):
    t=max(0.,min(42.999,(yy-.1)/.05));i=int(t)
    return slice_max[i]*(1-(t-i))+slice_max[i+1]*(t-i)
root_samples=[]
for vert,p in zip(main.data.vertices,originals):
    # Uniform 1.10 scale; sourceY follows the downward main trunk, sourceZ
    # carries its true fork width, sourceX is the thick surface-normal section.
    x=1.80+p.z*1.10
    y=4.65-(p.y-.1)*1.10
    burial=.40*(1-smooth(.1,.28,p.y))+.36*smooth(2.02,2.2,p.y)
    z=1.45+(p.x-outer_x(p.y))*1.10-burial
    vert.co=bl((x,y,z))
    root_samples.append({'source_y':p.y,'position':(x,y,z)})
main.data.materials.clear();main.data.materials.append(bpy.data.materials['P1_Root_Main'])
for poly in main.data.polygons:poly.use_smooth=True
main['source']=source.get('source_url','https://polyhaven.com/a/island_tree_01')
main['source_sha256']=source.get('source_sha256','')
main['source_rights']='CC0; frozen p1 source archive is retained; natural tree-base/fork, not a claimed root scan'
main['p2_mapping']='uniform 1.10 in all axes, rotate fork onto positive-Z face; measured sourceY sections translated in Z without normal flattening; only cut caps embedded'
main['collision_source']='same_visible_triangles'
bpy.context.view_layer.objects.active=main
main.select_set(True)
dec=main.modifiers.new('NaturalForkModerateDecimation','DECIMATE');dec.ratio=.52;dec.use_collapse_triangulate=True
bpy.ops.object.modifier_apply(modifier=dec.name)
main.data.calc_loop_triangles()
# Test actual post-decimation triangle interiors, not removed vertices or
# grazing edge rays. sourceY is recovered from the explicit linear Y mapping.
root_samples=[]
for tri in main.data.loop_triangles:
    p=sum((gd(main.data.vertices[i].co) for i in tri.vertices),Vector())/3
    root_samples.append({'source_y':.1+(4.65-p.y)/1.10,'position':list(p)})

objects=rocks+[main,bpy.data.objects['Root_NaturalNorthFork']]
anchors=[o for o in model.objects if o.type=='EMPTY' and o!=root]
bpy.context.view_layer.update()
def make_bvh(obs):
    vv=[];tt=[];owners=[]
    for ob in obs:
        ob.data.calc_loop_triangles();offset=len(vv)
        vv.extend([ob.matrix_world@v.co for v in ob.data.vertices])
        for tri in ob.data.loop_triangles:
            tt.append(tuple(offset+i for i in tri.vertices));owners.append(ob.name)
    return BVHTree.FromPolygons(vv,tt,all_triangles=True),owners
rock_bvh,_=make_bvh(rocks)
combined,owners=make_bvh(objects)
def down(x,z):
    hit,_,_,_=combined.ray_cast(bl((x,8,z)),bl((0,-1,0)),10.)
    return gd(hit).y if hit is not None else None
checks=[]
def check(name,ok,**detail): checks.append({'name':name,'passed':bool(ok),**detail})
points=[gd(o.matrix_world@v.co) for o in objects for v in o.data.vertices]
mins=[min(p[i] for p in points) for i in range(3)];maxs=[max(p[i] for p in points) for i in range(3)]
check('all_real_vertices_inside_original_hard_envelope',all(mins[i]>=a-1e-5 and maxs[i]<=b+1e-5 for i,(a,b) in enumerate(zip((0,0,-1.5),(3.75,5.25,1.5)))),minimum=mins,maximum=maxs)
check('actual_base_still_Y0',abs(mins[1])<1e-6)
for j,(z,y) in enumerate(sections[0][1]):
    got=down(.000001,z if abs(z)<1.5 else z*.999999)
    check('west_measured_join_'+str(j),got is not None and abs(got-y)<.0001,expected=y,actual=got,z=z)
for name,x,y,w in [('formal_lip',3.5,5.25,1.5),('lower_nose',3.749999,5.20,1.49)]:
    for i in range(21):
        z=-w+.00001+(2*w-.00002)*i/20;got=down(x,z)
        check(name+'_'+str(i),got is not None and abs(got-y)<.0001,expected=y,actual=got,z=z)
central=[]
for i in range(31):
    x=.001+3.748*i/30
    for z in (-.85,0,.85):
        got=down(x,z);expected=top_height(x,z)
        central.append({'x':x,'z':z,'actual':got,'expected':expected})
check('central_carrying_strip_continuous_no_new_rail',all(p['actual'] is not None and -.0002<=p['actual']-p['expected']<=.12 for p in central),samples=len(central))
p1_report=json.loads((P1/'geometry_report.json').read_text(encoding='utf8'))
for name,expected in p1_report['anchors_godot_local'].items():
    got=gd(bpy.data.objects[name].matrix_world.translation)
    check('unchanged_anchor_'+name,(got-Vector(expected)).length<1e-7,actual=list(got))
check('unit_root_origin',root.matrix_basis.is_identity)
for ob in objects:
    bm=bmesh.new();bm.from_mesh(ob.data)
    bad=sum(not e.is_manifold for e in bm.edges);zero=sum(f.calc_area()<1e-10 for f in bm.faces);bm.free()
    check('closed_actual_mesh_'+ob.name,bad==0,nonmanifold_edges=bad)
    check('nonzero_actual_faces_'+ob.name,zero==0,zero_area_faces=zero)
visibility=[]
for j in range(18):
    yy=.30+j*.09
    candidates=[p for p in root_samples if abs(p['source_y']-yy)<.035]
    outer=max(candidates,key=lambda p:p['position'][2])['position']
    hit,_,idx,_=combined.ray_cast(bl((outer[0],outer[1],3)),bl((0,0,-1)),4.)
    stone,_,_,_=rock_bvh.ray_cast(bl((outer[0],outer[1],3)),bl((0,0,-1)),5.)
    visibility.append({'source_y':yy,'sample':list(outer),'first_hit':owners[idx] if hit is not None else None,'first_hit_position':list(gd(hit)) if hit is not None else None,'rock_position':list(gd(stone)) if stone is not None else None})
check('main_root_continuous_visible_face_18_stations',all(r['first_hit']=='Root_NaturalSouthFork' for r in visibility),stations=visibility)
check('frozen_p1_source_unchanged',sha(SOURCE)==source_sha)
for ob in objects:ob.data.calc_loop_triangles()
triangles=sum(len(o.data.loop_triangles) for o in objects)
report={'status':'p2_basic_material_candidate_pending_actual_assembly_review','world_origin':[-14.5,0,25],'local_bounds':[mins,maxs],
 'inputs':{'p1_blend':str(SOURCE.relative_to(PROJECT)),'p1_sha256':source_sha,'layout_sha256':sha(LAYOUT),'reference_sha256':sha(REFERENCE),'script_sha256':sha(__file__)},
 'observations':['p1 actual game shots02/03/04 show parallel sharp shelves and root visible only as top fragments','p2 changes only free rock edges and visible south-root placement'],
 'geometry':{'mesh_count':len(objects),'triangles':triangles,'materials':sorted({m.name for o in objects for m in o.data.materials}),'collision':'same visible triangles; no boxes or hulls'},
 'edits':changes,'root_mapping':dict(main.items()),'anchors_godot_local':p1_report['anchors_godot_local'],'central_samples':central,
 'checks':checks,'failures':[c for c in checks if not c['passed']],
 'limits':['basic grouped material, no new UV/PBR bake','offline preview not game image','root front18 probes test continuity at these sections only, not complete camera visibility or all self-intersection','final same-camera actual assembly and physics are root-agent work']}
blend=BASE/'growth_approach_west_p2.blend'
bpy.ops.wm.save_as_mainfile(filepath=str(blend),check_existing=False)
report['blend_sha256']=sha(blend)
(BASE/'geometry_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
if report['failures']:
    print('WEST_P2_FAIL',json.dumps(report['failures'],ensure_ascii=False))
    raise RuntimeError('Physical/interface or visible-root checks failed; no GLB delivered')
bpy.ops.object.select_all(action='DESELECT')
for ob in [root]+objects+anchors:
    ob.hide_set(False);ob.select_set(True)
bpy.context.view_layer.objects.active=root
glb=BASE/'west_p2_review.glb'
bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,export_yup=True,export_apply=True,export_extras=True,export_animations=False)
report['review_glb']={'path':glb.name,'sha256':sha(glb),'bytes':glb.stat().st_size}
(BASE/'geometry_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
if '--no-render' not in sys.argv:
    target=bl((1.85,2.6,0.))
    scene.camera.location=target+bl((32,39,32))
    scene.camera.rotation_euler=(target-scene.camera.location).to_track_quat('-Z','Y').to_euler()
    scene.camera.data.ortho_scale=8.1
    scene.render.filepath=str(BASE/'west_p2_default_direction.png')
    bpy.ops.render.render(write_still=True)
    report['offline_preview']={'path':'west_p2_default_direction.png','sha256':sha(BASE/'west_p2_default_direction.png'),'direction':[32,39,32],'not_game_screenshot':True}
    (BASE/'geometry_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print('WEST_P2_READY',json.dumps({'checks':len(checks),'failures':len(report['failures']),'triangles':triangles,'glb':report['review_glb']},ensure_ascii=False))
