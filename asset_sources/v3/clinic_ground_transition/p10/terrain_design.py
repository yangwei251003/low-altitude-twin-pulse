"""Purposeful asymmetric P10 height field; no Blender dependency."""
import math

ROUTES=[
    [(-1.10,.49),(-1.22,1.04),(-1.52,1.62),(-1.43,2.10)],
    [(.40,.51),(.55,.91),(.90,1.22),(.74,1.72)],
    [(1.74,.51),(1.87,.99),(1.66,1.57),(1.94,2.14)],
]
BRANCHES=[
    [(-1.22,1.04),(-.96,1.38),(-.82,1.83)],
    [(.55,.91),(.28,1.18),(.06,1.50)],
    [(1.87,.99),(2.15,1.27),(2.38,1.75)],
]
def clamp(v,a=0,b=1):return max(a,min(b,v))
def smooth(v):v=clamp(v);return v*v*(3-2*v)
def route_frame(points,t):
    lengths=[math.dist(a,b) for a,b in zip(points,points[1:])];distance=t*sum(lengths)
    for a,b,length in zip(points,points[1:],lengths):
        if distance<=length+1e-10:
            q=clamp(distance/length);tangent=((b[0]-a[0])/length,(b[1]-a[1])/length)
            return (a[0]+q*(b[0]-a[0]),a[1]+q*(b[1]-a[1])),(-tangent[1],tangent[0])
        distance-=length
    return points[-1],(1,0)
def nearest(points,x,z):
    lengths=[math.dist(a,b) for a,b in zip(points,points[1:])];total=sum(lengths);walk=0;best=None
    for a,b,length in zip(points,points[1:],lengths):
        dx,dz=b[0]-a[0],b[1]-a[1];q=clamp(((x-a[0])*dx+(z-a[1])*dz)/(length*length))
        px,pz=a[0]+q*dx,a[1]+q*dz;d=math.hypot(x-px,z-pz);signed=(dx*(z-pz)-dz*(x-px))/length
        if best is None or d<best[0]:best=(d,signed,(walk+q*length)/total)
        walk+=length
    return best
def halfwidth(index,t):
    # Channel 1 opens into a broad left shoulder; channel 2 bends sharply;
    # channel 3 has a wider fine-sediment bed, not a copied pair of banks.
    return [.105+.035*t,.085+.035*math.sin(math.pi*t),.125+.030*t][index]
def field(x,z,front,outer):
    f,o=front(x),outer(x);s=clamp((z-f)/(o-f))
    edge=smooth((3-abs(x))/.16)*smooth((o-z)/.24)
    # Keep a real broken-concrete face exposed at the join; otherwise the new
    # broad shoulder would bury the existing fracture aggregate entirely.
    base=-.035*(1-s)
    cut=0;bank=0;wet=0;silt=0;deposit=0
    for index,points in enumerate(ROUTES):
        distance,signed,t=nearest(points,x,z);h=halfwidth(index,t)
        tail=smooth((1-t)/.16)
        bed=(1-smooth((distance-h*.38)/(h*.95)))*tail
        depth=[.055,.060,.045][index]*(.90+.10*math.sin(t*math.pi+index*.8))
        cut=max(cut,depth*bed)
        favored=1 if (index==0 or (index==1 and t<.64)) else -1
        side_gain=1 if signed*favored>0 else [.27,.42,.38][index]
        spread=[.30,.24,.31][index]*(.80+.20*math.sin(t*5.2+index)**2)
        shoulder=math.exp(-((distance-h*1.5)/spread)**2)*side_gain*tail
        shoulder*=smooth(distance/(h*1.2))
        bank=max(bank,shoulder*.009)
        # Broad continuous zones, deliberately unequal between routes.
        abundance=[.92,.86,.46][index]*(.72+.28*math.sin(t*4.4+index*.9)**2)
        deposit=max(deposit,shoulder*abundance)
        silt=max(silt,bed);wet=max(wet,bed*(.88-.30*t))
    for points in BRANCHES:
        distance,signed,t=nearest(points,x,z);h=.055+.020*t;tail=smooth((1-t)/.18)
        bed=(1-smooth((distance-h*.32)/(h*1.05)))*tail
        cut=max(cut,.026*bed);silt=max(silt,bed*.8);wet=max(wet,bed*.48)
    # Broken-concrete apron joins the broader shoulders, then fades into beds.
    apron=(1-smooth((z-f-.10)/.55))*(.58+.24*math.sin(x*1.7+.2)**2)
    deposit=max(deposit,apron)*(1-.94*silt)*edge
    return {'height':(base-cut+bank)*edge,'wet':wet*edge,'silt':silt*edge,'deposit':clamp(deposit),'base':base*edge}
