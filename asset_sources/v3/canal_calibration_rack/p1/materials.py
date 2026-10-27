"""Explicit-UV source PBR. Existing approved paint atlas + CC0 physical steel.

No concept projection, image pixel editing or implicit Generated coordinates.
"""
import bpy


def build(images):
    result={}
    for kind in ('PaintSteel','DeckSteel','HardwareSteel'):
        mat=bpy.data.materials.new('Calibration_'+kind);mat.use_nodes=True
        n=mat.node_tree.nodes;n.clear();links=mat.node_tree.links
        def put(value,socket):
            if hasattr(value,'node'):links.new(value,socket)
            else:socket.default_value=value
        def op(operation,a,b=0):
            node=n.new('ShaderNodeMath');node.operation=operation
            put(a,node.inputs[0]);put(b,node.inputs[1]);return node.outputs[0]
        def mix(f,a,b,label=''):
            node=n.new('ShaderNodeMixRGB');node.label=label
            for value,socket in zip((f,a,b),node.inputs):put(value,socket)
            return node.outputs[0]
        def clamp(a):return op('MINIMUM',1.,op('MAXIMUM',0.,a))
        def ramp(a,lo,hi):return clamp(op('DIVIDE',op('SUBTRACT',a,lo),hi-lo))
        def uv(name):
            node=n.new('ShaderNodeUVMap');node.uv_map=name;return node.outputs[0]
        def tex(name,vector):
            node=n.new('ShaderNodeTexImage');node.name=name;node.image=images[name]
            node.extension='EXTEND' if name=='PaintAtlas' else 'REPEAT'
            links.new(vector,node.inputs['Vector']);return node
        metric=uv('MetricUV');split=n.new('ShaderNodeSeparateXYZ');links.new(metric,split.inputs[0])
        x,y=split.outputs['X'],split.outputs['Y']
        panel=uv('PanelUV');ps=n.new('ShaderNodeSeparateXYZ');links.new(panel,ps.inputs[0])
        edge=op('MINIMUM',op('MINIMUM',ps.outputs['X'],op('SUBTRACT',1,ps.outputs['X'])),op('MINIMUM',ps.outputs['Y'],op('SUBTRACT',1,ps.outputs['Y'])))
        noise=n.new('ShaderNodeTexNoise');noise.inputs['Scale'].default_value=15.;noise.inputs['Detail'].default_value=2.
        links.new(metric,noise.inputs['Vector'])
        color=(.1,.1,.1,1);rough=.6;metal=0.;normal=None
        if kind=='PaintSteel':
            tx=tex('PaintAtlas',uv('FinishUV'));gray=n.new('ShaderNodeRGBToBW');links.new(tx.outputs['Color'],gray.inputs[0])
            rgb=n.new('ShaderNodeSeparateColor');links.new(tx.outputs['Color'],rgb.inputs[0])
            neutral=op('SUBTRACT',1,ramp(op('SUBTRACT',op('MAXIMUM',rgb.outputs[0],rgb.outputs[1]),op('MINIMUM',rgb.outputs[0],rgb.outputs[1])),.02,.16))
            exposed=op('MULTIPLY',ramp(gray.outputs[0],.09,.3),neutral)
            rust=op('MULTIPLY',ramp(op('SUBTRACT',rgb.outputs[0],op('MULTIPLY',rgb.outputs[1],1.3)),.01,.09),op('SUBTRACT',1,ramp(gray.outputs[0],.3,.5)))
            color=mix(.94,(.03,.08,.09,1),tx.outputs['Color'],'Approved teal paint atlas, cropped to component width')
            use=n.new('ShaderNodeVertexColor');use.layer_name='SurfaceUse';us=n.new('ShaderNodeSeparateColor');links.new(use.outputs['Color'],us.inputs[0])
            color=mix(op('MULTIPLY',us.outputs['Red'],.28),color,(.025,.03,.029,1),'Darker lower contact band only')
            rough=op('ADD',op('SUBTRACT',.72,op('MULTIPLY',exposed,.2)),op('MULTIPLY',rust,.16))
            metal=op('MULTIPLY',exposed,op('SUBTRACT',1,rust))
            # Shallow paint surface only; atlas brightness is not used as a height map.
            bump=n.new('ShaderNodeBump');bump.inputs['Distance'].default_value=.00015;bump.inputs['Strength'].default_value=.08
            links.new(noise.outputs['Fac'],bump.inputs['Height']);normal=bump.outputs['Normal']
        else:
            st=uv('SteelUV');co=tex('SteelColor',st);ro=tex('SteelRoughness',st);me=tex('SteelMetalness',st);nm=tex('SteelNormalGL',st)
            normal_node=n.new('ShaderNodeNormalMap');normal_node.space='TANGENT';normal_node.uv_map='SteelUV';normal_node.inputs['Strength'].default_value=.45
            links.new(nm.outputs['Color'],normal_node.inputs['Color']);normal=normal_node.outputs['Normal']
            color=mix(.35,co.outputs['Color'],(.25,.235,.215,1),'Warm grey physical steel, no painted white roof bloom')
            rough=op('ADD',.18,op('MULTIPLY',ro.outputs['Color'],.68));metal=me.outputs['Color']
            if kind=='DeckSteel':
                # Physical top coordinates, not one duplicated yellow frame per plate.
                coord=uv('TopUV');tp=n.new('ShaderNodeSeparateXYZ');links.new(coord,tp.inputs[0])
                tx,ty=tp.outputs['X'],tp.outputs['Y'];ax=op('ABSOLUTE',tx);ay=op('ABSOLUTE',ty)
                outer=op('MAXIMUM',ax,ay)
                band=op('MULTIPLY',op('GREATER_THAN',outer,.922),op('LESS_THAN',outer,1.001))
                # Two simple alignment ticks, no text or invented controls.
                tickx=op('LESS_THAN',op('ABSOLUTE',op('SUBTRACT',tx,.10)),.095)
                tickya=op('LESS_THAN',op('ABSOLUTE',op('SUBTRACT',ty,.69)),.014)
                tickyb=op('LESS_THAN',op('ABSOLUTE',op('ADD',ty,.69)),.014)
                ticks=op('MULTIPLY',tickx,op('MAXIMUM',tickya,tickyb))
                mark=op('MAXIMUM',band,ticks)
                wear=op('MULTIPLY',ramp(noise.outputs['Fac'],.64,.77),op('SUBTRACT',1,ramp(edge,0.,.16)))
                paint=op('MULTIPLY',mark,op('SUBTRACT',1,wear))
                color=mix(paint,color,(.62,.36,.035,1),'Worn but broad 79mm safety marking')
                rough=op('ADD',op('MULTIPLY',op('SUBTRACT',1,paint),rough),op('MULTIPLY',paint,.72));metal=op('MULTIPLY',metal,op('SUBTRACT',1,paint))
                # 160mm sparse alternating anti-slip ribs, shading only, <=1.1mm.
                u=op('MULTIPLY',op('ADD',tx,ty),.70710678);v=op('MULTIPLY',op('SUBTRACT',tx,ty),.70710678)
                fu=op('SUBTRACT',op('FRACT',op('DIVIDE',u,.16)),.5);fv=op('SUBTRACT',op('FRACT',op('DIVIDE',v,.16)),.5)
                rib=op('MULTIPLY',op('LESS_THAN',op('ABSOLUTE',fu),.19),op('LESS_THAN',op('ABSOLUTE',fv),.033))
                use=n.new('ShaderNodeVertexColor');use.layer_name='SurfaceUse';us=n.new('ShaderNodeSeparateColor');links.new(use.outputs['Color'],us.inputs[0])
                rib=op('MULTIPLY',rib,us.outputs['Green'])
                bump=n.new('ShaderNodeBump');bump.inputs['Distance'].default_value=.0011;bump.inputs['Strength'].default_value=.32
                put(rib,bump.inputs['Height']);links.new(normal,bump.inputs['Normal']);normal=bump.outputs['Normal']
            else:
                rough=op('ADD',.15,op('MULTIPLY',ro.outputs['Color'],.6))
        bs=n.new('ShaderNodeBsdfPrincipled');bs.name='SourcePrincipled';out=n.new('ShaderNodeOutputMaterial')
        links.new(bs.outputs['BSDF'],out.inputs['Surface'])
        put(color,bs.inputs['Base Color']);put(clamp(rough),bs.inputs['Roughness']);put(clamp(metal),bs.inputs['Metallic'])
        if normal:links.new(normal,bs.inputs['Normal'])
        bs.inputs['Emission Strength'].default_value=0;bs.inputs['Alpha'].default_value=1
        mat['source_role']=kind;mat['no_concept_projection']=True
        result[kind]=mat
    return result
