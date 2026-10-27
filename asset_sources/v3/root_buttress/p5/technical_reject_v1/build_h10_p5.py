"""P5 source-only reconstruction: directed Bisect blocks, no ring loft.
Design coordinates are Godot Y-up; no runtime export or baking is implemented.
"""
from pathlib import Path
import bpy,bmesh,math,json,hashlib,struct,sys
from mathutils import Vector
from mathutils.bvhtree import BVHTree

HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];P3=HERE.parent/'p3';P4=HERE.parent/'p4'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
frozen={}
for manifest in [P3/'p3_manifest.json',P4/'p4_manifest.json']:
 for item in json.loads(manifest.read_text(encoding='utf-8'))['entries']:
  frozen[item['path']]=item['sha256'];assert sha(ROOT/item['path'])==item['sha256']
runtime=json.loads((P3/'p3_manifest.json').read_text(encoding='utf-8'))['runtime_p2_sha256']
assert all(sha(ROOT/f'assets/v3/root_buttress/root_buttress_h{h}.glb')==v for h,v in runtime.items())
source=P3/'root_buttress_h10_p3_export_ready.blend'
bpy.ops.wm.open_mainfile(filepath=str(source))
asset=bpy.data.objects['RootButtress'];scene=bpy.context.scene;col=bpy.data.collections['Editable_RootButtress']
sap=bpy.data.objects['SapKnot'];anchors={n:bpy.data.objects[n] for n in ['GroundOrigin','BodyPerch','HostTarget','LowerShelf']}
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
def bp(p):return Vector((p[0],-p[2],p[1]))
def gp(p):return Vector((p.x,p.z,-p.y))
def material(name,color):
 m=bpy.data.materials.new(name);m.use_nodes=True;p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED');p.inputs['Base Color'].default_value=(*color,1);p.inputs['Roughness'].default_value=.87;p.inputs['Specular IOR Level'].default_value=.18;return m
stone=material('P5_Basic_CoolStone',(.14,.17,.185));wood=material('P5_Basic_BrownWood',(.16,.11,.068));amber=material('P5_Basic_Amber',(.65,.23,.025))
sap.data.materials.clear();sap.data.materials.append(amber)
parts=[sap];groups={'RockMasses':[],'LivingRoots':[],'SapKnot':[sap]};cut_records=[]
def add_mesh(name,mesh,group,mat):
 ob=bpy.data.objects.new(name,mesh);col.objects.link(ob);ob.parent=asset;ob['semantic_group']=group;mesh.materials.append(mat);parts.append(ob);groups[group].append(ob);return ob
def uv_planar(ob):
 uv=ob.data.uv_layers.new(name='SurfaceUV');uv.active_render=True
 for f in ob.data.polygons:
  axis=max(range(3),key=lambda k:abs(f.normal[k]));axes=[k for k in range(3) if k!=axis]
  for li in f.loop_indices:
   v=ob.data.vertices[ob.data.loops[li].vertex_index].co;uv.data[li].uv=(v[axes[0]]*.12,v[axes[1]]*.12)
 return ob
def bisect(bm,name,normal,offset,remove=True):
 n=Vector(normal);point=n*(offset/n.length_squared)
 out=bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=.000001,plane_co=bp(point),plane_no=bp(n),clear_outer=remove,clear_inner=False)
 if remove:
  boundary=[e for e in bm.edges if e.is_boundary]
  if boundary:bmesh.ops.holes_fill(bm,edges=boundary,sides=0)
 bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
 cut_records.append({'block':name,'normal_godot':list(normal),'offset':offset,'clear_outer':remove,'new_cut_geometry':len(out['geom_cut'])})

# Two off-centre faults follow the same geological strike s=z-.22*x.
# Actual front-right foot has minimum s=.8998 on its R.75 disk, so the
# second fault is fully back to Y10 by s=.85; no foot patch is displaced.
PROFILE=[(-1.15,10),(-.85,9.58),(-.60,9.82),(.20,9.82),(.45,9.40),(.65,9.40),(.85,10)]
def roof(s):
 if s<=PROFILE[0][0] or s>=PROFILE[-1][0]:return 10
 for (a,y),(b,z) in zip(PROFILE,PROFILE[1:]):
  if a<=s<=b:return y+(z-y)*(s-a)/(b-a)
 return 10
def block(name,bounds,cuts,top_faults=False):
 lo,hi=bounds;bm=bmesh.new();bmesh.ops.create_cube(bm,size=2)
 for v in bm.verts:
  p=gp(v.co);v.co=bp(tuple((lo[k]+hi[k])/2+p[k]*(hi[k]-lo[k])/2 for k in range(3)))
 for n,d in cuts:bisect(bm,name,n,d)
 if top_faults:
  for s,y in PROFILE:bisect(bm,name,(-.22,0,1),s,False)
  for v in bm.verts:
   p=gp(v.co)
   if p.y>9.35:p.y=min(p.y,roof(p.z-.22*p.x));v.co=bp(p)
 # Very small edge bevels communicate cut stone without swollen tiles.
 bm.normal_update();edges=[e for e in bm.edges if e.is_manifold and e.calc_face_angle(0)>.40]
 if edges:bmesh.ops.bevel(bm,geom=edges,offset=.055,segments=1,affect='EDGES',clamp_overlap=True)
 bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));me=bpy.data.meshes.new(name+'_Mesh');bm.to_mesh(me);bm.free();me.update()
 return uv_planar(add_mesh(name,me,'RockMasses',stone))

# Seven unequal intersecting geological masses. No vertices are produced by
# joining repeated rings. Each solid starts as one block, then is clipped by
# a small number of directed planes; all cut caps remain part of the solid.
block('Rock_01_LowerKeystone',((-4.7,0,-4.5),(4.2,6.4,4.5)),[
 ((1,.11,.06),4.6),((-1,.10,.12),5.1),((.10,1,-.06),6.6),((1,0,1),7.1),((-1,0,-1),7.9)])
block('Rock_02_UpperRearBearing',((-5.3,5.15,-5.2),(4.25,10,.55)),[
 ((-1,.075,-1),9.5),((1,-.10,-.04),4.4),((.08,0,-1),5.25)],True)
block('Rock_03_UpperFrontBearing',((-4.25,6.05,-.75),(5.1,10,5.25)),[
 ((1,.055,1),8.05),((0,1,.27),11.15),((-1,-.13,.03),4.0)],True)
block('Rock_04_WideLowerShelf',((-6.30,0,1.35),(-2.70,5,6.15)),[
 ((-1,.045,1),11.8),((-.12,0,1),6.55),((1,-.12,.1),-2.15)])
block('Rock_05_RightWaistShoulder',((1.25,0,1.25),(5.75,6.95,5.6)),[
 ((1,.18,0),5.8),((.13,1,.07),7.7),((1,0,1),9.25),((0,-.07,1),5.4)])
block('Rock_06_LowRearFooting',((-5.75,0,-6.20),(2.75,3.05,-2.7)),[
 ((-1,.06,-1),10.3),((.12,1,-.08),3.5),((1,0,-1),7.9)])
block('Rock_07_ShortBackRidge',((-5.6,7.35,-5.75),(-1.5,11.55,-3.95)),[
 ((.20,1,.12),9.9),((-1,.10,-1),10.7),((1,.12,0),-.5)])
bpy.context.view_layer.update()
def tree(objects):
 vertices=[];faces=[]
 for ob in objects:
  ob.data.calc_loop_triangles();off=len(vertices);vertices.extend(ob.matrix_world@v.co for v in ob.data.vertices);faces.extend(tuple(off+i for i in t.vertices) for t in ob.data.loop_triangles)
 return BVHTree.FromPolygons(vertices,faces,all_triangles=True)
stone_tree=tree(groups['RockMasses'])
def cat(a,b,c,d,t):return .5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t)
root_records=[]
def timber(name,knots,seed,follow=None,steps=4):
 samples=[]
 for i in range(len(knots)-1):
  a,b,c,d=[Vector(knots[k]) for k in [max(0,i-1),i,i+1,min(len(knots)-1,i+2)]]
  for j in range(steps):samples.append(cat(a,b,c,d,j/steps))
 samples.append(Vector(knots[-1]))
 # Width and depth are independent: this is one flattened woody solid, not
 # three tubular strands. Projection embeds the back in the bearing wall.
 if follow:
  for p in samples:
   if .8<p.y<9.45:
    origin=(p.x,p.y,9) if follow=='front' else (9,p.y,p.z)
    ray=(0,0,-1) if follow=='front' else (-1,0,0)
    hit=stone_tree.ray_cast(bp(origin),bp(ray),20)
    if hit[0]:
     point=gp(hit[0]);weight=min(1,(9.45-p.y)/.55,(p.y-.8)/.5)
     axis=2 if follow=='front' else 0;p[axis]=p[axis]*(1-weight)+(point[axis]+p[4]*.16)*weight
  for unused in range(2):
   out=[p.copy() for p in samples]
   for i in range(1,len(samples)-1):
    for axis in [0,2]:out[i][axis]=.6*samples[i][axis]+.2*(samples[i-1][axis]+samples[i+1][axis])
   samples=out
 section=[(-1,0),(-.83,.43),(-.51,.76),(-.17,.57),(.19,.85),(.55,.63),(.84,.36),(1,0),(.68,-.42),(0,-.65),(-.68,-.42)]
 n=len(section);verts=[];arc=[0.]
 for a,b in zip(samples,samples[1:]):arc.append(arc[-1]+(Vector(a[:3])-Vector(b[:3])).length)
 for i,p in enumerate(samples):
  tangent=(Vector(samples[min(i+1,len(samples)-1)][:3])-Vector(samples[max(0,i-1)][:3])).normalized()
  toward=Vector((0,0,1)) if follow!='right' else Vector((1,0,0))
  if abs(tangent.dot(toward))>.92:toward=Vector((0,1,0))
  u=tangent.cross(toward).normalized();v=u.cross(tangent).normalized();t=i/(len(samples)-1)
  twist=.28*math.sin(t*5.4+seed)-.10;ur=u*math.cos(twist)+v*math.sin(twist);vr=-u*math.sin(twist)+v*math.cos(twist)
  for a,b in section:
   q=Vector(p[:3])+ur*(a*p[3])+vr*(b*p[4]);q.y=max(0,q.y);verts.append(tuple(q))
 faces=[tuple(reversed(range(n)))]
 for i in range(len(samples)-1):
  for j in range(n):faces.append((i*n+j,i*n+(j+1)%n,(i+1)*n+(j+1)%n,(i+1)*n+j))
 faces.append(tuple((len(samples)-1)*n+j for j in range(n)))
 me=bpy.data.meshes.new(name+'_Mesh');me.from_pydata([bp(p) for p in verts],[],faces);me.update();bm=bmesh.new();bm.from_mesh(me);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free()
 ob=add_mesh(name,me,'LivingRoots',wood);uv=me.uv_layers.new(name='SurfaceUV');uv.active_render=True
 for f in me.polygons:
  js=[me.loops[li].vertex_index%n for li in f.loop_indices];seam=0 in js and n-1 in js
  for li in f.loop_indices:
   vi=me.loops[li].vertex_index;j=vi%n;uv.data[li].uv=((n if seam and j==0 else j)/n,arc[vi//n]/4)
 root_records.append({'name':name,'cross_section':'one broad flattened solid; 3-4 shallow longitudinal facets','sections':len(samples),'vertices_per_section':n,'samples_godot':[list(p) for p in samples]})
 return samples
main=timber('Root_MainTwistedButtress',[(.0,.80,5.65,1.02,.55),(-.65,2.6,4.9,1.2,.58),(.15,4.7,4.8,1.08,.53),(-.45,6.7,4.8,.90,.47),(-.65,8.4,5.0,.72,.37),(-.22,9.65,4.6,.46,.31),(0,10.58,4.48,.28,.25)],2,'front')
base=main[0]
timber('Root_Foot_Left',[(*base[:3],.81,.43),(-1.35,.48,6.05,.75,.35),(-3.2,.08,6.40,.12,.10)],4,steps=5)
timber('Root_Foot_Right',[(*base[:3],.77,.42),(1.12,.45,6.12,.68,.31),(2.85,.06,6.50,.10,.08)],7,steps=5)
timber('Root_RightEmbeddedBrace',[(5.45,.1,-3.8,.65,.40),(5.1,2.3,-2.7,.72,.43),(4.7,4.6,-2.0,.66,.40),(4.9,6.8,-1.8,.48,.34),(4.1,8.5,-2.25,.23,.22)],9,'right')
# A short collar reaches the immutable sap surface without a floating gem.
timber('Root_SapCollar',[(-.28,10.35,4.48,.30,.20),(-.45,10.85,4.48,.20,.17),(-.40,11.30,4.48,.11,.12)],1,steps=4)
bpy.context.view_layer.update()

# Read the real p6 contact markers, not the abandoned +/-3 m planning grid.
crown_path=ROOT/'asset_sources/v3/crown/candidates/p6/crown_glb_validation_p6.json'
crown=json.loads(crown_path.read_text(encoding='utf-8'))
def find_named_mapping(value,names):
 if isinstance(value,dict):
  if all(n in value and isinstance(value[n],dict) and 'position' in value[n] for n in names):return value
  for sub in value.values():
   found=find_named_mapping(sub,names)
   if found:return found
 elif isinstance(value,list):
  for sub in value:
   found=find_named_mapping(sub,names)
   if found:return found
names=['ClawContact_FL','ClawContact_FR','ClawContact_BL','ClawContact_BR'];markers=find_named_mapping(crown,names);assert markers
feet={n:markers[n]['position'] for n in names};checks=[]
def check(n,p,d=None):checks.append({'name':n,'pass':bool(p),'detail':d})
check('frozen_sap_geometry_uv_transform_and_anchors',fixed=={o.name:digest(o) for o in [sap,*anchors.values()]})
stone_tree=tree(groups['RockMasses']);roots_tree=tree(groups['LivingRoots'])
def down(bvh,x,z,start=15):
 h=bvh.ray_cast(bp((x,start,z)),bp((0,-1,0)),25)
 return list(gp(h[0])) if h[0] else None
for name,(x,y,z) in feet.items():
 samples=[(x,z)]+[(x+r*math.cos(i*math.tau/64),z+r*math.sin(i*math.tau/64)) for r in [.25,.5,.75] for i in range(64)]
 hits=[down(stone_tree,a,b) for a,b in samples];bad=[{'xz':p,'hit':h} for p,h in zip(samples,hits) if h is None or abs(h[1]-10)>.001]
 check(name+'_radius075_y10_support',not bad,{'centre_xz':[x,z],'probes':len(samples),'failures':bad})
 hits=[down(roots_tree,a,b) for a,b in samples];bad=[h for h in hits if h and h[1]>10.001]
 check(name+'_no_new_root_obstacle',not bad,bad)
top_probes=[(x,s+.22*x) for x in [-2,-1,0,1,2] for s in [-.85,0,.50]]
tops=[down(stone_tree,x,z) for x,z in top_probes]
check('two_offcentre_faults_only_lower_central_top',all(h and 9.399<=h[1]<9.9 for h in tops),{'xz':top_probes,'hits':tops})
lower=[down(stone_tree,-3.7+dx,3.2+dz,6) for dx,dz in [(0,0),(-.25,0),(.25,0),(0,-.25),(0,.25)]]
check('lower_shelf_anchor_y5',all(h and abs(h[1]-5)<.001 for h in lower),lower)
points=[gp(o.matrix_world@v.co) for o in parts for v in o.data.vertices]
bounds={'min':[min(p[k] for p in points) for k in range(3)],'max':[max(p[k] for p in points) for k in range(3)]}
lo=[-6.610198020935059,0,-6.804511547088623];hi=[6.905734539031982,11.93212890625,6.879329681396484]
check('inside_original_xyz_bounds',all(bounds['min'][k]>=lo[k]-.0001 and bounds['max'][k]<=hi[k]+.0001 for k in range(3)),bounds)
sap_tree=tree([sap]);blocking=tree(groups['RockMasses']+groups['LivingRoots']);target=Vector((0,11,4.5))
for i,origin in enumerate([(0,11,8),(-3,12,8),(3,12,8)]):
 direction=target-Vector(origin);sh=sap_tree.ray_cast(bp(origin),bp(direction.normalized()),direction.length+1);bh=blocking.ray_cast(bp(origin),bp(direction.normalized()),direction.length+1)
 check('sap_front_los_'+str(i),sh[0] is not None and (bh[0] is None or bh[3]>sh[3]+.01),{'sap_distance':sh[3],'blocking_distance':bh[3]})
nearest=roots_tree.find_nearest(bp(target));q=gp(nearest[0])-target
check('sap_attached_to_live_root',(q.x/.57)**2+(q.y/.78)**2+(q.z/.4)**2<.93,{'closest':list(gp(nearest[0]))})
tris=0
for ob in parts:ob.data.calc_loop_triangles();tris+=len(ob.data.loop_triangles)
check('seven_directionally_cut_blocks',len(groups['RockMasses'])==7 and len(cut_records)>20,{'blocks':7,'bisect_calls':len(cut_records)})
check('all_meshes_unique_active_uv',all(len(o.data.uv_layers)==1 and o.data.uv_layers[0].active_render for o in parts))
check('triangles_under_22000',tris<22000,tris)
check('p3_p4_files_frozen',all(sha(ROOT/p)==h for p,h in frozen.items()))
check('runtime_p2_frozen',all(sha(ROOT/f'assets/v3/root_buttress/root_buttress_h{h}.glb')==v for h,v in runtime.items()))
camera=scene.camera;t=bp((0,5.3,0));camera.location=t+bp((.535645,.652817,.535645))*35;camera.rotation_euler=(t-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.type='ORTHO';camera.data.ortho_scale=26.5
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=8;scene.cycles.use_denoising=True;scene.render.threads_mode='FIXED';scene.render.threads=2;scene.render.resolution_x=1024;scene.render.resolution_y=800;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG'
blend=HERE/'root_buttress_h10_form_p5.blend';bpy.ops.wm.save_as_mainfile(filepath=str(blend))
report={'stage':'p5 source-only method reconstruction; no bake/export/game validation','method':'7 unequal continuous block solids with numerical BMesh Bisect cuts and filled caps; 2 offcentre lowered top faults; one flattened twisted front timber with shallow facets and 2 terminal feet','source_sha256':sha(blend),'input_p3_sha256':sha(source),'crown_contact_report_path':str(crown_path.relative_to(ROOT)).replace('\\','/'),'crown_contact_report_sha256':sha(crown_path),'actual_contacts_godot_relative_to_body':feet,'body_perch_translation':[0,13,0],'runtime_body_lift_note':'root confirmed identity transform and +0.025m body/real-collision lift; terrain target remains Y10','anchors_godot':{n:list(gp(o.matrix_world.translation)) for n,o in anchors.items()},'fixed_object_hashes':fixed,'triangles':tris,'editable_meshes':len(parts),'bounds_godot':bounds,'top_profile_s_z_minus_point22x':PROFILE,'bisect_operations':cut_records,'roots':root_records,'checks':checks,'passed':sum(c['pass'] for c in checks),'total':len(checks),'all_pass':all(c['pass'] for c in checks),'runtime_p2_sha256':runtime,'render':{'camera_direction_godot':[.535645,.652817,.535645],'target_godot':[0,5.3,0],'orthographic_size':26.5,'pixels':[1024,800],'engine':'Cycles CPU','threads':2,'samples':8},'official_references':['https://docs.blender.org/manual/en/latest/modeling/meshes/editing/mesh/bisect.html','https://docs.blender.org/api/current/bmesh.ops.html?highlight=bmesh'],'limits':['basic palette and gray shape only; not PBR material evaluation','discrete Blender support/LOS checks do not replace root full p6 Godot body sweep','no repeated ring loft; no whole R4.2 plateau restriction','original Sap geometry/UV frozen; basic review material overrides allowed','not final art approval']}
(HERE/'p5_geometry_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('P5_REPORT '+json.dumps({k:report[k] for k in ['triangles','editable_meshes','bounds_godot','passed','total','all_pass']}),flush=True)
for c in checks:
 if not c['pass']:print('P5_FAIL '+json.dumps(c,ensure_ascii=False),flush=True)
assert report['all_pass'],'Fix geometry, not assertions'
if '--render' in sys.argv:
 scene.render.filepath=str(HERE/'h10_p5_basic_default.png');bpy.ops.render.render(write_still=True)
 gray_rock=material('P5_Gray_Stone',(.37,.37,.37));gray_wood=material('P5_Gray_Wood',(.23,.23,.23));gray_sap=material('P5_Gray_Sap',(.48,.48,.48))
 for name,mat in [('RockMasses',gray_rock),('LivingRoots',gray_wood),('SapKnot',gray_sap)]:
  for ob in groups[name]:ob.data.materials.clear();ob.data.materials.append(mat)
 scene.render.filepath=str(HERE/'h10_p5_gray_default.png');bpy.ops.render.render(write_still=True)
assert all(sha(ROOT/p)==h for p,h in frozen.items())
print('P5_DONE_SOURCE_ONLY_NO_BAKE_OR_GLB',flush=True)
