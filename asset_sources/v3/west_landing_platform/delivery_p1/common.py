from pathlib import Path
import bpy,json,hashlib,math,shutil,struct
from mathutils import Matrix
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
SOURCE=HERE.parent/'p1/west_landing_platform_editable.blend'
SOURCE_SHA='a7908e2e3a114f8a0a73bfb26e7216698b941a51de92f5915c1d2df3608d9105'
UVS=('MetricUV','FinishUV','PanelUV')
NAMES=('PlatformSteel','PlatformPaint','LegSteel','LegPaint')
COUNTS={'PlatformSteel':672,'PlatformPaint':660,'LegSteel':960,'LegPaint':836}
BOUNDS={'PlatformAssembly':[[-4,4.6,-2],[4,5,2]],'LegAssembly':[[-3.6,0,1],[-3.1,4.6,1.5]]}
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def write(name,value):(HERE/name).write_text(json.dumps(value,ensure_ascii=False,indent=2,allow_nan=False)+'\n',encoding='utf-8')
def gp(p):return [float(p[0]),float(p[2]),float(-p[1])]
def select(objects,active=None):
    bpy.ops.object.select_all(action='DESELECT')
    for ob in objects:ob.hide_set(False);ob.hide_viewport=False;ob.select_set(True)
    bpy.context.view_layer.objects.active=active or objects[0]
def save_relative(path):
    absolute={im.name:str(Path(bpy.path.abspath(im.filepath)).resolve()) for im in bpy.data.images if im.source=='FILE' and im.filepath}
    for name,p in absolute.items():bpy.data.images[name].filepath=p
    bpy.ops.wm.save_as_mainfile(filepath=str(path),relative_remap=False)
    for name,p in absolute.items():bpy.data.images[name].filepath=bpy.path.relpath(p)
    bpy.ops.wm.save_as_mainfile(filepath=str(path),relative_remap=False)
def image_audit(copy=False):
    rows=[]
    for im in bpy.data.images:
        if im.source!='FILE' or not im.filepath or not im.users:continue
        p=Path(bpy.path.abspath(im.filepath)).resolve();assert p.is_file(),(im.name,str(p))
        pixel=list(im.pixels[:4]);assert len(pixel)==4 and im.has_data and all(math.isfinite(x) for x in pixel)
        if copy:
            folder=HERE/'source_inputs';folder.mkdir(exist_ok=True);dst=folder/p.name
            if dst.exists():assert sha(dst)==sha(p)
            else:shutil.copyfile(p,dst)
            p=dst
        im.filepath=str(p)
        rows.append({'name':im.name,'path':str(p),'sha256':sha(p),'size':list(im.size),'colorspace':im.colorspace_settings.name,'pixel':pixel})
    return rows
def shader(mat):
    nodes=[n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED'];assert len(nodes)==1
    return nodes[0]
def source_rows(ob,uv='DeliveryUV'):
    me=ob.data;me.calc_loop_triangles()
    return [[{'p':gp(me.vertices[vi].co),'n':gp(me.corner_normals[li].vector),'uv':list(me.uv_layers[uv].data[li].uv)} for vi,li in zip(t.vertices,t.loops)] for t in me.loop_triangles]
def subset(src,ids,name,material=None):
    me=src.data;verts=[];faces=[];normals=[];layers={u.name:[] for u in me.uv_layers};remap={}
    for index in ids:
        face=[];p=me.polygons[index]
        for vi,li in zip(p.vertices,p.loop_indices):
            if vi not in remap:remap[vi]=len(verts);verts.append(tuple(me.vertices[vi].co))
            face.append(remap[vi]);normals.append(tuple(me.corner_normals[li].vector))
            for key in layers:layers[key].append(tuple(me.uv_layers[key].data[li].uv))
        faces.append(tuple(face))
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update()
    for p in mesh.polygons:p.use_smooth=True
    mesh.normals_split_custom_set(normals)
    for key,values in layers.items():
        mesh.uv_layers.new(name=key)
        for q,value in zip(mesh.uv_layers[key].data,values):q.uv=value
    mesh.uv_layers.active_index=mesh.uv_layers.find('DeliveryUV')
    for u in mesh.uv_layers:u.active_render=u.name=='DeliveryUV'
    mesh.materials.append(material or me.materials[0]);ob=bpy.data.objects.new(name,mesh);bpy.context.scene.collection.objects.link(ob)
    return ob
