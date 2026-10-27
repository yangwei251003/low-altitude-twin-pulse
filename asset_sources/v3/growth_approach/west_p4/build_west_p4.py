"""West P4 form study only. Blender 5.2 bundled Python, CPU2.
Run only in a coordinated render window:
blender --background --factory-startup --threads 2 --python-exit-code 1
  --python asset_sources/v3/growth_approach/west_p4/build_west_p4.py
Writes this directory only; no runtime/candidate GLB and no PBR.
Independent oblique convex rock masses are cut by the measured roof volume;
there is no complete top sheet extruded into a rectangular body.
"""
import bpy, bmesh, math, json, hashlib, sys
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree

BASE=Path(__file__).resolve().parent
PROJECT=BASE.parents[3]
P3=BASE.parent/'west_p3'
sys.path.insert(0,str(P3))
from geometry_checks import strict_self_intersections
LAYOUT=PROJECT/'data/v3/terrain/f1_growth_crossing.json'
REFERENCE=PROJECT/'references/v3/production/growth_approach/growth_approach_west_reference_v2.png'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def bl(p):return Vector((p[0],-p[2],p[1]))
def gd(p):return Vector((p[0],p[2],-p[1]))
BASE.mkdir(parents=True,exist_ok=True)
(BASE/'.gdignore').write_text('\n',encoding='utf8')
(BASE/'input_f1_growth_crossing.json').write_bytes(LAYOUT.read_bytes())
data=json.loads(LAYOUT.read_text(encoding='utf-8-sig'))
west=next(a for a in data['approaches'] if a['id']=='west')
sections=[(s['x']+14.5,[(z-25,y) for z,y in s['top_zy']]) for s in west['sections']]
original_top=[]
for k in range(len(sections)-1):
    xa,a=sections[k];xb,b=sections[k+1]
    for j in range(len(a)-1):
        aa=Vector((xa,a[j][1],a[j][0]));bb=Vector((xb,b[j][1],b[j][0]))
        cc=Vector((xb,b[j+1][1],b[j+1][0]));dd=Vector((xa,a[j+1][1],a[j+1][0]))
        original_top.extend([(aa,bb,cc),(aa,cc,dd)])
def top_height(x,z):
    for p,q,r in original_top:
        den=(q.z-r.z)*(p.x-r.x)+(r.x-q.x)*(p.z-r.z)
        u=((q.z-r.z)*(x-r.x)+(r.x-q.x)*(z-r.z))/den
        v=((r.z-p.z)*(x-r.x)+(p.x-r.x)*(z-r.z))/den
        if min(u,v,1-u-v)>=-1e-6:return u*p.y+v*q.y+(1-u-v)*r.y
    raise ValueError(('outside top',x,z))

bpy.ops.wm.read_factory_settings(use_empty=True)
scene=bpy.context.scene
scene.render.engine='CYCLES';scene.cycles.device='CPU'
scene.render.threads_mode='FIXED';scene.render.threads=2
scene.cycles.samples=12;scene.cycles.use_denoising=True
scene.render.resolution_x=1000;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX'
model=bpy.data.collections.new('EDITABLE_WEST_P4_FORM');scene.collection.children.link(model)
construction=bpy.data.collections.new('EDITABLE_CONSTRUCTION_NOT_RENDERED');scene.collection.children.link(construction)
root=bpy.data.objects.new('GrowthApproachWest',None);model.objects.link(root)
root['world_origin_godot']=[-14.5,0,25]
root['status']='p4_form_study_not_runtime_not_accepted'
prior=json.loads((P3/'geometry_report.json').read_text(encoding='utf8'))
anchors=[]
for name,p in prior['anchors_godot_local'].items():
    ob=bpy.data.objects.new(name,None);model.objects.link(ob);ob.parent=root;ob.location=bl(p);ob.empty_display_size=.08;anchors.append(ob)

def material(name,color):
    m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*color,1);p.inputs['Roughness'].default_value=.91
    return m
STONE=material('P4_Stone_MidGray',(.35,.335,.295))
LIGHT=material('P4_Stone_BroadCut',(.43,.415,.37))
DARK=material('P4_Stone_DeepPlane',(.255,.265,.25))
BARK=material('P4_Root_WarmWood',(.27,.145,.066))
MATS=[STONE,LIGHT,DARK,BARK]
objects=[];rocks=[];roots=[]
def mesh(name,verts,faces,collection=model):
    me=bpy.data.meshes.new(name+'_Mesh');me.from_pydata([bl(p) for p in verts],[],faces);me.update()
    ob=bpy.data.objects.new(name,me);collection.objects.link(ob)
    if collection==model:ob.parent=root
    for m in MATS:me.materials.append(m)
    bm=bmesh.new();bm.from_mesh(me);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free()
    return ob
def clean(ob):
    bm=bmesh.new();bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-6)
    bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=1e-8)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bm.to_mesh(ob.data);bm.free();ob.data.update()
def bool_op(ob,other,operation):
    bpy.context.view_layer.objects.active=ob
    mod=ob.modifiers.new('LocalSolid_'+operation,'BOOLEAN');mod.operation=operation;mod.solver='EXACT';mod.object=other
    bpy.ops.object.modifier_apply(modifier=mod.name)
    clean(ob)
def hide(ob):ob.hide_render=True;ob.hide_set(True)
def archive_copy(ob,name):
    cp=ob.copy();cp.data=ob.data.copy();cp.name=name;construction.objects.link(cp);cp.parent=None;hide(cp);return cp
def hull(name,points):
    ob=mesh(name,points,[])
    bm=bmesh.new();bm.from_mesh(ob.data)
    ret=bmesh.ops.convex_hull(bm,input=list(bm.verts),use_existing_faces=False)
    interior=list({v for v in list(ret.get('geom_interior',[]))+list(ret.get('geom_unused',[])) if isinstance(v,bmesh.types.BMVert) and v.is_valid})
    if interior:bmesh.ops.delete(bm,geom=interior,context='VERTS')
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(ob.data);bm.free()
    archive_copy(ob,name+'_UncutEditableMass')
    return ob

# The interface cutter is not exported/rendered and is never a visible lid.
vv=[(x,y,z) for x,zy in sections for z,y in zy]
vv+= [(x,0,z) for x,zy in sections for z,y in zy]
ff=[];n=20
for k in range(3):
    for j in range(4):
        a=k*5+j;b=(k+1)*5+j;c=b+1;d=a+1
        ff.extend([(a,b,c),(a,c,d),(a+n,d+n,c+n,b+n)])
rim=[0,5,10,15,16,17,18,19,14,9,4,3,2,1]
for a,b in zip(rim,rim[1:]+rim[:1]):ff.append((a,a+n,b+n,b))
roof=mesh('Measured_Local_Interface_Cutter',vv,ff,construction)

# Hand-designed uneven point clouds, not four oriented bounding boxes.
clouds={
'Rock_A_DiagonalMain':[
(.22,.20,.12),(.42,.12,-.94),(1.62,0,-.95),(2.13,.48,.45),(1.48,.08,1.24),(.50,.22,1.07),
(.17,2.25,.92),(.95,3.25,1.39),(2.50,2.15,.83),(2.72,3.45,-.73),(.20,3.47,-1.24),
(.36,4.08,-1.20),(.92,4.35,-1.31),(2.77,4.62,-1.14),(2.70,4.52,1.29),(.40,3.95,1.28),
(.30,5.30,-.94),(.30,5.30,.94),(2.82,5.60,-.94),(2.82,5.60,.94)],
'Rock_B_EastBearing':[
(1.72,2.25,-.53),(2.12,1.60,.27),(2.73,2.20,1.04),(3.28,3.48,1.40),(3.96,4.48,1.59),
(3.99,4.55,-1.59),(3.28,3.05,-1.23),(2.45,2.20,-1.24),
(1.80,4.72,-1.27),(2.75,4.82,-1.48),(4.03,5.88,-1.68),(4.03,5.88,1.68),(2.65,4.62,1.41),(1.72,4.58,1.13),
(1.72,5.75,-.94),(1.72,5.75,.94),(3.10,5.78,-.94),(3.10,5.78,.94)],
'Rock_C_WestFoot':[
(-.15,0,-1.31),(.58,0,-1.48),(1.55,.06,-.70),(1.35,.15,.85),(.40,0,1.48),(-.17,0,1.10),
(-.20,2.20,1.30),(.85,2.00,1.46),(1.54,2.89,.68),(1.45,3.42,-1.17),(-.17,3.3,-1.55),
(-.2,5.1,-1.61),(.75,3.88,-1.48),(1.37,4.4,-1.03),(1.30,4.1,1.20),(.42,3.7,1.46),(-.2,5.05,1.59),
(.25,5.15,-.94),(.25,5.15,.94),(1.40,5.22,-.94),(1.40,5.22,.94)],
'Rock_D_LowLock':[
(1.75,0,-.84),(2.65,0,-1.28),(3.37,0,-.83),(3.48,0,.64),(2.86,0,1.36),(2.03,.03,.97),
(1.92,1.35,-1.02),(2.72,2.16,-.96),(3.30,2.55,.19),(2.92,2.12,1.27),(2.02,1.53,1.03)]}

# One oblique front plane gives the root-side real volume, without a cavity.
front_cut=hull('Temporary_Front_Slope',[
(-1,-1,-3),(5,-1,-3),(5,7,-3),(-1,7,-3),
(-1,-1,.34),(5,-1,.34),(5,7,1.86),(-1,7,1.86)])
for c in list(front_cut.users_collection):c.objects.unlink(front_cut)
construction.objects.link(front_cut);front_cut.parent=None
raw=[]
for i,(name,pts) in enumerate(clouds.items()):
    ob=hull(name,pts)
    bool_op(ob,roof,'INTERSECT')
    # The measured west edge and last 0.25m lip require their full widths:
    # do not apply a global side cut there. Broad diagonal main mass only.
    if i==0:bool_op(ob,front_cut,'INTERSECT')
    raw.append(archive_copy(ob,name+'_ClippedBeforeJoin'))
    # Solid subtraction prevents coplanar visible roof overlaps while the
    # separate rocks remain editable. Unequal solid boundaries terminate seams.
    for previous in rocks:bool_op(ob,previous,'DIFFERENCE')
    clean(ob)
    for face in ob.data.polygons:
        n=gd(face.normal)
        face.material_index=1 if n.y>.73 else (2 if n.y<-.28 else (i%2))
    ob['construction']='independent oblique convex mass, local measured interface cut; no extruded full roof'
    rocks.append(ob);objects.append(ob)
hide(roof);hide(front_cut)

def bvh(obs):
    verts=[];tri=[]
    for ob in obs:
        ob.data.calc_loop_triangles();start=len(verts)
        verts += [ob.matrix_world@v.co for v in ob.data.vertices]
        tri += [tuple(start+i for i in t.vertices) for t in ob.data.loop_triangles]
    return BVHTree.FromPolygons(verts,tri,all_triangles=True)
bpy.context.view_layer.update()
rock_tree=bvh(rocks)
def side_z(x,y,sign):
    hit,_,_,_=rock_tree.ray_cast(bl((x,y,sign*3)),bl((0,0,-sign)),6)
    if hit is None:raise RuntimeError(('root path has no stone',x,y,sign))
    return gd(hit).z

root_paths=[]
def curve_root(name,xy,sign,widths):
    points=[]
    for i,((x,y),w) in enumerate(zip(xy,widths)):
        surface=side_z(x,y,sign)
        # Root caps deliberately enter the stone; the main span is exposed.
        embed=-.22 if i in (0,len(xy)-1) else .035
        z=sign*min(1.5-.19*w,abs(surface)+embed)
        points.append((x,y,z))
    # Editable curve + genuinely thick, non-circular cross section. The
    # authoring profile is preserved, not a flattened natural scan.
    profile=bpy.data.curves.new(name+'_Section','CURVE');profile.dimensions='2D'
    sp=profile.splines.new('POLY');sp.points.add(11)
    for j,p in enumerate(sp.points):
        a=math.tau*j/12;r=1+.10*math.cos(3*a+.4)+.045*math.sin(5*a)
        p.co=(.26*math.cos(a)*r,.16*math.sin(a)*r,0,1)
    sp.use_cyclic_u=True
    prof=bpy.data.objects.new(name+'_EditableSection',profile);construction.objects.link(prof)
    cu=bpy.data.curves.new(name+'_EditablePath','CURVE');cu.dimensions='3D';cu.resolution_u=7
    cu.bevel_mode='OBJECT';cu.bevel_object=prof;cu.use_fill_caps=True;cu.twist_mode='MINIMUM'
    path=cu.splines.new('BEZIER');path.bezier_points.add(len(points)-1)
    for p,co,w in zip(path.bezier_points,points,widths):
        p.co=bl(co);p.radius=w;p.handle_left_type='AUTO';p.handle_right_type='AUTO'
    author=bpy.data.objects.new(name+'_EditableCurve',cu);construction.objects.link(author)
    bpy.context.view_layer.update()
    me=bpy.data.meshes.new_from_object(author.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    ob=bpy.data.objects.new(name,me);model.objects.link(ob);ob.parent=root
    for m in MATS:me.materials.append(m)
    for face in me.polygons:face.material_index=3
    clean(ob)
    for face in me.polygons:face.use_smooth=False
    root_paths.append({'name':name,'points_godot':points,'radii_scale':widths,'section_metres':[.52,.32],'construction':'editable Bezier + asymmetric full cross-section; caps enter rocks'})
    hide(author);hide(prof);roots.append(ob);objects.append(ob)
    return ob,points

south,sp=curve_root('Root_South_Continuous',[(2.90,4.91),(2.66,4.65),(2.25,4.22),(1.82,3.70),(1.54,3.05),(1.73,2.40),(1.92,1.72),(2.01,1.18)],1,[.50,.90,1.05,1.0,.95,.80,.60,.18])
north,np=curve_root('Root_North_Continuous',[(.40,4.10),(.67,3.85),(.94,3.35),(1.05,2.77),(.84,2.10),(.51,1.48),(.35,.90)],-1,[.45,.95,1.,.90,.80,.60,.18])

# Editable branch only joins the exposed middle span; voxel union is confined
# to wood, not any measured interface or stone mesh.
branch,bp=curve_root('Root_South_Branch',[(1.82,3.70),(2.13,3.44),(2.47,3.08),(2.68,2.75)],1,[.74,.56,.40,.12])
bpy.ops.object.select_all(action='DESELECT')
for ob in (south,branch):ob.hide_set(False);ob.select_set(True)
bpy.context.view_layer.objects.active=south;bpy.ops.object.join()
objects.remove(branch);roots.remove(branch)
mod=south.modifiers.new('Local_Wood_Junction_Only','REMESH');mod.mode='VOXEL';mod.voxel_size=.025;mod.use_smooth_shade=False
bpy.ops.object.modifier_apply(modifier=mod.name);clean(south)
for face in south.data.polygons:face.material_index=3

bpy.context.view_layer.update()
checks=[]
def check(name,ok,**details):checks.append({'name':name,'passed':bool(ok),**details})
tree=bvh(objects)
def down(x,z):
    hit,_,_,_=tree.ray_cast(bl((x,8,z)),bl((0,-1,0)),10)
    return gd(hit).y if hit is not None else None
v=[gd(ob.matrix_world@p.co) for ob in objects for p in ob.data.vertices]
mins=[min(p[i] for p in v) for i in range(3)];maxs=[max(p[i] for p in v) for i in range(3)]
check('all_actual_vertices_in_envelope',all(mins[i]>=a-1e-5 and maxs[i]<=b+1e-5 for i,(a,b) in enumerate(zip((0,0,-1.5),(3.75,5.25,1.5)))),minimum=mins,maximum=maxs)
for j,(z,y) in enumerate(sections[0][1]):
    got=down(.00001,z*.999999);check('west_join_'+str(j),got is not None and abs(got-y)<.0002,actual=got,expected=y)
for label,x,y,w in [('lip',3.5,5.25,1.5),('nose',3.74999,5.20,1.49)]:
    vals=[down(x,-w+.00001+(2*w-.00002)*i/30) for i in range(31)]
    check(label+'_full_width',all(t is not None and abs(t-y)<.0002 for t in vals),values=vals,expected=y)
central=[]
for i in range(41):
    x=.001+3.748*i/40
    for z in (-.85,-.425,0,.425,.85):central.append({'x':x,'z':z,'actual':down(x,z),'expected':top_height(x,z)})
check('central_carrying_strip_exact_205',all(v['actual'] is not None and abs(v['actual']-v['expected'])<.0002 for v in central),samples=central)
for ob in anchors:check('anchor_'+ob.name,(gd(ob.matrix_world.translation)-Vector(prior['anchors_godot_local'][ob.name])).length<1e-7)
for ob in objects:
    bm=bmesh.new();bm.from_mesh(ob.data);bad=sum(not e.is_manifold for e in bm.edges);volume=bm.calc_volume(signed=True)
    zero=sum(f.calc_area()<1e-10 for f in bm.faces);bm.free()
    check('closed_'+ob.name,bad==0,nonmanifold_edges=bad)
    check('solid_'+ob.name,volume>0 and zero==0,volume=volume,zero_faces=zero)
check('source_p3_unchanged',sha(P3/'growth_approach_west_p3.blend')=='4a537c76d878d28b75cbfc6dda9bafbb58e79b17edb0f9f72e090980a8828d92')
for ob in objects:ob.data.calc_loop_triangles()
report={'status':'form_only_pending_first_image_review','inputs':{'layout_sha256':sha(LAYOUT),'reference_sha256':sha(REFERENCE),'script_sha256':sha(__file__)},'world_origin':[-14.5,0,25],'local_bounds':[mins,maxs],
 'method':'independent oblique thick hulls; measured local roof clipping; unequal solid joins; continuous custom-section editable root curves',
 'mesh_count':len(objects),'triangles':sum(len(ob.data.loop_triangles) for ob in objects),'root_paths':root_paths,'anchors':prior['anchors_godot_local'],'checks':checks,'failures':[c for c in checks if not c['passed']],
 'limits':['first basic-color form only; no PBR or GLB','offline not game camera capture','no player physics/real assembly/visual pass','root/stone embedding is deliberate; expensive self-crossing audit deferred until shape review']}

# Neutral display scene, same default game view direction as P1-P3.
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.025));ground=bpy.context.object;ground.name='PreviewGround_NotAsset'
ground.data.materials.append(material('PreviewNeutral',(.135,.155,.15)))
target=bl((1.85,2.6,0))
bpy.ops.object.camera_add();camera=bpy.context.object;camera.name='DefaultDirectionPreview';scene.camera=camera
camera.location=target+bl((32,39,32));camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.type='ORTHO';camera.data.ortho_scale=8.1
def area(name,p,power,size):
    bpy.ops.object.light_add(type='AREA',location=bl(p));ob=bpy.context.object;ob.name=name;ob.data.energy=power;ob.data.shape='DISK';ob.data.size=size
    ob.rotation_euler=(target-ob.location).to_track_quat('-Z','Y').to_euler()
area('BroadKey',(-3,11,8),1700,7);area('SoftFill',(8,7,-3),950,6)
scene.world=bpy.data.worlds.new('NeutralWorld');scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.25,.28,.30,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.35
for ob in construction.objects:hide(ob)
blend=BASE/'growth_approach_west_p4.blend';bpy.ops.wm.save_as_mainfile(filepath=str(blend),check_existing=False)
report['blend_sha256']=sha(blend)
(BASE/'geometry_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print('WEST_P4_CHECKS',json.dumps({'checks':len(checks),'failures':[c['name'] for c in report['failures']],'triangles':report['triangles']},ensure_ascii=False),flush=True)
# Root requested exactly one form image before further audits/iterations.
# Any quick numerical failure remains explicit in the report and stops promotion.
scene.render.filepath=str(BASE/'west_p4_default_direction.png');bpy.ops.render.render(write_still=True)
report['preview']={'path':'west_p4_default_direction.png','sha256':sha(BASE/'west_p4_default_direction.png'),'direction':[32,39,32],'not_game_screenshot':True}
(BASE/'geometry_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print('WEST_P4_FORM_READY',flush=True)
