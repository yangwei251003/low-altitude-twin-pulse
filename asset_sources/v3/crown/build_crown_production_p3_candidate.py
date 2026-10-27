"""Crown dev.6 material/UV production from the frozen v4 editable form.
Blender 5.2.1 CPU 2. --render: two source previews; --export: explicit GLB.
No imports from shared game or asset helpers. Original v4 is never overwritten.
"""
import bpy, bmesh, math, json, sys, hashlib
import numpy as np
from pathlib import Path
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

SOURCE=Path(__file__).resolve().parent; PROJECT=SOURCE.parents[2]
ART=PROJECT/'artifacts/v3/art/crown'; OUT=PROJECT/'assets/v3/crown'; TEX=SOURCE/'textures'
for folder in (ART,OUT,TEX): folder.mkdir(parents=True,exist_ok=True)
VERSION='p3'; DO_RENDER='--render' in sys.argv; DO_EXPORT='--export' in sys.argv
assert not DO_EXPORT, 'p3 is a material preview. Await material review then bake supported GLB textures.'
INPUT=SOURCE/'parasitic_crown_blockout.blend'
INPUT_SHA='24a3d72588ee89e96a040c8d8f47456a9e26ef1ebe45ff9fa5c4ebbf7c9bc13d'
assert hashlib.sha256(INPUT.read_bytes()).hexdigest()==INPUT_SHA, 'Frozen form v4 changed'
bpy.ops.wm.open_mainfile(filepath=str(INPUT))
scene=bpy.context.scene; scene.cycles.device='CPU'; scene.cycles.samples=12
scene.render.threads_mode='FIXED'; scene.render.threads=2
model=bpy.data.collections['Crown_EDITABLE_MASTER']; objects=list(model.objects)
meshes=[o for o in objects if o.type=='MESH']; root=bpy.data.objects['ParasiticCrown']
rest={o.name:o.matrix_basis.copy() for o in objects if o.type=='EMPTY'}
root['status']='material_candidate_not_integrated'; root['form_v4_sha256']=INPUT_SHA
texture_records=[]; leaf_uv={}

def bp(p): return Vector((p[0],-p[2],p[1]))
def gp(p): return [float(p.x),float(p.z),float(-p.y)]
def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def save_map(name,arr,noncolor=False):
    if arr.ndim==2: arr=np.repeat(arr[:,:,None],3,axis=2)
    h,w=arr.shape[:2]; rgba=np.ones((h,w,4),dtype=np.float32); rgb=np.clip(arr,0,1)
    # Generated PNG bytes must be sRGB encoded for colour maps. Shader constants
    # and the palettes above are linear; roughness/normal maps remain raw data.
    if not noncolor:rgb=np.where(rgb<=.0031308,rgb*12.92,1.055*np.power(rgb,1/2.4)-.055)
    rgba[:,:,:3]=rgb
    img=bpy.data.images.new(name,width=w,height=h,alpha=False)
    if noncolor: img.colorspace_settings.name='Non-Color'
    img.pixels.foreach_set(rgba.ravel()); img.file_format='PNG'; img.filepath_raw=str(TEX/(name+'.png'))
    img.save(); img.pack()
    path=Path(img.filepath_raw); texture_records.append({'file':str(path.relative_to(PROJECT)),'sha256':digest(path),'width':w,'height':h,'role':name,'bytes':path.stat().st_size})
    return img

def normal_from_height(height,strength=.045):
    dy,dx=np.gradient(height); n=np.dstack((-dx*height.shape[1]*strength,-dy*height.shape[0]*strength,np.ones_like(height)))
    n/=np.linalg.norm(n,axis=2)[:,:,None]
    return n*.5+.5

def stone_maps(size=2048):
    cell=size//4; col=np.zeros((size,size,3),np.float32); height=np.full((size,size),.5,np.float32)
    # Four coherent face families, not random per-polygon camouflage.
    palette=[(.47,.435,.355),(.425,.405,.350),(.370,.375,.350),(.320,.330,.310)]
    yy,xx=np.mgrid[0:cell,0:cell].astype(np.float32)/(cell-1)
    for row in range(4):
        for slot in range(4):
            base=np.array(palette[row])+np.array([.014,.007,-.004])*(slot-1.5)
            patch=np.broadcast_to(base,(cell,cell,3)).copy(); relief=np.full((cell,cell),.5,np.float32)
            # Four deliberately broad oblique brush masses per stone face.
            for j in range(4):
                cx=.18+(j%2)*.48+.025*math.sin(slot+j); cy=.20+(j//2)*.49
                u=xx-cx; v=yy-cy+u*(.25 if (j+slot)%2 else -.17)
                mask=(abs(u)<(.23 if j%2 else .27))&(abs(v)<(.10+.025*(j%2)))
                edge=np.minimum((.25-abs(u))/.05,(.13-abs(v))/.035); weight=np.clip(edge,0,1)*mask
                delta=np.array([.040,.030,.013])*(1 if (j+slot)%3 else -.75)
                patch+=weight[:,:,None]*delta; relief+=weight*.009*(1 if j%2 else -1)
            # Two interrupted, broad geological fractures with a warm lip.
            for j in range(2):
                line=.31+j*.38+(xx-.5)*(.22 if (slot+j)%2 else -.16)+.015*np.sin(xx*11+j)
                d=yy-line; active=(xx>.08+j*.13)&(xx<.92-j*.08)&~((xx>.39)&(xx<.48) if j else (xx>.66)&(xx<.73))
                cut=(abs(d)<.006)*active; bed=(abs(d)<.018)*active; lip=(d>.008)&(d<.027)&active
                patch[bed]*=.97;patch[cut]*=.82;patch[lip]+=np.array([.027,.021,.010])
                relief[bed]-=.003;relief[cut]-=.012;relief[lip]+=.003
            ys=slice(row*cell,(row+1)*cell);xs=slice(slot*cell,(slot+1)*cell)
            col[ys,xs]=patch;height[ys,xs]=relief
    return col,np.clip(.88+(height-.5)*.5,.79,.95),height

def bark_maps(size=2048):
    col=np.zeros((size,size,3),np.float32);height=np.full((size,size),.5,np.float32)
    sw=size//4; v,u=np.mgrid[0:size,0:sw].astype(np.float32);u/=(sw-1);v/=(size-1)
    for slot in range(4):
        base=np.array([.171,.094,.043])+np.array([.012,.006,.002])*(slot-1.5)
        patch=np.broadcast_to(base,(size,sw,3)).copy();relief=np.full((size,sw),.5,np.float32)
        # Wide bark plates, changing length/width and terminating at visible forks.
        for band,(left,right) in enumerate([(.055,.285),(.33,.58),(.635,.945)]):
            bend=.024*np.sin(v*(5+band)+slot*.8)+(.045 if band%2 else -.028)*(v-.5)
            local=(u-left-bend)/(right-left); inside=(local>0)&(local<1)
            facet=np.clip(np.minimum(local/.12,(1-local)/.12),0,1)
            intervals=[(.035,.29),(.34,.66),(.71,.985)] if (band+slot)%2 else [(.02,.43),(.49,.78),(.82,.98)]
            for cut,(start,end) in enumerate(intervals):
                taper=(v>start+(u-.5)*(.035 if cut%2 else -.045))&(v<end+(u-.5)*.025)
                weight=facet*inside*taper
                tone=np.array([.049,.029,.012])*(.70 if (band+cut+slot)%3 else -.70)
                patch+=weight[:,:,None]*tone;relief+=weight*(.046 if (band+cut)%2 else .026)
                # Long dark cleft on one side, broken at the plate ends.
                groove=(local>-.025)&(local<.045)&taper
                patch[groove]*=.57;relief[groove]-=.045
                warm=(local>.07)&(local<.17)&taper
                patch[warm]+=np.array([.030,.017,.006]);relief[warm]+=.012
        # A single broad asymmetric knot per strip, not dense repeated tiny noise.
        cx=.40+.09*math.sin(slot*1.7);cy=.54+.12*math.cos(slot*1.4)
        q=np.sqrt(((u-cx)/.12)**2+((v-cy)/.075)**2)
        knot=(q>.68)&(q<.85)&(v<cy+.045)
        patch[knot]*=.64;relief[knot]-=.028
        shoulder=(q>.86)&(q<1.13);patch[shoulder]+=np.array([.018,.009,.002]);relief[shoulder]+=.018
        xs=slice(slot*sw,(slot+1)*sw);col[:,xs]=patch;height[:,xs]=relief
    return col,np.clip(.84-(height-.5)*.65,.72,.94),height

def segment_distance(u,v,a,b):
    dx=b[0]-a[0];dy=b[1]-a[1];t=np.clip(((u-a[0])*dx+(v-a[1])*dy)/(dx*dx+dy*dy),0,1)
    return np.sqrt((u-a[0]-t*dx)**2+(v-a[1]-t*dy)**2)

def leaf_maps(size=1024):
    v,u=np.mgrid[0:size,0:size].astype(np.float32)/(size-1)
    col=np.zeros((size,size,3),np.float32)+np.array([.125,.155,.043]);h=np.full((size,size),.5,np.float32)
    # Wide irregular leaf-age patches; no tiny noise or regular color stripes.
    for j in range(17):
        cx=.05+.90*((j*.6180339)%1);cy=.04+.92*((j*.381966+.17)%1)
        d=((u-cx)/(.09+.04*(j%3)))**2+((v-cy+(u-cx)*.35)/(.06+.025*(j%4)))**2
        weight=np.clip(1-d,0,1)**.7
        col+=weight[:,:,None]*np.array([.028,.025,.005])*(1 if j%3 else -1.5)
    edge=np.ones((size,size),np.float32)
    for i,a in enumerate(leaf_outline_uv):
        edge=np.minimum(edge,segment_distance(u,v,a,leaf_outline_uv[(i+1)%len(leaf_outline_uv)]))
    dry=np.clip(1-edge/.037,0,1)
    col=col*(1-dry[:,:,None]*.65)+np.array([.21,.125,.038])*dry[:,:,None]*.65
    veins=[((.06,.08),(.20,.97)),((.06,.08),(.44,.43)),((.44,.43),(.98,.73)),((.44,.43),(.80,.05)),((.24,.26),(.84,.33)),((.36,.52),(.53,.72))]
    veins += [((.12+j*.03,.20+j*.10),(.32+j*.045,.15+j*.10)) for j in range(6)]
    veins += [((.43+j*.055,.43+j*.035),(.50+j*.065,.29+j*.017)) for j in range(5)]
    for i,(a,b) in enumerate(veins):
        d=segment_distance(u,v,a,b);wide=np.clip(1-d/(.015 if i<4 else .009),0,1)
        col+=wide[:,:,None]*np.array([.085,.069,.018]);h+=wide*(.025 if i<4 else .014)
    return col,np.full((size,size),.83,np.float32),h

def reference_material(name,kind):
    path=SOURCE/'material_references'/(kind+'_reference_p3.png')
    img=bpy.data.images.load(str(path),check_existing=False);img.name=kind+'_imagegen_color_p3';img.colorspace_settings.name='sRGB';img.pack()
    texture_records.append({'file':str(path.relative_to(PROJECT)),'sha256':digest(path),'width':img.size[0],'height':img.size[1],'role':'generated color reference actually UV mapped','bytes':path.stat().st_size})
    m=bpy.data.materials.new(name);m.use_nodes=True;n=m.node_tree.nodes;n.clear();links=m.node_tree.links
    out=n.new('ShaderNodeOutputMaterial');p=n.new('ShaderNodeBsdfPrincipled');links.new(p.outputs['BSDF'],out.inputs['Surface'])
    p.inputs['Metallic'].default_value=0;p.inputs['Roughness'].default_value=.91 if kind=='stone' else .86;p.inputs['Specular IOR Level'].default_value=.20
    uv=n.new('ShaderNodeUVMap');uv.uv_map='PaintUV'
    tex=n.new('ShaderNodeTexImage');tex.image=img;tex.extension='REPEAT';links.new(uv.outputs['UV'],tex.inputs['Vector'])
    # Model-space cavities modulate junctions. This source shader is baked only
    # after preview approval, so unsupported procedural nodes cannot reach GLB.
    ao=n.new('ShaderNodeAmbientOcclusion');ao.inputs['Distance'].default_value=.24;ao.samples=12
    shade=n.new('ShaderNodeMixRGB');shade.blend_type='MULTIPLY';shade.inputs[0].default_value=.48;links.new(tex.outputs['Color'],shade.inputs[1]);links.new(ao.outputs['Color'],shade.inputs[2])
    cavity=n.new('ShaderNodeMath');cavity.operation='SUBTRACT';cavity.inputs[0].default_value=.76;links.new(ao.outputs['AO'],cavity.inputs[1]);cavity.use_clamp=True
    geometry=n.new('ShaderNodeNewGeometry');separate=n.new('ShaderNodeSeparateXYZ');links.new(geometry.outputs['Normal'],separate.inputs[0])
    up=n.new('ShaderNodeMath');up.operation='MAXIMUM';up.inputs[1].default_value=.08;links.new(separate.outputs['Z'],up.inputs[0])
    mask=n.new('ShaderNodeMath');mask.operation='MULTIPLY';links.new(cavity.outputs[0],mask.inputs[0]);links.new(up.outputs[0],mask.inputs[1])
    strength=n.new('ShaderNodeMath');strength.operation='MULTIPLY';strength.inputs[1].default_value=2.4 if kind=='stone' else 1.6;strength.use_clamp=True;links.new(mask.outputs[0],strength.inputs[0])
    moss=n.new('ShaderNodeMixRGB');links.new(strength.outputs[0],moss.inputs[0]);links.new(shade.outputs[0],moss.inputs[1]);moss.inputs[2].default_value=(.105,.13,.026,1);links.new(moss.outputs[0],p.inputs['Base Color'])
    gray=n.new('ShaderNodeRGBToBW');links.new(tex.outputs['Color'],gray.inputs[0]);bump=n.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.42 if kind=='stone' else .58;bump.inputs['Distance'].default_value=.065 if kind=='stone' else .095;links.new(gray.outputs[0],bump.inputs['Height']);links.new(bump.outputs[0],p.inputs['Normal'])
    m['texture_authorship']='builtin imagegen single-material color, genuine UV mapping, authored approximate relief; geometric crevice moss; pending bake'
    return m

def core_maps(size=1024):
    v,u=np.mgrid[0:size,0:size].astype(np.float32)/(size-1)
    col=np.zeros((size,size,3),np.float32)+np.array([.43,.161,.022]);h=np.full((size,size),.5,np.float32)
    glow=np.zeros((size,size,3),np.float32)
    for j in range(5):
        line=j*.20+.025*np.sin(v*8+j*1.3)+.012*np.sin(v*19+j)
        d=abs(((u-line+.5)%1)-.5)
        cut=d<.007;lip=(d>=.007)&(d<.018)
        col[cut]*=.43;h[cut]-=.033;col[lip]+=np.array([.12,.07,.012]);h[lip]+=.012
        glow[lip]=(.85,.285,.035)
    glow+=np.array([.12,.033,.002])*np.maximum(0,np.sin(v*math.pi))[:,:,None]**.8
    return col,np.full((size,size),.47,np.float32),h,glow

def make_material(name,kind,normal_strength):
    vals={'stone':stone_maps,'bark':bark_maps,'leaf':leaf_maps,'core':core_maps}[kind]()
    color,rough,height=vals[:3]
    imgs=[save_map(kind+'_basecolor',color),save_map(kind+'_roughness',rough,True),save_map(kind+'_normal',normal_from_height(height,.055 if kind=='bark' else .035),True)]
    m=bpy.data.materials.new(name);m.use_nodes=True;n=m.node_tree.nodes;n.clear();link=m.node_tree.links
    output=n.new('ShaderNodeOutputMaterial');shader=n.new('ShaderNodeBsdfPrincipled');link.new(shader.outputs['BSDF'],output.inputs['Surface'])
    shader.inputs['Metallic'].default_value=0;shader.inputs['Specular IOR Level'].default_value=.26
    tex_nodes=[]
    for img in imgs:
        node=n.new('ShaderNodeTexImage');node.image=img;node.interpolation='Linear';node.extension='EXTEND';tex_nodes.append(node)
    link.new(tex_nodes[0].outputs['Color'],shader.inputs['Base Color']);link.new(tex_nodes[1].outputs['Color'],shader.inputs['Roughness'])
    normal=n.new('ShaderNodeNormalMap');normal.inputs['Strength'].default_value=normal_strength
    link.new(tex_nodes[2].outputs['Color'],normal.inputs['Color']);link.new(normal.outputs['Normal'],shader.inputs['Normal'])
    if kind=='core':
        emissive=n.new('ShaderNodeTexImage');emissive.image=save_map('core_emission',vals[3]);emissive.extension='EXTEND'
        link.new(emissive.outputs['Color'],shader.inputs['Emission Color']);shader.inputs['Emission Strength'].default_value=.30
        m['rest_emission_strength']=.30;m['controlled_core_material']=True
    m['texture_authorship']='original deterministic broad paint, no scraped imagery or concept projection'
    return m

leaf_outline_uv=[(.05,.08),(.18,.60),(.20,.98),(.51,.72),(.98,.73),(.88,.32),(.80,.05),(.30,.10)]
materials={'stone':reference_material('Crown_WarmStone','stone'),'bark':reference_material('Crown_ChestnutBark','bark'),
           'leaf':make_material('Crown_LeafMembrane','leaf',.62),'core':make_material('Crown_AmberCore','core',.50)}

# Add an actual narrow bevel to each pre-existing leaf membrane, retaining its
# independent object/pivot. There are no new decorative objects or new outline.
leaf_outline_uv=[(.05,.08),(.18,.60),(.20,.98),(.51,.72),(.98,.73),(.88,.32),(.80,.05),(.30,.10)]
for o in meshes:
    if not o.name.startswith('LeafMembrane_'): continue
    old=o.data; ps=[v.co.copy() for v in old.vertices[:8]]; c=old.vertices[8].co.copy();uvc=Vector((.44,.43))
    normal=sum((p.normal for p in old.polygons[:8]),Vector()).normalized()
    verts=[tuple(v) for v in ps]+[tuple(v.lerp(c,.10)+normal*.025) for v in ps]+[tuple(c)]
    verts += [tuple(v-normal*.045) for v in ps]+[tuple(c-normal*.045)]
    faces=[]
    for j in range(8):
        k=(j+1)%8;faces.extend([(j,k,8+k,8+j),(8+j,8+k,16),(17+k,17+j,25),(j,17+j,17+k,k)])
    data=bpy.data.meshes.new(o.name+'_ProductionMesh');data.from_pydata(verts,[],faces);data.update();o.data=data
    leaf_uv[o.name]=leaf_outline_uv+[tuple(Vector(p).lerp(uvc,.10)) for p in leaf_outline_uv]+[tuple(uvc)]+leaf_outline_uv+[tuple(uvc)]

for o in meshes:
    bm=bmesh.new();bm.from_mesh(o.data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(o.data);bm.free();o.data.update()

def new_uv(data):
    for layer in list(data.uv_layers):data.uv_layers.remove(layer)
    uv=data.uv_layers.new(name='PaintUV');uv.active_render=True;data.uv_layers.active=uv
    return uv

def cylindrical_uv(o,uv,kind):
    data=o.data;side=sorted(data.polygons[0].vertices)[2]
    assert side>=7 and side<=32, (o.name,side)
    rings=len(data.vertices)//side; has_tip=len(data.vertices)%side==1;slot=sum(map(ord,o.name))%4
    for poly in data.polygons:
        js=[int(i)%side for i in poly.vertices];seam=max(js)-min(js)>side//2
        for li,vi in zip(poly.loop_indices,poly.vertices):
            row=int(vi)//side;j=int(vi)%side
            circum=1.0 if seam and j==0 else j/side
            longitudinal=row/max(1,rings if has_tip else rings-1)
            if len(poly.vertices)>4:
                # True area on exposed/embedded end caps; never collapse UVs to a line.
                u=.5+.42*math.cos(j*math.tau/side);v=(.08 if row==0 else .92)+.055*math.sin(j*math.tau/side)
                uv.data[li].uv=(u,v)
                continue
            if has_tip and row==rings:
                adjacent=[int(index)%side for index in poly.vertices if int(index)//side<rings]
                circum=sum(1.0 if seam and index==0 else index/side for index in adjacent)/len(adjacent)
            if kind=='bark': pos=(.018+.964*circum+slot*.173,.018+.964*longitudinal)
            else: pos=(.008+.984*circum,.012+.976*longitudinal)
            uv.data[li].uv=pos

for o in meshes:
    if o.name=='CoreSeed':kind='core'
    elif o.name.startswith('LeafMembrane_'):kind='leaf'
    elif o.name.startswith(('CrownArmor_','DorsalShell_','ClawScute_')):kind='stone'
    else:kind='bark'
    o.data.materials.clear();o.data.materials.append(materials[kind]);uv=new_uv(o.data)
    if kind=='leaf':
        for poly in o.data.polygons:
            is_rim=min(poly.vertices)<8 and any(17<=vi<25 for vi in poly.vertices)
            for k,(li,vi) in enumerate(zip(poly.loop_indices,poly.vertices)):
                uv.data[li].uv=[(.02,.02),(.02,.06),(.98,.06),(.98,.02)][k] if is_rim else leaf_uv[o.name][vi]
    elif kind in ('bark','core') and len(o.data.polygons[0].vertices)==4:
        cylindrical_uv(o,uv,kind)
    else:
        coords=np.array([list(v.co) for v in o.data.vertices]);mins=coords.min(0);span=np.maximum(coords.max(0)-mins,.001)
        slot=sum(map(ord,o.name))%4
        for poly in o.data.polygons:
            n=poly.normal;axis=max(range(3),key=lambda i:abs(n[i]));axes=[i for i in range(3) if i!=axis]
            row=0 if n.z>.48 else (1 if n.y<-.25 else (3 if n.z<-.40 else 2))
            for li,vi in zip(poly.loop_indices,poly.vertices):
                p=(coords[vi]-mins)/span;local=(.04+.92*p[axes[0]],.04+.92*p[axes[1]])
                uv.data[li].uv=(.17*(slot%2)+local[0]*.48,.13*(slot//2)+local[1]*.48) if kind=='stone' else (local[0],local[1])
    o['stage']='dev6 material candidate; editable source and explicit GLB only'

def pose(amount):
    for name,basis in rest.items():bpy.data.objects[name].matrix_basis=basis.copy()
    for name,angle,axis in [('CrownPlatePivot_L',-48,'Z'),('CrownPlatePivot_R',48,'Z'),('CrownPlatePivot_C',-32,'X')]:
        bpy.data.objects[name].matrix_basis=rest[name]@Matrix.Rotation(math.radians(angle*amount),4,axis)
    bpy.context.view_layer.update()

def geometry_state():
    vs=[gp(o.matrix_world@v.co) for o in meshes for v in o.data.vertices]
    return {'min':[min(p[i] for p in vs) for i in range(3)],'max':[max(p[i] for p in vs) for i in range(3)],'radius':max(math.hypot(p[0],p[2]) for p in vs)}

def core_rays():
    verts=[];faces=[]
    for o in meshes:
        if o.name=='CoreSeed':continue
        start=len(verts);verts.extend(o.matrix_world@v.co for v in o.data.vertices)
        faces.extend(tuple(start+i for i in p.vertices) for p in o.data.polygons)
    tree=BVHTree.FromPolygons(verts,faces);blocked=0
    for x in [-.25,0,.25]:
        for y in [-.85,-.5,-.15]:
            a=bp((x,y,6));b=bp((x,y,1.09));d=b-a
            blocked+=tree.ray_cast(a,d.normalized(),d.length)[0] is not None
    return {'sample_count':9,'blocked':blocked}

report={'stage':'dev6_material_candidate','version':VERSION,'source_form_sha256':INPUT_SHA,'script_sha256':digest(Path(__file__)),
        'reference_sha256':root['reference_sha256'],'materials':list(m.name for m in materials.values()),'textures':texture_records,
        'editable_meshes':len(meshes),'triangles':sum(len(p.vertices)-2 for o in meshes for p in o.data.polygons),'uv_layer':'PaintUV','poses':{},'sweep':[],'exported':False}
assert len(meshes)==76 and len(materials)==4
report['source_uv_checks']={};bad_uv=[]
for o in meshes:
    o.data.calc_loop_triangles();uv=o.data.uv_layers.active;bad=0;tested=0
    for tri in o.data.loop_triangles:
        a,b,c=[o.data.vertices[i].co for i in tri.vertices]
        if (b-a).cross(c-a).length<=1e-9:continue
        tested+=1;ua,ub,uc=[uv.data[i].uv for i in tri.loops]
        det=(ub.x-ua.x)*(uc.y-ua.y)-(ub.y-ua.y)*(uc.x-ua.x)
        if abs(det)<=1e-10:bad+=1
    report['source_uv_checks'][o.name]={'tested_nondegenerate_triangles':tested,'collapsed_uv_triangles':bad,'layers':[layer.name for layer in o.data.uv_layers]}
    if bad:bad_uv.append((o.name,bad))
assert not bad_uv, bad_uv
for amount in [0,.25,.5,.75,1]:
    pose(amount);g=geometry_state();report['sweep'].append({'amount':amount,**g})
    assert g['radius']<=4.0 and g['min'][1]>=-3.00001 and g['max'][1]<=3.00001, g
for label,amount in [('closed',0),('open',1)]:
    pose(amount);g=geometry_state();rays=core_rays();report['poses'][label]={'bounds':g,'core_front_rays':rays}
    assert rays['blocked']==(9 if amount==0 else 0), rays
    if DO_RENDER:
        path=ART/('crown_material_'+label+'_'+VERSION+'.png');scene.render.filepath=str(path);bpy.ops.render.render(write_still=True)
        report['poses'][label]['preview']={'path':str(path.relative_to(PROJECT)),'sha256':digest(path)}
        print('CROWN_MATERIAL_PREVIEW',str(path),flush=True)
pose(0)
for img in bpy.data.images:
    if img.name.startswith(('stone_','bark_','leaf_','core_')) and not img.packed_file:img.pack()
source_path=SOURCE/'parasitic_crown.blend';bpy.ops.wm.save_as_mainfile(filepath=str(source_path));report['source_sha256']=digest(source_path)
if DO_EXPORT:
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:o.select_set(True)
    bpy.context.view_layer.objects.active=root
    glb=OUT/'parasitic_crown.glb'
    bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,export_apply=True,export_yup=True,export_extras=True,
                             export_texcoords=True,export_normals=True,export_materials='EXPORT',export_cameras=False,export_lights=False,export_animations=False)
    report['exported']=True;report['glb_sha256']=digest(glb);report['glb_bytes']=glb.stat().st_size
(ART/('crown_production_'+VERSION+'.json')).write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('CROWN_PRODUCTION_DONE',json.dumps({'meshes':len(meshes),'materials':len(materials),'triangles':report['triangles'],'exported':DO_EXPORT}),flush=True)
