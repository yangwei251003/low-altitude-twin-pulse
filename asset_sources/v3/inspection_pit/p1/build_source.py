"""Source-only inspection well from reviewed physical dimensions and P3 reference.
No glTF export; editable concrete panels, correct downhill ramp and flush props.
"""
import bpy, math, json, hashlib, os, sys
from pathlib import Path
from mathutils import Vector
sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
OUT=Path(os.environ['PIT_PREVIEW_OUTPUT']).resolve()
assert OUT.is_relative_to(HERE) and OUT.is_dir()
ATLAS=ROOT/'asset_sources/v3/i2_canal_revetment/p1/source_inputs/clinic_ground_material_atlas_UNEDITED.png'
FRONT=ROOT/'asset_sources/v3/i2_canal_revetment/p4/source_inputs/revetment_front_basecolor_v2_UNEDITED.png'
REFERENCE=ROOT/'references/v3/production/inspection_pit/p3-geometry-constrained.png'
PARTS=[]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def bp(x,y,z):return (x+17.625,-z+5.75,y)
def gp(v):return (v.x-17.625,v.z,5.75-v.y)
def dump(name,value):(OUT/name).write_text(json.dumps(value,ensure_ascii=False,indent=2,allow_nan=False),encoding='utf-8')

class Graph:
    def __init__(self,name):
        self.m=bpy.data.materials.new(name);self.m.use_nodes=True
        self.n=self.m.node_tree.nodes;self.n.clear();self.l=self.m.node_tree.links
    def val(self,v,s):
        if hasattr(v,'node'):self.l.new(v,s)
        else:s.default_value=(v,v,v,1) if s.type=='RGBA' and isinstance(v,(int,float)) else v
    def op(self,op,a,b=0):
        n=self.n.new('ShaderNodeMath');n.operation=op;self.val(a,n.inputs[0]);self.val(b,n.inputs[1]);return n.outputs[0]
    def mix(self,a,b,f):
        n=self.n.new('ShaderNodeMixRGB')
        for v,s in zip((f,a,b),n.inputs):self.val(v,s)
        return n.outputs[0]
    def uv(self,name):
        n=self.n.new('ShaderNodeUVMap');n.uv_map=name;return n.outputs[0]
    def texture(self,image,uv,extension='REPEAT'):
        n=self.n.new('ShaderNodeTexImage');n.image=image;n.extension=extension;self.l.new(uv,n.inputs['Vector']);return n.outputs['Color']
    def atlas_uv(self,metric,paint=False):
        sep=self.n.new('ShaderNodeSeparateXYZ');self.l.new(metric,sep.inputs[0])
        comb=self.n.new('ShaderNodeCombineXYZ')
        self.val(self.op('ADD',.008,self.op('MULTIPLY',.48,self.op('PINGPONG',self.op('DIVIDE',sep.outputs[0],2),1))),comb.inputs[0])
        self.val(self.op('ADD',.008 if paint else .508,self.op('MULTIPLY',.48,self.op('PINGPONG',self.op('DIVIDE',sep.outputs[1],2),1))),comb.inputs[1])
        return comb.outputs[0]
    def wall_uv(self):
        sep=self.n.new('ShaderNodeSeparateXYZ');self.l.new(self.uv('WallUV'),sep.inputs[0])
        comb=self.n.new('ShaderNodeCombineXYZ')
        self.val(self.op('FRACT',sep.outputs[0]),comb.inputs[0])
        self.val(self.op('MINIMUM',.9999,self.op('MAXIMUM',.0001,sep.outputs[1])),comb.inputs[1])
        return comb.outputs[0]

def material(kind):
    g=Graph('Pit_'+kind);metric=g.uv('MetricUV')
    noise=g.n.new('ShaderNodeTexNoise');noise.inputs['Scale'].default_value=45;noise.inputs['Detail'].default_value=2
    g.l.new(metric,noise.inputs['Vector'])
    metal=0.;rough=.86
    if kind=='Wall':
        # Four metre source image remains metric; crop the 2.8m height at -2.4m.
        color=g.mix((.30,.29,.26,1),g.texture(IMAGES['front'],g.wall_uv(),'EXTEND'),.88)
    elif kind in ('Floor','Coping','Ramp'):
        color=g.mix((.31,.30,.27,1),g.texture(IMAGES['atlas'],g.atlas_uv(metric),'EXTEND'),.62)
    elif kind=='Teal':
        color=g.mix((.025,.075,.08,1),g.texture(IMAGES['atlas'],g.atlas_uv(metric,True),'EXTEND'),.85);rough=.66
    elif kind=='Steel':color=(.105,.12,.12,1);metal=.8;rough=.61
    elif kind=='Yellow':color=(.66,.34,.025,1);rough=.8
    else:color=(.045,.043,.038,1);rough=.95
    bs=g.n.new('ShaderNodeBsdfPrincipled');g.val(color,bs.inputs['Base Color']);g.val(rough,bs.inputs['Roughness']);g.val(metal,bs.inputs['Metallic'])
    bump=g.n.new('ShaderNodeBump');bump.inputs['Distance'].default_value=.0008;bump.inputs['Strength'].default_value=.25
    g.l.new(noise.outputs['Fac'],bump.inputs['Height']);g.l.new(bump.outputs['Normal'],bs.inputs['Normal'])
    out=g.n.new('ShaderNodeOutputMaterial');g.l.new(bs.outputs['BSDF'],out.inputs['Surface'])
    g.m['unbaked_source']=True;g.m['no_reference_projection']=True
    return g.m

def uv(obj):
    mesh=obj.data
    for name in ('MetricUV','WallUV','AggregateUV','PaintUV'):mesh.uv_layers.new(name=name)
    for poly in mesh.polygons:
        n=Vector(gp(poly.normal))-Vector((-17.625,0,5.75))
        # gp is affine; remove its translation to obtain the Godot direction.
        dominant=max(range(3),key=lambda k:abs(n[k]))
        for li in poly.loop_indices:
            x,y,z=gp(obj.matrix_world@mesh.vertices[mesh.loops[li].vertex_index].co)
            a,b=(x,z) if dominant==1 else ((z,y) if dominant==0 else (x,y))
            mesh.uv_layers['MetricUV'].data[li].uv=(a,b)
            mesh.uv_layers['WallUV'].data[li].uv=((a+24)/4,(y+2.8)/2.8)
            u,v=(a/2)%1,(b/2)%1
            mesh.uv_layers['AggregateUV'].data[li].uv=(.008+u*.48,.508+v*.48)
            mesh.uv_layers['PaintUV'].data[li].uv=(.008+u*.48,.008+v*.48)
    mesh.uv_layers.active_index=0

def finish(obj,name,kind,bevel=0):
    obj.name=name;bpy.context.view_layer.objects.active=obj
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if bevel:
        mod=obj.modifiers.new('PhysicalEdgeBevel','BEVEL');mod.width=bevel;mod.segments=2
        bpy.ops.object.modifier_apply(modifier=mod.name)
    obj.data.materials.append(MATS[kind])
    if kind=='Wall':
        obj.data.materials.append(MATS['Coping'])
        for poly in obj.data.polygons:
            if poly.normal.z>.5:poly.material_index=1
    uv(obj);obj['editable_part']=True;obj['asset_id']='I2:inspection_pit';obj['role']=kind
    PARTS.append(obj);return obj

def box(name,x0,x1,y0,y1,z0,z1,kind,bevel=.003):
    bpy.ops.mesh.primitive_cube_add(size=1,location=bp((x0+x1)/2,(y0+y1)/2,(z0+z1)/2))
    ob=bpy.context.object;ob.dimensions=(x1-x0,z1-z0,y1-y0)
    return finish(ob,name,kind,bevel)

def mesh_obj(name,vertices,faces,kind):
    me=bpy.data.meshes.new(name);me.from_pydata([bp(*v) for v in vertices],[],faces);me.update()
    ob=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(ob)
    return finish(ob,name,kind)

def slab(name,x0,x1,z0,z1,kind='Floor',top=-2.4):
    return box(name,x0,x1,top-.06,top,z0,z1,kind,.002)

def wall_row(name,x0,x1,z0,z1,axis):
    length=(x1-x0) if axis=='X' else (z1-z0)
    count=max(1,math.ceil(length/2.4))
    for i in range(count):
        for j in range(2):
            a=i/count;b=(i+1)/count
            xx0=x0+(x1-x0)*a if axis=='X' else x0;xx1=x0+(x1-x0)*b if axis=='X' else x1
            zz0=z0+(z1-z0)*a if axis=='Z' else z0;zz1=z0+(z1-z0)*b if axis=='Z' else z1
            # Slight true joints; backing remains within original wall solid.
            if i>0:
                if axis=='X':xx0+=.003
                else:zz0+=.003
            if i<count-1:
                if axis=='X':xx1-=.003
                else:zz1-=.003
            y0=-2.4+j*1.2+(.003 if j else 0);y1=-1.2+j*1.2-(.003 if j==0 else 0)
            box(f'{name}_{i}_{j}',xx0,xx1,y0,y1,zz0,zz1,'Wall',.008)

def tiled_floor(name,x0,x1,z0,z1):
    nx=max(1,math.ceil((x1-x0)/2));nz=max(1,math.ceil((z1-z0)/2))
    for i in range(nx):
        for j in range(nz):
            a=x0+(x1-x0)*i/nx;b=x0+(x1-x0)*(i+1)/nx;c=z0+(z1-z0)*j/nz;d=z0+(z1-z0)*(j+1)/nz
            slab(f'{name}_{i}_{j}',a+.002 if i else a,b-.002 if i<nx-1 else b,c+.002 if j else c,d-.002 if j<nz-1 else d)

def ramp_y(z):return -2.4+(z-4)*2.4/6.5
def ramp_strip(name,z0,z1,lower=0):
    vertices=[(-20.5,ramp_y(z0)-lower,z0),(-17.5,ramp_y(z0)-lower,z0),(-17.5,ramp_y(z1)-lower,z1),(-20.5,ramp_y(z1)-lower,z1)]
    return mesh_obj(name,vertices,[(0,3,2,1)],'Ramp' if not lower else 'Seam')

bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
IMAGES={}
for key,p in [('atlas',ATLAS),('front',FRONT)]:
    im=bpy.data.images.load(str(p),check_existing=False);im.colorspace_settings.name='sRGB';im.pack();IMAGES[key]=im
MATS={kind:material(kind) for kind in ('Wall','Floor','Coping','Ramp','Teal','Steel','Yellow','Seam')}
wall_row('WestWall',-22,-21.7,1,10.5,'Z')
wall_row('EastWall',-13.55,-13.25,1,10.5,'Z')
wall_row('NorthWall',-21.7,-13.55,1,1.3,'X')
wall_row('SouthLeft',-21.7,-20.5,10.2,10.5,'X')
wall_row('SouthRight',-17.5,-13.55,10.2,10.5,'X')
# Joint backing is inset, without occupying the accessible interior.
box('WestBacking',-21.96,-21.75,-2.388,-.012,1.012,10.488,'Seam',0)
box('EastBacking',-13.5,-13.29,-2.388,-.012,1.012,10.488,'Seam',0)
box('NorthBacking',-21.688,-13.562,-2.388,-.012,1.04,1.25,'Seam',0)
tiled_floor('RearN',-21.7,-13.55,1.3,2)
tiled_floor('RearS',-21.7,-13.55,2.16,4)
tiled_floor('WestFloor',-21.7,-20.5,4,10.2)
tiled_floor('RightFloorFront',-17.5,-13.55,4,5.8)
tiled_floor('RightFloorBack',-17.5,-13.55,6.9,10.2)
tiled_floor('HatchWest',-17.5,-16.5,5.8,6.9)
tiled_floor('HatchEast',-15.4,-13.55,5.8,6.9)
slab('FlushInspectionFrame',-16.5,-15.4,5.8,6.9,'Steel',-2.402)
slab('FlushInspectionPlate',-16.46,-15.44,5.84,6.86,'Teal',-2.4)
for i,x in enumerate([-16.39,-15.51]):
    for j,z in enumerate([5.91,6.79]):
        bpy.ops.mesh.primitive_cylinder_add(vertices=8,radius=.018,depth=.004,location=bp(x,-2.401,z))
        finish(bpy.context.object,f'HatchBolt{i}{j}','Steel',.001)
slab('DrainRecess',-21.7,-13.55,2,2.16,'Seam',-2.425)
for i in range(82):
    x=-21.69+i*.099
    box(f'DrainCrossbar{i:02}',x,min(x+.025,-13.55),-2.42,-2.4,2,2.16,'Steel',.001)
# Exact high south entry, no external incline. Recessed anti-slip cuts are real.
for i in range(26):
    z=4+i*.25
    ramp_strip(f'RampSurface{i:02}',z,z+.242)
    ramp_strip(f'RecessedRampGroove{i:02}',z+.242,z+.25,.003)
mesh_obj('RampWestSolid',[(-20.5,-2.4,4),(-20.5,-2.4,10.5),(-20.5,0,10.5)],[(0,1,2)],'Wall')
mesh_obj('RampEastSolid',[(-17.5,-2.4,4),(-17.5,-2.4,10.5),(-17.5,0,10.5)],[(0,2,1)],'Wall')
mesh_obj('BuriedRampFront',[(-20.5,-2.4,10.5),(-17.5,-2.4,10.5),(-17.5,0,10.5),(-20.5,0,10.5)],[(0,1,2,3)],'Wall')
# Sparse flush anchoring plates, not gratuitous pipes or clutter.
for i,x in enumerate([-21.35,-19.4,-17.4,-15.4,-13.9]):
    box(f'NorthAnchor{i}',x-.095,x+.095,-.42,-.1,1.298,1.313,'Teal',.003)
    for j in range(2):
        bpy.ops.mesh.primitive_cylinder_add(vertices=8,radius=.016,depth=.009,location=bp(x,-.17-j*.18,1.317),rotation=(math.pi/2,0,0))
        finish(bpy.context.object,f'NorthAnchor{i}_Bolt{j}','Steel',.001)
for i,z in enumerate([1.7,4.3,6.8,9.7]):
    for side,x in [('West',-21.694),('East',-13.556)]:
        box(f'{side}Anchor{i}',x-.007,x+.007,-.42,-.1,z-.095,z+.095,'Teal',.002)
# Paint lies on the top coping, leaving the ramp opening fully free.
box('EntryPaintLeft',-21.3,-20.55,-.002,.001,10.24,10.47,'Yellow',.001)
box('EntryPaintRight',-17.45,-16.7,-.002,.001,10.24,10.47,'Yellow',.001)
bpy.context.view_layer.update()
# Blender uses the opposite front winding to the Godot physics construction.
# Thin ramp flanks must face their visible exterior before glTF backface culling.
for name,axis,sign in [('RampWestSolid',0,-1),('RampEastSolid',0,1),('BuriedRampFront',1,-1)]:
    assert all(p.normal[axis]*sign>.999 for p in bpy.data.objects[name].data.polygons),name
assert all(p.normal.z>.9 for ob in PARTS if ob.name.startswith('RampSurface') for p in ob.data.polygons)
triangles=0;bounds=[]
for ob in PARTS:
    ob.data.calc_loop_triangles();triangles+=len(ob.data.loop_triangles)
    bounds.extend([gp(ob.matrix_world@v.co) for v in ob.data.vertices])
report={'status':'source_preview_not_baked_not_imported','parts':len(PARTS),'triangles':triangles,'bounds_godot':[[min(v[i] for v in bounds) for i in range(3)],[max(v[i] for v in bounds) for i in range(3)]],'references':{str(p.relative_to(ROOT)):sha(p) for p in [ATLAS,FRONT,REFERENCE]},'physics_envelope_notes':'3mm seam relief, drain inset25mm, flush inspection plate; original physical wall planes retained','ramps':{'x':[-20.5,-17.5],'z':[4,10.5],'y':[-2.4,0]}}
assert all(math.isfinite(v) for row in report['bounds_godot'] for v in row)
assert report['bounds_godot'][0][0]>=-22.00001 and report['bounds_godot'][1][0]<=-13.24999
assert report['bounds_godot'][0][2]>=.99999 and report['bounds_godot'][1][2]<=10.50001
dump('source_report.json',report)
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-2.48));bpy.context.object.name='Studio_NOT_ASSET'
bpy.ops.object.camera_add(location=(12,-15,15));camera=bpy.context.object
camera.rotation_euler=(Vector((0,0,-.8))-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.type='ORTHO';camera.data.ortho_scale=14.8
scene=bpy.context.scene;scene.camera=camera
bpy.ops.object.light_add(type='AREA',location=(-5,-3,12));light=bpy.context.object;light.data.energy=2200;light.data.shape='DISK';light.data.size=9
scene.world.color=(.5,.5,.5);scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=20;scene.cycles.use_denoising=True
scene.render.threads_mode='FIXED';scene.render.threads=2;scene.render.resolution_x=1000;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.render.filepath=str(OUT/'01-reference-oblique.png')
source=OUT/'inspection_pit_editable.blend';bpy.ops.wm.save_as_mainfile(filepath=str(source))
bpy.ops.wm.open_mainfile(filepath=str(source))
assert len([ob for ob in bpy.data.objects if ob.get('asset_id')=='I2:inspection_pit'])==report['parts']
assert all(im.packed_file for im in bpy.data.images if im.source=='FILE')
bpy.ops.render.render(write_still=True)
dump('completed.json',{'source_sha256':sha(source),'render_sha256':sha(OUT/'01-reference-oblique.png'),'status':'reopened_and_rendered_no_glb'})
