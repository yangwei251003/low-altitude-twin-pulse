"""Low-cost P3 delivery: lighting-free 1K material bake, five visual groups.

The approved editable P3 is read-only. This script runs only in Root's engine
window. It does not render a new concept, alter collision, or modify game state.
"""
from pathlib import Path
import bpy, hashlib, json, math, os, sys, time
from mathutils import Matrix
sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
SOURCE = HERE.parent/'p3/runs/20261020_100415_51449c/output/f1_thermal_stone_editable.blend'
SOURCE_SHA = '9547909f7ea2a84e7aa6d5055de50659040989688115a52714403f0e276b7028'
OUT = Path(os.environ['THERMAL_DELIVERY_OUT']).resolve()
assert OUT.is_relative_to(HERE)

def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def dump(name,data): (OUT/name).write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
def select(objects):
    bpy.ops.object.select_all(action='DESELECT')
    for ob in objects: ob.hide_set(False);ob.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]

def plain(name):
    mat=bpy.data.materials.new(name);mat.use_nodes=True;mat.use_backface_culling=True
    nodes=mat.node_tree.nodes;links=mat.node_tree.links;nodes.clear()
    bs=nodes.new('ShaderNodeBsdfPrincipled');out=nodes.new('ShaderNodeOutputMaterial');links.new(bs.outputs[0],out.inputs[0])
    bs.inputs['Metallic'].default_value=0;bs.inputs['Roughness'].default_value=.6
    return mat,bs,nodes,links

def bake_static(ob):
    source=ob.data.materials[0]
    assert len(ob.data.materials)==1
    select([ob]);uv=ob.data.uv_layers.new(name='DeliveryUV');ob.data.uv_layers.active=uv;uv.active_render=True
    bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(66),island_margin=.015)
    bpy.ops.object.mode_set(mode='OBJECT')
    nodes=source.node_tree.nodes;links=source.node_tree.links
    bs=next(n for n in nodes if n.type=='BSDF_PRINCIPLED');output=next(n for n in nodes if n.type=='OUTPUT_MATERIAL')
    old_surface=output.inputs['Surface'].links[0].from_socket
    emission=nodes.new('ShaderNodeEmission');maps={}
    for channel,socket in [('BaseColor','Base Color'),('Roughness','Roughness'),('Normal',None)]:
        im=bpy.data.images.new(ob.name+'_'+channel,width=1024,height=1024,alpha=False)
        im.colorspace_settings.name='sRGB' if channel=='BaseColor' else 'Non-Color'
        tex=nodes.new('ShaderNodeTexImage');tex.image=im;nodes.active=tex
        if channel=='Normal':
            links.new(old_surface,output.inputs['Surface'])
            bpy.ops.object.bake(type='NORMAL',normal_space='TANGENT',use_clear=True,margin=8)
        else:
            inp=bs.inputs[socket]
            if inp.is_linked: links.new(inp.links[0].from_socket,emission.inputs['Color'])
            else:
                for link in list(emission.inputs['Color'].links):links.remove(link)
                value=inp.default_value
                emission.inputs['Color'].default_value=(value,value,value,1) if isinstance(value,float) else value
            emission.inputs['Strength'].default_value=1;links.new(emission.outputs[0],output.inputs['Surface'])
            bpy.ops.object.bake(type='EMIT',use_clear=True,margin=8)
        path=OUT/(ob.name+'_'+channel+'.png');im.filepath_raw=str(path);im.file_format='PNG';im.save()
        maps[channel]={'path':str(path),'sha256':sha(path),'size':[1024,1024]}
        nodes.remove(tex)
    links.new(old_surface,output.inputs['Surface']);nodes.remove(emission)
    mat,bs,nodes,links=plain(ob.name+'_PBR');uvnode=nodes.new('ShaderNodeUVMap');uvnode.uv_map='SurfaceUV'
    for channel,socket in [('BaseColor','Base Color'),('Roughness','Roughness'),('Normal','Normal')]:
        im=bpy.data.images.load(maps[channel]['path'],check_existing=False)
        im.colorspace_settings.name='sRGB' if channel=='BaseColor' else 'Non-Color'
        tex=nodes.new('ShaderNodeTexImage');tex.image=im;links.new(uvnode.outputs[0],tex.inputs['Vector'])
        if channel=='Normal':
            normal=nodes.new('ShaderNodeNormalMap');normal.uv_map='SurfaceUV';normal.inputs['Strength'].default_value=1
            links.new(tex.outputs['Color'],normal.inputs['Color']);links.new(normal.outputs[0],bs.inputs['Normal'])
        else:links.new(tex.outputs['Color'],bs.inputs[socket])
    for layer in list(ob.data.uv_layers):
        if layer.name!='DeliveryUV':ob.data.uv_layers.remove(layer)
    ob.data.uv_layers[0].name='SurfaceUV';ob.data.materials.clear();ob.data.materials.append(mat)
    for attr in list(ob.data.color_attributes):ob.data.color_attributes.remove(attr)
    return maps

def main():
    start=time.monotonic();assert sha(SOURCE)==SOURCE_SHA
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    keep=list(bpy.data.collections['F1ThermalStone_EDITABLE'].objects)
    for ob in list(bpy.data.objects):
        if ob not in keep or ob.type!='MESH':bpy.data.objects.remove(ob,do_unlink=True)
    # Export groups share the source materials; the two roots become one draw.
    groups={}
    for ob in list(bpy.data.objects):
        ob.parent=None
        key={'FT_WarmFacetedStone':'StoneBody','FT_ContinuousBark':'RootBindings','FT_SparseMoss':'Moss',
             'FT_TemperatureCore':'TemperatureCore','FT_HeatInlays':'HeatInlays'}[ob.data.materials[0].name]
        groups.setdefault(key,[]).append(ob)
    merged=[]
    for name,objects in groups.items():
        select(objects)
        if len(objects)>1:bpy.ops.object.join()
        ob=bpy.context.object;ob.name=name;assert ob.matrix_world==Matrix.Identity(4);merged.append(ob)
    sc=bpy.context.scene;sc.render.engine='CYCLES';sc.cycles.device='CPU';sc.cycles.samples=1
    sc.render.threads_mode='FIXED';sc.render.threads=2
    baked={}
    for ob in merged:
        if ob.name not in ('TemperatureCore','HeatInlays'):baked[ob.name]=bake_static(ob)
        else:
            attr=ob.data.color_attributes.get('CoreFacet');values=[tuple(v.color) for v in attr.data] if attr else [(1,1,1,1)]*len(ob.data.loops)
            for a in list(ob.data.color_attributes):ob.data.color_attributes.remove(a)
            colors=ob.data.color_attributes.new(name='RuntimeColor',type='FLOAT_COLOR',domain='CORNER')
            for entry,value in zip(colors.data,values):entry.color=value
            ob.data.color_attributes.render_color_index=0
            ob.data.color_attributes.active_color_index=0
            mat,bs,_,_=plain(ob.name+'_NeutralState');bs.inputs['Base Color'].default_value=(.61,.64,.61,1)
            bs.inputs['Roughness'].default_value=.41 if ob.name=='TemperatureCore' else .48
            ob.data.materials.clear();ob.data.materials.append(mat)
    root=bpy.data.objects.new('F1ThermalStone',None);sc.collection.objects.link(root)
    for ob in merged:ob.parent=root
    counts={ob.name:sum(len(p.vertices)-2 for p in ob.data.polygons) for ob in merged};assert sum(counts.values())==7896
    points=[ob.matrix_world@v.co for ob in merged for v in ob.data.vertices]
    godot=[(p.x,p.z,-p.y) for p in points]
    bounds=[[min(p[k] for p in godot) for k in range(3)],[max(p[k] for p in godot) for k in range(3)]]
    assert all(-1.5<=p[0]<=1.5 and 0<=p[1]<=2 and -1<=p[2]<=1 for p in godot)
    blend=OUT/'f1_thermal_stone_delivery.blend';bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    bpy.ops.wm.open_mainfile(filepath=str(blend));select([o for o in bpy.data.objects if o.type in ('MESH','EMPTY')])
    glb=OUT/'f1_thermal_stone.glb'
    bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,export_yup=True,
        export_apply=False,export_texcoords=True,export_normals=True,export_tangents=True,export_materials='EXPORT',
        export_vertex_color='ACTIVE',export_all_vertex_colors=False,export_cameras=False,export_lights=False,export_animations=False)
    assert sha(SOURCE)==SOURCE_SHA
    dump('delivery_report.json',{'status':'EXPORTED_PENDING_GODOT_CAMERA_CHECK','seconds':time.monotonic()-start,
        'source':str(SOURCE),'source_sha256':SOURCE_SHA,'source_unchanged':True,'delivery_blend':str(blend),
        'glb':str(glb),'glb_sha256':sha(glb),'bytes':glb.stat().st_size,'mesh_triangles':counts,'materials':5,
        'bounds_godot':bounds,'lighting_free_baked_maps':baked,'collision':'none; original entity box must stay',
        'scope':'P3 geometry retained; 1K base/roughness/tangent-normal maps; neutral separate temperature material; no runtime check'})
    print('THERMAL_DELIVERY_PASS '+str(glb),flush=True)

if __name__=='__main__':main()
