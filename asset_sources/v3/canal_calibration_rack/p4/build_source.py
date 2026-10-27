"""P4 bounded high-only manufactured tread, retaining the exact P3 low model."""
from pathlib import Path
import bpy,bmesh,sys,os,json,hashlib,time,math,traceback
sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
OUT=Path(os.environ['RACK_PREVIEW_OUTPUT']).resolve();assert OUT.is_relative_to(HERE)
sys.path.insert(0,str(HERE))
import layout,materials_patch

def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def write(name,data):(OUT/name).write_text(json.dumps(data,ensure_ascii=False,indent=2,allow_nan=False),encoding='utf-8')

def frozen_low():
    rows=[]
    for ob in sorted((x for x in bpy.data.objects if x.get('editable_piece')),key=lambda x:x.name):
        me=ob.data;me.calc_loop_triangles()
        rows.append({'name':ob.name,'matrix':[list(r) for r in ob.matrix_world],
             'vertices':[list(v.co) for v in me.vertices],'triangles':[list(t.vertices) for t in me.loop_triangles],
             'polygons':[[list(p.vertices),p.material_index,p.use_smooth] for p in me.polygons],
             'corner_normals':[list(n.vector) for n in me.corner_normals],
             'UV':{u.name:[list(x.uv) for x in u.data] for u in me.uv_layers},
             'UV_active':[me.uv_layers.active_index,[(u.name,u.active_render) for u in me.uv_layers]],
             'SurfaceUse':[list(x.color) for x in me.color_attributes['SurfaceUse'].data]})
    return {'sha256':hashlib.sha256(json.dumps(rows,sort_keys=True,separators=(',',':')).encode()).hexdigest(),
            'parts':len(rows),'triangles':sum(len(r['triangles']) for r in rows)}

def scene_lock():
    s=bpy.context.scene
    return {'camera':[list(x) for x in s.camera.matrix_world],'ortho_scale':s.camera.data.ortho_scale,
            'resolution':[s.render.resolution_x,s.render.resolution_y,s.render.resolution_percentage],
            'look':[s.view_settings.view_transform,s.view_settings.look,s.view_settings.exposure],
            'lights':[(o.name,[list(x) for x in o.matrix_world],o.data.energy,list(o.data.color),o.data.size) for o in bpy.data.objects if o.type=='LIGHT']}

def images_check(contract):
    rows=[];found=set()
    for im in bpy.data.images:
        if im.source!='FILE':continue
        path=Path(bpy.path.abspath(im.filepath)).resolve();assert path.is_file(),(im.name,str(path))
        pixel=list(im.pixels[:4]);assert len(pixel)==4 and im.has_data and all(math.isfinite(x) for x in pixel),im.name
        digest=sha(path)
        for role,row in contract['textures'].items():
            if path.name==Path(row['path']).name:
                assert digest==row['sha256'] and im.colorspace_settings.name==row['space'],role
                found.add(role)
        rows.append({'image':im.name,'path':str(path),'sha256':digest,'size':list(im.size),'space':im.colorspace_settings.name,'pixel':pixel})
        im.filepath=str(path)
    assert found==set(contract['textures'])
    return rows

def copy_plate(original,material):
    ob=original.copy();ob.data=original.data.copy();ob.name=original.name+'_P4_HighPlate'
    bpy.context.scene.collection.objects.link(ob);ob['editable_piece']=False;ob['high_source']=True;ob['source_plate']=original.name
    before=[tuple(v.co) for v in original.data.vertices];inverse=ob.matrix_world.inverted();max_delta=0.
    for v in ob.data.vertices:
        world=ob.matrix_world@v.co
        delta=layout.RECESS*min(1.,max(0.,(world.z-.310)/.010))
        world.z-=delta;v.co=inverse@world;max_delta=max(max_delta,delta)
    ob.data.update()
    for index,mat in enumerate(ob.data.materials):
        if mat is not None:
            assert mat.name=='CalibrationP3_DeckSteel',(ob.name,index,mat.name)
            ob.data.materials[index]=material
    assert [tuple(v.co) for v in original.data.vertices]==before
    original.hide_render=True;original.hide_set(True)
    ob.hide_render=False;ob.hide_set(False)
    assert max_delta<=.003
    return ob,{'object':ob.name,'original':original.name,'maximum_recess_m':max_delta,'vertex_count':len(ob.data.vertices),'UV_copied_unchanged':True}

def build_ribs(plate,rows,material):
    verts=[];faces=[]
    for row in rows:
        cx,cz=row['centre'];angle=-row['angle'];ca,sa=math.cos(angle),math.sin(angle)
        base=len(verts)
        for length,width,chamfer,height in ((.042,.010,.002,.31735),(.042,.010,.002,.3182),(.039,.007,.0015,.320)):
            for x,y in layout.ring(length,width,chamfer):
                verts.append((cx+x*ca-y*sa,-cz+x*sa+y*ca,height))
        faces.append(tuple(base+i for i in reversed(range(8))))
        for level in range(2):
            for i in range(8):
                j=(i+1)%8;faces.append((base+level*8+i,base+level*8+j,base+(level+1)*8+j,base+(level+1)*8+i))
        faces.append(tuple(base+16+i for i in range(8)))
    mesh=bpy.data.meshes.new(plate+'_P4_EditableRibs');mesh.from_pydata(verts,[],faces);mesh.update()
    ob=bpy.data.objects.new(plate+'_P4_EditableRibs',mesh);bpy.context.scene.collection.objects.link(ob)
    ob['high_source']=True;ob['source_plate']=plate;ob['rib_count']=len(rows);ob['not_runtime_geometry']=True
    mesh.materials.append(material)
    for name in ('MetricUV','PanelUV','FinishUV','SteelUV','TopUV'):mesh.uv_layers.new(name=name)
    mesh.color_attributes.new(name='SurfaceUse',type='FLOAT_COLOR',domain='CORNER')
    seed=hashlib.sha256(plate.encode()).digest();phase=seed[0]/255*.38
    x0,x1,z0,z1=layout.PLATES[plate]
    for poly in mesh.polygons:
        for li in poly.loop_indices:
            co=mesh.vertices[mesh.loops[li].vertex_index].co
            mesh.uv_layers['MetricUV'].data[li].uv=(co.x,co.y)
            mesh.uv_layers['TopUV'].data[li].uv=(co.x,co.y)
            mesh.uv_layers['SteelUV'].data[li].uv=(co.x/1.2+phase,co.y/1.2+seed[1]/255*.2)
            mesh.uv_layers['PanelUV'].data[li].uv=((co.x-x0)/(x1-x0),(-co.y-z0)/(z1-z0))
            mesh.uv_layers['FinishUV'].data[li].uv=(.75,.25)
            mesh.color_attributes['SurfaceUse'].data[li].color=(0,1,0,1)
    mesh.uv_layers.active_index=mesh.uv_layers.find('SteelUV')
    for uv in mesh.uv_layers:uv.active_render=uv.name=='SteelUV'
    return ob

def geometry_report():
    rows=[];points=[]
    for ob in sorted((o for o in bpy.data.objects if o.type=='MESH' and (o.get('editable_piece') or o.get('high_source')) and not o.hide_render),key=lambda o:o.name):
        me=ob.data;me.calc_loop_triangles();bm=bmesh.new();bm.from_mesh(me)
        bad=sum(not e.is_manifold for e in bm.edges);bm.free();assert bad==0,(ob.name,bad)
        for uv in me.uv_layers:assert all(math.isfinite(v) for item in uv.data for v in item.uv)
        points.extend([float(w.x),float(w.z),float(-w.y)] for w in (ob.matrix_world@v.co for v in me.vertices))
        rows.append({'name':ob.name,'triangles':len(me.loop_triangles),'nonmanifold_edges':bad,'rib_count':ob.get('rib_count',0)})
    bounds=[[min(p[i] for p in points) for i in range(3)],[max(p[i] for p in points) for i in range(3)]]
    assert max(abs(a-b) for row,expected in zip(bounds,[[-1.2,0,-1.2],[1.2,.32,1.2]]) for a,b in zip(row,expected))<=1e-5,bounds
    total=sum(r['triangles'] for r in rows);assert total==layout.report()['high_total_triangles_expected'],total
    assert sum(r['rib_count'] for r in rows)==len(layout.layout())
    return {'visible_high_source_parts':len(rows),'actual_triangles':total,'parts':rows,'actual_AABB':bounds,
            'low_triangles_retained':4740,'no_runtime_export':True,'colour_lighting':'P3 locked; eight local paint-edge losses only'}

def material_check():
    mat=bpy.data.materials['CalibrationP4_DeckSteel'];n=mat.node_tree.nodes;links=mat.node_tree.links
    assert 'ManufacturedAntiSlipBump' not in n
    assert any(l.from_node==n['OriginalSteelNormal'] and l.to_node==n['SourcePrincipled'] and l.to_socket.name=='Normal' for l in links)
    assert n['OriginalSteelNormal'].uv_map=='SteelUV'
    return {'real_ribs_no_duplicate_procedural_bump':True,'fine_normal_GL_strength':n['OriginalSteelNormal'].inputs['Strength'].default_value,
            'base_steel_multiplier':list(n['DarkSteelReflectance'].inputs[2].default_value),'local_yellow_edge_losses':8}

def main():
    started=time.monotonic();print(json.dumps({'status':'BLENDER_STARTED','pid':os.getpid(),'cpu_threads':2,'output':str(OUT)}),flush=True)
    contract=json.loads((HERE/'input_contract.json').read_text(encoding='utf-8'));src=ROOT/contract['source']['path'];assert sha(src)==contract['source']['sha256']
    bpy.ops.wm.open_mainfile(filepath=str(src));low=frozen_low();assert low['parts']==51 and low['triangles']==4740
    lock=scene_lock();image_before=images_check(contract)
    material=materials_patch.build(bpy.data.materials['CalibrationP3_DeckSteel']);recess=[];ribs=layout.layout()
    for name in layout.PLATES:
        ob,row=copy_plate(bpy.data.objects[name],material);recess.append(row)
        build_ribs(name,[r for r in ribs if r['plate']==name],material)
    bpy.context.view_layer.update()
    assert frozen_low()==low and scene_lock()==lock
    report=geometry_report();write('geometry_report.json',report);write('recess_report.json',recess);write('layout_actual.json',layout.report());write('images_before_save.json',image_before)
    write('material_chain_check.json',material_check())
    saved=OUT/'calibration_rack_p4_editable.blend';bpy.ops.wm.save_as_mainfile(filepath=str(saved),relative_remap=False);saved_sha=sha(saved)
    bpy.ops.wm.open_mainfile(filepath=str(saved));after=images_check(contract)
    assert frozen_low()==low and scene_lock()==lock and geometry_report()==report
    assert [(r['sha256'],r['space'],r['size']) for r in after]==[(r['sha256'],r['space'],r['size']) for r in image_before]
    write('actual_reopen.json',{'P3_low_geometry_UV_normals_exact':low,'camera_lighting_exact':True,'images':after,'material_chain':material_check()})
    scene=bpy.context.scene;scene.cycles.device='CPU';scene.render.threads_mode='FIXED';scene.render.threads=2
    scene.render.filepath=str(OUT/'01_reference_oblique.png');bpy.ops.render.render(write_still=True)
    assert sha(src)==contract['source']['sha256'] and sha(saved)==saved_sha
    write('result.json',{'status':'SOURCE_RENDERED_PENDING_ACTUAL_REVIEW','pid':os.getpid(),'elapsed_seconds':time.monotonic()-started,
                        'blend':str(saved),'blend_sha256':saved_sha,'image':str(OUT/'01_reference_oblique.png'),'image_sha256':sha(OUT/'01_reference_oblique.png'),
                        'source_P3_unchanged':True,'low_geometry_exact':low,'actual_high_triangles':report['actual_triangles'],
                        'baked':False,'exported':False,'runtime_written':False})

if __name__=='__main__':
    try:main()
    except Exception as exc:
        write('failure.json',{'exception':repr(exc),'traceback':traceback.format_exc(),'pid':os.getpid()})
        try:bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'failed_source.blend'),relative_remap=False)
        except Exception:pass
        raise
