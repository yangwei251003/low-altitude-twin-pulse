"""Native cap-only PBR bake, explicit 12-mesh GLB, and same-byte previews.
Uses the repository's established emission/ORM/tangent-bake recipe. It never
rebakes or rescales the original 4m images and never writes runtime assets.
"""
import sys,os,time,json,math,struct,hashlib,collections,shutil,argparse
from pathlib import Path
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parent))
from prepare import *

def select(objects):
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:obj.hide_set(False);obj.hide_viewport=False;obj.hide_render=False;obj.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
def shader(material):
    values=[n for n in material.node_tree.nodes if n.type=='BSDF_PRINCIPLED'];assert len(values)==1
    return values[0]
def load_png(path,channel):
    image=bpy.data.images.load(str(path),check_existing=False)
    image.colorspace_settings.name='sRGB' if channel=='BaseColor' else 'Non-Color'
    first=tuple(image.pixels[:4]);assert image.has_data and len(first)==4
    return image

def bake_channel(proxy,channel):
    target=HERE/'cap_textures';target.mkdir(exist_ok=True)
    path=target/('ClosureCaps_'+channel+'.png');assert not path.exists(),'do not rebake an existing channel'
    image=bpy.data.images.new('ClosureCaps_'+channel,width=CAP_SIZE[0],height=CAP_SIZE[1],alpha=False,float_buffer=False)
    image.colorspace_settings.name='sRGB' if channel=='BaseColor' else 'Non-Color';restore=[]
    try:
        for material in proxy.data.materials:
            nodes,links=material.node_tree.nodes,material.node_tree.links;p=shader(material)
            output=next(n for n in nodes if n.type=='OUTPUT_MATERIAL' and n.is_active_output)
            old=output.inputs['Surface'].links[0].from_socket;temporary=[];restore.append((material,output,old,temporary))
            if channel!='Normal':
                emit=nodes.new('ShaderNodeEmission');temporary.append(emit);emit.inputs['Strength'].default_value=1
                if channel=='BaseColor':
                    source=p.inputs['Base Color']
                    if source.is_linked:links.new(source.links[0].from_socket,emit.inputs['Color'])
                    else:emit.inputs['Color'].default_value=source.default_value
                else:
                    combine=nodes.new('ShaderNodeCombineColor');temporary.append(combine);combine.mode='RGB';combine.inputs['Red'].default_value=1
                    for label,key in [('Green','Roughness'),('Blue','Metallic')]:
                        source=p.inputs[key]
                        if source.is_linked:links.new(source.links[0].from_socket,combine.inputs[label])
                        else:combine.inputs[label].default_value=source.default_value
                    links.new(combine.outputs[0],emit.inputs['Color'])
                links.new(emit.outputs[0],output.inputs['Surface'])
            texture=nodes.new('ShaderNodeTexImage');temporary.append(texture);texture.image=image
            for node in nodes:node.select=False
            texture.select=True;nodes.active=texture
        select([proxy]);scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=1
        scene.render.threads_mode='FIXED';scene.render.threads=2
        scene.render.bake.normal_space='TANGENT';scene.render.bake.normal_r='POS_X';scene.render.bake.normal_g='POS_Y';scene.render.bake.normal_b='POS_Z'
        bpy.ops.object.bake(type='NORMAL' if channel=='Normal' else 'EMIT',use_clear=True,margin=CAP_MARGIN,use_selected_to_active=False)
        image.filepath_raw=str(path);image.file_format='PNG';image.save()
    finally:
        for material,output,old,temporary in restore:
            material.node_tree.links.new(old,output.inputs['Surface'])
            for node in temporary:material.node_tree.nodes.remove(node)
    loaded=load_png(path,channel);assert tuple(loaded.size)==CAP_SIZE
    return {'path':str(path),'sha256':sha(path),'size':list(loaded.size),'colorspace':loaded.colorspace_settings.name}

def bake():
    report=json.loads((HERE/'prepared_report.json').read_text(encoding='utf-8'))
    assert sha(SOURCE)==SOURCE_SHA and sha(HERE/'prepared.blend')==report['blend_sha256']
    bpy.ops.wm.open_mainfile(filepath=str(HERE/'prepared.blend'))
    progress_path=HERE/'bake_report.json'
    result=json.loads(progress_path.read_text(encoding='utf-8')) if progress_path.exists() else {'status':'CAP_BAKE_IN_PROGRESS','prepared_sha256':report['blend_sha256'],'channels':{}}
    assert result['prepared_sha256']==report['blend_sha256']
    for channel in ['BaseColor','ORM','Normal']:
        if channel in result['channels']:
            row=result['channels'][channel];assert sha(row['path'])==row['sha256'];load_png(row['path'],channel)
            continue
        print(json.dumps({'stage':'cap_bake_begin','channel':channel,'pid':os.getpid()}),flush=True)
        result['channels'][channel]=bake_channel(bpy.data.objects['ClosureCapBakeProxy'],channel)
        dump(progress_path,result)
        print(json.dumps({'stage':'cap_bake_complete','channel':channel,'pid':os.getpid()}),flush=True)
    result['status']='CAP_BAKE_COMPLETE';result['reused_original_images_unchanged']=all(sha(v['path'])==v['sha256'] for v in report['reused_textures'].values())
    assert result['reused_original_images_unchanged'] and sha(SOURCE)==SOURCE_SHA
    dump(progress_path,result)

def final_material(name,maps):
    material=bpy.data.materials.new(name);material.use_nodes=True;material.use_backface_culling=True
    nodes,links=material.node_tree.nodes,material.node_tree.links;nodes.clear()
    p=nodes.new('ShaderNodeBsdfPrincipled');output=nodes.new('ShaderNodeOutputMaterial');links.new(p.outputs[0],output.inputs['Surface'])
    uv=nodes.new('ShaderNodeUVMap');uv.uv_map='SurfaceUV';textures={}
    for channel in ['BaseColor','ORM','Normal']:
        row=maps[channel];assert sha(row['path'])==row['sha256']
        node=nodes.new('ShaderNodeTexImage');node.image=load_png(row['path'],channel);node.extension='EXTEND'
        links.new(uv.outputs[0],node.inputs['Vector']);textures[channel]=node
    links.new(textures['BaseColor'].outputs['Color'],p.inputs['Base Color'])
    split=nodes.new('ShaderNodeSeparateColor');split.mode='RGB';links.new(textures['ORM'].outputs['Color'],split.inputs[0])
    links.new(split.outputs['Green'],p.inputs['Roughness']);links.new(split.outputs['Blue'],p.inputs['Metallic'])
    normal=nodes.new('ShaderNodeNormalMap');normal.uv_map='SurfaceUV';normal.space='TANGENT';normal.inputs['Strength'].default_value=1
    links.new(textures['Normal'].outputs['Color'],normal.inputs['Color']);links.new(normal.outputs[0],p.inputs['Normal'])
    p.inputs['Alpha'].default_value=1;p.inputs['Emission Strength'].default_value=0
    return material

def geometry_hash(triangles):
    rows=[]
    for points in triangles:
        key,_=canonical(points);rows.append(struct.pack('<9f',*(0. if v==0 else v for p in key for v in p)))
    return hashlib.sha256(b''.join(sorted(rows))).hexdigest()

def verify_glb(path,expected,prepared,maps):
    doc,binary,accessor=read_glb(path)
    assert not doc.get('animations') and not doc.get('skins') and not doc.get('cameras')
    assert len(doc['meshes'])==12 and len(doc['materials'])==2 and len(doc['nodes'])==13
    identity=[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1];records={};global_surfaces=0;max_uv=0.;max_normal=0.
    parent={child:index for index,node in enumerate(doc['nodes']) for child in node.get('children',[])}
    root_indices=[i for i in range(len(doc['nodes'])) if i not in parent];assert len(root_indices)==1
    root_index=root_indices[0];assert doc['nodes'][root_index]['name']=='I2RevetmentClosureDelivery'
    for index,node in enumerate(doc['nodes']):
        assert node.get('translation',[0,0,0])==[0,0,0] and node.get('rotation',[0,0,0,1])==[0,0,0,1] and node.get('scale',[1,1,1])==[1,1,1]
        assert node.get('matrix',identity)==identity
        if 'mesh' not in node:continue
        name=node['name'];assert name in expected and parent[index]==root_index and name not in records
        actual=collections.defaultdict(list);points=[];triangles=[];surface_count=0
        for primitive in doc['meshes'][node['mesh']]['primitives']:
            assert primitive.get('mode',4)==4;surface_count+=1;attrs=primitive['attributes'];assert 'TEXCOORD_1' not in attrs and 'TANGENT' in attrs
            ps,ns,uv=accessor(attrs['POSITION']),accessor(attrs['NORMAL']),accessor(attrs['TEXCOORD_0']);tangents=accessor(attrs['TANGENT'])
            assert all(abs(abs(t[3])-1)<1e-6 for t in tangents)
            ids=[v[0] for v in accessor(primitive['indices'])];assert len(ids)%3==0
            points.extend(ps)
            for first in range(0,len(ids),3):
                rows=[{'p':ps[i],'n':ns[i],'uv':(uv[i][0],1-uv[i][1])} for i in ids[first:first+3]]
                key,order=canonical([r['p'] for r in rows]);actual[key].append(rows[order:]+rows[:order]);triangles.append([r['p'] for r in rows])
        source=collections.defaultdict(list)
        for rows in expected[name]:
            key,order=canonical([r['p'] for r in rows]);source[key].append(rows[order:]+rows[:order])
        assert {k:len(v) for k,v in source.items()}=={k:len(v) for k,v in actual.items()},(name,'actual triangle/winding multiset')
        for key,values in source.items():
            sort=lambda row:tuple(v for c in row for v in c['uv'])
            for left,right in zip(sorted(values,key=sort),sorted(actual[key],key=sort)):
                for a,b in zip(left,right):
                    max_uv=max(max_uv,max(abs(x-y) for x,y in zip(a['uv'],b['uv'])))
                    max_normal=max(max_normal,normal_difference(a['n'],b['n'])['degrees'])
        assert len(triangles)==prepared['pieces'][name]['triangles']
        records[name]={'triangles':len(triangles),'surfaces':surface_count,'geometry_sha256':geometry_hash(triangles),
            'bounds':{'min':[min(p[j] for p in points) for j in range(3)],'max':[max(p[j] for p in points) for j in range(3)]},'local_matrix':identity,'parent':'I2RevetmentClosureDelivery'}
        assert records[name]['bounds']==prepared['pieces'][name]['bounds']
        global_surfaces+=surface_count
    assert set(records)==set(prepared['pieces']) and max_uv<=2e-7 and max_normal<=NORMAL_TOLERANCE_DEG,('export UV/normal bound',max_uv,max_normal)
    expected_maps={'Closure_Original4m_PBR':maps[0],'Closure_SouthCaps_PBR':maps[1]}
    assert {m['name'] for m in doc['materials']}==set(expected_maps)
    for material in doc['materials']:
        assert material.get('alphaMode','OPAQUE')=='OPAQUE' and not material.get('doubleSided',False) and material.get('emissiveFactor',[0,0,0])==[0,0,0]
        for texture in [material['pbrMetallicRoughness']['baseColorTexture'],material['pbrMetallicRoughness']['metallicRoughnessTexture'],material['normalTexture']]:assert texture.get('texCoord',0)==0
    images=[]
    for image in doc['images']:
        assert image['mimeType']=='image/png' and 'uri' not in image
        view=doc['bufferViews'][image['bufferView']];start=view.get('byteOffset',0);data=binary[start:start+view['byteLength']]
        images.append({'sha256':hashlib.sha256(data).hexdigest(),'bytes':len(data),'size':struct.unpack_from('>II',data,16)})
    assert {r['sha256'] for r in images}=={r['sha256'] for group in maps for r in group.values()},'embedded PBR bytes must match frozen files'
    for material in doc['materials']:
        links={'BaseColor':material['pbrMetallicRoughness']['baseColorTexture'],'ORM':material['pbrMetallicRoughness']['metallicRoughnessTexture'],'Normal':material['normalTexture']}
        for channel,reference in links.items():
            image_index=doc['textures'][reference['index']]['source']
            assert images[image_index]['sha256']==expected_maps[material['name']][channel]['sha256'],(material['name'],channel,'wrong actual PBR texture binding')
    return {'status':'RAW_GLB_VERIFIED','glb_sha256':sha(path),'bytes':Path(path).stat().st_size,'pieces':records,'meshes':12,'surfaces':global_surfaces,'materials':len(doc['materials']),
        'triangles':sum(r['triangles'] for r in records.values()),'images':images,'uv_max_error':max_uv,'source_normal_max_degrees':max_normal}

def deliver():
    prepared=json.loads((HERE/'prepared_report.json').read_text(encoding='utf-8'));baked=json.loads((HERE/'bake_report.json').read_text(encoding='utf-8'))
    assert baked['status']=='CAP_BAKE_COMPLETE' and baked['prepared_sha256']==prepared['blend_sha256']
    assert sha(HERE/'prepared.blend')==prepared['blend_sha256'] and sha(SOURCE)==SOURCE_SHA
    glb=HERE/'revetment_closure.glb';assert not glb.exists(),'preserve earlier export attempt'
    bpy.ops.wm.open_mainfile(filepath=str(HERE/'prepared.blend'))
    materials=[final_material('Closure_Original4m_PBR',prepared['reused_textures']),final_material('Closure_SouthCaps_PBR',baked['channels'])]
    objects=[o for o in bpy.data.objects if o.get('closure_delivery')];assert len(objects)==12
    root=bpy.data.objects['I2RevetmentClosureDelivery'];expected={}
    for obj in objects:
        mesh=obj.data;slots=[v.value for v in mesh.attributes['DeliveryMaterialSlot'].data]
        mesh.materials.clear();mesh.materials.append(materials[0])
        if 1 in slots:mesh.materials.append(materials[1])
        for p,slot in zip(mesh.polygons,slots):p.material_index=slot
        for name in [layer.name for layer in mesh.uv_layers]:
            if name!='DeliveryBakeUV':mesh.uv_layers.remove(mesh.uv_layers[name])
        mesh.uv_layers['DeliveryBakeUV'].name='SurfaceUV';mesh.uv_layers.active_index=0;mesh.uv_layers[0].active_render=True
        mesh.calc_loop_triangles()
        expected[obj.name]=[[{'p':gp(mesh.vertices[vi].co),'n':gp(mesh.corner_normals[li].vector),'uv':tuple(mesh.uv_layers[0].data[li].uv)} for vi,li in zip(tri.vertices,tri.loops)] for tri in mesh.loop_triangles]
    keep=set(objects+[root])
    for obj in list(bpy.data.objects):
        if obj not in keep:bpy.data.objects.remove(obj,do_unlink=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'delivery.blend'),relative_remap=False)
    select([root]+objects)
    bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,export_yup=True,export_apply=False,
        export_texcoords=True,export_normals=True,export_tangents=True,export_materials='EXPORT',export_extras=True,export_cameras=False,export_lights=False,export_animations=False)
    report=verify_glb(glb,expected,prepared,[prepared['reused_textures'],baked['channels']]);dump(HERE/'raw_glb_report.json',report)
    # Actual same-byte import and geometry readback precede all preview images.
    bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(glb));bpy.context.view_layer.update()
    meshes=[o for o in bpy.data.objects if o.type=='MESH'];assert len(meshes)==12
    for obj in meshes:
        assert obj.name in report['pieces'] and obj.matrix_world==Matrix.Identity(4)
        obj.data.calc_loop_triangles();triangles=[[gp(obj.data.vertices[i].co) for i in tri.vertices] for tri in obj.data.loop_triangles]
        assert geometry_hash(triangles)==report['pieces'][obj.name]['geometry_sha256'],(obj.name,'same-byte reimport triangles')
    sys.path.insert(0,str(P1));from build_source import render_preview
    output=HERE/'same_byte_reimport';assert not output.exists();output.mkdir()
    render_preview(json.loads((P1/'layout_plan.json').read_text(encoding='utf-8')),output)
    assert sha(glb)==report['glb_sha256'] and sha(SOURCE)==SOURCE_SHA
    reimport={'status':'SAME_BYTE_REIMPORT_RENDERED_REQUIRES_ROOT_REVIEW','glb_sha256':sha(glb),'source_sha256':SOURCE_SHA,
        'images':[{'path':str(p),'sha256':sha(p)} for p in sorted(output.glob('*.png'))],'all_mesh_geometry_readback':True,
        'limitations':['Blender material preview, not actual MAIN or final art acceptance.','Ground collision and real water surfaces not exercised here.']}
    assert len(reimport['images'])==2;dump(output/'report.json',reimport)
    candidate=ROOT/'assets/v3/candidates/i2_revetment_closure';candidate.mkdir(exist_ok=True)
    dest=candidate/'revetment_closure.glb';assert not dest.exists();shutil.copyfile(glb,dest);assert sha(dest)==sha(glb)
    contract=dict(report,status='EXPORTED_VERIFIED',plan_sha256=PLAN_SHA,source_sha256=SOURCE_SHA,
        editable_source=str(SOURCE.relative_to(ROOT)),collision='None; original Ground remains authoritative',root_name='I2RevetmentClosureDelivery',
        source_transfer=prepared['transfer'],cap_atlas=prepared['cap_atlas'],same_byte_reimport_report=str((output/'report.json').relative_to(ROOT)),
        acceptance='candidate only; root must inspect real MAIN default/south/north joints')
    dump(candidate/'delivery_contract.json',contract);dump(HERE/'delivery_contract.json',contract)

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--stage',choices=['bake','deliver'],required=True)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:]);start=time.monotonic()
    print(json.dumps({'stage':args.stage+'_start','pid':os.getpid()}),flush=True)
    if args.stage=='bake':bake()
    else:deliver()
    print(json.dumps({'stage':args.stage+'_exit','pid':os.getpid(),'seconds':time.monotonic()-start}),flush=True)

if __name__=='__main__':main()
