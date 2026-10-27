"""Editable geometric authority for concept refinement, not final visual art."""
import bpy, json, sys
from pathlib import Path
from mathutils import Vector

HERE=Path(__file__).resolve().parent
data=json.loads((HERE/'geometry.json').read_text(encoding='utf-8'))
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
parts=[]
def point(v): return (v[0]+17.625, -(v[2]-5.75), v[1])
for name,row in data['parts'].items():
    vertices=[point(v) for v in row['vertices']]
    faces=[(i,i+2,i+1) for i in range(0,len(vertices),3)]
    mesh=bpy.data.meshes.new(name+'_metres')
    mesh.from_pydata(vertices,[],faces); mesh.update()
    obj=bpy.data.objects.new(name,mesh); bpy.context.collection.objects.link(obj)
    obj['stage']='structural_reference_not_final_art'
    obj['world_origin_godot']=[-17.625,0,5.75]
    uv=mesh.uv_layers.new(name='MetricUV')
    for poly in mesh.polygons:
        for li in poly.loop_indices:
            index=mesh.loops[li].vertex_index
            uv.data[li].uv=row['uv'][index]
    mat=bpy.data.materials.new('Reference_'+name); mat.use_nodes=True
    bs=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    bs.inputs['Base Color'].default_value=(*({'ramp':(.30,.35,.36),'floor':(.38,.36,.32),'walls':(.45,.43,.38),'coping':(.58,.55,.47)}[name]),1)
    bs.inputs['Roughness'].default_value=.85
    obj.data.materials.append(mat); parts.append(obj)
# Isolated outside wall backs: the running world buries these within the terrain.
def wall_back(name,a,b):
    points=[point([a[0],0,a[1]]),point([b[0],0,b[1]]),point([b[0],-2.4,b[1]]),point([a[0],-2.4,a[1]])]
    me=bpy.data.meshes.new(name); me.from_pydata(points,[],[(0,1,2,3)]); me.update()
    ob=bpy.data.objects.new(name,me); bpy.context.collection.objects.link(ob)
    ob.data.materials.append(bpy.data.materials['Reference_walls']); ob['buried_outer_surface']=True
wall_back('OuterWest',(-22,1),(-22,10.5))
wall_back('OuterEast',(-13.25,10.5),(-13.25,1))
wall_back('OuterNorth',(-13.25,1),(-22,1))
wall_back('OuterSouthLeft',(-22,10.5),(-20.5,10.5))
wall_back('OuterSouthRight',(-17.5,10.5),(-13.25,10.5))
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-2.43))
ground=bpy.context.object;ground.name='StudioGround_NOT_ASSET'
mat=bpy.data.materials.new('StudioGray');mat.diffuse_color=(.22,.23,.24,1);ground.data.materials.append(mat)
bpy.ops.object.camera_add(location=(12,-15,15))
camera=bpy.context.object;camera.name='ReferenceCamera'
camera.rotation_euler=(Vector((0,0,-.8))-camera.location).to_track_quat('-Z','Y').to_euler()
camera.data.type='ORTHO';camera.data.ortho_scale=14.8
scene=bpy.context.scene;scene.camera=camera
bpy.ops.object.light_add(type='AREA',location=(-5,-3,12))
light=bpy.context.object;light.data.energy=2200;light.data.shape='DISK';light.data.size=9
scene.world.color=(.5,.5,.5)
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=16
scene.render.threads_mode='FIXED';scene.render.threads=2
scene.cycles.use_denoising=True
scene.render.resolution_x=1000;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'
scene.render.filepath=str(HERE/'01-geometry-authority.png')
bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'inspection_pit_geometry.blend'))
bpy.ops.render.render(write_still=True)
print('PIT_BLOCKOUT_RENDERED_FROM_ACTUAL_PHYSICS_VERTICES')
