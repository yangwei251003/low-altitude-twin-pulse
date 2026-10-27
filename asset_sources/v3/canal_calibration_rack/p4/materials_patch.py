"""Preserve P3 colour/lighting. Replace redundant tread Bump with real ribs.
Only six local, edge-originating yellow paint losses are added.
"""
import bpy

def build(original):
    mat=original.copy();mat.name='CalibrationP4_DeckSteel'
    n=mat.node_tree.nodes;l=mat.node_tree.links;bs=n['SourcePrincipled']
    normal=n['OriginalSteelNormal'];bump=n['ManufacturedAntiSlipBump']
    for link in list(bs.inputs['Normal'].links):l.remove(link)
    l.new(normal.outputs['Normal'],bs.inputs['Normal']);n.remove(bump)
    def put(a,s):
        if hasattr(a,'node'):l.new(a,s)
        else:s.default_value=a
    def op(code,a,b=0):
        node=n.new('ShaderNodeMath');node.operation=code;put(a,node.inputs[0]);put(b,node.inputs[1]);return node.outputs[0]
    def clamp(v):return op('MINIMUM',1,op('MAXIMUM',0,v))
    def ramp(v,a,b):return clamp(op('DIVIDE',op('SUBTRACT',v,a),b-a))
    uv=n.new('ShaderNodeUVMap');uv.uv_map='TopUV';uv.name='P4_EdgeWear_MetricTopUV'
    split=n.new('ShaderNodeSeparateXYZ');l.new(uv.outputs[0],split.inputs[0]);x,y=split.outputs[0],split.outputs[1]
    # Coordinates use Blender XY, the same TopUV as P3. Elliptical losses
    # intersect an existing paint edge; they never create arbitrary rust spots.
    locations=[(-.27,.999,.067,.015),(.52,.923,.045,.012),(-.998,.27,.016,.078),
               (.998,-.48,.018,.058),(.37,-.924,.052,.013),(-.73,-.998,.040,.017),
               (.985,.340,.015,.030),(-.685,.982,.022,.016)]
    masks=[]
    for index,(cx,cy,rx,ry) in enumerate(locations):
        dx=op('DIVIDE',op('SUBTRACT',x,cx),rx);dy=op('DIVIDE',op('SUBTRACT',y,cy),ry)
        r=op('ADD',op('MULTIPLY',dx,dx),op('MULTIPLY',dy,dy))
        # A low amplitude, deterministic scallop gives unequal edge notches.
        wave=op('MULTIPLY',op('SINE',op('ADD',op('MULTIPLY',x,190),op('MULTIPLY',y,137))),.13)
        mask=op('SUBTRACT',1,ramp(op('ADD',r,wave),.62,1.02));mask.node.label='P4 local edge loss '+str(index)
        masks.append(mask)
    wear=masks[0]
    for mask in masks[1:]:wear=op('MAXIMUM',wear,mask)
    outer=op('MAXIMUM',op('ABSOLUTE',x),op('ABSOLUTE',y))
    band=op('MULTIPLY',op('GREATER_THAN',outer,.922),op('LESS_THAN',outer,1.001))
    wear=op('MULTIPLY',wear,band)
    source=n['DarkSteelReflectance'].outputs[0]
    base=bs.inputs['Base Color'].links[0].from_socket
    mix=n.new('ShaderNodeMixRGB');mix.name='P4_LocalPaintEdgeLoss';put(wear,mix.inputs[0]);put(base,mix.inputs[1]);put(source,mix.inputs[2]);l.new(mix.outputs[0],bs.inputs['Base Color'])
    for socket,value in [('Metallic',1.),('Roughness',.69),('Specular IOR Level',.5)]:
        old=bs.inputs[socket].links[0].from_socket
        result=op('ADD',op('MULTIPLY',op('SUBTRACT',1,wear),old),op('MULTIPLY',wear,value))
        l.new(result,bs.inputs[socket])
    mat['p4_change']='Real high-only ribs; no procedural rib Bump. Eight bounded yellow-edge chips. Original P3 colours retained.'
    return mat
