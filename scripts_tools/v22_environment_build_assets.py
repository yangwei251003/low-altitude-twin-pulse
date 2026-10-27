"""Original V2.2 functional scenery. Run using Blender --background --factory-startup.
Meters, Blender Z-up => Godot Y-up, facade front Godot +Z. No downloaded inputs.
The editable .blend preserves components; runtime GLB merges compatible parts.
"""
import bpy, math, json, hashlib, random
from pathlib import Path
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/models/v22'; SOURCE=ROOT/'assets/source_models/v22'
OUT.mkdir(parents=True,exist_ok=True);SOURCE.mkdir(parents=True,exist_ok=True)
random.seed(221014)
META=[]
def mat(n,c):
    rgb=[int(c[i:i+2],16)/255 for i in (0,2,4)]
    rgb=[v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in rgb]
    m=bpy.data.materials.new(n);m.diffuse_color=(*rgb,1);m.use_nodes=True
    m.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=(*rgb,1)
    m.node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value=.7
    return m
CREAM=mat('warm limestone','E2DCCC');DARK=mat('blue graphite','29434D');TEAL=mat('harbor enamel','39868D')
AMBER=mat('safety ochre','E3AE55');RED=mat('warning coral','CE705C');METAL=mat('galvanized silver','A6B9B6')
WOOD=mat('oiled cedar','AA825F');LEAF=mat('coastal sage','6F8F69');LEAF2=mat('dry reed','B5AD72')
SKIN=mat('warm skin','C49D80');GLASS=mat('blue glass','507C89');WHITE=mat('chalk','EEEADC')

def clear():
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
def finish(o,n,m,group='Body',bone=None):
    o.name=n;o.data.materials.append(m);o['motion_group']=group
    bpy.context.view_layer.objects.active=o;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if bone:o['bone']=bone
    return o
def box(n,p,s,m=CREAM,group='Body',bone=None):
    bpy.ops.mesh.primitive_cube_add(size=1,location=p);o=bpy.context.object;o.dimensions=s
    return finish(o,n,m,group,bone)
def cyl(n,p,r,d,m=DARK,verts=10,group='Body',bone=None):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts,radius=r,depth=d,location=p)
    return finish(bpy.context.object,n,m,group,bone)
def rod(n,a,b,r=.04,m=DARK,group='Body',bone=None):
    a,b=Vector(a),Vector(b);o=cyl(n,(a+b)/2,r,(b-a).length,m,10,group,bone)
    o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler();return o
def sphere(n,p,s,m=LEAF,group='Body',bone=None):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=1,location=p);o=bpy.context.object;o.scale=s
    return finish(o,n,m,group,bone)
def mesh(n,verts,faces,m=CREAM,group='Body'):
    me=bpy.data.meshes.new(n);me.from_pydata(verts,[],faces);me.update();o=bpy.data.objects.new(n,me)
    bpy.context.collection.objects.link(o);o.data.materials.append(m);o['motion_group']=group;return o
def ring(n,p,r,t,m=METAL,group='Body'):
    bpy.ops.mesh.primitive_torus_add(major_segments=16,minor_segments=4,major_radius=r,minor_radius=t,location=p)
    return finish(bpy.context.object,n,m,group)
def rail(a,b,z=1.0):
    for h in [.45,z]:rod('guard rail',(a[0],a[1],h),(b[0],b[1],h),.045,METAL)
    length=math.dist(a,b);count=max(1,int(length/1.2))
    for i in range(count+1):
        p=Vector(a).lerp(Vector(b),i/count);rod('upright',(p.x,p.y,0),(p.x,p.y,z),.055,DARK)
def export(name,use,pivots=None,rig=False):
    objects=[o for o in bpy.context.scene.objects if o.type=='MESH']
    bpy.context.view_layer.update();points=[o.matrix_world@Vector(v) for o in objects for v in o.bound_box]
    mins=[min(p[i] for p in points) for i in range(3)];maxs=[max(p[i] for p in points) for i in range(3)]
    bpy.context.scene.unit_settings.system='METRIC';bpy.context.scene.unit_settings.scale_length=1
    bpy.context.scene['asset_license']='CC0-1.0';bpy.context.scene['asset_author']='Low Altitude Squad V2.2 original procedural model'
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/(name+'.blend')))
    # Single vertex-color material, preserving mechanical pivots and skinning.
    material=bpy.data.materials.new('V22 vertex color');material.use_nodes=True
    nodes=material.node_tree.nodes;shader=nodes.get('Principled BSDF');shader.inputs['Roughness'].default_value=.7
    vc=nodes.new('ShaderNodeVertexColor');vc.layer_name='Color';material.node_tree.links.new(vc.outputs['Color'],shader.inputs['Base Color'])
    groups={}
    for o in objects:
        colors=o.data.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='CORNER')
        originals=list(o.data.materials)
        for poly in o.data.polygons:
            color=originals[poly.material_index].diffuse_color
            for li in poly.loop_indices:colors.data[li].color=color
        o.data.materials.clear();o.data.materials.append(material)
        for p in o.data.polygons:p.material_index=0
        if rig and not o.vertex_groups.get(o.get('bone','Hip')):
            g=o.vertex_groups.new(name=o.get('bone','Hip'));g.add(list(range(len(o.data.vertices))),1.0,'REPLACE')
        groups.setdefault(o.get('motion_group','Body'),[]).append(o)
    for group,parts in groups.items():
        bpy.ops.object.select_all(action='DESELECT')
        for o in parts:o.select_set(True)
        bpy.context.view_layer.objects.active=parts[0];bpy.ops.object.join();o=bpy.context.object;o.name=group
        bpy.context.scene.cursor.location=Vector((pivots or {}).get(group,(0,0,0)))
        bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
        if rig:
            arm=bpy.data.objects.get('PedestrianRig')
            modifier=next((m for m in o.modifiers if m.type=='ARMATURE'),None) or o.modifiers.new('Simple walking skeleton','ARMATURE')
            modifier.object=arm;o.parent=arm
    bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'.glb')),export_format='GLB',export_yup=True,export_animations=True,export_apply=False)
    tris=sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in bpy.context.scene.objects if o.type=='MESH')
    META.append({'id':name,'path':'res://assets/models/v22/'+name+'.glb','source':'assets/source_models/v22/'+name+'.blend','footprint':[round(maxs[0]-mins[0],3),round(maxs[1]-mins[1],3)],'height':round(maxs[2]-mins[2],3),'triangles':tris,'surface_count':len(groups),'motion_groups':list(groups),'usage':use,'license':'CC0-1.0','sha256':hashlib.sha256((OUT/(name+'.glb')).read_bytes()).hexdigest()})

def weather_station():
    clear();box('service plinth',(0,0,.12),(1.4,1.25,.24),CREAM)
    cyl('sensor mast',(0,0,1.9),.07,3.6,METAL)
    box('locked station cabinet',(0,0,.85),(.72,.50,.85),TEAL)
    box('display bezel',(0,-.26,.96),(.43,.04,.30),DARK)
    box('display screen',(0,-.285,.96),(.34,.02,.20),GLASS)
    for x in [-.15,0,.15]:cyl('panel control',(x,-.29,.66),.035,.03,AMBER)
    for z in [1.5,1.58,1.66,1.74]:cyl('temperature radiation shield',(0,0,z),.22,.035,WHITE,16)
    rod('vane arm',(-.55,0,3.3),(.55,0,3.3),.025,DARK,'WindVane')
    mesh('direction fin',[(-.55,0,3.3),(-.85,0,3.45),(-.85,0,3.15)],[(0,1,2)],AMBER,'WindVane')
    rod('anemometer arm',(-.4,0,3.65),(.4,0,3.65),.02,DARK,'Anemometer')
    rod('anemometer cross',(0,-.4,3.65),(0,.4,3.65),.02,DARK,'Anemometer')
    for x,y in [(-.4,0),(.4,0),(0,-.4),(0,.4)]:sphere('wind cup',(x,y,3.65),(.1,.1,.06),DARK,'Anemometer')
    box('solar panel rim',(.48,0,2.5),(.7,.7,.06),METAL)
    box('solar cells',(.48,0,2.54),(.62,.62,.025),DARK)
    for y in [-.2,0,.2]:box('solar divider',(.48,y,2.56),(.62,.015,.01),GLASS)
    export('weather_station','Readable wind direction/speed and weather selection',{'WindVane':(0,0,3.3),'Anemometer':(0,0,3.65)})

def ventilator():
    clear();box('concrete machinery footing',(0,0,.1),(2.6,1.8,.2),CREAM)
    box('teal fan enclosure',(0,0,1.6),(2.1,1.1,2.7),TEAL)
    for x in [-1,1]:box('edge rail',(x,-.58,1.6),(.12,.1,2.65),CREAM)
    hoop=ring('fan safety bezel',(0,-.6,1.85),.82,.09,METAL);hoop.rotation_euler.x=math.pi/2
    for x in [-.56,-.28,0,.28,.56]:rod('protective grille',(x,-.76,1.22),(x,-.76,2.48),.018,DARK)
    for i in range(5):
        a=i*math.tau/5;v=[(0,-.66,1.85),(.26,-.66,1.85),(.53,-.66,2.32),(.06,-.66,2.5)]
        rotated=[(x*math.cos(a)+(z-1.85)*math.sin(a),y,1.85-x*math.sin(a)+(z-1.85)*math.cos(a)) for x,y,z in v]
        mesh('rotor blade',rotated,[(0,1,2,3)],AMBER,'FanRotor')
    for z in [.42,.56,.70]:box('intake louvre',(0,-.58,z),(1.4,.08,.065),DARK)
    box('power switch box',(1.22,-.1,1.15),(.28,.5,.56),DARK)
    box('stop button',(1.22,-.365,1.2),(.13,.04,.13),RED)
    export('ventilator','Switchable +Z air jet with rotating protected impeller',{'FanRotor':(0,-.66,1.85)})

def crane():
    clear()
    for x in [-4,4]:
        box('bogie beam',(x,0,.3),(.75,4.2,.5),DARK)
        for y in [-1.5,1.5]:cyl('rail wheel',(x,y,.23),.25,.35,METAL,12)
        box('gantry column',(x,0,3.2),(.45,.55,6.0),TEAL)
        rod('diagonal bracing',(x,0,.8),(x*.72,0,5.8),.075,METAL)
    box('overhead box beam',(0,0,6.1),(8.8,.8,.7),TEAL)
    for x in range(-4,5):box('beam stiffener',(x,-.45,6.1),(.12,.10,.64),AMBER)
    box('trolley carriage',(0,0,5.55),(1.3,1.15,.36),DARK,'Trolley')
    for x in [-.42,.42]:rod('suspension cable',(x,0,5.4),(x,0,3.1),.025,METAL,'Hook')
    box('hook block',(0,0,3.08),(1.2,.65,.35),AMBER,'Hook')
    hook=ring('hook eye',(0,-.05,2.75),.23,.07,DARK,'Hook');hook.rotation_euler.x=math.pi/2
    box('operator station',(-3.3,-.9,4.9),(1.0,1.0,1.35),CREAM)
    box('operator glazing',(-3.3,-1.42,5.06),(.82,.04,.82),GLASS)
    for z in [1.0,1.4,1.8,2.2,2.6,3,3.4,3.8,4.2]:rod('ladder step',(-4.32,-.4,z),(-3.68,-.4,z),.035,METAL)
    export('gantry_crane','Port gantry with physical supports, moving hook and warning cycle',{'Trolley':(0,0,5.55),'Hook':(0,0,3.08)})

def platform():
    clear();box('lifting deck',(0,0,.18),(4.6,3.4,.36),DARK)
    for i in range(13):box('deck boards',(-2.1+i*.35,0,.39),(.32,3.1,.06),WOOD)
    for x in [-2.2,2.2]:box('yellow edge',(x,0,.41),(.1,3.4,.04),AMBER)
    for y in [-1.6,1.6]:box('yellow edge',(0,y,.41),(4.5,.10,.04),AMBER)
    for x in [-1.7,1.7]:
        rod('folding lift scissor',(x,-1.1,.02),(x,1.1,.31),.065,METAL)
        rod('folding lift scissor',(x,1.1,.02),(x,-1.1,.31),.065,METAL)
    for x in [-1.8,1.8]:cyl('deck warning puck',(x,-1.2,.45),.12,.05,AMBER)
    export('lift_platform','Animatable platform; collider top is local Y=0.45m')

def shore():
    clear();mesh('layered sloping bank',[(-4,-2,0),(4,-2,0),(-4,2,0),(4,2,0),(-4,-2,1.5),(4,-2,1.5),(-4,2,.15),(4,2,.15)],[(0,1,3,2),(0,4,5,1),(4,6,7,5),(2,3,7,6),(0,2,6,4),(1,5,7,3)],CREAM)
    for x in range(-3,4):
        sphere('bank stone',(x,1.7,.3),(.75,.5,.35),METAL)
        box('cap stone',(x,-1.9,1.52),(.95,.6,.16),CREAM)
    export('shore_bank','Visible sloping riprap edge; static collision supplied by terrain owner')

def bridge():
    clear();box('reinforced bridge slab',(0,0,.2),(12,5.6,.4),CREAM)
    box('asphalt deck',(0,0,.43),(11.7,5.1,.06),DARK)
    for x in range(-5,6,2):box('center lane marking',(x,0,.47),(.9,.08,.015),WHITE)
    for y in [-2.65,2.65]:rail((-5.8,y),(5.8,y),1.25)
    for x in [-4.8,4.8]:box('bridge bearing',(x,0,.09),(.7,5.6,.18),METAL)
    export('bridge_deck','Real bridge deck, railings, expansion joints; local top Y=.46m')

def dock():
    clear()
    for x in [-1.1,1.1]:cyl('flotation pontoon',(x,0,.28),.28,4.6,DARK,12).rotation_euler.x=math.pi/2
    box('dock bearer',(0,0,.49),(3.0,5.1,.15),DARK)
    for i in range(18):box('cedar planks',(0,-2.4+i*.28,.60),(3.1,.25,.10),WOOD)
    for x in [-1.35,1.35]:
        for y in [-2.15,2.15]:cyl('mooring bollard',(x,y,.85),.09,.45,TEAL);cyl('bollard cap',(x,y,1.08),.14,.06,METAL)
    for y in [-1,0,1]:
        fender=ring('rubber fender',(1.60,y,.5),.24,.08,DARK);fender.rotation_euler.y=math.pi/2
    export('floating_dock','Near-shore low-amplitude floating landing platform; deck Y=.65m')

def person(name,outfit,helmet=False):
    clear()
    box('jacket',(0,0,1.14),(.46,.3,.54),outfit,bone='Hip')
    box('reflective stripe',(0,-.155,1.13),(.46,.02,.07),CREAM,bone='Hip')
    sphere('head',(0,0,1.59),(.145,.13,.18),SKIN,bone='Hip')
    if helmet:
        sphere('safety helmet',(0,0,1.74),(.18,.15,.08),AMBER,bone='Hip');box('helmet brim',(0,-.05,1.72),(.37,.35,.03),AMBER,bone='Hip')
    else:sphere('hair',(0,.015,1.7),(.15,.13,.08),DARK,bone='Hip')
    for side,letter in [(-1,'L'),(1,'R')]:
        leg='Leg'+letter;arm='Arm'+letter
        rod('trouser leg',(side*.13,0,.86),(side*.13,0,.18),.085,DARK,bone=leg)
        box('shoe',(side*.13,-.05,.09),(.19,.34,.16),DARK,bone=leg)
        rod('sleeve',(side*.27,0,1.36),(side*.34,0,1.06),.08,outfit,bone=arm)
        rod('forearm',(side*.34,0,1.06),(side*.4,-.03,.88),.055,SKIN,bone=arm)
        sphere('hand',(side*.4,-.03,.87),(.06,.06,.08),SKIN,bone=arm)
    armdata=bpy.data.armatures.new('PedestrianRig');arm=bpy.data.objects.new('PedestrianRig',armdata);bpy.context.collection.objects.link(arm)
    bpy.context.view_layer.objects.active=arm;arm.select_set(True);bpy.ops.object.mode_set(mode='EDIT')
    hip=armdata.edit_bones.new('Hip');hip.head=(0,0,.9);hip.tail=(0,0,1.2)
    for side,letter in [(-1,'L'),(1,'R')]:
        b=armdata.edit_bones.new('Leg'+letter);b.head=(side*.13,0,.86);b.tail=(side*.13,0,.18);b.parent=hip
        b=armdata.edit_bones.new('Arm'+letter);b.head=(side*.27,0,1.36);b.tail=(side*.4,-.03,.88);b.parent=hip
    bpy.ops.object.mode_set(mode='POSE')
    for frame in [1,7,13,19,25]:
        phase=(frame-1)/24*math.tau
        for n,sign in [('LegL',1),('LegR',-1),('ArmL',-1),('ArmR',1)]:
            p=arm.pose.bones[n];p.rotation_mode='XYZ';p.rotation_euler.x=math.sin(phase)*.32*sign;p.keyframe_insert(data_path='rotation_euler',frame=frame)
    bpy.ops.object.mode_set(mode='OBJECT');bpy.context.scene.frame_start=1;bpy.context.scene.frame_end=25;bpy.context.scene.render.fps=24;bpy.context.scene.frame_set(1)
    # Editable source needs the same skin bindings as the interchange export.
    for o in [o for o in bpy.context.scene.objects if o.type=='MESH']:
        g=o.vertex_groups.new(name=o.get('bone','Hip'));g.add(list(range(len(o.data.vertices))),1,'REPLACE')
        mod=o.modifiers.new('Walking skin','ARMATURE');mod.object=arm;o.parent=arm
    export(name,'Shared five-bone walk cycle, low-poly pedestrian; no physical flight blocker',rig=True)

def barrier():
    clear()
    for x in [-1.2,1.2]:box('weighted foot',(x,0,.08),(.7,.8,.16),DARK);rod('post',(x,0,.15),(x,0,1.25),.06,TEAL)
    box('reflective barrier',(0,0,.92),(2.8,.15,.48),CREAM)
    for x in [-1.15,-.58,0,.58,1.15]:
        o=box('warning stripe',(x,-.09,.92),(.25,.03,.49),AMBER);o.rotation_euler.y=-.32
    cyl('beacon stem',(0,0,1.38),.05,.4,DARK);sphere('warning beacon',(0,0,1.6),(.12,.12,.14),AMBER)
    export('construction_barrier','Solid weighted construction rail with warning beacon')

def reeds():
    clear()
    for i in range(17):
        x=random.uniform(-.7,.7);y=random.uniform(-.55,.55);h=random.uniform(.5,1.4)
        rod('reed stem',(x,y,0),(x+.10,y,h),.012,LEAF)
        mesh('lance leaf',[(x,y,h*.25),(x+.34,y+.04,h*.62),(x+.12,y,h*.85)],[(0,1,2)],LEAF2 if i%3==0 else LEAF)
        if i%3==0:cyl('reed seedhead',(x+.1,y,h),.045,.2,LEAF2,6)
    export('shore_reeds','Native coastal reeds; vertex wind anchored at ground')

def bird():
    clear();sphere('gull body',(0,0,.16),(.17,.32,.14),WHITE)
    sphere('gull head',(0,-.28,.23),(.12,.13,.12),WHITE)
    mesh('beak',[(-.055,-.35,.22),(.055,-.35,.22),(0,-.53,.2),(0,-.35,.29)],[(0,1,2),(0,3,2),(1,2,3)],AMBER)
    for side in [-1,1]:mesh('wing',[(side*.1,0,.17),(side*.46,-.1,.18),(side*.85,.2,.13),(side*.18,.25,.14)],[(0,1,2,3)],WHITE,'WingLeft' if side<0 else 'WingRight')
    export('seagull','Small banked shore flock; low-cost articulated wings',{'WingLeft':(-.1,0,.17),'WingRight':(.1,0,.17)})

weather_station();ventilator();crane();platform();shore();bridge();dock()
person('pedestrian_worker',AMBER,True);person('pedestrian_walker',TEAL);person('pedestrian_citizen',RED)
barrier();reeds();bird()
(SOURCE/'.gdignore').write_text('',encoding='utf-8')
(SOURCE/'LICENSE.txt').write_text('These original V2.2 models and the generator are dedicated under CC0 1.0 Universal.\nAuthoring: Low Altitude Squad V2.2 project, 2026-10-14.\nhttps://creativecommons.org/publicdomain/zero/1.0/\nNo external model, image, font, or texture inputs.\n',encoding='utf-8')
(OUT/'manifest.json').write_text(json.dumps({'version':'V2.2','units':'meters','up_axis':'Y','front_axis':'+Z','license':'CC0-1.0','models':META},indent=2),encoding='utf-8')
print('V22_MODELS_COMPLETE',len(META),sum(m['triangles'] for m in META),flush=True)
