"""Original I-B thermal bypass. Godot coordinates in all modeling helpers.
CPU2 only. Explicit UV-authored PBR PNGs; no projected concept plane, no fake bake.
Editable parts saved before runtime-only joining. Copyright: project original.
"""
from pathlib import Path
import bpy, math, json, hashlib, struct, zlib, time
import numpy as np
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[3]
SRC=ROOT/'asset_sources/v3/thermal_bypass'; OUT=ROOT/'assets/v3/thermal_bypass'
TEX=SRC/'textures'; EVID=SRC/'evidence'
for d in (SRC,OUT,TEX,EVID):d.mkdir(parents=True,exist_ok=True)
(SRC/'.gdignore').write_text('')
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
scene=bpy.context.scene;scene.unit_settings.system='METRIC'
source=bpy.data.collections.new('Editable_ThermalBypass');scene.collection.children.link(source)
parts=[];groups={};mats={}
PIVOT=(-.70,1.00,.68)
def bp(p):return Vector((p[0],-p[2],p[1]))
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def png(path,arr):
    a=np.clip(arr*255+.5,0,255).astype(np.uint8)
    if a.ndim==2:a=np.repeat(a[:,:,None],3,axis=2)
    h,w,_=a.shape
    def chunk(t,d):return struct.pack('>I',len(d))+t+d+struct.pack('>I',zlib.crc32(t+d)&0xffffffff)
    raw=b''.join(b'\0'+row.tobytes() for row in a)
    path.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(raw,6))+chunk(b'IEND',b''))
def material(name,color,metal,rough,kind):
    n=512;v,u=np.mgrid[0:1:complex(n),0:1:complex(n)]
    atlas={r:np.zeros((1024,1024,3),dtype=float) for r in ('BaseColor','Roughness','Metallic','Normal')}
    for tile in range(4):
        rng=np.random.default_rng(8317+tile*59+len(name)*71)
        broad=(np.sin(u*13+tile)+np.sin(v*17+u*6)+np.sin(u*31-v*9))/6+.5
        fine=rng.random((n,n));edge=np.minimum.reduce((u,1-u,v,1-v))
        base=np.array(color)
        if kind=='steel' and tile>=2:base=np.array([.48,.50,.48])
        c=np.broadcast_to(base,(n,n,3)).copy()*(.96+.07*broad[:,:,None]+.012*(fine[:,:,None]-.5))
        # Material damage follows authored UV panel boundaries; broad quiet middle.
        chip=np.clip((.035+.022*broad-edge)*65,0,1)*np.clip((broad-.30)*2.6,0,1)
        rust=np.zeros_like(u)
        for _ in range(3):
            x=rng.uniform(.08,.92);start=rng.choice([.04,.96]);width=rng.uniform(.008,.025)
            trail=np.exp(-((u-x)/width)**2)*np.exp(-np.abs(v-start)/rng.uniform(.04,.18))
            rust+=trail
        rust=np.clip(rust*.40+chip*.36,0,.65)
        if kind in ('blue','ivory'):
            c=c*(1-chip[:,:,None]*.78)+np.array([.34,.36,.34])*chip[:,:,None]*.78
            c=c*(1-rust[:,:,None])+np.array([.36,.22,.12])*rust[:,:,None]
        elif kind=='copper':
            oxide=np.clip((.13-np.minimum(v,1-v))*5,0,.50)*(.4+.6*broad)
            c=c*(1-oxide[:,:,None])+np.array([.20,.35,.31])*oxide[:,:,None]
            c=c*(1-chip[:,:,None]*.2)+np.array([.75,.48,.26])*chip[:,:,None]*.2
        elif kind=='safety':
            bands=((u*3.4+v*.65)%1)>.67;c=np.where(bands[:,:,None],np.array([.10,.12,.12]),c)
            c=c*(1-chip[:,:,None]*.7)+np.array([.29,.38,.40])*chip[:,:,None]*.7
        elif kind=='status':
            # Runtime temperature (not power) owns the hue; a coloured base would
            # suppress orange/red when multiplied by wrapper state colours.
            c=np.broadcast_to(np.array([.84,.86,.84]),(n,n,3)).copy()
            c*=.90+.10*np.cos(v[:,:,None]*math.pi)
            chip*=0;rust*=0
        else:c*=1-rust[:,:,None]*.35
        r=np.clip(rough+.10*chip+.035*(broad-.5),.12,.95)
        h=chip*.015+rust*.004+.0005*fine
        gy,gx=np.gradient(h);normal=np.dstack((-gx*11,-gy*11,np.ones_like(h)));normal/=np.linalg.norm(normal,axis=2)[:,:,None]
        y=(tile//2)*512;x=(tile%2)*512
        for role,a in [('BaseColor',c),('Roughness',np.repeat(r[:,:,None],3,axis=2)),('Metallic',np.full((n,n,3),metal)),('Normal',normal*.5+.5)]:atlas[role][y:y+512,x:x+512]=a
    mat=bpy.data.materials.new(name);mat.use_nodes=True;bs=mat.node_tree.nodes.get('Principled BSDF')
    uv=mat.node_tree.nodes.new('ShaderNodeUVMap');uv.uv_map='SurfaceUV'
    for role,arr in atlas.items():
        p=TEX/f'{name}_{role}.png';png(p,arr)
        im=bpy.data.images.load(str(p),check_existing=False);im.colorspace_settings.name='sRGB' if role=='BaseColor' else 'Non-Color'
        im.filepath=bpy.path.relpath(str(p),start=str(SRC))
        node=mat.node_tree.nodes.new('ShaderNodeTexImage');node.image=im;node.label=role;node.extension='EXTEND'
        mat.node_tree.links.new(uv.outputs['UV'],node.inputs['Vector'])
        if role=='Normal':
            nm=mat.node_tree.nodes.new('ShaderNodeNormalMap');nm.inputs['Strength'].default_value=.30
            mat.node_tree.links.new(node.outputs['Color'],nm.inputs['Color']);mat.node_tree.links.new(nm.outputs['Normal'],bs.inputs['Normal'])
        else:mat.node_tree.links.new(node.outputs['Color'],bs.inputs[{'BaseColor':'Base Color','Roughness':'Roughness','Metallic':'Metallic'}[role]])
    if kind=='status':bs.inputs['Emission Color'].default_value=(.32,.32,.32,1);bs.inputs['Emission Strength'].default_value=.10
    mats[name]=mat;return mat
blue=material('TB_BluePaint',(.25,.44,.53),.08,.53,'blue')
ivory=material('TB_IvoryPaint',(.78,.75,.66),.04,.64,'ivory')
steel=material('TB_DarkSteel',(.26,.29,.29),.62,.53,'steel')
copper=material('TB_CopperHeat',(.66,.36,.21),.70,.43,'copper')
safety=material('TB_SafetyWear',(.91,.61,.12),.08,.67,'safety')
status=material('TB_StatusLens',(.30,.80,.70),.0,.22,'status')

def link(o):
    for c in list(o.users_collection):c.objects.unlink(o)
    source.objects.link(o)
def tileuv(u,v,t):return ((t%2+.008+.984*u)/2,(t//2+.008+.984*v)/2)
def uvbox(o,tile=None):
    me=o.data
    while me.uv_layers:me.uv_layers.remove(me.uv_layers[0])
    uv=me.uv_layers.new(name='SurfaceUV');me.uv_layers.active_index=0;uv.active_render=True
    offset=int(hashlib.sha256(o.name.encode()).hexdigest()[:4],16)%4
    for f in me.polygons:
        axes=[i for i in range(3) if i!=max(range(3),key=lambda k:abs(f.normal[k]))]
        coords=[me.vertices[me.loops[i].vertex_index].co for i in f.loop_indices]
        lo=[min(c[k] for c in coords) for k in axes];hi=[max(c[k] for c in coords) for k in axes]
        t=tile if tile is not None else (offset+f.index)%4
        for li,c in zip(f.loop_indices,coords):
            u,v=[(c[k]-a)/(b-a or 1) for k,a,b in zip(axes,lo,hi)]
            uv.data[li].uv=tileuv(u,v,t)
def reg(o,mat,group='StaticHousing',tile=None):
    link(o);o.data.materials.append(mat);uvbox(o,tile);parts.append(o);groups.setdefault(group,[]).append(o);return o
def box(name,p,size,mat=blue,bevel=.012,group='StaticHousing',tile=None):
    bpy.ops.mesh.primitive_cube_add(size=1,location=bp(p));o=bpy.context.object;o.name=name;o.scale=(size[0],size[2],size[1]);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    reg(o,mat,group,tile)
    if bevel:
        mod=o.modifiers.new('ManufacturedEdge','BEVEL');mod.width=bevel;mod.segments=1
        mod=o.modifiers.new('WeightedNormals','WEIGHTED_NORMAL');mod.keep_sharp=True
    return o
def cyl(name,a,b,r,mat=steel,n=16,group='StaticSteel',tile=0):
    a,b=bp(a),bp(b);d=b-a
    bpy.ops.mesh.primitive_cylinder_add(vertices=n,radius=r,depth=d.length,end_fill_type='NGON',location=(a+b)/2)
    o=bpy.context.object;o.name=name;o.rotation_euler=d.to_track_quat('Z','Y').to_euler();bpy.ops.object.transform_apply(location=False,rotation=True,scale=True);reg(o,mat,group,tile)
    for f in o.data.polygons:f.use_smooth=len(f.vertices)==4
    return o
def beam(name,a,b,w,d,mat=blue):
    aa,bb=bp(a),bp(b);v=bb-aa
    o=box(name,(0,0,0),(w,v.length,d),mat,.008)
    o.location=(aa+bb)/2;o.rotation_euler=v.to_track_quat('Z','Y').to_euler();return o
def mesh(name,verts,faces,mat,group='StaticHousing',uvs=None):
    me=bpy.data.meshes.new(name);me.from_pydata([bp(v) for v in verts],[],faces);me.update();o=bpy.data.objects.new(name,me);source.objects.link(o);reg(o,mat,group)
    if uvs:
        uv=me.uv_layers.active
        for f,coords in zip(me.polygons,uvs):
            for i,co in zip(f.loop_indices,coords):uv.data[i].uv=tileuv(*co,0)
    return o
def annulus(name,c,outer,inner,z0,z1,mat=blue,n=64):
    # Closed ring, not an opaque disk: blade silhouettes remain visible through it.
    verts=[]
    for zz,r in [(z0,outer),(z0,inner),(z1,outer),(z1,inner)]:
        for i in range(n):
            a=2*math.pi*i/n;verts.append((c[0]+r*math.cos(a),c[1]+r*math.sin(a),zz))
    faces=[];uvs=[]
    for i in range(n):
        j=(i+1)%n
        for row in [(i,j,n+j,n+i),(2*n+i,3*n+i,3*n+j,2*n+j),(i,2*n+i,2*n+j,j),(n+i,n+j,3*n+j,3*n+i)]:
            faces.append(row);uvs.append([(i/n,.02),(i/n,.98),((i+1)/n,.98),((i+1)/n,.02)])
    return mesh(name,verts,faces,mat,uvs=uvs)
def pipe(name,points,r=.083):
    pts=[Vector(p) for p in points];verts=[];faces=[];uvs=[];n=12
    for i,p in enumerate(pts):
        tangent=pts[min(i+1,len(pts)-1)]-pts[max(i-1,0)];tangent.normalize()
        axis=Vector((0,0,1));a=tangent.cross(axis).normalized();b=tangent.cross(a).normalized()
        for j in range(n):verts.append(tuple(p+r*(math.cos(j*2*math.pi/n)*a+math.sin(j*2*math.pi/n)*b)))
    for i in range(len(pts)-1):
        for j in range(n):
            k=(j+1)%n;faces.append((i*n+j,i*n+k,(i+1)*n+k,(i+1)*n+j));uvs.append([(j/n,i/(len(pts)-1)),((j+1)/n,i/(len(pts)-1)),((j+1)/n,(i+1)/(len(pts)-1)),(j/n,(i+1)/(len(pts)-1))])
    faces.extend([tuple(range(n-1,-1,-1)),tuple((len(pts)-1)*n+j for j in range(n))]);uvs.extend([[(.5+.48*math.cos(j*2*math.pi/n),.5+.48*math.sin(j*2*math.pi/n)) for j in range(n)] for _ in range(2)])
    o=mesh(name,verts,faces,copper,'HeatPipes',uvs)
    for f in o.data.polygons:f.use_smooth=len(f.vertices)==4
    return o
def bolt(name,x,y,z,r=.024):
    cyl(name+'_Washer',(x,y,z),(x,y,z+.011),r*1.35,steel,12,tile=2)
    cyl(name+'_Hex',(x,y,z+.011),(x,y,z+.036),r,steel,6,tile=2)

# Low skid, four service feet, finite thickness and full ground contact.
for x in [-1.32,1.32]:
    for z in [-.77,.77]:
        box('FootPad',(x,.035,z),(.32,.07,.32),steel,.012,'StaticSteel',2)
        box('FootBlock',(x,.135,z),(.25,.20,.25),blue,.014)
        cyl('FootBolt',(x,.235,z),(x,.266,z),.041,steel,6,tile=2)
for z in [-.78,.78]:box('SkidRail',(0,.22,z),(2.78,.20,.16),blue,.018)
for x in [-1.30,1.30]:box('SkidCross',(x,.22,0),(.16,.20,1.60),blue,.016)
box('ServiceTray',(0,.305,0),(2.68,.10,1.51),steel,.012,'StaticSteel',0)
for x in [-1.0,.90]:box('WornSafetyMark',(x,.228,.866),(.44,.108,.012),safety,.002,'StaticSafety')

# Fan duct: large true circle and a dark, physically recessed rear cavity.
annulus('FanPaintedDuct',PIVOT,.735,.626,.20,.785)
annulus('FanInnerMetalLip',PIVOT,.628,.599,.73,.803,steel)
annulus('FanFrontRimBead',PIVOT,.741,.708,.785,.82,blue)
cyl('FanRearMotor',(-.70,1,-.23),(-.70,1,.13),.24,steel,24,tile=0)
cyl('FanRearCavity',(-.70,1,.18),(-.70,1,.22),.70,steel,48,tile=0)
for i in range(11):
    y=.44+i*.105;half=math.sqrt(max(0,.55**2-(y-1)**2))
    if half>.05:box('RearDuctLouver',(-.70,y,.19),(2*half,.022,.05),steel,.003,'StaticSteel',0)
# Five swept, subtly pitched thick blades. Axis remains +Z in Godot.
for i in range(5):
    a=i*2*math.pi/5
    outline=[(.12,-.07),(.32,-.12),(.56,-.05),(.57,.13),(.45,.24),(.18,.105)]
    verts=[]
    for dz in [-.018,.018]:
        for r,t in outline:
            xx=r*math.cos(a)-t*math.sin(a);yy=r*math.sin(a)+t*math.cos(a)
            verts.append((PIVOT[0]+xx,PIVOT[1]+yy,PIVOT[2]+dz+.06*t/.24))
    faces=[tuple(range(5,-1,-1)),tuple(range(6,12))]+[(j,(j+1)%6,(j+1)%6+6,j+6) for j in range(6)]
    mesh('FanBlade_%02d'%i,verts,faces,steel,'FanBlades')
cyl('RotatingHub',(-.70,1,.65),(-.70,1,.765),.145,blue,24,'FanBlades',0)
# Four fixed guard spokes, clearly in front of the rotor, never parented to it.
for a in [0,math.pi/2,math.pi,3*math.pi/2]:
    a0=(-.70+.14*math.cos(a),1+.14*math.sin(a),.837);a1=(-.70+.61*math.cos(a),1+.61*math.sin(a),.837)
    d=Vector(a1)-Vector(a0);o=box('FixedGuardSpoke',tuple((Vector(a0)+Vector(a1))/2),(.045,d.length,.032),steel,.006,'StaticSteel',2)
    o.rotation_euler=bp(d).to_track_quat('Z','Y').to_euler()
    bolt('GuardEnd',a1[0],a1[1],.858,.022)
cyl('FixedHubCap',(-.70,1,.82),(-.70,1,.881),.115,blue,24,tile=0)
for a in np.linspace(0,2*math.pi,9)[:-1]:bolt('RimFastener',-.70+.69*math.cos(a),1+.69*math.sin(a),.825,.022)
for a in np.linspace(0,2*math.pi,6)[:-1]:bolt('HubFastener',-.70+.081*math.cos(a),1+.081*math.sin(a),.887,.012)
beam('FanFootBraceL',(-1.18,.34,.51),(-1.12,.49,.51),.09,.19)
beam('FanFootBraceR',(-.25,.34,.51),(-.15,.49,.51),.10,.19)

# Main rectangular heat exchanger depth, panel layering and service seams.
box('LowerServiceCasing',(.69,.565,-.025),(1.28,.42,1.37),ivory,.035)
box('LowerServiceDoor',(.73,.57,.684),(1.10,.28,.025),ivory,.015)
for x in [.25,1.21]:
    for y in [.465,.675]:bolt('DoorFastener',x,y,.707,.020)
box('RadiatorDarkVolume',(.72,1.19,-.06),(1.30,.81,1.30),steel,.025,'StaticSteel',0)
for y in np.linspace(.815,1.565,24):box('FineCoolingPlate',(.72,float(y),.634),(1.26,.012,.08),steel,.001,'StaticSteel',0)
# Eight coarse folded ribs: full top return and front face, unlike pasted stripes.
for j in range(8):
    x=.13+j*.165
    box('RadiatorRibFront_%02d'%j,(x,1.19,.719),(.087,.81,.095),ivory,.015)
    box('RadiatorRibTop_%02d'%j,(x,1.61,-.025),(.087,.065,1.42),ivory,.014)
    box('RadiatorRibBottom_%02d'%j,(x,.78,.60),(.087,.055,.25),ivory,.010)
    bolt('RibFastener',x,1.535,.775,.015)
    bolt('RibFastener',x,.847,.775,.015)
for x in [.015,1.385]:
    box('RadiatorCornerPost',(x,.99,.0),(.10,1.29,1.46),blue,.020)
    for y in [.49,1.51]:bolt('PostFastener',x,y,.756,.025)
box('TopRearFrame',(.70,1.665,-.70),(1.53,.10,.10),blue,.014)
box('RightServicePanel',(1.441,1.10,-.08),(.018,.72,1.12),blue,.012)
for y in [.97,1.06,1.15,1.24]:box('RightServiceVent',(1.455,y,-.12),(.013,.026,.64),steel,0,'StaticSteel',0)
for y in [.81,1.40]:
    for z in [-.52,.36]:cyl('SidePanelFastener',(1.452,y,z),(1.477,y,z),.021,steel,6,tile=2)
box('BottomRearAccess',(.70,.85,-.765),(1.30,.85,.065),ivory,.020)
for x in [.19,1.20]:
    for y in [.52,1.18]:cyl('RearFastener',(x,y,-.80),(x,y,-.825),.024,steel,6,tile=2)
for y in [.86,.98,1.10]:box('RearVent',(.70,y,-.807),(.65,.026,.03),steel,.004,'StaticSteel',0)
# Fan-side rear shell provides mass without closing the front ring.
box('FanRearHousing',(-.73,.92,-.405),(1.25,1.17,.49),blue,.055)
box('FanRearPanel',(-.73,.96,-.667),(1.05,.89,.035),ivory,.024)
for x in [-1.15,-.31]:
    for y in [.63,1.29]:cyl('MotorRearBolt',(x,y,-.69),(x,y,-.715),.024,steel,6,tile=2)

# Two continuous bent return pipes, squarely attached to bolted sockets.
for k,z in enumerate([.38,-.42]):
    left=-.015;right=1.225;bottom=1.51;radius=.17;yt=1.885
    pts=[(left,bottom,z),(left,yt-radius,z)]
    for a in np.linspace(math.pi,math.pi/2,8)[1:]:pts.append((left+radius+radius*math.cos(a),yt-radius+radius*math.sin(a),z))
    pts.append((right-radius,yt,z))
    for a in np.linspace(math.pi/2,0,8)[1:]:pts.append((right-radius+radius*math.cos(a),yt-radius+radius*math.sin(a),z))
    pts.extend([(right,bottom,z)])
    pipe('CopperReturn_%02d'%k,pts,.080)
    for x in [left,right]:
        cyl('PipeSocket',(x,1.48,z),(x,1.63,z),.116,blue,16,'StaticHousing',0)
        cyl('PipeFlange',(x,1.62,z),(x,1.66,z),.145,steel,16,tile=2)
        for a in [0,math.pi/2,math.pi,3*math.pi/2]:
            xx=x+.117*math.cos(a);zz=z+.117*math.sin(a)
            cyl('FlangeHex',(xx,1.657,zz),(xx,1.683,zz),.020,steel,6,tile=2)
    for x in [.40,.99]:
        cyl('PipeSleeve',(x-.020,yt,z),(x+.020,yt,z),.089,steel,16,tile=2)

# Narrow weather-sealed thermometer; segment separators stay static.
box('TemperatureHousing',(-.70,1.807,.43),(.91,.20,.28),blue,.025)
box('TemperatureInset',(-.70,1.809,.583),(.79,.105,.025),steel,.010,'StaticSteel',0)
box('TemperatureLens',(-.70,1.810,.601),(.735,.071,.013),status,.006,'StatusLens',0)
for i in range(1,14):box('TemperatureDivider',(-1.067+i*.0525,1.810,.610),(.006,.070,.006),steel,.001,'StaticSteel',0)
for x in [-1.105,-.295]:bolt('TemperatureBolt',x,1.81,.58,.016)

# Source hierarchy and animation hinge, saved editable before merging copies.
root=bpy.data.objects.new('ThermalBypass',None);source.objects.link(root)
pivot=bpy.data.objects.new('FanRotor',None);source.objects.link(pivot);pivot.location=bp(PIVOT);pivot.parent=root
bpy.context.view_layer.update()
for o in parts:
    mw=o.matrix_world.copy();o.parent=pivot if o in groups['FanBlades'] else root;o.matrix_world=mw
markers={'InteractionCentre':(0,1,0),'BaseOrigin':(0,0,0)}
for name,p in markers.items():o=bpy.data.objects.new(name,None);source.objects.link(o);o.location=bp(p);o.parent=root

# Soft neutral daylight; explicit actual geometry, no concept-image plane.
studio=bpy.data.collections.new('Studio_NotExported');scene.collection.children.link(studio)
def studio_link(o):
    for c in list(o.users_collection):c.objects.unlink(o)
    studio.objects.link(o)
def aim(o,target):o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.015));o=bpy.context.object;o.name='StudioGround';studio_link(o)
gm=bpy.data.materials.new('StudioOnly');gm.diffuse_color=(.25,.27,.28,1);o.data.materials.append(gm)
bpy.ops.object.camera_add(location=(4.4,-7,4.0));cam=bpy.context.object;cam.name='ReviewCamera';studio_link(cam);aim(cam,(0,0,1));cam.data.type='ORTHO';cam.data.ortho_scale=4.35;scene.camera=cam
for name,p,power,size in [('Key',(-3,-4,7),650,5),('Fill',(4,-1,4),420,4),('Rim',(0,4,6),600,4)]:
    bpy.ops.object.light_add(type='AREA',location=p);o=bpy.context.object;o.name=name;studio_link(o);o.data.energy=power;o.data.shape='DISK';o.data.size=size;aim(o,(0,0,1))
scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.38,.40,.42,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.45
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=24;scene.cycles.use_denoising=True;scene.render.threads_mode='FIXED';scene.render.threads=2
scene.render.resolution_x=1400;scene.render.resolution_y=1050;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG';scene.view_settings.view_transform='AgX'
scene.render.filepath=str(EVID/'thermal_bypass_source_front.png')
bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'thermal_bypass.blend'))
bpy.ops.render.render(write_still=True)

# Copies only: merged export does not damage editable source pieces.
exp=bpy.data.collections.new('Export_Merged');scene.collection.children.link(exp);deps=bpy.context.evaluated_depsgraph_get();copies={}
for group,objs in groups.items():
    copies[group]=[]
    for o in objs:
        c=bpy.data.objects.new(o.name+'_ExportCopy',bpy.data.meshes.new_from_object(o.evaluated_get(deps),preserve_all_data_layers=True,depsgraph=deps));exp.objects.link(c);c.matrix_world=o.matrix_world.copy();copies[group].append(c)
root.name='SOURCE_ThermalBypass';pivot.name='SOURCE_FanRotor'
er=bpy.data.objects.new('ThermalBypass',None);exp.objects.link(er)
ep=bpy.data.objects.new('FanRotor',None);exp.objects.link(ep);ep.location=bp(PIVOT);ep.parent=er
bpy.context.view_layer.update();exports=[er,ep]
for name,objs in copies.items():
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:o.select_set(True)
    bpy.context.view_layer.objects.active=objs[0];bpy.ops.object.join();o=bpy.context.object;o.name=name
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    scene.cursor.location=bp(PIVOT) if name=='FanBlades' else (0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    mw=o.matrix_world.copy();o.parent=ep if name=='FanBlades' else er;o.matrix_world=mw;exports.append(o)
for name,p in markers.items():
    bpy.data.objects[name].name='SOURCE_'+name;o=bpy.data.objects.new(name,None);exp.objects.link(o);o.location=bp(p);o.parent=er;exports.append(o)
bpy.context.view_layer.update()
tri=0;points=[]
for o in exports:
    if o.type=='MESH':o.data.calc_loop_triangles();tri+=len(o.data.loop_triangles);points.extend(o.matrix_world@v.co for v in o.data.vertices)
mins=[min(p[k] for p in points) for k in range(3)];maxs=[max(p[k] for p in points) for k in range(3)]
godotmin=[mins[0],mins[2],-maxs[1]];godotmax=[maxs[0],maxs[2],-mins[1]]
report={'asset':'thermal_bypass','blender':bpy.app.version_string,'triangles':tri,'editable_meshes':len(parts),'materials':list(mats),'runtime_nodes':[o.name for o in exports],'godot_bounds_expected':{'min':godotmin,'max':godotmax},'fan_pivot_expected':PIVOT,'fan_rotation_axis':'Godot asset-root +Z; actual GLB rest to be decoded','source':str(SRC/'thermal_bypass.blend'),'reference_sha256':sha(ROOT/'references/v3/production/thermal_bypass/thermal_bypass_v1.png'),'texture_method':'Original UV-authored 1024px BaseColor sRGB PNG plus independently authored roughness, metallic and tangent-normal PNG. Not a geometric bake or projected concept.','render':'Cycles CPU 2 threads, 24 samples, AgX; not gameplay','source_groups':{k:[o.name for o in v] for k,v in groups.items()}}
(EVID/'build_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
assert tri<=12000,tri
assert all(godotmin[i]>=[-1.5,0,-1][i]-.00001 and godotmax[i]<=[1.5,2,1][i]+.00001 for i in range(3)),(godotmin,godotmax)
bpy.ops.object.select_all(action='DESELECT')
for o in exports:o.select_set(True)
bpy.context.view_layer.objects.active=er
glb=OUT/'thermal_bypass.glb'
bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,export_apply=True,export_yup=True,export_cameras=False,export_lights=False,export_materials='EXPORT',export_texcoords=True,export_normals=True,export_extras=True,export_animations=False)
report.update(glb=str(glb),glb_sha256=sha(glb),glb_bytes=glb.stat().st_size)
(EVID/'build_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('THERMAL_BUILD',json.dumps({k:v for k,v in report.items() if k!='source_groups'},ensure_ascii=False))
