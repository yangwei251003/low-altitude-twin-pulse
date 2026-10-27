"""Explicit-UV source PBR. Existing approved paint atlas + CC0 physical steel.

No concept projection, image pixel editing or implicit Generated coordinates.
"""
import bpy


def build(images):
    result={}
    for kind in ('PaintSteel','DeckSteel','HardwareSteel'):
        mat=bpy.data.materials.new('CalibrationP2_'+kind);mat.use_nodes=True
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
            # Preserve the original image, but reveal its wear only near physical
            # component corners. Quiet centres no longer repeat long strip scratches.
            eu=op('MINIMUM',ps.outputs['X'],op('SUBTRACT',1,ps.outputs['X']))
            ev=op('MINIMUM',ps.outputs['Y'],op('SUBTRACT',1,ps.outputs['Y']))
            corner=op('MULTIPLY',op('SUBTRACT',1,ramp(eu,.035,.22)),op('SUBTRACT',1,ramp(ev,.035,.22)))
            patch=n.new('ShaderNodeTexNoise');patch.name='LocalizedCornerWeather';patch.inputs['Scale'].default_value=10.;patch.inputs['Detail'].default_value=1.
            links.new(metric,patch.inputs['Vector'])
            corner=op('MULTIPLY',corner,ramp(patch.outputs['Fac'],.25,.7))
            image_weight=op('ADD',.10,op('MULTIPLY',corner,.75))
            color=mix(image_weight,(.035,.10,.115,1),tx.outputs['Color'],'Quiet teal centre, original image wear at corners and cover ends')
            use=n.new('ShaderNodeVertexColor');use.layer_name='SurfaceUse';us=n.new('ShaderNodeSeparateColor');links.new(use.outputs['Color'],us.inputs[0])
            color=mix(op('MULTIPLY',us.outputs['Red'],.28),color,(.025,.03,.029,1),'Darker lower contact band only')
            exposed=op('MULTIPLY',exposed,corner);rust=op('MULTIPLY',rust,corner)
            rough=op('ADD',op('SUBTRACT',.74,op('MULTIPLY',exposed,.18)),op('MULTIPLY',rust,.12))
            metal=op('MULTIPLY',exposed,op('SUBTRACT',1,rust))
            # Shallow paint surface only; atlas brightness is not used as a height map.
            bump=n.new('ShaderNodeBump');bump.inputs['Distance'].default_value=.00015;bump.inputs['Strength'].default_value=.08
            links.new(noise.outputs['Fac'],bump.inputs['Height']);normal=bump.outputs['Normal']
        else:
            st=uv('SteelUV');co=tex('SteelColor',st);ro=tex('SteelRoughness',st);me=tex('SteelMetalness',st);nm=tex('SteelNormalGL',st)
            normal_node=n.new('ShaderNodeNormalMap');normal_node.name='OriginalSteelNormal';normal_node.space='TANGENT';normal_node.uv_map='SteelUV';normal_node.inputs['Strength'].default_value=.20
            links.new(nm.outputs['Color'],normal_node.inputs['Color']);normal=normal_node.outputs['Normal']
            color=mix(.18,(.18,.19,.19,1),co.outputs['Color'],'18 percent original steel colour, subdued broad cloud')
            rough=op('ADD',.55,op('MULTIPLY',ro.outputs['Color'],.28));metal=me.outputs['Color']
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
                distance=op('MINIMUM',op('SUBTRACT',outer,.922),op('SUBTRACT',1.001,outer))
                edge_weather=op('SUBTRACT',1,ramp(distance,.002,.018))
                sparse=n.new('ShaderNodeTexNoise');sparse.name='YellowEdgeWearPatches';sparse.inputs['Scale'].default_value=4.5;sparse.inputs['Detail'].default_value=1.
                links.new(metric,sparse.inputs['Vector'])
                wear=op('MULTIPLY',op('MULTIPLY',ramp(noise.outputs['Fac'],.49,.66),ramp(sparse.outputs['Fac'],.47,.66)),edge_weather)
                paint=op('MULTIPLY',mark,op('SUBTRACT',1,wear))
                color=mix(paint,color,(.50,.25,.008,1),'Saturated warm yellow, quiet centre and local edge chips')
                rough=op('ADD',op('MULTIPLY',op('SUBTRACT',1,paint),rough),op('MULTIPLY',paint,.80));metal=op('MULTIPLY',metal,op('SUBTRACT',1,paint))
                # 70mm diamond cells with alternating 28x5mm ribs. This is
                # source micro-height shading only, not changed collision geometry.
                u=op('MULTIPLY',op('ADD',tx,ty),.70710678);v=op('MULTIPLY',op('SUBTRACT',tx,ty),.70710678)
                cu=op('DIVIDE',u,.07);cv=op('DIVIDE',v,.07)
                fu=op('ABSOLUTE',op('SUBTRACT',op('FRACT',cu),.5));fv=op('ABSOLUTE',op('SUBTRACT',op('FRACT',cv),.5))
                parity=op('PINGPONG',op('ADD',op('FLOOR',cu),op('FLOOR',cv)),1.)
                longu=op('SUBTRACT',1,ramp(fu,.17,.20));shortu=op('SUBTRACT',1,ramp(fu,.024,.036))
                longv=op('SUBTRACT',1,ramp(fv,.17,.20));shortv=op('SUBTRACT',1,ramp(fv,.024,.036))
                rib=op('ADD',op('MULTIPLY',op('MULTIPLY',longu,shortv),op('SUBTRACT',1,parity)),op('MULTIPLY',op('MULTIPLY',shortu,longv),parity))
                use=n.new('ShaderNodeVertexColor');use.layer_name='SurfaceUse';us=n.new('ShaderNodeSeparateColor');links.new(use.outputs['Color'],us.inputs[0])
                rib=op('MULTIPLY',rib,us.outputs['Green'])
                bump=n.new('ShaderNodeBump');bump.name='ManufacturedAntiSlipBump';bump.inputs['Distance'].default_value=.0015;bump.inputs['Strength'].default_value=.70
                put(rib,bump.inputs['Height']);links.new(normal,bump.inputs['Normal']);normal=bump.outputs['Normal']
            else:
                rough=op('ADD',.48,op('MULTIPLY',ro.outputs['Color'],.30))
        bs=n.new('ShaderNodeBsdfPrincipled');bs.name='SourcePrincipled';out=n.new('ShaderNodeOutputMaterial')
        links.new(bs.outputs['BSDF'],out.inputs['Surface'])
        put(color,bs.inputs['Base Color']);put(clamp(rough),bs.inputs['Roughness']);put(clamp(metal),bs.inputs['Metallic'])
        if normal:links.new(normal,bs.inputs['Normal'])
        bs.inputs['Emission Strength'].default_value=0;bs.inputs['Alpha'].default_value=1
        mat['source_role']=kind;mat['no_concept_projection']=True
        result[kind]=mat
    return result
