"""Parent-requested basic-color GLB for real camera diagnosis, not promotion."""
import bpy,json,hashlib,struct
from pathlib import Path
from mathutils import Vector
HERE=Path(__file__).resolve().parent;PROJECT=HERE.parents[3]
SOURCE=HERE/'upper_cut_before_cleanup.blend'
OUT=PROJECT/'assets/v3/candidates/shore_root_t03a_p12';OUT.mkdir(parents=True,exist_ok=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
source_hash=sha(SOURCE)
bpy.ops.wm.open_mainfile(filepath=str(SOURCE));scene=bpy.context.scene
col=bpy.data.collections['P12_SHORE_ROOT_EDITABLE']
parts=[o for o in col.objects if o.type=='MESH' and not o.hide_render]
assert len(parts)==5,[o.name for o in parts]
root_mesh=bpy.data.objects['P10_NaturalMainRoot_TrueCrossSectionCuts']
def gp(p):return [float(p.x),float(p.z),float(-p.y)]
def bounds(objects):
    points=[gp(o.matrix_world@v.co) for o in objects for v in o.data.vertices]
    return {'min':[min(p[k] for p in points) for k in range(3)],'max':[max(p[k] for p in points) for k in range(3)]}
cap=[gp(root_mesh.matrix_world@v.co) for v in root_mesh.data.vertices if abs(v.co.z-.1)<1e-5]
source_bounds=bounds(parts)
asset_root=bpy.data.objects.new('ShoreRootT03A',None);col.objects.link(asset_root)
asset_root['status']='DIAGNOSTIC ONLY: basic colors, dense source mesh, not runtime or final artwork'
asset_root['known_coplanar_pair_area_sum_m2']=1.306336372408623e-9
meshes=[]
for name,group in [('RockMasses',[o for o in parts if o!=root_mesh]),('LivingRoots',[root_mesh])]:
    bpy.ops.object.select_all(action='DESELECT')
    for o in group:o.select_set(True)
    bpy.context.view_layer.objects.active=group[0]
    if len(group)>1:bpy.ops.object.join()
    ob=bpy.context.object;ob.name=name;ob.parent=asset_root
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    meshes.append(ob)
anchors={'GroundOrigin':[0,0,0],'BridgeJoin':[4.5,4.5,0],'WestBlend':[-4.3,.34,0]}
exported=[asset_root]+meshes
for name,p in anchors.items():
    ob=bpy.data.objects.new(name,None);col.objects.link(ob);ob.parent=asset_root;ob.location=(p[0],-p[2],p[1]);exported.append(ob)
bpy.ops.object.select_all(action='DESELECT')
for o in exported:o.select_set(True)
bpy.context.view_layer.objects.active=asset_root
editable=HERE/'shore_root_t03a_p12_diagnostic_export.blend';bpy.ops.wm.save_as_mainfile(filepath=str(editable))
glb=OUT/'shore_root_t03a_diagnostic.glb'
bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,export_apply=True,export_yup=True,
    export_extras=True,export_texcoords=False,export_normals=True,export_materials='EXPORT',export_cameras=False,export_lights=False,export_animations=False)
assert sha(SOURCE)==source_hash
for o in exported:o.name='Source_'+o.name
old=set(bpy.data.objects);bpy.ops.import_scene.gltf(filepath=str(glb));imported=[o for o in bpy.data.objects if o not in old]
actual_meshes=[o for o in imported if o.type=='MESH'];actual_bounds=bounds(actual_meshes)
actual_anchors={o.name:gp(o.matrix_world.translation) for o in imported if o.name in anchors}
assert set(actual_anchors)==set(anchors)
assert max(abs(actual_anchors[k][i]-anchors[k][i]) for k in anchors for i in range(3))<2e-5
assert max(abs(actual_bounds[k][i]-source_bounds[k][i]) for k in source_bounds for i in range(3))<2e-5
raw=glb.read_bytes();n=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+n])
triangles={m.get('name',str(i)):sum(doc['accessors'][p['indices']]['count']//3 for p in m['primitives']) for i,m in enumerate(doc['meshes'])}
result={'status':'basic-color diagnostic GLB; not formal geometry/art/performance acceptance',
    'glb':str(glb),'sha256':sha(glb),'bytes':glb.stat().st_size,
    'input_source':str(SOURCE),'input_source_sha256':source_hash,
    'editable_source':str(editable),'editable_source_sha256':sha(editable),
    'actual_readback_bounds_godot':actual_bounds,'actual_triangles':triangles,'actual_triangle_total':sum(triangles.values()),
    'actual_anchors_godot':actual_anchors,'actual_mesh_names':[o.name for o in actual_meshes],'material_count':len(doc['materials']),
    'root_base_cap_points':len(cap),'root_base_cap_bounds_godot':{'min':[min(p[i] for p in cap) for i in range(3)],'max':[max(p[i] for p in cap) for i in range(3)]},
    'placement_world_godot':[-24.5,0,-6],
    'known_limits':['12 coplanar boundary reports; independent clipped pair area sum 1.306336372408623e-9 square metres; not waived.',
        'Dense source mesh is deliberately not retopologized or performance-qualified.',
        'No UV/PBR bake, no game-camera approval, no runtime asset replacement.',
        'Wide upper gray cut surface is a modeling shortcut outside the required final-metre join, not an engineering requirement.'],
    'evidence':['upper_cut_diagnosis.json','upper_coplanar_audit.json','coplanar_overlap_measurement.json','p12_diagnostic_image.json']}
(HERE/'p12_diagnostic_glb.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print('P12_DIAGNOSTIC_GLB',json.dumps(result,ensure_ascii=False),flush=True)
