"""Original miniature combat fleet. Blender --background --factory-startup --python this.py.
No external geometry/textures. Editable parts are saved before runtime batching.
Blender +Y nose exports as Godot -Z; units are meters. Optional -- --no-render.
"""
import bpy, math, json, hashlib, sys
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/models/v22_combat'
SOURCE = ROOT / 'assets/source_models/v22_combat'
OUT.mkdir(parents=True, exist_ok=True)
SOURCE.mkdir(parents=True, exist_ok=True)
(SOURCE / '.gdignore').write_text('', encoding='utf-8')
META = []
PIVOTS = {}
bpy.context.preferences.filepaths.save_version = 0

def material(name, hex_color, metal=0.15, rough=.48, emission=0):
    rgb = [int(hex_color[i:i+2], 16)/255 for i in (0, 2, 4)]
    rgb = [v/12.92 if v <= .04045 else ((v+.055)/1.055)**2.4 for v in rgb]
    m = bpy.data.materials.new(name); m.use_nodes = True; m.diffuse_color = (*rgb, 1)
    bsdf = m.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*rgb, 1)
    bsdf.inputs['Metallic'].default_value = metal; bsdf.inputs['Roughness'].default_value = rough
    bsdf.inputs['Emission Color'].default_value = (*rgb, 1)
    bsdf.inputs['Emission Strength'].default_value = emission
    return m

PAINT = material('ceramic ivory enamel', 'D8D6C6', .15)
DARK = material('graphite gunmetal', '273940', .6)
EDGE = material('brushed edge metal', '8CABA9', .7, .36)
AMBER = material('ochre safety enamel', 'D7A045', .2)
RUST = material('warm red oxide', 'AD6451', .3)
BLUE = material('slate blue casing', '487183', .25)
BLACK = material('carbon and rubber', '15232A', .05, .7)
COPPER = material('copper conductor', 'A98052', .7)
LIGHT = material('enemy amber optics', 'FFBF69', .05, .3, 1.8)
GLASS = material('dark optical glass', '356E7F', .4, .22)

def clear():
    global PIVOTS
    bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
    PIVOTS = {}
    bpy.context.scene.cursor.location = (0, 0, 0)

def finish(obj, name, mat, group='Body', bevel=0):
    obj.name = name; obj.data.materials.append(mat); obj['motion_group'] = group
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod = obj.modifiers.new('manufactured soft edge', 'BEVEL'); mod.width = bevel; mod.segments = 2
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj

def box(name, pos, size, mat=PAINT, group='Body', bevel=.018):
    bpy.ops.mesh.primitive_cube_add(size=1, location=pos); obj=bpy.context.object; obj.dimensions=size
    return finish(obj, name, mat, group, min(bevel, min(size)*.2))

def cyl(name, pos, radius, depth, mat=DARK, group='Body', vertices=12):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=pos)
    return finish(bpy.context.object, name, mat, group, .007 if depth>.03 else 0)

def rod(name, a, b, radius=.025, mat=EDGE, group='Body', vertices=10):
    a,b=Vector(a),Vector(b); obj=cyl(name, (a+b)/2, radius, (b-a).length, mat, group, vertices)
    obj.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler(); return obj

def ring(name, pos, radius, thick, mat=PAINT, group='Body'):
    bpy.ops.mesh.primitive_torus_add(major_segments=20, minor_segments=6, major_radius=radius, minor_radius=thick, location=pos)
    return finish(bpy.context.object, name, mat, group)

def shell(name, length, width, height, pos=(0,0,0), mat=PAINT):
    # Octagonal chamfered plan, with a tapered raised upper shell.
    outline=[(-.37,-.5),(.37,-.5),(.5,-.30),(.47,.30),(.25,.5),(-.25,.5),(-.47,.30),(-.5,-.30)]
    vertices=[]
    for z, shrink in [(-height*.5, .92), (height*.15,1), (height*.5,.76)]:
        vertices.extend([(pos[0]+x*width*shrink, pos[1]+y*length*shrink, pos[2]+z) for x,y in outline])
    faces=[tuple(reversed(range(8))),tuple(range(16,24))]
    for level in range(2):
        for i in range(8): faces.append((level*8+i,level*8+(i+1)%8,(level+1)*8+(i+1)%8,(level+1)*8+i))
    me=bpy.data.meshes.new(name);me.from_pydata(vertices,[],faces);me.update()
    obj=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(obj)
    return finish(obj,name,mat,'Body',.016)

def empty(name, pos):
    obj=bpy.data.objects.new(name,None);obj.location=pos;obj.empty_display_size=.08;bpy.context.collection.objects.link(obj)
    return obj

def bolts(pos, width, length, z):
    for x,y in [(-width,-length),(width,-length),(width,length),(-width,length)]:
        cyl('recessed fastener',(pos[0]+x,pos[1]+y,z),.025,.012,EDGE,vertices=8)

def vents(x, y, z, count=5, length=.2):
    for i in range(count):box('recessed cooling grille',(x+(i-(count-1)/2)*.062,y,z),(.026,length,.018),BLACK,bevel=.003)

def duct(index, pos, radius=.29, accent=PAINT):
    x,y,z=pos; name='Rotor_'+str(index); PIVOTS[name]=pos
    ring('upper duct lip',pos,radius,.047,accent)
    ring('lower protective lip',(x,y,z-.085),radius,.025,DARK)
    for angle in [0,math.pi*.5,math.pi,math.pi*1.5]:
        dx,dy=math.cos(angle),math.sin(angle)
        rod('duct reinforcement',(x+dx*radius,y+dy*radius,z),(x+dx*radius,y+dy*radius,z-.085),.016,EDGE)
    rod('fixed motor bridge',(x-radius,y,z-.04),(x+radius,y,z-.04),.019,DARK)
    cyl('motor stator',(x,y,z-.045),.069,.13,DARK)
    cyl('rotor hub',(x,y,z+.015),.057,.04,EDGE,name)
    for angle in [0,2*math.pi/3,4*math.pi/3]:
        a=(x+math.cos(angle)*.04,y+math.sin(angle)*.04,z+.02)
        b=(x+math.cos(angle)*radius*.88,y+math.sin(angle)*radius*.88,z+.02)
        obj=box('swept rotor blade',Vector(a).lerp(Vector(b),.5),((Vector(b)-Vector(a)).length,.055,.013),BLACK,name,.004)
        obj.rotation_euler.z=angle-.15

def optic(y, z, radius=.11, x=0):
    rod('sensor gimbal bracket',(x-.15,y-.04,z+.11),(x+.15,y-.04,z+.11),.035,DARK)
    obj=cyl('gimbal optical housing',(x,y,z),radius,.17,DARK);obj.rotation_euler.x=math.pi/2
    obj=cyl('front lens bezel',(x,y+.09,z),radius*.83,.025,EDGE);obj.rotation_euler.x=math.pi/2
    obj=cyl('amber optical lens',(x,y+.106,z),radius*.62,.014,LIGHT,'Lights');obj.rotation_euler.x=math.pi/2

def landing_skids(length=.55, width=.27):
    for side in [-1,1]:
        rod('spring skid',(side*width,-length*.5,-.31),(side*width,length*.5,-.31),.025,DARK)
        for y in [-length*.35,length*.35]:rod('skid strut',(side*width,y,-.31),(side*width*.8,y,-.13),.022,EDGE)

def markings(width=.23, y=0, z=.17, color=AMBER):
    for x in [-width,width]:box('identification stripe',(x,y,z),(.052,.36,.018),color,bevel=.003)
    box('service panel',(0,-.18,z+.013),(.20,.19,.025),BLUE,bevel=.012)
    bolts((0,-.18),.077,.064,z+.03)

def antenna(x,y,z,height=.3):
    cyl('antenna socket',(x,y,z),.045,.07,DARK)
    rod('whip antenna',(x,y,z+.03),(x+.025,y,z+height),.012,EDGE)
    cyl('antenna amber cap',(x+.025,y,z+height),.024,.055,AMBER)

def weapon(kind='pulse', origin=(0,0,0), group='Body'):
    x,y,z=origin
    box('gimbal weapon chassis',(x,y,z),(.24,.36,.19),DARK,group)
    rod('weapon pivot',(x-.17,y-.08,z+.09),(x+.17,y-.08,z+.09),.05,EDGE,group)
    if kind=='pulse':
        box('ceramic barrel shroud',(x,y+.17,z),(.20,.26,.15),PAINT,group)
        rod('pulse bore',(x,y+.17,z),(x,y+.42,z),.064,BLACK,group,16)
        obj=cyl('pulse copper coil',(x,y+.25,z),.081,.065,COPPER,group);obj.rotation_euler.x=math.pi/2
        tip=.45
    elif kind=='burst':
        box('ammunition magazine',(x+.19,y-.03,z-.035),(.14,.27,.20),AMBER,group)
        for side in [-1,1]:
            rod('paired burst barrel',(x+side*.067,y+.1,z),(x+side*.067,y+.50,z),.035,BLACK,group)
            for offset in [.19,.27,.35]:
                obj=cyl('barrel cooling collar',(x+side*.067,y+offset,z),.047,.025,EDGE,group,12);obj.rotation_euler.x=math.pi/2
        tip=.53
    else:
        box('capacitor housing',(x,y-.07,z),(.30,.30,.24),BLUE,group)
        for side in [-1,1]:
            box('induction rail',(x+side*.1,y+.24,z),(.055,.57,.085),EDGE,group)
            for offset in [.08,.18,.28]:box('rail insulator',(x+side*.1,y+offset,z+.055),(.065,.035,.035),AMBER,group)
        box('charge aperture',(x,y+.48,z),(.07,.025,.065),LIGHT,'Lights')
        tip=.54
    return (x,y+tip,z)

def scout():
    clear(); shell('triangular scout lower hull',.85,.58,.22,mat=DARK)
    shell('scout raised armor',.72,.54,.19,(0,.015,.12))
    for i,pos in enumerate([(-.48,.24,.04),(.48,.24,.04),(0,-.52,.04)]):
        rod('tri motor arm',(0,0,0),pos,.045,EDGE);duct(i,pos,.245)
    optic(.42,-.06,.12);markings(.16,.03,.22);vents(0,-.18,.235,3,.10)
    antenna(.13,-.22,.23,.27);landing_skids(.5,.2)
    empty('WeaponMount',(0,.12,-.18));empty('SensorMount',(0,.44,-.06))
    export('enemy_scout','Scout / visible sensor head, three ducted motors, amber IFF')

def harasser():
    clear();shell('slender carbon keel',1.18,.43,.19,mat=DARK)
    shell('streamlined top shell',1.05,.48,.21,(0,.025,.12),BLUE)
    for i,pos in enumerate([(-.58,.30,.04),(.58,.30,.04),(-.47,-.43,.04),(.47,-.43,.04)]):
        rod('swept front outrigger',(0,-.15,-.01),pos,.045,EDGE);duct(i,pos,.235,PAINT)
    optic(.60,.04,.09);markings(.13,0,.23,RUST)
    for x in [-.13,.13]:vents(x,-.28,.24,2,.18)
    for x in [-.20,.20]:
        fin=box('swept tail fin',(x,-.46,.27),(.035,.30,.24),AMBER);fin.rotation_euler.x=-.3
    weapon('pulse',(0,.10,-.18));landing_skids(.6,.23)
    empty('WeaponMount',(0,.12,-.18));empty('Muzzle',(0,.56,-.18))
    export('enemy_harasser','Harasser / long hull, swept ducts, twin tail fins')

def suppressor():
    clear();shell('heavy reinforced chassis',1.15,.98,.30,mat=DARK)
    shell('stepped front armor',1.05,.9,.23,(0,.02,.20),PAINT)
    for i,pos in enumerate([(-.74,.47,.02),(.74,.47,.02),(-.74,-.47,.02),(.74,-.47,.02)]):
        rod('heavy spar',(0,pos[1]*.5,-.03),pos,.085,DARK);duct(i,pos,.305,AMBER)
    for x in [-.35,.35]:
        box('raised armor shoulder',(x,0,.28),(.19,.72,.15),BLUE)
        vents(x,-.10,.36,2,.36)
        for y in [-.25,.25]:cyl('shoulder armor bolt',(x,y,.365),.03,.012,EDGE,vertices=8)
    box('central recoil track',(0,0,.32),(.21,.7,.08),DARK)
    optic(.56,.18,.13);weapon('burst',(0,.21,-.22));landing_skids(.75,.4)
    antenna(-.23,-.39,.32,.25);antenna(.23,-.39,.32,.25)
    empty('WeaponMount',(0,.2,-.22));empty('Muzzle',(0,.74,-.22))
    export('enemy_suppressor','Suppression / wide low armor, four large ducts, paired barrels')

def support():
    clear();cyl('circular service chassis',(0,0,0),.41,.25,DARK,vertices=24)
    cyl('service dome',(0,0,.16),.36,.18,PAINT,vertices=24)
    ring('protected orange service rim',(0,0,.22),.33,.022,AMBER)
    for i,pos in enumerate([(-.59,.36,.03),(.59,.36,.03),(-.59,-.36,.03),(.59,-.36,.03)]):
        rod('repair platform boom',(0,pos[1]*.4,0),pos,.05,EDGE);duct(i,pos,.26)
    for side in [-1,1]:
        cyl('external service reservoir',(side*.20,-.1,.33),.095,.31,BLUE)
        ring('reservoir retaining band',(side*.20,-.1,.32),.10,.014,EDGE)
        rod('repair nozzle',(side*.20,.20,-.12),(side*.20,.56,-.20),.035,COPPER)
    rod('carry handle left',(-.16,-.2,.25),(-.16,-.2,.56),.025,DARK)
    rod('carry handle bridge',(-.16,-.2,.56),(.16,-.2,.56),.025,DARK)
    rod('carry handle right',(.16,-.2,.56),(.16,-.2,.25),.025,DARK)
    optic(.39,-.015,.09);antenna(0,-.29,.26,.37);landing_skids(.65,.28)
    box('service marking horizontal',(0,.12,.265),(.22,.055,.02),RUST)
    box('service marking vertical',(0,.12,.265),(.055,.22,.02),RUST)
    empty('WeaponMount',(0,.1,-.18));empty('RepairNozzle',(0,.57,-.20))
    export('enemy_support','Support / circular service body, reservoirs, repair nozzles')

def weapon_asset(kind):
    clear();tip=weapon(kind);empty('Muzzle',tip);empty('Attachment',(0,-.08,.1))
    export('weapon_'+kind,'Modular '+kind+' weapon; mounting origin is pivot, Muzzle points -Z')

def wrecks():
    clear();shell('fractured chassis',.68,.48,.21,mat=DARK)
    box('exposed internal battery',(0,-.08,.07),(.24,.28,.11),AMBER)
    for x in [-.1,0,.1]:rod('broken copper bus',(x,.06,.10),(x+.03,.29,.03),.015,COPPER)
    plate=box('bent upper casing',(-.12,-.05,.16),(.24,.42,.035),PAINT);plate.rotation_euler.y=.35
    export('wreck_core','Shared collision wreck core / exposed battery and broken bus')
    clear();rod('broken rotor spar',(-.35,0,0),(.20,0,.025),.055,DARK)
    ring('fractured duct',(.20,0,0),.22,.035,PAINT)
    cyl('damaged motor',(.20,0,.03),.065,.12,EDGE)
    blade=box('bent remaining blade',(.27,0,.10),(.28,.055,.012),BLACK);blade.rotation_euler.y=.25
    rod('loose conductor',(-.28,.03,.03),(-.06,.08,.08),.012,COPPER)
    export('wreck_rotor','Shared rotor arm wreck / duct, hub and bent blade')
    clear();shell('detached protective panel',.42,.34,.035,mat=PAINT)
    box('retained underside rib',(0,0,-.035),(.28,.035,.025),DARK)
    box('damaged identification stripe',(.08,0,.028),(.04,.28,.008),AMBER,bevel=.001)
    bolts((0,0),.11,.14,.025)
    export('wreck_panel','Shared detached enamel panel / underside rib and retained bolts')

def export(name, usage):
    scene=bpy.context.scene;scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
    scene['license']='CC0-1.0';scene['author']='Low Altitude Squad original procedural art, 2026-10-15'
    scene['front_axis_blender']='+Y';scene['front_axis_godot']='-Z'
    objects=[o for o in scene.objects if o.type=='MESH'];bpy.context.view_layer.update()
    points=[o.matrix_world@Vector(v) for o in objects for v in o.bound_box]
    mins=[min(p[i] for p in points) for i in range(3)];maxs=[max(p[i] for p in points) for i in range(3)]
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/(name+'.blend')))
    groups={};runtime_materials={}
    for group in ['paint','emissive']:
        m=bpy.data.materials.new(name+' '+group+' vertex colors');m.use_nodes=True
        bsdf=m.node_tree.nodes.get('Principled BSDF');bsdf.inputs['Roughness'].default_value=.5;bsdf.inputs['Metallic'].default_value=.25
        colors=m.node_tree.nodes.new('ShaderNodeVertexColor');colors.layer_name='Color'
        m.node_tree.links.new(colors.outputs['Color'],bsdf.inputs['Base Color'])
        if group=='emissive':
            m.node_tree.links.new(colors.outputs['Color'],bsdf.inputs['Emission Color']);bsdf.inputs['Emission Strength'].default_value=1.1
        runtime_materials[group]=m
    for obj in objects:
        group=obj.get('motion_group','Body');attr=obj.data.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='CORNER')
        mats=list(obj.data.materials)
        for polygon in obj.data.polygons:
            for li in polygon.loop_indices:attr.data[li].color=mats[polygon.material_index].diffuse_color
        obj.data.materials.clear();obj.data.materials.append(runtime_materials['emissive' if group=='Lights' else 'paint'])
        for polygon in obj.data.polygons:polygon.material_index=0
        groups.setdefault(group,[]).append(obj)
    for group,parts in groups.items():
        bpy.ops.object.select_all(action='DESELECT')
        for obj in parts:obj.select_set(True)
        bpy.context.view_layer.objects.active=parts[0]
        if len(parts)>1:bpy.ops.object.join()
        obj=bpy.context.object;obj.name=group
        bpy.context.scene.cursor.location=PIVOTS.get(group,(0,0,0));bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'.glb')),export_format='GLB',export_yup=True,export_animations=False,export_apply=True,export_extras=True)
    triangles=sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in scene.objects if o.type=='MESH')
    META.append({'id':name,'scene':'res://assets/models/v22_combat/'+name+'.glb','source':'assets/source_models/v22_combat/'+name+'.blend','scale':1.0,'front':'-Z','size_xyz':[round(maxs[0]-mins[0],4),round(maxs[2]-mins[2],4),round(maxs[1]-mins[1],4)],'triangles':triangles,'surface_count':len(groups),'mesh_nodes':list(groups),'rotor_nodes':{n:[p[0],p[2],-p[1]] for n,p in PIVOTS.items()},'usage':usage,'sha256':hashlib.sha256((OUT/(name+'.glb')).read_bytes()).hexdigest(),'license':'CC0-1.0'})

def render_catalog():
    clear();scene=bpy.context.scene
    positions=[(-3.15,1.8,0),(-1.05,1.8,0),(1.15,1.8,0),(3.4,1.8,0),(-2.5,-.5,.08),(0,-.5,.08),(2.5,-.5,.08),(-2.5,-2,.08),(0,-2,.08),(2.5,-2,.08)]
    for item,pos in zip(META,positions):
        old=set(bpy.data.objects);bpy.ops.import_scene.gltf(filepath=str(OUT/(item['id']+'.glb')))
        new=set(bpy.data.objects)-old
        for obj in new:
            if obj.parent not in new:obj.location+=Vector(pos)
    box('catalog floor',(0,0,-.42),(13,10,.1),material('matte catalog ground','687D81',0,.9),bevel=0)
    scene.world.color=(.18,.18,.18)
    for name,pos,power,size in [('large softbox',(1,3,7),1200,7),('cool fill',(-5,-1,4),800,6),('edge highlight',(4,-3,5),1000,5)]:
        data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size
        obj=bpy.data.objects.new(name,data);bpy.context.collection.objects.link(obj);obj.location=pos;obj.rotation_euler=(Vector((0,0,0))-obj.location).to_track_quat('-Z','Y').to_euler()
    data=bpy.data.cameras.new('catalog oblique camera');cam=bpy.data.objects.new('catalog oblique camera',data);bpy.context.collection.objects.link(cam)
    cam.location=(4.8,8.8,10.8);cam.rotation_euler=(Vector((0,0,.0))-cam.location).to_track_quat('-Z','Y').to_euler();data.type='ORTHO';data.ortho_scale=10.8;scene.camera=cam
    scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=24;scene.cycles.use_denoising=True
    scene.render.resolution_x=1600;scene.render.resolution_y=1050;scene.render.resolution_percentage=100
    scene.view_settings.view_transform='AgX';scene.render.image_settings.file_format='PNG';scene.render.filepath=str(SOURCE/'catalog_cpu_render.png')
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'catalog_scene.blend'));bpy.ops.render.render(write_still=True)

scout();harasser();suppressor();support()
for kind in ['pulse','burst','lance']:weapon_asset(kind)
wrecks()
license_text='Original V2.2 combat models, editable sources and generator are dedicated to CC0 1.0 Universal.\nAuthoring: Low Altitude Squad project, 2026-10-15.\nNo external geometry, textures, fonts or images used.\nhttps://creativecommons.org/publicdomain/zero/1.0/\n'
(SOURCE/'LICENSE.txt').write_text(license_text,encoding='utf-8');(OUT/'LICENSE.txt').write_text(license_text,encoding='utf-8')
(OUT/'manifest.json').write_text(json.dumps({'version':'V2.2 combat','units':'meters','up_axis':'Y','front_axis':'-Z','license':'CC0-1.0','author':'Low Altitude Squad project original procedural art','models':META},ensure_ascii=False,indent=2),encoding='utf-8')
verification={'models':len(META),'all_sources_exist':all((ROOT/m['source']).is_file() for m in META),'max_triangles':max(m['triangles'] for m in META),'total_glb_bytes':sum((OUT/(m['id']+'.glb')).stat().st_size for m in META),'failures':[]}
for item in META:
    if item['triangles']>18000:verification['failures'].append(item['id']+' exceeds triangle budget')
(SOURCE/'verification.json').write_text(json.dumps(verification,indent=2),encoding='utf-8')
print('V22_COMBAT_ASSETS',json.dumps(verification))
if '--no-render' not in sys.argv:render_catalog()
