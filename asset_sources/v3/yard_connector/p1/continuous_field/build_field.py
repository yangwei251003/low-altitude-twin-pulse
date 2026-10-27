"""One actual clipped field source + two views. No runtime/GLB/collision writes."""
from pathlib import Path
import sys,os,json,time,math,hashlib,shutil,struct,traceback
import bpy
from mathutils import Vector,Matrix
HERE=Path(__file__).resolve().parent; ROOT=HERE.parents[4]
sys.path.insert(0,str(HERE))
import field_geometry as geo
import materials as mats
OUT=Path(os.environ['YARD_FIELD_OUT']).resolve(); assert OUT.is_relative_to(HERE)
PARTS=[]; ORIGIN=(-5.7,0,19.25)
ROUNDING=[]
def dump(name,data): (OUT/name).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def bg(x,y,z): return (x-ORIGIN[0],-(z-ORIGIN[2]),y)
def mesh_piece(name,polygons,mat,y=0):
    vertices=[]; faces=[]; source_ids=[]; visible_ids=[]
    skipped=0.0
    for row in polygons:
        p=row['poly']; signed=geo.signed_area(p)
        if signed>0: p=list(reversed(p)) # Godot XZ positive area maps to Blender -Z.
        for i in range(1,len(p)-1):
            tri=[p[0],p[i],p[i+1]]; ar=geo.area(tri)
            if ar==0: continue
            local=[tuple(struct.unpack('<f',struct.pack('<f',v))[0] for v in bg(x,y,z)) for x,z in tri]
            q=[(v[0],v[1]) for v in local]
            position_error=max(math.dist(v,bg(*p3)) for v,p3 in zip(local,[(x,y,z) for x,z in tri]))
            assert position_error<=1e-5
            if geo.area(q)==0:
                longest=max(math.dist(tri[k],tri[(k+1)%3]) for k in range(3)); altitude=2*ar/longest
                assert altitude<=1e-5,('not a float32 residual',row,altitude)
                ROUNDING.append({'source_id':row['source_id'],'visible_id':row['visible_id'],'role':row['role'],'original_area_m2':ar,'original_altitude_m':altitude,'maximum_position_error_m':position_error,'reason':'exactly collinear after required Blender float32 local coordinate storage'})
                skipped+=ar; continue
            start=len(vertices); vertices.extend(local); faces.append((start,start+1,start+2))
            source_ids.append(row['source_id']); visible_ids.append(row['visible_id'])
    me=bpy.data.meshes.new(name); me.from_pydata(vertices,[],faces); me.update()
    uv=me.uv_layers.new(name='SourceMetric'); uv.active_render=True
    for loop in me.loops:
        co=me.vertices[loop.vertex_index].co; uv.data[loop.index].uv=(co.x+ORIGIN[0],-co.y+ORIGIN[2])
    for label,values in [('source_final_triangle_id',source_ids),('input_visible_triangle_id',visible_ids)]:
        attr=me.attributes.new(label,'INT','FACE'); attr.data.foreach_set('value',values)
    me.normals_split_custom_set([(0,0,1)]*len(me.loops))
    ob=bpy.data.objects.new(name,me); bpy.context.scene.collection.objects.link(ob); me.materials.append(mat)
    ob['yard_deliverable']=True; ob['cache_family']=mat['cache_family']; ob['source_kind']='actual clipped visible top'
    PARTS.append(ob); return ob,skipped

def hardware_box(name,rect,lo,hi,mat):
    x0,x1,z0,z1=rect; p=[(x0,z0),(x1,z0),(x1,z1),(x0,z1)]
    vertices=[bg(x,y,z) for y in (lo,hi) for x,z in p]
    # Normals explicitly outward in Blender mapping.
    faces=[(0,1,2,3),(7,6,5,4),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)]
    me=bpy.data.meshes.new(name); me.from_pydata(vertices,[],faces); me.update()
    uv=me.uv_layers.new(name='SourceMetric'); uv.active_render=True
    for face in me.polygons:
        axis=max(range(3),key=lambda k:abs(face.normal[k]))
        for li in face.loop_indices:
            co=me.vertices[me.loops[li].vertex_index].co
            uv.data[li].uv=(co.x+ORIGIN[0],-co.y+ORIGIN[2]) if axis==2 else ((-co.y+ORIGIN[2],co.z) if axis==0 else (co.x+ORIGIN[0],co.z))
    ob=bpy.data.objects.new(name,me); bpy.context.scene.collection.objects.link(ob); me.materials.append(mat)
    ob['yard_deliverable']=True; ob['cache_family']='local'; PARTS.append(ob)

def build(rows,material,config):
    stats={}; removed=0.0
    for role in sorted({r['role'] for r in rows}):
        selected=[r for r in rows if r['role']==role]
        y=config['seal_y'] if role=='seal' else config['inlet_bottom_y'] if role=='inlet' else 0.0
        ob,skipped=mesh_piece('Field_'+role,selected,material[role],y); removed+=skipped
        stats[role]={'pieces':len(selected),'triangles':len(ob.data.polygons),'area_m2':sum(geo.area(r['poly']) for r in selected),'y':y}
    x0,x1,z0,z1=config['inlet_rect']; w=.018
    for name,r in [('South',(x0,x1,z1-w,z1)),('North',(x0,x1,z0,z0+w)),('West',(x0,x0+.024,z0+w,z1-w)),('East',(x1-.024,x1,z0+w,z1-w))]:
        hardware_box('InletFrame_'+name,r,-.015,0,material['teal'])
    for i in range(36):
        x=x0+.045+i*.060; hardware_box('Grate_%02d'%i,(x,x+.014,z0+w,z1-w),-.014,-.001,material['steel'])
    count=0; points=[]
    for ob in PARTS:
        ob.data.calc_loop_triangles(); count+=len(ob.data.loop_triangles)
        assert all(abs(ob.matrix_world[r][c]-(1 if r==c else 0))<1e-8 for r in range(4) for c in range(4))
        if ob.get('source_kind'):
            for face in ob.data.polygons:
                p=[tuple(ob.data.vertices[i].co) for i in face.vertices]
                cross=(p[1][0]-p[0][0])*(p[2][1]-p[0][1])-(p[2][0]-p[0][0])*(p[1][1]-p[0][1])
                assert cross>0,(ob.name,face.index,cross)
        for loop in ob.data.uv_layers['SourceMetric'].data: assert all(math.isfinite(v) for v in loop.uv)
        points.extend((v.co.x+ORIGIN[0],v.co.z,-v.co.y+ORIGIN[2]) for v in ob.data.vertices)
    bounds=[[min(p[k] for p in points) for k in range(3)],[max(p[k] for p in points) for k in range(3)]]
    assert bounds[0][1]>=-.01501 and bounds[1][1]<=.00001
    assert count<20000,('unexpected triangulation growth',count)
    assert removed<=geo.AREA_EPS
    return {'editable_parts':len(PARTS),'triangles':count,'world_bounds':bounds,'origin_godot':ORIGIN,'roles':stats,'float32_collinear_residuals':ROUNDING,'degenerate_fan_area_removed_m2':removed,
            'scope':'actual visible-domain top surfaces; original float32 micro gaps preserved, no collider/export; inlet bottom and seals conservatively collide at existingY0'}

def context():
    """Read-only real authored court and pit, review only; not part of deliverable."""
    records=[]
    def load(path):
        before=set(bpy.data.objects); digest=geo.sha(path); bpy.ops.import_scene.gltf(filepath=str(path))
        imported=list(set(bpy.data.objects)-before); assert geo.sha(path)==digest
        records.append({'path':str(path),'sha256':digest}); return imported
    def copy_mesh(ob,at,turn):
        copy=ob.copy(); copy.parent=None; copy.name='REVIEW_ONLY_'+ob.name; bpy.context.scene.collection.objects.link(copy)
        copy.matrix_world=Matrix.Translation(Vector(bg(*at))) @ Matrix.Rotation(math.radians(turn),4,'Z') @ ob.matrix_world.copy()
        copy['review_context_only']=True
    rows=[('',(-19,0,15),0),('PlainP2West',(-13,0,15),0),('PlainB',(-7,0,15),0),('PlainP2West',(-19,0,21),-90),('PlainB',(-13,0,21),0),('PlainA',(-7,0,21),0),('PlainA',(-1,0,15),0),('PlainB',(5,0,15),0)]
    for path,is_plain in [(ROOT/'assets/v3/clinic_ground/clinic_ground.glb',False),(ROOT/'assets/v3/clinic_ground/clinic_ground_plain_v2.glb',True)]:
        imported=load(path)
        for variant,at,turn in rows:
            if bool(variant)!=is_plain: continue
            for ob in imported:
                if ob.type!='MESH': continue
                names=[]; current=ob
                while current: names.append(current.name); current=current.parent
                if not variant or variant in names: copy_mesh(ob,at,turn)
        for ob in imported: bpy.data.objects.remove(ob,do_unlink=True)
    imported=load(ROOT/'assets/v3/environment/inspection_pit/inspection_pit.glb')
    for ob in imported:
        if ob.type=='MESH': copy_mesh(ob,(-17.625,0,5.75),0)
    for ob in imported: bpy.data.objects.remove(ob,do_unlink=True)
    # Imported GLB image dependencies are packed. Original editable material inputs stay external.
    for im in bpy.data.images:
        if im.source=='FILE' and not im.packed_file and 'source_inputs' not in im.filepath: im.pack()
    return records

def studio():
    sc=bpy.context.scene; sc.render.engine='CYCLES'; sc.cycles.device='CPU'; sc.render.threads_mode='FIXED'; sc.render.threads=2
    sc.cycles.samples=24; sc.cycles.use_denoising=True; sc.render.resolution_x=1536; sc.render.resolution_y=1024; sc.render.resolution_percentage=100
    sc.view_settings.view_transform='Standard'; sc.view_settings.look='None'; sc.view_settings.exposure=0; sc.view_settings.gamma=1
    world=bpy.data.worlds.new('SameNeutralStudio'); sc.world=world; world.use_nodes=True
    world.node_tree.nodes['Background'].inputs[0].default_value=(.35,.37,.39,1); world.node_tree.nodes['Background'].inputs[1].default_value=.35
    for name,at,power,size in [('Key',(-7.5,-15,22.5),6875,22.5),('Fill',(12.5,10,15),3125,17.5)]:
        data=bpy.data.lights.new(name,'AREA'); data.energy=power; data.shape='DISK'; data.size=size
        ob=bpy.data.objects.new(name,data); sc.collection.objects.link(ob); ob.location=at; ob.rotation_euler=(-ob.location).to_track_quat('-Z','Y').to_euler()
    data=bpy.data.cameras.new('FieldReview'); camera=bpy.data.objects.new('FieldReview',data); sc.collection.objects.link(camera); data.type='ORTHO'; sc.camera=camera
    # Studio below pit bottom, never fills the actual pit/shore interface atY0.
    bpy.ops.mesh.primitive_plane_add(size=250,location=(0,0,-3.2)); floor=bpy.context.object; floor.name='REVIEW_ONLY_Studio'; floor['review_context_only']=True
    floor.data.materials.append(mats.solid('NeutralFloor',(.18,.19,.20),1))

def camera(target,scale):
    cam=bpy.context.scene.camera; t=Vector(bg(*target)); offset=Vector((9,-14,24))*2
    cam.location=t+offset; cam.rotation_euler=(-offset).to_track_quat('-Z','Y').to_euler(); cam.data.ortho_scale=scale

def fit_complete_view(target):
    camera(target,60); cam=bpy.context.scene.camera; inverse=cam.rotation_euler.to_matrix().transposed(); t=Vector(bg(*target))
    projected=[]
    for ob in bpy.context.scene.objects:
        if ob.type!='MESH' or ob.name=='REVIEW_ONLY_Studio': continue
        if not (ob.get('yard_deliverable') or ob.get('review_context_only')): continue
        projected.extend(inverse @ (ob.matrix_world @ v.co-t) for v in ob.data.vertices)
    aspect=bpy.context.scene.render.resolution_x/bpy.context.scene.render.resolution_y
    cam.data.ortho_scale=max(2*max(abs(v.x) for v in projected),2*max(abs(v.y) for v in projected)*aspect)*1.08
    return cam.data.ortho_scale

def main():
    start=time.monotonic(); bpy.ops.wm.read_factory_settings(use_empty=True)
    config=json.loads((HERE/'field_config.json').read_text(encoding='utf-8'))
    export,source,input_report=geo.read_export(os.environ['YARD_FIELD_GEOMETRY'])
    rows,partition=geo.partition(source,export['report'],config); dump('partition.json',partition); dump('actual_input.json',input_report)
    images,deps=mats.load_images(ROOT,HERE.parent/'revision2/inputs.json',OUT); material=mats.make_materials(images,config)
    geometry=build(rows,material,config); dump('geometry.json',geometry)
    contexts=context(); studio(); fit_complete_view((-5.7,0,14.5))
    source_path=OUT/'yard_connector_field_editable.blend'
    bpy.ops.wm.save_as_mainfile(filepath=str(source_path),relative_remap=False)
    for im in images.values(): im.filepath=bpy.path.relpath(str(Path(bpy.path.abspath(im.filepath)).resolve()))
    bpy.ops.wm.save_as_mainfile(filepath=str(source_path),relative_remap=False)
    expected={Path(r['local']).name:r for r in deps}; bpy.ops.wm.open_mainfile(filepath=str(source_path))
    checked=[]
    for im in bpy.data.images:
        if im.source!='FILE' or im.packed_file: continue
        p=Path(bpy.path.abspath(im.filepath)).resolve(); row=expected[p.name]
        assert p.is_file() and geo.sha(p)==row['sha256']; im.reload(); pixels=list(im.pixels[:4])
        assert len(pixels)==4 and all(math.isfinite(v) for v in pixels) and im.has_data and list(im.size)==row['size']
        checked.append({'path':str(p),'sha256':geo.sha(p),'size':list(im.size),'pixel':pixels})
    assert len(checked)==4
    renders=[]
    for name,target,scale in [('01-continuous-field-and-existing-court.png',(-5.7,0,14.5),None),('02-pit-court-connection-26m.png',(-15.5,0,14.5),26)]:
        if scale is None: actual_scale=fit_complete_view(target)
        else: camera(target,scale); actual_scale=scale
        path=OUT/name; bpy.context.scene.render.filepath=str(path); bpy.ops.render.render(write_still=True)
        assert path.is_file(); renders.append({'path':str(path),'sha256':geo.sha(path),'camera_target_godot':target,'ortho_scale':actual_scale})
    for row in contexts: assert geo.sha(row['path'])==row['sha256']
    assert geo.sha(input_report['manifest'])==input_report['manifest_sha256']
    dump('result.json',{'status':'SOURCE_RENDERED_NEEDS_PERSONAL_AND_ROOT_REVIEW','pid':os.getpid(),'elapsed_seconds':time.monotonic()-start,
        'source':str(source_path),'source_sha256':geo.sha(source_path),'geometry':geometry,'images_reopened':checked,'renders':renders,'review_context_readonly':contexts,
        'scope':'full actual clipped field source and read-only existing288m2/pit GLB context; no game/runtime/collision/bake/export','lighting':'same neutral radiance recipe as revision2; area lamp dimensionsx2.5, powerx6.25 for field scale'})
if __name__=='__main__':
    try: main()
    except Exception as exc:
        dump('failure.json',{'error':repr(exc),'traceback':traceback.format_exc(),'pid':os.getpid()})
        try: bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'failed_source.blend'),relative_remap=False)
        except Exception: pass
        raise
