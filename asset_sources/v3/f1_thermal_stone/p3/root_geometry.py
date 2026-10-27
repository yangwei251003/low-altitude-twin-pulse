"""Pure authored root geometry. No Blender imports; shared by source and static probe."""
import math

MAIN_CONTROLS=[(-1.12,.0095,.77),(-1.31,.36,.56),(-1.29,.92,.13),(-1.12,1.58,-.43),
    (-.77,1.84,-.62),(-.30,1.82,-.66),(.23,1.73,-.68),(.77,1.59,-.61),
    (1.19,1.35,-.37),(1.32,.94,.15),(1.30,.46,.59),(1.09,.0095,.80)]
FRONT_CONTROLS=[(1.28,.57,.66),(.95,.47,.79),(.48,.35,.85),(-.06,.24,.88),
    (-.59,.17,.88),(-1.06,.0095,.86)]

def add(a,b):return tuple(x+y for x,y in zip(a,b))
def sub(a,b):return tuple(x-y for x,y in zip(a,b))
def mul(a,s):return tuple(x*s for x in a)
def dot(a,b):return sum(x*y for x,y in zip(a,b))
def cross(a,b):return (a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])
def length(a):return math.sqrt(dot(a,a))
def unit(a):
    d=length(a)
    if d<1e-12:raise ValueError("Zero root frame vector")
    return mul(a,1/d)
def smooth(a,b,x):
    t=min(1,max(0,(x-a)/(b-a)));return t*t*(3-2*t)
def rotate_axis(v,axis,angle):
    c=math.cos(angle);s=math.sin(angle)
    return add(add(mul(v,c),mul(cross(axis,v),s)),mul(axis,dot(axis,v)*(1-c)))
def transport(v,old_t,new_t):
    axis=cross(old_t,new_t);s=length(axis);c=max(-1,min(1,dot(old_t,new_t)))
    if s<1e-12:
        if c<0:raise ValueError("Reversed root tangent")
        return v
    return rotate_axis(v,mul(axis,1/s),math.atan2(s,c))
def catmull(controls,steps=9):
    out=[]
    for i in range(len(controls)-1):
        a,b,c,d=controls[max(0,i-1)],controls[i],controls[i+1],controls[min(len(controls)-1,i+2)]
        for j in range(steps):
            t=j/steps
            out.append(tuple(.5*(2*b[k]+(-a[k]+c[k])*t+(2*a[k]-5*b[k]+4*c[k]-d[k])*t*t+
                                  (-a[k]+3*b[k]-3*c[k]+d[k])*t*t*t) for k in range(3)))
    return out+[tuple(controls[-1])]

def make_root(controls,radius,sides,offset=(0,0,0)):
    points=catmull(controls);tangents=[unit(sub(points[min(i+1,len(points)-1)],points[max(i-1,0)])) for i in range(len(points))]
    up=(0,1,0);normal=unit(sub(up,mul(tangents[0],dot(up,tangents[0]))))
    vertices=[];frames=[];distance=[0.0]
    for i,(p,tangent) in enumerate(zip(points,tangents)):
        if i:
            distance.append(distance[-1]+length(sub(p,points[i-1])))
            normal=unit(transport(normal,tangents[i-1],tangent))
        # Minimal rotation above the foot; only the last low contact portion
        # gradually aligns the ellipse's thin axis with world up.
        foot=1-smooth(.10,.34,p[1])
        target=sub(up,mul(tangent,dot(up,tangent)))
        if foot>0 and length(target)>.15:
            target=unit(target)
            if dot(target,normal)<0:target=mul(target,-1)
            angle=math.atan2(dot(tangent,cross(normal,target)),max(-1,min(1,dot(normal,target))))
            normal=unit(rotate_axis(normal,tangent,angle*foot*.25))
        normal=unit(sub(normal,mul(tangent,dot(normal,tangent))))
        side=unit(cross(tangent,normal));t=i/(len(points)-1)
        taper=.28+.72*smooth(0,.17,min(t,1-t))
        r=radius*taper*(1+.11*math.sin(t*math.tau*1.7)+.055*math.sin(t*17+1))
        aspect=(.86+.055*math.sin(t*8.2))*(1-foot)+.30*foot
        frames.append({'center':p,'tangent':tangent,'normal':normal,'side':side,'radius':r,'aspect':aspect,'foot':foot})
        for j in range(sides):
            a=j*math.tau/sides
            ridge=1+.075*math.cos(3*a+.26*math.sin(t*4))+.025*math.sin(5*a+t*3)
            v=add(add(p,mul(side,math.cos(a)*r*ridge)),mul(normal,math.sin(a)*r*aspect*ridge))
            vertices.append(add(v,offset))
    faces=[]
    for i in range(len(points)-1):
        for j in range(sides):faces.append((i*sides+j,i*sides+(j+1)%sides,(i+1)*sides+(j+1)%sides,(i+1)*sides+j))
    faces.extend([tuple(reversed(range(sides))),tuple((len(points)-1)*sides+j for j in range(sides))])
    turns=[math.degrees(math.atan2(length(cross(frames[i-1]['normal'],f['normal'])),dot(frames[i-1]['normal'],f['normal']))) for i,f in enumerate(frames) if i]
    report={'min':[min(v[k] for v in vertices) for k in range(3)],'max':[max(v[k] for v in vertices) for k in range(3)],
        'max_adjacent_frame_angle_deg':max(turns),'min_upper_aspect':min(f['aspect'] for f in frames if f['center'][1]>=.34),
        'max_upper_aspect':max(f['aspect'] for f in frames if f['center'][1]>=.34),'frames':frames}
    return vertices,faces,distance,report

def authored_roots():
    return [('RootBindings_Main',MAIN_CONTROLS,.156,22,(0,0,0)),
            ('RootBindings_Front',FRONT_CONTROLS,.132,18,(0,0,-.05))]
