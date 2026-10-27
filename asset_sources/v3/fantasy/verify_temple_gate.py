"""Blender-only round-trip of the delivered GLB, not a game-engine test.
Run: blender --background temple_gate.blend --python verify_temple_gate.py
"""
import bpy, json, struct, hashlib, math
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
SOURCE=Path(__file__).resolve().parent
ROOT=SOURCE.parents[2]
ART=ROOT/'artifacts/v3/art/fantasy'
path=ROOT/'assets/v3/fantasy/temple_gate.glb'
blob=path.read_bytes()
magic,version,total=struct.unpack_from('<4sII',blob)
assert magic==b'glTF' and version==2 and total==len(blob)
size,kind=struct.unpack_from('<I4s',blob,12)
assert kind==b'JSON'
doc=json.loads(blob[20:20+size])
materials=doc.get('materials',[])
rotor_json=next(n for n in doc['nodes'] if n.get('name')=='Rotor')
assert all(abs(a-b)<1e-5 for a,b in zip(rotor_json['translation'],[0,5.2,0]))
assert rotor_json.get('rotation',[0,0,0,1])==[0,0,0,1]
assert len(rotor_json.get('children',[]))==2
assert len(materials)==6
triangles=0
for mesh in doc['meshes']:
    for primitive in mesh['primitives']:
        assert primitive.get('mode',4)==4
        assert 'TEXCOORD_0' in primitive['attributes'] and 'NORMAL' in primitive['attributes']
        triangles+=doc['accessors'][primitive['indices']]['count']//3
assert triangles<60000
assert len(doc['meshes'])==8
assert all('bufferView' in image and 'uri' not in image for image in doc.get('images',[]))
assert all('uri' not in buffer for buffer in doc.get('buffers',[]))
assert len(doc.get('images',[]))>=15
for mat in materials:
    if mat['name']=='FB_InlaidCyanEnergy': continue
    assert 'baseColorTexture' in mat['pbrMetallicRoughness']
    assert 'metallicRoughnessTexture' in mat['pbrMetallicRoughness']
    assert 'normalTexture' in mat

# Hide, rather than replace, editable originals. Load the exact delivery artifact.
source_collection=bpy.data.collections['Editable_TempleGate']
source_collection.hide_render=True
source_collection.hide_viewport=True
bpy.ops.object.select_all(action='DESELECT')
before=set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=str(path))
imported=list(set(bpy.data.objects)-before)
moving=next(o for o in imported if o.type=='EMPTY' and o.name.startswith('Rotor'))
assert (moving.location-Vector((0,0,5.2))).length<1e-5
children=[o for o in imported if o.parent==moving and o.type=='MESH']
assert len(children)==2
volume={}
for o in children:
    o.data.calc_loop_triangles()
    volume[o.name]=sum(o.data.vertices[t.vertices[0]].co.dot(o.data.vertices[t.vertices[1]].co.cross(o.data.vertices[t.vertices[2]].co))/6 for t in o.data.loop_triangles)
    assert volume[o.name]>0, ('Inward rotor mesh',volume)
rotor_points=[o.matrix_world@v.co for o in children for v in o.data.vertices]
radius=[math.hypot(p.x,p.z-5.2) for p in rotor_points]
assert min(radius)>2.18 and max(radius)<=2.901
assert min(p.y for p in rotor_points)>=-.371 and max(p.y for p in rotor_points)<=.371

# Exercise the actual imported hierarchy, then restore its authoring pose.
rest=moving.matrix_basis.copy()
moving.rotation_mode='XYZ'; moving.rotation_euler=(0,math.pi/2,0)
bpy.context.view_layer.update()
turned=[o.matrix_world@v.co for o in children for v in o.data.vertices]
turned_radius=[math.hypot(p.x,p.z-5.2) for p in turned]
assert abs(min(turned_radius)-min(radius))<1e-4
assert abs(max(turned_radius)-max(radius))<1e-4
assert max(abs(p.y) for p in turned)<.371
moving.matrix_basis=rest
bpy.context.view_layer.update()
verts=[]; polygons=[]
for o in imported:
    if o.type!='MESH': continue
    offset=len(verts)
    verts.extend(o.matrix_world@v.co for v in o.data.vertices)
    polygons.extend(tuple(offset+i for i in p.vertices) for p in o.data.polygons)
bvh=BVHTree.FromPolygons(verts,polygons)
assert bvh.ray_cast(Vector((0,-3,5.2)),Vector((0,1,0)),6)[0] is None
assert bvh.ray_cast(Vector((2.55*math.cos(.12),-3,5.2+2.55*math.sin(.12))),Vector((0,1,0)),6)[0] is not None

report={'status':'PASS','blender_round_trip':True,'glb_bytes':len(blob),'sha256':hashlib.sha256(blob).hexdigest(),'triangles_glb':triangles,'mesh_count':len(doc['meshes']),'material_count':len(materials),'embedded_image_count':len(doc['images']),'rotor_gltf_node':rotor_json,'rotor_children':[o.name for o in children],'rotor_signed_volume_m3':volume,'rotor_radius_bounds_m':[min(radius),max(radius)],'checks':['GLB header and length','8 material-merged meshes, independent rotor','All meshes UV0 + normals + triangle mode','5 painted materials each have embedded base colour, roughness and normal maps','6 total materials, below 60k triangles','Rotor glTF local identity rotation and translation (0,5.2,0)','Blender GLB reimport restores pivot (0,0,5.2)','Rotor outward triangle winding','Real hollow radius >=2.18m including chord/bevel discretisation'],'not_tested':['Godot import','Game collision','In-game lighting','Performance','Human acceptance']}
report['checks']+=['Imported Rotor physically turned 90deg about local Blender Y; radius and axial depth remain invariant','Ray through centre passes through entire imported asset; ray through stone rim hits actual geometry']
with open(ART/'temple_gate_glb_verified.json','w',encoding='utf-8') as f: json.dump(report,f,ensure_ascii=False,indent=2)
scene=bpy.context.scene
scene.cycles.samples=32
scene.render.resolution_x=1200; scene.render.resolution_y=1200
scene.render.filepath=str(ART/'temple_gate_glb_preview.png')
bpy.ops.render.render(write_still=True)
print('FB_GLB_VERIFIED '+json.dumps(report,ensure_ascii=False))
