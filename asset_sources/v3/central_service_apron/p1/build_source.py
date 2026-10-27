"""One source build, actual reopen and one fixed-direction preview. Lease required."""
from pathlib import Path
import os,sys,json,time,math,traceback,hashlib
sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
sys.path.insert(0,str(HERE))
import bpy
from mathutils import Vector,Matrix
import geometry as geo
import materials
OUT=Path(os.environ['CENTRAL_APRON_OUT']).resolve();assert OUT.is_relative_to(HERE)
CONFIG=json.loads((HERE/'config.json').read_text(encoding='utf-8'))
ORIGIN=CONFIG['origin']

def dump(name,data):
    (OUT/name).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

def bg(p):return (p[0]-ORIGIN[0],-(p[2]-ORIGIN[2]),p[1])

def editable_mesh(name,rows,mats):
    vertices=[];faces=[];metric=[];runtime=[];original=[];normals=[];tangents=[];tints=[];mapping=[];residuals=[]
    role=rows[0]['role'];assert all(r['role']==role for r in rows)
    for row in rows:
        triangles,skip=geo.triangulate(row,ORIGIN);residuals.extend(skip)
        for t in triangles:
            start=len(vertices);vertices.extend(t['positions']);faces.append((start,start+1,start+2))
            mapping.append({'input_triangle':row['input_triangle'],'source_final_triangle':row['source_final_triangle'],
                            'barycentric':[row['barycentric'][i] for i in t['indices']]})
            for i in t['indices']:
                x,z=row['poly'][i];metric.append((x,z));offset=(.828,1.368) if role=='repair' else (0,0)
                runtime.append(((x+offset[0])/CONFIG['concrete_period_m'],(z+offset[1])/CONFIG['concrete_period_m']))
                original.append(row['original_uv'][i]);normals.append(row['original_normal']);tangents.append(row['original_tangent'])
                v=materials.use_tint(x,z,role);tints.append((v,v,v,1))
    if not faces:return None,[],residuals
    me=bpy.data.meshes.new(name);me.from_pydata(vertices,[],faces);me.update();me.materials.append(mats[role])
    for key,values in [('SourceMetric',metric),('RuntimeUV',runtime),('OriginalDryUV',original)]:
        uv=me.uv_layers.new(name=key)
        for loop,value in zip(uv.data,values):loop.uv=value
    me.uv_layers.active=me.uv_layers['RuntimeUV'];me.uv_layers['RuntimeUV'].active_render=True
    for key in ['input_triangle','source_final_triangle']:
        attr=me.attributes.new(key,'INT','FACE');attr.data.foreach_set('value',[m[key] for m in mapping])
    for key,values in [('OriginalDryNormal',normals),('OriginalDryTangentXYZ',[v[:3] for v in tangents])]:
        attr=me.attributes.new(key,'FLOAT_VECTOR','CORNER')
        attr.data.foreach_set('vector',[v for xyz in values for v in xyz])
    attr=me.attributes.new('OriginalDryTangentSign','FLOAT','CORNER');attr.data.foreach_set('value',[v[3] for v in tangents])
    attr=me.color_attributes.new(name='UseTint',type='FLOAT_COLOR',domain='CORNER')
    attr.data.foreach_set('color',[v for rgba in tints for v in rgba])
    # New flat surface gets its actual geometric normal; quantized original
    # engine normal is separately preserved above, not silently called identical.
    me.normals_split_custom_set([(0,0,1)]*len(me.loops))
    ob=bpy.data.objects.new(name,me);bpy.context.scene.collection.objects.link(ob)
    ob['apron_deliverable']=True;ob['surface_role']=role
    assert all(p.normal.z>.9999 and p.area>0 for p in me.polygons)
    return ob,mapping,residuals

def geometry_signature():
    rows=[]
    for o in sorted(bpy.context.scene.objects,key=lambda x:x.name):
        if not o.get('apron_deliverable'):continue
        me=o.data
        rows.append({'name':o.name,'matrix':[list(v) for v in o.matrix_world],
                     'positions':[list(v.co) for v in me.vertices],'polygons':[list(p.vertices) for p in me.polygons],
                     'uv':{u.name:[list(x.uv) for x in u.data] for u in me.uv_layers},
                     'materials':[m.name for m in me.materials],
                     'ids':[v.value for v in me.attributes['input_triangle'].data]})
    return hashlib.sha256(json.dumps(rows,sort_keys=True,separators=(',',':')).encode()).hexdigest()

def context():
    records=[];loaded={}
    for row in json.loads((HERE/'context.json').read_text(encoding='utf-8')):
        path=ROOT/row['path'];assert geo.sha(path)==row['sha256']
        if row['path'] not in loaded:
            before=set(bpy.data.objects);bpy.ops.import_scene.gltf(filepath=str(path));imported=list(set(bpy.data.objects)-before)
            loaded[row['path']]=[]
            for ob in imported:
                if ob.type!='MESH':continue
                parent=ob;names=[]
                while parent:names.append(parent.name.split('.')[0]);parent=parent.parent
                loaded[row['path']].append((ob,ob.matrix_world.copy(),names))
            for ob in imported:
                ob.hide_render=True;ob.hide_set(True)
        for ob,matrix,names in loaded[row['path']]:
            if row.get('variant') and row['variant'] not in names:continue
            copy=ob.copy();copy.parent=None;bpy.context.scene.collection.objects.link(copy)
            copy.matrix_world=Matrix.Translation(Vector(bg(row['origin']))) @ Matrix.Rotation(math.radians(row.get('turn',0)),4,'Z') @ matrix
            copy.name='REVIEW_ONLY_'+ob.name;copy['review_context_only']=True;copy.hide_render=False;copy.hide_set(False)
        records.append(row)
    for im in bpy.data.images:
        if im.source=='FILE' and not im.packed_file:
            resolved=Path(bpy.path.abspath(im.filepath)).resolve()
            if not resolved.is_relative_to(OUT):im.pack()
    return records

def original_floor_context(remainder,mats):
    """Show original retained surface and actual raised floor, never export them."""
    vertices=[];faces=[]
    for row in remainder:
        p=row['poly']
        if geo.signed_area(p)>0:p=list(reversed(p))
        for i in range(1,len(p)-1):
            if geo.area([p[0],p[i],p[i+1]])==0:continue
            k=len(vertices);vertices.extend(bg((x,0,z)) for x,z in [p[0],p[i],p[i+1]]);faces.append((k,k+1,k+2))
    me=bpy.data.meshes.new('OriginalRetainedDrySurface');me.from_pydata(vertices,[],faces);me.update()
    ob=bpy.data.objects.new('REVIEW_ONLY_OriginalRetainedDrySurface',me);bpy.context.scene.collection.objects.link(ob);ob['review_context_only']=True
    mat,b,_,_=materials.opaque('OriginalGreyboxContext');b.inputs['Base Color'].default_value=(.23,.27,.24,1);b.inputs['Roughness'].default_value=.95;me.materials.append(mat)
    # This is the existing opaque 4x1x4m raised floor, not a flattened void.
    bpy.ops.mesh.primitive_cube_add(size=1,location=bg((0,.5,-4)))
    floor=bpy.context.object;floor.name='REVIEW_ONLY_ExistingUnderDeckFloor';floor.dimensions=(4,4,1);floor['review_context_only']=True;floor.data.materials.append(mat)

def studio():
    sc=bpy.context.scene;sc.render.engine='CYCLES';sc.cycles.device='CPU';sc.cycles.samples=24;sc.cycles.use_denoising=True
    sc.render.threads_mode='FIXED';sc.render.threads=2
    sc.render.resolution_x=1440;sc.render.resolution_y=1080;sc.render.resolution_percentage=100
    sc.view_settings.view_transform='Standard';sc.view_settings.look='None';sc.view_settings.exposure=0;sc.view_settings.gamma=1
    world=bpy.data.worlds.new('ApprovedYardNeutralStudio');world.use_nodes=True;sc.world=world
    world.node_tree.nodes['Background'].inputs[0].default_value=(.35,.37,.39,1)
    world.node_tree.nodes['Background'].inputs[1].default_value=.35
    for name,at,power,size in [('Key',(-7.5,-15,22.5),6875,22.5),('Fill',(12.5,10,15),3125,17.5)]:
        d=bpy.data.lights.new(name,'AREA');d.energy=power;d.shape='DISK';d.size=size
        o=bpy.data.objects.new(name,d);sc.collection.objects.link(o);o.location=at;o.rotation_euler=(-o.location).to_track_quat('-Z','Y').to_euler()
    camdata=bpy.data.cameras.new('FixedObliqueSourceReview');cam=bpy.data.objects.new('FixedObliqueSourceReview',camdata);sc.collection.objects.link(cam);sc.camera=cam
    # Actual production direction: camera-world offset (32,39.8,32). One complete
    # source view uses fit scale; this is not a claim of actual Godot26m capture.
    t=Vector((0,0,0));delta=Vector((32,-32,39.8));cam.location=t+delta;cam.rotation_euler=(-delta).to_track_quat('-Z','Y').to_euler();camdata.type='ORTHO'
    inv=cam.rotation_euler.to_matrix().transposed();projected=[]
    for ob in sc.objects:
        if ob.get('apron_deliverable'):projected.extend(inv@(ob.matrix_world@v.co-t) for v in ob.data.vertices)
    aspect=sc.render.resolution_x/sc.render.resolution_y
    camdata.ortho_scale=max(max(abs(p.x) for p in projected)*2,max(abs(p.y) for p in projected)*2*aspect)*1.12
    # Low neutral studio background, no new Y0 sheet covering the true holes.
    bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-3.2));ob=bpy.context.object;ob.name='REVIEW_ONLY_Background'
    mat,b,_,_=materials.opaque('ReviewBackground');b.inputs['Base Color'].default_value=(.18,.19,.20,1);b.inputs['Roughness'].default_value=1;ob.data.materials.append(mat)
    return {'direction_godot':[32,39.8,32],'ortho_scale':camdata.ortho_scale,'complete_source_view':True,'not_actual_game_camera':True}

def main():
    began=time.monotonic();bpy.ops.wm.read_factory_settings(use_empty=True)
    source,source_report=geo.read_input(os.environ['CENTRAL_APRON_GEOMETRY'],os.environ['CENTRAL_APRON_GROUP'])
    rows,remainder,partition=geo.partition(source,CONFIG)
    dump('partition.json',partition);dump('remaining_triangular_regions.json',remainder);dump('input_readback.json',source_report)
    images,deps=materials.load_images(HERE,OUT);mats=materials.make(images,CONFIG)
    mapping={};residuals=[];objects=[]
    for name in sorted({r['part'] for r in rows}):
        ob,mp,rr=editable_mesh(name,[r for r in rows if r['part']==name],mats)
        if ob:objects.append(ob);mapping[name]=mp
        residuals.extend(rr)
    count=sum(len(o.data.polygons) for o in objects);assert count<=CONFIG['maximum_triangles']
    assert sum(r['area_m2'] for r in residuals)<=1e-6
    assert all(o.matrix_world==Matrix.Identity(4) for o in objects)
    points=[tuple(v.co) for o in objects for v in o.data.vertices]
    bounds=[[min(p[k] for p in points) for k in range(3)],[max(p[k] for p in points) for k in range(3)]]
    assert bounds[0][2]==bounds[1][2]==0
    dump('source_face_mapping.json',mapping)
    geometry={'triangles':count,'editable_parts':len(objects),'materials':3,'origin_godot':ORIGIN,'local_blender_bounds':bounds,
              'float32_residuals':residuals,'replacement_area_m2':partition['replacement_area_m2'],
              'normal_difference_from_original_quantized_engine_degrees':max(math.degrees(math.atan2(math.hypot(r['original_normal'][0],r['original_normal'][2]),r['original_normal'][1])) for r in rows),
              'collision':'none exported or changed; Y0 original floor kept; UnderDeckFloor excluded'}
    dump('geometry.json',geometry)
    contexts=context();original_floor_context(remainder,mats);camera=studio();before=geometry_signature()
    blend=OUT/'central_service_apron_editable.blend'
    # Resolve old context before changing .blend location; keep our3 external PNG
    # beside the source and pack imported GLB images only.
    for im in images.values():im.filepath=bpy.path.relpath(str(Path(bpy.path.abspath(im.filepath)).resolve()),start=str(OUT))
    bpy.ops.wm.save_as_mainfile(filepath=str(blend),relative_remap=False)
    bpy.ops.wm.open_mainfile(filepath=str(blend));assert geometry_signature()==before
    expected={Path(d['path']).name:d for d in deps};reopened=[]
    for im in bpy.data.images:
        if im.source!='FILE' or im.packed_file:continue
        p=Path(bpy.path.abspath(im.filepath)).resolve();row=expected[p.name]
        assert p.is_file() and geo.sha(p)==row['sha256'];pixel=list(im.pixels[:4])
        assert im.has_data and len(pixel)==4 and all(map(math.isfinite,pixel)) and list(im.size)==[2048,2048]
        reopened.append({'name':im.name,'path':str(p),'sha256':geo.sha(p),'size':list(im.size),'pixel':pixel})
    assert len(reopened)==3
    path=OUT/'01-central-service-apron-source.png';bpy.context.scene.render.filepath=str(path);bpy.ops.render.render(write_still=True)
    assert path.is_file() and geometry_signature()==before
    for r in contexts:assert geo.sha(ROOT/r['path'])==r['sha256']
    dump('result.json',{'status':'SOURCE_RENDERED_PENDING_PERSONAL_ROOT_REVIEW','pid':os.getpid(),'elapsed_seconds':time.monotonic()-began,
        'source':str(blend),'source_sha256':geo.sha(blend),'image':str(path),'image_sha256':geo.sha(path),
        'geometry':geometry,'geometry_signature':before,'images_reopened':reopened,'review_only_context':contexts,'camera':camera,
        'scope':'source only, no GLB, no runtime mutation, no physics or game visual verification'})

if __name__=='__main__':
    try:main()
    except Exception as exc:
        dump('failure.json',{'error':repr(exc),'traceback':traceback.format_exc(),'pid':os.getpid()})
        try:bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'failed_source.blend'),relative_remap=False)
        except Exception:pass
        raise
