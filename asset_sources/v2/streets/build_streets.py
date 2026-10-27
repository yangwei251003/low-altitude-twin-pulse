"""Editable meter-scale waterfront street kit. Blender 5.2 background builder.
All source geometry is authored here except explicitly recorded Kenney vehicles.
Blender Z-up -> exported Godot Y-up, fronts face Godot +Z.
"""
import bpy, math, random, json, hashlib, shutil
from pathlib import Path
from mathutils import Vector

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
OUT=ROOT/'assets/v2/streets'
BLENDS=HERE/'blend'
for p in [OUT,BLENDS]: p.mkdir(parents=True,exist_ok=True)
random.seed(20261014)
META=[]

def material(name, hexcolor, group='matte', alpha=1):
    rgb=[int(hexcolor[i:i+2],16)/255 for i in (0,2,4)]
    linear=[v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in rgb]
    m=bpy.data.materials.new(name);m.diffuse_color=(*linear,alpha);m.use_nodes=True;m['batch_group']=group
    m.node_tree.nodes.clear();s=m.node_tree.nodes.new('ShaderNodeBsdfPrincipled');output=m.node_tree.nodes.new('ShaderNodeOutputMaterial');m.node_tree.links.new(s.outputs['BSDF'],output.inputs['Surface']);s.inputs['Base Color'].default_value=(*linear,alpha)
    s.inputs['Roughness'].default_value={'matte':.72,'metal':.34,'glass':.18,'clear':.15,'emit':.45}[group]
    s.inputs['Metallic'].default_value=.5 if group=='metal' else .12 if group=='glass' else 0
    if group=='clear':
        s.inputs['Alpha'].default_value=alpha;m.surface_render_method='DITHERED'
    if group=='emit':
        s.inputs['Emission Color'].default_value=(*linear,1);s.inputs['Emission Strength'].default_value=.7
    return m

STONE=material('Warm architectural concrete','CAC6B8')
CREAM=material('Ivory limestone coping','F0E8D3')
BRICK=material('Terracotta facade','B7886E')
WOOD=material('Oiled cedar','AD805A')
SOIL=material('Soil and timber end grain','625A46')
LEAF=material('Foliage sage','61835C')
LEAF2=material('Foliage sunlit','829758')
TEAL=material('Harbor teal enamel','39868D','metal')
DARK=material('Midnight powdercoat','273E49','metal')
METAL=material('Brushed steel','9BAEAF','metal')
GLASS=material('Blue glazed facade','447785','glass')
CLEAR=material('Shelter safety glass','86C2C4','clear',.38)
AMBER=material('Safety ochre','DFA64F')
RED=material('Warm red traffic lens','DA715A','emit')
GREEN=material('Jade traffic lens','78BD95','emit')
LIGHT=material('Warm lamp diffuser','FFE5A5','emit')

def clear():
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    bpy.context.scene.cursor.location=(0,0,0)

def finish(o,name,mat,bevel=0):
    o.name=name;o.data.materials.append(mat)
    bpy.context.view_layer.objects.active=o
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if bevel:
        mod=o.modifiers.new('Manufactured edge radius','BEVEL');mod.width=bevel;mod.segments=1
        bpy.ops.object.modifier_apply(modifier=mod.name)
        mod=o.modifiers.new('Weighted face normals','WEIGHTED_NORMAL');bpy.ops.object.modifier_apply(modifier=mod.name)
    return o

def box(n,p,s,m=STONE,b=.02):
    bpy.ops.mesh.primitive_cube_add(size=1,location=p);o=bpy.context.object;o.dimensions=s
    return finish(o,n,m,b if min(s)>.18 else 0)

def cyl(n,p,r,d,m=DARK,verts=12):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts,radius=r,depth=d,location=p)
    return finish(bpy.context.object,n,m)

def rod(n,a,b,r=.035,m=DARK,verts=10):
    a,b=Vector(a),Vector(b);o=cyl(n,(a+b)/2,r,(b-a).length,m,verts)
    o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler();return o

def ring(n,p,r,t,m=DARK):
    bpy.ops.mesh.primitive_torus_add(major_segments=24,minor_segments=6,major_radius=r,minor_radius=t,location=p)
    return finish(bpy.context.object,n,m)

def sphere(n,p,s,m=LEAF,sub=1):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=sub,radius=1,location=p);o=bpy.context.object;o.scale=s
    return finish(o,n,m)

def mesh(n,verts,faces,m):
    me=bpy.data.meshes.new(n);me.from_pydata(verts,[],faces);me.update()
    o=bpy.data.objects.new(n,me);bpy.context.collection.objects.link(o);o.data.materials.append(m);return o

def text(body,p,size=.25,m=CREAM):
    bpy.ops.object.text_add(location=p);o=bpy.context.object;o.data.body=body;o.data.size=size
    o.data.align_x='CENTER';o.data.align_y='CENTER';o.data.extrude=.001;o.rotation_euler.x=math.pi/2
    o.data.materials.append(m);bpy.ops.object.convert(target='MESH');o.name='Sign '+body;return o

def window(x,y,z,w=1.3,h=1.75):
    box('Window reveal',(x,y,z),(w+.2,.10,h+.2),DARK,.008)
    box('Blue glazing',(x,y-.067,z),(w,.025,h),GLASS,.004)
    for dx in [-w/2,0,w/2]:box('Extruded window jamb',(x+dx,y-.10,z),(.06,.07,h+.12),CREAM,.005)
    for dz in [-h/2,h/2]:box('Window rail',(x,y-.10,z+dz),(w+.12,.08,.075),CREAM,.005)
    box('Projecting stone sill',(x,y-.16,z-h/2-.11),(w+.32,.34,.16),CREAM,.01)

def windows_all_sides(w,d,rows,cols=4):
    # Each facade is independently modeled then rigidly rotated into place.
    for side,(width,depth,angle) in enumerate([(w,d,0),(w,d,math.pi),(d,w,math.pi/2),(d,w,-math.pi/2)]):
        for z in rows:
            for i in range(cols):
                x=(i-(cols-1)/2)*(width-1.4)/cols
                before=set(bpy.context.scene.objects)
                window(x,-depth/2-.03,z,(width-1.4)/cols*.70,1.62)
                for o in set(bpy.context.scene.objects)-before:
                    px,py=o.location.x,o.location.y
                    o.location.x=px*math.cos(angle)-py*math.sin(angle)
                    o.location.y=px*math.sin(angle)+py*math.cos(angle)
                    o.rotation_euler.z+=angle

def vent(x,y,z):
    box('HVAC curb',(x,y,z+.12),(1.6,1.3,.24),DARK)
    box('HVAC enclosure',(x,y,z+.54),(1.4,1.1,.70),CREAM,.055)
    cyl('Cooling fan surround',(x,y,z+.91),.42,.07,DARK,20)
    for a in range(4):
        blade=box('Cooling fan blade',(x,y,z+.965),(.66,.12,.035),METAL,.01);blade.rotation_euler.z=a*math.pi/4
    for i in range(5):box('Intake louvre',(x-.5+i*.25,y-.565,z+.52),(.07,.05,.44),DARK,.005)

def parapet(w,d,z):
    box('Roof waterproof membrane',(0,0,z),(w,d,.14),DARK)
    for x in [-w/2,w/2]:box('Roof parapet',(x,0,z+.22),(.24,d+.24,.55),CREAM)
    for y in [-d/2,d/2]:box('Roof parapet',(0,y,z+.22),(w,.24,.55),CREAM)

def export(name,use,source='Original model for Low Altitude Squad V2',license='Project original'):
    objects=[o for o in bpy.context.scene.objects if o.type=='MESH']
    bpy.context.view_layer.update()
    bounds=[o.matrix_world@Vector(c) for o in objects for c in o.bound_box]
    minimum=[min(p[i] for p in bounds) for i in range(3)];maximum=[max(p[i] for p in bounds) for i in range(3)]
    # Center footprints at origin and place every asset on its ground plane.
    shift=Vector(((minimum[0]+maximum[0])/2,(minimum[1]+maximum[1])/2,minimum[2]))
    for o in objects:o.location-=shift
    bpy.context.scene.unit_settings.system='METRIC'
    bpy.context.scene.unit_settings.scale_length=1
    bpy.ops.wm.save_as_mainfile(filepath=str(BLENDS/(name+'.blend')))
    # Preserve modeled components in .blend; export by material response class.
    batch_mats={}
    for o in objects:
        bpy.context.view_layer.objects.active=o
        bpy.ops.object.select_all(action='DESELECT');o.select_set(True)
        bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
        colors=o.data.color_attributes.get('Color') or o.data.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='CORNER')
        original=list(o.data.materials)
        for poly in o.data.polygons:
            m=original[poly.material_index] if original else STONE
            group=m.get('batch_group','matte')
            rgba=tuple(m.diffuse_color)
            for loop in poly.loop_indices:colors.data[loop].color=rgba
            if group not in batch_mats:
                bm=bpy.data.materials.new('Street batch '+group);bm.use_nodes=True;bm['batch_group']=group
                bm.node_tree.nodes.clear();s=bm.node_tree.nodes.new('ShaderNodeBsdfPrincipled');output=bm.node_tree.nodes.new('ShaderNodeOutputMaterial');bm.node_tree.links.new(s.outputs['BSDF'],output.inputs['Surface']);v=bm.node_tree.nodes.new('ShaderNodeVertexColor');v.layer_name='Color'
                bm.node_tree.links.new(v.outputs['Color'],s.inputs['Base Color'])
                s.inputs['Roughness'].default_value={'matte':.72,'metal':.34,'glass':.18,'clear':.15,'emit':.45}[group]
                s.inputs['Metallic'].default_value=.5 if group=='metal' else .12 if group=='glass' else 0
                if group=='clear':
                    bm.node_tree.links.new(v.outputs['Alpha'],s.inputs['Alpha']);bm.surface_render_method='DITHERED'
                if group=='emit':
                    bm.node_tree.links.new(v.outputs['Color'],s.inputs['Emission Color']);s.inputs['Emission Strength'].default_value=.7
                batch_mats[group]=bm
        for i,m in enumerate(original):o.data.materials[i]=batch_mats[m.get('batch_group','matte')]
    # One mesh with a maximum of 5 surface materials; prune unused duplicates.
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:o.select_set(True)
    bpy.context.view_layer.objects.active=objects[0];bpy.ops.object.join();joined=bpy.context.object;joined.name=name
    used=list(dict.fromkeys(joined.data.materials))
    face_mats=[used.index(joined.data.materials[p.material_index]) for p in joined.data.polygons]
    joined.data.materials.clear()
    for m in used:joined.data.materials.append(m)
    for p,i in zip(joined.data.polygons,face_mats):p.material_index=i
    bpy.context.view_layer.update()
    final_bounds=[joined.matrix_world@Vector(c) for c in joined.bound_box]
    final_lo=Vector([min(p[i] for p in final_bounds) for i in range(3)])
    final_hi=Vector([max(p[i] for p in final_bounds) for i in range(3)])
    joined.location-=Vector(((final_lo.x+final_hi.x)/2,(final_lo.y+final_hi.y)/2,final_lo.z))
    minimum=list(final_lo);maximum=list(final_hi)
    bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'.glb')),export_format='GLB',export_yup=True,export_apply=True,
        export_texcoords=True,export_normals=True,export_vertex_color='NAME',export_vertex_color_name='Color',export_attributes=False,export_materials='EXPORT')
    joined.data.calc_loop_triangles()
    record=dict(id=name,path='res://assets/v2/streets/'+name+'.glb',source_blend=str((BLENDS/(name+'.blend')).relative_to(ROOT)).replace('\\','/'),
        footprint=[round(maximum[0]-minimum[0],3),round(maximum[1]-minimum[1],3)],height=round(maximum[2]-minimum[2],3),
        front='+Z',ground_y=0.0,usage=use,triangles=len(joined.data.loop_triangles),surfaces=len(used),source=source,license=license,
        sha256=hashlib.sha256((OUT/(name+'.glb')).read_bytes()).hexdigest())
    META.append(record);print('STREET_EXPORTED',name,record['triangles'],record['surfaces'],flush=True)

def bench_geometry(x=0,y=0):
    for xx in [-.83,.83]:
        for yy in [-.22,.22]:box('Bench leg',(x+xx,y+yy,.26),(.08,.09,.52),DARK,.01)
        rod('Backrest support',(x+xx,y+.2,.2),(x+xx,y+.30,1.02),.036,DARK)
    for yy in [-.22,-.07,.08,.23]:box('Cedar seat slat',(x,y+yy,.53),(2.05,.13,.09),WOOD,.015)
    for zz in [.76,.96]:box('Cedar back slat',(x,y+.28,zz),(2.05,.075,.16),WOOD,.012)
    for xx in [-1,1]:rod('Arm rest',(x+xx,y-.24,.76),(x+xx,y+.27,.76),.03,DARK)

clear();bench_geometry();export('bench','Pedestrian paths, bus stops, waterfront seating')

clear()
box('Shelter paving pad',(0,0,.07),(5.6,2.45,.14),STONE,.06)
for x in [-2.45,2.45]:
    for y in [-.86,.85]:rod('Shelter structural column',(x,y,.12),(x,y,2.65),.07,DARK)
box('Floating folded metal canopy',(0,0,2.69),(5.6,2.6,.19),TEAL,.07)
box('Canopy fascia',(0,-1.24,2.60),(5.45,.10,.22),CREAM)
box('Translucent shelter rear glass',(0,.84,1.42),(4.75,.026,2.22),CLEAR,0)
box('Translucent side glass',(-2.45,0,1.42),(.026,1.66,2.22),CLEAR,0)
for x in [-1.2,0,1.2]:rod('Rear glass mullion',(x,.88,.28),(x,.88,2.53),.026,METAL)
bench_geometry(-.65,.30)
box('Route information case',(1.63,.78,1.59),(.97,.16,1.45),DARK,.025)
box('Route map background',(1.63,.681,1.59),(.86,.022,1.30),CREAM,.003)
text('BAY  /  02',(1.62,.654,2.02),.12,DARK)
for i in range(5):
    cyl_ob=cyl('Map stop dot',(1.36,.648,1.75-i*.19),.028,.013,TEAL,10);cyl_ob.rotation_euler.x=math.pi/2
    box('Route line',(1.36,.646,1.35),(.015,.016,.78),TEAL,0)
    box('Timetable print',(1.64,.646,1.75-i*.19),(.32,.017,.022),DARK,0)
text('HARBOR LINE',(0,-1.306,2.63),.15,DARK)
export('bus_stop','Sidewalk transit hub; face +Z toward road')

clear()
cyl('Lamp anchor plate',(0,0,.07),.24,.14,DARK,16)
cyl('Tapered base sleeve',(0,0,.43),.12,.75,DARK,12)
rod('Streetlight shaft',(0,0,.45),(0,0,5.4),.068,DARK)
rod('Light outreach',(0,0,5.35),(0,-1.18,5.58),.06,DARK)
box('LED luminaire',(0,-1.2,5.54),(.42,1.1,.15),DARK,.045)
box('Diffuser',(0,-1.22,5.45),(.31,.9,.04),LIGHT,.02)
box('Wayfinding pole banner',(.24,0,3.88),(.50,.07,1.0),TEAL,.03)
text('01',(.24,-.044,3.94),.24,CREAM)
export('street_lamp','Along sidewalks; outreach projects +Z')

clear()
cyl('Signal pedestal',(0,0,.08),.23,.16,DARK)
rod('Signal pole',(0,0,.1),(0,0,3.0),.075,DARK)
box('Signal housing',(0,-.07,2.72),(.43,.27,1.2),DARK,.06)
for i,m in enumerate([RED,AMBER,GREEN]):
    lens=cyl('Traffic lens',(0,-.22,3.06-i*.34),.135,.038,m,16);lens.rotation_euler.x=math.pi/2
    box('Signal rain visor',(0,-.31,3.20-i*.34),(.34,.28,.045),DARK,.01)
box('Pedestrian button',(.10,-.11,1.13),(.13,.12,.24),AMBER,.02)
export('traffic_light','Road intersections; face +Z')

clear()
rod('Direction sign pole',(0,0,0),(0,0,2.8),.06,DARK)
for z,label in [(2.5,'HARBOR  >'),(2.04,'<  GARDEN'),(1.58,'LAB  01  >')]:
    box('Directional enamel sign',(0,0,z),(2.05,.10,.37),TEAL,.03)
    text(label,(0,-.061,z),.19,CREAM)
export('wayfinding_sign','Landmark navigation at junctions')

clear()
for x,m in [(-.43,TEAL),(.43,AMBER)]:
    box('Bin body',(x,0,.51),(.68,.62,.96),m,.07)
    box('Opening bezel',(x,-.325,.77),(.43,.07,.23),DARK,.025)
    box('Bin lid',(x,0,1.02),(.73,.68,.12),DARK,.04)
    text('RECYCLE' if x<0 else 'WASTE',(x,-.354,.4),.10,CREAM)
    for xx in [-.23,.23]:box('Bin foot',(x+xx,0,.06),(.09,.44,.12),DARK,.01)
export('recycling_bins','Civic detail near kiosks and walkways')

clear()
box('Planter base',(0,0,.34),(2.9,1.5,.68),STONE,.075)
box('Planter rim',(0,0,.70),(3.02,1.62,.14),CREAM,.025)
box('Recessed soil',(0,0,.78),(2.72,1.31,.03),SOIL,.01)
for x in [-1.0,-.4,.3,1.0]:
    sphere('Clipped evergreen',(x,0,1.04),(.45,.46,.36),LEAF,2)
for i in range(11):
    x=random.uniform(-1.25,1.25);y=random.uniform(-.45,.45)
    rod('Flower stem',(x,y,.81),(x,y,1.25),.014,LEAF)
    sphere('Small amber flower',(x,y,1.26),(.07,.07,.07),AMBER,1)
export('planter','Sidewalk separation and gardens')

clear()
box('Kiosk base',(0,0,.10),(3.8,3.3,.2),CREAM,.04)
box('Service cabin',(0,0,1.32),(3.35,2.7,2.45),TEAL,.07)
box('Cedar facade',(0,-1.38,1.02),(3.2,.13,1.62),WOOD,.02)
for x in [-1.43,-1.19,-.95,-.71,-.47,-.23,.01,.25,.49,.73,.97,1.21,1.45]:box('Timber vertical joint',(x,-1.458,.98),(.023,.02,1.48),SOIL,0)
box('Service window recess',(0,-1.41,1.90),(2.75,.11,1.03),DARK,.015)
box('Counter slab',(0,-1.77,1.43),(3.12,.91,.14),CREAM,.025)
box('Coffee machine',(-.68,-1.67,1.77),(.54,.40,.56),METAL,.045)
for x in [-.82,-.55]:cyl('Cup',(x,-1.91,1.55),.055,.13,CREAM)
box('Menu chalkboard',(.81,-1.58,1.91),(.57,.08,.75),DARK,.02)
text('COFFEE',(.8,-1.631,2.14),.084,CREAM)
for z in [1.98,1.85,1.72]:box('Menu lettering',(.8,-1.631,z),(.35,.015,.02),CREAM,0)
box('Wide kiosk roof',(0,0,2.64),(3.8,3.1,.20),CREAM,.07)
awning=box('Canvas awning',(0,-1.76,2.42),(3.55,1.15,.11),TEAL,.02);awning.rotation_euler.x=.14
for x in [-1.3,-.65,0,.65,1.3]:
    stripe=box('Awning stripe',(x,-1.77,2.48),(.22,1.12,.016),CREAM,.002);stripe.rotation_euler.x=.14
box('Roof sign backing',(0,0,2.99),(2.40,.18,.52),DARK,.035)
text('BAY COFFEE',(0,-.111,3.0),.25,CREAM)
export('coffee_kiosk','Public plazas, cafe waterfront; front service counter faces +Z')

clear()
for x in [-1.2,-.4,.4,1.2]:
    rod('Rack side',(x,-.22,.04),(x,-.22,.79),.032,METAL)
    rod('Rack top',(x,-.22,.79),(x,.22,.79),.032,METAL)
    rod('Rack side',(x,.22,.79),(x,.22,.04),.032,METAL)
# A parked cycle: wheels in YZ plane; actual triangulated frame and spokes.
for y in [-.62,.62]:
    o=ring('Bicycle tire',(.38,y,.42),.38,.035,DARK);o.rotation_euler.y=math.pi/2
    o=ring('Wheel rim',(.38,y,.42),.325,.018,METAL);o.rotation_euler.y=math.pi/2
    for a in range(0,360,60):
        r=math.radians(a);rod('Wheel spoke',(.38,y,.42),(.38,y+math.cos(r)*.32,.42+math.sin(r)*.32),.009,METAL,6)
for a,b in [((.38,-.62,.42),(.38,-.08,.46)),((.38,-.08,.46),(.38,-.28,1.02)),((.38,-.28,1.02),(.38,-.62,.42)),((.38,-.28,1.02),(.38,.43,1.02)),((.38,.43,1.02),(.38,-.08,.46)),((.38,.43,1.02),(.38,.62,.42))]:rod('Bicycle frame tube',a,b,.028,TEAL)
rod('Seatpost',(.38,-.28,1.02),(.38,-.31,1.17),.022,METAL)
box('Saddle',(.38,-.31,1.19),(.19,.29,.07),DARK,.03)
rod('Handlebar stem',(.38,.43,1.02),(.38,.40,1.24),.025,METAL)
rod('Handlebar',(.12,.40,1.24),(.64,.40,1.24),.025,DARK)
export('bicycle_rack','Bike parking with modeled bicycle beside shops')

clear()
for x in [-1.3,0,1.3]:
    cyl('Bollard base',(x,0,.055),.19,.11,DARK,12)
    cyl('Steel bollard',(x,0,.48),.085,.90,DARK,12)
    cyl('Reflective collar',(x,0,.74),.089,.12,CREAM,12)
    sphere('Rounded cap',(x,0,.93),(.087,.087,.065),TEAL,2)
export('bollards','Pedestrian curb boundaries; decorative, not flight blockers')

clear()
for x in [-2,-1,0,1,2]:
    box('Railing foot',(x,0,.04),(.19,.23,.08),DARK,.01)
    rod('Railing post',(x,0,.06),(x,0,1.10),.035,DARK)
for z in [.21,.66,1.08]:rod('Horizontal rail',(-2.0,0,z),(2.0,0,z),.032,DARK)
rod('Cedar handrail',(-2.04,0,1.16),(2.04,0,1.16),.06,WOOD)
export('promenade_railing','Waterfront edge; 4m modules')

clear()
box('Service cabinet concrete pad',(0,0,.08),(1.4,.76,.16),STONE,.025)
box('Weatherproof cabinet',(0,0,.78),(1.17,.56,1.40),TEAL,.055)
for x in [-.28,.28]:
    box('Access panel',(x,-.295,.78),(.51,.04,1.24),CREAM,.015)
    rod('Door latch',(x+.15,-.329,.72),(x+.15,-.329,.89),.015,DARK)
    for z in [.28,.34,.40,.46]:box('Vent slit',(x,-.322,z),(.35,.009,.014),DARK,0)
text('GRID  07',(0,-.329,1.19),.13,DARK)
export('utility_cabinet','Utility detail beside warehouses and labs')

clear()
box('Outdoor table top',(0,0,.81),(1.6,.83,.10),WOOD,.035)
for x in [-.63,.63]:
    rod('Table leg',(x,-.3,0),(x,.12,.77),.035,DARK)
    rod('Table leg',(x,.3,0),(x,-.12,.77),.035,DARK)
for y in [-.8,.8]:
    box('Cafe chair seat',(0,y,.45),(.5,.47,.07),TEAL,.025)
    for x in [-.2,.2]:
        for yy in [-.19,.19]:rod('Chair leg',(x,y+yy,.02),(x,y+yy,.43),.021,DARK)
        rod('Chair back',(x,y+.22,.45),(x,y+.22,.93),.023,DARK)
    box('Chair backrest',(0,y+.22,.82),(.5,.04,.21),TEAL,.015)
cyl('Coffee cup',(.4,0,.95),.07,.17,CREAM)
cyl('Table planter',(-.3,0,.96),.10,.2,BRICK)
sphere('Table succulent',(-.3,0,1.09),(.13,.12,.13),LEAF)
export('cafe_table','Outdoor cafe seating for plaza life')

clear()
cyl('Tree grate surround',(0,0,.04),1.02,.08,DARK,24)
cyl('Tree soil',(0,0,.09),.82,.035,SOIL,24)
for a in range(0,360,60):
    r=math.radians(a);rod('Radial tree grate',(math.cos(r)*.24,math.sin(r)*.24,.115),(math.cos(r)*.88,math.sin(r)*.88,.115),.017,METAL,6)
rod('Tree trunk',(0,0,.1),(.08,0,3.25),.14,SOIL,8)
for i in range(7):
    a=i*2.4;r=random.uniform(.25,.95);z=random.uniform(3.0,4.1);x=math.cos(a)*r;y=math.sin(a)*r
    rod('Tree branch',(.05,0,2.0),(x,y,z),.045,SOIL,6)
    sphere('Leaf crown',(x,y,z),(.94,.9,.82),LEAF if i%2 else LEAF2,2)
export('street_tree','Shaded walkways; opaque stylized crown avoids alpha sorting')
shutil.copy2(BLENDS/'street_tree.blend',HERE/'tree_variant_reference.blend')

for name,scales in [('street_tree_round',(1.14,1.08,1.06)),('street_tree_slender',(.80,.83,1.23))]:
    clear()
    with bpy.data.libraries.load(str(HERE/'tree_variant_reference.blend'),link=False) as (data_from,data_to):
        data_to.objects=data_from.objects
    for ob in data_to.objects:
        if ob:bpy.context.collection.objects.link(ob)
    for o in bpy.context.scene.objects:
        if o.type!='MESH':continue
        o.location.x*=scales[0];o.location.y*=scales[1];o.location.z*=scales[2]
        o.scale.x*=scales[0];o.scale.y*=scales[1];o.scale.z*=scales[2]
        if 'Leaf crown' in o.name and 'slender' in name:
            o.data.materials.clear();o.data.materials.append(LEAF)
    export(name,'Street tree silhouette variant for mixed avenues')

clear()
box('Herringbone planter base',(0,0,.19),(3.8,2.1,.38),STONE,.07)
box('Pergola wood decking',(0,0,.40),(3.6,1.93,.08),WOOD,.015)
for x in [-1.65,1.65]:
    for y in [-.8,.8]:box('Pergola post',(x,y,1.72),(.13,.13,2.55),WOOD,.015)
for y in [-.82,.82]:box('Pergola crossbeam',(0,y,3.0),(3.9,.16,.19),DARK,.018)
for x in [-1.7,-1.15,-.6,-.05,.5,1.05,1.6]:box('Pergola canopy slat',(x,0,3.15),(.15,2.35,.16),WOOD,.018)
bench_geometry(0,.15)
export('pergola','Garden rest point with real open slatted canopy')

# Architectural kit. Clear facade hierarchy and real rooftop services.
clear()
box('Office foundation',(0,0,.12),(10.4,8.4,.24),STONE,.06)
box('Office main mass',(0,0,3.72),(9.8,7.8,7.2),CREAM,.05)
box('Ground floor dark base',(0,0,1.29),(10,8,2.30),DARK,.015)
windows_all_sides(10,8,[1.45,4.15,6.47],4)
for z in [2.7,5.25,7.50]:box('Continuous floor cornice',(0,0,z),(10.30,8.30,.19),STONE,.025)
for x in [-4.8,4.8]:
    for y in [-3.85,3.85]:box('Corner sandstone pier',(x,y,4),(.30,.30,6.9),STONE,.015)
box('Entrance vestibule',(0,-4.23,1.35),(2.05,.66,2.58),GLASS,.01)
for x in [-1,0,1]:box('Entrance jamb',(x,-4.6,1.35),(.075,.07,2.58),METAL,.006)
box('Entrance canopy',(0,-4.63,2.83),(3.55,1.45,.18),TEAL,.04)
text('BAY  INNOVATION',(0,-4.15,3.22),.24,DARK)
parapet(9.9,7.9,7.62)
for x in [-2.5,0]:vent(x,1.6,7.71)
for x in [2,3.25]:
    o=box('Solar panel',(x,-.8,7.94),(1.0,2.2,.09),GLASS,.015);o.rotation_euler.x=.14
    for yy in [-1.45,-.8,-.15]:box('Solar cell seam',(x,yy,8.0),(1.0,.025,.015),METAL,.002)
export('office_pavilion','Tech park cornerstone; complete four-sided facade and rooftop equipment')

clear()
box('Cafe foundation',(0,0,.13),(8.7,6.5,.26),STONE,.055)
box('Cafe masonry',(0,0,2.23),(8.2,6.0,4.20),BRICK,.03)
windows_all_sides(8.2,6.0,[2.3],3)
box('Front storefront glazing',(0,-3.08,1.6),(6.65,.07,2.60),GLASS,.008)
for x in [-3.3,-1.65,0,1.65,3.3]:box('Storefront mullion',(x,-3.15,1.61),(.085,.09,2.72),DARK,.008)
box('Cafe sign frieze',(0,-3.14,3.50),(7.3,.14,.59),CREAM,.012)
text('WATERLINE  CAFE',(0,-3.223,3.51),.35,DARK)
for x in [-3.4,-1.7,0,1.7,3.4]:
    o=box('Cafe striped awning',(x,-3.55,2.83),(1.64,1.02,.10),TEAL if x else CREAM,.015);o.rotation_euler.x=.18
box('Cafe roof slab',(0,0,4.42),(8.65,6.4,.20),CREAM,.03)
parapet(8.3,6.05,4.57)
vent(2,1.3,4.63)
for x in [-2.4,-.7]:box('Roof skylight',(x,0,4.77),(1.25,2.5,.23),GLASS,.04)
export('waterfront_cafe','Low-rise waterside commercial landmark; outdoor seating fits in front')

clear()
box('Warehouse foundation',(0,0,.15),(12.6,9.1,.30),STONE,.045)
box('Warehouse shell',(0,0,2.65),(12,8.5,5.0),CREAM,.045)
for x in [-5.5,-4.5,-3.5,-2.5,-1.5,-.5,.5,1.5,2.5,3.5,4.5,5.5]:
    for y in [-4.27,4.27]:box('Corrugated wall rib',(x,y,2.77),(.07,.07,4.6),STONE,.007)
for x in [-3,3]:
    box('Roller door surround',(x,-4.34,1.95),(3.7,.18,3.72),DARK,.02)
    box('Roller shutter',(x,-4.45,1.89),(3.25,.08,3.42),TEAL,.01)
    for z in [.35,.70,1.05,1.4,1.75,2.1,2.45,2.8,3.15,3.5]:box('Roller shutter seam',(x,-4.50,z),(3.22,.02,.034),DARK,.003)
    for xx in [x-1.93,x+1.93]:cyl('Loading dock bumper',(xx,-4.7,.56),.095,1.12,AMBER)
box('Warehouse loading canopy',(0,-4.80,4.10),(12.6,1.95,.19),TEAL,.03)
for x in [-5.5,0,5.5]:rod('Canopy diagonal brace',(x,-4.3,3.45),(x,-5.5,3.95),.045,DARK)
text('HARBOR  LOGISTICS',(0,-4.381,4.68),.32,DARK)
mesh('Warehouse pitched roof',[(-6.3,-4.65,5.23),(6.3,-4.65,5.23),(-6.3,0,6.20),(6.3,0,6.20),(-6.3,4.65,5.23),(6.3,4.65,5.23)],[(0,1,3,2),(2,3,5,4)],TEAL)
for x in [-5,-3,-1,1,3,5]:
    rod('Roof standing seam',(x,-4.64,5.26),(x,0,6.23),.016,METAL)
    rod('Roof standing seam',(x,0,6.23),(x,4.64,5.26),.016,METAL)
for x in [-3,3]:
    cyl('Roof ventilator',(x,0,6.43),.28,.45,METAL,16)
    cyl('Ventilator rain hood',(x,0,6.69),.41,.12,DARK,16)
export('harbor_warehouse','Industrial harbor anchor with loading doors, ribs, seams, and ventilation')

clear()
box('Apartment podium',(0,0,.14),(9.8,7.7,.28),STONE,.05)
box('Apartment brick core',(0,0,5.39),(9.2,7.1,10.5),BRICK,.04)
windows_all_sides(9.2,7.1,[1.6,4.0,6.5,9.0],4)
for z in [2.8,5.3,7.8,10.65]:box('Apartment slab trim',(0,0,z),(9.5,7.4,.16),CREAM,.02)
for z in [3.3,5.8,8.3]:
    for x in [-2.4,2.4]:
        box('Projecting balcony slab',(x,-4.1,z),(2.05,1.15,.14),CREAM,.018)
        for xx in [x-.96,x-.48,x,x+.48,x+.96]:rod('Balcony baluster',(xx,-4.59,z+.08),(xx,-4.59,z+1.0),.025,DARK)
        rod('Balcony handrail',(x-1,-4.59,z+1.0),(x+1,-4.59,z+1.0),.032,DARK)
        for xx in [x-1,x+1]:rod('Balcony return',(xx,-4.59,z+1.0),(xx,-3.59,z+1.0),.029,DARK)
box('Residential entrance canopy',(0,-4.0,2.65),(2.5,1.6,.18),TEAL,.025)
text('CANAL  HOUSE',(0,-3.64,3.07),.22,CREAM)
parapet(9.3,7.2,10.80)
vent(-2.1,.8,10.91);vent(.1,.8,10.91)
box('Roof access room',(2.6,1.3,11.75),(2.3,2.8,1.8),CREAM,.025)
box('Roof access room top',(2.6,1.3,12.70),(2.55,3.0,.15),DARK,.02)
export('canal_apartments','Urban residential anchor with actual balconies on the road facade')

(OUT/'manifest.json').write_text(json.dumps(dict(schema=1,units='meters',axis='Godot Y-up',front='+Z',models=META),indent=2,ensure_ascii=False),encoding='utf-8')
print('STREET_KIT_COMPLETE',len(META),flush=True)
