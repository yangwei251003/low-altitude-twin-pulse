"""P10 two-scan source material; executed only in an authorized Blender run."""
from pathlib import Path
import hashlib,json

HERE=Path(__file__).resolve().parent
VENDOR=HERE.parent/'p9/vendor/polyhaven_sandy_gravel_02'
ROCK_VENDOR=HERE/'vendor/polyhaven_rocky_trail'
WIDTH_M=2.5

def verify_inputs():
    metadata=[]
    for folder in (VENDOR,ROCK_VENDOR):
        entry=json.loads((folder/'provenance.json').read_text(encoding='utf-8'))
        for row in entry['files']:
            p=folder/Path(row['path']).name
            assert p.stat().st_size==row['bytes']
            assert hashlib.sha256(p.read_bytes()).hexdigest()==row['sha256']
        metadata.append(entry)
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
    original=[tuple(v.uv) for v in ob.data.uv_layers['MetricUV'].data]
    ob.data.uv_layers.new(name='RockScanUV')
    for loop,uv in zip(ob.data.uv_layers['RockScanUV'].data,original):loop.uv=(uv[0]*1.5/2+.31,uv[1]*1.5/2+.09)
    ob.data.uv_layers.active_index=ob.data.uv_layers.find('MetricUV')
    for layer in ob.data.uv_layers:layer.active_render=layer.name=='MetricUV'
    ob['soil_source_width_m']=WIDTH_M

def make_soil_material():
    import bpy
    verify_inputs()
    m=bpy.data.materials.new('SOURCE_P10_TwoScans_Metric');m.use_nodes=True
    n=m.node_tree.nodes;l=m.node_tree.links;n.clear()
    uv=n.new('ShaderNodeUVMap');uv.uv_map='SoilScanUV'
    images={}
    for role,name,space in [('base','sandy_gravel_02_diff_2k.png','sRGB'),('normal','sandy_gravel_02_nor_gl_2k.png','Non-Color'),('rough','sandy_gravel_02_rough_2k.png','Non-Color')]:
        node=n.new('ShaderNodeTexImage');node.image=bpy.data.images.load(str(VENDOR/name),check_existing=True);node.image.colorspace_settings.name=space
        node.extension='REPEAT';node.interpolation='Linear';l.new(uv.outputs['UV'],node.inputs['Vector']);images[role]=node
    rock_uv=n.new('ShaderNodeUVMap');rock_uv.uv_map='RockScanUV'
    rocks={}
    for role,suffix,space in [('base','diff','sRGB'),('normal','nor_gl','Non-Color'),('rough','rough','Non-Color')]:
        node=n.new('ShaderNodeTexImage');node.image=bpy.data.images.load(str(ROCK_VENDOR/('rocky_trail_'+suffix+'_2k.png')),check_existing=True);node.image.colorspace_settings.name=space
        node.extension='REPEAT';node.interpolation='Linear';l.new(rock_uv.outputs['UV'],node.inputs['Vector']);rocks[role]=node
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
    blend=n.new('ShaderNodeMixRGB');blend.blend_type='MIX';l.new(split.outputs['Blue'],blend.inputs[0]);l.new(tone.outputs[0],blend.inputs[1]);l.new(rocks['base'].outputs[0],blend.inputs[2])
    wet_multiplier=scalar('SUBTRACT',1,scalar('MULTIPLY',split.outputs['Red'],.24))
    wet=n.new('ShaderNodeMixRGB');wet.blend_type='MULTIPLY';wet.inputs[0].default_value=1
    l.new(blend.outputs[0],wet.inputs[1]);l.new(wet_multiplier,wet.inputs[2])
    roughmix=n.new('ShaderNodeMixRGB');l.new(split.outputs['Blue'],roughmix.inputs[0]);l.new(images['rough'].outputs[0],roughmix.inputs[1]);l.new(rocks['rough'].outputs[0],roughmix.inputs[2])
    rough=scalar('MULTIPLY',roughmix.outputs[0],scalar('SUBTRACT',1,scalar('MULTIPLY',split.outputs['Red'],.25)))
    rough=scalar('MINIMUM',.95,scalar('MAXIMUM',.50,rough))
    normal=n.new('ShaderNodeNormalMap');normal.space='TANGENT';normal.uv_map='SoilScanUV'
    l.new(images['normal'].outputs['Color'],normal.inputs['Color'])
    l.new(scalar('SUBTRACT',1,scalar('MULTIPLY',split.outputs['Green'],.65)),normal.inputs['Strength'])
    rocknormal=n.new('ShaderNodeNormalMap');rocknormal.space='TANGENT';rocknormal.uv_map='RockScanUV';rocknormal.inputs['Strength'].default_value=.8;l.new(rocks['normal'].outputs[0],rocknormal.inputs['Color'])
    mixnormal=n.new('ShaderNodeMixRGB');l.new(split.outputs['Blue'],mixnormal.inputs[0]);l.new(normal.outputs[0],mixnormal.inputs[1]);l.new(rocknormal.outputs[0],mixnormal.inputs[2])
    normalized=n.new('ShaderNodeVectorMath');normalized.operation='NORMALIZE';l.new(mixnormal.outputs[0],normalized.inputs[0])
    bs=n.new('ShaderNodeBsdfPrincipled');bs.inputs['Metallic'].default_value=0;bs.inputs['Emission Strength'].default_value=0
    l.new(wet.outputs[0],bs.inputs['Base Color']);l.new(rough,bs.inputs['Roughness']);l.new(normalized.outputs[0],bs.inputs['Normal'])
    out=n.new('ShaderNodeOutputMaterial');l.new(bs.outputs[0],out.inputs['Surface'])
    m['author']='Dario Barresi + Amal Kumar / Poly Haven, CC0; local shader adaptation'
    m['source']='https://polyhaven.com/a/sandy_gravel_02'
    m['second_source']='https://polyhaven.com/a/rocky_trail'
    m['source_width_m']=WIDTH_M
    m['plan_limits']='P10 prepared material; no Blender preview/game approval before actual run.'
    return m
