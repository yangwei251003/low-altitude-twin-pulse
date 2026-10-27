"""P12 editable UV/PBR authoring; bounded retopology is verified before bake.

Run only after basic-form review. No runtime asset writes. The complete basic
source remains intact, high-detail meshes are also archived in this new blend.
"""
import bpy,bmesh,json,hashlib,math,shutil,struct,sys
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
OUT=Path(__file__).resolve().parent;PROJECT=OUT.parents[3]
sys.path.insert(0,str(OUT))
from geometry_checks import strict_self_intersections
SOURCE=OUT/'shore_root_t03a_p12.blend';TEX=OUT/'textures';TEX.mkdir(exist_ok=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
report=json.loads((OUT/'p12_source_report.json').read_text())
assert report['all_pass'] and sha(SOURCE)==report['source_sha256']
bpy.ops.wm.open_mainfile(filepath=str(SOURCE));scene=bpy.context.scene
asset=bpy.data.objects['ShoreRootT03A'];parts=[o for o in asset.children if o.type=='MESH']
root=bpy.data.objects['Root_MainFork'];high=bpy.data.objects['Rock_HighShoulder']
def gp(v):return Vector((v.x,v.z,-v.y))
def bp(v):return Vector((v[0],-v[2],v[1]))
def tree(ob):
 ob.data.calc_loop_triangles();return BVHTree.FromPolygons([ob.matrix_world@v.co for v in ob.data.vertices],[tuple(t.vertices) for t in ob.data.loop_triangles],all_triangles=True)
def topo(ob):
 bm=bmesh.new();bm.from_mesh(ob.data);pending=set(bm.verts);components=0
 while pending:
  components+=1;stack=[pending.pop()]
  while stack:
   v=stack.pop()
   for e in v.link_edges:
    j=e.other_vert(v)
    if j in pending:pending.remove(j);stack.append(j)
 result={'components':components,'boundary_edges':sum(e.is_boundary for e in bm.edges),'nonmanifold_edges':sum(not e.is_manifold for e in bm.edges),'signed_volume':bm.calc_volume(signed=True)};bm.free();return result
def top(t,x,z):
 p=t.ray_cast(bp((x,8,z)),bp((0,-1,0)),15)[0];return gp(p) if p is not None else None
def inside(t,p):
 votes=0
 for d in [Vector((.937,.281,.207)),Vector((-.193,.931,.311)),Vector((.271,-.347,.898))]:
  d.normalize();q=p.copy();n=0
  for _ in range(80):
   hit=t.ray_cast(q,d,50)[0]
   if hit is None:break
   n+=1;q=hit+d*.0001
  votes+=n%2
 return votes>=2
before={o.name:tree(o) for o in parts};raw_points={o.name:[o.matrix_world@v.co for v in o.data.vertices] for o in parts}
archive=bpy.data.collections.new('P12_DETAIL_BEFORE_RETOPOLOGY');scene.collection.children.link(archive);archive.hide_render=True;archive.hide_viewport=True
retopo=[]
contacts={'Rock_RearFoot':(-2.43,-2.5),'Rock_FrontFoot':(-2.31,3.03),'Rock_LowToe':(-1.45,3.65)}
base_points=[root.matrix_world@v.co for v in root.data.vertices if abs(v.co.z-.1)<1e-5]
for ob in parts:
 cp=ob.copy();cp.data=ob.data.copy();archive.objects.link(cp);cp.name='Detail_'+ob.name;cp.hide_render=True;cp.hide_viewport=True
 ob.data=ob.data.copy();ob.data.calc_loop_triangles();old_tri=len(ob.data.loop_triangles)
 if ob==root:ratio=1.
 else:
  ratio={'Rock_HighShoulder':min(.25,24000./old_tri),'Rock_RearFoot':.50,'Rock_FrontFoot':.20,'Rock_LowToe':.60}[ob.name]
  group=ob.vertex_groups.new(name='Measured_Contact_Protection')
  pinned=[]
  for v in ob.data.vertices:
   p=gp(ob.matrix_world@v.co)
   protect=p.y<.02
   if ob==high:
    protect|=(p.x>3.40 and p.y>4.38) or (2.8<p.x<4.3 and 2.9<p.y and abs(p.z)<1.35)
   else:
    x,z=contacts[ob.name];protect|=(p.x-x)**2+(p.z-z)**2<.55**2
   if protect:pinned.append(v.index)
  if pinned:group.add(pinned,1.,'REPLACE')
  bpy.context.view_layer.objects.active=ob
  mod=ob.modifiers.new('BoundedContactAwareReduction','DECIMATE');mod.ratio=ratio;mod.use_collapse_triangulate=True
  mod.vertex_group=group.name;mod.vertex_group_factor=1000.
  bpy.ops.object.modifier_apply(modifier=mod.name)
 ob.data.calc_loop_triangles();after=tree(ob)
 # Original vertex-to-new surface and new vertex-to-original surface are
 # explicit sampled surface errors; not claimed as an analytic Hausdorff bound.
 forward=max(after.find_nearest(p)[3] for p in raw_points[ob.name])
 reverse=max(before[ob.name].find_nearest(ob.matrix_world@v.co)[3] for v in ob.data.vertices)
 retopo.append({'mesh':ob.name,'ratio':ratio,'triangles_before':old_tri,'triangles_after':len(ob.data.loop_triangles),'all_original_vertices_to_new_max_m':forward,'all_new_vertices_to_original_max_m':reverse})
checks=[]
def check(n,ok,detail=None):checks.append({'name':n,'pass':bool(ok),'detail':detail})
for ob in parts:
 t=topo(ob);check(ob.name+'_closed_solid',t['components']==1 and t['boundary_edges']==0 and t['nonmanifold_edges']==0 and t['signed_volume']>0,t)
for r in retopo:check(r['mesh']+'_bounded_sampled_surface_error',max(r['all_original_vertices_to_new_max_m'],r['all_new_vertices_to_original_max_m'])<.04,r)
crossings=strict_self_intersections(high)
check('retopology_high_stone_no_nonadjacent_crossings',not crossings['strict_crossings'],crossings)
rt=tree(root)
for name,(x,z) in contacts.items():
 wp=rt.ray_cast(bp((x,-3,z)),bp((0,1,0)),12)[0];sp=top(tree(bpy.data.objects[name]),x,z)
 depth=sp.y-gp(wp).y if wp is not None and sp is not None else None
 check(name+'_contact_25_to_35mm',depth is not None and .025<depth<.035,depth)
 check(name+'_ground',min(gp(bpy.data.objects[name].matrix_world@v.co).y for v in bpy.data.objects[name].data.vertices)<=.01)
ht=tree(high);base_results=[{'inside':inside(ht,p),'nearest_m':ht.find_nearest(p)[3]} for p in base_points]
check('base_all_183_points_inside_8mm',len(base_results)==183 and all(r['inside'] and r['nearest_m']>=.008 for r in base_results),base_results)
join=[top(ht,x,z) for x in [3.55,4.,4.49] for z in [-2.75,-1.375,0,1.375,2.75]]
check('interface_15_probes_Y4_5',all(p is not None and abs(p.y-4.5)<.001 for p in join))
face_join=[ht.ray_cast(bp((7,y,z)),bp((-1,0,0)),5)[0]
 for y in [.25,1.,2.,3.,4.25] for z in [-2.75,-1.375,0,1.375,2.75]]
check('interface_25_side_probes_X4_5',all(p is not None and abs(gp(p).x-4.5)<.001 for p in face_join))
check('source_basic_unchanged',sha(SOURCE)==report['source_sha256'])
result={'stage':'P12 verified retopology before material bake','input_source_sha256':sha(SOURCE),'retopology':retopo,'base_cap_points_godot':[list(gp(p)) for p in base_points],'checks':checks,'passed':sum(c['pass'] for c in checks),'total':len(checks),'all_pass':all(c['pass'] for c in checks)}
(OUT/'p12_retopology_report.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
for c in checks:
 if not c['pass']:print('P12_RETOPO_FAIL '+json.dumps(c),flush=True)
assert result['all_pass'],'No bake or export after failed retopology/contact'

# Reuse the approved project's H10 P3 color recipes byte-identically, not its
# meshes. Explicit BOX coordinates reference fixed empties; temporary combined
# bake meshes therefore sample the same material positions as editable parts.
recipes={}
for kind,file in [('stone','RB_Stone_BaseColor_P3.png'),('bark','RB_Bark_BaseColor_P3.png')]:
 origin=PROJECT/'asset_sources/v3/root_buttress/p3/textures'/file;target=TEX/('Recipe_'+file)
 shutil.copyfile(origin,target);assert sha(origin)==sha(target);recipes[kind]={'path':str(target),'sha256':sha(target),'source':str(origin.relative_to(PROJECT))}
wood_coords=bpy.data.objects.new('P12_Bark_SourceFrame',None);scene.collection.objects.link(wood_coords);wood_coords.matrix_world=root.matrix_world.copy()
stone_coords=bpy.data.objects.new('P12_Stone_AssetFrame',None);scene.collection.objects.link(stone_coords)
def recipe(kind):
 m=bpy.data.materials.new('T03A_'+kind.title()+'_PBR');m.use_nodes=True;nodes=m.node_tree.nodes;links=m.node_tree.links
 p=next(n for n in nodes if n.type=='BSDF_PRINCIPLED');p.inputs['Roughness'].default_value=.88 if kind=='stone' else .84;p.inputs['Specular IOR Level'].default_value=.16
 coord=nodes.new('ShaderNodeTexCoord');coord.object=stone_coords if kind=='stone' else wood_coords
 scale=nodes.new('ShaderNodeVectorMath');scale.operation='SCALE';scale.inputs[3].default_value=.125 if kind=='stone' else .45;links.new(coord.outputs['Object'],scale.inputs[0])
 tex=nodes.new('ShaderNodeTexImage');tex.image=bpy.data.images.load(recipes[kind]['path'],check_existing=False);tex.image.pack();tex.projection='BOX';tex.projection_blend=.38
 links.new(scale.outputs[0],tex.inputs['Vector'])
 quiet=nodes.new('ShaderNodeMixRGB');quiet.inputs[0].default_value=.48 if kind=='stone' else .58
 quiet.inputs[2].default_value=(.17,.20,.21,1) if kind=='stone' else (.17,.12,.077,1)
 links.new(tex.outputs['Color'],quiet.inputs[1]);colour=quiet.outputs[0]
 if kind=='stone':
  # Sparse low shoulder moss, not green decoration covering the revised edge.
  noise=nodes.new('ShaderNodeTexNoise');noise.inputs['Scale'].default_value=.8;noise.inputs['Detail'].default_value=1.1;links.new(coord.outputs['Object'],noise.inputs['Vector'])
  thresh=nodes.new('ShaderNodeMath');thresh.operation='GREATER_THAN';thresh.inputs[1].default_value=.64;links.new(noise.outputs['Fac'],thresh.inputs[0])
  xyz=nodes.new('ShaderNodeSeparateXYZ');links.new(coord.outputs['Object'],xyz.inputs[0])
  low=nodes.new('ShaderNodeMath');low.operation='LESS_THAN';low.inputs[1].default_value=1.65;links.new(xyz.outputs['Z'],low.inputs[0])
  mask=nodes.new('ShaderNodeMath');mask.operation='MULTIPLY';links.new(thresh.outputs[0],mask.inputs[0]);links.new(low.outputs[0],mask.inputs[1])
  strength=nodes.new('ShaderNodeMath');strength.operation='MULTIPLY';strength.inputs[1].default_value=.4;links.new(mask.outputs[0],strength.inputs[0])
  moss=nodes.new('ShaderNodeMixRGB');links.new(strength.outputs[0],moss.inputs[0]);links.new(colour,moss.inputs[1]);moss.inputs[2].default_value=(.105,.145,.078,1);colour=moss.outputs[0]
 links.new(colour,p.inputs['Base Color'])
 bw=nodes.new('ShaderNodeRGBToBW');links.new(tex.outputs['Color'],bw.inputs[0]);bump=nodes.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.10;bump.inputs['Distance'].default_value=.025
 links.new(bw.outputs[0],bump.inputs['Height']);links.new(bump.outputs['Normal'],p.inputs['Normal']);return m
materials={k:recipe(k) for k in recipes}
for ob in parts:
 ob.data.materials.clear();ob.data.materials.append(materials['bark' if ob==root else 'stone'])
 for uv in list(ob.data.uv_layers):ob.data.uv_layers.remove(uv)
 uv=ob.data.uv_layers.new(name='RecipeUV');uv.active_render=True
 for poly in ob.data.polygons:
  for li in poly.loop_indices:
   v=ob.data.vertices[ob.data.loops[li].vertex_index].co;uv.data[li].uv=(v.x*.1,v.z*.1)
scene.render.threads_mode='FIXED';scene.render.threads=2;scene.cycles.device='CPU';scene.cycles.samples=12
path=OUT/'shore_root_t03a_p12_pbr_author.blend';bpy.ops.wm.save_as_mainfile(filepath=str(path))
result.update({'author_source':str(path),'author_sha256':sha(path),'material_recipes':recipes,'triangles_total':sum(x['triangles_after'] for x in retopo)})
(OUT/'p12_retopology_report.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print('P12_PBR_AUTHOR_READY '+json.dumps({'passed':result['passed'],'total':result['total'],'triangles':result['triangles_total']}),flush=True)
