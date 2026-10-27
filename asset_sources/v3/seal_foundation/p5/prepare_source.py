"""Create the independent P5 script from frozen P3 review utilities.
No old file writes. All geometry-generating code is replaced, not re-run.
"""
from pathlib import Path
import json,struct,hashlib
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
s=(HERE.parent/'p3/build_foundation_p3.py').read_text(encoding='utf-8')
s=s.replace('P3 single natural belly + explicitly re-sculpted upper shoulder.','P5 one natural middle slice + two planar caps + invertible global Y stretch.')
s=s.replace("'P3_EditableFoundation'","'P5_EditableFoundation'").replace("'SealFoundationP3'","'SealFoundationP5'")
s=s.replace("'One source rock; upper shoulder deliberately re-sculpted, not unchanged photogrammetry.'","'One original rock middle slice, capped planar cuts and invertible global Y scaling; not original scan proportions.'")
s=s.replace("'FOUNDATION_P3_PID'","'FOUNDATION_P5_PID'")
s=s.replace("'Basic_CoolSculptedRock'","'Basic_CoolMiddleSliceRock'")
s=s.replace("frozen=[vendor,ref,gatefile,HERE.parent/'p2/seal_foundation_p2.blend',HERE.parent/'p1/seal_foundation_form_p1.blend']","frozen=[vendor,ref,gatefile,HERE.parent/'p2/seal_foundation_p2.blend',HERE.parent/'p1/seal_foundation_form_p1.blend',HERE.parent/'p3/seal_foundation_p3.blend',HERE.parent/'p4/assess_sections.py',HERE.parent/'p4/section_assessment.json',HERE.parent/'p4/README.md']")
a=s.index('# Initial rigid natural body:');b=s.index('# Intentionally architectural beam;')
s=s[:a]+'''# Original wide middle slice. No local vertex displacement/warping.
v=(np.array(native['vertices'])-native['centre'])@native['principal_basis_columns']
p=v[:,[2,1,0]];p[:,2]*=-1
scale=9.0/np.ptp(p[:,2]);p*=scale
p[:,0]-=(p[:,0].min()+p[:,0].max())/2
p[:,2]-=(p[:,2].min()+p[:,2].max())/2
p[:,1]-=p[:,1].min()
pre_rigid_bounds=[p.min(0).tolist(),p.max(0).tolist()]
H=float(np.ptp(p[:,1]));lower_y=H*.38;upper_y=H*.53;y_scale=5.65/(upper_y-lower_y)
rock=mesh_ob('MiddleSliceNaturalBody',[bp(q) for q in p],native['triangles']);rock.parent=root;rock.data.materials.append(rockmat)
rock['source']='Boulder 01 native LOD3';rock['source_uniform_scale']=float(scale)
rock['authored_change']='Two parallel cuts; globally stretched Y by '+str(y_scale)+'; four outer shoulder plane cuts. No local vertex warp.'
cuts=[]
def cut_plane(ob,name,co,no):
 bm=bmesh.new();bm.from_mesh(ob.data)
 result=bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),plane_co=bp(co),plane_no=bp(no),dist=1e-7,clear_outer=True)
 edges=[e for e in result['geom_cut'] if isinstance(e,bmesh.types.BMEdge) and e.is_boundary]
 if edges:bmesh.ops.holes_fill(bm,edges=edges,sides=0)
 bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bmesh.ops.triangulate(bm,faces=list(bm.faces));bm.to_mesh(ob.data);bm.free();ob.data.update()
 cuts.append({'name':name,'plane_point_godot_local':co,'outward_plane_normal_godot':no,'cut_boundary_edges_filled':len(edges)})
cut_plane(rock,'Lower middle slice cap',(0,lower_y,0),(0,-1,0))
cut_plane(rock,'Upper middle slice cap',(0,upper_y,0),(0,1,0))
for vert in rock.data.vertices:vert.co.z=(vert.co.z-lower_y)*y_scale
rock.data.update()
# Major inclined outer breaks, entirely outside the full architectural beam
# footprint; leave actual gate support uncut. No narrow repeated facet bands.
cut_plane(rock,'East wide sloping fracture',(0,6.4955,0),(.85,1,.05))
cut_plane(rock,'West asymmetric wide fracture',(0,6.40,0),(-.90,1,-.04))
cut_plane(rock,'Positive end shoulder',(0,5.65,3.80),(0,1,1.10))
cut_plane(rock,'Negative end shoulder',(0,5.65,-3.78),(0,1,-1.35))

''' +s[b:]
start=s.index('outline=[');end=s.index('\nverts=[];rings=[]',start)
s=s[:start]+"outline=[(-.65,-3.65),(.65,-3.65),(.65,2.50),(.35,3.65),(-.65,3.65)]"+s[end:]
s=s.replace("ck('sculpt_vertical_map_has_positive_local_derivative',jacobian_min>0,{'minimum_analytic_dyprime_dy':jacobian_min,'note':'continuous-map diagnostic; triangulated self intersections are checked separately'})","ck('global_y_map_is_invertible',y_scale>0,{'dyprime_dy':y_scale,'scope':'Global affine map, plus independent capped half-space cuts; not P3 local height-field warp.'})")
start=s.index('rect=[(-.65,-3.65)');end=s.index("actual=[{'x':x",start)
s=s[:start]+'''# Real gate bottom is a subset of this conservative, read-back rectangle.
# The full architectural outer edge is intentionally allowed a small cantilever.
rect=[(-.36000002,-3.42000008),(.12400001,-3.42000008),(.12400001,3.42000008),(-.36000002,3.42000008)]
containing=[i for i,r in enumerate(bearing['loops']) if r['closed'] and all(pip(p,r['points']) for p in rect)]
intersections=sum(strict_seg(a,b,c,d) for row in bearing['loops'] for a,b in zip(row['points'],row['points'][1:]+row['points'][:1]) for c,d in zip(rect,rect[1:]+rect[:1]))
extra_inside=[i for i,r in enumerate(bearing['loops']) if i not in containing and any(pip(p,rect) for p in r['points'])]
ck('actual_gate_bottom_full_rectangle_in_solid_rock',len(containing)==1 and intersections==0 and not extra_inside and bearing['all_nodes_degree_2'],{'containing_loops':containing,'boundary_crossings':intersections,'other_loops_inside_seat':extra_inside,'rectangle_xz':rect,'method':'Conservative rectangle contains the 28 actual bottom triangles; outer beam corners are NOT claimed fully supported.'})
support=[{'x':float(x),'z':float(z),'rock_y':ray_y(rt,x,z)} for x in np.linspace(-.36,.124,11) for z in np.linspace(-3.42,3.42,71)]
ck('actual_gate_rock_projection_dense_support',all(q['rock_y'] is not None and abs(q['rock_y']-5.65)<2e-5 for q in support),{'samples':len(support),'failures':[q for q in support if q['rock_y'] is None or abs(q['rock_y']-5.65)>=2e-5]})
# Explicit 0.1m beam-top margin, stronger than actual irregular gate footprint.
beam_margin=[ray_y(bt,float(x),float(z)) for x in np.linspace(-.46,.224,9) for z in np.linspace(-3.52,3.52,73)]
ck('beam_top_actual_gate_plus_0_1m_margin',all(y is not None and abs(y-6.1)<1e-5 for y in beam_margin),{'samples':len(beam_margin),'rectangle_xz':[[-.46,-3.52],[.224,3.52]]})
''' +s[end:]
# Top-plane section is taken just inside rock to avoid coplanar ambiguity.
s=s.replace('bearing=section_loops(rock,5.65)','bearing=section_loops(rock,5.65-1e-6)')
s=s.replace("nominal=[ray_y(bt,float(x),float(z)) for x in np.linspace(-.5,.5,9) for z in np.linspace(-3.5,3.5,71)]\nck('gate_nominal_1x7_continuous_flat_beam_top_samples',all(y is not None and abs(y-6.1)<1e-5 for y in nominal),{'samples':len(nominal),'min':min(y for y in nominal if y is not None),'max':max(y for y in nominal if y is not None)})", "# Previous nominal 1x7 peripheral rectangle is not the actual gate bottom; use the explicit actual-foot margin above.")
s=s.replace("'FoundationP3_ReviewWorld'","'FoundationP5_ReviewWorld'")
start=s.index('def frame(points,margin=1.16):');end=s.index('assetpoints=',start)
s=s[:start]+'''framing=[]
def frame(points,margin=1.22):
 from bpy_extras.object_utils import world_to_camera_view
 arr=np.array([tuple(p) for p in points]);focus=Vector(tuple((arr.min(0)+arr.max(0))/2));camera.location=focus+offset;camera.rotation_euler=(focus-camera.location).to_track_quat('-Z','Y').to_euler();bpy.context.view_layer.update()
 inv=camera.matrix_world.inverted();pr=[inv@Vector(tuple(p)) for p in arr]
 mn=Vector((min(v.x for v in pr),min(v.y for v in pr),0));mx=Vector((max(v.x for v in pr),max(v.y for v in pr),0))
 # Re-centre in camera projection, not only world AABB. Read actual camera frame
 # to avoid sensor-fit / orthographic-scale interpretation assumptions.
 camera.location+=camera.rotation_euler.to_quaternion()@((mn+mx)*.5)
 c.ortho_scale=1.0;bpy.context.view_layer.update();vf=c.view_frame(scene=scene)
 fw=max(v.x for v in vf)-min(v.x for v in vf);fh=max(v.y for v in vf)-min(v.y for v in vf)
 c.ortho_scale=max((mx.x-mn.x)/fw,(mx.y-mn.y)/fh)*margin;bpy.context.view_layer.update()
 uv=[world_to_camera_view(scene,camera,Vector(tuple(p))) for p in arr]
 bounds=[min(p.x for p in uv),min(p.y for p in uv),max(p.x for p in uv),max(p.y for p in uv)]
 assert min(bounds[:2])>.025 and max(bounds[2:])<.975,('Review image crop',bounds)
 framing.append({'image_index':len(framing),'point_count':len(points),'projected_normalised_bounds':bounds,'fully_inside':True})
''' +s[end:]
s=s.replace("frame(assetpoints+gatepoints,1.18)","frame(assetpoints+gatepoints,1.22)")
s=s.replace("frame(focuspoints,1.06)","frame(focuspoints+assetpoints+gatepoints,1.14)")
s=s.replace('for y in [-2.2,11]','for y in [-3.2,9]')
for name in ['seal_foundation_p3.blend','seal_foundation_p3_basic.png','seal_foundation_p3_gate_assembly.png','seal_foundation_p3_near_shore_context.png']:
 s=s.replace("HERE/'"+name+"'","HERE/'"+name.replace('_p3','_p5')+"'")
s=s.replace("'P3 single-form source study, no PBR, GLB, runtime integration or human-play evidence'","'P5 middle-slice source study, no PBR, GLB, runtime integration or human-play evidence'")
start=s.index("'sculpt':{");end=s.index(",'bounds_local'",start)
s=s[:start]+"'sculpt':{'method':'Two parallel cuts with filled caps, invertible GLOBAL Y scale, four large half-space shoulder cuts. NO local height-field vertex pull.','source_lower_cut_y':lower_y,'source_upper_cut_y':upper_y,'global_y_scale':y_scale,'not_original_scan_proportions':True,'plane_cuts':cuts}"+s[end:]
s=s.replace("'render_direction_godot':[32,39,32]","'render_direction_godot':[32,39,32],'framing':framing,'actual_gate_bottom_evidence':json.loads((HERE/'actual_gate_bottom_triangles.json').read_text())")
s=s.replace("print('P3_","print('P5_")
s+= "\nreport['framing']=framing;report['elapsed_total_s']=time.time()-start\n(HERE/'form_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\\n',encoding='utf-8')\n"
(HERE/'build_foundation_p5.py').write_text(s,encoding='utf-8')
compile(s,'build_foundation_p5.py','exec')
# Read the complete actual GLB bottom triangles, not only sparse vertices.
p=ROOT/'assets/v3/candidates/rising_seal_p3/rising_seal_p3.glb';b=p.read_bytes();n=struct.unpack_from('<I',b,12)[0];g=json.loads(b[20:20+n]);binary=b[28+n:]
def accessor(i):
 a=g['accessors'][i];v=g['bufferViews'][a['bufferView']];width={'VEC3':3,'SCALAR':1}[a['type']];fmt={5126:'f',5125:'I',5123:'H',5121:'B'}[a['componentType']];size=struct.calcsize('<'+fmt*width);off=v.get('byteOffset',0)+a.get('byteOffset',0);stride=v.get('byteStride',size)
 return [struct.unpack_from('<'+fmt*width,binary,off+j*stride) for j in range(a['count'])]
triangles=[];parents={c:i for i,n in enumerate(g['nodes']) for c in n.get('children',[])}
for ni,nd in enumerate(g['nodes']):
 if 'mesh' not in nd:continue
 j=ni
 while True:
  a=g['nodes'][j]
  assert a.get('translation',[0,0,0])==[0,0,0] and a.get('rotation',[0,0,0,1])==[0,0,0,1] and a.get('scale',[1,1,1])==[1,1,1] and 'matrix' not in a
  if j not in parents:break
  j=parents[j]
 for pr in g['meshes'][nd['mesh']]['primitives']:
  vv=accessor(pr['attributes']['POSITION']);ii=[j[0] for j in accessor(pr['indices'])]
  for j in range(0,len(ii),3):
   t=[vv[k] for k in ii[j:j+3]]
   if all(abs(v[1]+2.5)<1e-6 for v in t):triangles.append(t)
assert len(triangles)==28
(HERE/'actual_gate_bottom_triangles.json').write_text(json.dumps({'glb':str(p),'sha256':hashlib.sha256(b).hexdigest(),'bottom_y':-2.5,'triangle_count':len(triangles),'triangles':triangles},indent=2),encoding='utf-8')
print('P5 script statically compiled; actual bottom triangles',len(triangles))
