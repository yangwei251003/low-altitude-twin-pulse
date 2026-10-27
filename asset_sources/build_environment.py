"""Harbor Garden production kit v2. Original editable geometry from approved sheets."""
from pathlib import Path
_lib=Path(__file__).with_name('build_models.py')
exec(compile(_lib.read_text(encoding='utf-8').split("for kind in ['player','patrol','charger','repair']:")[0],str(_lib),'exec'))

SAND=mat('Limestone face','BDB8A5',0,.91)
CREAM=mat('Cut stone cornice','DDD6BF',0,.72)
MOSS=mat('Aged joints','777F6C',0,.94)
GLASS=mat('Reflective blue glass','3F7780',.50,.18)
LEAVES=[mat('Olive foliage '+str(i),c,0,.87) for i,c in enumerate(['455B31','536938','667C43','7B8950','8D985C'])]
ROOF=mat('Patinated roof','345F67',.35,.48)
TERRACOTTA=mat('Terracotta','B37E56',0,.85)

def mesh_obj(name,verts,faces,material):
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update()
    ob=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(ob);ob.data.materials.append(material)
    return ob

def rail(a,b,z=1.0):
    a=Vector(a);b=Vector(b);length=(b-a).length
    for i in range(max(1,int(length/.9))+1):
        p=a+(b-a)*i/max(1,int(length/.9))
        rod('Baluster',(p.x,p.y,p.z),(p.x,p.y,p.z+z),.028,NAVY)
    for dz in [.22,z]:rod('Handrail',a+Vector((0,0,dz)),b+Vector((0,0,dz)),.035,NAVY)

def stone_wall(center,size):
    box('Stone structure',center,size,SAND,.035)
    x,y,z=center;w,d,h=size
    for level in range(1,max(1,int(h/.55))):
        zz=z-h/2+level*.55
        box('Bed joint',(x,y-d/2-.006,zz),(w,.012,.016),EDGE,0)
        box('Bed joint back',(x,y+d/2+.006,zz),(w,.012,.016),EDGE,0)
    box('Coping',(x,y,z+h/2+.08),(w+.22,d+.20,.16),CREAM,.025)

def arch(name,center,radius,width,thickness,material=CREAM):
    # In the X-Z plane, extruded in Y. Each voussoir is genuine wedge geometry.
    cx,cy,cz=center
    for i in range(18):
        a=math.pi*i/18+.008;b=math.pi*(i+1)/18-.008
        verts=[]
        for yy in [-width/2,width/2]:
            for r,t in [(radius,a),(radius,b),(radius+thickness,b),(radius+thickness,a)]:
                verts.append((cx+math.cos(t)*r,cy+yy,cz+math.sin(t)*r))
        mesh_obj(name,verts,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],material)

def window(x,y,z,w=1.0,h=1.5):
    box('Window recess',(x,y,z),(w+.20,.13,h+.20),NAVY,.025)
    box('Glass pane',(x,y-.076,z),(w,.028,h),GLASS,.01)
    box('Window mullion',(x,y-.10,z),(.048,.06,h+.1),CREAM,.008)
    box('Window transom',(x,y-.10,z),(w+.1,.06,.05),CREAM,.008)
    box('Sill',(x,y-.17,z-h/2-.10),(w+.35,.38,.16),CREAM,.025)

def roof_garden(w,d,z):
    box('Roof garden soil',(0,0,z),(w,d,.10),TRUNK,.01)
    for x in [-w/2,w/2]:box('Parapet',(x,0,z+.2),(.22,d+.25,.48),CREAM,.025)
    for y in [-d/2,d/2]:box('Parapet',(0,y,z+.2),(w,.22,.48),CREAM,.025)
    for i in range(22):
        x=random.uniform(-w*.4,w*.4);y=random.uniform(-d*.4,d*.4)
        sphere('Roof shrub',(x,y,z+.35),(.3,.3,random.uniform(.25,.45)),random.choice(LEAVES),1)

# Bridge spans the canal along X. Play deck remains at world altitude zero.
clear()
for x in [-4.5,4.5]:stone_wall((x,0,-1.65),(1.0,5.5,3.1))
for y in [-2.6,2.6]:
    arch('Limestone voussoir',(0,y,-3.0),3.65,.45,.48)
    # Deck hides upper side of arch, only underside reveals the opening.
    stone_wall((0,y,-.30),(9.6,.5,.45))
box('Paved deck',(0,0,-.08),(10,5.5,.18),STONE,.025)
for x in range(-4,5):box('Bridge paving joint',(x,0,.015),(.02,5.2,.006),EDGE,0)
for y in [-2.5,2.5]:rail((-4.7,y,.06),(4.7,y,.06),.75)
export('bridge')

clear()
stone_wall((0,0,2.2),(7.0,5.2,4.4))
for x in [-2.5,0,2.5]:window(x,-2.66,2.45,1.20,1.9)
for x in [-3.35,3.35]:box('Corner pilaster',(x,-2.72,2.15),(.38,.38,4.25),CREAM,.025)
box('Roof ledge',(0,0,4.52),(7.55,5.7,.28),CREAM,.04)
box('Metal roof',(0,0,4.72),(7.2,5.4,.15),ROOF,.04)
for x in [-3.4,3.4]:rail((x,-2.45,4.78),(x,2.45,4.78),.7)
for y in [-2.4,2.4]:rail((-3.4,y,4.78),(3.4,y,4.78),.7)
for x in [-1.7,1.7]:
    box('Roof machinery',(x,.8,5.0),(1.5,1.2,.6),IVORY,.055)
    for i in range(5):box('Vent grille',(x-.5+i*.25,.8,5.32),(.06,.85,.025),NAVY,.008)
sign=label('HARBOR LAB',(0,-2.76,4.0),.29,NAVY);sign.rotation_euler.x=math.pi/2
export('lab')

clear()
stone_wall((0,0,2.8),(4.0,4.0,5.6))
for y in [-2.10,2.10]:
    box('Tall sign panel',(0,y,3.5),(1.65,.08,3.2),NAVY,.025)
    for i in range(3):
        o=box('Leaf emblem',(-.30+i*.24,y-.06,3.8-i*.3),(.19,.03,.60),IVORY,.025);o.rotation_euler.y=-.5
box('Tower crown',(0,0,5.82),(4.45,4.45,.38),CREAM,.05)
box('Roof inset',(0,0,6.05),(3.8,3.8,.13),ROOF,.02)
for x in [-1.85,1.85]:rail((x,-1.85,6.15),(x,1.85,6.15),.65)
for y in [-1.85,1.85]:rail((-1.85,y,6.15),(1.85,y,6.15),.65)
box('Roof skylight',(0,0,6.3),(2,2,.4),GLASS,.04)
export('tower')

clear()
box('Greenhouse foundation',(0,0,.15),(6.5,9.5,.3),CREAM,.05)
for x in [-3,3]:box('Greenhouse plinth',(x,0,.55),(.26,9.0,.9),SAND,.025)
for y in [-4.4,-2.2,0,2.2,4.4]:
    for x in [-3,3]:rod('Steel post',(x,y,.35),(x,y,2.2),.055,TEAL)
    for i in range(18):
        a=math.pi*i/18;b=math.pi*(i+1)/18
        rod('Curved frame',(math.cos(a)*3,y,2.2+math.sin(a)*2),(math.cos(b)*3,y,2.2+math.sin(b)*2),.055,NAVY)
for i in range(14):
    a=math.pi*i/14;b=math.pi*(i+1)/14
    verts=[(math.cos(t)*2.96,y,2.2+math.sin(t)*1.97) for y,t in [(-4.4,a),(4.4,a),(4.4,b),(-4.4,b)]]
    mesh_obj('Glazed curved roof',verts,[(0,1,2,3)],GLASS)
for x in [-2,0,2]:rod('Roof longitudinal brace',(x,-4.5,2.2+math.sqrt(1-(x/3)**2)*2),(x,4.5,2.2+math.sqrt(1-(x/3)**2)*2),.045,CREAM)
for y in [-3,0,3]:
    box('Planting bed',(0,y,.5),(4.6,1.25,.6),TERRACOTTA,.02)
    for x in [-1.6,-.8,0,.8,1.6]:sphere('Cultivated plant',(x,y,1.05),(.43,.4,.48),random.choice(LEAVES),1)
export('greenhouse')

clear()
cyl('Lighthouse footing',(0,0,.2),2.0,.4,SAND,48)
bpy.ops.mesh.primitive_cone_add(vertices=48,radius1=1.4,radius2=.85,depth=7.0,location=(0,0,3.8));finish(bpy.context.object,'Tapered lighthouse',IVORY,.025)
for z in [1.1,2.3,3.5,4.7,6.0]:ring('Stone course',(0,0,z),1.4-(z-.3)*.55/7,.025,CREAM)
cyl('Gallery',(0,0,7.35),1.65,.28,NAVY,48)
for i in range(20):
    a=i*math.tau/20;rod('Gallery post',(math.cos(a)*1.5,math.sin(a)*1.5,7.4),(math.cos(a)*1.5,math.sin(a)*1.5,8.1),.035,NAVY)
ring('Gallery rail',(0,0,8.08),1.5,.035,NAVY)
cyl('Lantern glass',(0,0,8.3),.75,1.4,GLASS,16)
for i in range(8):
    a=i*math.tau/8;rod('Lantern frame',(math.cos(a)*.77,math.sin(a)*.77,7.65),(math.cos(a)*.77,math.sin(a)*.77,9),.04,NAVY)
cyl('Lantern cap',(0,0,9.0),1.0,.2,NAVY,32)
bpy.ops.mesh.primitive_cone_add(vertices=32,radius1=1.0,radius2=.12,depth=.65,location=(0,0,9.4));finish(bpy.context.object,'Lantern roof',ROOF)
rod('Finial',(0,0,9.6),(0,0,10.15),.06,NAVY)
for z in [2.4,4.8]:window(0,-1.16,z,.32,.74)
export('lighthouse')

clear()
for x in [-5,5]:
    for y in [-2.0,2.0]:
        box('Crane foot',(x,y,.15),(1.5,1.2,.3),NAVY,.06)
        rod('Gantry leg',(x,y,.3),(x*.7,y,9.0),.20,NAVY)
        rod('Diagonal brace',(x,y,1),(x*.7,-y,7.8),.07,METAL)
        box('Amber foot guard',(x,y,.6),(1.1,.7,.5),AMBER,.05)
for y in [-2,2]:
    box('Gantry beam',(0,y,9.0),(13,.38,.6),NAVY,.045)
    for x in range(-5,6):rod('Beam truss',(x,y,8.7),(x+1,y,9.7),.06,METAL)
    box('Beam top',(0,y,9.72),(13,.18,.18),NAVY,.02)
for x in [-5,0,5]:rod('Cross member',(x,-2,9.2),(x,2,9.2),.16,NAVY)
box('Hoist cart',(1,0,8.95),(1.8,4,.65),AMBER,.06)
for y in [-.4,.4]:rod('Suspension cable',(1,y,8.6),(1,y,3.6),.025,BLACK)
box('Cargo spreader',(1,0,3.6),(3,1.8,.2),AMBER,.025)
box('Hanging cargo',(1,0,2.45),(2.6,1.6,2),IVORY,.06)
for x in [.1,1.9]:box('Cargo strap',(x,0,2.5),(.13,1.65,2.1),NAVY,.015)
export('crane')

clear()
cyl('Fountain base',(0,0,.10),2.8,.20,CREAM,64)
cyl('Fountain bowl',(0,0,.32),2.55,.35,SAND,64)
cyl('Water mirror',(0,0,.53),2.3,.035,TEAL,64)
ring('Fountain rim',(0,0,.54),2.55,.16,CREAM)
cyl('Fountain pedestal',(0,0,.9),.38,.8,CREAM)
cyl('Upper bowl',(0,0,1.3),.95,.15,CREAM)
ring('Upper lip',(0,0,1.42),.85,.08,CREAM)
sphere('Fountain finial',(0,0,1.70),(.20,.20,.32),METAL)
export('fountain')

clear()
for i in range(9):box('Stone step',(0,-2.7+i*.6,.08+i*.14),(5,.63,.16+i*.28),CREAM,.02)
for x in [-2.55,2.55]:rail((x,-2.95,.2),(x,2.5,1.5),.7)
export('stairs')

clear();rail((-2.0,0,0),(2.0,0,0),.8);export('railing')

for tree_type in ['cypress','broadleaf']:
    clear();random.seed(73 if tree_type=='cypress' else 83)
    height=5.8 if tree_type=='cypress' else 4.7
    rod('Natural trunk',(0,0,0),(.1,0,height*.8),.12,TRUNK)
    for i in range(110 if tree_type=='cypress' else 150):
        if tree_type=='cypress':
            z=random.uniform(1.1,height);r=.7*(1-(z/height)**3);a=random.random()*math.tau
            x=math.cos(a)*r*random.random();y=math.sin(a)*r*random.random();sz=random.uniform(.22,.39)
            sphere('Leaf cluster',(x,y,z),(sz,sz,sz*1.6),random.choice(LEAVES),1)
        else:
            a=random.random()*math.tau;r=math.sqrt(random.random())*1.65
            x=math.cos(a)*r;y=math.sin(a)*r;z=3.25+random.uniform(-.4,1.4)*(1-r/2.6);sz=random.uniform(.25,.50)
            sphere('Leaf cluster',(x,y,z),(sz*1.2,sz,sz*.85),random.choice(LEAVES),1)
            if i%15==0:rod('Branch',(.05,0,1.6),(x,y,z),.055,TRUNK)
    export(tree_type)

clear()
box('Container',(0,0,1.1),(2.4,5.8,2.2),NAVY,.05)
for x in [-1.22,1.22]:
    for y in range(18):box('Corrugation',(x,-2.7+y*.32,1.1),(.09,.11,2.1),TEAL,.012)
for x in [-.6,.6]:
    box('Container door',(x,-2.94,1.1),(1.1,.10,2),TEAL,.025)
    rod('Locking bar',(x,-3.02,.22),(x,-3.02,1.96),.034,METAL)
for x in [-1.18,1.18]:
    for y in [-2.9,2.9]:box('Corner casting',(x,y,2.18),(.22,.23,.20),AMBER,.02)
export('container')

clear()
for x in [-1.4,1.4]:box('Pier pile',(x,0,-1.0),(.28,6.0,2.0),WOOD,.03)
box('Pier deck',(0,0,.0),(3.2,7,.28),NAVY,.035)
for i in range(24):box('Weathered deck plank',(0,-3.36+i*.29,.19),(3.1,.26,.10),WOOD,.013)
for x in [-1.45,1.45]:
    for y in [-3.1,0,3.1]:cyl('Mooring post',(x,y,0),.14,1.8,WOOD)
export('pier')

clear()
sphere('Yacht hull',(0,0,-.1),(1.2,3.7,.6),IVORY,3)
box('Deck',(0,0,.28),(1.8,5.5,.15),WOOD,.2)
box('Cabin',(0,-.7,.8),(1.3,2.0,.95),IVORY,.25)
box('Cabin glass',(0,-1.70,.9),(1.12,.03,.5),GLASS,.05)
rod('Mast',(0,.5,.4),(0,.5,7),.045,METAL)
mesh_obj('Folded sail',[(0,.5,6.6),(0,.5,1.6),(0,3.0,1.6)],[(0,1,2)],IVORY)
rod('Boom',(0,.5,1.6),(0,3.1,1.6),.04,NAVY)
export('yacht')
print('ENVIRONMENT_V2_COMPLETE',flush=True)
