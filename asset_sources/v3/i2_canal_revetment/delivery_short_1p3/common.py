"""Offline 1.3m crop delivery, adapted from the frozen verified 4m workflow.
All mutations stay in delivery_short_1p3. Import never starts an engine.
"""
from pathlib import Path
import hashlib, json, math, struct, shutil, sys
sys.dont_write_bytecode = True
import bpy
from mathutils import Matrix, Vector

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[3]
SOURCE = OUT.parent/'delivery_p4/i2_canal_revetment_editable.blend'
SOURCE_SHA = '2e14f59de71971596226af0ecf2c2d59ea4b8e6bffea60c07d2a0308ac563b71'
SIZE = 2048
TRIANGLES = None  # actual cropped count is measured; never inherited
UVS = ['SurfaceMetric','FrontFaceUV']
ATTRS = ['SourceHeight','SourceX','WaterFacing','RepairUse','ExposedSurface']
ROOT_NAME = 'I2CanalRevetment'
MESH_NAME = 'RevetmentSurface'
MATERIAL_NAME = 'I2Revetment_PBR'

def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def gp(p): return [p[0],p[2],-p[1]]
def bp(p): return Vector((p[0],-p[2],p[1]))
def write_json(p,v): Path(p).write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def select(objects):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:
        o.hide_set(False);o.hide_viewport=False;o.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
def shader(material):
    nodes=[n for n in material.node_tree.nodes if n.type=='BSDF_PRINCIPLED']
    assert len(nodes)==1,material.name
    return nodes[0]

def audit_images(label):
    rows=[]
    for im in bpy.data.images:
        if im.source!='FILE' or not im.filepath:continue
        p=Path(bpy.path.abspath(im.filepath)).resolve();assert p.is_file(),(label,im.name,str(p))
        im.reload();first=tuple(im.pixels[:4]);k=(int(im.size[0])*int(im.size[1])//2)*4;middle=tuple(im.pixels[k:k+4])
        assert len(first)==4 and len(middle)==4 and im.has_data and min(im.size)>0,(label,im.name,first,middle)
        rows.append({'name':im.name,'path':str(p),'sha256':sha(p),'size':list(im.size),'first_pixel':first,'middle_pixel':middle,'colorspace':im.colorspace_settings.name})
    return rows

def copy_inputs():
    original=audit_images('original source before checkpoint')
    assert {r['sha256'] for r in original} == {
        '11db122c63d06f7fcd25f5614f19cd0efee1b09997149071b993ed6eff7e8406',
        '32df77336c0abf940f7db69ee85e4f22f9eb64af22dc881d8c2e762b73861cba'}
    assert len(original)==2 and all(r['colorspace']=='sRGB' for r in original)
    (OUT/'source_inputs').mkdir(exist_ok=True)
    for im in bpy.data.images:
        if im.source!='FILE' or not im.filepath:continue
        p=Path(bpy.path.abspath(im.filepath)).resolve();dst=OUT/'source_inputs'/p.name
        if dst.exists():assert sha(dst)==sha(p)
        else:shutil.copyfile(p,dst)
        im.filepath=str(dst.resolve())
    return {'original':original,'copies':audit_images('absolute copies before checkpoint')}

def audit_material(material):
    pending=[shader(material)];seen=set();rows=[]
    while pending:
        n=pending.pop()
        if n.name in seen:continue
        seen.add(n.name)
        assert n.type not in {'TEX_COORD','NEW_GEOMETRY','OBJECT_INFO'},(material.name,n.type)
        if n.type.startswith('TEX_') and 'Vector' in n.inputs:assert n.inputs['Vector'].is_linked,(material.name,n.name)
        if n.type=='UVMAP':assert n.uv_map in UVS,(material.name,n.uv_map)
        if n.type=='ATTRIBUTE':assert n.attribute_name in ATTRS,(material.name,n.attribute_name)
        if n.type=='NORMAL_MAP':assert n.uv_map in UVS and n.space=='TANGENT'
        pending.extend(l.from_node for s in n.inputs for l in s.links)
        rows.append({'name':n.name,'type':n.type})
    return {'material':material.name,'explicit_uv_attributes_only':True,'active_nodes':rows,
            'normal_input_linked':shader(material).inputs['Normal'].is_linked}

def corner_fingerprint(mesh):
    h=hashlib.sha256()
    for name in UVS:
        for v in mesh.uv_layers[name].data:h.update(struct.pack('<2f',*v.uv))
    for name in ATTRS:
        for v in mesh.attributes[name].data:h.update(struct.pack('<f',v.value))
    return h.hexdigest()

def make_proxy(parts):
    dg=bpy.context.evaluated_depsgraph_get();vertices=[];faces=[];mids=[];normals=[];uv={n:[] for n in UVS};attrs={n:[] for n in ATTRS};materials=[];rows=[]
    for o in sorted(parts,key=lambda o:o.name):
        assert o.matrix_world.to_3x3().determinant()>0,o.name
        me=bpy.data.meshes.new_from_object(o.evaluated_get(dg),preserve_all_data_layers=True,depsgraph=dg);me.calc_loop_triangles()
        base=len(vertices);vertices.extend(tuple(o.matrix_world@v.co) for v in me.vertices)
        normal_matrix=o.matrix_world.to_3x3().inverted().transposed()
        rows.append({'name':o.name,'triangles':len(me.loop_triangles),'source_matrix':list(v for row in o.matrix_world for v in row)})
        for tri in me.loop_triangles:
            mat=me.materials[me.polygons[tri.polygon_index].material_index]
            if mat not in materials:materials.append(mat)
            faces.append(tuple(base+i for i in tri.vertices));mids.append(materials.index(mat))
            for li in tri.loops:
                normals.append(tuple((normal_matrix@me.corner_normals[li].vector).normalized()))
                for name in UVS:uv[name].append(tuple(me.uv_layers[name].data[li].uv) if name in me.uv_layers else (0.,0.))
                for name in ATTRS:
                    a=me.attributes.get(name)
                    if a is None:
                        assert name=='ExposedSurface', (o.name,name)
                        attrs[name].append(0.)
                    else:
                        assert a.domain=='CORNER' and a.data_type=='FLOAT',(o.name,name)
                        attrs[name].append(a.data[li].value)
        bpy.data.meshes.remove(me)
    assert len(faces)==sum(r['triangles'] for r in rows) and len(normals)==len(faces)*3
    mesh=bpy.data.meshes.new('Short_ExactSourceTriangles_BakeProxy');mesh.from_pydata(vertices,[],faces);mesh.update()
    for m in materials:mesh.materials.append(m)
    for poly,face,mid in zip(mesh.polygons,faces,mids):
        assert tuple(poly.vertices)==face
        poly.material_index=mid;poly.use_smooth=True
    mesh.normals_split_custom_set(normals)
    for name,values in uv.items():
        mesh.uv_layers.new(name=name)
        for target,value in zip(mesh.uv_layers[name].data,values):target.uv=value
    for name,values in attrs.items():
        mesh.attributes.new(name=name,type='FLOAT',domain='CORNER')
        for target,value in zip(mesh.attributes[name].data,values):target.value=value
    assert all(tuple(t.uv)==v for name,values in uv.items() for t,v in zip(mesh.uv_layers[name].data,values))
    assert all(t.value==v for name,values in attrs.items() for t,v in zip(mesh.attributes[name].data,values))
    proxy=bpy.data.objects.new('DeliveryBakeProxy',mesh);bpy.context.scene.collection.objects.link(proxy)
    assert proxy.matrix_world==Matrix.Identity(4)
    for o in parts:o.hide_render=True;o.hide_set(True)
    return proxy,rows,[audit_material(m) for m in materials]

def unique_uv(proxy):
    mesh=proxy.data;before=corner_fingerprint(mesh)
    mesh.uv_layers.new(name='DeliveryBakeUV');mesh.uv_layers.active_index=mesh.uv_layers.find('DeliveryBakeUV')
    for layer in mesh.uv_layers:layer.active_render=layer.name=='DeliveryBakeUV'
    select([proxy]);bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(66),island_margin=.004)
    bpy.ops.object.mode_set(mode='OBJECT');assert corner_fingerprint(mesh)==before
    uv=mesh.uv_layers['DeliveryBakeUV'];values=[float(v) for loop in uv.data for v in loop.uv]
    assert all(math.isfinite(v) and -1e-6<=v<=1.000001 for v in values)
    mesh.calc_loop_triangles();areas=[]
    for tri in mesh.loop_triangles:
        a,b,c=[uv.data[i].uv.copy() for i in tri.loops]
        areas.append(abs((b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x))*.5)
    if not all(a>1e-14 for a in areas):
        bad=[]
        for i,(tri,area) in enumerate(zip(mesh.loop_triangles,areas)):
            if area>1e-14:continue
            ps=[mesh.vertices[j].co.copy() for j in tri.vertices]
            bad.append({'triangle':i,'vertices':list(tri.vertices),'uv_area':area,'area_3d':tri.area,
                'positions_blender':[list(p) for p in ps],'positions_godot':[gp(p) for p in ps],
                'normal':list(tri.normal),'edge_lengths':[(ps[(j+1)%3]-ps[j]).length for j in range(3)],
                'bake_uv':[list(uv.data[j].uv) for j in tri.loops],
                'source_uv':{name:[list(mesh.uv_layers[name].data[j].uv) for j in tri.loops] for name in UVS}})
        write_json(OUT/'last_uv_failure.json',{'triangles':len(areas),'bad_count':len(bad),'bad_triangles':bad})
        bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'last_uv_failure.blend'),relative_remap=False)
        raise AssertionError('collapsed BakeUV triangle; exact failed triangles and blend saved')
    return {'loops':len(values)//2,'sha256':hashlib.sha256(struct.pack('<'+'f'*len(values),*values)).hexdigest(),
            'source_uv_attribute_fingerprint_before_after':before,'size':SIZE,'margin':.004,'minimum_uv_area':min(areas),'summed_uv_area':sum(areas),
            'scope':'native unwrap / finite noncollapsed triangles, not exhaustive independent overlap proof'}

def bake(proxy,channel):
    print('BAKE_BEGIN '+channel,flush=True);(OUT/'textures').mkdir(exist_ok=True)
    image=bpy.data.images.new('I2Revetment_'+channel,width=SIZE,height=SIZE,alpha=False,float_buffer=False)
    image.colorspace_settings.name='sRGB' if channel=='BaseColor' else 'Non-Color';restore=[]
    try:
        for material in proxy.data.materials:
            nodes,links=material.node_tree.nodes,material.node_tree.links;p=shader(material)
            output=next(n for n in nodes if n.type=='OUTPUT_MATERIAL' and n.is_active_output)
            old=output.inputs['Surface'].links[0].from_socket;temporary=[];restore.append((material,output,old,temporary))
            if channel!='Normal':
                emit=nodes.new('ShaderNodeEmission');emit.inputs['Strength'].default_value=1;temporary.append(emit)
                if channel=='BaseColor':
                    source=p.inputs['Base Color']
                    if source.is_linked:links.new(source.links[0].from_socket,emit.inputs['Color'])
                    else:emit.inputs['Color'].default_value=source.default_value
                else:
                    combine=nodes.new('ShaderNodeCombineColor');combine.mode='RGB';combine.inputs['Red'].default_value=1;temporary.append(combine)
                    for ch,key in [('Green','Roughness'),('Blue','Metallic')]:
                        source=p.inputs[key]
                        if source.is_linked:links.new(source.links[0].from_socket,combine.inputs[ch])
                        else:combine.inputs[ch].default_value=source.default_value
                    links.new(combine.outputs[0],emit.inputs['Color'])
                links.new(emit.outputs[0],output.inputs['Surface'])
            target=nodes.new('ShaderNodeTexImage');target.image=image;temporary.append(target)
            for node in nodes:node.select=False
            target.select=True;nodes.active=target
        select([proxy]);scene=bpy.context.scene
        scene.render.bake.normal_space='TANGENT';scene.render.bake.normal_r='POS_X';scene.render.bake.normal_g='POS_Y';scene.render.bake.normal_b='POS_Z'
        bpy.ops.object.bake(type='NORMAL' if channel=='Normal' else 'EMIT',use_clear=True,margin=8,use_selected_to_active=False)
        image.filepath_raw=str(OUT/'textures'/('I2Revetment_'+channel+'.png'));image.file_format='PNG';image.save()
    finally:
        for material,output,old,temporary in restore:
            material.node_tree.links.new(old,output.inputs['Surface'])
            for node in temporary:material.node_tree.nodes.remove(node)
    loaded=bpy.data.images.load(image.filepath_raw,check_existing=False);loaded.colorspace_settings.name=image.colorspace_settings.name
    first=tuple(loaded.pixels[:4]);assert loaded.has_data and len(first)==4 and tuple(loaded.size)==(SIZE,SIZE)
    print('BAKE_DONE '+channel,flush=True)
    return {'channel':channel,'path':image.filepath_raw,'sha256':sha(image.filepath_raw),'size':list(loaded.size),'colorspace':loaded.colorspace_settings.name,
            'scope':'RGB=1,roughness,metallic; no AO baked' if channel=='ORM' else 'source tangent normal response; no image-color height conversion' if channel=='Normal' else 'albedo-only emission pass, no studio lighting'}
