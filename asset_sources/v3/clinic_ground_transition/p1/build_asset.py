"""Original 6m coastal transition. Explicit shared boundary geometry, native PBR bake.
Source scene is editable; no Godot or production world changes. CPU2 only.
"""
from pathlib import Path
import bpy,bmesh,math,random,json,hashlib,time,os,shutil,sys
from mathutils import Vector
OUT=Path(__file__).resolve().parent;ROOT=OUT.parents[3]
ATLAS=ROOT/'references/v3/production/clinic_ground_transition/material_atlas_v1.png'
ATLAS_SHA='5c484832953ec55f4df0f9d3cefe137dc163558475ebb5501604d5557baefb19'
PARTS=[];GROUPS=['ConcreteAndSeals','AggregateAndChips'];CHIPS=[];SIZE=2048
X=[-3+i*.1 for i in range(61)]
EDGE=[(-3,.72),(-2.78,.75),(-2.57,.64),(-2.32,.66),(-2.04,.83),(-1.81,.87),(-1.58,.73),(-1.31,.53),(-1.08,.49),(-.86,.60),(-.64,.78),(-.36,.80),(-.14,.72),(.06,.75),(.29,.57),(.47,.52),(.69,.69),(.91,.84),(1.15,.89),(1.39,.73),(1.67,.50),(1.90,.53),(2.12,.65),(2.35,.80),(2.61,.81),(2.82,.76),(3,.72)]
OUTER=[(-3,2.14),(-2.65,2.26),(-2.23,2.14),(-1.81,2.38),(-1.48,2.40),(-1.08,2.21),(-.68,2.16),(-.20,2.36),(.21,2.31),(.65,2.15),(1.05,2.21),(1.44,2.39),(1.88,2.25),(2.24,2.06),(2.60,2.16),(3,2.20)]
FANS=[(-1.12,-.20,.34),(.40,.32,.27),(1.74,-.24,.38)]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def gp(p):return [float(p[0]),float(p[2]),float(-p[1])]
def bp(x,y,z):return (x,-z,y)
def interp(x,points):
    for (a,b),(c,d) in zip(points,points[1:]):
        if x<=c:return b+(d-b)*max(0,min(1,(x-a)/(c-a)))
    return points[-1][1]
def front(x):return interp(x,EDGE)
def outer(x):return interp(x,OUTER)
def clamp(v,a=0,b=1):return max(a,min(b,v))
def wet(x,z):
    value=0
    for center,bend,width in FANS:
        s=clamp((z-front(center))/1.65)
        axis=center+bend*s+.04*math.sin(s*8)
        w=width*(.38+.95*s)
        profile=math.exp(-((x-axis)/max(.03,w))**2*2.1)
        value=max(value,profile*(.82-.27*s))
    return value
def soil_y(x,z):
    f=front(x);s=clamp((z-f)/(outer(x)-f));side=math.sin(math.pi*clamp((x+3)/6))**.45
    # Connected shallow depression, boundaries exactly return to Y0.
    base=-.048*(1-s)-.017*math.sin(s*math.pi)*wet(x,z)
    broad=.004*math.sin(x*2.3+s*5)*math.sin(math.pi*s)
    return (base+broad)*side
def edge_y(x):return -.012*math.sin(math.pi*clamp((x+3)/6))-.018*(.5+.5*math.sin(x*5.2+.7))*math.sin(math.pi*clamp((x+3)/6))
def select(obs):
    bpy.ops.object.select_all(action='DESELECT')
    for o in obs:o.hide_set(False);o.select_set(True)
    bpy.context.view_layer.objects.active=obs[0]
def mesh(name,vs,fs,mat,group,kind):
    me=bpy.data.meshes.new(name);me.from_pydata(vs,[],fs);me.update()
    bm=bmesh.new();bm.from_mesh(me);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free();me.update()
    ob=bpy.data.objects.new(name,me);bpy.context.scene.collection.objects.link(ob);me.materials.append(mat)
    ob['editable_piece']=True;ob['runtime_group']=group;ob['material_kind']=kind
    me.uv_layers.new(name='MetricUV');uv=me.uv_layers['MetricUV']
    control=me.color_attributes.new(name='SurfaceControl',type='FLOAT_COLOR',domain='CORNER')
    for p in me.polygons:
        axis=max(range(3),key=lambda i:abs(p.normal[i]))
        for li in p.loop_indices:
            v=me.vertices[me.loops[li].vertex_index].co;x,y,z=gp(v)
            pair=(z,y) if axis==0 else ((x,y) if axis==1 else (x,z))
            uv.data[li].uv=(pair[0]/1.5,pair[1]/1.5)
            wear=clamp((z-front(x)+.18)/.25) if kind=='concrete' else 0
            control.data[li].color=(wet(x,z),wear,1 if axis==2 else 0,1)
    attr=me.attributes.new(name='RuntimeGroup',type='INT',domain='FACE')
    for f in attr.data:f.value=GROUPS.index(group)
    PARTS.append(ob);return ob
def grid_solid(name,top,rows,cols,mat,group,kind,bottom=-.18):
    vs=list(top)+[(x,y,bottom) for x,y,z in top];N=len(top);faces=[]
    for j in range(rows-1):
        for i in range(cols-1):
            a=j*cols+i;b=a+1;c=a+cols+1;d=a+cols
            faces.extend([(a,d,c),(a,c,b),(N+a,N+b,N+c),(N+a,N+c,N+d)])
    ring=list(range(cols))+[j*cols+cols-1 for j in range(1,rows)]+list(range((rows-1)*cols+cols-2,(rows-1)*cols-1,-1))+[j*cols for j in range(rows-2,0,-1)]
    for a,b in zip(ring,ring[1:]+ring[:1]):faces.append((a,b,N+b,N+a))
    return mesh(name,vs,faces,mat,group,kind)
class Graph:
    def __init__(self,name):
        self.m=bpy.data.materials.new(name);self.m.use_nodes=True;self.n=self.m.node_tree.nodes;self.n.clear();self.l=self.m.node_tree.links
    def put(self,v,s):
        if hasattr(v,'node'):self.l.new(v,s)
        else:s.default_value=v
    def op(self,op,a,b=None):
        n=self.n.new('ShaderNodeMath');n.operation=op;self.put(a,n.inputs[0])
        if b is not None:self.put(b,n.inputs[1])
        return n.outputs[0]
    def mix(self,a,b,f):
        n=self.n.new('ShaderNodeMixRGB');n.blend_type='MIX';self.put(f,n.inputs[0]);self.put(a,n.inputs[1]);self.put(b,n.inputs[2]);return n.outputs[0]
def author(kind,atlas):
    g=Graph('SOURCE_'+kind);n=g.n;l=g.l;uv=n.new('ShaderNodeUVMap');uv.uv_map='MetricUV'
    split=n.new('ShaderNodeSeparateXYZ');l.new(uv.outputs[0],split.inputs[0]);attr=n.new('ShaderNodeVertexColor');attr.layer_name='SurfaceControl';sep=n.new('ShaderNodeSeparateColor');l.new(attr.outputs[0],sep.inputs[0])
    def image(q,phase=(.17,.23),scale=1):
        c=n.new('ShaderNodeCombineXYZ')
        for axis,component,p in [('X','X',phase[0]),('Y','Y',phase[1])]:
            val=g.op('PINGPONG',g.op('ADD',g.op('MULTIPLY',split.outputs[component],scale),p),1)
            l.new(g.op('ADD',q[0 if axis=='X' else 1]+.008,g.op('MULTIPLY',val,.484)),c.inputs[axis])
        t=n.new('ShaderNodeTexImage');t.image=atlas;t.extension='EXTEND';l.new(c.outputs[0],t.inputs[0]);return t.outputs[0]
    noise=n.new('ShaderNodeTexNoise');l.new(uv.outputs[0],noise.inputs['Vector']);noise.inputs['Scale'].default_value=62;noise.inputs['Detail'].default_value=1.5
    if kind=='concrete':
        base=g.mix((.30,.28,.245,1),image((0,.5)),.84)
        broken=g.mix((.23,.235,.22,1),image((.5,.5),scale=1.5),.67)
        # Fracture material on sides and just the thin top broken lip, not full slab.
        frac=g.op('MAXIMUM',g.op('SUBTRACT',1,sep.outputs['Blue']),g.op('MULTIPLY',sep.outputs['Green'],.28))
        base=g.mix(base,broken,frac);rough=.82;dist=.0012
        damp=g.op('MULTIPLY',sep.outputs['Red'],g.op('MULTIPLY',sep.outputs['Green'],.25));base=g.mix(base,(.15,.145,.13,1),damp)
    elif kind=='soil':
        dry=g.mix((.185,.158,.12,1),image((0,0)),.56)
        damp=g.mix((.105,.088,.064,1),image((.5,0),(.41,.13)),.55)
        base=g.mix(dry,damp,sep.outputs['Red']);rough=g.op('SUBTRACT',.86,g.op('MULTIPLY',sep.outputs['Red'],.26));dist=.0023
    elif kind=='chip':base=g.mix((.29,.29,.26,1),image((.5,.5),scale=1.6),.55);rough=.83;dist=.0007
    else:base=(.045,.048,.043,1);rough=.94;dist=.0002
    bs=n.new('ShaderNodeBsdfPrincipled');g.put(base,bs.inputs['Base Color']);g.put(rough,bs.inputs['Roughness']);bs.inputs['Metallic'].default_value=0;bs.inputs['Emission Strength'].default_value=0
    bump=n.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.28;bump.inputs['Distance'].default_value=dist;l.new(noise.outputs['Fac'],bump.inputs['Height']);l.new(bump.outputs[0],bs.inputs['Normal'])
    out=n.new('ShaderNodeOutputMaterial');l.new(bs.outputs[0],out.inputs[0]);return g.m
def build(mats):
    # Three unequal surviving concrete lengths, two real narrow joints.
    ranges=[(-3,-1.17),(-1.15,.83),(.85,3)]
    for k,(a,b) in enumerate(ranges):
        xs=sorted(set([a,b]+[x for x in X if a<x<b]));top=[]
        for row in range(4):
            for x in xs:
                f=front(x)
                z=[.01,.18,f-.055,f][row];y=[0,0,0,edge_y(x)][row]
                top.append(bp(x,y,z))
        grid_solid('ConcreteResidual_%02d'%k,top,4,len(xs),mats['concrete'],GROUPS[0],'concrete')
    for k,(a,b) in enumerate([(-1.17,-1.15),(.83,.85)]):
        zmax=min(front(a),front(b))-.002
        grid_solid('RecessedCrossSeal_%02d'%k,[bp(a,-.012,.01),bp(b,-.012,.01),bp(a,-.012,zmax),bp(b,-.012,zmax)],2,2,mats['seal'],GROUPS[0],'seal')
    grid_solid('JoinSeal_10mm',[bp(-3,-.012,0),bp(3,-.012,0),bp(-3,-.012,.01),bp(3,-.012,.01)],2,2,mats['seal'],GROUPS[0],'seal')
    soil=[]
    for row in range(11):
        s=row/10
        for x in X:
            z=front(x)+(outer(x)-front(x))*s;soil.append(bp(x,soil_y(x,z),z))
    soil_ob=grid_solid('CompactedSoil_ContinuousSupport',soil,11,len(X),mats['soil'],GROUPS[1],'soil')
    # 24 non-uniform chips; maximum actual diameter 8cm. Clusters only near 3 breaks.
    rng=random.Random(73109)
    for i in range(24):
        center,bend,width=FANS[i%3];x=clamp(center+rng.uniform(-.28,.30),-2.9,2.9);z=front(x)+rng.uniform(.09,.52)
        radius=rng.uniform(.018,.04);h=rng.uniform(.014,.035);surface=soil_y(x,z)
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=1)
        tmp=bpy.context.object;vs=[]
        angle=rng.random()*math.tau
        for v in tmp.data.vertices:
            vx,vy,vz=v.co;stretch=1+rng.uniform(-.13,.13);xx=(vx*math.cos(angle)-vy*math.sin(angle))*radius;zz=(vx*math.sin(angle)+vy*math.cos(angle))*radius*.75
            yy=surface-.002+vz*h*.62;vs.append(bp(x+xx,yy,z+zz))
        fs=[list(p.vertices) for p in tmp.data.polygons];bpy.data.objects.remove(tmp,do_unlink=True)
        ob=mesh('SettledChip_%02d'%i,vs,fs,mats['chip'],GROUPS[1],'chip')
        ys=[p[2] for p in vs];CHIPS.append({'name':ob.name,'ground_center':[x,surface,z],'min_y':min(ys),'max_y':max(ys),'protrusion_m':max(ys)-surface,'diameter_m':radius*2,'embedded_below_ground_m':surface-min(ys)})
    return soil_ob
def geometry_report():
    checks=[];rows=[]
    for o in PARTS:
        bm=bmesh.new();bm.from_mesh(o.data);bad=[e for e in bm.edges if not e.is_manifold];volume=bm.calc_volume(signed=True);bm.free();o.data.calc_loop_triangles()
        checks.append({'name':o.name+' closed_positive_volume','pass':not bad and volume>0,'bad_edges':len(bad),'volume_m3':volume})
        rows.append({'name':o.name,'group':o['runtime_group'],'triangles':len(o.data.loop_triangles),'vertices':len(o.data.vertices)})
    p=[gp(v.co) for o in PARTS for v in o.data.vertices]
    bounds={'min':[min(v[i] for v in p) for i in range(3)],'max':[max(v[i] for v in p) for i in range(3)]}
    checks.extend([{'name':'6m_x_2.4m_footprint','pass':abs(bounds['min'][0]+3)<1e-6 and abs(bounds['max'][0]-3)<1e-6 and bounds['max'][2]<=2.400001 and bounds['min'][2]>=-1e-6},
      {'name':'heights_-0.18_to_0.03','pass':bounds['min'][1]>=-.180001 and bounds['max'][1]<=.030001},
      {'name':'all_chips_supported_and_visible','pass':all(c['embedded_below_ground_m']>.002 and c['protrusion_m']>.004 for c in CHIPS)},
      {'name':'outer_and_side_perimeter_returns_Y0','pass':all(abs(soil_y(x,outer(x)))<1e-8 for x in X) and all(abs(soil_y(-3,front(-3)+(outer(-3)-front(-3))*s/10))<1e-8 and abs(soil_y(3,front(3)+(outer(3)-front(3))*s/10))<1e-8 for s in range(11))}])
    footprint=[[x,0,outer(x)] for x in reversed(X)];footprint=[[ -3,0,0],[3,0,0]]+footprint
    report={'status':'SOURCE_GEOMETRY','bounds_godot':bounds,'triangles':sum(r['triangles'] for r in rows),'editable_pieces':len(PARTS),'parts':rows,'checks':checks,'chips':CHIPS,'footprint_godot':footprint,'front_boundary_xz':[[x,front(x)] for x in X],'water_or_hydraulic_network':False,'limits':['Separate closed concrete and soil solids meet along a buried contact seam. No visible coplanar stacked surface.','Main body collision supplied separately after export; no game physics measured here.']}
    (OUT/'geometry_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));assert all(c['pass'] for c in checks),[c for c in checks if not c['pass']]
    return report
def studio():
    scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=24;scene.cycles.use_denoising=True;scene.render.threads_mode='FIXED';scene.render.threads=2
    scene.render.resolution_x=1440;scene.render.resolution_y=860;scene.render.resolution_percentage=100
    scene.world=bpy.data.worlds.new('NeutralReview');scene.world.use_nodes=True;wn=scene.world.node_tree.nodes;wn.clear();bg=wn.new('ShaderNodeBackground');wo=wn.new('ShaderNodeOutputWorld');scene.world.node_tree.links.new(bg.outputs[0],wo.inputs[0]);bg.inputs[0].default_value=(.34,.37,.40,1);bg.inputs[1].default_value=.45
    scene.view_settings.view_transform='AgX';scene.view_settings.look='AgX - Medium High Contrast';scene.view_settings.exposure=0
    for name,location,power,size in [('Review_Key',(-3,-4,7),700,6),('Review_Fill',(5,2,5),350,5)]:
        data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size;o=bpy.data.objects.new(name,data);scene.collection.objects.link(o);o.location=location;o.rotation_euler=(Vector((0,-1,0))-o.location).to_track_quat('-Z','Y').to_euler()
    camdata=bpy.data.cameras.new('ReferenceObliqueCamera');cam=bpy.data.objects.new('ReferenceObliqueCamera',camdata);scene.collection.objects.link(cam);cam.location=(5.6,-8.2,6.4);target=Vector((0,-1.12,-.025));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();camdata.type='ORTHO';camdata.ortho_scale=7.5;scene.camera=cam
    # Neutral floor is offline only and stays below the real foundation.
    bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.19));floor=bpy.context.object;floor.name='STUDIO_ONLY_FLOOR';m=bpy.data.materials.new('StudioGray');m.use_nodes=True;mn=m.node_tree.nodes;mn.clear();bs=mn.new('ShaderNodeBsdfPrincipled');mo=mn.new('ShaderNodeOutputMaterial');m.node_tree.links.new(bs.outputs[0],mo.inputs[0]);bs.inputs['Base Color'].default_value=(.14,.15,.16,1);bs.inputs['Roughness'].default_value=.9;floor.data.materials.append(m)
def proxy_and_uv():
    copies=[]
    for o in PARTS:
        c=o.copy();c.data=o.data.copy();bpy.context.scene.collection.objects.link(c);c['editable_piece']=False;copies.append(c);o.hide_render=True;o.hide_set(True)
    select(copies);bpy.ops.object.join();proxy=bpy.context.object;proxy.name='BakeProxy'
    tri=proxy.modifiers.new('ExactTriangulation','TRIANGULATE');bpy.ops.object.modifier_apply(modifier=tri.name)
    proxy.data.uv_layers.new(name='BakeUV');proxy.data.uv_layers.active_index=proxy.data.uv_layers.find('BakeUV')
    for u in proxy.data.uv_layers:u.active_render=u.name=='BakeUV'
    bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.uv.smart_project(angle_limit=math.radians(66),island_margin=.004);bpy.ops.object.mode_set(mode='OBJECT')
    return proxy
def bake(proxy,channel):
    print('BAKE_BEGIN '+channel,flush=True);im=bpy.data.images.new('Transition_'+channel,width=SIZE,height=SIZE,alpha=False);im.colorspace_settings.name='sRGB' if channel=='BaseColor' else 'Non-Color';restore=[]
    for m in proxy.data.materials:
        n=m.node_tree.nodes;l=m.node_tree.links;bs=next(x for x in n if x.type=='BSDF_PRINCIPLED');out=next(x for x in n if x.type=='OUTPUT_MATERIAL');old=out.inputs[0].links[0].from_socket;temp=[]
        if channel!='Normal':
            em=n.new('ShaderNodeEmission');temp.append(em);em.inputs[1].default_value=1
            if channel=='BaseColor':
                s=bs.inputs['Base Color']
                if s.is_linked:l.new(s.links[0].from_socket,em.inputs[0])
                else:em.inputs[0].default_value=s.default_value
            else:
                comb=n.new('ShaderNodeCombineColor');comb.mode='RGB';comb.inputs['Red'].default_value=1;temp.append(comb)
                for c,key in [('Green','Roughness'),('Blue','Metallic')]:
                    s=bs.inputs[key]
                    if s.is_linked:l.new(s.links[0].from_socket,comb.inputs[c])
                    else:comb.inputs[c].default_value=s.default_value
                l.new(comb.outputs[0],em.inputs[0])
            l.new(em.outputs[0],out.inputs[0])
        target=n.new('ShaderNodeTexImage');target.image=im;temp.append(target)
        for nd in n:nd.select=False
        target.select=True;n.active=target;restore.append((m,out,old,temp))
    select([proxy]);scene=bpy.context.scene;scene.cycles.samples=1;scene.render.bake.normal_space='TANGENT';scene.render.bake.normal_r='POS_X';scene.render.bake.normal_g='POS_Y';scene.render.bake.normal_b='POS_Z'
    bpy.ops.object.bake(type='NORMAL' if channel=='Normal' else 'EMIT',margin=8,use_clear=True)
    path=OUT/'textures'/('Transition_'+channel+'.png');im.filepath_raw=str(path);im.file_format='PNG';im.save()
    for m,out,old,temp in restore:
        m.node_tree.links.new(old,out.inputs[0])
        for nd in temp:m.node_tree.nodes.remove(nd)
    print('BAKE_END '+channel,flush=True);return {'role':channel,'path':str(path),'sha256':sha(path),'colorspace':im.colorspace_settings.name,'size':list(im.size)}
def final_mat(rows):
    m=bpy.data.materials.new('GroundTransition_BakedPBR');m.use_nodes=True;m.use_backface_culling=True;n=m.node_tree.nodes;n.clear();l=m.node_tree.links;bs=n.new('ShaderNodeBsdfPrincipled');out=n.new('ShaderNodeOutputMaterial');l.new(bs.outputs[0],out.inputs[0]);uv=n.new('ShaderNodeUVMap');uv.uv_map='BakeUV';tex={}
    for r in rows:
        im=bpy.data.images.load(r['path'],check_existing=False);im.colorspace_settings.name=r['colorspace'];t=n.new('ShaderNodeTexImage');t.image=im;t.label=r['role'];l.new(uv.outputs[0],t.inputs[0]);tex[r['role']]=t
    l.new(tex['BaseColor'].outputs[0],bs.inputs['Base Color']);split=n.new('ShaderNodeSeparateColor');l.new(tex['ORM'].outputs[0],split.inputs[0]);l.new(split.outputs['Green'],bs.inputs['Roughness']);l.new(split.outputs['Blue'],bs.inputs['Metallic']);normal=n.new('ShaderNodeNormalMap');normal.uv_map='BakeUV';l.new(tex['Normal'].outputs[0],normal.inputs['Color']);l.new(normal.outputs[0],bs.inputs['Normal']);bs.inputs['Emission Strength'].default_value=0
    return m
def main():
    start=time.time();assert not (OUT/'editable_source.blend').exists();assert sha(ATLAS)==ATLAS_SHA
    for sub in ['textures','evidence','source_inputs']:(OUT/sub).mkdir(exist_ok=True)
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    copied=OUT/'source_inputs/material_atlas_v1_UNEDITED.png';shutil.copyfile(ATLAS,copied);atlas=bpy.data.images.load(str(copied));atlas.colorspace_settings.name='sRGB'
    mats={k:author(k,atlas) for k in ['concrete','soil','chip','seal']};build(mats);report=geometry_report();studio()
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'editable_source.blend'),relative_remap=False);report['source_sha256']=sha(OUT/'editable_source.blend')
    proxy=proxy_and_uv();bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'uv_checkpoint.blend'),relative_remap=False);maps=[]
    for channel in ['BaseColor','ORM','Normal']:
        maps.append(bake(proxy,channel));(OUT/'bake_report.json').write_text(json.dumps({'maps':maps,'status':'CHECKPOINT_'+channel},indent=2))
    material=final_mat(maps);proxy.data.materials.clear();proxy.data.materials.append(material)
    for p in proxy.data.polygons:p.material_index=0
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'baked_source.blend'),relative_remap=False)
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath:im.filepath=bpy.path.relpath(bpy.path.abspath(im.filepath))
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'baked_source.blend'),relative_remap=False);bpy.ops.wm.open_mainfile(filepath=str(OUT/'baked_source.blend'))
    reopened=[]
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath:
            p=Path(bpy.path.abspath(im.filepath));assert p.exists();im.reload();pixel=tuple(im.pixels[:4]);assert len(pixel)==4 and im.has_data;reopened.append({'path':str(p),'sha256':sha(p),'colorspace':im.colorspace_settings.name})
    scene=bpy.context.scene;scene.cycles.samples=24;image=OUT/'evidence/transition_source_p1.png';scene.render.filepath=str(image);bpy.ops.render.render(write_still=True)
    report.update(status='SOURCE_BAKED_RENDERED_PENDING_VISUAL_REVIEW',maps=maps,reopened_images=reopened,source_unchanged=sha(OUT/'editable_source.blend')==report['source_sha256'],preview_sha256=sha(image),seconds=time.time()-start)
    (OUT/'production_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print(json.dumps({'pid':os.getpid(),'stage':'end','seconds':time.time()-start,'triangles':report['triangles']}),flush=True)
if __name__=='__main__':main()
