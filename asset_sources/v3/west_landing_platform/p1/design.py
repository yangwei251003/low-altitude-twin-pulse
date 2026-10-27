"""Pure metre-scale layout. No Blender dependency or execution side effects."""
import math
BOUNDS={'PlatformAssembly':([-4,4.6,-2],[4,5,2]),'LegAssembly':([-3.6,0,1],[-3.1,4.6,1.5])}
ORIGIN=[-6,0,-4]
PITCH=.16
RIB_LENGTH=.062
RIB_WIDTH=.014
RIB_HEIGHT=.0015
DECK_Y=5-RIB_HEIGHT

def geometry_specs():
    boxes=[];bolts=[];plates={}
    def box(n,a,b,body='PlatformAssembly',finish='Teal',bevel=.004):
        boxes.append({'name':n,'min':a,'max':b,'body_group':body,'finish':finish,'bevel':bevel})
    def hex(n,c,axis,body='PlatformAssembly'):
        bolts.append({'name':n,'centre':c,'axis':axis,'body_group':body})
    # Recessed closed core: no exterior coplanar surface behind the fascia.
    box('PlatformClosedStructuralCore',[-3.86,4.61,-1.86],[3.86,4.948,1.86],finish='Seal')
    for sign in (-1,1):
        z0,z1=(-1.975,-1.86) if sign<0 else (1.86,1.975)
        box('LongFascia_'+str(sign),[-3.975,4.6,z0],[3.975,4.99,z1],bevel=.009)
        for j,x in enumerate((-2,0,2)):
            a,b=(-2,-1.972) if sign<0 else (1.972,2)
            box(f'LongSeamCover_{sign}_{j}',[x-.05,4.625,a],[x+.05,4.98,b],bevel=.003)
            for k,dx in enumerate((-.11,.11)):
                hex(f'FasciaHex_{sign}_{j}_{k}',[x+dx,4.81,sign*1.982],[0,0,sign])
    for sign in (-1,1):
        x0,x1=(-3.975,-3.86) if sign<0 else (3.86,3.975)
        box('EndFascia_'+str(sign),[x0,4.6,-1.86],[x1,4.99,1.86],bevel=.009)
        for z in (-1.72,1.72):hex(f'EndHex_{sign}_{z}',[sign*3.982,4.81,z],[sign,0,0])
    # Real flush top perimeter, contained entirely in the 0.4 m original slab.
    for sign in (-1,1):
        a,b=(-2,-1.86) if sign<0 else (1.86,2)
        box('LongTopCap_'+str(sign),[-4,4.99,a],[4,5,b],bevel=.003)
        a,b=(-4,-3.86) if sign<0 else (3.86,4)
        box('EndTopCap_'+str(sign),[a,4.99,-1.86],[b,5,1.86],bevel=.003)
    # Four broad panels along the 8 m axis, two across; narrow real backed joints.
    for ix in range(4):
        x0=-3.85+ix*1.925+.005;x1=-3.85+(ix+1)*1.925-.005
        for iz,(z0,z1) in enumerate([(-1.85,-.005),(.005,1.85)]):
            name=f'DeckPanel_{ix}_{iz}'
            box(name,[x0,4.948,z0],[x1,DECK_Y,z1],finish='Steel',bevel=.003)
            plates[name]=(x0,x1,z0,z1)
    # Original 0.5m column. Collars equal the original footprint, not imagegen flares.
    leg='LegAssembly'
    box('LegClosedCore',[-3.58,.11,1.02],[-3.12,4.48,1.48],leg,'Seal',.005)
    box('LegFlushFoot',[-3.6,0,1],[-3.1,.11,1.5],leg,bevel=.006)
    box('LegFlushHead',[-3.6,4.48,1],[-3.1,4.6,1.5],leg,bevel=.006)
    for x0,x1 in [(-3.6,-3.57),(-3.13,-3.1)]:
        for z0,z1 in [(1,1.03),(1.47,1.5)]:
            box(f'LegCornerSpine_{x0}_{z0}',[x0,.11,z0],[x1,4.48,z1],leg,bevel=.003)
    for k,(y0,y1) in enumerate([(.14,1.55),(1.57,3),(3.02,4.45)]):
        for side in ('South','North','West','East'):
            axis=2 if side in ('South','North') else 0
            sign=1 if side in ('South','East') else -1
            long=0 if axis==2 else 2
            u0,u1=(-3.565,-3.135) if axis==2 else (1.035,1.465)
            lo=[0,y0,0];hi=[0,y1,0];lo[long]=u0;hi[long]=u1
            if axis==2:lo[axis],hi[axis]=(1.475,1.492) if sign>0 else (1.008,1.025)
            else:lo[axis],hi[axis]=(-3.125,-3.108) if sign>0 else (-3.592,-3.575)
            box(f'LegServicePanel_{side}_{k}',lo,hi,leg,bevel=.003)
            for j,(u,y) in enumerate([(u0+.06,y0+.07),(u1-.06,y0+.07),(u0+.06,y1-.07),(u1-.06,y1-.07)]):
                c=[0,y,0];c[long]=u
                c[axis]=(1.49 if sign>0 else 1.01) if axis==2 else (-3.11 if sign>0 else -3.59)
                normal=[0,0,0];normal[axis]=sign
                hex(f'LegPanelHex_{side}_{k}_{j}',c,normal,leg)
    return boxes,bolts,plates

def ring(length,width,chamfer):
    a,b=length/2,width/2;c=chamfer
    return [(-a+c,-b),(a-c,-b),(a,-b+c),(a,b-c),(a-c,b),(-a+c,b),(-a,b-c),(-a,-b+c)]

def tread_layout():
    plates=geometry_specs()[2];rows=[]
    for plate,(x0,x1,z0,z1) in plates.items():
        for ix in range(-25,25):
            for iz in range(-13,13):
                for arm in (-1,1):
                    x=(ix+.5)*PITCH+arm*.028;z=(iz+.5)*PITCH+arm*.016;angle=arm*math.pi/4
                    ca,sa=math.cos(angle),math.sin(angle)
                    outline=[(x+a*ca-b*sa,z+a*sa+b*ca) for a,b in ring(RIB_LENGTH,RIB_WIDTH,.002)]
                    if all(x0+.012<=a<=x1-.012 and z0+.012<=b<=z1-.012 for a,b in outline):
                        rows.append({'plate':plate,'centre':[x,z],'angle':angle})
    return rows

def static_contract():
    boxes,bolts,plates=geometry_specs()
    for row in boxes:
        lo,hi=BOUNDS[row['body_group']]
        assert all(lo[i]<=row['min'][i]<row['max'][i]<=hi[i]+1e-9 for i in range(3)),row
    for row in bolts:
        lo,hi=BOUNDS[row['body_group']]
        for i in range(3):
            extent=.009 if row['axis'][i] else .035
            assert lo[i]-1e-9<=row['centre'][i]-extent and row['centre'][i]+extent<=hi[i]+1e-9,row
    ribs=tread_layout()
    return {'boxes':len(boxes),'bolts':len(bolts),'runtime_triangles_expected':len(boxes)*44+len(bolts)*20,
        'rib_count':len(ribs),'high_only_triangles_expected':len(ribs)*44,'pitch_m':PITCH,'rib_height_m':RIB_HEIGHT,
        'rib_bar_m':[RIB_LENGTH,RIB_WIDTH],'plate_count':len(plates),'body_boxes':BOUNDS,'source_local_origin_world':ORIGIN,
        'scope':'Pure source parameter check; Blender evaluated geometry and art not yet verified'}

if __name__=='__main__':
    import json
    print(json.dumps(static_contract(),indent=2))
