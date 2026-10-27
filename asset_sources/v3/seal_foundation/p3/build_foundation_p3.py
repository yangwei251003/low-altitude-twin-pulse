"""P3 single natural belly + explicitly re-sculpted upper shoulder.
Source only. No PBR/GLB/runtime writes. World=Godot local+(6,-3.2,26),
Blender=(local.x,-local.z,local.y). One bounded build and three review images.
"""
from pathlib import Path
import bpy,bmesh,numpy as np,json,math,hashlib,os,sys,time
from mathutils import Vector
from mathutils.bvhtree import BVHTree
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
sys.dont_write_bytecode=True;sys.path.insert(0,str(ROOT/'asset_sources/v3/shore_root/p12'))
from geometry_checks import strict_self_intersections
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
bp=lambda p:Vector((p[0],-p[2],p[1]))
gp=lambda p:Vector((p.x,p.z,-p.y))
world=lambda p:[float(p[0]+6),float(p[1]-3.2),float(p[2]+26)]
native=json.loads((HERE.parent/'p2/native_mesh_read.json').read_text())[0]
vendor=ROOT/'asset_sources/v3/growth_approach/resource_recovery/boulder_01/boulder_01_1k.blend'
ref=ROOT/'references/v3/production/seal_foundation/seal_foundation_reference_v2.png'
gatefile=ROOT/'assets/v3/candidates/rising_seal_p3/rising_seal_p3.glb'
contacts=json.loads((HERE.parent/'p1/door_bottom_contact.json').read_text(encoding='utf-8'))
assert sha(ref)=='1d1c0fedc0bb9b412af8a8caef60c32c00972e01c94a871ca11816f90e3967ab'
assert sha(vendor)==native['source_sha256'];assert sha(gatefile)==contacts['sha256']
frozen=[vendor,ref,gatefile,HERE.parent/'p2/seal_foundation_p2.blend',HERE.parent/'p1/seal_foundation_form_p1.blend']
frozen_hashes={p.relative_to(ROOT).as_posix():sha(p) for p in frozen}
shorefile=ROOT/'data/v3/terrain/f1_shore_layout.json';shore=json.loads(shorefile.read_text(encoding='utf-8'))
layout_snapshot_sha=sha(shorefile)
start=time.time();print('FOUNDATION_P3_PID',os.getpid(),flush=True)
bpy.ops.wm.read_factory_settings(use_empty=True);scene=bpy.context.scene
scene.render.threads_mode='FIXED';scene.render.threads=2
assetcol=bpy.data.collections.new('P3_EditableFoundation');scene.collection.children.link(assetcol)
sourcecol=bpy.data.collections.new('SOURCE_OriginalBoulderLOD3_Hidden');scene.collection.children.link(sourcecol);sourcecol.hide_render=True;sourcecol.hide_viewport=True
root=bpy.data.objects.new('SealFoundationP3',None);assetcol.objects.link(root);root['origin_world_godot']=[6,-3.2,26]
root['method']='One source rock; upper shoulder deliberately re-sculpted, not unchanged photogrammetry.'
with bpy.data.libraries.load(str(vendor),link=False) as (src,dst):dst.objects=[native['object']]
original=dst.objects[0];sourcecol.objects.link(original);original.name='SOURCE_Boulder01_LOD3_Original';original.hide_render=True
original['sha256']=sha(vendor)
def mesh_ob(name,v,f,col=assetcol):
 me=bpy.data.meshes.new(name+'_Mesh');me.from_pydata(v,[],f);me.update();ob=bpy.data.objects.new(name,me);col.objects.link(ob);return ob
def basic_mat(name,col,rough=.87):
 m=bpy.data.materials.new(name);m.diffuse_color=(*col,1);m.use_nodes=True;p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*col,1);p.inputs['Roughness'].default_value=rough;p.inputs['Specular IOR Level'].default_value=.2;return m
rockmat=basic_mat('Basic_CoolSculptedRock',(.29,.32,.33))
# Broad submerged darkening only, not photographic noise or a PBR pass.
nt=rockmat.node_tree;pos=nt.nodes.new('ShaderNodeNewGeometry');sep=nt.nodes.new('ShaderNodeSeparateXYZ');nt.links.new(pos.outputs['Position'],sep.inputs[0]);mr=nt.nodes.new('ShaderNodeMapRange');mr.inputs['From Min'].default_value=.6;mr.inputs['From Max'].default_value=1.3;mr.clamp=True;nt.links.new(sep.outputs['Z'],mr.inputs['Value']);ramp=nt.nodes.new('ShaderNodeValToRGB');ramp.color_ramp.elements[0].color=(.15,.19,.20,1);ramp.color_ramp.elements[1].color=(.29,.32,.33,1);nt.links.new(mr.outputs['Result'],ramp.inputs[0]);nt.links.new(ramp.outputs[0],nt.nodes['Principled BSDF'].inputs['Base Color'])
beammat=basic_mat('Basic_ArchitecturalBearingStone',(.37,.35,.30),.86)

# Initial rigid natural body: longest PCA axis along Z, middle along Y.
v=(np.array(native['vertices'])-native['centre'])@native['principal_basis_columns']
p=v[:,[2,1,0]];p[:,2]*=-1
scale=9.0/np.ptp(p[:,2]);p*=scale;p[:,0]-=(p[:,0].min()+p[:,0].max())/2;p[:,2]-=(p[:,2].min()+p[:,2].max())/2;p[:,1]-=p[:,1].min()+.16
pre_rigid_bounds=[p.min(0).tolist(),p.max(0).tolist()]
triangles=np.asarray(native['triangles'],dtype=int)

# Local end widening uses the real solid's cross sections, not a replacement
# rectangular prism. It is monotone in X and identical in the central belly.
edgepairs=np.vstack([triangles[:,[0,1]],triangles[:,[1,2]],triangles[:,[2,0]]]);aa=p[edgepairs[:,0]];bb=p[edgepairs[:,1]]
samples=np.linspace(-4.49,4.49,241);intervals=[]
for z in samples:
 mask=(aa[:,2]<=z)&(bb[:,2]>=z)|(aa[:,2]>=z)&(bb[:,2]<=z)
 mask &= np.abs(bb[:,2]-aa[:,2])>1e-10
 x=aa[mask,0]+(bb[mask,0]-aa[mask,0])*(z-aa[mask,2])/(bb[mask,2]-aa[mask,2])
 intervals.append([float(x.min()),float(x.max())] if len(x) else [-.01,.01])
intervals=np.array(intervals)
def smooth(t):t=np.clip(t,0,1);return t*t*(3-2*t)
original_p=p.copy();lo=np.interp(p[:,2],samples,intervals[:,0]);hi=np.interp(p[:,2],samples,intervals[:,1]);taper=smooth((4.32-np.abs(p[:,2]))/.42)
wantlo=lo+(np.minimum(lo,-1.06)-lo)*taper;wanthi=hi+(np.maximum(hi,1.06)-hi)*taper
span=np.maximum(hi-lo,.001);p[:,0]=wantlo+(p[:,0]-lo)/span*(wanthi-wantlo)
rock=mesh_ob('SculptedNaturalBody',[bp(q) for q in p],native['triangles']);rock.parent=root;rock.data.materials.append(rockmat)
rock['source']='Boulder 01 native LOD3';rock['source_uniform_scale']=float(scale);rock['upper_region']='authored deformation and local end widening, not original scan'

# Subdivide only the upper original faces before a nonlinear sculpt mapping.
# This creates topology for the authored shoulder instead of stretching a few
# old long triangles into the full 2m height change. No smoothing of old belly.
bm=bmesh.new();bm.from_mesh(rock.data);selected=[e for e in bm.edges if max(v.co.z for v in e.verts)>2.0]
bmesh.ops.subdivide_edges(bm,edges=selected,cuts=1,use_grid_fill=True,smooth=0.0)
bm.to_mesh(rock.data);bm.free();rock.data.update()
rock.data.calc_loop_triangles();before=[v.co.copy() for v in rock.data.vertices]
source_tree=BVHTree.FromPolygons(before,[tuple(t.vertices) for t in rock.data.loop_triangles],all_triangles=True)
changes=[];jacobian_min=1.0
for i,vert in enumerate(rock.data.vertices):
 q=gp(vert.co);hit=source_tree.ray_cast(bp((q.x,12,q.z)),bp((0,-1,0)),20)
 h=max(q.y,float(gp(hit[0]).y) if hit[0] is not None else q.y)
 # Flat only beneath and just within the bearing beam; wide outer blend makes
 # a full rock shoulder, not a raised narrow ribbon or uniform sidewall.
 outer_x=2.05 if q.x>0 else 1.90
 wx=float(smooth((outer_x-abs(q.x))/(outer_x-.79)))
 wz=float(smooth((4.34-abs(q.z))/(4.34-3.80)))
 target=h+wx*wz*(5.69-h)
 pivot=max(.25,min(2.55,h-1.15));interval=max(h-pivot,.1)
 u=max(0,min(1,(q.y-pivot)/interval));weight=u*u*(3-2*u)
 new_y=q.y+(target-h)*weight
 jac=1+(target-h)*6*u*(1-u)/interval;jacobian_min=min(jacobian_min,jac)
 vert.co=bp((q.x,new_y,q.z));changes.append(float(new_y-q.y))
rock.data.update()

def cut_and_close(ob,y,up):
 bm=bmesh.new();bm.from_mesh(ob.data)
 result=bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),plane_co=(0,0,y),plane_no=(0,0,1 if up else -1),dist=1e-7,clear_outer=True)
 edges=[e for e in result['geom_cut'] if isinstance(e,bmesh.types.BMEdge) and e.is_boundary]
 if edges:bmesh.ops.holes_fill(bm,edges=edges,sides=0)
 bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bmesh.ops.triangulate(bm,faces=list(bm.faces));bm.to_mesh(ob.data);bm.free();ob.data.update()
cut_and_close(rock,0,False)

# Intentionally architectural beam; continuous top 1x7 support remains inside
# chamfers. Side chips are wide and shallow, not a noisy tiled pattern.
outline=[(-.55,-3.65),(.52,-3.65),(.65,-3.52),(.65,-1.82),(.62,-1.65),(.65,-1.38),(.65,1.02),(.61,1.22),(.65,1.44),(.65,3.50),(.50,3.65),(-.52,3.65),(-.65,3.52),(-.65,1.9),(-.61,1.72),(-.65,1.50),(-.65,-.72),(-.62,-.91),(-.65,-1.10),(-.65,-3.50)]
verts=[];rings=[]
for y,inset in [(5.65,0),(5.72,0),(6.055,0),(6.1,.035)]:
 ring=[]
 for x,z in outline:
  xx=x-math.copysign(inset,x);zz=z-math.copysign(inset,z) if abs(z)>3.4 else z
  ring.append(len(verts));verts.append(bp((xx,y,zz)))
 rings.append(ring)
N=len(outline);faces=[tuple(reversed(rings[0])),tuple(rings[-1])]
for a,b in zip(rings,rings[1:]):faces.extend([(a[i],a[(i+1)%N],b[(i+1)%N],b[i]) for i in range(N)])
beam=mesh_ob('TempleBearingBeam',verts,faces);beam.parent=root;beam.data.materials.append(beammat)
bm=bmesh.new();bm.from_mesh(beam.data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bmesh.ops.triangulate(bm,faces=list(bm.faces));bm.to_mesh(beam.data);bm.free()
for ob in [rock,beam]:
 for f in ob.data.polygons:f.use_smooth=ob==rock
 if ob==rock:ob.data.set_sharp_from_angle(angle=math.radians(28))
 ob.data.update()
for name,point in [('GroundOrigin',(0,0,0)),('GateSeat',(0,6.1,0)),('Waterline',(0,1,0))]:
 ob=bpy.data.objects.new(name,None);assetcol.objects.link(ob);ob.parent=root;ob.location=bp(point);ob.empty_display_type='PLAIN_AXES';ob.empty_display_size=.2

def tree(ob):
 ob.data.calc_loop_triangles();return BVHTree.FromPolygons([v.co for v in ob.data.vertices],[tuple(t.vertices) for t in ob.data.loop_triangles],all_triangles=True)
rt=tree(rock);bt=tree(beam)
def ray_y(tr,x,z,origin=10):
 hit=tr.ray_cast(bp((x,origin,z)),bp((0,-1,0)),20)
 return None if hit[0] is None else float(gp(hit[0]).y)
checks=[]
def ck(name,passed,detail=None):checks.append({'name':name,'pass':bool(passed),'detail':detail})
def mesh_stats(ob):
 bm=bmesh.new();bm.from_mesh(ob.data);seen=set();components=0
 for v in bm.verts:
  if v in seen:continue
  components+=1;seen.add(v);stack=[v]
  while stack:
   q=stack.pop()
   for e in q.link_edges:
    w=e.other_vert(q)
    if w not in seen:seen.add(w);stack.append(w)
 ob.data.calc_loop_triangles();pp=np.array([tuple(gp(v.co)) for v in ob.data.vertices])
 result={'name':ob.name,'vertices':len(bm.verts),'triangles':len(ob.data.loop_triangles),'components':components,'boundary_edges':sum(e.is_boundary for e in bm.edges),'nonmanifold_edges':sum(not e.is_manifold for e in bm.edges),'volume_m3':bm.calc_volume(signed=True),'bounds_local':[pp.min(0).tolist(),pp.max(0).tolist()]};bm.free()
 result['self_intersections']=strict_self_intersections(ob,limit=30,include_coplanar=True)
 return result
stats=[]
for ob in [rock,beam]:
 s=mesh_stats(ob);stats.append(s);ck(ob.name+'_closed_positive_one_component',s['boundary_edges']==0 and s['nonmanifold_edges']==0 and s['components']==1 and s['volume_m3']>0,s)
 ck(ob.name+'_no_detected_self_intersections',not s['self_intersections']['strict_crossings'],s['self_intersections'])
 print('P3_MESH',ob.name,s['triangles'],s['boundary_edges'],len(s['self_intersections']['strict_crossings']),flush=True)
ck('sculpt_vertical_map_has_positive_local_derivative',jacobian_min>0,{'minimum_analytic_dyprime_dy':jacobian_min,'note':'continuous-map diagnostic; triangulated self intersections are checked separately'})

def section_loops(ob,height):
 ob.data.calc_loop_triangles();pp=[gp(v.co) for v in ob.data.vertices];edges=[]
 for t in ob.data.loop_triangles:
  q=[pp[i] for i in t.vertices];cut=[]
  for a,b in zip(q,q[1:]+q[:1]):
   if (a.y<height)!=(b.y<height):
    p=a+(b-a)*((height-a.y)/(b.y-a.y));cut.append((float(p.x),float(p.z)))
  if len(cut)==2 and (Vector(cut[0])-Vector(cut[1])).length>1e-8:edges.append(cut)
 key=lambda p:(round(p[0],5),round(p[1],5));coords={};adj={};pairs=set()
 for a,b in edges:
  ka,kb=key(a),key(b)
  if ka==kb:continue
  coords[ka]=a;coords[kb]=b;k=tuple(sorted((ka,kb)))
  if k in pairs:continue
  pairs.add(k);adj.setdefault(ka,[]).append(kb);adj.setdefault(kb,[]).append(ka)
 loops=[];unused=set(pairs)
 while unused:
  a,b=next(iter(unused));path=[a];prev=a;cur=b;unused.remove(tuple(sorted((a,b))))
  while cur!=a:
   path.append(cur);options=[x for x in adj[cur] if x!=prev and tuple(sorted((cur,x))) in unused]
   if not options:break
   nxt=options[0];unused.remove(tuple(sorted((cur,nxt))));prev,cur=cur,nxt
  loops.append({'closed':cur==a,'points':[coords[p] for p in path]})
 for row in loops:
  q=row['points'];row['area_abs_m2']=abs(sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(q,q[1:]+q[:1]))/2)
 return {'height_local_y':height,'height_world_y':height-3.2,'all_nodes_degree_2':all(len(v)==2 for v in adj.values()),'loops':loops,'segments':len(pairs)}
def pip(pt,poly):
 x,z=pt;inside=False
 for a,b in zip(poly,poly[1:]+poly[:1]):
  if (a[1]>z)!=(b[1]>z) and x<(b[0]-a[0])*(z-a[1])/(b[1]-a[1])+a[0]:inside=not inside
 return inside
def strict_seg(a,b,c,d):
 cross=lambda p,q,r:(q[0]-p[0])*(r[1]-p[1])-(q[1]-p[1])*(r[0]-p[0])
 return cross(a,b,c)*cross(a,b,d)<-1e-14 and cross(c,d,a)*cross(c,d,b)<-1e-14
water=section_loops(rock,1);bearing=section_loops(rock,5.65)
rect=[(-.65,-3.65),(.65,-3.65),(.65,3.65),(-.65,3.65)]
containing=[i for i,r in enumerate(bearing['loops']) if r['closed'] and all(pip(p,r['points']) for p in rect)]
intersections=sum(strict_seg(a,b,c,d) for row in bearing['loops'] for a,b in zip(row['points'],row['points'][1:]+row['points'][:1]) for c,d in zip(rect,rect[1:]+rect[:1]))
extra_inside=[i for i,r in enumerate(bearing['loops']) if i not in containing and any(pip(p,rect) for p in r['points'])]
ck('beam_bottom_full_1_3x7_3_inside_solid_rock_section',len(containing)==1 and intersections==0 and not extra_inside and bearing['all_nodes_degree_2'],{'containing_loops':containing,'boundary_crossings':intersections,'other_loops_inside_seat':extra_inside})
support=[{'x':float(x),'z':float(z),'rock_y':ray_y(rt,x,z)} for x in np.linspace(-.65,.65,15) for z in np.linspace(-3.65,3.65,75)]
ck('beam_bottom_dense_support',all(q['rock_y'] is not None and 5.65-1e-5<=q['rock_y']<6.1 for q in support),{'samples':len(support),'failures':[q for q in support if q['rock_y'] is None or q['rock_y']<5.65-1e-5 or q['rock_y']>=6.1]})
actual=[{'x':x,'z':z,'y':ray_y(bt,x,z)} for group in contacts['groups'] for x,_,z in group['local_gate_vertices']]
ck('actual_frozen_gate_36_bottom_vertices_supported',all(q['y'] is not None and abs(q['y']-6.1)<1e-5 for q in actual),actual)
nominal=[ray_y(bt,float(x),float(z)) for x in np.linspace(-.5,.5,9) for z in np.linspace(-3.5,3.5,71)]
ck('gate_nominal_1x7_continuous_flat_beam_top_samples',all(y is not None and abs(y-6.1)<1e-5 for y in nominal),{'samples':len(nominal),'min':min(y for y in nominal if y is not None),'max':max(y for y in nominal if y is not None)})
ck('actual_water_section_closed',water['all_nodes_degree_2'] and all(r['closed'] for r in water['loops']),water)

# Triangle-box SAT covers the full conservative sweep volume, not a point ray.
def tri_box_overlap(q,mn,mx):
 q=np.asarray(q);mn=np.array(mn);mx=np.array(mx)
 if np.any(q.max(0)<mn-1e-8) or np.any(q.min(0)>mx+1e-8):return False
 centre=(mn+mx)/2;half=(mx-mn)/2;q=q-centre;edges=[q[1]-q[0],q[2]-q[1],q[0]-q[2]]
 axes=[np.cross(edges[0],edges[1])]+[np.cross(e,a) for e in edges for a in np.eye(3)]
 for a in axes:
  if np.linalg.norm(a)<1e-12:continue
  proj=q@a;r=float(half@np.abs(a))
  if proj.min()>r+1e-8 or proj.max()<-r-1e-8:return False
 return True
def solid_inside(tr,point):
 direction=Vector((.813,.347,.467)).normalized();pos=bp(point);n=0
 for _ in range(100):
  h=tr.ray_cast(pos,direction,100)
  if h[0] is None:break
  n+=1;pos=h[0]+direction*1e-5
 return bool(n%2)
def sweep_check(name,mn_world,mx_world):
 mn=np.array(mn_world)-[6,-3.2,26];mx=np.array(mx_world)-[6,-3.2,26];bad=[];inside=[]
 for ob,tr in [(rock,rt),(beam,bt)]:
  pp=np.array([tuple(gp(v.co)) for v in ob.data.vertices]);tt=np.array([tuple(t.vertices) for t in ob.data.loop_triangles]);q=pp[tt]
  mask=np.all(q.max(1)>=mn,axis=1)&np.all(q.min(1)<=mx,axis=1)
  for i in np.where(mask)[0]:
   if tri_box_overlap(q[i],mn,mx):bad.append({'mesh':ob.name,'triangle':int(i)})
  for x in [mn[0],mx[0]]:
   for y in [mn[1],mx[1]]:
    for z in [mn[2],mx[2]]:
     if solid_inside(tr,[x,y,z]):inside.append({'mesh':ob.name,'point_local':[float(x),float(y),float(z)]})
 ck(name,not bad and not inside,{'world_min':mn_world,'world_max':mx_world,'intersecting_triangles':bad[:50],'count':len(bad),'contained_corners':inside,'scope':'full static triangle-box precheck of conservative sweep plus containment, NOT Godot movement proof'})
sweep_check('HX02_old_low_flight_full_envelope_plus_0_1m',[-6.2,2.56,23.95],[4.2,3.44,26.05])
sweep_check('gate_6m_travel_exclusion_above_seat',[5.5,2.90002,22.5],[6.5,13.9,29.5])
sweep_check('growth_bridge_actual_box_clear',[-11,4.75,23.5],[11,5.25,26.5])
sweep_check('south_route_full_body_plus_0_1m',[-5.2,3.56,31.95],[15.2,4.44,34.05])

# Read actual water cut against the current east shore; no rectangular footprint.
profile=np.array(shore['profile']);rightwater=lambda z:float(np.interp(z,profile[:,0],profile[:,2])-shore['slope_width'][1])
east_gaps=[rightwater(z+26)-(x+6) for row in water['loops'] for x,z in row['points']]
wet=bmesh.new();wet.from_mesh(rock.data);res=bmesh.ops.bisect_plane(wet,geom=list(wet.verts)+list(wet.edges)+list(wet.faces),plane_co=(0,0,1),plane_no=(0,0,1),dist=1e-7,clear_outer=True);ed=[e for e in res['geom_cut'] if isinstance(e,bmesh.types.BMEdge) and e.is_boundary]
if ed:bmesh.ops.holes_fill(wet,edges=ed,sides=0)
bmesh.ops.recalc_face_normals(wet,faces=list(wet.faces));submerged_volume=wet.calc_volume(signed=True);wet.free()
bed_area=sum(f.area for f in rock.data.polygons if all(abs(rock.data.vertices[i].co.z)<1e-5 for i in f.vertices))
ck('real_seabed_contact_patch',bed_area>0 and min(v.co.z for v in rock.data.vertices)>=-1e-5,{'contact_area_m2':bed_area,'world_y':-3.2})
ck('frozen_inputs_unchanged',all(sha(ROOT/p)==h for p,h in frozen_hashes.items()))

# Review-only frozen gate import. Existing P3 meshes/materials remain unchanged
# on disk; neutral material is assigned only to the source scene reference.
old=set(bpy.data.objects);bpy.ops.import_scene.gltf(filepath=str(gatefile));gateobjs=set(bpy.data.objects)-old
gatecol=bpy.data.collections.new('REFERENCE_FrozenP3Gate_NOT_ASSET');scene.collection.children.link(gatecol)
gaterefmat=basic_mat('ReferenceGate_Neutral',(.25,.28,.27),.9)
for ob in gateobjs:
 for c in list(ob.users_collection):c.objects.unlink(ob)
 gatecol.objects.link(ob)
 if ob.parent not in gateobjs:ob.location+=bp((0,8.6,0))
 if ob.type=='MESH':ob.data.materials.clear();ob.data.materials.append(gaterefmat)
gatecol.hide_render=True

context=bpy.data.collections.new('REFERENCE_ShoreAndBranchPositions_NOT_ASSET');scene.collection.children.link(context);context.hide_render=True
def context_mesh(name,v,f,mat):
 ob=mesh_ob(name,v,f,context);ob.data.materials.append(mat);ob['reference_only']=True;return ob
watermat=basic_mat('Reference_Water',(.075,.155,.18),.28);shoremat=basic_mat('Reference_Shore',(.17,.22,.18),.95);bridgemat=basic_mat('Reference_GrowthBridge',(.20,.27,.19),.9)
wp=lambda x,y,z:bp((x-6,y+3.2,z-26))
context_mesh('Water_Yminus2_2_POSITION_ONLY',[wp(x,-2.2,z) for x,z in [(-16,16),(20,16),(20,37),(-16,37)]],[(0,1,2,3)],watermat)
zs=sorted(set([17,35]+[float(r[0]) for r in profile if 17<r[0]<35]))
for side in ['east','west']:
 vv=[]
 for z in zs:
  if side=='east':edge=float(np.interp(z,profile[:,0],profile[:,2]));row=[(edge-1.6,-2.2),(edge,2.4),(25,2.4)]
  else:edge=float(np.interp(z,profile[:,0],profile[:,1]));row=[(edge+1.8,-2.2),(edge,0),(-18,0)]
  vv.extend([wp(x,y,z) for x,y in row])
 ff=[(i*3+j,(i+1)*3+j,(i+1)*3+j+1,i*3+j+1) for i in range(len(zs)-1) for j in range(2)]
 context_mesh('Current_'+side+'_shore_profile_POSITION_ONLY',vv,ff,shoremat)
bpy.ops.mesh.primitive_cube_add(size=1,location=wp(0,5,25));bridge=bpy.context.object;bridge.name='GrowthBridge_22x0_5x3_POSITION_ONLY';bridge.dimensions=(22,3,.5);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
for c in list(bridge.users_collection):c.objects.unlink(bridge)
context.objects.link(bridge);bridge.data.materials.append(bridgemat)

floor_mat=basic_mat('StudioFloor',(.17,.185,.19),.94);bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.025));floor=bpy.context.object;floor.name='StudioFloor_NOT_ASSET';floor.data.materials.append(floor_mat)
worldnode=bpy.data.worlds.new('FoundationP3_ReviewWorld');scene.world=worldnode;worldnode.use_nodes=True;worldnode.node_tree.nodes['Background'].inputs[0].default_value=(.47,.50,.53,1);worldnode.node_tree.nodes['Background'].inputs[1].default_value=.65
def light(name,at,energy,size):
 d=bpy.data.lights.new(name,'AREA');ob=bpy.data.objects.new(name,d);scene.collection.objects.link(ob);ob.location=at;d.energy=energy;d.shape='DISK';d.size=size;ob.rotation_euler=(Vector((0,0,3))-ob.location).to_track_quat('-Z','Y').to_euler()
light('Key',(7,-5,15),1900,10);light('Fill',(-7,5,8),900,9)
c=bpy.data.cameras.new('FixedObliqueDirection_32_39_32');camera=bpy.data.objects.new(c.name,c);scene.collection.objects.link(camera);c.type='ORTHO';scene.camera=camera
offset=bp((32,39,32))
def frame(points,margin=1.16):
 arr=np.array([tuple(p) for p in points]);focus=Vector(tuple((arr.min(0)+arr.max(0))/2));camera.location=focus+offset;camera.rotation_euler=(focus-camera.location).to_track_quat('-Z','Y').to_euler();bpy.context.view_layer.update();inv=camera.matrix_world.inverted();pr=[inv@Vector(tuple(p)) for p in arr];aspect=scene.render.resolution_x/scene.render.resolution_y
 width=max(v.x for v in pr)-min(v.x for v in pr);height=max(v.y for v in pr)-min(v.y for v in pr);c.ortho_scale=max(width,height*aspect)*margin
 # Blender orthographic scale is horizontal extent for this landscape frame.
assetpoints=[v.co for ob in [rock,beam] for v in ob.data.vertices]
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=16;scene.cycles.use_denoising=True;scene.render.resolution_x=1440;scene.render.resolution_y=1080;scene.render.resolution_percentage=100;scene.view_settings.view_transform='AgX';scene.render.image_settings.file_format='PNG'
frame(assetpoints)
source_path=HERE/'seal_foundation_p3.blend';bpy.ops.wm.save_as_mainfile(filepath=str(source_path))
allp=np.concatenate([np.array([tuple(gp(v.co)) for v in ob.data.vertices]) for ob in [rock,beam]])
report={'stage':'P3 single-form source study, no PBR, GLB, runtime integration or human-play evidence','source_sha256':sha(source_path),'reference_sha256':sha(ref),'source_to_world':{'godot_world_offset':[6,-3.2,26],'blender_xyz_from_local_godot':'(x,-z,y)'},'frozen_inputs':frozen_hashes,'shore_layout_snapshot_sha256':layout_snapshot_sha,'raw_uniform_scale':float(scale),'raw_rigid_bounds_local':pre_rigid_bounds,'sculpt':{'method':'monotone X cross-section widening at ends + continuous vertical upper-shoulder deformation; upper source edges subdivided before deformation; lower bed locally clipped','maximum_vertical_shift_m':max(changes),'minimum_vertical_shift_m':min(changes),'vertices_moved_over_1mm':sum(abs(d)>.001 for d in changes),'vertices_before_bed_clip':len(changes),'minimum_vertical_derivative':jacobian_min,'not_original_scan':True},'bounds_local':[allp.min(0).tolist(),allp.max(0).tolist()],'bounds_world':[world(allp.min(0)),world(allp.max(0))],'meshes':stats,'triangles':sum(s['triangles'] for s in stats),'beam_dimensions_m':[1.3,.45,7.3],'beam_world_top_y':2.9,'beam_world_bottom_y':2.45,'water_section':water,'bearing_rock_section':bearing,'submerged_rock_volume_m3':submerged_volume,'seabed_contact_area_m2':bed_area,'east_waterline_min_gap_m':min(east_gaps) if east_gaps else None,'checks':checks,'passed':sum(q['pass'] for q in checks),'total':len(checks),'all_pass':all(q['pass'] for q in checks),'beam_bottom_support_samples':support,'actual_gate_bottom_samples':actual,'render_direction_godot':[32,39,32],'limits':['not a game image','context shore and branch are simplified positional proxies','water plane is a review proxy, not runtime clipped mesh','SAT prechecks do not replace actual TR01/HX02 game sweeps','self audit excludes shared-vertex pairs and intentional rock/beam embedding'],'elapsed_before_render_s':time.time()-start}
(HERE/'form_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(HERE/'actual_water_section.json').write_text(json.dumps({'source_sha256':sha(source_path),'origin_world':[6,-3.2,26],'water_world_y':-2.2,'local_section':water,'world_loops':[[[float(x+6),float(z+26)] for x,z in row['points']] for row in water['loops']],'snapshot_east_waterline_min_gap_m':report['east_waterline_min_gap_m']},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('P3_CHECKS',report['passed'],report['total'],'triangles',report['triangles'],'failures',[q['name'] for q in checks if not q['pass']],flush=True)
scene.render.filepath=str(HERE/'seal_foundation_p3_basic.png');bpy.ops.render.render(write_still=True)
gatecol.hide_render=False;bpy.context.view_layer.update();gatepoints=[ob.matrix_world@v.co for ob in gateobjs if ob.type=='MESH' for v in ob.data.vertices];frame(assetpoints+gatepoints,1.18)
scene.render.filepath=str(HERE/'seal_foundation_p3_gate_assembly.png');bpy.ops.render.render(write_still=True)
context.hide_render=False;scene.render.resolution_x=1536;scene.render.resolution_y=1024;focuspoints=[wp(x,y,z) for x in [-12,17] for y in [-2.2,11] for z in [20,32]];frame(focuspoints,1.06)
scene.render.filepath=str(HERE/'seal_foundation_p3_near_shore_context.png');bpy.ops.render.render(write_still=True)
assert all(sha(ROOT/p)==h for p,h in frozen_hashes.items())
print('P3_EXIT_SECONDS',time.time()-start,'source',sha(source_path),flush=True)
