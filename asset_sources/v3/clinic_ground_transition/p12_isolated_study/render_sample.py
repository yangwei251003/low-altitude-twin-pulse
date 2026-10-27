"""One unobstructed source-model diagnostic; frozen P12 stays unchanged."""
from pathlib import Path
import bpy,json,hashlib,struct,time,os
from mathutils import Vector
HERE=Path(__file__).resolve().parent
P12=HERE.parent/'p12'
SOURCE=P12/'sample_review_01/editable_sample.blend'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def sig(mesh):
    b=bytearray()
    for v in mesh.vertices:b.extend(struct.pack('<3f',*v.co))
    for p in mesh.polygons:
        b.extend(struct.pack('<I',len(p.vertices)));b.extend(struct.pack('<'+'I'*len(p.vertices),*p.vertices))
    for uv in mesh.uv_layers:
        for d in uv.data:b.extend(struct.pack('<2f',*d.uv))
    return hashlib.sha256(b).hexdigest()
def look(obj,point):obj.rotation_euler=(Vector(point)-obj.location).to_track_quat('-Z','Y').to_euler()
def main():
    start=time.time();output=HERE/'rock07_isolated.png';assert not output.exists()
    source_sha=sha(SOURCE);manifest_sha=sha(P12/'manifest.json')
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    sample=bpy.data.objects['Study_Rock07_LOD3_Sediment047'];geometry_uv_sha=sig(sample.data)
    material=sample.data.materials[0];images=[]
    for node in material.node_tree.nodes:
        if node.type=='TEX_IMAGE' and node.image:
            im=node.image;path=Path(bpy.path.abspath(im.filepath));assert path.exists()
            im.reload();pixel=list(im.pixels[:4]);assert im.has_data and len(pixel)==4
            images.append({'file':str(path.resolve()),'sha256':sha(path),'pixels':list(im.size),'color_space':im.colorspace_settings.name});im.filepath=str(path.resolve())
    for ob in list(bpy.data.objects):
        if ob!=sample:bpy.data.objects.remove(ob,do_unlink=True)
    coords=[sample.matrix_world@v.co for v in sample.data.vertices]
    low=Vector(tuple(min(p[i] for p in coords) for i in range(3)));high=Vector(tuple(max(p[i] for p in coords) for i in range(3)))
    translation=Vector((-(low.x+high.x)*.5,-(low.y+high.y)*.5,-low.z))
    sample.location+=translation
    sample.hide_render=False;sample.hide_viewport=False;sample.hide_set(False)
    bpy.ops.mesh.primitive_plane_add(size=2,location=(0,0,-.0004));floor=bpy.context.object;floor.name='DiagnosticNeutralGround_NotAsset'
    mat=bpy.data.materials.new('DiagnosticNeutralGrey');mat.use_nodes=True
    bs=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED');bs.inputs['Base Color'].default_value=(.18,.18,.18,1);bs.inputs['Roughness'].default_value=.85
    floor.data.materials.append(mat)
    world=bpy.data.worlds.new('DiagnosticNeutralWorld');world.use_nodes=True
    world.node_tree.nodes.clear()
    background=world.node_tree.nodes.new('ShaderNodeBackground')
    world_output=world.node_tree.nodes.new('ShaderNodeOutputWorld')
    background.inputs['Color'].default_value=(.7,.7,.7,1);background.inputs['Strength'].default_value=.35
    world.node_tree.links.new(background.outputs['Background'],world_output.inputs['Surface'])
    scene=bpy.context.scene;scene.world=world
    for name,position,power,size in [('Key',(-.45,-.55,.70),12,.5),('Fill',(.55,-.15,.40),5,.5),('Rim',(.15,.50,.60),7,.4)]:
        data=bpy.data.lights.new('Diagnostic'+name,'AREA');data.energy=power;data.shape='DISK';data.size=size
        ob=bpy.data.objects.new('Diagnostic'+name,data);scene.collection.objects.link(ob);ob.location=position;look(ob,(0,0,.02))
    camera_data=bpy.data.cameras.new('DiagnosticCamera');camera=bpy.data.objects.new('DiagnosticCamera',camera_data);scene.collection.objects.link(camera)
    camera.location=(.22,-.27,.20);look(camera,(0,0,.023));camera_data.type='ORTHO';camera_data.ortho_scale=.19;camera_data.lens=50;camera_data.clip_start=.001;camera_data.clip_end=10;scene.camera=camera
    scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=32;scene.cycles.use_denoising=True
    scene.render.threads_mode='FIXED';scene.render.threads=2;scene.render.resolution_x=1440;scene.render.resolution_y=1080;scene.render.resolution_percentage=100
    scene.view_settings.exposure=0;scene.view_settings.gamma=1;scene.render.film_transparent=False
    assert sig(sample.data)==geometry_uv_sha;sample.data.calc_loop_triangles();assert len(sample.data.loop_triangles)==1854
    bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'isolated_diagnostic.blend'),relative_remap=False)
    scene.render.filepath=str(output);bpy.ops.render.render(write_still=True)
    assert sha(SOURCE)==source_sha and sha(P12/'manifest.json')==manifest_sha
    report={'status':'ISOLATED_SOURCE_MODEL_RENDERED_PENDING_REVIEW','pid':os.getpid(),'elapsed_seconds':time.time()-start,'purpose':'12cm source-model inspection on a neutral studio ground, not a scene or gameplay screenshot.','source':str(SOURCE),'source_sha256':source_sha,'frozen_p12_unchanged':True,'geometry_uv_signature_unchanged':geometry_uv_sha,'rigid_studio_translation_only':list(translation),'actual_triangles':1854,'same_uniform_scale_as_p12':.3743516733987144,'source_long_axis_m':.12,'actual_rotated_dimensions_m':list(high-low),'images':images,'normal_map':'Original Rock07 NormalGL tangent texture, unchanged strength 1 and native UV.','camera':{'location':list(camera.location),'rotation':list(camera.rotation_euler),'ortho_scale_m':.19},'lighting':'Neutral studio world and three area lights; this deliberately changes lighting from the scene to inspect the source, not an identical-light A/B.','render_sha256':sha(output),'no_bake_no_glb':True}
    (HERE/'result.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({'pid':os.getpid(),'exit_stage':'complete','seconds':time.time()-start,'render':str(output)}),flush=True)
if __name__=='__main__':main()
