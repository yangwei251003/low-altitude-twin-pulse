"""Reception V4 source-only revision. Prepared, not executed.

Run ONLY in a root-approved CPU2 window:
blender.exe -b -t 2 --python-exit-code 2 --python this_file.py -- --render-pair
Optional --entry-view adds a clearly labelled eye-level diagnostic, not a game view.
No GLB, GPU, runtime scene, external generation, or lower support is produced.
Frozen production_candidate is input; all output stays in revision_v4.
Godot-local (x,y,z) maps to Blender (x,-z,y); future world origin (7,5,-6).
"""
from pathlib import Path
import hashlib
import importlib.util
import json
import math
import sys

import bpy
from mathutils import Vector

OUT = Path(__file__).resolve().parent
PREVIOUS = OUT.parent / 'production_candidate'
INPUT = PREVIOUS / 'clinic_reception_candidate.blend'
INPUT_SHA = '685dc8489dbc8bb8acbe65ebd8a7b1271b9e2f04e7f46243e22951839da72fa2'
HELPER = PREVIOUS / 'build_reception_candidate.py'
HELPER_SHA = '99011033237d1fc4dde171a01276b9cf293703fad789c100a5ba321e4bb70e50'
FONT_PATH = Path('C:/Windows/Fonts/msyh.ttc')
EPS = 1e-6

assert hashlib.sha256(HELPER.read_bytes()).hexdigest() == HELPER_SHA
spec = importlib.util.spec_from_file_location('frozen_reception_helpers', HELPER)
H = importlib.util.module_from_spec(spec)
spec.loader.exec_module(H)  # No main(), no output or mutable input file.
p, box, tube, group, bounds, overlap = H.p, H.box, H.tube, H.group, H.bounds, H.overlap
ROOF_MATERIALS = []


def shader_math(nodes, links, operation, a, b=None):
    node = nodes.new('ShaderNodeMath'); node.operation = operation
    for index, value in enumerate([a, b]):
        if value is None:
            continue
        if isinstance(value, (int, float)):
            node.inputs[index].default_value = value
        else:
            links.new(value, node.inputs[index])
    return node.outputs[0]


def weather_material(name, clean, worn, rust, scale, threshold, rough=.74):
    """Meter-scale coating loss; broad patches and drain streaks, no fixed AO."""
    material = H.mat(name, clean, rough, .18)
    nodes, links = material.node_tree.nodes, material.node_tree.links
    geo = nodes.new('ShaderNodeNewGeometry')
    mapping = nodes.new('ShaderNodeVectorMath'); mapping.operation = 'MULTIPLY'
    mapping.inputs[1].default_value = (1.0, 1.0, .33)
    links.new(geo.outputs['Position'], mapping.inputs[0])
    noise = nodes.new('ShaderNodeTexNoise'); noise.inputs['Scale'].default_value = scale
    noise.inputs['Detail'].default_value = 1.5; noise.inputs['Roughness'].default_value = .55
    links.new(mapping.outputs['Vector'], noise.inputs['Vector'])
    ramp = nodes.new('ShaderNodeValToRGB'); ramp.color_ramp.interpolation = 'EASE'
    stops = [(0.0, clean), (threshold, clean), (threshold+.075, worn), (.80, rust)]
    cr = ramp.color_ramp
    cr.elements.remove(cr.elements[1]); cr.elements[0].position = stops[0][0]
    cr.elements[0].color = (*stops[0][1], 1)
    for at, color in stops[1:]:
        element = cr.elements.new(at); element.color = (*color, 1)
    links.new(noise.outputs['Fac'], ramp.inputs['Fac'])
    links.new(ramp.outputs['Color'], nodes['ClinicPrincipled'].inputs['Base Color'])
    # The texture is physical-meter based; no micro-noise or artificial normal map.
    material['source_only_weathering'] = 'Meter-space coating loss; no baked lighting/normal'
    return material


def paint_mask(material, kind):
    """Paint on the existing real surface, without raised collision decals."""
    nodes, links = material.node_tree.nodes, material.node_tree.links
    shader = nodes['ClinicPrincipled']; original = shader.inputs['Base Color'].links[0].from_socket
    geo = nodes.new('ShaderNodeNewGeometry'); xyz = nodes.new('ShaderNodeSeparateXYZ')
    links.new(geo.outputs['Position'], xyz.inputs[0])
    x, z = xyz.outputs['X'], xyz.outputs['Y']  # Blender Y is negative Godot Z.
    if kind == 'roof_cross':
        ax = shader_math(nodes, links, 'ABSOLUTE', shader_math(nodes, links, 'SUBTRACT', x, 3.35))
        az = shader_math(nodes, links, 'ABSOLUTE', shader_math(nodes, links, 'ADD', z, 1.95))
        vertical = shader_math(nodes, links, 'MULTIPLY', shader_math(nodes, links, 'LESS_THAN', ax, .18), shader_math(nodes, links, 'LESS_THAN', az, .65))
        horizontal = shader_math(nodes, links, 'MULTIPLY', shader_math(nodes, links, 'LESS_THAN', ax, .65), shader_math(nodes, links, 'LESS_THAN', az, .18))
        mask = shader_math(nodes, links, 'MAXIMUM', vertical, horizontal)
        color = (.06, .38, .18, 1)
    else:
        ax = shader_math(nodes, links, 'ABSOLUTE', x)
        stripe_distance = shader_math(nodes, links, 'ABSOLUTE', shader_math(nodes, links, 'SUBTRACT', ax, 1.48))
        mask = shader_math(nodes, links, 'LESS_THAN', stripe_distance, .055)
        color = (.11, .36, .25, 1)
    mixer = nodes.new('ShaderNodeMixRGB'); mixer.blend_type = 'MIX'
    links.new(mask, mixer.inputs[0]); links.new(original, mixer.inputs[1]); mixer.inputs[2].default_value = color
    links.new(mixer.outputs[0], shader.inputs['Base Color'])


def replace_material(obj, material):
    obj.data.materials.clear(); obj.data.materials.append(material)


def facade_text(name, text, location, max_width, height, material):
    data = bpy.data.curves.new(name+'_EditableText', 'FONT'); data.body = text
    data.font = bpy.data.fonts.load(str(FONT_PATH)); data.align_x = 'CENTER'; data.align_y = 'CENTER'
    data.size = height; data.extrude = 0; data.bevel_depth = 0
    obj = bpy.data.objects.new(name, data); bpy.context.scene.collection.objects.link(obj)
    obj.location = p(location); obj.rotation_euler = (math.pi/2, 0, 0)
    data.materials.append(material); bpy.context.view_layer.update()
    if obj.dimensions.x > max_width:
        factor = max_width / obj.dimensions.x; obj.scale *= factor
    # Mesh is independent and editable; original text/font provenance stays on it.
    bpy.ops.object.select_all(action='DESELECT'); obj.select_set(True)
    bpy.context.view_layer.objects.active = obj; bpy.ops.object.convert(target='MESH')
    obj = bpy.context.object; obj['original_text'] = text; obj['system_font_source'] = str(FONT_PATH)
    H.NEW.append(obj); return obj


def make_roof(name, x0, x1, z0, z1, steel, panel, gasket, is_canopy=False):
    """A complete waterproof roof: subdeck + seated panels + seams + edge drain."""
    start = len(H.NEW)
    box(name+'_Subdeck', (x0,3,z0), (x1,3.035,z1), gasket, 0)
    box(name+'_RimWest',(x0,3.035,z0),(x0+.12,3.29,z1),steel,.01)
    box(name+'_RimEast',(x1-.12,3.035,z0),(x1,3.29,z1),steel,.01)
    box(name+'_RimFront',(x0+.12,3.035,z1-.12),(x1-.12,3.29,z1),steel,.01)
    # Real recessed drain trough; it never opens through the roof skin.
    box(name+'_DrainBack',(x0+.12,3.035,z0+.015),(x1-.12,3.10,z0+.055),steel,.003)
    box(name+'_DrainLip',(x0+.12,3.035,z0+.22),(x1-.12,3.15,z0+.26),steel,.003)
    columns = 2 if is_canopy else 3
    inner_x0, inner_x1, inner_z0, inner_z1 = x0+.12,x1-.12,z0+.26,z1-.12
    cell_width = (inner_x1-inner_x0)/columns; split_z = (inner_z0+inner_z1)/2
    for index in range(columns):
        lo = inner_x0+index*cell_width; hi = inner_x0+(index+1)*cell_width
        for row,(za,zb) in enumerate([(inner_z0,split_z),(split_z,inner_z1)]):
            # Narrow recessed gaps expose the continuous weatherproof subdeck.
            piece = box(name+'_Panel_%s_%s'%(index,row),(lo+.018,3.035,za+.02),(hi-.018,3.25,zb-.02),panel,.012)
            piece['purpose'] = 'Removable roof sheet over continuous subdeck'
        if index:
            box(name+'_SeamBatten_%s'%index,(lo-.022,3.25,inner_z0),(lo+.022,3.285,inner_z1),steel,.004)
    box(name+'_CrossBatten',(inner_x0,3.25,split_z-.025),(inner_x1,3.282,split_z+.025),steel,.004)
    # Bounded fasteners at structural ends, not a carpet of tiny geometry.
    for x in [x0+.06,x1-.06]:
        for z in [z0+.08,z1-.08]:
            tube(name+'_Bolt',(x,3.29,z),(x,3.30,z),.032,gasket,8)
    return group(name,H.NEW[start:])


def descendant_meshes(obj):
    return [child for child in obj.children_recursive if child.type == 'MESH']


def eye_ray(scene, eye, target):
    origin = p(eye); direction = p(target)-origin
    hit, location, _normal, _index, obj, _matrix = scene.ray_cast(bpy.context.evaluated_depsgraph_get(), origin, direction.normalized(), distance=direction.length+.15)
    return {'eye':eye,'target':target,'hit':obj.name if hit else None,'desk_visible':bool(hit and obj.name.startswith('ReceptionDesk'))}


def main():
    assert hashlib.sha256(INPUT.read_bytes()).hexdigest() == INPUT_SHA, 'Frozen production input changed'
    assert FONT_PATH.is_file(), 'Required local sign font missing; no network fallback'
    bpy.ops.wm.open_mainfile(filepath=str(INPUT)); scene = bpy.context.scene
    remove = ('FrontSill','FrontHeader','DoorPocket','FrontWindow','WindowJamb','WindowSill','WindowHead','FacadeEdge','EastWall','EastWindow','ExteriorSalt','RearRoof','Canopy','ReceptionDesk','ReceptionMonitor','RearWall','WestWall')
    for obj in list(bpy.data.objects):
        if obj.name.startswith(remove): bpy.data.objects.remove(obj,do_unlink=True)

    steel = weather_material('V4_WeatheredTealFrame',(.09,.23,.25),(.24,.28,.27),(.27,.14,.07),3.1,.56)
    wall = weather_material('V4_ExteriorPanelWeather',(.56,.57,.52),(.41,.43,.39),(.29,.23,.16),1.5,.62,.87)
    roof = weather_material('V4_RoofWarmWeathered',(.51,.52,.48),(.34,.37,.35),(.28,.22,.15),1.1,.59,.84)
    awning = weather_material('V4_CanopyDarkMetal',(.24,.29,.29),(.18,.21,.20),(.27,.18,.10),1.6,.61,.80)
    gasket = H.mat('V4_GasketBareMetal',(.10,.14,.15),.68,.30)
    clean = H.mat('V4_CleanClinicLiner',(.66,.67,.60),.80)
    sign_white = H.mat('V4_ClinicSignWhite',(.76,.80,.73),.68)
    sign_green = H.mat('V4_ClinicSignGreen',(.06,.35,.19),.62)
    glass = H.mat('V4_SingleWindowPane',(.65,.75,.73),.19,0,.10)
    floor = weather_material('V4_WornServiceFloor',(.24,.29,.28),(.33,.35,.31),(.24,.20,.14),1.25,.61,.86)
    paint_mask(floor,'floor_route')
    marked_awning = awning.copy(); marked_awning.name = 'V4_CanopyMedicalPaint'
    paint_mask(marked_awning,'roof_cross')
    # Each roof group owns its fade materials; exterior walls/props never fade.
    for value in [steel,gasket,roof,awning,marked_awning]:
        copy = value.copy(); copy.name = value.name+'_RoofOnly'; ROOF_MATERIALS.append(copy)
    roof_steel,roof_gasket,roof_panel,roof_awning,roof_marked = ROOF_MATERIALS

    for obj in scene.objects:
        if obj.type != 'MESH':continue
        if obj.name.startswith(('FrontPost','DoorJamb','DoorHeader','DoorTrack','InteriorLampHousing')):replace_material(obj,steel)
        if obj.name == 'FrontDeck_existing_interface':replace_material(obj,floor)

    # One occupied corner volume. Front plane stops at X +/-4.8, side at Z=-.2.
    corners=[]
    for side,lo,hi in [('Left',-5,-4.8),('Right',4.8,5)]:
        corners.append(box('CornerPost'+side,(lo,0,-.2),(hi,3,0),steel,.01))
    for side,lo,hi,p0,p1,w0,w1 in [('Left',-4.8,-1.9,-3.55,-1.9,-4.52,-3.72),('Right',1.9,4.8,1.9,3.55,3.72,4.52)]:
        box('FrontSill'+side,(lo,0,-.2),(hi,.85,0),wall)
        box('FrontHeader'+side,(lo,2.6,-.2),(hi,3,0),steel)
        box('DoorPocketFace'+side,(p0,.85,-.16),(p1,2.6,0),wall)
        box('DoorPocketBack'+side,(p0,0,-.60),(p1,2.8,-.52),clean)
        box('FrontWindow'+side,(w0,.94,-.10),(w1,2.5,-.082),glass,0)
        for x in [w0-.08,w1]:box('WindowJamb'+side,(x,.85,-.2),(x+.08,2.6,0),steel,.008)
        box('WindowSill'+side,(w0-.08,.85,-.2),(w1+.08,.94,0),steel,.008)
        box('WindowHead'+side,(w0-.08,2.5,-.2),(w1+.08,2.6,0),steel,.008)
    for label,lo,hi in [('LeftOuter',-4.8,-4.60),('LeftPocketJoin',-3.64,-3.55),('RightPocketJoin',3.55,3.64),('RightOuter',4.60,4.8)]:
        box('FacadeEdge'+label,(lo,.85,-.2),(hi,2.6,0),steel,.008)

    # Rear and west panels have an inner clean liner and separately joined skin.
    box('RearInnerLiner',(-5,0,-3.88),(5,3,-3.8),clean,0)
    for index,(lo,hi) in enumerate([(-5,-2.5),(-2.5,0),(0,2.5),(2.5,5)]):
        box('RearWallModule%d'%index,(lo+.015,0,-4),(hi-.015,3,-3.88),wall,.008)
    box('WestInnerLiner',(-4.88,0,-3.8),(-4.8,3,-.2),clean,0)
    for index,(lo,hi) in enumerate([(-3.8,-2),(-2,-.2)]):
        box('WestWallModule%d'%index,(-5,0,lo+.015),(-4.88,3,hi-.015),wall,.008)

    # Window sections use disjoint volumes; front post ends at the corner plane.
    box('EastWallSill',(4.8,0,-3.8),(5,.9,-.2),wall)
    box('EastWallHeader',(4.8,2.65,-3.8),(5,3,-.2),steel)
    box('EastWindow',(4.88,1,-3.55),(4.898,2.55,-.48),glass,0)
    for label,za,zb in [('Rear',-3.8,-3.55),('Front',-.48,-.2)]:
        box('EastWindowPost'+label,(4.8,.9,za),(5,2.65,zb),steel,.008)
    box('EastWindowSill',(4.8,.9,-3.55),(5,1,-.48),steel,.008)
    box('EastWindowHead',(4.8,2.55,-3.55),(5,2.65,-.48),steel,.008)

    # Retained corner posts support fascia. Front soffit never drops below Y3.
    left=make_roof('RearRoofLeft',-5,0,-4,0,roof_steel,roof_panel,roof_gasket)
    right=make_roof('RearRoofRight',0,5,-4,0,roof_steel,roof_panel,roof_gasket)
    group('RearRoof',[left,right])
    make_roof('CanopyLeft',-5,-1.7,0,4,roof_steel,roof_awning,roof_gasket,True)
    make_roof('CanopyRight',1.7,5,0,4,roof_steel,roof_marked,roof_gasket,True)
    # Rear drain pipes stay against the rear wall, within the approved volume.
    for x in [-4.72,4.72]:
        tube('RearDrainPipe',(x,.18,-3.70),(x,2.96,-3.70),.045,gasket)
        tube('RearDrainOutlet',(x,.18,-3.70),(x,.18,-3.57),.045,gasket)
    # Front foot/cap plates stay outside the clear corridor Z<=3.5.
    for side,x0,x1 in [('Left',-5,-4.68),('Right',4.68,5)]:
        box('FrontPostFoot'+side,(x0,0,3.64),(x1,.12,4),steel,.012)
        box('FrontPostCollar'+side,(x0,2.74,3.64),(x1,3,4),steel,.012)

    # The counter is now on the actual open-door axis, beyond the entry turning bay.
    start=len(H.NEW)
    box('ReceptionDeskBody',(-1.25,0,-3.65),(1.25,.87,-2.69),clean,.04)
    box('ReceptionDeskFront',(-1.20,.12,-2.69),(1.20,.80,-2.65),sign_green,.025)
    box('ReceptionDeskTop',(-1.34,.87,-3.70),(1.34,1.01,-2.60),clean,.05)
    box('ReceptionDeskMonitorFoot',(-.70,1.01,-3.30),(-.40,1.04,-3.10),gasket)
    tube('ReceptionDeskMonitorStem',(-.55,1.04,-3.20),(-.55,1.24,-3.20),.025,gasket)
    box('ReceptionDeskMonitor',(-.82,1.17,-3.24),(-.28,1.48,-3.18),sign_green,.015)
    group('ReceptionDeskGroup',H.NEW[start:],(0,0,-3.15))
    # Move only the existing desk fixture/light; do not brighten the entire world.
    for name in ['InteriorLampHousingDesk','InteriorLampDiffuserDesk','InteriorLampCeilingMountDesk','InteriorAreaDesk']:
        obj=bpy.data.objects.get(name)
        if obj:obj.location += p((3.3,0,-.65))

    # Exterior identity is readable without opening/fading the roof.
    start=len(H.NEW)
    box('ReceptionSignBack',(2.03,1.18,.012),(3.43,2.48,.042),sign_white,.025)
    box('ReceptionSignCrossV',(2.60,1.80,.043),(2.86,2.35,.057),sign_green,.004)
    # Three disjoint bars form the cross: no coincident front faces at its centre.
    box('ReceptionSignCrossLeft',(2.455,1.945,.043),(2.60,2.205,.057),sign_green,.004)
    box('ReceptionSignCrossRight',(2.86,1.945,.043),(3.005,2.205,.057),sign_green,.004)
    facade_text('ReceptionChineseLabel','接诊',(2.73,1.50,.058),1.12,.38,sign_green)
    group('ReceptionSign',H.NEW[start:])

    bpy.context.view_layer.update()
    meshes=[obj for obj in scene.objects if obj.type=='MESH']; rows=[bounds(obj) for obj in meshes]
    contacts={name:min(bounds(obj)['min'][1] for obj in descendant_meshes(bpy.data.objects[name])) for name in ['Stretcher','TreatmentBedGroup','ReceptionDeskGroup']}
    rays=[eye_ray(scene,eye,target) for eye,target in [([0,1.65,1.2],[0,.65,-2.64]),([.75,1.65,1.2],[.55,.65,-2.64]),([-.75,1.65,1.2],[-.55,.65,-2.64])]]
    corners_to_check=['CornerPostRight','CornerPostLeft']
    adjoining=[row for row in rows if row['name'].startswith(('FrontSill','FrontHeader','FacadeEdge','EastWindow','EastWall','WestWall','WestInner'))]
    corner_overlaps=[]
    for name in corners_to_check:
        corner=bounds(bpy.data.objects[name])
        corner_overlaps.extend([{'corner':name,'other':row['name']} for row in adjoining if overlap(row,corner['min'],corner['max'])])
    checks={
        'front_3m_corridor_clear':not any(overlap(row,[-5,0,.5],[5,3,3.5]) for row in rows),
        'door_3_4m_by_2_8m_clear':not any(overlap(row,[-1.7,0,-.33],[1.7,2.8,.5]) for row in rows),
        'entry_turning_bay_clear':not any(overlap(row,[-1.65,0,-2.5],[1.65,2.75,-.61]) for row in rows),
        'unchanged_bounds':all(row['min'][0]>=-5-EPS and row['max'][0]<=5+EPS and row['min'][1]>=-.4-EPS and row['max'][1]<=3.3+EPS and row['min'][2]>=-4-EPS and row['max'][2]<=4+EPS for row in rows),
        'actual_furniture_ground_contact':all(abs(value)<EPS for value in contacts.values()),
        'actual_front_side_corner_volumes_disjoint':not corner_overlaps,
        'normal_roof_front_door_three_counter_rays':all(ray['desk_visible'] for ray in rays),
        'independent_groups_present':all(name in bpy.data.objects for name in ['DoorLeft','DoorRight','RearRoof','CanopyLeft','CanopyRight','ReceptionLight','Stretcher','TreatmentBedGroup','ReceptionDeskGroup']),
    }
    report={'status':'source_revision_v4_not_runtime_or_final_art','input_sha256':INPUT_SHA,'helper_sha256':HELPER_SHA,'root_world':[7,5,-6],'checks':checks,'corner_overlap_candidates':corner_overlaps,'counter_front_eye_rays':rays,'mesh_count':len(meshes),'actual_mesh_bounds':rows,'furniture_contact_y':contacts,'render_note':'Default direction is offline source view. Entry-eye view if requested is diagnostic; neither is a game screenshot.','unimplemented':['GLB/PBR baking','game collision and occlusion','rear-room lower support','door/furniture behavior','human gameplay verification']}
    (OUT/'reception_v4_geometry.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    assert all(checks.values()),checks
    scene.camera.data.ortho_scale=22
    scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=16
    scene.render.threads_mode='FIXED';scene.render.threads=2
    scene.render.resolution_x=1280;scene.render.resolution_y=720;scene.render.resolution_percentage=100
    scene.render.filepath=str(OUT/'reception_v4_normal.png')
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'clinic_reception_v4.blend'))
    if '--render' in sys.argv or '--render-pair' in sys.argv:bpy.ops.render.render(write_still=True)
    if '--render-pair' in sys.argv:
        for value in ROOF_MATERIALS:value.node_tree.nodes['ClinicPrincipled'].inputs['Alpha'].default_value=.16
        scene.render.filepath=str(OUT/'reception_v4_roof_fade.png');bpy.ops.render.render(write_still=True)
        for value in ROOF_MATERIALS:value.node_tree.nodes['ClinicPrincipled'].inputs['Alpha'].default_value=1
    if '--entry-view' in sys.argv:
        camera=scene.camera; camera.data.type='PERSP';camera.data.lens=24;camera.location=p((0,1.65,3.8))
        direction=p((0,1.15,-2))-camera.location;camera.rotation_euler=direction.to_track_quat('-Z','Y').to_euler()
        scene.render.filepath=str(OUT/'reception_v4_entry_diagnostic.png');bpy.ops.render.render(write_still=True)


if __name__=='__main__':main()
