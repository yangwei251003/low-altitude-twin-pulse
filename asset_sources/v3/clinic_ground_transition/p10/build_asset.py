"""P10 source-only reconstruction. Run only in a granted serial CPU2 window."""
from pathlib import Path
import importlib.util,json,math,os,random,sys,time,hashlib
sys.dont_write_bytecode=True
import bpy,bmesh
from mathutils import Vector
from mathutils.geometry import delaunay_2d_cdt
from mathutils.bvhtree import BVHTree
OUT=Path(__file__).resolve().parent
def load(name,path):
    spec=importlib.util.spec_from_file_location(name,path);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
P=load('frozen_p9',OUT.parent/'p9/build_asset.py');H=P.H;S=P.S
T=load('p10_terrain',OUT/'terrain_design.py');M=load('p10_material',OUT/'scan_soil_material.py')
P.OUT=OUT;H.OUT=OUT;S.OUT=OUT;P.material_module=M
BASE_MESH=P.BASE_MESH
SOIL=None;SOIL_BVH=None
def write(name,value):(OUT/name).write_text(json.dumps(value,ensure_ascii=False,indent=2),encoding='utf-8')
def design(x,z):return T.field(x,z,H.front,H.outer)
def analytical_y(x,z):return design(x,z)['height']
def actual_y(x,z):
    hit,normal,index,distance=SOIL_BVH.ray_cast(Vector(H.bp(x,.25,z)),Vector((0,0,-1)),1)
    assert hit is not None,('No actual soil support',x,z)
    return hit.z
H.soil_y=analytical_y;S.soil_y=analytical_y;P.soil_y=analytical_y
def mesh(name,vs,fs,mat,group,kind):
    ob=BASE_MESH(name,vs,fs,mat,group,kind)
    if kind=='soil':
        M.ensure_scan_uv(ob);control=ob.data.color_attributes['SurfaceControl']
        for poly in ob.data.polygons:
            for li in poly.loop_indices:
                co=ob.data.vertices[ob.data.loops[li].vertex_index].co;x,y,z=H.gp(co);f=design(x,z)
                control.data[li].color=(f['wet'],f['silt'],f['deposit'],1) if poly.normal.z>.15 else (0,0,0,1)
    return ob
H.mesh=mesh;P.mesh=mesh

def build_soil(mat):
    """One closed height field. CDT preserves bed/bank guides in XZ."""
    global SOIL,SOIL_BVH
    points=[];lookup={};constraints=[]
    def inside(x,z):return -3+1e-6<x<3-1e-6 and H.front(x)+1e-5<z<H.outer(x)-1e-5
    def add(x,z):
        key=(round(x,7),round(z,7))
        if key not in lookup:lookup[key]=len(points);points.append((x,z))
        return lookup[key]
    outline=[(x,H.front(x)) for x in H.X]
    outline.extend((3,H.front(3)+(H.outer(3)-H.front(3))*i/12) for i in range(1,13))
    outline.extend((x,H.outer(x)) for x in reversed(H.X[:-1]))
    outline.extend((-3,H.front(-3)+(H.outer(-3)-H.front(-3))*i/12) for i in range(11,0,-1))
    ring=[add(x,z) for x,z in outline]
    constraints.extend(zip(ring,ring[1:]+ring[:1]))
    # Quieter flats are coarser; guide lines supply detail where it is needed.
    for i in range(1,24):
        x=-3+i*.25
        for j in range(1,8):add(x,H.front(x)+(H.outer(x)-H.front(x))*j/8)
    for ri,route in enumerate(T.ROUTES+T.BRANCHES):
        main=ri<3;index=ri if main else ri-3;steps=16 if main else 9
        guide=[[] for _ in range(9)]
        for j in range(steps+1):
            t=.025+.95*j/steps;center,normal=T.route_frame(route,t)
            h=T.halfwidth(index,t) if main else .055+.020*t
            offsets=[-3.1*h,-1.7*h,-1.25*h,-.40*h,0,.40*h,1.25*h,1.7*h,3.1*h]
            for k,d in enumerate(offsets):
                x,z=center[0]+normal[0]*d,center[1]+normal[1]*d
                guide[k].append(add(x,z) if inside(x,z) else None)
        for line in guide:
            for a,b in zip(line,line[1:]):
                if a is None or b is None or a==b:continue
                if all(inside(points[a][0]*(1-t)+points[b][0]*t,points[a][1]*(1-t)+points[b][1]*t) for t in (.25,.5,.75)):constraints.append((a,b))
    vectors=[Vector(p) for p in points]
    outv,oute,outf,origv,orige,origf=delaunay_2d_cdt(vectors,list(constraints),[ring],1,1e-8,True)
    assert all(len(f)==3 for f in outf),'CDT returned nontriangular interior'
    # Close the actual returned boundary, including valid CDT split points.
    counts={}
    for face in outf:
        for a,b in zip(face,face[1:]+face[:1]):key=tuple(sorted((a,b)));counts[key]=counts.get(key,0)+1
    boundary=[edge for edge,count in counts.items() if count==1];adj={}
    for a,b in boundary:adj.setdefault(a,[]).append(b);adj.setdefault(b,[]).append(a)
    assert all(len(n)==2 for n in adj.values()),'Invalid top boundary degree'
    loop=[min(adj)];previous=None
    while True:
        current=loop[-1];nxt=next(n for n in adj[current] if n!=previous)
        if nxt==loop[0]:break
        assert nxt not in loop,'Multiple or repeated soil boundary'
        loop.append(nxt);previous=current
    assert len(loop)==len(boundary),'More than one top boundary loop'
    vs=[H.bp(v.x,analytical_y(v.x,v.y),v.y) for v in outv];faces=[tuple(f) for f in outf]
    bottoms={i:len(vs)+k for k,i in enumerate(loop)}
    vs.extend((vs[i][0],vs[i][1],-.18) for i in loop)
    for a,b in zip(loop,loop[1:]+loop[:1]):faces.append((a,b,bottoms[b],bottoms[a]))
    faces.append(tuple(bottoms[i] for i in reversed(loop)))
    SOIL=mesh('CompactedSoil_ContinuousSupport',vs,faces,mat,H.GROUPS[1],'soil')
    SOIL.data.calc_loop_triangles();SOIL_BVH=BVHTree.FromPolygons([v.co for v in SOIL.data.vertices],[tuple(f.vertices) for f in SOIL.data.loop_triangles],all_triangles=True)
    S.soil_y=actual_y;P.soil_y=actual_y
    # Legacy report still has a parametric perimeter check. Keep it, and add
    # the actual saved boundary/area checks below; stones use the real BVH.
    def area2(a,b,c):return abs((b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0]))*.5
    top_area=sum(area2(outv[f[0]],outv[f[1]],outv[f[2]]) for f in outf)
    outline_area=abs(sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(outline,outline[1:]+outline[:1])))*.5
    outer_ids=[i for i in loop if abs(outv[i].x)>=2.999999 or abs(outv[i].y-H.outer(outv[i].x))<1e-6]
    seam_error=max(abs(vs[i][2]) for i in outer_ids)
    assert seam_error<1e-7 and abs(top_area-outline_area)<1e-5
    write('terrain_build.json',{'method':'One closed XZ height field with explicit constrained bed/bank guides, not the P7 rectangular low mesh.','input_points':len(points),'constraint_segments':len(constraints),'top_vertices':len(outv),'top_triangles':len(outf),'actual_boundary_vertices':len(loop),'actual_outer_Y0_max_error_m':seam_error,'top_projected_area_m2':top_area,'boundary_projected_area_m2':outline_area,'all_tris':len(SOIL.data.loop_triangles),'high_only_particles':0})
    sections=[]
    for ri,route in enumerate(T.ROUTES):
        for t in (.18,.38,.62,.82):
            center,normal=T.route_frame(route,t);h=T.halfwidth(ri,t)
            samples=[]
            for k in range(121):
                d=-.40+.80*k/120;x,z=center[0]+normal[0]*d,center[1]+normal[1]*d
                if H.front(x)+1e-5<z<H.outer(x)-1e-5:samples.append({'offset_m':d,'y_m':actual_y(x,z)})
            banks=[actual_y(center[0]+normal[0]*d,center[1]+normal[1]*d) for d in (-h*1.35,h*1.35)]
            bottom=actual_y(*center)
            sections.append({'route':ri,'fraction':t,'center_xz_m':center,'actual_center_y_m':bottom,'actual_banks_y_m':banks,'actual_relative_center_depth_m':sum(banks)*.5-bottom,'samples':samples})
    write('actual_channel_sections.json',{'method':'Rays against the actual constructed soil triangle BVH, not height-function samples. No Godot collision test.','sections':sections})

def build(mats):
    cliffs=[]
    for k,(a,b) in enumerate([(-3,-1.17),(-1.15,.83),(.85,3)]):
        xs=sorted(set([a,b]+[x for x in H.X if a<x<b]));cliffs.append(P.fracture_block('ConcreteResidual_%02d'%k,xs,mats['concrete']))
    for k,(a,b) in enumerate([(-1.17,-1.15),(.83,.85)]):
        end=min(H.front(a),H.front(b))-.002;H.grid_solid('RecessedCrossSeal_%02d'%k,[H.bp(a,-.012,.01),H.bp(b,-.012,.01),H.bp(a,-.012,end),H.bp(b,-.012,end)],2,2,mats['seal'],H.GROUPS[0],'seal')
    H.grid_solid('JoinSeal_10mm',[H.bp(-3,-.012,0),H.bp(3,-.012,0),H.bp(-3,-.012,.01),H.bp(3,-.012,.01)],2,2,mats['seal'],H.GROUPS[0],'seal')
    build_soil(mats['soil']);rng=random.Random(621731)
    bvhs=[]
    for ob in cliffs:
        ob.data.calc_loop_triangles();bvhs.append(BVHTree.FromPolygons([v.co for v in ob.data.vertices],[f.vertices for f in ob.data.loop_triangles],all_triangles=True))
    for i in range(40):
        center,spread=[(-2.32,.35),(-1.10,.35),(.42,.32),(1.73,.40)][i%4];x=center+rng.uniform(-spread,spread);dia=rng.uniform(.055,.115);height=rng.uniform(.040,.070);cy=rng.uniform(-.048,-.021)
        ray=Vector(H.bp(x,cy,H.front(x)+.3));hits=[b.ray_cast(ray,Vector((0,1,0)),.7) for b in bvhs];hits=[r for r in hits if r[0] is not None];assert hits
        hit=min(hits,key=lambda row:row[3])[0];z=-hit.y+rng.uniform(-.006,.004);vs,fs,_=P.stone_vertices(x,z,dia,height,rng,cy=cy)
        ob=mesh('FractureAggregate_%02d'%i,vs,fs,mats['stone%d'%(i%4)],H.GROUPS[1],'chip')
        embedded=sum(any(P.inside(b,p) for b in bvhs) for p in vs)
        exposed=sum(not any(P.inside(b,p) for b in bvhs) and p[2]>analytical_y(p[0],-p[1])+.003 for p in vs)
        P.EMBEDDED.append({'name':ob.name,'inside_vertices':embedded,'visible_exposed_vertices':exposed,'center_godot':[x,cy,z],'diameter':dia})
    # Unequal clusters follow landform purpose, not identical two-sided strings.
    rng=random.Random(102731)
    for i in range(88):
        route=rng.choices((0,1,2),weights=(.46,.37,.17))[0]
        for attempt in range(80):
            t=rng.uniform(.12,.84);center,normal=T.route_frame(T.ROUTES[route],t);h=T.halfwidth(route,t)
            sign=1 if route==0 or (route==1 and t<.64) else -1
            if rng.random()<.19:sign*=-1
            offset=sign*(h*1.5+rng.uniform(.015,.21));x=center[0]+normal[0]*offset;z=center[1]+normal[1]*offset
            if -2.80<x<2.80 and H.front(x)+.10<z<H.outer(x)-.16 and design(x,z)['silt']<.30:break
        else:raise RuntimeError('No valid purposeful bank placement')
        P.add_low_stone('SedimentBankStone_%03d'%i,x,z,rng.uniform(.065,.135),rng.uniform(.050,.085),rng,mats['stone%d'%(i%4)])
    for i in range(10):
        center,spread=[(-1.14,.34),(.58,.36),(1.78,.25)][i%3];x=center+rng.uniform(-spread,spread);z=H.front(x)+rng.uniform(.10,.27)
        P.add_low_stone('FallenConcreteFragment_%02d'%i,x,z,rng.uniform(.13,.23),rng.uniform(.080,.125),rng,mats['stone%d'%((i+1)%4)],sub=2)
    write('sediment_distribution.json',{'low_stones':P.STONE_ROWS,'fine_stones':[],'fine_triangles':0,'embedded':P.EMBEDDED,'method':'Unequal true low clusters seated on actual new terrain; two scans for finer substrate, no high-only gravel blanket.'})

def proxy_uv():
    proxy=H.proxy_and_uv();uv=proxy.data.uv_layers['BakeUV'];categories={'soil':[],'concrete':[],'stones':[],'other':[]}
    for face in proxy.data.polygons:
        name=proxy.data.materials[face.material_index].name
        category='stones' if 'stone' in name else ('soil' if 'P10_TwoScans' in name and face.normal.z>.15 else ('concrete' if 'concrete' in name.lower() and face.normal.z>.60 else 'other'))
        categories[category].append(face.index)
    def projected(indices,box):
        coords=[H.gp(proxy.data.vertices[proxy.data.loops[li].vertex_index].co) for pi in indices for li in proxy.data.polygons[pi].loop_indices]
        lo=[min(c[i] for c in coords) for i in (0,2)];hi=[max(c[i] for c in coords) for i in (0,2)]
        for pi in indices:
            for li in proxy.data.polygons[pi].loop_indices:
                c=H.gp(proxy.data.vertices[proxy.data.loops[li].vertex_index].co)
                uv.data[li].uv=(box[0]+(c[0]-lo[0])/(hi[0]-lo[0])*box[2],box[1]+(c[2]-lo[1])/(hi[1]-lo[1])*box[3])
    projected(categories['soil'],(.02,.02,.96,.40));projected(categories['concrete'],(.02,.45,.96,.16))
    for category,box in [('stones',(.02,.64,.96,.26)),('other',(.02,.93,.96,.05))]:
        bpy.context.tool_settings.mesh_select_mode=(False,False,True)
        selected=set(categories[category])
        for face in proxy.data.polygons:face.select=face.index in selected
        bpy.ops.object.mode_set(mode='EDIT');bpy.ops.uv.smart_project(angle_limit=math.radians(66),island_margin=.03);bpy.ops.object.mode_set(mode='OBJECT')
        uv=proxy.data.uv_layers['BakeUV']
        for pi in categories[category]:
            for li in proxy.data.polygons[pi].loop_indices:
                u,v=tuple(uv.data[li].uv);uv.data[li].uv=(box[0]+u*box[2],box[1]+v*box[3])
    write('uv_allocation.json',{'categories':{k:len(v) for k,v in categories.items()},'regions':{'soil':[.02,.02,.96,.40],'concrete':[.02,.45,.96,.16],'stones':[.02,.64,.96,.26],'other':[.02,.93,.96,.05]},'purpose':'Visible top density takes priority; hidden bottom and vertical residual surfaces receive a smaller region. Exact density is measured after save.'})
    assert 'SoilScanUV' in proxy.data.uv_layers and 'RockScanUV' in proxy.data.uv_layers
    errors=[];images=[]
    metric=proxy.data.uv_layers['MetricUV']
    for pi in categories['soil']:
        for li in proxy.data.polygons[pi].loop_indices:
            u,v=metric.data[li].uv
            for layer,scale,offset in [('SoilScanUV',2.5,(.13,.27)),('RockScanUV',2.0,(.31,.09))]:
                actual=proxy.data.uv_layers[layer].data[li].uv
                errors.extend((abs(actual[0]-(u*1.5/scale+offset[0])),abs(actual[1]-(v*1.5/scale+offset[1]))))
    assert errors and max(errors)<1e-6
    for mat in proxy.data.materials:
        if not mat.name.startswith('SOURCE_P10_TwoScans'):continue
        for node in mat.node_tree.nodes:
            if node.type=='TEX_IMAGE' and node.image:
                linked=node.inputs['Vector'].links[0].from_node
                assert linked.type=='UVMAP' and linked.uv_map in ('SoilScanUV','RockScanUV')
                images.append({'name':node.image.name,'colorspace':node.image.colorspace_settings.name,'size':list(node.image.size),'uv':linked.uv_map})
    assert len(images)==6
    write('soil_scan_binding.json',{'actual_max_uv_error':max(errors),'actual_source_images':images})
    return proxy

def main():
    start=time.time();assert not(OUT/'editable_source.blend').exists(),'Preserve any previous P10 attempt first'
    for sub in ('textures','evidence','source_inputs'):(OUT/sub).mkdir(exist_ok=True)
    frozen={str(path):H.sha(path) for path in (OUT.parent/'p9/manifest.json',OUT.parent/'p9/editable_source.blend',OUT.parent/'p9/baked_source.blend')}
    M.verify_inputs();bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    atlas=bpy.data.images.load(str(H.ATLAS));atlas.colorspace_settings.name='sRGB'
    mats={kind:P.author(kind,atlas) for kind in ('concrete','soil','seal','stone0','stone1','stone2','stone3')};build(mats)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'geometry_attempt.blend'),relative_remap=False)
    report=S.OLD_GEOMETRY();report['checks'].append({'name':'actual_fracture_aggregate_buried_and_exposed','pass':all(r['inside_vertices']>0 and r['visible_exposed_vertices']>0 for r in P.EMBEDDED),'failed':[r for r in P.EMBEDDED if not(r['inside_vertices']>0 and r['visible_exposed_vertices']>0)]})
    report.update(highpoly_bake_triangles=0,low_mesh_changed_purposefully=True,main_terrain_grid=None,terrain_method='Constrained XZ bed/bank height field',collision_status='No runtime collider delivered. Root must validate actual changed surface.',budget_goal=8000)
    write('geometry_report.json',report);assert all(c['pass'] for c in report['checks']),[c for c in report['checks'] if not c['pass']]
    H.studio();bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'editable_source.blend'),relative_remap=False);source_sha=H.sha(OUT/'editable_source.blend')
    proxy=proxy_uv();H.attribute_audit(proxy);bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'uv_checkpoint.blend'),relative_remap=False)
    maps=[]
    for role in ('BaseColor','ORM','Normal'):
        maps.append(P.bake(proxy,role));write('bake_report.json',{'status':'CHECKPOINT_'+role,'maps':maps})
    ao=P.contact_ao(proxy);write('contact_ao_report.json',ao);P.pack_orm(proxy,maps,ao)
    standard,preview=P.delivery_and_preview_materials(maps);standard.name='GroundTransition_GLTF_P10';preview.name='GroundTransition_PreviewContactAO_P10';preview['export_material']=standard.name
    proxy.data.materials.clear();proxy.data.materials.append(preview)
    for face in proxy.data.polygons:face.material_index=0
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'baked_source.blend'),relative_remap=False)
    for image in bpy.data.images:
        if image.source=='FILE' and image.filepath:image.filepath=bpy.path.relpath(bpy.path.abspath(image.filepath))
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'baked_source.blend'),relative_remap=False);bpy.ops.wm.open_mainfile(filepath=str(OUT/'baked_source.blend'))
    reopened=[]
    for image in bpy.data.images:
        if image.source=='FILE' and image.filepath:
            path=Path(bpy.path.abspath(image.filepath));assert path.exists();image.reload();assert image.has_data
            reopened.append({'path':str(path),'sha256':H.sha(path),'colorspace':image.colorspace_settings.name})
    scene=bpy.context.scene;scene.cycles.samples=24;full=OUT/'evidence/transition_source_p10.png';scene.render.filepath=str(full);bpy.ops.render.render(write_still=True)
    scene.camera.location+=Vector((-1.15,-.06,0));scene.camera.data.ortho_scale=2.5;close=OUT/'evidence/transition_contact_close_p10.png';scene.render.filepath=str(close);bpy.ops.render.render(write_still=True)
    assert all(H.sha(path)==digest for path,digest in frozen.items())
    M.verify_inputs()
    report.update(status='P10_SOURCE_RENDERED_PENDING_ART_REVIEW_NO_GLB',maps=maps,reopened_images=reopened,render_sha256=H.sha(full),close_render_sha256=H.sha(close),editable_sha256=source_sha,source_unchanged=H.sha(OUT/'editable_source.blend')==source_sha,frozen_inputs_unchanged=True,seconds=time.time()-start)
    write('production_report.json',report);print(json.dumps({'pid':os.getpid(),'stage':'end','seconds':time.time()-start,'triangles':report['triangles'],'render':str(full)}),flush=True)
if __name__=='__main__':main()
