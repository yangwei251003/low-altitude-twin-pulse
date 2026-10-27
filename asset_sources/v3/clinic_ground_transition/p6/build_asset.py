"""P6: actual fracture strata / two-dimensional sediment banks / high-to-low bake.
Source-only, CPU2, one fixed camera. P3/P5 are read-only libraries, never rewritten.
"""
from pathlib import Path
import sys, importlib.util, math, random, json, time, os, shutil
sys.dont_write_bytecode=True
import bpy,bmesh
from mathutils import Vector
from mathutils.bvhtree import BVHTree
OUT=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('frozen_p5',OUT.parent/'p5/build_asset.py')
S=importlib.util.module_from_spec(spec);spec.loader.exec_module(S)
H=S.H;H.OUT=OUT;S.OUT=OUT
ROOT=H.ROOT
FINE=None;EMBEDDED=[];STONE_ROWS=[];BAKE_RECORD=[];SOIL=None
CHANNEL=S.channel_data

def write(name,value):
    (OUT/name).write_text(json.dumps(value,ensure_ascii=False,indent=2),encoding='utf-8')

def soil_y(x,z):
    s=H.clamp((z-H.front(x))/(H.outer(x)-H.front(x)))
    side=math.sin(math.pi*H.clamp((x+3)/6))**.45
    _,_,groove,bank=CHANNEL(x,z)
    # Real broad bed: dark fracture is exposed above it, rills are 1–2cm lower.
    return (-.066*(1-s)-.015*groove+.006*bank+.0025*math.sin(x*2.3+s*5)*math.sin(math.pi*s))*side*min(1,(1-s)*10)
H.soil_y=soil_y;S.soil_y=soil_y
mesh=S.mesh

def author(kind,atlas):
    if kind=='seal':return S.OLD_AUTHOR(kind,atlas)
    if kind=='concrete':
        m=S.OLD_AUTHOR(kind,atlas)
        for n in m.node_tree.nodes:
            if n.type=='MIX_RGB' and tuple(round(c,3) for c in n.inputs[1].default_value[:3])==(.23,.235,.22):
                n.inputs[1].default_value=(.105,.11,.10,1);n.inputs[0].default_value=.48
        return m
    g=H.Graph('SOURCE_P6_'+kind);n,l=g.n,g.l
    uv=n.new('ShaderNodeUVMap');uv.uv_map='MetricUV'
    attr=n.new('ShaderNodeVertexColor');attr.layer_name='SurfaceControl'
    sep=n.new('ShaderNodeSeparateColor');l.new(attr.outputs[0],sep.inputs[0])
    if kind=='soil':
        atlas2=bpy.data.images.load(str(OUT/'source_inputs/surface_atlas_v2_UNEDITED.png'),check_existing=True)
        atlas2.colorspace_settings.name='sRGB'
        # Keep continuous fine silt as background. Mid-sized gravel is geometry,
        # not a 0.5m repeating gravel picture masquerading as medium stones.
        split=n.new('ShaderNodeSeparateXYZ');l.new(uv.outputs[0],split.inputs[0])
        coord=n.new('ShaderNodeCombineXYZ')
        for axis in ['X','Y']:
            q=g.op('PINGPONG',split.outputs[axis],1)
            q=g.op('ADD',.012,g.op('MULTIPLY',q,.476 if axis=='X' else .976))
            l.new(q,coord.inputs[axis])
        tex=n.new('ShaderNodeTexImage');tex.image=atlas2;tex.extension='EXTEND';l.new(coord.outputs[0],tex.inputs[0])
        base=g.mix((.125,.107,.083,1),tex.outputs[0],.40)
        damp=g.op('SUBTRACT',1,g.op('MULTIPLY',sep.outputs['Red'],.20))
        mult=n.new('ShaderNodeMixRGB');mult.blend_type='MULTIPLY';mult.inputs[0].default_value=1
        l.new(base,mult.inputs[1]);l.new(damp,mult.inputs[2]);base=mult.outputs[0]
        rough=g.op('SUBTRACT',.88,g.op('ADD',g.op('MULTIPLY',sep.outputs['Green'],.12),g.op('MULTIPLY',sep.outputs['Red'],.16)))
        micro=.00035
    else:
        shade=int(kind[-1]);colors=[(.17,.158,.134,1),(.225,.215,.189,1),(.265,.254,.226,1),(.13,.135,.123,1)]
        base=colors[shade];rough=.81+shade*.025;micro=.00025
    bs=n.new('ShaderNodeBsdfPrincipled');g.put(base,bs.inputs['Base Color']);g.put(rough,bs.inputs['Roughness']);bs.inputs['Metallic'].default_value=0;bs.inputs['Emission Strength'].default_value=0
    noise=n.new('ShaderNodeTexNoise');l.new(uv.outputs[0],noise.inputs['Vector']);noise.inputs['Scale'].default_value=25;noise.inputs['Detail'].default_value=1
    bump=n.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.12;bump.inputs['Distance'].default_value=micro;l.new(noise.outputs['Fac'],bump.inputs['Height']);l.new(bump.outputs[0],bs.inputs['Normal'])
    out=n.new('ShaderNodeOutputMaterial');l.new(bs.outputs[0],out.inputs[0]);return g.m

def fracture_block(name,xs,mat):
    cols=len(xs);rows=4;vs=[]
    for r in range(rows):
        for x in xs:
            vs.append(H.bp(x,[0,0,0,H.edge_y(x)][r],[.01,.18,H.front(x)-.025,H.front(x)][r]))
    ring=list(range(cols))+[j*cols+cols-1 for j in range(1,rows)]+list(range((rows-1)*cols+cols-2,(rows-1)*cols-1,-1))+[j*cols for j in range(rows-2,0,-1)]
    bottom={i:len(vs)+k for k,i in enumerate(ring)}
    vs.extend([(vs[i][0],vs[i][1],-.18) for i in ring]);mid1={};mid2={}
    for i,x in enumerate(xs):
        envelope=math.sin(math.pi*(x-xs[0])/(xs[-1]-xs[0]))
        mid1[i]=len(vs);vs.append(H.bp(x,-.037-.009*math.sin(x*5.1+.6),H.front(x)+envelope*(.012+.010*math.sin(x*9))))
        mid2[i]=len(vs);vs.append(H.bp(x,-.092-.014*math.sin(x*3.7),H.front(x)-envelope*(.006+.010*math.sin(x*6+.5))))
    fs=[]
    for r in range(rows-1):
        for i in range(cols-1):
            a=r*cols+i;b=a+1;c=a+cols+1;d=a+cols;fs.extend([(a,d,c),(a,c,b)])
    front0=(rows-1)*cols
    for a,b in zip(ring,ring[1:]+ring[:1]):
        if a>=front0 and b>=front0:
            ia,ib=a-front0,b-front0
            fs.extend([(a,b,mid1[ib],mid1[ia]),(mid1[ia],mid1[ib],mid2[ib],mid2[ia]),(mid2[ia],mid2[ib],bottom[b],bottom[a])])
        elif b>=front0:
            i=b-front0;fs.append((a,b,mid1[i],mid2[i],bottom[b],bottom[a]))
        elif a>=front0:
            i=a-front0;fs.append((a,b,bottom[b],bottom[a],mid2[i],mid1[i]))
        else:fs.append((a,b,bottom[b],bottom[a]))
    fs.append(tuple(bottom[i] for i in ring))
    return mesh(name,vs,fs,mat,H.GROUPS[0],'concrete')

def inside(bvh,p):
    origin=Vector(p);direction=Vector((.837,.391,.383)).normalized();hits=[]
    for _ in range(32):
        hit,n,idx,d=bvh.ray_cast(origin,direction,20)
        if hit is None:break
        hits.append(hit);origin=hit+direction*.000001
    return len(hits)%2==1

ICOS={}
def ico(sub):
    if sub not in ICOS:
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=sub,radius=1)
        ob=bpy.context.object;ICOS[sub]=([tuple(v.co) for v in ob.data.vertices],[tuple(p.vertices) for p in ob.data.polygons]);bpy.data.objects.remove(ob,do_unlink=True)
    return ICOS[sub]

def stone_vertices(cx,cz,dia,height,rng,cy=None,sub=1):
    raw,faces=ico(sub);angle=rng.random()*math.tau
    cy=soil_y(cx,cz)-height*.10 if cy is None else cy
    aspect=rng.uniform(.65,.90);vs=[]
    for a,b,c in raw:
        factor=rng.uniform(.88,1.12);xx=(a*math.cos(angle)-b*math.sin(angle))*dia*.5*factor;zz=(a*math.sin(angle)+b*math.cos(angle))*dia*.5*aspect*factor
        vs.append(H.bp(cx+xx,cy+c*height*.5*rng.uniform(.9,1.1),cz+zz))
    if max(p[2] for p in vs)>.027:
        dy=max(p[2] for p in vs)-.027;vs=[(x,y,z-dy) for x,y,z in vs]
    return vs,faces,aspect

def point_on_route(ri,t):
    pts=H.ROUTES[ri][0];lengths=[math.dist(a,b) for a,b in zip(pts,pts[1:])];wanted=t*sum(lengths)
    for (a,b),length in zip(zip(pts,pts[1:]),lengths):
        if wanted<=length:
            q=wanted/length;dx=(b[0]-a[0])/length;dz=(b[1]-a[1])/length
            return a[0]+q*(b[0]-a[0]),a[1]+q*(b[1]-a[1]),(-dz,dx)
        wanted-=length
    return pts[-1][0],pts[-1][1],(0,1)

def bank_position(rng):
    # Unequal occupied lengths, with two-dimensional cross-bank scatter.
    intervals=[(.06,.28),(.36,.68),(.77,.94)]
    for _ in range(80):
        ri=rng.choices(range(6),weights=[3,1,3,1,3,1])[0];lo,hi=rng.choice(intervals);t=rng.uniform(lo,hi)
        x,z,normal=point_on_route(ri,t);main=ri in(0,2,4)
        bed=(.105+.085*t) if main else (.065+.035*t)
        if ri==2:bed*=.86
        width=.20 if main else .115
        offset=(bed+rng.uniform(.015,width))*(1 if rng.random()>.5 else -1)
        x+=normal[0]*offset;z+=normal[1]*offset
        if -2.85<x<2.85 and H.front(x)+.09<z<H.outer(x)-.09 and CHANNEL(x,z)[0]<.65:return x,z,ri,t
    raise RuntimeError('No valid sediment bank position')

def add_low_stone(name,x,z,dia,height,rng,material,sub=1):
    vs,fs,aspect=stone_vertices(x,z,dia,height,rng,sub=sub)
    ob=mesh(name,vs,fs,material,H.GROUPS[1],'chip');ground=soil_y(x,z)
    row={'name':name,'ground_center':[x,ground,z],'min_y':min(v[2] for v in vs),'max_y':max(v[2] for v in vs),'protrusion_m':max(v[2] for v in vs)-ground,'diameter_m':dia,'embedded_below_ground_m':ground-min(v[2] for v in vs),'projected_ellipse_m2':math.pi*dia*dia*aspect/4}
    H.CHIPS.append(row);STONE_ROWS.append(row);return ob

def build(mats):
    global SOIL,FINE
    cliffs=[]
    for k,(a,b) in enumerate([(-3,-1.17),(-1.15,.83),(.85,3)]):
        xs=sorted(set([a,b]+[x for x in H.X if a<x<b]));cliffs.append(fracture_block('ConcreteResidual_%02d'%k,xs,mats['concrete']))
    for k,(a,b) in enumerate([(-1.17,-1.15),(.83,.85)]):
        end=min(H.front(a),H.front(b))-.002;H.grid_solid('RecessedCrossSeal_%02d'%k,[H.bp(a,-.012,.01),H.bp(b,-.012,.01),H.bp(a,-.012,end),H.bp(b,-.012,end)],2,2,mats['seal'],H.GROUPS[0],'seal')
    H.grid_solid('JoinSeal_10mm',[H.bp(-3,-.012,0),H.bp(3,-.012,0),H.bp(-3,-.012,.01),H.bp(3,-.012,.01)],2,2,mats['seal'],H.GROUPS[0],'seal')
    top=[]
    for row in range(13):
        for x in H.X:
            z=H.front(x)+(H.outer(x)-H.front(x))*row/12;top.append(H.bp(x,soil_y(x,z),z))
    SOIL=H.grid_solid('CompactedSoil_ContinuousSupport',top,13,len(H.X),mats['soil'],H.GROUPS[1],'soil')
    bvhs=[]
    for o in cliffs:
        o.data.calc_loop_triangles();bvhs.append(BVHTree.FromPolygons([v.co for v in o.data.vertices],[p.vertices for p in o.data.loop_triangles],all_triangles=True))
    rng=random.Random(621731)
    for i in range(40):
        centers=[(-2.32,.35),(-1.10,.35),(.42,.32),(1.73,.40)];center,spread=centers[i%4]
        x=center+rng.uniform(-spread,spread);dia=rng.uniform(.055,.115);height=rng.uniform(.040,.070)
        cy=rng.uniform(-.048,-.021);ray=Vector(H.bp(x,cy,H.front(x)+.3));hitoptions=[b.ray_cast(ray,Vector((0,1,0)),.7) for b in bvhs];hits=[(r[0],r[3]) for r in hitoptions if r[0] is not None]
        assert hits,'No real fracture face for embedded aggregate';hit=min(hits,key=lambda h:h[1])[0]
        # Half crosses the actual surface; each fragment has its own vertical depth.
        z=-hit.y+rng.uniform(-.006,.004);vs,fs,_=stone_vertices(x,z,dia,height,rng,cy=cy)
        ob=mesh('FractureAggregate_%02d'%i,vs,fs,mats['stone%d'%(i%4)],H.GROUPS[1],'chip')
        ninside=sum(any(inside(b,p) for b in bvhs) for p in vs)
        exposed=sum(not any(inside(b,p) for b in bvhs) and p[2]>soil_y(p[0],-p[1])+.003 for p in vs)
        EMBEDDED.append({'name':ob.name,'inside_vertices':ninside,'visible_exposed_vertices':exposed,'center_godot':[x,cy,z],'diameter':dia})
    low_positions=[]
    for i in range(100):
        x,z,ri,t=bank_position(rng);dia=rng.uniform(.065,.135)
        add_low_stone('SedimentBankStone_%03d'%i,x,z,dia,rng.uniform(.027,.052),rng,mats['stone%d'%(i%4)])
        low_positions.append((x,z,dia*.38))
    for i in range(12):
        center,spread=[(-2.32,.30),(-1.10,.26),(.42,.32),(1.73,.35)][i%4]
        x=center+rng.uniform(-spread,spread);z=H.front(x)+rng.uniform(.10,.31)
        add_low_stone('FallenConcreteFragment_%02d'%i,x,z,rng.uniform(.13,.23),rng.uniform(.045,.075),rng,mats['stone%d'%((i+1)%4)],sub=2)
        low_positions.append((x,z,.09))
    highvs=[];highfs=[];highmi=[];finerows=[]
    for i in range(760):
        for attempt in range(60):
            x,z,ri,t=bank_position(rng);dia=rng.uniform(.024,.052)
            if not any(math.hypot(x-a,z-b)<r for a,b,r in low_positions):break
        else:continue
        vs,fs,aspect=stone_vertices(x,z,dia,rng.uniform(.012,.022),rng)
        start=len(highvs);highvs.extend(vs);highfs.extend([tuple(start+v for v in f) for f in fs]);highmi.extend([i%4]*len(fs));finerows.append({'x':x,'z':z,'diameter':dia,'area':math.pi*dia*dia*aspect/4})
    FINE=mesh('HIGH_ONLY_2_to_5cm_SedimentClusters',highvs,highfs,mats['stone0'],H.GROUPS[1],'chip');H.PARTS.remove(FINE)
    FINE['editable_piece']=False;FINE['high_poly_bake_only']=True
    for i in range(1,4):FINE.data.materials.append(mats['stone%d'%i])
    for p,mi in zip(FINE.data.polygons,highmi):p.material_index=mi
    FINE.hide_render=True;FINE.hide_set(True)
    write('sediment_distribution.json',{'low_stones':STONE_ROWS,'fine_stones':finerows,'raw_projected_area_sum_m2':sum(r['projected_ellipse_m2'] for r in STONE_ROWS)+sum(r['area'] for r in finerows),'area_note':'Ellipse sum is an upper bound before overlap/burial, not measured visible union. Bank locations follow the true six routes; clear silt beds are excluded.','small_stones_bake_only':True,'fine_triangles':len(highfs),'embedded':EMBEDDED})

def subset(proxy,group,name):
    ob=proxy.copy();ob.data=proxy.data.copy();bpy.context.scene.collection.objects.link(ob);ob.name=name;ob.hide_render=False;ob.hide_set(False)
    bm=bmesh.new();bm.from_mesh(ob.data);layer=bm.faces.layers.int['RuntimeGroup'];bmesh.ops.delete(bm,geom=[f for f in bm.faces if f[layer]!=group],context='FACES');bmesh.ops.delete(bm,geom=[v for v in bm.verts if not v.link_faces],context='VERTS');bm.to_mesh(ob.data);bm.free();ob.data.update();return ob

def bake(proxy,role):
    # First self-bake the real low concrete and silhouette stones. Then replace
    # only the soil ground UVs by a genuine selected-to-active high-detail pass.
    row=H.bake(proxy,role);im=next(im for im in bpy.data.images if im.name=='Transition_'+role)
    low=subset(proxy,1,'TEMP_P6_BakeTarget_Soil');high=low.copy();high.data=low.data.copy();bpy.context.scene.collection.objects.link(high);high.name='TEMP_P6_HighSource';high.hide_render=False;high.hide_set(False)
    fine=FINE.copy();fine.data=FINE.data.copy();bpy.context.scene.collection.objects.link(fine);fine.hide_render=False;fine.hide_set(False)
    H.select([high,fine]);bpy.ops.object.join();high=bpy.context.object
    restore=[]
    for m in set(high.data.materials)|set(low.data.materials):
        n=m.node_tree.nodes;l=m.node_tree.links;bs=next(x for x in n if x.type=='BSDF_PRINCIPLED');out=next(x for x in n if x.type=='OUTPUT_MATERIAL');old=out.inputs[0].links[0].from_socket;temp=[]
        if role!='Normal':
            em=n.new('ShaderNodeEmission');temp.append(em);em.inputs[1].default_value=1
            if role=='BaseColor':
                socket=bs.inputs['Base Color']
                if socket.is_linked:l.new(socket.links[0].from_socket,em.inputs[0])
                else:em.inputs[0].default_value=socket.default_value
            else:
                comb=n.new('ShaderNodeCombineColor');comb.mode='RGB';comb.inputs['Red'].default_value=1;temp.append(comb)
                for component,key in [('Green','Roughness'),('Blue','Metallic')]:
                    socket=bs.inputs[key]
                    if socket.is_linked:l.new(socket.links[0].from_socket,comb.inputs[component])
                    else:comb.inputs[component].default_value=socket.default_value
                l.new(comb.outputs[0],em.inputs[0])
            l.new(em.outputs[0],out.inputs[0])
        target=n.new('ShaderNodeTexImage');target.image=im;temp.append(target)
        for node in n:node.select=False
        n.active=target;target.select=True;restore.append((m,out,old,temp))
    proxy.hide_render=True;proxy.hide_set(True)
    H.select([low,high]);bpy.context.view_layer.objects.active=low
    print('SELECTED_TO_ACTIVE_BEGIN '+role,flush=True)
    bpy.ops.object.bake(type='NORMAL' if role=='Normal' else 'EMIT',use_selected_to_active=True,cage_extrusion=.035,max_ray_distance=.09,margin=8,use_clear=False)
    im.filepath_raw=row['path'];im.save()
    for m,out,old,temp in restore:
        m.node_tree.links.new(old,out.inputs[0])
        for node in temp:m.node_tree.nodes.remove(node)
    bpy.data.objects.remove(low,do_unlink=True);bpy.data.objects.remove(high,do_unlink=True);proxy.hide_render=False;proxy.hide_set(False)
    bpy.context.scene.render.bake.use_selected_to_active=False
    row['sha256']=H.sha(row['path']);row['method']='low self-base + separate soil high-to-low SelectedToActive';row['cage_extrusion_m']=.035;row['max_ray_distance_m']=.09
    print('SELECTED_TO_ACTIVE_END '+role,flush=True);return row

def main():
    start=time.time();assert not (OUT/'editable_source.blend').exists(),'Preserve prior attempt first'
    for sub in ['textures','evidence','source_inputs']:(OUT/sub).mkdir(exist_ok=True)
    frozen={str(p):H.sha(p) for p in [OUT.parent/'p5/build_asset.py',OUT.parent/'p5/manifest.json',OUT.parent/'p5/baked_source.blend']}
    assert H.sha(H.ATLAS)==H.ATLAS_SHA and H.sha(S.SURFACE)==S.SURFACE_SHA
    shutil.copyfile(H.ATLAS,OUT/'source_inputs/material_atlas_v1_UNEDITED.png');shutil.copyfile(S.SURFACE,OUT/'source_inputs/surface_atlas_v2_UNEDITED.png')
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    atlas=bpy.data.images.load(str(OUT/'source_inputs/material_atlas_v1_UNEDITED.png'));atlas.colorspace_settings.name='sRGB'
    mats={k:author(k,atlas) for k in ['concrete','soil','seal','stone0','stone1','stone2','stone3']};build(mats)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'geometry_attempt.blend'),relative_remap=False)
    report=S.OLD_GEOMETRY();report['main_terrain_grid']=[81,13]
    report['checks'].append({'name':'actual_fracture_bvh_embedded_and_visible','pass':all(r['inside_vertices']>0 and r['visible_exposed_vertices']>0 for r in EMBEDDED),'failed':[r for r in EMBEDDED if not(r['inside_vertices']>0 and r['visible_exposed_vertices']>0)]})
    report.update(embedded_aggregate=EMBEDDED,highpoly_bake_triangles=len(FINE.data.polygons),runtime_budget_goal=8000,collision_status='SOURCE_ONLY; new coarse collision not yet delivered. No P2 physics evidence reused.')
    write('geometry_report.json',report);assert all(c['pass'] for c in report['checks']),[c for c in report['checks'] if not c['pass']]
    H.studio();bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'editable_source.blend'),relative_remap=False);source_sha=H.sha(OUT/'editable_source.blend')
    proxy=H.proxy_and_uv();H.attribute_audit(proxy);bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'uv_checkpoint.blend'),relative_remap=False)
    maps=[]
    for role in ['BaseColor','ORM','Normal']:
        maps.append(bake(proxy,role));write('bake_report.json',{'status':'CHECKPOINT_'+role,'maps':maps})
    mat=H.final_mat(maps);proxy.data.materials.clear();proxy.data.materials.append(mat)
    for p in proxy.data.polygons:p.material_index=0
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'baked_source.blend'),relative_remap=False)
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath:im.filepath=bpy.path.relpath(bpy.path.abspath(im.filepath))
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'baked_source.blend'),relative_remap=False);bpy.ops.wm.open_mainfile(filepath=str(OUT/'baked_source.blend'))
    reopened=[]
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath:
            p=Path(bpy.path.abspath(im.filepath));assert p.exists();im.reload();assert len(im.pixels[:4])==4 and im.has_data;reopened.append({'path':str(p),'sha256':H.sha(p),'colorspace':im.colorspace_settings.name})
    scene=bpy.context.scene;scene.cycles.samples=24;path=OUT/'evidence/transition_source_p6.png';scene.render.filepath=str(path);bpy.ops.render.render(write_still=True)
    assert all(H.sha(p)==digest for p,digest in frozen.items())
    report.update(status='P6_SOURCE_RENDERED_PENDING_ACTUAL_ART_REVIEW_NO_GLB',maps=maps,reopened_images=reopened,render_sha256=H.sha(path),editable_sha256=source_sha,source_unchanged=H.sha(OUT/'editable_source.blend')==source_sha,frozen_inputs_unchanged=True,seconds=time.time()-start)
    write('production_report.json',report);print(json.dumps({'pid':os.getpid(),'stage':'end','seconds':time.time()-start,'triangles':report['triangles'],'render':str(path)}),flush=True)

if __name__=='__main__':main()
