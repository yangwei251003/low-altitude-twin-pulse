"""Original supporting PBR maps + unmodified shared generated color references.
Color PNGs are encoded as display/sRGB bytes; data maps are raw linear bytes.
No generated reference is recolored, cropped or overwritten by this module.
"""
import bpy,math,json,hashlib,shutil,struct,zlib
import numpy as np
from pathlib import Path

def png(path,rgb):
    a=np.clip(np.asarray(rgb)*255+.5,0,255).astype(np.uint8)
    if a.ndim==2:a=np.repeat(a[:,:,None],3,axis=2)
    h,w,_=a.shape
    raw=b''.join(b'\0'+row.tobytes() for row in a)
    def chunk(tag,data):return struct.pack('>I',len(data))+tag+data+struct.pack('>I',zlib.crc32(tag+data)&0xffffffff)
    path.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(raw,9))+chunk(b'IEND',b''))

def production_materials(src,root):
    tex=src/'textures';tex.mkdir(exist_ok=True)
    references=root/'asset_sources/v3/crown/material_references';provenance=[];mats={}
    for kind,source in [('Stone','stone_reference_p3.png'),('Bark','bark_reference_p3.png')]:
        original=references/source;target=tex/f'RB_{kind}_BaseColor.png';shutil.copyfile(original,target)
        provenance.append({'kind':kind,'source':str(original.relative_to(root)).replace('\\','/'),'copy':str(target.relative_to(root)).replace('\\','/'),'sha256':hashlib.sha256(target.read_bytes()).hexdigest(),'operation':'byte-identical copy; no image editing','limitations':'generated single-material color reference includes painted shading; not a measured albedo; seams/scale require visual review'})
    n=512;v,u=np.mgrid[0:n,0:n].astype(np.float32)/(n-1)
    for kind in ['Stone','Bark','Moss','Sap']:
        if kind=='Stone':
            height=.006*np.sin(u*18+v*9)+.004*np.sin(u*38-v*16)
            rough=.91+.025*np.sin(u*9+v*7)
        elif kind=='Bark':
            height=.014*np.sin(u*27+.30*np.sin(v*7))+.006*np.sin(u*53+.55*np.sin(v*11))
            rough=.86+.03*np.cos(u*21+np.sin(v*8))
        elif kind=='Moss':
            color=np.tile(np.array([.315,.37,.135],dtype=np.float32),(n,n,1))
            color+=(.020*np.sin(u*18+np.sin(v*16))+.014*np.cos(v*21))[:,:,None]*np.array([.6,1,.2])
            for k in range(19):
                cx=(k*.371)%1;cy=(k*.219+.11)%1
                stroke=((u-cx)/(.04+.015*(k%3)))**2+((v-cy)/.015)**2<1
                color[stroke]+=np.array([.032,.040,.009])
            png(tex/'RB_Moss_BaseColor.png',color);height=.003*np.sin(u*40)*np.sin(v*38);rough=np.full_like(u,.96)
        else:
            band=np.sin(u*14+v*5+.7*np.sin(v*12))
            color=np.tile(np.array([.72,.32,.055],dtype=np.float32),(n,n,1))
            color+=(.09*band+.035*np.cos(u*31-v*8))[:,:,None]*np.array([1,.72,.12])
            fleck=(np.sin(u*39+v*17)>.88)&(np.cos(v*47-u*11)>.80)
            color[fleck]=(.93,.62,.18);png(tex/'RB_Sap_BaseColor.png',color)
            height=.004*band;rough=.42+.045*band
        gy,gx=np.gradient(height);normal=np.dstack((-gx*22,-gy*22,np.ones_like(u)));normal/=np.linalg.norm(normal,axis=2)[:,:,None]
        png(tex/f'RB_{kind}_Roughness.png',rough);png(tex/f'RB_{kind}_Normal.png',normal*.5+.5)
        mat=bpy.data.materials.new('RB_'+kind);mat.use_nodes=True
        nodes=mat.node_tree.nodes;links=mat.node_tree.links;p=nodes['Principled BSDF']
        p.inputs['Metallic'].default_value=0;p.inputs['Roughness'].default_value=.85;p.inputs['Specular IOR Level'].default_value=.23
        uv=nodes.new('ShaderNodeUVMap');uv.uv_map='SurfaceUV'
        for suffix,socket in [('BaseColor','Base Color'),('Roughness','Roughness'),('Normal',None)]:
            im=bpy.data.images.load(str(tex/f'RB_{kind}_{suffix}.png'),check_existing=True)
            im.colorspace_settings.name='sRGB' if suffix=='BaseColor' else 'Non-Color';im.pack()
            node=nodes.new('ShaderNodeTexImage');node.image=im;node.extension='REPEAT';links.new(uv.outputs['UV'],node.inputs['Vector'])
            if socket:links.new(node.outputs['Color'],p.inputs[socket])
            else:
                normal_node=nodes.new('ShaderNodeNormalMap');normal_node.inputs['Strength'].default_value=.28
                links.new(node.outputs['Color'],normal_node.inputs['Color']);links.new(normal_node.outputs['Normal'],p.inputs['Normal'])
        if kind=='Sap':
            p.inputs['Emission Color'].default_value=(.17,.045,.003,1);p.inputs['Emission Strength'].default_value=.18
        mats[kind]=mat
    (src/'texture_provenance.json').write_text(json.dumps({'references':provenance,'supporting_maps':'original deterministic authored roughness/normal maps; color-independent, not recovered image geometry','color_encoding':'base colors sRGB PNG; roughness/normal Non-Color','material_count':4},ensure_ascii=False,indent=2),encoding='utf-8')
    return mats
