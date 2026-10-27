"""P3 material-only derivative. Open frozen P2, never regenerate its mesh."""
from pathlib import Path
import bpy, json, hashlib, struct
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];P2=HERE.parent/'p2'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
SOURCE=P2/'rising_seal_source_p2.blend'
INPUTS={
 SOURCE:'77771d3a022966635181512115777ddc38356117ea8e8d647a78d94630d4f671',
 P2/'rising_seal_p2_export_ready.blend':'3bdbd9cee0cc26aa8c255948ae55cead1ab7b4702a5cbf1c019a7efa290111e8',
 ROOT/'assets/v3/candidates/rising_seal_p2/rising_seal_p2.glb':'119deb3dcb6af31234b8445848da8cfb509753aedaf9d80e1e6db0244eed9b1b',
 ROOT/'references/v3/production/materials/temple_stone_surface_v1.png':'6f139127394eb9c59913f6fdd66dec510c18a658460efd594a9fd73475c939a8',
 ROOT/'references/v3/production/rising_seal/rising_seal_reference_v1.png':'836f5f42091d21ba9561cf78c387fc7220aa3ad840a7ffc1b70906021ea1d3f6'}
assert all(sha(p)==h for p,h in INPUTS.items())
bpy.ops.wm.open_mainfile(filepath=str(SOURCE));scene=bpy.context.scene;root=bpy.data.objects['RisingSeal']
parts=[o for o in root.children if o.type=='MESH'];anchors=[bpy.data.objects[n] for n in ['Centre','BottomContact','StateInlay']]
def digest(ob):
 h=hashlib.sha256();h.update(struct.pack('<16d',*(x for row in ob.matrix_world for x in row)))
 if ob.type=='MESH':
  for v in ob.data.vertices:h.update(struct.pack('<3d',*v.co))
  for p in ob.data.polygons:h.update(struct.pack('<'+str(len(p.vertices))+'I',*p.vertices))
 return h.hexdigest()
before={o.name:digest(o) for o in parts+anchors}
def material(name):
 m=bpy.data.materials.new(name);m.use_nodes=True;m.use_fake_user=True;n=m.node_tree.nodes;n.clear();l=m.node_tree.links
 out=n.new('ShaderNodeOutputMaterial');p=n.new('ShaderNodeBsdfPrincipled');l.new(p.outputs[0],out.inputs['Surface']);p.inputs['Specular IOR Level'].default_value=.22
 return m,n,l,p
def coords(n,l,uv=False,scale=(1,1,1)):
 c=n.new('ShaderNodeTexCoord');c.object=root;v=n.new('ShaderNodeVectorMath');v.operation='MULTIPLY';v.inputs[1].default_value=scale;l.new(c.outputs['UV' if uv else 'Object'],v.inputs[0]);return v.outputs[0]
def ramp(n,l,s,lo,hi,p0=.15,p1=.85):
 r=n.new('ShaderNodeValToRGB');r.color_ramp.elements[0].position=p0;r.color_ramp.elements[0].color=(*lo,1);r.color_ramp.elements[1].position=p1;r.color_ramp.elements[1].color=(*hi,1);l.new(s,r.inputs[0]);return r.outputs[0]
def noise(n,l,s,scale=1,detail=.5):
 q=n.new('ShaderNodeTexNoise');q.inputs['Scale'].default_value=scale;q.inputs['Detail'].default_value=detail;q.inputs['Roughness'].default_value=.35;l.new(s,q.inputs['Vector']);return q.outputs['Fac']
def rough(n,l,p,s,lo,hi):
 q=n.new('ShaderNodeMapRange');q.inputs['To Min'].default_value=lo;q.inputs['To Max'].default_value=hi;l.new(s,q.inputs['Value']);l.new(q.outputs['Result'],p.inputs['Roughness'])
def bump(n,l,p,s,strength,distance):
 b=n.new('ShaderNodeBump');b.inputs['Strength'].default_value=strength;b.inputs['Distance'].default_value=distance;l.new(s,b.inputs['Height']);l.new(b.outputs['Normal'],p.inputs['Normal'])
im=bpy.data.images.load(str(ROOT/'references/v3/production/materials/temple_stone_surface_v1.png'),check_existing=False);im.colorspace_settings.name='sRGB';im.pack()
stone_mats=[]
for label,base,factor in [('Face',(.25,.275,.285),.57),('WornEdge',(.31,.305,.28),.43),('SeamFloor',(.13,.15,.16),.30)]:
 m,n,l,p=material('P3_Stone_'+label);coord=coords(n,l,scale=(.25,.25,.25))
 t=n.new('ShaderNodeTexImage');t.name='Original_Generated_Albedo_4m';t.image=im;t.projection='BOX';t.projection_blend=.18;t.extension='REPEAT';t.interpolation='Linear';l.new(coord,t.inputs['Vector'])
 mix=n.new('ShaderNodeMixRGB');mix.blend_type='MIX';mix.inputs[0].default_value=factor;mix.inputs[1].default_value=(*base,1);l.new(t.outputs['Color'],mix.inputs[2]);l.new(mix.outputs[0],p.inputs['Base Color'])
 # Authored roughness/normal are deliberately independent of image dark creases.
 broad=noise(n,l,coords(n,l,scale=(1.1,.75,.9)),1.4,.35);rough(n,l,p,broad,.79,.91);bump(n,l,p,broad,.18,.012);stone_mats.append(m)
wood,n,l,p=material('P3_Root_WideUnevenGrain')
gr=noise(n,l,coords(n,l,uv=True,scale=(3.0,.32,1)),1.8,.65)
l.new(ramp(n,l,gr,(.115,.075,.043),(.205,.142,.085),.10,.90),p.inputs['Base Color']);rough(n,l,p,gr,.76,.91);bump(n,l,p,gr,.16,.016)
bronze,n,l,p=material('P3_Bronze_LocalWear');p.inputs['Metallic'].default_value=.5
wear=noise(n,l,coords(n,l,scale=(1.2,.65,1.0)),2.2,.6)
l.new(ramp(n,l,wear,(.13,.115,.065),(.30,.235,.10),.28,.78),p.inputs['Base Color']);rough(n,l,p,wear,.43,.70);bump(n,l,p,wear,.12,.008)
core,n,l,p=material('P3_Core_UniqueTeal');p.inputs['Metallic'].default_value=.1;p.inputs['Roughness'].default_value=.30
cp=noise(n,l,coords(n,l,scale=(1.3,1.3,1.3)),3,.4)
cc=ramp(n,l,cp,(.018,.26,.235),(.04,.53,.44),.1,.9);l.new(cc,p.inputs['Base Color']);l.new(cc,p.inputs['Emission Color']);p.inputs['Emission Strength'].default_value=.75
for ob in parts:
 if ob.name.startswith(('StoneMass_','SeamClosure','SealRecess')):
  for i,m in enumerate(list(ob.data.materials)):
   ob.data.materials[i]=stone_mats[2 if ob.name.startswith(('SeamClosure','SealRecess')) else 1 if 'Worn' in m.name else 0]
 elif ob.name.startswith('RootWrap_'):
  for i in range(len(ob.data.materials)):ob.data.materials[i]=wood
 elif ob.name=='SealEnergyGlass':
  for i in range(len(ob.data.materials)):ob.data.materials[i]=core
 else:
  for i in range(len(ob.data.materials)):ob.data.materials[i]=bronze
after={o.name:digest(o) for o in parts+anchors};triangles=0
for ob in parts:ob.data.calc_loop_triangles();triangles+=len(ob.data.loop_triangles)
checks=[{'name':'exact_P2_vertices_polygons_transforms_anchors','pass':before==after},{'name':'triangles_18528','pass':triangles==18528},{'name':'readonly_P2_and_reference_SHA_unchanged','pass':all(sha(p)==h for p,h in INPUTS.items())}]
assert all(c['pass'] for c in checks)
path=HERE/'rising_seal_source_p3.blend';scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=12;scene.cycles.use_denoising=True;scene.render.threads_mode='FIXED';scene.render.threads=2
scene.render.resolution_x=1200;scene.render.resolution_y=960;scene.render.resolution_percentage=100;bpy.ops.wm.save_as_mainfile(filepath=str(path))
old=json.loads((P2/'source_report.json').read_text(encoding='utf-8'))
report={'stage':'P3 pure material revision; frozen P2 geometry retained, offline candidate only','source_sha256':sha(path),'input_hashes':{p.relative_to(ROOT).as_posix():h for p,h in INPUTS.items()},'bounds_godot':old['bounds_godot'],'geometry_digests_P2':before,'geometry_digests_P3':after,'triangles':triangles,'checks':checks,'all_pass':all(c['pass'] for c in checks),'inherited_P2_geometry_checks':{'path':'asset_sources/v3/rising_seal/p2/source_report.json','sha256':sha(P2/'source_report.json'),'passed':27,'not_rerun':'Geometry identical; game physics from P2 is historical, P3 game render still needed'},'stone_image_scale_m':4,'stone_image_is_geometry':False,'stone_image_seamless_verified':False,'normal_and_roughness_independent_of_generated_albedo':True,'core_emission_strength':.75,'P2_game_evidence':{'path':'artifacts/v3/art/20261018_070126_seal_p2/capture.json','checks':16,'screenshots':7,'art_status':'rejected materials'}}
(HERE/'source_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
scene.render.filepath=str(HERE/'rising_seal_source_p3.png');bpy.ops.render.render(write_still=True);assert all(sha(p)==h for p,h in INPUTS.items());print('SEAL_P3_MATERIAL_SOURCE_DONE',sha(path),triangles,flush=True)
