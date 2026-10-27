"""Source-only empty calibration rack. Run only in root-authorized CPU2 slot."""
from pathlib import Path
import bpy,bmesh,math,json,hashlib,os,sys,time,shutil,traceback
from mathutils import Vector
sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
OUT=Path(os.environ['RACK_PREVIEW_OUTPUT']).resolve();assert OUT.is_relative_to(HERE)
sys.path.insert(0,str(HERE))
import materials
PARTS=[]


def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def write(name,data):(OUT/name).write_text(json.dumps(data,ensure_ascii=False,indent=2,allow_nan=False),encoding='utf-8')
def gp(v):return [float(v.x),float(v.z),float(-v.y)]
def bp(x,y,z):return (x,-z,y)


def audit_images():
    result=[]
    for im in bpy.data.images:
        if im.source!='FILE':continue
        p=Path(bpy.path.abspath(im.filepath)).resolve();assert p.is_file(),(im.name,str(p))
        pixels=tuple(im.pixels[:4]);assert len(pixels)==4 and im.has_data and all(math.isfinite(x) for x in pixels),im.name
        result.append({'image':im.name,'path':str(p),'sha256':sha(p),'size':list(im.size),'space':im.colorspace_settings.name,'first_pixel':pixels})
        im.filepath=str(p)
    return result


def add_uv(ob,role):
    me=ob.data;world=[ob.matrix_world@v.co for v in me.vertices]
    low=[min(p[i] for p in world) for i in range(3)];high=[max(p[i] for p in world) for i in range(3)]
    for name in ('MetricUV','PanelUV','FinishUV','SteelUV','TopUV'):me.uv_layers.new(name=name)
    me.color_attributes.new(name='SurfaceUse',type='FLOAT_COLOR',domain='CORNER')
    seed=hashlib.sha256(ob.name.encode()).digest();phase=seed[0]/255*.38
    for poly in me.polygons:
        dominant=max(range(3),key=lambda i:abs(poly.normal[i]));axes=[i for i in range(3) if i!=dominant]
        a,b=axes;sa=max(high[a]-low[a],1e-6);sb=max(high[b]-low[b],1e-6)
        for li in poly.loop_indices:
            co=world[me.loops[li].vertex_index];u=(co[a]-low[a])/sa;v=(co[b]-low[b])/sb
            me.uv_layers['MetricUV'].data[li].uv=(co[a],co[b])
            me.uv_layers['PanelUV'].data[li].uv=(u,v)
            me.uv_layers['SteelUV'].data[li].uv=(co[a]/1.2+phase,co[b]/1.2+seed[1]/255*.2)
            me.uv_layers['TopUV'].data[li].uv=(co.x,co.y)
            # Atlas lower-right teal strip: preserve metre-scale wear near a component edge.
            along,across=(u,v) if sa>=sb else (v,u)
            length,width=max(sa,sb),min(sa,sb);span=min(.94,length/8.5);band=min(.94,width/.8)
            sx=.02+phase*(.94-span);sy=.015+band*across if seed[2]&1 else .985-band*across
            me.uv_layers['FinishUV'].data[li].uv=(.502+.496*(sx+span*along),.002+.496*sy)
            me.color_attributes['SurfaceUse'].data[li].color=(max(0.,1-co.z/.085),1. if poly.normal.z>.75 else 0.,0.,1.)
    me.uv_layers.active_index=me.uv_layers.find('SteelUV')
    for u in me.uv_layers:u.active_render=u.name=='SteelUV'


def finish(ob,name,role,bevel,segments=2):
    ob.name=name;bpy.context.view_layer.objects.active=ob
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if bevel:
        mod=ob.modifiers.new('ManufacturedBevel','BEVEL');mod.width=bevel;mod.segments=segments;mod.affect='EDGES'
        bpy.ops.object.modifier_apply(modifier=mod.name)
    ob['editable_piece']=True;ob['runtime_group']='CalibrationRack';ob['finish']=role
    ob.data.materials.append(MATS[role]);PARTS.append(ob);return ob


def box(name,x0,x1,y0,y1,z0,z1,role,bevel=.006):
    bpy.ops.mesh.primitive_cube_add(size=1,location=bp((x0+x1)/2,(y0+y1)/2,(z0+z1)/2))
    ob=bpy.context.object;ob.dimensions=(x1-x0,z1-z0,y1-y0)
    ob=finish(ob,name,role,bevel);ob['design_bounds']=[x0,x1,y0,y1,z0,z1];return ob


def bolt(name,x,y,z,axis='Y'):
    bpy.ops.mesh.primitive_cylinder_add(vertices=6,radius=.024,depth=.009,location=bp(x,y,z))
    ob=bpy.context.object
    if axis=='Z':ob.rotation_euler.x=math.pi/2
    elif axis=='X':ob.rotation_euler.y=math.pi/2
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    return finish(ob,name,'HardwareSteel',.0014,1)


def top_pocket(x,z):
    plates=[o for o in PARTS if o.name.startswith(('LandingPlate','TopServiceStrip'))]
    targets=[o for o in plates if o['design_bounds'][0]<x<o['design_bounds'][1] and o['design_bounds'][4]<z<o['design_bounds'][5]]
    assert len(targets)==1,(x,z,[o.name for o in targets])
    bpy.ops.mesh.primitive_cylinder_add(vertices=16,radius=.028,depth=.012,location=bp(x,.318,z))
    tool=bpy.context.object;tool.name='TemporaryCounterbore_NOT_ASSET';target=targets[0]
    bpy.context.view_layer.objects.active=target
    modifier=target.modifiers.new('ShallowFlushFastenerPocket','BOOLEAN');modifier.operation='DIFFERENCE';modifier.solver='EXACT';modifier.object=tool
    bpy.ops.object.modifier_apply(modifier=modifier.name);bpy.data.objects.remove(tool,do_unlink=True)


def construct():
    # Continuous structural core, ring and separately editable inset plates.
    box('RackBaseShell',-1.17,1.17,0,.281,-1.17,1.17,'PaintSteel',.018)
    box('RimFront',-1.20,1.20,.235,.32,-1.20,-1.025,'PaintSteel',.009)
    box('RimRear',-1.20,1.20,.235,.32,1.025,1.20,'PaintSteel',.009)
    box('RimLeft',-1.20,-1.025,.235,.32,-1.025,1.025,'PaintSteel',.009)
    box('RimRight',1.025,1.20,.235,.32,-1.025,1.025,'PaintSteel',.009)
    box('TopServiceStrip',-1.021,-.68,.281,.32,-1.021,1.021,'DeckSteel',.002)
    for i,(a,b) in enumerate([(-1.021,-.344),(-.340,.338),(.342,1.021)]):
        box('LandingPlate_'+str(i),-.676,1.021,.281,.32,a,b,'DeckSteel',.002)
    # Corner protectors are within existing collision envelope, recessed below top.
    for sx in (-1,1):
        for sz in (-1,1):
            x0,x1=sorted((sx*1.10,sx*1.195));z0,z1=sorted((sz*1.10,sz*1.195))
            box('CornerGuard_%s_%s'%(sx,sz),x0,x1,.025,.306,z0,z1,'HardwareSteel',.01)
    # Flush side access plates, no protruding doorway/tool/rail fiction.
    for side in (-1,1):
        for i,c in enumerate((-.72,0.,.72)):
            z0,z1=sorted((side*1.168,side*1.185))
            box('SideAccess_%s_%s'%(side,i),c-.28,c+.28,.075,.226,z0,z1,'PaintSteel',.006)
            for dx in (-.235,.235):
                for h in (.104,.197):bolt('SideBolt_%s_%s_%s_%s'%(side,i,dx,h),c+dx,h,side*1.188,'Z')
    for x,z in [(-.94,-.91),(-.75,.91),(-.61,-.91),(.94,-.91),(-.61,.25),(.94,.25),(-.61,.91),(.94,.91)]:
        top_pocket(x,z)
        bolt('TopFastener_%s_%s'%(x,z),x,.3145,z)
    # Add explicit source UVs after the actual shallow counterbores exist.
    for ob in PARTS:add_uv(ob,ob['finish'])


def geometry():
    rows=[];all_points=[];h=hashlib.sha256()
    for ob in sorted(PARTS,key=lambda o:o.name):
        me=ob.data;me.calc_loop_triangles();points=[gp(ob.matrix_world@v.co) for v in me.vertices];all_points+=points
        bm=bmesh.new();bm.from_mesh(me);nonmanifold=sum(not e.is_manifold for e in bm.edges);bm.free()
        assert nonmanifold==0,(ob.name,nonmanifold)
        uv_bad=[]
        for u in me.uv_layers:
            if not all(math.isfinite(c) for q in u.data for c in q.uv):uv_bad.append(u.name)
        assert not uv_bad,(ob.name,uv_bad)
        h.update(ob.name.encode());h.update(repr(points).encode());h.update(repr([list(t.vertices) for t in me.loop_triangles]).encode())
        rows.append({'name':ob.name,'triangles':len(me.loop_triangles),'nonmanifold_edges':nonmanifold,'finish':ob['finish'],'UVs':[u.name for u in me.uv_layers]})
    minimum=[min(v[i] for v in all_points) for i in range(3)];maximum=[max(v[i] for v in all_points) for i in range(3)]
    expected_min=[-1.2,0,-1.2];expected_max=[1.2,.32,1.2]
    assert max(abs(a-b) for a,b in zip(minimum+maximum,expected_min+expected_max))<=1e-5,(minimum,maximum)
    for ob in PARTS:
        if ob.name.startswith(('LandingPlate','TopServiceStrip')):
            top=max(gp(ob.matrix_world@v.co)[1] for v in ob.data.vertices);assert abs(top-.32)<=1e-5
    return {'pieces':rows,'triangles':sum(r['triangles'] for r in rows),'actual_AABB':[minimum,maximum],'geometry_sha256':h.hexdigest(),
            'contract':'Godot origin at ground centre; (x,y,z) -> Blender(x,-z,y). Existing box collider retained by root; no collision exported.',
            'source_material_count':3,'budget_estimate_before_run':'about 3k–5k triangles; actual count above is authoritative'}


def scene_setup():
    scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=32
    scene.render.threads_mode='FIXED';scene.render.threads=2;scene.render.resolution_x=1280;scene.render.resolution_y=1100;scene.render.resolution_percentage=100
    scene.view_settings.view_transform='AgX';scene.view_settings.look='AgX - Medium High Contrast';scene.view_settings.exposure=0
    if scene.world is None:scene.world=bpy.data.worlds.new('ReviewWorld')
    scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.3,.34,.38,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.55
    bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.004));floor=bpy.context.object;floor.name='ReviewGround_NOT_ASSET'
    m=bpy.data.materials.new('NeutralReviewGround');m.use_nodes=True;m.node_tree.nodes.clear()
    bs=m.node_tree.nodes.new('ShaderNodeBsdfPrincipled');bs.inputs['Base Color'].default_value=(.15,.16,.17,1);bs.inputs['Roughness'].default_value=.9
    mo=m.node_tree.nodes.new('ShaderNodeOutputMaterial');m.node_tree.links.new(bs.outputs['BSDF'],mo.inputs['Surface']);floor.data.materials.append(m)
    for name,loc,energy,size in [('Key',(0,-3,6),900,5),('Fill',(-4,1,3),500,4),('Rim',(3,4,5),700,3)]:
        data=bpy.data.lights.new(name,'AREA');data.energy=energy;data.shape='DISK';data.size=size
        ob=bpy.data.objects.new(name,data);scene.collection.objects.link(ob);ob.location=loc;ob.rotation_euler=(Vector((0,0,.1))-ob.location).to_track_quat('-Z','Y').to_euler()
    bpy.ops.object.camera_add(location=(3.6,-4.6,3.8));cam=bpy.context.object;cam.name='ReferenceOblique_NOT_ASSET'
    cam.rotation_euler=(Vector((0,0,.13))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=3.65;scene.camera=cam


def main():
    print(json.dumps({'status':'BLENDER_STARTED','pid':os.getpid(),'cpu_threads':2,'output':str(OUT)}),flush=True)
    start=time.monotonic();contract=json.loads((HERE/'input_contract.json').read_text(encoding='utf-8'));images={};inputs=[]
    bpy.ops.wm.read_factory_settings(use_empty=True);(OUT/'source_inputs').mkdir()
    for key,row in contract['textures'].items():
        src=ROOT/row['path'];assert sha(src)==row['sha256'],str(src)
        dst=OUT/'source_inputs'/src.name;shutil.copy2(src,dst);assert sha(dst)==row['sha256']
        im=bpy.data.images.load(str(dst),check_existing=False);im.colorspace_settings.name=row['space'];tuple(im.pixels[:4]);assert im.has_data
        images[key]=im;inputs.append({'role':key,'path':str(dst),**row})
    global MATS;MATS=materials.build(images);construct();scene_setup();bpy.context.view_layer.update()
    report=geometry();write('geometry_report.json',report);before=report['geometry_sha256'];write('input_images.json',audit_images())
    saved=OUT/'calibration_rack_editable.blend';bpy.ops.wm.save_as_mainfile(filepath=str(saved),relative_remap=False);saved_sha=sha(saved)
    bpy.ops.wm.open_mainfile(filepath=str(saved));PARTS.clear();PARTS.extend(o for o in bpy.data.objects if o.get('editable_piece'))
    reopened=geometry();assert reopened['geometry_sha256']==before;write('reopened_image_check.json',audit_images())
    bpy.context.scene.render.filepath=str(OUT/'01_reference_oblique.png');bpy.ops.render.render(write_still=True)
    assert sha(saved)==saved_sha
    write('result.json',{'status':'SOURCE_RENDERED_PENDING_ACTUAL_IMAGE_REVIEW','pid':os.getpid(),'seconds':time.monotonic()-start,'blend':str(saved),'sha256':saved_sha,'image':str(OUT/'01_reference_oblique.png'),'image_sha256':sha(OUT/'01_reference_oblique.png'),'actual_triangles':report['triangles'],'editable_parts':len(PARTS),'runtime_written':False,'baked':False,'exported':False})


if __name__=='__main__':
    try:main()
    except Exception as exc:
        write('failure.json',{'status':'FAIL_STOP','exception':repr(exc),'traceback':traceback.format_exc(),'pid':os.getpid()})
        try:bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'failed_source.blend'),relative_remap=False)
        except Exception:pass
        raise
