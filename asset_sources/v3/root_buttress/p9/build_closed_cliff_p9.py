"""Closed, thick cliff trial from a rigidly aligned CC0 rock-face surface."""
import bpy,bmesh,json,math,hashlib,struct,sys
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
import numpy as np
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];sys.path.insert(0,str(HERE))
from plan_cliff_sections import upright_source,bilinear_sample,load
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
frozen={}
for folder in ['p3','p4','p5','p6','p7','p8']:
 for p in (HERE.parent/folder).rglob('*'):
  if p.is_file() and '__pycache__' not in p.parts and p.suffix!='.blend1':frozen[str(p.relative_to(ROOT))]=sha(p)
runtime={str(h):sha(ROOT/f'assets/v3/root_buttress/root_buttress_h{h}.glb') for h in [10,12,17,3]}
bpy.ops.wm.open_mainfile(filepath=str(HERE.parent/'p3/root_buttress_h10_p3_export_ready.blend'))
scene=bpy.context.scene;root=bpy.data.objects['RootButtress'];col=bpy.data.collections['Editable_RootButtress'];sap=bpy.data.objects['SapKnot'];anchors={n:bpy.data.objects[n] for n in ['GroundOrigin','BodyPerch','HostTarget','LowerShelf']}
def digest(ob):
 h=hashlib.sha256();h.update(struct.pack('<16d',*(v for row in ob.matrix_world for v in row)))
 if ob.type=='MESH':
  for v in ob.data.vertices:h.update(struct.pack('<3d',*v.co))
  for f in ob.data.polygons:h.update(struct.pack('<'+str(len(f.vertices))+'I',*f.vertices))
  for layer in ob.data.uv_layers:
   h.update(layer.name.encode())
   for v in layer.data:h.update(struct.pack('<2d',*v.uv))
 return h.hexdigest()
fixed={o.name:digest(o) for o in [sap,*anchors.values()]}
for ob in list(root.children_recursive):
 if ob.type=='MESH' and ob!=sap:bpy.data.objects.remove(ob,do_unlink=True)
sap.hide_render=True
def bp(p):return Vector((p[0],-p[2],p[1]))
def gp(p):return Vector((p.x,p.z,-p.y))
def mat(name,c):
 m=bpy.data.materials.new(name);m.use_nodes=True;p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED');p.inputs['Base Color'].default_value=(*c,1);p.inputs['Roughness'].default_value=.87;p.inputs['Specular IOR Level'].default_value=.2;return m
stone=mat('P9_NaturalCliff_Basic',(.22,.25,.26))
def mesh_obj(name,verts,faces,collection=col,parent=root):
 me=bpy.data.meshes.new(name+'_Mesh');me.from_pydata(verts,[],faces);me.update();bm=bmesh.new();bm.from_mesh(me);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free();ob=bpy.data.objects.new(name,me);collection.objects.link(ob);ob.parent=parent;me.materials.append(stone);return ob
archive=bpy.data.collections.new('P9_SourceAndClosedBodyBeforeCuts');scene.collection.children.link(archive);archive.hide_render=True;archive.hide_viewport=True
raw,raw_faces=load('rock_face_01');source=mesh_obj('Original_A_ReadOnlyGeometryCopy',[bp(v) for v in raw],raw_faces.tolist(),archive,None);source.hide_render=True;source.hide_viewport=True
field=upright_source();ys=np.linspace(0,11.2,81);us=np.linspace(-3.7,3.7,57)
profiles={};distances={}
for y in ys:
 samples=[bilinear_sample(field,float(u),float(y)) for u in us];profiles[float(y)]=[p[0] for p in samples];distances[float(y)]=[p[1] for p in samples]
max_delta=max(max(p) for p in profiles.values())
base={'front':min(5.0,6.80-max_delta),'right':min(5.0,6.80-max_delta),'back':min(5.0,6.75-max_delta),'left':min(5.0,6.55-max_delta)}
verts=[];rings=[]
for y in ys:
 d=profiles[float(y)]
 sides=[[(float(u),float(y),base['front']+delta) for u,delta in zip(us,d)],[(base['right']+delta,float(y),float(-u)) for u,delta in zip(us,d)],[(float(-u),float(y),-base['back']-delta) for u,delta in zip(us,d)],[(-base['left']-delta,float(y),float(u)) for u,delta in zip(us,d)]]
 perimeter=[]
 for i,side in enumerate(sides):
  perimeter.extend(side);a=Vector(side[-1]);b=Vector(sides[(i+1)%4][0])
  # New short corner faces close the natural front/right sheets; no source
  # vertex is stretched and these seams are explicitly reconstructed geometry.
  for t in [.2,.4,.6,.8]:perimeter.append(tuple(a.lerp(b,t)))
 rings.append(perimeter);verts.extend(bp(p) for p in perimeter)
n=len(rings[0]);faces=[]
for j in range(len(ys)-1):
 for i in range(n):faces.append((j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i))
faces.extend([tuple(reversed(range(n))),tuple((len(ys)-1)*n+i for i in range(n))])
body=mesh_obj('RockMasses',verts,faces);body['semantic_group']='RockMasses';body['construction']='rigid CC0 cliff surface resampling + new corner/back closure; single thick connected body'
for p in body.data.polygons:p.use_smooth=len(p.vertices)==4
cp=body.copy();cp.data=body.data.copy();archive.objects.link(cp);cp.parent=None;cp.hide_render=True;cp.hide_viewport=True;cp.name='ClosedFullHeightBody_BeforeTopAndShelfCuts'
def clip(ob,point,normal,keep_negative=True):
 bm=bmesh.new();bm.from_mesh(ob.data);r=bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=.000001,plane_co=bp(point),plane_no=bp(normal),clear_outer=keep_negative,clear_inner=not keep_negative)
 edges=[e for e in r['geom_cut'] if isinstance(e,bmesh.types.BMEdge) and e.is_boundary];filled=bmesh.ops.holes_fill(bm,edges=edges,sides=0)
 for f in filled.get('faces',[]):f.smooth=False
 bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(ob.data);bm.free();ob.data.update()
def boolean(target,cutter,operation):
 bpy.context.view_layer.objects.active=target;mod=target.modifiers.new('Connected geological cut','BOOLEAN');mod.operation=operation;mod.solver='EXACT';mod.object=cutter;bpy.ops.object.modifier_apply(modifier=mod.name);bpy.data.objects.remove(cutter,do_unlink=True)
# Cut air away from the one closed original volume. Keeping the rear ridge
# integral avoids the previous coincident overlapping-surface union.
def box_cut(name,lo,hi):
 vv=[bp((x,y,z)) for y in [lo[1],hi[1]] for z in [lo[2],hi[2]] for x in [lo[0],hi[0]]]
 ff=[(0,1,3,2),(4,6,7,5),(0,4,5,1),(2,3,7,6),(0,2,6,4),(1,5,7,3)]
 boolean(body,mesh_obj(name,vv,ff),'DIFFERENCE')
box_cut('TemporaryFrontAir',(-20,10,-3.75),(20,20,20))
box_cut('TemporaryRearLeftAir',(-20,10,-20),(-3.1,20,-3.70))
box_cut('TemporaryRearRightAir',(-.8,10,-20),(20,20,-3.70))
clip(body,(-2.0,11.1,-4.5),(-.1,1,.08),True)
# A single diagonal geological recess, not a rectangular shelf stuck on.
xz=[(-20,-13.75),(-20,20),(13.75,20)];vv=[bp((x,y,z)) for y in [5,15] for x,z in xz];ff=[(2,1,0),(3,4,5),(0,1,4,3),(1,2,5,4),(2,0,3,5)]
cutter=mesh_obj('TemporaryLeftShelfCut',vv,ff);boolean(body,cutter,'DIFFERENCE')
# Clean coincident cut vertices while preserving the clipped source shape.
bm=bmesh.new();bm.from_mesh(body.data);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.00001);bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=.000001);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(body.data);bm.free();body.data.update()
uv=body.data.uv_layers.new(name='ProvisionalUV');uv.active_render=True
for f in body.data.polygons:
 axis=max(range(3),key=lambda k:abs(f.normal[k]));axes=[k for k in range(3) if k!=axis]
 for li in f.loop_indices:
  v=body.data.vertices[body.data.loops[li].vertex_index].co;uv.data[li].uv=(v[axes[0]]*.1,v[axes[1]]*.1)
bpy.context.view_layer.update()
def tree(ob):
 ob.data.calc_loop_triangles();return BVHTree.FromPolygons([ob.matrix_world@v.co for v in ob.data.vertices],[tuple(t.vertices) for t in ob.data.loop_triangles],all_triangles=True)
bvh=tree(body);sap_tree=tree(sap)
def down(x,z,start=15):
 h=bvh.ray_cast(bp((x,start,z)),bp((0,-1,0)),30);return list(gp(h[0])) if h[0] else None
checks=[]
def check(name,passed,detail=None):checks.append({'name':name,'pass':bool(passed),'detail':detail})
check('fixed_sap_geometry_uv_transform_and_anchors',fixed=={o.name:digest(o) for o in [sap,*anchors.values()]})
feet=[(-2.54,2.17),(2.51,2.22),(-2.28,-2.5),(2.31,-2.48)]
for i,(x,z) in enumerate(feet):
 probes=[(x,z)]+[(x+r*math.cos(a*math.tau/64),z+r*math.sin(a*math.tau/64)) for r in [.25,.5,.75] for a in range(64)];hits=[down(a,b) for a,b in probes];bad=[{'xz':p,'hit':h} for p,h in zip(probes,hits) if h is None or abs(h[1]-10)>.001]
 check('foot_'+str(i)+'_193_probes_Y10',not bad,{'probes':len(probes),'failures':bad})
lower=[down(-3.7+dx,3.2+dz,6) for dx,dz in [(0,0),(-.25,0),(.25,0),(0,-.25),(0,.25)]];check('lower_shelf_five_probes_Y5',all(h and abs(h[1]-5)<.001 for h in lower),lower)
points=[gp(v.co) for v in body.data.vertices];bounds={'min':[min(p[k] for p in points) for k in range(3)],'max':[max(p[k] for p in points) for k in range(3)]};lo=[-6.610198020935059,0,-6.804511547088623];hi=[6.905734539031982,11.93212890625,6.879329681396484]
check('original_bounds_ground_and_ceiling',all(bounds['min'][k]>=lo[k]-.0001 and bounds['max'][k]<=hi[k]+.0001 for k in range(3)),bounds)
target=Vector((0,11,4.5))
for i,o in enumerate([(0,11,8),(-3,12,8),(3,12,8)]):
 d=target-Vector(o);sh=sap_tree.ray_cast(bp(o),bp(d.normalized()),d.length+1);rh=bvh.ray_cast(bp(o),bp(d.normalized()),d.length+1);check('sap_los_'+str(i),sh[0] is not None and (rh[0] is None or rh[3]>sh[3]+.01),{'sap_distance':sh[3],'rock_distance':rh[3]})
bm=bmesh.new();bm.from_mesh(body.data);boundary=sum(e.is_boundary for e in bm.edges);nonmanifold=sum(not e.is_manifold for e in bm.edges);volume=bm.calc_volume(signed=True);unseen=set(bm.verts);components=[]
while unseen:
 start=unseen.pop();stack=[start];count=1
 while stack:
  v=stack.pop()
  for e in v.link_edges:
   other=e.other_vert(v)
   if other in unseen:unseen.remove(other);stack.append(other);count+=1
 components.append(count)
bm.free();check('single_connected_closed_outer_shell',boundary==0 and nonmanifold==0 and len(components)==1 and volume>0,{'boundary_edges':boundary,'nonmanifold_edges':nonmanifold,'components_vertices':components,'signed_volume_m3':volume})
def section(height):
 edges=[]
 for tri in body.data.loop_triangles:
  vs=[gp(body.data.vertices[i].co) for i in tri.vertices];ps=[]
  for a,b in [(vs[0],vs[1]),(vs[1],vs[2]),(vs[2],vs[0])]:
   if (a.y<height)!=(b.y<height):
    p=a+(b-a)*((height-a.y)/(b.y-a.y));ps.append((float(p.x),float(p.z)))
  if len(ps)==2 and (Vector(ps[0])-Vector(ps[1])).length>.00001:edges.append(ps)
 adjacency={};coords={}
 for a,b in edges:
  ka=tuple(round(x,4) for x in a);kb=tuple(round(x,4) for x in b)
  if ka==kb:continue
  coords[ka]=a;coords[kb]=b;adjacency.setdefault(ka,set()).add(kb);adjacency.setdefault(kb,set()).add(ka)
 bad={str(k):len(v) for k,v in adjacency.items() if len(v)!=2};unvisited=set(adjacency);loops=[]
 while unvisited:
  start=unvisited.pop();path=[start];prev=None;current=start
  for _ in range(len(adjacency)+2):
   nexts=[n for n in adjacency[current] if n!=prev]
   if not nexts:break
   nxt=nexts[0]
   if nxt==start:break
   path.append(nxt);unvisited.discard(nxt);prev,current=current,nxt
  loops.append(path)
 area=sum(abs(sum(p[i][0]*p[(i+1)%len(p)][1]-p[(i+1)%len(p)][0]*p[i][1] for i in range(len(p)))/2) for p in loops)
 return {'y':height,'area_m2':area,'loops':len(loops),'bad_junctions':bad,'xz_bounds':[[min(k[i] for k in coords) for i in range(2)],[max(k[i] for k in coords) for i in range(2)]]}
sections=[section(y) for y in [2,4.95,5.05,8,9.9]];top_area=sections[-1]['area_m2'];ratio=min(s['area_m2'] for s in sections[:-1])/top_area
check('closed_sections_with_measured_area',all(s['loops']==1 and not s['bad_junctions'] for s in sections),{'sections':sections,'minimum_middle_to_upper_area':ratio,'note':'Area ratio is diagnostic, not a user or gameplay threshold. Natural thickness must be judged in the actual basic-color image; no extra source tilt was applied to reach an arbitrary percentage.'})
check('uniform_source_scale_and_rigid_alignment',abs(np.linalg.det(field['matrix'])-1)<1e-8,{'uniform_scale':field['scale'],'matrix':field['matrix'].tolist(),'axis_scale_ratio':1.0})
check('prior_sources_frozen',all(sha(ROOT/p)==v for p,v in frozen.items()));check('runtime_p2_frozen',all(sha(ROOT/f'assets/v3/root_buttress/root_buttress_h{h}.glb')==v for h,v in runtime.items()))
body.data.calc_loop_triangles();tris=len(body.data.loop_triangles);camera=scene.camera;t=bp((0,5.3,0));camera.location=t+bp((.535645,.652817,.535645))*35;camera.rotation_euler=(t-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.type='ORTHO';camera.data.ortho_scale=26.5
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=8;scene.cycles.use_denoising=True;scene.render.threads_mode='FIXED';scene.render.threads=2;scene.render.resolution_x=1024;scene.render.resolution_y=800;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG'
blend=HERE/'root_buttress_h10_closed_cliff_p9.blend';bpy.ops.wm.save_as_mainfile(filepath=str(blend))
report={'stage':'single closed cliff form trial; no roots/PBR/GLB','source_sha256':sha(blend),'triangles':tris,'bounds_godot':bounds,'anchors_godot':{n:list(gp(o.matrix_world.translation)) for n,o in anchors.items()},'fixed_hashes':fixed,'source_method':{'asset':'Rock Face 01','uniform_scale':field['scale'],'rigid_alignment_matrix':field['matrix'].tolist(),'mean_slope_degrees':math.degrees(math.atan(field['raw_fit'][1])),'baselines':base,'observed_normal_depth_max_m':max_delta,'grid_source_spacing_m':[float(us[1]-us[0]),float(ys[1]-ys[0])],'nearest_source_edge_distance_max_m':max(max(v) for v in distances.values()),'edge_reconstruction_note':'nearest valid samples only near scanned bottom/top boundary; new short corner faces, top and bottom closure are authored geometry, not original triangles','no_column_y_warp':True},'checks':checks,'passed':sum(c['pass'] for c in checks),'total':len(checks),'all_pass':all(c['pass'] for c in checks),'runtime_p2_sha256':runtime,'render':{'camera_direction_godot':[.535645,.652817,.535645],'target_godot':[0,5.3,0],'orthographic_size':26.5,'pixels':[1024,800],'engine':'Cycles CPU','threads':2,'samples':8},'limits':['source form candidate only; numeric passes do not accept art','resampled source surfaces plus authored closure, not unchanged scan topology','Sap unchanged but hidden in stone-only study','provisional planar UV only; no baked or photographic textures','full Crown/Godot sweep not performed']}
(HERE/'p9_geometry_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8');print('P9_REPORT '+json.dumps({k:report[k] for k in ['triangles','bounds_godot','passed','total','all_pass']}),flush=True)
for c in checks:
 if not c['pass']:print('P9_FAIL '+json.dumps(c,ensure_ascii=False),flush=True)
assert report['all_pass'],'Repair closed geometry before any render'
if '--render' in sys.argv:
 scene.render.filepath=str(HERE/'h10_p9_closed_cliff_default.png');bpy.ops.render.render(write_still=True)
assert all(sha(ROOT/p)==v for p,v in frozen.items());print('P9_DONE_SOURCE_ONLY_NO_RUNTIME_EXPORT',flush=True)
