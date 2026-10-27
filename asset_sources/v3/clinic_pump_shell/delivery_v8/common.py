from pathlib import Path
import bpy,json,hashlib,math,struct,shutil
from mathutils import Vector,Matrix
OUT=Path(__file__).resolve().parent;ROOT=OUT.parents[3]
SOURCE=OUT.parent/'prototype_v8/pump_shell_prototype.blend'
SOURCE_SHA='ab35e616404bc156ada04e7bccdb189d7c4438ff362d768b839c298dd90e1e3d'
ASSETS=ROOT/'assets/v3/clinic_pump_shell';SIZE=2048
GROUPS=['FloorSurface','WallFeetAndJambs','WestCover','EastCover','NorthCover','RoofCover']
UVS=['MetricUV','PanelUV','FinishUV','SteelUV']
COLORS=['WearControl','UVPhase','FaceSize','SurfaceUse']
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def gp(p):return [p[0],p[2],-p[1]]
def select(objs):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:o.hide_set(False);o.hide_viewport=False;o.select_set(True)
    bpy.context.view_layer.objects.active=objs[0]
def bs(m):
    n=[n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED'];assert len(n)==1,m.name
    return n[0]
def audit_material(m):
    shader=bs(m);pending=[shader];seen={};rows=[]
    while pending:
        n=pending.pop()
        if n.name in seen:continue
        seen[n.name]=n
        assert n.type not in {'TEX_COORD','NEW_GEOMETRY','OBJECT_INFO'},(m.name,n.name,n.type)
        if n.type.startswith('TEX_') and 'Vector' in n.inputs:assert n.inputs['Vector'].is_linked,(m.name,n.name,'implicit position')
        if n.type=='UVMAP':assert n.uv_map in UVS,(m.name,n.uv_map)
        if n.type=='VERTEX_COLOR':assert n.layer_name in COLORS,(m.name,n.layer_name)
        if n.type=='NORMAL_MAP':assert n.uv_map in UVS and n.space=='TANGENT'
        pending.extend(l.from_node for s in n.inputs for l in s.links)
        rows.append({'node':n.name,'type':n.type})
    return {'material':m.name,'active_nodes':rows,'explicit_uv_corner_attributes_only':True}
def triangles(o):
    me=o.data;me.calc_loop_triangles();rows=[]
    for t in me.loop_triangles:
        row={'positions':[gp(o.matrix_world@me.vertices[i].co) for i in t.vertices]}
        if 'SurfaceUV' in me.uv_layers:row['uv']=[list(me.uv_layers['SurfaceUV'].data[i].uv) for i in t.loops]
        rows.append(row)
    return rows
def copy_inputs():
    (OUT/'source_inputs').mkdir(exist_ok=True);rows=[]
    for im in bpy.data.images:
        if im.source!='FILE' or not im.filepath:continue
        src=Path(bpy.path.abspath(im.filepath));dst=OUT/'source_inputs'/src.name
        if dst.exists():assert sha(src)==sha(dst)
        else:shutil.copyfile(src,dst)
        im.filepath=str(dst);rows.append({'source':str(src),'copy':str(dst),'sha256':sha(dst),'colorspace':im.colorspace_settings.name})
    return rows
def make_proxy(parts):
    """Explicit source loop-triangles, named UVs and corner attrs; no transform shader."""
    dg=bpy.context.evaluated_depsgraph_get();verts=[];faces=[];mids=[];smooth=[];normals=[];uv={k:[] for k in UVS};cols={k:[] for k in COLORS};groups=[];materials=[];source_rows=[]
    for o in sorted(parts,key=lambda x:x.name):
        assert o.matrix_world==Matrix.Identity(4),o.name
        me=bpy.data.meshes.new_from_object(o.evaluated_get(dg),preserve_all_data_layers=True,depsgraph=dg);me.calc_loop_triangles()
        base=len(verts);verts.extend(tuple(v.co) for v in me.vertices)
        source_rows.append({'object':o.name,'group':o['runtime_group'],'triangles':len(me.loop_triangles)})
        for t in me.loop_triangles:
            mat=me.materials[me.polygons[t.polygon_index].material_index]
            if mat not in materials:materials.append(mat)
            faces.append(tuple(base+i for i in t.vertices));mids.append(materials.index(mat));groups.append(GROUPS.index(o['runtime_group']))
            for li in t.loops:
                normals.append(tuple(me.corner_normals[li].vector))
                for k in UVS:uv[k].append(tuple(me.uv_layers[k].data[li].uv) if k in me.uv_layers else (0,0))
                for k in COLORS:
                    attr=me.color_attributes.get(k);assert attr is not None and attr.domain=='CORNER',(o.name,k)
                    cols[k].append(tuple(attr.data[li].color))
        bpy.data.meshes.remove(me)
    assert len(faces)==13600 and len(normals)==40800
    mesh=bpy.data.meshes.new('BakeProxy_Exact13600Triangles');mesh.from_pydata(verts,[],faces);mesh.update()
    for m in materials:mesh.materials.append(m)
    for poly,indices,mid in zip(mesh.polygons,faces,mids):
        assert tuple(poly.vertices)==indices;poly.material_index=mid;poly.use_smooth=True
    mesh.normals_split_custom_set(normals)
    for k,values in uv.items():
        mesh.uv_layers.new(name=k)
        for loop,value in zip(mesh.uv_layers[k].data,values):loop.uv=value
    for k,values in cols.items():
        mesh.color_attributes.new(name=k,type='FLOAT_COLOR',domain='CORNER')
        for c,value in zip(mesh.color_attributes[k].data,values):c.color=value
    assert all(tuple(l.uv)==tuple(v) for k,values in uv.items() for l,v in zip(mesh.uv_layers[k].data,values))
    assert all(tuple(c.color)==tuple(v) for k,values in cols.items() for c,v in zip(mesh.color_attributes[k].data,values))
    attr=mesh.attributes.new(name='DeliveryGroup',type='INT',domain='FACE')
    for a,g in zip(attr.data,groups):a.value=g
    proxy=bpy.data.objects.new('DeliveryBakeProxy',mesh);bpy.context.scene.collection.objects.link(proxy)
    for o in parts:o.hide_render=True;o.hide_set(True)
    return proxy,source_rows,[audit_material(m) for m in materials]
def unique_uv(proxy):
    me=proxy.data;me.uv_layers.new(name='DeliveryBakeUV');me.uv_layers.active_index=me.uv_layers.find('DeliveryBakeUV')
    for uv in me.uv_layers:uv.active_render=uv.name=='DeliveryBakeUV'
    select([proxy]);bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(66),island_margin=.004)
    bpy.ops.object.mode_set(mode='OBJECT')
    a=[float(v) for l in me.uv_layers['DeliveryBakeUV'].data for v in l.uv]
    assert all(math.isfinite(v) and -1e-6<=v<=1.000001 for v in a)
    return {'loops':len(a)//2,'float32_sha256':hashlib.sha256(struct.pack('<'+'f'*len(a),*a)).hexdigest(),'size':SIZE,'island_margin':.004}
def bake(proxy,channel):
    print('BAKE_BEGIN '+channel,flush=True);(OUT/'textures').mkdir(exist_ok=True)
    image=bpy.data.images.new('PumpV8_'+channel,width=SIZE,height=SIZE,alpha=False,float_buffer=False)
    image.colorspace_settings.name='sRGB' if channel=='BaseColor' else 'Non-Color'
    restore=[]
    for m in proxy.data.materials:
        n=m.node_tree.nodes;lk=m.node_tree.links;shader=bs(m);output=next(n for n in n if n.type=='OUTPUT_MATERIAL' and n.is_active_output)
        old=output.inputs['Surface'].links[0].from_socket;temporary=[]
        if channel!='Normal':
            emit=n.new('ShaderNodeEmission');emit.inputs['Strength'].default_value=1;temporary.append(emit)
            if channel=='BaseColor':
                socket=shader.inputs['Base Color']
                if socket.is_linked:lk.new(socket.links[0].from_socket,emit.inputs['Color'])
                else:emit.inputs['Color'].default_value=socket.default_value
            else:
                combine=n.new('ShaderNodeCombineColor');combine.mode='RGB';combine.inputs['Red'].default_value=1;temporary.append(combine)
                for ch,key in [('Green','Roughness'),('Blue','Metallic')]:
                    s=shader.inputs[key]
                    if s.is_linked:lk.new(s.links[0].from_socket,combine.inputs[ch])
                    else:combine.inputs[ch].default_value=s.default_value
                lk.new(combine.outputs[0],emit.inputs['Color'])
            lk.new(emit.outputs[0],output.inputs['Surface'])
        target=n.new('ShaderNodeTexImage');target.image=image;temporary.append(target)
        for node in n:node.select=False
        target.select=True;n.active=target;restore.append((m,output,old,temporary))
    select([proxy]);scene=bpy.context.scene;scene.render.bake.normal_space='TANGENT';scene.render.bake.normal_r='POS_X';scene.render.bake.normal_g='POS_Y';scene.render.bake.normal_b='POS_Z'
    bpy.ops.object.bake(type='NORMAL' if channel=='Normal' else 'EMIT',use_clear=True,margin=8,use_selected_to_active=False)
    image.filepath_raw=str(OUT/'textures'/('PumpV8_'+channel+'.png'));image.file_format='PNG';image.save()
    for m,output,old,temporary in restore:
        m.node_tree.links.new(old,output.inputs['Surface'])
        for n in temporary:m.node_tree.nodes.remove(n)
    loaded=bpy.data.images.load(image.filepath_raw,check_existing=False);loaded.colorspace_settings.name=image.colorspace_settings.name
    print('BAKE_DONE '+channel,flush=True)
    return {'channel':channel,'path':image.filepath_raw,'sha256':sha(image.filepath_raw),'colorspace':loaded.colorspace_settings.name,'size':list(loaded.size)}
