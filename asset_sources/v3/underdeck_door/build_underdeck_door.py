"""I-B sliding flood door, authored geometry and UV PBR, Blender CPU2.

All dimensions below are Godot metres (X right, Y up, Z front). The source
conversion (x,-z,y) is a proper rotation, never a negative-scale mirror.
The continuous closed PanelBody is independent of decorative overhead hangers.
No reference pixels are projected onto geometry. No high/low bake is claimed.
"""
from pathlib import Path
import bpy, bmesh, math, json, hashlib, struct, zlib, time, os
import numpy as np
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[3]
SRC=Path(__file__).resolve().parent
OUT=ROOT/'assets/v3/underdeck_door'
TEX=SRC/'textures'; EV=SRC/'evidence'
for d in (SRC,OUT,TEX,EV): d.mkdir(parents=True,exist_ok=True)
(SRC/'.gdignore').write_text('',encoding='utf-8')
t0=time.time()
print('DOOR_BUILD_START',os.getpid(),bpy.app.version_string,flush=True)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
scene=bpy.context.scene
scene.unit_settings.system='METRIC'; scene.unit_settings.scale_length=1
coll=bpy.data.collections.new('Editable_UnderdeckDoor'); scene.collection.children.link(coll)
parts=[]; groups={}; materials={}
def bp(p): return Vector((p[0],-p[2],p[1]))
def gp(p): return [float(p[0]),float(p[2]),float(-p[1])]
def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def png(path,arr):
    a=np.clip(arr*255+.5,0,255).astype(np.uint8)
    if a.ndim==2: a=np.repeat(a[:,:,None],3,axis=2)
    h,w,_=a.shape
    def ch(t,d): return struct.pack('>I',len(d))+t+d+struct.pack('>I',zlib.crc32(t+d)&0xffffffff)
    # Authoring arrays use UV v increasing upwards; PNG rows start at the top.
    # Reverse rows exactly once, so upper-joint rust flows DOWN on the mesh and
    # the foot-zone salt remains at the foot. Values remain sRGB, no re-encoding.
    raw=b''.join(b'\0'+row.tobytes() for row in a[::-1])
    path.write_bytes(b'\x89PNG\r\n\x1a\n'+ch(b'IHDR',struct.pack('>IIBBBBB',w,h,8,2,0,0,0))+ch(b'IDAT',zlib.compress(raw,6))+ch(b'IEND',b''))

def surface_maps(kind,n):
    v,u=np.mgrid[0:1:complex(n),0:1:complex(n)]
    rng=np.random.default_rng({'paint':714,'silver':729,'steel':743,'safety':751,'lens':760}[kind])
    fine=rng.random((n,n))-.5
    def field(cells):
        grid=rng.random((cells+1,cells+1))
        xx=u*cells;yy=v*cells
        ix=np.minimum(xx.astype(int),cells-1);iy=np.minimum(yy.astype(int),cells-1)
        fx=xx-ix;fy=yy-iy;fx=fx*fx*(3-2*fx);fy=fy*fy*(3-2*fy)
        return ((grid[iy,ix]*(1-fx)+grid[iy,ix+1]*fx)*(1-fy)+(grid[iy+1,ix]*(1-fx)+grid[iy+1,ix+1]*fx)*fy)-.5
    broad=field(7)
    mottled=field(63)*.70+field(137)*.30
    edge=np.minimum.reduce((u,1-u,v,1-v))
    irregular=field(87)
    wear=np.clip((.012+irregular*.035-edge)/.010,0,1)
    rust=np.zeros_like(u)
    # The two prominent panel flows begin at ACTUAL lower hanger fasteners:
    # Godot (-1.312,1.42) and (1.312,1.42). One weaker flow starts at the real
    # lower-sheet seam y=-.18. No regularly spaced anonymous brown bars.
    drift=field(41);breakup=np.clip(.76+field(117)*.85+field(29)*.30,.28,1)
    anchors=[((-1.312+1.9)/3.8,(1.42+1.6)/3.2,.285,.0065),
             ((1.312+1.9)/3.8,(1.42+1.6)/3.2,.185,.0040),
             ((-.95+1.9)/3.8,(-.18+1.6)/3.2,.155,.0035)]
    for idx,(x,top,length,width) in enumerate(anchors):
        t=(top-v)/length;inside=(t>0)&(t<1);d=np.clip(t,0,1)
        centre=x+(.0025*np.sin(d*7+idx)+.0015*np.sin(d*19))*d
        taper=width*(.25+.75*(1-d))*(.86+.28*drift)
        core=np.exp(-((u-centre)/taper)**2)
        fade=np.minimum(d/.045,1)**.8*(1-d)**1.65
        rust+=core*fade*breakup*inside
        # A faint, shorter side rivulet on one source; does not create a new
        # unconnected top stamp. It branches only after the flow has begun.
        if idx==0:
            branch=centre+.008*np.clip((d-.22)/.42,0,1)
            rust+=.22*np.exp(-((u-branch)/(taper*.43))**2)*fade*inside*np.clip((d-.22)*9,0,1)*np.clip((.78-d)*8,0,1)
    lower=np.clip((.14+field(31)*.10-v)/.14,0,1)
    if kind=='paint':
        c=np.ones((n,n,3))*[.105,.190,.210]
        c*=1+.035*broad[:,:,None]+.012*fine[:,:,None]
        chip=wear*(.12+.88*((mottled>.06)&(irregular>-.10)))
        c=c*(1-chip[:,:,None]*.86)+np.array([.48,.49,.44])*chip[:,:,None]*.86
        oxid=np.clip(rust*.86+wear*.24,0,.86)
        c=c*(1-oxid[:,:,None])+np.array([.34,.175,.075])*oxid[:,:,None]
        rough=.62+.12*oxid+.06*wear+.018*broad; metal=np.full_like(u,.10)
        height=wear*.10+oxid*.045+fine*.003
    elif kind=='silver':
        c=np.ones((n,n,3))*[.475,.495,.475]
        c*=1+.09*broad[:,:,None]+.11*mottled[:,:,None]+.008*fine[:,:,None]
        # Sparse dirty water flows under upper seam, salt predominantly at foot.
        stain=np.clip(rust*.63+lower*.30,0,.70)
        c=c*(1-stain[:,:,None])+np.array([.28,.205,.13])*stain[:,:,None]
        salt=lower*np.clip((mottled+.07)*3.2,0,1)*.74
        c=c*(1-salt[:,:,None])+np.array([.72,.74,.68])*salt[:,:,None]
        rough=.66+.10*stain+.07*salt+.035*mottled
        metal=np.clip(.53-.23*stain-.30*salt,.1,.65)
        height=.012*mottled+.023*salt+.004*fine
    elif kind=='steel':
        c=np.ones((n,n,3))*[.44,.47,.465]
        brush=.012*np.sin(u*850)+.008*fine
        c*=1+.025*broad[:,:,None]+brush[:,:,None]
        ox=wear*.22
        c=c*(1-ox[:,:,None])+np.array([.31,.24,.17])*ox[:,:,None]
        rough=.32+.13*ox+.04*broad; metal=np.full_like(u,.78)
        height=brush*.045
    elif kind=='safety':
        stripes=(((u*17+v*.60)%1)<.31)&((u<.22)|(u>.73))
        c=np.empty((n,n,3));c[:]=[.68,.49,.18];c[stripes]=[.12,.16,.17]
        # Abrasion is concentrated at the actual bottom contact edge and two
        # low corners; the distant yellow/black warning silhouette stays quiet.
        foot=np.clip((.32+field(23)*.18-v)/.32,0,1)
        chips=np.clip((mottled-.015)*7,0,1)
        corner=(np.exp(-((u-.045)/.06)**2)+np.exp(-((u-.955)/.045)**2))*np.clip((.78-v)/.78,0,1)
        loss=np.clip(foot*(.30+.62*chips)+wear*.22+corner*.35,0,.85)
        loss=np.clip(loss,0,.8)
        c=c*(1-loss[:,:,None])+np.array([.40,.40,.34])*loss[:,:,None]
        c*=1+.035*broad[:,:,None]
        rough=.72+.10*loss;metal=np.full_like(u,.12);height=loss*.045
    else:
        c=np.ones((n,n,3))*[.79,.81,.80]
        c*=.96+.04*np.cos((v-.5)*math.pi)[:,:,None]
        rough=np.full_like(u,.34);metal=np.zeros_like(u);height=np.zeros_like(u)
    gy,gx=np.gradient(height)
    normal=np.dstack((-gx*12,-gy*12,np.ones_like(u)))
    normal/=np.linalg.norm(normal,axis=2)[:,:,None]
    return {'BaseColor':np.clip(c,0,1),'Roughness':np.clip(rough,.15,.94),'Metallic':np.clip(metal,0,1),'Normal':normal*.5+.5}

for name,kind,n in [('UD_PetrolPaint','paint',1024),('UD_Galvanized','silver',2048),('UD_BareSteel','steel',1024),('UD_SafetyBand','safety',1024),('UD_StatusLens','lens',512)]:
    mat=bpy.data.materials.new(name);mat.use_nodes=True
    nodes=mat.node_tree.nodes;links=mat.node_tree.links
    bs=next((n for n in nodes if n.type=='BSDF_PRINCIPLED'),None)
    if bs is None:bs=nodes.new('ShaderNodeBsdfPrincipled')
    output=next((n for n in nodes if n.type=='OUTPUT_MATERIAL'),None)
    if output is None:output=nodes.new('ShaderNodeOutputMaterial')
    links.new(bs.outputs['BSDF'],output.inputs['Surface'])
    uv=nodes.new('ShaderNodeUVMap');uv.uv_map='SurfaceUV'
    for role,a in surface_maps(kind,n).items():
        path=TEX/(name+'_'+role+'.png');png(path,a)
        im=bpy.data.images.load(str(path),check_existing=False)
        im.colorspace_settings.name='sRGB' if role=='BaseColor' else 'Non-Color'
        im.filepath='//textures/'+path.name
        tex=nodes.new('ShaderNodeTexImage');tex.image=im;tex.label=role;tex.extension='EXTEND'
        links.new(uv.outputs['UV'],tex.inputs['Vector'])
        if role=='Normal':
            node=nodes.new('ShaderNodeNormalMap');node.inputs['Strength'].default_value=.42
            links.new(tex.outputs['Color'],node.inputs['Color']);links.new(node.outputs['Normal'],bs.inputs['Normal'])
        else: links.new(tex.outputs['Color'],bs.inputs[{'BaseColor':'Base Color','Roughness':'Roughness','Metallic':'Metallic'}[role]])
    materials[name]=mat

def register(o,group):
    for c in list(o.users_collection):c.objects.unlink(o)
    coll.objects.link(o);parts.append(o);groups.setdefault(group,[]).append(o)
    o['runtime_group']=group
    return o
def normals(o):
    bm=bmesh.new();bm.from_mesh(o.data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(o.data);bm.free()
def add_uv(o,mode='local'):
    me=o.data
    while me.uv_layers:me.uv_layers.remove(me.uv_layers[0])
    me.uv_layers.new(name='SurfaceUV');me.uv_layers.active_index=0;me.uv_layers['SurfaceUV'].active_render=True
    layer=me.uv_layers['SurfaceUV']
    coords=[Vector(gp(o.matrix_world@v.co)) for v in me.vertices]
    lo=[min(p[k] for p in coords) for k in range(3)];hi=[max(p[k] for p in coords) for k in range(3)]
    for f in me.polygons:
        normal=Vector(gp(o.matrix_world.to_3x3()@f.normal))
        axes=[k for k in range(3) if k!=max(range(3),key=lambda k:abs(normal[k]))]
        matname=me.materials[f.material_index].name if me.materials else ''
        for li in f.loop_indices:
            p=coords[me.loops[li].vertex_index]
            if mode=='panel' and abs(normal.z)>.2:
                if matname=='UD_SafetyBand':u=(p.x+1.70)/3.4;v=(p.y+1.60)/.28
                else:u=(p.x+1.9)/3.8;v=(p.y+1.6)/3.2
                if normal.z<0:u=1-u
            else:
                u=(p[axes[0]]-lo[axes[0]])/(hi[axes[0]]-lo[axes[0]] or 1)
                v=(p[axes[1]]-lo[axes[1]])/(hi[axes[1]]-lo[axes[1]] or 1)
            layer.data[li].uv=(max(.002,min(.998,u)),max(.002,min(.998,v)))
def bevel(o,width=.008,segments=2):
    if width:
        m=o.modifiers.new('Machined_edge_radius','BEVEL');m.width=width;m.segments=segments;m.limit_method='ANGLE';m.angle_limit=.38
        m.profile=.5
    m=o.modifiers.new('Weighted_surface_normals','WEIGHTED_NORMAL');m.keep_sharp=True;m.weight=50
def mesh_obj(name,vs,fs,mat,group):
    me=bpy.data.meshes.new(name+'_EditableMesh');me.from_pydata([bp(v) for v in vs],[],fs);me.update()
    o=bpy.data.objects.new(name,me);coll.objects.link(o)
    o.data.materials.append(materials[mat]);register(o,group);normals(o);return o
def box(name,at,size,mat,group,edge=.006):
    bpy.ops.mesh.primitive_cube_add(size=1,location=bp(at));o=bpy.context.object;o.name=name
    o.dimensions=Vector((size[0],size[2],size[1]));bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    o.data.materials.append(materials[mat]);register(o,group);add_uv(o);bevel(o,edge);return o
def cylinder(name,at,radius,depth,mat,group,segments=20,edge=.003):
    bpy.ops.mesh.primitive_cylinder_add(vertices=segments,radius=radius,depth=depth,location=bp(at))
    o=bpy.context.object;o.name=name;o.rotation_euler=(math.pi/2,0,0)
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    o.data.materials.append(materials[mat]);register(o,group);add_uv(o);bevel(o,edge,1)
    for f in o.data.polygons:f.use_smooth=len(f.vertices)==4
    return o
def plate(name,outline,z0,z1,mat,group,edge=.005):
    n=len(outline);vs=[(x,y,z) for z in (z0,z1) for x,y in outline]
    fs=[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]
    for i in range(n):j=(i+1)%n;fs.append((i,j,j+n,i+n))
    o=mesh_obj(name,vs,fs,mat,group);add_uv(o);bevel(o,edge);return o
def bolt(name,x,y,z,group,front=1,r=.028):
    cylinder(name+'_Washer',(x,y,z),r*1.35,.004,'UD_BareSteel',group,16,.001)
    cylinder(name+'_Hex',(x,y,z+front*.005),r,.010,'UD_BareSteel',group,6,.0015)

# A single manifold solid with integrated recessed faces. No stacked hidden box
# or face plane is used to pretend that a see-through visual blocks the opening.
xs=sorted(set([-1.90,-1.87,-1.70,-1.675,-1.64,1.64,1.675,1.70,1.87,1.90]))
ys=sorted(set([-1.60,-1.57,-1.34,-1.30,-1.27,-1.245,-.205,-.18,-.155,-.055,-.03,-.005,1.275,1.30,1.325,1.57,1.60]))
rects=[(-1.70,1.70,-1.27,-.18),(-1.70,1.70,-.03,1.30)]
def face_height(x,y):
    # Raised continuous perimeter hems reach the exact +/-0.15 envelope.
    d=min(1.9-abs(x),1.6-abs(y))
    if d<.030001:return .15-.022*max(0,d)/.03
    for x0,x1,y0,y1 in rects:
        if x0<=x<=x1 and y0<=y<=y1:
            a=min(x-x0,x1-x,y-y0,y1-y)
            return .105+.023*(1-min(max(a,0)/.025,1))
    return .128
nx=len(xs);ny=len(ys);n=nx*ny
vs=[(x,y,sign*face_height(x,y)) for sign in (1,-1) for y in ys for x in xs]
fs=[];mi=[]
for side in range(2):
    for j in range(ny-1):
        for i in range(nx-1):
            a=side*n+j*nx+i;q=(a,a+1,a+nx+1,a+nx)
            fs.append(q if side==0 else q[::-1])
            x=(xs[i]+xs[i+1])/2;y=(ys[j]+ys[j+1])/2
            silver=any(x0<x<x1 and y0<y<y1 for x0,x1,y0,y1 in rects)
            hazard=-1.57<y< -1.34 and abs(x)<1.70
            mi.append(2 if hazard else 1 if silver else 0)
boundary=list(range(nx))+[j*nx+nx-1 for j in range(1,ny)]+[(ny-1)*nx+i for i in range(nx-2,-1,-1)]+[j*nx for j in range(ny-2,0,-1)]
for k,a in enumerate(boundary):
    b=boundary[(k+1)%len(boundary)];fs.append((a,b,b+n,a+n));mi.append(0)
body=mesh_obj('PanelBody',vs,fs,'UD_PetrolPaint','PanelBody')
body.data.materials.append(materials['UD_Galvanized']);body.data.materials.append(materials['UD_SafetyBand'])
for f,m in zip(body.data.polygons,mi):f.material_index=m
add_uv(body,'panel')
# Do not bevel this continuous grid: the explicit hems/inset shoulders already
# express radius-scale engineering, and its watertight coordinates are the lock.
body['continuous_solid']='single closed manifold; no apertures; exact outer 3.8 x 3.2 x .30m'

# Short edge reinforcement straps and plausible fastener spacing, on both faces.
for side in (1,-1):
    lab='Front' if side==1 else 'Rear'
    for x in (-1.80,1.80):
        box(lab+'_EndStrap_'+str(x),(x,0,side*.134),(.13,3.03,.012),'UD_PetrolPaint','PanelHardware',.004)
        for y in (-1.46,-1.27,1.21,1.45):bolt(lab+'_FrameBolt_%s_%s'%(x,y),x,y,side*.140,'PanelHardware',side,.023)
    # Actual small triangular gussets at four inner sheet corners, not broad
    # uniformly tiled plates. The two galvanized fields remain quiet and large.
    for x,sgn in [(-1.64,1),(1.64,-1)]:
        for y,dy in [(1.27,-1),(-1.24,1)]:
            outline=[(x,y),(x+sgn*.15,y),(x,y+dy*.15)]
            plate(lab+'_CornerGusset_%s_%s'%(x,y),outline,side*.112,side*.121,'UD_PetrolPaint','PanelHardware',.002)
    # Lower-right manual release and access cover. Rear is finished too, with
    # its own maintenance plate rather than transparent/single-sided geometry.
    cx=1.08 if side==1 else -.98
    box(lab+'_ServiceCover',(cx,-.70,side*.117),(.43,.80,.020),'UD_Galvanized','PanelHardware',.014)
    for dx in (-.17,.17):
        for dy in (-.34,.34):bolt(lab+'_CoverBolt_%s_%s'%(dx,dy),cx+dx,-.7+dy,side*.132,'PanelHardware',side,.021)
    hx=1.48 if side==1 else -1.45
    box(lab+'_ReleaseWell',(hx,-.70,side*.115),(.23,.61,.018),'UD_PetrolPaint','PanelHardware',.015)
    box(lab+'_ReleaseDarkInset',(hx,-.70,side*.126),(.115,.43,.012),'UD_BareSteel','PanelHardware',.009)
    box(lab+'_FlushReleaseHandle',(hx,-.70,side*.140),(.036,.31,.016),'UD_BareSteel','PanelHardware',.006)
    for y in (-.88,-.52):bolt(lab+'_HandleScrew_'+str(y),hx,y,side*.135,'PanelHardware',side,.012)

# Two visibly engaged carriage wheels. Their supporting track is stationary;
# all these pieces move with the panel. No rotation animation is exported.
wheel_centres=[]
for i,x in enumerate((-1.25,1.25)):
    wheel_centres.append([x,1.88,-.025])
    cylinder('HangerWheel_%02d'%i,(x,1.88,-.025),.145,.100,'UD_BareSteel','MovingHangers',40,.004)
    cylinder('WheelFrontCollar_%02d'%i,(x,1.88,.032),.112,.016,'UD_BareSteel','MovingHangers',32,.003)
    outline=[(x-.105,1.35),(x+.105,1.35),(x+.105,1.91),(x+.075,2.01),(x,2.04),(x-.075,2.01),(x-.105,1.91)]
    plate('HangerLoadStrap_%02d'%i,outline,.057,.106,'UD_PetrolPaint','MovingHangers',.009)
    cylinder('HangerAxle_%02d'%i,(x,1.88,.123),.053,.044,'UD_BareSteel','MovingHangers',20,.004)
    for dx in (-.062,.062):
        for y in (1.42,1.60):bolt('HangerFastener_%02d_%s_%s'%(i,dx,y),x+dx,y,.115,'MovingHangers',1,.021)

# 8.30m fixed C-channel, silver running surface exactly tangent to wheel bottom.
box('RailWeb',(2.10,1.88,-.15),(8.30,.36,.06),'UD_PetrolPaint','FixedRail',.005)
box('LowerChannelLip',(2.10,1.6925,-.03),(8.30,.065,.30),'UD_PetrolPaint','FixedRail',.003)
box('SilverRunningStrip',(2.10,1.730,-.025),(8.18,.010,.17),'UD_BareSteel','FixedRail',.0015)
box('UpperChannelLip',(2.10,2.0725,-.03),(8.30,.055,.30),'UD_PetrolPaint','FixedRail',.004)
for i,x in enumerate((-1.98,2.10,6.18)):
    box('WallRailClip_%02d'%i,(x,1.89,.155),(.13,.39,.05),'UD_PetrolPaint','StopAndGuides',.005)
    for y in (1.76,2.02):bolt('FixedClipBolt_%02d_%s'%(i,y),x,y,.187,'StopAndGuides',1,.025)
for i,x in enumerate((-1.97,6.17)):
    box('EndStop_%02d'%i,(x,1.87,-.015),(.13,.34,.23),'UD_BareSteel','StopAndGuides',.008)
    box('EndStopBuffer_%02d'%i,(x+(.08 if i==0 else -.08),1.88,-.025),(.03,.18,.14),'UD_PetrolPaint','StopAndGuides',.005)
# Fixed neutral state window, deliberately separate from door and wheel metal.
box('StatusHousing',(0,1.945,.192),(1.08,.235,.076),'UD_PetrolPaint','StopAndGuides',.014)
box('StatusLens',(0,1.95,.235),(1.0,.18,.020),'UD_StatusLens','StatusLens',.008)

# Authoring parents allow a source-side open pose without deforming geometry.
author_roots={}
for asset,groupnames in [('Panel',['PanelBody','PanelHardware','MovingHangers']),('Rail',['FixedRail','StopAndGuides','StatusLens'])]:
    parent=bpy.data.objects.new('SOURCE_'+asset,None);coll.objects.link(parent);author_roots[asset]=parent
    for gn in groupnames:
        for o in groups[gn]:mw=o.matrix_world.copy();o.parent=parent;o.matrix_world=mw

# Neutral, deliberately nondramatic studio. It is not a game world or screenshot.
world=bpy.data.worlds.new('Door_NeutralStudio');scene.world=world;world.use_nodes=True
background=next((n for n in world.node_tree.nodes if n.type=='BACKGROUND'),None)
if background is None:
    background=world.node_tree.nodes.new('ShaderNodeBackground')
    world_out=world.node_tree.nodes.new('ShaderNodeOutputWorld')
    world.node_tree.links.new(background.outputs['Background'],world_out.inputs['Surface'])
background.inputs[0].default_value=(.28,.31,.34,1)
background.inputs[1].default_value=.55
def area(name,at,power,size,color):
    data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size;data.color=color
    ob=bpy.data.objects.new(name,data);scene.collection.objects.link(ob);ob.location=bp(at)
    ob.rotation_euler=(bp((1.8,.3,0))-ob.location).to_track_quat('-Z','Y').to_euler()
area('StudioKey',(1,7,7),1200,7,(1,.96,.90))
area('StudioFill',(-5,3,3),750,6,(.86,.93,1))
area('StudioRim',(6,5,-4),1100,6,(1,.97,.92))
floor_mat=bpy.data.materials.new('StudioGround_NOT_EXPORTED');floor_mat.diffuse_color=(.25,.26,.26,1)
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-1.625));floor=bpy.context.object;floor.name='STUDIO_GROUND_NOT_EXPORTED';floor.data.materials.append(floor_mat)
camdata=bpy.data.cameras.new('DoorReviewCamera');cam=bpy.data.objects.new('DoorReviewCamera',camdata);scene.collection.objects.link(cam);scene.camera=cam
camdata.type='ORTHO';camdata.lens=50;camdata.clip_end=300
def camera(at,target,scale):
    cam.location=bp(at);cam.rotation_euler=(bp(target)-cam.location).to_track_quat('-Z','Y').to_euler();camdata.ortho_scale=scale
camera((8,4.4,13),(2.0,.25,0),10.6)
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=24
scene.render.threads_mode='FIXED';scene.render.threads=2
scene.render.resolution_x=1600;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.render.film_transparent=False
scene.view_settings.view_transform='AgX';scene.view_settings.look='AgX - Medium High Contrast';scene.view_settings.exposure=0
scene.render.filepath=str(EV/'underdeck_door_source_front.png')
bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'underdeck_door.blend'))

def mesh_stats(objects):
    points=[];tri=0;dg=bpy.context.evaluated_depsgraph_get()
    for o in objects:
        eo=o.evaluated_get(dg);me=eo.to_mesh();me.calc_loop_triangles();tri+=len(me.loop_triangles)
        points.extend(gp(o.matrix_world@v.co) for v in me.vertices);eo.to_mesh_clear()
    a=np.array(points);return {'triangles':tri,'bounds':{'min':a.min(axis=0).tolist(),'max':a.max(axis=0).tolist()}}

source_stats={g:mesh_stats(objs) for g,objs in groups.items()}
bm=bmesh.new();bm.from_mesh(body.data)
body_topology={'vertices':len(bm.verts),'faces':len(bm.faces),'boundary_edges':sum(e.is_boundary for e in bm.edges),'nonmanifold_edges':sum(not e.is_manifold for e in bm.edges),'signed_volume_m3':bm.calc_volume(signed=True)};bm.free()
checks=[]
def check(name,ok,detail=None):checks.append({'name':name,'passed':bool(ok),'detail':detail})
check('continuous_panel_body_closed',body_topology['boundary_edges']==0 and body_topology['nonmanifold_edges']==0,body_topology)
check('continuous_panel_exact_dimensions',np.allclose(source_stats['PanelBody']['bounds']['min'],[-1.9,-1.6,-.15],atol=2e-6) and np.allclose(source_stats['PanelBody']['bounds']['max'],[1.9,1.6,.15],atol=2e-6),source_stats['PanelBody'])
check('panel_solid_positive_volume',body_topology['signed_volume_m3']>2.0)
check('panel_hardware_stays_in_slab',all(source_stats['PanelHardware']['bounds']['min'][i]>=np.array([-1.9,-1.6,-.15])[i]-2e-6 and source_stats['PanelHardware']['bounds']['max'][i]<=np.array([1.9,1.6,.15])[i]+2e-6 for i in range(3)),source_stats['PanelHardware'])
check('hangers_declared_extra_top_mechanism',source_stats['MovingHangers']['bounds']['max'][1]<=2.10 and source_stats['MovingHangers']['bounds']['min'][1]>=1.34-2e-6,source_stats['MovingHangers'])
check('rail_above_opening',source_stats['FixedRail']['bounds']['min'][1]>=1.66-2e-6)
check('wheel_running_surface_contact',abs(1.88-.145-1.735)<1e-8)
check('wheel_full_travel_along_running_strip',all(x-.145>=-1.99 and x+.145+4.2<=6.19 for x,_,_ in wheel_centres))
running_actual=mesh_stats([o for o in parts if o.name=='SilverRunningStrip'])['bounds']
wheel_actual=[mesh_stats([o for o in parts if o.name=='HangerWheel_%02d'%i])['bounds']for i in range(2)]
check('actual_evaluated_wheels_touch_rail_top',all(abs(b['min'][1]-running_actual['max'][1])<2e-6 for b in wheel_actual),{'wheels':wheel_actual,'running_strip':running_actual})
check('actual_evaluated_wheels_stay_on_rail_full_travel',all(b['min'][0]>=running_actual['min'][0]-2e-6 and b['max'][0]+4.2<=running_actual['max'][0]+2e-6 for b in wheel_actual))
check('single_explicit_uv_all_parts',all(len(o.data.uv_layers)==1 and o.data.uv_layers.active.name=='SurfaceUV' and o.data.uv_layers.active.active_render for o in parts))
report={'asset':'underdeck_door','blender':bpy.app.version_string,'pid':os.getpid(),'reference':str(ROOT/'references/v3/production/underdeck_door/underdeck_door_v1.png'),'reference_sha256':sha(ROOT/'references/v3/production/underdeck_door/underdeck_door_v1.png'),'editable_meshes':len(parts),'materials':list(materials),'group_stats':source_stats,'panel_body_topology':body_topology,'wheel_centres_godot':wheel_centres,'wheel_radius':.145,'running_surface_y':1.735,'status_lens_nominal':{'center':[0,1.95,.235],'size':[1,.18,.02]},'checks':checks,'passed':sum(c['passed'] for c in checks),'failed':sum(not c['passed'] for c in checks),'source_parts':{g:[o.name for o in objs] for g,objs in groups.items()},'limits':'Hangers are wall-zone decoration above the 3.2m solid. Geometry only; no Godot/collision/performance/human acceptance. Authored UV PBR maps, not geometric baking.'}
(EV/'build_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
assert not report['failed'],[c for c in checks if not c['passed']]

# Export evaluated copies only. Editable authoring scene was saved beforehand.
ex=bpy.data.collections.new('RuntimeExportCopies');scene.collection.children.link(ex)
export_results={}
for asset,rootname,filename,groupnames in [('Panel','UnderdeckDoorPanel','panel.glb',['PanelBody','PanelHardware','MovingHangers']),('Rail','UnderdeckDoorRail','fixed_rail.glb',['FixedRail','StopAndGuides','StatusLens'])]:
    er=bpy.data.objects.new(rootname,None);ex.objects.link(er);exports=[er]
    for group in groupnames:
        copies=[];dg=bpy.context.evaluated_depsgraph_get()
        for o in groups[group]:
            me=bpy.data.meshes.new_from_object(o.evaluated_get(dg),preserve_all_data_layers=True,depsgraph=dg)
            c=bpy.data.objects.new('EXPORT_'+o.name,me);ex.objects.link(c);c.matrix_world=o.matrix_world.copy();copies.append(c)
        bpy.ops.object.select_all(action='DESELECT')
        for c in copies:c.select_set(True)
        bpy.context.view_layer.objects.active=copies[0];bpy.ops.object.join();c=bpy.context.object
        # Reserve exact names without changing the on-disk authoring source.
        if group in bpy.data.objects:bpy.data.objects[group].name='SOURCE_'+group
        c.name=group
        scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
        bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
        mw=c.matrix_world.copy();c.parent=er;c.matrix_world=mw;exports.append(c)
    bpy.ops.object.select_all(action='DESELECT')
    for o in exports:o.select_set(True)
    bpy.context.view_layer.objects.active=er
    path=OUT/filename
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_apply=True,export_yup=True,export_texcoords=True,export_normals=True,export_materials='EXPORT',export_cameras=False,export_lights=False,export_animations=False,export_extras=True)
    export_results[filename]={'sha256':sha(path),'bytes':path.stat().st_size,'root':rootname,'groups':groupnames}
    for o in exports:bpy.data.objects.remove(o,do_unlink=True)
report['exports']=export_results
(EV/'build_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
# Source render only; actual GLB reimport is performed separately.
bpy.ops.render.render(write_still=True)
report['source_render_completed']=True;report['elapsed_seconds']=time.time()-t0
(EV/'build_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('DOOR_BUILD_DONE',json.dumps({'pid':os.getpid(),'seconds':time.time()-t0,'source_parts':len(parts),'groups':source_stats,'exports':export_results},ensure_ascii=False),flush=True)
