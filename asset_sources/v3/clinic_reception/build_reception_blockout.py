"""Clinic reception dimensional blockout; source only, NOT executed/approved.

Run only after root grants a Blender CPU window:
  blender.exe --background --threads 2 --python build_reception_blockout.py
Add -- --render for one normal view, or -- --render-pair for normal/fade studies,
only when a preview render is authorized. Outputs stay beside
this script. Blender 5.2 standard bpy/mathutils only; no download/install/export.
Godot root is (7,5,-6); local Godot (x,y,z) -> Blender (x,-z,y).
This controls the geometry that imagegen could not prove from two references.
The clinical interior/roofs remain individual editable objects, not final art.
"""
from pathlib import Path
import json
import sys
import bpy
from mathutils import Vector

OUT = Path(__file__).resolve().parent
ROOT_WORLD = (7.0, 5.0, -6.0)
BOXES = []


def point(g):
    return (g[0], -g[2], g[1])


def material(name, rgb, alpha=1.0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*rgb, alpha)
    mat.use_nodes = True
    mat.node_tree.nodes.clear()
    shader = mat.node_tree.nodes.new('ShaderNodeBsdfPrincipled')
    shader.name = 'ClinicPrincipled'
    output = mat.node_tree.nodes.new('ShaderNodeOutputMaterial')
    mat.node_tree.links.new(shader.outputs['BSDF'],output.inputs['Surface'])
    shader.inputs['Base Color'].default_value = (*rgb, 1.0)
    shader.inputs['Roughness'].default_value = .7 if alpha == 1 else .18
    shader.inputs['Alpha'].default_value = alpha
    return mat


def block(name, lower, upper, mat, role='structure'):
    assert all(b > a for a, b in zip(lower, upper)), name
    size = tuple(b-a for a, b in zip(lower, upper))
    centre = tuple((a+b)*.5 for a, b in zip(lower, upper))
    bpy.ops.mesh.primitive_cube_add(size=1, location=point(centre))
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    obj['purpose'] = role
    obj['source'] = 'Authored exact dimensional blockout; not image-derived mesh'
    BOXES.append({'name':obj.name, 'min':list(lower), 'max':list(upper), 'role':role})
    return obj


def overlap_volume(a, b, epsilon=1e-8):
    return all(min(a['max'][i], b['max'][i])-max(a['min'][i], b['min'][i]) > epsilon for i in range(3))


def aim(obj, at):
    obj.rotation_euler = (Vector(point(at))-obj.location).to_track_quat('-Z','Y').to_euler()


def area_light(name, location, aim_at, energy, size, color):
    bpy.ops.object.light_add(type='AREA',location=point(location))
    obj=bpy.context.object;obj.name=name;obj.data.energy=energy
    obj.data.shape='DISK';obj.data.size=size;obj.data.color=color
    aim(obj,aim_at)
    return obj


def actual_bounds(obj):
    points = [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]
    godot = [(v.x,v.z,-v.y) for v in points]
    return {'name':obj.name,'min':[min(p[i] for p in godot) for i in range(3)],
            'max':[max(p[i] for p in godot) for i in range(3)]}


def main():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    scene = bpy.context.scene
    scene.unit_settings.system = 'METRIC'
    scene.unit_settings.scale_length = 1.0
    steel = material('Blockout_TealSteel', (.12,.27,.29))
    wall = material('Blockout_CleanWarmGray', (.64,.65,.61))
    floor = material('Blockout_DarkFloor', (.24,.29,.29))
    glass = material('Blockout_WindowPlaceholder', (.54,.69,.70),.20)
    bed = material('Blockout_ClinicalFabric', (.62,.71,.68))
    lamp = material('Blockout_ServiceLamp', (.82,.69,.42))
    diffuser = material('Blockout_InteriorWarmWhite', (.82,.79,.68))
    lit=diffuser.node_tree.nodes['ClinicPrincipled']
    lit.inputs['Emission Color'].default_value=(1.0,.87,.66,1.0)
    lit.inputs['Emission Strength'].default_value=2.5
    # Existing forward deck + PROPOSED rear deck; support below is root's task.
    block('FrontDeck_existing_interface', (-5,-.4,0), (5,0,4),floor,'bearing_surface')
    block('RearDeck_PROPOSED_not_integrated', (-5,-.4,-4),(5,0,0),floor,'new_bearing_candidate')
    block('RearWall',(-5,0,-4),(5,3,-3.8),wall)
    block('WestWall',(-5,0,-3.8),(-4.8,3,0),wall)
    # East observation window is a separate editable panel, not a collider claim.
    block('EastWallSill',(4.8,0,-3.8),(5,.9,0),wall)
    block('EastWallHeader',(4.8,2.65,-3.8),(5,3,0),wall)
    block('EastWindow',(4.85,.9,-3.65),(4.95,2.65,-.25),glass,'window_placeholder')
    for side, lo, hi in [('Left',-5,-1.7),('Right',1.7,5)]:
        block('FacadeSill'+side,(lo,0,-.2),(hi,.85,0),wall)
        block('FacadeWindow'+side,(lo,.85,-.15),(hi,2.6,-.05),glass,'window_placeholder')
        block('FacadeHeader'+side,(lo,2.6,-.2),(hi,3,0),steel)
    # Door frame is outside the opening x[-1.7,1.7], y[0,2.8].
    block('DoorJambLeft',(-1.9,0,-.3),(-1.7,2.8,0),steel)
    block('DoorJambRight',(1.7,0,-.3),(1.9,2.8,0),steel)
    block('DoorHeader',(-1.9,2.8,-.3),(1.9,3,0),steel)
    # OPEN leaves park beside opening; root must add/test actual actuation later.
    block('DoorLeft_OPEN',(-3.4,0,-.32),(-1.7,2.78,-.24),glass,'proposed_moving_leaf')
    block('DoorRight_OPEN',(1.7,0,-.32),(3.4,2.78,-.24),glass,'proposed_moving_leaf')
    roof_material=wall.copy();roof_material.name='Blockout_RearRoof_IndependentFade'
    canopy_material=steel.copy();canopy_material.name='Blockout_Canopy_IndependentFade'
    block('RearRoofLeft',(-5,3,-4),(0,3.3,0),roof_material,'occlusion_split_roof')
    block('RearRoofRight',(0,3,-4),(5,3.3,0),roof_material,'occlusion_split_roof')
    # Three metres of headroom everywhere in the front passage. No beam in gap.
    block('CanopyLeft',(-5,3,0),(-1.7,3.3,4),canopy_material,'occlusion_split_roof')
    block('CanopyRight',(1.7,3,0),(5,3.3,4),canopy_material,'occlusion_split_roof')
    block('FrontPostLeft',(-5,0,3.7),(-4.75,3,4),steel)
    block('FrontPostRight',(4.75,0,3.7),(5,3,4),steel)
    block('ReceptionDesk',(-4.3,0,-2.8),(-2.8,.95,-1.5),wall,'interior_prop')
    block('ReceptionDeskTop',(-4.35,.95,-2.85),(-2.75,1.03,-1.45),floor,'interior_prop')
    block('StretcherFrame',(2.8,.45,-3.3),(3.6,.65,-1.1),steel,'interior_prop')
    block('StretcherMattress',(2.8,.65,-3.3),(3.6,.8,-1.1),bed,'interior_prop')
    block('StretcherPillow',(2.9,.8,-3.18),(3.5,.9,-2.85),wall,'interior_prop')
    for x in [2.8,3.57]:
        block('StretcherSafetyRail',(x,.9,-2.9),(x+.03,.94,-1.4),steel,'interior_prop')
        for z in [-2.85,-1.45]:
            block('StretcherRailLeg',(x,.65,z),(x+.03,.9,z+.03),steel,'interior_prop')
    for x in [2.9,3.5]:
        for z in [-3.1,-1.3]:
            block('StretcherWheel', (x-.07,0,z-.09),(x+.07,.45,z+.09),steel,'interior_prop')
    block('TreatmentBed',(3.95,.45,-3.3),(4.65,.8,-1.2),bed,'interior_prop')
    block('TreatmentBedPillow',(4.02,.8,-3.2),(4.58,.9,-2.85),wall,'interior_prop')
    for x in [4.02,4.58]:
        for z in [-3.2,-1.3]:
            block('TreatmentBedLeg',(x-.04,0,z-.04),(x+.04,.45,z+.04),steel,'interior_prop')
    block('ReceptionLight',(-.4,2.83,.01),(.4,2.96,.08),lamp,'future_committed_state_visual')
    # Real authored fixture geometry plus local lights, no global exposure lift.
    for label, x in [('Desk',-3.3),('Beds',3.2)]:
        block('InteriorLampHousing'+label,(x-.85,2.86,-2.25),(x+.85,2.98,-1.95),steel,'interior_light_housing')
        block('InteriorLampDiffuser'+label,(x-.75,2.845,-2.21),(x+.75,2.86,-1.99),diffuser,'interior_light_diffuser')
        area_light('InteriorArea'+label,(x,2.82,-2.1),(x,.4,-2.1),85,1.5,(1.0,.87,.70))
    # Furniture remains independently movable; explicit feet/wheels touch Y0.
    for group, prefixes, pivot in [
        ('RearRoof',['RearRoof'],(0,3,-2)),
        ('Stretcher',['Stretcher'],(3.2,0,-2.2)),
        ('TreatmentBedGroup',['TreatmentBed'],(4.3,0,-2.25)),
        ('ReceptionDeskGroup',['ReceptionDesk'],(-3.55,0,-2.15)),
    ]:
        members=[obj for obj in list(scene.objects) if obj.type=='MESH' and any(obj.name.startswith(prefix) for prefix in prefixes)]
        parent=bpy.data.objects.new(group,None);scene.collection.objects.link(parent);parent.location=point(pivot)
        bpy.context.view_layer.update()
        for obj in members:
            transform=obj.matrix_world.copy();obj.parent=parent;obj.matrix_world=transform
        bpy.context.view_layer.update()
    # Empty anchors only: never added as rendered props/collision.
    for name, loc in [('Root_world_7_5_minus6',(0,0,0)),('CheckPoint',(0,.8,3)),('DoorOpening',(0,1.4,0)),('WestJoin',(-5,0,2)),('EastExit',(5,0,2))]:
        obj=bpy.data.objects.new(name,None);scene.collection.objects.link(obj);obj.location=point(loc)
    clear={'min':[-5,0,.5],'max':[5,3,3.5]}
    doorway={'min':[-1.7,0,-.33],'max':[1.7,2.8,.5]}
    checks={
        'front_clear_3m_width_3m_height':not any(overlap_volume(b,clear) for b in BOXES),
        'door_clear_3_4_by_2_8m':not any(overlap_volume(b,doorway) for b in BOXES),
        'body_envelope_10_by_8_by_3_3m':all(b['min'][0]>=-5 and b['max'][0]<=5 and b['min'][2]>=-4 and b['max'][2]<=4 and b['min'][1]>=-.4 and b['max'][1]<=3.3 for b in BOXES),
    }
    assert all(checks.values()),checks
    bpy.context.view_layer.update()
    meshes = [obj for obj in scene.objects if obj.type=='MESH']
    actual = [actual_bounds(obj) for obj in meshes]
    # Float32 Blender coordinates need sub-micron comparison tolerance here;
    # this is numerical readback, not an enlarged collision clearance.
    input_by_name={row['name']:row for row in BOXES}
    checks['actual_vertices_match_authored_boxes'] = all(max(abs(row[key][i]-input_by_name[row['name']][key][i]) for key in ['min','max'] for i in range(3)) < 1e-6 for row in actual)
    checks['actual_door_and_corridor_clear'] = not any(overlap_volume(row,clear,1e-6) or overlap_volume(row,doorway,1e-6) for row in actual)
    contacts={}
    for group in ['Stretcher','TreatmentBedGroup','ReceptionDeskGroup']:
        rows=[actual_bounds(obj) for obj in bpy.data.objects[group].children if obj.type=='MESH']
        contacts[group]=min(row['min'][1] for row in rows)
    checks['actual_furniture_feet_touch_floor'] = all(abs(y)<1e-6 for y in contacts.values())
    assert all(checks.values()),checks
    report={'status':'dimensional_source_only_not_engine_collision_or_art_approval','root_world':ROOT_WORLD,'checks':checks,'boxes':BOXES,'actual_mesh_bounds':actual,'furniture_contact_y_local':contacts,'preview':{'camera_offset':[19,23.15,19],'orthographic_scale':20,'resolution':[1280,720],'local_interior_lights':[{'energy_watts':85,'count':2,'color':[1,.87,.70]}],'roof_fade_study_alpha':.16,'render_mode':'CPU2'},'unimplemented':['rear support integration','body sweeps','door state and collision','UV/PBR','actual game camera acceptance']}
    (OUT/'blockout_dimensions.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    bpy.ops.object.camera_add(location=point((19,23.15,19)))
    camera=bpy.context.object;camera.name='DefaultDirectionCamera';camera.data.type='ORTHO';camera.data.ortho_scale=20
    aim(camera,(0,1.3,0));scene.camera=camera
    bpy.ops.object.light_add(type='AREA',location=point((3,12,6)))
    light=bpy.context.object;light.data.energy=1800;light.data.shape='DISK';light.data.size=9;aim(light,(0,1,0))
    scene.world.color=(.28,.28,.28)
    scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=12
    scene.render.threads_mode='FIXED';scene.render.threads=2
    scene.render.resolution_x=1280;scene.render.resolution_y=720;scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG'
    scene.render.filepath=str(OUT/'reception_dimension_blockout.png')
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'reception_dimension_blockout.blend'))
    if '--render' in sys.argv or '--render-pair' in sys.argv:
        bpy.ops.render.render(write_still=True)
    if '--render-pair' in sys.argv:
        # Diagnostic controlled roof fade, visibly different from the normal
        # view. This is not a claim that a production occlusion controller exists.
        for mat in [roof_material,canopy_material]:
            mat.node_tree.nodes['ClinicPrincipled'].inputs['Alpha'].default_value=.16
        scene.render.filepath=str(OUT/'reception_roof_fade_study.png')
        bpy.ops.render.render(write_still=True)
        for mat in [roof_material,canopy_material]:
            mat.node_tree.nodes['ClinicPrincipled'].inputs['Alpha'].default_value=1.0


if __name__ == '__main__':
    main()
