"""Independent, deterministic F-B second asset kit. Blender 5.2, metres, +Z up.

Usage: blender --background --factory-startup --threads 2 --python-exit-code 1
       --python build_fantasy_kit.py -- terrace|roots [--no-render]
No shared project imports. Source meshes stay editable; explicit GLB only.
"""
import bpy, bmesh, math, random, json, sys, hashlib
import numpy as np
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree

SOURCE=Path(__file__).resolve().parent
ROOT=SOURCE.parents[2]
OUT=ROOT/'assets/v3/fantasy_kit'
ART=ROOT/'artifacts/v3/art/fantasy_kit'
args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else ['terrace']
KIND=args[0]
NAME='rootstone_terrace' if KIND=='terrace' else 'photosensitive_roots'
TEX=SOURCE/'textures'/NAME
for p in (SOURCE,OUT,ART,TEX): p.mkdir(parents=True,exist_ok=True)
SEED=1707 if KIND=='terrace' else 4223
random.seed(SEED); rng=np.random.default_rng(SEED)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
for d in list(bpy.data.materials): bpy.data.materials.remove(d)
scene=bpy.context.scene
scene.unit_settings.system='METRIC'; scene.unit_settings.scale_length=1
scene.render.engine='CYCLES'; scene.cycles.device='CPU'; scene.cycles.samples=32
scene.cycles.use_denoising=True
scene.render.threads_mode='FIXED'; scene.render.threads=2
scene.render.resolution_percentage=100
scene.world.color=(.24,.24,.24)
scene.view_settings.view_transform='AgX'
scene.view_settings.look='AgX - Medium High Contrast'
model=bpy.data.collections.new('Editable_'+NAME); scene.collection.children.link(model)
studio=bpy.data.collections.new('Studio_NOT_EXPORTED'); scene.collection.children.link(studio)
objects=[]; pivots=[]

def move(obj,collection):
    for c in list(obj.users_collection): c.objects.unlink(obj)
    collection.objects.link(obj)

def save_map(name,arr,noncolor=False):
    h,w=arr.shape[:2]
    if arr.ndim==2: arr=np.repeat(arr[:,:,None],3,axis=2)
    rgba=np.ones((h,w,4),dtype=np.float32); rgba[:,:,:3]=np.clip(arr,0,1)
    img=bpy.data.images.new(name,width=w,height=h,alpha=False)
    if noncolor: img.colorspace_settings.name='Non-Color'
    img.pixels.foreach_set(rgba.ravel()); img.file_format='PNG'; img.filepath_raw=str(TEX/(name+'.png')); img.save(); img.pack()
    return img

def maps(kind,size=512):
    y,x=np.mgrid[0:size,0:size].astype(np.float32)/size
    bases={'stone':(.47,.45,.39),'bark':(.30,.16,.078),'moss':(.26,.31,.075),'mud':(.34,.265,.158),'leaf':(.285,.365,.15),'core':(.025,.41,.35)}
    col=np.tile(np.array(bases[kind]),(size,size,1))
    height=np.full((size,size),.5,dtype=np.float32)
    if kind=='stone':
        # Group entire faces, not camouflage flecks: rows shadow/main/top/cool side.
        cell=size//4
        colors=np.array([[.29,.32,.31],[.37,.365,.325],[.47,.445,.375],[.335,.365,.345]])
        for row in range(4):
            for c in range(4):
                ys=slice(row*cell,(row+1)*cell); xs=slice(c*cell,(c+1)*cell)
                patch=np.tile(colors[row]+np.array([.014,.006,-.005])*(c-1.5),(cell,cell,1))
                yy,xx=np.mgrid[0:cell,0:cell]/cell
                patch+=(.009*np.sin(xx*7+yy*5))[:,:,None]
                for j in range(16):
                    cx,cy=rng.uniform(.05,.95,2); a=rng.uniform(-.6,.6)
                    u=(xx-cx)*math.cos(a)+(yy-cy)*math.sin(a); v=-(xx-cx)*math.sin(a)+(yy-cy)*math.cos(a)
                    mask=(abs(u)<rng.uniform(.13,.33))&(abs(v)<rng.uniform(.018,.055))
                    patch[mask]+=np.array([.054,.042,.024])*(1 if j%2 else -1)
                hpatch=np.full((cell,cell),.5,dtype=np.float32)
                # Deliberate, readable geological seams survive the real oblique camera.
                # Three broad strata on walls, several irregular stress fractures on top.
                for j in range(3):
                    line=(.22+j*.27+.017*np.sin(xx*(12+j*4)+c)+.012*np.sin(xx*29+j))
                    if row==2: line+=(xx-.5)*(.22 if j%2 else -.18)
                    distance=yy-line
                    active=np.sin(xx*(8+j*2)+j*2.1+c*.7)>-.45
                    shadow=(abs(distance)<(.006 if row==2 else .009))&active
                    shoulder=(abs(distance)<(.024 if row==2 else .040))&active
                    warm=(distance>.009)&(distance<.023)&active
                    patch[shoulder]*=.94
                    patch[shadow]*=.76
                    patch[warm]+=np.array([.045,.038,.021])
                    hpatch[shadow]-=.060
                    for split in range(2):
                        crackx=.19+split*.54+.09*(yy-line)+.011*np.sin(yy*39+j)
                        crack=(abs(xx-crackx)<.004)&(abs(distance)<.11)&active
                        patch[crack]*=.77;hpatch[crack]-=.045
                col[ys,xs]=patch
                height[ys,xs]=hpatch
        rough=.9
    elif kind=='leaf':
        # Broad directional paint with a readable tapered vein pattern, UV mapped to each blade.
        center=.5+.025*np.sin(y*5)
        col+=(.025*np.cos(x*math.tau*2)+.014*np.sin(y*math.tau*4))[:,:,None]
        for j in range(55):
            cx,cy=rng.uniform(0,1,2); length=rng.uniform(.08,.24)
            u=x-cx; v=y-cy-u*(1 if cx<.5 else -1)*.65
            mask=(abs(u)<length)&(abs(v)<rng.uniform(.005,.024))
            tint=np.array([.04,.035,.012])*(1 if j%2 else -1)
            col[mask]+=tint
        vein=abs(x-center)<(.008*(1-y)+.002)
        for v0 in (.14,.30,.46,.62,.78):
            for side in (-1,1):
                dx=(x-center)*side
                line=v0+dx*.70+.17*dx*dx
                vein|=(dx>0)&(dx<.42*(1-v0*.6))&(abs(y-line)<.0035)
        edge=(x<.024)|(x>.976)
        col[vein|edge]=(.58,.54,.255); height[vein]=.57
        rough=.79
    else:
        variation=.017*np.sin(x*math.tau*3+y*math.tau*2)+.012*np.sin(x*math.tau*9-y*math.tau*4)
        col+=variation[:,:,None]; height+=variation*.2
        for j in range(80 if kind=='bark' else 36):
            cx,cy=rng.uniform(0,1,2); a=rng.uniform(1.42,1.72) if kind=='bark' else rng.uniform(-2,2)
            u=(x-cx)*math.cos(a)+(y-cy)*math.sin(a); v=-(x-cx)*math.sin(a)+(y-cy)*math.cos(a)
            mask=(abs(u)<rng.uniform(.04,.19))&(abs(v)<rng.uniform(.004,.023))
            tint=np.array([.046,.032,.015])*(1 if j%3 else -1)
            col[mask]+=tint; height[mask]+=.008 if j%2 else -.008
        if kind=='bark':
            grain=np.sin(math.tau*(x*8+.13*np.sin(y*math.tau*2)))
            grooves=np.maximum(0,(grain-.92)*3)*(.45+.55*np.sin(y*math.tau*3)**2)
            col-=grooves[:,:,None]*np.array([.07,.045,.02]); height-=grooves*.05
        if kind=='core':
            streak=np.maximum(0,np.cos(math.tau*(x*5+.08*np.sin(y*math.tau))))**12
            col+=streak[:,:,None]*np.array([.03,.21,.19])
        rough={'bark':.86,'moss':.96,'mud':.93,'core':.5}[kind]
    gy,gx=np.gradient(height); normal=np.dstack((-gx*2,-gy*2,np.ones_like(gx)))
    normal/=np.linalg.norm(normal,axis=2)[:,:,None]
    prefix='FKit_'+kind
    return [save_map(prefix+'_BaseColor',col),save_map(prefix+'_Roughness',rough+(height-.5)*.4,True),save_map(prefix+'_Normal',normal*.5+.5,True)]

def material(kind):
    m=bpy.data.materials.new('FK_'+kind.title()); m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF'); p.inputs['Roughness'].default_value=.85
    for index,(input_name,img) in enumerate(zip(('Base Color','Roughness','Normal'),maps(kind,1024 if kind in ('stone','bark','leaf') else 512))):
        n=m.node_tree.nodes.new('ShaderNodeTexImage'); n.image=img; n.location=(-600,200-index*220)
        if input_name=='Normal':
            normal=m.node_tree.nodes.new('ShaderNodeNormalMap'); normal.inputs['Strength'].default_value=.4
            m.node_tree.links.new(n.outputs['Color'],normal.inputs['Color']); m.node_tree.links.new(normal.outputs['Normal'],p.inputs['Normal'])
        else: m.node_tree.links.new(n.outputs['Color'],p.inputs[input_name])
    if kind=='core':
        p.inputs['Base Color'].default_value=(.012,.20,.15,1)
        p.inputs['Emission Color'].default_value=(.012,.40,.27,1); p.inputs['Emission Strength'].default_value=.22
    return m

BARK=material('bark'); MOSS=material('moss')
STONE=material('stone') if KIND=='terrace' else None
MUD=material('mud') if KIND=='terrace' else None
LEAF=material('leaf') if KIND=='roots' else None
CORE=material('core') if KIND=='roots' else None

def mesh_obj(name,verts,faces,mat,parent=None):
    mesh=bpy.data.meshes.new(name+'_mesh'); mesh.from_pydata(verts,[],faces); mesh.update()
    bm=bmesh.new(); bm.from_mesh(mesh); bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces)); bm.to_mesh(mesh); bm.free()
    obj=bpy.data.objects.new(name,mesh); model.objects.link(obj); objects.append(obj); mesh.materials.append(mat)
    if parent: obj.parent=parent
    return obj

def uv_faces(obj,density=.38):
    mesh=obj.data
    while mesh.uv_layers: mesh.uv_layers.remove(mesh.uv_layers[0])
    uv=mesh.uv_layers.new(name='PaintUV'); mesh.uv_layers.active_index=0; uv.active_render=True
    bounds=[(min(v.co[i] for v in mesh.vertices),max(v.co[i] for v in mesh.vertices)) for i in range(3)]
    tile=random.randrange(4); off=(random.random(),random.random())
    for p in mesh.polygons:
        axis=max(range(3),key=lambda k:abs(p.normal[k])); axes=[k for k in range(3) if k!=axis]
        for li in p.loop_indices:
            co=mesh.vertices[mesh.loops[li].vertex_index].co
            if mesh.materials[0]==STONE:
                row=2 if p.normal.z>.3 else (0 if p.normal.z<-.3 else (3 if p.normal.x>.5 else 1))
                v=[(co[a]-bounds[a][0])/max(.001,bounds[a][1]-bounds[a][0]) for a in axes]
                uv.data[li].uv=((tile+.025+v[0]*.95)/4,(row+.025+v[1]*.95)/4)
            else: uv.data[li].uv=(co[axes[0]]*density+off[0],co[axes[1]]*density+off[1])

def rock(name,center,scale,mat=None,jitter=.1,bevel=.09):
    mat=mat or STONE
    x,y,z=[s/2 for s in scale]
    verts=[]; sides=7
    angles=[math.tau*i/sides+random.uniform(-.12,.12) for i in range(sides)]
    for level in (0,1):
        for a in angles:
            radius=random.uniform(.88,1.14)
            verts.append((math.cos(a)*x*radius+random.uniform(-jitter,jitter),math.sin(a)*y*radius+random.uniform(-jitter,jitter),(-z if level==0 else z)+random.uniform(-jitter,jitter)))
    faces=[tuple(reversed(range(sides))),tuple(sides+i for i in range(sides))]
    faces.extend((i,(i+1)%sides,(i+1)%sides+sides,i+sides) for i in range(sides))
    ob=mesh_obj(name,verts,faces,mat); ob.location=center
    if bevel:
        bpy.context.view_layer.objects.active=ob
        mod=ob.modifiers.new('Editable_chipped_planes','BEVEL'); mod.width=bevel; mod.segments=1
        bpy.ops.object.modifier_apply(modifier=mod.name)
    uv_faces(ob); return ob

def tube(name,points,radii,mat=BARK,sides=10,parent=None,closed=False):
    pts=[Vector(p) for p in points]; verts=[]; rings=len(pts)
    # Parallel transported frame prevents the frame flips of an axis-switched tube.
    previous_u=None
    for i,p in enumerate(pts):
        tangent=(pts[(i+1)%rings]-pts[(i-1)%rings]).normalized() if closed else (pts[min(i+1,rings-1)]-pts[max(i-1,0)]).normalized()
        if previous_u is None:
            axis=Vector((0,0,1)) if abs(tangent.z)<.88 else Vector((0,1,0))
            u=tangent.cross(axis).normalized()
        else:
            u=(previous_u-tangent*previous_u.dot(tangent)).normalized()
            if u.length<.1: u=tangent.cross(Vector((1,0,0))).normalized()
        previous_u=u; v=tangent.cross(u).normalized()
        for j in range(sides):
            a=math.tau*j/sides
            radius=radii[i]*(1+.09*math.cos(j*3+i*.13))
            verts.append(p+(u*math.cos(a)+v*math.sin(a))*radius)
    faces=[]
    for i in range(rings if closed else rings-1):
        k=(i+1)%rings
        for j in range(sides): faces.append((i*sides+j,i*sides+(j+1)%sides,k*sides+(j+1)%sides,k*sides+j))
    if not closed:
        faces.extend((tuple(reversed(range(sides))),tuple((rings-1)*sides+j for j in range(sides))))
    ob=mesh_obj(name,verts,faces,mat,parent)
    if mat==BARK:
        for face in ob.data.polygons: face.use_smooth=True
    uv=ob.data.uv_layers.new(name='PaintUV'); ob.data.uv_layers.active_index=0; uv.active_render=True
    for face in ob.data.polygons:
        indices=[ob.data.loops[i].vertex_index for i in face.loop_indices]
        wrap=(max(i%sides for i in indices)-min(i%sides for i in indices))>sides/2
        endwrap=closed and (max(i//sides for i in indices)-min(i//sides for i in indices))>rings/2
        for li,vi in zip(face.loop_indices,indices):
            u=(vi%sides)/sides
            if wrap and u==0: u=1
            v=(vi//sides)/(rings if closed else rings-1)*3.5
            if endwrap and v==0: v=3.5
            uv.data[li].uv=(u,v)
    return ob

def smooth_points(anchors,count=50):
    ps=[Vector(x) for x in anchors]; out=[]
    for i in range(count):
        s=(len(ps)-1)*i/(count-1); k=min(len(ps)-2,int(s)); t=s-k
        a,b,c,d=ps[max(0,k-1)],ps[k],ps[k+1],ps[min(len(ps)-1,k+2)]
        out.append(.5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t))
    return out

def ico(name,loc,scale,mat,sub=1):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=sub,radius=1,location=loc)
    o=bpy.context.object; o.name=name; o.scale=scale; move(o,model); objects.append(o); o.data.materials.append(mat); uv_faces(o)
    return o

def grass(name,loc,size,mat=MOSS):
    vs=[]; fs=[]
    for i in range(5):
        a=random.random()*math.tau; h=size*random.uniform(.7,1.3)
        base=Vector(loc)+Vector((math.cos(a),math.sin(a),0))*size*.12
        side=Vector((-math.sin(a),math.cos(a),0))*size*.11
        mid=base+Vector((math.cos(a)*h*.18,math.sin(a)*h*.18,h*.6))
        tip=base+Vector((math.cos(a)*h*.4,math.sin(a)*h*.4,h))
        k=len(vs); vs.extend((base-side,base+side,mid+side*.45,mid-side*.45,tip))
        fs.extend(((k,k+1,k+2,k+3),(k+3,k+2,k+4)))
    ob=mesh_obj(name,vs,fs,mat); uv_faces(ob); return ob

def make_bvh(items):
    bpy.context.view_layer.update(); vs=[];fs=[]
    for o in items:
        base=len(vs); vs.extend(o.matrix_world@v.co for v in o.data.vertices)
        fs.extend(tuple(base+i for i in p.vertices) for p in o.data.polygons)
    return BVHTree.FromPolygons(vs,fs)

def top(bvh,x,y,fallback=5.5):
    hit=bvh.ray_cast(Vector((x,y,12)),Vector((0,0,-1)),20)
    return hit[0].z if hit[0] is not None else fallback

def terrace():
    # One continuous U-shaped rock volume, extruded along the actual flight tunnel.
    # The concave end profile is open below the arch; never cap it with a rectangle.
    profile=[(-2.4,.05),(-5.0,.02),(-5.55,.7),(-5.45,1.6),(-5.03,2.1),(-5.58,3.1),(-5.25,4.2),(-4.70,5.35),(-3.0,5.52),(-1,5.43),(1,5.48),(3.2,5.34),(4.83,5.26),(5.43,4.2),(5.2,3.15),(5.67,2.1),(5.18,1.25),(5.20,.08),(2.4,.06),(2.4,1.5),(2.38,2.8),(2.35,3.45),(1.8,3.92),(1.30,3.82),(.90,4.04),(.40,3.92),(-.05,4.20),(-.65,4.0),(-1.0,4.16),(-1.55,3.88),(-1.8,3.93),(-2.35,3.45),(-2.38,2.8),(-2.4,1.5)]
    verts=[]; slices=9; n=len(profile)
    for row in range(slices):
        y=-3.7+7.4*row/(slices-1)
        for j,(x,z) in enumerate(profile):
            interior=j==0 or j>=18
            dx=.035*math.sin(row*1.3+j) if interior else .16*math.sin(row*1.2+j*.4)
            dz=.025*math.sin(row*.9+j*.4) if interior else .07*math.sin(row*.85+j*.7)
            # Broad irregular front/back edges, same topology through the full module.
            yy=y+.16*math.sin(j*.75+row*.3) if row in (0,slices-1) else y+.07*math.sin(j)
            if row==0 and interior and 20<=j<=31:
                yy=-3.86-.22*math.sin(j*.91)
            verts.append((x+dx,yy,max(.01,z+dz)))
    faces=[tuple(reversed(range(n))),tuple((slices-1)*n+j for j in range(n))]
    for row in range(slices-1):
        for j in range(n): faces.append((row*n+j,row*n+(j+1)%n,(row+1)*n+(j+1)%n,(row+1)*n+j))
    body=mesh_obj('Continuous_Weathered_RockMass',verts,faces,STONE); uv_faces(body)
    # A few unequal outcrops and overlapping ledges provide erosion scale, not brick courses.
    for name,c,s in [
        ('WestFoot',(-4.7,-2.8,.57),(2.5,2.3,1.18)),
        ('WestShoulder',(-4.6,-2.6,2.05),(2.8,2.6,.85)),
        ('WestUpperShelf',(-4.55,-.8,3.62),(2.5,3.7,.64)),
        ('EastFoot',(4.6,-2.9,.65),(2.1,2.3,1.24)),
        ('EastBroadShelf',(4.65,.25,2.52),(2.4,4.3,.70)),
        ('EastRear',(4.6,2.5,4.22),(2.2,2.4,.81))]:
        rock(name,c,s,jitter=.09,bevel=.09)
    # The uneven cave lip belongs to the continuous rock volume above; no stone ring.
    stone_bvh=make_bvh(list(objects))
    # Walkable painted dirt ribbon follows the actual roof facets, not a floating flat sheet.
    vs=[];fs=[]
    for i in range(40):
        t=i/39; x=-4.75+9.5*t; y=-2.3+4.6*t+.60*math.sin(t*math.tau)
        for side in (-1,1):
            width=.58+.13*math.sin(t*23+side)+.12*math.sin(t*11)
            px=x-side*width*.44; py=y+side*width
            vs.append((px,py,top(stone_bvh,px,py)+.022))
        if i:
            k=i*2; fs.extend(((k-2,k-1,k+1),(k-2,k+1,k)))
    path=mesh_obj('Upper_Earthen_Path',vs,fs,MUD); uv_faces(path,.35)
    # Mud floor in the tunnel; real height geometry with no blocker above it.
    vs=[]; fs=[]
    for y in range(9):
        for x in range(7): vs.append((-2.5+x*(5/6),-3.85+y*.9625+.06*math.sin(x),.06+.025*math.sin(x*1.4+y)))
    for y in range(8):
        for x in range(6):
            k=y*7+x; fs.append((k,k+1,k+8,k+7))
    ob=mesh_obj('Lower_Cave_Path',vs,fs,MUD); uv_faces(ob,.4)
    # Broad root trunks follow a complete top -> lip -> cliff -> buried foot path.
    root_top_contacts=[]
    for side in (-1,1):
        for track in range(2):
            dy=track*.19
            anchors=[(side*2.8,.2+dy,5.1),(side*3.4,-1.4+dy,5.62),(side*3.7,-3.35+dy,5.5),(side*4.2,-3.93+dy,4.0),(side*3.65,-3.92+dy,2.35),(side*4.30,-3.94+dy,.88),(side*5.0,-3.2+dy,.02)]
            pts=smooth_points(anchors,48)
            if track:
                pts=[p+Vector((.15*math.sin(i*.5),.08*math.cos(i*.5),.06*math.sin(i*.5))) for i,p in enumerate(pts)]
            radii=[max(.006,(.31 if track==0 else .15)*(.65+.35*max(0,math.sin(math.pi*i/47))**.5)*min(1,i/7,(47-i)/10)) for i in range(48)]
            tube('CliffRoot_%s_%d'%(side,track),pts,radii,sides=12)
            # A root branching into a side ledge always returns beneath the rock surface.
            branch=smooth_points([pts[25],(side*4.95,-3.45,2.8),(side*5.55,-2.45,2.7),(side*5.1,-1.5,2.35)],25)
            tube('CliffRootBranch_%s_%d'%(side,track),branch,[.14*(1-i/24)+.018 for i in range(25)],sides=8)
            if track==0:
                toes=smooth_points([pts[35],(side*4.0,-4.02,1.24),(side*4.4,-3.7,.38),(side*4.65,-3.25,.12)],27)
                tube('RootForkBuriedFoot_%s'%side,toes,[max(.005,.16*(1-i/26)**1.1) for i in range(27)],sides=9)
        # Long root line around the far/right terrace rim adds structure to the unseen back.
        anchors=[(side*4.5,2.9,.02),(side*5.25,3.4,1.3),(side*5.45,2.8,3.0),(side*4.95,2.4,4.8),(side*4.2,1.3,5.43),(side*2.6,2.0,5.12)]
        pts=smooth_points(anchors,42)
        tube('RearButtressRoot_%s'%side,pts,[max(.006,(.24*max(0,math.sin(math.pi*i/41))**.4+.025)*min(1,i/5,(41-i)/8)) for i in range(42)],sides=10)
    # Surface rooted moss, quiet broad masses with small grass along seams, not full coverage.
    for patch,(cx,cy,rx,ry) in enumerate(((-3.05,1.1,2.10,1.90),(3.8,-1.4,1.65,1.8),(3.7,2.5,1.5,1.0),(-4.0,-2.3,1.1,1.0))):
        vs=[];fs=[]; step=.23
        for ix in range(int(rx*2/step)):
            for iy in range(int(ry*2/step)):
                x=cx-rx+ix*step; y=cy-ry+iy*step
                radius=((x-cx)/rx)**2+((y-cy)/ry)**2
                if radius>1+.12*math.sin(x*6+y*4): continue
                t=(x+4.75)/9.5; trail=-2.3+4.6*t+.6*math.sin(t*math.tau)
                if abs(y-trail)<.78: continue
                corners=[(x,y),(x+step,y),(x+step,y+step),(x,y+step)]
                zs=[top(stone_bvh,px,py,None) for px,py in corners]
                if any(z is None for z in zs): continue
                k=len(vs);vs.extend((px,py,z+.024) for (px,py),z in zip(corners,zs));fs.append((k,k+1,k+2,k+3))
                if random.random()<.05: grass('MossEdgeGrass_%d_%d_%d'%(patch,ix,iy),(x,y,zs[0]+.02),random.uniform(.12,.24))
        ob=mesh_obj('BroadMossMat_%d'%patch,vs,fs,MOSS); uv_faces(ob,.7)
    for side in (-1,1):
        for i in range(20):
            # Visible narrow crevice clumps embedded into front stone faces.
            z=random.choice((1.1,2.25,3.4,4.65))+random.uniform(-.04,.04)
            x=side*random.uniform(2.8,5.15)
            # At the lip or root contact, thin narrow masses are embedded into rock.
            ico('Cliff_CreviceMoss_%s_%d'%(side,i),(x,-3.73,z),(random.uniform(.17,.38),.12,.045),MOSS)
    return {'main_cave_clear_box_blender':{'min':[-2.05,-4.5,.30],'max':[2.05,4.5,3.45]},'upper_walkway_nominal_z':5.35,'front_direction_blender':[0,-1,0]}

def leaf_blade(name,parent,scale=1.0,offset=(0,0,0)):
    # Closed manifold blade with actual edge thickness, ridged cross-section and curled tip.
    vs=[];uvcoords=[]; rows=13; cols=7
    for face in (0,1):
        for i in range(rows):
            t=i/(rows-1); width=(.018+.37*math.sin(math.pi*t)**.82)*scale
            yc=(.10+.43*t+.17*math.sin(math.pi*t)-.07*t**6)*scale
            zc=(.22+1.12*t+.07*math.sin(math.pi*t)+.09*t**6)*scale
            for j in range(cols):
                s=-1+2*j/(cols-1)
                z=zc+.20*(1-s*s)*math.sin(math.pi*t)*scale
                z+=.08*s*math.sin(t*math.pi*1.6)*scale
                z+=.025*abs(s)*math.sin(t*math.pi*7)*scale
                z+=(.025 if face==0 else -.025)*scale
                x=s*width*(1+.13*s)+.13*math.sin(t*math.pi*1.7)*scale
                vs.append((x+offset[0],yc+offset[1],z+offset[2])); uvcoords.append(((s+1)/2,t))
    fs=[]; layer=rows*cols
    for face in range(2):
        for i in range(rows-1):
            for j in range(cols-1):
                k=face*layer+i*cols+j
                fs.append((k,k+1,k+cols+1,k+cols) if face==0 else (k+cols,k+cols+1,k+1,k))
    perimeter=list(range(cols))+[i*cols+cols-1 for i in range(1,rows)]+list(range((rows-1)*cols+cols-2,(rows-1)*cols-1,-1))+[i*cols for i in range(rows-2,0,-1)]
    for i,k in enumerate(perimeter):
        n=perimeter[(i+1)%len(perimeter)]; fs.append((k,n,n+layer,k+layer))
    ob=mesh_obj(name,vs,fs,LEAF,parent)
    uv=ob.data.uv_layers.new(name='PaintUV'); ob.data.uv_layers.active_index=0; uv.active_render=True
    for p in ob.data.polygons:
        for li in p.loop_indices: uv.data[li].uv=uvcoords[ob.data.loops[li].vertex_index]
    return ob

def roots():
    # Irregular major roots curl around a lower central depression, taper into the soil,
    # and branch into stems. No repeated concentric rope rings or exposed planar ends.
    anchors=[
        [(-.6,.5,.02),(-.95,.45,.25),(-1.0,-.30,.38),(-.45,-.92,.37),(.4,-.9,.29),(.95,-.4,.46),(.85,.4,.51),(.3,.88,.38),(-.35,.8,.15),(-.45,.45,.04)],
        [(.55,.6,.01),(.35,1.0,.25),(-.45,.86,.50),(-.85,.2,.56),(-.8,-.4,.28),(-.25,-.78,.19),(.4,-.62,.43),(.82,-.06,.39),(.55,.38,.03)],
        [(-.7,-.45,.02),(-1.05,-.4,.16),(-.84,.4,.18),(-.25,.98,.35),(.65,.82,.35),(1.05,.24,.22),(.8,-.6,.16),(.30,-1.0,.22),(-.35,-.9,.05)]]
    major=[]
    for k,a in enumerate(anchors):
        pts=smooth_points(a,64);major.append(pts)
        radii=[max(.006,(.17 if k<2 else .14)*(.65+.35*max(0,math.sin(math.pi*i/63))**.6)*(1+.12*math.sin(i*.5))*min(1,i/8,(63-i)/10)) for i in range(64)]
        tube('BasinMainRoot_%d'%k,pts,radii,sides=12)
    for k in range(4):
        start=major[k%3][13+k*7]
        a=math.atan2(start.y,start.x)
        pts=smooth_points([start,(1.03*math.cos(a+.17),1.03*math.sin(a+.17),.22),(1.14*math.cos(a+.35),1.14*math.sin(a+.35),.05)],23)
        tube('BasinBranchRoot_%d'%k,pts,[max(.004,.085*(1-i/22)**.9) for i in range(23)],sides=8)
    # Low living root bed grounds the piece; the top is a shallow concave bowl.
    vs=[(0,0,.14)];fs=[];n=36
    for i in range(n):
        a=math.tau*i/n;r=.83+.05*math.sin(a*5)
        vs.append((r*math.cos(a),r*math.sin(a),.25+.05*math.sin(a*3)))
    for i in range(n): fs.append((0,1+i,1+(i+1)%n))
    bed=mesh_obj('ConcaveMossRootBed',vs,fs,MOSS);uv_faces(bed,.9)
    for k in range(9):
        a=math.tau*k/9
        pts=smooth_points([(.85*math.cos(a),.85*math.sin(a),.19),(.55*math.cos(a+.3),.55*math.sin(a+.3),.21),(.22*math.cos(a+.5),.22*math.sin(a+.5),.16)],22)
        tube('BasinRootlet_%d'%k,pts,[.065*(1-i/21)+.008 for i in range(22)],sides=8)
    for i,(name,a) in enumerate((('N',0),('E',-math.pi/2),('S',math.pi),('W',math.pi/2))):
        # Local +Y points radially outward. Local X is the hinge; baseline is upright.
        pivot=bpy.data.objects.new('LeafPivot_'+name,None); model.objects.link(pivot); pivots.append(pivot)
        pivot.empty_display_type='ARROWS'; pivot.empty_display_size=.16
        pivot.location=(-math.sin(a)*.59,math.cos(a)*.59,.57); pivot.rotation_euler.z=a
        pivot['hinge_local_axis']='X'; pivot['open_angle_degrees']=-58.0
        pivot['closed_angle_degrees']=0.0
        stem=smooth_points([(0,0,-.15),(.04,.025,.02),(-.04,.10,.22),(.025,.20,.49)],22)
        tube('LeafStem_'+name,stem,[.10*(1-i/21)+.027 for i in range(22)],sides=9,parent=pivot)
        leaf_blade('LivingLeaf_'+name,pivot,scale=(1.0,.94,1.025,.97)[i])
        # Static root shoulder hides the hinge and grows continuously from the main basin.
        radial=Vector((-math.sin(a),math.cos(a),0))
        pts=smooth_points([radial*.93+Vector((0,0,.22)),radial*.80+Vector((0,0,.39)),radial*.59+Vector((0,0,.54))],18)
        tube('LeafRootShoulder_'+name,pts,[.14-i/17*.045 for i in range(18)],sides=10)
        ico('OrganicHingeKnot_'+name,tuple(pivot.location),(.18,.18,.16),BARK,sub=2)
    # Small upright seed-heart is held by actual little curved sepals, not a glass disc.
    vs=[]; fs=[]; rings=12;sides=16
    for i in range(rings):
        t=i/(rings-1); radius=.17*math.sin(math.pi*t)**.7+.005
        for j in range(sides):
            a=math.tau*j/sides; r=radius*(1+.07*math.cos(a*5))
            vs.append((r*math.cos(a),r*math.sin(a),.23+t*.48))
    for i in range(rings-1):
        for j in range(sides): fs.append((i*sides+j,i*sides+(j+1)%sides,(i+1)*sides+(j+1)%sides,(i+1)*sides+j))
    fs.extend((tuple(reversed(range(sides))),tuple((rings-1)*sides+j for j in range(sides))))
    core=mesh_obj('Static_SeedHeart',vs,fs,CORE); uv_faces(core,1.6)
    for k in range(5):
        a=math.tau*k/5
        pts=smooth_points([(.24*math.cos(a),.24*math.sin(a),.19),(.23*math.cos(a),.23*math.sin(a),.38),(.18*math.cos(a),.18*math.sin(a),.55),(.10*math.cos(a+.25),.10*math.sin(a+.25),.68)],18)
        tube('SeedRootSepal_%d'%k,pts,[.047*(1-i/17)+.006 for i in range(18)],sides=7)
        sepal=leaf_blade('SeedLivingSepal_%d'%k,None,scale=.31)
        sepal.rotation_euler.z=a;sepal.location=(-math.sin(a)*.14,math.cos(a)*.14,.19)
    for k in range(42):
        a=random.random()*math.tau; radius=random.uniform(.42,.98)
        z=.16+(radius-.42)*.55
        ico('BasinMoss_%02d'%k,(radius*math.cos(a),radius*math.sin(a),z),(random.uniform(.07,.14),random.uniform(.06,.14),.055),MOSS)
        if k%7==0: grass('BasinSprout_%02d'%k,(radius*math.cos(a),radius*math.sin(a),z+.04),.10)
    return {'leaf_open_degrees_local_x':-58.0,'leaf_closed_degrees_local_x':0,'core_emission_idle':.22,'hinge_warning':'Preserve each LeafPivot baseline basis; rotate about its LOCAL X. N/E/S/W have different baseline Z orientations in Blender.'}

details=terrace() if KIND=='terrace' else roots()
bpy.context.view_layer.update()
coords=[o.matrix_world@v.co for o in objects for v in o.data.vertices]
mins=[min(v[i] for v in coords) for i in range(3)]; maxs=[max(v[i] for v in coords) for i in range(3)]
size=[maxs[i]-mins[i] for i in range(3)]

def area(name,location,power,size,color):
    data=bpy.data.lights.new(name,'AREA'); data.energy=power; data.shape='DISK'; data.size=size; data.color=color
    ob=bpy.data.objects.new(name,data); studio.objects.link(ob); ob.location=location
    target=Vector((0,0,2.5 if KIND=='terrace' else .7)); ob.rotation_euler=(target-ob.location).to_track_quat('-Z','Y').to_euler()

scale=6 if KIND=='terrace' else 1.4
area('Warm_Key',(-scale*1.2,-scale*1.3,scale*2.2),1800 if KIND=='terrace' else 260,scale*1.2,(1,.89,.74))
area('Cool_Fill',(scale*1.3,-scale*.2,scale*1.0),900 if KIND=='terrace' else 140,scale,(.68,.79,1))
area('Soft_Rim',(0,scale*1.4,scale*1.7),1600 if KIND=='terrace' else 220,scale,(1,.92,.78))
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.06))
floor=bpy.context.object; floor.name='PreviewFloor_NOT_EXPORTED'; move(floor,studio)
fm=bpy.data.materials.new('PreviewFloor_NOT_EXPORTED'); fm.diffuse_color=(.18,.20,.19,1); floor.data.materials.append(fm)
camdata=bpy.data.cameras.new('PreviewCamera'); cam=bpy.data.objects.new('PreviewCamera',camdata); studio.objects.link(cam); scene.camera=cam; camdata.type='ORTHO'
def camera(loc,target,ortho):
    cam.location=loc; cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler(); camdata.ortho_scale=ortho
camera((11,-17,12),(0,0,2.5),16.5) if KIND=='terrace' else camera((3.2,-4.6,3.2),(0,0,.98),3.9)
scene.render.resolution_x=1100;scene.render.resolution_y=850
scene['asset_contract']=json.dumps(details)
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/(NAME+'.blend')))

# Export only normalized UV0 meshes, merged by material within the same motion parent.
# Source file was saved BEFORE the export-only joins, preserving every editable component.
exp=bpy.data.collections.new('Export_TEMP'); scene.collection.children.link(exp)
groups={}; export_objects=list(pivots)
for src in objects:
    cp=src.copy(); cp.data=src.data.copy(); exp.objects.link(cp)
    uv=cp.data.uv_layers[0]; uv.name='PaintUV'; cp.data.uv_layers.active_index=0; uv.active_render=True
    groups.setdefault((src.parent.name if src.parent else 'Static',src.data.materials[0].name),[]).append(cp)
static_names={'FK_Stone':'Static_Rock','FK_Bark':'Static_Root' if KIND=='terrace' else 'Static_RootBasin','FK_Moss':'Static_Foliage','FK_Mud':'Static_Path','FK_Core':'Static_Core'}
for (parent,mat),copies in groups.items():
    bpy.ops.object.select_all(action='DESELECT')
    for o in copies: o.select_set(True)
    bpy.context.view_layer.objects.active=copies[0]; bpy.ops.object.join()
    ob=copies[0]; ob.name=static_names.get(mat,'Static_'+mat) if parent=='Static' else parent+'_'+mat
    # One UV set after join is a correctness invariant, not just an optimization.
    assert len(ob.data.uv_layers)==1 and ob.data.uv_layers[0].name=='PaintUV',ob.name
    export_objects.append(ob)
bpy.ops.object.select_all(action='DESELECT')
for o in export_objects:o.select_set(True)
bpy.context.view_layer.objects.active=export_objects[-1]
glb=OUT/(NAME+'.glb')
bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,export_apply=True,export_extras=True,export_yup=True,export_texcoords=True,export_normals=True,export_materials='EXPORT',export_cameras=False,export_lights=False)
triangles=sum(sum(max(0,len(p.vertices)-2) for p in o.data.polygons) for o in export_objects if o.type=='MESH')
report={'asset':NAME,'seed':SEED,'source_object_count':len(objects),'triangles':triangles,'materials':sorted({o.data.materials[0].name for o in objects}),'bounds_blender':{'min':mins,'max':maxs,'size':size},'export_nodes':[o.name for o in export_objects],'details':details,'glb_sha256':hashlib.sha256(glb.read_bytes()).hexdigest(),'source_saved_before_export_joins':True,'cpu_threads':2}
(ART/(NAME+'_build.json')).write_text(json.dumps(report,indent=2),encoding='utf-8')
print('FANTASY_KIT_EXPORT',json.dumps(report))
# Render source or exported geometry once, never the superimposed source+export copies.
exp.hide_render=True
if '--no-render' not in args:
    scene.render.filepath=str(ART/(NAME+'_preview.png')); bpy.ops.render.render(write_still=True)
    if KIND=='terrace':
        camera((-10,16,10),(0,0,2.5),16.5)
        scene.render.filepath=str(ART/(NAME+'_back.png')); bpy.ops.render.render(write_still=True)
    else:
        for p in pivots: p.rotation_euler.x=math.radians(-58)
        camera((3.2,-4.6,3.2),(0,0,.65),4.1)
        scene.render.filepath=str(ART/(NAME+'_open.png')); bpy.ops.render.render(write_still=True)
print('FANTASY_KIT_DONE',NAME)
