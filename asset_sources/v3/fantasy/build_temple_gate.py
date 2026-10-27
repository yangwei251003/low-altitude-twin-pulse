"""F-B temple gate. Run with Blender 5.2 --background --python this_file.

Independent editable source; dimensions are metres. Front faces -Y, up is +Z.
Procedural brush maps are original source textures, not sampled reference pixels.
The single concept does not describe its back: rear masonry is an explicit design.
"""
import bpy, math, random, json, os, sys
import numpy as np
from pathlib import Path
from mathutils import Vector

SOURCE = Path(__file__).resolve().parent
ROOT = SOURCE.parents[2]
OUT = ROOT / 'assets/v3/fantasy'
ART = ROOT / 'artifacts/v3/art/fantasy'
TEX = SOURCE / 'textures'
for folder in (OUT, ART, TEX):
    folder.mkdir(parents=True, exist_ok=True)
random.seed(37219)
rng = np.random.default_rng(37219)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for data in list(bpy.data.materials): bpy.data.materials.remove(data)
scene = bpy.context.scene
scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1.0
model_collection = bpy.data.collections.new('Editable_TempleGate')
scene.collection.children.link(model_collection)
studio_collection = bpy.data.collections.new('Studio_NOT_EXPORTED')
scene.collection.children.link(studio_collection)
model_objects = []

def move_to(obj, coll):
    for c in list(obj.users_collection): c.objects.unlink(obj)
    coll.objects.link(obj)

def save_map(name, arr, non_color=False):
    h,w = arr.shape[:2]
    if arr.ndim == 2: arr=np.repeat(arr[:,:,None],3,axis=2)
    rgba = np.ones((h,w,4),dtype=np.float32)
    rgba[:,:,:3] = np.clip(arr[:,:,:3],0.0,1.0)
    img = bpy.data.images.new(name,width=w,height=h,alpha=False)
    if non_color: img.colorspace_settings.name='Non-Color'
    img.pixels.foreach_set(rgba.ravel())
    img.filepath_raw=str(TEX/(name+'.png'))
    img.file_format='PNG'
    img.save()
    img.pack()
    return img

def stone_atlas(size):
    """Sixteen face-tone tiles: quiet fields, large paint daubs, warm edge planes."""
    cell=size//4
    colours=np.array([[.39,.405,.385],[.475,.465,.405],[.57,.535,.435],[.44,.455,.415]])
    col=np.zeros((size,size,3),dtype=np.float32); height=np.full((size,size),.5,dtype=np.float32)
    yy,xx=np.mgrid[0:cell,0:cell].astype(np.float32)/cell
    for row in range(4):
        for column in range(4):
            tone=colours[row]+np.array([.016,-.003,-.013])*(column-1.5)
            patch=np.tile(tone,(cell,cell,1))
            patch+=(.009*np.sin((xx*1.1+yy*.7)*math.tau))[:,:,None]
            h=np.full((cell,cell),.5,dtype=np.float32)
            for i in range(10):
                cx,cy=rng.uniform(.05,.95,2); a=rng.uniform(-1.1,1.1)
                length=rng.uniform(.22,.62); width=rng.uniform(.025,.16)
                u=(xx-cx)*math.cos(a)+(yy-cy)*math.sin(a)
                v=-(xx-cx)*math.sin(a)+(yy-cy)*math.cos(a)
                mask=(abs(u)<length/2)&(abs(v)<width*(.5-.24*abs(u)/length))
                tint=np.array([.05,.032,-.002]) if i%2 else np.array([-.035,-.013,.009])
                patch[mask]+=tint*rng.uniform(.45,.85)
                h[mask]+=rng.uniform(-.006,.006)
            # Fine dry-brush streaks stay within the same quiet colour family.
            for i in range(13):
                cx,cy=rng.uniform(0,1,2)
                u=xx-cx; v=yy-cy-u*.5
                mask=(abs(u)<rng.uniform(.04,.14))&(abs(v)<.003)
                patch[mask]+=.014 if i%2 else -.010
            ys=slice(row*cell,(row+1)*cell); xs=slice(column*cell,(column+1)*cell)
            col[ys,xs]=patch; height[ys,xs]=h
    gy,gx=np.gradient(height)
    normal=np.dstack((-gx*3,-gy*3,np.ones_like(gx)))
    normal/=np.linalg.norm(normal,axis=2)[:,:,None]
    return (save_map('FB_stone_BaseColor',col),save_map('FB_stone_Roughness',.88+(height-.5)*.8,True),save_map('FB_stone_Normal',normal*.5+.5,True))

def brush_maps(kind, size=1024):
    """Tileable layered brush fields. Colour chips are broad, not photoreal grit."""
    if kind=='stone': return stone_atlas(size)
    y,x=np.mgrid[0:size,0:size].astype(np.float32)/size
    if kind=='stone':
        base=np.array([.49,.46,.36]); palette=np.array([[.69,.60,.43],[.40,.45,.43],[.58,.56,.46],[.31,.36,.35],[.73,.67,.50]])
        rough=.89
    elif kind=='bark':
        base=np.array([.26,.125,.057]); palette=np.array([[.46,.25,.105],[.35,.18,.078],[.19,.079,.032],[.56,.33,.15]])
        rough=.83
    elif kind=='moss':
        base=np.array([.20,.27,.055]); palette=np.array([[.34,.40,.075],[.13,.21,.042],[.43,.46,.12],[.22,.32,.058]])
        rough=.97
    elif kind=='leaf':
        base=np.array([.26,.37,.07]); palette=np.array([[.40,.50,.12],[.12,.28,.055],[.55,.56,.18],[.21,.38,.12]])
        rough=.86
    else:
        base=np.array([.30,.24,.105]); palette=np.array([[.48,.37,.15],[.17,.28,.21],[.34,.28,.13],[.54,.44,.23]])
        rough=.68
    # Periodic low-frequency directional underpainting.
    field=.034*np.sin(2*math.pi*(x*5+y*3))+.026*np.sin(2*math.pi*(x*13-y*7))
    field+=.018*np.sin(2*math.pi*(x*31+y*29))
    col=np.tile(base,(size,size,1))+field[:,:,None]
    height=field*.17+.5
    # Angular daubs with tapered ends. Spatial detail spans several scales.
    count=240 if kind=='stone' else 750
    for i in range(count):
        cx,cy=rng.uniform(0,size,2)
        length=rng.uniform(size*.040,size*.24) if kind=='stone' else rng.uniform(size*.018,size*.17)
        width=rng.uniform(size*.009,size*.055) if kind=='stone' else rng.uniform(size*.004,size*.045)
        angle=rng.uniform(-1.1,1.1) if kind=='stone' else rng.uniform(1.36,1.78)
        if kind in ('moss','leaf'): angle=rng.uniform(-math.pi,math.pi)
        a,b=math.cos(angle),math.sin(angle)
        radius=int(length+width+2)
        ix0,ix1=max(0,int(cx-radius)),min(size,int(cx+radius))
        iy0,iy1=max(0,int(cy-radius)),min(size,int(cy+radius))
        yy,xx=np.mgrid[iy0:iy1,ix0:ix1]
        u=(xx-cx)*a+(yy-cy)*b
        v=-(xx-cx)*b+(yy-cy)*a
        shape=(abs(u)<length*.5)&(abs(v)<width*(.5-.26*abs(u)/length))
        shape&=(u/length+v/max(width,1)<.72)
        pigment=palette[int(rng.integers(0,len(palette)))]
        strength=rng.uniform(.25,.8)
        target=col[iy0:iy1,ix0:ix1]
        target[shape]=target[shape]*(1-strength)+pigment*strength
        height[iy0:iy1,ix0:ix1][shape]+=rng.uniform(-.035,.035)
    if kind=='bark':
        grain=np.sin(2*math.pi*(x*23+.7*np.sin(2*math.pi*y*2)))
        grooves=np.clip((grain-.77)*2,0,1)
        col-=grooves[:,:,None]*np.array([.09,.055,.022])
        height-=grooves*.07
    if kind=='stone':
        # Short painterly hairline fissures, not a regular tile grid.
        for j in range(70):
            start=rng.uniform(0,size,2); delta=rng.uniform(-75,75,2)
            for t in np.linspace(0,1,65):
                px,py=(start+delta*t+np.array([math.sin(t*13)*3,math.sin(t*8)*2])).astype(int)
                if 1<=px<size-2 and 1<=py<size-2:
                    col[py:py+2,px:px+2]*=.60
                    height[py:py+2,px:px+2]-=.045
    gy,gx=np.gradient(height)
    normal=np.dstack((-gx*3.5,-gy*3.5,np.ones_like(gx)))
    normal/=np.linalg.norm(normal,axis=2)[:,:,None]
    normal=normal*.5+.5
    roughness=np.clip(rough+(height-.5)*.5,.2,1)
    return (save_map('FB_'+kind+'_BaseColor',col),save_map('FB_'+kind+'_Roughness',roughness,True),save_map('FB_'+kind+'_Normal',normal,True))

def painted_material(name, kind, metallic=0):
    mat=bpy.data.materials.new(name); mat.use_nodes=True
    nodes=mat.node_tree.nodes; links=mat.node_tree.links
    bsdf=nodes.get('Principled BSDF')
    bsdf.inputs['Metallic'].default_value=metallic
    maps=brush_maps(kind,1024 if kind in ('stone','bark') else 512)
    for index,(label,image) in enumerate(zip(('Base Color','Roughness','Normal'),maps)):
        n=nodes.new('ShaderNodeTexImage'); n.image=image; n.label=label+' — editable painted source'
        n.location=(-580,300-index*250)
        if label=='Normal':
            normal=nodes.new('ShaderNodeNormalMap'); normal.inputs['Strength'].default_value=.48
            normal.location=(-240,-190); links.new(n.outputs['Color'],normal.inputs['Color']); links.new(normal.outputs['Normal'],bsdf.inputs['Normal'])
        else: links.new(n.outputs['Color'],bsdf.inputs[label])
    return mat

STONE=painted_material('FB_WarmFacetedStone','stone')
BARK=painted_material('FB_TwistedPaintedBark','bark')
MOSS=painted_material('FB_OliveMoss','moss')
LEAF=painted_material('FB_SageGrass','leaf')
METAL=painted_material('FB_OldBearingBronze','bronze',.63)
ENERGY=bpy.data.materials.new('FB_InlaidCyanEnergy'); ENERGY.use_nodes=True
eb=ENERGY.node_tree.nodes.get('Principled BSDF')
eb.inputs['Base Color'].default_value=(.018,.33,.34,1)
eb.inputs['Metallic'].default_value=.25; eb.inputs['Roughness'].default_value=.31
eb.inputs['Emission Color'].default_value=(.013,.60,.62,1); eb.inputs['Emission Strength'].default_value=.55

def finish(obj,mat,parent=None):
    move_to(obj,model_collection); model_objects.append(obj)
    obj.data.materials.append(mat)
    if parent is not None:
        # Geometry authored in global metre coordinates; keep exact global placement.
        obj.parent=parent; obj.matrix_parent_inverse=parent.matrix_world.inverted()
    return obj

def uv_faces(obj, density=.36):
    mesh=obj.data
    uv=mesh.uv_layers.new(name='PaintUV') if not mesh.uv_layers else mesh.uv_layers[0]
    uv.name='PaintUV'
    mesh.uv_layers.active_index=0
    uv.active_render=True
    offset=np.array([random.random(),random.random()])
    is_stone=bool(mesh.materials and mesh.materials[0]==STONE)
    tile_column=random.randrange(4) if is_stone else 0
    bounds=[(min(v.co[i] for v in mesh.vertices),max(v.co[i] for v in mesh.vertices)) for i in range(3)] if is_stone else []
    for p in mesh.polygons:
        n=p.normal; axis=max(range(3),key=lambda k:abs(n[k]))
        axes=[i for i in range(3) if i!=axis]
        for li in p.loop_indices:
            co=mesh.vertices[mesh.loops[li].vertex_index].co
            if is_stone:
                row=2 if n.z>.18 else (0 if n.z<-.55 else (3 if abs(n.x)>.88 else 1))
                values=[(co[ax]-bounds[ax][0])/max(.001,bounds[ax][1]-bounds[ax][0]) for ax in axes]
                uv.data[li].uv=((tile_column+.025+values[0]*.95)/4,(row+.025+values[1]*.95)/4)
            else:
                uv.data[li].uv=(co[axes[0]]*density+offset[0],co[axes[1]]*density+offset[1])

def bevel(obj,width=.05):
    bpy.context.view_layer.objects.active=obj
    mod=obj.modifiers.new('Editable_chiselled_edge','BEVEL'); mod.width=width; mod.segments=1
    mod.affect='EDGES'
    bpy.ops.object.modifier_apply(modifier=mod.name)
    obj.data.update()

def block(name,loc,scale,mat=STONE,jitter=.045,bevel_width=.06):
    x,y,z=[s/2 for s in scale]
    verts=[(a*x+random.uniform(-jitter,jitter),b*y+random.uniform(-jitter,jitter),c*z+random.uniform(-jitter,jitter)) for a,b,c in ((-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1))]
    mesh=bpy.data.meshes.new(name+'_mesh'); mesh.from_pydata(verts,[],[(0,3,2,1),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),(4,5,6,7)]); mesh.update()
    obj=bpy.data.objects.new(name,mesh); model_collection.objects.link(obj); obj.location=loc
    model_objects.append(obj); mesh.materials.append(mat)
    if bevel_width: bevel(obj,bevel_width)
    uv_faces(obj)
    return obj

def annulus(name,r0,r1,a0,a1,zcenter,depth,ycenter=0,mat=STONE,parent=None,segments=6,chamfer=.035):
    verts=[]
    for y in (ycenter-depth/2,ycenter+depth/2):
        for r in (r0,r1):
            for i in range(segments+1):
                a=a0+(a1-a0)*i/segments
                verts.append((math.cos(a)*r,y,zcenter+math.sin(a)*r))
    n=segments+1; faces=[]
    for i in range(segments):
        # -Y front, +Y back, inner, outer.
        faces.extend([(i,i+1,n+i+1,n+i),(2*n+i,3*n+i,3*n+i+1,2*n+i+1),(i,2*n+i,2*n+i+1,i+1),(n+i,n+i+1,3*n+i+1,3*n+i)])
    faces.extend([(0,n,3*n,2*n),(n-1,3*n-1,4*n-1,2*n-1)])
    # Front is -Y; reverse the strip loops to give the closed annulus outward normals.
    faces=[tuple(reversed(f)) for f in faces]
    mesh=bpy.data.meshes.new(name+'_mesh'); mesh.from_pydata(verts,[],faces); mesh.update()
    obj=bpy.data.objects.new(name,mesh); model_collection.objects.link(obj); model_objects.append(obj); mesh.materials.append(mat)
    if chamfer: bevel(obj,chamfer)
    uv_faces(obj,.48)
    if parent is not None:
        obj.parent=parent; obj.matrix_parent_inverse=parent.matrix_world.inverted()
    return obj

rotor=bpy.data.objects.new('Rotor',None); model_collection.objects.link(rotor)
rotor.empty_display_type='CIRCLE'; rotor.empty_display_size=2.9
rotor.location=(0,0,5.2); rotor.rotation_mode='XYZ'
rotor['rotation_axis_blender']='Y'; rotor['rotation_axis_godot']='Z'
rotor['inner_radius_m']=2.2; rotor['outer_radius_m']=2.9; rotor['depth_m']=.7
rotor['pivot_blender_m']=[0.0,0.0,5.2]
bpy.context.view_layer.update()

# Rotation body: genuine hollow annulus, assembled from eighteen face-chamfered stones.
for k in range(18):
    a0=2*math.pi*k/18+.005; a1=2*math.pi*(k+1)/18-.005
    annulus('Rotor_Stone_%02d'%k,2.2,2.9,a0,a1,5.2,.56,parent=rotor,segments=5,chamfer=.025)
    # Actual recessed channel. The shallow core sits behind two raised face rails.
    for face in (-1,1):
        annulus('Rotor_InnerRail_%02d_%s'%(k,face),2.2,2.505,a0,a1,5.2,.07,face*.315,STONE,rotor,5,.020)
        annulus('Rotor_OuterRail_%02d_%s'%(k,face),2.605,2.9,a0,a1,5.2,.07,face*.315,STONE,rotor,5,.020)
        annulus('Rotor_Inlay_%02d_%s'%(k,'F' if face<0 else 'B'),2.525,2.585,a0+.006,a1-.006,5.2,.020,face*.291,ENERGY,rotor,5,.006)
        # Broken highlighted scored rune dashes near outer rim, every third stone.
        if k%3==0:
            amid=(a0+a1)/2
            annulus('Rotor_Rune_%02d_%s'%(k,face),2.73,2.79,amid-.045,amid+.045,5.2,.018,face*.355,ENERGY,rotor,2,.004)

# Three deliberate stair levels; individual pavers instead of a seamless plinth.
for level,(z,ycenter,depth,width) in enumerate(((.16,-.35,3.8,8.5),(.43,.05,3.0,7.8),(.70,.35,2.2,7.1))):
    count=9-level
    for i in range(count):
        pw=width/count
        block('Stair_L%d_Paver_%02d'%(level+1,i),(-width/2+pw*(i+.5),ycenter,z),(pw-.035,depth,.30),jitter=.035,bevel_width=.055)

# Recessed courses, wider collars, broken crowns: recognisable layered outer frame.
for side in (-1,1):
    x=side*3.54
    block('Foot_%s'%side,(x,.16,1.13),(1.55,1.95,.58),bevel_width=.10)
    for k in range(8):
        z=1.66+k*.78
        width=1.02+(.04 if k%2==0 else 0)
        obj=block('Pillar_%s_Course_%02d'%(side,k),(x+random.uniform(-.035,.035),.16,z),(width,1.38+random.uniform(-.07,.07),.74),jitter=.045,bevel_width=.08)
        obj.rotation_euler[2]=random.uniform(-.018,.018)
        # Offset chips and inset blocks break the regular pillar grid.
        if k in (1,4,6):
            block('Pillar_%s_FaceChip_%s'%(side,k),(x+side*.23,-.59,z+.05),(.75,.13,.39),jitter=.07,bevel_width=.035)
    block('Collar_%s_Under'%side,(x,.13,7.84),(1.60,1.72,.26),bevel_width=.055)
    block('Collar_%s_Main'%side,(x,.13,8.07),(1.55,1.91,.25),bevel_width=.055)
    block('Crown_%s_Main'%side,(x,.10,8.54),(1.35,1.58,.66),jitter=.10,bevel_width=.10)
    block('Crown_%s_Broken'%side,(x+side*.20,.24,9.03),(.77,1.25,.43),jitter=.11,bevel_width=.06)

# High masonry arch: static inner radius 3.19 exceeds rotor radius by 0.29m.
for k in range(9):
    a0=math.radians(24+132*k/9)+.004
    a1=math.radians(24+132*(k+1)/9)-.004
    annulus('OuterArch_Voussoir_%02d'%k,3.19,3.97,a0,a1,5.2,1.22,.17,segments=3,chamfer=.075)
block('Keystone_Crown',(0,-.01,9.35),(1.10,1.58,.94),jitter=.10,bevel_width=.09)
block('Keystone_Front',(0,-.66,8.98),(.78,.28,1.22),jitter=.055,bevel_width=.065)

def cylinder(name,loc,radius,depth,mat,vertices=12):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=radius,depth=depth,end_fill_type='NGON',location=loc,rotation=(math.pi/2,0,0))
    obj=bpy.context.object; obj.name=name; finish(obj,mat)
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    bevel(obj,.025); uv_faces(obj,.8)
    return obj

# Bearing housings overlap the ring only in projection. Axial gap >=0.09m.
# No axle traverses the opening. The three stations hold the OUTSIDE of the rim.
for k,a in enumerate((math.pi/2,7*math.pi/6,11*math.pi/6)):
    x=math.cos(a)*2.72; z=5.2+math.sin(a)*2.72
    for facing in (-1,1):
        obj=block('Bearing_%d_%s_Housing'%(k,facing),(x,facing*.68,z),(.72,.42,1.02),jitter=.025,bevel_width=.085)
        obj.rotation_euler[1]=a-math.pi/2
        cylinder('Bearing_%d_%s_Bronze'%(k,facing),(x,facing*.92,z),.255,.085,METAL)
        cylinder('Bearing_%d_%s_Cyan'%(k,facing),(x,facing*.975,z),.161,.047,ENERGY)
    # Radial support outside swept radius, also axially separated.
    r=3.27
    for facing in (-1,1):
        obj=block('Bearing_%d_%s_Brace'%(k,facing),(math.cos(a)*r,facing*.69,5.2+math.sin(a)*r),(.37,.43,.74),mat=METAL,jitter=.012,bevel_width=.035)
        obj.rotation_euler[1]=a-math.pi/2

def tube(name,points,radii,mat=BARK,sides=9):
    pts=[Vector(p) for p in points]; verts=[]
    for i,p in enumerate(pts):
        tangent=(pts[min(len(pts)-1,i+1)]-pts[max(0,i-1)]).normalized()
        axis=Vector((0,1,0)) if abs(tangent.y)<.9 else Vector((1,0,0))
        u=tangent.cross(axis).normalized(); v=tangent.cross(u).normalized()
        for j in range(sides):
            a=2*math.pi*j/sides+.25*math.sin(i*.8)
            r=radii[i]*(1+.13*math.sin(j*2.3+i*.55))
            verts.append(p+(u*math.cos(a)+v*math.sin(a))*r)
    faces=[]
    for i in range(len(pts)-1):
        for j in range(sides): faces.append((i*sides+j,i*sides+(j+1)%sides,(i+1)*sides+(j+1)%sides,(i+1)*sides+j))
    faces.append(tuple(reversed(range(sides)))); faces.append(tuple((len(pts)-1)*sides+j for j in range(sides)))
    mesh=bpy.data.meshes.new(name+'_mesh'); mesh.from_pydata(verts,[],faces); mesh.update()
    obj=bpy.data.objects.new(name,mesh); model_collection.objects.link(obj); model_objects.append(obj); mesh.materials.append(mat)
    uv=mesh.uv_layers.new(name='PaintUV')
    mesh.uv_layers.active_index=0
    uv.active_render=True
    for p in mesh.polygons:
        for li in p.loop_indices:
            vi=mesh.loops[li].vertex_index
            uv.data[li].uv=((vi%sides)/sides*1.3,(vi//sides)/max(1,len(pts)-1)*3.2)
    return obj

# Thick paired roots twist up both piers. The ring slab and its sweep stay clear.
for side in (-1,1):
    for strand in range(3):
        pts=[]; radii=[]
        for i in range(31):
            t=i/30; angle=t*math.pi*2.1+strand*2.0+side*.8
            ca,sa=math.cos(angle),math.sin(angle)
            # A rounded rectangular path hugs the real squared pillar. An ellipse
            # would disappear inside each corner, producing disconnected root stubs.
            radius=(abs(ca/.62)**6+abs(sa/.94)**6)**(-1/6)
            px=side*(3.55+radius*ca)
            py=.10+radius*sa
            pz=.45+t*8.72
            # Roots near the rotating envelope pass in front/behind with axial clearance.
            rr=math.hypot(px,pz-5.2)
            if rr<3.55:
                # All inner-arc roots go around the front of the mechanism. Merely
                # choosing +/-Y per point would make an interpolated segment cross
                # through the rotating slab where the sign changes.
                py=-max(abs(py),.98)
            taper=min(1.0,max(.08,(1-t)/.16))
            pts.append((px,py,pz)); radii.append((.23+.05*math.sin(t*4))*((1-.38*t) if strand!=1 else 1)*taper)
        tube('Root_Pier_%s_%s'%(side,strand),pts,radii,sides=10)
    # Buttress roots spread into stair edges and terminate organically.
    for branch in range(5):
        start=Vector((side*(3.50+random.uniform(-.27,.26)),random.uniform(-.20,.40),3.2+random.uniform(-.45,.65)))
        end=Vector((side*random.uniform(2.95,4.08),random.uniform(-2.02,1.42),.16))
        pts=[]
        for i in range(17):
            t=i/16; p=start.lerp(end,t)
            p.x+=.18*math.sin(t*math.pi*3+branch)
            p.y-=.60*math.sin(t*math.pi)
            pts.append(p)
        tube('Root_Buttress_%s_%s'%(side,branch),pts,[.22*(1-i/17)+.025 for i in range(17)],sides=8)
    # Bark brush texture carries fine ridges. No freestanding cut-ended rib rods.

# Overhead tangles sit on the crown; asymmetry breaks a manufactured-perfect silhouette.
for j in range(3):
    pts=[]
    for i in range(31):
        t=i/30; x=-3.55+7.1*t
        z=8.68+.68*math.sin(math.pi*t)+.13*math.sin(t*17+j)
        pts.append((x,.34+j*.22+.13*math.sin(t*12+j),z))
    tube('Root_Crown_%s'%j,pts,[.15+.055*math.sin(math.pi*i/30) for i in range(31)],sides=8)

def moss(name,loc,scale):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=1,location=loc)
    obj=bpy.context.object; obj.name=name; obj.scale=scale; finish(obj,MOSS)
    uv_faces(obj,.7)
    return obj

def grass(name,loc,size):
    verts=[]; faces=[]
    for b in range(random.randint(5,8)):
        a=random.random()*math.tau; h=size*random.uniform(.65,1.5)
        base=Vector(loc)+Vector((math.cos(a)*size*.23,math.sin(a)*size*.23,0))
        side=Vector((math.cos(a),math.sin(a),0))*size*.15
        tip=base+Vector((math.cos(a)*h*.35,math.sin(a)*h*.35,h))
        middle=base.lerp(tip,.55)+Vector((0,0,h*.10))
        off=len(verts); verts.extend((base-side,base+side,middle+side*.45,middle-side*.45,tip))
        faces.extend(((off,off+1,off+2,off+3),(off+3,off+2,off+4)))
    mesh=bpy.data.meshes.new(name+'_mesh'); mesh.from_pydata(verts,[],faces); mesh.update()
    obj=bpy.data.objects.new(name,mesh); model_collection.objects.link(obj); model_objects.append(obj); mesh.materials.append(LEAF); uv_faces(obj,.8)

# Moss sticks to ledges and root footings, never floats throughout the doorway.
for i in range(115):
    side=random.choice((-1,1))
    x=side*random.uniform(2.96,4.14)
    y=random.uniform(-1.45,1.13)
    z=1.45 if abs(y)<1 and i%2==0 else (.86 if abs(y)<1 else .29)
    s=random.uniform(.10,.32)
    moss('Moss_Foot_%03d'%i,(x,y,z),(s,s*.83,random.uniform(.035,.10)))
    if i%3==0: grass('Grass_Foot_%03d'%i,(x,y,z+.03),random.uniform(.14,.27))
for i in range(75):
    side=random.choice((-1,1)); level=random.choice((2.05,2.84,3.62,4.40,5.18,5.96,6.74,7.52,8.23,8.91))
    x=side*random.uniform(3.03,4.02); y=random.choice((-1,1))*random.uniform(.63,.82)
    s=random.uniform(.08,.22)
    moss('Moss_Ledge_%03d'%i,(x,y,level),(s,s*.65,.045))
    if i%5==0: grass('Grass_Ledge_%03d'%i,(x,y,level),.14)
for side in (-1,1):
    for k in range(7):
        z=2.05+k*.78; x=side*3.54
        pts=[(x-.43+i*.215,-.59-.028*math.sin(i*2+k),z+.018*math.sin(i*3+k)) for i in range(5)]
        tube('Moss_Crevice_%s_%s'%(side,k),pts,[.034,.058,.045,.061,.028],MOSS,5)
        if k%2==0: grass('Grass_Crevice_%s_%s'%(side,k),pts[2],.16)
for i in range(22):
    # Place on an actual crown-root surface; independent approximate heights can
    # float above the arch when seen from the back.
    t=random.uniform(.04,.96); j=random.randrange(3)
    x=-3.55+7.1*t
    y=.34+j*.22+.13*math.sin(t*12+j)
    z=8.68+.68*math.sin(math.pi*t)+.13*math.sin(t*17+j)
    radius=.15+.055*math.sin(math.pi*t)
    moss('Moss_Crown_%03d'%i,(x,y,z+radius*.82),(.22,.15,.06))
for i in range(30):
    x=random.uniform(-3.1,3.1); level=random.choice((0,1,2))
    y=(-2.22,-1.46,-.72)[level]+random.uniform(-.04,.04)
    z=(.32,.59,.86)[level]
    moss('Moss_StepSeam_%03d'%i,(x,y,z),(.14,.07,.025))
    if i%3==0: grass('Grass_StepSeam_%03d'%i,(x,y,z),.12)

# Readable scattered chipped stones only on external plinth margins.
for i in range(21):
    side=random.choice((-1,1)); x=side*random.uniform(3.25,4.15); y=random.uniform(-1.8,1.2)
    block('Loose_ChiselFragment_%02d'%i,(x,y,.35),(random.uniform(.12,.27),random.uniform(.15,.29),random.uniform(.09,.18)),jitter=.045,bevel_width=.02)

# Source objects stay individually editable, with packed maps and documented groups.
for obj in model_objects:
    obj['asset_family']='F-B'
    obj['kinematic_group']='rotor' if obj.parent==rotor else 'static'
    if obj.type=='MESH':
        for polygon in obj.data.polygons: polygon.use_smooth=False

# Isolated studio. No studio lights, camera or floor are exported into the game model.
floor_mat=bpy.data.materials.new('Studio_WarmGrey'); floor_mat.diffuse_color=(.29,.31,.30,1)
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.045)); floor=bpy.context.object; floor.name='Studio_Floor'; move_to(floor,studio_collection); floor.data.materials.append(floor_mat)
world=bpy.data.worlds.new('FB_SoftStudio'); scene.world=world; world.use_nodes=True
world.node_tree.nodes['Background'].inputs[0].default_value=(.48,.52,.56,1)
world.node_tree.nodes['Background'].inputs[1].default_value=.45
def area(name,loc,energy,size,color):
    data=bpy.data.lights.new(name,'AREA'); data.energy=energy; data.shape='DISK'; data.size=size; data.color=color
    obj=bpy.data.objects.new(name,data); studio_collection.objects.link(obj); obj.location=loc; obj.rotation_euler=(Vector((0,0,4.5))-obj.location).to_track_quat('-Z','Y').to_euler()
area('Key_Softbox',(-6,-8,14),2200,7,(1,.88,.69))
area('Fill_Cool',(7,-3,10),1450,6,(.68,.85,1))
area('Rim_Crown',(1,6,13),2300,5,(1,.91,.73))
camera_data=bpy.data.cameras.new('FB_InspectionCamera'); camera=bpy.data.objects.new('FB_InspectionCamera',camera_data); studio_collection.objects.link(camera); scene.camera=camera
camera_data.type='ORTHO'; camera_data.ortho_scale=12.8
def camera_view(location,target=(0,0,4.6)):
    camera.location=location; camera.rotation_euler=(Vector(target)-camera.location).to_track_quat('-Z','Y').to_euler()
camera_view((12,-20,12.6))
scene.render.engine='CYCLES'; scene.cycles.samples=32; scene.cycles.use_denoising=True
scene.render.resolution_x=1200; scene.render.resolution_y=1200; scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'; scene.render.film_transparent=False
scene.view_settings.view_transform='AgX'
scene.view_settings.look='AgX - Medium High Contrast'
scene.render.filepath=str(ART/'temple_gate_preview.png')

# Collect audit before making temporary export copies.
bpy.context.view_layer.update()
def clip_y(poly, bound, keep_greater):
    result=[]
    for start,end in zip(poly,poly[1:]+poly[:1]):
        sin=(start.y>=bound) if keep_greater else (start.y<=bound)
        ein=(end.y>=bound) if keep_greater else (end.y<=bound)
        if sin: result.append(start)
        if sin!=ein:
            result.append(start+(end-start)*((bound-start.y)/(end.y-start.y)))
    return result

def swept_overlap(obj, margin=0):
    # Clip each real triangle to the rotor's axial slab, then solve the radial
    # interval of that convex projection. This checks complete faces, not vertices.
    mesh=obj.data; mesh.calc_loop_triangles()
    for tri in mesh.loop_triangles:
        poly=[obj.matrix_world@mesh.vertices[i].co for i in tri.vertices]
        poly=clip_y(poly,-.365-margin,True)
        if len(poly)<3: continue
        poly=clip_y(poly,.365+margin,False)
        if len(poly)<3: continue
        flat=[Vector((p.x,p.z-5.2)) for p in poly]
        minimum=1e30; maximum=max(p.length for p in flat)
        signs=[]
        for a,b in zip(flat,flat[1:]+flat[:1]):
            d=b-a
            t=max(0,min(1,-a.dot(d)/max(1e-12,d.length_squared)))
            minimum=min(minimum,(a+t*d).length)
            cross=d.x*(-a.y)-d.y*(-a.x)
            if abs(cross)>1e-7: signs.append(cross>0)
        if len(signs)>0 and (all(signs) or not any(signs)):
            # A nondegenerate projected face containing the circle centre.
            area=sum(a.x*b.y-a.y*b.x for a,b in zip(flat,flat[1:]+flat[:1]))
            if abs(area)>1e-7: minimum=0
        if minimum < 2.9+margin-1e-5 and maximum > 2.2-margin+1e-5:
            return True
    return False

overlaps=[o.name for o in model_objects if o.parent!=rotor and swept_overlap(o)]
clearance_hits=[o.name for o in model_objects if o.parent!=rotor and swept_overlap(o,.04)]
print('ROTOR_SWEEP_CHECK '+json.dumps({'overlaps':overlaps,'within_40mm_margin':clearance_hits}))
assert not overlaps, 'STATIC ROTOR OVERLAP: '+str(overlaps)
points=[o.matrix_world@Vector(v) for o in model_objects for v in o.bound_box]
mins=[min(p[i] for p in points) for i in range(3)]; maxs=[max(p[i] for p in points) for i in range(3)]
triangle_count=sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in model_objects)
audit={'asset':'temple_gate','source_reference':'references/v3/concepts/F-B.png','source_objects':len(model_objects),'triangles_source':triangle_count,'materials':sorted({m.name for o in model_objects for m in o.data.materials}),'bounds_blender_m':{'min':mins,'max':maxs,'dimensions':[maxs[i]-mins[i] for i in range(3)]},'rotor':{'pivot_blender':[0,0,5.2],'axis_blender':'Y','axis_godot':'Z','inner_diameter_m':4.4,'outer_diameter_m':5.8,'stone_depth_m':.7},'notes':['Back is inferred from single front-oblique concept.','No collision geometry included; engine integrator owns collision and interaction.','Offline studio preview is not an engine screenshot.','Source texture brushes are deterministic original generated artwork.']}
audit['rotor_sweep']={'static_intersections':overlaps,'static_within_40mm_margin':clearance_hits,'method':'Triangle axial slab clipping followed by projected convex polygon radial interval; entire swept annulus, including 0.365m axial envelope.'}
assert triangle_count<60000, triangle_count
assert len(audit['materials'])<=8
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'temple_gate.blend'))

# Explicit GLB export. Merge by material only within static or moving group.
export_collection=bpy.data.collections.new('TEMP_EXPORT_MERGED'); scene.collection.children.link(export_collection)
export_rotor=bpy.data.objects.new('Rotor',None); export_collection.objects.link(export_rotor)
# Blender names are unique: preserve literal export node name by renaming editable parent.
rotor.name='Editable_Rotor'; export_rotor.name='Rotor'; export_rotor.location=(0,0,5.2)
for key in rotor.keys(): export_rotor[key]=rotor[key]
bpy.context.view_layer.update()
export_objects=[]
for moving in (False,True):
    materials=sorted({o.data.materials[0].name for o in model_objects if (o.parent==rotor)==moving})
    for material_name in materials:
        originals=[o for o in model_objects if (o.parent==rotor)==moving and o.data.materials[0].name==material_name]
        copies=[]
        for original in originals:
            new=original.copy(); new.data=original.data.copy(); new.parent=None
            new.matrix_world=original.matrix_world.copy(); export_collection.objects.link(new); copies.append(new)
        bpy.ops.object.select_all(action='DESELECT')
        for obj in copies: obj.select_set(True)
        bpy.context.view_layer.objects.active=copies[0]; bpy.ops.object.join()
        merged=bpy.context.object
        merged.name=('Rotor_' if moving else 'Static_')+material_name.removeprefix('FB_')
        bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
        if moving:
            merged.parent=export_rotor; merged.matrix_parent_inverse=export_rotor.matrix_world.inverted()
        export_objects.append(merged)
bpy.ops.object.select_all(action='DESELECT')
for obj in export_objects+[export_rotor]: obj.select_set(True)
bpy.context.view_layer.objects.active=export_rotor
audit['export_nodes']=[o.name for o in export_objects]+['Rotor']
bpy.ops.export_scene.gltf(filepath=str(OUT/'temple_gate.glb'),export_format='GLB',use_selection=True,export_yup=True,export_apply=True,export_extras=True,export_animations=False,export_cameras=False,export_lights=False,export_materials='EXPORT')
with open(ART/'temple_gate_audit.json','w',encoding='utf-8') as f: json.dump(audit,f,ensure_ascii=False,indent=2)
for obj in export_objects+[export_rotor]: bpy.data.objects.remove(obj,do_unlink=True)
bpy.data.collections.remove(export_collection)
rotor.name='Rotor'

# Render the actual editable model. Back and front views make the through-opening explicit.
scene.render.filepath=str(ART/'temple_gate_preview.png'); bpy.ops.render.render(write_still=True)
scene.cycles.samples=24; scene.render.resolution_x=900; scene.render.resolution_y=900
camera_view((0,-22,5.2),(0,0,4.8)); camera_data.ortho_scale=11.4
scene.render.filepath=str(ART/'temple_gate_front.png'); bpy.ops.render.render(write_still=True)
camera_view((-12,18,11.0)); camera_data.ortho_scale=12.7
scene.render.filepath=str(ART/'temple_gate_back.png'); bpy.ops.render.render(write_still=True)
print('FB_GATE_COMPLETE '+json.dumps(audit,ensure_ascii=False))
