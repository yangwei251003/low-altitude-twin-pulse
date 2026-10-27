"""Original I-B maintenance overpass. Helpers use Godot Y-up metres.
Run with Blender --background --threads 2 --python ... -- --revision 1.
All runtime materials are explicit UV/PBR images, never concept projections.
"""
import bpy,math,json,hashlib,sys
import numpy as np
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[3]
SRC=ROOT/'asset_sources/v3/overpass';OUT=ROOT/'assets/v3/overpass';EVID=ROOT/'artifacts/v3/art/overpass';TEX=OUT/'textures'
for d in [SRC,OUT,EVID,TEX]:d.mkdir(parents=True,exist_ok=True)
REV=int(sys.argv[sys.argv.index('--revision')+1]) if '--revision' in sys.argv else 1
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
scene=bpy.context.scene;scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
col=bpy.data.collections.new('Editable_Overpass');scene.collection.children.link(col)
parts=[];groups={}
def pos(p):return Vector((p[0],-p[2],p[1]))
def link(o,c=col):
 for old in list(o.users_collection):old.objects.unlink(o)
 c.objects.link(o)

def material(name,index):
 m=bpy.data.materials.new(name);m.use_nodes=True;bs=m.node_tree.nodes.get('Principled BSDF')
 n=2048 if index in [0,1] else 1024;rng=np.random.default_rng(78100+index)
 v,u=np.mgrid[0:1:complex(n),0:1:complex(n)]
 def cloud(cells):
  g=rng.random((cells+1,cells+1));x=np.minimum(u*cells,cells-.00001);y=np.minimum(v*cells,cells-.00001);ix=x.astype(int);iy=y.astype(int);fx=x-ix;fy=y-iy;fx=fx*fx*(3-2*fx);fy=fy*fy*(3-2*fy)
  return (1-fx)*(1-fy)*g[iy,ix]+fx*(1-fy)*g[iy,ix+1]+(1-fx)*fy*g[iy+1,ix]+fx*fy*g[iy+1,ix+1]
 broad=cloud(9);medium=cloud(45);grain=rng.random((n,n));height=.002*grain
 base=np.zeros((n,n,3));rough=np.ones((n,n))*.63;metal=np.zeros((n,n))
 if index==0:
  # Four original material swatches: dry work concrete, repair, damp, footings.
  lu=(u*2)%1;lv=(v*2)%1;swatch=(u>=.5).astype(int)+2*(v>=.5).astype(int)
  palette=np.array([[.54,.53,.48],[.445,.455,.415],[.35,.37,.34],[.50,.48,.43]])
  aggregate=cloud(190)
  base=palette[swatch]*(.96+.075*broad[:,:,None]+.045*(aggregate[:,:,None]-.5)+.010*(grain[:,:,None]-.5))
  edge=np.minimum.reduce([lu,1-lu,lv,1-lv]);dirt=np.clip((.038+.030*medium-edge)*15,0,.65)
  base*=1-dirt[:,:,None]*.33;rough=.80-.12*(swatch==2)+.06*(medium-.5)+.025*(aggregate-.5)
  # Wide low-contrast stains exist only on the two selected repair slabs.
  stain=(swatch==1)*(np.exp(-((lu-.33)/.32)**2-((lv-.30)/.15)**2)+.6*np.exp(-((lu-.75)/.25)**2-((lv-.79)/.22)**2))
  base*=1-stain[:,:,None]*.13;height+=.003*(aggregate-.5)
  # A few subdued irregular hairline scars, not a full-surface cloud texture.
  for cx in [.18,.72]:
   crack=np.exp(-((u-cx-.012*np.sin(v*21)-.005*np.sin(v*73))/.00055)**2)*np.clip((v-.22)*2,0,1)*.18
   base*=1-crack[:,:,None];height-=crack*.006
  tide=(swatch==3)*np.clip((.33-lv)*2.2,0,.45);base*=1-tide[:,:,None]
 elif index in [1,2]:
  colour=np.array([.10,.21,.235] if index==1 else [.285,.30,.285]);base=colour*(.95+.065*broad[:,:,None]+.012*(grain[:,:,None]-.5))
  # Steel atlas: left is a 35m girder, right is short structural metal.
  # This prevents metre-scale girder streaks shrinking to specks on piers.
  su=(u*2)%1 if index==1 else u
  edge=np.minimum.reduce([su,1-su,v,1-v]);mask=np.clip((.034+.035*medium-edge)*30,0,1)
  oxide=mask*np.clip((medium-.20)*2.4,0,.95)*(.90 if index==1 else .58)
  if index==1:
   long=u<.5
   for j,(x,width,tail) in enumerate([(-13,.20,.18),(-8.5,.14,.40),(-4.2,.26,.29),(0,.18,.10),(4.2,.24,.34),(13,.22,.17)]):
    cx=.012+.976*(x+17.5)/35
    irregular=.0009*np.sin(v*(26+j*3)+j)+.0010*(medium-.5)
    lateral=np.exp(-((su-cx-irregular)/(.976*width/35*.58))**2)
    vertical=np.clip((v-tail)/.10,0,1)*np.clip((.998-v)/.025,0,1)
    oxide+=long*lateral*vertical*(.65+.30*medium)
   # Sparse lower-edge patches; no uniform rust outline around every surface.
   for cx,width in [(.08,.06),(.31,.09),(.59,.065),(.81,.08),(.95,.035)]:
    oxide+=long*np.exp(-((su-cx)/width)**2)*np.clip((.07+.055*medium-v)*15,0,1)*.82
   oxide+=~long*np.clip((.075+.03*medium-edge)*10,0,1)*np.clip((broad-.28)*1.5,0,.55)
  oxide=np.clip(oxide,0,.96);base=base*(1-oxide[:,:,None])+np.array([.39,.145,.038])*oxide[:,:,None]
  chip=mask*np.clip((grain-.87)*5,0,.5);base=base*(1-chip[:,:,None])+np.array([.31,.33,.31])*chip[:,:,None]
  salt=mask*np.clip((medium-.66)*1.6,0,.22);base=base*(1-salt[:,:,None])+np.array([.60,.57,.46])*salt[:,:,None]
  metal[:]=.10 if index==1 else .65;metal*=1-oxide*.75;metal=metal*(1-chip)+.75*chip;rough=(.64 if index==1 else .48)+oxide*.18+.025*(medium-.5);height-=chip*.01
 else:
  stripe=((u*5+v*.6)%1)<.58;base=np.where(stripe[:,:,None],np.array([.74,.41,.026]),np.array([.022,.028,.027]));base*=.96+.045*broad[:,:,None]
  wear=np.clip((grain-.96)*12,0,.4)*np.clip((.08-np.minimum.reduce([u,1-u,v,1-v]))*10,0,1);base=base*(1-wear[:,:,None])+np.array([.21,.23,.20])*wear[:,:,None];rough[:]=.66;metal[:]=.05
 gy,gx=np.gradient(height);normal=np.dstack((-gx*9,-gy*9,np.ones_like(height)));normal/=np.linalg.norm(normal,axis=2)[:,:,None]
 maps={'BaseColor':base,'Roughness':rough,'Metallic':metal,'Normal':normal*.5+.5}
 for role,data in maps.items():
  px=np.ones((n,n,4),dtype=np.float32);px[:,:,:3]=data[:,:,None] if data.ndim==2 else data
  im=bpy.data.images.new(name+'_'+role,width=n,height=n,alpha=True)
  if role!='BaseColor':im.colorspace_settings.name='Non-Color'
  im.pixels.foreach_set(px.ravel());im.filepath_raw=str(TEX/(name+'_'+role+'.png'));im.file_format='PNG';im.save();im.filepath=bpy.path.relpath(im.filepath_raw,start=str(SRC))
  node=m.node_tree.nodes.new('ShaderNodeTexImage');node.image=im;node.extension='EXTEND'
  if role=='Normal':
   nm=m.node_tree.nodes.new('ShaderNodeNormalMap');nm.inputs['Strength'].default_value=.18;m.node_tree.links.new(node.outputs['Color'],nm.inputs['Color']);m.node_tree.links.new(nm.outputs['Normal'],bs.inputs['Normal'])
  else:m.node_tree.links.new(node.outputs['Color'],bs.inputs[{'BaseColor':'Base Color','Roughness':'Roughness','Metallic':'Metallic'}[role]])
 return m
deck=material('Overpass_WarmWorkDeck',0);teal=material('Overpass_AgedTealSteel',1);steel=material('Overpass_BareHardware',2);safety=material('Overpass_WornSafety',3)
mats=[deck,teal,steel,safety]

def uv(o,swatch=0):
 # Primitive operators add UVMap. Remove it: unbound image nodes and glTF
 # both select the render-active first set, which must be our authored UVs.
 for old in list(o.data.uv_layers):o.data.uv_layers.remove(old)
 layer=o.data.uv_layers.new(name='SurfaceUV')
 o.data.uv_layers.active_index=0;layer.active_render=True
 for f in o.data.polygons:
  axis=max(range(3),key=lambda k:abs(f.normal[k]));axes=[k for k in range(3) if k!=axis]
  cs=[o.data.vertices[o.data.loops[li].vertex_index].co for li in f.loop_indices]
  lo=[min(c[k] for c in cs) for k in axes];hi=[max(c[k] for c in cs) for k in axes]
  for li,c in zip(f.loop_indices,cs):
   a,b=[.012+.976*(c[k]-l)/(h-l or 1) for k,l,h in zip(axes,lo,hi)]
   if o.data.materials[0]==deck:a,b=(a+(swatch%2))*.5,(b+(swatch//2))*.5
   elif o.data.materials[0]==teal:
    long=o.name.startswith(('Long_edge_girder_web','Girder_top_bottom_flange'))
    a=(a+(0 if long else 1))*.5
   layer.data[li].uv=(a,b)
def register(o,name,m,swatch=0,bevel=0):
 o.name=name;link(o);o.data.materials.append(m);parts.append(o);groups.setdefault(m.name,[]).append(o);uv(o,swatch)
 if bevel:
  mod=o.modifiers.new('Machined_edge','BEVEL');mod.width=bevel;mod.segments=1;o.modifiers.new('Face_weighted_normals','WEIGHTED_NORMAL')
 return o
def box(name,at,d,m,swatch=0,bevel=.015):
 bpy.ops.mesh.primitive_cube_add(size=1,location=pos(at));o=bpy.context.object;o.dimensions=(d[0],d[2],d[1]);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);return register(o,name,m,swatch,bevel)
def cylinder(name,a,b,r,m,verts=8):
 a,b=pos(a),pos(b);d=b-a;bpy.ops.mesh.primitive_cylinder_add(vertices=verts,radius=r,depth=d.length,location=(a+b)/2);o=bpy.context.object;o.rotation_mode='QUATERNION';o.rotation_quaternion=d.to_track_quat('Z','Y');bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
 for f in o.data.polygons:f.use_smooth=len(f.vertices)==4
 return register(o,name,m)
def beam(name,a,b,width,depth,m):
 a,b=pos(a),pos(b);d=b-a;bpy.ops.mesh.primitive_cube_add(size=1,location=(a+b)/2);o=bpy.context.object;o.dimensions=(width,depth,d.length);o.rotation_mode='QUATERNION';o.rotation_quaternion=d.to_track_quat('Z','Y');bpy.ops.object.transform_apply(location=False,rotation=True,scale=True);return register(o,name,m,bevel=.012)

# Continuous top working surface and thin deep edge steel. No central support.
box('Deck_structural_underlay',(0,.15,0),(34.76,.12,5.52),teal,bevel=.01)
for z in [-3.40,3.40]:
 box('Long_edge_girder_web',(0,0,z),(35,.64,.10),teal,bevel=.012)
 for y in [-.36,.36]:box('Girder_top_bottom_flange',(0,y,z),(35,.08,.20),teal,bevel=.01)
for x in [-17.42,17.42]:box('Flush_end_cross_girder',(x,0,0),(.16,.80,6.80),teal,bevel=.012)
for x in [-13,-8.5,-4.2,0,4.2,8.5,13]:box('Deck_transverse_crossbeam',(x,-.22,0),(.18,.34,6.72),teal,bevel=.01)

def panel_rect(x0,x1,z0,z1,swatch=0,name='Work_deck_panel'):
 return box(name,((x0+x1)/2,.31,(z0+z1)/2),(x1-x0,.18,z1-z0),deck,swatch,.012)
cuts=[[-17.36,-13.5,-9.5,-5.5,-1.5,2.5,6.5,10.5,14.5,17.36],[-17.36,-15.5,-11.5,-7.5,-3.5,.5,4.5,8.5,12.5,17.36]]
for row,xs in enumerate(cuts):
 z0,z1=(-2.75,-.015) if row==0 else (.015,2.75)
 for i,(a,b) in enumerate(zip(xs,xs[1:])):
  a+=.014;b-=.014;sw=1 if (row,i) in [(0,2),(1,7)] else 0
  if (row,i) in [(0,5),(1,3)]:
   cx=(a+b)/2;cz=(z0+z1)/2;hx=.62;hz=.48
   panel_rect(a,cx-hx,z0,z1,sw);panel_rect(cx+hx,b,z0,z1,sw);panel_rect(cx-hx,cx+hx,z0,cz-hz,sw);panel_rect(cx-hx,cx+hx,cz+hz,z1,sw)
   box('Recessed_damp_inspection_cover',(cx,.335,cz),(1.22,.07,.94),deck,2,.02)
   for sx in [-1,1]:
    for sz in [-1,1]:cylinder('Inspection_cover_fastener',(cx+sx*.5,.372,cz+sz*.35),(cx+sx*.5,.39,cz+sz*.35),.032,steel,verts=6)
   box('Inspection_cover_handle_recess',(cx,.375,cz),(.34,.018,.075),steel,bevel=.006)
  else:panel_rect(a,b,z0,z1,sw)

# Two real drainage troughs with spaced bars and a visible recessed bottom.
for sign in [-1,1]:
 z=sign*3.02;box('Drain_dark_bottom',(0,.20,z),(34.72,.06,.48),teal,bevel=0)
 for side in [-1,1]:box('Drain_continuous_sidewall',(0,.285,z+side*.25),(34.72,.19,.045),steel,bevel=.006)
 for j in range(158):
  x=-17.22+j*(34.44/157);box('Drain_transverse_real_bar',(x,.36,z),(.045,.08,.46),steel,bevel=0)
 for x in [-17.25,-13.5,-9.5,-5.5,-1.5,2.5,6.5,10.5,14.5,17.25]:box('Drain_removable_panel_end',(x,.36,z),(.075,.08,.50),steel,bevel=.004)
 # Broken safety segments, not a full noisy strip along 70 metres of edge.
 for a,b in [(-17.1,-15.4),(-13.5,-12.3),(-4.8,-3.6),(3.7,4.9),(12.2,13.5),(15.4,17.1)]:box('Local_safety_edge_tab',((a+b)/2,.409,sign*2.65),(b-a,.018,.20),safety,bevel=0)
for x in [-17.23,17.23]:
 for z in [-1.85,1.85]:box('Short_end_threshold_safety',(x,.409,z),(.20,.018,1.35),safety,bevel=0)

# Precision splice plates and fasteners along the exposed blue-grey edge.
for sign in [-1,1]:
 z=sign*3.47
 for x in [-17.15,-13,-8.5,-4.2,0,4.2,8.5,13,17.15]:
  box('Girder_bolted_splice',(x,0,z),(.24,.66,.045),steel,bevel=.01)
  for dx in [-.065,.065]:
   for y in [-.22,.22]:cylinder('Girder_splice_hex',(x+dx,y,z),(x+dx,y,z+sign*.025),.035,steel,verts=6)
 # Open rails remain low and thin so the whale behind remains visible.
 for x in np.linspace(-17.15,17.15,11):
  box('Rail_mount_foot',(float(x),.44,sign*3.30),(.22,.08,.23),teal,bevel=.01)
  cylinder('Rail_slender_upright',(float(x),.48,sign*3.30),(float(x),1.64,sign*3.30),.045,steel,verts=8)
  cylinder('Rail_amber_small_cap',(float(x),1.64,sign*3.30),(float(x),1.70,sign*3.30),.05,safety,verts=8)
 for y in [.94,1.62]:cylinder('Rail_continuous_handbar',(-17.25,y,sign*3.30),(17.25,y,sign*3.30),.035,steel,verts=8)

# Exactly two slender I-section piers at +/-13; short braces local to piers.
for x in [-13,13]:
 box('Compact_footing',(x,-7.36,0),(1.86,.28,2.16),deck,3,.035)
 box('Pier_steel_baseplate',(x,-7.18,0),(1.30,.08,1.70),teal,bevel=.018)
 box('Pier_I_web',(x,-3.80,0),(.16,6.68,1.20),teal,bevel=.01)
 for z in [-.59,.59]:box('Pier_I_flange',(x,-3.80,z),(.82,6.68,.16),teal,bevel=.012)
 box('Pier_head_crossmember',(x,-.64,0),(1.12,.48,6.18),teal,bevel=.018)
 for sign in [-1,1]:
  beam('Pier_short_longitudinal_brace',(x,-2.2,0),(x+sign*2.0,-.42,0),.18,.22,teal)
  beam('Pier_short_lateral_brace',(x,-2.45,sign*.58),(x,-.82,sign*2.72),.20,.22,teal)
  box('Pier_base_guard',(x+sign*.47,-6.95,0),(.14,.40,1.04),deck,3,.012)
  for z in [-.66,.66]:
   box('Anchor_bolt_seat',(x+sign*.48,-7.08,z),(.20,.10,.22),steel,bevel=.01)
   cylinder('Foot_anchor_hex',(x+sign*.48,-7.03,z),(x+sign*.48,-6.92,z),.065,steel,verts=6)
 for y in [-5.7,-3.9,-2.1]:
  box('Pier_stiffener_clip',(x,y,0),(.83,.075,1.32),teal,bevel=.008)
  for sign in [-1,1]:
   for z in [-.46,.46]:cylinder('Pier_clip_hex',(x+sign*.40,y,z),(x+sign*.44,y,z),.036,steel,verts=6)

root=bpy.data.objects.new('MaintenanceOverpass',None);col.objects.link(root)
for o in parts:o.parent=root
markers={'DeckLanding':(0,1.4,0),'UnderpassEntry':(0,-3.5,6),'UnderpassExit':(0,-3.5,-6)}
for name,p in markers.items():o=bpy.data.objects.new(name,None);col.objects.link(o);o.parent=root;o.location=pos(p)

# Stable studio excluded from export.
studio=bpy.data.collections.new('Studio_NotExported');scene.collection.children.link(studio)
def aim(o,target):o.rotation_euler=(pos(target)-o.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.mesh.primitive_plane_add(size=200,location=pos((0,-7.54,0)));floor=bpy.context.object;link(floor,studio)
fm=bpy.data.materials.new('StudioFloor');fm.diffuse_color=(.27,.29,.29,1);floor.data.materials.append(fm)
bpy.ops.object.camera_add(location=pos((33,23,40)));camera=bpy.context.object;link(camera,studio);camera.data.type='ORTHO';camera.data.ortho_scale=43;aim(camera,(0,-2,0));scene.camera=camera
for at,power,size in [((-15,25,18),5500,18),((20,15,-10),4500,16),((-10,12,-22),4000,14),((0,4,22),2600,20)]:
 bpy.ops.object.light_add(type='AREA',location=pos(at));light=bpy.context.object;link(light,studio);light.data.energy=power;light.data.size=size;aim(light,(0,-2,0))
scene.world.use_nodes=True;bg=scene.world.node_tree.nodes.get('Background');bg.inputs['Color'].default_value=(.35,.38,.40,1);bg.inputs['Strength'].default_value=.70
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=20;scene.cycles.use_denoising=True
scene.render.threads_mode='FIXED';scene.render.threads=2;scene.render.resolution_x=1536;scene.render.resolution_y=1000;scene.render.resolution_percentage=100;scene.view_settings.view_transform='AgX'
bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'maintenance_overpass.blend'))

# Disposable evaluated copies, one mesh per material; editable originals stay saved.
deps=bpy.context.evaluated_depsgraph_get();exp=bpy.data.collections.new('Export_Disposable');scene.collection.children.link(exp)
export_root=bpy.data.objects.new('Export_MaintenanceOverpass',None);exp.objects.link(export_root);exports=[export_root];counts=[];allpoints=[]
names={deck.name:'DeckPanels',teal.name:'SteelStructure',steel.name:'RailingsHardware',safety.name:'SafetyMarkings'}
for matname,objects in groups.items():
 copies=[]
 for p in objects:
  c=p.copy();c.data=bpy.data.meshes.new_from_object(p.evaluated_get(deps),preserve_all_data_layers=True,depsgraph=deps);c.modifiers.clear();c.parent=None;exp.objects.link(c);c.matrix_world=p.matrix_world.copy();copies.append(c)
 bpy.ops.object.select_all(action='DESELECT')
 for c in copies:c.select_set(True)
 bpy.context.view_layer.objects.active=copies[0];bpy.ops.object.join();o=bpy.context.object;o.name=names[matname]
 bpy.ops.object.transform_apply(location=False,rotation=True,scale=True);scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR');o.parent=export_root
 o.data.calc_loop_triangles();allpoints.extend(o.matrix_world@v.co for v in o.data.vertices);counts.append({'node':o.name,'triangles':len(o.data.loop_triangles),'material':matname,'source_parts':[p.name for p in objects]});exports.append(o)
for name,p in markers.items():
 source=bpy.data.objects[name];source.name='Source_'+name;e=bpy.data.objects.new(name,None);exp.objects.link(e);e.parent=export_root;e.location=pos(p);exports.append(e)
root.name='Source_MaintenanceOverpass';export_root.name='MaintenanceOverpass'
total=sum(r['triangles'] for r in counts);assert 12000<=total<=22000,f'Triangle budget failure: {total}'
bpy.ops.object.select_all(action='DESELECT')
for o in exports:o.select_set(True)
bpy.context.view_layer.objects.active=export_root
glb=OUT/'maintenance_overpass.glb';bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,export_yup=True,export_apply=True,export_materials='EXPORT',export_cameras=False,export_lights=False,export_animations=False,export_extras=True)
ps=[(p.x,p.z,-p.y) for p in allpoints];bounds={'min':[min(p[k] for p in ps) for k in range(3)],'max':[max(p[k] for p in ps) for k in range(3)]}
report={'revision':REV,'glb_sha256':hashlib.sha256(glb.read_bytes()).hexdigest(),'bytes':glb.stat().st_size,'triangles':total,'materials':4,'mesh_count':4,'editable_parts':len(parts),'bounds_godot':bounds,'markers':markers,'groups':counts,'design':{'deck_bounds':{'min':[-17.5,-.4,-3.5],'max':[17.5,.4,3.5]},'piers_x':[-13,13],'support_bottom_y':-7.5,'max_rail_y':1.7,'clear_central_underpass':'X [-10,10], Z [-6,6], Y [-6.8,-1.2] sampled after reimport'},'renderer':'Blender Cycles CPU2; not game screenshot','scope':'single static asset; root owns Godot collision and world integration'}
(EVID/f'build_v{REV}.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
(EVID/'original_materials.json').write_text(json.dumps({'origin':'Original four-material UV/PBR; edge oxidation and deck swatches, no projected reference images','files':[{'path':str(p.relative_to(ROOT)).replace('\\','/'),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(TEX.glob('*.png'))]},ensure_ascii=False,indent=2),encoding='utf-8')
exp.hide_render=True
print('OVERPASS_BUILD '+json.dumps({k:v for k,v in report.items() if k!='groups'}),flush=True)
if '--build-only' not in sys.argv:
 views=[('front',(33,23,40),(0,-2,0)),('back',(-32,20,-40),(0,-2,0)),('under',(0,-2.5,36),(0,-2.5,0))]
 if '--quick-preview' in sys.argv:scene.cycles.samples=8;views=views[:1]
 for view,at,target in views:
  camera.location=pos(at);aim(camera,target);scene.render.filepath=str(EVID/f'overpass_{view}_v{REV}.png');bpy.ops.render.render(write_still=True)
 print('OVERPASS_PREVIEW_COMPLETE' if '--quick-preview' in sys.argv else 'OVERPASS_THREE_VIEWS_COMPLETE',flush=True)
