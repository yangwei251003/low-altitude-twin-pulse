"""P2 source graphs: causal weathering at metre scale, no atlas pixel edits."""

def build_material(Graph,bpy,name,kind,atlas,offset=0):
    g=Graph(name);n=g.n;l=g.l
    uv=n.new('ShaderNodeUVMap');uv.uv_map='SurfaceMetric'
    sep=n.new('ShaderNodeSeparateXYZ');l.new(uv.outputs['UV'],sep.inputs[0]);u,v=sep.outputs['X'],sep.outputs['Y']
    def attr(name):
        a=n.new('ShaderNodeAttribute');a.attribute_name=name;return a.outputs['Fac']
    h=attr('SourceHeight');x=attr('SourceX');front=attr('WaterFacing');repair=attr('RepairUse')
    macro=g.noise(uv.outputs[0],2.4,1);micro=g.noise(uv.outputs[0],48,2)
    def sample(quadrant,scale=1.8,shift=0):
        comb=n.new('ShaderNodeCombineXYZ')
        for socket,value,start,delta in [(comb.inputs['X'],u,quadrant[0],.13+offset+shift),(comb.inputs['Y'],v,quadrant[1],.39+shift)]:
            mirrored=g.op('PINGPONG',g.op('ADD',g.op('DIVIDE',value,scale),delta),1)
            g.val(g.op('ADD',start+.008,g.op('MULTIPLY',mirrored,.484)),socket)
        tex=n.new('ShaderNodeTexImage');tex.image=atlas;tex.extension='EXTEND'
        tex.label='Original 1254 atlas / quadrant627; physical 1.8m sample'
        l.new(comb.outputs[0],tex.inputs['Vector']);return tex.outputs['Color']
    def interval(value,start,end,feather):
        return g.op('MULTIPLY',g.clamp(g.op('DIVIDE',g.op('SUBTRACT',value,start),feather)),g.clamp(g.op('DIVIDE',g.op('SUBTRACT',end,value),feather)))
    def lateral(center,width):
        return g.clamp(g.op('SUBTRACT',1,g.op('DIVIDE',g.op('ABSOLUTE',g.op('SUBTRACT',x,center)),width)))
    def sine(value,frequency):return g.op('SINE',g.op('MULTIPLY',value,frequency))

    if kind=='concrete':
        # P1's full-face grain is deliberately reduced. Metre scale unchanged.
        base=g.mix((.34,.325,.30,1),sample((.5,.5)),.36)
        repair_color=g.mix((.22,.225,.208,1),sample((0,.5),1.8,.23),.35)
        base=g.mix(base,repair_color,repair)

        # Three independent broad runoffs, all from top edge/seam causes.
        runoff=0
        for center,start,length,width,strength,drift in [
                (-1.11,-.04,1.82,.18,.46,-.045),
                (.79,-.06,2.30,.23,.40,.065),
                (1.73,-.03,1.35,.29,.35,-.06)]:
            down=g.op('SUBTRACT',start,h);t=g.clamp(g.op('DIVIDE',down,length))
            active=interval(down,0,length,.08)
            c=g.op('ADD',center,g.op('MULTIPLY',drift,sine(t,2.3)))
            w=g.op('MULTIPLY',width,g.op('ADD',.62,g.op('MULTIPLY',sine(g.op('ADD',t,.45),2.1),.38)))
            body=g.op('POWER',lateral(c,w),1.5)
            tail=g.op('ADD',.35,g.op('MULTIPLY',g.op('SUBTRACT',1,t),.65))
            broken=g.op('ADD',.72,g.op('MULTIPLY',macro,.28))
            r=g.op('MULTIPLY',strength,g.op('MULTIPLY',active,g.op('MULTIPLY',body,g.op('MULTIPLY',tail,broken))))
            runoff=g.op('MAXIMUM',runoff,r)
        runoff=g.op('MULTIPLY',runoff,front)
        base=g.mix(base,g.mult(base,(.52,.49,.405,1)),runoff)

        # Deposit is adjacent to the two real seams, no whole-wall parallel bars.
        seam_deposit=0
        for sx,width,phase in [(-1.09,.095,0),(.79,.12,1.7)]:
            vary=g.op('ADD',.64,g.op('MULTIPLY',sine(g.op('ADD',h,phase),3.4),.28))
            band=lateral(sx,g.op('MULTIPLY',width,vary))
            band=g.op('MULTIPLY',band,interval(h,-2.69,-.10,.16))
            band=g.op('MULTIPLY',band,g.op('ADD',.25,g.op('MULTIPLY',macro,.60)))
            seam_deposit=g.op('MAXIMUM',seam_deposit,band)
        seam_deposit=g.op('MULTIPLY',seam_deposit,front)
        base=g.mix(base,g.mult(base,(.49,.43,.33,1)),g.op('MULTIPLY',seam_deposit,.58))

        # Actual datum remains -1.2m. Only weathered boundary undulates locally.
        water_edge=g.op('ADD',-1.2,g.op('MULTIPLY',g.op('SUBTRACT',macro,.5),.035))
        wet=g.clamp(g.op('ADD',.5,g.op('MULTIPLY',g.op('SUBTRACT',water_edge,h),13)))
        depth=g.clamp(g.op('DIVIDE',g.op('SUBTRACT',-1.2,h),1.6))
        damp=g.op('MULTIPLY',wet,g.op('ADD',.65,g.op('MULTIPLY',depth,.20)))
        base=g.mix(base,g.mult(base,(.33,.45,.44,1)),damp)

        salt=0
        # Nonperiodic 0.34-0.73m sections with different widths and gaps.
        for left,right,halfwidth,phase in [(-1.98,-1.60,.026,0),(-1.44,-.71,.067,.5),
                (-.40,.10,.037,1.2),(.43,1.13,.055,2.0),(1.44,1.81,.029,2.6)]:
            along=interval(x,left,right,.055)
            width=g.op('MULTIPLY',halfwidth,g.op('ADD',.60,g.op('MULTIPLY',macro,.75)))
            centre=g.op('ADD',water_edge,g.op('MULTIPLY',sine(g.op('ADD',x,phase),10),.009))
            across=g.clamp(g.op('SUBTRACT',1,g.op('DIVIDE',g.op('ABSOLUTE',g.op('SUBTRACT',h,centre)),width)))
            broken=g.clamp(g.op('MULTIPLY',g.op('SUBTRACT',macro,.24),2.1))
            salt=g.op('MAXIMUM',salt,g.op('MULTIPLY',along,g.op('MULTIPLY',across,broken)))
        salt=g.op('MULTIPLY',salt,front)
        base=g.mix(base,(.58,.55,.47,1),g.op('MULTIPLY',salt,.76))

        rust=0
        for fx,fy,length,width in [(-1.55,-.65,.72,.068),(.38,-.89,1.02,.083)]:
            down=g.op('SUBTRACT',fy-.09,h);t=g.clamp(g.op('DIVIDE',down,length))
            c=g.op('ADD',fx,g.op('MULTIPLY',g.op('SUBTRACT',macro,.5),.024))
            w=g.op('MULTIPLY',width,g.op('ADD',.18,g.op('MULTIPLY',g.op('SUBTRACT',1,t),.82)))
            r=g.op('MULTIPLY',lateral(c,w),g.op('MULTIPLY',interval(down,0,length,.025),g.op('SUBTRACT',1,t)))
            rust=g.op('MAXIMUM',rust,r)
        rust=g.op('MULTIPLY',rust,front)
        base=g.mix(base,(.20,.095,.030,1),g.op('MULTIPLY',rust,.63))

        # Unequal lower wet-erosion heights; no fine high-frequency colour noise.
        lower_edge=g.op('ADD',-2.16,g.op('ADD',g.op('MULTIPLY',sine(x,1.7),.13),g.op('MULTIPLY',sine(g.op('ADD',x,.7),3.1),.08)))
        algae=g.clamp(g.op('DIVIDE',g.op('SUBTRACT',lower_edge,h),.37))
        algae=g.op('MULTIPLY',algae,g.op('ADD',.42,g.op('MULTIPLY',macro,.58)))
        base=g.mix(base,g.mult(base,(.48,.58,.34,1)),g.op('MULTIPLY',algae,.62))
        rough=g.op('SUBTRACT',.88,g.op('MULTIPLY',wet,.22))
        rough=g.op('MAXIMUM',rough,g.op('MULTIPLY',repair,.87))
        rough=g.op('MAXIMUM',rough,g.op('MULTIPLY',salt,.96))
        metal=0;distance=.00045;strength=.14
        bump_height=g.op('ADD',g.op('MULTIPLY',micro,.22),g.op('MULTIPLY',salt,.7))
    elif kind=='aggregate':
        base=g.mix((.23,.23,.208,1),sample((0,.5),1.8,.23),.45)
        # Repaired concrete aggregate, not natural dark river pebbles.
        rough=.88;metal=0;distance=.0005;strength=.18;bump_height=micro
    elif kind=='paint':
        base=g.mix((.025,.075,.079,1),sample((0,0),.7),.72)
        rough=.68;metal=0;distance=.00015;strength=.20;bump_height=micro
    elif kind=='metal':
        base=(.19,.21,.205,1);rough=.46;metal=1;distance=.00008;strength=.20;bump_height=micro
    else:
        base=(.075,.08,.074,1);rough=.93;metal=0;distance=.0002;strength=.20;bump_height=micro
    bs=n.new('ShaderNodeBsdfPrincipled');g.val(base,bs.inputs['Base Color']);g.val(rough,bs.inputs['Roughness']);g.val(metal,bs.inputs['Metallic'])
    bs.inputs['Emission Color'].default_value=(0,0,0,1);bs.inputs['Emission Strength'].default_value=0
    bump=n.new('ShaderNodeBump');bump.inputs['Strength'].default_value=strength;bump.inputs['Distance'].default_value=distance
    g.val(bump_height,bump.inputs['Height']);l.new(bump.outputs['Normal'],bs.inputs['Normal'])
    out=n.new('ShaderNodeOutputMaterial');l.new(bs.outputs['BSDF'],out.inputs['Surface'])
    g.m['source_only_unbaked']=True;g.m['reference_texture_not_projected']=True
    g.m['p2_fullface_texture_mix']=.36 if kind=='concrete' else 0
    return g.m
