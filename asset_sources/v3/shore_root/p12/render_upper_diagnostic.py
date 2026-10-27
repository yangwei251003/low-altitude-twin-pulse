"""A clearly marked fixed-camera diagnosis image, never a passing source."""
import bpy,json,hashlib,numpy as np
from pathlib import Path
from mathutils import Vector
OUT=Path(__file__).resolve().parent;PROJECT=OUT.parents[3]
SOURCE=OUT/'upper_cut_before_cleanup.blend';BRIDGE=PROJECT/'assets/v3/root_arch/f1_root_arch.glb'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
before={'source':sha(SOURCE),'bridge':sha(BRIDGE)}
bpy.ops.wm.open_mainfile(filepath=str(SOURCE));scene=bpy.context.scene
high=bpy.data.objects['P10_HighShoulder_ContinuousThickCliff'];high.data.calc_loop_triangles()
np.savez(OUT/'upper_cut_mesh_arrays.npz',
    vertices=np.asarray([tuple(high.matrix_world@v.co) for v in high.data.vertices],dtype=np.float64),
    triangles=np.asarray([tuple(t.vertices) for t in high.data.loop_triangles],dtype=np.int32))
camera=scene.camera.matrix_world.copy();scale=scene.camera.data.ortho_scale
old=set(bpy.data.objects);bpy.ops.import_scene.gltf(filepath=str(BRIDGE))
new=[o for o in bpy.data.objects if o not in old];root=next(o for o in new if o.name=='F1RootArch');root.location+=Vector((24.5,0,0))
colours={'WalkableRoot':(.285,.225,.165),'StoneRemnants':(.28,.285,.27),'Moss':(.17,.23,.14),'Foliage':(.21,.27,.16)}
for ob in new:
    if ob.type!='MESH':continue
    mat=bpy.data.materials.new('DiagnosticBridge_'+ob.name);mat.use_nodes=True
    shader=mat.node_tree.nodes.get('Principled BSDF');shader.inputs['Base Color'].default_value=(*colours[ob.name],1);shader.inputs['Roughness'].default_value=.87
    for i in range(len(ob.data.materials)):ob.data.materials[i]=mat
scene.render.threads_mode='FIXED';scene.render.threads=2;scene.cycles.device='CPU';scene.cycles.samples=12
image=OUT/'p12-upper-cut-diagnostic-assembly.png';scene.render.filepath=str(image)
bpy.context.view_layer.update();assert camera==scene.camera.matrix_world and scale==scene.camera.data.ortho_scale
bpy.ops.render.render(write_still=True)
assert before=={'source':sha(SOURCE),'bridge':sha(BRIDGE)}
(OUT/'p12_diagnostic_image.json').write_text(json.dumps({'status':'diagnostic only; coplanar audit pending; not accepted source, GLB or game image',
    'input_sha256':before,'image_sha256':sha(image),'unchanged_camera':True,'bridge_local_translation_godot':[24.5,0,0]},indent=2),encoding='utf-8')
print('DIAGNOSTIC_IMAGE_ONLY',str(image),flush=True)
