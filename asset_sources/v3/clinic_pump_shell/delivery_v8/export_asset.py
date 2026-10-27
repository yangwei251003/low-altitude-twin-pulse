from pathlib import Path
import sys,json,time,os,struct,math,collections,shutil
sys.path.insert(0,str(Path(__file__).resolve().parent))
from common import *
import numpy as np

def empty(name,parent=None):
    o=bpy.data.objects.new(name,None);bpy.context.scene.collection.objects.link(o);o.parent=parent;o.matrix_basis=Matrix.Identity(4);return o
def final_material(maps):
    m=bpy.data.materials.new('ClinicPumpShell_PBR');m.use_nodes=True;m.use_backface_culling=True
    n=m.node_tree.nodes;n.clear();lk=m.node_tree.links;p=n.new('ShaderNodeBsdfPrincipled');p.name='PumpPBR';out=n.new('ShaderNodeOutputMaterial');lk.new(p.outputs[0],out.inputs['Surface'])
    uv=n.new('ShaderNodeUVMap');uv.uv_map='SurfaceUV';textures={}
    for channel in ['BaseColor','ORM','Normal']:
        im=bpy.data.images.load(maps[channel],check_existing=False);im.colorspace_settings.name='sRGB' if channel=='BaseColor' else 'Non-Color'
        t=n.new('ShaderNodeTexImage');t.name='Baked_'+channel;t.image=im;lk.new(uv.outputs[0],t.inputs['Vector']);textures[channel]=t
    lk.new(textures['BaseColor'].outputs['Color'],p.inputs['Base Color'])
    split=n.new('ShaderNodeSeparateColor');split.mode='RGB';lk.new(textures['ORM'].outputs['Color'],split.inputs[0]);lk.new(split.outputs['Green'],p.inputs['Roughness']);lk.new(split.outputs['Blue'],p.inputs['Metallic'])
    nm=n.new('ShaderNodeNormalMap');nm.space='TANGENT';nm.uv_map='SurfaceUV';nm.inputs['Strength'].default_value=1
    lk.new(textures['Normal'].outputs['Color'],nm.inputs['Color']);lk.new(nm.outputs[0],p.inputs['Normal']);p.inputs['Alpha'].default_value=1;p.inputs['Emission Strength'].default_value=0
    return m
def split_groups(proxy,material):
    me=proxy.data;me.calc_loop_triangles();uv=me.uv_layers['DeliveryBakeUV'];attr=me.attributes['DeliveryGroup'];rows={};runtime=[]
    # Original editable 200-object file and bake checkpoints remain separately.
    # Final delivery scene contains only six runtime meshes + review camera/lights.
    for o in list(bpy.data.objects):
        if o!=proxy and (o.get('editable_piece') or o.type=='EMPTY'):bpy.data.objects.remove(o,do_unlink=True)
    root=empty('ClinicPumpShell');root['world_origin_godot']=[-7,0,8];root['source_v8_sha256']=SOURCE_SHA
    permanent=empty('PermanentNavigation',root);cover=empty('OccludingCover',root)
    for gi,name in enumerate(GROUPS):
        vmap={};verts=[];faces=[];uvs=[];normals=[]
        for tri in me.loop_triangles:
            if attr.data[tri.polygon_index].value!=gi:continue
            face=[]
            for vi,li in zip(tri.vertices,tri.loops):
                if vi not in vmap:vmap[vi]=len(verts);verts.append(tuple(me.vertices[vi].co))
                face.append(vmap[vi]);uvs.append(tuple(uv.data[li].uv));normals.append(tuple(me.corner_normals[li].vector))
            faces.append(face)
        mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update()
        for poly in mesh.polygons:poly.use_smooth=True
        mesh.normals_split_custom_set(normals);mesh.uv_layers.new(name='SurfaceUV')
        for l,u in zip(mesh.uv_layers['SurfaceUV'].data,uvs):l.uv=u
        mesh.uv_layers.active_index=0;mesh.uv_layers[0].active_render=True;mesh.materials.append(material)
        o=bpy.data.objects.new(name,mesh);bpy.context.scene.collection.objects.link(o);o.parent=permanent if gi<2 else cover;o.matrix_basis=Matrix.Identity(4)
        o['collision']='None authored: retain original seven root-owned BoxShape3D colliders.';runtime.append(o)
        mesh.calc_loop_triangles();rows[name]=[]
        for tri in mesh.loop_triangles:
            rows[name].append([{'p':gp(mesh.vertices[vi].co),'n':gp(mesh.corner_normals[li].vector),'uv':list(mesh.uv_layers[0].data[li].uv)} for vi,li in zip(tri.vertices,tri.loops)])
    assert sum(len(a) for a in rows.values())==13600
    bpy.data.objects.remove(proxy,do_unlink=True)
    return root,[root,permanent,cover]+runtime,runtime,rows

def canonical(corners):
    keys=[tuple(round(x,5) for x in c['p']) for c in corners]
    i=min(range(3),key=lambda i:keys[i:]+keys[:i]);return tuple(keys[i:]+keys[:i]),corners[i:]+corners[:i]

def verify_raw(path,expected,textures):
    raw=path.read_bytes();magic,version,length=struct.unpack_from('<4sII',raw);assert (magic,version,length)==(b'glTF',2,len(raw));offset=12;doc=None;binary=None
    while offset<len(raw):
        size,kind=struct.unpack_from('<I4s',raw,offset);offset+=8;chunk=raw[offset:offset+size];offset+=size
        if kind==b'JSON':doc=json.loads(chunk)
        elif kind==b'BIN\0':binary=chunk
    assert doc is not None and binary is not None
    def accessor(index):
        a=doc['accessors'][index];v=doc['bufferViews'][a['bufferView']];assert 'sparse' not in a and not a.get('normalized',False)
        width={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']];fmt,byte={5121:('B',1),5123:('H',2),5125:('I',4),5126:('f',4)}[a['componentType']]
        start=v.get('byteOffset',0)+a.get('byteOffset',0);stride=v.get('byteStride',width*byte)
        return [struct.unpack_from('<'+fmt*width,binary,start+i*stride) for i in range(a['count'])]
    nodes={};actual={};all_points=[]
    for node in doc['nodes']:
        name=node['name'];assert name not in nodes;nodes[name]=node
        assert all(abs(a-b)<1e-7 for a,b in zip(node.get('matrix',[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]),[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]))
        assert max([abs(a) for a in node.get('translation',[0,0,0])])<1e-7
        assert max(abs(a-b) for a,b in zip(node.get('rotation',[0,0,0,1]),[0,0,0,1]))<1e-7
        assert max(abs(a-1) for a in node.get('scale',[1,1,1]))<1e-7
        if 'mesh' not in node:continue
        actual[name]=[];mesh=doc['meshes'][node['mesh']];assert len(mesh['primitives'])==1
        for primitive in mesh['primitives']:
            attrs=primitive['attributes'];assert primitive.get('mode',4)==4 and 'TEXCOORD_0' in attrs and 'TEXCOORD_1' not in attrs
            ps=accessor(attrs['POSITION']);ns=accessor(attrs['NORMAL']);uv=accessor(attrs['TEXCOORD_0']);indices=[i[0] for i in accessor(primitive['indices'])]
            assert len(indices)%3==0 and all(math.isfinite(x) and -1e-6<=x<=1.000001 for u in uv for x in u)
            all_points.extend(ps)
            for i in range(0,len(indices),3):actual[name].append([{'p':list(ps[j]),'n':list(ns[j]),'uv':[uv[j][0],1-uv[j][1]]} for j in indices[i:i+3]])
    assert set(actual)==set(GROUPS) and set(nodes)==set(GROUPS)|{'ClinicPumpShell','PermanentNavigation','OccludingCover'}
    errors={'position':0.,'normal':0.,'uv':0.};counts={};normal_source_error=0.;normal_quantization_error=0.
    for name in GROUPS:
        a=collections.defaultdict(list);b=collections.defaultdict(list)
        for row in expected[name]:k,c=canonical(row);a[k].append(c)
        for row in actual[name]:k,c=canonical(row);b[k].append(c)
        assert collections.Counter({k:len(v) for k,v in a.items()})==collections.Counter({k:len(v) for k,v in b.items()}),(name,'triangle multiset/winding')
        for key in a:
            sortkey=lambda tri:tuple(round(x,6) for c in tri for x in c['uv']+c['n'])
            for et,at in zip(sorted(a[key],key=sortkey),sorted(b[key],key=sortkey)):
                for e,c in zip(et,at):
                    for field,label in [('p','position'),('uv','uv')]:errors[label]=max(errors[label],max(abs(x-y) for x,y in zip(e[field],c[field])))
                    # Installed Blender 5.2.1 glTF exporter primitive_extract.py:1462
                    # rounds normals to ROUNDING_DIGIT=4, then normalizes float32.
                    # Check that documented transform strictly, retaining the raw
                    # source-to-export delta separately; do not loosen geometry/UV.
                    q=np.round(np.asarray([e['n']],dtype=np.float32),4)
                    np.divide(q,np.linalg.norm(q,axis=1,keepdims=True),out=q)
                    errors['normal']=max(errors['normal'],max(abs(float(x)-y) for x,y in zip(q[0],c['n'])))
                    normal_source_error=max(normal_source_error,max(abs(x-y) for x,y in zip(e['n'],c['n'])))
                    normal_quantization_error=max(normal_quantization_error,max(abs(float(x)-y) for x,y in zip(q[0],e['n'])))
        counts[name]=len(actual[name])
    assert errors['position']<3e-6 and errors['normal']<3e-5 and errors['uv']<2e-6,errors
    assert sum(counts.values())==13600
    assert len(doc['materials'])==1 and len(doc['images'])==3
    mat=doc['materials'][0];assert not mat.get('doubleSided',False) and mat.get('alphaMode','OPAQUE')=='OPAQUE'
    for texture in [mat['pbrMetallicRoughness']['baseColorTexture'],mat['pbrMetallicRoughness']['metallicRoughnessTexture'],mat['normalTexture']]:assert texture.get('texCoord',0)==0
    embedded=[]
    for im in doc['images']:
        assert 'bufferView' in im and 'uri' not in im and im['mimeType']=='image/png'
        v=doc['bufferViews'][im['bufferView']];data=binary[v.get('byteOffset',0):v.get('byteOffset',0)+v['byteLength']]
        assert data[:8]==b'\x89PNG\r\n\x1a\n' and struct.unpack_from('>II',data,16)==(SIZE,SIZE)
        embedded.append({'name':im.get('name'),'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()})
    assert {i['sha256'] for i in embedded}=={sha(p) for p in textures.values()},'Embedded texture bytes differ: inspect instead of silently accepting.'
    return {'sha256':sha(path),'bytes':len(raw),'nodes':nodes,'triangles_by_group':counts,'triangles':sum(counts.values()),'meshes':6,'material':mat,'images':embedded,'max_source_errors':errors,'normal_check':{'method':'Installed official glTF exporter float32 round(4), then normalize; verify transformed expected normals, report original delta separately.','raw_source_to_glb_max':normal_source_error,'expected_quantization_max':normal_quantization_error,'quantized_expected_to_glb_max':errors['normal']},'all_node_transforms_identity':True,'bounds':{'min':[min(p[i] for p in all_points) for i in range(3)],'max':[max(p[i] for p in all_points) for i in range(3)]},'source_origin_world_godot':[-7,0,8]}

def main():
    start=time.time();assert sha(SOURCE)==SOURCE_SHA;assert not (ASSETS/'clinic_pump_shell.glb').exists(),'Never overwrite a published candidate.'
    bake_report=json.loads((OUT/'bake_report.json').read_text(encoding='utf-8'));assert bake_report['status']=='BAKE_COMPLETE_PENDING_EXPORT'
    assert sha(OUT/'bake_complete.blend')==bake_report['blend_sha256']
    print(json.dumps({'stage':'start_export','pid':os.getpid(),'threads':2}),flush=True)
    bpy.ops.wm.open_mainfile(filepath=str(OUT/'bake_complete.blend'));scene=bpy.context.scene
    textures={r['channel']:r['path'] for r in bake_report['textures']}
    for r in bake_report['textures']:assert sha(r['path'])==r['sha256']
    material=final_material(textures);root,selected,meshes,expected=split_groups(bpy.data.objects['DeliveryBakeProxy'],material)
    (OUT/'expected_runtime_triangles.json').write_text(json.dumps(expected,separators=(',',':'))+'\n',encoding='utf-8')
    blend=OUT/'clinic_pump_shell_delivery.blend';bpy.ops.wm.save_as_mainfile(filepath=str(blend),relative_remap=False)
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath:im.filepath=bpy.path.relpath(bpy.path.abspath(im.filepath))
    bpy.ops.wm.save_as_mainfile(filepath=str(blend),relative_remap=False);bpy.ops.wm.open_mainfile(filepath=str(blend))
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath:
            path=Path(bpy.path.abspath(im.filepath));assert path.is_file();im.reload();pixel=tuple(im.pixels[:4]);assert len(pixel)==4 and im.has_data
    selected=[bpy.data.objects[n] for n in GROUPS+['ClinicPumpShell','PermanentNavigation','OccludingCover']];select(selected)
    candidate=OUT/'clinic_pump_shell.glb'
    bpy.ops.export_scene.gltf(filepath=str(candidate),export_format='GLB',use_selection=True,export_yup=True,export_apply=False,export_texcoords=True,export_normals=True,export_tangents=True,export_materials='EXPORT',export_extras=True,export_cameras=False,export_lights=False)
    raw=verify_raw(candidate,expected,textures)
    (OUT/'raw_glb_report.json').write_text(json.dumps(raw,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    # Read the exact exported bytes into a scene without source/runtime meshes.
    for o in list(bpy.data.objects):
        if o.name in GROUPS+['ClinicPumpShell','PermanentNavigation','OccludingCover']:bpy.data.objects.remove(o,do_unlink=True)
    before=set(bpy.data.objects.keys());bpy.ops.import_scene.gltf(filepath=str(candidate));imported=[o for o in bpy.data.objects if o.name not in before and o.type=='MESH']
    assert {o.name for o in imported}==set(GROUPS)
    for o in imported:
        o.data.calc_loop_triangles();assert len(o.data.loop_triangles)==len(expected[o.name])
        source=collections.Counter(canonical(t)[0] for t in expected[o.name]);actual=collections.Counter()
        for t in o.data.loop_triangles:
            c=[{'p':gp(o.matrix_world@o.data.vertices[i].co)} for i in t.vertices];actual[canonical(c)[0]]+=1
        assert actual==source,(o.name,'actual reimport positions/winding')
    scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=18;scene.render.threads_mode='FIXED';scene.render.threads=2
    image=OUT/'clinic_pump_shell_glb_preview.png';scene.render.filepath=str(image);bpy.ops.render.render(write_still=True)
    assert sha(candidate)==raw['sha256'] and sha(SOURCE)==SOURCE_SHA
    ASSETS.mkdir(parents=True,exist_ok=True);shutil.copyfile(candidate,ASSETS/'clinic_pump_shell.glb')
    for path in textures.values():shutil.copyfile(path,ASSETS/Path(path).name)
    assert sha(ASSETS/'clinic_pump_shell.glb')==raw['sha256']
    final={'status':'RAW_GLB_AND_SAME_BYTE_REIMPORT_COMPLETE_PENDING_VISUAL_REVIEW','runtime':str(ASSETS/'clinic_pump_shell.glb'),'glb':raw,'source_v8_sha256':SOURCE_SHA,'delivery_blend_sha256':sha(blend),'reimport_png':str(image),'reimport_png_sha256':sha(image),'elapsed_seconds':time.time()-start,'limits':['Offline same-byte GLB preview; no Godot/performance/flight/fader acceptance.','Original seven physical boxes are root-owned; no collisions exported.','V8 editable source is immutable; delivery uses six merged runtime groups.']}
    (OUT/'delivery_report.json').write_text(json.dumps(final,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    asset_files=[ASSETS/'clinic_pump_shell.glb']+[ASSETS/Path(p).name for p in textures.values()]
    manifest={'status':'EXPORTED_CANDIDATE_PENDING_GODOT_AND_FINAL_ART_REVIEW','source_v8_sha256':SOURCE_SHA,'source_directory':str(SOURCE.parent),'world_origin_godot':[-7,0,8],'nodes':GROUPS,'all_node_transforms_identity':True,'triangles':13600,'material_count':1,'collision':'None exported; original seven root-owned boxes retained','files':[{'path':p.name,'bytes':p.stat().st_size,'sha256':sha(p)} for p in asset_files],'source_report':str(OUT/'delivery_report.json'),'metal012_source':'https://ambientcg.com/view?id=Metal012','license':'CC0-1.0'}
    (ASSETS/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'stage':'end_export','pid':os.getpid(),'seconds':time.time()-start,'sha256':raw['sha256']}),flush=True)
if __name__=='__main__':main()
