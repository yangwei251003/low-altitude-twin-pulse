"""P2 thick interlocked stone sections and roots that actually turn corners.
First source/basic-material study only. No PBR atlas, GLB or game import.
Local coordinates: u=Godot Z width, v=Godot Y up, t=Godot X thickness.
"""
from pathlib import Path
import bpy,bmesh,math,json,hashlib,struct,sys
from mathutils import Vector
from mathutils.bvhtree import BVHTree
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
P1=HERE.parent/'p1';SOURCE=P1/'rising_seal_source_p1.blend'
REF=ROOT/'references/v3/production/rising_seal/rising_seal_reference_v1.png'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
input_hashes={str(p.relative_to(ROOT)).replace('\\','/'):sha(p) for p in [SOURCE,P1/'build_rising_seal.py',REF]}
assert sha(REF)=='836f5f42091d21ba9561cf78c387fc7220aa3ad840a7ffc1b70906021ea1d3f6'
bpy.ops.wm.open_mainfile(filepath=str(SOURCE));scene=bpy.context.scene
col=bpy.data.collections['Editable_RisingSeal'];root=bpy.data.objects['RisingSeal']
pos=lambda u,v,t:Vector((t,-u,v))
def digest(ob):
 h=hashlib.sha256();h.update(struct.pack('<16d',*(x for row in ob.matrix_world for x in row)))
 if ob.type=='MESH':
  for v in ob.data.vertices:h.update(struct.pack('<3d',*v.co))
  for f in ob.data.polygons:h.update(struct.pack('<'+str(len(f.vertices))+'I',*f.vertices))
 return h.hexdigest()
old_parts=[o for o in root.children if o.type=='MESH']
replaced_prefixes=('StoneSection_','RootCorner_','RootBraid_','RootFork_','BronzeChannel_','PanelClamp_','ClampRivet')
preserved={o.name:digest(o) for o in root.children if o.name not in ['ContinuousSlab'] and not o.name.startswith(replaced_prefixes)}
for ob in old_parts:
 if ob.name=='ContinuousSlab' or ob.name.startswith(replaced_prefixes):bpy.data.objects.remove(ob,do_unlink=True)

def mat(name,color,rough=.88):
 m=bpy.data.materials.new(name);m.use_nodes=True
 p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED');p.inputs['Base Color'].default_value=(*color,1);p.inputs['Roughness'].default_value=rough;p.inputs['Specular IOR Level'].default_value=.18
 return m
stone=mat('P2_Stone_BroadBrush',(.235,.265,.275))
edge=mat('P2_Stone_WornFracture',(.29,.285,.26))
dark=mat('P2_Stone_SeamFloor',(.16,.19,.20))
wood=mat('P2_Root_BroadGrain',(.17,.105,.055))
# Continuous low-contrast brush variation, never Voronoi colour cells.
for material,lo,hi,scale in [(stone,(.215,.25,.262,1),(.265,.285,.29,1),(.6,1.25,.8)),(wood,(.125,.074,.038,1),(.205,.133,.074,1),(4.5,1.1,1))]:
 ns=material.node_tree.nodes;ls=material.node_tree.links;p=next(n for n in ns if n.type=='BSDF_PRINCIPLED')
 coord=ns.new('ShaderNodeTexCoord');mapping=ns.new('ShaderNodeVectorMath');mapping.operation='MULTIPLY';mapping.inputs[1].default_value=scale
 texture=ns.new('ShaderNodeTexNoise');texture.inputs['Scale'].default_value=1.45;texture.inputs['Detail'].default_value=.7;texture.inputs['Roughness'].default_value=.3
 ramp=ns.new('ShaderNodeValToRGB');ramp.color_ramp.elements[0].position=.12;ramp.color_ramp.elements[0].color=lo;ramp.color_ramp.elements[1].position=.88;ramp.color_ramp.elements[1].color=hi
 ls.new(coord.outputs['UV' if material==wood else 'Object'],mapping.inputs[0]);ls.new(mapping.outputs[0],texture.inputs['Vector']);ls.new(texture.outputs['Fac'],ramp.inputs[0]);ls.new(ramp.outputs[0],p.inputs['Base Color'])
 # Real authored surface relief; broad wood grain, restrained stone weathering.
 bump=ns.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.28;bump.inputs['Distance'].default_value=.025
 if material==wood:
  wave=ns.new('ShaderNodeTexWave');wave.wave_type='BANDS';wave.bands_direction='X';wave.inputs['Scale'].default_value=6;wave.inputs['Distortion'].default_value=3.5;wave.inputs['Detail'].default_value=1.5
  ls.new(mapping.outputs[0],wave.inputs['Vector']);ls.new(wave.outputs['Fac'],bump.inputs['Height'])
 else:ls.new(texture.outputs['Fac'],bump.inputs['Height'])
 ls.new(bump.outputs['Normal'],p.inputs['Normal'])
 rough=ns.new('ShaderNodeMapRange');rough.inputs['To Min'].default_value=.77 if material==wood else .78;rough.inputs['To Max'].default_value=.92
 ls.new(texture.outputs['Fac'],rough.inputs['Value']);ls.new(rough.outputs['Result'],p.inputs['Roughness'])

def mesh(name,verts,faces,materials,indices=None):
 data=bpy.data.meshes.new(name+'_Mesh');data.from_pydata(verts,[],faces);data.update()
 ob=bpy.data.objects.new(name,data);col.objects.link(ob);ob.parent=root
 for m in materials:data.materials.append(m)
 if indices:
  for poly,i in zip(data.polygons,indices):poly.material_index=i
 bm=bmesh.new();bm.from_mesh(data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(data);bm.free()
 return ob

outline=[(-3.42,-2.5),(3.42,-2.5),(3.43,1.92),(3.20,2.34),(1.15,2.35),(.45,2.39),(-1.17,2.36),(-3.20,2.32),(-3.44,1.93)]
n=len(outline)
back=mesh('SeamClosure',[pos(u,v,t) for t in [-.36,-.20] for u,v in outline],[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],[dark])

# The six stones extend through most of the slab thickness. Uneven edge bands
# and two broad planar front facets are actual geometry, not a colour mask.
polygons=[
 [(-3.42,-2.50),(-1.28,-2.50),(-1.13,-1.68),(-1.22,-.12),(-2.39,-.10),(-3.39,-.04)],
 [(-1.23,-2.50),(1.12,-2.50),(1.20,-1.66),(1.14,-.11),(.28,-.13),(-1.18,-.10),(-1.10,-1.68)],
 [(1.18,-2.50),(3.42,-2.50),(3.43,-1.72),(3.39,-.08),(2.53,-.03),(1.19,-.12),(1.25,-1.67)],
 [(-3.40,-.02),(-2.41,-.04),(-1.23,-.06),(-1.08,.67),(-1.20,2.34),(-2.61,2.38),(-3.20,2.30),(-3.42,1.93)],
 [(-1.18,-.04),(.29,-.08),(1.15,-.06),(1.20,1.09),(1.13,2.33),(.45,2.38),(-1.15,2.34),(-1.03,.68)],
 [(1.21,-.06),(2.53,.02),(3.39,-.02),(3.42,1.91),(3.20,2.33),(2.21,2.35),(1.18,2.32),(1.25,1.09)],
]
stone_specs=[]
def thick_section(name,poly,index):
 cx=sum(p[0] for p in poly)/len(poly);cy=sum(p[1] for p in poly)/len(poly)
 inner=[]
 for i,(u,v) in enumerate(poly):
  width=.105+.035*((i+index*2)%4)
  d=Vector((cx-u,cy-v)).normalized()*width
  inner.append((u+d.x,v+d.y))
 # One oblique mineral cleavage crossing each front face; different phase/angle.
 slope=[.27,-.32,.18,-.22,.36,-.29][index];offset=cx+slope*cy+[.16,-.22,.20,-.18,.11,-.09][index]
 def side(p):return p[0]+slope*p[1]-offset
 def depth(p):
  d=side(p)
  return .30 + (.040*d if d<=0 else -.052*d) + .008*(index%2)
 rings=[]
 for i,p in enumerate(inner):
  q=inner[(i+1)%len(inner)];points=[p]
  if side(p)*side(q)<-1e-10:
   f=side(p)/(side(p)-side(q));points.append((p[0]+f*(q[0]-p[0]),p[1]+f*(q[1]-p[1])))
  rings.append(points)
 vertices=[];faces=[];mi=[];lookup={}
 def vertex(u,v,t):
  key=(round(u,8),round(v,8),round(t,8))
  if key not in lookup:lookup[key]=len(vertices);vertices.append(pos(u,v,t))
  return lookup[key]
 rear=[vertex(u,v,-.34) for u,v in poly]
 shoulder=[vertex(u,v,.10+.012*((i+index)%3)) for i,(u,v) in enumerate(poly)]
 faces.append(tuple(reversed(rear)));mi.append(0)
 for i in range(len(poly)):
  j=(i+1)%len(poly);faces.append((rear[i],rear[j],shoulder[j],shoulder[i]));mi.append(0)
  edge_points=rings[i]+[inner[j]]
  faces.append(tuple([shoulder[i],shoulder[j]]+[vertex(u,v,depth((u,v))) for u,v in reversed(edge_points)]));mi.append(1)
 def clip(sign):
  result=[]
  for i,p in enumerate(inner):
   q=inner[(i+1)%len(inner)];a=side(p)*sign;b=side(q)*sign
   if a>=-1e-9:result.append(p)
   if a*b<0:
    f=a/(a-b);result.append((p[0]+f*(q[0]-p[0]),p[1]+f*(q[1]-p[1])))
  return result
 for sign in [-1,1]:
  face=clip(sign);faces.append(tuple(vertex(u,v,depth((u,v))) for u,v in face));mi.append(0)
 ob=mesh(name,vertices,faces,[stone,edge],mi)
 stone_specs.append({'name':name,'back_depth':-.34,'front_peak':max(v.x for v in vertices),'front_facets':2,'edge_width_range':[.105,.21]})
 return ob
for i,poly in enumerate(polygons):thick_section('StoneMass_%02d'%i,poly,i)

def interpolate(controls,steps=6):
 samples=[]
 for k in range(len(controls)-1):
  p0=Vector(controls[max(0,k-1)][:3]);p1=Vector(controls[k][:3]);p2=Vector(controls[k+1][:3]);p3=Vector(controls[min(k+2,len(controls)-1)][:3])
  for j in range(steps):
   t=j/steps
   p=.5*((2*p1)+(-p0+p2)*t+(2*p0-5*p1+4*p2-p3)*t*t+(-p0+3*p1-3*p2+p3)*t*t*t)
   r=controls[k][3]*(1-t)+controls[k+1][3]*t;samples.append((p,r))
 samples.append((Vector(controls[-1][:3]),controls[-1][3]));return samples

root_specs=[]
def rooted_curve(name,controls,phase=0,bed=False):
 # Measured first trial exceeded front envelope by 6.74mm. Translate only the
 # exposed front centreline 12mm inward; retain its full rounded cross-section.
 controls=[(u,v,t-.012 if t>.10 else t,r) for u,v,t,r in controls]
 samples=interpolate(controls);vertices=[];faces=[];count=16;previous_a=None
 for i,(local,radius) in enumerate(samples):
  p=pos(*local);before=pos(*samples[max(0,i-1)][0]);after=pos(*samples[min(len(samples)-1,i+1)][0]);tangent=(after-before).normalized()
  if previous_a is None:
   a=Vector((1,0,0))
   if abs(a.dot(tangent))>.9:a=Vector((0,0,1))
  else:a=previous_a
  a=(a-tangent*a.dot(tangent)).normalized();b=tangent.cross(a).normalized();previous_a=a
  for j in range(count):
   angle=math.tau*j/count;twist=phase+i*.027
   ridge=1 if bed else 1+.10*math.sin(3*angle+twist)+.035*math.sin(5*angle-twist*.7)
   vertices.append(p+radius*ridge*(a*math.cos(angle)*(.58 if bed else .92)+b*math.sin(angle)*(1.45 if bed else 1)))
 for i in range(len(samples)-1):
  for j in range(count):faces.append((i*count+j,i*count+(j+1)%count,(i+1)*count+(j+1)%count,(i+1)*count+j))
 faces.extend([tuple(reversed(range(count))),tuple(range((len(samples)-1)*count,len(samples)*count))])
 ob=mesh(name,vertices,faces,[wood]);uv=ob.data.uv_layers.new(name='RootDetailUV');uv.active_render=True
 for poly in ob.data.polygons:
  for li in poly.loop_indices:
   vi=ob.data.loops[li].vertex_index;uv.data[li].uv=((vi%count)/count,(vi//count)/(len(samples)-1)*3)
  poly.use_smooth=True
 root_specs.append({'name':name,'controls_u_v_t_radius':controls,'section_minor_major_ratio':.92 if not bed else 'shallow stone-bed cutter','closed_caps':True,'temporary_cutter':bed})
 return ob

def exact_boolean(target,cutter,operation,label):
 bpy.context.view_layer.objects.active=target
 mod=target.modifiers.new(label,'BOOLEAN');mod.operation=operation;mod.solver='EXACT';mod.object=cutter
 bpy.ops.object.modifier_apply(modifier=mod.name)

construction=bpy.data.collections.new('EditableRootConstructionPieces_Hidden');scene.collection.children.link(construction);construction.hide_render=True;construction.hide_viewport=True
root_masters=[]
for side in [-1,1]:
 # The master root remains visibly continuous down the FRONT; only its upper
 # return crosses the top. A separate branch turns the side. Carve the actual
 # shallow stone bed below these full round sections, instead of hiding them.
 controls=[(side*2.95,1.78,-.23,.11),(side*2.96,2.17,-.16,.18),(side*2.80,2.20,.05,.21),(side*2.66,1.98,.25,.21),(side*2.67,1.57,.25,.20),(side*2.92,1.06,.25,.225),(side*3.08,.60,.25,.19),(side*3.09,.23,.25,.18),(side*2.93,-.17,.25,.21),(side*2.66,-.63,.25,.22),(side*2.82,-1.15,.25,.20),(side*3.09,-1.70,.25,.19),(side*3.10,-2.08,.25,.16),(side*3.02,-2.38,.25,.095)]
 if side>0:
  controls=[(u,v+(.06*math.sin(i*.73) if 1<i<12 else 0),t,r*(.95 if i>6 else 1)) for i,(u,v,t,r) in enumerate(controls)]
 upper=[(side*2.91,1.08,.22,.13),(side*2.61,.86,.29,.14),(side*2.28,.75,.27,.10),(side*2.03,.54,.17,.025)]
 lower=[(side*2.77,-1.02,.24,.12),(side*3.15,-1.20,.18,.12),(side*3.38,-1.36,.0,.075),(side*3.37,-1.55,-.18,.035)]
 topfork=[(side*2.67,1.87,.24,.16),(side*2.43,2.00,.25,.145),(side*2.17,2.17,.25,.11),(side*2.02,2.27,.25,.065)]
 footfork=[(side*3.08,-1.71,.25,.155),(side*2.88,-1.91,.25,.15),(side*2.64,-2.14,.25,.12),(side*2.50,-2.36,.25,.065)]
 master=rooted_curve('RootWrap_'+str(side),controls,side*.8)
 branches=[rooted_curve('RootForkUpper_'+str(side),upper,side),rooted_curve('RootForkSide_'+str(side),lower,side+1),rooted_curve('RootForkFoot_'+str(side),footfork,side+1.3)]
 for source_piece in [master,*branches]:
  cp=source_piece.copy();cp.data=source_piece.data.copy();cp.parent=None;cp.hide_render=True;construction.objects.link(cp);cp.name=source_piece.name+'_Construction'
 for path,label in [(controls,'Main'),(lower,'Side'),(footfork,'Foot')]:
  cutter=rooted_curve('TemporaryRootBed_%s_%s'%(side,label),path,side*.8,bed=True)
  for stone_piece in [o for o in list(root.children) if o.name.startswith('StoneMass_')]:
   exact_boolean(stone_piece,cutter,'DIFFERENCE','P2_LocalRootStoneBed')
  bpy.data.objects.remove(cutter,do_unlink=True)
 for branch in branches:
  exact_boolean(master,branch,'UNION','P2_ContinuousRootForkUnion');bpy.data.objects.remove(branch,do_unlink=True)
 root_masters.append(master)

# Actual shallow engraved channel with a narrower bronze inlay. Follow the
# existing stone front across the six pieces instead of hovering at fixed X.
stone_pieces=[o for o in root.children if o.name.startswith('StoneMass_')]
def stone_front(u,v):
 hits=[]
 for ob in stone_pieces:
  bm=bmesh.new();bm.from_mesh(ob.data);tree=BVHTree.FromBMesh(bm)
  for du in [0,-.045,.045]:
   hit,normal,face,dist=tree.ray_cast(pos(u+du,v,1),Vector((-1,0,0)),2)
   if hit is not None:hits.append(hit.x)
  bm.free()
 return max(hits) if hits else .22

bronze=bpy.data.materials['Seal_AgedBronze'];patina=bpy.data.materials['Seal_TealPatina']
next(n for n in bronze.node_tree.nodes if n.type=='BSDF_PRINCIPLED').inputs['Base Color'].default_value=(.275,.225,.12,1)

def ribbon(name,path,width,tbottom,ttop,material):
 # path is (u,v,front-depth); cross strip has finite thickness and closed ends.
 verts=[];faces=[]
 for i,(u,v,t) in enumerate(path):
  before=Vector(path[max(0,i-1)][:2]);after=Vector(path[min(len(path)-1,i+1)][:2]);d=(after-before).normalized();n=Vector((-d.y,d.x))*width*.5
  verts.extend([pos(u+n.x,v+n.y,t+tbottom),pos(u-n.x,v-n.y,t+tbottom),pos(u-n.x,v-n.y,t+ttop),pos(u+n.x,v+n.y,t+ttop)])
 faces=[(3,2,1,0),(4*(len(path)-1),4*(len(path)-1)+1,4*(len(path)-1)+2,4*(len(path)-1)+3)]
 for i in range(len(path)-1):
  for j in range(4):faces.append((4*i+j,4*i+(j+1)%4,4*(i+1)+(j+1)%4,4*(i+1)+j))
 return mesh(name,verts,faces,[material])

channel_specs=[]
for side in [-1,1]:
 controls=[(side*.59,-.23,0,1),(side*.91,-.29,0,1),(side*1.23,-.18,0,1),(side*1.52,-.12,0,1),(side*2.38,-.09,0,1),(side*2.81,-.03,0,1),(side*3.04,.10,0,1)]
 path=[(p.x,p.y,stone_front(p.x,p.y)) for p,r in interpolate(controls,steps=3)]
 cutter=ribbon('TemporaryBronzeGroove',path,.20,-.070,.08,dark)
 for ob in stone_pieces:exact_boolean(ob,cutter,'DIFFERENCE','Inset_Bronze_Channel')
 bpy.data.objects.remove(cutter,do_unlink=True)
 ribbon('BronzeChannel_'+str(side),path,.118,-.058,-.006,bronze)
 channel_specs.append({'name':'BronzeChannel_'+str(side),'path_u_v_surface':path,'groove_width':.20,'groove_depth':.07,'bronze_width':.118,'front_inset':.006})

# Continuous bent straps physically cross each top/bottom edge; no floating
# rectangular front-only plate. Matching slot is cut in the stone underneath.
clamp_specs=[]
def bent_clamp(name,u,path,halfwidth,thickness,material):
 verts=[];faces=[]
 for i,(v,t) in enumerate(path):
  a=Vector(path[max(0,i-1)]);b=Vector(path[min(len(path)-1,i+1)]);direction=(b-a).normalized();n=Vector((-direction.y,direction.x))*thickness*.5
  verts.extend([pos(u-halfwidth,v-n.x,t-n.y),pos(u+halfwidth,v-n.x,t-n.y),pos(u+halfwidth,v+n.x,t+n.y),pos(u-halfwidth,v+n.x,t+n.y)])
 faces=[(3,2,1,0),(4*(len(path)-1),4*(len(path)-1)+1,4*(len(path)-1)+2,4*(len(path)-1)+3)]
 for i in range(len(path)-1):
  for j in range(4):faces.append((4*i+j,4*i+(j+1)%4,4*(i+1)+(j+1)%4,4*(i+1)+j))
 return mesh(name,verts,faces,[material])

for sign in [-1,1]:
 for u in [-1.82,1.80]:
  if sign>0:
   path=[(v,stone_front(u,v)+.003) for v in [1.78,2.00,2.14,2.23,2.30]]+[(2.365,.04),(2.365,-.12),(2.365,-.29),(2.28,-.348),(2.09,-.348)]
  else:
   path=[(v,stone_front(u,v)+.003) for v in [-1.89,-2.12,-2.30,-2.40,-2.45]]+[(-2.475,.01),(-2.475,-.12),(-2.475,-.29),(-2.40,-.348),(-2.16,-.348)]
  cutter=bent_clamp('TemporaryClampBed',u,path,.17,.085,dark)
  for ob in stone_pieces:exact_boolean(ob,cutter,'DIFFERENCE','Inset_CrossEdgeClamp')
  bpy.data.objects.remove(cutter,do_unlink=True)
  name='PanelClamp_%s_%s'%(u,sign);bent_clamp(name,u,path,.135,.035,bronze)
  clamp_specs.append({'name':name,'u':u,'cross_edge_path_v_t':path,'thickness':.035,'groove_thickness':.085})

# Exact boolean left one independently located triangular cap at the upper
# clamp/stone face junction after removing the optional top fork. Repair only
# those measured three vertices; never close unknown holes or weaken checks.
repair_records=[]
ob=bpy.data.objects['StoneMass_03'];bm=bmesh.new();bm.from_mesh(ob.data)
boundary=[e for e in bm.edges if e.is_boundary]
if boundary:
 expected=[Vector((.3079999983,2.2793631554,2.1847124100)),Vector((.2792120874,1.9900000095,2.1936938763)),Vector((.2930558622,1.9900000095,2.1936938763))]
 vs=list({v for e in boundary for v in e.verts})
 assert len(boundary)==len(vs)==3 and all(min((v.co-p).length for p in expected)<1e-5 for v in vs),'Unexpected boundary; refuse generic fill'
 area=(vs[1].co-vs[0].co).cross(vs[2].co-vs[0].co).length*.5
 bmesh.ops.holes_fill(bm,edges=boundary,sides=3);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(ob.data)
 repair_records.append({'object':ob.name,'method':'fill sole measured three-edge cap','area_m2':area,'vertices_blender':[list(v) for v in expected]})
bm.free()
opposed_face_cleanup=[]
for ob in [o for o in root.children if o.name.startswith('StoneMass_')]:
 old=ob.data;old.calc_loop_triangles();tris=list(old.loop_triangles);keys={}
 for i,t in enumerate(tris):keys.setdefault(tuple(sorted(t.vertices)),[]).append(i)
 skip=set()
 for ids,indices in keys.items():
  if len(indices)==1:continue
  assert len(indices)==2,'Unexpected triangle multiplicity'
  normals=[]
  for i in indices:
   a,b,c=[old.vertices[j].co for j in tris[i].vertices];normals.append((b-a).cross(c-a).normalized())
  assert normals[0].dot(normals[1])<-.999,'Not a classified opposite-face pair'
  a,b,c=[old.vertices[j].co for j in ids]
  opposed_face_cleanup.append({'object':ob.name,'vertex_ids':ids,'original_polygons':[tris[i].polygon_index for i in indices],'area_m2':(b-a).cross(c-a).length*.5,'removed_triangle_count':2})
  skip.update(indices)
 if not skip:continue
 kept=[t for i,t in enumerate(tris) if i not in skip]
 data=bpy.data.meshes.new(ob.name+'_LocalThinFaceCleanup');data.from_pydata([tuple(v.co) for v in old.vertices],[],[tuple(t.vertices) for t in kept]);data.update()
 for m in old.materials:data.materials.append(m)
 normal_values=[]
 for poly,t in zip(data.polygons,kept):
  poly.material_index=old.polygons[t.polygon_index].material_index;poly.use_smooth=old.polygons[t.polygon_index].use_smooth
  normal_values.extend(tuple(old.corner_normals[i].vector) for i in t.loops)
 for layer in old.uv_layers:
  target=data.uv_layers.new(name=layer.name)
  for poly,t in zip(data.polygons,kept):
   for li,oi in zip(poly.loop_indices,t.loops):target.data[li].uv=layer.data[oi].uv
 data.normals_split_custom_set(normal_values);ob.data=data
 # No coordinate movement, decimation, weld, remesh, or unrelated face loss.
 data.calc_loop_triangles()
 assert len(data.loop_triangles)==len(tris)-len(skip)
assert len(opposed_face_cleanup)==20,'Cleanup scope differs from 20 independently classified pairs'
bpy.context.view_layer.update();parts=[o for o in root.children if o.type=='MESH']
checks=[]
def check(name,ok,detail=None):checks.append({'name':name,'pass':bool(ok),'detail':detail})
points=[o.matrix_world@v.co for o in parts for v in o.data.vertices]
bounds={'min':[min(p[k] for p in points) for k in range(3)],'max':[max(p[k] for p in points) for k in range(3)]}
part_bounds={o.name:{'min':[min((o.matrix_world@v.co)[k] for v in o.data.vertices) for k in range(3)],'max':[max((o.matrix_world@v.co)[k] for v in o.data.vertices) for k in range(3)]} for o in parts}
check('moving_envelope_1x5x7',all(bounds['min'][k]>=lo-1e-5 and bounds['max'][k]<=hi+1e-5 for k,(lo,hi) in enumerate([(-.5,.5),(-3.5,3.5),(-2.5,2.5)])),bounds)
for ob in parts:
 bm=bmesh.new();bm.from_mesh(ob.data)
 closed=all(e.is_manifold for e in bm.edges);volume=bm.calc_volume(signed=True)
 check(ob.name+'_closed_positive',closed and volume>0,{'boundary':sum(e.is_boundary for e in bm.edges),'nonmanifold':sum(not e.is_manifold for e in bm.edges),'signed_volume':volume});bm.free()
for ob in root_masters:
 bm=bmesh.new();bm.from_mesh(ob.data);left=set(bm.verts);sizes=[]
 while left:
  stack=[left.pop()];size=0
  while stack:
   v=stack.pop();size+=1
   for e in v.link_edges:
    w=e.other_vert(v)
    if w in left:left.remove(w);stack.append(w)
  sizes.append(size)
 bm.free();check(ob.name+'_one_connected_master_with_forks',len(sizes)==1,{'component_vertex_counts':sizes})
check('core_and_markers_exact_P1_copper_changes_authorized',preserved=={name:digest(bpy.data.objects[name]) for name in preserved})
check('level_bottom_contact',abs(bounds['min'][2]+2.5)<1e-6 and (bpy.data.objects['BottomContact'].location-pos(0,-2.5,0)).length<1e-7)
check('readonly_inputs_unchanged',all(sha(ROOT/p)==value for p,value in input_hashes.items()))
check('no_voronoi_stone_colour',all(n.type!='TEX_VORONOI' for n in stone.node_tree.nodes))
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=12;scene.cycles.use_denoising=True;scene.render.threads_mode='FIXED';scene.render.threads=2
scene.render.resolution_x=1200;scene.render.resolution_y=960;scene.render.resolution_percentage=100
blend=HERE/'rising_seal_source_p2.blend';bpy.ops.wm.save_as_mainfile(filepath=str(blend))
report={'stage':'P2 refined source with additional forks and actual inset copper; no atlas/GLB yet','input_hashes':input_hashes,'source_sha256':sha(blend),'bounds_blender':bounds,'bounds_godot':{'min':[bounds['min'][0],bounds['min'][2],-bounds['max'][1]],'max':[bounds['max'][0],bounds['max'][2],-bounds['min'][1]]},'part_bounds_blender':part_bounds,'parts':len(parts),'triangles':sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in parts),'stone_specs':stone_specs,'root_specs':root_specs,'channel_specs':channel_specs,'clamp_specs':clamp_specs,'preserved_hashes':preserved,'checks':checks,'passed':sum(c['pass'] for c in checks),'total':len(checks),'all_pass':all(c['pass'] for c in checks),'limits':['candidate not final art','separate closed stone pieces overlap a continuous seam floor','full engine collision/movement/synchronization untested']}
(HERE/'source_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
report['specific_boolean_repairs']=repair_records
report['specific_reversed_face_cleanup']=opposed_face_cleanup
(HERE/'source_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('RISING_SEAL_P2_SOURCE '+json.dumps({'passed':report['passed'],'total':report['total'],'triangles':report['triangles'],'bounds':bounds,'failures':[c for c in checks if not c['pass']]},ensure_ascii=False),flush=True)
assert report['all_pass'],'Stop on actual closed/envelope failure before render'
if '--render' in sys.argv:
 scene.render.filepath=str(HERE/'rising_seal_source_p2.png');bpy.ops.render.render(write_still=True)
print('RISING_SEAL_P2_DONE',flush=True)
