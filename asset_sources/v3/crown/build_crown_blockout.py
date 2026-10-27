"""Crown beast: editable silhouette study, not a final/export-ready asset.
Blender 5.2.1; CPU two threads. No GLB is exported by this script.
Coordinates in authoring helpers are Godot metres, +Y up, +Z front.
Usage: blender -b --factory-startup -t 2 --python-exit-code 1 --python THIS -- [--no-render]
"""
import bpy, math, json, sys, hashlib
from pathlib import Path
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

SOURCE=Path(__file__).resolve().parent
PROJECT=SOURCE.parents[2]
ART=PROJECT/'artifacts/v3/art/crown'
SOURCE.mkdir(parents=True,exist_ok=True); ART.mkdir(parents=True,exist_ok=True)
NO_RENDER='--no-render' in sys.argv
VERSION='v4'
REFERENCE=PROJECT/'references/v3/production/crown/parasitic_crown_reference_v1.png'
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
scene=bpy.context.scene
scene.unit_settings.system='METRIC'; scene.unit_settings.scale_length=1.0
scene.render.engine='CYCLES'; scene.cycles.device='CPU'; scene.cycles.samples=10
scene.cycles.use_denoising=True
scene.render.threads_mode='FIXED'; scene.render.threads=2
scene.render.resolution_x=1100; scene.render.resolution_y=850; scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX'; scene.view_settings.look='AgX - Medium High Contrast'
model=bpy.data.collections.new('Crown_EDITABLE_MASTER'); scene.collection.children.link(model)
studio=bpy.data.collections.new('Studio_NOT_EXPORTED'); scene.collection.children.link(studio)
meshes=[]; pivots={}; contacts={}

def bp(p): return Vector((p[0],-p[2],p[1]))
def gp(p): return [float(p.x),float(p.z),float(-p.y)]
def relocate(o,collection):
    for c in list(o.users_collection): c.objects.unlink(o)
    collection.objects.link(o)

def material(name,level):
    m=bpy.data.materials.new(name); m.use_nodes=True
    rgb=level if isinstance(level,tuple) else (level,level,level)
    n=m.node_tree.nodes.get('Principled BSDF'); n.inputs['Base Color'].default_value=(*rgb,1)
    n.inputs['Roughness'].default_value=.88
    return m
STONE=material('STUDY_WarmStone',(.44,.405,.33))
ROOT=material('STUDY_ChestnutRoot',(.19,.10,.045))
LEAF=material('STUDY_OliveMembrane',(.18,.22,.065))
# Three flat colour families only. The seed uses stone clay for legibility;
# its eventual amber colour/emission is deliberately outside this form study.
CORE=STONE
CAVITY=ROOT

def empty(name,at=(0,0,0),parent=None):
    o=bpy.data.objects.new(name,None); model.objects.link(o)
    o.empty_display_type='PLAIN_AXES'; o.empty_display_size=.24
    if parent: o.parent=parent
    o.matrix_world=Matrix.Translation(bp(at)); bpy.context.view_layer.update()
    pivots[name]=o
    return o

root=empty('ParasiticCrown')
root['status']='silhouette_study_not_integrated'
root['game_forward']='+Z'; root['body_origin']='centre; support contacts Y=-3m'
root['reference_sha256']=hashlib.sha256(REFERENCE.read_bytes()).hexdigest()

def mesh(name,verts,faces,mat,parent=root,smooth=False):
    data=bpy.data.meshes.new(name+'_Mesh')
    data.from_pydata([bp(v) for v in verts],[],faces); data.update()
    o=bpy.data.objects.new(name,data); model.objects.link(o)
    data.materials.append(mat)
    for poly in data.polygons: poly.use_smooth=smooth
    o.parent=parent; o.matrix_parent_inverse=parent.matrix_world.inverted()
    o['stage']='editable primary form; UV/PBR not finalized'
    meshes.append(o)
    return o

def curve_samples(points,radii,steps=5):
    points=[Vector(p) for p in points]; values=[]
    for i in range(len(points)-1):
        a=points[max(0,i-1)]; b=points[i]; c=points[i+1]; d=points[min(len(points)-1,i+2)]
        for j in range(steps):
            t=j/steps
            p=.5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t)
            r=radii[i]*(1-t)+radii[i+1]*t
            values.append((p,r))
    values.append((points[-1],radii[-1]))
    return values

def tube(name,points,radii,mat=ROOT,parent=root,sides=10,steps=5,flatten=1.0,twist=0.0,knots=0.0):
    samples=curve_samples(points,radii,steps); tip=samples[-1][1] <= 1e-6
    ring_samples=samples[:-1] if tip else samples
    verts=[]; faces=[]
    last_normal=None
    for i,(p,r) in enumerate(ring_samples):
        before=samples[max(0,i-1)][0]; after=samples[min(len(samples)-1,i+1)][0]
        tangent=(after-before).normalized()
        guide=Vector((0,1,0)) if abs(tangent.y)<.88 else Vector((0,0,1))
        normal=tangent.cross(guide).normalized() if last_normal is None else (last_normal-tangent*last_normal.dot(tangent)).normalized()
        across=tangent.cross(normal).normalized(); last_normal=normal
        along=i/max(1,len(ring_samples)-1)
        for j in range(sides):
            angle=2*math.pi*j/sides+twist*(along+.16*math.sin(along*math.pi*2))
            # Broad noncircular root sections, not equal-diameter cylinders.
            section=1+.15*math.cos(angle*3+i*.045)+.075*math.sin(angle*5+i*.055)
            burl=1+knots*(math.exp(-((along-.25)/.095)**2)*(.62+.38*math.cos(angle-.8))
                         +math.exp(-((along-.62)/.11)**2)*(.60+.40*math.cos(angle+1.1))
                         +.5*math.exp(-((along-.87)/.075)**2)*(.65+.35*math.cos(angle-2.0)))
            local_flat=flatten*(1-.15*math.sin(along*math.pi*2+.35)) if knots else flatten
            q=p+normal*(math.cos(angle)*r*section*burl)+across*(math.sin(angle)*r*local_flat*section*burl)
            verts.append(tuple(q))
    for i in range(len(ring_samples)-1):
        for j in range(sides): faces.append((i*sides+j,i*sides+(j+1)%sides,(i+1)*sides+(j+1)%sides,(i+1)*sides+j))
    faces.append(tuple(range(sides-1,-1,-1)))
    if tip:
        index=len(verts); verts.append(tuple(samples[-1][0])); base=(len(ring_samples)-1)*sides
        for j in range(sides): faces.append((base+j,base+(j+1)%sides,index))
    else: faces.append(tuple((len(ring_samples)-1)*sides+j for j in range(sides)))
    return mesh(name,verts,faces,mat,parent,True)

def stone_plate(name,outline,z,thickness,parent=root,lean=.0,lean_x=.0,phase=.0):
    """Irregular solid plate: broad bevel band, raised unequal facets, no texture noise."""
    centre=Vector((sum(p[0] for p in outline)/len(outline),sum(p[1] for p in outline)/len(outline)))
    n=len(outline); verts=[]
    for ring in range(3):
        for i,p in enumerate(outline):
            point=Vector(p)
            if ring==2: point=centre+(point-centre)*(.69+.105*math.sin(i*1.7+phase))
            depth=z+lean*(point.y-centre.y)+lean_x*(point.x-centre.x)
            depth += (-thickness*(.88+.13*math.sin(i+phase)) if ring==0 else (.03+.035*math.sin(i*1.3+phase) if ring==1 else thickness*(.52+.17*math.sin(i*1.9+phase))))
            verts.append((point.x,point.y,depth))
    peak=len(verts); verts.append((centre.x+.05,centre.y+.09,z+thickness*.49))
    faces=[]
    faces.append(tuple(range(n-1,-1,-1)))
    for ring in range(2):
        for j in range(n): faces.append((ring*n+j,ring*n+(j+1)%n,(ring+1)*n+(j+1)%n,(ring+1)*n+j))
    for j in range(n): faces.append((2*n+j,2*n+(j+1)%n,peak))
    return mesh(name,verts,faces,STONE,parent,False)

def broken_shell(name,outline,centre,thickness=.32):
    """Wide stone cap wrapping the seed sac; solid irregular shell, no spike fan."""
    n=len(outline); centre=Vector(centre); verts=[]
    verts.extend((x,y-thickness*(.9+.1*math.sin(i*1.4)),z) for i,(x,y,z) in enumerate(outline))
    verts.extend(outline)
    for i,p in enumerate(outline):
        q=Vector(p).lerp(centre,.28+.075*math.sin(i*1.7));q.y+=.08+.035*math.sin(i*1.3)
        verts.append(tuple(q))
    verts.append(tuple(centre)); peak=len(verts)-1
    faces=[tuple(range(n-1,-1,-1))]
    for r in range(2):
        for j in range(n): faces.append((r*n+j,r*n+(j+1)%n,(r+1)*n+(j+1)%n,(r+1)*n+j))
    for j in range(n): faces.append((2*n+j,2*n+(j+1)%n,peak))
    return mesh(name,verts,faces,STONE)

# Continuous torso sleeve, front rim and genuine recessed cavity. No sphere body.
N=24; verts=[]; faces=[]
profiles=[(-1.75,.60,.65,-.10),(-1.25,1.38,1.13,-.10),(-.4,1.72,1.31,-.16),(.55,1.68,1.27,-.22),(1.25,1.37,1.13,-.28),(1.60,.90,.90,-.48),(.70,.78,.78,-.48)]
for k,(z,rx,ry,cy) in enumerate(profiles):
    for j in range(N):
        a=j*2*math.pi/N
        factor=1+.075*math.sin(3*a+k*.6)+.025*math.cos(5*a-k*.9)
        verts.append((math.cos(a)*rx*factor,cy+math.sin(a)*ry*factor,z+.06*math.cos(a*2+k)))
for k in range(len(profiles)-1):
    for j in range(N): faces.append((k*N+j,k*N+(j+1)%N,(k+1)*N+(j+1)%N,(k+1)*N+j))
faces.append(tuple(range(N-1,-1,-1)))
mesh('Torso_ContinuousRootSleeve',verts,faces,ROOT,smooth=True)
mesh('CoreCavity_Back',[(math.cos(j*2*math.pi/N)*.8,-.48+math.sin(j*2*math.pi/N)*.8,.65) for j in range(N)],[tuple(range(N))],CAVITY)

# Seed body is a pointed, faceted kernel inside the real opening.
seed_verts=[]; seed_faces=[]; seed_rows=13; seed_sides=14
for i in range(seed_rows):
    t=i/(seed_rows-1); y=-1.34+t*1.64; radius=math.sin(math.pi*t)**.72
    for j in range(seed_sides):
        a=2*math.pi*j/seed_sides
        seed_verts.append((.54*radius*math.cos(a),y,1.06+.41*radius*math.sin(a)))
for i in range(seed_rows-1):
    for j in range(seed_sides): seed_faces.append((i*seed_sides+j,i*seed_sides+(j+1)%seed_sides,(i+1)*seed_sides+(j+1)%seed_sides,(i+1)*seed_sides+j))
core_mesh=mesh('CoreSeed',seed_verts,seed_faces,CORE,smooth=False)
core=empty('Core',(0,-.50,1.09),root)
core['purpose']='weakpoint anchor inside recessed seed; final hurtbox measured after approved shell'

# Thick split roots frame, rather than fill, the mouth recess.
for side in [-1,1]:
    tube('JawRoot_'+str(side),[(side*1.34,-.52,1.17),(side*.98,-1.13,1.55),(side*.48,-1.54,1.50),(side*.18,-1.72,1.13)],[.32,.28,.18,.035],steps=7,flatten=.67,twist=.65*side,knots=.23)
    tube('BrowRoot_'+str(side),[(side*1.38,.08,1.01),(side*.93,.62,1.20),(side*.42,.63,1.37),(side*.18,.25,1.38)],[.28,.25,.18,.045],steps=7,flatten=.68,twist=.55*side,knots=.20)
    # Rear-to-front growth bundles tie the torso and limb shoulders together.
    for k in range(3):
        tube('TorsoGrowth_%s_%d'%(side,k),[(side*.42,-.38+k*.36,-1.68),(side*1.21,-.65+k*.45,-1.05),(side*1.65,-.79+k*.48,-.2),(side*1.38,-.38+k*.34,.67)],[.24,.30,.29,.16],steps=7,flatten=.58,twist=.8*side,knots=.25)
    tube('BackBearingRoot_'+str(side),[(side*.38,-.36,-1.88),(side*.94,.50,-1.30),(side*.77,1.19,-.55),(side*.46,1.10,.37),(side*1.34,.06,.80)],[.15,.32,.29,.31,.26],steps=7,flatten=.61,twist=1.05*side,knots=.20)

plate_l=empty('CrownPlatePivot_L',(-1.34,.50,.62),root)
plate_r=empty('CrownPlatePivot_R',(1.34,.46,.62),root)
plate_c=empty('CrownPlatePivot_C',(0,.60,1.10),root)
# Unequal load-bearing fractured rocks. Large pieces overlap at cracks and all
# fragments of a valve retain the existing shared moving pivot.
stone_plate('CrownArmor_L_Jaw',[(-1.72,-.30),(-1.80,.35),(-1.55,.73),(-1.10,.97),(-.71,.84),(-.47,.54),(-.13,.43),(.055,.10),(.055,-.74),(-.08,-1.21),(-.43,-1.44),(-.83,-1.04),(-1.21,-.77)],1.76,.56,plate_l,lean=-.16,lean_x=-.13,phase=.4)
stone_plate('CrownArmor_L_Crest',[(-1.72,.57),(-1.70,1.21),(-1.56,1.73),(-1.55,2.27),(-1.27,2.46),(-1.07,2.30),(-1.04,1.86),(-.86,1.70),(-.73,1.19),(-.57,.94),(-.76,.65),(-1.19,.42)],1.56,.49,plate_l,lean=-.24,lean_x=.09,phase=1.2)
stone_plate('CrownArmor_R_Jaw',[(-.055,-.79),(-.055,.12),(.20,.45),(.56,.55),(.77,.83),(1.20,.76),(1.55,.45),(1.80,.14),(1.65,-.48),(1.29,-.77),(.95,-.92),(.61,-1.29),(.25,-1.40)],1.79,.59,plate_r,lean=.05,lean_x=.13,phase=2.1)
stone_plate('CrownArmor_R_Crest',[(.66,.70),(.80,1.18),(.93,1.37),(1.03,1.87),(1.33,2.20),(1.55,2.14),(1.58,1.74),(1.75,1.45),(1.71,.98),(1.82,.66),(1.31,.39),(.96,.50)],1.47,.52,plate_r,lean=.09,lean_x=-.17,phase=3.0)
stone_plate('CrownArmor_C_Brow',[(-.70,.18),(-.87,.64),(-.70,1.06),(-.31,1.38),(.15,1.30),(.48,1.40),(.75,1.04),(.65,.64),(.54,.20)],1.41,.52,plate_c,lean=-.16,lean_x=-.08,phase=1.7)
stone_plate('CrownArmor_C_Crest',[(-.68,1.12),(-.53,1.70),(-.40,2.14),(-.35,2.58),(-.17,2.79),(.14,2.91),(.29,2.71),(.24,2.35),(.40,2.00),(.38,1.65),(.60,1.39),(.27,1.08),(-.19,1.21)],1.09,.47,plate_c,lean=-.22,lean_x=.08,phase=.9)

# Three broad, thick, broken caps enclose the dorsal seed sac instead of
# standing small spikes on a bare smooth ball. The seams expose load-bearing roots.
broken_shell('DorsalShell_L',[(-.22,1.31,.28),(-.62,1.43,.68),(-1.11,1.13,.73),(-1.46,.79,.42),(-1.73,.48,.22),(-1.79,.27,-.18),(-1.62,.31,-.56),(-1.70,.16,-.82),(-1.32,.66,-1.17),(-.78,1.16,-1.01),(-.60,1.40,-.59),(-.35,1.37,-.37)],(-.93,1.85,-.20),.49)
broken_shell('DorsalShell_R',[(.32,1.31,.35),(.73,1.49,.68),(1.13,1.28,.59),(1.40,.98,.31),(1.77,.44,.16),(1.86,.18,-.32),(1.62,.27,-.59),(1.67,.16,-.93),(1.29,.58,-1.27),(.82,1.04,-1.09),(.69,1.21,-.71),(.45,1.34,-.39)],(1.08,1.70,-.32),.54)
broken_shell('DorsalShell_Rear',[(-.71,1.06,-.89),(-.30,1.39,-.65),(.10,1.40,-.78),(.53,1.14,-1.08),(.71,.70,-1.40),(.42,.45,-1.77),(-.13,.34,-1.96),(-.37,.57,-1.75),(-.68,.64,-1.64),(-.85,.91,-1.27)],(-.15,1.58,-1.24),.43)

limb_specs={
 'FL':{'shoulder':(-1.33,-.28,.42),'elbow':(-2.82,.12,.31),'wrist':(-2.73,-1.52,1.38),'palm':(-2.54,-2.02,1.60),'front':True},
 'FR':{'shoulder':(1.35,-.36,.48),'elbow':(2.79,-.36,.67),'wrist':(2.79,-1.68,1.45),'palm':(2.51,-2.10,1.65),'front':True},
 'BL':{'shoulder':(-1.21,-.43,-.91),'elbow':(-2.61,-.80,-1.66),'wrist':(-2.65,-1.99,-2.01),'palm':(-2.28,-2.27,-1.93),'front':False},
 'BR':{'shoulder':(1.22,-.40,-.92),'elbow':(2.58,-.59,-1.57),'wrist':(2.70,-1.96,-1.98),'palm':(2.31,-2.23,-1.91),'front':False}}
for key,spec in limb_specs.items():
    s=Vector(spec['shoulder']); e=Vector(spec['elbow']); w=Vector(spec['wrist']); p=Vector(spec['palm'])
    front=spec['front']; side=-1 if s.x<0 else 1; direction=1 if front else -1
    shoulder=empty('ClawShoulder_'+key,tuple(s),root)
    wrist=empty('ClawWrist_'+key,tuple(w),shoulder)
    middle=s.lerp(e,.48)+Vector((0,.08,.16*direction))
    arm_end=w+(w-e).normalized()*.24
    # Two unequal structural roots split at the shoulder, cross around the elbow,
    # expose a deep longitudinal cleft, and meet again inside the wrist knot.
    primary_elbow=e+Vector((-side*.06,.12,.17*direction))
    primary_forearm=e.lerp(w,.54)+Vector((-side*.12,.04,.18*direction))
    tube('RootArmPrimary_'+key,[tuple(s),tuple(middle),tuple(primary_elbow),tuple(primary_forearm),tuple(arm_end)],[.58,.43,.41,.29,.32],parent=shoulder,sides=13,steps=7,flatten=.71,twist=1.10*side,knots=.31)
    branch_mid=s.lerp(e,.63)+Vector((side*.12,.31,-.14*direction))
    branch_elbow=e+Vector((side*.17,-.10,-.25*direction))
    branch_forearm=e.lerp(w,.52)+Vector((side*.14,-.04,-.25*direction))
    tube('RootArmFork_'+key,[tuple(s+Vector((side*.08,.08,-.08*direction))),tuple(branch_mid),tuple(branch_elbow),tuple(branch_forearm),tuple(w+Vector((side*.05,0,-.03*direction)))],[.40,.27,.32,.22,.36],parent=shoulder,sides=12,steps=7,flatten=.62,twist=-1.05*side,knots=.27)
    palm_start=w+Vector((0,.36,-.16*direction))
    palm_size=1.15 if front else 1.0
    palm_radii=[r*palm_size for r in [.27,.48,.56,.43,.25]]
    tube('RootPalm_'+key,[tuple(palm_start),tuple(w),tuple(w.lerp(p,.55)),tuple(p),tuple(p+Vector((0,-.10,.20*direction)))],palm_radii,parent=wrist,sides=13,steps=7,flatten=.63,twist=1.12*side,knots=.29)
    # One load path grows from the inner shoulder across the elbow and forks
    # into the wrist; it changes the silhouette instead of decorating a pipe.
    wrap_points=[s+Vector((-side*.05,.24,.03)),middle+Vector((side*.03,.22,.19*direction)),primary_elbow+Vector((side*.15,.05,.14*direction)),e.lerp(w,.58)+Vector((side*.30,-.04,.04)),w+Vector((side*.12,-.05,.01))]
    tube('RootArmCrossBranch_'+key,[tuple(q) for q in wrap_points],[.22,.26,.19,.25,.14],parent=shoulder,sides=11,steps=7,flatten=.53,twist=-.8*side,knots=.23)
    for finger in range(3):
        offset=(finger-1)*(.43 if front else .34)
        base=p+Vector((offset,.10,.10*direction))
        knuckle=base+Vector((offset*.16,.13+(finger%2)*.07,.37*direction))
        hook=base+Vector((offset*.22,-.32,.60*direction))
        tip=Vector((base.x+offset*.18,-3.0,base.z+.47*direction))
        buried_base=base+Vector((-offset*.18,.15,-.26*direction))
        neck=base.lerp(knuckle,.43)
        tube('GraspDigit_%s_%d'%(key,finger),[tuple(buried_base),tuple(base),tuple(neck),tuple(knuckle),tuple(hook),tuple(tip)],[.30 if front else .22,.26 if front else .20,.19 if front else .15,.30 if front else .23,.13,0],parent=wrist,sides=11,steps=6,flatten=.66,twist=.40*side)
        # Broad palm roots feed each finger; the three knuckles are offset and
        # unequal, rather than three identical hooked tubes planted in a cuff.
        feed_start=w+Vector((offset*.22,.02,-.08*direction))
        feed_mid=w.lerp(base,.52)+Vector((offset*.37,.15,.08*direction))
        tube('PalmFork_%s_%d'%(key,finger),[tuple(feed_start),tuple(feed_mid),tuple(base),tuple(knuckle)],[.24 if front else .18,.20 if front else .16,.15,.08],parent=wrist,sides=9,steps=5,flatten=.58,twist=.65*side,knots=.18)
    contact_point=(p.x,-3.0,p.z+.57*direction)
    contacts[key]=empty('ClawContact_'+key,contact_point,wrist)
    contacts[key]['purpose']='authoring grasp/ground contact; nearest central hook tip'
    # A broad wrist scute, with a single asymmetric ridge, gives claws their weight.
    if front:
        x=p.x
        stone_plate('ClawScute_'+key,[(x-.51,-2.45),(x-.65,-1.80),(x-.40,-1.25),(x-.19,-1.00),(x+.14,-.96),(x+.42,-1.47),(x+.52,-2.14),(x+.22,-2.60)],p.z+.09,.31,wrist,lean=-.21)
    else:
        x=p.x
        stone_plate('ClawScute_'+key,[(x-.32,-2.51),(x-.42,-1.86),(x-.10,-1.45),(x+.36,-1.99),(x+.28,-2.50)],p.z-.04,.17,wrist,lean=.08)

def membrane(side):
    pivot=empty('LeafPivot_'+('L' if side<0 else 'R'),(side*.95,.65,-1.15),root)
    points=[(side*.95,.65,-1.15),(side*1.35,1.48,-1.73),(side*1.73,2.16,-2.22),
            (side*1.98,1.53,-2.58),(side*2.60,1.55,-2.20),(side*2.43,.73,-2.42),
            (side*2.14,.29,-2.67),(side*1.65,.52,-1.92)]
    centre=(side*1.69,1.00,-1.98)
    verts=points+[centre]+[(x,y-.045,z) for x,y,z in points]+[(centre[0],centre[1]-.045,centre[2])]
    faces=[]; n=len(points)
    for i in range(n):
        j=(i+1)%n
        faces.extend([(i,j,n),(n+1+j,n+1+i,2*n+1),(i,n+1+i,n+1+j,j)])
    mesh('LeafMembrane_'+str(side),verts,faces,LEAF,pivot,False)
    tube('LeafSpar_'+str(side),[points[0],points[1],points[2]],[.18,.15,.035],parent=pivot,sides=8,steps=5)
    tube('LeafOuterRib_'+str(side),[points[1],centre,points[4],points[6]],[.13,.105,.07,0],parent=pivot,sides=7,steps=4)
    tube('LeafLowerRib_'+str(side),[points[0],centre,points[6]],[.12,.09,0],parent=pivot,sides=7,steps=4)
membrane(-1); membrane(1)

rest={name:o.matrix_basis.copy() for name,o in pivots.items()}
def pose(opened=False):
    for name,o in pivots.items(): o.matrix_basis=rest[name].copy()
    if opened:
        plate_l.matrix_basis=rest['CrownPlatePivot_L']@Matrix.Rotation(math.radians(-48*float(opened)),4,'Z')
        plate_r.matrix_basis=rest['CrownPlatePivot_R']@Matrix.Rotation(math.radians(48*float(opened)),4,'Z')
        plate_c.matrix_basis=rest['CrownPlatePivot_C']@Matrix.Rotation(math.radians(-32*float(opened)),4,'X')
    bpy.context.view_layer.update()

def report_pose():
    coords=[gp(o.matrix_world@v.co) for o in meshes for v in o.data.vertices]
    farthest=max(((math.hypot(p[0],p[2]),o.name,p) for o in meshes for v in o.data.vertices for p in [gp(o.matrix_world@v.co)]),key=lambda item:item[0])
    return {'godot_min':[min(p[i] for p in coords) for i in range(3)],'godot_max':[max(p[i] for p in coords) for i in range(3)],
            'horizontal_radius':farthest[0],'radius_witness':{'mesh':farthest[1],'godot_vertex':farthest[2]},'vertices':len(coords)}

def blocker_ray(source,target):
    vs=[]; fs=[]
    for o in meshes:
        if o==core_mesh: continue
        start=len(vs);vs.extend(o.matrix_world@v.co for v in o.data.vertices)
        fs.extend(tuple(start+i for i in p.vertices) for p in o.data.polygons)
    tree=BVHTree.FromPolygons(vs,fs)
    a=bp(source); b=bp(target); delta=b-a
    hit=tree.ray_cast(a,delta.normalized(),delta.length)
    return {'blocked':hit[0] is not None,'distance':float(hit[3]) if hit[0] is not None else None}

scene.world.use_nodes=True
world_background=scene.world.node_tree.nodes.get('Background')
world_background.inputs['Color'].default_value=(.28,.28,.28,1);world_background.inputs['Strength'].default_value=.55
floor_mat=material('StudioGrey',.32)
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-3.02)); floor=bpy.context.object;floor.name='StudioFloor_NOT_EXPORTED';floor.data.materials.append(floor_mat);relocate(floor,studio)
def light(name,at,energy,size):
    data=bpy.data.lights.new(name,'AREA'); data.energy=energy; data.shape='DISK';data.size=size
    o=bpy.data.objects.new(name,data);studio.objects.link(o);o.location=bp(at)
    o.rotation_euler=(bp((0,-.3,0))-o.location).to_track_quat('-Z','Y').to_euler()
light('Key',(-6,9,7),1350,7)
light('Fill',(7,3,5),850,6)
light('Rim',(0,6,-8),1550,5)
camera_data=bpy.data.cameras.new('CrownReviewCamera');camera=bpy.data.objects.new('CrownReviewCamera',camera_data);studio.objects.link(camera);scene.camera=camera
camera_data.type='ORTHO';camera_data.ortho_scale=10.6
def set_camera(at,target=(0,-.12,0),scale=10.6):
    camera.location=bp(at);camera.rotation_euler=(bp(target)-camera.location).to_track_quat('-Z','Y').to_euler();camera_data.ortho_scale=scale
set_camera((9,8,12))
report={'stage':'three_colour_form_'+VERSION+'_not_approved','reference_sha256':root['reference_sha256'],'script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'software':bpy.app.version_string,'cpu_threads':2,
        'triangles':sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in meshes),'editable_meshes':len(meshes),'final_glb_exported':False,'poses':{},'pivots':{}}
for name,o in pivots.items():
    report['pivots'][name]={'godot_world_rest':gp(o.matrix_world.translation),'parent':o.parent.name if o.parent else None,'blender_local_translation':list(o.location)}
report['pivot_checks']={}
for key,contact in contacts.items():
    shoulder=pivots['ClawShoulder_'+key]; wrist=pivots['ClawWrist_'+key]
    contact_before=contact.matrix_world.translation.copy()
    digit=bpy.data.objects['GraspDigit_%s_1'%key]
    nearest=min((digit.matrix_world@v.co-contact_before).length for v in digit.data.vertices)
    checks={'rest_contact_y':gp(contact_before)[1],'central_tip_distance':nearest}
    for joint,axis in [(shoulder,'Z'),(wrist,'X')]:
        old_world=joint.matrix_world.copy()
        joint.matrix_basis=rest[joint.name]@Matrix.Rotation(math.radians(12),4,axis)
        bpy.context.view_layer.update()
        expected=joint.matrix_world@old_world.inverted()@contact_before
        checks[joint.name]={'motion_m':(contact.matrix_world.translation-contact_before).length,
                            'transform_error_m':(contact.matrix_world.translation-expected).length}
        pose(False)
    report['pivot_checks'][key]=checks
report['root_identity_error']=max(abs(root.matrix_world[i][j]-(1.0 if i==j else 0.0)) for i in range(4) for j in range(4))
report['armor_sweep_samples']=[]
for openness in [0.0,.25,.5,.75,1.0]:
    pose(openness); bounds=report_pose()
    report['armor_sweep_samples'].append({'openness':openness,'horizontal_radius':bounds['horizontal_radius'],'min_y':bounds['godot_min'][1],'max_y':bounds['godot_max'][1]})
for label,opened in [('closed',False),('open',True)]:
    pose(opened);report['poses'][label]=report_pose()
    report['poses'][label]['core_front_ray']=blocker_ray((0,-.50,6),(0,-.50,1.09))
    report['poses'][label]['core_oblique_ray']=blocker_ray((2.5,1.2,6),(0,-.50,1.09))
    targets=[(x,y,1.09) for x in [-.25,0,.25] for y in [-.85,-.50,-.15]]
    report['poses'][label]['central_core_front_samples']={'count':len(targets),'blocked':sum(1 for target in targets if blocker_ray((target[0],target[1],6),target)['blocked'])}
    if not NO_RENDER:
        scene.render.filepath=str(ART/('crown_'+label+'_form_'+VERSION+'.png'));bpy.ops.render.render(write_still=True)
        report['poses'][label]['preview']={'path':str(Path(scene.render.filepath).relative_to(PROJECT)),'sha256':hashlib.sha256(Path(scene.render.filepath).read_bytes()).hexdigest()}
        print('CROWN_PREVIEW_READY',scene.render.filepath,flush=True)
pose(False);set_camera((9,8,12))
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'parasitic_crown_blockout.blend'))
report['source_sha256']=hashlib.sha256((SOURCE/'parasitic_crown_blockout.blend').read_bytes()).hexdigest()
report['constraints']={'default_and_open_radius_le4':all(p['horizontal_radius']<=4.001 for p in report['poses'].values()),
    'default_and_open_vertical_within3':all(p['godot_min'][1]>=-3.001 and p['godot_max'][1]<=3.001 for p in report['poses'].values()),
    'core_closed_blocks':report['poses']['closed']['core_front_ray']['blocked'],
    'core_open_front_clear':not report['poses']['open']['core_front_ray']['blocked'],
    'closed_central_core_samples_all_blocked':report['poses']['closed']['central_core_front_samples']['blocked']==9,
    'open_central_core_samples_all_clear':report['poses']['open']['central_core_front_samples']['blocked']==0,
    'armor_sweep_samples_within_envelope':all(p['horizontal_radius']<=4.001 and p['min_y']>=-3.001 and p['max_y']<=3.001 for p in report['armor_sweep_samples'])}
(ART/('crown_blockout_report_'+VERSION+'.json')).write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('CROWN_BLOCKOUT_REPORT',json.dumps(report['constraints']),flush=True)
if not all(report['constraints'].values()):
    raise RuntimeError('Crown form contract failed: '+', '.join(k for k,v in report['constraints'].items() if not v))
