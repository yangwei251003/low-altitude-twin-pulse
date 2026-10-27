"""Editable single-prop block/material study. Not an exported runtime asset.

Coordinates below: u=Godot Z (horizontal), v=Godot Y, t=Godot X.
The complete moving slab fits 1 x 5 x 7 metres. Original procedural materials.
Run Blender background with --threads 2; renders require the shared GPU/CPU slot.
"""
from pathlib import Path
import bpy, bmesh, math, json, hashlib
from mathutils import Vector

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
REF=ROOT/'references/v3/production/rising_seal/rising_seal_reference_v1.png'
assert hashlib.sha256(REF.read_bytes()).hexdigest()=='836f5f42091d21ba9561cf78c387fc7220aa3ad840a7ffc1b70906021ea1d3f6'
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
scene=bpy.context.scene
scene.unit_settings.system='METRIC'
collection=bpy.data.collections.new('Editable_RisingSeal');scene.collection.children.link(collection)
root=bpy.data.objects.new('RisingSeal',None);collection.objects.link(root)
parts=[]

def pos(u,v,t):return (t,-u,v)

def material(name,color,roughness=.85,metal=0):
    m=bpy.data.materials.new(name);m.use_nodes=True
    p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Roughness'].default_value=roughness
    p.inputs['Metallic'].default_value=metal
    p.inputs['Specular IOR Level'].default_value=.25
    return m

stone=material('Seal_CoolMineral',(.27,.31,.32))
back=material('Seal_RecessedStone',(.19,.23,.23))
bronze=material('Seal_AgedBronze',(.21,.19,.105),.66,.5)
patina=material('Seal_TealPatina',(.10,.24,.20),.8,.25)
wood=material('Seal_RoundedRoots',(.20,.115,.06),.9)
core=material('Seal_TealInlay',(.06,.36,.32),.45,.15)

# Large mineral colour fields, no photographic tiled noise or baked studio light.
nodes=stone.node_tree.nodes;links=stone.node_tree.links
p=next(n for n in nodes if n.type=='BSDF_PRINCIPLED')
tex=nodes.new('ShaderNodeTexNoise');tex.inputs['Scale'].default_value=2.1
tex.inputs['Detail'].default_value=1.1;tex.inputs['Roughness'].default_value=.4
ramp=nodes.new('ShaderNodeValToRGB')
ramp.color_ramp.elements[0].position=.22;ramp.color_ramp.elements[0].color=(.20,.235,.25,1)
ramp.color_ramp.elements[1].position=.78;ramp.color_ramp.elements[1].color=(.38,.40,.385,1)
links.new(tex.outputs['Fac'],ramp.inputs[0]);links.new(ramp.outputs[0],p.inputs['Base Color'])
vor=nodes.new('ShaderNodeTexVoronoi');vor.inputs['Scale'].default_value=5.4
gray=nodes.new('ShaderNodeRGBToBW');links.new(vor.outputs['Color'],gray.inputs[0])
facets=nodes.new('ShaderNodeValToRGB');facets.color_ramp.interpolation='CONSTANT'
for element in list(facets.color_ramp.elements)[1:]:facets.color_ramp.elements.remove(element)
for i,(at,color) in enumerate([(0,(.22,.25,.27,1)),(.26,(.29,.32,.32,1)),(.43,(.38,.38,.34,1)),(.61,(.32,.35,.36,1)),(.79,(.43,.425,.38,1))]):
    e=facets.color_ramp.elements[0] if i==0 else facets.color_ramp.elements.new(at)
    e.position=at;e.color=color
links.new(gray.outputs[0],facets.inputs[0]);links.new(facets.outputs[0],p.inputs['Base Color'])
wood_nodes=wood.node_tree.nodes;wood_links=wood.node_tree.links
wp=next(n for n in wood_nodes if n.type=='BSDF_PRINCIPLED')
uv=wood_nodes.new('ShaderNodeTexCoord');mapping=wood_nodes.new('ShaderNodeVectorMath');mapping.operation='MULTIPLY';mapping.inputs[1].default_value=(8,1.5,1)
noise=wood_nodes.new('ShaderNodeTexNoise');noise.inputs['Scale'].default_value=3;noise.inputs['Detail'].default_value=2
wr=wood_nodes.new('ShaderNodeValToRGB');wr.color_ramp.elements[0].position=.18;wr.color_ramp.elements[0].color=(.10,.057,.03,1)
wr.color_ramp.elements[1].position=.8;wr.color_ramp.elements[1].color=(.30,.21,.125,1)
wood_links.new(uv.outputs['UV'],mapping.inputs[0]);wood_links.new(mapping.outputs[0],noise.inputs['Vector']);wood_links.new(noise.outputs['Fac'],wr.inputs[0]);wood_links.new(wr.outputs[0],wp.inputs['Base Color'])

def finish(obj,name,mat):
    obj.name=name
    for c in list(obj.users_collection):c.objects.unlink(obj)
    collection.objects.link(obj);obj.parent=root
    obj.data.materials.append(mat)
    parts.append(obj)
    return obj

def prism(name,poly,t0,t1,mat,bevel=0):
    n=len(poly);vertices=[pos(u,v,t) for t in [t0,t1] for u,v in poly]
    faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]
    faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    data=bpy.data.meshes.new(name);data.from_pydata(vertices,[],faces);data.update()
    obj=bpy.data.objects.new(name,data);scene.collection.objects.link(obj)
    bm=bmesh.new();bm.from_mesh(data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(data);bm.free()
    finish(obj,name,mat)
    if bevel:
        bpy.context.view_layer.objects.active=obj;obj.select_set(True)
        mod=obj.modifiers.new('Authored_worn_edge','BEVEL');mod.width=bevel;mod.segments=1
        bpy.ops.object.modifier_apply(modifier=mod.name);obj.select_set(False)
    return obj

# Continuous backing closes the decorative panel seams, without false holes.
outline=[(-3.5,-2.5),(3.5,-2.5),(3.5,2.2),(3.25,2.5),(-3.28,2.5),(-3.5,2.27)]
prism('ContinuousSlab',outline,-.5,.22,back,.055)
cuts=[-3.46,-1.80,-.02,1.82,3.46]
for row in range(2):
    for col in range(4):
        left,right=cuts[col]+.018,cuts[col+1]-.018
        lower=-2.46 if row==0 else -.10
        upper=-.15 if row==0 else 2.46
        chamfer=.14 if col in [0,3] and row==1 else .065
        poly=[(left,lower),(right,lower+.025*(col%2)),(right,upper-chamfer),(right-chamfer,upper),(left+chamfer,upper-.018*(col%3)),(left,upper-chamfer)]
        panel=prism('StoneSection_%d_%d'%(row,col),poly,.135,.35+(.015 if (row+col)%3==0 else 0),stone,.105)
        # Local recess behind each actual root corridor; it does not flatten roots.
        bm=bmesh.new();bm.from_mesh(panel.data)
        front=[f for f in bm.faces if f.normal.x>.65]
        bmesh.ops.subdivide_edges(bm,edges=list({e for f in front for e in f.edges}),cuts=4,use_grid_fill=True)
        for vertex in bm.verts:
            if vertex.co.x<.23:continue
            u,v=-vertex.co.y,vertex.co.z
            centre=(2.92+.22*math.sin((v+2.39)/4.78*math.tau+(1 if u>0 else -1)*.5))
            distance=abs(abs(u)-centre)
            if distance<.47:vertex.co.x-=.17*max(0,1-distance/.47)
            vertex.co.x+=.018*math.sin(u*2.3+v*1.7)*math.sin(v*1.8-u)
        bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(panel.data);bm.free()

def cylinder(name,u,v,t,radius,depth,mat,vertices=48):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=radius,depth=depth,location=pos(u,v,t),rotation=(0,math.pi/2,0))
    o=finish(bpy.context.object,name,mat)
    bpy.context.view_layer.objects.active=o;bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    return o

def torus(name,u,v,t,radius,tube,mat):
    bpy.ops.mesh.primitive_torus_add(major_segments=64,minor_segments=8,location=pos(u,v,t),rotation=(0,math.pi/2,0),major_radius=radius,minor_radius=tube)
    o=finish(bpy.context.object,name,mat)
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    return o

cylinder('SealRecess',0,-.10,.37,.70,.055,back)
cylinder('SealBronzeBoss',0,-.10,.40,.60,.10,bronze)
cylinder('SealEnergyGlass',0,-.10,.45,.405,.08,core,12)
torus('SealOuterRing',0,-.10,.435,.53,.035,bronze)
torus('SealPatinaRing',0,-.10,.445,.445,.018,patina)
for side in [-1,1]:
    band=[(.58,-.36),(1.10,-.42),(1.38,-.27),(2.88,-.22),(3.16,-.08),(3.16,.11),(2.86,-.03),(1.32,-.07),(1.05,-.21),(.58,-.18)]
    prism('BronzeChannel_'+str(side),[(u*side,v) for u,v in band],.365,.392,bronze,.016)
    for u in [-1.8,1.82]:
        v=side*2.12
        prism('PanelClamp_%s_%s'%(u,side),[(u-.14,v-.28),(u+.14,v-.28),(u+.14,v+.28),(u-.14,v+.28)],.35,.45,bronze,.025)
        for off in [-.18,.18]:cylinder('ClampRivet',u,v+off,.46,.042,.025,patina,12)

def rounded_root(name,centres,radii):
    """Closed tapered root with a full oval cross-section and broad uneven ridges."""
    vertices=[];n=12
    for i,(u,v,t) in enumerate(centres):
        p=Vector(pos(u,v,t))
        previous=Vector(pos(*centres[max(0,i-1)]));following=Vector(pos(*centres[min(len(centres)-1,i+1)]))
        tangent=(following-previous).normalized()
        a=Vector((1,0,0));a=(a-tangent*a.dot(tangent)).normalized();b=tangent.cross(a).normalized()
        for j in range(n):
            angle=math.tau*j/n;ridge=1+.09*math.sin(angle*3+i*.45)+.035*math.cos(angle*5-i*.4)
            vertices.append(p+(a*math.cos(angle)*.72+b*math.sin(angle))*radii[i]*ridge)
    faces=[]
    for i in range(len(centres)-1):
        for j in range(n):faces.append((i*n+j,i*n+(j+1)%n,(i+1)*n+(j+1)%n,(i+1)*n+j))
    faces.extend([tuple(reversed(range(n))),tuple(range((len(centres)-1)*n,len(centres)*n))])
    data=bpy.data.meshes.new(name);data.from_pydata(vertices,[],faces);data.update()
    ob=bpy.data.objects.new(name,data);scene.collection.objects.link(ob);finish(ob,name,wood)
    bm=bmesh.new();bm.from_mesh(data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(data);bm.free()
    layer=data.uv_layers.new(name='RootDetailUV')
    for poly in data.polygons:
        for li in poly.loop_indices:
            vertex=data.loops[li].vertex_index
            layer.data[li].uv=((vertex%n)/n,(vertex//n)/(len(centres)-1))
    for p in data.polygons:p.use_smooth=True
    return ob

for side in [-1,1]:
    points=[];radii=[]
    for i in range(27):
        f=i/26;v=-2.39+4.78*f
        u=side*(2.92+.22*math.sin(f*math.tau+side*.5))
        middle=math.sin(math.pi*f)**.4
        points.append((u,v,.20+.065*middle));radii.append(.025+.22*middle)
    rounded_root('RootCorner_'+str(side),points,radii)
    for strand in [-1,1]:
        braid=[];sizes=[]
        for i,(u,v,t) in enumerate(points):
            f=i/(len(points)-1);middle=math.sin(math.pi*f)**.5
            braid.append((u+.16*strand*middle*math.cos(f*math.tau*1.4),v,t+.07*middle*math.sin(f*math.tau*1.4)))
            sizes.append((.025+.062*middle))
        rounded_root('RootBraid_%s_%s'%(side,strand),braid,sizes)
    points=[];radii=[]
    for i in range(15):
        f=i/14;points.append((side*(2.89-.72*f),1.45+.78*f,.35));radii.append(.13*(1-f)+.025)
    rounded_root('RootFork_'+str(side),points,radii)

for name,u,v,t in [('Centre',0,0,0),('BottomContact',0,-2.5,0),('StateInlay',0,-.1,.49)]:
    marker=bpy.data.objects.new(name,None);collection.objects.link(marker);marker.parent=root;marker.location=pos(u,v,t)
bpy.context.view_layer.update()
points=[o.matrix_world@v.co for o in parts for v in o.data.vertices]
bounds={'min':[min(p[k] for p in points) for k in range(3)],'max':[max(p[k] for p in points) for k in range(3)]}
checks=[]
def check(name,ok,detail=None):checks.append({'name':name,'passed':bool(ok),'detail':detail})
check('all_inside_moving_envelope',all(bounds['min'][k]>=low-1e-5 and bounds['max'][k]<=high+1e-5 for k,(low,high) in enumerate([(-.5,.5),(-3.5,3.5),(-2.5,2.5)])),bounds)
for ob in parts:
    bm=bmesh.new();bm.from_mesh(ob.data)
    check(ob.name+'_closed',all(e.is_manifold for e in bm.edges))
    bm.free()

studio=bpy.data.collections.new('Studio_NotExported');scene.collection.children.link(studio)
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-2.53));floor=bpy.context.object
for c in list(floor.users_collection):c.objects.unlink(floor)
studio.objects.link(floor);floor.data.materials.append(material('StudioGrey',(.21,.23,.23)))
camdata=bpy.data.cameras.new('ReviewCamera');camera=bpy.data.objects.new('ReviewCamera',camdata);studio.objects.link(camera)
camera.location=(12,10,9);target=Vector((0,0,.0));camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler()
camdata.type='ORTHO';camdata.ortho_scale=10;scene.camera=camera
for name,loc,power,size in [('Key',(8,3,11),1600,8),('Fill',(3,-8,5),1000,7)]:
    data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size
    obj=bpy.data.objects.new(name,data);studio.objects.link(obj);obj.location=loc;obj.rotation_euler=(Vector((0,0,0))-obj.location).to_track_quat('-Z','Y').to_euler()
scene.world.color=(.22,.22,.22)
scene.render.engine='CYCLES';scene.cycles.samples=24;scene.cycles.use_denoising=True
scene.render.threads_mode='FIXED';scene.render.threads=2
scene.render.resolution_x=1200;scene.render.resolution_y=960;scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX'
blend=HERE/'rising_seal_source_p1.blend'
bpy.ops.wm.save_as_mainfile(filepath=str(blend))
report={'stage':'Editable source/basic material, no UV atlas/GLB or engine acceptance','reference':str(REF),'bounds_blender':bounds,'triangles':sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in parts),'parts':len(parts),'checks':checks,'passed':all(c['passed'] for c in checks),'source_sha256':hashlib.sha256(blend.read_bytes()).hexdigest()}
(HERE/'source_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
assert report['passed'],[(c['name'],c['detail']) for c in checks if not c['passed']]
scene.render.filepath=str(HERE/'rising_seal_source_p1.png');bpy.ops.render.render(write_still=True)
print('RISING_SEAL_SOURCE',json.dumps({'passed':report['passed'],'checks':len(checks),'triangles':report['triangles']}))
