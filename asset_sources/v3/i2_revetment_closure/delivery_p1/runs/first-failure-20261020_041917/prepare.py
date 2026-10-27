"""Preserve approved geometry; transfer the actual frozen 4m bake UV.
Only the two exposed southern caps get a new small native-bake atlas.
No texture baking, GLB export, or production installation in this stage.
"""
from pathlib import Path
import sys,json,math,os,time,collections,shutil,struct
sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];P1=HERE.parent/'p1'
sys.path.insert(0,str(HERE))
from transfer import *
import bpy
from mathutils import Matrix,Vector

SOURCE=P1/'output/i2_revetment_closure_editable.blend'
SOURCE_SHA='2b8be5939de4f3a98f87aa9e7b940fdb94a1d18c41ce673077c48e0fc991fcdd'
ORIGINAL=ROOT/'asset_sources/v3/i2_canal_revetment/delivery_p4'
REFERENCE=ORIGINAL/'prepared_clean_uv.blend'
REFERENCE_SHA='c21b0be7eec93ae06a7d8c71ccbf40d9151831b603537e249cf0429a4d872c71'
GLB_SHA='46dd85357ba8cdcee41fe3aeabfe77ca7cb3aa3f1842450ad8a393e27f7cb197'
PLAN_SHA='90246f5528d31d73633a4b22fc69ff0cd61330489ede112e33d908d8097fff7b'
UVS=['SurfaceMetric','FrontFaceUV'];ATTRS=['SourceHeight','SourceX','WaterFacing','RepairUse','ExposedSurface']
CAP_SIZE=(1024,256);CAP_DENSITY=320.;CAP_MARGIN=3;ISLAND_GAP=8;OUTER=4

def dump(path,value):Path(path).write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def gp(p):return [float(p[0]),float(p[2]),float(-p[1])]
def matrix(spec):
    x,z,o=spec['local_x'],spec['water'],spec['origin']
    return Matrix(((x[0],-z[0],0,o[0]),(-x[1],z[1],0,-o[2]),(0,0,1,o[1]),(0,0,0,1)))
def columns(values,size):return [values[i:i+size] for i in range(0,len(values),size)]
def triangle_data(mesh,tri,transform=Matrix.Identity(4)):
    return {'p':[tuple(transform@mesh.vertices[i].co) for i in tri.vertices],
        'material':mesh.materials[mesh.polygons[tri.polygon_index].material_index].name,
        'uv':{name:[tuple(mesh.uv_layers[name].data[i].uv) for i in tri.loops] for name in UVS},
        'attrs':{name:[float(mesh.attributes[name].data[i].value) if mesh.attributes.get(name) else 0. for i in tri.loops] for name in ATTRS}}

def read_reference():
    assert sha(REFERENCE)==REFERENCE_SHA and sha(ORIGINAL/'i2_canal_revetment_p4.glb')==GLB_SHA
    bpy.ops.wm.open_mainfile(filepath=str(REFERENCE))
    proxy=bpy.data.objects['DeliveryBakeProxy'];mesh=proxy.data;mesh.calc_loop_triangles();rows=[]
    raw,images=original_glb_triangles(ORIGINAL/'i2_canal_revetment_p4.glb')
    max_error=0.;densities=[]
    for tri in mesh.loop_triangles:
        row=triangle_data(mesh,tri);row['bake']=[tuple(mesh.uv_layers['DeliveryBakeUV'].data[i].uv) for i in tri.loops]
        key,order=canonical(row['p']);uv=row['bake'][order:]+row['bake'][:order]
        candidates=raw.get(key,[])
        errors=[max(abs(a-b) for x,y in zip(uv,other) for a,b in zip(x,y)) for other in candidates]
        assert errors and min(errors)<=2e-7,('prepared proxy differs from actual frozen GLB',tri.polygon_index,min(errors,default=None))
        index=errors.index(min(errors));candidates.pop(index);max_error=max(max_error,min(errors));rows.append(row)
        densities.append((area(row['p']),uv_area(row['bake'])*2048*2048))
    assert len(rows)==5152 and all(not remaining for remaining in raw.values())
    maps={channel:ORIGINAL/'textures'/('I2Revetment_'+channel+'.png') for channel in ['BaseColor','ORM','Normal']}
    assert {r['sha256'] for r in images}=={sha(p) for p in maps.values()}
    return rows,{'actual_glb_sha256':GLB_SHA,'prepared_sha256':REFERENCE_SHA,'actual_triangles':len(rows),
        'actual_glb_uv_max_error':max_error,'images':images,
        'all_surface_area_weighted_density_px_per_m':math.sqrt(sum(v[1] for v in densities)/sum(v[0] for v in densities))},maps

def cap_plane(target,spec):
    # Only original source-body faces are eligible. A coincident coordinate
    # alone is insufficient: its real face normal must be the new cut normal.
    normal=cross(sub(target['p'][1],target['p'][0]),sub(target['p'][2],target['p'][0]));length=norm(normal)
    assert length>0
    for index,(nx,nz,d) in enumerate(spec['clip_planes']):
        outward=(-nx,nz,0.);nlen=norm(outward)
        if dot(normal,outward)/(length*nlen)<.99999:continue
        if all(abs(nx*p[0]-nz*p[1]-d)<3e-6 for p in target['p']):return index
    return None

def create_mesh(name,rows,materials):
    mesh=bpy.data.meshes.new(name+'_Mesh');corners=[c for row in rows for c in row['corners']]
    mesh.from_pydata([c['p'] for c in corners],[],[(i,i+1,i+2) for i in range(0,len(corners),3)]);mesh.update()
    for material in materials:mesh.materials.append(material)
    for poly,row in zip(mesh.polygons,rows):poly.material_index=materials.index(row['material']);poly.use_smooth=True
    mesh.normals_split_custom_set([c['n'] for c in corners])
    for name_uv in UVS+['DeliveryBakeUV']:mesh.uv_layers.new(name=name_uv)
    for name_attr in ATTRS:mesh.attributes.new(name=name_attr,type='FLOAT',domain='CORNER')
    mesh.attributes.new(name='DeliveryMaterialSlot',type='INT',domain='FACE')
    for poly,row in zip(mesh.polygons,rows):mesh.attributes['DeliveryMaterialSlot'].data[poly.index].value=row['slot']
    for i,c in enumerate(corners):
        for name_uv in UVS:mesh.uv_layers[name_uv].data[i].uv=c['uv'][name_uv]
        mesh.uv_layers['DeliveryBakeUV'].data[i].uv=c['bake']
        for name_attr in ATTRS:mesh.attributes[name_attr].data[i].value=c['attrs'][name_attr]
    mesh.uv_layers.active_index=mesh.uv_layers.find('DeliveryBakeUV')
    for layer in mesh.uv_layers:layer.active_render=layer.name=='DeliveryBakeUV'
    angles=[];bad=[];uv_area_sum=0.
    for i,c in enumerate(corners):
        original=tuple(c['n']);actual=tuple(mesh.corner_normals[i].vector)
        angles.append(math.degrees(math.atan2(norm(cross(original,actual)),dot(original,actual))))
        assert tuple(mesh.vertices[i].co)==tuple(c['p'])
        for uv in UVS:assert tuple(mesh.uv_layers[uv].data[i].uv)==tuple(c['uv'][uv])
        for attr in ATTRS:assert mesh.attributes[attr].data[i].value==c['attrs'][attr]
    mesh.calc_loop_triangles()
    for tri in mesh.loop_triangles:
        uv=[tuple(mesh.uv_layers['DeliveryBakeUV'].data[i].uv) for i in tri.loops];value=uv_area(uv);uv_area_sum+=value
        if value<=0 or not all(math.isfinite(v) and -1e-6<=v<=1.000001 for point in uv for v in point):
            bad.append({'triangle':tri.index,'positions':[list(mesh.vertices[i].co) for i in tri.vertices],'area_3d_m2':tri.area,'uv':uv,'uv_area':value})
    if bad:dump(HERE/'uv_failure.json',{'object':name,'triangles':bad});raise AssertionError(('nonpositive or invalid actual float32 UV',name,len(bad)))
    assert max(angles,default=0)<=.01,('custom normal encoding angle',name,max(angles))
    obj=bpy.data.objects.new(name,mesh);bpy.context.scene.collection.objects.link(obj)
    return obj,{'triangles':len(mesh.loop_triangles),'minimum_uv_area':min(uv_area([tuple(mesh.uv_layers['DeliveryBakeUV'].data[i].uv) for i in t.loops]) for t in mesh.loop_triangles),
                'sum_uv_area':uv_area_sum,'normal_encoding_max_degrees':max(angles,default=0)}

def checkpoint_signature(names):
    result={}
    for name in names:
        obj=bpy.data.objects[name];mesh=obj.data;h=hashlib.sha256()
        assert obj.matrix_world==Matrix.Identity(4)
        for vertex in mesh.vertices:h.update(struct.pack('<3f',*vertex.co))
        for p in mesh.polygons:
            h.update(struct.pack('<2i',p.material_index,len(p.vertices)));h.update(struct.pack('<'+'i'*len(p.vertices),*p.vertices))
        for layer in mesh.uv_layers:
            h.update(layer.name.encode())
            for c in layer.data:h.update(struct.pack('<2f',*c.uv))
        for name_attr in ATTRS:
            for c in mesh.attributes[name_attr].data:h.update(struct.pack('<f',c.value))
        for c in mesh.attributes['DeliveryMaterialSlot'].data:h.update(struct.pack('<i',c.value))
        for c in mesh.corner_normals:h.update(struct.pack('<3f',*c.vector))
        h.update(json.dumps([m.name for m in mesh.materials]).encode());result[name]=h.hexdigest()
    return result

def main():
    started=time.monotonic();assert sha(SOURCE)==SOURCE_SHA and sha(P1/'layout_plan.json')==PLAN_SHA
    assert not (HERE/'prepared.blend').exists(),'preserve existing delivery checkpoint'
    print(json.dumps({'stage':'prepare_start','pid':os.getpid()}),flush=True)
    reference,reference_report,maps=read_reference();transfer=SourceTransfer(reference)
    original_report=json.loads((ORIGINAL/'prepared_clean_uv_report.json').read_text(encoding='utf-8'))
    original_matrices={r['name']:Matrix(columns(r['source_matrix'],4)) for r in original_report['source_parts']}
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE));bpy.context.view_layer.update()
    plan=json.loads((P1/'layout_plan.json').read_text(encoding='utf-8'));specs={p['id']:p for p in plan['pieces']}
    pieces={key:[] for key in specs};caps=collections.defaultdict(list);omitted=[];source_count=0;reference_area=0.;reference_pixels=0.
    source_objects=[o for o in bpy.data.objects if o.get('closure_export_surface')];source_materials=[]
    for obj in sorted(source_objects,key=lambda o:o.name):
        key=obj['closure_piece'];spec=specs[key];piece_matrix=matrix(spec)
        body=obj.name==key+'_Surface';old_name='ConcreteBody_4m_Closed' if body else obj.name[len(key)+1:]
        transform=original_matrices[old_name]
        measured=piece_matrix.inverted()@obj.matrix_world
        assert max(abs(a-b) for ar,br in zip(transform,measured) for a,b in zip(ar,br))<3e-6,(obj.name,'original authored matrix')
        dg=bpy.context.evaluated_depsgraph_get();mesh=bpy.data.meshes.new_from_object(obj.evaluated_get(dg),preserve_all_data_layers=True,depsgraph=dg);mesh.calc_loop_triangles()
        normals=obj.matrix_world.to_3x3().inverted().transposed()
        for tri in mesh.loop_triangles:
            source_count+=1;target=triangle_data(mesh,tri,transform);plane=cap_plane(target,spec) if body else None
            if plane==2 and spec['segment']=='NorthHead':
                omitted.append({'object':obj.name,'triangle':tri.index,'area_m2':area(target['p']),'reason':'new north rear cap at Z2 buried against north ground; editable cap retained'})
                continue
            is_cap=plane is not None
            if is_cap:assert key in ('WestMouth_03','EastMouth_03') and plane==1,(obj.name,tri.index,'unexpected exposed cut plane',plane)
            bake=None if is_cap else transfer.map_triangle(target,(obj.name,tri.index))
            material=mesh.materials[mesh.polygons[tri.polygon_index].material_index]
            if material not in source_materials:source_materials.append(material)
            row={'material':material,'slot':int(is_cap),'corners':[],'source_triangle':tri.index,'source_object':obj.name,'local_points':target['p']}
            for j,(vi,li) in enumerate(zip(tri.vertices,tri.loops)):
                row['corners'].append({'p':tuple(obj.matrix_world@mesh.vertices[vi].co),'n':tuple((normals@mesh.corner_normals[li].vector).normalized()),
                    'uv':{name:target['uv'][name][j] for name in UVS},'attrs':{name:target['attrs'][name][j] for name in ATTRS},'bake':None if is_cap else bake[j]})
            pieces[key].append(row)
            if is_cap:caps[key].append(row)
            else:reference_area+=area(target['p']);reference_pixels+=uv_area(bake)*2048*2048
        bpy.data.meshes.remove(mesh)
    assert source_count==24520 and set(caps)=={'WestMouth_03','EastMouth_03'}
    atlas=[];row_start=OUTER
    for key in sorted(caps):
        nx,nz,_=specs[key]['clip_planes'][1];horizontal=Vector((nz,nx,0)).normalized()
        all_points=[p for row in caps[key] for p in row['local_points']];lo=min(dot(p,horizontal) for p in all_points);hi=max(dot(p,horizontal) for p in all_points)
        height=(hi-lo)*CAP_DENSITY
        assert 2.8*CAP_DENSITY+2*OUTER<=CAP_SIZE[0] and row_start+height+OUTER<=CAP_SIZE[1],('cap atlas does not fit fixed resolution/density',key,height,row_start)
        for row in caps[key]:
            for c,p in zip(row['corners'],row['local_points']):c['bake']=((OUTER+(p[2]+2.8)*CAP_DENSITY)/CAP_SIZE[0],(row_start+(dot(p,horizontal)-lo)*CAP_DENSITY)/CAP_SIZE[1])
        atlas.append({'piece':key,'pixel_bounds':[OUTER,row_start,OUTER+2.8*CAP_DENSITY,row_start+height],'area_m2':sum(area(r['local_points']) for r in caps[key]),'triangles':len(caps[key])})
        row_start+=height+ISLAND_GAP
    for obj in source_objects:obj.hide_render=True;obj.hide_set(True)
    root=bpy.data.objects.new('I2RevetmentClosureDelivery',None);bpy.context.scene.collection.objects.link(root)
    records={};normal_max=0.;caps_all=[]
    for key,rows in pieces.items():
        obj,record=create_mesh(key,rows,source_materials);obj.parent=root;obj['closure_delivery']=True
        ps=[gp(v.co) for v in obj.data.vertices];record['bounds']={'min':[min(p[j] for p in ps) for j in range(3)],'max':[max(p[j] for p in ps) for j in range(3)]}
        record['reused_triangles']=sum(r['slot']==0 for r in rows);record['cap_triangles']=sum(r['slot']==1 for r in rows);records[key]=record
        normal_max=max(normal_max,record['normal_encoding_max_degrees']);caps_all.extend(r for r in rows if r['slot']==1)
    cap_proxy,cap_record=create_mesh('ClosureCapBakeProxy',caps_all,source_materials);cap_proxy.hide_render=True;cap_proxy.hide_set(True)
    target=HERE/'reused_textures';target.mkdir(exist_ok=True)
    copied={}
    for channel,path in maps.items():
        dst=target/path.name
        if not dst.exists():shutil.copyfile(path,dst)
        assert sha(dst)==sha(path);copied[channel]={'path':str(dst),'sha256':sha(dst),'size':[2048,2048]}
    gap=atlas[1]['pixel_bounds'][1]-atlas[0]['pixel_bounds'][3]
    assert gap>=ISLAND_GAP and gap>2*CAP_MARGIN
    report={'status':'PREPARED_PENDING_CAP_BAKE','pid':os.getpid(),'source_sha256':SOURCE_SHA,'plan_sha256':PLAN_SHA,'reference':reference_report,
        'scope':'offline source-correspondence; no Godot/physics/image approval','pieces':records,'meshes':12,'expected_materials':2,
        'triangles':sum(r['triangles'] for r in records.values()),'source_surface_triangles':source_count,'omitted_buried_triangles':omitted,
        'omitted_buried_area_m2':sum(r['area_m2'] for r in omitted),'transfer':{'mapped_triangles':transfer.mapped,'equivalent_boundary_candidates':transfer.multiple_equivalent,'max_errors':transfer.maximum,
            'retained_area_weighted_density_px_per_m':math.sqrt(reference_pixels/reference_area),'resampling':False},
        'reused_textures':copied,'cap_atlas':{'size':CAP_SIZE,'density_px_per_m':CAP_DENSITY,'margin_px':CAP_MARGIN,'actual_min_island_gap_px':gap,'islands':atlas,
            'coverage':sum(r['area_m2'] for r in atlas)*CAP_DENSITY**2/(CAP_SIZE[0]*CAP_SIZE[1]),'mesh':cap_record},'normal_encoding_max_degrees':normal_max}
    names=list(records)+['ClosureCapBakeProxy'];saved_signature=checkpoint_signature(names)
    path=HERE/'prepared.blend';bpy.ops.wm.save_as_mainfile(filepath=str(path),relative_remap=False)
    bpy.ops.wm.open_mainfile(filepath=str(path));bpy.context.view_layer.update()
    assert checkpoint_signature(names)==saved_signature,'actual saved geometry/UV/attributes/material/normals differ'
    report['saved_reopened_signatures']=saved_signature
    report['blend_sha256']=sha(path);report['seconds']=time.monotonic()-started
    assert sha(SOURCE)==SOURCE_SHA and sha(REFERENCE)==REFERENCE_SHA
    dump(HERE/'prepared_report.json',report)
    print(json.dumps({'stage':'prepare_exit','pid':os.getpid(),'triangles':report['triangles'],'seconds':report['seconds']}),flush=True)

if __name__=='__main__':
    try:main()
    except Exception as error:
        dump(HERE/'last_prepare_failure.json',{'pid':os.getpid(),'error':repr(error),'source_unchanged':sha(SOURCE)==SOURCE_SHA})
        raise
