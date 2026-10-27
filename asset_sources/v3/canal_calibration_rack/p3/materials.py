"""Explicit-UV source PBR. Existing approved paint atlas + CC0 physical steel.

No concept projection, image pixel editing or implicit Generated coordinates.
"""
import bpy


def build(images):
    result={}
    for kind in ('PaintSteel','DeckSteel','HardwareSteel'):
        mat=bpy.data.materials.new('CalibrationP3_'+kind);mat.use_nodes=True
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
        color=(.1,.1,.1,1);rough=.6;metal=0.;normal=None;specular=.5
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
            image_weight=op('ADD',.10,op('MULTIPLY',corner,.18))
            color=mix(image_weight,(.012,.035,.040,1),tx.outputs['Color'],'Dark teal paint with restrained original variation')
            use=n.new('ShaderNodeVertexColor');use.layer_name='SurfaceUse';us=n.new('ShaderNodeSeparateColor');links.new(use.outputs['Color'],us.inputs[0])
            color=mix(op('MULTIPLY',us.outputs['Red'],.28),color,(.025,.03,.029,1),'Darker lower contact band only')
            # Discontinuous real component edge/corner wear, never a full-width
            # horizontal colour strip. The existing UVs remain unchanged.
            edge_zone=op('SUBTRACT',1,ramp(edge,.012,.065))
            coarse=ramp(patch.outputs['Fac'],.43,.64)
            broken=ramp(noise.outputs['Fac'],.48,.63)
            chips=op('MULTIPLY',op('MAXIMUM',corner,op('MULTIPLY',edge_zone,coarse)),broken)
            color=mix(chips,color,(.13,.145,.14,1),'Exposed steel at irregular component-edge chips')
            rust=op('MULTIPLY',chips,op('SUBTRACT',1,ramp(patch.outputs['Fac'],.52,.71)))
            color=mix(op('MULTIPLY',rust,.65),color,(.085,.036,.012,1),'Sparse oxidised chip boundaries')
            # Two unequal traces originate below the actual front upper bolts
            # at x=-.485 and x=.235, y=.197. Gate by front face normal.
            geom=n.new('ShaderNodeNewGeometry');gs=n.new('ShaderNodeSeparateXYZ');links.new(geom.outputs['Normal'],gs.inputs[0])
            front=op('LESS_THAN',gs.outputs['Y'],-.75)
            drips=[]
            for centre,width,bottom in ((-.485,.012,.083),(.235,.009,.116)):
                t=ramp(y,bottom,.18)
                w=op('MULTIPLY',width,op('ADD',.25,op('MULTIPLY',t,.75)))
                sideways=op('SUBTRACT',1,ramp(op('DIVIDE',op('ABSOLUTE',op('SUBTRACT',x,centre)),w),.25,1.))
                drips.append(op('MULTIPLY',sideways,op('MULTIPLY',t,op('SUBTRACT',1,ramp(y,.178,.19)))))
            drip=op('MULTIPLY',front,op('MULTIPLY',op('MAXIMUM',*drips),.65))
            color=mix(drip,color,(.09,.037,.013,1),'Two short unequal bolt-sourced oxidation traces')
            rough=op('ADD',op('SUBTRACT',.74,op('MULTIPLY',chips,.13)),op('MULTIPLY',op('MAXIMUM',rust,drip),.13))
            metal=op('MULTIPLY',chips,op('SUBTRACT',1,op('MAXIMUM',rust,drip)));specular=.28
            # Shallow paint surface only; atlas brightness is not used as a height map.
            bump=n.new('ShaderNodeBump');bump.inputs['Distance'].default_value=.00015;bump.inputs['Strength'].default_value=.08
            links.new(noise.outputs['Fac'],bump.inputs['Height']);normal=bump.outputs['Normal']
        else:
            st=uv('SteelUV');co=tex('SteelColor',st);ro=tex('SteelRoughness',st);me=tex('SteelMetalness',st);nm=tex('SteelNormalGL',st)
            normal_node=n.new('ShaderNodeNormalMap');normal_node.name='OriginalSteelNormal';normal_node.space='TANGENT';normal_node.uv_map='SteelUV';normal_node.inputs['Strength'].default_value=.20
            links.new(nm.outputs['Color'],normal_node.inputs['Color']);normal=normal_node.outputs['Normal']
            # Measured original linear mean is ~(.671,.723,.783). A bounded
            # multiplier keeps its detail instead of replacing it with flat grey.
            scale=n.new('ShaderNodeMixRGB');scale.name='DarkSteelReflectance';scale.blend_type='MULTIPLY';scale.inputs[0].default_value=1
            links.new(co.outputs['Color'],scale.inputs[1]);scale.inputs[2].default_value=(.075,.075,.070,1);color=scale.outputs[0]
            rough=op('ADD',.62,op('MULTIPLY',ro.outputs['Color'],.80));metal=me.outputs['Color']
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
                color=mix(paint,color,(.32,.13,.0015,1),'Lower-value saturated industrial yellow under fixed AgX lighting')
                rough=op('ADD',op('MULTIPLY',op('SUBTRACT',1,paint),rough),op('MULTIPLY',paint,.80));metal=op('MULTIPLY',metal,op('SUBTRACT',1,paint))
                specular=op('ADD',op('MULTIPLY',op('SUBTRACT',1,paint),.5),op('MULTIPLY',paint,.12))
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
                bump=n.new('ShaderNodeBump');bump.name='ManufacturedAntiSlipBump';bump.inputs['Distance'].default_value=.0020;bump.inputs['Strength'].default_value=.85
                put(rib,bump.inputs['Height']);links.new(normal,bump.inputs['Normal']);normal=bump.outputs['Normal']
            else:
                color=mix(.25,color,co.outputs['Color'],'Hardware retains a brighter metal response than the old deck')
                rough=op('ADD',.48,op('MULTIPLY',ro.outputs['Color'],.50))
        bs=n.new('ShaderNodeBsdfPrincipled');bs.name='SourcePrincipled';out=n.new('ShaderNodeOutputMaterial')
        links.new(bs.outputs['BSDF'],out.inputs['Surface'])
        put(color,bs.inputs['Base Color']);put(clamp(rough),bs.inputs['Roughness']);put(clamp(metal),bs.inputs['Metallic'])
        put(specular,bs.inputs['Specular IOR Level'])
        if normal:links.new(normal,bs.inputs['Normal'])
        bs.inputs['Emission Strength'].default_value=0;bs.inputs['Alpha'].default_value=1
        mat['source_role']=kind;mat['no_concept_projection']=True
        result[kind]=mat
    return result
