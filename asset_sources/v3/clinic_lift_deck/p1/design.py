"""Pure metre-scale moving Deck only; no Blender import or launch."""
import math
ROOT_NAME='ClinicLiftDeck'
GROUP='DeckAssembly'
BOUNDS={GROUP:([-2,-.175,-2],[2,.175,2])}
ORIGIN={'type':'moving_body_centre','body':'moving_bodies.Deck','world_at_top_4':[0,3.825,-4],'world_at_top_5':[0,4.825,-4]}
PITCH=.16
RIB_LENGTH=.062
RIB_WIDTH=.014
RIB_HEIGHT=.0015
TOP_Y=.175
DECK_Y=TOP_Y-RIB_HEIGHT

def geometry_specs():
    boxes=[];bolts=[];plates={}
    def box(n,a,b,finish='Teal',bevel=.004):
        boxes.append({'name':n,'min':a,'max':b,'body_group':GROUP,'finish':finish,'bevel':bevel})
    def hex(n,c,axis):
        bolts.append({'name':n,'centre':c,'axis':axis,'body_group':GROUP})
    # Recessed core never duplicates a visible fascia/cap surface.
    box('DeckClosedCore',[-1.86,-.165,-1.86],[1.86,.123,1.86],finish='Seal')
    for sign in (-1,1):
        a,b=(-1.975,-1.86) if sign<0 else (1.86,1.975)
        box('LongFascia_'+str(sign),[-1.975,-.175,a],[1.975,.165,b],bevel=.007)
        box('EndFascia_'+str(sign),[a,-.175,-1.86],[b,.165,1.86],bevel=.007)
        a,b=(-2,-1.972) if sign<0 else (1.972,2)
        box('LongSeamCover_'+str(sign),[-.05,-.15,a],[.05,.15,b],bevel=.003)
        box('EndSeamCover_'+str(sign),[a,-.15,-.05],[b,.15,.05],bevel=.003)
        for j,d in enumerate((-.11,.11)):
            hex(f'LongSeamHex_{sign}_{j}',[d,.01,sign*1.982],[0,0,sign])
            hex(f'EndSeamHex_{sign}_{j}',[sign*1.982,.01,d],[sign,0,0])
        a,b=(-2,-1.86) if sign<0 else (1.86,2)
        box('LongTopCap_'+str(sign),[-2,.165,a],[2,TOP_Y,b],bevel=.003)
        box('EndTopCap_'+str(sign),[a,.165,-1.86],[b,TOP_Y,1.86],bevel=.003)
    for ix,(x0,x1) in enumerate([(-1.85,-.005),(.005,1.85)]):
        for iz,(z0,z1) in enumerate([(-1.85,-.005),(.005,1.85)]):
            name=f'DeckPanel_{ix}_{iz}'
            box(name,[x0,.123,z0],[x1,DECK_Y,z1],finish='Steel',bevel=.003)
            plates[name]=(x0,x1,z0,z1)
            for j,(x,z) in enumerate([(x0+.10,z0+.10),(x1-.10,z0+.10),(x0+.10,z1-.10),(x1-.10,z1-.10)]):
                # Head top shares max body Y.175; fastener is embedded in the plate, not outside the Box.
                hex(f'DeckFastener_{ix}_{iz}_{j}',[x,TOP_Y-.009,z],[0,1,0])
    return boxes,bolts,plates

def ring(length,width,chamfer):
    a,b=length/2,width/2;c=chamfer
    return [(-a+c,-b),(a-c,-b),(a,-b+c),(a,b-c),(a-c,b),(-a+c,b),(-a,b-c),(-a,-b+c)]

def tread_layout():
    boxes,bolts,plates=geometry_specs();rows=[]
    bolt_xz=[(b['centre'][0],b['centre'][2]) for b in bolts if b['axis']==[0,1,0]]
    for plate,(x0,x1,z0,z1) in plates.items():
        for ix in range(-13,13):
            for iz in range(-13,13):
                for arm in (-1,1):
                    x=(ix+.5)*PITCH+arm*.028;z=(iz+.5)*PITCH+arm*.016;angle=arm*math.pi/4
                    ca,sa=math.cos(angle),math.sin(angle)
                    outline=[(x+a*ca-b*sa,z+a*sa+b*ca) for a,b in ring(RIB_LENGTH,RIB_WIDTH,.002)]
                    if not all(x0+.012<=a<=x1-.012 and z0+.012<=b<=z1-.012 for a,b in outline):continue
                    if any(math.hypot(x-a,z-b)<.075 for a,b in bolt_xz):continue
                    rows.append({'plate':plate,'centre':[x,z],'angle':angle})
    return rows

def static_contract():
    boxes,bolts,plates=geometry_specs();lo,hi=BOUNDS[GROUP]
    for r in boxes:assert all(lo[i]<=r['min'][i]<r['max'][i]<=hi[i]+1e-9 for i in range(3)),r
    for r in bolts:
        for i in range(3):
            extent=.009 if r['axis'][i] else .035
            assert lo[i]-1e-9<=r['centre'][i]-extent and r['centre'][i]+extent<=hi[i]+1e-9,r
    ribs=tread_layout()
    return {'boxes':len(boxes),'bolts':len(bolts),'runtime_triangles_expected':len(boxes)*44+len(bolts)*20,
        'rib_count':len(ribs),'high_only_triangles_expected':len(ribs)*44,'pitch_m':PITCH,'rib_height_m':RIB_HEIGHT,
        'rib_bar_m':[RIB_LENGTH,RIB_WIDTH],'plate_count':len(plates),'body_boxes':BOUNDS,'source_origin':ORIGIN,
        'scope':'Static parameter evidence only; actual evaluated model and visuals not yet verified'}

