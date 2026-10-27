"""P2 thick interlocked stone sections and roots that actually turn corners.
First source/basic-material study only. No PBR atlas, GLB or game import.
Local coordinates: u=Godot Z width, v=Godot Y up, t=Godot X thickness.
"""
from pathlib import Path
import bpy,bmesh,math,json,hashlib,struct,sys
from mathutils import Vector
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
P1=HERE.parent/'p1';SOURCE=P1/'rising_seal_source_p1.blend'
REF=ROOT/'references/v3/production/rising_seal/rising_seal_reference_v1.png'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
input_hashes={str(p.relative_to(ROOT)).replace('\\','/'):sha(p) for p in [SOURCE,P1/'build_rising_seal.py',REF]}
assert sha(REF)=='836f5f42091d21ba9561cf78c387fc7220aa3ad840a7ffc1b70906021ea1d3f6'
bpy.ops.wm.open_mainfile(filepath=str(SOURCE));scene=bpy.context.scene
col=bpy.data.collections['Editable_RisingSeal'];root=bpy.data.objects['RisingSeal']
pos=lambda u,v,t:Vector((t,-u,v))
def digest(ob):
 h=hashlib.sha256();h.update(struct.pack('<16d',*(x for row in ob.matrix_world for x in row)))
 if ob.type=='MESH':
  for v in ob.data.vertices:h.update(struct.pack('<3d',*v.co))
  for f in ob.data.polygons:h.update(struct.pack('<'+str(len(f.vertices))+'I',*f.vertices))
 return h.hexdigest()
old_parts=[o for o in root.children if o.type=='MESH']
preserved={o.name:digest(o) for o in root.children if o.name not in ['ContinuousSlab'] and not o.name.startswith(('StoneSection_','RootCorner_','RootBraid_','RootFork_'))}
for ob in old_parts:
 if ob.name=='ContinuousSlab' or ob.name.startswith(('StoneSection_','RootCorner_','RootBraid_','RootFork_')):bpy.data.objects.remove(ob,do_unlink=True)

def mat(name,color,rough=.88):
 m=bpy.data.materials.new(name);m.use_nodes=True
 p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED');p.inputs['Base Color'].default_value=(*color,1);p.inputs['Roughness'].default_value=rough;p.inputs['Specular IOR Level'].default_value=.18
 return m
stone=mat('P2_Stone_BroadBrush',(.235,.265,.275))
edge=mat('P2_Stone_WornFracture',(.29,.285,.26))
dark=mat('P2_Stone_SeamFloor',(.16,.19,.20))
wood=mat('P2_Root_BroadGrain',(.17,.105,.055))
# Continuous low-contrast brush variation, never Voronoi colour cells.
for material,lo,hi,scale in [(stone,(.215,.25,.262,1),(.265,.285,.29,1),(.6,1.25,.8)),(wood,(.125,.074,.038,1),(.205,.133,.074,1),(4.5,1.1,1))]:
 ns=material.node_tree.nodes;ls=material.node_tree.links;p=next(n for n in ns if n.type=='BSDF_PRINCIPLED')
 coord=ns.new('ShaderNodeTexCoord');mapping=ns.new('ShaderNodeVectorMath');mapping.operation='MULTIPLY';mapping.inputs[1].default_value=scale
 texture=ns.new('ShaderNodeTexNoise');texture.inputs['Scale'].default_value=1.45;texture.inputs['Detail'].default_value=.7;texture.inputs['Roughness'].default_value=.3
 ramp=ns.new('ShaderNodeValToRGB');ramp.color_ramp.elements[0].position=.12;ramp.color_ramp.elements[0].color=lo;ramp.color_ramp.elements[1].position=.88;ramp.color_ramp.elements[1].color=hi
 ls.new(coord.outputs['UV' if material==wood else 'Object'],mapping.inputs[0]);ls.new(mapping.outputs[0],texture.inputs['Vector']);ls.new(texture.outputs['Fac'],ramp.inputs[0]);ls.new(ramp.outputs[0],p.inputs['Base Color'])

def mesh(name,verts,faces,materials,indices=None):
 data=bpy.data.meshes.new(name+'_Mesh');data.from_pydata(verts,[],faces);data.update()
 ob=bpy.data.objects.new(name,data);col.objects.link(ob);ob.parent=root
 for m in materials:data.materials.append(m)
 if indices:
  for poly,i in zip(data.polygons,indices):poly.material_index=i
 bm=bmesh.new();bm.from_mesh(data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(data);bm.free()
 return ob

outline=[(-3.42,-2.5),(3.42,-2.5),(3.43,1.92),(3.20,2.34),(1.15,2.35),(.45,2.39),(-1.17,2.36),(-3.20,2.32),(-3.44,1.93)]
n=len(outline)
back=mesh('SeamClosure',[pos(u,v,t) for t in [-.36,-.20] for u,v in outline],[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],[dark])

# The six stones extend through most of the slab thickness. Uneven edge bands
# and two broad planar front facets are actual geometry, not a colour mask.
polygons=[
 [(-3.42,-2.50),(-1.28,-2.50),(-1.13,-1.68),(-1.22,-.12),(-2.39,-.10),(-3.39,-.04)],
 [(-1.23,-2.50),(1.12,-2.50),(1.20,-1.66),(1.14,-.11),(.28,-.13),(-1.18,-.10),(-1.10,-1.68)],
 [(1.18,-2.50),(3.42,-2.50),(3.43,-1.72),(3.39,-.08),(2.53,-.03),(1.19,-.12),(1.25,-1.67)],
 [(-3.40,-.02),(-2.41,-.04),(-1.23,-.06),(-1.08,.67),(-1.20,2.34),(-2.61,2.38),(-3.20,2.30),(-3.42,1.93)],
 [(-1.18,-.04),(.29,-.08),(1.15,-.06),(1.20,1.09),(1.13,2.33),(.45,2.38),(-1.15,2.34),(-1.03,.68)],
 [(1.21,-.06),(2.53,.02),(3.39,-.02),(3.42,1.91),(3.20,2.33),(2.21,2.35),(1.18,2.32),(1.25,1.09)],
]
stone_specs=[]
def thick_section(name,poly,index):
 cx=sum(p[0] for p in poly)/len(poly);cy=sum(p[1] for p in poly)/len(poly)
 inner=[]
 for i,(u,v) in enumerate(poly):
  width=.105+.035*((i+index*2)%4)
  d=Vector((cx-u,cy-v)).normalized()*width
  inner.append((u+d.x,v+d.y))
 # One oblique mineral cleavage crossing each front face; different phase/angle.
 slope=[.27,-.32,.18,-.22,.36,-.29][index];offset=cx+slope*cy+[.16,-.22,.20,-.18,.11,-.09][index]
 def side(p):return p[0]+slope*p[1]-offset
 def depth(p):
  d=side(p)
  return .30 + (.024*d if d<=0 else -.032*d) + .008*(index%2)
 rings=[]
 for i,p in enumerate(inner):
  q=inner[(i+1)%len(inner)];points=[p]
  if side(p)*side(q)<-1e-10:
   f=side(p)/(side(p)-side(q));points.append((p[0]+f*(q[0]-p[0]),p[1]+f*(q[1]-p[1])))
  rings.append(points)
 vertices=[];faces=[];mi=[];lookup={}
 def vertex(u,v,t):
  key=(round(u,8),round(v,8),round(t,8))
  if key not in lookup:lookup[key]=len(vertices);vertices.append(pos(u,v,t))
  return lookup[key]
 rear=[vertex(u,v,-.34) for u,v in poly]
 shoulder=[vertex(u,v,.10+.012*((i+index)%3)) for i,(u,v) in enumerate(poly)]
 faces.append(tuple(reversed(rear)));mi.append(0)
 for i in range(len(poly)):
  j=(i+1)%len(poly);faces.append((rear[i],rear[j],shoulder[j],shoulder[i]));mi.append(0)
  edge_points=rings[i]+[inner[j]]
  faces.append(tuple([shoulder[i],shoulder[j]]+[vertex(u,v,depth((u,v))) for u,v in reversed(edge_points)]));mi.append(1)
 def clip(sign):
  result=[]
  for i,p in enumerate(inner):
   q=inner[(i+1)%len(inner)];a=side(p)*sign;b=side(q)*sign
   if a>=-1e-9:result.append(p)
   if a*b<0:
    f=a/(a-b);result.append((p[0]+f*(q[0]-p[0]),p[1]+f*(q[1]-p[1])))
  return result
 for sign in [-1,1]:
  face=clip(sign);faces.append(tuple(vertex(u,v,depth((u,v))) for u,v in face));mi.append(0)
 ob=mesh(name,vertices,faces,[stone,edge],mi)
 stone_specs.append({'name':name,'back_depth':-.34,'front_peak':max(v.x for v in vertices),'front_facets':2,'edge_width_range':[.105,.21]})
 return ob
for i,poly in enumerate(polygons):thick_section('StoneMass_%02d'%i,poly,i)

def interpolate(controls,steps=6):
 samples=[]
 for k in range(len(controls)-1):
  p0=Vector(controls[max(0,k-1)][:3]);p1=Vector(controls[k][:3]);p2=Vector(controls[k+1][:3]);p3=Vector(controls[min(k+2,len(controls)-1)][:3])
  for j in range(steps):
   t=j/steps
   p=.5*((2*p1)+(-p0+p2)*t+(2*p0-5*p1+4*p2-p3)*t*t+(-p0+3*p1-3*p2+p3)*t*t*t)
   r=controls[k][3]*(1-t)+controls[k+1][3]*t;samples.append((p,r))
 samples.append((Vector(controls[-1][:3]),controls[-1][3]));return samples

root_specs=[]
def rooted_curve(name,controls,phase=0):
 # Measured first trial exceeded front envelope by 6.74mm. Translate only the
 # exposed front centreline 12mm inward; retain its full rounded cross-section.
 controls=[(u,v,t-.012 if t>.10 else t,r) for u,v,t,r in controls]
 samples=interpolate(controls);vertices=[];faces=[];count=16;previous_a=None
 for i,(local,radius) in enumerate(samples):
  p=pos(*local);before=pos(*samples[max(0,i-1)][0]);after=pos(*samples[min(len(samples)-1,i+1)][0]);tangent=(after-before).normalized()
  if previous_a is None:
   a=Vector((1,0,0))
   if abs(a.dot(tangent))>.9:a=Vector((0,0,1))
  else:a=previous_a
  a=(a-tangent*a.dot(tangent)).normalized();b=tangent.cross(a).normalized();previous_a=a
  for j in range(count):
   angle=math.tau*j/count;twist=phase+i*.027
   ridge=1+.10*math.sin(3*angle+twist)+.035*math.sin(5*angle-twist*.7)
   vertices.append(p+radius*ridge*(a*math.cos(angle)*.92+b*math.sin(angle)))
 for i in range(len(samples)-1):
  for j in range(count):faces.append((i*count+j,i*count+(j+1)%count,(i+1)*count+(j+1)%count,(i+1)*count+j))
 faces.extend([tuple(reversed(range(count))),tuple(range((len(samples)-1)*count,len(samples)*count))])
 ob=mesh(name,vertices,faces,[wood]);uv=ob.data.uv_layers.new(name='RootDetailUV');uv.active_render=True
 for poly in ob.data.polygons:
  for li in poly.loop_indices:
   vi=ob.data.loops[li].vertex_index;uv.data[li].uv=((vi%count)/count,(vi//count)/(len(samples)-1)*3)
  poly.use_smooth=True
 root_specs.append({'name':name,'controls_u_v_t_radius':controls,'section_minor_major_ratio':.92,'closed_caps':True})
 return ob

for side in [-1,1]:
 # A real front→top→back return and a second front→side bend are visible in 3D.
 controls=[(side*2.95,1.78,-.23,.11),(side*2.96,2.17,-.16,.18),(side*2.80,2.20,.05,.21),(side*2.66,1.98,.25,.21),(side*2.67,1.57,.27,.20),(side*2.92,1.06,.25,.225),(side*3.18,.60,.10,.19),(side*3.23,.23,.01,.18),(side*3.00,-.17,.26,.21),(side*2.66,-.63,.26,.22),(side*2.82,-1.15,.26,.20),(side*3.15,-1.70,.10,.19),(side*3.18,-2.08,-.02,.16),(side*3.10,-2.37,.02,.065)]
 if side>0:
  controls=[(u,v+(.06*math.sin(i*.73) if 1<i<12 else 0),t,r*(.95 if i>6 else 1)) for i,(u,v,t,r) in enumerate(controls)]
 rooted_curve('RootWrap_'+str(side),controls,side*.8)
 rooted_curve('RootForkUpper_'+str(side),[(side*2.91,1.08,.22,.13),(side*2.61,.86,.29,.14),(side*2.28,.75,.27,.10),(side*2.03,.54,.17,.025)],side)
 rooted_curve('RootForkLower_'+str(side),[(side*2.72,-.75,.22,.13),(side*2.44,-1.01,.29,.145),(side*2.29,-1.37,.26,.10),(side*2.39,-1.73,.15,.025)],side+1)

bpy.context.view_layer.update();parts=[o for o in root.children if o.type=='MESH']
checks=[]
def check(name,ok,detail=None):checks.append({'name':name,'pass':bool(ok),'detail':detail})
points=[o.matrix_world@v.co for o in parts for v in o.data.vertices]
bounds={'min':[min(p[k] for p in points) for k in range(3)],'max':[max(p[k] for p in points) for k in range(3)]}
part_bounds={o.name:{'min':[min((o.matrix_world@v.co)[k] for v in o.data.vertices) for k in range(3)],'max':[max((o.matrix_world@v.co)[k] for v in o.data.vertices) for k in range(3)]} for o in parts}
check('moving_envelope_1x5x7',all(bounds['min'][k]>=lo-1e-5 and bounds['max'][k]<=hi+1e-5 for k,(lo,hi) in enumerate([(-.5,.5),(-3.5,3.5),(-2.5,2.5)])),bounds)
for ob in parts:
 bm=bmesh.new();bm.from_mesh(ob.data)
 closed=all(e.is_manifold for e in bm.edges);volume=bm.calc_volume(signed=True)
 check(ob.name+'_closed_positive',closed and volume>0,{'boundary':sum(e.is_boundary for e in bm.edges),'nonmanifold':sum(not e.is_manifold for e in bm.edges),'signed_volume':volume});bm.free()
check('core_clamps_channels_and_markers_exact_P1',preserved=={name:digest(bpy.data.objects[name]) for name in preserved})
check('level_bottom_contact',abs(bounds['min'][2]+2.5)<1e-6 and (bpy.data.objects['BottomContact'].location-pos(0,-2.5,0)).length<1e-7)
check('readonly_inputs_unchanged',all(sha(ROOT/p)==value for p,value in input_hashes.items()))
check('no_voronoi_stone_colour',all(n.type!='TEX_VORONOI' for n in stone.node_tree.nodes))
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=12;scene.cycles.use_denoising=True;scene.render.threads_mode='FIXED';scene.render.threads=2
scene.render.resolution_x=1200;scene.render.resolution_y=960;scene.render.resolution_percentage=100
blend=HERE/'rising_seal_source_p2.blend';bpy.ops.wm.save_as_mainfile(filepath=str(blend))
report={'stage':'P2 first source/basic-material image; no atlas, GLB or game acceptance','input_hashes':input_hashes,'source_sha256':sha(blend),'bounds_blender':bounds,'bounds_godot':{'min':[bounds['min'][0],bounds['min'][2],-bounds['max'][1]],'max':[bounds['max'][0],bounds['max'][2],-bounds['min'][1]]},'part_bounds_blender':part_bounds,'parts':len(parts),'triangles':sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in parts),'stone_specs':stone_specs,'root_specs':root_specs,'preserved_hashes':preserved,'checks':checks,'passed':sum(c['pass'] for c in checks),'total':len(checks),'all_pass':all(c['pass'] for c in checks),'limits':['first source only; not final art','separate closed stone pieces overlap a continuous seam floor','full engine collision/movement/synchronization untested']}
(HERE/'source_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('RISING_SEAL_P2_SOURCE '+json.dumps({'passed':report['passed'],'total':report['total'],'triangles':report['triangles'],'bounds':bounds,'failures':[c for c in checks if not c['pass']]},ensure_ascii=False),flush=True)
assert report['all_pass'],'Stop on actual closed/envelope failure before render'
if '--render' in sys.argv:
 scene.render.filepath=str(HERE/'rising_seal_source_p2.png');bpy.ops.render.render(write_still=True)
print('RISING_SEAL_P2_DONE',flush=True)
