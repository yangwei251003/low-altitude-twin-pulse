"""Build the existing verified apron plan and export three low-cost groups.

No source render or atlas: reuse the approved concrete maps and vertex tint.
The stored complementary visual surface is installed only after its exact live
raw-array hash matches. No collider is constructed or altered.
"""
from pathlib import Path
import bpy, hashlib, importlib.util, json, os, shutil, struct, sys, time
from mathutils import Matrix
sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
OUT=Path(os.environ['CENTRAL_APRON_OUT']).resolve();assert OUT.is_relative_to(HERE)
sys.path.insert(0,str(HERE))
import geometry as geo
import materials
spec=importlib.util.spec_from_file_location('central_source_frozen',HERE/'build_source.py')
source=importlib.util.module_from_spec(spec);spec.loader.exec_module(source)
CONFIG=json.loads((HERE/'config.json').read_text(encoding='utf-8'))

def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def dump(name,value):(OUT/name).write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def select(objects):
    bpy.ops.object.select_all(action='DESELECT')
    for ob in objects:ob.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]

def simple_material(name,images,seal=False):
    mat,bs,nodes,links=materials.opaque(name)
    if seal:
        bs.inputs['Base Color'].default_value=(.033,.037,.033,1);bs.inputs['Roughness'].default_value=.95;bs.inputs['Metallic'].default_value=0
        return mat
    uv=nodes.new('ShaderNodeUVMap');uv.uv_map='RuntimeUV';textures={}
    for key,image in images.items():
        tex=nodes.new('ShaderNodeTexImage');tex.image=image;tex.extension='REPEAT'
        links.new(uv.outputs[0],tex.inputs['Vector']);textures[key]=tex
    links.new(textures['BaseColor'].outputs['Color'],bs.inputs['Base Color'])
    sep=nodes.new('ShaderNodeSeparateColor');links.new(textures['ORM'].outputs[0],sep.inputs[0])
    links.new(sep.outputs['Green'],bs.inputs['Roughness']);links.new(sep.outputs['Blue'],bs.inputs['Metallic'])
    nm=nodes.new('ShaderNodeNormalMap');nm.uv_map='RuntimeUV';nm.inputs['Strength'].default_value=1
    links.new(textures['Normal'].outputs[0],nm.inputs['Color']);links.new(nm.outputs[0],bs.inputs['Normal'])
    return mat

def complementary_geometry(remainder,originals):
    arrays={'faces':[],'normals':[],'uv':[],'tangents':[]};small_area=0
    for row in remainder:
        original=originals[row['input_triangle']];poly=row['poly'];ids=list(range(len(poly)))
        # This JSON is direct Godot clockwise geometry, unlike Blender's
        # CCW source mesh above. Keep an upward normal with negative cross dot.
        if geo.signed_area(poly)<0:ids.reverse()
        for k in range(1,len(ids)-1):
            triangle=[poly[ids[0]],poly[ids[k]],poly[ids[k+1]]]
            if geo.area(triangle)==0:continue
            positions=[(geo.f32(x),0.0,geo.f32(z)) for x,z in triangle]
            if geo.area([(p[0],p[2]) for p in positions])==0:
                small_area+=geo.area(triangle);continue
            for p,position in zip(triangle,positions):
                weight=geo.barycentric(p,original['poly']);arrays['faces'].append(position)
                arrays['normals'].append(original['corners']['normals'][0]);arrays['tangents'].append(original['corners']['tangents'][0])
                arrays['uv'].append(geo.interpolate(original['corners']['uv'],weight))
    assert small_area<=1e-6
    return arrays,small_area

def main():
    start=time.monotonic();bpy.ops.wm.read_factory_settings(use_empty=True)
    geometry=HERE/'live_input/geometry.json';assert sha(geometry)=='5a854ff84970fedfb54764158ea039f4ef4f45f6707b63f1867b2127d456ccef'
    rows,readback=geo.read_input(geometry,'remainder');selected,remainder,partition=geo.partition(rows,CONFIG)
    images,deps=materials.load_images(HERE,OUT);image_names={key:im.name for key,im in images.items()};mats=materials.make(images,CONFIG);objects=[]
    for name in sorted({r['part'] for r in selected}):
        ob,_,_=source.editable_mesh(name,[r for r in selected if r['part']==name],mats)
        if ob:objects.append(ob)
    counts_before=sum(len(o.data.polygons) for o in objects);assert counts_before==1148
    editable=OUT/'central_service_apron_editable.blend';before=source.geometry_signature()
    bpy.ops.wm.save_as_mainfile(filepath=str(editable),relative_remap=False)
    bpy.ops.wm.open_mainfile(filepath=str(editable));assert source.geometry_signature()==before
    images={key:bpy.data.images[name] for key,name in image_names.items()}
    objects=[o for o in bpy.data.objects if o.get('apron_deliverable')]
    groups={}
    for ob in objects:
        role=ob['surface_role'];key='ApronJoint' if role=='joint' else 'ApronMaintenance' if role=='maintenance' else 'ApronConcrete'
        # Vertex tint is the glTF COLOR_0 multiplier. Material graph remains
        # standard image PBR, avoiding unsupported procedural export nodes.
        attr=ob.data.color_attributes['UseTint']
        if role=='maintenance':
            for item in attr.data:item.color=tuple(v*.64 for v in item.color[:3])+(1.0,)
        groups.setdefault(key,[]).append(ob)
    merged=[];counts={}
    for name,objects in groups.items():
        select(objects)
        if len(objects)>1:bpy.ops.object.join()
        ob=bpy.context.object;ob.name=name;assert ob.matrix_world==Matrix.Identity(4)
        ob.data.materials.clear();ob.data.materials.append(simple_material(name+'_PBR',images,name=='ApronJoint'))
        for uv in list(ob.data.uv_layers):
            if uv.name!='RuntimeUV':ob.data.uv_layers.remove(uv)
        for attr in list(ob.data.attributes):
            if attr.name in ['input_triangle','source_final_triangle','OriginalDryNormal','OriginalDryTangentXYZ','OriginalDryTangentSign']:ob.data.attributes.remove(attr)
        counts[name]=len(ob.data.polygons);merged.append(ob)
    root=bpy.data.objects.new('CentralServiceApron',None);bpy.context.scene.collection.objects.link(root)
    for ob in merged:ob.parent=root
    delivery=OUT/'central_service_apron_delivery.blend';bpy.ops.wm.save_as_mainfile(filepath=str(delivery),relative_remap=False)
    bpy.ops.wm.open_mainfile(filepath=str(delivery));select(list(bpy.data.objects))
    glb=OUT/'central_service_apron.glb'
    bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,export_yup=True,export_apply=False,
        export_texcoords=True,export_normals=True,export_tangents=True,export_materials='EXPORT',export_vertex_color='ACTIVE',
        export_all_vertex_colors=False,export_cameras=False,export_lights=False,export_animations=False)
    complementary,residual=complementary_geometry(remainder,rows)
    points=[(v.co.x,v.co.z,-v.co.y) for ob in bpy.data.objects if ob.type=='MESH' for v in ob.data.vertices]
    bounds=[[min(p[k] for p in points) for k in range(3)],[max(p[k] for p in points) for k in range(3)]]
    dump('central_service_partition.json',{'version':1,'source_attributes_sha256':json.loads(geometry.read_text())['raw_attributes_sha256'],
        'ground_collision_sha256':readback['ground_collision_sha256'],'source_area_m2':readback['area_m2'],
        'replacement_area_m2':partition['replacement_area_m2'],'retained_area_m2':partition['remainder_area_m2'],
        'float32_degenerate_area_m2':residual,'mesh_triangles':counts,'bounds_godot':bounds,'geometry':complementary})
    dump('delivery_report.json',{'status':'EXPORTED_PENDING_GODOT_CAMERA_CHECK','seconds':time.monotonic()-start,
        'editable_blend':str(editable),'editable_reopen_signature':before,'delivery_blend':str(delivery),'glb':str(glb),
        'glb_sha256':sha(glb),'bytes':glb.stat().st_size,'mesh_triangles':counts,'materials':3,'maps':deps,
        'origin_godot':CONFIG['origin'],'partition':partition,'collision':'original Ground untouched; no collider exported',
        'scope':'no new source render, existing verified layout and 3 shared concrete maps; pending actual engine/camera'})
    print('APRON_DELIVERY_PASS '+str(glb),flush=True)

if __name__=='__main__':main()
