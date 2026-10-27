"""One p6 candidate from approved cavity/wing geometry; frozen p5 is read-only.
CPU 2. --render previews; --bake performs real PBR bake; --export writes ONLY here.
"""
import bpy, math, json, sys, hashlib
import numpy as np
from pathlib import Path
from mathutils import Vector, Matrix

HERE=Path(__file__).resolve().parent
CROWN=HERE.parents[1]; PROJECT=CROWN.parents[2]
INPUT=HERE/'parasitic_crown_p6_geometry.blend'; TEX=HERE/'textures'
TEX.mkdir(exist_ok=True)
OUT=PROJECT/'assets/v3/candidates/crown_p6'
BAKE='--bake'in sys.argv; EXPORT='--export'in sys.argv; RENDER='--render'in sys.argv
assert not EXPORT or BAKE
bpy.ops.wm.open_mainfile(filepath=str(INPUT))
scene=bpy.context.scene; scene.cycles.device='CPU'; scene.cycles.samples=12
scene.render.threads_mode='FIXED';scene.render.threads=2
model=bpy.data.collections['Crown_EDITABLE_MASTER']; objects=list(model.objects)
meshes=[o for o in objects if o.type=='MESH']; root=bpy.data.objects['ParasiticCrown']
rest={o.name:o.matrix_basis.copy()for o in objects if o.type=='EMPTY'}
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def bp(p):return Vector((p[0],-p[2],p[1]))
def gp(p):return [float(p.x),float(p.z),float(-p.y)]
inputs={'stone':HERE/'stone_reference.png','bark':CROWN/'material_references/bark_reference_p3.png','leaf':CROWN/'material_references/leaf_reference_p4.png'}
names={'stone':'Crown_WarmStone','bark':'Crown_ChestnutBark','leaf':'Crown_LeafMembrane','core':'Crown_AmberCore'}
for kind,name in names.items():bpy.data.materials[name].name=name+'_P5_FROZEN_REFERENCE'
core=bpy.data.materials[names['core']+'_P5_FROZEN_REFERENCE'].copy();core.name=names['core']
# Core geometry and appearance remain untouched. The helper will bake its
# existing PaintUV atlas into the p6 atlas without pretending it is new anatomy.
def material(kind):
    m=bpy.data.materials.new(names[kind]);m.use_nodes=True;n=m.node_tree.nodes;n.clear();l=m.node_tree.links
    out=n.new('ShaderNodeOutputMaterial');p=n.new('ShaderNodeBsdfPrincipled');l.new(p.outputs[0],out.inputs['Surface'])
    p.inputs['Roughness'].default_value={'stone':.94,'bark':.91,'leaf':.86}[kind]
    p.inputs['Specular IOR Level'].default_value=.18;p.inputs['Metallic'].default_value=0
    uv=n.new('ShaderNodeUVMap');uv.uv_map='PaintUV'
    img=bpy.data.images.load(str(inputs[kind]),check_existing=False);img.colorspace_settings.name='sRGB';img.pack()
    tex=n.new('ShaderNodeTexImage');tex.image=img;tex.extension='REPEAT';l.new(uv.outputs['UV'],tex.inputs['Vector'])
    broad=n.new('ShaderNodeMixRGB');broad.blend_type='MIX';broad.inputs[0].default_value={'stone':.16,'bark':.48,'leaf':.40}[kind]
    l.new(tex.outputs['Color'],broad.inputs[1]);broad.inputs[2].default_value={'stone':(.50,.465,.385,1),'bark':(.08,.040,.019,1),'leaf':(.045,.105,.018,1)}[kind]
    ao=n.new('ShaderNodeAmbientOcclusion');ao.inputs['Distance'].default_value=.24;ao.samples=12
    cavity=n.new('ShaderNodeMixRGB');cavity.blend_type='MULTIPLY';cavity.inputs[0].default_value=.32
    l.new(broad.outputs[0],cavity.inputs[1]);l.new(ao.outputs['Color'],cavity.inputs[2]);l.new(cavity.outputs[0],p.inputs['Base Color'])
    gray=n.new('ShaderNodeRGBToBW');l.new(tex.outputs['Color'],gray.inputs[0]);bump=n.new('ShaderNodeBump')
    bump.inputs['Strength'].default_value={'stone':.12,'bark':.24,'leaf':.15}[kind]
    bump.inputs['Distance'].default_value={'stone':.014,'bark':.035,'leaf':.012}[kind]
    l.new(gray.outputs[0],bump.inputs['Height']);l.new(bump.outputs[0],p.inputs['Normal'])
    m['authorship']='Original builtin imagegen color; UV mapped; low-contrast broad planes; conservative authored approximate relief'
    return m
materials={kind:material(kind)for kind in inputs};materials['core']=core
def new_uv(data):
    for u in list(data.uv_layers):data.uv_layers.remove(u)
    u=data.uv_layers.new(name='PaintUV');u.active_render=True;data.uv_layers.active=u;return u
def cylinder(o,uv):
    d=o.data;sides=sorted(d.polygons[0].vertices)[2]
    assert 7<=sides<=32,(o.name,sides)
    rings=len(d.vertices)//sides;tip=len(d.vertices)%sides==1;slot=sum(map(ord,o.name))%4
    for poly in d.polygons:
        js=[int(i)%sides for i in poly.vertices];seam=max(js)-min(js)>sides//2
        for li,vi in zip(poly.loop_indices,poly.vertices):
            row=int(vi)//sides;j=int(vi)%sides;c=1. if seam and j==0 else j/sides;v=row/max(1,rings if tip else rings-1)
            if len(poly.vertices)>4:
                uv.data[li].uv=(.5+.42*math.cos(j*math.tau/sides),(.08 if row==0 else .92)+.055*math.sin(j*math.tau/sides));continue
            if tip and row==rings:
                adjacent=[int(i)%sides for i in poly.vertices if int(i)//sides<rings]
                c=sum(1. if seam and j==0 else j/sides for j in adjacent)/len(adjacent)
            uv.data[li].uv=(.018+.964*c+slot*.173,.018+.964*v)
for o in meshes:
    kind='core'if o.name=='CoreSeed'else 'leaf'if o.name.startswith('LeafMembrane_')else 'stone'if o.name.startswith(('CrownArmor_','DorsalShell_','ClawScute_'))else 'bark'
    o.data.materials.clear();o.data.materials.append(materials[kind])
    if kind in ('core','leaf'):
        assert o.data.uv_layers.active is not None
        o.data.uv_layers.active.name='PaintUV';o.data.uv_layers.active.active_render=True
        continue
    uv=new_uv(o.data)
    if kind=='bark'and len(o.data.polygons[0].vertices)==4:cylinder(o,uv);continue
    coords=np.array([list(v.co)for v in o.data.vertices]);low=coords.min(0);span=np.maximum(coords.max(0)-low,.001);slot=sum(map(ord,o.name))%4
    for poly in o.data.polygons:
        axis=max(range(3),key=lambda i:abs(poly.normal[i]));axes=[i for i in range(3)if i!=axis]
        for li,vi in zip(poly.loop_indices,poly.vertices):
            q=(coords[vi]-low)/span
            # A broad crop of one quiet slab, not a repeated small-rock atlas.
            uv.data[li].uv=(.06+slot*.035+q[axes[0]]*.64,.08+(slot%2)*.09+q[axes[1]]*.64)
def pose(amount):
    for name,matrix in rest.items():bpy.data.objects[name].matrix_basis=matrix.copy()
    for name,deg,axis in [('CrownPlatePivot_L',-60,'Z'),('CrownPlatePivot_R',72,'Z'),('CrownPlatePivot_C',-58,'X')]:
        bpy.data.objects[name].matrix_basis=rest[name]@Matrix.Rotation(math.radians(deg*amount),4,axis)
    bpy.context.view_layer.update()
root['status']='p6 isolated candidate; not runtime accepted'
root['open_angles_godot_degrees']='L:Y:-60,R:Y:72,C:X:-58'
camera=scene.camera;camera.location=bp((32,39,32));camera.rotation_euler=(-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.ortho_scale=26
scene.render.resolution_x=1280;scene.render.resolution_y=720;scene.render.resolution_percentage=100
report={'stage':'p6 isolated candidate, not game acceptance','geometry_sha256':sha(INPUT),'script_sha256':sha(Path(__file__)),'angles':[-60,72,-58],
 'materials':list(names.values()),'mesh_count':len(meshes),'triangles':sum(len(p.vertices)-2 for o in meshes for p in o.data.polygons),
 'input_images':{kind:{'path':str(path.relative_to(PROJECT)),'sha256':sha(path)}for kind,path in inputs.items()},'previews':{},'baked':BAKE,'exported':EXPORT}
pose(0)
if BAKE:
    sys.path.insert(0,str(HERE));from bake_candidate_surfaces import bake_pbr
    materials,records=bake_pbr(scene,meshes,materials,TEX,'p6');report['bake_maps']=records
    assert {m.name for m in materials.values()}==set(names.values())
uv_checks=[]
for o in meshes:
    o.data.calc_loop_triangles();u=o.data.uv_layers.active;bad=0
    for tri in o.data.loop_triangles:
        a,b,c=[o.data.vertices[i].co for i in tri.vertices]
        if (b-a).cross(c-a).length<=1e-9:continue
        a,b,c=[u.data[i].uv for i in tri.loops]
        bad+=abs((b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x))<=1e-10
    uv_checks.append({'node':o.name,'collapsed':int(bad),'uv_layers':[u.name for u in o.data.uv_layers]})
assert not any(x['collapsed']for x in uv_checks),[x for x in uv_checks if x['collapsed']]
report['uv_checks']=uv_checks
for label,amount in [('closed',0),('open',1)]:
    pose(amount)
    if RENDER:
        p=HERE/('p6_material_'+label+'_game_angle.png');scene.render.filepath=str(p);bpy.ops.render.render(write_still=True)
        report['previews'][label]={'path':str(p),'sha256':sha(p)}
pose(0)
blend=HERE/('parasitic_crown_p6.blend'if BAKE else 'parasitic_crown_p6_surface_study.blend')
bpy.ops.wm.save_as_mainfile(filepath=str(blend));report['blend_sha256']=sha(blend)
if EXPORT:
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:o.select_set(True)
    OUT.mkdir(parents=True,exist_ok=True)
    bpy.context.view_layer.objects.active=root;glb=OUT/'parasitic_crown.glb'
    bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,export_apply=True,export_yup=True,export_extras=True,export_texcoords=True,export_normals=True,export_materials='EXPORT',export_cameras=False,export_lights=False,export_animations=False)
    report['glb_sha256']=sha(glb);report['glb_bytes']=glb.stat().st_size
(HERE/'surface_review.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('P6_SURFACE_DONE',json.dumps({k:report[k]for k in ['mesh_count','triangles','baked','exported']}),flush=True)
