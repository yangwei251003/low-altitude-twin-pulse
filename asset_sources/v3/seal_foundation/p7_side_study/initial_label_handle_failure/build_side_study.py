"""P7 one bounded east-side patch with ordered arc-length parameter domain, source only. Numeric gates precede images.
Keep old boundary vertices and join new triangles onto those SAME BMVerts.
Two explicit broad planes inside; CDT only triangulates fixed constraints.
No PBR, GLB, runtime changes, remeshing or automated whole-body simplification.
"""
from pathlib import Path
import bpy,bmesh,numpy as np,json,hashlib,os,sys,time,math,ast,traceback
from mathutils import Vector
from mathutils.geometry import delaunay_2d_cdt
from mathutils.bvhtree import BVHTree
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
sys.dont_write_bytecode=True;sys.path.insert(0,str(ROOT/'asset_sources/v3/shore_root/p12'))
from geometry_checks import strict_self_intersections
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
bp=lambda p:Vector((p[0],-p[2],p[1]))
gp=lambda p:Vector((p.x,p.z,-p.y))
source=HERE.parent/'p5/seal_foundation_p5.blend'
assert sha(source)=='41fc1fd582245bdeea28f6644858886d432a4ac3a9124a8d189ff75cb9bbe93f'
script5=HERE.parent/'p5/build_foundation_p5.py'
frozen={str(p):sha(p) for p in [source,script5,HERE.parent/'p5/form_report.json',HERE.parent/'p5/actual_water_section.json']}
frozen.update({str(p):sha(p) for p in [HERE.parent/'p6_side_study/build_side_study.py',HERE.parent/'p6_side_study/diagnostic.json',HERE.parent/'p6_side_study/side_report.json']})
start=time.time();report={'stage':'P7 bounded source-side patch study; no runtime or PBR/GLB','pid':os.getpid(),'source_sha256':sha(source),'frozen_inputs':frozen,'checks':[],'images':[]}
checks=report['checks']
def ck(name,ok,detail=None):checks.append({'name':name,'pass':bool(ok),'detail':detail})
def write_report():
 report['elapsed_s']=time.time()-start;report['passed']=sum(c['pass'] for c in checks);report['total']=len(checks);report['all_pass']=all(c['pass'] for c in checks)
 (HERE/'side_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
def require(name,ok,detail=None):
 ck(name,ok,detail);write_report()
 if not ok:
  report['failed_gate']=name
  try:
   if 'rock' in globals():
    if 'bm' in globals() and bm is not None and bm.is_valid:
     bm.to_mesh(rock.data);rock.data.update()
    failed=HERE/'seal_foundation_p7_failed.blend'
    bpy.ops.wm.save_as_mainfile(filepath=str(failed))
    report['failed_source']={'file':failed.name,'sha256':sha(failed),'status':'FAILED_INTERMEDIATE_NOT_RENDERED'}
  except Exception as e:report['failure_save_error']=repr(e)
  write_report()
  raise RuntimeError('Stop before rendering: '+name)
print('SIDE_STUDY_PID',os.getpid(),flush=True)
bpy.ops.wm.open_mainfile(filepath=str(source));scene=bpy.context.scene
scene.render.threads_mode='FIXED';scene.render.threads=2;scene.cycles.device='CPU';scene.cycles.samples=16
rock=bpy.data.objects['MiddleSliceNaturalBody'];beam=bpy.data.objects['TempleBearingBeam']
f5=script5.read_text(encoding='utf-8');tree5=ast.parse(f5)
for node in tree5.body:
 if isinstance(node,ast.FunctionDef) and node.name in ['tree','mesh_stats','section_loops','tri_box_overlap','solid_inside']:
  exec(compile(ast.Module(body=[node],type_ignores=[]),str(script5),'exec'),globals())
original=rock.copy();original.data=rock.data.copy();original.name='SOURCE_P5_Body_Unmodified_Hidden'
hc=bpy.data.collections.new('SOURCE_P5_SideStudy_Hidden');scene.collection.children.link(hc);hc.objects.link(original);hc.hide_render=True;hc.hide_viewport=True
before_tree=tree(original);before_stats=mesh_stats(original);before_water=section_loops(original,1)
old_camera_matrix=scene.camera.matrix_world.copy();old_ortho=scene.camera.data.ortho_scale
def geo_hash(ob):
 return hashlib.sha256(np.array([tuple(v.co) for v in ob.data.vertices],dtype='<f8').tobytes()+str([tuple(f.vertices) for f in ob.data.polygons]).encode()).hexdigest()
beam_hash=geo_hash(beam)
planes=[('bed',(0,0,0),(0,1,0)),('bearing',(0,5.65,0),(0,1,0)),('east_shoulder',(0,6.4955,0),(.85,1,.05)),('west_shoulder',(0,6.4,0),(-.9,1,-.04)),('positive_shoulder',(0,5.65,3.8),(0,1,1.1)),('negative_shoulder',(0,5.65,-3.78),(0,1,-1.35))]
def protected_summary(ob):
 rows={}
 for name,co,no in planes:
  co=bp(co);no=bp(no).normalized();fs=[f for f in ob.data.polygons if all(abs(no.dot(ob.data.vertices[i].co-co))<2e-5 for i in f.vertices)]
  rows[name]={'area':sum(f.area for f in fs),'vertices':[tuple(ob.data.vertices[i].co) for f in fs for i in f.vertices]}
 return rows
before_protected=protected_summary(original)

# The patch is on the visible +X wall, waterline upward, below shoulder.
y0,y1=1.0,4.25;z0,z1=-1.15,1.55
report['patch_domain_local_godot']={'side':'+X','y':[y0,y1],'z':[z0,z1],'scope':'One connected outside wall only; no other side replacement'}
bm=bmesh.new();bm.from_mesh(rock.data)
for co,no in [((0,y0,0),(0,1,0)),((0,y1,0),(0,1,0)),((0,0,z0),(0,0,1)),((0,0,z1),(0,0,1))]:
 bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),plane_co=bp(co),plane_no=bp(no),dist=1e-7,clear_inner=False,clear_outer=False)
bm.normal_update();bm.faces.ensure_lookup_table()
chosen=[]
for f in bm.faces:
 p=gp(f.calc_center_median())
 if p.x>.45 and y0+1e-6<p.y<y1-1e-6 and z0+1e-6<p.z<z1-1e-6:chosen.append(f)
require('nonempty_local_patch',bool(chosen),{'faces':len(chosen)})
cs=set(chosen);be=[e for e in bm.edges if sum(f in cs for f in e.link_faces)==1 and any(f not in cs for f in e.link_faces)]
adj={}
for e in be:
 for v in e.verts:adj.setdefault(v,[]).append(e.other_vert(v))
require('patch_boundary_degree_two',bool(adj) and all(len(a)==2 for a in adj.values()),{'boundary_edges':len(be),'bad_degrees':[len(a) for a in adj.values() if len(a)!=2]})
first=next(iter(adj));loop=[first];prev=None;cur=first
while True:
 nxt=next(v for v in adj[cur] if v!=prev)
 if nxt==first:break
 if nxt in loop:raise RuntimeError('Boundary repeats before closing')
 loop.append(nxt);prev,cur=cur,nxt
require('patch_has_one_boundary_loop',len(loop)==len(adj),{'loop_vertices':len(loop),'all_boundary_vertices':len(adj)})
uv=[Vector((gp(v.co).z,gp(v.co).y)) for v in loop]
def cross(a,b,c):return (b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x)
area=sum(a.x*b.y-b.x*a.y for a,b in zip(uv,uv[1:]+uv[:1]))*.5
if area<0:loop.reverse();uv.reverse();area=-area
# P6's real 3D boundary is valid, but its YZ projection folds back on the
# upper edge. Do not sort/merge/delete vertices to force a graph. Parameterize
# each existing ordered side by 3D arc length on a simple rectangle. The actual
# BMVerts/coordinates remain unchanged; this changes only CDT coordinates.
p6=json.loads((HERE.parent/'p6_side_study/diagnostic.json').read_text(encoding='utf-8'))
recorded=p6['diagnostic_all_edges']
require('all_118_original_boundary_segments_preserved_before_parameterization',len(loop)==118 and len(recorded)==118 and all((gp(loop[i].co)-Vector(recorded[i]['coords_local_godot'][0])).length<1e-7 and (gp(loop[(i+1)%len(loop)].co)-Vector(recorded[i]['coords_local_godot'][1])).length<1e-7 for i in range(len(loop))),{'count':len(loop),'comparison':'ordered 3D endpoints against frozen P6 diagnostic, tolerance 1e-7m'})
raw_uv=[p.copy() for p in uv]
corners=[Vector((z1,y0)),Vector((z1,y1)),Vector((z0,y1)),Vector((z0,y0))]
corner_ids=[]
for c in corners:
 ids=[i for i,p in enumerate(raw_uv) if (p-c).length<2e-5]
 require('unique_original_corner_'+str(len(corner_ids)),len(ids)==1,ids)
 corner_ids.append(ids[0])
uv=[None]*len(loop);side_rows=[]
for si,a in enumerate(corner_ids):
 b=corner_ids[(si+1)%4];ids=[a]
 while ids[-1]!=b:ids.append((ids[-1]+1)%len(loop))
 lengths=[(loop[v].co-loop[u].co).length for u,v in zip(ids,ids[1:])]
 require('parameter_side_has_positive_edge_lengths_'+str(si),all(x>0 for x in lengths),{'indices':ids,'arc_length_m':sum(lengths)})
 total=sum(lengths);cum=0
 for k,idx in enumerate(ids):
  if k:cum+=lengths[k-1]
  t=cum/total;uv[idx]=corners[si].lerp(corners[(si+1)%4],t)
 side_rows.append({'side_index':si,'corner_vertex_ids':[a,b],'original_ordered_ids':ids,'three_dimensional_arc_length_m':total,'length_m':lengths})
require('parameter_assignment_complete',all(v is not None for v in uv))
# Unlike P6, catch collinear overlap as well as transverse crossings.
parameter_overlaps=[]
for i in range(len(uv)):
 for j in range(i+1,len(uv)):
  if j==(i+1)%len(uv) or i==(j+1)%len(uv):continue
  a,b=uv[i],uv[(i+1)%len(uv)];c,d=uv[j],uv[(j+1)%len(uv)]
  strict=cross(a,b,c)*cross(a,b,d)<-1e-14 and cross(c,d,a)*cross(c,d,b)<-1e-14
  collinear=abs(cross(a,b,c))<1e-9 and abs(cross(a,b,d))<1e-9
  axis=0 if abs(b.x-a.x)>=abs(b.y-a.y) else 1
  overlap=min(max(a[axis],b[axis]),max(c[axis],d[axis]))-max(min(a[axis],b[axis]),min(c[axis],d[axis]))
  if strict or (collinear and overlap>1e-8):parameter_overlaps.append({'edges':[i,j],'collinear':collinear,'overlap':float(overlap)})
require('arc_parameter_boundary_simple_no_collinear_overlap',not parameter_overlaps,parameter_overlaps)
report['parameterization']={'method':'ordered per-side 3D arc-length map to simple rectangle; no boundary reorder, removal, merge or 3D movement','sides':side_rows,'vertices':[{'id':i,'original_3d_godot':list(gp(loop[i].co)),'raw_YZ':list(raw_uv[i]),'CDT_parameter':list(uv[i])} for i in range(len(loop))],'P6_failed_edge_ids':p6['diagnostic_failed_indices']}

# Fit only the gross wall orientation. Two authored broad planes replace fine
# grooves; interior points are NOT shrinkwrapped back onto those grooves.
samples=[]
for y in np.linspace(1.35,3.9,8):
 for z in np.linspace(-.90,1.25,9):
  hit=before_tree.ray_cast(bp((5,float(y),float(z))),bp((-1,0,0)),8)
  if hit[0] is not None:samples.append([float(y),float(z),float(gp(hit[0]).x)])
require('gross_surface_samples',len(samples)==72,{'samples':len(samples)})
A=np.array([[1,s[0]-2.625,s[1]] for s in samples]);sol=np.linalg.lstsq(A,np.array([s[2] for s in samples]),rcond=None)[0]
report['gross_surface_fit']={'constant':float(sol[0]),'y_slope':float(sol[1]),'z_slope':float(sol[2]),'rms_before':float(np.sqrt(np.mean((A@sol-np.array([s[2] for s in samples]))**2)))}
iy0,iy1=1.28,3.97
basez=[-.91,.13,1.25];shear=.20/(iy1-iy0)
control=[]
for y in [iy0,iy1]:
 for k,zbase in enumerate(basez):
  z=zbase+shear*(y-iy0);x=float(sol[0]+sol[1]*(y-2.625)+sol[2]*z+([-.035,.13,-.035][k]))
  control.append((x,y,z))
# One common shift, if necessary, keeps the authored face inside the old AABB;
# not per-vertex projection into old grooves.
limit=max(gp(v.co).x for v in original.data.vertices)
offset=max(0,max(q[0] for q in control)-limit)
control=[(x-offset,y,z) for x,y,z in control]
report['authoring']={'planes':2,'inner_controls_godot':control,'common_x_shift_to_old_bounds':offset,'reason':'two broad nonparallel planes with a slanted common crease; boundary unchanged'}
N=len(loop);coords=uv+[Vector((q[2],q[1])) for q in control]
edges=[(i,(i+1)%N) for i in range(N)]+[(N,N+1),(N+1,N+2),(N+2,N+5),(N+5,N+4),(N+4,N+3),(N+3,N),(N+1,N+4)]
outv,oute,outf,origv,orige,origf=delaunay_2d_cdt(coords,edges,[list(range(N))],1,1e-9,True)
boundary_map={}
for oi,ids in enumerate(origv):
 ids=[i for i in ids if i<N]
 if ids:
  require('no_CDT_boundary_merge_'+str(oi),len(ids)==1,ids);boundary_map[ids[0]]=oi
require('CDT_retains_all_shared_boundary_vertices',len(boundary_map)==N,{'retained':len(boundary_map),'expected':N})
require('CDT_has_no_unowned_inserted_vertices',all(ids for ids in origv),{'unowned_indices':[i for i,ids in enumerate(origv) if not ids]})
old_boundary_coordinates={id(v):v.co.copy() for v in loop}
report['removed_patch_faces']=len(chosen);report['boundary_vertex_count']=N
patch_layer=bm.faces.layers.int.new('P7_side_patch')
for f in bm.faces:f[patch_layer]=0
boundary_before=[]
for i,v in enumerate(loop):
 w=loop[(i+1)%N];e=next(e for e in v.link_edges if e.other_vert(v)==w)
 boundary_before.append({'edge':i,'coords_local_godot':[list(gp(v.co)),list(gp(w.co))],'length_m':e.calc_length(),'old_faces':sum(f not in cs for f in e.link_faces),'removed_faces':sum(f in cs for f in e.link_faces)})
# Delete old patch faces, and only now remove resulting orphan interior edges.
bmesh.ops.delete(bm,geom=chosen,context='FACES_ONLY')
for e in list(bm.edges):
 if not e.link_faces:bm.edges.remove(e)
for v in list(bm.verts):
 if not v.link_edges:bm.verts.remove(v)
vmap=[]
for oi,ids in enumerate(origv):
 idx=ids[0]
 if idx<N:vmap.append(loop[idx])
 else:vmap.append(bm.verts.new(bp(control[idx-N])))
newfaces=[]
for tri in outf:
 f=bm.faces.new([vmap[i] for i in tri]);f.smooth=False;f.material_index=0;f[patch_layer]=1;newfaces.append(f)
bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.normal_update()
shared=[]
newset=set(newfaces)
for i,v in enumerate(loop):
 w=loop[(i+1)%N];es=[e for e in v.link_edges if e.other_vert(v)==w]
 shared.append(bool(len(es)==1 and len(es[0].link_faces)==2 and sum(f in newset for f in es[0].link_faces)==1))
report['boundary_adjacency']=[]
for i,v in enumerate(loop):
 w=loop[(i+1)%N];es=[e for e in v.link_edges if e.other_vert(v)==w];row=dict(boundary_before[i])
 row.update({'after_edge_count':len(es),'new_faces':sum(f in newset for e in es for f in e.link_faces),'retained_faces':sum(f not in newset for e in es for f in e.link_faces),'passes_original_gate':shared[i]});report['boundary_adjacency'].append(row)
require('all_boundary_edges_shared_old_and_new_faces',all(shared),{'edges':N,'failed':[i for i,q in enumerate(shared) if not q]})
require('shared_boundary_coordinates_exact',all((v.co-old_boundary_coordinates[id(v)]).length==0 for v in loop))
report['new_patch_triangles']=len(newfaces)
minangles=[];areas=[];interior_faces=[]
for f in newfaces:
 vv=[v.co.copy() for v in f.verts];lens=[(vv[(i+1)%3]-vv[i]).length for i in range(3)];angles=[]
 for i in range(3):
  a=vv[(i+1)%3]-vv[i];b=vv[(i+2)%3]-vv[i]
  angles.append(math.degrees(a.angle(b)))
 minangles.append(min(angles));areas.append(f.calc_area())
 if all(v not in loop for v in f.verts):interior_faces.append({'area':f.calc_area(),'min_angle_degrees':min(angles),'normal_blender':list(f.normal)})
report['triangle_quality']={'minimum_angle_degrees':min(minangles),'triangles_below_5_degrees':sum(a<5 for a in minangles),'minimum_area_m2':min(areas),'broad_interior_faces':interior_faces,'note':'thin boundary transitions are reported, not automatically excused; images only after topology gates'}
require('new_triangles_not_degenerate',min(areas)>1e-10,{'minimum_area_m2':min(areas)})
bm.to_mesh(rock.data);bm.free();bm=None;rock.data.update();rock.data.set_sharp_from_angle(angle=math.radians(28))
after_stats=mesh_stats(rock);report['before_mesh']=before_stats;report['after_mesh']=after_stats
require('new_body_closed_one_positive_component',after_stats['boundary_edges']==0 and after_stats['nonmanifold_edges']==0 and after_stats['components']==1 and after_stats['volume_m3']>0,after_stats)
# Detailed retained/new adjacency on every reported intersecting pair, so a
# failure is inspectable without another model run or a guessed parameter sweep.
rock.data.calc_loop_triangles();at=rock.data.attributes.get('P7_side_patch')
labels=[int(v.value) for v in at.data] if at else [0]*len(rock.data.polygons)
edge_faces={}
for f in rock.data.polygons:
 ids=list(f.vertices)
 for a,b in zip(ids,ids[1:]+ids[:1]):edge_faces.setdefault(tuple(sorted((a,b))),[]).append(f.index)
pair_details=[]
for pair in after_stats['self_intersections']['strict_crossings']:
 row={'reported':pair,'members':[]}
 for ti in pair['triangles']:
  t=rock.data.loop_triangles[ti];pi=t.polygon_index;p=rock.data.polygons[pi];ids=list(p.vertices)
  row['members'].append({'triangle':ti,'polygon':pi,'is_new_patch':bool(labels[pi]),'vertex_ids':list(t.vertices),'coords_local_godot':[list(gp(rock.data.vertices[v].co)) for v in t.vertices],'polygon_edge_neighbors':[{'edge':[a,b],'neighbor_polygons':edge_faces[tuple(sorted((a,b)))],'neighbor_is_new_patch':[bool(labels[x]) for x in edge_faces[tuple(sorted((a,b)))]]} for a,b in zip(ids,ids[1:]+ids[:1])]})
 pair_details.append(row)
report['self_intersection_adjacency']=pair_details
require('new_body_no_detected_self_intersections',not after_stats['self_intersections']['strict_crossings'],after_stats['self_intersections'])
after_tree=tree(rock);after_protected=protected_summary(rock)
prot=[]
for name,row in before_protected.items():
 distances=[float(after_tree.find_nearest(Vector(v))[3]) for v in row['vertices']]
 other=after_protected[name];prot.append({'name':name,'before_area':row['area'],'after_area':other['area'],'area_delta':other['area']-row['area'],'max_old_vertex_surface_distance':max(distances) if distances else None})
require('protected_bed_bearing_shoulders_preserved',all(abs(r['area_delta'])<1e-4 and (r['max_old_vertex_surface_distance'] or 0)<2e-5 for r in prot),prot)
require('beam_geometry_exactly_unchanged',geo_hash(beam)==beam_hash,{'sha256':beam_hash})
after_water=section_loops(rock,1)
def segdist(p,a,b):
 p=Vector(p);a=Vector(a);b=Vector(b);ab=b-a
 return (p-(a+ab*max(0,min(1,(p-a).dot(ab)/max(ab.length_squared,1e-20))))).length
def directed_section(a,b):
 edges=[(p,q) for r in b['loops'] for p,q in zip(r['points'],r['points'][1:]+r['points'][:1])]
 return max(min(segdist(p,x,y) for x,y in edges) for r in a['loops'] for p in r['points'])
wd=max(directed_section(before_water,after_water),directed_section(after_water,before_water))
require('actual_waterline_unchanged',wd<2e-5 and after_water['all_nodes_degree_2'],{'bidirectional_vertex_to_segment_distance_m':wd,'before_loops':len(before_water['loops']),'after_loops':len(after_water['loops'])})
oldbounds=np.array(before_stats['bounds_local']);newbounds=np.array(after_stats['bounds_local']);growth=np.maximum(oldbounds[0]-newbounds[0],newbounds[1]-oldbounds[1])
report['volume_change_m3']=after_stats['volume_m3']-before_stats['volume_m3'];report['AABB_outward_change_per_axis_m']=growth.tolist()
require('no_AABB_growth',np.max(growth)<2e-5,report['AABB_outward_change_per_axis_m'])
# Old protected-region mesh distances are checked; real Godot movement is not.
report['channel_scope']='Patch localY1..4.25 => worldY-2.2..1.05, below HX02 expanded bottom2.56, unchanged upper shoulders and beam. No new Godot physical sweep claimed.'
require('patch_below_low_flight_envelope',y1-3.2<2.56,{'patch_world_max_y':y1-3.2,'protected_low_flight_world_min_y':2.56})
require('all_frozen_inputs_unchanged',all(sha(Path(p))==h for p,h in frozen.items()))
report['scope_limits']=['One side only','No materials/texture refinement','Numeric geometry gates are not aesthetic acceptance','No Godot, human play or performance test','Self audit excludes shared-vertex triangle pairs; independent coplanar overlap audit included']
out=HERE/'seal_foundation_p7_side_study.blend';bpy.ops.wm.save_as_mainfile(filepath=str(out));report['source_sha256_out']=sha(out);write_report()
print('SIDE_NUMERIC_PASS',report['passed'],report['total'],'triangles',after_stats['triangles'],flush=True)
scene.camera.matrix_world=old_camera_matrix;scene.camera.data.ortho_scale=old_ortho;bpy.context.view_layer.update()
scene.render.filepath=str(HERE/'side_study_whole.png');bpy.ops.render.render(write_still=True);report['images'].append({'file':'side_study_whole.png','camera':'exact P5 basic view','sha256':sha(HERE/'side_study_whole.png')})
camera=scene.camera;c=camera.data;offset=bp((32,39,32));framing=[]
node=next(n for n in tree5.body if isinstance(n,ast.FunctionDef) and n.name=='frame');exec(compile(ast.Module(body=[node],type_ignores=[]),str(script5),'exec'),globals())
patchpoints=[bp((x,y,z)) for x in [.5,2.25] for y in [.6,4.6] for z in [z0-.3,z1+.3]]
frame(patchpoints,1.22);scene.render.filepath=str(HERE/'side_study_close.png');bpy.ops.render.render(write_still=True);report['images'].append({'file':'side_study_close.png','camera':'same fixed oblique direction, closer framing','sha256':sha(HERE/'side_study_close.png')})
report['close_framing']=framing;write_report();print('SIDE_EXIT_SECONDS',time.time()-start,flush=True)
