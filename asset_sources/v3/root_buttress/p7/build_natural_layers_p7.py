"""P7 natural-layer method trial. Four rigid source pieces, no column warp."""
import bpy,bmesh,math,json,hashlib,struct,sys
from pathlib import Path
from mathutils import Vector,Matrix
from mathutils.bvhtree import BVHTree
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];VENDOR=HERE.parent/'p6/vendor';P3=HERE.parent/'p3'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
frozen={}
for name in ['p3','p4','p5','p6']:
 for p in (HERE.parent/name).rglob('*'):
  if p.is_file() and '__pycache__' not in p.parts and p.suffix!='.blend1':frozen[str(p.relative_to(ROOT))]=sha(p)
runtime={h:sha(ROOT/f'assets/v3/root_buttress/root_buttress_h{h}.glb') for h in [10,12,17,3]}
bpy.ops.wm.open_mainfile(filepath=str(P3/'root_buttress_h10_p3_export_ready.blend'))
scene=bpy.context.scene;asset=bpy.data.objects['RootButtress'];col=bpy.data.collections['Editable_RootButtress'];sap=bpy.data.objects['SapKnot']
anchors={n:bpy.data.objects[n] for n in ['GroundOrigin','BodyPerch','HostTarget','LowerShelf']}
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
for ob in list(asset.children_recursive):
 if ob.type=='MESH' and ob!=sap:bpy.data.objects.remove(ob,do_unlink=True)
sap.hide_render=True
def bp(p):return Vector((p[0],-p[2],p[1]))
def gp(p):return Vector((p.x,p.z,-p.y))
def material(name,color):
 m=bpy.data.materials.new(name);m.use_nodes=True;p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED');p.inputs['Base Color'].default_value=(*color,1);p.inputs['Roughness'].default_value=.86;p.inputs['Specular IOR Level'].default_value=.2;return m
stone=material('P7_Stone_Form_Only',(.22,.245,.255))
gltf=json.loads((VENDOR/'rock_moss_set_01_1k.gltf').read_text());binary=(VENDOR/'rock_moss_set_01.bin').read_bytes()
def accessor(index):
 a=gltf['accessors'][index];v=gltf['bufferViews'][a['bufferView']];typ={5126:'f',5125:'I',5123:'H',5121:'B'}[a['componentType']];width={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']];st=struct.Struct('<'+typ*width);stride=v.get('byteStride',st.size);off=v.get('byteOffset',0)+a.get('byteOffset',0)
 return [st.unpack_from(binary,off+i*stride) for i in range(a['count'])]
def tree(ob):
 ob.data.calc_loop_triangles();return BVHTree.FromPolygons([ob.matrix_world@v.co for v in ob.data.vertices],[tuple(t.vertices) for t in ob.data.loop_triangles],all_triangles=True)
source_records=[];parts=[];archive=bpy.data.collections.new('P7_RigidNaturalPieces_BeforeCuts');scene.collection.children.link(archive);archive.hide_viewport=True;archive.hide_render=True
def make_rock(index,name,scale,centre,yaw=0,roll=0,ground=False):
 prim=gltf['meshes'][index]['primitives'][0];raw=accessor(prim['attributes']['POSITION']);idx=[i[0] for i in accessor(prim['indices'])];lo=[min(p[k] for p in raw) for k in range(3)];hi=[max(p[k] for p in raw) for k in range(3)]
 rot=Matrix.Rotation(yaw,3,'Y')@Matrix.Rotation(roll,3,'Z')
 verts=[rot@Vector([(p[k]-(lo[k]+hi[k])/2)*scale for k in range(3)]) for p in raw]
 shift=Vector(centre)
 if ground:shift.y=-min(p.y for p in verts)
 verts=[bp(p+shift) for p in verts]
 me=bpy.data.meshes.new(name+'_Mesh');me.from_pydata(verts,[],[tuple(idx[i:i+3]) for i in range(0,len(idx),3)]);me.update();bm=bmesh.new();bm.from_mesh(me);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.00005);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free()
 ob=bpy.data.objects.new(name,me);col.objects.link(ob);ob.parent=asset;me.materials.append(stone);ob['semantic_group']='RockMasses';parts.append(ob)
 for p in me.polygons:p.use_smooth=True
 cp=ob.copy();cp.data=ob.data.copy();cp.parent=None;cp.hide_render=True;cp.hide_viewport=True;archive.objects.link(cp);cp.name=name+'_RigidBeforeCuts'
 source_records.append({'object':name,'source_mesh':gltf['nodes'][index]['name'],'source_triangles':len(idx)//3,'axis_scale':[scale]*3,'axis_scale_ratio':1.0,'translation_godot':list(shift),'yaw_radians':yaw,'roll_radians':roll,'method':'rigid rotation and uniform scale; source topology only, no photo maps'})
 return ob
def clip_top(ob,height):
 bm=bmesh.new();bm.from_mesh(ob.data);r=bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=.000001,plane_co=bp((0,height,0)),plane_no=bp((0,1,0)),clear_outer=True,clear_inner=False)
 edges=[e for e in r['geom_cut'] if isinstance(e,bmesh.types.BMEdge) and e.is_boundary]
 fill=bmesh.ops.holes_fill(bm,edges=edges,sides=0)
 for f in fill.get('faces',[]):f.smooth=False
 bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(ob.data);bm.free();ob.data.update()
 ob['horizontal_cut_godot_y']=height
 # Mesh normals are smooth on the original irregular rock, flat only at the cut.
 for f in ob.data.polygons:
  if abs(f.center.z-height)<.0001 and abs(f.normal.z)>.999:f.use_smooth=False

# Paper calculation selected Rock03's existing section; no vertices are lifted.
span3_y=1.0996944606304169;cut3_y=-.05*span3_y
upper=make_rock(2,'UpperNaturalLayer',5.5,(.5,10-cut3_y*5.5,-.3))
clip_top(upper,10)
base=make_rock(3,'FoundationNaturalRock',4.8,(.55,0,-.3),yaw=-.12,roll=.06,ground=True)
shelf=make_rock(0,'LeftNaturalShelf',2.0,(-3.7,5-(.55-.5)*1.4726980924606323*2,3.1),yaw=-.06)
clip_top(shelf,5)
ridge=make_rock(0,'RearShortNaturalRidge',1.0,(-2.1,10.5,-5.2),yaw=math.pi/2)

# One local wedge subtraction opens the mid shelf. It does not sculpt the cap
# or main silhouette and cannot create the four foot support surfaces.
xz=[(-9,1.3),(-3.9,1.3),(-1.8,7.8),(-9,7.8)]
verts=[bp((x,y,z)) for y in [4.92,12] for x,z in xz]
faces=[(3,2,1,0),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]
me=bpy.data.meshes.new('ShelfAccessWedge');me.from_pydata(verts,[],faces);me.update();cutter=bpy.data.objects.new('TemporaryShelfAccessWedge',me);col.objects.link(cutter)
bpy.context.view_layer.objects.active=base;mod=base.modifiers.new('Single left shelf access cut','BOOLEAN');mod.operation='DIFFERENCE';mod.solver='EXACT';mod.object=cutter;bpy.ops.object.modifier_apply(modifier=mod.name);bpy.data.objects.remove(cutter,do_unlink=True)

# Provisional planar UV only for editability; no texture baking is performed.
for ob in parts:
 uv=ob.data.uv_layers.new(name='ProvisionalUV');uv.active_render=True
 for f in ob.data.polygons:
  axis=max(range(3),key=lambda k:abs(f.normal[k]));axes=[k for k in range(3) if k!=axis]
  for li in f.loop_indices:
   v=ob.data.vertices[ob.data.loops[li].vertex_index].co;uv.data[li].uv=(v[axes[0]]*.12,v[axes[1]]*.12)
bpy.context.view_layer.update();trees={o.name:tree(o) for o in parts}
def down(x,z,start=15,only=None):
 hits=[]
 for name,t in trees.items():
  if only and name!=only:continue
  h=t.ray_cast(bp((x,start,z)),bp((0,-1,0)),30)
  if h[0]:hits.append((h[3],list(gp(h[0])),name))
 return min(hits) if hits else None
FEET=[(-2.54,2.17),(2.51,2.22),(-2.28,-2.5),(2.31,-2.48)]
checks=[]
def check(n,p,d=None):checks.append({'name':n,'pass':bool(p),'detail':d})
check('source_block_count_at_most_five',len(parts)<=5,len(parts))
check('all_source_axis_scale_ratios_at_most_1_25',all(r['axis_scale_ratio']<=1.25 for r in source_records),source_records)
check('fixed_sap_geometry_uv_transform_and_four_anchors',fixed=={o.name:digest(o) for o in [sap,*anchors.values()]})
for i,(x,z) in enumerate(FEET):
 probes=[(x,z)]+[(x+r*math.cos(a*math.tau/64),z+r*math.sin(a*math.tau/64)) for r in [.25,.5,.75] for a in range(64)]
 hits=[down(a,b) for a,b in probes];one=[down(a,b,only=upper.name) for a,b in probes]
 bad=[{'xz':p,'all':h,'upper_only':u} for p,h,u in zip(probes,hits,one) if h is None or u is None or abs(h[1][1]-10)>.001 or abs(u[1][1]-10)>.001]
 check('actual_foot_'+str(i)+'_R075_Y10_same_upper_rock',not bad,{'probes':len(probes),'failures':bad})
lower=[down(-3.7+dx,3.2+dz,6) for dx,dz in [(0,0),(-.25,0),(.25,0),(0,-.25),(0,.25)]]
check('lower_shelf_y5',all(h and abs(h[1][1]-5)<.001 for h in lower),lower)
points=[gp(o.matrix_world@v.co) for o in parts for v in o.data.vertices];bounds={'min':[min(p[k] for p in points) for k in range(3)],'max':[max(p[k] for p in points) for k in range(3)]}
lo=[-6.610198020935059,0,-6.804511547088623];hi=[6.905734539031982,11.93212890625,6.879329681396484]
check('within_original_bounds',all(bounds['min'][k]>=lo[k]-.0001 and bounds['max'][k]<=hi[k]+.0001 for k in range(3)),bounds)
target=Vector((0,11,4.5));sap_tree=tree(sap)
for i,origin in enumerate([(0,11,8),(-3,12,8),(3,12,8)]):
 d=target-Vector(origin);sh=sap_tree.ray_cast(bp(origin),bp(d.normalized()),d.length+1);rock=[]
 for name,t in trees.items():
  hit=t.ray_cast(bp(origin),bp(d.normalized()),d.length+1)
  if hit[0]:rock.append((hit[3],name))
 check('sap_los_'+str(i),sh[0] is not None and (not rock or min(rock)[0]>sh[3]+.01),{'sap_distance':sh[3],'rock_hits':rock})
for a,b in [(upper,base),(shelf,base),(ridge,upper)]:
 count=len(trees[a.name].overlap(trees[b.name]));check('real_intersection_'+a.name+'_'+b.name,count>0,{'intersecting_triangle_pairs':count})
check('p3_p4_p5_p6_frozen',all(sha(ROOT/p)==v for p,v in frozen.items()))
check('runtime_p2_frozen',all(sha(ROOT/f'assets/v3/root_buttress/root_buttress_h{h}.glb')==v for h,v in runtime.items()))
geometry={};tris=0
for o in parts:
 o.data.calc_loop_triangles();bm=bmesh.new();bm.from_mesh(o.data);n=sum(not e.is_manifold for e in bm.edges);bm.free();geometry[o.name]={'triangles':len(o.data.loop_triangles),'vertices':len(o.data.vertices),'nonmanifold_edges':n};tris+=len(o.data.loop_triangles)
camera=scene.camera;t=bp((0,5.3,0));camera.location=t+bp((.535645,.652817,.535645))*35;camera.rotation_euler=(t-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.type='ORTHO';camera.data.ortho_scale=26.5
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=8;scene.cycles.use_denoising=True;scene.render.threads_mode='FIXED';scene.render.threads=2;scene.render.resolution_x=1024;scene.render.resolution_y=800;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG'
blend=HERE/'root_buttress_h10_natural_layers_p7.blend';bpy.ops.wm.save_as_mainfile(filepath=str(blend))
report={'stage':'source-only natural layer method trial, no roots/PBR/GLB','source_sha256':sha(blend),'source_records':source_records,'triangles':tris,'geometry':geometry,'bounds_godot':bounds,'anchors_godot':{n:list(gp(o.matrix_world.translation)) for n,o in anchors.items()},'fixed_hashes':fixed,'checks':checks,'passed':sum(c['pass'] for c in checks),'total':len(checks),'all_pass':all(c['pass'] for c in checks),'runtime_p2_sha256':runtime,'render':{'camera_direction_godot':[.535645,.652817,.535645],'target_godot':[0,5.3,0],'orthographic_size':26.5,'pixels':[1024,800],'engine':'Cycles CPU','threads':2,'samples':8},'limits':['no aesthetic acceptance implied by geometry checks','no final root system yet; Sap hidden for stone-only study but unchanged','provisional planar UV only, no baked or photo textures','four source pieces retained and may intersect internally; no runtime collision/export','actual full-Crown sweep and game-camera evidence not performed']}
(HERE/'p7_geometry_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('P7_REPORT '+json.dumps({k:report[k] for k in ['triangles','bounds_godot','passed','total','all_pass']}),flush=True)
for c in checks:
 if not c['pass']:print('P7_FAIL '+json.dumps(c,ensure_ascii=False),flush=True)
assert report['all_pass'],'Repair source placement/cuts, do not weaken checks'
if '--render' in sys.argv:
 scene.render.filepath=str(HERE/'h10_p7_natural_layers_default.png');bpy.ops.render.render(write_still=True)
assert all(sha(ROOT/p)==v for p,v in frozen.items())
print('P7_DONE_SOURCE_ONLY_NO_EXPORT',flush=True)
