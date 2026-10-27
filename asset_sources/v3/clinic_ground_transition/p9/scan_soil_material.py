"""Static P9 source material preparation; executed only in authorized Blender run."""
from pathlib import Path
import hashlib,json

HERE=Path(__file__).resolve().parent
VENDOR=HERE/'vendor/polyhaven_sandy_gravel_02'
WIDTH_M=2.5

def verify_inputs():
    metadata=json.loads((VENDOR/'provenance.json').read_text(encoding='utf-8'))
    for row in metadata['files']:
        p=VENDOR/Path(row['path']).name
        assert p.stat().st_size==row['bytes']
        assert hashlib.sha256(p.read_bytes()).hexdigest()==row['sha256']
    return metadata

def ensure_scan_uv(ob):
    # Capture tuples before creating a layer: Blender may invalidate old RNA
    # handles when the UV layer collection is extended.
    original=[tuple(v.uv) for v in ob.data.uv_layers['MetricUV'].data]
    if 'SoilScanUV' not in ob.data.uv_layers:ob.data.uv_layers.new(name='SoilScanUV')
    target=ob.data.uv_layers['SoilScanUV']
    for loop,uv in zip(target.data,original):
        loop.uv=(uv[0]*1.5/WIDTH_M+.13,uv[1]*1.5/WIDTH_M+.27)
    ob.data.uv_layers.active_index=ob.data.uv_layers.find('MetricUV')
    for layer in ob.data.uv_layers:layer.active_render=layer.name=='MetricUV'
    ob['soil_source_width_m']=WIDTH_M

def verify_scan_binding(ob):
    """Read actual soil loops after construction/join, before any bake."""
    metric=ob.data.uv_layers['MetricUV'];scan=ob.data.uv_layers['SoilScanUV']
    soil_slots={i for i,m in enumerate(ob.data.materials) if m and m.name.startswith('SOURCE_P9_SandyGravel02_Metric')}
    errors=[];loop_count=0
    for face in ob.data.polygons:
        if face.material_index not in soil_slots:continue
        for li in face.loop_indices:
            old=metric.data[li].uv;actual=scan.data[li].uv
            errors.extend([abs(actual[0]-(old[0]*1.5/WIDTH_M+.13)),abs(actual[1]-(old[1]*1.5/WIDTH_M+.27))]);loop_count+=1
    assert loop_count>0,'No soil loops found for scan UV validation'
    error=max(errors);assert error<1e-6,('SoilScanUV mismatch',error)
    rows=[]
    for index in soil_slots:
        material=ob.data.materials[index]
        textures=[n for n in material.node_tree.nodes if n.type=='TEX_IMAGE' and n.image]
        assert len(textures)==3
        for node in textures:
            assert node.inputs['Vector'].is_linked
            uv=node.inputs['Vector'].links[0].from_node
            assert uv.type=='UVMAP' and uv.uv_map=='SoilScanUV'
            rows.append({'image':node.image.name,'colorspace':node.image.colorspace_settings.name,'uv':uv.uv_map})
        normal=next(n for n in material.node_tree.nodes if n.type=='NORMAL_MAP')
        assert normal.space=='TANGENT' and normal.uv_map=='SoilScanUV'
    return {'mesh':ob.name,'soil_loop_count':loop_count,'max_metric_to_scan_uv_error':error,'source_width_m':WIDTH_M,'images':rows}

def make_soil_material():
    import bpy
    verify_inputs()
    m=bpy.data.materials.new('SOURCE_P9_SandyGravel02_Metric');m.use_nodes=True
    n=m.node_tree.nodes;l=m.node_tree.links;n.clear()
    uv=n.new('ShaderNodeUVMap');uv.uv_map='SoilScanUV'
    images={}
    for role,name,space in [('base','sandy_gravel_02_diff_2k.png','sRGB'),('normal','sandy_gravel_02_nor_gl_2k.png','Non-Color'),('rough','sandy_gravel_02_rough_2k.png','Non-Color')]:
        node=n.new('ShaderNodeTexImage');node.image=bpy.data.images.load(str(VENDOR/name),check_existing=True);node.image.colorspace_settings.name=space
        node.extension='REPEAT';node.interpolation='Linear';l.new(uv.outputs['UV'],node.inputs['Vector']);images[role]=node
    controls=n.new('ShaderNodeVertexColor');controls.layer_name='SurfaceControl'
    split=n.new('ShaderNodeSeparateColor');l.new(controls.outputs['Color'],split.inputs[0])
    def scalar(op,a,b):
        node=n.new('ShaderNodeMath');node.operation=op
        for i,value in enumerate([a,b]):
            if isinstance(value,(int,float)):node.inputs[i].default_value=value
            else:l.new(value,node.inputs[i])
        return node.outputs[0]
    tone=n.new('ShaderNodeHueSaturation');tone.inputs['Hue'].default_value=.5;tone.inputs['Saturation'].default_value=.60;tone.inputs['Value'].default_value=.90;tone.inputs['Fac'].default_value=1
    l.new(images['base'].outputs['Color'],tone.inputs['Color'])
    wet_multiplier=scalar('SUBTRACT',1,scalar('MULTIPLY',split.outputs['Red'],.24))
    wet=n.new('ShaderNodeMixRGB');wet.blend_type='MULTIPLY';wet.inputs[0].default_value=1
    l.new(tone.outputs['Color'],wet.inputs[1]);l.new(wet_multiplier,wet.inputs[2])
    rough=scalar('MULTIPLY',images['rough'].outputs['Color'],scalar('SUBTRACT',1,scalar('MULTIPLY',split.outputs['Red'],.25)))
    rough=scalar('MINIMUM',.95,scalar('MAXIMUM',.50,rough))
    normal=n.new('ShaderNodeNormalMap');normal.space='TANGENT';normal.uv_map='SoilScanUV'
    l.new(images['normal'].outputs['Color'],normal.inputs['Color'])
    l.new(scalar('SUBTRACT',1,scalar('MULTIPLY',split.outputs['Green'],.65)),normal.inputs['Strength'])
    bs=n.new('ShaderNodeBsdfPrincipled');bs.inputs['Metallic'].default_value=0;bs.inputs['Emission Strength'].default_value=0
    l.new(wet.outputs[0],bs.inputs['Base Color']);l.new(rough,bs.inputs['Roughness']);l.new(normal.outputs['Normal'],bs.inputs['Normal'])
    out=n.new('ShaderNodeOutputMaterial');l.new(bs.outputs[0],out.inputs['Surface'])
    m['author']='Dario Barresi / Poly Haven, CC0; local shader adaptation'
    m['source']='https://polyhaven.com/a/sandy_gravel_02'
    m['source_width_m']=WIDTH_M
    m['plan_limits']='P9 prepared material; no Blender preview/game approval before actual run.'
    return m
