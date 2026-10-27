"""Editable original industrial modules; Blender 5.2 -> explicit Godot GLB."""
import bpy, math, json
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/models/worldui'; SOURCE=ROOT/'assets/source/worldui'
OUT.mkdir(parents=True,exist_ok=True);SOURCE.mkdir(parents=True,exist_ok=True)
def xyz(p):return (p[0],-p[2],p[1])
def mat(name,color,metal=0):
 m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True
 nodes=m.node_tree.nodes;p=next((n for n in nodes if n.type=='BSDF_PRINCIPLED'),None)
 if p is None:
  p=nodes.new('ShaderNodeBsdfPrincipled');out=nodes.new('ShaderNodeOutputMaterial');m.node_tree.links.new(p.outputs['BSDF'],out.inputs['Surface'])
 p.inputs['Base Color'].default_value=(*color,1);p.inputs['Roughness'].default_value=.72;p.inputs['Metallic'].default_value=metal
 return m
M={k:mat(k,c,.28 if k in ['steel','glass'] else .08) for k,c in {'ivory':(.29,.32,.28),'steel':(.045,.07,.075),'teal':(.035,.13,.14),'glass':(.06,.15,.19),'ochre':(.30,.18,.045),'concrete':(.23,.26,.24),'stone':(.10,.135,.12),'solar':(.035,.075,.13),'rust':(.30,.12,.065),'light':(.70,.53,.23),'green':(.16,.25,.12)}.items()}
# Broad oxide and repair contrasts use the same .72 roughness and meter scale.
# Weathering is geometry in the editable blend, not a texture/noise dependency.
M.update({k:mat(k,c,.08) for k,c in {'oxide':(.13,.055,.028),'patch':(.17,.21,.19),'dust':(.25,.22,.16)}.items()})
WEAR={}
WEAR_OUTLINES=[ [(-.5,-.34),(-.31,-.5),(.28,-.46),(.5,-.12),(.39,.31),(.12,.5),(-.34,.38),(-.46,.08)], [(-.5,-.43),(-.12,-.5),(.43,-.32),(.5,.14),(.23,.49),(-.18,.37),(-.47,.5),(-.38,-.04)] ]
def weather_face(verts,m):
 data=WEAR.setdefault(m,{'verts':[],'faces':[]});start=len(data['verts']);data['verts'].extend(tuple(v) for v in verts);data['faces'].append(tuple(range(start,start+len(verts))))
def weather_patch(p,u,v,size,m='rust',profile=0):
 # Eight broad silhouette corners, no high-frequency scratches or small decals.
 weather_face([xyz(tuple(p[k]+u[k]*a*size[0]+v[k]*b*size[1] for k in range(3))) for a,b in WEAR_OUTLINES[profile%2]],m)
def beam_weather(o,width,length,center=-.30,span=.24,m='rust'):
 # Native beam local +Z is its length. Four matching surface patches wrap one
 # damaged section. An 8mm render offset avoids coplanar flicker; no collider
 # is generated or enlarged by this cosmetic surface layer.
 for axis in [0,1]:
  for sign in [-1,1]:
   verts=[]
   for a,b in WEAR_OUTLINES[axis]:
    p=[0.,0.,(center+b*span)*length];p[axis]=sign*(width*.5+.045);p[1-axis]=a*width*.93
    verts.append(o.matrix_world @ Vector(p))
   weather_face(verts,m)
def flush_weathering():
 # One mesh per weather material per asset, rather than a draw call per patch.
 for material,data in WEAR.items():
  mesh=bpy.data.meshes.new('Editable broad '+material+' patches');mesh.from_pydata(data['verts'],[],data['faces']);mesh.update()
  obj=bpy.data.objects.new('Port surface weathering '+material,mesh);bpy.context.collection.objects.link(obj);finish(obj,obj.name,material)
 WEAR.clear()
def batch_port_export():
 # Save the separately editable blend first. Runtime GLB then batches the static
 # port meshes by material, so weathering does not add per-patch draw calls.
 groups={}
 for obj in list(bpy.context.scene.objects):
  if obj.type!='MESH':continue
  bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
  for modifier in list(obj.modifiers):bpy.ops.object.modifier_apply(modifier=modifier.name)
  key=tuple(material.name for material in obj.data.materials);groups.setdefault(key,[]).append(obj)
 for key,objects in groups.items():
  bpy.ops.object.select_all(action='DESELECT')
  for obj in objects:obj.select_set(True)
  bpy.context.view_layer.objects.active=objects[0]
  if len(objects)>1:bpy.ops.object.join()
  objects[0].name='Port material '+(' '.join(key))
def finish(o,name,m,parent=None):
 o.name=name;o.data.materials.append(M[m]);
 if parent:o.parent=parent
 return o
def box(name,p,s,m='ivory',bevel=.08,parent=None):
 bpy.ops.mesh.primitive_cube_add(size=1,location=xyz(p));o=bpy.context.object;o.dimensions=(s[0],s[2],s[1]);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 if bevel:
  b=o.modifiers.new('Manufactured edge radius','BEVEL');b.width=min(bevel,min(s)*.18);b.segments=2
  o.modifiers.new('Weighted face normals','WEIGHTED_NORMAL')
 return finish(o,name,m,parent)
def cyl(name,p,r,h,m='steel',r2=None,parent=None):
 bpy.ops.mesh.primitive_cone_add(vertices=16,radius1=r,radius2=r if r2 is None else r2,depth=h,location=xyz(p));o=bpy.context.object
 return finish(o,name,m,parent)
def beam(name,a,b,width,m='steel'):
 a=Vector(xyz(a));b=Vector(xyz(b));d=b-a
 bpy.ops.mesh.primitive_cube_add(size=1,location=(a+b)/2);o=bpy.context.object;o.dimensions=(width,width,d.length);o.rotation_euler=d.to_track_quat('Z','Y').to_euler();bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);return finish(o,name,m)
def aged_beam(name,a,b,width):
 # Adjacent solid paint sections avoid coplanar weather decals and their shadow acne.
 av=Vector(a);bv=Vector(b)
 for start,end,material in [(0,.14,'rust'),(.14,.20,'oxide'),(.20,.78,'ochre'),(.78,.86,'rust'),(.86,1,'ochre')]:
  beam(name,av.lerp(bv,start),av.lerp(bv,end),width,material)
def empty(name,p):
 o=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(o);o.location=xyz(p);return o
def research():
 box('Foundation',(0,.28,0),(23,.56,15),'concrete');box('Glass lower band',(0,2.2,0),(21,3.4,13),'glass')
 box('Research upper volume',(0,6.4,0),(20,4.4,12));box('Window ribbon',(0,7,6.06),(17,1.7,.15),'glass');box('Window ribbon back',(0,7,-6.06),(17,1.7,.15),'glass')
 for x in [-9,-3,3,9]:box('Facade structural mullion',(x,2.2,6.7),(.28,3.6,.35),'ivory')
 box('Cantilever canopy',(0,4.1,1),(23,.45,15));box('Roof lip',(0,8.8,0),(21,.45,13),'ivory');box('Rooftop service',(5,9.3,-3),(5,1,3),'teal')
 for x in [-6,-2]:box('Roof photovoltaic',(x,9.08,-1),(3.2,.16,5),'solar')
 for x in [-8,8]:box('Upper shade fin',(x,7,6.5),(.2,2.7,1.2),'teal')
 box('Entrance',(0,1.8,6.7),(3,3.1,.3),'teal');box('Door glass',(0,1.8,6.9),(2.4,2.7,.12),'glass')
def workshop():
 box('Plinth',(0,.25,0),(16,.5,12),'concrete');box('Workshop shell',(0,2.8,0),(15,5,11));box('Roof',(0,5.5,0),(16,.4,12),'steel')
 for x in [-4,2]:
  box('Roller shutter',(x,2.2,5.6),(4.5,3.8,.2),'teal')
  for y in [1,2,3]:box('Shutter rib',(x,y,5.74),(4.4,.06,.08),'steel',.01)
 box('Clerestory',(0,4.7,5.65),(12,.65,.15),'glass');box('Ventilation',(4,5.9,-2),(3,.8,3),'concrete')
def test_frame():
 for x in [-4.4,4.4]:
  box('Concrete footing',(x,.2,0),(1.5,.4,3),'concrete');box('Flight test upright',(x,3.5,0),(.55,7,.55),'teal')
 box('Measurement crossbeam',(0,6.8,0),(9,.5,.6),'ivory');box('Instrument',(0,6.3,0),(1,.6,1),'ochre')
 for x in [-3,0,3]:box('Gate marker',(x,6.8,.34),(.4,.32,.08),'light')
def solar():
 for z in [-2.2,2.2]:
  for x in [-5,0,5]:
   box('Panel pier',(x,1,z),(.22,2,.22),'steel');box('Concrete shoe',(x,.15,z),(.7,.3,.7),'concrete')
  beam('Rack rail',(-6,2,z),(6,2,z),.15)
 for x in [-5.1,-1.7,1.7,5.1]:
  for z in [-2.05,2.05]:
   box('Aluminum frame',(x,2.35,z),(3.3,.18,3.9),'ivory',.02);box('Photovoltaic laminate',(x,2.46,z),(3.15,.06,3.7),'solar',.01)
   for dx in [-.8,0,.8]:box('Cell separator',(x+dx,2.495,z),(.018,.01,3.7),'concrete',0)
 box('Inverter',(0,.8,3.5),(1.5,1.6,.5),'teal')
def battery():
 box('Concrete foundation',(0,.2,0),(12,.4,7),'concrete')
 for x in [-4.4,-1.5,1.5,4.4]:
  box('Battery cabinet',(x,2,0),(2.6,3.5,4),'ivory');box('Cabinet door',(x,2,2.04),(2.2,3,.08),'teal',.02);box('Status strip',(x,3.1,2.12),(1.1,.12,.08),'light',.01)
  for y in [.8,1,1.2]:box('Passive vent',(x,y,2.1),(1.6,.04,.04),'steel',0)
 beam('Power bus',(-5,.7,-2.5),(5,.7,-2.5),.25,'ochre')
def substation():
 box('Substation apron',(0,.25,0),(12,.5,9),'concrete');box('Transformer',(0,1.9,0),(4.5,2.8,3.4),'teal')
 for x in [-2.5,2.5]:
  for z in [-1.2,-.6,0,.6,1.2]:box('Cooling radiator',(x,1.8,z),(.5,2.2,.18),'steel',.03)
 for x in [-1.4,0,1.4]:
  cyl('Insulator',(x,3.8,0),.24,1.4,'ivory')
  for y in [3.3,3.6,3.9,4.2]:cyl('Insulator skirt',(x,y,0),.34,.10,'concrete')
 for x in [-4.6,4.6]:beam('Electrical gantry',(x,0,-2.7),(x,5.7,-2.7),.3)
 beam('Power crossbeam',(-4.6,5.7,-2.7),(4.6,5.7,-2.7),.3)
 for x in [-2.6,0,2.6]:beam('Feeder',(x,5.5,-2.7),(x/2,4.4,0),.07,'ochre')
def turbine():
 cyl('Tower foundation',(0,.4,0),2,.8,'concrete');cyl('Tapered tubular tower',(0,10.6,0),.8,20,'ivory',.42);box('Nacelle',(0,20.7,.2),(2.2,1.8,4.2),'ivory',.25)
 box('Access door',(0,1.4,.79),(.7,1.7,.08),'teal');cyl('Hub',(0,20.7,-2.1),.65,.85,'steel')
 rotor=empty('Rotor',(0,20.7,-2.4))
 # Mesh coordinates relative to rotor: a true three-blade assembly in the XY plane.
 for i in range(3):
  a=i*2*math.pi/3
  pts=[(-.22,.45,0),(.42,1.4,.08),(.55,3.3,.04),(.12,8.5,0),(-.10,8.7,0),(-.25,3.3,-.05)]
  verts=[]
  for depth in [-.07,.07]:
   for x,y,z in pts:verts.append(xyz((x*math.cos(a)-y*math.sin(a),x*math.sin(a)+y*math.cos(a),z+depth)))
  n=len(pts);faces=[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]+[(j,(j+1)%n,(j+1)%n+n,j+n) for j in range(n)]
  mesh=bpy.data.meshes.new('Blade airfoil');mesh.from_pydata(verts,[],faces);mesh.update();o=bpy.data.objects.new('Blade_'+str(i),mesh);bpy.context.collection.objects.link(o);o.parent=rotor;finish(o,o.name,'ivory')
 # Rotor cap local to pivot, not baked into tower.
 cap=box('Rotor cap',(0,0,0),(1,.9,.8),'teal',.15,rotor)
def container_unit(x,y,z,m='rust',length=12.):
 half=length*.5;scale=length/12.
 # Foot origin stays at y=0; all fittings, paint patches and repairs fit inside
 # length x 2.8 x 3.0. Length is optional, preserving existing call sites.
 box('Container shell',(x,y+1.4,z),(length-.06,2.7,2.8),m)
 for dx in [-half+.16,half-.16]:
  box('End frame',(x+dx,y+1.4,z),(.18,2.8,2.9),'steel',.02)
  for side in [-1,1]:
   for h in [.12,2.68]:box('Corner casting',(x+dx,y+h,z+side*1.34),(.28,.24,.28),'steel',.02)
 for i in range(max(2,int(length)-1)):
  dx=-half+1.+i*(length-2.)/max(1,int(length)-2)
  for side in [-1,1]:box('Corrugated wall',(x+dx,y+1.4,z+side*1.43),(.12,2.5,.06),m,.01)
 box('Repaired end door',(x+half-.025,y+1.4,z),(.04,2.34,2.48),m,.012)
 box('Door dividing seam',(x+half-.003,y+1.4,z),(.006,2.30,.045),'steel',0)
 for side in [-1,1]:
  u=(1,0,0) if side==1 else (-1,0,0)
  if m in ['rust','concrete']:weather_patch((x-2.7*scale,y+.64,z+side*1.468),u,(0,1,0),(2.1*scale,.62),'oxide' if m=='rust' else 'rust',side)
  weather_patch((x,y+.27,z+side*1.471),u,(0,1,0),(length-.7,.46),'oxide',1)
  if side==1:weather_patch((x+4.4*scale,y+1.9,z+side*1.472),u,(0,1,0),(.45*scale,1.3),'rust' if m!='rust' else 'dust')
  box('Weld repair backing',(x+2.3*scale,y+1.27,z+side*1.475),(1.9*scale,1.12,.012),'steel',.01)
  box('Mismatched repair plate',(x+2.3*scale,y+1.27,z+side*1.485),(1.66*scale,.9,.018),'patch' if m!='ivory' else 'rust',.01)
 if m!='teal':weather_patch((x-2.5*scale,y+2.786,z+.9),(1,0,0),(0,0,-1),(2.3*scale,.6),'oxide' if m=='rust' else 'rust',1)
def container():
 container_unit(0,0,-1.5);container_unit(0,0,1.5,'teal');container_unit(0,2.8,-1.5,'ivory')
def container_low():
 # Single layer, same two-lane footprint; permits readable low sight lines.
 container_unit(0,0,-1.5,'teal');container_unit(0,0,1.5,'rust')
def container_offset():
 # A shorter salvaged top unit is shifted across the gap of the two lower rows.
 # No rotated or overhanging corners: the original 12 x 5.6 x 6 collider holds.
 container_unit(0,0,-1.5,'concrete');container_unit(0,0,1.5,'teal');container_unit(1.2,2.8,.6,'ochre',9.2)
def warehouse():
 box('Foundation',(0,.25,0),(24,.5,16),'concrete');box('Warehouse envelope',(0,4.5,0),(23,8,15),'steel')
 for side in [-1,1]:
  for x in range(-10,11,4):box('Metal siding pier',(x,4.5,side*7.6),(.25,8,.2),'concrete')
 box('Eave roof',(0,8.7,0),(24,.4,16),'ivory');box('Roof raised monitor',(0,9.3,0),(20,.9,3),'ivory')
 for x in [-7,0,7]:box('Warehouse shutter',(x,2.9,7.7),(5,5,.15),'rust');box('Dock canopy',(x,5.7,8.3),(6,.25,1.5),'ochre')
 # Roof and lower cladding carry the largest marks in the oblique view.
 for side in [-1,1]:
  weather_patch((0,1.02,side*7.515),(side,0,0),(0,1,0),(20.5,1.0),'oxide',side)
  weather_patch((-5,4.25,side*7.516),(side,0,0),(0,1,0),(5.1,3.5),'rust',1)
  weather_patch((6.5,6.1,side*7.517),(side,0,0),(0,1,0),(2.9,2.8),'rust')
  weather_patch((side*11.515,2.05,0),(0,0,side),(0,1,0),(11.8,2.1),'rust',1)
 weather_patch((-5.0,8.906,-4.5),(1,0,0),(0,0,-1),(8.4,4.5),'rust',1)
 weather_patch((5.7,8.907,4.6),(1,0,0),(0,0,-1),(6.3,4.0),'oxide')
 weather_patch((2.6,9.756,0),(1,0,0),(0,0,-1),(6.5,2.5),'rust')
 for x in [-7,7]:
  weather_patch((x,1.2,7.781),(1,0,0),(0,1,0),(4.5,1.2),'oxide')
  box('Warehouse shutter repair',(x+.7,3.0,7.796),(1.8,1.45,.025),'patch',.015)
  weather_patch((x,5.831,8.3),(1,0,0),(0,0,-1),(4.8,1.1),'oxide')
def crane():
 for x in [-10,10]:
  for z in [-3,3]:
   box('Rail bogie',(x,.8,z),(3,1.1,2),'steel');aged_beam('A-frame leg',(x,1,z),(x*.75,18,z*.5),.8)
   weather_patch((x,1.356,z),(1,0,0),(0,0,-1),(2.6,1.7),'rust',1)
   for xx in [-.8,.8]:cyl('Bogie wheel',(x+xx,.4,z),.4,.55,'steel')
  beam('Tie girder',(x*.75,12,-2),(x*.75,12,2),.4,'ochre')
 for z in [-1.5,1.5]:
  aged_beam('Crane top girder',(-12,18,z),(12,18,z),1);beam('Maintenance rail',(-12,20,z),(12,20,z),.10,'ivory')
  for x in range(-12,13,3):beam('Guardrail post',(x,18.7,z),(x,20,z),.10,'ivory')
 box('Trolley',(1,19,0),(4,1,4),'steel');box('Operator cabin',(-7,16,1.8),(2.3,2.5,2.3),'ivory');box('Cabin glazing',(-7,16.2,3),(1.9,1.4,.08),'glass')
 for x in [0,2]:beam('Hoist cable',(x,18,0),(x,10,0),.06,'steel')
 box('Spreader',(1,9.7,0),(5,.6,2),'ochre')
 weather_patch((1,10.006,0),(1,0,0),(0,0,-1),(4.4,1.7),'oxide',1)
 weather_patch((-7,17.256,1.8),(1,0,0),(0,0,-1),(2.0,1.9),'rust')
 box('Cabin welded replacement panel',(-7,15.2,2.963),(1.4,.65,.024),'patch',.015)
 for x in [-10,10]:beam('Crane rail',(x,.06,-12),(x,.06,12),.16,'steel')
def service():
 box('Service cabinet',(0,1.1,0),(1.6,2.2,.8),'ivory');box('Tool drawer',(0,.8,.45),(1.3,.7,.1),'teal');box('Display',(0,1.6,.45),(.9,.5,.08),'glass');box('Status',(0,1.99,.46),(.7,.08,.06),'light')
def shore_rock():
 import random
 rng=random.Random(616)
 for i,(x,y,z,scale) in enumerate([(-1.5,1,0,(3,2.5,3)),(1,1.3,.4,(4,3,3)),(0,.5,-1.5,(3,1.6,3))]):
  bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=1,location=xyz((x,y,z)));o=bpy.context.object
  o.scale=(scale[0]/2,scale[2]/2,scale[1]/2)
  for v in o.data.vertices:v.co.x*=rng.uniform(.85,1.15);v.co.y*=rng.uniform(.85,1.15)
  bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
  finish(o,'Weathered stone '+str(i),'stone')
for name,fn in [('shore_rock',shore_rock),('research',research),('workshop',workshop),('test_frame',test_frame),('solar',solar),('battery',battery),('substation',substation),('turbine',turbine),('container',container),('container_low',container_low),('container_offset',container_offset),('warehouse',warehouse),('crane',crane),('service',service)]:
 bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False);fn();flush_weathering()
 bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/(name+'.blend')))
 if name in ['container','container_low','container_offset','warehouse']:batch_port_export()
 bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'.glb')),export_format='GLB',export_apply=True,export_yup=True)
 print('WORLDUI_MODEL '+name)
conveyor=SOURCE/'conveyor_kenney/Models/GLB format'
for filename,name in [('conveyor-long-stripe-sides','conveyor'),('robot-arm-a','robot_arm'),('scanner-high','scanner_gate')]:
 path=conveyor/(filename+'.glb')
 if not path.exists():continue
 bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
 bpy.ops.import_scene.gltf(filepath=str(path))
 for o in list(bpy.context.scene.objects):
  if o.type!='MESH':continue
  original=list(o.data.materials);uv=o.data.uv_layers.active
  palette=['steel','ivory','ochre','teal'];indices=[]
  for face in o.data.polygons:
   col=(.25,.30,.30)
   material=original[min(face.material_index,len(original)-1)] if original else None
   if material and material.use_nodes and uv:
    tex=next((n.image for n in material.node_tree.nodes if n.type=='TEX_IMAGE' and n.image),None)
    if tex:
     u=sum(uv.data[k].uv.x for k in face.loop_indices)/len(face.loop_indices);v=sum(uv.data[k].uv.y for k in face.loop_indices)/len(face.loop_indices)
     w,h=tex.size;ix=min(w-1,max(0,int(u*w)));iy=min(h-1,max(0,int(v*h)));index=(iy*w+ix)*4;col=tuple(tex.pixels[index:index+3])
   lum=sum(col)/3
   indices.append(0 if lum<.24 else (1 if lum>.68 else (2 if col[0]>col[2]*1.3 else 3)))
  o.data.materials.clear()
  for key in palette:o.data.materials.append(M[key])
  for face,index in zip(o.data.polygons,indices):face.material_index=index
 bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/(name+'_kenney_styled.blend')))
 bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'.glb')),export_format='GLB',export_apply=True,export_yup=True)
(OUT/'manifest.json').write_text(json.dumps({'author':'Original project models; conveyor/robot_arm/scanner_gate are styled Kenney CC0 derivatives','units':'meters','palette':'ivory graphite teal ochre','roughness':.72,'models':[p.name for p in OUT.glob('*.glb')]},indent=2),encoding='utf-8')
