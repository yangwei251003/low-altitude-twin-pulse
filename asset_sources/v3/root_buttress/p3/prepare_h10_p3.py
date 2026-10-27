"""Material-only source candidate. Never writes frozen runtime GLBs or p2 source.
Blender native shader edits; original generated PNGs remain byte-identical.
"""
import bpy, json, hashlib, math, struct, sys
from pathlib import Path
from mathutils import Vector

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
SOURCE=HERE.parent/'root_buttress_h10_material_p2.blend'
EXPECTED_SOURCE='ff1e53e770ad0202cd72bca02295a0b90c90256f2522a4f0f4a6f07ef16ba72e'
RUNTIME={
 '10':'ceaae98c56aa8fa3517d43a11708c352e8741fa801d78a24eba87871a8d29d53',
 '12':'85f1d453724b22d379b7313f23aaf0ce2d3090e8b1bc033827bb8bfab36ad536',
 '17':'fd876e8ec85c736f325c4af8ae8d64ab19a24b4e8f1334bd2a422ec9b0d0545a',
 '3':'46eb968ed292cd9e2b74715433c30f19a51080379fc8f018cbd29109df72552b'}
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(SOURCE)==EXPECTED_SOURCE
def frozen():
 return {h:sha(ROOT/f'assets/v3/root_buttress/root_buttress_h{h}.glb') for h in RUNTIME}
assert frozen()==RUNTIME
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
asset=bpy.data.objects['RootButtress']
parts=sorted([o for o in asset.children_recursive if o.type=='MESH'],key=lambda o:o.name)
markers=sorted([o for o in asset.children_recursive if o.type=='EMPTY'],key=lambda o:o.name)
def geometry_digest():
 h=hashlib.sha256()
 for o in parts:
  h.update(o.name.encode());h.update(struct.pack('<16d',*(v for row in o.matrix_world for v in row)))
  for v in o.data.vertices:h.update(struct.pack('<3d',*v.co))
  for p in o.data.polygons:h.update(struct.pack('<'+str(len(p.vertices))+'I',*p.vertices))
  for layer in o.data.uv_layers:
   h.update(layer.name.encode())
   for loop in layer.data:h.update(struct.pack('<2d',*loop.uv))
 for o in markers:h.update(o.name.encode());h.update(struct.pack('<16d',*(v for row in o.matrix_world for v in row)))
 return h.hexdigest()
before=geometry_digest()
scene=bpy.context.scene
camera=scene.camera
# Same fixed oblique direction as actual capture, neutral studio lighting.
target=Vector((0,0,5.3));direction=Vector((.535645,-.535645,.652817))
camera.location=target+direction*35
camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler()
camera.data.type='ORTHO';camera.data.ortho_scale=23.5
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=12
scene.cycles.use_denoising=True;scene.render.threads_mode='FIXED';scene.render.threads=2
scene.render.resolution_x=1280;scene.render.resolution_y=1000;scene.render.resolution_percentage=80
scene.render.image_settings.file_format='PNG'
if '--render-baseline' in sys.argv:
 scene.render.filepath=str(HERE/'h10_p2_controlled_baseline.png')
 bpy.ops.render.render(write_still=True)

stone=bpy.data.materials['RB_Stone'];nodes=stone.node_tree.nodes;links=stone.node_tree.links
p=nodes['Principled BSDF']
new_image=bpy.data.images.load(str(HERE/'stone_reference_p3.png'),check_existing=False)
new_image.colorspace_settings.name='sRGB';new_image.pack()
stone_tex=next(n for n in nodes if n.type=='TEX_IMAGE' and 'BaseColor' in n.image.name)
stone_tex.image=new_image
# Slight cool mineral tint is authored material shading, not altered PNG bytes.
cool=nodes.new('ShaderNodeMixRGB');cool.name='P3_CoolMineralTint';cool.blend_type='MIX'
cool.inputs[0].default_value=.10;cool.inputs[2].default_value=(.105,.145,.17,1)
links.new(stone_tex.outputs['Color'],cool.inputs[1]);links.new(cool.outputs[0],p.inputs['Base Color'])
p.inputs['Specular IOR Level'].default_value=.18
for n in nodes:
 if n.type=='NORMAL_MAP':n.inputs['Strength'].default_value=.15

bark=bpy.data.materials['RB_Bark'];nodes=bark.node_tree.nodes;links=bark.node_tree.links;p=nodes['Principled BSDF']
bark_tex=next(n for n in nodes if n.type=='TEX_IMAGE' and 'BaseColor' in n.image.name)
quiet=nodes.new('ShaderNodeMixRGB');quiet.name='P3_QuietBarkContrast';quiet.blend_type='MIX'
quiet.inputs[0].default_value=.48;quiet.inputs[2].default_value=(.12,.085,.05,1)
links.new(bark_tex.outputs['Color'],quiet.inputs[1]);links.new(quiet.outputs[0],p.inputs['Base Color'])
p.inputs['Specular IOR Level'].default_value=.18
for n in nodes:
 if n.type=='NORMAL_MAP':n.inputs['Strength'].default_value=.16

after=geometry_digest();assert before==after,'Material revision changed geometry, transforms, UV or anchors'
assert frozen()==RUNTIME
out=HERE/'root_buttress_h10_material_p3.blend'
bpy.ops.wm.save_as_mainfile(filepath=str(out))
report={
 'stage':'p3 SOURCE-ONLY material candidate; no runtime export; awaiting actual visual review',
 'source_input':str(SOURCE.relative_to(ROOT)).replace('\\','/'),'source_input_sha256':EXPECTED_SOURCE,
 'source_output':str(out.relative_to(ROOT)).replace('\\','/'),'source_output_sha256':sha(out),
 'geometry_uv_anchor_fingerprint_before':before,'geometry_uv_anchor_fingerprint_after':after,
 'unchanged_geometry_uv_anchors':before==after,'editable_meshes':len(parts),
 'markers':{o.name:list(o.location) for o in markers},'marker_coordinates':'Blender Z-up; Godot = (x,z,-y)',
 'runtime_p2_before_after_sha256':frozen(),'runtime_p2_unchanged':frozen()==RUNTIME,
 'image':{'path':str((HERE/'stone_reference_p3.png').relative_to(ROOT)).replace('\\','/'),
  'sha256':sha(HERE/'stone_reference_p3.png'),'tool':'built-in image_gen',
  'tool_returned_path':'${USERPROFILE}/.codex/generated_images/01a14537-64a1-7b02-9a3b-bfb58caf03fe/exec-7b5ffd6f-50b8-488d-b158-d1e9f638f8ec.png',
  'operation':'byte-identical copied original; no bitmap edits','prompt_file':'stone_prompt_p3.txt'},
 'material_changes':{'Stone':'new sparse-fissure cool bedrock image; linear 10% cool mineral tint; normal .15',
  'Bark':'native Blender MixRGB 48% constant linear (.12,.085,.05), preserving original bitmap and UV; normal .16',
  'Moss/Sap':'unchanged p2 materials and geometry'},
 'limits':['not a game screenshot','not exact Godot lighting; neutral controlled studio',
  'MixRGB candidate must be baked to PBR before future GLB export',
  'top regular outline and broad front root strip remain; no geometry change authorized'],
 'camera_direction_godot':[.535645,.652817,.535645],
 'render':{'engine':'Cycles CPU','threads':2,'samples':12,'pixels':[1024,800]}}
(HERE/'p3_source_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('P3_SOURCE '+json.dumps(report,ensure_ascii=False),flush=True)
if '--render' in sys.argv:
 scene.render.filepath=str(HERE/'h10_p3_material_candidate.png');bpy.ops.render.render(write_still=True)
assert frozen()==RUNTIME
print('P3_DONE_RUNTIME_UNCHANGED',flush=True)
