"""Reception production-shape preparation; NOT EXECUTED.

Requires Blender 5.2, stdlib/bpy/mathutils only. No download, imagegen or GLB.
Run only in a root-approved CPU2 window, with --python-exit-code 2.
  blender.exe -b -t 2 --python-exit-code 2 --python this_file.py -- --render-pair
Frozen R2 blend is the exact geometric input. Output never leaves this folder.
Godot local (x,y,z) -> Blender (x,-z,y); future world root remains (7,5,-6).
Materials are source/basic candidates, not baked or accepted production PBR.
"""
from pathlib import Path
import hashlib
import json
import math
import sys
import bpy
from mathutils import Vector

OUT=Path(__file__).resolve().parent
INPUT=OUT.parent/'evidence/form_r2/reception_dimension_blockout.blend'
INPUT_SHA='9d8aa1f736c5cc6e0edd8371c0ea573492a0e9ce0bd52e94b40cf9e905fa7c87'
NEW=[]
ROOFS=[]


def p(v): return Vector((v[0],-v[2],v[1]))


def mat(name,color,roughness=.65,metallic=0,alpha=1):
    value=bpy.data.materials.new(name);value.diffuse_color=(*color,alpha)
    value.use_nodes=True;value.node_tree.nodes.clear()
    shader=value.node_tree.nodes.new('ShaderNodeBsdfPrincipled');shader.name='ClinicPrincipled'
    end=value.node_tree.nodes.new('ShaderNodeOutputMaterial')
    value.node_tree.links.new(shader.outputs['BSDF'],end.inputs['Surface'])
    shader.inputs['Base Color'].default_value=(*color,1)
    shader.inputs['Roughness'].default_value=roughness
    shader.inputs['Metallic'].default_value=metallic
    shader.inputs['Alpha'].default_value=alpha
    return value


def box(name,lo,hi,material,bevel=.012):
    assert all(hi[i]>lo[i] for i in range(3)),name
    size=[hi[i]-lo[i] for i in range(3)]
    bpy.ops.mesh.primitive_cube_add(size=1,location=p([(lo[i]+hi[i])/2 for i in range(3)]))
    obj=bpy.context.object;obj.name=name;obj.dimensions=(size[0],size[2],size[1])
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if bevel:
        modifier=obj.modifiers.new('ManufacturedEdge','BEVEL')
        modifier.width=min(bevel,min(size)*.3);modifier.segments=2
        bpy.context.view_layer.objects.active=obj;bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.data.materials.append(material);NEW.append(obj)
    return obj


def tube(name,a,b,radius,material,vertices=12):
    start=p(a);end=p(b);axis=end-start
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=radius,depth=axis.length,location=(start+end)/2)
    obj=bpy.context.object;obj.name=name
    obj.rotation_euler=axis.to_track_quat('Z','Y').to_euler()
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    obj.data.materials.append(material);NEW.append(obj)
    return obj


def group(name,members,pivot=(0,0,0)):
    obj=bpy.data.objects.new(name,None);bpy.context.scene.collection.objects.link(obj);obj.location=p(pivot)
    bpy.context.view_layer.update()
    for child in members:
        transform=child.matrix_world.copy();child.parent=obj;child.matrix_world=transform
    bpy.context.view_layer.update()
    return obj


def bounds(obj):
    pts=[obj.matrix_world@v.co for v in obj.data.vertices]
    pts=[(v.x,v.z,-v.y) for v in pts]
    return {'name':obj.name,'min':[min(v[i] for v in pts) for i in range(3)],'max':[max(v[i] for v in pts) for i in range(3)]}


def overlap(row,lo,hi):
    return all(min(row['max'][i],hi[i])-max(row['min'][i],lo[i])>1e-6 for i in range(3))


def roof(name,xlo,xhi,zlo,zhi,steel,panel):
    # Adjacent actual panels/frame, not coincident colored plates on a box.
    parts=[box(name+'_WestFrame',(xlo,3,zlo),(xlo+.12,3.3,zhi),steel),
           box(name+'_EastFrame',(xhi-.12,3,zlo),(xhi,3.3,zhi),steel),
           box(name+'_FrontFrame',(xlo+.12,3,zhi-.12),(xhi-.12,3.3,zhi),steel),
           box(name+'_RearFrame',(xlo+.12,3,zlo),(xhi-.12,3.3,zlo+.12),steel),
           box(name+'_Infill',(xlo+.12,3.04,zlo+.12),(xhi-.12,3.28,zhi-.12),panel)]
    obj=group(name,parts);ROOFS.extend(parts);return obj


def main():
    assert hashlib.sha256(INPUT.read_bytes()).hexdigest()==INPUT_SHA,'Frozen R2 input changed'
    bpy.ops.wm.open_mainfile(filepath=str(INPUT))
    scene=bpy.context.scene
    # R2's façade panels intersected the jamb/header in visible boundary planes.
    # Replace this bounded part rather than darkening it with material patches.
    prefixes=('Facade','Door','EastWindow','EastWallSill','EastWallHeader','Stretcher','TreatmentBed','ReceptionDesk','RearRoof','Canopy')
    for obj in list(bpy.data.objects):
        if obj.name.startswith(prefixes) and obj.name!='DoorOpening': bpy.data.objects.remove(obj,do_unlink=True)
    teal=mat('Candidate_TealPaint',(.105,.245,.265),.58,.18)
    warm=mat('Candidate_CleanWarmGray',(.64,.65,.59),.76)
    dark=mat('Candidate_DarkSteel',(.16,.20,.205),.45,.5)
    glass=mat('Candidate_Window',(.60,.73,.73),.16,0,.14)
    fabric=mat('Candidate_ClinicalFabric',(.64,.72,.68),.88)
    rubber=mat('Candidate_Rubber',(.055,.065,.065),.82)
    salt=mat('Candidate_ExteriorSeamSalt',(.43,.45,.40),.94)
    roof_steel=teal.copy();roof_steel.name='Candidate_RoofSteel_IndependentFade'
    roof_panel=warm.copy();roof_panel.name='Candidate_RoofPanel_IndependentFade'
    for obj in scene.objects:
        if obj.type!='MESH':continue
        if obj.name in ['RearWall','WestWall']:obj.data.materials.clear();obj.data.materials.append(warm)
        elif obj.name.startswith(('FrontPost','InteriorLampHousing')):obj.data.materials.clear();obj.data.materials.append(teal)

    # Glass never coincides with the jambs, and parked leaves have their own slot.
    for side,lo,hi,pocket_lo,pocket_hi,window_lo,window_hi in [
        ('Left',-5,-1.9,-3.55,-1.9,-4.78,-3.72),
        ('Right',1.9,5,1.9,3.55,3.72,4.78)]:
        box('FrontSill'+side,(lo,0,-.2),(hi,.85,0),warm)
        box('FrontHeader'+side,(lo,2.6,-.2),(hi,3,0),teal)
        box('DoorPocketFace'+side,(pocket_lo,.85,-.16),(pocket_hi,2.6,0),warm)
        box('DoorPocketBack'+side,(pocket_lo,0,-.60),(pocket_hi,2.8,-.52),warm)
        box('FrontWindow'+side,(window_lo,.94,-.10),(window_hi,2.5,-.082),glass,0)
        for x in [window_lo-.08,window_hi]:
            box('WindowJamb'+side,(x,.85,-.2),(x+.08,2.6,0),teal,.008)
        box('WindowSill'+side,(window_lo-.08,.85,-.2),(window_hi+.08,.94,0),teal,.008)
        box('WindowHead'+side,(window_lo-.08,2.5,-.2),(window_hi+.08,2.6,0),teal,.008)
    for label,lo,hi in [('LeftOuter',-5,-4.86),('LeftPocketJoin',-3.64,-3.55),('RightPocketJoin',3.55,3.64),('RightOuter',4.86,5)]:
        box('FacadeEdge'+label,(lo,.85,-.2),(hi,2.6,0),teal,.008)
    # Jambs and side façade stop at shared boundaries, no duplicate exterior face.
    box('DoorJambLeft',(-1.9,0,-.30),(-1.7,2.8,0),teal)
    box('DoorJambRight',(1.7,0,-.30),(1.9,2.8,0),teal)
    box('DoorHeader',(-1.9,2.8,-.30),(1.9,3,0),teal)
    box('DoorTrack',(-3.55,2.86,-.48),(3.55,2.96,-.35),dark,.008)
    for side,lo,hi in [('Left',-3.4,-1.7),('Right',1.7,3.4)]:
        parts=[box('Door'+side+'Bottom',(lo,0,-.46),(hi,.8,-.40),warm),
               box('Door'+side+'Glass',(lo+.07,.8,-.448),(hi-.07,2.68,-.430),glass,0),
               box('Door'+side+'Top',(lo,2.68,-.46),(hi,2.78,-.40),teal),
               box('Door'+side+'EdgeL',(lo,.8,-.46),(lo+.07,2.68,-.40),teal,.004),
               box('Door'+side+'EdgeR',(hi-.07,.8,-.46),(hi,2.68,-.40),teal,.004)]
        leaf=group('Door'+side,parts,((lo+hi)/2,0,-.43))
        leaf['state']='open geometry only; future close translation is +1.7m for Left / -1.7m for Right'
    # Side observation window retains clinic visibility without a glass cuboid.
    box('EastWallSill',(4.8,0,-3.8),(5,.9,0),warm)
    box('EastWallHeader',(4.8,2.65,-3.8),(5,3,0),teal)
    box('EastWindow',(4.88,1.0,-3.55),(4.898,2.55,-.25),glass,0)
    for z in [-3.65,-.25]:box('EastWindowPost',(4.8,.9,z),(5,2.65,z+.1),teal,.008)
    box('EastWindowSill',(4.8,.9,-3.65),(5,1,-.15),teal,.008)
    box('EastWindowHead',(4.8,2.55,-3.65),(5,2.65,-.15),teal,.008)
    # Exterior wear is placed at a few actual low joints; no full-body noise.
    box('ExteriorSaltJointEast',(4.995,.06,-3.6),(5,.11,-.25),salt,0)
    for side,lo,hi in [('Left',-4.7,-3.8),('Right',3.8,4.7)]:
        box('ExteriorSaltJoint'+side,(lo,.07,.001),(hi,.12,.006),salt,0)
    rear_l=roof('RearRoofLeft',-5,0,-4,0,roof_steel,roof_panel)
    rear_r=roof('RearRoofRight',0,5,-4,0,roof_steel,roof_panel)
    group('RearRoof',[rear_l,rear_r])
    roof('CanopyLeft',-5,-1.7,0,4,roof_steel,roof_panel)
    roof('CanopyRight',1.7,5,0,4,roof_steel,roof_panel)
    for label,x in [('Desk',-3.3),('Beds',3.2)]:
        box('InteriorLampCeilingMount'+label,(x-.04,2.98,-2.15),(x+.04,3.04,-2.05),dark,.004)

    # Furniture is authored as objects with feet/wheels, not fused building relief.
    start=len(NEW)
    for x in [2.84,3.56]:tube('StretcherLongFrame',(x,.56,-3.25),(x,.56,-1.15),.028,dark)
    for z in [-3.25,-1.15]:tube('StretcherCrossFrame',(2.84,.56,z),(3.56,.56,z),.028,dark)
    for x in [2.9,3.5]:
        for z in [-3.1,-1.3]:
            tube('StretcherCasterLeg',(x,.24,z),(x,.56,z),.025,dark)
            tube('StretcherWheel',(x-.05,.12,z),(x+.05,.12,z),.12,rubber,16)
    box('StretcherMattress',(2.81,.59,-3.28),(3.59,.77,-1.12),fabric,.055)
    box('StretcherPillow',(2.9,.77,-3.17),(3.5,.88,-2.83),warm,.045)
    for x in [2.81,3.59]:
        tube('StretcherSafetyRail',(x,.94,-2.85),(x,.94,-1.45),.02,teal)
        for z in [-2.85,-1.45]:tube('StretcherRailSupport',(x,.57,z),(x,.94,z),.018,teal)
    group('Stretcher',NEW[start:],(3.2,0,-2.2))
    start=len(NEW)
    box('TreatmentBedFrame',(3.98,.48,-3.28),(4.62,.58,-1.22),dark)
    box('TreatmentBedMattress',(3.95,.58,-3.3),(4.65,.79,-1.2),fabric,.06)
    box('TreatmentBedPillow',(4.03,.79,-3.19),(4.57,.90,-2.84),warm,.045)
    for x in [4.04,4.56]:
        for z in [-3.15,-1.35]:tube('TreatmentBedFoot',(x,0,z),(x,.48,z),.035,dark)
    group('TreatmentBedGroup',NEW[start:],(4.3,0,-2.25))
    start=len(NEW)
    box('ReceptionDeskBody',(-4.15,0,-1.85),(-2.65,.89,-.78),warm,.035)
    box('ReceptionDeskFront',(-4.13,.12,-.775),(-2.67,.82,-.75),teal,.015)
    box('ReceptionDeskTop',(-4.25,.89,-1.95),(-2.55,1.01,-.68),warm,.045)
    box('ReceptionMonitorFoot',(-3.62,1.01,-1.55),(-3.38,1.04,-1.35),dark)
    tube('ReceptionMonitorStem',(-3.5,1.04,-1.45),(-3.5,1.20,-1.45),.025,dark)
    box('ReceptionMonitor',(-3.75,1.14,-1.49),(-3.25,1.43,-1.44),teal,.015)
    group('ReceptionDeskGroup',NEW[start:],(-3.4,0,-1.3))

    bpy.context.view_layer.update()
    meshes=[obj for obj in scene.objects if obj.type=='MESH']
    rows=[bounds(obj) for obj in meshes]
    contacts={name:min(bounds(child)['min'][1] for child in bpy.data.objects[name].children if child.type=='MESH') for name in ['Stretcher','TreatmentBedGroup','ReceptionDeskGroup']}
    checks={
        'front_3m_path_clear':not any(overlap(row,[-5,0,.5],[5,3,3.5]) for row in rows),
        'door_3_4_by_2_8_clear':not any(overlap(row,[-1.7,0,-.33],[1.7,2.8,.5]) for row in rows),
        'unchanged_envelope':all(row['min'][0]>=-5.000001 and row['max'][0]<=5.000001 and row['min'][2]>=-4.000001 and row['max'][2]<=4.000001 and row['min'][1]>=-.400001 and row['max'][1]<=3.300001 for row in rows),
        'furniture_ground_contact':all(abs(y)<1e-6 for y in contacts.values()),
    }
    assert all(checks.values()),checks
    scene.camera.data.ortho_scale=22 # R2 top corner had only a few pixels margin.
    scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=12
    scene.render.threads_mode='FIXED';scene.render.threads=2
    scene.render.filepath=str(OUT/'reception_candidate_normal.png')
    report={'status':'basic_production_shape_candidate_not_final_art','input':str(INPUT),'input_sha256':INPUT_SHA,'root_world':[7,5,-6],'checks':checks,'mesh_count':len(meshes),'actual_bounds':rows,'furniture_contact_y':contacts,'not_implemented':['UV/PBR baking','GLB','game collision','rear support integration','runtime door/furniture interaction','game occlusion behavior'],'camera_ortho':22}
    (OUT/'candidate_geometry.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'clinic_reception_candidate.blend'))
    if '--render' in sys.argv or '--render-pair' in sys.argv:bpy.ops.render.render(write_still=True)
    if '--render-pair' in sys.argv:
        for value in [roof_steel,roof_panel]:value.node_tree.nodes['ClinicPrincipled'].inputs['Alpha'].default_value=.16
        scene.render.filepath=str(OUT/'reception_candidate_roof_fade.png');bpy.ops.render.render(write_still=True)
        for value in [roof_steel,roof_panel]:value.node_tree.nodes['ClinicPrincipled'].inputs['Alpha'].default_value=1


if __name__=='__main__':main()
