"""P2 source: dielectric paint, local metal chips, real geometry tread.

Procedural source remains editable; not yet baked/exportable game PBR.
Studio and cameras are unchanged from P1 for comparison.
"""
import math
import bpy


def linear(hex_color):
    values=[int(hex_color[i:i+2],16)/255 for i in (0,2,4)]
    return tuple(v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in values)+(1,)


def create_materials():
    result={}
    specifications={
        'IB_BlueSteel':('173d45','244b53',0.0,.70),
        'IB_DeckSteel':('343e44','4a545a',.78,.61),
        'IB_DarkSteel':('2a3337','3a4449',.82,.57),
        'IB_BurnishedSteel':('7f898a','a0a6a2',.92,.36),
        'IB_OchreGrip':('94703a','b18a45',0.0,.67),
    }
    for name,(dark,light,metallic,roughness) in specifications.items():
        mat=bpy.data.materials.new(name);mat.use_nodes=True;mat.diffuse_color=linear(dark)
        mat['source_only_procedural']=True
        mat['pbr_bake_status']='not baked; source preview only'
        mat['coating_model']='dielectric; metallic only local chip mask' if metallic==0 else 'exposed metal'
        nodes,links=mat.node_tree.nodes,mat.node_tree.links;nodes.clear()

        def node(kind,label,x,y):
            n=nodes.new(kind);n.label=label;n.location=(x,y);return n

        def connect(value,socket):
            if hasattr(value,'node'):links.new(value,socket)
            else:socket.default_value=value

        def calc(op,a,b,label,x,y):
            n=node('ShaderNodeMath',label,x,y);n.operation=op
            connect(a,n.inputs[0]);connect(b,n.inputs[1]);return n.outputs[0]

        def ramp(value,lo,hi,label,x,y):
            n=node('ShaderNodeValToRGB',label,x,y)
            n.color_ramp.elements[0].position=lo;n.color_ramp.elements[1].position=hi
            n.color_ramp.interpolation='EASE';links.new(value,n.inputs[0]);return n.outputs['Color']

        def mix(a,b,f,label,x,y):
            n=node('ShaderNodeMixRGB',label,x,y)
            connect(a,n.inputs[1]);connect(b,n.inputs[2]);connect(f,n.inputs[0]);return n.outputs[0]

        out=node('ShaderNodeOutputMaterial','Source material',1400,100)
        bsdf=node('ShaderNodeBsdfPrincipled','Dielectric painted coating' if metallic==0 else 'Bare steel',1150,100)
        bsdf.inputs['Metallic'].default_value=metallic
        bsdf.inputs['Roughness'].default_value=roughness
        bsdf.inputs['IOR'].default_value=1.48
        links.new(bsdf.outputs[0],out.inputs['Surface'])
        geometry=node('ShaderNodeNewGeometry','Source metres',-1500,450)
        coords=geometry.outputs['Position']
        xyz=node('ShaderNodeSeparateXYZ','Source X / Blender Z is vertical Y',-1300,150)
        links.new(coords,xyz.inputs[0])
        broad=node('ShaderNodeTexNoise','Broad quiet colour variation',-1300,450)
        broad.inputs['Scale'].default_value=.85;broad.inputs['Detail'].default_value=1.3
        links.new(coords,broad.inputs['Vector'])
        colour=mix(linear(dark),linear(light),broad.outputs['Fac'],'Restrained base colours',-1000,450)

        if metallic==0:
            xphase=calc('MULTIPLY',xyz.outputs['X'],math.pi,'Actual 1m rib spacing',-1100,150)
            xwave=calc('SINE',xphase,0,'Rib axes',-900,150)
            xdist=calc('ABSOLUTE',xwave,0,'Distance proxy from rib axes',-700,150)
            yphase=calc('MULTIPLY',xyz.outputs['Z'],math.pi,'Fold heights 0 and 1m',-1100,-10)
            ywave=calc('SINE',yphase,0,'Fold axes',-900,-10)
            ydist=calc('ABSOLUTE',ywave,0,'Distance proxy from folds',-700,-10)
            distance=calc('MINIMUM',xdist,ydist,'Restrict to actual ribs and folded edges',-500,80)
            edge=calc('MULTIPLY',distance,26,'Narrow 12mm-ish coating edge',-300,80)
            edge=calc('SUBTRACT',1,edge,'Edge falloff',-100,80)
            edge=calc('MAXIMUM',edge,0,'Keep large paint areas intact',100,80)
            chips=node('ShaderNodeTexNoise','Millimetre edge-chip shape',-700,-260)
            chips.inputs['Scale'].default_value=67;chips.inputs['Detail'].default_value=2
            links.new(coords,chips.inputs['Vector'])
            density=ramp(chips.outputs['Fac'],.59,.72,'Sparse, not uniform speckles',-450,-260)
            chip=calc('MULTIPLY',edge,density,'Only local exposed substrate',320,10)
            patch=ramp(broad.outputs['Fac'],.40,.66,'Uneven weathered regions',-700,-470)
            chip=calc('MULTIPLY',chip,patch,'Retain unweathered sections',520,10)
            links.new(chip,bsdf.inputs['Metallic'])
            colour=mix(colour,linear('697273'),chip,'Exposed steel only at chips',720,450)
            if name=='IB_BlueSteel':
                runoff=calc('MULTIPLY',xdist,5,'Local runoff widths',-450,-640)
                runoff=calc('SUBTRACT',1,runoff,'Seam runoff distance',-250,-640)
                runoff=calc('MAXIMUM',runoff,0,'No streaks in quiet panel centres',-50,-640)
                low=node('ShaderNodeMapRange','Lower 45cm runoff only',-700,-830);low.clamp=True
                low.inputs['From Min'].default_value=-.20;low.inputs['From Max'].default_value=.45
                low.inputs['To Min'].default_value=.65;low.inputs['To Max'].default_value=0
                links.new(xyz.outputs['Z'],low.inputs['Value'])
                salt=calc('MULTIPLY',runoff,low.outputs[0],'Lower seam runoff',150,-640)
                salt=calc('MULTIPLY',salt,patch,'Patchy accumulation',350,-640)
                salt=calc('MULTIPLY',salt,.42,'Restrained salt',550,-640)
                colour=mix(colour,linear('8d9084'),salt,'Sparse local salt',940,450)
            pits=node('ShaderNodeTexNoise','Coating microtexture',-700,-1050)
            pits.inputs['Scale'].default_value=140;pits.inputs['Detail'].default_value=1
            links.new(coords,pits.inputs['Vector'])
            bump=node('ShaderNodeBump','Coating microtexture, not tread',730,-140)
            bump.inputs['Strength'].default_value=.12;bump.inputs['Distance'].default_value=.00018
            links.new(pits.outputs['Fac'],bump.inputs['Height']);links.new(bump.outputs['Normal'],bsdf.inputs['Normal'])
        if name=='IB_DeckSteel':
            grain=node('ShaderNodeTexNoise','Steel fine surface only',-900,-260)
            grain.inputs['Scale'].default_value=110;grain.inputs['Detail'].default_value=1
            links.new(coords,grain.inputs['Vector'])
            bump=node('ShaderNodeBump','Fine steel grain under real emboss',730,-140)
            bump.inputs['Strength'].default_value=.08;bump.inputs['Distance'].default_value=.00012
            links.new(grain.outputs['Fac'],bump.inputs['Height']);links.new(bump.outputs['Normal'],bsdf.inputs['Normal'])
        links.new(colour,bsdf.inputs['Base Color'])
        rough=node('ShaderNodeMapRange','Quiet roughness variation',700,-360);rough.clamp=True
        rough.inputs['To Min'].default_value=max(.15,roughness-.04)
        rough.inputs['To Max'].default_value=min(.9,roughness+.05)
        links.new(broad.outputs['Fac'],rough.inputs['Value']);links.new(rough.outputs[0],bsdf.inputs['Roughness'])
        result[name]=mat
    return result
