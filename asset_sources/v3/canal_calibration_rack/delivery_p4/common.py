from pathlib import Path
import bpy,math,json,hashlib,shutil,sys
from mathutils import Matrix
sys.dont_write_bytecode=True
OUT=Path(__file__).resolve().parent;ROOT=OUT.parents[3]
SOURCE=OUT.parent/'p4/preview_20261020_035045_756760/calibration_rack_p4_editable.blend'
SOURCE_SHA='a7d48c4b46fca78b9cc5bbea7448d4d630b03aef64ea195b47e6c86421eb73fc'
PLATES=('TopServiceStrip','LandingPlate_0','LandingPlate_1','LandingPlate_2')
UVS=('MetricUV','PanelUV','FinishUV','SteelUV','TopUV')
ROOT_NAME='CalibrationRack'
PARTS={'DeckSurface':944,'StructureAndHardware':3796}

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def write(name,row):(OUT/name).write_text(json.dumps(row,ensure_ascii=False,indent=2,allow_nan=False),encoding='utf-8')
def gp(p):return [float(p[0]),float(p[2]),float(-p[1])]
def select(objects,active=None):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:o.hide_set(False);o.hide_viewport=False;o.select_set(True)
    bpy.context.view_layer.objects.active=active or objects[0]
def shader(material):
    rows=[n for n in material.node_tree.nodes if n.type=='BSDF_PRINCIPLED'];assert len(rows)==1,material.name
    return rows[0]

def audit_images(copy=False):
    rows=[];(OUT/'source_inputs').mkdir(exist_ok=True)
    for im in bpy.data.images:
        if im.source!='FILE' or not im.filepath:continue
        p=Path(bpy.path.abspath(im.filepath)).resolve();assert p.is_file(),(im.name,str(p))
        pixel=list(im.pixels[:4]);assert len(pixel)==4 and im.has_data and all(math.isfinite(x) for x in pixel),im.name
        if copy:
            dst=OUT/'source_inputs'/p.name
            if dst.exists():assert sha(dst)==sha(p)
            else:shutil.copyfile(p,dst)
            p=dst
        im.filepath=str(p)
        rows.append({'image':im.name,'path':str(p),'bytes':p.stat().st_size,'sha256':sha(p),'space':im.colorspace_settings.name,'size':list(im.size),'pixel':pixel})
    return rows

def proxy(parts,name):
    """Exact source triangulation and interpolated corner normals, world baked into identity."""
    verts=[];faces=[];mids=[];normals=[];uvs={n:[] for n in UVS};colors=[];mats=[];origin=[]
    for ob in sorted(parts,key=lambda o:o.name):
        me=ob.data;me.calc_loop_triangles();base=len(verts);verts.extend(tuple(ob.matrix_world@v.co) for v in me.vertices)
        normal_matrix=ob.matrix_world.to_3x3().inverted().transposed()
        for tri in me.loop_triangles:
            mat=me.materials[me.polygons[tri.polygon_index].material_index];assert mat
            if mat not in mats:mats.append(mat)
            faces.append(tuple(base+i for i in tri.vertices));mids.append(mats.index(mat));origin.append(ob.name)
            for li in tri.loops:
                normals.append(tuple((normal_matrix@me.corner_normals[li].vector).normalized()))
                for uv in UVS:uvs[uv].append(tuple(me.uv_layers[uv].data[li].uv))
                colors.append(tuple(me.color_attributes['SurfaceUse'].data[li].color))
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update()
    for mat in mats:mesh.materials.append(mat)
    for poly,mid in zip(mesh.polygons,mids):poly.material_index=mid;poly.use_smooth=True
    mesh.normals_split_custom_set(normals)
    for uv,values in uvs.items():
        mesh.uv_layers.new(name=uv)
        for corner,value in zip(mesh.uv_layers[uv].data,values):corner.uv=value
    mesh.color_attributes.new(name='SurfaceUse',type='FLOAT_COLOR',domain='CORNER')
    for corner,value in zip(mesh.color_attributes['SurfaceUse'].data,colors):corner.color=value
    obj=bpy.data.objects.new(name,mesh);bpy.context.scene.collection.objects.link(obj)
    obj['delivery_proxy']=True;obj['source_parts']=json.dumps([o.name for o in parts]);return obj

def smart_faces(obj,face_ids,rect,margin=.012):
    if not face_ids:return
    select([obj]);bpy.context.tool_settings.mesh_select_mode=(False,False,True)
    bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='DESELECT');bpy.ops.object.mode_set(mode='OBJECT')
    wanted=set(face_ids)
    for poly in obj.data.polygons:poly.select=poly.index in wanted
    bpy.ops.object.mode_set(mode='EDIT');bpy.ops.uv.smart_project(angle_limit=math.radians(66),island_margin=margin)
    bpy.ops.object.mode_set(mode='OBJECT')
    a,b,c,d=rect;layer=obj.data.uv_layers['DeliveryUV']
    for index in face_ids:
        for li in obj.data.polygons[index].loop_indices:
            u,v=layer.data[li].uv;layer.data[li].uv=(a+u*(b-a),c+v*(d-c))

def unwrap(deck_targets,structure):
    # One deck proxy combines all four original low plates; top UVs preserve
    # continuous physical placement. The narrow remainder strip is for hidden
    # bottom, side and pocket faces, not the tread visible surface.
    deck=proxy(deck_targets,'DeckBakeProxy');all_targets=[deck,structure]
    for obj in all_targets:
        me=obj.data;me.uv_layers.new(name='DeliveryUV');me.uv_layers.active_index=me.uv_layers.find('DeliveryUV')
        for u in me.uv_layers:u.active_render=u.name=='DeliveryUV'
    primary=[];other=[];me=deck.data
    for p in me.polygons:
        z=sum(me.vertices[v].co.z for v in p.vertices)/len(p.vertices)
        (primary if p.normal.z>.75 and z>.317 else other).append(p.index)
    smart_faces(deck,other,(.015,.985,.015,.095),margin=.04)
    by_face={};offset=0
    for ob in sorted(deck_targets,key=lambda o:o.name):
        ob.data.calc_loop_triangles();count=len(ob.data.loop_triangles)
        for i in range(offset,offset+count):by_face[i]=ob.name
        offset+=count
    # Independent atlas rectangles provide 20.48 px gutters between the real
    # 4 mm seams. Source TopUV remains unchanged, so paint/steel stay aligned.
    regions={
        'TopServiceStrip':(-1.021,-.680,-1.021,1.021,.020,.179,.120,.980),
        'LandingPlate_0':(-.676,1.021,.344,1.021,.189,.980,.700,.980),
        'LandingPlate_1':(-.676,1.021,-.338,.340,.189,.980,.410,.690),
        'LandingPlate_2':(-.676,1.021,-1.021,-.342,.189,.980,.120,.400),
    }
    for index in primary:
        x0,x1,y0,y1,u0,u1,v0,v1=regions[by_face[index]]
        for li in me.polygons[index].loop_indices:
            v=me.vertices[me.loops[li].vertex_index].co
            me.uv_layers['DeliveryUV'].data[li].uv=(u0+(v.x-x0)/(x1-x0)*(u1-u0),v0+(v.y-y0)/(y1-y0)*(v1-v0))
    smart_faces(structure,list(range(len(structure.data.polygons))),(.01,.99,.01,.99))
    report={}
    for obj in all_targets:
        me=obj.data;me.calc_loop_triangles();bad=[];minimum=1.
        for tri in me.loop_triangles:
            uv=[tuple(me.uv_layers['DeliveryUV'].data[i].uv) for i in tri.loops]
            area=abs((uv[1][0]-uv[0][0])*(uv[2][1]-uv[0][1])-(uv[1][1]-uv[0][1])*(uv[2][0]-uv[0][0]))*.5
            minimum=min(minimum,area)
            if area==0:bad.append(tri.index)
        assert not bad,(obj.name,'zero UV triangles',bad)
        assert all(math.isfinite(c) and 0<=c<=1 for l in me.uv_layers['DeliveryUV'].data for c in l.uv)
        report[obj.name]={'triangles':len(me.loop_triangles),'minimum_UV_area':minimum,'zero_UV_triangles':bad}
    report['deck_top_density_px_per_m']={name:[2048*(u1-u0)/(x1-x0),2048*(v1-v0)/(y1-y0)] for name,(x0,x1,y0,y1,u0,u1,v0,v1) in regions.items()}
    report['primary_gutter_px']=20.48
    report['deck_primary_triangles']=len(primary);report['deck_secondary_triangles']=len(other)
    write('UV_report.json',report);return deck

def split_deck(deck,originals):
    """Matching four low groups, with DeliveryUV copied from the common atlas."""
    me=deck.data;result=[];offset=0
    # proxy() sorted source order defines the deterministic face spans.
    for original in sorted(originals,key=lambda o:o.name):
        original.data.calc_loop_triangles();count=len(original.data.loop_triangles);ids=list(range(offset,offset+count));offset+=count
        verts=[];faces=[];normals=[];values=[]
        for index in ids:
            p=me.polygons[index];base=len(verts);verts.extend(tuple(me.vertices[v].co) for v in p.vertices);faces.append(tuple(range(base,base+3)))
            for li in p.loop_indices:normals.append(tuple(me.corner_normals[li].vector));values.append(tuple(me.uv_layers['DeliveryUV'].data[li].uv))
        mesh=bpy.data.meshes.new(original.name+'_Target');mesh.from_pydata(verts,[],faces);mesh.update()
        for p in mesh.polygons:p.use_smooth=True
        mesh.normals_split_custom_set(normals);mesh.uv_layers.new(name='DeliveryUV')
        for li,uv in zip(mesh.uv_layers['DeliveryUV'].data,values):li.uv=uv
        mesh.uv_layers.active_index=0;mesh.uv_layers[0].active_render=True
        # Target has a trivial independent material; high source supplies shading.
        mat=bpy.data.materials.new(original.name+'_BakeTarget');mat.use_nodes=True;mat.node_tree.nodes.clear()
        bs=mat.node_tree.nodes.new('ShaderNodeBsdfPrincipled');out=mat.node_tree.nodes.new('ShaderNodeOutputMaterial');mat.node_tree.links.new(bs.outputs[0],out.inputs[0])
        mesh.materials.append(mat)
        obj=bpy.data.objects.new(original.name+'_BakeTarget',mesh);bpy.context.scene.collection.objects.link(obj);obj['delivery_target']=True
        result.append((original.name,obj))
    assert offset==len(me.polygons);return result

def source_rows(mesh):
    mesh.calc_loop_triangles();uv=mesh.uv_layers['DeliveryUV']
    return [[{'p':gp(mesh.vertices[v].co),'n':gp(mesh.corner_normals[l].vector),'uv':list(uv.data[l].uv)} for v,l in zip(t.vertices,t.loops)] for t in mesh.loop_triangles]
