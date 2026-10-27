"""Yard connector P1: source-only, explicit metric UV. Requires Root engine lease."""
from pathlib import Path
import bpy,bmesh,json,hashlib,math,os,shutil,time
from mathutils import Vector
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[4]
OUT=Path(os.environ['YARD_PREVIEW_OUTPUT']).resolve()
assert OUT.is_relative_to(HERE)
PARTS=[]
BASE_CURVE=[(-6,.91),(-4.9,.94),(-3.8,.82),(-2.45,.89),(-1.5,1.06),(-.2,1.12),(1.15,.99),(2.25,1.08),(3.6,.90),(4.65,.82),(6,.91)]
def base_front(x):
    for (a,y),(b,z) in zip(BASE_CURVE,BASE_CURVE[1:]):
        if a<=x<=b:return y+(z-y)*(x-a)/(b-a)
    raise ValueError(x)
# Three finite damage events, not periodic noise. All cut inward into hardstand.
NOTCHES=[(-4.20,-4.16,-4.08,-4.04,.025),(-.82,-.77,-.65,-.59,.045),(3.05,3.12,3.29,3.34,.035)]
curve_points=dict(BASE_CURVE)
for xa,xb,xc,xd,depth in NOTCHES:
    for x,d in [(xa,0),(xb,depth),(xc,depth),(xd,0)]:curve_points[x]=base_front(x)-d
CURVE=sorted(curve_points.items())
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def dump(name,value):(OUT/name).write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def bg(x,y,z):return (x,-z,y)
def front(x):
    for (a,y),(b,z) in zip(CURVE,CURVE[1:]):
        if a<=x<=b:return y+(z-y)*(x-a)/(b-a)
    raise ValueError(x)
def clean(poly):
    out=[]
    for p in poly:
        if not out or math.dist(p,out[-1])>1e-9:out.append(tuple(p))
    if len(out)>1 and math.dist(out[0],out[-1])<1e-9:out.pop()
    changed=True
    while changed and len(out)>3:
        changed=False
        for i,b in enumerate(out):
            a=out[i-1];c=out[(i+1)%len(out)]
            cross=(b[0]-a[0])*(c[1]-b[1])-(b[1]-a[1])*(c[0]-b[0])
            between=(b[0]-a[0])*(c[0]-b[0])+(b[1]-a[1])*(c[1]-b[1])>=0
            if abs(cross)<1e-12 and between:
                out.pop(i);changed=True;break
    return out
def split(poly,axis,edge):
    sides=[[],[]]
    for a,b in zip(poly,poly[1:]+poly[:1]):
        da=a[axis]-edge;db=b[axis]-edge
        if da<=0:sides[0].append(a)
        if da>=0:sides[1].append(a)
        if (da<0 and db>0) or (da>0 and db<0):
            t=da/(da-db);p=tuple(a[i]+(b[i]-a[i])*t for i in range(2))
            sides[0].append(p);sides[1].append(p)
    return [clean(p) for p in sides]
def clip_rect(poly,rect):
    result=poly
    for axis,edge,keep in [(0,rect[0],1),(0,rect[1],0),(1,rect[2],1),(1,rect[3],0)]:
        result=split(result,axis,edge)[keep]
        if len(result)<3:return []
    return result
def minus_rect(poly,rect):
    remaining=poly;outside=[]
    for axis,edge,keep in [(0,rect[0],1),(0,rect[1],0),(1,rect[2],1),(1,rect[3],0)]:
        both=split(remaining,axis,edge)
        if len(both[1-keep])>=3:outside.append(both[1-keep])
        remaining=both[keep]
        if len(remaining)<3:break
    return outside
def area(poly):return abs(sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(poly,poly[1:]+poly[:1])))*.5
def extrude(name,poly,low,top,mat,group):
    poly=clean(poly)
    assert len(poly)>=3 and area(poly)>1e-8,name
    n=len(poly);verts=[bg(x,(y(x,z) if callable(y) else y),z) for y in [low,top] for x,z in poly]
    faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    me=bpy.data.meshes.new(name);me.from_pydata(verts,[],faces);me.update()
    bm=bmesh.new();bm.from_mesh(me);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free();me.update()
    uv=me.uv_layers.new(name='SourceMetric');uv.active_render=True
    for face in me.polygons:
        axis=max(range(3),key=lambda a:abs(face.normal[a]))
        for li in face.loop_indices:
            co=me.vertices[me.loops[li].vertex_index].co
            # Real metres. Top XY -> Godot XZ; sides use their own along/height coordinates.
            uv.data[li].uv=(co.x,-co.y) if axis==2 else ((-co.y,co.z) if axis==0 else (co.x,co.z))
    ob=bpy.data.objects.new(name,me);bpy.context.scene.collection.objects.link(ob)
    me.materials.append(mat);ob['editable_piece']=True;ob['runtime_group']=group;PARTS.append(ob)
    return ob
def box(name,x0,x1,z0,z1,lo,hi,mat,group):
    return extrude(name,[(x0,z0),(x1,z0),(x1,z1),(x0,z1)],lo,hi,mat,group)
class G:
    def __init__(self,name):
        self.m=bpy.data.materials.new(name);self.m.use_nodes=True;self.n=self.m.node_tree.nodes;self.n.clear();self.l=self.m.node_tree.links
        self.bs=self.n.new('ShaderNodeBsdfPrincipled');self.bs.inputs['Emission Strength'].default_value=0
        out=self.n.new('ShaderNodeOutputMaterial');self.l.new(self.bs.outputs[0],out.inputs[0])
        uv=self.n.new('ShaderNodeUVMap');uv.uv_map='SourceMetric';self.uv=uv.outputs[0]
        sep=self.n.new('ShaderNodeSeparateXYZ');self.l.new(self.uv,sep.inputs[0]);self.u=sep.outputs[0];self.v=sep.outputs[1]
    def put(self,x,s):
        if hasattr(x,'node'):self.l.new(x,s)
        else:s.default_value=(x,x,x,1) if isinstance(x,(int,float)) and s.type=='RGBA' else x
    def op(self,op,a,b=0):
        n=self.n.new('ShaderNodeMath');n.operation=op;self.put(a,n.inputs[0]);self.put(b,n.inputs[1]);return n.outputs[0]
    def mix(self,a,b,f,mode='MIX'):
        n=self.n.new('ShaderNodeMixRGB');n.blend_type=mode;self.put(f,n.inputs[0]);self.put(a,n.inputs[1]);self.put(b,n.inputs[2]);return n.outputs[0]
    def vec(self,u,v):
        n=self.n.new('ShaderNodeCombineXYZ');self.put(u,n.inputs[0]);self.put(v,n.inputs[1]);return n.outputs[0]
    def tex(self,image,vector):
        n=self.n.new('ShaderNodeTexImage');n.image=image;n.extension='REPEAT';self.l.new(vector,n.inputs[0]);return n.outputs['Color']
def atlas_sample(g,im,quadrant):
    # Preserve approved P2 metre scale. Crop one source quadrant, no image pixel manipulation.
    u=g.op('PINGPONG',g.op('ADD',g.op('DIVIDE',g.u,1.8),.17),1)
    v=g.op('PINGPONG',g.op('ADD',g.op('DIVIDE',g.v,1.8),.39),1)
    vec=g.vec(g.op('ADD',quadrant[0]+.008,g.op('MULTIPLY',u,.484)),g.op('ADD',quadrant[1]+.008,g.op('MULTIPLY',v,.484)))
    return g.tex(im,vec)
def concrete(im,repair=False):
    g=G('YC_Repair' if repair else 'YC_Concrete')
    base=atlas_sample(g,im,(.5,.5) if repair else (0,.5))
    cement=(.255,.236,.209,1) if not repair else (.19,.182,.166,1)
    # Half the full-field image contrast. Source UV stays explicit metres.
    def near(value,at,width):return g.op('MAXIMUM',0,g.op('SUBTRACT',1,g.op('DIVIDE',g.op('ABSOLUTE',g.op('SUBTRACT',value,at)),width)))
    edge=g.op('MAXIMUM',near(g.u,-2.4,.13),near(g.u,2.25,.13))
    edge=g.op('MAXIMUM',edge,g.op('MULTIPLY',near(g.v,-.45,.13),g.op('LESS_THAN',g.u,-2.4)))
    edge=g.op('MAXIMUM',edge,near(g.v,-2,.12))
    boundary=0
    for (xa,za),(xb,zb) in zip(CURVE,CURVE[1:]):
        mask=g.op('MULTIPLY',g.op('GREATER_THAN',g.u,xa),g.op('LESS_THAN',g.u,xb))
        value=g.op('ADD',za,g.op('MULTIPLY',g.op('SUBTRACT',g.u,xa),(zb-za)/(xb-xa)))
        boundary=g.op('ADD',boundary,g.op('MULTIPLY',mask,value))
    edge=g.op('MAXIMUM',edge,near(g.v,boundary,.16))
    for cx,cz,hx,hz in [(-.125,-1.025,.775,.465),(5.125,-.12,.475,.35)]:
        dx=g.op('SUBTRACT',g.op('ABSOLUTE',g.op('SUBTRACT',g.u,cx)),hx)
        dz=g.op('SUBTRACT',g.op('ABSOLUTE',g.op('SUBTRACT',g.v,cz)),hz)
        ring=g.op('MAXIMUM',0,g.op('SUBTRACT',1,g.op('DIVIDE',g.op('ABSOLUTE',g.op('MAXIMUM',dx,dz)),.12)))
        edge=g.op('MAXIMUM',edge,ring)
    geo=g.n.new('ShaderNodeNewGeometry');normal=g.n.new('ShaderNodeSeparateXYZ');g.l.new(geo.outputs['Normal'],normal.inputs[0])
    edge=g.op('MULTIPLY',edge,g.op('GREATER_THAN',normal.outputs['Z'],.7))
    weight=g.op('ADD',.26,g.op('MULTIPLY',edge,.21))
    tone=g.mix(cement,base,weight)
    tone=g.mix(tone,g.mix(tone,(.87,.88,.88,1),1,'MULTIPLY'),g.op('MULTIPLY',edge,.28))
    g.put(tone,g.bs.inputs['Base Color'])
    g.put(g.op('SUBTRACT',.88,g.op('MULTIPLY',edge,.07)),g.bs.inputs['Roughness']);g.bs.inputs['Metallic'].default_value=0
    noise=g.n.new('ShaderNodeTexNoise');g.l.new(g.uv,noise.inputs['Vector']);noise.inputs['Scale'].default_value=70;noise.inputs['Detail'].default_value=1
    bump=g.n.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.18;bump.inputs['Distance'].default_value=.0005
    g.l.new(noise.outputs['Fac'],bump.inputs['Height']);g.l.new(bump.outputs[0],g.bs.inputs['Normal'])
    return g.m
def soil(images):
    g=G('YC_CompactedBase')
    coord=g.vec(g.op('DIVIDE',g.u,2.53),g.op('DIVIDE',g.v,2.53))
    color=g.tex(images['sand_color'],coord)
    sat=g.n.new('ShaderNodeHueSaturation');sat.inputs['Saturation'].default_value=.35;sat.inputs['Value'].default_value=.88;g.l.new(color,sat.inputs['Color'])
    # Quiet mineral binder. No displaced scan and no duplicated macro normal.
    color=g.mix((.145,.124,.099,1),sat.outputs[0],.60)
    # Broad drying near the actual off-centre inlet; continuous multiplier, no painted shadow.
    du=g.op('DIVIDE',g.op('SUBTRACT',g.u,1.1),1.8);dv=g.op('DIVIDE',g.op('SUBTRACT',g.v,1.38),.60)
    wet=g.op('MAXIMUM',0,g.op('SUBTRACT',1,g.op('ADD',g.op('MULTIPLY',du,du),g.op('MULTIPLY',dv,dv))))
    # One broad cause-based drying/compaction field at the unchanged inlet.
    # No global cloud layer; original CC0 texture remains the material information.
    color=g.mix(color,g.mix(color,(.52,.60,.66,1),1,'MULTIPLY'),g.op('MULTIPLY',wet,.64))
    g.put(color,g.bs.inputs['Base Color'])
    rough=g.tex(images['sand_rough'],coord);g.put(g.op('SUBTRACT',g.op('ADD',.78,g.op('MULTIPLY',rough,.16)),g.op('MULTIPLY',wet,.15)),g.bs.inputs['Roughness'])
    n=g.n.new('ShaderNodeNormalMap');n.uv_map='SourceMetric';n.inputs['Strength'].default_value=.32;g.l.new(g.tex(images['sand_normal'],coord),n.inputs['Color']);g.l.new(n.outputs[0],g.bs.inputs['Normal'])
    return g.m
def solid(name,color,rough,metal=0):
    g=G(name);g.bs.inputs['Base Color'].default_value=(*color,1);g.bs.inputs['Roughness'].default_value=rough;g.bs.inputs['Metallic'].default_value=metal;return g.m
def load_inputs():
    inputs=json.loads((HERE/'inputs.json').read_text(encoding='utf-8'));imgs={};rows=[]
    dest=OUT/'source_inputs';dest.mkdir()
    for row in inputs['images']:
        p=ROOT/row['path'];assert sha(p)==row['sha256'],str(p)
        target=dest/p.name;shutil.copyfile(p,target);assert sha(target)==row['sha256']
        im=bpy.data.images.load(str(target),check_existing=False);im.colorspace_settings.name=row['colorspace']
        pixel=list(im.pixels[:4]);assert len(pixel)==4 and all(math.isfinite(v) for v in pixel) and im.has_data
        assert tuple(im.size)==tuple(row['size']),str(p)
        imgs[row['role']]=im;rows.append(dict(row,local=str(target),pixel=pixel))
    return imgs,rows
def build(images):
    m=concrete(images['atlas']);repair=concrete(images['atlas'],True);base=soil(images)
    grout=solid('YC_Seal',(.033,.037,.033),.95);bed=solid('YC_BuriedBase',(.105,.098,.084),.97)
    teal=solid('YC_TealTrim',(.045,.098,.10),.63,.15);steel=solid('YC_GrateSteel',(.22,.24,.24),.56,.88)
    box('BuriedContinuousSubstrate',-6,6,-2,2,-.18,-.04,bed,'GroundBody')
    # A single continuous jagged material boundary, rather than repeated 6m decorative tiles.
    full_hard=[(-5.99,-1.99),(5.99,-1.99),(5.99,front(5.99))]+[(x,z) for x,z in reversed(CURVE) if -5.99<x<5.99]+[(-5.99,front(-5.99))]
    hard=[(-5.99,-1.99),(5.99,-1.99),(5.99,front(5.99)-.025)]+[(x,z-.025) for x,z in reversed(CURVE) if -5.99<x<5.99]+[(-5.99,front(-5.99)-.025)]
    slabs=[(-5.99,-2.41,-1.99,-.46),(-5.99,-2.41,-.44,2),(-2.39,2.24,-1.99,2),(2.26,5.99,-1.99,2)]
    repairs=[(-.90,.65,-1.49,-.56),(4.65,5.60,-.47,.23)]
    for i,r in enumerate(slabs):
        polys=[clip_rect(hard,r)]
        for patch in repairs:polys=[p for q in polys for p in minus_rect(q,patch)]
        for j,p in enumerate(polys):
            if len(p)>=3 and area(p)>1e-8:extrude('Hardstand_%02d_%02d'%(i,j),p,-.04,0,m,'GroundBody')
    for i,r in enumerate(repairs):
        box('RepairSeal_%02d'%i,*r,-.04,-.008,grout,'GroundBody')
        box('RepairPour_%02d'%i,r[0]+.01,r[1]-.01,r[2]+.01,r[3]-.01,-.04,0,repair,'GroundBody')
    # Exact gaps and recessed seal. Foundation is not a coplanar cover.
    for i,(x0,x1) in enumerate([(-2.41,-2.39),(2.24,2.26)]):
        extrude('LongJoint_%d'%i,clip_rect(full_hard,(x0,x1,-1.99,2)),-.04,-.008,grout,'GroundBody')
    box('StaggeredTJoint',-5.99,-2.41,-.46,-.44,-.04,-.008,grout,'GroundBody')
    box('CourtHalfSeal',-6,6,-2,-1.99,-.04,-.008,grout,'GroundBody')
    for i,(a,b) in enumerate([(-6,-5.99),(5.99,6)]):
        extrude('EndHalfSeal_%d'%i,[(a,-1.99),(b,-1.99),(b,front(b)),(a,front(a))],-.04,-.008,grout,'GroundBody')
    # A real 25mm collar with a 4mm compressed front, each segment planar.
    for k,((xa,za),(xb,zb)) in enumerate(zip(CURVE,CURVE[1:])):
        band=[(xa,za-.025),(xb,zb-.025),(xb,zb),(xa,za)]
        for j,(left,right) in enumerate([(-5.99,-2.41),(-2.39,2.24),(2.26,5.99)]):
            p=clip_rect(band,(left,right,-2,2))
            if len(p)>=3 and area(p)>1e-8:
                extrude('CompressedEdge_%02d_%d'%(k,j),p,-.04,lambda x,z:-.004*min(1,max(0,(z-(front(x)-.025))/.025)),m,'GroundBody')
    compact=CURVE+[(6,2),(-6,2)]
    opening=(0,2.2,1.30,1.46)
    for i,p in enumerate(minus_rect(compact,opening)):
        if area(p)>1e-8:extrude('CompactedBase_%02d'%i,p,-.04,0,base,'GroundBody')
    box('InletClosedBottom',0,2.2,1.30,1.46,-.04,-.015,grout,'DrainHardware')
    for name,r in [('Front',(0,2.2,1.30,1.318)),('Back',(0,2.2,1.442,1.46)),('Left',(0,.024,1.318,1.442)),('Right',(2.176,2.2,1.318,1.442))]:
        box('InletFrame_'+name,*r,-.015,0,teal,'DrainHardware')
    for i in range(36):
        x=.045+i*.060
        box('GrateBar_%02d'%i,x,x+.014,1.318,1.442,-.014,-.001,steel,'DrainHardware')
def check_geometry():
    records=[];points=[]
    for ob in PARTS:
        me=ob.data;me.calc_loop_triangles();bm=bmesh.new();bm.from_mesh(me)
        bad=sum(not e.is_manifold for e in bm.edges);bm.free()
        assert bad==0,ob.name
        for t in me.loop_triangles:
            a,b,c=[me.vertices[i].co for i in t.vertices];assert (b-a).cross(c-a).length>1e-10,ob.name
        for uv in me.uv_layers['SourceMetric'].data:assert all(math.isfinite(v) for v in uv.uv)
        points.extend((v.co.x,v.co.z,-v.co.y) for v in me.vertices)
        records.append({'name':ob.name,'triangles':len(me.loop_triangles),'nonmanifold_edges':bad,'identity':all(abs(ob.matrix_world[r][c]-(1 if r==c else 0))<1e-8 for r in range(4) for c in range(4))})
    bounds=[[min(p[i] for p in points) for i in range(3)],[max(p[i] for p in points) for i in range(3)]]
    expected=[[-6,-.18,-2],[6,0,2]]
    assert all(abs(bounds[k][a]-expected[k][a])<=1e-5 for k in range(2) for a in range(3))
    triangles=sum(r['triangles'] for r in records);assert triangles<=8000,triangles
    return {'parts':records,'triangles':triangles,'bounds_godot':bounds,'revision':'2, material and local edge only; same 12x4/inlet/camera', 'checks':'individual closed meshes, nonzero actual triangles, finite metricUV, exact module bounds; internal structural contacts intentionally allowed','limits':'Not full self-intersection, actual engine collision or art acceptance; no runtime world installed.'}
def studio():
    scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.render.threads_mode='FIXED';scene.render.threads=2
    scene.cycles.samples=24;scene.cycles.use_denoising=True
    scene.render.resolution_x=1536;scene.render.resolution_y=1024;scene.render.resolution_percentage=100
    scene.view_settings.view_transform='Standard';scene.view_settings.look='None';scene.view_settings.exposure=0;scene.view_settings.gamma=1
    world=bpy.data.worlds.new('NeutralStudio');scene.world=world;world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.35,.37,.39,1);world.node_tree.nodes['Background'].inputs[1].default_value=.35
    for name,pos,power,size in [('Key',(-3,-6,9),1100,9),('Fill',(5,4,6),500,7)]:
        light=bpy.data.lights.new(name,'AREA');light.energy=power;light.shape='DISK';light.size=size
        ob=bpy.data.objects.new(name,light);scene.collection.objects.link(ob);ob.location=pos;ob.rotation_euler=(Vector((0,0,0))-ob.location).to_track_quat('-Z','Y').to_euler()
    data=bpy.data.cameras.new('ReferenceOblique');cam=bpy.data.objects.new('ReferenceOblique',data);scene.collection.objects.link(cam)
    cam.location=(9,-14,24);cam.rotation_euler=(-cam.location).to_track_quat('-Z','Y').to_euler();data.type='ORTHO';data.ortho_scale=14.5;scene.camera=cam
    bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.185));floor=bpy.context.object;floor.name='REVIEW_ONLY_Studio';floor.data.materials.append(solid('StudioGray',(.18,.19,.20),1))
def main():
    start=time.time();bpy.ops.wm.read_factory_settings(use_empty=True)
    images,dependencies=load_inputs();build(images);report=check_geometry();studio()
    dump('geometry.json',report)
    source=OUT/'yard_connector_editable.blend'
    bpy.ops.wm.save_as_mainfile(filepath=str(source),relative_remap=False)
    for im in images.values():im.filepath=bpy.path.relpath(str(Path(bpy.path.abspath(im.filepath)).resolve()))
    bpy.ops.wm.save_as_mainfile(filepath=str(source),relative_remap=False)
    expected={Path(r['local']).name:r for r in dependencies};bpy.ops.wm.open_mainfile(filepath=str(source))
    verified=[]
    for im in bpy.data.images:
        if im.source!='FILE':continue
        path=Path(bpy.path.abspath(im.filepath)).resolve();row=expected[path.name]
        assert path.is_file() and sha(path)==row['sha256']
        im.reload();pixel=list(im.pixels[:4]);assert len(pixel)==4 and im.has_data and all(math.isfinite(v) for v in pixel)
        verified.append({'file':str(path),'sha256':sha(path),'size':list(im.size),'colorspace':im.colorspace_settings.name,'pixel':pixel})
    assert len(verified)==4
    paths=[]
    for name,scale in [('01-single-reference-oblique.png',14.5),('02-single-26m-readability.png',26)]:
        scene=bpy.context.scene;scene.camera.data.ortho_scale=scale;path=OUT/name;scene.render.filepath=str(path);bpy.ops.render.render(write_still=True)
        assert path.exists();paths.append({'path':str(path),'sha256':sha(path)})
    dump('result.json',{'status':'SOURCE_RENDERED_PENDING_PERSONAL_REVIEW','source':str(source),'source_sha256':sha(source),'elapsed_seconds':time.time()-start,'pid':os.getpid(),'geometry':report,'images_reopened':verified,'renders':paths,'scope':'one isolated new source module; no bake/export/engine/world/collision change'})
if __name__=='__main__':main()

