"""Natural CC0 rock forms as editable sculpt base; source only, no export."""
import bpy,bmesh,math,json,hashlib,struct,sys
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];VENDOR=HERE/'vendor';P3=HERE.parent/'p3'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
frozen={}
for name in ['p3','p4','p5']:
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
sap.hide_render=True # stone-only study; geometry/UV remain in the source.
def bp(p):return Vector((p[0],-p[2],p[1]))
def gp(p):return Vector((p.x,p.z,-p.y))
def mat(name,c):
 m=bpy.data.materials.new(name);m.use_nodes=True;p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED');p.inputs['Base Color'].default_value=(*c,1);p.inputs['Roughness'].default_value=.88;p.inputs['Specular IOR Level'].default_value=.18;return m
stone=mat('P6_NaturalStone_Basic',(.145,.17,.185))
gltf=json.loads((VENDOR/'rock_moss_set_01_1k.gltf').read_text());binary=(VENDOR/'rock_moss_set_01.bin').read_bytes()
def accessor(index):
 a=gltf['accessors'][index];v=gltf['bufferViews'][a['bufferView']];typ={5126:'f',5125:'I',5123:'H',5121:'B'}[a['componentType']];width={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']];st=struct.Struct('<'+typ*width);stride=v.get('byteStride',st.size);off=v.get('byteOffset',0)+a.get('byteOffset',0)
 return [st.unpack_from(binary,off+i*stride) for i in range(a['count'])]
def mesh_tree(ob):
 ob.data.calc_loop_triangles();return BVHTree.FromPolygons([v.co for v in ob.data.vertices],[tuple(t.vertices) for t in ob.data.loop_triangles],all_triangles=True)
source_records=[];parts=[]
def make_rock(index,name,dimensions,centre,yaw=0):
 prim=gltf['meshes'][index]['primitives'][0];raw=accessor(prim['attributes']['POSITION']);idx=[i[0] for i in accessor(prim['indices'])];lo=[min(p[k] for p in raw) for k in range(3)];hi=[max(p[k] for p in raw) for k in range(3)];verts=[]
 for p in raw:
  q=[((p[k]-(lo[k]+hi[k])/2)/(hi[k]-lo[k]))*dimensions[k] for k in range(3)]
  x,z=q[0],q[2];q[0]=x*math.cos(yaw)-z*math.sin(yaw);q[2]=x*math.sin(yaw)+z*math.cos(yaw);verts.append(bp(tuple(q[k]+centre[k] for k in range(3))))
 me=bpy.data.meshes.new(name+'_Mesh');me.from_pydata(verts,[],[tuple(idx[i:i+3]) for i in range(0,len(idx),3)]);me.update();bm=bmesh.new();bm.from_mesh(me);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.00005);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free()
 ob=bpy.data.objects.new(name,me);col.objects.link(ob);ob.parent=asset;me.materials.append(stone);ob['semantic_group']='RockMasses';parts.append(ob)
 source_records.append({'object':name,'source_mesh':gltf['nodes'][index]['name'],'source_triangles':len(idx)//3,'dimensions_godot':dimensions,'centre_godot':centre,'yaw_rad':yaw,'use':'geometry only; no scan photographs or material maps'})
 return ob
main=make_rock(3,'Natural_MainRock04',(10.4,11.0,9.4),(0,5.5,-.1),-.10)
shelf=make_rock(0,'Natural_LowerShelfRock01',(4.2,5.7,5.5),(-4.15,2.85,3.6),-.08)
ridge=make_rock(2,'Natural_ShortRidgeRock03',(3.5,2.4,2.3),(-2.8,10.0,-4.7),.18)
FEET=[(-2.54,2.17),(2.51,2.22),(-2.28,-2.50),(2.31,-2.48)]
def smooth(x):x=max(0,min(1,x));return x*x*(3-2*x)
def foot_distance(x,z):return min(math.hypot(x-a,z-b) for a,b in FEET)
def top_goal(x,z):
 # Broad asymmetric shallow erosion, not two parallel machined channels.
 a=z+.19*x+.42+.22*math.sin(x*.73);b=z-.13*x-1.05-.25*math.cos(x*.56)
 natural=9.79+.11*math.sin(x*.7+z*.25)+.07*math.cos(z*.8-x*.3)-.28*math.exp(-(a/.65)**2)-.14*math.exp(-(b/.8)**2)
 natural=max(9.4,min(9.95,natural));blend=1-smooth((foot_distance(x,z)-.99)/.42)
 return natural*(1-blend)+10*blend
def deform_top(ob,mode):
 oldtree=mesh_tree(ob);moves=[]
 for v in ob.data.vertices:
  p=gp(v.co);hit=oldtree.ray_cast(bp((p.x,20,p.z)),bp((0,-1,0)),30)
  if not hit[0]:continue
  height=gp(hit[0]).y
  if mode=='main':
   inside=math.sqrt((p.x/3.55)**2+((p.z+.1)/3.4)**2);influence=max(1-smooth((inside-1)/.43),1-smooth((foot_distance(p.x,p.z)-1.15)/1.1));floor=2.65
   if p.y>floor and height>floor+.2:
    goal=top_goal(p.x,p.z);warped=floor+(p.y-floor)*(goal-floor)/(height-floor);new=p.y+(warped-p.y)*influence;p.y=new
  else:
   distance=math.hypot(p.x+3.7,p.z-3.2);influence=1-smooth((distance-1.0)/1.5);floor=.8
   if p.y>floor and height>floor+.2:
    goal=5-.25*smooth((distance-.65)/1.7);new=floor+(p.y-floor)*(goal-floor)/(height-floor);p.y=p.y+(new-p.y)*influence
  p.y=max(0,p.y);v.co=bp(p)
 ob.data.update()
deform_top(main,'main');deform_top(shelf,'shelf')

# Open the real mid-height shelf to its front/left approach. This is one
# local subtractive trim of natural geometry, not the base construction.
bpy.ops.mesh.primitive_cube_add(size=1,location=bp((-4.7,6.05,4.7)))
cutter=bpy.context.object;cutter.name='TemporaryShelfAccessTrim';cutter.dimensions=(5.1,5.6,2.10);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
for ob in [main]:
 bpy.context.view_layer.objects.active=ob;mod=ob.modifiers.new('Local shelf access trim','BOOLEAN');mod.operation='DIFFERENCE';mod.solver='EXACT';mod.object=cutter;bpy.ops.object.modifier_apply(modifier=mod.name)
bpy.data.objects.remove(cutter,do_unlink=True)

# Preserve separate natural source pieces in an inactive collection before
# unifying them into a continuous sculpt base. No original vendor file changes.
archive=bpy.data.collections.new('P6_EditableNaturalPieces');scene.collection.children.link(archive)
for ob in parts:
 cp=ob.copy();cp.data=ob.data.copy();archive.objects.link(cp);cp.name=ob.name+'_BeforeUnion';cp.hide_render=True;cp.hide_viewport=True;cp.parent=None
archive.hide_render=True;archive.hide_viewport=True
bpy.ops.object.select_all(action='DESELECT')
for ob in parts:ob.select_set(True)
bpy.context.view_layer.objects.active=main;bpy.ops.object.join();main.name='RockMasses';main['semantic_group']='RockMasses'
main.data.remesh_voxel_size=.12;main.data.remesh_voxel_adaptivity=0;bpy.ops.object.voxel_remesh()
# Very light smoothing suppresses scanner micro-pebbles, not major silhouette.
mod=main.modifiers.new('Sculpt base relaxation','SMOOTH');mod.factor=.18;mod.iterations=2;bpy.ops.object.modifier_apply(modifier=mod.name)
for v in main.data.vertices:
 p=gp(v.co)
 if foot_distance(p.x,p.z)<.99 and p.y>9.25:p.y=10
 if math.hypot(p.x+3.7,p.z-3.2)<.75 and 4.45<p.y<5.65:p.y=5
 p.y=max(0,p.y);v.co=bp(p)
main.data.update();main.data.materials.clear();main.data.materials.append(stone)
for f in main.data.polygons:f.use_smooth=True
uv=main.data.uv_layers.new(name='SurfaceUV');uv.active_render=True
for f in main.data.polygons:
 axis=max(range(3),key=lambda k:abs(f.normal[k]));axes=[k for k in range(3) if k!=axis]
 for li in f.loop_indices:
  v=main.data.vertices[main.data.loops[li].vertex_index].co;uv.data[li].uv=(v[axes[0]]*.12,v[axes[1]]*.12)
bpy.context.view_layer.update();bvh=mesh_tree(main)
def down(x,z,start=15):
 h=bvh.ray_cast(bp((x,start,z)),bp((0,-1,0)),25);return list(gp(h[0])) if h[0] else None
checks=[]
def check(n,p,d=None):checks.append({'name':n,'pass':bool(p),'detail':d})
check('fixed_sap_geometry_uv_transform_and_anchors',fixed=={o.name:digest(o) for o in [sap,*anchors.values()]})
for i,(x,z) in enumerate(FEET):
 probes=[(x,z)]+[(x+r*math.cos(a*math.tau/64),z+r*math.sin(a*math.tau/64)) for r in [.25,.5,.75] for a in range(64)];hits=[down(a,b) for a,b in probes];bad=[{'xz':p,'hit':h} for p,h in zip(probes,hits) if h is None or abs(h[1]-10)>.001]
 check('actual_foot_'+str(i)+'_R075_Y10',not bad,{'probes':len(probes),'failures':bad})
lower=[down(-3.7+dx,3.2+dz,6) for dx,dz in [(0,0),(-.25,0),(.25,0),(0,-.25),(0,.25)]]
check('lower_shelf_y5',all(h and abs(h[1]-5)<.001 for h in lower),lower)
points=[gp(v.co) for v in main.data.vertices];bounds={'min':[min(p[k] for p in points) for k in range(3)],'max':[max(p[k] for p in points) for k in range(3)]}
lo=[-6.610198020935059,0,-6.804511547088623];hi=[6.905734539031982,11.93212890625,6.879329681396484]
check('within_original_bounds',all(bounds['min'][k]>=lo[k]-.0001 and bounds['max'][k]<=hi[k]+.0001 for k in range(3)),bounds)
target=Vector((0,11,4.5));sap_tree=mesh_tree(sap)
for i,origin in enumerate([(0,11,8),(-3,12,8),(3,12,8)]):
 d=target-Vector(origin);sh=sap_tree.ray_cast(bp(origin),bp(d.normalized()),d.length+1);bh=bvh.ray_cast(bp(origin),bp(d.normalized()),d.length+1)
 check('sap_los_'+str(i),sh[0] is not None and (bh[0] is None or bh[3]>sh[3]+.01),{'sap_distance':sh[3],'rock_distance':bh[3]})
check('p3_p4_p5_frozen',all(sha(ROOT/p)==v for p,v in frozen.items()))
check('runtime_p2_frozen',all(sha(ROOT/f'assets/v3/root_buttress/root_buttress_h{h}.glb')==v for h,v in runtime.items()))
main.data.calc_loop_triangles();tris=len(main.data.loop_triangles)
camera=scene.camera;t=bp((0,5.3,0));camera.location=t+bp((.535645,.652817,.535645))*35;camera.rotation_euler=(t-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.type='ORTHO';camera.data.ortho_scale=26.5
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=8;scene.cycles.use_denoising=True;scene.render.threads_mode='FIXED';scene.render.threads=2;scene.render.resolution_x=1024;scene.render.resolution_y=800;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG'
blend=HERE/'root_buttress_h10_natural_p6.blend';bpy.ops.wm.save_as_mainfile(filepath=str(blend))
report={'stage':'natural-source H10 stone-only form experiment; no final roots, textures, baking or GLB','source_sha256':sha(blend),'sources':source_records,'vendor_provenance':json.loads((VENDOR/'provenance.json').read_text()),'scan_piece_archive_collection':'P6_EditableNaturalPieces (hidden source pieces, not runtime parts)','sculpt_process':['read natural source topology without photographic materials','continuous local top deformation to actual foot disks, asymmetric shallow relief','one local shelf access subtraction','voxel union at 0.12m; two light relaxation iterations','reflatten actual R0.75 support with .99m mesh margin'],'triangles':tris,'vertices':len(main.data.vertices),'bounds_godot':bounds,'anchors_godot':{n:list(gp(o.matrix_world.translation)) for n,o in anchors.items()},'fixed_hashes':fixed,'checks':checks,'passed':sum(c['pass'] for c in checks),'total':len(checks),'all_pass':all(c['pass'] for c in checks),'runtime_p2_sha256':runtime,'render':{'camera_direction_godot':[.535645,.652817,.535645],'target_godot':[0,5.3,0],'orthographic_size':26.5,'pixels':[1024,800],'engine':'Cycles CPU','threads':2,'samples':8},'limits':['stone-only source experiment, not final world/asset','SapKnot retained with unchanged geometry/UV but hidden in stone-only render','natural root source selected separately; not yet incorporated','UV is provisional planar editing UV, not final PBR unwrap','no actual Godot full-body traversal evidence','no external photos used as hand-painted texture','natural silhouette must still be reviewed against F-B reference']}
(HERE/'p6_geometry_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('P6_REPORT '+json.dumps({k:report[k] for k in ['triangles','vertices','bounds_godot','passed','total','all_pass']}),flush=True)
for c in checks:
 if not c['pass']:print('P6_FAIL '+json.dumps(c,ensure_ascii=False),flush=True)
assert report['all_pass'],'Repair support/geometry, do not weaken checks'
if '--render' in sys.argv:
 scene.render.filepath=str(HERE/'h10_p6_natural_stone_default.png');bpy.ops.render.render(write_still=True)
assert all(sha(ROOT/p)==v for p,v in frozen.items())
print('P6_DONE_STONE_ONLY_NO_RUNTIME_EXPORT',flush=True)
