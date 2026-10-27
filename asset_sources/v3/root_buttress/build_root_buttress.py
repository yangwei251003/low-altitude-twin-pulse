"""Original root-and-stone host terrain, shape review before PBR production.
Coordinates in helpers are Godot Y-up metres. H changes lower construction,
not the platform or sap-knot dimensions. No runtime GLB during shape review.
"""
import bpy,bmesh,math,json,hashlib,sys
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[3]
SRC=ROOT/'asset_sources/v3/root_buttress';OUT=ROOT/'assets/v3/root_buttress';ART=ROOT/'artifacts/v3/art/root_buttress'
for d in (SRC,OUT,ART):d.mkdir(parents=True,exist_ok=True)
H=10.0;REV=int(sys.argv[sys.argv.index('--revision')+1]) if '--revision' in sys.argv else 1
PRODUCTION='--production' in sys.argv
TARGET_H=float(sys.argv[sys.argv.index('--height')+1]) if '--height' in sys.argv else H
assert TARGET_H in (3,10,12,17)
LOW=TARGET_H==3
def adapt_y(y):
 if LOW:return y
 return y*(TARGET_H-3)/7 if y<=7 else y+(TARGET_H-H)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
scene=bpy.context.scene;scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
col=bpy.data.collections.new('Editable_RootButtress');scene.collection.children.link(col)
parts=[];groups={}
def bp(p):return Vector((p[0],-p[2],p[1]))
def gp(p):return [p.x,p.z,-p.y]
def material(name,value):
 m=bpy.data.materials.new(name);m.use_nodes=True;n=m.node_tree.nodes['Principled BSDF'];n.inputs['Base Color'].default_value=(*([value]*3),1);n.inputs['Roughness'].default_value=.86
 return m
if PRODUCTION:
 sys.path.insert(0,str(SRC));from root_buttress_materials import production_materials
 MATS=production_materials(SRC,ROOT);rock_mat=MATS['Stone'];root_mat=MATS['Bark'];sap_mat=MATS['Sap']
else:rock_mat=material('Review_Rock',.47);root_mat=material('Review_Root',.28);sap_mat=material('Review_Sap',.61)
def obj(name,vertices,faces,material,group):
 me=bpy.data.meshes.new(name+'_Mesh');me.from_pydata([bp(p) for p in vertices],[],faces);me.update()
 bm=bmesh.new();bm.from_mesh(me);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free()
 ob=bpy.data.objects.new(name,me);col.objects.link(ob);me.materials.append(material);parts.append(ob);groups.setdefault(group,[]).append(ob)
 return ob
def project_uv(ob):
 for layer in list(ob.data.uv_layers):ob.data.uv_layers.remove(layer)
 uv=ob.data.uv_layers.new(name='SurfaceUV');ob.data.uv_layers.active_index=0;uv.active_render=True
 for f in ob.data.polygons:
  axis=max(range(3),key=lambda i:abs(f.normal[i]));axes=[i for i in range(3) if i!=axis]
  for li in f.loop_indices:
   p=ob.data.vertices[ob.data.loops[li].vertex_index].co;uv.data[li].uv=(p[axes[0]]*.11,p[axes[1]]*.11)
 # Shape-stage UV is explicit but PBR scale/atlas refinement is later.
 return ob
outline=[(-1,-.73),(-.62,-.98),(.03,-1.0),(.62,-.92),(.90,-.55),(.97,-.16),(.98,.43),(.81,.78),(.35,.96),(.18,.91),(.10,.84),(-.12,.84),(-.25,.96),(-.71,.90),(-1.02,.38),(-1.0,-.12)]
def rock_loft(name,rings):
 # Each ring is height, centre-x, centre-z, x-radius, z-radius, yaw.
 vs=[];n=len(outline)
 for ri,(y,cx,cz,rx,rz,angle) in enumerate(rings):
  ca,sa=math.cos(angle),math.sin(angle)
  for j,(x,z) in enumerate(outline):
   irregular=1+.043*math.sin(j*4.1+ri*1.9)
   px=x*rx*irregular;pz=z*rz*irregular
   # Broad irregular break lines, not continuous evenly spaced bevel bands.
   yy=y if ri in (0,len(rings)-1) or y==5 else y+.22*math.sin(j*2.3+ri*1.4)
   vs.append((cx+px*ca-pz*sa,adapt_y(yy),cz+px*sa+pz*ca))
 faces=[tuple(reversed(range(n)))]
 for ri in range(len(rings)-1):
  for j in range(n):faces.append((ri*n+j,ri*n+(j+1)%n,(ri+1)*n+(j+1)%n,(ri+1)*n+j))
 if name=='Rock_A_ContinuousMainWall':
  # Only the outer lip is chipped. The actual four-foot support surface is a
  # separate broad coplanar inner polygon, never distorted for visual noise.
  last=(len(rings)-1)*n
  for j in range(n):
   x,y,z=vs[last+j];vs[last+j]=(x,y-.12-.12*math.sin(j*1.71),z)
  inner=[(-4,-3.2),(-3.75,-3.65),(.1,-3.65),(3.75,-3.65),(4,-3.2),(4,-.7),(4,1.8),(3.75,3.65),(1.5,3.65),(.77,3.65),(.45,3.65),(-.5,3.65),(-1,3.65),(-3.75,3.65),(-4,1.6),(-4,-.5)]
  off=len(vs);vs.extend((x,TARGET_H,z) for x,z in inner)
  for j in range(n):faces.append((last+j,last+(j+1)%n,off+(j+1)%n,off+j))
  faces.append(tuple(off+j for j in range(n)))
 else:faces.append(tuple((len(rings)-1)*n+j for j in range(n)))
 return project_uv(obj(name,vs,faces,rock_mat,'RockMasses'))

# Exactly three major interconnected rock bodies. Broad sloping walls are
# structural geometry; there is no thin facade hiding an empty platform.
if LOW:
 rock_loft('Rock_A_ContinuousMainWall',[(0,.3,-.1,4.85,3.80,-.04),(.85,.1,-.1,5.40,4.25,.03),(2.05,.1,0,5.75,4.60,-.04),(3,0,0,5.75,4.70,0)])
 rock_loft('Rock_B_LowLeftFracture',[(0,-3.9,.1,1.8,3.40,.03),(1.2,-4.1,.2,1.85,3.5,-.08),(2.55,-4.25,-.6,1.65,2.30,.06)])
 rock_loft('Rock_C_LowFrontFracture',[(0,3.2,2.1,2.1,2.35,-.11),(1.2,3.5,2.0,2.25,2.25,.07),(2.60,3.0,1.2,1.9,2.35,-.05)])
else:
 rock_loft('Rock_A_ContinuousMainWall',[
 (0,.65,-.4,4.35,3.20,-.06),
 (2.75,.85,-.45,4.18,3.60,.08),
 (5.8,.65,-.3,4.60,3.75,-.03),
 (7.3,.25,-.1,4.95,4.02,-.07),
 (H-1.8,.15,-.10,5.48,4.45,.015),
 (H-1.05,-.08,.05,5.65,4.70,-.035),
 (H,0,0,5.75,4.7,0),
 ])
 rock_loft('Rock_B_LowerShelfAndBackSpur',[
 (.0,-2.7,-.5,2.55,3.05,.11),
 (2.0,-2.4,-.5,2.50,3.0,-.04),
 (3.7,-2.6,.20,2.80,3.6,.09),
 (4.35,-2.8,.80,3.13,3.93,-.02),
 (5.0,-2.7,.65,3.16,4.0,0),
 (5.0,-2.65,-1.85,1.82,1.94,.12),
 (7.6,-3.2,-2.15,2.0,1.65,-.09),
 (9.9,-4.80,-3.75,1.08,1.03,-.14),
 (11.15,-4.95,-3.85,.91,.79,.08),
 (11.48,-5.04,-3.86,.78,.63,-.04),
 ])
 rock_loft('Rock_C_AngledFrontButtress',[
 (.0,3.0,1.75,2.13,2.55,-.13),
 (2.1,3.4,1.25,2.00,2.54,.07),
 (3.3,3.1,1.50,2.15,2.40,-.09),
 (4.0,3.55,1.32,1.65,2.12,-.06),
 (6.45,3.40,1.0,1.60,2.10,.12),
 (7.7,3.05,1.1,2.06,2.16,-.09),
 (8.95,2.85,.65,1.8,2.0,.05),
 ])

def cat(a,b,c,d,t):return .5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t)
def root_tube(name,knots,seed=0,steps=7,sides=12,flat=.73):
 # Unequal radii, asymmetric lobes, twisting broad sections and real forks.
 # No constant-radius curve bevel or duplicated parallel tubes.
 knots=[(x,adapt_y(y),z,r) for x,y,z,r in knots]
 samples=[]
 for i in range(len(knots)-1):
  a=Vector(knots[max(i-1,0)]);b=Vector(knots[i]);c=Vector(knots[i+1]);d=Vector(knots[min(i+2,len(knots)-1)])
  for j in range(steps):samples.append(cat(a,b,c,d,j/steps))
 samples.append(Vector(knots[-1]));vs=[];last_u=None;last_tangent=None
 arc=[0.0]
 for a,b in zip(samples,samples[1:]):arc.append(arc[-1]+(Vector(a[:3])-Vector(b[:3])).length)
 uv_circ=math.tau*sum(p[3] for p in samples)/len(samples)*.85/4.0
 for i,p in enumerate(samples):
  tangent=Vector(samples[min(i+1,len(samples)-1)][:3])-Vector(samples[max(i-1,0)][:3]);tangent.normalize()
  if last_u is None:
   hint=Vector((0,0,1)) if abs(tangent.z)<.88 else Vector((1,0,0));u=tangent.cross(hint).normalized()
  else:
   # Parallel transport prevents threshold-based frame flips and ribbon seams.
   u=last_tangent.rotation_difference(tangent)@last_u
   u=(u-tangent*u.dot(tangent)).normalized()
  v=tangent.cross(u).normalized();last_u=u.copy();last_tangent=tangent.copy()
  t=i/(len(samples)-1);twist=.38*math.sin(t*6.5+seed)+t*.60
  radius=max(.045,p[3]);knot=1+.10*math.exp(-((t-.39)/.11)**2)+.07*math.exp(-((t-.72)/.08)**2)
  for j in range(sides):
   a=2*math.pi*j/sides+twist;lobes=1+.19*math.sin(3*a+seed+t*1.2)+.07*math.cos(5*a-t*2)
   q=Vector(p[:3])+radius*knot*lobes*(u*math.cos(a)+v*math.sin(a)*flat)
   q.y=max(0,q.y);vs.append(tuple(q))
 faces=[tuple(reversed(range(sides)))]
 for i in range(len(samples)-1):
  for j in range(sides):faces.append((i*sides+j,i*sides+(j+1)%sides,(i+1)*sides+(j+1)%sides,(i+1)*sides+j))
 faces.append(tuple((len(samples)-1)*sides+j for j in range(sides)))
 ob=obj(name,vs,faces,root_mat,'LivingRoots')
 uv=ob.data.uv_layers.new(name='SurfaceUV');ob.data.uv_layers.active_index=0;uv.active_render=True
 for f in ob.data.polygons:
  js=[ob.data.loops[li].vertex_index%sides for li in f.loop_indices];seam=0 in js and sides-1 in js
  for li in f.loop_indices:
   vi=ob.data.loops[li].vertex_index;j=vi%sides
   uv.data[li].uv=((sides if seam and j==0 else j)/sides*uv_circ+seed*.137,arc[vi//sides]/4+seed*.211)
  f.use_smooth=len(f.vertices)==4
 if name.startswith('Root_01_Fiber') or name=='Root_02_RightWrapWeightBearing':
  # Low-relief solid bark plates follow the actual root surface. Their unequal
  # ends and staggered lengths remain readable before any normal/color map.
  # Decorative split from physical root trunk so future collision can omit it.
  for band in range(7):
   for sector in range(6):
    start=2+band*7+(sector*3+seed)%5
    end=min(start+5+(band+sector*2)%6,len(samples)-3)
    if end-start<3:continue
    jj=(sector*3+band%2)%sides
    ringids=[start,start+1,end-1,end];pvs=[];puvs=[]
    for ri,si in enumerate(ringids):
     for cj in range(4):
      # Fractional angular sampling makes a narrow edge lip without box bevels.
      angle_index=jj+(-.10,.12,1.72,1.95)[cj]
      lo=math.floor(angle_index)%sides;hi=(lo+1)%sides;f=angle_index-math.floor(angle_index)
      surf=Vector(vs[si*sides+lo]).lerp(Vector(vs[si*sides+hi]),f)
      radial=(surf-Vector(samples[si][:3])).normalized()
      rise=.013 if ri in (0,3) or cj in (0,3) else .065+.035*math.sin(band*3+sector)
      plate_point=surf+radial*rise
      if LOW:plate_point.y=max(.003,plate_point.y)
      pvs.append(tuple(plate_point));puvs.append((angle_index/sides*uv_circ+seed*.137,arc[si]/4+seed*.211))
    pfaces=[(r*4+c,r*4+c+1,(r+1)*4+c+1,(r+1)*4+c) for r in range(3) for c in range(3)]
    plate=obj(f'BarkPlate_{seed}_{band:02}_{sector:02}',pvs,pfaces,root_mat,'BarkPlates')
    uvp=plate.data.uv_layers.new(name='SurfaceUV');plate.data.uv_layers.active_index=0;uvp.active_render=True
    for face in plate.data.polygons:
     for li in face.loop_indices:uvp.data[li].uv=puvs[plate.data.loops[li].vertex_index]
 return ob

# One front root is made of three unequal interlocking structural fibres.
# Its middle section moves to the right so the left Y5 shelf is actually visible.
front_path=[(2.9,.0,5.2,.44),(3.25,1.4,4.95,.71),(3.05,3.25,4.55,.76),(2.3,5.25,4.55,.78),
 (1.2,7.35,4.35,.71),(.55,9.10,4.02,.64),(.0,10.35,3.88,.49),(.0,11.20,3.83,.36)]
if LOW:front_path=[(3.4,0,5.3,.33),(2.7,.5,5.0,.55),(1.7,1.4,4.65,.61),(.55,2.3,4.2,.45),(.0,3.0,4.0,.25),(.1,3.0,3.7,.07)]
for fibre,(phase,scale,offset) in enumerate(((0,.82,.12),(2.3,.75,.67),(4.35,.59,.67))):
 knots=[]
 for k,(x,y,z,r) in enumerate(front_path):
  t=k/(len(front_path)-1);a=phase+t*4.1+.18*math.sin(t*9+phase);spread=offset*(.78+.22*math.sin(t*3.14))
  knots.append((x+math.cos(a)*spread,y,z+math.sin(a)*spread,r*scale))
 root_tube(f'Root_01_Fiber_{fibre+1}',knots,seed=1+fibre*3,flat=.90,sides=14)
right_path=[
 (5.0,.0,-2.7,.50),(4.9,1.5,-1.8,1.02),(5.25,3.4,-1.1,1.12),(5.65,5.3,-1.5,1.02),
 (5.65,7.2,-2.2,.98),(5.0,8.7,-3.25,.82),(3.5,9.65,-4.1,.61),(1.9,10.0,-4.45,.36),(.6,10.0,-4.4,.12)
]
if LOW:right_path=[(5.6,0,-1.2,.32),(5.7,.7,-1.8,.62),(5.45,1.65,-2.3,.69),(4.7,2.65,-3.2,.62),(3.3,2.90,-4.2,.43),(1.9,3,-4.45,.20),(.6,3,-4.4,.08)]
root_tube('Root_02_RightWrapWeightBearing',right_path,seed=5,flat=.88,sides=16)
forks=[
 ('FrontFoot_Left',[(2.65,1.3,5.1,.60),(.4,.72,5.5,.62),(-2.2,.30,6.15,.40),(-4.5,.08,6.5,.10)],2),
 ('FrontFoot_Right',[(3.1,1.2,5.0,.60),(4.1,.65,5.5,.64),(5.9,.22,5.9,.37),(6.8,.06,5.3,.09)],3),
 ('FrontFoot_Centre',[(2.8,1.2,5.2,.62),(1.4,.40,6.1,.55),(.2,.08,6.8,.12)],7),
 ('FrontFork_LowerShelf',[(1.8,5.1,4.6,.40),(.5,3.8,4.8,.37),(-1.6,1.9,5.0,.38),(-4.6,.40,4.9,.40),(-6.6,.08,4.8,.10)],4),
 ('ShelfFoot_Branch',[(-2.7,1.35,5.0,.40),(-4.4,.40,5.55,.37),(-6.1,.06,6.15,.10)],9),
 ('RightFoot_Back',[(5.0,1.4,-2.5,.83),(5.7,.55,-3.8,.67),(6.4,.12,-5.5,.23),(6.8,.04,-6.3,.07)],8),
 ('RightFoot_Side',[(5.1,1.3,-2.2,.83),(6.2,.40,-.9,.47),(6.8,.08,1.1,.12)],10),
 ('BackFoot_Fork',[(4.9,2.4,-2.0,.67),(3.3,.8,-3.8,.55),(2.1,.25,-5.5,.32),(.3,.05,-6.5,.07)],13),
 ('RearFineFork',[(3.3,.8,-3.8,.4),(4.5,.20,-5.3,.3),(4.7,.04,-6.8,.06)],14),
 ('SapCradle_Left',[(-.7,9.6,4.0,.34),(-.72,10.5,4.3,.29),(-.68,11.2,4.35,.22),(-.35,11.8,4.30,.11)],17),
 ('SapCradle_Right',[(.7,9.6,4.0,.32),(.76,10.6,4.3,.27),(.62,11.5,4.35,.18),(.25,11.85,4.20,.09)],19),
 ('RightOuterCord',[(5.3,.1,-3,.15),(5.6,1.8,-1.9,.30),(6.05,3.5,-1.0,.33),(6.5,5.3,-1.5,.31),(6.4,7,-2.1,.24),(5.2,8.8,-3.25,.12)],24),
]
if LOW:
 forks=[
  ('LowFrontFoot_Left',[(2.2,.65,5.1,.44),(.1,.3,5.6,.39),(-2.5,.08,6.1,.15),(-4.5,.03,6.4,.07)],2),
  ('LowFrontFoot_Right',[(3.1,.4,5.1,.43),(4.6,.22,5.7,.33),(6.7,.04,5.3,.07)],3),
  ('LowFrontFoot_Centre',[(2.7,.45,5.3,.4),(1.5,.23,6.1,.29),(.2,.04,6.8,.07)],7),
  ('LowLeftContact',[(.2,2.4,4.4,.32),(-1.5,1.3,4.6,.35),(-3.8,.25,4.9,.31),(-6.6,.03,4.8,.07)],4),
  ('LowRightFoot_Back',[(5.5,.65,-1.8,.42),(6.1,.2,-3.9,.3),(6.8,.03,-6.3,.06)],8),
  ('LowRightFoot_Side',[(5.6,.4,-1.4,.4),(6.3,.22,.2,.26),(6.8,.03,1.1,.07)],10),
  ('LowRearRoot',[(4.9,.65,-2.3,.32),(3.1,.25,-4.4,.3),(.3,.03,-6.5,.07)],13),
 ]
for name,knots,seed in forks:root_tube('RootBranch_'+name,knots,seed,steps=6,sides=10,flat=.66)

# Physical amber knot connects to the lifted front root shoulder. It is not
# a floating marker. Kept separate for later light/thermal state material.
sap=None
if not LOW:
 bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2,radius=1,location=bp((0,TARGET_H+1,4.5)))
 sap=bpy.context.object;sap.name='SapKnot';sap.scale=(.57,.40,.78);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 for c in list(sap.users_collection):c.objects.unlink(sap)
 col.objects.link(sap);sap.data.materials.append(sap_mat);parts.append(sap);groups['SapKnot']=[sap];project_uv(sap)
 for face in sap.data.polygons:
  coords=[]
  for li in face.loop_indices:
   p=sap.data.vertices[sap.data.loops[li].vertex_index].co
   coords.append((li,math.atan2(p.y/.40,p.x/.57)/math.tau+.5,math.asin(max(-1,min(1,p.z/.78)))/math.pi+.5))
  seam=max(u for _,u,v in coords)-min(u for _,u,v in coords)>.5
  for li,u,v in coords:sap.data.uv_layers[0].data[li].uv=(u+1 if seam and u<.5 else u,v)

if PRODUCTION:
 # Small moss islands conform to actual root/stone surfaces, never a continuous
 # neon rim or a planar sheet floating between roots. Kept collision-free.
 cvs=[];cfs=[]
 for ob in groups['RockMasses']+groups['LivingRoots']:
  ob.data.calc_loop_triangles();off=len(cvs);cvs.extend(ob.matrix_world@v.co for v in ob.data.vertices);cfs.extend(tuple(off+i for i in f.vertices) for f in ob.data.loop_triangles)
 support=BVHTree.FromPolygons(cvs,cfs,all_triangles=True)
 def moss_island(name,origin,direction,axes,rx,ry):
  centre=Vector(origin);direction=Vector(direction).normalized();a,b=map(Vector,axes)
  vertices=[];depths=[]
  for ring in (0,1):
   for j in range(10):
    angle=j*math.tau/10;r=0 if ring==0 else 1+.15*math.sin(j*3.2)
    start=centre+a*math.cos(angle)*rx*r+b*math.sin(angle)*ry*r
    hit= support.ray_cast(bp(start),bp(direction),4)
    if hit[0] is None:return
    vertices.append(tuple(Vector(gp(hit[0]))-direction*.022));depths.append(hit[3])
  if max(depths)-min(depths)>.48:return
  faces=[(j,10+j,10+(j+1)%10) for j in range(10)]
  project_uv(obj(name,vertices,faces,MATS['Moss'],'MossDetails'))
 for k,(x,z) in enumerate([(4.45,-3.25),(4.9,-2.7),(-.85,4.1),(.8,4.15)]):
  for q in range(5):
   dx=.19*math.sin(q*2.8+k);dz=.13*math.cos(q*3.4+k)
   moss_island(f'Moss_TopContact_{k}_{q}',(x+dx,TARGET_H+.8,z+dz),(0,-1,0),((1,0,0),(0,0,1)),.085+.015*(q%3),.060+.015*(q%2))

asset=bpy.data.objects.new('RootButtress',None);col.objects.link(asset)
for ob in parts:ob.parent=asset
anchors={'GroundOrigin':(0,0,0),'BodyPerch':(0,TARGET_H+3,0),'HostTarget':(0,TARGET_H+1,4.5),'LowerShelf':(-3.7,adapt_y(5),3.2)}
if LOW:anchors.pop('LowerShelf')
for name,p in anchors.items():
 ob=bpy.data.objects.new(name,None);col.objects.link(ob);ob.parent=asset;ob.location=bp(p)

# Inspect actual geometry before rendering. This is not engine collision.
vs=[];faces=[];allpoints=[];triangles=0
for ob in parts:
 ob.data.calc_loop_triangles();triangles+=len(ob.data.loop_triangles);allpoints.extend(gp(ob.matrix_world@v.co) for v in ob.data.vertices)
 if ob==sap or ob in groups.get('BarkPlates',[]) or ob in groups.get('MossDetails',[]):continue
 offset=len(vs);vs.extend(ob.matrix_world@v.co for v in ob.data.vertices);faces.extend(tuple(offset+i for i in t.vertices) for t in ob.data.loop_triangles)
tree=BVHTree.FromPolygons(vs,faces,all_triangles=True)
def ground_hit(x,z,start=TARGET_H+4):
 hit=tree.ray_cast(bp((x,start,z)),bp((0,-1,0)),start+1)
 return gp(hit[0]) if hit[0] is not None else None
feet=[];checks={}
for x in [-3,3]:
 for z in [-3,3]:
  samples=[]
  for dx,dz in [(0,0),(-.35,0),(.35,0),(0,-.35),(0,.35)]:samples.append(ground_hit(x+dx,z+dz))
  okay=all(p is not None and abs(p[1]-TARGET_H)<.015 for p in samples);checks[f'foot_{x}_{z}_five_samples']=okay;feet.append({'centre':[x,TARGET_H,z],'surface_samples':samples,'supported':okay})
low=None if LOW else ground_hit(-3.7,3.2,start=adapt_y(5)+1)
checks['low_has_no_mid_shelf']=(len(anchors)==3) if LOW else True
if not LOW:checks['lower_shelf_height']=low is not None and abs(low[1]-adapt_y(5))<.015
bounds={'min':[min(p[k] for p in allpoints) for k in range(3)],'max':[max(p[k] for p in allpoints) for k in range(3)]}
checks['grounded']=bounds['min'][1]>=-.001
checks['roots_within_about_14m']=max(abs(bounds['min'][0]),abs(bounds['max'][0]),abs(bounds['min'][2]),abs(bounds['max'][2]))<7.35
checks['exact_three_major_rock_masses']=len(groups['RockMasses'])==3
checks['no_visible_sap_on_fall_platform' if LOW else 'sap_independent_mesh']=('SapKnot' not in bpy.data.objects) if LOW else ('SapKnot' in bpy.data.objects)

# Neutral review studio; never part of eventual export.
studio=bpy.data.collections.new('ReviewStudio_NotExported');scene.collection.children.link(studio)
def studio_link(o):
 for c in list(o.users_collection):c.objects.unlink(o)
 studio.objects.link(o)
def aim(o,target):o.rotation_euler=(bp(target)-o.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.mesh.primitive_plane_add(size=150,location=bp((0,-.05,0)));floor=bpy.context.object;studio_link(floor)
fm=material('Review_Floor',.25);floor.data.materials.append(fm)
bpy.ops.object.camera_add(location=bp((20,TARGET_H*.53+17.2,20)));camera=bpy.context.object;studio_link(camera);camera.data.type='ORTHO';camera.data.ortho_scale=23.5+(TARGET_H-10)*.70;aim(camera,(0,TARGET_H*.53,0));scene.camera=camera
for at,power,size in [((-12,22,18),2700,12),((15,14,-8),2100,10),((-6,15,-14),2000,9)]:
 bpy.ops.object.light_add(type='AREA',location=bp(at));light=bpy.context.object;studio_link(light);light.data.energy=power;light.data.size=size;aim(light,(0,5,0))
scene.world.use_nodes=True;bg=scene.world.node_tree.nodes['Background'];bg.inputs['Color'].default_value=(.40,.40,.40,1);bg.inputs['Strength'].default_value=.6
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=8;scene.cycles.use_denoising=True
scene.render.threads_mode='FIXED';scene.render.threads=2;scene.render.resolution_x=1280;scene.render.resolution_y=1000;scene.render.resolution_percentage=80;scene.render.image_settings.file_format='PNG';scene.view_settings.view_transform='AgX'
stem=f'root_buttress_h{int(TARGET_H)}_material_p{REV}' if PRODUCTION else f'root_buttress_form_v{REV}'
blend=SRC/f'{stem}.blend';bpy.ops.wm.save_as_mainfile(filepath=str(blend))
report={'revision':REV,'height':TARGET_H,'phase':'material trial, source only, runtime GLB not exported' if PRODUCTION else 'shape only, not production PBR or runtime GLB','source_path':str(blend.relative_to(ROOT)).replace('\\','/'),'source_sha256':hashlib.sha256(blend.read_bytes()).hexdigest(),'triangles':triangles,'editable_meshes':len(parts),'major_rocks':3,'primary_root_groups':2,'front_structural_fibres':3,'branches':len(forks),'bounds_godot':bounds,'anchors_godot':anchors,'foot_contact_samples':feet,'lower_shelf_hit':low,'checks':checks,'all_checks_pass':all(checks.values()),'reference_sha256':'f8484936f0a15fd8afc7219d81b03af5b0d3c6b40b2e8e1105dfd978d8469675','planned_collision':'RockMasses and LivingRoots static concave triangles; independent SapKnot target; omit BarkPlates/MossDetails; no enclosing convex hull','known_design_adaptation':'Sap knot lifted to H+1 front root shoulder; tall variants extend lower segments but retain fixed upper ledge thickness and sap scale; root cross-sections regenerated at original radius','scope':'Blender source point sampling, not Godot flight-body or final art acceptance'}
(ART/(f'{stem}.json' if PRODUCTION else f'form_v{REV}.json')).write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8');print('ROOT_BUTTRESS_FORM '+json.dumps(report,ensure_ascii=False),flush=True)
if '--export' in sys.argv:
 assert PRODUCTION and all(checks.values()), 'Do not export unvalidated shape or failed support geometry'
 # Export-only copies. Source is already saved with all editable parts and
 # never overwritten by merges. Decorative bark/moss remain collision-free groups.
 export_col=bpy.data.collections.new('Runtime_ExportCopies');scene.collection.children.link(export_col)
 runtime=bpy.data.objects.new(f'RootButtressH{int(TARGET_H)}',None);export_col.objects.link(runtime)
 exported=[runtime];export_stats=[]
 for name in ['RockMasses','LivingRoots','BarkPlates','MossDetails','SapKnot']:
  sources=groups.get(name,[])
  if not sources:continue
  bpy.ops.object.select_all(action='DESELECT');copies=[]
  for original in sources:
   cp=original.copy();cp.data=original.data.copy();cp.parent=None;cp.matrix_world=original.matrix_world.copy();export_col.objects.link(cp);cp.select_set(True);copies.append(cp)
  bpy.context.view_layer.objects.active=copies[0];bpy.ops.object.join();merged=bpy.context.object
  if name in bpy.data.objects and bpy.data.objects[name]!=merged:bpy.data.objects[name].name='Source_'+name
  merged.name=name;merged.parent=runtime;bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
  merged['collision_role']='static_concave' if name in ('RockMasses','LivingRoots') else ('target_only' if name=='SapKnot' else 'decoration_no_collision')
  merged.data.calc_loop_triangles();export_stats.append({'name':name,'triangles':len(merged.data.loop_triangles),'materials':len(merged.data.materials),'uv_layers':[l.name for l in merged.data.uv_layers]});exported.append(merged)
 for name,p in anchors.items():
  bpy.data.objects[name].name='Source_'+name
  marker=bpy.data.objects.new(name,None);export_col.objects.link(marker);marker.parent=runtime;marker.location=bp(p);exported.append(marker)
 bpy.ops.object.select_all(action='DESELECT')
 for ob in exported:ob.select_set(True)
 bpy.context.view_layer.objects.active=runtime
 glb=OUT/f'root_buttress_h{int(TARGET_H)}.glb'
 bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,export_apply=True,export_yup=True,export_extras=True,export_texcoords=True,export_normals=True,export_materials='EXPORT',export_cameras=False,export_lights=False,export_animations=False)
 report['runtime']={'path':str(glb.relative_to(ROOT)).replace('\\','/'),'sha256':hashlib.sha256(glb.read_bytes()).hexdigest(),'bytes':glb.stat().st_size,'meshes':export_stats,'root_node':runtime.name,'status':'candidate exported, awaiting independent binary/readback and actual Godot camera'}
 report['phase']='candidate runtime exported; not final art; independent readback evidence separate'
 (ART/f'{stem}.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
 # No duplicate export geometry in source-camera previews.
 for ob in exported:ob.hide_render=True
if '--build-only' not in sys.argv:
 scene.render.filepath=str(ART/f'{stem}.png');bpy.ops.render.render(write_still=True)
 if '--two-views' in sys.argv:
  camera.location=bp((0,TARGET_H*.53+9.7,28));aim(camera,(0,TARGET_H*.53,0));scene.render.filepath=str(ART/(f'{stem}_front.png' if PRODUCTION else f'root_buttress_front_v{REV}.png'));bpy.ops.render.render(write_still=True)
print('ROOT_BUTTRESS_FORM_DONE',flush=True)
