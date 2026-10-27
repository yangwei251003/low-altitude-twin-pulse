"""P9: scanned 2.5m soil PBR / unchanged low geometry / native contact AO.
Source-only, CPU2, one fixed camera. P3/P5 are read-only libraries, never rewritten.
"""
from pathlib import Path
import sys, importlib.util, math, random, json, time, os, shutil
sys.dont_write_bytecode=True
import bpy,bmesh,hashlib,struct
from mathutils import Vector
from mathutils.bvhtree import BVHTree
OUT=Path(__file__).resolve().parent
material_spec=importlib.util.spec_from_file_location('p9_scan_material',OUT/'scan_soil_material.py')
material_module=importlib.util.module_from_spec(material_spec);material_spec.loader.exec_module(material_module)
spec=importlib.util.spec_from_file_location('frozen_p5',OUT.parent/'p5/build_asset.py')
S=importlib.util.module_from_spec(spec);spec.loader.exec_module(S)
H=S.H;H.OUT=OUT;S.OUT=OUT
ROOT=H.ROOT
EMBEDDED=[];STONE_ROWS=[];SOIL=None
CHANNEL=S.channel_data

def write(name,value):
    (OUT/name).write_text(json.dumps(value,ensure_ascii=False,indent=2),encoding='utf-8')

def soil_y(x,z):
    s=H.clamp((z-H.front(x))/(H.outer(x)-H.front(x)))
    side=math.sin(math.pi*H.clamp((x+3)/6))**.45
    _,_,groove,bank=CHANNEL(x,z)
    # Real broad bed: dark fracture is exposed above it, rills are 1–2cm lower.
    shoulder=.009*bank*(.75+.25*math.sin(x*4.3+z*5.1))
    return (-.058*(1-s)-.025*groove+shoulder+.0025*math.sin(x*2.3+s*5)*math.sin(math.pi*s))*side*min(1,(1-s)*10)
H.soil_y=soil_y;S.soil_y=soil_y
BASE_MESH=S.mesh
def mesh(name,vs,fs,mat,group,kind):
    ob=BASE_MESH(name,vs,fs,mat,group,kind)
    if kind=='soil':material_module.ensure_scan_uv(ob)
    return ob
# grid_solid belongs to the frozen helper module and resolves its own mesh
# global. Route it through this local wrapper so the soil receives SoilScanUV.
H.mesh=mesh

def author(kind,atlas):
    if kind=='soil':return material_module.make_soil_material()
    if kind=='seal':return S.OLD_AUTHOR(kind,atlas)
    if kind=='concrete':
        m=S.OLD_AUTHOR(kind,atlas)
        for n in m.node_tree.nodes:
            if n.type=='MIX_RGB' and tuple(round(c,3) for c in n.inputs[1].default_value[:3])==(.23,.235,.22):
                n.inputs[1].default_value=(.105,.11,.10,1);n.inputs[0].default_value=.48
        return m
    g=H.Graph('SOURCE_P9_'+kind);n,l=g.n,g.l
    uv=n.new('ShaderNodeUVMap');uv.uv_map='MetricUV'
    attr=n.new('ShaderNodeVertexColor');attr.layer_name='SurfaceControl'
    sep=n.new('ShaderNodeSeparateColor');l.new(attr.outputs[0],sep.inputs[0])
    if kind.startswith('stone'):
        shade=int(kind[-1]);colors=[(.14,.125,.105,1),(.19,.175,.15,1),(.23,.22,.19,1),(.115,.118,.105,1)]
        rock=n.new('ShaderNodeTexNoise');l.new(uv.outputs[0],rock.inputs['Vector']);rock.inputs['Scale'].default_value=22;rock.inputs['Detail'].default_value=1.2
        factor=g.op('ADD',.78,g.op('MULTIPLY',rock.outputs['Fac'],.34))
        mult=n.new('ShaderNodeMixRGB');mult.blend_type='MULTIPLY';mult.inputs[0].default_value=1;mult.inputs[1].default_value=colors[shade];l.new(factor,mult.inputs[2]);base=mult.outputs[0]
        rough=.80+shade*.025;micro=.0013
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
    embedded=cy is not None
    cy=soil_y(cx,cz)+height*.10 if cy is None else cy
    aspect=rng.uniform(.65,.90);vs=[]
    tilt=0 if embedded else rng.uniform(-.36,.36)
    for a,b,c in raw:
        factor=rng.uniform(.88,1.12) if embedded else rng.uniform(.83,1.17);xx=(a*math.cos(angle)-b*math.sin(angle))*dia*.5*factor;zz=(a*math.sin(angle)+b*math.cos(angle))*dia*.5*aspect*factor
        yy=c*height*.5*(rng.uniform(.9,1.1) if embedded else rng.uniform(.86,1.14))
        # Purposeful tilt preserves a thick angular body; it is not a flat disk
        # made to look rounded with a normal map. Embedded edge pieces stay put.
        yy,zz=yy*math.cos(tilt)-zz*math.sin(tilt),yy*math.sin(tilt)+zz*math.cos(tilt)
        vs.append(H.bp(cx+xx,cy+yy,cz+zz))
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
    for _ in range(80):
        ri=rng.choices(range(6),weights=[3,1,3,1,3,1])[0];t=rng.uniform(.05,.95)
        # Continuous but uneven density, not three synchronized blank intervals.
        if rng.random()>.82+.16*math.sin(t*9.7+ri*1.9):continue
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
    global SOIL
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
        add_low_stone('SedimentBankStone_%03d'%i,x,z,dia,rng.uniform(.050,.085),rng,mats['stone%d'%(i%4)])
        low_positions.append((x,z,dia*.38))
    for i in range(12):
        center,spread=[(-2.32,.30),(-1.10,.26),(.42,.32),(1.73,.35)][i%4]
        x=center+rng.uniform(-spread,spread);z=H.front(x)+rng.uniform(.10,.31)
        add_low_stone('FallenConcreteFragment_%02d'%i,x,z,rng.uniform(.13,.23),rng.uniform(.080,.125),rng,mats['stone%d'%((i+1)%4)],sub=2)
        low_positions.append((x,z,.09))
    write('sediment_distribution.json',{'low_stones':STONE_ROWS,'fine_stones':[],'small_stones_bake_only':False,'fine_triangles':0,'embedded':EMBEDDED,'method':'No high-only grain layer. Official Sandy Gravel 02 scan is baked through 2.5m SoilScanUV onto unchanged true low terrain.'})

def subset(proxy,group,name):
    ob=proxy.copy();ob.data=proxy.data.copy();bpy.context.scene.collection.objects.link(ob);ob.name=name;ob.hide_render=False;ob.hide_set(False)
    bm=bmesh.new();bm.from_mesh(ob.data);layer=bm.faces.layers.int['RuntimeGroup'];bmesh.ops.delete(bm,geom=[f for f in bm.faces if f[layer]!=group],context='FACES');bmesh.ops.delete(bm,geom=[v for v in bm.verts if not v.link_faces],context='VERTS');bm.to_mesh(ob.data);bm.free();ob.data.update();return ob

def bake(proxy,role):
    # Source material normal/roughness are baked on the actual low geometry.
    # No selected-to-active invented fine-stone blanket in P9.
    return H.bake(proxy,role)

def contact_ao(proxy):
    """Actual local hemispherical occlusion from a copy of the joined low mesh.
    OnlyLocal excludes the active target duplicate and the studio ground. It does
    include the terrain, embedded fragments and true coarse stones. The source
    scan's fine relief is not claimed to supply geometrical contact AO here.
    """
    high=proxy.copy();high.data=proxy.data.copy();bpy.context.scene.collection.objects.link(high);high.name='TEMP_P9_HighContactGeometry';high.hide_render=False;high.hide_set(False)
    im=bpy.data.images.new('P9_ContactAO_Raw',width=H.SIZE,height=H.SIZE,alpha=False);im.colorspace_settings.name='Non-Color';im.generated_color=(1,1,1,1)
    restore=[]
    for m in set(high.data.materials)|set(proxy.data.materials):
        n=m.node_tree.nodes;l=m.node_tree.links;out=next(x for x in n if x.type=='OUTPUT_MATERIAL');old=out.inputs[0].links[0].from_socket
        ao=n.new('ShaderNodeAmbientOcclusion');ao.only_local=True;ao.inside=False;ao.samples=16;ao.inputs['Distance'].default_value=.08;ao.inputs['Color'].default_value=(1,1,1,1)
        em=n.new('ShaderNodeEmission');em.inputs[1].default_value=1;l.new(ao.outputs['AO'],em.inputs[0]);l.new(em.outputs[0],out.inputs[0])
        target=n.new('ShaderNodeTexImage');target.image=im
        for node in n:node.select=False
        target.select=True;n.active=target;restore.append((m,out,old,[ao,em,target]))
    H.select([proxy,high]);bpy.context.view_layer.objects.active=proxy;scene=bpy.context.scene;scene.cycles.samples=1
    print('CONTACT_AO_BEGIN source_only_local distance=.08 samples=16',flush=True)
    bpy.ops.object.bake(type='EMIT',use_selected_to_active=True,cage_extrusion=.035,max_ray_distance=.09,margin=8,use_clear=True)
    path=OUT/'textures/AO_Contact_Raw.png';im.filepath_raw=str(path);im.file_format='PNG';im.save()
    for m,out,old,temp in restore:
        m.node_tree.links.new(old,out.inputs[0])
        for node in temp:m.node_tree.nodes.remove(node)
    bpy.data.objects.remove(high,do_unlink=True);scene.render.bake.use_selected_to_active=False
    print('CONTACT_AO_END',flush=True)
    return {'path':str(path),'sha256':H.sha(path),'colorspace':'Non-Color','source_geometry':'Unchanged true low terrain and coarse stones only; no high-only small-grain geometry','node':'AmbientOcclusion only_local=True inside=False samples=16','distance_m':.08,'cage_extrusion_m':.035,'max_ray_distance_m':.09,'lighting_baked':False}

def pack_orm(proxy,maps,ao_row):
    original=next(r for r in maps if r['role']=='ORM');raw=OUT/'textures/Transition_ORM_before_AO.png';shutil.copyfile(original['path'],raw)
    g=H.Graph('TEMP_P9_NativeORMPacking');n,l=g.n,g.l;uv=n.new('ShaderNodeUVMap');uv.uv_map='BakeUV'
    ao=n.new('ShaderNodeTexImage');ao.image=bpy.data.images.load(ao_row['path'],check_existing=False);ao.image.colorspace_settings.name='Non-Color';l.new(uv.outputs[0],ao.inputs[0])
    old=n.new('ShaderNodeTexImage');old.image=bpy.data.images.load(str(raw),check_existing=False);old.image.colorspace_settings.name='Non-Color';l.new(uv.outputs[0],old.inputs[0])
    split=n.new('ShaderNodeSeparateColor');l.new(old.outputs[0],split.inputs[0]);comb=n.new('ShaderNodeCombineColor');comb.mode='RGB';l.new(ao.outputs[0],comb.inputs['Red']);l.new(split.outputs['Green'],comb.inputs['Green']);l.new(split.outputs['Blue'],comb.inputs['Blue'])
    em=n.new('ShaderNodeEmission');em.inputs[1].default_value=1;l.new(comb.outputs[0],em.inputs[0]);out=n.new('ShaderNodeOutputMaterial');l.new(em.outputs[0],out.inputs[0])
    im=bpy.data.images.new('P9_ORM_Final',width=H.SIZE,height=H.SIZE,alpha=False);im.colorspace_settings.name='Non-Color'
    target=n.new('ShaderNodeTexImage');target.image=im;n.active=target;target.select=True
    proxy.data.materials.clear();proxy.data.materials.append(g.m)
    for p in proxy.data.polygons:p.material_index=0
    H.select([proxy]);bpy.ops.object.bake(type='EMIT',use_selected_to_active=False,margin=8,use_clear=True)
    im.filepath_raw=original['path'];im.file_format='PNG';im.save();original.update(sha256=H.sha(original['path']),occlusion='R actual native contact AO, no painted albedo shadow',roughness='G preserved from native author bake',metallic='B preserved from native author bake')
    # All image writes above were native Blender image saves / shader baking.
    # No external pixel editing or source image alteration.
    return original

def delivery_and_preview_materials(maps):
    standard=H.final_mat(maps);standard.name='GroundTransition_GLTF_P9';standard.use_fake_user=True
    n,l=standard.node_tree.nodes,standard.node_tree.links
    split=next(x for x in n if x.type=='SEPARATE_COLOR')
    group=bpy.data.node_groups.get('glTF Material Output')
    if group is None:
        group=bpy.data.node_groups.new('glTF Material Output','ShaderNodeTree');group.interface.new_socket(name='Occlusion',in_out='INPUT',socket_type='NodeSocketFloat')
    gltf=n.new('ShaderNodeGroup');gltf.node_tree=group;l.new(split.outputs['Red'],gltf.inputs['Occlusion'])
    preview=standard.copy();preview.name='GroundTransition_PreviewContactAO_P9'
    n,l=preview.node_tree.nodes,preview.node_tree.links;bs=next(x for x in n if x.type=='BSDF_PRINCIPLED');split=next(x for x in n if x.type=='SEPARATE_COLOR');base=bs.inputs['Base Color'].links[0].from_socket
    multiply=n.new('ShaderNodeMixRGB');multiply.name='PreviewOnly_ContactOcclusion';multiply.blend_type='MULTIPLY';multiply.inputs[0].default_value=1;l.new(base,multiply.inputs[1]);l.new(split.outputs['Red'],multiply.inputs[2]);l.new(multiply.outputs[0],bs.inputs['Base Color'])
    preview['export_material']='GroundTransition_GLTF_P9';preview['preview_only_ao_response']='Same ORM R; multiplication approximates AO for offline inspection. glTF uses occlusionTexture; lighting equivalence is not claimed.'
    return standard,preview

def verify_frozen_low_parts():
    def signature(ob):
        digest=hashlib.sha256()
        for v in ob.data.vertices:digest.update(struct.pack('<3f',*v.co))
        for f in ob.data.polygons:
            digest.update(struct.pack('<I',len(f.vertices)))
            digest.update(struct.pack('<'+'I'*len(f.vertices),*f.vertices))
        for row in ob.matrix_world:digest.update(struct.pack('<4f',*row))
        return digest.hexdigest()
    names=tuple(ob.name for ob in H.PARTS);current={ob.name:signature(ob) for ob in H.PARTS}
    with bpy.data.libraries.load(str(OUT.parent/'p7/editable_source.blend'),link=False) as (available,loaded):
        assert all(name in available.objects for name in names)
        loaded.objects=list(names)
    rows=[]
    for name,ob in zip(names,loaded.objects):
        old=signature(ob);rows.append({'name':name,'p7':old,'p9':current[name],'equal':old==current[name]})
        bpy.data.objects.remove(ob,do_unlink=True)
    result={'method':'Exact float32 vertices, ordered original polygon indices and object matrix from frozen P7 editable source; material excluded.','parts':rows,'all_equal':all(r['equal'] for r in rows)}
    write('low_geometry_equivalence.json',result)
    assert result['all_equal'],[r['name'] for r in rows if not r['equal']]
    return result

def main():
    start=time.time();assert not (OUT/'editable_source.blend').exists(),'Preserve prior attempt first'
    for sub in ['textures','evidence','source_inputs']:(OUT/sub).mkdir(exist_ok=True)
    frozen={str(p):H.sha(p) for p in [OUT.parent/'p7/build_asset.py',OUT.parent/'p7/manifest.json',OUT.parent/'p7/baked_source.blend']}
    vendor=material_module.verify_inputs()
    frozen.update({str(material_module.VENDOR/Path(row['path']).name):row['sha256'] for row in vendor['files']})
    frozen.update({str(OUT.parent/'p8/manifest.json'):H.sha(OUT.parent/'p8/manifest.json'),str(OUT.parent/'p8/baked_source.blend'):H.sha(OUT.parent/'p8/baked_source.blend')})
    assert H.sha(H.ATLAS)==H.ATLAS_SHA and H.sha(S.SURFACE)==S.SURFACE_SHA
    shutil.copyfile(H.ATLAS,OUT/'source_inputs/material_atlas_v1_UNEDITED.png');shutil.copyfile(S.SURFACE,OUT/'source_inputs/surface_atlas_v2_UNEDITED.png')
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    atlas=bpy.data.images.load(str(OUT/'source_inputs/material_atlas_v1_UNEDITED.png'));atlas.colorspace_settings.name='sRGB'
    mats={k:author(k,atlas) for k in ['concrete','soil','seal','stone0','stone1','stone2','stone3']};build(mats)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'geometry_attempt.blend'),relative_remap=False)
    low_equivalence=verify_frozen_low_parts()
    report=S.OLD_GEOMETRY();report['main_terrain_grid']=[81,13]
    report['checks'].append({'name':'exact_low_geometry_matches_frozen_P7','pass':low_equivalence['all_equal']})
    report['checks'].append({'name':'actual_fracture_bvh_embedded_and_visible','pass':all(r['inside_vertices']>0 and r['visible_exposed_vertices']>0 for r in EMBEDDED),'failed':[r for r in EMBEDDED if not(r['inside_vertices']>0 and r['visible_exposed_vertices']>0)]})
    report.update(embedded_aggregate=EMBEDDED,highpoly_bake_triangles=0,runtime_budget_goal=8000,collision_status='SOURCE_ONLY; new coarse collision not yet delivered. No P2 physics evidence reused.')
    write('geometry_report.json',report);assert all(c['pass'] for c in report['checks']),[c for c in report['checks'] if not c['pass']]
    H.studio();bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'editable_source.blend'),relative_remap=False);source_sha=H.sha(OUT/'editable_source.blend')
    proxy=H.proxy_and_uv();H.attribute_audit(proxy)
    write('soil_scan_binding.json',material_module.verify_scan_binding(proxy))
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'uv_checkpoint.blend'),relative_remap=False)
    maps=[]
    for role in ['BaseColor','ORM','Normal']:
        maps.append(bake(proxy,role));write('bake_report.json',{'status':'CHECKPOINT_'+role,'maps':maps})
    ao=contact_ao(proxy);write('contact_ao_report.json',ao);pack_orm(proxy,maps,ao)
    standard,mat=delivery_and_preview_materials(maps);proxy.data.materials.clear();proxy.data.materials.append(mat)
    for p in proxy.data.polygons:p.material_index=0
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'baked_source.blend'),relative_remap=False)
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath:im.filepath=bpy.path.relpath(bpy.path.abspath(im.filepath))
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'baked_source.blend'),relative_remap=False);bpy.ops.wm.open_mainfile(filepath=str(OUT/'baked_source.blend'))
    reopened=[]
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath:
            p=Path(bpy.path.abspath(im.filepath));assert p.exists();im.reload();assert len(im.pixels[:4])==4 and im.has_data;reopened.append({'path':str(p),'sha256':H.sha(p),'colorspace':im.colorspace_settings.name})
    scene=bpy.context.scene;scene.cycles.samples=24;path=OUT/'evidence/transition_source_p9.png';scene.render.filepath=str(path);bpy.ops.render.render(write_still=True)
    # Keep the exact full camera for comparison. A second camera translates and
    # narrows the same oblique view around the first channel for contact review.
    camera=scene.camera;old_location=camera.location.copy();old_scale=camera.data.ortho_scale
    camera.location+=Vector((-1.15,-.06,0));camera.data.ortho_scale=2.5
    close=OUT/'evidence/transition_contact_close_p9.png';scene.render.filepath=str(close);bpy.ops.render.render(write_still=True)
    camera.location=old_location;camera.data.ortho_scale=old_scale
    assert all(H.sha(p)==digest for p,digest in frozen.items())
    report.update(status='P9_SOURCE_RENDERED_PENDING_ACTUAL_ART_REVIEW_NO_GLB',maps=maps,contact_ao=ao,reopened_images=reopened,render_sha256=H.sha(path),close_render_sha256=H.sha(close),editable_sha256=source_sha,source_unchanged=H.sha(OUT/'editable_source.blend')==source_sha,frozen_inputs_unchanged=True,seconds=time.time()-start)
    write('production_report.json',report);print(json.dumps({'pid':os.getpid(),'stage':'end','seconds':time.time()-start,'triangles':report['triangles'],'render':str(path)}),flush=True)

if __name__=='__main__':main()
