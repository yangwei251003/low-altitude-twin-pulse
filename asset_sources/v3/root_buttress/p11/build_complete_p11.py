"""P11 bounded rock refinement and natural fork roots; explicit material source."""
import bpy,bmesh,math,json,hashlib,struct,sys
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
runtime={str(h):sha(ROOT/f'assets/v3/root_buttress/root_buttress_h{h}.glb') for h in [10,12,17,3]}
source=HERE.parent/'p10/root_buttress_h10_refined_cliff_p10.blend';source_sha=sha(source)
fork_source=ROOT/'asset_sources/v3/shore_root/p9/rigid_root_main_form.blend';fork_sha=sha(fork_source)
bpy.ops.wm.open_mainfile(filepath=str(source));scene=bpy.context.scene;root=bpy.data.objects['RootButtress'];body=bpy.data.objects['RockMasses'];sap=bpy.data.objects['SapKnot'];col=bpy.data.collections['Editable_RootButtress'];sap.hide_render=False
anchors={n:bpy.data.objects[n] for n in ['GroundOrigin','BodyPerch','HostTarget','LowerShelf']}
def bp(p):return Vector((p[0],-p[2],p[1]))
def gp(p):return Vector((p.x,p.z,-p.y))
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
def clean(ob):
 bm=bmesh.new();bm.from_mesh(ob.data);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-6);bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=1e-7);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(ob.data);bm.free();ob.data.update()
def mesh(name,vertices,faces):
 data=bpy.data.meshes.new(name+'_Mesh');data.from_pydata([bp(v) for v in vertices],[],faces);data.update();ob=bpy.data.objects.new(name,data);col.objects.link(ob);ob.parent=root;clean(ob);return ob
def boolean(cutter):
 bpy.context.view_layer.objects.active=body;m=body.modifiers.new('P11_BoundedFracture','BOOLEAN');m.operation='DIFFERENCE';m.solver='EXACT';m.object=cutter;bpy.ops.object.modifier_apply(modifier=m.name);bpy.data.objects.remove(cutter,do_unlink=True)
# Clean ridge front geometrically with a continuous two-plane air wedge.
cross=[(-8,13.28),(-3.9,10),(8,10),(8,15),(-8,15)]
vv=[(x,y,z) for x in [-9,9] for z,y in cross];ff=[tuple(reversed(range(5))),tuple(range(5,10))]+[(i,(i+1)%5,(i+1)%5+5,i+5) for i in range(5)]
boolean(mesh('TemporaryRearRidgeGeometricTrim',vv,ff))
# A few wide fracture faces, not a repeated narrow crack network.
def fracture(name,polygon,axis,plane):
 vv=[]
 for depth in [0,1]:
  for u,y in polygon:
   v=plane(u,y) if depth==0 else 9
   vv.append((u,y,v) if axis=='front' else (v,y,u))
 n=len(polygon);ff=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
 boolean(mesh(name,vv,ff))
fracture('TemporaryFrontBroadFracture',[(1.8,6.0),(2.2,8.8),(4.7,8.1),(4.3,5.3),(3.0,4.8)],'front',lambda x,y:4.20+.09*(y-7)+.05*(x-3))
fracture('TemporaryRightBroadFracture',[(-3.8,3.8),(-3.2,7.7),(-1.2,8.5),(-.4,5.5),(-1.4,3.5)],'right',lambda z,y:4.30+.06*(y-6)-.045*(z+2))
bm=bmesh.new();bm.from_mesh(body.data)
edges=[e for e in bm.edges if all(gp(v.co).y>9.8 and gp(v.co).z<-3.4 for v in e.verts)]
bmesh.ops.dissolve_limit(bm,angle_limit=math.radians(2),use_dissolve_boundaries=False,verts=list({v for e in edges for v in e.verts}),edges=edges,delimit={'NORMAL'})
bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(body.data);bm.free();clean(body)
def tree(items):
 vs=[];fs=[]
 for ob in items:
  ob.data.calc_loop_triangles();off=len(vs);vs.extend(ob.matrix_world@v.co for v in ob.data.vertices);fs.extend(tuple(off+i for i in f.vertices) for f in ob.data.loop_triangles)
 return BVHTree.FromPolygons(vs,fs,all_triangles=True)
bpy.context.view_layer.update();rock_bvh=tree([body])
def wall_depth(side,u,y):
 if side=='front':o=(u,y,9);d=(0,0,-1);component=2;fallback=4.5
 elif side=='right':o=(9,y,u);d=(-1,0,0);component=0;fallback=4.8
 else:o=(-9,y,u);d=(1,0,0);component=0;fallback=-4.8
 hit=rock_bvh.ray_cast(bp(o),bp(d),18)
 if hit[0] is None:return fallback
 p=gp(hit[0]);value=p[component]
 if side in ['front','right'] and value<2:return fallback
 if side=='left' and value>-2:return fallback
 return value
# Read only the frozen genuine coarse-fork source, not its studio/rock shoulder.
with bpy.data.libraries.load(str(fork_source),link=False) as (data_from,data_to):data_to.objects=['P9_Natural_Fork_Rigid_3x_No_Stretch']
fork=data_to.objects[0];col.objects.link(fork)
# Local mesh is still original Blender-converted source coordinates, before its
# P9 world transform. Trim only the two documented fine branches at source X=-.6.
bm=bmesh.new();bm.from_mesh(fork.data)
r=bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),plane_co=Vector((-.6,0,0)),plane_no=Vector((-1,0,0)),dist=1e-6,clear_outer=True)
edges=[e for e in r['geom_cut'] if isinstance(e,bmesh.types.BMEdge) and e.is_boundary]
if edges:bmesh.ops.holes_fill(bm,edges=edges,sides=0)
bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(fork.data);bm.free()
fork.matrix_world.identity();fork.parent=None
archive=bpy.data.collections.new('P11_ReadOnlyForkCopyAndUnbakedSources');scene.collection.children.link(archive);archive.hide_render=True;archive.hide_viewport=True
col.objects.unlink(fork);archive.objects.link(fork);fork.name='Original_ClippedFork_LocalCoordinates';fork.hide_render=True
roots=[];root_specs=[('Root_FrontSap','front',3.9,10.9,-.25,.34),('Root_RightFork','right',3.3,9.2,-.6,.36)]
for name,side,scale,top,offset,flatten in root_specs:
 ob=bpy.data.objects.new(name,fork.data.copy());col.objects.link(ob);ob.parent=root;ob.data.materials.clear()
 for layer in list(ob.data.uv_layers):ob.data.uv_layers.remove(layer)
 uv=ob.data.uv_layers.new(name='RecipeUV');uv.active_render=True
 originals=[gp(v.co) for v in ob.data.vertices]
 for poly in ob.data.polygons:
  for li in poly.loop_indices:
   p=originals[ob.data.loops[li].vertex_index];uv.data[li].uv=(p.z*.33+p.x*.17,p.y*.46)
 for v,p in zip(ob.data.vertices,originals):
  u=-p.z*scale+offset;y=top-(p.y-.1)*scale
  surface=wall_depth(side,u,y);tip=max(0,min(1,(p.y-1.95)/.25));bury=-.35+1.25*tip
  if side!='front':bury+=1.05*max(0,min(1,(.32-p.y)/.22))
  thickness=(p.x+.10)*scale*flatten
  if side=='front':
   t=max(0,min(1,(y-9.1)/1.8));surface=surface*(1-t)+4.05*t
   q=(u,y,surface-bury+thickness)
  elif side=='right':q=(surface-bury+thickness,y,u)
  else:q=(surface+bury-thickness,y,u)
  v.co=bp(q)
 clean(ob)
 bpy.context.view_layer.objects.active=ob;m=ob.modifiers.new('NaturalForkModerateRetopology','DECIMATE');m.ratio=.60;m.use_collapse_triangulate=True;bpy.ops.object.modifier_apply(modifier=m.name);clean(ob)
 for f in ob.data.polygons:f.use_smooth=True
 ob['source']='island_tree_01 mesh0 primitive0 Y.1..2.2 X[-.6,.4], natural fork retained'
 ob['adaptation']='original length/lateral uniform scale, flattened normal section, surface-conforming depth; tips embedded in rock'
 roots.append(ob)
def make_material(name,image_path,kind):
 mat=bpy.data.materials.new(name);mat.use_nodes=True;nodes=mat.node_tree.nodes;links=mat.node_tree.links;p=next(n for n in nodes if n.type=='BSDF_PRINCIPLED')
 im=bpy.data.images.load(str(image_path),check_existing=False);im.colorspace_settings.name='sRGB';im.pack();tex=nodes.new('ShaderNodeTexImage');tex.image=im
 if kind=='stone':
  coord=nodes.new('ShaderNodeTexCoord');scale=nodes.new('ShaderNodeVectorMath');scale.operation='SCALE';scale.inputs[3].default_value=.125;links.new(coord.outputs['Object'],scale.inputs[0]);links.new(scale.outputs[0],tex.inputs['Vector']);tex.projection='BOX';tex.projection_blend=.35
 else:
  uv=nodes.new('ShaderNodeUVMap');uv.uv_map='RecipeUV';links.new(uv.outputs['UV'],tex.inputs['Vector'])
 quiet=nodes.new('ShaderNodeMixRGB');quiet.blend_type='MIX';quiet.name='P11_LowContrastBroadMaterial';quiet.inputs[0].default_value=.45 if kind=='stone' else .30;quiet.inputs[2].default_value=(.17,.20,.21,1) if kind=='stone' else (.12,.085,.052,1);links.new(tex.outputs['Color'],quiet.inputs[1]);links.new(quiet.outputs[0],p.inputs['Base Color']);p.inputs['Roughness'].default_value=.88 if kind=='stone' else .82;p.inputs['Specular IOR Level'].default_value=.16
 bw=nodes.new('ShaderNodeRGBToBW');links.new(tex.outputs['Color'],bw.inputs[0]);bump=nodes.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.12;bump.inputs['Distance'].default_value=.04;links.new(bw.outputs[0],bump.inputs['Height']);links.new(bump.outputs['Normal'],p.inputs['Normal'])
 return mat
stone=make_material('P11_Stone_Recipe',HERE.parent/'p3/textures/RB_Stone_BaseColor_P3.png','stone');bark=make_material('P11_Bark_Recipe',HERE.parent/'p3/textures/RB_Bark_BaseColor_P3.png','bark')
body.data.materials.clear();body.data.materials.append(stone)
for o in roots:o.data.materials.append(bark)
bpy.context.view_layer.update();static=tree([body,*roots]);sap_bvh=tree([sap]);root_bvh=tree(roots)
checks=[]
def check(name,ok,detail=None):checks.append({'name':name,'pass':bool(ok),'detail':detail})
def topology(ob):
 bm=bmesh.new();bm.from_mesh(ob.data);d={'boundary_edges':sum(e.is_boundary for e in bm.edges),'nonmanifold_edges':sum(not e.is_manifold for e in bm.edges),'signed_volume':bm.calc_volume(signed=True)};left=set(bm.verts);counts=[]
 while left:
  stack=[left.pop()];count=0
  while stack:
   v=stack.pop();count+=1
   for e in v.link_edges:
    w=e.other_vert(v)
    if w in left:left.remove(w);stack.append(w)
  counts.append(count)
 d['components']=counts;bm.free();return d
for o in [body,*roots]:
 t=topology(o);check(o.name+'_closed_one_component',t['boundary_edges']==0 and t['nonmanifold_edges']==0 and len(t['components'])==1 and t['signed_volume']>0,t)
feet=[(-2.54,2.17),(2.51,2.22),(-2.28,-2.5),(2.31,-2.48)]
for i,(x,z) in enumerate(feet):
 points=[(x,z)]+[(x+r*math.cos(a*math.tau/64),z+r*math.sin(a*math.tau/64)) for r in [.25,.5,.75] for a in range(64)];hits=[]
 for a,b in points:
  h=static.ray_cast(bp((a,15,b)),bp((0,-1,0)),18);hits.append(list(gp(h[0])) if h[0] else None)
 bad=[{'xz':p,'hit':h} for p,h in zip(points,hits) if h is None or abs(h[1]-10)>.001];check(f'foot_{i}_193_Y10',not bad,{'probes':len(points),'failures':bad})
lower=[]
for dx,dz in [(0,0),(-.25,0),(.25,0),(0,-.25),(0,.25)]:
 h=static.ray_cast(bp((-3.7+dx,6,3.2+dz)),bp((0,-1,0)),2);lower.append(list(gp(h[0])) if h[0] else None)
check('LowerShelf_5_points_Y5',all(h and abs(h[1]-5)<.001 for h in lower),lower)
target=bp((0,11,4.5))
for i,o in enumerate([(0,11,8),(-3,12,8),(3,12,8)]):
 origin=bp(o);d=target-origin;sh=sap_bvh.ray_cast(origin,d.normalized(),d.length+1);rh=static.ray_cast(origin,d.normalized(),d.length+1);check('Sap_LOS_'+str(i),sh[0] is not None and (rh[0] is None or rh[3]>sh[3]+.01),{'sap_distance':sh[3],'solid_distance':rh[3]})
nearest=root_bvh.find_nearest(target);delta=gp(nearest[0])-Vector((0,11,4.5)) if nearest[0] else Vector((100,100,100));ellipsoid=(delta.x/.57)**2+(delta.y/.78)**2+(delta.z/.4)**2
check('living_root_enters_Sap_volume',ellipsoid<.93,{'closest':list(gp(nearest[0])) if nearest[0] else None,'ellipsoid':ellipsoid})
parts=[body,*roots,sap];points=[gp(o.matrix_world@v.co) for o in parts for v in o.data.vertices];bounds={'min':[min(p[k] for p in points) for k in range(3)],'max':[max(p[k] for p in points) for k in range(3)]};lo=[-6.610198020935059,0,-6.804511547088623];hi=[6.905734539031982,11.93212890625,6.879329681396484]
check('original_bounds',all(bounds['min'][k]>=lo[k]-.0001 and bounds['max'][k]<=hi[k]+.0001 for k in range(3)),bounds)
check('Sap_and_4_anchors_unchanged',fixed=={o.name:digest(o) for o in [sap,*anchors.values()]})
check('P10_and_root_vendor_source_unchanged',sha(source)==source_sha and sha(fork_source)==fork_sha)
check('runtime_P2_frozen',all(sha(ROOT/f'assets/v3/root_buttress/root_buttress_h{h}.glb')==v for h,v in runtime.items()))
stats=[]
for o in parts:o.data.calc_loop_triangles();stats.append({'name':o.name,'triangles':len(o.data.loop_triangles),'vertices':len(o.data.vertices)})
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=8;scene.cycles.use_denoising=True;scene.render.threads_mode='FIXED';scene.render.threads=2;scene.render.resolution_x=1024;scene.render.resolution_y=800;scene.render.resolution_percentage=100
blend=HERE/'root_buttress_h10_complete_p11.blend';bpy.ops.wm.save_as_mainfile(filepath=str(blend))
report={'stage':'complete P11 source pre-bake candidate','source_sha256':sha(blend),'input_P10_sha256':source_sha,'natural_fork_source_sha256':fork_sha,'fixed_hashes':fixed,'runtime_P2_sha256':runtime,'stats':stats,'bounds_godot':bounds,'anchors_godot':{n:list(gp(o.matrix_world.translation)) for n,o in anchors.items()},'checks':checks,'passed':sum(c['pass'] for c in checks),'total':len(checks),'all_pass':all(c['pass'] for c in checks),'root_adaptation_specs':root_specs,'limits':['actual full-Crown sweep and Godot camera not performed','natural tree fork adapted as roots; not unmodified scan','broad fracture faces and ridge cleanup are authored geometry','material recipe unbaked; runtime candidate not exported yet']}
(HERE/'p11_source_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8');print('P11_SOURCE '+json.dumps(report,ensure_ascii=False),flush=True)
assert report['all_pass'],'Stop on concrete geometry failure before render/bake/export'
if '--render' in sys.argv:scene.render.filepath=str(HERE/'h10_p11_complete_material_source.png');bpy.ops.render.render(write_still=True)
print('P11_SOURCE_DONE',flush=True)
