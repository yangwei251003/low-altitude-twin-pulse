"""Native periodic cache only, never bakes the12x4 display block or whole field atlas."""
from pathlib import Path
import sys,os,json,time,math,hashlib
import bpy
import numpy as np
HERE=Path(__file__).resolve().parent; ROOT=HERE.parents[4]; sys.path.insert(0,str(HERE))
import materials as mats
OUT=Path(os.environ['YARD_FIELD_OUT']).resolve(); assert OUT.is_relative_to(HERE)
def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def dump(name,data): (OUT/name).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def activate(ob):
    bpy.ops.object.select_all(action='DESELECT'); ob.hide_set(False); ob.select_set(True); bpy.context.view_layer.objects.active=ob

def tile(name,period,material):
    me=bpy.data.meshes.new(name); me.from_pydata([(0,0,0),(period,0,0),(period,period,0),(0,period,0)],[],[(0,1,2,3)]); me.update()
    me.uv_layers.new(name='SourceMetric'); me.uv_layers.new(name='CacheUV')
    metric=me.uv_layers['SourceMetric']; target=me.uv_layers['CacheUV']
    for loop in me.loops:
        p=me.vertices[loop.vertex_index].co; metric.data[loop.index].uv=(p.x,p.y); target.data[loop.index].uv=(p.x/period,p.y/period)
    me.uv_layers.active=target; target.active_render=True
    ob=bpy.data.objects.new(name,me); bpy.context.scene.collection.objects.link(ob); me.materials.append(material); return ob

def channel(mat,name):
    bs=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED'); socket=bs.inputs[name]
    if socket.is_linked:return socket.links[0].from_socket
    return socket.default_value

def cache(ob,family):
    mat=ob.data.materials[0]; nodes=mat.node_tree.nodes; links=mat.node_tree.links
    out=next(n for n in nodes if n.type=='OUTPUT_MATERIAL'); original=out.inputs['Surface'].links[0].from_socket
    emission=nodes.new('ShaderNodeEmission'); emission.inputs['Strength'].default_value=1
    combine=nodes.new('ShaderNodeCombineColor'); combine.mode='RGB'; combine.inputs['Red'].default_value=1
    for input_name,target in [('Roughness',combine.inputs['Green']),('Metallic',combine.inputs['Blue'])]:
        source=channel(mat,input_name)
        if hasattr(source,'node'): links.new(source,target)
        else: target.default_value=source
    records=[]; activate(ob)
    for map_name in ['BaseColor','ORM','Normal']:
        im=bpy.data.images.new(family+'_'+map_name,width=2048,height=2048,alpha=False,float_buffer=False)
        im.colorspace_settings.name='sRGB' if map_name=='BaseColor' else 'Non-Color'
        texture=nodes.new('ShaderNodeTexImage'); texture.image=im; nodes.active=texture
        for n in nodes: n.select=False
        texture.select=True
        if map_name=='Normal':
            links.new(original,out.inputs['Surface']); kind='NORMAL'
        else:
            value=channel(mat,'Base Color') if map_name=='BaseColor' else combine.outputs[0]
            for link in list(emission.inputs['Color'].links): links.remove(link)
            if hasattr(value,'node'): links.new(value,emission.inputs['Color'])
            else: emission.inputs['Color'].default_value=value
            links.new(emission.outputs[0],out.inputs['Surface']); kind='EMIT'
        bpy.ops.object.bake(type=kind,use_clear=True,margin=0)
        p=OUT/(family+'_'+map_name+'.png'); im.filepath_raw=str(p); im.file_format='PNG'; im.save()
        file_image=bpy.data.images.load(str(p),check_existing=False); file_image.colorspace_settings.name=im.colorspace_settings.name
        texture.image=file_image
        read_pixel=list(file_image.pixels[:4]); assert file_image.has_data and len(read_pixel)==4 and all(math.isfinite(v) for v in read_pixel)
        values=np.empty(2048*2048*4,dtype=np.float32); im.pixels.foreach_get(values); values=values.reshape(2048,2048,4)
        assert np.isfinite(values).all() and im.has_data and p.is_file()
        stats={'min':values[:,:,:3].min(axis=(0,1)).tolist(),'max':values[:,:,:3].max(axis=(0,1)).tolist(),
               'edge_center_difference_x_mean':float(np.abs(values[:,0,:3]-values[:,-1,:3]).mean()),
               'edge_center_difference_y_mean':float(np.abs(values[0,:,:3]-values[-1,:,:3]).mean())}
        if map_name=='ORM': assert float(values[:,:,0].min())>.99 and float(values[:,:,2].max())<.01
        records.append({'path':str(p),'sha256':sha(p),'size':[2048,2048],'colorspace':im.colorspace_settings.name,'statistics':stats})
        # Each completed native map is recoverable even if a later stage fails.
        links.new(original,out.inputs['Surface']); dump(family+'_checkpoint.json',records)
        bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'cache_checkpoint.blend'),relative_remap=False)
    nodes.remove(emission); nodes.remove(combine)
    return records

def main():
    start=time.monotonic(); bpy.ops.wm.read_factory_settings(use_empty=True)
    sc=bpy.context.scene; sc.render.engine='CYCLES'; sc.cycles.device='CPU'; sc.cycles.samples=8
    sc.render.threads_mode='FIXED'; sc.render.threads=2; sc.render.bake.use_selected_to_active=False; sc.render.bake.normal_space='TANGENT'
    images,deps=mats.load_images(ROOT,HERE.parent/'revision2/inputs.json',OUT)
    config=json.loads((HERE/'field_config.json').read_text(encoding='utf-8'))
    rows={}
    for family,period,mat in [('concrete',3.6,mats.concrete(images)),('soil',2.53,mats.soil(images,config))]:
        ob=tile('CACHE_ONLY_'+family,period,mat); rows[family]=cache(ob,family); ob.hide_render=True; ob.hide_set(True)
    for im in bpy.data.images:
        if im.source=='FILE': im.filepath=bpy.path.relpath(str(Path(bpy.path.abspath(im.filepath)).resolve()),start=str(OUT))
    source=OUT/'shared_periodic_materials.blend'; bpy.ops.wm.save_as_mainfile(filepath=str(source),relative_remap=False)
    bpy.ops.wm.open_mainfile(filepath=str(source))
    checked=[]
    expected={Path(r['path']).name:r['sha256'] for maps in rows.values() for r in maps}
    expected.update({Path(r['local']).name:r['sha256'] for r in deps})
    for im in bpy.data.images:
        if im.source!='FILE': continue
        p=Path(bpy.path.abspath(im.filepath)).resolve(); assert p.name in expected and sha(p)==expected[p.name]
        im.reload(); sample=list(im.pixels[:4]); assert len(sample)==4 and im.has_data and all(math.isfinite(v) for v in sample)
        checked.append({'path':str(p),'sha256':sha(p),'size':list(im.size),'pixel':sample})
    dump('result.json',{'status':'SHARED_CACHE_BAKED_NEEDS_IMAGE_SEAM_REVIEW','pid':os.getpid(),'elapsed_seconds':time.monotonic()-start,
        'source':str(source),'source_sha256':sha(source),'materials':rows,'images_reopened':checked,
        'normal_contract':'soil original NormalMap .32 baked exactly once; cached NormalMap strength=1. Concrete only periodic .5mm/.18 procedural microBump; no photographed color-as-height.',
        'roughness_contract':'concrete .88; soil .78+.16*original_rough. AO absent =>R1. Metallic0 both bases.',
        'scope':'two shared2K PBR sets only; no per-piece/whole-field atlas, local wet/hardware bake deferred until approved field preview; noGLB/runtime'})
if __name__=='__main__': main()
