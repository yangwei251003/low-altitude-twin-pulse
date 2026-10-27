"""Approved yard concrete cache, no new bake or image manipulation."""
from pathlib import Path
import json, math, shutil
import bpy
import geometry as geo

def load_images(here,out):
    rows=json.loads((here/'inputs.json').read_text(encoding='utf-8'))['maps']
    dest=out/'textures';dest.mkdir();images={};checks=[]
    for row in rows:
        p=here/row['local'];assert geo.sha(p)==row['sha256']
        q=dest/p.name;shutil.copyfile(p,q);assert geo.sha(q)==row['sha256']
        im=bpy.data.images.load(str(q),check_existing=False)
        im.colorspace_settings.name=row['colorspace']
        pixel=list(im.pixels[:4]);assert im.has_data and len(pixel)==4 and all(map(math.isfinite,pixel))
        assert list(im.size)==row['size']
        images[row['channel']]=im
        checks.append({**row,'path':str(q),'sample':pixel})
    return images,checks

def opaque(name):
    m=bpy.data.materials.new(name);m.use_nodes=True;m.use_backface_culling=True
    n,l=m.node_tree.nodes,m.node_tree.links;n.clear()
    b=n.new('ShaderNodeBsdfPrincipled');o=n.new('ShaderNodeOutputMaterial');l.new(b.outputs[0],o.inputs[0])
    b.inputs['Emission Strength'].default_value=0;b.inputs['Alpha'].default_value=1
    return m,b,n,l

def concrete(name,images,tint):
    m,b,n,l=opaque(name)
    uv=n.new('ShaderNodeUVMap');uv.uv_map='RuntimeUV';textures={}
    for ch,im in images.items():
        tex=n.new('ShaderNodeTexImage');tex.image=im;tex.extension='REPEAT'
        l.new(uv.outputs[0],tex.inputs['Vector']);textures[ch]=tex
    mul=n.new('ShaderNodeMixRGB');mul.blend_type='MULTIPLY';mul.inputs[0].default_value=1
    mul.inputs[2].default_value=tint;l.new(textures['BaseColor'].outputs['Color'],mul.inputs[1])
    # Large localized usage variation is a vertex attribute, not painted light.
    attr=n.new('ShaderNodeVertexColor');attr.layer_name='UseTint'
    use=n.new('ShaderNodeMixRGB');use.blend_type='MULTIPLY';use.inputs[0].default_value=1
    l.new(mul.outputs[0],use.inputs[1]);l.new(attr.outputs['Color'],use.inputs[2]);l.new(use.outputs[0],b.inputs['Base Color'])
    sep=n.new('ShaderNodeSeparateColor');sep.mode='RGB'
    l.new(textures['ORM'].outputs[0],sep.inputs[0]);l.new(sep.outputs['Green'],b.inputs['Roughness']);l.new(sep.outputs['Blue'],b.inputs['Metallic'])
    normal=n.new('ShaderNodeNormalMap');normal.space='TANGENT';normal.uv_map='RuntimeUV';normal.inputs['Strength'].default_value=1
    l.new(textures['Normal'].outputs['Color'],normal.inputs['Color']);l.new(normal.outputs[0],b.inputs['Normal'])
    m['source_cache']='yard field approved revision2, concrete 3.6m periodic cache'
    m['normal_contract']='Original cached microbump only, near-neutral in measurement; strength1 once. No new bump or color-derived height.'
    m['orm_contract']='R=1 no AO; G=roughness B=metallic; Non-Color'
    return m

def make(images,config):
    route=concrete('ApronConcrete',images,(1,1,1,1))
    maintenance=concrete('ApronMaintenance',images,config['maintenance_multiplier'])
    seal,b,_,_=opaque('ApronJoint');b.inputs['Base Color'].default_value=(.033,.037,.033,1)
    b.inputs['Roughness'].default_value=.95;b.inputs['Metallic'].default_value=0
    return {'route':route,'repair':route,'maintenance':maintenance,'joint':seal}

def use_tint(x,z,role):
    # Two low-contrast elongated maintenance traces: neither repeated per panel
    # nor spread across every surface. Both keep the underlying cache readable.
    if role not in {'maintenance','route'}: return 1.0
    a=math.exp(-(((x+8.2)/2.5)**2+((z+6.8)/1.0)**2))
    b=math.exp(-(((x-3.3)/1.5)**2+((z-5.3)/3.6)**2))
    return 1.0-.045*a-.035*b
