"""Original Harbor Garden modular assets, authored against approved reference sheets.
Run with Blender 5.2: blender --background --python asset_sources/build_models.py
"""
import bpy, math, random
from pathlib import Path
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/models'
SOURCE=ROOT/'asset_sources/blend'
OUT.mkdir(parents=True,exist_ok=True)
SOURCE.mkdir(parents=True,exist_ok=True)
random.seed(41)

def mat(name,hexcolor,metal=0,rough=.5,emission=0):
    color=tuple(int(hexcolor[i:i+2],16)/255 for i in (0,2,4))
    # Convert display sRGB colors to linear Blender inputs.
    linear=tuple(v/12.92 if v<.04045 else ((v+.055)/1.055)**2.4 for v in color)
    m=bpy.data.materials.new(name); m.diffuse_color=(*linear,1)
    m.use_nodes=True
    m.node_tree.nodes.clear()
    p=m.node_tree.nodes.new('ShaderNodeBsdfPrincipled')
    output=m.node_tree.nodes.new('ShaderNodeOutputMaterial')
    m.node_tree.links.new(p.outputs['BSDF'],output.inputs['Surface'])
    p.inputs['Base Color'].default_value=(*linear,1)
    p.inputs['Metallic'].default_value=metal; p.inputs['Roughness'].default_value=rough
    if emission:
        p.inputs['Emission Color'].default_value=(*linear,1); p.inputs['Emission Strength'].default_value=emission
    return m

IVORY=mat('Ceramic ivory','E8E3D4',.05,.42)
NAVY=mat('Navy powdercoat','233D49',.45,.35)
TEAL=mat('Teal paint','438D92',.15,.42)
METAL=mat('Brushed aluminum','93A5A6',.65,.32)
BLACK=mat('Dark rubber','142832',0,.65)
AMBER=mat('Warning amber','E7A147',.05,.48)
RED=mat('Enemy coral','C8604D',.12,.42)
GREEN=mat('Support sage','708D6B',.05,.55)
LIGHT=mat('Cyan lens','71E4DE',.15,.2,1.0)
HOT=mat('Amber core','FFAF58',.1,.26,1.4)
STONE=mat('Warm limestone','C9C5B7',0,.86)
EDGE=mat('Stone edge','AAA99D',0,.8)
WOOD=mat('Dock cedar','A1805B',0,.72)
LEAF=mat('Leaf sage','648163',0,.82)
LEAF2=mat('Leaf light','7F9569',0,.82)
TRUNK=mat('Tree bark','6E654E',0,.85)

def clear():
    bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)

def finish(obj,name,material,bevel=0):
    obj.name=name
    obj.data.materials.append(material)
    if bevel:
        bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
        mod=obj.modifiers.new('Fine manufactured edge','BEVEL'); mod.width=bevel; mod.segments=3
        bpy.context.view_layer.objects.active=obj
        bpy.ops.object.modifier_apply(modifier=mod.name)
        mod=obj.modifiers.new('Weighted surface normals','WEIGHTED_NORMAL')
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj

def box(name,loc,size,material=IVORY,bevel=.04):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc)
    o=bpy.context.object; o.dimensions=size
    return finish(o,name,material,bevel)

def cyl(name,loc,radius,depth,material=NAVY,vertices=24):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=radius,depth=depth,location=loc)
    return finish(bpy.context.object,name,material,.012)

def sphere(name,loc,scale,material=IVORY,sub=2):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=sub,radius=1,location=loc)
    o=bpy.context.object;o.scale=scale
    return finish(o,name,material)

def rod(name,a,b,radius,material=NAVY):
    a,b=Vector(a),Vector(b); o=cyl(name,(a+b)/2,radius,(b-a).length,material,12)
    o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler();return o

def ring(name,loc,radius,thick,material=IVORY):
    bpy.ops.mesh.primitive_torus_add(major_segments=40,minor_segments=8,location=loc,major_radius=radius,minor_radius=thick)
    return finish(bpy.context.object,name,material)

def label(text,loc,size=.25,material=NAVY):
    bpy.ops.object.text_add(location=loc);o=bpy.context.object;o.data.body=text;o.data.size=size;o.data.align_x='CENTER';o.data.extrude=.001
    o.data.materials.append(material);bpy.ops.object.convert(target='MESH');return o

def export(name):
    # Editable native source before material batching.
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/(name+'.blend')))
    for material in bpy.data.materials:
        objects=[o for o in bpy.context.scene.objects if o.type=='MESH' and not o.name.startswith('Rotor') and o.data.materials and o.data.materials[0]==material]
        if len(objects)>1:
            bpy.ops.object.select_all(action='DESELECT')
            for o in objects:o.select_set(True)
            bpy.context.view_layer.objects.active=objects[0];bpy.ops.object.join()
            bpy.context.object.name='Body_'+material.name
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'.glb')),export_format='GLB',export_apply=True,export_yup=True)
    print('ASSET_EXPORTED '+name,flush=True)

def drone(kind):
    clear(); player=kind=='player'; paint=TEAL if player else (GREEN if kind=='repair' else RED)
    if kind=='repair': cyl('Round repair body',(0,0,.05),.47,.32,IVORY)
    else:
        shell=box('Ceramic body',(0,0,.06),(.62,1.04 if kind!='charger' else 1.28,.32),IVORY,.12)
        if kind=='charger':shell.scale.x=.82
    box('Battery spine',(0,-.13,.255),(.29,.57,.12),paint,.05)
    box('Battery latch',(0,-.22,.335),(.12,.16,.055),NAVY,.015)
    box('Belly frame',(0,0,-.14),(.50,.76,.18),NAVY,.04)
    box('Optic surround',(0,.51,.025),(.30,.15,.18),NAVY,.035)
    box('Optic cyan',(0,.59,.045),(.16,.025,.07),LIGHT if player else HOT,.02)
    for x in [-.80,.80]:
        for y in [-.73,.73]:
            rod('Arm',(x*.30,y*.35,-.02),(x,y,.03),.07,NAVY)
            rod('Arm edge',(x*.33,y*.4,.055),(x*.85,y*.90,.10),.025,METAL)
            cyl('Motor',(x,y,.07),.11,.28,NAVY)
            cyl('Hub trim',(x,y,.04),.12,.035,paint)
            ring('Propeller guard',(x,y,.19),.37,.032,IVORY if player else paint)
            for k in range(4):
                ang=k*math.pi/2
                rod('Guard strut',(x,y,.05),(x+math.cos(ang)*.35,y+math.sin(ang)*.35,.17),.012,NAVY)
            blades=[]
            for k in range(2):
                blade=box('Blade',(x,y,.205),(.66,.065,.02),BLACK,.016);blade.rotation_euler.z=k*math.pi/2
                blades.append(blade)
            bpy.ops.object.select_all(action='DESELECT')
            for o in blades:o.select_set(True)
            bpy.context.view_layer.objects.active=blades[0];bpy.ops.object.join();o=bpy.context.object
            bpy.context.scene.cursor.location=(x,y,.205);bpy.ops.object.origin_set(type='ORIGIN_CURSOR');o.name=f'Rotor_{x}_{y}'
            cyl('Hub cap',(x,y,.255),.065,.06,paint)
    for x in [-.38,.38]:
        rod('Landing leg',(x*.6,.35,-.18),(x,.45,-.5),.035,NAVY)
        rod('Landing leg',(x*.6,-.35,-.18),(x,-.45,-.5),.035,NAVY)
        rod('Landing skid',(x,-.53,-.51),(x,.55,-.51),.04,BLACK)
    for x in [-.23,.23]:
        for y in [-.37,.30]:cyl('Shell screw',(x,y,.23),.018,.014,METAL,8)
    if kind=='repair':ring('Support ring',(0,0,.3),.25,.023,GREEN)
    export('player' if player else 'enemy_'+kind)

for kind in ['player','patrol','charger','repair']:drone(kind)
for kind in ['pulse','charge','shield','cooler','agile','stable']:
    clear()
    if kind in ['agile','stable']:
        for x in [-.80,.80]:
            for y in [-.73,.73]:
                ring('Motor upgrade band',(x,y,-.03),.13,.025,TEAL if kind=='agile' else IVORY)
                if kind=='agile':rod('Fin',(x,y,-.1),(x*1.15,y,-.3),.018,TEAL)
    else:
        box('Module shell',(0,0,0),(.32,.38,.23),IVORY,.045)
        for x in [-.19,.19]:box('Mounting lug',(x,0,.08),(.08,.16,.07),NAVY,.013)
        if kind in ['pulse','charge']:
            barrel=cyl('Emitter',(0,.26,-.02),.11 if kind=='charge' else .075,.31,NAVY);barrel.rotation_euler.x=math.pi/2
            lens=cyl('Emitter optic',(0,.42,-.02),.073 if kind=='charge' else .045,.025,LIGHT);lens.rotation_euler.x=math.pi/2
            if kind=='charge':
                for x in [-.1,.1]:box('Emitter rail',(x,.25,.05),(.035,.35,.045),TEAL,.008)
        elif kind=='shield':sphere('Shield generator',(0,0,.1),(.16,.16,.11),TEAL);ring('Ring',(0,0,.12),.12,.014,LIGHT)
        else:
            for y in [-.14,-.07,0,.07,.14]:box('Radiator fin',(0,y,.15),(.34,.025,.10),NAVY,.004)
    export('module_'+kind)

clear()
cyl('Base',(0,0,-.60),1.30,.40,NAVY)
cyl('Core cradle',(0,0,.15),1.12,.35,IVORY)
sphere('Amber reactor',(0,0,.60),(.80,.80,.90),HOT,3)
for z in [0,.55,1.12]:ring('Core brace',(0,0,z),.82,.075,NAVY)
for angle in range(0,360,60):
    a=math.radians(angle);rod('Reactor rib',(math.cos(a)*.8,math.sin(a)*.8,-.1),(math.cos(a)*.8,math.sin(a)*.8,1.2),.065,NAVY)
cyl('Top housing',(0,0,1.45),1.25,.48,IVORY)
cyl('Vent plate',(0,0,1.74),.85,.12,NAVY)
for x in [-.5,-.25,0,.25,.5]:box('Top grille',(x,0,1.83),(.055,1.0,.09),METAL,.01)
for x in [-1.2,1.2]:
    for y in [-1.0,1.0]:
        cyl('Shoulder',(x,y,.8),.50,.7,IVORY)
        cyl('Shoulder cap',(x,y,1.17),.37,.11,RED)
        rod('Leg upper',(x,y,.5),(x*1.5,y*1.4,-.20),.22,NAVY)
        sphere('Joint',(x*1.5,y*1.4,-.20),(.30,.30,.30),METAL)
        rod('Leg lower',(x*1.5,y*1.4,-.2),(x*1.65,y*1.6,-1.30),.22,NAVY)
        armor=box('Leg armor',(x*1.58,y*1.5,-.65),(.50,.5,.7),IVORY,.1)
        box('Foot',(x*1.65,y*1.6,-1.45),(.70,.85,.22),NAVY,.05)
export('boss')

clear();cyl('Power footing',(0,0,.18),.55,.36,NAVY);cyl('Housing',(0,0,.8),.35,1.1,IVORY)
for a in range(0,360,90):
    angle=math.radians(a);box('Status light',(math.cos(angle)*.34,math.sin(angle)*.34,.9),(.08,.08,.45),HOT,.015)
cyl('Cap',(0,0,1.4),.44,.14,TEAL);export('node')

clear();box('Cargo shell',(0,0,.45),(1.0,.8,.9),IVORY,.07)
for x in [-.44,.44]:box('Cargo band',(x,0,.46),(.12,.84,.92),NAVY,.022)
box('Cargo lid',(0,0,.95),(.8,.68,.07),AMBER,.018)
box('Handle',(0,0,1.04),(.35,.12,.06),NAVY,.02);export('crate')

clear();box('Cover footing',(0,0,.10),(2.4,1.0,.20),EDGE,.06)
box('Cover',(0,0,.82),(2.2,.8,1.45),STONE,.10)
box('Cover cap',(0,0,1.58),(2.3,.87,.12),IVORY,.03)
for x in [-.75,0,.75]:box('Stripe',(x,-.412,1.15),(.23,.016,.10),AMBER,.005)
export('cover')

clear();box('Planter base',(0,0,.3),(2.8,1.4,.6),IVORY,.10)
box('Soil',(0,0,.63),(2.5,1.1,.08),TRUNK,.02)
for x in [-.85,0,.85]:sphere('Bush',(x,0,.93),(.58,.5,.45),LEAF if x else LEAF2)
export('planter')

clear();cyl('Tree planter',(0,0,.22),.85,.44,STONE)
rod('Trunk',(0,0,.3),(.13,.03,2.4),.13,TRUNK)
for i in range(7):
    a=i*2.4;z=2.25+random.random()*.8;x=math.cos(a)*.65;y=math.sin(a)*.6
    rod('Branch',(0,0,1.5),(x,y,z),.055,TRUNK)
    sphere('Crown',(x,y,z),(.75,.75,.9),LEAF if i%2 else LEAF2)
export('tree')

clear();box('Hangar base',(0,0,.15),(6.8,4.6,.3),STONE,.08)
box('Hangar walls',(0,0,1.65),(6.2,4,3.0),IVORY,.12)
box('Door surround',(0,-2.05,1.35),(3.0,.2,2.6),NAVY,.04)
box('Door recess',(0,-2.18,1.28),(2.6,.04,2.36),BLACK,.02)
for x in [-1.15,-.58,0,.58,1.15]:box('Door rib',(x,-2.22,1.3),(.04,.04,2.2),METAL,.008)
box('Roof',(0,0,3.25),(6.5,4.25,.23),TEAL,.075)
box('Roof trim',(0,-2.2,3.14),(6.7,.12,.16),IVORY,.025)
for x in [-2.4,2.4]:
    box('Window',(x,-2.035,1.9),(.72,.06,.65),NAVY,.04)
    box('Window glass',(x,-2.07,1.9),(.57,.03,.5),TEAL,.02)
for x in [-2,-1,0,1,2]:box('Solar cell',(x,.6,3.42),(.84,1.5,.06),NAVY,.015)
for x in [-2.65,2.65]:rod('Drain',(x,-1.7,.25),(x,-1.7,3.25),.05,METAL)
for x in [-1,1]:cyl('Vent',(x,1.4,3.53),.22,.38,METAL)
sign=label('HARBOR / 01',(0,-2.22,2.76),.28,IVORY);sign.rotation_euler.x=math.pi/2
export('hangar')

clear()
for x in [-2,2]:
    box('Arch support',(x,0,1.75),(.30,.55,3.5),NAVY,.05)
    box('Arch foot',(x,0,.1),(.65,.85,.2),STONE,.05)
box('Canopy roof',(0,0,3.55),(4.5,1.8,.28),TEAL,.08)
for x in [-1.8,1.8]:box('Mark',(x,-.31,2.0),(.20,.04,.30),AMBER,.01)
export('canopy')

clear();cyl('Pad base',(0,0,.08),2.1,.16,NAVY,64);cyl('Pad stone',(0,0,.18),1.98,.10,STONE,64)
ring('Pad trim',(0,0,.25),1.8,.045,TEAL)
for x in [-.5,.5]:box('H mark',(x,0,.25),(.13,1.3,.012),IVORY,.003)
box('H cross',(0,0,.25),(1.0,.13,.012),IVORY,.003);export('pad')

clear();box('Dock',(0,0,.15),(3.0,5.0,.30),NAVY,.04)
for y in range(12):box('Plank',(0,-2.28+y*.41,.34),(2.9,.37,.12),WOOD,.012)
for x in [-1.45,1.45]:
    for y in [-2.25,2.25]:cyl('Post',(x,y,0),.12,2.0,WOOD);ring('Tie',(x,y,.8),.15,.024,NAVY)
export('dock')

clear();cyl('Lamp base',(0,0,.12),.25,.24,NAVY);rod('Lamp stem',(0,0,.2),(0,0,2.3),.06,NAVY)
box('Lamp head',(0,0,2.38),(.5,.35,.16),IVORY,.04);box('Lamp bulb',(0,0,2.28),(.38,.23,.03),LIGHT,.005)
export('lamp')
print('ALL_MODELS_COMPLETE',flush=True)
