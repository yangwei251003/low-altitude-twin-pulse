"""Normalize the exported tree variants to the exact ground plane."""
import bpy, json, hashlib
from pathlib import Path
from mathutils import Vector
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2];OUT=ROOT/'assets/v2/streets'
manifest=json.loads((OUT/'manifest.json').read_text(encoding='utf-8'))
for name in ['street_tree_round','street_tree_slender']:
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    path=OUT/(name+'.glb');bpy.ops.import_scene.gltf(filepath=str(path))
    meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
    bpy.context.view_layer.update()
    bounds=[o.matrix_world@Vector(c) for o in meshes for c in o.bound_box]
    lo=Vector([min(p[i] for p in bounds) for i in range(3)]);hi=Vector([max(p[i] for p in bounds) for i in range(3)])
    shift=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
    for o in meshes:
        world=o.matrix_world.copy();o.parent=None;o.matrix_world=world;o.location-=shift
    bpy.context.view_layer.update()
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',export_yup=True,export_apply=True,
        export_vertex_color='MATERIAL')
    m=next(m for m in manifest['models'] if m['id']==name)
    m['footprint']=[round(hi.x-lo.x,3),round(hi.y-lo.y,3)];m['height']=round(hi.z-lo.z,3)
    m['sha256']=hashlib.sha256(path.read_bytes()).hexdigest()
    print('TREE_GROUND_FIXED',name,lo.z,flush=True)
(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2,ensure_ascii=False),encoding='utf-8')
