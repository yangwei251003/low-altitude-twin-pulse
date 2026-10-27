"""Explicit six-body/two-material GLB. Original editable 21-part source stays frozen."""
from pathlib import Path
import hashlib
import json
import sys
import time
sys.dont_write_bytecode=True
import bpy
from mathutils import Matrix,Vector
sys.path.insert(0,str(Path(__file__).resolve().parent))
from verify_export import verify_raw
OUT=Path(__file__).resolve().parent
ROOT=OUT.parents[3]
ORIGIN=[15,5,0]
GROUPS=['WestLanding','EastLanding','SouthBypass','WestOuterRail','EastOuterRail','SouthOuterRail']
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def gp(p):return [p[0],p[2],-p[1]]
def bp(p):return Vector((p[0],-p[2],p[1]))
def write(p,v):Path(p).write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

def final_material(maps, name):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.use_backface_culling = True
    nodes, links = material.node_tree.nodes, material.node_tree.links
    nodes.clear()
    p = nodes.new('ShaderNodeBsdfPrincipled')
    output = nodes.new('ShaderNodeOutputMaterial')
    links.new(p.outputs[0], output.inputs['Surface'])
    uv = nodes.new('ShaderNodeUVMap')
    uv.uv_map = 'SurfaceUV'
    textures = {}
    for channel in ['BaseColor','ORM','Normal']:
        image = bpy.data.images.load(maps[channel], check_existing=False)
        image.colorspace_settings.name = 'sRGB' if channel == 'BaseColor' else 'Non-Color'
        node = nodes.new('ShaderNodeTexImage')
        node.name = 'Baked_'+channel
        node.image = image
        links.new(uv.outputs[0], node.inputs['Vector'])
        textures[channel] = node
    links.new(textures['BaseColor'].outputs['Color'], p.inputs['Base Color'])
    split = nodes.new('ShaderNodeSeparateColor')
    split.mode = 'RGB'
    links.new(textures['ORM'].outputs['Color'], split.inputs[0])
    links.new(split.outputs['Green'], p.inputs['Roughness'])
    links.new(split.outputs['Blue'], p.inputs['Metallic'])
    normal = nodes.new('ShaderNodeNormalMap')
    normal.space = 'TANGENT'
    normal.uv_map = 'SurfaceUV'
    normal.inputs['Strength'].default_value = 1
    links.new(textures['Normal'].outputs['Color'], normal.inputs['Color'])
    links.new(normal.outputs[0], p.inputs['Normal'])
    p.inputs['Alpha'].default_value = 1
    p.inputs['Emission Strength'].default_value = 0
    return material

def main():
    started=time.monotonic();target=OUT/'shared_access_landings.glb';assert not target.exists()
    prep=json.loads((OUT/'atlas_preparation_report.json').read_text(encoding='utf-8'))
    baked=json.loads((OUT/'bake_report.json').read_text(encoding='utf-8'));assert baked['stage']=='BAKE_COMPLETE'
    assert sha(OUT/'uv_checkpoint.blend')==prep['checkpoint_sha256']
    for row in baked['textures'].values():assert sha(row['path'])==row['sha256']
    bpy.ops.wm.open_mainfile(filepath=str(OUT/'uv_checkpoint.blend'))
    proxy=bpy.data.objects['DeliveryProxy'];mesh=proxy.data;mesh.calc_loop_triangles()
    layout_path=ROOT/'data/v3/terrain/i2_shared_access_layout.json'
    assert sha(layout_path)=='ad357fc68c68692a99f2d5394f8774569e3fa3caceaade0920a917468104b556'
    specs={r['id']:r for r in json.loads(layout_path.read_text(encoding='utf-8'))['fixed']}
    mats=[final_material({ch:baked['textures'][group+'/'+ch]['path'] for ch in ['BaseColor','ORM','Normal']},'SharedLandings_'+group+'_PBR') for group in ['Deck','Coating']]
    for obj in list(bpy.data.objects):
        if obj.type=='EMPTY':bpy.data.objects.remove(obj,do_unlink=True)
    root=bpy.data.objects.new('SharedAccessLandings',None);bpy.context.scene.collection.objects.link(root)
    root['world_origin_godot']=ORIGIN;root['source_sha256']=prep['source_sha256']
    selected=[root];expected={};contract={'identity_groups':[{'name':root.name,'parent':None,'translation':[0,0,0]}],'anchors':[],'parts':[]}
    for group_id,name in enumerate(GROUPS):
        center=[specs[name]['center'][i]-ORIGIN[i] for i in range(3)];cb=bp(center)
        verts=[];faces=[];normals=[];uvs=[];mids=[]
        for tri in mesh.loop_triangles:
            if mesh.attributes['DeliveryGroup'].data[tri.polygon_index].value!=group_id:continue
            start=len(verts);verts.extend(tuple(mesh.vertices[vi].co-cb) for vi in tri.vertices);faces.append((start,start+1,start+2))
            normals.extend(tuple(mesh.corner_normals[li].vector) for li in tri.loops)
            uvs.extend(tuple(mesh.uv_layers['DeliveryBakeUV'].data[li].uv) for li in tri.loops)
            material=mesh.materials[mesh.polygons[tri.polygon_index].material_index]
            mids.append(0 if material.name=='IB_DeckSteel' else 1)
        m=bpy.data.meshes.new(name+'_DeliveryMesh');m.from_pydata(verts,[],faces);m.update()
        for mat in mats:m.materials.append(mat)
        for face,mid in zip(m.polygons,mids):face.use_smooth=True;face.material_index=mid
        m.normals_split_custom_set(normals);m.uv_layers.new(name='SurfaceUV');m.uv_layers[0].active_render=True
        for loop,value in zip(m.uv_layers[0].data,uvs):loop.uv=value
        obj=bpy.data.objects.new(name,m);bpy.context.scene.collection.objects.link(obj);obj.parent=root;obj.location=cb
        obj['source_body_id']=name;obj['collision_scope']='Visual only. Preserve original production fixed body and dimensions.'
        selected.append(obj);m.calc_loop_triangles()
        expected[name]=[[{'p':gp(m.vertices[vi].co),'n':gp(m.corner_normals[li].vector),'uv':list(m.uv_layers[0].data[li].uv),'material':mats[m.polygons[tri.polygon_index].material_index].name} for vi,li in zip(tri.vertices,tri.loops)] for tri in m.loop_triangles]
        assert len(expected[name])==prep['body_triangles'][name]
        points=[gp(v.co) for v in m.vertices]
        bounds={'min':[min(v[i] for v in points) for i in range(3)],'max':[max(v[i] for v in points) for i in range(3)]}
        contract['parts'].append({'name':name,'parent':root.name,'translation':center,'triangles':len(expected[name]),'accessor_local_bounds_expected':bounds})
    assert sum(len(v) for v in expected.values())==13908
    for obj in list(bpy.data.objects):
        if obj not in selected and obj.type not in ('CAMERA','LIGHT'):bpy.data.objects.remove(obj,do_unlink=True)
    for image in bpy.data.images:
        if image.source=='FILE' and image.filepath:
            image.filepath=bpy.path.relpath(bpy.path.abspath(image.filepath),start=str(OUT))
    for obj in bpy.context.selected_objects:obj.select_set(False)
    for obj in selected:obj.hide_render=False;obj.hide_set(False);obj.select_set(True)
    bpy.context.view_layer.objects.active=selected[1]
    blend=OUT/'shared_access_landings_delivery.blend';bpy.ops.wm.save_as_mainfile(filepath=str(blend),relative_remap=False)
    bpy.ops.export_scene.gltf(filepath=str(target),export_format='GLB',use_selection=True,export_yup=True,
        export_apply=False,export_texcoords=True,export_normals=True,export_tangents=True,export_materials='EXPORT',
        export_extras=True,export_cameras=False,export_lights=False,export_animations=False)
    raw=verify_raw(target,expected,{key:r['path'] for key,r in baked['textures'].items()},contract)
    write(OUT/'raw_glb_report.json',raw);write(OUT/'node_contract.json',contract)
    write(OUT/'export_report.json',{'stage':'RAW_GLB_VERIFIED_PENDING_SAME_BYTE_REIMPORT','seconds':time.monotonic()-started,
         'glb_sha256':raw['sha256'],'bytes':raw['bytes'],'source_sha256':prep['source_sha256'],'runtime_written':False,
         'delivery_blend_sha256':sha(blend),'expected_geometry_kept_in_memory_not_dumped_to_giant_json':True})
    print('LANDING_EXPORT '+json.dumps({'sha256':raw['sha256'],'bytes':raw['bytes'],'seconds':time.monotonic()-started}),flush=True)
if __name__=='__main__':main()
