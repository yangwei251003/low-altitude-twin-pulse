"""P3 causal finish fields, anchored in explicit authored metric UVs.

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


def create_materials():
    specifications={
        'IB_BlueSteel':('12343d','1b424a',0.0,.70),
        'IB_DeckSteel':('323a40','465055',.68,.61),
        'IB_DarkSteel':('242c2f','374044',.82,.59),
        'IB_BurnishedSteel':('78817f','9da59f',.92,.37),
        'IB_OchreGrip':('987037','b18b46',0.0,.68),
    }
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
            salt=mul(guard,patches(PLAN['salt'],'Salt lower edge '))
            # Sparse finite pools, not repeated waves at every rib.
            salt=mul(salt,ramp(irregular,.22,.70,'Broken mineral crust coverage'))
            rust=0
            for i,row in enumerate(PLAN['rust_fasteners']):
                # The authored tail begins at a real .09/.91m rivet and drops.
                tail={'c':[row['x']+row['drift']/2,row['y']-row['length']/2,row['z']],
                      'r':[row['width'],row['length']/2+.009,.11],'strength':row['strength']}
                head={'c':[row['x'],row['y'],row['z']],
                      'r':[.026,.025,.11],'strength':row['strength']*.75}
                rust=op('MAXIMUM',rust,op('MAXIMUM',ellipse(tail,'Rivet runoff '+str(i)),ellipse(head,'Rivet oxide '+str(i))))
            rust=mul(guard,rust)
            chip=mul(guard,patches(PLAN['edge_chips'],'Fold coating loss '))
            chip=mul(chip,ramp(irregular,.35,.69,'Interrupted edge chips'))
            colour=mix(chip,colour,linear('65716e'),'Metal only where coating is lost')
            colour=mix(salt,colour,linear('969b89'),'Dry salt accumulation at selected low sections')
            colour=mix(rust,colour,linear('795035'),'Oxide from selected fasteners')
            metal=mul(chip,mul(sub(1,salt),sub(1,rust)))
            rough=add(sub(rough,mul(chip,.16)),add(mul(salt,.15),mul(rust,.16)))
            height=add(height,sub(mul(salt,.35),mul(chip,.15)))
            bump_distance=.0006
        elif name=='IB_OchreGrip':
            wear=mul(grip,patches(PLAN['grip_wear'],'Actual hand contact '))
            wear=mul(wear,ramp(irregular,.26,.58,'Ragged paint loss at grasp'))
            colour=mix(wear,colour,linear('72766b'),'Exposed grip substrate, retain yellow outside contact')
            metal=mul(wear,.94);rough=sub(rough,mul(wear,.30));height=sub(height,mul(wear,.22))
        elif name=='IB_DeckSteel':
            lane_center=add(.10,mul(op('SINE',mul(x,.80)),.14))
            lane=sub(1,ramp(op('ABSOLUTE',sub(z,lane_center)),.33,.86,'East-west walking lane'))
            lane=mul(top,mul(lane,add(.60,mul(broad,.40))))
            scuff=mul(top,patches(PLAN['deck_scuffs'],'Finite boot scrape '))
            long_coords=vec('MULTIPLY',coords,(2,1,95),'Scratches follow X travel direction')
            streak=noise(long_coords,1,1.2,'Fine directional abrasion only inside scrape areas')
            scuff=mul(scuff,ramp(streak,.40,.69,'Scrape line variation'))
            colour=mix(mul(lane,.19),colour,linear('6d706b'),'Moderate traffic band, original steel still visible')
            colour=mix(scuff,colour,linear('858982'),'Isolated long shoe scuffs')
            rough=add(rough,mul(lane,.13));rough=sub(rough,mul(scuff,.10))
            height=sub(height,mul(scuff,.22));bump_distance=.00035
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

        bsdf=node('ShaderNodeBsdfPrincipled','P3_Principled')
        put(colour,bsdf.inputs['Base Color']);put(clamp(rough),bsdf.inputs['Roughness'])
        put(clamp(metal),bsdf.inputs['Metallic']);bsdf.inputs['IOR'].default_value=1.48
        bsdf.inputs['Alpha'].default_value=1;bsdf.inputs['Emission Strength'].default_value=0
        bump=node('ShaderNodeBump','Submillimetre material response; tread remains geometry')
        bump.inputs['Strength'].default_value=bump_strength;bump.inputs['Distance'].default_value=bump_distance
        put(height,bump.inputs['Height']);links.new(bump.outputs['Normal'],bsdf.inputs['Normal'])
        out=node('ShaderNodeOutputMaterial','P3_Output');links.new(bsdf.outputs[0],out.inputs['Surface'])
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
                assert node.uv_map in {'SourceXZ','SourceY'};uvs.add(node.uv_map)
            if node.type=='VERTEX_COLOR':
                assert node.layer_name=='WeatherUse';attributes.add(node.layer_name)
            pending.extend(link.from_node for socket in node.inputs for link in socket.links)
        assert uvs=={'SourceXZ','SourceY'} and attributes=={'WeatherUse'}
        rows.append({'material':mat.name,'active_node_count':len(seen),
                     'explicit_uvs':sorted(uvs),'corner_attributes':sorted(attributes),
                     'no_transform_or_implicit_coordinates':True,'baked':False})
    return rows
