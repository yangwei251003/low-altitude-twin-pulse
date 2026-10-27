"""F-B root arch. Editable meshes, authored image maps, explicit Y-up GLB.
Blender 5.2.1: --background --factory-startup --threads 2 --python-exit-code 1
 --python build_root_arch.py -- [--render]
Only root_arch directories are written. No Godot, network, or third-party assets.
"""
import bpy, math, random, json, hashlib, sys
import numpy as np
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree

SRC=Path(__file__).resolve().parent
ROOT=SRC.parents[2]
OUT=ROOT/'assets/v3/root_arch'
ART=ROOT/'artifacts/v3/art/root_arch'
TEX=SRC/'textures'
for p in (OUT,ART,TEX): p.mkdir(parents=True,exist_ok=True)
SEED=19173
REVISION=6
random.seed(SEED); rng=np.random.default_rng(SEED)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
for mat in list(bpy.data.materials): bpy.data.materials.remove(mat)
scene=bpy.context.scene
scene.unit_settings.system='METRIC'; scene.unit_settings.scale_length=1
model=bpy.data.collections.new('Editable_RootArch'); scene.collection.children.link(model)
studio=bpy.data.collections.new('Studio_NOT_EXPORTED'); scene.collection.children.link(studio)
parts=[]; groups={}; textures=[]

def bpos(p): return Vector((p[0],-p[2],p[1]))
def move(o,c):
    for old in list(o.users_collection): old.objects.unlink(o)
    c.objects.link(o)

def image_map(name,a,noncolor=False):
    h,w=a.shape[:2]
    if a.ndim==2: a=np.repeat(a[:,:,None],3,axis=2)
    rgba=np.ones((h,w,4),dtype=np.float32);rgba[:,:,:3]=np.clip(a,0,1)
    image=bpy.data.images.new(name,width=w,height=h,alpha=False)
    if noncolor:image.colorspace_settings.name='Non-Color'
    image.pixels.foreach_set(rgba.ravel());image.file_format='PNG'
    image.filepath_raw=str(TEX/(name+'.png'));image.save();image.pack()
    textures.append(image.filepath_raw)
    return image

def painted_maps(kind,n=1024):
    v,u=np.mgrid[0:n,0:n].astype(np.float32)/(n-1)
    height=np.full((n,n),.5,dtype=np.float32)
    base={'Bark':(.32,.245,.165),'Stone':(.45,.455,.405),'Moss':(.23,.285,.105),'Leaf':(.30,.40,.14)}[kind]
    color=np.tile(np.array(base,dtype=np.float32),(n,n,1))
    rough=np.full((n,n),{'Bark':.88,'Stone':.91,'Moss':.96,'Leaf':.78}[kind],dtype=np.float32)
    if kind=='Bark':
        # Broad growth-following strokes. V spans the root circumference; U its length.
        warp=.34*np.sin(u*7)+.20*np.sin(u*17)+.08*np.sin(u*31)
        for cx,cy in ((.24,.56),(.67,.79),(.82,.38)):
            warp+=.11*np.sin(np.arctan2((v-cy)*1.8,u-cx))*np.exp(-((u-cx)/.1)**2-((v-cy)/.20)**2)
        ridge=np.cos(math.tau*(v*2.8+warp))
        color+=(.045*ridge+.024*np.sin(u*11+v*9))[:,:,None]*np.array([1,.79,.46])
        height+=.012*ridge
        for k in range(5):
            vv=.30+.12*k+.075*np.sin(u*(7+k%3)+k)+.035*np.sin(u*19+k)
            d=np.abs(v-vv)
            active=(np.sin(u*(9+k%4)+k*1.4)>.45)
            groove=(d<(.002+.0005*(k%3)))&active
            shoulder=(v-vv>.004)&(v-vv<.012)&active
            color[groove]*=.82; height[groove]-=.025
            color[shoulder]+=np.array([.052,.039,.021])
        for k in range(65):
            cx,cy=rng.uniform(0,1,2); a=rng.uniform(-.30,.30)
            x=u-cx; y=v-cy-a*x
            mask=(abs(x)<rng.uniform(.025,.11))&(abs(y)<rng.uniform(.010,.045))&(abs(x)+abs(y)<.14)
            color[mask]+=np.array([.045,.032,.021])*(1 if k%3 else -1)
        for cx,cy in ((.26,.53),(.71,.75),(.48,.35)):
            radial=np.sqrt(((u-cx)/.075)**2+((v-cy)/.13)**2)
            knot=(radial<1.2)&(radial>.3)
            color[knot]+=(.014*np.sin(radial[knot]*23))[:,None]*np.array([1,.8,.5])
        # UV atlas bottom quarter is the accumulated earth/worn growth on the deck.
        # Structural roots use the remaining three quarters, never road-colored bark.
        path=v<.265
        earth=np.tile(np.array([.42,.37,.28]),(n,n,1))
        earth+=(.016*np.sin(u*17+v*8)+.010*np.sin(u*41-v*15))[:,:,None]
        for k in range(90):
            cx=rng.uniform(0,1);cy=rng.uniform(0,.265)
            px=u-cx;py=v-cy+.2*px
            mask=(abs(px)<rng.uniform(.012,.045))&(abs(py)<rng.uniform(.005,.023))&(abs(px)+abs(py)<.06)
            earth[mask]+=np.array([.023,.021,.014])*(1 if k%3 else -.6)
        edge=((v<.060+.012*np.sin(u*34))|(v>.196+.014*np.sin(u*21)))&(np.sin(u*33)+.5*np.sin(u*67)>-.2)
        earth[edge]=earth[edge]*.72+np.array([.28,.30,.155])*.28
        color[path]=earth[path];height[path]=.50
        for k in range(16):
            center=(k+.4)/16+.006*np.sin(v*60+k)
            crack=(abs(u-center)<.00065)&(v<.265)&(np.sin(v*79+k)>0)
            color[crack]*=.80;height[crack]-=.012
        cap=(u>.92)&(v>.86)
        radial=np.sqrt(((u-.96)/.04)**2+((v-.93)/.07)**2)
        grain=.015*np.sin(radial*23+.3*np.sin(v*70))
        cap_color=np.tile(np.array([.29,.225,.15]),(n,n,1))+grain[:,:,None]
        color[cap]=cap_color[cap]
    elif kind=='Stone':
        # Four face families in an atlas: cool fracture, warm wall, pale top, dark side.
        palette=[(.36,.39,.37),(.45,.44,.38),(.49,.49,.43),(.31,.34,.32)]
        for row,clr in enumerate(palette):
            sl=slice(row*n//4,(row+1)*n//4)
            color[sl]=clr
        color+=(.012*np.sin(u*9+v*13))[:,:,None]
        for k in range(100):
            cx,cy=rng.uniform(0,1,2); a=rng.uniform(-.6,.6)
            x=(u-cx)*math.cos(a)+(v-cy)*math.sin(a)
            y=-(u-cx)*math.sin(a)+(v-cy)*math.cos(a)
            mask=(abs(x)<rng.uniform(.035,.14))&(abs(y)<rng.uniform(.004,.016))
            color[mask]+=np.array([.046,.037,.024])*(1 if k%3 else -1)
        for k in range(8):
            line=(k+.5)/8+.012*np.sin(u*(8+k)+k)
            crack=(abs(v-line)<.0015)&(np.sin(u*19+k)>0)
            color[crack]*=.73;height[crack]-=.025
    elif kind=='Moss':
        color+=(.030*np.sin(u*8+np.sin(v*9))+.018*np.cos(v*15))[:,:,None]*np.array([.8,1,.4])
        for k in range(150):
            cx,cy=rng.uniform(0,1,2)
            mask=((u-cx)/rng.uniform(.008,.036))**2+((v-cy)/rng.uniform(.003,.013))**2<1
            color[mask]+=np.array([.027,.033,.009])*(1 if k%4 else -1)
            height[mask]+=.006
    else:
        center=.5+.022*np.sin(v*8)
        color+=(.038*np.cos((u-.5)*math.pi)+.014*np.sin(v*8))[:,:,None]
        vein=abs(u-center)<.009
        for vv in (.18,.36,.54,.72):
            for side in (-1,1):
                x=(u-center)*side
                vein|=(x>0)&(x<.45)&(abs(v-vv-x*.55)<.005)
        color[vein]=(.49,.52,.23);height[vein]+=.015
    gy,gx=np.gradient(height)
    normal=np.dstack((-gx*3.4,-gy*3.4,np.ones_like(gx)))
    normal/=np.linalg.norm(normal,axis=2)[:,:,None]
    return image_map('RA_'+kind+'_BaseColor',color),image_map('RA_'+kind+'_Roughness',rough,True),image_map('RA_'+kind+'_Normal',normal*.5+.5,True)

def material(kind):
    col,rough,normal=painted_maps(kind,2048 if kind=='Bark' else 1024)
    mat=bpy.data.materials.new('RA_'+kind);mat.use_nodes=True
    p=mat.node_tree.nodes.get('Principled BSDF');p.inputs['Roughness'].default_value=.85
    p.inputs['Specular IOR Level'].default_value=.24
    for image,socket in ((col,'Base Color'),(rough,'Roughness')):
        n=mat.node_tree.nodes.new('ShaderNodeTexImage');n.image=image
        mat.node_tree.links.new(n.outputs['Color'],p.inputs[socket])
    n=mat.node_tree.nodes.new('ShaderNodeTexImage');n.image=normal
    norm=mat.node_tree.nodes.new('ShaderNodeNormalMap');norm.inputs['Strength'].default_value=.48
    mat.node_tree.links.new(n.outputs['Color'],norm.inputs['Color']);mat.node_tree.links.new(norm.outputs['Normal'],p.inputs['Normal'])
    return mat

MATS={kind:material(kind) for kind in ('Bark','Stone','Moss','Leaf')}

def mesh(name,verts,faces,kind,group,uvs=None,smooth=False):
    data=bpy.data.meshes.new(name+'_Mesh');data.from_pydata([bpos(v) for v in verts],[],faces);data.update()
    obj=bpy.data.objects.new(name,data);model.objects.link(obj);data.materials.append(MATS[kind])
    layer=data.uv_layers.new(name='PaintUV')
    for poly in data.polygons:
        poly.use_smooth=smooth
        if uvs is not None:
            for li in poly.loop_indices:layer.data[li].uv=uvs[data.loops[li].vertex_index]
            if len(poly.vertices)>4:
                axes=sorted(range(3),key=lambda j:abs(poly.normal[j]))[:2]
                coords=[data.vertices[data.loops[li].vertex_index].co for li in poly.loop_indices]
                lo=[min(c[j] for c in coords) for j in axes];hi=[max(c[j] for c in coords) for j in axes]
                for li,co in zip(poly.loop_indices,coords):
                    a=(co[axes[0]]-lo[0])/max(.001,hi[0]-lo[0]);b=(co[axes[1]]-lo[1])/max(.001,hi[1]-lo[1])
                    layer.data[li].uv=(.925+.07*a,.865+.12*b)
        else:
            # Per-face projection into a padded atlas patch, each face stays editable.
            nrm=poly.normal;axis=max(range(3),key=lambda j:abs(nrm[j]))
            axes=[j for j in range(3) if j!=axis]
            coords=[data.vertices[data.loops[li].vertex_index].co for li in poly.loop_indices]
            lo=[min(c[j] for c in coords) for j in axes]; hi=[max(c[j] for c in coords) for j in axes]
            row=2 if nrm.z>.45 else (3 if nrm.z<-.25 else (poly.index%2))
            col=(poly.index*7)%4
            for li,co in zip(poly.loop_indices,coords):
                vv=[(co[j]-lo[k])/max(.001,hi[k]-lo[k]) for k,j in enumerate(axes)]
                layer.data[li].uv=((col+.08+.84*vv[0])/4,(row+.08+.84*vv[1])/4)
    parts.append(obj);groups.setdefault(group,[]).append(obj)
    return obj

def deck_y(x):return 4.5+5.0*(1-(x/20)**2)
def bend_z(x):return .095*math.sin(x*.22)*math.sin(math.pi*(x+20)/40)

# A continuous wide top with non-repeating cross-section, not eight stair boxes.
section=[(-2.99,-.13),(-2.9,0),(-1.75,.018),(-.60,.01),(.60,0),(1.75,.012),(2.9,0),(2.99,-.16),(2.97,-.85),(1.9,-.60),(1.54,-.60),(.30,-.65),(-1.18,-.65),(-1.7,-.60),(-2.97,-.80)]
verts=[];uv=[];faces=[];count=73;ns=len(section)
for i in range(count):
    x=-20+40*i/(count-1);q=abs(x/20);thick=.94+.65*math.exp(-((abs(x)-15.8)/3.0)**2)-.5*q**14
    for j,(z,h) in enumerate(section):
        # Side changes are long-wave and asymmetric; useful top remains 5.8 m wide.
        side_warp=(.13*math.sin(x*.42+j*.8)+.07*math.sin(x*.17-j)) if j not in range(1,7) else 0
        flare=.95*max(0,(q-.6)/.4)**1.2
        z*=1+flare/3.13
        if j in (0,7):side_warp=math.copysign(.02+.08*math.sin(x*.39+j)**2,z)
        if j in (8,14):
            # Edge bedding follows the upper envelope of the interleaved roots;
            # it thickens at their crossing instead of hanging as a paper sheet.
            h=-(.87-.59*abs(math.sin(3*math.pi*(x+20)/40)))
            side_warp=0
        y=deck_y(x)+h*(thick if h<-.2 else 1)
        y=max(.02,y)
        xx=x
        if i in (0,count-1) and j>=8:xx=x-math.copysign(.25+.09*math.sin(j*1.8),x)
        verts.append((xx,y,z+bend_z(x)+side_warp))
        uv.append((i/(count-1),.025+.20*j/7 if j<=7 else .30+.68*(j-8)/(ns-8)))
for i in range(count-1):
    for j in range(ns):faces.append((i*ns+j,i*ns+(j+1)%ns,(i+1)*ns+(j+1)%ns,(i+1)*ns+j))
faces.extend((tuple(reversed(range(ns))),tuple((count-1)*ns+j for j in range(ns))))
mesh('Continuous_WornRoot_Deck',verts,faces,'Bark','WalkableRoot',uv)

def root_tube(name,points,radii,sides=12,flatten=.85,phase=0):
    vs=[];uvs=[];fs=[]
    for i,p in enumerate(points):
        p=Vector(p);a=Vector(points[max(0,i-1)]);b=Vector(points[min(len(points)-1,i+1)])
        tangent=(b-a).normalized()
        side=Vector((0,0,1));side=(side-tangent*side.dot(tangent)).normalized()
        if side.length<.1:side=Vector((1,0,0))
        up=side.cross(tangent).normalized()
        t=i/(len(points)-1);twist=.48*math.sin(t*5+phase)+.32*t
        for j in range(sides):
            angle=math.tau*j/sides+twist
            scallop=1+.16*math.cos(j*math.tau*3/sides+t*5+phase)+.07*math.sin(j*math.tau*5/sides-t*8)
            off=(side*math.cos(angle)+up*math.sin(angle)*flatten)*radii[i]*scallop
            point=p+off;point.x=max(-20,min(20,point.x))
            # Keep the full root ring below the continuous walking surface. Merely
            # capping vertices inside the clear band lets an outside vertex's
            # triangle interpolate back into the band as an unexpected ridge.
            point.y=max(.02,min(point.y,deck_y(point.x)+.005))
            vs.append(point);uvs.append((.02+.96*t,.29+.69*j/sides))
    for i in range(len(points)-1):
        for j in range(sides):fs.append((i*sides+j,(i+1)*sides+j,(i+1)*sides+(j+1)%sides,i*sides+(j+1)%sides))
    fs.extend((tuple(range(sides)),tuple((len(points)-1)*sides+j for j in reversed(range(sides)))))
    return mesh(name,vs,fs,'Bark','WalkableRoot',uvs)

# Deliberately composed side profiles, rather than four offset copies of one arch.
# Front upper/lower roots leave visible negative spaces, then merge at the feet.
root_x=[-19.9,-16,-10,-4,2,8,14,19.9]
profiles=[
    ([.35,5.2,7.7,8.95,8.96,8.35,6.1,.38],[5.3,4.3,3.05,3.10,3.30,2.95,3.9,5.4],[.17,.95,.50,.41,.42,.49,.95,.18]),
    ([.3,3.8,6.9,7.80,7.75,7.48,4.7,.30],[4.0,4.1,3.45,3.38,3.25,3.65,4.6,5.2],[.18,1.03,.46,.38,.38,.43,.95,.17]),
    ([.35,4.7,7.8,8.65,8.95,8.15,5.8,.36],[-5.3,-4.1,-3.4,-3.25,-3.15,-3.5,-4.4,-5.4],[.16,1.1,.56,.44,.45,.57,.92,.16]),
    ([.38,4.4,7.8,8.75,8.7,8.1,5.0,.33],[-1.7,-1.9,-.55,.5,-.35,-1.7,-2.3,-2.6],[.18,.96,.63,.48,.52,.61,.89,.17])]
def profile_value(values,x):
    seg=min(len(root_x)-2,max(0,next((i-1 for i,a in enumerate(root_x) if a>x),len(root_x)-2)))
    t=(x-root_x[seg])/(root_x[seg+1]-root_x[seg]);t=max(0,min(1,t))
    p0=values[max(0,seg-1)];p1=values[seg];p2=values[seg+1];p3=values[min(len(values)-1,seg+2)]
    return .5*((2*p1)+(-p0+p2)*t+(2*p0-5*p1+4*p2-p3)*t*t+(-p0+3*p1-3*p2+p3)*t*t*t)
for k,(ys,zs,rs) in enumerate(profiles):
    pts=[];radii=[]
    for i in range(65):
        x=-19.9+39.8*i/64;t=(x+20)/40;q=abs(x/20)
        if k<2:
            sign=1 if k==0 else -1
            end=max(0,(q-.66)/.34);drop=3.0*end*end*(3-2*end)
            yy=deck_y(x)-1.20+sign*.70*math.sin(3*math.pi*t)-drop
            zz=3.10+sign*.57*math.sin(math.tau*t+.5)+1.65*q**4
            radius=(.60+.45*q*q+.07*math.sin(t*11+k))*(1-.80*end**5)
            pts.append((x,max(.22,yy),zz));radii.append(max(.10,radius))
        else:
            pts.append((x,profile_value(ys,x),profile_value(zs,x)));radii.append(max(.1,profile_value(rs,x)))
    root_tube('Primary_Growth_%d'%k,pts,radii,13,.88,k*.8)

def bezier(points,n=30):
    out=[]
    for i in range(n):
        t=i/(n-1);a,b,c,d=[Vector(p) for p in points]
        out.append(a*(1-t)**3+b*(3*t*(1-t)**2)+c*(3*t*t*(1-t))+d*t**3)
    return out

# Root buttresses anchor both ends; six distinct paths, never concentric ropes.
buttresses=[
    [(-13.2,6.6,-2.4),(-15.8,5.0,-4.2),(-18.0,1.0,-5.1),(-19.7,.18,-5.6)],
    [(-13.8,6.2,2.9),(-15.0,4.1,4.6),(-17.4,1.2,5.1),(-19.3,.12,6.2)],
    [(-17.0,5.0,-.8),(-16.9,3.1,-2.5),(-18.4,.6,-3.3),(-19.6,.10,-3.6)],
    [(12.5,6.9,2.4),(14.2,4.9,4.1),(17.5,1.1,5.1),(19.4,.12,6.25)],
    [(16.0,5.6,-2.6),(15.8,3.3,-4.5),(18.0,.7,-5.0),(19.7,.12,-5.5)],
    [(17.2,4.9,.6),(17.0,3.4,2.1),(18.5,.6,3.0),(19.75,.1,3.4)]]
for k,path in enumerate(buttresses):
    points=bezier(path,31)
    radii=[(1.02 if k%3 else 1.28)*((1-i/30)**.64)+.065 for i in range(31)]
    root_tube('End_Buttress_%02d'%k,points,radii,13,.80,k)

# Local forks are broad enough to read in silhouette, and never weave repeatedly.
forks=[
    [(-16,4.0,4.7),(-13,6.5,4.1),(-5,7.4,2.2),(1,8.7,2.5)],
    [(16,4.3,4.5),(12,6.8,4.0),(7,7.3,2.8),(2,8.5,2.0)],
    [(-15,4.5,-4.5),(-10,7.6,-4.2),(-2,7.4,-2.2),(5,8.3,-2.6)]]
for k,path in enumerate(forks):
    pts=bezier(path,35);radii=[(.69 if k!=1 else .88)*(1-i/34)**.6+.035 for i in range(35)]
    root_tube('Tapered_Companion_%d'%k,pts,radii,12,.80,k)

def rock(name,center,size,seed,follow_deck=False,wall=False):
    rr=random.Random(seed);n=8
    vs=[]
    outline=[(.5,.24),(.29,.5),(-.27,.5),(-.5,.22),(-.5,-.29),(-.25,-.5),(.26,-.5),(.5,-.24)]
    yaw=rr.uniform(-.30,.30);tilt=rr.uniform(-.09,.09)
    for level,y in enumerate((-.5,-.25,.28,.5)):
        for j,(px,pz) in enumerate(outline):
            s=((.83,1,.96,.88) if wall else (.68,1,.90,.55))[level]*rr.uniform(.87,1.12)
            dx=(px*math.cos(yaw)-pz*math.sin(yaw))*size[0]*s
            dz=(px*math.sin(yaw)+pz*math.cos(yaw))*size[2]*s
            xx=max(-20,min(20,center[0]+dx))
            yy=center[1]+y*size[1]+(deck_y(xx)-deck_y(center[0]) if follow_deck else tilt*dx+(rr.uniform(-.08,.08)*size[1] if level in (1,2) else 0))
            vs.append((xx,max(0,yy),center[2]+dz))
    fs=[tuple(reversed(range(n))),tuple(3*n+j for j in range(n))]
    for r in range(3):
        for j in range(n):fs.append((r*n+j,r*n+(j+1)%n,(r+1)*n+(j+1)%n,(r+1)*n+j))
    return mesh(name,vs,[tuple(reversed(f)) for f in fs],'Stone','StoneRemnants')

# Asymmetric ruins: one fractured pier in the west, a broken lower pair in the east.
stone_specs=[(-18.1,.9,-3.7,3.1,1.8,2.3),(-17.0,1.0,3.6,2.8,2.0,2.1),
             (17.4,.9,3.9,3.0,1.8,2.2),(18.2,.85,-3.6,3.1,1.7,2.4),
             (-18.0,5.85,-3.47,1.0,2.45,.96),(-16.4,5.15,3.5,1.35,1.0,1.0),
             (18.1,5.45,3.50,1.1,1.75,1.0),(16.8,5.82,-3.55,1.4,.95,.95),
             (14.8,6.32,3.55,1.15,.8,1.1),(-14.7,6.3,-3.52,1.45,.8,1.0)]
for i,s in enumerate(stone_specs):rock('Embedded_Ruin_%02d'%i,s[:3],s[3:],200+i)
# A buried fractured wall base ties the landing stones together; the roots grow
# around this mass rather than balancing the bridge on isolated four-legged props.
for side in (-1,1):
    rock('Buried_Wall_Foundation_%s'%side,(side*18.4,deck_y(18.4)-2.60,.15),(4.2,5.0,9.2),590+side,True,True)
# Broken low stone strata are interpenetrated by the existing buttresses. They form
# an irregular landing, rather than four exposed polygonal support pillars.
for side in (-1,1):
    for j,(xx,zz,sx,sy,sz,yy) in enumerate(((18.8,-2.0,2.5,2.1,2.8,1.05),(18.8,.7,2.5,2.3,3.2,1.15),(18.5,3.0,2.7,2.0,2.7,1.0),(17.1,-3.6,2.6,1.4,2.0,.7),(17.4,3.6,2.5,1.6,2.1,.8),(19.15,-1.0,2.0,1.35,2.2,3.15),(19.0,1.25,2.2,1.45,2.1,3.05),(17.4,-2.5,2.1,1.15,1.8,2.7))):
        rock('Landing_Fracture_%s_%02d'%(side,j),(side*xx,yy,zz),(sx,sy,sz),610+j+side*17)
# Worn, shallow fragments interrupt the root deck locally; no repetitive stone pavement.
for i,(x,z,sx,sz) in enumerate(((-17,1.8,1.6,.8),(-15.4,1.4,1.1,.75),(-12,-1.7,1.8,.65),(-10.8,-1.5,.9,.6),(-3.7,2.15,1.4,.65),(1.2,-2.1,1.6,.72),(8.8,1.7,1.4,.8),(10.2,1.9,1.1,.65),(16,-1.6,1.5,.85))):
    rock('Worn_Inlay_%02d'%i,(x,deck_y(x)-.015,z),(sx,.16,sz),400+i,True)
for i,(x,z,sx,sz) in enumerate(((-17,-.9,2.6,1.7),(-14.8,-.1,2.5,1.45),(-13,.7,1.7,1.1),(-2.3,-.9,2.5,1.5),(.3,-.2,2.6,1.7),(2.6,.5,1.7,1.15),(11.3,-.8,2.5,1.5),(13.7,.1,2.8,1.5),(16,1.0,2.0,1.2))):
    rock('Broad_Worn_Fragment_%02d'%i,(x,deck_y(x)-.005,z),(sx,.14,sz),470+i,True)
# Broken paving survives in clusters along the shoulder, with real thickness.
for i,(x,z,sx,sz) in enumerate(((-14.2,2.85,2.5,.95),(-12.2,2.88,1.5,.75),(-1.6,2.88,2.4,.85),(1.1,2.92,1.65,.80),(10.7,2.89,2.6,.95),(13.0,2.92,1.6,.72),(-15.1,-2.87,2.4,.85),(6.5,-2.88,3.1,.9))):
    rock('Broken_Path_Shoulder_%02d'%i,(x,deck_y(x)-.16,z),(sx,.40,sz),530+i,True)

# Two partially exposed broad root scars break the soil path, not repeated decking.
for k,cx in enumerate((-9.0,5.5)):
    vs=[];uv=[];fs=[]
    for i in range(13):
        t=i/12;z=-2.85+5.7*t;x=cx+(t-.5)*(4.0 if k==0 else -3.0)+.3*math.sin(t*4)
        width=.16+.48*math.sin(math.pi*t)**.6
        for j in (-1,0,1):
            xx=x+j*width
            rise=.008 if j else .015+.085*math.sin(math.pi*t)**2
            vs.append((xx,deck_y(xx)+rise,z));uv.append((.1+.8*t,.39+.16*(j+1)/2))
    for i in range(12):
        for j in range(2):fs.append((i*3+j,i*3+j+1,(i+1)*3+j+1,(i+1)*3+j))
    mesh('Broad_Exposed_RootScar_%d'%k,vs,[tuple(reversed(f)) for f in fs],'Bark','WalkableRoot',uv)

bpy.context.view_layer.update()
surface_vs=[];surface_fs=[]
for ob in parts:
    off=len(surface_vs);surface_vs.extend(ob.matrix_world@v.co for v in ob.data.vertices)
    surface_fs.extend(tuple(off+i for i in p.vertices) for p in ob.data.polygons)
surface_tree=BVHTree.FromPolygons(surface_vs,surface_fs)
def surface_y(x,z):
    hit=surface_tree.ray_cast(bpos((x,18,z)),Vector((0,0,-1)),20)
    return hit[0].z if hit[0] is not None else deck_y(x)

def moss_patch(name,x,z,rx,rz,phase):
    z*=.88;rz*=.65
    n=20;rings=3;vs=[(x,surface_y(x,z)+.012,z)];uv=[(.5,.5)];fs=[]
    for k in range(1,rings+1):
        for j in range(n):
            a=math.tau*j/n;r=(1+.16*math.sin(a*3+phase)+.11*math.cos(a*5-phase))*k/rings
            xx=max(-19.85,min(19.85,x+math.cos(a)*rx*r));zz=z+math.sin(a)*rz*r
            vs.append((xx,surface_y(xx,zz)+.012,zz));uv.append((.5+math.cos(a)*.47*k/rings,.5+math.sin(a)*.47*k/rings))
    fs.extend((0,1+(j+1)%n,1+j) for j in range(n))
    for k in range(rings-1):
        for j in range(n):fs.append((1+k*n+j,1+k*n+(j+1)%n,1+(k+1)*n+(j+1)%n,1+(k+1)*n+j))
    return mesh(name,vs,fs,'Moss','Moss',uv)

# Long broken connected shelves of moss, large/medium/small hierarchy, no grid coverage.
for i,(x,z,rx,rz) in enumerate(((-17.4,-2.9,2.3,.45),(-14,-2.85,2.0,.40),(-9.9,-2.88,2.5,.36),(-5.4,-2.92,1.6,.42),(.2,-2.87,1.8,.41),(5.4,-2.9,2.3,.39),(9.4,-2.91,1.7,.31),(15.8,-2.9,2.7,.44),(-17.2,2.94,2.6,.42),(-12.6,2.91,2.5,.36),(-7.2,2.9,2.0,.4),(-.8,2.9,2.7,.46),(4.8,2.89,2.0,.35),(10.3,2.94,2.7,.39),(16.3,2.91,2.6,.45))):
    moss_patch('Moss_Edge_%02d'%i,x,z,rx,rz,i*.73)
for i,(x,z) in enumerate(((-18.5,-2.4),(-16.3,2.4),(-11.5,-2.3),(-3.4,2.5),(6.2,-2.4),(12.8,2.4),(17.9,-2.4))):
    moss_patch('Moss_Transition_%02d'%i,x,z,.75,.28,i)

def plant(name,x,z,scale,phase):
    base=Vector((x,surface_y(x,z)+.025,z));vs=[];fs=[];uv=[]
    for k in range(5):
        angle=k*math.tau/5+phase;length=scale*(.78+.25*math.sin(k*2+phase));offset=len(vs)
        direction=Vector((math.cos(angle),0,math.sin(angle)));side=Vector((-math.sin(angle),0,math.cos(angle)))
        for i in range(6):
            t=i/5;center=base+direction*(length*t*.84)+Vector((0,length*(.82*t-.44*t*t),0))
            width=length*.23*math.sin(math.pi*t)**.6
            for j in (-1,0,1):
                p=center+side*(width*j)+Vector((0,-abs(j)*width*.26,0))
                vs.append(p);uv.append(((j+1)/2,t))
        for i in range(5):
            for j in range(2):fs.append((offset+i*3+j,offset+i*3+j+1,offset+(i+1)*3+j+1,offset+(i+1)*3+j))
    return mesh(name,vs,fs,'Leaf','Foliage',uv)
for i,(x,z,s) in enumerate(((-18.8,-3.1,.72),(-16.1,3.0,.60),(-14.3,-3.05,.48),(-5.5,3.05,.42),(2.3,-3.1,.38),(8.7,3.0,.46),(15.8,-3.1,.62),(18.2,3.05,.76))):
    plant('Broadleaf_Clump_%02d'%i,x,z,s,i*.8)

# Authored root and semantic anchors survive reimport independently of mesh merging.
root=bpy.data.objects.new('F1RootArch',None);model.objects.link(root)
root['asset_version']='F1-root-arch-v%d'%REVISION;root['units']='metres';root['walkable_width_m']=5.8
for ob in parts:ob.parent=root
MARKERS={'EntryWest':(-20,4.5,0),'Crown':(0,9.5,0),'EntryEast':(20,4.5,0),'Underpass':(0,3.25,0)}
markers=[]
for name,at in MARKERS.items():
    o=bpy.data.objects.new(name,None);model.objects.link(o);o.location=bpos(at);o.parent=root;markers.append(o)

def aim(o,point):o.rotation_euler=(bpos(point)-o.location).to_track_quat('-Z','Y').to_euler()
def area(name,at,power,size,color):
    d=bpy.data.lights.new(name,'AREA');d.energy=power;d.size=size;d.color=color
    o=bpy.data.objects.new(name,d);studio.objects.link(o);o.location=bpos(at);aim(o,(0,4,0))
area('Key',(-10,34,20),18000,23,(1,.91,.78))
area('Fill',(22,20,-15),11500,20,(.76,.84,1))
area('Rim',(-20,20,-20),14500,18,(1,.93,.81))
bpy.ops.mesh.primitive_plane_add(size=220,location=(0,0,-.05));floor=bpy.context.object;floor.name='StudioGround';move(floor,studio)
floor_mat=bpy.data.materials.new('Studio_Only');floor_mat.diffuse_color=(.22,.235,.24,1);floor.data.materials.append(floor_mat)
camdata=bpy.data.cameras.new('ReviewCamera');cam=bpy.data.objects.new('ReviewCamera',camdata);studio.objects.link(cam);scene.camera=cam
camdata.type='ORTHO';camdata.ortho_scale=47
def camera(at,target,scale=47):cam.location=bpos(at);aim(cam,target);camdata.ortho_scale=scale
camera((29,27,43),(0,4.3,0),47)
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=28;scene.cycles.use_denoising=True
scene.render.threads_mode='FIXED';scene.render.threads=2
scene.render.resolution_x=1536;scene.render.resolution_y=864;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.world.color=(.25,.25,.25)
scene.view_settings.view_transform='AgX';scene.view_settings.look='AgX - Medium High Contrast'
scene['asset_contract']=json.dumps({'markers':MARKERS,'span':40,'clear_width':5.8,'crown_top':9.5,'end_top':4.5,'central_clearance_min':6.5})
bpy.context.view_layer.update()
source_path=SRC/'f1_root_arch.blend'
bpy.ops.wm.save_as_mainfile(filepath=str(source_path))

# Evaluated export copies merge by purpose/material. Source retains every editable part.
exp=bpy.data.collections.new('Export_ONLY');scene.collection.children.link(exp)
root.name='Source_F1RootArch'
outroot=bpy.data.objects.new('F1RootArch',None);exp.objects.link(outroot);outroot['asset_version']='F1-root-arch-v%d'%REVISION
exports=[outroot]
for group,originals in groups.items():
    copies=[]
    for original in originals:
        cp=original.copy();cp.data=original.data.copy();cp.parent=None;cp.matrix_world=original.matrix_world.copy();exp.objects.link(cp);copies.append(cp)
    bpy.ops.object.select_all(action='DESELECT')
    for ob in copies:ob.select_set(True)
    bpy.context.view_layer.objects.active=copies[0];bpy.ops.object.join();joined=copies[0];joined.name=group
    scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=True);joined.parent=outroot;exports.append(joined)
    assert len(joined.data.uv_layers)==1
for marker in markers:
    name=marker.name;marker.name='Source_'+name
    cp=bpy.data.objects.new(name,None);exp.objects.link(cp);cp.location=marker.location;cp.parent=outroot;exports.append(cp)
bpy.ops.object.select_all(action='DESELECT')
for ob in exports:ob.select_set(True)
bpy.context.view_layer.objects.active=outroot
path=OUT/'f1_root_arch.glb'
bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_apply=True,export_yup=True,export_extras=True,export_texcoords=True,export_normals=True,export_materials='EXPORT',export_cameras=False,export_lights=False,export_animations=False)
triangles=0;coords=[]
for ob in exports:
    if ob.type!='MESH':continue
    ob.data.calc_loop_triangles();triangles+=len(ob.data.loop_triangles)
    coords.extend(ob.matrix_world@v.co for v in ob.data.vertices)
mn=[min(v[k] for v in coords) for k in range(3)];mx=[max(v[k] for v in coords) for k in range(3)]
report={'asset':'F1RootArch','reference':'references/v3/production/root_arch/root_arch_reference_v1.png','seed':SEED,'blender':bpy.app.version_string,'source_editable_meshes':len(parts),'triangles':triangles,'materials':list(MATS),'export_nodes':[o.name for o in exports],'godot_bounds':{'min':[mn[0],mn[2],-mx[1]],'max':[mx[0],mx[2],-mn[1]]},'markers':MARKERS,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'bytes':path.stat().st_size,'texture_provenance':'original deterministic handpaint-style maps authored in this script, no scraped or third-party image textures','textures':textures,'scope':'source/export only, not Godot physics or final visual acceptance'}
(ART/'build_report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('ROOT_ARCH_BUILD '+json.dumps(report))
assert 12000<=triangles<=24000,triangles
exp.hide_render=True
if '--render' in sys.argv:
    for name,at,target,scale in [('default_oblique',(29,27,43),(0,4.3,0),47),('underpass',(5,8,48),(0,4.8,0),46),('top',(0,62,.01),(0,0,0),46)]:
        camera(at,target,scale);scene.render.filepath=str(ART/(name+'_v%d.png'%REVISION));bpy.ops.render.render(write_still=True)
print('ROOT_ARCH_DONE')
