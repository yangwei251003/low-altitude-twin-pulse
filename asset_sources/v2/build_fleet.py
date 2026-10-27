"""Original editable V2 airframes and attachments, metres, GLB + Blender sources."""
import math
from pathlib import Path
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / 'assets/v2/models'
SOURCES = ROOT / 'asset_sources/v2/blend'
OUTPUT.mkdir(parents=True, exist_ok=True)
SOURCES.mkdir(parents=True, exist_ok=True)

def material(name, rgb, metallic=0.0, roughness=0.5, emission=0.0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*rgb, 1)
    mat.use_nodes = True
    node = next((n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None)
    if node is None:
        node = mat.node_tree.nodes.new('ShaderNodeBsdfPrincipled')
        output = next((n for n in mat.node_tree.nodes if n.type == 'OUTPUT_MATERIAL'), None)
        if output is None:
            output = mat.node_tree.nodes.new('ShaderNodeOutputMaterial')
        mat.node_tree.links.new(node.outputs['BSDF'], output.inputs['Surface'])
    node.inputs['Base Color'].default_value = (*rgb, 1)
    node.inputs['Metallic'].default_value = metallic
    node.inputs['Roughness'].default_value = roughness
    node.inputs['Emission Color'].default_value = (*rgb, 1)
    node.inputs['Emission Strength'].default_value = emission
    return mat

IVORY = material('Warm white enamel', (0.89, 0.89, 0.83), .15, .38)
DARK = material('Blue graphite frame', (.045, .095, .12), .6, .4)
TEAL = material('Teal working light', (.08, .65, .51), .15, .28, .7)
AMBER = material('Amber safety mark', (.95, .49, .12), .2, .4)
METAL = material('Brushed alloy', (.38, .46, .47), .7, .38)
RUBBER = material('Damped feet', (.02, .026, .03), 0, .85)
GLASS = material('Optical blue glass', (.08, .30, .4), .55, .15)

def reset():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)

def box(name, pos, size, mat, bevel=.025):
    bpy.ops.mesh.primitive_cube_add(size=1, location=pos)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    if bevel:
        mod = obj.modifiers.new('Machined edges', 'BEVEL')
        mod.width = bevel
        mod.segments = 2
        obj.modifiers.new('Face normals', 'WEIGHTED_NORMAL')
    return obj

def cylinder(name, pos, radius, depth, mat, vertices=16):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=pos)
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    mod = obj.modifiers.new('Rim', 'BEVEL')
    mod.width = .009
    mod.segments = 2
    obj.modifiers.new('Normals', 'WEIGHTED_NORMAL')
    return obj

def beam(name, a, b, width, mat):
    a, b = Vector(a), Vector(b)
    obj = box(name, (a + b) / 2, (width, width, (b-a).length), mat, .012)
    obj.rotation_euler = (b-a).to_track_quat('Z', 'Y').to_euler()
    return obj

def rotor(x, y, z, radius, index, guarded=False):
    cylinder('Motor%d' % index, (x,y,z), .068, .09, METAL)
    bpy.ops.object.empty_add(location=(x,y,z+.07))
    pivot = bpy.context.object
    pivot.name = 'Rotor%02d' % index
    for a in [0, math.pi]:
        blade = box('Propeller', (x + math.cos(a)*radius*.45,y+math.sin(a)*radius*.45,z+.07), (radius*.92,.054,.015), DARK, .008)
        blade.rotation_euler.z = a + .12
        blade.parent = pivot
        blade.matrix_parent_inverse = pivot.matrix_world.inverted()
    cylinder('RotorCap', (x,y,z+.085), .033, .04, TEAL)
    if guarded:
        bpy.ops.mesh.primitive_torus_add(major_segments=24, minor_segments=6, location=(x,y,z+.02), major_radius=radius+.027, minor_radius=.022)
        bpy.context.object.name = 'RotorProtection'
        bpy.context.object.data.materials.append(IVORY)

def export(name):
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCES / (name+'.blend')))
    bpy.ops.export_scene.gltf(filepath=str(OUTPUT/(name+'.glb')), export_format='GLB', export_yup=True, export_apply=True, export_animations=False, export_cameras=False, export_lights=False)

FRAMES = {
    'tr01': (1.4,1.4,4,.24), 'hx02':(2.2,1.9,6,.29),
    'ag03':(.9,1.0,4,.17), 'nx04':(1.5,1.6,4,.24),
    'sh05':(1.8,1.8,4,.26), 'at06':(1.6,1.9,4,.25),
}
for name, (width,length,count,radius) in FRAMES.items():
    reset()
    body_w = width * (.28 if name != 'hx02' else .35)
    body_l = length * (.46 if name == 'at06' else .40)
    box('Chassis', (0,0,0), (body_w,body_l,.20), DARK)
    box('UpperShell', (0,0,.115), (body_w*.88,body_l*.86,.12), IVORY)
    box('BatterySpine', (0,.04,.20), (body_w*.35,body_l*.66,.055), TEAL)
    for side in [-1,1]:
        box('SideRail', (side*body_w*.49,0,.04), (.025,body_l*.7,.05), METAL)
        box('NavigationLight', (side*body_w*.33,-body_l*.48,.12), (.06,.035,.04), TEAL)
        for end in [-1,1]:
            beam('LandingStrut', (side*body_w*.4,end*body_l*.38,-.08), (side*body_w*.55,end*body_l*.45,-.28), .035, METAL)
            box('LandingFoot', (side*body_w*.55,end*body_l*.45,-.29), (.12,.07,.04), RUBBER)
    for i in range(count):
        angle = math.tau*i/count + (math.pi/4 if count==4 else math.pi/6)
        x = math.cos(angle)*(width/2-radius-.04)
        y = math.sin(angle)*(length/2-radius-.04)
        beam('Arm', (x*.2,y*.2,0), (x,y,.025), .075 if name != 'ag03' else .05, DARK)
        beam('ArmStripe', (x*.5,y*.5,.04), (x*.85,y*.85,.06), .025, IVORY)
        rotor(x,y,.04,radius,i,name in ['tr01','sh05'])
        if name=='sh05': rotor(x,y,-.12,radius,i+4)
    if name=='hx02':
        for x in [-.28,.28]: box('CargoRail', (x,.08,-.27), (.08,.9,.08), AMBER)
        box('WinchBay',(0,.08,-.12),(.33,.37,.13),METAL)
    if name=='ag03':
        box('RacingNose',(0,-.24,.08),(.16,.2,.09),AMBER)
    if name=='nx04':
        cylinder('SensorPivot',(0,-.30,-.12),.10,.13,METAL)
        lens=cylinder('OpticalLens',(0,-.38,-.16),.072,.08,GLASS)
        lens.rotation_euler.x=math.pi/2
        box('SensorHood',(0,-.35,-.045),(.27,.23,.035),DARK)
    if name=='sh05':
        for x in [-body_w*.55,body_w*.55]: box('Armor', (x,0,.05),(.07,body_l*.9,.19),IVORY)
    if name=='at06':
        for x in [-.27,.27]:
            box('WeaponPod',(x,-.26,-.05),(.15,.4,.14),IVORY)
            for j in range(5): box('CoolingFin',(x,.16+j*.045,.12),(.14,.014,.085),METAL,.006)
    export(name)

MODULES = ['pulse_base','burst_capacitor','scan_base','hook_base','delivery_base','clearance_base','searchlight_base','guard_base','cargo_winch','precision_gimbal','racing_drive','long_range_battery','night_sensor','cooling_duct','reinforced_guard']
for name in MODULES:
    reset()
    box('MountAdapter',(0,0,.03),(.18,.18,.04),METAL,.008)
    if name in ['hook_base','cargo_winch']:
        cylinder('WinchDrum',(0,0,-.065),.10,.12,AMBER)
        beam('HookShank',(0,0,-.10),(0,0,-.25),.035,METAL)
        beam('HookClaw',(0,0,-.25),(.09,0,-.25),.035,METAL)
    elif name in ['pulse_base','burst_capacitor']:
        box('Receiver',(0,0,-.04),(.17,.25,.12),DARK)
        barrel=cylinder('Barrel',(0,-.20,-.04),.038,.21,METAL)
        barrel.rotation_euler.x=math.pi/2
        if name=='burst_capacitor':
            for x in [-.105,.105]: cylinder('Capacitor',(x,0,-.03),.034,.16,TEAL)
    elif name in ['scan_base','night_sensor','precision_gimbal','searchlight_base']:
        box('Gimbal',(0,0,-.05),(.18,.16,.13),DARK)
        lens=cylinder('Lens',(0,-.095,-.05),.055,.05,TEAL if name=='searchlight_base' else GLASS)
        lens.rotation_euler.x=math.pi/2
    elif name=='delivery_base':
        box('CargoBox',(0,0,-.10),(.28,.32,.19),IVORY)
        box('DeliveryBand',(0,0,-.205),(.10,.33,.012),TEAL,.003)
    elif name=='clearance_base':
        box('CutterHousing',(0,0,-.06),(.18,.23,.12),AMBER)
        wheel=cylinder('CutterWheel',(0,-.17,-.07),.085,.025,METAL,20)
        wheel.rotation_euler.x=math.pi/2
    elif name=='cooling_duct':
        box('Duct',(0,0,.08),(.22,.24,.12),DARK)
        for y in [-.08,-.04,0,.04,.08]: box('Fin',(0,y,.16),(.24,.014,.06),METAL,.003)
    elif name=='reinforced_guard':
        for x in [-.22,.22]: box('GuardPlate',(x,0,0),(.05,.45,.16),IVORY)
    else:
        box('Pack',(0,0,.08),(.22,.29,.12),IVORY)
        box('StatusBand',(0,-.15,.08),(.14,.015,.05),TEAL,.003)
    export(name)
print('V2_FLEET_EXPORTED', len(FRAMES), len(MODULES))
