"""Executed in build_siphon_whale's namespace; original geometry and PBR maps."""
import numpy as np,hashlib
TEX=OUT/'textures';TEX.mkdir(parents=True,exist_ok=True)
# Original calm, low-contrast base surfaces, wear tied to each armor panel's edge.
def make_maps(material,index):
 n=1024 if index<3 else 512;rng=np.random.default_rng(7300+index)
 v,u=np.mgrid[0:1:complex(n),0:1:complex(n)]
 def cloud(cells):
  g=rng.random((cells+1,cells+1));x=np.minimum(u*cells,cells-.00001);y=np.minimum(v*cells,cells-.00001)
  ix=x.astype(int);iy=y.astype(int);fx=x-ix;fy=y-iy;fx=fx*fx*(3-2*fx);fy=fy*fy*(3-2*fy)
  return (1-fx)*(1-fy)*g[iy,ix]+fx*(1-fy)*g[iy,ix+1]+(1-fx)*fy*g[iy+1,ix]+fx*fy*g[iy+1,ix+1]
 broad=cloud(7);medium=cloud(33);grain=rng.random((n,n));edge=np.minimum.reduce([u,1-u,v,1-v])
 edgemask=np.clip((.010+.015*medium-edge)*45,0,1)
 palette=[(.65,.65,.59),(.055,.17,.19),(.32,.35,.36),(.024,.031,.032),(.82,.43,.025),(.02,.43,.54)]
 base=np.array(palette[index])[None,None,:]*(.965+.055*broad[:,:,None]+.015*(grain[:,:,None]-.5))
 rough=np.full((n,n),[.56,.54,.40,.76,.61,.30][index])+.045*(medium-.5)
 metal=np.full((n,n),[.08,.13,.83,.24,.05,.15][index]);height=.0025*grain
 if index in [0,1,2]:
  oxide=edgemask*np.clip((medium-.30)*2,0,1)*(.72 if index!=2 else .24)
  # Only a few narrow gravity drips, starting at panel top and dying quickly.
  for x in [.13,.59,.84]:
   oxide+=np.exp(-((u-x)/.007)**2)*np.clip((v-.54)/.35,0,1)*.16
  oxide=np.clip(oxide,0,.8)
  base=base*(1-oxide[:,:,None])+np.array([.25,.105,.035])*oxide[:,:,None]
  chip=edgemask*np.clip((grain-.92)*9,0,1)*.65
  base=base*(1-chip[:,:,None])+np.array([.39,.40,.37])*chip[:,:,None]
  rough+=oxide*.19;metal*=1-oxide*.68;metal=metal*(1-chip)+.75*chip;height-=chip*.016
 if index==4:
  stripe=((u*5+v*.25)%1)<.60;base=np.where(stripe[:,:,None],base,np.array([.025,.028,.027]));base*=1-edgemask[:,:,None]*.12
 if index==5:
  # The only emissive material: coherent segments inside the protected cells.
  band=.77+.22*np.cos(v*math.pi*10)**8;base*=band[:,:,None]
 gy,gx=np.gradient(height);normal=np.dstack((-gx*12,-gy*12,np.ones_like(height)));normal/=np.linalg.norm(normal,axis=2)[:,:,None]
 maps={'BaseColor':base,'Roughness':np.clip(rough,0,1),'Metallic':metal,'Normal':normal*.5+.5}
 nodes=material.node_tree.nodes;bs=nodes.get('Principled BSDF');images={}
 for role,data in maps.items():
  px=np.ones((n,n,4),np.float32);px[:,:,:3]=data[:,:,None] if data.ndim==2 else data
  im=bpy.data.images.new(material.name+'_'+role,width=n,height=n,alpha=True)
  if role!='BaseColor':im.colorspace_settings.name='Non-Color'
  im.pixels.foreach_set(px.ravel());dst=TEX/(material.name+'_'+role+'.png');im.filepath_raw=str(dst);im.file_format='PNG';im.save();im.filepath=bpy.path.relpath(str(dst),start=str(SRC));images[role]=im
  node=nodes.new('ShaderNodeTexImage');node.image=im;node.label=role;node.extension='EXTEND'
  if role=='Normal':
   nm=nodes.new('ShaderNodeNormalMap');nm.inputs['Strength'].default_value=.20;material.node_tree.links.new(node.outputs['Color'],nm.inputs['Color']);material.node_tree.links.new(nm.outputs['Normal'],bs.inputs['Normal'])
  else:material.node_tree.links.new(node.outputs['Color'],bs.inputs[{'BaseColor':'Base Color','Roughness':'Roughness','Metallic':'Metallic'}[role]])
  if index==5 and role=='BaseColor':material.node_tree.links.new(node.outputs['Color'],bs.inputs['Emission Color'])
 return images
PBR={m.name:make_maps(m,i) for i,m in enumerate(materials)}

def section_at(z,sections):
 for a,b in zip(sections,sections[1:]):
  if a[0]-1e-6<=z<=b[0]+1e-6:
   t=(z-a[0])/(b[0]-a[0]);return [a[k]*(1-t)+b[k]*t for k in range(1,4)]
 return list(sections[0 if z<sections[0][0] else -1][1:])
def surface_point(z,a,sections,cx=0,offset=.035):
 rx,ry,cy=section_at(z,sections);return (cx+(rx+offset)*math.cos(a),cy+(ry+offset)*math.sin(a),z)
def panel(name,z0,z1,a0,a1,sections,m,cx=0,group='StaticHull',nu=6,nv=4,offset=.035):
 vs=[];fs=[]
 for j in range(nv+1):
  z=z0+(z1-z0)*j/nv
  for i in range(nu+1):vs.append(surface_point(z,a0+(a1-a0)*i/nu,sections,cx,offset))
 for j in range(nv):
  for i in range(nu):
   a=j*(nu+1)+i;fs.append((a,a+1,a+nu+2,a+nu+1))
 o=mesh(name,vs,fs,m,group,True);uv=o.data.uv_layers.new(name='ArmorUV')
 for face in o.data.polygons:
  for li in face.loop_indices:
   vi=o.data.loops[li].vertex_index;j,i=divmod(vi,nu+1);uv.data[li].uv=(.018+.964*i/nu,.018+.964*j/nv)
 solid=o.modifiers.new('Plate_thickness','SOLIDIFY');solid.thickness=.040;solid.offset=0
 return o
# Body undercoat plus genuinely separate curved formed panels. No geometry at core hole.
body=bpy.data.objects['Whale_continuous_curved_hull'];body.data.materials[0]=teal
# Long load-bearing shoulder shells, a separate spine and a teal lower belt.
# Panel boundaries follow service regions, deliberately not every hull cross-section.
angles=[0,.48,theta_a,theta_b,math.pi-.48,math.pi,4*math.pi/3,5*math.pi/3,2*math.pi]
for ai,(t0,t1) in enumerate(zip(angles,angles[1:])):
 if ai in [1,3]:zcuts=[-8.52,-5.20,-1.65,1.2,4.4,6.42]
 elif ai==2:zcuts=[-8.52,-6.3,-2.50,1.2,4.4,6.42]
 elif ai in [0,4]:zcuts=[-8.52,-4.30,.35,6.42]
 else:zcuts=[-8.52,-4.8,1.8,6.42]
 for za,zb in zip(zcuts,zcuts[1:]):
  if ai==2 and za>=1.19 and zb<=4.41:continue
  chosen=teal if ai in [0,4,5,7] and za>=-4.9 else ivory
  panel('Hull_long_formed_shell',za+.018,zb-.018,t0+.004,t1-.004,HULL,chosen,nu=10,nv=max(8,int((zb-za)*4)))
  if ai in [1,3] and za>=-5.21:
   for z in [za+.18,zb-.18]:
    theta=t0+.07 if ai==1 else t1-.07;p=surface_point(z,theta,HULL,offset=.075);n=Vector((math.cos(theta),math.sin(theta),0));cylinder('Shell_edge_hex_fastener',Vector(p)-n*.015,Vector(p)+n*.032,.050,steel,verts=6)
# Small dedicated inspection covers and recessed ventilation groups on each shoulder.
for side in [-1,1]:
 a0,a1=(.73,1.02) if side>0 else (math.pi-1.02,math.pi-.73)
 panel('Inspection_cover_surround',-1.24,.20,a0-.018,a1+.018,HULL,steel,nu=6,nv=5,offset=.074)
 panel('Inspection_cover_painted_lid',-1.17,.13,a0,a1,HULL,teal,nu=6,nv=5,offset=.098)
 for z in [-1.08,.04]:
  for a in [a0+.025,a1-.025]:
   p=Vector(surface_point(z,a,HULL,offset=.13));n=Vector((math.cos(a),math.sin(a),0));cylinder('Service_cover_fastener',p-n*.012,p+n*.028,.042,steel,verts=6)
 panel('Vent_recess_dark_back',-3.65,-2.10,a0,a1,HULL,dark,nu=6,nv=7,offset=.074)
 for j in range(6):
  z=-3.54+j*.245
  panel('Vent_individual_metal_louvre',z,z+.085,a0+.012,a1-.012,HULL,steel,nu=5,nv=1,offset=.125)
 # Restrained warning stripes at the nose maintenance boundary, not every plate.
 a0,a1=(.51,.65) if side>0 else (math.pi-.65,math.pi-.51)
 panel('Nose_maintenance_hazard',4.82,5.72,a0,a1,HULL,safety,nu=3,nv=4,offset=.083)
# Mechanical seams across curved hatch skins and restrained safety strips.
for side in [-1,1]:
 group='PortHatch' if side<0 else 'StarboardHatch'
 pod=[(-2.75,.58,.62,0),(-2.25,1.16,1.02,0),(-1.5,1.38,1.15,0),(1.5,1.38,1.15,0),(2.4,1.08,.91,0),(2.85,.68,.65,0)]
 base=next(o for o in groups[group] if 'curved_upper' in o.name);base.data.materials[0]=teal
 zcuts=[-2.7,-1.40,1.70,2.80]
 for a,b in zip(zcuts,zcuts[1:]):
  for j in range(2):panel('Pod_long_hatch_shell',a+.016,b-.016,j*math.pi/2+.006,(j+1)*math.pi/2-.006,pod,ivory if a<1.69 else teal,cx=side*7,group=group,nu=10,nv=9)
 panel('Pod_service_spine',-.85,.65,1.38,1.76,pod,teal,cx=side*7,group=group,nu=4,nv=5,offset=.085)
 for z in [-.65,-.25,.15,.50]:panel('Pod_spine_louvre',z,z+.07,1.40,1.74,pod,steel,cx=side*7,group=group,nu=3,nv=1,offset=.12)
 # Safety painted panels are separate real strips on the outer upper edge.
 a0=.06 if side>0 else math.pi-.16
 for z0,z1 in [(-1.4,-.6),(.6,1.4)]:panel('Hatch_hazard_strip',z0,z1,a0,a0+.10,pod,safety,cx=side*7,group=group,nu=2,nv=2)
 for z in [-1.65,-.55,.55,1.65]:
  cylinder('Hatch_hinge_knuckle',(side*5.75,.10,z-.16),(side*5.75,.10,z+.16),.20,steel,verts=12)
  cylinder('Hatch_hinge_endcap',(side*5.75,.10,z-.18),(side*5.75,.10,z-.15),.21,teal,verts=12)
  # Bolted mount below the hatch swing volume.
  box('Pod_hinge_mount',(side*5.82,-.04,z),(.32,.28,.40),teal,radius=.035)
 # Cells retain metal supports separate from their three emissive mesh nodes.
 for z in [-.78,.78]:ellipse_rim('Side_cell_collar',(side*7,.25,z),.43,.43,.045,steel,n=24)
 for z in [-.96,.96]:cylinder('Side_cell_dark_end',(side*7,.25,z-.025),(side*7,.25,z+.025),.40,steel,verts=20)
 for z in [-1.1,1.1]:
  cylinder('Pectoral_joint_housing',(side*4.72,-.38,z),(side*5.02,-.38,z),.30,teal,verts=16)
  cylinder('Pectoral_joint_pin',(side*4.68,-.38,z),(side*5.08,-.38,z),.12,steel,verts=12)
# Nose lip assembled ring panels and internal intake ribs with depth.
for j in range(24):
 a=2*math.pi*j/24;c=(3.80*math.cos(a),-.20+1.53*math.sin(a),6.79)
 cylinder('Nose_lip_rivet',(c[0],c[1],6.75),(c[0],c[1],6.83),.048,steel,verts=6)
for x in [-2.1,0,2.1]:box('Gill_cross_backplate',(x,-.20,6.16),(.10,2.2,.10),teal,radius=.018)
# Tail lobes get raised tapered plates; joint rings stay visually separate.
for side in [-1,1]:
 outline=[(side*.85,-8.4),(side*2.3,-8.2),(side*3.7,-7.8),(side*3.8,-8.3),(side*3.4,-8.95),(side*2.1,-9.5),(side*.8,-9.25)]
 if side<0:outline.reverse()
 o=extruded_outline('Tail_swept_armor_plate',outline,1.34,.055,ivory)
 for v in o.data.vertices:v.co.z+=abs(v.co.x)*.045
 for z in [-8.5,-8.9]:cylinder('Tail_pin_lock',(side*.90,1.38,z),(side*.90,1.48,z),.065,steel,verts=6)
 # Real tapered stiffener webs and inspection hardware, not a featureless inlay.
 for offset in [0,.42]:
  web=[(side*1.15,-8.45-offset),(side*1.20,-8.53-offset),(side*3.15,-8.16-offset),(side*3.12,-8.07-offset)]
  if side<0:web.reverse()
  o=extruded_outline('Tail_tapered_stiffener',web,1.43,.07,steel)
  for v in o.data.vertices:v.co.z+=abs(v.co.x)*.045
 for x,z in [(1.35,-9.05),(3.0,-8.55)]:
  y=1.49+x*.045;cylinder('Tail_plate_lock',(side*x,y,z),(side*x,y+.055,z),.065,steel,verts=6)
# Shield gets a flat grip ridge and rails that belong to its moving group.
for z in [1.52,3.95]:
 p=surface_point(z,math.pi/2,HULL,offset=.11);box('Shield_slide_grip',(0,p[1],z),(.68,.07,.12),steel,'CoreShield',.025)
for side in [-1,1]:
 for z in [1.35,4.20]:
  p=surface_point(z,theta_a if side>0 else theta_b,HULL,offset=.13);cylinder('Core_frame_bolt',(p[0],p[1]-.04,p[2]),(p[0],p[1]+.025,p[2]),.05,steel,verts=6)

# Planar projection only for secondary pieces; major curved plates already use coherent UV.
for o in parts:
 if o.data.uv_layers:continue
 uv=o.data.uv_layers.new(name='ArmorUV')
 for face in o.data.polygons:
  axis=max(range(3),key=lambda k:abs(face.normal[k]));axes=[k for k in range(3) if k!=axis]
  cs=[o.data.vertices[o.data.loops[li].vertex_index].co for li in face.loop_indices]
  lo=[min(c[k] for c in cs) for k in axes];hi=[max(c[k] for c in cs) for k in axes]
  for li,c in zip(face.loop_indices,cs):uv.data[li].uv=tuple(.025+.95*(c[k]-a)/(b-a or 1) for k,a,b in zip(axes,lo,hi))
for o in parts:
 o.data.uv_layers.active.name='ArmorUV';o.data.uv_layers.active.active_render=True
(EVID/'original_materials.json').write_text(json.dumps({'origin':'Original procedural panel-edge coastal PBR maps; no copied external imagery','materials':[m.name for m in materials],'files':[{'path':str(p.relative_to(ROOT)),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(TEX.glob('*.png'))]},indent=2),encoding='utf-8')
