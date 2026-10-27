"""Reopen editable source then actual GLB: UV/PBR, dimensions, usable deck, arch void.
Blender --background --factory-startup --threads 2 --python-exit-code 1
 --python verify_root_arch.py -- [--render]
This is Blender triangle evidence, not Godot collision/performance acceptance.
"""
import bpy, json, struct, hashlib, math, sys
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree

SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[2]
ART=ROOT/'artifacts/v3/art/root_arch';OUT=ROOT/'assets/v3/root_arch'
GLB=OUT/'f1_root_arch.glb';BLEND=SRC/'f1_root_arch.blend'
REVISION=6
checks={};details={}
def check(key,ok):
    checks[key]=bool(ok)
    if not ok:print('ROOT_ARCH_FAIL',key)
def bpos(p):return Vector((p[0],-p[2],p[1]))
def gpos(p):return [p[0],p[2],-p[1]]

bpy.ops.wm.open_mainfile(filepath=str(BLEND))
source=[o for o in bpy.data.collections['Editable_RootArch'].objects if o.type=='MESH']
check('source_is_editable_parts',len(source)>30)
check('source_uv_on_every_part',all(len(o.data.uv_layers)==1 for o in source))
images=[i for i in bpy.data.images if i.source=='FILE' and i.name.startswith('RA_')]
check('source_has_all_12_packed_pbr_maps',len(images)==12 and all(i.packed_file for i in images))
check('source_texture_files_exist',all(Path(bpy.path.abspath(i.filepath)).is_file() for i in images))
details['editable_meshes']=len(source)
details['source_sha256']=hashlib.sha256(BLEND.read_bytes()).hexdigest()

raw=GLB.read_bytes();json_size=struct.unpack_from('<I',raw,12)[0]
doc=json.loads(raw[20:20+json_size]);bin_start=20+json_size+8;binary=raw[bin_start:]
triangles=0;primitive_rows=[]
def read_accessor(index):
    a=doc['accessors'][index];v=doc['bufferViews'][a['bufferView']]
    fmt={5121:'B',5123:'H',5125:'I',5126:'f'}[a['componentType']]
    size={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']]
    fmt='<'+fmt*size;step=struct.calcsize(fmt);stride=v.get('byteStride',step)
    off=v.get('byteOffset',0)+a.get('byteOffset',0)
    return [struct.unpack_from(fmt,binary,off+i*stride) for i in range(a['count'])]
for mesh in doc['meshes']:
    for prim in mesh['primitives']:
        attrs=prim['attributes'];count=doc['accessors'][prim['indices']]['count']//3;triangles+=count
        valid_uv='TEXCOORD_0' in attrs
        if valid_uv:
            uv=read_accessor(attrs['TEXCOORD_0']);indices=[v[0] for v in read_accessor(prim['indices'])]
            degenerate=sum(abs((uv[b][0]-uv[a][0])*(uv[c][1]-uv[a][1])-(uv[b][1]-uv[a][1])*(uv[c][0]-uv[a][0]))<1e-10 for a,b,c in zip(indices[::3],indices[1::3],indices[2::3]))
            # Tube cap fans and leaf tips can legitimately collapse UV; whole joined
            # primitives must not get default UVs or zero-area texturing.
            valid_uv=all(math.isfinite(x) for pair in uv for x in pair) and degenerate<count*.10
        check(mesh['name']+'_finite_usable_uv',valid_uv)
        mat=doc['materials'][prim['material']];pbr=mat['pbrMetallicRoughness']
        check(mat['name']+'_image_pbr',all(k in pbr for k in ('baseColorTexture','metallicRoughnessTexture')) and 'normalTexture' in mat)
        primitive_rows.append({'mesh':mesh['name'],'triangles':count,'material':mat['name'],'degenerate_uv_triangles':degenerate if 'TEXCOORD_0' in attrs else None})
check('triangle_budget_12_to_24k',12000<=triangles<=24000)
check('material_budget_4',len(doc['materials'])<=4)
check('exact_four_semantic_meshes',len(doc['meshes'])==4)
check('all_images_embedded',len(doc.get('images',[]))>=8 and all('bufferView' in i for i in doc['images']))
check('no_exported_studio',not doc.get('cameras') and 'KHR_lights_punctual' not in doc.get('extensions',{}))

bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(GLB))
bpy.context.view_layer.update()
meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
structural=[o for o in meshes if o.name in ('WalkableRoot','StoneRemnants')]
check('explicit_structural_collision_groups',len(structural)==2)
coords=[o.matrix_world@v.co for o in meshes for v in o.data.vertices]
mn=[min(gpos(p)[k] for p in coords) for k in range(3)];mx=[max(gpos(p)[k] for p in coords) for k in range(3)]
check('40m_span',abs(mn[0]+20)<.01 and abs(mx[0]-20)<.01)
check('no_geometry_below_ground',mn[1]>=-.05)
root=bpy.data.objects.get('F1RootArch')
check('root_identity',root is not None and root.matrix_world.is_identity)
expected={'EntryWest':(-20,4.5,0),'Crown':(0,9.5,0),'EntryEast':(20,4.5,0),'Underpass':(0,3.25,0)}
anchors={}
for name,at in expected.items():
    node=bpy.data.objects.get(name)
    check(name+'_unique_actual_anchor',node is not None and (node.matrix_world.translation-bpos(at)).length<.001)
    anchors[name]=gpos(node.matrix_world.translation) if node else None

vs=[];fs=[]
for o in structural:
    off=len(vs);vs.extend(o.matrix_world@v.co for v in o.data.vertices)
    fs.extend(tuple(off+i for i in p.vertices) for p in o.data.polygons)
tree=BVHTree.FromPolygons(vs,fs)
def ray(start,end):
    a=bpos(start);b=bpos(end);delta=b-a
    hit=tree.ray_cast(a,delta.normalized(),delta.length)
    return gpos(hit[0]) if hit[0] is not None else None

# Dense real-surface sampling, 5.5 m useful width, including ends and crown.
deck=[];deck_good=True;max_error=0;max_slope=0;previous={}
for i in range(81):
    x=-19.95+39.9*i/80;expected_y=4.5+5*(1-(x/20)**2)
    for z in (-2.75,-2.0,-1.0,0,1.0,2.0,2.75):
        hit=ray((x,18,z),(x,-1,z))
        if hit is None:deck_good=False;continue
        error=abs(hit[1]-expected_y);max_error=max(max_error,error)
        if error>.25:deck_good=False
        if z in previous:max_slope=max(max_slope,abs(hit[1]-previous[z][1])/(x-previous[z][0]))
        previous[z]=(x,hit[1]);deck.append({'x':round(x,3),'z':z,'top':round(hit[1],5)})
check('continuous_5_5m_usable_deck',deck_good and len(deck)==567)
check('deck_longitudinal_grade_under_0_65',max_slope<.65)
check('crown_and_end_heights',abs(ray((0,18,0),(0,0,0))[1]-9.5)<.08 and abs(ray((19.95,18,0),(19.95,0,0))[1]-4.5)<.10)

# Complete front-to-back flight corridor at the central crossing, not only one ray.
blocked=[];count=0
for i in range(29):
    x=-7+14*i/28
    for j in range(14):
        y=.25+6.25*j/13;hit=ray((x,y,-7),(x,y,7));count+=1
        if hit:blocked.append({'x':x,'y':y,'hit':hit})
check('central_underpass_14m_wide_6_5m_high_clear',not blocked)
clearances=[]
for x in (-6,-3,0,3,6):
    for z in (-2.5,0,2.5):
        hit=ray((x,.01,z),(x,15,z))
        if hit:clearances.append(hit[1])
check('actual_central_roof_above_6_5m',len(clearances)==15 and min(clearances)>=6.5)
details.update({'triangles':triangles,'materials':len(doc['materials']),'mesh_count':len(doc['meshes']),'embedded_images':len(doc.get('images',[])),'primitives':primitive_rows,'bounds_godot':{'min':mn,'max':mx},'markers_godot':anchors,'deck_sample_count':len(deck),'max_deck_error_m':max_error,'max_longitudinal_grade':max_slope,'deck_samples':deck,'underpass_rays':count,'blocked_underpass_rays':blocked,'minimum_sampled_central_underside_y':min(clearances) if clearances else None})
report={'asset':'F1RootArch','glb_sha256':hashlib.sha256(raw).hexdigest(),'glb_bytes':len(raw),'blender':bpy.app.version_string,'checks':checks,'all_checks_pass':all(checks.values()),'details':details,'limits':['Actual GLB roundtrip and CPU triangle BVH, not Godot PhysicsServer.','Studio render from imported GLB, not a game screenshot or performance measurement.']}
(ART/'verification.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('ROOT_ARCH_VERIFY '+json.dumps({k:v for k,v in report.items() if k!='details'}))
assert report['all_checks_pass'],[k for k,v in checks.items() if not v]

if '--render' in sys.argv:
    scene=bpy.context.scene
    scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=28;scene.cycles.use_denoising=True
    scene.render.threads_mode='FIXED';scene.render.threads=2
    scene.render.resolution_x=1536;scene.render.resolution_y=864;scene.render.resolution_percentage=100
    if '--preview' in sys.argv:
        scene.cycles.samples=8;scene.render.resolution_percentage=60
    if '--clay' in sys.argv:
        clay=bpy.data.materials.new('ReviewClay_NOT_EXPORTED');clay.diffuse_color=(.39,.36,.30,1);clay.use_nodes=True
        clay.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(.39,.36,.30,1)
        clay.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value=.9
        for ob in meshes:
            ob.data.materials.clear();ob.data.materials.append(clay)
    scene.render.image_settings.file_format='PNG';scene.world.color=(.25,.25,.25)
    scene.view_settings.view_transform='AgX';scene.view_settings.look='AgX - Medium High Contrast'
    def aim(o,p):o.rotation_euler=(bpos(p)-o.location).to_track_quat('-Z','Y').to_euler()
    for name,at,power,size,color in [('Key',(-10,34,20),18000,23,(1,.91,.78)),('Fill',(22,20,-15),11500,20,(.76,.84,1)),('Rim',(-20,20,-20),14500,18,(1,.93,.81))]:
        data=bpy.data.lights.new(name,'AREA');data.energy=power;data.size=size;data.color=color
        ob=bpy.data.objects.new(name,data);scene.collection.objects.link(ob);ob.location=bpos(at);aim(ob,(0,4,0))
    bpy.ops.mesh.primitive_plane_add(size=220,location=(0,0,-.05));floor=bpy.context.object
    fm=bpy.data.materials.new('StudioOnly');fm.diffuse_color=(.22,.235,.24,1);floor.data.materials.append(fm)
    data=bpy.data.cameras.new('ReviewCamera');cam=bpy.data.objects.new('ReviewCamera',data);scene.collection.objects.link(cam);scene.camera=cam;data.type='ORTHO'
    requested_views=next((a.split('=',1)[1].split(',') for a in sys.argv if a.startswith('--views=')),None)
    for name,at,target,scale in [('default_oblique',(29,27,43),(0,4.3,0),47),('underpass',(5,8,48),(0,4.8,0),46),('top',(0,62,.01),(0,0,0),46)]:
        if requested_views is not None and name not in requested_views:continue
        cam.location=bpos(at);aim(cam,target);data.ortho_scale=scale
        suffix=('_clay' if '--clay' in sys.argv else '')+('_preview' if '--preview' in sys.argv else '')
        scene.render.filepath=str(ART/(name+'_v%d'%REVISION+suffix+'.png'));bpy.ops.render.render(write_still=True)
print('ROOT_ARCH_VERIFIED_DONE')
