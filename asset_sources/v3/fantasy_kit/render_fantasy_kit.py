"""Render locked runtime GLBs, without saving or exporting model changes. CPU 2 threads."""
import bpy,math,json,hashlib,sys
from pathlib import Path
from mathutils import Vector,Matrix
ROOT=Path(__file__).resolve().parents[3]
ART=ROOT/'artifacts/v3/art/fantasy_kit'
args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
names=['rootstone_terrace','photosensitive_roots'] if not args else args
for name in names:
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    path=ROOT/'assets/v3/fantasy_kit'/(name+'.glb')
    before=hashlib.sha256(path.read_bytes()).hexdigest()
    bpy.ops.import_scene.gltf(filepath=str(path))
    scene=bpy.context.scene
    scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=24;scene.cycles.use_denoising=True
    scene.render.threads_mode='FIXED';scene.render.threads=2
    scene.render.resolution_x=1040;scene.render.resolution_y=820;scene.render.resolution_percentage=100
    scene.view_settings.view_transform='AgX';scene.view_settings.look='AgX - Medium High Contrast'
    scene.world.color=(.24,.24,.24)
    terrace=name=='rootstone_terrace';scale=6 if terrace else 1.4
    target=Vector((0,0,2.5 if terrace else .8))
    for n,loc,power,size,color in (
        ('Key',(-scale*1.2,-scale*1.3,scale*2.2),1800 if terrace else 260,scale*1.2,(1,.89,.74)),
        ('Fill',(scale*1.3,-scale*.2,scale),900 if terrace else 140,scale,(.68,.79,1)),
        ('Rim',(0,scale*1.4,scale*1.7),1600 if terrace else 220,scale,(1,.92,.78))):
        data=bpy.data.lights.new(n,'AREA');data.energy=power;data.shape='DISK';data.size=size;data.color=color
        ob=bpy.data.objects.new(n,data);scene.collection.objects.link(ob);ob.location=loc;ob.rotation_euler=(target-ob.location).to_track_quat('-Z','Y').to_euler()
    bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.07 if terrace else 0))
    floor=bpy.context.object;floor.name='Offline_Studio_Floor'
    mat=bpy.data.materials.new('Offline_Studio_Floor');mat.diffuse_color=(.18,.20,.19,1);floor.data.materials.append(mat)
    data=bpy.data.cameras.new('Camera');cam=bpy.data.objects.new('Camera',data);scene.collection.objects.link(cam);scene.camera=cam;data.type='ORTHO'
    def camera(loc,target,ortho):
        cam.location=loc;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();data.ortho_scale=ortho
    camera((11,-17,12),(0,0,2.5),16.5) if terrace else camera((3.2,-4.6,3.2),(0,0,.98),3.9)
    scene.render.filepath=str(ART/(name+'_glb_preview.png'));bpy.ops.render.render(write_still=True)
    if terrace:
        camera((-10,16,10),(0,0,2.5),16.5)
        scene.render.filepath=str(ART/(name+'_glb_back.png'));bpy.ops.render.render(write_still=True)
    else:
        for n in ('N','E','S','W'):
            p=bpy.data.objects['LeafPivot_'+n];p.matrix_basis=p.matrix_basis@Matrix.Rotation(math.radians(-58),4,'X')
        camera((3.2,-4.6,3.2),(0,0,.65),4.5)
        scene.render.filepath=str(ART/(name+'_glb_open.png'));bpy.ops.render.render(write_still=True)
    assert before==hashlib.sha256(path.read_bytes()).hexdigest()
    (ART/(name+'_render_evidence.json')).write_text(json.dumps({'input':'assets/v3/fantasy_kit/'+name+'.glb','sha256':before,'render_engine':'Blender Cycles CPU','threads':2,'samples':24,'model_file_unchanged':True,'not_game_screenshot':True},indent=2),encoding='utf-8')
    print('LOCKED_GLB_RENDERED',name,before)
