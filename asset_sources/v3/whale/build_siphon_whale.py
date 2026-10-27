"""Original I-B siphon whale. Godot coordinates in helpers, Blender Z-up source."""
from pathlib import Path
import bpy,math,json,sys
from mathutils import Vector
REV=int(sys.argv[sys.argv.index('--revision')+1]) if '--revision' in sys.argv else 1
ROOT=Path(__file__).resolve().parents[3]
SRC=ROOT/'asset_sources/v3/whale';OUT=ROOT/'assets/v3/whale';EVID=ROOT/'artifacts/v3/art/whale'
for p in (SRC,OUT,EVID):p.mkdir(parents=True,exist_ok=True)
(SRC/'.gdignore').write_text('',encoding='utf-8')
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
scene=bpy.context.scene;scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
col=bpy.data.collections.new('Editable_Whale');scene.collection.children.link(col)
parts=[];groups={}
def pos(v):return Vector((v[0],-v[2],v[1]))
def link(o):
 for c in list(o.users_collection):c.objects.unlink(o)
 col.objects.link(o)
def mat(name,color,metal=.0,rough=.6,emit=0):
 m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True
 bs=m.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(*color,1);bs.inputs['Metallic'].default_value=metal;bs.inputs['Roughness'].default_value=rough
 if emit:bs.inputs['Emission Color'].default_value=(*color,1);bs.inputs['Emission Strength'].default_value=emit
 return m
ivory=mat('Whale_IvoryArmor',(.63,.64,.59),.45,.51)
teal=mat('Whale_TealArmor',(.055,.16,.17),.65,.48)
steel=mat('Whale_BrushedMetal',(.32,.37,.38),.8,.34)
dark=mat('Whale_DarkCavity',(.025,.034,.034),.35,.65)
safety=mat('Whale_SafetyAmber',(.85,.43,.045),.45,.54)
core=mat('Whale_CoreCyan',(.03,.55,.62),.2,.3,2.0)
materials=[ivory,teal,steel,dark,safety,core]
def reg(o,m,group='StaticHull'):
 link(o);o.data.materials.append(m);parts.append(o);groups.setdefault(group,[]).append(o)
 return o
def mesh(name,verts,faces,m,group='StaticHull',smooth=False):
 data=bpy.data.meshes.new(name);data.from_pydata([pos(v) for v in verts],[],faces);data.update()
 o=bpy.data.objects.new(name,data);col.objects.link(o);reg(o,m,group)
 for p in data.polygons:p.use_smooth=smooth
 return o
def bevel(o,w=.04,segments=2):
 mod=o.modifiers.new('Manufactured_edge_radius','BEVEL');mod.width=w;mod.segments=segments
 o.modifiers.new('Weighted_normals','WEIGHTED_NORMAL');return o
def box(name,at,dim,m,group='StaticHull',radius=.04):
 bpy.ops.mesh.primitive_cube_add(size=1,location=pos(at));o=bpy.context.object;o.name=name;o.dimensions=(dim[0],dim[2],dim[1]);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);reg(o,m,group)
 return bevel(o,radius) if radius else o
def cylinder(name,a,b,r,m,group='StaticHull',verts=16):
 a,b=pos(a),pos(b);d=b-a;bpy.ops.mesh.primitive_cylinder_add(vertices=verts,radius=r,depth=d.length,location=(a+b)/2)
 o=bpy.context.object;o.name=name;o.rotation_mode='QUATERNION';o.rotation_quaternion=d.to_track_quat('Z','Y');bpy.ops.object.transform_apply(location=False,rotation=True,scale=True);reg(o,m,group)
 for p in o.data.polygons:p.use_smooth=len(p.vertices)==4
 return o
def loft(name,sections,m,cx=0,theta0=0,theta1=2*math.pi,n=64,group='StaticHull',caps=True,core_recess=False):
 closed=abs(theta1-theta0-2*math.pi)<1e-5;ring=n if closed else n+1;vs=[];fs=[]
 for z,rx,ry,cy in sections:
  for j in range(ring):
   a=theta0+(theta1-theta0)*j/n;vs.append((cx+rx*math.cos(a),cy+ry*math.sin(a),z))
 for i in range(len(sections)-1):
  for j in range(n):
   if core_recess and sections[i][0]>=1.19 and sections[i+1][0]<=4.41 and 13<=j<19:continue
   k=(j+1)%ring;fs.append((i*ring+j,i*ring+k,(i+1)*ring+k,(i+1)*ring+j))
 if caps:
  fs.append(tuple(reversed(range(ring))));fs.append(tuple((len(sections)-1)*ring+j for j in range(ring)))
 o=mesh(name,vs,fs,m,group,True);return o
def extruded_outline(name,outline,y,thick,m,group='StaticHull'):
 # Smooth polygon contour with real thickness; X/Z positions stay authored.
 vs=[(x,y-thick*.5,z) for x,z in outline]+[(x,y+thick*.5,z) for x,z in outline];n=len(outline)
 fs=[tuple(reversed(range(n))),tuple(n+i for i in range(n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
 return bevel(mesh(name,vs,fs,m,group),min(.07,thick*.2),2)
def ellipse_rim(name,c,rx,ry,tube,m,n=64,group='StaticHull'):
 vs=[];fs=[]
 for j in range(n):
  a=2*math.pi*j/n
  for k in range(8):
   b=2*math.pi*k/8;vs.append((c[0]+(rx+tube*math.cos(b))*math.cos(a),c[1]+(ry+tube*math.cos(b))*math.sin(a),c[2]+tube*math.sin(b)))
 for j in range(n):
  for k in range(8):fs.append((j*8+k,((j+1)%n)*8+k,((j+1)%n)*8+(k+1)%8,j*8+(k+1)%8))
 return mesh(name,vs,fs,m,group,True)

# Hull sections are recorded for the root's future sectional collision wrapper.
HULL=[(-8.55,.52,.43,1.15),(-7.6,.70,.56,.94),(-6.4,1.05,.72,.58),(-5.2,1.60,.92,.25),(-4.0,2.35,1.15,.08),(-2.5,3.35,1.60,0),(-1.0,4.24,2.00,.10),(0,4.65,2.15,.15),(1.2,4.9,2.3,.15),(2.2,4.98,2.3,.15),(3.2,4.87,2.15,.10),(4.4,4.62,1.95,0),(5.5,4.25,1.75,-.10),(6.45,3.80,1.53,-.20)]
loft('Whale_continuous_curved_hull',HULL,ivory,caps=False,core_recess=True)
loft('Tail_end_cap',[(-8.57,.48,.39,1.15),(-8.54,.50,.41,1.15)],teal)
# The lower nose is a genuinely recessed intake rather than a closed box.
loft('Intake_dark_recess',[(5.95,3.64,1.40,-.20),(6.62,3.69,1.42,-.20)],dark,caps=False)
ellipse_rim('Intake_formed_lip',(0,-.20,6.66),3.80,1.53,.14,teal)
for i in range(-8,9):
 x=i*.42;half=1.42*math.sqrt(max(0,1-(x/3.69)**2))
 cylinder('Front_siphon_gill', (x,-.20-half,6.64),(x,-.20+half,6.64),.070,steel,verts=10)
# Tail fluke uses swept lobes with a central notch and tapered outside tips.
right=[(.35,-8.15),(1.2,-8.2),(2.5,-7.95),(3.75,-7.55),(4.35,-7.60),(4.25,-8.35),(3.7,-9.20),(2.25,-9.85),(.75,-9.55),(.25,-9.05)]
for name,outline in [('Starboard_tail_fluke',right),('Port_tail_fluke',[(-x,z) for x,z in reversed(right)])]:
 o=extruded_outline(name,outline,1.1,.36,teal)
 for v in o.data.vertices:v.co.z+=abs(v.co.x)*.045
cylinder('Tail_cross_axle',(-1.0,1.1,-8.55),(1.0,1.1,-8.55),.23,steel,verts=20)
for x in [-.9,-.65,.65,.9]:cylinder('Tail_hinge_collar',(x-.06,1.1,-8.55),(x+.06,1.1,-8.55),.32,teal,verts=20)
for side in [-1,1]:
 # Main pectoral support joins the waist to the side pod.
 outline=[(side*3.7,1.45),(side*5.0,1.15),(side*6.25,.75),(side*6.25,-1.35),(side*4.4,-1.6)]
 if side<0:outline.reverse()
 extruded_outline('Pectoral_pod_support',outline,-.38,.50,teal)
 for z in [-.8,.7]:cylinder('Pod_actuator_rod',(side*4.4,-.12,z),(side*6.1,-.12,z),.10,steel)
 pod=[(-2.75,.58,.62,0),(-2.25,1.16,1.02,0),(-1.5,1.38,1.15,0),(1.5,1.38,1.15,0),(2.4,1.08,.91,0),(2.85,.68,.65,0)]
 group='PortHatch' if side<0 else 'StarboardHatch'
 loft(group+'_curved_upper_cover',pod,ivory,cx=side*7,theta0=0,theta1=math.pi,n=32,group=group)
 loft('Side_pod_lower_shell',pod,teal,cx=side*7,theta0=math.pi,theta1=2*math.pi,n=32)
 ellipse_rim('Side_pod_intake',(side*7,0,2.88),.68,.65,.10,teal,n=40)
 for j in [-2,-1,0,1,2]:cylinder('Pod_intake_gill',(side*7+j*.21,-.49,2.9),(side*7+j*.21,.49,2.9),.038,steel,verts=8)
 cylinder('Pod_longitudinal_hinge',(side*5.75,.10,-1.8),(side*5.75,.10,1.8),.12,steel)
 cylinder('Pod_weakpoint_cell',(side*7,.25,-.9),(side*7,.25,.9),.40,core,'PortGlow' if side<0 else 'StarboardGlow')

# Real cut-out in the hull, with recessed interior and a flush curved shutter.
core_pos=(0,2.02,3.1)
opening=[s for s in HULL if 1.19<=s[0]<=4.41]
theta_a=2*math.pi*13/64;theta_b=2*math.pi*19/64
box('Core_recess_floor',(0,1.03,2.8),(2.88,.14,3.18),dark,radius=.04)
for a in [theta_a,theta_b]:
 edge=[(rx*math.cos(a),cy+ry*math.sin(a),z) for z,rx,ry,cy in opening]
 for j in range(len(edge)-1):
  p,q=edge[j:j+2];mesh('Core_recess_sidewall',[p,q,(q[0],1.05,q[2]),(p[0],1.05,p[2])],[(0,1,2,3)],teal)
  cylinder('Core_window_long_frame',p,q,.10,teal,verts=12)
for s in [opening[0],opening[-1]]:
 z,rx,ry,cy=s;edge=[(rx*math.cos(a),cy+ry*math.sin(a),z) for a in [theta_a+(theta_b-theta_a)*j/8 for j in range(9)]]
 for p,q in zip(edge,edge[1:]):cylinder('Core_window_cross_frame',p,q,.10,teal,verts=10)
 mesh('Core_recess_endwall',edge+[(edge[-1][0],1.05,z),(edge[0][0],1.05,z)],[tuple(range(11))],teal)
cylinder('Recessed_core_pressure_cell',(0,1.64,1.8),(0,1.45,3.76),.52,core,'CoreGlow',verts=32)
for z in [1.85,2.12,3.40,3.68]:ellipse_rim('Core_cell_band',(0,1.64-(z-1.8)/1.96*.19,z),.54,.54,.045,steel,n=32)
for z in [1.79,3.77]:
 cy=1.64-(z-1.8)/1.96*.19;cylinder('Core_cell_dark_end',(0,cy,z-.025),(0,cy,z+.025),.52,steel,verts=32)
o=loft('Core_flush_curved_shield',opening,teal,theta0=theta_a,theta1=theta_b,n=6,group='CoreShield',caps=False)
solid=o.modifiers.new('Shield_real_thickness','SOLIDIFY');solid.thickness=.08;solid.offset=0

if '--production' in sys.argv:
 exec(compile((SRC/'whale_surface_detail.py').read_text(encoding='utf-8'),str(SRC/'whale_surface_detail.py'),'exec'),globals())

root=bpy.data.objects.new('SiphonWhale',None);col.objects.link(root)
pivots={}
for side,name in [(-1,'PortHatchPivot'),(1,'StarboardHatchPivot')]:
 p=bpy.data.objects.new(name,None);col.objects.link(p);p.location=pos((side*5.75,.10,0));p.parent=root;pivots[name]=p
bpy.context.view_layer.update()
for o in parts:
 world=o.matrix_world.copy();o.parent=root
 if o in groups.get('PortHatch',[]):o.parent=pivots['PortHatchPivot']
 if o in groups.get('StarboardHatch',[]):o.parent=pivots['StarboardHatchPivot']
 o.matrix_world=world
MARKERS={'PortWeakpoint':(-7,.65,0),'StarboardWeakpoint':(7,.65,0),'CoreWeakpoint':core_pos,'AttackOrigin':(0,-.20,6.9),'RetryEntry':(-28,-.8,14)}
for name,at in MARKERS.items():
 o=bpy.data.objects.new(name,None);col.objects.link(o);o.location=pos(at);o.parent=root
raw_anchor=bpy.data.objects.new('RawCommandRecordAnchor',None);col.objects.link(raw_anchor);raw_anchor.parent=bpy.data.objects['CoreWeakpoint'];raw_anchor.location=pos((0,1.03,0))

# Preview setup, excluded from future production exports.
studio=bpy.data.collections.new('Studio_NotExported');scene.collection.children.link(studio)
def studio_link(o):
 for c in list(o.users_collection):c.objects.unlink(o)
 studio.objects.link(o)
def aim(o,target):o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-2.28));floor=bpy.context.object;studio_link(floor);floor.data.materials.append(mat('StudioFloor',(.28,.30,.31)))
bpy.ops.object.camera_add(location=pos((22,24,29)));camera=bpy.context.object;studio_link(camera);aim(camera,pos((0,0,-.7)));camera.data.type='ORTHO';camera.data.ortho_scale=25;scene.camera=camera
for loc,power,size in [((-10,18,14),3500,10),((14,10,-2),2300,9),((-6,12,-15),3000,8)]:
 bpy.ops.object.light_add(type='AREA',location=pos(loc));o=bpy.context.object;studio_link(o);o.data.energy=power;o.data.shape='DISK';o.data.size=size;aim(o,(0,0,0))
scene.world.color=(.24,.24,.24);scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=20;scene.cycles.use_denoising=True
scene.render.threads_mode='FIXED';scene.render.threads=2;scene.render.resolution_x=1280;scene.render.resolution_y=1100;scene.render.resolution_percentage=100;scene.view_settings.view_transform='AgX'
production='--production' in sys.argv
if production:
 exec(compile((SRC/'whale_export.py').read_text(encoding='utf-8'),str(SRC/'whale_export.py'),'exec'),globals())
else:bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'siphon_whale_silhouette.blend'))
for view,where in [('front',(22,24,29)),('back',(-20,21,-26)),('open',(22,24,29))]:
 if view=='open':
  # Godot Z corresponds to Blender -Y; negative/positive local rotations map here.
  pivots['PortHatchPivot'].rotation_euler.y=math.radians(68)
  pivots['StarboardHatchPivot'].rotation_euler.y=math.radians(-68)
  for o in groups['CoreShield']:o.location+=pos((0,.30,-3.2))
 camera.location=pos(where);aim(camera,pos((0,0,-.7)));scene.render.filepath=str(EVID/(f'siphon_whale_{view}_v{REV}.png' if production else f'siphon_whale_silhouette_{view}_v2.png'));bpy.ops.render.render(write_still=True)
report={'status':'silhouette v2 only, no production UV/PBR or GLB','core_weakpoint_godot':core_pos,'hull_sections_z_rx_ry_center_y':HULL,'side_pod_centers_godot':[[-7,0,0],[7,0,0]],'pivot_godot':{'PortHatchPivot':[-5.75,.10,0],'StarboardHatchPivot':[5.75,.10,0]},'material_slots':6,'render':'Cycles CPU2','view_files':['siphon_whale_silhouette_front_v2.png','siphon_whale_silhouette_back_v2.png','siphon_whale_silhouette_open_v2.png']}
if not production:
 (EVID/'silhouette_v2.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
 print('WHALE_SILHOUETTE '+json.dumps(report,ensure_ascii=False))
else:print('WHALE_PRODUCTION_RENDER_COMPLETE version='+str(REV))
