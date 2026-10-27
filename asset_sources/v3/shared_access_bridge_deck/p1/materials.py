"""Editable source-only I-B materials. Deliberately not exported as baked PBR.

No external textures or copied image pixels. Natural salt runs use low frequency
position masks; deck tread is shallow bump only and has no collision meaning.
Bake/atlas/export is a separate stage after the three source views are reviewed.
"""
import bpy


def linear(hex_color):
    values=[int(hex_color[i:i+2],16)/255 for i in (0,2,4)]
    return tuple(v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in values)+(1,)


def create_materials():
    result={}
    specifications={
        'IB_BlueSteel':('365f64','486b70',.56,.55),
        'IB_DeckSteel':('596267','778084',.72,.47),
        'IB_DarkSteel':('343d42','4c555a',.78,.48),
        'IB_BurnishedSteel':('939a99','b1b5b0',.85,.34),
        'IB_OchreGrip':('b58c43','d0a652',.40,.58),
    }
    for name,(dark,light,metallic,roughness) in specifications.items():
        mat=bpy.data.materials.new(name)
        mat.use_nodes=True
        mat.diffuse_color=linear(dark)
        mat['source_only_procedural']=True
        mat['pbr_bake_status']='not baked; source preview only'
        nodes,links=mat.node_tree.nodes,mat.node_tree.links
        nodes.clear()

        def node(kind,label,x,y):
            n=nodes.new(kind);n.label=label;n.location=(x,y);return n

        def math_node(op,a,b,label,x,y):
            n=node('ShaderNodeMath',label,x,y);n.operation=op
            for index,value in enumerate((a,b)):
                if hasattr(value,'node'): links.new(value,n.inputs[index])
                else:n.inputs[index].default_value=value
            return n.outputs[0]

        output=node('ShaderNodeOutputMaterial','Source material output',1000,0)
        bsdf=node('ShaderNodeBsdfPrincipled','Editable coated metal',760,0)
        bsdf.inputs['Metallic'].default_value=metallic
        bsdf.inputs['Roughness'].default_value=roughness
        links.new(bsdf.outputs['BSDF'],output.inputs['Surface'])
        geometry=node('ShaderNodeNewGeometry','Metres in source studio',-1100,300)
        sep=node('ShaderNodeSeparateXYZ','Height: Blender Z = Godot Y',-900,-250)
        links.new(geometry.outputs['Position'],sep.inputs[0])
        broad=node('ShaderNodeTexNoise','Quiet broad variation',-880,350)
        broad.inputs['Scale'].default_value=1.1
        broad.inputs['Detail'].default_value=2
        broad.inputs['Roughness'].default_value=.6
        links.new(geometry.outputs['Position'],broad.inputs['Vector'])
        base=node('ShaderNodeMixRGB','Low contrast metal colour',-620,350)
        base.inputs[1].default_value=linear(dark)
        base.inputs[2].default_value=linear(light)
        links.new(broad.outputs['Fac'],base.inputs[0])
        colour=base.outputs[0]

        if name in ('IB_BlueSteel','IB_OchreGrip'):
            stretch=node('ShaderNodeVectorMath','Gravity-aligned sparse runs',-880,80)
            stretch.operation='MULTIPLY';stretch.inputs[1].default_value=(11,11,.45)
            links.new(geometry.outputs['Position'],stretch.inputs[0])
            runs=node('ShaderNodeTexNoise','Local runoff irregularity',-650,70)
            runs.inputs['Scale'].default_value=2
            runs.inputs['Detail'].default_value=2
            links.new(stretch.outputs[0],runs.inputs['Vector'])
            ramp=node('ShaderNodeValToRGB','Only a few streaks',-440,60)
            ramp.color_ramp.elements[0].position=.56
            ramp.color_ramp.elements[1].position=.73
            links.new(runs.outputs['Fac'],ramp.inputs[0])
            height=node('ShaderNodeMapRange','Weather mainly below the mid-panel',-650,-240)
            height.clamp=True
            height.inputs['From Min'].default_value=-.28
            height.inputs['From Max'].default_value=.85
            height.inputs['To Min'].default_value=.8
            height.inputs['To Max'].default_value=.05
            links.new(sep.outputs['Z'],height.inputs['Value'])
            mask=math_node('MULTIPLY',ramp.outputs['Color'],height.outputs[0],'Lower-edge salt',-180,40)
            mask=math_node('MULTIPLY',mask,broad.outputs['Fac'],'Patchy deposits, quiet areas retained',20,40)
            mask=math_node('MULTIPLY',mask,.48,'Restrained salt colour',200,40)
            salt=node('ShaderNodeMixRGB','Salt at seams and low edges',420,300)
            salt.inputs[2].default_value=linear('aaa99b')
            links.new(colour,salt.inputs[1]);links.new(mask,salt.inputs[0])
            colour=salt.outputs[0]
            # Fine paint pitting is shallow source bump; no false deep holes.
            pits=node('ShaderNodeTexNoise','Paint micropitting',-420,-500)
            pits.inputs['Scale'].default_value=155
            pits.inputs['Detail'].default_value=1
            links.new(geometry.outputs['Position'],pits.inputs['Vector'])
            bump=node('ShaderNodeBump','Submillimetre paint texture',420,-300)
            bump.inputs['Strength'].default_value=.16
            bump.inputs['Distance'].default_value=.00035
            links.new(pits.outputs['Fac'],bump.inputs['Height'])
            links.new(bump.outputs['Normal'],bsdf.inputs['Normal'])

        if name=='IB_DeckSteel':
            uv=node('ShaderNodeUVMap','Explicit SurfaceUV, source metre projection',-880,-40)
            uv.uv_map='SurfaceUV'
            rotate=node('ShaderNodeVectorRotate','Diagonal shallow tread',-650,-40)
            rotate.rotation_type='AXIS_ANGLE'
            rotate.inputs['Axis'].default_value=(0,0,1)
            rotate.inputs['Angle'].default_value=.78539816339
            links.new(uv.outputs['UV'],rotate.inputs['Vector'])
            wave_x=node('ShaderNodeTexWave','Short raised treads X',-430,-40)
            wave_y=node('ShaderNodeTexWave','Short raised treads Y',-430,-220)
            for wave,direction in ((wave_x,'X'),(wave_y,'Y')):
                wave.wave_type='BANDS';wave.bands_direction=direction
                wave.wave_profile='SIN'
                wave.inputs['Scale'].default_value=8.5
                wave.inputs['Distortion'].default_value=0
                links.new(rotate.outputs['Vector'],wave.inputs['Vector'])
            wx=math_node('GREATER_THAN',wave_x.outputs['Fac'],.80,'Narrow tread',-170,-50)
            wy=math_node('GREATER_THAN',wave_y.outputs['Fac'],.55,'Separated tread length',-170,-220)
            tread=math_node('MULTIPLY',wx,wy,'Broken diagonal tread, not a deep grid',40,-60)
            bump=node('ShaderNodeBump','1mm source normal impression',420,-160)
            bump.inputs['Strength'].default_value=.32
            bump.inputs['Distance'].default_value=.001
            links.new(tread,bump.inputs['Height']);links.new(bump.outputs['Normal'],bsdf.inputs['Normal'])
        links.new(colour,bsdf.inputs['Base Color'])
        # Broad roughness variation follows the same material scale.
        rough=node('ShaderNodeMapRange','Subtle roughness variation',220,-500)
        rough.clamp=True
        rough.inputs['To Min'].default_value=max(.1,roughness-.07)
        rough.inputs['To Max'].default_value=min(.95,roughness+.08)
        links.new(broad.outputs['Fac'],rough.inputs['Value'])
        links.new(rough.outputs[0],bsdf.inputs['Roughness'])
        result[name]=mat
    return result
