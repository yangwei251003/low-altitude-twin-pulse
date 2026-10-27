"""Editable WestLanding source; two independent original Box envelopes.

This entry is prepared statically. Run only in a Root-assigned Blender window.
The manufacturing tread is an editable high-only source, not runtime geometry.
"""
from pathlib import Path
import sys,os,time,traceback
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parent))
from common import *
import design

RUNTIME_NAMES={('PlatformAssembly','Steel'):'PlatformSteel',('PlatformAssembly','Paint'):'PlatformPaint',
               ('LegAssembly','Steel'):'LegSteel',('LegAssembly','Paint'):'LegPaint'}
TOLERANCE=1e-5

def identity(ob):
    return max(abs(ob.matrix_local[i][j]-(1 if i==j else 0)) for i in range(4) for j in range(4))<=1e-8

def empty(name,parent=None):
    ob=bpy.data.objects.new(name,None);bpy.context.scene.collection.objects.link(ob)
    if parent:ob.parent=parent
    ob.matrix_basis=Matrix.Identity(4)
    return ob

def assign(ob,group,finish,parents):
    ob.parent=parents[group];ob.matrix_basis=Matrix.Identity(4)
    ob['body_group']=group
    ob['runtime_mesh']=RUNTIME_NAMES[(group,'Steel' if finish=='Steel' else 'Paint')]
    return ob

def build_ribs(plate,rows,material,parent):
    verts=[];faces=[]
    for row in rows:
        cx,cz=row['centre'];a=-row['angle'];ca,sa=math.cos(a),math.sin(a);base=len(verts)
        profiles=((design.RIB_LENGTH,design.RIB_WIDTH,.002,design.DECK_Y-.00015),
                  (design.RIB_LENGTH,design.RIB_WIDTH,.002,design.DECK_Y+.0004),
                  (design.RIB_LENGTH-.003,design.RIB_WIDTH-.003,.0015,5.0))
        for length,width,chamfer,height in profiles:
            for x,y in design.ring(length,width,chamfer):
                verts.append((cx+x*ca-y*sa,-cz+x*sa+y*ca,height))
        faces.append(tuple(base+i for i in reversed(range(8))))
        for level in range(2):
            for i in range(8):
                j=(i+1)%8
                faces.append((base+level*8+i,base+level*8+j,base+(level+1)*8+j,base+(level+1)*8+i))
        faces.append(tuple(base+16+i for i in range(8)))
    me=bpy.data.meshes.new(plate+'_TreadHighMesh');me.from_pydata(verts,[],faces);me.update()
    ob=bpy.data.objects.new(plate+'_TreadHigh',me);bpy.context.scene.collection.objects.link(ob)
    ob.parent=parent;ob['high_source']=True;ob['not_runtime_geometry']=True
    ob['body_group']='PlatformAssembly';ob['source_plate']=plate;ob['rib_count']=len(rows)
    uv_source(ob,'Steel');me.materials.append(material)
    # All tread triangles use exactly the plate's top-plane source UV frame and phase.
    seed=int(hashlib.sha256(plate.encode()).hexdigest()[:8],16)
    metric=me.uv_layers['MetricUV']
    for loop in me.loops:
        p=gp(me.vertices[loop.vertex_index].co)
        metric.data[loop.index].uv=(p[0]/CONFIG['source_metric_repeat_m']+(seed%17)*.071,p[2]/CONFIG['source_metric_repeat_m']+(seed%11)*.083)
    return ob

def geometry_report():
    deps=bpy.context.evaluated_depsgraph_get();rows=[];digest=hashlib.sha256()
    points={g:[] for g in design.BOUNDS};mesh_counts={k:0 for k in RUNTIME_NAMES.values()}
    for ob in sorted((o for o in bpy.data.objects if o.type=='MESH' and (o.get('editable_piece') or o.get('high_source'))),key=lambda x:x.name):
        assert identity(ob),(ob.name,'nonidentity transform')
        group=ob['body_group'];assert ob.parent.name==group
        ev=ob.evaluated_get(deps);me=ev.to_mesh(preserve_all_data_layers=True,depsgraph=deps)
        try:
            me.calc_loop_triangles();coords=[gp(v.co) for v in me.vertices]
            assert coords and all(math.isfinite(c) for p in coords for c in p),ob.name
            lo=[min(p[i] for p in coords) for i in range(3)];hi=[max(p[i] for p in coords) for i in range(3)]
            guard=design.BOUNDS[group]
            max_outside=max([0.]+[guard[0][i]-lo[i] for i in range(3)]+[hi[i]-guard[1][i] for i in range(3)])
            assert max_outside<=TOLERANCE,(ob.name,lo,hi,max_outside)
            bm=bmesh.new();bm.from_mesh(me);nonmanifold=sum(not e.is_manifold for e in bm.edges)
            volume=bm.calc_volume(signed=True);bm.free()
            assert nonmanifold==0 and volume>0,(ob.name,nonmanifold,volume)
            assert set(UVS).issubset(me.uv_layers.keys()),ob.name
            uv_state={}
            for name in UVS:
                layer=me.uv_layers[name]
                assert all(math.isfinite(v) for q in layer.data for v in q.uv),(ob.name,name)
                h=hashlib.sha256()
                for q in layer.data:h.update(struct.pack('<2f',*q.uv))
                uv_state[name]=h.hexdigest()
            record={'name':ob.name,'body_group':group,'runtime_mesh':ob.get('runtime_mesh'),
                    'vertices':len(me.vertices),'triangles':len(me.loop_triangles),'bounds':[lo,hi],
                    'outside_original_Box_m':max_outside,'nonmanifold_edges':nonmanifold,'signed_volume_m3':volume,
                    'high_only':bool(ob.get('high_source')),'UV_sha256':uv_state,'rib_count':ob.get('rib_count',0)}
            h=hashlib.sha256()
            for v in me.vertices:h.update(struct.pack('<3f',*v.co))
            for t in me.loop_triangles:h.update(struct.pack('<4I',*t.vertices,t.material_index))
            for n in me.corner_normals:h.update(struct.pack('<3f',*n.vector))
            record['geometry_normals_sha256']=h.hexdigest()
            digest.update(json.dumps(record,sort_keys=True).encode());rows.append(record);points[group].extend(coords)
            if not record['high_only']:mesh_counts[record['runtime_mesh']]+=record['triangles']
        finally:ev.to_mesh_clear()
    group_bounds={}
    for group,coords in points.items():
        bounds=[[fn(p[i] for p in coords) for i in range(3)] for fn in (min,max)]
        assert max(abs(v-e) for row,exp in zip(bounds,design.BOUNDS[group]) for v,e in zip(row,exp))<=TOLERANCE,(group,bounds)
        group_bounds[group]=bounds
    for name in ('WestLandingPlatform','PlatformAssembly','LegAssembly'):assert identity(bpy.data.objects[name]),name
    assert sum(mesh_counts.values())<=20000,mesh_counts
    assert sum(row['rib_count'] for row in rows)==len(design.tread_layout())
    return {'geometry_sha256':digest.hexdigest(),'parts':rows,'editable_low_parts':sum(not r['high_only'] for r in rows),
            'low_triangles':sum(mesh_counts.values()),'runtime_mesh_triangles':mesh_counts,
            'high_only_triangles':sum(r['triangles'] for r in rows if r['high_only']),
            'actual_per_body_bounds':group_bounds,'per_body_test_not_union_AABB_only':True,
            'tolerance_m':TOLERANCE,'source_origin_world':design.ORIGIN,'identity_hierarchy':True,
            'collision_export':False,'high_only_tread_not_runtime_geometry':True}

def studio():
    s=bpy.context.scene;s.render.engine='CYCLES';s.cycles.device='CPU';s.cycles.samples=24;s.cycles.use_denoising=True
    s.render.threads_mode='FIXED';s.render.threads=2;s.render.resolution_x=1280;s.render.resolution_y=1000
    s.render.resolution_percentage=100;s.render.image_settings.file_format='PNG'
    s.view_settings.view_transform='AgX';s.view_settings.look='AgX - Medium High Contrast';s.view_settings.exposure=0
    w=bpy.data.worlds.new('NeutralStudio');w.use_nodes=True;w.node_tree.nodes['Background'].inputs[0].default_value=(.44,.47,.50,1)
    w.node_tree.nodes['Background'].inputs[1].default_value=.55;s.world=w
    groundmat=bpy.data.materials.new('ReviewGround_NotAsset');groundmat.diffuse_color=(.23,.24,.25,1)
    bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.012));o=bpy.context.object;o.name='ReviewGround_NOT_ASSET';o.data.materials.append(groundmat)
    for name,loc,energy,size in [('Key',(-5,-7,13),1800,8),('Fill',(8,-1,9),600,7)]:
        data=bpy.data.lights.new(name,'AREA');data.energy=energy;data.shape='DISK';data.size=size
        ob=bpy.data.objects.new(name,data);s.collection.objects.link(ob);ob.location=loc
        ob.rotation_euler=(Vector((0,0,2.7))-ob.location).to_track_quat('-Z','Y').to_euler()
    camera=bpy.data.objects.new('SourceReviewCamera',bpy.data.cameras.new('SourceReviewCamera'));s.collection.objects.link(camera)
    s.camera=camera;camera.data.type='ORTHO';camera.data.ortho_scale=11.5;camera.location=(11,-13,12)
    camera.rotation_euler=(Vector((0,0,3.6))-camera.location).to_track_quat('-Z','Y').to_euler()
    return {'camera_position_blender':list(camera.location),'target_blender':[0,0,3.6],'ortho_m':11.5,
            'resolution':[1280,1000],'samples':24,'CPU_threads':2,'exposure':0,'view':'AgX - Medium High Contrast',
            'scope':'Offline complete single-object source review; not actual MAIN/game validation'}

def main():
    began=time.monotonic();print(json.dumps({'stage':'source','pid':os.getpid(),'CPU_threads':2}),flush=True)
    path=HERE/'west_landing_platform_editable.blend'
    assert not path.exists(),'Preserve existing source: explicit new revision required'
    design.static_contract();bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.preferences.filepaths.save_version=0
    images,input_rows=load_inputs();mats=materials(images);root=empty('WestLandingPlatform')
    root['origin_world']=design.ORIGIN;parents={name:empty(name,root) for name in design.BOUNDS}
    boxes,bolts,plates=design.geometry_specs()
    for r in boxes:
        mat=mats['Steel' if r['finish']=='Steel' else 'Paint']
        assign(box(r['name'],r['min'],r['max'],mat,r['finish'],r['bevel']),r['body_group'],r['finish'],parents)
    for r in bolts:assign(bolt(r['name'],r['centre'],r['axis'],mats['Steel']),r['body_group'],'Steel',parents)
    ribs=design.tread_layout()
    for plate in plates:build_ribs(plate,[r for r in ribs if r['plate']==plate],mats['Steel'],parents['PlatformAssembly'])
    bpy.context.view_layer.update();camera=studio();before=image_audit()
    # Save inspectable geometry before any expensive evaluated-geometry assertions.
    save_relative(HERE/'source_diagnostic_checkpoint.blend')
    report=geometry_report();write('geometry_report.json',report)
    save_relative(path);source_hash=sha(path)
    bpy.ops.wm.open_mainfile(filepath=str(path));after=image_audit();reread=geometry_report()
    assert reread['geometry_sha256']==report['geometry_sha256'],'Reopened geometry/UV/normals changed'
    assert [(r['sha256'],r['size'],r['space']) for r in before]==[(r['sha256'],r['size'],r['space']) for r in after]
    report.update(reopened_images=after,source_inputs=input_rows,source_sha256=source_hash,camera=camera,
                  material_groups=2,source_reference=str(ROOT/'references/v3/production/west_landing_platform/west_landing_platform_reference_v1.png'),
                  reference_sha256=sha(ROOT/'references/v3/production/west_landing_platform/west_landing_platform_reference_v1.png'),
                  manufacturing_tread={'pitch_m':design.PITCH,'bar_size_m':[design.RIB_LENGTH,design.RIB_WIDTH],
                      'relief_m':design.RIB_HEIGHT,'low_deck_top_m':design.DECK_Y,'high_peak_m':5.,
                      'fine_scan_NormalGL_strength_once':CONFIG['Steel']['fine_normal_strength_once'],'no_procedural_duplicate_tread_bump':True},
                  responsibility='Original two Box collisions and dynamic bearing markings remain Root-owned. No new collision/rail/column/brace.',
                  status='SOURCE_VERIFIED_RENDER_PENDING')
    write('source_report.json',report)
    scene=bpy.context.scene;scene.render.filepath=str(HERE/'01-single-object.png');bpy.ops.render.render(write_still=True)
    assert sha(path)==source_hash
    report.update(status='SOURCE_PREVIEW_COMPLETE_PENDING_ART_REVIEW',pid=os.getpid(),seconds=time.monotonic()-began,
                  images=[{'path':scene.render.filepath,'sha256':sha(scene.render.filepath),'scope':camera['scope']}])
    write('source_report.json',report)
    print(json.dumps({'stage':'source_end','pid':os.getpid(),'seconds':report['seconds'],'low_parts':report['editable_low_parts'],
                      'low_triangles':report['low_triangles'],'high_only_triangles':report['high_only_triangles']}),flush=True)

if __name__=='__main__':
    try:main()
    except Exception:
        (HERE/'source_failure.txt').write_text(traceback.format_exc(),encoding='utf-8')
        raise
