"""UV-authored raster PBR. PNG rows and tangent +Y match increasing UV v.
Derived from the project's verified underdeck atlas method; no Blender calls here.
BaseColor values are authored sRGB once. All other maps are linear data.
"""
from pathlib import Path
import struct,zlib
import numpy as np

SIZE=2048
REGIONS={
 'deck':(0,0,.5,.5), 'tank':(0,.5,.5,1),
 'paint_post':(.5,0,.75,.5), 'paint_beam':(.75,0,1,.5),
 'steel':(.5,.5,.75,.75), 'yellow':(.75,.5,1,.75),
 'liner':(.5,.75,.75,1), 'rubber':(.75,.75,1,1),
}
METRES={'deck':(7,5.6),'tank':(1.84,3),'paint_post':(.6,5.6),'paint_beam':(6,.4),
        'steel':(1,1),'yellow':(1,1),'liner':(1.6,3),'rubber':(1,1)}

def png(path,arr):
 a=np.clip(arr*255+.5,0,255).astype(np.uint8)
 if a.ndim==2:a=np.repeat(a[:,:,None],3,axis=2)
 h,w,_=a.shape
 def chunk(t,d):return struct.pack('>I',len(d))+t+d+struct.pack('>I',zlib.crc32(t+d)&0xffffffff)
 raw=b''.join(b'\0'+row.tobytes() for row in a[::-1])
 Path(path).write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(raw,6))+chunk(b'IEND',b''))

def mapped_uv(kind,u,v):
 a,b,c,d=REGIONS[kind];pad=6/SIZE
 return (a+pad+(c-a-2*pad)*max(0,min(1,float(u))), b+pad+(d-b-2*pad)*max(0,min(1,float(v))))

def tile(kind,w,h):
 v,u=np.mgrid[0:1:complex(h),0:1:complex(w)]
 rng=np.random.default_rng(217+list(REGIONS).index(kind))
 def field(n):
  a=rng.random((n+1,n+1));xx=u*n;yy=v*n;ix=np.minimum(xx.astype(int),n-1);iy=np.minimum(yy.astype(int),n-1)
  x=xx-ix;y=yy-iy;x=x*x*(3-2*x);y=y*y*(3-2*y)
  return (a[iy,ix]*(1-x)+a[iy,ix+1]*x)*(1-y)+(a[iy+1,ix]*(1-x)+a[iy+1,ix+1]*x)*y-.5
 broad=field(5);medium=field(31);grain=rng.random((h,w))-.5
 edge=np.minimum.reduce((u,1-u,v,1-v))
 broken=np.clip((.009+medium*.016-edge)/.009,0,1)
 rough=np.full((h,w),.65);metal=np.zeros((h,w));height=np.zeros((h,w))
 def mix(color,weight,base):
  weight=np.clip(weight,0,1)
  return base*(1-weight[:,:,None])+np.array(color)*weight[:,:,None]
 def trails(rows):
  result=np.zeros_like(u)
  for x,top,length,width,strength in rows:
   t=(top-v)/length;d=np.clip(t,0,1);mid=x+.009*np.sin(d*8)*d
   a=np.exp(-((u-mid)/(width*(1-.72*d)+.0001))**2)
   a*=np.clip(d/.08,0,1)*(1-d)**1.5*((t>=0)&(t<=1))*(.75+.5*medium)
   result+=a*strength
  return np.clip(result,0,.72)
 if kind=='deck':
  x=-12+u*7;z=-10+v*5.6
  c=np.ones((h,w,3))*[.54,.55,.515]
  c*=1+.035*broad[:,:,None]+.016*medium[:,:,None]+.005*grain[:,:,None]
  joint=np.zeros_like(u)
  for line in [-10.05,-7.6]:joint=np.maximum(joint,np.exp(-((x-line)/.010)**2))
  for line in [-8.6,-6.05]:joint=np.maximum(joint,np.exp(-((z-line)/.010)**2))
  c=mix([.19,.225,.22],joint*.66,c);height-=joint*.0025
  # Quiet work area on the wide right side; no repeated full-surface cloud pattern.
  work=(x>-7.75)&(x<-5.28)&(z>-9.6)&(z<-6.05)
  c=mix([.575,.585,.55],work*.20,c)
  # Real narrow drainage-cover graphic, not a hole or traversable cavity.
  drain=(abs(z+9.70)<.065)&(x>-11.65)&(x<-5.35)
  slots=drain&(((x+11.65)%.10)<.035)&(abs(z+9.70)<.043)
  c=mix([.31,.35,.34],drain*.9,c);c=mix([.105,.15,.15],slots*.8,c)
  height-=slots*.0015;metal=drain*.45
  warning=(((abs(z+9.9)<.05)&(((x>-11.75)&(x<-10.5))|((x>-6.3)&(x<-5.2))))|
           ((abs(x+5.1)<.05)&(((z>-9.6)&(z<-8.7))|((z>-6.8)&(z<-5.95))))|
           ((abs(z+4.50)<.05)&(((x>-9.1)&(x<-8.55))|((x>-6.7)&(x<-6.2)))))
  c=mix([.72,.52,.19],warning*(.78+.15*medium),c)
  # Only two localized marks beside actual panel intersections/drain, no cracks everywhere.
  grime=np.exp(-((x+10.05)/.17)**2-((z+8.6)/.40)**2)*.16
  grime+=np.exp(-((x+6.0)/.40)**2-((z+9.70)/.13)**2)*.14
  c=mix([.30,.31,.255],grime,c);rough=.77+.08*grime+.02*medium
  height+=medium*.0005
 elif kind in ('paint_post','paint_beam','tank'):
  c=np.ones((h,w,3))*[.20,.325,.34];c*=1+.035*broad[:,:,None]
  chip=broken*np.clip(.30+medium*2.0,0,.85)
  rows=[]
  if kind=='paint_post':rows=[(.20,.91,.10,.055,.65),(.80,.91,.065,.035,.42)]
  elif kind=='tank':rows=[(.12,.94,.21,.018,.55),(.88,.94,.13,.024,.62)]
  runoff=trails(rows)
  base_dirt=np.clip((.10+.025*broad-v)/.10,0,1)*(.22 if kind=='paint_post' else .07)
  c=mix([.47,.49,.45],chip*.75,c)
  c=mix([.33,.175,.085],runoff+chip*.22,c)
  c=mix([.19,.235,.205],base_dirt,c)
  rough=.62+.15*runoff+.10*base_dirt;metal=np.full((h,w),.08)
  height=chip*.0003+runoff*.00012
 elif kind=='steel':
  c=np.ones((h,w,3))*[.45,.475,.46];c*=1+.04*broad[:,:,None]+.006*grain[:,:,None]
  rough=.38+.09*broken+.015*medium;metal=np.full((h,w),.72);height=medium*.00012
 elif kind=='yellow':
  c=np.ones((h,w,3))*[.74,.53,.19]
  stripe=((u*3.1+v*.6)%1)<.24;c[stripe]=[.15,.185,.18]
  c=mix([.41,.43,.39],broken*.50,c);rough=.72+.06*broken;metal=np.full((h,w),.08);height=broken*.0002
 elif kind=='liner':
  c=np.ones((h,w,3))*[.83,.835,.78];c*=1+.006*broad[:,:,None]
  rough=np.full((h,w),.40);height=np.zeros((h,w))
 else:
  c=np.ones((h,w,3))*[.12,.15,.15];rough=np.full((h,w),.80)
 dx,dv=METRES[kind]
 gy,gx=np.gradient(height,dv/max(h-1,1),dx/max(w-1,1))
 normal=np.dstack((-gx,-gy,np.ones_like(height)));normal/=np.linalg.norm(normal,axis=2)[:,:,None]
 return {'BaseColor':c,'Roughness':rough,'Metallic':metal,'Normal':normal*.5+.5}

def create_textures(directory):
 directory=Path(directory);directory.mkdir(parents=True,exist_ok=True)
 atlas={k:np.zeros((SIZE,SIZE,3),dtype=np.float32) for k in ['BaseColor','Roughness','Metallic','Normal']}
 for kind,(a,b,c,d) in REGIONS.items():
  x0,y0,x1,y1=[int(q*SIZE) for q in (a,b,c,d)]
  for role,arr in tile(kind,x1-x0,y1-y0).items():
   if arr.ndim==2:arr=np.repeat(arr[:,:,None],3,axis=2)
   atlas[role][y0:y1,x0:x1]=arr
 paths={}
 for role,arr in atlas.items():
  path=directory/('CG_SurfaceAtlas_'+role+'.png');png(path,arr);paths[role]=path
 return paths
