"""Approved revision2 recipes with periodic metric coordinates. No image pixel editing."""
from pathlib import Path
import bpy, hashlib, json, math, shutil

class Graph:
    def __init__(self,name):
        self.m=bpy.data.materials.new(name); self.m.use_nodes=True
        self.n=self.m.node_tree.nodes; self.n.clear(); self.l=self.m.node_tree.links
        self.bs=self.n.new('ShaderNodeBsdfPrincipled'); self.bs.inputs['Emission Strength'].default_value=0
        self.out=self.n.new('ShaderNodeOutputMaterial'); self.l.new(self.bs.outputs[0],self.out.inputs['Surface'])
        uv=self.n.new('ShaderNodeUVMap'); uv.uv_map='SourceMetric'; self.uv=uv.outputs[0]
        sep=self.n.new('ShaderNodeSeparateXYZ'); self.l.new(self.uv,sep.inputs[0]); self.u=sep.outputs[0]; self.v=sep.outputs[1]
    def put(self,x,socket):
        if hasattr(x,'node'): self.l.new(x,socket)
        else: socket.default_value=(x,x,x,1) if isinstance(x,(float,int)) and socket.type=='RGBA' else x
    def op(self,operation,a,b=0):
        n=self.n.new('ShaderNodeMath'); n.operation=operation; self.put(a,n.inputs[0]); self.put(b,n.inputs[1]); return n.outputs[0]
    def mix(self,a,b,f,mode='MIX'):
        n=self.n.new('ShaderNodeMixRGB'); n.blend_type=mode
        for value,socket in zip((f,a,b),n.inputs): self.put(value,socket)
        return n.outputs[0]
    def vec(self,x,y,z=0):
        n=self.n.new('ShaderNodeCombineXYZ')
        for value,socket in zip((x,y,z),n.inputs): self.put(value,socket)
        return n.outputs[0]
    def tex(self,image,vector):
        n=self.n.new('ShaderNodeTexImage'); n.image=image; n.extension='REPEAT'; self.l.new(vector,n.inputs[0]); return n.outputs['Color']

def atlas(g,image,quadrant):
    u=g.op('PINGPONG',g.op('ADD',g.op('DIVIDE',g.u,1.8),.17),1)
    v=g.op('PINGPONG',g.op('ADD',g.op('DIVIDE',g.v,1.8),.39),1)
    return g.tex(image,g.vec(g.op('ADD',quadrant[0]+.008,g.op('MULTIPLY',u,.484)),g.op('ADD',quadrant[1]+.008,g.op('MULTIPLY',v,.484))))

def periodic_micro_bump(g,period=3.6):
    # A 4D torus preserves a metric derivative and matches value/derivative on both edges.
    angle_u=g.op('MULTIPLY',g.u,2*math.pi/period); angle_v=g.op('MULTIPLY',g.v,2*math.pi/period)
    r=period/(2*math.pi)
    components=[g.op('MULTIPLY',g.op(op,ang),r) for ang,op in [(angle_u,'SINE'),(angle_u,'COSINE'),(angle_v,'SINE'),(angle_v,'COSINE')]]
    noise=g.n.new('ShaderNodeTexNoise'); noise.noise_dimensions='4D'
    g.l.new(g.vec(*components[:3]),noise.inputs['Vector']); g.l.new(components[3],noise.inputs['W'])
    noise.inputs['Scale'].default_value=70; noise.inputs['Detail'].default_value=1
    bump=g.n.new('ShaderNodeBump'); bump.inputs['Strength'].default_value=.18; bump.inputs['Distance'].default_value=.0005
    g.l.new(noise.outputs['Fac'],bump.inputs['Height']); g.l.new(bump.outputs['Normal'],g.bs.inputs['Normal'])

def concrete(images,repair=False):
    g=Graph('YC_RepairLocal' if repair else 'YC_ConcreteShared')
    color=atlas(g,images['atlas'],(.5,.5) if repair else (0,.5))
    g.put(g.mix((.19,.182,.166,1) if repair else (.255,.236,.209,1),color,.26),g.bs.inputs['Base Color'])
    g.bs.inputs['Roughness'].default_value=.84 if repair else .88
    periodic_micro_bump(g); g.m['period_metres']=3.6; g.m['cache_family']='local' if repair else 'concrete'
    return g.m

def soil(images,config,local=False):
    g=Graph('YC_SoilLocal' if local else 'YC_SoilShared')
    coord=g.vec(g.op('DIVIDE',g.u,2.53),g.op('DIVIDE',g.v,2.53))
    sat=g.n.new('ShaderNodeHueSaturation'); sat.inputs['Saturation'].default_value=.35; sat.inputs['Value'].default_value=.88
    g.l.new(g.tex(images['sand_color'],coord),sat.inputs['Color'])
    color=g.mix((.145,.124,.099,1),sat.outputs[0],.60)
    rough=g.op('ADD',.78,g.op('MULTIPLY',g.tex(images['sand_rough'],coord),.16))
    if local:
        cx,cz=config['wet_center']; rx,rz=config['wet_radii']
        du=g.op('DIVIDE',g.op('SUBTRACT',g.u,cx),rx); dv=g.op('DIVIDE',g.op('SUBTRACT',g.v,cz),rz)
        wet=g.op('MAXIMUM',0,g.op('SUBTRACT',1,g.op('ADD',g.op('MULTIPLY',du,du),g.op('MULTIPLY',dv,dv))))
        color=g.mix(color,g.mix(color,(.52,.60,.66,1),1,'MULTIPLY'),g.op('MULTIPLY',wet,.64))
        rough=g.op('SUBTRACT',rough,g.op('MULTIPLY',wet,.15))
    g.put(color,g.bs.inputs['Base Color']); g.put(rough,g.bs.inputs['Roughness'])
    normal=g.n.new('ShaderNodeNormalMap'); normal.uv_map='SourceMetric'; normal.inputs['Strength'].default_value=.32
    g.l.new(g.tex(images['sand_normal'],coord),normal.inputs['Color']); g.l.new(normal.outputs[0],g.bs.inputs['Normal'])
    g.m['period_metres']=2.53; g.m['cache_family']='local' if local else 'soil'; g.m['source_normal_strength']=.32
    return g.m

def solid(name,color,roughness,metallic=0):
    g=Graph(name); g.bs.inputs['Base Color'].default_value=(*color,1); g.bs.inputs['Roughness'].default_value=roughness
    g.bs.inputs['Metallic'].default_value=metallic; g.m['cache_family']='local'; return g.m

def make_materials(images,config):
    return {'concrete':concrete(images),'soil':soil(images,config),'soil_local':soil(images,config,True),
            'repair':concrete(images,True),'seal':solid('YC_SealLocal',(.033,.037,.033),.95),
            'inlet':solid('YC_InletBottomLocal',(.033,.037,.033),.95),
            'teal':solid('YC_TealLocal',(.045,.098,.10),.63,.15),'steel':solid('YC_SteelLocal',(.22,.24,.24),.56,.88)}

def load_images(root,inputs_path,out):
    manifest=json.loads(Path(inputs_path).read_text(encoding='utf-8')); images={}; rows=[]
    destination=Path(out)/'source_inputs'; destination.mkdir(exist_ok=True)
    for row in manifest['images']:
        original=Path(root)/row['path']; digest=hashlib.sha256(original.read_bytes()).hexdigest()
        assert digest==row['sha256'],str(original)
        p=destination/original.name
        if not p.exists(): shutil.copyfile(original,p)
        assert hashlib.sha256(p.read_bytes()).hexdigest()==digest
        im=bpy.data.images.load(str(p),check_existing=False); im.colorspace_settings.name=row['colorspace']
        pixel=list(im.pixels[:4]); assert len(pixel)==4 and all(math.isfinite(v) for v in pixel) and im.has_data
        assert list(im.size)==row['size']
        images[row['role']]=im; rows.append({**row,'local':str(p),'pixel':pixel})
    return images,rows
