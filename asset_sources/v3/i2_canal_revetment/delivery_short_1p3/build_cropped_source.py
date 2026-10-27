"""True 1.3m middle crop of frozen cleaned source, explicit source-UV caps."""
from pathlib import Path
import sys,os,time,collections
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parent))
from common import *
from mathutils.bvhtree import BVHTree

HALF=.65

def mix(a,b,t):
    return {'p':a['p'].lerp(b['p'],t),'n':(a['n']*(1-t)+b['n']*t).normalized(),
        'uv':{n:tuple(a['uv'][n][i]*(1-t)+b['uv'][n][i]*t for i in range(2)) for n in UVS},
        'attr':{n:a['attr'][n]*(1-t)+b['attr'][n]*t for n in ATTRS}}

def clip(poly,plane,keep_greater,source_points,cut_points,cut_audit):
    result=[]
    for a,b in zip(poly,poly[1:]+poly[:1]):
        da=(a['p'].x-plane)*(1 if keep_greater else -1);db=(b['p'].x-plane)*(1 if keep_greater else -1)
        ia=da>=0;ib=db>=0
        if ia:result.append(a)
        if ia!=ib:
            t=(plane-a['p'].x)/(b['p'].x-a['p'].x);v=mix(a,b,t);v['p'].x=plane
            support=tuple(sorted(set(a['support'])|set(b['support'])))
            assert len(support)==2,('cut must stay on original triangle edge',support)
            key=('cut',plane,*support)
            if key not in cut_points:
                first,last=[source_points[i] for i in support]
                exact_t=(plane-float(first.x))/(float(last.x)-float(first.x))
                point=Vector(tuple(float(first[i])+(float(last[i])-float(first[i]))*exact_t for i in range(3)))
                point.x=plane;cut_points[key]=point
            row=cut_audit.setdefault(key,{'edge':list(support),'plane':plane,'raw_round8_keys':set(),'max_raw_to_canonical_m':0.})
            row['raw_round8_keys'].add(tuple(round(float(q),8) for q in v['p']))
            row['max_raw_to_canonical_m']=max(row['max_raw_to_canonical_m'],(v['p']-cut_points[key]).length)
            v.update(p=cut_points[key].copy(),key=key,support=support);result.append(v)
    return result

def edges(faces):
    result=collections.defaultdict(list)
    for i,f in enumerate(faces):
        for a,b in zip(f['ids'],f['ids'][1:]+f['ids'][:1]):result[tuple(sorted((a,b)))].append((i,a,b))
    return result

def main():
    started=time.monotonic();assert sha(SOURCE)==SOURCE_SHA
    assert not (OUT/'prepared_clean_uv.blend').exists(),'preserve earlier short source'
    print(json.dumps({'stage':'short_crop_start','pid':os.getpid()}),flush=True)
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE));inputs=copy_inputs()
    source_parts=[o for o in bpy.data.objects if o.get('editable_piece')];assert len(source_parts)==8
    body=bpy.data.objects['ConcreteBody_4m_Closed'];assert not body.modifiers and body.matrix_world==Matrix.Identity(4)
    old=body.data;old.calc_loop_triangles();original_points=[v.co.copy() for v in old.vertices]
    old_bvh=BVHTree.FromPolygons(original_points,[tuple(t.vertices) for t in old.loop_triangles],all_triangles=True)
    vertices=[];lookup={};faces=[];maximum_same_point_join=0.;cut_points={};cut_audit={}
    def index(p,key):
        nonlocal maximum_same_point_join
        if key in lookup:
            maximum_same_point_join=max(maximum_same_point_join,(vertices[lookup[key]]-p).length)
            return lookup[key]
        lookup[key]=len(vertices);vertices.append(p.copy());return len(vertices)-1
    for number,tri in enumerate(old.loop_triangles):
        poly=[]
        for vi,li in zip(tri.vertices,tri.loops):
            poly.append({'p':old.vertices[vi].co.copy(),'n':old.corner_normals[li].vector.copy(),'key':('v',int(vi)),'support':(int(vi),),
                'uv':{n:tuple(old.uv_layers[n].data[li].uv) for n in UVS},
                'attr':{n:old.attributes[n].data[li].value for n in ATTRS}})
        poly=clip(clip(poly,-HALF,True,original_points,cut_points,cut_audit),HALF,False,original_points,cut_points,cut_audit)
        for j in range(1,len(poly)-1):
            corners=[poly[0],poly[j],poly[j+1]];ids=[index(v['p'],v['key']) for v in corners]
            if len(set(ids))<3:continue
            faces.append({'ids':ids,'corners':corners,'original_triangle':number,'material':old.polygons[tri.polygon_index].material_index,'cap':False})
    assert maximum_same_point_join<=1e-7
    audit_rows=[{**r,'raw_round8_keys':[list(k) for k in sorted(r['raw_round8_keys'])]} for r in cut_audit.values()]
    write_json(OUT/'cut_vertex_identity_report.json',{'method':'original vertex ID or (source edge IDs, plane); canonical float64 intersection rounded once to Blender float32',
        'actual_blender_old_round8_split_edges':sum(len(r['raw_round8_keys'])>1 for r in audit_rows),'edges':audit_rows})
    assert all(r['max_raw_to_canonical_m']<=1e-6 for r in audit_rows)
    e=edges(faces);open_edges=[o[0] for o in e.values() if len(o)==1]
    cap_reports=[]
    for side in [-1,1]:
        plane=side*HALF;directed=[]
        for _,a,b in open_edges:
            if abs(vertices[a].x-plane)<1e-6 and abs(vertices[b].x-plane)<1e-6:directed.append((b,a))
        assert directed,side
        follows={a:b for a,b in directed};assert len(follows)==len(directed)
        start=min(follows);loop=[start]
        while follows[loop[-1]]!=start:
            loop.append(follows[loop[-1]]);assert len(loop)<=len(directed)
        assert len(loop)==len(directed),'multiple cap rings unsupported'
        center=sum((vertices[i] for i in loop),Vector())/len(loop);center.x=plane;center_id=index(center,('cap_center',side))
        def cap_corner(p):
            x,y,z=gp(p);depth=-z;source_x=plane-side*depth
            return {'p':p.copy(),'n':Vector((side,0,0)),
                'uv':{'SurfaceMetric':(z,y),'FrontFaceUV':((source_x+2)/4,(y+2.8)/2.8)},
                'attr':{'SourceHeight':y,'SourceX':x,'WaterFacing':0.,'RepairUse':0.,'ExposedSurface':1.}}
        minimum_area=float('inf')
        for a,b in zip(loop,loop[1:]+loop[:1]):
            ids=[center_id,a,b];ps=[vertices[i] for i in ids]
            cross=(ps[1]-ps[0]).cross(ps[2]-ps[0]);assert cross.x*side>1e-12,'cap not star shaped or wrong winding'
            minimum_area=min(minimum_area,cross.length*.5)
            faces.append({'ids':ids,'corners':[cap_corner(p) for p in ps],'original_triangle':None,'material':0,'cap':True})
        cap_reports.append({'side':side,'plane_x':plane,'boundary_segments':len(loop),'triangles':len(loop),'minimum_area':minimum_area,
            'uv':'adjacent front 0.35m strip; original 4m horizontal density and 2.8m vertical density'})
    e=edges(faces);bad={str(k):v for k,v in e.items() if len(v)!=2 or v[0][1:]==v[1][1:]};assert not bad,bad
    mesh=bpy.data.meshes.new('Revetment1p3_TrueCroppedAndCapped');mesh.from_pydata(vertices,[],[f['ids'] for f in faces]);mesh.update()
    for mat in old.materials:mesh.materials.append(mat)
    for p,f in zip(mesh.polygons,faces):p.material_index=f['material'];p.use_smooth=True
    mesh.normals_split_custom_set([tuple(c['n']) for f in faces for c in f['corners']])
    for n in UVS:
        mesh.uv_layers.new(name=n)
        for p,f in zip(mesh.polygons,faces):
            for li,c in zip(p.loop_indices,f['corners']):mesh.uv_layers[n].data[li].uv=c['uv'][n]
    for n in ATTRS:
        mesh.attributes.new(name=n,type='FLOAT',domain='CORNER')
        for p,f in zip(mesh.polygons,faces):
            for li,c in zip(p.loop_indices,f['corners']):mesh.attributes[n].data[li].value=c['attr'][n]
    body.data=mesh;body.name='ConcreteBody_1p3_Closed'
    keep=[body]+[o for o in source_parts if o.name.startswith('Fixing_1_')]
    assert len(keep)==4
    for obj in source_parts:
        if obj not in keep:bpy.data.objects.remove(obj,do_unlink=True)
    new_bvh=BVHTree.FromPolygons(vertices,[f['ids'] for f in faces],all_triangles=True);rays=[]
    for x in [-.62,-.4,0,.3,.6]:
        for y in [-.05,-.8,-1.2,-2.,-2.7]:
            origin=Vector((x,-1,y));direction=Vector((0,1,0));a=old_bvh.ray_cast(origin,direction,2);b=new_bvh.ray_cast(origin,direction,2)
            assert a[0] is not None and b[0] is not None
            error=(a[0]-b[0]).length;assert error<=1e-6
            rays.append({'x':x,'y':y,'difference_m':error})
    volume=sum(vertices[f['ids'][0]].dot(vertices[f['ids'][1]].cross(vertices[f['ids'][2]]))/6 for f in faces);assert volume>0
    actual=[gp(v) for v in vertices];lo=[min(p[i] for p in actual) for i in range(3)];hi=[max(p[i] for p in actual) for i in range(3)]
    assert max(abs(a-b) for a,b in zip(lo+hi,[-.65,-2.8,-.35,.65,0,0]))<1e-6
    geometry={'input_sha256':SOURCE_SHA,'editable_objects':4,'body_triangles':len(faces),'caps':cap_reports,'closed':True,'signed_volume_m3':volume,
        'bounds':{'min':lo,'max':hi},'maximum_identical_clip_point_join_m':maximum_same_point_join,'rays':rays,
        'no_global_scale':True,'front_uv_horizontal_range':[.3375,.6625],'cap_texture_density':'0.35m adjacent front strip, no whole-image squeeze',
        'retained_objects':[o.name for o in keep],'source_triangle_mapping':[{'source':f['original_triangle'],'cap':f['cap']} for f in faces]}
    write_json(OUT/'crop_geometry_report.json',geometry)
    editable=OUT/'i2_canal_revetment_editable.blend';audit_images('short source before save');bpy.ops.wm.save_as_mainfile(filepath=str(editable),relative_remap=False)
    bpy.ops.wm.open_mainfile(filepath=str(editable));audit_images('reopened short source')
    parts=[o for o in bpy.data.objects if o.get('editable_piece')];assert len(parts)==4
    proxy,source_rows,materials=make_proxy(parts);uv=unique_uv(proxy)
    proxy.data.calc_loop_triangles();density=[]
    for tri in proxy.data.loop_triangles:
        if gp(tri.normal)[2]<.9 or tri.area<1e-7:continue
        a,b,c=[proxy.data.uv_layers['DeliveryBakeUV'].data[i].uv for i in tri.loops]
        area=abs((b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x))*.5
        density.append({'area_m2':tri.area,'pixels_per_m':math.sqrt(area*SIZE*SIZE/tri.area)})
    weighted=sum(r['area_m2']*r['pixels_per_m'] for r in density)/sum(r['area_m2'] for r in density)
    uv['actual_front_area_weighted_pixels_per_m']=weighted
    checkpoint=OUT/'prepared_clean_uv.blend';bpy.ops.wm.save_as_mainfile(filepath=str(checkpoint),relative_remap=False)
    report={'status':'CLEAN_UV_VERIFIED','source_sha256':SOURCE_SHA,'input_images':inputs,'source_parts':source_rows,'material_audit':materials,
        'uv':uv,'geometry':geometry,'triangles':sum(r['triangles'] for r in source_rows),'blend_sha256':sha(checkpoint),'seconds':time.monotonic()-started}
    write_json(OUT/'prepared_clean_uv_report.json',report);assert sha(SOURCE)==SOURCE_SHA
    print(json.dumps({'stage':'short_crop_exit','pid':os.getpid(),'triangles':report['triangles'],'seconds':time.monotonic()-started}),flush=True)

if __name__=='__main__':main()
