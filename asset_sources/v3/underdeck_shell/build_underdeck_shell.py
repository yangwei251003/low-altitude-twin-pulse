"""I-B warehouse body. Exact layout faces + separate shallow architecture.
Godot metres are the authoring contract; Blender coordinates are (x,-z,y).
Only this asset's source/runtime directories are written. No engine import.
"""
from pathlib import Path
import bpy,bmesh,numpy as np,math,json,hashlib,struct,zlib,time,os
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[3];SRC=Path(__file__).resolve().parent
OUT=ROOT/'assets/v3/underdeck_shell';EV=SRC/'evidence';TEX=SRC/'textures'
for d in (SRC,OUT,EV,TEX):d.mkdir(parents=True,exist_ok=True)
(SRC/'.gdignore').write_text('',encoding='utf-8')
started=time.time();print('SHELL_START',os.getpid(),bpy.app.version_string,flush=True)
L=json.loads((ROOT/'data/v3/terrain/i1_underdeck_layout.json').read_text(encoding='utf-8'))
origin=np.array(L['origin'],dtype=np.float32)
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
bp=lambda p:Vector((float(p[0]),-float(p[2]),float(p[1])))
gp=lambda p:np.array([float(p[0]),float(p[2]),float(-p[1])])
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
scene=bpy.context.scene;scene.unit_settings.system='METRIC'
coll=bpy.data.collections.new('Editable_UnderdeckShell');scene.collection.children.link(coll)
parts=[];groups={};checks=[];skipped=[]
def check(name,ok,detail=None):checks.append({'name':name,'passed':bool(ok),'detail':detail})
def png(path,arr):
    a=np.clip(arr*255+.5,0,255).astype(np.uint8)
    if a.ndim==2:a=np.repeat(a[:,:,None],3,axis=2)
    h,w,_=a.shape
    def ch(t,d):return struct.pack('>I',len(d))+t+d+struct.pack('>I',zlib.crc32(t+d)&0xffffffff)
    raw=b''.join(b'\0'+row.tobytes()for row in a[::-1])
    path.write_bytes(b'\x89PNG\r\n\x1a\n'+ch(b'IHDR',struct.pack('>IIBBBBB',w,h,8,2,0,0,0))+ch(b'IDAT',zlib.compress(raw,6))+ch(b'IEND',b''))

# One shared 2k atlas, three original orientation/material slots. No duplicated
# 2k textures for the three bindings. All values are authored sRGB once.
regions={'concrete':(0,.5,.5,1),'floor':(0,0,.5,.5),'paint':(.5,.5,.75,1),
         'steel':(.75,.75,1,1),'dark':(.75,.5,1,.75),'yellow':(.5,0,.75,.5),
         'roof':(.75,0,1,.5)}
N=2048;atlas={k:np.zeros((N,N,3)if k=='BaseColor'else(N,N),dtype=np.float32)for k in ['BaseColor','Roughness','Metallic','Height']}
def tile(kind,w,h):
    v,u=np.mgrid[0:1:complex(h),0:1:complex(w)];rng=np.random.default_rng(180+list(regions).index(kind))
    def field(n):
        a=rng.random((n+1,n+1));xx=u*n;yy=v*n;ix=np.minimum(xx.astype(int),n-1);iy=np.minimum(yy.astype(int),n-1)
        x=xx-ix;y=yy-iy;x=x*x*(3-2*x);y=y*y*(3-2*y)
        return (a[iy,ix]*(1-x)+a[iy,ix+1]*x)*(1-y)+(a[iy+1,ix]*(1-x)+a[iy+1,ix+1]*x)*y-.5
    broad=field(6);medium=field(35);fine=rng.random((h,w))-.5
    edge=np.minimum.reduce((u,1-u,v,1-v));wear=np.clip((.016+medium*.025-edge)/.012,0,1)
    runoff=np.zeros_like(u)
    for x,top,length,width in [( .13,.94,.36,.012),(.87,.93,.21,.008),(.46,.48,.24,.006)]:
        t=(top-v)/length;d=np.clip(t,0,1);centre=x+.006*np.sin(7*d)*d
        runoff+=np.exp(-((u-centre)/(width*(1-.78*d)))**2)*np.clip(d/.06,0,1)*(1-d)**1.6*((t>=0)&(t<=1))*(.8+.4*medium)
    damp=np.clip((.20+.05*broad+.035*medium-v)/.20,0,1)
    if kind=='concrete':
        c=np.ones((h,w,3))*[.65,.63,.58];c*=1+.065*broad[:,:,None]+.045*medium[:,:,None]+.008*fine[:,:,None]
        stain=np.clip(damp*.48,0,.55);c=c*(1-stain[:,:,None])+np.array([.25,.285,.255])*stain[:,:,None]
        rust=np.clip(runoff*.90,0,.82);c=c*(1-rust[:,:,None])+np.array([.37,.20,.085])*rust[:,:,None]
        salt=damp*np.clip(medium*2.1+.12,0,.65);c=c*(1-salt[:,:,None]*.40)+np.array([.66,.66,.59])*salt[:,:,None]*.40
        # Actual large panel seams, not dense repeated micro-crack camouflage.
        joint=np.exp(-((v-.46)/.0028)**2)*.30
        c*=1-joint[:,:,None];rough=.83+.07*damp+.02*medium;metal=np.zeros_like(u);height=.018*medium+.004*fine-.06*joint
    elif kind in ('floor','roof'):
        base=[.44,.46,.435]if kind=='floor'else[.58,.585,.55]
        c=np.ones((h,w,3))*base;c*=1+.045*broad[:,:,None]+.025*medium[:,:,None]
        dirt=(wear*.05 if kind=='floor'else np.zeros_like(u))+np.clip((broad-.14)*.18,0,.07);c*=1-dirt[:,:,None]
        line=np.exp(-((u-.5)/.003)**2)*.17 if kind=='roof'else np.zeros_like(u)
        c*=1-line[:,:,None];rough=.82+.08*dirt;metal=np.zeros_like(u);height=.004*medium-(.012*wear if kind=='floor'else 0)-.008*line
    elif kind=='paint':
        c=np.ones((h,w,3))*[.18,.30,.32];c*=1+.05*broad[:,:,None]
        chip=wear*np.clip(.36+medium*2.2,0,1);oxid=wear*.18+runoff*.85
        c=c*(1-chip[:,:,None]*.65)+np.array([.46,.46,.40])*chip[:,:,None]*.65
        c=c*(1-oxid[:,:,None])+np.array([.34,.17,.075])*oxid[:,:,None]
        rough=.64+.13*oxid;metal=np.ones_like(u)*.08;height=chip*.06+oxid*.025
    elif kind=='steel':
        c=np.ones((h,w,3))*[.42,.445,.435];c*=1+.06*broad[:,:,None]+.008*fine[:,:,None]
        rough=.37+wear*.14;metal=np.ones_like(u)*.68;height=medium*.006
    elif kind=='dark':
        c=np.ones((h,w,3))*[.12,.155,.16];c*=1+.07*broad[:,:,None]
        rough=np.ones_like(u)*.72;metal=np.ones_like(u)*.24;height=medium*.008
    else:
        stripes=((u*3.5+v*.6)%1)<.28;c=np.ones((h,w,3))*[.69,.48,.15];c[stripes]=[.12,.155,.16]
        worn=wear*.35+np.clip((.15-v)/.15,0,1)*np.clip(medium+.25,0,.6)
        c=c*(1-worn[:,:,None])+np.array([.37,.37,.31])*worn[:,:,None]
        rough=.76+.10*worn;metal=np.ones_like(u)*.07;height=worn*.03
    return {'BaseColor':c,'Roughness':np.broadcast_to(rough,(h,w)),'Metallic':metal,'Height':height}
for kind,(a,b,c,d)in regions.items():
    x0,y0,x1,y1=[int(q*N)for q in(a,b,c,d)];maps=tile(kind,x1-x0,y1-y0)
    for role,arr in maps.items():atlas[role][y0:y1,x0:x1]=arr
height=atlas.pop('Height');gy,gx=np.gradient(height);normal=np.dstack((-gx*10,-gy*10,np.ones_like(height)));normal/=np.linalg.norm(normal,axis=2)[:,:,None];atlas['Normal']=normal*.5+.5
imgs={}
for role,arr in atlas.items():
    path=TEX/('UDS_SharedAtlas_'+role+'.png');png(path,arr);im=bpy.data.images.load(str(path));im.filepath='//textures/'+path.name
    im.colorspace_settings.name='sRGB'if role=='BaseColor'else'Non-Color';imgs[role]=im
del atlas,height,normal
materials=[]
for name in ['UDS_WallSurface','UDS_UpperSurface','UDS_UndersideSurface']:
    m=bpy.data.materials.new(name);m.use_nodes=True;ns=m.node_tree.nodes;lk=m.node_tree.links
    bs=next((n for n in ns if n.type=='BSDF_PRINCIPLED'),None)or ns.new('ShaderNodeBsdfPrincipled')
    op=next((n for n in ns if n.type=='OUTPUT_MATERIAL'),None)or ns.new('ShaderNodeOutputMaterial');lk.new(bs.outputs['BSDF'],op.inputs['Surface'])
    uv=ns.new('ShaderNodeUVMap');uv.uv_map='SurfaceUV'
    for role,im in imgs.items():
        tx=ns.new('ShaderNodeTexImage');tx.image=im;tx.extension='EXTEND';tx.label=role;lk.new(uv.outputs['UV'],tx.inputs['Vector'])
        if role=='Normal':
            nm=ns.new('ShaderNodeNormalMap');nm.inputs['Strength'].default_value=.35;lk.new(tx.outputs['Color'],nm.inputs['Color']);lk.new(nm.outputs['Normal'],bs.inputs['Normal'])
        else:lk.new(tx.outputs['Color'],bs.inputs[{'BaseColor':'Base Color','Roughness':'Roughness','Metallic':'Metallic'}[role]])
    materials.append(m)
def mapped_uv(kind,u,v):
    a,b,c,d=regions[kind];pad=3/N
    return(float(a+pad+(c-a-2*pad)*max(0,min(1,u))),float(b+pad+(d-b-2*pad)*max(0,min(1,v))))
def register(o,group):
    for co in list(o.users_collection):co.objects.unlink(o)
    coll.objects.link(o);parts.append(o);groups.setdefault(group,[]).append(o);o['runtime_group']=group;return o
def mesh(name,vs,fs,mi,uvs,group):
    me=bpy.data.meshes.new(name+'_EditableMesh');me.from_pydata([bp(v)for v in vs],[],fs);me.update()
    o=bpy.data.objects.new(name,me);coll.objects.link(o)
    for m in materials:me.materials.append(m)
    for p,i in zip(me.polygons,mi):p.material_index=i
    layer=me.uv_layers.new(name='SurfaceUV');me.uv_layers.active_index=0;layer.active_render=True
    for p,uv in zip(me.polygons,uvs):
        for li,coord in zip(p.loop_indices,uv):layer.data[li].uv=coord
    register(o,group);return o
voids=[(np.array(h['min'])-origin,np.array(h['max'])-origin,h['id'])for h in L['voids']]
def intersects(a,b,c,d,eps=1e-5):return all(min(b[k],d[k])-max(a[k],c[k])>eps for k in range(3))
gatezones=[(np.array([-2.05,.44,8.30]),np.array([6.25,4.20,8.76])),(np.array([-6.25,.44,-8.76]),np.array([2.05,4.20,-8.30]))]
def safe_detail(lo,hi):return not any(intersects(lo,hi,a,b)for a,b,_ in voids)and not any(intersects(lo,hi,a,b)for a,b in gatezones)
def box(name,at,size,kind,group='CoverDetails',mat=0,bevel=.012,check_space=True):
    lo=np.array(at)-np.array(size)/2;hi=np.array(at)+np.array(size)/2
    if check_space and not safe_detail(lo,hi):skipped.append(name);return None
    bpy.ops.mesh.primitive_cube_add(size=1,location=bp(at));o=bpy.context.object;o.name=name;o.dimensions=(size[0],size[2],size[1]);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    o.data.materials.append(materials[mat]);register(o,group)
    while o.data.uv_layers:o.data.uv_layers.remove(o.data.uv_layers[0])
    uv=o.data.uv_layers.new(name='SurfaceUV');uv.active_render=True
    for p in o.data.polygons:
        axis=max(range(3),key=lambda k:abs(gp(p.normal)[k]));axes=[k for k in range(3)if k!=axis]
        # Vertically oriented paint/concrete always has UV v along real height.
        if axis!=1:axes=[0 if axis==2 else 2,1]
        for li in p.loop_indices:
            q=gp(o.matrix_world@o.data.vertices[o.data.loops[li].vertex_index].co)
            uv.data[li].uv=mapped_uv(kind,(q[axes[0]]-lo[axes[0]])/size[axes[0]],(q[axes[1]]-lo[axes[1]])/size[axes[1]])
    if bevel:
        m=o.modifiers.new('Small_physical_edge','BEVEL');m.width=min(bevel,min(size)*.22);m.segments=1
        m=o.modifiers.new('Weighted_surface_normals','WEIGHTED_NORMAL');m.keep_sharp=True
    return o

# Reproduce the exact ordered Godot float32 collision partition for evidence;
# only visual copies are exported. Additional UV cuts are coplanar partitions.
outerlo=np.array(L['outer']['min']);outerhi=np.array(L['outer']['max'])
axes=[sorted({outerlo[k],outerhi[k]}|{float(p[k])for h in L['voids']for p in(h['min'],h['max'])if outerlo[k]<p[k]<outerhi[k]})for k in range(3)]
filled={}
for x in range(len(axes[0])-1):
 for y in range(len(axes[1])-1):
  for z in range(len(axes[2])-1):
   mid=np.array([(axes[k][i]+axes[k][i+1])/2 for k,i in enumerate((x,y,z))])
   if not any(all(np.array(h['min'])<=mid)and all(mid<np.array(h['max']))for h in L['voids']):filled[(x,y,z)]=True
dirs=[(-1,0,0),(1,0,0),(0,-1,0),(0,1,0),(0,0,-1),(0,0,1)]
def quad(lo,hi,d):
    if d[0]:
        x=lo[0]if d[0]<0 else hi[0];ps=[(x,lo[1],lo[2]),(x,hi[1],lo[2]),(x,hi[1],hi[2]),(x,lo[1],hi[2])]
    elif d[1]:
        y=lo[1]if d[1]<0 else hi[1];ps=[(lo[0],y,lo[2]),(hi[0],y,lo[2]),(hi[0],y,hi[2]),(lo[0],y,hi[2])]
    else:
        z=lo[2]if d[2]<0 else hi[2];ps=[(lo[0],lo[1],z),(hi[0],lo[1],z),(hi[0],hi[1],z),(lo[0],hi[1],z)]
    ps=np.array(ps,dtype=np.float32)
    if np.dot(np.cross(ps[1]-ps[0],ps[2]-ps[0]),d)>0:ps=ps[::-1]
    return ps
cg=[[],[],[]];original=[];visual={'NavigationSurface':[],'CoverSurface':[]}
def emit(lo,hi,d,g,group,owner):
    fixed=next(k for k in range(3)if d[k]);free=[k for k in range(3)if k!=fixed]
    # Horizontal meters share UV across the original orthogonal partitions.
    horizontal=[k for k in free if k!=1];cuts={k:[float(lo[k]),float(hi[k])]for k in free}
    for k in horizontal:
        cuts[k]=sorted(set(cuts[k]+[v for v in np.arange(-8.5,8.51,4.25)if lo[k]+1e-5<v<hi[k]-1e-5]))
    for i in range(len(cuts[free[0]])-1):
      for j in range(len(cuts[free[1]])-1):
        a=lo.copy();b=hi.copy()
        for k,n in zip(free,(i,j)):a[k]=cuts[k][n];b[k]=cuts[k][n+1]
        ps=quad(a,b,d)[::-1].copy();kind='concrete'if fixed!=1 else'roof'if d[1]>0 and abs(float(hi[1])-6)<1e-5 else'floor'
        if fixed!=1:
            k=0 if fixed==2 else 2;band=math.floor(((a[k]+b[k])/2+8.5)/4.25+1e-7)
            uvs=[mapped_uv(kind,(p[k]+8.5-band*4.25)/4.25,p[1]/6)for p in ps]
        else:
            bands={k:math.floor(((a[k]+b[k])/2+8.5)/4.25+1e-7)for k in(0,2)}
            uvs=[mapped_uv(kind,(p[0]+8.5-bands[0]*4.25)/4.25,(p[2]+8.5-bands[2]*4.25)/4.25)for p in ps]
        visual[group].append({'points':ps.tolist(),'uv':uvs,'material':g,'owner':owner,'area':float((b[free[0]]-a[free[0]])*(b[free[1]]-a[free[1]]))})
for cell in filled:
 lo=np.array([axes[k][cell[k]]for k in range(3)],dtype=np.float32)-origin
 hi=np.array([axes[k][cell[k]+1]for k in range(3)],dtype=np.float32)-origin
 for d in dirs:
  if tuple(cell[k]+d[k]for k in range(3))in filled:continue
  g=1 if d[1]>0 else 2 if d[1]<0 else 0;ps=quad(lo,hi,d);cg[g].extend(ps[[0,1,2,0,2,3]].tolist())
  owner=len(original);fixed=next(k for k in range(3)if d[k]);free=[k for k in range(3)if k!=fixed]
  original.append({'points':ps.tolist(),'group':g,'area':float((hi[free[0]]-lo[free[0]])*(hi[free[1]]-lo[free[1]]))})
  if d[1]:emit(lo,hi,d,g,'NavigationSurface'if d[1]>0 and hi[1]<6 else'CoverSurface',owner);continue
  if(cell[0],cell[1]+1,cell[2])not in filled and hi[1]<6:emit(lo,hi,d,g,'NavigationSurface',owner);continue
  air=(lo+hi)/2+origin;k=0 if d[0]else 2;air[k]=(lo[k]if d[k]<0 else hi[k])+origin[k]+d[k]*.001
  floors=[h['min'][1]for h in L['voids']if h['min'][0]<air[0]<h['max'][0]and h['min'][2]<air[2]<h['max'][2]]
  cut=np.float32(max(lo[1],min(hi[1],min(floors,default=0)+.32)))
  if cut>=hi[1]:emit(lo,hi,d,g,'NavigationSurface',owner)
  elif cut<=lo[1]:emit(lo,hi,d,g,'CoverSurface',owner)
  else:
    fh=hi.copy();fh[1]=cut;wl=lo.copy();wl[1]=cut
    emit(lo,fh,d,g,'NavigationSurface',owner);emit(wl,hi,d,g,'CoverSurface',owner)
raw=np.array([p for g in cg for p in g],dtype='<f4').tobytes();collision_sha=hashlib.sha256(raw).hexdigest()
check('original_696_collision_bytes',len(raw)//36==696 and collision_sha=='8a9138bcf652ba71777aa89ec89bff8b790068b6e0c5b570c252560d51ee6473',{'triangles':len(raw)//36,'sha256':collision_sha})
for group,rows in visual.items():
    vs=[];fs=[];mi=[];uv=[]
    for row in rows:
        n=len(vs);vs+=row['points'];fs.append(tuple(range(n,n+4)));mi.append(row['material']);uv.append(row['uv'])
    mesh(group,vs,fs,mi,uv,group)
covered=[0.0]*len(original)
for rows in visual.values():
 for row in rows:covered[row['owner']]+=row['area']
check('every_original_face_area_covered',all(abs(covered[i]-r['area'])<3e-5 for i,r in enumerate(original)),{'original_quads':len(original),'rendered_quads':sum(map(len,visual.values()))})
(EV/'surface_partition.json').write_text(json.dumps({'original':original,'visual':visual,'collision_sha256':collision_sha},indent=2),encoding='utf-8')

# Exterior steel framework. 6mm is the declared shallow visual allowance;
# parking envelopes and every playable opening are excluded before creation.
for s in(-1,1):
    z=s*8.472
    for x in(-8.15,-4.55,4.55,8.15):
        box('FacadePost_%s_%s'%(s,x),(x,3,z),(.24,5.9,.060),'paint')
    box('FacadeHeader_%s'%s,(0,5.62,s*8.473),(16.78,.56,.060),'paint')
    for x in(-7.3,-3.7,0,3.7,7.3):
        box('HeaderSplice_%s_%s'%(s,x),(x,5.62,s*8.487),(.38,.63,.034),'paint')
        for dx in(-.105,.105):
            box('HeaderFastener_%s_%s_%s'%(s,x,dx),(x+dx,5.79,s*8.501),(.075,.075,.010),'steel',bevel=.01)
    # Short dark fascia inserts read as closed ventilation panels, not new holes.
    for x in(-6.4,-2.7,2.7,6.4):
        box('FasciaInset_%s_%s'%(s,x),(x,5.03,s*8.495),(2.65,.42,.018),'dark')
        for y in(4.91,5.08):box('FasciaBlade_%s_%s_%s'%(s,x,y),(x,y,s*8.502),(2.50,.055,.008),'steel',bevel=.001)
for s in(-1,1):
    x=s*8.472
    for z in(-8.15,-4.5,-.9,1.65,5.35,8.15):box('SidePost_%s_%s'%(s,z),(x,3,z),(.060,5.9,.24),'paint')
    box('SideHeader_%s'%s,(s*8.473,5.62,0),(.060,.56,16.78),'paint')
    for z in(-6.3,-2.7,2.7,6.3):
        box('SideFascia_%s_%s'%(s,z),(s*8.495,5.03,z),(.018,.42,2.55),'dark')
        for y in(4.91,5.08):box('SideFasciaBlade_%s_%s_%s'%(s,z,y),(s*8.502,y,z),(.008,.055,2.4),'steel',bevel=.001)
    for z in(-7.3,-3.7,0,3.7,7.3):
        box('SideSplice_%s_%s'%(s,z),(s*8.487,5.62,z),(.034,.63,.38),'paint')
        for dz in(-.105,.105):box('SideFastener_%s_%s_%s'%(s,z,dz),(s*8.501,5.79,z+dz),(.010,.075,.075),'steel',bevel=.01)
# No decorative side-window bar; four flush surround strips stay OUTSIDE void.
for z in(1.74,5.26):box('EastWindowJamb_'+str(z),(8.483,3.55,z),(.046,2.65,.20),'paint')
for y in(2.17,4.94):box('EastWindowEdge_'+str(y),(8.483,y,3.5),(.046,.20,3.7),'paint')

# Roof thin service seams and drain strip: very shallow, no new rail or stair.
for x in(-8.20,8.20):box('RoofSideCap_'+str(x),(x,5.99,0),(.22,.032,16.6),'paint',mat=1,bevel=.004)
for z in(-8.2,8.2):box('RoofEndCap_'+str(z),(0,5.99,z),(16.1,.032,.22),'paint',mat=1,bevel=.004)
box('RoofDrainBed',(0,5.999,3.05),(16.1,.008,.43),'dark',mat=1,bevel=0)
for x in np.linspace(-7.9,7.9,52):box('RoofDrainSlat_%.2f'%x,(x,6.003,3.05),(.055,.006,.39),'steel',mat=1,bevel=0)
for x in(-7,0,7):
    # Their three separate source boxes EXACTLY express existing solid columns.
    box('Tower_%s_SolidHousing'%x,(x,8.8,1),(3,5.6,3),'concrete','RoofSupports',bevel=0)
    for dx in(-1.40,1.40):
      for dz in(-1.40,1.40):box('Tower_%s_Corner_%s_%s'%(x,dx,dz),(x+dx,8.8,1+dz),(.204,5.58,.204),'paint','RoofSupports',bevel=.018)
    for y in(6.15,9.15,11.42):
      for s in(-1,1):
        box('Tower_%s_FB_Belt_%s_%s'%(x,y,s),(x,y,1+s*1.478),(2.84,.20,.052),'paint','RoofSupports')
        box('Tower_%s_LR_Belt_%s_%s'%(x,y,s),(x+s*1.478,y,1),(.052,.20,2.84),'paint','RoofSupports')
    for s in(-1,1):
      box('Tower_%s_FB_VentBed_%s'%(x,s),(x,10.28,1+s*1.496),(2.48,1.92,.016),'dark','RoofSupports',bevel=.008)
      box('Tower_%s_LR_VentBed_%s'%(x,s),(x+s*1.496,10.28,1),(.016,1.92,2.48),'dark','RoofSupports',bevel=.008)
      for i in range(8):
        y=9.47+i*.235
        box('Tower_%s_FB_Louver_%s_%s'%(x,s,i),(x,y,1+s*1.499),(2.34,.070,.014),'steel','RoofSupports',bevel=.006)
        box('Tower_%s_LR_Louver_%s_%s'%(x,s,i),(x+s*1.499,y,1),(.014,.070,2.34),'steel','RoofSupports',bevel=.006)
    # Flush tower cap and distinct long vertical panel seams.
    box('Tower_%s_TopCap'%x,(x,11.593,1),(2.98,.026,2.98),'steel','RoofSupports',bevel=.007)
    for s in(-1,1):
      for dx in(-.42,.42):box('Tower_%s_LowerSeam_%s_%s'%(x,s,dx),(x+dx,7.7,1+s*1.502),(.022,2.78,.006),'dark','RoofSupports',bevel=0)
      for dx in(-1.30,1.30):
       for y in(6.22,9.14,11.40):box('Tower_%s_Bolt_%s_%s_%s'%(x,s,dx,y),(x+dx,y,1+s*1.501),(.08,.08,.010),'steel','RoofSupports',bevel=.01)
    # The tower maintenance boundary is paint on existing roof, not a fence.
    for s in(-1,1):
      box('Tower_%s_SafetyFB_%s'%(x,s),(x,6.002,1+s*1.70),(2.9,.004,.09),'yellow',mat=1,bevel=0)
      if abs(x+s*1.70)+.045<8.5:box('Tower_%s_SafetyLR_%s'%(x,s),(x+s*1.70,6.002,1),(.09,.004,3.4),'yellow',mat=1,bevel=0)

# Runtime branches; authoring parts remain separately editable in saved blend.
root=bpy.data.objects.new('UnderdeckShellArt',None);coll.objects.link(root)
parents={}
for name in('PermanentNavigation','OccludingCover'):
    p=bpy.data.objects.new(name,None);coll.objects.link(p);p.parent=root;parents[name]=p
    if name=='PermanentNavigation':p['terrain_visibility_keep']=True
for o in parts:
    p=parents['PermanentNavigation'if o['runtime_group']=='NavigationSurface'else'OccludingCover'];mw=o.matrix_world.copy();o.parent=p;o.matrix_world=mw
dg=bpy.context.evaluated_depsgraph_get();stats={}
for g,obs in groups.items():
    ps=[];tri=0
    for o in obs:
        eo=o.evaluated_get(dg);me=eo.to_mesh();me.calc_loop_triangles();tri+=len(me.loop_triangles);ps.extend(gp(o.matrix_world@v.co).tolist()for v in me.vertices);eo.to_mesh_clear()
    a=np.array(ps);stats[g]={'triangles':tri,'bounds':{'min':a.min(0).tolist(),'max':a.max(0).tolist()},'editable_parts':[o.name for o in obs]}
check('all_parts_single_explicit_uv',all(len(o.data.uv_layers)==1 and o.data.uv_layers.active.name=='SurfaceUV'and o.data.uv_layers.active.active_render for o in parts))
check('three_material_bindings',len(materials)==3)
check('runtime_budget_22000',sum(v['triangles']for v in stats.values())<=22000,{'triangles':sum(v['triangles']for v in stats.values())})
check('cover_includes_all_three_full_height_towers',len([o for o in parts if o.name.endswith('SolidHousing')])==3 and abs(stats['RoofSupports']['bounds']['max'][1]-11.606)<.001)
bad=[]
for o in parts:
 if o['runtime_group']in('NavigationSurface','CoverSurface'):continue
 pts=np.array([gp(o.matrix_world@Vector(c))for c in o.bound_box]);lo=pts.min(0);hi=pts.max(0)
 if not safe_detail(lo,hi):bad.append(o.name)
check('independent_all_detail_AABB_clearance',not bad,bad)
check('bounded_6mm_visual_skin',all(v['bounds']['min'][0]>=-8.5061 and v['bounds']['min'][2]>=-8.5061 and v['bounds']['max'][0]<=8.5061 and v['bounds']['max'][2]<=8.5061 and v['bounds']['min'][1]>=-.00001 and v['bounds']['max'][1]<=11.6061 for v in stats.values()),stats)
check('no_new_runtime_collision',not any(o.rigid_body for o in parts))

# Studio with the real fixed oblique direction. Whole object fits in frame.
w=bpy.data.worlds.new('Warehouse_NeutralStudio');scene.world=w;w.use_nodes=True
bg=next((n for n in w.node_tree.nodes if n.type=='BACKGROUND'),None)
if bg is None:
 bg=w.node_tree.nodes.new('ShaderNodeBackground');wo=w.node_tree.nodes.new('ShaderNodeOutputWorld');w.node_tree.links.new(bg.outputs[0],wo.inputs[0])
bg.inputs[0].default_value=(.33,.35,.37,1);bg.inputs[1].default_value=.7
def area(name,at,power,size,color):
 d=bpy.data.lights.new(name,'AREA');d.energy=power;d.shape='DISK';d.size=size;d.color=color;o=bpy.data.objects.new(name,d);scene.collection.objects.link(o);o.location=bp(at);o.rotation_euler=(bp((0,4,0))-o.location).to_track_quat('-Z','Y').to_euler()
area('StudioKey',(3,24,19),4000,16,(1,.96,.90));area('StudioFill',(-18,13,10),2600,16,(.90,.95,1));area('StudioRim',(5,17,-19),3800,15,(1,.98,.94))
mat=bpy.data.materials.new('StudioGround_NOT_EXPORTED');mat.diffuse_color=(.26,.27,.27,1)
bpy.ops.mesh.primitive_plane_add(size=250,location=(0,0,-.03));ground=bpy.context.object;ground.name='STUDIO_GROUND_NOT_EXPORTED';ground.data.materials.append(mat)
cd=bpy.data.cameras.new('WarehouseReviewCamera');cam=bpy.data.objects.new('WarehouseReviewCamera',cd);scene.collection.objects.link(cam);scene.camera=cam;cd.type='ORTHO';cd.ortho_scale=35;cd.clip_end=300
def camera(at,target=(0,4.8,0)):
    cam.location=bp(at);cam.rotation_euler=(bp(target)-cam.location).to_track_quat('-Z','Y').to_euler()
camera((32,43.8,32));scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=20;scene.render.threads_mode='FIXED';scene.render.threads=2
scene.render.resolution_x=1600;scene.render.resolution_y=1100;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG'
scene.view_settings.view_transform='AgX';scene.view_settings.look='AgX - Medium High Contrast';scene.view_settings.exposure=0
bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'underdeck_shell.blend'))
report={'blender':bpy.app.version_string,'pid':os.getpid(),'source_origin_world':L['origin'],'checks':checks,'passed':sum(c['passed']for c in checks),'failed':sum(not c['passed']for c in checks),'group_stats':stats,'editable_meshes':len(parts),'materials':[m.name for m in materials],'skipped_for_clearance':skipped,'reference_sha256':sha(ROOT/'references/v3/production/underdeck_shell/underdeck_shell_v1.png'),'collision_sha256':collision_sha,'shallow_visual_offset_m':.006,'scope':'offline editable art; original collision replay only, no engine sweep or visual acceptance; UV-authored PBR, not high-low baking'}
(EV/'build_report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
assert not report['failed'],[c for c in checks if not c['passed']]

# Merge evaluated export COPIES, preserving source hierarchy and each part.
ex=bpy.data.collections.new('ExportCopies');scene.collection.children.link(ex);er=bpy.data.objects.new('ExportUnderdeckShellArt',None);ex.objects.link(er);exports=[er]
eps={}
for name in parents:
 p=bpy.data.objects.new('Export'+name,None);ex.objects.link(p);p.parent=er;eps[name]=p;exports.append(p)
 if name=='PermanentNavigation':p['terrain_visibility_keep']=True
for group,obs in groups.items():
 cs=[]
 for o in obs:
    me=bpy.data.meshes.new_from_object(o.evaluated_get(dg),preserve_all_data_layers=True,depsgraph=dg);c=bpy.data.objects.new('EX_'+o.name,me);ex.objects.link(c);c.matrix_world=o.matrix_world.copy();cs.append(c)
 bpy.ops.object.select_all(action='DESELECT')
 for c in cs:c.select_set(True)
 bpy.context.view_layer.objects.active=cs[0];bpy.ops.object.join();c=bpy.context.object
 if group in bpy.data.objects:bpy.data.objects[group].name='SOURCE_'+group
 c.name=group;scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR');bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
 mw=c.matrix_world.copy();c.parent=eps['PermanentNavigation'if group=='NavigationSurface'else'OccludingCover'];c.matrix_world=mw;exports.append(c)
root.name='SOURCE_UnderdeckShellArt';er.name='UnderdeckShellArt'
for name,p in parents.items():p.name='SOURCE_'+name;eps[name].name=name
bpy.ops.object.select_all(action='DESELECT')
for o in exports:o.select_set(True)
bpy.context.view_layer.objects.active=er;path=OUT/'underdeck_shell.glb'
bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_apply=True,export_yup=True,export_texcoords=True,export_normals=True,export_materials='EXPORT',export_cameras=False,export_lights=False,export_animations=False,export_extras=True)
report['export']={'path':str(path),'bytes':path.stat().st_size,'sha256':sha(path)}
for o in exports:bpy.data.objects.remove(o,do_unlink=True)
for label,at in [('front',(32,43.8,32)),('rear',(-32,43.8,-32))]:
 camera(at);scene.render.filepath=str(EV/('underdeck_shell_source_'+label+'.png'));bpy.ops.render.render(write_still=True)
report['elapsed_seconds']=time.time()-started;report['render_complete']=True
(EV/'build_report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('SHELL_BUILD_DONE',json.dumps({'pid':os.getpid(),'seconds':report['elapsed_seconds'],'triangles':sum(v['triangles']for v in stats.values()),'checks_passed':report['passed'],'export':report['export']}),flush=True)
