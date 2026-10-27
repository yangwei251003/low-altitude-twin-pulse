"""Normalize selected CC0 Kenney cars and preserve editable sources."""
import bpy, json, hashlib
from pathlib import Path
from mathutils import Vector

HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2]
OUT=ROOT/'assets/v2/streets';BLENDS=HERE/'blend'
SOURCE=HERE/'third_party/kenney_car_kit/Models/GLB format'
manifest=json.loads((OUT/'manifest.json').read_text(encoding='utf-8'))
for name,length in [('sedan',4.5),('suv',4.7),('delivery',5.4),('van',4.9)]:
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=str(SOURCE/(name+'.glb')))
    meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action='DESELECT')
    for o in meshes:o.select_set(True)
    bpy.context.view_layer.objects.active=meshes[0];bpy.ops.object.join();o=bpy.context.object
    o.matrix_world=o.matrix_world.copy();o.parent=None
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    bounds=[o.matrix_world@Vector(c) for c in o.bound_box]
    lo=Vector([min(p[i] for p in bounds) for i in range(3)]);hi=Vector([max(p[i] for p in bounds) for i in range(3)])
    scale=length/max(hi.x-lo.x,hi.y-lo.y)
    o.scale*=scale;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    bpy.context.view_layer.update()
    bounds=[o.matrix_world@Vector(c) for c in o.bound_box]
    lo=Vector([min(p[i] for p in bounds) for i in range(3)]);hi=Vector([max(p[i] for p in bounds) for i in range(3)])
    o.location-=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
    for x in list(bpy.context.scene.objects):
        if x!=o:bpy.data.objects.remove(x,do_unlink=True)
    o.name='car_'+name
    bpy.context.scene.unit_settings.system='METRIC'
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=str(BLENDS/(o.name+'.blend')))
    path=OUT/(o.name+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',export_yup=True,export_apply=True)
    o.data.calc_loop_triangles()
    manifest['models']=[m for m in manifest['models'] if m['id']!=o.name]
    manifest['models'].append(dict(id=o.name,path='res://assets/v2/streets/'+path.name,
        source_blend=str((BLENDS/(o.name+'.blend')).relative_to(ROOT)).replace('\\','/'),
        footprint=[round(hi.x-lo.x,3),round(hi.y-lo.y,3)],height=round(hi.z-lo.z,3),
        front='+Z (inherited Kenney orientation)',ground_y=0.0,usage='Parked street vehicle; decorative',triangles=len(o.data.loop_triangles),
        surfaces=len(o.data.materials),source='https://kenney.nl/assets/car-kit',license='CC0-1.0',
        source_file=str((SOURCE/(name+'.glb')).relative_to(ROOT)).replace('\\','/'),
        sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
    print('VEHICLE_EXPORTED',o.name,flush=True)
(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2,ensure_ascii=False),encoding='utf-8')
