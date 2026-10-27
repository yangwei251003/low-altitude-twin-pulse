"""Bounded H10 shape revision, source only. No baking or runtime export.
All design coordinates are Godot Y-up metres; Blender receives (x,-z,y).
"""
import bpy,bmesh,math,json,hashlib,struct,sys
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree

HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
P3=HERE.parent/'p3';SOURCE=P3/'root_buttress_h10_p3_export_ready.blend'
sha=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
frozen=json.loads((P3/'p3_manifest.json').read_text(encoding='utf-8'))
before_files={e['path']:sha(ROOT/e['path']) for e in frozen['entries']}
assert all(before_files[e['path']]==e['sha256'] for e in frozen['entries'])
runtime={h:sha(ROOT/f'assets/v3/root_buttress/root_buttress_h{h}.glb') for h in ['10','12','17','3']}
assert runtime==frozen['runtime_p2_sha256']
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene=bpy.context.scene;asset=bpy.data.objects['RootButtress'];col=bpy.data.collections['Editable_RootButtress']
sap=bpy.data.objects['SapKnot'];anchors={n:bpy.data.objects[n] for n in ['GroundOrigin','BodyPerch','HostTarget','LowerShelf']}
def digest_object(ob):
 h=hashlib.sha256();h.update(struct.pack('<16d',*(c for row in ob.matrix_world for c in row)))
 if ob.type=='MESH':
  for v in ob.data.vertices:h.update(struct.pack('<3d',*v.co))
  for f in ob.data.polygons:h.update(struct.pack('<'+str(len(f.vertices))+'I',*f.vertices))
  for uv in ob.data.uv_layers:
   h.update(uv.name.encode())
   for p in uv.data:h.update(struct.pack('<2d',*p.uv))
 return h.hexdigest()
fixed_before={o.name:digest_object(o) for o in [sap,*anchors.values()]}
for ob in list(asset.children_recursive):
 if ob.type=='MESH' and ob!=sap:bpy.data.objects.remove(ob,do_unlink=True)
MATS={k:bpy.data.materials['RB_'+k] for k in ['Stone','Bark','Moss','Sap']}
# New geometry must not sample the old packed atlas at unrelated coordinates.
# Keep the frozen Sap material/UV, and append the approved native p3 recipes
# for new stone/root surfaces; this stage still renders only shape overrides.
with bpy.data.libraries.load(str(P3/'root_buttress_h10_material_p3.blend'),link=False) as (src,dst):
 dst.materials=['RB_Stone','RB_Bark']
for kind,mat in zip(['Stone','Bark'],dst.materials):
 assert mat is not None
 MATS[kind]=mat
parts=[sap];groups={n:[] for n in ['RockMasses','LivingRoots','BarkPlates','MossDetails','SapKnot']};groups['SapKnot']=[sap]
def bp(p):return Vector((p[0],-p[2],p[1]))
def gp(p):return Vector((p.x,p.z,-p.y))
def obj(name,verts,faces,kind,group):
 me=bpy.data.meshes.new(name+'_Mesh');me.from_pydata([bp(v) for v in verts],[],faces);me.update()
 bm=bmesh.new();bm.from_mesh(me);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free()
 ob=bpy.data.objects.new(name,me);col.objects.link(ob);ob.parent=asset;me.materials.append(MATS[kind]);ob['semantic_group']=group
 parts.append(ob);groups[group].append(ob);return ob
def project_uv(ob):
 uv=ob.data.uv_layers.new(name='SurfaceUV');ob.data.uv_layers.active_index=0;uv.active_render=True
 for f in ob.data.polygons:
  axis=max(range(3),key=lambda k:abs(f.normal[k]));axes=[k for k in range(3) if k!=axis]
  for li in f.loop_indices:
   v=ob.data.vertices[ob.data.loops[li].vertex_index].co;uv.data[li].uv=(v[axes[0]]*.11,v[axes[1]]*.11)
 return ob
def rock(name,rings,inner_top=None):
 n=len(rings[0]);assert all(len(r)==n for r in rings)
 vs=[p for r in rings for p in r];faces=[tuple(reversed(range(n)))]
 for r in range(len(rings)-1):
  for j in range(n):faces.append((r*n+j,r*n+(j+1)%n,(r+1)*n+(j+1)%n,(r+1)*n+j))
 if inner_top:
  off=len(vs);vs.extend((x,10,z) for x,z in inner_top);last=(len(rings)-1)*n
  for j in range(n):faces.append((last+j,last+(j+1)%n,off+(j+1)%n,off+j))
  faces.append(tuple(off+j for j in range(n)))
 else:faces.append(tuple((len(rings)-1)*n+j for j in range(n)))
 return project_uv(obj(name,vs,faces,'Stone','RockMasses'))

# Broad continuous foundation, intentionally different at each section. The
# top is not a detached cap; uneven fracture planes run through the wall.
safe=[(4.35,0),(4.3,2.2),(3.55,3.55),(2.2,4.3),(0,4.35),(-2.2,4.3),(-3.55,3.55),(-4.3,2.2),(-4.35,0),(-4.3,-2.2),(-3.55,-3.55),(-2.2,-4.3),(0,-4.35),(2.2,-4.3),(3.55,-3.55),(4.3,-2.2)]
ground=[(5.65,0,.2),(5.7,0,2.5),(4.7,0,4.5),(2.3,0,5.25),(-.1,0,4.85),(-2.35,0,4.9),(-4.1,0,4.25),(-5.6,0,2.2),(-5.85,0,.0),(-5.5,0,-2.6),(-4.7,0,-4.7),(-2.35,0,-5.35),(.15,0,-5.45),(2.6,0,-5.5),(4.65,0,-4.8),(5.65,0,-2.45)]
lower=[(5.25,4.3,.1),(5.55,5.8,2.4),(4.15,4.9,4.45),(1.8,5.9,4.8),(-.3,4.8,4.6),(-1.8,6.3,3.6),(-2.9,6.4,2.45),(-4.5,6.4,1.5),(-5.5,4.7,.2),(-5.3,5.9,-2.6),(-4.7,4.6,-4.6),(-2.7,5.5,-4.9),(.25,4.9,-4.6),(2.3,5.8,-5.2),(4.5,4.8,-4.4),(5.0,5.5,-2.5)]
upper=[(4.6,8.3,.3),(4.8,7.2,2.6),(4.0,8.1,4.9),(1.7,7.7,4.7),(0,8.4,4.2),(-2.8,7.1,4.4),(-4.8,7.4,4.2),(-5.6,8.0,1.8),(-5.2,7.1,.2),(-4.6,8.0,-2.7),(-4.8,8.6,-4.5),(-2.3,8.2,-4.8),(.5,7.2,-4.2),(2.5,7.8,-5.2),(4.2,7.5,-4.8),(4.7,8.5,-2.5)]
rim=[(5.4,9.4,-.3),(5.65,9.2,2.2),(4.6,9.1,4.7),(2.4,9.55,5.1),(.1,8.7,4.85),(-2.1,8.6,5.25),(-4.5,9.1,4.75),(-5.5,9.3,2.5),(-5.75,9.55,.1),(-5.6,9.8,-2.55),(-4.5,10,-4.8),(-2.4,9.6,-5.4),(.2,9.2,-5.2),(2.5,9.6,-5.15),(4.3,9.85,-4.7),(5.35,9.1,-2.45)]
rock('Rock_01_ContinuousFracturedWall',[ground,lower,upper,rim],safe)

# A genuine left Y5 shelf and a thick rear residual ridge, not a ring of props.
rock('Rock_02_LeftShelfButtress',[
 [(-6.15,0,.6),(-6.05,0,3.1),(-4.8,0,4.35),(-3.1,0,4.7),(-2.6,0,3.1),(-3.3,0,1.5),(-4.9,0,.2)],
 [(-5.9,3.2,.8),(-5.6,3.5,3.2),(-4.4,3.0,4.5),(-2.9,3.6,4.45),(-2.7,3.15,3.0),(-3.4,3.7,1.6),(-5.0,3.3,.3)],
 [(-6.1,5,1.0),(-5.8,5,3.2),(-4.7,5,4.4),(-3.0,5,4.7),(-2.8,5,3.3),(-3.5,5,2.0),(-4.8,5,.5)]])
rock('Rock_03_ThickRearResidualRidge',[
 [(-6.2,0,-2.5),(-6.05,0,-5.6),(-3,0,-6.2),(.5,0,-5.8),(.7,0,-4.9),(-4.6,0,-2.2)],
 [(-5.7,6.3,-2.9),(-5.8,7.1,-5.8),(-3.3,6.8,-6.0),(.15,6.1,-5.5),(.3,7.1,-4.6),(-4.8,6.4,-2.65)],
 [(-6.05,10.5,-3.4),(-5.7,11.8,-5.4),(-3,11.2,-5.7),(.2,10.3,-5.4),(.2,10.1,-4.7),(-4.6,10.15,-3.2)]])
rock('Rock_04_AngledFrontRightShoulder',[
 [(1.4,0,3.4),(2.5,0,5.3),(4.7,0,5.5),(6.1,0,3.25),(5.3,0,1.9),(3.0,0,1.5)],
 [(1.85,3.4,3.6),(2.8,3.1,5.0),(4.8,3.9,5.1),(5.6,4.25,3.4),(5.1,3.2,2.3),(3.0,3.8,2.0)],
 [(2.2,6.9,3.35),(2.85,7.8,4.7),(4.35,7.1,4.8),(5.0,6.6,3.1),(4.8,7.2,2.15),(3.0,7.7,1.9)]])

def tree_for(objects):
 vs=[];fs=[]
 for ob in objects:
  ob.data.calc_loop_triangles();offset=len(vs);vs.extend(ob.matrix_world@v.co for v in ob.data.vertices)
  fs.extend(tuple(offset+i for i in t.vertices) for t in ob.data.loop_triangles)
 return BVHTree.FromPolygons(vs,fs,all_triangles=True)
bpy.context.view_layer.update();rock_tree=tree_for(groups['RockMasses'])
def cat(a,b,c,d,t):return .5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t)
def safe_root_point(q):
 q=Vector(q);q.y=max(0,q.y)
 radius=math.hypot(q.x,q.z)
 if q.y>9.5 and radius<4.45:q.x*=4.45/radius;q.z*=4.45/radius
 return q
contacts=[];primary_samples={}
def root(name,knots,seed,surface=None,steps=6,sides=14,plates=False):
 samples=[]
 for i in range(len(knots)-1):
  a,b,c,d=[Vector(knots[k]) for k in [max(i-1,0),i,i+1,min(i+2,len(knots)-1)]]
  for j in range(steps):samples.append(cat(a,b,c,d,j/steps))
 samples.append(Vector(knots[-1]));sample_contacts=[]
 for p in samples:
  if surface and .25<p.y<9.75:
   if surface=='front':origin=(p.x,p.y,9);direction=(0,0,-1)
   else:origin=(9,p.y,p.z);direction=(-1,0,0)
   hit=rock_tree.ray_cast(bp(origin),bp(direction),18)
   if hit[0]:
    face=gp(hit[0])
    weight=min(1,max(0,(9.75-p.y)/.85),max(0,(p.y-.25)/.75))
    if surface=='front':p.z=p.z*(1-weight)+(face.z+p[3]*.50)*weight
    else:p.x=p.x*(1-weight)+(face.x+p[3]*.50)*weight
  nearest=rock_tree.find_nearest(bp(p[:3]));sample_contacts.append({'centre':list(p[:3]),'radius':p[3],'nearest_rock_distance':nearest[3]})
 if surface:
  # Broad roots bend over an edge rather than instantly stepping to a new
  # ray-hit surface. Their continuous fibres remain partly embedded.
  for unused in range(2):
   smooth=[p.copy() for p in samples]
   for i in range(1,len(samples)-1):
    for axis in [0,2]:smooth[i][axis]=.6*samples[i][axis]+.2*(samples[i-1][axis]+samples[i+1][axis])
   samples=smooth
  sample_contacts=[{'centre':list(p[:3]),'radius':p[3],'nearest_rock_distance':rock_tree.find_nearest(bp(p[:3]))[3]} for p in samples]
  contacts.append({'root':name,'surface_following':surface,'samples':sample_contacts})
  primary_samples[name]=[p.copy() for p in samples]
 verts=[];arc=[0.0]
 for a,b in zip(samples,samples[1:]):arc.append(arc[-1]+(Vector(a[:3])-Vector(b[:3])).length)
 last_u=None;last_tangent=None;frames=[]
 for i,p in enumerate(samples):
  tangent=(Vector(samples[min(i+1,len(samples)-1)][:3])-Vector(samples[max(i-1,0)][:3])).normalized()
  if last_u is None:
   hint=Vector((0,0,1)) if abs(tangent.z)<.88 else Vector((1,0,0));u=tangent.cross(hint).normalized()
  else:u=last_tangent.rotation_difference(tangent)@last_u;u=(u-tangent*u.dot(tangent)).normalized()
  v=tangent.cross(u).normalized();last_u=u.copy();last_tangent=tangent.copy();t=i/(len(samples)-1)
  r=max(.025,p[3])*(1+.11*math.exp(-((t-.34)/.1)**2)+.06*math.exp(-((t-.74)/.08)**2))
  frames.append((u.copy(),v.copy(),r,t))
  for j in range(sides):
   a=j*math.tau/sides+.18*math.sin(t*5.5+seed)+t*.35
   lobes=1+.24*math.sin(3*a+seed+t*1.3)+.075*math.cos(5*a-t)
   verts.append(tuple(safe_root_point(Vector(p[:3])+r*lobes*(u*math.cos(a)+v*math.sin(a)*.88))))
 if surface:
  # Three unequal interwoven geometric fibres, not a broad flattened ribbon
  # with grooves merely painted on it. Their lobes intersect to stay joined.
  verts=[]
  for fibre,(offset,size) in enumerate([(.42,.62),(.48,.52),(.54,.46)]):
   for p,(u,v,r,t) in zip(samples,frames):
    phase=fibre*math.tau/3+t*4.2+seed*.31
    centre=Vector(p[:3])+r*offset*(u*math.cos(phase)+v*math.sin(phase))
    for j in range(sides):
     a=j*math.tau/sides+.1*math.sin(t*7+seed)
     radius=r*size*(1+.07*math.sin(4*a+t*3+fibre))
     verts.append(tuple(safe_root_point(centre+radius*(u*math.cos(a)+v*math.sin(a)))))
 fibre_count=3 if surface else 1;strip=len(samples)*sides;faces=[]
 for fibre in range(fibre_count):
  offset=fibre*strip;faces.append(tuple(offset+j for j in reversed(range(sides))))
  for i in range(len(samples)-1):
   for j in range(sides):faces.append((offset+i*sides+j,offset+i*sides+(j+1)%sides,offset+(i+1)*sides+(j+1)%sides,offset+(i+1)*sides+j))
  faces.append(tuple(offset+(len(samples)-1)*sides+j for j in range(sides)))
 ob=obj(name,verts,faces,'Bark','LivingRoots');uv=ob.data.uv_layers.new(name='SurfaceUV');uv.active_render=True
 circ=math.tau*sum(p[3] for p in samples)/len(samples)*.85/4
 for f in ob.data.polygons:
  js=[ob.data.loops[li].vertex_index%sides for li in f.loop_indices];seam=0 in js and sides-1 in js
  for li in f.loop_indices:
   vi=ob.data.loops[li].vertex_index%strip;j=vi%sides;uv.data[li].uv=((sides if seam and j==0 else j)/sides*circ+seed*.137,arc[vi//sides]/4+seed*.211)
  f.use_smooth=len(f.vertices)==4
 if plates:
  # Eight uneven low-relief plates per major root; no repeating band grid.
  for k,at in enumerate([.14,.31,.56,.78]):
   for side in [0,1]:
    start=max(1,int(at*(len(samples)-1))+(k+side)%3);end=min(len(samples)-2,start+3+(k*2+side)%5)
    j=(seed+k*3+side*5)%sides;vs=[]
    for row,si in enumerate([start,start+1,end-1,end]):
     for c in range(4):
      aj=j+[-.05,.15,1.65,1.88][c];lo=math.floor(aj)%sides;hi=(lo+1)%sides
      p=Vector(verts[si*sides+lo]).lerp(Vector(verts[si*sides+hi]),aj-math.floor(aj))
      radial=(p-Vector(samples[si][:3])).normalized();rise=.012 if row in [0,3] or c in [0,3] else .045+.02*math.sin(k+seed)
      vs.append(tuple(safe_root_point(p+radial*rise)))
    fs=[(r*4+c,r*4+c+1,(r+1)*4+c+1,(r+1)*4+c) for r in range(3) for c in range(3)]
    project_uv(obj(f'BarkPlate_{seed}_{k}_{side}',vs,fs,'Bark','BarkPlates'))
 return ob

# Two diverging front roots follow actual stone surfaces, with unequal taper.
# Their join remains behind the fixed amber target, outside the safety disk.
root('Root_FrontLeft_FaultFollowing',[(-4.3,.1,5.2,.35),(-3.25,1.8,4.5,.64),(-2.2,3.6,4.6,.65),(-2.45,5.4,4.2,.52),(-1.7,7.2,4.4,.52),(-.55,8.65,4.4,.45),(-.18,9.7,4.5,.32),(0,10.6,4.48,.27)],3,'front',plates=True)
root('Root_FrontRight_SplitButtress',[(5.0,.1,4.9,.36),(4.6,1.9,4.2,.70),(3.5,3.9,4.4,.76),(3.25,5.8,4.3,.64),(2.25,7.4,4.25,.55),(.95,8.8,4.45,.42),(.18,9.7,4.5,.30),(0,10.6,4.48,.26)],8,'front',plates=True)
root('Root_RightRear_Embedded',[ (5.7,.1,-3.5,.40),(5.2,2.0,-2.8,.79),(5.3,4.0,-2.2,.83),(5.3,6.4,-2.7,.69),(4.6,8.0,-3.5,.56),(3.3,9.3,-3.9,.38),(1.8,9.8,-4.5,.20),(.4,9.85,-4.5,.06)],14,'right',plates=True)
forks=[
 ('LeftGroundFan_A',[(-3.4,1.2,5.0,.48),(-4.4,.5,5.7,.42),(-6.3,.04,6.0,.07)],2),
 ('LeftGroundFan_B',[(-3.3,1.2,5.1,.45),(-2.7,.3,6.0,.39),(-1.2,.03,6.65,.06)],6),
 ('LeftGroundFan_C',[(-3.5,.9,4.9,.36),(-5.0,.3,4.9,.32),(-6.35,.03,4.1,.06)],9),
 ('RightGroundFan_A',[(4.7,1.25,4.9,.50),(5.5,.5,5.4,.43),(6.55,.03,5.7,.06)],11),
 ('RightGroundFan_B',[(4.6,1.1,5.0,.45),(3.7,.3,6.1,.37),(2.8,.03,6.65,.07)],12),
 ('RightGroundFan_C',[(5.0,1.2,4.6,.44),(5.9,.35,3.0,.34),(6.65,.03,2.0,.06)],15),
 ('RearGroundFan_A',[(5.7,1.25,-3.6,.50),(6.0,.4,-4.8,.35),(6.35,.03,-6.45,.06)],18),
 ('RearGroundFan_B',[(5.7,.9,-3.6,.40),(4.5,.3,-5.1,.34),(2.7,.03,-6.5,.07)],21),
 ('AmberCradle_Left',[(-.3,10.2,4.50,.25),(-.55,10.9,4.45,.18),(-.48,11.5,4.48,.12),(-.17,11.76,4.45,.045)],24),
 ('AmberCradle_Right',[(.3,10.2,4.50,.24),(.56,10.9,4.45,.17),(.48,11.4,4.48,.11),(.17,11.72,4.45,.045)],27)]
for name,knots,seed in forks:
 if 'GroundFan' in name:
  parent_name='Root_FrontLeft_FaultFollowing' if name.startswith('Left') else ('Root_FrontRight_SplitButtress' if name.startswith('Right') else 'Root_RightRear_Embedded')
  start=min(primary_samples[parent_name],key=lambda p:abs(p.y-knots[0][1]))
  # The branch cap begins inside the actual supporting root, not at a guessed
  # old coordinate after its centre was moved against the rock surface.
  knots[0]=(*start[:3],knots[0][3])
 root('RootBranch_'+name,knots,seed,steps=6,sides=12)
bpy.context.view_layer.update()

checks=[]
def check(name,passed,detail=None):checks.append({'name':name,'pass':bool(passed),'detail':detail})
fixed_after={o.name:digest_object(o) for o in [sap,*anchors.values()]}
check('fixed_sap_geometry_uv_transform_and_four_anchors_unchanged',fixed_before==fixed_after,{'before':fixed_before,'after':fixed_after})
stone_tree=tree_for(groups['RockMasses']);roots_tree=tree_for(groups['LivingRoots']+groups['BarkPlates'])
def down(tree,x,z,start=13):
 hit=tree.ray_cast(bp((x,start,z)),bp((0,-1,0)),20)
 return list(gp(hit[0])) if hit[0] else None
disk=[]
for ix in range(-14,15):
 for iz in range(-14,15):
  x,z=ix*.3,iz*.3
  if x*x+z*z<=4.2**2+1e-9:disk.append((x,z))
disk.extend((4.2*math.cos(i*math.tau/128),4.2*math.sin(i*math.tau/128)) for i in range(128))
hits=[down(stone_tree,x,z) for x,z in disk]
bad=[{'xz':p,'hit':h} for p,h in zip(disk,hits) if h is None or abs(h[1]-10)>.001]
check('protected_radius_4_2_rock_top_y10',not bad,{'probe_count':len(disk),'failures':bad})
root_hits=[down(roots_tree,x,z) for x,z in disk]
blocked=[{'xz':p,'hit':h} for p,h in zip(disk,root_hits) if h and h[1]>10.005]
check('new_roots_do_not_add_obstacle_above_safe_top',not blocked,blocked)
feet=[]
for x in [-3,3]:
 for z in [-3,3]:
  pts=[down(stone_tree,x+dx,z+dz) for dx,dz in [(0,0),(-.35,0),(.35,0),(0,-.35),(0,.35),(-.25,-.25),(.25,-.25),(-.25,.25),(.25,.25)]]
  check(f'foot_{x}_{z}_nine_points_y10',all(p and abs(p[1]-10)<.001 for p in pts),pts);feet.extend(pts)
lower_hits=[down(stone_tree,-3.7+dx,3.2+dz,6) for dx,dz in [(0,0),(-.25,0),(.25,0),(0,-.25),(0,.25)]]
check('lower_shelf_y5_five_points',all(p and abs(p[1]-5)<.001 for p in lower_hits),lower_hits)
all_points=[gp(o.matrix_world@v.co) for o in parts for v in o.data.vertices]
bounds={'min':[min(p[k] for p in all_points) for k in range(3)],'max':[max(p[k] for p in all_points) for k in range(3)]}
limit_min=[-6.610198020935059,0,-6.804511547088623];limit_max=[6.905734539031982,11.93212890625,6.879329681396484]
check('within_frozen_p2_xyz_bounds',all(bounds['min'][k]>=limit_min[k]-.0001 and bounds['max'][k]<=limit_max[k]+.0001 for k in range(3)),bounds)
sap_tree=tree_for([sap]);static=tree_for(groups['RockMasses']+groups['LivingRoots']);target=Vector((0,11,4.5))
for k,origin in enumerate([(0,11,8),(-3,12,8),(3,12,8)]):
 ray=(target-Vector(origin));sh=sap_tree.ray_cast(bp(origin),bp(ray.normalized()),ray.length+1);bh=static.ray_cast(bp(origin),bp(ray.normalized()),ray.length+1)
 check(f'sap_front_los_{k}',sh[0] is not None and (bh[0] is None or bh[3]>sh[3]+.01),{'sap_distance':sh[3],'static_distance':bh[3]})
near=roots_tree.find_nearest(bp(target));local=gp(near[0])-target
check('root_connected_to_frozen_sap',(local.x/.57)**2+(local.y/.78)**2+(local.z/.40)**2<.93,{'closest':list(gp(near[0]))})
triangles=0
for ob in parts:ob.data.calc_loop_triangles();triangles+=len(ob.data.loop_triangles)
check('triangles_under_22000',triangles<22000,triangles)
check('all_source_meshes_have_unique_active_SurfaceUV',all(len(o.data.uv_layers)==1 and o.data.uv_layers.active.name=='SurfaceUV' and o.data.uv_layers[0].active_render for o in parts))
check('p3_files_unchanged',all(sha(ROOT/path)==digest for path,digest in before_files.items()))
check('runtime_p2_files_unchanged',all(sha(ROOT/f'assets/v3/root_buttress/root_buttress_h{h}.glb')==digest for h,digest in runtime.items()))

# Save native editable PBR source; gray/basic review overrides are temporary.
camera=scene.camera;target_b=bp((0,5.3,0));camera.location=target_b+bp((.535645,.652817,.535645))*35
camera.rotation_euler=(target_b-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.type='ORTHO';camera.data.ortho_scale=26.5
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=8;scene.cycles.use_denoising=True;scene.render.threads_mode='FIXED';scene.render.threads=2
scene.render.resolution_x=1024;scene.render.resolution_y=800;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG'
blend=HERE/'root_buttress_h10_form_p4.blend';bpy.ops.wm.save_as_mainfile(filepath=str(blend))
report={'stage':'p4 shape source only; no baking or GLB export; visual review pending','input_p3_sha256':sha(SOURCE),'output_source_sha256':sha(blend),'triangles':triangles,'editable_meshes':len(parts),'major_rock_masses':len(groups['RockMasses']),'bounds_godot':bounds,'fixed_object_hashes':fixed_after,'anchors_godot':{n:list(gp(o.matrix_world.translation)) for n,o in anchors.items()},'rock_surface_following_root_samples':contacts,'checks':checks,'passed':sum(c['pass'] for c in checks),'total':len(checks),'all_checks_pass':all(c['pass'] for c in checks),'runtime_p2_sha256':runtime,'gpu_observation_source':'artifacts/v3/art/capture-20261018_022355_7ec161, actually viewed 02/05/04/06','confirmed_gpu_improvement':'p3 cool stone separates crown and amber; paving crack network no longer dominates','remaining_gpu_failure':'same-width tabletop outline and broad pasted-looking front root; this p4 is a new offline shape candidate, not game-validated','camera_direction_godot':[.535645,.652817,.535645],'render_modes':['gray shape only','basic approved cool-stone/brown-root palette; no texture noise'],'limits':['protected top probes target RockMasses; immutable existing SapKnot separately preserved as agreed','discrete Blender probes are not actual full crown/flight-body sweep','no runtime export or other-height production','do not use texture strata as evidence of new rock volume']}
(HERE/'p4_geometry_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('P4_REPORT '+json.dumps({k:report[k] for k in ['triangles','editable_meshes','bounds_godot','passed','total','all_checks_pass']},ensure_ascii=False),flush=True)
for c in checks:
 if not c['pass']:print('P4_FAILED '+json.dumps(c,ensure_ascii=False),flush=True)
assert report['all_checks_pass'],'Shape violates hard geometry constraints; do not lower assertions'
if '--render' in sys.argv:
 original={o.name:list(o.data.materials) for o in parts}
 for mode,colors in [('gray',{'RockMasses':(.37,.37,.37,1),'LivingRoots':(.23,.23,.23,1),'BarkPlates':(.23,.23,.23,1),'SapKnot':(.48,.48,.48,1)}),('basic',{'RockMasses':(.14,.17,.185,1),'LivingRoots':(.16,.11,.068,1),'BarkPlates':(.16,.11,.068,1),'SapKnot':(.65,.23,.025,1)})]:
  for group,obs in groups.items():
   if not obs:continue
   mat=bpy.data.materials.new('Review_'+mode+'_'+group);mat.use_nodes=True;p=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED');p.inputs['Base Color'].default_value=colors[group];p.inputs['Roughness'].default_value=.86;p.inputs['Specular IOR Level'].default_value=.18
   for ob in obs:ob.data.materials.clear();ob.data.materials.append(mat)
  scene.render.filepath=str(HERE/f'h10_p4_{mode}_default.png');bpy.ops.render.render(write_still=True)
 for ob in parts:ob.data.materials.clear();[ob.data.materials.append(m) for m in original[ob.name]]
assert all(sha(ROOT/path)==digest for path,digest in before_files.items())
print('P4_DONE_NO_RUNTIME_EXPORT',flush=True)
