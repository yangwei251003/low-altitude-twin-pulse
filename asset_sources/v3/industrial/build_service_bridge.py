"""Editable I-B bridge; run with Blender 5.2.1 --background --python this_file.
All meshes, UVs and PBR maps are original procedural construction.
"""
from pathlib import Path
import bpy, math, json, random, sys, hashlib
import numpy as np
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[3]
SRC=ROOT/"asset_sources/v3/industrial"
OUT=ROOT/"assets/v3/industrial"
EVID=ROOT/"artifacts/v3/art/industrial"
TEX=OUT/"textures"
for p in (SRC,OUT,EVID,TEX): p.mkdir(parents=True,exist_ok=True)
(SRC/".gdignore").write_text("",encoding="utf-8")
REV=int(sys.argv[sys.argv.index("--")+1]) if "--" in sys.argv else 1
random.seed(81027)
bpy.ops.object.select_all(action="SELECT"); bpy.ops.object.delete(use_global=False)
for block in list(bpy.data.materials): bpy.data.materials.remove(block)
scene=bpy.context.scene
scene.unit_settings.system="METRIC"
scene.unit_settings.scale_length=1
source_col=bpy.data.collections.new("Editable_Components")
scene.collection.children.link(source_col)
static=[]; slats=[]; materials={}

def image_file(name, data, color=True):
    h,w=data.shape[:2]
    im=bpy.data.images.new(name,width=w,height=h,alpha=True)
    if not color: im.colorspace_settings.name="Non-Color"
    rgba=np.ones((h,w,4),dtype=np.float32)
    if data.ndim==2: rgba[:,:,:3]=data[:,:,None]
    else: rgba[:,:,:3]=data
    im.pixels.foreach_set(rgba.ravel())
    im.filepath_raw=str(TEX/(name+".png")); im.file_format="PNG"; im.save()
    im.filepath=bpy.path.relpath(str(TEX/(name+".png")),start=str(SRC))
    return im

def pbr(name, kind, size=1024):
    rng=np.random.default_rng(200+len(materials))
    v,u=np.mgrid[0:1:complex(size),0:1:complex(size)]
    fine=rng.random((size,size))
    def cloud(cells):
        grid=rng.random((cells+1,cells+1))
        xx=np.minimum(u*cells,cells-.00001); yy=np.minimum(v*cells,cells-.00001)
        ix=xx.astype(int); iy=yy.astype(int); fx=xx-ix; fy=yy-iy
        fx=fx*fx*(3-2*fx); fy=fy*fy*(3-2*fy)
        return ((1-fx)*(1-fy)*grid[iy,ix]+fx*(1-fy)*grid[iy,ix+1]
                +(1-fx)*fy*grid[iy+1,ix]+fx*fy*grid[iy+1,ix+1])
    broad=cloud(7)*.55+cloud(23)*.30+cloud(71)*.15
    mott=cloud(103)
    border=np.minimum.reduce([u,1-u,v,1-v])
    streak=np.zeros((size,size))
    for _ in range(19):
        x=rng.uniform(0,1); start=rng.uniform(.3,1); length=rng.uniform(.12,.8)
        streak+=np.exp(-((u-x)/rng.uniform(.003,.021))**2)*np.clip((start-v)/.05,0,1)*np.clip((v-(start-length))/.08,0,1)*rng.uniform(.2,.9)
    streak=np.clip(streak,0,1)
    seam=(border<.017).astype(float)
    edge=(border<(.012+.022*mott)).astype(float)
    rust=np.clip(edge*.8+streak*(.25+.6*(v>.45)),0,1)
    rust*=np.clip((mott-.24)*2,0,1)
    if kind=="paint":
        base=np.array([.13,.34,.37]); rough=.52+.24*mott
        peeled=(border<(.035+.060*mott))*np.clip((mott-.27)*2.0,0,1)
        rust=np.clip(rust*1.6+peeled*.9,0,1)
        color=base[None,None,:]*(.85+.22*broad[:,:,None])
        color=color*(1-rust[:,:,None])+np.array([.43,.21,.085])*rust[:,:,None]
        bare=(border<(.008+.008*mott))*np.clip((mott-.42)*2.8,0,1)
        color=color*(1-bare[:,:,None])+np.array([.62,.63,.57])*bare[:,:,None]
        metal=.60*(1-rust)
        height=.03*mott+.2*edge+.035*fine
        # salt trails descend from upper edges and bolted seams.
        salt=streak*.19*(v>.16)*(v<.78)
        color=color*(1-salt[:,:,None])+np.array([.58,.62,.57])*salt[:,:,None]
    elif kind=="concrete":
        color=np.array([.76,.73,.65])[None,None,:]*(.93+.10*broad[:,:,None])
        dirt=np.clip(streak*.53+np.clip((.13-v)/.13,0,1)*broad*.28,0,.75)
        color=color*(1-dirt[:,:,None])+np.array([.25,.22,.17])*dirt[:,:,None]
        pits=np.clip((cloud(185)-.71)*5,0,1)*(.25+.5*mott)
        color*=1-pits[:,:,None]*.5
        # construction joint is sparse and gravity marks begin beneath it.
        joint=np.exp(-((v-.49)/.003)**2)*.22
        crack=np.exp(-((u-(.32+.009*np.sin(v*19)+.004*np.sin(v*63)))/.0015)**2)*((v>.21)&(v<.73))*.18
        joint+=crack
        color*=1-joint[:,:,None]
        rough=np.clip(.82+.14*mott,0,1); metal=np.zeros_like(u)
        height=.015*mott+.013*fine-pits*.10-joint*.2
    elif kind=="steel":
        color=np.array([.43,.46,.46])[None,None,:]*(.75+.27*broad[:,:,None])
        scratches=(np.sin(v*2100+np.sin(u*21))>.93)*.08
        color+=scratches[:,:,None]
        color=color*(1-rust[:,:,None]*.55)+np.array([.25,.115,.045])*rust[:,:,None]*.55
        rough=.33+.3*mott; metal=np.ones_like(u)*.88
        height=.04*fine+.06*scratches
    elif kind=="graphite":
        color=np.array([.075,.09,.095])[None,None,:]*(.7+.5*broad[:,:,None])
        color+=edge[:,:,None]*.045
        rough=.65+.2*mott; metal=np.ones_like(u)*.7; height=.07*fine
    elif kind=="rubber":
        color=np.array([.025,.032,.033])[None,None,:]*(.8+.4*broad[:,:,None])
        rough=.82+.14*mott; metal=np.zeros_like(u); height=.035*fine
    elif kind=="hazard":
        stripe=((u*10+v*2)%1<.46).astype(float)
        yellow=np.array([.76,.48,.035]); black=np.array([.045,.052,.049])
        color=yellow[None,None,:]*stripe[:,:,None]+black[None,None,:]*(1-stripe[:,:,None])
        chip=np.clip(edge*.8+(fine>.95)*mott*.65+streak*.3,0,.9)
        color=color*(1-chip[:,:,None])+np.array([.29,.28,.23])*chip[:,:,None]
        rough=.6+.27*mott; metal=np.ones_like(u)*.3; height=.08*fine+.1*chip
    elif kind=="shutter":
        color=np.array([.51,.53,.52])[None,None,:]*(.81+.21*broad[:,:,None])
        line=(np.sin(v*800+np.sin(u*13))>.92)*.04
        color+=line[:,:,None]
        stain=streak*.3+edge*.2
        color=color*(1-stain[:,:,None])+np.array([.29,.17,.075])*stain[:,:,None]
        stripe=((u*15+v*5)%1<.48).astype(float)
        band=v<.15
        safety=np.array([.82,.51,.04])[None,None,:]*stripe[:,:,None]+np.array([.035,.045,.047])[None,None,:]*(1-stripe[:,:,None])
        color=np.where(band[:,:,None],safety,color)
        rough=.4+.28*mott; metal=np.where(band,.35,.86)
        height=.035*fine+.09*edge
    else:
        color=np.array([.25,.105,.045])[None,None,:]*(.8+.4*broad[:,:,None])
        rough=.8+.15*mott; metal=np.zeros_like(u); height=.12*mott+.05*fine
    # Explicit tangent normals, not a nonportable procedural-only shader.
    gy,gx=np.gradient(height)
    normal=np.dstack((-gx*13,-gy*13,np.ones_like(u)))
    normal/=np.linalg.norm(normal,axis=2)[:,:,None]
    normal=normal*.5+.5
    maps={k:image_file(name+"_"+k,np.clip(x,0,1),k=="BaseColor") for k,x in (
        ("BaseColor",color),("Roughness",rough),("Metallic",metal),("Normal",normal))}
    mat=bpy.data.materials.new(name); mat.use_nodes=True
    nodes=mat.node_tree.nodes; bs=nodes.get("Principled BSDF")
    for key,socket in [("BaseColor","Base Color"),("Roughness","Roughness"),("Metallic","Metallic")]:
        n=nodes.new("ShaderNodeTexImage"); n.image=maps[key]; n.label=key
        mat.node_tree.links.new(n.outputs["Color"],bs.inputs[socket])
    n=nodes.new("ShaderNodeTexImage"); n.image=maps["Normal"]
    nm=nodes.new("ShaderNodeNormalMap"); nm.inputs["Strength"].default_value=.30
    mat.node_tree.links.new(n.outputs["Color"],nm.inputs["Color"])
    mat.node_tree.links.new(nm.outputs["Normal"],bs.inputs["Normal"])
    materials[name]=mat
    return mat

teal=pbr("I_B_TealSaltPaint","paint")
concrete=pbr("I_B_PorousConcrete","concrete")
steel=pbr("I_B_BrushedSteel","steel")
graphite=pbr("I_B_Grating","graphite",512)
rubber=pbr("I_B_Rubber","rubber",512)
hazard=pbr("I_B_SafetyWear","hazard",512)
shuttermat=pbr("I_B_ShutterSteel","shutter")
rustmat=pbr("I_B_RustFasteners","rust",512)

def register(obj,mat, moving=False):
    for col in list(obj.users_collection): col.objects.unlink(obj)
    source_col.objects.link(obj)
    obj.data.materials.append(mat)
    if not moving: static.append(obj)
    return obj

def box(name,loc,dim,mat,bev=.02,moving=False):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc); o=bpy.context.object; o.name=name
    o.dimensions=dim; bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    # Each physical face gets its own full UV panel. Default cube cross-atlas UVs
    # put painted weathering in the middle of faces instead of actual edges.
    uv=o.data.uv_layers.active
    for polygon in o.data.polygons:
        coords=[o.data.vertices[o.data.loops[i].vertex_index].co for i in polygon.loop_indices]
        axis=max(range(3),key=lambda k:abs(polygon.normal[k]))
        axes=[k for k in range(3) if k!=axis]
        mins=[min(c[k] for c in coords) for k in axes]
        maxs=[max(c[k] for c in coords) for k in axes]
        for i,c in zip(polygon.loop_indices,coords):
            uv.data[i].uv=tuple((c[k]-lo)/(hi-lo or 1) for k,lo,hi in zip(axes,mins,maxs))
    register(o,mat,moving)
    if bev:
        m=o.modifiers.new("Machined_edge","BEVEL"); m.width=bev; m.segments=2
        m=o.modifiers.new("Weighted_normals","WEIGHTED_NORMAL")
    return o

def cylinder(name,a,b,r,mat,verts=12):
    a,b=Vector(a),Vector(b); vec=b-a
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts,radius=r,depth=vec.length,location=(a+b)/2)
    o=bpy.context.object; o.name=name; o.rotation_quaternion=vec.to_track_quat("Z","Y")
    o.rotation_mode="QUATERNION"; o.rotation_quaternion=vec.to_track_quat("Z","Y")
    register(o,mat)
    for p in o.data.polygons:p.use_smooth=True
    return o

def prism(name,profile,y0,y1,mat):
    n=len(profile)
    verts=[(x,y,z) for y in (y0,y1) for x,z in profile]
    faces=[tuple(range(n-1,-1,-1)),tuple(range(n,n*2))]
    faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    mesh=bpy.data.meshes.new(name); mesh.from_pydata(verts,[],faces); mesh.update()
    o=bpy.data.objects.new(name,mesh); source_col.objects.link(o); o.data.materials.append(mat); static.append(o)
    uv=mesh.uv_layers.new(name="UVMap")
    for p in mesh.polygons:
        coords=[Vector(verts[mesh.loops[i].vertex_index]) for i in p.loop_indices]
        axis=max(range(3),key=lambda k:abs(p.normal[k]))
        axes=[k for k in range(3) if k!=axis]
        mins=[min(c[k] for c in coords) for k in axes]; maxs=[max(c[k] for c in coords) for k in axes]
        for i,c in zip(p.loop_indices,coords):
            uv.data[i].uv=tuple((c[k]-lo)/(hi-lo or 1) for k,lo,hi in zip(axes,mins,maxs))
    m=o.modifiers.new("Cast_bevel","BEVEL"); m.width=.045; m.segments=2
    o.modifiers.new("Weighted_normals","WEIGHTED_NORMAL")
    return o

def bolt(name,x,y,z,axis="Y",r=.045):
    p=Vector((x,y,z)); delta=Vector((0,.018,0) if axis=="Y" else (0,0,.025))
    cylinder(name+"_rust_washer",p-delta*.1,p+delta*.35,r*1.45,rustmat,12)
    cylinder(name,p,p+delta,r,steel,6)

# Four shoulder-foot cast concrete legs, joined by two substantial foundation pads.
for end in (-1,1):
    x=end*5
    box(f"Foundation_{end}",(x,0,.18),(2,4,.36),concrete,.06)
    box(f"BaseSteelWeb_{end}",(x,0,.62),(1.35,1.2,.42),teal,.025)
    for side in (-1,1):
        y=side*1.25
        profile=[(x-.78,.35),(x+.78,.35),(x+.55,2.78),(x+.88,3.58),
                 (x+.88,4.5),(x-.88,4.5),(x-.88,3.58),(x-.55,2.78)]
        prism(f"ShoulderedConcrete_{end}_{side}",profile,y-.55,y+.55,concrete)
        box(f"PierCap_{end}_{side}",(x,y,4.37),(1.9,1.18,.36),concrete,.035)
        for off in (-.57,.57):
            box("AnchorFoot",(x+off,y,.40),(.3,.4,.12),teal,.02)
            bolt("FoundationAnchor",x+off,y,.48,"Z",.065)
        # Main casting joint; kept sparse and horizontal rather than random spots.
        box("ConcreteCastJoint",(x,y-side*.555,2.42),(1.29,.012,.018),rustmat,0)
    box(f"EndLoadWeb_{end}",(x,0,2.34),(.75,.64,3.9),teal,.025)
    for z in (.8,1.6,2.4,3.2):
        box("PierCableClamp",(x,-.37,z),(1.05,.15,.12),teal,.012)
    for xx in (-.20,0,.20):
        cylinder("VerticalPowerConduit",(x+xx,-.48,.52),(x+xx,-.48,4.12),.045,graphite,12)
    # Cover plate, vented junction cabinet and two bends.
    box("PierJunctionBox",(x+.07,-.65,1.95),(.88,.44,1.12),teal,.045)
    box("JunctionSilverDoor",(x+.07,-.89,1.95),(.73,.035,.95),steel,.012)
    for zz in np.linspace(1.65,2.25,9):
        box("CabinetVent",(x-.08,-.916,float(zz)),(.31,.018,.022),graphite,.003)
    cylinder("CabinetHandle",(x+.33,-.935,1.88),(x+.33,-.935,2.10),.018,graphite,10)

# Segmented engineered side beams and flanges.
for side in (-1,1):
    y=side*1.84
    for j in range(6):
        x=-5+j*2
        box(f"SideWeb_{side}_{j}",(x,y,4.16),(1.985,.18,.65),teal,.018)
        for z in (3.86,4.49):box("IBeamFlange",(x,y,z),(1.99,.31,.10),teal,.014)
        for xx in (x-.86,x+.86):
            for z in (3.99,4.34): bolt("WebRivet",xx,y+side*.105,z)
    for x in (-4,-2,0,2,4):
        box("SplicePlate",(x,y+side*.112,4.16),(.22,.04,.62),teal,.01)
        for z in (3.97,4.18,4.37):bolt("SpliceBolt",x,y+side*.14,z,r=.037)
    for z in (3.99,4.16,4.32):
        cylinder("SideCable",(-5.85,side*1.97,z),(5.85,side*1.97,z),.025,hazard if z==4.16 else graphite,12)
    for x in (-5,-3,-1,1,3,5):
        box("CableBand",(x,side*1.97,4.16),(.055,.05,.44),steel,.006)
# Cross-members visible through real grating holes.
for x in (-5.6,-4,-2,0,2,4,5.6):
    box("UnderdeckCrossMember",(x,0,4.30),(.16,3.7,.30),teal,.015)
for y in (-1.0,0,1.0): box("LongitudinalStringer",(0,y,4.43),(11.8,.10,.24),graphite,.01)
# Floor grating modeled as actual bars: no opaque plane across openings.
for x in np.arange(-5.85,5.86,.13):
    box("GratingBearingBar",(float(x),0,4.755),(.025,3.46,.09),graphite,.003)
for y in np.arange(-1.67,1.68,.15):
    box("GratingCrossBar",(0,float(y),4.77),(11.75,.019,.06),graphite,.002)
for x in (-6,-4,-2,0,2,4,6):
    box("GratePanelDivider",(max(-5.94,min(5.94,x)),0,4.765),(.09,3.5,.07),steel,.007)
for side in (-1,1):
    box("WornDeckSafetyStripe",(0,side*1.76,4.79),(11.92,.12,.02),hazard,.003)

# True gaps on BOTH edges: no rail or post inside X [-2.3,2.3].
for side in (-1,1):
    y=side*1.78
    for start,end in ((-5.82,-2.42),(2.42,5.82)):
        for z in (5.12,5.45,5.73):
            cylinder("RailTube",(start,y,z),(end,y,z),.033,steel,12)
        for x in np.linspace(start,end,4):
            box("RailPost",(float(x),y,5.25),(.075,.075,.95),teal,.009)
            box("RailFoot",(float(x),y,4.82),(.20,.22,.055),teal,.006)
            box("YellowPostCap",(float(x),y,5.73),(.095,.095,.08),hazard,.012)
            bolt("RailFootBolt",float(x)-.06,y,4.855,"Z",.025)

# Gate portals and head; rigid tracks only reach roll-up head.
for side in (-1,1):
    x=side*2.45
    box("GateColumn",(x,1.74,6.32),(.30,.35,3.04),teal,.025)
    box("GateTrack",(side*2.245,1.73,6.20),(.075,.16,2.80),graphite,.009)
    cylinder("VerticalDriveRail",(side*2.36,1.51,4.90),(side*2.36,1.51,7.66),.035,steel)
    foot_x=x+side*.15
    box("GateFootplate",(foot_x,1.66,4.86),(.58,.61,.12),teal,.025)
    for dx in (-.20,.20):
        bolt("GateAnchor",foot_x+dx,1.48,4.94,"Z",.045)
    for z in (5.05,5.9,6.7,7.45):
        bolt("GateColumnBolt",x,1.545,z,r=.047)
    box("GateCrashStripe",(x,1.55,5.12),(.25,.018,.40),hazard,.007)
    box("RollerEndHousing",(x,1.70,7.77),(.50,.51,.46),teal,.045)
    for dx in (-.16,.16):
        for zz in (7.62,7.90):bolt("RollerHousingBolt",x+dx,1.43,zz,r=.035)
cylinder("RollerBarrel",(-2.18,1.75,7.81),(2.18,1.75,7.81),.19,steel,32)
box("HeadLowerBeam",(0,1.77,7.665),(4.52,.24,.13),teal,.015)
box("GateControlBox",(2.65,1.54,6.05),(.39,.31,.75),concrete,.032)
box("GateControlDoor",(2.65,1.365,6.05),(.30,.025,.63),steel,.008)
cylinder("GateControlConduit",(2.65,1.50,4.85),(2.65,1.50,5.67),.035,rubber)
for x in (2.58,2.7):
    bolt("ControlScrew",x,1.344,6.30,r=.022)
box("ControlStatus",(2.65,1.339,6.13),(.12,.012,.085),hazard,.006)

# Shutter is an EMPTY pivot; each slat has its own centre-origin and UV band.
shutter=bpy.data.objects.new("Shutter",None); source_col.objects.link(shutter)
shutter.location=(0,1.75,4.8)
for i in range(16):
    h=2.8/16
    o=box(f"Slat_{i:02d}",(0,1.75,4.8+(i+.5)*h),(4.4,.085,h-.008),shuttermat,.012,True)
    o.parent=shutter; o.matrix_parent_inverse=shutter.matrix_world.inverted()
    # Preserve center origins; textured hazard band only on the bottom slat.
    for item in o.data.uv_layers.active.data:
        item.uv.y=.02+item.uv.y*.11 if i==0 else .20+item.uv.y*.77
    slats.append(o)
    o["slat_index"]=i
    o["movement"]="Godot +Y; hide above head; maximum lift 2.8m"

# Reference-driven pass 2: add visible channelled louver profiles and asymmetric
# casing seam covers. Pass 1 deliberately retained the basic silhouette for review.
if REV>=2:
    for o in slats:
        # Mesh shape has a shallow stepped lip; remains one mesh/material/slat.
        for vtx in o.data.vertices:
            if vtx.co.z<0: vtx.co.y-=.018
    for x in (-5,5):
        for side in (-1,1):
            box("PierBoltRail",(x,side*.35,2.36),(.13,.11,3.63),teal,.012)
            for zz in (1.0,1.8,2.6,3.4):
                bolt("PierWebFastener",x,side*.415,zz,r=.041)
    # Long beam wear must read at game distance: restrained raised splice flanges,
    # differentiated steel cleats; no uniformly scattered rust geometry.
    for x in (-4,-2,0,2,4):
        for side in (-1,1):
            box("SpliceEdgeCap",(x,side*1.955,4.49),(.28,.035,.065),steel,.008)

# Setup editable studio: neutral lighting, oblique camera, no baked lighting texture.
studio=bpy.data.collections.new("Studio_NotExported"); scene.collection.children.link(studio)
def studio_link(obj):
    for col in list(obj.users_collection):col.objects.unlink(obj)
    studio.objects.link(obj)
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.018))
ground=bpy.context.object; ground.name="StudioGround"; studio_link(ground)
gm=bpy.data.materials.new("StudioOnly"); gm.diffuse_color=(.20,.22,.24,1)
ground.data.materials.append(gm)
def point(obj,target):obj.rotation_euler=(Vector(target)-obj.location).to_track_quat("-Z","Y").to_euler()
bpy.ops.object.camera_add(location=(-14,-20,14))
cam=bpy.context.object; cam.name="ReferenceOblique"; point(cam,(0,0,3.5)); studio_link(cam)
cam.data.type="ORTHO"; cam.data.ortho_scale=17.5; scene.camera=cam
for name,loc,power,size in [("Key",(-3,-7,14),2200,8),("Fill",(8,3,12),1700,7),("Rim",(-6,6,9),1300,5)]:
    bpy.ops.object.light_add(type="AREA",location=loc); o=bpy.context.object
    o.name=name; o.data.energy=power; o.data.shape="DISK"; o.data.size=size; point(o,(0,0,3)); studio_link(o)
scene.world.color=(.25,.25,.25)
scene.render.engine="CYCLES"; scene.cycles.device="CPU"; scene.cycles.samples=20
scene.cycles.use_denoising=True
scene.render.resolution_x=1280; scene.render.resolution_y=1024; scene.render.resolution_percentage=100
scene.render.image_settings.file_format="PNG"
scene.view_settings.view_transform="AgX"
scene.render.filepath=str(EVID/f"service_bridge_review_v{REV}.png")
# UV checks are performed on source before export join.
missing_uv=[o.name for o in static+slats if not o.data.uv_layers]
source_info={"editable_static_components":len(static),"slat_count":len(slats),"missing_uv":missing_uv}
# Relative linked maps stay external and editable; never pack hidden rendering images.
bpy.ops.wm.save_as_mainfile(filepath=str(SRC/"service_bridge.blend"))
bpy.ops.render.render(write_still=True)

# Export a copy; keep the saved .blend exploded into individually editable parts.
export_col=bpy.data.collections.new("Export_Merged")
scene.collection.children.link(export_col)
copies=[]
export_depsgraph=bpy.context.evaluated_depsgraph_get()
for obj in static+slats:
    c=obj.copy()
    c.data=bpy.data.meshes.new_from_object(obj.evaluated_get(export_depsgraph),preserve_all_data_layers=True,depsgraph=export_depsgraph)
    c.modifiers.clear(); export_col.objects.link(c)
    c.parent=None; c.matrix_world=obj.matrix_world.copy()
    copies.append((obj,c))
bpy.ops.object.select_all(action="DESELECT")
for _,c in copies:c.select_set(True)
bpy.context.view_layer.objects.active=copies[0][1]
root=bpy.data.objects.new("ServiceBridge",None); export_col.objects.link(root)
export_shutter=bpy.data.objects.new("Shutter_EXPORT",None); export_col.objects.link(export_shutter)
export_shutter.location=(0,1.75,4.8); export_shutter.parent=root
outobjs=[root,export_shutter]
static_groups={mat.name:[c for original,c in copies if original in static and c.data.materials[0]==mat] for mat in materials.values()}
for mat in materials.values():
    objs=static_groups[mat.name]
    if not objs:continue
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:o.select_set(True)
    bpy.context.view_layer.objects.active=objs[0]
    bpy.ops.object.join(); merged=bpy.context.object; merged.name="Static_"+mat.name
    merged.parent=root; outobjs.append(merged)
for original,c in copies:
    if original not in slats:continue
    c.name=original.name+"_EXPORT"
    world=c.matrix_world.copy(); c.parent=export_shutter; c.matrix_world=world
    outobjs.append(c)
# Temporarily rename original source nodes to ensure glTF names are exact.
shutter.name="Source_Shutter"
export_shutter.name="Shutter"
for original,c in copies:
    if original in slats:
        desired=original.name; original.name="Source_"+desired; c.name=desired
bpy.ops.object.select_all(action="DESELECT")
for o in outobjs:o.select_set(True)
bpy.context.view_layer.objects.active=root
glb=OUT/"service_bridge.glb"
bpy.ops.export_scene.gltf(filepath=str(glb),export_format="GLB",use_selection=True,
    export_apply=True,export_yup=True,export_cameras=False,export_lights=False,
    export_materials="EXPORT",export_texcoords=True,export_normals=True,
    export_extras=True,export_animations=False)
triangles=0
for o in outobjs:
    if o.type=="MESH":o.data.calc_loop_triangles();triangles+=len(o.data.loop_triangles)
report={
"asset":"service_bridge","selected_direction":"I-B","revision":REV,
"blender_version":bpy.app.version_string,"units":"meters","blender_axis":"Z up; length X",
"nominal_dimensions":{"length":12,"width":4,"deck_top":4.8,"gate_clear_width":4.4,
"gate_clear_height":2.8,"gate_plane_y":1.75,"maximum_slat_lift":2.8},
"blender_shutter_pivot":[0,1.75,4.8],"expected_godot_shutter_pivot":[0,4.8,-1.75],
"export_nodes":[o.name for o in outobjs],"triangles":triangles,
"runtime_materials":len(materials),"source":source_info,
"slats":[{"name":o.name.removeprefix("Source_"),"local_center":[0,0,(i+.5)*.175],
"expected_godot_local_center":[0,(i+.5)*.175,0]} for i,o in enumerate(slats)],
"collision":"none; root integration owns collision",
"render":scene.render.filepath,"source_blend":str(SRC/"service_bridge.blend"),"glb":str(glb),
"sha256":hashlib.sha256(glb.read_bytes()).hexdigest(),
"validation_limits":["Not imported in Godot by asset agent","Studio render is not gameplay",
"All 16 slats deliberately remain separate draw submissions for roll-up animation"],
}
(EVID/f"asset_report_v{REV}.json").write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding="utf-8")
print("INDUSTRIAL_ASSET_REPORT "+json.dumps(report,ensure_ascii=False))
