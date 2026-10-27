"""Re-import final GLBs, validate geometry, render a catalog (not a game screenshot)."""
import bpy, json, math, struct, hashlib, sys
from pathlib import Path
from mathutils import Vector

HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2];OUT=ROOT/'assets/v2/streets'
manifest=json.loads((OUT/'manifest.json').read_text(encoding='utf-8'))
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
checks=[]
for idx,entry in enumerate(manifest['models']):
    path=OUT/(entry['id']+'.glb');data=path.read_bytes()
    assert data[:4]==b'glTF'
    size,kind=struct.unpack_from('<II',data,12)
    gltf=json.loads(data[20:20+size])
    primitives=[p for me in gltf.get('meshes',[]) for p in me['primitives']]
    assert len(primitives)<=5,(entry['id'],len(primitives))
    if entry['license']=='Project original':
        assert all('COLOR_0' in p['attributes'] for p in primitives),entry['id']
    before=set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    meshes=[o for o in set(bpy.context.scene.objects)-before if o.type=='MESH']
    bpy.context.view_layer.update()
    bounds=[o.matrix_world@Vector(c) for o in meshes for c in o.bound_box]
    lo=Vector([min(p[i] for p in bounds) for i in range(3)]);hi=Vector([max(p[i] for p in bounds) for i in range(3)])
    assert len(meshes)>0
    checks.append(dict(id=entry['id'],surfaces=len(primitives),vertices=sum(len(o.data.vertices) for o in meshes),
        bytes=len(data),ground_z=round(lo.z,7),ground_pass=abs(lo.z)<.001,dimensions=[round(v,3) for v in (hi-lo)],sha256=hashlib.sha256(data).hexdigest()))
    # Catalog scale only; game assets themselves remain meter scale.
    scale=3.5/max(hi-lo)
    offset=Vector(((idx%5-2)*4.9,(idx//5-2)*5.0,.13))
    for o in meshes:
        world=o.matrix_world.copy();o.parent=None;o.matrix_world=world
        o.location=o.location*scale+offset;o.scale*=scale
    bpy.ops.mesh.primitive_cube_add(size=1,location=(offset.x,offset.y,-.04))
    plinth=bpy.context.object;plinth.dimensions=(4.55,4.45,.21)
    mat=bpy.data.materials.get('Catalog sandstone')
    if not mat:
        mat=bpy.data.materials.new('Catalog sandstone');mat.diffuse_color=(.72,.74,.68,1)
    plinth.data.materials.append(mat)
    bpy.ops.object.text_add(location=(offset.x,offset.y-1.97,.08))
    t=bpy.context.object;t.data.body=entry['id'].replace('_',' ').upper();t.data.align_x='CENTER';t.data.size=.19;t.data.extrude=.001
    tm=bpy.data.materials.get('Catalog ink')
    if not tm:tm=bpy.data.materials.new('Catalog ink');tm.diffuse_color=(.035,.08,.1,1)
    t.data.materials.append(tm)

world=bpy.data.worlds.new('Catalog daylight');bpy.context.scene.world=world;world.use_nodes=True
world.node_tree.nodes.clear();bg=world.node_tree.nodes.new('ShaderNodeBackground');bg.inputs['Color'].default_value=(.65,.75,.78,1);bg.inputs['Strength'].default_value=.7
output=world.node_tree.nodes.new('ShaderNodeOutputWorld');world.node_tree.links.new(bg.outputs['Background'],output.inputs['Surface'])
bpy.ops.object.light_add(type='AREA',location=(-12,-17,28));bpy.context.object.data.energy=3000;bpy.context.object.data.shape='DISK';bpy.context.object.data.size=20
bpy.ops.object.light_add(type='SUN',location=(0,0,15));bpy.context.object.rotation_euler=(math.radians(20),math.radians(-25),math.radians(-25));bpy.context.object.data.energy=2.2;bpy.context.object.data.angle=.20
bpy.ops.object.camera_add(location=(22,-34,33));cam=bpy.context.object;cam.rotation_euler=(Vector((0,0,0))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=34
scene=bpy.context.scene;scene.camera=cam;scene.render.engine='CYCLES';scene.cycles.samples=16
scene.render.resolution_x=1800;scene.render.resolution_y=1800;scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX';scene.render.image_settings.file_format='PNG';scene.render.filepath=str(HERE/'street_catalog.png')
bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'catalog_scene.blend'))
(HERE/'verification.json').write_text(json.dumps(dict(check='Final GLB re-import and material/ground/geometry checks',models=checks),indent=2),encoding='utf-8')
if '--checks-only' not in sys.argv:bpy.ops.render.render(write_still=True)
print('STREET_VALIDATION_COMPLETE',len(checks),flush=True)
