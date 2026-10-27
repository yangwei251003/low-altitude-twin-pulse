"""Source preview only. Root must grant the serial CPU2 window before running."""
from pathlib import Path
import sys, json, hashlib, os, time, shutil, math, struct
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parent))
import bpy
from mathutils import Matrix,Vector
from plan import *
from crop import crop_mesh,surface_copy,bp,gp

def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def dump(path,value):Path(path).write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def signature():
    result={}
    for obj in bpy.data.objects:
        if not obj.get('closure_piece'):continue
        h=hashlib.sha256();mesh=obj.data
        for row in obj.matrix_world:h.update(struct.pack('<4f',*row))
        for v in mesh.vertices:h.update(struct.pack('<3f',*v.co))
        for poly in mesh.polygons:
            h.update(struct.pack('<2i',poly.material_index,len(poly.vertices)))
            h.update(struct.pack('<'+'i'*len(poly.vertices),*poly.vertices))
        for layer in mesh.uv_layers:
            h.update(layer.name.encode())
            for row in layer.data:h.update(struct.pack('<2f',*row.uv))
        for name in ['SourceHeight','SourceX','WaterFacing','RepairUse','ExposedSurface']:
            layer=mesh.attributes.get(name)
            if layer:
                for row in layer.data:h.update(struct.pack('<f',row.value))
        h.update(json.dumps([m.name for m in mesh.materials]).encode())
        result[obj.name]=h.hexdigest()
    return result
def matrix(spec):
    x,z=spec['local_x'],spec['water'];o=spec['origin']
    return Matrix(((x[0],-z[0],0,o[0]),(-x[1],z[1],0,-o[2]),(0,0,1,o[1]),(0,0,0,1)))
def point_inside(point,planes):
    x,y,z=gp(point)
    return all(nx*x+nz*z>=d-1e-7 for nx,nz,d in planes)

def plain(name,color):
    material=bpy.data.materials.new(name);material.use_nodes=True
    node=next(n for n in material.node_tree.nodes if n.type=='BSDF_PRINCIPLED');node.inputs['Base Color'].default_value=(*color,1);node.inputs['Roughness'].default_value=.8
    return material

def scene_context(plan):
    """Read-only old banks as context; never included in the deliverable set."""
    for side,x,angle in [('West',12.6,math.pi/2),('East',16.9,-math.pi/2)]:
        for number,(length,z) in enumerate([(4,4.3),(4,8.3),(4,12.3),(1.3,14.95)]):
            path=ROOT/('assets/v3/i2_canal_revetment/i2_canal_revetment_4m.glb' if length==4 else 'assets/v3/i2_canal_revetment/i2_canal_revetment_1p3.glb')
            before=set(bpy.data.objects);bpy.ops.import_scene.gltf(filepath=str(path))
            imported=set(bpy.data.objects)-before
            transform=Matrix.Translation(bp((x,0,z)))@Matrix.Rotation(angle,4,'Z')
            for obj in imported:
                obj['closure_context_only']=True
                if obj.parent not in imported:obj.matrix_world=transform@obj.matrix_world
    # Flat bed and exact water silhouette are spatial illustration, no collision.
    profile=[(2.3,12.6,16.9),(15.6,12.6,16.9),(19,9.5,22.5),(28,9.5,24.5)]
    polygon=[(l,-1.2,z) for z,l,r in profile]+[(r,-1.2,z) for z,l,r in reversed(profile)]
    mesh=bpy.data.meshes.new('ContextWater');mesh.from_pydata([bp(v) for v in polygon],[],[list(range(len(polygon)))])
    water=bpy.data.objects.new('ContextWater_NotGameplay',mesh);bpy.context.scene.collection.objects.link(water);water.data.materials.append(plain('ContextWater',(0.045,.16,.18)))
    water['closure_context_only']=True
    bpy.ops.mesh.primitive_plane_add(size=200,location=bp((15,-2.81,15)))
    floor=bpy.context.object;floor.name='ContextBed';floor.data.materials.append(plain('ContextBed',(.12,.14,.14)));floor['closure_context_only']=True

def setup_camera(name,at,size):
    target=bp(at);offset=bp((32,39,32))
    camera=bpy.data.objects.new(name,bpy.data.cameras.new(name));bpy.context.scene.collection.objects.link(camera)
    camera.location=target+offset;camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler()
    camera.data.type='ORTHO';camera.data.ortho_scale=size
    return camera

def render_preview(plan,out):
    scene_context(plan)
    scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=16;scene.cycles.use_denoising=True
    scene.render.threads_mode='FIXED';scene.render.threads=2;scene.render.resolution_x=1280;scene.render.resolution_y=720;scene.render.resolution_percentage=100
    scene.world=bpy.data.worlds.new('ClosurePreviewWorld');scene.world.use_nodes=True
    next(n for n in scene.world.node_tree.nodes if n.type=='BACKGROUND').inputs[0].default_value=(.23,.26,.29,1)
    sun=bpy.data.objects.new('Sun',bpy.data.lights.new('Sun','SUN'));bpy.context.scene.collection.objects.link(sun);sun.data.energy=2;sun.rotation_euler=(.5,-.45,-.4)
    scene.view_settings.view_transform='AgX'
    cameras=[('01-default',setup_camera('Default',(14.75,1.8,17),26)),('02-south-joint',setup_camera('SouthJoint',(13.4,-.3,19),15))]
    for name,camera in cameras:
        scene.camera=camera;scene.render.filepath=str(out/(name+'.png'));bpy.ops.render.render(write_still=True)

def main():
    start=time.monotonic();assert sha(SOURCE)==SOURCE_SHA
    out=HERE/'output';out.mkdir(exist_ok=True)
    assert not (out/'i2_revetment_closure_editable.blend').exists(),'preserve previous source attempt'
    plan=build_plan();dump(HERE/'layout_plan.json',plan)
    print(json.dumps({'stage':'build_start','pid':os.getpid(),'source_only':True}),flush=True)
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    source_parts=[o for o in bpy.data.objects if o.get('editable_piece')];assert len(source_parts)==8
    body=bpy.data.objects['ConcreteBody_4m_Closed'];assert body.matrix_world==Matrix.Identity(4)
    frozen_body=body.data.copy()
    inputs=[];(HERE/'source_inputs').mkdir(exist_ok=True)
    for image in bpy.data.images:
        if image.source!='FILE' or not image.filepath:continue
        path=Path(bpy.path.abspath(image.filepath)).resolve();destination=HERE/'source_inputs'/path.name
        if not destination.exists():shutil.copyfile(path,destination)
        assert sha(path)==sha(destination)
        image.filepath=str(destination);image.reload();pixels=tuple(image.pixels[:4])
        assert image.has_data and len(pixels)==4
        inputs.append(dict(path=str(destination.relative_to(ROOT)),sha256=sha(destination)))
    original_objects=list(bpy.data.objects)
    records=[];editable=[];assembly=bpy.data.objects.new('I2RevetmentClosure',None);bpy.context.scene.collection.objects.link(assembly)
    for spec in plan['pieces']:
        mesh,audit=crop_mesh(frozen_body,spec['clip_planes'],spec['id'])
        core=bpy.data.objects.new(spec['id']+'_ClosedEditable',mesh);bpy.context.scene.collection.objects.link(core)
        core.parent=assembly;core.matrix_world=matrix(spec);core['editable_piece']=True;core['closure_piece']=spec['id']
        # Keep true closed construction source. Surface preview omits buried
        # internal joint caps instead of drawing two coincident opaque walls.
        internal=[0,1]
        if spec['id'] in ('WestMouth_03','EastMouth_03'):internal=[0]
        front_min_x=12.6-spec['origin'][0] if spec['segment']=='NorthHead' else None
        preview_mesh=surface_copy(mesh,internal,spec['id']+'_DeliverySurface',front_min_x)
        preview=bpy.data.objects.new(spec['id']+'_Surface',preview_mesh);bpy.context.scene.collection.objects.link(preview)
        preview.parent=assembly;preview.matrix_world=matrix(spec);preview['closure_export_surface']=True;preview['closure_piece']=spec['id']
        core.hide_render=True;core.hide_set(True)
        kept=[];omitted=[]
        for source in source_parts:
            if source==body:continue
            evaluated=source.evaluated_get(bpy.context.evaluated_depsgraph_get())
            inside=all(point_inside(source.matrix_world@v.co,spec['clip_planes']) for v in evaluated.data.vertices)
            if not inside:omitted.append(source.name);continue
            obj=source.copy();obj.data=source.data.copy();bpy.context.scene.collection.objects.link(obj)
            obj.name=spec['id']+'_'+source.name;obj.parent=assembly;obj.matrix_world=matrix(spec)@source.matrix_world
            obj.hide_render=False;obj.hide_set(False);obj['closure_piece']=spec['id'];obj['closure_export_surface']=True
            kept.append(obj.name);editable.append(obj)
        actual=[gp(core.matrix_world@v.co) for v in mesh.vertices]
        bounds=dict(min=[min(v[i] for v in actual) for i in range(3)],max=[max(v[i] for v in actual) for i in range(3)])
        assert abs(bounds['min'][1]+2.8)<1e-5 and abs(bounds['max'][1])<1e-6
        violations=[]
        center=mul(tuple(map(sum,zip(*spec['footprint']))),1/4)
        for a,b in zip(spec['footprint'],spec['footprint'][1:]+spec['footprint'][:1]):
            nx,nz,d=signed_plane(a,b,center)
            violations.append(max(max(0.,d-nx*p[0]-nz*p[2]) for p in actual))
        assert max(violations)<.000003,(spec['id'],'actual source outside planned land-side footprint',violations)
        records.append(dict(id=spec['id'],geometry=audit,world_bounds=bounds,accessories_retained=kept,
            maximum_float32_footprint_error_m=max(violations),
            accessories_omitted_whole_when_crossing_cut=omitted,internal_cap_planes_omitted_from_surface=internal,
            transform=[list(row) for row in core.matrix_world]))
        editable.append(core)
    for obj in original_objects:bpy.data.objects.remove(obj,do_unlink=True)
    bpy.context.view_layer.update()
    source_file=out/'i2_revetment_closure_editable.blend'
    before_save=signature()
    bpy.ops.wm.save_as_mainfile(filepath=str(source_file),relative_remap=False)
    bpy.ops.wm.open_mainfile(filepath=str(source_file));bpy.context.view_layer.update()
    reopened=signature();assert before_save==reopened,'editable source geometry/UV/attribute/material-slot readback mismatch'
    render_preview(plan,out)
    assert sha(SOURCE)==SOURCE_SHA
    report=dict(status='SOURCE_PREVIEW_NOT_RUNTIME',pid=os.getpid(),elapsed=time.monotonic()-start,source_sha256=SOURCE_SHA,
        editable_sha256=sha(source_file),source_images=inputs,piece_count=len(records),pieces=records,plan=plan,
        editable_readback_exact_geometry_uv_attributes=True,editable_signatures=reopened,
        scope='source geometry/material preview; collision and actual Godot camera untested',
        no_runtime_glb=True,no_global_scaling=True)
    dump(out/'source_report.json',report)
    print(json.dumps({'stage':'source_exit','pid':os.getpid(),'seconds':report['elapsed'],'pieces':len(records)}),flush=True)

if __name__=='__main__':main()
