"""Prepared material/lighting revision only. Await root CPU2 window.
Load frozen P1 geometry and UV, audit actual nodes, rebuild author materials,
native bake, reopen and render. Never saves or modifies P1 files.
"""
from pathlib import Path
import bpy,json,hashlib,importlib.util,shutil,time,os,sys
SRC=Path(__file__).resolve().parent
P1=SRC.parent/'p1'
BASE=P1/'clinic_ground_p1.blend'
BASE_SHA='0ef67a73ae21e14f98676744eed43ab02cc52da42d73bc5e5ee0279a0aec0c75'
ATLAS=P1/'source_inputs/material_atlas_UNEDITED.png'
ATLAS_SHA='11db122c63d06f7fcd25f5614f19cd0efee1b09997149071b993ed6eff7e8406'
sys.dont_write_bytecode=True  # Read frozen helper without writing P1/__pycache__.
spec=importlib.util.spec_from_file_location('frozen_ground_helpers',P1/'build_ground.py')
H=importlib.util.module_from_spec(spec);spec.loader.exec_module(H)
H.SRC=SRC;H.AUTHORS=[];H.PIECES=[];H.CHECKS=[]

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def geometry_signature():
    rows=[]
    for o in sorted(H.PIECES,key=lambda ob:ob.name):
        mods=[{'type':m.type,'width':getattr(m,'width',None),'segments':getattr(m,'segments',None),'limit_method':getattr(m,'limit_method',None)} for m in o.modifiers]
        rows.append({'name':o.name,'matrix':[list(r) for r in o.matrix_world],'vertices':[list(v.co) for v in o.data.vertices],
                     'faces':[list(p.vertices) for p in o.data.polygons],'uv':[[u.name,[list(d.uv) for d in u.data]] for u in o.data.uv_layers],'modifiers':mods})
    return hashlib.sha256(json.dumps(rows,separators=(',',':')).encode()).hexdigest()

def preflight():
    m=bpy.data.materials['CGround_BakedPBR'];nodes=m.node_tree.nodes;out=next(n for n in nodes if n.type=='OUTPUT_MATERIAL')
    links=list(out.inputs['Surface'].links)
    assert len(links)==1 and links[0].from_node.type=='BSDF_PRINCIPLED','Final source must use actual Principled output.'
    bs=links[0].from_node;ec=bs.inputs['Emission Color'];es=bs.inputs['Emission Strength']
    effective=[float(c)*float(es.default_value) for c in ec.default_value[:3]]
    assert not ec.is_linked and not es.is_linked and max(effective)<1e-8,'Unexpected effective emission: stop before lighting changes.'
    images=[]
    for role,socket in [('BaseColor','Base Color'),('Roughness','Roughness'),('Metallic','Metallic')]:
        incoming=list(bs.inputs[socket].links);assert len(incoming)==1 and incoming[0].from_node.type=='TEX_IMAGE'
        im=incoming[0].from_node.image;path=Path(bpy.path.abspath(im.filepath)).resolve()
        assert path.exists();im.reload();pixel=list(im.pixels[:4]);assert len(pixel)==4 and im.has_data
        expected='sRGB' if role=='BaseColor' else 'Non-Color';assert im.colorspace_settings.name==expected
        images.append({'role':role,'path':str(path),'sha256':sha(path),'colorspace':im.colorspace_settings.name})
    normal=list(bs.inputs['Normal'].links);assert len(normal)==1 and normal[0].from_node.type=='NORMAL_MAP'
    nm=normal[0].from_node;tex=list(nm.inputs['Color'].links);assert len(tex)==1 and tex[0].from_node.type=='TEX_IMAGE'
    im=tex[0].from_node.image;assert im.colorspace_settings.name=='Non-Color';path=Path(bpy.path.abspath(im.filepath)).resolve()
    assert path.exists();im.reload();pixel=list(im.pixels[:4]);assert len(pixel)==4 and im.has_data
    images.append({'role':'Normal','path':str(path),'sha256':sha(path),'colorspace':im.colorspace_settings.name})
    floor=bpy.data.objects.get('STUDIO_ONLY_FLOOR');floor_m=floor.data.materials[0]
    audit={'status':'ACTUAL_P1_MATERIAL_VERIFIED','actual_output_node':bs.name,'emission_rgb':list(ec.default_value),
           'emission_strength':float(es.default_value),'effective_emission_rgb':effective,'images':images,
           'floor_material_use_nodes':floor_m.use_nodes,'floor_diffuse_color':list(floor_m.diffuse_color),
           'floor_nodes':[{'name':n.name,'type':n.type,'base_color':list(n.inputs['Base Color'].default_value) if n.type=='BSDF_PRINCIPLED' else None} for n in floor_m.node_tree.nodes] if floor_m.node_tree else [],
           'note':'This audit is recorded before any lighting/material change. Editing diffuse_color alone may not change a node-based floor.'}
    (SRC/'evidence/p1_actual_material_preflight.json').write_text(json.dumps(audit,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    return audit

def author_p2(name,kind,atlas):
    g=H.Graph(name);n=g.n;l=g.l;geo=n.new('ShaderNodeNewGeometry')
    xyz=n.new('ShaderNodeSeparateXYZ');l.new(geo.outputs['Position'],xyz.inputs[0]);x=xyz.outputs['X'];z=g.op('MULTIPLY',xyz.outputs['Y'],-1);h=xyz.outputs['Z']
    normals=n.new('ShaderNodeSeparateXYZ');l.new(geo.outputs['Normal'],normals.inputs[0])
    weights=[g.op('POWER',g.op('ABSOLUTE',normals.outputs[a]),8) for a in ['X','Y','Z']]
    total=g.op('ADD',g.op('ADD',weights[0],weights[1]),weights[2]);weights=[g.op('DIVIDE',w,g.op('MAXIMUM',total,.0001)) for w in weights]
    # Normal-dependent real metre projections: X wall -> Z/height, Z wall -> X/height,
    # top -> X/Z. Soft blend at bevels, no constant-coordinate side stretching.
    projections=[(z,h),(x,h),(x,z)]
    def image_sample(u,v,quadrant,scale,shift):
        u0,v0=quadrant;comb=n.new('ShaderNodeCombineXYZ')
        # Mirrored repeat guarantees C0 continuity for an atlas not certified seamless.
        # A second offset, rotated scale reduces bilateral repeat without pixel edits.
        pu=g.op('PINGPONG',g.op('ADD',g.op('DIVIDE',u,scale),shift[0]),1)
        pv=g.op('PINGPONG',g.op('ADD',g.op('DIVIDE',v,scale),shift[1]),1)
        l.new(g.op('ADD',u0+.008,g.op('MULTIPLY',pu,.484)),comb.inputs['X'])
        l.new(g.op('ADD',v0+.008,g.op('MULTIPLY',pv,.484)),comb.inputs['Y'])
        im=n.new('ShaderNodeTexImage');im.image=atlas;im.extension='EXTEND';im.label='Unedited flat atlas / metric mirrored sample'
        l.new(comb.outputs[0],im.inputs['Vector']);return im.outputs['Color']
    def projected(quadrant,scale):
        colors=[]
        for u,v in projections:
            first=image_sample(u,v,quadrant,scale,(.17,.39))
            second=image_sample(v,g.op('MULTIPLY',u,-1),quadrant,scale*1.43,(.63,.22))
            colors.append(g.mix(first,second,.18))
        blendxy=g.mix(colors[0],colors[1],g.op('DIVIDE',weights[1],g.op('MAXIMUM',.0001,g.op('ADD',weights[0],weights[1]))))
        return g.mix(blendxy,colors[2],weights[2])
    top=g.op('GREATER_THAN',normals.outputs['Z'],.6)
    micro=g.noise(geo.outputs['Position'],55,2);macro=g.noise(geo.outputs['Position'],1.2,1)
    if kind=='concrete':
        # Median values measured read-only from atlas, converted once sRGB -> linear.
        # 62% real image retains trowel/aggregate;37% cement reduces dark large-stone contrast.
        base=g.mix((.39675523,.32777810,.27049779,1),projected((0,.5),1.8),.62)
        repair=g.mix((.27049779,.24228112,.21586050,1),projected((.5,.5),1.8),.65)
        base=g.mix(base,repair,g.op('MULTIPLY',top,g.rectangle(x,z,-1.8,-1.45,.70,.30)))
        near=g.op('MAXIMUM',0,g.op('SUBTRACT',1,g.op('DIVIDE',g.op('ABSOLUTE',g.op('SUBTRACT',x,2.44)),.48)))
        wet=g.op('MULTIPLY',top,g.op('MULTIPLY',near,g.op('ADD',.26,g.op('MULTIPLY',macro,.12))))
        base=g.mix(base,g.color_mult(base,(.53,.58,.55,1)),wet)
        yellow=g.op('MINIMUM',1,g.op('ADD',g.rectangle(x,z,2.85,2.85,.13,.07),g.rectangle(x,z,2.85,-2.85,.13,.07)))
        chips=g.op('GREATER_THAN',g.noise(geo.outputs['Position'],35,1),.38)
        base=g.mix(base,(.58,.32,.045,1),g.op('MULTIPLY',top,g.op('MULTIPLY',yellow,chips)))
        rough=g.op('ADD',.74,g.op('MULTIPLY',micro,.14));metal=0;distance=.0008
    elif kind=='teal':
        base=projected((0,0),1.8);rough=.66;metal=.08;distance=.0002
        spots=0
        for i,zz in enumerate([H.CASSETTES[0]+.026,H.CASSETTES[1]-.026,H.CASSETTES[2]+.026,H.CASSETTES[4]-.026]):
            dx=g.op('DIVIDE',g.op('SUBTRACT',x,2.431 if i%2==0 else 2.689),.032)
            dz=g.op('DIVIDE',g.op('SUBTRACT',z,zz),.070 if i%2 else .045)
            radius=g.op('ADD',g.op('MULTIPLY',dx,dx),g.op('MULTIPLY',dz,dz))
            spots=g.op('MAXIMUM',spots,g.op('MAXIMUM',0,g.op('SUBTRACT',1,radius)))
        base=g.mix(base,(.15,.058,.018,1),g.op('MULTIPLY',spots,g.op('ADD',.18,g.op('MULTIPLY',micro,.34))))
    elif kind=='galvanized':
        base=projected((.5,0),1.8);rough=.48;metal=.80;distance=.00012
    else:base=(.040,.047,.043,1);rough=.91;metal=0;distance=.0001
    bs=n.new('ShaderNodeBsdfPrincipled');g.value(base,bs.inputs['Base Color']);g.value(rough,bs.inputs['Roughness']);g.value(metal,bs.inputs['Metallic'])
    bs.inputs['Emission Color'].default_value=(0,0,0,1);bs.inputs['Emission Strength'].default_value=0
    bump=n.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.25;bump.inputs['Distance'].default_value=distance
    g.value(micro,bump.inputs['Height']);l.new(bump.outputs['Normal'],bs.inputs['Normal'])
    em=n.new('ShaderNodeEmission');em.inputs['Strength'].default_value=1;out=n.new('ShaderNodeOutputMaterial');l.new(bs.outputs['BSDF'],out.inputs['Surface'])
    H.AUTHORS.append({'material':g.m,'graph':g,'bsdf':bs,'emission':em,'output':out,'channels':{'BaseColor':base,'Roughness':rough,'Metallic':metal}})
    return g.m

def neutral_studio():
    scene=bpy.context.scene
    bg=scene.world.node_tree.nodes.get('Background');assert bg
    bg.inputs['Color'].default_value=(.42,.45,.48,1);bg.inputs['Strength'].default_value=.22
    for name,power in [('Review_Key',450),('Review_Fill',160)]:bpy.data.objects[name].data.energy=power
    floor=bpy.data.objects['STUDIO_ONLY_FLOOR'];m=bpy.data.materials.new('P2_NeutralStudioFloor');m.use_nodes=True
    n=m.node_tree.nodes;n.clear();bs=n.new('ShaderNodeBsdfPrincipled');out=n.new('ShaderNodeOutputMaterial');m.node_tree.links.new(bs.outputs[0],out.inputs['Surface'])
    bs.inputs['Base Color'].default_value=(.18,.20,.22,1);bs.inputs['Roughness'].default_value=.95;bs.inputs['Emission Strength'].default_value=0
    floor.data.materials.clear();floor.data.materials.append(m)
    scene.view_settings.view_transform='Standard';scene.view_settings.look='None';scene.view_settings.exposure=0;scene.view_settings.gamma=1
    scene.render.resolution_x=1280;scene.render.resolution_y=1280;scene.render.resolution_percentage=100;scene.cycles.samples=32;scene.cycles.use_denoising=True

def main():
    start=time.time();blend=SRC/'clinic_ground_p2.blend';assert not blend.exists()
    assert sha(BASE)==BASE_SHA and sha(ATLAS)==ATLAS_SHA
    for folder in ['evidence','textures','source_inputs']:(SRC/folder).mkdir(exist_ok=True)
    print(json.dumps({'stage':'start','pid':os.getpid(),'threads':2,'material_only':True}),flush=True)
    copied=SRC/'source_inputs/material_atlas_UNEDITED.png';shutil.copyfile(ATLAS,copied);assert sha(copied)==ATLAS_SHA
    bpy.ops.wm.open_mainfile(filepath=str(BASE));scene=bpy.context.scene;scene.render.threads_mode='FIXED';scene.render.threads=2;scene.cycles.device='CPU'
    audit=preflight();H.PIECES=sorted([o for o in bpy.data.objects if o.type=='MESH' and o.get('editable_piece',False)],key=lambda o:o.name)
    assert len(H.PIECES)==77;signature=geometry_signature();frozen_report=json.loads((P1/'evidence/production_report.json').read_text(encoding='utf-8'))
    atlas=bpy.data.images.load(str(copied),check_existing=False);atlas.colorspace_settings.name='sRGB'
    mats={kind:author_p2('SOURCE_P2_'+kind,kind,atlas) for kind in ['concrete','teal','galvanized','dark']}
    for o in H.PIECES:
        name=o.name
        if name.startswith('Pour_') or name.startswith('Drain_OuterConcrete') or name.startswith('Drain_EndConcrete'):kind='concrete'
        elif name.startswith('Joint_') or name.startswith('Drain_ClosedBottom') or name.startswith('Drain_EndWall'):kind='dark'
        elif 'Frame' in name:kind='teal'
        else:
            assert 'GrateBar' in name or 'LowerBrace' in name or 'Bolt_' in name,name;kind='galvanized'
        o.data.materials.clear();o.data.materials.append(mats[kind])
    bpy.data.materials['CGround_BakedPBR'].name='ARCHIVE_P1_BakedPBR_NOT_USED'
    assert geometry_signature()==signature
    bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'material_uv_checkpoint.blend'),relative_remap=False)
    baked=H.bake_and_apply(SRC/'textures');assert geometry_signature()==signature
    final_bs=next(n for n in bpy.data.materials['CGround_BakedPBR'].node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    final_bs.inputs['Emission Color'].default_value=(0,0,0,1);final_bs.inputs['Emission Strength'].default_value=0
    bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'baked_checkpoint.blend'),relative_remap=False)
    report={'status':'P2_BAKED_PENDING_PREVIEW','source_sha256':BASE_SHA,'geometry_uv_signature':signature,'geometry_uv_unchanged':True,
            'triangles_from_identical_source':frozen_report['triangles'],'source_pieces':77,'baked_maps':baked,'p1_material_preflight':audit,
            'sampling':{'concrete_primary_patch_m':1.8,'secondary_patch_m':2.574,'secondary_blend':.18,'concrete_image_weight':.62,'projection':'abs(normal)^8 triplanar; mirrored repeat to avoid discontinuities; original PNG unedited'},
            'limits':['Mirrored-repeat symmetry still needs visual review.','No geometry/UV change, no GLB/Godot or final art acceptance.']}
    (SRC/'evidence/production_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    neutral_studio();bpy.ops.wm.save_as_mainfile(filepath=str(blend),relative_remap=False)
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath:im.filepath=bpy.path.relpath(str(Path(bpy.path.abspath(im.filepath)).resolve()))
    bpy.ops.wm.save_as_mainfile(filepath=str(blend),relative_remap=False)
    bpy.ops.wm.open_mainfile(filepath=str(blend));scene=bpy.context.scene;readback=[]
    for n in bpy.data.materials['CGround_BakedPBR'].node_tree.nodes:
        if n.type!='TEX_IMAGE':continue
        im=n.image;p=Path(bpy.path.abspath(im.filepath)).resolve();row=next(r for r in baked if r['role']==n.label)
        assert p.exists() and sha(p)==row['sha256'];im.reload();pixel=list(im.pixels[:4]);assert len(pixel)==4 and im.has_data and tuple(im.size)==(2048,2048)
        readback.append({'role':n.label,'path':str(p),'sha256':sha(p),'colorspace':im.colorspace_settings.name})
    assert len(readback)==4
    H.PIECES=sorted([o for o in bpy.data.objects if o.type=='MESH' and o.get('editable_piece',False)],key=lambda o:o.name)
    assert geometry_signature()==signature and sha(BASE)==BASE_SHA
    output=SRC/'evidence/clinic_ground_p2.png';scene.render.filepath=str(output);bpy.ops.render.render(write_still=True)
    report.update(status='SOURCE_RENDERED_PENDING_VISUAL_REVIEW',reopened_images=readback,blend_sha256=sha(blend),preview_sha256=sha(output),elapsed_seconds=time.time()-start)
    (SRC/'evidence/production_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'stage':'end','pid':os.getpid(),'seconds':time.time()-start,'p1_source_unchanged':sha(BASE)==BASE_SHA}),flush=True)

if __name__=='__main__':main()
