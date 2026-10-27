"""Two original I-B industrial kit assets. Blender 5.2.1, CPU two threads.
Inputs are the original I-B PBR texture set, not projected concept images.
Run --background --factory-startup --threads 2 --python this_file -- terrace|relay.
All dimensions in modeling helpers use Godot X/Y-up/Z-front coordinates.
"""
from pathlib import Path
import bpy, json, math, sys, shutil, hashlib
import numpy as np
from mathutils import Vector, Matrix

ROOT=Path(__file__).resolve().parents[3]
SRC=ROOT/'asset_sources/v3/industrial_kit'; OUT=ROOT/'assets/v3/industrial_kit'
EVID=ROOT/'artifacts/v3/art/industrial_kit'; TEX=OUT/'textures'
for folder in (SRC,OUT,EVID,TEX):folder.mkdir(parents=True,exist_ok=True)
(SRC/'.gdignore').write_text('',encoding='utf-8')
KIND=sys.argv[sys.argv.index('--')+1] if '--' in sys.argv else 'terrace'
assert KIND in ('terrace','relay')
REV=int(sys.argv[sys.argv.index('--')+2]) if '--' in sys.argv and len(sys.argv)>sys.argv.index('--')+2 else 1
ASSET='coastal_work_terrace' if KIND=='terrace' else 'power_relay_cabinet'
ROOTNAME='CoastalWorkTerrace' if KIND=='terrace' else 'PowerRelayCabinet'
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
scene=bpy.context.scene;scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
source=bpy.data.collections.new('Editable_'+ROOTNAME);scene.collection.children.link(source)
parts=[]; special={}; pivots={}; markers={}; materials={}; texture_provenance=[]

def concrete_atlas():
    # UV lower half is vertical cast concrete; upper half is rain-worn horizontal
    # paving. Separate orientation prevents downward rust trails on a flat floor.
    rng=np.random.default_rng(731992);n=512
    v,u=np.mgrid[0:1:complex(n),0:1:complex(n)]
    def cloud(cells):
        grid=rng.random((cells+1,cells+1));x=np.minimum(u*cells,cells-.00001);y=np.minimum(v*cells,cells-.00001)
        ix=x.astype(int);iy=y.astype(int);fx=x-ix;fy=y-iy;fx=fx*fx*(3-2*fx);fy=fy*fy*(3-2*fy)
        return (1-fx)*(1-fy)*grid[iy,ix]+fx*(1-fy)*grid[iy,ix+1]+(1-fx)*fy*grid[iy+1,ix]+fx*fy*grid[iy+1,ix+1]
    broad=cloud(6)*.55+cloud(17)*.30+cloud(57)*.15;fine=cloud(134);grain=rng.random((n,n))
    edge=np.minimum.reduce([u,1-u,v,1-v]);pits=np.clip((fine-.69)*6,0,1)
    colors=[];heights=[];roughs=[]
    for horizontal in [False,True]:
        pigment=np.array([.65,.61,.51])
        color=pigment[None,None,:]*(.76+.48*broad[:,:,None])
        stains=np.clip((broad-.50)*2.8,0,.55)
        if horizontal:
            stains*=np.clip((cloud(14)-.18)*1.6,0,1)
            chalk=np.clip((cloud(22)-.61)*2.1,0,.36)
        else:
            streak=np.zeros((n,n))
            for _ in range(7):
                x=rng.uniform(.03,.97);start=rng.uniform(.6,1)
                streak+=np.exp(-((u-x)/rng.uniform(.008,.024))**2)*np.clip((start-v)/.1,0,1)*np.clip((v-.07)/.35,0,1)
            stains=np.clip(stains*.7+streak*.36+np.clip((.22-v)/.22,0,1)*(.25+.3*broad),0,.65)
            chalk=np.clip((cloud(17)-.62)*2.3,0,.34)
        color=color*(1-stains[:,:,None])+np.array([.25,.24,.18])*stains[:,:,None]
        color=color*(1-chalk[:,:,None])+np.array([.82,.80,.71])*chalk[:,:,None]
        if not horizontal:
            tide=np.clip((.27+.025*np.sin(u*11)+.02*broad-v)/.15,0,1)*.58
            color=color*(1-tide[:,:,None])+np.array([.17,.19,.14])*tide[:,:,None]
        color*=1-pits[:,:,None]*.35
        chipped=(edge<(.006+.014*fine))*np.clip((fine-.4)*2,0,1)
        color=color*(1-chipped[:,:,None]*.28)+np.array([.72,.69,.59])*chipped[:,:,None]*.28
        height=.02*grain+.05*fine-pits*.13;rough=.78+.19*fine
        if horizontal and KIND=='terrace':
            # Quiet worked concrete, not high-contrast marble clouds. The vertical
            # half above is byte-for-byte unchanged; keep its tide and gravity wear.
            pigment=np.array([.62,.60,.54])
            color=pigment[None,None,:]*(.965+.060*broad[:,:,None]+.014*(grain[:,:,None]-.5))
            rare_pores=np.clip((grain-.993)*142,0,1)
            color*=1-rare_pores[:,:,None]*.16
            wear=np.clip((broad-.60)*.65,0,.08)
            color=color*(1-wear[:,:,None])+np.array([.72,.70,.64])*wear[:,:,None]
            color=color*(1-chipped[:,:,None]*.10)+np.array([.70,.68,.62])*chipped[:,:,None]*.10
            height=.003*grain+.004*fine-rare_pores*.012
            rough=.84+.035*fine
        colors.append(color);heights.append(height);roughs.append(rough)
    height=np.concatenate(heights,axis=0);gy,gx=np.gradient(height)
    normal=np.dstack((-gx*10,-gy*10,np.ones_like(height)));normal/=np.linalg.norm(normal,axis=2)[:,:,None]
    return {'BaseColor':np.concatenate(colors,axis=0),'Roughness':np.concatenate(roughs,axis=0),'Metallic':np.zeros_like(height),'Normal':normal*.5+.5}

CONCRETE_ATLAS=concrete_atlas()

def bpos(g):return Vector((g[0],-g[2],g[1]))
def link(obj):
    for col in list(obj.users_collection):col.objects.unlink(obj)
    source.objects.link(obj)

def material(name,original,signal=False):
    mat=bpy.data.materials.new(name);mat.use_nodes=True;maps={}
    # Terrace-only paths isolate revisions from the locked relay .blend/.glb.
    terrace_concrete=KIND=='terrace' and original=='I_B_PorousConcrete'
    terrace_safety=KIND=='terrace' and signal
    texname='IK_TerraceConcrete' if terrace_concrete else ('IK_TerraceSafety' if terrace_safety else name)
    for role in ('BaseColor','Roughness','Metallic','Normal'):
        src=ROOT/'assets/v3/industrial/textures'/f'{original}_{role}.png'
        dst=TEX/f'{texname}_{role}.png'
        if original=='I_B_PorousConcrete':
            data=CONCRETE_ATLAS[role];h,w=data.shape[:2];px=np.ones((h,w,4),dtype=np.float32)
            px[:,:,:3]=data[:,:,None] if data.ndim==2 else data
            im=bpy.data.images.new(f'{name}_{role}',width=w,height=h,alpha=True)
            if role!='BaseColor':im.colorspace_settings.name='Non-Color'
            im.pixels.foreach_set(px.ravel());im.file_format='PNG';im.filepath_raw=str(dst);im.save()
        elif terrace_safety:
            # No green region or emission in a stair marking. Pad 16px around a
            # coherent six-band yellow/charcoal field; samples never wrap to a lamp.
            w=h=512;v,u=np.mgrid[0:1:complex(h),0:1:complex(w)]
            u=np.clip(u,16/512,1-16/512);v=np.clip(v,16/512,1-16/512)
            stripe=((u*6+v*.38)%1)<.58
            grain=np.random.default_rng(4195).random((h,w))
            px=np.ones((h,w,4),dtype=np.float32)
            if role=='BaseColor':
                px[:,:,:3]=np.where(stripe[:,:,None],np.array([.72,.36,.022]),np.array([.022,.024,.022]))
                px[:,:,:3]*=(.96+.07*grain[:,:,None])
                scuff=(grain>.996)[:,:,None]*.14
                px[:,:,:3]=px[:,:,:3]*(1-scuff)+np.array([.24,.22,.17])*scuff
            elif role=='Roughness':px[:,:,:3]=(.78+.08*grain)[:,:,None]
            elif role=='Metallic':px[:,:,:3]=.05
            else:px[:,:,:3]=[.5,.5,1]
            im=bpy.data.images.new(f'{texname}_{role}',width=w,height=h,alpha=True)
            if role!='BaseColor':im.colorspace_settings.name='Non-Color'
            im.pixels.foreach_set(px.ravel());im.file_format='PNG';im.filepath_raw=str(dst);im.save()
        elif not signal:
            shutil.copy2(src,dst)
            im=bpy.data.images.load(str(dst),check_existing=False)
        else:
            inp=bpy.data.images.load(str(src),check_existing=False)
            w,h=inp.size;px=np.array(inp.pixels[:],dtype=np.float32).reshape(h,w,4)
            boundary=int(w*.77)
            if role=='BaseColor':px[:,boundary:,:3]=[.12,.74,.43]
            elif role=='Roughness':px[:,boundary:,:3]=.23
            elif role=='Metallic':px[:,boundary:,:3]=.15
            else:px[:,boundary:,:3]=[.5,.5,1]
            im=bpy.data.images.new(f'{name}_{role}',width=w,height=h,alpha=True)
            if role!='BaseColor':im.colorspace_settings.name='Non-Color'
            im.pixels.foreach_set(px.ravel());im.file_format='PNG';im.filepath_raw=str(dst);im.save()
            bpy.data.images.remove(inp)
        if role!='BaseColor':im.colorspace_settings.name='Non-Color'
        im.filepath=bpy.path.relpath(str(dst),start=str(SRC));maps[role]=im
        change='terrace-only quiet horizontal concrete; original vertical tide retained' if terrace_concrete else ('terrace-only padded yellow/charcoal stripes; no green/emission' if terrace_safety else ('new original two-surface cast-concrete atlas using I-B palette' if original=='I_B_PorousConcrete' else ('original I-B copied unchanged' if not signal else 'new UV atlas: original safety region plus separate green signal swatch')))
        texture_provenance.append({'source':str(src.relative_to(ROOT)),'source_sha256':hashlib.sha256(src.read_bytes()).hexdigest(),'output':str(dst.relative_to(ROOT)),'change':change})
    bs=mat.node_tree.nodes.get('Principled BSDF')
    for key,socket in [('BaseColor','Base Color'),('Roughness','Roughness'),('Metallic','Metallic')]:
        n=mat.node_tree.nodes.new('ShaderNodeTexImage');n.image=maps[key];n.label=key
        if terrace_safety:n.extension='EXTEND'
        mat.node_tree.links.new(n.outputs['Color'],bs.inputs[socket])
    n=mat.node_tree.nodes.new('ShaderNodeTexImage');n.image=maps['Normal']
    if terrace_safety:n.extension='EXTEND'
    nm=mat.node_tree.nodes.new('ShaderNodeNormalMap');nm.inputs['Strength'].default_value=.30
    mat.node_tree.links.new(n.outputs['Color'],nm.inputs['Color']);mat.node_tree.links.new(nm.outputs['Normal'],bs.inputs['Normal'])
    if signal and not terrace_safety:
        w=h=512;px=np.zeros((h,w,4),dtype=np.float32);px[:,:,3]=1;px[:,int(w*.77):,:3]=[.12,.74,.43]
        im=bpy.data.images.new(name+'_Emission',width=w,height=h,alpha=True);im.pixels.foreach_set(px.ravel())
        dst=TEX/(name+'_Emission.png');im.filepath_raw=str(dst);im.file_format='PNG';im.save();im.filepath=bpy.path.relpath(str(dst),start=str(SRC))
        n=mat.node_tree.nodes.new('ShaderNodeTexImage');n.image=im;mat.node_tree.links.new(n.outputs['Color'],bs.inputs['Emission Color']);bs.inputs['Emission Strength'].default_value=1.8
    materials[name]=mat;return mat

ivory=material('IK_IvoryWeather','I_B_PorousConcrete')
teal=material('IK_TealSalt','I_B_TealSaltPaint')
steel=material('IK_Galvanized','I_B_BrushedSteel')
safety=material('IK_SafetySignal','I_B_SafetyWear',True)

def face_uv(obj,signal=False):
    mesh=obj.data;uv=mesh.uv_layers.active or mesh.uv_layers.new(name='UVMap')
    for face in mesh.polygons:
        axes=[k for k in range(3) if k!=max(range(3),key=lambda k:abs(face.normal[k]))]
        coords=[mesh.vertices[mesh.loops[i].vertex_index].co for i in face.loop_indices]
        lo=[min(c[k] for c in coords) for k in axes];hi=[max(c[k] for c in coords) for k in axes]
        for loop,c in zip(face.loop_indices,coords):
            u,v=[(c[k]-a)/(z-a or 1) for k,a,z in zip(axes,lo,hi)]
            if obj.data.materials and obj.data.materials[0]==safety:
                if KIND=='terrace':u=.04+u*.92;v=.04+v*.92
                else:u=.81+u*.16 if signal else u*.72
            if obj.data.materials and obj.data.materials[0]==ivory:
                if int(hashlib.sha256(obj.name.encode()).hexdigest()[:2],16)%2:u=1-u
                if KIND=='terrace' and abs(face.normal.z)<.9:v=min(1,max(0,(c.z+obj.location.z)/4))
                v=.505+v*.49 if abs(face.normal.z)>.9 else .005+v*.49
            uv.data[loop].uv=(u,v)

def reg(o,mat,group=None,signal=False):
    link(o);o.data.materials.append(mat);face_uv(o,signal);parts.append(o)
    if group:special.setdefault(group,[]).append(o)
    return o

def box(name,at,size,mat,bevel=.012,group=None,signal=False):
    bpy.ops.mesh.primitive_cube_add(size=1,location=bpos(at));o=bpy.context.object;o.name=name
    o.dimensions=(size[0],size[2],size[1]);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    reg(o,mat,group,signal)
    if bevel:
        m=o.modifiers.new('Rounded_manufactured_edges','BEVEL');m.width=bevel;m.segments=1
        o.modifiers.new('Weighted_normals','WEIGHTED_NORMAL')
    return o

def cylinder(name,a,b,r,mat,vertices=12,group=None,signal=False):
    a,b=bpos(a),bpos(b);direction=b-a
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=r,depth=direction.length,location=(a+b)/2)
    o=bpy.context.object;o.name=name;o.rotation_mode='QUATERNION';o.rotation_quaternion=direction.to_track_quat('Z','Y')
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=True);reg(o,mat,group,signal)
    for p in o.data.polygons:p.use_smooth=len(p.vertices)==4
    return o

def beam(name,a,b,width,mat,group=None):
    a,b=bpos(a),bpos(b);v=b-a
    bpy.ops.mesh.primitive_cube_add(size=1,location=(a+b)/2);o=bpy.context.object;o.name=name
    o.dimensions=(width,width,v.length);o.rotation_mode='QUATERNION';o.rotation_quaternion=v.to_track_quat('Z','Y')
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=True);reg(o,mat,group)
    m=o.modifiers.new('Edge_bevel','BEVEL');m.width=width*.12;m.segments=1
    o.modifiers.new('Weighted_normals','WEIGHTED_NORMAL');return o

def front_bolt(name,x,y,z,r=.032,group=None):
    cylinder(name+'_Washer',(x,y,z-.004),(x,y,z+.006),r*1.35,steel,12,group)
    cylinder(name,(x,y,z+.006),(x,y,z+.022),r,steel,6,group)

def top_bolt(name,x,y,z,r=.04):
    cylinder(name,(x,y-.015,z),(x,y,z),r,steel,6)

def marker(name,at):markers[name]=bpos(at)

def terrace():
    # Solid retaining courses, independently editable; no repeated bridge feet.
    box('Continuous_Foundation',(0,.125,0),(12,.25,8),ivory,.035)
    for i in range(4):
        lo=.25+i*.8625;hi=.25+(i+1)*.8625
        for j in range(4):
            x=-3.2+(j+.5)*2.3
            box(f'Main_CastCourse_{i}_{j}',(x,(lo+hi)/2,-.2),(2.288,hi-lo-.012,7.6),ivory,.018)
        box(f'Stair_Left_Cheek_{i}',(-5.8,(lo+hi)/2,0),(.388,hi-lo-.012,8),ivory,.018)
        box(f'Stair_Rear_Mass_{i}',(-4.4,(lo+hi)/2,-2.2),(2.4,hi-lo-.012,3.6),ivory,.018)
    # Real inset stair opening: 16 risers, no solid body behind the flight path.
    for i in range(16):
        height=(i+1)*.25;z=4-(i+.5)*.275
        box(f'Stair_Tread_{i:02}',(-4.4,(height-.012)/2,z),(2.18,height-.012,.268),ivory,.008)
        box(f'Stair_Nosing_{i:02}',(-4.4,height-.006,z+.093),(2.10,.012,.080),safety,.002)
    # Segmented usable top slabs; trench remains genuinely recessed.
    for x0,x1 in [(-3.2,-.14),(-.14,2.93),(2.93,5.76)]:
        for z0,z1 in [(-3.76,-1.65),(-1.65,.70),(.70,3.05)]:
            box('Worktop_Slab',((x0+x1)/2,3.85,(z0+z1)/2),(x1-x0-.016,.30,z1-z0-.016),ivory,.015)
    box('LeftTopCoping',(-5.68,3.85,0),(.16,.30,7.52),ivory,.01)
    box('StairLanding',(-4.4,3.85,-2.08),(2.4,.30,3.36),ivory,.01)
    # Rear and lateral steel caps are exactly flush with Y=4 and envelope edges.
    for x in [-5.88,5.88]:box('Side_Edge_Cap',(x,3.935,0),(.24,.11,7.96),teal,.008)
    box('Rear_Edge_Cap',(0,3.935,-3.88),(11.48,.11,.24),teal,.008)
    box('Front_Top_Cap',(1.28,3.845,3.8),(8.96,.29,.4),teal,.01)
    box('Drain_Trough_Bottom',(1.4,3.725,3.325),(9.16,.05,.55),steel,.003)
    for z in [3.075,3.575]:box('Drain_Grate_Frame',(1.4,3.9775,z),(9.15,.045,.035),steel,.003)
    for i in range(91):box('Drain_Grate_Bar',(-3.14+i*.1,3.9775,3.325),(.026,.045,.50),steel,.002)
    # Front shell leaves a real service recess and two recessed scuppers.
    xbreak=[-3.2,-2.6,-.4,.55,1.05,4.2,4.7,6]
    ybreak=[.25,.70,1.55,2.4,3.2,3.7]
    for xi in range(len(xbreak)-1):
        x0,x1=xbreak[xi:xi+2]
        for yi in range(len(ybreak)-1):
            y0,y1=ybreak[yi:yi+2]
            recess=(x0==-2.6 and y0==2.4)
            drain=(x0 in [.55,4.2] and y0==.25)
            if recess or drain:continue
            shallow=y0>=3.2
            box('Front_Retaining_Panel',((x0+x1)/2,(y0+y1)/2,3.76 if shallow else 3.8),(x1-x0-.012,y1-y0-.012,.32 if shallow else .4),ivory,.012)
    box('Service_Pocket_Back',(-1.5,2.8,3.62),(2.18,.76,.035),teal,.008)
    for y in [2.52,2.72,2.92]:
        cylinder('Service_Conduit',(-2.42,y,3.78),(-.72,y,3.78),.040,steel,10)
        cylinder('Conduit_Downleg',(-2.42,2.42,3.78),(-2.42,y,3.78),.04,steel,10)
    box('Recessed_Junction',(-.69,2.79,3.80),(.40,.52,.22),ivory,.015)
    for y in np.linspace(2.65,2.94,5):box('Junction_Louver',(-.69,float(y),3.923),(.23,.025,.025),steel,.002)
    for x in [.8,4.45]:
        for off in [-.16,0,.16]:cylinder('Scupper_Bar',(x+off,.28,3.86),(x+off,.66,3.86),.028,steel,8)
        box('Scupper_Sill',(x,.268,3.8),(.48,.036,.4),steel,.003)
    # Belting/splices on front and outer side; controlled bolted construction.
    box('Front_Steel_Belt',(1.4,3.46,3.94),(9.16,.44,.04),teal,.008)
    for x in [-3.04,.10,3.10,5.84]:
        box('Front_Splice',(x,3.44,3.967),(.24,.48,.065),teal,.006)
        for y in [3.24,3.44,3.64]:front_bolt('Front_Splice_Bolt',x,y,3.976,.042)
    for side in [-1,1]:
        box('Side_Belt',(side*5.982,3.46,0),(.036,.44,7.94),teal,.008)
        for z in [-3.65,-1.2,1.2,3.65]:
            box('CopingRepairPlate',(side*5.74,3.946,z),(.40,.044,.40),teal,.006)
            top_bolt('CopingAnchor',side*5.74,4,z,.045)
    for x in [-2.86,5.72]:
        for z in [-3.88,3.79]:box('CornerSafety',(x,3.997,z),(.48,.006,.18),safety,0)
    # Stair cheek lower plates emphasize the sloping access without adding rails.
    beam('StairInner_Edge',(-3.25,.28,3.92),(-3.25,3.96,-.35),.10,teal)
    marker('TopCenter',(1.2,4,0));marker('FrontDock',(1.4,4,4))
    marker('StairBottom',(-4.4,0,4));marker('StairTop',(-4.4,4,-.4))
    marker('JoinLeft',(-6,2,0));marker('JoinRight',(6,2,0));marker('JoinRear',(0,2,-4))

def relay():
    box('Cabinet_Foundation',(0,.09,0),(2,.18,1.6),ivory,.025)
    box('Main_Cabinet_Shell',(0,1.43,-.04),(1.76,2.5,1.20),teal,.035)
    box('Roof_Drip_Coping',(0,2.65,-.03),(1.94,.12,1.44),steel,.022)
    box('Roof_Teal_Trim',(0,2.585,.664),(1.92,.10,.07),teal,.008)
    for x in [-.84,.84]:
        box('Corner_Structural_Rib',(x,1.38,.607),(.11,2.4,.075),teal,.01)
        box('Anchor_Shoe',(x,.235,.52),(.24,.11,.30),teal,.01)
        for off in [-.07,.07]:top_bolt('Base_Anchor',x+off,.295,.56,.03)
    # Doors remain separate editable plates; no meaningless geometry behind vents.
    for x in [-.413,.413]:
        box('Service_Door',(x,1.61,.595),(.78,1.62,.055),teal,.015)
        for y in [.92,2.26]:
            box('Door_Hinge',(x+(-.355 if x<0 else .355),y,.636),(.10,.17,.05),steel,.006)
            cylinder('Hinge_Barrel',(x+(-.355 if x<0 else .355),y-.085,.673),(x+(-.355 if x<0 else .355),y+.085,.673),.022,steel,10)
        hx=x+(.29 if x<0 else -.29)
        for y in [1.16,1.36]:cylinder('Handle_Mount',(hx,y,.625),(hx,y,.690),.018,steel,8)
        cylinder('Door_Handle',(hx,1.16,.690),(hx,1.36,.690),.025,steel,10)
    box('Instrument_Ivory_Fascia',(.42,1.65,.637),(.63,1.40,.032),ivory,.012)
    box('Switch_Backing',(.42,1.34,.667),(.39,.52,.028),steel,.008)
    for x in [.18,.66]:
        for y in [1.02,2.27]:front_bolt('FasciaBolt',x,y,.663,.020)
    # Status lens: exact independently addressable node/material UV range.
    cylinder('Lamp_Bezel',(.42,2.13,.66),(.42,2.13,.704),.128,steel,16)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16,ring_count=8,radius=.100,location=bpos((.42,2.13,.706)))
    lamp=bpy.context.object;lamp.name='StatusLamp';lamp.scale=(1,.55,1);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    reg(lamp,safety,'StatusLamp',True)
    # Thin metal protection cross stays static, does not erase the readable lens.
    cylinder('LampCageHorizontal',(.33,2.13,.767),(.51,2.13,.767),.008,steel,8)
    cylinder('LampCageVertical',(.42,2.04,.768),(.42,2.22,.768),.008,steel,8)
    pivots['SwitchPivot']=bpos((.42,1.34,.715))
    cylinder('Switch_Axle',(.29,1.34,.708),(.55,1.34,.708),.065,steel,16)
    box('Switch_Lever',(.42,1.56,.717),(.075,.44,.050),steel,.008,'SwitchHandle')
    box('Switch_Grip',(.42,1.80,.725),(.13,.21,.080),safety,.015,'SwitchHandle')
    # Three ceramic flanges and metal sockets are three distinct interaction meshes.
    box('Terminal_Ivory_Band',(0,.615,.625),(1.56,.44,.045),ivory,.012)
    for x,key in [(-.52,'Terminal_A'),(0,'Terminal_B'),(.52,'Terminal_C')]:
        box(key+'_Plate',(x,.615,.662),(.34,.34,.035),steel,.008,key)
        for z,r in [(.694,.135),(.726,.116),(.758,.126)]:
            cylinder(key+'_Ceramic',(x,.615,z-.016),(x,.615,z+.016),r,ivory,14,key)
        cylinder(key+'_Socket',(x,.615,.771),(x,.615,.795),.092,steel,12,key)
        for dx in [-.132,.132]:
            for dy in [-.132,.132]:front_bolt(key+'_Bolt',x+dx,.615+dy,.688,.016,key)
    # Louvers are actual folded metal blades with depth and undercuts.
    box('Front_Vent_Recess',(-.42,1.76,.630),(.51,.95,.020),steel,.008)
    for y in np.linspace(1.35,2.18,10):
        o=box('Front_Louver',(-.42,float(y),.666),(.46,.030,.070),steel,.004)
        o.rotation_euler.x=math.radians(-15)
    box('Lower_Vent_Recess',(0,.305,.638),(1.52,.20,.018),steel,.005)
    for y in [.245,.31,.375]:box('Lower_Louver',(0,y,.672),(1.46,.022,.065),steel,.003)
    # Visible right-side vent, conduit and wall gland kept inside width/depth limits.
    box('Side_Vent_Border',(.892,2.03,-.07),(.035,.57,.50),steel,.007)
    for y in np.linspace(1.82,2.24,6):box('Side_Louver',(.920,float(y),-.07),(.056,.024,.43),steel,.003)
    box('Side_Gland_Box',(.91,.73,-.17),(.15,.40,.31),ivory,.012)
    for z in [-.25,-.09]:
        cylinder('Side_Conduit',(.928,.23,z),(.928,.52,z),.027,steel,10)
        for y in [.30,.44]:box('Conduit_Clamp',(.941,y,z),(.045,.035,.09),steel,.004)
    # Lifting lugs set the strict 2.8m height; holes remain actual geometry.
    for x in [-.60,.60]:
        bpy.ops.mesh.primitive_torus_add(major_radius=.055,minor_radius=.020,major_segments=12,minor_segments=6,location=bpos((x,2.725,-.08)),rotation=(math.pi/2,0,0))
        o=bpy.context.object;o.name='Lifting_Eye';bpy.ops.object.transform_apply(location=False,rotation=True,scale=True);reg(o,teal)
    for x in [-.84,.84]:
        for y in [1.25,1.65]:box('Edge_Safety',(x,y,.650),(.08,.20,.015),safety,.002)
    for x in [-.73,-.10,.10,.73]:
        for y in [.88,2.34]:front_bolt('Door_Perimeter_Bolt',x,y,.634,.020)
    marker('InteractionFront',(0,1.35,1.1));marker('CableInputRear',(0,.42,-.65))

terrace() if KIND=='terrace' else relay()

# Authoring roots and precise local pivots. Mesh transforms are already Y-up-safe
# after exporter conversion, not hidden under a rotated application wrapper.
root=bpy.data.objects.new(ROOTNAME,None);source.objects.link(root)
for name,at in pivots.items():
    p=bpy.data.objects.new(name,None);source.objects.link(p);p.location=at;p.parent=root;pivots[name]=p
bpy.context.view_layer.update()
for obj in parts:
    transform=obj.matrix_world.copy();obj.parent=root;obj.matrix_world=transform
    if obj in special.get('SwitchHandle',[]):obj.parent=pivots['SwitchPivot'];obj.matrix_world=transform
for name,at in markers.items():
    o=bpy.data.objects.new(name,None);source.objects.link(o);o.location=at;o.parent=root;markers[name]=o

# All preview-only objects live outside the source and export collections.
studio=bpy.data.collections.new('Studio_NotExported');scene.collection.children.link(studio)
def studiolink(o):
    for c in list(o.users_collection):c.objects.unlink(o)
    studio.objects.link(o)
def aim(o,target):o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.035));ground=bpy.context.object;ground.name='StudioGround';studiolink(ground)
gm=bpy.data.materials.new('StudioOnly');gm.diffuse_color=(.29,.31,.33,1);ground.data.materials.append(gm)
camera_at=(15,-20,16) if KIND=='terrace' else (4,-6,3.8)
target=(0,0,1.8) if KIND=='terrace' else (0,0,1.4)
bpy.ops.object.camera_add(location=camera_at);cam=bpy.context.object;cam.name='ReviewCamera';aim(cam,target);studiolink(cam)
cam.data.type='ORTHO';cam.data.ortho_scale=17.5 if KIND=='terrace' else 4.15;scene.camera=cam
scale=1 if KIND=='terrace' else .30
for name,loc,power,size in [('Key',(-3,-7,15),2500,8),('Fill',(8,3,12),1500,7),('Rim',(-8,6,10),1700,5)]:
    bpy.ops.object.light_add(type='AREA',location=Vector(loc)*scale);o=bpy.context.object;o.name=name;o.data.energy=power*scale*scale;o.data.shape='DISK';o.data.size=size*scale;aim(o,target);studiolink(o)
scene.world.color=(.23,.23,.23);scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=24;scene.cycles.use_denoising=True
scene.render.threads_mode='FIXED';scene.render.threads=2
scene.render.resolution_x=1152;scene.render.resolution_y=960;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG';scene.view_settings.view_transform='AgX'
scene.render.filepath=str(EVID/f'{ASSET}_review_v{REV}.png')
bpy.ops.wm.save_as_mainfile(filepath=str(SRC/f'{ASSET}.blend'))
if '--export-only' not in sys.argv:bpy.ops.render.render(write_still=True)

# Export evaluated copies; source blend retains all individual editable elements.
exp=bpy.data.collections.new('Export_Merged');scene.collection.children.link(exp)
deps=bpy.context.evaluated_depsgraph_get();copies=[]
special_lookup={o.name:g for g,objs in special.items() for o in objs}
for obj in parts:
    c=obj.copy();c.data=bpy.data.meshes.new_from_object(obj.evaluated_get(deps),preserve_all_data_layers=True,depsgraph=deps);c.modifiers.clear();exp.objects.link(c);c.parent=None;c.matrix_world=obj.matrix_world.copy()
    copies.append((obj,c))
root.name='Source_'+ROOTNAME
export_root=bpy.data.objects.new(ROOTNAME,None);exp.objects.link(export_root);out=[export_root]
export_pivots={}
for name,obj in pivots.items():
    obj.name='Source_'+name;p=bpy.data.objects.new(name,None);exp.objects.link(p);p.location=obj.location;p.parent=export_root;export_pivots[name]=p;out.append(p)
def merge(objs,name,parent,origin=None):
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objs:obj.select_set(True)
    bpy.context.view_layer.objects.active=objs[0];bpy.ops.object.join();o=bpy.context.object;o.name=name
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    scene.cursor.location=origin if origin is not None else Vector((0,0,0));bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    m=o.matrix_world.copy();o.parent=parent;o.matrix_world=m;out.append(o);return o
for mat in materials.values():
    cs=[c for orig,c in copies if orig.name not in special_lookup and orig.data.materials[0]==mat]
    if cs:merge(cs,'Static_'+mat.name,export_root)
for group,originals in special.items():
    cs=[c for orig,c in copies if orig in originals]
    for o in originals:
        if o.name==group:o.name='Source_'+group
    parent=export_pivots.get('SwitchPivot',export_root) if group=='SwitchHandle' else export_root
    origin=bpos((.42,1.34,.715)) if group=='SwitchHandle' else (bpos(({'Terminal_A':-.52,'Terminal_B':0,'Terminal_C':.52}[group],.615,.70)) if group.startswith('Terminal') else bpos((.42,2.13,.706)))
    merge(cs,group,parent,origin)
for name,obj in markers.items():
    obj.name='Source_'+name;o=bpy.data.objects.new(name,None);exp.objects.link(o);o.location=obj.location;o.parent=export_root;out.append(o)
bpy.ops.object.select_all(action='DESELECT')
for o in out:o.select_set(True)
bpy.context.view_layer.objects.active=export_root
glb=OUT/f'{ASSET}.glb'
bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,export_apply=True,export_yup=True,export_cameras=False,export_lights=False,export_materials='EXPORT',export_texcoords=True,export_normals=True,export_extras=True,export_animations=False)
triangles=0;points=[]
for o in out:
    if o.type!='MESH':continue
    o.data.calc_loop_triangles();triangles+=len(o.data.loop_triangles)
    points.extend(o.matrix_world@v.co for v in o.data.vertices)
mins=[min(p[k] for p in points) for k in range(3)];maxs=[max(p[k] for p in points) for k in range(3)]
report={'asset':ASSET,'revision':REV,'reference':f'references/v3/production/industrial/{ASSET}.png','blender':bpy.app.version_string,'render_engine':'Cycles CPU','render_threads':scene.render.threads,'triangles':triangles,'materials':list(materials),'editable_meshes':len(parts),'export_nodes':[o.name for o in out],'missing_uv':[o.name for o in parts if not o.data.uv_layers],'blender_bounds':{'min':mins,'max':maxs},'expected_godot_bounds':{'min':[mins[0],mins[2],-maxs[1]],'max':[maxs[0],maxs[2],-mins[1]]},'source_blend':str(SRC/f'{ASSET}.blend'),'glb':str(glb),'glb_sha256':hashlib.sha256(glb.read_bytes()).hexdigest(),'texture_provenance':texture_provenance,'collision':'none: root integration owns explicit wrapper','limits':['Studio render is not Godot gameplay','No whole-project import performed','Runtime collisions/performance not tested by asset worker']}
(EVID/f'{ASSET}_report_v{REV}.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
assert triangles<=20000,(ASSET,triangles)
print('KIT_ASSET_REPORT '+json.dumps({k:v for k,v in report.items() if k!='texture_provenance'},ensure_ascii=False))
