"""Bounded V2 source preparation. Reads frozen V1; writes only this directory."""
from pathlib import Path
import hashlib,json,ast

HERE=Path(__file__).resolve().parent
OLD=HERE.parent/'prototype_v1'
def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
manifest=json.loads((OLD/'manifest.json').read_text(encoding='utf-8'))
for entry in manifest['files']:
    assert sha(OLD/entry['path'])==entry['sha256'],entry['path']
s=(OLD/'build_prototype.py').read_text(encoding='utf-8')
s=s.replace('Prepared source-only prototype. Requires root-approved atlas + CPU2 window.','V2 local joint construction and cause-based wear; source-only. CPU2 window required.')
s=s.replace("ORIGIN=Vector((-7,0,8));PARTS=[];GROUPS={};MATERIALS={}","ORIGIN=Vector((-7,0,8));PARTS=[];GROUPS={};MATERIALS={};V2_JOINTS=[]")

# Explicit metric sizes and face-purpose masks survive evaluated geometry;
# they do not depend on an object's Generated coordinate changing after join.
needle=" phase=n.new('ShaderNodeVertexColor');phase.layer_name='UVPhase';ph=n.new('ShaderNodeSeparateColor');lk.new(phase.outputs['Color'],ph.inputs[0])"
s=s.replace(needle,needle+"\n sizes=n.new('ShaderNodeVertexColor');sizes.layer_name='FaceSize';sz=n.new('ShaderNodeSeparateColor');lk.new(sizes.outputs['Color'],sz.inputs[0])\n purpose=n.new('ShaderNodeVertexColor');purpose.layer_name='SurfaceUse';use=n.new('ShaderNodeSeparateColor');lk.new(purpose.outputs['Color'],use.inputs[0])")
old="""  # Actual panel bolts are at normalized u=.045/.955, v=.92; masks run down.
  dist=sub(.92,v);active=mul(op('GREATER_THAN',dist,0),op('LESS_THAN',dist,cs.outputs['Blue']))
  left=op('MAXIMUM',0,sub(1,op('DIVIDE',op('ABSOLUTE',sub(u,add(.045,mul(dist,.008)))),.012)))
  right=op('MAXIMUM',0,sub(1,op('DIVIDE',op('ABSOLUTE',sub(u,sub(.955,mul(dist,.006)))),.009)))
  taper=op('MAXIMUM',0,sub(1,op('DIVIDE',dist,cs.outputs['Blue'])))
  mask=mul(mul(active,taper),mul(add(mul(left,cs.outputs['Red']),mul(right,cs.outputs['Green'])),.34))
  mix=n.new('ShaderNodeMixRGB');lk.new(mask,mix.inputs[0]);lk.new(base,mix.inputs[1]);mix.inputs[2].default_value=(.085,.043,.019,1);base=mix.outputs[0]
"""
new="""  # Actual selected panel bolts: u=.045/.955, v=.92. Physical length in m.
  dist=mul(sub(.92,v),sz.outputs['Green'])
  active=mul(op('GREATER_THAN',dist,0),op('LESS_THAN',dist,cs.outputs['Blue']))
  grain=n.new('ShaderNodeTexNoise');grain.inputs['Scale'].default_value=19;grain.inputs['Detail'].default_value=1.3;lk.new(metric.outputs['UV'],grain.inputs['Vector'])
  wobble=mul(sub(grain.outputs['Fac'],.5),.009)
  taper=op('MAXIMUM',0,sub(1,op('DIVIDE',dist,cs.outputs['Blue'])))
  width=mul(add(.012,mul(taper,.026)),add(.45,mul(grain.outputs['Fac'],1.0)))
  left=op('MAXIMUM',0,sub(1,op('DIVIDE',op('ABSOLUTE',sub(mul(sub(u,.045),sz.outputs['Red']),wobble)),width)))
  right=op('MAXIMUM',0,sub(1,op('DIVIDE',op('ABSOLUTE',add(mul(sub(u,.955),sz.outputs['Red']),wobble)),mul(width,.73))))
  mask=mul(mul(active,taper),mul(add(mul(left,cs.outputs['Red']),mul(right,cs.outputs['Green'])),.70))
  mix=n.new('ShaderNodeMixRGB');lk.new(mask,mix.inputs[0]);lk.new(base,mix.inputs[1]);mix.inputs[2].default_value=(.12,.061,.026,1);base=mix.outputs[0]
"""
assert old in s;s=s.replace(old,new)
weather="""
 # All additional wear is restricted to a real surface purpose or edge.
 # V2 never changes the atlas pixels and never puts overall noise in base color.
 edgeu=mul(op('MINIMUM',u,sub(1,u)),sz.outputs['Red'])
 edgev=mul(op('MINIMUM',v,sub(1,v)),sz.outputs['Green'])
 edge=op('MINIMUM',edgeu,edgev)
 low=n.new('ShaderNodeTexNoise');low.inputs['Scale'].default_value=3.2;low.inputs['Detail'].default_value=1;lk.new(metric.outputs['UV'],low.inputs['Vector'])
 chips=n.new('ShaderNodeTexNoise');chips.inputs['Scale'].default_value=34;chips.inputs['Detail'].default_value=1.5;lk.new(metric.outputs['UV'],chips.inputs['Vector'])
 def tint_mask(current,factor,color,label):
  q=n.new('ShaderNodeMixRGB');q.label=label;inp(factor,q.inputs[0]);lk.new(current,q.inputs[1]);q.inputs[2].default_value=(*color,1);return q.outputs[0]
 if name=='PS_Teal':
  # 10-30mm broken exposed paint edges. Sparse broad islands, not a tiled patina.
  edgewidth=add(.008,mul(chips.outputs['Fac'],.025))
  edgefade=op('MAXIMUM',0,sub(1,op('DIVIDE',edge,edgewidth)))
  broken=op('MINIMUM',1,op('MAXIMUM',0,mul(sub(low.outputs['Fac'],.40),4.2)))
  chipped=mul(use.outputs['Red'],mul(edgefade,mul(broken,op('GREATER_THAN',chips.outputs['Fac'],.32))))
  base=tint_mask(base,mul(chipped,.72),(.28,.245,.19),'Broken bare edges at real metal profile boundary')
  mask=op('MAXIMUM',mask,mul(chipped,.44))
  # Connection plates have actual paired fasteners, 0.16m between centres.
  # Alpha purpose channel marks TOP of these plates only.
  hx=mul(sub(u,.5),sz.outputs['Red']);hy=mul(sub(v,.5),sz.outputs['Green'])
  nearleft=op('SQRT',add(op('POWER',add(hx,.08),2),op('POWER',hy,2)))
  nearright=op('SQRT',add(op('POWER',sub(hx,.08),2),op('POWER',hy,2)))
  rootdist=op('MINIMUM',nearleft,nearright)
  boltroot=mul(purpose.outputs['Alpha'],mul(op('MAXIMUM',0,sub(1,op('DIVIDE',rootdist,.072))),add(.45,mul(chips.outputs['Fac'],.55))))
  base=tint_mask(base,mul(boltroot,.62),(.14,.072,.03),'Oxide at actual paired hex-head roots')
  mask=op('MAXIMUM',mask,mul(boltroot,.3))
 elif name=='PS_Zinc':
  # Roof margins: 60-170mm irregular low contrast salt and settled dust.
  width=add(.065,mul(low.outputs['Fac'],.105))
  rim=mul(use.outputs['Green'],mul(op('MAXIMUM',0,sub(1,op('DIVIDE',edge,width))),add(.27,mul(chips.outputs['Fac'],.37))))
  base=tint_mask(base,rim,(.40,.395,.35),'Salt concentrated beside roof seams; broad centre left quiet')
  mask=op('MAXIMUM',mask,mul(rim,.38))
 elif name=='PS_Concrete':
  # Only exterior wall foot: no dirty band on floor/inside potable-work area.
  height=mul(v,sz.outputs['Green'])
  dampheight=add(.08,mul(low.outputs['Fac'],.26))
  heightfade=op('MAXIMUM',0,sub(1,op('DIVIDE',height,dampheight)))
  patches=op('MINIMUM',1,op('MAXIMUM',0,mul(sub(low.outputs['Fac'],.36),3.5)))
  damp=mul(use.outputs['Blue'],mul(heightfade,mul(patches,.61)))
  base=tint_mask(base,damp,(.11,.12,.115),'Interrupted wall-foot damp patches, no continuous black plinth')
  mask=op('MAXIMUM',mask,mul(damp,.35))
"""
needle=" bs=n.new('ShaderNodeBsdfPrincipled');bs.name='PumpPrincipled';"
assert needle in s;s=s.replace(needle,weather+needle)

needle=" wear=me.color_attributes['WearControl'];phase=me.color_attributes['UVPhase'];key="
repl=" me.color_attributes.new(name='FaceSize',type='FLOAT_COLOR',domain='CORNER');me.color_attributes.new(name='SurfaceUse',type='FLOAT_COLOR',domain='CORNER')\n wear=me.color_attributes['WearControl'];phase=me.color_attributes['UVPhase'];sizes=me.color_attributes['FaceSize'];surface=me.color_attributes['SurfaceUse'];key="
assert needle in s;s=s.replace(needle,repl)
needle="   wear.data[li].color=(1.0 if exterior and seed%3==0 else 0.,1.0 if exterior and seed%4==1 else 0.,.26+.065*(seed%3),1);phase.data[li].color=phase_uv"
repl="""   wear.data[li].color=(1.0 if exterior and seed%3==0 else 0.,1.0 if exterior and seed%4==1 else 0.,.38+.17*(seed%3),1);phase.data[li].color=phase_uv
   sizes.data[li].color=(bb[1][axes[0]]-bb[0][axes[0]],bb[1][axes[1]]-bb[0][axes[1]],0,1)
   roof_top=source_id=='PumpRoof' and gn.y>.9
   frame_face=finish=='Teal' and (exterior or roof_top)
   surface.data[li].color=(float(frame_face),float(roof_top and o.name.startswith('RoofZincPanel')),float(exterior and o.name.endswith('_Foot')),float(roof_top and o.name.startswith('RoofJointPlate')))
"""
assert needle in s;s=s.replace(needle,repl)
# Larger hex heads only at the eight real roof connections; panel fasteners retain V1.
s=s.replace('def bolt(name,centre,normal,source,group,radius=.034):','def bolt(name,centre,normal,source,group,radius=.034,count=10,depth=.010):')
s=s.replace('u.normalize();v=n.cross(u);depth=.010;count=10','u.normalize();v=n.cross(u)')
s=s.replace(" o=bpy.data.objects.new(name,me);bpy.context.scene.collection.objects.link(o);return register(o,source,group,'Zinc')", " o=bpy.data.objects.new(name,me);bpy.context.scene.collection.objects.link(o);o['head_sides']=count;o['head_diameter_m']=radius*2;return register(o,source,group,'Zinc')")
needle="  for z in [lo[2]+.13,hi[2]-.13]:bolt('RoofBattenBolt_%d_%.2f'%(i,z),[(a+b)/2,3.495,z],[0,1,0],'PumpRoof','RoofCover',.042)"
repl="""  # 14mm connection caps seat across the panel/batten meeting point.
  # The two 70mm hex heads are contained at Y<=3.5, not new roof obstacles.
  cx=min(hi[0]-.18,max(lo[0]+.18,x))
  for j,z in enumerate([lo[2]+.18,hi[2]-.18]):
   plate=box('RoofJointPlate_%d_%d'%(i,j),[cx-.18,3.478,z-.16],[cx+.18,3.492,z+.16],'PumpRoof','RoofCover','Teal',.002)
   for k,dx in enumerate([-.08,.08]):bolt('RoofJointHex_%d_%d_%d'%(i,j,k),[cx+dx,3.496,z],[0,1,0],'PumpRoof','RoofCover',.035,count=6,depth=.008)
   V2_JOINTS.append({'plate':plate.name,'centre_world':[cx,3.485,z],'plate_size_m':[.36,.014,.32],'heads':2,'head_diameter_m':.07,'head_top_world_y':3.5})
"""
assert needle in s;s=s.replace(needle,repl)
needle=" check('no fabricated threshold beyond floor Z12',hit is None)"
s=s.replace(needle,needle+"\n check('eight actual connection caps and sixteen paired 70mm hex heads',len(V2_JOINTS)==8 and sum(o.name.startswith('RoofJointHex') and o.get('head_sides')==6 and abs(o.get('head_diameter_m',0)-.07)<1e-9 for o in PARTS)==16)\n check('localized wear purposes present',all('SurfaceUse' in o.data.color_attributes and 'FaceSize' in o.data.color_attributes for o in PARTS))")
s=s.replace("'author_material_count':len(MATERIALS)","'author_material_count':len(MATERIALS),'v2_roof_connections':V2_JOINTS")
s=s.replace("no_runtime_or_layout_edits=True)","no_runtime_or_layout_edits=True,v1_manifest_sha256=sha(HERE.parent/'prototype_v1/manifest.json'),revision='V2 physical joint plates and localized purpose-based weathering; same seven collision bounds')")
ast.parse(s)
(HERE/'build_prototype.py').write_text(s,encoding='utf-8')
r=(OLD/'run_preview.py').read_text(encoding='utf-8')
r=r.replace('import subprocess,json,time','import subprocess,json,time,hashlib')
r=r.replace('start=time.time()',"old=HERE.parent/'prototype_v1'\nmanifest=json.loads((old/'manifest.json').read_text(encoding='utf-8'))\ndef assert_frozen():\n for item in manifest['files']:\n  assert hashlib.sha256((old/item['path']).read_bytes()).hexdigest()==item['sha256'],item['path']\nassert_frozen()\nstart=time.time()")
r=r.replace("report.update(status='EXITED',exit_code=code,elapsed_seconds=time.time()-start)","assert_frozen()\n report.update(status='EXITED',exit_code=code,elapsed_seconds=time.time()-start,v1_frozen_files_verified=len(manifest['files']))")
ast.parse(r)
(HERE/'run_preview.py').write_text(r,encoding='utf-8')
config=json.loads((OLD/'input_config.json').read_text(encoding='utf-8'))
config.update(status='ROOT_V2_CPU_WINDOW_GRANTED_AFTER_PROGRESS_EXIT',revision='V2 localized joint hardware and wear',v1_manifest_sha256=sha(OLD/'manifest.json'))
(HERE/'input_config.json').write_text(json.dumps(config,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'prepared':str(HERE),'v1_files_verified':len(manifest['files']),'build_ast_valid':True,'runner_ast_valid':True,'executed_blender':False},ensure_ascii=False))

