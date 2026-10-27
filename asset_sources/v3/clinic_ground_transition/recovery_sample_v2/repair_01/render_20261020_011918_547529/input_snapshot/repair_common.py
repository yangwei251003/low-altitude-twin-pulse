"""Static-prepared repair helpers. Original files are immutable inputs."""
from pathlib import Path
import hashlib, json, math, os, struct, sys
sys.dont_write_bytecode = True
import bpy
import numpy as np
from mathutils import Vector

HERE = Path(__file__).resolve().parent
V2 = HERE.parent
ROOT = HERE.parents[4]
OUT = Path(os.environ['RECOVERY_REPAIR_OUTPUT']).resolve()
assert OUT.is_relative_to(HERE)
CONTRACT = json.loads((V2/'input_contract.json').read_text(encoding='utf-8'))
INSPECTION = V2/'repair/inspection_20261020_000619_140916'
SIZE = 1024
CAGE_OFFSET = .035


def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def write(name, value):
    (OUT/name).write_text(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False)+'\n', encoding='utf-8')


def verify_frozen():
    rows=[]
    for rel, expected in CONTRACT['inputs'].items():
        p=ROOT/rel
        actual={'bytes':p.stat().st_size,'sha256':sha(p)}
        assert actual==expected, (rel,actual,expected)
        rows.append({'path':rel,**actual})
    for filename,digest in [('diagnostic_manifest.json','e8ddefed8b45dab3b94ab24943b0a8a6027d4ef3f370063c87af59d230e08ed2'),
                            ('repair/inspection_manifest.json','3060c4fd9668cab39f786d507474f72fdc95413e88bfc93cf6e1986cfcb25d83')]:
        p=V2/filename; assert sha(p)==digest,filename
        manifest=json.loads(p.read_text(encoding='utf-8'))
        for row in manifest['files']:
            f=p.parent/row['path']
            assert f.stat().st_size==row['bytes'] and sha(f)==row['sha256'],str(f)
    return rows


def images():
    rows=[]
    for im in bpy.data.images:
        if im.source!='FILE': continue
        p=Path(bpy.path.abspath(im.filepath)).resolve()
        assert p.is_file(),(im.name,im.filepath,str(p))
        px=tuple(im.pixels[:4])
        assert px and im.has_data and all(math.isfinite(x) for x in px),im.name
        # This changes only the loaded repair scene, never an original blend.
        im.filepath=str(p)
        rows.append({'image':im.name,'path':str(p),'sha256':sha(p),'bytes':p.stat().st_size,
                     'size':list(im.size),'space':im.colorspace_settings.name,'first_pixel':px})
    return rows


def array(im):
    px=np.empty(len(im.pixels),np.float32); im.pixels.foreach_get(px)
    return px.reshape((im.size[1],im.size[0],4))


def select(obs, active):
    bpy.ops.object.select_all(action='DESELECT')
    for o in obs:
        o.hide_set(False);o.hide_viewport=False;o.select_set(True)
    bpy.context.view_layer.objects.active=active


def show(obs):
    wanted={o.name for o in obs}
    for o in bpy.data.objects:
        if o.type=='MESH' and (o.get('study_part') or o.get('repair_part')):
            o.hide_render=o.name not in wanted


def scene_lock(scene):
    return {'camera_matrix':[list(r) for r in scene.camera.matrix_world],
            'ortho_scale':scene.camera.data.ortho_scale,
            'resolution':[scene.render.resolution_x,scene.render.resolution_y,scene.render.resolution_percentage],
            'view_transform':scene.view_settings.view_transform,'look':scene.view_settings.look,
            'exposure':scene.view_settings.exposure,'gamma':scene.view_settings.gamma,
            'lights':[{'name':o.name,'matrix':[list(r) for r in o.matrix_world],
                       'energy':o.data.energy,'color':list(o.data.color),'size':o.data.size}
                      for o in bpy.data.objects if o.type=='LIGHT']}


def angle(a,b):
    return math.degrees(math.acos(max(-1.,min(1.,a.normalized().dot(b.normalized())))))


def geom_key(me,t):
    return tuple(sorted(tuple(round(float(v),8) for v in me.vertices[i].co) for i in t.vertices))


def face_kind(me,t):
    p=me.polygons[t.polygon_index]
    return 'top' if p.use_smooth else ('bottom' if p.normal.z<-.9 else 'side')


def digest(me, include_source_uv=False):
    """Independent of polygon grouping, but includes winding, corner normals and BakeUV."""
    me.calc_loop_triangles(); h=hashlib.sha256()
    layers=[u for u in me.uv_layers if include_source_uv or u.name=='BakeUV']
    for t in me.loop_triangles:
        for li in t.loops:
            v=me.vertices[me.loops[li].vertex_index].co
            h.update(struct.pack('<3f',*v))
            # Raw float normal equality is separately measured as an angle;
            # the immutable geometry/UV digest deliberately excludes rounding.
            for layer in layers:h.update(struct.pack('<2f',*layer.data[li].uv))
    return h.hexdigest()


def subset(source, ids, name):
    """Actual existing triangles and all corner attributes, no retessellation guess."""
    old=source.data;old.calc_loop_triangles();ts=[old.loop_triangles[i] for i in ids]
    used=sorted({i for t in ts for i in t.vertices});remap={v:i for i,v in enumerate(used)}
    me=bpy.data.meshes.new(name)
    me.from_pydata([tuple(old.vertices[i].co) for i in used],[],[tuple(remap[i] for i in t.vertices) for t in ts]);me.update()
    for mat in old.materials:me.materials.append(mat)
    normals=[]
    for p,t in zip(me.polygons,ts):
        p.use_smooth=old.polygons[t.polygon_index].use_smooth
        p.material_index=old.polygons[t.polygon_index].material_index
        normals.extend(tuple(old.corner_normals[li].vector) for li in t.loops)
    # Allocate every UV layer first; Blender can invalidate prior RNA handles.
    for u in old.uv_layers:me.uv_layers.new(name=u.name)
    for u in old.uv_layers:
        dst=me.uv_layers[u.name]
        for p,t in zip(me.polygons,ts):
            for a,b in zip(p.loop_indices,t.loops):dst.data[a].uv=tuple(u.data[b].uv)
    for attr in old.color_attributes:
        assert attr.domain=='CORNER',('Unexpected attribute domain',attr.name,attr.domain)
        dst=me.color_attributes.new(name=attr.name,type=attr.data_type,domain='CORNER')
        for p,t in zip(me.polygons,ts):
            for a,b in zip(p.loop_indices,t.loops):dst.data[a].color=tuple(attr.data[b].color)
    me.normals_split_custom_set(normals);me.update();me.calc_loop_triangles()
    if 'BakeUV' in me.uv_layers:
        me.uv_layers.active_index=me.uv_layers.find('BakeUV')
        for u in me.uv_layers:u.active_render=u.name=='BakeUV'
    else:
        me.uv_layers.active_index=me.uv_layers.find(old.uv_layers.active.name)
        for u in me.uv_layers:u.active_render=old.uv_layers[u.name].active_render
    ob=bpy.data.objects.new(name,me);bpy.context.scene.collection.objects.link(ob)
    ob.matrix_world=source.matrix_world.copy();ob['repair_part']=True
    err=max(angle(Vector(n),me.corner_normals[i].vector) for i,n in enumerate(normals))
    assert err<.1,(name,'corner normal copy failure',err)
    for p,t in zip(me.polygons,ts):
        for a,b in zip(p.loop_indices,t.loops):
            assert tuple(me.vertices[me.loops[a].vertex_index].co)==tuple(old.vertices[old.loops[b].vertex_index].co)
    return ob,used,{'name':name,'original_triangles':list(ids),'vertices':len(used),'triangles':len(ts),'split_normal_copy_max_deg':err}


def side_source_uv(ob, face_ids):
    me=ob.data; changed=[]; face_set=set(face_ids)
    for i in face_ids:
        p=me.polygons[i];sx=abs(p.normal.x)>=abs(p.normal.y)
        for li in p.loop_indices:
            v=me.vertices[me.loops[li].vertex_index].co
            horizontal=-v.y if sx else v.x
            me.uv_layers['RockScanUV'].data[li].uv=(horizontal/2+.31,v.z/2+.09)
            me.uv_layers['SoilScanUV'].data[li].uv=(horizontal/2.5+.13,v.z/2.5+.27)
        changed.append(i)
    me.calc_loop_triangles();areas={n:[] for n in ('RockScanUV','SoilScanUV')}
    for t in me.loop_triangles:
        if t.polygon_index not in face_set:continue
        for n in areas:
            a,b,c=[me.uv_layers[n].data[li].uv for li in t.loops]
            areas[n].append(abs((b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x))*.5)
    result={'object':ob.name,'changed_side_polygons':changed,'triangles':len(next(iter(areas.values()))),
            'minimum_uv_area':{n:min(v) for n,v in areas.items()},'Rocky_metres':2.,'Sandy_metres':2.5}
    assert all(min(v)>1e-14 for v in areas.values()),result
    return result


def raster_owners(me):
    me.calc_loop_triangles();uv=me.uv_layers['BakeUV'];owner=np.full((SIZE,SIZE),-1,np.int32)
    overlap=0
    for t in me.loop_triangles:
        q=np.array([tuple(uv.data[i].uv) for i in t.loops],np.float64);a,b,c=q
        det=np.cross(b-a,c-a).item();assert abs(det)>1e-14
        x0=max(0,int(math.floor(q[:,0].min()*SIZE-.5)));x1=min(SIZE-1,int(math.ceil(q[:,0].max()*SIZE-.5)))
        y0=max(0,int(math.floor(q[:,1].min()*SIZE-.5)));y1=min(SIZE-1,int(math.ceil(q[:,1].max()*SIZE-.5)))
        yy,xx=np.mgrid[y0:y1+1,x0:x1+1];px=(xx+.5)/SIZE-a[0];py=(yy+.5)/SIZE-a[1]
        b1=(px*(c[1]-a[1])-py*(c[0]-a[0]))/det;b2=((b[0]-a[0])*py-(b[1]-a[1])*px)/det
        inside=(b1>1e-7)&(b2>1e-7)&(1-b1-b2>1e-7);block=owner[y0:y1+1,x0:x1+1]
        overlap+=int((inside&(block>=0)).sum());block[inside]=t.index
    assert overlap==0,('UV interior overlap',overlap)
    return owner


def new_image(name, space, directory):
    im=bpy.data.images.new(name,width=SIZE,height=SIZE,alpha=False,float_buffer=False)
    im.colorspace_settings.name=space;im.generated_color=(1,0,1,1)
    im.file_format='PNG';im.filepath_raw=str(directory/(name+'.png'));return im


def source_stage_result(stage):
    p=Path(os.environ['RECOVERY_REPAIR_PREVIOUS']).resolve()
    assert p.is_relative_to(HERE)
    r=json.loads((p/'result.json').read_text(encoding='utf-8'));assert r['stage']==stage and r['status']=='PASS',r
    blend=p/r['blend'];assert sha(blend)==r['blend_sha256'],str(blend)
    return p,r,blend
