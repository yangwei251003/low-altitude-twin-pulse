"""T03-A p5: joined limestone ledges and embedded thick curved roots.

Source-only geometry review. No runtime export, textures, baking or Godot.
"""
import bpy
import hashlib
import json
import math
import sys
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree

PROJECT=Path(__file__).resolve().parents[3]
SRC=PROJECT/'asset_sources/v3/shore_root'
ART=PROJECT/'artifacts/v3/art/shore_root'
BRIDGE=PROJECT/'assets/v3/root_arch/f1_root_arch.glb'
BRIDGE_SHA='a14fd39f649ddd00cf2316126349b841376334879022e6c9256b6ed323ddd581'
REFERENCE_SHA='5a5dace7fd687b6226cc68a7c9094f3050f6ef8c378252c32ee9a06ae30f5859'
SRC.mkdir(parents=True,exist_ok=True);ART.mkdir(parents=True,exist_ok=True)
assert hashlib.sha256(BRIDGE.read_bytes()).hexdigest()==BRIDGE_SHA
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
scene=bpy.context.scene
parts=[]
def bp(p):return Vector((p[0],-p[2],p[1]))
def gp(p):return [float(p.x),float(p.z),float(-p.y)]
def collection(name):
    c=bpy.data.collections.new(name);scene.collection.children.link(c);return c
model=collection('T03A_EDITABLE_MAIN_FORM')
studio=collection('STUDIO_NOT_ASSET')
reference=collection('READ_ONLY_ROOT_ARCH_ASSEMBLY')
root=bpy.data.objects.new('F1ShoreRoot',None);model.objects.link(root)
root['world_position_godot']=[-24.5,0,-6]
root['status']='p5 editable main-form study, no final materials or runtime export'
root['reference_sha256']=REFERENCE_SHA

def mat(name,colour):
    m=bpy.data.materials.new(name);m.diffuse_color=(*colour,1);m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*colour,1)
    p.inputs['Roughness'].default_value=.88;p.inputs['Specular IOR Level'].default_value=.21
    return m
stone=[mat('Study_Stone_Cool',(.235,.26,.27)),mat('Study_Stone_LightPlane',(.28,.295,.29)),
       mat('Study_Stone_Shadow',(.18,.205,.22)),mat('Study_Stone_WarmCut',(.29,.275,.24))]
soil=[mat('Study_Earth',(.245,.215,.165)),mat('Study_Wet_Silt',(.13,.16,.155))]
bark=[mat('Study_Bark',(.26,.185,.12)),mat('Study_Bark_LightPlane',(.31,.235,.15)),
      mat('Study_Bark_DeepFold',(.18,.14,.105))]

def mesh(name,vs,fs,materials,role,mi=None):
    d=bpy.data.meshes.new(name+'_EditableMesh');d.from_pydata([bp(v) for v in vs],[],fs);d.update()
    o=bpy.data.objects.new(name,d);model.objects.link(o);o.parent=root;o['role']=role
    for m in materials:d.materials.append(m)
    if mi:
        for p,j in zip(d.polygons,mi):p.material_index=j
    bpy.context.view_layer.objects.active=o;o.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.normals_make_consistent(inside=False);bpy.ops.object.mode_set(mode='OBJECT');o.select_set(False)
    parts.append(o);return o

def bvh(objects):
    vs=[];fs=[]
    for o in objects:
        if o.type!='MESH':continue
        offset=len(vs);vs.extend(o.matrix_world@v.co for v in o.data.vertices)
        fs.extend(tuple(offset+i for i in p.vertices) for p in o.data.polygons)
    return BVHTree.FromPolygons(vs,fs)
def top(tree,x,z):
    hit=tree.ray_cast(bp((x,12,z)),Vector((0,0,-1)),15)[0]
    return None if hit is None else float(hit.z)

PROFILE=[(-4.5,.06),(-4.3,.34),(-3.3,.80),(-2.1,1.39),(-.8,2.08),
         (.5,2.92),(1.7,3.70),(2.65,4.20),(3.5,4.48),(4.6,4.48)]
def base_height(x):
    for i in range(len(PROFILE)-1):
        x0,y0=PROFILE[i];x1,y1=PROFILE[i+1]
        if x<=x1:return y0+max(0.,min(1.,(x-x0)/(x1-x0)))*(y1-y0)
    return PROFILE[-1][1]

def rock_height(x,z):
    # Unequal long planes, not a lid. The last metre alone is a flat interface.
    h=base_height(x)
    if x<3.5:
        modulation=(.13*math.sin(x*1.15+z*.71)+.10*math.cos(z*1.7-x*.35))
        h+=modulation*min(1.,max(0.,(x+4.5)/1.3))*min(1.,max(0.,(3.5-x)/.65))
    elif abs(z)<=2.86:return 4.48
    # Rock ribs project beside the route and form an inclined broken edge.
    ridge=.33*math.exp(-((z+2.6)/.6)**2)*math.exp(-((x-.2)/2.6)**2)
    h+=ridge
    outside=max(0.,min(1.,(abs(z)-2.85)/2.9))
    h*=1.-.985*(outside**1.25)
    # A real open groove in the lower wet stone, not a painted moss stripe.
    if x<-.8 and z>3.4:
        h=max(.30,h)
        h*=1.-.92*math.exp(-((z-4.55)/.30)**2)
        h+=.16*math.exp(-((z-5.0)/.25)**2)
    return max(.05,h)

# Three large strata share the same continuous surface with interlocking seams.
# Every piece is closed and editable; all three extend into the supporting foot.
zrows=[-5.9,-5.1,-4.2,-3.3,-2.86,-2.0,-.9,.35,1.45,2.35,2.86,3.5,3.9,4.25,4.55,5.0,5.75]
west=[-2.7,-3.7,-4.1,-4.4,-4.5,-4.35,-4.5,-4.4,-4.5,-4.3,-4.5,-4.4,-4.5,-4.5,-4.5,-4.2,-3.1]
east=[2.7,3.5,4.15,4.58,4.58,4.58,4.58,4.58,4.58,4.58,4.58,4.25,3.8,3.35,2.8,2.25,.8]
def seam(index,z):
    return (-1.55 if index==0 else 1.35)+.27*math.sin(z*1.3+index*1.1)+.14*math.cos(z*.7-index)
for layer,name in enumerate(['West_Continuous_RockFoot','Middle_Joined_Limestone','Upper_Joined_ReceivingRock']):
    vs=[];fs=[];ids=[];columns=7
    for r,z in enumerate(zrows):
        a=west[r] if layer==0 else max(west[r],seam(layer-1,z))
        b=east[r] if layer==2 else min(east[r],seam(layer,z))
        a=min(a,b-.08)
        # Slanted planar ribs and non-identical boundary widths break the silhouette.
        for j in range(columns):
            t=j/(columns-1);x=a+(b-a)*t
            zz=z if j in (0,columns-1) or r in (0,len(zrows)-1) else z+.08*math.sin(j*2.7+r*1.9)
            vs.append((x,rock_height(x,zz),zz))
    n=len(vs);vs +=[(x,0,z) for x,y,z in vs]
    for r in range(len(zrows)-1):
        for j in range(columns-1):
            a=r*columns+j
            fs.append((a,a+1,a+1+columns,a+columns))
            ids.append(1 if r in (4,5,6,7,8,9) else (3 if (layer==0 and r<3) else 0))
            fs.append((a+n,a+columns+n,a+1+columns+n,a+1+n));ids.append(2)
    outline=list(range(columns))+[r*columns+columns-1 for r in range(1,len(zrows))]
    outline+=list(range(n-2,n-columns-1,-1))+[r*columns for r in range(len(zrows)-2,0,-1)]
    mids={}
    for a in outline:
        x,y,z=vs[a];row=a//columns;col=a%columns
        # The exposed cut is several broad fractured planes, not one vertical
        # rectangle. Interior seams retain exactly matching positions.
        dx=0.;dz=0.
        if (layer==0 and col==0) or (layer==2 and col==columns-1):
            dx=-math.copysign(.22+.10*math.sin(z*1.3)**2,x)
        if row in (0,len(zrows)-1):dz=-math.copysign(.16,z)
        mids[a]=len(vs);vs.append((x+dx,y*(.43+.08*math.sin(z*1.9+x)),z+dz))
    for j,a in enumerate(outline):
        b=outline[(j+1)%len(outline)]
        fs.append((a,b,mids[b],mids[a]));ids.append(0)
        fs.append((mids[a],mids[b],b+n,a+n));ids.append(2 if j%3 else 3)
    mesh(name,vs,fs,stone,'individually editable structural stone',ids)

def ledge(name,x0,x1,z0,z1,h0,h1,phase):
    # Broad interlocking geological layers, rather than small independent posts.
    perimeter=[(.0,.17),(.12,.0),(.73,.025),(1.,.18),(.95,.81),(.78,1.),(.19,.93),(.015,.69)]
    vertices=[]
    for level in range(3):
        for i,(u,v) in enumerate(perimeter):
            x=x0+(x1-x0)*u;z=z0+(z1-z0)*v
            height=h0+(h1-h0)*u+.07*math.sin(i*1.8+phase)
            if level==0:y=.03
            elif level==1:
                y=height*.72;x+=(.10*math.sin(i*2.1+phase));z+=.08*math.cos(i*1.7+phase)
            else:y=height
            vertices.append((x,y,z))
    faces=[tuple(reversed(range(8))),tuple(range(16,24))];ids=[2,1]
    for k in range(2):
        for j in range(8):faces.append((k*8+j,k*8+(j+1)%8,(k+1)*8+(j+1)%8,(k+1)*8+j));ids.append((0,2,0,3,0,2,0,0)[j])
    mesh(name,vertices,faces,stone,'individually editable structural stone',ids)
ledge('Lower_Broad_Limestone_Ledge',-3.85,-.55,-3.55,-.30,1.18,1.85,.3)
ledge('Middle_Interlocked_Limestone_Ledge',-2.1,1.4,-3.55,-.80,2.40,3.14,1.7)
ledge('Upper_Embedded_Limestone_Ledge',.6,3.35,-4.5,-1.0,3.95,4.54,2.8)
ledge('South_Fractured_RockShoulder',.8,2.5,3.85,4.7,2.4,2.86,4.1)

bpy.context.view_layer.update();stone_tree=bvh(parts)
stone_triangles=[]
for ob in parts:
    ob.data.calc_loop_triangles()
    for tri in ob.data.loop_triangles:
        points=[Vector(gp(ob.matrix_world@ob.data.vertices[i].co)) for i in tri.vertices]
        normal=(points[1]-points[0]).cross(points[2]-points[0])
        if normal.y>1e-5:stone_triangles.append((points,normal))

# Disconnected soil deposits sit in the actual rock surface, with buried volume.
# They neither bridge a gap nor define a separate strip hovering above the slope.
def soil_patch(name,cx,cz,rx,rz,phase,wet=False):
    # Clip actual rock triangles to the deposit outline. Merely sampling a few
    # corners makes a new soil triangulation cut through the old rock mesh.
    outline=[Vector((cx+rx*math.cos(a),cz+rz*math.sin(a)))
             for a in [phase*.1+math.tau*j/12 for j in range(12)]]
    def cross(a,b):return a.x*b.y-a.y*b.x
    def clip(poly,a,b):
        if not poly:return []
        result=[];last=poly[-1];ld=cross(b-a,last-a)
        for current in poly:
            cd=cross(b-a,current-a)
            if (cd>=-1e-9)!=(ld>=-1e-9):
                t=ld/(ld-cd);result.append(last+(current-last)*t)
            if cd>=-1e-9:result.append(current)
            last=current;ld=cd
        return result
    vertices=[];faces=[]
    for points,normal in stone_triangles:
        poly=[Vector((p.x,p.z)) for p in points]
        for i,a in enumerate(outline):poly=clip(poly,a,outline[(i+1)%len(outline)])
        clean=[]
        for p in poly:
            if not clean or (p-clean[-1]).length>1e-6:clean.append(p)
        if len(clean)>1 and (clean[0]-clean[-1]).length<1e-6:clean.pop()
        poly=clean
        if len(poly)<3:continue
        area=abs(sum(cross(poly[i],poly[(i+1)%len(poly)]) for i in range(len(poly))))*.5
        if area<1e-5:continue
        # Only exposed top triangles receive soil; hidden interlocking faces do not.
        center=sum(poly,Vector((0,0)))/len(poly)
        sample=points[0].y-(normal.x*(center.x-points[0].x)+normal.z*(center.y-points[0].z))/normal.y
        visible=top(stone_tree,center.x,center.y)
        if visible is None or visible-sample>.025:continue
        offset=len(vertices);count=len(poly)
        for p in poly:
            h=points[0].y-(normal.x*(p.x-points[0].x)+normal.z*(p.y-points[0].z))/normal.y
            vertices.append((p.x,h+.012,p.y))
        vertices +=[(x,max(.005,y-.16),z) for x,y,z in vertices[offset:offset+count]]
        faces.extend([tuple(offset+i for i in range(count)),tuple(offset+count+i for i in reversed(range(count)))])
        for j in range(count):faces.append((offset+j,offset+(j+1)%count,offset+(j+1)%count+count,offset+j+count))
    return mesh(name,vertices,faces,[soil[int(wet)]],'embedded soil deposit')
soil_patch('West_Soil_Deposit',-3.08,-.1,1.05,1.9,.7)
soil_patch('Middle_Soil_Deposit',-.68,.28,1.65,1.65,2.2)
soil_patch('Upper_Soil_Deposit',1.75,-.35,1.43,1.8,4.0)
soil_patch('Wet_Groove_Silt',-3.15,4.55,.63,.16,1.0,True)

# Exact functional contact is confined to the last roughly one metre.
vs=[];fs=[]
for x,zwidth,y in [(3.35,2.66,4.43),(3.55,2.86,4.5),(4.50,2.86,4.5)]:
    for z in [-zwidth,-1.3,0,1.3,zwidth]:vs.append((x,y,z))
n=len(vs);vs +=[(x,y-.24,z) for x,y,z in vs]
for i in range(2):
    for j in range(4):a=i*5+j;fs.append((a,a+1,a+6,a+5));fs.append((a+n,a+5+n,a+6+n,a+1+n))
edge=[0,1,2,3,4,9,14,13,12,11,10,5]
for i,a in enumerate(edge):b=edge[(i+1)%len(edge)];fs.append((a,b,b+n,a+n))
mesh('LastMetre_5_72m_ReceivingContact',vs,fs,[soil[0]],'exact final metre interface')


def catmull(values,t):
    segment=min(len(values)-2,int(t));f=t-segment
    p0=Vector(values[max(segment-1,0)]);p1=Vector(values[segment]);p2=Vector(values[segment+1]);p3=Vector(values[min(segment+2,len(values)-1)])
    return .5*((2*p1)+(-p0+p2)*f+(2*p0-5*p1+4*p2-p3)*f*f+(-p0+3*p1-3*p2+p3)*f*f*f)


def embedded_root(name,control,widths,depths,phase):
    # Plan-view curves and non-circular section variation are real geometry.
    # Root centres follow actual underlying rock, burying about one third of
    # their depth. This prevents a floating black cavity beneath the front root.
    count=(len(control)-1)*6+1;centers=[];cross=[]
    for i in range(count):
        t=(len(control)-1)*i/(count-1);p=catmull(control,t)
        seg=min(len(control)-2,int(t));fraction=t-seg
        w=widths[seg]+(widths[seg+1]-widths[seg])*fraction
        d=depths[seg]+(depths[seg+1]-depths[seg])*fraction
        ground=top(stone_tree,p.x,p.y)
        if ground is None:raise RuntimeError('Root outside rock foot '+name)
        centers.append(Vector((p.x,ground+d*.22,p.y)));cross.append((w,d))
    n=12;verts=[];faces=[];mi=[]
    for i,center in enumerate(centers):
        tangent=(centers[min(i+1,count-1)]-centers[max(i-1,0)]).normalized()
        side=tangent.cross(Vector((0,1,0))).normalized();up=side.cross(tangent).normalized()
        w,d=cross[i];twist=.23*math.sin(i*.19+phase)
        for j in range(n):
            a=math.tau*j/n+twist
            large_lobe=1+.17*math.sin(a*3+i*.13+phase)+.07*math.cos(a*5-i*.15)
            p=center+side*(math.cos(a)*w*.5*large_lobe)+up*(math.sin(a)*d*.5*large_lobe)
            verts.append(tuple(p))
    faces=[tuple(reversed(range(n))),tuple((count-1)*n+j for j in range(n))];mi=[2,2]
    for i in range(count-1):
        for j in range(n):
            faces.append((i*n+j,i*n+(j+1)%n,(i+1)*n+(j+1)%n,(i+1)*n+j))
            mi.append(0)
    ob=mesh(name,verts,faces,bark,'editable broad load-bearing root',mi)
    for polygon in ob.data.polygons:
        if polygon.index>=2:polygon.use_smooth=True
    # Inspect the produced mesh, including its curved local frame and lobes.
    # At least one lower vertex of each section must enter supporting rock;
    # this catches clearance that nominal vertical radius alone would miss.
    contact=[]
    for i in range(count):
        low=sorted([gp(v.co) for v in ob.data.vertices[i*n:(i+1)*n]],key=lambda p:p[1])[:3]
        gaps=[]
        for x,y,z in low:
            support=top(stone_tree,x,z)
            if support is not None:gaps.append(y-support)
        contact.append({'section':i,'lowest_vertex_gaps':gaps,
                        'minimum_gap':min(gaps) if gaps else None})
    return ob,contact

root_records=[]
for spec in [
    ('Primary_Curved_LoadRoot',[(-3.95,1.6),(-2.85,2.1),(-1.65,2.85),(-.15,2.65),(1.15,3.25),(2.5,3.1),(4.05,3.47)],
     [.40,1.20,1.70,1.85,1.60,1.25,.52],[.28,.90,1.50,1.80,1.45,.85,.32],.6),
    ('Lower_Fork_Embedded_In_WetRock',[(-1.68,2.85),(-2.25,3.27),(-2.8,3.7),(-3.75,3.9)],
     [1.22,1.03,.72,.24],[.95,.80,.53,.18],2.1),
    ('Side_Fork_StoneCrease',[(-.1,2.7),(.05,3.6),(.4,4.35),(.8,5.0)],
     [1.35,1.18,.85,.22],[1.0,.87,.60,.18],3.2),
    ('North_PartlyBuried_CounterRoot',[(-3.2,-3.3),(-1.85,-3.57),(-.15,-3.2),(1.45,-3.55),(3.5,-3.33)],
     [.25,.58,1.05,.95,.30],[.18,.42,.76,.72,.22],4.3)]:
    obj,samples=embedded_root(*spec);root_records.append({'name':obj.name,'contact_samples':samples})

MARKERS={'GroundOrigin':(0,0,0),'BridgeJoin':(4.5,4.5,0),'WestBlend':(-4.3,.34,0)}
for name,at in MARKERS.items():
    o=bpy.data.objects.new(name,None);model.objects.link(o);o.parent=root;o.location=bp(at)
    o.empty_display_type='PLAIN_AXES';o.empty_display_size=.45;o['godot_local_metres']=list(at)
bpy.context.view_layer.update();asset_tree=bvh(parts)

def move(o,c):
    for old in list(o.users_collection):old.objects.unlink(o)
    c.objects.link(o)
before=set(bpy.data.objects);bpy.ops.import_scene.gltf(filepath=str(BRIDGE))
imported=[o for o in bpy.data.objects if o not in before]
for o in imported:
    move(o,reference);o['read_only_assembly_reference']=True
    if o.parent not in imported:o.location+=bp((24.5,0,0))
bpy.context.view_layer.update();bridge_tree=bvh(imported)
join=[]
for z in [-2.75,-2.65,-1.8,0,1.8,2.65,2.75]:
    a=top(asset_tree,4.48,z);b=top(bridge_tree,4.52,z)
    join.append({'z':z,'shoulder_y':a,'bridge_y':b,'step_m':None if a is None or b is None else b-a})
gully=[{'x':x,'samples':[{'z':z,'y':top(asset_tree,x,z)} for z in [3.9,4.55,5.0]]} for x in [-3.6,-3.1]]
root_contact=all(p['minimum_gap'] is not None and p['minimum_gap']<=.02 for r in root_records for p in r['contact_samples'])
coords=[gp(o.matrix_world@v.co) for o in parts for v in o.data.vertices]
triangles=0
for o in parts:o.data.calc_loop_triangles();triangles+=len(o.data.loop_triangles)
checks={'all_seven_join_samples_step_le_0_12m':all(p['step_m'] is not None and abs(p['step_m'])<=.12 for p in join),
        'gully_two_cross_profiles_have_0_12m_banks':all(all(r['samples'][j]['y']-r['samples'][1]['y']>.12 for j in [0,2]) for r in gully),
        'actual_mesh_root_sections_enter_supporting_rock':root_contact,
        'main_form_within_authored_envelope':all(-4.51<=p[0]<=4.61 and -.01<=p[1]<=5.01 and -6.01<=p[2]<=6.01 for p in coords),
        'frozen_bridge_unchanged':hashlib.sha256(BRIDGE.read_bytes()).hexdigest()==BRIDGE_SHA}
report={'asset':'T03-A F1 shore root','revision':'p5','scope':'source-only geometric main-form study, native Blender BVH; not exported or engine tested',
        'blender':bpy.app.version_string,'reference_sha256':REFERENCE_SHA,'world_root_godot':[-24.5,0,-6],
        'markers_godot':MARKERS,'editable_meshes':len(parts),'triangles':triangles,
        'bounds_godot':{'min':[min(v[i] for v in coords) for i in range(3)],'max':[max(v[i] for v in coords) for i in range(3)]},
        'actual_bridge_join_samples':join,'gully_cross_profiles':gully,'root_contact_samples':root_records,
        'geometry_checks':checks,'bridge_reference_sha256':hashlib.sha256(BRIDGE.read_bytes()).hexdigest(),
        'changes_from_p4':['Four broad interlocked limestone ledges rise from the continuous rock foot.',
                           'Soil is clipped to actual exposed triangles, fixing incompatible triangulation intersections.',
                           'Main root has thicker asymmetric sections and continuous surface shading without fake longitudinal colour bands.',
                           'Final metre interface and real wet gully retain the same measurements.'],
        'limits':['No final UV, textures or baking.','No runtime GLB or Godot evidence.',
                  'Section contact proves some lower vertices enter rock, not that every part of each section touches; visual review is required.',
                  'No claim of artistic approval or full 5.5m walking clearance along the entire rock slope.']}

def aim(o,p):o.rotation_euler=(bp(p)-o.location).to_track_quat('-Z','Y').to_euler()
def light(name,at,power,size,colour):
    d=bpy.data.lights.new(name,'AREA');d.energy=power;d.size=size;d.color=colour
    o=bpy.data.objects.new(name,d);studio.objects.link(o);o.location=bp(at);aim(o,(0,2,0))
light('Study_Key',(-7,17,12),2100,10,(1,.95,.88));light('Study_Fill',(13,12,-9),1600,12,(.84,.9,1))
light('Study_Rim',(-6,12,-12),1800,9,(1,.94,.82))
bpy.ops.mesh.primitive_plane_add(size=160,location=(0,0,-.003));floor=bpy.context.object;move(floor,studio)
floor.name='Studio_Ground_NOT_ASSET';floor.data.materials.append(mat('Studio_Neutral',(.235,.25,.26)))
cd=bpy.data.cameras.new('ReviewCamera');camera=bpy.data.objects.new('ReviewCamera',cd);studio.objects.link(camera);scene.camera=camera;cd.type='ORTHO'
def view(at,target,scale):camera.location=bp(at);aim(camera,target);cd.ortho_scale=scale
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=10;scene.cycles.use_denoising=True
scene.render.threads_mode='FIXED';scene.render.threads=2
scene.render.resolution_x=1280;scene.render.resolution_y=900;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.world.use_nodes=True
scene.world.node_tree.nodes.get('Background').inputs['Color'].default_value=(.3,.33,.36,1)
scene.world.node_tree.nodes.get('Background').inputs['Strength'].default_value=.45
scene.view_settings.view_transform='AgX';scene.view_settings.look='AgX - Medium High Contrast'
reference.hide_render=True;reference.hide_viewport=True
view((15,16,20),(0,2.1,0),16.4)
path=SRC/'f1_shore_root_p5.blend';scene['geometry_report']=json.dumps(report,ensure_ascii=False)
bpy.ops.wm.save_as_mainfile(filepath=str(path))
report['source']={'path':str(path),'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
(ART/'geometry_p5.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('SHORE_P5_GEOMETRY '+json.dumps(checks))
if '--render' in sys.argv:
    scene.render.filepath=str(ART/'01-default-oblique-p5.png');bpy.ops.render.render(write_still=True)
    reference.hide_render=False;reference.hide_viewport=False
    view((-13,17,23),(4.1,3.25,0),23.5)
    scene.render.filepath=str(ART/'02-bridge-assembly-offline-p5.png');bpy.ops.render.render(write_still=True)
assert hashlib.sha256(BRIDGE.read_bytes()).hexdigest()==BRIDGE_SHA
print('SHORE_P5_DONE')
