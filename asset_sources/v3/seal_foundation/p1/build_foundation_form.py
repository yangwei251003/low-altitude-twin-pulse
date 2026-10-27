"""One closed thick foundation. Interface rows fixed; geological faces vary inward.
Source-only form study. No PBR, GLB, Godot or production data write.
Godot local origin at world (6,-3.2,26); Blender coordinates (x,-z,y).
"""
from pathlib import Path
import bpy,bmesh,math,json,hashlib,struct
from mathutils import Vector
from mathutils.bvhtree import BVHTree
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
contract=json.loads((HERE/'interface.json').read_text(encoding='utf-8'))
input_paths=[ROOT/x['path'] for x in contract['readonly_inputs']]
contact_record=json.loads((HERE/'door_bottom_contact.json').read_text(encoding='utf-8'));input_paths.append(ROOT/contact_record['source'])
input_hashes={p.relative_to(ROOT).as_posix():sha(p) for p in input_paths}
reference=ROOT/'references/v3/production/seal_foundation/seal_foundation_reference_v1.png'
assert sha(reference)=='e197ae5f8d144923038ba50b0c4684de05a652f96ebff4352d87c33f7931fe89'
layout=json.loads((ROOT/'data/v3/terrain/f1_growth_crossing.json').read_text(encoding='utf-8'));f=layout['gate_foundation']
assert f['top_y']==2.9 and f['bottom_y']==-3.2 and f['outer']==contract['world_foundation']['outer']
bpy.ops.wm.read_factory_settings(use_empty=True);scene=bpy.context.scene
col=bpy.data.collections.new('Editable_SealFoundation');scene.collection.children.link(col)
root=bpy.data.objects.new('SealFoundationP1',None);col.objects.link(root)
root['origin_world_godot']=[6,-3.2,26];root['interface_water_local_y']=1.0;root['stage']='source form only'
gp=lambda p:Vector((p.x,p.z,-p.y))
bp=lambda x,y,z:Vector((x,-z,y))

# Nonuniform width stations describe four broad structural faces, not a tile grid.
# Their y levels differ by station and side, producing diagonal, staggered shoulders.
zs=[-3.75,-3.50,-3.25,-2.60,-1.95,-1.30,-.90,-.20,.55,1.10,1.65,2.35,2.95,3.25,3.50,3.75]
def plan_half(z):return 1.25-max(0,abs(z)-3.25)
def clamp(x,a,b):return min(b,max(a,x))
def tri_lobe(z,centre,width):return max(0,1-abs(z-centre)/width)
def levels(z,side):
 # Only a few directional cleavage/shoulder levels, each spanning a broad zone.
 # No random per-vertex perturbation or long thin detached column construction.
 a=2.30+.18*z+.37*tri_lobe(z,-2.05,1.4)
 b=4.10-.16*z-.36*tri_lobe(z,.75,1.6)
 if side<0:a=2.62-.13*z+.20*tri_lobe(z,1.8,1.8);b=4.37+.10*z-.25*tri_lobe(z,-1.5,1.5)
 a=clamp(a,1.55,3.15);b=clamp(b,3.45,4.95)
 return [0,1,a-.18,a,a+.16,b-.16,b,b+.18,5.83,6.1]
def half_surface(z,y,row,side):
 limit=plan_half(z)
 if row in [0,1]:return limit # exact bed/water contour, no flared toes
 # Broad longitudinal geological divisions; inward creases change phase with height.
 seam_a=-1.45+.13*(y-3);seam_b=1.25-.11*(y-3)
 crease=.15*tri_lobe(z,seam_a,.55)+.12*tri_lobe(z,seam_b,.60)
 if side<0:crease=.12*tri_lobe(z,-.55-.13*(y-3),.70)+.09*tri_lobe(z,2.30,.55)
 broad=.055+.055*tri_lobe(z,-2.6,1.3)+.035*tri_lobe(z,.1,2)
 # Lower face undercut -> thick ledge -> inner face; ledges don't repeat at one height.
 inset={2:.25,3:.31,4:.055,5:.14,6:.27,7:.06,8:.11,9:.045}[row]
 if row==9:crease=0;broad=.035 # quiet horizontal load-bearing shoulder
 return max(.60,limit-inset-broad-crease)

verts=[];rings=[];front_grid=[];back_grid=[]
for row in range(10):
 front=[];back=[]
 for side,ids in [(1,front),(-1,back)]:
  for z in zs:
   y=levels(z,side)[row];x=side*half_surface(z,y,row,side)
   ids.append(len(verts));verts.append(bp(x,y,z))
 front_grid.append(front);back_grid.append(back);rings.append(front+list(reversed(back)))
faces=[];regions=[]
for row in range(9):
 for side,grid in [(1,front_grid),(-1,back_grid)]:
  for j in range(len(zs)-1):
   a,b=grid[row][j:j+2];c,d=grid[row+1][j:j+2]
   faces.append((a,b,d,c) if side>0 else (b,a,c,d));regions.append('WetBase' if row==0 else 'CleavageShoulders' if row in [3,6] else 'RockFaces')
 # Close both narrow ends with the same connected mesh; no exposed hidden box.
 for j in [0,len(zs)-1]:
  faces.append((front_grid[row][j],back_grid[row][j],back_grid[row+1][j],front_grid[row+1][j]));regions.append('WetBase' if row==0 else 'RockFaces')
faces.append(tuple(reversed(rings[0])));regions.append('WetBase')
faces.append(tuple(rings[-1]));regions.append('BearingShoulder')
mesh=bpy.data.meshes.new('Connected_ThickRock_Surface');mesh.from_pydata(verts,[],faces);mesh.update()
bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(mesh);bm.free()
body=bpy.data.objects.new('FoundationRockBody',mesh);col.objects.link(body);body.parent=root
body['construction']='Single closed thick body with broad staggered front/back fracture surfaces; fixed water/bed octagon. No booleans, voxel or detached plates.'
def mat(name,color,rough):
 m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True;p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED');p.inputs['Base Color'].default_value=(*color,1);p.inputs['Roughness'].default_value=rough;p.inputs['Specular IOR Level'].default_value=.18;return m
mats=[mat('Basic_CoolRock',(.235,.275,.285),.88),mat('Basic_QuietWornShoulder',(.29,.30,.29),.88),mat('Basic_LowWetBand',(.105,.135,.127),.77)]
for m in mats:mesh.materials.append(m)
for p,label in zip(mesh.polygons,regions):p.material_index=2 if label=='WetBase' else 1 if label in ['BearingShoulder','CleavageShoulders'] else 0;p.use_smooth=False
for label,indices in [('BedRing',rings[0]),('WaterlineRing',rings[1]),('BearingRim',rings[-1]),('LongFaceFront',[i for row in front_grid for i in row]),('LongFaceBack',[i for row in back_grid for i in row])]:
 vg=body.vertex_groups.new(name=label);vg.add(indices,1.0,'REPLACE')
for name,point in [('GroundOrigin',(0,0,0)),('GateSeat',(0,6.1,0)),('Waterline',(0,1,0))]:
 ob=bpy.data.objects.new(name,None);col.objects.link(ob);ob.parent=root;ob.location=bp(*point);ob.empty_display_type='PLAIN_AXES';ob.empty_display_size=.18

# Read real source mesh; contacts and waterline are not inferred from the render.
checks=[]
def check(name,ok,detail=None):checks.append({'name':name,'pass':bool(ok),'detail':detail})
mesh.calc_loop_triangles();bm=bmesh.new();bm.from_mesh(mesh)
check('single_closed_manifold',all(e.is_manifold for e in bm.edges),{'boundary_edges':sum(e.is_boundary for e in bm.edges),'nonmanifold_edges':sum(not e.is_manifold for e in bm.edges)})
volume=bm.calc_volume(signed=True);check('positive_volume',volume>0,volume)
seen=set();components=0
for v in bm.verts:
 if v in seen:continue
 components+=1;stack=[v];seen.add(v)
 while stack:
  q=stack.pop()
  for e in q.link_edges:
   other=e.other_vert(q)
   if other not in seen:seen.add(other);stack.append(other)
check('one_connected_rock_component',components==1,components);bm.free()
points=[gp(v.co) for v in mesh.vertices];bounds={'min':[min(p[k] for p in points) for k in range(3)],'max':[max(p[k] for p in points) for k in range(3)]}
check('exact_7_5x2_5x6_1_overall_envelope',all(abs(bounds['min'][k]-v)<1e-5 for k,v in enumerate([-1.25,0,-3.75])) and all(abs(bounds['max'][k]-v)<1e-5 for k,v in enumerate([1.25,6.1,3.75])),bounds)
local_oct=[Vector((x-6,z-26)) for x,z in f['outer']]
def edge_distance(p,a,b):
 t=clamp((p-a).dot(b-a)/(b-a).length_squared,0,1);return (p-a-(b-a)*t).length
for row,label,height in [(0,'bed',0),(1,'waterline',1)]:
 p=[points[i] for i in rings[row]]
 errs=[min(edge_distance(Vector((v.x,v.z)),local_oct[j],local_oct[(j+1)%8]) for j in range(8)) for v in p]
 area=abs(sum(p[i].x*p[(i+1)%len(p)].z-p[(i+1)%len(p)].x*p[i].z for i in range(len(p)))/2)
 check(label+'_exact_fixed_octagon',max(errs)<1e-6 and abs(area-18.25)<1e-6 and all(abs(v.y-height)<1e-6 for v in p),{'max_boundary_error_m':max(errs),'area_m2':area,'local_y':height})
tree=BVHTree.FromPolygons([v.co for v in mesh.vertices],[tuple(t.vertices) for t in mesh.loop_triangles],all_triangles=True)
hits=[]
for x in [-.5,-.25,0,.25,.5]:
 for k in range(29):
  z=-3.5+k*.25;hit=tree.ray_cast(bp(x,7,z),Vector((0,0,-1)),2)
  hits.append({'x':x,'z':z,'y':gp(hit[0]).y if hit[0] else None})
check('full_nominal_gate_footprint_supported_Y6_1',all(p['y'] is not None and abs(p['y']-6.1)<1e-5 for p in hits),{'rays':len(hits),'min_y':min(p['y'] for p in hits if p['y'] is not None),'max_y':max(p['y'] for p in hits if p['y'] is not None)})
actual_hits=[]
for group in contact_record['groups']:
 for x,_,z in group['local_gate_vertices']:
  hit=tree.ray_cast(bp(x,7,z),Vector((0,0,-1)),2);actual_hits.append(gp(hit[0]).y if hit[0] else None)
check('actual_frozen_P3_lower_vertices_supported',all(y is not None and abs(y-6.1)<1e-5 for y in actual_hits),{'P3_glb_sha256':contact_record['sha256'],'actual_lower_vertices':len(actual_hits)})
check('no_top_obstacle_above_gate_contact',max(p.y for p in points)<=6.10001)
check('source_triangle_budget_30000',len(mesh.loop_triangles)<=30000,len(mesh.loop_triangles))
check('height_grid_no_surface_folding',all(levels(z,side)[i+1]>levels(z,side)[i] for z in zs for side in [-1,1] for i in range(9)))
check('front_back_never_cross',all(half_surface(z,levels(z,side)[row],row,side)>0 for row in range(10) for z in zs for side in [-1,1]))
check('readonly_project_inputs_unchanged',all(sha(ROOT/p)==v for p,v in input_hashes.items()))

# Basic-color neutral studio; this is deliberately not a game image.
floor_m=mat('Studio_NeutralFloor',(.16,.175,.18),.92)
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.025));floor=bpy.context.object;floor.name='StudioFloor_NotAsset';floor.data.materials.append(floor_m)
world=bpy.data.worlds.new('FoundationReviewWorld');scene.world=world;world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.40,.44,.47,1);world.node_tree.nodes['Background'].inputs[1].default_value=.6
def area_light(name,location,energy,size):
 d=bpy.data.lights.new(name,'AREA');o=bpy.data.objects.new(name,d);scene.collection.objects.link(o);o.location=location;d.energy=energy;d.shape='DISK';d.size=size;o.rotation_euler=(Vector((0,0,3))-o.location).to_track_quat('-Z','Y').to_euler()
area_light('StudioKey',(4,6,12),1500,9);area_light('StudioFill',(-6,-3,7),650,8)
c=bpy.data.cameras.new('DefaultOblique');camera=bpy.data.objects.new('DefaultOblique',c);scene.collection.objects.link(camera);camera.location=(12,10,11);camera.rotation_euler=(Vector((0,0,3.05))-camera.location).to_track_quat('-Z','Y').to_euler();c.type='ORTHO';c.ortho_scale=10.5;scene.camera=camera
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=12;scene.cycles.use_denoising=True;scene.render.threads_mode='FIXED';scene.render.threads=2;scene.render.resolution_x=1200;scene.render.resolution_y=960;scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX';scene.render.image_settings.file_format='PNG'
path=HERE/'seal_foundation_form_p1.blend';bpy.ops.wm.save_as_mainfile(filepath=str(path))
report={'stage':'source basic-color form; no PBR/GLB/game validation','source_sha256':sha(path),'reference_sha256':sha(reference),'readonly_inputs':input_hashes,'vertices':len(mesh.vertices),'triangles':len(mesh.loop_triangles),'volume_m3':volume,'bounds_local_godot':bounds,'origin_world_godot':[6,-3.2,26],'anchors_local_godot':{'GroundOrigin':[0,0,0],'GateSeat':[0,6.1,0],'Waterline':[0,1,0]},'checks':checks,'passed':sum(c['pass'] for c in checks),'total':len(checks),'all_pass':all(c['pass'] for c in checks),'support_rays':hits,'method':'One thick closed graph surface, front/back with broad directional fracture shoulders; no voxel/boolean/disconnected plates. Water/bed exact octagon, top contact planar.','limits':['no final artistic approval','no GLB or engine import','graph ordering and manifold tests are not a general self-intersection certificate','triangulated broad quads may show facet diagonals; inspect actual image']}
(HERE/'form_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print('FOUNDATION_FORM_CHECKS',report['passed'],report['total'],json.dumps([c for c in checks if not c['pass']]),flush=True)
assert report['all_pass'],'Hard interface check failed; no render'
scene.render.filepath=str(HERE/'seal_foundation_form_p1.png');bpy.ops.render.render(write_still=True);assert all(sha(ROOT/p)==v for p,v in input_hashes.items());print('FOUNDATION_FORM_DONE',sha(path),flush=True)
