"""Owned crown-only UV/PBR baking. No shared helpers or game engine side effects.

Temporary meshes combine each material for efficient baking, then copy only UVs
back to the original 76 independently moving pieces. AO is local crevice shading;
no direct/indirect studio lighting is baked. Images use the same target PaintUV.
"""
import bpy, math, hashlib

def bake_pbr(scene, meshes, materials, output, version):
    original_visibility={o:o.hide_render for o in meshes}
    studio_visibility={o:o.hide_render for o in bpy.data.collections['Studio_NOT_EXPORTED'].objects if o.type=='MESH'}
    for o in studio_visibility:o.hide_render=True
    groups={kind:[o for o in meshes if o.data.materials[0]==mat] for kind,mat in materials.items()}
    temps={}; mapping={}; metadata=[]; baked={}
    bpy.ops.object.select_all(action='DESELECT')
    for kind,group in groups.items():
        vertices=[];faces=[];source=[];smooth=[]
        for o in group:
            offset=len(vertices);vertices.extend(tuple(o.matrix_world@v.co) for v in o.data.vertices)
            for poly in o.data.polygons:
                faces.append(tuple(offset+i for i in poly.vertices));source.append((o,poly.index));smooth.append(poly.use_smooth)
        data=bpy.data.meshes.new('_CrownBake_'+kind);data.from_pydata(vertices,[],faces);data.update()
        temp=bpy.data.objects.new('_CrownBake_'+kind,data);scene.collection.objects.link(temp);data.materials.append(materials[kind])
        detail=data.uv_layers.new(name='DetailUV');target=data.uv_layers.new(name='PaintUV')
        for poly,(o,index),use_smooth in zip(data.polygons,source,smooth):
            poly.use_smooth=use_smooth
            for li,old_li in zip(poly.loop_indices,o.data.polygons[index].loop_indices):
                detail.data[li].uv=o.data.uv_layers.active.data[old_li].uv
        data.uv_layers.active=target;target.active_render=True
        for node in materials[kind].node_tree.nodes:
            if node.type=='UVMAP':node.uv_map='DetailUV'
            elif node.type=='TEX_IMAGE' and not node.inputs['Vector'].is_linked:
                uvnode=materials[kind].node_tree.nodes.new('ShaderNodeUVMap');uvnode.uv_map='DetailUV'
                materials[kind].node_tree.links.new(uvnode.outputs['UV'],node.inputs['Vector'])
            elif node.type=='NORMAL_MAP':node.uv_map='DetailUV'
        temp.select_set(True);bpy.context.view_layer.objects.active=temp
        bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.uv.smart_project(angle_limit=math.radians(66),island_margin=.012,area_weight=.6,correct_aspect=True,scale_to_bounds=True)
        bpy.ops.object.mode_set(mode='OBJECT');temp.select_set(False)
        temps[kind]=temp;mapping[kind]=source
    for o in meshes:o.hide_render=True
    scene.render.engine='CYCLES';scene.cycles.samples=12
    scene.render.bake.use_selected_to_active=False;scene.render.bake.use_clear=True;scene.render.bake.margin=12
    scene.render.bake.margin_type='EXTEND';scene.render.bake.normal_space='TANGENT'
    for kind,temp in temps.items():
        mat=materials[kind];mat.name=mat.name+'_AUTHOR';mat.use_fake_user=True
        nodes=mat.node_tree.nodes;links=mat.node_tree.links
        out=next(n for n in nodes if n.type=='OUTPUT_MATERIAL');p=next(n for n in nodes if n.type=='BSDF_PRINCIPLED')
        emission=nodes.new('ShaderNodeEmission');emission.inputs['Strength'].default_value=1
        target=nodes.new('ShaderNodeTexImage');target.name='ACTIVE_BAKE_TARGET'
        size=2048 if kind in ('stone','bark') else 1024
        images={}
        bpy.ops.object.select_all(action='DESELECT');temp.select_set(True);bpy.context.view_layer.objects.active=temp
        channels=['basecolor','roughness','normal']+(['emission'] if kind=='core' else [])
        for channel in channels:
            name=kind+'_'+channel+'_'+version;img=bpy.data.images.new(name,width=size,height=size,alpha=False,float_buffer=False)
            img.colorspace_settings.name='Non-Color' if channel in ('roughness','normal') else 'sRGB'
            target.image=img
            for n in nodes:n.select=False
            target.select=True;nodes.active=target
            if channel=='normal':
                links.new(p.outputs['BSDF'],out.inputs['Surface']);bake_type='NORMAL'
            else:
                source_socket=p.inputs[{'basecolor':'Base Color','roughness':'Roughness','emission':'Emission Color'}[channel]]
                for link in list(emission.inputs['Color'].links):links.remove(link)
                if source_socket.is_linked:links.new(source_socket.links[0].from_socket,emission.inputs['Color'])
                else:
                    value=source_socket.default_value
                    emission.inputs['Color'].default_value=(value,value,value,1) if isinstance(value,float) else value
                links.new(emission.outputs[0],out.inputs['Surface']);bake_type='EMIT'
            print('CROWN_BAKE_START',kind,channel,size,flush=True)
            bpy.ops.object.bake(type=bake_type)
            img.file_format='PNG';img.filepath_raw=str(output/(name+'.png'));img.save();img.pack()
            path=output/(name+'.png');metadata.append({'file':str(path),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'width':size,'height':size,'role':channel,'material':kind,'bytes':path.stat().st_size})
            images[channel]=img
            print('CROWN_BAKE_END',kind,channel,flush=True)
        links.new(p.outputs['BSDF'],out.inputs['Surface']);nodes.remove(emission);nodes.remove(target)
        result=bpy.data.materials.new(mat.name.removesuffix('_AUTHOR'));result.use_nodes=True
        rn=result.node_tree.nodes;rn.clear();rl=result.node_tree.links
        ro=rn.new('ShaderNodeOutputMaterial');rp=rn.new('ShaderNodeBsdfPrincipled');rl.new(rp.outputs['BSDF'],ro.inputs['Surface'])
        rp.inputs['Metallic'].default_value=0;rp.inputs['Specular IOR Level'].default_value=.20
        uv=rn.new('ShaderNodeUVMap');uv.uv_map='PaintUV'
        for channel,img in images.items():
            tex=rn.new('ShaderNodeTexImage');tex.image=img;tex.extension='EXTEND';rl.new(uv.outputs['UV'],tex.inputs['Vector'])
            if channel=='normal':
                normal=rn.new('ShaderNodeNormalMap');normal.uv_map='PaintUV';normal.inputs['Strength'].default_value=1
                rl.new(tex.outputs['Color'],normal.inputs['Color']);rl.new(normal.outputs[0],rp.inputs['Normal'])
            else:rl.new(tex.outputs['Color'],rp.inputs[{'basecolor':'Base Color','roughness':'Roughness','emission':'Emission Color'}[channel]])
        if kind=='core':rp.inputs['Emission Strength'].default_value=.30;result['rest_emission_strength']=.30;result['controlled_core_material']=True
        result['surface_source']='imagegen material color + source geometric cavity, baked only to PaintUV; tangent normal from authored bump'
        result['bake_margin_px']=12;result['normal_convention']='OpenGL tangent, Non-Color'
        for poly,(o,index) in zip(temp.data.polygons,mapping[kind]):
            for li,old_li in zip(poly.loop_indices,o.data.polygons[index].loop_indices):
                o.data.uv_layers.active.data[old_li].uv=temp.data.uv_layers['PaintUV'].data[li].uv
        for o in groups[kind]:o.data.materials.clear();o.data.materials.append(result)
        baked[kind]=result
    for temp in temps.values():
        data=temp.data;bpy.data.objects.remove(temp,do_unlink=True);bpy.data.meshes.remove(data)
    for o,hidden in original_visibility.items():o.hide_render=hidden
    for o,hidden in studio_visibility.items():o.hide_render=hidden
    bpy.context.view_layer.update()
    return baked,metadata
