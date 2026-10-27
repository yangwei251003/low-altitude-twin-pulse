"""Restore only high polygon material indices from retained original/mapping. No bake."""
from pathlib import Path
import sys,os,time,json,hashlib,traceback
sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parent))
import bpy
import numpy as np
import common as C
CONTRACT=json.loads((HERE/'input_contract.json').read_text(encoding='utf-8'))


def verify():
    rows={}
    for path,expected in CONTRACT['input_hashes'].items():
        p=Path(path);actual={'bytes':p.stat().st_size,'sha256':C.sha(p)}
        assert actual==expected,(path,actual,expected);rows[path]=actual
    return rows


def fingerprint(data,include_material=True):
    h=hashlib.sha256()
    for key in ['co','vi','li','normals','smooth']+(['materials'] if include_material else []):
        a=data[key];h.update(key.encode());h.update(str(a.shape).encode());h.update(a.tobytes())
    for key,a in sorted(data['uv'].items()):h.update(key.encode());h.update(a.tobytes())
    h.update(repr([list(r) for r in data['object'].matrix_world]).encode())
    return h.hexdigest()


def graph(material):
    nodes=[]
    for node in material.node_tree.nodes:
        values=[]
        for socket in node.inputs:
            if not hasattr(socket,'default_value'):continue
            value=socket.default_value
            try:value=list(value)
            except TypeError:pass
            values.append([socket.identifier,value])
        image=getattr(node,'image',None)
        nodes.append({'name':node.name,'type':node.bl_idname,'inputs':values,'image':None if image is None else [image.name,C.sha(Path(bpy.path.abspath(image.filepath)).resolve()),image.colorspace_settings.name],'uv_map':getattr(node,'uv_map',None)})
    return {'name':material.name,'nodes':nodes,'links':[[x.from_node.name,x.from_socket.identifier,x.to_node.name,x.to_socket.identifier] for x in material.node_tree.links]}


def scene_lock(scene):
    return {'camera_matrix':[list(r) for r in scene.camera.matrix_world],
            'ortho_scale':scene.camera.data.ortho_scale,
            'resolution':[scene.render.resolution_x,scene.render.resolution_y,scene.render.resolution_percentage],
            'view_transform':scene.view_settings.view_transform,'look':scene.view_settings.look,
            'exposure':scene.view_settings.exposure,'gamma':scene.view_settings.gamma,
            'lights':[{'name':o.name,'matrix':[list(r) for r in o.matrix_world],
                       'energy':o.data.energy,'color':list(o.data.color),'size':o.data.size}
                      for o in bpy.data.objects if o.type=='LIGHT']}


def visibility(names):
    wanted=set(names)
    for ob in bpy.data.objects:
        if ob.type=='MESH':ob.hide_render=ob.name not in wanted
    bpy.context.view_layer.update()
    assert {o.name for o in bpy.data.objects if o.type=='MESH' and not o.hide_render}==wanted


def main():
    start=time.monotonic();before=verify();oldinputs=C.verify_inputs()
    bpy.ops.wm.open_mainfile(filepath=CONTRACT['completed_blend'])
    low=C.read(bpy.data.objects['BoundaryLowFull']);high=C.read(bpy.data.objects['BoundaryHighFull']);original=C.read(bpy.data.objects['RepairHighFull'])
    image_before=C.images_before_save();image_sha={x['path']:x['sha256'] for x in image_before}
    low_hash=fingerprint(low);high_geo_hash=fingerprint(high,False);low_graph=graph(low['mesh'].materials[0]);camera=scene_lock(bpy.context.scene)
    context=[o.name for o in bpy.data.objects if o.type=='MESH' and not o.hide_render and o.name!='BoundaryLowFull']
    mapping=json.loads(Path(CONTRACT['mapping']).read_text(encoding='utf-8'));ids=np.asarray(mapping['original_triangle'],np.int32)
    assert len(ids)==len(high['tri']) and len(high['mesh'].polygons)==len(high['tri'])
    slots=[m.name for m in original['mesh'].materials];actual_slots=[m.name for m in high['mesh'].materials]
    expected_slots=['BoundaryGlobalAO_'+name for name in slots]
    assert actual_slots==expected_slots,(actual_slots,expected_slots)
    expected=original['materials'][ids];before_indices=high['materials'].copy()
    for t,index in zip(high['mesh'].loop_triangles,expected):high['mesh'].polygons[t.polygon_index].material_index=int(index)
    high['mesh'].update();actual=C.read(high['object'])
    assert np.array_equal(actual['materials'],expected)
    assert fingerprint(actual,False)==high_geo_hash and fingerprint(C.read(low['object']))==low_hash
    assert graph(low['mesh'].materials[0])==low_graph
    report={'original_slots':slots,'high_slots':actual_slots,'original_face_mapping_used':True,
        'before_index_counts':dict(zip(*[x.tolist() for x in np.unique(before_indices,return_counts=True)])),
        'restored_index_counts':dict(zip(*[x.tolist() for x in np.unique(expected,return_counts=True)])),
        'changed_high_triangles':int((before_indices!=expected).sum()),'high_geometry_UV_normals_exact':True,'low_all_data_exact':True,
        'new_bake':False,'image_bytes_unchanged':image_sha,'source_file_unchanged':True}
    C.write('material_index_repair.json',report)
    saved=C.OUT/'corrected_high_reference.blend';bpy.ops.wm.save_as_mainfile(filepath=str(saved),relative_remap=False);saved_sha=C.sha(saved)
    bpy.ops.wm.open_mainfile(filepath=str(saved));newlow=C.read(bpy.data.objects['BoundaryLowFull']);newhigh=C.read(bpy.data.objects['BoundaryHighFull'])
    assert fingerprint(newlow)==low_hash and fingerprint(newhigh,False)==high_geo_hash and np.array_equal(newhigh['materials'],expected)
    assert graph(newlow['mesh'].materials[0])==low_graph and scene_lock(bpy.context.scene)==camera
    images=C.images_before_save();assert {x['path']:x['sha256'] for x in images}==image_sha
    C.write('actual_reopen.json',{'high_material_mapping_exact':True,'low_geometry_UV_normals_material_graph_exact':True,'high_geometry_UV_normals_exact':True,'images':images,'camera_lights_exact':True})
    scene=bpy.context.scene;scene.cycles.device='CPU';scene.cycles.samples=24;renders=[]
    for ob,name in [(newhigh['object'],'01_high_source_corrected.png'),(newlow['object'],'02_low_unchanged.png')]:
        assert scene_lock(scene)==camera
        visibility([ob.name]+context);scene.render.filepath=str(C.OUT/name);bpy.ops.render.render(write_still=True)
        p=C.OUT/name;renders.append({'path':str(p),'bytes':p.stat().st_size,'sha256':C.sha(p)});C.write('render_checkpoint.json',renders)
    assert verify()==before and C.verify_inputs()==oldinputs and C.sha(saved)==saved_sha
    C.write('result.json',{'status':'MATERIAL_DISPLAY_REPAIR_PENDING_IMAGE_REVIEW','pid':os.getpid(),'seconds':time.monotonic()-start,'blend':str(saved),'sha256':saved_sha,'renders':renders,'no_rebake':True,'source_hashes_unchanged':True})


if __name__=='__main__':
    try:main()
    except Exception as exc:
        C.write('failure.json',{'status':'FAIL_STOP','exception':repr(exc),'traceback':traceback.format_exc(),'pid':os.getpid()});raise
