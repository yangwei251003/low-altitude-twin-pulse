"""P8 one original asymmetric whole rock solid from authored wide fracture planes.
Source only. No PBR/GLB/runtime writes. World=Godot local+(6,-3.2,26),
Blender=(local.x,-local.z,local.y). One bounded build and two review images.
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
ref=ROOT/'references/v3/production/seal_foundation/seal_foundation_reference_v2.png'
gatefile=ROOT/'assets/v3/candidates/rising_seal_p3/rising_seal_p3.glb'
contacts=json.loads((HERE.parent/'p1/door_bottom_contact.json').read_text(encoding='utf-8'))
assert sha(ref)=='1d1c0fedc0bb9b412af8a8caef60c32c00972e01c94a871ca11816f90e3967ab'
assert sha(gatefile)==contacts['sha256']
frozen=[ref,gatefile,HERE.parent/'p5/seal_foundation_p5.blend',HERE.parent/'p5/build_foundation_p5.py',HERE.parent/'p6_side_study/build_side_study.py',HERE.parent/'p6_side_study/diagnostic.json',HERE.parent/'p7_side_study/seal_foundation_p7_side_study.blend']
frozen_hashes={q.relative_to(ROOT).as_posix():sha(q) for q in frozen}
shorefile=ROOT/'data/v3/terrain/f1_shore_layout.json';shore=json.loads(shorefile.read_text(encoding='utf-8'))
layout_snapshot_sha=sha(shorefile)
start=time.time();print('FOUNDATION_P8_PID',os.getpid(),flush=True)
bpy.ops.wm.read_factory_settings(use_empty=True);scene=bpy.context.scene
scene.render.threads_mode='FIXED';scene.render.threads=2
assetcol=bpy.data.collections.new('P8_EditableWholeFoundation');scene.collection.children.link(assetcol)
root=bpy.data.objects.new('SealFoundationP8',None);assetcol.objects.link(root);root['origin_world_godot']=[6,-3.2,26]
root['method']='Original asymmetric convex rock solid from authored large half-spaces. No scanned-body topology, repeated columns, radial loft or local vertex stretching.'
def mesh_ob(name,v,f,col=assetcol):
 me=bpy.data.meshes.new(name+'_Mesh');me.from_pydata(v,[],f);me.update();ob=bpy.data.objects.new(name,me);col.objects.link(ob);return ob
def basic_mat(name,col,rough=.87):
 m=bpy.data.materials.new(name);m.diffuse_color=(*col,1);m.use_nodes=True;p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*col,1);p.inputs['Roughness'].default_value=rough;p.inputs['Specular IOR Level'].default_value=.2;return m
rockmat=basic_mat('Basic_CoolOriginalRock',(.29,.32,.33))
# Broad submerged darkening only, not photographic noise or a PBR pass.
nt=rockmat.node_tree;pos=nt.nodes.new('ShaderNodeNewGeometry');sep=nt.nodes.new('ShaderNodeSeparateXYZ');nt.links.new(pos.outputs['Position'],sep.inputs[0]);mr=nt.nodes.new('ShaderNodeMapRange');mr.inputs['From Min'].default_value=.6;mr.inputs['From Max'].default_value=1.3;mr.clamp=True;nt.links.new(sep.outputs['Z'],mr.inputs['Value']);ramp=nt.nodes.new('ShaderNodeValToRGB');ramp.color_ramp.elements[0].color=(.15,.19,.20,1);ramp.color_ramp.elements[1].color=(.29,.32,.33,1);nt.links.new(mr.outputs['Result'],ramp.inputs[0]);nt.links.new(ramp.outputs[0],nt.nodes['Principled BSDF'].inputs['Base Color'])
beammat=basic_mat('Basic_ArchitecturalBearingStone',(.37,.35,.30),.86)

# Original whole-form composition: one uneven thick belly, two different
# long-side rhythms, wide diagonal end breaks and a genuinely broad seabed foot.
# Every surface is explicitly authored; no scan, ring extrusion or random noise.
# These plane intersections author a convex closed solid. The stored mesh retains
# its large editable polygons rather than baking the construction into a scan.
import itertools
plane_specs=[
 ('bed',(0,-1,0),0),('bearing_seat',(0,1,0),5.65),
 ('east_lower_wide_face',(1,-.08,.06),2.28),
 ('east_middle_diagonal',(1,.13,-.19),2.47),
 ('east_upper_oblique_shoulder',(1,.85,.09),5.72),
 ('east_front_broad_break',(1,.26,-.42),3.85),
 ('east_back_broad_break',(1,.33,.39),3.99),
 ('west_middle_belly',(-1,.1,-.04),2.25),
 ('west_upper_unequal_shoulder',(-1,.78,.08),5.40),
 ('west_front_broad_break',(-1,.20,-.45),3.5),
 ('west_back_broad_break',(-1,.30,.37),3.76),
 ('front_lower_slant',(0,-.05,-1),4.35),
 ('front_upper_unequal_break',(.06,.50,-1),6.61),
 ('back_lower_slant',(0,-.04,1),4.4),
 ('back_upper_unequal_break',(-.08,.62,1),7.25),
 ('wide_foot_west',(-1,-.42,.14),1.85),
 ('wide_foot_east',(1,-.32,-.10),1.95),
 ('wide_foot_front',(0,-.35,-1),3.95),
 ('wide_foot_back',(0,-.26,1),4.10)]
A=np.array([r[1] for r in plane_specs],dtype=float);B=np.array([r[2] for r in plane_specs],dtype=float);points=[]
for ids in itertools.combinations(range(len(A)),3):
 aa=A[list(ids)]
 if abs(np.linalg.det(aa))<1e-10:continue
 q=np.linalg.solve(aa,B[list(ids)])
 if np.all(A@q<=B+1e-8) and not any(np.linalg.norm(q-v)<1e-7 for v in points):points.append(q)
P=np.array(points);faces=[];authored_faces=[]
for i,(name,normal,d) in enumerate(plane_specs):
 ids=[j for j,q in enumerate(P) if abs(float(A[i]@q-B[i]))<1e-6]
 if len(ids)<3:continue
 n=np.array(normal,dtype=float);n/=np.linalg.norm(n);axis=np.eye(3)[np.argmin(np.abs(n))]
 u=np.cross(n,axis);u/=np.linalg.norm(u);v=np.cross(n,u);centre=P[ids].mean(0)
 ids.sort(key=lambda j:math.atan2(float((P[j]-centre)@v),float((P[j]-centre)@u)))
 faces.append(tuple(ids));authored_faces.append({'name':name,'normal_godot':normal,'plane_max_dot':d,'vertex_ids':ids})
rock=mesh_ob('OriginalWideFractureBody',[bp(q) for q in P],faces);rock.parent=root;rock.data.materials.append(rockmat)
bm=bmesh.new();bm.from_mesh(rock.data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(rock.data);bm.free();rock.data.update()
rock['authored_surface_count']=len(faces);rock['not_scan']='Fully original plane-built topology, no 6x stretched scanned body.'
rock['composition']='Unequal long-side faces, diagonal front/back shoulders and wide sloping foot; shared narrow architectural bearing seat.'
# Intentionally architectural beam; continuous top 1x7 support remains inside
# chamfers. Side chips are wide and shallow, not a noisy tiled pattern.
outline=[(-.65,-3.65),(.65,-3.65),(.65,2.50),(.35,3.65),(-.65,3.65)]
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
 for f in ob.data.polygons:f.use_smooth=False
 if ob==rock:ob.data.set_sharp_from_angle(angle=math.radians(1))
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
 print('P8_MESH',ob.name,s['triangles'],s['boundary_edges'],len(s['self_intersections']['strict_crossings']),flush=True)
ck('original_authored_solid_respects_all_halfspaces',bool(len(P)) and np.all(P@A.T<=B+1e-7),{'editable_large_faces':len(authored_faces),'method':'Original plane-built topology; no scan, ring loft or arbitrary per-vertex warp. Face count is descriptive, not an art-acceptance threshold.'})

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
water=section_loops(rock,1);bearing=section_loops(rock,5.65-1e-6)
# Real gate bottom is a subset of this conservative, read-back rectangle.
# The full actual footprint is required; outer beam support is also measured below.
rect=[(-.36000002,-3.42000008),(.12400001,-3.42000008),(.12400001,3.42000008),(-.36000002,3.42000008)]
containing=[i for i,r in enumerate(bearing['loops']) if r['closed'] and all(pip(p,r['points']) for p in rect)]
intersections=sum(strict_seg(a,b,c,d) for row in bearing['loops'] for a,b in zip(row['points'],row['points'][1:]+row['points'][:1]) for c,d in zip(rect,rect[1:]+rect[:1]))
extra_inside=[i for i,r in enumerate(bearing['loops']) if i not in containing and any(pip(p,rect) for p in r['points'])]
ck('actual_gate_bottom_full_rectangle_in_solid_rock',len(containing)==1 and intersections==0 and not extra_inside and bearing['all_nodes_degree_2'],{'containing_loops':containing,'boundary_crossings':intersections,'other_loops_inside_seat':extra_inside,'rectangle_xz':rect,'method':'Conservative rectangle contains the 28 actual bottom triangles; outer beam corners are NOT claimed fully supported.'})
support=[{'x':float(x),'z':float(z),'rock_y':ray_y(rt,x,z)} for x in np.linspace(-.36,.124,11) for z in np.linspace(-3.42,3.42,71)]
ck('actual_gate_rock_projection_dense_support',all(q['rock_y'] is not None and abs(q['rock_y']-5.65)<2e-5 for q in support),{'samples':len(support),'failures':[q for q in support if q['rock_y'] is None or abs(q['rock_y']-5.65)>=2e-5]})
beam_bottom_support=[{'x':x,'z':z,'rock_y':ray_y(rt,x,z)} for x,z in outline]
# Convex seat: support of the full beam polygon follows if every corner is in
# the same convex top face. Keep this evidence explicit, separate from 16 classes.
beam_outer_support={'all_outline_vertices_supported':all(q['rock_y'] is not None and abs(q['rock_y']-5.65)<2e-5 for q in beam_bottom_support),'vertices':beam_bottom_support,'reason':'Convex body top cross-section plus convex beam outline'}
# Explicit 0.1m beam-top margin, stronger than actual irregular gate footprint.
beam_margin=[ray_y(bt,float(x),float(z)) for x in np.linspace(-.46,.224,9) for z in np.linspace(-3.52,3.52,73)]
ck('beam_top_actual_gate_plus_0_1m_margin',all(y is not None and abs(y-6.1)<1e-5 for y in beam_margin),{'samples':len(beam_margin),'rectangle_xz':[[-.46,-3.52],[.224,3.52]]})
actual=[{'x':x,'z':z,'y':ray_y(bt,x,z)} for group in contacts['groups'] for x,_,z in group['local_gate_vertices']]
ck('actual_frozen_gate_36_bottom_vertices_supported',all(q['y'] is not None and abs(q['y']-6.1)<1e-5 for q in actual),actual)
# Previous nominal 1x7 peripheral rectangle is not the actual gate bottom; use the explicit actual-foot margin above.
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
worldnode=bpy.data.worlds.new('FoundationP8_ReviewWorld');scene.world=worldnode;worldnode.use_nodes=True;worldnode.node_tree.nodes['Background'].inputs[0].default_value=(.47,.50,.53,1);worldnode.node_tree.nodes['Background'].inputs[1].default_value=.65
def light(name,at,energy,size):
 d=bpy.data.lights.new(name,'AREA');ob=bpy.data.objects.new(name,d);scene.collection.objects.link(ob);ob.location=at;d.energy=energy;d.shape='DISK';d.size=size;ob.rotation_euler=(Vector((0,0,3))-ob.location).to_track_quat('-Z','Y').to_euler()
light('Key',(7,-5,15),1900,10);light('Fill',(-7,5,8),900,9)
c=bpy.data.cameras.new('FixedObliqueDirection_32_39_32');camera=bpy.data.objects.new(c.name,c);scene.collection.objects.link(camera);c.type='ORTHO';scene.camera=camera
offset=bp((32,39,32))
framing=[]
def frame(points,margin=1.22):
 from bpy_extras.object_utils import world_to_camera_view
 arr=np.array([tuple(p) for p in points]);focus=Vector(tuple((arr.min(0)+arr.max(0))/2));camera.location=focus+offset;camera.rotation_euler=(focus-camera.location).to_track_quat('-Z','Y').to_euler();bpy.context.view_layer.update()
 inv=camera.matrix_world.inverted();pr=[inv@Vector(tuple(p)) for p in arr]
 mn=Vector((min(v.x for v in pr),min(v.y for v in pr),0));mx=Vector((max(v.x for v in pr),max(v.y for v in pr),0))
 # Re-centre in camera projection, not only world AABB. Read actual camera frame
 # to avoid sensor-fit / orthographic-scale interpretation assumptions.
 camera.location+=camera.rotation_euler.to_quaternion()@((mn+mx)*.5)
 c.ortho_scale=1.0;bpy.context.view_layer.update();vf=c.view_frame(scene=scene)
 fw=max(v.x for v in vf)-min(v.x for v in vf);fh=max(v.y for v in vf)-min(v.y for v in vf)
 c.ortho_scale=max((mx.x-mn.x)/fw,(mx.y-mn.y)/fh)*margin;bpy.context.view_layer.update()
 uv=[world_to_camera_view(scene,camera,Vector(tuple(p))) for p in arr]
 bounds=[min(p.x for p in uv),min(p.y for p in uv),max(p.x for p in uv),max(p.y for p in uv)]
 assert min(bounds[:2])>.025 and max(bounds[2:])<.975,('Review image crop',bounds)
 framing.append({'image_index':len(framing),'point_count':len(points),'projected_normalised_bounds':bounds,'fully_inside':True})
assetpoints=[v.co for ob in [rock,beam] for v in ob.data.vertices]
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=16;scene.cycles.use_denoising=True;scene.render.resolution_x=1440;scene.render.resolution_y=1080;scene.render.resolution_percentage=100;scene.view_settings.view_transform='AgX';scene.render.image_settings.file_format='PNG'
frame(assetpoints)
source_path=HERE/'seal_foundation_p8_whole_form.blend';bpy.ops.wm.save_as_mainfile(filepath=str(source_path))
allp=np.concatenate([np.array([tuple(gp(v.co)) for v in ob.data.vertices]) for ob in [rock,beam]])
report={'stage':'P8 original whole-form source study; no PBR, GLB, runtime integration or human-play evidence','source_sha256':sha(source_path),'reference_sha256':sha(ref),'source_to_world':{'godot_world_offset':[6,-3.2,26],'blender_xyz_from_local_godot':'(x,-z,y)'},'frozen_inputs':frozen_hashes,'shore_layout_snapshot_sha256':layout_snapshot_sha,'sculpt':{'method':'One original asymmetric convex solid composed of authored large planes. No scan topology or 6x vertical stretch. No radial rings, repeated columns, old 118-edge seam or old waterline restriction.','editable_large_face_count':len(authored_faces),'faces':authored_faces,'points_godot_local':P.tolist(),'limitations':'Convex whole-form study; broad-plane count does not prove natural-rock aesthetics.'},'bounds_local':[allp.min(0).tolist(),allp.max(0).tolist()],'bounds_world':[world(allp.min(0)),world(allp.max(0))],'meshes':stats,'triangles':sum(q['triangles'] for q in stats),'beam_dimensions_m':[1.3,.45,7.3],'beam_world_top_y':2.9,'beam_world_bottom_y':2.45,'water_section':water,'bearing_rock_section':bearing,'submerged_rock_volume_m3':submerged_volume,'seabed_contact_area_m2':bed_area,'east_waterline_min_gap_m':min(east_gaps) if east_gaps else None,'checks':checks,'passed':sum(q['pass'] for q in checks),'total':len(checks),'all_pass':all(q['pass'] for q in checks),'actual_gate_rock_support_samples':support,'beam_full_bottom_support':beam_outer_support,'actual_gate_bottom_samples':actual,'render_direction_godot':[32,39,32],'framing':framing,'actual_gate_bottom_evidence':json.loads((HERE.parent/'p5/actual_gate_bottom_triangles.json').read_text(encoding='utf-8')),'limits':['not a game image','one original whole-form bounded trial, not guaranteed art success','SAT prechecks do not replace actual TR01/HX02 game sweeps','self audit excludes shared-vertex pairs and intentional rock/beam embedding','water section recomputed from the new solid; production water mesh unchanged'],'elapsed_before_render_s':time.time()-start}
(HERE/'form_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(HERE/'actual_water_section.json').write_text(json.dumps({'source_sha256':sha(source_path),'origin_world':[6,-3.2,26],'water_world_y':-2.2,'local_section':water,'world_loops':[[[float(x+6),float(z+26)] for x,z in row['points']] for row in water['loops']],'snapshot_east_waterline_min_gap_m':report['east_waterline_min_gap_m']},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('P8_CHECKS',report['passed'],report['total'],'triangles',report['triangles'],'failures',[q['name'] for q in checks if not q['pass']],flush=True)
scene.render.filepath=str(HERE/'whole_form_basic.png');bpy.ops.render.render(write_still=True)
gatecol.hide_render=False;bpy.context.view_layer.update();gatepoints=[ob.matrix_world@v.co for ob in gateobjs if ob.type=='MESH' for v in ob.data.vertices];frame(assetpoints+gatepoints,1.22)
scene.render.filepath=str(HERE/'whole_form_closed_gate.png');bpy.ops.render.render(write_still=True)
assert all(sha(ROOT/p)==h for p,h in frozen_hashes.items())
print('P8_EXIT_SECONDS',time.time()-start,'source',sha(source_path),flush=True)

report['framing']=framing;report['elapsed_total_s']=time.time()-start
(HERE/'form_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
