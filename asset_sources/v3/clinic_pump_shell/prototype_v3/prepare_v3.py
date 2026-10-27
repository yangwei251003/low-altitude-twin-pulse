"""Prepare V3 only; no Blender launch. Frozen V1/V2 and atlas remain read-only."""
from pathlib import Path
import ast,hashlib,json,math
HERE=Path(__file__).resolve().parent;OLD=HERE.parent/'prototype_v2'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
for old in [HERE.parent/'prototype_v1',OLD]:
 m=json.loads((old/'manifest.json').read_text(encoding='utf-8'))
 for x in m['files']:assert sha(old/x['path'])==x['sha256'],x['path']
s=(OLD/'build_prototype.py').read_text(encoding='utf-8')
s=s.replace('V2 local joint construction and cause-based wear','V3 explicit metre-scale local masks; frozen V2 geometry')
s=s.replace('import bpy,bmesh,sys,json,hashlib,math,time,os,shutil','import bpy,bmesh,sys,json,hashlib,math,time,os,shutil,struct')

placement=r'''
def explicit_patches(name,gn):
 # Centre along longest face axis, total span, inward depth, selected edge 0/1.
 # No world-wide random colour. These locations correspond to actual joints.
 zero=(0.,0.,0.,0.)
 if name=='RoofBatten_1' and gn.y>.9:return (.50,.65,.075,0),(7.92,.38,.06,1)
 if name=='RoofBatten_2' and gn.y>.9:return (7.8,.58,.085,0),zero
 if name=='RoofJointPlate_1_1' and gn.y>.9:return (.24,.14,.06,1),zero
 if name=='RoofContinuousCore':
  if gn.z>.9:return (3.60,.46,.065,1),(7.10,.32,.08,1)
  if gn.x>.9:return (5.50,.56,.07,1),zero
  if gn.z<-.9:return (2.20,.41,.06,1),zero
 if name=='PumpSouthWestJamb_Upright_1' and gn.z>.9:return (2.17,.36,.06,0),(.28,.35,.065,1)
 if name=='PumpSouthEastJamb_Upright_0' and gn.z>.9:return (2.26,.30,.07,1),zero
 if name=='PumpEastWall_Upright_2' and gn.x>.9:return (2.04,.46,.065,0),zero
 # Concrete patches: centre, total width, maximum rise; fourth channel unused.
 if name=='PumpEastWall_Foot' and gn.x>.9:return (1.15,1.25,.24,0),(6.7,.72,.30,0)
 if name=='PumpSouthWestJamb_Foot' and gn.z>.9:return (.70,.82,.22,0),zero
 if name=='PumpSouthEastJamb_Foot' and gn.z>.9:return (2.50,.64,.27,0),zero
 if name=='PumpNorthWall_Foot' and gn.z<-.9:return (2.2,1.1,.25,0),(8.2,.65,.20,0)
 if name=='PumpWestWall_Foot' and gn.x<-.9:return (4.3,1.0,.24,0),zero
 return zero,zero

def explicit_streak(name,exterior):
 # Actual top fasteners, not arbitrary image-space spots. Full width 4–7cm.
 entries={'PumpSouthWestJamb_Panel_0_0':(1,0,.65,.065),
          'PumpSouthEastJamb_Panel_0_0':(0,1,.45,.055),
          'PumpEastWall_Panel_0_1':(0,1,.72,.07),
          'PumpEastWall_Panel_2_1':(1,0,.51,.045),
          'PumpWestWall_Panel_1_1':(1,0,.57,.06),
          'PumpNorthWall_Panel_1_1':(0,1,.41,.05)}
 return entries.get(name,(0,0,.5,.05)) if exterior else (0,0,.5,.05)

def geometry_digest(objects):
 dg=bpy.context.evaluated_depsgraph_get();h=hashlib.sha256();rows=[]
 for o in sorted(objects,key=lambda v:v.name):
  me=bpy.data.meshes.new_from_object(o.evaluated_get(dg),preserve_all_data_layers=True,depsgraph=dg);me.transform(o.matrix_world);me.calc_loop_triangles()
  h.update(o.name.encode('utf-8')+b'\0')
  for v in me.vertices:h.update(struct.pack('<3f',*v.co))
  for t in me.loop_triangles:h.update(struct.pack('<3I',*t.vertices))
  rows.append({'name':o.name,'vertices':len(me.vertices),'triangles':len(me.loop_triangles)})
  bpy.data.meshes.remove(me)
 return {'sha256':h.hexdigest(),'parts':rows}

def read_frozen_v2():
 path=HERE.parent/'prototype_v2/pump_shell_prototype.blend'
 assert sha(path)=='7cffd4cc2df7797f40d315f615ea224bef9f0730a44a6ade4b1c886a50c5d19c'
 bpy.ops.wm.open_mainfile(filepath=str(path));bpy.context.view_layer.update()
 reps=[]
 for name,axis,sign,size,role in [('RoofBatten_1',1,1,(.24,8.5),(1,0,0,0)),('PumpSouthWestJamb_Panel_0_0',2,1,(2.98,2.25),(0,0,0,0)),('PumpEastWall_Foot',0,1,(8,.35),(0,0,1,0))]:
  o=bpy.data.objects[name];me=o.data;p=next(p for p in me.polygons if gp(p.normal)[axis]*sign>.9)
  li=p.loop_indices[0];fs=tuple(me.color_attributes['FaceSize'].data[li].color);su=tuple(me.color_attributes['SurfaceUse'].data[li].color);wc=tuple(me.color_attributes['WearControl'].data[li].color)
  assert all(abs(fs[j]-size[j])<2e-6 for j in range(2)),(name,fs)
  assert all(abs(su[j]-role[j])<2e-6 for j in range(4)),(name,su)
  reps.append({'object':name,'face_size':fs,'surface_use':su,'wear_control':wc})
 materials=[]
 for m in bpy.data.materials:
  if not m.use_nodes or not m.name.startswith('PS_'):continue
  layers=[n.layer_name for n in m.node_tree.nodes if n.type=='VERTEX_COLOR']
  assert 'FaceSize' in layers and 'SurfaceUse' in layers
  for n in m.node_tree.nodes:
   if n.type=='VERTEX_COLOR' and n.layer_name in ['FaceSize','SurfaceUse']:
    assert n.outputs['Color'].is_linked,(m.name,n.layer_name)
  materials.append({'name':m.name,'linked_attribute_layers':layers})
 return {'blend_sha256':sha(path),'geometry':geometry_digest([o for o in bpy.data.objects if o.get('editable_piece')]),'actual_blender_attributes':reps,'actual_linked_material_attributes':materials,'limits':'Data/link readback, not proof of visual adequacy.'}

'''
needle='def material(name,image,region,scale,roughness,metallic,weather=False,tint=None,calm=None):'
s=s.replace(needle,placement+needle)
start=s.index('  # Actual selected panel bolts:')
end=s.index('\n # All additional wear',start)
s=s[:start]+r'''  # Blue length and Alpha full width come from the SIX explicit real fasteners.
  dist=mul(sub(.92,v),sz.outputs['Green'])
  active=mul(op('GREATER_THAN',dist,0),op('LESS_THAN',dist,cs.outputs['Blue']))
  grain=n.new('ShaderNodeTexNoise');grain.inputs['Scale'].default_value=7;grain.inputs['Detail'].default_value=1;lk.new(metric.outputs['UV'],grain.inputs['Vector'])
  wobble=mul(sub(grain.outputs['Fac'],.5),.006)
  taper=op('MAXIMUM',0,sub(1,op('DIVIDE',dist,cs.outputs['Blue'])))
  halfwidth=mul(mul(control.outputs['Alpha'],.5),add(.62,mul(taper,.38)))
  left=op('POWER',op('MAXIMUM',0,sub(1,op('DIVIDE',op('ABSOLUTE',sub(mul(sub(u,.045),sz.outputs['Red']),wobble)),halfwidth))),.35)
  right=op('POWER',op('MAXIMUM',0,sub(1,op('DIVIDE',op('ABSOLUTE',add(mul(sub(u,.955),sz.outputs['Red']),wobble)),halfwidth))),.35)
  mask=mul(mul(active,op('POWER',taper,.55)),mul(add(mul(left,cs.outputs['Red']),mul(right,cs.outputs['Green'])),.85))
  mix=n.new('ShaderNodeMixRGB');lk.new(mask,mix.inputs[0]);lk.new(base,mix.inputs[1]);mix.inputs[2].default_value=(.12,.061,.026,1);base=mix.outputs[0]
''' +s[end:]
start=s.index(" if name=='PS_Teal':")
end=s.index("  # Connection plates have actual",start)
s=s[:start]+r''' if name=='PS_Teal':
  # Local 6–9cm edge loss, not a thin random outline around every profile.
  xu=mul(u,sz.outputs['Red']);xv=mul(v,sz.outputs['Green'])
  long_is_u=op('GREATER_THAN',sz.outputs['Red'],sz.outputs['Green'])
  along=add(mul(xu,long_is_u),mul(xv,sub(1,long_is_u)))
  across=add(mul(xv,long_is_u),mul(xu,sub(1,long_is_u)))
  crossmax=op('MINIMUM',sz.outputs['Red'],sz.outputs['Green'])
  chipped=0
  for key in ['WearPatchA','WearPatchB']:
   va=n.new('ShaderNodeVertexColor');va.layer_name=key;sp=n.new('ShaderNodeSeparateColor');lk.new(va.outputs['Color'],sp.inputs[0])
   centre,span,depth=sp.outputs['Red'],sp.outputs['Green'],sp.outputs['Blue']
   enabled=op('GREATER_THAN',span,.001)
   longitudinal=op('POWER',op('MAXIMUM',0,sub(1,op('DIVIDE',op('ABSOLUTE',sub(along,centre)),op('MAXIMUM',mul(span,.5),.001)))),.23)
   edgedist=add(mul(across,sub(1,va.outputs['Alpha'])),mul(sub(crossmax,across),va.outputs['Alpha']))
   raggeddepth=mul(depth,add(.78,mul(low.outputs['Fac'],.22)))
   inward=op('POWER',op('MAXIMUM',0,sub(1,op('DIVIDE',edgedist,op('MAXIMUM',raggeddepth,.001)))),.32)
   # One 5cm missing bite per broad fragment, avoiding rectangular ends.
   notch=mul(op('LESS_THAN',op('ABSOLUTE',sub(along,add(centre,.085))),.025),op('GREATER_THAN',edgedist,mul(depth,.35)))
   fragment=mul(enabled,mul(longitudinal,mul(inward,sub(1,notch))))
   chipped=op('MAXIMUM',chipped,mul(use.outputs['Red'],fragment))
  base=tint_mask(base,mul(chipped,.84),(.31,.265,.195),'Selected 6–9cm interrupted edge chips at actual corners')
  mask=op('MAXIMUM',mask,mul(chipped,.72))
''' +s[end:]
start=s.index(" elif name=='PS_Concrete':")
end=s.index(" bs=n.new('ShaderNodeBsdfPrincipled')",start)
s=s[:start]+r''' elif name=='PS_Concrete':
  # Explicit separated exterior-foot patches; no full-length dirty stripe.
  along=mul(u,sz.outputs['Red']);height=mul(v,sz.outputs['Green']);damp=0
  for key in ['WearPatchA','WearPatchB']:
   va=n.new('ShaderNodeVertexColor');va.layer_name=key;sp=n.new('ShaderNodeSeparateColor');lk.new(va.outputs['Color'],sp.inputs[0])
   centre,span,rise=sp.outputs['Red'],sp.outputs['Green'],sp.outputs['Blue']
   enabled=op('GREATER_THAN',span,.001)
   lateral=op('POWER',op('MAXIMUM',0,sub(1,op('DIVIDE',op('ABSOLUTE',sub(along,centre)),op('MAXIMUM',mul(span,.5),.001)))),.38)
   wetheight=mul(rise,add(.65,mul(low.outputs['Fac'],.35)))
   vertical=op('POWER',op('MAXIMUM',0,sub(1,op('DIVIDE',height,op('MAXIMUM',wetheight,.001)))),.6)
   damp=op('MAXIMUM',damp,mul(use.outputs['Blue'],mul(enabled,mul(lateral,vertical))))
  base=tint_mask(base,mul(damp,.62),(.105,.12,.115),'Sparse large foot patches with quiet gaps')
  mask=op('MAXIMUM',mask,mul(damp,.6))
 # Named actual mask output. Optional diagnostic reconnects this to emission;
 # no image editing and no dependency on changing compositor APIs.
 probe=n.new('ShaderNodeMath');probe.operation='MULTIPLY';probe.name='V3_EvaluatedWeatherMask';inp(mask,probe.inputs[0]);probe.inputs[1].default_value=1
''' +s[end:]
needle=" me.color_attributes.new(name='FaceSize',type='FLOAT_COLOR',domain='CORNER');me.color_attributes.new(name='SurfaceUse',type='FLOAT_COLOR',domain='CORNER')"
s=s.replace(needle,needle+"\n me.color_attributes.new(name='WearPatchA',type='FLOAT_COLOR',domain='CORNER');me.color_attributes.new(name='WearPatchB',type='FLOAT_COLOR',domain='CORNER')")
needle="surface=me.color_attributes['SurfaceUse'];key="
s=s.replace(needle,"surface=me.color_attributes['SurfaceUse'];patch_a=me.color_attributes['WearPatchA'];patch_b=me.color_attributes['WearPatchB'];key=")
needle="   wear.data[li].color=(1.0 if exterior and seed%3==0 else 0.,1.0 if exterior and seed%4==1 else 0.,.38+.17*(seed%3),1);phase.data[li].color=phase_uv"
s=s.replace(needle,"   wear.data[li].color=explicit_streak(o.name,exterior);phase.data[li].color=phase_uv\n   patch_a.data[li].color,patch_b.data[li].color=explicit_patches(o.name,gn)")
s=s.replace("frame_face=finish=='Teal' and (exterior or roof_top)","frame_face=finish=='Teal' and (exterior or roof_top or (o.name=='RoofContinuousCore' and abs(gn.y)<.1))")
s=s.replace(" scene=bpy.context.scene;scene.render.engine='CYCLES'", " scene=bpy.context.scene;scene.render.engine='CYCLES'")
needle=" start=time.time();assert not (HERE/'pump_shell_prototype.blend').exists(),'Preserve previous run first.'"
s=s.replace(needle,needle+"\n baseline=read_frozen_v2()")
needle=" build(plan);bpy.context.view_layer.update();report=inspect(plan)"
s=s.replace(needle,needle+"\n new_geometry=geometry_digest(PARTS);assert new_geometry['sha256']==baseline['geometry']['sha256'],'V3 material-only revision must not change evaluated V2 geometry'\n (HERE/'evidence/v2_blender_attribute_and_geometry_readback.json').write_text(json.dumps(baseline,ensure_ascii=False,indent=2)+'\\n',encoding='utf-8')\n report['v2_geometry_exact_match']=True;report['geometry_sha256']=new_geometry['sha256']")
s=s.replace("revision='V2 physical joint plates and localized purpose-based weathering; same seven collision bounds'","revision='V3 material-only: explicit broad local chips, six fastener streaks, separated foot wet patches; exact V2 geometry'")
needle=" report.update(status='SOURCE_RENDERED_PENDING_ACTUAL_VISUAL_REVIEW'"
diagnostic=r''' if '--mask-diagnostic' in sys.argv:
  # Diagnostic only, after the source is saved and beauty images completed.
  # Never resave this emission-only state into editable production source.
  for o in bpy.data.objects:
   if o.get('editable_piece'):o.hide_render=False
  for m in bpy.data.materials:
   if not m.use_nodes or not m.name.startswith('PS_'):continue
   n=m.node_tree.nodes;lk=m.node_tree.links;output=next(q for q in n if q.type=='OUTPUT_MATERIAL')
   emission=n.new('ShaderNodeEmission');lk.new(n['V3_EvaluatedWeatherMask'].outputs[0],emission.inputs['Color']);emission.inputs['Strength'].default_value=1;lk.new(emission.outputs[0],output.inputs['Surface'])
  scene.cycles.samples=4;scene.view_settings.view_transform='Standard';scene.view_settings.exposure=0
  scene.render.filepath=str(HERE/'evidence/pump_shell_purpose_mask.png');bpy.ops.render.render(write_still=True)
  report['optional_shader_mask_diagnostic']={'path':scene.render.filepath,'sha256':sha(Path(scene.render.filepath)),'scope':'Actual shader mask emission-only diagnostic, NOT a material appearance or game image; source was not resaved.'}
'''
s=s.replace(needle,diagnostic+needle)
ast.parse(s);(HERE/'build_prototype.py').write_text(s,encoding='utf-8')

r=(OLD/'run_preview.py').read_text(encoding='utf-8')
a=r.index("old=HERE.parent/'prototype_v1'");b=r.index('start=time.time()',a)
r=r[:a]+"""olds=[HERE.parent/'prototype_v1',HERE.parent/'prototype_v2']
manifests=[json.loads((old/'manifest.json').read_text(encoding='utf-8')) for old in olds]
def assert_frozen():
 for old,manifest in zip(olds,manifests):
  for item in manifest['files']:
   assert hashlib.sha256((old/item['path']).read_bytes()).hexdigest()==item['sha256'],str(old/item['path'])
assert_frozen()
"""+r[b:]
r=r.replace("v1_frozen_files_verified=len(manifest['files'])","v1_v2_frozen_files_verified=sum(len(m['files']) for m in manifests)")
r=r.replace('import subprocess,json,time,hashlib','import subprocess,json,time,hashlib,sys')
r=r.replace("str(HERE/'build_prototype.py')],cwd=", "str(HERE/'build_prototype.py')]+(['--','--mask-diagnostic'] if '--mask-diagnostic' in sys.argv else []),cwd=")
ast.parse(r);(HERE/'run_preview.py').write_text(r,encoding='utf-8')
c=json.loads((OLD/'input_config.json').read_text(encoding='utf-8'));c.update(status='PREPARED_WAIT_ROOT_CPU_WINDOW',revision='V3 measured material mask revision',v2_manifest_sha256=sha(OLD/'manifest.json'))
(HERE/'input_config.json').write_text(json.dumps(c,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

# Pure projection estimate. This is not rasterized GPU evidence.
direction=(32,39,32);length=math.sqrt(sum(x*x for x in direction));forward=[x/length for x in direction]
foreshorten=[math.sqrt(1-x*x) for x in forward]
ppm=720/26
projection={'basis':'Production OFFSET(32,39,32), 1280x720, orthographic size26, default KEEP_HEIGHT1; no engine run','pixels_per_m_unforeshortened':ppm,'axis_foreshortening_xyz':foreshorten,'old_edge_8_to_33mm_projected_px':[.008*ppm*foreshorten[0],.033*ppm*foreshorten[0]],'new_edge_6_to_9cm_projected_px':[.06*ppm*foreshorten[0],.09*ppm*foreshorten[0]],'new_streak_full_4_to_7cm_projected_px':[.04*ppm*foreshorten[0],.07*ppm*foreshorten[0]],'new_streak_length_45_to_72cm_projected_px':[.45*ppm*foreshorten[1],.72*ppm*foreshorten[1]],'foot_patch_width_72_to_125cm_projected_px':[.72*ppm*foreshorten[2],1.25*ppm*foreshorten[2]],'foot_patch_rise_24_to_30cm_projected_px':[.24*ppm*foreshorten[1],.30*ppm*foreshorten[1]],'limits':'Approximate length projections, not shader coverage or antialiasing/readability acceptance. Full contrast-core can be narrower than mathematical support.'}
(HERE/'projection_estimate.json').write_text(json.dumps(projection,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'prepared':str(HERE),'ast_valid':True,'no_blender_launched':True,'projection':projection},ensure_ascii=False))
