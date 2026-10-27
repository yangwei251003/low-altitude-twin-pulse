"""CPU-only Blender inspection of exported GLB files, not a game screenshot."""
import bpy, math, json, struct, hashlib
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]; OUT=ROOT/'assets/models/v22'; SOURCE=ROOT/'assets/source_models/v22'
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
manifest=json.loads((OUT/'manifest.json').read_text(encoding='utf-8'))
checks=[]
for index,item in enumerate(manifest['models']):
    path=OUT/(item['id']+'.glb');raw=path.read_bytes();length,kind=struct.unpack_from('<II',raw,12);gltf=json.loads(raw[20:20+length])
    primitives=[p for mesh in gltf['meshes'] for p in mesh['primitives']]
    assert all('COLOR_0' in p['attributes'] for p in primitives)
    assert all('POSITION' in p['attributes'] and 'NORMAL' in p['attributes'] for p in primitives)
    with bpy.data.libraries.load(str(ROOT/item['source']),link=False) as (source_data,destination_data):
        assert source_data.objects
        editable_object_count=len(source_data.objects)
    assert hashlib.sha256(raw).hexdigest()==item['sha256']
    if item['id'].startswith('pedestrian_'):assert gltf.get('skins') and gltf.get('animations')
    checks.append({'id':item['id'],'color_attributes':True,'normal_attributes':True,'surfaces':len(primitives),'skins':len(gltf.get('skins',[])),'animations':len(gltf.get('animations',[])),'sha256_matches_manifest':True,'editable_blend_loaded':True,'editable_object_count':editable_object_count})
    before=set(bpy.context.scene.objects);bpy.ops.import_scene.gltf(filepath=str(path));new=list(set(bpy.context.scene.objects)-before)
    root=bpy.data.objects.new('Catalog_'+item['id'],None);bpy.context.collection.objects.link(root)
    for o in new:
        if o.parent not in new:o.parent=root
    extent=max(item['footprint']+[item['height']]);scale=4.2/max(extent,.01)
    root.scale=(scale,scale,scale);root.location=((index%4-1.5)*6,(index//4-1.5)*6,0)
    # The label is intentionally a model identifier, not screenshot or game UI.
    bpy.ops.object.text_add(location=(root.location.x,root.location.y-2.7,.035))
    label=bpy.context.object;label.data.body=item['id'];label.data.align_x='CENTER';label.data.size=.27
    label.rotation_euler=(0,0,0)
    m=bpy.data.materials.get('LabelInk')
    if m is None:m=bpy.data.materials.new('LabelInk');m.diffuse_color=(.035,.08,.09,1)
    label.data.materials.append(m)
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.035));floor=bpy.context.object
m=bpy.data.materials.new('warm background');m.diffuse_color=(.55,.61,.59,1);floor.data.materials.append(m)
bpy.ops.object.camera_add(location=(18,-28,31));camera=bpy.context.object;camera.rotation_euler=(Vector((0,0,1))-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.type='ORTHO';camera.data.ortho_scale=32
bpy.context.scene.camera=camera
for p,energy,size in [((0,-10,20),2400,12),((-12,6,14),1500,10),((12,8,16),1800,8)]:
    bpy.ops.object.light_add(type='AREA',location=p);light=bpy.context.object;light.data.energy=energy;light.data.shape='DISK';light.data.size=size;light.rotation_euler=(Vector((0,0,0))-light.location).to_track_quat('-Z','Y').to_euler()
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=20;scene.cycles.use_denoising=True
scene.render.threads_mode='FIXED';scene.render.threads=4;scene.world.color=(.3,.3,.3)
scene.render.resolution_x=1500;scene.render.resolution_y=1250;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.render.filepath=str(SOURCE/'catalog_cpu_render.png')
scene.view_settings.view_transform='AgX';scene.frame_set(1)
bpy.ops.render.render(write_still=True)
(SOURCE/'verification.json').write_text(json.dumps({'kind':'exported_model_validation_not_gameplay','count':len(checks),'total_unique_triangles':sum(m['triangles'] for m in manifest['models']),'checks':checks,'render':'assets/source_models/v22/catalog_cpu_render.png','render_engine':'Blender Cycles CPU'},indent=2),encoding='utf-8')
print('V22_EXPORT_VALIDATION_PASS',len(checks),flush=True)
