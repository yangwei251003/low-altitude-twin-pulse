"""Fixed landing source finish, adapted from P4 causal finish fields, anchored in explicit authored metric UVs.

No object/generated/world-position coordinates. Named UVs and WeatherUse corner
attributes can be retained on an evaluated bake proxy; source PBR inputs can be
baked to one distinct DeliveryBakeUV without changing the visible source masks.
This module does not perform or claim that bake.
"""
import json
from pathlib import Path
import bpy


PLAN=json.loads(Path(__file__).with_name('finish_layout.json').read_text(encoding='utf-8'))


def linear(hex_color):
    values=[int(hex_color[i:i+2],16)/255 for i in (0,2,4)]
    return tuple(v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in values)+(1,)


def create_materials(tread_image,surface_mask):
    specifications={
        'IB_BlueSteel':('12343d','1b424a',0.0,.70),
        'IB_DeckSteel':('323a40','465055',.68,.61),
    }
    image_path=Path(__file__).parent/PLAN['paint_image']['path']
    import hashlib
    assert hashlib.sha256(image_path.read_bytes()).hexdigest()==PLAN['paint_image']['sha256']
    paint_image=bpy.data.images.load(str(image_path),check_existing=False)
    paint_image.colorspace_settings.name='sRGB'
    _=tuple(paint_image.pixels[:4])
    assert paint_image.has_data and list(paint_image.size)==PLAN['paint_image']['pixels']
    result={}
    for name,(dark,light,metallic,roughness) in specifications.items():
        mat=bpy.data.materials.new(name);mat.use_nodes=True;mat.diffuse_color=linear(dark)
        mat['pbr_bake_status']='Source only: explicit UV/corner attributes, not yet baked.'
        mat['material_scope']='Authored weathering response, no emission, no geometry displacement.'
        mat['coating_model']='dielectric with local exposed substrate' if metallic==0 else 'exposed steel'
        nodes,links=mat.node_tree.nodes,mat.node_tree.links;nodes.clear()

        def node(kind,label):
            n=nodes.new(kind);n.label=label;n.name=label
            index=len(nodes)-1;n.location=((index%8)*210,-(index//8)*180)
            return n

        def put(value,socket):
            if hasattr(value,'node'):links.new(value,socket)
            else:socket.default_value=value

        def op(kind,a,b=0,label=''):
            n=node('ShaderNodeMath',label or kind);n.operation=kind
            put(a,n.inputs[0]);put(b,n.inputs[1]);return n.outputs[0]

        def clamp(value):return op('MINIMUM',1,op('MAXIMUM',0,value))
        def add(a,b):return op('ADD',a,b)
        def mul(a,b):return op('MULTIPLY',a,b)
        def sub(a,b):return op('SUBTRACT',a,b)

        def ramp(value,lo,hi,label):
            n=node('ShaderNodeMapRange',label);n.clamp=True;n.interpolation_type='SMOOTHSTEP'
            put(value,n.inputs['Value']);n.inputs['From Min'].default_value=lo
            n.inputs['From Max'].default_value=hi;return n.outputs['Result']

        def mix(f,a,b,label):
            n=node('ShaderNodeMixRGB',label);put(f,n.inputs[0]);put(a,n.inputs[1]);put(b,n.inputs[2])
            return n.outputs[0]

        def vec(kind,a,b=None,label=''):
            n=node('ShaderNodeVectorMath',label or kind);n.operation=kind;put(a,n.inputs[0])
            if b is not None:put(b,n.inputs[1])
            return n.outputs['Value' if kind=='LENGTH' else 'Vector']

        uxz=node('ShaderNodeUVMap','Explicit source XZ metres');uxz.uv_map='SourceXZ'
        uy=node('ShaderNodeUVMap','Explicit source Y metres');uy.uv_map='SourceY'
        sxz=node('ShaderNodeSeparateXYZ','Asset X / Z');links.new(uxz.outputs['UV'],sxz.inputs[0])
        sy=node('ShaderNodeSeparateXYZ','Asset Y');links.new(uy.outputs['UV'],sy.inputs[0])
        x,y,z=sxz.outputs['X'],sy.outputs['X'],sxz.outputs['Y']
        combine=node('ShaderNodeCombineXYZ','Authored metre coordinates')
        for value,axis in ((x,'X'),(y,'Y'),(z,'Z')):put(value,combine.inputs[axis])
        coords=combine.outputs[0]
        usage=node('ShaderNodeVertexColor','Explicit surface purpose');usage.layer_name='WeatherUse'
        uses=node('ShaderNodeSeparateColor','Guard / deck / grip / carriage');uses.mode='RGB'
        links.new(usage.outputs['Color'],uses.inputs[0])
        guard,top,grip=uses.outputs['Red'],uses.outputs['Green'],uses.outputs['Blue']
        carriage=usage.outputs['Alpha']

        def noise(vector,scale,detail,label):
            n=node('ShaderNodeTexNoise',label);n.inputs['Scale'].default_value=scale
            n.inputs['Detail'].default_value=detail;put(vector,n.inputs['Vector']);return n.outputs['Fac']

        broad=noise(coords,.7,1.0,'Quiet metre-scale tone')
        irregular=noise(coords,19,2.0,'Centimetre weather edge breakup')
        micro=noise(coords,120,1.0,'Very shallow micro finish')

        def ellipse(row,label,broken=True):
            local=vec('SUBTRACT',coords,tuple(row['c']),label+' center')
            scaled=vec('MULTIPLY',local,tuple(1/v for v in row['r']),label+' actual radii')
            radius=vec('LENGTH',scaled,label=label+' distance')
            edge=sub(1,radius)
            if broken:edge=add(edge,mul(sub(irregular,.5),.34))
            return mul(ramp(edge,0,.30,label+' irregular finite edge'),row.get('strength',1))

        def patches(rows,label):
            value=0
            for i,row in enumerate(rows):value=op('MAXIMUM',value,ellipse(row,label+str(i)))
            return value

        colour=mix(broad,linear(dark),linear(light),'Restrained unweathered material')
        rough=add(roughness,mul(sub(broad,.5),.045))
        metal=metallic;height=mul(micro,.08);bump_distance=.00025;bump_strength=.16

        if name=='IB_BlueSteel':
            puv=node('ShaderNodeUVMap','One authored full guard UV, no repeated hardware panel')
            puv.uv_map='PaintPanelUV'
            texture=node('ShaderNodeTexImage','Unedited native painted steel image')
            texture.image=paint_image;texture.extension='EXTEND';texture.interpolation='Linear'
            links.new(puv.outputs['UV'],texture.inputs['Vector'])
            pxy=node('ShaderNodeSeparateXYZ','Guard UV height')
            links.new(puv.outputs['UV'],pxy.inputs[0])
            image_weight=add(.58,mul(ramp(pxy.outputs['Y'],.08,.60,'More intact lower coating'),.06))
            colour=mix(image_weight,linear('163c44'),texture.outputs['Color'],'58 to 64 percent original image plus intact teal')
            channels=node('ShaderNodeSeparateColor','Authored response classification only');channels.mode='RGB'
            links.new(texture.outputs['Color'],channels.inputs[0])
            red,green,blue=channels.outputs['Red'],channels.outputs['Green'],channels.outputs['Blue']
            chroma=sub(op('MAXIMUM',red,op('MAXIMUM',green,blue)),op('MINIMUM',red,op('MINIMUM',green,blue)))
            neutral=sub(1,ramp(chroma,.012,.050,'Low chroma exposed substrate candidate'))
            oxide=ramp(sub(red,mul(green,1.20)),.002,.035,'Brown oxide candidate from original color')
            lower=sub(1,ramp(pxy.outputs['Y'],.40,.80,'Response only within low weathered coating'))
            exposed=mul(image_weight,mul(lower,mul(neutral,sub(1,oxide))))
            metal=mul(exposed,.75)
            rough=add(sub(.71,mul(exposed,.12)),mul(mul(oxide,lower),.12))
            height=mul(mul(oxide,lower),.12);bump_distance=.00025;bump_strength=.10
        elif name=='IB_OchreGrip':
            wear=mul(grip,patches(PLAN['grip_wear'],'Actual hand contact '))
            wear=mul(wear,ramp(irregular,.26,.58,'Ragged paint loss at grasp'))
            colour=mix(wear,colour,linear('72766b'),'Exposed grip substrate, retain yellow outside contact')
            metal=mul(wear,.94);rough=sub(rough,mul(wear,.30));height=sub(height,mul(wear,.22))
        elif name=='IB_DeckSteel':
            tuv=node('ShaderNodeUVMap','Same UV as actual normal bake');tuv.uv_map='TreadUV'
            mask=node('ShaderNodeTexImage','High geometry semantic face bake');mask.image=surface_mask
            mask.extension='REPEAT';mask.interpolation='Linear';links.new(tuv.outputs['UV'],mask.inputs['Vector'])
            channels=node('ShaderNodeSeparateColor','Top / slope / recess');channels.mode='RGB';links.new(mask.outputs['Color'],channels.inputs[0])
            crest=mul(top,channels.outputs['Red']);slope=mul(top,channels.outputs['Green']);recess=mul(top,channels.outputs['Blue'])
            # Two irregular real walking paths; finite dirt and polishing, no white albedo stripes.
            wear=0
            for offset,phase,width in [(-.48,.4,.24),(.38,2.1,.29)]:
                center=add(offset,mul(op('SINE',add(mul(x,.75),phase)),.12))
                distance=op('ABSOLUTE',sub(z,center))
                band=sub(1,ramp(distance,width,width+.24,'Soft irregular traffic edge'))
                breakup=ramp(noise(vec('MULTIPLY',coords,(.42,1,1.3)),1,1.5,'Uneven boot-polished patches'),.31,.67,'Patch support')
                wear=op('MAXIMUM',wear,mul(band,breakup))
            wear=mul(wear,top)
            pu=node('ShaderNodeUVMap','Plate corner actual metres');pu.uv_map='PlateMetres'
            ps=node('ShaderNodeUVMap','Actual plate span metres');ps.uv_map='PlateSize'
            xy=node('ShaderNodeSeparateXYZ','Plate point');links.new(pu.outputs[0],xy.inputs[0])
            wh=node('ShaderNodeSeparateXYZ','Plate span');links.new(ps.outputs[0],wh.inputs[0])
            u,v=xy.outputs['X'],xy.outputs['Y'];w,h=wh.outputs['X'],wh.outputs['Y']
            dx=op('MINIMUM',op('ABSOLUTE',sub(u,.045)),op('ABSOLUTE',sub(u,sub(w,.045))))
            dz=op('MINIMUM',op('ABSOLUTE',sub(v,.045)),op('ABSOLUTE',sub(v,sub(h,.045))))
            radius=op('SQRT',add(mul(dx,dx),mul(dz,dz)))
            bolt=mul(top,mul(sub(1,ramp(radius,.026,.078,'Finite fixing contact wear')),ramp(radius,.014,.025,'Outside real fastener')))
            edge=op('MINIMUM',op('MINIMUM',u,sub(w,u)),op('MINIMUM',v,sub(h,v)))
            seam=mul(top,sub(1,ramp(edge,.008,.045,'Grime restricted to actual plate joint')))
            dust=mul(recess,mul(sub(1,mul(wear,.80)),add(.10,mul(broad,.13))))
            colour=mix(dust,colour,linear('333c39'),'Fine recess dust, without false black cavities')
            colour=mix(mul(crest,add(.62,mul(wear,.20))),colour,linear('737b78'),'Bare steel polished crest, never white')
            colour=mix(mul(slope,.20),colour,linear('48524f'),'Edge abrasion uses same geometric tile')
            colour=mix(mul(wear,.14),colour,linear('56605b'),'Uneven walking polish remains steel')
            colour=mix(mul(seam,.35),colour,linear('252d2b'),'Local seam accumulation')
            colour=mix(mul(bolt,.25),colour,linear('646c65'),'Contact rings around actual corner fixings')
            rough=sub(add(.65,mul(dust,.16)),mul(wear,.13))
            rough=sub(rough,mul(crest,.30));rough=sub(rough,mul(slope,.12));rough=sub(rough,mul(bolt,.12))
            rough=add(rough,mul(seam,.08));metal=sub(.68,mul(dust,.28));height=mul(micro,.08)
            bump_distance=.00025
        elif name in ('IB_DarkSteel','IB_BurnishedSteel'):
            oil=0;spec=PLAN['bearing_oil']
            for xc in spec['axle_centers_x']:
                for zc in spec['wheel_centers_z']:
                    for dx in spec['side_offsets_x']:
                        row={'c':[xc+dx,spec['axis_y'],zc],
                             'r':[spec['thickness_m'],spec['radius_m'],spec['radius_m']], 'strength':.88}
                        oil=op('MAXIMUM',oil,ellipse(row,'Grease at real axle'))
            oil=mul(carriage,oil)
            colour=mix(oil,colour,linear('131a19'),'Local axle grease, running rims retain metal')
            rough=sub(rough,mul(oil,.22));metal=mul(metal,sub(1,mul(oil,.80)))
            height=add(height,mul(oil,.12))

        bsdf=node('ShaderNodeBsdfPrincipled','P4_Principled')
        put(colour,bsdf.inputs['Base Color']);put(clamp(rough),bsdf.inputs['Roughness'])
        put(clamp(metal),bsdf.inputs['Metallic']);bsdf.inputs['IOR'].default_value=1.48
        bsdf.inputs['Alpha'].default_value=1;bsdf.inputs['Emission Strength'].default_value=0
        bump=node('ShaderNodeBump','Submillimetre finish over preserved tread normal')
        bump.inputs['Strength'].default_value=bump_strength;bump.inputs['Distance'].default_value=bump_distance
        put(height,bump.inputs['Height']);links.new(bump.outputs['Normal'],bsdf.inputs['Normal'])
        if name=='IB_DeckSteel':
            tuv=node('ShaderNodeUVMap','Explicit metric tread period');tuv.uv_map='TreadUV'
            image=node('ShaderNodeTexImage','Actual selected-to-active 1.8mm tread bake')
            image.image=tread_image;image.interpolation='Linear';image.extension='REPEAT'
            links.new(tuv.outputs['UV'],image.inputs['Vector'])
            nm=node('ShaderNodeNormalMap','Baked tangent frame for TreadUV');nm.uv_map='TreadUV'
            links.new(image.outputs['Color'],nm.inputs['Color']);put(top,nm.inputs['Strength'])
            links.new(nm.outputs['Normal'],bump.inputs['Normal'])
        out=node('ShaderNodeOutputMaterial','P4_Output');links.new(bsdf.outputs[0],out.inputs['Surface'])
        mat['maximum_source_bump_distance_m']=bump_distance
        result[name]=mat
    return result


def audit_materials(materials):
    """Read active shader inputs: no implicit/object-dependent source coordinates."""
    rows=[]
    for mat in materials.values():
        output=next(n for n in mat.node_tree.nodes if n.type=='OUTPUT_MATERIAL')
        pending=[output];seen=set();uvs=set();attributes=set()
        while pending:
            node=pending.pop()
            if node.name in seen:continue
            seen.add(node.name)
            assert node.type not in {'TEX_COORD','NEW_GEOMETRY','OBJECT_INFO'},(mat.name,node.name)
            if node.type.startswith('TEX_') and 'Vector' in node.inputs:
                assert node.inputs['Vector'].is_linked,(mat.name,node.name,'implicit vector')
            if node.type=='UVMAP':
                assert node.uv_map in {'SourceXZ','SourceY','PaintPanelUV','TreadUV','PlateMetres','PlateSize'};uvs.add(node.uv_map)
            if node.type=='VERTEX_COLOR':
                assert node.layer_name=='WeatherUse';attributes.add(node.layer_name)
            pending.extend(link.from_node for socket in node.inputs for link in socket.links)
        if mat.name=='IB_BlueSteel':
            assert uvs=={'PaintPanelUV'} and not attributes
        else:
            assert uvs=={'SourceXZ','SourceY','TreadUV','PlateMetres','PlateSize'} and attributes=={'WeatherUse'}
        rows.append({'material':mat.name,'active_node_count':len(seen),
                     'explicit_uvs':sorted(uvs),'corner_attributes':sorted(attributes),
                     'no_transform_or_implicit_coordinates':True,'baked':False})
    return rows
