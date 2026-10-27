"""P2 natural thick rocks: one bounded source/assembly study, no PBR/GLB.
Original LOD3 meshes remain hidden/editable. Main rock transforms are rigid +
uniform scale; only interface/end planes and shallow seat ownership cuts occur.
Godot local origin = world (6,-3.2,26); Blender mapping (x,-z,y).
"""
from pathlib import Path
import bpy,bmesh,numpy as np,json,math,hashlib,os,sys,time
from mathutils import Vector,Matrix
from mathutils.bvhtree import BVHTree
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
sys.dont_write_bytecode=True
sys.path.insert(0,str(ROOT/'asset_sources/v3/shore_root/p12'))
from geometry_checks import strict_self_intersections
SHA=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
bp=lambda p:Vector((p[0],-p[2],p[1]))
gp=lambda p:Vector((p[0],p[2],-p[1]))
start=time.time();print('FOUNDATION_P2_BUILD_PID',os.getpid(),flush=True)
contract=json.loads((HERE.parent/'p1/interface.json').read_text(encoding='utf-8'))
contacts=json.loads((HERE.parent/'p1/door_bottom_contact.json').read_text(encoding='utf-8'))
native=json.loads((HERE/'native_mesh_read.json').read_text())
INPUTS=[ROOT/'asset_sources/v3/growth_approach/resource_recovery'/r['asset']/(r['asset']+'_1k.blend') for r in native]
INPUTS += [HERE.parent/'p1/seal_foundation_form_p1.blend',ROOT/contacts['source'],ROOT/'references/v3/production/seal_foundation/seal_foundation_reference_v1.png',ROOT/'data/v3/terrain/f1_growth_crossing.json',ROOT/'data/v3/terrain/f1_shore_layout.json']
hashes={p.relative_to(ROOT).as_posix():SHA(p) for p in INPUTS}
assert hashes[contacts['source']]==contacts['sha256']
bpy.ops.wm.read_factory_settings(use_empty=True);scene=bpy.context.scene
scene.render.threads_mode='FIXED';scene.render.threads=2
parts=bpy.data.collections.new('P2_EditableFoundation');scene.collection.children.link(parts)
originals=bpy.data.collections.new('SOURCE_NaturalLOD3_ReadOnlyCopies');scene.collection.children.link(originals);originals.hide_render=True;originals.hide_viewport=True
root=bpy.data.objects.new('SealFoundationP2',None);parts.objects.link(root)
root['origin_world_godot']=[6,-3.2,26];root['stage']='basic form candidate, not approved'
def material(name,c,rough=.88):
 m=bpy.data.materials.new(name);m.diffuse_color=(*c,1);m.use_nodes=True;n=m.node_tree.nodes.get('Principled BSDF');n.inputs['Base Color'].default_value=(*c,1);n.inputs['Roughness'].default_value=rough;n.inputs['Specular IOR Level'].default_value=.18;return m
rockmat=material('Basic_NaturalCoolRock',(.255,.29,.30))
wetmat=material('Basic_SubmergedInterface',(.145,.18,.18),.78)
topmat=material('Basic_CutBearingSurface',(.275,.295,.295))
ASSET=[];STATS=[];POSES=[]

def make_mesh(name,vertices,faces,collection=parts):
 me=bpy.data.meshes.new(name+'_Mesh');me.from_pydata(vertices,[],faces);me.update();ob=bpy.data.objects.new(name,me);collection.objects.link(ob);return ob
def relink(ob,collection):
 for c in list(ob.users_collection):c.objects.unlink(ob)
 collection.objects.link(ob)
def load_native(row):
 file=ROOT/'asset_sources/v3/growth_approach/resource_recovery'/row['asset']/(row['asset']+'_1k.blend')
 with bpy.data.libraries.load(str(file),link=False) as (src,dst):dst.objects=[row['object']]
 ob=dst.objects[0];originals.objects.link(ob);ob.name='SOURCE_'+row['object'];ob.hide_render=True
 ob['source_file']=str(file);ob['source_sha256']=SHA(file)
 return ob
sources=[load_native(row) for row in native]

def cut_plane(ob,point,normal,label):
 bm=bmesh.new();bm.from_mesh(ob.data)
 result=bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),plane_co=bp(point),plane_no=bp(normal),dist=1e-7,clear_outer=True)
 edges=[e for e in result['geom_cut'] if isinstance(e,bmesh.types.BMEdge) and e.is_boundary]
 if edges:
  fill=bmesh.ops.holes_fill(bm,edges=edges,sides=0)
  for f in fill['faces']:f.material_index=1 if label=='gate_seat' else 0
 bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(ob.data);bm.free();ob.data.update()
def triangulate(ob):
 bm=bmesh.new();bm.from_mesh(ob.data);bmesh.ops.triangulate(bm,faces=list(bm.faces));bm.to_mesh(ob.data);bm.free();ob.data.update()
def materialize(ob,wet=False):
 ob.data.materials.clear();ob.data.materials.append(wetmat if wet else rockmat);ob.data.materials.append(topmat)
 for p in ob.data.polygons:p.use_smooth=False
def bounds(ob):
 a=np.array([tuple(gp(ob.matrix_world@v.co)) for v in ob.data.vertices]);return {'min':a.min(0).tolist(),'max':a.max(0).tolist()}
def tree_for(ob):
 ob.data.calc_loop_triangles();return BVHTree.FromPolygons([ob.matrix_world@v.co for v in ob.data.vertices],[tuple(t.vertices) for t in ob.data.loop_triangles],all_triangles=True)
def stats(ob):
 ob.data.calc_loop_triangles();bm=bmesh.new();bm.from_mesh(ob.data)
 info={'name':ob.name,'vertices':len(bm.verts),'triangles':len(ob.data.loop_triangles),'boundary_edges':sum(e.is_boundary for e in bm.edges),'nonmanifold_edges':sum(not e.is_manifold for e in bm.edges),'volume_m3':bm.calc_volume(signed=True),'bounds_local_godot':bounds(ob)}
 # Count components independently of face winding.
 seen=set();n=0
 for v in bm.verts:
  if v in seen:continue
  n+=1;stack=[v];seen.add(v)
  while stack:
   q=stack.pop()
   for e in q.link_edges:
    w=e.other_vert(q)
    if w not in seen:seen.add(w);stack.append(w)
 info['components']=n;bm.free()
 info['self_intersections']=strict_self_intersections(ob,limit=30,include_coplanar=True)
 return info

# Principal axes derive from actual native LOD3, not the preview or a cube.
v=(np.array(native[0]['vertices'])-native[0]['centre'])@native[0]['principal_basis_columns']
canonical=v[:,[2,0,1]]
specs=[('BoulderWest',-2.50,-2,.71),('BoulderMiddle',-.05,2,.70),('BoulderEast',2.20,0,.75)]
for name,z_offset,tilt,fraction in specs:
 p=canonical.copy()*3.08;p[:,0]-=(p[:,0].min()+p[:,0].max())*.5;p[:,0]+=.25
 a=math.radians(tilt);rotation=np.array([[1,0,0],[0,math.cos(a),-math.sin(a)],[0,math.sin(a),math.cos(a)]])
 p=p@rotation.T;seat=p[:,1].min()+np.ptp(p[:,1])*fraction;p[:,1]+=6.1-seat;p[:,2]+=z_offset
 ob=make_mesh(name,[bp(q) for q in p],native[0]['triangles']);ob.parent=root;materialize(ob)
 original_bounds=bounds(ob);ob['source_asset']='Boulder 01 LOD3';ob['uniform_scale']=3.08;ob['rigid_tilt_deg']=tilt;ob['anisotropic_scale_used']=False
 # Tiny width/end clipping is reported, not called an unchanged natural rock.
 for point,normal,label in [((0,6.1,0),(0,1,0),'gate_seat'),((1.5,0,0),(1,0,0),'free_width'),((-1.5,0,0),(-1,0,0),'free_width'),((0,0,3.75),(0,0,1),'end'),((0,0,-3.75),(0,0,-1),'end')]:cut_plane(ob,point,normal,label)
 ASSET.append(ob);POSES.append({'name':name,'scale_uniform':3.08,'tilt_about_depth_deg':tilt,'z_offset':z_offset,'source_height_fraction_at_seat':fraction,'before_local_cuts':original_bounds,'after_local_cuts':bounds(ob)})

# A naturally thick bearing rock supports the upright masses. Its short PCA
# axis is thickness, not an artificially squashed copy of the other boulder.
nv=(np.array(native[1]['vertices'])-native[1]['centre'])@native[1]['principal_basis_columns']
p=nv[:,[2,1,0]]*2.0
# Swap handedness of this permutation without deforming: reverse long direction.
p[:,2]*=-1;p[:,0]-=(p[:,0].min()+p[:,0].max())*.5;p[:,1]+=3.8-p[:,1].max()
base=make_mesh('NamaNaturalBearing',[bp(q) for q in p],native[1]['triangles']);base.parent=root;materialize(base)
base['source_asset']='Namaqualand Boulder 03 LOD3';base['uniform_scale']=2.0;base['anisotropic_scale_used']=False
for point,normal,label in [((0,0,0),(0,-1,0),'bed'),((1.5,0,0),(1,0,0),'free_width'),((-1.5,0,0),(-1,0,0),'free_width'),((0,0,3.75),(0,0,1),'end'),((0,0,-3.75),(0,0,-1),'end')]:cut_plane(base,point,normal,label)
# At Y=1 each inclined local interface plane coincides with the fixed water
# octagon. At Y>=2 the natural rock is free up to the separately stated 3m cap.
octagon=[(x-6,z-26) for x,z in contract['world_foundation']['outer']]
for i,(x,z) in enumerate(octagon):
 x2,z2=octagon[(i+1)%8];dx=x2-x;dz=z2-z
 # Listed polygon is CCW in XZ; outward normal is right of each edge.
 nx,nz=dz,-dx;length=math.hypot(nx,nz);nx/=length;nz/=length
 cut_plane(base,(x,1,z),(nx,-.25,nz),'water_join')
ASSET.append(base)

# Necessary civil interface only: exact submerged 1m socket. It is not the
# six-metre visible form generator and cannot become a long dry cap/column.
vv=[bp((x,y,z)) for y in [0,1.015] for x,z in octagon]
ff=[tuple(reversed(range(8))),tuple(range(8,16))]+[(i,(i+1)%8,(i+1)%8+8,i+8) for i in range(8)]
socket=make_mesh('ExactSubmergedSocket_ONLY_1m',vv,ff);socket.parent=root;materialize(socket,True)
bm=bmesh.new();bm.from_mesh(socket.data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(socket.data);bm.free();ASSET.append(socket)

# Avoid visible coplanar top surfaces: assign three shallow seat zones. The
# buried lower rocks continue to interpenetrate intentionally and stay editable.
def shallow_ownership_cut(ob,cut_z,above):
 bpy.ops.mesh.primitive_cube_add(size=1,location=bp((0,6.5,cut_z+(5 if above else -5))))
 cutter=bpy.context.object;cutter.name='TEMP_SeatOwnership';cutter.dimensions=(8,10,1.0);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 # Blender dimensions order X,Y(depth),Z(height), slab bottom Ygodot=6.0.
 mod=ob.modifiers.new('LocalSeatOwnership','BOOLEAN');mod.operation='DIFFERENCE';mod.solver='EXACT';mod.object=cutter
 bpy.context.view_layer.objects.active=ob;ob.select_set(True);cutter.select_set(False);bpy.ops.object.modifier_apply(modifier=mod.name);bpy.data.objects.remove(cutter,do_unlink=True)
shallow_ownership_cut(ASSET[0],-1.10,True)
shallow_ownership_cut(ASSET[1],-1.10,False);shallow_ownership_cut(ASSET[1],1.10,True)
shallow_ownership_cut(ASSET[2],1.10,False)
for ob in ASSET:triangulate(ob)
for name,point in [('GroundOrigin',(0,0,0)),('GateSeat',(0,6.1,0)),('Waterline',(0,1,0))]:
 ob=bpy.data.objects.new(name,None);parts.objects.link(ob);ob.parent=root;ob.location=bp(point);ob.empty_display_type='PLAIN_AXES';ob.empty_display_size=.18

checks=[]
def ck(name,passed,detail=None):checks.append({'name':name,'pass':bool(passed),'detail':detail})
for ob in ASSET:
 s=stats(ob);STATS.append(s);ck(ob.name+'_closed_one_component',s['boundary_edges']==0 and s['nonmanifold_edges']==0 and s['components']==1 and s['volume_m3']>0,s)
 ck(ob.name+'_no_detected_self_crossings',not s['self_intersections']['strict_crossings'],s['self_intersections'])
 print('MESH_AUDIT',ob.name,s['triangles'],s['boundary_edges'],len(s['self_intersections']['strict_crossings']),flush=True)
trees=[(ob,tree_for(ob)) for ob in ASSET]
def ray_height(x,z):
 rows=[]
 for ob,tr in trees:
  h=tr.ray_cast(bp((x,7,z)),bp((0,-1,0)),8)
  if h[0] is not None:rows.append((float(gp(h[0]).y),ob.name))
 return max(rows) if rows else (None,None)
support=[{'x':float(x),'z':float(z),'height':ray_height(x,z)[0],'mesh':ray_height(x,z)[1]} for x in np.linspace(-.5,.5,5) for z in np.linspace(-3.5,3.5,29)]
actual=[{'x':x,'z':z,'height':ray_height(x,z)[0],'mesh':ray_height(x,z)[1]} for group in contacts['groups'] for x,_,z in group['local_gate_vertices']]
ck('actual_36_frozen_gate_lower_vertices_at_Y6_1',all(q['height'] is not None and abs(q['height']-6.1)<1e-5 for q in actual),{'samples':len(actual),'failed':[q for q in actual if q['height'] is None or abs(q['height']-6.1)>=1e-5]})
ck('conservative_nominal_1x7_gate_footprint_supported',all(q['height'] is not None and abs(q['height']-6.1)<1e-5 for q in support),{'samples':len(support),'failed':[q for q in support if q['height'] is None or abs(q['height']-6.1)>=1e-5]})
allp=np.concatenate([np.array([tuple(gp(v.co)) for v in ob.data.vertices]) for ob in ASSET]);bb={'min':allp.min(0).tolist(),'max':allp.max(0).tolist()}
ck('allowed_3m_free_width_7_5m_length_and_6_1m_height',bb['min'][0]>=-1.50001 and bb['max'][0]<=1.50001 and bb['min'][1]>=-1e-5 and bb['max'][1]<=6.10001 and bb['min'][2]>=-3.75001 and bb['max'][2]<=3.75001,bb)
# Real water slice audit: all intersections of every asset triangle at Y=1
# must remain in the original octagon; the socket guarantees its full boundary.
def in_oct(x,z,tol=2e-6):
 for i,(a,b) in enumerate(octagon):
  c,d=octagon[(i+1)%8]
  if (c-a)*(z-b)-(d-b)*(x-a)<-tol:return False
 return True
waterpoints=[]
for ob in ASSET:
 pp=[gp(v.co) for v in ob.data.vertices]
 for tri in ob.data.loop_triangles:
  q=[pp[k] for k in tri.vertices]
  for a,b in zip(q,q[1:]+q[:1]):
   if (a.y<1)!=(b.y<1):
    t=(1-a.y)/(b.y-a.y);p=a+(b-a)*t;waterpoints.append((p.x,p.z))
ck('water_slice_exact_octagon_no_rock_outside',len(waterpoints)>0 and all(in_oct(x,z) for x,z in waterpoints),{'samples':len(waterpoints),'outside':[list(p) for p in waterpoints if not in_oct(*p)],'socket_area_m2':18.25})
ck('submerged_socket_bottom_original_octagon',abs(min(gp(v.co).y for v in socket.data.vertices))<1e-6 and all(in_oct(gp(v.co).x,gp(v.co).z) for v in socket.data.vertices))

# Actual internal seam visibility: cast from the review camera to milled/end
# faces. Cross-object intersections are intentional; an exposed cap is reported.
cam_pos=Vector((12,10,11))
cap_visibility=[]
for ob in ASSET[:3]:
 visible=0;tested=0;area=0.0
 for poly in ob.data.polygons:
  if poly.normal.z<.98:continue
  centre=poly.center;h=gp(centre).y
  if abs(h-6.0)>.001:continue
  tested+=1;d=centre-cam_pos;dist=d.length;d.normalize();nearest=None
  for other,tr in trees:
   hit=tr.ray_cast(cam_pos,d,dist+.01)
   if hit[0] is not None and (nearest is None or hit[3]<nearest[0]):nearest=(hit[3],other.name)
  if nearest and nearest[1]==ob.name and abs(nearest[0]-dist)<.003:visible+=1;area+=poly.area
 cap_visibility.append({'mesh':ob.name,'shallow_seat_shelf_triangles':tested,'visible_triangles':visible,'visible_area_m2':area})
ck('milled_internal_seat_shelves_hidden_in_assembly',all(q['visible_triangles']==0 for q in cap_visibility),cap_visibility)
ck('readonly_inputs_unchanged',all(SHA(ROOT/p)==h for p,h in hashes.items()))
tris=sum(s['triangles'] for s in STATS)

# Frozen real gate is a reference assembly only, never part of the foundation.
existing=set(bpy.data.objects);bpy.ops.import_scene.gltf(filepath=str(ROOT/contacts['source']))
gate_objects=set(bpy.data.objects)-existing;gate_col=bpy.data.collections.new('REFERENCE_FrozenGate_P3_NOT_FOUNDATION');scene.collection.children.link(gate_col)
for ob in gate_objects:
 relink(ob,gate_col)
 if ob.parent not in gate_objects:ob.location+=bp((0,8.6,0))
 ob['reference_only']=True
 # Quiet neutral gate makes the new foundation form legible in this basic study.
 if ob.type=='MESH':
  ob.data.materials.clear();ob.data.materials.append(material('ReferenceGate_'+ob.name,(.22,.255,.25),.85))

floor_mat=material('StudioFloor',(.165,.18,.19),.95)
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.025));floor=bpy.context.object;floor.name='StudioFloor_NOT_ASSET';floor.data.materials.append(floor_mat)
world=bpy.data.worlds.new('P2_ReviewWorld');scene.world=world;world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.48,.50,.52,1);world.node_tree.nodes['Background'].inputs[1].default_value=.65
def light(name,location,energy,size):
 d=bpy.data.lights.new(name,'AREA');ob=bpy.data.objects.new(name,d);scene.collection.objects.link(ob);ob.location=location;d.energy=energy;d.shape='DISK';d.size=size;ob.rotation_euler=(Vector((0,0,4))-ob.location).to_track_quat('-Z','Y').to_euler()
light('Key',(6,7,15),1900,9);light('Fill',(-6,-4,9),1000,8)
c=bpy.data.cameras.new('FoundationReview_Oblique');camera=bpy.data.objects.new('FoundationReview_Oblique',c);scene.collection.objects.link(camera);camera.location=cam_pos;camera.rotation_euler=(Vector((0,0,3.05))-camera.location).to_track_quat('-Z','Y').to_euler();c.type='ORTHO';c.ortho_scale=10.5;scene.camera=camera
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=12;scene.cycles.use_denoising=True
scene.render.resolution_x=1200;scene.render.resolution_y=960;scene.render.resolution_percentage=100;scene.view_settings.view_transform='AgX';scene.render.image_settings.file_format='PNG'
source_path=HERE/'seal_foundation_p2.blend'
gate_col.hide_render=True
bpy.ops.wm.save_as_mainfile(filepath=str(source_path))
report={'stage':'one basic-color source/assembly study, not PBR, not GLB, not game approval','source_sha256':SHA(source_path),'readonly_inputs':hashes,'bounds_local_godot':bb,'outward_extension_from_original_x_m':{'negative':max(0,-1.25-bb['min'][0]),'positive':max(0,bb['max'][0]-1.25)},'natural_sources':[{k:v for k,v in r.items() if k not in ['vertices','triangles']} for r in native],'poses':POSES,'meshes':STATS,'checks':checks,'passed':sum(c['pass'] for c in checks),'total':len(checks),'all_pass':all(c['pass'] for c in checks),'triangles':tris,'triangle_target_note':'approximately 30k is a target; measured count is reported without destructive simplification','nominal_support_rays':support,'actual_gate_contacts':actual,'visible_internal_shelves':cap_visibility,'method':'3 independent rigid/uniform Boulder01 LOD3 bodies + natural Nama bearing + only 1m exact submerged socket. Local clipping/seat ownership, no global warp, no voxel union.','limitations':['cross-object deep overlaps intentional and not self-intersections','individual shared-vertex triangle pairs excluded by self-crossing audit','basic source only; no runtime collision/flight tests','actual image can still fail artistic reference despite geometry checks'],'elapsed_before_render_s':time.time()-start}
(HERE/'form_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('FOUNDATION_P2_CHECKS',report['passed'],report['total'],'triangles',tris,'failures',[q['name'] for q in checks if not q['pass']],flush=True)
# A diagnostic image is intentionally retained even when a form/interface check
# fails. It is never relabelled a passed candidate or exported to production.
gate_col.hide_render=True;scene.render.filepath=str(HERE/'seal_foundation_p2_basic.png');bpy.ops.render.render(write_still=True)
gate_col.hide_render=False;camera.location=(16,14,16);camera.rotation_euler=(Vector((0,0,5.3))-camera.location).to_track_quat('-Z','Y').to_euler();c.ortho_scale=15;scene.render.filepath=str(HERE/'seal_foundation_p2_gate_assembly.png');bpy.ops.render.render(write_still=True)
assert all(SHA(ROOT/p)==h for p,h in hashes.items())
print('FOUNDATION_P2_EXIT',time.time()-start,'source',SHA(source_path),flush=True)
