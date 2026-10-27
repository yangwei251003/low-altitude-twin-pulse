"""One source geometry contact image, not an assembled platform or game scene."""
from pathlib import Path
import bpy,bmesh,json,struct,hashlib,math
from mathutils import Vector
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
research=json.loads((HERE/'source_geometry_research.json').read_text())
frozen={p:sha(p) for p in [ROOT/'assets/v3/root_buttress/root_buttress_h10.glb',HERE.parent/'p7/root_buttress_h10_natural_layers_p7.blend']}
bpy.ops.wm.read_factory_settings(use_empty=True);scene=bpy.context.scene
def bp(p):return Vector((p[0],-p[2],p[1]))
def acc(g,b,index):
 a=g['accessors'][index];v=g['bufferViews'][a['bufferView']];typ={5126:'f',5125:'I',5123:'H',5121:'B'}[a['componentType']];w={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']];s=struct.Struct('<'+typ*w);off=v.get('byteOffset',0)+a.get('byteOffset',0);stride=v.get('byteStride',s.size)
 return [s.unpack_from(b,off+i*stride) for i in range(a['count'])]
def read(path):
 g=json.loads(path.read_text());b=(path.parent/g['buffers'][0]['uri']).read_bytes();p=g['meshes'][0]['primitives'][0];vs=acc(g,b,p['attributes']['POSITION']);ix=[i[0] for i in acc(g,b,p['indices'])];fs=[tuple(ix[i:i+3]) for i in range(0,len(ix),3)]
 return vs,fs
def mat(name,c,rough=.8):
 m=bpy.data.materials.new(name);m.use_nodes=True;p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED');p.inputs['Base Color'].default_value=(*c,1);p.inputs['Roughness'].default_value=rough;p.inputs['Specular IOR Level'].default_value=.2;return m
stone=mat('Shared_clay_no_texture',(.30,.33,.34));floor=mat('Neutral_floor',(.105,.12,.13));ink=mat('Caption',(.67,.73,.77))
records=[]
def show(name,vs,fs,offset):
 used=sorted(set(i for f in fs for i in f));mapping={v:i for i,v in enumerate(used)};raw=[vs[i] for i in used];lo=[min(p[k] for p in raw) for k in range(3)];hi=[max(p[k] for p in raw) for k in range(3)];centre=[(lo[k]+hi[k])/2 for k in range(3)]
 vertices=[bp((p[0]-centre[0]+offset,p[1]-lo[1],p[2]-centre[2])) for p in raw];faces=[tuple(mapping[i] for i in f) for f in fs]
 me=bpy.data.meshes.new(name+'_RawMesh');me.from_pydata(vertices,[],faces);me.update();me.materials.append(stone);ob=bpy.data.objects.new(name,me);scene.collection.objects.link(ob)
 for p in me.polygons:p.use_smooth=True
 ob['source_transform']='Translation only; scale (1,1,1), no deformation or retopology'
 bm=bmesh.new();bm.from_mesh(me);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.00001);boundary=sum(e.is_boundary for e in bm.edges);nonmanifold=sum(not e.is_manifold for e in bm.edges);bm.free()
 records.append({'name':name,'display_scale':[1,1,1],'source_triangles':len(fs),'source_span_godot': [hi[k]-lo[k] for k in range(3)],'source_bounds_godot':[lo,hi],'display_translation_godot':[offset-centre[0],-lo[1],-centre[2]],'boundary_edges_after_virtual_uv_weld':boundary,'nonmanifold_after_virtual_uv_weld':nonmanifold,'material':'uniform shared clay, no original base/normal/PBR maps'})
 return ob
for name,x in [('rock_face_01',-6.0),('rock_face_02',0.0)]:
 path=HERE/'vendor'/name/(name+'_1k.gltf');vs,fs=read(path);show(name,vs,fs,x)
coastpath=ROOT/'asset_sources/third_party/coast_rocks_01/coast_rocks_01_1k.gltf';vs,fs=read(coastpath);crop=research['coast_top_crop_candidates'][0];x,z=crop['min_xz'];cropped=[]
for f in fs:
 centre=[sum(vs[i][k] for i in f)/3 for k in range(3)]
 if x<=centre[0]<=x+4 and z<=centre[2]<=z+4:cropped.append(f)
show('coast_rocks_original_4m_patch',vs,cropped,6.0)
# The coast patch is intentionally left open at crop boundaries: no invented
# thickness, vertical scaling or backfill can misrepresent its real source.
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.035));bpy.context.object.name='ReviewFloor';bpy.context.object.data.materials.append(floor)
world=bpy.data.worlds.new('NeutralWorld');world.use_nodes=True;world.node_tree.nodes['Background'].inputs['Color'].default_value=(.36,.39,.42,1);world.node_tree.nodes['Background'].inputs['Strength'].default_value=.55;scene.world=world
def area(name,pos,power,size):
 data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size;ob=bpy.data.objects.new(name,data);scene.collection.objects.link(ob);ob.location=bp(pos);ob.rotation_euler=(bp((0,1,0))-ob.location).to_track_quat('-Z','Y').to_euler()
area('BroadKey',(-5,9,6),1500,8);area('NeutralFill',(8,6,3),950,8);area('Rim',(0,7,-5),1100,7)
camdata=bpy.data.cameras.new('SourceContactCamera');cam=bpy.data.objects.new('SourceContactCamera',camdata);scene.collection.objects.link(cam);cam.location=bp((0,9,19));target=bp((0,1.5,0));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();camdata.type='ORTHO';camdata.ortho_scale=19.5;scene.camera=cam
def text(body,pos,size=.24):
 cu=bpy.data.curves.new('Caption','FONT');cu.body=body;cu.align_x='CENTER';cu.size=size;cu.extrude=0;ob=bpy.data.objects.new('Caption',cu);scene.collection.objects.link(ob);ob.data.materials.append(ink);ob.location=bp(pos);ob.rotation_euler=cam.rotation_euler
text('SOURCE GEOMETRY ONLY  |  Shared clay / actual scale / no assembly',(0,5.5,0),.3)
for x,a,b in [(-6,'A  ROCK FACE 01','4.95 x 3.56 x 3.83 m  /  20,174 tris'),(0,'B  ROCK FACE 02','2.71 x 2.47 x 2.13 m  /  29,566 tris'),(6,'C  EXISTING COAST CROP','4.19 x 2.03 x 4.15 m  /  18,311 tris')]:
 text(a,(x,.45,3.5),.26);text(b,(x,.35,4.5),.18)
text('A/B: Poly Haven CC0 original meshes   |   C: unscaled 4 m coastal patch; open crop edges',(0,.35,6.0),.19)
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=12;scene.cycles.use_denoising=True;scene.render.threads_mode='FIXED';scene.render.threads=2;scene.render.resolution_x=1600;scene.render.resolution_y=850;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG';scene.view_settings.view_transform='AgX'
blend=HERE/'source_geometry_contact_p8.blend';bpy.ops.wm.save_as_mainfile(filepath=str(blend));scene.render.filepath=str(HERE/'source_geometry_contact_p8.png');bpy.ops.render.render(write_still=True)
report={'purpose':'inspect raw natural cliff source form before any platform assembly','source_blend_sha256':sha(blend),'image_sha256':sha(HERE/'source_geometry_contact_p8.png'),'source_records':records,'render':{'engine':'Cycles CPU','threads':2,'samples':12,'size':[1600,850],'camera_godot':[0,9,19],'look_at_godot':[0,1.5,0]},'old_source_and_runtime_unchanged':all(sha(p)==v for p,v in frozen.items()),'limits':['no construction or functional platform validation','no original photograph maps or image editing','virtual UV seam weld used only for topology inventory, source triangles preserved','coast crop is open at cut boundary, not a closed collision shape','a better source is not final F-B stylization']}
(HERE/'contact_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8');assert report['old_source_and_runtime_unchanged'];print('P8_CONTACT_DONE '+json.dumps({'records':records,'source_sha':report['source_blend_sha256'],'image_sha':report['image_sha256']}),flush=True)
