"""P8 source-only broad deposit sampling. Imported only by the Blender builder."""
import math, bisect
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

class SedimentField:
    def __init__(self, H, soil, low_positions):
        self.H=H;self.low_positions=low_positions;self.cell=.02
        xs=np.arange(-3+self.cell/2,3,self.cell);zs=np.arange(self.cell/2,2.4,self.cell)
        X,Z=np.meshgrid(xs,zs);front=np.array([H.front(float(x)) for x in xs])[None,:];outer=np.array([H.outer(float(x)) for x in xs])[None,:]
        density=np.zeros_like(X);bed=np.zeros_like(X,dtype=bool)
        for ri,(pts,_) in enumerate(H.ROUTES):
            lengths=[math.dist(a,b) for a,b in zip(pts,pts[1:])];total=sum(lengths);distance=np.full(X.shape,np.inf);along=np.zeros_like(X);walk=0
            for (a,b),length in zip(zip(pts,pts[1:]),lengths):
                q=np.clip(((X-a[0])*(b[0]-a[0])+(Z-a[1])*(b[1]-a[1]))/length**2,0,1)
                d=np.hypot(X-(a[0]+q*(b[0]-a[0])),Z-(a[1]+q*(b[1]-a[1])));better=d<distance
                distance=np.where(better,d,distance);along=np.where(better,(walk+q*length)/total,along);walk+=length
            main=ri in (0,2,4);width=(.105+.085*along) if main else (.065+.035*along)
            if ri==2:width*=.86
            spread=(.50+.20*np.sin(along*4.3+ri*.83)**2) if main else (.24+.10*np.sin(along*4.3+ri*.83)**2)
            # Merge support fields before sampling, so intersecting banks become
            # broad deposits instead of separate equally spaced strings.
            across=np.clip((distance-width)/spread,0,1)
            bank=(1-across)**.55*np.clip((distance-width*.8)/(.035+width*.2),0,1)
            bank*=np.clip(along/.03,0,1)*np.clip((1-along)/.05,0,1)
            bank*=distance<width+spread
            density=np.maximum(density,bank);bed|=distance<width*.8
        apron_depth=.45+.25*(.5+.5*np.sin(X*1.1+.4))
        apron=np.clip(1-(Z-front)/apron_depth,0,1)**.55
        density=np.maximum(density,apron)
        # Broad unequal clusters. This modulates grain probability, never color.
        density*=np.clip(.68+.18*np.sin(X*1.7+Z*3.8)+.14*np.sin(X*4.1-Z*2.3),.30,1)
        density*=np.clip((Z-front)/.055,0,1)*np.clip((outer-Z)/.12,0,1)
        density*=np.clip((3-np.abs(X))/.12,0,1)
        valid=(Z>front+.035)&(Z<outer-.055)&(~bed)
        density*=valid
        chosen=np.flatnonzero(density.ravel()>1e-5)
        self.coords=np.column_stack((X.ravel()[chosen],Z.ravel()[chosen]))
        self.weights=density.ravel()[chosen];self.cumulative=np.cumsum(self.weights).tolist()
        self.protected_bed=bed;self.support_area=float(np.count_nonzero(density>0)*self.cell**2)
        soil.data.calc_loop_triangles()
        self.bvh=BVHTree.FromPolygons([v.co for v in soil.data.vertices],[p.vertices for p in soil.data.loop_triangles],all_triangles=True)
        self.occupied={};self.spacing=.06;self.rows=[];self.rejected={'large_stone_overlap':0,'fine_center_spacing':0,'outside_soil':0,'bed_or_boundary':0}

    def ground(self,x,z):
        hit,normal,idx,distance=self.bvh.ray_cast(Vector((x,-z,.15)),Vector((0,0,-1)),.5)
        return None if hit is None else float(hit.z)

    def location(self,rng,dia,channel):
        for _ in range(120):
            i=bisect.bisect_left(self.cumulative,rng.random()*self.cumulative[-1]);x,z=self.coords[min(i,len(self.coords)-1)]
            x=float(x+rng.uniform(-.5,.5)*self.cell);z=float(z+rng.uniform(-.5,.5)*self.cell)
            if not(-2.95<x<2.95 and self.H.front(x)+.035<z<self.H.outer(x)-.055) or channel(x,z)[0]>.80:
                self.rejected['bed_or_boundary']+=1;continue
            if any(math.hypot(x-a,z-b)<r+dia*.15 for a,b,r in self.low_positions):
                self.rejected['large_stone_overlap']+=1;continue
            key=(math.floor(x/self.spacing),math.floor(z/self.spacing))
            neighbors=[p for a in range(key[0]-1,key[0]+2) for b in range(key[1]-1,key[1]+2) for p in self.occupied.get((a,b),[])]
            if any(math.hypot(x-a,z-b)<.27*(dia+d) for a,b,d in neighbors):
                self.rejected['fine_center_spacing']+=1;continue
            y=self.ground(x,z)
            if y is None:self.rejected['outside_soil']+=1;continue
            self.occupied.setdefault(key,[]).append((x,z,dia));return x,z,y
        return None

    def seat(self,vertices):
        # Seat on the actual triangulated soil, not its construction formula.
        deltas=[]
        for p in vertices:
            ground=self.ground(p[0],-p[1])
            if ground is not None:deltas.append(p[2]-ground)
        if not deltas:return None
        # Place the lower portion into soil. Translate a whole angular grain;
        # do not flatten its vertices or float it above the contact surface.
        shift=min(0,-.002-min(deltas))
        seated=[(x,y,z+shift) for x,y,z in vertices]
        minimum=min(deltas)+shift;maximum=max(deltas)+shift
        if not(minimum<=-.001 and maximum>=.002):return None
        return seated,minimum,maximum

    def report(self):
        return {'sampling_grid_m':self.cell,'support_area_m2':self.support_area,'actual_soil_BVH':True,'main_side_reach_m':[.50,.70],'branch_side_reach_m':[.24,.34],'fracture_apron_reach_m':[.45,.70],'rejections':self.rejected,'note':'Support area is not projected exposed coverage; actual mesh coverage is measured after construction.'}
